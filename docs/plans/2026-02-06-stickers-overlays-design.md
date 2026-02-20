# Stickers & Overlays System - Design Document

**Author:** Development Team
**Date:** 2026-02-06
**Status:** Draft - Pending Review
**Related:** [Text & Titles System](2026-02-06-text-titles-system-design.md), [Timeline Architecture V2](2026-01-30-timeline-architecture-v2-design.md), [DESIGN.md](../DESIGN.md)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Architecture Design](#3-architecture-design)
4. [Data Models](#4-data-models)
5. [Sticker Library](#5-sticker-library)
6. [Animated Stickers](#6-animated-stickers)
7. [Gesture Handling](#7-gesture-handling)
8. [Keyframe Animations](#8-keyframe-animations)
9. [Timeline Integration](#9-timeline-integration)
10. [Preview Rendering](#10-preview-rendering)
11. [Export Pipeline](#11-export-pipeline)
12. [UI Design](#12-ui-design)
13. [Edge Cases](#13-edge-cases)
14. [Performance](#14-performance)
15. [Testing Strategy](#15-testing-strategy)
16. [Implementation Plan](#16-implementation-plan)

---

## 1. Overview

### Purpose

The Stickers & Overlays System adds the ability to place static and animated visual elements on top of video content. Stickers include bundled emoji, shapes, icons, animated Lottie/GIF elements, and user-imported PNG images with transparency. Each sticker can be positioned, scaled, rotated, and animated using the existing keyframe system, giving users expressive compositing tools that feel native to iOS.

### Goals

- **Rich visual library:** Bundled stickers organized by categories with search and favorites, providing a polished out-of-the-box experience comparable to native iOS apps like iMessage and Clips.
- **Animated sticker support:** Lottie and GIF stickers rendered smoothly during preview and baked accurately into exported video.
- **Gesture-first interaction:** Drag, pinch, and rotate stickers directly on the video preview with haptic feedback and snap guides, matching the interaction model established by TextClip.
- **Timeline-native:** Sticker clips are first-class timeline citizens, supporting trim, split, move, copy, delete, and duration control through the existing Persistent AVL tree.
- **Keyframe animation:** Full keyframe-based animation of position, scale, rotation, and opacity using the existing `InterpolationType` system (21 easing types).
- **Export-accurate:** Stickers rendered during preview must match the exported video pixel-for-pixel, using a dual pipeline (Flutter for preview, Core Animation for export).
- **Performance-safe:** Sticker rendering during playback must stay within a 3ms per-frame budget for up to 8 simultaneous stickers to maintain 60 FPS.

### Non-Goals (Out of Scope for V1)

- 3D sticker transforms (perspective, depth, parallax).
- Sticker packs purchased via In-App Purchase (marketplace integration).
- Video stickers (stickers that are themselves video clips).
- AI-generated stickers (text-to-sticker generation).
- Sticker physics or collision detection.
- User drawing/painting overlay tools (freehand annotation).
- Sticker-to-sticker parent-child attachment (grouping stickers).

---

## 2. Current State Analysis

### Existing Overlay Infrastructure

The codebase already has significant overlay infrastructure established by the Text & Titles system:

| Component | Status | Relevance to Stickers |
|-----------|--------|----------------------|
| `GeneratorClip` base class | Implemented | `StickerClip` will extend this, same pattern as `TextClip` and `ColorClip` |
| `TimelineItem.fromJson` dispatch | Implemented | Needs new `case 'sticker'` entry |
| `TrackType` enum | Implemented | Needs new `sticker` track type (or reuse `overlayVideo`) |
| `Track` model | Implemented | Works as-is for sticker tracks |
| `PersistentTimeline` | Implemented | Fully generic over `TimelineItem`, works with `StickerClip` |
| `TimelineManager` | Implemented | O(1) undo/redo, works with any `TimelineItem` subclass |
| `InterpolationType` enum | Implemented | 21 easing types, reused for sticker keyframes |
| `BezierControlPoints` | Implemented | Custom bezier curves, reused for sticker keyframes |
| `TextClipManager` pattern | Designed | `StickerClipManager` follows identical overlay track management pattern |
| `TextPreviewPainter` pattern | Designed | `StickerPreviewPainter` follows same `CustomPainter` overlay approach |
| `TextLayerBuilder` (Swift) | Designed | `StickerLayerBuilder` follows same `CALayer` export approach |
| `AVVideoCompositionCoreAnimationTool` | In export pipeline | Same compositing mechanism for sticker layers |
| `CompositionBuilder` | Implemented | Multi-segment composition building, needs sticker layer integration |
| `VideoProcessingService` | Implemented | Export orchestration, needs sticker data channel |

### What Needs to Be Built

| Component | Description |
|-----------|-------------|
| `StickerClip` model | New `GeneratorClip` subclass for sticker data |
| `StickerAsset` model | Metadata for individual sticker assets (bundled + imported) |
| `StickerCategory` model | Category grouping with icons and ordering |
| `StickerKeyframe` model | Position/scale/rotation/opacity keyframes (mirrors `TextKeyframe`) |
| `StickerClipManager` | CRUD operations, overlay track management, undo/redo |
| `StickerPreviewPainter` | Flutter `CustomPainter` for rendering stickers over video |
| `StickerBrowserView` | iOS 26 Liquid Glass sticker picker UI with categories, search, favorites |
| `StickerEditorPanel` | Inspector panel for selected sticker (opacity, keyframes, duration) |
| `StickerLayerBuilder` (Swift) | Converts `StickerClip` data to `CALayer` for export |
| `StickerExportService` (Swift) | Integrates sticker layers with `AVVideoCompositionCoreAnimationTool` |
| `StickerFavoritesManager` | Persistence for user favorites |
| `LottieExportRenderer` (Swift) | Bakes Lottie animations to `CALayer` keyframe sequences for export |
| Bundled sticker assets | PNG/Lottie/GIF files organized by category |

### Architectural Alignment with TextClip

The sticker system is architecturally parallel to the text system. This is intentional: both are overlay clips that generate visual content without referencing external video media, both live on dedicated overlay tracks, both support keyframe animation, and both use the same dual rendering pipeline (Flutter preview + Core Animation export). By following the same patterns, we minimize architectural divergence and ensure the systems can share infrastructure (e.g., `InterpolationUtils`, overlay track management, gesture handling).

---

## 3. Architecture Design

### 3.1 Rendering Strategy: Dual Pipeline

Sticker rendering follows the same split architecture as text:

| Context | Renderer | Technology | Frame Budget |
|---------|----------|-----------|-------------|
| **Preview** (playback + scrub) | Flutter side | `CustomPainter` + `Canvas.drawImage` / Lottie widget | < 3ms per sticker clip |
| **Export** | Native side | `CALayer` + `CAAnimation` via `AVVideoCompositionCoreAnimationTool` | N/A (offline) |

**Why dual pipeline?**
- Preview requires Flutter-side rendering because the video is displayed in a Flutter widget; overlaying stickers requires compositing within the Flutter render tree.
- Export requires native `CALayer` objects because `AVAssetExportSession` composites layers via `AVVideoCompositionCoreAnimationTool` at the AVFoundation level.

### 3.2 High-Level Architecture

```
Flutter Layer                              Native Layer (Swift)
-----------                              -------------------

StickerBrowserView                       StickerLayerBuilder
  |                                        |
  v                                        v
StickerClipManager ----[Platform Channel]-> StickerExportService
  |                                        |
  v                                        v
StickerPreviewPainter                    AVVideoCompositionCoreAnimationTool
  |                                        |
  v                                        v
VideoPreviewStack                        AVAssetWriter / AVAssetExportSession
```

### 3.3 Component Responsibilities

| Component | Layer | Purpose |
|-----------|-------|---------|
| `StickerClipManager` | Dart / `lib/core/` | CRUD operations on StickerClips. Manages sticker clip state across overlay tracks. Exposes sticker data to both the preview painter and export pipeline. |
| `StickerPreviewPainter` | Dart / `lib/timeline/rendering/` | `CustomPainter` that renders all visible sticker clips at the current playhead position. Handles static image rendering, animated sticker frame selection, keyframe interpolation, and compositing order. |
| `StickerBrowserView` | Dart / `lib/views/sticker/` | Full sticker picker UI with categories, search, favorites. Uses iOS 26 Liquid Glass design exclusively (CNTabBar for categories, CupertinoSearchTextField for search). |
| `StickerEditorPanel` | Dart / `lib/views/sticker/` | Inspector for selected sticker. Controls opacity, flip, keyframe management, duration. Uses Cupertino widgets. |
| `StickerTimelinePainter` | Dart / `lib/timeline/rendering/painters/` | Renders sticker clips as timeline track items. Shows sticker thumbnail inside the clip rectangle. |
| `StickerLayerBuilder` | Swift / `ios/Runner/Sticker/` | Converts `StickerClip` data to `CALayer` with `CAAnimation` for export. Handles static images, Lottie baking, and GIF frame sequences. |
| `StickerExportService` | Swift / `ios/Runner/Sticker/` | Integrates `StickerLayerBuilder` output with `AVVideoCompositionCoreAnimationTool` during export. |
| `StickerFavoritesManager` | Dart / `lib/core/` | Persists favorite sticker asset IDs to local storage. |
| `StickerAssetRegistry` | Dart / `lib/data/` | Registry of all available sticker assets (bundled + imported), organized by category. |

### 3.4 Sticker Clips on the Timeline

Sticker clips live on dedicated sticker/overlay tracks. Multiple sticker tracks can exist, allowing overlapping stickers at the same time. Track index determines z-order (higher index = rendered on top).

```
Track Layout:
  [Main Video Track]  [==== Video Clip A ====][==== Video Clip B ====]
  [Text Track 1]           [== Title ==]
  [Sticker Track 1]   [= Star =]   [= Arrow =]
  [Sticker Track 2]        [==== Animated Logo ====]
```

### 3.5 Integration with Existing Systems

The sticker system integrates with existing components at these points:

1. **TimelineItem hierarchy:** `StickerClip extends GeneratorClip` - plug into existing tree, serialization, and undo/redo.
2. **Keyframe system:** Reuse `InterpolationType`, `BezierControlPoints`, and `InterpolationUtils` for sticker animation.
3. **Gesture system:** Extend the preview overlay gesture handling to support sticker drag/pinch/rotate (same approach as TextClip gestures).
4. **Export pipeline:** Add sticker layers alongside text layers in the `CALayer` hierarchy attached to `AVVideoCompositionCoreAnimationTool`.
5. **Track system:** Add `TrackType.sticker` for dedicated sticker tracks with an orange/yellow default color.
6. **Design system:** All UI uses `CNTabBar`, `CNButton.icon`, `CupertinoSearchTextField`, `CupertinoSlider`, and standard Liquid Glass styling.

---

## 4. Data Models

### 4.1 StickerClip (New TimelineItem Subclass)

`StickerClip` extends `GeneratorClip` (same pattern as `ColorClip` and `TextClip`) because stickers generate visual content without referencing an external video media file. (Note: static image stickers reference a sticker asset file, but this is distinct from a `MediaAsset` video source.)

```dart
/// lib/models/clips/sticker_clip.dart

@immutable
class StickerClip extends GeneratorClip {
  /// Reference to the sticker asset (by asset ID).
  /// This identifies which sticker image/animation to render.
  final String stickerAssetId;

  /// Position of the sticker center on the video canvas.
  /// Normalized coordinates (0.0-1.0) where (0.5, 0.5) is center.
  final Offset position;

  /// Rotation angle in radians.
  final double rotation;

  /// Scale factor (1.0 = default sticker size).
  /// Default size is determined by the sticker asset's intrinsic size
  /// relative to a 1080p reference canvas.
  final double scale;

  /// Opacity (0.0-1.0).
  final double opacity;

  /// Whether the sticker is horizontally flipped.
  final bool isFlippedHorizontally;

  /// Whether the sticker is vertically flipped.
  final bool isFlippedVertically;

  /// Keyframes for custom property animation.
  /// Timestamps are relative to clip start.
  final List<StickerKeyframe> keyframes;

  /// Optional display name override.
  final String? name;

  /// Tint color applied as a color multiply on the sticker.
  /// Null means no tint (render as-is).
  final int? tintColorValue;

  /// For animated stickers (Lottie/GIF): playback speed multiplier.
  /// 1.0 = normal speed, 0.5 = half speed, 2.0 = double speed.
  /// Ignored for static stickers.
  final double animationSpeed;

  /// For animated stickers: whether animation loops.
  /// If false, the animation plays once and holds the last frame.
  final bool animationLoops;

  const StickerClip({
    required super.id,
    required super.durationMicroseconds,
    required this.stickerAssetId,
    this.position = const Offset(0.5, 0.5),
    this.rotation = 0.0,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.isFlippedHorizontally = false,
    this.isFlippedVertically = false,
    this.keyframes = const [],
    this.name,
    this.tintColorValue,
    this.animationSpeed = 1.0,
    this.animationLoops = true,
  });

  @override
  String get displayName => name ?? 'Sticker';

  @override
  String get itemType => 'sticker';

  /// Whether this sticker references an animated asset (Lottie or GIF).
  /// Determined at runtime by looking up the StickerAsset.
  bool get hasKeyframes => keyframes.isNotEmpty;
}
```

**Registration in `TimelineItem.fromJson`:**

```dart
static TimelineItem fromJson(Map<String, dynamic> json) {
  final type = json['itemType'] as String;
  switch (type) {
    case 'video':   return VideoClip.fromJson(json);
    case 'image':   return ImageClip.fromJson(json);
    case 'audio':   return AudioClip.fromJson(json);
    case 'gap':     return GapClip.fromJson(json);
    case 'color':   return ColorClip.fromJson(json);
    case 'text':    return TextClip.fromJson(json);
    case 'sticker': return StickerClip.fromJson(json);  // <--- NEW
    default:
      debugPrint('Warning: Unknown timeline item type "$type", preserving as gap');
      return GapClip(
        id: json['id'] as String? ?? 'unknown',
        durationMicroseconds: json['durationMicros'] as int? ?? 1000000,
      );
  }
}
```

**Registration in TrackType:** Add a new enum value:

```dart
enum TrackType {
  mainVideo,
  overlayVideo,
  audio,
  music,
  voiceover,
  effect,
  text,
  sticker,  // <--- NEW
}
```

With extension:

```dart
case TrackType.sticker:
  return const Color(0xFFFF9F0A); // iOS system orange
```

### 4.2 StickerAsset

Represents metadata about a single sticker resource (bundled or imported).

```dart
/// lib/models/sticker/sticker_asset.dart

enum StickerAssetType {
  /// Static raster image (PNG with transparency).
  staticImage,

  /// Animated Lottie JSON file.
  lottie,

  /// Animated GIF.
  gif,

  /// SVG vector image.
  svg,
}

@immutable
class StickerAsset {
  /// Unique identifier for this sticker asset.
  final String id;

  /// Display name (e.g., "Star", "Heart", "Fire").
  final String name;

  /// Asset type.
  final StickerAssetType type;

  /// Category ID this sticker belongs to.
  final String categoryId;

  /// Path to the asset file.
  /// For bundled: relative to assets/stickers/ (e.g., "emoji/star.png").
  /// For imported: absolute path in app's documents directory.
  final String assetPath;

  /// Whether this is a bundled (built-in) sticker.
  final bool isBuiltIn;

  /// Intrinsic width at 1080p reference resolution (logical pixels).
  /// Used to calculate default scale.
  final double intrinsicWidth;

  /// Intrinsic height at 1080p reference resolution (logical pixels).
  final double intrinsicHeight;

  /// For animated stickers: total animation duration in milliseconds.
  /// Null for static stickers.
  final int? animationDurationMs;

  /// For animated stickers: number of frames.
  /// Null for static stickers.
  final int? frameCount;

  /// Search keywords for this sticker.
  final List<String> keywords;

  /// Preview thumbnail path (smaller version for browser grid).
  final String? thumbnailPath;

  const StickerAsset({
    required this.id,
    required this.name,
    required this.type,
    required this.categoryId,
    required this.assetPath,
    this.isBuiltIn = true,
    this.intrinsicWidth = 120.0,
    this.intrinsicHeight = 120.0,
    this.animationDurationMs,
    this.frameCount,
    this.keywords = const [],
    this.thumbnailPath,
  });

  /// Whether this is an animated sticker.
  bool get isAnimated =>
      type == StickerAssetType.lottie || type == StickerAssetType.gif;
}
```

### 4.3 StickerCategory

```dart
/// lib/models/sticker/sticker_category.dart

@immutable
class StickerCategory {
  /// Unique identifier.
  final String id;

  /// Display name (e.g., "Emoji", "Shapes", "Arrows", "Decorative").
  final String name;

  /// SF Symbol icon name for the category tab.
  final String iconName;

  /// Sort order in the category tab bar.
  final int sortOrder;

  /// Whether this is a built-in category (not deletable).
  final bool isBuiltIn;

  const StickerCategory({
    required this.id,
    required this.name,
    required this.iconName,
    this.sortOrder = 0,
    this.isBuiltIn = true,
  });
}
```

**Built-in categories:**

| Category | SF Symbol | Contents |
|----------|-----------|----------|
| Favorites | `heart.fill` | User-favorited stickers across all categories |
| Emoji | `face.smiling` | Emoji-style stickers (smileys, people, gestures) |
| Shapes | `square.on.circle` | Geometric shapes (circles, stars, arrows, badges) |
| Icons | `sparkles` | Decorative icons (checkmarks, stars, crowns, ribbons) |
| Animated | `play.circle` | Lottie/GIF animated stickers |
| Decorative | `wand.and.stars` | Borders, frames, flourishes, dividers |
| Social | `bubble.left.fill` | Speech bubbles, hashtags, social media icons |
| Imported | `square.and.arrow.down` | User-imported PNG overlays |

### 4.4 StickerKeyframe

Mirrors `TextKeyframe` from the text system. Stores sticker-specific animatable properties.

```dart
/// lib/models/sticker/sticker_keyframe.dart

@immutable
class StickerKeyframe {
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

  const StickerKeyframe({
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

**Why a separate type from `TextKeyframe`?**

While `StickerKeyframe` and `TextKeyframe` have identical fields, they serve semantically different overlay types. Keeping them separate enables future divergence (e.g., sticker-specific properties like tint color animation, flip state animation, or animation playback offset). If the two never diverge, they could be refactored into a shared `OverlayKeyframe` base type in a future cleanup pass.

**Shared interpolation infrastructure:** Both `StickerKeyframe` and `TextKeyframe` reuse `InterpolationType` and `BezierControlPoints` from `keyframe.dart`, and share the `InterpolationUtils` helper class for easing math. No interpolation logic is duplicated.

### 4.5 Integration with Existing Clip Type Hierarchy

The `StickerClip` joins the existing hierarchy:

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
      |-- TextClip
      |-- StickerClip  <--- NEW
```

---

## 5. Sticker Library

### 5.1 Bundled Sticker Assets

The app ships with a curated library of stickers organized under `assets/stickers/`:

```
assets/
  stickers/
    emoji/
      star.png
      heart.png
      fire.png
      thumbs_up.png
      lightning.png
      sparkle.png
      ...
    shapes/
      circle.png
      rounded_rect.png
      star_shape.png
      arrow_right.png
      arrow_curved.png
      badge_ribbon.png
      ...
    icons/
      checkmark_circle.png
      crown.png
      trophy.png
      ribbon.png
      music_note.png
      camera.png
      ...
    animated/
      confetti.json          (Lottie)
      fireworks.json         (Lottie)
      sparkle_burst.json     (Lottie)
      thumbs_up_anim.json    (Lottie)
      loading_spinner.json   (Lottie)
      heart_beat.json        (Lottie)
      ...
    decorative/
      frame_vintage.png
      border_ornate.png
      divider_flourish.png
      corner_decoration.png
      ...
    social/
      speech_bubble.png
      thought_bubble.png
      hashtag.png
      at_symbol.png
      ...
    thumbnails/               (Pre-generated 64x64 thumbnails for browser)
      emoji/
      shapes/
      icons/
      animated/
      decorative/
      social/
```

**Asset specifications:**

| Property | Static (PNG) | Animated (Lottie) | Animated (GIF) |
|----------|-------------|-------------------|-----------------|
| Format | PNG with alpha | Lottie JSON | GIF |
| Reference size | 256x256 px | 256x256 px canvas | 256x256 px |
| Max file size | 100 KB | 200 KB | 500 KB |
| Color profile | sRGB | N/A | sRGB |
| Thumbnail | 64x64 PNG | 64x64 PNG (first frame) | 64x64 PNG (first frame) |

### 5.2 Sticker Asset Registry

All available stickers are cataloged in a registry:

```dart
/// lib/data/sticker_registry.dart

class StickerAssetRegistry {
  /// All available sticker categories.
  final List<StickerCategory> categories;

  /// All sticker assets indexed by ID.
  final Map<String, StickerAsset> _assetsById;

  /// Assets indexed by category ID.
  final Map<String, List<StickerAsset>> _assetsByCategory;

  /// Built-in categories and assets (loaded at startup).
  static StickerAssetRegistry loadBuiltIn();

  /// Add user-imported sticker.
  StickerAssetRegistry withImportedSticker(StickerAsset asset);

  /// Remove user-imported sticker.
  StickerAssetRegistry withoutSticker(String assetId);

  /// Search stickers by keyword (searches name + keywords list).
  List<StickerAsset> search(String query);

  /// Get all stickers in a category.
  List<StickerAsset> stickersInCategory(String categoryId);

  /// Get sticker by ID.
  StickerAsset? getById(String id);
}
```

### 5.3 Search

Sticker search operates over the `name` and `keywords` fields of each `StickerAsset`:

```dart
List<StickerAsset> search(String query) {
  if (query.isEmpty) return [];

  final lowerQuery = query.toLowerCase();
  final results = <StickerAsset>[];

  for (final asset in _assetsById.values) {
    if (asset.name.toLowerCase().contains(lowerQuery)) {
      results.add(asset);
      continue;
    }
    for (final keyword in asset.keywords) {
      if (keyword.toLowerCase().contains(lowerQuery)) {
        results.add(asset);
        break;
      }
    }
  }

  // Sort: exact name matches first, then keyword matches
  results.sort((a, b) {
    final aNameMatch = a.name.toLowerCase().startsWith(lowerQuery) ? 0 : 1;
    final bNameMatch = b.name.toLowerCase().startsWith(lowerQuery) ? 0 : 1;
    return aNameMatch.compareTo(bNameMatch);
  });

  return results;
}
```

**Search performance:** With fewer than 500 bundled stickers, linear search is well within budget (< 1ms). No index structure is needed for V1.

### 5.4 Favorites Persistence

User favorites are persisted as a set of sticker asset IDs in a JSON file:

```dart
/// lib/core/sticker_favorites_manager.dart

class StickerFavoritesManager extends ChangeNotifier {
  /// Set of favorited sticker asset IDs.
  Set<String> _favoriteIds = {};

  /// File path for persistence.
  late final String _filePath;

  /// Whether a sticker is favorited.
  bool isFavorite(String assetId) => _favoriteIds.contains(assetId);

  /// Toggle favorite status.
  void toggleFavorite(String assetId) {
    if (_favoriteIds.contains(assetId)) {
      _favoriteIds.remove(assetId);
    } else {
      _favoriteIds.add(assetId);
    }
    notifyListeners();
    _save();
  }

  /// Get all favorited sticker assets (resolved from registry).
  List<StickerAsset> getFavorites(StickerAssetRegistry registry) {
    return _favoriteIds
        .map((id) => registry.getById(id))
        .whereType<StickerAsset>()
        .toList();
  }

  /// Load from disk.
  Future<void> load() async {
    // Read favorites.json from app documents
    // Parse JSON array of string IDs
  }

  /// Save to disk.
  Future<void> _save() async {
    // Write _favoriteIds as JSON array to favorites.json
  }
}
```

**Storage location:**

```
Documents/
  stickers/
    favorites.json           // ["star_01", "heart_02", "confetti_01", ...]
    imported/                // User-imported sticker files
      custom_logo.png
      brand_watermark.png
```

### 5.5 Custom Image Overlay Import

Users can import PNG images with transparency from the iOS Files app or Photos library:

```dart
/// lib/core/sticker_import_service.dart

class StickerImportService {
  /// Import a PNG image as a custom sticker.
  ///
  /// 1. Copy file to app's sticker import directory.
  /// 2. Generate 64x64 thumbnail.
  /// 3. Read image dimensions for intrinsicWidth/Height.
  /// 4. Create StickerAsset with categoryId = 'imported'.
  /// 5. Register in StickerAssetRegistry.
  /// 6. Return the new StickerAsset.
  Future<StickerAsset?> importImage(String sourcePath);

  /// Delete an imported sticker.
  Future<void> deleteImported(String assetId);

  /// Supported file extensions.
  static const supportedExtensions = ['.png', '.webp'];
}
```

**Import constraints:**

| Constraint | Value | Reason |
|-----------|-------|--------|
| Max file size | 5 MB | Memory pressure during rendering |
| Max dimensions | 2048 x 2048 px | GPU texture size limit for smooth rendering |
| Min dimensions | 32 x 32 px | Usability (too small to interact with) |
| Supported formats | PNG, WebP | Transparency support required |
| Max imported stickers | 100 | Storage and registry performance |

---

## 6. Animated Stickers

### 6.1 Lottie Stickers

Lottie stickers are JSON-based vector animations rendered using the `lottie` Flutter package for preview and baked to `CAKeyframeAnimation` on the native side for export.

**Preview rendering:**

```dart
/// During preview, animated stickers use the lottie package.
///
/// The StickerPreviewPainter does NOT use the lottie widget directly
/// (since it's a CustomPainter, not a widget). Instead, the Lottie
/// composition is loaded and rendered frame-by-frame:

class LottieFrameRenderer {
  /// Loaded Lottie composition.
  LottieComposition? _composition;

  /// Load composition from asset path.
  Future<void> load(String assetPath) async {
    _composition = await AssetLottie(assetPath).load();
  }

  /// Render a specific frame to a Canvas.
  ///
  /// [progress] is 0.0-1.0 representing animation progress.
  /// [rect] is the destination rectangle on the canvas.
  void renderFrame(Canvas canvas, Rect rect, double progress) {
    if (_composition == null) return;

    final drawable = LottieDrawable()
      ..composition = _composition!
      ..setProgress(progress);

    // Save canvas state, translate/scale to rect, draw, restore
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / _composition!.bounds.width,
                 rect.height / _composition!.bounds.height);
    drawable.draw(canvas, _composition!.bounds);
    canvas.restore();
  }
}
```

**Animation progress calculation:**

```dart
double computeAnimationProgress(StickerClip clip, int clipOffsetMicros, StickerAsset asset) {
  if (asset.animationDurationMs == null) return 0.0;

  final animDurationMicros = asset.animationDurationMs! * 1000;
  final adjustedOffset = (clipOffsetMicros * clip.animationSpeed).round();

  if (clip.animationLoops) {
    return (adjustedOffset % animDurationMicros) / animDurationMicros;
  } else {
    return (adjustedOffset / animDurationMicros).clamp(0.0, 1.0);
  }
}
```

### 6.2 GIF Stickers

GIF stickers are decoded into individual frames at load time. During preview, the appropriate frame is selected based on the current clip offset.

```dart
/// lib/core/sticker/gif_frame_cache.dart

class GifFrameCache {
  /// Decoded frames for a GIF sticker.
  /// Key: asset ID, Value: list of decoded frames.
  final Map<String, List<GifFrame>> _cache = {};

  /// Maximum number of GIF stickers cached simultaneously.
  static const int maxCachedGifs = 5;

  /// Load and decode a GIF file.
  Future<List<GifFrame>> loadGif(String assetId, String assetPath) async {
    if (_cache.containsKey(assetId)) return _cache[assetId]!;

    // Decode GIF frames on a background isolate
    final frames = await compute(_decodeGif, assetPath);

    // Evict oldest if cache full
    if (_cache.length >= maxCachedGifs) {
      _cache.remove(_cache.keys.first);
    }

    _cache[assetId] = frames;
    return frames;
  }

  /// Get the frame for a given animation progress (0.0-1.0).
  GifFrame? getFrame(String assetId, double progress) {
    final frames = _cache[assetId];
    if (frames == null || frames.isEmpty) return null;

    final index = (progress * (frames.length - 1)).round().clamp(0, frames.length - 1);
    return frames[index];
  }
}

@immutable
class GifFrame {
  /// Decoded image data.
  final ui.Image image;

  /// Duration of this frame in milliseconds.
  final int durationMs;

  const GifFrame({required this.image, required this.durationMs});
}
```

### 6.3 Export of Animated Stickers

During export, animated stickers must be baked into the `CALayer` hierarchy. The approach differs by type:

**Lottie export:**

```swift
// ios/Runner/Sticker/LottieExportRenderer.swift

class LottieExportRenderer {
    /// Convert a Lottie animation to a sequence of CAKeyframeAnimation
    /// applied to a CALayer containing rasterized frames.
    ///
    /// Strategy: Pre-render the Lottie animation to a sequence of CGImage
    /// frames, then create a CAKeyframeAnimation on the CALayer's `contents`
    /// property that cycles through the frames at the correct timing.
    func renderToLayer(
        lottiePath: String,
        videoSize: CGSize,
        stickerFrame: CGRect,
        startTime: CMTime,
        duration: CMTime,
        speed: Double,
        loops: Bool
    ) -> CALayer {
        // 1. Load Lottie composition using lottie-ios
        // 2. Pre-render frames to CGImage array at export resolution
        // 3. Create CALayer with first frame as contents
        // 4. Create CAKeyframeAnimation(keyPath: "contents")
        //    with values = cgImages, keyTimes = normalized timestamps
        // 5. Set beginTime = startTime relative to composition start
        // 6. Set duration, repeatCount (infinite if loops)
        // 7. Apply to layer
        let layer = CALayer()
        // ... configuration
        return layer
    }
}
```

**GIF export:**

```swift
// ios/Runner/Sticker/GifExportRenderer.swift

class GifExportRenderer {
    /// Convert a GIF to a CAKeyframeAnimation on a CALayer.
    ///
    /// Similar to Lottie but simpler: extract frames from the GIF
    /// using ImageIO, create CAKeyframeAnimation on `contents`.
    func renderToLayer(
        gifPath: String,
        videoSize: CGSize,
        stickerFrame: CGRect,
        startTime: CMTime,
        duration: CMTime,
        speed: Double,
        loops: Bool
    ) -> CALayer {
        // 1. Load GIF via CGImageSource
        // 2. Extract frames and durations
        // 3. Create CALayer + CAKeyframeAnimation
        let layer = CALayer()
        // ... configuration
        return layer
    }
}
```

### 6.4 Animated Sticker Memory Management

Animated stickers can be memory-intensive:

| Sticker Type | Memory per Sticker | Mitigation |
|-------------|-------------------|------------|
| Static PNG | ~256 KB (256x256 RGBA) | Shared image cache with LRU eviction |
| Lottie | ~50 KB (JSON) + ~1 MB (rendered frames at preview resolution) | Render on demand, cache 2 seconds of frames |
| GIF | ~2-5 MB (all decoded frames) | Max 5 GIFs cached, evict LRU |

**Total animated sticker memory budget:** 20 MB maximum across all cached animated sticker frames. This is enforced by the `GifFrameCache` and `LottieFrameRenderer` classes, which track total memory usage and evict oldest entries when exceeded.

---

## 7. Gesture Handling

### 7.1 Sticker Gestures on Video Preview

When a sticker is placed on the video preview, the user can interact with it via touch gestures. The gesture model follows the same approach established by TextClip:

| Gesture | Action | Implementation |
|---------|--------|---------------|
| **Tap on sticker** | Select sticker (show handles) | Hit-test against sticker bounds, set selection |
| **Drag on sticker** | Move position | Update `StickerClip.position` (normalized) |
| **Pinch on sticker** | Scale | Update `StickerClip.scale` |
| **Two-finger rotate** | Rotate | Update `StickerClip.rotation` |
| **Drag + Pinch + Rotate** | Simultaneous transform | All three applied in a single gesture |
| **Double-tap on sticker** | Open editor panel | Present `StickerEditorPanel` |
| **Long-press on sticker** | Show context menu | `CupertinoContextMenu` with Copy, Delete, Flip, etc. |
| **Tap on empty area** | Deselect sticker | Clear selection, dismiss handles |

### 7.2 Hit Testing

Sticker hit testing accounts for the sticker's current transform (position, scale, rotation):

```dart
/// Determine if a touch point hits a sticker.
///
/// [touchPoint] is in normalized canvas coordinates (0.0-1.0).
/// [clip] is the sticker clip with current transform state.
/// [asset] provides intrinsic dimensions for bounds calculation.
bool hitTestSticker(Offset touchPoint, StickerClip clip, StickerAsset asset, Size canvasSize) {
  // 1. Calculate sticker bounds in canvas coordinates
  final stickerWidth = asset.intrinsicWidth * clip.scale / canvasSize.width;
  final stickerHeight = asset.intrinsicHeight * clip.scale / canvasSize.height;

  // 2. Transform touch point to sticker's local coordinate space
  //    (inverse of position + rotation transform)
  final dx = touchPoint.dx - clip.position.dx;
  final dy = touchPoint.dy - clip.position.dy;
  final cosR = cos(-clip.rotation);
  final sinR = sin(-clip.rotation);
  final localX = dx * cosR - dy * sinR;
  final localY = dx * sinR + dy * cosR;

  // 3. Check if local point is within sticker bounds
  final halfW = stickerWidth / 2;
  final halfH = stickerHeight / 2;
  return localX >= -halfW && localX <= halfW &&
         localY >= -halfH && localY <= halfH;
}
```

### 7.3 Selection Handles

When a sticker is selected, visual handles appear around it:

```
     [Rotate Handle]
          |
  +---[Top Edge]---+
  |                 |
[Left]  [Sticker]  [Right]    <-- Drag handles for scaling
  |                 |
  +--[Bottom Edge]--+
          |
     [Delete Handle]
```

The handles are rendered by `StickerPreviewPainter` as small circular touchpoints. Handle interactions:

- **Corner handles:** Proportional scale (drag outward to enlarge, inward to shrink).
- **Rotation handle:** Rotate by dragging in a circular motion around the center.
- **Delete handle:** Tap to delete (with `CupertinoAlertDialog` confirmation).

### 7.4 Snap Guides

When dragging a sticker, snap guides appear to help with alignment:

| Snap Target | Threshold | Visual Feedback |
|-------------|-----------|-----------------|
| Canvas center (0.5, 0.5) | 0.02 normalized | Cyan crosshair lines |
| Canvas horizontal center | 0.02 | Cyan horizontal line |
| Canvas vertical center | 0.02 | Cyan vertical line |
| Canvas edges (0.0, 1.0) | 0.02 | Cyan edge line |
| Other sticker positions | 0.02 | Yellow alignment line |

**Haptic feedback:** `HapticFeedback.selectionClick()` triggers when a sticker snaps to a guide.

### 7.5 Gesture-to-Keyframe Recording

When "Record Keyframes" mode is enabled in the sticker editor:

1. A keyframe is automatically created at the current playhead position when the user begins a gesture.
2. A second keyframe is created at the gesture end position.
3. This allows rapid creation of motion paths by scrubbing to a time, positioning the sticker, scrubbing to another time, and repositioning.

This mirrors the Smart Edit system's gesture-to-keyframe pattern established in `GestureCaptureEngine`.

---

## 8. Keyframe Animations

### 8.1 Animatable Properties

Each `StickerKeyframe` stores the following animatable properties:

| Property | Type | Range | Default |
|----------|------|-------|---------|
| `position` | `Offset` | (0.0-1.0, 0.0-1.0) | (0.5, 0.5) |
| `scale` | `double` | 0.1 - 5.0 | 1.0 |
| `rotation` | `double` | -infinity to infinity (radians) | 0.0 |
| `opacity` | `double` | 0.0 - 1.0 | 1.0 |

### 8.2 Interpolation

Keyframe interpolation reuses the shared `InterpolationUtils` class (designed in the Text & Titles system):

```dart
StickerRenderData interpolateStickerKeyframes(
  List<StickerKeyframe> keyframes,
  int clipOffsetMicros,
) {
  if (keyframes.isEmpty) return StickerRenderData.identity;

  if (keyframes.length == 1) {
    final kf = keyframes[0];
    return StickerRenderData(
      position: kf.position,
      scale: kf.scale,
      rotation: kf.rotation,
      opacity: kf.opacity,
    );
  }

  // Find surrounding keyframes using binary search
  StickerKeyframe? before;
  StickerKeyframe? after;

  for (int i = 0; i < keyframes.length; i++) {
    if (keyframes[i].timestampMicros <= clipOffsetMicros) {
      before = keyframes[i];
    } else {
      after = keyframes[i];
      break;
    }
  }

  // Before first keyframe: use first keyframe values
  if (before == null) {
    final kf = keyframes.first;
    return StickerRenderData(
      position: kf.position,
      scale: kf.scale,
      rotation: kf.rotation,
      opacity: kf.opacity,
    );
  }

  // After last keyframe: use last keyframe values
  if (after == null) {
    return StickerRenderData(
      position: before.position,
      scale: before.scale,
      rotation: before.rotation,
      opacity: before.opacity,
    );
  }

  // Interpolate between surrounding keyframes
  final range = after.timestampMicros - before.timestampMicros;
  final rawT = (clipOffsetMicros - before.timestampMicros) / range;
  final t = InterpolationUtils.applyEasing(
    rawT,
    before.interpolation,
    before.bezierPoints,
  );

  return StickerRenderData(
    position: InterpolationUtils.lerpOffset(before.position, after.position, t),
    scale: InterpolationUtils.lerpDouble(before.scale, after.scale, t),
    rotation: InterpolationUtils.lerpDouble(before.rotation, after.rotation, t),
    opacity: InterpolationUtils.lerpDouble(before.opacity, after.opacity, t),
  );
}
```

### 8.3 Keyframe UI on Timeline

Sticker keyframes are displayed as small diamond markers on the sticker clip in the timeline, identical to the pattern used for text clip keyframes:

```
[====== Sticker Clip ======]
       ^      ^      ^
       |      |      |
     KF1    KF2    KF3          <-- Diamond markers on clip
```

Tapping a diamond marker selects that keyframe and scrolls the playhead to its timestamp. The sticker editor panel then shows the keyframe's properties for editing.

### 8.4 Keyframe Management UI

The sticker editor panel includes a keyframe section:

```
Keyframes Section:
  [+ Add Keyframe at Playhead]    <-- Creates keyframe at current time

  List of keyframes:
  [KF1  0:00.500  easeInOut  ...]    <-- Tap to select, swipe to delete
  [KF2  0:01.200  spring     ...]
  [KF3  0:02.800  linear     ...]

  Selected Keyframe:
  Interpolation: [CupertinoPicker: 21 easing types]
  Position: [x: 0.50  y: 0.50]      <-- Read-only, set via gesture
  Scale:    [CupertinoSlider: 0.1-5.0]
  Rotation: [CupertinoSlider: -360 to 360 degrees]
  Opacity:  [CupertinoSlider: 0.0-1.0]
```

---

## 9. Timeline Integration

### 9.1 StickerClip in the Persistent AVL Tree

`StickerClip` extends `GeneratorClip`, which has a `durationMicroseconds` field. This makes it directly compatible with the `PersistentTimeline` tree, which uses `item.durationMicroseconds` for subtree duration calculations.

**No changes needed to `PersistentTimeline`, `TimelineNode`, or `TimelineManager`** -- they are generic over `TimelineItem` and work with `StickerClip` out of the box.

### 9.2 StickerClipManager

Following the `TextClipManager` pattern:

```dart
/// lib/core/sticker_clip_manager.dart

class StickerClipManager extends ChangeNotifier {
  /// Sticker timelines by track ID.
  /// Each sticker track has its own PersistentTimeline.
  Map<String, PersistentTimeline> _stickerTimelines = {};

  /// Undo/redo stacks per track.
  final Map<String, List<PersistentTimeline>> _undoStacks = {};
  final Map<String, List<PersistentTimeline>> _redoStacks = {};

  /// Sticker asset registry.
  final StickerAssetRegistry _registry;

  StickerClipManager(this._registry);

  /// Create a new sticker track and return its ID.
  String createStickerTrack({String? name});

  /// Add a StickerClip to a track at a specific time.
  void addStickerClip(String trackId, int timeMicros, StickerClip clip);

  /// Remove a StickerClip.
  void removeStickerClip(String trackId, String clipId);

  /// Update a StickerClip (e.g., after transform, keyframe edit, opacity change).
  void updateStickerClip(String trackId, String clipId, StickerClip newClip);

  /// Get all StickerClips visible at a specific time across all sticker tracks.
  List<(String trackId, StickerClip clip, int offsetWithinClip)> stickerClipsAtTime(int timeMicros);

  /// Move a sticker clip to a different time (or different track).
  void moveStickerClip(String fromTrackId, String toTrackId, String clipId, int newTimeMicros);

  /// Split sticker clip at time.
  void splitStickerClipAt(String trackId, int timeMicros);

  /// Trim sticker clip head or tail.
  void trimStickerClipHead(String trackId, String clipId, int newStartMicros);
  void trimStickerClipTail(String trackId, String clipId, int newEndMicros);

  /// Duplicate a sticker clip.
  void duplicateStickerClip(String trackId, String clipId);

  /// Undo/redo for a specific track.
  void undo(String trackId);
  void redo(String trackId);
}
```

### 9.3 Duration Control

Sticker clip duration is controlled via:

1. **Timeline drag handles:** Drag the left/right edge of the sticker clip on the timeline to trim/extend.
2. **Duration field in editor:** Explicit duration input via `CupertinoTextField` in the sticker editor panel.
3. **Snap to video length:** Option to extend the sticker to cover the full video duration.

**Duration constraints:**

| Constraint | Value |
|-----------|-------|
| Minimum duration | 33,333 microseconds (~1 frame at 30fps) |
| Maximum duration | Total video duration |
| Default duration | 3,000,000 microseconds (3 seconds) |
| Animated sticker default | Match the sticker's animation duration (or 3s, whichever is longer) |

### 9.4 Sticker Track Operations

| Operation | Behavior |
|-----------|----------|
| **Add sticker** | Creates clip at playhead on first available sticker track (or creates new track) |
| **Delete sticker** | Removes clip from track. If track is now empty, offer to remove track. |
| **Reorder tracks** | Drag track header up/down to change z-order |
| **Lock track** | Prevents editing of all stickers on that track |
| **Mute track** | Hides all stickers on that track during preview (still exported) |
| **Add track** | Creates a new empty sticker track |

---

## 10. Preview Rendering

### 10.1 StickerPreviewPainter

`StickerPreviewPainter` is a `CustomPainter` that sits in the widget tree above the video player, alongside `TextPreviewPainter`:

```dart
/// lib/timeline/rendering/painters/sticker_preview_painter.dart

class StickerPreviewPainter extends CustomPainter {
  /// All sticker clips visible at current time, sorted by track z-order.
  final List<StickerRenderData> visibleStickers;

  /// Current playhead time (for animation progress calculation).
  final int currentTimeMicros;

  /// Video render size (to convert normalized positions to pixels).
  final Size videoSize;

  /// Selected sticker clip ID (to draw selection handles).
  final String? selectedStickerId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stickerData in visibleStickers) {
      _renderSticker(canvas, size, stickerData);
    }

    // Draw selection handles for selected sticker
    if (selectedStickerId != null) {
      final selected = visibleStickers
          .where((s) => s.clipId == selectedStickerId)
          .firstOrNull;
      if (selected != null) {
        _drawSelectionHandles(canvas, size, selected);
      }
    }
  }

  void _renderSticker(Canvas canvas, Size size, StickerRenderData data) {
    if (data.opacity <= 0.0) return;

    canvas.save();

    // 1. Translate to sticker position (normalized -> pixel)
    final px = data.position.dx * size.width;
    final py = data.position.dy * size.height;
    canvas.translate(px, py);

    // 2. Apply rotation
    canvas.rotate(data.rotation);

    // 3. Apply scale
    canvas.scale(data.scale * (data.isFlippedHorizontally ? -1 : 1),
                 data.scale * (data.isFlippedVertically ? -1 : 1));

    // 4. Apply opacity
    final paint = Paint()..color = Color.fromRGBO(255, 255, 255, data.opacity);

    // 5. Apply tint if present
    if (data.tintColorValue != null) {
      paint.colorFilter = ColorFilter.mode(
        Color(data.tintColorValue!),
        BlendMode.modulate,
      );
    }

    // 6. Draw the sticker image centered at origin
    final halfW = data.renderWidth / 2;
    final halfH = data.renderHeight / 2;
    final destRect = Rect.fromLTWH(-halfW, -halfH, data.renderWidth, data.renderHeight);

    if (data.image != null) {
      // Static sticker or current GIF frame
      canvas.drawImageRect(data.image!, data.sourceRect, destRect, paint);
    }
    // Lottie stickers are rendered via LottieFrameRenderer.renderFrame()

    canvas.restore();
  }

  void _drawSelectionHandles(Canvas canvas, Size size, StickerRenderData data) {
    // Draw dashed border around sticker
    // Draw corner scale handles (circles)
    // Draw rotation handle (circle above top edge)
    // Draw delete handle (X below bottom edge)
  }

  @override
  bool shouldRepaint(StickerPreviewPainter oldDelegate) {
    return visibleStickers != oldDelegate.visibleStickers ||
           currentTimeMicros != oldDelegate.currentTimeMicros ||
           selectedStickerId != oldDelegate.selectedStickerId;
  }
}
```

### 10.2 StickerRenderData

Lightweight struct computed each frame from `StickerClip` + current time + resolved asset:

```dart
@immutable
class StickerRenderData {
  final String clipId;
  final String stickerAssetId;
  final Offset position;       // After keyframe interpolation
  final double scale;          // After keyframe interpolation
  final double rotation;       // After keyframe interpolation
  final double opacity;        // After keyframe interpolation
  final bool isFlippedHorizontally;
  final bool isFlippedVertically;
  final int? tintColorValue;
  final double renderWidth;    // In canvas pixels
  final double renderHeight;   // In canvas pixels
  final ui.Image? image;       // Resolved sticker image (or current anim frame)
  final Rect sourceRect;       // Source rect within the image
  final int trackIndex;        // For z-order
  final bool isAnimated;       // Whether this is an animated sticker

  static const StickerRenderData identity = StickerRenderData(
    clipId: '',
    stickerAssetId: '',
    position: Offset(0.5, 0.5),
    scale: 1.0,
    rotation: 0.0,
    opacity: 1.0,
    isFlippedHorizontally: false,
    isFlippedVertically: false,
    tintColorValue: null,
    renderWidth: 0,
    renderHeight: 0,
    image: null,
    sourceRect: Rect.zero,
    trackIndex: 0,
    isAnimated: false,
  );

  const StickerRenderData({
    required this.clipId,
    required this.stickerAssetId,
    required this.position,
    required this.scale,
    required this.rotation,
    required this.opacity,
    required this.isFlippedHorizontally,
    required this.isFlippedVertically,
    required this.tintColorValue,
    required this.renderWidth,
    required this.renderHeight,
    required this.image,
    required this.sourceRect,
    required this.trackIndex,
    required this.isAnimated,
  });
}
```

### 10.3 Sticker Image Cache

Static sticker images are cached in memory to avoid re-decoding:

```dart
/// lib/core/sticker/sticker_image_cache.dart

class StickerImageCache {
  /// Cache of decoded sticker images.
  /// Key: asset ID, Value: decoded ui.Image.
  final Map<String, ui.Image> _cache = {};

  /// Maximum cache entries for static stickers.
  static const int maxStaticEntries = 30;

  /// Load and cache a static sticker image.
  Future<ui.Image?> getImage(String assetId, String assetPath) async {
    if (_cache.containsKey(assetId)) return _cache[assetId];

    // Decode image on background isolate
    final image = await _decodeImageFromAsset(assetPath);

    // Evict oldest if full
    if (_cache.length >= maxStaticEntries) {
      final oldest = _cache.keys.first;
      _cache[oldest]?.dispose();
      _cache.remove(oldest);
    }

    _cache[assetId] = image;
    return image;
  }

  /// Evict a specific entry.
  void evict(String assetId) {
    _cache[assetId]?.dispose();
    _cache.remove(assetId);
  }

  /// Clear all cached images.
  void clear() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }
}
```

### 10.4 Compositing Order in Preview

The video preview compositing stack (bottom to top):

```
1. Video player widget (base video)
2. TextPreviewPainter (text overlays, sorted by track index)
3. StickerPreviewPainter (sticker overlays, sorted by track index)
4. Gesture overlay (selection handles, snap guides)
```

If both text and sticker clips exist at the same time, their z-order is determined by track index across all overlay track types. A sticker on track index 3 renders above text on track index 2.

---

## 11. Export Pipeline

### 11.1 Platform Channel Data Transfer

During export, sticker clips are serialized and sent to the native layer:

```dart
// Platform channel call from Flutter
final stickerLayers = stickerClips.map((clip) => {
  'clipId': clip.id,
  'stickerAssetId': clip.stickerAssetId,
  'assetPath': registry.getById(clip.stickerAssetId)!.assetPath,
  'assetType': registry.getById(clip.stickerAssetId)!.type.name,
  'position': {'x': clip.position.dx, 'y': clip.position.dy},
  'scale': clip.scale,
  'rotation': clip.rotation,
  'opacity': clip.opacity,
  'isFlippedHorizontally': clip.isFlippedHorizontally,
  'isFlippedVertically': clip.isFlippedVertically,
  'startMicros': clip.startTimeOnTimeline,
  'endMicros': clip.endTimeOnTimeline,
  'durationMicros': clip.durationMicroseconds,
  'keyframes': clip.keyframes.map((kf) => kf.toJson()).toList(),
  'tintColorValue': clip.tintColorValue,
  'animationSpeed': clip.animationSpeed,
  'animationLoops': clip.animationLoops,
  'animationDurationMs': registry.getById(clip.stickerAssetId)!.animationDurationMs,
  'intrinsicWidth': registry.getById(clip.stickerAssetId)!.intrinsicWidth,
  'intrinsicHeight': registry.getById(clip.stickerAssetId)!.intrinsicHeight,
}).toList();
```

### 11.2 StickerLayerBuilder (Swift)

```swift
// ios/Runner/Sticker/StickerLayerBuilder.swift

class StickerLayerBuilder {
    private let lottieRenderer = LottieExportRenderer()
    private let gifRenderer = GifExportRenderer()

    func buildStickerLayers(
        from stickerData: [[String: Any]],
        videoSize: CGSize,
        videoDuration: CMTime
    ) -> CALayer {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)

        for data in stickerData {
            let assetType = data["assetType"] as? String ?? "staticImage"

            switch assetType {
            case "lottie":
                let layer = buildLottieLayer(from: data, videoSize: videoSize, videoDuration: videoDuration)
                parentLayer.addSublayer(layer)

            case "gif":
                let layer = buildGifLayer(from: data, videoSize: videoSize, videoDuration: videoDuration)
                parentLayer.addSublayer(layer)

            default: // staticImage, svg
                let layer = buildStaticLayer(from: data, videoSize: videoSize, videoDuration: videoDuration)
                parentLayer.addSublayer(layer)
            }
        }

        return parentLayer
    }

    private func buildStaticLayer(
        from data: [String: Any],
        videoSize: CGSize,
        videoDuration: CMTime
    ) -> CALayer {
        let layer = CALayer()

        // 1. Load image from asset path
        guard let assetPath = data["assetPath"] as? String,
              let image = UIImage(contentsOfFile: assetPath)?.cgImage else {
            return layer
        }

        // 2. Configure frame based on position, scale, intrinsic size
        let position = data["position"] as? [String: Double] ?? ["x": 0.5, "y": 0.5]
        let scale = data["scale"] as? Double ?? 1.0
        let intrinsicW = data["intrinsicWidth"] as? Double ?? 120
        let intrinsicH = data["intrinsicHeight"] as? Double ?? 120

        // Scale intrinsic size relative to 1080p reference
        let scaleRatio = videoSize.height / 1080.0
        let renderW = intrinsicW * scale * scaleRatio
        let renderH = intrinsicH * scale * scaleRatio
        let centerX = position["x"]! * Double(videoSize.width)
        // Core Animation Y is flipped (origin at bottom-left)
        let centerY = (1.0 - position["y"]!) * Double(videoSize.height)

        layer.frame = CGRect(
            x: centerX - renderW / 2,
            y: centerY - renderH / 2,
            width: renderW,
            height: renderH
        )
        layer.contents = image

        // 3. Apply rotation
        let rotation = data["rotation"] as? Double ?? 0.0
        layer.transform = CATransform3DMakeRotation(CGFloat(-rotation), 0, 0, 1)

        // 4. Apply opacity
        let opacity = data["opacity"] as? Double ?? 1.0
        layer.opacity = Float(opacity)

        // 5. Apply flip transforms
        let flipH = data["isFlippedHorizontally"] as? Bool ?? false
        let flipV = data["isFlippedVertically"] as? Bool ?? false
        if flipH || flipV {
            var transform = layer.transform
            if flipH { transform = CATransform3DScale(transform, -1, 1, 1) }
            if flipV { transform = CATransform3DScale(transform, 1, -1, 1) }
            layer.transform = transform
        }

        // 6. Set visibility timing
        let startMicros = data["startMicros"] as? Int ?? 0
        let endMicros = data["endMicros"] as? Int ?? 0
        let startTime = CMTime(value: CMTimeValue(startMicros), timescale: 1_000_000)
        let endTime = CMTime(value: CMTimeValue(endMicros), timescale: 1_000_000)

        // Hide before start and after end
        layer.opacity = 0
        let showAnimation = CABasicAnimation(keyPath: "opacity")
        showAnimation.fromValue = Float(opacity)
        showAnimation.toValue = Float(opacity)
        showAnimation.beginTime = CMTimeGetSeconds(startTime)
        showAnimation.duration = CMTimeGetSeconds(endTime) - CMTimeGetSeconds(startTime)
        showAnimation.fillMode = .forwards
        showAnimation.isRemovedOnCompletion = false
        layer.add(showAnimation, forKey: "visibility")

        // 7. Add keyframe animations if present
        let keyframes = data["keyframes"] as? [[String: Any]] ?? []
        if !keyframes.isEmpty {
            addKeyframeAnimations(to: layer, keyframes: keyframes,
                                 videoSize: videoSize, startTime: startTime,
                                 clipDuration: CMTimeGetSeconds(endTime) - CMTimeGetSeconds(startTime))
        }

        return layer
    }

    private func addKeyframeAnimations(
        to layer: CALayer,
        keyframes: [[String: Any]],
        videoSize: CGSize,
        startTime: CMTime,
        clipDuration: Double
    ) {
        // Convert StickerKeyframes to CAKeyframeAnimation objects
        // for position, transform (scale + rotation), and opacity.
        // Each animation uses beginTime = start of clip,
        // with keyTimes normalized to clip duration.
    }

    private func buildLottieLayer(
        from data: [String: Any],
        videoSize: CGSize,
        videoDuration: CMTime
    ) -> CALayer {
        guard let assetPath = data["assetPath"] as? String else {
            return CALayer()
        }

        let position = data["position"] as? [String: Double] ?? ["x": 0.5, "y": 0.5]
        let scale = data["scale"] as? Double ?? 1.0
        let startMicros = data["startMicros"] as? Int ?? 0
        let durationMicros = data["durationMicros"] as? Int ?? 3_000_000
        let speed = data["animationSpeed"] as? Double ?? 1.0
        let loops = data["animationLoops"] as? Bool ?? true
        let intrinsicW = data["intrinsicWidth"] as? Double ?? 120
        let intrinsicH = data["intrinsicHeight"] as? Double ?? 120

        let scaleRatio = videoSize.height / 1080.0
        let renderW = intrinsicW * scale * scaleRatio
        let renderH = intrinsicH * scale * scaleRatio
        let centerX = position["x"]! * Double(videoSize.width)
        let centerY = (1.0 - position["y"]!) * Double(videoSize.height)
        let frame = CGRect(x: centerX - renderW / 2, y: centerY - renderH / 2,
                          width: renderW, height: renderH)

        let startTime = CMTime(value: CMTimeValue(startMicros), timescale: 1_000_000)
        let duration = CMTime(value: CMTimeValue(durationMicros), timescale: 1_000_000)

        return lottieRenderer.renderToLayer(
            lottiePath: assetPath,
            videoSize: videoSize,
            stickerFrame: frame,
            startTime: startTime,
            duration: duration,
            speed: speed,
            loops: loops
        )
    }

    private func buildGifLayer(
        from data: [String: Any],
        videoSize: CGSize,
        videoDuration: CMTime
    ) -> CALayer {
        // Similar to Lottie but uses GifExportRenderer
        guard let assetPath = data["assetPath"] as? String else {
            return CALayer()
        }

        let position = data["position"] as? [String: Double] ?? ["x": 0.5, "y": 0.5]
        let scale = data["scale"] as? Double ?? 1.0
        let startMicros = data["startMicros"] as? Int ?? 0
        let durationMicros = data["durationMicros"] as? Int ?? 3_000_000
        let speed = data["animationSpeed"] as? Double ?? 1.0
        let loops = data["animationLoops"] as? Bool ?? true
        let intrinsicW = data["intrinsicWidth"] as? Double ?? 120
        let intrinsicH = data["intrinsicHeight"] as? Double ?? 120

        let scaleRatio = videoSize.height / 1080.0
        let renderW = intrinsicW * scale * scaleRatio
        let renderH = intrinsicH * scale * scaleRatio
        let centerX = position["x"]! * Double(videoSize.width)
        let centerY = (1.0 - position["y"]!) * Double(videoSize.height)
        let frame = CGRect(x: centerX - renderW / 2, y: centerY - renderH / 2,
                          width: renderW, height: renderH)

        let startTime = CMTime(value: CMTimeValue(startMicros), timescale: 1_000_000)
        let duration = CMTime(value: CMTimeValue(durationMicros), timescale: 1_000_000)

        return gifRenderer.renderToLayer(
            gifPath: assetPath,
            videoSize: videoSize,
            stickerFrame: frame,
            startTime: startTime,
            duration: duration,
            speed: speed,
            loops: loops
        )
    }
}
```

### 11.3 Integration with Export Composition

The sticker layer tree is added alongside text layers in the `AVVideoCompositionCoreAnimationTool` hierarchy:

```swift
// In VideoProcessingService export method:

let videoLayer = CALayer()
videoLayer.frame = CGRect(origin: .zero, size: finalOutputSize)

let textParentLayer = textLayerBuilder.buildTextLayers(
    from: textLayers,
    videoSize: finalOutputSize,
    videoDuration: totalDuration
)

let stickerParentLayer = stickerLayerBuilder.buildStickerLayers(
    from: stickerLayers,
    videoSize: finalOutputSize,
    videoDuration: totalDuration
)

let outputLayer = CALayer()
outputLayer.frame = CGRect(origin: .zero, size: finalOutputSize)
outputLayer.addSublayer(videoLayer)
outputLayer.addSublayer(textParentLayer)    // Text above video
outputLayer.addSublayer(stickerParentLayer) // Stickers above text

let animationTool = AVVideoCompositionCoreAnimationTool(
    postProcessingAsVideoLayer: videoLayer,
    in: outputLayer
)
videoComposition.animationTool = animationTool
```

**Note on z-ordering:** The relative order of text and sticker parent layers matches the track index ordering: sticker tracks with higher indices render above text tracks with lower indices, and vice versa. For full correct ordering, a single parent layer should be used with sublayers added in track index order, intermixing text and sticker layers as needed:

```swift
// Correct approach for mixed overlay ordering:
let overlayParentLayer = CALayer()
overlayParentLayer.frame = CGRect(origin: .zero, size: finalOutputSize)

// Sort all overlay layers (text + sticker) by their track index
let allOverlays = (textLayerEntries + stickerLayerEntries)
    .sorted(by: { $0.trackIndex < $1.trackIndex })

for overlay in allOverlays {
    overlayParentLayer.addSublayer(overlay.layer)
}

let outputLayer = CALayer()
outputLayer.frame = CGRect(origin: .zero, size: finalOutputSize)
outputLayer.addSublayer(videoLayer)
outputLayer.addSublayer(overlayParentLayer)
```

---

## 12. UI Design

### 12.1 Sticker Browser (iOS 26 Liquid Glass)

The sticker browser is presented as a half-sheet modal (same as text template browser) with full Liquid Glass styling:

```
+----------------------------------------------+
|  [X Close]     Stickers              [Search] |  <-- CupertinoNavigationBar
+----------------------------------------------+
| [Favorites][Emoji][Shapes][Icons][Animated].. |  <-- CNTabBar (scrollable)
+----------------------------------------------+
|                                               |
|  +------+  +------+  +------+  +------+      |
|  | Star |  | Heart|  | Fire |  |Thumbs|      |  <-- Grid of sticker thumbnails
|  +------+  +------+  +------+  +------+      |     (4 columns, scrollable)
|                                               |
|  +------+  +------+  +------+  +------+      |
|  |Light |  |Spark |  | Moon |  | Sun  |      |
|  +------+  +------+  +------+  +------+      |
|                                               |
|  +------+  +------+  +------+  +------+      |
|  |Arrow |  |Badge |  |Crown |  |Music |      |
|  +------+  +------+  +------+  +------+      |
|                                               |
+----------------------------------------------+
```

### 12.2 Category Tab Bar

The category selector uses `CNTabBar` from `cupertino_native_better`:

```dart
Positioned(
  left: 0,
  right: 0,
  top: navBarHeight,
  child: SizedBox(
    height: 44,
    child: CNTabBar(
      items: categories.map((cat) => CNTabBarItem(
        label: cat.name,
        icon: CNSymbol(cat.iconName),
        activeIcon: CNSymbol('${cat.iconName}.fill'),
      )).toList(),
      currentIndex: _selectedCategoryIndex,
      onTap: (index) {
        HapticFeedback.selectionClick();
        setState(() => _selectedCategoryIndex = index);
      },
      shrinkCentered: false,
    ),
  ),
),
```

### 12.3 Search Bar

```dart
CupertinoSearchTextField(
  placeholder: 'Search stickers',
  onChanged: (query) {
    setState(() {
      _searchResults = _registry.search(query);
      _isSearching = query.isNotEmpty;
    });
  },
  style: const TextStyle(color: CupertinoColors.white),
)
```

### 12.4 Sticker Grid

The sticker grid is a `GridView.builder` with 4 columns:

```dart
GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 4,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
  ),
  itemCount: stickers.length,
  itemBuilder: (context, index) {
    final sticker = stickers[index];
    return _StickerTile(
      asset: sticker,
      isFavorite: _favoritesManager.isFavorite(sticker.id),
      onTap: () => _addStickerToTimeline(sticker),
      onLongPress: () => _showStickerContextMenu(sticker),
      onFavoriteToggle: () => _favoritesManager.toggleFavorite(sticker.id),
    );
  },
)
```

Each tile shows:
- Sticker thumbnail (64x64 from pre-generated thumbnails).
- Animated stickers show a small play icon badge in the bottom-right corner.
- Favorite stickers show a small heart icon badge in the top-right corner.
- Long-press opens a `CupertinoContextMenu` with: "Add to Favorites" / "Remove from Favorites", "Preview" (full size), "Info" (dimensions, type).

### 12.5 Sticker Editor Panel

When a sticker is selected on the timeline or video preview, the editor panel appears:

```
+----------------------------------------------+
|         Sticker Properties                    |  <-- Section header
+----------------------------------------------+
| Opacity      [=========|=] 80%               |  <-- CupertinoSlider
| Duration     [0:03.000        ]              |  <-- CupertinoTextField
| Flip         [H] [V]                        |  <-- CupertinoButton toggles
| Tint Color   [Color Well]                    |  <-- Tap opens color picker
| Anim Speed   [=========|=] 1.0x             |  <-- CupertinoSlider (animated only)
| Anim Loop    [ON       ]                    |  <-- CupertinoSwitch (animated only)
+----------------------------------------------+
|         Keyframes                            |  <-- Section header
+----------------------------------------------+
| [+ Add Keyframe]                             |  <-- CNButton.icon glass style
| KF1  0:00.500  easeInOut                     |
| KF2  0:01.200  spring                        |
+----------------------------------------------+
```

All controls use native Cupertino widgets as mandated by the project's design system.

### 12.6 Add Sticker Entry Point

The "Add Sticker" action is accessible from:

1. **Timeline toolbar:** A sticker icon button opens the sticker browser.
2. **Video preview long-press:** Context menu includes "Add Sticker" option.
3. **Bottom bar action:** On the main editor screen, alongside text and other overlay actions.

The action button uses the standard pattern:

```dart
CNButton.icon(
  icon: const CNSymbol('face.smiling', size: 24),
  config: const CNButtonConfig(
    style: CNButtonStyle.glass,
    minHeight: 44,
    width: 44,
  ),
  onPressed: _openStickerBrowser,
),
```

### 12.7 Sticker Context Menu

Long-pressing a sticker on the video preview shows:

```dart
CupertinoContextMenu(
  actions: [
    CupertinoContextMenuAction(
      child: const Text('Copy'),
      trailingIcon: CupertinoIcons.doc_on_doc,
      onPressed: _copySticker,
    ),
    CupertinoContextMenuAction(
      child: const Text('Duplicate'),
      trailingIcon: CupertinoIcons.plus_square_on_square,
      onPressed: _duplicateSticker,
    ),
    CupertinoContextMenuAction(
      child: const Text('Flip Horizontal'),
      trailingIcon: CupertinoIcons.arrow_right_arrow_left,
      onPressed: _flipHorizontal,
    ),
    CupertinoContextMenuAction(
      child: const Text('Flip Vertical'),
      trailingIcon: CupertinoIcons.arrow_up_arrow_down,
      onPressed: _flipVertical,
    ),
    CupertinoContextMenuAction(
      child: const Text('Send to Back'),
      trailingIcon: CupertinoIcons.arrow_down_to_line,
      onPressed: _sendToBack,
    ),
    CupertinoContextMenuAction(
      child: const Text('Bring to Front'),
      trailingIcon: CupertinoIcons.arrow_up_to_line,
      onPressed: _bringToFront,
    ),
    CupertinoContextMenuAction(
      isDestructiveAction: true,
      child: const Text('Delete'),
      trailingIcon: CupertinoIcons.delete,
      onPressed: _deleteSticker,
    ),
  ],
  child: _stickerPreviewWidget,
),
```

---

## 13. Edge Cases

### 13.1 Many Simultaneous Stickers

- Maximum visible stickers rendered simultaneously: 8 (enforced).
- If more than 8 sticker clips overlap at the same time across tracks, only the top 8 (by track index) are rendered.
- A debug-mode warning is logged when more than 8 overlapping stickers are detected.
- The limit ensures the 3ms-per-sticker budget fits within the total frame budget.

### 13.2 Large Animated Stickers

- Lottie files larger than 200 KB are rejected during import with a user-facing warning.
- GIF files larger than 500 KB are rejected during import.
- If a Lottie animation has more than 300 frames, it is sampled at half frame rate during preview to stay within budget.
- During fast scrub (velocity > threshold), animated stickers render their first frame only (frozen).

### 13.3 Memory Pressure

- The app monitors memory warnings via `didReceiveMemoryWarning` (iOS).
- Under memory pressure:
  1. All GIF frame caches are cleared.
  2. Lottie frame caches are cleared.
  3. Static sticker image cache is reduced to 10 entries.
  4. Non-visible sticker images are evicted.
- Memory recovery is automatic; caches are rebuilt on demand.

### 13.4 Sticker at Video Boundaries

- Sticker clips cannot extend beyond the total timeline duration.
- If the user drags a sticker clip past the end of the timeline, it is clamped.
- Sticker clips can start at time 0 and end at the last frame.

### 13.5 Sticker Clip Copy/Paste

- Copy creates a deep clone of the `StickerClip` with a new UUID.
- The clone references the same `stickerAssetId` (the sticker image is shared, not duplicated).
- All keyframes, transforms, and animation settings are copied.
- Paste inserts the clone at the playhead on the same (or first available) sticker track.

### 13.6 Deleted Imported Sticker Assets

If a user-imported sticker file is deleted from disk but referenced by existing `StickerClip`s:

1. The `StickerAssetRegistry` marks the asset as missing.
2. The `StickerPreviewPainter` renders a placeholder image (gray square with "?" icon).
3. The export pipeline skips missing sticker layers (with a warning to the user).
4. The user is prompted to re-import or remove the affected sticker clips.

### 13.7 Sticker During Transitions

- Sticker clips span across video transitions without being affected by the transition effect.
- Stickers float above the video layer in the compositing stack, so cross-dissolves and other transitions apply only to the video beneath.

### 13.8 Sticker on Color/Gap Clips

- Stickers can overlay any clip type (video, image, color, gap).
- The sticker is rendered at the same position regardless of the underlying video content.
- On gap clips (black), stickers still render normally (sticker on black background).

### 13.9 Project Portability (Missing Assets)

- Bundled sticker assets are always available (shipped with the app).
- Imported stickers are stored in the app's Documents directory and included in project export/backup.
- If a project references a sticker that does not exist in the current app version (e.g., sticker removed in an app update), the system falls back to a placeholder.

---

## 14. Performance

### 14.1 Rendering Budget Per Frame

| Component | Budget | Notes |
|-----------|--------|-------|
| Video rendering | 6.6 ms | Standard video decode + display |
| Text rendering (up to 5 clips) | 10 ms | 2ms per text clip |
| Sticker rendering (up to 8 clips) | 3 ms total | ~0.375ms per static sticker |
| Gesture/UI overhead | 0.5 ms | Hit testing, selection handles |
| **Total** | **~20 ms** | Exceeds 16.6ms budget at full load |

**Mitigation for full-load scenarios:**

1. During playback with many overlays, disable selection handles (saves ~0.5ms).
2. During fast scrub, render only static first-frame for animated stickers (saves ~2ms for animated).
3. Animated sticker rendering cost varies: Lottie (~1.5ms), GIF (~0.5ms), Static (~0.2ms).
4. With 8 static stickers, total sticker cost is ~1.6ms, well within budget.
5. With 4 animated Lottie + 4 static, total is ~7.6ms, which combined with text may require reduced text rendering quality during scrub.

### 14.2 Sticker Image Decode Performance

| Asset Type | First Load | Cached Access |
|-----------|-----------|---------------|
| Static PNG (256x256) | ~5ms (background isolate) | < 0.1ms |
| Lottie JSON | ~10ms (parse) | Frame render: ~1.5ms |
| GIF (30 frames) | ~50ms (decode all frames, background) | Frame select: < 0.1ms |

### 14.3 Export Performance Impact

| Scenario | Export Overhead |
|----------|---------------|
| 5 static stickers | < 2% increase in export time |
| 5 animated Lottie stickers | ~5-10% increase (frame pre-rendering) |
| 10+ stickers | ~10-15% increase |

Export overhead is primarily from Lottie pre-rendering (converting Lottie to CGImage sequences). Static stickers add negligible overhead since `CALayer` compositing is GPU-accelerated.

### 14.4 Memory Budget

| Component | Budget | Notes |
|-----------|--------|-------|
| Static sticker image cache | ~8 MB | 30 entries at ~256 KB each |
| GIF frame cache | ~15 MB | 5 GIFs at ~3 MB each |
| Lottie render cache | ~5 MB | 2 seconds of frames per active Lottie |
| Sticker clip data | < 1 MB | ~2 KB per clip, up to 200 clips |
| **Total** | **~29 MB** | Within the 200 MB app memory budget |

---

## 15. Testing Strategy

### 15.1 Unit Tests

| Test File | Coverage |
|-----------|----------|
| `test/models/sticker_clip_test.dart` | StickerClip creation, copyWith, serialization, duration constraints |
| `test/models/sticker_keyframe_test.dart` | StickerKeyframe creation, serialization, interpolation |
| `test/models/sticker_asset_test.dart` | StickerAsset creation, serialization, type detection |
| `test/core/sticker_clip_manager_test.dart` | CRUD operations, undo/redo, multi-track, clip queries |
| `test/core/sticker_favorites_test.dart` | Favorite toggle, persistence, registry integration |
| `test/core/sticker_search_test.dart` | Search by name, keywords, ranking |
| `test/core/sticker_keyframe_interpolation_test.dart` | Interpolation math, edge cases, all easing types |
| `test/core/sticker_import_test.dart` | Import validation, size constraints, file management |

### 15.2 Widget Tests

| Test File | Coverage |
|-----------|----------|
| `test/views/sticker_browser_test.dart` | Category navigation, search, favorites, grid rendering |
| `test/views/sticker_editor_panel_test.dart` | Opacity slider, keyframe list, animation controls |

### 15.3 Integration Tests

| Test File | Coverage |
|-----------|----------|
| `test/integration/sticker_timeline_test.dart` | Sticker placement, trim, split, move on timeline |
| `test/integration/sticker_gesture_test.dart` | Drag, pinch, rotate gestures, snap guides |
| `test/integration/sticker_export_test.dart` | End-to-end export with stickers (verify CALayer output) |

### 15.4 Performance Tests

- Render 8 static stickers at 60fps: verify < 3ms total per frame.
- Render 4 animated Lottie stickers at 60fps: verify < 8ms total per frame.
- Decode 5 GIF stickers simultaneously: verify < 20 MB memory.
- Search 500 stickers with keyword: verify < 5ms response time.
- Load sticker browser with 500 thumbnails: verify < 500ms initial load.

---

## 16. Implementation Plan

### Phase 1: Core Data Models and Registry (3 days)

**Files to create:**
- `lib/models/clips/sticker_clip.dart` - StickerClip model
- `lib/models/sticker/sticker_asset.dart` - StickerAsset model
- `lib/models/sticker/sticker_category.dart` - StickerCategory model
- `lib/models/sticker/sticker_keyframe.dart` - StickerKeyframe model
- `lib/data/sticker_registry.dart` - Asset registry with categories

**Files to modify:**
- `lib/models/clips/timeline_item.dart` - Add `case 'sticker'` to `fromJson`
- `lib/models/clips/clips.dart` - Export `sticker_clip.dart`
- `lib/timeline/data/models/track.dart` - Add `TrackType.sticker`
- `lib/design_system/glass_styles.dart` - Add `clipSticker` color

**Deliverables:**
- All data models with full serialization (toJson/fromJson)
- Complete test suite for all models
- Registry with built-in categories (no assets yet)
- `flutter analyze` passes, `flutter test` passes

### Phase 2: Static Sticker Preview and Placement (4 days)

**Files to create:**
- `lib/core/sticker_clip_manager.dart` - CRUD and track management
- `lib/core/sticker/sticker_image_cache.dart` - Image cache
- `lib/timeline/rendering/painters/sticker_preview_painter.dart` - Preview renderer
- `lib/timeline/rendering/painters/sticker_timeline_painter.dart` - Timeline track renderer

**Deliverables:**
- Add sticker clip to timeline
- Render static stickers over video preview
- Sticker clips visible on timeline tracks
- Undo/redo for sticker operations
- Image caching with LRU eviction

### Phase 3: Gesture Handling (3 days)

**Files to create:**
- `lib/views/sticker/sticker_gesture_handler.dart` - Gesture processing
- `lib/views/sticker/sticker_selection_handles.dart` - Visual handles

**Deliverables:**
- Drag to move stickers on preview
- Pinch to scale stickers
- Two-finger rotate
- Selection handles (corner, rotation, delete)
- Snap guides with haptic feedback
- Hit testing with rotation-aware bounds

### Phase 4: Sticker Browser UI (3 days)

**Files to create:**
- `lib/views/sticker/sticker_browser_view.dart` - Main browser
- `lib/views/sticker/sticker_tile.dart` - Grid tile widget
- `lib/core/sticker_favorites_manager.dart` - Favorites persistence

**Files to create (assets):**
- `assets/stickers/` - Bundled sticker PNG files (initial set of ~50 stickers)
- `assets/stickers/thumbnails/` - Pre-generated thumbnails

**Deliverables:**
- Full sticker browser with CNTabBar categories
- CupertinoSearchTextField search
- Favorites with persistence
- 4-column grid with thumbnails
- Long-press context menu
- iOS 26 Liquid Glass styling throughout

### Phase 5: Sticker Editor Panel (2 days)

**Files to create:**
- `lib/views/sticker/sticker_editor_panel.dart` - Inspector panel

**Deliverables:**
- Opacity slider (CupertinoSlider)
- Duration control
- Flip horizontal/vertical toggles
- Tint color picker
- Context menu integration (copy, delete, bring to front, send to back)

### Phase 6: Keyframe Animations (3 days)

**Files to modify:**
- `lib/views/sticker/sticker_editor_panel.dart` - Add keyframe section

**Deliverables:**
- Add/remove/edit keyframes on sticker clips
- Keyframe interpolation with all 21 easing types
- Keyframe diamonds on timeline clip
- Keyframe recording via gesture interaction
- Interpolation utilities shared with text system

### Phase 7: Animated Sticker Support (4 days)

**Files to create:**
- `lib/core/sticker/lottie_frame_renderer.dart` - Lottie preview rendering
- `lib/core/sticker/gif_frame_cache.dart` - GIF decoding and caching

**Files to create (assets):**
- `assets/stickers/animated/` - Bundled Lottie/GIF files

**Deliverables:**
- Lottie sticker preview rendering (frame-by-frame on canvas)
- GIF sticker preview rendering (decoded frame selection)
- Animation speed and loop controls
- Memory management for animated sticker caches

### Phase 8: Custom Image Import (2 days)

**Files to create:**
- `lib/core/sticker/sticker_import_service.dart` - Import pipeline

**Deliverables:**
- Import PNG/WebP from Files app
- Thumbnail generation
- Dimension validation
- "Imported" category in browser
- Delete imported sticker

### Phase 9: Export Pipeline (4 days)

**Files to create:**
- `ios/Runner/Sticker/StickerLayerBuilder.swift` - CALayer builder
- `ios/Runner/Sticker/StickerExportService.swift` - Export integration
- `ios/Runner/Sticker/LottieExportRenderer.swift` - Lottie to CAKeyframeAnimation
- `ios/Runner/Sticker/GifExportRenderer.swift` - GIF to CAKeyframeAnimation

**Files to modify:**
- `ios/Runner/VideoProcessingService.swift` - Integrate sticker layers
- `ios/Runner/AppDelegate.swift` - Register sticker platform channel

**Deliverables:**
- Static sticker export via CALayer
- Animated sticker export (Lottie + GIF baking)
- Keyframe animation export via CAKeyframeAnimation
- Correct z-ordering with text overlays
- Export accuracy verification (preview matches export)

### Phase 10: Polish and Optimization (2 days)

**Deliverables:**
- Performance profiling and optimization
- Memory pressure handling
- Missing asset placeholders
- Edge case handling (many stickers, large files, boundary conditions)
- Full test suite completion
- Documentation updates (FEATURES.md, DESIGN.md, APP_LOGIC.md)

### Total Estimated Timeline: 30 days

| Phase | Days | Cumulative |
|-------|------|-----------|
| Phase 1: Data Models | 3 | 3 |
| Phase 2: Static Preview | 4 | 7 |
| Phase 3: Gestures | 3 | 10 |
| Phase 4: Browser UI | 3 | 13 |
| Phase 5: Editor Panel | 2 | 15 |
| Phase 6: Keyframes | 3 | 18 |
| Phase 7: Animated | 4 | 22 |
| Phase 8: Import | 2 | 24 |
| Phase 9: Export | 4 | 28 |
| Phase 10: Polish | 2 | 30 |

### Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `lottie` | latest | Lottie animation rendering in Flutter |
| `lottie-ios` (CocoaPod) | latest | Lottie rendering for native export |
| `image` (Dart) | existing | GIF decoding |
| `uuid` | existing | Unique ID generation |
| `cupertino_native_better` | ^1.3.2 | iOS 26 Liquid Glass components |
| `adaptive_platform_ui` | ^0.1.100 | Platform-aware widgets |

### Prerequisites from Other Systems

| System | Requirement | Status |
|--------|------------|--------|
| Timeline V2 | PersistentTimeline generic over TimelineItem | Implemented |
| Timeline V2 | Multi-track support (Track model) | Implemented |
| Text System | InterpolationUtils shared class | Designed (must implement before Phase 6) |
| Text System | TextClipManager overlay track pattern | Designed (template for StickerClipManager) |
| Export | AVVideoCompositionCoreAnimationTool integration | Designed in Text System |
| Design System | Liquid Glass components | Implemented |

---

**Document End**

**Last Updated:** 2026-02-06
**Maintained By:** Development Team

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Senior Architect)
**Date:** 2026-02-06
**Scope:** Full document review against codebase state as of 2026-02-06

---

### Architecture Assessment

**Overall Grade: B+ (Strong design with several issues requiring attention before implementation)**

The Stickers & Overlays design document demonstrates strong architectural alignment with the existing codebase. The dual rendering pipeline, `GeneratorClip` inheritance pattern, and keyframe system reuse are all well-reasoned. The document correctly identifies the parallel structure with the Text & Titles system and leverages existing infrastructure effectively.

The design shows a mature understanding of the codebase, with accurate references to `PersistentTimeline`, `TimelineManager`, `GeneratorClip`, `InterpolationType`, `BezierControlPoints`, `Track`, `TrackType`, `CompositionBuilder`, and `VideoProcessingService`. All referenced code patterns have been verified as accurate.

---

### Codebase Verification

#### 1. StickerClip Model vs. Existing Patterns

**Verified:** `StickerClip extends GeneratorClip` correctly mirrors `ColorClip` and `TextClip`.

- `GeneratorClip` (in `timeline_item.dart` lines 147-162) requires `id` and `durationMicroseconds` via `super` -- `StickerClip` correctly forwards these.
- `itemType` override to `'sticker'` follows the pattern from `ColorClip.itemType => 'color'` (line 35) and `TextClip.itemType => 'text'` (line 109).
- `displayName` override follows the pattern from `ColorClip.displayName => name ?? 'Color'` (line 32).
- Position/rotation/scale/opacity fields mirror `TextClip` (lines 33-43) exactly.
- Keyframes list follows `TextClip.keyframes` pattern (line 64).

**Issue Identified:** `StickerClip` in the design does **not** include `copyWith()`, `duplicate()`, `splitAt()`, `toJson()`, or `fromJson()` methods. Both `ColorClip` and `TextClip` implement all of these. The design shows `StickerClip.fromJson` used in `TimelineItem.fromJson` dispatch but never defines the method body. The `StickerClip` model as shown is incomplete for implementation.

**Issue Identified:** `StickerClip` references `clip.startTimeOnTimeline` (Section 11.1, line 1507) but `TimelineItem` has no such field. Start time is a positional property derived from the tree, not stored on the clip. The export data must compute this externally (e.g., via `PersistentTimeline.startTimeOf(clipId)`), and the design should clarify this.

#### 2. TimelineItem.fromJson Dispatch

**Verified:** The existing `TimelineItem.fromJson` switch statement (in `timeline_item.dart` lines 59-85) does not currently have a `case 'sticker'`. The design correctly identifies this needs to be added. The fallback to `GapClip` for unknown types provides forward compatibility.

**Issue Identified:** The `timeline_item.dart` file imports `text_clip.dart` (line 15) but does not import a hypothetical `sticker_clip.dart`. The import will need to be added alongside the switch case.

#### 3. TrackType Enum

**Verified:** The existing `TrackType` enum (in `track.dart` lines 8-29) does not contain `sticker`. The design correctly identifies this addition.

**Issue Identified:** The `TrackTypeExtension.defaultColor` switch (track.dart lines 34-51) and `displayName` switch (lines 54-71) are exhaustive switches with no `default`. Adding `TrackType.sticker` requires adding cases to **all** extension properties: `defaultColor`, `displayName`, `supportsVideo`, `supportsAudio`, `supportsEffects`, and `supportsText`. The design mentions `defaultColor` but omits the other five properties. A `supportsSticker` property should also be added to the extension.

#### 4. clips.dart Barrel Export

**Verified:** The barrel file (clips.dart) currently exports 6 clip types. It needs `export 'sticker_clip.dart';` added. The design mentions modifying `clips.dart` in Phase 1 but does not explicitly show this line.

#### 5. Dual Rendering Pipeline

**Verified approach is correct.** The video preview in Flutter uses `CustomPainter` compositing, while export uses `AVVideoCompositionCoreAnimationTool`. This is the only viable approach given the architecture:
- Flutter preview requires Flutter-side rendering because the video is in a Flutter texture widget.
- AVFoundation export requires `CALayer` because `AVAssetExportSession` composites via Core Animation.

**Concern:** The design claims "pixel-for-pixel" accuracy between preview and export (Section 1, Goals). This is aspirational but unlikely to be exactly achievable because:
1. Flutter's `Canvas` rendering and Core Animation's `CALayer` rendering use different rasterization engines.
2. Coordinate system differences (Flutter Y-down vs. Core Animation Y-up) create potential for subtle off-by-one positioning.
3. Anti-aliasing and sub-pixel rendering differ between the two pipelines.

A more accurate goal would be "visually equivalent within 1-2 pixel tolerance."

#### 6. Keyframe System Reuse

**Verified:** `TextKeyframe` (in `text_keyframe.dart`) has identical fields to the proposed `StickerKeyframe`: `id`, `timestampMicros`, `position`, `scale`, `rotation`, `opacity`, `interpolation`, `bezierPoints`. Both import from `keyframe.dart` for `InterpolationType` and `BezierControlPoints`.

**The design acknowledges these are identical** and proposes keeping them separate for future divergence (Section 4.4, lines 484-488). This is a reasonable approach, but the document should add a TODO to evaluate consolidation into `OverlayKeyframe` after V1 ships.

#### 7. TimelineManager Integration

**Verified:** `TimelineManager` (in `timeline_manager.dart`) is generic over `TimelineItem` and its `splitAt()` method handles `TextClip` (lines 240-256). **This will need a new `else if (item is StickerClip)` branch.** The design document states "No changes needed to TimelineManager" (Section 9.1, line 1178), which is incorrect -- `splitAt()` requires a new branch for `StickerClip`.

#### 8. StickerClipManager vs. TimelineManager

**Potential architectural conflict:** The design proposes `StickerClipManager` with its own `Map<String, PersistentTimeline>` and per-track undo/redo stacks (Section 9.2). But the existing `TimelineManager` already provides undo/redo. This creates **two parallel undo/redo systems** that are not synchronized.

When a user presses Cmd+Z, which undo fires? If the user added a sticker (tracked by `StickerClipManager`) and then trimmed a video clip (tracked by `TimelineManager`), the undo order across the two managers will be disjoint. The Text system design likely has the same issue (it proposes `TextClipManager` with per-track undo). This needs a **unified undo controller** or clear documentation of the undo scope.

#### 9. glass_styles.dart Missing Sticker Color

**Verified:** `glass_styles.dart` defines clip colors (`clipVideo`, `clipAudio`, `clipImage`, `clipText`, `clipEffect`, `clipGap`, `clipColor`) but does **not** have `clipSticker`. The design correctly identifies this gap (Phase 1 deliverables, line 2163) and proposes `Color(0xFFFF9F0A)` (iOS system orange). However, this conflicts with `clipImage` which is already `Color(0xFFFF9500)` -- these are visually almost identical. Recommend using `Color(0xFFFFD60A)` (iOS system yellow) to differentiate.

#### 10. CompositionBuilder Integration

**Verified:** `CompositionBuilder` (in `CompositionBuilder.swift`) does not currently support sticker segments. Its `SegmentType` enum (line 17) has: video, audio, image, gap, color, silence, offline. The design correctly identifies this gap but proposes integrating stickers at the `VideoProcessingService` level via `AVVideoCompositionCoreAnimationTool` rather than modifying `CompositionBuilder`. This is the correct approach -- stickers are overlays, not timeline segments.

#### 11. VideoProcessingService Export

**Verified:** `VideoProcessingService.swift` uses `AVMutableVideoComposition` with `AVMutableVideoCompositionInstruction` and `AVMutableVideoCompositionLayerInstruction`. Currently it does not use `AVVideoCompositionCoreAnimationTool`.

**Critical finding:** The design proposes adding `AVVideoCompositionCoreAnimationTool` to the export pipeline, but the current `VideoProcessingService` uses `AVAssetExportSession` with `.videoComposition`. When `animationTool` is set on the video composition, `AVAssetExportSession` handles the compositing. However, `AVVideoCompositionCoreAnimationTool` and custom `AVVideoCompositing` protocols (custom compositor) are **mutually exclusive** -- you cannot use both on the same `AVMutableVideoComposition`. The design does not address whether a custom compositor is planned. If effects or color grading use a custom `AVVideoCompositing`, the sticker `CALayer` approach will not work and an alternative (per-frame rendering) will be needed.

---

### Critical Issues

**C1. Missing `splitAt()` in `TimelineManager` for `StickerClip`**

The design states "No changes needed to TimelineManager" but `TimelineManager.splitAt()` has explicit `is VideoClip`, `is GapClip`, `is ColorClip`, `is TextClip` type checks. `StickerClip` will silently fail to split without a new branch. The `StickerClip` class also needs a `splitAt()` method (like `TextClip.splitAt()` which partitions keyframes and handles animation state).

**Severity:** Critical (split operation will silently fail)
**Fix:** Add `StickerClip.splitAt()` method to the model and add `else if (item is StickerClip)` branch in `TimelineManager.splitAt()`.

**C2. Missing Serialization on `StickerClip`**

The `StickerClip` model shown in Section 4.1 lacks `toJson()`, `fromJson()`, `copyWith()`, `duplicate()`, `splitAt()`, `==`, `hashCode`, and `toString()`. All other `GeneratorClip` subclasses implement these. Without serialization, project save/load will break for any project containing stickers. Without `copyWith()`, immutable state updates are impossible.

**Severity:** Critical (model is incomplete for implementation)
**Fix:** Add full serialization, equality, and mutation methods following the `TextClip` pattern.

**C3. `AVVideoCompositionCoreAnimationTool` Compatibility with Custom Compositor**

If the project ever uses a custom `AVVideoCompositing` for effects or color correction, `AVVideoCompositionCoreAnimationTool` cannot be used simultaneously. The design does not address this constraint. If a custom compositor is already planned (e.g., in effects or transition design docs), this is a hard architectural conflict.

**Severity:** Critical (potential architectural dead end)
**Fix:** Add a section acknowledging this limitation. If custom compositor is planned, design a fallback rendering path that composites sticker images per-frame within the custom compositor's `renderPixelBuffer()` method. Alternatively, commit to `AVVideoCompositionCoreAnimationTool` and require all video effects to use `CIFilter` (which is compatible).

**C4. Dual Undo/Redo System**

The `StickerClipManager` proposes per-track `PersistentTimeline` undo/redo stacks independent of `TimelineManager`. This means the user has two uncoordinated undo histories. Combined with the `TextClipManager` design (which presumably has a third), Cmd+Z becomes unpredictable.

**Severity:** Critical (broken UX for undo/redo)
**Fix:** Either (a) route all sticker operations through the existing `TimelineManager` by treating sticker tracks as additional `PersistentTimeline` instances managed by a single undo controller, or (b) implement an `UndoCoordinator` that serializes undo operations across all managers into a single global stack.

---

### Important Issues

**I1. `StickerClip.startTimeOnTimeline` Does Not Exist**

Section 11.1 references `clip.startTimeOnTimeline` and `clip.endTimeOnTimeline` in the platform channel data. `TimelineItem` has no such properties -- start time is computed from tree position via `PersistentTimeline.startTimeOf(clipId)`. The export serialization code must compute these externally before serialization.

**Severity:** Important (will cause compile error)
**Fix:** Replace with `stickerClipManager.startTimeOf(trackId, clipId)` or similar.

**I2. Animation Progress Integer Division Bug**

Section 6.1, the `computeAnimationProgress` function (line 812):
```dart
return (adjustedOffset / animDurationMicros).clamp(0.0, 1.0);
```
This performs integer division in Dart if both operands are `int`, which would always return 0 or 1. The function must use `toDouble()` on one operand:
```dart
return (adjustedOffset / animDurationMicros.toDouble()).clamp(0.0, 1.0);
```
Similarly, line 810 `adjustedOffset % animDurationMicros` works correctly for `int` modulo, but the subsequent division also needs `.toDouble()`.

**Severity:** Important (all non-looping animated stickers will render incorrectly)
**Fix:** Ensure double division in progress calculation.

**I3. GIF Frame Cache Eviction Policy is FIFO, Not LRU**

Section 6.2, `GifFrameCache` (line 841):
```dart
_cache.remove(_cache.keys.first);
```
This is FIFO eviction, not LRU. A GIF that was recently accessed could be evicted if it was loaded first. The document describes the cache as having "LRU eviction" in Section 6.4 but the implementation is FIFO. Use a `LinkedHashMap` with access-order tracking, or move accessed entries to the end.

**Severity:** Important (cache thrashing under common usage patterns)
**Fix:** Use `LinkedHashMap` or track access timestamps for true LRU.

**I4. Missing `InterpolationUtils` Class**

The design references `InterpolationUtils.applyEasing()`, `InterpolationUtils.lerpOffset()`, and `InterpolationUtils.lerpDouble()` (Section 8.2) as a shared utility. However, a glob search for `interpolation_utils` found no files in the codebase. This class does not exist yet.

The Phase 6 prerequisite table (Section 16, line 2331) states "InterpolationUtils shared class - Designed (must implement before Phase 6)". However, the sticker keyframe interpolation code in Section 8.2 uses it directly. This is a hard dependency that must be built before any keyframe features work.

**Severity:** Important (hard dependency on non-existent code)
**Fix:** Either (a) implement `InterpolationUtils` as Phase 1 work or (b) inline the interpolation logic in the sticker system with a TODO to extract it later.

**I5. Performance Budget Exceeds 16.6ms**

Section 14.1 honestly acknowledges that the full-load scenario (video + 5 text + 8 stickers + gestures) totals ~20ms, exceeding the 16.6ms budget for 60 FPS. The proposed mitigations are reasonable but rely on heuristic degradation. With 4 animated Lottie stickers + text, the total reaches ~17.6ms before video rendering.

**Severity:** Important (guaranteed frame drops at full load)
**Fix:** Consider (a) reducing the max simultaneous sticker limit from 8 to 6, (b) making animated sticker frame rendering asynchronous with 1-frame latency, or (c) pre-rendering animated sticker frames to texture on a background thread.

**I6. SVG Support Declared But Not Designed**

`StickerAssetType.svg` exists in the enum (Section 4.2) but there is no SVG rendering code, no SVG decoder, no SVG export path, and no SVG performance budget. SVG rendering in Flutter requires `flutter_svg` or similar, and SVG-to-`CALayer` export is non-trivial.

**Severity:** Important (dead code path that will cause runtime crashes)
**Fix:** Either (a) remove SVG from V1 scope and add to Non-Goals, or (b) design the SVG rendering and export pipeline.

---

### Minor Issues

**M1. Static Sticker Image Cache Uses Map.keys.first for Eviction**

`StickerImageCache` (Section 10.3, line 1447) and `GifFrameCache` (Section 6.2, line 841) both use `_cache.keys.first` for eviction. Standard Dart `Map` does not guarantee insertion order (though `LinkedHashMap`, the default implementation, does). This is fragile and should be documented as relying on `LinkedHashMap` behavior, or should use explicit eviction tracking.

**M2. Hardcoded Search Limit**

Section 5.3 notes "fewer than 500 bundled stickers" as justification for linear search. If imported stickers are added (up to 100 per Section 5.5), the total could reach 600. Still within budget, but the assumption should be revisited if the limit changes.

**M3. Missing Haptic Feedback on Sticker Placement**

Section 7.4 specifies haptic feedback for snap guides, but there is no haptic feedback specified for initial sticker placement (tapping a sticker in the browser to add it). Other similar actions in the project use `HapticFeedback.mediumImpact()`.

**M4. Category Tab Bar Width**

The sticker browser uses 8 categories in a `CNTabBar` (Section 12.2). The CLAUDE.md standard bottom bar pattern specifies `width: 220` for the tab bar, which accommodates 2-3 tabs. With 8 categories, the tab bar must either scroll horizontally or the `shrinkCentered` property must be set differently. The design shows `shrinkCentered: false` which is correct for a full-width tab bar, but the positioning uses `left: 0, right: 0` which differs from the standard `left: 16` pattern.

**M5. Lottie Export Dependency**

The design lists `lottie-ios` (CocoaPod) as a dependency for native export (Section 16, line 2319). The `lottie-ios` library provides `AnimationView` for UIKit but does not natively provide frame-by-frame CGImage extraction. The `LottieExportRenderer` will need to use `AnimationView.render(progress:)` to a `CALayer`, capture the layer to a `CGImage` using `CGContext`, and build the `CAKeyframeAnimation` from those images. This is feasible but the design's pseudocode (Section 6.3) oversimplifies the implementation.

**M6. Missing `@immutable` Annotation on `StickerKeyframe`**

Section 4.4 shows `StickerKeyframe` with `@immutable` but unlike `TextKeyframe`, it does not include `copyWith()`, `==`, `hashCode`, or `toString()`. These are needed for immutable value semantics and for keyframe comparison during undo/redo.

**M7. Tint Color Not Animatable**

Section 4.4 mentions future divergence could include "tint color animation" but `StickerKeyframe` does not include a `tintColorValue` field. If this is desired in the future, adding it later will require keyframe data migration. Consider adding it now as an optional field with null default.

---

### Questions

**Q1.** What is the z-ordering policy when a sticker track and a text track have the same index? The design states track index determines z-order (Section 3.4, Section 10.4) but does not specify a tiebreaker. Recommend: sticker tracks render above text tracks at the same index (stickers are typically foreground elements).

**Q2.** For the export pipeline (Section 11.3), the "correct approach for mixed overlay ordering" shows sorting all overlay layers by track index. How is track index communicated to the Swift side? Currently, the platform channel data (Section 11.1) does not include a `trackIndex` field in the serialized sticker data.

**Q3.** The design proposes `StickerFavoritesManager extends ChangeNotifier` for favorites persistence. Should this be a `ValueNotifier<Set<String>>` instead, to avoid the overhead of a full `ChangeNotifier` for a simple set?

**Q4.** How should sticker clips behave during timeline ripple operations? If a video clip before a sticker clip is deleted, does the sticker clip shift earlier in time (ripple) or stay at its absolute position (overlay behavior)? This depends on whether sticker tracks participate in ripple edits. The design does not specify.

**Q5.** The `StickerAssetRegistry` uses `loadBuiltIn()` as a static factory (Section 5.2). When is this called? Is it during app startup (blocking) or lazy-loaded on first access to the sticker browser? If at startup, it adds to the app launch time budget.

**Q6.** For imported stickers, what happens to the `StickerAsset` entries when the app is updated? The `StickerAssetRegistry` presumably rebuilds from the assets directory on each launch. Are imported sticker metadata persisted separately from the bundled registry?

---

### Positive Observations

**P1. Strong Architectural Alignment:** The design correctly identifies and reuses every relevant existing component (`GeneratorClip`, `PersistentTimeline`, `InterpolationType`, `BezierControlPoints`, `TrackType`, `CompositionBuilder`, `VideoProcessingService`). No unnecessary reinvention.

**P2. Comprehensive Edge Case Coverage:** Section 13 covers many real-world scenarios: many simultaneous stickers, memory pressure, boundary conditions, deleted assets, transitions, gap clips, project portability. This level of forethought prevents bugs.

**P3. Honest Performance Analysis:** Section 14 does not hide the fact that full-load scenarios exceed the 16.6ms frame budget. The mitigations (reduced rendering during fast scrub, animation freeze, handle suppression) are practical.

**P4. Correct Coordinate System Handling:** The `StickerLayerBuilder` Swift code correctly handles Core Animation's Y-flipped coordinate system (`1.0 - position["y"]!`). This is a common source of bugs in Flutter-to-native rendering and the design gets it right.

**P5. Immutable Data Pattern:** `StickerClip`, `StickerAsset`, `StickerCategory`, `StickerKeyframe`, and `StickerRenderData` are all `@immutable`, consistent with the project's persistent data structure architecture.

**P6. Well-Scoped Non-Goals:** The non-goals (Section 1) are well-chosen, deferring 3D transforms, video stickers, AI generation, physics, and drawing tools. This keeps V1 deliverable.

**P7. Phased Implementation Plan:** The 10-phase plan builds incrementally, with data models first and export last. Each phase has clear deliverables and file lists. Dependencies between phases are correctly identified.

**P8. TextClip as Proven Template:** The design explicitly models itself after `TextClip`, which is already implemented and tested. This reduces risk because the patterns are validated.

---

### Checklist Summary

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | `StickerClip extends GeneratorClip` correctly | PASS | Matches `ColorClip` and `TextClip` patterns |
| 2 | `StickerClip` has complete API surface | FAIL | Missing `copyWith`, `toJson`, `fromJson`, `splitAt`, `duplicate`, `==`, `hashCode` |
| 3 | `TimelineItem.fromJson` dispatch accurate | PASS | Correctly identifies needed `case 'sticker'` |
| 4 | `TrackType.sticker` addition complete | PARTIAL | Missing `displayName`, `supportsVideo/Audio/Effects/Text` switch cases |
| 5 | Dual rendering pipeline sound | PASS | Correct approach for Flutter preview + CALayer export |
| 6 | Lottie preview rendering feasible | PASS | `LottieDrawable` frame-by-frame rendering is supported by the `lottie` package |
| 7 | GIF preview rendering feasible | PASS | Frame decoding via `compute()` isolate is appropriate |
| 8 | Gesture hit testing mathematically correct | PASS | Rotation-aware inverse transform is correct |
| 9 | Keyframe interpolation reuses existing infra | PARTIAL | Reuses `InterpolationType` and `BezierControlPoints` but depends on non-existent `InterpolationUtils` |
| 10 | Export pipeline `AVVideoCompositionCoreAnimationTool` | CONCERN | Incompatible with custom `AVVideoCompositing`; no fallback designed |
| 11 | Timeline integration (undo/redo) | FAIL | Dual undo system creates UX conflict with `TimelineManager` |
| 12 | `TimelineManager.splitAt()` updated | FAIL | Design says "no changes needed" but `splitAt()` requires new branch |
| 13 | Memory budget realistic | PASS | 29 MB within 200 MB app budget is reasonable |
| 14 | Performance budget achievable | PARTIAL | Full-load exceeds 16.6ms; mitigations are reasonable but need testing |
| 15 | iOS 26 Liquid Glass compliance | PASS | All UI uses `CNTabBar`, `CNButton.icon`, `CupertinoSearchTextField`, `CupertinoSlider`, `CupertinoSwitch`, `CupertinoContextMenu` |
| 16 | Integration with text system | PASS | Correct overlay layer hierarchy, shared keyframe infra |
| 17 | Missing sticker color in `glass_styles.dart` | IDENTIFIED | Needs `clipSticker` color; proposed orange conflicts with `clipImage` |
| 18 | `clips.dart` barrel export updated | IDENTIFIED | Needs `export 'sticker_clip.dart'` |
| 19 | Test coverage plan complete | PASS | Unit, widget, integration, and performance tests planned |
| 20 | Dependencies identified | PASS | `lottie`, `lottie-ios`, `image`, `uuid`, `cupertino_native_better` |

**Recommendation:** Address all 4 Critical issues (C1-C4) and Important issues I1, I2, I4, I6 before proceeding to implementation. The remaining Important and Minor issues can be addressed during implementation phases.

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Scope:** Implementation viability, cross-system integration risks, R1 issue resolution proposals

---

### Codebase Verification Results

#### V1. StickerClip Model Completeness (R1-C2 Verification)

**R1 identified:** `StickerClip` is missing `toJson()`, `fromJson()`, `copyWith()`, `duplicate()`, `splitAt()`, `==`, `hashCode`, `toString()`.

**Verified: Correct and Critical.** Cross-referencing with the implemented codebase:

| Method | `ColorClip` | `TextClip` | `StickerClip` (Design) | Required? |
|--------|-------------|------------|----------------------|-----------|
| `copyWith()` | Yes (lines 128-140) | Yes (lines 165-217) | **Missing** | **Yes** -- immutable state updates are impossible without it. Every gesture (drag, pinch, rotate) needs `copyWith()` to produce a new clip. |
| `duplicate()` | Yes (lines 143-148) | Yes (lines 220-240) | **Missing** | **Yes** -- copy/paste operation defined in Section 13.5 requires it. |
| `splitAt()` | Yes (lines 151-174) | Yes (lines 254-319) | **Missing** | **Yes** -- `TimelineManager.splitAt()` calls it; R1-C1 confirms this. |
| `toJson()` | Yes (lines 179-185) | Yes (lines 324-345) | **Missing** | **Yes** -- project save breaks without it. |
| `fromJson()` | Yes (lines 188-193) | Yes (lines 351-396) | Referenced but not defined | **Yes** -- `TimelineItem.fromJson` dispatches to it. |
| `==` / `hashCode` | Inherits from `TimelineItem` (ID-based) | Inherits from `TimelineItem` (ID-based) | Inherits from `TimelineItem` | **Adequate** -- `TimelineItem.==` compares by ID (line 88-89), which is sufficient for tree operations. Value equality is not needed. |
| `toString()` | Yes (lines 196-199) | Yes (lines 399-403) | **Missing** | **Useful** for debugging but not blocking. |

**Resolution Proposal:** The `StickerClip` must implement all six methods before Phase 1 is considered complete. The `splitAt()` method for `StickerClip` should follow `TextClip.splitAt()` exactly:
1. Validate offset against `_minSplitDuration` (100ms minimum per half).
2. Partition keyframes by timestamp: left keeps `kf.timestampMicros < offsetMicros`, right re-times keyframes by subtracting `offsetMicros`.
3. Both halves share `stickerAssetId`, `tintColorValue`, `animationSpeed`, `animationLoops`, and flip states.
4. Both halves get new UUIDs.
5. Return `({StickerClip left, StickerClip right})?` using the same record pattern as `TextClip`.

The `copyWith()` method needs careful handling of nullable fields (`name`, `tintColorValue`) using the `clearX = false` pattern from `TextClip.copyWith()`.

#### V2. Export Pipeline Conflict (R1-C3 Verification)

**R1 identified:** `AVVideoCompositionCoreAnimationTool` is incompatible with custom `AVVideoCompositing`.

**Verified: This is now UPGRADED to BLOCKER severity.** The `2026-02-06-multi-track-compositing-design.md` document explicitly plans a custom `AVVideoCompositing` implementation (`MultiTrackCompositor`) for per-frame GPU compositing of multiple video tracks. Key evidence:

1. Section 3.2 of the multi-track design shows `MultiTrackCompositor` implementing the `AVVideoCompositing` protocol, performing per-frame CIFilter-based compositing.
2. Section 3.4 shows the frame rendering flow using `asyncRequest.sourceFrame(byTrackID:)` and `asyncRequest.finish(withComposedVideoFrame:)` -- this is the `AVVideoCompositing` API.
3. Section 1.4 states: "GPU-first rendering. All blending, chroma key, and composition operations run on the GPU via `CIFilter` chains and `AVVideoCompositing` protocol -- never on the CPU."

Apple's documentation is explicit: **`AVVideoCompositionCoreAnimationTool` cannot be set on an `AVMutableVideoComposition` that also uses a custom `AVVideoCompositing` class.** They are mutually exclusive. The current Stickers design relies entirely on `AVVideoCompositionCoreAnimationTool` for export (Sections 11.2, 11.3), which means:

- **If multi-track compositing ships first:** Sticker export as designed will not work. The custom compositor consumes the `AVMutableVideoComposition`, preventing `animationTool` from being set.
- **If stickers ship first:** The `CALayer` export works temporarily, but must be completely rewritten when multi-track compositing is added.
- **Either way, the sticker export design is architecturally doomed.**

**Resolution Proposal -- Two viable alternatives:**

**Alternative A: Render stickers inside the custom compositor (recommended)**

Sticker layers are composited per-frame within the `MultiTrackCompositor.startRequest()` method, alongside video overlay tracks. This means:
1. Sticker images (static, Lottie frame, GIF frame) are pre-decoded to `CIImage` or `CGImage`.
2. At each frame, the compositor queries which stickers are visible at the current time.
3. Each sticker is composited onto the output `CVPixelBuffer` using `CIFilter` chains (`CIAffineTransform` for position/scale/rotation, `CIColorMatrix` for opacity/tint).
4. Sticker keyframe interpolation runs on the Swift side (port `InterpolationUtils` logic or pass pre-computed per-frame transforms from Flutter).

**Pros:** Unified compositing path for all overlay types. Consistent with multi-track architecture. Blend modes and chroma key "just work" on stickers too.
**Cons:** Per-frame sticker compositing is more expensive than `CALayer` (which is hardware-optimized by Core Animation). Lottie rendering per-frame on the compositor thread adds latency.

**Alternative B: Two-pass export**

1. First pass: Export video with multi-track compositing using custom `AVVideoCompositing` (no stickers).
2. Second pass: Re-encode the first-pass output with `AVVideoCompositionCoreAnimationTool` adding sticker `CALayer`s on top.

**Pros:** Sticker export code as designed works unchanged.
**Cons:** Double encoding degrades quality (generation loss). Double the export time. Intermediate file uses significant disk space. This is not a viable production approach.

**Recommendation:** Alternative A is the only architecturally sound path. The design should be revised to integrate sticker rendering into the custom compositor pipeline. This changes Phase 9 significantly: instead of `StickerLayerBuilder` creating `CALayer` objects, it becomes `StickerCompositorRenderer` that provides `CIImage` objects to the compositor per-frame.

#### V3. Dual Undo System (R1-C4 Verification)

**R1 identified:** `StickerClipManager` has its own undo/redo stacks independent of `TimelineManager`.

**Verified: Confirmed critical. The multi-track design resolves this, but the sticker design contradicts it.**

The `MultiTrackTimelineManager` proposed in `2026-02-06-multi-track-compositing-design.md` (Section 3.2, lines 185-198) is designed to be the **single unified undo controller** for all tracks. It wraps a `MultiTrackState` containing `Map<String, PersistentTimeline>` and performs O(1) undo/redo by swapping the entire `MultiTrackState` pointer.

However, the Sticker design (Section 9.2) proposes `StickerClipManager` with its own `Map<String, PersistentTimeline> _stickerTimelines` and per-track undo/redo stacks. This is **exactly the pattern that `MultiTrackTimelineManager` is designed to replace**.

The existing `TimelineManager` (in `lib/core/timeline_manager.dart`) is a single-track manager wrapping one `PersistentTimeline`. It has no concept of multiple tracks. The `splitAt()` method (lines 191-257) is the only place with explicit type checks per clip type.

**Resolution Proposal -- Unified approach:**

1. **Do not create `StickerClipManager` with its own undo stacks.** Instead, use `MultiTrackTimelineManager` as the single source of truth for all track data (main video, overlay video, text, sticker).
2. If `MultiTrackTimelineManager` is not yet implemented, create a lightweight `StickerClipManager` that delegates mutations to a shared undo coordinator rather than maintaining its own stacks. This manager becomes a convenience facade, not a state owner.
3. When `MultiTrackTimelineManager` ships, `StickerClipManager` becomes a thin query layer that reads from the multi-track state and translates sticker-specific operations (add sticker, update position, etc.) into generic `insertClipOnTrack()` / `updateClipOnTrack()` calls.
4. Undo/redo is handled exclusively by `MultiTrackTimelineManager`, which swaps the entire `MultiTrackState` (including all sticker tracks) atomically.

**Implementation dependency:** This means `MultiTrackTimelineManager` (or at minimum, a multi-track state container with unified undo) must be implemented before or concurrently with Phase 2 of the sticker system. The sticker implementation plan should add this as a Phase 0 prerequisite.

#### V4. TextClip Alignment Verification

**Verified: StickerClip is closely aligned with TextClip but has several gaps.**

Detailed comparison of `TextClip` (fully implemented, 405 lines) vs. proposed `StickerClip`:

| Feature | `TextClip` | `StickerClip` (Design) | Gap |
|---------|-----------|----------------------|-----|
| Extends `GeneratorClip` | Yes | Yes | None |
| `@immutable` | Yes | Yes | None |
| Position/rotation/scale/opacity | Yes (lines 33-43) | Yes | None |
| Keyframes list | `List<TextKeyframe>` (line 64) | `List<StickerKeyframe>` | None |
| `hasKeyframes` getter | Yes (line 113) | Yes | None |
| `sortedKeyframes` getter | Yes (lines 118-122) | **Missing** | Need `sortedKeyframes` for interpolation code to work on unsorted input |
| `copyWith()` with `clearX` params | Yes (lines 165-217) | **Missing** | Needed for nullable field handling (`name`, `tintColorValue`) |
| `duplicate()` | Yes (lines 220-240) | **Missing** | Needed for copy/paste |
| `splitAt()` with keyframe partitioning | Yes (lines 254-319) | **Missing** | Needed for split operation |
| `toJson()` / `fromJson()` | Yes (lines 324-396) | **Missing** | Needed for project persistence |
| Factory constructors | `TextClip.subtitle()` (line 136) | None needed | N/A |
| `shortLabel` for timeline UI | Yes (lines 126-131) | **Missing** | Sticker clips should show sticker name in timeline |
| `toString()` | Yes (lines 399-403) | **Missing** | Debugging aid |
| Enter/exit/sustain animations | Yes (3 presets) | Not applicable (uses keyframes only) | Correct -- stickers use keyframes rather than preset animations |
| `templateId` | Yes | Not applicable | Correct |
| `isSubtitle` | Yes | Not applicable | Correct |
| `textAlign` / `maxWidthFraction` | Yes | Not applicable | Correct |

**Additional fields unique to StickerClip not in TextClip:**
- `stickerAssetId` (required)
- `isFlippedHorizontally` / `isFlippedVertically`
- `tintColorValue` (nullable int)
- `animationSpeed`
- `animationLoops`

These are all appropriate additions. The design correctly identifies sticker-specific properties while maintaining the shared overlay clip structure.

#### V5. Lottie Export Memory and Performance Analysis

**R1 flagged (M5):** `lottie-ios` does not natively provide frame-by-frame CGImage extraction. The `LottieExportRenderer` must render to `CALayer`, capture via `CGContext`, then build `CAKeyframeAnimation`.

**Deep analysis of the pre-rendering approach:**

Under the current design (using `CAKeyframeAnimation` with pre-rendered CGImages), the memory cost for a single Lottie sticker during export:

| Parameter | Value |
|-----------|-------|
| Lottie render size | 256x256 at export resolution (scaled by `videoSize.height / 1080.0`) |
| At 1080p export | 256x256 pixels = 256 KB per frame (RGBA) |
| At 4K export | 512x512 pixels (2x scale) = 1 MB per frame |
| Lottie typical frame rate | 30fps |
| Typical animation duration | 2 seconds |
| Frames per animation cycle | 60 frames |
| Memory per Lottie at 1080p | 60 x 256 KB = **15 MB** |
| Memory per Lottie at 4K | 60 x 1 MB = **60 MB** |

With 5 animated Lottie stickers at 4K export: **300 MB** just for the pre-rendered frame arrays. This exceeds the 200 MB app memory budget on its own.

**However, this analysis assumes the `CAKeyframeAnimation` approach (R1's assumption).** Under the revised Alternative A compositor approach, frames are rendered on-demand per compositor frame, which keeps memory to O(1) per sticker (one frame at a time). This is another argument for Alternative A.

If `CAKeyframeAnimation` is retained for any reason, mitigations:
1. Render at reduced resolution (128x128 for preview-quality stickers) and let `CALayer.contentsGravity` upscale.
2. Pre-render in chunks: render 30 frames, add to animation, release, render next 30.
3. Use `CVPixelBuffer` pool rather than `CGImage` array to reduce memory overhead.
4. Limit concurrent Lottie pre-rendering to 1 sticker at a time (sequential, not parallel).

#### V6. Multi-Track Compositing Integration Assessment

**This is the central cross-system integration risk.**

The multi-track compositing design (`2026-02-06-multi-track-compositing-design.md`) establishes:

1. **`MultiTrackState`** as the top-level state container, with `Map<String, PersistentTimeline>` per track.
2. **`MultiTrackTimelineManager`** as the unified undo/redo controller.
3. **`MultiTrackCompositor` (Swift, `AVVideoCompositing`)** as the per-frame GPU compositor.
4. **Track ordering via `trackOrder: List<String>`** determines z-order (bottom to top).

The sticker system integrates at these points:

| Integration Point | Sticker Design | Multi-Track Design | Conflict? |
|-------------------|---------------|-------------------|-----------|
| State container | `StickerClipManager._stickerTimelines` (own map) | `MultiTrackState.timelines` (shared map) | **Yes** -- two maps of timelines |
| Undo/redo | `StickerClipManager._undoStacks` (per-track) | `MultiTrackTimelineManager._undoStack` (global) | **Yes** -- two undo systems |
| Track type | `TrackType.sticker` (proposed new enum value) | Uses existing `TrackType.overlayVideo` and `TrackType.text` | **Partial** -- sticker needs its own type, multi-track design doesn't mention it |
| Z-ordering | Track index from `Track.index` | `MultiTrackState.trackOrder` list | **Compatible** -- track index maps to position in trackOrder |
| Export compositor | `AVVideoCompositionCoreAnimationTool` + `CALayer` | `AVVideoCompositing` custom compositor | **Fatal conflict** -- mutually exclusive APIs |
| Preview rendering | `StickerPreviewPainter` (Flutter `CustomPainter`) | Multi-track design uses Flutter-side compositing for preview too | **Compatible** -- both use Flutter-side rendering for preview |

**Resolution:** The sticker system must be designed as a "track type plugin" within the multi-track architecture rather than a standalone subsystem. Specifically:

1. `TrackType.sticker` is added to the enum (as proposed).
2. Sticker tracks participate in `MultiTrackState.timelines` and `MultiTrackState.trackOrder`.
3. The `MultiTrackCompositor` has a sticker rendering branch that loads sticker images and composites them per-frame, alongside video overlay compositing.
4. `StickerClipManager` becomes a query/mutation facade over `MultiTrackTimelineManager`, not a state owner.

#### V7. Performance Budget Reality Check

**R1 flagged (I5):** Full-load scenario totals ~20ms, exceeding the 16.6ms budget.

**More detailed analysis with codebase context:**

The performance table in Section 14.1 combines video rendering (6.6ms), text rendering (10ms for 5 clips), sticker rendering (3ms for 8 clips), and gesture overhead (0.5ms) into a single 20ms total. This is misleading because it assumes all three overlay systems are at maximum load simultaneously, which is an extreme edge case.

**Realistic scenarios:**

| Scenario | Video | Text | Stickers | Gestures | Total | Within Budget? |
|----------|-------|------|----------|----------|-------|----------------|
| Normal editing (1 text, 2 stickers) | 6.6ms | 2ms | 0.8ms | 0.5ms | 9.9ms | Yes |
| Title sequence (3 texts, 0 stickers) | 6.6ms | 6ms | 0ms | 0.5ms | 13.1ms | Yes |
| Sticker-heavy (0 text, 6 static stickers) | 6.6ms | 0ms | 1.2ms | 0.5ms | 8.3ms | Yes |
| Mixed heavy (3 texts, 4 stickers, 2 animated) | 6.6ms | 6ms | 3.5ms | 0.5ms | 16.6ms | Marginal |
| Absolute maximum (5 texts, 4 Lottie, 4 static) | 6.6ms | 10ms | 7.6ms | 0.5ms | 24.7ms | No |

The absolute maximum scenario is unrealistic in practice. The "mixed heavy" scenario is the realistic worst case and sits exactly at the 16.6ms boundary.

**Recommendation:** Keep the 8-sticker maximum but implement a **dynamic quality tier** system:
- **Tier 1 (< 8ms overlay budget remaining):** Full quality -- all stickers rendered at native resolution, animated stickers at full frame rate.
- **Tier 2 (< 4ms overlay budget remaining):** Reduced quality -- animated stickers at half frame rate, hit test handles suppressed during playback.
- **Tier 3 (< 2ms overlay budget remaining):** Minimal quality -- all animated stickers frozen at current frame, non-selected stickers rendered at 50% resolution.

The tier selection should be based on a rolling average of recent frame times measured via `Stopwatch`, not on static counts.

---

### Integration Risk Assessment

| Risk | Severity | Probability | Impact | Mitigation |
|------|----------|-------------|--------|------------|
| Export pipeline incompatibility (CAAnimationTool vs custom compositor) | **BLOCKER** | 100% if multi-track ships | Export breaks completely | Redesign export to use per-frame compositor rendering (Alternative A) |
| Dual undo system causing user confusion | **Critical** | 100% | Unpredictable Cmd+Z behavior | Unify under `MultiTrackTimelineManager`; do not ship independent sticker undo |
| `StickerClip` model incompleteness | **Critical** | 100% | Cannot save/load projects, cannot split clips | Implement full API surface before Phase 1 completion |
| Lottie pre-rendering memory at 4K | **High** | Likely with 3+ animated stickers | OOM crash during export | Use per-frame rendering in compositor, or render at capped resolution |
| `InterpolationUtils` dependency on non-existent code | **High** | 100% | Keyframe animation compilation failure | Implement `InterpolationUtils` as Phase 0 prerequisite |
| `Track.fromJson` fails on unknown `TrackType.sticker` | **Medium** | When loading old projects on new app | Crash on project load | `Track.fromJson` uses `firstWhere` without `orElse` (line 276) -- will throw if `sticker` is not in enum. Add `orElse` fallback. |
| Integer division bug in animation progress | **Medium** | 100% for non-looping stickers | Sticker renders first or last frame only | Use `.toDouble()` as R1-I2 specifies |
| SVG rendering dead path | **Medium** | First time user selects SVG asset type | Runtime crash or silent failure | Remove `StickerAssetType.svg` from V1; add to future scope |

---

### Critical Findings

#### CF1. Export Architecture Must Be Redesigned (BLOCKER)

**This is the single most important finding of this review.**

The Stickers design and the Multi-Track Compositing design are architecturally incompatible on the export path. Both cannot ship as designed. The resolution requires one of:

1. **Commit to custom compositor for all overlay rendering (recommended).** Text overlays, stickers, and video overlays all render within the `MultiTrackCompositor.startRequest()` per-frame pipeline. This is consistent, extensible, and avoids the `CALayer` limitation entirely. It means the Text & Titles system export design also needs revision (same `AVVideoCompositionCoreAnimationTool` conflict).

2. **Ship stickers before multi-track and accept a rewrite.** Stickers ship with `CALayer` export. When multi-track compositing ships, sticker export is rewritten to use the custom compositor. This wastes Phase 9 work (4 days) entirely.

3. **Use a hybrid approach.** The custom compositor handles video track compositing. After the compositor produces its output, a second `AVVideoComposition` pass adds `CALayer` overlays via `AVVideoCompositionCoreAnimationTool`. This requires two encoding passes and introduces quality loss.

**Recommendation:** Option 1. Design all overlay export (text + stickers) around the custom compositor from the start. Revise Phase 9 of this document and the corresponding Text & Titles export design accordingly.

#### CF2. Unified Undo System Is a Prerequisite (Critical)

The `StickerClipManager` must not own its own undo stacks. The multi-track design's `MultiTrackTimelineManager` should be implemented first (even if only supporting main video + sticker tracks initially) to serve as the single undo controller.

If `MultiTrackTimelineManager` cannot be implemented first, the minimum viable approach is:
1. `StickerClipManager` holds sticker `PersistentTimeline` instances but does NOT maintain undo stacks.
2. A shared `UndoCoordinator` wraps both `TimelineManager` (main track) and `StickerClipManager` (sticker tracks), serializing all mutations into a single ordered undo stack.
3. Each undo entry records which manager to call `restore()` on and the previous state pointer.

This is more complex than just implementing `MultiTrackTimelineManager`, which is why the latter is recommended.

#### CF3. StickerClip Model Completeness Blocks Phase 1 (Critical)

The `StickerClip` model as designed cannot be used in the persistent timeline without `toJson()`/`fromJson()` (project persistence), `copyWith()` (immutable updates), `splitAt()` (timeline split operation), and `duplicate()` (copy/paste). Additionally, `StickerKeyframe` needs `copyWith()`, `toJson()`/`fromJson()`, `==`/`hashCode`, and `toString()` -- exactly matching the implemented `TextKeyframe`.

**Action:** Write complete `StickerClip` and `StickerKeyframe` implementations following `TextClip` and `TextKeyframe` as templates. The gap is well-defined: every method in `TextClip` that is not text-specific needs a sticker equivalent.

---

### Important Findings

#### IF1. `Track.fromJson` Will Crash on Unknown TrackType

The current `Track.fromJson()` (in `track.dart` line 276):
```dart
type: TrackType.values.firstWhere((t) => t.name == json['type']),
```
This uses `firstWhere` without an `orElse` callback. If a project saved with `TrackType.sticker` is loaded on an older app version that does not have the `sticker` enum value, this throws a `StateError`. The `TimelineItem.fromJson` already handles this gracefully with a fallback to `GapClip`, but `Track.fromJson` does not.

**Fix:** Add `orElse: () => TrackType.effect` (or a sensible default) to `Track.fromJson`, matching the forward-compatibility pattern used by `TimelineItem.fromJson`.

#### IF2. TrackType Extension Exhaustive Switch Statements

Adding `TrackType.sticker` requires updating ALL six extension properties in `TrackTypeExtension`:
1. `defaultColor` -- add sticker color (use `Color(0xFFFFD60A)` / iOS system yellow, per R1's recommendation to avoid collision with `clipImage`'s orange `0xFFFF9500`)
2. `displayName` -- return `'Sticker'`
3. `supportsVideo` -- return `false`
4. `supportsAudio` -- return `false`
5. `supportsEffects` -- return `false`
6. `supportsText` -- return `false`

Additionally, add a new `supportsSticker` property:
```dart
bool get supportsSticker => this == TrackType.sticker;
```

Without updating all six, Dart's exhaustive switch will produce a compile-time error, blocking the build.

#### IF3. StickerClip Has No `startTimeOnTimeline` Property (R1-I1 Confirmation)

Confirmed. `TimelineItem` has `id` and `durationMicroseconds` but no positional properties. Start time is computed from tree position. The export serialization in Section 11.1 references `clip.startTimeOnTimeline` and `clip.endTimeOnTimeline`, which do not exist.

**Fix:** The export serialization must compute start times externally:
```dart
for (final trackId in stickerTrackIds) {
  final timeline = multiTrackState.timelines[trackId]!;
  for (final clip in timeline.toList()) {
    final startMicros = timeline.startTimeOf(clip.id) ?? 0;
    final endMicros = startMicros + clip.durationMicroseconds;
    stickerLayers.add({
      // ...clip properties...
      'startMicros': startMicros,
      'endMicros': endMicros,
      'trackIndex': multiTrackState.trackOrder.indexOf(trackId),
    });
  }
}
```

#### IF4. Lottie Frame Rendering in Custom Compositor Has Threading Constraints

If the export is redesigned to use the custom compositor (CF1, Alternative A), Lottie rendering must happen on the compositor's rendering thread. The `lottie-ios` library's `AnimationView` is UIKit-based and must render on the main thread. This creates a thread-safety issue.

**Resolution:** Pre-render Lottie frames to a `[CFTimeInterval: CGImage]` dictionary before export begins (on the main thread), then look up frames by time in the compositor thread (thread-safe read). This is a form of the "pre-rendering" approach but done once upfront rather than stored as `CAKeyframeAnimation` values.

Memory impact: same as V5 analysis above. Mitigate with resolution capping and chunked rendering.

#### IF5. Sticker Tracks and Ripple Edit Behavior (R1-Q4)

R1 asked: do sticker clips ripple when underlying video clips are deleted?

**Analysis from codebase:** The current `TimelineManager.remove()` (line 165) operates on a single `PersistentTimeline`. It does not notify or adjust other tracks. The multi-track design's `MultiTrackTimelineManager` also does not mention cross-track ripple.

**Recommendation:** Sticker tracks should NOT ripple. Stickers are positioned at absolute timeline times (like markers), not relative to video clips. If a 5-second video clip at t=10s is deleted and the main track ripples, sticker clips on overlay tracks should remain at their absolute positions. This is consistent with professional NLE behavior (Final Cut Pro, DaVinci Resolve) where overlay tracks are independent of main track ripple.

This should be documented explicitly in the design as it affects user expectations.

---

### Action Items for Review 3

| # | Action | Owner | Priority | Blocks |
|---|--------|-------|----------|--------|
| 1 | **Redesign export pipeline** to use custom compositor for sticker rendering instead of `AVVideoCompositionCoreAnimationTool`. Update Section 11 and Phase 9. Coordinate with Text & Titles export design. | Design Team | **BLOCKER** | Phase 9 |
| 2 | **Add complete `StickerClip` implementation** to Section 4.1: `copyWith()`, `duplicate()`, `splitAt()`, `toJson()`, `fromJson()`, `toString()`, and `shortLabel`. Follow `TextClip` template exactly. | Design Team | Critical | Phase 1 |
| 3 | **Add complete `StickerKeyframe` implementation** to Section 4.4: `copyWith()`, `toJson()`, `fromJson()`, `==`, `hashCode`, `toString()`. Follow `TextKeyframe` template exactly. | Design Team | Critical | Phase 1 |
| 4 | **Replace `StickerClipManager` undo/redo** with delegation to `MultiTrackTimelineManager` or shared `UndoCoordinator`. Remove per-track undo stacks from Section 9.2. | Design Team | Critical | Phase 2 |
| 5 | **Add `StickerClip` branch to `TimelineManager.splitAt()`** or document that split operations route through `MultiTrackTimelineManager`. Update Section 9.1 to remove "no changes needed" claim. | Design Team | Critical | Phase 2 |
| 6 | **Add `orElse` fallback to `Track.fromJson`** for forward compatibility with unknown `TrackType` values. | Implementation | Important | Phase 1 |
| 7 | **Document all `TrackTypeExtension` changes** needed for `TrackType.sticker` (6 switch cases + new `supportsSticker`). Update Section 4.1. | Design Team | Important | Phase 1 |
| 8 | **Fix `startTimeOnTimeline` reference** in Section 11.1 export serialization. Replace with external start time computation via `PersistentTimeline.startTimeOf()`. | Design Team | Important | Phase 9 |
| 9 | **Remove `StickerAssetType.svg`** from V1 scope. Add to Non-Goals. Or provide complete SVG rendering + export design. | Design Team | Important | Phase 1 |
| 10 | **Add Lottie export memory budget** analysis for 4K scenarios. Cap pre-render resolution at 512x512 regardless of export resolution. Document the quality tradeoff. | Design Team | Important | Phase 9 |
| 11 | **Fix integer division bug** in `computeAnimationProgress` (Section 6.1). Use `.toDouble()`. | Design Team | Important | Phase 7 |
| 12 | **Fix GIF cache eviction** from FIFO to LRU. Use `LinkedHashMap` with access-order tracking. | Design Team | Minor | Phase 7 |
| 13 | **Document non-ripple behavior** for sticker tracks explicitly in Section 9. | Design Team | Minor | Phase 2 |
| 14 | **Add `sortedKeyframes` getter** to `StickerClip` matching `TextClip.sortedKeyframes`. | Design Team | Minor | Phase 6 |
| 15 | **Verify `InterpolationUtils` implementation timeline.** It is a hard dependency for Phase 6. Either implement it as Phase 0 or inline the logic. | Implementation | Important | Phase 6 |
| 16 | **Add `trackIndex` to platform channel sticker data** for correct z-ordering in mixed text+sticker overlay export (R1-Q2). | Design Team | Important | Phase 9 |

**Review 3 Focus Recommendation:** Review 3 should verify the revised export architecture (after CF1 is addressed), validate the unified undo design, and perform a final API surface audit comparing `StickerClip` / `StickerKeyframe` to their `TextClip` / `TextKeyframe` counterparts line-by-line.

---

## Review 3: Final Implementation Readiness Sign-off

**Reviewer:** Claude (Auto-Review Round 3)
**Date:** 2026-02-06
**Verdict:** CONDITIONAL GO

---

### R1/R2 Issue Resolution Status

All critical and important issues from R1 and R2 are reviewed below for whether each has a clear, actionable mitigation plan.

#### Critical Issues

| ID | Issue | Mitigation Plan? | Status |
|----|-------|------------------|--------|
| R1-C1 | Missing `splitAt()` in `TimelineManager` for `StickerClip` | **Yes.** R2 confirms and specifies: add `StickerClip.splitAt()` method (partitioning keyframes, same record return pattern as `TextClip`) and add `else if (item is StickerClip)` branch to `TimelineManager.splitAt()`. Alternatively, route through `MultiTrackTimelineManager` when available. Clear path. | RESOLVED (plan exists) |
| R1-C2 | Missing serialization/mutation methods on `StickerClip` | **Yes.** R2-V1 provides a complete gap analysis table and specifies every missing method (`copyWith`, `duplicate`, `splitAt`, `toJson`, `fromJson`, `toString`, `shortLabel`) with the exact `TextClip` lines to template from. R2-CF3 reaffirms this blocks Phase 1. Clear implementation template. | RESOLVED (plan exists) |
| R1-C3 | `AVVideoCompositionCoreAnimationTool` incompatible with custom `AVVideoCompositing` | **Yes.** R2-CF1 upgrades to BLOCKER and provides two alternatives. Alternative A (render stickers inside custom compositor per-frame) is recommended and architecturally sound. R2-V2 confirms the multi-track design explicitly uses `AVVideoCompositing`, making the conflict 100% certain. The mitigation is well-defined: replace `StickerLayerBuilder` (CALayer-based) with `StickerCompositorRenderer` (CIImage-based per-frame rendering). | RESOLVED (redesign path defined) |
| R1-C4 | Dual undo/redo system | **Yes.** R2-V3 provides a concrete resolution: `StickerClipManager` must not own undo stacks. Use `MultiTrackTimelineManager` as single undo controller. If that is not yet available, use a lightweight `UndoCoordinator` facade. R2-CF2 reaffirms this and recommends implementing `MultiTrackTimelineManager` as a Phase 0 prerequisite. Clear architecture. | RESOLVED (plan exists) |

#### Important Issues

| ID | Issue | Mitigation Plan? | Status |
|----|-------|------------------|--------|
| R1-I1 | `startTimeOnTimeline` does not exist on `TimelineItem` | **Yes.** R2-IF3 provides exact replacement code using `timeline.startTimeOf(clip.id)`. | RESOLVED |
| R1-I2 | Integer division bug in `computeAnimationProgress` | **Yes.** Both R1 and R2 specify the fix: use `.toDouble()`. Trivial code fix. | RESOLVED |
| R1-I3 | GIF cache FIFO vs LRU mismatch | **Yes.** R2 Action Item #12 specifies using `LinkedHashMap` with access-order. | RESOLVED |
| R1-I4 | Missing `InterpolationUtils` class | **Yes.** R2 Action Item #15 flags this as a hard Phase 6 dependency. Resolution: implement as Phase 0 or inline. | RESOLVED (path defined, but see Condition #3 below) |
| R1-I5 | Performance budget exceeds 16.6ms at full load | **Yes.** R2-V7 provides detailed realistic scenario analysis showing that typical cases fit within budget. Full-load is an extreme edge case. R2 proposes a dynamic quality tier system (3 tiers based on rolling frame time average). | RESOLVED (acceptable with dynamic degradation) |
| R1-I6 | SVG support declared but not designed | **Yes.** R2 Action Item #9 recommends removal from V1. | RESOLVED |
| R2-IF1 | `Track.fromJson` crashes on unknown `TrackType` | **Yes.** R2 Action Item #6 specifies adding `orElse` fallback. | RESOLVED |
| R2-IF2 | `TrackTypeExtension` exhaustive switch needs 6+ updates | **Yes.** R2 Action Item #7 enumerates all six properties plus new `supportsSticker`. | RESOLVED |
| R2-IF4 | Lottie threading constraints in custom compositor | **Yes.** R2 proposes pre-rendering Lottie frames to `[CFTimeInterval: CGImage]` dictionary on main thread before export, then thread-safe lookups during compositing. | RESOLVED |
| R2-IF5 | Sticker track ripple behavior undefined | **Yes.** R2 recommends non-ripple (absolute positioning), consistent with professional NLEs. | RESOLVED |

**Summary:** All 4 critical issues and all 10 important issues have concrete mitigation plans. None remain unaddressed.

---

### Codebase Verification

I read the following source files and verified the design's claims against actual implementation:

#### 1. `lib/models/clips/timeline_item.dart` (163 lines)

- **Confirmed:** `TimelineItem` is abstract with `id`, `durationMicroseconds`, `displayName`, `itemType`, `toJson()`, and `fromJson()` dispatch.
- **Confirmed:** `fromJson` switch (lines 62-84) currently handles `video`, `image`, `audio`, `gap`, `color`, `text`. Adding `case 'sticker'` is straightforward -- one line plus an import.
- **Confirmed:** `GeneratorClip` (lines 147-162) is the correct base class. It takes `id` and `durationMicroseconds` via `super`. The `StickerClip` design correctly extends this.
- **Confirmed:** Equality is ID-based (lines 88-92), inherited by all subclasses. `StickerClip` does not need custom `==`/`hashCode` unless value equality is required (it is not for tree operations).

#### 2. `lib/models/clips/text_clip.dart` (405 lines)

- **Confirmed:** `TextClip extends GeneratorClip` with position/rotation/scale/opacity fields (lines 33-43), `List<TextKeyframe> keyframes` (line 64), `hasKeyframes` getter (line 113), `sortedKeyframes` getter (lines 118-122), `copyWith()` with `clearX` pattern for nullable fields (lines 165-217), `duplicate()` (lines 220-240), `splitAt()` with keyframe partitioning (lines 254-319), `toJson()`/`fromJson()` (lines 324-396), and `toString()` (lines 399-403).
- **Confirmed:** This is a complete, production-quality template for `StickerClip`. Every non-text-specific method maps directly to a sticker equivalent. The implementation gap is purely mechanical -- no design ambiguity exists.

#### 3. `lib/models/clips/color_clip.dart` (201 lines)

- **Confirmed:** `ColorClip extends GeneratorClip` is the simpler pattern without keyframes. Has `copyWith()`, `duplicate()`, `splitAt()`, `toJson()`/`fromJson()`, `toString()`. The `splitAt()` is simpler than `TextClip` (no keyframe partitioning). `StickerClip.splitAt()` must follow the `TextClip` pattern (with keyframe partitioning), not `ColorClip`.

#### 4. `lib/core/timeline_manager.dart` (449 lines)

- **Confirmed:** `TimelineManager` wraps a single `PersistentTimeline` with undo/redo stacks (lines 22-28). The `_execute()` method (lines 119-138) pushes current state to undo stack, clears redo, applies mutation, sets dirty flag.
- **Confirmed:** `splitAt()` (lines 191-257) has explicit type checks: `is VideoClip`, `is GapClip`, `is ColorClip`, `is TextClip`. There is no `default` branch or generic handler. A `StickerClip` will silently be ignored without a new branch.
- **Confirmed:** The `addKeyframe` and `removeKeyframe` methods (lines 288-307) are hardcoded to `VideoClip`. Sticker keyframe operations will need to go through `updateItem()` (line 181) with a new `StickerClip` produced via `copyWith(keyframes: ...)`, not through dedicated keyframe methods. This is viable but should be noted.
- **Key observation:** `TimelineManager` manages ONE `PersistentTimeline`. It has no concept of multiple tracks. This confirms R2-V3's finding that `StickerClipManager` with its own timeline map creates a parallel state system. The multi-track architecture is necessary.

#### 5. `ios/Runner/VideoProcessingService.swift` (912 lines)

- **Confirmed:** Currently uses `AVAssetExportSession` with `AVMutableVideoComposition` for export. Does NOT use `AVVideoCompositionCoreAnimationTool`. Does NOT use a custom `AVVideoCompositing`.
- **Confirmed:** The `renderComposition()` method (lines 335-550) builds a multi-clip composition with per-clip keyframe transforms using `AVMutableVideoCompositionLayerInstruction`. This is the standard `AVFoundation` pipeline.
- **Confirmed:** Adding `AVVideoCompositionCoreAnimationTool` to the existing export pipeline IS technically possible today (before multi-track compositing ships), because neither `animationTool` nor custom `AVVideoCompositing` is currently set. However, this would create a known rewrite burden when multi-track ships.
- **Key observation for export redesign:** The `VideoProcessingService` exposes Flutter results via `FlutterResult` callbacks and progress via `EventSinkProvider`. The sticker export integration must maintain these patterns regardless of whether it uses `CALayer` or per-frame compositor rendering.

#### 6. `lib/models/persistent_timeline.dart` (425 lines)

- **Confirmed:** `PersistentTimeline` is fully generic over `TimelineItem`. It uses `item.durationMicroseconds` for subtree duration (via `TimelineNode`). It has `insertAt()`, `append()`, `remove()`, `updateItem()`, `itemAtTime()`, `startTimeOf()`, `getById()`, `containsId()`, `toList()`, `toJson()`, `fromJson()`.
- **Confirmed:** No changes needed to `PersistentTimeline` for `StickerClip` support. It works out of the box with any `TimelineItem` subclass.
- **Confirmed:** The O(1) ID lookup via `Expando`-cached index (lines 24-163) works for all `TimelineItem` types including `StickerClip`.
- **Confirmed:** `fromJson()` (line 415) delegates to `TimelineItem.fromJson()`, which will dispatch to `StickerClip.fromJson()` once the switch case is added.

#### 7. `lib/timeline/data/models/track.dart` (331 lines)

- **Confirmed:** `TrackType` enum (lines 8-29) has 7 values. All extension methods use exhaustive `switch` without `default`. Adding `TrackType.sticker` will require updating all 6 extension properties (`defaultColor`, `displayName`, `supportsVideo`, `supportsAudio`, `supportsEffects`, `supportsText`) or the Dart analyzer will report errors.
- **Confirmed:** `Track.fromJson()` (line 276) uses `TrackType.values.firstWhere((t) => t.name == json['type'])` WITHOUT `orElse`. Loading a project saved with `TrackType.sticker` on an older app version will throw `StateError`. This must be fixed with `orElse: () => TrackType.effect` (or another safe default).
- **Confirmed:** The `Track` model itself needs no structural changes -- it supports any `TrackType` value via the enum.

#### 8. `lib/models/text/text_keyframe.dart` (149 lines)

- **Confirmed:** `TextKeyframe` has `copyWith()` (lines 57-79), `toJson()`/`fromJson()` (lines 83-117), `==`/`hashCode` (lines 119-143), `toString()` (lines 145-148). The `StickerKeyframe` design is missing ALL of these. The implementation is straightforward -- field-for-field identical structure, just with the `TextKeyframe` name changed to `StickerKeyframe`.

#### 9. `lib/models/clips/clips.dart` (13 lines)

- **Confirmed:** Barrel file exports 6 clip types. Adding `export 'sticker_clip.dart';` is a one-line change.

#### 10. `lib/design_system/glass_styles.dart`

- **Confirmed:** `clipImage` is `Color(0xFFFF9500)` (orange) and `clipText` is `Color(0xFFFF2D55)` (pink). The design proposes `Color(0xFFFF9F0A)` for stickers, which is visually almost identical to `clipImage`. R1 correctly recommends `Color(0xFFFFD60A)` (iOS system yellow) to differentiate.

---

### Implementation Readiness Assessment

#### Phasing Assessment

The 10-phase, 30-day implementation plan is generally well-structured. Phase-by-phase assessment:

| Phase | Days | Realistic? | Notes |
|-------|------|-----------|-------|
| Phase 1: Data Models | 3 | **Yes.** Well-defined scope. Template from `TextClip`/`TextKeyframe` exists. Must include `StickerKeyframe` complete implementation (R2-CF3). | Add 0.5 day for `TrackType` extension updates. |
| Phase 2: Static Preview | 4 | **Conditional.** Depends on unified undo resolution. If `MultiTrackTimelineManager` must be implemented first, add 2-3 days. If using temporary `UndoCoordinator` facade, on schedule. | The `StickerClipManager` scope must be clarified per R2-CF2. |
| Phase 3: Gestures | 3 | **Yes.** Follows established `TextClip` gesture patterns. Hit-testing math is verified correct. | Straightforward. |
| Phase 4: Browser UI | 3 | **Yes.** Standard Liquid Glass UI work. `CNTabBar`, `CupertinoSearchTextField`, `GridView.builder`. No novel challenges. | Must source/create ~50 bundled sticker assets. Asset creation time not accounted for. |
| Phase 5: Editor Panel | 2 | **Yes.** Standard Cupertino widget composition. | Straightforward. |
| Phase 6: Keyframes | 3 | **Conditional.** Hard dependency on `InterpolationUtils` which does not exist. Must implement `InterpolationUtils` first (1-2 days) or inline the logic. | Add 1-2 days if `InterpolationUtils` must be created. |
| Phase 7: Animated Stickers | 4 | **Yes.** Lottie and GIF rendering are well-understood. The `lottie` Flutter package supports frame-by-frame rendering. GIF decoding via `compute()` isolate is standard. | Memory management is the main risk. |
| Phase 8: Import | 2 | **Yes.** File picking, validation, thumbnail generation. Standard iOS file system work. | Straightforward. |
| Phase 9: Export | 4 | **Needs redesign.** If using Alternative A (custom compositor rendering), this phase is significantly different from what is documented. Must render sticker CIImages per-frame in compositor rather than building CALayers. The `lottie-ios` pre-rendering and GIF frame extraction remain similar, but the integration target changes. If multi-track compositor does not exist yet, a simpler initial export can use `AVVideoCompositionCoreAnimationTool` temporarily with a documented rewrite plan. | Estimate may increase to 5-6 days if designing the compositor integration from scratch. |
| Phase 10: Polish | 2 | **Yes.** Standard optimization and edge-case work. | May need 3 days if performance issues surface. |

**Adjusted total estimate:** 32-37 days (depending on undo architecture and export redesign scope).

#### Effort Estimate Assessment

The original 30-day estimate is **slightly optimistic** for the following reasons:

1. **Sticker asset creation** (designing/sourcing ~50 PNG stickers + Lottie animations) is not included in any phase.
2. **`InterpolationUtils` implementation** is a hard dependency not budgeted.
3. **Export pipeline redesign** (from CALayer to compositor) adds complexity to Phase 9.
4. **Multi-track undo integration** may require implementing parts of `MultiTrackTimelineManager` earlier than planned.

A more realistic estimate is **34-38 days** for complete implementation including all R1/R2 mitigations.

#### Dependency Assessment

| Dependency | Status | Blocking? |
|-----------|--------|-----------|
| `PersistentTimeline` (generic over TimelineItem) | Implemented, verified | No |
| Multi-track support (`Track` model, `TrackType` enum) | Implemented, needs `sticker` addition | No (one enum value + extension cases) |
| `InterpolationType` + `BezierControlPoints` | Implemented in `keyframe.dart` | No |
| `InterpolationUtils` shared class | **NOT IMPLEMENTED** | **Yes** -- blocks Phase 6 keyframe animations |
| `TextClip`/`TextKeyframe` as templates | Implemented (405 + 149 lines) | No |
| `MultiTrackTimelineManager` (unified undo) | **NOT IMPLEMENTED** | **Conditional** -- needed before shipping, but Phase 2 can use temporary facade |
| `MultiTrackCompositor` (custom `AVVideoCompositing`) | **NOT IMPLEMENTED** | **Conditional** -- needed for final export, but initial export can use CALayer temporarily |
| `lottie` Flutter package | Available on pub.dev | No (add to `pubspec.yaml`) |
| `lottie-ios` CocoaPod | Available | No (add to `Podfile`) |
| Bundled sticker asset files | **DO NOT EXIST** | **Yes** -- Phase 4 browser is empty without them |

#### Showstopper Risk Assessment

| Risk | Showstopper? | Assessment |
|------|-------------|------------|
| Export pipeline conflict (CALayer vs custom compositor) | **No** -- because the current `VideoProcessingService` does not use either `animationTool` or custom `AVVideoCompositing`. Stickers can ship with `AVVideoCompositionCoreAnimationTool` NOW and be rewritten when multi-track ships. This is explicitly Alternative 2 from R2-CF1. The rewrite cost (4 days of Phase 9 work) is acceptable if multi-track is >2 months away. | Manageable with documented rewrite plan |
| Dual undo system | **No** -- a temporary `UndoCoordinator` or even separate undo scopes (main track vs overlay tracks) is workable for an initial release, with migration to `MultiTrackTimelineManager` as a follow-up. Professional NLEs often scope undo per-track in early versions. | Manageable with temporary architecture |
| `InterpolationUtils` missing | **No** -- can be inlined or implemented in ~1-2 days. The math is well-defined (linear, ease-in/out, spring, bezier curves). | Trivial to resolve |
| Performance at max load | **No** -- realistic scenarios are within budget. Dynamic quality degradation handles edge cases. | Acceptable |
| Missing sticker assets | **No** -- placeholder assets can be used for development. Final art can be sourced in parallel. | Non-blocking for code |

**No showstopper risks identified.** All risks have viable mitigations.

---

### Mandatory Conditions (CONDITIONAL GO)

The following conditions MUST be satisfied before or during implementation. Failure to address any of these will result in a broken, unshippable feature.

1. **Complete `StickerClip` API surface before Phase 1 sign-off.** The `StickerClip` model must include `copyWith()` (with `clearName` and `clearTintColorValue` parameters for nullable fields), `duplicate()`, `splitAt()` (with keyframe partitioning matching `TextClip.splitAt()` exactly), `toJson()`, `fromJson()`, `toString()`, and `shortLabel` getter. Template: `TextClip` lines 118-403. This is a Phase 1 gate -- no further work proceeds without it.

2. **Complete `StickerKeyframe` API surface before Phase 1 sign-off.** The `StickerKeyframe` model must include `copyWith()` (with `clearBezierPoints` parameter), `toJson()`, `fromJson()`, `==`, `hashCode`, and `toString()`. Template: `TextKeyframe` (all 149 lines). This is a Phase 1 gate.

3. **Implement `InterpolationUtils` before Phase 6 begins.** This shared utility class (`applyEasing()`, `lerpOffset()`, `lerpDouble()`) is a hard dependency for both the sticker keyframe system and the text keyframe system. It must exist as a concrete implementation, not just a design reference. Budget 1-2 days. Can be implemented as an early Phase 6 task or as a standalone prerequisite.

4. **Add `StickerClip` branch to `TimelineManager.splitAt()`.** Add `else if (item is StickerClip)` to `TimelineManager.splitAt()` (after the existing `TextClip` branch at line 256) following the exact same pattern. Must be done in Phase 2 when `StickerClipManager` is built.

5. **Remove `StickerAssetType.svg` from V1 scope.** SVG rendering and export are undesigned. The enum value creates a dead code path that will cause runtime failures if a user somehow triggers it. Remove from `StickerAssetType` and add SVG stickers to the Non-Goals section.

6. **Add `orElse` fallback to `Track.fromJson()` (line 276 of `track.dart`).** Without this, any project saved with `TrackType.sticker` on a newer app version and opened on an older version will crash. Change `TrackType.values.firstWhere((t) => t.name == json['type'])` to include `orElse: () => TrackType.effect`.

7. **Document the export architecture decision explicitly.** Before Phase 9 begins, the team must make a binding decision between: (A) Ship with `AVVideoCompositionCoreAnimationTool` now, accept documented rewrite when multi-track compositor ships. (B) Implement `StickerCompositorRenderer` from the start, requiring parts of the multi-track compositor infrastructure. Decision must be recorded in the design doc with rationale and timeline implications. Either choice is viable; an unresolved conflict is not.

8. **Document the undo architecture decision explicitly.** Before Phase 2 begins, the team must decide between: (A) Implement `MultiTrackTimelineManager` as Phase 0 (adds 3-5 days but provides clean architecture). (B) Implement lightweight `UndoCoordinator` that wraps both `TimelineManager` and `StickerClipManager` undo stacks into a single ordered queue. (C) Accept per-subsystem undo scopes for V1 with documented migration plan. Decision must be recorded with rationale.

9. **Fix `computeAnimationProgress` integer division** (R1-I2). The non-looping animation progress calculation must use `.toDouble()` to prevent integer truncation. This is a one-line fix but produces completely broken animated sticker rendering if missed.

10. **Add `trackIndex` to platform channel sticker export data.** The export serialization (Section 11.1) must include the track index for each sticker clip so the native side can correctly z-order sticker layers relative to text layers. Without this, mixed text+sticker overlays will have unpredictable z-ordering in exports.

---

### Final Recommendation

The Stickers & Overlays design document is a thorough, well-structured design that correctly leverages existing infrastructure (`GeneratorClip`, `PersistentTimeline`, `InterpolationType`, dual rendering pipeline). The architecture is sound. R1 and R2 identified 4 critical issues and 10+ important issues -- all of which now have concrete, actionable mitigation plans.

The primary risks are cross-system integration points: the export pipeline conflict with multi-track compositing and the dual undo system. Both are real but neither is a showstopper because workable interim approaches exist (temporary `CALayer` export, per-subsystem undo scopes). These create documented technical debt rather than architectural dead ends, and the debt has clear payoff timelines tied to the multi-track compositing implementation.

The implementation plan is realistic within the 34-38 day adjusted estimate. The 10 mandatory conditions above represent concrete, bounded work items that must be completed at specified phase gates. None requires redesign of the core architecture; most are completion of incomplete API surfaces using existing templates.

**Verdict: CONDITIONAL GO.** Proceed to implementation with the 10 mandatory conditions enforced at their respective phase gates. The most important gate is Phase 1 completion: if `StickerClip` and `StickerKeyframe` do not have complete API surfaces (conditions #1 and #2), no subsequent phase should begin.
