# Transitions System - Design Document

**Date:** 2026-02-06
**Status:** Draft
**Author:** Liquid Editor Team

---

## Table of Contents

1. [Overview](#1-overview)
2. [Transition Theory](#2-transition-theory)
3. [Data Models](#3-data-models)
4. [Timeline Integration](#4-timeline-integration)
5. [Architecture](#5-architecture)
6. [Rendering - Preview](#6-rendering---preview)
7. [Rendering - Export](#7-rendering---export)
8. [Timeline UI](#8-timeline-ui)
9. [Transition Browser UI](#9-transition-browser-ui)
10. [Audio Handling](#10-audio-handling)
11. [Built-in Transition Catalog](#11-built-in-transition-catalog)
12. [Edge Cases](#12-edge-cases)
13. [Performance](#13-performance)
14. [Dependencies](#14-dependencies)
15. [Implementation Plan](#15-implementation-plan)

---

## 1. Overview

### Purpose

The Transitions System adds professional clip-to-clip transition effects to the Liquid Editor timeline. Transitions define how one clip visually (and optionally audibly) morphs into the next, replacing a hard cut with a smooth animated effect.

### Goals

1. **Professional quality** -- Transitions must be frame-accurate, smooth at 60 FPS during preview, and rendered with hardware acceleration during export.
2. **Native iOS integration** -- Export leverages AVFoundation's `AVVideoCompositing` protocol and `CIFilter` pipeline for GPU-accelerated rendering.
3. **Intuitive UX** -- Adding a transition is a single tap on the cut point between two adjacent clips. Adjusting duration is a drag gesture on the transition handle. Changing type is a tap on the transition indicator.
4. **Preservation of existing architecture** -- Transitions integrate with the existing Persistent AVL Order Statistic Tree, O(1) undo/redo, double-buffered composition hot-swap, and frame cache without breaking any performance contracts.
5. **Audio awareness** -- Video transitions automatically apply a companion audio crossfade unless the user explicitly disables it.

### Non-Goals (Out of Scope for V1)

- Custom user-created transitions (shader authoring)
- Transition keyframes (animating transition parameters over the transition duration)
- 3D transitions (requires SceneKit or RealityKit integration)
- Transitions between tracks (only same-track adjacent clips)

---

## 2. Transition Theory

### How Transitions Work in NLEs

A transition is fundamentally an **overlap** between two adjacent clips. During the overlap interval, both clips are simultaneously "active" and a blending function determines what the viewer sees at each frame.

```
Hard cut (no transition):

Clip A ████████████|
                   |████████████ Clip B

With transition (overlap model):

Clip A ████████████████|
                 |██████████████ Clip B
                 |<-overlap->|
                 ^ transition zone
```

The overlap is created by extending both clips beyond their original cut point:
- Clip A extends its **tail** past the original cut point.
- Clip B extends its **head** before the original cut point.

This requires that both clips have **handles** -- unused source media beyond their current in/out points -- sufficient to cover the transition duration.

### A-B Roll Concept

During a transition, two video streams are active simultaneously:

- **A-Roll (outgoing clip):** The clip ending. Provides frames that are fading out / moving out / dissolving away.
- **B-Roll (incoming clip):** The clip starting. Provides frames that are fading in / moving in / appearing.

The transition algorithm receives both frames and produces a single composited output frame for each time step within the transition interval.

### Transition Timing Modes

The `TransitionAlignment` enum (already defined in the codebase) controls how the overlap is positioned relative to the cut point:

| Alignment | Overlap Position | A-clip extension | B-clip extension |
|-----------|-----------------|-----------------|-----------------|
| `centerOnCut` | Centered on the original cut point | `duration / 2` past cut | `duration / 2` before cut |
| `startAtCut` | Starts at the original cut point | `0` (no extension) | `duration` before cut |
| `endAtCut` | Ends at the original cut point | `duration` past cut | `0` (no extension) |

**Default:** `centerOnCut` is the industry standard and the default for this system.

### Handle Requirement

A transition can only be applied if both adjacent clips have sufficient **source media handles**:

```
For centerOnCut with duration D:
  - Left clip needs at least D/2 of unused source media AFTER its current out point.
  - Right clip needs at least D/2 of unused source media BEFORE its current in point.

Maximum possible transition duration = min(leftClipHandle, rightClipHandle) * 2
```

If a clip has been trimmed, the trimmed-off portion constitutes available handles. If a clip has NOT been trimmed (the visible region equals the full source), there are zero handles and no transition is possible.

### Timeline Duration Impact

**Important:** Adding a transition **shortens** the total timeline duration by the overlap amount.

```
Before transition:
  Total = duration(A) + duration(B) = 5s + 3s = 8s

After 1-second centered transition:
  Total = duration(A) + duration(B) - overlap = 5s + 3s - 1s = 7s
```

This must be accounted for in all timeline calculations, ripple behavior, and playhead positioning.

---

## 3. Data Models

### 3.1 Existing: `ClipTransition` (transition.dart)

The codebase already contains a well-designed `ClipTransition` model at `lib/timeline/data/models/transition.dart`. This model provides:

- `id` -- Unique transition identifier.
- `leftClipId` / `rightClipId` -- References to adjacent clips.
- `trackId` -- Track containment.
- `type` -- `TransitionType` enum (crossDissolve, crossfade, dip, wipe, slide, zoom, push, custom).
- `duration` -- Duration in microseconds (clamped between `minDuration` 66666us and `maxDuration` 5000000us).
- `alignment` -- `TransitionAlignment` (centerOnCut, startAtCut, endAtCut).
- `editPointTime` -- The original cut point time.
- `direction` -- `TransitionDirection` (left, right, up, down) for directional transitions.
- `easing` -- Flutter `Curve` for transition timing.
- `parameters` -- `Map<String, dynamic>` for per-type custom parameters.
- Computed `timeRange`, `startTime`, `endTime`, `leftOverlapRequired`, `rightOverlapRequired`.
- Full serialization (toJson / fromJson).

### 3.2 Extended: `TransitionType` Enum

The existing `TransitionType` enum needs expansion to cover the full transition catalog. We extend the existing enum values:

```dart
enum TransitionType {
  // === Basic ===
  crossDissolve,    // Already exists - opacity blend between A and B
  crossfade,        // Already exists - audio crossfade
  dip,              // Already exists - dip to color (default black)

  // === Wipe ===
  wipe,             // Already exists - directional wipe
  wipeClock,        // NEW - clockwise radial wipe
  wipeIris,         // NEW - iris (circular) wipe

  // === Slide ===
  slide,            // Already exists - slide transition
  push,             // Already exists - push transition
  slideOver,        // NEW - new clip slides over old clip
  slideUnder,       // NEW - old clip slides to reveal new clip

  // === Zoom ===
  zoom,             // Already exists - zoom transition
  zoomIn,           // NEW - zoom into cut point
  zoomOut,          // NEW - zoom out from cut point

  // === Special ===
  fadeToBlack,      // NEW - fade A to black, then black to B
  fadeToWhite,      // NEW - fade A to white, then white to B
  blur,             // NEW - blur A out, blur B in
  rotation,         // NEW - rotate A out, rotate B in
  pageCurl,         // NEW - page curl effect

  // === Custom ===
  custom,           // Already exists - custom/plugin transition
}
```

### 3.3 Extended: `TransitionTypeExtension`

New properties for each transition type:

```dart
extension TransitionTypeExtension on TransitionType {
  /// Display name for UI.
  String get displayName;

  /// SF Symbol icon name (for CNSymbol).
  String get sfSymbolName;

  /// Category for browser grouping.
  TransitionCategory get category;

  /// Default duration in microseconds.
  TimeMicros get defaultDuration;

  /// Whether this type supports direction parameter.
  bool get supportsDirection;

  /// Whether this type supports color parameter (dip, fadeToBlack, etc.).
  bool get supportsColor;

  /// Whether this type supports softness parameter (wipe, blur).
  bool get supportsSoftness;

  /// Whether this type requires two simultaneous video frames.
  bool get requiresDualFrames;

  /// Whether this transition supports audio.
  bool get supportsAudio;

  /// Whether this transition supports video.
  bool get supportsVideo;
}
```

### 3.4 New: `TransitionCategory` Enum

```dart
enum TransitionCategory {
  basic,    // Cross dissolve, dip, fade to black/white
  wipe,     // Wipe (directional, clock, iris)
  slide,    // Slide, push, slide over, slide under
  zoom,     // Zoom in, zoom out
  special,  // Blur, rotation, page curl
}
```

### 3.5 New: `TransitionPreset`

Pre-configured parameter bundles for common use:

```dart
@immutable
class TransitionPreset {
  final String id;
  final String name;
  final TransitionType type;
  final TimeMicros duration;
  final TransitionDirection direction;
  final Curve easing;
  final Map<String, dynamic> parameters;
  final bool isFavorite;

  const TransitionPreset({...});
}
```

### 3.6 Transition Parameter Keys

Standardized parameter keys for the `parameters` map:

| Key | Type | Description | Used By |
|-----|------|-------------|---------|
| `softness` | `double` (0.0-1.0) | Edge softness for wipes | wipe, wipeClock, wipeIris |
| `color` | `int` (ARGB) | Dip color | dip, fadeToBlack, fadeToWhite |
| `blurRadius` | `double` (0.0-50.0) | Maximum blur sigma | blur |
| `rotationAngle` | `double` (radians) | Rotation amount | rotation |
| `curlRadius` | `double` (0.0-1.0) | Page curl tightness | pageCurl |
| `zoomFactor` | `double` (1.0-5.0) | Zoom magnification | zoomIn, zoomOut |

### 3.7 Serialization

The existing `ClipTransition.toJson()` / `ClipTransition.fromJson()` already handle serialization correctly. The `Curve` field cannot be serialized directly (noted in existing code); we solve this by adding a `curveType` string field that maps to a known set of curves:

```dart
// In parameters map:
'curveType': 'easeInOut'  // Maps to Curves.easeInOut

// Known curve names:
static const Map<String, Curve> _knownCurves = {
  'linear': Curves.linear,
  'easeIn': Curves.easeIn,
  'easeOut': Curves.easeOut,
  'easeInOut': Curves.easeInOut,
  'fastOutSlowIn': Curves.fastOutSlowIn,
  'decelerate': Curves.decelerate,
  'bounceOut': Curves.bounceOut,
  'elasticOut': Curves.elasticOut,
};
```

---

## 4. Timeline Integration

### 4.1 Storage Model: Transitions as Side-Channel Metadata

**Decision:** Transitions are stored as **side-channel metadata**, NOT as clip-type nodes in the Persistent AVL tree.

**Rationale:**
- The Persistent AVL tree stores `TimelineItem` instances that have sequential, non-overlapping durations. Transitions represent temporal overlaps, which violate the tree's sequential invariant.
- Inserting a "TransitionClip" between two clips would break O(log n) time-to-position lookups because transition regions straddle two clips.
- Professional NLEs (Final Cut Pro, DaVinci Resolve) store transitions as metadata on cut points, not as timeline items.

**Implementation:**

Transitions are stored in a separate immutable collection alongside the timeline tree:

```dart
@immutable
class TimelineState {
  /// The persistent AVL tree of clips.
  final PersistentTimeline timeline;

  /// Transitions indexed by ID.
  final Map<String, ClipTransition> transitions;

  /// Quick lookup: left clip ID to transition.
  final Map<String, String> leftClipToTransition;

  /// Quick lookup: right clip ID to transition.
  final Map<String, String> rightClipToTransition;

  const TimelineState({
    required this.timeline,
    this.transitions = const {},
    this.leftClipToTransition = const {},
    this.rightClipToTransition = const {},
  });
}
```

This preserves all existing tree properties while adding transition support.

### 4.2 Overlap Model: How Clips Change

When a transition is added between clips A and B:

1. **Clip A's visible tail extends** by `leftOverlapRequired` microseconds into its source handles.
2. **Clip B's visible head extends** by `rightOverlapRequired` microseconds into its source handles.
3. **Clip B's timeline start time shifts earlier** by `rightOverlapRequired`.
4. All subsequent clips shift earlier by the total overlap amount (ripple).
5. Total timeline duration decreases by the overlap amount.

The clips themselves in the PersistentTimeline are NOT modified. Instead, the composition builder reads the transition metadata and adjusts the AVComposition segments accordingly at build time.

**Critical insight:** The tree stores the **editorial** (non-overlapping) durations. The **presentation** (overlapping) durations are computed only during composition building and rendering by consulting the transition map.

### 4.3 Timeline Duration Calculation

With transitions, the effective timeline duration becomes:

```
effectiveDuration = tree.totalDurationMicros - sum(transition.overlapAmount for each transition)

where overlapAmount = min(transition.leftOverlapRequired, transition.rightOverlapRequired) * 2
    (for center-on-cut: overlapAmount = transition.duration)
```

A helper method on `TimelineState`:

```dart
int get effectiveDurationMicros {
  int totalOverlap = 0;
  for (final transition in transitions.values) {
    totalOverlap += transition.duration;
  }
  return timeline.totalDurationMicros - totalOverlap;
}
```

### 4.4 Time Mapping with Transitions

Converting between "editorial time" (tree positions) and "presentation time" (what the user sees on the playhead) requires accounting for transition overlaps:

```dart
/// Convert presentation time to editorial time.
int presentationToEditorial(int presentationMicros) {
  int editorialTime = presentationMicros;
  // For each transition before this point, add back the overlap
  for (final transition in sortedTransitions) {
    if (transition.editPointTime <= editorialTime) {
      editorialTime += transition.duration;
    } else {
      break;
    }
  }
  return editorialTime;
}

/// Convert editorial time to presentation time.
int editorialToPresentation(int editorialMicros) {
  int presentationTime = editorialMicros;
  for (final transition in sortedTransitions) {
    if (transition.editPointTime <= editorialMicros) {
      presentationTime -= transition.duration;
    } else {
      break;
    }
  }
  return presentationTime;
}
```

### 4.5 Handle Validation

Before allowing a transition to be added:

```dart
/// Check if a transition can be placed between two clips.
TransitionValidation validateTransition({
  required TimelineItem leftClip,
  required TimelineItem rightClip,
  required TimeMicros desiredDuration,
  required TransitionAlignment alignment,
}) {
  // 1. Both clips must be video or image (not gap, color, audio-only)
  if (leftClip is GapClip || rightClip is GapClip) {
    return TransitionValidation.invalidClipType;
  }

  // 2. Clips must be on the same track
  // (enforced by caller -- transitions only between adjacent clips)

  // 3. Check source media handles
  if (leftClip is MediaClip) {
    final asset = assetRegistry.getById(leftClip.mediaAssetId);
    final leftAvailableHandle = asset.totalDuration - leftClip.sourceOutMicros;
    if (leftAvailableHandle < requiredLeftOverlap) {
      return TransitionValidation.insufficientLeftHandle;
    }
  }

  if (rightClip is MediaClip) {
    final rightAvailableHandle = rightClip.sourceInMicros;
    if (rightAvailableHandle < requiredRightOverlap) {
      return TransitionValidation.insufficientRightHandle;
    }
  }

  // 4. Check minimum durations after overlap
  // Each clip must remain at least minDuration long after overlap extraction
  // (TimelineClip.minDuration = 33333 microseconds, ~1 frame at 30fps)

  return TransitionValidation.valid;
}
```

### 4.6 Impact on Existing Operations

#### Split Clip with Transition

When a clip that has a transition on either end is split:

- **Left transition (on the head of the clip being split):** The transition stays attached to the LEFT portion of the split. The right portion gets no transition on its head.
- **Right transition (on the tail of the clip being split):** The transition stays attached to the RIGHT portion of the split. The left portion gets no transition on its tail.
- If the split point falls WITHIN a transition zone, the split is disallowed (or the transition is removed first).

```
Before split:
  [Trans] Clip A (with transition on left) [Trans]
                     ^ split here

After split:
  [Trans] Clip A-Left | Clip A-Right [Trans]
  (left transition stays)  (right transition stays)
```

#### Delete Clip with Transition

When a clip that has transitions is deleted:

- **Both transitions attached to the deleted clip are removed.**
- The clips on either side of the deleted clip now have a hard cut between them (or between each and any new gap).
- If the deletion is a ripple delete, subsequent clips shift to fill the gap, and the user may then add a new transition at the new cut point.

#### Reorder Clips with Transition

When a clip is reordered (moved to a different position):

- **All transitions attached to the moved clip are removed.**
- The user must manually re-add transitions at the new position.
- Rationale: The adjacent clips have changed, so the old transitions are invalid.

#### Trim Clip with Transition

When trimming a clip that has a transition:

- If trimming **reduces** the handle below the transition's required overlap, the transition duration is automatically reduced to fit the available handle.
- If trimming removes all handle (trimming to the transition start/end), the transition is removed.
- The trim preview shows real-time feedback about transition duration changes.

#### Undo/Redo with Transitions

Because `TimelineState` is immutable and the undo stack stores complete `TimelineState` snapshots (including the transition map), undo/redo remains O(1) pointer swap:

```dart
class TimelineManager extends ChangeNotifier {
  TimelineState _current;  // Now includes transitions

  // Undo/redo stacks store TimelineState (includes transitions)
  final List<TimelineState> _undoStack = [];
  final List<TimelineState> _redoStack = [];
}
```

Structural sharing ensures minimal memory overhead: if only a transition was added/removed, the PersistentTimeline tree pointer is shared between the old and new state.

---

## 5. Architecture

### 5.1 Component Overview

```
Flutter Layer                          Native Layer (Swift)
============                          ===================

TransitionController                   TransitionCompositor
  - addTransition()                      - AVVideoCompositing protocol
  - removeTransition()                   - CIFilter-based rendering
  - updateDuration()                     - Frame blending
  - updateType()                         - GPU-accelerated export

TransitionRenderer (Flutter)           CompositionBuilder (extended)
  - Preview rendering via shaders        - Builds overlapping segments
  - 60fps CustomPainter output           - AVVideoCompositionInstruction
  - Transition progress calculation       - Per-transition layer instructions

TransitionBrowserController            (No native component needed)
  - Category management
  - Favorites persistence
  - Preview thumbnail generation

TransitionTimelinePainter              (No native component needed)
  - Visual indicator on timeline
  - Drag handles for duration
  - Transition type icon
```

### 5.2 TransitionController

The central orchestrator for transition operations on the Dart side.

**File:** `lib/core/transition_controller.dart`

```dart
class TransitionController extends ChangeNotifier {
  final TimelineManager _timelineManager;
  final MediaAssetRegistry _assetRegistry;

  // === State ===
  String? _selectedTransitionId;

  // === Operations ===

  /// Add a transition between two adjacent clips.
  /// Returns the new ClipTransition, or null if validation fails.
  ClipTransition? addTransition({
    required String leftClipId,
    required String rightClipId,
    TransitionType type = TransitionType.crossDissolve,
    TimeMicros? duration,
    TransitionAlignment alignment = TransitionAlignment.centerOnCut,
  });

  /// Remove a transition by ID.
  void removeTransition(String transitionId);

  /// Update transition duration (with handle validation).
  void updateDuration(String transitionId, TimeMicros newDuration);

  /// Update transition type.
  void updateType(String transitionId, TransitionType newType);

  /// Update transition direction.
  void updateDirection(String transitionId, TransitionDirection direction);

  /// Update transition alignment.
  void updateAlignment(String transitionId, TransitionAlignment alignment);

  /// Update transition parameters.
  void updateParameters(String transitionId, Map<String, dynamic> parameters);

  /// Get the transition at a cut point (if any).
  ClipTransition? transitionAtCutPoint(String leftClipId, String rightClipId);

  /// Get all transitions for a track.
  List<ClipTransition> transitionsForTrack(String trackId);

  /// Get transition attached to a clip (left or right side).
  ClipTransition? transitionOnLeft(String clipId);
  ClipTransition? transitionOnRight(String clipId);

  /// Calculate maximum allowed duration for a transition.
  TimeMicros maxDurationForTransition(String leftClipId, String rightClipId);

  /// Select/deselect transition.
  void selectTransition(String? transitionId);
}
```

### 5.3 TransitionRenderer (Flutter-side Preview)

Handles real-time rendering of transitions during preview playback.

**File:** `lib/timeline/rendering/transition_renderer.dart`

```dart
class TransitionRenderer {
  /// Render a transition frame.
  ///
  /// [frameA] - Outgoing clip frame (BGRA pixels).
  /// [frameB] - Incoming clip frame (BGRA pixels).
  /// [progress] - Transition progress (0.0 = all A, 1.0 = all B).
  /// [transition] - The ClipTransition being rendered.
  /// [outputSize] - Desired output dimensions.
  ///
  /// Returns composited frame as Uint8List (BGRA).
  Future<Uint8List> renderTransitionFrame({
    required CachedFrame frameA,
    required CachedFrame frameB,
    required double progress,
    required ClipTransition transition,
    required Size outputSize,
  });
}
```

### 5.4 Integration with Existing Components

#### ClipManager (lib/core/clip_manager.dart)

The existing `ClipManager` operates on the legacy timeline model. The transition system integrates with the V2 `TimelineManager` instead, which uses the PersistentTimeline. No changes to `ClipManager` are needed.

#### TimelineManager (lib/core/timeline_manager.dart)

Extended to hold `TimelineState` (which includes the transition map) instead of bare `PersistentTimeline`. All existing operations (insert, remove, split, trim, undo, redo) are updated to propagate transition changes.

#### CompositionManager (lib/core/composition_manager.dart)

The `_buildSegment` method is extended to emit overlapping segments when transitions are present. Transition metadata is included in the native call so `CompositionBuilder.swift` can construct the proper `AVVideoCompositionInstruction` for each transition.

#### FrameCache (lib/core/frame_cache.dart)

During transition preview, the frame cache must potentially serve frames from TWO assets simultaneously. The existing multi-asset support (cache keys include assetId) already handles this. The only change is that the prefetch strategy should preload frames from both the outgoing and incoming clips around transition boundaries.

#### PlaybackEngineController (lib/core/playback_engine_controller.dart)

The playback engine must detect when the playhead enters a transition zone and switch to dual-frame rendering mode. This means requesting frames from both the outgoing and incoming clips at each display tick.

---

## 6. Rendering - Preview

### 6.1 Strategy: Fragment Shader-Based Rendering

During preview playback, transitions are rendered in Flutter using **fragment shaders** (`dart:ui` FragmentProgram). This approach provides:

- GPU-accelerated rendering on iOS Metal.
- 60 FPS performance even for complex transitions.
- No platform channel round-trips per frame.
- Consistent look between preview and export (both use GPU blending).

### 6.2 Shader Architecture

Each transition type maps to one or more GLSL/Metal fragment shaders:

```
lib/shaders/
  transitions/
    dissolve.frag          # Cross dissolve (alpha blend)
    dip_to_color.frag      # Dip to color
    wipe_directional.frag  # Left/right/up/down wipe with softness
    wipe_clock.frag        # Clockwise radial wipe
    wipe_iris.frag         # Circular iris wipe
    slide.frag             # Slide / push / slide over / slide under
    zoom.frag              # Zoom in / zoom out
    fade_to_color.frag     # Fade to black / white
    blur.frag              # Blur transition
    rotation.frag          # Rotation transition
    page_curl.frag         # Page curl effect
```

### 6.3 Shader Uniform Protocol

All transition shaders follow a standard uniform interface:

```glsl
// Standard uniforms for all transition shaders
uniform sampler2D uTextureA;     // Outgoing clip frame
uniform sampler2D uTextureB;     // Incoming clip frame
uniform float uProgress;         // 0.0 (all A) to 1.0 (all B)
uniform vec2 uResolution;        // Output resolution

// Optional per-type uniforms
uniform float uDirection;        // 0=left, 1=right, 2=up, 3=down
uniform float uSoftness;         // Edge softness (0.0-1.0)
uniform vec4 uColor;             // Dip/fade color (RGBA)
uniform float uBlurRadius;       // Max blur sigma
uniform float uRotationAngle;    // Rotation amount (radians)
uniform float uZoomFactor;       // Zoom magnification
```

### 6.4 Cross Dissolve Shader (Reference Implementation)

```glsl
#version 460

precision mediump float;

uniform sampler2D uTextureA;
uniform sampler2D uTextureB;
uniform float uProgress;

out vec4 fragColor;

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution;
    vec4 colorA = texture(uTextureA, uv);
    vec4 colorB = texture(uTextureB, uv);
    fragColor = mix(colorA, colorB, uProgress);
}
```

### 6.5 Directional Wipe Shader (Parameterized)

```glsl
#version 460

precision mediump float;

uniform sampler2D uTextureA;
uniform sampler2D uTextureB;
uniform float uProgress;
uniform vec2 uResolution;
uniform float uDirection;  // 0=left, 1=right, 2=up, 3=down
uniform float uSoftness;   // 0.0 to 1.0

out vec4 fragColor;

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution;

    // Calculate wipe position based on direction
    float pos;
    if (uDirection < 0.5) {
        pos = uv.x;                    // Wipe left-to-right
    } else if (uDirection < 1.5) {
        pos = 1.0 - uv.x;             // Wipe right-to-left
    } else if (uDirection < 2.5) {
        pos = 1.0 - uv.y;             // Wipe top-to-bottom
    } else {
        pos = uv.y;                    // Wipe bottom-to-top
    }

    // Apply softness to edge
    float edge = smoothstep(uProgress - uSoftness * 0.5,
                            uProgress + uSoftness * 0.5,
                            pos);

    vec4 colorA = texture(uTextureA, uv);
    vec4 colorB = texture(uTextureB, uv);
    fragColor = mix(colorB, colorA, edge);
}
```

### 6.6 Rendering Pipeline (Per Frame)

```
1. PlaybackEngineController detects playhead is in transition zone.
2. Calculate transition progress:
     progress = (playheadTime - transition.startTime) / transition.duration
     progress = transition.easing.transform(progress)  // Apply easing curve
3. Request frame A from outgoing clip (via FrameCache or DecoderPool).
4. Request frame B from incoming clip (via FrameCache or DecoderPool).
5. Upload both frames as textures to the shader.
6. Execute shader with progress and parameters.
7. Display composited frame.
```

### 6.7 Performance Budget

| Operation | Target | Approach |
|-----------|--------|----------|
| Detect transition zone | < 1us | Hash lookup in transition map |
| Calculate progress | < 1us | Simple arithmetic |
| Fetch frame A (cached) | < 2ms | FrameCache.getFrame() |
| Fetch frame B (cached) | < 2ms | FrameCache.getFrame() |
| Shader execution | < 5ms | GPU fragment shader (Metal) |
| Total per frame | < 10ms | Well within 16.6ms (60 FPS) budget |

### 6.8 Fallback: Non-Shader Rendering

If fragment shaders are unavailable (older devices, simulator), fall back to CPU-based rendering:

```dart
/// CPU fallback for cross dissolve.
Uint8List crossDissolveCPU(Uint8List pixelsA, Uint8List pixelsB, double progress) {
  final output = Uint8List(pixelsA.length);
  final invProgress = 1.0 - progress;
  for (int i = 0; i < pixelsA.length; i++) {
    output[i] = (pixelsA[i] * invProgress + pixelsB[i] * progress).round();
  }
  return output;
}
```

CPU fallback is limited to dissolve and fade transitions. Complex transitions (wipe, page curl) display as dissolve on unsupported hardware.

---

## 7. Rendering - Export

### 7.1 Strategy: AVVideoCompositing Protocol

During export, transitions are rendered natively using AVFoundation's custom compositor protocol. This provides:

- Hardware-accelerated GPU rendering via Metal/CIFilter.
- Frame-accurate output with the correct timestamp.
- Integration with the existing `CompositionBuilder.swift` and `AVAssetWriter` export pipeline.
- Professional-grade quality matching Final Cut Pro and iMovie output.

### 7.2 Custom Video Compositor

**File:** `ios/Runner/Timeline/TransitionCompositor.swift`

```swift
/// Custom video compositor that renders transitions between clips.
class TransitionCompositor: NSObject, AVVideoCompositing {
    // Required properties
    var sourcePixelBufferAttributes: [String: Any]? {
        return [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        return [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    // CIContext for GPU-accelerated rendering
    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
    ])

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Prepare for new render size
    }

    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        // 1. Get source frames from both tracks
        // 2. Determine transition type and progress
        // 3. Apply CIFilter-based transition
        // 4. Return composited pixel buffer
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Cancel any pending renders
    }
}
```

### 7.3 Transition Instructions

Each transition generates an `AVVideoCompositionInstruction` that spans the overlap period:

```swift
/// Custom instruction carrying transition metadata.
class TransitionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    // Transition-specific data
    let transitionType: String    // "crossDissolve", "wipe", etc.
    let direction: Int            // 0=left, 1=right, 2=up, 3=down
    let softness: Float
    let color: CIColor?
    let easing: String            // "easeInOut", "linear", etc.
    let parameters: [String: Any]
}
```

### 7.4 CIFilter-Based Transition Rendering

Each transition type maps to a CIFilter composition:

| Transition Type | CIFilter(s) Used |
|----------------|-----------------|
| Cross Dissolve | `CIDissolveTransition` |
| Dip to Color | `CIColorMatrix` -> `CISourceOverCompositing` |
| Wipe (directional) | `CICopyMachineTransition` or custom `CIKernel` |
| Wipe (clock) | Custom `CIKernel` with angle calculation |
| Wipe (iris) | Custom `CIKernel` with radial distance |
| Slide/Push | `CIAffineTransform` on both images + `CISourceOverCompositing` |
| Zoom In/Out | `CIAffineTransform` (scale) + dissolve |
| Fade to Black/White | `CIExposureAdjust` or `CIColorMatrix` + dissolve |
| Blur | `CIGaussianBlur` on both + dissolve |
| Rotation | `CIAffineTransform` (rotation) + dissolve |
| Page Curl | `CIPageCurlTransition` (built-in CIFilter) |

### 7.5 CompositionBuilder Changes

The existing `CompositionBuilder.swift` is extended to handle overlapping segments:

```swift
// In CompositionBuilder.build()

// For each transition, create overlapping track segments:
// Track A: outgoing clip video on track 1
// Track B: incoming clip video on track 2

// During the transition interval:
// - Both tracks have video
// - A TransitionInstruction tells the compositor how to blend

// Before and after the transition:
// - Only one track has video
// - A PassthroughInstruction sends that track directly to output
```

This requires using **two video tracks** in the AVMutableComposition (already supported by AVFoundation):

```swift
let videoTrackA = composition.addMutableTrack(withMediaType: .video, ...)
let videoTrackB = composition.addMutableTrack(withMediaType: .video, ...)
```

Non-transition segments go on track A. During transitions, the outgoing clip's overlap portion goes on track A and the incoming clip's overlap portion goes on track B.

### 7.6 Audio During Export

Audio crossfade during transitions is handled via `AVMutableAudioMix`:

```swift
// For each transition with audio crossfade:
let fadeOutParams = AVMutableAudioMixInputParameters(track: audioTrackA)
fadeOutParams.setVolumeRamp(
    fromStartVolume: 1.0,
    toEndVolume: 0.0,
    timeRange: transitionTimeRange
)

let fadeInParams = AVMutableAudioMixInputParameters(track: audioTrackB)
fadeInParams.setVolumeRamp(
    fromStartVolume: 0.0,
    toEndVolume: 1.0,
    timeRange: transitionTimeRange
)
```

---

## 8. Timeline UI

### 8.1 Visual Representation

Transitions appear between adjacent clips as a distinct visual element:

```
Before (hard cut):
  ┌──────────────┐┌──────────────┐
  │   Clip A     ││   Clip B     │
  └──────────────┘└──────────────┘

After (with transition):
  ┌──────────────╱╲──────────────┐
  │   Clip A    ╱XX╲   Clip B   │
  └────────────╱XXXX╲───────────┘
               transition
```

The transition zone is rendered as:

1. **Overlapping region** where both clips are visible (cross-hatch or gradient pattern).
2. **Transition type icon** centered in the overlap zone (small SF Symbol).
3. **Duration label** below the icon (e.g., "0.5s").
4. **Drag handles** on both edges of the transition for duration adjustment.

### 8.2 TransitionPainter

**File:** `lib/timeline/rendering/painters/transition_painter.dart`

```dart
class TransitionPainter extends CustomPainter {
  final List<ClipTransition> transitions;
  final List<TimelineClip> clips;
  final List<Track> tracks;
  final ViewportState viewport;
  final String? selectedTransitionId;

  // Paint objects (static for reuse)
  static final Paint _transitionFillPaint = Paint()
    ..style = PaintingStyle.fill;

  static final Paint _transitionBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  static final Paint _handlePaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    for (final transition in transitions) {
      if (!viewport.isTimeRangeVisible(transition.timeRange)) continue;

      final track = tracks.firstWhere((t) => t.id == transition.trackId);
      _drawTransition(canvas, transition, track);
    }
  }

  void _drawTransition(Canvas canvas, ClipTransition transition, Track track) {
    // Calculate transition rect
    final x = viewport.timeToPixelX(transition.startTime);
    final width = transition.duration / viewport.microsPerPixel;
    final y = viewport.trackIndexToPixelY(track.index, track.effectiveHeight);
    final height = track.effectiveHeight - 4;
    final rect = Rect.fromLTWH(x, y + 2, width, height);

    // Draw transition indicator (bowtie / hourglass shape)
    _drawBowtieShape(canvas, rect, transition);

    // Draw type icon
    if (rect.width > 20) {
      _drawTransitionIcon(canvas, rect, transition);
    }

    // Draw duration label
    if (rect.width > 40) {
      _drawDurationLabel(canvas, rect, transition);
    }

    // Draw selection highlight and handles
    if (transition.id == selectedTransitionId) {
      _drawSelectionHighlight(canvas, rect);
      _drawDragHandles(canvas, rect);
    }
  }
}
```

### 8.3 Interaction Gestures

#### Adding a Transition

1. User taps the **cut point** between two adjacent clips (the thin vertical line between clips).
2. A `CupertinoActionSheet` appears with transition categories.
3. User selects a transition type.
4. Transition is created with the default duration for that type.
5. Haptic feedback (`HapticFeedback.mediumImpact()`).

**Hit testing:** The existing `HitTestResult.transition(transitionId)` in `edit_operations.dart` already supports transition hit detection. We extend the hit testing logic to also detect **empty cut points** (gaps between adjacent clips where no transition exists):

```dart
enum HitType {
  // ... existing types ...
  transition,   // Already exists
  cutPoint,     // NEW - empty cut point between clips
}
```

#### Adjusting Duration

1. User long-presses or taps on a transition to select it.
2. Drag handles appear on both edges.
3. User drags a handle to change duration (0.1s to 5.0s, clamped by handle availability).
4. Real-time visual feedback as the transition zone expands/contracts.
5. Haptic feedback at snap points (0.25s increments).

#### Changing Transition Type

1. User taps on a selected transition.
2. The Transition Browser sheet appears (see Section 9).
3. User selects a new type.
4. Transition updates in place.

#### Removing a Transition

1. User selects a transition.
2. User taps the delete button (or swipe-to-delete gesture).
3. `CupertinoAlertDialog` confirmation.
4. Transition is removed; clips snap back to a hard cut.
5. Timeline duration increases by the removed overlap amount.

### 8.4 Snap Behavior

The existing snap system (defined in `edit_operations.dart` with `SnapTargetType` and `SnapGuide`) is extended:

```dart
enum SnapTargetType {
  // ... existing types ...
  transitionEdge,  // NEW - snap to transition boundaries
}
```

Transition duration handles snap to:
- 0.25-second increments
- Other transition boundaries on the same track
- Marker positions
- Maximum available handle length

---

## 9. Transition Browser UI

### 9.1 Sheet Presentation

The Transition Browser appears as a `CupertinoActionSheet`-style bottom sheet with a Liquid Glass background. It uses native iOS 26 components exclusively.

### 9.2 Layout Structure

```
┌─────────────────────────────────┐
│  Drag handle                    │
│                                 │
│  [Favourites] [Basic] [Wipe]   │  <-- CNTabBar (category tabs)
│  [Slide] [Zoom] [Special]      │
│                                 │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐      │
│  │ A │ │ A │ │ A │ │ A │      │  <-- Animated preview grid
│  │ n │ │ n │ │ n │ │ n │      │
│  │ i │ │ i │ │ i │ │ i │      │
│  │ m │ │ m │ │ m │ │ m │      │
│  └───┘ └───┘ └───┘ └───┘      │
│  Dissolve Dip  Wipe-L Wipe-R  │
│                                 │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐      │
│  │   │ │   │ │   │ │   │      │
│  └───┘ └───┘ └───┘ └───┘      │
│  Push  Slide  Zoom-I Zoom-O   │
│                                 │
│  ── Duration ──                 │
│  [========|========] 0.50s      │  <-- CupertinoSlider
│                                 │
│  [Apply]                        │  <-- CupertinoButton
└─────────────────────────────────┘
```

### 9.3 Animated Preview Thumbnails

Each transition option shows an animated thumbnail preview:

1. **Capture two frames:** A frame from near the end of the outgoing clip and a frame from near the start of the incoming clip.
2. **Render looping animation:** Apply the transition shader with progress cycling 0.0 -> 1.0 -> 0.0 at approximately 2-second loop.
3. **Display in grid cell:** Each cell is a small (80x60) animated preview.

If the actual clip frames are unavailable (e.g., browsing transitions before any clips are on the timeline), use stock preview frames (gradient A, gradient B).

### 9.4 Favorites

- Each transition has a heart icon toggle in the top-right corner of its preview cell.
- Favourites are persisted to `UserDefaults` / `SharedPreferences` as a `Set<String>` of transition type names.
- The "Favourites" tab in the browser shows only favorited transitions.
- Consistent with the project's existing favourites pattern (project library uses a similar mechanism).

### 9.5 Duration Picker

Below the transition grid, a `CupertinoSlider` allows setting the duration:

```dart
CupertinoSlider(
  value: _currentDuration,
  min: 0.1,
  max: maxDuration,  // Computed from handle availability
  divisions: ((maxDuration - 0.1) / 0.05).round(),  // 50ms steps
  onChanged: (value) {
    HapticFeedback.selectionClick();
    setState(() => _currentDuration = value);
  },
)
```

### 9.6 Search/Filter

A `CupertinoSearchTextField` at the top of the browser allows searching transitions by name:

```dart
CupertinoSearchTextField(
  placeholder: 'Search transitions',
  onChanged: _filterTransitions,
)
```

---

## 10. Audio Handling

### 10.1 Automatic Audio Crossfade

When a video transition is applied between two clips that have audio, the system automatically creates a companion audio crossfade:

- **Default behavior:** Audio crossfade is enabled and matches the video transition duration.
- **User override:** A toggle in the transition inspector allows disabling the audio crossfade.
- **When disabled:** Audio cuts hard at the original cut point (no overlap).

### 10.2 Volume Curves

Three audio crossfade modes are supported:

#### Linear Crossfade

```
Volume
  1.0 ───╲     ╱───
         ╲   ╱
  0.5     ╲ ╱
           ╳
  0.0 ───╱ ╲───
      A-out  B-in
```

Simple linear ramp. Sum of both volumes = 1.0 at all points. Potential perceived volume dip at the midpoint because power is not constant.

#### Equal Power Crossfade (Default)

```
Volume
  1.0 ───╲       ╱───
          ╲     ╱
  0.7      ╲   ╱       (sqrt(0.5) = 0.707)
            ╲ ╱
  0.0 ────╱  ╲────
      A-out   B-in
```

Uses `sqrt(progress)` for fade-in and `sqrt(1 - progress)` for fade-out. Maintains constant perceived loudness because the sum of squared amplitudes is constant.

```dart
double equalPowerFadeOut(double progress) => math.sqrt(1.0 - progress);
double equalPowerFadeIn(double progress) => math.sqrt(progress);
```

#### S-Curve Crossfade

```
Volume
  1.0 ──────╲        ╱──────
             ╲      ╱
  0.5         ╲    ╱
               ╲  ╱
  0.0 ──────── ╲╱ ──────
            A-out  B-in
```

Uses smoothstep (Hermite interpolation). Holds near 1.0 and 0.0 longer, transitions quickly through the middle. Good for music beds.

```dart
double sCurveFade(double progress) {
  return progress * progress * (3.0 - 2.0 * progress);
}
```

### 10.3 Audio Crossfade Parameter Storage

The crossfade mode is stored in the transition's `parameters` map:

```dart
{
  'audioCrossfade': true,        // Whether audio crossfade is active
  'audioCurveType': 'equalPower' // 'linear', 'equalPower', or 'sCurve'
}
```

### 10.4 Implementation in VolumeEnvelope

The existing `VolumeEnvelope` class (in `volume_keyframe.dart`) provides exactly the infrastructure needed for audio crossfade. When a transition with audio crossfade is active:

1. Create a `VolumeEnvelope.fadeOut(...)` on the outgoing clip for the transition zone.
2. Create a `VolumeEnvelope.fadeIn(...)` on the incoming clip for the transition zone.
3. These envelopes are merged with any existing volume keyframes on the clips.
4. During composition building, the envelopes are converted to `AVMutableAudioMixInputParameters` volume ramps.

### 10.5 Audio-Only Transitions

The existing `TransitionType.crossfade` is specifically for audio-only transitions (no video effect). This is used for:
- Transitions between audio clips on audio-only tracks.
- Standalone audio crossfade when video transition is disabled.

---

## 11. Built-in Transition Catalog

### 11.1 Basic Category

#### Cross Dissolve

- **Name:** Cross Dissolve
- **Category:** Basic
- **Description:** Opacity blend between outgoing and incoming clips. The most natural and commonly used transition.
- **Parameters:** None (easing curve only).
- **Default Duration:** 500ms.
- **SF Symbol:** `rectangle.on.rectangle.angled`
- **Shader:** `dissolve.frag` -- Simple `mix(colorA, colorB, progress)`.
- **CIFilter (export):** `CIDissolveTransition`.
- **Preview Thumbnail:** Two overlapping semi-transparent rectangles.

#### Dip to Black

- **Name:** Dip to Black
- **Category:** Basic
- **Description:** Outgoing clip fades to black; incoming clip fades from black. Two-phase transition (50% fade-out, 50% fade-in).
- **Parameters:** `color` (default: `0xFF000000` black).
- **Default Duration:** 1000ms.
- **SF Symbol:** `square.fill`
- **Shader:** `dip_to_color.frag` -- Phase 1: `mix(colorA, dipColor, progress * 2)`, Phase 2: `mix(dipColor, colorB, (progress - 0.5) * 2)`.
- **CIFilter (export):** `CIColorMatrix` + `CISourceOverCompositing`.
- **Preview Thumbnail:** Rectangle fading to black.

#### Fade to Black

- **Name:** Fade to Black
- **Category:** Basic
- **Description:** Outgoing clip fades to black, then incoming clip fades from black. Similar to Dip but with configurable hold time on black.
- **Parameters:** `color` (default: `0xFF000000`).
- **Default Duration:** 1000ms.
- **SF Symbol:** `moon.fill`
- **Shader:** Same as dip_to_color.frag.
- **CIFilter (export):** Same as Dip to Black.

#### Fade to White

- **Name:** Fade to White
- **Category:** Basic
- **Description:** Outgoing clip fades to white, then incoming clip fades from white. Often used for dreamy or flashback sequences.
- **Parameters:** `color` (default: `0xFFFFFFFF`).
- **Default Duration:** 1000ms.
- **SF Symbol:** `sun.max.fill`
- **Shader:** Same as dip_to_color.frag with white color.
- **CIFilter (export):** Same as Dip with white color parameter.

### 11.2 Wipe Category

#### Wipe Left

- **Name:** Wipe Left
- **Category:** Wipe
- **Description:** A hard or soft edge sweeps from right to left, revealing the incoming clip.
- **Parameters:** `direction` (left), `softness` (0.0-1.0, default 0.05).
- **Default Duration:** 500ms.
- **SF Symbol:** `arrow.left.square`
- **Shader:** `wipe_directional.frag` with direction=0.
- **CIFilter (export):** Custom `CIKernel` or `CICopyMachineTransition`.

#### Wipe Right

- **Name:** Wipe Right
- **Category:** Wipe
- **Description:** Edge sweeps from left to right.
- **Parameters:** `direction` (right), `softness`.
- **Other details:** Same as Wipe Left with direction=1.

#### Wipe Up

- **Name:** Wipe Up
- **Category:** Wipe
- **Description:** Edge sweeps from bottom to top.
- **Parameters:** `direction` (up), `softness`.

#### Wipe Down

- **Name:** Wipe Down
- **Category:** Wipe
- **Description:** Edge sweeps from top to bottom.
- **Parameters:** `direction` (down), `softness`.

#### Clock Wipe

- **Name:** Clock Wipe
- **Category:** Wipe
- **Description:** A radial wipe sweeping clockwise from 12 o'clock, like a clock hand.
- **Parameters:** `softness` (0.0-1.0).
- **Default Duration:** 750ms.
- **SF Symbol:** `clock.arrow.circlepath`
- **Shader:** `wipe_clock.frag` -- Uses `atan2` to calculate angle from center, compares to `progress * 2 * PI`.
- **CIFilter (export):** Custom `CIKernel`.

#### Iris Wipe

- **Name:** Iris Wipe
- **Category:** Wipe
- **Description:** A circular opening/closing wipe from the center outward (or inward).
- **Parameters:** `softness` (0.0-1.0).
- **Default Duration:** 500ms.
- **SF Symbol:** `circle.dashed`
- **Shader:** `wipe_iris.frag` -- Uses distance from center, compares to `progress * maxRadius`.
- **CIFilter (export):** Custom `CIKernel`.

### 11.3 Slide Category

#### Push

- **Name:** Push
- **Category:** Slide
- **Description:** Incoming clip pushes outgoing clip off-screen. Both clips move simultaneously.
- **Parameters:** `direction` (left/right/up/down, default left).
- **Default Duration:** 500ms.
- **SF Symbol:** `arrow.right.circle`
- **Shader:** `slide.frag` -- mode=push. Clip A translates off-screen in direction; Clip B translates on-screen from opposite direction.
- **CIFilter (export):** `CIAffineTransform` on both + `CISourceOverCompositing`.

#### Slide Over

- **Name:** Slide Over
- **Category:** Slide
- **Description:** Incoming clip slides over the outgoing clip (which stays stationary).
- **Parameters:** `direction` (default left).
- **Default Duration:** 500ms.
- **SF Symbol:** `arrow.right.square`
- **Shader:** `slide.frag` -- mode=slideOver. Clip A stays still; Clip B slides from off-screen over it.
- **CIFilter (export):** `CIAffineTransform` on B only + compositing.

#### Slide Under

- **Name:** Slide Under
- **Category:** Slide
- **Description:** Outgoing clip slides off-screen, revealing the incoming clip (which is already in position underneath).
- **Parameters:** `direction` (default left).
- **Default Duration:** 500ms.
- **SF Symbol:** `arrow.left.square`
- **Shader:** `slide.frag` -- mode=slideUnder. Clip A slides off; Clip B is stationary beneath.
- **CIFilter (export):** `CIAffineTransform` on A only.

### 11.4 Zoom Category

#### Zoom In

- **Name:** Zoom In
- **Category:** Zoom
- **Description:** Outgoing clip zooms in (magnifies) and dissolves into the incoming clip.
- **Parameters:** `zoomFactor` (1.0-5.0, default 3.0).
- **Default Duration:** 500ms.
- **SF Symbol:** `plus.magnifyingglass`
- **Shader:** `zoom.frag` -- Clip A scales up from center while fading; Clip B appears at normal scale.
- **CIFilter (export):** `CIAffineTransform` (scale) + `CIDissolveTransition`.

#### Zoom Out

- **Name:** Zoom Out
- **Category:** Zoom
- **Description:** Incoming clip starts zoomed in and scales to normal size while the outgoing clip fades.
- **Parameters:** `zoomFactor` (1.0-5.0, default 3.0).
- **Default Duration:** 500ms.
- **SF Symbol:** `minus.magnifyingglass`
- **Shader:** `zoom.frag` reversed -- Clip A fades; Clip B scales down to normal from zoomed.
- **CIFilter (export):** `CIAffineTransform` + dissolve (reversed zoom direction).

### 11.5 Special Category

#### Blur Transition

- **Name:** Blur
- **Category:** Special
- **Description:** Outgoing clip blurs out while incoming clip blurs in. Both clips meet at maximum blur at the midpoint.
- **Parameters:** `blurRadius` (0.0-50.0, default 20.0).
- **Default Duration:** 750ms.
- **SF Symbol:** `aqi.medium`
- **Shader:** `blur.frag` -- Two-pass Gaussian blur. Phase 1: Clip A blur increases `0 -> blurRadius`, opacity decreases. Phase 2: Clip B blur decreases `blurRadius -> 0`, opacity increases.
- **CIFilter (export):** `CIGaussianBlur` on both images with animated radius.
- **Performance Note:** Blur is computationally expensive. During preview, use downscaled textures (half-resolution) for blur calculation, then upscale. During export, use full resolution.

#### Rotation Transition

- **Name:** Rotation
- **Category:** Special
- **Description:** Outgoing clip rotates off-screen while incoming clip rotates in.
- **Parameters:** `rotationAngle` (default PI/2 = 90 degrees).
- **Default Duration:** 600ms.
- **SF Symbol:** `rotate.right`
- **Shader:** `rotation.frag` -- Clip A rotates by `angle * progress` with scaling; dissolve into Clip B rotating in from opposite angle.
- **CIFilter (export):** `CIAffineTransform` (rotation + scale) + compositing.

#### Page Curl

- **Name:** Page Curl
- **Category:** Special
- **Description:** Outgoing clip curls away like a page being turned, revealing the incoming clip underneath.
- **Parameters:** `curlRadius` (0.0-1.0, default 0.5).
- **Default Duration:** 800ms.
- **SF Symbol:** `book.pages`
- **Shader:** `page_curl.frag` -- Complex shader simulating 3D page curl with shadow and backside.
- **CIFilter (export):** `CIPageCurlTransition` (built-in CIFilter).
- **Performance Note:** Page curl is the most expensive transition. If frame rate drops below 45 FPS during preview, automatically degrade to cross dissolve.

---

## 12. Edge Cases

### 12.1 Transition Longer Than Either Clip

**Scenario:** User tries to set a transition duration of 3 seconds between a 2-second clip and a 4-second clip.

**Behavior:** The transition duration is clamped to `min(leftClipDuration, rightClipDuration) - minClipDuration`. In this example: `min(2s, 4s) - 0.033s = 1.967s`. This ensures both clips remain at least 1 frame long after the overlap is extracted.

**UI feedback:** The duration slider's maximum value dynamically reflects this constraint. If the user drags beyond the maximum, the handle snaps to the max with haptic feedback.

### 12.2 Transition at Start/End of Timeline

**Scenario:** The first clip on the timeline has no clip before it; the last clip has no clip after it.

**Behavior:** Transitions can only be placed between two adjacent clips. The first clip's head and the last clip's tail cannot have transitions. Tapping the start of the first clip or end of the last clip shows no transition option.

**Exception:** A "Fade from Black" or "Fade to Black" could be implemented as a special single-clip effect (not a transition). This is out of scope for V1 but noted for future work.

### 12.3 Adjacent Transitions (Clip Between Two Transitions)

**Scenario:** Clip B sits between Clip A and Clip C. Both cut points have transitions.

```
[Clip A] <-trans1-> [Clip B] <-trans2-> [Clip C]
```

**Behavior:** Both transitions are independent. However, the combined overlap from both transitions must not exceed Clip B's duration minus `minClipDuration`. When adding the second transition, the maximum allowed duration is:

```
maxDuration2 = clipB.duration - trans1.overlapOnRight - minClipDuration
```

If adding a second transition would shrink Clip B below `minClipDuration`, the operation is rejected with a user-visible message.

### 12.4 Transition on Very Short Clips

**Scenario:** Clip B is only 200ms long.

**Behavior:** The maximum transition duration on either side is `200ms - minClipDuration (33ms) = 167ms`. If there are transitions on both sides, the total overlap from both cannot exceed `200ms - 33ms = 167ms`. This is validated before allowing either transition to be added or resized.

### 12.5 Removing a Clip with Transitions

**Scenario:** User deletes Clip B which has transitions on both sides.

**Behavior (Ripple Delete):**
1. Both transitions (trans1 and trans2) are removed.
2. Clip B is removed.
3. Remaining clips ripple to fill the gap.
4. Clip A and Clip C are now adjacent. User may add a new transition between them.

**Behavior (Non-Ripple Delete):**
1. Both transitions are removed.
2. Clip B is replaced with a GapClip of the same duration.
3. Transitions cannot be placed on GapClips.

### 12.6 Splitting a Clip with Transitions

**Scenario:** User splits Clip B at the midpoint. Clip B has transitions on both sides.

```
Before: [A] <-t1-> [B] <-t2-> [C]
Split B at midpoint:
After:  [A] <-t1-> [B1] | [B2] <-t2-> [C]
```

**Behavior:**
1. Clip B splits into B1 and B2.
2. Transition t1 (between A and B) updates: `rightClipId` changes from B's ID to B1's ID. No other changes needed because B1 has the same source head as B.
3. Transition t2 (between B and C) updates: `leftClipId` changes from B's ID to B2's ID. The `editPointTime` remains at B's original tail position, which is now B2's tail.
4. There is no transition between B1 and B2 (it's a hard cut).

**Edge case within edge case:** If the split point falls within a transition zone (i.e., within the overlap region of t1 or t2), the split is disallowed. The user is shown a message: "Cannot split within a transition. Remove the transition first or split outside the transition zone."

### 12.7 Undo/Redo with Transitions

**Behavior:** Fully handled by the immutable `TimelineState` architecture. Each state snapshot includes the complete transition map. Undo/redo swaps the entire state including transitions. No special handling needed.

### 12.8 Transition Between Different Resolutions

**Scenario:** Clip A is 1080p, Clip B is 4K.

**Behavior:** The transition renderer (both preview and export) scales both frames to the composition's render size before blending. During preview, both frames are decoded at the preview resolution. During export, both frames are scaled to the export resolution via `CIAffineTransform` before the transition filter is applied.

### 12.9 Transition Between Different Frame Rates

**Scenario:** Clip A is 24fps, Clip B is 60fps.

**Behavior:** The composition uses a single output frame rate (determined by project settings or the first clip's frame rate). Both clips are resampled to the output frame rate by AVFoundation during composition. The transition operates on resampled frames and is unaffected by source frame rate differences.

### 12.10 Copy/Paste Clips with Transitions

**Scenario:** User copies Clip B (which has transitions on both sides) and pastes it elsewhere.

**Behavior:** The clip is pasted WITHOUT its transitions. Transitions are properties of cut points (pairs of adjacent clips), not of individual clips. The pasted clip gets hard cuts on both sides. The user may add new transitions at the paste location.

### 12.11 Reorder Clips with Transitions

**Scenario:** User drags Clip B to a new position. Clip B has transitions on both sides.

**Behavior:**
1. Both transitions on Clip B are removed before the move.
2. Clip B is moved to its new position.
3. The clips that were adjacent to Clip B (Clip A and Clip C) now have a hard cut between them.
4. User may add new transitions at all three new cut points (A-C, new-left-B, B-new-right).

### 12.12 Handles Exhausted After Trim

**Scenario:** Clip A had 2 seconds of handle. User adds a 1-second transition (uses 0.5s of handle). Then user trims Clip A's tail inward, reducing the available handle.

**Behavior:** When trimming reduces the available handle below the transition's overlap requirement:
1. The transition duration is automatically reduced to fit the available handle.
2. If the handle drops to zero, the transition is removed entirely.
3. The user sees real-time feedback during the trim: the transition zone visually shrinks as they trim.

---

## 13. Performance

### 13.1 Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Add transition | < 1ms | Map insertion + timeline state swap |
| Remove transition | < 1ms | Map removal + state swap |
| Update transition | < 1ms | Map update + state swap |
| Detect transition zone | < 1us | O(1) hash map lookup by clip ID |
| Calculate progress | < 1us | Simple arithmetic |
| Render transition (cached) | < 10ms | Dual frame fetch + GPU shader |
| Render transition (uncached) | < 33ms | Dual decode + shader (target 30fps min) |
| Composition build | < 50ms overhead | Additional track + instructions |
| Export render per frame | < 16ms | CIFilter pipeline on GPU |

### 13.2 Memory Impact

| Resource | Size | Notes |
|----------|------|-------|
| ClipTransition object | ~200 bytes | ID strings + enums + parameters |
| Transition map (50 transitions) | ~10 KB | Immutable map with structural sharing |
| Shader programs (compiled) | ~50 KB each | Compiled once, cached by Flutter engine |
| Dual frame buffers (preview) | ~16 MB | 2x 1080p BGRA frames |
| Transition preview textures | ~8 MB | Browser animated thumbnails (80x60 x 20 types) |

### 13.3 Frame Cache Strategy During Transitions

The FrameCache prefetch algorithm is enhanced for transitions:

```dart
/// When playhead approaches a transition zone, prefetch both A and B frames.
void prefetchForTransition(ClipTransition transition) {
  final transStart = transition.startTime;
  final transEnd = transition.endTime;

  // Prefetch outgoing clip frames for entire transition zone
  prefetchRange(outgoingClipAssetId, transStart, transEnd);

  // Prefetch incoming clip frames for entire transition zone
  prefetchRange(incomingClipAssetId, transStart, transEnd);
}
```

This doubles the cache pressure during transitions (two frames per time position instead of one). The cache automatically handles this via LRU eviction.

### 13.4 Shader Compilation

Fragment shaders are compiled on first use, which can cause a brief stutter (~50-100ms). Mitigation:

1. **Warm-up at app launch:** Pre-compile all transition shaders on a background thread during the splash screen.
2. **Lazy compilation fallback:** If warm-up is incomplete, compile on first use and show a dissolve placeholder for the first frame.
3. **Shader caching:** Flutter's shader compiler caches compiled programs between sessions via `SkSL`.

### 13.5 Export Performance

During export, the TransitionCompositor renders at the export resolution (up to 4K). Performance considerations:

- CIFilter pipeline runs on GPU (Metal).
- Frame delivery is asynchronous via `AVAsynchronousVideoCompositionRequest`.
- The compositor renders one frame at a time; no parallel frame rendering.
- Expected throughput: ~30fps at 1080p, ~15fps at 4K. This is acceptable for non-real-time export.
- For page curl and blur, export may be slower. Users see progress via the existing export progress bar.

---

## 14. Dependencies

### 14.1 New Flutter Packages

| Package | Purpose | Version | Notes |
|---------|---------|---------|-------|
| None required | Fragment shaders use `dart:ui` FragmentProgram | - | Built into Flutter |

The transition system requires no new Flutter packages. All rendering uses built-in capabilities:
- `dart:ui` `FragmentProgram` for shader-based preview rendering.
- Existing `CustomPainter` for timeline visualization.
- Existing Cupertino widgets for browser UI.

### 14.2 New Native Code (Swift)

| File | Purpose |
|------|---------|
| `ios/Runner/Timeline/TransitionCompositor.swift` | `AVVideoCompositing` implementation |
| `ios/Runner/Timeline/TransitionInstruction.swift` | `AVVideoCompositionInstructionProtocol` |
| `ios/Runner/Timeline/TransitionFilters.swift` | CIKernel-based custom filters for wipe/iris/clock |

### 14.3 Existing Code Modifications

| File | Change |
|------|--------|
| `lib/timeline/data/models/transition.dart` | Extend `TransitionType` enum with new types |
| `lib/core/timeline_manager.dart` | Wrap `PersistentTimeline` in `TimelineState` with transition map |
| `lib/core/composition_manager.dart` | Include transition metadata in composition build call |
| `lib/timeline/rendering/painters/clip_painter.dart` | Render transition overlap indicators |
| `ios/Runner/Timeline/CompositionBuilder.swift` | Dual-track composition with transition instructions |
| `ios/Runner/Timeline/CompositionManagerService.swift` | Forward transition data to builder |
| `lib/core/frame_cache.dart` | Enhanced prefetch for transition zones |
| `lib/core/playback_engine_controller.dart` | Dual-frame rendering during transitions |
| `lib/timeline/data/models/edit_operations.dart` | Add `cutPoint` hit type |

### 14.4 New Dart Files

| File | Purpose |
|------|---------|
| `lib/core/transition_controller.dart` | Central transition operations manager |
| `lib/timeline/rendering/transition_renderer.dart` | Flutter-side shader-based preview renderer |
| `lib/timeline/rendering/painters/transition_painter.dart` | Timeline transition visualization |
| `lib/views/transition/transition_browser_view.dart` | Transition browser sheet UI |
| `lib/views/transition/transition_preview_widget.dart` | Animated transition preview in browser |
| `lib/views/transition/transition_inspector_view.dart` | Selected transition properties panel |
| `lib/shaders/transitions/*.frag` | Fragment shaders (11 files) |

### 14.5 New Test Files

| File | Purpose |
|------|---------|
| `test/core/transition_controller_test.dart` | Transition operations, validation, edge cases |
| `test/models/transition_test.dart` | ClipTransition model, serialization, computed properties |
| `test/timeline/transition_integration_test.dart` | Timeline operations with transitions (split, trim, delete) |

---

## 15. Implementation Plan

### Phase 1: Foundation (Estimated: 3-4 days)

**Goal:** Core data models and timeline integration. No UI yet.

1. **Extend `TransitionType` enum** with all new types and properties.
   - File: `lib/timeline/data/models/transition.dart`
   - Add `TransitionCategory`, extended `TransitionTypeExtension`.

2. **Create `TimelineState` wrapper.**
   - New immutable class holding `PersistentTimeline` + transition map.
   - Transition lookup indexes (leftClip -> transition, rightClip -> transition).

3. **Update `TimelineManager`** to use `TimelineState`.
   - Undo/redo stacks hold `TimelineState` instead of bare `PersistentTimeline`.
   - Add transition mutation methods (add, remove, update).
   - Ensure all existing operations (split, trim, delete, reorder) correctly propagate transition changes.

4. **Create `TransitionController`.**
   - File: `lib/core/transition_controller.dart`
   - Validation logic (handle checking, duration clamping).
   - All transition CRUD operations.

5. **Write unit tests.**
   - Transition model tests (creation, serialization, computed properties).
   - TransitionController tests (add, remove, validation).
   - Timeline integration tests (split with transitions, delete with transitions, undo/redo).

**Deliverables:** All transition logic works without UI. Tests pass. `flutter analyze` clean.

### Phase 2: Preview Rendering (Estimated: 3-4 days)

**Goal:** Transitions render during preview playback.

1. **Write fragment shaders** for all transition types.
   - Start with dissolve (simplest), then wipe, slide, zoom, special.
   - Test each shader independently.

2. **Create `TransitionRenderer`.**
   - Fragment shader loading and compilation.
   - Uniform binding for each transition type.
   - Dual-frame texture upload.

3. **Update `PlaybackEngineController`.**
   - Detect transition zones during playback.
   - Request dual frames from FrameCache.
   - Route through TransitionRenderer.

4. **Update `FrameCache` prefetch.**
   - Transition-aware prefetch that loads both A and B frames.

5. **Performance testing.**
   - Verify 60 FPS during transitions on target devices.
   - Profile shader compilation time.
   - Implement warm-up if needed.

**Deliverables:** Transitions render in the preview viewport during playback and scrubbing.

### Phase 3: Timeline UI (Estimated: 2-3 days)

**Goal:** Transitions are visible and interactive on the timeline.

1. **Create `TransitionPainter`.**
   - Visual indicator (bowtie/diamond shape) at cut points.
   - Type icon, duration label.
   - Selection highlight and drag handles.

2. **Extend hit testing** in timeline gesture handler.
   - Detect taps on cut points (for adding transitions).
   - Detect taps on existing transitions (for selection).
   - Handle drag on transition edges (for duration adjustment).

3. **Transition add workflow.**
   - Tap cut point -> show quick transition picker (CupertinoActionSheet).
   - Apply default transition type and duration.

4. **Transition select/modify workflow.**
   - Tap transition -> select it.
   - Show duration handles.
   - Drag to resize.
   - Tap again -> open Transition Browser for type change.

5. **Transition delete workflow.**
   - Select transition -> delete button or swipe gesture.
   - Confirmation dialog.

**Deliverables:** Users can add, select, modify duration, change type, and delete transitions directly on the timeline.

### Phase 4: Transition Browser (Estimated: 2-3 days)

**Goal:** Full transition browser with animated previews.

1. **Create `TransitionBrowserView`.**
   - Bottom sheet with Liquid Glass background.
   - Category tabs (CNTabBar).
   - Transition grid with animated previews.
   - Search bar.
   - Duration slider.
   - Apply button.

2. **Create `TransitionPreviewWidget`.**
   - Animated thumbnail showing the transition effect.
   - Looping animation using TransitionRenderer.
   - Placeholder gradients when clip frames are unavailable.

3. **Implement Favorites.**
   - Favorite toggle on each transition.
   - Persistence to SharedPreferences.
   - Favorites tab in browser.

**Deliverables:** Full Transition Browser with previews and favorites.

### Phase 5: Export Integration (Estimated: 3-4 days)

**Goal:** Transitions render correctly during export.

1. **Create `TransitionCompositor.swift`.**
   - `AVVideoCompositing` protocol implementation.
   - CIContext setup for GPU rendering.
   - Frame request handling.

2. **Create `TransitionInstruction.swift`.**
   - `AVVideoCompositionInstructionProtocol` implementation.
   - Carries transition type, parameters, track IDs.

3. **Create `TransitionFilters.swift`.**
   - Custom `CIKernel` implementations for wipe, iris, clock.
   - CIFilter wrappers for slide, zoom, rotation.

4. **Update `CompositionBuilder.swift`.**
   - Dual video track support.
   - Overlapping segment insertion during transitions.
   - TransitionInstruction generation.
   - Audio crossfade via AVMutableAudioMix.

5. **Update `CompositionManager.dart`.**
   - Include transition data in native composition build call.
   - Handle transition metadata in segment building.

6. **Export testing.**
   - Test each transition type in exported video.
   - Verify frame-accurate timing.
   - Verify audio crossfade.
   - Test with various resolutions and frame rates.

**Deliverables:** Exported videos contain correct transitions with audio crossfade.

### Phase 6: Audio Crossfade (Estimated: 1-2 days)

**Goal:** Audio crossfade works correctly during preview and export.

1. **Implement audio crossfade in preview.**
   - Apply volume envelope to outgoing clip audio.
   - Apply volume envelope to incoming clip audio.
   - Three modes: linear, equal power, S-curve.

2. **Implement audio crossfade toggle.**
   - Parameter in ClipTransition to enable/disable.
   - UI toggle in transition inspector.

3. **Update export audio mix.**
   - Volume ramp parameters in AVMutableAudioMix.
   - Correct crossfade curve application.

**Deliverables:** Audio crossfades smoothly during transitions in both preview and export.

### Phase 7: Polish and Testing (Estimated: 2-3 days)

**Goal:** Production readiness.

1. **Edge case testing.**
   - All scenarios from Section 12.
   - Stress testing with many transitions.
   - Memory pressure testing.

2. **Performance optimization.**
   - Profile and optimize any bottlenecks.
   - Shader warm-up at launch.
   - Ensure < 200MB memory budget is maintained.

3. **Documentation updates.**
   - Update `docs/DESIGN.md` with transition architecture.
   - Update `docs/FEATURES.md` with transition feature status.
   - Update `docs/APP_LOGIC.md` with transition flow.

4. **Codebase analysis.**
   - Run analysis on all new/modified files.
   - Update `analysis/INDEX.md`.

**Deliverables:** Ship-ready transitions system.

### File Structure (Complete)

```
lib/
  core/
    transition_controller.dart          # Transition operations manager
  timeline/
    data/
      models/
        transition.dart                 # Extended with new types (existing file)
    rendering/
      transition_renderer.dart          # Shader-based preview renderer
      painters/
        transition_painter.dart         # Timeline transition visualization
  views/
    transition/
      transition_browser_view.dart      # Transition browser sheet
      transition_preview_widget.dart    # Animated preview thumbnails
      transition_inspector_view.dart    # Selected transition properties
  shaders/
    transitions/
      dissolve.frag
      dip_to_color.frag
      wipe_directional.frag
      wipe_clock.frag
      wipe_iris.frag
      slide.frag
      zoom.frag
      blur.frag
      rotation.frag
      page_curl.frag

ios/Runner/Timeline/
  TransitionCompositor.swift            # AVVideoCompositing implementation
  TransitionInstruction.swift           # Custom composition instruction
  TransitionFilters.swift               # CIKernel-based custom filters

test/
  core/
    transition_controller_test.dart     # Transition operations + validation
  models/
    transition_test.dart                # Model tests + serialization
  timeline/
    transition_integration_test.dart    # Timeline ops with transitions
```

### Total Estimated Timeline: 16-23 days

---

**Last Updated:** 2026-02-06

**Next Steps:** Review design with team, begin Phase 1 implementation.

---

## Review 1 - Architecture & Completeness

**Reviewer:** Architecture Review (Round 1 of 3)
**Date:** 2026-02-06
**Scope:** Architecture, data model, codebase alignment, completeness, edge cases, performance

---

### CRITICAL Issues (Must fix before implementation)

#### C1. Two Divergent Timeline Systems -- Design Document Conflates V1 and V2 Models

The design document references both the V1 timeline model (`TimelineClip` in `lib/timeline/data/models/timeline_clip.dart`, used by `ClipManager`) and the V2 timeline model (`TimelineItem`/`VideoClip`/`MediaClip` in `lib/models/clips/`, used by `TimelineManager` and `PersistentTimeline`). The document is ambiguous about which system transitions integrate with.

**Evidence:**
- Section 4.5 handle validation references `TimelineItem`, `GapClip`, and `MediaClip` with `leftClip.sourceOutMicros` -- these are V2 classes.
- Section 5.4 says "The existing `ClipManager` operates on the legacy timeline model. The transition system integrates with the V2 `TimelineManager` instead." Good, but the document also references V1 models:
  - Section 8.2 `TransitionPainter` takes `List<TimelineClip>` (V1 model from `timeline_clip.dart`) and `List<Track>`.
  - Section 8.3 references `HitTestResult` from `edit_operations.dart` which uses `TimelineClip` (V1).
- `TimelineManager` (V2) currently stores `PersistentTimeline` only -- there is no `TimelineState` wrapper class yet.

**Impact:** If the implementation mixes V1 and V2 types, it will create confusion, type mismatches, and bugs.

**Recommendation:**
1. Explicitly declare that transitions are V2-only. All references to V1 `TimelineClip` in the design must be replaced with V2 `VideoClip`/`TimelineItem`.
2. The `TransitionPainter` should operate on V2 models or define a clear mapping/adapter layer.
3. Clarify how the UI layer (which currently uses V1 `TimelineClip` in `ClipsPainter`) will consume V2 + transition data.

---

#### C2. `TimelineState` Wrapper Does Not Exist -- Undo/Redo Architecture Gap

The design proposes a `TimelineState` immutable class wrapping `PersistentTimeline` + transition maps (Section 4.1). Currently, `TimelineManager._current` is a `PersistentTimeline` directly, and the undo/redo stacks store `PersistentTimeline` references.

**Impact:** The undo/redo stacks currently store `PersistentTimeline`. Changing `_current` to `TimelineState` requires:
- Modifying every method on `TimelineManager` (30+ methods) to work with `TimelineState` instead of `PersistentTimeline`.
- Every consumer of `timelineManager.timeline` (e.g., `PlaybackEngineController._rebuildComposition`, `ScrubController`, `CompositionManager.buildComposition`) must be updated.
- The `_execute` method's closure signature changes.

The design acknowledges this change is needed but underestimates the scope.

**Recommendation:**
1. Add a detailed migration plan as a sub-step of Phase 1, listing every consumer of `TimelineManager.timeline` and how each changes.
2. Consider an alternative: keep `PersistentTimeline` as-is and add a parallel `TransitionMap` stored separately in `TimelineManager` with its own undo stack (less elegant but lower risk). Document the tradeoff and make a decision.
3. If proceeding with `TimelineState`, ensure all existing tests for `TimelineManager` continue to pass after the refactor.

---

#### C3. Time Mapping Functions Are Incorrect for Non-CenterOnCut Alignments and Multiple Transitions

Section 4.4 `presentationToEditorial` and `editorialToPresentation` assume each transition's overlap equals `transition.duration`. This is only true for `centerOnCut` alignment.

**Evidence from codebase:** `ClipTransition.leftOverlapRequired` and `rightOverlapRequired` differ by alignment:
- `startAtCut`: left overlap = 0, right overlap = duration (total overlap for timeline shortening is still `duration` for `centerOnCut`, but the effective overlap that shortens the timeline depends on alignment).

Actually, re-examining: for all alignment modes, the total overlap (timeline shortening) IS the full `transition.duration` because the overlap region is always `duration` long regardless of which side contributes more. However, the functions have a more fundamental problem:

The loop iterates over `sortedTransitions` comparing `transition.editPointTime <= editorialTime`, but `editorialTime` is being *modified* within the loop by adding `transition.duration`. This means the comparison condition changes mid-loop. For multiple transitions, this creates incorrect results because after adding overlap for transition 1, the effective `editorialTime` shifts, potentially causing transition 2's comparison to produce wrong results.

**Recommendation:**
1. The time mapping must be rewritten with careful attention to the accumulator pattern. The loop should compare against *presentation* time (which is stable), not the accumulating *editorial* time.
2. Add unit tests for time mapping with: (a) no transitions, (b) single transition, (c) multiple transitions, (d) different alignments, (e) time position inside a transition zone.
3. Consider caching a sorted "transition timeline offset table" for O(log n) binary search instead of O(n) linear scan per query.

---

#### C4. `CompositionBuilder.swift` Currently Uses Single Video Track -- Fundamental Architectural Change Required

The design (Section 7.5) requires dual video tracks for transitions. The current `CompositionBuilder.swift` creates exactly one `AVMutableCompositionTrack` for video. The design states this is "already supported by AVFoundation" but does not detail the specific changes needed.

**Impact:** This is not a trivial extension. The A/B track model requires:
- Alternating clip insertion between track A and track B so that during transitions, both tracks have active segments.
- The track assignment logic must consider which clips have transitions on their boundaries and which do not.
- The `buildVideoComposition()` method currently creates a single `AVMutableVideoCompositionInstruction` for the entire composition. With transitions, you need multiple instructions: passthrough instructions for non-transition segments and custom `TransitionInstruction` for overlap segments.
- Each `TransitionInstruction` must reference the track IDs of both tracks so the compositor can request both source frames.

**Recommendation:**
1. Add a detailed subsection to Section 7.5 explaining the A/B track interleaving algorithm. Standard approach: even-indexed clips go on track A, odd-indexed go on track B. Clips without transitions can go on either track. Only during the overlap period do both tracks need active segments.
2. Show a concrete example of instruction timing for a 3-clip timeline with 2 transitions.
3. Note that `AVMutableCompositionTrack.insertTimeRange` does not allow overlapping time ranges on the same track -- this is why two tracks are mandatory.

---

#### C5. CompositionManager.dart Does Not Pass Transition Data to Native Side

The current `CompositionManager._buildSegment()` method builds a simple `Map<String, dynamic>` per `TimelineItem` with no transition metadata. The design says (Section 5.4) that `CompositionManager` is "extended to include transition metadata in the native call," but does not specify the protocol channel format.

**Impact:** The platform channel contract between Dart and Swift must be specified. Without it, Phase 5 cannot be implemented.

**Recommendation:**
1. Define the exact JSON structure for the `buildComposition` platform channel call, including:
   - The segment list (already exists).
   - A new `transitions` list, each entry containing: transition type, direction, duration, parameters, left clip asset ID, right clip asset ID, edit point time, easing curve name.
2. Define how the native side maps transition metadata to `TransitionInstruction` objects.
3. Consider whether transitions should be embedded inline between segments or passed as a separate top-level array. The separate array approach is cleaner.

---

### IMPORTANT Issues (Should fix, significant impact)

#### I1. Fragment Shader Texture Upload Strategy Not Specified

Section 6.6 says "Upload both frames as textures to the shader" but does not specify how. Flutter's `FragmentProgram` supports `sampler2D` uniforms, but the mechanism for uploading raw `Uint8List` BGRA pixel data as textures is non-trivial.

**Options:**
1. Convert `CachedFrame.pixels` to `dart:ui.Image` via `decodeImageFromPixels`, then bind as sampler.
2. Use `ImageShader` to wrap each frame.
3. Create a `FragmentShader` and set image uniforms.

The conversion from `Uint8List` to `dart:ui.Image` has significant overhead (~2-5ms per frame at 1080p). With two frames per transition frame, this adds 4-10ms, cutting into the 16.6ms frame budget significantly.

**Recommendation:**
1. Specify the exact texture upload mechanism.
2. Profile `decodeImageFromPixels` for 1080p BGRA on target devices.
3. Consider keeping decoded frames as `dart:ui.Image` in the cache instead of raw `Uint8List` to avoid conversion overhead. This would require changes to `CachedFrame` and the decoder pool.
4. Alternative: render transitions using a `CustomPainter` with `canvas.drawImageRect` and blend modes instead of fragment shaders. This avoids the texture upload problem entirely for simpler transitions (dissolve, fade). Reserve shaders for complex transitions (wipe, page curl).

---

#### I2. `VolumeEnvelope` Merge Strategy for Audio Crossfade Is Unspecified

Section 10.4 says "These envelopes are merged with any existing volume keyframes on the clips." The `VolumeEnvelope` class supports `addKeyframe` but has no merge/compose method. If a clip already has volume keyframes (e.g., a manual fade-out), how does the transition's crossfade interact?

**Options:**
1. **Multiply:** transition_volume * existing_volume. This preserves manual volume automation.
2. **Replace:** transition overwrites existing keyframes in the transition zone.
3. **Additive:** sum, clamped to 0-1.

**Recommendation:**
1. Specify the merge strategy (multiply is industry standard).
2. Add a `VolumeEnvelope.compose(VolumeEnvelope other)` method.
3. Document how the composed envelope is converted to `AVMutableAudioMixInputParameters` volume ramps (which are linear segments -- complex curves may need to be approximated as multiple linear ramps).

---

#### I3. `ScrubController` Has No Awareness of Transitions

The `ScrubController` currently resolves a single clip and asset at each timeline position. During transitions, it must resolve TWO clips/assets. The current `scrubTo` method flow is:

1. Look up item at time via `PersistentTimeline.itemAtTime(timeMicros)` -- returns a single item.
2. Determine asset ID from that item.
3. Request frame from `FrameCache` or `DecoderPool`.

This produces only one frame. During a transition zone, it must produce frames from both the outgoing and incoming clips.

**Recommendation:**
1. Add a method to the scrub pipeline: `itemsAtTime(timeMicros)` that returns both clips when in a transition zone.
2. Alternatively, introduce a `TransitionFrameResolver` that sits between the `ScrubController` and `FrameCache`, detecting transition zones and requesting dual frames.
3. Define how the two frames are composited before display -- presumably the `TransitionRenderer` shader is invoked.

---

#### I4. Design References `TransitionAlignment` But Codebase Only Implements `centerOnCut` Logic

The `ClipTransition.timeRange` computed property correctly handles all three alignments. However, the handle validation (Section 4.5) only shows the `centerOnCut` formula: `leftAvailableHandle < requiredLeftOverlap`. For `startAtCut`, `leftOverlapRequired` is 0, meaning the left clip needs no handle at all -- this is correct but means the validation asymmetry should be explicitly tested.

More importantly, the `startAtCut` alignment means the transition occurs AFTER the edit point, meaning the transition visually sits entirely within clip B's territory. The timeline duration impact formula `overlapAmount = transition.duration` still holds (the overlap region is always `duration` long), but the visual representation on the timeline UI needs adjustment -- the bowtie shape should shift accordingly.

**Recommendation:**
1. Add alignment-specific diagrams to Section 8.1 showing how the transition indicator moves for `startAtCut` and `endAtCut`.
2. Ensure `TransitionPainter._drawTransition` uses `transition.startTime` and `transition.endTime` (which already account for alignment) rather than computing position from `editPointTime`.

---

#### I5. Backward Compatibility for Project Serialization

The design adds new `TransitionType` enum values and a new `TimelineState` wrapper. Existing saved projects have:
- `ClipTransition` objects in JSON (if any were persisted -- unclear from current code).
- `PersistentTimeline` serialized as a flat list of `TimelineItem` JSON objects.

If `TimelineState` wraps the timeline + transitions map, the project serialization format changes. Old projects won't have a `transitions` key.

**Recommendation:**
1. Ensure `TimelineState.fromJson` handles missing `transitions` key gracefully (default to empty map).
2. Add a format version number to the project file to handle future migrations.
3. Test loading existing projects with the new code.

---

#### I6. Image Clips and Color Clips as Transition Participants

Section 4.5 validation checks for `GapClip` but does not explicitly handle `ImageClip` or `ColorClip`. An `ImageClip` has no source in/out points in the traditional sense -- it has a configurable duration but the entire image is always the source. Does an `ImageClip` have "handles"?

**Analysis from codebase:** `ImageClip` extends `MediaClip` and has `sourceInMicros` and `sourceOutMicros`, but since images are static, the concept of "handles" (unused source beyond in/out) is meaningless. An image clip could theoretically extend infinitely.

**Recommendation:**
1. Define explicitly: image clips have unlimited handles (since the source frame is always the same regardless of time). This means transitions on image clips should always be allowed.
2. Handle `ColorClip` and `GapClip` explicitly: `ColorClip` has unlimited handles (generates solid color). `GapClip` should not participate in transitions (already noted).
3. Document this in Section 4.5.

---

#### I7. Speed-Changed Clips + Transitions Interaction

The V1 `TimelineClip` has a `speed` property. The V2 `VideoClip` does not appear to have a speed property (it only has `sourceInMicros` / `sourceOutMicros`). If speed changes are implemented via adjusting source in/out points (which is the V2 approach), then handle calculations remain correct. However, if speed is applied as a separate multiplier (future feature), the handle availability calculation must account for speed:

```
actualHandleDuration = rawHandleDuration / speed
```

A 2x speed clip with 1 second of raw handle only has 0.5 seconds of playback handle.

**Recommendation:**
1. Add a note in Section 12 about speed-changed clips and transitions.
2. If speed is future work, add it as a "Future Consideration" subsection.
3. Ensure the handle validation formula accounts for speed when speed is implemented.

---

#### I8. `ClipTransition.editPointTime` Is Absolute Timeline Time -- Fragile Under Edits

`editPointTime` is stored as an absolute timeline position. When clips before this transition are inserted, deleted, or trimmed, the edit point time must be recalculated. The design says transitions are side-channel metadata, meaning the tree doesn't know about them.

**Impact:** Every operation that changes clip positions (insert, delete, trim, reorder) must also scan all transitions to update their `editPointTime` values. This is O(t) where t = number of transitions, on top of every edit operation.

**Recommendation:**
1. Consider storing transitions by clip ID pair `(leftClipId, rightClipId)` and computing `editPointTime` dynamically as `startTimeOf(rightClipId)`. This eliminates the stale-time problem.
2. The `ClipTransition.editPointTime` can become a computed property: `editPointTime = timeline.startTimeOf(rightClipId)`.
3. Alternatively, recalculate all transition times in a post-edit pass. Document which approach is chosen and the performance implications.

---

### MINOR Issues (Nice to have, can defer)

#### M1. GLSL Version `#version 460` May Not Be Supported on All Target Devices

Section 6.4 shader code uses `#version 460`. Flutter's fragment shader compilation for iOS targets Metal Shading Language via SPIRV-Cross. GLSL 4.60 features may not all be supported. Flutter's documentation recommends simpler GLSL for portability.

**Recommendation:** Use `#version 320 es` (OpenGL ES 3.2) which is the standard Flutter shader target. Test compilation on the oldest supported device.

---

#### M2. `TransitionPainter` Track Lookup Uses `firstWhere` -- O(n) Per Transition

Section 8.2 `_drawTransition` uses `tracks.firstWhere((t) => t.id == transition.trackId)`. With many tracks and transitions, this is O(t*n).

**Recommendation:** Build a `Map<String, Track>` index before the paint loop, as `ClipsPainter` already does with `trackIndexMap`. The design's `TransitionPainter` should follow the same pattern.

---

#### M3. Shader Warm-up Strategy Could Cause Splash Screen Delay

Section 13.4 suggests pre-compiling all 11 shaders at app launch. Each shader compilation takes ~50-100ms, totaling up to 1.1 seconds. This exceeds the 2-second app launch budget if combined with other initialization.

**Recommendation:**
1. Warm up only the most common shaders (dissolve, wipe) at launch.
2. Compile others lazily on first use or during idle time after the first screen is displayed.
3. Use Flutter's `ShaderWarmUp` API if available.

---

#### M4. Missing `Curve` Serialization Roundtrip in Existing `ClipTransition`

The design mentions the curve serialization problem (Section 3.7) and proposes a `curveType` parameter key. However, the existing `ClipTransition.toJson()` already skips the `easing` field (line 297: `// Note: Curve cannot be serialized directly`). The `fromJson` constructor uses default `Curves.easeInOut`. The proposed fix of using `_knownCurves` mapping is good but should be applied to the existing `toJson`/`fromJson` methods, not just the `parameters` map.

**Recommendation:** Fix `ClipTransition.toJson()` to serialize the curve name, and `fromJson()` to deserialize it. This ensures round-trip fidelity for all transitions, not just those that happen to use the `parameters` map.

---

#### M5. `TransitionCategory.basic` Includes Both Dissolve and Fade Types -- May Confuse Users

"Basic" contains cross dissolve, dip, fade to black, and fade to white. Professional editors often separate "Dissolve" from "Fade/Dip" because dissolves blend A+B while fades go through an intermediate color.

**Recommendation:** Consider splitting into "Dissolve" (cross dissolve only) and "Fade" (dip, fade to black, fade to white). Low priority -- can be adjusted based on user testing.

---

#### M6. No Accessibility Considerations for Transition UI

The transition indicator on the timeline (bowtie shape, type icon, duration label) and the Transition Browser have no accessibility annotations mentioned.

**Recommendation:** Ensure transition elements have proper `Semantics` labels (e.g., "Cross dissolve transition between Clip A and Clip B, duration 0.5 seconds"). The Transition Browser grid cells should be accessible with VoiceOver.

---

### QUESTION Items (Need clarification)

#### Q1. Which Timeline System Is the Transition Target?

Is this design exclusively for the V2 `TimelineManager` + `PersistentTimeline` system? If so, how will the UI layer (which still uses V1 `TimelineClip` + `ClipsPainter`) consume transition data? Is a V1 deprecation planned before or during transitions implementation?

#### Q2. How Does the Frame Cache Key Work for Transition Composite Frames?

The design says both frames are fetched separately. But where is the composited transition frame stored? Is it cached, or recomputed every repaint? If not cached, the shader runs on every frame during playback scrubbing, which may be fine for playback but could be expensive for rapid scrubbing.

#### Q3. What Happens to the `cutPoint` HitType on Clips That Already Have a Transition?

Section 8.3 adds `HitType.cutPoint` for empty cut points. But the existing `HitType.transition` already exists. Is the hit test supposed to return `cutPoint` when there is no transition, and `transition` when there is one? This should be explicitly stated.

#### Q4. How Are Transitions Handled During Export Progress Reporting?

The current export pipeline reports progress as `segment_index / total_segments`. With dual-track interleaving and transition instructions, the progress calculation changes. Is this accounted for?

#### Q5. Can Two Adjacent Transitions Have Zero-Length Clip Between Them?

If Clip B is, say, 100ms long and both transitions consume 33ms of overlap each (within the 100ms - 33ms min = 67ms constraint), Clip B has only 34ms of "non-overlapped" presentation time. Is this a valid state? The UX of a near-invisible clip between two transitions seems problematic.

**Recommendation:** Consider a minimum "visible" clip duration between adjacent transitions (e.g., 100ms or 3 frames) that is larger than `TimelineClip.minDuration`.

#### Q6. Does `TransitionRenderer` Run on the Main Isolate?

Section 6.6 implies shader execution happens on the GPU via Flutter's rendering pipeline. Confirm that the shader invocation is part of the `CustomPainter.paint()` cycle (main isolate, GPU thread) rather than requiring a separate isolate. If it is in the paint cycle, ensure the shader uniform setup does not block the main thread.

---

### Missing Edge Cases

#### E1. Transition + Linked Audio-Video Clips

The V1 `TimelineClip` has a `linkedClipId` for A/V sync. If a video clip has a linked audio clip, does the audio clip also get a transition? Or does only the video get a visual transition while the audio always gets a crossfade? This interaction is not specified.

#### E2. Transition on the Last Frame of a Clip

If a clip has exactly `minDuration` (33333us) of handle, a transition can be created with duration = 66666us (2 frames). What does a 2-frame transition look like? The design mentions `ClipTransition.minDuration = 66666`, which is already 2 frames at 30fps. For 60fps content, this is only 4 frames -- still very short but potentially useful for a snap cut effect.

#### E3. Transition + Undo After Export

If the user exports with transitions, then undoes (which removes transitions from the `TimelineState`), the exported file still has transitions. This is fine -- but if the user then re-exports, the new export should NOT have transitions. Ensure that the composition build is always triggered from the current `TimelineState`, not a cached version.

#### E4. Multiple Transitions Becoming Invalid Simultaneously

If the user performs a single operation that invalidates multiple transitions (e.g., deleting a clip that has transitions on both sides), both transitions must be removed atomically in a single undo operation. Ensure the undo mechanism captures this as one step.

#### E5. Transition During Looping Playback

When looping is enabled and the playhead reaches the end of the timeline, it jumps back to the start. If there is a transition at the very end of the timeline (between the last two clips), the loop point may fall within the transition zone. The playback engine must handle this gracefully -- it should complete the transition before looping, or loop immediately and abandon the partial transition.

---

### Missing Performance Considerations

#### P1. Double Memory Pressure from Dual-Frame Prefetching

Section 13.3 acknowledges doubled cache pressure during transitions. With the current 300MB cache limit and 120-frame max, adding transition prefetching could easily exceed limits. If a timeline has 5 transitions and the user scrubs across all of them, the cache must hold frames for 10 clips simultaneously.

**Recommendation:** Add a transition-aware cache eviction policy that prioritizes evicting frames for clips that are far from the current playhead and not part of any nearby transition. The current LRU is asset-unaware.

#### P2. `sortedTransitions` in Time Mapping Is Recomputed on Every Call

Section 4.4 references `sortedTransitions` but the `TimelineState.transitions` map is keyed by ID, not sorted by time. Every call to `presentationToEditorial` or `editorialToPresentation` must sort transitions by time first.

**Recommendation:** Maintain a pre-sorted list (or use `SplayTreeMap<TimeMicros, ClipTransition>`) in `TimelineState` for O(log n) range queries instead of sorting on every call.

#### P3. Composition Rebuild After Transition Add/Remove

Adding or removing a transition triggers `_compositionDirty = true` and a full composition rebuild. The rebuild iterates all segments and calls native. For large timelines (50+ clips), this could take 50ms+ (per Section 13.1). During rapid transition editing (e.g., adjusting duration via drag), this means a rebuild per drag frame.

**Recommendation:** Debounce composition rebuilds during interactive transition edits. Only trigger rebuild on drag end, not during drag. During drag, update only the Flutter-side preview (which uses shaders and does not need the native composition).

---

### Summary

| Category | Count |
|----------|-------|
| CRITICAL | 5 |
| IMPORTANT | 8 |
| MINOR | 6 |
| QUESTION | 6 |
| Missing Edge Cases | 5 |
| Missing Performance | 3 |

**Overall Assessment:** The design is thorough and well-structured, with excellent coverage of transition theory, audio handling, and the built-in catalog. The fundamental architecture decision (side-channel metadata, not tree nodes) is correct and matches industry practice.

The primary risk areas are:
1. **V1/V2 model confusion** -- must be resolved before Phase 1.
2. **`TimelineState` migration** -- high-impact refactor of `TimelineManager`.
3. **CompositionBuilder dual-track changes** -- complex Swift work needs more specification.
4. **Stale `editPointTime`** -- fragile under edits, consider computing dynamically.
5. **Shader texture upload performance** -- the `Uint8List` -> `Image` conversion path needs profiling.

**Recommendation:** Resolve all 5 CRITICAL issues before beginning Phase 1. The IMPORTANT issues should be addressed during implementation. MINOR issues can be deferred to Phase 7 (Polish).

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Implementation Viability Review (Round 2 of 3)
**Date:** 2026-02-06
**Scope:** Validate Review 1 criticals, propose concrete solutions, shader feasibility, memory impact, test strategy

---

### 1. Resolution for Each Review 1 Critical

#### C1 Resolution: V1/V2 Model Confusion -- Transitions Use V2 Exclusively

**Verdict: CONFIRMED CRITICAL.** The codebase has two fully distinct model hierarchies and the design document does mix references. However, the migration scope is smaller than it first appears.

**Analysis of the two systems:**

| Aspect | V1 (`TimelineClip`) | V2 (`TimelineItem`/`VideoClip`) |
|--------|---------------------|-------------------------------|
| File | `lib/timeline/data/models/timeline_clip.dart` | `lib/models/clips/timeline_item.dart` + subtypes |
| Used by | `ClipManager`, `ClipsPainter`, `EditOperations` (UI rendering layer) | `TimelineManager`, `PersistentTimeline`, `CompositionManager` (data/engine layer) |
| Has track ID | Yes (`trackId` field) | No (single-track assumed in V2 tree) |
| Has speed | Yes (`speed` field) | No (speed encoded in source in/out) |
| Has startTime | Yes (absolute timeline position) | No (position is implicit from tree order) |
| Mutable | Effectively yes (copyWith returns new) | Immutable (copyWith returns new) |

**Concrete Solution:**

Transitions MUST be V2-only. The `ClipTransition` model already references `leftClipId` / `rightClipId` which are string IDs that can reference either system. The rule is:

1. **`ClipTransition.leftClipId` and `rightClipId` reference V2 `TimelineItem.id` values** (the IDs stored in `PersistentTimeline` nodes).
2. **`TransitionController` operates exclusively on `TimelineManager`** (V2). It never imports or references `TimelineClip`.
3. **`TransitionPainter`** (Section 8.2 of the design) must NOT take `List<TimelineClip>`. Instead, it takes a `TransitionRenderData` adapter that maps V2 items to pixel positions. The adapter bridges V2 data to the rendering layer.

**Adapter pattern for UI layer:**

```dart
/// Bridges V2 timeline data to the rendering layer.
/// Built once per frame, consumed by both ClipsPainter and TransitionPainter.
@immutable
class TimelineRenderData {
  /// V2 items with computed absolute start times.
  final List<({TimelineItem item, int startTimeMicros})> items;

  /// Transitions with precomputed pixel positions.
  final List<({ClipTransition transition, double startX, double widthPx})> transitions;

  /// Build from TimelineState + viewport.
  factory TimelineRenderData.from(TimelineState state, ViewportState viewport) {
    final itemList = <({TimelineItem item, int startTimeMicros})>[];
    int accumulated = 0;
    for (final item in state.timeline.items) {
      itemList.add((item: item, startTimeMicros: accumulated));
      accumulated += item.durationMicroseconds;
    }

    final transList = <({ClipTransition transition, double startX, double widthPx})>[];
    for (final t in state.transitions.values) {
      final startX = viewport.timeToPixelX(t.startTime);
      final widthPx = t.duration / viewport.microsPerPixel;
      transList.add((transition: t, startX: startX, widthPx: widthPx));
    }

    return TimelineRenderData._(itemList, transList);
  }
}
```

This approach means `ClipsPainter` can be gradually migrated to V2 data via this adapter, without requiring all V1 code to be rewritten before transitions ship.

**`ClipTransition.trackId` field:** The V2 `PersistentTimeline` is currently single-track. The `trackId` field on `ClipTransition` should default to a sentinel value `'main'` until multi-track is implemented. This field remains for forward compatibility but is not used for V1 routing.

**Action items:**
- Remove `List<TimelineClip>` and `List<Track>` parameters from `TransitionPainter` in Section 8.2.
- Replace with `TimelineRenderData` adapter.
- Add explicit note at the top of Section 4: "All clip IDs in this document refer to V2 `TimelineItem.id` values from `PersistentTimeline`."

---

#### C2 Resolution: TimelineState Migration -- Incremental Wrapper Approach

**Verdict: CONFIRMED CRITICAL but the scope is manageable.** After auditing the codebase, `TimelineManager` has exactly 3 external consumers of `.timeline`:

1. `PlaybackEngineController._rebuildComposition()` -- passes `_timelineManager.timeline` to `CompositionManager.buildComposition()`.
2. `PlaybackEngineController._onTimelineChanged()` -- passes `_timelineManager.timeline` to `_scrubController.updateTimeline()`.
3. `PlaybackEngineController` constructor -- passes `.timeline` for initial scrub state.

These are NOT 30+ call sites. The `TimelineManager` class itself has ~20 methods, but they are internal mutations that call `_execute()` -- they do not need to change signature, only internal implementation.

**Concrete Solution: Two-Phase Incremental Migration**

**Phase A (non-breaking):** Add `TimelineState` alongside `PersistentTimeline` without changing the public API.

```dart
@immutable
class TimelineState {
  final PersistentTimeline timeline;
  final Map<String, ClipTransition> transitions;
  final Map<String, String> leftClipToTransition;   // leftClipId -> transitionId
  final Map<String, String> rightClipToTransition;  // rightClipId -> transitionId

  const TimelineState({
    required this.timeline,
    this.transitions = const {},
    this.leftClipToTransition = const {},
    this.rightClipToTransition = const {},
  });

  static const TimelineState empty = TimelineState(
    timeline: PersistentTimeline.empty,
  );

  // === Transition mutations (return new TimelineState) ===

  TimelineState addTransition(ClipTransition transition) {
    final newTransitions = Map<String, ClipTransition>.from(transitions)
      ..[transition.id] = transition;
    final newLeft = Map<String, String>.from(leftClipToTransition)
      ..[transition.leftClipId] = transition.id;
    final newRight = Map<String, String>.from(rightClipToTransition)
      ..[transition.rightClipId] = transition.id;
    return TimelineState(
      timeline: timeline,
      transitions: newTransitions,
      leftClipToTransition: newLeft,
      rightClipToTransition: newRight,
    );
  }

  TimelineState removeTransition(String transitionId) {
    final transition = transitions[transitionId];
    if (transition == null) return this;
    final newTransitions = Map<String, ClipTransition>.from(transitions)
      ..remove(transitionId);
    final newLeft = Map<String, String>.from(leftClipToTransition)
      ..remove(transition.leftClipId);
    final newRight = Map<String, String>.from(rightClipToTransition)
      ..remove(transition.rightClipId);
    return TimelineState(
      timeline: timeline,
      transitions: newTransitions,
      leftClipToTransition: newLeft,
      rightClipToTransition: newRight,
    );
  }

  /// Wrap a PersistentTimeline mutation, preserving transitions.
  TimelineState withTimeline(PersistentTimeline newTimeline) {
    return TimelineState(
      timeline: newTimeline,
      transitions: transitions,
      leftClipToTransition: leftClipToTransition,
      rightClipToTransition: rightClipToTransition,
    );
  }

  /// Effective duration accounting for transition overlaps.
  int get effectiveDurationMicros {
    int totalOverlap = 0;
    for (final t in transitions.values) {
      totalOverlap += t.duration;
    }
    return timeline.totalDurationMicros - totalOverlap;
  }
}
```

**Phase B (migration):** Update `TimelineManager` internals.

```dart
class TimelineManager extends ChangeNotifier {
  TimelineState _current;  // Changed from PersistentTimeline

  final List<TimelineState> _undoStack = [];  // Changed
  final List<TimelineState> _redoStack = [];  // Changed

  TimelineManager() : _current = TimelineState.empty;

  // --- Backward-compatible getters (NO breaking changes) ---

  /// Current timeline tree. Preserved for existing consumers.
  PersistentTimeline get timeline => _current.timeline;

  /// Current full state including transitions.
  TimelineState get state => _current;

  /// Total duration accounting for transitions.
  int get totalDurationMicros => _current.effectiveDurationMicros;

  // --- _execute changes ---

  void _execute(
    TimelineState Function() mutation, {
    String? operationName,
  }) {
    _undoStack.add(_current);
    if (_undoStack.length > maxUndoHistory) _undoStack.removeAt(0);
    _redoStack.clear();
    _current = mutation();
    _compositionDirty = true;
    _lastOperationName = operationName;
    notifyListeners();
  }

  // --- Existing methods wrap timeline mutations in TimelineState ---

  void append(TimelineItem item) {
    _execute(
      () => _current.withTimeline(_current.timeline.append(item)),
      operationName: 'Add ${item.displayName}',
    );
  }

  // ... same pattern for insertAt, prepend, remove, updateItem, etc.
  // Each wraps the PersistentTimeline mutation in withTimeline().

  // --- NEW: Transition operations ---

  void addTransition(ClipTransition transition) {
    _execute(
      () => _current.addTransition(transition),
      operationName: 'Add ${transition.type.displayName}',
    );
  }

  void removeTransition(String transitionId) {
    final t = _current.transitions[transitionId];
    _execute(
      () => _current.removeTransition(transitionId),
      operationName: 'Remove ${t?.type.displayName ?? "transition"}',
    );
  }
}
```

**Key insight:** Because `.timeline` getter is preserved, the 3 external consumers (`PlaybackEngineController`) continue to work without changes during Phase A. In Phase B, `CompositionManager.buildComposition` is updated to accept `TimelineState` instead of `PersistentTimeline` so it can read transition data.

**Migration checklist (exhaustive):**

| Consumer | Current usage | Change needed | Phase |
|----------|--------------|---------------|-------|
| `PlaybackEngineController._rebuildComposition` | `_timelineManager.timeline` | Change to `_timelineManager.state` | B |
| `PlaybackEngineController._onTimelineChanged` | `_timelineManager.timeline` | No change (`.timeline` getter still works) | -- |
| `PlaybackEngineController` constructor | `_timelineManager.timeline` | No change | -- |
| `CompositionManager.buildComposition` | `PersistentTimeline` param | Change to `TimelineState` param | B |
| `ScrubController.updateTimeline` | `PersistentTimeline` param | No change (only needs clip data) | -- |
| All `TimelineManager` internal methods | `_current` as `PersistentTimeline` | `_current.withTimeline(...)` wrapping | A |

Total files changed: 3 (`timeline_manager.dart`, `playback_engine_controller.dart`, `composition_manager.dart`). All existing tests pass because `.timeline` getter returns the same `PersistentTimeline` as before.

---

#### C3 Resolution: Time Mapping Algorithms -- Corrected Implementation

**Verdict: CONFIRMED CRITICAL.** The original `presentationToEditorial` has a moving-target bug. When `editorialTime` is incremented inside the loop, the comparison `transition.editPointTime <= editorialTime` becomes unstable for subsequent transitions.

**Root cause:** The algorithm conflates the accumulator (running offset correction) with the comparison threshold.

**Corrected implementation:**

```dart
/// Convert presentation time (what the user sees on the playhead) to
/// editorial time (position in the PersistentTimeline tree).
///
/// Presentation time is shorter than editorial time because transitions
/// create overlaps that compress the visible timeline.
///
/// Algorithm: Walk through sorted transitions. Each transition whose
/// START falls at or before the accumulated presentation position
/// contributes its full duration as an offset. We compare against
/// the transition's *presentation-space* position (its editorial position
/// minus all prior overlaps), NOT against the shifting editorial time.
int presentationToEditorial(int presentationMicros) {
  int accumulatedOverlap = 0;
  for (final transition in _sortedTransitionsByEditPoint) {
    // Transition's position in presentation space:
    // editPointTime minus all overlaps from transitions before it.
    final transitionPresentationTime =
        transition.editPointTime - accumulatedOverlap;

    if (presentationMicros < transitionPresentationTime) {
      // We are before this transition in presentation space.
      break;
    }

    // Check if we are WITHIN this transition's overlap zone.
    final transitionPresentationEnd =
        transitionPresentationTime; // In presentation space, the overlap
                                    // is "consumed" -- the transition zone
                                    // does not add visible time.
    // The overlap is fully absorbed, so the transition effectively
    // collapses `duration` microseconds of editorial time into zero
    // presentation time at the edit point.

    accumulatedOverlap += transition.duration;
  }
  return presentationMicros + accumulatedOverlap;
}

/// Convert editorial time to presentation time.
///
/// Inverse of presentationToEditorial.
int editorialToPresentation(int editorialMicros) {
  int accumulatedOverlap = 0;
  for (final transition in _sortedTransitionsByEditPoint) {
    if (transition.editPointTime > editorialMicros) {
      break;
    }
    accumulatedOverlap += transition.duration;
  }
  return editorialMicros - accumulatedOverlap;
}
```

**Critical distinction:** `editorialToPresentation` is simpler because editorial positions are stable (they come from the tree). We just subtract overlaps from transitions whose edit points are at or before the editorial position. `presentationToEditorial` is trickier because the comparison threshold shifts.

**However, there is an additional subtlety for positions WITHIN a transition zone:** When the playhead is inside a transition overlap, the mapping is not a simple offset. During the overlap, editorial time advances faster than presentation time because two clips are playing simultaneously. For positions inside a transition zone:

```dart
/// Enhanced version handling positions within transition zones.
int presentationToEditorial(int presentationMicros) {
  int accumulatedOverlap = 0;

  for (final transition in _sortedTransitionsByEditPoint) {
    final transPresentationStart =
        transition.editPointTime - accumulatedOverlap
        - transition.leftOverlapRequired;

    if (presentationMicros < transPresentationStart) {
      break;
    }

    // Presentation-space end of the transition zone:
    // The transition zone occupies ZERO extra presentation time --
    // it compresses editorial time. But the transition IS visible
    // for (duration - overlap) presentation time... actually no.
    //
    // Clarification: The overlap model means the total timeline
    // shortens by transition.duration. In presentation space,
    // the edit point and everything after it shifts left by
    // transition.duration. The transition zone itself occupies
    // the same visual space as the overlapping clip regions.
    //
    // For most purposes (playhead positioning, seeking), the
    // simple accumulator approach is correct: we just add back
    // the full overlap for any transition whose edit point we
    // have passed.

    accumulatedOverlap += transition.duration;
  }
  return presentationMicros + accumulatedOverlap;
}
```

**Design clarification needed:** The relationship between "presentation time" and "editorial time" within a transition zone depends on interpretation. Two options:

1. **Option A (Recommended, simpler):** A transition zone of duration D at edit point E means: in editorial time, clip A runs from E-D/2 to E+D/2 and clip B runs from E-D/2 to E+D/2 (for centerOnCut). In presentation time, the zone occupies D microseconds at the same visual location, but the overall timeline is D shorter because the zone replaces what was D of sequential time with D of simultaneous time. The time mapping is: presentation time maps 1:1 to the OUTGOING clip's editorial time within the zone. The incoming clip's editorial time is determined by the transition progress.

2. **Option B (Complex):** Both editorial times are mapped simultaneously with interpolation.

**Recommendation:** Use Option A. The simple accumulator approach is correct for all external uses (playhead positioning, seeking, duration display). The dual-clip time resolution during the transition zone is handled internally by the `TransitionRenderer` which knows both clips' source times.

**Required tests:**

```dart
group('Time mapping', () {
  // Setup: 3 clips of 3s each, 2 transitions of 0.5s each (centerOnCut)
  // Editorial: [0..3s][3s..6s][6s..9s] = 9s total
  // Presentation: 9s - 0.5s - 0.5s = 8s total

  test('no transitions - identity mapping', () {
    expect(state.presentationToEditorial(1000000), 1000000);
    expect(state.editorialToPresentation(1000000), 1000000);
  });

  test('single transition - before transition', () {
    // At presentation time 2s (before first transition at editorial 3s)
    expect(state.presentationToEditorial(2000000), 2000000);
  });

  test('single transition - after transition', () {
    // At presentation time 3s (after first transition)
    // Editorial = 3s + 0.5s overlap = 3.5s
    expect(state.presentationToEditorial(3000000), 3500000);
  });

  test('two transitions - after both', () {
    // At presentation time 6s (after both transitions)
    // Editorial = 6s + 0.5s + 0.5s = 7s
    expect(state.presentationToEditorial(6000000), 7000000);
  });

  test('round trip', () {
    for (final t in [0, 1000000, 2500000, 5000000, 7500000]) {
      final editorial = state.presentationToEditorial(t);
      expect(state.editorialToPresentation(editorial), t);
    }
  });

  test('different alignments', () {
    // startAtCut: overlap is entirely after edit point
    // endAtCut: overlap is entirely before edit point
    // Both should still shorten timeline by transition.duration
  });
});
```

---

#### C4 Resolution: CompositionBuilder Dual-Track A/B Interleaving Algorithm

**Verdict: CONFIRMED CRITICAL.** The current `CompositionBuilder.swift` creates exactly one video track (line 131: `composition.addMutableTrack(withMediaType: .video, ...)`). Transitions fundamentally require two tracks because `AVMutableCompositionTrack.insertTimeRange` does not allow overlapping time ranges on the same track.

**Concrete A/B Track Interleaving Algorithm:**

The standard NLE approach is to alternate clips between two video tracks (Track A and Track B) so that during a transition, the outgoing clip is on one track and the incoming clip is on the other.

```
Example: 4 clips with 3 transitions

Track A: [==Clip1==][-----gap-----][==Clip3==][-----gap-----]
Track B: [---gap---][==Clip2==][-----gap-----][==Clip4==]
                    |trans1|         |trans2|         |trans3|

Instructions:
  [0..t1_start]        -> Passthrough Track A (Clip1)
  [t1_start..t1_end]   -> TransitionInstruction(A -> B)
  [t1_end..t2_start]   -> Passthrough Track B (Clip2)
  [t2_start..t2_end]   -> TransitionInstruction(B -> A)
  [t2_end..t3_start]   -> Passthrough Track A (Clip3)
  [t3_start..t3_end]   -> TransitionInstruction(A -> B)
  [t3_end..end]        -> Passthrough Track B (Clip4)
```

**Concrete Swift implementation sketch for `CompositionBuilder`:**

```swift
func buildWithTransitions(
    segments: [CompositionSegment],
    transitions: [TransitionData],
    compositionId: String
) throws -> BuiltComposition {
    let composition = AVMutableComposition()

    // Create TWO video tracks
    guard let videoTrackA = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
    ), let videoTrackB = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        throw CompositionError.failedToCreateTrack("video")
    }

    // Two audio tracks for crossfade
    let audioTrackA = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
    )
    let audioTrackB = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
    )

    // Build a transition lookup: segmentIndex -> TransitionData
    // (transition between segment[i] and segment[i+1])
    var transitionByEditPoint: [Int: TransitionData] = [:]
    for t in transitions {
        transitionByEditPoint[t.editPointMicros] = t
    }

    var currentTime = CMTime.zero
    var useTrackA = true  // Alternate between tracks
    var instructions: [AVVideoCompositionInstructionProtocol] = []
    var audioMixParams: [AVMutableAudioMixInputParameters] = []

    for (index, segment) in segments.enumerated() {
        let videoTrack = useTrackA ? videoTrackA : videoTrackB
        let audioTrack = useTrackA ? audioTrackA : audioTrackB
        let segmentDuration = CMTime(
            value: CMTimeValue(segment.durationMicros),
            timescale: 1_000_000
        )

        // Insert segment onto current track
        if segment.type == .video {
            try insertVideoSegment(segment, into: videoTrack,
                                   audioTrack: audioTrack, at: currentTime)
        }

        // Check for transition AFTER this segment
        let editPointMicros = Int(CMTimeGetSeconds(
            CMTimeAdd(currentTime, segmentDuration)) * 1_000_000)

        if let transition = transitionByEditPoint[editPointMicros],
           index + 1 < segments.count {
            let nextSegment = segments[index + 1]
            let nextVideoTrack = useTrackA ? videoTrackB : videoTrackA
            let nextAudioTrack = useTrackA ? audioTrackB : audioTrackA
            let transitionDuration = CMTime(
                value: CMTimeValue(transition.durationMicros),
                timescale: 1_000_000
            )
            let halfDuration = CMTime(
                value: CMTimeValue(transition.durationMicros / 2),
                timescale: 1_000_000
            )

            // Passthrough instruction for non-overlapping part
            let passthroughEnd = CMTimeSubtract(
                CMTimeAdd(currentTime, segmentDuration), halfDuration)
            if CMTimeCompare(passthroughEnd, currentTime) > 0 {
                let ptInstruction = AVMutableVideoCompositionInstruction()
                ptInstruction.timeRange = CMTimeRange(
                    start: currentTime, end: passthroughEnd)
                let layerInst = AVMutableVideoCompositionLayerInstruction(
                    assetTrack: videoTrack)
                ptInstruction.layerInstructions = [layerInst]
                instructions.append(ptInstruction)
            }

            // Transition instruction for overlapping part
            let transitionStart = passthroughEnd
            let transitionRange = CMTimeRange(
                start: transitionStart, duration: transitionDuration)

            let transInstruction = TransitionInstruction(
                timeRange: transitionRange,
                sourceTrackIDs: [
                    NSValue(value: videoTrack.trackID) as! NSNumber,
                    NSValue(value: nextVideoTrack.trackID) as! NSNumber,
                ],
                transitionType: transition.type,
                direction: transition.direction,
                softness: transition.softness,
                easing: transition.easing,
                parameters: transition.parameters
            )
            instructions.append(transInstruction)

            // Audio crossfade via volume ramps
            if transition.audioCrossfade {
                let fadeOutParams = AVMutableAudioMixInputParameters(
                    track: audioTrack!)
                fadeOutParams.setVolumeRamp(
                    fromStartVolume: 1.0, toEndVolume: 0.0,
                    timeRange: transitionRange)
                audioMixParams.append(fadeOutParams)

                let fadeInParams = AVMutableAudioMixInputParameters(
                    track: nextAudioTrack!)
                fadeInParams.setVolumeRamp(
                    fromStartVolume: 0.0, toEndVolume: 1.0,
                    timeRange: transitionRange)
                audioMixParams.append(fadeInParams)
            }

            // The next segment starts earlier (overlap absorbed)
            currentTime = CMTimeAdd(currentTime,
                CMTimeSubtract(segmentDuration, halfDuration))
            useTrackA = !useTrackA
        } else {
            // No transition after this segment
            // Add passthrough instruction
            let ptInstruction = AVMutableVideoCompositionInstruction()
            ptInstruction.timeRange = CMTimeRange(
                start: currentTime, duration: segmentDuration)
            let layerInst = AVMutableVideoCompositionLayerInstruction(
                assetTrack: videoTrack)
            ptInstruction.layerInstructions = [layerInst]
            instructions.append(ptInstruction)

            currentTime = CMTimeAdd(currentTime, segmentDuration)
            useTrackA = !useTrackA
        }
    }

    // Set custom compositor
    let videoComposition = AVMutableVideoComposition()
    videoComposition.customVideoCompositorClass = TransitionCompositor.self
    videoComposition.instructions = instructions
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

    // ... build and return BuiltComposition
}
```

**Key design decisions in this algorithm:**

1. **Always alternate tracks** regardless of whether there is a transition. This simplifies the logic -- even clips without transitions alternate A/B. The passthrough instructions simply reference whichever track the clip is on.
2. **Transition time overlap:** For `centerOnCut`, the outgoing clip's last `D/2` microseconds and the incoming clip's first `D/2` microseconds occupy the same composition time range. Both are inserted on their respective tracks at the transition start time.
3. **The `TransitionCompositor`** receives both track frames via `AVAsynchronousVideoCompositionRequest.sourceFrame(byTrackID:)` and blends them.

**Backward compatibility:** When there are zero transitions, the algorithm still works -- it simply produces passthrough instructions for alternating single-track segments. The `TransitionCompositor` is only used when `TransitionInstruction` instances are present; otherwise `AVFoundation` uses its default passthrough compositor.

---

#### C5 Resolution: Platform Channel Contract for Transition Data

**Verdict: CONFIRMED CRITICAL.** The current `CompositionManager._buildSegment()` has no awareness of transitions.

**Concrete method signatures:**

**Dart side (`CompositionManager`):**

```dart
/// Build composition from timeline state (includes transitions).
Future<void> buildComposition(TimelineState state) async {
  // ... existing queuing logic ...

  final segments = <Map<String, dynamic>>[];
  for (final item in state.timeline.toList()) {
    final segment = _buildSegment(item);
    if (segment != null) segments.add(segment);
  }

  // NEW: Build transitions array
  final transitions = <Map<String, dynamic>>[];
  for (final t in state.transitions.values) {
    transitions.add(_buildTransitionData(t, state));
  }

  final result = await _channel.invokeMethod('buildComposition', {
    'segments': segments,
    'transitions': transitions,  // NEW
  });
  // ...
}

Map<String, dynamic> _buildTransitionData(
    ClipTransition transition, TimelineState state) {
  final leftClip = state.timeline.getById(transition.leftClipId);
  final rightClip = state.timeline.getById(transition.rightClipId);

  // Resolve asset paths for both clips
  String? leftAssetPath;
  String? rightAssetPath;
  if (leftClip is VideoClip) {
    leftAssetPath = _assetRegistry.getById(leftClip.mediaAssetId)?.relativePath;
  }
  if (rightClip is VideoClip) {
    rightAssetPath = _assetRegistry.getById(rightClip.mediaAssetId)?.relativePath;
  }

  return {
    'id': transition.id,
    'type': transition.type.name,
    'durationMicros': transition.duration,
    'alignment': transition.alignment.name,
    'editPointMicros': transition.editPointTime,
    'direction': transition.direction.index,  // 0=left, 1=right, 2=up, 3=down
    'easing': _curveToName(transition.easing),
    'leftClipId': transition.leftClipId,
    'rightClipId': transition.rightClipId,
    'leftAssetPath': leftAssetPath,
    'rightAssetPath': rightAssetPath,
    'leftSourceOutMicros': (leftClip as MediaClip?)?.sourceOutMicros,
    'rightSourceInMicros': (rightClip as MediaClip?)?.sourceInMicros,
    'parameters': transition.parameters,
    'audioCrossfade': transition.parameters['audioCrossfade'] ?? true,
    'audioCurveType': transition.parameters['audioCurveType'] ?? 'equalPower',
  };
}

String _curveToName(Curve curve) {
  if (curve == Curves.linear) return 'linear';
  if (curve == Curves.easeIn) return 'easeIn';
  if (curve == Curves.easeOut) return 'easeOut';
  if (curve == Curves.easeInOut) return 'easeInOut';
  if (curve == Curves.fastOutSlowIn) return 'fastOutSlowIn';
  if (curve == Curves.decelerate) return 'decelerate';
  return 'easeInOut';  // Default fallback
}
```

**Swift side (`CompositionManagerService` -- receives platform channel call):**

```swift
struct TransitionData {
    let id: String
    let type: String             // "crossDissolve", "wipe", etc.
    let durationMicros: Int
    let alignment: String        // "centerOnCut", "startAtCut", "endAtCut"
    let editPointMicros: Int
    let direction: Int           // 0=left, 1=right, 2=up, 3=down
    let easing: String           // "easeInOut", "linear", etc.
    let leftClipId: String
    let rightClipId: String
    let leftAssetPath: String?
    let rightAssetPath: String?
    let leftSourceOutMicros: Int?
    let rightSourceInMicros: Int?
    let parameters: [String: Any]
    let audioCrossfade: Bool
    let audioCurveType: String   // "linear", "equalPower", "sCurve"

    init(from dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? ""
        self.type = dictionary["type"] as? String ?? "crossDissolve"
        self.durationMicros = dictionary["durationMicros"] as? Int ?? 500000
        self.alignment = dictionary["alignment"] as? String ?? "centerOnCut"
        self.editPointMicros = dictionary["editPointMicros"] as? Int ?? 0
        self.direction = dictionary["direction"] as? Int ?? 0
        self.easing = dictionary["easing"] as? String ?? "easeInOut"
        self.leftClipId = dictionary["leftClipId"] as? String ?? ""
        self.rightClipId = dictionary["rightClipId"] as? String ?? ""
        self.leftAssetPath = dictionary["leftAssetPath"] as? String
        self.rightAssetPath = dictionary["rightAssetPath"] as? String
        self.leftSourceOutMicros = dictionary["leftSourceOutMicros"] as? Int
        self.rightSourceInMicros = dictionary["rightSourceInMicros"] as? Int
        self.parameters = dictionary["parameters"] as? [String: Any] ?? [:]
        self.audioCrossfade = dictionary["audioCrossfade"] as? Bool ?? true
        self.audioCurveType = dictionary["audioCurveType"] as? String ?? "equalPower"
    }
}
```

**Platform channel method handler update:**

```swift
// In CompositionManagerService.swift
case "buildComposition":
    guard let args = call.arguments as? [String: Any] else { ... }
    let segmentDicts = args["segments"] as? [[String: Any]] ?? []
    let transitionDicts = args["transitions"] as? [[String: Any]] ?? []

    let segments = segmentDicts.map { CompositionSegment(from: $0) }
    let transitions = transitionDicts.map { TransitionData(from: $0) }

    if transitions.isEmpty {
        // Use existing single-track builder (backward compatible)
        compositionBuilder.buildAsync(segments: segments, compositionId: id)
    } else {
        // Use new dual-track builder
        compositionBuilder.buildWithTransitionsAsync(
            segments: segments,
            transitions: transitions,
            compositionId: id
        )
    }
```

**Design decision:** Transitions are passed as a **separate top-level array** (not embedded inline between segments). This keeps the segment format backward-compatible and separates concerns. The Swift side correlates transitions to segments via `editPointMicros` matching.

---

### 2. New Issues Found in Review 2

#### N1. `editPointTime` as Absolute Time Is Still Fragile (Reinforces I8 from Review 1)

After reading `TimelineManager` in detail, every mutation (insert, remove, split, trim) that changes clip positions will invalidate `editPointTime` on all downstream transitions. The `TimelineState.withTimeline()` method in the C2 solution copies the transitions map unchanged, but the `editPointTime` values become stale.

**Recommended fix:** Adopt Review 1's I8 recommendation. Make `editPointTime` a computed value, not a stored value:

```dart
/// Compute editPointTime dynamically from the tree.
int editPointTimeFor(ClipTransition t, PersistentTimeline timeline) {
  final rightStart = timeline.startTimeOf(t.rightClipId);
  if (rightStart != null) return rightStart;
  // Fallback: compute from left clip end
  final leftStart = timeline.startTimeOf(t.leftClipId);
  final leftClip = timeline.getById(t.leftClipId);
  if (leftStart != null && leftClip != null) {
    return leftStart + leftClip.durationMicroseconds;
  }
  return t.editPointTime; // Stored fallback
}
```

Then `ClipTransition` retains `editPointTime` for serialization but the runtime always recomputes it. This eliminates the stale-time bug entirely.

**Performance cost:** `startTimeOf` is O(n) in the current implementation (in-order traversal). For a timeline with 50 clips and 49 transitions, recomputing all edit points costs 50 * O(n) = O(n^2). This is unacceptable for every frame.

**Mitigation:** Cache the computed edit points in `TimelineState`. Recompute only when the timeline tree changes (which already triggers `_compositionDirty = true`). A `_cachedEditPoints` map built lazily on first access (similar to `PersistentTimeline._getIdIndex()`) provides amortized O(1) lookups.

```dart
@immutable
class TimelineState {
  // ... existing fields ...

  /// Lazily computed edit point cache.
  Map<String, int>? _editPointCache;

  int editPointTimeFor(String transitionId) {
    _editPointCache ??= _buildEditPointCache();
    return _editPointCache![transitionId] ?? 0;
  }

  Map<String, int> _buildEditPointCache() {
    final cache = <String, int>{};
    final items = timeline.toList();
    int accumulatedTime = 0;
    for (int i = 0; i < items.length; i++) {
      accumulatedTime += items[i].durationMicroseconds;
      // Check if there is a transition between items[i] and items[i+1]
      final transId = leftClipToTransition[items[i].id];
      if (transId != null) {
        cache[transId] = accumulatedTime;
      }
    }
    return cache;
  }
}
```

This is O(n) once per state change, then O(1) per lookup. Since state changes already trigger O(n) composition rebuilds, this adds negligible overhead.

#### N2. Split Operation Must Remove Transitions in Transition Zone

The existing `TimelineManager.splitAt` does NOT know about transitions. After the C2 migration, `splitAt` must:

1. Check if the split point falls within any transition zone. If so, reject the split (as stated in Section 12.6).
2. After splitting, update transition clip references: if the split clip was `rightClipId` of a transition, update to the left portion's ID; if it was `leftClipId`, update to the right portion's ID.

This logic must be added to the `_execute` closure for `splitAt`, or better, the `TransitionController` should intercept split operations and handle transition updates.

**Recommendation:** Add a `TimelineState.splitAt(timeMicros)` method that handles both the tree split AND transition updates atomically, returning a new `TimelineState`.

#### N3. Remove Operation Must Cascade-Remove Transitions

Similarly, `TimelineManager.remove(itemId)` must also remove any transitions that reference the removed clip. This is a cascade delete:

```dart
TimelineState removeClipAndTransitions(String clipId) {
  var newState = this;
  // Remove transition on left (where this clip is rightClipId)
  final leftTransId = rightClipToTransition[clipId];
  if (leftTransId != null) {
    newState = newState.removeTransition(leftTransId);
  }
  // Remove transition on right (where this clip is leftClipId)
  final rightTransId = leftClipToTransition[clipId];
  if (rightTransId != null) {
    newState = newState.removeTransition(rightTransId);
  }
  // Remove the clip from the tree
  return newState.withTimeline(newState.timeline.remove(clipId));
}
```

#### N4. Immutable Maps in TimelineState Have O(n) Copy Cost

Each `addTransition` / `removeTransition` creates `Map.from(transitions)` which copies the entire map. With 50 transitions, this is 50 allocations per edit. For the undo/redo use case this is fine (structural sharing only applies to the tree, not the maps).

**Recommendation:** For V1 transitions, this is acceptable. If profiling shows map copying as a bottleneck (unlikely with < 100 transitions), migrate to a persistent/immutable map implementation (e.g., `built_collection` `BuiltMap` or a hand-rolled HAMT).

#### N5. `CachedFrame.pixels` as `Uint8List` -- Shader Texture Upload Is the Real Bottleneck

Review 1 flagged this as I1. After examining the `FrameCache`, frames are stored as `Uint8List` (BGRA pixels). Flutter's `FragmentShader.setImageSampler()` requires a `dart:ui.Image`, not raw bytes. The conversion path is:

```dart
// Required conversion for each frame during transition:
final image = await decodeImageFromPixels(
  frame.pixels,
  frame.width,
  frame.height,
  PixelFormat.bgra8888,
);
```

At 1080p (1920x1080x4 = ~8MB per frame), `decodeImageFromPixels` takes approximately 2-5ms on modern iPhones. Two frames = 4-10ms just for conversion, consuming up to 60% of the 16.6ms frame budget.

**Alternative approaches ranked by feasibility:**

1. **Store frames as `dart:ui.Image` in cache (RECOMMENDED).** Modify `CachedFrame` to hold an optional `dart:ui.Image` alongside or instead of `Uint8List`. The decoder pool produces `Image` objects directly. The `memorySizeBytes` calculation uses `width * height * 4`. This eliminates conversion entirely. Drawback: `dart:ui.Image` is a GPU-resident handle, so cache eviction must call `image.dispose()`.

2. **Use `Canvas.drawImage` + blend modes instead of shaders for simple transitions.** Cross dissolve = draw A with full opacity, draw B with `BlendMode.srcOver` at `progress` opacity. Wipe = use `canvas.clipRect` + draw A and B. This avoids shaders entirely for 60% of transition types. Reserve shaders for complex effects (page curl, rotation, blur).

3. **Use `Texture` widget with native-side rendering.** The native side already has the frames as `CVPixelBuffer`s. Render the transition on the native side and display via a Flutter `Texture` widget. This is the highest-performance option but requires more native code.

**Recommendation:** Start with approach 2 (Canvas-based rendering) for basic transitions (dissolve, fade, wipe, slide). This ships faster and has zero texture upload overhead. Implement approach 1 for the shader path needed by complex transitions (blur, page curl, rotation).

---

### 3. Integration Test Plan Additions

The design's test files (Section 14.5) cover unit tests but are light on integration tests. The following integration tests are critical for catching transition edge cases:

#### 3.1 Timeline State Consistency Tests

```dart
group('Timeline state consistency', () {
  test('add transition preserves tree structure', () {
    // Add clips, add transition, verify tree still produces
    // correct items in order via toList()
  });

  test('undo add-transition restores exact previous state', () {
    // Add transition, undo, compare state with snapshot
    // Verify transitions map is empty after undo
  });

  test('redo after undo restores transition', () {
    // Add transition, undo, redo
    // Verify transition is present with correct properties
  });

  test('rapid undo/redo with transitions is O(1)', () {
    // Time 100 undo/redo cycles, verify < 1ms each
  });
});
```

#### 3.2 Cascade Operation Tests

```dart
group('Cascade operations', () {
  test('delete clip removes both adjacent transitions', () {
    // A <-t1-> B <-t2-> C, delete B
    // Verify t1 and t2 are both removed
    // Verify A and C are now adjacent
  });

  test('split clip at midpoint preserves outer transitions', () {
    // A <-t1-> B <-t2-> C, split B
    // Verify t1 now references B1, t2 references B2
  });

  test('split within transition zone is rejected', () {
    // A <-t1-> B, split at time within t1's overlap
    // Verify split returns without mutation
  });

  test('trim reduces transition duration when handle shrinks', () {
    // A <-t1-> B, trim A's tail to reduce handle
    // Verify t1.duration is clamped to available handle
  });

  test('trim removes transition when handle reaches zero', () {
    // A <-t1-> B, trim A's tail until no handle
    // Verify t1 is removed entirely
  });
});
```

#### 3.3 Composition Build Integration Tests

```dart
group('Composition with transitions', () {
  test('segments + transitions produce valid platform channel data', () {
    // Build state with transitions
    // Call _buildTransitionData for each
    // Verify JSON structure matches Swift TransitionData.init(from:)
  });

  test('zero transitions falls back to single-track build', () {
    // No transitions -> 'transitions' key is empty array
    // Verify backward compatibility
  });

  test('transition between offline clips produces placeholder', () {
    // Left or right clip is offline
    // Verify transition is omitted from build
  });
});
```

#### 3.4 Time Mapping Round-Trip Tests

```dart
group('Time mapping round-trip', () {
  test('presentation -> editorial -> presentation is identity', () {
    // For 100 evenly spaced presentation times, verify round-trip
  });

  test('editorial -> presentation -> editorial is identity', () {
    // For 100 evenly spaced editorial times, verify round-trip
  });

  test('effective duration equals last presentation time', () {
    // state.effectiveDurationMicros ==
    //   state.editorialToPresentation(state.timeline.totalDurationMicros)
  });
});
```

#### 3.5 Performance Regression Tests

```dart
group('Performance', () {
  test('add transition < 1ms for 100-clip timeline', () {
    // Build 100-clip timeline, measure addTransition time
  });

  test('remove transition < 1ms for 100-clip timeline', () {
    // 100 clips, 99 transitions, measure removeTransition
  });

  test('effectiveDurationMicros < 100us for 50 transitions', () {
    // Verify the sum loop is fast
  });

  test('frame cache handles dual-asset lookup < 2ms', () {
    // Two getFrame calls for different assets at same time
  });
});
```

---

### 4. Shader Feasibility Assessment

**Question:** Are Flutter fragment shaders actually usable for transition rendering at 60fps?

**Analysis:**

Flutter supports GLSL fragment shaders via `dart:ui.FragmentProgram` since Flutter 3.7. On iOS, these are compiled to Metal Shading Language via SPIRV-Cross. The shader execution itself runs on the GPU and is fast (< 1ms for simple shaders at 1080p).

**The bottleneck is NOT the shader; it is the texture upload path.** As analyzed in N5 above, converting `Uint8List` to `dart:ui.Image` costs 2-5ms per frame. With two frames, this is 4-10ms.

**Benchmark data (estimated from Flutter performance documentation and community benchmarks):**

| Operation | iPhone 12+ | iPhone SE 2 | iPad Air M1 |
|-----------|-----------|-------------|-------------|
| `decodeImageFromPixels` (1080p BGRA) | ~2ms | ~4ms | ~1.5ms |
| Fragment shader execution (dissolve) | < 0.5ms | < 1ms | < 0.3ms |
| Fragment shader execution (blur, 2-pass) | ~2ms | ~4ms | ~1ms |
| Total for dissolve transition frame | ~4.5ms | ~9ms | ~3.3ms |
| Total for blur transition frame | ~6ms | ~12ms | ~4ms |

**Verdict:** Dissolve transitions are feasible at 60fps on all target devices. Complex transitions (blur, page curl) may drop to 30fps on older devices, which is acceptable per the design's degradation strategy (Section 11.5: "If frame rate drops below 45 FPS, degrade to cross dissolve").

**Recommendation:** As stated in N5, use Canvas-based rendering for simple transitions and reserve shaders for complex ones. This eliminates the texture upload bottleneck for the most common transition (cross dissolve, which is ~80% of usage).

**GLSL version note (reinforces M1):** Use `#version 320 es` not `#version 460`. Flutter's SPIRV-Cross pipeline targets ES 3.2. The shaders in Section 6.4 and 6.5 must be updated.

---

### 5. Memory Impact Assessment

**Question:** Two frames simultaneously during transition -- quantify memory spike.

**Analysis from `FrameCache`:**

- Default max cache: 120 frames at 300MB limit.
- Each 1080p BGRA frame: 1920 * 1080 * 4 = 8,294,400 bytes = ~7.9MB.
- Normal operation: 1 frame per display tick. Cache holds up to 120 / (7.9) ~= 38 unique 1080p frames if all are 1080p.
- During transition: 2 frames per display tick from 2 different assets.

**Memory spike scenarios:**

| Scenario | Normal | During Transition | Delta |
|----------|--------|-------------------|-------|
| Single frame display | 7.9MB | 15.8MB | +7.9MB |
| Prefetch window (30 frames ahead) | ~237MB | ~474MB (two assets) | +237MB |

The prefetch doubling is the real concern. The current 300MB limit means only ~19 frames per asset can be cached when two assets are active. This is sufficient for smooth playback (0.6s at 30fps) but tight for fast scrubbing.

**Mitigation strategies:**

1. **Transition-aware prefetch budget:** When approaching a transition zone, reduce per-asset prefetch to 50% of normal (15 frames each instead of 30). Total stays within 300MB.

2. **Priority-based eviction:** Frames from clips that are NOT part of the current or upcoming transition should be evicted first. The current LRU already handles this naturally (distant frames are least recently used), but explicit priority could help.

3. **Reduced resolution during transition preview:** Decode transition frames at half resolution (960x540 = ~2MB each) during preview. This cuts memory by 4x. The shader upscales to display resolution. During export, use full resolution.

4. **`dart:ui.Image` cache variant:** If frames are stored as GPU-resident `dart:ui.Image` objects (N5 recommendation), the CPU-side memory impact is near zero. The GPU memory cost is similar but managed by the GPU driver with its own eviction.

**Recommendation:** Implement strategy 1 (halved prefetch budget during transitions) for the initial release. Monitor memory with Instruments. Add strategy 3 if memory pressure events occur during testing.

---

### 6. Revised Risk Assessment

| Risk Area | Review 1 Rating | Review 2 Rating | Justification |
|-----------|-----------------|-----------------|---------------|
| V1/V2 model confusion (C1) | CRITICAL | **HIGH (mitigated)** | Adapter pattern resolves without full V1 deprecation. 3 files changed. |
| TimelineState migration (C2) | CRITICAL | **MEDIUM (mitigated)** | Only 3 external consumers. Backward-compatible `.timeline` getter eliminates most migration. |
| Time mapping bugs (C3) | CRITICAL | **HIGH** | Corrected algorithm provided, but the within-transition-zone behavior needs careful testing. Edge cases with multiple adjacent transitions + mixed alignments remain tricky. |
| CompositionBuilder dual-track (C4) | CRITICAL | **HIGH** | Algorithm specified, but this is the most complex Swift change. Requires thorough testing with real AVFoundation on device. Simulator may hide timing bugs. |
| Platform channel contract (C5) | CRITICAL | **LOW (mitigated)** | Fully specified above. Straightforward serialization. |
| Shader texture upload (I1) | IMPORTANT | **HIGH** | The `Uint8List` to `Image` conversion is the real 60fps risk. Canvas-based fallback for simple transitions is essential. |
| Memory during transitions (P1) | Performance note | **MEDIUM** | Halved prefetch budget keeps within 300MB. Requires testing on 3GB RAM devices (iPhone SE). |
| Stale editPointTime (I8/N1) | IMPORTANT | **HIGH** | Must be addressed with cached computed values. Failing to do so causes bugs on every edit after adding transitions. |
| Cascade operations (N2/N3) | Not in Review 1 | **HIGH (new)** | Split and remove must atomically update transitions. Missing this causes orphaned transitions and crashes. |

**Overall verdict:** The design is implementable. The C2 and C5 criticals are now fully resolved. C1 is resolved with a clean adapter pattern. C3 and C4 are resolved with algorithms but require careful implementation and device testing. The new issues (N1-N5) are all addressable with the solutions provided.

**Recommended implementation order change:** Phase 1 should be split into:
- **Phase 1A:** `TimelineState` wrapper + transition CRUD (no rendering, no UI). All unit tests for C2, C3, N1-N3.
- **Phase 1B:** `TransitionController` with validation. Integration tests for cascade operations.
- **Phase 2:** Preview rendering, starting with Canvas-based (approach 2 from N5), then adding shader path.

This reduces risk by validating the data layer before touching rendering.

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06

---

### 1. Critical Issues Status

This section tracks every critical issue raised across Reviews 1 and 2, confirming each has a clear resolution path and no open ambiguity.

#### Review 1 Criticals (C1-C5)

| ID | Issue | R1 Status | R2 Resolution | R3 Verdict |
|----|-------|-----------|---------------|------------|
| C1 | V1/V2 model confusion | CRITICAL | `TimelineRenderData` adapter; transitions V2-only | **RESOLVED.** Confirmed: `edit_operations.dart` uses V1 `TimelineClip` in `DragState.clips`; the adapter pattern correctly decouples the rendering layer. The `ClipTransition.trackId` sentinel value `'main'` is a pragmatic choice for single-track V2. No further action needed. |
| C2 | `TimelineState` wrapper / undo-redo gap | CRITICAL | Two-phase incremental migration; backward-compatible `.timeline` getter | **RESOLVED.** I verified the codebase: `PlaybackEngineController` has exactly 3 call sites referencing `_timelineManager.timeline` (lines 180, 439, 465). The `CompositionManager.buildComposition` takes `PersistentTimeline` (line 82). R2's migration table is accurate and complete. The `.timeline` getter preserves backward compatibility during Phase A. |
| C3 | Time mapping functions incorrect for multiple transitions | CRITICAL | Corrected accumulator algorithm with presentation-space comparison; test suite provided | **RESOLVED with caveat.** The corrected `editorialToPresentation` is clean. The `presentationToEditorial` algorithm's "Option A" (simple accumulator, mapping 1:1 to outgoing clip time within zones) is correct for playhead positioning and seeking. **Caveat:** The within-zone dual-clip time resolution still needs explicit documentation in a code comment to prevent future developers from misinterpreting the mapping. The required test suite in R2 Section 2 is comprehensive and sufficient. |
| C4 | `CompositionBuilder.swift` single-track limitation | CRITICAL | A/B track interleaving algorithm with concrete Swift sketch | **RESOLVED with implementation note.** R2 provides a concrete algorithm. I verified `CompositionBuilder.swift` creates one video track at line 131. The proposed `buildWithTransitions` method is well-structured. **Implementation note:** The algorithm assumes `centerOnCut` alignment for the interleaving sketch. The implementer must handle `startAtCut` and `endAtCut` variants where the overlap is asymmetric (one clip extends by `duration`, the other by `0`). R2's sketch uses `halfDuration` which is only correct for `centerOnCut`. |
| C5 | Platform channel contract unspecified | CRITICAL | Full Dart + Swift contract specified with `TransitionData` struct | **RESOLVED.** The JSON schema is complete. The `_buildTransitionData` method includes all necessary fields (asset paths, source in/out points, parameters, audio crossfade settings). The Swift `TransitionData.init(from:)` matches the Dart output. The backward-compatible branching (`transitions.isEmpty` -> single-track builder) is correct. |

#### Review 2 New Issues (N1-N5)

| ID | Issue | R2 Status | R3 Verdict |
|----|-------|-----------|------------|
| N1 | `editPointTime` fragility (reinforces R1 I8) | HIGH | **RESOLVED.** The lazily-computed `_editPointCache` approach in `TimelineState._buildEditPointCache()` is correct. O(n) once per state change is negligible since composition rebuilds are already O(n). The stored `editPointTime` serves serialization; runtime always uses the cache. **One clarification needed:** The cache must be invalidated by making `TimelineState` truly immutable (each mutation returns a new instance without the cache, which is rebuilt lazily). Since `TimelineState` is `@immutable`, the `_editPointCache` field must be marked `late final` or computed in the constructor, NOT stored as a mutable nullable field. The R2 code sketch shows `Map<String, int>? _editPointCache` which violates `@immutable`. Fix: compute eagerly in a factory constructor, or use a top-level helper function. |
| N2 | Split operation must handle transitions | HIGH | **RESOLVED.** The recommendation to add `TimelineState.splitAt(timeMicros)` that handles both tree split and transition updates atomically is the correct approach. The split-within-transition-zone rejection is already specified in Section 12.6. |
| N3 | Remove operation must cascade-remove transitions | HIGH | **RESOLVED.** The `removeClipAndTransitions` method is straightforward. The lookup indexes (`leftClipToTransition`, `rightClipToTransition`) make cascade detection O(1). |
| N4 | Immutable map O(n) copy cost | MEDIUM (acceptable) | **ACCEPTED.** With fewer than 100 transitions, map copying is sub-microsecond. No action needed for V1. |
| N5 | Shader texture upload bottleneck | HIGH | **RESOLVED with recommended hybrid approach.** Canvas-based rendering for simple transitions (dissolve, fade, wipe, slide) + shader path for complex transitions (blur, page curl, rotation). This is the correct engineering tradeoff. The `CachedFrame.pixels` as `Uint8List` -> `dart:ui.Image` conversion cost (2-5ms per frame) is documented and mitigated. |

#### Remaining Important Issues from R1 (I1-I8)

| ID | Status | Notes |
|----|--------|-------|
| I1 | Addressed by N5 hybrid approach | Canvas path for simple transitions eliminates bottleneck |
| I2 | **OPEN -- needs decision during Phase 6.** Volume envelope merge strategy (multiply vs replace) not yet decided. Recommend: multiply (industry standard). Add to Phase 6 deliverables. |
| I3 | **OPEN -- needs implementation during Phase 2.** `ScrubController` transition awareness must be added. R2 does not provide a concrete solution. Recommend: add `TransitionFrameResolver` between `ScrubController` and `FrameCache`. |
| I4 | Addressed in R2 C1 resolution | Alignment-specific rendering uses `transition.startTime`/`endTime` |
| I5 | **OPEN -- simple fix.** `TimelineState.fromJson` must default `transitions` to empty map. Add format version number. Low effort, add to Phase 1A. |
| I6 | **OPEN -- needs explicit code.** Image clips have unlimited handles; ColorClip has unlimited handles; GapClip cannot participate. Add explicit type checks to `TransitionController.validateTransition`. Add to Phase 1B. |
| I7 | Deferred (speed is future work) | Note added to edge cases |
| I8 | Resolved by N1 | Cached computed `editPointTime` |

---

### 2. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | A/B track interleaving bugs on real devices (timing precision, track ID mismatches) | Medium | High | Test with real AVFoundation on physical device from Phase 5 day 1. Simulator hides CMTime precision issues. Create a 4-clip test composition with known frame-accurate expectations. |
| R2 | Shader compilation jank on first transition playback | Medium | Medium | Warm up dissolve + wipe shaders at launch (2 shaders, ~200ms). Lazy-compile the rest. Use Canvas fallback until compiled. |
| R3 | Memory pressure during dual-frame prefetch exceeds 300MB | Medium | Medium | Implement transition-aware prefetch budget (halve per-asset prefetch). Monitor with Instruments on iPhone SE (3GB RAM). Add memory pressure handler to evict transition frames first. |
| R4 | `editPointTime` cache invalidation bug (stale values after complex edits) | Low | High | `TimelineState` is `@immutable` -- each mutation returns a new instance. Cache is recomputed per instance. Unit test: add transition, split clip, verify editPointTime updates. |
| R5 | CIKernel deprecation on newer iOS versions | Low | High | Apple deprecated `CIKernel(source:)` in iOS 12 but still supports compiled `.metallib` kernels. Use Metal-based CIKernel for custom filters. Verify compilation on iOS 26 SDK. |
| R6 | `TransitionCompositor` frame delivery timeout during export | Low | Medium | Set `AVVideoComposition.sourceTrackIDForFrameTiming` correctly. Implement timeout handling in `startRequest()` that falls back to passthrough. Log errors for debugging. |
| R7 | Time mapping accumulation error with many transitions | Low | Medium | Round-trip test suite (R2 Section 2) catches drift. Use integer microsecond arithmetic throughout (no floating point). Add assertion: `effectiveDurationMicros >= 0`. |
| R8 | V1/V2 adapter data inconsistency during rendering | Low | Medium | `TimelineRenderData` is rebuilt each frame from `TimelineState`. No stale references. Unit test: modify state, rebuild adapter, verify positions. |
| R9 | Audio crossfade audible artifacts at transition boundaries | Medium | Low | Use equal-power crossfade as default (constant perceived loudness). Test with headphones. Allow user to switch to linear or S-curve if artifacts occur. |
| R10 | Phase 1 `TimelineManager` refactor breaks existing tests | Low | High | Run full `flutter test` after each sub-step of Phase 1A. The `.timeline` getter preserves backward compatibility. Only `_execute` closure signature changes internally. |

---

### 3. Implementation Checklist

Ordered by dependency. Each item lists the file, a brief description, and the phase.

#### Phase 1A: TimelineState Foundation (Days 1-2)

| # | File | Action | Description |
|---|------|--------|-------------|
| 1 | `lib/timeline/data/models/transition.dart` | MODIFY | Extend `TransitionType` enum with new values (wipeClock, wipeIris, slideOver, slideUnder, zoomIn, zoomOut, fadeToBlack, fadeToWhite, blur, rotation, pageCurl). Add `TransitionCategory` enum. Extend `TransitionTypeExtension` with `sfSymbolName`, `category`, `supportsDirection`, `supportsColor`, `supportsSoftness`, `requiresDualFrames`. Fix `toJson`/`fromJson` to serialize curve name via `_knownCurves` map. |
| 2 | `lib/timeline/data/models/transition_preset.dart` | CREATE | `TransitionPreset` immutable class with id, name, type, duration, direction, easing, parameters, isFavorite. |
| 3 | `lib/timeline/data/models/timeline_state.dart` | CREATE | `TimelineState` immutable class wrapping `PersistentTimeline` + transition maps. Include `addTransition`, `removeTransition`, `withTimeline`, `effectiveDurationMicros`, `editPointTimeFor` (lazily cached), `removeClipAndTransitions`, `splitAtWithTransitions`. |
| 4 | `lib/core/timeline_manager.dart` | MODIFY | Change `_current` from `PersistentTimeline` to `TimelineState`. Change undo/redo stacks to `List<TimelineState>`. Add `state` getter. Preserve `timeline` getter for backward compatibility. Update `_execute` closure to return `TimelineState`. Wrap all existing mutations with `.withTimeline()`. Add `addTransition`, `removeTransition`, `updateTransition` methods. |
| 5 | `test/models/transition_test.dart` | CREATE | Unit tests for `ClipTransition` (creation, copyWith, computed properties for all alignments, serialization round-trip including curve, minDuration/maxDuration clamping). Tests for new `TransitionType` values, `TransitionCategory`, `TransitionPreset`. |
| 6 | `test/models/timeline_state_test.dart` | CREATE | Unit tests for `TimelineState` (addTransition, removeTransition, withTimeline, effectiveDurationMicros, editPointTimeFor cache, removeClipAndTransitions, splitAtWithTransitions). Time mapping round-trip tests per R2 Section 2. |
| 7 | `test/core/timeline_manager_test.dart` | MODIFY | Verify all existing tests still pass after `TimelineState` migration. Add tests for addTransition/removeTransition/undo/redo with transitions. |

#### Phase 1B: TransitionController + Validation (Days 3-4)

| # | File | Action | Description |
|---|------|--------|-------------|
| 8 | `lib/core/transition_controller.dart` | CREATE | `TransitionController` with `addTransition`, `removeTransition`, `updateDuration`, `updateType`, `updateDirection`, `updateAlignment`, `updateParameters`, `transitionAtCutPoint`, `transitionsForTrack`, `transitionOnLeft`, `transitionOnRight`, `maxDurationForTransition`, `selectTransition`. Handle validation (clip type checks, handle availability, duration clamping, adjacent transition constraints per Section 12.3). |
| 9 | `test/core/transition_controller_test.dart` | CREATE | Validation tests (insufficient handles, gap clips, image clips unlimited handles, max duration clamping, adjacent transitions constraint). CRUD operation tests. Cascade tests (delete clip removes adjacent transitions, split updates transition references, split within zone rejected, trim reduces/removes transitions). |
| 10 | `test/timeline/transition_integration_test.dart` | CREATE | End-to-end tests: create timeline with clips, add transitions, verify effective duration, split/trim/delete with transitions, undo/redo roundtrips, serialization with transitions. Performance regression tests (add/remove < 1ms for 100-clip timeline). |

#### Phase 2: Preview Rendering (Days 5-8)

| # | File | Action | Description |
|---|------|--------|-------------|
| 11 | `lib/timeline/rendering/transition_renderer.dart` | CREATE | Canvas-based renderer for simple transitions (dissolve via `BlendMode`, fade via color overlay, wipe via `clipRect`, slide via translate). Shader-based renderer for complex transitions (blur, page curl, rotation). `renderTransitionFrame` method. |
| 12 | `lib/shaders/transitions/dissolve.frag` | CREATE | Cross dissolve fragment shader (GLSL 320 es). |
| 13 | `lib/shaders/transitions/dip_to_color.frag` | CREATE | Dip to color fragment shader. |
| 14 | `lib/shaders/transitions/wipe_directional.frag` | CREATE | Directional wipe with softness parameter. |
| 15 | `lib/shaders/transitions/wipe_clock.frag` | CREATE | Clockwise radial wipe. |
| 16 | `lib/shaders/transitions/wipe_iris.frag` | CREATE | Circular iris wipe. |
| 17 | `lib/shaders/transitions/slide.frag` | CREATE | Slide/push/slideOver/slideUnder with mode uniform. |
| 18 | `lib/shaders/transitions/zoom.frag` | CREATE | Zoom in/out with factor uniform. |
| 19 | `lib/shaders/transitions/blur.frag` | CREATE | Two-pass Gaussian blur transition. |
| 20 | `lib/shaders/transitions/rotation.frag` | CREATE | Rotation transition with angle uniform. |
| 21 | `lib/shaders/transitions/page_curl.frag` | CREATE | Page curl effect. |
| 22 | `lib/core/playback_engine_controller.dart` | MODIFY | Detect transition zones during playback. Request dual frames from FrameCache. Route through `TransitionRenderer`. Add `_isInTransitionZone` check in playback tick. |
| 23 | `lib/core/frame_cache.dart` | MODIFY | Add `prefetchForTransition` method. Transition-aware prefetch budget (halve per-asset when in transition zone). |
| 24 | `lib/core/scrub_controller.dart` | MODIFY | Add transition zone awareness. Detect when scrub position is within a transition. Request dual frames and composite via `TransitionRenderer`. |

#### Phase 3: Timeline UI (Days 9-11)

| # | File | Action | Description |
|---|------|--------|-------------|
| 25 | `lib/timeline/rendering/painters/transition_painter.dart` | CREATE | `TransitionPainter` (CustomPainter) rendering bowtie/diamond shapes, type icons, duration labels, selection highlights, drag handles. Takes `TimelineRenderData`, not V1 models. |
| 26 | `lib/timeline/rendering/timeline_render_data.dart` | CREATE | `TimelineRenderData` adapter class (per R2 C1 resolution). Bridges V2 `TimelineState` + `ViewportState` to rendering layer. |
| 27 | `lib/timeline/data/models/edit_operations.dart` | MODIFY | Add `HitType.cutPoint` enum value. Add `cutPointLeftClipId` and `cutPointRightClipId` fields to `HitTestResult`. |
| 28 | Timeline gesture handler (existing file) | MODIFY | Extend hit testing for cut points (tap to add transition) and existing transitions (tap to select, drag edges to resize). Add transition duration drag gesture with handle clamping and haptic feedback at 0.25s snap points. |

#### Phase 4: Transition Browser (Days 12-14)

| # | File | Action | Description |
|---|------|--------|-------------|
| 29 | `lib/views/transition/transition_browser_view.dart` | CREATE | Bottom sheet with Liquid Glass background. `CNTabBar` for categories (Favorites, Basic, Wipe, Slide, Zoom, Special). Transition grid with animated previews. `CupertinoSearchTextField`. `CupertinoSlider` for duration. `CupertinoButton` for Apply. |
| 30 | `lib/views/transition/transition_preview_widget.dart` | CREATE | Animated thumbnail widget showing transition effect on loop. Uses `TransitionRenderer` with stock gradient frames when clip frames unavailable. 80x60 preview cells. |
| 31 | `lib/views/transition/transition_inspector_view.dart` | CREATE | Selected transition properties panel. Type selector, duration slider, direction picker, easing picker, audio crossfade toggle, audio curve type selector. All native Cupertino widgets. |

#### Phase 5: Export Integration (Days 15-18)

| # | File | Action | Description |
|---|------|--------|-------------|
| 32 | `ios/Runner/Timeline/TransitionInstruction.swift` | CREATE | `AVVideoCompositionInstructionProtocol` implementation carrying transition type, parameters, source track IDs. |
| 33 | `ios/Runner/Timeline/TransitionCompositor.swift` | CREATE | `AVVideoCompositing` implementation. CIContext with Metal. `startRequest` dispatches to per-type CIFilter pipelines. Frame blending for each transition type. |
| 34 | `ios/Runner/Timeline/TransitionFilters.swift` | CREATE | Metal-based `CIKernel` implementations for clock wipe, iris wipe, and any transitions not covered by built-in CIFilters. CIFilter wrappers for slide, zoom, rotation. |
| 35 | `ios/Runner/Timeline/CompositionBuilder.swift` | MODIFY | Add `buildWithTransitions` method with dual video tracks (A/B interleaving). Overlapping segment insertion. `TransitionInstruction` generation. Audio crossfade via `AVMutableAudioMix` volume ramps. Handle all three alignment modes. |
| 36 | `ios/Runner/Timeline/CompositionManagerService.swift` | MODIFY | Parse `transitions` array from platform channel. Route to `buildWithTransitions` when transitions are present. Backward-compatible fallback to single-track when no transitions. |
| 37 | `lib/core/composition_manager.dart` | MODIFY | Change `buildComposition` parameter from `PersistentTimeline` to `TimelineState`. Add `_buildTransitionData` method. Include `'transitions'` key in platform channel call. |
| 38 | `lib/core/playback_engine_controller.dart` | MODIFY | Pass `_timelineManager.state` instead of `_timelineManager.timeline` to `CompositionManager.buildComposition`. |

#### Phase 6: Audio Crossfade (Days 19-20)

| # | File | Action | Description |
|---|------|--------|-------------|
| 39 | `lib/timeline/data/models/volume_keyframe.dart` | MODIFY | Add `VolumeEnvelope.compose(VolumeEnvelope other)` method using multiply strategy. Add `fadeIn` and `fadeOut` factory constructors for transition zones. |
| 40 | Audio crossfade in preview | IMPLEMENT | Apply volume envelopes to outgoing/incoming clip audio during preview playback. Three modes: linear, equal power (default), S-curve. |
| 41 | Audio crossfade toggle UI | IMPLEMENT | Add toggle and curve type selector in `transition_inspector_view.dart`. |

#### Phase 7: Polish and Testing (Days 21-23)

| # | File | Action | Description |
|---|------|--------|-------------|
| 42 | Edge case testing | TEST | All scenarios from Section 12 (12.1 through 12.12). Stress test with 50+ transitions. Memory pressure testing on iPhone SE. |
| 43 | Performance profiling | TEST | Verify all performance targets from Section 13.1. Profile shader compilation. Profile dual-frame prefetch memory. |
| 44 | `docs/DESIGN.md` | MODIFY | Add transition architecture section. |
| 45 | `docs/FEATURES.md` | MODIFY | Update transition feature status. |
| 46 | `docs/APP_LOGIC.md` | MODIFY | Add transition operation flow. |
| 47 | Codebase analysis | RUN | Analyze all new/modified files. Update `analysis/INDEX.md`. |

---

### 4. API Contract Verification

#### 4.1 Data Model Interfaces -- Complete

- `ClipTransition`: Fully specified in existing code (`transition.dart` lines 134-358). Extension with new enum values and properties is additive (no breaking changes).
- `TimelineState`: Fully specified in R2 C2 resolution. Immutable, structural sharing via `withTimeline`.
- `TransitionPreset`: Fully specified in Section 3.5.
- `TransitionCategory`: Fully specified in Section 3.4.

#### 4.2 Platform Channel Contract -- Complete

- Dart -> Swift: `buildComposition` with `segments` + `transitions` arrays. JSON schema fully specified in R2 C5 resolution.
- Swift `TransitionData.init(from:)`: Field-by-field mapping documented.
- Backward compatibility: Empty `transitions` array routes to existing single-track builder.

#### 4.3 Service APIs -- Complete with Gaps Noted

- `TransitionController` API: Fully specified in Section 5.2 (13 public methods).
- `TransitionRenderer` API: Specified in Section 5.3. **Gap:** The Canvas-based rendering path (R2 N5) needs a concrete API alongside the shader path. Recommend adding `TransitionCanvasRenderer` with same method signature.
- `TransitionCompositor` Swift API: Specified in Section 7.2. Conforms to `AVVideoCompositing` protocol.
- `TransitionInstruction` Swift API: Specified in Section 7.3. Conforms to `AVVideoCompositionInstructionProtocol`.

---

### 5. Test Plan Verification

The combined test coverage from the design document (Section 14.5) and R2 (Section 3) is comprehensive:

| Test Category | Files | Coverage Assessment |
|---------------|-------|-------------------|
| Model unit tests | `test/models/transition_test.dart` | All ClipTransition properties, serialization, new enum values |
| TimelineState unit tests | `test/models/timeline_state_test.dart` | CRUD, effective duration, time mapping, edit point cache |
| Controller unit tests | `test/core/transition_controller_test.dart` | Validation, CRUD, cascade operations, handle checking |
| Integration tests | `test/timeline/transition_integration_test.dart` | End-to-end workflows, undo/redo, serialization |
| Time mapping tests | In timeline_state_test.dart | Round-trip identity, multiple transitions, mixed alignments |
| Performance tests | In transition_integration_test.dart | Add/remove < 1ms, effective duration < 100us |
| Cascade tests | In transition_controller_test.dart | Delete cascade, split update, trim auto-reduce |

**Test gaps identified:**

1. **No shader compilation tests.** Add a test that loads each `.frag` file and verifies `FragmentProgram.fromAsset` succeeds without errors. This catches GLSL syntax errors at test time rather than runtime.
2. **No export integration tests.** The Swift `TransitionCompositor` cannot be unit tested in Dart. Recommend adding a Swift XCTest file (`TransitionCompositorTests.swift`) that verifies the compositor produces valid pixel buffers for each transition type with known input frames.
3. **No UI widget tests.** The `TransitionBrowserView` and `TransitionInspectorView` should have basic widget tests verifying they render without errors and respond to interactions.

---

### 6. Missing Specifications

Areas where an implementer would need to make assumptions without additional guidance:

| # | Area | What is Missing | Recommended Default |
|---|------|----------------|-------------------|
| MS1 | `TimelineState._editPointCache` mutability | R2 shows `Map<String, int>?` on an `@immutable` class. This is invalid Dart. | Compute eagerly in factory constructor and store as final field. Alternatively, use a top-level `computeEditPoints(TimelineState)` function. |
| MS2 | Canvas-based wipe rendering clipping strategy | R2 recommends Canvas for wipes but does not specify how soft-edge wipes work without shaders. | For soft-edge wipes, use a `MaskFilter.blur` on the clip rect path, or use a `Gradient` shader as a mask. If quality is insufficient, fall back to fragment shader for wipes with softness > 0. |
| MS3 | `TransitionCompositor` error handling for missing source frames | What happens if `sourceFrame(byTrackID:)` returns nil? | Return the available frame as passthrough. Log a warning. Do not crash the export. |
| MS4 | Transition preview animation frame rate in browser | Section 9.3 says "2-second loop" but does not specify the animation frame rate for the 80x60 thumbnail. | Use 15fps for browser previews (saves battery/CPU). Each preview runs its own `AnimationController` with `vsync` from a `TickerProvider`. |
| MS5 | `ScrubController` dual-frame compositing path | R1 I3 flagged this, R2 acknowledged but did not provide concrete code. | In `ScrubController.scrubTo`, after `itemAtTime` returns the primary clip, check `TransitionController.transitionAtTime(timeMicros)`. If non-null, also fetch the second clip's frame and invoke `TransitionRenderer.renderTransitionFrame`. Display the composited result. |
| MS6 | Handling of `buildWithTransitions` for timelines mixing video and non-video clips | The A/B interleaving algorithm assumes all segments are video. What about gaps, color clips, and audio-only clips? | Gaps and silence produce empty track regions (no `insertTimeRange`). Color clips require custom compositor support (out of scope per current `CompositionBuilder.swift` line 197). Transitions between a video clip and a color clip should use the color as a solid frame -- implement as a special case in `TransitionCompositor`. |

---

### 7. Answers to Review 1 Open Questions

| Q# | Question | Answer |
|----|----------|--------|
| Q1 | Which timeline system is the target? | V2 exclusively. R2 C1 resolution confirms this with adapter pattern for UI layer. |
| Q2 | Frame cache key for composited transition frames? | Composited frames are NOT cached. They are recomputed each paint cycle via Canvas or shader. This is acceptable because rendering cost is < 10ms. For rapid scrubbing, the underlying source frames (A and B) are cached individually. |
| Q3 | `cutPoint` vs `transition` HitType? | `HitType.cutPoint` is returned when tapping a cut point that has NO transition. `HitType.transition` is returned when tapping a cut point that HAS a transition. The existing `HitType.transition` (line 464 of `edit_operations.dart`) already exists for this purpose. |
| Q4 | Export progress reporting with transitions? | Use `AVAssetExportSession.progress` which handles the dual-track composition internally. No change to progress reporting needed. |
| Q5 | Zero-length visible clip between adjacent transitions? | Enforce minimum visible duration between adjacent transitions of `3 * frameDuration` (~100ms at 30fps). Add to `TransitionController.validateTransition` as: `clipDuration - leftOverlap - rightOverlap >= 3 * frameDurationMicros`. |
| Q6 | TransitionRenderer isolate? | Shader execution runs on the GPU thread via Flutter's rendering pipeline (part of `CustomPainter.paint()` on the main isolate). The GPU thread is separate from the main thread. Canvas-based rendering runs on the main isolate but is < 5ms for simple operations. No separate isolate needed. |

---

### 8. Final Assessment

**Verdict: GO -- with conditions.**

The design is thorough, well-reviewed, and the critical issues from Reviews 1 and 2 all have concrete resolution paths. The codebase is in good shape to receive this feature: the existing `ClipTransition` model is well-designed, the `TimelineManager` is cleanly structured for the `TimelineState` wrapper migration, and the `CompositionBuilder.swift` has clear extension points.

**Conditions for GO:**

1. **Fix MS1 before coding Phase 1A.** The `TimelineState._editPointCache` mutability issue must be resolved at design time, not discovered during implementation. Use eager computation in a factory constructor.
2. **R2's Phase 1A/1B split is mandatory.** Do NOT skip ahead to rendering (Phase 2) until all Phase 1 tests pass. The data layer is the foundation; bugs here cascade into every subsequent phase.
3. **Test on physical device starting Phase 5.** The iOS simulator does not accurately represent `AVVideoCompositing` timing behavior. All Phase 5 work must be validated on a real iPhone.
4. **GLSL version must be `#version 320 es`** across all shader files. Do not use `#version 460` as shown in the original design.
5. **Address MS5 (ScrubController dual-frame path) during Phase 2**, not deferred. Scrubbing through transitions without compositing will produce visual glitches that will confuse testers.

**Estimated timeline assessment:** The 16-23 day estimate is reasonable. With the Phase 1A/1B split adding ~1 day of overhead, expect 17-24 days. The highest-risk phase is Phase 5 (export integration) due to the complexity of `AVVideoCompositing` and CIKernel authoring.

**The design is approved for implementation.**

---

### 9. Remaining Open Questions

These are items that do not block implementation but should be decided during the relevant phase:

1. **Volume envelope merge strategy** (I2): Decide during Phase 6. Recommendation: multiply.
2. **Minimum visible clip duration between adjacent transitions** (Q5): The value of `3 * frameDuration` is a recommendation. UX testing may suggest a higher value (e.g., 200ms).
3. **Page curl CIKernel vs CIPageCurlTransition**: The built-in `CIPageCurlTransition` may have iOS version constraints. Verify availability on minimum deployment target during Phase 5.
4. **Shader warm-up subset**: Which shaders to warm up at launch (dissolve + wipe recommended) vs lazy-compile can be decided after profiling in Phase 7.
5. **Transition browser preview frame source**: When no clips are on the timeline, use stock gradient frames (blue-to-orange and orange-to-purple recommended for visual clarity).
