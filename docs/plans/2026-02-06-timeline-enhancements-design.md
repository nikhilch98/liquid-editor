# Timeline Enhancements - Design Document

**Document Version:** 1.0
**Created:** 2026-02-06
**Status:** Draft - Pending Review
**Authors:** Development Team

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current Architecture Analysis](#2-current-architecture-analysis)
3. [Duplicate Clip](#3-duplicate-clip)
4. [Magnetic Timeline / Auto-Gap-Close](#4-magnetic-timeline--auto-gap-close)
5. [Waveform on Audio Clips](#5-waveform-on-audio-clips)
6. [Multi-Select (Marquee)](#6-multi-select-marquee)
7. [Link/Unlink Audio-Video](#7-linkunlink-audio-video)
8. [Insert vs Overwrite Edit](#8-insert-vs-overwrite-edit)
9. [J-Cut / L-Cut](#9-j-cut--l-cut)
10. [Replace Clip](#10-replace-clip)
11. [Undo History Visualization](#11-undo-history-visualization)
12. [Timeline Zoom Pinch](#12-timeline-zoom-pinch)
13. [Edge Cases & Error Handling](#13-edge-cases--error-handling)
14. [Performance Analysis](#14-performance-analysis)
15. [Implementation Plan](#15-implementation-plan)
16. [Testing Strategy](#16-testing-strategy)
17. [File Structure](#17-file-structure)

---

## 1. Overview

### 1.1 Purpose

This document specifies ten timeline enhancement features for Liquid Editor. Each feature is designed to integrate cleanly with the existing Persistent AVL Order Statistic Tree architecture (`PersistentTimeline`), the immutable clip model hierarchy (`TimelineItem` -> `MediaClip` / `GeneratorClip`), and the gesture/rendering pipeline (`TimelineGestureHandler`, `ClipsPainter`).

### 1.2 Design Principles

- **Immutability first:** All operations produce new `PersistentTimeline` instances via structural sharing. No mutation of existing state.
- **O(1) undo/redo:** Every feature pushes to the undo stack in `TimelineManager._execute()`. Undo remains a pointer swap.
- **Native iOS 26 Liquid Glass UI:** All new UI elements use `CupertinoButton`, `CupertinoActionSheet`, `CNTabBar`, `CNButton.icon` with `CNButtonStyle.glass`, and `BackdropFilter` blur effects. Zero Material widgets.
- **60 FPS guarantee:** No main-thread blocking. Waveform extraction runs on background isolates. Marquee selection uses spatial indexing. Rendering stays in `CustomPainter`.
- **Haptic feedback:** All user actions fire appropriate `HapticFeedback` calls (`selectionClick`, `lightImpact`, `mediumImpact`).

### 1.3 Scope

| Feature | Priority | Complexity | Dependencies |
|---------|----------|------------|--------------|
| Duplicate Clip | P0 | Low | ClipboardController (exists) |
| Magnetic Timeline | P0 | Medium | RippleTrimController (exists) |
| Waveform on Audio Clips | P1 | High | Native AVFoundation bridge |
| Multi-Select (Marquee) | P1 | Medium | SelectionState, TrimHitTester (exist) |
| Link/Unlink Audio-Video | P1 | Medium | TimelineClip.linkedClipId (exists) |
| Insert vs Overwrite Edit | P2 | Medium | TimelineManager (exists) |
| J-Cut / L-Cut | P2 | High | Link/Unlink (above) |
| Replace Clip | P2 | Medium | TimelineManager (exists) |
| Undo History Visualization | P3 | Low | TimelineManager undo/redo stacks |
| Timeline Zoom Pinch | Done | - | ZoomController (exists, verified) |

---

## 2. Current Architecture Analysis

### 2.1 Data Layer

#### PersistentTimeline (`lib/models/persistent_timeline.dart`)
- Immutable AVL order statistic tree
- O(log n) `itemAtTime`, `insertAt`, `remove`, `updateItem`
- O(1) `getById` / `containsId` via lazily-built `Expando`-cached ID index
- O(n) `toList`, `fromSortedList` for serialization
- All mutations return new tree instances with structural sharing
- Empty tree is `const PersistentTimeline.empty`

#### TimelineItem Hierarchy (`lib/models/clips/`)
```
TimelineItem (abstract)
  +-- MediaClip (abstract: mediaAssetId, sourceIn/Out)
  |     +-- VideoClip (keyframes, name, splitAt, trimStart/End, duplicate)
  |     +-- AudioClip (volume, isMuted, duplicate)
  |     +-- ImageClip (...)
  +-- GeneratorClip (abstract: duration)
        +-- GapClip (splitAt, duplicate)
        +-- ColorClip (color, splitAt, duplicate)
```

Key observations:
- `VideoClip.duplicate()` already generates a new UUID and appends "(copy)" to name
- `AudioClip.duplicate()` same pattern
- `GapClip.duplicate()` generates new UUID
- All clips are `@immutable` with `copyWith` support

#### TimelineClip UI Model (`lib/timeline/data/models/timeline_clip.dart`)
- Rendering-optimized wrapper with `startTime`, `duration`, `trackId`, `clipColor`
- Has `linkedClipId: String?` field for A/V linking (already present)
- Has `hasAudio`, `volume`, `isMuted` fields
- Supports `splitAt`, `trimHead`, `trimTail`, `slip`, `moveBy`, `moveTo`, `withSpeed`
- `minDuration = 33333` microseconds (1 frame at 30fps)

### 2.2 Manager Layer

#### TimelineManager (`lib/core/timeline_manager.dart`)
- Wraps `PersistentTimeline` with undo/redo stacks
- `_execute(mutation, operationName)` pattern: saves current to undo stack, applies mutation, marks composition dirty
- `maxUndoHistory = 100` states
- Undo = `_current = _undoStack.removeLast()` (O(1) pointer swap)
- Redo = `_current = _redoStack.removeLast()` (O(1) pointer swap)
- Stores `_lastOperationName` for UI feedback
- Exposes `undoCount`, `redoCount` getters

#### ClipManager (`lib/core/clip_manager.dart`)
- Legacy manager using mutable `List<TimelineItem>` with command pattern
- Has `SplitCommand`, `DeleteCommand`, `ReorderCommand`, `TrimCommand`
- Coexists with `TimelineManager` (V1 vs V2 architecture)

### 2.3 Editing Controllers (`lib/timeline/editing/`)

| Controller | Purpose | Key Methods |
|-----------|---------|-------------|
| `ClipboardController` | Copy/cut/paste/duplicate | `copy()`, `cut()`, `paste()`, `duplicate()` |
| `SplitController` | Split at playhead | `splitClip()`, `splitAtPlayhead()`, `validateSplit()` |
| `SnapController` | Magnetic snapping | `findSnapPoints()`, `findTrimSnapPoints()` |
| `RippleTrimController` | Ripple trim modes | `calculateTrimPreview()`, `applyRippleTrim()` |
| `SlipSlideController` | Slip/slide editing | `SlipController`, `SlideController` |
| `MarkerController` | Marker CRUD | (manages timeline markers) |

### 2.4 Gesture Layer (`lib/timeline/gestures/`)

#### TimelineGestureHandler
- Central coordinator for all gestures
- `GestureState` enum: `idle`, `scrolling`, `zooming`, `dragging`, `trimming`, `scrubbingPlayhead`, `marqueeSelecting`, `reordering`
- Hit testing via `TrimHitTester` with priority: playhead > ruler > trim handles > clips > markers > empty
- Sub-controllers: `TimelineScrollController`, `ZoomController`, `ClipDragController`, `TrimController`
- Long press on clip enters `GestureState.reordering`
- Long press on empty space starts `GestureState.marqueeSelecting`
- Double-tap dispatches `DoubleTapAction` (openClipEditor, openMarkerEditor, zoomToFitClip)

#### SelectionState (`lib/timeline/data/models/selection_state.dart`)
- `selectedClipIds: Set<String>` for multi-selection
- `primaryClipId: String?` for primary target
- `mode: SelectionMode` enum: normal, range, trimHead, trimTail, slip, slide, roll, marquee
- `marqueeStart: Offset?`, `marqueeEnd: Offset?` for rectangle drawing
- Methods: `selectClip()`, `addClipToSelection()`, `toggleClipSelection()`, `selectClips()`, `startMarquee()`, `updateMarquee()`, `endMarquee()`

### 2.5 Rendering Layer (`lib/timeline/rendering/painters/`)

| Painter | Purpose |
|---------|---------|
| `ClipsPainter` | Clip rectangles, labels, badges, trim handles, speed/reverse indicators |
| `SelectionOverlayPainter` | Selection highlights, marquee dashed rectangle, trim handles with grips |
| `RulerPainter` | Time ruler with tick marks |
| `PlayheadPainter` | Playhead line and handle |
| `TrackLanesPainter` | Track backgrounds |
| `SnapGuidePainter` | Snap guide lines during drag/trim |

### 2.6 Integration Points Summary

For new features, the primary integration points are:

1. **Data operations:** Add methods to `TimelineManager._execute()` pattern
2. **Editing logic:** Create new controllers in `lib/timeline/editing/`
3. **Gesture handling:** Extend `TimelineGestureHandler` or add callbacks
4. **Visual feedback:** Extend existing painters or add new `CustomPainter` subclasses
5. **UI controls:** Use Liquid Glass widgets (`CupertinoButton`, `CNButton.icon`, `CupertinoActionSheet`)
6. **Native bridge:** Platform channels for AVFoundation operations (waveform extraction)

---

## 3. Duplicate Clip

### 3.1 Overview

Duplicate one or more selected clips, placing copies either immediately after the originals (in-place) or at the current playhead position. This feature leverages the existing `ClipboardController.duplicate()` method and the `VideoClip.duplicate()` / `AudioClip.duplicate()` methods already present in the codebase.

### 3.2 Behavior Specification

#### 3.2.1 Duplicate In-Place (Default)

When the user triggers "Duplicate" with one or more clips selected:

1. For each selected clip, create a duplicate using the clip's existing `.duplicate()` method (generates new UUID, appends "(copy)" to name).
2. Calculate `insertTime` = `originalClip.endTime` (insert immediately after the source clip).
3. If ripple mode is active (`RippleTrimController.mode != none`), shift all subsequent clips on the same track by the duplicated clip's duration.
4. If ripple mode is off, insert overlapping (overwrite behavior).
5. Push the entire operation as a single `_execute()` call on `TimelineManager` for atomic undo.
6. Select the newly duplicated clip(s).
7. Fire `HapticFeedback.mediumImpact()`.

#### 3.2.2 Duplicate at Playhead

When the user triggers "Duplicate at Playhead":

1. For each selected clip, create a duplicate using `.duplicate()`.
2. Calculate `insertTime` = current playhead position.
3. Maintain relative offsets between clips if multiple are selected (same as `ClipboardController.paste()` logic).
4. Apply insert or overwrite behavior based on current edit mode (see Section 8).
5. Push as single `_execute()` call for atomic undo.
6. Select the newly duplicated clips.
7. Fire `HapticFeedback.mediumImpact()`.

#### 3.2.3 Property Preservation

The duplicate must preserve:
- `mediaAssetId` (same source media)
- `sourceInMicros` / `sourceOutMicros` (same source range)
- `keyframes` (deep copy with same transforms and timestamps)
- `volume`, `isMuted`
- `speed`, `isReversed`
- `clipColor`
- Effects metadata (`hasEffects`, `effectCount`) -- note: actual effect data is referenced by clip ID in a future effects system, so duplicates would need new effect instances

The duplicate must NOT preserve:
- `id` (new UUID generated)
- `linkedClipId` (links are severed; user can re-link manually)
- `name` gets "(copy)" suffix

### 3.3 Data Layer Changes

#### New method on `TimelineManager`:

```dart
/// Duplicate items and insert after originals.
void duplicateItems(List<String> itemIds, {TimeMicros? insertAt}) {
  _execute(() {
    var timeline = _current;
    for (final itemId in itemIds) {
      final item = timeline.getById(itemId);
      if (item == null) continue;

      final startTime = timeline.startTimeOf(itemId);
      if (startTime == null) continue;

      TimelineItem duplicate;
      if (item is VideoClip) {
        duplicate = item.duplicate();
      } else if (item is AudioClip) {
        duplicate = item.duplicate();
      } else if (item is GapClip) {
        duplicate = item.duplicate();
      } else if (item is ColorClip) {
        duplicate = item.duplicate();
      } else {
        continue;
      }

      final targetTime = insertAt ?? (startTime + item.durationMicroseconds);
      timeline = timeline.insertAt(targetTime, duplicate);
    }
    return timeline;
  }, operationName: 'Duplicate ${itemIds.length == 1 ? "clip" : "${itemIds.length} clips"}');
}
```

### 3.4 Controller: DuplicateController

New file: `lib/timeline/editing/duplicate_controller.dart`

```dart
class DuplicateController {
  /// Duplicate selected clips in-place (after each original).
  List<TimelineItem> duplicateInPlace(List<TimelineItem> items);

  /// Duplicate selected clips at a specific time.
  List<TimelineItem> duplicateAtTime(List<TimelineItem> items, TimeMicros time);

  /// Duplicate with ripple: shift subsequent clips to make room.
  List<ClipMove> calculateRippleMoves({
    required List<TimelineItem> duplicatedItems,
    required List<TimelineClip> allClips,
    required String trackId,
  });
}
```

### 3.5 UI Integration

- **Context menu:** Long-press on selected clip -> `CupertinoActionSheet` with "Duplicate" and "Duplicate at Playhead" options
- **Toolbar button:** `CNButton.icon` with `CNSymbol('plus.rectangle.on.rectangle')` and `CNButtonStyle.glass`
- **iPad keyboard shortcut:** Cmd+D for duplicate in-place, Cmd+Shift+D for duplicate at playhead
- **Accessibility:** `Semantics(label: 'Duplicate selected clip')` on button

### 3.6 Undo/Redo

Single `_execute()` call wraps the entire multi-clip duplicate operation. Undo removes all duplicated clips in one pointer swap. No special undo logic needed beyond the standard `TimelineManager` pattern.

---

## 4. Magnetic Timeline / Auto-Gap-Close

### 4.1 Overview

Automatically close gaps when clips are deleted, moved, or trimmed shorter. This creates a "magnetic" feel where clips snap together to fill empty space, similar to Final Cut Pro's magnetic timeline behavior.

### 4.2 Behavior Specification

#### 4.2.1 Gap Detection

A "gap" exists when there is empty time between two adjacent clips on the same track (no `GapClip` or other item occupying that time). In the current architecture using `PersistentTimeline`, gaps can be:

1. **Explicit gaps:** `GapClip` items in the tree (intentional spacing)
2. **Implicit gaps:** Empty time between clip end and next clip start (artifact of editing)

The magnetic timeline targets **implicit gaps only**. Explicit `GapClip` items are user-intentional and should NOT be auto-closed.

#### 4.2.2 Magnetic Mode Toggle

```dart
enum MagneticMode {
  /// No automatic gap closing. Clips stay where placed.
  off,

  /// Close gaps on the affected track only.
  track,

  /// Close gaps on all tracks (maintain sync).
  allTracks,
}
```

Default: `MagneticMode.track`.

This is distinct from the existing `SnapController` (which handles snap-to-edge during drag) and `RippleTrimController` (which handles ripple during trim). Magnetic mode handles **post-operation gap closure**.

#### 4.2.3 Trigger Points

Magnetic gap-close triggers after:

1. **Delete clip:** Remove clip -> shift subsequent clips left to fill void
2. **Move clip away:** Drag clip to different position or track -> close gap at source
3. **Trim shorter:** Trim a clip's head or tail shorter -> close gap created
4. **Cut operation (clipboard):** Cut clips -> close gap

It does NOT trigger during:
- Drag preview (only on commit)
- Trim preview (only on commit)
- Undo/redo (those restore exact state)

#### 4.2.4 Gap Close Algorithm

```
function closeGapsOnTrack(trackId, clips):
    trackClips = clips.where(clip.trackId == trackId)
                      .sortBy(clip.startTime)

    moves = []
    currentEnd = 0  // or first clip start if we want left-alignment

    for clip in trackClips:
        if clip.startTime > currentEnd:
            // Gap found
            gap = clip.startTime - currentEnd
            moves.add(ClipMove(clip.id, clip.startTime - gap))
        currentEnd = max(currentEnd, clip.endTime)

    return moves
```

For `MagneticMode.allTracks`, apply the same algorithm independently to each track, then normalize so no clip moves before time 0.

#### 4.2.5 Animation

When clips slide to close a gap, animate the movement over 200ms using `CurvedAnimation` with `Curves.easeOutCubic`. The animation is visual-only (the data model updates immediately; the painter interpolates positions during the animation window).

### 4.3 Data Layer Changes

#### GapCloseController (`lib/timeline/editing/gap_close_controller.dart`)

```dart
class GapCloseController {
  MagneticMode mode = MagneticMode.track;

  /// Detect and close gaps on a track after an operation.
  /// Returns list of clip moves needed to close gaps.
  List<ClipMove> detectAndClose({
    required List<TimelineClip> clips,
    required String trackId,
    Set<String> excludeClipIds = const {},
  });

  /// Close gaps on all tracks.
  List<ClipMove> detectAndCloseAllTracks({
    required List<TimelineClip> clips,
    required List<Track> tracks,
    Set<String> excludeClipIds = const {},
  });

  /// Check if a track has gaps.
  bool hasGaps(List<TimelineClip> trackClips);

  /// Calculate total gap time on a track.
  TimeMicros totalGapTime(List<TimelineClip> trackClips);
}
```

#### Integration with TimelineManager

After delete/move/trim operations, if `magneticMode != off`, the `_execute()` closure includes a gap-close step:

```dart
void removeWithMagnetic(String itemId) {
  _execute(() {
    var timeline = _current.remove(itemId);
    if (_magneticMode != MagneticMode.off) {
      timeline = _applyGapClose(timeline);
    }
    return timeline;
  }, operationName: 'Delete clip');
}
```

This ensures the gap-close is part of the same atomic undo operation.

### 4.4 Interaction with GapClip

When magnetic mode encounters a `GapClip` (explicit gap), it treats it as intentional content and does NOT close through it. The gap-close algorithm only operates on empty time that has no `TimelineItem` of any type.

To distinguish: In the `PersistentTimeline`, if `itemAtTime(gapStart)` returns a `GapClip`, the gap is intentional. If `itemAtTime(gapStart)` returns `null` (time exceeds total duration) or the next clip's `startTime` leaves dead space before it, that is an implicit gap to close.

### 4.5 UI Integration

- **Toggle button:** `CupertinoButton` in timeline toolbar showing magnet icon (`CNSymbol('magnet')`)
- **State indicator:** Button tint changes to `CupertinoColors.activeBlue` when magnetic mode is on
- **Settings:** Long-press on magnet button shows `CupertinoActionSheet` with mode options (Off, Track, All Tracks)
- **Animation visual:** Clips animate sliding into position (painter interpolation, 200ms, easeOutCubic)

### 4.6 Undo/Redo

Since gap-close is bundled into the same `_execute()` call as the triggering operation (delete, move, trim), undo restores the pre-operation state including the original gap. No special handling needed.

---

## 5. Waveform on Audio Clips

### 5.1 Overview

Display audio waveform data inside clip rectangles on the timeline for audio clips and the audio track of video clips. Waveform extraction runs on the native side (AVFoundation) via platform channels, and rendering uses a new `WaveformPainter` integrated into `ClipsPainter`.

### 5.2 Waveform Data Model

```dart
/// Cached waveform data for a media asset's audio track.
@immutable
class WaveformData {
  /// Media asset ID this waveform belongs to.
  final String mediaAssetId;

  /// Samples per second (resolution).
  /// Higher = more detail, more memory.
  /// 100 samples/sec is sufficient for timeline display.
  final int samplesPerSecond;

  /// Normalized amplitude samples (0.0 to 1.0).
  /// Each sample represents the peak amplitude in its time window.
  final Float32List samples;

  /// Total duration of the audio in microseconds.
  final int durationMicros;

  /// Whether this is a placeholder (extraction in progress).
  final bool isPlaceholder;

  const WaveformData({
    required this.mediaAssetId,
    required this.samplesPerSecond,
    required this.samples,
    required this.durationMicros,
    this.isPlaceholder = false,
  });
}
```

### 5.3 Memory Budget

At 100 samples/second, a `Float32List`:
- 1 minute of audio = 6,000 samples = 24 KB
- 10 minutes of audio = 60,000 samples = 240 KB
- 1 hour of audio = 360,000 samples = 1.44 MB

This is well within budget. We can afford 200 samples/second for better visual quality at high zoom levels, doubling memory to ~2.88 MB per hour. Even with 10 distinct media assets, total waveform cache stays under 30 MB.

### 5.4 Native Extraction Pipeline

#### Platform Channel API

```dart
class WaveformExtractor {
  static const _channel = MethodChannel('liquid_editor/waveform');

  /// Extract waveform from a media asset.
  /// Runs on native background thread, does not block UI.
  Future<WaveformData> extractWaveform({
    required String assetPath,
    required String mediaAssetId,
    int samplesPerSecond = 200,
  });

  /// Cancel in-progress extraction.
  void cancelExtraction(String mediaAssetId);
}
```

#### Native Side (Swift)

```swift
// In WaveformExtractorPlugin.swift
func extractWaveform(assetURL: URL, samplesPerSecond: Int) async throws -> [Float] {
    let asset = AVAsset(url: assetURL)
    let track = try await asset.loadTracks(withMediaType: .audio).first!
    let reader = try AVAssetReader(asset: asset)

    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVNumberOfChannelsKey: 1  // Downmix to mono for waveform
    ]

    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(output)
    reader.startReading()

    // Process audio buffers, compute peak amplitudes per window
    // Return Float32 array of normalized peaks
}
```

The extraction runs on a background `DispatchQueue`. Results are streamed back to Flutter via the platform channel. A placeholder `WaveformData` with `isPlaceholder = true` is shown during extraction (renders as a flat line at 50% height).

### 5.5 Waveform Cache

```dart
class WaveformCache {
  /// In-memory cache keyed by mediaAssetId.
  final Map<String, WaveformData> _cache = {};

  /// Pending extractions.
  final Set<String> _pending = {};

  /// Get cached waveform or trigger extraction.
  WaveformData? getOrExtract(String mediaAssetId, String assetPath);

  /// Evict from cache (when media asset is removed from project).
  void evict(String mediaAssetId);

  /// Persist waveform data alongside project file.
  /// Stored as binary file: {project_dir}/waveforms/{mediaAssetId}.wf
  Future<void> saveToDisk(String projectDir);

  /// Load persisted waveform data.
  Future<void> loadFromDisk(String projectDir);

  /// Total memory used by cache.
  int get memorySizeBytes;
}
```

### 5.6 Rendering

#### Waveform Drawing in ClipsPainter

The waveform is drawn inside the clip rectangle, centered vertically. For audio clips, it fills the full clip height. For video clips with audio, it occupies the bottom 30% of the clip rectangle.

```dart
void _drawWaveform(Canvas canvas, TimelineClip clip, Rect clipRect, WaveformData waveform) {
  // Calculate visible sample range based on clip's source in/out and viewport
  final startSample = (clip.sourceIn / 1000000.0 * waveform.samplesPerSecond).round();
  final endSample = (clip.sourceOut / 1000000.0 * waveform.samplesPerSecond).round();
  final visibleSamples = endSample - startSample;

  // Determine pixel stride: how many samples per pixel
  final samplesPerPixel = visibleSamples / clipRect.width;

  if (samplesPerPixel <= 0) return;

  // Build path
  final path = Path();
  final waveformRect = clip.type == ClipType.audio
      ? clipRect.deflate(2)
      : Rect.fromLTRB(clipRect.left, clipRect.bottom - clipRect.height * 0.3,
                       clipRect.right, clipRect.bottom - 2);

  final midY = waveformRect.center.dy;
  final maxAmplitude = waveformRect.height / 2;

  path.moveTo(waveformRect.left, midY);

  for (double px = 0; px < clipRect.width; px += 1.0) {
    final sampleIdx = startSample + (px * samplesPerPixel).round();
    if (sampleIdx >= waveform.samples.length) break;

    // Get peak amplitude for this pixel column
    final endIdx = (startSample + ((px + 1) * samplesPerPixel).round())
        .clamp(0, waveform.samples.length - 1);
    double peak = 0;
    for (int i = sampleIdx; i <= endIdx; i++) {
      if (waveform.samples[i] > peak) peak = waveform.samples[i];
    }

    final x = waveformRect.left + px;
    final amplitude = peak * maxAmplitude;

    // Draw symmetrical waveform (top and bottom)
    path.lineTo(x, midY - amplitude);
  }

  // Mirror back for bottom half
  for (double px = clipRect.width - 1; px >= 0; px -= 1.0) {
    final sampleIdx = startSample + (px * samplesPerPixel).round();
    if (sampleIdx >= waveform.samples.length) continue;

    final endIdx = (startSample + ((px + 1) * samplesPerPixel).round())
        .clamp(0, waveform.samples.length - 1);
    double peak = 0;
    for (int i = sampleIdx; i <= endIdx; i++) {
      if (waveform.samples[i] > peak) peak = waveform.samples[i];
    }

    final x = waveformRect.left + px;
    final amplitude = peak * maxAmplitude;
    path.lineTo(x, midY + amplitude);
  }

  path.close();

  // Fill with semi-transparent color
  final waveformColor = clip.type == ClipType.audio
      ? const Color(0xFF34C759) // Green for audio clips
      : const Color(0x80808080); // Gray for video audio

  canvas.drawPath(path, Paint()
    ..color = waveformColor.withValues(alpha: 0.6)
    ..style = PaintingStyle.fill);
}
```

#### Dynamic Detail Based on Zoom Level

At low zoom (overview), use every Nth sample to reduce path complexity:
- `samplesPerPixel > 10`: skip samples, just track peaks per pixel column
- `samplesPerPixel <= 10`: render individual samples as smooth curve
- `samplesPerPixel <= 1`: sub-pixel resolution, use Bezier interpolation between samples

### 5.7 UI Integration

- Waveform is always visible on audio clips (`ClipType.audio`)
- For video clips, waveform is shown when track height >= `Track.heightLarge` (88px)
- Waveform color: green (`#34C759`) for audio clips, translucent gray for video audio
- During extraction: show pulsing placeholder bar (50% height, 30% opacity, slow fade animation)

---

## 6. Multi-Select (Marquee)

### 6.1 Overview

Draw a selection rectangle to select multiple clips. The infrastructure for this largely exists: `GestureState.marqueeSelecting`, `SelectionState.marquee*` fields, `SelectionMode.marquee`, and `TrimHitTester.findClipsInRect()`. This section specifies the remaining implementation details.

### 6.2 Current State Analysis

Already implemented:
- `SelectionState` has `marqueeStart`, `marqueeEnd`, `startMarquee()`, `updateMarquee()`, `endMarquee()`, `marqueeRect`
- `SelectionMode.marquee` enum value exists
- `TimelineGestureHandler.onLongPressStart()` starts marquee on empty space
- `TrimHitTester.findClipsInRect()` returns clips intersecting a `Rect`
- `SelectionOverlayPainter._drawMarqueeSelection()` draws dashed rectangle
- `SelectionState.selectClips()` selects a `Set<String>` of clip IDs

Needs implementation:
- Gesture refinement (two-finger drag as alternative trigger)
- Selection policy (fully inside vs partially inside marquee)
- Add-to-selection behavior (hold to add)
- Operations on multi-selection (group actions)

### 6.3 Behavior Specification

#### 6.3.1 Trigger

- **Primary:** Long press (300ms) on empty space, then drag. Already implemented in `onLongPressStart`.
- **Alternative:** Two-finger drag on timeline area (not zoom). Differentiate from pinch zoom: if both fingers move in the same direction with similar velocity, it is a two-finger scroll or marquee. If fingers diverge/converge, it is a pinch zoom.

#### 6.3.2 Selection Policy

**Partially inside selection:** A clip is selected if its rectangle overlaps the marquee rectangle AT ALL. This is more forgiving and matches the behavior of most creative tools (Premiere Pro, After Effects, Figma).

The existing `TrimHitTester.findClipsInRect()` already uses `Rect.overlaps()` which implements this policy.

#### 6.3.3 Visual Feedback

The existing `SelectionOverlayPainter._drawMarqueeSelection()` draws:
- Semi-transparent fill (10% opacity of selection color)
- Dashed border (6px dash, 4px gap)

Enhancement: During marquee drag, clips that are *currently* inside the marquee should show a lightweight highlight (border glow at 20% opacity) before the selection is committed. This provides real-time feedback as the user drags.

#### 6.3.4 Add-to-Selection

When the user taps a clip while clips are already selected:
- **Normal tap:** Replace selection with tapped clip (current behavior)
- **Tap with two fingers on screen (second finger held):** Add/toggle the tapped clip in the selection

Alternative approach for touch: After marquee selection, tapping another clip with a quick double-tap adds it to the current selection. A single tap clears and selects only the tapped clip.

#### 6.3.5 Operations on Multi-Selection

When multiple clips are selected (`selectedClipIds.length > 1`):

| Operation | Behavior |
|-----------|----------|
| Delete | Delete all selected clips, ripple if magnetic mode on |
| Copy | Copy all selected clips to clipboard with relative positions |
| Cut | Cut all selected clips |
| Paste | (operates on clipboard, not selection) |
| Duplicate | Duplicate all selected clips in-place |
| Move/Drag | Move all selected clips as a group, maintaining relative positions |
| Split | Split all selected clips at playhead |

The `ClipDragController` already accepts `clipIds: _selection.selectedClipIds` in `startDrag()`, so multi-drag is supported.

### 6.4 Data Layer Changes

No changes needed to `SelectionState` (already complete). No changes needed to `PersistentTimeline`.

### 6.5 Gesture Handler Changes

```dart
// In TimelineGestureHandler._updateMarqueeSelection():
void _updateMarqueeSelection() {
  if (_marqueeStart == null || _marqueeCurrent == null) return;

  _selection = _selection.updateMarquee(_marqueeCurrent!);

  // Find clips in marquee rect
  final rect = Rect.fromPoints(_marqueeStart!, _marqueeCurrent!);
  final hitTester = TrimHitTester(
    clips: _clips,
    markers: _markers,
    viewport: _viewport,
    playheadPosition: _playheadPosition,
    trackHeights: _trackHeights,
    trackYPositions: _trackYPositions,
  );

  final clipsInRect = hitTester.findClipsInRect(rect);
  final clipIds = clipsInRect.map((c) => c.id).toSet();

  // ENHANCEMENT: preserve previously selected clips if modifier active
  // For touch: not applicable (no modifier keys)
  // For iPad keyboard: check if Shift is held
  _selection = _selection.selectClips(clipIds);
  onSelectionChanged?.call(_selection);
}
```

This code already exists and is correct. The main work is ensuring that multi-selection operations (delete, duplicate, move) properly handle the `Set<String>` of selected clip IDs throughout the pipeline.

---

## 7. Link/Unlink Audio-Video

### 7.1 Overview

Video clips imported from files with audio tracks should have their audio synchronized with the video. The `TimelineClip` model already has a `linkedClipId: String?` field for this purpose. This feature implements the full lifecycle of audio-video linking.

### 7.2 Link Model

When a video file with audio is imported:
1. Create a `VideoClip` on the main video track
2. Create an `AudioClip` on an audio track, referencing the same `mediaAssetId`
3. Set `videoClip.linkedClipId = audioClip.id` and `audioClip.linkedClipId = videoClip.id` (bidirectional)

The linked clips have matching `sourceInMicros` / `sourceOutMicros` and identical `durationMicroseconds`. They occupy the same timeline time range, just on different tracks.

### 7.3 Behavior Specification

#### 7.3.1 Linked State (Default for Imported Clips)

When two clips are linked:

| Operation | Behavior |
|-----------|----------|
| Move | Moving one moves the other by the same delta |
| Trim head | Trimming one trims the other's head identically |
| Trim tail | Trimming one trims the other's tail identically |
| Delete | Deleting one deletes the other |
| Split | Splitting one splits the other at the same time |
| Speed change | Changing speed on one changes the other |
| Copy | Copies both clips (linked in the paste) |

| Operation | Behavior |
|-----------|----------|
| Slip | Independent (audio content can slip independently of video) |
| Volume | Independent (only audio clip affected) |
| Mute | Independent (only audio clip affected) |
| Effects | Independent (video effects do not affect audio, audio effects do not affect video) |

#### 7.3.2 Unlink

User selects a linked clip, triggers "Unlink". Both clips lose their `linkedClipId` reference:

```dart
void unlinkClips(String clipId) {
  final clip = getClipById(clipId);
  if (clip?.linkedClipId == null) return;

  final linkedId = clip!.linkedClipId!;

  _execute(() {
    var timeline = _current;
    // Clear linkedClipId on both clips
    final clip1 = timeline.getById(clipId);
    final clip2 = timeline.getById(linkedId);
    // ... update both with clearLinkedClipId
    return timeline;
  }, operationName: 'Unlink audio/video');
}
```

After unlinking, both clips behave independently. The user can move, trim, delete one without affecting the other.

#### 7.3.3 Re-Link

User selects two clips (one video, one audio) on different tracks, triggers "Link". Validation:
- Exactly 2 clips selected
- One must be on a video-capable track, the other on an audio-capable track
- Both must have the same `mediaAssetId` (from the same source file)
- Both must be the same duration (or close enough: within 1 frame tolerance)
- Both must be at the same timeline position (or close: within 1 frame tolerance)

If valid, set `linkedClipId` on both clips.

### 7.4 Visual Indicators

#### 7.4.1 Link Chain Icon

When a clip is linked, draw a small chain icon in the clip's bottom-left corner. Use `CNSymbol('link')` (SF Symbol). The icon is drawn by `ClipsPainter` when `clip.linkedClipId != null`.

#### 7.4.2 Link Line Between Tracks

Draw a thin vertical dashed line connecting the linked clips across tracks. This line appears when either clip is selected. Rendered by a new `LinkIndicatorPainter` overlay.

### 7.5 Controller: LinkController

```dart
class LinkController {
  /// Link two clips (bidirectional).
  (TimelineClip, TimelineClip) link(TimelineClip clipA, TimelineClip clipB);

  /// Unlink a clip from its partner.
  (TimelineClip, TimelineClip) unlink(TimelineClip clip, TimelineClip linkedClip);

  /// Validate if two clips can be linked.
  LinkValidation validateLink(TimelineClip clipA, TimelineClip clipB);

  /// Get the linked partner clip.
  TimelineClip? getLinkedClip(TimelineClip clip, List<TimelineClip> allClips);

  /// Apply operation to linked clip (propagate move, trim, etc.).
  TimelineClip propagateOperation(
    TimelineClip sourceClip,
    TimelineClip linkedClip,
    LinkableOperation operation,
  );
}

enum LinkableOperation {
  move,
  trimHead,
  trimTail,
  delete,
  split,
  speedChange,
}

@immutable
class LinkValidation {
  final bool isValid;
  final String? error;
  const LinkValidation({required this.isValid, this.error});
}
```

### 7.6 Integration with Gesture Handler

When a linked clip is dragged, the `ClipDragController.startDrag()` must include the linked clip's ID in the drag set:

```dart
// In TimelineGestureHandler.onScaleStart():
if (hitResult.isClip && _selection.isClipSelected(hitResult.elementId!)) {
  // Collect linked clips
  final dragClipIds = Set<String>.from(_selection.selectedClipIds);
  for (final clipId in _selection.selectedClipIds) {
    final clip = _clips.firstWhere((c) => c.id == clipId);
    if (clip.linkedClipId != null) {
      dragClipIds.add(clip.linkedClipId!);
    }
  }

  _state = GestureState.dragging;
  dragController.startDrag(
    clipIds: dragClipIds,
    position: position,
    time: hitResult.hitTime,
  );
}
```

Similarly for trim and delete operations.

---

## 8. Insert vs Overwrite Edit

### 8.1 Overview

Two modes for placing clips on the timeline:
- **Insert mode:** Adding a clip pushes all subsequent clips to the right, preserving their relative timing.
- **Overwrite mode:** Adding a clip replaces the content at that position; existing clips may be trimmed or split to accommodate.

### 8.2 Edit Mode Model

```dart
enum EditMode {
  /// Insert: push subsequent clips right to make room.
  insert,

  /// Overwrite: replace content at target position.
  overwrite,
}
```

Stored as a property on the timeline view state (not persisted per-project; it is a UI preference).

### 8.3 Behavior Specification

#### 8.3.1 Insert Mode

When a clip is placed at time `T` with duration `D`:

1. Find all clips on the target track that start at or after time `T`.
2. Shift each of those clips right by `D` microseconds.
3. Insert the new clip at time `T`.
4. If a clip straddles `T` (starts before, ends after), split it at `T`, then shift the right half.

This is a ripple insert. It is similar to `RippleTrimController` with `RippleTrimMode.track`.

#### 8.3.2 Overwrite Mode

When a clip is placed at time `T` with duration `D`:

1. Find all clips on the target track that overlap the range `[T, T+D)`.
2. For each overlapping clip:
   - If fully contained within `[T, T+D)`: delete it.
   - If it starts before `T` and ends within `[T, T+D)`: trim its tail to `T`.
   - If it starts within `[T, T+D)` and ends after `T+D`: trim its head to `T+D`.
   - If it spans the entire range (starts before `T`, ends after `T+D`): split at `T` and `T+D`, delete the middle portion.
3. Insert the new clip at time `T`.

#### 8.3.3 Affected Operations

| Operation | Insert Mode | Overwrite Mode |
|-----------|-------------|----------------|
| Paste from clipboard | Push clips right | Replace content |
| Drag clip from media library | Push clips right | Replace content |
| Duplicate at playhead | Push clips right | Replace content |
| Drag existing clip to new position | Push clips right (if different track) | Replace content |

Operations NOT affected by edit mode:
- Trim (always adjusts the clip itself)
- Split (does not add content)
- Delete (does not add content)
- Duplicate in-place (inserts after the clip on the same track)

### 8.4 Controller: EditModeController

```dart
class EditModeController {
  EditMode mode = EditMode.insert;

  /// Calculate the clip modifications needed to insert at a position.
  InsertResult calculateInsert({
    required TimelineClip newClip,
    required List<TimelineClip> trackClips,
    required TimeMicros insertTime,
  });

  /// Calculate the clip modifications needed to overwrite at a position.
  OverwriteResult calculateOverwrite({
    required TimelineClip newClip,
    required List<TimelineClip> trackClips,
    required TimeMicros insertTime,
  });
}

@immutable
class InsertResult {
  /// Clips to shift right.
  final List<ClipMove> shifts;
  /// Clips to split (if a clip straddles the insert point).
  final List<SplitClipResult> splits;

  const InsertResult({required this.shifts, required this.splits});
}

@immutable
class OverwriteResult {
  /// Clips to delete entirely.
  final List<String> deleteIds;
  /// Clips to trim.
  final List<TrimPreview> trims;
  /// Clips to split.
  final List<SplitClipResult> splits;

  const OverwriteResult({
    required this.deleteIds,
    required this.trims,
    required this.splits,
  });
}
```

### 8.5 UI Integration

- **Mode toggle:** `CupertinoButton` in timeline toolbar with icon that switches between:
  - Insert mode: `CNSymbol('arrow.right.to.line.compact')` (arrow pushing right)
  - Overwrite mode: `CNSymbol('rectangle.on.rectangle')` (rectangle overlaying)
- **Visual indicator:** The playhead cursor changes appearance in overwrite mode: a red triangular overlay on the playhead handle, indicating destructive placement.
- **Tooltip:** Long-press on the toggle shows mode description in a `CupertinoActionSheet`.

### 8.6 Undo/Redo

Both insert and overwrite operations are wrapped in a single `_execute()` call, so undo reverses the entire compound operation atomically.

---

## 9. J-Cut / L-Cut

### 9.1 Overview

J-Cut and L-Cut are professional editing techniques where audio and video transitions are offset:
- **J-Cut:** Audio from the NEXT clip starts playing BEFORE its video appears (audio precedes video). Creates anticipation.
- **L-Cut:** Audio from the CURRENT clip continues playing AFTER the next clip's video starts (audio extends past video). Creates continuity.

These require the Link/Unlink feature (Section 7) as a prerequisite, since J/L cuts involve independently trimming the audio portion of a linked clip beyond its video boundaries.

### 9.2 Prerequisites

- Link/Unlink Audio-Video (Section 7) must be implemented
- Clips must be linked (have `linkedClipId` set)
- Independent audio trim handles must be visible when a linked clip is selected

### 9.3 Behavior Specification

#### 9.3.1 Creating a J-Cut

1. User selects the NEXT clip's audio portion (the one that will play early).
2. User drags the audio clip's left trim handle to the LEFT, extending it before the video.
3. The audio now starts before the video cut point.
4. The linked video clip is NOT affected (stays at its current position).

In terms of data:
- The audio `TimelineClip` gets a new `startTime` that is earlier than its linked video clip's `startTime`.
- The audio `sourceIn` is extended (earlier in the source).
- The video clip remains unchanged.

#### 9.3.2 Creating an L-Cut

1. User selects the CURRENT clip's audio portion (the one that will extend).
2. User drags the audio clip's right trim handle to the RIGHT, extending it past the video.
3. The audio now continues after the video cut point.
4. The linked video clip is NOT affected.

In terms of data:
- The audio `TimelineClip` gets a longer `duration` / later `endTime` than its linked video clip.
- The audio `sourceOut` is extended (further in the source).
- The video clip remains unchanged.

#### 9.3.3 Implementation Strategy: Partial Unlink

Rather than fully unlinking, J/L cuts use a "partial unlink" state where trim operations on the audio are independent, but move/delete/split operations still propagate. This requires a finer-grained link model:

```dart
enum LinkMode {
  /// Fully linked: all operations propagate.
  full,

  /// Trim-independent: trim is independent, move/delete/split propagate.
  /// Used for J-cuts and L-cuts.
  trimIndependent,

  /// Fully independent (unlinked).
  none,
}
```

When a J-cut or L-cut is created, the link mode changes from `full` to `trimIndependent`. This preserves synchronization for moves while allowing independent audio trimming.

### 9.4 Visual Representation

When an audio clip extends beyond its linked video clip:
- The extended audio region is drawn with a lower opacity (40% vs normal 70%).
- A diagonal hash pattern indicates the "overhang" region.
- The link line between audio and video clips shows an offset indicator (the chain is drawn at the audio's actual start/end, not the video's).

In `ClipsPainter`:
```dart
void _drawJLCutOverhang(Canvas canvas, Rect overhangRect, Color clipColor) {
  // Draw lower-opacity background
  canvas.drawRRect(
    RRect.fromRectAndRadius(overhangRect, Radius.circular(cornerRadius)),
    Paint()..color = clipColor.withValues(alpha: 0.3),
  );

  // Draw diagonal hash pattern
  // ... (clip path, draw diagonal lines at 45 degrees, 4px spacing)
}
```

### 9.5 Trim Handle Behavior

For linked clips with `LinkMode.trimIndependent`:
- Video trim handles: visible on video clip, trim video only
- Audio trim handles: visible on audio clip, trim audio only (can extend beyond video)
- Moving the pair moves both by the same delta
- The audio trim handles use a distinct color (green outline vs white) to indicate independent trimming

### 9.6 Constraints

- Audio cannot extend before time 0 on the timeline
- Audio source range cannot extend beyond the source media's actual audio duration
- J/L cut audio overhang must not overlap with other clips on the same audio track (if overlap occurs, show red invalid indicator)
- Maximum overhang: limited by source media duration minus current source out point (for L-cut) or source in point minus 0 (for J-cut)

### 9.7 Undo/Redo

Each J/L cut trim operation is a standard trim on the audio clip, committed via `TimelineManager._execute()`. The link mode change (`full` -> `trimIndependent`) is persisted as part of the clip state update.

---

## 10. Replace Clip

### 10.1 Overview

Swap a clip's media source while preserving its timeline position, duration, applied effects, keyframes, and color grading. Useful for swapping placeholder footage with final footage, or trying different takes.

### 10.2 Behavior Specification

#### 10.2.1 Replace Flow

1. User selects a clip on the timeline.
2. User triggers "Replace Clip" (via context menu or toolbar).
3. Media picker opens (same picker used for import, filtered to compatible media types).
4. User selects new media.
5. System validates replacement (see 10.2.2).
6. System creates new clip with replaced media, preserving properties.
7. Original clip is replaced in the timeline via `TimelineManager.updateItem()`.
8. `HapticFeedback.mediumImpact()`.

#### 10.2.2 Validation

- New media must be the same type (video replaces video, audio replaces audio; image can replace video or image).
- New media must have sufficient duration to cover the clip's current source range. If not, present options (see 10.2.3).

#### 10.2.3 Duration Mismatch Handling

If the new media is **shorter** than the current clip's source range:

Present a `CupertinoActionSheet` with options:
1. **Shorten clip:** Trim the clip's `sourceOut` (and timeline duration) to match the new media's duration. Ripple subsequent clips if magnetic mode is on.
2. **Freeze last frame:** Use the new media's full duration, then hold the last frame for the remaining time. (Implementation: split into a media clip + a freeze-frame clip.)
3. **Cancel:** Do not replace.

If the new media is **longer** than the current clip's source range:
- Use the same source in/out points (proportionally mapped). The extra media is available for future trim extension.
- Alternatively, maintain the same source in point and trim out to match original duration.

#### 10.2.4 Property Transfer

Properties preserved from the original clip:
- `id` (same clip ID, in-place replacement)
- `startTime`, `duration` (same position on timeline)
- `trackId` (same track)
- `sourceIn`, `sourceOut` (same range, unless duration mismatch -- see above)
- `keyframes` (same transforms at same timestamps)
- `speed`, `isReversed`
- `clipColor`, `label`
- `linkedClipId` (if linked, the link is maintained with the new media)
- `hasEffects`, `effectCount` (effects reference clip ID, not media)
- `volume`, `isMuted`, `hasAudio`

Properties changed:
- `mediaAssetId` (new media source)
- `isOffline` (reset to false, new media is presumably online)

### 10.3 Data Layer

```dart
// In TimelineManager:
void replaceClipMedia(String clipId, String newMediaAssetId, {
  int? newSourceInMicros,
  int? newSourceOutMicros,
}) {
  final item = _current.getById(clipId);
  if (item == null) return;

  TimelineItem newItem;
  if (item is VideoClip) {
    newItem = item.copyWith(
      mediaAssetId: newMediaAssetId,
      sourceInMicros: newSourceInMicros,
      sourceOutMicros: newSourceOutMicros,
    );
  } else if (item is AudioClip) {
    newItem = item.copyWith(
      mediaAssetId: newMediaAssetId,
      sourceInMicros: newSourceInMicros,
      sourceOutMicros: newSourceOutMicros,
    );
  } else {
    return; // Cannot replace generator clips
  }

  _execute(
    () => _current.updateItem(clipId, newItem),
    operationName: 'Replace clip media',
  );
}
```

### 10.4 Controller: ReplaceClipController

```dart
class ReplaceClipController {
  /// Validate replacement compatibility.
  ReplaceValidation validate({
    required TimelineItem originalClip,
    required MediaAsset newMedia,
  });

  /// Calculate replacement with duration matching.
  ReplaceResult calculateReplacement({
    required TimelineItem originalClip,
    required MediaAsset newMedia,
    required DurationMismatchStrategy strategy,
  });
}

enum DurationMismatchStrategy {
  shorten,
  freezeLastFrame,
  loopMedia,
}

@immutable
class ReplaceValidation {
  final bool isValid;
  final bool hasDurationMismatch;
  final int? newMediaDurationMicros;
  final int? currentClipDurationMicros;
  final String? error;

  const ReplaceValidation({
    required this.isValid,
    this.hasDurationMismatch = false,
    this.newMediaDurationMicros,
    this.currentClipDurationMicros,
    this.error,
  });
}
```

### 10.5 UI Integration

- **Context menu:** Long-press on clip -> `CupertinoActionSheet` -> "Replace Clip..."
- **Toolbar:** `CNButton.icon` with `CNSymbol('arrow.2.squarepath')` when a clip is selected
- **Media picker:** Reuse existing import picker flow, but return the selection to the replace controller instead of creating a new clip

---

## 11. Undo History Visualization

### 11.1 Overview

Display a visual list of all undo/redo operations, allowing the user to tap any point in the history to jump to that state. This exposes the `TimelineManager._undoStack` and `_redoStack` in a user-friendly way.

### 11.2 Data Model

The existing `TimelineManager` stores:
- `_undoStack: List<PersistentTimeline>` (previous states)
- `_redoStack: List<PersistentTimeline>` (undone states)
- `_lastOperationName: String?` (name of the last operation)

Problem: The undo stack stores `PersistentTimeline` instances but NOT the operation names. Only the most recent operation name is stored in `_lastOperationName`.

Solution: Create a parallel metadata stack that stores operation names alongside the timeline states:

```dart
/// Metadata for an undo history entry.
@immutable
class UndoHistoryEntry {
  /// Human-readable operation name.
  final String operationName;

  /// Timestamp when the operation was performed.
  final DateTime timestamp;

  /// Number of clips affected.
  final int affectedClipCount;

  /// Type of operation for icon display.
  final UndoOperationType type;

  const UndoHistoryEntry({
    required this.operationName,
    required this.timestamp,
    this.affectedClipCount = 0,
    required this.type,
  });
}

enum UndoOperationType {
  insert,
  remove,
  split,
  trim,
  move,
  duplicate,
  replace,
  link,
  groupOperation,
  other,
}
```

### 11.3 TimelineManager Changes

Add a parallel metadata list:

```dart
class TimelineManager extends ChangeNotifier {
  // ... existing fields ...

  /// Metadata for undo history entries.
  final List<UndoHistoryEntry> _undoMetadata = [];

  /// Metadata for redo history entries.
  final List<UndoHistoryEntry> _redoMetadata = [];

  /// Get undo history for UI display.
  List<UndoHistoryEntry> get undoHistory => List.unmodifiable(_undoMetadata);

  /// Get redo history for UI display.
  List<UndoHistoryEntry> get redoHistory => List.unmodifiable(_redoMetadata);

  /// Jump to a specific point in undo history.
  /// [index] is 0 for the oldest state, undoCount-1 for the most recent.
  void jumpToUndoState(int index) {
    if (index < 0 || index >= _undoStack.length) return;

    // Move states between undo and redo stacks
    final stepsToUndo = _undoStack.length - 1 - index;
    for (int i = 0; i < stepsToUndo; i++) {
      undo();
    }
  }
}
```

Update `_execute()` to track metadata:

```dart
void _execute(
  PersistentTimeline Function() mutation, {
  String? operationName,
  UndoOperationType type = UndoOperationType.other,
  int affectedClipCount = 0,
}) {
  _undoStack.add(_current);
  _undoMetadata.add(UndoHistoryEntry(
    operationName: operationName ?? 'Edit',
    timestamp: DateTime.now(),
    affectedClipCount: affectedClipCount,
    type: type,
  ));

  // Trim if over limit
  if (_undoStack.length > maxUndoHistory) {
    _undoStack.removeAt(0);
    _undoMetadata.removeAt(0);
  }

  _redoStack.clear();
  _redoMetadata.clear();

  _current = mutation();
  _compositionDirty = true;
  _lastOperationName = operationName;

  notifyListeners();
}
```

### 11.4 UI: Undo History Panel

A sliding panel from the bottom (or side on iPad) showing the operation history.

#### Layout

```
+-------------------------------------------+
| Undo History                          [x]  |
+-------------------------------------------+
| [icon] Split clip           2:34 PM   <-- | (current state, highlighted blue)
| [icon] Trim end             2:33 PM       |
| [icon] Move clip            2:32 PM       |
| [icon] Add clip             2:31 PM       |
| [icon] Import video         2:30 PM       |
+-------------------------------------------+
|         --- Redo States ---               |
| [icon] Delete clip          2:35 PM  (dim)|
+-------------------------------------------+
```

#### Widget Structure

```dart
class UndoHistoryPanel extends StatelessWidget {
  // Uses CupertinoListSection with CupertinoListTile entries
  // BackdropFilter for Liquid Glass blur background
  // CupertinoNavigationBar at top with "Undo History" title
  // Tap on any entry calls timelineManager.jumpToUndoState(index)
  // Current state highlighted with CupertinoColors.activeBlue
  // Redo states shown dimmed below the current state
}
```

#### Native Liquid Glass Styling

- Panel background: `BackdropFilter` with `ImageFilter.blur(sigmaX: 20, sigmaY: 20)`, `CupertinoColors.systemBackground.withOpacity(0.7)`
- List items: `CupertinoListTile` with SF Symbol icons per operation type
- Current state: blue accent border, filled background at 10% opacity
- Redo states: 50% opacity text, lighter background
- Timestamps: `CupertinoColors.secondaryLabel` color

### 11.5 Branching Undo

When the user edits after undoing (the standard branching problem):
- The redo stack is cleared (current behavior in `_execute()`).
- The undo history panel shows only the undo stack (linear history).
- Future enhancement: tree-based undo with branching visualization.

For V1, linear undo with redo-stack-clear is sufficient and matches most editors' behavior.

### 11.6 Memory Considerations

Each `PersistentTimeline` in the undo stack shares structure with its neighbors (structural sharing from the AVL tree). The memory overhead is proportional to the number of changed nodes, not the total timeline size.

For a timeline with 100 clips and 100 undo states:
- Each undo state changes ~O(log 100) = ~7 nodes
- Each node is ~100 bytes
- Total overhead: ~100 * 7 * 100 = ~70 KB

The `UndoHistoryEntry` metadata adds ~100 bytes per entry, so ~10 KB for 100 entries.

Total undo memory: well under 1 MB, even with 100 states and 1000 clips.

---

## 12. Timeline Zoom Pinch

### 12.1 Status: Already Implemented

The timeline zoom pinch is fully implemented in `ZoomController` (`lib/timeline/gestures/zoom_controller.dart`). This section documents the existing implementation and confirms it meets requirements.

### 12.2 Current Implementation

#### Pinch Gesture Flow:
1. `TimelineGestureHandler.onScaleStart()` detects `pointerCount >= 2`, sets `GestureState.zooming`
2. `ZoomController.startZoom()` captures focal point and anchor time
3. `ZoomController.updateZoom()` computes new `microsPerPixel` from scale ratio, clamps to `[100, 100000]` range
4. Viewport updated via `ViewportState.zoomCenteredOnTime()` to preserve anchor point
5. `ZoomController.endZoom()` fires `HapticFeedback.lightImpact()`

#### Haptic Feedback:
- `HapticFeedback.heavyImpact()` when hitting zoom limits (min/max)
- `HapticFeedback.lightImpact()` on zoom end

#### Animated Zoom:
- `ZoomController.zoomTo()` uses `AnimationController` with `CurvedAnimation`
- Convenience methods: `zoomIn()`, `zoomOut()`, `zoomToFitAll()`, `zoomToSelection()`, `zoomToTimeRange()`, `resetZoom()`
- Default curve: `Curves.easeOutCubic`, duration: 300ms

#### Zoom Limits:
- `minMicrosPerPixel = 100.0` (~10ms per pixel, frame-level detail)
- `maxMicrosPerPixel = 100000.0` (~100ms per pixel, overview)
- `defaultMicrosPerPixel = 10000.0` (~10ms per pixel)

### 12.3 Verification Checklist

- [x] Two-finger pinch zoom works
- [x] Anchor point preserved during zoom (content under fingers stays in place)
- [x] Smooth animation for programmatic zoom
- [x] Haptic feedback at zoom limits
- [x] Zoom level persisted in `ViewportState`
- [x] Zoom limits enforced
- [x] Double-tap to zoom (via `onDoubleTap` callback in gesture handler)
- [x] Zoom to fit all content (`zoomToFitAll`)
- [x] Zoom to selection (`zoomToSelection`)

No additional work needed for this feature.

---

## 13. Edge Cases & Error Handling

### 13.1 Duplicate Clip Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Duplicate at end of timeline | Clip inserted at `endTime`, extending timeline duration |
| Duplicate gap clip | Creates a new `GapClip` with same duration and new UUID |
| Duplicate clip with broken media link | Duplicate inherits `isOffline = true`, preserves `mediaAssetId` for potential relink |
| Duplicate 0 clips selected | No-op, no undo entry created |
| Duplicate with insert mode at occupied position | Insert mode pushes subsequent clips; overwrite mode replaces content |
| Duplicate at playhead inside existing clip | Behavior depends on edit mode (insert: split + push; overwrite: replace portion) |

### 13.2 Magnetic Timeline Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Delete clip with transition on either side | Remove transition as well, then close gap |
| Close gap with intentional GapClip adjacent | Stop gap-close at the GapClip boundary; do not close through intentional gaps |
| Magnetic close creates sub-frame gap | If remaining gap is < 1 frame (33,333 us at 30fps), snap to zero |
| All clips deleted except one | Single clip remains at time 0 (or wherever it was) |
| Magnetic close on track with 1000+ clips | Algorithm is O(n) per track but runs once per operation; acceptable for <2ms even with 1000 clips |
| Undo after magnetic close | Restores exact pre-operation state including the gap |

### 13.3 Waveform Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Audio file with no audio track | Return empty waveform (all zeros); show flat line |
| Corrupted audio file | Extraction fails gracefully; show placeholder indefinitely with error icon |
| Extremely long audio (>1 hour) | Extract in chunks; show progressively (first N seconds first, then extend) |
| Clip trimmed during extraction | Waveform data covers full source; clip's `sourceIn/Out` determines visible range |
| Multiple clips from same media asset | Share the same `WaveformData` instance from cache |
| App backgrounded during extraction | Extraction continues via background task; results cached on completion |
| Low memory conditions | Evict waveform cache for non-visible clips; re-extract on demand |

### 13.4 Multi-Select Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Marquee across tracks | Select clips from all tracks that intersect the rectangle |
| Marquee with 100+ clips | `findClipsInRect` is O(n) over all clips; for 100 clips this is <1ms |
| Marquee with only gap clips visible | No clips selected (gap clips are not rendered as selectable) |
| Delete multi-selection with linked clips | If a linked partner is not in the selection, warn user or auto-include it |
| Move multi-selection to different track | All selected clips move to the target track; if they came from multiple tracks, maintain relative track offsets |

### 13.5 Link/Unlink Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Link clips with different durations | Reject with validation error: "Clips must have matching durations" |
| Link clips on same track | Reject: linked clips must be on different tracks |
| Delete one of a linked pair | Delete both (linked behavior) |
| Unlink then re-link | Re-link validates same `mediaAssetId` and timing alignment |
| Import video with no audio | No audio clip created; video clip has `hasAudio = false`, no link |
| Speed change on linked pair | Both clips get same speed change (linked behavior) |

### 13.6 J-Cut / L-Cut Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| J-cut audio extends before time 0 | Clamp to time 0; cannot extend before timeline start |
| L-cut audio extends past source duration | Clamp to source duration; show warning toast |
| J/L cut with speed-changed clip | Audio overhang duration accounts for speed factor |
| J-cut audio overlaps previous clip on same audio track | Show red invalid indicator; prevent overlap (same as standard trim collision detection) |
| Undo J-cut creation | Restore original linked trim state (audio snaps back to video boundaries) |
| Replace clip media on J/L cut clip | New media must have audio track; audio overhang re-validated against new source duration |

### 13.7 Replace Clip Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Replace with different resolution | New resolution used for rendering; keyframe transforms preserved (they are relative, not absolute pixel values) |
| Replace with different frame rate | Timeline positions (microseconds) are frame-rate-independent; no adjustment needed. Keyframes at specific frames may shift slightly. |
| Replace generator clip (gap, color) | Reject: generator clips have no media to replace |
| Replace linked video clip | Both video and audio clip get new `mediaAssetId`; audio properties (waveform cache) updated |
| Replace with image (video -> image) | Convert clip type from VideoClip to ImageClip; preserve position/duration; keyframes preserved |
| New media has no audio but old clip had audio link | Unlink the audio clip; leave audio clip as independent with old media |

### 13.8 Undo History Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Undo history panel open during edit | List updates in real-time as operations are performed |
| Jump to state N, then edit | Redo states beyond N are discarded (standard branching behavior) |
| Jump to state 0 (initial state) | Timeline reset to initial import state |
| 500+ undo operations | Only last `maxUndoHistory` (100) are kept; oldest are evicted. Metadata list stays in sync. |
| Undo state references deleted media asset | Timeline state is valid (it stores `mediaAssetId`, not file content); clip shows `isOffline = true` |

### 13.9 Insert vs Overwrite Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Insert mode on empty track | No clips to push; insert at target time directly |
| Overwrite on empty region | No clips to trim/delete; insert at target time directly |
| Overwrite splits a clip that has keyframes | Keyframes partitioned correctly (same as split logic) |
| Insert at time 0 | All existing clips on track shift right |
| Multi-track insert (all tracks mode) | All tracks shift their clips right by the same amount |

---

## 14. Performance Analysis

### 14.1 Operation Complexity

| Feature | Operation | Time Complexity | Expected Latency |
|---------|-----------|----------------|------------------|
| Duplicate | `insertAt` + `getById` | O(log n) | <1ms for 1000 clips |
| Magnetic close | Track scan + moves | O(k) per track, k = clips on track | <2ms for 100 clips/track |
| Waveform extract | Native async | Background thread | 200ms-5s depending on duration |
| Waveform render | CustomPainter path | O(w) where w = clip pixel width | <1ms per clip |
| Marquee select | `findClipsInRect` | O(n) all clips | <1ms for 100 clips |
| Link propagate | `getById` + `updateItem` | O(log n) | <1ms |
| Insert mode | Scan + shift | O(k) clips on track | <2ms for 100 clips |
| Overwrite mode | Scan + trim/split | O(k) clips in range | <1ms |
| Replace clip | `updateItem` | O(log n) | <1ms |
| Undo history UI | List build | O(h) where h = history length | <1ms for 100 entries |

### 14.2 Memory Impact

| Feature | Additional Memory | Notes |
|---------|-------------------|-------|
| Duplicate | +1 tree node per duplicate | Structural sharing minimizes overhead |
| Magnetic close | 0 (in-place moves) | Part of same `_execute()` call |
| Waveform cache | ~240KB per minute of audio | At 200 samples/sec, Float32 |
| Multi-select | +Set<String> of IDs | Negligible (~8 bytes per clip ID reference) |
| Link/Unlink | +1 String field per linked clip | Already exists in model |
| Insert/Overwrite | 0 (UI state only) | Single enum value |
| J/L Cut | +1 enum field per clip | `LinkMode` enum |
| Replace | 0 (in-place update) | Structural sharing |
| Undo history metadata | ~100 bytes per entry | 100 entries = ~10 KB |

### 14.3 Frame Budget

At 60 FPS, each frame has ~16.6ms. The rendering budget is:

| Component | Budget | Current Usage | After Enhancements |
|-----------|--------|---------------|-------------------|
| Clip painting | 4ms | ~2ms (100 clips) | ~3ms (+waveform) |
| Selection overlay | 1ms | ~0.5ms | ~0.5ms (no change) |
| Snap guides | 0.5ms | ~0.2ms | ~0.2ms |
| Ruler | 0.5ms | ~0.3ms | ~0.3ms |
| Playhead | 0.2ms | ~0.1ms | ~0.1ms |
| Link indicators | 0.5ms | N/A | ~0.3ms (new) |
| Gesture processing | 2ms | ~1ms | ~1.2ms |
| Layout | 2ms | ~1ms | ~1ms |
| **Total** | **~16ms** | **~5.1ms** | **~6.6ms** |

Headroom: 10ms. Well within 60 FPS budget even after all enhancements.

### 14.4 Waveform Rendering Optimization

To avoid per-frame overhead:
1. Pre-compute waveform path for the current zoom level and cache it
2. Invalidate cache when zoom level changes (microsPerPixel changes significantly, >5% threshold)
3. Use `shouldRepaint` to skip redraws when waveform data hasn't changed
4. For clips not visible in the viewport, skip waveform path computation entirely

---

## 15. Implementation Plan

### Phase 1: Foundation (Week 1)
**Target:** Duplicate + Magnetic Timeline

| Task | Effort | File |
|------|--------|------|
| Create `DuplicateController` | 2h | `lib/timeline/editing/duplicate_controller.dart` |
| Add `duplicateItems()` to `TimelineManager` | 1h | `lib/core/timeline_manager.dart` |
| Duplicate UI (context menu + toolbar button) | 2h | Timeline toolbar widget |
| Create `GapCloseController` | 3h | `lib/timeline/editing/gap_close_controller.dart` |
| Integrate magnetic close into delete/move/trim | 2h | `lib/core/timeline_manager.dart` |
| Magnetic mode toggle UI | 1h | Timeline toolbar widget |
| Magnetic close animation (painter interpolation) | 2h | `lib/timeline/rendering/painters/` |
| Unit tests | 3h | `test/timeline/editing/` |
| **Phase 1 Total** | **16h** | |

### Phase 2: Waveform (Week 2)
**Target:** Waveform on Audio Clips

| Task | Effort | File |
|------|--------|------|
| Create `WaveformData` model | 1h | `lib/timeline/data/models/waveform_data.dart` |
| Create `WaveformCache` | 2h | `lib/timeline/data/waveform_cache.dart` |
| Swift waveform extraction plugin | 4h | `ios/Runner/WaveformExtractorPlugin.swift` |
| Platform channel bridge | 2h | `lib/services/waveform_extractor.dart` |
| `WaveformPainter` integration in `ClipsPainter` | 3h | `lib/timeline/rendering/painters/clip_painter.dart` |
| Dynamic detail based on zoom level | 2h | `lib/timeline/rendering/painters/clip_painter.dart` |
| Placeholder/loading animation | 1h | Painter code |
| Integration tests | 2h | `test/timeline/rendering/` |
| **Phase 2 Total** | **17h** | |

### Phase 3: Multi-Select + Link/Unlink (Week 3)
**Target:** Complete multi-select UX and audio-video linking

| Task | Effort | File |
|------|--------|------|
| Refine marquee gesture (real-time clip highlight) | 2h | `lib/timeline/gestures/timeline_gesture_handler.dart` |
| Multi-select operations (group delete, move, copy) | 3h | Various controllers |
| Create `LinkController` | 3h | `lib/timeline/editing/link_controller.dart` |
| Link propagation in drag/trim/delete | 3h | Gesture handler + controllers |
| Link visual indicators (chain icon, connecting line) | 2h | `ClipsPainter` + new `LinkIndicatorPainter` |
| Link/Unlink UI (context menu options) | 1h | Timeline context menu |
| Auto-link on video import | 2h | Import flow |
| Unit tests | 3h | `test/timeline/editing/` |
| **Phase 3 Total** | **19h** | |

### Phase 4: Insert/Overwrite + J/L Cuts (Week 4)
**Target:** Edit modes and professional cut types

| Task | Effort | File |
|------|--------|------|
| Create `EditModeController` | 3h | `lib/timeline/editing/edit_mode_controller.dart` |
| Insert mode implementation | 3h | Integration with paste, drag, duplicate |
| Overwrite mode implementation | 3h | Integration with paste, drag, duplicate |
| Edit mode toggle UI | 1h | Timeline toolbar |
| `LinkMode` enum and partial unlink | 2h | `lib/timeline/data/models/timeline_clip.dart` |
| J-cut / L-cut trim behavior | 3h | `TrimController` modifications |
| J/L cut visual representation (overhang rendering) | 2h | `ClipsPainter` |
| Unit tests | 3h | `test/timeline/editing/` |
| **Phase 4 Total** | **20h** | |

### Phase 5: Replace + Undo Visualization (Week 5)
**Target:** Clip replacement and undo history UI

| Task | Effort | File |
|------|--------|------|
| Create `ReplaceClipController` | 2h | `lib/timeline/editing/replace_clip_controller.dart` |
| `replaceClipMedia()` on `TimelineManager` | 1h | `lib/core/timeline_manager.dart` |
| Duration mismatch handling UI | 2h | `CupertinoActionSheet` |
| Replace clip UI flow | 2h | Context menu + media picker integration |
| `UndoHistoryEntry` model | 1h | `lib/timeline/data/models/undo_history_entry.dart` |
| Metadata tracking in `TimelineManager._execute()` | 1h | `lib/core/timeline_manager.dart` |
| `UndoHistoryPanel` widget | 3h | `lib/timeline/widgets/undo_history_panel.dart` |
| Undo history panel Liquid Glass styling | 2h | Widget code |
| `jumpToUndoState()` implementation | 1h | `lib/core/timeline_manager.dart` |
| Unit tests | 3h | `test/timeline/` |
| **Phase 5 Total** | **18h** | |

### Total Effort Estimate

| Phase | Hours | Calendar |
|-------|-------|----------|
| Phase 1: Duplicate + Magnetic | 16h | Week 1 |
| Phase 2: Waveform | 17h | Week 2 |
| Phase 3: Multi-Select + Link | 19h | Week 3 |
| Phase 4: Insert/Overwrite + J/L | 20h | Week 4 |
| Phase 5: Replace + Undo History | 18h | Week 5 |
| **Total** | **90h** | **5 weeks** |

---

## 16. Testing Strategy

### 16.1 Unit Tests

Each controller gets a dedicated test file:

| Controller | Test File | Key Test Cases |
|-----------|-----------|----------------|
| `DuplicateController` | `test/timeline/editing/duplicate_controller_test.dart` | Single/multi duplicate, in-place/at-playhead, property preservation, linked clip handling |
| `GapCloseController` | `test/timeline/editing/gap_close_controller_test.dart` | Gap detection, single/multi track close, intentional gap preservation, sub-frame gap snap |
| `LinkController` | `test/timeline/editing/link_controller_test.dart` | Link/unlink, validation, operation propagation, partial unlink (J/L cuts) |
| `EditModeController` | `test/timeline/editing/edit_mode_controller_test.dart` | Insert shift calculation, overwrite trim/split, edge cases at boundaries |
| `ReplaceClipController` | `test/timeline/editing/replace_clip_controller_test.dart` | Validation, duration mismatch strategies, property transfer |
| `WaveformCache` | `test/timeline/data/waveform_cache_test.dart` | Cache hit/miss, eviction, memory tracking |

### 16.2 Integration Tests

| Test | Scope |
|------|-------|
| Duplicate + undo/redo | Full cycle: duplicate, verify state, undo, verify restored |
| Magnetic delete + transition | Delete clip between two clips with transition, verify gap closed and transition removed |
| Marquee select + group delete | Draw marquee, verify correct clips selected, delete all, verify magnetic close |
| J-cut creation + undo | Create J-cut, verify audio extends, undo, verify restored |
| Replace + waveform update | Replace clip media, verify waveform cache invalidated and re-extracted |
| Insert mode paste + undo | Paste with insert mode, verify clips shifted, undo, verify original positions |

### 16.3 Performance Tests

| Test | Metric | Threshold |
|------|--------|-----------|
| Duplicate 100 clips | Latency | <10ms |
| Magnetic close 100 clips/track | Latency | <5ms |
| Waveform render 50 visible clips | Frame time | <4ms |
| Marquee select over 500 clips | Selection time | <5ms |
| Undo history with 100 entries | Panel build time | <16ms (1 frame) |
| Insert mode with 1000 clips on track | Shift calculation | <10ms |

### 16.4 Snapshot Tests

Painters are tested via golden (snapshot) tests:
- Waveform rendering at various zoom levels
- Link indicators between tracks
- J/L cut overhang visualization
- Selection overlay with multi-select
- Marquee rectangle during drag

---

## 17. File Structure

### 17.1 New Files

```
lib/
  timeline/
    editing/
      duplicate_controller.dart          # Phase 1
      gap_close_controller.dart          # Phase 1
      link_controller.dart               # Phase 3
      edit_mode_controller.dart          # Phase 4
      replace_clip_controller.dart       # Phase 5
    data/
      models/
        waveform_data.dart               # Phase 2
        undo_history_entry.dart          # Phase 5
        link_mode.dart                   # Phase 4
      waveform_cache.dart                # Phase 2
    rendering/
      painters/
        link_indicator_painter.dart      # Phase 3
    widgets/
      undo_history_panel.dart            # Phase 5
  services/
    waveform_extractor.dart              # Phase 2

ios/
  Runner/
    WaveformExtractorPlugin.swift        # Phase 2

test/
  timeline/
    editing/
      duplicate_controller_test.dart     # Phase 1
      gap_close_controller_test.dart     # Phase 1
      link_controller_test.dart          # Phase 3
      edit_mode_controller_test.dart     # Phase 4
      replace_clip_controller_test.dart  # Phase 5
    data/
      waveform_cache_test.dart           # Phase 2
    rendering/
      waveform_painter_test.dart         # Phase 2
      link_indicator_painter_test.dart   # Phase 3
```

### 17.2 Modified Files

```
lib/
  core/
    timeline_manager.dart                # All phases (new methods, metadata tracking)
  timeline/
    data/
      models/
        timeline_clip.dart               # Phase 4 (LinkMode enum)
    gestures/
      timeline_gesture_handler.dart      # Phase 3, 4 (link propagation, edit mode)
      drag_controller.dart               # Phase 3 (linked clip inclusion)
      trim_controller.dart               # Phase 4 (J/L cut independent trim)
    rendering/
      painters/
        clip_painter.dart                # Phase 2, 3, 4 (waveform, link icon, J/L overhang)
        selection_overlay_painter.dart   # Phase 3 (marquee real-time highlight)
    editing/
      clipboard_controller.dart          # Phase 1 (duplicate integration)
      ripple_trim_controller.dart        # Phase 1 (magnetic close integration)
```

---

## Appendix A: SF Symbol References

| Feature | Symbol Name | Usage |
|---------|-------------|-------|
| Duplicate | `plus.rectangle.on.rectangle` | Toolbar button |
| Magnetic toggle | `magnet` | Toolbar toggle |
| Insert mode | `arrow.right.to.line.compact` | Mode indicator |
| Overwrite mode | `rectangle.on.rectangle` | Mode indicator |
| Link | `link` | Clip indicator, context menu |
| Unlink | `link.badge.plus` | Context menu |
| Replace | `arrow.2.squarepath` | Context menu, toolbar |
| Undo history | `clock.arrow.circlepath` | Panel trigger button |
| J-cut | `arrow.left.and.line.vertical.and.arrow.right` | Context menu |
| L-cut | `arrow.right.and.line.vertical.and.arrow.left` | Context menu |
| Waveform | `waveform` | Track header indicator |

## Appendix B: Haptic Feedback Map

| Action | Haptic Type | Rationale |
|--------|-------------|-----------|
| Clip duplicated | `mediumImpact` | Confirms creation action |
| Gap closed (animation start) | `lightImpact` | Subtle confirmation |
| Magnetic mode toggled | `selectionClick` | State change acknowledgment |
| Marquee selection started | `mediumImpact` (from long press) | Already implemented |
| Clips selected via marquee | `selectionClick` | As clips enter selection |
| Link/unlink completed | `mediumImpact` | Relationship change |
| Edit mode toggled | `selectionClick` | State change |
| J/L cut audio overhang created | `selectionClick` | Trim feedback |
| Replace clip completed | `mediumImpact` | Content change |
| Undo history jump | `lightImpact` | Navigation action |
| Zoom limit hit | `heavyImpact` | Already implemented |

## Appendix C: Glossary

| Term | Definition |
|------|-----------|
| **Structural sharing** | When two immutable data structures share unchanged subtrees, minimizing memory for undo states |
| **Ripple** | Shifting subsequent clips to fill or make space after an edit |
| **Magnetic timeline** | Automatic gap closure after edit operations |
| **J-Cut** | Audio from next clip starts before its video appears |
| **L-Cut** | Audio from current clip continues after next clip's video ends |
| **Slip** | Moving source content within clip boundaries without changing timeline position |
| **Slide** | Moving a clip's position while adjacent clips adjust |
| **Order Statistic Tree** | A balanced BST augmented with subtree size/duration for O(log n) positional queries |
| **Overwrite edit** | Placing content that replaces existing clips at the target position |
| **Insert edit** | Placing content that pushes existing clips to the right |

---

## Review 1 - Architecture & Completeness

**Reviewer:** Senior Architecture Review
**Date:** 2026-02-06
**Scope:** Architecture validation, completeness check, code conflict analysis, edge case coverage, performance, undo/redo, gesture integration, rendering feasibility
**Status:** Review Complete - 8 CRITICAL, 12 IMPORTANT, 9 MINOR, 6 QUESTION

---

### CRITICAL Issues

#### C1. PersistentTimeline is single-track, but design assumes multi-track operations

**Severity:** CRITICAL
**Sections Affected:** 4 (Magnetic Timeline), 6 (Marquee), 7 (Link/Unlink), 8 (Insert/Overwrite), 9 (J/L Cuts)

The `PersistentTimeline` (persistent AVL order statistic tree) is a **single linear sequence** of `TimelineItem` objects. It has no concept of tracks -- items are ordered sequentially by cumulative duration, not by track. The `TimelineClip` UI model has a `trackId` field, but the underlying `PersistentTimeline` stores items in a flat sequence.

However, the design document repeatedly references track-scoped operations:
- Section 4.2.4: `closeGapsOnTrack(trackId, clips)` -- operates on a per-track basis
- Section 4.3: `GapCloseController.detectAndClose({trackId})` -- filters by track
- Section 7.2: "Create a `VideoClip` on the main video track" and "Create an `AudioClip` on an audio track"
- Section 8.3.1: "Find all clips on the target track that start at or after time `T`"

**The fundamental architecture conflict:** Either (a) the `PersistentTimeline` is being used as a per-track structure (one tree per track), or (b) the design assumes multi-track awareness in the tree itself. The document does not clarify which model is in use.

Looking at the code: `TimelineManager._execute()` takes a closure that returns a new `PersistentTimeline`. The `TimelineClip` model (used by the rendering layer) is separate from the `TimelineItem` model (used by `PersistentTimeline`). There appears to be a mapping layer between them, but the design document treats them as if the `PersistentTimeline` directly supports track-scoped queries.

**Required Resolution:** The design must explicitly document the mapping between `PersistentTimeline` (single-track flat sequence) and the multi-track `TimelineClip` model. Either:
1. Specify that there is one `PersistentTimeline` per track, with the `TimelineManager` managing a `Map<String, PersistentTimeline>` -- but the current code shows a single `_current` field.
2. Specify that the `PersistentTimeline` stores all items from all tracks in a flattened sequence, and track-scoped queries are done by filtering `toList()` -- but this defeats O(log n) for per-track operations.
3. Introduce a multi-track container that wraps per-track `PersistentTimeline` instances.

Without this clarification, **every feature that operates per-track** has undefined behavior relative to the actual data structure.

---

#### C2. `TimelineManager.duplicateItems()` assumes tree supports `startTimeOf()` and `insertAt()` as sequential operations, but structural sharing may invalidate ID index between calls

**Severity:** CRITICAL
**Section Affected:** 3.3 (Duplicate Data Layer)

The proposed `duplicateItems()` method (Section 3.3) iterates over `itemIds`, calling `timeline.getById(itemId)` and `timeline.startTimeOf(itemId)` on the evolving `var timeline`. However, after each `timeline = timeline.insertAt(targetTime, duplicate)`, the ID index cache (an `Expando`-based lazy cache on `PersistentTimeline`) is rebuilt for the new instance. The `Expando` cache for the **previous** instance is still valid because the old tree is not mutated -- but the **new** tree instance after `insertAt` does not automatically carry the old index.

For the second clip in a multi-clip duplicate, `timeline.getById(itemId)` on the **new** tree will trigger a full O(n) `toList()` to rebuild the ID index, because the item's position in the tree may have shifted due to the first insert.

**Moreover**, if two clips have adjacent positions on the timeline and the first duplicate's `insertAt` shifts the second clip, `startTimeOf(itemId)` will return the **updated** start time (post-shift). This may or may not be desired -- the document does not specify whether duplicates should be calculated against the original positions or the evolving state.

**Required Resolution:**
1. Capture all clip data and start times **before** beginning mutations (snapshot approach).
2. Apply all inserts in a single batch, or sort by descending time to avoid position shifts affecting subsequent lookups.
3. Document the expected behavior for overlapping duplicates.

---

#### C3. `LinkMode` enum not present on `TimelineClip` -- requires model change and serialization update

**Severity:** CRITICAL
**Sections Affected:** 9.3.3 (J/L Cut Partial Unlink), 17.2 (Modified Files)

The design introduces `LinkMode` (Section 9.3.3) with three states: `full`, `trimIndependent`, `none`. However, `TimelineClip` (line 101-102) currently only has `linkedClipId: String?`. There is no `linkMode` field.

Adding `LinkMode` to `TimelineClip` requires:
1. A new field: `final LinkMode linkMode;`
2. Updates to `copyWith()` (currently has `clearLinkedClipId` but no `linkMode` parameter)
3. Updates to `toJson()` / `fromJson()` for persistence
4. Updates to `operator ==` and `hashCode` (currently includes `linkedClipId` but not `linkMode`)
5. Updates to all places that check `clip.linkedClipId != null` to also check `linkMode`

The design mentions this in Section 17.2 ("Phase 4 (LinkMode enum)") but does not specify the `TimelineClip.copyWith` changes or the serialization/equality impact. This is a breaking model change that must be carefully planned.

**Required Resolution:** Add explicit `TimelineClip` model diff showing the field addition, `copyWith` parameter, serialization format, and backward compatibility handling for projects saved without `linkMode`.

---

#### C4. Magnetic gap-close algorithm operates on `List<TimelineClip>` (UI model), but mutations must go through `PersistentTimeline` (data model)

**Severity:** CRITICAL
**Sections Affected:** 4.3 (Gap Close Integration), 4.2.4 (Algorithm)

The gap-close algorithm (Section 4.2.4) operates on `List<TimelineClip>` sorted by `startTime`. It produces a list of `ClipMove` objects. However, applying these moves requires calling `PersistentTimeline.updateItem()` for each moved clip.

The issue: `TimelineClip` is a **rendering model** that does not exist in the `PersistentTimeline`. The tree stores `TimelineItem` instances (`VideoClip`, `AudioClip`, `GapClip`, etc.). There is no documented mapping from a `ClipMove` on a `TimelineClip` to a mutation on the `PersistentTimeline`.

The integration code in Section 4.3 shows:
```dart
void removeWithMagnetic(String itemId) {
  _execute(() {
    var timeline = _current.remove(itemId);
    if (_magneticMode != MagneticMode.off) {
      timeline = _applyGapClose(timeline);
    }
    return timeline;
  }, operationName: 'Delete clip');
}
```

But `_applyGapClose(timeline)` is not defined. How does it obtain `List<TimelineClip>` from a `PersistentTimeline`? The tree does not store `trackId` on its `TimelineItem` nodes -- `trackId` is only on `TimelineClip`.

**Required Resolution:** Either:
1. Add track awareness to `PersistentTimeline` / `TimelineItem`, or
2. Document the conversion path from `PersistentTimeline.toList()` -> track grouping -> gap detection -> `ClipMove` -> tree mutations, including complexity implications (this may degrade the O(log n) advantage to O(n)).

---

#### C5. Dual manager architecture (ClipManager V1 + TimelineManager V2) creates undefined interaction for new features

**Severity:** CRITICAL
**Sections Affected:** All feature sections

The codebase has TWO clip managers:
1. `ClipManager` (V1) -- mutable `List<TimelineItem>` with command pattern (`SplitCommand`, `DeleteCommand`, etc.)
2. `TimelineManager` (V2) -- immutable `PersistentTimeline` with `_execute()` pattern

Both coexist in the codebase (Section 2.2 acknowledges this: "Coexists with `TimelineManager` (V1 vs V2 architecture)").

The design document adds all new features to `TimelineManager` (V2). However, it does not specify:
1. Whether `ClipManager` is still actively used by any UI code paths
2. Whether operations must be synchronized between the two managers
3. Whether V1 should be deprecated before implementing these features
4. What happens if a user triggers a V1 operation (e.g., `SplitCommand`) interleaved with V2 operations (e.g., `duplicateItems()`)

**Required Resolution:** Add a section explicitly stating the migration plan. Either V1 is fully deprecated (and the design should note which callsites need migration), or V1/V2 coexistence rules must be specified to prevent state desynchronization.

---

#### C6. Waveform inner loop in `_drawWaveform` has O(samplesPerPixel) per pixel, making total cost O(width * samplesPerPixel) -- can exceed frame budget for wide clips

**Severity:** CRITICAL
**Section Affected:** 5.6 (Waveform Rendering)

The waveform rendering code (Section 5.6) contains a nested loop:

```dart
for (double px = 0; px < clipRect.width; px += 1.0) {
  // Inner loop: iterate from sampleIdx to endIdx
  for (int i = sampleIdx; i <= endIdx; i++) {
    if (waveform.samples[i] > peak) peak = waveform.samples[i];
  }
}
```

Then the same loop is repeated for the mirror (bottom half). For a 1000-pixel-wide clip at 200 samples/sec with zoom level giving `samplesPerPixel = 10`, this is:
- Outer: 1000 iterations
- Inner: 10 iterations per outer
- Mirror: same again
- Total: ~20,000 iterations per clip

For 10 visible audio clips: ~200,000 iterations per frame. With Float32 access and branch prediction, this is likely ~0.5-1ms. Still within budget, but Section 14.3 estimates only "+1ms" for waveform rendering across all clips -- this may be optimistic for high-zoom scenarios where `samplesPerPixel` is 1 or less (Bezier interpolation is mentioned but not budgeted).

More critically, the code builds a `Path` with 2000+ points (1000 top + 1000 bottom) per clip per frame. The `canvas.drawPath` call with a filled complex path can be expensive, especially on older iOS devices.

**Required Resolution:**
1. Add pre-computed waveform path caching per clip per zoom level (mentioned in Section 14.4 but not shown in Section 5.6 code).
2. Move the inner peak-finding loop to a precomputation step that runs when zoom changes, not every frame.
3. Use `Path.addPolygon` with pre-computed points for better GPU performance.
4. Add the caching mechanism to the `ClipsPainter` constructor or `shouldRepaint` logic.

---

#### C7. `jumpToUndoState()` implementation uses sequential `undo()` calls, which is O(k) not O(1)

**Severity:** CRITICAL
**Section Affected:** 11.3 (TimelineManager Changes)

The proposed `jumpToUndoState()` implementation (Section 11.3):

```dart
void jumpToUndoState(int index) {
  if (index < 0 || index >= _undoStack.length) return;
  final stepsToUndo = _undoStack.length - 1 - index;
  for (int i = 0; i < stepsToUndo; i++) {
    undo();
  }
}
```

This calls `undo()` k times, each of which calls `notifyListeners()`, triggers composition rebuild, and validates selection. For jumping from state 100 to state 0, this fires 100 `notifyListeners()` calls and 100 composition rebuilds.

This violates the design principle of "O(1) undo/redo" and will cause severe UI jank (100 rebuilds in a single synchronous call).

**Required Resolution:** Implement `jumpToUndoState()` as a direct pointer swap:

```dart
void jumpToUndoState(int index) {
  if (index < 0 || index >= _undoStack.length) return;
  // Move states between stacks without intermediate notifications
  final stepsToUndo = _undoStack.length - index;
  for (int i = 0; i < stepsToUndo; i++) {
    _redoStack.add(_current);
    _redoMetadata.add(_undoMetadata.removeLast()); // fix: metadata must also move
    _current = _undoStack.removeLast();
  }
  _compositionDirty = true;
  notifyListeners(); // Single notification
}
```

Also needs corresponding metadata stack manipulation and `_redoMetadata` synchronization.

---

#### C8. `_execute()` signature change for metadata breaks all existing callers

**Severity:** CRITICAL
**Section Affected:** 11.3 (TimelineManager._execute Changes)

The proposed `_execute()` modification (Section 11.3) adds required parameters:

```dart
void _execute(
  PersistentTimeline Function() mutation, {
  String? operationName,
  UndoOperationType type = UndoOperationType.other,
  int affectedClipCount = 0,
})
```

While `type` and `affectedClipCount` have defaults (so technically non-breaking), the implementation also changes the internal logic: it now adds to `_undoMetadata`, trims `_undoMetadata`, clears `_redoMetadata`.

The issue: Every existing `_execute()` call (insert, append, remove, updateItem, splitAt, trimStart, trimEnd, addKeyframe, removeKeyframe, clear -- at least 12 callsites) would need to be audited and updated to pass meaningful `UndoOperationType` values. Without this, all operations show as `UndoOperationType.other` in the undo history panel, which defeats the purpose of the feature.

Additionally, the `undo()` and `redo()` methods must be updated to move metadata between stacks, but the design only shows the `_execute()` change -- it does not show the corresponding `undo()` / `redo()` metadata handling.

**Required Resolution:**
1. Show the full `undo()` and `redo()` method changes including metadata stack manipulation.
2. Provide a migration table mapping each existing `_execute()` callsite to its `UndoOperationType`.
3. Consider deriving `UndoOperationType` from `operationName` strings automatically (pattern matching) to reduce migration burden.

---

### IMPORTANT Issues

#### I1. Magnetic timeline does not account for transitions between clips

**Severity:** IMPORTANT
**Section Affected:** 4.2, 13.2

Section 13.2 mentions "Delete clip with transition on either side: Remove transition as well, then close gap." However, the gap-close algorithm (Section 4.2.4) has no awareness of `ClipTransition` objects. The `ClipTransition` model (in `transition.dart`) references `leftClipId` and `rightClipId`. When a clip is deleted and gaps are closed:

1. Transitions referencing the deleted clip become orphaned.
2. If subsequent clips slide left, their `editPointTime` in existing transitions becomes invalid.
3. The algorithm does not specify where/how transition cleanup happens.

**Required Resolution:** The `GapCloseController.detectAndClose()` must accept a `List<ClipTransition>` parameter. Return value should include `transitionsToRemove: List<String>` (IDs) and `transitionsToUpdate: List<ClipTransition>` (with adjusted `editPointTime`).

---

#### I2. Link propagation in gesture handler uses `firstWhere` without null safety

**Severity:** IMPORTANT
**Section Affected:** 7.6 (Integration with Gesture Handler)

The proposed code:
```dart
final clip = _clips.firstWhere((c) => c.id == clipId);
```

This will throw `StateError` if the clip ID is not found in `_clips`. Since `_selection.selectedClipIds` may contain IDs for clips that have been removed (e.g., after undo), this is a potential crash.

**Required Resolution:** Use `firstWhereOrNull` or wrap in try-catch. Apply defensively throughout all linked clip lookups.

---

#### I3. Clipboard `duplicate()` method already exists but behaves differently from design's `DuplicateController`

**Severity:** IMPORTANT
**Sections Affected:** 3.4 (DuplicateController), existing `ClipboardController.duplicate()`

The existing `ClipboardController.duplicate()` (clipboard_controller.dart line 255-282) already implements duplication with:
- New UUID via `_uuid.v4()`
- Optional `timeOffset` parameter
- `clearLinkedClipId: true`

The design proposes a NEW `DuplicateController` (Section 3.4) with separate methods. This creates **two places** that implement duplication logic, violating DRY. The existing `ClipboardController.duplicate()` does NOT append "(copy)" to the label (it preserves the label as-is), but the design says it should (via `clip.duplicate()` on the domain model).

**Required Resolution:** Either:
1. Extend `ClipboardController.duplicate()` to cover all cases (in-place, at-time, with-ripple), or
2. Create `DuplicateController` but have `ClipboardController.duplicate()` delegate to it, or
3. Remove `ClipboardController.duplicate()` and redirect all callers to `DuplicateController`.

---

#### I4. Two-finger drag for marquee (Section 6.3.1) conflicts with zoom gesture detection

**Severity:** IMPORTANT
**Section Affected:** 6.3.1 (Marquee Trigger)

The design proposes two-finger drag as an alternative marquee trigger: "If both fingers move in the same direction with similar velocity, it is a two-finger scroll or marquee. If fingers diverge/converge, it is a pinch zoom."

However, `TimelineGestureHandler.onScaleStart()` (line 307-308) currently treats ALL `pointerCount >= 2` as zoom:
```dart
if (details.pointerCount >= 2) {
  _state = GestureState.zooming;
  zoomController.startZoom(...);
}
```

Differentiating between "same-direction two-finger" and "diverging two-finger" requires analyzing `ScaleUpdateDetails` after the gesture starts -- you cannot determine this at `onScaleStart`. This means:
1. The gesture must start as `zooming`, then transition to `marqueeSelecting` if the fingers are detected as same-direction.
2. State transitions from `zooming` to `marqueeSelecting` are not currently handled (and would require `ZoomController.cancelZoom()` + marquee start).
3. The velocity/direction analysis adds per-frame overhead.

**Required Resolution:** Either drop the two-finger marquee (long-press is sufficient) or design a robust gesture disambiguation flow with clear transition rules. Long-press is already implemented and works; adding two-finger adds significant complexity for marginal UX gain on a mobile device.

---

#### I5. `GapCloseController.mode` is mutable state on a controller -- should be immutable or managed by a state holder

**Severity:** IMPORTANT
**Section Affected:** 4.3 (GapCloseController)

The proposed `GapCloseController` has:
```dart
MagneticMode mode = MagneticMode.track;
```

This is mutable state on a controller. If the `GapCloseController` is shared (e.g., singleton or injected), changing `mode` during an operation could cause race conditions. All other existing controllers follow this pattern too (e.g., `RippleTrimController.mode`, `SlideController.mode`), so this is consistent with the codebase -- but it's worth noting for future refactoring.

**Required Resolution:** Acceptable for consistency, but consider passing `MagneticMode` as a parameter to `detectAndClose()` instead of storing it as mutable state. This matches the immutability-first principle.

---

#### I6. Replace clip (Section 10) preserves clip `id` but changes `mediaAssetId` -- waveform cache invalidation not specified

**Severity:** IMPORTANT
**Sections Affected:** 10.2.4 (Property Transfer), 5.5 (Waveform Cache)

When a clip's media is replaced, the `WaveformCache` keyed by `mediaAssetId` needs to:
1. Trigger extraction for the new `mediaAssetId` (if not already cached).
2. The old `mediaAssetId` cache entry should NOT be evicted (other clips may reference it).
3. The rendering layer must detect the `mediaAssetId` change to switch waveform data.

The design mentions this in Section 13.7 ("Replace clip media on J/L cut clip: New media must have audio track; audio overhang re-validated") and the testing section mentions "Replace + waveform update," but the actual cache invalidation flow is not specified.

**Required Resolution:** Add a waveform cache invalidation hook in `replaceClipMedia()` or document that `ClipsPainter` automatically picks up the correct waveform via `clip.mediaAssetId` lookup in `WaveformCache`.

---

#### I7. Overwrite mode split-at-both-ends case creates 3 clips from 1, but only specifies deleting "the middle portion"

**Severity:** IMPORTANT
**Section Affected:** 8.3.2 (Overwrite Mode)

The overwrite specification says: "If it spans the entire range (starts before T, ends after T+D): split at T and T+D, delete the middle portion."

This creates 3 segments: left (before T), middle (T to T+D, deleted), right (after T+D). The right segment needs a new clip ID (from the split). The design does not specify:
1. How the right segment's `linkedClipId` is handled (if the original clip was linked)
2. How keyframes are partitioned across the 3 segments (split logic handles 2-way, not 3-way)
3. Whether the existing `SplitController.splitClip()` can be called twice in sequence (first at T, then at T+D on the right portion)

**Required Resolution:** Specify the 3-way split explicitly. Recommend implementing as two sequential 2-way splits: split at T (produces left + remaining), then split remaining at T+D (produces middle + right), then delete middle.

---

#### I8. `_execute()` mutation closure captures `_current` by closure, not by value

**Severity:** IMPORTANT
**Section Affected:** 3.3 (duplicateItems), 4.3 (removeWithMagnetic)

The proposed `duplicateItems()` code:
```dart
_execute(() {
  var timeline = _current;
  for (final itemId in itemIds) {
    // ...
    timeline = timeline.insertAt(targetTime, duplicate);
  }
  return timeline;
}, operationName: '...');
```

Inside `_execute()`, the closure is invoked AFTER `_undoStack.add(_current)` (line 124 of timeline_manager.dart). The closure then reads `_current` -- which is the SAME reference that was just pushed to the undo stack. This is correct because `PersistentTimeline` is immutable, so the push doesn't affect the closure's `_current`. However, this pattern is fragile -- if anyone adds mutation of `_current` before the closure call in `_execute()`, the closure would see the wrong state.

**Required Resolution:** Consider passing `_current` as a parameter to the mutation closure: `PersistentTimeline Function(PersistentTimeline current) mutation`, and invoke as `_current = mutation(_current)`. This makes the contract explicit and avoids capture ambiguity.

---

#### I9. Undo history panel shows `undoHistory` and `redoHistory` as unmodifiable lists -- but these are computed on every access

**Severity:** IMPORTANT
**Section Affected:** 11.3 (TimelineManager Changes)

```dart
List<UndoHistoryEntry> get undoHistory => List.unmodifiable(_undoMetadata);
List<UndoHistoryEntry> get redoHistory => List.unmodifiable(_redoMetadata);
```

Each call to `undoHistory` creates a new `UnmodifiableListView` wrapper. If the `UndoHistoryPanel` widget calls these getters during every `build()`, and the panel rebuilds frequently (e.g., listening to `TimelineManager` notifications), this creates garbage. For 100 entries, this is a trivial allocation, but it's worth noting.

**Required Resolution:** Cache the unmodifiable views and invalidate on change. Or use `ValueNotifier<List<UndoHistoryEntry>>` for targeted rebuilds.

---

#### I10. `ImageClip` not handled in `duplicateItems()` type switch

**Severity:** IMPORTANT
**Section Affected:** 3.3 (duplicateItems code)

The `duplicateItems()` code handles `VideoClip`, `AudioClip`, `GapClip`, `ColorClip` but does NOT handle `ImageClip`. From the clip hierarchy in Section 2.1:
```
MediaClip (abstract)
  +-- VideoClip
  +-- AudioClip
  +-- ImageClip (...)
```

If an `ImageClip` is in the selection, it is silently skipped (`continue`). The design specifies that `ImageClip` exists in the hierarchy but doesn't mention its `duplicate()` method.

**Required Resolution:** Add `ImageClip` to the type switch, or use a generic approach: `if (item is MediaClip) { duplicate = item.duplicate(); }` if all `MediaClip` subclasses have a `duplicate()` method.

---

#### I11. Multi-select drag across tracks does not specify track offset preservation

**Severity:** IMPORTANT
**Section Affected:** 6.3.5 (Operations on Multi-Selection)

The table states: "Move multi-selection to different track: All selected clips move to the target track; if they came from multiple tracks, maintain relative track offsets."

However, tracks are identified by `String id`, not by integer index. "Relative track offset" implies calculating `targetTrackIndex - primaryClipTrackIndex` and applying that delta to all clips' track indices. This requires:
1. Converting `trackId` to `index` for all clips
2. Computing the track offset from the drag target
3. Finding tracks at the computed indices
4. Handling cases where computed target tracks don't exist (e.g., dragging 3-track selection down when only 2 tracks exist below)

The `ClipDragController` currently does not implement cross-track relative offset logic.

**Required Resolution:** Specify the track offset algorithm and its edge cases (non-existent target tracks, locked tracks, incompatible track types).

---

#### I12. Waveform extraction cancellation and cleanup not fully specified

**Severity:** IMPORTANT
**Section Affected:** 5.4 (Native Extraction Pipeline)

The `WaveformExtractor.cancelExtraction(String mediaAssetId)` method is declared but:
1. No mechanism for the native side to receive cancellation (the Swift code uses `AVAssetReader.startReading()` which cannot be cancelled mid-read without calling `reader.cancelReading()`)
2. No handling of the race condition: extraction completes just as cancel is called
3. No handling of Flutter engine hot restart (native task continues, Flutter side loses reference)
4. `_pending` set in `WaveformCache` is not cleared on cancellation

**Required Resolution:** Specify the cancellation protocol: native side checks a cancellation flag between buffer reads; platform channel sends cancel message; cache marks the extraction as cancelled to reject late-arriving results.

---

### MINOR Issues

#### M1. `DuplicateController` class may be unnecessary

**Severity:** MINOR
**Section Affected:** 3.4

The `DuplicateController` has three methods, all of which could be static utility functions or methods on `TimelineManager`. Given that `ClipboardController` already has a `duplicate()` method, adding a third place for duplication logic increases surface area. Consider whether this controller earns its class.

---

#### M2. `loopMedia` in `DurationMismatchStrategy` not documented in behavior spec

**Severity:** MINOR
**Section Affected:** 10.4

The enum has `loopMedia` but Section 10.2.3 only describes `shorten`, `freezeLastFrame`, and `cancel`. `loopMedia` is never mentioned in the behavior specification.

**Required Resolution:** Either document looping behavior or remove the enum value.

---

#### M3. Waveform `Float32List` constructor uses `const` but `Float32List` is not const-constructible

**Severity:** MINOR
**Section Affected:** 5.2

The `WaveformData` class is declared `@immutable` with `const` constructor, but `Float32List` cannot be used in const contexts. The `const` keyword on the constructor is misleading since no instance can actually be `const` (due to `Float32List`).

**Required Resolution:** Remove `const` from the `WaveformData` constructor, or document that `isPlaceholder` instances use an empty `Float32List()`.

---

#### M4. Haptic feedback for "clips selected via marquee" says `selectionClick` fires "as clips enter selection"

**Severity:** MINOR
**Section Affected:** Appendix B

Firing `selectionClick` on every frame during marquee drag (as clips enter/leave selection) would be excessive. If the marquee passes over 20 clips, that's 20+ haptic events in rapid succession.

**Required Resolution:** Fire haptic once when the selection count changes, not on every frame. Or debounce to max 1 haptic per 200ms.

---

#### M5. SF Symbol `link.badge.plus` for Unlink is semantically incorrect

**Severity:** MINOR
**Section Affected:** Appendix A

`link.badge.plus` suggests "add link" (plus badge on link). For "Unlink," a more appropriate symbol would be `link.slash` or `link.circle.fill` with a slash overlay.

**Required Resolution:** Use `link` with a crossed-out visual or a different SF Symbol for unlink.

---

#### M6. `UndoHistoryEntry.affectedClipCount` default is 0 for all existing operations

**Severity:** MINOR
**Section Affected:** 11.2, 11.3

Since `affectedClipCount` defaults to `0` in the `_execute()` signature, all existing operations (insert, remove, trim, etc.) will show `affectedClipCount: 0` in the undo history. This makes the field useless unless every existing callsite is updated.

**Required Resolution:** Either derive `affectedClipCount` automatically (e.g., diff old and new tree counts), or accept that this field is aspirational and not populated for V1.

---

#### M7. `SelectionState.selectClips()` resets mode to `normal`, clearing marquee state during drag

**Severity:** MINOR
**Section Affected:** 6.5 (Gesture Handler Changes)

In `_updateMarqueeSelection()`, the code calls:
```dart
_selection = _selection.selectClips(clipIds);
```

`selectClips()` (selection_state.dart line 225-231) sets `mode: SelectionMode.normal`. But during an active marquee drag, the mode should remain `SelectionMode.marquee`. This means every marquee update call resets the mode to `normal`, then the next line needs to re-set it to `marquee`.

Looking at the actual `_updateMarqueeSelection()` code in timeline_gesture_handler.dart (line 592-613), the `updateMarquee()` call before `selectClips()` does NOT set the mode -- it only updates `marqueeEnd`. Then `selectClips()` sets mode to `normal`. The marquee visual would still work (since `marqueeStart`/`marqueeEnd` are preserved), but `selection.isMarqueeSelecting` would return `false` during the drag.

**Required Resolution:** Use `_selection.copyWith(selectedClipIds: clipIds)` instead of `_selection.selectClips(clipIds)` during marquee to avoid mode reset.

---

#### M8. Phase 2 effort estimate for Swift waveform extraction (4h) seems optimistic

**Severity:** MINOR
**Section Affected:** 15 (Phase 2)

Implementing AVFoundation audio extraction, platform channel bridge, background thread management, error handling, cancellation, and buffer-to-Float32 conversion in 4 hours is aggressive. Similar implementations in production codebases typically take 8-12 hours including edge cases (multi-channel audio, varying sample rates, DRM content, compressed formats).

---

#### M9. `ImageClip` not mentioned in Replace Clip type compatibility matrix

**Severity:** MINOR
**Section Affected:** 10.2.2

"New media must be the same type (video replaces video, audio replaces audio; image can replace video or image)." This says image can replace video, but does not specify: Can video replace image? If a 5-second video replaces a 5-second image clip, the image has no `sourceIn`/`sourceOut` -- how are these initialized?

---

### QUESTION Items

#### Q1. Does `PersistentTimeline.insertAt()` handle inserting at a position that falls inside an existing item?

The gap-close algorithm and insert mode both involve inserting at arbitrary times. If `insertAt(T, item)` is called and time T falls within an existing item, does it split that item, or shift it? The `PersistentTimeline` documentation says it inserts "at time position" but the behavior for mid-item insertion is not clear from the interface.

---

#### Q2. What is the source of truth for track assignments?

`TimelineClip` has `trackId`, but `PersistentTimeline` stores `TimelineItem` (which has no `trackId`). Where is the mapping from `TimelineItem.id` to `trackId` maintained? Is there a separate track assignment table? This is critical for understanding how multi-track features integrate.

---

#### Q3. Should linked clips share the same `PersistentTimeline` position, or occupy separate positions on different track timelines?

If the system uses one `PersistentTimeline` per track, linked video and audio clips are in separate trees. If it uses a single flat timeline, they occupy adjacent positions. The design's link propagation logic depends heavily on which model is used.

---

#### Q4. For J/L cuts, when audio extends beyond video, does the audio clip overlap with adjacent clips on the audio track?

The design says "J-cut audio overlaps previous clip on same audio track: Show red invalid indicator; prevent overlap." But what about the rendering -- does the overhang region need to coexist visually with the adjacent clip? Should it be drawn on a separate layer or at a different Z-order?

---

#### Q5. Is the `SnapController` aware of magnetic mode, or are they independent?

`SnapController` handles snap-to-edge during drag. `GapCloseController` handles post-operation gap closure. Are these two systems independent? When magnetic mode closes a gap after a drag, does the snap controller's result get discarded (since the gap-close overrides the final position)?

---

#### Q6. How does waveform rendering interact with `shouldRepaint()` on `ClipsPainter`?

Currently `ClipsPainter.shouldRepaint()` checks `clips`, `tracks`, `selectedClipIds`, `viewport`, `showTrimHandles`, `cornerRadius`. Waveform data is not in this list. If waveform extraction completes and the cache is updated, how does the painter know to repaint? The `WaveformCache` is not passed to `ClipsPainter`.

**Likely resolution:** Either pass `WaveformCache` (or a version counter) to `ClipsPainter` and include it in `shouldRepaint`, or trigger a timeline rebuild when waveform extraction completes.

---

### Summary Table

| Category | Count | Breakdown |
|----------|-------|-----------|
| CRITICAL | 8 | C1 (multi-track arch), C2 (duplicate batch), C3 (LinkMode model), C4 (gap-close model mapping), C5 (dual manager), C6 (waveform perf), C7 (jump O(k)), C8 (execute signature) |
| IMPORTANT | 12 | I1-I12 |
| MINOR | 9 | M1-M9 |
| QUESTION | 6 | Q1-Q6 |
| **Total** | **35** | |

### Recommendations for Review Round 2

1. **Resolve C1 first** -- the multi-track architecture question underpins almost every feature. Propose and document the mapping layer between `PersistentTimeline` and `TimelineClip`.
2. **Resolve C5** -- dual manager coexistence must be decided before adding new mutation paths.
3. **Consolidate C2, C4, C8** -- these all stem from the `_execute()` pattern needing an upgrade. Design a revised `_execute()` that handles metadata, batch operations, and proper parameter passing.
4. **Prototype C6** -- build the waveform path cache before committing to the rendering approach. Profile on an actual iPad with 10 audio clips at high zoom.
5. **Address all CRITICAL items** before proceeding to implementation.

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Scope:** Codebase verification of all design assumptions, integration risk assessment for each feature, cross-feature interaction analysis, performance viability against actual code structure
**Status:** Review Complete - 6 CRITICAL, 9 IMPORTANT, 7 MINOR, 4 ACTION ITEMS

---

### Codebase Verification Results

This section verifies every major assumption in the design document against the actual codebase.

#### V1. TimelineManager `_execute()` Pattern - VERIFIED WITH ISSUES

**Assumption:** The design states `_execute()` takes a closure returning `PersistentTimeline`, pushes current to undo stack, and applies the mutation atomically.

**Verification:** Confirmed at `lib/core/timeline_manager.dart` lines 119-138. The `_execute()` method:
1. Pushes `_current` to `_undoStack` (line 124)
2. Trims undo stack to `maxUndoHistory = 100` (lines 125-127)
3. Clears `_redoStack` (line 130)
4. Invokes the mutation closure: `_current = mutation()` (line 133)
5. Sets `_compositionDirty = true` and `_lastOperationName` (lines 134-135)
6. Calls `notifyListeners()` (line 137)

**Issue Found:** The closure captures `_current` from the enclosing scope. The closure is invoked **after** `_undoStack.add(_current)` on line 124, but since `PersistentTimeline` is immutable and the undo stack stores a reference to the same object, the closure's reference to `_current` on line 133 is still the same pre-push object. This is correct but fragile, as Review 1 noted (I8). However, the bigger issue is that the closure on line 133 assigns back to `_current`, meaning **the closure must itself read `_current` to get the starting state**. All existing callers do this correctly (e.g., `remove` on line 170: `() => _current.remove(itemId)`), but the proposed `duplicateItems()` code in Section 3.3 does `var timeline = _current;` inside the closure, which also correctly captures the pre-mutation state. **Verified safe for current usage.**

#### V2. PersistentTimeline Data Structure - VERIFIED, SINGLE-TRACK CONFIRMED

**Assumption:** The design treats `PersistentTimeline` as supporting track-scoped operations.

**Verification at `lib/models/persistent_timeline.dart`:** The tree is a **single flat sequence** of `TimelineItem` objects. There is:
- No `trackId` field on `TimelineItem` (verified at `lib/models/clips/timeline_item.dart` lines 24-80)
- No `trackId` on `MediaClip` or `GeneratorClip` (lines 82-149)
- No `trackId` on `VideoClip` (verified at `lib/models/clips/video_clip.dart`)
- No `trackId` on `AudioClip` (verified at `lib/models/clips/audio_clip.dart`)

Track assignment lives exclusively on `TimelineClip` (`lib/timeline/data/models/timeline_clip.dart` line 63: `final String trackId`), which is a **separate UI rendering model**.

**Critical Implication:** The `PersistentTimeline` cannot answer "which clips are on track X?" without a full O(n) traversal and external mapping. This confirms Review 1's C1 finding and is the most fundamental architectural gap. The design's track-scoped algorithms (gap close, insert mode, ripple) **cannot operate directly on the `PersistentTimeline`**.

**Mapping Layer Identified:** `TimelineViewController` (`lib/timeline/timeline_controller.dart`) holds `List<TimelineClip> _allClips` (line 26), which is the rendering model with track assignments. But there is no documented bidirectional synchronization between `TimelineViewController._allClips` and `TimelineManager._current` (the `PersistentTimeline`). These appear to be **two separate sources of truth**, which is a serious integration risk.

#### V3. `startTimeOf()` is O(n), Not O(log n) - VERIFIED

**Assumption:** The design document (Section 1.2, Section 14.1) claims timeline lookup and `startTimeOf` are O(log n).

**Verification at `lib/models/persistent_timeline.dart` lines 98-124:** The `_startTimeOf()` method performs an **in-order traversal** searching for a matching `itemId`:
```
_startTimeOf(node, itemId, accumulated):
  if node.left: result = _startTimeOf(left, itemId, accumulated)  // always tries left
  if found: return
  check current node
  if match: return accumulated + leftDuration
  if node.right: _startTimeOf(right, itemId, ...)
```

This visits nodes in order until it finds the target. In the worst case (item is at the rightmost position), this is **O(n)**, not O(log n). The tree is ordered by cumulative duration (an order statistic tree), not by item ID, so there is no way to binary-search by ID.

**Impact on Design:** The `duplicateItems()` method (Section 3.3) calls `timeline.startTimeOf(itemId)` inside a loop over `itemIds`. For k items being duplicated on a timeline with n total items, this is **O(k * n)** in the worst case, not O(k * log n) as implied. For 10 items on a 1000-item timeline, this is ~10,000 operations instead of ~100.

**Mitigation Already Exists:** `getById()` uses the `Expando`-cached ID index and is O(1) after first access (O(n) to build). However, `startTimeOf()` does NOT use this cache. A `startTimeMap` cache (parallel to the ID index) could be built lazily, but this is not currently implemented.

#### V4. Undo/Redo Stacks - VERIFIED, METADATA GAP CONFIRMED

**Assumption:** The undo/redo stacks store `PersistentTimeline` instances with O(1) swap.

**Verification:** Confirmed at `lib/core/timeline_manager.dart`:
- `_undoStack: List<PersistentTimeline>` (line 25)
- `_redoStack: List<PersistentTimeline>` (line 28)
- `undo()` at lines 296-310: swaps `_current` with `_undoStack.removeLast()`, pushes old `_current` to `_redoStack`
- `redo()` at lines 313-327: mirror operation

**Metadata Gap Confirmed:** The stacks store only `PersistentTimeline` references. There is no `_undoMetadata` or `_redoMetadata` list. The `_lastOperationName` (line 39) only tracks the single most recent operation name and is reset to `null` on undo/redo (lines 302, 318). The design's undo history visualization (Section 11) requires adding parallel metadata stacks, which is a non-trivial change to `_execute()`, `undo()`, `redo()`, `clearHistory()`, `loadFromJson()`, `clear()`, and `reset()` -- all 7 methods.

#### V5. SelectionState Marquee Support - VERIFIED, WORKS AS DESCRIBED

**Assumption:** Marquee selection infrastructure already exists.

**Verification at `lib/timeline/data/models/selection_state.dart`:**
- `SelectionMode.marquee` exists (line 32)
- `marqueeStart: Offset?` and `marqueeEnd: Offset?` fields exist (lines 63-66)
- `startMarquee()`, `updateMarquee()`, `endMarquee()` methods exist (lines 351-367)
- `marqueeRect` getter exists (lines 117-120)
- `isMarqueeSelecting` getter exists (line 114)

**Verified at `lib/timeline/gestures/timeline_gesture_handler.dart`:**
- `GestureState.marqueeSelecting` exists (line 47)
- `_marqueeStart` and `_marqueeCurrent` fields exist (lines 167-170)
- Long press on empty space initiates marquee (referenced in the design)

**Verified at `lib/timeline/gestures/hit_testing.dart`:**
- `findClipsInRect(Rect rect)` exists at line 277

**Conclusion:** The marquee infrastructure is genuinely present and functional. The remaining work is limited to: real-time visual feedback during drag, add-to-selection behavior, and group operations on multi-selection.

#### V6. `TimelineClip.linkedClipId` - VERIFIED

**Assumption:** The `linkedClipId` field exists on `TimelineClip` for A/V linking.

**Verification at `lib/timeline/data/models/timeline_clip.dart`:**
- `final String? linkedClipId;` exists (line 102)
- `copyWith` supports `linkedClipId` and `clearLinkedClipId` (lines 226, 237, 252)
- Serialization: `toJson()` includes `linkedClipId` (line 391), `fromJson()` reads it (line 416)

**However:** `linkedClipId` is on `TimelineClip` (UI model), NOT on `TimelineItem`/`VideoClip`/`AudioClip` (data model). When a linked clip operation requires modifying the `PersistentTimeline`, the link relationship must be mapped from the UI model back to the data model. The data model has no concept of linking. This is another manifestation of the V2 finding (two sources of truth).

#### V7. WaveformCache - VERIFIED, ALREADY EXISTS

**Assumption:** Waveform extraction and caching needs to be built from scratch.

**Verification at `lib/timeline/cache/waveform_cache.dart`:** A comprehensive `WaveformCache` class **already exists** with:
- Multi-LOD support (`WaveformLOD.low`, `medium`, `high`) (lines 9-18)
- `WaveformData` model with `Float32List samples`, `sampleRate`, `durationMicros`, `lod` (lines 47-117)
- `getWaveformSamples()` with automatic LOD selection based on zoom level (lines 173-208)
- LRU eviction by memory budget (default 20MB) (lines 274-293)
- Concurrent generation queue with max 2 concurrent (lines 240-269)
- Preload, evict, and clear methods

**Critical Finding:** The design document (Section 5) specifies creating a `WaveformData` model and `WaveformCache` as new files. **These already exist.** The Phase 2 effort estimate (17h) includes "Create `WaveformData` model (1h)" and "Create `WaveformCache` (2h)" which are unnecessary. The existing cache is more sophisticated than the proposed one (it has multi-LOD, which the design does not).

**Missing:** The `waveformGenerator` callback (`Future<WaveformData?> Function(String assetId, WaveformLOD lod)?` at line 163) is declared but not connected to a native platform channel implementation. The Swift extraction plugin and platform channel bridge are genuinely needed.

#### V8. SnapController and Magnetic Timeline - VERIFIED, INDEPENDENT SYSTEMS

**Assumption:** `SnapController` and the proposed `GapCloseController` are independent.

**Verification at `lib/timeline/editing/snap_controller.dart`:**
- `SnapController` handles **real-time snap during drag/trim** (pixel-distance-based, lines 109-199)
- It adjusts the drag delta to snap to targets
- It fires haptic feedback on snap
- It does NOT modify the timeline or close gaps

The proposed `GapCloseController` would handle **post-operation gap closure** (after delete, move, trim are committed). These are indeed independent:
- `SnapController`: modifies drag preview position (visual feedback)
- `GapCloseController`: modifies committed timeline state (data mutation)

**Interaction Risk:** After a drag operation completes, the `SnapController`'s adjusted position becomes the commit position. If `GapCloseController` then runs (e.g., to close the source gap), it may further adjust positions. The final state would be: snap-adjusted position at destination + gap-closed at source. This is correct behavior, but the two adjustments must be applied within the same `_execute()` call to maintain atomic undo.

#### V9. RippleTrimController - VERIFIED, OPERATES ON UI MODEL

**Assumption:** `RippleTrimController` exists and handles ripple during trim.

**Verification at `lib/timeline/editing/ripple_trim_controller.dart`:**
- Operates on `List<TimelineClip>` (UI model), not `PersistentTimeline`
- `calculateTrimPreview()` (line 57) takes `allClips` and `trackClips` parameters
- `applyRippleTrim()` (line 187) returns a new `List<TimelineClip>`
- Has `RippleTrimMode.none`, `.track`, `.allTracks` (lines 8-17)

**Critical Finding:** The controller produces a `List<TimelineClip>` result, but there is no code path that translates this back to `PersistentTimeline` mutations. The `applyRippleTrim()` method returns a modified clip list, but someone must map each modified clip back to a `TimelineItem` and call `TimelineManager.updateItem()`. This is the same UI-model-to-data-model mapping gap identified in V2 and V6.

#### V10. ClipboardController.duplicate() - VERIFIED, CONFLICTS WITH DESIGN

**Assumption:** The design proposes a new `DuplicateController` alongside existing clipboard duplicate.

**Verification at `lib/timeline/editing/clipboard_controller.dart` lines 255-282:**
- `duplicate()` exists, generates new UUIDs via `_uuid.v4()`
- Sets `clearLinkedClipId: true` (line 275)
- Does NOT call `clip.duplicate()` on the domain model -- it uses `clip.copyWith()` on `TimelineClip` (UI model)
- Does NOT append "(copy)" to label (preserves original label)
- Returns `List<TimelineClip>` (UI model), not `List<TimelineItem>` (data model)

**Conflict:** The design's `DuplicateController` (Section 3.4) would operate differently: it would call `VideoClip.duplicate()` which generates new UUID AND appends "(copy)". The design's `TimelineManager.duplicateItems()` (Section 3.3) operates on `TimelineItem` (data model). This means the same feature has two competing implementations at two different layers. Review 1's I3 identified this; this review confirms the conflict is real.

#### V11. Dual Manager Architecture - VERIFIED, ACTIVELY IN USE

**Assumption:** `ClipManager` (V1) may or may not still be in active use.

**Verification:** `ClipManager` is **actively used** by:
- `SmartEditViewModel` (line 41: `final ClipManager clipManager;`, line 397: `clipManager = ClipManager()`)
- `ExportSheet` (line 140: `final ClipManager clipManager;`)
- `SmartEditViewModel._initializeClipManager()` (line 403) initializes clips
- `SmartEditViewModel._onClipManagerChange()` (line 414) listens for changes
- `SmartEditViewModel._initializeClipManagerWithVideo()` (line 776) sets up clips from video

`TimelineManager` is also used (via `TimelineViewController` which holds `WaveformCache`, `ThumbnailCache`).

**Critical Finding:** The two managers operate on **different model types**:
- `ClipManager` operates on `List<TimelineItem>` (domain model: `VideoClip`, `AudioClip`, etc.)
- `TimelineManager` operates on `PersistentTimeline` (immutable tree of `TimelineItem`)
- `TimelineViewController` operates on `List<TimelineClip>` (UI rendering model)

There is NO synchronization code between these three. The design proposes adding all new features to `TimelineManager`, but the primary editing view (`SmartEditView`) uses `ClipManager`. This means **new features added to `TimelineManager` will not be accessible from the main editing UI** without migration work.

#### V12. `PersistentTimeline.insertAt()` Behavior for Mid-Item Insertion - VERIFIED

**Assumption:** Review 1 Q1 asked whether `insertAt()` splits an existing item if time falls inside it.

**Verification at `lib/models/persistent_timeline.dart` lines 218-247:** The `_insertAt()` method navigates the tree by comparing `timeMicros` against `leftDuration` (the subtree duration of the left child). When `timeMicros` falls within the current node's item (i.e., `timeMicros > leftDuration` but `timeMicros < leftDuration + node.itemDurationMicros`):
- It calculates `timeInRight = timeMicros - leftDuration - node.itemDurationMicros`
- `timeInRight` will be negative, so it is clamped to 0 (line 239: `final clampedTime = timeInRight < 0 ? 0 : timeInRight`)
- The new item is inserted as the leftmost node in the right subtree

**Result:** `insertAt()` does NOT split existing items. It inserts the new item at the position, effectively creating an overlap if the target time falls within an existing item's duration. The existing item's duration does not change. This means **insert mode (Section 8.3.1) cannot rely solely on `insertAt()` to handle the "clip straddles insert point" case** -- explicit split-then-shift logic is required.

---

### Integration Risk Assessment

#### Risk 1: Three-Layer Model Impedance Mismatch (CRITICAL)

**Risk Level:** CRITICAL
**Affects:** All 10 features

The codebase has three distinct model layers with no documented synchronization:

| Layer | Model | Location | Used By |
|-------|-------|----------|---------|
| Domain | `TimelineItem` (`VideoClip`, `AudioClip`, etc.) | `lib/models/clips/` | `PersistentTimeline`, `ClipManager` |
| Persistent | `PersistentTimeline` (AVL tree of `TimelineItem`) | `lib/models/persistent_timeline.dart` | `TimelineManager` |
| UI/Rendering | `TimelineClip` (with `trackId`, `linkedClipId`, colors) | `lib/timeline/data/models/timeline_clip.dart` | `TimelineViewController`, all painters, gesture handler |

Every proposed feature requires crossing these boundaries:
- **Duplicate:** Must create `TimelineItem` via `item.duplicate()`, insert into `PersistentTimeline`, AND create corresponding `TimelineClip` with `trackId`
- **Magnetic close:** Must detect gaps in `List<TimelineClip>` (has `trackId`), compute moves, then apply via `PersistentTimeline` mutations (has no `trackId`)
- **Link/Unlink:** Must set `linkedClipId` on `TimelineClip` (UI model), but persist via `PersistentTimeline` which stores `TimelineItem` (no `linkedClipId`)

**The design document's code samples operate on only one layer at a time and never show the cross-layer translation.** This is the single greatest implementation risk.

**Proposed Resolution:** Before any feature implementation, create a `TimelineCoordinator` class that:
1. Maintains a bidirectional mapping: `Map<String, String> itemIdToTrackId` and `Map<String, String> itemIdToLinkedClipId`
2. Provides `toTimelineClips(PersistentTimeline, Map<String, Track>)` conversion
3. Provides `applyClipMoves(List<ClipMove>, PersistentTimeline)` reverse conversion
4. Is the SINGLE bridge between `TimelineManager` and `TimelineViewController`

#### Risk 2: `startTimeOf()` O(n) Performance in Batch Operations (IMPORTANT)

**Risk Level:** IMPORTANT
**Affects:** Duplicate (Section 3), Magnetic Close (Section 4), Insert Mode (Section 8)

As verified in V3, `startTimeOf(itemId)` is O(n). In `duplicateItems()`, it is called once per item being duplicated. In magnetic gap-close, it would be called for every clip on the affected track. In insert mode shift, it would be called for every clip after the insert point.

For a timeline with 200 clips and a 20-clip batch duplicate:
- Current: 20 * 200 = 4,000 node visits for `startTimeOf` alone
- Each node visit involves string comparison on `item.id`
- Estimated: ~0.5ms (still within budget, but leaves less headroom)

For 1000 clips with 100-clip insert-mode shift:
- 100 * 1000 = 100,000 node visits
- Estimated: ~5-10ms (may exceed 1ms budget per operation)

**Proposed Resolution:** Add a lazily-built `startTimeMap` cache to `PersistentTimeline`, similar to the existing `_idIndexCache`. Build it via in-order traversal, accumulating start times. Cache via `Expando`. Cost: O(n) on first access, O(1) for subsequent lookups on the same tree instance.

#### Risk 3: ClipManager (V1) Must Be Migrated or Isolated Before Feature Work (CRITICAL)

**Risk Level:** CRITICAL
**Affects:** All features accessible from SmartEditView

`SmartEditViewModel` (the main editing view's state management) uses `ClipManager`, not `TimelineManager`. Lines 41, 397, 403, 414, 776 in `smart_edit_view_model.dart` all reference `ClipManager`.

If new features are added only to `TimelineManager`, they will be unreachable from the primary editing interface. The user would have no way to trigger duplicate, magnetic close, link/unlink, insert/overwrite, J/L cuts, or replace clip from the main editor.

**Options:**
1. **Full migration:** Replace `ClipManager` with `TimelineManager` in `SmartEditViewModel` before implementing features. High effort (~2-3 days), but clean.
2. **Parallel wiring:** Add `TimelineManager` to `SmartEditViewModel` alongside `ClipManager`, route new features to V2. Medium effort, but creates more dual-manager complexity.
3. **Facade:** Create a unified interface that delegates to the appropriate manager. Moderate effort, maintainable.

**Recommendation:** Option 1 (full migration). The `ClipManager` has 4 command classes (`SplitCommand`, `DeleteCommand`, `ReorderCommand`, `TrimCommand`) that are already implemented as methods on `TimelineManager` (`splitAt`, `remove`, `updateItem`, `trimStart`/`trimEnd`). Migration is straightforward.

#### Risk 4: Waveform Rendering in ClipsPainter Without WaveformCache Access (IMPORTANT)

**Risk Level:** IMPORTANT
**Affects:** Waveform on Audio Clips (Section 5)

`ClipsPainter` (line 11 of `lib/timeline/rendering/painters/clip_painter.dart`) is a `CustomPainter` that receives `clips`, `tracks`, `selectedClipIds`, `viewport`, `showTrimHandles`, and `cornerRadius`. It does NOT receive `WaveformCache`.

To draw waveforms inside clips, the painter needs access to waveform sample data. Options:
1. **Pass `WaveformCache` to `ClipsPainter`:** Adds a dependency, requires `shouldRepaint` update
2. **Pre-compute waveform paths per clip:** Pass `Map<String, Path> waveformPaths` to the painter. Paths are pre-built when zoom changes or waveform data arrives. Keeps painter stateless.
3. **Pass `Map<String, Float32List> waveformSamples`:** Pre-extract visible samples per clip, pass to painter

**Recommendation:** Option 2 (pre-computed paths). This:
- Keeps `ClipsPainter` as a pure rendering function with no cache access
- Avoids per-frame path construction (the path is rebuilt only on zoom change or waveform data arrival)
- Works naturally with `shouldRepaint` (compare path reference identity)

The `TimelineViewController` already holds `WaveformCache` (line 52 of `timeline_controller.dart`). It can build paths and pass them down.

#### Risk 5: J/L Cut Requires Independent Audio Trim on Linked Clips - Gesture System Not Designed for This (IMPORTANT)

**Risk Level:** IMPORTANT
**Affects:** J-Cut / L-Cut (Section 9)

The current `TrimController` trims a single clip's edge. For J/L cuts, the user must be able to trim the audio clip's edge independently while the linked video clip stays put. This requires:

1. **Hit testing must distinguish audio vs video trim handles on a linked pair.** Currently, `TrimHitTester` checks all clips' edges. When a linked video and audio clip overlap on the timeline (same time range, different tracks), the trim handle for the audio clip must be individually targetable.

2. **The `TrimController` must know whether to propagate the trim to the linked clip.** Currently there is no `LinkMode` awareness in trim logic. The trim controller would need to check: if the clip being trimmed has `linkMode == trimIndependent`, do NOT propagate the trim.

3. **Visual rendering of independent audio trim handles.** The audio clip needs visually distinct trim handles (green vs white as specified in Section 9.5). This requires `ClipsPainter` to check `linkMode` per clip and render different handle styles.

**Estimated Additional Complexity:** The design estimates 3h for "J-cut / L-cut trim behavior" in `TrimController`. Given the gesture handler modifications, hit testing changes, visual rendering, and link mode checks, 6-8h is more realistic.

#### Risk 6: Insert Mode Shift Calculation on `PersistentTimeline` Without Track Awareness (IMPORTANT)

**Risk Level:** IMPORTANT
**Affects:** Insert vs Overwrite Edit (Section 8)

Insert mode requires: "Find all clips on the target track that start at or after time T, shift each right by D microseconds." This is a track-scoped query.

`PersistentTimeline` has no track concept. To find clips on a specific track:
1. Call `toList()` to get all items (O(n))
2. Map each item to its track via the external track assignment table
3. Filter by target track
4. Identify items starting at or after time T
5. For each, compute new position and call `updateItem()` or remove+reinsert

The remove+reinsert approach is needed because changing an item's timeline position in the order statistic tree requires removing it from one position and inserting at another (the tree is ordered by cumulative duration, not by start time as a key).

For a track with 100 clips, shifting all of them means 100 remove + 100 insert operations, each O(log n). Total: O(200 * log n) = O(200 * 10) = ~2,000 operations. At ~1us per tree operation, this is ~2ms -- within budget but tight.

**Alternative:** Rebuild the tree from a sorted list after computing new positions. `PersistentTimeline.fromSortedList()` is O(n) and produces a perfectly balanced tree. For the shift case, this may be more efficient than 200 individual mutations.

#### Risk 7: Undo History Visualization Requires UI Plumbing Not Currently Wired (LOW)

**Risk Level:** LOW
**Affects:** Undo History Visualization (Section 11)

The `UndoHistoryPanel` widget needs to be accessible from the timeline UI. Currently, the timeline toolbar is rendered inside `TimelineWidget` (`lib/timeline/widgets/timeline_widget.dart`). Adding a new panel requires:
1. A trigger button in the toolbar (straightforward)
2. An overlay or bottom sheet for the panel (using `CupertinoActionSheet` or custom `BackdropFilter` panel)
3. The panel needs a reference to `TimelineManager` to access undo/redo metadata

This is standard UI wiring with no architectural risk.

---

### Critical Findings

#### CF1. `PersistentTimeline` Cannot Support Multi-Track Features Without a Mapping Layer

**Severity:** CRITICAL (blocks 7 of 10 features)

The `PersistentTimeline` stores `TimelineItem` objects in a single sequence ordered by cumulative duration. It has no concept of tracks, links, or clip colors. The rendering layer (`TimelineClip`) has all of these. **Every multi-track feature requires a translation layer that does not exist.**

The design document proposes algorithms that operate on `List<TimelineClip>` (with track awareness) but commits results to `PersistentTimeline` (without track awareness). The translation is never shown.

**Resolution Required Before Implementation:**
1. Define where track assignments are stored (on `TimelineItem`? in a separate `Map<String, String>`?)
2. Define where link relationships are stored
3. Create the `TimelineCoordinator` class that bridges the two models
4. All design algorithms must show the full flow: UI model -> algorithm -> data model mutation

#### CF2. `startTimeOf()` Is O(n), Invalidating Performance Claims for Batch Operations

**Severity:** CRITICAL (affects performance budget)

The design claims O(log n) for all timeline operations. `startTimeOf()` is O(n) because it performs in-order traversal by item ID. This affects:
- `duplicateItems()`: calls `startTimeOf()` per item
- Any bulk operation that needs to know where items are on the timeline

**Resolution:** Either:
1. Add a `startTimeMap: Map<String, int>` cache (built lazily like the ID index), or
2. Restructure `duplicateItems()` and similar methods to avoid `startTimeOf()` (use `toList()` once, build a local start-time map, then apply mutations)

#### CF3. `SmartEditViewModel` Uses `ClipManager` (V1), Not `TimelineManager` (V2)

**Severity:** CRITICAL (blocks feature accessibility)

New features added to `TimelineManager` will not be accessible from the main editing view because `SmartEditViewModel` uses `ClipManager`. Migration must happen first.

#### CF4. WaveformCache Already Exists - Design Proposes Redundant Implementation

**Severity:** IMPORTANT (not blocking, but wastes effort if not caught)

The design proposes creating `WaveformData` model and `WaveformCache` as new files (Phase 2). These already exist at `lib/timeline/cache/waveform_cache.dart` with a more sophisticated multi-LOD implementation. The existing code matches the design's intent but with better zoom-level adaptation.

**Phase 2 effort should be reduced by ~3h** (skip model and cache creation, focus on native extraction plugin and painter integration).

#### CF5. `PersistentTimeline.insertAt()` Does Not Split Straddling Items

**Severity:** IMPORTANT (affects Insert Mode correctness)

As verified in V12, `insertAt()` inserts at a time position without splitting any existing item at that position. Insert mode (Section 8.3.1 step 4) requires: "If a clip straddles T, split it at T, then shift the right half." This split must be done explicitly before the insert, using `splitAt()` on `TimelineManager`, then `insertAt()` for the new content.

The design's `EditModeController.calculateInsert()` returns `SplitClipResult` objects for straddling clips, which is correct in principle. But the actual execution must be: split first, shift second, insert third -- all within a single `_execute()` closure. The ordering matters because each step produces a new `PersistentTimeline` instance.

#### CF6. Linked Clip Operations Require Atomic Multi-Item Mutations

**Severity:** IMPORTANT (affects correctness of Link/Unlink, J/L Cuts)

When a linked clip is deleted, both clips must be removed. When moved, both must move. The `_execute()` closure must perform multiple tree mutations atomically:

```
_execute(() {
  var timeline = _current;
  timeline = timeline.remove(clipId);
  timeline = timeline.remove(linkedClipId); // linked partner
  return timeline;
});
```

This pattern works but requires knowing the `linkedClipId` at the `TimelineManager` level. Since `linkedClipId` is stored on `TimelineClip` (UI model) and NOT on `TimelineItem` (data model), the `TimelineManager` has no way to discover the linked partner without external input.

**Resolution:** Either:
1. Add `linkedClipId` to `TimelineItem` subclasses (requires data model change), or
2. Always pass linked IDs as parameters to `TimelineManager` methods (e.g., `removeWithLinked(String clipId, String? linkedClipId)`)

---

### Important Findings

#### IF1. `selectClips()` Resets Mode to `normal` During Active Marquee

Review 1 identified this as M7. Verification confirms: `SelectionState.selectClips()` (line 225-231) calls `copyWith(mode: SelectionMode.normal)`. During an active marquee drag, `_updateMarqueeSelection()` calls `selectClips()`, which resets mode from `marquee` to `normal`. This breaks `isMarqueeSelecting` during the drag.

**Fix:** Use `_selection = _selection.copyWith(selectedClipIds: clipIds)` instead of `_selection.selectClips(clipIds)` during marquee updates, preserving the `marquee` mode.

#### IF2. `ClipDragController` Supports Multi-Clip Drag via `DragState.clips` List

Verified at `lib/timeline/data/models/edit_operations.dart` lines 14-43: `DragState` has `clips: List<TimelineClip>` and `originalPositions: Map<String, TimeMicros>`. This supports multi-clip drag natively. Adding linked clips to the drag set (as proposed in Section 7.6) is architecturally feasible -- the caller just needs to include the linked clip IDs in the initial `DragState.clips` list.

#### IF3. `VideoClip.duplicate()` Generates New UUID But `ClipboardController.duplicate()` Also Generates New UUID

Two different UUID generation paths:
- `VideoClip.duplicate()` uses `const Uuid().v4()` (video_clip.dart line 248)
- `ClipboardController.duplicate()` uses `_uuid.v4()` where `_uuid = const Uuid()` (clipboard_controller.dart line 87, 266)

Both produce v4 UUIDs. There is no collision risk (v4 UUIDs are cryptographically random). But the two paths produce different results: `VideoClip.duplicate()` appends "(copy)" to name; `ClipboardController.duplicate()` preserves the original label. The design should pick one path.

#### IF4. `TrimHitTester.findClipsInRect()` Uses Linear Scan

Verified: `findClipsInRect` at hit_testing.dart line 277 iterates all clips and checks `Rect.overlaps()`. For 500 clips, this is 500 rect-overlap checks per call. Each check is ~4 comparisons. Total: ~2000 comparisons, well under 1ms. No spatial indexing needed at current scale.

However, if marquee is updated every frame during drag (60 calls/second), this becomes 30,000 rect checks per second, still negligible. **No concern for current implementation.**

#### IF5. Gap-Close Algorithm Complexity on Large Tracks

The proposed gap-close algorithm (Section 4.2.4) is O(k) where k = clips on the affected track. For 1000 clips on a single track, sorting + scanning is ~1000 * log(1000) = ~10,000 operations for the sort, plus 1000 for the scan. At ~100ns per comparison, sorting takes ~1ms. Within budget for a single invocation but tight.

**Concern:** If `MagneticMode.allTracks` is active and there are 5 tracks with 200 clips each, the total is 5 * (200 log 200 + 200) = ~9,000 operations. Still within 1ms.

**Optimization:** If clips are maintained in sorted order per track (via the `TimelineViewController`), the sort step can be eliminated.

#### IF6. `DurationMismatchStrategy.loopMedia` Undocumented

Review 1 M2 noted this. Confirmed: the enum value `loopMedia` in `ReplaceClipController` (Section 10.4) has no corresponding behavior specification. It should either be documented or removed from the design.

#### IF7. Undo History Panel Memory for `List.unmodifiable` Wrapper

Review 1 I9 noted potential garbage from `List.unmodifiable()` on every `build()`. For 100 entries, `UnmodifiableListView` creates one wrapper object per call. At 60 FPS during panel display, this is 60 tiny allocations per second -- negligible. Not a real performance concern, but caching the unmodifiable view would be cleaner.

#### IF8. Transition Model Not Integrated With Gap-Close

Review 1 I1 noted this. Verified: `ClipTransition` model exists at `lib/timeline/data/models/transition.dart`. The `GapCloseController` design does not accept transitions as input and cannot clean up orphaned transitions. This must be added to the gap-close interface.

#### IF9. `TimelineManager` Selection Is Single-Item, Not Multi-Select

`TimelineManager` has `_selectedItemId: String?` (line 35) -- single selection. But the timeline UI uses `SelectionState.selectedClipIds: Set<String>` (selection_state.dart line 39) -- multi-select. These are separate selection systems.

New features that operate on multi-selection (duplicate, delete, move) must use `SelectionState.selectedClipIds` (from `TimelineViewController`), not `TimelineManager._selectedItemId`. The design correctly shows this in its code samples, but it is worth noting that `TimelineManager.selectItem()` / `selectedItem` are V1 holdovers and should not be used for new features.

---

### Minor Findings

#### MF1. `TimelineItem.operator==` Compares Only by `id`

At timeline_item.dart lines 74-76:
```dart
bool operator ==(Object other) =>
    identical(this, other) || (other is TimelineItem && id == other.id);
```

This means two `VideoClip` instances with the same `id` but different `sourceInMicros` compare as equal. `PersistentTimeline.updateItem()` uses `node.item.id == itemId` for lookup, not equality, so this does not affect tree operations. But it could cause `shouldRepaint` or `==` comparisons in widget trees to produce false positives if clips are compared by value after trim/edit.

#### MF2. `VideoClip.splitAt()` Minimum Duration Is 100ms, But `TimelineClip.minDuration` Is 33,333us (~33ms)

`VideoClip.splitAt()` uses `const minDuration = 100000` (100ms) at video_clip.dart line 62. `TimelineClip.minDuration = 33333` (~33ms) at timeline_clip.dart line 208. These are different minimum durations at different layers. A split that produces a 50ms clip would be rejected by `VideoClip.splitAt()` but accepted by `TimelineClip.splitAt()`.

**Impact:** For J/L cuts where audio overhang can be small, the 100ms minimum on the domain model may prevent valid short overhangs.

#### MF3. `AudioClip` Has No `splitAt()` Method

`VideoClip.splitAt()` exists (video_clip.dart line 61). `GapClip.splitAt()` and `ColorClip.splitAt()` also exist. But `AudioClip` has no `splitAt()` method. If a split operation targets an audio clip, `TimelineManager.splitAt()` (line 192-241) does not handle the `AudioClip` type (no `else if (item is AudioClip)` branch). Audio clips silently cannot be split.

**Impact:** This blocks split operations on standalone audio clips and may affect J/L cut implementations where audio clips need to be split at specific points.

#### MF4. Phase 2 Effort Overestimated Due to Existing WaveformCache

As noted in CF4, the `WaveformData` model and `WaveformCache` already exist. Phase 2 should be reduced from 17h to ~14h (remove 1h for model creation and 2h for cache creation).

#### MF5. `ImageClip` Missing from `TimelineManager.splitAt()` and `duplicateItems()`

`TimelineManager.splitAt()` (lines 192-241) handles `VideoClip`, `GapClip`, `ColorClip` but not `ImageClip`. The proposed `duplicateItems()` also skips `ImageClip`. Both should handle all clip types.

#### MF6. SF Symbol `magnet` May Not Exist

The design references `CNSymbol('magnet')` for the magnetic toggle button (Section 4.5). The SF Symbols library does not include a symbol named exactly `magnet`. The closest symbols are `lines.measurement.horizontal` or a custom icon. This should be verified against the SF Symbols app catalog.

#### MF7. `RippleTrimController.applyRippleTrim()` Returns `List<TimelineClip>` but Has No Integration Path to `PersistentTimeline`

Same as V9 finding. The method returns a new clip list but there is no code that translates this back to tree mutations. This is a specific instance of the broader model impedance mismatch (CF1).

---

### Action Items for Review 3

| # | Action | Priority | Owner | Blocks |
|---|--------|----------|-------|--------|
| A1 | **Design the `TimelineCoordinator` class** that bridges `PersistentTimeline` (data model) and `TimelineClip` (UI model). Must define: track assignment storage, link relationship storage, bidirectional conversion methods. This resolves CF1, V2, V6, V9, CF6, MF7. | P0 - CRITICAL | Architecture | All features |
| A2 | **Migrate `SmartEditViewModel` from `ClipManager` to `TimelineManager`**. Map the 4 command classes to equivalent `TimelineManager` methods. Verify all UI code paths work with the new manager. This resolves CF3 and V11. | P0 - CRITICAL | Implementation | Feature accessibility |
| A3 | **Add `startTimeMap` cache to `PersistentTimeline`** (lazily built via `Expando`, same pattern as `_idIndexCache`). Also add `AudioClip.splitAt()` method. This resolves CF2, V3, MF3. | P1 - HIGH | Implementation | Batch operation performance |
| A4 | **Update Phase 2 estimates** to account for existing `WaveformCache`. Remove redundant model/cache creation tasks. Define the `ClipsPainter` waveform rendering integration path (pre-computed paths vs direct cache access). This resolves CF4, MF4, Risk 4. | P2 - MEDIUM | Planning | Phase 2 accuracy |

### Summary Statistics

| Category | Count | Breakdown |
|----------|-------|-----------|
| CRITICAL | 6 | CF1 (model mismatch), CF2 (startTimeOf O(n)), CF3 (V1 manager in use), CF4 (redundant waveform), CF5 (insertAt no split), CF6 (linked atomic) |
| IMPORTANT | 9 | IF1-IF9 |
| MINOR | 7 | MF1-MF7 |
| ACTION ITEMS | 4 | A1-A4 |
| **Total Findings** | **22** | Plus 12 verification results (V1-V12) |

### Review 2 Conclusion

The design document is well-structured and covers feature behavior comprehensively. However, it consistently operates at the `TimelineClip` (UI model) layer while proposing mutations at the `PersistentTimeline` (data model) layer, without showing the translation between them. The single greatest risk is the **three-layer model impedance mismatch** (CF1): every feature requires crossing model boundaries that have no documented bridge.

The second critical risk is **`ClipManager` (V1) being the active manager in `SmartEditViewModel`** (CF3). Until this is migrated, no new features will be reachable from the main editing interface.

The third critical risk is **`startTimeOf()` being O(n)** (CF2), which undermines performance claims for batch operations. This has a straightforward fix (lazy cache) and should be implemented as a prerequisite.

**Recommendation:** Resolve A1 (coordinator design) and A2 (V1 migration) before any feature implementation begins. A3 (performance cache) and A4 (estimate updates) can be done in parallel with Phase 1 implementation.

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Scope:** Final sign-off review. Resolution status for all 14 critical issues from R1+R2, risk register, ordered implementation checklist, feature independence analysis, GO/NO-GO decision.
**Status:** Review Complete - CONDITIONAL GO

---

### 3.1 Critical Issues Status

R1 identified 8 critical issues (C1-C8). R2 identified 6 more (CF1-CF6). This section tracks the resolution status of all 14.

| ID | Issue | Resolution Status | Blocking? | Resolution Path |
|----|-------|-------------------|-----------|-----------------|
| C1 | `PersistentTimeline` is single-track, design assumes multi-track | **UNRESOLVED - Subsumed by CF1** | YES | See CF1 resolution below |
| C2 | `duplicateItems()` ID index invalidation between inserts | **RESOLUTION IDENTIFIED** | No (if followed) | Snapshot all clip data and start times before mutations. Sort inserts by descending time to avoid position shifts. R1's recommendation is correct and sufficient. |
| C3 | `LinkMode` enum not on `TimelineClip` - model change needed | **RESOLUTION IDENTIFIED** | No (Phase 4 only) | Add `LinkMode linkMode` field to `TimelineClip` with default `LinkMode.full`. Add to `copyWith()`, `toJson()`/`fromJson()` with backward-compatible default. Add to `operator ==`/`hashCode`. Deferred to Phase 4 -- does not block Phases 1-3. |
| C4 | Gap-close operates on `List<TimelineClip>`, mutations go through `PersistentTimeline` | **UNRESOLVED - Subsumed by CF1** | YES | Requires `TimelineCoordinator` from CF1. |
| C5 | Dual manager architecture (`ClipManager` V1 + `TimelineManager` V2) | **UNRESOLVED - Subsumed by CF3** | YES | Requires V1 migration from CF3. |
| C6 | Waveform inner loop O(width * samplesPerPixel) per frame | **RESOLUTION IDENTIFIED** | No (if followed) | R1's fix is correct: pre-compute waveform `Path` per clip per zoom level, cache in `Map<String, Path>`, invalidate on zoom change (>5% threshold). Pass pre-computed paths to `ClipsPainter`. R2 Risk 4 recommends Option 2 (pre-computed paths). This is viable and sufficient. |
| C7 | `jumpToUndoState()` fires O(k) `notifyListeners()` calls | **RESOLUTION IDENTIFIED** | No (if followed) | R1 provided corrected implementation with single `notifyListeners()` call. Must also move metadata entries between stacks in the same loop. Straightforward fix. |
| C8 | `_execute()` signature change breaks callers | **RESOLUTION IDENTIFIED** | No (if followed) | New parameters have defaults (`type = .other`, `affectedClipCount = 0`), so existing callers compile unchanged. Existing operations will show as `UndoOperationType.other` until individually updated -- acceptable for V1. Derive type from `operationName` via pattern matching as a follow-up. The `undo()`/`redo()` metadata stack manipulation was shown by R1 and is correct. |
| CF1 | Three-layer model impedance mismatch (no bridge between `PersistentTimeline` and `TimelineClip`) | **UNRESOLVED** | **YES - PRIMARY BLOCKER** | R2 proposed `TimelineCoordinator`. See Section 3.2 for assessment. |
| CF2 | `startTimeOf()` is O(n), not O(log n) | **RESOLUTION IDENTIFIED** | No (if followed) | Add `_startTimeCache` via `Expando`, same pattern as `_idIndexCache`. Build via single in-order traversal accumulating start times. O(n) on first access, O(1) thereafter per tree instance. Straightforward. See Section 3.3. |
| CF3 | `SmartEditViewModel` uses `ClipManager` (V1), not `TimelineManager` (V2) | **UNRESOLVED** | **YES - SECONDARY BLOCKER** | See Section 3.4 for migration assessment. |
| CF4 | `WaveformCache` already exists, design proposes redundant implementation | **RESOLVED** | No | R2 correctly identified the existing implementation. Phase 2 estimates should reduce by 3h. Remaining work: Swift extraction plugin, platform channel, painter integration. |
| CF5 | `PersistentTimeline.insertAt()` does not split straddling items | **RESOLUTION IDENTIFIED** | No (if followed) | Insert mode must explicitly: (1) split straddling clip via `TimelineManager.splitAt()`, (2) shift right-half and subsequent clips, (3) insert new content -- all within a single `_execute()` closure. This is an implementation detail, not an architectural gap. |
| CF6 | Linked clip operations require atomic multi-item mutations, but `linkedClipId` is only on UI model | **UNRESOLVED - Requires CF1 resolution** | YES | Either add `linkedClipId` to `TimelineItem` subclasses (data model change) or pass linked IDs externally. Depends on `TimelineCoordinator` design from CF1. |

**Summary:** 3 issues remain unresolved and blocking (CF1, CF3, CF6). 11 issues have identified resolution paths. CF6 is resolved once CF1 is resolved. Effectively, **2 independent blockers remain: CF1 and CF3.**

---

### 3.2 Key Blocker Assessment: Three-Layer Model (CF1)

R2 proposes a `TimelineCoordinator` class that:
1. Maintains `Map<String, String> itemIdToTrackId` and `Map<String, String> itemIdToLinkedClipId`
2. Provides `toTimelineClips(PersistentTimeline, Map<String, Track>)` conversion
3. Provides `applyClipMoves(List<ClipMove>, PersistentTimeline)` reverse conversion
4. Is the single bridge between `TimelineManager` and `TimelineViewController`

**Assessment: The coordinator approach is architecturally sound but incomplete.** Here is what is needed:

#### 3.2.1 Where Track Assignments Live

Currently, track assignment (`trackId`) exists ONLY on `TimelineClip` (UI model). It is NOT on `TimelineItem` (data model). This means the `PersistentTimeline` does not know which track a clip belongs to.

**Decision needed:** Either:
- **(A)** Add `trackId` to `TimelineItem` (clean but requires data model change + serialization update + migration for existing projects)
- **(B)** Store track assignments in a separate `Map<String, String>` inside `TimelineCoordinator` (avoids data model change but creates a second source of truth that must be kept in sync)
- **(C)** Use one `PersistentTimeline` per track, with `TimelineCoordinator` managing `Map<String, PersistentTimeline>` (clean separation but requires changes to undo/redo -- must snapshot the entire map, not just one tree)

**Recommendation: Option (A).** Adding `trackId: String` to `TimelineItem` is the cleanest long-term solution. It adds ~20 bytes per item (a string reference), has no performance impact, and eliminates the impedance mismatch for all track-scoped operations. The serialization change is backward-compatible (default `trackId` to `'main'` for legacy projects). The `PersistentTimeline` itself does not need to be track-aware -- callers can filter `toList()` by `trackId` or use the ID index. The tree remains a single flat sequence, but each item knows its track.

Option (C) is architecturally elegant but creates significant undo/redo complexity (undo must restore all per-track trees atomically, which means storing `Map<String, PersistentTimeline>` in the undo stack instead of a single `PersistentTimeline`). This is a larger change than needed.

#### 3.2.2 Where Link Relationships Live

Same situation: `linkedClipId` is on `TimelineClip` (UI model) only.

**Recommendation:** Add `linkedItemId: String?` to `TimelineItem` base class. This allows `TimelineManager` to discover linked partners without external input. The field is nullable and defaults to `null` for backward compatibility.

#### 3.2.3 Minimal TimelineCoordinator Scope

With `trackId` and `linkedItemId` on `TimelineItem`, the `TimelineCoordinator` simplifies to:

```
class TimelineCoordinator {
  /// Convert PersistentTimeline items to rendering-ready TimelineClips.
  List<TimelineClip> buildClips(PersistentTimeline timeline, List<Track> tracks);

  /// Get items on a specific track (uses toList() + filter, O(n)).
  List<TimelineItem> itemsOnTrack(PersistentTimeline timeline, String trackId);

  /// Get start times for all items (uses cached startTimeMap).
  Map<String, int> startTimeMap(PersistentTimeline timeline);

  /// Apply clip moves back to PersistentTimeline.
  PersistentTimeline applyMoves(PersistentTimeline timeline, List<ClipMove> moves);
}
```

This is a utility/mapper class, not a state holder. It holds no mutable state -- it transforms between representations. This is the right design.

**Estimated effort for CF1 resolution: 2-3 days** (add `trackId` and `linkedItemId` to `TimelineItem`, update all subclass constructors/serialization, create `TimelineCoordinator`, update `TimelineManager` to use coordinator for track-scoped operations).

---

### 3.3 Performance: `startTimeOf()` O(n) Cache Viability (CF2)

The proposed fix is a lazily-built `_startTimeCache` using the same `Expando` pattern as `_idIndexCache`.

**Viability assessment: Fully viable.** The implementation is:

```
final Expando<Map<String, int>> _startTimeCache = Expando('PersistentTimeline._startTimes');

Map<String, int> _getStartTimeMap() {
  if (root == null) return const {};
  var map = _startTimeCache[this];
  if (map == null) {
    map = _buildStartTimeMap();
    _startTimeCache[this] = map;
  }
  return map;
}

Map<String, int> _buildStartTimeMap() {
  final map = <String, int>{};
  _collectStartTimes(root, 0, map);
  return map;
}

static void _collectStartTimes(TimelineNode? node, int accumulated, Map<String, int> map) {
  if (node == null) return;
  _collectStartTimes(node.left, accumulated, map);
  final nodeStart = accumulated + node.leftDuration;
  map[node.item.id] = nodeStart;
  _collectStartTimes(node.right, nodeStart + node.itemDurationMicros, map);
}
```

Then `startTimeOf(String itemId)` becomes: `return _getStartTimeMap()[itemId];`

**Cost:** O(n) on first access per tree instance (same as `_buildIdIndex`). O(1) for all subsequent lookups. Each new `PersistentTimeline` from a mutation gets its own `Expando` slot, so the cache is automatically invalidated on mutation. Memory: ~16 bytes per entry (String ref + int) * n items. For 1000 items: ~16 KB. Negligible.

**Estimated effort: 1-2 hours.**

---

### 3.4 ClipManager to TimelineManager Migration (CF3)

`SmartEditViewModel` references `ClipManager` in 47+ lines (verified via grep). The key integration points are:

| ClipManager Method | TimelineManager Equivalent | Notes |
|---|---|---|
| `clipManager.clips` | `_current.toList()` | Returns `List<TimelineItem>` |
| `clipManager.loadItems(items)` | `loadFromJson()` or `PersistentTimeline.fromSortedList()` | |
| `clipManager.splitAtTimelinePosition(time)` | `splitAt(timeMicros)` | Already exists |
| `clipManager.deleteSelectedClip(ripple:)` | `remove(itemId)` | Ripple logic needs magnetic close integration |
| `clipManager.selectClip(id)` | `selectItem(id)` | Already exists |
| `clipManager.undo()` / `redo()` | `undo()` / `redo()` | Already exists, O(1) |
| `clipManager.canUndo` / `canRedo` | `canUndo` / `canRedo` | Already exists |
| `clipManager.sourceToTimeline(time)` | Custom method needed | Uses `itemAtTime()` + `startTimeOf()` |
| `clipManager.timelineToSource(time)` | Custom method needed | Inverse of above |
| `clipManager.timelineStartOf(clip)` | `startTimeOf(itemId)` | Already exists (needs cache fix per CF2) |
| `clipManager.clips.isNotEmpty` | `isNotEmpty` | Already exists |
| `clipManager.selectedClip` | `selectedItem` | Already exists |
| `clipManager.items` | `items` (via `toList()`) | Already exists |
| `clipManager.totalDuration` | `totalDuration` | Already exists |
| `clipManager.gaps` | Filter `toList()` for `GapClip` instances | Custom method needed |
| `clipManager.clipContainingSourceTime(time)` | `itemAtTime(timeMicros)` | Already exists |
| `clipManager.initializeWithSingleClip(...)` | Custom init method needed | Create clip, `append()` it |

**Assessment:** Most `ClipManager` methods have direct equivalents on `TimelineManager`. The migration requires:
1. Adding 3-4 convenience methods to `TimelineManager` (`sourceToTimeline`, `timelineToSource`, `gaps`, `initializeWithSingleClip`)
2. Updating ~47 lines in `SmartEditViewModel` to use `TimelineManager`
3. Updating `ExportSheet` (1 reference) and `Project` model (1 reference) -- both minor
4. Removing `ClipManager` after migration is verified

**Estimated effort: 2-3 days** (including testing). This is a prerequisite for all feature work.

**Risk:** The `ClipManager` uses a mutable `List<TimelineItem>` with command pattern. The `TimelineManager` uses immutable `PersistentTimeline`. The migration changes the underlying data semantics from mutable to immutable. Any code that holds a reference to `clipManager.clips` and expects it to update in-place will break. All references must be re-evaluated for this semantic change.

---

### 3.5 Risk Register

| # | Risk | Likelihood | Impact | Severity | Mitigation | Owner |
|---|------|-----------|--------|----------|------------|-------|
| R1 | `TimelineCoordinator` design takes longer than estimated, delaying all features | Medium | High | **HIGH** | Time-box to 3 days. If not complete, fall back to Option (B) (external map). Ship Duplicate and Undo History without coordinator since they do not require track awareness. | Architecture |
| R2 | `ClipManager` migration breaks existing editing functionality | Medium | Critical | **CRITICAL** | Implement behind a feature flag. Keep `ClipManager` in code until `TimelineManager` path is fully tested. Run full regression suite. | Implementation |
| R3 | `startTimeOf()` cache invalidation causes stale data | Low | High | **MEDIUM** | `Expando` automatically creates new cache per tree instance. Since every mutation returns a new `PersistentTimeline`, stale reads are structurally impossible. Unit test with mutation-then-lookup sequences. | Implementation |
| R4 | Waveform path pre-computation causes visible delay on zoom change | Low | Medium | **LOW** | Pre-compute asynchronously on zoom change. Use previous zoom's path until new one is ready (stale-while-revalidate pattern). Path computation for 10 clips at 1000px each takes <5ms. | Implementation |
| R5 | Three-model-layer approach accumulates technical debt over time | High | Medium | **MEDIUM** | Document the `TimelineCoordinator` contract thoroughly. Add integration tests that verify round-trip fidelity (TimelineItem -> TimelineClip -> mutation -> TimelineItem). Schedule periodic model consolidation reviews. | Architecture |
| R6 | `AudioClip.splitAt()` missing blocks J/L cut and split-on-audio features | High | Medium | **MEDIUM** | Implement `AudioClip.splitAt()` as a prerequisite in Phase 1. Pattern identical to `VideoClip.splitAt()`. Estimated: 1 hour. | Implementation |
| R7 | Insert mode shift on 1000-clip track approaches frame budget | Low | Medium | **LOW** | Use `PersistentTimeline.fromSortedList()` rebuild instead of 1000 individual remove+insert operations. Benchmark during Phase 4. | Implementation |
| R8 | Two-finger marquee gesture conflicts with pinch zoom | Medium | Low | **LOW** | Drop two-finger marquee. Long-press is sufficient and already implemented. Two-finger adds complexity for marginal UX gain. R1 I4 agrees. | Design |
| R9 | Undo history metadata stacks desynchronize from timeline stacks | Low | High | **MEDIUM** | Encapsulate undo/redo stacks in a single `UndoStack<T>` class that pairs `PersistentTimeline` with `UndoHistoryEntry`. Single list of pairs eliminates desync possibility. | Implementation |
| R10 | Feature interactions create untested edge cases (e.g., magnetic close + linked clips + insert mode) | Medium | Medium | **MEDIUM** | Define a cross-feature interaction matrix. Write integration tests for the top 10 most likely combinations. Prioritize single-feature correctness first. | Testing |

---

### 3.6 Implementation Checklist (Ordered)

This is the recommended implementation order, accounting for blockers and dependencies.

#### Phase 0: Prerequisites (MUST complete before any feature work)

| # | Task | File(s) | Effort | Resolves | Blocks |
|---|------|---------|--------|----------|--------|
| 0.1 | Add `trackId: String` to `TimelineItem` base class | `lib/models/clips/timeline_item.dart`, all subclasses, serialization | 4h | CF1 (partial) | All multi-track features |
| 0.2 | Add `linkedItemId: String?` to `TimelineItem` base class | Same as 0.1 | 2h | CF6 | Link/Unlink, J/L Cuts |
| 0.3 | Add `_startTimeCache` via `Expando` to `PersistentTimeline` | `lib/models/persistent_timeline.dart` | 2h | CF2 | Batch operations performance |
| 0.4 | Create `TimelineCoordinator` utility class | `lib/core/timeline_coordinator.dart` (new) | 6h | CF1 | All multi-track features |
| 0.5 | Migrate `SmartEditViewModel` from `ClipManager` to `TimelineManager` | `lib/views/smart_edit/smart_edit_view_model.dart`, `lib/core/timeline_manager.dart` | 16h | CF3, C5 | Feature accessibility |
| 0.6 | Add `AudioClip.splitAt()` method | `lib/models/clips/audio_clip.dart` | 1h | MF3 | Audio split, J/L Cuts |
| 0.7 | Add `ImageClip` handling to `TimelineManager.splitAt()` and type switches | `lib/core/timeline_manager.dart` | 1h | I10, MF5 | Image clip operations |
| 0.8 | Unit tests for all Phase 0 changes | `test/` | 8h | - | Confidence |
| | **Phase 0 Total** | | **40h (~1 week)** | | |

#### Phase 1: Duplicate + Magnetic Timeline (Week 2)

| # | Task | File(s) | Effort | Notes |
|---|------|---------|--------|-------|
| 1.1 | Implement `duplicateItems()` on `TimelineManager` (snapshot-first approach per C2 fix) | `lib/core/timeline_manager.dart` | 2h | Capture all data before mutations |
| 1.2 | Create `DuplicateController` (delegate from `ClipboardController.duplicate()` per I3) | `lib/timeline/editing/duplicate_controller.dart` | 2h | Single source of duplication logic |
| 1.3 | Duplicate UI: context menu + toolbar button | Timeline toolbar widget | 2h | Use `CupertinoActionSheet`, `CNButton.icon` |
| 1.4 | Create `GapCloseController` with transition awareness (per I1) | `lib/timeline/editing/gap_close_controller.dart` | 4h | Accept `List<ClipTransition>`, return orphaned transition IDs |
| 1.5 | Integrate magnetic close into delete/move/trim in `TimelineManager` | `lib/core/timeline_manager.dart` | 3h | Use `TimelineCoordinator` for track-scoped queries |
| 1.6 | Magnetic mode toggle UI | Timeline toolbar widget | 1h | `CupertinoButton` with magnet icon |
| 1.7 | Magnetic close animation (painter interpolation, 200ms) | `lib/timeline/rendering/painters/` | 2h | Visual-only, data updates immediately |
| 1.8 | Unit tests for Phase 1 | `test/timeline/editing/` | 4h | |
| | **Phase 1 Total** | | **20h** | |

#### Phase 2: Waveform (Week 3)

| # | Task | File(s) | Effort | Notes |
|---|------|---------|--------|-------|
| 2.1 | Swift waveform extraction plugin | `ios/Runner/WaveformExtractorPlugin.swift` | 6h | R1 M8 correctly noted 4h is optimistic; budget 6h |
| 2.2 | Platform channel bridge connecting to existing `WaveformCache` | `lib/services/waveform_extractor.dart` | 2h | Wire `waveformGenerator` callback |
| 2.3 | Waveform path pre-computation layer | `lib/timeline/rendering/waveform_path_builder.dart` (new) | 3h | Build `Map<String, Path>`, invalidate on zoom |
| 2.4 | `ClipsPainter` integration with pre-computed waveform paths | `lib/timeline/rendering/painters/clip_painter.dart` | 2h | Pass paths, update `shouldRepaint` |
| 2.5 | Placeholder/loading animation during extraction | Painter code | 1h | Pulsing bar at 50% height |
| 2.6 | Tests | `test/timeline/rendering/`, `test/timeline/cache/` | 2h | |
| | **Phase 2 Total** | | **16h** | Reduced from 17h per CF4 |

#### Phase 3: Multi-Select + Link/Unlink (Week 4)

| # | Task | File(s) | Effort | Notes |
|---|------|---------|--------|-------|
| 3.1 | Refine marquee gesture: real-time clip highlight, fix `selectClips()` mode reset (IF1) | Gesture handler, `SelectionState` | 2h | Use `copyWith(selectedClipIds:)` instead of `selectClips()` |
| 3.2 | Multi-select group operations (delete, move, copy, duplicate) | Various controllers | 3h | Ensure all use `SelectionState.selectedClipIds` |
| 3.3 | Create `LinkController` with validation | `lib/timeline/editing/link_controller.dart` | 3h | Use `linkedItemId` from data model (Phase 0.2) |
| 3.4 | Link propagation in drag/trim/delete (use `firstWhereOrNull` per I2) | Gesture handler, controllers | 4h | R2 Risk 5 suggests 6-8h for J/L trim; basic link propagation is simpler |
| 3.5 | Link visual indicators (chain icon, connecting line) | `ClipsPainter`, `LinkIndicatorPainter` (new) | 2h | |
| 3.6 | Link/Unlink UI (context menu options) | Timeline context menu | 1h | |
| 3.7 | Auto-link on video import (create paired Video+Audio clips) | Import flow | 2h | |
| 3.8 | Unit tests | `test/timeline/editing/` | 4h | |
| | **Phase 3 Total** | | **21h** | |

#### Phase 4: Insert/Overwrite + J/L Cuts (Week 5)

| # | Task | File(s) | Effort | Notes |
|---|------|---------|--------|-------|
| 4.1 | Create `EditModeController` with insert shift + overwrite trim/split | `lib/timeline/editing/edit_mode_controller.dart` | 4h | Handle 3-way split per I7 (two sequential 2-way splits) |
| 4.2 | Insert mode implementation (explicit split-before-shift per CF5) | Integration with paste, drag, duplicate | 3h | All within single `_execute()` |
| 4.3 | Overwrite mode implementation | Integration with paste, drag, duplicate | 3h | |
| 4.4 | Edit mode toggle UI + playhead visual indicator | Timeline toolbar | 1h | Red overlay on playhead for overwrite |
| 4.5 | Add `LinkMode` to `TimelineClip` (per C3, deferred to Phase 4) | `lib/timeline/data/models/timeline_clip.dart` | 2h | `full`, `trimIndependent`, `none` |
| 4.6 | J-cut / L-cut independent audio trim | `TrimController`, hit testing, `LinkController` | 6h | R2 Risk 5 correctly estimates 6-8h |
| 4.7 | J/L cut visual representation (overhang rendering) | `ClipsPainter` | 2h | Lower opacity + hash pattern |
| 4.8 | Unit tests | `test/timeline/editing/` | 4h | |
| | **Phase 4 Total** | | **25h** | Increased from 20h for J/L complexity |

#### Phase 5: Replace + Undo History (Week 6)

| # | Task | File(s) | Effort | Notes |
|---|------|---------|--------|-------|
| 5.1 | Create `ReplaceClipController` with validation and duration mismatch handling | `lib/timeline/editing/replace_clip_controller.dart` | 2h | Remove `loopMedia` from enum per M2/IF6 |
| 5.2 | `replaceClipMedia()` on `TimelineManager` + waveform cache invalidation hook (per I6) | `lib/core/timeline_manager.dart` | 2h | |
| 5.3 | Duration mismatch UI + Replace clip flow | `CupertinoActionSheet`, media picker | 3h | |
| 5.4 | `UndoHistoryEntry` model + `UndoStack<T>` encapsulation (per R9) | `lib/timeline/data/models/undo_history_entry.dart`, `lib/core/timeline_manager.dart` | 3h | Pair timeline+metadata to prevent desync |
| 5.5 | Update `_execute()`, `undo()`, `redo()`, `clearHistory()`, `loadFromJson()`, `clear()`, `reset()` for metadata (per C8, V4) | `lib/core/timeline_manager.dart` | 2h | 7 methods total |
| 5.6 | `jumpToUndoState()` with O(1) single-notification (per C7 fix) | `lib/core/timeline_manager.dart` | 1h | |
| 5.7 | `UndoHistoryPanel` Liquid Glass widget | `lib/timeline/widgets/undo_history_panel.dart` | 3h | `BackdropFilter`, `CupertinoListSection` |
| 5.8 | Unit tests | `test/timeline/` | 4h | |
| | **Phase 5 Total** | | **20h** | |

#### Total Effort Summary

| Phase | Hours | Calendar | Prerequisite |
|-------|-------|----------|--------------|
| Phase 0: Prerequisites | 40h | Week 1 | None |
| Phase 1: Duplicate + Magnetic | 20h | Week 2 | Phase 0 |
| Phase 2: Waveform | 16h | Week 3 | Phase 0.5 (V1 migration) |
| Phase 3: Multi-Select + Link | 21h | Week 4 | Phase 0 |
| Phase 4: Insert/Overwrite + J/L | 25h | Week 5 | Phase 3 (Link) |
| Phase 5: Replace + Undo History | 20h | Week 6 | Phase 0.5 |
| **Total** | **142h** | **6 weeks** | |

**Note:** Original estimate was 90h across 5 weeks. The revised estimate of 142h across 6 weeks accounts for Phase 0 prerequisites (40h) that were not in the original plan, increased J/L cut estimate, and increased waveform native plugin estimate. The Phase 0 work is essential infrastructure that de-risks all subsequent phases.

---

### 3.7 Feature Independence Analysis

Given the two remaining blockers (CF1: model bridge, CF3: V1 migration), which features can ship independently?

| Feature | Requires Multi-Track? | Requires V1 Migration? | Requires Link? | Can Ship Independently? | Notes |
|---------|----------------------|----------------------|----------------|------------------------|-------|
| **Duplicate Clip** | No (operates on individual items by ID) | YES (must be accessible from SmartEditView) | No | **PARTIAL** - data layer works now, UI requires CF3 | `duplicateItems()` on `TimelineManager` can be implemented and tested in isolation. UI integration requires V1 migration. |
| **Magnetic Timeline** | YES (track-scoped gap detection) | YES | No | **NO** | Requires both CF1 and CF3. |
| **Waveform on Audio Clips** | No (rendering only, keyed by `mediaAssetId`) | Partially (waveform renders in timeline widget, not SmartEditView) | No | **YES** | The waveform extraction pipeline and painter integration operate on the rendering layer (`TimelineClip`, `ClipsPainter`). These are independent of the data model bridge and V1 migration. Can be shipped as a standalone visual enhancement. |
| **Multi-Select (Marquee)** | No (operates on `SelectionState`, existing gestures) | No (operates on timeline gesture layer) | No | **YES** | All infrastructure exists. Remaining work is refinement (real-time highlight, IF1 fix). Can ship independently. |
| **Link/Unlink Audio-Video** | Partially (link is cross-track by nature) | YES | - | **NO** | Requires `linkedItemId` on data model (Phase 0.2) and V1 migration. |
| **Insert vs Overwrite Edit** | YES (track-scoped clip shift) | YES | No | **NO** | Requires CF1 and CF3. |
| **J-Cut / L-Cut** | YES (audio on different track) | YES | YES (Link/Unlink) | **NO** | Depends on Link/Unlink + track awareness. |
| **Replace Clip** | No (single item update by ID) | YES | No | **PARTIAL** - data layer works now, UI requires CF3 | Same as Duplicate: `replaceClipMedia()` can be implemented on `TimelineManager`. |
| **Undo History Visualization** | No (operates on `TimelineManager` stacks) | YES (panel needs to be in SmartEditView) | No | **PARTIAL** - metadata tracking works now, panel UI requires CF3 | `UndoHistoryEntry` model and `_execute()` changes are independent. Panel widget is independent of data model bridge. However, it needs to be accessible from the main editor UI (CF3). |
| **Timeline Zoom Pinch** | No | No | No | **ALREADY DONE** | Verified complete in Section 12. |

**Features that can ship before CF1/CF3 resolution:**
1. **Multi-Select (Marquee)** - Refinement only, operates entirely on the rendering/gesture layer
2. **Waveform on Audio Clips** - Native extraction + painter integration, operates on rendering layer

**Features that can have data-layer work done pre-migration (testable in isolation):**
3. **Duplicate Clip** - `TimelineManager.duplicateItems()` + unit tests
4. **Replace Clip** - `TimelineManager.replaceClipMedia()` + unit tests
5. **Undo History Visualization** - metadata model + `_execute()` changes + unit tests

---

### 3.8 Final Assessment: CONDITIONAL GO

**Decision: CONDITIONAL GO**

The design document is comprehensive, well-structured, and covers the 10 features with appropriate depth. The feature specifications are sound, the edge cases are well-considered, and the performance analysis is realistic (once the O(n) `startTimeOf` issue is fixed).

However, implementation cannot proceed on the full feature set until two blockers are resolved:

#### Conditions for Full GO:

1. **CF1 Resolution (Model Bridge):** Add `trackId` and `linkedItemId` to `TimelineItem` base class. Create `TimelineCoordinator` utility class. This is Phase 0, steps 0.1-0.4. **Must be complete before Phases 1, 3, 4 begin.**

2. **CF3 Resolution (V1 Migration):** Migrate `SmartEditViewModel` from `ClipManager` to `TimelineManager`. This is Phase 0, step 0.5. **Must be complete before any feature UI is accessible.**

#### Immediate Actions (Can Start Now):

The following work can begin in parallel with Phase 0:

- **Multi-Select marquee refinement** (Phase 3.1): Fix IF1 (`selectClips` mode reset), add real-time clip highlight. This is self-contained in the gesture/rendering layer.
- **Waveform native extraction plugin** (Phase 2.1-2.2): Swift AVFoundation work and platform channel bridge are independent of all blockers.
- **`startTimeOf()` cache** (Phase 0.3): 2 hours, immediately improves all existing batch operations.
- **`AudioClip.splitAt()`** (Phase 0.6): 1 hour, removes a known gap.
- **Undo history metadata model** (Phase 5.4-5.5): Can be implemented on `TimelineManager` without UI integration.

#### Items Explicitly Deferred or Dropped:

1. **Two-finger marquee** (from Section 6.3.1): DROPPED. Long-press is sufficient. Two-finger conflicts with zoom and adds significant complexity for marginal gain. Unanimous across R1 (I4) and R2 (Risk 8).
2. **`DurationMismatchStrategy.loopMedia`**: DROPPED from enum. Not documented in behavior spec. Can be added later if needed.
3. **`affectedClipCount` auto-derivation**: DEFERRED to post-launch. Acceptable to show `0` for V1. Auto-derive from tree diff in a follow-up.
4. **Branching undo visualization**: DEFERRED (acknowledged in Section 11.5). Linear undo is sufficient for V1.

---

### 3.9 Remaining Open Questions

| # | Question | Context | Proposed Answer | Status |
|---|----------|---------|-----------------|--------|
| OQ1 | Should `trackId` on `TimelineItem` be `final` or allow reassignment for cross-track moves? | Phase 0.1 design decision | `final` -- create a new item via `copyWith(trackId:)` for cross-track moves. Consistent with immutability-first principle. | **Needs confirmation** |
| OQ2 | When magnetic close encounters both an implicit gap and a transition, which takes priority? | Phase 1.4 edge case | Remove the transition first (it references a deleted clip), then close the gap. The gap-close algorithm should run AFTER transition cleanup. | **Needs confirmation** |
| OQ3 | For the `TimelineCoordinator`, should `buildClips()` be called on every `notifyListeners()` or only when the timeline changes? | Performance consideration | Only when `_compositionDirty == true`. The coordinator result should be cached and invalidated on dirty flag. | **Needs confirmation** |
| OQ4 | How should `SmartEditViewModel` expose `TimelineManager` to child widgets? | Architecture -- Provider? GetIt? Direct injection? | Match existing pattern in codebase. If `ClipManager` is provided via constructor injection, use the same pattern for `TimelineManager`. | **Needs codebase audit** |
| OQ5 | The `Project` model references `ClipManager` (`lib/models/project.dart`). Should `Project.clips` serialize from `TimelineManager.toJson()` instead? | CF3 migration detail | Yes. `Project.withClips()` should accept `List<Map<String, dynamic>>` from `TimelineManager.toJson()`. | **Needs confirmation** |
| OQ6 | What is the maximum number of tracks the app should support? | Affects whether O(n) track filtering on `toList()` is acceptable long-term | For a mobile editor, 8-12 tracks is reasonable. With 1000 clips across 10 tracks, `toList()` + filter is 1000 iterations (~0.1ms). Acceptable. Beyond 50 tracks, consider per-track trees. | **Design decision needed** |

---

### 3.10 Review Summary Statistics (All Three Reviews Combined)

| Category | R1 | R2 | R3 | Total Unique |
|----------|----|----|----|----|
| CRITICAL | 8 | 6 | 0 new (all tracked) | 14 |
| IMPORTANT | 12 | 9 | 0 new | 21 |
| MINOR | 9 | 7 | 0 new | 16 |
| QUESTIONS | 6 | 0 | 6 new (OQ1-OQ6) | 12 |
| ACTION ITEMS | 0 | 4 | 7 (Phase 0 tasks) | 11 |
| **Resolved** | - | - | **11 of 14 critical** | |
| **Unresolved Blockers** | - | - | **2 (CF1, CF3)** | |

**Final Verdict:** The design is sound. The implementation plan is viable with the addition of Phase 0. Two blockers must be resolved before the full feature set can ship, but 2 features (Multi-Select refinement, Waveform) and 3 data-layer implementations (Duplicate, Replace, Undo metadata) can proceed immediately.

**Estimated total delivery: 6 weeks from Phase 0 start, or 5 weeks from Phase 0 completion.**
