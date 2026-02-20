// EffectShaders.metal
// LiquidEditor
//
// GPU compute kernels for visual effects processing.
//
// Features:
// - Separable Gaussian blur (horizontal + vertical pass)
// - Vignette effect with configurable intensity, radius, and softness
// - Film grain noise with animated time seed
// - Sharpen via unsharp mask technique
//
// Integration:
// - Designed to complement EffectPipeline.swift for GPU-accelerated paths.
// - Uniforms match EffectUniforms in SharedTypes.h.
// - Each effect is a standalone kernel that can be dispatched independently.
//
// Performance:
// - Gaussian blur uses separable convolution: O(2N) instead of O(N^2).
// - Maximum kernel radius: 64 pixels (128 taps per pass).
// - Film grain uses GPU-native noise (no texture fetch).
// - All kernels use half precision for color math.

#include <metal_stdlib>
#include "SharedTypes.h"

using namespace metal;

// MARK: - Constants

/// Maximum supported blur kernel radius in pixels.
/// Larger radii are clamped to this value. At 64 pixels, the kernel
/// samples 129 texels per pass (2*64+1), which fits within threadgroup limits.
constant int kMaxBlurRadius = 64;

// MARK: - Gaussian Blur (Separable)

/// Pre-compute Gaussian weight for a given offset and sigma.
static half gaussianWeight(int offset, half sigma) {
    half x = half(offset);
    return exp(-x * x / (2.0h * sigma * sigma));
}

/// Separable Gaussian blur - single pass (horizontal or vertical).
///
/// Call this kernel twice: once with blurDirection=0 (horizontal),
/// then with blurDirection=1 (vertical) on the intermediate result.
/// This achieves O(2*radius) instead of O(radius^2) per pixel.
///
/// The source texture should use clamp-to-edge addressing to avoid
/// black borders. Sigma is derived from blurRadius (radius = 3*sigma).
kernel void gaussianBlurKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant EffectUniforms&       uniforms [[buffer(BufferIndexEffectParams)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    uint width  = source.get_width();
    uint height = source.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    half sigma = half(uniforms.blurRadius);
    if (sigma < 0.5h) {
        // No blur: pass through
        dest.write(source.read(gid), gid);
        return;
    }

    // Kernel radius: 3 sigma covers 99.7% of the distribution
    int radius = min(int(ceil(sigma * 3.0h)), kMaxBlurRadius);
    bool horizontal = (uniforms.blurDirection == 0);

    // Accumulate weighted samples
    half4 colorSum = half4(0.0h);
    half  weightSum = 0.0h;

    for (int i = -radius; i <= radius; i++) {
        int2 samplePos;
        if (horizontal) {
            samplePos = int2(int(gid.x) + i, int(gid.y));
        } else {
            samplePos = int2(int(gid.x), int(gid.y) + i);
        }

        // Clamp to texture bounds
        samplePos.x = clamp(samplePos.x, 0, int(width) - 1);
        samplePos.y = clamp(samplePos.y, 0, int(height) - 1);

        half w = gaussianWeight(i, sigma);
        colorSum += source.read(uint2(samplePos)) * w;
        weightSum += w;
    }

    dest.write(colorSum / weightSum, gid);
}

// MARK: - Vignette Effect

/// Apply a radial vignette darkening effect.
///
/// The vignette is computed as a smooth radial falloff from the frame center.
/// Intensity controls how dark the edges become, radius controls where the
/// falloff begins, and softness controls the transition width.
///
/// Matches the behavior of CIVignetteEffect in CoreImage.
kernel void vignetteKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant EffectUniforms&       uniforms [[buffer(BufferIndexEffectParams)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    uint width  = source.get_width();
    uint height = source.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    half4 srcColor = source.read(gid);

    // Normalized coordinates centered at (0.5, 0.5)
    half2 uv = half2(float2(gid) / float2(width, height));
    half2 center = half2(0.5h, 0.5h);

    // Compute distance from center, accounting for aspect ratio
    half aspect = half(width) / half(height);
    half2 diff = (uv - center) * half2(aspect, 1.0h);
    half dist = length(diff);

    // Vignette parameters
    half intensity = half(uniforms.vignetteIntensity);
    half radius    = half(uniforms.vignetteRadius);
    half softness  = half(uniforms.vignetteSoftness);

    // Smooth falloff: 1.0 at center, darkens toward edges
    half vignette = 1.0h - smoothstep(radius, radius + softness, dist) * intensity;
    vignette = clamp(vignette, 0.0h, 1.0h);

    dest.write(half4(srcColor.rgb * vignette, srcColor.a), gid);
}

// MARK: - Film Grain Noise

/// Hash function for pseudo-random noise generation.
///
/// Uses a fast integer hash suitable for GPU noise that produces
/// well-distributed values. No texture lookups required.
static half hash12(half2 p) {
    half3 p3 = fract(half3(p.x, p.y, p.x) * 0.1031h);
    p3 += dot(p3, half3(p3.y, p3.z, p3.x) + 33.33h);
    return fract((p3.x + p3.y) * p3.z);
}

/// Apply animated film grain noise.
///
/// Generates pseudo-random luminance noise that varies per frame
/// (via grainTime). The noise is additive and centered around 0
/// to avoid shifting the overall brightness.
///
/// Matches the behavior of the CIRandomGenerator + CIAdditionCompositing
/// approach used in EffectPipeline.swift.
kernel void filmGrainKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant EffectUniforms&       uniforms [[buffer(BufferIndexEffectParams)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    uint width  = source.get_width();
    uint height = source.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    half4 srcColor = source.read(gid);

    half intensity = half(uniforms.grainIntensity);
    half grainSize = half(uniforms.grainSize);
    half timeSeed  = half(uniforms.grainTime);

    // Scale coordinates by grain size (larger grainSize = coarser grain)
    half2 scaledPos = half2(float2(gid) / max(grainSize, 0.5h));

    // Generate noise using hash with time variation
    half noise = hash12(scaledPos + half2(timeSeed * 12.345h, timeSeed * 67.89h));

    // Center noise around 0 (-0.5 to 0.5) and apply intensity
    half grainValue = (noise - 0.5h) * intensity;

    // Add noise to color (preserving alpha)
    half3 grainedColor = srcColor.rgb + grainValue;
    grainedColor = clamp(grainedColor, half3(0.0h), half3(1.0h));

    dest.write(half4(grainedColor, srcColor.a), gid);
}

// MARK: - Sharpen (Unsharp Mask)

/// Apply unsharp mask sharpening.
///
/// Sharpening is computed as:
///   sharp = original + amount * (original - blurred)
///
/// The blur is approximated with a small 3x3 or 5x5 box kernel
/// weighted by a Gaussian for the given radius. This avoids needing
/// a separate blur pass for small radii.
///
/// For larger radii, use the Gaussian blur kernel first and pass the
/// blurred result as a separate texture. This kernel handles the
/// common case of small-radius sharpening (radius <= 5).
kernel void sharpenKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant EffectUniforms&       uniforms [[buffer(BufferIndexEffectParams)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    uint width  = source.get_width();
    uint height = source.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    half4 srcColor = source.read(gid);
    half amount    = half(uniforms.sharpenAmount);
    half radius    = half(uniforms.sharpenRadius);
    half threshold = half(uniforms.sharpenThreshold);

    if (amount < 0.001h) {
        dest.write(srcColor, gid);
        return;
    }

    // Compute local average (Gaussian-weighted neighborhood)
    int kernelRadius = clamp(int(ceil(radius)), 1, 5);
    half sigma = max(radius, 0.5h);

    half4 blurredSum = half4(0.0h);
    half  weightSum  = 0.0h;

    for (int dy = -kernelRadius; dy <= kernelRadius; dy++) {
        for (int dx = -kernelRadius; dx <= kernelRadius; dx++) {
            int2 samplePos = int2(gid) + int2(dx, dy);
            samplePos.x = clamp(samplePos.x, 0, int(width) - 1);
            samplePos.y = clamp(samplePos.y, 0, int(height) - 1);

            half dist = half(dx * dx + dy * dy);
            half w = exp(-dist / (2.0h * sigma * sigma));

            blurredSum += source.read(uint2(samplePos)) * w;
            weightSum += w;
        }
    }

    half4 blurred = blurredSum / weightSum;

    // Compute the detail (high-frequency) component
    half4 detail = srcColor - blurred;

    // Threshold: only sharpen edges above the threshold
    // This prevents sharpening noise in flat areas
    half detailLum = abs(dot(detail.rgb, half3(0.2126h, 0.7152h, 0.0722h)));
    half mask = smoothstep(threshold * 0.5h, threshold, detailLum);

    // Apply sharpening
    half4 sharpened = srcColor + detail * amount * mask;
    sharpened.rgb = clamp(sharpened.rgb, half3(0.0h), half3(1.0h));
    sharpened.a = srcColor.a;

    dest.write(sharpened, gid);
}

// MARK: - Combined Blur + Sharpen Kernel

/// Two-pass unsharp mask using a pre-blurred texture.
///
/// For larger blur radii, the Gaussian blur kernel should be run first
/// (horizontal + vertical) to produce the blurred texture. This kernel
/// then computes the sharpening from the original and blurred pair.
kernel void unsharpMaskKernel(
    texture2d<half, access::read>  original [[texture(TextureIndexSource)]],
    texture2d<half, access::read>  blurred  [[texture(TextureIndexBackground)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant EffectUniforms&       uniforms [[buffer(BufferIndexEffectParams)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    uint width  = original.get_width();
    uint height = original.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    half4 origColor = original.read(gid);
    half4 blurColor = blurred.read(gid);
    half  amount    = half(uniforms.sharpenAmount);
    half  threshold = half(uniforms.sharpenThreshold);

    // Detail = original - blurred
    half4 detail = origColor - blurColor;

    // Threshold mask
    half detailLum = abs(dot(detail.rgb, half3(0.2126h, 0.7152h, 0.0722h)));
    half mask = smoothstep(threshold * 0.5h, threshold, detailLum);

    // Apply
    half4 sharpened = origColor + detail * amount * mask;
    sharpened.rgb = clamp(sharpened.rgb, half3(0.0h), half3(1.0h));
    sharpened.a = origColor.a;

    dest.write(sharpened, gid);
}
