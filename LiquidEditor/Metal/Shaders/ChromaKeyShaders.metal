// ChromaKeyShaders.metal
// LiquidEditor
//
// GPU compute kernels for chroma key (green/blue screen) processing.
//
// Features:
// - YCbCr-based chroma key extraction for perceptually accurate keying
// - Adjustable tolerance and softness for fine-tuning the matte
// - Spill suppression to remove color bleed on foreground edges
// - Edge feathering via distance-based alpha smoothing
//
// Integration:
// - Designed to work with ChromaKeyFilter.swift and MultiTrackCompositor.
// - Uniforms match ChromaKeyUniforms in SharedTypes.h.
// - Input: BGRA texture (TextureIndexSource).
// - Output: BGRA texture with alpha channel set by chroma key matte.
//
// Performance:
// - Uses half precision for color math where possible.
// - Single-pass compute kernel; no intermediate buffers.
// - Threadgroup: 16x16 = 256 threads.

#include <metal_stdlib>
#include "SharedTypes.h"

using namespace metal;

// MARK: - Color Space Conversion

/// Convert RGB to YCbCr (BT.601 standard).
///
/// Y  = luminance [0, 1]
/// Cb = blue-difference chroma [-0.5, 0.5]
/// Cr = red-difference chroma [-0.5, 0.5]
static half3 rgbToYCbCr(half3 rgb) {
    half y  = 0.299h * rgb.r + 0.587h * rgb.g + 0.114h * rgb.b;
    half cb = (rgb.b - y) * 0.564h;
    half cr = (rgb.r - y) * 0.713h;
    return half3(y, cb, cr);
}

// MARK: - Chroma Key Compute Kernel

/// Main chroma key extraction kernel.
///
/// For each pixel:
/// 1. Convert RGB to YCbCr.
/// 2. Compute chroma distance from target color in CbCr plane.
/// 3. Generate soft matte from distance, tolerance, and softness.
/// 4. Apply edge feathering.
/// 5. Suppress color spill on partially-keyed pixels.
/// 6. Output premultiplied RGBA with computed alpha.
kernel void chromaKeyKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant ChromaKeyUniforms&    uniforms [[buffer(BufferIndexChromaKey)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) {
        return;
    }

    half4 srcColor = source.read(gid);
    half3 rgb = srcColor.rgb;

    // Un-premultiply if source has alpha
    if (srcColor.a > 0.001h && srcColor.a < 0.999h) {
        rgb /= srcColor.a;
    }

    // Convert to YCbCr
    half3 ycbcr = rgbToYCbCr(rgb);

    // Determine target CbCr based on color type
    half2 targetCbCr;
    if (uniforms.targetColorType == 0) {
        // Green screen
        targetCbCr = half2(-0.3316h, -0.4186h); // pre-computed for pure green
    } else if (uniforms.targetColorType == 1) {
        // Blue screen
        targetCbCr = half2(0.5h, -0.0813h);     // pre-computed for pure blue
    } else {
        // Custom color from uniforms
        targetCbCr = half2(uniforms.targetColorYCbCr.y, uniforms.targetColorYCbCr.z);
    }

    // Compute chroma distance in CbCr plane (ignoring luminance)
    half2 chromaDelta = half2(ycbcr.y, ycbcr.z) - targetCbCr;
    half chromaDist = length(chromaDelta);

    // Generate matte from distance
    half tolerance = half(uniforms.tolerance);
    half softness  = half(uniforms.softness);

    half alpha;
    if (chromaDist < tolerance) {
        // Inside hard key region: fully transparent
        alpha = 0.0h;
    } else if (chromaDist < tolerance + softness) {
        // Soft edge region: smooth falloff
        alpha = smoothstep(tolerance, tolerance + softness, chromaDist);
    } else {
        // Outside key region: fully opaque
        alpha = 1.0h;
    }

    // Edge feathering: sample neighbors for smoother edges
    half feather = half(uniforms.edgeFeather);
    if (feather > 0.5h && alpha > 0.01h && alpha < 0.99h) {
        // Sample 4 neighbors to smooth the matte edge
        half alphaSum = alpha;
        uint sampleCount = 1;

        int2 offsets[4] = { int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1) };
        for (int i = 0; i < 4; i++) {
            int2 neighborPos = int2(gid) + offsets[i] * int2(feather);
            if (neighborPos.x >= 0 && neighborPos.x < int(source.get_width()) &&
                neighborPos.y >= 0 && neighborPos.y < int(source.get_height())) {
                half4 nColor = source.read(uint2(neighborPos));
                half3 nRgb = nColor.a > 0.001h ? nColor.rgb / nColor.a : half3(0.0h);
                half3 nYcbcr = rgbToYCbCr(nRgb);
                half2 nDelta = half2(nYcbcr.y, nYcbcr.z) - targetCbCr;
                half nDist = length(nDelta);
                half nAlpha;
                if (nDist < tolerance) {
                    nAlpha = 0.0h;
                } else if (nDist < tolerance + softness) {
                    nAlpha = smoothstep(tolerance, tolerance + softness, nDist);
                } else {
                    nAlpha = 1.0h;
                }
                alphaSum += nAlpha;
                sampleCount += 1;
            }
        }
        alpha = alphaSum / half(sampleCount);
    }

    // Spill suppression: remove color bleed from the screen color
    half spillStrength = half(uniforms.spillSuppression);
    half3 outRgb = rgb;

    if (spillStrength > 0.01h && alpha > 0.01h) {
        if (uniforms.targetColorType == 0) {
            // Green spill: reduce green channel excess
            half greenExcess = rgb.g - max(rgb.r, rgb.b);
            if (greenExcess > 0.0h) {
                half suppression = min(greenExcess * spillStrength, greenExcess);
                outRgb.g -= suppression;
                // Redistribute to maintain luminance
                outRgb.r += suppression * 0.5h;
                outRgb.b += suppression * 0.5h;
            }
        } else if (uniforms.targetColorType == 1) {
            // Blue spill: reduce blue channel excess
            half blueExcess = rgb.b - max(rgb.r, rgb.g);
            if (blueExcess > 0.0h) {
                half suppression = min(blueExcess * spillStrength, blueExcess);
                outRgb.b -= suppression;
                outRgb.r += suppression * 0.5h;
                outRgb.g += suppression * 0.5h;
            }
        }
    }

    // Clamp and output as premultiplied alpha
    outRgb = clamp(outRgb, half3(0.0h), half3(1.0h));
    half finalAlpha = alpha * srcColor.a;
    dest.write(half4(outRgb * finalAlpha, finalAlpha), gid);
}

// MARK: - Chroma Key with Mask

/// Chroma key extraction with an external matte mask.
///
/// Combines the computed chroma key matte with an external mask texture.
/// Useful for refining automated keying with user-painted mask corrections.
kernel void chromaKeyWithMaskKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::read>  mask     [[texture(TextureIndexMask)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant ChromaKeyUniforms&    uniforms [[buffer(BufferIndexChromaKey)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) {
        return;
    }

    half4 srcColor = source.read(gid);
    half3 rgb = srcColor.rgb;

    if (srcColor.a > 0.001h && srcColor.a < 0.999h) {
        rgb /= srcColor.a;
    }

    half3 ycbcr = rgbToYCbCr(rgb);

    half2 targetCbCr;
    if (uniforms.targetColorType == 0) {
        targetCbCr = half2(-0.3316h, -0.4186h);
    } else if (uniforms.targetColorType == 1) {
        targetCbCr = half2(0.5h, -0.0813h);
    } else {
        targetCbCr = half2(uniforms.targetColorYCbCr.y, uniforms.targetColorYCbCr.z);
    }

    half2 chromaDelta = half2(ycbcr.y, ycbcr.z) - targetCbCr;
    half chromaDist = length(chromaDelta);

    half tolerance = half(uniforms.tolerance);
    half softness  = half(uniforms.softness);

    half chromaAlpha;
    if (chromaDist < tolerance) {
        chromaAlpha = 0.0h;
    } else if (chromaDist < tolerance + softness) {
        chromaAlpha = smoothstep(tolerance, tolerance + softness, chromaDist);
    } else {
        chromaAlpha = 1.0h;
    }

    // Read external mask (r channel = mask value, 1 = keep, 0 = remove)
    half maskValue = mask.read(gid).r;

    // Combine: use minimum of chroma matte and external mask
    half alpha = min(chromaAlpha, maskValue) * srcColor.a;

    half3 outRgb = clamp(rgb, half3(0.0h), half3(1.0h));
    dest.write(half4(outRgb * alpha, alpha), gid);
}
