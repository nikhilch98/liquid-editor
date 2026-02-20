// CompositorShaders.metal
// LiquidEditor
//
// Multi-track video compositing shaders for the GPU rendering pipeline.
//
// Features:
// - Vertex/fragment shaders for textured quad rendering with transforms
// - 17+ blend mode kernels matching CompBlendMode.swift
// - Alpha compositing with per-layer opacity
// - Spatial transforms (translate, scale, rotate) via model-view-projection matrix
//
// Integration:
// - Used by MultiTrackCompositor for GPU-accelerated layer compositing.
// - Uniforms correspond to CompositorUniforms in SharedTypes.h.
// - Texture binding: source (0), background (1), destination (2).

#include <metal_stdlib>
#include "SharedTypes.h"

using namespace metal;

// MARK: - Vertex Shader

/// Vertex output for textured quad rendering.
struct CompositorVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

/// Transform a textured quad vertex by the model-view-projection matrix.
///
/// Input vertices define a quad in clip space. The transform matrix handles
/// translation, scale, and rotation for layer positioning (PiP, freeform, etc.).
vertex CompositorVertexOut compositorVertex(
    const device CompositorVertex* vertices [[buffer(BufferIndexVertices)]],
    constant CompositorUniforms&   uniforms [[buffer(BufferIndexUniforms)]],
    uint                           vid      [[vertex_id]]
) {
    CompositorVertexOut out;
    out.position = uniforms.transform * vertices[vid].position;
    out.texCoord = vertices[vid].texCoord;
    return out;
}

// MARK: - Blend Mode Helpers

/// Convert RGB to HSL for component blend modes.
static float3 rgbToHsl(float3 c) {
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float l = (maxC + minC) * 0.5;

    if (maxC == minC) {
        return float3(0.0, 0.0, l);
    }

    float d = maxC - minC;
    float s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC);

    float h;
    if (maxC == c.r) {
        h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    } else if (maxC == c.g) {
        h = (c.b - c.r) / d + 2.0;
    } else {
        h = (c.r - c.g) / d + 4.0;
    }
    h /= 6.0;

    return float3(h, s, l);
}

/// Helper for HSL to RGB conversion.
static float hueToRgb(float p, float q, float t) {
    float tt = t;
    if (tt < 0.0) tt += 1.0;
    if (tt > 1.0) tt -= 1.0;
    if (tt < 1.0 / 6.0) return p + (q - p) * 6.0 * tt;
    if (tt < 0.5)        return q;
    if (tt < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - tt) * 6.0;
    return p;
}

/// Convert HSL to RGB.
static float3 hslToRgb(float3 hsl) {
    if (hsl.y == 0.0) {
        return float3(hsl.z);
    }
    float q = hsl.z < 0.5 ? hsl.z * (1.0 + hsl.y) : hsl.z + hsl.y - hsl.z * hsl.y;
    float p = 2.0 * hsl.z - q;
    return float3(
        hueToRgb(p, q, hsl.x + 1.0 / 3.0),
        hueToRgb(p, q, hsl.x),
        hueToRgb(p, q, hsl.x - 1.0 / 3.0)
    );
}

/// Compute luminance from linear RGB using Rec. 709 coefficients.
static float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

/// Apply the specified blend mode to source and destination colors.
///
/// Both src and dst are expected in premultiplied alpha format.
/// Returns the blended color in premultiplied alpha.
static half4 applyBlendMode(half4 src, half4 dst, uint mode) {
    // Un-premultiply for blend math (avoid division by zero)
    float3 s = src.a > 0.001h ? float3(src.rgb / src.a) : float3(0.0);
    float3 d = dst.a > 0.001h ? float3(dst.rgb / dst.a) : float3(0.0);
    float3 result;

    switch (mode) {
        case BlendModeNormal:
            // Source-over compositing handled externally
            result = s;
            break;

        case BlendModeMultiply:
            result = s * d;
            break;

        case BlendModeScreen:
            result = s + d - s * d;
            break;

        case BlendModeOverlay:
            // Overlay = Screen if dst > 0.5, Multiply otherwise
            result = mix(
                2.0 * s * d,
                1.0 - 2.0 * (1.0 - s) * (1.0 - d),
                step(float3(0.5), d)
            );
            break;

        case BlendModeSoftLight:
            // W3C soft light formula
            result = mix(
                d - (1.0 - 2.0 * s) * d * (1.0 - d),
                d + (2.0 * s - 1.0) * (sqrt(d) - d),
                step(float3(0.5), s)
            );
            break;

        case BlendModeHardLight:
            // Hard light = Overlay with layers swapped
            result = mix(
                2.0 * s * d,
                1.0 - 2.0 * (1.0 - s) * (1.0 - d),
                step(float3(0.5), s)
            );
            break;

        case BlendModeColorDodge:
            result = float3(
                s.r >= 1.0 ? 1.0 : min(1.0, d.r / max(1.0 - s.r, 0.001)),
                s.g >= 1.0 ? 1.0 : min(1.0, d.g / max(1.0 - s.g, 0.001)),
                s.b >= 1.0 ? 1.0 : min(1.0, d.b / max(1.0 - s.b, 0.001))
            );
            break;

        case BlendModeColorBurn:
            result = float3(
                s.r <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - d.r) / max(s.r, 0.001)),
                s.g <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - d.g) / max(s.g, 0.001)),
                s.b <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - d.b) / max(s.b, 0.001))
            );
            break;

        case BlendModeDarken:
            result = min(s, d);
            break;

        case BlendModeLighten:
            result = max(s, d);
            break;

        case BlendModeDifference:
            result = abs(s - d);
            break;

        case BlendModeExclusion:
            result = s + d - 2.0 * s * d;
            break;

        case BlendModeAdd:
            result = min(s + d, float3(1.0));
            break;

        case BlendModeSubtract:
            result = max(d - s, float3(0.0));
            break;

        case BlendModeLuminosity: {
            float3 dHsl = rgbToHsl(d);
            float  sLum = luminance(s);
            result = hslToRgb(float3(dHsl.x, dHsl.y, sLum));
            break;
        }

        case BlendModeHue: {
            float3 sHsl = rgbToHsl(s);
            float3 dHsl = rgbToHsl(d);
            result = hslToRgb(float3(sHsl.x, dHsl.y, dHsl.z));
            break;
        }

        case BlendModeSaturation: {
            float3 sHsl = rgbToHsl(s);
            float3 dHsl = rgbToHsl(d);
            result = hslToRgb(float3(dHsl.x, sHsl.y, dHsl.z));
            break;
        }

        case BlendModeColor: {
            float3 sHsl = rgbToHsl(s);
            float3 dHsl = rgbToHsl(d);
            result = hslToRgb(float3(sHsl.x, sHsl.y, dHsl.z));
            break;
        }

        default:
            result = s;
            break;
    }

    // Porter-Duff source-over compositing with blended result
    float outA = float(src.a) + float(dst.a) * (1.0 - float(src.a));
    float3 outRgb;
    if (outA > 0.001) {
        outRgb = (result * float(src.a) + float3(dst.rgb) * (1.0 - float(src.a))) / outA;
    } else {
        outRgb = float3(0.0);
    }

    return half4(half3(outRgb * outA), half(outA));
}

// MARK: - Fragment Shader

/// Sample a textured quad and apply blend mode compositing.
///
/// Reads the foreground layer from the source texture, applies opacity,
/// reads the current composite from the background texture, and blends
/// them using the specified blend mode.
fragment half4 compositorFragment(
    CompositorVertexOut          in       [[stage_in]],
    texture2d<half>              source   [[texture(TextureIndexSource)]],
    texture2d<half>              bg       [[texture(TextureIndexBackground)]],
    constant CompositorUniforms& uniforms [[buffer(BufferIndexUniforms)]]
) {
    constexpr sampler texSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_zero
    );

    half4 srcColor = source.sample(texSampler, in.texCoord);
    half4 bgColor  = bg.sample(texSampler, in.texCoord);

    // Apply per-layer opacity
    srcColor *= half(uniforms.opacity);

    // Apply blend mode
    return applyBlendMode(srcColor, bgColor, uniforms.blendMode);
}

// MARK: - Compute Kernel: Blend Composite

/// Compute kernel for blend-mode compositing of two full-frame textures.
///
/// This is an alternative to the render pipeline approach, useful when
/// both source and background are already rendered to textures and we
/// need a single-pass composite without geometry.
///
/// Threadgroup size: 16x16 (256 threads per group).
kernel void compositorBlendKernel(
    texture2d<half, access::read>  source   [[texture(TextureIndexSource)]],
    texture2d<half, access::read>  bg       [[texture(TextureIndexBackground)]],
    texture2d<half, access::write> dest     [[texture(TextureIndexDestination)]],
    constant CompositorUniforms&   uniforms [[buffer(BufferIndexUniforms)]],
    uint2                          gid      [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) {
        return;
    }

    half4 srcColor = source.read(gid);
    half4 bgColor  = bg.read(gid);

    // Apply per-layer opacity
    srcColor *= half(uniforms.opacity);

    // Apply blend mode
    half4 result = applyBlendMode(srcColor, bgColor, uniforms.blendMode);

    dest.write(result, gid);
}
