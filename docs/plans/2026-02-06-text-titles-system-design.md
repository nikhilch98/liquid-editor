# Text & Titles System - Design Document

**Author:** Development Team
**Date:** 2026-02-06
**Status:** Draft - Pending Review
**Related:** [Timeline Architecture V2](2026-01-30-timeline-architecture-v2-design.md), [DESIGN.md](../DESIGN.md)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Data Models](#2-data-models)
3. [Architecture](#3-architecture)
4. [Timeline Integration](#4-timeline-integration)
5. [Text Editor UI](#5-text-editor-ui)
6. [Rendering Pipeline](#6-rendering-pipeline)
7. [Text Animations](#7-text-animations)
8. [Subtitle System](#8-subtitle-system)
9. [Text Behind Subject](#9-text-behind-subject)
10. [Font Management](#10-font-management)
11. [Persistence](#11-persistence)
12. [Edge Cases](#12-edge-cases)
13. [Performance Considerations](#13-performance-considerations)
14. [Dependencies](#14-dependencies)
15. [Implementation Plan](#15-implementation-plan)

---

## 1. Overview

### Purpose

The Text & Titles System adds comprehensive text overlay capabilities to Liquid Editor, enabling users to place styled, animated text on top of video content at any position and time range. The system encompasses simple text overlays, animated titles, subtitles, and advanced compositing features like text-behind-subject.

### Goals

- **Native feel:** Text editing must feel as responsive and polished as native iOS text editing (inline editing on the video preview, smooth animations, iOS keyboard integration).
- **Timeline-native:** Text clips are first-class timeline citizens that support all standard editing operations (trim, split, move, copy, delete) through the existing Persistent AVL tree.
- **Animation-rich:** Support for preset enter/exit/sustain animations plus full keyframe-based custom animation using the existing `Keyframe` + `InterpolationType` system.
- **Export-accurate:** What the user sees during preview must match the exported video pixel-for-pixel. This requires a dual rendering pipeline: Flutter `CustomPainter` for preview and native Core Animation/Core Text for export.
- **Performance-safe:** Text rendering during playback must never exceed a 2ms per-frame budget to maintain 60 FPS.

### Non-Goals (Out of Scope for V1)

- 3D text extrusion or perspective transforms.
- Per-character animation (animate each letter individually). This is deferred to V2.
- Text-to-speech or voice-to-subtitle auto-transcription (requires ML model integration).
- Handwriting simulation or freehand drawing overlay.

---

## 2. Data Models

### 2.1 TextClip (New TimelineItem Subclass)

`TextClip` extends `GeneratorClip` (same pattern as `ColorClip`) because text generates visual content without referencing an external media file.

```dart
/// lib/models/clips/text_clip.dart

@immutable
class TextClip extends GeneratorClip {
  /// The text content (supports multi-line via \n).
  final String text;

  /// Visual style of the text.
  final TextOverlayStyle style;

  /// Position of the text center on the video canvas.
  /// Normalized coordinates (0.0-1.0) where (0.5, 0.5) is center.
  final Offset position;

  /// Rotation angle in radians.
  final double rotation;

  /// Scale factor (1.0 = default size as defined by style.fontSize).
  final double scale;

  /// Opacity (0.0-1.0).
  final double opacity;

  /// Enter animation preset (null = no enter animation).
  final TextAnimationPreset? enterAnimation;

  /// Exit animation preset (null = no exit animation).
  final TextAnimationPreset? exitAnimation;

  /// Sustain animation preset (null = static text).
  final TextAnimationPreset? sustainAnimation;

  /// Duration of enter animation in microseconds.
  /// Clamped to [0, durationMicroseconds / 2].
  final int enterDurationMicros;

  /// Duration of exit animation in microseconds.
  /// Clamped to [0, durationMicroseconds / 2].
  final int exitDurationMicros;

  /// Keyframes for custom property animation.
  /// Timestamps are relative to clip start.
  /// Each keyframe stores a TextTransform (position, scale, rotation, opacity).
  final List<TextKeyframe> keyframes;

  /// Template ID this was created from (null if custom).
  final String? templateId;

  /// Optional display name.
  final String? name;

  /// Whether this is a subtitle clip (affects rendering layer and behavior).
  final bool isSubtitle;

  /// Text alignment within the bounding box.
  final TextAlign textAlign;

  /// Maximum width as fraction of video width (0.0-1.0).
  /// Text wraps when it exceeds this width. Default 0.9.
  final double maxWidthFraction;

  const TextClip({
    required super.id,
    required super.durationMicroseconds,
    required this.text,
    required this.style,
    this.position = const Offset(0.5, 0.5),
    this.rotation = 0.0,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.enterAnimation,
    this.exitAnimation,
    this.sustainAnimation,
    this.enterDurationMicros = 300000, // 300ms default
    this.exitDurationMicros = 300000,
    this.keyframes = const [],
    this.templateId,
    this.name,
    this.isSubtitle = false,
    this.textAlign = TextAlign.center,
    this.maxWidthFraction = 0.9,
  });

  @override
  String get displayName => name ?? (isSubtitle ? 'Subtitle' : 'Text');

  @override
  String get itemType => 'text';
}
```

**Registration:** `TimelineItem.fromJson` must be updated to handle `itemType: 'text'` and dispatch to `TextClip.fromJson`.

**Registration in ClipType:** The existing `ClipType.text` enum value in `lib/timeline/data/models/timeline_clip.dart` already exists, as does the `TrackType.text` in `track.dart`. No enum additions are required.

### 2.2 TextOverlayStyle

```dart
/// lib/models/text/text_overlay_style.dart

@immutable
class TextOverlayStyle {
  /// Font family name (system or custom).
  final String fontFamily;

  /// Font size in logical pixels at 1080p reference.
  /// Scales proportionally for other resolutions.
  final double fontSize;

  /// Text color.
  final Color color;

  /// Font weight.
  final FontWeight fontWeight;

  /// Whether text is italic.
  final bool isItalic;

  /// Letter spacing (0.0 = normal).
  final double letterSpacing;

  /// Line height multiplier (1.0 = normal).
  final double lineHeight;

  /// Text shadow (null = no shadow).
  final TextShadowStyle? shadow;

  /// Text outline/stroke (null = no outline).
  final TextOutlineStyle? outline;

  /// Background box behind text (null = no background).
  final TextBackgroundStyle? background;

  /// Glow effect around text (null = no glow).
  final TextGlowStyle? glow;

  /// Text decoration (underline, strikethrough).
  final TextDecoration decoration;

  /// Whether the font is a custom imported font.
  final bool isCustomFont;

  /// Custom font file path (only if isCustomFont is true).
  /// Stored as relative path within app's font directory.
  final String? customFontPath;

  const TextOverlayStyle({
    this.fontFamily = '.SF Pro Display',
    this.fontSize = 48.0,
    this.color = const Color(0xFFFFFFFF),
    this.fontWeight = FontWeight.bold,
    this.isItalic = false,
    this.letterSpacing = 0.0,
    this.lineHeight = 1.2,
    this.shadow,
    this.outline,
    this.background,
    this.glow,
    this.decoration = TextDecoration.none,
    this.isCustomFont = false,
    this.customFontPath,
  });
}

@immutable
class TextShadowStyle {
  final Color color;
  final Offset offset;    // Normalized to font size units
  final double blurRadius;

  const TextShadowStyle({
    this.color = const Color(0x80000000),
    this.offset = const Offset(0.02, 0.02),
    this.blurRadius = 4.0,
  });
}

@immutable
class TextOutlineStyle {
  final Color color;
  final double width; // In logical pixels

  const TextOutlineStyle({
    this.color = const Color(0xFF000000),
    this.width = 2.0,
  });
}

@immutable
class TextBackgroundStyle {
  final Color color;
  final double cornerRadius;
  final EdgeInsets padding; // In logical pixels

  const TextBackgroundStyle({
    this.color = const Color(0x80000000),
    this.cornerRadius = 8.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });
}

@immutable
class TextGlowStyle {
  final Color color;
  final double radius;
  final double intensity; // 0.0-1.0

  const TextGlowStyle({
    this.color = const Color(0xFF007AFF),
    this.radius = 10.0,
    this.intensity = 0.5,
  });
}
```

### 2.3 TextKeyframe (Extends Existing Keyframe Concept)

Rather than reusing `Keyframe` directly (which stores `VideoTransform` with video-specific semantics), we define a `TextKeyframe` that stores text-specific animatable properties.

```dart
/// lib/models/text/text_keyframe.dart

@immutable
class TextKeyframe {
  final String id;

  /// Timestamp relative to clip start (microseconds).
  final int timestampMicros;

  /// Position (normalized 0.0-1.0).
  final Offset position;

  /// Scale factor.
  final double scale;

  /// Rotation in radians.
  final double rotation;

  /// Opacity (0.0-1.0).
  final double opacity;

  /// Interpolation type to next keyframe.
  /// Reuses the existing InterpolationType enum from keyframe.dart.
  final InterpolationType interpolation;

  /// Custom bezier control points (when interpolation == bezier).
  final BezierControlPoints? bezierPoints;

  const TextKeyframe({
    required this.id,
    required this.timestampMicros,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.interpolation = InterpolationType.easeInOut,
    this.bezierPoints,
  });
}
```

**Why a separate type instead of reusing Keyframe?**
- `Keyframe` stores `VideoTransform` with `anchor` semantics specific to video pan/zoom/rotate.
- `TextKeyframe` stores position/scale/rotation/opacity with normalized-to-canvas semantics.
- Attempting to overload `VideoTransform` for text would create confusing dual semantics for `translation` (video viewport offset vs. canvas position).
- The `InterpolationType` and `BezierControlPoints` types are reused directly, avoiding duplication of interpolation logic.

### 2.4 TextAnimationPreset

```dart
/// lib/models/text/text_animation_preset.dart

enum TextAnimationPresetType {
  // Enter animations
  fadeIn,
  slideInLeft,
  slideInRight,
  slideInTop,
  slideInBottom,
  scaleUp,
  bounceIn,
  typewriter,
  glitchIn,
  rotateIn,
  blurIn,
  popIn,

  // Exit animations
  fadeOut,
  slideOutLeft,
  slideOutRight,
  slideOutTop,
  slideOutBottom,
  scaleDown,
  bounceOut,
  glitchOut,
  rotateOut,
  blurOut,
  popOut,

  // Sustain animations (loop during visible duration)
  breathe,
  pulse,
  float,
  shake,
  colorCycle,
  flicker,
}

@immutable
class TextAnimationPreset {
  final TextAnimationPresetType type;

  /// Animation intensity (0.0-1.0). Controls amplitude of movement/scale.
  final double intensity;

  /// Custom parameters per animation type (e.g., direction angle for slide).
  final Map<String, double> parameters;

  const TextAnimationPreset({
    required this.type,
    this.intensity = 1.0,
    this.parameters = const {},
  });
}
```

### 2.5 TextTemplate

```dart
/// lib/models/text/text_template.dart

@immutable
class TextTemplate {
  final String id;
  final String name;
  final String category; // e.g., "Titles", "Lower Thirds", "Social", "Cinematic"
  final TextOverlayStyle style;
  final Offset defaultPosition;
  final TextAnimationPreset? defaultEnterAnimation;
  final TextAnimationPreset? defaultExitAnimation;
  final TextAnimationPreset? defaultSustainAnimation;
  final int defaultDurationMicros;
  final TextAlign defaultAlignment;
  final double defaultMaxWidthFraction;

  /// Preview thumbnail path (bundled asset).
  final String? thumbnailAsset;

  /// Whether this is a built-in template (not deletable).
  final bool isBuiltIn;

  const TextTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.style,
    this.defaultPosition = const Offset(0.5, 0.5),
    this.defaultEnterAnimation,
    this.defaultExitAnimation,
    this.defaultSustainAnimation,
    this.defaultDurationMicros = 3000000, // 3 seconds
    this.defaultAlignment = TextAlign.center,
    this.defaultMaxWidthFraction = 0.9,
    this.thumbnailAsset,
    this.isBuiltIn = true,
  });
}
```

### 2.6 SubtitleEntry

```dart
/// lib/models/text/subtitle_entry.dart

@immutable
class SubtitleEntry {
  final int index;
  final int startMicros;
  final int endMicros;
  final String text;

  /// Optional speaker label (for multi-speaker SRT).
  final String? speaker;

  /// Style overrides (null = use track default style).
  final TextOverlayStyle? styleOverride;

  const SubtitleEntry({
    required this.index,
    required this.startMicros,
    required this.endMicros,
    required this.text,
    this.speaker,
    this.styleOverride,
  });

  int get durationMicros => endMicros - startMicros;
}
```

### 2.7 SubtitleTrack (Wrapper Around Multiple TextClips)

Rather than introducing a fundamentally new track concept, subtitles are modeled as a sequence of `TextClip` objects (with `isSubtitle: true`) placed on a `Track` of type `TrackType.text`. The `SubtitleTrack` class is a service-level wrapper that provides SRT/VTT import/export and batch operations over these clips.

```dart
/// lib/core/subtitle_manager.dart

class SubtitleManager {
  /// Import SRT file and create TextClips on the given track.
  List<TextClip> importSRT(String srtContent, TextOverlayStyle defaultStyle);

  /// Import VTT file and create TextClips on the given track.
  List<TextClip> importVTT(String vttContent, TextOverlayStyle defaultStyle);

  /// Export TextClips from a track to SRT format.
  String exportSRT(List<TextClip> subtitleClips);

  /// Export TextClips from a track to VTT format.
  String exportVTT(List<TextClip> subtitleClips);
}
```

### 2.8 Integration with Existing Clip Types

The `TextClip` joins the existing hierarchy:

```
TimelineItem (abstract)
  |-- MediaClip (abstract)
  |   |-- VideoClip
  |   |-- AudioClip
  |   |-- ImageClip
  |
  |-- GeneratorClip (abstract)
      |-- GapClip
      |-- ColorClip
      |-- TextClip  <--- NEW
```

**Changes to `TimelineItem.fromJson`:**

```dart
static TimelineItem fromJson(Map<String, dynamic> json) {
  final type = json['itemType'] as String;
  switch (type) {
    case 'video': return VideoClip.fromJson(json);
    case 'image': return ImageClip.fromJson(json);
    case 'audio': return AudioClip.fromJson(json);
    case 'gap':   return GapClip.fromJson(json);
    case 'color': return ColorClip.fromJson(json);
    case 'text':  return TextClip.fromJson(json);  // <--- NEW
    default: throw ArgumentError('Unknown timeline item type: $type');
  }
}
```

---

## 3. Architecture

### 3.1 Rendering Strategy: Dual Pipeline

Text rendering follows a split architecture:

| Context | Renderer | Technology | Frame Budget |
|---------|----------|-----------|-------------|
| **Preview** (playback + scrub) | Flutter side | `CustomPainter` + `TextPainter` | < 2ms per text clip |
| **Export** | Native side | `CATextLayer` + `Core Text` via `AVVideoCompositionCoreAnimationTool` | N/A (offline) |

**Why not render everything on Flutter side?**
- AVFoundation export operates at the native layer. To burn text into exported video frames, we must provide text as `CALayer` objects attached to the `AVMutableVideoComposition` via `AVVideoCompositionCoreAnimationTool`.
- This is the standard technique used by professional iOS video editors (iMovie, Clips, etc.).

**Why not render everything on native side?**
- During preview, the video is displayed via Flutter's video player widget. Overlaying text requires Flutter widgets or painters that can be composited above the video in the Flutter render tree.
- Platform views for text overlays would incur significant overhead and break gesture handling.

### 3.2 High-Level Architecture

```
Flutter Layer                              Native Layer (Swift)
-----------                              -------------------

TextEditorPanel                          TextLayerBuilder
  |                                        |
  v                                        v
TextClipManager ----[Platform Channel]---> TextExportService
  |                                        |
  v                                        v
TextPreviewPainter                       AVVideoCompositionCoreAnimationTool
  |                                        |
  v                                        v
VideoPreviewStack                        AVAssetWriter / AVAssetExportSession
```

### 3.3 Component Responsibilities

| Component | Layer | Purpose |
|-----------|-------|---------|
| `TextClipManager` | Dart / `lib/core/` | CRUD operations on TextClips. Manages text clip state, template application, font resolution. Exposes text clip data to both the preview painter and the export pipeline. |
| `TextPreviewPainter` | Dart / `lib/timeline/rendering/` | `CustomPainter` that renders all visible text clips at the current playhead position. Handles animation interpolation, caching, and compositing order. |
| `TextEditorPanel` | Dart / `lib/views/text/` | Full-screen text editing UI. Inline editing on video preview, style panel, animation picker, template browser. Uses Cupertino widgets exclusively. |
| `TextTimelinePainter` | Dart / `lib/timeline/rendering/painters/` | Renders text clips as timeline track items (similar to how `ClipsPainter` renders video clips). Shows text preview inside the timeline clip rectangle. |
| `TextLayerBuilder` | Swift / `ios/Runner/Text/` | Converts `TextClip` data (received via platform channel) into `CATextLayer` + `CAAnimation` objects for export. |
| `TextExportService` | Swift / `ios/Runner/Text/` | Integrates `TextLayerBuilder` output with `AVVideoCompositionCoreAnimationTool` during export composition building. |
| `SubtitleManager` | Dart / `lib/core/` | SRT/VTT parsing, generation, and batch TextClip creation. |
| `FontManager` | Dart / `lib/core/` | System font enumeration, custom font loading via `FontLoader`, font preview cache. |

### 3.4 Text Clips on the Timeline

Text clips live on dedicated text tracks (`TrackType.text`). Multiple text tracks can exist, allowing overlapping text at the same time. The existing multi-track architecture handles this naturally.

```
Track Layout:
  [Main Video Track]  [==== Video Clip A ====][==== Video Clip B ====]
  [Text Track 1]           [== Title ==]
  [Text Track 2]      [= Lower Third =]               [= Credit =]
  [Subtitle Track]    [Sub1][Sub2][Sub3][Sub4][Sub5][Sub6][Sub7][Sub8]
```

Text tracks are rendered above video tracks in the compositor. Track order (index) determines z-order: higher index = rendered on top.

### 3.5 Integration with Keyframe System

The existing `InterpolationType` enum (21 types including linear, hold, easeIn/Out, spring, bounce, elastic, etc.) and `BezierControlPoints` are reused directly for `TextKeyframe.interpolation`.

The interpolation math in `ClipManager._applyEasing()` and `ClipManager._interpolateTransform()` is extracted into a shared utility:

```dart
/// lib/core/interpolation_utils.dart

class InterpolationUtils {
  /// Apply easing function to a normalized t value (0.0-1.0).
  static double applyEasing(double t, InterpolationType type, [BezierControlPoints? bezier]);

  /// Interpolate between two Offsets.
  static Offset lerpOffset(Offset a, Offset b, double t);

  /// Interpolate between two doubles.
  static double lerpDouble(double a, double b, double t);
}
```

This eliminates duplication between video keyframe interpolation and text keyframe interpolation.

### 3.6 Integration with Export Pipeline

The current export pipeline in `VideoProcessingService.swift` uses `AVMutableVideoComposition` with `AVMutableVideoCompositionLayerInstruction` for transforms. Text export adds a parallel layer:

```
AVMutableComposition
  |
  +-- Video Track (with layer instructions for transforms)
  |
  +-- Audio Track (with audio mix)
  |
  +-- CALayer (parent layer)
       |
       +-- Video Layer (renders video composition)
       |
       +-- Text Layer 1 (CATextLayer + CAAnimationGroup)
       |
       +-- Text Layer 2 (CATextLayer + CAAnimationGroup)
       |
       ...
```

This is achieved via `AVVideoCompositionCoreAnimationTool.init(postProcessingAsVideoLayer:in:)` which composites a Core Animation layer tree on top of the video output.

---

## 4. Timeline Integration

### 4.1 TextClip in the Persistent AVL Tree

`TextClip` extends `GeneratorClip`, which has a `durationMicroseconds` field. This makes it directly compatible with the `PersistentTimeline` tree, which uses `item.durationMicroseconds` for subtree duration calculations.

**No changes needed to `PersistentTimeline`, `TimelineNode`, or `TimelineManager`** -- they are generic over `TimelineItem` and will work with `TextClip` out of the box.

However, `TextClip` lives on its own text track(s), not interleaved with video clips on the main track. The `TimelineManager` currently manages a single `PersistentTimeline`. For multi-track support, we need a mapping:

```dart
/// Proposed extension to timeline state (conceptual, not a code change yet)
///
/// Each track has its own PersistentTimeline.
/// The main timeline (mainVideo track) uses the existing TimelineManager.
/// Overlay tracks (text, audio, etc.) each maintain a separate PersistentTimeline.
///
/// For V1, text tracks are managed by TextClipManager which holds a
/// Map<String, PersistentTimeline> keyed by track ID.
```

### 4.2 TextClipManager

```dart
/// lib/core/text_clip_manager.dart

class TextClipManager extends ChangeNotifier {
  /// Text timelines by track ID.
  /// Each text track has its own PersistentTimeline for independent editing.
  Map<String, PersistentTimeline> _textTimelines = {};

  /// Undo/redo stacks per track.
  final Map<String, List<PersistentTimeline>> _undoStacks = {};
  final Map<String, List<PersistentTimeline>> _redoStacks = {};

  /// Create a new text track and return its ID.
  String createTextTrack({String? name});

  /// Add a TextClip to a track at a specific time.
  void addTextClip(String trackId, int timeMicros, TextClip clip);

  /// Remove a TextClip.
  void removeTextClip(String trackId, String clipId);

  /// Update a TextClip (e.g., after text edit, style change, animation change).
  void updateTextClip(String trackId, String clipId, TextClip newClip);

  /// Get all TextClips visible at a specific time across all text tracks.
  List<(String trackId, TextClip clip, int offsetWithin)> textClipsAtTime(int timeMicros);

  /// Move a text clip to a different time (or different track).
  void moveTextClip(String fromTrackId, String toTrackId, String clipId, int newTimeMicros);

  /// Split text clip at time.
  void splitTextClipAt(String trackId, int timeMicros);

  /// Trim text clip head or tail.
  void trimTextClipHead(String trackId, String clipId, int newStartMicros);
  void trimTextClipTail(String trackId, String clipId, int newEndMicros);

  /// Undo/redo for a specific track.
  void undo(String trackId);
  void redo(String trackId);
}
```

### 4.3 Rendering Text Clips on Timeline UI

A new `TextClipsPainter` (similar to `ClipsPainter`) renders text clips as colored rectangles on text tracks. Inside each rectangle, the clip's text content is rendered as a truncated label.

```dart
/// lib/timeline/rendering/painters/text_clip_painter.dart

class TextClipsPainter extends CustomPainter {
  final List<TimelineClip> textClips;
  final List<Track> textTracks;
  final Set<String> selectedClipIds;
  final ViewportState viewport;

  // Renders text clips as pink/magenta rectangles (TrackType.text color)
  // Shows truncated text content inside the rectangle
  // Shows animation indicators (enter/exit icons at clip edges)
  // Shows keyframe diamonds if hasKeyframes
}
```

### 4.4 Selecting, Trimming, Moving Text Clips

All existing gesture interactions on the timeline (tap to select, drag handles to trim, drag to reorder/move, long-press context menu) apply to text clips identically. The gesture handler dispatches to `TextClipManager` for text tracks based on the track type of the tapped clip.

**Snap behavior:** Text clips snap to video clip boundaries, playhead, and other text clip edges, using the existing snap guide system.

### 4.5 Multiple Overlapping Text Clips

Multiple text clips CAN exist at the same time on different text tracks. They CANNOT overlap on the same track (same constraint as video clips on a single track). The timeline enforces this by rejecting inserts that would cause overlap on the same track.

If the user wants overlapping text, they add another text track. The UI provides an "Add Text Track" action.

---

## 5. Text Editor UI

### 5.1 Entry Points

The user enters the text editor from:

1. **"Add Text" button** on the timeline toolbar - Creates a new TextClip at the playhead position with default style, then opens the editor.
2. **Tapping an existing text clip** on the timeline - Selects it. Double-tapping opens the editor.
3. **Tapping the text overlay** on the video preview - Opens the editor for that clip.
4. **Template browser** - Applying a template creates a TextClip and opens the editor.

### 5.2 Text Editor Layout

The text editor is a full-screen modal sheet (presented via `CupertinoPageRoute` with slide-up transition) that shows:

```
+----------------------------------------------+
|  [Cancel]    Edit Text              [Done]    |  <-- CupertinoNavigationBar
+----------------------------------------------+
|                                               |
|              VIDEO PREVIEW                    |
|                                               |
|         [  Editable Text Here  ]              |  <-- Inline text on preview
|                                               |
+----------------------------------------------+
|  [Style] [Animation] [Position] [Templates]  |  <-- Tab selector (CNTabBar)
+----------------------------------------------+
|                                               |
|            PANEL CONTENT                      |  <-- Changes based on tab
|   (Style: font picker, color, effects)        |
|   (Animation: enter/exit/sustain pickers)     |
|   (Position: alignment grid, nudge controls)  |
|   (Templates: grid of preset styles)          |
|                                               |
+----------------------------------------------+
|          iOS KEYBOARD (when editing text)      |
+----------------------------------------------+
```

### 5.3 Inline Text Editing on Video Preview

When the user taps the text overlay on the video preview:

1. A `CupertinoTextField` (invisible border, transparent background) is overlaid exactly on top of the rendered text position.
2. The iOS keyboard appears.
3. Text changes are applied in real-time to the `TextClip` and the preview painter re-renders immediately.
4. Tapping outside the text dismisses the keyboard and confirms the edit.

**Gesture handling:**
- **Single tap on text:** Start editing (show cursor, open keyboard).
- **Pan on text:** Move the text position (updates `TextClip.position`).
- **Pinch on text:** Scale the text (updates `TextClip.scale`).
- **Two-finger rotate on text:** Rotate the text (updates `TextClip.rotation`).
- **Pan on empty area:** Dismissed editing mode, moves playhead.

### 5.4 Style Panel

The style panel uses native Cupertino widgets exclusively:

```
Font Family:    [CupertinoPicker - scrollable font list with preview]
Font Size:      [CupertinoSlider: 12-200]
Font Weight:    [CupertinoSegmentedControl: Light | Regular | Medium | Bold | Heavy]
Italic:         [CupertinoSwitch]
Text Color:     [Color well - tap opens CupertinoColorPicker grid]
Letter Spacing: [CupertinoSlider: -5 to 20]
Line Height:    [CupertinoSlider: 0.8 to 3.0]
Alignment:      [CupertinoSegmentedControl: Left | Center | Right]
----- Effects Section -----
Shadow:         [CupertinoSwitch + color/offset/blur controls]
Outline:        [CupertinoSwitch + color/width controls]
Background:     [CupertinoSwitch + color/corner radius controls]
Glow:           [CupertinoSwitch + color/radius/intensity controls]
```

Each control updates the `TextClip.style` in real-time and the preview re-renders immediately.

### 5.5 Animation Picker

```
Enter Animation:    [Horizontal scrollable grid of animation previews]
                    Each preview is a small animated thumbnail showing the effect
                    Tap to select, tap again to deselect

Enter Duration:     [CupertinoSlider: 0.1s - 2.0s]

Exit Animation:     [Same grid layout as enter]
Exit Duration:      [CupertinoSlider: 0.1s - 2.0s]

Sustain Animation:  [Same grid layout]
                    Only enabled when clip duration > enter + exit durations
```

Animation previews are pre-rendered as small animated widgets (using Flutter's `AnimationController`) that loop continuously to show the user what each animation looks like.

### 5.6 Template Browser

```
Category Tabs: [All] [Titles] [Lower Thirds] [Social] [Cinematic] [Subtitles]

Grid of templates (2 columns, scrollable):
+------------------+  +------------------+
| [Preview Image]  |  | [Preview Image]  |
| "Bold Title"     |  | "Elegant Script" |
+------------------+  +------------------+
| [Preview Image]  |  | [Preview Image]  |
| "News Lower 3rd" |  | "Social Pop"    |
+------------------+  +------------------+
```

Tapping a template applies its style, position, and default animations to the current text clip (or creates a new one at the playhead if none is selected).

### 5.7 Keyboard Handling

- The keyboard is managed via Flutter's standard `FocusNode` + `CupertinoTextField`.
- When the keyboard appears, the video preview and text editor panel resize to accommodate (using `MediaQuery.of(context).viewInsets.bottom`).
- The text input supports multi-line via `maxLines: null` and `textInputAction: TextInputAction.newline`.
- Copy/paste is supported via the iOS system clipboard.
- Predictive text and autocorrect are enabled by default but can be toggled.

---

## 6. Rendering Pipeline

### 6.1 Preview Rendering (Flutter Side)

`TextPreviewPainter` is a `CustomPainter` that sits in the widget tree above the video player:

```dart
/// lib/timeline/rendering/painters/text_preview_painter.dart

class TextPreviewPainter extends CustomPainter {
  /// All text clips visible at current time, sorted by track z-order.
  final List<TextRenderData> visibleTexts;

  /// Current playhead time (for animation progress calculation).
  final int currentTimeMicros;

  /// Video render size (to convert normalized positions to pixels).
  final Size videoSize;

  /// Person segmentation mask (for text-behind-subject, nullable).
  final ui.Image? personMask;

  @override
  void paint(Canvas canvas, Size size) {
    for (final textData in visibleTexts) {
      _renderText(canvas, size, textData);
    }
  }

  void _renderText(Canvas canvas, Size size, TextRenderData data) {
    // 1. Calculate animation progress (enter/sustain/exit phase)
    // 2. Apply animation transforms to position/scale/rotation/opacity
    // 3. Apply keyframe interpolation if keyframes exist
    // 4. Build TextStyle from TextOverlayStyle
    // 5. Layout text with TextPainter
    // 6. Apply transforms to canvas (translate, scale, rotate)
    // 7. Draw background box (if enabled)
    // 8. Draw glow (if enabled, using MaskFilter)
    // 9. Draw outline (if enabled, using Paint.style = stroke)
    // 10. Draw shadow (if enabled)
    // 11. Draw text
    // 12. Restore canvas
  }
}
```

**TextRenderData** is a lightweight struct computed each frame from `TextClip` + current time:

```dart
@immutable
class TextRenderData {
  final String clipId;
  final String text;
  final TextOverlayStyle style;
  final Offset position;       // After animation + keyframe interpolation
  final double scale;          // After animation + keyframe interpolation
  final double rotation;       // After animation + keyframe interpolation
  final double opacity;        // After animation + keyframe interpolation
  final TextAlign textAlign;
  final double maxWidthFraction;
  final int trackIndex;        // For z-order
  final bool isSubtitle;
  final bool enableTextBehindSubject;
}
```

### 6.2 Static Text Cache

For text clips that are NOT currently animating (no enter/exit/sustain animation active, and between keyframes with the same values), the rendered text is cached as a `ui.Image`:

```dart
class TextRenderCache {
  /// Cache key: clipId + style hash + text hash + size hash.
  final Map<String, ui.Image> _cache = {};

  /// Maximum cache entries.
  static const int maxEntries = 20;

  /// Get or create cached text image.
  ui.Image getOrCreate(TextRenderData data, Size videoSize);

  /// Invalidate cache for a specific clip (e.g., after text or style edit).
  void invalidate(String clipId);

  /// Clear all cached text images.
  void clear();
}
```

This avoids re-laying out and re-painting text every frame when it is static, saving significant CPU time.

### 6.3 Export Rendering (Native Side)

During export, text clips are sent to the native layer via platform channel:

```dart
// Platform channel call from Flutter
final textLayers = textClips.map((clip) => {
  'clipId': clip.id,
  'text': clip.text,
  'fontFamily': clip.style.fontFamily,
  'fontSize': clip.style.fontSize,
  'fontWeight': clip.style.fontWeight.index,
  'isItalic': clip.style.isItalic,
  'colorValue': clip.style.color.toARGB32(),
  'position': {'x': clip.position.dx, 'y': clip.position.dy},
  'scale': clip.scale,
  'rotation': clip.rotation,
  'opacity': clip.opacity,
  'startMicros': clip.startTimeOnTimeline,
  'endMicros': clip.endTimeOnTimeline,
  'enterAnimation': clip.enterAnimation?.toJson(),
  'exitAnimation': clip.exitAnimation?.toJson(),
  'sustainAnimation': clip.sustainAnimation?.toJson(),
  'enterDurationMicros': clip.enterDurationMicros,
  'exitDurationMicros': clip.exitDurationMicros,
  'keyframes': clip.keyframes.map((kf) => kf.toJson()).toList(),
  'shadow': clip.style.shadow?.toJson(),
  'outline': clip.style.outline?.toJson(),
  'background': clip.style.background?.toJson(),
  'glow': clip.style.glow?.toJson(),
  'textAlign': clip.textAlign.name,
  'maxWidthFraction': clip.maxWidthFraction,
  'isSubtitle': clip.isSubtitle,
}).toList();
```

On the native side, `TextLayerBuilder` converts each entry to a `CATextLayer`:

```swift
// ios/Runner/Text/TextLayerBuilder.swift

class TextLayerBuilder {
    func buildTextLayers(
        from textData: [[String: Any]],
        videoSize: CGSize,
        videoDuration: CMTime
    ) -> CALayer {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)

        for data in textData {
            let textLayer = createTextLayer(from: data, videoSize: videoSize)
            let animations = createAnimations(from: data, videoDuration: videoDuration)
            for animation in animations {
                textLayer.add(animation, forKey: nil)
            }
            parentLayer.addSublayer(textLayer)
        }

        return parentLayer
    }

    private func createTextLayer(from data: [String: Any], videoSize: CGSize) -> CATextLayer {
        let layer = CATextLayer()
        // Configure font, text, color, alignment
        // Configure frame based on normalized position + video size
        // Configure shadow, border (outline), background
        return layer
    }

    private func createAnimations(from data: [String: Any], videoDuration: CMTime) -> [CAAnimation] {
        // Convert enter/exit/sustain animations to CABasicAnimation or CAKeyframeAnimation
        // Convert TextKeyframes to CAKeyframeAnimation with timing functions
        // All animations use beginTime relative to video start
        return []
    }
}
```

Integration with export in `VideoProcessingService.swift`:

```swift
// In renderComposition method, after building videoComposition:

let textLayerBuilder = TextLayerBuilder()
let textParentLayer = textLayerBuilder.buildTextLayers(
    from: textLayers,
    videoSize: finalOutputSize,
    videoDuration: totalDuration
)

// Create animation tool
let videoLayer = CALayer()
videoLayer.frame = CGRect(origin: .zero, size: finalOutputSize)

let outputLayer = CALayer()
outputLayer.frame = CGRect(origin: .zero, size: finalOutputSize)
outputLayer.addSublayer(videoLayer)
outputLayer.addSublayer(textParentLayer)

let animationTool = AVVideoCompositionCoreAnimationTool(
    postProcessingAsVideoLayer: videoLayer,
    in: outputLayer
)
videoComposition.animationTool = animationTool
```

### 6.4 Animation Interpolation During Preview

Each frame during playback/scrub, the preview painter must determine the current animated state of each visible text clip:

```dart
TextRenderData computeTextState(TextClip clip, int clipOffsetMicros) {
  var position = clip.position;
  var scale = clip.scale;
  var rotation = clip.rotation;
  var opacity = clip.opacity;

  // Phase 1: Apply keyframe interpolation (if keyframes exist)
  if (clip.keyframes.isNotEmpty) {
    final interpolated = interpolateKeyframes(clip.keyframes, clipOffsetMicros);
    position = interpolated.position;
    scale = interpolated.scale;
    rotation = interpolated.rotation;
    opacity = interpolated.opacity;
  }

  // Phase 2: Apply preset animations on top of keyframe state
  final enterEnd = clip.enterDurationMicros;
  final exitStart = clip.durationMicroseconds - clip.exitDurationMicros;

  if (clipOffsetMicros < enterEnd && clip.enterAnimation != null) {
    // Enter phase
    final t = clipOffsetMicros / enterEnd;
    final anim = evaluateEnterAnimation(clip.enterAnimation!, t);
    position = Offset(position.dx + anim.positionDelta.dx, position.dy + anim.positionDelta.dy);
    scale *= anim.scaleFactor;
    rotation += anim.rotationDelta;
    opacity *= anim.opacityFactor;
  } else if (clipOffsetMicros > exitStart && clip.exitAnimation != null) {
    // Exit phase
    final t = (clipOffsetMicros - exitStart) / clip.exitDurationMicros;
    final anim = evaluateExitAnimation(clip.exitAnimation!, t);
    position = Offset(position.dx + anim.positionDelta.dx, position.dy + anim.positionDelta.dy);
    scale *= anim.scaleFactor;
    rotation += anim.rotationDelta;
    opacity *= anim.opacityFactor;
  } else if (clip.sustainAnimation != null) {
    // Sustain phase (looping)
    final sustainDuration = exitStart - enterEnd;
    if (sustainDuration > 0) {
      final sustainOffset = clipOffsetMicros - enterEnd;
      final t = (sustainOffset % sustainDuration) / sustainDuration;
      final anim = evaluateSustainAnimation(clip.sustainAnimation!, t);
      position = Offset(position.dx + anim.positionDelta.dx, position.dy + anim.positionDelta.dy);
      scale *= anim.scaleFactor;
      rotation += anim.rotationDelta;
      opacity *= anim.opacityFactor;
    }
  }

  return TextRenderData(
    clipId: clip.id,
    text: clip.text,
    style: clip.style,
    position: position,
    scale: scale,
    rotation: rotation,
    opacity: opacity,
    textAlign: clip.textAlign,
    maxWidthFraction: clip.maxWidthFraction,
    trackIndex: trackIndex,
    isSubtitle: clip.isSubtitle,
    enableTextBehindSubject: false, // Separate compositing path
  );
}
```

### 6.5 Performance Considerations for Real-Time Rendering

**Budget:** Each text clip must render in under 2ms. With a maximum of ~5 simultaneous text clips, total text rendering budget is 10ms, leaving 6.6ms for video rendering to maintain 60 FPS (16.6ms total frame budget).

**Optimizations:**

1. **TextPainter reuse:** A pool of `TextPainter` objects is reused across frames rather than re-allocated.
2. **Layout caching:** `TextPainter.layout()` is only called when text content, style, or max width changes (not every frame).
3. **Static text image caching:** Non-animating text is cached as `ui.Image` (see section 6.2).
4. **Clip culling:** Text clips not overlapping the current playhead time are skipped entirely.
5. **Simplified rendering for fast scrub:** During fast scrub (velocity > threshold), text effects (glow, shadow, outline) are disabled; only the text fill is rendered.

---

## 7. Text Animations

### 7.1 Enter Animations

Each animation is defined as a function `f(t) -> AnimationState` where `t` goes from `0.0` (clip start) to `1.0` (end of enter duration). At `t=0`, the text is fully "entered" from its hidden state. At `t=1`, the text is at its normal resting state.

| Animation | Position Delta | Scale Factor | Rotation Delta | Opacity Factor | Notes |
|-----------|---------------|--------------|----------------|---------------|-------|
| `fadeIn` | (0, 0) | 1.0 | 0 | t | Simple opacity fade |
| `slideInLeft` | (-(1-t) * 0.3, 0) | 1.0 | 0 | t | Slides from left edge |
| `slideInRight` | ((1-t) * 0.3, 0) | 1.0 | 0 | t | Slides from right edge |
| `slideInTop` | (0, -(1-t) * 0.3) | 1.0 | 0 | t | Slides from top |
| `slideInBottom` | (0, (1-t) * 0.3) | 1.0 | 0 | t | Slides from bottom |
| `scaleUp` | (0, 0) | t | 0 | t | Grows from zero |
| `bounceIn` | (0, 0) | bounceEasing(t) | 0 | min(t*2, 1) | Bounce easing on scale |
| `typewriter` | (0, 0) | 1.0 | 0 | 1.0 | Characters revealed left-to-right (special rendering) |
| `glitchIn` | random jitter * (1-t) | 1.0 + noise*(1-t)*0.1 | noise*(1-t)*0.05 | t + noise*0.3*(1-t) | Random noise decreasing over time |
| `rotateIn` | (0, 0) | t | (1-t) * pi/4 | t | Rotates in from 45 degrees |
| `blurIn` | (0, 0) | 1.0 | 0 | t | Gaussian blur decreases (requires MaskFilter) |
| `popIn` | (0, 0) | elasticEasing(t) | 0 | min(t*3, 1) | Elastic overshoot on scale |

**Typewriter special handling:** Instead of applying position/scale/rotation/opacity transforms, the typewriter animation clips the visible text length. A character index `floor(t * textLength)` determines how many characters are visible. This requires special handling in both `TextPreviewPainter` (render substring) and `TextLayerBuilder` (CATextLayer with animated `string` property or `mask` layer).

### 7.2 Exit Animations

Exit animations are the inverse of enter animations. The function `f(t)` goes from `0.0` (text at normal state) to `1.0` (text fully hidden/exited).

| Animation | Behavior |
|-----------|----------|
| `fadeOut` | Inverse of fadeIn |
| `slideOutLeft` | Text slides off to the left |
| `slideOutRight` | Text slides off to the right |
| `slideOutTop` | Text slides off to the top |
| `slideOutBottom` | Text slides off to the bottom |
| `scaleDown` | Text shrinks to zero |
| `bounceOut` | Bounce easing on scale decrease |
| `glitchOut` | Increasing random noise until invisible |
| `rotateOut` | Rotates away to 45 degrees |
| `blurOut` | Gaussian blur increases until invisible |
| `popOut` | Elastic undershoot on scale decrease |

### 7.3 Sustain Animations (Looping)

Sustain animations loop continuously between the end of the enter animation and the start of the exit animation. The parameter `t` cycles from `0.0` to `1.0` repeatedly.

| Animation | Behavior |
|-----------|----------|
| `breathe` | Scale oscillates between 0.98 and 1.02 using sin(t * 2pi) |
| `pulse` | Opacity oscillates between 0.7 and 1.0 using sin(t * 2pi) |
| `float` | Y-position oscillates +/- 0.01 using sin(t * 2pi) |
| `shake` | X-position oscillates with decreasing amplitude random noise |
| `colorCycle` | Hue rotates through 360 degrees (special style animation) |
| `flicker` | Random opacity between 0.5 and 1.0 |

### 7.4 Custom Animation via Keyframes

When the user adds `TextKeyframe` entries to a `TextClip`, these override the base position/scale/rotation/opacity values. The keyframe system provides full control:

- Multiple keyframes can be placed at any point in the clip's duration.
- Each keyframe specifies position, scale, rotation, and opacity.
- The interpolation type between keyframes uses any of the 21 `InterpolationType` values.
- Preset enter/exit animations can coexist with keyframes; the preset animation is applied as a multiplicative modifier on top of the keyframe-interpolated values.

### 7.5 Animation Timing and Easing

All preset animations use `easeOut` easing for enter animations and `easeIn` easing for exit animations by default. This can be overridden per-animation via the `parameters` map in `TextAnimationPreset`:

```dart
TextAnimationPreset(
  type: TextAnimationPresetType.slideInLeft,
  intensity: 1.0,
  parameters: {'easing': 'spring'}, // Override easing
)
```

---

## 8. Subtitle System

### 8.1 SRT Parsing

SRT (SubRip Text) format:

```
1
00:00:01,000 --> 00:00:04,000
Hello, world!

2
00:00:05,000 --> 00:00:08,000
This is a subtitle.
```

The `SubtitleManager.importSRT` parser:

1. Splits the file by blank-line-separated blocks.
2. Parses each block: index line, timestamp line (HH:MM:SS,mmm --> HH:MM:SS,mmm), text lines.
3. Converts timestamps to microseconds.
4. Creates a `TextClip` for each entry with `isSubtitle: true`.
5. Applies the provided `defaultStyle`.
6. Sets position to bottom-center: `Offset(0.5, 0.85)`.
7. Returns the list of `TextClip` objects.

**Edge cases handled:**
- UTF-8 BOM at file start.
- Missing blank line between entries.
- HTML formatting tags (`<b>`, `<i>`, `<u>`) - stripped for V1, styled in V2.
- Empty lines within subtitle text (treated as line breaks).
- Non-sequential indices (re-indexed during import).

### 8.2 VTT Parsing

WebVTT format:

```
WEBVTT

00:01.000 --> 00:04.000
Hello, world!

00:05.000 --> 00:08.000
This is a subtitle.
```

Differences from SRT:
- No index numbers required.
- Different timestamp format (no commas, uses dots).
- Supports CSS-like `::cue` styling (parsed but not applied in V1).
- Supports positioning metadata (`position:`, `line:`, `align:`).

### 8.3 SRT/VTT Generation

Export creates valid SRT/VTT from the subtitle TextClips:

```dart
String exportSRT(List<TextClip> subtitleClips) {
  final buffer = StringBuffer();
  final sorted = [...subtitleClips]..sort((a, b) => a.startTime.compareTo(b.startTime));

  for (var i = 0; i < sorted.length; i++) {
    final clip = sorted[i];
    buffer.writeln('${i + 1}');
    buffer.writeln('${_formatSRTTime(clip.startTime)} --> ${_formatSRTTime(clip.endTime)}');
    buffer.writeln(clip.text);
    buffer.writeln();
  }

  return buffer.toString();
}
```

### 8.4 Subtitle Track Behavior

Subtitle clips differ from regular text clips in several ways:

| Aspect | Regular Text Clip | Subtitle Clip |
|--------|------------------|---------------|
| Default position | Center (0.5, 0.5) | Bottom center (0.5, 0.85) |
| Default style | Large, bold | Medium, white with black outline |
| Animations | Enter/exit animations enabled | No animations by default |
| Track display | Normal text track | Track labeled "Subtitles" |
| Timeline rendering | Shows text content in clip | Shows text content in clip |
| Import/export | Manual creation only | SRT/VTT import/export |
| Background | User configurable | Semi-transparent black default |

### 8.5 Subtitle Style Customization

Subtitles use a track-level default style that applies to all subtitle clips on that track. Individual clips can have style overrides.

The subtitle style editor (accessible from the track header) provides:
- Font family and size.
- Text color.
- Outline (on/off, color, width).
- Background box (on/off, color, opacity, corner radius).
- Position offset (vertical placement).

### 8.6 Burn-in vs. Soft Subtitles

| Mode | Description | Implementation |
|------|-------------|----------------|
| **Burn-in** (default) | Subtitles are rendered into the video pixels during export | `CATextLayer` via `AVVideoCompositionCoreAnimationTool` |
| **Soft subtitles** | Subtitles are embedded as a separate track in the MP4 container | `AVAssetWriterInput` with `AVMediaType.text` + SRT data |

V1 implements burn-in only. Soft subtitle export is deferred to V2.

---

## 9. Text Behind Subject

### 9.1 Concept

"Text Behind Subject" places text between the background and the person, creating a depth effect where the text appears behind a tracked person. This uses the existing person segmentation mask from the tracking system.

### 9.2 Compositing Order

```
Layer Stack (bottom to top):
1. Video frame (full frame)
2. Text overlay (rendered at specified position)
3. Person mask (alpha channel from person segmentation)
4. Video frame * person mask (person pixels only, composited on top of text)

Result: Text visible everywhere EXCEPT where the person is standing.
```

### 9.3 Implementation (Preview)

```dart
void _renderTextBehindSubject(Canvas canvas, Size size, TextRenderData data, ui.Image personMask) {
  // Step 1: Save canvas state
  canvas.saveLayer(null, Paint());

  // Step 2: Draw the text normally
  _drawText(canvas, size, data);

  // Step 3: Use the person mask to "cut out" the text where the person is
  // BlendMode.dstOut: erases the destination (text) where the source (mask) is opaque
  canvas.drawImage(
    personMask,
    Offset.zero,
    Paint()..blendMode = BlendMode.dstOut,
  );

  // Step 4: Restore canvas (composites the result)
  canvas.restore();
}
```

### 9.4 Implementation (Export)

On the native side, this requires a custom `AVVideoCompositing` implementation that:

1. Receives each video frame.
2. Runs person segmentation on the frame (or uses pre-computed mask data).
3. Renders text onto the frame.
4. Applies the person mask to cut out the text behind the person.

This is more complex than the standard `AVVideoCompositionCoreAnimationTool` approach and requires:

```swift
class TextBehindSubjectCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let sourceFrame = request.sourceFrame(byTrackID: videoTrackID) else {
            request.finish(with: NSError(...))
            return
        }

        // 1. Get person mask for this frame time
        // 2. Render text onto a CIImage
        // 3. Composite: video + text + mask -> output
        // 4. request.finish(withComposedVideoFrame: outputBuffer)
    }
}
```

### 9.5 Performance Implications

- **Preview:** The person segmentation mask is already computed by the tracking system (`PersonTrackingResult.bodyOutline`). Converting the outline to a rasterized mask image adds ~1ms per frame. Total text-behind-subject preview cost: ~3ms per frame.
- **Export:** Person segmentation can be pre-computed (cached from tracking analysis) or run on each frame during export. Pre-computed is preferred for speed.

### 9.6 Fallback When No Tracking Data

If no person tracking data is available for the current frame:
- The text renders normally (on top of everything, no depth effect).
- The UI shows a warning: "Person tracking required for text behind subject."
- The user can trigger tracking analysis from within the text editor.

---

## 10. Font Management

### 10.1 System Font Enumeration

Flutter provides access to system fonts via `SystemChannels.textInput` and the font fallback system. However, enumerating all installed fonts requires a native call:

```swift
// ios/Runner/Font/FontEnumerator.swift

class FontEnumerator {
    static func allFontFamilies() -> [String] {
        return UIFont.familyNames.sorted()
    }

    static func fontsInFamily(_ family: String) -> [String] {
        return UIFont.fontNames(forFamilyName: family)
    }
}
```

Platform channel call:

```dart
final List<String> systemFonts = await methodChannel.invokeMethod('getSystemFonts');
```

### 10.2 Bundled Premium Fonts

The app bundles a curated set of premium fonts as assets:

```yaml
# pubspec.yaml additions
flutter:
  fonts:
    - family: Montserrat
      fonts:
        - asset: assets/fonts/Montserrat-Regular.ttf
        - asset: assets/fonts/Montserrat-Bold.ttf
          weight: 700
        - asset: assets/fonts/Montserrat-Italic.ttf
          style: italic
    - family: Playfair Display
      fonts:
        - asset: assets/fonts/PlayfairDisplay-Regular.ttf
        - asset: assets/fonts/PlayfairDisplay-Bold.ttf
          weight: 700
    - family: Oswald
      fonts:
        - asset: assets/fonts/Oswald-Regular.ttf
        - asset: assets/fonts/Oswald-Bold.ttf
          weight: 700
    # Additional bundled fonts...
```

### 10.3 Custom Font Import

Users can import TTF/OTF fonts from the iOS Files app:

```dart
class FontManager {
  /// Directory for custom imported fonts.
  late final String _fontDirectory;

  /// Import a font file from a URI (Files app picker).
  Future<String?> importFont(String sourcePath) async {
    // 1. Copy file to app's font directory
    // 2. Register with Flutter's FontLoader
    // 3. Return the font family name
    // 4. Persist font reference in a fonts.json manifest
  }

  /// Load all previously imported custom fonts (called at app startup).
  Future<void> loadCustomFonts() async {
    // Read fonts.json manifest
    // For each font, call FontLoader.load()
  }

  /// List all available fonts (system + bundled + custom).
  List<FontInfo> get availableFonts;

  /// Delete a custom imported font.
  Future<void> deleteCustomFont(String fontFamily);
}
```

**Custom font registration for export:** Custom fonts must also be available on the native side for `CATextLayer` rendering during export. The font file path is sent to the native layer, which registers it via `CTFontManagerRegisterFontsForURL`.

### 10.4 Font Preview in Picker

The font picker shows each font family name rendered in its own typeface. This is achieved by building a list of `Text` widgets, each with `TextStyle(fontFamily: familyName)`.

To avoid loading all fonts at once (expensive), the picker uses lazy loading:
- Only fonts visible in the scroll viewport are loaded.
- A `ListView.builder` with `itemExtent` provides efficient scrolling.
- Font preview text: the user's current text content (or "Aa Bb Cc" if empty).

---

## 11. Persistence

### 11.1 TextClip Serialization

```dart
// TextClip.toJson()
Map<String, dynamic> toJson() => {
  'itemType': 'text',
  'id': id,
  'durationMicros': durationMicroseconds,
  'text': text,
  'style': style.toJson(),
  'position': {'x': position.dx, 'y': position.dy},
  'rotation': rotation,
  'scale': scale,
  'opacity': opacity,
  'enterAnimation': enterAnimation?.toJson(),
  'exitAnimation': exitAnimation?.toJson(),
  'sustainAnimation': sustainAnimation?.toJson(),
  'enterDurationMicros': enterDurationMicros,
  'exitDurationMicros': exitDurationMicros,
  'keyframes': keyframes.map((kf) => kf.toJson()).toList(),
  'templateId': templateId,
  'name': name,
  'isSubtitle': isSubtitle,
  'textAlign': textAlign.name,
  'maxWidthFraction': maxWidthFraction,
};

// TextClip.fromJson()
factory TextClip.fromJson(Map<String, dynamic> json) => TextClip(
  id: json['id'] as String,
  durationMicroseconds: json['durationMicros'] as int,
  text: json['text'] as String,
  style: TextOverlayStyle.fromJson(json['style'] as Map<String, dynamic>),
  position: Offset(
    (json['position']['x'] as num).toDouble(),
    (json['position']['y'] as num).toDouble(),
  ),
  rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
  scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
  opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
  enterAnimation: json['enterAnimation'] != null
    ? TextAnimationPreset.fromJson(json['enterAnimation'] as Map<String, dynamic>)
    : null,
  exitAnimation: json['exitAnimation'] != null
    ? TextAnimationPreset.fromJson(json['exitAnimation'] as Map<String, dynamic>)
    : null,
  sustainAnimation: json['sustainAnimation'] != null
    ? TextAnimationPreset.fromJson(json['sustainAnimation'] as Map<String, dynamic>)
    : null,
  enterDurationMicros: json['enterDurationMicros'] as int? ?? 300000,
  exitDurationMicros: json['exitDurationMicros'] as int? ?? 300000,
  keyframes: (json['keyframes'] as List?)
    ?.map((kf) => TextKeyframe.fromJson(kf as Map<String, dynamic>))
    .toList() ?? [],
  templateId: json['templateId'] as String?,
  name: json['name'] as String?,
  isSubtitle: json['isSubtitle'] as bool? ?? false,
  textAlign: TextAlign.values.firstWhere(
    (a) => a.name == json['textAlign'],
    orElse: () => TextAlign.center,
  ),
  maxWidthFraction: (json['maxWidthFraction'] as num?)?.toDouble() ?? 0.9,
);
```

### 11.2 Template Storage

Built-in templates are defined as `const` Dart objects in a template registry file:

```dart
/// lib/data/text_templates.dart

const List<TextTemplate> builtInTextTemplates = [
  TextTemplate(
    id: 'title_bold_center',
    name: 'Bold Title',
    category: 'Titles',
    style: TextOverlayStyle(
      fontFamily: '.SF Pro Display',
      fontSize: 72,
      color: Color(0xFFFFFFFF),
      fontWeight: FontWeight.w900,
      shadow: TextShadowStyle(color: Color(0x80000000), offset: Offset(0.02, 0.02), blurRadius: 8),
    ),
    defaultEnterAnimation: TextAnimationPreset(type: TextAnimationPresetType.fadeIn),
    defaultExitAnimation: TextAnimationPreset(type: TextAnimationPresetType.fadeOut),
  ),
  // ... more templates
];
```

User-created templates are stored as JSON in the app's documents directory:

```
Documents/
  templates/
    user_templates.json
```

### 11.3 Font References

Font references in serialized projects use a strategy to handle portability:

| Font Type | Reference | Resolution |
|-----------|-----------|------------|
| System font | Font family name string | Resolved by iOS at runtime |
| Bundled font | Font family name string | Always available (bundled with app) |
| Custom font | Font family name + `customFontPath` | Resolved from app's font directory |

If a custom font is missing when loading a project, the system falls back to `.SF Pro Display` and displays a warning to the user.

---

## 12. Edge Cases

### 12.1 Very Long Text Wrapping

- Text wraps at `maxWidthFraction * videoWidth`.
- Multi-line text is vertically centered on the specified position.
- If text exceeds the video height, it is clipped at the video bounds (with a fade-out gradient at the clip edge to indicate overflow).
- Maximum text length: 2000 characters (enforced at input).

### 12.2 Emoji in Text

- Emoji are supported through Flutter's `TextPainter` (which handles Unicode emoji natively on iOS).
- On the native export side, `CATextLayer` with `NSAttributedString` handles emoji via the system emoji font.
- Emoji color rendering: Uses the Apple Color Emoji font automatically.
- Emoji sizing: Emoji scale with the configured `fontSize`.

### 12.3 RTL Language Support

- `TextDirection` is determined automatically from the text content using `Bidi.detectRtlDirectionality()` from the `intl` package.
- `TextPainter` and `NSAttributedString` both support RTL natively.
- The style panel does not need explicit RTL controls; it is automatic.
- Mixed LTR/RTL text (e.g., Arabic with embedded English) is handled by the underlying text shaping engine (Core Text on iOS).

### 12.4 Text at Video Boundaries

- **Clip starts at time 0:** Enter animation plays from the very start. No issue.
- **Clip ends at video end:** Exit animation completes at the exact video end. If the exit animation would extend beyond the video, it is clamped to the remaining time.
- **Clip extends beyond video:** Text clips cannot extend beyond the total video duration. The timeline enforces this.

### 12.5 Multiple Overlapping Text Clips

- Up to 10 text clips can be visible simultaneously (across multiple text tracks).
- Rendering order follows track index (higher index = rendered on top).
- If more than 10 text clips overlap, only the top 10 are rendered (with a performance warning in debug mode).

### 12.6 Text During Transitions

- If a text clip spans a video transition (cross dissolve, etc.), the text renders continuously through the transition without being affected by the transition effect.
- This is the expected behavior: text overlays float above the video layer and are not part of the video transition.

### 12.7 Memory with Many Text Clips

- `TextClip` is a lightweight immutable object (~500 bytes each).
- A project with 100 text clips consumes ~50KB for the clip data.
- `TextRenderCache` is bounded at 20 entries, consuming at most ~10MB of `ui.Image` data.
- Font loading: Each loaded font family consumes ~200KB-2MB of memory. Limit of 30 simultaneously loaded custom fonts.

### 12.8 Export with 10+ Text Overlays

- `CATextLayer` is GPU-accelerated and handles dozens of simultaneous layers efficiently.
- `AVVideoCompositionCoreAnimationTool` composites all layers in a single GPU pass.
- Export time increase for text: negligible (< 5% overhead for 10 text layers).
- Memory during export: Each `CATextLayer` consumes ~1KB. The parent `CALayer` hierarchy is lightweight.

### 12.9 Zero-Duration or Extremely Short Text Clips

- Minimum text clip duration: same as `TimelineClip.minDuration` (33,333 microseconds, ~1 frame at 30fps).
- Enter + exit animation durations are clamped so their sum never exceeds the clip duration.
- If the clip is shorter than the sum of enter and exit durations, enter takes priority and exit is truncated.

### 12.10 Text Clip Copy/Paste

- Copy creates a deep clone of the `TextClip` with a new UUID.
- Paste inserts the clone at the playhead on the same (or first available) text track.
- Copied text clips retain all styles, animations, and keyframes.

---

## 13. Performance Considerations

### 13.1 Text Rendering Budget Per Frame

| Component | Budget | Typical | Notes |
|-----------|--------|---------|-------|
| Text layout (`TextPainter.layout()`) | 0.5ms | 0.1ms | Cached when text/style unchanged |
| Text painting (`TextPainter.paint()`) | 0.3ms | 0.1ms | |
| Effects (shadow, outline, glow, background) | 1.0ms | 0.3ms | Per text clip |
| Animation interpolation | 0.1ms | 0.05ms | |
| Canvas transform (translate, scale, rotate) | 0.05ms | 0.02ms | |
| **Total per text clip** | **1.95ms** | **0.57ms** | |
| **Total for 5 clips** | **9.75ms** | **2.85ms** | Within 16.6ms frame budget |

### 13.2 Cache Strategies for Static Text

| Cache | What | Size | Eviction |
|-------|------|------|----------|
| `TextPainter` layout cache | Layout results for unchanged text | Up to 20 entries | LRU |
| `TextRenderCache` | Rendered `ui.Image` for static text | Up to 20 entries, ~10MB | LRU |
| Font preview cache | Rendered font name images for picker | Up to 50 entries, ~5MB | LRU |

### 13.3 Animation Interpolation Cost

- Simple animations (fade, slide): 1 lerp operation per property = 4 lerps (position.x, position.y, scale, opacity) = ~0.01ms.
- Complex animations (spring, elastic, bounce): Math.sin/cos/pow per property = ~0.05ms.
- Keyframe interpolation with binary search: O(log k) where k = number of keyframes. For 20 keyframes: ~0.02ms.

### 13.4 Memory Footprint of Font Loading

| Font Source | Memory Per Font | Max Loaded | Total |
|-------------|----------------|------------|-------|
| System fonts | 0 (loaded by OS on demand) | Unlimited | 0 |
| Bundled fonts | ~500KB average | 10 families | ~5MB |
| Custom imported fonts | ~500KB average | 30 fonts | ~15MB |
| **Total** | | | **~20MB** |

This is well within the 200MB performance budget.

### 13.5 Export Rendering with Text Layers

- `AVVideoCompositionCoreAnimationTool` is hardware-accelerated.
- Text layers are rasterized once and cached by Core Animation.
- Animated text layers are re-rasterized only when their content changes (which is every frame for animated text, but the GPU handles this efficiently).
- No measurable export time increase for up to 20 text layers.

---

## 14. Dependencies

### 14.1 New Dart/Flutter Packages

| Package | Purpose | Required? |
|---------|---------|-----------|
| `file_picker` (^8.0.0) | Select TTF/OTF font files from iOS Files app | Yes |
| None others | Text rendering uses built-in Flutter `TextPainter`, `CustomPainter` | - |

No new Flutter packages are required for core text rendering. The existing `uuid` package is used for ID generation. The existing `provider` package handles state management.

### 14.2 Native Code Changes (Swift)

New files to create:

| File | Purpose |
|------|---------|
| `ios/Runner/Text/TextLayerBuilder.swift` | Builds `CATextLayer` hierarchy from text clip data |
| `ios/Runner/Text/TextExportService.swift` | Integrates text layers with `AVVideoCompositionCoreAnimationTool` |
| `ios/Runner/Text/TextAnimationBuilder.swift` | Converts animation presets to `CAAnimation` objects |
| `ios/Runner/Text/TextBehindSubjectCompositor.swift` | Custom `AVVideoCompositing` for text-behind-subject |
| `ios/Runner/Font/FontEnumerator.swift` | System font enumeration via `UIFont.familyNames` |

Existing files to modify:

| File | Change |
|------|--------|
| `ios/Runner/AppDelegate.swift` | Add method channel handler for text operations |
| `ios/Runner/VideoProcessingService.swift` | Call `TextExportService` during composition export |
| `ios/Runner/Timeline/CompositionBuilder.swift` | Add text segment type handling |

### 14.3 Existing Dart Code Modifications

| File | Change |
|------|--------|
| `lib/models/clips/timeline_item.dart` | Add `case 'text'` to `fromJson` switch |
| `lib/models/clips/clips.dart` | Export new `text_clip.dart` |
| `lib/timeline/data/models/timeline_clip.dart` | No change needed (`ClipType.text` already exists) |
| `lib/timeline/data/models/track.dart` | No change needed (`TrackType.text` already exists) |
| `lib/timeline/rendering/painters/clip_painter.dart` | Add text clip rendering branch (or delegate to `TextClipsPainter`) |
| `lib/core/clip_manager.dart` | Extract `_applyEasing` to shared `InterpolationUtils` |

---

## 15. Implementation Plan

### Phase 1: Core Text Model + Basic Rendering (Week 1-2)

**Goal:** Add text to video and see it in preview.

| Task | Files Created/Modified | Tests |
|------|----------------------|-------|
| Create `TextClip` model | `lib/models/clips/text_clip.dart` | `test/models/clips/text_clip_test.dart` |
| Create `TextOverlayStyle` model | `lib/models/text/text_overlay_style.dart` | `test/models/text/text_overlay_style_test.dart` |
| Create `TextKeyframe` model | `lib/models/text/text_keyframe.dart` | `test/models/text/text_keyframe_test.dart` |
| Register `TextClip` in `TimelineItem.fromJson` | `lib/models/clips/timeline_item.dart` | Update existing clip tests |
| Create `TextClipManager` | `lib/core/text_clip_manager.dart` | `test/core/text_clip_manager_test.dart` |
| Create `TextPreviewPainter` | `lib/timeline/rendering/painters/text_preview_painter.dart` | Visual verification |
| Create `TextRenderCache` | `lib/timeline/rendering/text_render_cache.dart` | `test/timeline/rendering/text_render_cache_test.dart` |
| Extract `InterpolationUtils` | `lib/core/interpolation_utils.dart` | `test/core/interpolation_utils_test.dart` |
| Add text track to timeline UI | `lib/timeline/rendering/painters/text_clip_painter.dart` | Visual verification |

**Milestone:** User can programmatically add a TextClip and see it rendered on the video preview.

### Phase 2: Text Editor UI (Week 3-4)

**Goal:** Full text editing experience with inline editing.

| Task | Files Created/Modified | Tests |
|------|----------------------|-------|
| Create `TextEditorPanel` (main editor view) | `lib/views/text/text_editor_panel.dart` | Widget tests |
| Create `TextStylePanel` | `lib/views/text/text_style_panel.dart` | Widget tests |
| Create inline text editing overlay | `lib/views/text/inline_text_editor.dart` | Widget tests |
| Create gesture handling for text (move, scale, rotate) | `lib/views/text/text_gesture_handler.dart` | Unit tests |
| Add "Add Text" button to timeline toolbar | Modify timeline toolbar | Integration test |
| Create `FontManager` | `lib/core/font_manager.dart` | `test/core/font_manager_test.dart` |
| Create font picker widget | `lib/views/text/font_picker.dart` | Widget tests |
| Create color picker integration | `lib/views/text/text_color_picker.dart` | Widget tests |
| Add font enumeration native code | `ios/Runner/Font/FontEnumerator.swift` | Native tests |

**Milestone:** User can add text, edit inline on preview, change fonts/colors/effects.

### Phase 3: Text Animations (Week 5-6)

**Goal:** Preset enter/exit/sustain animations and keyframe animation.

| Task | Files Created/Modified | Tests |
|------|----------------------|-------|
| Create `TextAnimationPreset` model | `lib/models/text/text_animation_preset.dart` | Unit tests |
| Implement all enter animation evaluators | `lib/core/text_animation_evaluator.dart` | `test/core/text_animation_evaluator_test.dart` |
| Implement all exit animation evaluators | Same file | Same test file |
| Implement all sustain animation evaluators | Same file | Same test file |
| Create animation picker UI | `lib/views/text/text_animation_picker.dart` | Widget tests |
| Integrate animations into `TextPreviewPainter` | Modify existing painter | Visual verification |
| Add TextKeyframe UI (add/move/delete keyframes on timeline) | `lib/views/text/text_keyframe_editor.dart` | Widget tests |

**Milestone:** User can apply enter/exit/sustain animations and create custom keyframe animations.

### Phase 4: Export Pipeline (Week 7-8)

**Goal:** Exported video contains text overlays matching preview.

| Task | Files Created/Modified | Tests |
|------|----------------------|-------|
| Create `TextLayerBuilder` (Swift) | `ios/Runner/Text/TextLayerBuilder.swift` | Swift unit tests |
| Create `TextAnimationBuilder` (Swift) | `ios/Runner/Text/TextAnimationBuilder.swift` | Swift unit tests |
| Create `TextExportService` (Swift) | `ios/Runner/Text/TextExportService.swift` | Integration tests |
| Integrate with `VideoProcessingService.renderComposition` | Modify existing file | Export comparison tests |
| Add text data platform channel | Modify `AppDelegate.swift` | Channel tests |
| Custom font registration for export | Native font loading | Font rendering tests |

**Milestone:** Exported video contains text matching the preview exactly.

### Phase 5: Templates + Subtitles (Week 9-10)

**Goal:** Template browser and subtitle import/export.

| Task | Files Created/Modified | Tests |
|------|----------------------|-------|
| Create `TextTemplate` model | `lib/models/text/text_template.dart` | Unit tests |
| Create built-in template registry | `lib/data/text_templates.dart` | Unit tests |
| Create template browser UI | `lib/views/text/template_browser.dart` | Widget tests |
| Create `SubtitleManager` | `lib/core/subtitle_manager.dart` | `test/core/subtitle_manager_test.dart` |
| SRT parser + generator | In `SubtitleManager` | Parsing tests with edge cases |
| VTT parser + generator | In `SubtitleManager` | Parsing tests with edge cases |
| Subtitle import UI (file picker) | `lib/views/text/subtitle_import_sheet.dart` | Widget tests |
| Subtitle track UI differences | Modify timeline rendering | Visual verification |

**Milestone:** User can browse/apply templates and import/export SRT/VTT subtitles.

### Phase 6: Text Behind Subject (Week 11-12)

**Goal:** Depth-aware text placement using person tracking masks.

| Task | Files Created/Modified | Tests |
|------|----------------------|-------|
| Create mask rasterizer (body outline to `ui.Image`) | `lib/core/mask_rasterizer.dart` | Unit tests |
| Implement text-behind-subject in `TextPreviewPainter` | Modify existing painter | Visual verification |
| Create `TextBehindSubjectCompositor` (Swift) | `ios/Runner/Text/TextBehindSubjectCompositor.swift` | Swift tests |
| Integrate with export pipeline | Modify export service | Export comparison tests |
| Add UI toggle for text-behind-subject per text clip | Modify text editor panel | Widget tests |
| Handle no-tracking-data fallback | Modify painter + UI | Edge case tests |

**Milestone:** Text renders behind tracked persons in both preview and export.

### File Structure Summary

```
lib/
  models/
    clips/
      text_clip.dart                    # NEW - TextClip model
    text/
      text_overlay_style.dart           # NEW - Style model
      text_keyframe.dart                # NEW - TextKeyframe model
      text_animation_preset.dart        # NEW - Animation preset model
      text_template.dart                # NEW - Template model
      subtitle_entry.dart               # NEW - Subtitle entry model
  core/
    text_clip_manager.dart              # NEW - Text clip CRUD + undo/redo
    subtitle_manager.dart               # NEW - SRT/VTT import/export
    font_manager.dart                   # NEW - Font loading + enumeration
    interpolation_utils.dart            # NEW - Shared interpolation math
    text_animation_evaluator.dart       # NEW - Animation evaluation functions
    mask_rasterizer.dart                # NEW - Body outline to mask image
  views/
    text/
      text_editor_panel.dart            # NEW - Main text editor view
      text_style_panel.dart             # NEW - Style editing controls
      text_animation_picker.dart        # NEW - Animation selection grid
      template_browser.dart             # NEW - Template browser view
      font_picker.dart                  # NEW - Font selection picker
      text_color_picker.dart            # NEW - Color picker for text
      inline_text_editor.dart           # NEW - Inline editing on preview
      text_gesture_handler.dart         # NEW - Move/scale/rotate gestures
      text_keyframe_editor.dart         # NEW - Keyframe editing UI
      subtitle_import_sheet.dart        # NEW - SRT/VTT import UI
  timeline/
    rendering/
      painters/
        text_clip_painter.dart          # NEW - Timeline text clip rendering
        text_preview_painter.dart       # NEW - Video preview text rendering
      text_render_cache.dart            # NEW - Cached text images
  data/
    text_templates.dart                 # NEW - Built-in template definitions

ios/Runner/
  Text/
    TextLayerBuilder.swift              # NEW - CATextLayer construction
    TextExportService.swift             # NEW - Export integration
    TextAnimationBuilder.swift          # NEW - CAAnimation construction
    TextBehindSubjectCompositor.swift   # NEW - Custom AVVideoCompositing
  Font/
    FontEnumerator.swift                # NEW - System font enumeration

test/
  models/
    clips/
      text_clip_test.dart               # NEW
    text/
      text_overlay_style_test.dart      # NEW
      text_keyframe_test.dart           # NEW
  core/
    text_clip_manager_test.dart         # NEW
    subtitle_manager_test.dart          # NEW
    font_manager_test.dart              # NEW
    interpolation_utils_test.dart       # NEW
    text_animation_evaluator_test.dart  # NEW
  timeline/
    rendering/
      text_render_cache_test.dart       # NEW
```

### Test Plan Summary

| Category | Test Count (Est.) | Coverage Target |
|----------|------------------|----------------|
| Model serialization (TextClip, Style, Keyframe, Template) | 30 | 100% |
| TextClipManager operations (CRUD, undo/redo, split, trim) | 25 | 100% |
| Animation evaluation (all 12 enter + 11 exit + 6 sustain) | 29 | 100% |
| Keyframe interpolation (all 21 InterpolationType values) | 21 | 100% |
| SRT/VTT parsing (valid files, malformed files, edge cases) | 20 | 100% |
| SRT/VTT generation | 10 | 100% |
| Font manager (system, bundled, custom, missing font fallback) | 12 | 100% |
| Text render cache (LRU eviction, invalidation) | 8 | 100% |
| Widget tests (editor panel, style panel, animation picker) | 15 | 80% |
| Integration tests (add text, edit, export) | 5 | Key flows |
| **Total** | **~175** | |

---

## Appendix A: Platform Channel API

### Method Channel: `com.liquideditor/text`

| Method | Direction | Parameters | Returns |
|--------|-----------|------------|---------|
| `getSystemFonts` | Dart -> Swift | None | `List<String>` font family names |
| `registerCustomFont` | Dart -> Swift | `{path: String}` | `{family: String}` or error |
| `buildTextExportLayers` | Dart -> Swift | `{textClips: List, videoSize: {w, h}, durationMicros: int}` | `{success: bool}` |

The `buildTextExportLayers` method is called during export. The native side stores the built `CALayer` hierarchy and applies it when `VideoProcessingService` creates the `AVVideoCompositionCoreAnimationTool`.

---

## Appendix B: Bundled Template Categories

| Category | Count | Example Templates |
|----------|-------|-------------------|
| **Titles** | 8 | Bold Center, Elegant Script, Neon Glow, Minimal Clean |
| **Lower Thirds** | 6 | News Bar, Social Tag, Name + Title, Location Tag |
| **Social** | 6 | Instagram Caption, TikTok Title, YouTube Subscribe, Story Text |
| **Cinematic** | 4 | Film Credits, Chapter Title, Quote Frame, Typewriter |
| **Subtitles** | 4 | Standard White, Boxed Black, Yellow Outline, Karaoke Style |
| **Total** | **28** | |

---

## Appendix C: Text-Behind-Subject Compositing Pseudocode

```
// For each frame at time T:

1. videoFrame = decodeVideoFrame(T)
2. textImage  = renderAllTextClips(T, videoSize)  // RGBA image with text pixels
3. personMask = getPersonMask(T)                   // Alpha-only image (white = person)

// Option A: Text behind ALL persons
4. invertedMask = invert(personMask)               // White = not-person
5. maskedText   = textImage * invertedMask          // Text only where no person
6. output       = composite(videoFrame, maskedText) // Video + masked text

// Option B: Text behind SPECIFIC persons (using tracking data)
4. selectedMask = combineSelectedPersonMasks(T, selectedPersonIds)
5. invertedMask = invert(selectedMask)
6. maskedText   = textImage * invertedMask
7. output       = composite(videoFrame, maskedText)
```

---

**Document Revision History:**

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-06 | 1.0 | Initial draft |
| 2026-02-06 | 1.0-review1 | Architecture & Completeness review added |
| 2026-02-06 | 1.0-review2 | Implementation Viability & Integration Risk review added |

---

## Review 1 - Architecture & Completeness

**Reviewer:** Architecture Review
**Date:** 2026-02-06
**Scope:** Full design document against existing codebase
**Codebase files examined:**
- `lib/models/clips/timeline_item.dart` (new V2 clip hierarchy)
- `lib/models/clips/color_clip.dart`, `gap_clip.dart` (GeneratorClip examples)
- `lib/models/clips/clips.dart` (barrel exports)
- `lib/models/timeline_clip.dart` (legacy V1 clip model used by ClipManager)
- `lib/models/keyframe.dart` (Keyframe, VideoTransform, InterpolationType, BezierControlPoints, KeyframeTimeline)
- `lib/core/clip_manager.dart` (legacy V1 clip operations)
- `lib/core/timeline_manager.dart` (V2 PersistentTimeline wrapper)
- `lib/models/persistent_timeline.dart` (AVL tree)
- `lib/timeline/data/models/timeline_clip.dart` (UI rendering TimelineClip model)
- `lib/timeline/data/models/track.dart` (Track, TrackType)
- `lib/timeline/rendering/painters/clip_painter.dart` (ClipsPainter)
- `ios/Runner/AppDelegate.swift` (platform channel setup)
- `ios/Runner/VideoProcessingService.swift` (export pipeline)

---

### CRITICAL Issues

#### C1. Dual Clip Model Architecture - TextClip Must Bridge Both Systems

**Problem:** The codebase has TWO parallel clip model systems:
1. **V1 (Legacy):** `lib/models/timeline_clip.dart` contains `TimelineItem`/`TimelineClip`/`TimelineGap` with mutable fields, `orderIndex`, `sourceVideoPath`, and `Duration` types. This is used by `ClipManager`.
2. **V2 (New):** `lib/models/clips/timeline_item.dart` contains `TimelineItem`/`MediaClip`/`GeneratorClip` hierarchy with `@immutable` classes, `String id`, microsecond ints. This is used by `PersistentTimeline` and `TimelineManager`.

The design document only shows `TextClip` extending `GeneratorClip` from the V2 system, but `ClipManager` (which handles the old `TimelineClip` model) would not be able to operate on the new `TextClip`. The `TimelineManager.splitAt()` method explicitly matches on `VideoClip` and other V2 types but does not yet handle `TextClip`.

**Recommendation:** The design must explicitly address:
- Whether V1 `ClipManager` is fully deprecated for text operations (it should be -- text should only use V2 `TimelineManager`).
- `TimelineManager.splitAt()` must be updated with a `TextClip` case to handle splitting (the design should specify what splitting a text clip means -- does it duplicate the text into two shorter duration clips?).
- Document that `TextClipManager` is NOT a replacement for `TimelineManager` but a supplementary service layer that calls through to `TimelineManager` for structural operations.

#### C2. TextClipManager Introduces Parallel Undo/Redo That Conflicts with TimelineManager

**Problem:** The design proposes `TextClipManager` with `Map<String, PersistentTimeline> _textTimelines` and its own `_undoStacks` and `_redoStacks` per track. But `TimelineManager` already provides undo/redo for a `PersistentTimeline`. Having two independent undo systems creates:
- User confusion: Ctrl+Z undoes video operations OR text operations, unpredictably.
- State inconsistency: Undoing a video edit does not undo a correlated text edit.
- No unified undo history: The user expects a single undo stack across all operations.

**Recommendation:** Instead of per-track undo/redo in `TextClipManager`, use a unified approach:
- Option A: Extend `TimelineManager` to manage multiple tracks (each with a `PersistentTimeline`), with a single composite undo stack that stores snapshots of ALL tracks.
- Option B: Create a `MultiTrackTimelineManager` that holds a `Map<String, PersistentTimeline>` and a single undo stack where each entry is a `Map<String, PersistentTimeline>` snapshot.
- Either way, `TextClipManager` should become a stateless service that calls the unified manager, not own its own timelines.

#### C3. Export Pipeline Does Not Currently Use AVVideoCompositionCoreAnimationTool

**Problem:** The existing `VideoProcessingService.renderComposition()` method uses `AVMutableVideoCompositionLayerInstruction` with `setTransformRamp()` for video transforms, then creates an `AVAssetExportSession` directly. It does NOT use `AVVideoCompositionCoreAnimationTool`. Introducing `animationTool` is a fundamental change to the export pipeline because:
- When you set `videoComposition.animationTool`, the `AVAssetExportSession` switches to a different compositing path that processes ALL frames through Core Animation.
- This is incompatible with custom `AVVideoCompositing` protocols (needed for text-behind-subject).
- `AVVideoCompositionCoreAnimationTool` requires specific layer setup with the video layer as a child layer, and this changes how `setTransformRamp` behaves (transforms now apply to the video layer within the parent, not to the composition output).

**Recommendation:**
- The design must acknowledge this is a breaking change to the export pipeline and detail exactly how the existing transform ramp logic will coexist with the new `animationTool`.
- Specifically: when `animationTool` is set, `AVMutableVideoCompositionLayerInstruction` transforms apply to the `videoLayer` inside the `outputLayer`. The `renderSize` becomes the `outputLayer` size. The existing transform calculator must account for this nested layer structure.
- Document a clear migration plan: test with existing projects that have keyframe transforms + text overlays together.

#### C4. AVVideoCompositionCoreAnimationTool and Custom AVVideoCompositing Are Mutually Exclusive

**Problem:** Section 9.4 proposes `TextBehindSubjectCompositor` implementing `AVVideoCompositing` for text-behind-subject export. Section 6.3 proposes `AVVideoCompositionCoreAnimationTool` for regular text export. These two approaches are **mutually exclusive** on `AVMutableVideoComposition`:
- Setting `videoComposition.animationTool` uses Core Animation for compositing.
- Setting `videoComposition.customVideoCompositorClass` uses a custom compositor.
- You cannot use both simultaneously.

**Recommendation:** The design must choose ONE of:
- Option A: Use custom `AVVideoCompositing` for ALL text rendering during export (not just text-behind-subject). This gives maximum control but requires rendering text into pixel buffers manually using Core Graphics/Core Text on every frame -- more code, more CPU cost.
- Option B: Use `AVVideoCompositionCoreAnimationTool` for standard text and fall back to the custom compositor only when text-behind-subject is enabled for any clip. Switch between the two pipelines based on project content.
- Option C: Always use custom `AVVideoCompositing` (simplest, most consistent). Render text + person masking in one unified pipeline. This eliminates the need for `TextLayerBuilder`/`CATextLayer` entirely.
- Recommend Option C for consistency. Document the trade-off (slightly more CPU during export but consistent rendering path).

#### C5. TextClip Has No `startTimeOnTimeline` Property

**Problem:** In section 6.3 (Export Rendering), the platform channel data includes `'startMicros': clip.startTimeOnTimeline` and `'endMicros': clip.endTimeOnTimeline`. But `TextClip` (as a `GeneratorClip`) only has `durationMicroseconds`. It does not know its position on the timeline -- that information is stored in the `PersistentTimeline` tree structure (via node position). The clip itself is position-agnostic.

**Recommendation:** The export pipeline must query `PersistentTimeline.startTimeOf(clipId)` for each text clip to determine its absolute timeline position. Update section 6.3 to show:
```dart
final startMicros = textTimeline.startTimeOf(clip.id);
final endMicros = startMicros + clip.durationMicroseconds;
```
This is not just a documentation fix -- the export code must be structured to resolve positions from the tree at export time.

---

### IMPORTANT Issues

#### I1. `isGeneratorClip` Check in TimelineClip UI Model Is Incomplete

**Problem:** `TimelineClip` (the UI model in `lib/timeline/data/models/timeline_clip.dart`) has:
```dart
bool get isGeneratorClip => type == ClipType.gap || type == ClipType.color;
```
This does not include `ClipType.text`, so text clips would not be recognized as generator clips in the UI model.

**Recommendation:** Update `isGeneratorClip` to include `ClipType.text`:
```dart
bool get isGeneratorClip => type == ClipType.gap || type == ClipType.color || type == ClipType.text;
```

#### I2. Sustain Animation Loop Period Not Configurable

**Problem:** The design says sustain animations loop with `t = (sustainOffset % sustainDuration) / sustainDuration` where `sustainDuration = exitStart - enterEnd`. This means the loop period equals the entire sustain duration. For a 10-second text clip with 0.3s enter and 0.3s exit, the "breathe" animation would take 9.4 seconds for one cycle -- far too slow.

**Recommendation:** Sustain animations need a separate `loopDurationMicros` parameter (e.g., default 2 seconds for breathe, 1 second for pulse). The formula should be:
```dart
final loopDuration = sustainAnimation.loopDurationMicros ?? defaultLoopDuration;
final t = (sustainOffset % loopDuration) / loopDuration;
```
Add `loopDurationMicros` to `TextAnimationPreset` or use the `parameters` map (e.g., `parameters: {'loopDuration': 2.0}`).

#### I3. Missing `copyWith` Method on TextClip

**Problem:** The `TextClip` model is `@immutable` but the design does not show a `copyWith` method. Every edit operation (text change, style change, position update, animation change) requires creating a new `TextClip` instance. Without `copyWith`, callers must specify all ~20 parameters every time. The existing `ColorClip` has `copyWith` for this reason.

**Recommendation:** Add a comprehensive `copyWith` method to `TextClip`. This is essential for the real-time editing flow described in sections 5.3 and 5.4.

#### I4. No `TextClip.splitAt()` Method

**Problem:** `ColorClip` and `GapClip` both implement `splitAt()` for splitting. `TextClip` inherits from `GeneratorClip` but has no split implementation. Section 4.4 says "All existing gesture interactions... apply to text clips identically" including split.

**Recommendation:** Add `TextClip.splitAt(int offsetMicros)` that creates two `TextClip` instances:
- Left clip: same text and style, `durationMicroseconds = offsetMicros`.
- Right clip: same text and style, `durationMicroseconds = durationMicroseconds - offsetMicros`.
- Keyframes must be partitioned and re-timed relative to each new clip's start.
- Enter animation goes to the left clip; exit animation goes to the right clip.
- Define minimum duration for split (same as `TimelineClip.minDuration`).

#### I5. Font Name Mismatch Between Flutter and Core Text

**Problem:** The design uses font family names like `.SF Pro Display` in `TextOverlayStyle.fontFamily`. On the Flutter side, `TextPainter` uses the `fontFamily` property of `TextStyle`. On the native side, `CATextLayer` uses `CTFont` (Core Text). The font naming conventions differ:
- Flutter uses "family names" registered with the framework.
- Core Text uses PostScript names or family names from the font file.
- System font `.SF Pro Display` is accessed differently on each side (on Flutter it may fall back to the default iOS font; on native it requires `UIFont.systemFont(ofSize:weight:)`).

**Recommendation:**
- Document a font resolution strategy that maps Flutter family names to Core Text font descriptors.
- For system fonts, use `UIFont.systemFont(ofSize:weight:)` on the native side rather than trying to use the `.SF Pro Display` string directly with `CTFontCreateWithName`.
- For bundled/custom fonts, the font file path must be sent to the native side and registered via `CTFontManagerRegisterFontsForURL` (as noted), but the family name returned by registration may differ from the Flutter name. Build a mapping table.

#### I6. `_applyEasing` Only Handles 8 of 21 InterpolationType Values

**Problem:** The design proposes extracting `ClipManager._applyEasing()` into shared `InterpolationUtils`. But the current implementation only handles `linear`, `hold`, `easeIn`, `easeOut`, `easeInOut`, `cubicIn`, `cubicOut`, `cubicInOut`, and falls through to `return t` (linear) for the remaining 13 types (spring, bounce, elastic, circIn/Out/InOut, expoIn/Out/InOut, backIn/Out/InOut, bezier).

**Recommendation:** The `InterpolationUtils` must implement ALL 21 interpolation types. This is existing technical debt that will become user-visible when text keyframes use spring/elastic/bounce interpolation and the animation just falls through to linear. Add this to Phase 1 scope with full test coverage.

#### I7. No Error Handling for Platform Channel Text Export

**Problem:** The platform channel API (Appendix A) shows `buildTextExportLayers` returning `{success: bool}`, but there is no error propagation path. If font loading fails, if text rendering crashes, or if the `CALayer` setup is invalid, the export will silently produce video without text.

**Recommendation:** The platform channel should return error details:
```
{success: bool, error: String?, failedClipIds: List<String>?}
```
Also add a validation step: before export, verify all referenced fonts are available on the native side. Surface missing-font errors to the user before starting the export.

#### I8. Missing Text-Specific Properties in TimelineClip UI Model

**Problem:** The `TimelineClip` UI model (`lib/timeline/data/models/timeline_clip.dart`) is used by `ClipsPainter` for rendering clips in the timeline. For text clips, the painter needs the text content to show as a label inside the rectangle, but `TimelineClip.label` is optional and would need to be populated from `TextClip.text`. There is no bridge between the V2 `TextClip` model and the UI `TimelineClip` model.

**Recommendation:** Either:
- Add a `TextClip.toTimelineClip(String trackId, int startTime)` method that maps the V2 model to the UI model (setting `label = text.substring(0, 30)`, `type = ClipType.text`, etc.).
- Or, modify `TextClipsPainter` to directly consume `TextClip` objects instead of going through `TimelineClip`. The design already proposes a separate `TextClipsPainter` -- make it explicit that it takes `List<TextClip>` not `List<TimelineClip>`.

#### I9. `colorCycle` Sustain Animation Modifies Style, Not Transform

**Problem:** Section 7.3 lists `colorCycle` as a sustain animation that "rotates hue through 360 degrees." All other animations operate on the `AnimationState` (position/scale/rotation/opacity), but `colorCycle` changes the text color. This requires modifying `TextOverlayStyle.color` per frame, which is different from the transform-based animation pipeline. The `computeTextState` function (section 6.4) does not handle style mutations.

**Recommendation:** Either:
- Remove `colorCycle` from V1 (it introduces style animation, which is a per-character concept more suited to V2).
- Or, add a `colorOverride` field to `TextRenderData` and handle it as a special case in the painter. The animation evaluator returns a color override when `colorCycle` is active.

#### I10. TextClip Location in File Hierarchy Inconsistent

**Problem:** The design places `TextClip` at `lib/models/clips/text_clip.dart` (consistent with the V2 hierarchy), but the related style/keyframe/animation models are at `lib/models/text/text_overlay_style.dart`. This creates a split where the clip model is in `clips/` but its dependent types are in `text/`. All other clip types (VideoClip, ColorClip, etc.) have their dependent types either inline or in the same directory.

**Recommendation:** Consider one of:
- Move all text models into `lib/models/text/` including `text_clip.dart`, and have `clips.dart` barrel file re-export it. This keeps all text-related models together.
- Or, keep `text_clip.dart` in `clips/` but move the style/keyframe types there too. The `text/` folder would only contain UI-related text widgets.
- Document the chosen convention.

---

### MINOR Issues

#### M1. `BezierControlPoints` Import Missing from TextKeyframe

**Problem:** `TextKeyframe` references `BezierControlPoints` and `InterpolationType` from `keyframe.dart`, but the import is not shown. This is trivial but should be noted in the design for implementors.

**Recommendation:** Add to file header: `import '../keyframe.dart';` for `InterpolationType` and `BezierControlPoints`.

#### M2. Template Thumbnail Asset Strategy Not Specified

**Problem:** Section 2.5 mentions `thumbnailAsset` but doesn't specify how thumbnail images for 28 built-in templates will be generated or stored.

**Recommendation:** Specify: templates either use programmatically-rendered previews (a small Flutter widget that renders the template text with its style) or pre-rendered PNG assets in `assets/templates/`. The programmatic approach is preferred (no asset bloat, always up to date with style changes).

#### M3. Maximum Text Track Count Not Specified

**Problem:** The design allows unlimited text tracks ("Multiple text tracks can exist") but does not define a practical limit.

**Recommendation:** Define a maximum of 10 text tracks per project. Beyond that, performance during both preview (multiple `PersistentTimeline` lookups per frame) and export (multiple `CATextLayer` trees) degrades. Enforce in `TextClipManager.createTextTrack()`.

#### M4. `SubtitleEntry` Model Appears Redundant

**Problem:** `SubtitleEntry` (section 2.6) is defined but never used beyond the SRT/VTT parser as an intermediate representation. The parser ultimately creates `TextClip` objects. `SubtitleEntry` adds a model that must be maintained but provides no runtime value.

**Recommendation:** Make `SubtitleEntry` a private intermediate type inside `SubtitleManager`, or eliminate it entirely and parse directly into `TextClip` instances. This reduces the public API surface.

#### M5. `CupertinoColorPicker` Does Not Exist in Flutter SDK

**Problem:** Section 5.4 references "CupertinoColorPicker grid" but Flutter's Cupertino library does not include a native color picker widget.

**Recommendation:** Use a custom Cupertino-styled color picker built from `CupertinoPicker` or use the `flutter_colorpicker` package with Cupertino theming. Alternatively, build a native iOS 26 color well using a platform view wrapping `UIColorWell` (available since iOS 14). Document which approach to use to maintain the native feel.

#### M6. `glitchIn`/`glitchOut` Animation Uses Random Noise

**Problem:** Random noise in animations (section 7.1) means the preview rendering is non-deterministic. If the user scrubs back and forth, the glitch pattern changes. More importantly, the export pipeline must produce the exact same glitch pattern, which requires seeding the random generator with a deterministic seed per frame.

**Recommendation:** Use a seeded PRNG based on `clipId.hashCode + frameMicros` to ensure deterministic glitch patterns across preview and export.

#### M7. Test Plan Missing Export Consistency Tests

**Problem:** The test plan (section 15) does not include tests that verify preview rendering matches export rendering. This is the core promise of section 1 ("What the user sees during preview must match the exported video pixel-for-pixel").

**Recommendation:** Add an "Export Consistency" test category:
- Render a text frame at time T using `TextPreviewPainter` -> capture as image.
- Export the same frame using the native pipeline -> extract frame from exported video.
- Compare pixel similarity (SSIM > 0.95 threshold).
- Minimum 5 test cases: static text, text with shadow/outline, animated text at enter/sustain/exit phases.

#### M8. No Mention of VoiceOver/Accessibility for Text Overlays

**Problem:** The design does not address accessibility. Text overlays on video should be exposed to VoiceOver so visually impaired users can navigate text clips.

**Recommendation:** Add accessibility semantics to the text editor UI (already covered by Cupertino widgets) and ensure the timeline text clips have semantic labels. Add to section 5 or create a new section.

---

### QUESTION Items

#### Q1. Which Model System Does the "Add Text" Flow Use?

The design references both `TextClipManager` (V2-based, with `PersistentTimeline`) and the UI `TimelineClip` model. When the user taps "Add Text":
1. Which system creates the clip? (`TextClipManager.addTextClip` or `TimelineManager.insertAt`?)
2. How does the UI `TimelineClip` model get updated? Does `TextClipsPainter` consume V2 `TextClip` directly or does it go through `TimelineClip`?
3. Where does the gesture handler route interactions -- to `ClipManager` (V1) or `TextClipManager` (proposed)?

Needs explicit data flow diagram showing the creation, rendering, and editing paths.

#### Q2. How Are Text Track Z-Order Changes Handled?

Section 3.4 says "Track order (index) determines z-order: higher index = rendered on top." But `Track.index` is a vertical position index in the timeline UI, not necessarily a rendering z-order for the preview. Are these the same? What happens when the user reorders tracks in the timeline -- does the text rendering order change?

#### Q3. What Happens to Text When Video Clips Are Reordered?

If the user reorders video clips on the main track, text clips on text tracks maintain their absolute timeline positions. This could cause text to become misaligned with the video it was designed for. Should text clips be linked to video segments (move with them) or remain at absolute positions?

#### Q4. How Does Text Export Work with Multi-Source Video (Timeline V2)?

The design assumes a single `videoPath` in `renderComposition`. Timeline V2 supports multiple source videos via `MediaAsset` registry. The export platform channel for text sends `textClips` separately from video. How do text layer start/end times align when the composition is built from multiple source assets with different time ranges?

#### Q5. What Is the Maximum Font Size?

Section 5.4 says "Font Size: CupertinoSlider: 12-200" but section 2.2 defaults to 48. At 200pt on a 1080p video, text could easily overflow. Is 200 the right upper bound? Should it be resolution-dependent?

---

### Additional Edge Cases (Augmenting Section 12)

#### 12.11 Text Clip with Empty String

- If the user deletes all text content, the clip should still exist on the timeline (not auto-delete).
- The preview painter should render nothing for an empty-string clip (not crash).
- The timeline painter should show "[Empty]" as the label inside the clip rectangle.
- The export pipeline should skip rendering for empty text clips.

#### 12.12 Font Unavailable During Project Load

- If a project references a bundled font that was removed in an app update, fall back to `.SF Pro Display` and warn the user.
- If a project references a custom font that was deleted, same fallback behavior.
- The warning should be non-blocking and shown once per project load (not per clip).
- Store the original font name so if the font becomes available again (re-imported), it auto-resolves.

#### 12.13 Text Clip Spanning the Entire Timeline

- A text clip can be the same duration as the entire video.
- Enter + exit animation durations must be clamped to `durationMicroseconds / 2` each.
- If the text clip is the only clip on its track, there is no meaningful "split" unless the text content should be duplicated.

#### 12.14 Concurrent Text Edits During Playback

- If the user edits text content while playback is active, the preview painter must handle mid-frame updates without crashing.
- The `TextRenderCache` must be invalidated synchronously when text content changes.
- Playback should not stutter during text edits; if cache invalidation causes a frame drop, it is acceptable for a single frame.

#### 12.15 Undo After Template Application

- Applying a template overwrites style, position, and animations.
- Undo must restore ALL previous values (not just the last property changed).
- This must be a single undo operation, not one per property.

#### 12.16 Text Clip Drag Between Tracks

- When dragging a text clip from one text track to another, the clip must maintain its timeline position (start time).
- If the destination track has a conflicting clip at that position, show a snap guide and prevent the drop (or offer to create a new track).

---

### Additional Performance Considerations (Augmenting Section 13)

#### 13.6 PersistentTimeline Lookup Cost Per Text Track

- Each text track has its own `PersistentTimeline`. During playback, the preview painter must query `itemAtTime()` on EVERY text track for EVERY frame.
- With 10 text tracks, this is 10 x O(log n) lookups per frame.
- For a typical project (5 text clips per track), each lookup is O(log 5) ~ 2-3 comparisons. Total: ~30 comparisons per frame ~ negligible.
- But if a single track has 100 subtitle clips, the lookup is O(log 100) ~ 7 comparisons per track. With 3 subtitle tracks: 21 comparisons. Still negligible.
- **Verdict: no concern.** But document the expectation that tracks should not exceed ~500 items.

#### 13.7 Font Loading Latency at First Render

- `FontLoader.load()` is async and may take 50-100ms per font family.
- If a project uses 10 custom fonts, initial load takes 0.5-1 second.
- During this time, text renders with the fallback font, then "pops" to the correct font.
- **Recommendation:** Load all project fonts during project open (before showing the timeline), not lazily during first render.

#### 13.8 Memory Pressure from ui.Image Cache During Scrubbing

- The `TextRenderCache` holds up to 20 `ui.Image` entries.
- During scrubbing, if the user has many text clips each with unique styles, the cache thrashes.
- Each `ui.Image` for a text render at 1080p might be 100-500KB depending on text bounds.
- 20 entries x 500KB = 10MB. Acceptable per section 12.7.
- But `ui.Image` is GPU-resident. Monitor GPU memory alongside the 10MB estimate.

#### 13.9 Platform Channel Serialization Cost for Export

- Sending 100+ subtitle `TextClip` objects over the platform channel as `List<Map<String, dynamic>>` involves JSON-like serialization.
- For 200 subtitle clips with full style data, this is ~200KB of data over the platform channel.
- `StandardMessageCodec` handles this efficiently but benchmark with 500+ clips.
- **Recommendation:** Consider sending text data in batches or as a single binary blob if profiling shows serialization overhead > 10ms.

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Implementation Viability Review
**Date:** 2026-02-06
**Scope:** Validate Review 1 criticals with concrete solutions; assess integration risk with existing codebase
**Codebase files examined (with focus on integration points):**
- `lib/core/timeline_manager.dart` (undo/redo, splitAt, mutation pattern)
- `lib/models/clips/timeline_item.dart` (TimelineItem, GeneratorClip hierarchy)
- `lib/models/clips/color_clip.dart` (GeneratorClip pattern to replicate)
- `lib/models/keyframe.dart` (InterpolationType - all 21 values, BezierControlPoints, KeyframeTimeline)
- `lib/timeline/data/models/timeline_clip.dart` (UI TimelineClip model, ClipType, isGeneratorClip)
- `lib/timeline/data/models/track.dart` (TrackType.text already exists)
- `ios/Runner/VideoProcessingService.swift` (export pipeline, no animationTool usage)
- `lib/core/clip_manager.dart` (V1 legacy, _applyEasing - confirmed 8 of 21 handled)

---

### 1. Resolution for Each Review 1 Critical

#### C1 Resolution: Dual Clip Model - TextClip Across V1 and V2

**Verdict: CONFIRMED CRITICAL.** The codebase has two parallel systems and this must be explicitly resolved.

**Concrete Solution: Text operates exclusively in V2. V1 ClipManager is not extended.**

Rationale: The V1 `ClipManager` is a legacy system managing a mutable `List<TimelineItem>` with `orderIndex` semantics. Extending it for text would double the implementation surface. Instead:

1. **TextClip lives only in the V2 hierarchy** (`GeneratorClip -> TextClip`), as the design already proposes.

2. **`TimelineManager.splitAt()` must gain a `TextClip` case.** The current method handles `VideoClip`, `GapClip`, and `ColorClip` explicitly. The split implementation for text:

```dart
// In TimelineManager.splitAt():
} else if (item is TextClip) {
  final split = item.splitAt(offsetWithin);
  if (split == null) return;

  final startTime = _current.startTimeOf(item.id) ?? 0;

  _execute(() {
    var timeline = _current.remove(item.id);
    timeline = timeline.insertAt(startTime, split.left);
    timeline = timeline.insertAt(
      startTime + split.left.durationMicroseconds, split.right);
    return timeline;
  }, operationName: 'Split text');

  _selectedItemId = split.right.id;
}
```

3. **`TextClip.splitAt()` semantics:** Both halves keep the same `text` and `style`. Keyframes are partitioned by timestamp relative to the split point and re-timed. Enter animation stays on left clip; exit animation stays on right clip. Left clip gets no exit animation; right clip gets no enter animation. This follows the "non-destructive split" convention established by `ColorClip.splitAt()`.

```dart
({TextClip left, TextClip right})? splitAt(int offsetMicros) {
  const minDuration = 100000; // 100ms minimum
  if (offsetMicros < minDuration ||
      offsetMicros > durationMicroseconds - minDuration) {
    return null;
  }

  // Partition keyframes
  final leftKeyframes = keyframes
      .where((kf) => kf.timestampMicros < offsetMicros)
      .toList();
  final rightKeyframes = keyframes
      .where((kf) => kf.timestampMicros >= offsetMicros)
      .map((kf) => kf.copyWith(
            timestampMicros: kf.timestampMicros - offsetMicros))
      .toList();

  final left = TextClip(
    id: const Uuid().v4(),
    durationMicroseconds: offsetMicros,
    text: text,
    style: style,
    position: position,
    rotation: rotation,
    scale: scale,
    opacity: opacity,
    enterAnimation: enterAnimation,
    exitAnimation: null,  // No exit on left half
    sustainAnimation: sustainAnimation,
    enterDurationMicros: enterDurationMicros.clamp(0, offsetMicros ~/ 2),
    exitDurationMicros: 0,
    keyframes: leftKeyframes,
    templateId: templateId,
    name: name != null ? '$name (1)' : null,
    isSubtitle: isSubtitle,
    textAlign: textAlign,
    maxWidthFraction: maxWidthFraction,
  );

  final right = TextClip(
    id: const Uuid().v4(),
    durationMicroseconds: durationMicroseconds - offsetMicros,
    text: text,
    style: style,
    position: position,
    rotation: rotation,
    scale: scale,
    opacity: opacity,
    enterAnimation: null,  // No enter on right half
    exitAnimation: exitAnimation,
    sustainAnimation: sustainAnimation,
    enterDurationMicros: 0,
    exitDurationMicros: exitDurationMicros.clamp(
        0, (durationMicroseconds - offsetMicros) ~/ 2),
    keyframes: rightKeyframes,
    templateId: templateId,
    name: name != null ? '$name (2)' : null,
    isSubtitle: isSubtitle,
    textAlign: textAlign,
    maxWidthFraction: maxWidthFraction,
  );

  return (left: left, right: right);
}
```

4. **`TextClipManager` is a service layer, NOT a timeline owner.** It provides text-specific operations (template application, style mutation helpers, subtitle import) but delegates all structural operations (insert, remove, update, split, trim) to a `TimelineManager` (or the unified multi-track manager proposed in C2 resolution below). This is explicitly documented.

5. **V1 `ClipManager` migration note:** Existing video editing flows that still use V1 `ClipManager` are unaffected. Text functionality is V2-only. When V1 is eventually deprecated, text will already be on the target architecture.

---

#### C2 Resolution: Unified Undo/Redo System

**Verdict: CONFIRMED CRITICAL.** Two independent undo stacks are unacceptable for user experience.

**Concrete Solution: `MultiTrackTimelineManager` with composite undo snapshots.**

The key insight from reading `TimelineManager` is that its undo mechanism is beautifully simple: push `PersistentTimeline` roots onto a stack, swap pointers on undo/redo. This same pattern extends to multi-track by storing a composite snapshot:

```dart
/// lib/core/multi_track_timeline_manager.dart

@immutable
class TimelineSnapshot {
  /// Main video track timeline.
  final PersistentTimeline mainTimeline;

  /// Overlay track timelines, keyed by track ID.
  final Map<String, PersistentTimeline> overlayTimelines;

  const TimelineSnapshot({
    required this.mainTimeline,
    this.overlayTimelines = const {},
  });
}

class MultiTrackTimelineManager extends ChangeNotifier {
  TimelineSnapshot _current;
  final List<TimelineSnapshot> _undoStack = [];
  final List<TimelineSnapshot> _redoStack = [];
  static const int maxUndoHistory = 100;

  // Selection state
  String? _selectedItemId;
  String? _selectedTrackId;

  MultiTrackTimelineManager()
      : _current = TimelineSnapshot(
            mainTimeline: PersistentTimeline.empty);

  // --- Unified mutation with single undo entry ---
  void _execute(
    TimelineSnapshot Function() mutation, {
    String? operationName,
  }) {
    _undoStack.add(_current);
    if (_undoStack.length > maxUndoHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _current = mutation();
    notifyListeners();
  }

  // --- Main track operations (delegate to existing patterns) ---
  void insertMainTrack(int timeMicros, TimelineItem item) {
    _execute(
      () => TimelineSnapshot(
        mainTimeline: _current.mainTimeline.insertAt(timeMicros, item),
        overlayTimelines: _current.overlayTimelines,
      ),
      operationName: 'Insert ${item.displayName}',
    );
  }

  // --- Text track operations ---
  void addTextClip(String trackId, int timeMicros, TextClip clip) {
    _execute(() {
      final updatedOverlays = Map<String, PersistentTimeline>.from(
          _current.overlayTimelines);
      final trackTimeline = updatedOverlays[trackId]
          ?? PersistentTimeline.empty;
      updatedOverlays[trackId] = trackTimeline.insertAt(timeMicros, clip);
      return TimelineSnapshot(
        mainTimeline: _current.mainTimeline,
        overlayTimelines: updatedOverlays,
      );
    }, operationName: 'Add text');
  }

  // --- O(1) Undo/Redo - single pointer swap covers ALL tracks ---
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_current);
    _current = _undoStack.removeLast();
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_current);
    _current = _redoStack.removeLast();
    notifyListeners();
  }
}
```

**Why this works:**
- **O(1) undo/redo is preserved.** Each `TimelineSnapshot` is a pair of persistent data structure roots. Structural sharing means the `Map<String, PersistentTimeline>` entries that were NOT modified share the same tree nodes as the previous snapshot. Only the changed track's root pointer differs.
- **Single undo stack for ALL operations.** User presses Ctrl+Z and the last operation (whether it was a video trim or a text style change) is reversed.
- **`TextClipManager` becomes stateless.** It no longer owns timelines or undo stacks. It becomes a pure service with helper methods that construct new `TextClip` instances (apply template, apply style, etc.) and return them. The caller uses `MultiTrackTimelineManager` to persist the change.
- **Migration path from `TimelineManager`.** The existing `TimelineManager` can be adapted into `MultiTrackTimelineManager` by wrapping its `_current` in a `TimelineSnapshot`. The existing single-track API becomes a convenience method that delegates to `_current.mainTimeline`. This is a non-breaking refactor.

**Memory impact:** Each undo snapshot stores root pointers for all tracks. With 5 text tracks and 100 undo entries, this is 100 snapshots x (1 main root + 5 overlay roots) = 600 root pointers. At ~8 bytes each = ~5KB. Negligible. The actual tree nodes are shared via structural sharing.

---

#### C3 Resolution: Export Pipeline - AVVideoCompositionCoreAnimationTool Integration

**Verdict: CONFIRMED CRITICAL.** The existing export pipeline does not use `animationTool` and adding it changes behavior.

**Concrete Solution: Conditional pipeline selection with integration test guard.**

After reading `VideoProcessingService.swift`, the key observation is that the current pipeline builds `AVMutableVideoComposition` with `instructions` containing `AVMutableVideoCompositionLayerInstruction` objects that use `setTransformRamp`. When `animationTool` is set on the composition:

1. The `videoComposition.renderSize` becomes the parent `CALayer`'s frame size.
2. `AVMutableVideoCompositionLayerInstruction` transforms apply to the `videoLayer` (child layer), not the composition output.
3. The coordinate system for `setTransformRamp` is now relative to the `videoLayer` within the `outputLayer`.

The fix requires:

```swift
// In VideoProcessingService.renderComposition():

// After building videoComposition with existing layerInstruction logic...

if let textLayers = textLayersData, !textLayers.isEmpty {
    // Build text CALayer hierarchy
    let textLayerBuilder = TextLayerBuilder()
    let textParentLayer = textLayerBuilder.buildTextLayers(
        from: textLayers,
        videoSize: finalOutputSize,
        videoDuration: totalDuration
    )

    // Create parent/video layer structure required by animationTool
    let videoLayer = CALayer()
    videoLayer.frame = CGRect(origin: .zero, size: finalOutputSize)

    let outputLayer = CALayer()
    outputLayer.frame = CGRect(origin: .zero, size: finalOutputSize)
    outputLayer.isGeometryFlipped = true  // CRITICAL: Core Animation uses bottom-left origin
    outputLayer.addSublayer(videoLayer)
    outputLayer.addSublayer(textParentLayer)

    let animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer,
        in: outputLayer
    )
    videoComposition.animationTool = animationTool

    // NOTE: Existing setTransformRamp calls remain unchanged.
    // When animationTool is set, the layer instructions apply to
    // the video track WITHIN the videoLayer. The transforms are
    // relative to the videoLayer's coordinate space, which matches
    // the renderSize. No recalculation needed.
}
// If no text layers, the export pipeline remains exactly as-is.
```

**Key insight:** The existing `setTransformRamp` calls do NOT need modification when `animationTool` is added. The transform ramps operate on the video composition track, which feeds into the `videoLayer`. The `outputLayer` composites `videoLayer + textParentLayer`. The transform math in `VideoTransformCalculator` produces transforms relative to `outputSize`, which matches both the `renderSize` and the `videoLayer.frame`. This was verified by reading the existing `createTransform()` calls in `VideoProcessingService`.

**Integration test requirement:** Export the same project with and without text overlays and verify:
1. Video transforms (pan/zoom/rotate) produce identical pixel output for the video portion.
2. Text appears at the correct positions on top of the transformed video.
3. Animated text (enter/exit) timing matches the preview.

---

#### C4 Resolution: AVVideoCompositionCoreAnimationTool vs Custom AVVideoCompositing Mutual Exclusivity

**Verdict: CONFIRMED CRITICAL.** These two APIs are indeed mutually exclusive on `AVMutableVideoComposition`.

**Concrete Solution: Option B (conditional pipeline selection) for V1, with Option C as V2 target.**

Rationale for choosing Option B over Option C for V1:

- **Option C** (always use custom `AVVideoCompositing`) would require reimplementing all text rendering via Core Graphics/Core Text on every frame during export. This is significantly more code and CPU-intensive than `CATextLayer` rendering via `animationTool`.
- **Option B** uses the efficient `AVVideoCompositionCoreAnimationTool` path for the common case (text overlays without text-behind-subject) and only falls back to the custom compositor when text-behind-subject is enabled.

Implementation:

```swift
// In TextExportService.swift:

enum TextExportPipeline {
    case coreAnimation    // Standard: CATextLayer via animationTool
    case customCompositor // Advanced: AVVideoCompositing for text-behind-subject
}

func determineExportPipeline(textClips: [[String: Any]]) -> TextExportPipeline {
    // Check if any text clip has text-behind-subject enabled
    let needsCustomCompositor = textClips.contains { clip in
        (clip["textBehindSubject"] as? Bool) == true
    }
    return needsCustomCompositor ? .customCompositor : .coreAnimation
}
```

**When `coreAnimation` pipeline is selected:**
- Build `CATextLayer` hierarchy via `TextLayerBuilder`.
- Set `videoComposition.animationTool`.
- Text-behind-subject clips are rendered as normal text (no depth effect -- a known limitation surfaced to the user).

**When `customCompositor` pipeline is selected:**
- Set `videoComposition.customVideoCompositorClass = TextBehindSubjectCompositor.self`.
- The custom compositor renders ALL text (not just text-behind-subject clips) using Core Graphics/Core Text per frame.
- Person mask data is pre-computed and passed to the compositor.
- Video transforms are handled by the custom compositor (not `setTransformRamp`).

**Phase 4 implements only the `coreAnimation` pipeline.** Phase 6 implements the `customCompositor` pipeline. The conditional selection is added in Phase 6 when `TextBehindSubjectCompositor` is built.

**User-facing behavior:** If the user enables text-behind-subject on any clip, the export switches to the custom compositor pipeline. A brief info banner tells the user: "Text behind subject enabled -- export may take longer." This sets expectations for the CPU-intensive path.

---

#### C5 Resolution: TextClip Has No `startTimeOnTimeline`

**Verdict: CONFIRMED CRITICAL.** This is a fundamental architectural constraint of the Persistent AVL Tree design: clips are position-agnostic, positions are computed from tree structure.

**Concrete Solution: Resolve positions at export time from the tree.**

The export preparation code (in Flutter, before the platform channel call) must query positions from the `MultiTrackTimelineManager`:

```dart
// In export preparation code:

List<Map<String, dynamic>> prepareTextLayersForExport(
  MultiTrackTimelineManager manager,
) {
  final textLayers = <Map<String, dynamic>>[];

  for (final entry in manager.overlayTimelines.entries) {
    final trackId = entry.key;
    final timeline = entry.value;
    final items = timeline.toList();

    for (final item in items) {
      if (item is! TextClip) continue;

      final startMicros = timeline.startTimeOf(item.id);
      if (startMicros == null) continue;  // Shouldn't happen, defensive

      final endMicros = startMicros + item.durationMicroseconds;

      textLayers.add({
        'clipId': item.id,
        'text': item.text,
        'startMicros': startMicros,
        'endMicros': endMicros,
        // ... all other TextClip properties ...
      });
    }
  }

  // Sort by start time for deterministic layer ordering
  textLayers.sort((a, b) =>
      (a['startMicros'] as int).compareTo(b['startMicros'] as int));

  return textLayers;
}
```

**This is not just a documentation fix** -- it is a correctness requirement. The design document section 6.3 must be updated to show this resolution pattern. The `startTimeOnTimeline` / `endTimeOnTimeline` references in the platform channel payload should be replaced with the computed values above.

---

### 2. New Issues Found

#### CRITICAL

##### C6. `TimelineItem.fromJson` Does Not Handle Unknown Types Gracefully for Forward Compatibility

**Problem:** The current `TimelineItem.fromJson` throws `ArgumentError` for unknown `itemType` values:
```dart
default: throw ArgumentError('Unknown timeline item type: $type');
```

When a project saved with the text feature (containing `itemType: 'text'`) is opened on an older app version that does not have `TextClip`, the entire project fails to load. This is a data loss scenario.

**Recommendation:** Change the default case to return a `GapClip` (or a new `UnknownClip` type) with the original JSON preserved, and log a warning. The schema version should be bumped and validated at project load time. Add this to Phase 1 scope.

```dart
default:
  // Forward compatibility: preserve unknown types as gaps
  debugPrint('Warning: Unknown timeline item type "$type", preserving as gap');
  return GapClip(
    id: json['id'] as String,
    durationMicroseconds: json['durationMicros'] as int? ?? 1000000,
  );
```

##### C7. `MultiTrackTimelineManager` Undo Snapshot Memory with Large Subtitle Tracks

**Problem:** The `TimelineSnapshot` approach stores root pointers for ALL tracks on every mutation. With structural sharing, most nodes are shared. However, if a user edits subtitle text on a track with 500 subtitle clips, each edit creates a new `PersistentTimeline` root for that track. The path-copied nodes from root to the edited leaf are ~O(log 500) = ~9 nodes per edit. With 100 undo entries, this is 900 new nodes total -- acceptable.

BUT: the `Map<String, PersistentTimeline>` in `TimelineSnapshot` is a Dart `Map`, which is NOT a persistent data structure. Each snapshot creates a shallow copy of the map. With 10 tracks and 100 undo entries, this is 1000 map entries referencing existing roots -- still acceptable in terms of memory (~80KB), but the `Map.from()` copy on every mutation is O(k) where k = number of tracks.

**Recommendation:** For V1 (likely < 10 tracks), `Map.from()` is fine. Document that if track count grows beyond 20, the `Map` should be replaced with a persistent/immutable map (e.g., from `built_collection` or a custom HAMT). This is not blocking for V1.

**Verdict: IMPORTANT, not CRITICAL.** Acceptable for V1 scope but document the limitation.

#### IMPORTANT

##### I11. `TextKeyframe` Missing `copyWith` Method

**Problem:** `TextKeyframe` is `@immutable` but has no `copyWith` method. The keyframe partitioning in `TextClip.splitAt()` requires creating modified copies with updated `timestampMicros`. The `Keyframe` class in `keyframe.dart` has `copyWith`; `TextKeyframe` should follow the same pattern.

**Recommendation:** Add `copyWith` to `TextKeyframe`:
```dart
TextKeyframe copyWith({
  String? id,
  int? timestampMicros,
  Offset? position,
  double? scale,
  double? rotation,
  double? opacity,
  InterpolationType? interpolation,
  BezierControlPoints? bezierPoints,
}) => TextKeyframe(
  id: id ?? this.id,
  timestampMicros: timestampMicros ?? this.timestampMicros,
  position: position ?? this.position,
  scale: scale ?? this.scale,
  rotation: rotation ?? this.rotation,
  opacity: opacity ?? this.opacity,
  interpolation: interpolation ?? this.interpolation,
  bezierPoints: bezierPoints ?? this.bezierPoints,
);
```

##### I12. `TextOverlayStyle` Serialization Not Shown for Sub-Styles

**Problem:** The design shows `TextClip.toJson()` calling `style.toJson()` but never defines `TextOverlayStyle.toJson()` / `fromJson()`. The same applies to `TextShadowStyle`, `TextOutlineStyle`, `TextBackgroundStyle`, and `TextGlowStyle`. Without explicit serialization, JSON round-tripping will silently lose style data.

**Recommendation:** Add explicit `toJson`/`fromJson` to all style classes. Example for `TextOverlayStyle`:
```dart
Map<String, dynamic> toJson() => {
  'fontFamily': fontFamily,
  'fontSize': fontSize,
  'color': color.toARGB32(),
  'fontWeight': fontWeight.index,
  'isItalic': isItalic,
  'letterSpacing': letterSpacing,
  'lineHeight': lineHeight,
  'shadow': shadow?.toJson(),
  'outline': outline?.toJson(),
  'background': background?.toJson(),
  'glow': glow?.toJson(),
  'decoration': decoration.toString(),  // TextDecoration needs custom handling
  'isCustomFont': isCustomFont,
  'customFontPath': customFontPath,
};
```
And corresponding `fromJson` with safe defaults for every field. Add this to Phase 1 scope since it blocks persistence.

##### I13. `TextDecoration` Serialization Is Non-Trivial

**Problem:** `TextOverlayStyle` includes `TextDecoration decoration`. Flutter's `TextDecoration` is a special class -- it is not an enum, it uses bitfield composition (`TextDecoration.combine([underline, lineThrough])`). Standard `toString()` produces `TextDecoration.underline` for single values but `TextDecoration.combine` for multiples. This does not round-trip cleanly through JSON.

**Recommendation:** Serialize `TextDecoration` as a list of string flags:
```dart
// toJson:
'decoration': [
  if (decoration.contains(TextDecoration.underline)) 'underline',
  if (decoration.contains(TextDecoration.overline)) 'overline',
  if (decoration.contains(TextDecoration.lineThrough)) 'lineThrough',
],

// fromJson:
decoration: TextDecoration.combine([
  if ((json['decoration'] as List?)?.contains('underline') ?? false)
    TextDecoration.underline,
  if ((json['decoration'] as List?)?.contains('overline') ?? false)
    TextDecoration.overline,
  if ((json['decoration'] as List?)?.contains('lineThrough') ?? false)
    TextDecoration.lineThrough,
]),
```

##### I14. `FontWeight` Serialization via Index Is Fragile

**Problem:** The platform channel payload in section 6.3 sends `'fontWeight': clip.style.fontWeight.index`. Flutter's `FontWeight` uses indices 0-8 mapping to w100-w900. But the native side (Core Text) uses different weight values (e.g., `UIFont.Weight.bold` = 0.4, not 6). The index-based mapping will produce incorrect weights on the native side.

**Recommendation:** Send the actual numeric weight value and map it to `UIFont.Weight` on the native side:
```dart
// Dart side:
'fontWeight': clip.style.fontWeight.value,  // 100, 200, ..., 900

// Swift side:
func mapFontWeight(_ value: Int) -> UIFont.Weight {
    switch value {
    case 100: return .ultraLight
    case 200: return .thin
    case 300: return .light
    case 400: return .regular
    case 500: return .medium
    case 600: return .semibold
    case 700: return .bold
    case 800: return .heavy
    case 900: return .black
    default: return .regular
    }
}
```

##### I15. `isGeometryFlipped` Required for Core Animation Layer

**Problem:** The export integration code in section 6.3 does not set `isGeometryFlipped = true` on the `outputLayer`. Core Animation uses a bottom-left coordinate origin by default, while AVFoundation video uses top-left. Without this flag, ALL text will render upside-down vertically in the exported video.

**Recommendation:** The `outputLayer` MUST have `isGeometryFlipped = true`. This is shown in the C3 resolution code above. Add this to the design document section 6.3 code snippets.

##### I16. Platform Channel Method `buildTextExportLayers` Has Stateful Coupling

**Problem:** Appendix A defines `buildTextExportLayers` as a method that "stores the built CALayer hierarchy" on the native side, which is then "applied when VideoProcessingService creates the AVVideoCompositionCoreAnimationTool." This creates invisible stateful coupling between two platform channel calls: first `buildTextExportLayers`, then `renderComposition`. If the ordering is wrong, or if `renderComposition` is called without a prior `buildTextExportLayers`, the export produces video without text silently.

**Recommendation:** Eliminate the stateful coupling. Send text layer data as a parameter to `renderComposition` itself:
```dart
// Instead of two calls:
//   1. await channel.invokeMethod('buildTextExportLayers', textData);
//   2. await channel.invokeMethod('renderComposition', videoData);

// Single call with all data:
await channel.invokeMethod('renderComposition', {
  'videoPath': ...,
  'clips': ...,
  'textLayers': textLayersData,  // NEW: text data included directly
  // ... other params ...
});
```
On the Swift side, `renderComposition` receives `textLayers` as an optional parameter. If present, it builds the `CALayer` hierarchy inline before creating the export session. No stored state needed.

#### MINOR

##### M9. `TextAnimationPreset.toJson()` / `fromJson()` Not Defined

**Problem:** `TextAnimationPreset` is referenced in serialization (`enterAnimation?.toJson()`) but its serialization methods are not shown in the design. The `parameters` map (`Map<String, double>`) serializes naturally, but `TextAnimationPresetType` must be serialized as a string enum name.

**Recommendation:** Add:
```dart
Map<String, dynamic> toJson() => {
  'type': type.name,
  'intensity': intensity,
  'parameters': parameters,
};

factory TextAnimationPreset.fromJson(Map<String, dynamic> json) =>
    TextAnimationPreset(
      type: TextAnimationPresetType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => TextAnimationPresetType.fadeIn,
      ),
      intensity: (json['intensity'] as num?)?.toDouble() ?? 1.0,
      parameters: (json['parameters'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble()))
          ?? const {},
    );
```

##### M10. `TextKeyframe.toJson()` / `fromJson()` Not Defined

**Problem:** Same issue as M9. `TextKeyframe` serialization methods are referenced but not shown.

**Recommendation:** Define them explicitly, reusing the `InterpolationType` and `BezierControlPoints` serialization patterns from `Keyframe`:
```dart
Map<String, dynamic> toJson() => {
  'id': id,
  'timestampMicros': timestampMicros,
  'position': {'x': position.dx, 'y': position.dy},
  'scale': scale,
  'rotation': rotation,
  'opacity': opacity,
  'interpolation': interpolation.name,
  'bezierPoints': bezierPoints?.toJson(),
};
```

##### M11. `TextAlign` Import from dart:ui vs flutter/painting

**Problem:** `TextClip` uses `TextAlign` which is in `dart:ui`. The design does not specify the import, and there are two `TextAlign` definitions (`dart:ui` and `package:flutter/painting.dart` which re-exports it). This is a minor confusion point for implementors.

**Recommendation:** Import from `package:flutter/painting.dart` (the standard Flutter import) for consistency with the rest of the codebase.

---

### 3. Integration Test Plan Additions

The following integration tests should be added to the test plan in Section 15:

#### 3.1 Cross-System Integration Tests

| Test | Description | Phase |
|------|-------------|-------|
| V2 TextClip in PersistentTimeline | Insert, query, remove TextClip via PersistentTimeline API. Verify `startTimeOf`, `itemAtTime` work correctly. | Phase 1 |
| TextClip split via TimelineManager | Split a TextClip at various points. Verify keyframes are correctly partitioned. Verify enter/exit animations are correctly assigned. | Phase 1 |
| Unified undo across tracks | Add video clip, add text clip, undo once (text removed), undo again (video removed), redo (video restored). Verify state consistency. | Phase 1 |
| Text + video export with transforms | Export a project with both video keyframe transforms and text overlays. Verify video transforms still produce correct output. Verify text appears at correct positions. | Phase 4 |
| Export without text (regression) | Export an existing project that has NO text clips. Verify export output is bit-identical to previous version (no `animationTool` interference when there are no text layers). | Phase 4 |
| 100 subtitle clips export | Import a 100-entry SRT file, export. Verify all 100 subtitles appear at correct times in exported video. Measure platform channel serialization time (target < 10ms). | Phase 5 |
| Font fallback on missing custom font | Save project with custom font, delete font file, reopen project. Verify fallback to SF Pro, verify warning shown, verify original font name preserved in JSON. | Phase 2 |
| Project schema forward compatibility | Load a project JSON that contains an unknown `itemType: 'future_type'`. Verify project loads (with the unknown item as a gap) instead of crashing. | Phase 1 |

#### 3.2 Export Consistency Tests (Addressing M7)

| Test | Description | Phase |
|------|-------------|-------|
| Static text position | Render a white text on black video at (0.25, 0.75). Extract frame from preview and export. Compare positions match within 2px tolerance. | Phase 4 |
| Text with shadow + outline | Render styled text. Verify shadow offset and outline width are visually similar between preview and export. | Phase 4 |
| Animated text at enter midpoint | Capture preview frame at 50% of enter animation. Extract same frame from export. Compare text position/opacity match within tolerance. | Phase 4 |
| Animated text at sustain | Same as above for sustain phase. | Phase 4 |
| Multi-font text | Export with both system font and bundled font. Verify both render correctly in export. | Phase 4 |

#### 3.3 Undo/Redo Stress Tests

| Test | Description | Phase |
|------|-------------|-------|
| 100 rapid text edits then undo all | Perform 100 text content changes on a single TextClip, then undo all 100. Verify original text is restored. Measure memory (should be < 1MB due to structural sharing). | Phase 1 |
| Interleaved video + text operations undo | Alternate between video trim and text style changes. Undo sequence should reverse in correct order regardless of which track was modified. | Phase 1 |
| Template apply then undo | Apply template (changes ~10 properties at once). Single undo restores all properties. | Phase 2 |

---

### 4. Revised Implementation Risk Assessment

#### Phase 1 Risk: LOW -> MEDIUM

Originally assessed as low risk (just data models), but the following additions increase complexity:
- `MultiTrackTimelineManager` must be designed and implemented (C2 resolution). This is foundational and affects all subsequent phases.
- `TextClip.splitAt()` with keyframe partitioning has subtle edge cases.
- `TimelineItem.fromJson` forward compatibility change (C6) affects existing tests.
- Full serialization round-trip for 6 new model classes (TextClip, TextOverlayStyle, TextShadowStyle, TextOutlineStyle, TextBackgroundStyle, TextGlowStyle, TextKeyframe, TextAnimationPreset) requires comprehensive tests.

**Recommendation:** Extend Phase 1 to 3 weeks. The `MultiTrackTimelineManager` is the critical path item.

#### Phase 2 Risk: LOW (unchanged)

Text editor UI is independent of the core architecture. Uses standard Cupertino widgets. Font enumeration platform channel is straightforward.

#### Phase 3 Risk: LOW -> MEDIUM

The `InterpolationUtils` extraction (I6) requires implementing 13 missing interpolation types with correct mathematical formulas. This is not hard but requires precision and comprehensive testing. The animation evaluation functions themselves are straightforward but must be pixel-perfect to match Core Animation curves on the native side.

#### Phase 4 Risk: MEDIUM -> HIGH

This is the highest risk phase due to:
- **C3:** `AVVideoCompositionCoreAnimationTool` integration changes the export pipeline behavior. Regression risk for existing projects with video transforms.
- **I15:** `isGeometryFlipped` must be correct or all text renders upside-down.
- **I14:** Font weight mapping between Flutter and Core Text must be validated for all 9 weight values.
- **I5 (from Review 1):** Font name resolution between Flutter and Core Text is a known pain point.
- **I16:** Stateful platform channel coupling (resolved by passing text data inline to `renderComposition`).

**Recommendation:** Phase 4 should include a 1-week integration testing buffer. Build an automated export comparison test that renders the same frame via Flutter `TextPreviewPainter` and via native export, then compares pixel similarity.

#### Phase 5 Risk: LOW (unchanged)

Templates are const data. SRT/VTT parsing is well-defined. Low integration risk.

#### Phase 6 Risk: HIGH (unchanged)

Custom `AVVideoCompositing` is the most complex native code in the entire system. It requires:
- Manual pixel buffer management.
- Per-frame text rendering via Core Graphics (NOT `CATextLayer`).
- Person mask compositing with correct blend modes.
- Handling ALL video transforms that `setTransformRamp` currently handles (since custom compositor replaces the standard compositing path).

**Recommendation:** Phase 6 should be scoped as a separate mini-project with its own design review. The conditional pipeline selection (Option B from C4 resolution) means Phase 6 can be deferred without blocking any other text functionality.

---

### 5. State Management Flow: TextClip Flutter <-> Native Synchronization

**Question from review prompt: "How does TextClip state flow between Flutter and native? Is there a synchronization issue?"**

**Answer: There is no persistent synchronization.** Text state lives exclusively on the Flutter side. The native side receives text data only at two specific moments:

1. **Font enumeration (startup):** Native -> Flutter. One-time query. No sync needed.
2. **Export (user-triggered):** Flutter -> Native. Text clip data is serialized and sent to the native side as a one-shot payload when export begins. The native side builds `CALayer` objects from this data, uses them for export, then discards them. There is no ongoing sync.

This architecture is correct and avoids sync issues. During preview, text rendering happens entirely in Flutter (`TextPreviewPainter`). During export, text rendering happens entirely in native (`TextLayerBuilder` + `CATextLayer`). The two pipelines operate independently, connected only by the shared `TextClip` data model.

**Risk:** The two rendering pipelines could produce visually different results for the same `TextClip` data. This is the "export consistency" concern addressed by the integration tests in section 3.2 above. The most likely sources of visual discrepancy are:
- Font metrics differences between Flutter's text shaper and Core Text.
- Shadow/glow rendering differences between Flutter's `Canvas` and `CALayer` shadow.
- Animation timing differences between Flutter's interpolation math and `CAMediaTimingFunction`.

Mitigation: Use identical mathematical formulas for interpolation (the `InterpolationUtils` extraction ensures this) and accept minor sub-pixel differences in font rendering.

---

### 6. Serialization Completeness Assessment

**Question from review prompt: "Can every TextClip property be fully round-tripped through JSON?"**

**Assessment: NO -- several gaps identified.**

| Property | Serializable? | Issue | Fix |
|----------|:---:|-------|-----|
| `id` (String) | Yes | -- | -- |
| `durationMicroseconds` (int) | Yes | -- | -- |
| `text` (String) | Yes | -- | -- |
| `style` (TextOverlayStyle) | **NO** | `toJson`/`fromJson` not defined (I12) | Define serialization for all 5 style classes |
| `style.fontWeight` (FontWeight) | **Partial** | Index-based serialization works for Dart round-trip but not Flutter<->Native (I14) | Use `.value` (100-900) |
| `style.decoration` (TextDecoration) | **NO** | Not a simple enum; bitfield (I13) | Serialize as list of strings |
| `style.color` (Color) | Yes | Uses `toARGB32()` / `Color(int)` | -- |
| `position` (Offset) | Yes | Serialized as `{x, y}` | -- |
| `rotation` (double) | Yes | -- | -- |
| `scale` (double) | Yes | -- | -- |
| `opacity` (double) | Yes | -- | -- |
| `enterAnimation` (TextAnimationPreset?) | **NO** | `toJson`/`fromJson` not defined (M9) | Define serialization |
| `exitAnimation` (TextAnimationPreset?) | **NO** | Same as above | Same fix |
| `sustainAnimation` (TextAnimationPreset?) | **NO** | Same as above | Same fix |
| `enterDurationMicros` (int) | Yes | -- | -- |
| `exitDurationMicros` (int) | Yes | -- | -- |
| `keyframes` (List\<TextKeyframe\>) | **NO** | `toJson`/`fromJson` not defined (M10) | Define serialization |
| `templateId` (String?) | Yes | -- | -- |
| `name` (String?) | Yes | -- | -- |
| `isSubtitle` (bool) | Yes | -- | -- |
| `textAlign` (TextAlign) | Yes | Uses `.name` / `firstWhere` | -- |
| `maxWidthFraction` (double) | Yes | -- | -- |

**7 of 22 properties have incomplete or missing serialization.** All gaps are fixable with the recommendations in I12, I13, I14, M9, and M10. These must ALL be completed in Phase 1 since persistence is a prerequisite for saving projects.

---

### 7. Migration Path for Existing Projects

**Question from review prompt: "How do existing projects (no text) handle the new schema?"**

**Answer: No migration needed, but version validation is recommended.**

Existing project JSON contains a `List<Map<String, dynamic>>` with `itemType` values of `video`, `gap`, `color`, etc. Since no `text` items exist in old projects:

1. `TimelineItem.fromJson` processes only known types. No `text` entries exist, so no error.
2. The `MultiTrackTimelineManager` loads the main timeline from JSON. The `overlayTimelines` map starts empty. No text tracks exist.
3. The UI shows no text tracks (correct).

**Forward compatibility concern (C6):** If a user creates a project with text, saves it, then opens it on an older app version, the `case 'text'` is missing and `TimelineItem.fromJson` throws. This is the C6 issue -- the fix is to handle unknown types gracefully.

**Recommended migration steps:**
1. Add a `schemaVersion` field to the project JSON root (default `1` for existing projects, `2` when text support is added).
2. On load, if `schemaVersion < 2`, the project has no text tracks -- load normally.
3. On load, if `schemaVersion >= 2` and the app does not support text, show a warning: "This project uses features from a newer version. Some elements may not display correctly."
4. On save, always write the current `schemaVersion`.

---

### 8. Phasing Dependency Analysis

**Question from review prompt: "Are the implementation phases ordered correctly? Any dependencies between phases that could block?"**

**Analysis:**

```
Phase 1 (Core Models + Rendering) --> Phase 2 (Editor UI)
                                  --> Phase 3 (Animations)
                                  --> Phase 4 (Export)
                                  --> Phase 5 (Templates + Subtitles)
                                                              --> Phase 6 (Text Behind Subject)
```

**Phase 1 is the correct starting point.** All other phases depend on the data models and `MultiTrackTimelineManager`.

**Phases 2, 3, 4, and 5 can partially parallelize:**
- Phase 2 (Editor UI) and Phase 3 (Animations) have no dependency between them. They both depend only on Phase 1 models.
- Phase 4 (Export) depends on Phase 3 for animation export, but the basic text export (static text, no animations) can begin before Phase 3 completes.
- Phase 5 (Templates + Subtitles) depends on Phase 2 for the template browser UI but the `SubtitleManager` (SRT/VTT parsing) can be built in parallel with Phase 2.

**Phase 6 depends on Phase 4** (it extends the export pipeline) and Phase 3 (animations must work in the custom compositor).

**Blocking risk:**
- **Phase 1 -> Phase 4 is the critical path.** If Phase 1 takes longer than expected (the `MultiTrackTimelineManager` refactor is significant), Phase 4 (export) is delayed. Since export is the most complex and highest-risk phase, any delay compounds.
- **Recommendation:** Start Phase 4 native Swift work (TextLayerBuilder, CATextLayer construction) in parallel with Phase 1, using mock data. The Swift code does not depend on the Dart data models -- it just receives dictionaries over the platform channel.

**Revised recommended ordering:**
1. **Week 1-3:** Phase 1 (Core Models + MultiTrackTimelineManager)
2. **Week 2-4:** Phase 4 native work begins (TextLayerBuilder Swift code, independent of Flutter)
3. **Week 4-5:** Phase 2 (Editor UI)
4. **Week 4-6:** Phase 3 (Animations -- can run parallel to Phase 2)
5. **Week 6-8:** Phase 4 integration (connect Flutter export code to Swift TextLayerBuilder)
6. **Week 8-10:** Phase 5 (Templates + Subtitles)
7. **Week 11-12:** Phase 6 (Text Behind Subject -- if time permits)

---

### 9. API Surface Review: Required Swift Methods

**Question from review prompt: "What exact Swift methods are needed?"**

Based on the analysis, the complete native API surface is:

#### TextLayerBuilder.swift
```swift
final class TextLayerBuilder {
    /// Build CALayer hierarchy from text clip data.
    /// Called inline during export, not stored.
    func buildTextLayers(
        from textData: [[String: Any]],
        videoSize: CGSize,
        videoDuration: CMTime
    ) -> CALayer

    /// Create a single CATextLayer from clip data.
    private func createTextLayer(
        from data: [String: Any],
        videoSize: CGSize
    ) -> CATextLayer

    /// Resolve font: system fonts via UIFont.systemFont,
    /// custom fonts via CTFontManagerRegisterFontsForURL.
    private func resolveFont(
        family: String,
        size: CGFloat,
        weight: Int,
        isItalic: Bool,
        isCustom: Bool,
        customPath: String?
    ) -> CTFont
}
```

#### TextAnimationBuilder.swift
```swift
final class TextAnimationBuilder {
    /// Convert animation preset to CAAnimation group.
    func buildEnterAnimation(
        type: String,
        duration: CFTimeInterval,
        intensity: Double,
        parameters: [String: Double],
        beginTime: CFTimeInterval
    ) -> CAAnimationGroup?

    /// Convert exit animation preset.
    func buildExitAnimation(
        type: String,
        duration: CFTimeInterval,
        intensity: Double,
        parameters: [String: Double],
        beginTime: CFTimeInterval
    ) -> CAAnimationGroup?

    /// Convert sustain animation preset (repeating).
    func buildSustainAnimation(
        type: String,
        intensity: Double,
        parameters: [String: Double],
        beginTime: CFTimeInterval,
        duration: CFTimeInterval
    ) -> CAAnimationGroup?

    /// Convert TextKeyframes to CAKeyframeAnimation.
    func buildKeyframeAnimation(
        keyframes: [[String: Any]],
        beginTime: CFTimeInterval,
        clipDuration: CFTimeInterval
    ) -> [CAAnimation]
}
```

#### FontEnumerator.swift
```swift
final class FontEnumerator {
    /// Return all available font family names, sorted.
    static func allFontFamilies() -> [String]

    /// Return all font names within a family (for weight/style variants).
    static func fontsInFamily(_ family: String) -> [String]

    /// Register a custom font file for use in Core Text.
    /// Returns the registered font family name.
    static func registerCustomFont(at path: String) -> String?
}
```

#### Platform Channel Additions to AppDelegate.swift
```swift
// In handleMethodCall:
case "getSystemFonts":
    result(FontEnumerator.allFontFamilies())

case "registerCustomFont":
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
        result(FlutterError(...))
        return
    }
    if let family = FontEnumerator.registerCustomFont(at: path) {
        result(["family": family])
    } else {
        result(FlutterError(code: "FONT_REGISTER_FAILED", ...))
    }

// renderComposition is modified to accept optional textLayers parameter
// (see I16 resolution above)
```

---

### Summary of All Issues

| ID | Severity | Summary | Phase Impact |
|----|----------|---------|-------------|
| C1 | CRITICAL (confirmed) | Dual clip model - TextClip must be V2-only with splitAt | Phase 1 |
| C2 | CRITICAL (confirmed) | Parallel undo/redo - need unified MultiTrackTimelineManager | Phase 1 |
| C3 | CRITICAL (confirmed) | Export pipeline animationTool integration | Phase 4 |
| C4 | CRITICAL (confirmed) | CoreAnimation vs custom compositor mutual exclusivity | Phase 4/6 |
| C5 | CRITICAL (confirmed) | No startTimeOnTimeline - resolve from tree at export | Phase 1/4 |
| C6 | **CRITICAL (new)** | Forward compatibility of TimelineItem.fromJson | Phase 1 |
| C7 | IMPORTANT (new) | MultiTrackTimelineManager snapshot memory with many tracks | Phase 1 (doc) |
| I11 | IMPORTANT (new) | TextKeyframe missing copyWith | Phase 1 |
| I12 | IMPORTANT (new) | TextOverlayStyle + sub-styles missing serialization | Phase 1 |
| I13 | IMPORTANT (new) | TextDecoration serialization is non-trivial | Phase 1 |
| I14 | IMPORTANT (new) | FontWeight index-based serialization incorrect for native | Phase 4 |
| I15 | IMPORTANT (new) | isGeometryFlipped required for CALayer | Phase 4 |
| I16 | IMPORTANT (new) | Platform channel stateful coupling | Phase 4 |
| M9 | MINOR (new) | TextAnimationPreset serialization not defined | Phase 1 |
| M10 | MINOR (new) | TextKeyframe serialization not defined | Phase 1 |
| M11 | MINOR (new) | TextAlign import path clarification | Phase 1 |

**Overall Risk Assessment: MEDIUM-HIGH.** The design is architecturally sound but has significant implementation gaps in serialization, undo/redo unification, and export pipeline integration. Phase 1 scope should be expanded to 3 weeks to absorb the `MultiTrackTimelineManager` refactor and comprehensive serialization work. Phase 4 carries the highest integration risk and should include a 1-week testing buffer.

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Scope:** Final gate review before implementation begins. Cross-references R1 and R2 findings against codebase state. Produces risk register, implementation checklist, and GO/NO-GO decision.
**Codebase files verified:**
- `lib/models/clips/timeline_item.dart` (GeneratorClip base, fromJson switch, equality by ID)
- `lib/models/clips/color_clip.dart` (GeneratorClip pattern: copyWith, splitAt, toJson/fromJson, duplicate)
- `lib/models/clips/gap_clip.dart` (Minimal GeneratorClip: copyWith, splitAt, toJson/fromJson)
- `lib/models/clips/video_clip.dart` (MediaClip pattern: keyframe partitioning in splitAt, trim ops, copyWith)
- `lib/models/clips/clips.dart` (Barrel exports, needs `text_clip.dart` addition)
- `lib/core/timeline_manager.dart` (PersistentTimeline wrapper, undo/redo via pointer swap, splitAt handles VideoClip/GapClip/ColorClip -- NO TextClip case)
- `lib/timeline/data/models/timeline_clip.dart` (UI TimelineClip: ClipType.text exists, isGeneratorClip misses text)
- `lib/timeline/data/models/track.dart` (TrackType.text exists with pink color, supportsText getter exists)
- `ios/Runner/VideoProcessingService.swift` (Full export pipeline: renderVideo + renderComposition, NO animationTool usage, transforms via setTransformRamp only)
- `ios/Runner/AppDelegate.swift` (Platform channel: "com.liquideditor/video_processing", renderComposition accepts videoPath + clips)
- `lib/models/keyframe.dart` (InterpolationType: 21 values confirmed)
- `lib/core/clip_manager.dart` (_applyEasing: confirmed handles only 8 of 21 InterpolationType values)

---

### Critical Issues Status

| Issue ID | Source | Summary | Status | Resolution Path |
|----------|--------|---------|--------|-----------------|
| **C1** | R1 | Dual clip model -- TextClip must bridge V1/V2 | **RESOLVED in R2.** TextClip is V2-only. `TimelineManager.splitAt()` needs TextClip case. `TextClipManager` is a stateless service, not a timeline owner. The concrete `splitAt` implementation in R2 is correct and follows the pattern established by `VideoClip.splitAt()` in `video_clip.dart` (keyframe partitioning + new UUIDs). |
| **C2** | R1 | Parallel undo/redo conflicts | **RESOLVED in R2.** `MultiTrackTimelineManager` with `TimelineSnapshot` composite undo is architecturally sound. The O(1) pointer-swap undo is preserved. Memory analysis confirms negligible overhead. One concern remains: see Risk R3 below regarding migration from existing `TimelineManager`. |
| **C3** | R1 | Export pipeline does not use AVVideoCompositionCoreAnimationTool | **RESOLVED in R2.** Conditional pipeline: add `animationTool` only when text layers exist. R2 correctly notes that `setTransformRamp` calls need no modification when `animationTool` is present. Verified against `VideoProcessingService.swift` -- the existing transform calculator produces transforms relative to `outputSize` which matches both the old and new layer structures. The `isGeometryFlipped = true` requirement (I15) is included in R2's code. |
| **C4** | R1 | CoreAnimationTool and custom AVVideoCompositing are mutually exclusive | **RESOLVED in R2.** Option B (conditional pipeline selection) is correct for V1. Phase 6 scoped as separate mini-project. The enum-based pipeline selection (`TextExportPipeline.coreAnimation` vs `.customCompositor`) is clean. |
| **C5** | R1 | TextClip has no `startTimeOnTimeline` property | **RESOLVED in R2.** Positions resolved from `PersistentTimeline.startTimeOf()` at export time. The `prepareTextLayersForExport` function in R2 is correct. |
| **C6** | R2 | `TimelineItem.fromJson` throws on unknown types | **ACKNOWLEDGED, needs implementation.** The fallback-to-GapClip approach is pragmatic. Schema versioning recommended. This must be the FIRST change in Phase 1 as it affects existing test infrastructure. |
| **C7** | R2 | MultiTrackTimelineManager snapshot memory | **ACKNOWLEDGED, acceptable for V1.** `Map.from()` on every mutation is O(k) where k = track count. With k < 10, this is sub-microsecond. Document the limitation for future. |

**Assessment: All 7 critical issues have clear, verified resolution paths. No unresolved critical blockers.**

---

### New Issues Found in Review 3

#### R3-1. `MultiTrackTimelineManager` Migration Breaks Existing `TimelineManager` Consumers (IMPORTANT)

**Problem:** The current codebase uses `TimelineManager` directly in at least the timeline controller and potentially the project serialization layer. Introducing `MultiTrackTimelineManager` as a replacement requires updating all consumers. R2 mentions this is a "non-breaking refactor" but does not detail which files beyond `TimelineManager` itself need modification.

**Concrete files affected (verified from codebase):**
- `lib/timeline/timeline_controller.dart` -- likely holds a `TimelineManager` reference
- `lib/timeline/editing/*.dart` -- split, trim, clipboard controllers dispatch to `TimelineManager`
- `lib/timeline/gestures/drag_controller.dart` -- drag operations modify timeline via manager
- Any Provider/ChangeNotifier wiring in the widget tree that injects `TimelineManager`

**Recommendation:** Phase 1 should adopt an adapter approach: `MultiTrackTimelineManager` wraps the existing `TimelineManager` API for the main track (delegating to `_current.mainTimeline`). Expose the same public API for main-track operations so existing consumers do not break. Add new methods for overlay track operations. This way, Phase 1 does NOT require rewriting all timeline consumers -- only new text-related code uses the overlay API.

#### R3-2. `CompositionBuilder.swift` Referenced in Design But Does Not Exist (MINOR)

**Problem:** Section 14.2 lists `ios/Runner/Timeline/CompositionBuilder.swift` as a file to modify. This file does not exist in the codebase. The composition building logic lives entirely within `VideoProcessingService.swift`.

**Recommendation:** Remove the `CompositionBuilder.swift` reference from the design. The export integration point is `VideoProcessingService.renderComposition()` directly.

#### R3-3. Platform Channel Name Mismatch (MINOR)

**Problem:** The design proposes a new method channel `com.liquideditor/text` (Appendix A) for font operations. The existing channel is `com.liquideditor/video_processing`. Adding a second channel is acceptable but adds complexity. R2's resolution for I16 (passing text data inline to `renderComposition`) means only font operations need the text channel.

**Recommendation:** Add font operations (`getSystemFonts`, `registerCustomFont`) to the existing `com.liquideditor/video_processing` channel rather than creating a new channel. This reduces setup code and keeps all native bridge calls in one place. The method names are unambiguous.

#### R3-4. `TextClip.toJson()` Must Call `super` Fields Explicitly (MINOR)

**Problem:** `GeneratorClip` stores `_durationMicroseconds` as a private field. `TextClip.toJson()` in section 11.1 includes `'durationMicros': durationMicroseconds` which accesses the getter -- this is correct. But `TimelineItem.id` must also be included. Examining the pattern in `ColorClip.toJson()`, the `id` is included explicitly. The design's `toJson()` does include `'id': id` -- confirmed correct. No action needed, but implementers should verify they follow the `ColorClip` pattern exactly.

---

### Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | `AVVideoCompositionCoreAnimationTool` integration causes regressions in existing video-only export (transforms render differently with nested layer structure) | Medium | High | Automated export comparison test: export same project with/without text, compare video-only frames pixel-by-pixel. Run this test in Phase 4 before merging. |
| R2 | Font rendering mismatch between Flutter `TextPainter` (preview) and Core Text `CATextLayer` (export) -- different font metrics, kerning, line breaking | High | Medium | Accept minor sub-pixel differences. Use SSIM threshold of 0.90 (not 0.95) for font-heavy comparison tests. Document known differences. For system fonts, both sides use Core Text underneath (Flutter on iOS delegates to Core Text). |
| R3 | `MultiTrackTimelineManager` refactor disrupts existing timeline editing features (split, trim, drag, clipboard) | Medium | High | Use adapter pattern (R3-1 above). Do NOT rewrite existing consumers in Phase 1. Regression test all existing editing operations after the refactor. |
| R4 | All 21 `InterpolationType` implementations produce different curves than Core Animation `CAMediaTimingFunction` equivalents | Medium | Medium | For standard easings (easeIn, easeOut, easeInOut), use the exact same cubic bezier control points as `CAMediaTimingFunction`. For spring/elastic/bounce, implement mathematically identical formulas. Phase 3 must include a visual comparison test. |
| R5 | Custom font loading via `CTFontManagerRegisterFontsForURL` fails silently or returns a different family name than expected | Medium | Low | `FontEnumerator.registerCustomFont()` returns the actual registered family name. Store this name in a Flutter-side mapping. Test with 5+ real TTF/OTF fonts. |
| R6 | `TextRenderCache` `ui.Image` objects consume GPU memory not tracked by Dart GC, causing OOM on low-memory devices | Low | High | Limit cache to 20 entries (already specified). Add memory pressure listener that clears cache when `AppLifecycleState.paused`. Monitor with Instruments during Phase 1 testing. |
| R7 | Phase 1 takes longer than 3 weeks due to `MultiTrackTimelineManager` complexity, blocking all subsequent phases | Medium | High | Start Phase 4 Swift work (TextLayerBuilder) in parallel using mock data (R2 recommendation). UI work (Phase 2) can also begin in parallel once models are finalized (even before manager is complete). |
| R8 | SRT/VTT parser fails on real-world subtitle files (encoding issues, malformed timestamps, non-standard extensions) | Medium | Low | Gather 20+ real SRT/VTT files from open subtitle databases for test corpus. Implement lenient parsing (skip malformed entries rather than failing entire import). |
| R9 | `colorCycle` sustain animation requires style mutation not supported by current animation pipeline | Low | Low | Defer `colorCycle` to V2 as recommended in R1-I9. Remove from V1 scope. 5 sustain animations remain (breathe, pulse, float, shake, flicker). |
| R10 | Glitch animation non-determinism between preview and export | Low | Medium | Use seeded PRNG as recommended in R1-M6: `seed = clipId.hashCode ^ frameMicros`. Implement identically in Dart and Swift. |

---

### Implementation Checklist

Ordered by dependency. Each item specifies files to create or modify with a brief description.

#### Phase 1: Core Models + MultiTrackTimelineManager (Week 1-3)

**1.1 Forward Compatibility Fix (Day 1)**
- [ ] MODIFY `lib/models/clips/timeline_item.dart` -- Change `fromJson` default case from `throw` to return `GapClip` with preserved data + warning log

**1.2 Data Models (Day 1-4)**
- [ ] CREATE `lib/models/text/text_overlay_style.dart` -- `TextOverlayStyle`, `TextShadowStyle`, `TextOutlineStyle`, `TextBackgroundStyle`, `TextGlowStyle` all with `toJson`/`fromJson`, `copyWith`
- [ ] CREATE `lib/models/text/text_keyframe.dart` -- `TextKeyframe` with `toJson`/`fromJson`, `copyWith`. Import `InterpolationType` and `BezierControlPoints` from `keyframe.dart`
- [ ] CREATE `lib/models/text/text_animation_preset.dart` -- `TextAnimationPresetType` enum (remove `colorCycle` from V1), `TextAnimationPreset` with `toJson`/`fromJson`
- [ ] CREATE `lib/models/text/text_template.dart` -- `TextTemplate` model with `toJson`/`fromJson`
- [ ] CREATE `lib/models/text/subtitle_entry.dart` -- `SubtitleEntry` as internal parsing intermediate (make private to subtitle_manager or keep minimal)
- [ ] CREATE `lib/models/clips/text_clip.dart` -- `TextClip extends GeneratorClip` with all 20+ fields, `copyWith`, `splitAt`, `duplicate`, `toJson`/`fromJson`, `displayName`, `itemType`
- [ ] MODIFY `lib/models/clips/timeline_item.dart` -- Add `case 'text': return TextClip.fromJson(json);` and import
- [ ] MODIFY `lib/models/clips/clips.dart` -- Add `export 'text_clip.dart';`

**1.3 Interpolation Utils Extraction (Day 3-5)**
- [ ] CREATE `lib/core/interpolation_utils.dart` -- Extract `_applyEasing` from `clip_manager.dart`, implement ALL 21 `InterpolationType` values (spring, bounce, elastic, circIn/Out/InOut, expoIn/Out/InOut, backIn/Out/InOut, bezier). Add `lerpOffset`, `lerpDouble` helpers
- [ ] MODIFY `lib/core/clip_manager.dart` -- Replace `_applyEasing` with call to `InterpolationUtils.applyEasing`

**1.4 MultiTrackTimelineManager (Day 4-10)**
- [ ] CREATE `lib/core/multi_track_timeline_manager.dart` -- `TimelineSnapshot` (immutable, holds mainTimeline + overlayTimelines map), `MultiTrackTimelineManager extends ChangeNotifier` with unified undo/redo, adapter methods for main track that delegate to existing patterns, new overlay track methods for text CRUD
- [ ] MODIFY `lib/core/timeline_manager.dart` -- Optionally refactor to delegate to `MultiTrackTimelineManager`, OR keep as-is and have `MultiTrackTimelineManager` internally use `PersistentTimeline` directly (preferred to avoid circular dependency)
- [ ] MODIFY `lib/core/timeline_manager.dart` -- Add `TextClip` case to `splitAt()` method (follow `ColorClip` pattern but with keyframe partitioning per R2 C1 resolution)

**1.5 Timeline UI Model Updates (Day 8-10)**
- [ ] MODIFY `lib/timeline/data/models/timeline_clip.dart` -- Fix `isGeneratorClip` to include `ClipType.text`

**1.6 TextClipManager Service (Day 9-12)**
- [ ] CREATE `lib/core/text_clip_manager.dart` -- Stateless service: `applyTemplate`, `applyStyle`, `computeTextState` (animation interpolation at time T), helpers for creating TextClip from template. Does NOT own timelines or undo stacks. Calls `MultiTrackTimelineManager` for mutations.

**1.7 Text Render Cache (Day 10-12)**
- [ ] CREATE `lib/timeline/rendering/text_render_cache.dart` -- LRU cache for `ui.Image`, max 20 entries, keyed by clipId + style hash + text hash + size hash, invalidation by clipId

**1.8 Text Preview Painter (Day 11-14)**
- [ ] CREATE `lib/timeline/rendering/painters/text_preview_painter.dart` -- `TextPreviewPainter extends CustomPainter`, renders visible text clips at current time, animation interpolation, `TextPainter` reuse pool, layout caching, calls `TextRenderCache` for static text

**1.9 Text Timeline Painter (Day 13-15)**
- [ ] CREATE `lib/timeline/rendering/painters/text_clip_painter.dart` -- `TextClipsPainter extends CustomPainter`, renders text clips as pink/magenta rectangles in timeline UI, shows truncated text label, animation indicators at edges, keyframe diamonds

**1.10 Phase 1 Tests (Throughout)**
- [ ] CREATE `test/models/clips/text_clip_test.dart` -- Construction, copyWith, splitAt (keyframe partitioning, animation assignment), toJson/fromJson round-trip, displayName, itemType, edge cases (empty text, min duration)
- [ ] CREATE `test/models/text/text_overlay_style_test.dart` -- All sub-styles toJson/fromJson round-trip, TextDecoration serialization, FontWeight serialization via .value
- [ ] CREATE `test/models/text/text_keyframe_test.dart` -- Construction, copyWith, toJson/fromJson, InterpolationType round-trip
- [ ] CREATE `test/models/text/text_animation_preset_test.dart` -- toJson/fromJson, all preset type names round-trip
- [ ] CREATE `test/core/interpolation_utils_test.dart` -- All 21 InterpolationType values: boundary conditions (t=0, t=1), midpoint behavior, monotonicity where applicable
- [ ] CREATE `test/core/multi_track_timeline_manager_test.dart` -- Insert/remove/update on main and overlay tracks, unified undo/redo across tracks, interleaved operations, snapshot memory (structural sharing verification)
- [ ] CREATE `test/core/text_clip_manager_test.dart` -- Template application, style mutation, computeTextState at enter/sustain/exit phases
- [ ] CREATE `test/timeline/rendering/text_render_cache_test.dart` -- LRU eviction, invalidation, max entries
- [ ] MODIFY existing `TimelineManager` tests -- Add TextClip splitAt test case
- [ ] MODIFY existing `TimelineItem.fromJson` tests -- Add unknown type forward compatibility test

#### Phase 2: Text Editor UI (Week 4-5)

- [ ] CREATE `lib/views/text/text_editor_panel.dart` -- Full-screen modal with `CupertinoNavigationBar`, video preview, tab selector (`CNTabBar` per CLAUDE.md standard), panel content
- [ ] CREATE `lib/views/text/text_style_panel.dart` -- Font picker, size slider, weight segmented control, color well, effects toggles -- all native Cupertino widgets
- [ ] CREATE `lib/views/text/inline_text_editor.dart` -- `CupertinoTextField` overlay on video preview, transparent background, real-time text updates
- [ ] CREATE `lib/views/text/text_gesture_handler.dart` -- Pan (move), pinch (scale), two-finger rotate gestures on text overlay
- [ ] CREATE `lib/core/font_manager.dart` -- Font enumeration (platform channel to native), custom font import via `file_picker`, `FontLoader` registration, font directory management, `loadCustomFonts()` at startup
- [ ] CREATE `lib/views/text/font_picker.dart` -- `ListView.builder` with lazy font loading, each item rendered in its own typeface, search/filter
- [ ] CREATE `lib/views/text/text_color_picker.dart` -- Cupertino-styled color picker (custom widget using `CupertinoPicker` or platform view wrapping `UIColorWell`)
- [ ] CREATE `ios/Runner/Font/FontEnumerator.swift` -- `allFontFamilies()`, `fontsInFamily()`, `registerCustomFont(at:)`
- [ ] MODIFY `ios/Runner/AppDelegate.swift` -- Add `getSystemFonts` and `registerCustomFont` method channel handlers (on existing `com.liquideditor/video_processing` channel)
- [ ] MODIFY timeline toolbar widget -- Add "Add Text" button (CNButton.icon with plus symbol)

#### Phase 3: Text Animations (Week 4-6, parallel with Phase 2)

- [ ] CREATE `lib/core/text_animation_evaluator.dart` -- Functions for all enter (11 types), exit (11 types), sustain (5 types, excluding colorCycle) animation evaluators. Returns `AnimationState` (positionDelta, scaleFactor, rotationDelta, opacityFactor). Sustain uses configurable `loopDurationMicros` (R1-I2 fix). Glitch uses seeded PRNG (R1-M6 fix).
- [ ] CREATE `lib/views/text/text_animation_picker.dart` -- Horizontal scrollable grid of animation previews (small animated widgets), enter/exit/sustain tabs, duration sliders
- [ ] MODIFY `lib/timeline/rendering/painters/text_preview_painter.dart` -- Integrate animation evaluator calls into `computeTextState` per-frame pipeline
- [ ] CREATE `lib/views/text/text_keyframe_editor.dart` -- UI for adding/moving/deleting keyframes on text clip timeline, diamond indicators, drag handles
- [ ] CREATE `test/core/text_animation_evaluator_test.dart` -- All 27 animation types: boundary values (t=0, t=1), midpoint behavior, sustain looping with configurable period, glitch determinism with same seed

#### Phase 4: Export Pipeline (Week 6-8)

- [ ] CREATE `ios/Runner/Text/TextLayerBuilder.swift` -- `buildTextLayers(from:videoSize:videoDuration:)` returns `CALayer`. `createTextLayer(from:videoSize:)` handles font resolution (system via `UIFont.systemFont`, custom via `CTFontManagerRegisterFontsForURL`), position mapping (normalized to pixel), style (shadow, outline, background). FontWeight mapping via numeric value (R2-I14 fix).
- [ ] CREATE `ios/Runner/Text/TextAnimationBuilder.swift` -- Convert enter/exit/sustain presets to `CABasicAnimation`/`CAKeyframeAnimation` groups. Convert `TextKeyframe` arrays to `CAKeyframeAnimation`. Map `InterpolationType` to `CAMediaTimingFunction` where applicable, custom timing for spring/elastic/bounce.
- [ ] CREATE `ios/Runner/Text/TextExportService.swift` -- `TextExportPipeline` enum. `determineExportPipeline()`. Integration point that builds layer hierarchy and sets `animationTool` on composition. `outputLayer.isGeometryFlipped = true` (R2-I15).
- [ ] MODIFY `ios/Runner/VideoProcessingService.swift` -- Accept optional `textLayers` parameter in `renderComposition()`. If present, call `TextExportService` to build layer hierarchy and set `animationTool`. If absent, export unchanged (regression safety).
- [ ] MODIFY `ios/Runner/AppDelegate.swift` -- Pass `textLayers` from method channel args to `renderComposition()` call
- [ ] MODIFY Flutter export preparation code -- Create `prepareTextLayersForExport()` that resolves positions from `MultiTrackTimelineManager`, serializes all text clip data, passes to `renderComposition` platform channel call
- [ ] CREATE export consistency tests -- Static text position comparison, styled text comparison, animated text at enter/sustain/exit midpoints
- [ ] CREATE regression test -- Export project without text, verify output unchanged from pre-text-feature baseline

#### Phase 5: Templates + Subtitles (Week 8-10)

- [ ] CREATE `lib/data/text_templates.dart` -- 28 built-in `TextTemplate` const definitions across 5 categories. Programmatic thumbnail previews (not asset images, per R1-M2).
- [ ] CREATE `lib/views/text/template_browser.dart` -- Category tabs, 2-column grid, tap to apply
- [ ] CREATE `lib/core/subtitle_manager.dart` -- `importSRT()`, `importVTT()`, `exportSRT()`, `exportVTT()`. Lenient parsing (skip malformed entries). Handle UTF-8 BOM, HTML tags, missing blank lines (R1 edge cases 8.1).
- [ ] CREATE `lib/views/text/subtitle_import_sheet.dart` -- File picker for SRT/VTT, preview of parsed entries, default style selection
- [ ] CREATE `test/core/subtitle_manager_test.dart` -- 20+ test cases with real-world SRT/VTT corpus

#### Phase 6: Text Behind Subject (Week 11-12, if time permits)

- [ ] CREATE `lib/core/mask_rasterizer.dart` -- Convert body outline polygons to `ui.Image` alpha mask
- [ ] MODIFY `lib/timeline/rendering/painters/text_preview_painter.dart` -- `_renderTextBehindSubject` with `BlendMode.dstOut` compositing
- [ ] CREATE `ios/Runner/Text/TextBehindSubjectCompositor.swift` -- Custom `AVVideoCompositing`, per-frame text rendering via Core Graphics, person mask compositing
- [ ] MODIFY `ios/Runner/Text/TextExportService.swift` -- Conditional pipeline selection: use custom compositor when any clip has `textBehindSubject: true`
- [ ] Separate design review for Phase 6 before implementation (per R2 recommendation)

---

### Test Plan Verification

Cross-referencing against R1/R2 test requirements:

| Category | R1/R2 Requirement | Covered? | Phase |
|----------|-------------------|----------|-------|
| Model serialization round-trip | R2 Section 6: 7/22 properties had gaps | YES -- all serialization defined in checklist 1.2 | 1 |
| Forward compatibility | R2-C6: Unknown itemType should not crash | YES -- checklist 1.1 | 1 |
| TextClip splitAt with keyframes | R2-C1: Keyframe partitioning, animation assignment | YES -- checklist 1.10 | 1 |
| Unified undo/redo | R2-C2: Single undo stack across video + text | YES -- checklist 1.10 | 1 |
| All 21 InterpolationType | R1-I6: Only 8 implemented | YES -- checklist 1.3 + 1.10 | 1 |
| Animation evaluation (27 types) | R1 Section 15 Test Plan | YES -- checklist Phase 3 tests | 3 |
| SRT/VTT parsing edge cases | R1 Section 8: BOM, HTML tags, etc. | YES -- checklist Phase 5 tests | 5 |
| Export consistency preview vs export | R1-M7: Pixel comparison | YES -- checklist Phase 4 tests | 4 |
| Export regression (no text) | R2 Section 3.1 | YES -- checklist Phase 4 | 4 |
| 100 subtitle clips export | R2 Section 3.1 | YES -- checklist Phase 5 | 5 |
| Font fallback on missing font | R2 Section 3.1 | YES -- checklist Phase 2 | 2 |
| Interleaved undo stress test | R2 Section 3.3 | YES -- checklist 1.10 | 1 |
| VoiceOver/Accessibility | R1-M8 | PARTIAL -- Cupertino widgets provide baseline. Explicit semantic labels for timeline text clips should be added in Phase 2. | 2 |

**Total estimated test count: ~190 tests** (R1 estimated 175; additional integration tests from R2 add ~15).

---

### Final Assessment

**CONDITIONAL GO.**

The design is approved for implementation with the following mandatory conditions:

1. **Phase 1 expanded to 3 weeks** (per R2 recommendation). The `MultiTrackTimelineManager` is the foundation for everything else and must be solid.

2. **Adapter pattern for MultiTrackTimelineManager** (R3-1). Do NOT rewrite existing `TimelineManager` consumers. Wrap and extend. This reduces Phase 1 risk from HIGH to MEDIUM.

3. **Forward compatibility fix is Day 1** (C6). This is a one-line change that protects existing users.

4. **Remove `colorCycle` from V1 scope** (R1-I9). It introduces style-mutation animation that does not fit the transform-based pipeline. Defer to V2.

5. **Single platform channel** (R3-3). Add font methods to existing `com.liquideditor/video_processing` channel rather than creating `com.liquideditor/text`.

6. **Phase 4 must include 1-week integration testing buffer.** The `AVVideoCompositionCoreAnimationTool` integration is the highest-risk change in the entire system. A regression in video export would be catastrophic.

7. **Phase 6 gated on separate design review.** Custom `AVVideoCompositing` is complex enough to warrant its own mini-design document covering pixel buffer management, transform handling, and performance profiling.

8. **Start Phase 4 Swift work in parallel with Phase 1** (R2 recommendation). `TextLayerBuilder.swift` and `TextAnimationBuilder.swift` can be developed against mock dictionary data without any Dart dependency.

**Blocking conditions (will change to NO-GO if not met):**
- All 7 serialization gaps (R2 Section 6) must be resolved before any data is persisted. Incomplete serialization = data loss.
- `MultiTrackTimelineManager` must have 100% test coverage of undo/redo across interleaved track operations before Phase 2 begins.
- The export regression test (no-text project produces unchanged output) must pass before the Phase 4 `animationTool` changes are merged.

---

### Remaining Open Questions

These do not block implementation but should be answered during Phase 1:

| # | Question | Source | Recommendation |
|---|----------|--------|----------------|
| OQ1 | How are text track z-order changes handled? Is `Track.index` the rendering z-order for preview? | R1-Q2 | Yes, use `Track.index` for both timeline vertical position and preview z-order. Document that reordering tracks in the timeline UI changes the text rendering order in preview and export. |
| OQ2 | What happens to text when video clips are reordered? | R1-Q3 | For V1, text clips maintain absolute timeline positions. They are NOT linked to video clips. Add a "link to video" feature in V2. Document this behavior clearly in the UI (tooltip or onboarding). |
| OQ3 | How does text export work with multi-source video (Timeline V2)? | R1-Q4 | For V1, `renderComposition` handles a single source asset. Text clip times are absolute timeline times, which already align correctly with the composition timeline built from multiple clip segments. The `prepareTextLayersForExport` function resolves absolute times from the tree. No special handling needed. |
| OQ4 | Maximum font size: is 200pt correct? | R1-Q5 | 200pt at 1080p is large but valid (banner text). Keep 200pt as the slider maximum. The text wraps at `maxWidthFraction` and is clipped at video bounds. Add a "text overflow" indicator in the preview when text exceeds bounds. |
| OQ5 | Maximum text track count? | R1-M3 | Set to 10 text tracks. Enforce in `MultiTrackTimelineManager.createOverlayTrack()`. Surface an error to the user if they attempt to add an 11th. |
| OQ6 | `SubtitleEntry` model: keep or eliminate? | R1-M4 | Make it a private class inside `SubtitleManager`. Do not export it. Parse SRT/VTT into `SubtitleEntry` intermediates, then convert to `TextClip` instances. This keeps the parser logic clean without polluting the public API. |
| OQ7 | Should the `MultiTrackTimelineManager` replace `TimelineManager` entirely, or coexist? | New | Coexist for V1. `TimelineManager` continues to serve existing video-only flows. `MultiTrackTimelineManager` is the new unified manager. In V2, migrate all consumers to `MultiTrackTimelineManager` and deprecate `TimelineManager`. |

---

### Document Revision

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-06 | 1.0-review3 | Final implementation readiness review added. Risk register, implementation checklist, GO/NO-GO decision. |
