# Color Grading & Filters System Design

**Date:** 2026-02-06
**Status:** Design
**Author:** Development Team
**Depends On:** Timeline Architecture V2, VideoProcessingService (native export pipeline), Keyframe system

---

## Table of Contents

1. [Overview](#1-overview)
2. [Data Models](#2-data-models)
3. [Architecture](#3-architecture)
4. [CIFilter Pipeline](#4-cifilter-pipeline)
5. [LUT System](#5-lut-system)
6. [Color Grading UI](#6-color-grading-ui)
7. [Curves Editor](#7-curves-editor)
8. [HSL Wheels](#8-hsl-wheels)
9. [Real-Time Preview](#9-real-time-preview)
10. [Export Integration](#10-export-integration)
11. [Color Match](#11-color-match)
12. [Persistence](#12-persistence)
13. [Edge Cases](#13-edge-cases)
14. [Performance](#14-performance)
15. [Bundled LUT Library](#15-bundled-lut-library)
16. [Dependencies](#16-dependencies)
17. [Implementation Plan](#17-implementation-plan)

---

## 1. Overview

The Color Grading & Filters system adds professional color correction and grading to Liquid Editor. It integrates with the existing `VideoClip` model, keyframe system (18+ interpolation types), and native `VideoProcessingService` export pipeline.

### Goals

- Professional-grade color adjustments (exposure, contrast, saturation, temperature, etc.)
- LUT-based filter system with bundled library and custom .cube import
- HSL color wheels for shadows/midtones/highlights
- RGB + luminance curves with draggable control points
- All parameters keyframeable using the existing keyframe system
- Real-time GPU-accelerated preview via CIFilter pipeline on iOS
- Before/after comparison mode
- Color match between clips
- Save/load custom color presets

### Integration Points

| Existing Component | Integration |
|---|---|
| `VideoClip` (lib/models/clips/video_clip.dart) | Add `colorGradeId` field referencing a `ColorGrade` |
| `TimelineClip` (lib/timeline/data/models/timeline_clip.dart) | Add `hasColorGrade` metadata flag |
| `Keyframe` / `InterpolationType` (lib/models/keyframe.dart) | Reuse existing 21 interpolation types for color keyframes |
| `VideoProcessingService` (ios/Runner/VideoProcessingService.swift) | Add CIFilter pipeline to `AVVideoComposition` during export |
| `MethodChannel` (`com.liquideditor/video_processing`) | New methods: `applyColorGrade`, `previewColorGrade`, `parseLUT` |

---

## 2. Data Models

### 2.1 ColorGrade

The primary model holding all color adjustment parameters for a clip.

```dart
/// lib/models/color_grade.dart

@immutable
class ColorGrade {
  final String id;

  // --- Basic Adjustments (all normalized -1.0 to 1.0 unless noted) ---
  final double exposure;      // -3.0 to 3.0 EV
  final double brightness;    // -1.0 to 1.0
  final double contrast;      // -1.0 to 1.0
  final double saturation;    // -1.0 to 1.0 (0.0 = no change, -1.0 = desaturated)
  final double vibrance;      // -1.0 to 1.0
  final double temperature;   // -1.0 to 1.0 (maps to 2000K-10000K)
  final double tint;          // -1.0 to 1.0 (green to magenta)
  final double highlights;    // -1.0 to 1.0
  final double shadows;       // -1.0 to 1.0
  final double whites;        // -1.0 to 1.0
  final double blacks;        // -1.0 to 1.0
  final double sharpness;     // 0.0 to 1.0
  final double clarity;       // -1.0 to 1.0

  // --- LUT Filter ---
  final LUTFilter? lutFilter;

  // --- HSL Adjustments ---
  final HSLAdjustment hslShadows;
  final HSLAdjustment hslMidtones;
  final HSLAdjustment hslHighlights;

  // --- Curves ---
  final CurveData curveLuminance;
  final CurveData curveRed;
  final CurveData curveGreen;
  final CurveData curveBlue;

  // --- Vignette ---
  final double vignetteIntensity;  // 0.0 to 1.0
  final double vignetteRadius;     // 0.0 to 2.0 (normalized from center)
  final double vignetteSoftness;   // 0.0 to 1.0

  // --- Metadata ---
  final bool isEnabled;  // Master toggle
  final DateTime createdAt;
  final DateTime modifiedAt;

  const ColorGrade({
    required this.id,
    this.exposure = 0.0,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.vibrance = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.sharpness = 0.0,
    this.clarity = 0.0,
    this.lutFilter,
    this.hslShadows = const HSLAdjustment.identity(),
    this.hslMidtones = const HSLAdjustment.identity(),
    this.hslHighlights = const HSLAdjustment.identity(),
    this.curveLuminance = const CurveData.identity(),
    this.curveRed = const CurveData.identity(),
    this.curveGreen = const CurveData.identity(),
    this.curveBlue = const CurveData.identity(),
    this.vignetteIntensity = 0.0,
    this.vignetteRadius = 1.0,
    this.vignetteSoftness = 0.5,
    this.isEnabled = true,
    required this.createdAt,
    required this.modifiedAt,
  });

  /// Check if any parameter deviates from defaults
  bool get isIdentity =>
      exposure == 0.0 && brightness == 0.0 && contrast == 0.0 &&
      saturation == 0.0 && vibrance == 0.0 && temperature == 0.0 &&
      tint == 0.0 && highlights == 0.0 && shadows == 0.0 &&
      whites == 0.0 && blacks == 0.0 && sharpness == 0.0 &&
      clarity == 0.0 && lutFilter == null &&
      hslShadows.isIdentity && hslMidtones.isIdentity &&
      hslHighlights.isIdentity &&
      curveLuminance.isIdentity && curveRed.isIdentity &&
      curveGreen.isIdentity && curveBlue.isIdentity &&
      vignetteIntensity == 0.0;

  // copyWith, toJson, fromJson omitted for brevity
}
```

### 2.2 LUTFilter

```dart
@immutable
class LUTFilter {
  final String id;
  final String name;
  final String lutAssetPath;      // Bundle path or document directory path
  final LUTSource source;         // bundled | custom
  final int dimension;            // LUT dimension (typically 33 or 65)
  final double intensity;         // 0.0 to 1.0 blend with original
  final String? category;         // "cinematic", "vintage", "bw", etc.
  final String? thumbnailPath;    // Cached preview thumbnail

  const LUTFilter({
    required this.id,
    required this.name,
    required this.lutAssetPath,
    required this.source,
    this.dimension = 33,
    this.intensity = 1.0,
    this.category,
    this.thumbnailPath,
  });
}

enum LUTSource { bundled, custom }
```

### 2.3 HSLAdjustment

Represents hue/saturation offset for a tonal range (shadows, midtones, highlights).

```dart
@immutable
class HSLAdjustment {
  final double hue;         // 0.0 to 360.0 degrees (offset from neutral)
  final double saturation;  // 0.0 to 1.0 (0.0 = neutral)
  final double luminance;   // -1.0 to 1.0 (lift/gamma/gain)

  const HSLAdjustment({
    this.hue = 0.0,
    this.saturation = 0.0,
    this.luminance = 0.0,
  });

  const HSLAdjustment.identity()
      : hue = 0.0,
        saturation = 0.0,
        luminance = 0.0;

  bool get isIdentity => hue == 0.0 && saturation == 0.0 && luminance == 0.0;
}
```

### 2.4 CurveData

```dart
@immutable
class CurveData {
  /// Control points as normalized (x, y) pairs where x=input, y=output.
  /// Always starts at (0,0) and ends at (1,1) for identity.
  /// Minimum 2 points, maximum 16 points.
  final List<CurvePoint> points;

  const CurveData({required this.points});

  const CurveData.identity()
      : points = const [
          CurvePoint(0.0, 0.0),
          CurvePoint(1.0, 1.0),
        ];

  bool get isIdentity =>
      points.length == 2 &&
      points[0].x == 0.0 && points[0].y == 0.0 &&
      points[1].x == 1.0 && points[1].y == 1.0;

  /// Evaluate the curve at a given input value using monotone cubic interpolation.
  double evaluate(double input) { /* Fritsch-Carlson monotone cubic */ }
}

@immutable
class CurvePoint {
  final double x; // 0.0 to 1.0
  final double y; // 0.0 to 1.0

  const CurvePoint(this.x, this.y);
}
```

### 2.5 ColorPreset

```dart
@immutable
class ColorPreset {
  final String id;
  final String name;
  final String? description;
  final ColorGrade grade;            // Full snapshot of the color grade
  final PresetSource source;         // builtin | user
  final String? category;            // "cinematic", "portrait", etc.
  final String? thumbnailBase64;     // Preview thumbnail
  final DateTime createdAt;

  const ColorPreset({
    required this.id,
    required this.name,
    this.description,
    required this.grade,
    required this.source,
    this.category,
    this.thumbnailBase64,
    required this.createdAt,
  });
}

enum PresetSource { builtin, user }
```

### 2.6 ColorGrade Keyframe

Color grades are keyframeable by composing with the existing keyframe system. Rather than adding color parameters to `VideoTransform`, we create a parallel keyframe track:

```dart
@immutable
class ColorKeyframe {
  final String id;
  final Duration timestamp;          // Relative to clip start (same as Keyframe)
  final ColorGrade grade;            // Full color state at this point
  final InterpolationType interpolation;  // Reuses existing 21 types
  final List<Offset>? bezierPoints;  // For custom bezier interpolation

  const ColorKeyframe({
    required this.id,
    required this.timestamp,
    required this.grade,
    this.interpolation = InterpolationType.linear,
    this.bezierPoints,
  });
}
```

Color keyframes interpolate each numeric parameter independently using the same `InterpolationType` enum and `TransformInterpolator` easing functions from the existing system. LUT filters crossfade via intensity blending. Curve points interpolate per-point (must have matching point counts between keyframes).

---

## 3. Architecture

### 3.1 Component Diagram

```
Flutter Layer
==============================================================================

  ColorGradeController (ChangeNotifier)
  ├── colorGrade: ColorGrade         (current state)
  ├── colorKeyframes: List<CK>      (keyframe track)
  ├── previewMode: PreviewMode       (normal / beforeAfter / split)
  ├── activePanel: ColorPanel        (adjustments / lut / hsl / curves / vig)
  │
  ├── updateParameter(name, value)   → rebuild CIFilter params
  ├── addColorKeyframe()             → snapshot current grade at playhead
  ├── interpolateAt(Duration)        → compute grade at time
  ├── applyPreset(ColorPreset)       → load full grade
  ├── matchColor(sourceClipId)       → trigger histogram match
  ├── importLUT(File)                → parse .cube, register
  └── savePreset(name)               → serialize current grade

  SmartEditViewModel
  └── colorGradeController            (owns lifecycle)

==============================================================================
Platform Channel: com.liquideditor/color_grading
==============================================================================

Native iOS Layer (Swift)
==============================================================================

  ColorGradingService
  ├── buildFilterChain(params)   → CIFilter chain for preview
  ├── applyToPixelBuffer(CVPixelBuffer, params) → real-time render
  ├── parseCubeLUT(path)         → [Float] data + dimension
  ├── computeHistogram(assetURL, timeRange) → histogram data
  ├── matchHistograms(source, target) → matched ColorGrade
  └── buildVideoComposition(params) → AVVideoComposition with CIFilters

  VideoProcessingService (EXISTING - extended)
  └── renderComposition(...)     → now accepts colorGradeParams per clip
```

### 3.2 VideoClip Extension

The `VideoClip` model gains a reference to color grading data:

```dart
class VideoClip extends MediaClip {
  final List<Keyframe> keyframes;       // Existing: transform keyframes
  final List<ColorKeyframe> colorKeyframes;  // NEW: color keyframes
  final String? colorGradeId;           // NEW: reference to default ColorGrade
  final String? name;

  // ... existing methods ...

  // NEW: Color keyframe operations (mirrors existing keyframe pattern)
  VideoClip addColorKeyframe(ColorKeyframe kf) => copyWith(
    colorKeyframes: [...colorKeyframes, kf],
  );
  VideoClip removeColorKeyframe(String kfId) => copyWith(
    colorKeyframes: colorKeyframes.where((k) => k.id != kfId).toList(),
  );
}
```

The `TimelineClip` UI model adds a flag:

```dart
class TimelineClip {
  // ... existing fields ...
  final bool hasColorGrade;   // NEW: show color indicator on clip
}
```

### 3.3 State Flow

```
User adjusts slider → ColorGradeController.updateParameter()
    ↓
ColorGrade immutable copy created
    ↓
Send params to native via MethodChannel (throttled to 60fps max)
    ↓
ColorGradingService.buildFilterChain() on native
    ↓
CIFilter chain applied to preview CVPixelBuffer
    ↓
Rendered frame displayed in preview widget
```

---

## 4. CIFilter Pipeline

### 4.1 Filter Chain Order

The order of CIFilter application matters. The pipeline processes in this order to match professional color grading workflows (similar to DaVinci Resolve node order):

```
Source Frame (CVPixelBuffer)
    │
    ▼
1. CIExposureAdjust        ← exposure (-3.0 to 3.0 EV)
    │
    ▼
2. CITemperatureAndTint     ← temperature + tint
    │
    ▼
3. CIHighlightShadowAdjust  ← highlights + shadows
    │
    ▼
4. CIToneCurve              ← whites + blacks (mapped to 5-point curve)
    │
    ▼
5. CIColorControls          ← brightness + contrast + saturation
    │
    ▼
6. Vibrance (custom)        ← saturation boost for unsaturated pixels only
    │
    ▼
7. HSL Wheels               ← shadows/midtones/highlights color shift
   (CIColorMatrix per range)
    │
    ▼
8. CIToneCurve (RGB)        ← per-channel curves (R, G, B, Luminance)
    │
    ▼
9. CIColorCubeWithColorSpace ← LUT filter (if applied)
    │
    ▼
10. CISharpenLuminance       ← sharpness
    │
    ▼
11. CIUnsharpMask            ← clarity (local contrast via unsharp mask)
    │
    ▼
12. CIVignette               ← vignette
    │
    ▼
Output Frame
```

### 4.2 Parameter-to-CIFilter Mapping

| Parameter | CIFilter | Input Key | Value Mapping |
|---|---|---|---|
| exposure | CIExposureAdjust | inputEV | Direct: -3.0 to 3.0 |
| brightness | CIColorControls | inputBrightness | Direct: -1.0 to 1.0 |
| contrast | CIColorControls | inputContrast | Map: -1.0..1.0 to 0.25..1.75 (1.0 = neutral) |
| saturation | CIColorControls | inputSaturation | Map: -1.0..1.0 to 0.0..2.0 (1.0 = neutral) |
| vibrance | Custom kernel | -- | Selective saturation boost (see 4.3) |
| temperature | CITemperatureAndTint | inputNeutral | Map: -1.0..1.0 to 2000K..10000K (6500K = neutral) |
| tint | CITemperatureAndTint | inputTargetNeutral | Map: -1.0..1.0 to green..magenta shift |
| highlights | CIHighlightShadowAdjust | inputHighlightAmount | Map: -1.0..1.0 to -1.0..1.0 |
| shadows | CIHighlightShadowAdjust | inputShadowAmount | Map: -1.0..1.0 to -1.0..1.0 |
| whites | CIToneCurve | inputPoint4 | Adjust top curve point |
| blacks | CIToneCurve | inputPoint0 | Adjust bottom curve point |
| sharpness | CISharpenLuminance | inputSharpness | Map: 0.0..1.0 to 0.0..2.0 |
| clarity | CIUnsharpMask | inputRadius + inputIntensity | radius=20, intensity mapped 0.0..1.5 |
| vignette | CIVignette | inputIntensity + inputRadius | Direct mapping |

### 4.3 Vibrance Implementation

CIFilter does not have a built-in vibrance filter. Implement as a CIColorKernel:

```swift
// Vibrance boosts saturation of less-saturated pixels, leaves saturated pixels alone.
// This prevents oversaturation of skin tones.
let vibranceKernel = CIColorKernel(source: """
    kernel vec4 vibrance(sampler image, float amount) {
        vec4 pixel = sample(image, samplerCoord(image));
        float avg = (pixel.r + pixel.g + pixel.b) / 3.0;
        float maxChannel = max(pixel.r, max(pixel.g, pixel.b));
        float saturation = maxChannel - avg;
        float boost = amount * (1.0 - saturation) * (1.0 - saturation);
        pixel.rgb = mix(vec3(avg), pixel.rgb, 1.0 + boost);
        return pixel;
    }
""")
```

### 4.4 HSL Wheels to CIFilter Mapping

The HSL wheels (shadows/midtones/highlights) are implemented using luminance-range-specific color matrix operations:

```swift
func buildHSLFilter(adjustment: HSLAdjustment, range: TonalRange) -> CIFilter {
    // 1. Convert hue+saturation to RGB offset vector
    let angle = adjustment.hue * .pi / 180.0
    let r = cos(angle) * adjustment.saturation
    let g = cos(angle - 2.0 * .pi / 3.0) * adjustment.saturation
    let b = cos(angle + 2.0 * .pi / 3.0) * adjustment.saturation

    // 2. Create luminance mask for tonal range
    //    - shadows: luminance 0.0-0.33 (feathered)
    //    - midtones: luminance 0.2-0.8 (feathered)
    //    - highlights: luminance 0.67-1.0 (feathered)

    // 3. Apply CIColorMatrix with mask-weighted RGB offsets
    //    Plus luminance lift/gamma/gain adjustment
}
```

### 4.5 Whites/Blacks via CIToneCurve

The whites and blacks adjustments map to the endpoints of a 5-point tone curve:

```swift
// Default identity curve: (0,0), (0.25,0.25), (0.5,0.5), (0.75,0.75), (1,1)
// blacks slider adjusts point0.y: blacks=-1 → (0, -0.15), blacks=1 → (0, 0.15)
// whites slider adjusts point4.y: whites=-1 → (1, 0.85), whites=1 → (1, 1.15)

let toneCurve = CIFilter(name: "CIToneCurve")!
toneCurve.setValue(CIVector(x: 0.0, y: max(0, blacks * 0.15)),
                   forKey: "inputPoint0")
toneCurve.setValue(CIVector(x: 1.0, y: min(1, 1.0 + whites * 0.15)),
                   forKey: "inputPoint4")
```

### 4.6 Filter Chain Optimization

To avoid creating CIFilter instances every frame:

```swift
final class CIFilterChain {
    // Pre-allocated filter instances (reused across frames)
    private let exposureFilter = CIFilter(name: "CIExposureAdjust")!
    private let tempTintFilter = CIFilter(name: "CITemperatureAndTint")!
    private let highlightShadowFilter = CIFilter(name: "CIHighlightShadowAdjust")!
    private let toneCurveFilter = CIFilter(name: "CIToneCurve")!
    private let colorControlsFilter = CIFilter(name: "CIColorControls")!
    private let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
    private let vignetteFilter = CIFilter(name: "CIVignette")!

    // Only update parameters that changed (dirty flag per filter)
    private var dirtyFlags: Set<FilterStage> = []

    func updateParameter(_ param: String, value: Double) {
        // Mark only the affected filter as dirty
        dirtyFlags.insert(FilterStage.for(param))
    }

    func apply(to image: CIImage) -> CIImage {
        var result = image
        // Only rebuild dirty filters; others reuse cached output
        // ... chain application ...
        return result
    }
}
```

---

## 5. LUT System

### 5.1 .cube File Format

The industry-standard .cube format for 3D LUTs:

```
# Comment line
TITLE "My LUT"
DOMAIN_MIN 0.0 0.0 0.0
DOMAIN_MAX 1.0 1.0 1.0
LUT_3D_SIZE 33
0.000000 0.000000 0.000000
0.003906 0.000000 0.000000
...
```

### 5.2 Parser (Native Swift)

```swift
struct ParsedLUT {
    let title: String
    let dimension: Int        // e.g. 33
    let data: [Float]         // dimension^3 * 4 (RGBA) float array
    let domainMin: SIMD3<Float>
    let domainMax: SIMD3<Float>
}

func parseCubeLUT(at path: String) throws -> ParsedLUT {
    let content = try String(contentsOfFile: path, encoding: .utf8)
    var dimension = 0
    var title = ""
    var data: [Float] = []
    var domainMin = SIMD3<Float>(0, 0, 0)
    var domainMax = SIMD3<Float>(1, 1, 1)

    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

        if trimmed.hasPrefix("LUT_3D_SIZE") {
            dimension = Int(trimmed.split(separator: " ").last ?? "33") ?? 33
        } else if trimmed.hasPrefix("TITLE") {
            title = String(trimmed.dropFirst(6)).trimmingCharacters(in: .init(charactersIn: "\" "))
        } else if trimmed.hasPrefix("DOMAIN_MIN") {
            let parts = trimmed.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 { domainMin = SIMD3(parts[0], parts[1], parts[2]) }
        } else if trimmed.hasPrefix("DOMAIN_MAX") {
            let parts = trimmed.split(separator: " ").compactMap { Float($0) }
            if parts.count == 3 { domainMax = SIMD3(parts[0], parts[1], parts[2]) }
        } else {
            // RGB data line
            let values = trimmed.split(separator: " ").compactMap { Float($0) }
            if values.count >= 3 {
                data.append(contentsOf: [values[0], values[1], values[2], 1.0]) // RGBA
            }
        }
    }

    guard dimension > 0, data.count == dimension * dimension * dimension * 4 else {
        throw LUTParseError.invalidDimension
    }

    return ParsedLUT(title: title, dimension: dimension, data: data,
                     domainMin: domainMin, domainMax: domainMax)
}
```

### 5.3 LUT Application via CIFilter

```swift
func createLUTFilter(from lut: ParsedLUT, intensity: Float) -> CIFilter? {
    let size = lut.dimension
    let dataSize = size * size * size * 4 * MemoryLayout<Float>.size
    let data = Data(bytes: lut.data, count: dataSize)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
    filter.setValue(size, forKey: "inputCubeDimension")
    filter.setValue(data, forKey: "inputCubeData")
    filter.setValue(colorSpace, forKey: "inputColorSpace")

    // Intensity blending: lerp between identity LUT and graded LUT
    // When intensity < 1.0, blend with CIColorCrossPolynomial identity
    // or use CIMix filter to blend original with LUT result
    return filter
}
```

### 5.4 Intensity Blending

When LUT intensity < 1.0, blend the LUT output with the original:

```swift
func applyLUTWithIntensity(image: CIImage, lutFilter: CIFilter, intensity: Float) -> CIImage {
    lutFilter.setValue(image, forKey: kCIInputImageKey)
    guard let lutResult = lutFilter.outputImage else { return image }

    if intensity >= 0.999 { return lutResult }

    // Use CIBlendWithAlphaMask or manual mix
    let mixFilter = CIFilter(name: "CIMix")! // CIMix is not built-in
    // Alternative: use CISourceOverCompositing with alpha-adjusted overlay

    // Practical approach: use CIColorMatrix to reduce alpha, then composite
    let alphaFilter = CIFilter(name: "CIColorMatrix")!
    alphaFilter.setValue(lutResult, forKey: kCIInputImageKey)
    alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(intensity)), forKey: "inputAVector")
    guard let adjustedLut = alphaFilter.outputImage else { return image }

    let composite = CIFilter(name: "CISourceOverCompositing")!
    composite.setValue(adjustedLut, forKey: kCIInputImageKey)
    composite.setValue(image, forKey: kCIInputBackgroundImageKey)
    return composite.outputImage ?? image
}
```

### 5.5 Bundled LUT Storage

Bundled LUTs are stored as pre-parsed binary data in the iOS app bundle for instant loading:

```
ios/Runner/Assets/LUTs/
├── cinematic/
│   ├── teal_orange.cube
│   ├── film_noir.cube
│   ├── golden_hour.cube
│   └── ...
├── vintage/
│   ├── polaroid.cube
│   ├── kodak_portra.cube
│   └── ...
└── manifest.json           ← index of all bundled LUTs with metadata
```

Custom user LUTs are stored in the app's Documents directory:

```
Documents/LUTs/
├── custom_lut_uuid1.cube
├── custom_lut_uuid2.cube
└── custom_luts.json        ← user LUT metadata index
```

### 5.6 Custom LUT Import Flow

```
User taps "Import LUT" → File picker (.cube files)
    ↓
Copy .cube to Documents/LUTs/
    ↓
MethodChannel: parseCubeLUT(path)
    ↓
Native: validate, parse, return (dimension, title)
    ↓
Flutter: create LUTFilter model, generate preview thumbnail
    ↓
Add to custom LUT library, persist metadata
```

---

## 6. Color Grading UI

### 6.1 Panel Structure

The color grading UI is accessed by selecting a clip and tapping a "Color" button in the editor toolbar. It appears as a bottom panel (similar to the existing keyframe timeline panel).

```
┌─────────────────────────────────────────────────┐
│  Video Preview (with before/after if enabled)   │
├─────────────────────────────────────────────────┤
│  Panel Tabs: [Adjust] [Filters] [HSL] [Curves] │
│              [Vignette]                         │
├─────────────────────────────────────────────────┤
│                                                 │
│  Panel Content (varies by tab)                  │
│                                                 │
├─────────────────────────────────────────────────┤
│  Bottom Bar: [Reset] [Before/After] [Presets]   │
│              [Keyframe ◇] [Copy Grade]          │
└─────────────────────────────────────────────────┘
```

### 6.2 Adjustments Panel

A vertical scrollable list of labeled CupertinoSliders:

```dart
Widget _buildAdjustmentsPanel(ColorGrade grade) {
  return ListView(
    children: [
      _buildSliderRow('Exposure', grade.exposure, -3.0, 3.0,
          (v) => controller.updateParameter('exposure', v)),
      _buildSliderRow('Brightness', grade.brightness, -1.0, 1.0,
          (v) => controller.updateParameter('brightness', v)),
      _buildSliderRow('Contrast', grade.contrast, -1.0, 1.0,
          (v) => controller.updateParameter('contrast', v)),
      _buildSliderRow('Saturation', grade.saturation, -1.0, 1.0,
          (v) => controller.updateParameter('saturation', v)),
      _buildSliderRow('Vibrance', grade.vibrance, -1.0, 1.0,
          (v) => controller.updateParameter('vibrance', v)),
      const _SectionDivider('White Balance'),
      _buildSliderRow('Temperature', grade.temperature, -1.0, 1.0,
          (v) => controller.updateParameter('temperature', v)),
      _buildSliderRow('Tint', grade.tint, -1.0, 1.0,
          (v) => controller.updateParameter('tint', v)),
      const _SectionDivider('Tone'),
      _buildSliderRow('Highlights', grade.highlights, -1.0, 1.0,
          (v) => controller.updateParameter('highlights', v)),
      _buildSliderRow('Shadows', grade.shadows, -1.0, 1.0,
          (v) => controller.updateParameter('shadows', v)),
      _buildSliderRow('Whites', grade.whites, -1.0, 1.0,
          (v) => controller.updateParameter('whites', v)),
      _buildSliderRow('Blacks', grade.blacks, -1.0, 1.0,
          (v) => controller.updateParameter('blacks', v)),
      const _SectionDivider('Detail'),
      _buildSliderRow('Sharpness', grade.sharpness, 0.0, 1.0,
          (v) => controller.updateParameter('sharpness', v)),
      _buildSliderRow('Clarity', grade.clarity, -1.0, 1.0,
          (v) => controller.updateParameter('clarity', v)),
    ],
  );
}
```

Each slider uses `CupertinoSlider` (per CLAUDE.md requirements). The slider has:
- Label on the left
- Current value display on the right
- Double-tap to reset to 0

### 6.3 Filters Panel (LUT Browser)

Horizontal scrollable grid of filter thumbnails with intensity slider below:

```
┌─────────────────────────────────────────────────┐
│ Categories: [All] [Cinematic] [Vintage] [B&W]   │
│             [Portrait] [Custom]                  │
├─────────────────────────────────────────────────┤
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐  │
│ │ None │ │Teal  │ │Film  │ │Golden│ │Warm  │  │
│ │      │ │Orange│ │Noir  │ │Hour  │ │Sunset│  │
│ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘  │
│ ◄──────────────────────────────────────────────► │
├─────────────────────────────────────────────────┤
│ Intensity: ═══════════●══════  [85%]            │
└─────────────────────────────────────────────────┘
```

Each thumbnail is generated by applying the LUT to a reference frame from the current clip. Thumbnails are cached per clip+LUT combination.

### 6.4 Before/After Comparison

Three modes accessible via a toggle button:

1. **Side-by-Side Split**: Vertical divider draggable left/right. Left = original, right = graded.
2. **Swipe Toggle**: Hold to see original, release for graded.
3. **Full Toggle**: Tap to toggle between original and graded.

Implementation uses two `CIImage` renderers: one with filter chain, one without.

---

## 7. Curves Editor

### 7.1 UI Layout

```
┌─────────────────────────────────────────────────┐
│  Channel: [RGB] [R] [G] [B] [Luma]             │
├─────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────┐  │
│  │              Curve Canvas                  │  │
│  │   (256x256 logical, rendered on           │  │
│  │    CustomPainter with anti-aliased         │  │
│  │    spline curve and draggable points)      │  │
│  │                                            │  │
│  │  ·─────────────────────────●               │  │
│  │  │                    ●   /                │  │
│  │  │               ●  /                      │  │
│  │  │          ·  /                           │  │
│  │  ●─────·──/                                │  │
│  │  ─────────────────────────────────         │  │
│  └───────────────────────────────────────────┘  │
│  Histogram overlay (optional, semi-transparent)  │
│  [Reset Curve] [Add Point] [Delete Point]       │
└─────────────────────────────────────────────────┘
```

### 7.2 Canvas Implementation

```dart
class CurvesEditorCanvas extends CustomPainter {
  final CurveData curveData;
  final CurveChannel activeChannel;
  final List<double>? histogram;  // 256-bin histogram for overlay
  final int? selectedPointIndex;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw grid (4x4 with subtle lines)
    _drawGrid(canvas, size);

    // 2. Draw histogram overlay (if available)
    if (histogram != null) {
      _drawHistogram(canvas, size, histogram!);
    }

    // 3. Draw identity diagonal (subtle reference line)
    _drawIdentityLine(canvas, size);

    // 4. Draw the monotone cubic spline curve
    _drawCurve(canvas, size, curveData);

    // 5. Draw control points (circles with hit areas)
    _drawControlPoints(canvas, size, curveData.points, selectedPointIndex);
  }
}
```

### 7.3 Control Point Interaction

- **Drag**: Move a control point. X is constrained between neighboring points (cannot cross). Y is clamped to 0.0-1.0.
- **Tap empty area**: Add a new control point at that position on the curve (max 16).
- **Double-tap point**: Delete it (except endpoints at x=0 and x=1).
- **Pinch on canvas**: Zoom the curve view for fine control.
- **Long-press point**: Show exact numeric values in a tooltip.

### 7.4 Spline Interpolation

Use monotone cubic Hermite interpolation (Fritsch-Carlson method) to ensure the curve never overshoots between control points:

```dart
double evaluateMonotoneCubic(List<CurvePoint> points, double x) {
  // 1. Find interval [i, i+1] containing x
  // 2. Compute tangents with Fritsch-Carlson monotonicity constraints
  // 3. Evaluate cubic Hermite basis
  // This ensures no ringing/overshoot artifacts in the color transform
}
```

### 7.5 Curve to CIFilter Conversion

The `CurveData` is sampled at 256 points and passed to `CIToneCurve` (for 5-point approximation) or to a custom `CIColorCurves` filter (for higher fidelity):

```swift
// For simple curves (< 5 points), use CIToneCurve directly
// For complex curves, sample to 256-entry lookup table and use CIColorMap
func curveToCIFilter(curveData: [Float], channel: CurveChannel) -> CIFilter {
    // Sample curve at 256 points
    var lut = [Float](repeating: 0, count: 256 * 4)
    for i in 0..<256 {
        let input = Float(i) / 255.0
        let output = evaluateCurve(curveData, at: input)
        // Apply to appropriate channel
        switch channel {
        case .luminance:
            lut[i * 4 + 0] = output  // R
            lut[i * 4 + 1] = output  // G
            lut[i * 4 + 2] = output  // B
            lut[i * 4 + 3] = 1.0     // A
        case .red:
            lut[i * 4 + 0] = output
            lut[i * 4 + 1] = Float(i) / 255.0  // identity
            lut[i * 4 + 2] = Float(i) / 255.0
            lut[i * 4 + 3] = 1.0
        // ... green, blue similarly
        }
    }
    // Create 1D color cube (256x1x1)
    let filter = CIFilter(name: "CIColorCube")!
    filter.setValue(256, forKey: "inputCubeDimension")
    filter.setValue(Data(bytes: lut, count: lut.count * 4), forKey: "inputCubeData")
    return filter
}
```

---

## 8. HSL Wheels

### 8.1 Three-Wheel Layout

```
┌─────────────────────────────────────────────────┐
│     Shadows        Midtones       Highlights     │
│   ┌────────┐    ┌────────┐    ┌────────┐       │
│   │  ╱──╲  │    │  ╱──╲  │    │  ╱──╲  │       │
│   │ │  ● │ │    │ │ ●  │ │    │ │  ● │ │       │
│   │  ╲──╱  │    │  ╲──╱  │    │  ╲──╱  │       │
│   └────────┘    └────────┘    └────────┘       │
│   Luma: ═●══    Luma: ═●══    Luma: ═●══       │
└─────────────────────────────────────────────────┘
```

### 8.2 Wheel Widget

Each color wheel is a `CustomPainter` with:

- **Outer ring**: Hue gradient (rainbow circle)
- **Inner disc**: Saturation gradient (center = neutral, edge = full saturation)
- **Control dot**: Position encodes hue (angle) and saturation (distance from center)
- **Luminance slider**: Below each wheel, a `CupertinoSlider` for lift/gamma/gain

### 8.3 Wheel Interaction

```dart
class ColorWheelWidget extends StatefulWidget {
  final HSLAdjustment adjustment;
  final ValueChanged<HSLAdjustment> onChanged;
  final String label;  // "Shadows", "Midtones", "Highlights"
}
```

Gesture handling:
- **Pan on wheel**: Moves the control dot. Convert cartesian offset to polar (hue, saturation).
- **Double-tap wheel center**: Reset to neutral (hue=0, saturation=0).
- **Haptic feedback**: Light impact when crossing center or cardinal directions.

### 8.4 Polar-to-HSL Conversion

```dart
HSLAdjustment offsetToHSL(Offset offset, double wheelRadius) {
  final distance = offset.distance;
  final saturation = (distance / wheelRadius).clamp(0.0, 1.0);
  final hue = (math.atan2(offset.dy, offset.dx) * 180 / math.pi + 360) % 360;
  return HSLAdjustment(hue: hue, saturation: saturation);
}

Offset hslToOffset(HSLAdjustment hsl, double wheelRadius) {
  final angle = hsl.hue * math.pi / 180;
  final radius = hsl.saturation * wheelRadius;
  return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
}
```

### 8.5 Tonal Range Masking

On the native side, each wheel adjustment is applied only to its tonal range using luminance masking:

```swift
func applyHSLWheels(
    image: CIImage,
    shadows: HSLAdjustment,
    midtones: HSLAdjustment,
    highlights: HSLAdjustment
) -> CIImage {
    // Use CIKernel to compute luminance-weighted color offsets
    // Shadow mask: smoothstep(0.0, 0.33, luma) inverted
    // Midtone mask: 1.0 - shadow_mask - highlight_mask
    // Highlight mask: smoothstep(0.67, 1.0, luma)
    // Apply per-range color matrix with feathered overlap
}
```

---

## 9. Real-Time Preview

### 9.1 Architecture

Real-time preview uses a Metal-backed `CIContext` to render the CIFilter chain directly to the preview surface:

```
Playback frame (CVPixelBuffer from AVPlayer)
    ↓
CIImage(cvPixelBuffer:)
    ↓
CIFilterChain.apply(to: ciImage, params: colorGradeParams)
    ↓
CIContext.render(to: MTLTexture or CVPixelBuffer)
    ↓
Display via Flutter Texture widget (texture ID)
```

### 9.2 Platform Channel Protocol

```dart
// Flutter → Native: Update color grade parameters for preview
await _channel.invokeMethod('updateColorGrade', {
  'clipId': clipId,
  'params': colorGrade.toNativeMap(),  // Flat map of all parameters
});

// Native responds by applying filters to the next frame automatically.
// No round-trip needed per frame -- params are cached on native side.
```

### 9.3 Parameter Throttling

To prevent overwhelming the native pipeline during rapid slider adjustments:

```dart
class ColorGradeController extends ChangeNotifier {
  Timer? _debounceTimer;

  void updateParameter(String name, double value) {
    _currentGrade = _currentGrade.copyWithParam(name, value);
    notifyListeners();  // Update UI immediately

    // Debounce native update to max 60fps
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 16), () {
      _sendToNative(_currentGrade);
    });
  }
}
```

### 9.4 Preview Rendering Pipeline (Native)

```swift
final class ColorGradingPreviewService {
    private let ciContext: CIContext
    private let filterChain: CIFilterChain
    private var currentParams: [String: Any] = [:]

    init() {
        // Metal-backed CIContext for GPU rendering
        let device = MTLCreateSystemDefaultDevice()!
        ciContext = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false,    // Reduce memory usage
            .priorityRequestLow: false,     // High priority for preview
        ])
        filterChain = CIFilterChain()
    }

    func processFrame(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        filterChain.updateParams(currentParams)
        let outputImage = filterChain.apply(to: inputImage)

        // Render to output pixel buffer (pre-allocated from pool)
        let outputBuffer = pixelBufferPool.dequeue()
        ciContext.render(outputImage, to: outputBuffer)
        return outputBuffer
    }
}
```

### 9.5 Flutter Texture Integration

The graded preview is displayed via Flutter's `Texture` widget, backed by a native `FlutterTexture`:

```swift
class ColorGradeTextureHandler: NSObject, FlutterTexture {
    private var latestPixelBuffer: CVPixelBuffer?

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    func updateFrame(_ buffer: CVPixelBuffer) {
        latestPixelBuffer = buffer
        registry.textureFrameAvailable(textureId)
    }
}
```

```dart
// Flutter widget
Texture(textureId: _colorGradeTextureId)
```

This approach avoids sending pixel data over the platform channel (zero-copy path via shared GPU memory).

---

## 10. Export Integration

### 10.1 AVVideoComposition with CIFilters

During export, color grading is applied using `AVVideoComposition`'s custom compositor API, which runs CIFilters on each frame during the export pass. This integrates with the existing `VideoProcessingService.renderComposition()` method.

```swift
// Extension to existing renderComposition in VideoProcessingService.swift

func renderCompositionWithColorGrading(
    videoPath: String,
    clips: [[String: Any]],
    colorGrades: [String: [String: Any]],  // clipId -> color grade params
    targetWidth: Int?,
    targetHeight: Int?,
    fps: Int,
    bitrateMbps: Double,
    enableHdr: Bool,
    result: @escaping FlutterResult
) {
    // ... existing composition building code (lines 335-433 of current file) ...

    // NEW: Apply CIFilter-based video composition instead of layer instructions
    let videoComposition = AVMutableVideoComposition(asset: composition) { request in
        // This closure is called for EVERY frame during export
        let sourceImage = request.sourceImage(byTrackID: compVideoTrack.trackID)

        // 1. Apply geometric transform (existing keyframe system)
        var result = self.applyTransform(to: sourceImage, at: request.compositionTime,
                                          clipInstructions: clipInstructions,
                                          transformCalculator: transformCalculator)

        // 2. Determine which clip is active at this time
        let activeClipId = self.findActiveClip(at: request.compositionTime,
                                                clipInstructions: clipInstructions)

        // 3. Apply color grade for active clip
        if let clipId = activeClipId,
           let gradeParams = colorGrades[clipId] {
            // Interpolate keyframed color params at current time
            let interpolatedParams = self.interpolateColorParams(
                gradeParams, at: request.compositionTime)
            result = self.colorFilterChain.apply(to: result, params: interpolatedParams)
        }

        request.finish(with: result, context: self.exportCIContext)
    }

    videoComposition.renderSize = finalOutputSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

    // ... existing export session code ...
}
```

### 10.2 Per-Clip Color Grade in Export Data

The Flutter side sends color grade data per clip in the export payload:

```dart
// In export_sheet.dart or export logic
final exportData = {
  'videoPath': project.videoPath,
  'clips': clips.map((clip) => {
    final data = clip.toExportJson();
    // Attach resolved color grade (with keyframes interpolated at export FPS)
    if (clip.colorKeyframes.isNotEmpty) {
      data['colorGrade'] = _resolveColorKeyframes(clip);
    } else if (clip.colorGradeId != null) {
      data['colorGrade'] = colorGradeStore[clip.colorGradeId]!.toNativeMap();
    }
    return data;
  }).toList(),
};
```

### 10.3 Color Keyframe Resolution for Export

During export, color keyframes are pre-sampled at the export frame rate to avoid real-time interpolation in the export compositor:

```dart
/// Pre-sample color keyframes at export FPS for a clip.
Map<String, dynamic> _resolveColorKeyframes(VideoClip clip) {
  final fps = exportPreset.fps;
  final durationMs = clip.durationMicroseconds ~/ 1000;
  final frameCount = (durationMs * fps / 1000).ceil();

  final samples = <Map<String, dynamic>>[];
  for (int i = 0; i < frameCount; i++) {
    final timeMs = (i * 1000 / fps).round();
    final grade = _interpolateGradeAt(
      clip.colorKeyframes,
      Duration(milliseconds: timeMs),
    );
    samples.add({
      'timeMs': timeMs,
      'params': grade.toNativeMap(),
    });
  }
  return {'keyframedSamples': samples};
}
```

### 10.4 LUT Handling During Export

If a clip uses a LUT filter, the LUT data is loaded once and cached for the duration of the export:

```swift
// In the export compositor closure
private var lutCache: [String: CIFilter] = [:]

func getLUTFilter(lutPath: String, intensity: Float) -> CIFilter {
    if let cached = lutCache[lutPath] {
        cached.setValue(intensity, forKey: "inputIntensity") // Custom key
        return cached
    }
    let parsed = try! parseCubeLUT(at: lutPath)
    let filter = createLUTFilter(from: parsed, intensity: intensity)!
    lutCache[lutPath] = filter
    return filter
}
```

### 10.5 HDR Export with Color Grading

When HDR export is enabled (existing `enableHdr` flag), the CIFilter pipeline operates in extended sRGB color space to preserve HDR range:

```swift
if enableHdr {
    // Use wide color space for CIContext
    let options: [CIContextOption: Any] = [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_HLG)!,
    ]
    exportCIContext = CIContext(mtlDevice: device, options: options)
}
```

---

## 11. Color Match

### 11.1 Overview

Color Match allows users to copy the look of one clip and apply it to another by matching color histograms. This is useful when combining footage from different cameras or lighting conditions.

### 11.2 Algorithm: Histogram Matching

The approach uses cumulative histogram matching in CIE Lab color space:

```swift
struct ColorHistogram {
    var luminance: [Int]   // 256 bins
    var a: [Int]           // 256 bins (green-red axis)
    var b: [Int]           // 256 bins (blue-yellow axis)
    var totalPixels: Int
}

func computeHistogram(asset: AVAsset, timeRange: CMTimeRange) -> ColorHistogram {
    // 1. Extract N evenly-spaced frames from the clip (e.g., 10 frames)
    // 2. For each frame:
    //    a. Convert to CIE Lab color space
    //    b. Accumulate per-channel histograms
    // 3. Normalize by total pixel count
    // Returns averaged histogram representing the clip's color distribution
}

func matchHistograms(source: ColorHistogram, target: ColorHistogram) -> [Float] {
    // For each channel (L, a, b):
    // 1. Compute CDF of source histogram
    // 2. Compute CDF of target histogram
    // 3. For each source bin, find the target bin with closest CDF value
    // 4. Build a 256-entry lookup table mapping source → target
    //
    // Returns 3 lookup tables (L, a, b) each with 256 entries
    // These are applied as CIColorCube filters per channel
}
```

### 11.3 Color Match to ColorGrade Conversion

Rather than applying a raw lookup table, convert the histogram match result into approximate `ColorGrade` parameters for editability:

```swift
func histogramMatchToColorGrade(
    sourceLUT: [Float],  // 256-entry per channel
    targetLUT: [Float]
) -> ColorGradeParams {
    // Analyze the LUT to extract approximate parameters:
    // - Exposure: overall luminance shift (average L channel offset)
    // - Contrast: slope of L channel LUT at midpoint
    // - Temperature: ratio of a-channel shift
    // - Tint: ratio of b-channel shift
    // - Saturation: average chroma scaling
    // - Curves: fit the LUT to a CurveData with 5-7 control points
    //
    // This gives an editable approximation. For exact match,
    // also include a residual LUT that captures what the
    // parametric approximation missed.
}
```

### 11.4 User Flow

```
1. User selects target clip (the one to be graded)
2. Taps "Color Match" button
3. Selects source clip (the reference look) from a clip picker
4. Native: compute histograms for both clips
5. Native: generate matching LUTs
6. Flutter: convert to ColorGrade + residual LUT
7. Apply to target clip as new ColorGrade
8. User can further adjust parameters on top of the match
```

### 11.5 Platform Channel API

```dart
// Flutter → Native
final result = await _channel.invokeMethod('matchColor', {
  'sourceAssetPath': sourceClip.mediaAssetPath,
  'sourceTimeRange': {'startMs': sourceIn, 'endMs': sourceOut},
  'targetAssetPath': targetClip.mediaAssetPath,
  'targetTimeRange': {'startMs': targetIn, 'endMs': targetOut},
  'sampleFrames': 10,
});

// Returns: Map with approximate ColorGrade params + residual LUT path
```

---

## 12. Persistence

### 12.1 ColorGrade Serialization

ColorGrade serializes to JSON, compatible with the existing `ProjectStorage` system:

```dart
// In project JSON structure:
{
  "project": {
    "id": "...",
    "clips": [
      {
        "itemType": "video",
        "id": "clip-uuid",
        "mediaAssetId": "asset-uuid",
        "sourceInMicros": 0,
        "sourceOutMicros": 5000000,
        "keyframes": [...],          // Existing transform keyframes
        "colorGradeId": "grade-uuid",
        "colorKeyframes": [          // NEW: color keyframes
          {
            "id": "ckf-uuid",
            "timestampMicros": 0,
            "grade": { /* full ColorGrade JSON */ },
            "interpolation": "easeInOut",
            "bezierPoints": null
          }
        ]
      }
    ],
    "colorGrades": {                 // NEW: top-level color grade store
      "grade-uuid": {
        "id": "grade-uuid",
        "exposure": 0.5,
        "brightness": 0.0,
        "contrast": 0.1,
        "saturation": -0.2,
        "vibrance": 0.3,
        "temperature": 0.1,
        "tint": 0.0,
        "highlights": -0.1,
        "shadows": 0.2,
        "whites": 0.0,
        "blacks": 0.05,
        "sharpness": 0.3,
        "clarity": 0.1,
        "lutFilter": {
          "id": "lut-uuid",
          "name": "Teal Orange",
          "lutAssetPath": "bundled://cinematic/teal_orange",
          "source": "bundled",
          "dimension": 33,
          "intensity": 0.85,
          "category": "cinematic"
        },
        "hslShadows": {"hue": 220.0, "saturation": 0.15, "luminance": -0.1},
        "hslMidtones": {"hue": 0.0, "saturation": 0.0, "luminance": 0.0},
        "hslHighlights": {"hue": 40.0, "saturation": 0.1, "luminance": 0.05},
        "curveLuminance": {
          "points": [
            {"x": 0.0, "y": 0.0},
            {"x": 0.25, "y": 0.22},
            {"x": 0.5, "y": 0.55},
            {"x": 0.75, "y": 0.78},
            {"x": 1.0, "y": 1.0}
          ]
        },
        "curveRed": {"points": [{"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 1.0}]},
        "curveGreen": {"points": [{"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 1.0}]},
        "curveBlue": {"points": [{"x": 0.0, "y": 0.0}, {"x": 1.0, "y": 1.0}]},
        "vignetteIntensity": 0.2,
        "vignetteRadius": 1.2,
        "vignetteSoftness": 0.6,
        "isEnabled": true,
        "createdAt": "2026-02-06T10:30:00Z",
        "modifiedAt": "2026-02-06T11:45:00Z"
      }
    }
  }
}
```

### 12.2 LUT File References

LUT references use a URI scheme to distinguish bundled vs. custom:

| Scheme | Example | Resolution |
|---|---|---|
| `bundled://` | `bundled://cinematic/teal_orange` | `Bundle.main.path(forResource:)` |
| `custom://` | `custom://uuid-of-lut` | `Documents/LUTs/{uuid}.cube` |

On project load, LUT availability is validated. If a custom LUT file is missing, the `LUTFilter` is marked as offline (similar to `TimelineClip.isOffline`).

### 12.3 Preset Persistence

User presets are stored in a dedicated file in the app's Documents directory:

```
Documents/
├── projects/
│   └── ... (existing project storage)
├── presets/
│   └── color_presets.json     ← user-saved color presets
└── LUTs/
    └── ... (custom LUT files)
```

```dart
// color_presets.json
{
  "presets": [
    {
      "id": "preset-uuid",
      "name": "My Cinematic Look",
      "description": "Teal shadows, warm highlights",
      "grade": { /* full ColorGrade JSON */ },
      "source": "user",
      "category": "cinematic",
      "thumbnailBase64": "iVBORw0KGgo...",
      "createdAt": "2026-02-06T12:00:00Z"
    }
  ]
}
```

### 12.4 Undo/Redo Integration

Color grade changes participate in the existing undo/redo system via the `KeyframeManager`'s snapshot pattern:

```dart
// Each color grade change creates an immutable snapshot
void updateColorGrade(ColorGrade newGrade) {
  final snapshot = TimelineSnapshot(
    colorGrades: {..._colorGrades, clipId: newGrade},
    // ... other timeline state
  );
  _undoStack.push(snapshot);
}
```

Since `ColorGrade` is `@immutable`, snapshots are cheap (reference sharing for unchanged data).

---

## 13. Edge Cases

### 13.1 HDR Content

| Scenario | Handling |
|---|---|
| HDR source + SDR export | Convert to SDR via tone mapping before color grading |
| SDR source + HDR export | Apply color grade in extended sRGB, encode as HLG |
| Mixed HDR/SDR clips | Normalize to working color space before grading |
| CIFilter clipping | Use `CIContext` with `.workingColorSpace: .extendedLinearSRGB` to avoid clipping highlights |

### 13.2 Different Color Spaces

```swift
// Before applying CIFilter chain, normalize to working color space
func normalizeColorSpace(image: CIImage) -> CIImage {
    let workingSpace = CGColorSpace(name: CGColorSpace.linearSRGB)!
    return image.matchedToWorkingSpace(workingSpace) ?? image
}
```

Handle:
- **Rec.709** (most consumer video): Direct processing in sRGB
- **Rec.2020** (HDR): Process in extended linear sRGB, convert back for output
- **P3 (iPhone footage)**: Convert to sRGB for processing, back to P3 for display
- **ProRes Log**: Apply log-to-linear conversion before grading

### 13.3 Timeline with 10+ Clips

Each clip can have its own independent `ColorGrade`. Performance considerations:

- CIFilter chain instances are **per-clip** but filters are lightweight (just parameter containers)
- During playback, only the **active clip's** filter chain is applied (single clip visible at a time)
- During export, filter chains are created once per clip and reused for all frames in that clip
- Color grade parameters are sent to native only when the active clip changes or parameters change

### 13.4 Undo/Redo with Color Grades

- Color grade changes are atomic (entire `ColorGrade` snapshot per undo step)
- Adding/removing color keyframes are separate undo operations
- LUT changes (apply/remove) are undo-able
- Preset application is a single undo step (restores previous grade)

### 13.5 Clip Split with Color Grade

When a clip is split (existing `VideoClip.splitAt()`), both resulting clips inherit the same `colorGradeId` and color keyframes are partitioned:

```dart
// In VideoClip.splitAt() - color keyframe partitioning
// (mirrors existing transform keyframe partitioning)
final leftColorKfs = colorKeyframes
    .where((kf) => kf.timestamp.inMicroseconds < offsetMicros)
    .toList();

final rightColorKfs = colorKeyframes
    .where((kf) => kf.timestamp.inMicroseconds >= offsetMicros)
    .map((kf) => kf.copyWith(
      timestamp: Duration(
        microseconds: kf.timestamp.inMicroseconds - offsetMicros,
      ),
    ))
    .toList();
```

### 13.6 Memory Pressure

When the system signals memory pressure:
1. Release LUT filter caches (they can be re-parsed from disk)
2. Release preview CIFilter chain (rebuilt on next parameter change)
3. Keep only the current clip's color grade in memory
4. Release histogram caches (recomputed on demand)

---

## 14. Performance

### 14.1 Performance Budgets

| Operation | Target | Notes |
|---|---|---|
| CIFilter chain (preview) | < 8ms per frame | GPU-accelerated via Metal |
| CIFilter chain (export) | < 16ms per frame | Can be slightly slower than preview |
| LUT parsing (.cube file) | < 200ms | One-time on import, cached as binary |
| LUT application (CIColorCube) | < 2ms per frame | GPU texture lookup |
| Histogram computation (10 frames) | < 500ms | Background thread |
| Color match algorithm | < 1s total | Histogram + LUT generation |
| Color grade parameter update | < 1ms | Dart-side immutable copy |
| Platform channel round-trip | < 2ms | Parameter map serialization |
| Curve evaluation (256 samples) | < 0.1ms | Monotone cubic, pre-computed |
| Color keyframe interpolation | < 0.5ms | Per-parameter lerp |

### 14.2 GPU Rendering Strategy

All CIFilter operations run on the GPU via Metal:

```swift
// Create Metal-backed CIContext (done once at init)
let device = MTLCreateSystemDefaultDevice()!
let ciContext = CIContext(mtlDevice: device, options: [
    .cacheIntermediates: false,  // Save GPU memory
    .name: "ColorGrading",
])

// The CIFilter chain compiles to a single Metal shader at render time
// (CIFilter chain fusion - iOS optimizes multiple filters into one pass)
```

Key optimization: CIFilter chain fusion. When multiple CIFilters are chained, iOS compiles them into a single Metal compute kernel, avoiding intermediate texture allocations.

### 14.3 Memory Budget

| Component | Budget | Notes |
|---|---|---|
| CIFilter chain (reusable instances) | ~2 KB | 12 filter instances, parameter data only |
| LUT data (single 33x33x33 RGBA) | ~562 KB | 33^3 * 4 * 4 bytes (float RGBA) |
| LUT cache (max 3 active) | ~1.7 MB | Preview + export + one spare |
| LUT thumbnails (20 cached) | ~400 KB | 20 * ~20KB JPEG thumbnails |
| Curve lookup tables (4 channels) | ~4 KB | 4 * 256 * 4 bytes |
| Histogram data (per clip) | ~3 KB | 3 channels * 256 bins * 4 bytes |
| Preview pixel buffer pool | ~8 MB | 2 buffers at 1080p BGRA |
| **Total** | ~11 MB | Well within 200MB app budget |

### 14.4 Optimization Techniques

1. **Dirty flag system**: Only rebuild CIFilters for changed parameters (not the entire chain)
2. **Filter chain fusion**: Let iOS fuse the chain into a single GPU pass
3. **Pixel buffer pool**: Pre-allocate output buffers to avoid allocation per frame
4. **Parameter batching**: Batch multiple slider changes into a single native update
5. **Lazy LUT loading**: Parse .cube files only when first selected, not at app launch
6. **Thumbnail generation**: Generate LUT preview thumbnails on a background queue
7. **Export optimization**: Pre-sample color keyframes to avoid interpolation in export compositor

---

## 15. Bundled LUT Library

### 15.1 LUT Categories and Entries

| Category | LUT Name | Description | Dimension |
|---|---|---|---|
| **Cinematic** | Teal & Orange | Classic blockbuster color contrast | 33 |
| | Film Noir | High contrast B&W with deep blacks | 33 |
| | Golden Hour | Warm golden tones, lifted shadows | 33 |
| | Moonlight | Cool blue nighttime look | 33 |
| | Blockbuster | Desaturated with crushed blacks | 33 |
| | Anamorphic | Warm amber highlights, cool shadows | 33 |
| **Vintage** | Polaroid | Faded with warm cast | 33 |
| | Kodak Portra 400 | Natural skin tones, soft pastels | 33 |
| | Fuji Superia | Green-tinted shadows, warm highlights | 33 |
| | Cross Process | Shifted colors, high saturation | 33 |
| | Faded Film | Lifted blacks, desaturated | 33 |
| | 70s Warm | Heavy warm tint, low contrast | 33 |
| **Black & White** | Classic B&W | Standard desaturation | 33 |
| | High Contrast B&W | Punchy blacks and whites | 33 |
| | Sepia | Warm brown tone | 33 |
| | Silver | Cool-toned monochrome | 33 |
| **Portrait** | Soft Glow | Reduced clarity, warm skin tones | 33 |
| | Beauty | Smooth contrast, vibrant but natural | 33 |
| | Matte | Lifted blacks, reduced contrast | 33 |
| **Landscape** | Vivid Nature | Boosted greens and blues | 33 |
| | Sunrise | Warm oranges and pinks | 33 |
| | Overcast | Cool, desaturated, moody | 33 |
| **Social** | Clean Pop | Bright, slightly lifted, vibrant | 33 |
| | Warm Glow | Soft warm filter | 33 |
| | Cool Tone | Slightly desaturated cool look | 33 |
| | Dreamy | Soft contrast, pastel shift | 33 |

**Total: 25 bundled LUTs** (~14 MB uncompressed, ~4 MB compressed in app bundle)

### 15.2 LUT Manifest

```json
// ios/Runner/Assets/LUTs/manifest.json
{
  "version": 1,
  "luts": [
    {
      "id": "builtin_teal_orange",
      "name": "Teal & Orange",
      "filename": "cinematic/teal_orange.cube",
      "category": "cinematic",
      "dimension": 33,
      "description": "Classic blockbuster contrast between warm skin and cool backgrounds",
      "author": "Liquid Editor",
      "sortOrder": 0
    },
    // ... 24 more entries
  ]
}
```

### 15.3 LUT Thumbnail Generation

Thumbnails are generated lazily on first display using a reference frame from the current clip:

```swift
func generateLUTThumbnail(
    lutPath: String,
    referenceFrame: CVPixelBuffer,
    size: CGSize
) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: referenceFrame)
    let resized = ciImage.transformed(by: CGAffineTransform(
        scaleX: size.width / ciImage.extent.width,
        y: size.height / ciImage.extent.height
    ))
    let lut = parseCubeLUT(at: lutPath)
    let filter = createLUTFilter(from: lut, intensity: 1.0)
    filter.setValue(resized, forKey: kCIInputImageKey)
    guard let output = filter.outputImage else { return nil }
    let cgImage = ciContext.createCGImage(output, from: output.extent)!
    return UIImage(cgImage: cgImage)
}
```

---

## 16. Dependencies

### 16.1 Existing Dependencies (No Changes)

| Dependency | Role |
|---|---|
| AVFoundation | Video composition, export |
| Core Image (CIFilter) | All filter operations |
| Metal | GPU-accelerated CIContext |
| Flutter platform channels | Dart <-> Swift communication |

### 16.2 New Native Code Required

| File | Purpose | Estimated Lines |
|---|---|---|
| `ios/Runner/ColorGrading/ColorGradingService.swift` | Platform channel handler, orchestrator | ~300 |
| `ios/Runner/ColorGrading/CIFilterChain.swift` | Reusable filter chain with dirty flags | ~400 |
| `ios/Runner/ColorGrading/LUTParser.swift` | .cube file parser and CIColorCube builder | ~200 |
| `ios/Runner/ColorGrading/HistogramMatcher.swift` | Histogram computation and matching | ~250 |
| `ios/Runner/ColorGrading/VibranceKernel.swift` | Custom CIKernel for vibrance | ~50 |
| `ios/Runner/ColorGrading/HSLWheelKernel.swift` | Custom CIKernel for tonal range HSL | ~100 |

### 16.3 New Flutter Code Required

| File | Purpose | Estimated Lines |
|---|---|---|
| `lib/models/color_grade.dart` | ColorGrade, LUTFilter, HSLAdjustment, CurveData, ColorPreset models | ~500 |
| `lib/models/color_keyframe.dart` | ColorKeyframe model | ~100 |
| `lib/core/color_grade_controller.dart` | State management, parameter throttling, native bridge | ~400 |
| `lib/core/color_interpolator.dart` | Per-parameter color keyframe interpolation | ~200 |
| `lib/views/color_grading/color_grading_panel.dart` | Main panel with tab navigation | ~300 |
| `lib/views/color_grading/adjustments_panel.dart` | Slider-based adjustments | ~250 |
| `lib/views/color_grading/filters_panel.dart` | LUT browser and intensity slider | ~300 |
| `lib/views/color_grading/curves_editor.dart` | Curves canvas with control points | ~500 |
| `lib/views/color_grading/hsl_wheels_panel.dart` | Three color wheels + luminance sliders | ~400 |
| `lib/views/color_grading/vignette_panel.dart` | Vignette controls | ~100 |
| `lib/views/color_grading/before_after_view.dart` | Comparison mode widget | ~200 |
| `lib/views/color_grading/preset_sheet.dart` | Preset save/load UI | ~200 |

### 16.4 VideoClip Model Changes

The existing `VideoClip` class (`lib/models/clips/video_clip.dart`) requires the following additions:

```dart
class VideoClip extends MediaClip {
  final List<Keyframe> keyframes;              // EXISTING
  final List<ColorKeyframe> colorKeyframes;    // NEW
  final String? colorGradeId;                  // NEW
  final String? name;                          // EXISTING
  // ... all existing methods unchanged ...
  // ... new color keyframe methods (addColorKeyframe, removeColorKeyframe, etc.)
}
```

### 16.5 New Platform Channel Methods

Register on `com.liquideditor/color_grading` channel:

| Method | Direction | Parameters | Returns |
|---|---|---|---|
| `updateColorGrade` | Flutter -> Native | `{clipId, params}` | void |
| `parseCubeLUT` | Flutter -> Native | `{path}` | `{dimension, title, valid}` |
| `generateLUTThumbnail` | Flutter -> Native | `{lutPath, frameData, width, height}` | Base64 JPEG |
| `matchColor` | Flutter -> Native | `{sourceAsset, targetAsset, timeRanges}` | ColorGrade params map |
| `computeHistogram` | Flutter -> Native | `{assetPath, startMs, endMs}` | Histogram data |
| `initPreview` | Flutter -> Native | `{}` | textureId |
| `disposePreview` | Flutter -> Native | `{}` | void |

---

## 17. Implementation Plan

### Phase 1: Core Infrastructure (Week 1-2)

**Goal:** Data models, native CIFilter pipeline, basic adjustments panel.

| Task | Est. Hours | Priority |
|---|---|---|
| Create `ColorGrade`, `LUTFilter`, `HSLAdjustment`, `CurveData` models | 8 | P0 |
| Create `ColorKeyframe` model | 3 | P0 |
| Extend `VideoClip` with `colorGradeId` and `colorKeyframes` | 4 | P0 |
| Implement `CIFilterChain` (native Swift) with parameter mapping | 12 | P0 |
| Implement `ColorGradingService` platform channel handler | 6 | P0 |
| Build real-time preview pipeline (Flutter Texture + native renderer) | 10 | P0 |
| Create `ColorGradeController` (Dart state management) | 8 | P0 |
| Build adjustments panel UI (13 sliders with CupertinoSlider) | 6 | P0 |
| Unit tests for models (serialization, identity, copyWith) | 4 | P0 |
| Integration test: adjust slider -> see preview change | 4 | P0 |

**Deliverable:** User can select a clip, open color panel, adjust exposure/brightness/contrast/saturation/temperature and see real-time preview.

### Phase 2: LUT System & Filters (Week 3-4)

**Goal:** LUT parsing, bundled library, custom import, filter browser UI.

| Task | Est. Hours | Priority |
|---|---|---|
| Implement `LUTParser.swift` (.cube parser + validation) | 6 | P0 |
| Create `CIColorCubeWithColorSpace` integration with intensity blending | 6 | P0 |
| Create 25 bundled LUT .cube files (generate or license) | 12 | P0 |
| Build LUT manifest and bundle integration | 3 | P0 |
| Build filters panel UI (horizontal grid + intensity slider) | 8 | P0 |
| Implement LUT thumbnail generation pipeline | 6 | P1 |
| Implement custom LUT import (file picker + validation + storage) | 6 | P1 |
| Unit tests for LUT parser (valid .cube, invalid, edge cases) | 4 | P0 |

**Deliverable:** User can browse bundled filters, apply LUT with intensity control, import custom .cube files.

### Phase 3: Advanced Grading (Week 5-7)

**Goal:** Curves editor, HSL wheels, vignette, vibrance kernel.

| Task | Est. Hours | Priority |
|---|---|---|
| Implement curves editor canvas (CustomPainter) | 12 | P0 |
| Implement control point interaction (drag, add, delete) | 8 | P0 |
| Implement monotone cubic interpolation (Fritsch-Carlson) | 4 | P0 |
| Build curve-to-CIFilter conversion (256-sample LUT) | 6 | P0 |
| Implement HSL wheel widget (CustomPainter) | 10 | P0 |
| Implement HSL-to-CIFilter mapping (tonal range masking) | 8 | P0 |
| Implement `VibranceKernel` (custom CIColorKernel) | 3 | P1 |
| Build vignette panel UI | 3 | P1 |
| Implement clarity filter (CIUnsharpMask with large radius) | 2 | P1 |
| Implement whites/blacks via CIToneCurve endpoint adjustment | 3 | P1 |
| Unit tests for curve interpolation | 4 | P0 |
| Unit tests for HSL polar/cartesian conversion | 3 | P0 |

**Deliverable:** Full professional grading toolkit with curves, wheels, vignette.

### Phase 4: Integration & Polish (Week 8-9)

**Goal:** Export integration, keyframes, presets, color match, before/after.

| Task | Est. Hours | Priority |
|---|---|---|
| Integrate CIFilter pipeline into `VideoProcessingService` export | 10 | P0 |
| Implement color keyframe interpolation (`ColorInterpolator`) | 8 | P0 |
| Implement color keyframe UI (add/remove/navigate on timeline) | 6 | P0 |
| Export: pre-sample color keyframes at export FPS | 4 | P0 |
| Implement before/after comparison (split, toggle, swipe) | 6 | P1 |
| Implement color match (histogram computation + matching) | 10 | P1 |
| Implement preset save/load UI | 6 | P1 |
| Build 10 built-in presets (combinations of adjustments + LUTs) | 4 | P2 |
| Implement clip split color keyframe partitioning | 3 | P1 |
| HDR color space handling in CIFilter pipeline | 6 | P1 |
| Performance profiling and optimization | 8 | P0 |
| End-to-end test: grade clip -> export -> verify output | 6 | P0 |
| Update documentation (DESIGN.md, APP_LOGIC.md, FEATURES.md) | 4 | P0 |

**Deliverable:** Production-ready color grading system with export, keyframes, presets, and color match.

### Total Estimated Effort

| Phase | Hours | Weeks |
|---|---|---|
| Phase 1: Core Infrastructure | ~65 | 2 |
| Phase 2: LUT System & Filters | ~51 | 2 |
| Phase 3: Advanced Grading | ~66 | 2.5 |
| Phase 4: Integration & Polish | ~81 | 2.5 |
| **Total** | **~263** | **~9** |

### Risk Mitigation

| Risk | Mitigation |
|---|---|
| CIFilter chain > 8ms budget | Profile early; fuse filters, reduce chain length, lower preview resolution |
| Custom CIKernel deprecation (iOS 16+) | Use `CIColorKernel` API which remains supported; fallback to Metal shaders |
| LUT file compatibility | Validate .cube format strictly; reject 1D LUTs, non-standard headers |
| Memory pressure from LUT data | Lazy load, evict inactive LUTs, compress in bundle |
| Color space mismatch artifacts | Normalize to working color space at pipeline entry, convert back at exit |
| Keyframe interpolation visual artifacts | Use monotone interpolation for curves; clamp all parameters to valid ranges |

---

**End of Document**

*Last Updated: 2026-02-06*

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Senior Architect)
**Date:** 2026-02-06

### Architecture Assessment

**Overall Rating: 7.5/10 -- Strong design with several critical gaps that need resolution before implementation.**

The document demonstrates a thorough understanding of professional color grading workflows and CIFilter capabilities. The CIFilter pipeline order is well-reasoned (matching DaVinci Resolve's node paradigm), the data models are appropriately immutable, and the performance-conscious design (dirty flags, filter chain reuse, pixel buffer pools) is sound. However, the document has significant misalignment with the actual codebase's dual-model architecture and some technical inaccuracies in the CIFilter API usage that must be resolved.

**Architecture Strengths:**
- Immutable `ColorGrade` model with comprehensive parameter coverage
- CIFilter chain order is professionally correct (exposure first, then temperature, tones, color controls, LUT, sharpness last)
- Dirty flag optimization system for selective filter rebuilds
- Separate `ColorGradingService` as a new native service (good SRP)
- LUT system with proper `.cube` parsing and `CIColorCubeWithColorSpace` usage
- Color keyframe system that parallels (but doesn't bloat) the existing transform keyframe model
- Memory budget analysis is thorough and realistic (~11 MB total)

**Architecture Weaknesses:**
- Dual clip model confusion (V1 `TimelineClip` in `lib/models/timeline_clip.dart` vs V2 `VideoClip` in `lib/models/clips/video_clip.dart` vs UI `TimelineClip` in `lib/timeline/data/models/timeline_clip.dart`)
- Export pipeline integration proposes an API that does not exist in the current `VideoProcessingService.swift`
- `SmartEditViewModel` ownership model for `ColorGradeController` is loosely specified
- Platform channel naming inconsistency (doc references both `com.liquideditor/video_processing` and `com.liquideditor/color_grading`)

### Codebase Verification

**Files Reviewed:**

| File | Purpose | Alignment with Design |
|------|---------|----------------------|
| `ios/Runner/VideoProcessingService.swift` | Native export pipeline | MISMATCH: Uses `AVMutableVideoComposition` with layer instructions, NOT custom compositor closure API |
| `lib/models/clips/video_clip.dart` (V2) | Clip model | PARTIAL: Has `keyframes` but no `colorKeyframes` or `colorGradeId` -- fields must be added |
| `lib/models/timeline_clip.dart` (V1) | Legacy clip model | NOT ADDRESSED: Design does not mention this model but `SmartEditViewModel` actually uses it |
| `lib/timeline/data/models/timeline_clip.dart` | UI rendering clip | MISMATCH: Has `hasEffects` but not `hasColorGrade` as proposed |
| `lib/models/keyframe.dart` | Keyframe + InterpolationType | ALIGNED: 21 interpolation types confirmed, `BezierControlPoints` exists |
| `lib/core/timeline_manager.dart` | Timeline operations | ALIGNED: O(1) undo/redo via pointer swap confirmed |
| `lib/views/smart_edit/smart_edit_view_model.dart` | Editor state | RISK: Uses `ClipManager` with V1 `TimelineClip`, not V2 `VideoClip` |
| `docs/DESIGN.md` | Architecture overview | ALIGNED: Platform channel pattern confirmed |

**Critical Finding: Three Clip Models Exist**

The codebase has three distinct clip models that the design document does not adequately reconcile:

1. **V1 `TimelineClip`** (`lib/models/timeline_clip.dart`): Mutable, used by `SmartEditViewModel` and `ClipManager`. Has `sourceVideoPath`, `sourceInPoint`, `sourceOutPoint`, mutable `keyframes` list, `orderIndex`.

2. **V2 `VideoClip`** (`lib/models/clips/video_clip.dart`): Immutable `@immutable`, used by `PersistentTimeline` and `TimelineManager`. Has `mediaAssetId`, `sourceInMicros`, `sourceOutMicros`, immutable `keyframes` list.

3. **UI `TimelineClip`** (`lib/timeline/data/models/timeline_clip.dart`): Immutable `@immutable`, used for timeline UI rendering. Has `hasEffects`, `hasKeyframes`, `hasAudio` metadata flags.

The design document proposes adding `colorGradeId` and `colorKeyframes` to V2 `VideoClip` and `hasColorGrade` to the UI `TimelineClip`, but the `SmartEditViewModel` (the actual editor state manager) uses V1 `TimelineClip` for its clip operations, not V2. The `ColorGradeController` is proposed as owned by `SmartEditViewModel`, which means the color grading system will need to bridge between V1 clips (which `SmartEditViewModel` works with) and V2 clips (which the design proposes to extend).

**Critical Finding: Export Pipeline Mismatch**

The design document's Section 10.1 proposes using `AVMutableVideoComposition(asset:) { request in ... }` -- the closure-based custom compositor API. However, the existing `VideoProcessingService.renderComposition()` (lines 335-550) uses the traditional approach:
- `AVMutableVideoComposition()` with `.instructions` array
- `AVMutableVideoCompositionInstruction` with `AVMutableVideoCompositionLayerInstruction`
- `setTransformRamp(fromStart:toEnd:timeRange:)` for keyframe transforms

The closure-based API (`AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)`) is fundamentally different and CANNOT coexist with layer instructions in the same video composition. This means the export pipeline requires a complete rewrite, not an extension, of the existing `renderComposition()` method. The design must explicitly acknowledge this as a breaking change to the export system.

### Critical Issues

**C1: Dual Clip Model -- Which Model Gets Color Grading?**

The design proposes extending V2 `VideoClip` with `colorGradeId` and `colorKeyframes`, but the active editor (`SmartEditViewModel`) operates on V1 `TimelineClip` via `ClipManager`. Color grading parameters must be accessible during editing (when V1 is in use) and during export (when V2 may be used).

**Resolution Required:** Either:
- (a) Add color grading fields to V1 `TimelineClip` as well, with sync logic to V2 on save/export
- (b) Migrate `SmartEditViewModel` to use V2 `VideoClip` exclusively before implementing color grading
- (c) Store color grades in a separate store keyed by clip ID (partially proposed with `colorGradeId` but the design mixes direct embedding with reference)

**Recommendation:** Option (c) with a dedicated `ColorGradeStore` (Map<String, ColorGrade>) that is model-agnostic. Both V1 and V2 clips reference grades by ID only. This decouples color grading from the clip model migration.

**C2: Export Pipeline Requires Rewrite, Not Extension**

As noted above, the closure-based `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)` is incompatible with the existing layer-instruction-based composition. The current export pipeline handles keyframe transforms via `setTransformRamp()`, which is ONLY available through `AVMutableVideoCompositionLayerInstruction`.

To apply both transforms AND CIFilters, you need `AVVideoCompositing` (custom compositor protocol) which gives you access to both the source frames (for CIFilter application) and the composition request (for transform handling). The design does not mention `AVVideoCompositing` at all.

**Resolution Required:** The export pipeline must either:
- (a) Implement `AVVideoCompositing` protocol (custom compositor) that handles both transforms and color grading
- (b) Apply transforms AS CIFilters (e.g., `CIAffineTransform`) in the closure-based API, abandoning `setTransformRamp`
- (c) Use a two-pass export (first apply transforms, then apply color grading) -- unacceptable for performance

**Recommendation:** Option (a). Implement a custom `AVVideoCompositing` class that receives `AVAsynchronousVideoCompositionRequest`, extracts source frames, applies transform + CIFilter chain, and finishes the request. This is the industry-standard approach for professional video editors.

**C3: `CIColorKernel` Is Deprecated (iOS 15+) -- Vibrance and HSL Kernels at Risk**

The design proposes `CIColorKernel(source:)` for the vibrance filter (Section 4.3) and implies custom kernel usage for HSL tonal range masking (Section 4.4, 8.5). `CIColorKernel` with OpenGL Shading Language (GLSL-like) source strings was deprecated in iOS 12 and removed from the modern API path. On iOS 15+ (this project's minimum target), the recommended approach is `CIKernel(functionName:fromMetalLibraryData:)` using Metal Shading Language.

**Resolution Required:**
- Rewrite vibrance kernel as a Metal shader compiled into a `.metallib`
- Rewrite HSL tonal range masking as a Metal shader
- OR implement vibrance using existing CIFilters (e.g., selective `CIColorControls` with luminance masking via `CIBlendWithMask`)
- OR use `CIFilter.registerName()` to register custom Metal-backed filters

**Recommendation:** Use Metal shaders compiled at build time via `.metal` files in the Xcode project. This avoids runtime compilation and is the modern path.

**C4: Platform Channel Naming Inconsistency**

The design references TWO different channel names:
- Section 1 (Integration Points table): `com.liquideditor/video_processing` for new methods `applyColorGrade`, `previewColorGrade`, `parseLUT`
- Section 3.1 (Component Diagram) and Section 16.5: `com.liquideditor/color_grading` as the channel name

This is contradictory. Other design documents in this project (text-titles, audio) have been advised to consolidate onto the existing `com.liquideditor/video_processing` channel OR create clearly separated channels.

**Resolution Required:** Pick one:
- Add to existing `com.liquideditor/video_processing` (simpler, fewer channels)
- Create `com.liquideditor/color_grading` (better separation, more method names)

**Recommendation:** Create `com.liquideditor/color_grading` as a dedicated channel. Color grading has 7+ methods and its own preview lifecycle, which justifies separation. But remove the conflicting reference in Section 1.

### Important Issues

**I1: LUT Intensity Blending Implementation Is Incorrect**

Section 5.4 proposes using `CIColorMatrix` to adjust the alpha channel and then `CISourceOverCompositing` to blend the LUT result with the original. This will NOT produce correct intensity blending because:
- Adjusting alpha only affects compositing behavior, not the color values
- `CISourceOverCompositing` with reduced alpha would blend against the background, not the original image

The correct approach for LUT intensity blending is:
```swift
// Use CIMix (not built-in) or implement as:
// output = original * (1 - intensity) + lutResult * intensity
// Via CIBlendWithAlphaMask with a constant-color mask,
// or via a simple CIColorKernel/Metal shader that does linear interpolation
```

Alternatively, interpolate the LUT data itself: for each entry in the LUT cube, lerp between identity (input=output) and the LUT value based on intensity. This produces a new LUT that can be applied at full strength.

**I2: Color Match Algorithm Returns Editable Parameters -- Lossy by Design**

Section 11.3 proposes converting histogram match LUTs into approximate `ColorGrade` parameters for editability. While the intent is good (users can tweak the result), fitting a 256-entry per-channel LUT to ~13 parametric sliders is inherently very lossy. A teal-orange grade cannot be represented by exposure + contrast + temperature alone.

The design mentions a "residual LUT" to capture what the parametric approximation missed, but this is vaguely specified. How is the residual LUT stored? Is it a separate `LUTFilter` applied after the parametric adjustments? How does it interact with further user edits?

**Recommendation:** Make the color match result a `LUTFilter` (3D LUT) by default, with an optional "Decompose to Parameters" action that performs the lossy conversion. This gives accurate results by default and editable results on demand.

**I3: `CurveData.evaluate()` -- Monotone Cubic Body Is Omitted**

Section 2.4 shows `double evaluate(double input) { /* Fritsch-Carlson monotone cubic */ }` with the implementation omitted. This is fine for a design doc, but Section 7.5 then proposes sampling the curve at 256 points and using `CIColorCube` (a 3D LUT) to represent a 1D curve. This is overkill and wastes resources.

For per-channel curves:
- Curves with 5 or fewer points: use `CIToneCurve` directly (it takes 5 control points)
- Curves with more than 5 points: sample to a 256-entry 1D lookup and use `CIColorMap` (not `CIColorCube` which is 3D)

The design incorrectly uses `CIColorCube` (Section 7.5, line 934) for what is fundamentally a 1D operation. A 256x1x1 cube is wasteful. Use `CIColorMap` with a 256x1 gradient image instead.

**I4: Before/After Preview Needs Two Separate Render Paths**

Section 6.4 mentions "two `CIImage` renderers: one with filter chain, one without" but does not address the performance cost. During before/after split view, you need to render TWO frames per display frame: one original, one graded. At 60fps with an 8ms budget per frame, you need 16ms total -- which exceeds the 16.67ms frame budget.

**Recommendation:** For split-screen mode, render a single frame, split it geometrically, and apply the CIFilter chain only to the "after" half. CIFilter operations work on sub-regions via `CIImage.cropped(to:)`, so you can avoid rendering the full filter chain on both halves.

**I5: `ColorKeyframe` Stores Full `ColorGrade` Snapshot -- Memory Concern**

Each `ColorKeyframe` (Section 2.6) stores a complete `ColorGrade` object. With 13 doubles, 3 `HSLAdjustment`s, 4 `CurveData` (each with up to 16 points), a `LUTFilter`, and metadata, each `ColorGrade` is roughly 500-800 bytes. With 20+ keyframes per clip and multiple clips, this could consume significant memory and make serialization verbose.

**Recommendation:** Consider a delta-based approach where keyframes store only the parameters that differ from the clip's base `ColorGrade`. Alternatively, accept the memory cost (it is within the budget) but add compression for serialization (e.g., only serialize non-default values).

**I6: No Cancellation Protocol for Long-Running Native Operations**

Section 16.5 defines platform channel methods like `matchColor` and `computeHistogram` that can take 500ms-1s. There is no cancellation mechanism. If the user navigates away from the color grading panel or selects a different clip during computation, the result will be stale.

**Recommendation:** Add a `cancelOperation` method to the platform channel, and use operation IDs to correlate requests with responses. The native side should check for cancellation between frame sampling iterations.

### Minor Issues

**M1: `isIdentity` Uses Floating-Point Equality**

`ColorGrade.isIdentity` (Section 2.1, line 144) compares doubles with `==` (e.g., `exposure == 0.0`). Floating-point equality is fragile, especially after serialization round-trips (JSON parse introduces floating-point noise). The existing `VideoTransform.isIdentity` correctly uses epsilon comparison (`(scale - 1.0).abs() < 0.001`).

**Recommendation:** Use epsilon-based comparison for all double comparisons in `isIdentity`.

**M2: `CITemperatureAndTint` Parameter Mapping Is Oversimplified**

Section 4.2 maps temperature to `inputNeutral` as a linear 2000K-10000K range. `CITemperatureAndTint` actually takes a `CIVector` for `inputNeutral` with (temperature, tint) as Kelvin values, and `inputTargetNeutral` with the target. The mapping should set `inputNeutral` to the measured color temperature (e.g., 6500K) and `inputTargetNeutral` to the user's desired shift. The current description is vague on this.

**M3: Missing `toJson`/`fromJson` for Several Models**

The design shows `// copyWith, toJson, fromJson omitted for brevity` for `ColorGrade` and does not show serialization for `HSLAdjustment`, `CurveData`, or `CurvePoint`. While this is fine for a design document, the persistence section (12.1) shows the expected JSON structure. Ensure the serialization code handles all edge cases, especially `CurveData.points` which is a list of objects.

**M4: Missing Error Handling in LUT Parser**

Section 5.2 shows `parseCubeLUT()` that throws `LUTParseError.invalidDimension` but does not handle:
- Malformed float values in data lines
- Missing `LUT_3D_SIZE` header
- Data count mismatch (too few or too many lines)
- Very large LUT dimensions (e.g., 128x128x128 = ~32MB)
- 1D LUTs (the `.cube` format supports both; design should explicitly reject)

**M5: UI Sliders Use `ListView` -- Should Use `CupertinoScrollbar`**

Section 6.2 wraps sliders in a `ListView`. Per CLAUDE.md requirements, all UI must use native iOS 26 Liquid Glass components. The `ListView` should be wrapped with `CupertinoScrollbar` for native scroll indicators, and section dividers should use `CupertinoListSection` styling.

**M6: Vignette Parameters Need Clarification**

`vignetteRadius` is documented as "0.0 to 2.0 (normalized from center)" but `CIVignette` accepts `inputRadius` as a float where the meaning depends on the image size. The mapping between the normalized value and `CIVignette`'s input needs to be specified.

**M7: Thumbnail Storage as Base64 in Presets**

Section 2.5 stores preset thumbnails as `thumbnailBase64`. For a typical 100x56 JPEG, this is ~20KB encoded. With 25+ bundled presets and user presets, this bloats the JSON. Consider storing thumbnails as separate files and referencing by path.

### Questions

**Q1:** The `SmartEditViewModel` currently uses `ClipManager` with V1 `TimelineClip`, but the V2 architecture uses `TimelineManager` with `PersistentTimeline`. Is there a planned migration, and should color grading wait for that migration to avoid implementing against a soon-to-be-deprecated model?

**Q2:** How does color grading interact with the existing `CompositionPlaybackController`? The controller currently uses `AVMutableComposition` for seamless multi-clip playback. Will the color grading preview use a separate native rendering pipeline (the proposed `ColorGradeTextureHandler`) or integrate into the existing composition player?

**Q3:** The design proposes generating LUT thumbnails from "a reference frame from the current clip." When the user switches clips, do all 25+ LUT thumbnails regenerate? What is the expected latency for thumbnail regeneration, and is there a loading state?

**Q4:** How does the proposed `com.liquideditor/color_grading` channel registration integrate with `AppDelegate.swift`? The current `AppDelegate` registers channels in `application(_:didFinishLaunchingWithOptions:)`. Does the new channel follow the same pattern, or does `ColorGradingService` register its own channel?

**Q5:** For the `hold` interpolation type (instant jump) between color keyframes, is the expectation that the color grade changes abruptly, or is there a minimum crossfade duration to avoid visible flash?

**Q6:** The design mentions using `CIMix` filter (Section 5.4, line 664) with a comment "CIMix is not built-in." If it is not built-in, why reference it? This will confuse implementers.

### Positive Observations

1. **Comprehensive CIFilter mapping table** (Section 4.2) is an excellent implementation reference. Every parameter has a specific CIFilter name, input key, and value mapping documented. This will significantly reduce implementation guesswork.

2. **Filter chain optimization** (Section 4.6) with pre-allocated filter instances and dirty flags is a production-quality design. This avoids the common mistake of creating new CIFilter instances per frame.

3. **LUT URI scheme** (Section 12.2) with `bundled://` and `custom://` prefixes is a clean abstraction that handles storage location transparently.

4. **Clip split with color keyframe partitioning** (Section 13.5) correctly mirrors the existing transform keyframe partitioning pattern. This shows good awareness of existing code patterns.

5. **Memory pressure handling** (Section 13.6) with prioritized resource release is well-thought-out and follows iOS best practices for `didReceiveMemoryWarning`.

6. **Pre-sampling color keyframes for export** (Section 10.3) is smart -- avoids real-time interpolation in the time-critical export compositor.

7. **Phase-based implementation plan** with clear deliverables per phase and realistic hour estimates (~263 hours over 9 weeks).

8. **The `isIdentity` optimization** on `ColorGrade` allows the pipeline to skip the entire CIFilter chain when no grading is applied, which is an important performance optimization.

### Checklist Summary

| Criterion | Status | Notes |
|-----------|--------|-------|
| Data models complete and immutable | PASS (with M1 fix needed) | `ColorGrade`, `LUTFilter`, `HSLAdjustment`, `CurveData`, `ColorPreset`, `ColorKeyframe` all `@immutable` |
| CIFilter pipeline correctly specified | PARTIAL | Filter order correct; vibrance kernel uses deprecated API (C3); LUT blending incorrect (I1) |
| Codebase alignment | FAIL | Dual clip model not reconciled (C1); export pipeline mismatch (C2) |
| V1/V2 model integration clear | FAIL | Design references V2 `VideoClip` but `SmartEditViewModel` uses V1 `TimelineClip` (C1) |
| LUT support correctly specified | PASS | `.cube` parsing, `CIColorCubeWithColorSpace`, bundled library, custom import all well-designed |
| Performance budget realistic | PASS | 8ms CIFilter chain is achievable with Metal; memory budget ~11MB is within limits |
| Export pipeline integration | FAIL | Closure-based API incompatible with existing layer instructions (C2) |
| Keyframe integration | PASS | Parallel track design is clean; reuses existing `InterpolationType` |
| Edge cases covered | PASS | HDR, color space normalization, memory pressure, clip split, 10+ clips |
| UI uses Liquid Glass components | PARTIAL | `CupertinoSlider` specified; missing `CupertinoScrollbar`, `CupertinoListSection` (M5) |
| Platform channel protocol complete | PARTIAL | Methods listed but naming inconsistency (C4); missing cancellation (I6) |
| Undo/redo integration specified | PASS | Immutable snapshots, atomic operations |
| Persistence format complete | PASS | Full JSON schema with example |

### Recommended Priority for Resolution

| Priority | Issue | Effort |
|----------|-------|--------|
| **P0** | C1: Resolve dual clip model for color grading | Design decision (2h) |
| **P0** | C2: Design custom `AVVideoCompositing` for export | Design + prototype (8h) |
| **P0** | C3: Replace deprecated `CIColorKernel` with Metal shaders | Design change (1h) |
| **P1** | C4: Fix platform channel naming inconsistency | 15 min |
| **P1** | I1: Fix LUT intensity blending implementation | 1h redesign |
| **P1** | I3: Use `CIColorMap` instead of `CIColorCube` for 1D curves | 30 min redesign |
| **P1** | I4: Optimize before/after split rendering | 1h redesign |
| **P2** | I2: Clarify color match residual LUT design | 2h |
| **P2** | I5: Consider delta-based keyframe storage | 1h |
| **P2** | I6: Add cancellation protocol for native operations | 1h |

---

*Review 1 Complete. Forwarding to Review 2 for implementation viability and integration risk analysis.*

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06

### Codebase Verification Results

This review verified the design document against every key file in the codebase. The following table summarizes the verification of each major design assumption:

| Design Assumption | Verified Against | Actual State | Verdict |
|---|---|---|---|
| CIFilter chain can be applied during export via closure API | `VideoProcessingService.swift` lines 240-280, 446-499 | Both `renderVideo()` and `renderComposition()` use `AVMutableVideoCompositionInstruction` + `AVMutableVideoCompositionLayerInstruction` with `setTransformRamp()`. Zero CIFilter usage in export. | **INCOMPATIBLE** |
| `VideoClip` can be extended with `colorGradeId` and `colorKeyframes` | `lib/models/clips/video_clip.dart` (286 lines) | Immutable `@immutable` class with `keyframes: List<Keyframe>` and `name: String?`. Constructor, `copyWith`, `toJson`, `fromJson`, `splitAt`, `trimStart`, `trimEnd` all must be updated. ~15 methods need modification. | **VIABLE but invasive** |
| `TimelineManager` handles undo for color grade changes | `lib/core/timeline_manager.dart` lines 119-138 | `_execute()` pushes entire `PersistentTimeline` root to undo stack. Color grades stored on `VideoClip` (within the tree) automatically get O(1) undo via structural sharing. | **ALIGNED** |
| Keyframe system has 21 interpolation types | `lib/models/keyframe.dart` lines 113-147 | `InterpolationType` enum has exactly 21 values. `BezierControlPoints` class exists. `Keyframe` stores `VideoTransform`, `InterpolationType`, and optional `BezierControlPoints`. | **ALIGNED** |
| `CompositionBuilder` can support color grading during playback | `ios/Runner/Timeline/CompositionBuilder.swift` lines 366-390 | `buildVideoComposition()` creates `AVMutableVideoComposition` with `AVMutableVideoCompositionInstruction` and `setTransform(.identity, at: .zero)`. No `customVideoCompositorClass` is set. | **REQUIRES MIGRATION** |
| `CompositionPlayerService` can display color-graded frames | `ios/Runner/CompositionPlayerService.swift` | Uses `AVPlayer` with `AVPlayerLayer`. Video composition is set on `AVPlayerItem`. If `customVideoCompositorClass` is set on the video composition, AVPlayer will invoke the custom compositor during playback. | **VIABLE (post-migration)** |
| Existing CIFilter usage in codebase | All `*.swift` files | CIFilter used ONLY in `PeopleService.swift` (line 327: `CIAreaAverage`) and `ReIDExtractor.swift` (lines 270/285: `CIColorControls`, `CIExposureAdjust`). Both are for image analysis, not video rendering. | **NO EXISTING PIPELINE** |
| No existing Metal shaders in project | `ios/Runner/` | Zero `.metal` files. Zero `CIColorKernel` references. Zero `CIKernel` references. | **CONFIRMED: Greenfield** |
| AppDelegate channel registration pattern | `ios/Runner/AppDelegate.swift` lines 80-130 | `setupPlatformChannels(with:)` creates `FlutterMethodChannel` with `messenger`, sets call handler. Pattern is straightforward. New `ColorGradingService` would follow same pattern. | **ALIGNED** |
| `AVAssetExportSession` with custom compositor | Video effects R2 (verified externally) | `AVAssetExportSession` respects `videoComposition.customVideoCompositorClass`. Standard approach since iOS 9. | **CONFIRMED** |

### Integration Risk Assessment

#### Risk 1: CRITICAL -- Three Design Documents Propose Three Independent Custom Compositors

**Risk Level: CRITICAL (showstopper if not addressed before implementation)**

The color grading design (Section 10.1) proposes CIFilter-chain-based export rendering. However, two other design documents in this project propose their own `AVVideoCompositing` implementations:

1. **Video Effects** (`2026-02-06-video-effects-system-design.md`): Proposes `EffectVideoCompositor` (lines 881-920) implementing `AVVideoCompositing` with CIFilter chains for per-clip effects (blur, chroma key, etc.)
2. **Transitions** (`2026-02-06-transitions-system-design.md`): Proposes `TransitionCompositor` (lines 829-870) implementing `AVVideoCompositing` for cross-dissolve and other transitions between clips.
3. **Text & Titles** (`2026-02-06-text-titles-system-design.md`): Proposes `TextBehindSubjectCompositor` (line 1377) implementing `AVVideoCompositing` for text-behind-subject rendering.

**The fundamental constraint:** `AVMutableVideoComposition` accepts EXACTLY ONE `customVideoCompositorClass`. You cannot stack multiple custom compositors. This means all four systems (color grading, video effects, transitions, text overlays) must be rendered within a SINGLE unified compositor.

**Impact on Color Grading Design:** The color grading CIFilter chain cannot exist as an independent rendering pipeline. It must be integrated as a stage within whatever unified compositor the project adopts. The design document does not address this at all.

**Required Resolution:** A unified compositor architecture document that specifies:
- A single `UnifiedVideoCompositor: AVVideoCompositing` class
- Custom instruction protocol carrying per-clip effect chains, color grades, transition parameters, and text overlay data
- Rendering order: transforms -> color grading -> effects -> text -> transitions
- This is a cross-cutting architectural decision that affects ALL four design documents

#### Risk 2: HIGH -- Export Pipeline Rewrite Scope Is Larger Than Acknowledged

**Risk Level: HIGH**

R1 correctly identified the incompatibility between layer instructions and custom compositors (C2). However, the full scope of the rewrite is larger than the 8-hour estimate suggests:

**Current export architecture (3 separate paths):**
1. `VideoProcessingService.renderVideo()` (lines 172-330): Single-clip export with `setTransformRamp` layer instructions via `AVAssetExportSession`
2. `VideoProcessingService.renderComposition()` (lines 335-550): Multi-clip export with per-clip `setTransformRamp` layer instructions via `AVAssetExportSession`
3. `CompositionBuilder.build()` (lines 115-239): Playback composition with identity transform layer instructions

All three paths must migrate to the custom compositor pattern. This involves:
- Creating custom `AVVideoCompositionInstructionProtocol` conforming instructions (not `AVMutableVideoCompositionInstruction`)
- Reimplementing `setTransformRamp` behavior manually using `CIAffineTransform` in the compositor
- Handling per-clip keyframe interpolation at render time (previously handled by AVFoundation's built-in instruction system)
- Managing `CVPixelBuffer` pools for intermediate rendering

The Video Effects R2 (lines 3171-3177) already confirmed: "When `customVideoCompositorClass` is set on `AVMutableVideoComposition`, the standard `AVMutableVideoCompositionLayerInstruction` transforms are IGNORED. The custom compositor receives raw source pixel buffers and must handle ALL rendering including transforms."

**Estimated effort:** 20-30 hours for the unified compositor migration, not 8 hours for color grading alone.

#### Risk 3: HIGH -- V1/V2 Model Resolution Remains Unresolved

**Risk Level: HIGH**

R1 flagged three clip models (C1). This review verifies the state is unchanged:

**V1 `TimelineClip`** (`lib/models/timeline_clip.dart`):
- MUTABLE class (non-`@immutable`)
- Fields: `sourceVideoPath: String`, `sourceInPoint: Duration`, `sourceOutPoint: Duration`, `keyframes: List<Keyframe>` (mutable list), `isSelected: bool`, `isDragging: bool`
- Used by: `SmartEditViewModel`, `ClipManager` (the active editing pipeline)

**V2 `VideoClip`** (`lib/models/clips/video_clip.dart`):
- IMMUTABLE class (`@immutable`)
- Fields: `mediaAssetId: String`, `sourceInMicros: int`, `sourceOutMicros: int`, `keyframes: List<Keyframe>` (final), `name: String?`
- Used by: `PersistentTimeline`, `TimelineManager` (the V2 timeline architecture)

**UI `TimelineClip`** (`lib/timeline/data/models/timeline_clip.dart`):
- IMMUTABLE class (`@immutable`)
- Fields: `id`, `mediaAssetId`, `trackId`, `type`, `startTime`, `duration`, `sourceIn`, `sourceOut`, `speed`, `hasEffects`, `hasKeyframes`, `hasAudio`, `volume`, `isMuted`
- Used by: Timeline UI widgets

The design proposes adding `colorGradeId: String?` and `colorKeyframes: List<ColorKeyframe>` to V2 `VideoClip`. This is correct for the V2 architecture. However, the **active editor** (`SmartEditViewModel`) operates on V1 `TimelineClip`. Until V1 is deprecated or migrated, color grading must work with V1 clips too.

**R1's recommendation** (Option C: model-agnostic `ColorGradeStore` keyed by clip ID) is the safest path. This review endorses that recommendation with the following refinement:

```dart
/// Clip-agnostic color grade store
class ColorGradeStore extends ChangeNotifier {
  final Map<String, ColorGrade> _grades = {};       // clipId -> grade
  final Map<String, List<ColorKeyframe>> _keyframes = {}; // clipId -> keyframes

  ColorGrade? gradeForClip(String clipId) => _grades[clipId];
  // ... mutation methods with immutable snapshots for undo
}
```

Both V1 `TimelineClip.id` and V2 `VideoClip.id` are UUID strings, so the keying is compatible across models.

#### Risk 4: MEDIUM -- No Existing CIFilter Rendering Infrastructure

**Risk Level: MEDIUM**

The codebase has zero CIFilter-based video frame rendering. The only CIFilter usage is in `PeopleService.swift` (for area averaging) and `ReIDExtractor.swift` (for color/exposure analysis during tracking). Neither involves rendering to `CVPixelBuffer` or `MTLTexture`.

This means the color grading system requires building the entire CIFilter rendering infrastructure from scratch:
- Metal-backed `CIContext` creation and management
- `CVPixelBuffer` pool allocation and recycling
- `FlutterTexture` registration for zero-copy preview
- CIFilter chain construction and parameter caching

This is not a blocker, but increases the implementation estimate. The Video Effects design document already calls this out as greenfield (R2 line 2997). Color grading should NOT duplicate this infrastructure but should integrate with the effects system's compositor.

#### Risk 5: MEDIUM -- `CIColorKernel` Deprecation Confirmed (R1-C3 Validated)

**Risk Level: MEDIUM**

R1 flagged `CIColorKernel` deprecation (C3). This review confirms:
- Zero `.metal` files exist in `ios/Runner/`
- Zero `CIKernel` or `CIColorKernel` references exist anywhere in the native codebase
- The project has no Metal shader compilation pipeline configured in Xcode

The vibrance kernel (Section 4.3) and HSL tonal range masking kernel (Section 8.5) both require custom GPU code. The two viable approaches are:

**Option A: Metal Shader Library (recommended)**
- Create `ios/Runner/ColorGrading/Shaders/ColorGrading.metal`
- Compile via Xcode's build system into a `.metallib`
- Load at runtime via `CIKernel(functionName:fromMetalLibraryData:)`
- Pros: Best performance, modern API, compile-time shader validation
- Cons: Requires Metal Shading Language expertise, Xcode build integration

**Option B: CIFilter-Only Workaround (fallback)**
- Vibrance: Approximate using `CIColorControls` with selective saturation + luminance mask via `CIBlendWithMask`
- HSL Wheels: Use `CIColorMatrix` per tonal range with luminance-derived mask images generated via `CILinearGradient` + `CISmoothLinearGradient`
- Pros: No Metal shaders needed, standard CIFilter API
- Cons: Less precise vibrance, more filters in chain (performance cost), tonal range masking is approximate

**Recommendation:** Start with Option B for Phase 1 (basic adjustments). Add Metal shaders in Phase 3 (advanced grading) when vibrance and HSL precision matter. This derisks Phase 1 delivery.

### Critical Findings

**CF1: Unified Compositor Is the #1 Prerequisite**

The color grading system CANNOT be implemented in isolation. The export pipeline (Section 10) and preview pipeline (Section 9) both require a custom `AVVideoCompositing` implementation. This same compositor is needed by Video Effects, Transitions, and Text/Titles. Building four separate compositors is architecturally impossible (only one compositor class per video composition).

**Action Required:** Before implementing Phase 1 of color grading, the project needs a Unified Compositor Design Document that:
1. Defines a single `UnifiedCompositor: AVVideoCompositing` class
2. Defines a custom `CompositorInstruction: AVVideoCompositionInstructionProtocol` carrying all per-clip data
3. Specifies the rendering pipeline order: geometry transforms -> color grading -> video effects -> text overlays -> transition blending
4. Specifies the pixel buffer management strategy (pool sizing, format, color space)
5. Addresses the `CompositionBuilder.swift` migration (currently uses standard instructions)

This is a cross-cutting concern that blocks ALL four feature systems. Estimated design effort: 4-6 hours. Estimated implementation effort for the compositor skeleton: 16-24 hours.

**CF2: `VideoClip` Model Changes Cascade Through 15+ Methods**

Adding `colorGradeId` and `colorKeyframes` to `VideoClip` is not a simple field addition. The V2 `VideoClip` class has tightly coupled methods that must all be updated:

| Method | Lines | Change Required |
|---|---|---|
| Constructor | 27-34 | Add 2 new parameters with defaults |
| `splitAt()` | 61-110 | Partition `colorKeyframes` (mirroring transform keyframes) |
| `trimStart()` | 117-151 | Filter/adjust `colorKeyframes` timestamps |
| `trimEnd()` | 156-180 | Filter `colorKeyframes` beyond new end |
| `addKeyframe()` | 185-192 | No change (transform-specific) |
| `removeKeyframe()` | 195-202 | No change (transform-specific) |
| `updateKeyframe()` | 205-213 | No change (transform-specific) |
| `clearKeyframes()` | 216-223 | Consider: should this clear color keyframes too? |
| `copyWith()` | 228-244 | Add `colorKeyframes` and `colorGradeId` parameters |
| `duplicate()` | 247-254 | Include `colorKeyframes`, decide on `colorGradeId` inheritance |
| `toJson()` | 259-267 | Serialize `colorKeyframes` and `colorGradeId` |
| `fromJson()` | 270-280 | Deserialize `colorKeyframes` and `colorGradeId` |
| `toString()` | 283-284 | Optional: add color info |

Additionally, `TimelineManager.splitAt()` (lines 198-213) delegates to `VideoClip.splitAt()` and would automatically handle color keyframe partitioning if `VideoClip.splitAt()` is updated.

This is viable but must be done carefully to avoid breaking existing serialization (backward compatibility: existing projects without `colorKeyframes` must load correctly with empty defaults).

**CF3: LUT Intensity Blending (R1-I1) -- Concrete Fix Required**

R1 identified the LUT intensity blending as incorrect. This review provides the specific fix:

The correct approach uses `CIBlendWithAlphaMask` or a simple custom blend:

```swift
func applyLUTWithIntensity(original: CIImage, lutResult: CIImage, intensity: Float) -> CIImage {
    if intensity >= 0.999 { return lutResult }
    if intensity <= 0.001 { return original }

    // Option 1: Pre-blend the LUT data itself (best performance)
    // Modify each LUT entry: lut[i] = lerp(identity[i], lut[i], intensity)
    // This produces a new LUT that can be applied at full strength

    // Option 2: Post-blend via CIFilter (simpler, slightly more GPU cost)
    // Use CIBlendWithMask with a constant-value mask image
    let constantMask = CIImage(color: CIColor(red: CGFloat(intensity),
                                               green: CGFloat(intensity),
                                               blue: CGFloat(intensity)))
        .cropped(to: original.extent)

    let blend = CIFilter(name: "CIBlendWithMask")!
    blend.setValue(lutResult, forKey: kCIInputImageKey)
    blend.setValue(original, forKey: kCIInputBackgroundImageKey)
    blend.setValue(constantMask, forKey: "inputMaskImage")
    return blend.outputImage ?? lutResult
}
```

Option 1 (pre-blending LUT data) is preferred because it adds zero GPU cost at render time. The intensity-adjusted LUT can be precomputed when the slider changes and cached until the next change.

### Important Findings

**IF1: LUT Parser Data Array Size Calculation Is Correct but Fragile**

Section 5.2 (line 621) validates: `data.count == dimension * dimension * dimension * 4`. This is correct for RGBA float data. However, the parser silently appends `1.0` for alpha (line 616: `data.append(contentsOf: [values[0], values[1], values[2], 1.0])`). The `.cube` format specifies only RGB values per entry.

Potential issue: Some non-standard `.cube` files include alpha as a fourth column. The parser would interpret the alpha value as the Red of the NEXT entry, silently corrupting the LUT. The parser should explicitly check `values.count` and handle 3-value and 4-value lines differently.

Additionally, the `DOMAIN_MIN`/`DOMAIN_MAX` parsing (lines 607-611) incorrectly uses `compactMap { Float($0) }` on the split results, which would include "DOMAIN_MIN" as a failed parse (returns nil, gets filtered). The split should skip the first element: `trimmed.split(separator: " ").dropFirst().compactMap { Float($0) }`.

**IF2: Color Keyframe Interpolation Has a Subtle Gotcha with Curve Points**

Section 2.6 states: "Curve points interpolate per-point (must have matching point counts between keyframes)." This is a fragile constraint. If a user has a 3-point luminance curve at keyframe A and a 5-point luminance curve at keyframe B, the interpolation is undefined.

Options:
1. **Enforce matching point counts** between adjacent color keyframes (UI prevents adding/removing points when keyframes exist). This is restrictive.
2. **Resample curves** to a fixed resolution (e.g., 16 points) before interpolation. This is more flexible but lossy.
3. **Interpolate the evaluated curve** (sample both curves at 256 points, lerp the outputs). This is the most robust approach and avoids per-point matching entirely.

**Recommendation:** Option 3. Interpolate the 256-sample lookup tables, not the control points. This sidesteps the matching problem entirely and is computationally trivial (256 lerps per channel per frame).

**IF3: `CITemperatureAndTint` API Usage Needs Correction**

R1 flagged this as M2 (minor). This review elevates it to Important because incorrect usage will produce visibly wrong results:

`CITemperatureAndTint` takes TWO `CIVector` parameters:
- `inputNeutral`: The color temperature/tint of the source image (what the camera captured)
- `inputTargetNeutral`: The desired target temperature/tint

The correct mapping for a user-facing temperature slider (-1.0 to 1.0):

```swift
// Source is assumed to be shot at daylight (6500K, 0 tint)
let neutralTemp: Float = 6500.0
let neutralTint: Float = 0.0

// User slider maps temperature: -1.0 -> warm (lower K), +1.0 -> cool (higher K)
// Counterintuitive: to make image WARMER, set target to LOWER Kelvin
let targetTemp = neutralTemp + (temperature * -3500.0) // -1.0 -> 10000K (cool), +1.0 -> 3000K (warm)
let targetTint = tint * 150.0 // -150 to +150 range

let filter = CIFilter(name: "CITemperatureAndTint")!
filter.setValue(CIVector(x: CGFloat(neutralTemp), y: CGFloat(neutralTint)), forKey: "inputNeutral")
filter.setValue(CIVector(x: CGFloat(targetTemp), y: CGFloat(targetTint)), forKey: "inputTargetNeutral")
```

The design document's mapping (Section 4.2) says "Map: -1.0..1.0 to 2000K..10000K" but does not specify which parameter receives the Kelvin value. This ambiguity will produce incorrect results if implemented naively.

**IF4: Export Pre-Sampling (Section 10.3) Generates Potentially Huge Data**

Section 10.3 pre-samples color keyframes at export FPS. For a 60-second clip at 30fps, this produces 1,800 color grade samples. Each `ColorGrade` serialized to a native map contains ~30 parameters. That is 54,000 key-value pairs sent over the platform channel in a single invocation.

While platform channel serialization can handle this, the approach is wasteful. The native compositor should receive the raw keyframes and interpolation types, then perform interpolation during rendering (matching the existing transform keyframe pattern in `VideoProcessingService` which uses `setTransformRamp` -- the native equivalent of keyframe interpolation).

**Recommended alternative:** Send the raw color keyframes to native, implement interpolation in Swift. This reduces channel payload from O(frames) to O(keyframes), typically < 20 entries vs. 1,800.

**IF5: Before/After Split-Screen Performance (R1-I4 Deepened)**

R1 noted the double-render cost. The specific optimization is:

For split-screen mode, render the FULL frame through the CIFilter chain, then composite half of the original over the graded result:

```swift
// 1. Apply full filter chain
let gradedImage = filterChain.apply(to: sourceImage)

// 2. Create split mask (left half white, right half black)
let splitX = sourceImage.extent.width * splitPosition
let leftRect = CGRect(x: 0, y: 0, width: splitX, height: sourceImage.extent.height)

// 3. Crop original to left half, composite over graded
let originalHalf = sourceImage.cropped(to: leftRect)
let composite = originalHalf.composited(over: gradedImage)
```

This renders the filter chain once (8ms) plus one crop + composite (~0.5ms), well within the 16.67ms frame budget.

**IF6: Memory Impact of ColorGrade in PersistentTimeline Undo Stack**

The `TimelineManager` stores `PersistentTimeline` roots in the undo stack (max 100 entries). With structural sharing, most undo snapshots share 99% of their data. However, each `VideoClip` modification creates a path copy from the modified node to the root.

Adding `colorKeyframes: List<ColorKeyframe>` to `VideoClip` means every color adjustment creates a new `VideoClip` node in the tree. Each `ColorKeyframe` stores a full `ColorGrade` (~800 bytes as R1 estimated). With 5 color keyframes per clip, that is 4KB per `VideoClip` node.

With 100 undo steps of color grade adjustments (rapid slider dragging), the undo stack accumulates 100 path copies. Path copy cost is O(log n) nodes, each ~4KB = ~40-60KB per undo entry. 100 entries = ~4-6MB. This is within the 200MB budget but suggests throttling undo snapshots during slider dragging (e.g., one snapshot per 200ms, not per frame).

The design's debounce timer (Section 9.3, 16ms) fires undo-triggering updates 60 times per second. The `TimelineManager._execute()` pushes to the undo stack on every mutation. **This must be rate-limited for color grading changes** to avoid 60 undo entries per second of slider dragging.

### Action Items for Review 3

| # | Item | Priority | Owner |
|---|---|---|---|
| 1 | **Design Unified Compositor Architecture** -- Single `AVVideoCompositing` implementation for color grading + effects + transitions + text. This is a cross-cutting prerequisite. | **P0 (blocker)** | Architecture Team |
| 2 | **Decide V1/V2 approach for color grading storage** -- Endorse `ColorGradeStore` (model-agnostic) or commit to V2-only with migration plan | **P0** | Architecture Team |
| 3 | **Specify undo throttling for slider changes** -- Rate-limit undo snapshots during continuous slider dragging to prevent stack bloat | **P1** | Design |
| 4 | **Fix `CITemperatureAndTint` parameter specification** -- Provide exact `inputNeutral`/`inputTargetNeutral` CIVector values | **P1** | Design |
| 5 | **Resolve curve interpolation strategy** -- Choose between per-point interpolation (current) and 256-sample LUT interpolation (recommended) | **P1** | Design |
| 6 | **Fix LUT parser `DOMAIN_MIN`/`DOMAIN_MAX` parsing** -- Skip header keyword before parsing float values | **P1** | Implementation |
| 7 | **Add Metal shader build pipeline to Xcode project** -- Required for vibrance and HSL kernels, or commit to CIFilter-only workaround for Phase 1 | **P1** | Implementation |
| 8 | **Reconsider export pre-sampling** -- Send raw keyframes to native instead of pre-sampled frames to reduce channel payload | **P2** | Design |
| 9 | **Handle non-standard .cube files** -- Support optional 4th column (alpha) in LUT data lines | **P2** | Implementation |
| 10 | **Review 3 scope: UI/UX compliance check** -- Verify all proposed UI widgets match CLAUDE.md Liquid Glass requirements (CNTabBar pattern, CupertinoSlider, CupertinoScrollbar) | **P2** | Review 3 |

### Summary Assessment

**Implementation Viability: CONDITIONALLY VIABLE**

The color grading system is well-designed at the model and algorithm level. The CIFilter pipeline is professionally correct, the data models are sound, and the performance budget is realistic. However, the system cannot be implemented in isolation due to a fundamental architectural dependency: the unified compositor.

**Three blocking prerequisites must be resolved before Phase 1 begins:**
1. Unified Compositor Design (cross-cutting across 4 feature systems)
2. V1/V2 clip model decision for color grading storage
3. Metal shader pipeline decision (Phase 1 can proceed with CIFilter-only workaround)

**Estimated additional effort beyond the design's 263 hours:**
- Unified compositor design + skeleton: 20-30 hours
- VideoClip model changes with full test coverage: 8-12 hours (more than the design's 4-hour estimate)
- Metal shader pipeline setup: 4-8 hours (if pursuing Metal path)
- Undo throttling infrastructure: 4-6 hours
- **Total additional: 36-56 hours**, bringing the realistic total to **~300-320 hours**

The design is strong enough to proceed to implementation planning once the unified compositor architecture is established. The model-level code (Dart) can begin in parallel with compositor design.

---

*Review 2 Complete. Review 3 should focus on UI/UX compliance with iOS 26 Liquid Glass requirements and full widget audit against CLAUDE.md standards.*

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Scope:** Final gate review before implementation begins. Resolves all outstanding criticals from R1 and R2, verifies cross-cutting dependencies, produces risk register, ordered implementation checklist, and GO/NO-GO decision.

---

### 3.1 Critical Issues Status

All 4 criticals from R1 and 3 blocking prerequisites from R2 are tracked below with resolution status and prescribed paths.

| ID | Issue | R1/R2 | Resolution Status | Resolution Path |
|----|-------|-------|-------------------|-----------------|
| C1 | Dual clip model -- which model gets color grading? | R1-C1, R2-Risk3 | **RESOLVED (by design decision)** | Adopt model-agnostic `ColorGradeStore` keyed by clip ID. Both V1 `TimelineClip.id` and V2 `VideoClip.id` are UUID strings. Color grades and color keyframes live in the store, not embedded in clip models. V2 `VideoClip` gains `colorGradeId: String?` as a lightweight reference only; `colorKeyframes` move to the store. V1 clips access the same store by ID. This decouples color grading from the V1-to-V2 migration entirely. |
| C2 | Export pipeline requires rewrite, not extension | R1-C2, R2-Risk2 | **RESOLVED (via Unified Compositor)** | The export pipeline will migrate to a single `UnifiedCompositor: AVVideoCompositing` implementation (see CF1 below). Geometric transforms currently handled by `setTransformRamp()` will be reimplemented as `CIAffineTransform` operations within the compositor. Color grading CIFilters are applied as a subsequent stage in the same compositor render pass. This is a breaking change to `VideoProcessingService.renderComposition()` and `CompositionBuilder.buildVideoComposition()`, but is necessary for color grading, video effects, transitions, and text overlays alike. |
| C3 | `CIColorKernel` deprecated -- vibrance and HSL kernels at risk | R1-C3, R2-Risk5 | **RESOLVED (phased approach)** | Phase 1-2: Use CIFilter-only workarounds (vibrance via `CIColorControls` + luminance mask via `CIBlendWithMask`; HSL via per-range `CIColorMatrix` with gradient-derived masks). Phase 3: Add Metal shader pipeline (`ios/Runner/ColorGrading/Shaders/ColorGrading.metal`) for precise vibrance and HSL kernels. The CIFilter-only workarounds are adequate for initial release; Metal shaders are a polish upgrade. |
| C4 | Platform channel naming inconsistency | R1-C4 | **RESOLVED** | Use dedicated `com.liquideditor/color_grading` channel. Remove the conflicting reference in Section 1 Integration Points table (currently says `com.liquideditor/video_processing`). The color grading channel has 7+ methods and its own preview lifecycle, justifying a separate channel. Registration follows the existing `AppDelegate.setupPlatformChannels(with:)` pattern. |
| BP1 | Unified Compositor Design prerequisite | R2-CF1 | **RESOLUTION PATH DEFINED** | See Section 3.2 below. A standalone architecture document must be created before any export/preview rendering work begins. Dart-side model work (Phases 1a) can proceed in parallel. |
| BP2 | V1/V2 clip model decision | R2-Risk3, Action Item 2 | **RESOLVED (via C1)** | `ColorGradeStore` is the endorsed approach. See C1 resolution. |
| BP3 | Metal shader pipeline decision | R2-Action Item 7 | **RESOLVED (via C3)** | Phased approach: CIFilter-only for Phase 1-2, Metal shaders for Phase 3. |

**R1 Important Issues Resolution:**

| ID | Issue | Resolution |
|----|-------|------------|
| I1 | LUT intensity blending incorrect | **RESOLVED.** Use pre-blended LUT data: `lut[i] = lerp(identity[i], lut[i], intensity)`. Precompute on slider change, cache until next change. Zero GPU overhead at render time. Fallback for dynamic intensity: `CIBlendWithMask` with constant-value mask image (R2-CF3). |
| I2 | Color match residual LUT design vague | **RESOLVED.** Color match produces a `LUTFilter` (3D LUT) as the primary result. An optional "Decompose to Parameters" button performs the lossy conversion to editable `ColorGrade` sliders. Residual LUT is stored alongside the parametric approximation and applied after parametric adjustments in the filter chain. |
| I3 | `CIColorCube` for 1D curves is wasteful | **RESOLVED.** Curves with 5 or fewer points use `CIToneCurve` directly. Curves with more points sample to 256-entry 1D lookup and use `CIColorMap` with a 256x1 gradient image. `CIColorCube` is reserved for 3D LUTs only. |
| I4 | Before/after split renders two full frames | **RESOLVED.** Render the full frame through the CIFilter chain once (8ms). Crop the original image to the "before" region. Composite the original crop over the graded frame. Total cost: ~8.5ms, well within 16.67ms budget. |
| I5 | ColorKeyframe stores full snapshot -- memory concern | **ACCEPTED.** Full `ColorGrade` snapshots per keyframe is retained. At ~800 bytes per keyframe with a realistic maximum of 20 keyframes per clip, memory impact is 16KB per clip -- negligible. The alternative (delta encoding) adds implementation complexity without meaningful benefit. Only serialize non-default values in JSON to reduce persistence size. |
| I6 | No cancellation for long-running native operations | **RESOLVED.** Add `cancelColorOperation` method to the platform channel. Use an atomic `operationId` counter. Native side checks `isCancelled` between histogram frame sampling iterations. Stale results are discarded on the Dart side if the active clip has changed. |

**R2 Important Findings Resolution:**

| ID | Issue | Resolution |
|----|-------|------------|
| IF1 | LUT parser 4-column `.cube` handling | **RESOLVED.** Parser checks `values.count`: if 3, append `1.0` for alpha. If 4, use all four values. If other count, skip line with warning. `DOMAIN_MIN`/`DOMAIN_MAX` parsing uses `dropFirst()` before `compactMap`. |
| IF2 | Curve interpolation with mismatched point counts | **RESOLVED.** Adopt 256-sample LUT interpolation (R2 Option 3). Both keyframe curves are evaluated at 256 input points. The 256-sample outputs are lerped per-sample. No per-point matching required. |
| IF3 | `CITemperatureAndTint` API usage correction | **RESOLVED.** Set `inputNeutral` to `CIVector(x: 6500, y: 0)` (assumed daylight source). Set `inputTargetNeutral` to `CIVector(x: 6500 + (temperature * -3500), y: tint * 150)`. Temperature slider: -1.0 = warm (3000K target), +1.0 = cool (10000K target). |
| IF4 | Export pre-sampling sends huge data over channel | **RESOLVED.** Send raw color keyframes to native (O(keyframes), typically < 20). Native compositor performs interpolation at render time using the same easing functions. Interpolation per frame is < 0.5ms (13 doubles lerped). |
| IF5 | Before/after split performance | **RESOLVED (via I4).** |
| IF6 | Undo stack bloat from rapid slider dragging | **RESOLVED.** Introduce undo coalescing: during continuous slider interaction (pan gesture active), do not push to undo stack. Push a single undo entry on gesture end (`onPanEnd` / `onChangeEnd`). The `ColorGradeController` tracks `_isInteracting` state. UI updates immediately via `notifyListeners()`, but `TimelineManager._execute()` is only called on interaction end. |

**R1 Minor Issues Resolution:**

| ID | Resolution |
|----|------------|
| M1 | Use epsilon comparison: `(exposure).abs() < 0.0001` for all doubles in `isIdentity`. |
| M2 | Resolved via IF3 above. |
| M3 | Implementation will include full `toJson`/`fromJson` for all models with edge case handling. |
| M4 | LUT parser gains: malformed float rejection, missing `LUT_3D_SIZE` error, dimension cap at 65 (reject > 65x65x65), 1D LUT explicit rejection with `LUTParseError.unsupported1D`. |
| M5 | `ListView` in adjustments panel wrapped with `CupertinoScrollbar`. Section dividers use Cupertino styling. |
| M6 | `vignetteRadius` normalized 0.0-1.0 in `ColorGrade`, mapped to `CIVignette.inputRadius` as `radius * min(imageWidth, imageHeight) * 0.5`. |
| M7 | Bundled preset thumbnails stored as asset files, referenced by path. User preset thumbnails stored in `Documents/presets/thumbnails/` as JPEG files, referenced by filename in JSON. |

---

### 3.2 Unified Compositor -- Cross-Cutting Dependency Assessment

R2 correctly identified that four design documents (Color Grading, Video Effects, Transitions, Text/Titles) each propose their own `AVVideoCompositing` implementation, but `AVMutableVideoComposition` accepts exactly ONE `customVideoCompositorClass`.

**Current State Verification:**
- `ios/Runner/Timeline/CompositionBuilder.swift`: Uses `AVMutableVideoComposition` with standard `AVMutableVideoCompositionInstruction` and `setTransform(.identity, at: .zero)`. No `customVideoCompositorClass` is set.
- `ios/Runner/VideoProcessingService.swift`: Uses `AVMutableVideoCompositionLayerInstruction` with `setTransformRamp()`. No custom compositor.
- Zero `AVVideoCompositing` protocol conformances exist in the codebase.
- Zero `.metal` files exist in `ios/Runner/`.

**Viability Assessment:**

The unified compositor approach is architecturally sound and is the industry-standard pattern for professional video editors on iOS. The key design points:

1. **Single `UnifiedCompositor: AVVideoCompositing`** that handles all rendering stages
2. **Custom `CompositorInstruction: AVVideoCompositionInstructionProtocol`** carrying per-clip data (transforms, color grades, effects, text overlays, transition parameters)
3. **Render pipeline order**: Geometry transforms (CIAffineTransform) -> Color grading (CIFilter chain) -> Video effects (blur, chroma key, etc.) -> Text overlays (Core Text rendering) -> Transition blending (cross-dissolve, etc.)
4. **Shared infrastructure**: Metal-backed `CIContext`, `CVPixelBuffer` pool, `FlutterTexture` for preview

**Impact on Color Grading Implementation:**

Color grading Phase 1a (Dart models, `ColorGradeStore`, `ColorGradeController`) has ZERO dependency on the unified compositor. Only Phase 1b (real-time preview) and Phase 4 (export integration) require the compositor. This means 40-50% of color grading work can proceed immediately.

**Recommended Approach:** Create a minimal `UnifiedCompositor` design document (estimated 4-6 hours) that specifies the compositor skeleton. The color grading team implements their CIFilter chain as a callable module (`CIFilterChain.apply(to:params:) -> CIImage`) that the compositor invokes. This keeps color grading logic isolated while enabling integration.

---

### 3.3 CIFilter Pipeline Verification

The 12-stage CIFilter pipeline (Section 4.1) was verified against the Apple CIFilter Reference:

| # | Filter | API Status (iOS 18+) | Parameters Correct | Notes |
|---|--------|---------------------|-------------------|-------|
| 1 | `CIExposureAdjust` | Available | Yes | `inputEV` accepts Float directly |
| 2 | `CITemperatureAndTint` | Available | **Corrected (IF3)** | Must use CIVector for both `inputNeutral` and `inputTargetNeutral` |
| 3 | `CIHighlightShadowAdjust` | Available | Yes | `inputHighlightAmount` and `inputShadowAmount` both -1.0 to 1.0 |
| 4 | `CIToneCurve` | Available | Yes | 5 control points via `inputPoint0` through `inputPoint4` |
| 5 | `CIColorControls` | Available | **Needs mapping** | `inputContrast` neutral is 1.0 (not 0.0); `inputSaturation` neutral is 1.0 (not 0.0). Design's mapping (Section 4.2) correctly accounts for this. |
| 6 | Vibrance | Custom | **Phased (C3)** | Phase 1: CIFilter workaround. Phase 3: Metal shader. |
| 7 | HSL Wheels | Custom | **Phased (C3)** | Phase 1: `CIColorMatrix` per range. Phase 3: Metal shader. |
| 8 | `CIToneCurve` (RGB) | Available | **Corrected (I3)** | Use `CIToneCurve` for <=5 points, `CIColorMap` for >5 points. NOT `CIColorCube`. |
| 9 | `CIColorCubeWithColorSpace` | Available | Yes | Correctly specified for 3D LUT application |
| 10 | `CISharpenLuminance` | Available | Yes | `inputSharpness` 0.0 to 2.0 mapped from 0.0-1.0 slider |
| 11 | `CIUnsharpMask` | Available | Yes | Large radius (20px) for local contrast (clarity) |
| 12 | `CIVignette` | Available | Yes | `inputIntensity` and `inputRadius` |

**Filter Chain Fusion Verification:** iOS's CIFilter graph compiler does fuse chained filters into a single Metal compute kernel. However, fusion is broken by custom CIKernels (they become separate passes). With the Phase 1 CIFilter-only approach, all 12 stages can potentially fuse into 1-3 GPU passes. With Metal shaders in Phase 3, the vibrance and HSL stages become separate passes (total: 3-5 GPU passes). The 8ms budget per frame at 1080p is still achievable on A14+ devices.

**Production Readiness:** The pipeline is production-ready with the corrections noted above. The dirty flag optimization (Section 4.6) ensures only modified filter parameters are updated per frame. The pre-allocated filter instances avoid object creation overhead.

---

### 3.4 LUT System Verification

| Aspect | Status | Notes |
|--------|--------|-------|
| `.cube` parser correctness | **PASS (with fixes)** | Parser handles 3-column and 4-column data, `DOMAIN_MIN`/`DOMAIN_MAX` parsing corrected, dimension capped at 65 |
| `CIColorCubeWithColorSpace` usage | **PASS** | Correct API for 3D LUT application with explicit color space |
| Intensity blending | **PASS (with fix)** | Pre-blended LUT data approach (zero render-time cost) |
| Bundled LUT storage | **PASS** | 25 LUTs at 33x33x33 = ~14MB uncompressed, ~4MB compressed. Acceptable app bundle impact. |
| Custom LUT import | **PASS** | File picker -> validate -> copy to Documents/LUTs/ -> parse -> register. Proper error handling for malformed files. |
| LUT URI scheme | **PASS** | `bundled://` and `custom://` prefixes cleanly separate storage locations |
| Memory management | **PASS** | Max 3 active LUTs (~1.7MB), lazy loading, eviction on memory pressure |
| Thumbnail generation | **PASS** | Lazy generation from reference frame, cached per clip+LUT combination |

**LUT Data Validation Checklist (must be enforced in parser):**
1. `LUT_3D_SIZE` must be present and between 2 and 65
2. Data line count must equal `dimension^3`
3. Each data line must have 3 or 4 float values, all in `[DOMAIN_MIN, DOMAIN_MAX]`
4. Total data array size must equal `dimension^3 * 4` (RGBA floats)
5. Reject files > 50MB (prevents decompression bomb from malicious `.cube` files)
6. Reject 1D LUTs (`LUT_1D_SIZE` header) with specific error

---

### 3.5 iOS 26 Liquid Glass UI Compliance Audit

Verification of all proposed UI elements against CLAUDE.md requirements:

| UI Element | Design Section | Proposed Widget | CLAUDE.md Compliant | Required Fix |
|------------|---------------|-----------------|--------------------|----|
| Adjustment sliders | 6.2 | `CupertinoSlider` | **YES** | None |
| Panel tab bar | 6.1 | Not specified | **NEEDS FIX** | Must use `CNTabBar` from `cupertino_native_better` (CLAUDE.md Standard Bottom Bar Pattern) |
| Slider labels/values | 6.2 | Text + Row | **ACCEPTABLE** | Use `CupertinoColors.label` and `CupertinoColors.secondaryLabel` for colors |
| Section dividers | 6.2 | `_SectionDivider` (custom) | **NEEDS FIX** | Use `CupertinoListSection` header styling or `CupertinoColors.separator` |
| Filter thumbnails | 6.3 | Grid of images | **ACCEPTABLE** | Wrap in `CupertinoScrollbar` for horizontal scroll indicator |
| Intensity slider | 6.3 | Not specified | **NEEDS FIX** | Must be `CupertinoSlider` |
| Channel selector (curves) | 7.1 | `[RGB] [R] [G] [B] [Luma]` | **NEEDS FIX** | Use `CupertinoSegmentedControl` for channel selection |
| Curves canvas | 7.1 | `CustomPainter` | **ACCEPTABLE** | Custom painting is acceptable for specialized graphics widgets |
| Curve action buttons | 7.1 | `[Reset] [Add] [Delete]` | **NEEDS FIX** | Must be `CupertinoButton` instances |
| Color wheels | 8.1-8.2 | `CustomPainter` | **ACCEPTABLE** | Custom painting for specialized color input widgets is acceptable |
| Luminance sliders | 8.1 | Slider below each wheel | **NEEDS FIX** | Must be `CupertinoSlider` |
| Bottom bar buttons | 6.1 | `[Reset] [Before/After] [Presets]` | **NEEDS FIX** | Use `CNButton.icon` with `CNButtonStyle.glass` per CLAUDE.md Standard Bottom Bar Pattern |
| Keyframe diamond | 6.1 | `[Keyframe diamond]` | **ACCEPTABLE** | Small toggle can be a `CupertinoButton` with diamond icon |
| Preset save dialog | Not specified | Not specified | **NEEDS FIX** | Must use `CupertinoAlertDialog` with `CupertinoTextField` for name input |
| Preset browser | Not specified | Not specified | **NEEDS FIX** | Should use `CupertinoActionSheet` or bottom sheet with `CupertinoListTile` entries |
| Category filter | 6.3 | `[All] [Cinematic] [Vintage]...` | **NEEDS FIX** | Use `CupertinoSegmentedControl` or horizontal `CupertinoButton` row |
| Before/after mode picker | 6.4 | Toggle button | **NEEDS FIX** | Use `CupertinoSegmentedControl` with three segments |
| Scroll containers | 6.2 | `ListView` | **NEEDS FIX** | Wrap with `CupertinoScrollbar` |
| Haptic feedback | 8.3 | Light impact on wheel | **YES** | Already specified with `HapticFeedback.selectionClick()` |

**Overall UI Compliance: 5/18 elements fully compliant, 13 need fixes.**

The fixes are straightforward (widget substitutions, no architectural changes). All custom `CustomPainter` widgets (curves canvas, color wheels) are acceptable because they implement specialized graphic input surfaces that have no native equivalent.

**Critical UI Pattern:** The color grading panel's bottom bar MUST follow the CLAUDE.md Standard Bottom Bar Pattern:
```dart
// Bottom bar with action buttons - RIGHT side
Positioned(
  right: 16,
  bottom: MediaQuery.of(context).padding.bottom + 22,
  child: CNButton.icon(
    icon: const CNSymbol('plus', size: 24),
    config: const CNButtonConfig(
      style: CNButtonStyle.glass,
      minHeight: 56,
      width: 56,
    ),
    onPressed: _onAddKeyframe,
  ),
),
```

---

### 3.6 Risk Register

| # | Risk | Probability | Impact | Severity | Mitigation |
|---|------|-------------|--------|----------|------------|
| R1 | Unified compositor design is delayed, blocking preview and export | Medium | Critical | **HIGH** | Dart model work (Phase 1a) proceeds in parallel. CIFilter chain is implemented as a standalone module testable without compositor. |
| R2 | CIFilter chain exceeds 8ms budget on older devices (A14) | Medium | High | **HIGH** | Profile at Phase 1 milestone. Reduce preview resolution to 720p if needed. Implement dynamic quality scaling (measure render time, adjust resolution). |
| R3 | V1-to-V2 migration completes mid-implementation, invalidating `ColorGradeStore` bridge | Low | Medium | **MEDIUM** | `ColorGradeStore` is designed to work with either model. If V2 migration completes, remove V1 bridge code; store remains unchanged. |
| R4 | Custom `.cube` files from users cause parser crashes | Medium | Low | **MEDIUM** | Strict validation with dimension cap (65), file size cap (50MB), malformed line skipping, comprehensive error reporting to UI. |
| R5 | Metal shader compilation fails on some Xcode configurations | Low | Medium | **MEDIUM** | Defer Metal shaders to Phase 3. Phase 1-2 use CIFilter-only workaround. Metal shaders are additive, not required for MVP. |
| R6 | Color keyframe interpolation produces visual artifacts at extreme settings | Medium | Medium | **MEDIUM** | Clamp all interpolated values to valid ranges. Use monotone interpolation for curves (prevents overshoot). Test with extreme parameter combinations. |
| R7 | Memory pressure from LUT cache + undo stack during grading session | Low | Medium | **LOW** | LUT cache limited to 3 entries. Undo coalescing for slider interactions. Memory pressure handler releases LUT cache first. |
| R8 | Export with color grading + effects + transitions exceeds 16ms per frame budget | Medium | Medium | **MEDIUM** | Export is not real-time constrained (can take longer). The 16ms target is for preview only. Export can degrade gracefully. |
| R9 | 25 bundled LUT files increase app bundle by ~4MB | Low | Low | **LOW** | Acceptable trade-off. Can move to on-demand download in future if needed. |
| R10 | Before/after split-screen introduces visual seam artifacts | Low | Low | **LOW** | Use anti-aliased divider line. Render graded frame at full resolution, composite original half over it (no sub-pixel alignment issues). |
| R11 | `CITemperatureAndTint` produces unexpected results with non-daylight source footage | Medium | Low | **LOW** | Document that temperature slider assumes 6500K source. Future enhancement: auto-detect source color temperature from metadata. |
| R12 | Platform channel serialization latency for color grade params > 2ms | Low | Low | **LOW** | Color grade parameter map is ~30 key-value pairs of doubles. Measured platform channel overhead for maps of this size is < 0.5ms. |

---

### 3.7 Implementation Checklist

Ordered by dependency. Items within the same phase can be parallelized. Bold items are on the critical path.

#### Phase 0: Prerequisites (Before Color Grading)

| # | File | Purpose | Depends On | Est. Hours |
|---|------|---------|------------|------------|
| 0.1 | `docs/plans/unified-compositor-design.md` | **Unified compositor architecture document** | Nothing | 6 |
| 0.2 | `ios/Runner/Compositor/UnifiedCompositor.swift` | **Compositor skeleton: AVVideoCompositing protocol** | 0.1 | 12 |
| 0.3 | `ios/Runner/Compositor/CompositorInstruction.swift` | **Custom instruction protocol with per-clip data** | 0.1 | 4 |
| 0.4 | `ios/Runner/Compositor/PixelBufferPool.swift` | CVPixelBuffer pool for compositor output | 0.2 | 4 |
| 0.5 | Migrate `CompositionBuilder.swift` | Use custom instructions instead of layer instructions | 0.2, 0.3 | 8 |
| 0.6 | Migrate `VideoProcessingService.renderComposition()` | Use `customVideoCompositorClass` | 0.2, 0.3 | 8 |

#### Phase 1a: Dart Models (No native dependency)

| # | File | Purpose | Depends On | Est. Hours |
|---|------|---------|------------|------------|
| **1.1** | **`lib/models/color_grade.dart`** | **ColorGrade, LUTFilter, HSLAdjustment, CurveData, CurvePoint, ColorPreset models** | Nothing | 8 |
| **1.2** | **`lib/models/color_keyframe.dart`** | **ColorKeyframe model** | 1.1 | 3 |
| **1.3** | **`lib/core/color_grade_store.dart`** | **Model-agnostic store: Map<clipId, ColorGrade> + Map<clipId, List<ColorKeyframe>>** | 1.1, 1.2 | 6 |
| 1.4 | `lib/core/color_interpolator.dart` | Per-parameter interpolation with 256-sample curve LUT lerp | 1.1, 1.2 | 6 |
| 1.5 | `lib/core/color_grade_controller.dart` | ChangeNotifier, parameter throttling, undo coalescing, native bridge | 1.1, 1.3, 1.4 | 8 |
| 1.6 | `lib/models/clips/video_clip.dart` (modify) | Add `colorGradeId: String?` field, update constructor/copyWith/toJson/fromJson | 1.1 | 3 |
| 1.7 | `test/models/color_grade_test.dart` | Unit tests: serialization, identity, copyWith, isIdentity with epsilon | 1.1 | 4 |
| 1.8 | `test/core/color_interpolator_test.dart` | Unit tests: interpolation, curve evaluation, edge cases | 1.4 | 3 |
| 1.9 | `test/core/color_grade_store_test.dart` | Unit tests: store CRUD, undo integration | 1.3 | 3 |

#### Phase 1b: Native CIFilter Pipeline + Preview

| # | File | Purpose | Depends On | Est. Hours |
|---|------|---------|------------|------------|
| **1.10** | **`ios/Runner/ColorGrading/CIFilterChain.swift`** | **Reusable filter chain with dirty flags, 12-stage pipeline** | Nothing | 12 |
| **1.11** | **`ios/Runner/ColorGrading/ColorGradingService.swift`** | **Platform channel handler, method dispatch** | 1.10 | 6 |
| 1.12 | `ios/Runner/ColorGrading/ColorGradePreviewService.swift` | Metal-backed CIContext, FlutterTexture, CVPixelBuffer pool | 1.10, 0.4 | 10 |
| 1.13 | `ios/Runner/AppDelegate.swift` (modify) | Register `com.liquideditor/color_grading` channel | 1.11 | 1 |
| 1.14 | Integration test: slider -> native -> preview frame | End-to-end validation | 1.5, 1.12 | 4 |

#### Phase 1c: Adjustments Panel UI

| # | File | Purpose | Depends On | Est. Hours |
|---|------|---------|------------|------------|
| 1.15 | `lib/views/color_grading/color_grading_panel.dart` | Main panel with `CNTabBar` tab navigation (Adjust/Filters/HSL/Curves/Vignette) | 1.5 | 6 |
| 1.16 | `lib/views/color_grading/adjustments_panel.dart` | 13 `CupertinoSlider` rows with `CupertinoScrollbar`, double-tap reset | 1.15 | 6 |

#### Phase 2: LUT System

| # | File | Purpose | Depends On | Est. Hours |
|---|------|---------|------------|------------|
| **2.1** | **`ios/Runner/ColorGrading/LUTParser.swift`** | **.cube parser with validation, 3/4-column support, dimension cap** | Nothing | 6 |
| 2.2 | `ios/Runner/ColorGrading/LUTManager.swift` | LUT caching, intensity pre-blending, manifest loading | 2.1 | 6 |
| 2.3 | `ios/Runner/Assets/LUTs/manifest.json` + 25 `.cube` files | Bundled LUT library | Nothing | 12 |
| 2.4 | `lib/views/color_grading/filters_panel.dart` | Horizontal grid, `CupertinoSegmentedControl` categories, `CupertinoSlider` intensity | 1.15, 2.1 | 8 |
| 2.5 | LUT thumbnail generation pipeline | Lazy generation from reference frame, caching | 2.2, 1.12 | 6 |
| 2.6 | Custom LUT import flow | File picker, validation, Documents/LUTs/ storage | 2.1, 2.2 | 6 |
| 2.7 | `test/native/lut_parser_test.swift` | Unit tests: valid .cube, malformed, 1D rejection, large dimension | 2.1 | 4 |

#### Phase 3: Advanced Grading

| # | File | Purpose | Depends On | Est. Hours |
|---|------|---------|------------|------------|
| 3.1 | `lib/views/color_grading/curves_editor.dart` | `CustomPainter` canvas, control point interaction, `CupertinoSegmentedControl` channel selector | 1.15 | 12 |
| 3.2 | Monotone cubic interpolation (Fritsch-Carlson) | `CurveData.evaluate()` implementation | 1.1 | 4 |
| 3.3 | Curve-to-CIFilter conversion | `CIToneCurve` (<=5 points) or `CIColorMap` (>5 points) | 1.10, 3.2 | 6 |
| 3.4 | `lib/views/color_grading/hsl_wheels_panel.dart` | Three `CustomPainter` color wheels + `CupertinoSlider` luminance | 1.15 | 10 |
| 3.5 | HSL-to-CIFilter mapping | `CIColorMatrix` per tonal range with luminance gradient masks | 1.10 | 8 |
| 3.6 | `lib/views/color_grading/vignette_panel.dart` | Three `CupertinoSlider` controls | 1.15 | 3 |
| 3.7 | `ios/Runner/ColorGrading/Shaders/ColorGrading.metal` (optional) | Metal shader for vibrance + HSL precision | 1.10 | 8 |
| 3.8 | `test/views/curves_editor_test.dart` | Unit tests: point add/remove, constraint validation, spline evaluation | 3.1, 3.2 | 4 |
| 3.9 | `test/views/hsl_wheel_test.dart` | Unit tests: polar-to-cartesian, HSL conversion | 3.4 | 3 |

#### Phase 4: Integration & Polish

| # | File | Purpose | Depends On | Est. Hours |
|---|------|---------|------------|------------|
| **4.1** | **Compositor color grading stage** | **Integrate CIFilterChain into UnifiedCompositor render pipeline** | 0.2, 1.10 | 8 |
| 4.2 | Color keyframe interpolation in compositor | Native-side interpolation at render time | 4.1, 1.4 | 6 |
| 4.3 | Color keyframe UI (add/remove/navigate on timeline) | Keyframe diamond on timeline, add at playhead | 1.5, 1.15 | 6 |
| 4.4 | `lib/views/color_grading/before_after_view.dart` | Split/toggle/swipe comparison modes, `CupertinoSegmentedControl` mode picker | 1.12 | 6 |
| 4.5 | `ios/Runner/ColorGrading/HistogramMatcher.swift` | Histogram computation + CIE Lab matching | 1.10 | 10 |
| 4.6 | Color match UI flow | Clip picker, progress indicator, result application | 4.5, 1.5 | 6 |
| 4.7 | `lib/views/color_grading/preset_sheet.dart` | Save (`CupertinoAlertDialog`), load (`CupertinoActionSheet`), manage presets | 1.5 | 6 |
| 4.8 | 10 built-in presets | Curated combinations of adjustments + LUTs | 1.1, 2.3 | 4 |
| 4.9 | HDR color space handling | Extended sRGB `CIContext`, color space normalization | 1.10, 4.1 | 6 |
| 4.10 | Clip split with color grade | `ColorGradeStore` partitions keyframes on split | 1.3 | 3 |
| 4.11 | Performance profiling | Profile CIFilter chain, compositor, memory | All | 8 |
| 4.12 | End-to-end test: grade -> export -> verify | Full pipeline validation | 4.1 | 6 |
| 4.13 | Documentation updates | DESIGN.md, APP_LOGIC.md, FEATURES.md | All | 4 |

**Total Implementation Checklist: 48 items**

---

### 3.8 Revised Effort Estimate

| Phase | Original Estimate | Revised Estimate | Delta | Reason |
|-------|-------------------|------------------|-------|--------|
| Phase 0 (Prerequisites) | Not estimated | 42 hours | +42 | Unified compositor design + skeleton + migration |
| Phase 1a (Dart Models) | 65 hours (combined) | 44 hours | -- | Split from Phase 1b/1c |
| Phase 1b (Native Pipeline) | (included above) | 33 hours | -- | Split from Phase 1a |
| Phase 1c (Adjustments UI) | (included above) | 12 hours | -- | Split from Phase 1a |
| Phase 2 (LUT System) | 51 hours | 48 hours | -3 | Minor reduction |
| Phase 3 (Advanced Grading) | 66 hours | 58 hours | -8 | Metal shaders optional |
| Phase 4 (Integration) | 81 hours | 79 hours | -2 | Native-side keyframe interpolation reduces export complexity |
| **Total** | **263 hours** | **316 hours** | **+53** | Phase 0 overhead + more realistic model changes |

Note: Phase 0 is a shared cost across Color Grading, Video Effects, Transitions, and Text/Titles. If amortized across 4 features, the color grading share is ~10.5 hours, bringing the effective total to ~285 hours.

---

### 3.9 R1/R2 Questions Resolution

| Question | Resolution |
|----------|------------|
| Q1: Should color grading wait for V1-to-V2 migration? | **No.** `ColorGradeStore` is model-agnostic. Color grading works with either model via clip ID keying. |
| Q2: How does color grading interact with `CompositionPlaybackController`? | Color grading preview uses a separate `FlutterTexture` for zero-copy GPU rendering. During playback, the unified compositor applies the CIFilter chain to each frame. The `CompositionPlaybackController` sets `customVideoCompositorClass` on the `AVPlayerItem`'s video composition. |
| Q3: Do LUT thumbnails regenerate when switching clips? | Yes. LUT thumbnails are cached per `clipId + lutId` pair. When switching clips, a background queue generates thumbnails for the new reference frame. A loading shimmer is shown during generation (~200ms per thumbnail). The 25 bundled thumbnails are generated in parallel on a concurrent queue. |
| Q4: How does the new channel integrate with `AppDelegate.swift`? | `ColorGradingService` is instantiated in `AppDelegate.setupPlatformChannels(with:)` alongside `VideoProcessingService`. The `ColorGradingService` creates and owns its `FlutterMethodChannel` on `com.liquideditor/color_grading`. |
| Q5: `hold` interpolation -- abrupt or crossfade? | Abrupt (instant jump). The `hold` interpolation type is defined as "no interpolation, instant jump" in the existing `InterpolationType` enum. For color grades, this produces an instant color change at the keyframe timestamp. If users want a smooth transition, they use `easeInOut` or another easing type. |
| Q6: `CIMix` filter reference in Section 5.4? | Removed. The corrected approach uses pre-blended LUT data (Option 1 from R2-CF3). The `CIMix` reference was a design error. |

---

### 3.10 Test Plan Summary

| Test Category | Count | Focus |
|---------------|-------|-------|
| Unit: ColorGrade model | 15+ | Serialization round-trip, isIdentity epsilon, copyWith, parameter clamping |
| Unit: CurveData evaluation | 10+ | Identity curve, monotone cubic, endpoint behavior, 16-point max |
| Unit: ColorInterpolator | 10+ | Linear lerp, hold (instant), easeInOut, curve LUT interpolation |
| Unit: ColorGradeStore | 10+ | CRUD, undo integration, clip ID keying, keyframe partitioning on split |
| Unit: LUT parser (Swift) | 12+ | Valid .cube, 3-column, 4-column, missing header, dimension cap, 1D rejection, malformed floats |
| Unit: CIFilterChain (Swift) | 8+ | Parameter mapping correctness, dirty flag optimization, identity bypass |
| Unit: HSL polar conversion | 5+ | Cartesian-to-polar, polar-to-cartesian, edge cases (0 degrees, 360 degrees) |
| Integration: Slider -> preview | 3+ | Adjust parameter, verify native callback, verify texture update |
| Integration: LUT apply -> preview | 3+ | Select LUT, verify CIColorCube application, verify intensity blending |
| Integration: Export with color grade | 3+ | Grade clip, export, verify output frame colors match expected values |
| End-to-end: Full workflow | 2+ | Import -> grade -> keyframe -> export -> verify |

---

### 3.11 Final Assessment: CONDITIONAL GO

**Decision: CONDITIONAL GO**

The Color Grading & Filters system design is architecturally sound, professionally specified, and production-ready at the model and algorithm level. All 4 critical issues from R1 and all 3 blocking prerequisites from R2 have defined resolution paths. The CIFilter pipeline is verified against current Apple APIs. The LUT system is correctly specified. The data models are properly immutable.

**GO for immediate implementation:**
- Phase 1a (Dart models, `ColorGradeStore`, `ColorGradeController`, interpolator, tests) -- 44 hours
- Phase 2 partial (LUT parser native implementation, bundled LUT preparation) -- 24 hours
- Phase 3 partial (curves editor UI, HSL wheel UI as standalone widgets) -- 29 hours

**BLOCKED until Unified Compositor is designed and skeleton implemented:**
- Phase 0 (Unified Compositor) -- 42 hours (shared cost)
- Phase 1b (real-time preview pipeline) -- 33 hours
- Phase 4 (export integration, color match, before/after) -- 79 hours

**Conditions for full GO:**
1. Unified Compositor design document is approved (Phase 0.1)
2. Unified Compositor skeleton passes basic test (Phase 0.2: render a single frame with identity transform through the compositor)
3. `CompositionBuilder.swift` migration is verified with existing tests (Phase 0.5)

**What can start TODAY:** 97 hours of work (Phase 1a + Phase 2 partial + Phase 3 partial) has zero dependency on the Unified Compositor. This represents ~31% of the total effort and produces all Dart models, the full CIFilter chain (native), the LUT parser, and the UI widget shells. These components are independently testable and immediately useful once the compositor is ready.

**Estimated timeline to production:** 10-11 weeks (accounting for Phase 0 shared work and sequential dependencies in Phase 4).

---

### 3.12 Remaining Open Questions

| # | Question | Owner | Blocking? |
|---|----------|-------|-----------|
| OQ1 | Who owns the Unified Compositor design document? Should it be a separate design doc or an addendum to Video Effects? | Architecture Team | YES (blocks Phase 1b, Phase 4) |
| OQ2 | Should bundled LUT `.cube` files be created in-house or licensed from a third party? This affects the 12-hour Phase 2.3 estimate. | Product/Legal | NO (LUT placeholder files can be used for development) |
| OQ3 | Should the `ColorGradeStore` persist independently (its own JSON file) or be embedded in the project JSON? | Design Author | NO (either approach works; recommend embedding in project JSON for atomic save) |
| OQ4 | What is the minimum iOS version target? R1 mentioned iOS 15+ for `CIColorKernel` deprecation. If iOS 18+ is the minimum, additional modern APIs become available (`CIFilter.colorCubeWithColorSpace()` factory method, etc.). | Product | NO |
| OQ5 | Should the color grading panel be a bottom sheet (draggable up/down) or a fixed panel? The design shows a fixed panel but other editors (LumaFusion, CapCut) use resizable panels. | UX Design | NO |

---

*Review 3 Complete. Design approved for CONDITIONAL GO. Implementation may begin on Phase 1a, Phase 2 partial, and Phase 3 partial immediately. Remaining phases are blocked on Unified Compositor prerequisite.*
