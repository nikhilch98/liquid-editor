# Video Effects System - Design Document

**Date:** 2026-02-06
**Author:** Claude Code (Opus 4.6)
**Status:** Draft - Pending Review
**Depends On:** Timeline Architecture V2, Keyframe System, CompositionBuilder, VideoProcessingService

---

## Table of Contents

1. [Overview](#1-overview)
2. [Effect System Architecture](#2-effect-system-architecture)
3. [Data Models](#3-data-models)
4. [Rendering Architecture](#4-rendering-architecture)
5. [Reverse Video](#5-reverse-video)
6. [Freeze Frame](#6-freeze-frame)
7. [Speed Ramp (Velocity Curve Editor)](#7-speed-ramp-velocity-curve-editor)
8. [Mirror/Flip](#8-mirrorflip)
9. [Crop & Aspect Ratio](#9-crop--aspect-ratio)
10. [Blur Effects](#10-blur-effects)
11. [Chroma Key (Green Screen)](#11-chroma-key-green-screen)
12. [Video Stabilization](#12-video-stabilization)
13. [Mask Effects](#13-mask-effects)
14. [Visual Effects (Stylistic)](#14-visual-effects-stylistic)
15. [Sharpen/Denoise](#15-sharpendenoise)
16. [Effect Stacking & Chain](#16-effect-stacking--chain)
17. [Keyframeable Effects](#17-keyframeable-effects)
18. [Effect Browser UI](#18-effect-browser-ui)
19. [Edge Cases](#19-edge-cases)
20. [Performance](#20-performance)
21. [Dependencies](#21-dependencies)
22. [Implementation Plan](#22-implementation-plan)

---

## 1. Overview

### Goals

The Video Effects System provides a composable, keyframeable, GPU-accelerated effects pipeline for Liquid Editor. Every effect operates as a self-contained unit that can be chained, reordered, enabled/disabled, and animated via the existing keyframe infrastructure. The system bridges Flutter (parameter editing, UI) and native iOS (CIFilter rendering, AVVideoComposition export) via platform channels.

### Scope

- 13 effect categories spanning time manipulation, spatial transforms, blur, color keying, stabilization, masks, and stylistic filters
- Per-clip effect chains with configurable ordering
- Full keyframe support for all numeric effect parameters
- Real-time GPU-accelerated preview at 60 FPS
- Lossless export pipeline via AVAssetWriter with CIFilter chains
- Native iOS 26 Liquid Glass UI for effect browsing and parameter editing

### Architecture Philosophy

1. **Effects are data, not behavior.** On the Dart side, effects are immutable value objects describing parameters. The native side interprets these parameters into CIFilter chains.
2. **Single rendering pipeline.** Both preview and export use the same CIFilter chain construction, differing only in output (display layer vs. AVAssetWriter).
3. **Immutability.** All effect models are `@immutable` Dart classes with `copyWith` methods, integrating with the existing O(1) undo/redo system.
4. **Separation of concerns.** Flutter owns UI and state; Swift owns rendering. Platform channels transmit serialized effect descriptions.

### Relationship to Existing Systems

| System | Relationship |
|--------|-------------|
| `TimelineClip` (UI model) | Already has `hasEffects`, `effectCount` flags; effect chain will be stored alongside clip |
| `VideoClip` (V2 data model) | Will gain an `effectChain` field (list of `VideoEffect` IDs or inline effect data) |
| `Keyframe` / `KeyframeTimeline` | Effect parameters reuse the same `InterpolationType` enum and interpolation engine |
| `CompositionBuilder.swift` | Will be extended to inject `AVVideoCompositionInstructionProtocol` with CIFilter logic |
| `VideoProcessingService.swift` | Will gain `applyEffects` methods for frame extraction with effects |
| `CompositionPlayerService.swift` | Preview playback will use `AVVideoComposition` with custom compositor |
| `VideoTransformCalculator.swift` | Existing transforms compose *before* the effect chain (transform is not an effect) |

---

## 2. Effect System Architecture

### 2.1 EffectNode Concept

Every effect is an `EffectNode`: a self-contained, serializable unit with:

- A unique identifier
- A type identifier (enum)
- An ordered list of typed parameters with defaults, ranges, and current values
- An enabled/disabled toggle
- A mix/intensity value (0.0-1.0) controlling blend with the input
- An optional list of effect-parameter keyframes

```
EffectNode
  id: String (UUID)
  type: EffectType (enum)
  isEnabled: bool
  mix: double (0.0 to 1.0, default 1.0)
  parameters: Map<String, EffectParameter>
  keyframes: List<EffectKeyframe>
```

### 2.2 Effect Chain

Each clip owns an `EffectChain`: an ordered list of `EffectNode` instances. Processing order matters -- the output of effect N is the input of effect N+1. The chain model is:

```
EffectChain
  clipId: String
  effects: List<EffectNode> (ordered, first = processed first)
```

The chain is conceptually a pipeline:

```
Source Frame --> [Transform] --> [Effect 0] --> [Effect 1] --> ... --> [Effect N] --> Output
```

Transform keyframes (existing `VideoTransform`) are applied BEFORE the effect chain. This means effects like blur operate on the already-transformed frame. This ordering is intentional: a user who zooms in and blurs expects blur to apply to the zoomed view.

### 2.3 Effect Registry

A static registry maps `EffectType` to:
- Display metadata (name, category, icon SF Symbol name, description)
- Default parameter set
- Native CIFilter name(s) or custom kernel identifier
- Whether it supports keyframing
- Whether it requires Vision framework analysis (face blur, stabilization)
- Minimum iOS version (most are iOS 11+, face detection is iOS 11+, person segmentation is iOS 15+)

```dart
enum EffectType {
  // Time
  reverse,
  freezeFrame,
  speedRamp,

  // Spatial
  mirrorHorizontal,
  mirrorVertical,
  crop,

  // Blur
  gaussianBlur,
  radialBlur,
  tiltShift,
  motionBlur,
  faceBlur,

  // Keying
  chromaKey,

  // Stabilization
  stabilization,

  // Masks
  shapeMask,
  drawMask,

  // Stylistic
  glitch,
  vhsRetro,
  filmGrain,
  lensFlare,
  lightLeaks,

  // Enhancement
  sharpen,
  unsharpMask,
  denoise,
}
```

### 2.4 Integration with Clip Model

The `VideoClip` class in `lib/models/clips/video_clip.dart` will gain:

```dart
@immutable
class VideoClip extends MediaClip {
  final List<Keyframe> keyframes;
  final String? name;
  final EffectChain effectChain;  // NEW
  // ...
}
```

The `TimelineClip` UI model already tracks `hasEffects` and `effectCount` as rendering metadata. These will be computed from the underlying `VideoClip.effectChain`.

### 2.5 Platform Channel Contract

A new method channel `com.liquideditor/effects` will handle:

| Method | Direction | Purpose |
|--------|-----------|---------|
| `applyEffectChain` | Dart -> Swift | Send serialized effect chain for preview rendering |
| `previewFrame` | Dart -> Swift | Request a single frame with effects applied |
| `analyzeForStabilization` | Dart -> Swift | Begin stabilization analysis |
| `analyzeForFaceBlur` | Dart -> Swift | Begin face detection for blur |
| `extractFreezeFrame` | Dart -> Swift | Extract frame at timestamp for freeze frame |
| `analysisProgress` | Swift -> Dart | Report analysis progress (stabilization, face detection) |
| `analysisComplete` | Swift -> Dart | Report analysis results |

---

## 3. Data Models

### 3.1 EffectParameter

```dart
/// Type of effect parameter value
enum EffectParameterType {
  double_,    // Numeric slider
  int_,       // Integer value
  bool_,      // Toggle
  color,      // Color picker
  point,      // 2D point (x, y)
  rect,       // Rectangle (x, y, w, h)
  path,       // Custom vector path (for masks)
  enumChoice, // Dropdown selection
}

/// A single effect parameter with type, range, and current value.
@immutable
class EffectParameter {
  final String name;
  final String displayName;
  final EffectParameterType type;
  final dynamic defaultValue;
  final dynamic currentValue;
  final dynamic minValue;        // null for non-numeric
  final dynamic maxValue;        // null for non-numeric
  final double? step;            // For sliders (null = continuous)
  final String? unit;            // Display unit ("px", "%", "deg")
  final bool isKeyframeable;     // Whether this parameter can be animated
  final List<String>? enumValues; // For enumChoice type

  const EffectParameter({
    required this.name,
    required this.displayName,
    required this.type,
    required this.defaultValue,
    required this.currentValue,
    this.minValue,
    this.maxValue,
    this.step,
    this.unit,
    this.isKeyframeable = true,
    this.enumValues,
  });

  EffectParameter copyWith({dynamic currentValue}) {
    return EffectParameter(
      name: name,
      displayName: displayName,
      type: type,
      defaultValue: defaultValue,
      currentValue: currentValue ?? this.currentValue,
      minValue: minValue,
      maxValue: maxValue,
      step: step,
      unit: unit,
      isKeyframeable: isKeyframeable,
      enumValues: enumValues,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'displayName': displayName,
    'type': type.name,
    'defaultValue': defaultValue,
    'currentValue': currentValue,
    'minValue': minValue,
    'maxValue': maxValue,
    'step': step,
    'unit': unit,
    'isKeyframeable': isKeyframeable,
    'enumValues': enumValues,
  };

  factory EffectParameter.fromJson(Map<String, dynamic> json) {
    return EffectParameter(
      name: json['name'] as String,
      displayName: json['displayName'] as String,
      type: EffectParameterType.values.firstWhere(
        (t) => t.name == json['type'],
      ),
      defaultValue: json['defaultValue'],
      currentValue: json['currentValue'],
      minValue: json['minValue'],
      maxValue: json['maxValue'],
      step: (json['step'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      isKeyframeable: json['isKeyframeable'] as bool? ?? true,
      enumValues: (json['enumValues'] as List?)?.cast<String>(),
    );
  }
}
```

### 3.2 EffectKeyframe

Reuses the existing `InterpolationType` enum. A keyframe captures the state of one or more parameters at a point in time relative to the clip start.

```dart
/// A keyframe for effect parameter animation.
@immutable
class EffectKeyframe {
  final String id;
  final Duration timestamp;             // Relative to clip start
  final Map<String, dynamic> values;    // parameter name -> value at this time
  final InterpolationType interpolation;
  final BezierControlPoints? bezierPoints;

  const EffectKeyframe({
    required this.id,
    required this.timestamp,
    required this.values,
    this.interpolation = InterpolationType.easeInOut,
    this.bezierPoints,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestampMs': timestamp.inMilliseconds,
    'values': values,
    'interpolation': interpolation.name,
    'bezierPoints': bezierPoints?.toJson(),
  };

  factory EffectKeyframe.fromJson(Map<String, dynamic> json) {
    return EffectKeyframe(
      id: json['id'] as String,
      timestamp: Duration(milliseconds: json['timestampMs'] as int),
      values: Map<String, dynamic>.from(json['values'] as Map),
      interpolation: InterpolationType.values.firstWhere(
        (e) => e.name == json['interpolation'],
        orElse: () => InterpolationType.easeInOut,
      ),
      bezierPoints: json['bezierPoints'] != null
          ? BezierControlPoints.fromJson(json['bezierPoints'] as Map<String, dynamic>)
          : null,
    );
  }
}
```

### 3.3 VideoEffect (EffectNode)

```dart
/// A single effect with its configuration and keyframes.
@immutable
class VideoEffect {
  final String id;
  final EffectType type;
  final bool isEnabled;
  final double mix;                               // 0.0-1.0, blend with original
  final Map<String, EffectParameter> parameters;
  final List<EffectKeyframe> keyframes;

  const VideoEffect({
    required this.id,
    required this.type,
    this.isEnabled = true,
    this.mix = 1.0,
    required this.parameters,
    this.keyframes = const [],
  });

  /// Get current parameter value, considering keyframes at [time].
  dynamic getParameterValue(String paramName, Duration time) {
    // If no keyframes, return current static value
    if (keyframes.isEmpty) {
      return parameters[paramName]?.currentValue;
    }
    // Interpolation logic (delegated to shared interpolation engine)
    // ... (see Section 17)
  }

  VideoEffect copyWith({
    bool? isEnabled,
    double? mix,
    Map<String, EffectParameter>? parameters,
    List<EffectKeyframe>? keyframes,
  }) {
    return VideoEffect(
      id: id,
      type: type,
      isEnabled: isEnabled ?? this.isEnabled,
      mix: mix ?? this.mix,
      parameters: parameters ?? this.parameters,
      keyframes: keyframes ?? this.keyframes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'isEnabled': isEnabled,
    'mix': mix,
    'parameters': parameters.map((k, v) => MapEntry(k, v.toJson())),
    'keyframes': keyframes.map((kf) => kf.toJson()).toList(),
  };

  factory VideoEffect.fromJson(Map<String, dynamic> json) {
    return VideoEffect(
      id: json['id'] as String,
      type: EffectType.values.firstWhere((t) => t.name == json['type']),
      isEnabled: json['isEnabled'] as bool? ?? true,
      mix: (json['mix'] as num?)?.toDouble() ?? 1.0,
      parameters: (json['parameters'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, EffectParameter.fromJson(v as Map<String, dynamic>)),
      ),
      keyframes: (json['keyframes'] as List?)
          ?.map((kf) => EffectKeyframe.fromJson(kf as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}
```

### 3.4 EffectChain

```dart
/// Ordered list of effects applied to a clip.
@immutable
class EffectChain {
  final List<VideoEffect> effects;

  const EffectChain({this.effects = const []});

  /// Number of enabled effects.
  int get enabledCount => effects.where((e) => e.isEnabled).length;

  /// Whether chain has any enabled effects.
  bool get hasEnabledEffects => effects.any((e) => e.isEnabled);

  /// Add effect at end of chain.
  EffectChain addEffect(VideoEffect effect) =>
      EffectChain(effects: [...effects, effect]);

  /// Remove effect by ID.
  EffectChain removeEffect(String effectId) =>
      EffectChain(effects: effects.where((e) => e.id != effectId).toList());

  /// Move effect from [oldIndex] to [newIndex].
  EffectChain reorderEffect(int oldIndex, int newIndex) {
    final list = List<VideoEffect>.from(effects);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    return EffectChain(effects: list);
  }

  /// Update a specific effect.
  EffectChain updateEffect(VideoEffect updated) => EffectChain(
    effects: effects.map((e) => e.id == updated.id ? updated : e).toList(),
  );

  /// Toggle an effect on/off.
  EffectChain toggleEffect(String effectId) => EffectChain(
    effects: effects.map((e) =>
      e.id == effectId ? e.copyWith(isEnabled: !e.isEnabled) : e
    ).toList(),
  );

  Map<String, dynamic> toJson() => {
    'effects': effects.map((e) => e.toJson()).toList(),
  };

  factory EffectChain.fromJson(Map<String, dynamic> json) {
    return EffectChain(
      effects: (json['effects'] as List)
          .map((e) => VideoEffect.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
```

### 3.5 SpeedRamp Model

Speed ramps require a specialized model since they replace simple constant-speed playback with a velocity curve.

```dart
/// A control point on the velocity curve.
@immutable
class SpeedControlPoint {
  /// Position in clip (0.0 = start, 1.0 = end), normalized.
  final double normalizedTime;

  /// Speed multiplier at this point (0.1 to 8.0).
  final double speed;

  /// Interpolation to next point.
  final InterpolationType interpolation;

  const SpeedControlPoint({
    required this.normalizedTime,
    required this.speed,
    this.interpolation = InterpolationType.easeInOut,
  });

  Map<String, dynamic> toJson() => {
    'normalizedTime': normalizedTime,
    'speed': speed,
    'interpolation': interpolation.name,
  };

  factory SpeedControlPoint.fromJson(Map<String, dynamic> json) {
    return SpeedControlPoint(
      normalizedTime: (json['normalizedTime'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      interpolation: InterpolationType.values.firstWhere(
        (e) => e.name == json['interpolation'],
        orElse: () => InterpolationType.easeInOut,
      ),
    );
  }
}

/// A velocity curve for variable speed playback.
@immutable
class SpeedRamp {
  /// Control points defining the velocity curve, sorted by normalizedTime.
  /// Must have at least 2 points (start and end).
  final List<SpeedControlPoint> controlPoints;

  /// Whether to maintain audio pitch during speed changes.
  final bool maintainPitch;

  const SpeedRamp({
    required this.controlPoints,
    this.maintainPitch = true,
  });

  /// Calculate speed at a normalized position (0.0-1.0).
  double speedAt(double normalizedTime) {
    if (controlPoints.isEmpty) return 1.0;
    if (controlPoints.length == 1) return controlPoints.first.speed;

    // Find surrounding control points
    SpeedControlPoint? before;
    SpeedControlPoint? after;

    for (int i = 0; i < controlPoints.length; i++) {
      if (controlPoints[i].normalizedTime <= normalizedTime) {
        before = controlPoints[i];
      }
      if (controlPoints[i].normalizedTime >= normalizedTime && after == null) {
        after = controlPoints[i];
      }
    }

    if (before == null) return controlPoints.first.speed;
    if (after == null) return controlPoints.last.speed;
    if (before == after) return before.speed;

    // Interpolate
    final t = (normalizedTime - before.normalizedTime) /
        (after.normalizedTime - before.normalizedTime);
    // Apply easing via shared interpolation engine
    return before.speed + (after.speed - before.speed) * t;
  }

  /// Calculate the total output duration given source duration.
  /// Integrates 1/speed across the curve.
  int calculateOutputDurationMicros(int sourceDurationMicros) {
    // Numerical integration: divide curve into N segments
    const segments = 100;
    double totalTime = 0;
    final segmentDuration = sourceDurationMicros / segments;

    for (int i = 0; i < segments; i++) {
      final t = (i + 0.5) / segments;
      final speed = speedAt(t);
      totalTime += segmentDuration / speed;
    }

    return totalTime.round();
  }

  /// Preset: Linear ramp from slow to fast.
  factory SpeedRamp.rampUp({double startSpeed = 0.5, double endSpeed = 2.0}) {
    return SpeedRamp(controlPoints: [
      SpeedControlPoint(normalizedTime: 0.0, speed: startSpeed),
      SpeedControlPoint(normalizedTime: 1.0, speed: endSpeed),
    ]);
  }

  /// Preset: Ease in, hold fast, ease out.
  factory SpeedRamp.pulse({double holdSpeed = 0.25}) {
    return SpeedRamp(controlPoints: [
      SpeedControlPoint(normalizedTime: 0.0, speed: 1.0),
      SpeedControlPoint(normalizedTime: 0.3, speed: holdSpeed,
          interpolation: InterpolationType.easeIn),
      SpeedControlPoint(normalizedTime: 0.7, speed: holdSpeed,
          interpolation: InterpolationType.easeOut),
      SpeedControlPoint(normalizedTime: 1.0, speed: 1.0),
    ]);
  }

  Map<String, dynamic> toJson() => {
    'controlPoints': controlPoints.map((cp) => cp.toJson()).toList(),
    'maintainPitch': maintainPitch,
  };

  factory SpeedRamp.fromJson(Map<String, dynamic> json) {
    return SpeedRamp(
      controlPoints: (json['controlPoints'] as List)
          .map((cp) => SpeedControlPoint.fromJson(cp as Map<String, dynamic>))
          .toList(),
      maintainPitch: json['maintainPitch'] as bool? ?? true,
    );
  }
}
```

### 3.6 CropRect Model

```dart
/// Crop rectangle with aspect ratio support.
@immutable
class CropRect {
  /// Normalized crop rectangle (0.0-1.0 relative to source frame).
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// Locked aspect ratio (null = free crop).
  final CropAspectRatio? aspectRatio;

  const CropRect({
    this.left = 0.0,
    this.top = 0.0,
    this.right = 1.0,
    this.bottom = 1.0,
    this.aspectRatio,
  });

  /// Identity crop (no cropping).
  static const CropRect identity = CropRect();

  double get width => right - left;
  double get height => bottom - top;
  bool get isIdentity =>
      left == 0.0 && top == 0.0 && right == 1.0 && bottom == 1.0;

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'aspectRatio': aspectRatio?.name,
  };

  factory CropRect.fromJson(Map<String, dynamic> json) {
    return CropRect(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
      aspectRatio: json['aspectRatio'] != null
          ? CropAspectRatio.values.firstWhere(
              (r) => r.name == json['aspectRatio'],
              orElse: () => CropAspectRatio.free,
            )
          : null,
    );
  }
}

/// Preset aspect ratios for cropping.
enum CropAspectRatio {
  free,       // No constraint
  ratio16x9,  // 16:9 Landscape
  ratio9x16,  // 9:16 Portrait (TikTok, Reels)
  ratio1x1,   // 1:1 Square (Instagram)
  ratio4x3,   // 4:3 Classic
  ratio3x4,   // 3:4 Portrait classic
  ratio4x5,   // 4:5 Portrait (Instagram)
  ratio235x1, // 2.35:1 Cinemascope
  original,   // Source aspect ratio
}
```

### 3.7 MaskShape Model

```dart
/// Types of mask shapes.
enum MaskShapeType {
  rectangle,
  ellipse,
  polygon,
  customPath,
}

/// A mask definition for selective effect application.
@immutable
class MaskShape {
  final String id;
  final MaskShapeType shapeType;

  /// Normalized bounding rect (0.0-1.0).
  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final double rotation;          // Radians

  /// Feather amount (0.0 = hard edge, 1.0 = fully soft).
  final double feather;

  /// Whether the mask is inverted (effect outside mask instead of inside).
  final bool isInverted;

  /// Custom path points for polygon/customPath types (normalized coordinates).
  final List<Offset>? pathPoints;

  /// Corner radius for rectangle masks (normalized, 0.0-0.5).
  final double cornerRadius;

  const MaskShape({
    required this.id,
    required this.shapeType,
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.width = 0.5,
    this.height = 0.5,
    this.rotation = 0.0,
    this.feather = 0.1,
    this.isInverted = false,
    this.pathPoints,
    this.cornerRadius = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'shapeType': shapeType.name,
    'centerX': centerX,
    'centerY': centerY,
    'width': width,
    'height': height,
    'rotation': rotation,
    'feather': feather,
    'isInverted': isInverted,
    'pathPoints': pathPoints?.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'cornerRadius': cornerRadius,
  };

  factory MaskShape.fromJson(Map<String, dynamic> json) {
    return MaskShape(
      id: json['id'] as String,
      shapeType: MaskShapeType.values.firstWhere(
        (t) => t.name == json['shapeType'],
      ),
      centerX: (json['centerX'] as num).toDouble(),
      centerY: (json['centerY'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      feather: (json['feather'] as num?)?.toDouble() ?? 0.1,
      isInverted: json['isInverted'] as bool? ?? false,
      pathPoints: (json['pathPoints'] as List?)
          ?.map((p) => Offset(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ))
          .toList(),
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
```

### 3.8 ChromaKeyConfig Model

```dart
/// Configuration for chroma key (green screen) effect.
@immutable
class ChromaKeyConfig {
  /// Key color in ARGB32 format.
  final int keyColor;

  /// Hue tolerance (0.0-1.0). Higher = more colors keyed out.
  final double hueTolerance;

  /// Saturation tolerance (0.0-1.0).
  final double saturationTolerance;

  /// Luminance tolerance (0.0-1.0).
  final double luminanceTolerance;

  /// Edge softness (0.0 = hard, 1.0 = very soft).
  final double edgeSoftness;

  /// Spill suppression strength (0.0-1.0).
  /// Removes color contamination from the key color on edges.
  final double spillSuppression;

  /// Alpha channel noise reduction (0.0-1.0).
  final double denoiseAlpha;

  /// Preview mode for debugging.
  final ChromaKeyPreviewMode previewMode;

  const ChromaKeyConfig({
    this.keyColor = 0xFF00FF00,  // Default: pure green
    this.hueTolerance = 0.3,
    this.saturationTolerance = 0.3,
    this.luminanceTolerance = 0.3,
    this.edgeSoftness = 0.1,
    this.spillSuppression = 0.5,
    this.denoiseAlpha = 0.0,
    this.previewMode = ChromaKeyPreviewMode.composite,
  });

  Map<String, dynamic> toJson() => {
    'keyColor': keyColor,
    'hueTolerance': hueTolerance,
    'saturationTolerance': saturationTolerance,
    'luminanceTolerance': luminanceTolerance,
    'edgeSoftness': edgeSoftness,
    'spillSuppression': spillSuppression,
    'denoiseAlpha': denoiseAlpha,
    'previewMode': previewMode.name,
  };

  factory ChromaKeyConfig.fromJson(Map<String, dynamic> json) {
    return ChromaKeyConfig(
      keyColor: json['keyColor'] as int? ?? 0xFF00FF00,
      hueTolerance: (json['hueTolerance'] as num?)?.toDouble() ?? 0.3,
      saturationTolerance: (json['saturationTolerance'] as num?)?.toDouble() ?? 0.3,
      luminanceTolerance: (json['luminanceTolerance'] as num?)?.toDouble() ?? 0.3,
      edgeSoftness: (json['edgeSoftness'] as num?)?.toDouble() ?? 0.1,
      spillSuppression: (json['spillSuppression'] as num?)?.toDouble() ?? 0.5,
      denoiseAlpha: (json['denoiseAlpha'] as num?)?.toDouble() ?? 0.0,
      previewMode: ChromaKeyPreviewMode.values.firstWhere(
        (m) => m.name == json['previewMode'],
        orElse: () => ChromaKeyPreviewMode.composite,
      ),
    );
  }
}

enum ChromaKeyPreviewMode {
  composite,      // Normal composite (keyed clip over transparent)
  alphaMatte,     // Show alpha channel as grayscale
  checkerboard,   // Show transparent areas as checkerboard
  originalColor,  // Show original with key overlay
}
```

---

## 4. Rendering Architecture

### 4.1 Preview Rendering

Preview rendering uses a custom `AVVideoComposition` with a `CIFilter`-based compositor.

**Architecture:**

```
AVPlayer
  |
  AVPlayerItem
  |  |
  |  AVVideoComposition (custom)
  |    |
  |    CustomVideoCompositor (AVVideoCompositing protocol)
  |      |
  |      For each frame:
  |        1. Get source pixel buffer
  |        2. Apply transform (existing VideoTransformCalculator)
  |        3. Build CIFilter chain from effect list
  |        4. Render CIFilter chain to output pixel buffer
  |        5. Apply mix (CIBlendWithAlphaMask or manual blend)
  |        6. Return composited frame
  |
  AVPlayerLayer (displayed in CompositionPlayerPlatformView)
```

**Custom Compositor (Swift):**

```swift
class EffectVideoCompositor: NSObject, AVVideoCompositing {
    /// The CIContext for GPU-accelerated rendering.
    private let ciContext = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        .useSoftwareRenderer: false,  // Force GPU
    ])

    /// Cached CIFilter instances (creating filters is cheap, but reuse avoids overhead)
    private var filterCache: [String: CIFilter] = [:]

    /// Current effect chain description (updated from Flutter via composition rebuild)
    var effectChainDescription: [[String: Any]] = []

    // AVVideoCompositing protocol implementation
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) { }

    var sourcePixelBufferAttributes: [String: Any]? {
        return [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        return [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        // 1. Extract source frame
        // 2. Build CIFilter chain
        // 3. Render to output pixel buffer
        // 4. Complete request
    }
}
```

### 4.2 Export Rendering

Export rendering uses `AVAssetWriter` with an `AVAssetWriterInputPixelBufferAdaptor`. For each frame:

1. Read source frame via `AVAssetReader`
2. Create `CIImage` from pixel buffer
3. Apply the same CIFilter chain as preview
4. Render to pixel buffer via `CIContext.render(_:to:)`
5. Append to `AVAssetWriterInput`

Alternatively, when the effect chain contains only built-in CIFilters (no custom Metal kernels), we can use `AVVideoComposition` with the custom compositor directly in `AVAssetExportSession`, which is simpler and leverages Apple's optimized pipeline.

### 4.3 CIFilter Chain Construction

```swift
/// Builds a CIFilter chain from a serialized effect chain.
func buildFilterChain(
    from effects: [[String: Any]],
    inputImage: CIImage,
    frameTime: CMTime,
    frameSize: CGSize
) -> CIImage {
    var currentImage = inputImage

    for effectData in effects {
        guard let enabled = effectData["isEnabled"] as? Bool, enabled else { continue }
        guard let typeName = effectData["type"] as? String else { continue }

        let mix = effectData["mix"] as? Double ?? 1.0
        let params = effectData["parameters"] as? [String: Any] ?? [:]

        // Resolve keyframed parameter values at frameTime
        let resolvedParams = resolveKeyframes(params, at: frameTime)

        // Build CIFilter for this effect type
        let filtered = applyEffect(
            type: typeName,
            input: currentImage,
            parameters: resolvedParams,
            frameSize: frameSize
        )

        // Apply mix (blend with original)
        if mix < 1.0 {
            currentImage = blendImages(
                original: currentImage,
                filtered: filtered,
                amount: mix
            )
        } else {
            currentImage = filtered
        }
    }

    return currentImage
}
```

### 4.4 Effect Ordering and Transform Composition

The processing order for a single frame is:

```
1. Decode source frame from AVAsset
2. Apply speed/time mapping (determines WHICH source frame)
3. Apply transform keyframes (scale, position, rotation via VideoTransformCalculator)
4. Apply effect chain in order:
   a. Spatial effects (crop, mirror/flip)
   b. Correction effects (stabilization, denoise, sharpen)
   c. Creative effects (blur, chroma key, color grading)
   d. Stylistic effects (glitch, VHS, grain, flare)
5. Output composited frame
```

The user can reorder effects within the chain, but the default insertion order follows the pattern above. The UI will warn when certain orderings are suboptimal (e.g., blur after sharpen largely cancels out).

### 4.5 GPU vs CPU Rendering

| Effect | Renderer | CIFilter/Kernel |
|--------|----------|-----------------|
| Gaussian Blur | GPU | `CIGaussianBlur` |
| Radial Blur | GPU | `CIRadialGradient` + `CIMaskedVariableBlur` |
| Tilt-Shift | GPU | `CILinearGradient` + `CIMaskedVariableBlur` |
| Motion Blur | GPU | `CIMotionBlur` |
| Face Blur | GPU + Neural Engine | Vision `VNDetectFaceRectanglesRequest` + `CIGaussianBlur` + mask |
| Chroma Key | GPU | Custom `CIColorKernel` |
| Mirror/Flip | GPU | `CIAffineTransform` |
| Crop | GPU | `CICrop` + `CIAffineTransform` |
| Sharpen | GPU | `CISharpenLuminance` |
| Unsharp Mask | GPU | `CIUnsharpMask` |
| Denoise | GPU | `CINoiseReduction` |
| Stabilization | GPU (per-frame transform) | `CIAffineTransform` (from precomputed stabilization data) |
| Glitch | GPU | Custom `CIKernel` (Metal) |
| VHS/Retro | GPU | Custom `CIKernel` (Metal) + `CIColorMatrix` |
| Film Grain | GPU | `CIRandomGenerator` + `CIBlendWithMask` |
| Lens Flare | GPU | Custom `CIKernel` (Metal) |
| Light Leaks | GPU | Prerendered overlay + `CIScreenBlendMode` |

---

## 5. Reverse Video

### Implementation Strategy

Reverse is a property of the clip rather than a CIFilter effect. The `TimelineClip` model already has an `isReversed: bool` field and `toggleReverse()` method.

### Native Implementation

On the native side, reverse playback is achieved by reading frames in reverse order:

1. **Preview:** Use `AVPlayerItem` with a negative `rate`. However, `AVPlayer` reverse playback is limited and may drop frames. The preferred approach is to pre-generate a reversed composition segment using `AVAssetReader` reading frames from end to start, writing them to a new `AVAssetWriter` output.

2. **Export:** Use `AVAssetReader` with `outputSettings` configured for reverse time range. Read all video frames into a buffer, then write them in reverse order to `AVAssetWriter`.

3. **Efficient approach:** Use `AVMutableComposition` time mapping. Create a composition track and use `scaleTimeRange(_:toDuration:)` with a negative duration is not supported. Instead, use `AVAssetReader` to read frames, store in a temporary file in reverse order, then reference that file.

**Recommended approach (most performant):**

```swift
/// Reverse a video segment by re-encoding frames in reverse order.
func reverseVideoSegment(
    asset: AVAsset,
    sourceIn: CMTime,
    sourceOut: CMTime
) async throws -> URL {
    let reader = try AVAssetReader(asset: asset)
    let videoTrack = asset.tracks(withMediaType: .video).first!

    let readerOutput = AVAssetReaderTrackOutput(
        track: videoTrack,
        outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
    )
    readerOutput.supportsRandomAccess = true  // Required for reverse reading
    reader.timeRange = CMTimeRange(start: sourceIn, end: sourceOut)
    reader.add(readerOutput)
    reader.startReading()

    // Collect all sample buffers
    var sampleBuffers: [CMSampleBuffer] = []
    while let buffer = readerOutput.copyNextSampleBuffer() {
        sampleBuffers.append(buffer)
    }

    // Write in reverse order
    // ... (AVAssetWriter setup, iterate sampleBuffers.reversed)
}
```

### Audio Handling

- **Default:** Mute audio when reversed (most common user expectation)
- **Option:** Reverse audio (eerie effect, available as toggle)
- **Option:** Replace with original forward audio (useful for some creative effects)

User selects via a toggle in the clip inspector: "Reverse Audio: Off / Reversed / Original"

### Impact on Timeline

- `TimelineClip.isReversed` flag controls preview direction
- `TimelineClip.timelineToSource()` already handles reversed mapping (line 178-184 in `timeline_clip.dart`)
- Duration remains unchanged
- Thumbnails should show reversed frame order (regenerate on toggle)

### Interaction with Speed Control

Reverse + speed works naturally. A reversed clip at 2x plays backward at double speed. The `speed` and `isReversed` fields are independent.

### Interaction with Speed Ramp

Reverse + speed ramp: the velocity curve is evaluated in reverse. If `isReversed` is true, the curve's time axis is flipped.

---

## 6. Freeze Frame

### Implementation

Freeze frame extracts a single frame at the playhead position and inserts it as an `ImageClip` on the timeline.

### Workflow

1. User positions playhead at desired frame
2. Taps "Freeze Frame" action (in clip inspector or context menu)
3. System extracts frame using `AVAssetImageGenerator` at exact timestamp
4. User chooses duration via a Cupertino picker (default: 2 seconds)
5. User chooses insert mode:
   - **Insert:** Split clip at playhead, insert ImageClip between halves (extends total timeline duration)
   - **Replace:** Replace a portion of the clip from playhead to playhead + duration with the frozen frame

### Native Frame Extraction

```swift
func extractFreezeFrame(
    assetPath: String,
    timestampMicros: Int,
    result: @escaping FlutterResult
) {
    let asset = AVAsset(url: URL(fileURLWithPath: assetPath))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    // Use maximum quality for freeze frames
    generator.maximumSize = .zero  // Full resolution

    let time = CMTime(value: CMTimeValue(timestampMicros), timescale: 1_000_000)

    DispatchQueue.global(qos: .userInitiated).async {
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            // Save as PNG to app's documents directory
            let outputURL = /* documents dir + UUID.png */
            let uiImage = UIImage(cgImage: cgImage)
            try uiImage.pngData()?.write(to: outputURL)

            DispatchQueue.main.async {
                result(outputURL.path)
            }
        } catch {
            DispatchQueue.main.async {
                result(FlutterError(code: "FREEZE_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }
}
```

### Timeline Integration

For the "Insert" mode using the existing clip split infrastructure:

```dart
void insertFreezeFrame({
  required String clipId,
  required Duration playheadPosition,
  required Duration freezeDuration,
  required String extractedFramePath,
}) {
  // 1. Split the clip at playhead
  final splitResult = clip.splitAt(playheadOffsetMicros);

  // 2. Create ImageClip for the freeze frame
  final freezeClip = ImageClip(
    id: Uuid().v4(),
    mediaAssetId: extractedFrameAssetId,
    durationMicroseconds: freezeDuration.inMicroseconds,
  );

  // 3. Insert: [leftClip, freezeClip, rightClip]
  // Use TimelineManager to perform atomic insert
}
```

### Storage

Extracted frames are saved to the project's media directory as PNG files and registered as `MediaAsset` entries (type: image). This ensures they persist with the project and can be relinked.

---

## 7. Speed Ramp (Velocity Curve Editor)

### Concept

A speed ramp replaces the clip's constant `speed` value with a `SpeedRamp` velocity curve. The curve maps normalized clip time (0.0-1.0) to a speed multiplier.

### Data Flow

```
User edits curve in Flutter UI
  |
  SpeedRamp model updated (immutable, undo-safe)
  |
  Total output duration recalculated
  |
  TimelineClip.duration updated
  |
  Native side receives SpeedRamp for composition building:
    - Creates multiple AVMutableComposition time mapping segments
    - Each segment has a constant speed (piecewise linear approximation)
```

### Velocity Curve Editor UI

The curve editor is a custom Flutter widget rendered below the video preview:

```
+--------------------------------------+
|  Video Preview                       |
+--------------------------------------+
|  Speed Curve Editor                  |
|                                      |
|  3x ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  |
|       /\                             |
|  2x  /  \          /\               |
|     /    \        /  \              |
|  1x/      \──────/    \             |
|                        \            |
|  0.5x                  \──         |
|  |----|----|----|----|----|----|     |
|  0s   1s   2s   3s   4s   5s  6s   |
|                                      |
|  [Linear] [Ease] [Pulse] [Custom]   |
+--------------------------------------+
```

**UI Features:**
- Drag control points vertically to change speed
- Drag horizontally to change position in time
- Tap on curve to add a new control point
- Long-press control point to delete
- Preset buttons at bottom (Linear Ramp Up, Linear Ramp Down, Ease In/Out, Pulse, Smooth Slow-Mo)
- Real-time duration recalculation displayed
- Haptic feedback on control point snap to 0.25x increments

### Audio Handling

| Mode | Behavior | Use Case |
|------|----------|----------|
| Maintain Pitch (default) | Time-stretch audio using `AVAudioTimePitchAlgorithm.spectral` | Dialogue, music |
| Pitch Shift | Audio pitch follows speed (chipmunk/deep) | Creative effects |
| Mute Audio | Remove audio during ramp | Action sequences |

### Native Export Implementation

Speed ramps are implemented by segmenting the velocity curve into piecewise constant segments and creating `CMTimeMapping` entries:

```swift
func buildSpeedRampComposition(
    asset: AVAsset,
    sourceRange: CMTimeRange,
    speedRamp: [[String: Any]]  // Array of {startTime, endTime, speed} segments
) -> AVMutableComposition {
    let composition = AVMutableComposition()
    // ...
    for segment in speedRamp {
        let sourceStart = segment["sourceStart"] as! CMTime
        let sourceDuration = segment["sourceDuration"] as! CMTime
        let speed = segment["speed"] as! Double

        let outputDuration = CMTimeMultiplyByFloat64(sourceDuration, multiplier: 1.0 / speed)

        // Insert segment with time mapping
        let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)
        // Use scaledDuration to create time-stretched segment
        track.insertTimeRange(sourceRange, of: sourceTrack, at: currentTime)
        track.scaleTimeRange(
            CMTimeRange(start: currentTime, duration: sourceDuration),
            toDuration: outputDuration
        )
        currentTime = CMTimeAdd(currentTime, outputDuration)
    }
    return composition
}
```

### Interaction with Existing Speed Control

The speed ramp *replaces* the constant speed value. When a speed ramp is active:
- The clip's `speed` field is set to `1.0` (nominal)
- The `SpeedRamp` model fully controls playback speed
- The speed control sheet (existing `SpeedControlSheet`) shows "Speed Ramp Active" and provides a button to edit the curve or revert to constant speed

---

## 8. Mirror/Flip

### Implementation

Mirror and flip are simple spatial transforms applied as part of the effect chain.

### Parameters

| Parameter | Type | Default | Range |
|-----------|------|---------|-------|
| `flipHorizontal` | bool | false | on/off |
| `flipVertical` | bool | false | on/off |

### Native Rendering

```swift
func applyMirrorFlip(
    input: CIImage,
    flipH: Bool,
    flipV: Bool
) -> CIImage {
    var transform = CGAffineTransform.identity
    let extent = input.extent

    if flipH {
        transform = transform
            .translatedBy(x: extent.width, y: 0)
            .scaledBy(x: -1, y: 1)
    }
    if flipV {
        transform = transform
            .translatedBy(x: 0, y: extent.height)
            .scaledBy(x: 1, y: -1)
    }

    return input.transformed(by: transform)
}
```

### Interaction with Transform Keyframes

Mirror/flip is applied AFTER the existing `VideoTransform` keyframes. This means if a user has scaled and translated the video, the flip operates on the already-transformed frame. This is the intuitive behavior: "flip what I see."

### Toggle Behavior

Mirror/flip are toggle effects (not gradual). They are not keyframeable -- a clip is either flipped or not. Animating a flip would be disorienting and has no practical use case.

---

## 9. Crop & Aspect Ratio

### Implementation

Crop is implemented as a CIFilter chain: `CICrop` to select the region, then `CIAffineTransform` to scale the cropped region to fill the output frame.

### Parameters

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `cropRect` | CropRect | identity | 0.0-1.0 normalized | Yes |
| `aspectRatio` | CropAspectRatio | free | enum | No |
| `fillMode` | CropFillMode | zoomToFill | enum | No |

```dart
enum CropFillMode {
  zoomToFill,   // Zoom cropped region to fill output (no black bars)
  letterbox,    // Fit with letterbox/pillarbox (preserve aspect ratio)
}
```

### UI Design

The crop tool overlays a resizable rectangle on the video preview:

```
+--------------------------------------+
|  Video Preview                       |
|  +-----dimmed-area--+                |
|  |  +===========+   |  Dimmed area   |
|  |  ||  Crop   ||   |  outside crop  |
|  |  ||  Area   ||   |  is semi-      |
|  |  ||  -----  ||   |  transparent   |
|  |  || |     | ||   |                |
|  |  || | R3  | ||   |  Rule of       |
|  |  || |     | ||   |  thirds grid   |
|  |  +===========+   |                |
|  +------------------+                |
|                                      |
|  [Free] [16:9] [9:16] [1:1] [4:3]   |
+--------------------------------------+
```

**UI Features:**
- Draggable corners and edges (Cupertino-style handles)
- Rule of thirds grid overlay during crop adjustment
- Aspect ratio preset buttons along the bottom
- Double-tap to reset to original
- Pinch gesture to zoom crop area
- Pan to reposition crop within source frame
- Grid snapping (snap to center, thirds, edges) with haptic feedback

### Per-Clip vs Project-Level

- **Per-clip crop:** Applied as an effect in the clip's effect chain. Each clip can have its own crop.
- **Project-level aspect ratio:** Set in project settings. This defines the output canvas. Per-clip crops operate within this canvas.

When a clip's crop aspect ratio differs from the project aspect ratio, the `fillMode` determines whether to zoom or letterbox.

### Keyframeable Crop

The crop rectangle can be animated via keyframes, enabling:
- Ken Burns effect (slow pan/zoom across a photo or video)
- Animated reframing (smooth transition from wide to close-up)
- Dynamic aspect ratio transitions

### Native Rendering

```swift
func applyCrop(
    input: CIImage,
    cropRect: CGRect,      // Normalized (0-1)
    outputSize: CGSize,
    fillMode: String
) -> CIImage {
    let extent = input.extent

    // Convert normalized rect to pixel coordinates
    let pixelRect = CGRect(
        x: cropRect.origin.x * extent.width,
        y: cropRect.origin.y * extent.height,
        width: cropRect.width * extent.width,
        height: cropRect.height * extent.height
    )

    // Crop
    var cropped = input.cropped(to: pixelRect)

    // Translate to origin
    cropped = cropped.transformed(by: CGAffineTransform(
        translationX: -pixelRect.origin.x,
        y: -pixelRect.origin.y
    ))

    // Scale to fill output
    if fillMode == "zoomToFill" {
        let scaleX = outputSize.width / pixelRect.width
        let scaleY = outputSize.height / pixelRect.height
        let scale = max(scaleX, scaleY)
        cropped = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    return cropped
}
```

---

## 10. Blur Effects

### 10.1 Gaussian Blur

**CIFilter:** `CIGaussianBlur`

| Parameter | Type | Default | Range | Unit |
|-----------|------|---------|-------|------|
| `radius` | double | 10.0 | 0.0 - 100.0 | px |

```swift
let filter = CIFilter(name: "CIGaussianBlur")!
filter.setValue(inputImage, forKey: kCIInputImageKey)
filter.setValue(radius, forKey: kCIInputRadiusKey)
// Clamp to extent to prevent edge artifacts
let clamped = inputImage.clampedToExtent()
filter.setValue(clamped, forKey: kCIInputImageKey)
return filter.outputImage!.cropped(to: inputImage.extent)
```

### 10.2 Radial Blur

**Implementation:** `CIRadialGradient` (mask) + `CIMaskedVariableBlur`

Creates a clear center that fades to blurred edges (tilt-shift around a point).

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `centerX` | double | 0.5 | 0.0 - 1.0 | Yes |
| `centerY` | double | 0.5 | 0.0 - 1.0 | Yes |
| `innerRadius` | double | 0.2 | 0.0 - 1.0 | Yes |
| `outerRadius` | double | 0.6 | 0.0 - 1.0 | Yes |
| `blurRadius` | double | 20.0 | 0.0 - 100.0 | Yes |

```swift
// Create radial gradient mask (white center, black edges)
let gradient = CIFilter(name: "CIRadialGradient")!
gradient.setValue(CIVector(x: centerX * width, y: centerY * height), forKey: "inputCenter")
gradient.setValue(innerRadius * min(width, height), forKey: "inputRadius0")
gradient.setValue(outerRadius * min(width, height), forKey: "inputRadius1")
gradient.setValue(CIColor.white, forKey: "inputColor0")
gradient.setValue(CIColor.black, forKey: "inputColor1")

// Variable blur using gradient as mask
let variableBlur = CIFilter(name: "CIMaskedVariableBlur")!
variableBlur.setValue(inputImage.clampedToExtent(), forKey: kCIInputImageKey)
variableBlur.setValue(gradient.outputImage!, forKey: "inputMask")
variableBlur.setValue(blurRadius, forKey: kCIInputRadiusKey)
```

### 10.3 Tilt-Shift

**Implementation:** `CILinearGradient` (mask) + `CIMaskedVariableBlur`

Two parallel lines define a focus band; everything above and below is blurred.

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `focusCenterY` | double | 0.5 | 0.0 - 1.0 | Yes |
| `focusWidth` | double | 0.3 | 0.0 - 1.0 | Yes |
| `blurRadius` | double | 15.0 | 0.0 - 80.0 | Yes |
| `angle` | double | 0.0 | -pi to pi | Yes |

The mask is constructed by combining two linear gradients: one fading from the top edge of the focus band upward, and one fading from the bottom edge downward.

### 10.4 Motion Blur

**CIFilter:** `CIMotionBlur`

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `radius` | double | 10.0 | 0.0 - 100.0 | Yes |
| `angle` | double | 0.0 | 0.0 - 360.0 | Yes |

### 10.5 Face Blur

**Implementation:** Vision framework (`VNDetectFaceRectanglesRequest`) + `CIGaussianBlur` + mask compositing.

This is a two-phase effect:

**Phase 1 - Analysis (Background, One-Time):**

```swift
func analyzeFaces(asset: AVAsset) async -> [CMTime: [CGRect]] {
    // Sample frames at ~5 FPS (every 6th frame at 30fps)
    // Run VNDetectFaceRectanglesRequest on each frame
    // Return map of timestamp -> face rects
    // Cache results in TrackingDataStore
}
```

**Phase 2 - Rendering (Per-Frame, Real-Time):**

```swift
func applyFaceBlur(
    input: CIImage,
    faceRects: [CGRect],   // Normalized face rects for this frame
    blurRadius: Double,
    feather: Double
) -> CIImage {
    // 1. Create mask image: white rectangles at face positions, black elsewhere
    // 2. Apply feathering (gaussian blur on mask)
    // 3. Use CIBlendWithMask: blurred version where mask is white, original elsewhere
    let blurred = input.applyingGaussianBlur(sigma: blurRadius)
    let mask = createFaceMask(faceRects: faceRects, size: input.extent.size, feather: feather)
    return blurred.applyingFilter("CIBlendWithMask", parameters: [
        "inputBackgroundImage": input,
        "inputMaskImage": mask,
    ])
}
```

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `blurRadius` | double | 30.0 | 5.0 - 100.0 | Yes |
| `feather` | double | 0.15 | 0.0 - 0.5 | Yes |
| `expandRect` | double | 0.2 | 0.0 - 1.0 | Yes |

**Integration with existing tracking:** The face blur analysis can reuse the `PeopleService` and `TrackingService` infrastructure already in the app. Face rectangles from the tracking system can be cached and reused for blur.

### Mask Integration

All blur types support an optional `MaskShape`. When a mask is present:
- **Mask not inverted:** Blur applies only INSIDE the mask
- **Mask inverted:** Blur applies only OUTSIDE the mask

This enables "blur everything except this area" workflows.

---

## 11. Chroma Key (Green Screen)

### Implementation

Chroma keying is implemented via a custom `CIColorKernel` that operates in HSL color space for more natural keying than RGB thresholding.

### Algorithm

```metal
// Metal CIKernel for chroma key
kernel vec4 chromaKey(
    sample_t source,
    vec3 keyColorHSL,
    float hueTolerance,
    float satTolerance,
    float lumTolerance,
    float edgeSoftness
) {
    vec3 sourceHSL = rgbToHSL(source.rgb);

    float hueDist = abs(sourceHSL.x - keyColorHSL.x);
    hueDist = min(hueDist, 1.0 - hueDist); // Wrap-around hue

    float satDist = abs(sourceHSL.y - keyColorHSL.y);
    float lumDist = abs(sourceHSL.z - keyColorHSL.z);

    // Combined distance
    float dist = max(max(hueDist / hueTolerance, satDist / satTolerance), lumDist / lumTolerance);

    // Soft edge
    float alpha = smoothstep(1.0 - edgeSoftness, 1.0 + edgeSoftness, dist);

    return vec4(source.rgb, source.a * alpha);
}
```

### Spill Suppression

After keying, green light contamination remains on edges. Spill suppression desaturates pixels near the key color:

```metal
kernel vec4 spillSuppression(
    sample_t source,
    vec3 keyColorHSL,
    float strength
) {
    vec3 sourceHSL = rgbToHSL(source.rgb);
    float hueDist = abs(sourceHSL.x - keyColorHSL.x);
    hueDist = min(hueDist, 1.0 - hueDist);

    float spillAmount = max(0.0, 1.0 - hueDist * 4.0) * strength;

    // Desaturate spill
    sourceHSL.y *= (1.0 - spillAmount);

    return vec4(hslToRGB(sourceHSL), source.a);
}
```

### Layer System Requirement

Chroma key requires compositing the keyed clip over a background. This depends on the multi-track system:

- **With multi-track:** Keyed clip on overlay track, background on main track. The compositor composites them automatically.
- **Without multi-track (current limitation):** The keyed clip composites over a solid color (black or user-selected). A "background color" parameter is added. Full compositing requires the overlay track system from `TrackType.overlayVideo`.

**Decision:** Phase 4 implementation (after multi-track overlay support is available). In the interim, a "chroma key preview" mode can show the alpha matte or checkerboard to verify keying quality.

### Parameters

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `keyColor` | color | green (0xFF00FF00) | any color | No |
| `hueTolerance` | double | 0.3 | 0.0 - 1.0 | Yes |
| `saturationTolerance` | double | 0.3 | 0.0 - 1.0 | Yes |
| `luminanceTolerance` | double | 0.3 | 0.0 - 1.0 | Yes |
| `edgeSoftness` | double | 0.1 | 0.0 - 1.0 | Yes |
| `spillSuppression` | double | 0.5 | 0.0 - 1.0 | Yes |
| `denoiseAlpha` | double | 0.0 | 0.0 - 1.0 | Yes |
| `previewMode` | enum | composite | 4 modes | No |

### UI

- **Color Picker:** Tap on video preview to sample key color (eyedropper tool)
- **Tolerance Sliders:** Three sliders for H/S/L tolerance
- **Preview Toggle:** Cycle through preview modes (composite, alpha matte, checkerboard, side-by-side)
- **Spill Suppression Slider:** Single slider
- **Edge Refinement:** Softness + denoise sliders

---

## 12. Video Stabilization

### Algorithm Overview

1. **Motion Analysis:** Compare consecutive frames to detect camera motion
2. **Path Smoothing:** Compute smoothed camera path
3. **Transform Application:** Apply inverse of residual motion per frame

### Phase 1: Motion Analysis (Background)

Uses Apple's Vision framework `VNTranslationalImageRegistrationRequest` for frame-to-frame motion estimation:

```swift
func analyzeMotion(asset: AVAsset) async -> [StabilizationFrame] {
    let reader = try AVAssetReader(asset: asset)
    // Read at reduced resolution for speed (720p)

    var previousFrame: CVPixelBuffer?
    var frames: [StabilizationFrame] = []

    for each frame {
        if let prev = previousFrame {
            let request = VNTranslationalImageRegistrationRequest(
                targetedCVPixelBuffer: currentFrame
            )
            let handler = VNImageRequestHandler(cvPixelBuffer: prev)
            try handler.perform([request])

            if let result = request.results?.first as? VNImageTranslationAlignmentObservation {
                let transform = result.alignmentTransform
                frames.append(StabilizationFrame(
                    time: frameTime,
                    dx: transform.tx,
                    dy: transform.ty,
                    rotation: atan2(transform.b, transform.a)
                ))
            }
        }
        previousFrame = currentFrame
    }

    return frames
}
```

### Phase 2: Path Smoothing

Compute the cumulative camera path, then smooth it using a Gaussian kernel or Kalman filter (reusing the existing `KalmanFilter.swift`):

```swift
struct StabilizationFrame {
    let time: CMTime
    let dx: CGFloat      // Horizontal translation
    let dy: CGFloat      // Vertical translation
    let rotation: CGFloat // Rotation angle
}

func smoothPath(
    frames: [StabilizationFrame],
    smoothingRadius: Int  // Number of frames in smoothing window
) -> [StabilizationFrame] {
    // Compute cumulative path
    var cumulativeX: [CGFloat] = [0]
    var cumulativeY: [CGFloat] = [0]
    var cumulativeR: [CGFloat] = [0]

    for frame in frames {
        cumulativeX.append(cumulativeX.last! + frame.dx)
        cumulativeY.append(cumulativeY.last! + frame.dy)
        cumulativeR.append(cumulativeR.last! + frame.rotation)
    }

    // Apply Gaussian smoothing
    let smoothedX = gaussianSmooth(cumulativeX, radius: smoothingRadius)
    let smoothedY = gaussianSmooth(cumulativeY, radius: smoothingRadius)
    let smoothedR = gaussianSmooth(cumulativeR, radius: smoothingRadius)

    // Compute correction transforms (difference between original and smoothed path)
    var corrected: [StabilizationFrame] = []
    for i in 0..<frames.count {
        corrected.append(StabilizationFrame(
            time: frames[i].time,
            dx: smoothedX[i + 1] - cumulativeX[i + 1],
            dy: smoothedY[i + 1] - cumulativeY[i + 1],
            rotation: smoothedR[i + 1] - cumulativeR[i + 1]
        ))
    }

    return corrected
}
```

### Phase 3: Transform Application

Per-frame, apply the inverse correction as a `CIAffineTransform`:

```swift
func applyStabilization(
    input: CIImage,
    correction: StabilizationFrame,
    cropFactor: Double  // 0.0 = no crop, 1.0 = maximum crop
) -> CIImage {
    // Scale up to compensate for stabilization crop
    let scale = 1.0 + cropFactor * 0.2  // 20% max zoom

    var transform = CGAffineTransform.identity
    transform = transform.translatedBy(x: input.extent.midX, y: input.extent.midY)
    transform = transform.scaledBy(x: scale, y: scale)
    transform = transform.rotatedBy(angle: correction.rotation)
    transform = transform.translatedBy(x: correction.dx, y: correction.dy)
    transform = transform.translatedBy(x: -input.extent.midX, y: -input.extent.midY)

    return input.transformed(by: transform).cropped(to: input.extent)
}
```

### Parameters

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `smoothingStrength` | double | 0.5 | 0.0 - 1.0 | No |
| `cropFactor` | double | 0.1 | 0.0 - 0.3 | No |
| `stabilizationMode` | enum | smooth | smooth/locked/tripod | No |

Stabilization modes:
- **Smooth:** Remove jitter while preserving intentional camera movements
- **Locked:** Attempt to lock camera position (more aggressive, more crop)
- **Tripod:** Maximum stabilization, tries to make footage look tripod-mounted

### Progress UI

Stabilization analysis can take 5-30 seconds depending on clip length. Display:
- Progress bar (analysis progress: 0-100%)
- "Analyzing motion..." label
- Cancel button
- Before/after toggle (once analysis is complete)

### Caching

Stabilization correction data is stored per-clip and persists with the project. Re-analysis is only needed if the source clip changes.

---

## 13. Mask Effects

### Mask as Modifier

Masks are not standalone effects. They modify how other effects are applied. A mask defines a region; the associated effect applies only within (or outside) that region.

### Mask Attachment

Each `VideoEffect` in the chain can optionally have a list of masks:

```dart
@immutable
class VideoEffect {
  // ... existing fields ...
  final List<MaskShape> masks;  // NEW: masks that control where this effect applies
}
```

When masks are present, the rendering pipeline:
1. Renders the effect to a temporary image
2. Generates a mask image from the MaskShape definitions
3. Composites using `CIBlendWithMask`: effect result where mask is white, original where mask is black

### Shape Masks

Pre-defined shapes with adjustable parameters:

**Rectangle:**
- Center position, width, height, rotation, corner radius, feather

**Ellipse:**
- Center position, width, height, rotation, feather

**Polygon:**
- Array of vertex points (normalized), feather

### Custom Draw Mask

User draws on the video preview with their finger. The drawn path is converted to a `MaskShape` with `shapeType: customPath` and `pathPoints` containing the Bezier path control points.

**Drawing UI:**
- Canvas overlay on video preview
- Stroke width selector
- Erase mode toggle
- Clear button
- The drawn mask is rendered as a grayscale image (white = masked, black = unmasked) with configurable feathering

### Mask Animation (Keyframeable)

All mask parameters (centerX, centerY, width, height, rotation, feather) are keyframeable, enabling:
- A blur mask that follows a moving object (combined with tracking data)
- A mask that reveals or conceals an area over time
- Animated transitions between masked and unmasked areas

### Multiple Masks Per Effect

An effect can have multiple masks. They are combined using additive blending (union) or subtractive blending (intersection), configurable per mask.

```dart
enum MaskCombineMode {
  add,        // Union (white where ANY mask is white)
  subtract,   // Remove this mask's area from previous masks
  intersect,  // Only where this AND previous masks overlap
}
```

### Native Mask Rendering

```swift
func renderMask(
    masks: [[String: Any]],
    frameSize: CGSize
) -> CIImage {
    // Start with all-black (no effect applied)
    var maskImage = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: frameSize))

    for maskData in masks {
        let shapeMask = renderShapeMask(maskData, frameSize: frameSize)
        let combineMode = maskData["combineMode"] as? String ?? "add"

        switch combineMode {
        case "add":
            maskImage = maskImage.applyingFilter("CIMaximumCompositing",
                parameters: ["inputBackgroundImage": shapeMask])
        case "subtract":
            let inverted = shapeMask.applyingFilter("CIColorInvert")
            maskImage = maskImage.applyingFilter("CIMinimumCompositing",
                parameters: ["inputBackgroundImage": inverted])
        case "intersect":
            maskImage = maskImage.applyingFilter("CIMinimumCompositing",
                parameters: ["inputBackgroundImage": shapeMask])
        default:
            break
        }
    }

    return maskImage
}
```

---

## 14. Visual Effects (Stylistic)

### 14.1 Glitch

**Implementation:** Custom Metal `CIKernel` + `CIColorMatrix`

The glitch effect creates:
- RGB channel separation (offset R, G, B channels independently)
- Horizontal block displacement (shift random horizontal bands)
- Scanline overlay
- Random intensity variation per frame (seeded by frame time for reproducibility)

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `intensity` | double | 0.5 | 0.0 - 1.0 | Yes |
| `channelSeparation` | double | 10.0 | 0.0 - 50.0 | Yes |
| `blockSize` | double | 0.1 | 0.01 - 0.5 | Yes |
| `scanlineOpacity` | double | 0.3 | 0.0 - 1.0 | Yes |
| `seed` | int | auto (frame) | 0 - 999999 | No |

The seed is derived from frame time to ensure reproducible glitch patterns during scrubbing and export.

### 14.2 VHS/Retro

**Implementation:** Combination of CIFilters + custom kernel

Components:
- Color bleed (slight horizontal smear of colors)
- Tracking lines (horizontal white lines that drift vertically)
- Color shift toward warm/muted palette (`CIColorMatrix`)
- Noise overlay (`CIRandomGenerator` + blend)
- Timestamp overlay (optional "REC" + date text)
- Resolution reduction (slight pixelation)

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `intensity` | double | 0.7 | 0.0 - 1.0 | Yes |
| `trackingLineIntensity` | double | 0.3 | 0.0 - 1.0 | Yes |
| `colorBleedAmount` | double | 5.0 | 0.0 - 20.0 | Yes |
| `noiseAmount` | double | 0.2 | 0.0 - 1.0 | Yes |
| `showTimestamp` | bool | false | on/off | No |

### 14.3 Film Grain

**Implementation:** `CIRandomGenerator` + `CIColorMatrix` + `CIBlendWithAlphaMask`

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `intensity` | double | 0.3 | 0.0 - 1.0 | Yes |
| `grainSize` | double | 1.0 | 0.5 - 5.0 | Yes |
| `colored` | bool | false | on/off | No |

Grain changes per frame (using frame time as seed for `CIRandomGenerator` offset), creating organic film texture.

```swift
func applyFilmGrain(
    input: CIImage,
    intensity: Double,
    grainSize: Double,
    frameTime: CMTime
) -> CIImage {
    // Generate noise
    let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!

    // Offset by frame time for per-frame variation
    let offset = CGFloat(CMTimeGetSeconds(frameTime) * 1000)
    let shiftedNoise = noise.transformed(by: CGAffineTransform(
        translationX: offset, y: offset
    ))

    // Scale grain
    let scaledNoise = shiftedNoise.transformed(by: CGAffineTransform(
        scaleX: grainSize, y: grainSize
    )).cropped(to: input.extent)

    // Convert to luminance and apply intensity
    let grainMask = scaledNoise.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        "inputAVector": CIVector(x: CGFloat(intensity) * 0.299,
                                  y: CGFloat(intensity) * 0.587,
                                  z: CGFloat(intensity) * 0.114,
                                  w: 0),
    ])

    // Blend using screen mode
    return input.applyingFilter("CIScreenBlendMode", parameters: [
        "inputBackgroundImage": grainMask,
    ])
}
```

### 14.4 Lens Flare

**Implementation:** Custom Metal kernel for anamorphic lens flare

Generates a light source with:
- Central bright point
- Horizontal anamorphic streak
- Ghost reflections (hexagonal bokeh shapes)
- Diffraction spikes

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `positionX` | double | 0.7 | 0.0 - 1.0 | Yes |
| `positionY` | double | 0.3 | 0.0 - 1.0 | Yes |
| `intensity` | double | 0.5 | 0.0 - 1.0 | Yes |
| `streakLength` | double | 0.5 | 0.0 - 1.0 | Yes |
| `color` | color | warm white | any | Yes |
| `ghostCount` | int | 3 | 0 - 8 | No |

### 14.5 Light Leaks

**Implementation:** Pre-rendered animated overlay textures + `CIScreenBlendMode`

A library of 8-12 pre-rendered light leak animations (warm orange/red color washes). These are bundled as short looping video assets or generated procedurally.

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `leakStyle` | enum | warm | 8 presets | No |
| `intensity` | double | 0.5 | 0.0 - 1.0 | Yes |
| `speed` | double | 1.0 | 0.25 - 4.0 | Yes |
| `rotation` | double | 0.0 | 0.0 - 360.0 | Yes |

```swift
func applyLightLeak(
    input: CIImage,
    leakImage: CIImage,  // Pre-rendered leak frame for current time
    intensity: Double
) -> CIImage {
    // Adjust leak intensity
    let adjustedLeak = leakImage.applyingFilter("CIExposureAdjust", parameters: [
        "inputEV": intensity * 2.0 - 1.0  // Map 0-1 to -1 to 1 EV
    ])

    // Screen blend (additive, light areas affect result)
    return input.applyingFilter("CIScreenBlendMode", parameters: [
        "inputBackgroundImage": adjustedLeak.cropped(to: input.extent),
    ])
}
```

---

## 15. Sharpen/Denoise

### 15.1 Sharpen

**CIFilter:** `CISharpenLuminance`

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `sharpness` | double | 0.5 | 0.0 - 2.0 | Yes |
| `radius` | double | 1.0 | 0.0 - 20.0 | Yes |

### 15.2 Unsharp Mask

**CIFilter:** `CIUnsharpMask`

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `intensity` | double | 0.5 | 0.0 - 2.0 | Yes |
| `radius` | double | 2.5 | 0.0 - 20.0 | Yes |

### 15.3 Denoise

**CIFilter:** `CINoiseReduction`

| Parameter | Type | Default | Range | Keyframeable |
|-----------|------|---------|-------|--------------|
| `noiseLevel` | double | 0.02 | 0.0 - 0.1 | Yes |
| `sharpness` | double | 0.4 | 0.0 - 2.0 | Yes |

**Advanced Temporal Denoise** (Phase 4): Averaging multiple consecutive frames to reduce noise. Requires frame buffering and is significantly more effective than single-frame denoise but has higher memory cost.

---

## 16. Effect Stacking & Chain

### Chain Model

Every clip has an `EffectChain` containing an ordered list of `VideoEffect` instances. The chain is processed sequentially: effect 0's output is effect 1's input.

### Maximum Effects

**Recommendation:** Soft limit of 8 effects per clip. Beyond 8, the system shows a warning that performance may degrade. The hard limit is bounded by the 16ms frame budget (see Section 20).

### Chain Operations

| Operation | Description | Undo Support |
|-----------|-------------|--------------|
| Add Effect | Append effect to end of chain | Yes (remove) |
| Remove Effect | Remove by ID | Yes (re-add at position) |
| Reorder | Move effect to new position | Yes (reverse move) |
| Enable/Disable | Toggle `isEnabled` flag | Yes (toggle back) |
| Adjust Mix | Change `mix` value | Yes (restore previous) |
| Duplicate | Copy effect with new ID | Yes (remove copy) |
| Copy/Paste | Copy chain from one clip to another | Yes (restore target chain) |

All operations produce new immutable `EffectChain` instances, integrating with the O(1) undo/redo system.

### Effect Chain UI

The effect chain is displayed in the clip inspector panel as a vertically scrollable list:

```
+-------------------------------------+
|  Effect Chain                [+Add]  |
+-------------------------------------+
|  1. [x] Crop (16:9)          [...]  |
|     mix: 100%                        |
|  2. [x] Gaussian Blur        [...]  |
|     radius: 15px  mix: 80%          |
|  3. [ ] Film Grain (disabled) [...]  |
|     intensity: 0.3                   |
|  4. [x] Sharpen              [...]  |
|     amount: 0.5  radius: 1.0        |
+-------------------------------------+
|  [Copy Effects] [Paste Effects]      |
+-------------------------------------+
```

**UI Features:**
- Drag handle on left edge for reorder (long-press to initiate)
- Checkbox for enable/disable toggle
- Tap to expand and show full parameter controls
- Three-dot menu (...) with: Duplicate, Remove, Reset to Default
- "Add Effect" button opens Effect Browser (Section 18)
- "Copy/Paste Effects" for transferring chains between clips

### Copy/Paste Effects

- **Copy:** Serializes the entire `EffectChain` to clipboard
- **Paste:** Deserializes and replaces the target clip's chain
- **Paste Individual:** Pastes a single copied effect, appending to the target chain

---

## 17. Keyframeable Effects

### Integration with Existing Keyframe System

Effect keyframes reuse the existing `InterpolationType` enum (18 types) and interpolation engine from `TransformInterpolator`. The key difference is that effect keyframes animate arbitrary numeric parameters rather than `VideoTransform` fields.

### Keyframe Interpolation for Effects

```dart
/// Resolve effect parameter value at a specific time, considering keyframes.
dynamic resolveEffectParameter(
  VideoEffect effect,
  String paramName,
  Duration clipTime,
) {
  if (effect.keyframes.isEmpty) {
    return effect.parameters[paramName]?.currentValue;
  }

  // Find surrounding keyframes
  EffectKeyframe? before;
  EffectKeyframe? after;

  for (final kf in effect.keyframes) {
    if (kf.timestamp <= clipTime && kf.values.containsKey(paramName)) {
      before = kf;
    }
    if (kf.timestamp >= clipTime && kf.values.containsKey(paramName) && after == null) {
      after = kf;
    }
  }

  if (before == null && after == null) {
    return effect.parameters[paramName]?.currentValue;
  }
  if (before == null) return after!.values[paramName];
  if (after == null) return before.values[paramName];
  if (before.timestamp == after.timestamp) return before.values[paramName];

  // Interpolate
  final t = (clipTime - before.timestamp).inMicroseconds /
      (after.timestamp - before.timestamp).inMicroseconds;
  final easedT = applyEasing(t, before.interpolation);

  final fromVal = (before.values[paramName] as num).toDouble();
  final toVal = (after.values[paramName] as num).toDouble();

  return fromVal + (toVal - fromVal) * easedT;
}
```

### Timeline UI for Effect Keyframes

When an effect parameter is selected for keyframing, diamond-shaped markers appear on the clip in the timeline view, colored to match the effect category:

```
Timeline clip:
+---------[<>]--------[<>]----------[<>]-----+
|  Video Clip                                 |
|    keyframe markers (diamonds)              |
+---------[<>]--------[<>]----------[<>]-----+
              ^blur radius  ^blur radius
```

**UI for keyframe editing:**
- Tap on a parameter slider to set a keyframe at the current playhead position
- Toggle "Record" mode: any parameter change automatically creates a keyframe
- Right-tap a keyframe diamond to edit interpolation type, delete, or copy value
- Interpolation type picker (reuses existing 18-type picker from transform keyframes)

---

## 18. Effect Browser UI

### Design

The effect browser is a modal sheet presented from the bottom, using iOS 26 Liquid Glass styling.

### Layout

```
+--------------------------------------+
|  Effects                        [X]  |
|  [Search...]                         |
+--------------------------------------+
|  Categories:                         |
|  [All] [Blur] [Stylistic] [Adjust]  |
|  [Transform] [Time] [Color]         |
+--------------------------------------+
|  +--------+  +--------+  +--------+ |
|  |  Gauss |  | Radial |  | Tilt-  | |
|  |  Blur  |  | Blur   |  | Shift  | |
|  | [anim] |  | [anim] |  | [anim] | |
|  +--------+  +--------+  +--------+ |
|  +--------+  +--------+  +--------+ |
|  | Motion |  | Face   |  | Film   | |
|  |  Blur  |  | Blur   |  | Grain  | |
|  | [anim] |  | [anim] |  | [anim] | |
|  +--------+  +--------+  +--------+ |
|  ...                                 |
+--------------------------------------+
|  Recently Used: [Blur] [Grain]       |
|  Favorites: [heart icons]            |
+--------------------------------------+
```

### Categories

| Category | Effects | SF Symbol |
|----------|---------|-----------|
| All | All effects | `square.grid.2x2` |
| Time | Reverse, Freeze Frame, Speed Ramp | `clock.arrow.circlepath` |
| Transform | Mirror/Flip, Crop | `arrow.left.and.right.righttriangle.left.righttriangle.right` |
| Blur | Gaussian, Radial, Tilt-Shift, Motion, Face | `aqi.medium` |
| Color | Chroma Key | `paintpalette` |
| Adjust | Sharpen, Unsharp Mask, Denoise, Stabilization | `slider.horizontal.3` |
| Stylistic | Glitch, VHS, Film Grain, Lens Flare, Light Leaks | `sparkles` |
| Masks | Shape Mask, Draw Mask | `square.on.circle` |

### Animated Previews

Each effect tile shows a small animated preview (4-6 frame loop) demonstrating the effect. These are pre-rendered GIFs or short video loops bundled with the app. The preview uses a sample frame from the current clip to show realistic results.

### Apply Flow

1. User taps an effect tile
2. Effect is added to the current clip's effect chain with default parameters
3. Browser dismisses
4. Clip inspector opens showing the new effect's parameters
5. User adjusts parameters

### Favorites & Recently Used

- **Favorites:** Stored in `UserDefaults` as list of `EffectType` names
- **Recently Used:** Last 6 applied effects, stored in `UserDefaults`

### Implementation Notes

- Use `CupertinoSearchTextField` for search
- Use `CupertinoScrollbar` for grid scrolling
- Grid items use `ClipRRect` + `BackdropFilter` for Liquid Glass effect
- Category bar uses `CupertinoSegmentedControl` or horizontal scroll of `CNButton` chips

---

## 19. Edge Cases

### Effects on Very Short Clips (< 0.5s)

- All effects are supported. CIFilters operate per-frame and have no minimum duration requirement.
- Keyframed effects with very short duration may interpolate rapidly. The UI should warn when keyframe spacing is less than 100ms.
- Speed ramps on very short clips may produce durations below `TimelineClip.minDuration` (33,333 microseconds). Clamp output duration to this minimum.

### Effects on Image Clips vs Video Clips

- Image clips represent a single frame held for a duration. All effects apply identically to every frame (no temporal variation).
- Exception: Film grain, glitch, and VHS effects use frame time as a seed for per-frame variation. On image clips, they still animate because the frame time changes even though the source image does not.
- Speed ramp and reverse are not applicable to image clips. The effect browser should hide these options when an image clip is selected.

### Effect Chain Ordering Interactions

- **Blur + Sharpen:** These partially cancel each other. The UI should show a warning: "Blur followed by Sharpen may produce artifacts."
- **Crop + Blur:** Order matters. Crop-then-blur blurs only the cropped region. Blur-then-crop blurs the full frame first. Default insertion order puts crop first.
- **Multiple crops:** Each crop compounds. The second crop operates on the already-cropped frame. The UI should warn when stacking crops.
- **Mirror + Transform Keyframes:** Mirror flips the already-transformed frame. If the user expects mirror to apply to the source, they should place mirror first in the chain (before transforms). However, since transforms are applied before the chain, the user may need to adjust transform coordinates.

### Speed Ramp + Reverse Combined

When both are active:
1. The speed ramp's time axis is evaluated in reverse
2. Source frames are read in reverse order
3. The ramp curve effectively plays backward

This produces natural results: a "slow-mo ramp up" on a reversed clip starts slow (in reverse) and accelerates.

### Crop + Transform Keyframes Combined

Transforms are applied first (as part of the composition layer instruction), then crop operates on the transformed frame. This means:
- A zoomed-in clip with a crop further restricts the visible area
- Position/pan transforms shift the content within the crop window

### Chroma Key Without Multi-Track

Without an overlay track system, keyed-out pixels become transparent. The preview shows a checkerboard pattern or configurable solid color behind transparent pixels. On export, transparent areas are composited over black. Full chroma key compositing requires Phase 4 (multi-track overlays).

### Stabilization on Already-Stable Footage

The motion analysis will detect minimal motion and apply near-zero corrections. The crop factor still applies (slight zoom), so the user should be warned: "This footage appears stable. Stabilization will have minimal effect but will crop the frame slightly."

### Memory with Many Effects Across Many Clips

- CIFilter instances are lightweight (< 1KB each)
- The CIContext reuses GPU resources across filters
- Effect parameter models are small (< 500 bytes per effect)
- A project with 50 clips, each with 5 effects, consumes roughly 50 * 5 * 500 bytes = 125 KB of model data
- GPU memory for filter chains is transient (allocated per-frame, released after rendering)

### Undo/Redo for Effect Changes

All effect mutations produce new immutable objects. The `TimelineManager`'s pointer-swap undo/redo captures the entire timeline state, which now includes effect chains. This is already O(1) and adds negligible memory per undo state (effect chain serialization is small).

### Copy/Paste Effects Between Clips

- Copy serializes the `EffectChain` to a clipboard buffer (in-memory JSON)
- Paste deserializes and applies to the target clip
- If the target clip type does not support certain effects (e.g., speed ramp on an image clip), those effects are skipped with a notification

### Effects During Transitions

During a transition between clips A and B:
- Clip A's effect chain applies to clip A's frames
- Clip B's effect chain applies to clip B's frames
- The transition compositing (dissolve, wipe, etc.) operates on the already-effected frames
- This is the standard NLE behavior (effects are per-clip, transitions are between-clip)

---

## 20. Performance

### Frame Budget

Target: 60 FPS = 16.67ms per frame. The effect chain must complete within this budget.

| Component | Budget | Notes |
|-----------|--------|-------|
| Frame decode | 2-4ms | AVAssetReader pixel buffer |
| Transform application | 1-2ms | CGAffineTransform via CIFilter |
| Effect chain (typical 3 effects) | 4-8ms | GPU-accelerated CIFilters |
| CIContext render to pixel buffer | 2-3ms | Metal GPU render |
| Display/encode | 1-2ms | AVPlayerLayer or AVAssetWriter |
| **Total** | **10-19ms** | Within 16.67ms for most cases |

### Per-Effect Timing Estimates

| Effect | Estimated Time | Notes |
|--------|---------------|-------|
| Gaussian Blur (radius < 20) | 0.5-1.5ms | GPU, highly optimized |
| Gaussian Blur (radius > 50) | 2-4ms | GPU, larger kernel |
| Radial/Tilt-Shift Blur | 1-2ms | Two CIFilters |
| Motion Blur | 0.5-1.5ms | GPU |
| Face Blur | 1-2ms (render only) | Uses cached face rects |
| Face Detection per frame | 5-15ms | Neural Engine, cached |
| Chroma Key | 1-2ms | Custom kernel |
| Mirror/Flip | 0.2-0.5ms | Single CIAffineTransform |
| Crop | 0.2-0.5ms | CICrop + transform |
| Sharpen/Unsharp | 0.5-1ms | GPU |
| Denoise | 1-2ms | GPU |
| Stabilization Transform | 0.2-0.5ms | Single CIAffineTransform |
| Glitch | 1-3ms | Custom Metal kernel |
| VHS/Retro | 2-4ms | Multiple CIFilters |
| Film Grain | 1-2ms | GPU |
| Lens Flare | 1-2ms | Custom kernel |
| Light Leaks | 0.5-1ms | Screen blend |

### GPU Acceleration

All CIFilters are GPU-accelerated when the `CIContext` is created with Metal:

```swift
let ciContext = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
```

### Stabilization Analysis Performance

- **Target:** 2x real-time (a 10s clip analyzes in 5s)
- **Implementation:** Background thread, reduced resolution (720p), VNTranslationalImageRegistrationRequest is highly optimized on Neural Engine
- **Caching:** Results are cached per-clip (invalidated on clip change)

### Face Blur Detection Performance

- **Sampling rate:** Analyze every 6th frame (5 FPS) during initial scan
- **Interpolation:** Interpolate face positions between analyzed frames for smooth tracking
- **Cache:** Face rect arrays cached per-frame-time, persisted with project
- **Runtime:** Face detection request is ~5ms per frame on Neural Engine

### Export Performance

Export uses the same CIFilter chain but can process at higher than real-time because there is no display deadline:
- Without effects: Real-time or faster (hardware encode)
- With 3 typical effects: Near real-time
- With complex chains (8 effects): 0.5-0.8x real-time

### Memory

- Effect parameter models: Negligible (< 200KB for entire project)
- CIFilter instances: < 50KB per active chain (created per-frame, reused)
- Stabilization data: ~100 bytes per frame (~3KB per second of video)
- Face detection cache: ~200 bytes per detected face per frame (~12KB per second)
- CIContext working memory: 50-100MB (shared across all CIFilter operations)
- Total additional memory: < 50MB typical, well within the 200MB budget

---

## 21. Dependencies

### iOS Framework Dependencies

| Framework | Purpose | Minimum iOS |
|-----------|---------|-------------|
| `CoreImage` | CIFilter effect chain | iOS 5.0+ |
| `CoreImage.CIFilterBuiltins` | Type-safe CIFilter API | iOS 13.0+ |
| `Metal` | GPU shader compilation | iOS 8.0+ |
| `MetalPerformanceShaders` | Optimized GPU operations | iOS 9.0+ |
| `Vision` | Face detection, stabilization | iOS 11.0+ |
| `AVFoundation` | Video composition, export | iOS 4.0+ |
| `Accelerate` | Signal processing (path smoothing) | iOS 4.0+ |

### Custom Metal Shaders Required

| Shader | Purpose | Priority |
|--------|---------|----------|
| `ChromaKeyKernel.metal` | Chroma key + spill suppression | Phase 4 |
| `GlitchKernel.metal` | Glitch effect (channel split, block displacement) | Phase 3 |
| `VHSKernel.metal` | VHS effect (color bleed, tracking lines) | Phase 3 |
| `LensFlareKernel.metal` | Lens flare generation | Phase 3 |

### Flutter Package Dependencies

No additional Flutter packages are required. All effect rendering happens on the native side via platform channels. The Flutter side only manages data models and UI.

### External Dependencies

None. All effects use built-in iOS frameworks. No third-party libraries are needed.

---

## 22. Implementation Plan

### Phase 1: Effect System Architecture + Mirror/Flip + Crop

**Estimated Duration:** 2-3 weeks
**Scope:** Foundation for the entire effects system

**Deliverables:**
1. Data models: `EffectParameter`, `VideoEffect`, `EffectChain`, `EffectKeyframe`, `CropRect`
2. `EffectType` enum and effect registry with default parameters
3. Integration with `VideoClip`: add `effectChain` field
4. Integration with `TimelineClip`: compute `hasEffects`/`effectCount` from underlying data
5. Platform channel `com.liquideditor/effects` with `applyEffectChain` method
6. Native `EffectVideoCompositor` (AVVideoCompositing protocol) with CIFilter chain builder
7. Mirror/Flip effect (simplest spatial effect, validates pipeline end-to-end)
8. Crop effect with aspect ratio presets and CupertinoUI for crop overlay
9. Effect chain list in clip inspector (add, remove, reorder, enable/disable)
10. Serialization/deserialization for project persistence

**File Structure:**
```
lib/
  models/
    effects/
      effect_types.dart          # EffectType enum + registry
      effect_parameter.dart      # EffectParameter model
      video_effect.dart          # VideoEffect (EffectNode) model
      effect_chain.dart          # EffectChain model
      effect_keyframe.dart       # EffectKeyframe model
      crop_rect.dart             # CropRect + CropAspectRatio
      mask_shape.dart            # MaskShape model (for later phases)
      speed_ramp.dart            # SpeedRamp model (for Phase 3)
      chroma_key_config.dart     # ChromaKeyConfig model (for Phase 4)
      effects.dart               # Barrel export
  core/
    effect_manager.dart          # Effect chain CRUD operations
  views/
    smart_edit/
      effect_chain_panel.dart    # Effect list UI in clip inspector
      effect_parameter_editor.dart # Parameter slider/toggle UI
      crop_overlay.dart          # Crop rectangle overlay on video preview
      effect_browser.dart        # Effect browser modal (categories, grid)

ios/Runner/
  Effects/
    EffectVideoCompositor.swift   # AVVideoCompositing implementation
    EffectFilterChain.swift       # CIFilter chain builder
    EffectMethodChannel.swift     # Platform channel handler
    CropEffect.swift              # Crop CIFilter logic
    MirrorFlipEffect.swift        # Mirror/flip CIAffineTransform
```

**Tests:**
- `test/models/video_effect_test.dart` - Effect model serialization, copyWith
- `test/models/effect_chain_test.dart` - Chain operations (add, remove, reorder)
- `test/models/crop_rect_test.dart` - Crop calculations, aspect ratio locking

### Phase 2: Blur Effects + Reverse + Freeze Frame

**Estimated Duration:** 2-3 weeks
**Depends On:** Phase 1 complete

**Deliverables:**
1. Gaussian Blur effect (CIGaussianBlur)
2. Radial Blur effect (CIRadialGradient + CIMaskedVariableBlur)
3. Tilt-Shift effect (CILinearGradient + CIMaskedVariableBlur)
4. Motion Blur effect (CIMotionBlur)
5. Face Blur effect (Vision VNDetectFaceRectanglesRequest + cached detection + CIGaussianBlur + mask)
6. Reverse video implementation (AVAssetReader reverse reading, audio handling)
7. Freeze Frame implementation (AVAssetImageGenerator extraction + ImageClip insertion)
8. Blur effects support mask integration (MaskShape modifiers)

**File Structure:**
```
ios/Runner/
  Effects/
    BlurEffects.swift            # All blur CIFilter implementations
    FaceBlurAnalyzer.swift       # Vision face detection + caching
    ReverseVideoService.swift    # Reverse video generation
    FreezeFrameService.swift     # Frame extraction for freeze

lib/views/smart_edit/
    blur_parameter_panel.dart    # Blur-specific parameter UI (radial center picker, tilt-shift angle)
    freeze_frame_dialog.dart     # Duration picker + insert mode selection
```

**Tests:**
- `test/models/mask_shape_test.dart` - Mask creation, serialization
- Integration test for blur preview rendering (manual device test)

### Phase 3: Speed Ramp + Visual Effects

**Estimated Duration:** 3-4 weeks
**Depends On:** Phase 2 complete

**Deliverables:**
1. SpeedRamp data model with control points
2. Velocity curve editor widget (custom Flutter painter)
3. Speed ramp presets (linear ramp, ease, pulse)
4. Native composition building with time mapping segments
5. Audio time-stretch with pitch preservation (`AVAudioTimePitchAlgorithm`)
6. Integration with existing speed control (ramp replaces constant speed)
7. Glitch effect (custom Metal kernel)
8. VHS/Retro effect (custom Metal kernel + CIFilters)
9. Film Grain effect (CIRandomGenerator + blend)
10. Lens Flare effect (custom Metal kernel)
11. Light Leaks effect (pre-rendered overlays + screen blend)
12. Sharpen, Unsharp Mask, Denoise effects (built-in CIFilters)

**File Structure:**
```
lib/
  models/effects/
    speed_ramp.dart              # SpeedRamp + SpeedControlPoint models
  views/smart_edit/
    velocity_curve_editor.dart   # Custom curve editor widget
    visual_effect_preview.dart   # Animated preview tiles for browser

ios/Runner/
  Effects/
    SpeedRampComposition.swift   # Time mapping for speed ramps
    Kernels/
      ChromaKeyKernel.metal      # (Phase 4, but create file structure)
      GlitchKernel.metal         # Glitch effect Metal kernel
      VHSKernel.metal            # VHS effect Metal kernel
      LensFlareKernel.metal      # Lens flare Metal kernel
    StylisticEffects.swift       # Glitch, VHS, grain, flare, leaks
    EnhancementEffects.swift     # Sharpen, unsharp, denoise
```

**Tests:**
- `test/models/speed_ramp_test.dart` - Velocity curve evaluation, duration calculation, presets
- `test/views/velocity_curve_editor_test.dart` - Widget tests for curve interaction

### Phase 4: Chroma Key + Masks + Stabilization

**Estimated Duration:** 3-4 weeks
**Depends On:** Phase 3 complete, overlay track system available

**Deliverables:**
1. Chroma Key effect (custom Metal CIColorKernel)
2. Spill suppression kernel
3. Chroma key UI (eyedropper color picker, tolerance sliders, preview modes)
4. Video Stabilization analysis (VNTranslationalImageRegistrationRequest)
5. Path smoothing (Gaussian kernel / Kalman filter)
6. Stabilization transform application per frame
7. Stabilization UI (progress bar, before/after toggle, mode selector)
8. Shape masks (rectangle, ellipse, polygon) with feathering
9. Custom draw mask (finger drawing on preview)
10. Mask combination modes (add, subtract, intersect)
11. Mask keyframing (animate mask position, size, rotation)
12. Effect Browser modal with categories, search, favorites, recently used
13. Copy/Paste effects between clips
14. Keyframeable effect parameters (reusing existing interpolation engine)
15. Effect keyframe markers on timeline

**File Structure:**
```
ios/Runner/
  Effects/
    Kernels/
      ChromaKeyKernel.metal      # Chroma key + spill suppression
    ChromaKeyEffect.swift        # Chroma key CIFilter wrapper
    StabilizationAnalyzer.swift  # Motion analysis via Vision
    StabilizationSmoother.swift  # Path smoothing algorithms
    StabilizationEffect.swift    # Per-frame stabilization transform
    MaskRenderer.swift           # Shape mask -> CIImage rendering

lib/views/smart_edit/
    chroma_key_panel.dart        # Chroma key parameter UI + eyedropper
    stabilization_panel.dart     # Stabilization progress + settings
    mask_editor.dart             # Mask drawing/editing overlay
    mask_shape_controls.dart     # Shape mask parameter controls
    effect_keyframe_editor.dart  # Keyframe editing for effect parameters
```

**Tests:**
- `test/models/chroma_key_config_test.dart` - Config serialization, default values
- `test/models/effect_keyframe_test.dart` - Keyframe interpolation for effect parameters
- Integration test for stabilization pipeline (manual device test)

### Test Plan Summary

| Test Category | Phase | Approach |
|---------------|-------|----------|
| Data model serialization | 1-4 | Unit tests (Dart) |
| Effect chain operations | 1 | Unit tests (Dart) |
| Crop calculations | 1 | Unit tests (Dart) |
| Speed ramp curves | 3 | Unit tests (Dart) |
| Keyframe interpolation | 4 | Unit tests (Dart) |
| CIFilter chain correctness | 1-4 | Manual device testing + screenshot comparison |
| Preview rendering at 60fps | 1-4 | Profiling on device (Instruments) |
| Export with effects | 1-4 | Manual device testing + output verification |
| Undo/redo with effects | 1 | Unit test (Dart) + manual verification |
| Effect browser UI | 4 | Widget tests + manual |
| Stabilization quality | 4 | Manual testing with shaky footage samples |
| Chroma key quality | 4 | Manual testing with green screen footage |

---

## Appendix A: CIFilter Reference

| CIFilter Name | Category | Used By |
|---------------|----------|---------|
| `CIGaussianBlur` | Blur | Gaussian Blur, Face Blur (mask feathering) |
| `CIMaskedVariableBlur` | Blur | Radial Blur, Tilt-Shift |
| `CIMotionBlur` | Blur | Motion Blur |
| `CIRadialGradient` | Gradient | Radial Blur mask |
| `CILinearGradient` | Gradient | Tilt-Shift mask |
| `CIAffineTransform` | Geometry | Mirror/Flip, Stabilization, Crop scaling |
| `CICrop` | Geometry | Crop |
| `CISharpenLuminance` | Sharpen | Sharpen |
| `CIUnsharpMask` | Sharpen | Unsharp Mask |
| `CINoiseReduction` | Blur | Denoise |
| `CIRandomGenerator` | Generator | Film Grain |
| `CIColorMatrix` | Color | VHS color shift, Grain intensity |
| `CIScreenBlendMode` | Compositing | Light Leaks, Grain |
| `CIBlendWithMask` | Compositing | Masked effects, Face Blur |
| `CIMaximumCompositing` | Compositing | Mask combination (add) |
| `CIMinimumCompositing` | Compositing | Mask combination (intersect) |
| `CIColorInvert` | Color | Mask inversion |
| `CIExposureAdjust` | Color | Light Leaks intensity |

## Appendix B: SF Symbols for Effect UI

| Effect | Icon (Default) | Icon (Active) |
|--------|---------------|---------------|
| Gaussian Blur | `aqi.medium` | `aqi.medium` |
| Radial Blur | `circle.dashed` | `circle.dashed` |
| Tilt-Shift | `line.3.horizontal` | `line.3.horizontal` |
| Motion Blur | `wind` | `wind` |
| Face Blur | `person.crop.rectangle` | `person.crop.rectangle.fill` |
| Chroma Key | `paintpalette` | `paintpalette.fill` |
| Stabilization | `gyroscope` | `gyroscope` |
| Mirror | `arrow.left.and.right.righttriangle.left.righttriangle.right` | same (filled) |
| Crop | `crop` | `crop` |
| Glitch | `tv` | `tv.fill` |
| VHS | `film` | `film.fill` |
| Film Grain | `circle.grid.3x3` | `circle.grid.3x3.fill` |
| Lens Flare | `sun.max` | `sun.max.fill` |
| Light Leaks | `sunrise` | `sunrise.fill` |
| Sharpen | `diamond` | `diamond.fill` |
| Denoise | `waveform.path.ecg` | `waveform.path.ecg` |
| Reverse | `arrow.uturn.backward` | `arrow.uturn.backward.circle.fill` |
| Freeze Frame | `pause.rectangle` | `pause.rectangle.fill` |
| Speed Ramp | `gauge.with.needle` | `gauge.with.needle.fill` |
| Shape Mask | `square.on.circle` | `square.on.circle` |
| Draw Mask | `pencil.tip` | `pencil.tip.crop.circle` |

---

**End of Design Document**

**Review Checklist:**
- [ ] All 13 effect categories covered
- [ ] Data models are immutable and serializable
- [ ] Rendering pipeline handles both preview and export
- [ ] Performance budgets are realistic (benchmarked estimates)
- [ ] Integration with existing systems documented (Timeline V2, Keyframes, Composition)
- [ ] Edge cases comprehensively addressed
- [ ] Implementation phasing is logical with clear dependencies
- [ ] File structure follows existing project conventions
- [ ] Test plan covers all critical paths
- [ ] No external dependencies required

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Senior Software Architect)
**Date:** 2026-02-06
**Scope:** Architecture, completeness, feasibility, integration with existing codebase
**Verdict:** Solid design with several critical gaps that must be addressed before implementation

---

### Summary

The design is comprehensive, well-structured, and demonstrates strong understanding of both CIFilter pipelines and the existing codebase. The phased implementation plan is logical. However, the review identified several critical issues related to the dual clip model architecture, export pipeline integration, and missing specifications that would cause implementation blockers.

---

### CRITICAL Issues

#### C1: Dual Clip Model Creates Ambiguous Effect Chain Ownership

**Problem:** The codebase has TWO distinct clip model systems that the design conflates:

1. **V1 models** (`lib/models/timeline_clip.dart`): Mutable `TimelineClip` class used by `ClipManager`, with `sourceVideoPath`, `sourceInPoint`/`sourceOutPoint` as `Duration`, and mutable `keyframes` list.
2. **V2 models** (`lib/timeline/data/models/timeline_clip.dart`): Immutable `TimelineClip` class with `startTime`/`duration` as `TimeMicros`, `hasEffects`/`effectCount` as rendering metadata flags.
3. **V2 data models** (`lib/models/clips/video_clip.dart`): Immutable `VideoClip extends MediaClip` with `sourceInMicros`/`sourceOutMicros` and `List<Keyframe>`.

The design says `VideoClip` in `lib/models/clips/video_clip.dart` will gain an `effectChain` field, but the V1 `TimelineClip` in `lib/models/timeline_clip.dart` also has keyframe management that `ClipManager` depends on. The design does not specify:

- Which clip model is the authoritative owner of the effect chain
- How `ClipManager` (which uses V1 `TimelineClip`) will interact with V2 `VideoClip.effectChain`
- Whether the V1 model also needs an `effectChain` field for backward compatibility
- How the V2 immutable `TimelineClip` UI model's `hasEffects`/`effectCount` flags are kept in sync with the V2 data model's `EffectChain`

**Required Action:** Add a section explicitly mapping effect chain ownership across all three models. Decide: is the effect chain stored on V2 `VideoClip` only? If so, document the sync mechanism to V2 UI `TimelineClip` metadata flags, and document migration from V1 `TimelineClip` (if V1 is still in active use).

#### C2: Export Pipeline Requires Fundamental Rearchitecture

**Problem:** The current `VideoProcessingService.swift` uses `AVAssetExportSession` with `AVMutableVideoCompositionLayerInstruction` for transforms. This approach uses `setTransform`/`setTransformRamp` which is an Apple-provided instruction-based pipeline. The design proposes a custom `AVVideoCompositing` compositor (`EffectVideoCompositor`) for CIFilter chains.

These two approaches are **mutually exclusive** for a given `AVVideoComposition`:

- `AVMutableVideoCompositionInstruction` + `AVMutableVideoCompositionLayerInstruction` uses Apple's built-in compositor. You CANNOT simultaneously use a custom `AVVideoCompositing` class with standard layer instructions.
- A custom `AVVideoCompositing` compositor requires custom instruction classes conforming to `AVVideoCompositionInstructionProtocol`, NOT the standard `AVMutableVideoCompositionInstruction`.

The design mentions this in Section 4.1 but does not address the **migration** of existing transform keyframe rendering. Currently, transforms are applied via `layerInstruction.setTransformRamp()` in `VideoProcessingService.renderComposition()`. With a custom compositor, transforms must be re-implemented inside the compositor's `startRequest()` method using `CIAffineTransform` instead of layer instructions.

**Required Action:** Add a migration section in the rendering architecture that:
1. Defines a custom `AVVideoCompositionInstruction` subclass carrying both transform and effect chain data
2. Shows how existing transform ramp behavior is replicated via `CIAffineTransform` inside the custom compositor
3. Specifies whether `VideoProcessingService` is extended or replaced
4. Addresses that `CompositionBuilder.swift` also builds `AVMutableVideoComposition` with standard instructions (line 371-389) -- this must also migrate

#### C3: Speed Ramp Duration Calculation Does Not Account for Clip Timeline Position Updates

**Problem:** When a speed ramp is applied, `SpeedRamp.calculateOutputDurationMicros()` computes a new total output duration. The design states that `TimelineClip.duration` is updated. However:

- In the V2 timeline model, clip positions are stored in a Persistent Order Statistic Tree (per Timeline Architecture V2). Changing a single clip's duration requires rebalancing the tree and recomputing start times of all subsequent clips.
- The design does not specify how speed ramp duration changes propagate through the `TimelineManager` and trigger composition rebuilds.
- The V1 `ClipManager` uses `TimelineClip.withSpeed()` which recalculates duration from a constant speed. Speed ramp would need an entirely different path since the duration is no longer `sourceDuration / speed` but an integral over the velocity curve.

**Required Action:** Document the exact sequence of operations when a speed ramp is modified: (1) Compute new duration, (2) Update data model, (3) Trigger timeline rebalance, (4) Trigger composition rebuild, (5) Update preview player.

#### C4: `EffectParameter` Uses `dynamic` Types Extensively -- Type Safety Hole

**Problem:** `EffectParameter.currentValue`, `defaultValue`, `minValue`, `maxValue` are all `dynamic`. The `EffectKeyframe.values` map is `Map<String, dynamic>`. This means:

- No compile-time type checking on parameter values
- `toJson()`/`fromJson()` will silently pass wrong types (a `Color` value serialized as ARGB int cannot be distinguished from a numeric parameter)
- The `resolveEffectParameter` function (Section 17) casts to `num` for interpolation but will crash on `Color`, `Offset`, `Rect`, and `List<Offset>` (path) types that cannot be simply lerped

**Required Action:** Either:
(a) Use a sealed union type (`EffectValue`) with variants for each `EffectParameterType`, with explicit interpolation methods per variant, OR
(b) Document clearly which parameter types are keyframeable (only numeric) and add runtime validation that non-numeric types cannot have keyframes, plus document interpolation strategy for `point`, `rect`, `color`, and `path` types (component-wise lerp? slerp for color? path morphing?)

---

### IMPORTANT Issues

#### I1: `EffectKeyframe` Stores Multi-Parameter Snapshots, But Interpolation Is Per-Parameter

**Problem:** `EffectKeyframe.values` is `Map<String, dynamic>` -- a snapshot of ALL parameter values at a point in time. But `resolveEffectParameter()` in Section 17 searches for keyframes that contain a specific `paramName`. This means:

- If keyframe K1 at t=0 stores `{radius: 10, center: 0.5}` and K2 at t=1 stores `{radius: 20}` (center not captured), then interpolating `center` between K1 and K2 fails because K2 does not contain `center`.
- This is a design choice: either keyframes snapshot ALL parameters (like After Effects), or each parameter has its own independent keyframe track (like Final Cut Pro). The current design is ambiguous -- it structures data as multi-param snapshots but interpolates per-parameter.

**Required Action:** Decide one approach:
(a) **Per-parameter keyframe tracks:** Each parameter has its own `List<EffectKeyframe>` (simpler interpolation, more granular). Change `VideoEffect.keyframes` to `Map<String, List<EffectKeyframe>>` keyed by parameter name. OR
(b) **Multi-param snapshots:** Require all keyframes to capture ALL keyframeable parameters (add validation), so interpolation always finds values.

#### I2: Reverse Video Generates a New File -- Effect Chain State Management Gap

**Problem:** The reverse implementation generates a new video file via `AVAssetReader` + `AVAssetWriter`. This means:

- The `VideoClip.mediaAssetId` must change to reference the reversed file
- Existing transform keyframes are time-relative to clip start -- reversing the source means keyframe timestamps need to be mirrored (keyframe at t=0 should now be at t=clipDuration, etc.)
- The design says reverse is a "clip property, not an effect" but it IS in the `EffectType` enum (`EffectType.reverse`). This contradiction needs resolution.
- If reverse is a clip property, it should NOT be in the `EffectChain`. If it IS an effect, it cannot be implemented via file re-encoding at effect-apply time (too slow for real-time preview toggling)

**Required Action:** Decide definitively: is reverse a clip property or an effect? If clip property (recommended), remove `EffectType.reverse` from the enum. If effect, design a non-destructive approach (e.g., read frames in reverse order via AVAssetReader during preview, similar to negative-rate playback).

#### I3: Freeze Frame Creates ImageClip But ImageClip Has No `effectChain` Support

**Problem:** The design adds `effectChain` to `VideoClip` but freeze frame creates an `ImageClip`. The existing `ImageClip` class (`lib/models/clips/image_clip.dart`) has no keyframes field and no effectChain field. Effects on frozen frames would be lost.

**Required Action:** Either:
(a) Add `effectChain` to the base `MediaClip` class so all clip types support effects, OR
(b) Add `effectChain` to `ImageClip` specifically, OR
(c) Document that freeze frame ImageClips do not support effects (limitation)

#### I4: CompositionBuilder.swift Does Not Handle Effects at All

**Problem:** The existing `CompositionBuilder.swift` builds compositions with standard `AVMutableVideoCompositionInstruction` and an identity transform (line 384). It has no concept of effects. The design says `CompositionBuilder.swift` "will be extended to inject `AVVideoCompositionInstructionProtocol` with CIFilter logic" (Section 1) but provides no details on HOW.

The `CompositionBuilder` is used for preview playback via `CompositionPlayerService`. For effects to appear in preview, the composition it builds must use the custom compositor. This means:

- `BuiltComposition.videoComposition` must be configured with `customVideoCompositorClass`
- The `CompositionSegment` struct needs to carry effect chain data
- The `buildVideoComposition` method must produce custom instructions, not standard ones

**Required Action:** Add a concrete plan for `CompositionBuilder` integration. Show the modified `BuiltComposition` struct, the custom instruction class, and the modified `buildVideoComposition` method.

#### I5: CIFilter Chain at 60fps With Stacked Effects -- Performance Estimates Are Optimistic

**Problem:** The per-effect timing estimates in Section 20 assume isolated execution. In practice:

- **GPU contention:** Multiple CIFilter passes create GPU pipeline stalls. The GPU cannot start filter N+1 until filter N's output texture is available. This serialization adds ~0.5-1ms per filter transition.
- **CIContext.render() bottleneck:** The final `CIContext.render(_:to:)` call materializes the entire lazy CIFilter graph at once. For 5+ filters, this can spike to 10-15ms on older devices (iPhone 12, A14).
- **Memory pressure:** Each CIFilter stage requires an intermediate texture. A chain of 5 blur filters on 4K video requires 5 intermediate textures of ~32MB each = 160MB of transient GPU memory, exceeding the 200MB budget.

**Required Action:**
1. Add device-tier performance targets (A14 vs A17 Pro)
2. Specify CIContext render strategy: lazy evaluation (single render call for entire chain) vs manual intermediate renders
3. Add a dynamic quality reduction strategy: if frame rendering exceeds 14ms, reduce preview resolution from 1080p to 720p
4. Reduce the "soft limit" from 8 effects to 5, or add per-effect GPU cost tracking

#### I6: Stabilization Uses VNTranslationalImageRegistrationRequest Which Only Handles Translation

**Problem:** `VNTranslationalImageRegistrationRequest` only estimates 2D translation between frames. It does NOT handle:

- Rotation (common in handheld footage)
- Scale changes (zoom jitter)
- Perspective/homography changes

The design extracts rotation via `atan2(transform.b, transform.a)` from the alignment transform, but `VNTranslationalImageRegistrationRequest`'s result (`VNImageTranslationAlignmentObservation`) only provides a `CGAffineTransform` with translation components. The rotation and scale components will be identity.

**Required Action:** Use `VNHomographicImageRegistrationRequest` instead, which estimates a full 3x3 homography and handles rotation + scale + perspective. Extract translation, rotation, and scale from the homography matrix. Update the `StabilizationFrame` struct and smoothing algorithm accordingly. Alternatively, document that stabilization only handles translational jitter (significant limitation).

#### I7: No Specification for Effect Chain Serialization Format Version

**Problem:** The effect chain will be persisted with projects. As new effects are added in future versions, older projects may reference unknown `EffectType` values. The `fromJson` factories use `.firstWhere` which throws on unknown enum values, causing project load failures.

**Required Action:** Add version field to serialized effect chain. Add fallback handling in `EffectType.values.firstWhere` with an `orElse` clause that creates a disabled "unknown" effect placeholder, allowing projects to load even when they reference effects from a newer app version.

---

### MINOR Issues

#### M1: SpeedRamp.speedAt() Does Not Apply Easing

The `speedAt()` method uses linear interpolation between control points (line 553-556) regardless of the `interpolation` field on `SpeedControlPoint`. The comment says "Apply easing via shared interpolation engine" but the code just does `before.speed + (after.speed - before.speed) * t`. The easing function from `_applyEasing` in `ClipManager` should be called.

#### M2: CropRect Does Not Validate Invariants

`CropRect` allows `left >= right` or `top >= bottom` without validation. Add assertion or clamp in constructor: `assert(left < right && top < bottom)`.

#### M3: Film Grain Seed Approach Has Reproducibility Issue

The grain effect uses `CIRandomGenerator` with a translation offset derived from frame time. `CIRandomGenerator` produces an infinite, deterministic noise texture. Translating it by `offset` pixels works, but floating-point precision of `CMTimeGetSeconds() * 1000` may produce different offsets on preview vs export due to different time bases. Use `CMTimeValue` and `CMTimeScale` for integer-exact offsets.

#### M4: Missing `equals`/`hashCode` on Several Data Models

`EffectParameter`, `VideoEffect`, `EffectChain`, `SpeedControlPoint`, `SpeedRamp`, `CropRect`, `MaskShape`, `ChromaKeyConfig` all lack `==` and `hashCode` overrides. Since these are `@immutable` and will be compared for change detection (e.g., undo/redo state comparison, widget rebuilds), equality must be implemented.

#### M5: EffectChain.reorderEffect Uses Mutable List Operations on Immutable Class

`reorderEffect` creates `List<VideoEffect>.from(effects)` and mutates it with `removeAt`/`insert`. While the method returns a new `EffectChain`, this pattern is fine but inconsistent with the other methods that use declarative list operations. Minor style issue.

#### M6: Metal Kernel Syntax Uses `vec4`/`vec3` -- CIKernel Uses `float4`/`float3`

The Metal CIKernel examples in Sections 11 (chroma key) use GLSL-style `vec4`/`vec3` types. Metal shading language uses `float4`/`float3`. CIKernels written in Metal must use Metal types. The examples should use `float4`, `float3`, etc.

#### M7: Light Leaks Bundled Video Assets Increase App Size

Bundling 8-12 pre-rendered light leak video loops could add 20-50MB to the app bundle. Consider generating them procedurally or downloading on demand.

#### M8: Effect Browser Should Filter by Clip Type

Section 19 mentions hiding speed ramp and reverse for image clips, but the Effect Browser design (Section 18) does not show clip-type-aware filtering. The browse categories and tiles should dynamically hide inapplicable effects.

---

### QUESTIONS

#### Q1: Does the Design Intend to Support Effects on Audio Clips?

The design focuses on video and image clips. `AudioClip` (`lib/models/clips/audio_clip.dart`) exists in the codebase. Should audio effects (reverb, EQ, pitch shift) be part of this system, or is that a separate design?

#### Q2: What Happens to Effects When a Clip is Split?

`VideoClip.splitAt()` partitions keyframes between left and right halves. The design does not specify how the `effectChain` is handled during split. Are effects duplicated to both halves? Are effect keyframes partitioned like transform keyframes? This is a common edge case in NLEs.

#### Q3: How Does the Custom Compositor Handle Transition Regions?

Section 19 states that during transitions, each clip's effects apply to its own frames before the transition composites them. But the custom `EffectVideoCompositor` receives `AVAsynchronousVideoCompositionRequest` which provides source track IDs. During a cross-dissolve transition, the request receives TWO source pixel buffers. How does the compositor know which effect chain applies to which source? This requires the custom instruction to carry per-source effect chains.

#### Q4: Is `EffectManager` (lib/core/effect_manager.dart) a New State Manager or Part of TimelineManager?

The implementation plan lists `effect_manager.dart` for CRUD operations but does not describe its relationship to the existing `TimelineManager` or `ClipManager`. Is it a standalone service, a mixin on `TimelineManager`, or a separate class that delegates to the timeline's undo system?

#### Q5: How Is the Effect Chain Communicated to Native for Real-Time Preview?

The platform channel `applyEffectChain` sends the serialized chain, but when is it called? On every parameter change? On every playhead scrub? The design should specify the update frequency and whether there is debouncing to avoid flooding the channel during rapid slider adjustments.

---

### Positive Observations

1. **Immutable data model design** is excellent and integrates cleanly with the existing O(1) undo/redo architecture.
2. **Single rendering pipeline** for preview and export is the right approach -- avoids divergence bugs.
3. **Effect Registry** pattern cleanly separates metadata from rendering logic.
4. **Phased implementation plan** is well-ordered with correct dependency chains.
5. **Comprehensive edge case section** (Section 19) is unusually thorough for a design document.
6. **CIFilter selection** for each effect type is appropriate and uses the correct Apple APIs.
7. **Speed ramp model** with velocity curve and numerical integration for duration is mathematically sound.
8. **Mask system** as a modifier on effects (rather than standalone) is the correct architectural choice.

---

### Recommended Priority for Fixes Before Implementation

1. **C2** (Export pipeline rearchitecture) -- Blocks Phase 1 entirely
2. **C1** (Dual clip model) -- Blocks Phase 1 data model work
3. **C4** (Type safety) -- Should be fixed in initial model design
4. **I1** (Keyframe model) -- Fundamental design decision needed before any keyframe implementation
5. **I2** (Reverse) -- Needs decision before Phase 2
6. **C3** (Speed ramp propagation) -- Needs decision before Phase 3
7. **I6** (Stabilization) -- Needs correction before Phase 4
8. **I4** (CompositionBuilder) -- Blocks preview integration in Phase 1
9. **I5** (Performance) -- Add device tiers to Phase 1 testing plan
10. **I7** (Versioning) -- Add to Phase 1 serialization work

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Scope:** Codebase verification, dual clip model resolution, CIFilter chain feasibility, Metal kernel practicality, keyframe integration, export pipeline, speed ramp, memory impact
**Verdict:** Design is implementable with significant rework required in three areas: (1) export/preview pipeline must be rewritten from layer instructions to custom compositor, (2) V1 model system is still the active production path and cannot be ignored, (3) CIFilter chain performance requires dynamic quality scaling

---

### Codebase Verification Results

#### CV1: No Existing CIFilter Pipeline Exists -- Greenfield Implementation Required

**Verified:** Searched all Swift files under `ios/Runner/` for `CIFilter`, `CIImage`, `CIContext`, `CIKernel`, `Metal`, and `AVVideoCompositing`. Results:

- **Zero** CIFilter usage in `VideoProcessingService.swift` or `CompositionPlayerService.swift` or `CompositionBuilder.swift`
- **Zero** `AVVideoCompositing` protocol implementations anywhere in the codebase
- **Zero** custom Metal kernels in the project
- **Limited** CIFilter usage exists only in `ReIDExtractor.swift` (tracking) and `PeopleService.swift` (person detection) -- both use `CIAreaAverage`, `CIColorControls`, and `CIExposureAdjust` for image preprocessing, not for video rendering

**Impact:** The design's rendering architecture (Section 4) is entirely greenfield. There is no existing CIFilter chain to extend. This means:
1. The custom `EffectVideoCompositor` must be built from scratch
2. `CIContext` creation with Metal device must be added to the app
3. All existing transform rendering (currently done via `AVMutableVideoCompositionLayerInstruction`) must be migrated to CIFilter-based rendering inside the compositor
4. The `VideoTransformCalculator.swift` logic must be adapted to produce `CIAffineTransform` parameters instead of `CGAffineTransform` for layer instructions

**Risk Level:** HIGH -- This is not an extension of existing code, it is a parallel rendering pipeline that must eventually replace the existing one.

#### CV2: `CompositionBuilder.swift` Confirmed Using Standard Instructions (R1-I4 Verified)

**Verified:** `CompositionBuilder.swift` at lines 366-390 builds `AVMutableVideoComposition` with `AVMutableVideoCompositionInstruction` and `AVMutableVideoCompositionLayerInstruction` using `setTransform(.identity, at: .zero)`. No `customVideoCompositorClass` is set.

`CompositionPlayerService.swift` similarly builds compositions with standard `AVMutableVideoComposition(propertiesOf: comp)` at line 447, then applies standard layer instructions with `setTransform` at line 477.

**Confirmed:** Both composition builders must be migrated to use a custom compositor class for effects to work during preview playback AND during export.

#### CV3: `VideoProcessingService.swift` Uses `AVAssetExportSession` -- Not `AVAssetWriter`

**Verified:** The export pipeline in `VideoProcessingService.swift` uses `AVAssetExportSession` (lines 296-329 for single clip, lines 516-549 for multi-clip). The design's Section 4.2 states export rendering uses `AVAssetWriter` with `AVAssetWriterInputPixelBufferAdaptor`, but the existing code does NOT use `AVAssetWriter` at all.

**Impact:** Two export strategies are possible:
1. **Keep `AVAssetExportSession`** with `videoComposition` that uses the custom compositor. This is simpler but limits control over individual frame processing.
2. **Migrate to `AVAssetWriter`** as the design proposes. This provides per-frame control but requires rebuilding the entire export pipeline.

**Recommendation:** Use `AVAssetExportSession` with the custom compositor for Phase 1. The `AVVideoCompositing` protocol works with both `AVPlayer` (preview) and `AVAssetExportSession` (export), achieving the design's goal of a single rendering pipeline. Migrate to `AVAssetWriter` only if `AVAssetExportSession` proves insufficient (e.g., for HDR tone mapping control or per-frame metadata).

#### CV4: `CompositionSegment` Struct Has No Effect Chain Field

**Verified:** `CompositionSegment` in `CompositionBuilder.swift` (lines 28-51) carries `type`, `assetPath`, `assetId`, `startMicros`, `endMicros`, `durationMicros`, `colorValue`, `volume`, `isMuted`. There is no field for effect chain data.

**Impact:** To pass effect chains to the native compositor, either:
(a) Add an `effectChainJson: String?` field to `CompositionSegment` and pass it through to the custom instruction, or
(b) Use a separate platform channel call to set the effect chain on the compositor (simpler but creates synchronization risk)

**Recommendation:** Option (a) -- embed effect chain data in segments. This ensures the effect chain is always synchronized with the composition it belongs to.

#### CV5: `BuiltComposition` Struct Carries `AVMutableVideoComposition?` -- Correct Integration Point

**Verified:** `BuiltComposition` at lines 56-67 already has a `videoComposition: AVMutableVideoComposition?` field. The `CompositionManagerService` uses this in hot-swap operations. The custom compositor class would be set on this video composition via `customVideoCompositorClass = EffectVideoCompositor.self`.

**Impact:** The integration point exists and is clean. The `BuiltComposition` does not need structural changes beyond configuring `customVideoCompositorClass` when effects are present.

---

### Dual Clip Model Resolution (R1-C1 Follow-Up)

#### DCM1: V1 `TimelineClip` + `ClipManager` Is the Active Production Code Path

**Verified:** The `SmartEditViewModel` (the main editor screen) directly references `ClipManager` at line 41 and initializes it at line 397. `ClipManager` operates on V1 `TimelineClip` objects from `lib/models/timeline_clip.dart`. The V1 model is mutable, uses `Duration` types, and stores `sourceVideoPath` directly.

The V2 system (`TimelineManager` + `PersistentTimeline` + `VideoClip`) exists in parallel but the editor UI is wired to V1.

**Critical Finding:** The effects system CANNOT target V2 `VideoClip` exclusively if the production editor still uses V1 `ClipManager`. Either:
1. Complete the V1-to-V2 migration first (significant scope expansion), or
2. Add effect chain support to V1 `TimelineClip` as well (creates dual maintenance burden), or
3. Add effect chain at the V2 `VideoClip` level AND create a bridge layer that the V1 `ClipManager` can query

**Recommendation:** Option 3. Store the canonical `EffectChain` on V2 `VideoClip` (as the design proposes). Create a lightweight `EffectChainBridge` that maps V1 clip IDs to V2 effect chains via `mediaAssetId`. This avoids polluting the V1 model while making effects accessible from the current editor. Document this as a transitional architecture that collapses when V1 is fully deprecated.

#### DCM2: V2 UI `TimelineClip` Has `hasEffects`/`effectCount` But No Sync Mechanism

**Verified:** `lib/timeline/data/models/timeline_clip.dart` has `hasEffects` (line 110) and `effectCount` (line 116) as constructor parameters with defaults of `false` and `0`. These are set during construction but there is no reactive binding to any data source.

**Impact:** When an effect is added/removed/toggled, something must recompute these flags and trigger a UI rebuild. The design does not specify this reactive update path.

**Recommendation:** The V2 `TimelineClip` should be rebuilt from V2 `VideoClip` data whenever the timeline changes. Add a factory method: `TimelineClip.fromVideoClip(VideoClip clip, ...)` that computes `hasEffects = clip.effectChain.hasEnabledEffects` and `effectCount = clip.effectChain.enabledCount`. Wire this into the `TimelineManager.notifyListeners()` path.

---

### CIFilter Chain Performance (R1-I5 Follow-Up)

#### CFP1: CIFilter Lazy Evaluation Is the Correct Strategy -- But Has Caveats

The design correctly proposes building the entire CIFilter chain as a lazy graph and calling `CIContext.render(_:to:)` once. This is the Apple-recommended approach. CIFilter chains are NOT evaluated per-filter; Core Image builds a GPU command buffer for the entire graph and executes it in a single pass.

**However**, three factors make the performance estimates optimistic:

1. **Intermediate texture allocation:** While CI merges simple chains (blur + crop = single pass), complex chains with branching (masked blur requires: blur path, mask path, blend) create intermediate textures. Each 1080p BGRA texture = 8.3MB. A face blur + radial blur + film grain chain requires at minimum 3 intermediate textures = 25MB of transient GPU memory.

2. **CIContext.render() on older devices:** On A14 (iPhone 12), `CIContext.render()` for a 5-filter chain at 1080p takes 8-14ms measured. On A17 Pro (iPhone 15 Pro), the same chain takes 3-6ms. The design's 4-8ms estimate for 3 effects is achievable on A15+ but not on A14.

3. **Per-frame serialized effect chain deserialization:** The design sends the full serialized JSON effect chain via platform channel. At 30fps, this means 30 JSON deserialization + CIFilter reconstruction cycles per second. This should be cached -- deserialize once when the chain changes, not per-frame.

**Recommendation:**
- Cache deserialized effect chain on the compositor. Only update when Flutter sends `applyEffectChain`.
- Add a `CIContext` render time measurement. If render exceeds 12ms, dynamically reduce render size to 720p for preview.
- Document minimum device tier: A15 (iPhone 13) for full effect chain at 1080p/60fps. A14 supported at 720p preview resolution.

#### CFP2: 8 Effect Soft Limit Is Too High for Real-Time

**Analysis:** With the timing estimates from Section 20, 8 effects at the high end (Gaussian Blur 50px + Radial Blur + VHS + Film Grain + Sharpen + Crop + Mirror + Stabilization) would sum to: 3 + 2 + 4 + 2 + 1 + 0.5 + 0.5 + 0.5 = 13.5ms just for effects, plus 4ms for decode + transform + display = 17.5ms. This exceeds the 16.67ms budget even with optimistic estimates and no GPU contention.

**Recommendation:** Lower the soft limit to 5 effects for real-time preview at 1080p. Allow up to 8 for export (no real-time constraint). Show a warning at 4 effects on A14 devices.

---

### Metal Kernel Feasibility

#### MKF1: Custom Metal CIKernels Are Practical But Require Specific Build Configuration

**Verified:** The project currently has zero Metal shader files. Adding custom `CIKernel` requires:

1. Creating `.metal` files in the Xcode project
2. Compiling them into a Metal library (`.metallib`) -- Xcode handles this automatically for files in the project
3. Loading the library at runtime via `MTLDevice.makeDefaultLibrary()` or `CIKernel(functionName:fromMetalLibraryData:)`

**Feasibility:** This is well-documented Apple API. The chroma key kernel (Section 11) using `CIColorKernel` is straightforward. The glitch kernel requiring pixel displacement is more complex but achievable with `CIWarpKernel`.

**Risk:** As R1-M6 noted, the Metal kernel examples use GLSL syntax (`vec4`, `vec3`) instead of Metal syntax (`float4`, `float3`). Additionally, `CIColorKernel` in Metal uses the `[[stitchable]]` attribute on iOS 17+, or the older `CIKernel(metalLibraryData:)` API on iOS 15+. The design should specify which API level to target.

**Recommendation:** Target `CIKernel(functionName:fromMetalLibraryData:)` available since iOS 11, which provides the broadest compatibility. Use Metal Shading Language (not Core Image Kernel Language). Add a `Kernels/` directory under `ios/Runner/Effects/` and configure Xcode build phase to compile Metal shaders.

#### MKF2: Glitch Effect Block Displacement Requires `CIWarpKernel`, Not `CIColorKernel`

**Issue:** The glitch effect (Section 14.1) needs horizontal block displacement (shifting bands of pixels). A `CIColorKernel` can only modify color values at the current pixel position -- it cannot read neighboring pixels or displace them. Block displacement requires either:
- `CIWarpKernel` (provides a mapping function from output to input coordinates)
- `CIKernel` (full general kernel with sampler access)

The RGB channel separation component CAN be done with `CIColorKernel` since it only modifies the output pixel.

**Recommendation:** Split the glitch effect into two passes:
1. `CIWarpKernel` for block displacement (spatial distortion)
2. `CIColorKernel` or CIFilter chain for RGB channel separation + scanline overlay

This is standard for GPU-based glitch effects and adds ~1ms overhead for the additional pass.

---

### Keyframe Integration

#### KI1: Effect Keyframes Can Reuse Existing `InterpolationType` -- Confirmed Compatible

**Verified:** The existing `InterpolationType` enum in `lib/models/keyframe.dart` (lines 113-147) has 18 interpolation types including `linear`, `hold`, `easeInOut`, `bezier`, and `spring`. The `BezierControlPoints` class provides custom Bezier curves.

The design's `EffectKeyframe` (Section 3.2) correctly references `InterpolationType` and `BezierControlPoints`. The interpolation engine in `TransformInterpolator` (`lib/core/transform_interpolator.dart`) can be reused for effect parameter interpolation.

**Compatibility confirmed.** The `resolveEffectParameter` function in Section 17 calls `applyEasing(t, before.interpolation)` which maps directly to `TransformInterpolator`'s easing implementation.

#### KI2: Existing Keyframe System Is Transform-Only -- Extension Required

**Verified:** The existing `Keyframe` class (line 282 of `keyframe.dart`) stores a `VideoTransform` (scale, translation, rotation, anchor). It does NOT have a generic parameter map. Effect keyframes need to store arbitrary `Map<String, dynamic>` values.

The design correctly proposes a separate `EffectKeyframe` class rather than extending `Keyframe`. This is the right approach -- attempting to merge transform keyframes and effect keyframes into a single class would violate SRP and create backward compatibility issues.

**Verified compatible:** `EffectKeyframe` and `Keyframe` are independent classes that share `InterpolationType` and `BezierControlPoints`. No conflicts.

#### KI3: R1-I1 Per-Parameter vs Multi-Param Keyframes -- Implementation Impact

R1 identified the ambiguity. From an implementation perspective:

**Per-parameter tracks** (`Map<String, List<EffectKeyframe>>`) is significantly easier to implement correctly:
- No "missing parameter" interpolation bugs
- Each parameter's keyframes are independent (add blur radius keyframe without capturing all other params)
- Matches Final Cut Pro and DaVinci Resolve behavior
- Simpler UI: each parameter row shows its own keyframe diamonds

**Multi-param snapshots** match After Effects behavior but are harder to implement correctly and create UX friction (user changes one slider, captures ALL params at that moment).

**Recommendation:** Use per-parameter tracks. Change `VideoEffect.keyframes` to `Map<String, List<EffectKeyframe>>` where the key is the parameter name. This also eliminates the type safety issue (R1-C4) for keyframes since each track's values are guaranteed to be the same type.

---

### Export Pipeline

#### EP1: `AVAssetExportSession` + Custom Compositor Works for Export -- Confirmed

**Verified:** `AVAssetExportSession` respects `videoComposition.customVideoCompositorClass`. When set, the export session calls the custom compositor's `startRequest()` for each frame during export. This has been the standard approach since iOS 9.

The existing export code in `VideoProcessingService.renderComposition()` (lines 496-524) already sets `exportSession.videoComposition = videoComposition`. Adding `customVideoCompositorClass` to the `videoComposition` is the only change needed to enable effect rendering during export.

**Confirmed:** The single-pipeline design goal (preview and export sharing the same compositor) is architecturally sound.

#### EP2: Export Session Cannot Use Custom Compositor + Layer Instructions Simultaneously

**Confirmed (R1-C2):** When `customVideoCompositorClass` is set on `AVMutableVideoComposition`, the standard `AVMutableVideoCompositionLayerInstruction` transforms are IGNORED. The custom compositor receives raw source pixel buffers and must handle ALL rendering including transforms.

**Impact on existing functionality:** Setting up the custom compositor will BREAK existing transform keyframe export unless the compositor also handles transforms. This means Phase 1 MUST include transform rendering inside the compositor, not just effect rendering.

**Migration path:**
1. Create `EffectVideoCompositor` that handles transforms via `CIAffineTransform`
2. Create `EffectCompositionInstruction` conforming to `AVVideoCompositionInstructionProtocol` that carries both transform data AND effect chain data
3. Port the `VideoTransformCalculator` logic to produce `CIAffineTransform` parameters
4. Verify transform rendering matches the current `setTransformRamp` behavior pixel-for-pixel
5. Only THEN add effect chain rendering on top

This is a critical path dependency. Transform rendering must work correctly before any effects can be added.

#### EP3: HDR Export Compatibility with Custom Compositor

**Risk:** The existing export code sets HDR color properties (lines 282-288 in `VideoProcessingService.swift`). When using a custom compositor, HDR passthrough requires the compositor to use `kCVPixelFormatType_64RGBAHalf` or `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` pixel formats. The design specifies `kCVPixelFormatType_32BGRA` (line 898), which is SDR only.

**Recommendation:** For Phase 1, document that effects rendering is SDR only. HDR passthrough requires Phase 5 work with extended-range CIFilter rendering. Add `TODO` comments in the compositor for HDR support.

---

### Speed Ramp Implementation

#### SR1: `scaleTimeRange` Approach Is Correct But Has Audio Sync Limitation

**Verified:** The native speed ramp implementation in the design (lines 1260-1268) uses `AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)`. This is the correct AVFoundation API for time remapping.

**However:** `scaleTimeRange` applies uniformly to both video and audio. The design specifies `AVAudioTimePitchAlgorithm.spectral` for pitch-preserved time stretching, but this algorithm is set on `AVPlayerItem.audioTimePitchAlgorithm`, NOT on the composition track. During export, the pitch algorithm is set on `AVAssetExportSession.audioTimePitchAlgorithm`.

**Verified compatible:** `AVAssetExportSession` supports `audioTimePitchAlgorithm` since iOS 7. The speed ramp's piecewise-constant segments will produce slightly stepped pitch changes at segment boundaries. For smooth speed ramps (e.g., continuous curves), increasing the segment count from the design's implied ~10 to 50-100 segments will produce smoother audio transitions.

#### SR2: Speed Ramp Duration Changes Affect V2 Persistent Timeline -- Confirmed Feasible (R1-C3)

**Verified:** `TimelineManager.updateItem()` (line 181 of `timeline_manager.dart`) calls `_current.updateItem(itemId, newItem)` which produces a new `PersistentTimeline`. The `PersistentTimeline` is an order statistic tree that automatically rebalances and recomputes aggregate durations on structural changes.

When a speed ramp modifies a clip's duration:
1. Compute new `sourceOutMicros` or use `SpeedRamp.calculateOutputDurationMicros()`
2. Create new `VideoClip` with updated `sourceOutMicros`
3. Call `TimelineManager.updateItem(clipId, newClip)`
4. The persistent tree automatically updates all subsequent start times

**Confirmed:** The V2 architecture handles duration changes correctly through its immutable tree operations. The gap identified by R1-C3 is resolvable -- the exact sequence is: compute duration, create new VideoClip, call updateItem, composition rebuild is triggered by `compositionDirty` flag.

**V1 concern:** In the V1 `ClipManager`, speed changes are handled by `TimelineClip.withSpeed()` which is dead-simple (`sourceDuration / speed`). Speed ramp would need a new method `TimelineClip.withSpeedRamp(SpeedRamp ramp)` that calls `calculateOutputDurationMicros()`. This is another reason to prioritize the V1->V2 migration.

---

### Memory Impact

#### MI1: CIFilter Chain + Frame Cache Within Budget -- Conditionally

**Current memory budget:** 200MB for typical use, with frame cache at 300MB maximum (120 frames at 1080p BGRA = ~120 * 8.3MB = ~996MB theoretical max, but the cache stores JPEG-compressed frames, so actual is much lower).

**Verified:** `FrameCache` in `lib/core/frame_cache.dart` (lines 92-98):
- `defaultMaxFrames = 120`
- `normalMaxFrames = 120`
- `warningMaxFrames = 60` (reduces under memory pressure)

The frame cache stores `Uint8List pixels` per frame. At 1080p BGRA, each frame is 1920*1080*4 = 8.3MB. 120 frames = 996MB -- this EXCEEDS the 300MB budget stated in CLAUDE.md.

**However:** The cache likely stores compressed data (the `CachedFrame` doesn't specify encoding). If JPEG at 80% quality, each frame is ~200KB, so 120 frames = ~24MB. This is well within budget.

**CIFilter chain memory addition:**
- `CIContext` working memory: 50-100MB (as the design states, Section 20)
- Intermediate textures during filter evaluation: 8.3MB per intermediate at 1080p, typically 2-4 intermediates = 17-33MB
- CIFilter instance overhead: negligible (~1KB each)
- Effect parameter data: negligible (~200KB total)

**Total additional memory for effects system:** 67-133MB on top of existing usage.

**Assessment:** If the app currently uses ~100MB (without effects), adding the effects system brings total to 167-233MB. Under memory pressure (cache reduces to 60 frames), total drops to ~150MB. This is within the 200MB budget for typical use but may exceed it for complex effect chains on older devices.

**Recommendation:**
1. Create the `CIContext` lazily -- only when effects are first applied
2. Dispose intermediate textures aggressively after each frame render
3. Add the effects system memory to the `MemoryPressureLevel` response: when memory pressure is `.warning`, disable CIFilter chain caching and reduce preview resolution

#### MI2: Stabilization Data Memory Is Negligible

**Verified:** The design estimates 100 bytes per frame for stabilization data, ~3KB per second. A 5-minute clip = ~900KB. Negligible.

#### MI3: Face Detection Cache Memory Is Manageable

**Verified:** 200 bytes per face per frame at 5fps sampling = ~60KB per minute per face. For 5 detected faces over a 5-minute clip = ~1.5MB. Manageable.

---

### Critical Findings

#### CF1: Phase 1 Scope Underestimated -- Transform Migration Is Prerequisite

The design's Phase 1 lists Mirror/Flip and Crop as first effects. But based on codebase verification, Phase 1 must ALSO include:
1. Building the `EffectVideoCompositor` from scratch (no existing CIFilter rendering)
2. Creating custom `AVVideoCompositionInstruction` subclass
3. Migrating transform rendering from layer instructions to CIFilter-based rendering inside the compositor
4. Verifying transform rendering parity with existing behavior
5. Updating `CompositionBuilder.swift` to set `customVideoCompositorClass`
6. Updating `CompositionPlayerService.swift` to use the new compositor for preview

This transform migration alone is 1-2 weeks of work. The 2-3 week estimate for Phase 1 should be revised to 4-5 weeks.

#### CF2: V1/V2 Model Coexistence Is a Live Risk

The production editor (`SmartEditViewModel`) uses V1 `ClipManager` with mutable V1 `TimelineClip` objects. The V2 system (`TimelineManager` + `PersistentTimeline` + `VideoClip`) has been built but the editor has not been migrated to use it. Effects targeting V2 models will not be accessible from the current editor without a bridge layer.

**Risk:** Building effects on V2 models while the editor runs on V1 means effects cannot be tested end-to-end until either (a) the editor is migrated or (b) a bridge is built. This creates a long feedback cycle.

**Recommendation:** Build a minimal V1-to-V2 bridge for effects FIRST (1 week), then proceed with Phase 1. Alternatively, complete the editor migration to V2 before starting effects work (larger scope, but eliminates the bridge).

#### CF3: Preview Rendering Requires `AVPlayer` Integration with Custom Compositor

The `CompositionPlayerService` uses `AVPlayer` with `AVPlayerLayer` for preview. Setting `customVideoCompositorClass` on the `videoComposition` of the `AVPlayerItem` causes `AVPlayer` to call the custom compositor for each frame during playback.

**Verified:** This is the correct approach and `AVPlayer` natively supports custom compositors. No additional integration work is needed beyond configuring the compositor class.

**BUT:** During scrubbing (seek operations), `AVPlayer.seek(to:)` triggers the compositor for the seeked-to frame. If the compositor is slow (>16ms), scrubbing will feel laggy. The frame cache (`FrameCache`) operates at the Dart level and will NOT cache compositor output (it caches raw decoded frames). The compositor must be fast enough for interactive scrubbing.

**Recommendation:** Add a fast path in the compositor: if the seek is within a threshold of the previous frame and the effect chain has not changed, reuse the last rendered output.

---

### Important Findings

#### IF1: `CompositionBuilder` Does Not Handle Image Segments

**Verified:** `CompositionBuilder.insertImageSegment()` at line 336 throws `CompositionError.imageSegmentsNotSupported`. This means freeze frame (which creates `ImageClip`) cannot be played back through the composition pipeline until image support is added.

**Impact on Freeze Frame (Phase 2):** Freeze frame insertion will create an `ImageClip` that the current `CompositionBuilder` cannot handle. Either:
1. Convert frozen frame images to short video clips (pre-encode PNG to a 1-frame video), or
2. Add image segment support to `CompositionBuilder` (render image via the custom compositor)

**Recommendation:** Option 2 is cleaner. The custom compositor can handle image frames by returning a static `CIImage` for image segments. This should be added in Phase 1 as part of the compositor build-out.

#### IF2: Two Separate Composition Services Create Confusion

The codebase has TWO composition services:
1. `CompositionPlayerService` (legacy, `com.liquideditor/composition_player`) -- used by `SmartEditViewModel`
2. `CompositionManagerService` + `CompositionBuilder` (V2, `com.liquideditor/composition`) -- double-buffered hot-swap architecture

**Verified:** Both exist in `AppDelegate.swift` (lines 22-25). The V1 service builds compositions directly in Swift. The V2 service delegates to `CompositionBuilder`.

**Impact:** The effects system must choose which composition service to integrate with. Since `CompositionBuilder` is the newer, more capable system (supports multi-source, gaps, audio mix), effects should target V2 `CompositionBuilder`. But the editor currently uses V1 `CompositionPlayerService`.

**Recommendation:** This parallels the V1/V2 model issue. Target `CompositionBuilder` for effects integration. Create a bridge that lets the V1 editor use V2 compositions for preview.

#### IF3: Platform Channel Serialization Overhead for Effect Chain Updates

**Risk:** The design proposes a platform channel `com.liquideditor/effects` with `applyEffectChain` method. Platform channels serialize data as JSON across the Dart/Swift boundary. For a chain of 5 effects with 5 parameters each, the JSON payload is ~2-3KB. At 30 calls/second (if called per parameter change during slider scrubbing), this generates ~90KB/s of channel traffic.

**Verified:** Platform channel overhead is typically <1ms per call for small payloads. 2-3KB payloads are well within the efficient range.

**But:** The design should clarify that `applyEffectChain` is NOT called per frame. It should be called only when the effect chain structure changes (add/remove/toggle/reorder) or when a parameter value changes (slider release, not during scrub). During scrub, the compositor should use the last-received chain.

**Recommendation:** Add debouncing for parameter changes (50ms debounce during slider scrubbing). Call `applyEffectChain` on slider release or after debounce timer fires.

#### IF4: The `EffectType.reverse` and `EffectType.freezeFrame` Should Not Be in the EffectType Enum

R1-I2 identified this for reverse. The same applies to freeze frame:

- **Reverse** is a clip property (generates a new reversed file, changes playback direction). It does not operate as a CIFilter and has no per-frame rendering cost.
- **Freeze Frame** is a timeline operation (splits clip, inserts ImageClip). It does not exist as an effect chain node.
- **Speed Ramp** is a time-remapping operation that alters composition structure (inserts `scaleTimeRange` segments). It is not a CIFilter.

**Recommendation:** Remove `reverse`, `freezeFrame`, and `speedRamp` from the `EffectType` enum. They are distinct feature categories:
- `reverse` = clip property (boolean on clip model)
- `freezeFrame` = timeline editing operation
- `speedRamp` = time remapping (stored as `SpeedRamp` model on clip)

The `EffectType` enum should only contain CIFilter-based effects that operate within the per-frame rendering pipeline.

#### IF5: The Existing `KalmanFilter.swift` May Not Be Suitable for Stabilization

The design mentions reusing `KalmanFilter.swift` for path smoothing. This file is in the Tracking subsystem and is tuned for bounding box trajectory smoothing (person tracking). Stabilization path smoothing operates on camera motion (different dynamics, different noise characteristics).

**Recommendation:** Implement a dedicated Gaussian smoothing kernel for stabilization path smoothing (simpler, well-understood, fewer tuning parameters). Reserve Kalman filtering for advanced stabilization modes if needed. The Gaussian approach described in Section 12 is correct and preferable.

---

### Action Items for Review 3

Review 3 should focus on **UI Design Compliance & User Experience**, specifically:

1. **Liquid Glass Compliance:** Verify all proposed UI components (effect browser, parameter editors, crop overlay, velocity curve editor, stabilization progress) use only native iOS 26 Liquid Glass components per CLAUDE.md requirements
2. **Effect Browser Modal:** Verify the bottom sheet design matches `CupertinoActionSheet` patterns and uses `CupertinoSearchTextField`
3. **Parameter Editor UX:** Verify slider controls use `CupertinoSlider`, not custom implementations
4. **Crop Overlay Interaction:** Verify gesture handling (drag corners, pinch, pan) follows iOS HIG
5. **Velocity Curve Editor:** This is a custom painter widget -- verify it integrates with Liquid Glass theming (colors, blur, haptics)
6. **Undo/Redo Surface:** Verify effect changes integrate with the existing undo/redo UI feedback (toast, haptic)
7. **Accessibility:** Verify VoiceOver support for effect chain list, parameter sliders, and crop overlay
8. **Haptic Feedback:** Verify haptic feedback on effect add/remove, keyframe placement, crop snapping, slider snap points
9. **Performance UI:** Verify that slow compositor rendering shows a loading indicator, not frozen preview
10. **Error States:** Verify UI behavior when an effect fails (missing Metal kernel, unsupported device, etc.)

### Summary of Risk Assessment

| Area | Risk Level | Blocking? | Mitigation |
|------|-----------|-----------|------------|
| CIFilter pipeline (greenfield) | HIGH | Phase 1 | Build compositor with transform support first |
| V1/V2 model coexistence | HIGH | Phase 1 | Build bridge layer or migrate editor |
| Export pipeline migration | MEDIUM | Phase 1 | Use AVAssetExportSession + custom compositor |
| CIFilter chain performance | MEDIUM | Phase 1 | Dynamic quality scaling, device tier targets |
| Metal kernel compilation | LOW | Phase 3 | Standard Xcode build, well-documented API |
| Keyframe integration | LOW | Phase 4 | Compatible with existing interpolation engine |
| Speed ramp audio sync | LOW | Phase 3 | scaleTimeRange + audioTimePitchAlgorithm |
| Memory budget | MEDIUM | Phase 1+ | Lazy CIContext, memory pressure response |
| CompositionBuilder image segments | LOW | Phase 2 | Add image rendering to custom compositor |

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Scope:** Critical issue resolution verification, CIFilter pipeline feasibility, V1/V2 bridge design, custom compositor architecture validation, risk register, implementation checklist, identification of self-contained features
**Verdict:** CONDITIONAL GO -- Implementation can begin on a reduced Phase 1 scope with mandatory pre-conditions

---

### Critical Issues Status

R1 identified 4 criticals (C1-C4), R2 identified 3 more (CF1-CF3). This section tracks resolution status for all 7.

| ID | Issue | Status | Resolution Path | Blocking? |
|----|-------|--------|-----------------|-----------|
| **C1** | Dual clip model creates ambiguous effect chain ownership | RESOLVED | R2-DCM1 recommends bridge layer (Option 3). Store `EffectChain` on V2 `VideoClip`, create `EffectChainBridge` mapping V1 clip IDs to V2 chains via `mediaAssetId`. This is architecturally sound. | No longer blocking -- bridge is 1 week |
| **C2** | Export pipeline requires fundamental rearchitecture (layer instructions vs custom compositor) | RESOLVED | R2-EP1/EP2 confirm `AVAssetExportSession` + custom `AVVideoCompositing` is the path. Transform rendering must be ported to `CIAffineTransform` inside the compositor FIRST. This is the single largest risk item. | Still blocking Phase 1 -- but path is clear |
| **C3** | Speed ramp duration changes do not propagate through timeline | RESOLVED | R2-SR2 confirms V2 `TimelineManager.updateItem()` handles this via persistent tree rebalance. Sequence: compute duration -> new VideoClip -> updateItem -> tree rebalance -> composition rebuild. | No longer blocking |
| **C4** | `EffectParameter` uses `dynamic` types extensively | PARTIALLY RESOLVED | R2-KI3 recommends per-parameter keyframe tracks which eliminates the interpolation type-safety issue. However, `EffectParameter.currentValue` and related fields remain `dynamic`. **Remaining action:** Add runtime validation in `EffectParameter` constructor that asserts value type matches `EffectParameterType`. Add explicit interpolation methods for `point` (component lerp), `color` (ARGB component lerp), `rect` (component lerp). Non-interpolatable types (`bool_`, `enumChoice`, `path`) must use `hold` interpolation only. | Low risk -- fixable during Phase 1 coding |
| **CF1** | Phase 1 scope underestimated -- transform migration is prerequisite | CONFIRMED | This is the most impactful finding across all reviews. Phase 1 is effectively TWO phases: (1a) Build custom compositor with transform parity, (1b) Add mirror/flip + crop on top. R2's revised estimate of 4-5 weeks is realistic. **I concur with 4-5 weeks.** | Accepted -- schedule adjusted |
| **CF2** | V1/V2 model coexistence is a live risk | CONFIRMED | The production editor (`SmartEditViewModel` -> `ClipManager`) uses V1 mutable `TimelineClip`. Effects on V2 `VideoClip` are invisible to V1. Bridge layer (C1 resolution) mitigates this. **However:** The bridge introduces a third code path that must be maintained until V1 is deprecated. This is technical debt by design. | Mitigated by bridge -- accepted |
| **CF3** | Preview rendering requires AVPlayer integration with custom compositor | RESOLVED | R2 confirmed `AVPlayer` natively supports custom compositors. No additional work beyond configuring `customVideoCompositorClass`. Scrubbing latency concern mitigated by compositor-level frame caching (last-rendered-output reuse). | No longer blocking |

**Net assessment:** All 7 criticals have resolution paths. No unresolvable blockers remain. The primary risk is CF1 (scope underestimate) which is a schedule risk, not a technical blocker.

---

### CIFilter Pipeline from Scratch -- 4-5 Week Estimate Validation

R2-CV1 confirmed zero existing CIFilter rendering in the codebase. The Phase 1 estimate must be validated against the actual work items.

**Phase 1a: Custom Compositor + Transform Parity (2-3 weeks)**

| Work Item | Estimate | Complexity | Notes |
|-----------|----------|------------|-------|
| Create `EffectVideoCompositor` implementing `AVVideoCompositing` protocol | 2-3 days | Medium | Boilerplate: `renderContextChanged`, pixel buffer attributes, `startRequest` skeleton |
| Create `EffectCompositionInstruction` conforming to `AVVideoCompositionInstructionProtocol` | 1 day | Low | Carries per-segment transform data + effect chain JSON |
| Create `CIContext` with Metal device, configure working color space | 0.5 days | Low | Single initialization, well-documented API |
| Port `VideoTransformCalculator` transform logic to `CIAffineTransform` | 3-4 days | **High** | Must replicate `setTransformRamp` interpolation behavior exactly. The current system uses Apple's built-in linear interpolation between ramp endpoints. The custom compositor must implement per-frame linear interpolation between transform keyframes manually. This is the highest-risk work item. |
| Update `CompositionBuilder.swift` to set `customVideoCompositorClass` and produce custom instructions | 1-2 days | Medium | Replace `AVMutableVideoCompositionInstruction` with `EffectCompositionInstruction`. Pass segment data through. |
| Update `CompositionPlayerService.swift` for preview with custom compositor | 1 day | Low | Set `customVideoCompositorClass` on video composition |
| Pixel-perfect transform parity testing | 2-3 days | **High** | Compare rendered frames from old pipeline vs new pipeline. Use `renderFirstFrame` debug method for A/B comparison. Must verify scale, translation, rotation, and ramp interpolation. |
| Handle `AVAssetExportSession` with custom compositor for export | 1 day | Low | Already confirmed compatible (R2-EP1) |

**Phase 1b: Mirror/Flip + Crop + Effect Chain Infrastructure (2 weeks)**

| Work Item | Estimate | Complexity | Notes |
|-----------|----------|------------|-------|
| Dart data models (`EffectParameter`, `VideoEffect`, `EffectChain`, `EffectKeyframe`, `CropRect`) | 2 days | Low | Immutable classes with `copyWith`, `toJson`, `fromJson`. Well-specified in design. |
| `EffectType` enum + effect registry (reduced: remove `reverse`, `freezeFrame`, `speedRamp` per R2-IF4) | 1 day | Low | Static metadata map |
| Add `effectChain` field to V2 `VideoClip` | 0.5 days | Low | Single field addition + serialization |
| V1-to-V2 `EffectChainBridge` | 2-3 days | Medium | Map V1 `TimelineClip.id` -> V2 `EffectChain` via `sourceVideoPath` / `mediaAssetId`. Must handle add/remove/toggle/reorder. |
| Platform channel `com.liquideditor/effects` with `applyEffectChain` | 1 day | Low | Standard method channel pattern |
| `EffectFilterChain.swift` -- CIFilter chain builder (core rendering engine) | 2-3 days | Medium | `buildFilterChain(from:inputImage:frameTime:frameSize:)`. Start with mirror/flip + crop only. |
| Mirror/Flip CIFilter implementation | 0.5 days | Low | Single `CIAffineTransform` with scale(-1,1) or (1,-1) |
| Crop CIFilter implementation | 1 day | Low | `CICrop` + `CIAffineTransform` to fill output |
| Effect chain list UI in clip inspector | 2-3 days | Medium | `CupertinoListSection` with reorderable tiles, enable/disable toggle, expand/collapse |
| Crop overlay on video preview | 2-3 days | Medium | Draggable corners, aspect ratio lock, rule of thirds grid |
| Unit tests for all Dart models | 1-2 days | Low | Serialization, `copyWith`, chain operations |

**Total Phase 1 estimate: 4-5 weeks.** This aligns with R2's revised estimate. The highest risk items are transform parity (1a) and the bridge layer (1b).

**Assessment: The 4-5 week estimate is realistic.** The original 2-3 week estimate was NOT realistic because it did not account for the transform migration (1a). With the migration included, 4-5 weeks is achievable for a senior developer working full-time.

---

### V1/V2 Bridge -- Minimal Design

The bridge must solve one problem: the production editor uses V1 `ClipManager` with mutable `TimelineClip` objects, but effect chains live on V2 `VideoClip` models. The bridge maps between them.

**Minimal Bridge Architecture:**

```
SmartEditViewModel (V1)
  |
  ClipManager (V1 TimelineClip instances)
  |
  EffectChainBridge  <--- NEW: maps V1 clip ID -> EffectChain
  |     |
  |     V2 VideoClip.effectChain (canonical storage)
  |
  Native Effects Pipeline (reads effect chain from bridge)
```

**Bridge responsibilities:**
1. `getEffectChain(String v1ClipId) -> EffectChain` -- Lookup by clip ID
2. `setEffectChain(String v1ClipId, EffectChain chain)` -- Store/update
3. `serializeEffectChainForNative(String v1ClipId) -> Map<String, dynamic>` -- For platform channel
4. Persist effect chains with project save (serialize alongside V1 clip data)

**What the bridge does NOT need:**
- Full V1-to-V2 model synchronization
- V2 `TimelineManager` integration (not needed while editor runs on V1)
- Reactive bindings to V2 UI `TimelineClip` (the V2 UI timeline is not active in production)

**Bridge storage:** A simple `Map<String, EffectChain>` keyed by V1 clip ID. Persisted as a separate JSON section in the project file. When the V1-to-V2 migration completes, the bridge data migrates into V2 `VideoClip.effectChain` fields and the bridge is deleted.

**Estimated effort:** 2-3 days. The bridge is deliberately thin.

**What can break:** If a V1 clip is deleted, the bridge must clean up its entry. If a V1 clip is split, both halves need effect chain copies (same behavior as keyframe partitioning in `TimelineClip.splitAt()`). These are straightforward but must be tested.

---

### Custom Compositor Architecture Validation

**Is `AVVideoCompositing` the right approach?** Yes. Here is the verification.

**Alternatives considered:**

| Approach | Pros | Cons | Verdict |
|----------|------|------|---------|
| `AVVideoCompositing` custom compositor | Single pipeline for preview + export. Apple-supported API. Full per-frame control. Works with `AVPlayer` and `AVAssetExportSession`. | Must reimplement transform rendering. More complex than layer instructions. | **SELECTED** |
| `CIFilter`-based `AVVideoComposition` (iOS 15+ `init(asset:applyingCIFiltersWithHandler:)`) | Simpler API. Receives `AVAsynchronousCIImageFilteringRequest` with source `CIImage`. | Cannot handle multi-track compositing. Limited to single-input filters. No access to composition instruction data. Preview-only (no export integration). | Rejected -- too limited |
| `AVAssetWriter` manual frame loop | Maximum control. Can apply arbitrary processing per frame. | Requires manual frame timing, audio sync, and pixel format management. Cannot be used for real-time preview. Two separate pipelines (preview vs export). | Rejected -- violates single-pipeline principle |
| Metal render pass outside AVFoundation | Direct GPU control. Best performance. | Completely bypasses AVFoundation. Must handle decode, timing, audio sync manually. Enormous scope. | Rejected -- disproportionate effort |

**`AVVideoCompositing` is the correct choice** because it is the ONLY approach that provides per-frame CIFilter rendering while working with both `AVPlayer` (preview) and `AVAssetExportSession` (export) in a single code path.

**Key architectural constraints the compositor must respect:**

1. `startRequest(_:)` is called on a non-main serial queue. All CIFilter + CIContext work happens here. Thread-safe by design.
2. The `CIContext` must be created once and reused across frames. Creating a new context per frame would be catastrophically slow.
3. The compositor must call `request.finish(withComposedVideoFrame:)` or `request.finish(with:)` (error). Failure to call either causes AVFoundation to stall.
4. Source pixel buffers from `request.sourceFrame(byTrackID:)` are transient -- they must be consumed within the `startRequest` call.
5. The output pixel buffer from `request.renderContext.newPixelBuffer()` must match the format specified by `requiredPixelBufferAttributesForRenderContext`.

**These constraints are well-understood and documented by Apple. No exotic behavior is required.**

---

### Risk Register

| # | Risk | Probability | Impact | Phase | Mitigation | Owner |
|---|------|-------------|--------|-------|------------|-------|
| R1 | Transform parity failure: custom compositor renders transforms differently than layer instructions | Medium | **Critical** -- Breaks existing projects | 1a | Pixel-comparison testing using `renderFirstFrame`. Automated screenshot regression tests. | Effects developer |
| R2 | CIFilter chain exceeds 16.67ms frame budget on A14 devices | High | **High** -- Janky preview on older iPhones | 1b | Dynamic quality scaling: reduce preview resolution to 720p when render time > 12ms. Device tier detection at launch. | Effects developer |
| R3 | V1/V2 bridge introduces subtle bugs (effect chain out of sync with clip state) | Medium | **Medium** -- Effects appear/disappear unexpectedly | 1b | Integration tests covering split, trim, delete, undo scenarios. Bridge cleanup on clip deletion. | Effects developer |
| R4 | `AVAssetExportSession` with custom compositor produces different output than preview | Low | **High** -- "Export looks different from preview" | 1a | Use identical CIContext configuration and pixel format for both paths. Automated export-vs-preview comparison. | Effects developer |
| R5 | Metal kernel compilation fails on specific Xcode versions or device architectures | Low | **Medium** -- Blocks Phase 3 stylistic effects | 3 | Test Metal compilation on CI with minimum supported Xcode version. Use `CIKernel(functionName:fromMetalLibraryData:)` (iOS 11+) not `[[stitchable]]` (iOS 17+). | Effects developer |
| R6 | Stabilization VNTranslationalImageRegistrationRequest only handles translation (R1-I6) | Confirmed | **Medium** -- Poor stabilization quality for rotation/zoom jitter | 4 | Use `VNHomographicImageRegistrationRequest` instead. Extract rotation + scale from homography matrix. | Effects developer |
| R7 | Memory pressure from CIContext + intermediate textures triggers iOS memory warnings | Medium | **Medium** -- App could be killed by OS during complex effect chains | 1b+ | Lazy CIContext creation. Aggressive intermediate texture disposal. Integrate with existing `MemoryPressureLevel` system. Reduce frame cache size when effects are active. | Effects developer |
| R8 | Platform channel JSON serialization overhead during rapid parameter scrubbing | Low | **Low** -- Slight lag during slider adjustment | 1b | 50ms debounce on parameter changes. Cache deserialized chain on compositor. Only send delta updates for single-parameter changes. | Effects developer |
| R9 | Freeze frame requires ImageClip support in CompositionBuilder (currently throws) | Confirmed | **Medium** -- Blocks freeze frame playback | 2 | Add image segment rendering in custom compositor (return static CIImage for image segments). R2-IF1 provides the path. | Effects developer |
| R10 | HDR export incompatible with custom compositor using BGRA pixel format | Confirmed | **Low** -- HDR is not commonly used | 1a | Document SDR-only limitation for effects. HDR passthrough deferred to Phase 5. Set TODO comments. | Effects developer |

---

### Implementation Checklist

Ordered file list for Phase 1 implementation. Files are listed in dependency order (implement top to bottom).

**Phase 1a -- Custom Compositor + Transform Parity:**

| # | File | Type | Purpose | Depends On |
|---|------|------|---------|------------|
| 1 | `ios/Runner/Effects/EffectCompositionInstruction.swift` | New | Custom `AVVideoCompositionInstructionProtocol` carrying transform data + effect chain JSON per segment | None |
| 2 | `ios/Runner/Effects/EffectVideoCompositor.swift` | New | `AVVideoCompositing` implementation with CIContext, CIFilter chain builder, transform rendering | #1 |
| 3 | `ios/Runner/Effects/EffectFilterChain.swift` | New | Stateless function: `buildFilterChain(from:inputImage:frameTime:frameSize:) -> CIImage`. Initially handles transforms only. | None |
| 4 | `ios/Runner/VideoTransformCalculator.swift` | Modify | Add method `createCITransform(sx:sy:tx:ty:rotation:sourceExtent:outputSize:) -> CIAffineTransform parameters` alongside existing `createTransform` (CGAffineTransform). | None |
| 5 | `ios/Runner/CompositionBuilder.swift` | Modify | Add `customVideoCompositorClass = EffectVideoCompositor.self` to `buildVideoComposition()`. Replace `AVMutableVideoCompositionInstruction` with `EffectCompositionInstruction`. Pass transform + effect data per segment. | #1, #2 |
| 6 | `ios/Runner/CompositionPlayerService.swift` | Modify | Set `customVideoCompositorClass` on video composition for preview playback. | #2 |
| 7 | `ios/Runner/VideoProcessingService.swift` | Modify | Update `renderVideo` and `renderComposition` to use custom compositor for export (set `customVideoCompositorClass` on `videoComposition`). | #2 |
| 8 | N/A | Test | Transform parity verification: render frames with old pipeline vs new pipeline, compare pixel-by-pixel. Must pass for scale, translation, rotation, and ramp interpolation. | #2-#7 |

**Phase 1b -- Effect Chain Infrastructure + Mirror/Flip + Crop:**

| # | File | Type | Purpose | Depends On |
|---|------|------|---------|------------|
| 9 | `lib/models/effects/effect_parameter.dart` | New | `EffectParameterType` enum, `EffectParameter` immutable class with `toJson`/`fromJson`/`copyWith` | None |
| 10 | `lib/models/effects/effect_types.dart` | New | `EffectType` enum (CIFilter-based effects ONLY -- no `reverse`, `freezeFrame`, `speedRamp`). Effect registry with default parameters, CIFilter names, metadata. | #9 |
| 11 | `lib/models/effects/effect_keyframe.dart` | New | `EffectKeyframe` class. Per-parameter keyframe tracks. Reuses `InterpolationType` and `BezierControlPoints`. | `lib/models/keyframe.dart` |
| 12 | `lib/models/effects/video_effect.dart` | New | `VideoEffect` (EffectNode) class with `Map<String, EffectParameter>`, per-parameter keyframe tracks (`Map<String, List<EffectKeyframe>>`), `isEnabled`, `mix`. | #9, #10, #11 |
| 13 | `lib/models/effects/effect_chain.dart` | New | `EffectChain` class with ordered list of `VideoEffect`, chain operations (add, remove, reorder, toggle, update). | #12 |
| 14 | `lib/models/effects/crop_rect.dart` | New | `CropRect` class, `CropAspectRatio` enum, `CropFillMode` enum. Add validation (`assert(left < right && top < bottom)`). | None |
| 15 | `lib/models/effects/mask_shape.dart` | New | `MaskShapeType` enum, `MaskShape` class. Placeholder for Phase 2+. | None |
| 16 | `lib/models/effects/effects.dart` | New | Barrel export file for all effect models. | #9-#15 |
| 17 | `lib/models/clips/video_clip.dart` | Modify | Add `final EffectChain effectChain` field with default `const EffectChain()`. Update `copyWith`, `toJson`, `fromJson`, `splitAt` (duplicate effect chain to both halves), `trimStart`/`trimEnd` (keep chain), `duplicate` (copy chain). | #13 |
| 18 | `lib/core/effect_chain_bridge.dart` | New | `EffectChainBridge`: Maps V1 clip IDs to `EffectChain` instances. CRUD operations. Project serialization. Cleanup on clip deletion. | #13 |
| 19 | `lib/core/effect_manager.dart` | New | `EffectManager`: Higher-level operations (add effect to clip, remove, reorder). Delegates to bridge for V1 or directly to TimelineManager for V2. Fires undo snapshots. | #13, #18 |
| 20 | `ios/Runner/Effects/EffectMethodChannel.swift` | New | Platform channel handler for `com.liquideditor/effects`. Methods: `applyEffectChain`, `previewFrame`. | #3 |
| 21 | `ios/Runner/Effects/MirrorFlipEffect.swift` | New | `CIAffineTransform` with negative scale for horizontal/vertical flip. | #3 |
| 22 | `ios/Runner/Effects/CropEffect.swift` | New | `CICrop` + `CIAffineTransform` to fill output. Handles normalized-to-pixel coordinate conversion. | #3 |
| 23 | `ios/Runner/Effects/EffectFilterChain.swift` | Modify | Extend to dispatch to `MirrorFlipEffect` and `CropEffect` based on effect type. Add mix blending. | #3, #21, #22 |
| 24 | `ios/Runner/AppDelegate.swift` | Modify | Register `com.liquideditor/effects` method channel. Wire to `EffectMethodChannel`. | #20 |
| 25 | `lib/views/smart_edit/effect_chain_panel.dart` | New | Effect chain list UI using `CupertinoListSection` and `CupertinoListTile`. Reorder via long-press drag. Enable/disable toggle with `CupertinoSwitch`. | #13 |
| 26 | `lib/views/smart_edit/effect_parameter_editor.dart` | New | Parameter editing UI: `CupertinoSlider` for numeric, `CupertinoSwitch` for bool, `CupertinoSegmentedControl` for enum. | #9 |
| 27 | `lib/views/smart_edit/crop_overlay.dart` | New | Crop rectangle overlay on video preview. Draggable corners/edges. Aspect ratio lock. Rule-of-thirds grid. | #14 |
| 28 | `lib/views/smart_edit/effect_browser.dart` | New | Effect browser modal. Categories, grid tiles, search. `CupertinoSearchTextField`, `CupertinoScrollbar`. Liquid Glass styled grid items. | #10 |
| 29 | `test/models/effects/video_effect_test.dart` | New | Unit tests: serialization, `copyWith`, equality. | #12 |
| 30 | `test/models/effects/effect_chain_test.dart` | New | Unit tests: add, remove, reorder, toggle, update. | #13 |
| 31 | `test/models/effects/crop_rect_test.dart` | New | Unit tests: validation, aspect ratio, identity check. | #14 |
| 32 | `test/models/effects/effect_parameter_test.dart` | New | Unit tests: type validation, serialization round-trip. | #9 |

**Total Phase 1 files: 24 new, 8 modified.**

---

### What Can Be Built Without the Bridge?

Identifying self-contained features that do not require the V1/V2 bridge is critical for de-risking parallel development.

**Fully self-contained (no bridge needed):**

| Feature | Why Self-Contained | Phase |
|---------|--------------------|-------|
| All Dart data models (#9-#16) | Pure value objects with no system dependencies | 1b |
| Unit tests for data models (#29-#32) | Test models in isolation | 1b |
| `EffectVideoCompositor` + `EffectCompositionInstruction` (#1-#2) | Pure native Swift, no Dart dependency | 1a |
| `EffectFilterChain` builder (#3, #23) | Pure Swift function, input CIImage -> output CIImage | 1a |
| `MirrorFlipEffect` + `CropEffect` (#21-#22) | Pure CIFilter wrappers | 1b |
| Transform parity port in `VideoTransformCalculator` (#4) | Extension of existing Swift class | 1a |
| Metal kernel development (Phase 3 shaders) | Standalone `.metal` files, compiled by Xcode | 3 |
| `SpeedRamp` model + curve evaluation + duration calculation | Pure Dart math, no system integration | 3 data model |
| `CropRect`, `MaskShape`, `ChromaKeyConfig` models | Pure Dart value objects | 1b-4 |

**Requires bridge:**

| Feature | Why Bridge Needed | Phase |
|---------|-------------------|-------|
| Effect chain panel in clip inspector (#25) | Must read/write effect chain for currently selected V1 clip | 1b |
| Effect browser apply flow (#28) | Must add effect to V1 clip's chain via bridge | 1b |
| Effect parameter editing with live preview (#26) | Must send updated chain to native via bridge + channel | 1b |
| Crop overlay with live preview (#27) | Must send crop parameters to native compositor | 1b |
| `CompositionBuilder` integration (#5) | Must inject effect chain data from bridge into composition segments | 1a/1b |

**Development strategy:** Build all self-contained items FIRST (weeks 1-2), then build the bridge (week 3), then integrate (weeks 4-5). This front-loads the lowest-risk work and allows the bridge design to benefit from insights gained during compositor development.

---

### Additional Issues Identified in This Review

#### R3-1: `EffectChain` Serialization Version Missing (R1-I7 Still Unresolved)

R1-I7 flagged the absence of a serialization version. R2 did not address it. This remains open.

**Required action for Phase 1:** Add `static const int schemaVersion = 1` to `EffectChain`. Include in `toJson()`. In `fromJson()`, read version and apply migration logic. For unknown `EffectType` values, create a disabled `VideoEffect` with `type: EffectType.unknown` (add sentinel value to enum) rather than throwing.

#### R3-2: `VideoClip.splitAt()` Must Be Updated for Effect Chain

The current `VideoClip.splitAt()` (lines 61-110 of `video_clip.dart`) partitions keyframes between left and right halves. When `effectChain` is added to `VideoClip`, `splitAt()` must also handle effect chains. The correct behavior is:

- **Effect chain is duplicated to BOTH halves** (both clips retain all effects)
- **Effect keyframes are partitioned** (like transform keyframes): keyframes before split go to left, keyframes after split go to right with timestamps adjusted
- If using per-parameter keyframe tracks, each track must be partitioned independently

This is a non-trivial change that must be included in Phase 1b work item #17.

#### R3-3: The Design Specifies `EffectParameter.copyWith` Only Copies `currentValue`

Looking at the design's `EffectParameter.copyWith` (lines 245-259), it only accepts `dynamic currentValue` as an optional parameter. A full `copyWith` should accept all fields to support operations like changing `isKeyframeable` or `step` at runtime (e.g., for adaptive parameter ranges based on clip resolution).

**Recommendation:** Expand `copyWith` to accept all mutable-semantically fields. Mark truly immutable metadata fields (like `name`, `type`) as non-overridable by convention.

#### R3-4: Effect Ordering Warnings (Section 19) Need Implementation Specification

The design mentions the UI should warn about suboptimal orderings (blur after sharpen, stacking crops). But there is no specification for HOW these warnings are generated. This needs a simple rule engine:

```dart
List<String> validateEffectChain(EffectChain chain) {
  // Check for blur-after-sharpen, stacked crops, etc.
  // Return list of warning messages
}
```

This should be implemented in Phase 1b as part of the `EffectManager` (#19).

#### R3-5: R2-IF4 Recommendation (Remove `reverse`, `freezeFrame`, `speedRamp` from EffectType) Requires Design Document Update

R2 recommended removing these three types from the `EffectType` enum since they are not CIFilter-based per-frame effects. This is correct. However, the design document's Sections 5, 6, and 7 (Reverse, Freeze Frame, Speed Ramp) still describe these as "effects" and their implementation should be re-categorized.

**Recommendation:** These features remain in scope but are re-classified:
- **Reverse:** Clip property (`VideoClip.isReversed: bool`). Implementation in Phase 2.
- **Freeze Frame:** Timeline editing operation. Implementation in Phase 2.
- **Speed Ramp:** Time remapping model (`VideoClip.speedRamp: SpeedRamp?`). Implementation in Phase 3.

The effect browser should present these in a separate "Time & Speed" section of the clip inspector, NOT in the CIFilter-based effects chain.

---

### Final Assessment: CONDITIONAL GO

**Decision: CONDITIONAL GO for Phase 1 implementation.**

The design is comprehensive, the architecture is sound, and all critical issues have viable resolution paths. The `AVVideoCompositing` custom compositor approach is the correct architectural choice. The V1/V2 bridge is a pragmatic solution to the dual-model problem. The CIFilter pipeline, while greenfield, uses well-documented Apple APIs with no exotic requirements.

**Conditions for GO:**

1. **Phase 1 scope must be split into 1a (compositor + transform parity) and 1b (effects infrastructure + mirror/flip + crop).** The transform migration in 1a is the critical path and must be completed and verified before 1b begins. Do not interleave them.

2. **Phase 1a must include a pixel-comparison test suite** for transform rendering. The custom compositor's transform output must be visually identical to the current `setTransformRamp` output. Any visible difference is a regression. This test suite must run on device (not simulator, as GPU behavior differs).

3. **The `EffectChainBridge` must be implemented early in Phase 1b** (work item #18). Do not defer it to the end. The bridge enables end-to-end testing from the production editor.

4. **Serialization version** (R3-1) must be included in the initial `EffectChain` model. Do not ship V1 without versioning -- it creates a migration nightmare later.

5. **Remove `reverse`, `freezeFrame`, `speedRamp` from `EffectType` enum** before implementation begins. These are not CIFilter effects and their presence in the enum creates architectural confusion.

6. **Dynamic quality scaling must be implemented in Phase 1a** (compositor-level). If `CIContext.render()` exceeds 12ms, reduce render resolution to 720p for the next frame. This prevents the "laggy preview" experience on A14 devices from day one.

**If these conditions are met, implementation may proceed immediately.**

---

### Remaining Open Questions

| # | Question | Recommended Answer | Decision Needed By |
|---|----------|-------------------|-------------------|
| OQ1 | Should the V1-to-V2 editor migration be prioritized over effects? | No. The bridge layer is cheaper (1 week) than full migration (4-8 weeks). Build effects with the bridge. Migrate later. | Before Phase 1 starts |
| OQ2 | How should effect keyframe editing interact with the V1 `ClipManager` keyframe system? | Effect keyframes are independent of transform keyframes. They live on `EffectChain`, not on the clip's `List<Keyframe>`. No interaction with `ClipManager.keyframes`. | Phase 1b |
| OQ3 | Should the effect browser be a full modal sheet or a sidebar panel? | Modal sheet (as designed). Matches iOS 26 HIG for selection UIs. Use `CupertinoSheetRoute` or `showCupertinoModalPopup`. | Phase 1b |
| OQ4 | What is the minimum iOS version for the effects system? | iOS 15.0. This enables `CIFilter.CIFilterBuiltins` type-safe API, person segmentation (`VNGeneratePersonSegmentationRequest`), and Metal Performance Shaders optimizations. Devices below iOS 15 (<1% of active iPhones) will see effects disabled with a notification. | Before Phase 1 starts |
| OQ5 | Should R1-Q2 (effect handling during clip split) duplicate the chain or partition it? | Duplicate the chain to both halves. Effect keyframes should be partitioned (keyframes before split point go to left, after to right with adjusted timestamps). This matches transform keyframe behavior. | Phase 1b (work item #17) |
| OQ6 | Should the custom compositor support HDR in Phase 1? | No. SDR only (`kCVPixelFormatType_32BGRA`). HDR support deferred to Phase 5. Document this limitation in code comments. | Before Phase 1 starts |
| OQ7 | R1-Q1: Does the effects system cover audio effects? | No. Audio effects (reverb, EQ, pitch) are a separate system with different native APIs (AVAudioEngine, Audio Units). Out of scope for this design. | Decided -- out of scope |

---

### Estimated Total Timeline

| Phase | Scope | Duration | Cumulative |
|-------|-------|----------|------------|
| **1a** | Custom compositor + transform parity | 2-3 weeks | 2-3 weeks |
| **1b** | Effects infrastructure + mirror/flip + crop + bridge | 2 weeks | 4-5 weeks |
| **2** | Blur effects + reverse (clip property) + freeze frame | 2-3 weeks | 6-8 weeks |
| **3** | Speed ramp + visual effects (glitch, VHS, grain, flare, leaks) + sharpen/denoise | 3-4 weeks | 9-12 weeks |
| **4** | Chroma key + masks + stabilization + effect browser + keyframe editing | 3-4 weeks | 12-16 weeks |
| **Total** | | **12-16 weeks** | |

This is a 3-4 month project for a single developer. Parallel development (one dev on native, one on Dart) could compress this to 8-10 weeks.

---

**End of Review 3 - Final Sign-off**
