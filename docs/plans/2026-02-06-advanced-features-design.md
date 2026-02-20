# Advanced Features System - Design Document

**Date:** 2026-02-06
**Author:** Claude Code (Opus 4.6)
**Status:** Draft - Pending Review
**Depends On:** Timeline Architecture V2, Keyframe System, CompositionBuilder, VideoProcessingService, Video Effects System, Tracking System

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Motion Tracking](#3-motion-tracking)
4. [Masking System](#4-masking-system)
5. [Pan & Scan (Ken Burns Effect)](#5-pan--scan-ken-burns-effect)
6. [Slow Motion & Time-Lapse](#6-slow-motion--time-lapse)
7. [Frame Interpolation](#7-frame-interpolation)
8. [Multi-Camera Editing](#8-multi-camera-editing)
9. [Proxy Editing](#9-proxy-editing)
10. [Markers & Chapter Points](#10-markers--chapter-points)
11. [Clone/Stamp Tool](#11-clonestamp-tool)
12. [Data Models](#12-data-models)
13. [Integration](#13-integration)
14. [Edge Cases](#14-edge-cases)
15. [Performance](#15-performance)
16. [Testing Strategy](#16-testing-strategy)
17. [Implementation Plan](#17-implementation-plan)

---

## 1. Overview

### Goals

The Advanced Features System extends Liquid Editor with professional-grade capabilities that differentiate it from basic video editors. These features span object tracking, masking, speed manipulation, multi-camera workflows, and proxy editing -- the tools expected in a serious creative application. Every feature integrates with the existing Timeline Architecture V2 (O(log n) operations, O(1) undo/redo) and leverages Apple's native frameworks (Vision, CoreImage, AVFoundation) for GPU-accelerated performance.

### Scope

- 10 advanced feature areas covering motion tracking, masking, clone/stamp, time-lapse, slow motion, frame interpolation, pan & scan, multi-camera editing, proxy editing, and markers/chapters
- Full integration with the existing keyframe system (`Keyframe`, `VideoTransform`, `InterpolationType`)
- Native iOS implementation via Vision framework (`VNTrackObjectRequest`, `VNDetectHumanBodyPoseRequest`) and CoreImage (`CIFilter`)
- Real-time preview at 60 FPS for lightweight features; background processing for compute-heavy operations
- Immutable data models following the established `@immutable` pattern with `copyWith`

### Non-Goals

- Android/cross-platform implementations (iOS-first per project philosophy)
- 3D motion tracking or camera solve (requires specialized compute beyond mobile)
- AI-generated content (text-to-video, generative fill) -- out of scope for V1
- Audio-reactive effects (belongs in a separate audio features design)
- Real-time collaborative multi-camera switching (single-device workflow only)

### Architecture Philosophy

1. **Data over behavior.** Feature state lives in immutable Dart models. Native Swift code interprets these models into Vision/CoreImage/AVFoundation operations.
2. **Extend, do not replace.** Every feature builds on existing infrastructure (`TimelineManager`, `MediaAssetRegistry`, `CompositionBuilder`, `VideoClip.keyframes`). No parallel systems.
3. **Progressive complexity.** Features that can run at 60 FPS in preview mode (pan & scan, markers) ship first. Features requiring background processing (motion tracking, frame interpolation) queue work and notify on completion.
4. **Fail gracefully.** Tracking loss, mask complexity limits, and proxy sync failures produce user-visible warnings, never crashes or silent corruption.

### Relationship to Existing Systems

| System | How Advanced Features Extend It |
|--------|-------------------------------|
| `VideoClip` (V2 data model) | Gains `masks`, `trackingDataId`, `speedMultiplier`, `multiCamGroupId` fields |
| `Keyframe` / `KeyframeTimeline` | Mask paths, crop regions, and speed curves reuse existing `InterpolationType` interpolation |
| `BoundingBoxTracker.swift` | Motion tracking extends existing `VNDetectHumanBodyPoseRequest` pipeline to generic object tracking |
| `TrackingDataStore.swift` | Stores motion tracking paths alongside person tracking results |
| `CompositionBuilder.swift` | Extended with `AVVideoCompositionInstructionProtocol` for masks, speed changes, and multi-cam switching |
| `VideoProcessingService.swift` | Gains frame interpolation, proxy generation, and clone/stamp rendering |
| `MediaAssetRegistry` | Gains proxy asset association and multi-cam group metadata |
| `TimelineMarker` (existing model) | Extended with chapter export metadata and thumbnail snapshots |
| `EffectChain` (video effects system) | Masks act as effect inputs; clone/stamp is an effect node |

---

## 2. Current State Analysis

### What Exists

| Feature Area | Current State | Notes |
|-------------|---------------|-------|
| **Person Tracking** | Fully implemented | `BoundingBoxTracker` (pose-based, iOS 15+), `KalmanFilter` smoothing, `TrackingDataStore` interpolation |
| **Markers** | Model implemented | `TimelineMarker` with `MarkerType` enum (generic, chapter, todo, sync, beat), point and range markers |
| **Keyframe System** | Fully implemented | 21 interpolation types, `VideoTransform` (scale, translation, rotation, anchor), binary search surrounding keyframes |
| **Proxy Generation** | Partially implemented | `ProxyGenerator.swift` generates 480p proxies for tracking analysis; not used for general editing workflow |
| **Speed Control** | Not implemented | No `speedMultiplier` on clips; no time remapping infrastructure |
| **Masking** | Not implemented | No mask data model or rendering pipeline |
| **Multi-Camera** | Not implemented | No multi-cam grouping, sync detection, or angle switching |
| **Frame Interpolation** | Not implemented | No optical flow or frame blending |
| **Clone/Stamp** | Not implemented | No region duplication tools |
| **Pan & Scan** | Not implemented | Existing `VideoTransform` handles scale/translate/rotate but lacks keyframed crop regions |

### Gaps to Address

1. **VideoClip lacks speed/mask/tracking fields.** The immutable model needs extension without breaking serialization backward compatibility.
2. **CompositionBuilder does not support custom compositors.** Currently uses `AVMutableVideoCompositionInstruction` with identity transform only. Masks, speed changes, and multi-cam switching require `AVVideoCompositing` protocol implementation.
3. **No generic object tracking.** Existing tracking is person-specific (`VNDetectHumanBodyPoseRequest`). Generic object tracking needs `VNTrackObjectRequest` or `VNTrackRectangleRequest`.
4. **Proxy system is tracking-only.** The existing `ProxyGenerator` creates 480p proxies solely for tracking analysis. A full proxy editing workflow needs resolution-matched proxies, transparent switching, and export from originals.
5. **Marker model is not integrated with export.** `TimelineMarker` exists as a data model but has no export pathway for chapter metadata in MP4/MOV files.

---

## 3. Motion Tracking

### Overview

Motion tracking allows users to select an object in a frame and track its position, scale, and rotation across time. Tracked paths can be used to attach overlays (text, stickers, graphics) that follow the object, or to drive mask positions for localized effects.

### Vision Framework Integration

Apple provides two tracking APIs suitable for this feature:

#### VNTrackObjectRequest (Primary)

- **Input:** Initial bounding box observation (`VNDetectedObjectObservation`)
- **Output:** Updated bounding box per frame with confidence score
- **Performance:** ~2ms per frame on Neural Engine (A14+), ~8ms on CPU
- **Limitations:** Tracks rectangular regions only; no rotation estimation; can lose track on occlusion
- **iOS Requirement:** iOS 11+ (well within our iOS 18.0 minimum)

#### VNTrackRectangleRequest (Alternative)

- **Input:** Rectangle observation from `VNDetectRectanglesRequest`
- **Output:** Updated rectangle with perspective transform
- **Use Case:** Tracking planar surfaces (signs, screens, cards) where perspective matters
- **Limitations:** Requires clear rectangular edges; fails on organic shapes

### Architecture

```
Flutter                           Native iOS (Swift)
------                           ------------------
MotionTrackingController         MotionTrackingService
  |                                |
  |-- startTracking(clipId,        |-- VNSequenceRequestHandler
  |     initialRect, frameRange)   |     |
  |                                |     |-- VNTrackObjectRequest (per frame)
  |<-- onProgress(float)          |     |-- VNTrackRectangleRequest (optional)
  |<-- onResult(TrackingPath)     |     |
  |                                |-- TrackingPathBuilder
  |-- attachOverlay(trackPathId,   |     |-- Kalman filter smoothing
  |     overlayClipId)             |     |-- Confidence-based interpolation
  |                                |     |-- Path simplification (RDP algorithm)
  |-- detachOverlay(overlayClipId) |
```

### MethodChannel API

```
Channel: com.liquideditor/motion_tracking

Methods:
  startObjectTracking:
    args: {
      videoPath: String,           // Source video file path
      initialRect: {x, y, w, h},  // Normalized bounding box (0.0-1.0)
      startFrameMs: int,           // Start time in milliseconds
      endFrameMs: int,             // End time in milliseconds
      trackingQuality: String,     // "fast" | "accurate" (VNRequestTrackingLevel)
    }
    returns: String (trackingJobId)

  cancelObjectTracking:
    args: { jobId: String }

  getTrackingPath:
    args: { jobId: String }
    returns: {
      points: [{timeMs, x, y, width, height, confidence, rotation}],
      averageConfidence: double,
      lostFrames: [int],           // Timestamps where tracking was lost
    }
```

### Tracking Path Data Flow

1. **User taps object** in video preview at current frame.
2. Flutter sends initial bounding box + time range to native via MethodChannel.
3. Native creates `VNSequenceRequestHandler`, processes frames sequentially.
4. Each frame result is accumulated in `TrackingPathBuilder`.
5. After completion, path is smoothed with existing `KalmanFilter` implementation.
6. Path is simplified using Ramer-Douglas-Peucker algorithm (reduce point count for large videos).
7. Result is sent back to Flutter as `TrackingPath` model.
8. User can then attach any overlay clip to the tracking path.

### Tracking Loss Recovery

When `VNTrackObjectRequest` reports low confidence (< 0.3):

1. **Short gap (< 500ms):** Interpolate position using Kalman filter prediction.
2. **Medium gap (500ms - 2s):** Mark frames as "estimated" in tracking path; show yellow indicators in timeline.
3. **Long gap (> 2s):** Stop tracking, prompt user to re-select object. Allow manual keyframe correction for estimated segments.

### Overlay Attachment

Once a tracking path exists, any overlay (text clip, sticker, or shape) can be attached:

```dart
/// Attaches an overlay to a tracking path.
/// The overlay's position at each frame is computed by interpolating
/// the tracking path and applying the offset.
class TrackingAttachment {
  final String trackingPathId;
  final String overlayClipId;
  final Offset anchorOffset;     // Offset from tracked center (normalized)
  final bool matchScale;         // Scale overlay with tracked object size
  final bool matchRotation;      // Rotate overlay with tracked object
}
```

During export, `CompositionBuilder` reads the tracking path and applies per-frame transforms to the overlay layer using `AVVideoCompositionLayerInstruction.setTransform(_:at:)`.

---

## 4. Masking System

### Overview

Masking isolates regions of a video frame for selective effect application. Users can create shape masks (rectangle, ellipse, polygon), draw freeform brush masks, or use person segmentation masks from the existing tracking system.

### Mask Types

| Type | Description | Use Case |
|------|-------------|----------|
| **RectangleMask** | Axis-aligned rectangle with corner radius | Quick region isolation, letterboxing |
| **EllipseMask** | Ellipse defined by center, radii, and rotation | Face isolation, spotlight effects |
| **PolygonMask** | Arbitrary polygon with N vertices | Custom shape cutouts |
| **BrushMask** | Freeform painted path with variable stroke width | Precise organic shapes |
| **PersonMask** | Auto-generated from `VNGeneratePersonSegmentationRequest` | Background replacement, person effects |
| **LuminanceMask** | Derived from frame luminance values | Highlight/shadow targeting |

### Data Model

```dart
@immutable
class MaskDefinition {
  final String id;
  final MaskType type;
  final bool isInverted;         // Apply effect outside mask
  final double feather;          // Edge softness (0.0 = hard, 1.0 = maximum blur)
  final double opacity;          // Mask strength (0.0 = transparent, 1.0 = fully opaque)
  final double expansion;        // Grow/shrink mask boundary (negative = shrink)
  final MaskShapeData shapeData; // Type-specific geometry
  final List<MaskKeyframe> keyframes; // Animated mask parameters
}

@immutable
class MaskShapeData {
  // Rectangle
  final Rect? rect;              // Normalized (0.0-1.0)
  final double? cornerRadius;

  // Ellipse
  final Offset? center;
  final double? radiusX;
  final double? radiusY;
  final double? rotation;

  // Polygon
  final List<Offset>? vertices;  // Normalized coordinates

  // Brush
  final List<BrushStroke>? strokes;

  // Person segmentation
  final int? personIndex;        // Which detected person

  // Luminance
  final double? luminanceMin;
  final double? luminanceMax;
}

@immutable
class BrushStroke {
  final List<Offset> points;     // Path points (normalized)
  final double width;            // Stroke width (normalized)
  final double softness;         // Edge softness per stroke
}
```

### Native Rendering Pipeline

Masks are rendered natively using CoreImage:

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│ Source Frame │────>│ Mask Generator    │────>│ CIBlendWithMask     │
│ (CIImage)   │     │ (CIRadialGradient │     │                     │
└─────────────┘     │  CIAffineTransform│     │ Input: source       │
                    │  CIGaussianBlur   │     │ Background: effect  │
                    │  for feathering)  │     │ Mask: generated     │
                    └──────────────────┘     └─────────────────────┘
```

#### Shape Mask Generation (CIFilter Chain)

1. **Rectangle:** `CICrop` to define region, then `CIGaussianBlur` on alpha channel for feathering.
2. **Ellipse:** Render `CIRadialGradient` with hard stops, apply `CIAffineTransform` for non-circular ellipses.
3. **Polygon:** Render polygon path into `CGContext`, create `CIImage` from bitmap, blur for feathering.
4. **Brush:** Render all strokes into `CGContext` with variable-width Bezier paths, create `CIImage`.
5. **Person:** Use `VNGeneratePersonSegmentationRequest` (iOS 15+) output matte directly as `CIImage` mask.
6. **Luminance:** Apply `CIColorClamp` with min/max luminance thresholds, use result as mask.

#### Feathering Implementation

Feathering is implemented as `CIGaussianBlur` applied to the binary mask image:

```swift
func applyFeather(to mask: CIImage, featherAmount: CGFloat, frameSize: CGSize) -> CIImage {
    // Convert normalized feather (0.0-1.0) to pixel radius
    let maxFeather = max(frameSize.width, frameSize.height) * 0.1 // 10% of frame = max feather
    let radius = featherAmount * maxFeather

    guard radius > 0 else { return mask }

    return mask.applyingFilter("CIGaussianBlur", parameters: [
        kCIInputRadiusKey: radius
    ]).cropped(to: mask.extent)
}
```

### Mask Keyframing

Mask shapes can be animated over time by keyframing their parameters:

- **Rectangle:** Animate `rect.origin`, `rect.size`, `cornerRadius`
- **Ellipse:** Animate `center`, `radiusX`, `radiusY`, `rotation`
- **Polygon:** Animate individual vertex positions (requires vertex count to remain constant)
- **Common:** Animate `feather`, `opacity`, `expansion`, `isInverted` (snap on boolean)

Mask keyframes use the same `InterpolationType` enum as video transform keyframes, enabling consistent easing behavior across all animated properties.

---

## 5. Pan & Scan (Ken Burns Effect)

### Overview

Pan & scan (the "Ken Burns effect") applies animated crop regions to a video, creating the illusion of camera movement within a static or wider shot. This is implemented as keyframed crop rectangles that interpolate smoothly between positions.

### Relationship to Existing VideoTransform

The existing `VideoTransform` already handles scale, translation, and rotation. Pan & scan is conceptually similar but operates as a **crop region** rather than a viewport transform:

| Aspect | VideoTransform (existing) | Pan & Scan (new) |
|--------|--------------------------|------------------|
| **What it does** | Moves/scales the viewport over the video | Defines a crop rectangle within the source frame |
| **Output size** | Always fills the export resolution | Crops to region, then scales to fill export resolution |
| **Use case** | Interactive gesture-driven editing | Pre-defined start/end regions for smooth animation |
| **Data model** | `scale`, `translation`, `rotation`, `anchor` | `cropRect` (normalized), interpolated between keyframes |

### Data Model

```dart
@immutable
class PanScanRegion {
  /// Crop rectangle in normalized coordinates (0.0-1.0 relative to source frame)
  final Rect cropRect;

  /// Rotation angle in radians (optional, for tilted crops)
  final double rotation;

  const PanScanRegion({
    required this.cropRect,
    this.rotation = 0.0,
  });
}
```

Pan & scan is stored as keyframes on the clip, where each keyframe's "transform" is a `PanScanRegion` instead of a `VideoTransform`. This could be implemented by:

1. **Option A (Recommended):** Add an optional `panScanRegions: List<PanScanKeyframe>` field to `VideoClip`. Pan & scan keyframes are separate from transform keyframes, allowing both to coexist.
2. **Option B:** Encode pan & scan as a special effect in the `EffectChain`. This is conceptually clean but adds latency to the effect pipeline for a simple crop operation.

### Interpolation

Crop regions interpolate component-wise:

```dart
PanScanRegion interpolate(PanScanRegion a, PanScanRegion b, double t, InterpolationType type) {
  final easedT = applyEasing(t, type);
  return PanScanRegion(
    cropRect: Rect.lerp(a.cropRect, b.cropRect, easedT)!,
    rotation: lerpDouble(a.rotation, b.rotation, easedT)!,
  );
}
```

### Native Export

During export, `CompositionBuilder` applies the crop by:

1. Computing the interpolated `PanScanRegion` for each frame.
2. Creating a `CIImage` crop: `sourceFrame.cropped(to: pixelRect)`.
3. Scaling the cropped region to the export resolution using `CILanczosScaleTransform`.
4. Optionally applying `CIAffineTransform` for rotation.

### UI Interaction

The pan & scan editor shows:
- Source frame with a draggable/resizable crop rectangle overlay
- Timeline with crop region keyframes (separate track from transform keyframes)
- "Start" and "End" buttons for quick two-keyframe setup
- Preview button to play the animated crop in real-time

---

## 6. Slow Motion & Time-Lapse

### Overview

Speed manipulation allows users to slow down or speed up portions of a video clip. Slow motion reduces playback speed (0.1x - 1.0x), while time-lapse increases it (1.0x - 100x). Both require frame-rate-aware time remapping in the composition pipeline.

### Speed Model

```dart
@immutable
class SpeedSettings {
  /// Speed multiplier (0.1 = 10x slow, 1.0 = normal, 10.0 = 10x fast)
  final double speedMultiplier;

  /// Whether to maintain audio pitch when changing speed
  final bool maintainPitch;

  /// Frame blending mode for speed changes
  final FrameBlendMode blendMode;

  /// Speed ramp keyframes (for variable speed within a clip)
  /// If empty, speedMultiplier applies uniformly
  final List<SpeedKeyframe> rampKeyframes;

  const SpeedSettings({
    this.speedMultiplier = 1.0,
    this.maintainPitch = true,
    this.blendMode = FrameBlendMode.none,
    this.rampKeyframes = const [],
  });

  /// Effective duration after speed change
  int effectiveDurationMicros(int sourceDurationMicros) =>
      (sourceDurationMicros / speedMultiplier).round();
}

enum FrameBlendMode {
  /// No blending, nearest frame
  none,

  /// Linear blend between adjacent frames
  blend,

  /// Optical flow interpolation (highest quality, most expensive)
  opticalFlow,
}

@immutable
class SpeedKeyframe {
  final Duration timestamp;          // Position in clip timeline
  final double speedMultiplier;      // Speed at this point
  final InterpolationType interpolation;
}
```

### Time-Lapse Implementation

Time-lapse (speed > 1.0x) is straightforward:

1. **Frame Sampling:** For a 10x time-lapse, keep every 10th frame. AVFoundation handles this naturally by adjusting the time mapping in `AVMutableCompositionTrack`.
2. **Composition:** Use `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)` to compress the clip's time range.
3. **Audio:** Either drop audio (common for time-lapse) or pitch-shift using `AVAudioTimePitchAlgorithm.spectral`.

```swift
// Time-lapse: compress 10 seconds to 1 second (10x speed)
let sourceRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600))
let targetDuration = CMTime(seconds: 1, preferredTimescale: 600)
try compositionTrack.scaleTimeRange(sourceRange, toDuration: targetDuration)
```

### Slow Motion Implementation

Slow motion (speed < 1.0x) requires generating frames that do not exist in the source:

1. **No Blending (mode: `.none`):** Duplicate frames to fill the extended duration. Simplest but produces stuttery playback at extreme slow-mo (< 0.25x).
2. **Frame Blending (mode: `.blend`):** Cross-dissolve between adjacent source frames. Better than duplication; uses `CIDissolveTransition` filter.
3. **Optical Flow (mode: `.opticalFlow`):** Generate intermediate frames using motion estimation. Highest quality. See Section 7 (Frame Interpolation).

### AVFoundation Time Remapping

For uniform speed changes, `AVMutableCompositionTrack.scaleTimeRange` is sufficient. For speed ramps (variable speed), we need per-frame time mapping:

```swift
// Speed ramp: build a custom time remapping function
// Map each output frame time to a source frame time
func buildTimeRemapping(rampKeyframes: [SpeedKeyframe], sourceDuration: CMTime) -> [(outputTime: CMTime, sourceTime: CMTime)] {
    var mapping: [(CMTime, CMTime)] = []
    var sourceAccumulator: Double = 0.0
    let frameDuration = 1.0 / 30.0 // Output frame rate

    var outputTime: Double = 0.0
    while sourceAccumulator < CMTimeGetSeconds(sourceDuration) {
        let speed = interpolateSpeed(at: sourceAccumulator, keyframes: rampKeyframes)
        mapping.append((
            CMTime(seconds: outputTime, preferredTimescale: 600),
            CMTime(seconds: sourceAccumulator, preferredTimescale: 600)
        ))
        sourceAccumulator += frameDuration * speed
        outputTime += frameDuration
    }

    return mapping
}
```

This time remapping is applied during export via a custom `AVVideoCompositing` implementation that reads frames at the remapped source times.

### Audio Handling

| Speed Range | Audio Treatment |
|-------------|----------------|
| 0.1x - 0.5x | Pitch-corrected time stretch (`AVAudioTimePitchAlgorithm.spectral`) or mute |
| 0.5x - 2.0x | Pitch-corrected time stretch (good quality) |
| 2.0x - 4.0x | Pitch-corrected time stretch (acceptable quality, artifacts increase) |
| > 4.0x | Mute audio (pitch correction artifacts become unacceptable) |

---

## 7. Frame Interpolation

### Overview

Frame interpolation generates intermediate frames between existing source frames, enabling smooth slow motion even when the source was shot at standard frame rates (24/30 fps). This is the compute-heavy complement to the speed manipulation system.

### Approaches

#### 7.1 Frame Blending (Simple, Fast)

Cross-dissolve between adjacent frames using alpha blending:

```swift
func blendFrames(frame1: CIImage, frame2: CIImage, factor: Double) -> CIImage {
    return frame1.applyingFilter("CIDissolveTransition", parameters: [
        kCIInputTargetImageKey: frame2,
        kCIInputTimeKey: factor,
    ])
}
```

- **Quality:** Low. Produces ghosting on fast-moving subjects.
- **Performance:** < 1ms per frame (GPU accelerated).
- **When to use:** Quick previews, speeds down to 0.5x.

#### 7.2 Motion-Compensated Interpolation (High Quality, Slow)

Uses optical flow to estimate per-pixel motion vectors, then warps source frames to synthesize intermediate frames.

**Apple Framework Options:**

1. **VTFrameRateConversion (iOS 16+):** Apple's built-in frame rate conversion in Video Toolbox. This is a black-box API that handles optical flow internally. Unfortunately, it is primarily designed for display refresh rate matching (24fps -> 120fps) and has limited configurability for creative slow-mo.

2. **VNGenerateOpticalFlowRequest (iOS 14+, Vision framework):**
   - Computes dense optical flow between two frames
   - Returns a `CVPixelBuffer` containing per-pixel motion vectors (2-channel float16)
   - We can then use these vectors to warp frames ourselves
   - **Performance:** ~30-50ms per frame pair on A14 (Neural Engine accelerated)
   - **This is the recommended approach** for maximum control

3. **Metal Performance Shaders + Custom Kernel:**
   - Write a Metal compute shader for frame warping based on optical flow vectors
   - Most control but highest implementation effort
   - Fallback if Vision optical flow quality is insufficient

### Optical Flow Pipeline

```
Frame N          Frame N+1         Vision Framework
   |                |                    |
   +-------+--------+                   |
           |                             |
   VNGenerateOpticalFlowRequest --------+
           |
    Flow Field (CVPixelBuffer, float16x2)
           |
     +-----+-----+
     |           |
  Forward      Backward
  Warping      Warping
     |           |
     +-----+-----+
           |
    Alpha Blend Warped Results
           |
    Interpolated Frame
```

### Implementation

```swift
class FrameInterpolator {
    private let ciContext: CIContext

    init() {
        // Use Metal for GPU acceleration
        ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
    }

    /// Generate an intermediate frame between two source frames
    func interpolate(
        frame1: CVPixelBuffer,
        frame2: CVPixelBuffer,
        factor: Double, // 0.0 = frame1, 1.0 = frame2
        quality: InterpolationQuality
    ) async throws -> CIImage {
        switch quality {
        case .blend:
            return blendFrames(
                CIImage(cvPixelBuffer: frame1),
                CIImage(cvPixelBuffer: frame2),
                factor: factor
            )

        case .opticalFlow:
            // Compute forward optical flow (frame1 -> frame2)
            let flowRequest = VNGenerateOpticalFlowRequest(
                targetedCVPixelBuffer: frame2
            )
            flowRequest.computationAccuracy = .medium
            flowRequest.outputPixelFormat = kCVPixelFormatType_TwoComponent16Half

            let handler = VNImageRequestHandler(
                cvPixelBuffer: frame1,
                options: [:]
            )
            try handler.perform([flowRequest])

            guard let flowObservation = flowRequest.results?.first else {
                // Fallback to simple blend if optical flow fails
                return blendFrames(
                    CIImage(cvPixelBuffer: frame1),
                    CIImage(cvPixelBuffer: frame2),
                    factor: factor
                )
            }

            // Warp frames using flow vectors
            return warpWithFlow(
                frame1: CIImage(cvPixelBuffer: frame1),
                frame2: CIImage(cvPixelBuffer: frame2),
                flowField: flowObservation.pixelBuffer,
                factor: factor
            )
        }
    }

    /// Warp source frames using optical flow field
    private func warpWithFlow(
        frame1: CIImage,
        frame2: CIImage,
        flowField: CVPixelBuffer,
        factor: Double
    ) -> CIImage {
        // This requires a custom CIKernel or Metal shader to:
        // 1. Read flow vectors from flowField
        // 2. Scale vectors by factor (forward) and (1-factor) (backward)
        // 3. Sample frame1 at (pixel + flow * factor)
        // 4. Sample frame2 at (pixel - flow * (1 - factor))
        // 5. Blend the two warped results

        // Placeholder: Use Metal compute shader for production
        // For now, fall back to blend
        return blendFrames(frame1, frame2, factor: factor)
    }
}
```

### Performance Budget

| Operation | Target | Device |
|-----------|--------|--------|
| Optical flow computation | < 50ms | A14+ (Neural Engine) |
| Frame warping (Metal shader) | < 5ms | Any Metal GPU |
| Total per interpolated frame | < 60ms | A14+ |
| Frame blend fallback | < 2ms | Any device |

**Implication:** Real-time preview of optical flow interpolation is NOT feasible at 60fps (60ms budget per frame = exactly 16.6fps). Strategy:

1. **Preview:** Use frame blending for real-time playback.
2. **Background pre-render:** Compute optical flow interpolated frames in background, cache results.
3. **Export:** Use full optical flow pipeline (not real-time constrained).

---

## 8. Multi-Camera Editing

### Overview

Multi-camera editing allows users to import multiple video clips shot simultaneously from different camera angles, synchronize them by audio, and switch between angles on a shared timeline. This is common for interviews, live events, and music videos.

### Multi-Cam Group Model

```dart
@immutable
class MultiCamGroup {
  final String id;
  final String name;
  final List<MultiCamAngle> angles;
  final int syncOffsetBaseMicros;  // Reference angle's timeline position
  final String? referenceAngleId;   // Which angle is the "master" for sync

  const MultiCamGroup({
    required this.id,
    required this.name,
    required this.angles,
    this.syncOffsetBaseMicros = 0,
    this.referenceAngleId,
  });
}

@immutable
class MultiCamAngle {
  final String id;
  final String mediaAssetId;       // References MediaAsset
  final String label;              // "Camera A", "Wide Shot", etc.
  final int syncOffsetMicros;      // Offset from group base time
  final bool isAudioReference;     // Use this angle's audio for the group

  const MultiCamAngle({
    required this.id,
    required this.mediaAssetId,
    required this.label,
    this.syncOffsetMicros = 0,
    this.isAudioReference = false,
  });
}
```

### Audio Sync Detection

Synchronizing multiple camera angles is done by cross-correlating their audio waveforms:

```
Camera A audio:  ___/\___/\/\___/\___
Camera B audio:  _____/\___/\/\___/\_
                      |<-- offset -->|
```

#### Implementation

1. **Extract audio:** Use `AVAssetReader` to read PCM audio samples from each angle.
2. **Downsample:** Reduce to mono 8kHz for faster cross-correlation.
3. **Cross-correlate:** Compute normalized cross-correlation between reference audio and each other angle's audio.
4. **Find peak:** The offset at maximum correlation is the sync offset.

```swift
func computeAudioSyncOffset(
    referenceAudio: [Float],
    targetAudio: [Float],
    sampleRate: Double
) -> Int {
    // Use Accelerate framework for fast cross-correlation
    let resultLength = referenceAudio.count + targetAudio.count - 1
    var result = [Float](repeating: 0, count: resultLength)

    vDSP_conv(
        referenceAudio, 1,
        targetAudio, 1,
        &result, 1,
        vDSP_Length(resultLength),
        vDSP_Length(targetAudio.count)
    )

    // Find peak
    var maxValue: Float = 0
    var maxIndex: vDSP_Length = 0
    vDSP_maxvi(result, 1, &maxValue, &maxIndex, vDSP_Length(resultLength))

    // Convert sample offset to microseconds
    let sampleOffset = Int(maxIndex) - targetAudio.count + 1
    let timeMicros = Int(Double(sampleOffset) / sampleRate * 1_000_000)
    return timeMicros
}
```

**Performance:** Cross-correlation of 60-second audio clips at 8kHz takes approximately 200ms using Accelerate framework. This is a one-time operation per angle pair.

### Angle Switching

Once synchronized, the user switches angles by placing "cut points" on the timeline. Each cut point specifies which angle is active from that point forward.

```dart
@immutable
class MultiCamCutPoint {
  final int timeMicros;           // Timeline position
  final String activeAngleId;     // Which angle to show
  final TransitionType transition; // Cut, dissolve, etc.
  final int transitionDurationMs; // Duration for non-cut transitions

  const MultiCamCutPoint({
    required this.timeMicros,
    required this.activeAngleId,
    this.transition = TransitionType.cut,
    this.transitionDurationMs = 0,
  });
}
```

### Multi-Cam Viewer UI

The multi-cam editing view shows:
- **Multi-view grid:** All angles displayed simultaneously (2x2, 3x3 depending on angle count)
- **Active angle highlight:** Border highlight on the currently active angle
- **Click to switch:** Tapping an angle during playback creates a cut point
- **Timeline:** Shows colored segments indicating which angle is active at each point

### Export

During export, the multi-cam group is "flattened" into a single timeline track:

1. For each cut point range, extract the segment from the appropriate angle's video.
2. Apply sync offsets to ensure frame-accurate alignment.
3. Audio comes from the designated reference angle (or a mixed-down combination).
4. Insert segments into `CompositionBuilder` with proper time mappings.

### Complexity Assessment

**This is a HIGH COMPLEXITY feature.** Multi-camera editing requires:
- Audio analysis infrastructure (new)
- Multi-view rendering (performance intensive)
- Sync offset management (precision critical)
- Custom composition building (extends existing builder significantly)

**Recommendation:** Implement in a later phase after core features (masking, speed, pan & scan) are stable. Start with 2-angle support before generalizing to N angles.

---

## 9. Proxy Editing

### Overview

Proxy editing allows users to work with lower-resolution copies of their source media during editing, then automatically switch to the original full-resolution files at export time. This dramatically improves editing responsiveness for 4K/ProRes footage on mobile devices.

### Current State

The existing `ProxyGenerator.swift` creates 480p proxies for **tracking analysis only**. It uses `AVAssetExportSession` with `AVAssetExportPreset640x480`. This proxy system needs significant extension for general editing:

| Aspect | Current (Tracking Proxy) | Needed (Editing Proxy) |
|--------|--------------------------|------------------------|
| **Resolution** | 480p (fixed) | Configurable (540p, 720p, 1080p) |
| **Purpose** | Vision framework input | Editing playback and preview |
| **Storage** | Temporary, deleted after analysis | Persistent alongside project |
| **Switching** | Not transparent | Automatic switch between proxy/original |
| **Codec** | Default (H.264) | H.264 for speed, HEVC for smaller size |
| **Audio** | Not preserved | Preserved for sync |
| **Metadata** | Not tracked | Linked to original via `MediaAsset` |

### Proxy Asset Model

```dart
@immutable
class ProxyAsset {
  final String id;
  final String originalAssetId;    // References the full-res MediaAsset
  final ProxyResolution resolution;
  final String relativePath;       // Path to proxy file
  final int fileSize;              // Proxy file size in bytes
  final DateTime generatedAt;
  final ProxyStatus status;

  const ProxyAsset({
    required this.id,
    required this.originalAssetId,
    required this.resolution,
    required this.relativePath,
    required this.fileSize,
    required this.generatedAt,
    this.status = ProxyStatus.ready,
  });
}

enum ProxyResolution {
  quarter,     // 1/4 of original (e.g., 4K -> 1080p)
  half,        // 1/2 of original (e.g., 4K -> 2K)
  proxy540p,   // Fixed 540p (iPhone-optimized for editing)
  proxy720p,   // Fixed 720p (good balance)
}

enum ProxyStatus {
  generating,  // Background generation in progress
  ready,       // Available for use
  failed,      // Generation failed
  stale,       // Original was modified since proxy was generated
}
```

### Proxy Generation Pipeline

```
User imports 4K video
        |
        v
MediaAssetRegistry.register(asset)
        |
        v
ProxyGenerationQueue.enqueue(assetId, resolution)
        |
        v
[Background Thread]
    AVAssetExportSession
    - preset based on resolution
    - preserve audio
    - H.264 codec for speed
        |
        v
ProxyAsset created, linked to original
        |
        v
UI switches to proxy for playback
```

### Transparent Switching

The key architectural challenge is making proxy/original switching invisible to the editing UI:

```dart
class ProxyManager extends ChangeNotifier {
  final MediaAssetRegistry _assetRegistry;
  final Map<String, ProxyAsset> _proxiesByOriginalId = {};
  bool _useProxies = true; // User preference

  /// Get the path to use for a given asset ID
  /// Returns proxy path if available and proxies enabled, otherwise original path
  String getPlaybackPath(String assetId) {
    if (!_useProxies) return _assetRegistry.getById(assetId)!.relativePath;

    final proxy = _proxiesByOriginalId[assetId];
    if (proxy != null && proxy.status == ProxyStatus.ready) {
      return proxy.relativePath;
    }
    return _assetRegistry.getById(assetId)!.relativePath;
  }

  /// Toggle proxy mode
  void setUseProxies(bool value) {
    _useProxies = value;
    notifyListeners(); // Triggers recomposition
  }
}
```

### Export from Originals

During export, the system MUST use original full-resolution assets regardless of proxy mode:

```swift
// In CompositionBuilder, before building:
func resolveAssetPath(_ segment: CompositionSegment, proxyManager: ProxyManager?) -> String {
    // Always use original for export
    if isExportMode {
        return segment.originalAssetPath ?? segment.assetPath!
    }
    // For preview, use proxy if available
    return proxyManager?.getPlaybackPath(segment.assetId!) ?? segment.assetPath!
}
```

### Storage Budget

| Source Resolution | Proxy Resolution | Proxy Size (per minute) | Savings |
|------------------|-----------------|------------------------|---------|
| 4K (3840x2160) | 540p | ~8 MB | ~95% |
| 4K (3840x2160) | 720p | ~15 MB | ~90% |
| 1080p | 540p | ~5 MB | ~80% |

---

## 10. Markers & Chapter Points

### Overview

The existing `TimelineMarker` model (in `lib/timeline/data/models/marker.dart`) provides a solid foundation with five marker types (generic, chapter, todo, sync, beat), point and range markers, and full serialization. This section focuses on extending markers for export chapter metadata and navigation enhancements.

### Current Model Strengths

The `TimelineMarker` model is well-designed:
- Immutable with `copyWith`
- Supports point markers and range markers (via `duration` field)
- `MarkerType` enum includes `chapter` and `sync` types (already anticipating these use cases)
- Color-coded with type-specific defaults (blue=generic, green=chapter, orange=todo, purple=sync, pink=beat)
- Full JSON serialization

### Extensions Needed

#### 10.1 Chapter Export Metadata

When exporting a video with chapter markers, the chapter data must be embedded in the output file:

```dart
@immutable
class ChapterMetadata {
  final String title;              // Chapter title (from marker label)
  final String? artworkAssetId;    // Optional thumbnail image
  final String? url;               // Optional URL link
  final Map<String, String> custom; // Custom metadata key-value pairs

  const ChapterMetadata({
    required this.title,
    this.artworkAssetId,
    this.url,
    this.custom = const {},
  });
}
```

Chapter markers are exported using `AVAssetWriter` metadata tracks:

```swift
func addChapterTrack(
    to writer: AVAssetWriter,
    chapters: [(timeMicros: Int, title: String, artwork: Data?)]
) throws {
    // Create chapter metadata track
    let chapterInput = AVAssetWriterInput(
        mediaType: .metadata,
        outputSettings: nil
    )

    // Create metadata adapter for timed metadata
    let adapter = AVAssetWriterInputMetadataAdaptor(
        assetWriterInput: chapterInput
    )
    writer.add(chapterInput)

    // Write chapter metadata groups
    for (index, chapter) in chapters.enumerated() {
        let startTime = CMTime(value: CMTimeValue(chapter.timeMicros), timescale: 1_000_000)
        let endTime: CMTime
        if index + 1 < chapters.count {
            endTime = CMTime(value: CMTimeValue(chapters[index + 1].timeMicros), timescale: 1_000_000)
        } else {
            endTime = writer.overallDurationHint
        }

        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = chapter.title as NSString

        let group = AVTimedMetadataGroup(
            items: [titleItem],
            timeRange: CMTimeRange(start: startTime, end: endTime)
        )
        adapter.append(group)
    }
}
```

#### 10.2 Marker Navigation

Extend the timeline UI with marker-based navigation:

- **Jump to next/previous marker:** Keyboard shortcuts or buttons
- **Marker list panel:** Scrollable list of all markers, tap to seek
- **Marker filtering:** Show/hide markers by type
- **Marker snapping:** Playhead snaps to nearby markers during scrubbing (within configurable threshold)

```dart
class MarkerNavigator {
  final List<TimelineMarker> _markers;

  /// Find the next marker after the given time
  TimelineMarker? nextMarker(int afterTimeMicros) {
    for (final marker in _markers) {
      if (marker.time > afterTimeMicros) return marker;
    }
    return null;
  }

  /// Find the previous marker before the given time
  TimelineMarker? previousMarker(int beforeTimeMicros) {
    TimelineMarker? previous;
    for (final marker in _markers) {
      if (marker.time >= beforeTimeMicros) break;
      previous = marker;
    }
    return previous;
  }

  /// Find marker nearest to time within snap threshold
  TimelineMarker? snapToMarker(int timeMicros, {int thresholdMicros = 100000}) {
    TimelineMarker? nearest;
    int nearestDistance = thresholdMicros;
    for (final marker in _markers) {
      final distance = (marker.time - timeMicros).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = marker;
      }
    }
    return nearest;
  }
}
```

#### 10.3 Beat Detection (Future)

The `MarkerType.beat` type anticipates automatic beat detection for music videos. This would use `AVAudioPCMBuffer` analysis to detect transients (onset detection):

- **Algorithm:** Spectral flux onset detection with adaptive thresholding
- **Implementation:** Accelerate framework FFT + custom peak picking
- **Output:** Array of `TimelineMarker` with `type: .beat` at detected beat positions
- **Use Case:** Auto-generate cut points for music video editing

**Note:** Beat detection is a Phase 3+ feature. The data model is ready; the analysis algorithm is deferred.

---

## 11. Clone/Stamp Tool

### Overview

The clone/stamp tool allows users to duplicate a region of a video frame onto another location within the same frame. This is useful for removing objects, duplicating elements, or creating mirror effects. Unlike traditional photo editors, the video clone/stamp must handle temporal consistency (cloned regions should be consistent across frames).

### Approach

Clone/stamp operates as a per-frame image manipulation using CoreImage:

```
Source Region (sample point)
        |
        v
    CICrop + CIAffineTransform
        |
        v
    CISourceOverCompositing
        |
        v
    Output Frame (source + cloned region)
```

### Data Model

```dart
@immutable
class CloneStampOperation {
  final String id;
  final Offset sourcePoint;      // Normalized center of source region
  final Offset targetPoint;      // Normalized center of destination
  final double radius;           // Normalized brush radius
  final double feather;          // Edge softness (0.0 - 1.0)
  final double opacity;          // Blend opacity
  final bool matchLuminance;     // Adjust brightness to match surrounding area

  const CloneStampOperation({
    required this.id,
    required this.sourcePoint,
    required this.targetPoint,
    this.radius = 0.05,
    this.feather = 0.3,
    this.opacity = 1.0,
    this.matchLuminance = false,
  });
}
```

### Per-Frame Consistency

For video, clone/stamp operations can be:

1. **Static:** Same source and target positions for all frames. Simple but the cloned content may not match if the background moves.
2. **Tracked:** Source and target points follow tracking paths (see Motion Tracking section). The clone region moves with the tracked object.
3. **Keyframed:** Source and target points are keyframed, allowing manual adjustment per frame or at key moments.

### CIFilter Implementation

```swift
func applyCloneStamp(
    to frame: CIImage,
    operation: CloneStampOperation,
    frameSize: CGSize
) -> CIImage {
    // Convert normalized coordinates to pixel coordinates
    let sourceCenter = CGPoint(
        x: CGFloat(operation.sourcePoint.x) * frameSize.width,
        y: CGFloat(operation.sourcePoint.y) * frameSize.height
    )
    let targetCenter = CGPoint(
        x: CGFloat(operation.targetPoint.x) * frameSize.width,
        y: CGFloat(operation.targetPoint.y) * frameSize.height
    )
    let pixelRadius = CGFloat(operation.radius) * max(frameSize.width, frameSize.height)

    // Crop source region
    let sourceRect = CGRect(
        x: sourceCenter.x - pixelRadius,
        y: sourceCenter.y - pixelRadius,
        width: pixelRadius * 2,
        height: pixelRadius * 2
    )
    let sourceRegion = frame.cropped(to: sourceRect)

    // Create circular mask for feathering
    let mask = CIImage(color: .white)
        .cropped(to: CGRect(origin: .zero, size: CGSize(width: pixelRadius * 2, height: pixelRadius * 2)))
        .applyingFilter("CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: pixelRadius, y: pixelRadius),
            "inputRadius0": pixelRadius * (1.0 - CGFloat(operation.feather)),
            "inputRadius1": pixelRadius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.clear,
        ])

    // Translate source region to target position
    let offset = CGAffineTransform(
        translationX: targetCenter.x - sourceCenter.x,
        y: targetCenter.y - sourceCenter.y
    )
    let translatedSource = sourceRegion.transformed(by: offset)
    let translatedMask = mask.transformed(by: CGAffineTransform(
        translationX: targetCenter.x - pixelRadius,
        y: targetCenter.y - pixelRadius
    ))

    // Composite using blend with mask
    return translatedSource.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: frame,
        kCIInputMaskImageKey: translatedMask,
    ])
}
```

### Complexity Assessment

**MEDIUM COMPLEXITY.** The per-frame CIFilter approach is straightforward. The main challenges are:
- UI for selecting source/target regions (gesture handling)
- Temporal consistency for video (tracking integration)
- Performance at high resolution (CIFilter chain cost)

---

## 12. Data Models

### Summary of New Models

| Model | File Location | Purpose |
|-------|---------------|---------|
| `TrackingPath` | `lib/models/tracking_path.dart` | Motion tracking result with per-frame positions |
| `TrackingAttachment` | `lib/models/tracking_attachment.dart` | Links overlay to tracking path |
| `MaskDefinition` | `lib/models/mask.dart` | Mask shape, feather, opacity, keyframes |
| `MaskShapeData` | `lib/models/mask.dart` | Type-specific mask geometry |
| `BrushStroke` | `lib/models/mask.dart` | Freeform brush path data |
| `PanScanRegion` | `lib/models/pan_scan.dart` | Keyframed crop rectangle |
| `SpeedSettings` | `lib/models/speed_settings.dart` | Speed multiplier, blend mode, ramp keyframes |
| `SpeedKeyframe` | `lib/models/speed_settings.dart` | Variable speed point |
| `MultiCamGroup` | `lib/models/multi_cam.dart` | Group of synchronized camera angles |
| `MultiCamAngle` | `lib/models/multi_cam.dart` | Single camera angle with sync offset |
| `MultiCamCutPoint` | `lib/models/multi_cam.dart` | Angle switch point on timeline |
| `ProxyAsset` | `lib/models/proxy_asset.dart` | Low-res proxy file linked to original |
| `ChapterMetadata` | `lib/models/chapter_metadata.dart` | Chapter export data for markers |
| `CloneStampOperation` | `lib/models/clone_stamp.dart` | Clone/stamp source and target regions |

### VideoClip Extensions

The existing `VideoClip` model will gain these optional fields:

```dart
@immutable
class VideoClip extends MediaClip {
  // ... existing fields ...
  final List<Keyframe> keyframes;
  final String? name;

  // NEW: Advanced features
  final SpeedSettings? speedSettings;
  final List<MaskDefinition> masks;
  final List<PanScanKeyframe> panScanKeyframes;
  final String? trackingPathId;
  final String? multiCamGroupId;
  final List<CloneStampOperation> cloneStamps;
}
```

All new fields default to `null` or empty lists, preserving backward compatibility with existing serialization. The `fromJson` factory will use null-coalescing for all new fields.

### MediaAsset Extensions

```dart
@immutable
class MediaAsset {
  // ... existing fields ...

  // NEW: Proxy and multi-cam support
  final String? proxyAssetId;       // Associated proxy, if generated
  final String? multiCamGroupId;    // Multi-cam group membership
}
```

---

## 13. Integration

### Integration with Timeline Architecture V2

All advanced feature operations go through `TimelineManager._execute()`, which automatically handles:
- Undo stack push (existing behavior)
- Redo stack clear (existing behavior)
- Composition dirty flag (existing behavior)
- Listener notification (existing behavior)

New operations added to `TimelineManager`:

```dart
// Speed
void setClipSpeed(String clipId, SpeedSettings settings);

// Masks
void addMask(String clipId, MaskDefinition mask);
void updateMask(String clipId, String maskId, MaskDefinition mask);
void removeMask(String clipId, String maskId);

// Pan & Scan
void setPanScanKeyframes(String clipId, List<PanScanKeyframe> keyframes);

// Clone/Stamp
void addCloneStamp(String clipId, CloneStampOperation operation);
void removeCloneStamp(String clipId, String stampId);
```

### Integration with Export Pipeline

The export pipeline in `VideoProcessingService.swift` gains new responsibilities:

1. **Speed changes:** Time remapping via custom `AVVideoCompositing`
2. **Masks:** CIFilter chain with `CIBlendWithMask` in custom compositor
3. **Pan & scan:** Per-frame `CICrop` + `CILanczosScaleTransform`
4. **Multi-cam:** Segment extraction from correct angles with sync offsets
5. **Chapter markers:** `AVAssetWriterInputMetadataAdaptor` for chapter track
6. **Clone/stamp:** CIFilter chain in custom compositor

### Integration with EffectChain

Masks and clone/stamp operations can interact with the existing Video Effects System:

```
Source Frame
    |
    v
[VideoTransform] (existing)
    |
    v
[Pan & Scan crop] (if configured)
    |
    v
[Effect Chain] (from Video Effects System)
    |
    v
[Mask application] (effects applied only within mask)
    |
    v
[Clone/Stamp] (operates on post-effect frame)
    |
    v
Output Frame
```

### MethodChannel Extensions

New channels for native operations:

```
com.liquideditor/motion_tracking     - Object tracking via Vision
com.liquideditor/frame_interpolation - Optical flow + frame synthesis
com.liquideditor/proxy               - Extended proxy generation (currently exists for tracking)
com.liquideditor/audio_analysis      - Audio sync for multi-cam
```

---

## 14. Edge Cases

### Motion Tracking

| Edge Case | Handling |
|-----------|----------|
| Object leaves frame | Stop tracking, mark final frames as "lost". Allow user to re-initiate. |
| Object fully occluded | Kalman filter prediction for up to 500ms. Beyond that, mark as lost. |
| Very fast motion (blur) | Reduce tracking confidence threshold. Accept lower accuracy over failure. |
| Camera shake during tracking | Apply stabilization filter before tracking (optional preprocessing). |
| Tracking initialization on featureless region | Warn user, suggest selecting a more distinctive region. |
| Multiple similar objects (e.g., tennis balls) | VNTrackObjectRequest may swap targets. Mitigate with IoU-based verification. |

### Masking

| Edge Case | Handling |
|-----------|----------|
| Polygon with > 100 vertices | Simplify with Ramer-Douglas-Peucker before sending to native. Max 500 vertices. |
| Brush strokes exceeding memory | Rasterize strokes into fixed-resolution alpha mask (1024x1024). |
| Mask keyframes with different vertex counts | Disallow vertex count changes between keyframes for polygon masks. |
| Person mask with multiple overlapping people | Use `VNGeneratePersonSegmentationRequest` qualityLevel `.accurate` and select by person index. |
| Inverted mask on fully transparent clip | Result is the effect applied to the entire frame. Display warning. |
| Feather > 50% of frame size | Clamp feather to prevent full-frame blur. |

### Speed Manipulation

| Edge Case | Handling |
|-----------|----------|
| Speed 0.0x (freeze) | Treat as freeze frame: hold a single frame for the clip's duration. |
| Speed > 100x | Cap at 100x. Beyond this, frame sampling artifacts are unacceptable. |
| Speed change on clip with keyframes | Remap keyframe timestamps proportionally. Warn user. |
| Audio at extreme speeds (< 0.25x or > 4x) | Mute audio. Pitch correction artifacts are too severe. |
| Speed ramp crossing 0.0x | Disallow zero-crossing. Minimum speed is 0.01x. |
| Speed change affecting timeline duration | Recalculate clip duration. Update `PersistentTimeline` via `updateItem`. |

### Multi-Camera

| Edge Case | Handling |
|-----------|----------|
| Audio sync fails (no shared audio event) | Fall back to manual sync. Show waveforms side-by-side. |
| Angles with different frame rates | Normalize to highest frame rate. Insert frame duplicates as needed. |
| Angles with different resolutions | Scale all to match the reference angle's resolution during multi-view. |
| Angle added mid-edit (after cuts exist) | Re-sync and preserve existing cut points. New angle is available from its sync start. |
| All angles have no audio | Require manual sync (timecode or visual cue matching). |
| Sync offset drift over time (clock skew) | Alert user. Allow manual drift correction with a "drift rate" parameter. |

### Proxy Editing

| Edge Case | Handling |
|-----------|----------|
| Original file deleted/moved | Mark proxy as orphaned. Attempt relink via `contentHash`. |
| Proxy generation interrupted | Mark as `ProxyStatus.failed`. Allow retry. |
| Proxy and original have different durations (encoding artifact) | Use original duration as source of truth. Clamp proxy reads. |
| Disk space insufficient for proxies | Warn user before generation. Allow generating proxies for selected clips only. |
| Export started while proxies are generating | Block export until all required proxies are ready, or export from originals directly. |

---

## 15. Performance

### Performance Budgets by Feature

| Feature | Preview (60fps) | Export | Notes |
|---------|-----------------|--------|-------|
| **Motion Tracking** | N/A (background) | N/A (pre-computed) | ~2ms/frame on Neural Engine |
| **Shape Masks** | < 3ms/frame | < 5ms/frame | CIFilter chain, GPU accelerated |
| **Brush Masks** | < 5ms/frame | < 8ms/frame | Rasterize to texture first |
| **Person Masks** | < 15ms/frame | < 20ms/frame | VNGeneratePersonSegmentation |
| **Pan & Scan** | < 2ms/frame | < 3ms/frame | CICrop + CILanczosScale |
| **Slow Motion (blend)** | < 3ms/frame | < 3ms/frame | CIDissolveTransition |
| **Slow Motion (optical flow)** | N/A (pre-render) | < 60ms/frame | VNGenerateOpticalFlow + warp |
| **Frame Interpolation** | N/A (pre-render) | < 60ms/frame | Same as optical flow slow-mo |
| **Multi-Cam Multi-View** | < 8ms total | N/A | 4 simultaneous 540p decodes |
| **Proxy Switching** | < 1ms | 0ms | Path resolution only |
| **Markers (navigation)** | < 0.1ms | N/A | Binary search on sorted list |
| **Clone/Stamp** | < 4ms/frame | < 6ms/frame | CIFilter chain |

### Memory Budget

| Feature | Memory Impact | Notes |
|---------|--------------|-------|
| Tracking path (1 min video, 30fps) | ~144 KB | 1800 points x 80 bytes |
| Mask rasterized texture | 4 MB | 1024x1024 RGBA |
| Optical flow field (1080p) | 8 MB | 1920x1080 x 2 channels x float16 |
| Proxy asset (1 min, 540p) | ~5 MB disk | Not in RAM during editing |
| Multi-cam 4-angle decode | ~200 MB | 4 simultaneous decoder buffers |
| Frame interpolation cache | ~50 MB | 20 pre-rendered frames at 1080p |

### GPU Utilization

Features are designed to run on the GPU via CoreImage and Metal:

- **CIFilter chains** (masks, clone/stamp, pan & scan) execute entirely on GPU.
- **Vision framework** (tracking, optical flow, person segmentation) uses Neural Engine when available, falling back to GPU.
- **Composition rendering** uses AVFoundation's built-in GPU pipeline.

**Critical constraint:** Multiple GPU-intensive features running simultaneously may cause frame drops. The rendering pipeline must prioritize the active preview and defer background work:

1. Preview rendering: **Highest priority** (display link callback)
2. Frame interpolation pre-render: **User-initiated priority** (background queue)
3. Proxy generation: **Utility priority** (background queue)
4. Tracking analysis: **Utility priority** (background queue)

---

## 16. Testing Strategy

### Unit Tests

| Test Area | Test File | Coverage |
|-----------|-----------|----------|
| `TrackingPath` model | `test/models/tracking_path_test.dart` | Serialization, interpolation, point access |
| `MaskDefinition` model | `test/models/mask_test.dart` | All mask types, feathering, inversion, serialization |
| `SpeedSettings` model | `test/models/speed_settings_test.dart` | Duration calculation, speed ramp interpolation |
| `MultiCamGroup` model | `test/models/multi_cam_test.dart` | Angle sync offsets, cut point ordering |
| `ProxyAsset` model | `test/models/proxy_asset_test.dart` | Status transitions, link/unlink |
| `PanScanRegion` model | `test/models/pan_scan_test.dart` | Rect interpolation, rotation |
| `CloneStampOperation` model | `test/models/clone_stamp_test.dart` | Coordinate validation, serialization |
| `ChapterMetadata` model | `test/models/chapter_metadata_test.dart` | Serialization, default values |
| `MarkerNavigator` | `test/core/marker_navigator_test.dart` | Next/previous/snap search |
| `VideoClip extensions` | `test/models/clips/video_clip_extended_test.dart` | New fields serialization backward compat |

### Integration Tests

| Test Area | Description |
|-----------|-------------|
| Speed change + timeline duration | Verify `PersistentTimeline` correctly recalculates total duration when clip speed changes |
| Mask + effect chain | Verify masked effect applies only within mask region |
| Pan & scan + export | Verify exported video has correct crop at sampled frames |
| Proxy switch + composition | Verify composition uses proxy for preview and original for export |
| Tracking path + overlay | Verify overlay position matches tracking path at test timestamps |
| Multi-cam sync | Verify audio cross-correlation produces correct offsets with known test audio |

### Native Tests (XCTest)

| Test Area | Description |
|-----------|-------------|
| `MotionTrackingService` | Track a known object in a test video, verify bounding box trajectory |
| `FrameInterpolator` | Interpolate between two frames, verify output dimensions and non-nil result |
| `MaskRenderer` | Render each mask type, verify output CIImage dimensions |
| `CloneStampRenderer` | Apply clone/stamp, verify pixel values at target match source |
| `ChapterTrackWriter` | Write chapter metadata to test file, read back and verify |

---

## 17. Implementation Plan

### Phased Approach

The 10 features are grouped into 4 phases based on complexity, dependencies, and user value:

#### Phase 1: Foundation (Estimated: 3-4 weeks)

Features that extend existing infrastructure with moderate complexity:

| Feature | Effort | Dependencies | User Value |
|---------|--------|--------------|------------|
| **Markers & Chapters** | Low | Existing `TimelineMarker` model | High (navigation, export chapters) |
| **Pan & Scan (Ken Burns)** | Medium | Existing keyframe system, `VideoTransform` | High (widely used for photo slideshows, establishing shots) |
| **Time-Lapse** | Low | `AVMutableCompositionTrack.scaleTimeRange` | Medium (simple speed-up) |

**Deliverables:**
- `MarkerNavigator` class with next/prev/snap
- Chapter export via `AVAssetWriterInputMetadataAdaptor`
- `PanScanRegion` model + keyframe interpolation
- Pan & scan UI overlay (crop rectangle editor)
- Time-lapse speed multiplier on `VideoClip` (speeds > 1.0x)
- `SpeedSettings` model (uniform speed only, no ramps)

#### Phase 2: Core Advanced (Estimated: 4-6 weeks)

Features that require new native infrastructure:

| Feature | Effort | Dependencies | User Value |
|---------|--------|--------------|------------|
| **Masking (shapes)** | Medium | CIFilter pipeline, custom compositor | High (selective effects) |
| **Slow Motion (frame blending)** | Medium | `SpeedSettings` from Phase 1 | High (creative speed effects) |
| **Proxy Editing** | Medium | Extended `ProxyGenerator`, `MediaAsset` | High (4K workflow enablement) |
| **Clone/Stamp** | Medium | CIFilter pipeline | Medium (content-aware editing) |

**Deliverables:**
- `MaskDefinition` model (rectangle, ellipse, polygon)
- Mask rendering via CIFilter chain
- Mask UI (shape drawing, feather slider)
- Slow motion with frame blending (`CIDissolveTransition`)
- `ProxyAsset` model + `ProxyManager`
- Extended `ProxyGenerator` with resolution options and audio preservation
- `CloneStampOperation` model + CIFilter rendering
- Clone/stamp UI (source/target selection)

#### Phase 3: High Complexity (Estimated: 6-8 weeks)

Features requiring significant new systems:

| Feature | Effort | Dependencies | User Value |
|---------|--------|--------------|------------|
| **Motion Tracking (generic objects)** | High | `VNTrackObjectRequest`, Kalman filter | High (overlay attachment) |
| **Brush Masks** | Medium | Gesture system, rasterization | Medium (precise masking) |
| **Frame Interpolation (optical flow)** | High | `VNGenerateOpticalFlowRequest`, Metal shader | High (smooth slow-mo) |

**Deliverables:**
- `MotionTrackingService.swift` with `VNTrackObjectRequest`
- `TrackingPath` model + `TrackingAttachment`
- Tracking UI (tap to select, path preview)
- `BrushStroke` model + gesture capture for painting masks
- Brush mask rasterization pipeline
- `FrameInterpolator` with optical flow + Metal warp shader
- Background pre-rendering pipeline for interpolated frames

#### Phase 4: Professional (Estimated: 8-10 weeks)

The most complex feature with the most new infrastructure:

| Feature | Effort | Dependencies | User Value |
|---------|--------|--------------|------------|
| **Multi-Camera Editing** | Very High | Audio analysis, multi-view rendering, composition builder extension | High (professional workflow) |
| **Speed Ramps** | Medium | Phase 2 slow motion, custom `AVVideoCompositing` | Medium (creative speed curves) |
| **Beat Detection** | Medium | Audio analysis from multi-cam, FFT | Medium (music video workflow) |

**Deliverables:**
- Audio cross-correlation sync engine (Accelerate framework)
- `MultiCamGroup`, `MultiCamAngle`, `MultiCamCutPoint` models
- Multi-view renderer (2x2, 3x3 grid)
- Multi-cam angle switching UI
- Multi-cam composition flattening for export
- Speed ramp keyframe editor UI
- Variable speed time remapping in custom compositor
- Beat detection algorithm (spectral flux onset detection)

### Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Optical flow quality insufficient on mobile | High | Fall back to frame blending. Test on A14, A15, A16, A17 devices. |
| Multi-cam audio sync fails with music-only content | Medium | Provide manual sync UI as fallback. Visual waveform alignment. |
| CIFilter chain too slow for real-time mask preview | Medium | Downsample preview to 720p. Cache mask textures across frames. |
| Proxy/original switching causes composition rebuild | Low | Use double-buffered composition (existing architecture). |
| Tracking loss rate too high for reliable overlay attachment | Medium | Provide manual keyframe correction UI for lost segments. |
| Memory pressure from multi-cam 4-angle decode | High | Decode at 540p for multi-view. Only decode active angle at full resolution. |
| Speed changes invalidating existing keyframe timestamps | Medium | Remap keyframes automatically. Show confirmation dialog to user. |
| Frame interpolation Metal shader compatibility across devices | Low | All target devices (A14+) support Metal 2.4+. Test on oldest supported device. |

### Success Criteria

A feature from this design is COMPLETE when:

1. Dart model is `@immutable` with `copyWith` and full JSON serialization (backward compatible)
2. Native implementation uses approved Apple frameworks (Vision, CoreImage, AVFoundation, Metal)
3. `flutter analyze` reports 0 issues
4. `flutter test` passes 100% including new model tests
5. Preview playback maintains 60 FPS (or gracefully falls back to lower quality)
6. Export produces correct output verified by automated test
7. Undo/redo works for all operations (via `TimelineManager._execute`)
8. UI uses exclusively native iOS 26 Liquid Glass components
9. Analysis files updated for all modified/created files
10. This design document is updated with implementation notes and actual performance measurements

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Senior Architect)
**Date:** 2026-02-06
**Files Reviewed:** Design document + 8 codebase source files (VideoProcessingService.swift, CompositionBuilder.swift, CompositionManagerService.swift, video_clip.dart, keyframe.dart, marker.dart, media_asset.dart, timeline_manager.dart, BoundingBoxTracker.swift, TrackingDataStore.swift, KalmanFilter.swift, timeline_item.dart, persistent_timeline.dart)

---

### Architecture Assessment

**Overall Grade: B+**

The document demonstrates strong architectural thinking with a clear "data over behavior" philosophy, proper immutable model patterns, and realistic phasing. The design correctly extends existing systems rather than replacing them. However, several integration gaps and API correctness issues need resolution before implementation.

**Strengths:**
- Consistent with the established codebase patterns (immutable models, `copyWith`, JSON serialization)
- Correct use of `_execute()` pattern in `TimelineManager` for undo/redo integration
- Appropriate use of Apple frameworks (Vision, CoreImage, AVFoundation, Accelerate)
- Realistic phasing that respects dependency ordering
- Thorough edge case analysis

**Weaknesses:**
- Several API signatures do not match actual codebase implementations
- Missing critical detail on custom `AVVideoCompositing` protocol, which is the linchpin for masks, speed changes, and multi-cam
- Frame interpolation warp shader is left as a placeholder -- this is the hardest part of the feature
- Proxy system does not address how `CompositionBuilder` resolves paths today

---

### Codebase Verification

#### 1. Vision Framework Usage

**VNTrackObjectRequest (Section 3):** CORRECT in principle. The API usage is valid:
- `VNSequenceRequestHandler` is the correct handler for sequential frame tracking
- `VNDetectedObjectObservation` is the correct observation type
- `VNRequestTrackingLevel` (.fast, .accurate) is a real API
- Performance estimate of ~2ms on Neural Engine is reasonable for A14+

**Mismatch with existing tracker:** The document claims (Section 2) that `BoundingBoxTracker` uses `VNDetectHumanBodyPoseRequest`. Verified: this is CORRECT -- `BoundingBoxTracker.swift` line 105 creates `VNDetectHumanBodyPoseRequest()` and uses it for person-specific bounding box tracking. The document correctly identifies that generic object tracking needs `VNTrackObjectRequest`, which is a fundamentally different API (tracking an observation across frames vs. detecting per-frame).

**ISSUE:** The document proposes `MotionTrackingService` as a new Swift class but does not explain how it coexists with the existing `TrackingService.swift`. The existing `TrackingService` orchestrates `BoundingBoxTracker`, `TrackingDataStore`, `TrackReidentifier`, etc. The new `MotionTrackingService` must either extend `TrackingService` or be clearly scoped as a parallel service for non-person tracking. The document does not address this.

**VNGenerateOpticalFlowRequest (Section 7):** CORRECT API usage. The code sample correctly:
- Creates the request with a `targetedCVPixelBuffer`
- Sets `computationAccuracy` and `outputPixelFormat`
- Uses `VNImageRequestHandler` (not the sequence handler -- correct for single-pair flow)
- Accesses `results?.first` for the observation
- Notes the float16 2-channel output format

**ISSUE:** `VNGenerateOpticalFlowRequest` was introduced in iOS 14, not "iOS 14+" as stated. The minimum target is iOS 18.0 per the project config, so this is fine, but the framing suggests the iOS 14 requirement is somehow a constraint when it is not.

#### 2. Masking Architecture

**CIBlendWithMask approach (Section 4):** CORRECT. `CIBlendWithMask` is the standard CoreImage filter for compositing with a mask. The pipeline description (source frame + mask + effect -> CIBlendWithMask) is architecturally sound.

**ISSUE: CIBlendWithMask parameter names.** The document uses `kCIInputBackgroundImageKey` and `kCIInputMaskImageKey` which are correct. However, the rendered pipeline diagram shows:
```
Input: source
Background: effect
Mask: generated
```
This is semantically inverted. In `CIBlendWithMask`, `inputImage` is the foreground (the effected version), `inputBackgroundImage` is the background (original), and `inputMaskImage` determines where the foreground shows through. The diagram should be:
```
Input: effected frame (effect applied to entire frame)
Background: original frame (unaffected)
Mask: mask region (white = show effected, black = show original)
```

**Feathering via CIGaussianBlur:** CORRECT approach. Blurring the binary mask is the standard technique. The `.cropped(to: mask.extent)` call after blur is essential to prevent the blur from expanding the image bounds -- good detail.

**ISSUE: Maximum feather calculation.** The code uses `max(frameSize.width, frameSize.height) * 0.1` as the maximum feather radius. For a 4K frame (3840x2160), this gives a maximum blur radius of 384 pixels, which would require a very large kernel. `CIGaussianBlur` performance degrades significantly at large radii (>50px). The design should specify a practical maximum (e.g., 100px) or document that large feather values will be clamped for performance.

**Shape mask generation specifics:**
- Rectangle via `CICrop`: Technically CICrop produces a hard rectangle, so feathering requires the separate blur step. This is correct.
- Ellipse via `CIRadialGradient`: This works for circles but the document correctly notes `CIAffineTransform` is needed for non-circular ellipses. CORRECT.
- Polygon via `CGContext` rendering: This requires leaving the CIFilter GPU pipeline to render into a CPU bitmap, then re-uploading as CIImage. This is a performance bottleneck for complex polygons. The document should note this CPU/GPU roundtrip cost.
- Person via `VNGeneratePersonSegmentationRequest`: CORRECT. The output is already a `CVPixelBuffer` that can be wrapped as `CIImage`.

#### 3. Speed / Time-Lapse

**`scaleTimeRange(_:toDuration:)` (Section 6):** CORRECT. This is the standard AVFoundation API for uniform time remapping. The code example is valid:
```swift
try compositionTrack.scaleTimeRange(sourceRange, toDuration: targetDuration)
```

**ISSUE: `effectiveDurationMicros` calculation.** The Dart model calculates:
```dart
int effectiveDurationMicros(int sourceDurationMicros) =>
    (sourceDurationMicros / speedMultiplier).round();
```
This is mathematically correct (2x speed = half duration), but it does not account for speed ramps. When `rampKeyframes` is non-empty, the effective duration requires integrating `1/speed(t)` over the source duration. The document has the `buildTimeRemapping` function in Swift but the Dart-side `effectiveDurationMicros` method would give incorrect results for ramped clips. This needs a comment or a more complete implementation.

**ISSUE: Timeline duration recalculation.** When a clip's speed changes, its effective duration changes. The design correctly identifies this in edge cases (Section 14: "Recalculate clip duration. Update `PersistentTimeline` via `updateItem`"). However, `VideoClip.durationMicroseconds` is computed as `sourceOutMicros - sourceInMicros` (line 122 of `timeline_item.dart`). Changing speed does NOT change `sourceInMicros` or `sourceOutMicros`. This means the `PersistentTimeline` tree would have an incorrect duration for speed-changed clips. **This is a fundamental data model issue.** Either:
  - (a) `VideoClip` must override `durationMicroseconds` to account for speed, or
  - (b) Speed-changed clips must adjust their source out point to simulate the new duration, or
  - (c) The timeline must store an explicit `timelineDurationMicros` field that overrides the computed value.

Option (a) is the cleanest. The document must address this explicitly.

**Audio handling:** The `AVAudioTimePitchAlgorithm.spectral` recommendation is correct. The speed-range-to-audio-treatment table is reasonable and matches real-world expectations.

#### 4. Frame Interpolation

**Optical flow approach (Section 7):** The choice of `VNGenerateOpticalFlowRequest` is reasonable for mobile. The document correctly identifies that:
- Real-time preview is NOT feasible (~60ms per frame at best)
- Background pre-rendering is the right strategy
- Frame blending is the fallback for real-time preview

**CRITICAL ISSUE: The warp shader is a placeholder.** The `warpWithFlow` function (line 655-671) contains:
```swift
// Placeholder: Use Metal compute shader for production
// For now, fall back to blend
return blendFrames(frame1, frame2, factor: factor)
```
This means the entire optical flow feature currently has no actual implementation beyond what `CIDissolveTransition` already provides. The Metal compute shader for per-pixel warping based on flow vectors is the core technical challenge of this feature. The design must either:
1. Provide the Metal shader specification (input layout, kernel signature, thread group size)
2. Reference a concrete implementation approach (e.g., using `MPSImageBilinearScale` with custom remapping)
3. Acknowledge this as a research spike with uncertain outcome

Without the warp shader, "optical flow frame interpolation" is just "frame blending with extra steps and 60ms overhead."

**Performance note:** The 50ms estimate for `VNGenerateOpticalFlowRequest` is reasonable for A14+ at 1080p with `.medium` accuracy. However, the document should note that `.high` accuracy can take 100-200ms per frame pair, which may be needed for quality results.

#### 5. Multi-Camera Audio Sync

**Cross-correlation approach (Section 8):** CORRECT in principle. Cross-correlation of audio waveforms is the standard technique for audio-based sync.

**ISSUE: `vDSP_conv` usage.** The function signature shown is:
```swift
vDSP_conv(referenceAudio, 1, targetAudio, 1, &result, 1,
          vDSP_Length(resultLength), vDSP_Length(targetAudio.count))
```
This is the convolution function, not correlation. For cross-correlation, one of the signals should be time-reversed, or `vDSP_correlate` (which is actually just `vDSP_conv` with reversed second input) should be used. The actual signature of `vDSP_conv` for correlation requires the filter to be passed in reverse order. The current code would compute convolution, not correlation. The peak of the convolution does not correspond to the sync offset in the same way.

**CORRECTION NEEDED:** Either:
1. Time-reverse `targetAudio` before passing to `vDSP_conv`, or
2. Use `vDSP_crosscorr` (not a real function; Accelerate does correlation via `vDSP_conv` with reversed input), or
3. Use FFT-based cross-correlation: FFT both signals, multiply (conjugate of one), inverse FFT. This is also faster for long signals (O(n log n) vs O(n^2)).

**Performance estimate:** "200ms for 60-second audio at 8kHz" is optimistic. 60 seconds at 8kHz = 480,000 samples. Cross-correlation of two 480K-sample signals via `vDSP_conv` is O(n*m). FFT-based approach would be much faster and should be recommended.

**Practical concern:** Audio sync can fail when cameras have different audio environments (e.g., one camera close to speakers, another far away). The document mentions this in edge cases but should recommend normalizing audio (RMS normalization) before cross-correlation to handle level differences.

#### 6. Proxy System Integration with MediaAssetRegistry

**ProxyManager design (Section 9):** The `ProxyManager` correctly uses `MediaAssetRegistry` for path resolution. The `getPlaybackPath` method is clean.

**ISSUE: `CompositionBuilder` path resolution.** The existing `CompositionBuilder.swift` (line 250) gets asset paths from `CompositionSegment.assetPath`. The proxy system proposes resolving paths in `CompositionBuilder` directly:
```swift
func resolveAssetPath(_ segment: CompositionSegment, proxyManager: ProxyManager?) -> String
```
But `ProxyManager` is a Dart-side `ChangeNotifier` class. It cannot be passed directly to the native Swift `CompositionBuilder`. The path resolution must happen on the Dart side before segments are serialized and sent to native via the method channel. The design should specify that `CompositionManagerService` receives already-resolved paths (proxy paths for preview, original paths for export), not that `CompositionBuilder` performs the resolution itself.

**ISSUE: Missing `CompositionSegment` extension.** The existing `CompositionSegment` struct does not have an `originalAssetPath` field. The proxy system would need to either:
1. Add `originalAssetPath` to `CompositionSegment` (for export fallback), or
2. Always send the correct path from Dart side (proxy for preview, original for export)

Option 2 is simpler and aligns with "data over behavior" philosophy.

**Storage budget:** The estimates are reasonable. 540p proxy at ~8MB/minute for 4K source is consistent with H.264 at reasonable bitrate.

#### 7. Markers & Chapter Points

**TimelineMarker extension (Section 10):** The existing `TimelineMarker` model (verified in `marker.dart`) is well-designed and already includes `MarkerType.chapter` and `MarkerType.sync` types. The document correctly identifies that only the export pathway and navigation utilities are needed.

**ChapterMetadata model:** Clean and minimal. The `artworkAssetId` reference is a nice touch for thumbnail chapters.

**Chapter export via AVAssetWriter:** The `AVAssetWriterInputMetadataAdaptor` approach is CORRECT. This is Apple's recommended way to write timed metadata (chapters) into MP4/MOV files.

**ISSUE: `writer.overallDurationHint` usage.** The code uses `writer.overallDurationHint` for the last chapter's end time. `overallDurationHint` is a hint set before writing begins; if not set, it defaults to `.invalid`. The code should fall back to the total composition duration passed as a parameter, not rely on `overallDurationHint`.

**MarkerNavigator:** The implementation is functionally correct but uses O(n) linear scan for all three operations. The `TimelineMarker` list is described as sorted, so binary search would be more appropriate for `nextMarker` and `previousMarker`. For `snapToMarker`, a binary search to find the closest could reduce from O(n) to O(log n). Given that marker counts are typically small (< 100), this is a minor performance note, not a blocking issue.

**ISSUE: Missing integration with `TimelineManager`.** The document proposes `MarkerNavigator` as a standalone class. But markers are currently managed by `MarkerController` (in `lib/timeline/editing/marker_controller.dart`). The design should specify how `MarkerNavigator` relates to the existing `MarkerController` -- is it a helper used by `MarkerController`, or a replacement?

#### 8. Integration Assessment

**Timeline integration (Section 13):** The proposed `TimelineManager` extensions are well-designed:
```dart
void setClipSpeed(String clipId, SpeedSettings settings);
void addMask(String clipId, MaskDefinition mask);
void updateMask(String clipId, String maskId, MaskDefinition mask);
```
These correctly follow the existing pattern of `TimelineManager` mutation methods that call `_execute()`.

**ISSUE: `_execute()` only works for `PersistentTimeline` mutations.** The `_execute` method (line 119 of `timeline_manager.dart`) takes a `PersistentTimeline Function()` mutation. Adding a mask to a `VideoClip` requires:
1. Getting the clip from the timeline
2. Creating a new clip with the mask added
3. Calling `updateItem` on the timeline
This is similar to how `addKeyframe` works (line 288). However, `VideoClip` currently has no `masks` field, no `speedSettings` field, etc. **All of these fields must be added to `VideoClip` first** and the `copyWith`, `toJson`, and `fromJson` methods must be updated. The document mentions this (Section 12) but does not show the actual implementation of the updated `VideoClip` constructor, `copyWith`, or serialization. This is significant work that should be estimated.

**Export integration:** The document correctly identifies that masks, speed changes, and multi-cam require a custom `AVVideoCompositing` protocol implementation. The existing `CompositionBuilder` uses `AVMutableVideoCompositionInstruction` with identity transforms only (verified: line 384 of `CompositionBuilder.swift` sets `.identity` transform). A custom compositor is a MAJOR addition that the document references but does not design.

**CRITICAL MISSING DESIGN:** The custom `AVVideoCompositing` protocol implementation is mentioned in passing (Section 2, Section 6, Section 13) but never fully specified. This is the single most important native component needed for masks, speed changes, clone/stamp, and multi-cam rendering. The design should include:
1. The `AVVideoCompositing` class structure
2. The custom `AVVideoCompositionInstructionProtocol` definition
3. How per-frame rendering dispatches to CIFilter chains
4. Thread safety (the compositor's `renderContextChanged` and `startRequest` are called on different threads)
5. How it integrates with the existing `CompositionBuilder`

**MethodChannel extensions:** The four new channels are reasonable. However, the existing channel architecture should be documented -- how many channels exist today and whether consolidation is appropriate.

#### 9. Performance Assessment

**Performance budgets (Section 15):**

| Feature | Budget Realistic? | Notes |
|---------|-------------------|-------|
| Shape masks < 3ms | YES | Simple CIFilter chains are very fast on GPU |
| Brush masks < 5ms | MARGINAL | Depends on stroke count and rasterization approach |
| Person masks < 15ms | YES | VNGeneratePersonSegmentationRequest is well-optimized |
| Pan & scan < 2ms | YES | CICrop + scale is trivial |
| Slow motion blend < 3ms | YES | Single CIFilter |
| Optical flow < 60ms | OPTIMISTIC | 50ms for flow + 5ms for warp = 55ms leaves little headroom |
| Multi-cam multi-view < 8ms | VERY OPTIMISTIC | 4 simultaneous 540p decodes is decoder-limited, not GPU-limited |
| Markers < 0.1ms | YES | Simple binary search |
| Clone/stamp < 4ms | YES | CIFilter chain |

**Multi-cam multi-view concern:** Simultaneously decoding 4 video streams at 540p requires 4 active `AVAssetReader` instances. iOS limits the number of concurrent hardware decoders (typically 4-6 on modern chips). At 540p H.264, each decoder can handle this, but the combined memory for decoder buffers (~200MB noted in the document) is a significant portion of the 200MB app memory budget from CLAUDE.md. This needs careful testing on actual devices.

**ISSUE: Memory budget conflict.** The CLAUDE.md performance budget states "Memory: < 200MB for typical use (excluding frame cache)." The multi-cam feature alone requests ~200MB for decoder buffers (Section 15). This exceeds the budget. The document should address this by either:
1. Increasing the memory budget for multi-cam workflows
2. Reducing decoder buffer requirements (e.g., decode only 2 angles at full rate, thumbnail the others)
3. Making multi-cam a "pro" feature with different memory constraints

#### 10. Complexity & Timeline Assessment

**Phase 1 (3-4 weeks): Foundation**
- Markers & Chapters: LOW complexity, estimate reasonable
- Pan & Scan: MEDIUM complexity, estimate reasonable
- Time-Lapse: LOW complexity, estimate reasonable

**Phase 2 (4-6 weeks): Core Advanced**
- Masking (shapes): MEDIUM complexity, but requires custom `AVVideoCompositing` which is HIGH. Underestimated.
- Slow Motion (blend): MEDIUM, estimate reasonable
- Proxy Editing: MEDIUM, estimate reasonable
- Clone/Stamp: MEDIUM, estimate reasonable

**Phase 3 (6-8 weeks): High Complexity**
- Motion Tracking: HIGH, estimate reasonable
- Brush Masks: MEDIUM, estimate reasonable
- Frame Interpolation: **VERY HIGH**, underestimated. The Metal warp shader alone could take 2-4 weeks of R&D.

**Phase 4 (8-10 weeks): Professional**
- Multi-Camera: VERY HIGH, estimate reasonable
- Speed Ramps: MEDIUM, estimate reasonable
- Beat Detection: MEDIUM, estimate reasonable

**Overall timeline: 21-28 weeks (5-7 months).** This is aggressive but achievable for a dedicated team. For a single developer with Claude Code assistance, add 30-50% buffer.

---

### Critical Issues

**C1. Missing Custom AVVideoCompositing Design (Severity: BLOCKING)**
The document references custom video composition in 5+ places but never specifies the implementation. This is the foundational native component that enables masks, speed changes, clone/stamp, and multi-cam during export and preview. Without this design, Phases 2-4 cannot be implemented.

**Action Required:** Add a new section (or sub-section of Section 13) titled "Custom Video Compositor" that specifies:
- `CustomVideoCompositor: AVVideoCompositing` class
- `CustomCompositionInstruction: AVVideoCompositionInstructionProtocol` class
- Per-frame rendering pipeline (CIContext + CIFilter chain)
- Thread safety model
- Integration with existing `CompositionBuilder`

**C2. VideoClip Duration Incorrect After Speed Change (Severity: BLOCKING)**
`VideoClip.durationMicroseconds` (inherited from `MediaClip`) is computed as `sourceOutMicros - sourceInMicros`. Changing speed does NOT change these values, so the timeline tree will have incorrect durations for speed-changed clips. This breaks `PersistentTimeline`'s duration-based O(log n) lookup.

**Action Required:** Either override `durationMicroseconds` in `VideoClip` to account for `speedSettings?.effectiveDurationMicros(sourceDuration)`, or add an explicit `timelineDurationOverrideMicros` field. Document the chosen approach and its impact on `PersistentTimeline` tree augmentation.

**C3. Frame Interpolation Warp Shader Is a Placeholder (Severity: HIGH)**
Without the Metal warp shader, optical flow frame interpolation provides zero benefit over simple frame blending. The document should either specify the shader or mark this as a research spike with a fallback plan.

**Action Required:** Either provide a Metal shader specification or add a "Research Spike" milestone before Phase 3 that validates the approach with a prototype.

---

### Important Issues

**I1. Cross-Correlation vs Convolution for Audio Sync (Severity: MEDIUM)**
The `vDSP_conv` usage computes convolution, not cross-correlation. The sync offset calculation will be incorrect.

**Action Required:** Use FFT-based cross-correlation (FFT -> conjugate multiply -> IFFT) or reverse one input signal before `vDSP_conv`.

**I2. CIBlendWithMask Semantics Inverted in Diagram (Severity: MEDIUM)**
The pipeline diagram shows "Input: source, Background: effect" which is backwards. This could lead to incorrect implementation.

**Action Required:** Correct the diagram to show "Input: effected frame, Background: original frame, Mask: region selector."

**I3. ProxyManager Path Resolution is Dart-Side, Not Swift-Side (Severity: MEDIUM)**
The document shows proxy resolution happening in `CompositionBuilder` (Swift) but `ProxyManager` is a Dart class. The path resolution must happen before segments are sent to native.

**Action Required:** Clarify that path resolution is done in Dart. The method channel payload should contain the already-resolved paths. Remove the Swift-side `resolveAssetPath` function.

**I4. Relationship Between MotionTrackingService and Existing TrackingService (Severity: MEDIUM)**
The document proposes `MotionTrackingService` without explaining how it relates to the existing `TrackingService` -> `BoundingBoxTracker` -> `TrackingDataStore` pipeline.

**Action Required:** Specify whether `MotionTrackingService` is a new parallel service (separate from person tracking) or an extension of `TrackingService`. If parallel, document how they share resources (e.g., `ProxyGenerator`).

**I5. MarkerNavigator Relationship to Existing MarkerController (Severity: LOW-MEDIUM)**
The document does not explain how `MarkerNavigator` integrates with the existing `MarkerController` in `lib/timeline/editing/marker_controller.dart`.

**Action Required:** Specify whether `MarkerNavigator` is used by `MarkerController` or replaces some of its functionality.

**I6. Memory Budget Exceeded by Multi-Cam (Severity: MEDIUM)**
Multi-cam requires ~200MB for decoder buffers, which equals the entire app memory budget.

**Action Required:** Either relax the memory budget for multi-cam workflows or reduce simultaneous decoder count.

---

### Minor Issues

**M1.** The `SpeedSettings.effectiveDurationMicros` method does not handle speed ramps (only uses `speedMultiplier`). Add a comment noting this limitation or implement the integration.

**M2.** The `MaskShapeData` class uses nullable fields for every shape type. Consider using a sealed class hierarchy (`MaskShapeData.rectangle`, `MaskShapeData.ellipse`, etc.) to enforce type safety and prevent invalid combinations.

**M3.** The `CloneStampOperation` in Section 11 creates a mask using `CIRadialGradient` but passes `CIColor.white` and `CIColor.clear` as parameters. `CIRadialGradient` takes `inputColor0` and `inputColor1` as `CIColor` values -- verify that `.clear` is correctly interpreted (should be `CIColor(red: 0, green: 0, blue: 0, alpha: 0)`).

**M4.** The `PanScanRegion` data model in Section 5 is defined but a `PanScanKeyframe` type is referenced later (`List<PanScanKeyframe>` on `VideoClip`) without definition. This type needs to be specified -- it presumably wraps `PanScanRegion` with a timestamp and `InterpolationType`.

**M5.** The `MarkerNavigator.nextMarker` and `previousMarker` methods use linear scan. Since markers are sorted by time, binary search would be more appropriate. Minor given typical marker counts.

**M6.** The `MultiCamCutPoint` references `TransitionType` which is not defined in this document or in the existing codebase models. Need to either define it or reference the transitions design document if one exists.

**M7.** The `ChapterMetadata` model has a `url` field. Chapter URLs in MP4 are non-standard (QuickTime supports them via `AVMetadataItem` but not all players display them). Document this limitation.

**M8.** The `BrushStroke.softness` field overlaps with `MaskDefinition.feather`. Clarify whether per-stroke softness is applied before or after the global mask feathering, and whether they compound.

---

### Questions

**Q1.** How does the person segmentation mask handle video where the person moves in and out of frame? `VNGeneratePersonSegmentationRequest` produces a full-frame matte -- does the mask "follow" the person automatically, or does it need to be combined with tracking data for temporal consistency?

**Q2.** For speed ramps with `FrameBlendMode.opticalFlow`, does each speed-change segment require its own set of pre-rendered interpolated frames? What is the expected storage overhead for a 10-second speed ramp at 0.25x?

**Q3.** The multi-cam export "flattens" the multi-cam group into a single timeline track. Does this support transitions (dissolves) between angles, or only hard cuts? The `MultiCamCutPoint.transition` field suggests transitions, but the export pipeline description only mentions segment extraction.

**Q4.** For brush masks, the document mentions a 1024x1024 fixed-resolution rasterization limit. What happens for 4K exports -- is the 1024x1024 mask upscaled? This could produce visible pixelation on fine brush strokes.

**Q5.** The proxy system stores proxies alongside the project. What happens when a project is duplicated or shared? Are proxy files regenerated, or do they need to be included in the project bundle?

**Q6.** For the pan & scan feature, Option A (separate `panScanKeyframes` field) is recommended. How does this interact with the existing `VideoTransform` keyframes? If both are active simultaneously, what is the order of application -- crop first then transform, or transform first then crop?

---

### Positive Observations

1. **Excellent current state analysis (Section 2).** The document accurately identifies what exists, what is partially implemented, and what gaps need filling. Every claim was verified against the codebase.

2. **Strong edge case coverage (Section 14).** The edge case tables are comprehensive and practical. The tracking loss recovery strategy (Section 3) with graduated confidence thresholds (500ms, 2s) is well-thought-out.

3. **Realistic Phase 4 complexity assessment.** Marking multi-camera editing as "VERY HIGH" and recommending 2-angle support before N-angle generalization shows engineering maturity.

4. **Proper reuse of existing infrastructure.** The design builds on `KalmanFilter2D` for tracking smoothing, `TrackingDataStore` for path storage, `InterpolationType` for mask keyframing, and `MediaAssetRegistry` for proxy association. No unnecessary reinvention.

5. **Non-goals section is clear and appropriate.** Excluding 3D motion tracking, AI-generated content, and real-time collaborative multi-cam keeps the scope manageable.

6. **Good architectural philosophy.** "Data over behavior" with immutable Dart models and native Swift interpretation is the right pattern for a Flutter + native iOS app.

7. **Testing strategy (Section 16) is comprehensive.** Unit tests for all new models, integration tests for cross-system interactions, and XCTest for native code cover the key quality dimensions.

8. **The phased implementation plan respects dependencies.** Phase 1 features have no native dependencies beyond what exists. Phase 2 introduces the CIFilter pipeline. Phase 3 requires Vision framework extensions. Phase 4 builds on all prior phases. This ordering minimizes rework.

---

### Checklist Summary

| Check | Status | Notes |
|-------|--------|-------|
| Vision framework APIs correct | PASS with caveat | `VNTrackObjectRequest` and `VNGenerateOpticalFlowRequest` are correct; `MotionTrackingService` relationship to `TrackingService` undefined |
| Masking architecture correct | PASS with caveats | CIBlendWithMask correct but diagram semantics inverted; feather max radius needs clamping |
| Speed/time-lapse correct | FAIL | `scaleTimeRange` correct but `VideoClip.durationMicroseconds` does not account for speed -- tree augmentation will be incorrect |
| Frame interpolation realistic | PARTIAL | Optical flow detection correct; warp shader is placeholder; not realistic without Metal implementation |
| Multi-cam audio sync correct | FAIL | Uses convolution not correlation; result will be incorrect |
| Proxy system integrates | PASS with caveat | Dart-side resolution correct; Swift-side resolution code is misplaced |
| Markers extend correctly | PASS | Clean extension of existing `TimelineMarker` model |
| Integration with timeline | PASS with caveat | `_execute()` pattern correct; `VideoClip` model changes not yet specified |
| Integration with undo/redo | PASS | All mutations via `TimelineManager._execute()` |
| Integration with export | FAIL | Custom `AVVideoCompositing` not designed -- cannot export masks, speed, or multi-cam |
| Performance budgets realistic | MOSTLY | Most budgets reasonable; multi-cam memory exceeds app budget; optical flow budget tight |
| Implementation estimates realistic | MOSTLY | Phase 3 frame interpolation underestimated; Phase 2 masking underestimated due to custom compositor |
| Data models follow patterns | PASS | Immutable, `copyWith`, JSON serialization consistent with codebase |
| Backward compatibility addressed | PASS | Null-coalescing for new fields in `fromJson` |

**Review 1 Verdict: CONDITIONAL APPROVAL -- Resolve C1, C2, C3 before implementation begins. Address I1-I6 before the relevant phase.**

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Files Verified:** `lib/models/clips/video_clip.dart`, `lib/models/clips/timeline_item.dart`, `lib/models/timeline_node.dart`, `lib/models/persistent_timeline.dart`, `lib/core/timeline_manager.dart`, `ios/Runner/VideoProcessingService.swift`, `ios/Runner/Timeline/CompositionBuilder.swift`, `ios/Runner/Tracking/TrackingService.swift`, `docs/plans/2026-02-06-multi-track-compositing-design.md`, `docs/plans/2026-02-06-video-effects-system-design.md`

---

### Codebase Verification Results

#### 1. Custom Compositor (R1-C1 Resolution)

**Status: RESOLVABLE -- Must Unify With Multi-Track & Effects Compositors**

R1 flagged the missing `AVVideoCompositing` design as BLOCKING. Upon verifying the other design documents, this is actually a **cross-cutting concern shared by three design documents**:

| Design Document | Proposed Compositor | Purpose |
|----------------|--------------------|---------|
| **Multi-Track Compositing** | `MultiTrackCompositor` | PiP, split-screen, blend modes, chroma key |
| **Video Effects System** | `EffectVideoCompositor` | CIFilter chains, speed ramps |
| **Advanced Features (this doc)** | Unnamed (referenced but never specified) | Masks, speed changes, clone/stamp, multi-cam |

**The fundamental problem:** AVFoundation only allows ONE `customVideoCompositorClass` per `AVVideoComposition`. You cannot stack multiple compositor classes. These three designs each propose their own compositor in isolation. In practice, there must be a **single unified compositor** that handles all per-frame rendering: multi-track compositing, effects chains, masks, speed remapping, clone/stamp, and multi-cam switching.

**Proposed Resolution:**

A single `LiquidEditorCompositor: NSObject, AVVideoCompositing` class with a unified instruction protocol:

```swift
class LiquidEditorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    // Multi-track compositing
    let trackConfigs: [CMPersistentTrackID: TrackCompositeConfig]?
    let trackOrder: [CMPersistentTrackID]?

    // Per-track rendering
    let effectChains: [CMPersistentTrackID: EffectChainConfig]?
    let masks: [CMPersistentTrackID: [MaskConfig]]?
    let cloneStamps: [CMPersistentTrackID: [CloneStampConfig]]?
    let panScanRegions: [CMPersistentTrackID: PanScanConfig]?

    // Transform (replaces AVMutableVideoCompositionLayerInstruction)
    let transforms: [CMPersistentTrackID: (start: CGAffineTransform, end: CGAffineTransform)]?

    // Speed (time remapping handled externally via composition track,
    // but frame blending mode passed here)
    let frameBlendMode: FrameBlendMode?

    // Multi-cam
    let multiCamActiveAngle: CMPersistentTrackID?
    let multiCamTransition: TransitionConfig?
}
```

The unified compositor's `startRequest()` method processes each frame through a pipeline:

1. **Source frame retrieval** (from `request.sourceFrame(byTrackID:)`)
2. **Time remapping / frame blending** (if speed ramp + blend mode active)
3. **Transform application** (CIAffineTransform, replaces layer instruction ramps)
4. **Pan & scan crop** (CICrop + CILanczosScaleTransform)
5. **Effect chain** (CIFilter chain from video effects system)
6. **Mask application** (CIBlendWithMask for selective effects)
7. **Clone/stamp** (CIFilter chain for region duplication)
8. **Multi-track compositing** (layering with blend modes, chroma key)
9. **Multi-cam switching** (select active angle's output)
10. **Output** (render to CVPixelBuffer)

**Key migration note** (verified against codebase): The existing `VideoProcessingService.swift` uses `layerInstruction.setTransformRamp()` (lines 271, 489) and `CompositionBuilder.swift` uses `layerInstruction.setTransform(.identity, at: .zero)` (line 384). Both MUST migrate to `CIAffineTransform` inside the unified compositor when any advanced feature is active. For clips with only basic transforms and no effects/masks/speed, the standard layer instruction path can be kept as a fast path.

**This resolution must be coordinated across all three design documents.** It should be specified as a shared infrastructure document: `docs/plans/2026-02-06-unified-compositor-design.md`.

**Risk Level: HIGH.** The unified compositor is the most architecturally complex native component in the entire app. It must be implemented FIRST (pre-Phase 2) and all three design documents depend on it.

---

#### 2. Duration After Speed Change (R1-C2 Resolution)

**Status: VERIFIED BROKEN -- Proposed Fix Below**

Codebase verification confirms the problem is exactly as R1 described:

- `MediaClip.durationMicroseconds` (line 122 of `timeline_item.dart`): `sourceOutMicros - sourceInMicros`
- `TimelineNode.itemDurationMicros` (line 56 of `timeline_node.dart`): `item.durationMicroseconds`
- `TimelineNode.subtreeDurationMicros` propagates item durations up the tree

If a 10-second clip has `speedMultiplier = 2.0`, its source duration is still 10s but its timeline duration should be 5s. The tree would report 10s, breaking:
- `PersistentTimeline.totalDurationMicros` (over-reports total duration)
- `PersistentTimeline.itemAtTime()` (wrong item returned at boundary times)
- `PersistentTimeline.startTimeOf()` (wrong start times for subsequent clips)
- `TimelineManager.splitAt()` (splits at wrong position)

**Proposed Fix: Override `durationMicroseconds` in `VideoClip` (Option A)**

This is the cleanest approach because it keeps the fix localized and the tree invariant (`subtreeDuration = left.duration + self.duration + right.duration`) remains correct without tree-level changes.

```dart
@immutable
class VideoClip extends MediaClip {
  final SpeedSettings? speedSettings;
  // ... other new fields ...

  @override
  int get durationMicroseconds {
    final sourceDuration = sourceOutMicros - sourceInMicros;
    if (speedSettings == null || speedSettings!.rampKeyframes.isEmpty) {
      // Uniform speed: simple division
      return (sourceDuration / (speedSettings?.speedMultiplier ?? 1.0)).round();
    } else {
      // Speed ramp: integrate 1/speed(t) over source duration
      return speedSettings!.effectiveDurationMicros(sourceDuration);
    }
  }
}
```

**Cascade effects verified:**
- `TimelineNode.leaf(item)` computes `subtreeDurationMicros` from `item.durationMicroseconds`, so the tree auto-updates.
- `VideoClip.splitAt(offsetMicros)` uses `durationMicroseconds` for validation (line 66). After speed change, the offset is in *timeline* time, not source time. The `splitAt` method must be updated to convert timeline offset to source offset before splitting. This is a secondary issue.
- `VideoClip.toJson()` serializes `sourceInMicros` and `sourceOutMicros` (not the computed duration), so serialization is unaffected.

**Additional concern: `SpeedSettings.effectiveDurationMicros` for ramps.** The design provides this method for uniform speed only. For ramps, it requires numerical integration:

```dart
int effectiveDurationMicros(int sourceDurationMicros) {
  if (rampKeyframes.isEmpty) {
    return (sourceDurationMicros / speedMultiplier).round();
  }
  // Numerical integration of 1/speed(t) dt
  // Use trapezoidal rule with keyframe segments
  double outputDuration = 0;
  final sortedKf = List<SpeedKeyframe>.from(rampKeyframes)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  int prevTimeMicros = 0;
  double prevSpeed = sortedKf.first.speedMultiplier;

  for (final kf in sortedKf) {
    final segmentDuration = kf.timestamp.inMicroseconds - prevTimeMicros;
    final avgSpeed = (prevSpeed + kf.speedMultiplier) / 2;
    outputDuration += segmentDuration / avgSpeed;
    prevTimeMicros = kf.timestamp.inMicroseconds;
    prevSpeed = kf.speedMultiplier;
  }

  // Remaining segment after last keyframe
  final remaining = sourceDurationMicros - prevTimeMicros;
  if (remaining > 0) {
    outputDuration += remaining / prevSpeed;
  }

  return outputDuration.round();
}
```

**Action Required:** Update `SpeedSettings.effectiveDurationMicros` to handle ramps. Update `VideoClip.splitAt` to account for time remapping.

---

#### 3. Frame Interpolation Warp Shader (R1-C3 Resolution)

**Status: RESEARCH SPIKE REQUIRED -- Optical Flow Viable, Warp Shader Needs Prototype**

**Optical flow computation viability:** CONFIRMED. `VNGenerateOpticalFlowRequest` is a production API available since iOS 14. Performance on A14+ is well-documented at 30-50ms per frame pair at 1080p. The design's usage is correct.

**Warp shader viability assessment:**

The warp operation is conceptually simple: for each pixel in the output frame, sample from frame1 at `(x + flow.x * factor, y + flow.y * factor)` and from frame2 at `(x - flow.x * (1-factor), y - flow.y * (1-factor))`, then blend. This is a standard image-warping operation.

**Option A: Metal Compute Shader (Recommended)**

A Metal compute kernel for frame warping is approximately 30-50 lines of MSL code. The flow field from `VNGenerateOpticalFlowRequest` is a `CVPixelBuffer` with `kCVPixelFormatType_TwoComponent16Half` (two half-float channels). This maps directly to a Metal texture with `.rg16Float` pixel format.

```metal
kernel void warpFrames(
    texture2d<half, access::read> frame1 [[texture(0)]],
    texture2d<half, access::read> frame2 [[texture(1)]],
    texture2d<half, access::read> flowField [[texture(2)]],
    texture2d<half, access::write> output [[texture(3)]],
    constant float &factor [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    float2 uv = float2(gid) / float2(output.get_width(), output.get_height());
    half2 flow = flowField.read(gid).rg;

    // Forward warp from frame1
    float2 srcUV1 = uv + float2(flow) * factor;
    // Backward warp from frame2
    float2 srcUV2 = uv - float2(flow) * (1.0 - factor);

    // Bilinear sample (requires sampler in practice)
    half4 color1 = frame1.read(uint2(srcUV1 * float2(frame1.get_width(), frame1.get_height())));
    half4 color2 = frame2.read(uint2(srcUV2 * float2(frame2.get_width(), frame2.get_height())));

    // Blend
    half4 result = mix(color1, color2, half(factor));
    output.write(result, gid);
}
```

This is a realistic 1-2 day implementation task for the shader itself, plus 2-3 days for integration (Metal pipeline state, texture management, buffer lifecycle).

**Performance estimate:** Metal compute shaders for per-pixel image warping run at <5ms for 1080p on A14+. Combined with the 30-50ms optical flow computation, the total of 35-55ms per interpolated frame is below the 60ms budget.

**However, quality concerns remain:**
- Bidirectional flow would require TWO `VNGenerateOpticalFlowRequest` calls (frame1->frame2 and frame2->frame1), doubling the flow computation time to 60-100ms.
- Occlusion handling (areas visible in one frame but not the other) requires additional logic in the shader.
- Edge artifacts near frame boundaries need clamping.

**Recommendation:** Add a **2-week research spike** before Phase 3 that validates:
1. Metal shader produces acceptable visual quality on test footage
2. Unidirectional flow is sufficient or bidirectional is needed
3. Quality vs. frame blending difference justifies the 30x performance cost

If the spike fails, fall back to `CIDissolveTransition` (frame blending) as the "optical flow" tier and document the limitation. The `FrameBlendMode.opticalFlow` enum value remains valid but maps to best-available algorithm.

---

#### 4. Audio Sync Cross-Correlation (R1-I1 Resolution)

**Status: vDSP_conv Usage Is Incorrect -- FFT Approach Required**

R1 correctly identified that `vDSP_conv` computes convolution, not cross-correlation. Verified: Apple's documentation for `vDSP_conv` states it computes the convolution of two vectors.

For cross-correlation, the Accelerate framework approach is:

**Option A: Reverse + Convolve (Simple)**
```swift
// Reverse targetAudio, then convolve
var reversedTarget = [Float](repeating: 0, count: targetAudio.count)
vDSP_vrvrs(targetAudio, 1, &reversedTarget, 1, vDSP_Length(targetAudio.count))
vDSP_conv(referenceAudio, 1, reversedTarget, 1, &result, 1, ...)
```
This works but is still O(n*m), which is slow for long audio (480K samples = ~230 billion operations).

**Option B: FFT-Based Cross-Correlation (Recommended)**
```swift
func crossCorrelateFFT(reference: [Float], target: [Float], sampleRate: Double) -> Int {
    let n = reference.count + target.count - 1
    let fftLength = vDSP_Length(1 << Int(ceil(log2(Double(n))))) // Next power of 2

    // Create FFT setup
    let log2n = vDSP_Length(log2(Double(fftLength)))
    guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0 }
    defer { vDSP_destroy_fftsetup(fftSetup) }

    // Zero-pad and FFT both signals
    var refFFT = fft(reference, length: Int(fftLength), setup: fftSetup, log2n: log2n)
    var tarFFT = fft(target, length: Int(fftLength), setup: fftSetup, log2n: log2n)

    // Conjugate multiply: refFFT * conj(tarFFT)
    // This gives the cross-power spectrum
    var crossPower = conjugateMultiply(refFFT, tarFFT)

    // Inverse FFT
    var correlation = ifft(crossPower, setup: fftSetup, log2n: log2n)

    // Find peak
    var maxVal: Float = 0
    var maxIdx: vDSP_Length = 0
    vDSP_maxvi(correlation, 1, &maxVal, &maxIdx, vDSP_Length(correlation.count))

    // Convert to time offset
    let sampleOffset = Int(maxIdx)
    if sampleOffset > correlation.count / 2 {
        return Int(Double(sampleOffset - correlation.count) / sampleRate * 1_000_000)
    }
    return Int(Double(sampleOffset) / sampleRate * 1_000_000)
}
```

**Performance:** FFT-based cross-correlation is O(n log n). For 480K samples (60s at 8kHz), this is approximately 480K * 19 = ~9M operations, completing in <10ms on modern hardware via the Accelerate framework. This is a 23x speedup over the O(n^2) convolution approach.

**Additional recommendations for audio sync:**
1. **RMS normalize** both signals before correlation to handle volume differences between cameras.
2. **Use a 10-second excerpt** from the middle of each clip (where audio is most likely to have distinctive events) rather than the full duration. This reduces FFT size and improves robustness.
3. **Sub-sample accuracy:** After finding the peak bin, use parabolic interpolation on the 3 bins around the peak for sub-sample offset precision.

---

#### 5. Integration with Other Feature Systems

**Status: THREE CRITICAL CROSS-SYSTEM DEPENDENCIES IDENTIFIED**

##### 5.1 Unified Compositor Dependency (BLOCKING)

As detailed in Section 1 above, the Advanced Features system shares a compositor with Multi-Track Compositing and Video Effects. The render pipeline order must be unambiguous. Verified pipeline order from the three designs:

```
Per-Track Render Pipeline (inside unified compositor):

1. Source Frame (from AVAsynchronousVideoCompositionRequest)
2. Speed / Time Remap (frame selection + optional frame blending)
3. VideoTransform (scale, translate, rotate via CIAffineTransform)
4. Pan & Scan (CICrop + CILanczosScaleTransform)
5. Effect Chain (CIFilter chain from Video Effects System)
6. Mask Application (CIBlendWithMask -- effect applied within mask)
7. Clone/Stamp (CISourceOverCompositing with mask)
8. Color Grading (from Color Grading & Filters System)

Multi-Track Composition Stage:
9. Per-track opacity
10. Chroma key (per-track)
11. Blend mode compositing (bottom-to-top)
12. Multi-cam angle selection

Output:
13. Render to CVPixelBuffer
```

**Key ordering constraint:** Masks MUST come AFTER the effect chain. The mask determines WHERE the effect is applied. If mask came before effects, the effect would be applied to the mask region, not masked from the full-frame effect. The design document's pipeline (Section 13) shows this order correctly, but it must be enforced in the unified compositor.

##### 5.2 VideoClip Model Expansion Scope

The `VideoClip` class currently has 6 fields (id, mediaAssetId, sourceInMicros, sourceOutMicros, keyframes, name). The Advanced Features design proposes adding 6 more (speedSettings, masks, panScanKeyframes, trackingPathId, multiCamGroupId, cloneStamps). The Video Effects design proposes adding `effectChain`. The Multi-Track design proposes adding `trackConfig`.

**Total new fields: 8.** This significantly increases the surface area of `VideoClip`. Every mutation method (`addKeyframe`, `removeKeyframe`, `updateKeyframe`, `clearKeyframes`, `trimStart`, `trimEnd`, `splitAt`, `copyWith`, `duplicate`) must propagate all new fields. Verified: the current `addKeyframe` method (line 185) constructs a new `VideoClip` with all 6 fields explicitly. Adding 8 more fields means all 9 mutation methods must be updated.

**Risk:** High likelihood of bugs where a mutation method forgets to carry forward one of the new fields, silently dropping masks or speed settings on clip operations.

**Mitigation:** The `copyWith` method (line 228) should be used by ALL mutation methods instead of direct constructor calls. Currently, `addKeyframe` does NOT use `copyWith` -- it constructs a `VideoClip` directly. After field expansion, this pattern must be refactored:

```dart
// CURRENT (fragile, doesn't forward new fields):
VideoClip addKeyframe(Keyframe keyframe) => VideoClip(
  id: id,
  mediaAssetId: mediaAssetId,
  sourceInMicros: sourceInMicros,
  sourceOutMicros: sourceOutMicros,
  keyframes: [...keyframes, keyframe],
  name: name,
);

// REQUIRED (forward-compatible):
VideoClip addKeyframe(Keyframe keyframe) => copyWith(
  keyframes: [...keyframes, keyframe],
);
```

ALL existing mutation methods (addKeyframe, removeKeyframe, updateKeyframe, clearKeyframes, trimStart, trimEnd, splitAt, duplicate) must be refactored to use `copyWith` before adding new fields. This is a prerequisite task.

##### 5.3 MethodChannel Proliferation

The existing codebase has these channels:
- `com.liquideditor/tracking` (TrackingService)
- `com.liquideditor/tracking/progress` (EventChannel)
- `com.liquideditor/video` (VideoProcessingService via AppDelegate)

The Advanced Features design proposes 4 new channels:
- `com.liquideditor/motion_tracking`
- `com.liquideditor/frame_interpolation`
- `com.liquideditor/proxy`
- `com.liquideditor/audio_analysis`

The Multi-Track and Effects designs likely add more. With 7+ channels, the AppDelegate's method channel registration becomes unwieldy.

**Recommendation:** Consolidate related channels. Motion tracking should extend the existing `com.liquideditor/tracking` channel (add new methods to `TrackingService`) rather than creating a parallel `com.liquideditor/motion_tracking` channel. This aligns with the design's own principle of "extend, do not replace."

---

#### 6. Performance Budgets -- Mobile GPU Reality Check

**Status: MOSTLY REALISTIC, TWO CONCERNS**

##### 6.1 CIFilter Chain Accumulation

The performance budgets list individual feature costs. But in practice, features stack:

| Scenario | Features Active | Individual Totals | Realistic Total |
|----------|----------------|-------------------|-----------------|
| Basic edit | Transform only | < 1ms | < 1ms |
| Masked effect | Transform + Effect + Mask | 1 + 3 + 3 = 7ms | ~10ms (pipeline overhead) |
| Full creative | Transform + PanScan + Effect + Mask + CloneStamp | 1 + 2 + 3 + 3 + 4 = 13ms | ~18ms (GPU stalls) |
| Multi-cam + effects | 4x decode + Transform + Effect + Mask | 8 + 1 + 3 + 3 = 15ms | ~22ms |

At 60fps, the budget per frame is 16.67ms. The "full creative" scenario exceeds this on any single track. With multi-track compositing (2+ tracks), the per-track budget halves.

**Mitigation strategies (should be documented in design):**
1. **Adaptive quality:** Detect when frame rendering exceeds 14ms and automatically downscale preview to 720p or 540p.
2. **Effect chain caching:** If effect parameters haven't changed between frames, reuse the previous frame's CIFilter output. Only re-render on parameter keyframe changes.
3. **Mask rasterization caching:** Static masks (no keyframes) only need to be rasterized once. Cache the mask texture and reuse across frames.
4. **Feature priority shedding:** If GPU is overloaded, shed features in this order: clone/stamp > mask feathering > effect quality > pan/scan.

##### 6.2 Multi-Cam Memory Budget

R1 flagged that multi-cam's ~200MB for 4 decoder buffers equals the entire app memory budget. Verified: CLAUDE.md states "Memory: < 200MB for typical use (excluding frame cache)."

**Proposed resolution:** Multi-cam editing enters a "multi-cam mode" that:
1. Suspends the frame cache (freeing its ~300MB allocation)
2. Reduces decoder resolution to 480p for inactive angles (4 * ~25MB = ~100MB)
3. Decodes only the active angle at full resolution (~50MB)
4. Total: ~150MB, within budget

When exiting multi-cam mode, angles are "flattened" to a single track and normal memory patterns resume.

---

#### 7. Phasing -- Independence Assessment

| Feature | Can Build Independently? | Hard Dependencies |
|---------|------------------------|--------------------|
| **Markers & Chapters** | YES | None -- extends existing model |
| **Pan & Scan** | YES (preview) / NO (export) | Export requires unified compositor |
| **Time-Lapse (uniform speed)** | YES | `scaleTimeRange` only -- no compositor needed |
| **Shape Masks** | NO | Requires unified compositor |
| **Slow Motion (frame blend)** | PARTIAL | Uniform speed: `scaleTimeRange`. Blend mode: requires compositor |
| **Proxy Editing** | YES | Self-contained path resolution |
| **Clone/Stamp** | NO | Requires unified compositor |
| **Motion Tracking** | YES (analysis) / NO (overlay attachment) | Analysis: standalone. Overlay: requires compositor for export |
| **Brush Masks** | NO | Requires compositor (same as shape masks) |
| **Frame Interpolation** | YES (computation) / NO (integration) | Optical flow: standalone. Frame output: requires compositor |
| **Multi-Camera** | NO | Audio sync, compositor, multi-view rendering |
| **Speed Ramps** | NO | Requires compositor for per-frame time remapping |
| **Beat Detection** | YES | Audio analysis only, outputs markers |

**Revised phasing recommendation:**

**Phase 0 (Pre-requisite, 3-4 weeks):**
- Unified compositor design + implementation
- `VideoClip` field expansion + `copyWith` refactoring
- This unblocks all subsequent phases

**Phase 1 (Foundation, 2-3 weeks):**
- Markers & Chapters (fully independent)
- Pan & Scan (models + UI; export support auto-enabled by Phase 0 compositor)
- Time-Lapse / Uniform Speed (via `scaleTimeRange`, no compositor needed)
- Proxy Editing (fully independent)

**Phase 2 (Core Advanced, 4-6 weeks):**
- Shape Masks (now enabled by Phase 0 compositor)
- Slow Motion with frame blending
- Clone/Stamp
- Speed Ramps

**Phase 3 (High Complexity, 6-8 weeks):**
- Motion Tracking (analysis + overlay attachment)
- Brush Masks
- Frame Interpolation (research spike first, 2 weeks)

**Phase 4 (Professional, 8-10 weeks):**
- Multi-Camera Editing
- Beat Detection

This adds 3-4 weeks for Phase 0 but de-risks all subsequent phases by ensuring the compositor foundation exists.

---

### Critical Findings

**C4. Unified Compositor Is a Cross-Cutting Architectural Decision (Severity: BLOCKING)**

Three design documents (Advanced Features, Multi-Track Compositing, Video Effects) each propose their own `AVVideoCompositing` implementation. AVFoundation only allows one compositor per composition. A unified compositor must be designed as shared infrastructure before any feature requiring per-frame custom rendering can be implemented.

**Action Required:** Create `docs/plans/2026-02-06-unified-compositor-design.md` specifying:
- The unified `LiquidEditorCompositor` class
- The unified `LiquidEditorInstruction` protocol conformance
- Per-frame render pipeline order
- Thread safety model (compositor callbacks come on arbitrary threads)
- Migration plan for existing `VideoProcessingService.renderComposition()` transform logic
- Migration plan for existing `CompositionBuilder.buildVideoComposition()` identity transform
- Fast path: when no advanced features are active, fall back to standard layer instructions

**C5. VideoClip Mutation Methods Do Not Use copyWith (Severity: HIGH)**

All 9 mutation methods on `VideoClip` (addKeyframe, removeKeyframe, updateKeyframe, clearKeyframes, trimStart, trimEnd, splitAt, copyWith itself, duplicate) construct new `VideoClip` instances with explicit field lists. When 8 new fields are added, every method must be manually updated. Failure to carry forward a field silently drops that feature data.

**Action Required:** Refactor all `VideoClip` mutation methods to delegate through `copyWith` BEFORE adding any new fields. This is a prerequisite task for Phase 1.

---

### Important Findings

**I7. TrackingService Architecture Conflict (Severity: MEDIUM)**

The existing `TrackingService.swift` is a substantial, well-architected service (~1500 lines) that:
- Manages sessions via `SessionStore` (actor-based concurrency)
- Uses `TrackingAlgorithm` protocol with registered trackers
- Currently only registers `BoundingBoxTracker` (person-specific)
- Has post-processing pipeline (smoothing, merge, noise filter, gap fill, re-ID)
- Provides progress via EventChannel

The design proposes `MotionTrackingService` as a separate service. This creates architectural duplication:
- Two session management systems
- Two progress reporting channels
- Two method channel handlers

**Recommended approach:** Add a `GenericObjectTracker` conforming to `TrackingAlgorithm` protocol:

```swift
class GenericObjectTracker: TrackingAlgorithm {
    let algorithmType = "objectTracking"
    let displayName = "Object Tracking"
    let supportsMultiplePeople = false // tracks single object

    private var sequenceHandler: VNSequenceRequestHandler?
    private var lastObservation: VNDetectedObjectObservation?

    func analyze(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation,
                 previousResults: [PersonTrackingResult]?) async throws -> [PersonTrackingResult] {
        // Use VNTrackObjectRequest with sequenceHandler
    }
}
```

Register it alongside `BoundingBoxTracker`:
```swift
private func registerTrackers() {
    trackers["boundingBox"] = BoundingBoxTracker()
    trackers["objectTracking"] = GenericObjectTracker()
}
```

This reuses the existing session management, progress reporting, and data store. The `TrackingService` would need a new method (`startObjectTracking`) that initializes the tracking region, but the core pipeline remains shared.

**I8. splitAt and trimStart/trimEnd Need Speed-Awareness (Severity: MEDIUM)**

When `VideoClip.durationMicroseconds` accounts for speed, `splitAt(offsetMicros)` receives a timeline-time offset but converts it to source time via `sourceInMicros + offsetMicros` (line 70 of video_clip.dart). With speed != 1.0, this conversion is incorrect:

```dart
// CURRENT (assumes speed = 1.0):
final splitSourceTime = sourceInMicros + offsetMicros;

// CORRECT (with speed):
final splitSourceTime = sourceInMicros +
    (offsetMicros * (speedSettings?.speedMultiplier ?? 1.0)).round();
```

Similarly, `trimStart` and `trimEnd` operate on source microseconds but the timeline offset mapping (`timelineToSource` on `MediaClip`) does not account for speed.

**Action Required:** Add speed-aware time mapping methods and update split/trim operations.

**I9. PanScanKeyframe Type Is Referenced But Never Defined (Severity: LOW-MEDIUM)**

The design references `List<PanScanKeyframe>` on `VideoClip` (Section 12, line 1276) but only defines `PanScanRegion`. The keyframe wrapper needs specification:

```dart
@immutable
class PanScanKeyframe {
    final Duration timestamp;
    final PanScanRegion region;
    final InterpolationType interpolation;
}
```

R1 flagged this as M4. Confirming it requires resolution before Phase 1 implementation.

**I10. Multi-Cam Audio Sync Should Use Accelerate vDSP FFT Functions (Severity: MEDIUM)**

Per the analysis in Section 4 above, FFT-based cross-correlation is 23x faster than `vDSP_conv`. For the Accelerate framework, use:
- `vDSP_create_fftsetup` / `vDSP_fft_zrip` for real-to-complex FFT
- `vDSP_zvmul` for complex conjugate multiplication
- `vDSP_fft_zrip` (inverse) for the final correlation signal

Additionally, add RMS normalization before correlation and use 10-second excerpts rather than full audio.

---

### Action Items for Review 3

| ID | Action | Blocking? | Assigned To |
|----|--------|-----------|-------------|
| R2-A1 | Create unified compositor design document | YES | Design phase |
| R2-A2 | Refactor `VideoClip` mutation methods to use `copyWith` | YES (pre-Phase 1) | Implementation |
| R2-A3 | Override `VideoClip.durationMicroseconds` for speed | YES (pre-Phase 1) | Implementation |
| R2-A4 | Implement `SpeedSettings.effectiveDurationMicros` for ramps | No (Phase 4) | Implementation |
| R2-A5 | Add speed-aware `splitAt`/`trimStart`/`trimEnd` | YES (pre-Phase 2) | Implementation |
| R2-A6 | Define `PanScanKeyframe` type | No (Phase 1) | Design |
| R2-A7 | Replace `vDSP_conv` with FFT cross-correlation | No (Phase 4) | Implementation |
| R2-A8 | Add `GenericObjectTracker` to `TrackingService` | No (Phase 3) | Implementation |
| R2-A9 | Schedule frame interpolation research spike (2 weeks) | No (pre-Phase 3) | Research |
| R2-A10 | Add adaptive quality / feature shedding for GPU overload | No (Phase 2+) | Implementation |
| R2-A11 | Define multi-cam memory mode (suspend frame cache) | No (Phase 4) | Design |
| R2-A12 | Consolidate `com.liquideditor/motion_tracking` into existing tracking channel | No (Phase 3) | Design |

### Review 2 Verdict

**CONDITIONAL APPROVAL** -- The design is architecturally sound but cannot proceed to implementation until:

1. **C4 (Unified Compositor)** is resolved with a shared infrastructure design. This is the single most important pre-requisite and affects three design documents simultaneously.
2. **C5 (VideoClip copyWith refactoring)** is completed as a code change before any new fields are added.
3. **R1-C2 (Duration override)** is implemented per the proposed fix above.

Once these three blockers are resolved, the revised phasing (Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4) provides a viable implementation path with clear independence boundaries.

**Review 3 should focus on:** The unified compositor design document (once created), the concrete Metal shader prototype results, and the refactored `VideoClip` mutation methods.

---

## Review 3: Final Implementation Readiness Sign-off

**Reviewer:** Claude (Auto-Review Round 3 - Opus 4.6)
**Date:** 2026-02-06
**Verdict:** CONDITIONAL GO

### R1/R2 Issue Resolution Status

| Issue ID | Description | Mitigation Plan? | Status |
|----------|-------------|-------------------|--------|
| **R1-C1** | Missing custom `AVVideoCompositing` design | YES -- R2 provides detailed `LiquidEditorCompositor` + `LiquidEditorInstruction` specification, 10-step render pipeline, and identifies the cross-cutting dependency with Multi-Track and Video Effects designs | **Resolved in principle; implementation document not yet created** |
| **R1-C2** | `VideoClip.durationMicroseconds` incorrect after speed change | YES -- R2 provides concrete fix (override in `VideoClip` with `effectiveDurationMicros`), verifies cascade effects on tree augmentation, and identifies secondary issues in `splitAt`/`trimStart`/`trimEnd` | **Resolved with concrete code** |
| **R1-C3** | Frame interpolation warp shader is placeholder | YES -- R2 provides a realistic 30-line Metal compute shader specification, estimates 1-2 day implementation + 2-3 day integration, and recommends a 2-week research spike pre-Phase 3 | **Resolved with acceptable risk (research spike acknowledges uncertainty)** |
| **R1-I1** | `vDSP_conv` computes convolution, not correlation | YES -- R2 provides FFT-based cross-correlation implementation using Accelerate framework, estimates 23x speedup, and adds RMS normalization + excerpt recommendations | **Resolved with concrete code** |
| **R1-I2** | CIBlendWithMask semantics inverted in diagram | Acknowledged in R1; not yet corrected in design document body | **Open -- low severity, cosmetic** |
| **R1-I3** | ProxyManager path resolution is Dart-side, not Swift-side | YES -- R2 confirms resolution must happen in Dart before method channel serialization | **Resolved** |
| **R1-I4** | MotionTrackingService relationship to existing TrackingService | YES -- R2 proposes `GenericObjectTracker` conforming to existing `TrackingAlgorithm` protocol, registered alongside `BoundingBoxTracker` | **Resolved with concrete architecture** |
| **R1-I5** | MarkerNavigator relationship to MarkerController | Not explicitly resolved by R2 but low severity | **Open -- low severity** |
| **R1-I6** | Memory budget exceeded by multi-cam | YES -- R2 proposes "multi-cam mode" suspending frame cache, 480p for inactive angles, total ~150MB within budget | **Resolved** |
| **R2-C4** | Unified compositor is cross-cutting architectural decision | Identified as BLOCKING; requires `unified-compositor-design.md` | **Not yet created -- remains blocking** |
| **R2-C5** | VideoClip mutation methods do not use copyWith | Identified as prerequisite before adding new fields | **Not yet implemented -- remains blocking** |
| **R2-I7** | TrackingService architecture conflict | Resolved by `GenericObjectTracker` approach | **Resolved** |
| **R2-I8** | splitAt/trimStart/trimEnd need speed-awareness | Concrete fix provided (multiply offset by speed multiplier) | **Resolved with concrete code** |
| **R2-I9** | PanScanKeyframe type referenced but never defined | Concrete definition provided | **Resolved** |
| **R2-I10** | Multi-cam audio sync should use FFT | Concrete implementation provided | **Resolved** |

**Summary:** Of 16 issues across R1 and R2, 12 have concrete mitigation plans or resolutions. 2 remain open but are low severity (I2, I5). 2 remain BLOCKING (C4 unified compositor document, C5 VideoClip refactoring). The blocking items are pre-implementation tasks, not design deficiencies.

---

### Codebase Verification

I verified the following source files against the design and R1/R2 claims:

#### 1. `lib/models/clips/timeline_item.dart` -- V2 Type Hierarchy

**Verified correct.** The three-tier hierarchy (`TimelineItem` -> `MediaClip`/`GeneratorClip` -> concrete types) is clean and extensible. The `MediaClip.durationMicroseconds` getter (line 122: `sourceOutMicros - sourceInMicros`) confirms R1-C2: speed changes will NOT be reflected in the computed duration without an explicit override in `VideoClip`. The forward-compatibility strategy (line 59-85, unknown types fall back to `GapClip`) is sound and will work for new advanced feature types.

#### 2. `lib/models/persistent_timeline.dart` -- Tree Data Structure

**Verified correct.** The `PersistentTimeline` is a well-implemented immutable AVL order statistic tree. Key findings:
- `itemAtTime()` (line 68) traverses using `node.leftDuration` and `node.itemDurationMicros`, confirming that incorrect item durations from speed changes would propagate wrong lookup results.
- `updateItem()` (line 314) correctly uses `identical()` checks for structural sharing.
- The `Expando`-based lazy ID index (line 24) is a clever optimization that avoids breaking immutability.
- The tree correctly recomputes `subtreeDurationMicros` in `withItem()` (line 113 of `timeline_node.dart`), so once `VideoClip` overrides `durationMicroseconds`, the tree will auto-correct.

**No design-level risk.** The tree architecture fully supports the proposed speed/mask/pan-scan extensions without structural changes.

#### 3. `lib/core/timeline_manager.dart` -- Mutation/Undo System

**Verified correct.** The `_execute()` pattern (line 119-138) is the single mutation entry point: push to undo stack, clear redo, apply mutation, set dirty flag, notify listeners. All proposed new methods (`setClipSpeed`, `addMask`, `updateMask`, `removeMask`, `setPanScanKeyframes`, `addCloneStamp`, `removeCloneStamp`) can follow the same pattern as `addKeyframe` (line 288-296), which gets the clip, creates a modified copy, and calls `_current.updateItem()`.

**Concern confirmed:** The `addKeyframe` method (line 289) casts to `VideoClip` but the cast result is only used for the `addKeyframe` call. This pattern is correct but all new methods must perform the same cast-and-validate pattern.

#### 4. `ios/Runner/VideoProcessingService.swift` -- Native Video Processing

**Verified correct.** The service is well-structured with clear separation of concerns (thumbnail generation, proxy generation, rendering, composition export). Key observations:
- `generateProxy` (line 116) uses `AVAssetExportPreset1920x1080` -- the design correctly identifies this needs extension to configurable resolutions.
- `renderComposition` (line 335) uses `AVMutableVideoCompositionLayerInstruction` with `setTransformRamp` (line 489). This MUST be migrated to the unified compositor for advanced features as R2 correctly identifies.
- The service uses `DispatchQueue.global(qos: .userInitiated)` consistently for background work, which aligns with performance requirements.
- The `EventSinkProvider` protocol (line 909) is a clean pattern for progress reporting from native to Flutter.

**No surprises.** The existing code is a solid foundation that can be extended for new features.

#### 5. `lib/models/keyframe.dart` -- Keyframe Architecture

**Verified correct.** The `Keyframe` model (line 282) with `VideoTransform`, 21 `InterpolationType` values, and `BezierControlPoints` is comprehensive. The `KeyframeTimeline` class (line 399) with binary search `surroundingKeyframes` method provides the interpolation infrastructure that mask keyframes, pan-scan keyframes, and speed keyframes will reuse.

**Compatibility note:** The `KeyframeTimeline` is internally mutable (line 396: "maintains internal mutability for performance") with `_modificationHash` for cache invalidation. New keyframe types (mask, pan-scan) should NOT reuse this class directly -- they should use the immutable pattern already proposed in the design (keyframe lists stored directly on the clip model). This avoids mixing mutable `KeyframeTimeline` with the immutable `PersistentTimeline` architecture.

#### 6. `ios/Runner/Timeline/CompositionBuilder.swift` -- Composition Building

**Verified correct.** The builder (line 72-419) handles video, audio, image, gap, color, silence, and offline segment types. Key observations:
- `buildVideoComposition` (line 366) applies identity transforms only (line 384: `layerInstruction.setTransform(.identity, at: .zero)`). R1 and R2 correctly identify this as the point where the unified compositor integration must happen.
- Thread-safe asset caching via `NSLock` (line 87, 395).
- The `CompositionSegment` struct (line 28) has no fields for masks, speed, pan-scan, or clone-stamp. These will flow through the unified compositor's instruction protocol, not through segment data.
- `BuiltComposition` result struct (line 56) includes `videoComposition` which will carry the custom compositor class reference.

**Risk confirmed:** The builder currently returns `AVMutableVideoComposition` with standard instructions. Switching to custom compositor instructions is a non-trivial refactoring. However, the builder's architecture (separate build phases for video, audio, instruction) is well-suited for this extension.

#### 7. `lib/models/clips/video_clip.dart` -- Current Implementation

**Verified: R2-C5 is NOT yet resolved.** All 9 mutation methods (`addKeyframe` line 185, `removeKeyframe` line 195, `updateKeyframe` line 205, `clearKeyframes` line 216, `splitAt` line 61, `trimStart` line 117, `trimEnd` line 156, `copyWith` line 228, `duplicate` line 247) construct `VideoClip` instances with explicit field lists. None delegate through `copyWith`. Adding 8 new fields without refactoring first will require updating all 9 methods, with high risk of dropped fields.

---

### Implementation Readiness Assessment

#### Phasing Assessment

The R2-revised phasing (Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4) is realistic and correctly ordered:

| Phase | Estimated Duration | Assessment | Risk |
|-------|-------------------|------------|------|
| **Phase 0** (Unified compositor + VideoClip refactoring) | 3-4 weeks | **Correctly identified as prerequisite.** This is the highest-risk, lowest-glamour work. It must be completed before any compositor-dependent feature. Estimate is reasonable for the compositor design + implementation + VideoClip refactoring. | HIGH -- compositor is architecturally complex |
| **Phase 1** (Markers, Pan & Scan, Time-Lapse, Proxy) | 2-3 weeks | **Realistic.** All four features can be built independently. Markers and proxy are fully self-contained. Pan & scan models + UI can be built with export deferred to compositor. Time-lapse via `scaleTimeRange` needs no compositor. | LOW |
| **Phase 2** (Shape Masks, Slow Motion, Clone/Stamp, Speed Ramps) | 4-6 weeks | **Slightly underestimated.** Shape masks require the CIFilter rendering pipeline and mask UI (drawing gestures). Clone/stamp similarly needs a CIFilter chain + UI. The combination of 4 features with UI work in 4-6 weeks is tight. Recommend 5-7 weeks. | MEDIUM |
| **Phase 3** (Motion Tracking, Brush Masks, Frame Interpolation) | 6-8 weeks + 2-week spike | **Realistic with the research spike.** Motion tracking is well-scoped with the `GenericObjectTracker` approach. Brush masks build on Phase 2 mask infrastructure. Frame interpolation depends on Metal shader validation. | MEDIUM-HIGH (shader uncertainty) |
| **Phase 4** (Multi-Camera, Beat Detection) | 8-10 weeks | **Realistic.** Multi-camera is the most complex feature in the entire design. The 8-10 week estimate for audio sync + multi-view rendering + composition flattening is appropriate. Beat detection is an independent add-on. | HIGH (multi-cam complexity) |

**Total estimated: 21-31 weeks (5-8 months).** Adding 30-50% buffer for a single-developer scenario gives 7-12 months. This is a substantial but not unreasonable roadmap.

#### Effort Estimates

| Item | Estimated | Assessed | Notes |
|------|-----------|----------|-------|
| Unified compositor design doc | 1 week | 1-2 weeks | Must coordinate with multi-track and effects designs; thread safety is non-trivial |
| Unified compositor implementation | 2-3 weeks | 2-4 weeks | `AVVideoCompositing` protocol is notoriously finicky with thread safety and pixel buffer management |
| VideoClip copyWith refactoring | 2-3 days | 1-2 days | Mechanical refactoring; existing tests should catch regressions |
| VideoClip duration override for speed | 1-2 days | 1-2 days | Straightforward with cascade verification |
| Speed-aware split/trim | 2-3 days | 2-3 days | Requires careful time mapping logic and test coverage |
| Metal warp shader prototype | 2 weeks (spike) | 2-3 weeks (spike) | Quality evaluation and occlusion handling may extend timeline |

#### Dependency Analysis

The design correctly identifies these hard dependencies:

1. **Unified compositor** blocks: Shape masks, brush masks, clone/stamp, speed ramps, multi-cam export, effect-masked rendering.
2. **Phase 1 completion** blocks: Phase 2 slow motion (needs SpeedSettings from time-lapse work).
3. **Phase 2 mask infrastructure** blocks: Phase 3 brush masks.
4. **Research spike** blocks: Phase 3 frame interpolation commitment.
5. **Phase 2-3 completion** blocks: Phase 4 multi-camera (which depends on compositor, tracking, and potentially speed ramps for angle-level speed adjustment).

No circular dependencies detected. The DAG is well-formed.

#### Showstopper Risk Assessment

| Risk | Probability | Impact | Showstopper? |
|------|------------|--------|-------------|
| Unified compositor thread safety issues causing crashes | Medium | High | **Potentially.** `AVVideoCompositing` callbacks come on arbitrary threads. Incorrect synchronization could cause race conditions that only manifest under load. Mitigation: extensive XCTest coverage with concurrent frame requests. |
| Metal warp shader produces unacceptable visual quality | Low-Medium | Medium | **No.** Frame blending fallback exists. Feature degrades gracefully. |
| Multi-cam 4-angle decoding hits iOS hardware decoder limit | Low | High | **No.** R2 mitigation (480p inactive angles) is viable. Can fall back to 2-angle mode. |
| VideoClip field expansion breaks existing serialization | Low | High | **No.** Null-coalescing in `fromJson` ensures backward compatibility. Verified this pattern works by examining existing `keyframes` deserialization (line 275-278 of video_clip.dart). |
| CIFilter chain performance exceeds frame budget with stacked features | Medium | Medium | **No.** R2 adaptive quality and feature shedding strategies are viable. Preview can drop to 720p. |
| Optical flow computation (VNGenerateOpticalFlowRequest) unavailable or degraded on certain devices | Very Low | Medium | **No.** API is available on all devices with iOS 14+ (project minimum is iOS 18). Neural Engine acceleration varies by chip but graceful fallback exists. |

**No showstopper risks identified.** All high-impact risks have concrete mitigation strategies documented in R2.

---

### Mandatory Conditions (CONDITIONAL GO)

The following conditions MUST be met before or during implementation:

1. **Create `docs/plans/2026-02-06-unified-compositor-design.md` BEFORE Phase 0 implementation begins.** This document must specify: (a) the `LiquidEditorCompositor` class with `AVVideoCompositing` protocol conformance, (b) the `LiquidEditorInstruction` with `AVVideoCompositionInstructionProtocol` conformance, (c) the 10-step per-frame render pipeline from R2, (d) thread safety model with explicit lock/queue strategy, (e) fast-path fallback for clips with no advanced features, and (f) migration plan for existing `VideoProcessingService.renderComposition()` and `CompositionBuilder.buildVideoComposition()`.

2. **Refactor all `VideoClip` mutation methods to use `copyWith` BEFORE adding any new fields.** Specifically: `addKeyframe`, `removeKeyframe`, `updateKeyframe`, `clearKeyframes`, `splitAt`, `trimStart`, `trimEnd`, and `duplicate` must all delegate through `copyWith` instead of constructing `VideoClip` instances directly. This is a prerequisite for Phase 1 and must be verified by ensuring no `VideoClip(` constructor calls exist in mutation methods (only in `copyWith` itself, `fromJson`, and test setup).

3. **Override `VideoClip.durationMicroseconds` to account for speed BEFORE any speed-related feature is implemented.** The tree augmentation invariant (`subtreeDuration = left + self + right`) depends on correct `durationMicroseconds` values. A speed-changed clip with incorrect duration breaks `itemAtTime()`, `startTimeOf()`, and `totalDurationMicros`. This must be implemented and tested with the persistent timeline before Phase 1 time-lapse work begins.

4. **Conduct the 2-week frame interpolation research spike BEFORE committing to Phase 3 scope.** The spike must produce: (a) a working Metal compute shader for flow-based frame warping, (b) visual quality comparison with frame blending on 3+ test clips, (c) measured performance on A14 and A17 Pro devices. If the spike fails to produce acceptable quality, Phase 3 scope should be reduced to frame blending only, and the `FrameBlendMode.opticalFlow` enum value should map to best-effort frame blending.

5. **Correct the CIBlendWithMask pipeline diagram (R1-I2) in the design document.** While cosmetic, an incorrect diagram risks incorrect implementation. Input should be the effected frame, Background should be the original frame, and Mask determines where the effect shows through.

6. **Add adaptive quality / feature priority shedding strategy to the design document.** R2 identified that stacked features can exceed the 16.67ms per-frame budget. The design must document: (a) adaptive preview downscaling when frame rendering exceeds 14ms, (b) feature shedding priority order, and (c) mask/effect caching strategy for static parameters.

---

### Final Recommendation

This Advanced Features design document is a comprehensive, well-structured plan covering 10 professional-grade features. The original design demonstrated strong architectural thinking with appropriate use of Apple's native frameworks, proper immutable data model patterns, and realistic phasing. Reviews 1 and 2 identified critical issues -- most notably the missing unified compositor design (R1-C1/R2-C4), the broken duration calculation for speed-changed clips (R1-C2), and the fragile VideoClip mutation pattern (R2-C5) -- all of which now have concrete, verified resolution paths.

The codebase verification confirms that the existing infrastructure (`PersistentTimeline`, `TimelineManager`, `VideoProcessingService`, `CompositionBuilder`, `Keyframe` system) is architecturally sound and ready to support the proposed extensions. The tree data structure will correctly propagate speed-aware durations once the `VideoClip` override is in place. The native composition pipeline has clear extension points for the unified compositor. The tracking infrastructure can absorb generic object tracking via the existing `TrackingAlgorithm` protocol.

The verdict is **CONDITIONAL GO** rather than unconditional GO because two blocking prerequisites (unified compositor design document and VideoClip refactoring) require concrete deliverables before Phase 0 implementation can begin. These are well-scoped tasks with clear acceptance criteria, not open-ended research questions. Once completed, the revised 5-phase implementation plan (Phase 0 through Phase 4) provides a viable, dependency-respecting path to full implementation over approximately 6-10 months.

**Proceed with implementation after satisfying the 6 mandatory conditions listed above.**
