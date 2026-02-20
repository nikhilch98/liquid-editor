// SharedTypes.h
// LiquidEditor
//
// Shared type definitions between Metal shaders and Swift host code.
// This header is included by .metal files and can be imported in Swift
// via a bridging header if needed.
//
// Convention:
// - All buffer structs are 16-byte aligned for Metal compatibility.
// - Color values use float4 (RGBA, linear, premultiplied alpha where noted).
// - Coordinate systems follow Metal NDC: [-1, 1] for vertex, [0, 1] for UV.

#ifndef SharedTypes_h
#define SharedTypes_h

#ifdef __METAL_VERSION__
// Metal context: types come from metal_stdlib (included by .metal files)
#include <metal_stdlib>
using namespace metal;
#else
// Swift / C context: use SIMD types
#include <simd/simd.h>
typedef simd_float2   float2;
typedef simd_float3   float3;
typedef simd_float4   float4;
typedef simd_float4x4 float4x4;
typedef unsigned int  uint;
#endif

// MARK: - Buffer Indices

/// Buffer binding indices for vertex/fragment/compute shaders.
enum BufferIndex {
    BufferIndexVertices       = 0,
    BufferIndexUniforms       = 1,
    BufferIndexBlendParams    = 2,
    BufferIndexColorGrading   = 3,
    BufferIndexEffectParams   = 4,
    BufferIndexChromaKey      = 5,
};

/// Texture binding indices.
enum TextureIndex {
    TextureIndexSource        = 0,
    TextureIndexBackground    = 1,
    TextureIndexDestination   = 2,
    TextureIndexLUT           = 3,
    TextureIndexMask          = 4,
};

// MARK: - Blend Modes

/// Blend mode enumeration matching CompBlendMode in Swift.
/// Values correspond to the order in CompBlendMode.swift.
enum BlendMode {
    BlendModeNormal       = 0,
    BlendModeMultiply     = 1,
    BlendModeScreen       = 2,
    BlendModeOverlay      = 3,
    BlendModeSoftLight    = 4,
    BlendModeHardLight    = 5,
    BlendModeColorDodge   = 6,
    BlendModeColorBurn    = 7,
    BlendModeDarken       = 8,
    BlendModeLighten      = 9,
    BlendModeDifference   = 10,
    BlendModeExclusion    = 11,
    BlendModeAdd          = 12,
    BlendModeLuminosity   = 13,
    BlendModeHue          = 14,
    BlendModeSaturation   = 15,
    BlendModeColor        = 16,
    BlendModeSubtract     = 17,
};

// MARK: - Vertex Types

/// Vertex for textured quad rendering.
/// Position in clip space, UV in [0,1] texture coordinates.
struct CompositorVertex {
    float4 position;   // clip-space position (x, y, z, w)
    float2 texCoord;   // texture coordinate (u, v)
};

// MARK: - Compositor Uniforms

/// Per-layer uniforms for the compositor vertex/fragment shaders.
struct CompositorUniforms {
    float4x4 transform;          // model-view-projection matrix
    float    opacity;             // layer opacity [0, 1]
    uint     blendMode;           // BlendMode enum value
    float    _padding0;
    float    _padding1;
};

// MARK: - Chroma Key Uniforms

/// Uniforms for the chroma key compute kernel.
struct ChromaKeyUniforms {
    float3  targetColorYCbCr;     // target color in YCbCr space
    float   tolerance;            // color distance threshold [0, 1]
    float   softness;             // edge softness / feather width [0, 1]
    float   spillSuppression;     // spill removal strength [0, 1]
    float   edgeFeather;          // edge feathering radius in pixels
    uint    targetColorType;      // 0=green, 1=blue, 2=custom
};

// MARK: - Color Grading Uniforms

/// Uniforms for the color grading compute kernel.
struct ColorGradingUniforms {
    // Basic adjustments
    float exposure;           // EV offset [-4, 4]
    float contrast;           // contrast multiplier [0.25, 4.0] (1.0 = neutral)
    float brightness;         // brightness offset [-1, 1]
    float saturation;         // saturation multiplier [0, 4] (1.0 = neutral)

    // White balance
    float temperature;        // kelvin offset mapped to [-1, 1]
    float tint;               // green-magenta shift [-1, 1]
    float _wbPad0;
    float _wbPad1;

    // Lift / Gamma / Gain (color wheels)
    float4 lift;              // shadows color + level (rgb = color, a = level)
    float4 gamma;             // midtones color + level
    float4 gain;              // highlights color + level

    // Highlight / Shadow color shift
    float4 highlightColor;    // tint applied to highlights (rgb = color, a = strength)
    float4 shadowColor;       // tint applied to shadows (rgb = color, a = strength)

    // LUT parameters
    float lutIntensity;       // LUT blend strength [0, 1]
    uint  lutDimension;       // LUT cube dimension (e.g., 33, 64)
    float _lutPad0;
    float _lutPad1;
};

// MARK: - Effect Uniforms

/// Uniforms for visual effect compute kernels.
struct EffectUniforms {
    // Gaussian blur
    float blurRadius;         // blur sigma in pixels
    uint  blurDirection;      // 0 = horizontal, 1 = vertical
    float _blurPad0;
    float _blurPad1;

    // Vignette
    float vignetteIntensity;  // vignette strength [0, 2]
    float vignetteRadius;     // normalized radius [0, 1]
    float vignetteSoftness;   // falloff softness [0, 1]
    float _vignettePad;

    // Film grain
    float grainIntensity;     // noise intensity [0, 1]
    float grainSize;          // noise scale multiplier
    float grainTime;          // time seed for animated noise
    float _grainPad;

    // Sharpen (unsharp mask)
    float sharpenAmount;      // sharpening strength [0, 4]
    float sharpenRadius;      // kernel radius in pixels
    float sharpenThreshold;   // edge threshold for selective sharpening
    float _sharpenPad;

    // Frame dimensions
    float2 frameDimensions;   // width, height in pixels
    float2 _framePad;
};

#endif /* SharedTypes_h */
