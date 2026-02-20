// ColorGradingShaders.metal
// LiquidEditor
//
// GPU compute kernels for real-time color grading.
//
// Features:
// - 3D LUT application (33x33x33 or 64x64x64 cube with trilinear interpolation)
// - Exposure, contrast, saturation, brightness, temperature, tint adjustments
// - Lift/gamma/gain color wheels for shadow/midtone/highlight control
// - Highlights/shadows color shift with luminance-based masking
//
// Integration:
// - Designed to complement ColorGradingPipeline.swift for GPU-accelerated paths.
// - Uniforms match ColorGradingUniforms in SharedTypes.h.
// - Can be used as a single-pass alternative to the CIFilter chain when
//   the full pipeline is applied (avoids N intermediate texture copies).
//
// Performance:
// - All math in half precision where safe (color range [0, 1]).
// - Single-pass kernel avoids intermediate texture allocation.
// - 3D LUT uses trilinear interpolation via hardware texture sampler.

#include <metal_stdlib>
#include "SharedTypes.h"

using namespace metal;

// MARK: - Color Space Helpers

/// Compute luminance using Rec. 709 coefficients.
static half luminance709(half3 c) {
    return dot(c, half3(0.2126h, 0.7152h, 0.0722h));
}

/// Apply ASC CDL-style lift/gamma/gain.
///
/// Standard color grading formula used in DaVinci Resolve, Nuke, etc.:
///   output = (gain * (input + lift * (1 - input)))^(1/gamma)
///
/// - Parameters:
///   - input: Linear RGB color [0, 1]
///   - lift: Shadow level offset per channel
///   - gamma: Midtone power curve per channel (1.0 = neutral)
///   - gain: Highlight multiplier per channel (1.0 = neutral)
/// - Returns: Graded color [0, 1]
static half3 applyLiftGammaGain(half3 input, half3 lift, half3 gamma, half3 gain) {
    // Lift: offsets the shadows
    half3 lifted = gain * (input + lift * (1.0h - input));
    lifted = max(lifted, half3(0.0h));

    // Gamma: adjust midtones via power curve
    // Invert gamma so values > 1 brighten (matching DaVinci convention)
    half3 invGamma = 1.0h / max(gamma, half3(0.01h));
    return pow(lifted, invGamma);
}

/// Apply white balance adjustment by shifting color temperature.
///
/// Approximates CITemperatureAndTint behavior:
/// - temperature > 0 = warmer (shift toward yellow/red)
/// - temperature < 0 = cooler (shift toward blue)
/// - tint > 0 = more magenta
/// - tint < 0 = more green
static half3 applyWhiteBalance(half3 color, half temp, half tint) {
    // Temperature: warm/cool shift on blue-yellow axis
    half3 result = color;
    result.r += temp * 0.1h;
    result.b -= temp * 0.1h;

    // Tint: green-magenta shift
    result.g -= tint * 0.05h;
    result.r += tint * 0.025h;
    result.b += tint * 0.025h;

    return result;
}

// MARK: - 3D LUT Application

/// Apply a 3D LUT to a color using trilinear interpolation.
///
/// The LUT is stored as a 3D texture (dimension x dimension x dimension).
/// Trilinear interpolation is performed by the hardware sampler.
///
/// - Parameters:
///   - color: Input linear RGB [0, 1]
///   - lut: 3D texture containing the LUT
///   - intensity: Blend factor [0, 1] (0 = original, 1 = full LUT)
/// - Returns: LUT-graded color
static half3 applyLUT3D(half3 color, texture3d<half> lut, half intensity) {
    constexpr sampler lutSampler(
        filter::linear,
        address::clamp_to_edge
    );

    // Sample the 3D LUT with the input color as coordinates
    half3 lutColor = lut.sample(lutSampler, float3(color)).rgb;

    // Blend between original and LUT result
    return mix(color, lutColor, intensity);
}

// MARK: - Function Constants

/// Function constant controlling LUT availability.
/// Set to true when a LUT texture is bound; false otherwise.
constant bool hasLUT [[function_constant(0)]];

// MARK: - Full Color Grading Kernel

/// Single-pass color grading compute kernel.
///
/// Applies all color grading stages in professional order:
/// 1. Exposure
/// 2. White Balance (Temperature + Tint)
/// 3. Contrast + Brightness + Saturation
/// 4. Lift / Gamma / Gain
/// 5. Highlight / Shadow color shift
/// 6. 3D LUT (if bound)
///
/// This is a GPU-accelerated alternative to the CIFilter chain in
/// ColorGradingPipeline.swift. Use when applying multiple adjustments
/// simultaneously to avoid intermediate texture copies.
kernel void colorGradingKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    texture3d<half, access::sample> lut     [[texture(TextureIndexLUT), function_constant(hasLUT)]],
    constant ColorGradingUniforms& uniforms [[buffer(BufferIndexColorGrading)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) {
        return;
    }

    half4 srcColor = source.read(gid);
    half3 color = srcColor.rgb;
    half  alpha = srcColor.a;

    // Un-premultiply for grading
    if (alpha > 0.001h && alpha < 0.999h) {
        color /= alpha;
    }

    // Stage 1: Exposure (EV offset, applied as power-of-2 multiplier)
    if (abs(uniforms.exposure) > 0.0001) {
        color *= half(exp2(uniforms.exposure));
    }

    // Stage 2: White Balance
    if (abs(uniforms.temperature) > 0.0001 || abs(uniforms.tint) > 0.0001) {
        color = applyWhiteBalance(color, half(uniforms.temperature), half(uniforms.tint));
    }

    // Stage 3: Contrast + Brightness + Saturation
    {
        // Brightness
        if (abs(uniforms.brightness) > 0.0001) {
            color += half(uniforms.brightness);
        }

        // Contrast (pivot at 0.5)
        if (abs(uniforms.contrast - 1.0) > 0.0001) {
            color = (color - 0.5h) * half(uniforms.contrast) + 0.5h;
        }

        // Saturation
        if (abs(uniforms.saturation - 1.0) > 0.0001) {
            half lum = luminance709(color);
            color = mix(half3(lum), color, half(uniforms.saturation));
        }
    }

    // Stage 4: Lift / Gamma / Gain
    {
        half3 lift  = half3(uniforms.lift.x,  uniforms.lift.y,  uniforms.lift.z);
        half3 gamma = half3(uniforms.gamma.x, uniforms.gamma.y, uniforms.gamma.z);
        half3 gain  = half3(uniforms.gain.x,  uniforms.gain.y,  uniforms.gain.z);

        // Only apply if any channel deviates from identity
        bool liftActive  = any(abs(lift)      > half3(0.001h));
        bool gammaActive = any(abs(gamma - 1.0h) > half3(0.001h));
        bool gainActive  = any(abs(gain  - 1.0h) > half3(0.001h));

        if (liftActive || gammaActive || gainActive) {
            color = applyLiftGammaGain(color, lift, gamma, gain);
        }
    }

    // Stage 5: Highlight / Shadow color shift
    {
        half lum = luminance709(color);

        // Shadow tint (applied more strongly to dark areas)
        half4 shadowTint = half4(uniforms.shadowColor);
        if (shadowTint.a > 0.001h) {
            half shadowMask = 1.0h - smoothstep(0.0h, 0.5h, lum);
            color += shadowTint.rgb * shadowTint.a * shadowMask * 0.2h;
        }

        // Highlight tint (applied more strongly to bright areas)
        half4 highlightTint = half4(uniforms.highlightColor);
        if (highlightTint.a > 0.001h) {
            half highlightMask = smoothstep(0.5h, 1.0h, lum);
            color += highlightTint.rgb * highlightTint.a * highlightMask * 0.2h;
        }
    }

    // Stage 6: 3D LUT (if available)
    if (hasLUT && uniforms.lutIntensity > 0.001) {
        color = applyLUT3D(color, lut, half(uniforms.lutIntensity));
    }

    // Clamp and re-premultiply
    color = clamp(color, half3(0.0h), half3(1.0h));
    dest.write(half4(color * alpha, alpha), gid);
}

// MARK: - Standalone LUT Application

/// Compute kernel for applying only a 3D LUT to a texture.
///
/// Useful for LUT preview thumbnails or when only the LUT stage
/// is needed without the full grading pipeline.
kernel void lutApplyKernel(
    texture2d<half, access::read>   source    [[texture(TextureIndexSource)]],
    texture2d<half, access::write>  dest      [[texture(TextureIndexDestination)]],
    texture3d<half, access::sample> lut       [[texture(TextureIndexLUT)]],
    constant ColorGradingUniforms&  uniforms  [[buffer(BufferIndexColorGrading)]],
    uint2                           gid       [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) {
        return;
    }

    half4 srcColor = source.read(gid);
    half3 color = srcColor.rgb;
    half  alpha = srcColor.a;

    // Un-premultiply
    if (alpha > 0.001h && alpha < 0.999h) {
        color /= alpha;
    }

    constexpr sampler lutSampler(filter::linear, address::clamp_to_edge);
    half3 lutColor = lut.sample(lutSampler, float3(color)).rgb;

    // Blend with original based on intensity
    half intensity = half(uniforms.lutIntensity);
    color = mix(color, lutColor, intensity);

    color = clamp(color, half3(0.0h), half3(1.0h));
    dest.write(half4(color * alpha, alpha), gid);
}

// MARK: - Exposure Only Kernel

/// Fast single-adjustment kernel for exposure preview.
///
/// Used for real-time exposure slider feedback where the full pipeline
/// would be wasteful.
kernel void exposureKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant float&                ev       [[buffer(BufferIndexColorGrading)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) {
        return;
    }

    half4 srcColor = source.read(gid);
    half multiplier = half(exp2(ev));
    half3 color = clamp(srcColor.rgb * multiplier, half3(0.0h), half3(1.0h));
    dest.write(half4(color, srcColor.a), gid);
}
