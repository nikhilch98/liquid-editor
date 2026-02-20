# Timeline UI/UX Implementation Document

**Version:** 1.0
**Last Updated:** 2026-01-30
**Target Platform:** iOS (Mobile Only)
**Framework:** Flutter + Native iOS (AVFoundation)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Performance Architecture](#3-performance-architecture)
4. [Core Data Structures](#4-core-data-structures)
5. [Timeline Structure & Layout](#5-timeline-structure--layout)
6. [Playhead & Navigation](#6-playhead--navigation)
7. [Clip Representation & Interaction](#7-clip-representation--interaction)
8. [Trimming & Editing](#8-trimming--editing)
9. [Snapping & Alignment](#9-snapping--alignment)
10. [Markers & Annotations](#10-markers--annotations)
11. [Transitions & Effects](#11-transitions--effects)
12. [Keyframe System](#12-keyframe-system)
13. [Audio Features](#13-audio-features)
14. [Gesture System](#14-gesture-system)
15. [Undo/Redo System](#15-undoredo-system)
16. [Performance Optimizations](#16-performance-optimizations)
17. [File Structure](#17-file-structure)
18. [Implementation Phases](#18-implementation-phases)

---

## 1. Executive Summary

### 1.1 Goals

- **Zero-lag timeline interactions** - All gestures respond within 16ms (60fps)
- **Butter-smooth scrolling** - No dropped frames during pan/zoom
- **Instant playhead response** - Scrubbing feels connected to touch
- **Professional feature set** - Match/exceed CapCut, DaVinci, LumaFusion
- **Native iOS feel** - Leverage platform conventions and haptics

### 1.2 Key Principles

1. **GPU-First Rendering** - All timeline visuals on GPU via CustomPainter
2. **Lazy Everything** - Only render/compute what's visible
3. **Predictive Loading** - Anticipate user actions and preload
4. **Immutable State** - All timeline state changes create new objects
5. **Gesture Priority** - Touch response takes precedence over everything

### 1.3 Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Touch-to-visual latency | < 16ms | Time from touch event to frame render |
| Scroll frame rate | 60fps constant | No drops during pan/pinch |
| Playhead scrub latency | < 8ms | Playhead position update |
| Clip move feedback | < 16ms | Visual update on drag start |
| Thumbnail load time | < 100ms | First thumbnail visible |
| Waveform generation | < 2s/minute | Background processing |

---

## 2. Architecture Overview

### 2.1 Layer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    TimelineWidget                            ││
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ ││
│  │  │  RulerLayer  │ │ TracksLayer  │ │   OverlayLayer       │ ││
│  │  │  (Canvas)    │ │  (Canvas)    │ │ (Playhead/Selection) │ ││
│  │  └──────────────┘ └──────────────┘ └──────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                      INTERACTION LAYER                           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                TimelineGestureHandler                        ││
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌───────────┐ ││
│  │  │ PanHandler │ │PinchHandler│ │ TapHandler │ │LongPress  │ ││
│  │  └────────────┘ └────────────┘ └────────────┘ └───────────┘ ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                       STATE LAYER                                │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │               TimelineViewController                         ││
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ ││
│  │  │ViewportState │ │SelectionState│ │    EditState         │ ││
│  │  └──────────────┘ └──────────────┘ └──────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                       DATA LAYER                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                 TimelineDataManager                          ││
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ ││
│  │  │PersistentTree│ │ UndoManager  │ │   AssetRegistry      │ ││
│  │  └──────────────┘ └──────────────┘ └──────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│                      CACHE LAYER                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ ││
│  │  │ThumbnailCache│ │WaveformCache │ │   LayoutCache        │ ││
│  │  └──────────────┘ └──────────────┘ └──────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Rendering Pipeline

```
Touch Event
    │
    ▼
┌─────────────────┐
│ Gesture Handler │ ─── Immediate visual feedback (< 8ms)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ State Update    │ ─── Batched state changes
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Layout Compute  │ ─── Only affected regions
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Render (GPU)    │ ─── Canvas repaint
└─────────────────┘
```

### 2.3 Component Communication

```dart
/// Central timeline controller - single source of truth
class TimelineViewController extends ChangeNotifier {
  // Viewport state (zoom, scroll position)
  final ViewportController viewport;

  // Selection state (selected clips, edit mode)
  final SelectionController selection;

  // Timeline data (clips, tracks, markers)
  final TimelineDataManager data;

  // Playback state (current time, playing)
  final PlaybackController playback;

  // Undo/redo management
  final UndoManager undoManager;
}
```

---

## 3. Performance Architecture

### 3.1 Rendering Strategy

#### 3.1.1 Virtualized Rendering

Only render clips that are visible in the current viewport:

```dart
class TimelineViewport {
  /// Visible time range
  final int startTimeMicros;
  final int endTimeMicros;

  /// Visible track range
  final int firstVisibleTrack;
  final int lastVisibleTrack;

  /// Pixels per microsecond (zoom level)
  final double pixelsPerMicrosecond;

  /// Calculate visible clips from timeline tree
  List<ClipRenderData> getVisibleClips(PersistentTimeline timeline) {
    // O(log n + k) where k is visible clips
    return timeline.queryRange(startTimeMicros, endTimeMicros);
  }
}
```

#### 3.1.2 Layer Separation

Separate static and dynamic content for efficient repaints:

```dart
class TimelineRenderLayers {
  // Layer 0: Background (rarely changes)
  final BackgroundLayer background;

  // Layer 1: Track backgrounds (changes on track edit)
  final TrackBackgroundLayer trackBg;

  // Layer 2: Clips (changes on timeline edit)
  final ClipLayer clips;

  // Layer 3: Waveforms (async loading)
  final WaveformLayer waveforms;

  // Layer 4: Thumbnails (async loading)
  final ThumbnailLayer thumbnails;

  // Layer 5: Transitions (changes on transition edit)
  final TransitionLayer transitions;

  // Layer 6: Keyframes (changes on animation edit)
  final KeyframeLayer keyframes;

  // Layer 7: Markers (changes on marker edit)
  final MarkerLayer markers;

  // Layer 8: Selection highlights (changes frequently)
  final SelectionLayer selection;

  // Layer 9: Playhead (changes every frame during playback)
  final PlayheadLayer playhead;

  // Layer 10: Drag preview (changes during drag)
  final DragPreviewLayer dragPreview;

  // Layer 11: Snap guides (changes during drag)
  final SnapGuideLayer snapGuides;
}
```

#### 3.1.3 Repaint Regions

Minimize repaint area using RepaintBoundary:

```dart
class TimelineWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Static layers - repaint only on data change
        RepaintBoundary(
          child: CustomPaint(
            painter: ClipPainter(clips: visibleClips),
          ),
        ),

        // Dynamic layers - repaint frequently
        RepaintBoundary(
          child: CustomPaint(
            painter: PlayheadPainter(time: currentTime),
          ),
        ),
      ],
    );
  }
}
```

### 3.2 Memory Management

#### 3.2.1 Thumbnail Cache Strategy

```dart
class ThumbnailCache {
  /// Maximum memory for thumbnails (50MB default)
  static const int maxMemoryBytes = 50 * 1024 * 1024;

  /// LRU cache with memory pressure handling
  final LruCache<ThumbnailKey, ui.Image> _cache;

  /// Priority queue for loading
  final PriorityQueue<ThumbnailRequest> _loadQueue;

  /// Currently loading thumbnails
  final Set<ThumbnailKey> _loading;

  /// Get thumbnail or schedule load
  ui.Image? getThumbnail(String assetId, int timeMicros, int width) {
    final key = ThumbnailKey(assetId, timeMicros, width);

    // Check cache
    final cached = _cache.get(key);
    if (cached != null) return cached;

    // Schedule load if not already loading
    if (!_loading.contains(key)) {
      _scheduleLoad(key, priority: _calculatePriority(key));
    }

    return null; // Return placeholder
  }

  /// Calculate load priority based on visibility
  int _calculatePriority(ThumbnailKey key) {
    // Higher priority for:
    // 1. Clips near playhead
    // 2. Clips in center of viewport
    // 3. Selected clips
  }
}
```

#### 3.2.2 Waveform Cache Strategy

```dart
class WaveformCache {
  /// Waveform data at multiple LODs
  final Map<String, WaveformLOD> _waveforms;

  /// LOD levels: 1 sample per 100ms, 10ms, 1ms
  static const List<int> lodLevels = [100000, 10000, 1000];

  /// Get waveform samples for visible range
  Float32List getWaveformSamples(
    String assetId,
    int startMicros,
    int endMicros,
    int targetSamples,
  ) {
    // Select appropriate LOD based on zoom
    final microsPerSample = (endMicros - startMicros) / targetSamples;
    final lodLevel = _selectLOD(microsPerSample);

    // Return cached samples or schedule generation
    return _waveforms[assetId]?.getSamples(
      startMicros, endMicros, lodLevel
    ) ?? Float32List(0);
  }
}
```

### 3.3 Threading Model

```dart
/// Background processing isolates
class TimelineWorkers {
  /// Thumbnail generation isolate
  final Isolate thumbnailWorker;

  /// Waveform generation isolate
  final Isolate waveformWorker;

  /// Layout computation isolate (for complex timelines)
  final Isolate layoutWorker;

  /// Communication ports
  final SendPort thumbnailPort;
  final SendPort waveformPort;
  final SendPort layoutPort;
}
```

---

## 4. Core Data Structures

### 4.1 Time Representation

```dart
/// All times stored as microseconds (int64)
/// NEVER use Duration or double for timeline times
typedef TimeMicros = int;

/// Time utilities
extension TimeMicrosExtensions on TimeMicros {
  /// Convert to seconds
  double get seconds => this / 1000000.0;

  /// Convert to milliseconds
  double get milliseconds => this / 1000.0;

  /// Format as timecode (HH:MM:SS:FF)
  String toTimecode(Rational frameRate) {
    final totalFrames = timeToFrames(this, frameRate);
    final fps = frameRate.toDouble().round();
    final frames = totalFrames % fps;
    final totalSeconds = totalFrames ~/ fps;
    final seconds = totalSeconds % 60;
    final totalMinutes = totalSeconds ~/ 60;
    final minutes = totalMinutes % 60;
    final hours = totalMinutes ~/ 60;

    return '${hours.toString().padLeft(2, '0')}:'
           '${minutes.toString().padLeft(2, '0')}:'
           '${seconds.toString().padLeft(2, '0')}:'
           '${frames.toString().padLeft(2, '0')}';
  }
}
```

### 4.2 Viewport State

```dart
@immutable
class ViewportState {
  /// Scroll position (microseconds at left edge)
  final TimeMicros scrollPosition;

  /// Zoom level (microseconds per pixel)
  final double microsPerPixel;

  /// Viewport width in pixels
  final double viewportWidth;

  /// Viewport height in pixels
  final double viewportHeight;

  /// Vertical scroll offset (for multi-track)
  final double verticalOffset;

  /// Calculate visible time range
  TimeRange get visibleTimeRange {
    final startMicros = scrollPosition;
    final endMicros = scrollPosition + (viewportWidth * microsPerPixel).round();
    return TimeRange(startMicros, endMicros);
  }

  /// Convert time to pixel X coordinate
  double timeToPixelX(TimeMicros time) {
    return (time - scrollPosition) / microsPerPixel;
  }

  /// Convert pixel X to time
  TimeMicros pixelXToTime(double pixelX) {
    return scrollPosition + (pixelX * microsPerPixel).round();
  }

  /// Zoom limits
  static const double minMicrosPerPixel = 100; // ~10ms per pixel (max zoom)
  static const double maxMicrosPerPixel = 100000; // ~100ms per pixel (min zoom)
}
```

### 4.3 Track Model

```dart
@immutable
class Track {
  final String id;
  final String name;
  final TrackType type; // video, audio, effect
  final int index; // vertical position
  final double height; // pixels
  final bool isMuted;
  final bool isSolo;
  final bool isLocked;
  final Color color;
  final bool isCollapsed;

  /// Track height presets
  static const double heightSmall = 44.0;
  static const double heightMedium = 64.0;
  static const double heightLarge = 88.0;
  static const double heightFilmstrip = 120.0;
}

enum TrackType {
  mainVideo,    // Primary video track
  overlayVideo, // B-roll, picture-in-picture
  audio,        // Audio track
  music,        // Music track
  voiceover,    // Voice recording
  effect,       // Adjustment layer
  text,         // Text/titles
}
```

### 4.4 Time Range Helper

```dart
@immutable
class TimeRange {
  final TimeMicros start;
  final TimeMicros end;

  const TimeRange(this.start, this.end);

  TimeMicros get duration => end - start;

  bool contains(TimeMicros time) => time >= start && time < end;

  bool overlaps(TimeRange other) {
    return start < other.end && end > other.start;
  }
}
```

### 4.5 Clip Type Enum

```dart
enum ClipType {
  video,
  audio,
  image,
  text,
  effect,
}
```

### 4.6 Clip Model (Enhanced)

```dart
@immutable
class TimelineClip {
  // Identity
  final String id;
  final String mediaAssetId;
  final String trackId;
  final ClipType type;            // Type of clip

  // Timeline position
  final TimeMicros startTime;     // Position on timeline
  final TimeMicros duration;      // Duration on timeline

  // Source range
  final TimeMicros sourceIn;      // In point in source
  final TimeMicros sourceOut;     // Out point in source

  // Speed
  final double speed;             // 1.0 = normal, 0.5 = half, 2.0 = double
  final bool isReversed;

  // Visual properties
  final Color clipColor;
  final String? label;

  // Links
  final String? linkedClipId;     // For A/V sync

  // Metadata
  final bool isOffline;           // Media file missing
  final bool hasEffects;
  final bool hasKeyframes;
  final int effectCount;

  /// Calculate end time on timeline
  TimeMicros get endTime => startTime + duration;

  /// Calculate source duration
  TimeMicros get sourceDuration => sourceOut - sourceIn;

  /// Check if time is within clip
  bool containsTime(TimeMicros time) {
    return time >= startTime && time < endTime;
  }

  /// Map timeline time to source time
  TimeMicros timelineToSource(TimeMicros timelineTime) {
    final offsetFromStart = timelineTime - startTime;
    final scaledOffset = (offsetFromStart * speed).round();
    if (isReversed) {
      return sourceOut - scaledOffset;
    }
    return sourceIn + scaledOffset;
  }
}
```

### 4.7 Selection State

```dart
@immutable
class SelectionState {
  /// Selected clip IDs
  final Set<String> selectedClipIds;

  /// Primary selected clip (for multi-select operations)
  final String? primaryClipId;

  /// In/Out point range
  final TimeMicros? inPoint;
  final TimeMicros? outPoint;

  /// Selection mode
  final SelectionMode mode;

  /// Check if clip is selected
  bool isSelected(String clipId) => selectedClipIds.contains(clipId);

  /// Check if has range selection
  bool get hasRange => inPoint != null && outPoint != null;

  /// Get range duration
  TimeMicros? get rangeDuration {
    if (inPoint == null || outPoint == null) return null;
    return outPoint! - inPoint!;
  }
}

enum SelectionMode {
  normal,       // Single/multi clip selection
  range,        // In/out point selection
  trimHead,     // Trimming clip start
  trimTail,     // Trimming clip end
  slip,         // Slipping content
  slide,        // Sliding position
}
```

---

## 5. Timeline Structure & Layout

### 5.1 Track System Implementation

#### 5.1.1 Track Header Widget

```dart
class TrackHeader extends StatelessWidget {
  final Track track;
  final VoidCallback onMuteToggle;
  final VoidCallback onSoloToggle;
  final VoidCallback onLockToggle;
  final VoidCallback onHeightChange;
  final VoidCallback onColorChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80, // Fixed track header width
      height: track.height,
      decoration: BoxDecoration(
        color: track.color.withOpacity(0.1),
        border: Border(
          right: BorderSide(color: Colors.white24),
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Track name (truncated)
          Text(
            track.name,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 4),
          // Control buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _TrackButton(
                icon: CupertinoIcons.speaker_slash_fill,
                isActive: track.isMuted,
                onTap: onMuteToggle,
                size: 20,
              ),
              _TrackButton(
                icon: CupertinoIcons.headphones,
                isActive: track.isSolo,
                onTap: onSoloToggle,
                size: 20,
              ),
              _TrackButton(
                icon: CupertinoIcons.lock_fill,
                isActive: track.isLocked,
                onTap: onLockToggle,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small icon button for track controls
class _TrackButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final double size;

  const _TrackButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: size + 8,
        height: size + 8,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive
              ? CupertinoColors.systemBlue.withOpacity(0.2)
              : CupertinoColors.tertiarySystemFill,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: size - 4,
          color: isActive
              ? CupertinoColors.systemBlue
              : CupertinoColors.secondaryLabel,
        ),
      ),
    );
  }
}
```

#### 5.1.2 Track Reordering

```dart
class TrackReorderController {
  /// Currently dragging track
  String? _draggingTrackId;

  /// Original index of dragging track
  int? _originalIndex;

  /// Current hover index during drag
  int? _hoverIndex;

  /// Start track drag
  void startDrag(String trackId, int index) {
    _draggingTrackId = trackId;
    _originalIndex = index;
    _hoverIndex = index;
    HapticFeedback.mediumImpact();
  }

  /// Update drag position
  void updateDrag(double y, List<Track> tracks) {
    final newIndex = _calculateTrackIndex(y, tracks);
    if (newIndex != _hoverIndex) {
      _hoverIndex = newIndex;
      HapticFeedback.selectionClick();
    }
  }

  /// Complete drag
  void endDrag(TimelineDataManager data) {
    if (_draggingTrackId != null &&
        _hoverIndex != null &&
        _hoverIndex != _originalIndex) {
      data.reorderTrack(_draggingTrackId!, _hoverIndex!);
      HapticFeedback.mediumImpact();
    }
    _reset();
  }

  /// Cancel drag
  void cancelDrag() {
    _reset();
  }
}
```

### 5.2 Timeline Canvas Implementation

#### 5.2.1 Main Timeline Widget

```dart
class TimelineCanvas extends StatefulWidget {
  final TimelineViewController controller;

  @override
  State<TimelineCanvas> createState() => _TimelineCanvasState();
}

class _TimelineCanvasState extends State<TimelineCanvas>
    with SingleTickerProviderStateMixin {

  late final TimelineGestureHandler _gestureHandler;
  late final AnimationController _scrollAnimationController;

  @override
  void initState() {
    super.initState();
    _gestureHandler = TimelineGestureHandler(
      controller: widget.controller,
      onRepaint: () => setState(() {}),
    );
    _scrollAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.controller.viewport.updateSize(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return GestureDetector(
          onScaleStart: _gestureHandler.onScaleStart,
          onScaleUpdate: _gestureHandler.onScaleUpdate,
          onScaleEnd: _gestureHandler.onScaleEnd,
          onTapDown: _gestureHandler.onTapDown,
          onTapUp: _gestureHandler.onTapUp,
          onLongPressStart: _gestureHandler.onLongPressStart,
          onLongPressMoveUpdate: _gestureHandler.onLongPressMoveUpdate,
          onLongPressEnd: _gestureHandler.onLongPressEnd,
          child: Stack(
            children: [
              // Background
              const TimelineBackground(),

              // Track lanes
              RepaintBoundary(
                child: CustomPaint(
                  painter: TrackLanesPainter(
                    tracks: widget.controller.data.tracks,
                    viewport: widget.controller.viewport.state,
                  ),
                  size: Size.infinite,
                ),
              ),

              // Clips
              RepaintBoundary(
                child: CustomPaint(
                  painter: ClipsPainter(
                    clips: _getVisibleClips(),
                    viewport: widget.controller.viewport.state,
                    selection: widget.controller.selection.state,
                    thumbnailCache: widget.controller.thumbnailCache,
                    waveformCache: widget.controller.waveformCache,
                  ),
                  size: Size.infinite,
                ),
              ),

              // Transitions
              RepaintBoundary(
                child: CustomPaint(
                  painter: TransitionsPainter(
                    transitions: _getVisibleTransitions(),
                    viewport: widget.controller.viewport.state,
                  ),
                  size: Size.infinite,
                ),
              ),

              // Markers
              RepaintBoundary(
                child: CustomPaint(
                  painter: MarkersPainter(
                    markers: widget.controller.data.markers,
                    viewport: widget.controller.viewport.state,
                  ),
                  size: Size.infinite,
                ),
              ),

              // Selection overlay
              RepaintBoundary(
                child: CustomPaint(
                  painter: SelectionOverlayPainter(
                    selection: widget.controller.selection.state,
                    viewport: widget.controller.viewport.state,
                  ),
                  size: Size.infinite,
                ),
              ),

              // Snap guides (during drag)
              if (_gestureHandler.isDragging)
                RepaintBoundary(
                  child: CustomPaint(
                    painter: SnapGuidesPainter(
                      guides: _gestureHandler.activeSnapGuides,
                      viewport: widget.controller.viewport.state,
                    ),
                    size: Size.infinite,
                  ),
                ),

              // Playhead (most frequently updated)
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: widget.controller.playback,
                  builder: (context, _) => CustomPaint(
                    painter: PlayheadPainter(
                      time: widget.controller.playback.currentTime,
                      viewport: widget.controller.viewport.state,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<TimelineClip> _getVisibleClips() {
    return widget.controller.data.queryVisibleClips(
      widget.controller.viewport.state.visibleTimeRange,
    );
  }
}
```

#### 5.2.2 Clip Painter Implementation

```dart
class ClipsPainter extends CustomPainter {
  final List<TimelineClip> clips;
  final ViewportState viewport;
  final SelectionState selection;
  final ThumbnailCache thumbnailCache;
  final WaveformCache waveformCache;

  // Paint objects (reused for performance)
  final Paint _clipBgPaint = Paint();
  final Paint _clipBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _selectionPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  final Paint _waveformPaint = Paint()
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    for (final clip in clips) {
      _paintClip(canvas, clip, size);
    }
  }

  void _paintClip(Canvas canvas, TimelineClip clip, Size size) {
    // Calculate clip rect
    final left = viewport.timeToPixelX(clip.startTime);
    final right = viewport.timeToPixelX(clip.endTime);
    final top = _getTrackTop(clip.trackId);
    final height = _getTrackHeight(clip.trackId);

    // Skip if not visible
    if (right < 0 || left > size.width) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, right - left, height),
      const Radius.circular(4),
    );

    // 1. Draw clip background
    _clipBgPaint.color = clip.clipColor.withOpacity(0.8);
    canvas.drawRRect(rect, _clipBgPaint);

    // 2. Draw thumbnails (video clips)
    if (clip.type == ClipType.video) {
      _paintThumbnails(canvas, clip, rect.outerRect);
    }

    // 3. Draw waveform (audio clips)
    if (clip.type == ClipType.audio) {
      _paintWaveform(canvas, clip, rect.outerRect);
    }

    // 4. Draw clip label
    _paintClipLabel(canvas, clip, rect.outerRect);

    // 5. Draw effect badges
    if (clip.hasEffects) {
      _paintEffectBadge(canvas, rect.outerRect, clip.effectCount);
    }

    // 6. Draw speed indicator
    if (clip.speed != 1.0 || clip.isReversed) {
      _paintSpeedIndicator(canvas, rect.outerRect, clip.speed, clip.isReversed);
    }

    // 7. Draw selection highlight
    if (selection.isSelected(clip.id)) {
      _selectionPaint.color = Colors.white;
      canvas.drawRRect(rect, _selectionPaint);

      // Draw trim handles
      _paintTrimHandles(canvas, rect.outerRect);
    }

    // 8. Draw border
    _clipBorderPaint.color = Colors.white30;
    canvas.drawRRect(rect, _clipBorderPaint);

    // 9. Draw offline indicator
    if (clip.isOffline) {
      _paintOfflineIndicator(canvas, rect.outerRect);
    }
  }

  void _paintThumbnails(Canvas canvas, TimelineClip clip, Rect rect) {
    final thumbnailWidth = 60.0; // Fixed thumbnail width
    final visibleWidth = rect.width;
    final thumbnailCount = (visibleWidth / thumbnailWidth).ceil() + 1;

    for (int i = 0; i < thumbnailCount; i++) {
      final x = rect.left + (i * thumbnailWidth);
      if (x > rect.right) break;
      if (x + thumbnailWidth < rect.left) continue;

      // Calculate source time for this thumbnail
      final timeOffset = ((x - rect.left) / rect.width * clip.duration).round();
      final sourceTime = clip.timelineToSource(clip.startTime + timeOffset);

      // Get thumbnail from cache
      final thumbnail = thumbnailCache.getThumbnail(
        clip.mediaAssetId,
        sourceTime,
        thumbnailWidth.toInt(),
      );

      if (thumbnail != null) {
        final thumbnailRect = Rect.fromLTWH(
          x.clamp(rect.left, rect.right - 1),
          rect.top,
          thumbnailWidth.clamp(0, rect.right - x),
          rect.height,
        );

        canvas.save();
        canvas.clipRect(rect);
        canvas.drawImageRect(
          thumbnail,
          Rect.fromLTWH(0, 0, thumbnail.width.toDouble(), thumbnail.height.toDouble()),
          thumbnailRect,
          Paint(),
        );
        canvas.restore();
      }
    }
  }

  void _paintWaveform(Canvas canvas, TimelineClip clip, Rect rect) {
    final samples = waveformCache.getWaveformSamples(
      clip.mediaAssetId,
      clip.sourceIn,
      clip.sourceOut,
      rect.width.toInt(),
    );

    if (samples.isEmpty) return;

    final centerY = rect.center.dy;
    final maxAmplitude = rect.height / 2 - 4;

    _waveformPaint.color = clip.clipColor.withOpacity(0.5);

    final path = Path();
    path.moveTo(rect.left, centerY);

    for (int i = 0; i < samples.length; i++) {
      final x = rect.left + i;
      final amplitude = samples[i] * maxAmplitude;
      path.lineTo(x, centerY - amplitude);
    }

    // Mirror for bottom half
    for (int i = samples.length - 1; i >= 0; i--) {
      final x = rect.left + i;
      final amplitude = samples[i] * maxAmplitude;
      path.lineTo(x, centerY + amplitude);
    }

    path.close();
    canvas.drawPath(path, _waveformPaint);
  }

  void _paintTrimHandles(Canvas canvas, Rect rect) {
    const handleWidth = 8.0;
    const handleColor = Colors.white;

    final handlePaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.fill;

    // Left handle
    final leftHandle = RRect.fromRectAndCorners(
      Rect.fromLTWH(rect.left, rect.top + 4, handleWidth, rect.height - 8),
      topLeft: const Radius.circular(4),
      bottomLeft: const Radius.circular(4),
    );
    canvas.drawRRect(leftHandle, handlePaint);

    // Right handle
    final rightHandle = RRect.fromRectAndCorners(
      Rect.fromLTWH(rect.right - handleWidth, rect.top + 4, handleWidth, rect.height - 8),
      topRight: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(rightHandle, handlePaint);

    // Handle grip lines
    final gripPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1.0;

    // Left grip lines
    for (int i = 0; i < 3; i++) {
      final y = rect.center.dy - 6 + (i * 6);
      canvas.drawLine(
        Offset(rect.left + 2, y),
        Offset(rect.left + handleWidth - 2, y),
        gripPaint,
      );
    }

    // Right grip lines
    for (int i = 0; i < 3; i++) {
      final y = rect.center.dy - 6 + (i * 6);
      canvas.drawLine(
        Offset(rect.right - handleWidth + 2, y),
        Offset(rect.right - 2, y),
        gripPaint,
      );
    }
  }

  @override
  bool shouldRepaint(ClipsPainter oldDelegate) {
    return clips != oldDelegate.clips ||
           viewport != oldDelegate.viewport ||
           selection != oldDelegate.selection;
  }
}
```

### 5.3 Zoom Implementation

#### 5.3.1 Pinch-to-Zoom

```dart
class ZoomController {
  final ViewportController viewport;

  /// Zoom anchor point (where pinch started)
  Offset? _zoomAnchor;

  /// Time at anchor point
  TimeMicros? _anchorTime;

  /// Initial zoom level
  double? _initialMicrosPerPixel;

  /// Start zoom gesture
  void startZoom(Offset focalPoint) {
    _zoomAnchor = focalPoint;
    _anchorTime = viewport.state.pixelXToTime(focalPoint.dx);
    _initialMicrosPerPixel = viewport.state.microsPerPixel;
  }

  /// Update zoom
  void updateZoom(double scale) {
    if (_initialMicrosPerPixel == null || _anchorTime == null) return;

    // Calculate new zoom level
    final newMicrosPerPixel = (_initialMicrosPerPixel! / scale).clamp(
      ViewportState.minMicrosPerPixel,
      ViewportState.maxMicrosPerPixel,
    );

    // Calculate scroll position to keep anchor point stable
    final newScrollPosition = _anchorTime! -
        (_zoomAnchor!.dx * newMicrosPerPixel).round();

    viewport.update(
      microsPerPixel: newMicrosPerPixel,
      scrollPosition: newScrollPosition,
    );
  }

  /// End zoom gesture
  void endZoom() {
    _zoomAnchor = null;
    _anchorTime = null;
    _initialMicrosPerPixel = null;
  }

  /// Zoom to specific level with animation
  Future<void> zoomTo(double targetMicrosPerPixel, {Duration? duration}) async {
    final startMicrosPerPixel = viewport.state.microsPerPixel;
    final startScroll = viewport.state.scrollPosition;

    // Calculate center time to keep centered during zoom
    final centerTime = viewport.state.pixelXToTime(
      viewport.state.viewportWidth / 2
    );

    final animation = AnimationController(
      vsync: _vsync,
      duration: duration ?? const Duration(milliseconds: 200),
    );

    animation.addListener(() {
      final t = Curves.easeOutCubic.transform(animation.value);
      final currentMicrosPerPixel = startMicrosPerPixel +
          (targetMicrosPerPixel - startMicrosPerPixel) * t;

      final newScrollPosition = centerTime -
          ((viewport.state.viewportWidth / 2) * currentMicrosPerPixel).round();

      viewport.update(
        microsPerPixel: currentMicrosPerPixel,
        scrollPosition: newScrollPosition,
      );
    });

    await animation.forward();
    animation.dispose();
  }

  /// Zoom presets
  void zoomToFitAll(TimeMicros totalDuration) {
    final targetMicrosPerPixel = totalDuration /
        (viewport.state.viewportWidth * 0.95);
    zoomTo(targetMicrosPerPixel);
  }

  void zoomToSelection(TimeMicros start, TimeMicros end) {
    final duration = end - start;
    final targetMicrosPerPixel = duration /
        (viewport.state.viewportWidth * 0.8);
    zoomTo(targetMicrosPerPixel);
  }

  void zoomToFrameLevel(Rational frameRate) {
    // Show approximately 30 frames on screen
    final frameDuration = framesToTime(1, frameRate);
    final targetMicrosPerPixel = (frameDuration * 30) /
        viewport.state.viewportWidth;
    zoomTo(targetMicrosPerPixel);
  }
}
```

### 5.4 Minimap/Overview Implementation

```dart
class TimelineMinimap extends StatelessWidget {
  final TimelineViewController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: GestureDetector(
        onTapDown: (details) => _jumpToPosition(details.localPosition),
        onHorizontalDragUpdate: (details) => _jumpToPosition(details.localPosition),
        child: CustomPaint(
          painter: MinimapPainter(
            clips: controller.data.allClips,
            totalDuration: controller.data.totalDuration,
            visibleRange: controller.viewport.state.visibleTimeRange,
            playheadTime: controller.playback.currentTime,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _jumpToPosition(Offset position) {
    final totalDuration = controller.data.totalDuration;
    final time = (position.dx / context.size!.width * totalDuration).round();

    controller.viewport.scrollToTime(time, centered: true);
    HapticFeedback.lightImpact();
  }
}

class MinimapPainter extends CustomPainter {
  final List<TimelineClip> clips;
  final TimeMicros totalDuration;
  final TimeRange visibleRange;
  final TimeMicros playheadTime;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black54,
    );

    // Draw clips as colored rectangles
    for (final clip in clips) {
      final left = clip.startTime / totalDuration * size.width;
      final width = clip.duration / totalDuration * size.width;
      final trackIndex = _getTrackIndex(clip.trackId);
      final top = trackIndex * (size.height / _totalTracks);
      final clipHeight = size.height / _totalTracks - 1;

      canvas.drawRect(
        Rect.fromLTWH(left, top, width.clamp(1, size.width), clipHeight),
        Paint()..color = clip.clipColor.withOpacity(0.7),
      );
    }

    // Draw visible range indicator
    final rangeLeft = visibleRange.start / totalDuration * size.width;
    final rangeWidth = visibleRange.duration / totalDuration * size.width;

    canvas.drawRect(
      Rect.fromLTWH(rangeLeft, 0, rangeWidth, size.height),
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.fill,
    );

    canvas.drawRect(
      Rect.fromLTWH(rangeLeft, 0, rangeWidth, size.height),
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Draw playhead
    final playheadX = playheadTime / totalDuration * size.width;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = Colors.red
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(MinimapPainter oldDelegate) {
    return clips != oldDelegate.clips ||
           visibleRange != oldDelegate.visibleRange ||
           playheadTime != oldDelegate.playheadTime;
  }
}
```

---

## 6. Playhead & Navigation

### 6.1 Playhead Modes

#### 6.1.1 Fixed-Center Playhead (CapCut Style)

```dart
class FixedCenterPlayheadController {
  final ViewportController viewport;
  final PlaybackController playback;

  /// Center position on screen
  double get centerX => viewport.state.viewportWidth / 2;

  /// Calculate scroll position to center given time
  TimeMicros _scrollForTime(TimeMicros time) {
    return time - (centerX * viewport.state.microsPerPixel).round();
  }

  /// Scroll timeline to center time
  void centerOnTime(TimeMicros time, {bool animated = true}) {
    final targetScroll = _scrollForTime(time);

    if (animated) {
      viewport.animateScrollTo(targetScroll);
    } else {
      viewport.setScrollPosition(targetScroll);
    }
  }

  /// During playback: continuously scroll to keep playhead centered
  void onPlaybackUpdate(TimeMicros currentTime) {
    final targetScroll = _scrollForTime(currentTime);
    viewport.setScrollPosition(targetScroll);
  }

  /// During scrub: move timeline, playhead stays fixed
  void onScrub(double deltaX) {
    final timeDelta = (deltaX * viewport.state.microsPerPixel).round();
    final newTime = (playback.currentTime + timeDelta).clamp(
      0,
      playback.duration,
    );

    // Update both playhead time and scroll position together
    playback.seekTo(newTime);
    viewport.setScrollPosition(_scrollForTime(newTime));
  }
}
```

#### 6.1.2 Moving Playhead (Traditional)

```dart
class MovingPlayheadController {
  final ViewportController viewport;
  final PlaybackController playback;

  /// Auto-scroll margin (how close to edge before scrolling)
  static const double scrollMargin = 100.0;

  /// During playback: scroll when playhead approaches edge
  void onPlaybackUpdate(TimeMicros currentTime) {
    final playheadX = viewport.state.timeToPixelX(currentTime);

    // Check if playhead is near right edge
    if (playheadX > viewport.state.viewportWidth - scrollMargin) {
      // Scroll to keep playhead at left side
      final newScroll = currentTime -
          ((scrollMargin * 2) * viewport.state.microsPerPixel).round();
      viewport.animateScrollTo(newScroll);
    }

    // Check if playhead is before viewport (looped back)
    if (playheadX < 0) {
      final newScroll = currentTime -
          (scrollMargin * viewport.state.microsPerPixel).round();
      viewport.animateScrollTo(newScroll);
    }
  }

  /// Scrub: drag playhead, timeline stays fixed
  void onPlayheadDrag(double x) {
    final newTime = viewport.state.pixelXToTime(x);
    playback.seekTo(newTime.clamp(0, playback.duration));
  }
}
```

### 6.2 Time Ruler Implementation

```dart
class TimeRulerPainter extends CustomPainter {
  final ViewportState viewport;
  final TimeMicros? inPoint;
  final TimeMicros? outPoint;
  final Rational frameRate;
  final bool showFrames;

  // Tick mark configuration
  static const double majorTickHeight = 16.0;
  static const double mediumTickHeight = 10.0;
  static const double minorTickHeight = 6.0;
  static const double tickTopPadding = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate tick interval based on zoom level
    final tickConfig = _calculateTickConfig(viewport.microsPerPixel);

    // Draw in/out range highlight
    if (inPoint != null && outPoint != null) {
      _drawRangeHighlight(canvas, size, inPoint!, outPoint!);
    }

    // Draw tick marks and labels
    _drawTicks(canvas, size, tickConfig);
  }

  _TickConfig _calculateTickConfig(double microsPerPixel) {
    // Target: tick marks every ~50-100 pixels
    final targetTickPixels = 80.0;
    final targetTickMicros = targetTickPixels * microsPerPixel;

    // Round to nice intervals
    if (targetTickMicros < 100000) {
      // Less than 0.1s - show frame-level ticks
      final frameDuration = framesToTime(1, frameRate);
      final framesPerTick = (targetTickMicros / frameDuration).round().clamp(1, 30);
      return _TickConfig(
        majorInterval: frameDuration * framesPerTick * 10,
        mediumInterval: frameDuration * framesPerTick * 5,
        minorInterval: frameDuration * framesPerTick,
        formatLabel: _formatFrameLabel,
      );
    } else if (targetTickMicros < 1000000) {
      // Less than 1s - show 0.1s ticks
      return _TickConfig(
        majorInterval: 1000000, // 1 second
        mediumInterval: 500000, // 0.5 seconds
        minorInterval: 100000, // 0.1 seconds
        formatLabel: _formatSecondsLabel,
      );
    } else if (targetTickMicros < 10000000) {
      // Less than 10s - show 1s ticks
      return _TickConfig(
        majorInterval: 10000000, // 10 seconds
        mediumInterval: 5000000, // 5 seconds
        minorInterval: 1000000, // 1 second
        formatLabel: _formatSecondsLabel,
      );
    } else if (targetTickMicros < 60000000) {
      // Less than 1m - show 10s ticks
      return _TickConfig(
        majorInterval: 60000000, // 1 minute
        mediumInterval: 30000000, // 30 seconds
        minorInterval: 10000000, // 10 seconds
        formatLabel: _formatMinutesLabel,
      );
    } else {
      // Show 1m ticks
      return _TickConfig(
        majorInterval: 300000000, // 5 minutes
        mediumInterval: 60000000, // 1 minute
        minorInterval: 30000000, // 30 seconds
        formatLabel: _formatMinutesLabel,
      );
    }
  }

  void _drawTicks(Canvas canvas, Size size, _TickConfig config) {
    final startTime = viewport.scrollPosition -
        (100 * viewport.microsPerPixel).round();
    final endTime = viewport.scrollPosition +
        ((viewport.viewportWidth + 100) * viewport.microsPerPixel).round();

    // Align to tick interval
    final firstMajorTick = (startTime ~/ config.majorInterval) * config.majorInterval;

    // Draw minor ticks
    final minorPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0;

    for (var t = firstMajorTick; t < endTime; t += config.minorInterval) {
      if (t % config.mediumInterval == 0) continue; // Skip if medium/major
      final x = viewport.timeToPixelX(t);
      canvas.drawLine(
        Offset(x, size.height - minorTickHeight),
        Offset(x, size.height),
        minorPaint,
      );
    }

    // Draw medium ticks
    final mediumPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0;

    for (var t = firstMajorTick; t < endTime; t += config.mediumInterval) {
      if (t % config.majorInterval == 0) continue; // Skip if major
      final x = viewport.timeToPixelX(t);
      canvas.drawLine(
        Offset(x, size.height - mediumTickHeight),
        Offset(x, size.height),
        mediumPaint,
      );
    }

    // Draw major ticks with labels
    final majorPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.5;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var t = firstMajorTick; t < endTime; t += config.majorInterval) {
      final x = viewport.timeToPixelX(t);

      // Draw tick
      canvas.drawLine(
        Offset(x, size.height - majorTickHeight),
        Offset(x, size.height),
        majorPaint,
      );

      // Draw label
      final label = config.formatLabel(t);
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, tickTopPadding),
      );
    }
  }

  void _drawRangeHighlight(Canvas canvas, Size size, TimeMicros inPoint, TimeMicros outPoint) {
    final leftX = viewport.timeToPixelX(inPoint);
    final rightX = viewport.timeToPixelX(outPoint);

    // Highlight color
    canvas.drawRect(
      Rect.fromLTWH(leftX, 0, rightX - leftX, size.height),
      Paint()..color = Colors.blue.withOpacity(0.2),
    );

    // In/Out markers
    final markerPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(leftX, 0),
      Offset(leftX, size.height),
      markerPaint,
    );
    canvas.drawLine(
      Offset(rightX, 0),
      Offset(rightX, size.height),
      markerPaint,
    );

    // Bracket indicators
    final bracketPath = Path()
      ..moveTo(leftX + 6, 2)
      ..lineTo(leftX, 2)
      ..lineTo(leftX, size.height - 2)
      ..lineTo(leftX + 6, size.height - 2);

    canvas.drawPath(bracketPath, markerPaint..style = PaintingStyle.stroke);

    final bracketPath2 = Path()
      ..moveTo(rightX - 6, 2)
      ..lineTo(rightX, 2)
      ..lineTo(rightX, size.height - 2)
      ..lineTo(rightX - 6, size.height - 2);

    canvas.drawPath(bracketPath2, markerPaint);
  }

  String _formatFrameLabel(TimeMicros time) {
    final frames = timeToFrames(time, frameRate);
    final fps = frameRate.toDouble().round();
    final frameInSecond = frames % fps;
    final totalSeconds = frames ~/ fps;
    final seconds = totalSeconds % 60;
    final minutes = totalSeconds ~/ 60;

    if (showFrames) {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${frameInSecond.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _formatSecondsLabel(TimeMicros time) {
    final totalSeconds = time ~/ 1000000;
    final seconds = totalSeconds % 60;
    final minutes = totalSeconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatMinutesLabel(TimeMicros time) {
    final totalMinutes = time ~/ 60000000;
    final minutes = totalMinutes % 60;
    final hours = totalMinutes ~/ 60;
    final seconds = (time ~/ 1000000) % 60;

    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(TimeRulerPainter oldDelegate) {
    return viewport != oldDelegate.viewport ||
           inPoint != oldDelegate.inPoint ||
           outPoint != oldDelegate.outPoint ||
           showFrames != oldDelegate.showFrames;
  }
}
```

### 6.3 Playhead Painter

```dart
class PlayheadPainter extends CustomPainter {
  final TimeMicros time;
  final ViewportState viewport;
  final bool isFixed; // Fixed-center mode

  @override
  void paint(Canvas canvas, Size size) {
    final x = isFixed
        ? viewport.viewportWidth / 2
        : viewport.timeToPixelX(time);

    // Skip if outside viewport
    if (x < -10 || x > viewport.viewportWidth + 10) return;

    // Draw playhead line
    final linePaint = Paint()
      ..color = const Color(0xFFFF3B30) // iOS red
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      linePaint,
    );

    // Draw playhead handle (top triangle)
    final handlePath = Path()
      ..moveTo(x - 8, 0)
      ..lineTo(x + 8, 0)
      ..lineTo(x, 12)
      ..close();

    canvas.drawPath(
      handlePath,
      Paint()..color = const Color(0xFFFF3B30),
    );

    // Draw subtle shadow
    canvas.drawPath(
      handlePath,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(PlayheadPainter oldDelegate) {
    return time != oldDelegate.time ||
           viewport != oldDelegate.viewport ||
           isFixed != oldDelegate.isFixed;
  }
}
```

### 6.4 Navigation Buttons

```dart
class TimelineNavigationBar extends StatelessWidget {
  final TimelineViewController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Jump to start
          _NavButton(
            icon: CupertinoIcons.backward_end_fill,
            onTap: () {
              controller.playback.seekTo(0);
              HapticFeedback.lightImpact();
            },
          ),

          // Previous edit point
          _NavButton(
            icon: CupertinoIcons.chevron_left_2,
            onTap: () {
              final prevEdit = controller.data.findPreviousEditPoint(
                controller.playback.currentTime
              );
              if (prevEdit != null) {
                controller.playback.seekTo(prevEdit);
                HapticFeedback.selectionClick();
              }
            },
          ),

          // Previous frame
          _NavButton(
            icon: CupertinoIcons.chevron_left,
            onTap: () {
              final frameStep = framesToTime(1, controller.data.frameRate);
              controller.playback.seekTo(
                (controller.playback.currentTime - frameStep).clamp(0, controller.playback.duration)
              );
              HapticFeedback.selectionClick();
            },
            onLongPress: () => _startFrameStep(-1),
            onLongPressEnd: () => _stopFrameStep(),
          ),

          const SizedBox(width: 16),

          // Play/Pause
          _PlayButton(controller: controller),

          const SizedBox(width: 16),

          // Next frame
          _NavButton(
            icon: CupertinoIcons.chevron_right,
            onTap: () {
              final frameStep = framesToTime(1, controller.data.frameRate);
              controller.playback.seekTo(
                (controller.playback.currentTime + frameStep).clamp(0, controller.playback.duration)
              );
              HapticFeedback.selectionClick();
            },
            onLongPress: () => _startFrameStep(1),
            onLongPressEnd: () => _stopFrameStep(),
          ),

          // Next edit point
          _NavButton(
            icon: CupertinoIcons.chevron_right_2,
            onTap: () {
              final nextEdit = controller.data.findNextEditPoint(
                controller.playback.currentTime
              );
              if (nextEdit != null) {
                controller.playback.seekTo(nextEdit);
                HapticFeedback.selectionClick();
              }
            },
          ),

          // Jump to end
          _NavButton(
            icon: CupertinoIcons.forward_end_fill,
            onTap: () {
              controller.playback.seekTo(controller.playback.duration);
              HapticFeedback.lightImpact();
            },
          ),
        ],
      ),
    );
  }
}

/// Helper class for play/pause button
class _PlayButton extends StatelessWidget {
  final TimelineViewController controller;

  const _PlayButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.playback,
      builder: (context, _) {
        final isPlaying = controller.playback.isPlaying;

        return GestureDetector(
          onTap: () {
            if (isPlaying) {
              controller.playback.pause();
            } else {
              controller.playback.play();
            }
            HapticFeedback.lightImpact();
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: CupertinoColors.systemBlue,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              color: CupertinoColors.white,
              size: 28,
            ),
          ),
        );
      },
    );
  }
}

/// Navigation button helper
class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onLongPressEnd;

  const _NavButton({
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: onLongPress != null
          ? (_) => onLongPress!()
          : null,
      onLongPressEnd: onLongPressEnd != null
          ? (_) => onLongPressEnd!()
          : null,
      child: Container(
        width: 44,
        height: 44,
        child: Icon(
          icon,
          color: CupertinoColors.label,
          size: 22,
        ),
      ),
    );
  }
}
```

---

## 7. Clip Representation & Interaction

### 7.1 Clip Visual Design System

```dart
/// Visual configuration for different clip types
class ClipVisualConfig {
  final Color baseColor;
  final bool showThumbnails;
  final bool showWaveform;
  final IconData typeIcon;
  final double minDisplayWidth;

  static const video = ClipVisualConfig(
    baseColor: Color(0xFF5856D6), // Purple
    showThumbnails: true,
    showWaveform: false,
    typeIcon: CupertinoIcons.video_camera_solid,
    minDisplayWidth: 20,
  );

  static const audio = ClipVisualConfig(
    baseColor: Color(0xFF34C759), // Green
    showThumbnails: false,
    showWaveform: true,
    typeIcon: CupertinoIcons.waveform,
    minDisplayWidth: 10,
  );

  static const image = ClipVisualConfig(
    baseColor: Color(0xFFFF9500), // Orange
    showThumbnails: true,
    showWaveform: false,
    typeIcon: CupertinoIcons.photo_fill,
    minDisplayWidth: 20,
  );

  static const text = ClipVisualConfig(
    baseColor: Color(0xFFFF2D55), // Pink
    showThumbnails: false,
    showWaveform: false,
    typeIcon: CupertinoIcons.textformat,
    minDisplayWidth: 30,
  );

  static const effect = ClipVisualConfig(
    baseColor: Color(0xFF007AFF), // Blue
    showThumbnails: false,
    showWaveform: false,
    typeIcon: CupertinoIcons.sparkles,
    minDisplayWidth: 20,
  );
}
```

### 7.2 Selection System

```dart
class SelectionController extends ChangeNotifier {
  Set<String> _selectedIds = {};
  String? _primaryId;

  /// Single tap selection
  void selectClip(String clipId, {bool addToSelection = false}) {
    if (addToSelection) {
      // Toggle selection
      if (_selectedIds.contains(clipId)) {
        _selectedIds = Set.from(_selectedIds)..remove(clipId);
        if (_primaryId == clipId) {
          _primaryId = _selectedIds.isNotEmpty ? _selectedIds.first : null;
        }
      } else {
        _selectedIds = Set.from(_selectedIds)..add(clipId);
        _primaryId = clipId;
      }
    } else {
      // Single selection
      _selectedIds = {clipId};
      _primaryId = clipId;
    }

    HapticFeedback.selectionClick();
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedIds = {};
    _primaryId = null;
    notifyListeners();
  }

  /// Marquee selection
  void selectInRect(Rect rect, List<TimelineClip> clips, ViewportState viewport) {
    final selected = <String>{};

    for (final clip in clips) {
      final clipRect = _getClipRect(clip, viewport);
      if (rect.overlaps(clipRect)) {
        selected.add(clip.id);
      }
    }

    _selectedIds = selected;
    _primaryId = selected.isNotEmpty ? selected.first : null;

    HapticFeedback.selectionClick();
    notifyListeners();
  }

  /// Select all clips on a track
  void selectAllOnTrack(String trackId, List<TimelineClip> clips) {
    _selectedIds = clips
        .where((c) => c.trackId == trackId)
        .map((c) => c.id)
        .toSet();
    _primaryId = _selectedIds.isNotEmpty ? _selectedIds.first : null;
    notifyListeners();
  }

  /// Select all clips after/before playhead
  void selectDirection(
    TimeMicros playheadTime,
    List<TimelineClip> clips,
    bool forward,
  ) {
    _selectedIds = clips
        .where((c) => forward
            ? c.startTime >= playheadTime
            : c.endTime <= playheadTime)
        .map((c) => c.id)
        .toSet();
    _primaryId = _selectedIds.isNotEmpty ? _selectedIds.first : null;
    notifyListeners();
  }
}
```

### 7.3 Drag State Models

```dart
/// State during clip drag operation
@immutable
class DragState {
  final List<TimelineClip> clips;
  final String primaryClipId;
  final Map<String, TimeMicros> originalPositions;
  final TimeMicros touchOffsetMicros;
  final String currentTrackId;

  const DragState({
    required this.clips,
    required this.primaryClipId,
    required this.originalPositions,
    required this.touchOffsetMicros,
    required this.currentTrackId,
  });
}

/// Preview of drag result
@immutable
class DragPreview {
  final List<ClipPreview> clips;
  final List<SnapGuide> snapGuides;
  final bool isValid;

  const DragPreview({
    required this.clips,
    required this.snapGuides,
    required this.isValid,
  });
}

/// Preview of single clip during drag
@immutable
class ClipPreview {
  final TimelineClip originalClip;
  final TimeMicros previewStartTime;
  final String previewTrackId;

  const ClipPreview({
    required this.originalClip,
    required this.previewStartTime,
    required this.previewTrackId,
  });
}

/// Clip move operation
@immutable
class ClipMove {
  final String clipId;
  final TimeMicros newStartTime;
  final String newTrackId;

  const ClipMove({
    required this.clipId,
    required this.newStartTime,
    required this.newTrackId,
  });
}
```

### 7.4 Clip Drag & Drop

```dart
class ClipDragController {
  final TimelineDataManager data;
  final ViewportState viewport;
  final SelectionController selection;
  final SnapController snap;

  /// Drag state
  DragState? _dragState;

  /// Start dragging selected clips
  void startDrag(Offset globalPosition, String primaryClipId) {
    final selectedClips = selection.selectedIds
        .map((id) => data.getClip(id))
        .whereType<TimelineClip>()
        .toList();

    if (selectedClips.isEmpty) return;

    // Calculate offset from touch to clip start
    final primaryClip = data.getClip(primaryClipId)!;
    final touchTime = viewport.pixelXToTime(globalPosition.dx);
    final offsetFromStart = touchTime - primaryClip.startTime;

    _dragState = DragState(
      clips: selectedClips,
      primaryClipId: primaryClipId,
      originalPositions: Map.fromEntries(
        selectedClips.map((c) => MapEntry(c.id, c.startTime))
      ),
      touchOffsetMicros: offsetFromStart,
      currentTrackId: primaryClip.trackId,
    );

    HapticFeedback.mediumImpact();
  }

  /// Update drag position
  DragPreview? updateDrag(Offset globalPosition, double trackY) {
    if (_dragState == null) return null;

    // Calculate new time position
    final touchTime = viewport.pixelXToTime(globalPosition.dx);
    final newStartTime = touchTime - _dragState!.touchOffsetMicros;

    // Calculate delta from original positions
    final timeDelta = newStartTime -
        _dragState!.originalPositions[_dragState!.primaryClipId]!;

    // Determine target track
    final targetTrackId = _getTrackAtY(trackY) ?? _dragState!.currentTrackId;

    // Check for snap points
    final snapResult = snap.findSnapPoints(
      _dragState!.clips,
      timeDelta,
      targetTrackId,
    );

    final finalTimeDelta = snapResult?.adjustedDelta ?? timeDelta;

    // Create preview
    return DragPreview(
      clips: _dragState!.clips.map((c) => ClipPreview(
        originalClip: c,
        previewStartTime: _dragState!.originalPositions[c.id]! + finalTimeDelta,
        previewTrackId: targetTrackId,
      )).toList(),
      snapGuides: snapResult?.guides ?? [],
      isValid: _validateDrop(finalTimeDelta, targetTrackId),
    );
  }

  /// Complete drag
  void endDrag(DragPreview? preview) {
    if (_dragState == null || preview == null) {
      _dragState = null;
      return;
    }

    if (preview.isValid) {
      // Apply the move
      data.moveClips(
        preview.clips.map((p) => ClipMove(
          clipId: p.originalClip.id,
          newStartTime: p.previewStartTime,
          newTrackId: p.previewTrackId,
        )).toList(),
      );

      HapticFeedback.mediumImpact();
    } else {
      // Invalid drop - return to original
      HapticFeedback.notificationError();
    }

    _dragState = null;
  }

  /// Cancel drag
  void cancelDrag() {
    _dragState = null;
    HapticFeedback.lightImpact();
  }

  /// Validate drop position
  bool _validateDrop(TimeMicros timeDelta, String trackId) {
    for (final clip in _dragState!.clips) {
      final newStart = _dragState!.originalPositions[clip.id]! + timeDelta;
      final newEnd = newStart + clip.duration;

      // Check timeline bounds
      if (newStart < 0) return false;

      // Check for collisions with other clips
      final collisions = data.queryRange(newStart, newEnd, trackId: trackId);
      for (final other in collisions) {
        if (!_dragState!.clips.any((c) => c.id == other.id)) {
          return false; // Collision with non-dragged clip
        }
      }
    }
    return true;
  }
}
```

### 7.4 Copy/Paste System

```dart
class ClipboardController {
  List<TimelineClip>? _copiedClips;
  TimeMicros? _copyReferenceTime;

  /// Copy selected clips
  void copy(List<TimelineClip> clips, TimeMicros referenceTime) {
    if (clips.isEmpty) return;

    // Store copies with relative times
    _copiedClips = clips.map((c) => c.copyWith(
      id: const Uuid().v4(), // New ID for paste
    )).toList();
    _copyReferenceTime = referenceTime;

    HapticFeedback.lightImpact();
  }

  /// Cut selected clips
  void cut(List<TimelineClip> clips, TimeMicros referenceTime, TimelineDataManager data) {
    copy(clips, referenceTime);
    data.deleteClips(clips.map((c) => c.id).toList(), ripple: false);
  }

  /// Paste at playhead
  List<TimelineClip>? paste(TimeMicros pasteTime, TimelineDataManager data) {
    if (_copiedClips == null || _copyReferenceTime == null) return null;

    // Calculate time offset
    final earliestClip = _copiedClips!.reduce(
      (a, b) => a.startTime < b.startTime ? a : b
    );
    final timeOffset = pasteTime - earliestClip.startTime;

    // Create new clips with adjusted times
    final pastedClips = _copiedClips!.map((c) => c.copyWith(
      id: const Uuid().v4(),
      startTime: c.startTime + timeOffset,
    )).toList();

    // Add to timeline
    for (final clip in pastedClips) {
      data.addClip(clip);
    }

    HapticFeedback.mediumImpact();
    return pastedClips;
  }

  /// Check if clipboard has content
  bool get hasContent => _copiedClips != null && _copiedClips!.isNotEmpty;
}
```

---

## 8. Trimming & Editing

### 8.1 Trim Handle Detection

```dart
class TrimHitTester {
  static const double handleWidth = 20.0; // Touch target width
  static const double handleExtension = 10.0; // Extra tap area beyond clip edge

  /// Test if position hits a trim handle
  TrimHitResult? hitTest(
    Offset position,
    List<TimelineClip> clips,
    ViewportState viewport,
    SelectionState selection,
  ) {
    for (final clip in clips) {
      final clipRect = _getClipRect(clip, viewport);

      // Only test selected clips (or allow trim-to-select)
      final isSelected = selection.isSelected(clip.id);

      // Left handle zone
      final leftZone = Rect.fromLTWH(
        clipRect.left - handleExtension,
        clipRect.top,
        handleWidth + handleExtension,
        clipRect.height,
      );

      if (leftZone.contains(position)) {
        return TrimHitResult(
          clipId: clip.id,
          edge: TrimEdge.left,
          wasSelected: isSelected,
        );
      }

      // Right handle zone
      final rightZone = Rect.fromLTWH(
        clipRect.right - handleWidth,
        clipRect.top,
        handleWidth + handleExtension,
        clipRect.height,
      );

      if (rightZone.contains(position)) {
        return TrimHitResult(
          clipId: clip.id,
          edge: TrimEdge.right,
          wasSelected: isSelected,
        );
      }
    }

    return null;
  }
}

enum TrimEdge { left, right }

class TrimHitResult {
  final String clipId;
  final TrimEdge edge;
  final bool wasSelected;
}
```

### 8.2 Trim State Models

```dart
/// State during trim operation
@immutable
class TrimState {
  final TimelineClip clip;
  final TrimEdge edge;
  final TimeMicros originalStartTime;
  final TimeMicros originalDuration;
  final TimeMicros originalSourceIn;
  final TimeMicros originalSourceOut;

  const TrimState({
    required this.clip,
    required this.edge,
    required this.originalStartTime,
    required this.originalDuration,
    required this.originalSourceIn,
    required this.originalSourceOut,
  });
}

/// Preview of trim result
@immutable
class TrimPreview {
  final String clipId;
  final TimeMicros newStartTime;
  final TimeMicros newDuration;
  final TimeMicros newSourceIn;
  final TimeMicros newSourceOut;
  final SnapGuide? snapGuide;
  final TimeMicros trimmedDelta;
  final List<RipplePreview>? rippleClips;

  const TrimPreview({
    required this.clipId,
    required this.newStartTime,
    required this.newDuration,
    required this.newSourceIn,
    required this.newSourceOut,
    this.snapGuide,
    required this.trimmedDelta,
    this.rippleClips,
  });

  static TrimPreview empty() => const TrimPreview(
    clipId: '',
    newStartTime: 0,
    newDuration: 0,
    newSourceIn: 0,
    newSourceOut: 0,
    trimmedDelta: 0,
  );

  TrimPreview copyWith({List<RipplePreview>? rippleClips}) {
    return TrimPreview(
      clipId: clipId,
      newStartTime: newStartTime,
      newDuration: newDuration,
      newSourceIn: newSourceIn,
      newSourceOut: newSourceOut,
      snapGuide: snapGuide,
      trimmedDelta: trimmedDelta,
      rippleClips: rippleClips ?? this.rippleClips,
    );
  }
}

/// Ripple effect on other clips
@immutable
class RipplePreview {
  final String clipId;
  final TimeMicros newStartTime;

  const RipplePreview({
    required this.clipId,
    required this.newStartTime,
  });
}

/// Trim snap result
@immutable
class TrimSnapResult {
  final TimeMicros snapTime;
  final SnapGuide guide;

  const TrimSnapResult({
    required this.snapTime,
    required this.guide,
  });
}
```

### 8.3 Trim Controller

```dart
class TrimController {
  final TimelineDataManager data;
  final ViewportState viewport;
  final SnapController snap;

  /// Current trim state
  TrimState? _trimState;

  /// Start trim operation
  void startTrim(String clipId, TrimEdge edge) {
    final clip = data.getClip(clipId);
    if (clip == null) return;

    _trimState = TrimState(
      clip: clip,
      edge: edge,
      originalStartTime: clip.startTime,
      originalDuration: clip.duration,
      originalSourceIn: clip.sourceIn,
      originalSourceOut: clip.sourceOut,
    );

    HapticFeedback.lightImpact();
  }

  /// Update trim position
  TrimPreview updateTrim(double deltaX) {
    if (_trimState == null) {
      return TrimPreview.empty();
    }

    final timeDelta = (deltaX * viewport.microsPerPixel).round();

    if (_trimState!.edge == TrimEdge.left) {
      return _updateLeftTrim(timeDelta);
    } else {
      return _updateRightTrim(timeDelta);
    }
  }

  TrimPreview _updateLeftTrim(TimeMicros timeDelta) {
    final state = _trimState!;

    // Calculate new start time
    var newStartTime = state.originalStartTime + timeDelta;
    var newSourceIn = state.originalSourceIn + timeDelta;
    var newDuration = state.originalDuration - timeDelta;

    // Clamp to valid range
    // 1. Can't trim past source start
    if (newSourceIn < 0) {
      final adjustment = -newSourceIn;
      newSourceIn = 0;
      newStartTime = state.originalStartTime + state.originalSourceIn;
      newDuration = state.originalDuration - state.originalSourceIn;
    }

    // 2. Can't trim to less than minimum duration
    const minDuration = 33333; // ~1 frame at 30fps
    if (newDuration < minDuration) {
      newDuration = minDuration;
      newStartTime = state.originalStartTime + state.originalDuration - minDuration;
      newSourceIn = state.originalSourceOut - minDuration;
    }

    // 3. Can't trim into negative timeline
    if (newStartTime < 0) {
      final adjustment = -newStartTime;
      newStartTime = 0;
      newSourceIn += adjustment;
      newDuration -= adjustment;
    }

    // Check for snap points
    final snapResult = snap.findTrimSnapPoints(
      newStartTime,
      state.clip.trackId,
      isLeftEdge: true,
    );

    if (snapResult != null) {
      final snapDelta = snapResult.snapTime - newStartTime;
      newStartTime = snapResult.snapTime;
      newSourceIn += snapDelta;
      newDuration -= snapDelta;
    }

    return TrimPreview(
      clipId: state.clip.id,
      newStartTime: newStartTime,
      newDuration: newDuration,
      newSourceIn: newSourceIn,
      newSourceOut: state.originalSourceOut,
      snapGuide: snapResult?.guide,
      trimmedDelta: newStartTime - state.originalStartTime,
    );
  }

  TrimPreview _updateRightTrim(TimeMicros timeDelta) {
    final state = _trimState!;

    // Calculate new end time
    var newDuration = state.originalDuration + timeDelta;
    var newSourceOut = state.originalSourceOut + timeDelta;

    // Get source duration for this clip
    final sourceDuration = data.getSourceDuration(state.clip.mediaAssetId);

    // Clamp to valid range
    // 1. Can't trim past source end
    if (newSourceOut > sourceDuration) {
      newSourceOut = sourceDuration;
      newDuration = newSourceOut - state.originalSourceIn;
    }

    // 2. Can't trim to less than minimum duration
    const minDuration = 33333;
    if (newDuration < minDuration) {
      newDuration = minDuration;
      newSourceOut = state.originalSourceIn + minDuration;
    }

    // Check for snap points
    final newEndTime = state.originalStartTime + newDuration;
    final snapResult = snap.findTrimSnapPoints(
      newEndTime,
      state.clip.trackId,
      isLeftEdge: false,
    );

    if (snapResult != null) {
      final snapDelta = snapResult.snapTime - newEndTime;
      newDuration += snapDelta;
      newSourceOut += snapDelta;
    }

    return TrimPreview(
      clipId: state.clip.id,
      newStartTime: state.originalStartTime,
      newDuration: newDuration,
      newSourceIn: state.originalSourceIn,
      newSourceOut: newSourceOut,
      snapGuide: snapResult?.guide,
      trimmedDelta: newDuration - state.originalDuration,
    );
  }

  /// Complete trim operation
  void endTrim(TrimPreview preview) {
    if (_trimState == null) return;

    // Apply the trim
    data.trimClip(
      preview.clipId,
      newStartTime: preview.newStartTime,
      newDuration: preview.newDuration,
      newSourceIn: preview.newSourceIn,
      newSourceOut: preview.newSourceOut,
    );

    _trimState = null;
    HapticFeedback.mediumImpact();
  }

  /// Cancel trim
  void cancelTrim() {
    _trimState = null;
    HapticFeedback.lightImpact();
  }
}
```

### 8.4 Ripple & Roll Trim

```dart
/// Roll edit state
@immutable
class RollState {
  final TimelineClip leftClip;
  final TimelineClip rightClip;
  final TimeMicros originalEditPoint;

  const RollState({
    required this.leftClip,
    required this.rightClip,
    required this.originalEditPoint,
  });
}

/// Roll preview result
@immutable
class RollPreview {
  final String leftClipId;
  final String rightClipId;
  final TimeMicros editPoint;
  final TimeMicros leftNewDuration;
  final TimeMicros rightNewStartTime;
  final TimeMicros rightNewDuration;

  const RollPreview({
    required this.leftClipId,
    required this.rightClipId,
    required this.editPoint,
    required this.leftNewDuration,
    required this.rightNewStartTime,
    required this.rightNewDuration,
  });

  static RollPreview empty() => const RollPreview(
    leftClipId: '',
    rightClipId: '',
    editPoint: 0,
    leftNewDuration: 0,
    rightNewStartTime: 0,
    rightNewDuration: 0,
  );
}

class RippleTrimController extends TrimController {
  @override
  TrimPreview _updateLeftTrim(TimeMicros timeDelta) {
    final preview = super._updateLeftTrim(timeDelta);

    // Calculate ripple effect on subsequent clips
    final affectedClips = data.queryAfter(
      _trimState!.originalStartTime,
      trackId: _trimState!.clip.trackId,
    );

    final rippleDelta = preview.trimmedDelta;

    return preview.copyWith(
      rippleClips: affectedClips.map((c) => RipplePreview(
        clipId: c.id,
        newStartTime: c.startTime + rippleDelta,
      )).toList(),
    );
  }

  @override
  void endTrim(TrimPreview preview) {
    super.endTrim(preview);

    // Apply ripple to subsequent clips
    if (preview.rippleClips != null) {
      for (final ripple in preview.rippleClips!) {
        data.moveClip(ripple.clipId, ripple.newStartTime);
      }
    }
  }
}

class RollTrimController {
  final TimelineDataManager data;
  final ViewportState viewport;

  RollState? _rollState;

  /// Start roll edit (adjust edit point between two clips)
  void startRoll(String leftClipId, String rightClipId) {
    final leftClip = data.getClip(leftClipId);
    final rightClip = data.getClip(rightClipId);

    if (leftClip == null || rightClip == null) return;

    _rollState = RollState(
      leftClip: leftClip,
      rightClip: rightClip,
      originalEditPoint: leftClip.endTime,
    );

    HapticFeedback.lightImpact();
  }

  /// Update roll position
  RollPreview updateRoll(double deltaX) {
    if (_rollState == null) return RollPreview.empty();

    final timeDelta = (deltaX * viewport.microsPerPixel).round();
    var newEditPoint = _rollState!.originalEditPoint + timeDelta;

    // Clamp to valid range
    final leftMin = _rollState!.leftClip.startTime + 33333;
    final rightMax = _rollState!.rightClip.endTime - 33333;
    newEditPoint = newEditPoint.clamp(leftMin, rightMax);

    // Calculate new clip bounds
    final leftNewDuration = newEditPoint - _rollState!.leftClip.startTime;
    final rightNewStartTime = newEditPoint;
    final rightNewDuration = _rollState!.rightClip.endTime - newEditPoint;

    return RollPreview(
      leftClipId: _rollState!.leftClip.id,
      rightClipId: _rollState!.rightClip.id,
      editPoint: newEditPoint,
      leftNewDuration: leftNewDuration,
      rightNewStartTime: rightNewStartTime,
      rightNewDuration: rightNewDuration,
    );
  }

  /// Complete roll edit
  void endRoll(RollPreview preview) {
    if (_rollState == null) return;

    data.rollEdit(
      leftClipId: preview.leftClipId,
      rightClipId: preview.rightClipId,
      newEditPoint: preview.editPoint,
    );

    _rollState = null;
    HapticFeedback.mediumImpact();
  }
}
```

### 8.5 Split State Models

```dart
/// Result of split operation
@immutable
class SplitResult {
  final List<SplitClipResult> clips;

  const SplitResult({required this.clips});
}

/// Individual clip split result
@immutable
class SplitClipResult {
  final String originalClipId;
  final TimelineClip leftClip;
  final TimelineClip rightClip;

  const SplitClipResult({
    required this.originalClipId,
    required this.leftClip,
    required this.rightClip,
  });
}
```

### 8.6 Split Operation

```dart
class SplitController {
  final TimelineDataManager data;

  /// Split clip at playhead
  SplitResult? splitAtPlayhead(TimeMicros playheadTime, {String? clipId}) {
    // Find clip(s) at playhead
    final clips = clipId != null
        ? [data.getClip(clipId)].whereType<TimelineClip>().toList()
        : data.queryTime(playheadTime);

    if (clips.isEmpty) return null;

    final results = <SplitClipResult>[];

    for (final clip in clips) {
      // Check if playhead is within clip (not at edges)
      if (playheadTime <= clip.startTime || playheadTime >= clip.endTime) {
        continue;
      }

      // Calculate split point in source
      final sourceTime = clip.timelineToSource(playheadTime);

      // Create left clip
      final leftClip = clip.copyWith(
        id: const Uuid().v4(),
        sourceOut: sourceTime,
        // Duration is auto-calculated from source range
      );

      // Create right clip
      final rightClip = clip.copyWith(
        id: const Uuid().v4(),
        startTime: playheadTime,
        sourceIn: sourceTime,
      );

      results.add(SplitClipResult(
        originalClipId: clip.id,
        leftClip: leftClip,
        rightClip: rightClip,
      ));
    }

    if (results.isEmpty) return null;

    // Apply splits
    for (final result in results) {
      data.splitClip(
        result.originalClipId,
        result.leftClip,
        result.rightClip,
      );
    }

    HapticFeedback.mediumImpact();

    return SplitResult(clips: results);
  }

  /// Split all tracks at playhead
  SplitResult? splitAllTracks(TimeMicros playheadTime) {
    final allClips = data.queryTime(playheadTime);

    final results = <SplitClipResult>[];
    for (final clip in allClips) {
      final result = splitAtPlayhead(playheadTime, clipId: clip.id);
      if (result != null) {
        results.addAll(result.clips);
      }
    }

    return results.isNotEmpty ? SplitResult(clips: results) : null;
  }
}
```

### 8.7 Slip & Slide State Models

```dart
/// Slip state (move content within clip boundaries)
@immutable
class SlipState {
  final TimelineClip clip;
  final TimeMicros originalSourceIn;
  final TimeMicros originalSourceOut;

  const SlipState({
    required this.clip,
    required this.originalSourceIn,
    required this.originalSourceOut,
  });
}

/// Slip preview result
@immutable
class SlipPreview {
  final String clipId;
  final TimeMicros newSourceIn;
  final TimeMicros newSourceOut;
  final TimeMicros startTime;
  final TimeMicros duration;

  const SlipPreview({
    required this.clipId,
    required this.newSourceIn,
    required this.newSourceOut,
    required this.startTime,
    required this.duration,
  });

  static SlipPreview empty() => const SlipPreview(
    clipId: '',
    newSourceIn: 0,
    newSourceOut: 0,
    startTime: 0,
    duration: 0,
  );
}

/// Slide state (move clip position, adjacent clips adjust)
@immutable
class SlideState {
  final TimelineClip clip;
  final TimelineClip? leftClip;
  final TimelineClip? rightClip;
  final TimeMicros originalStartTime;

  const SlideState({
    required this.clip,
    this.leftClip,
    this.rightClip,
    required this.originalStartTime,
  });
}

/// Slide preview result
@immutable
class SlidePreview {
  final String clipId;
  final TimeMicros newStartTime;
  final TimeMicros? leftClipNewDuration;
  final TimeMicros? rightClipNewStartTime;

  const SlidePreview({
    required this.clipId,
    required this.newStartTime,
    this.leftClipNewDuration,
    this.rightClipNewStartTime,
  });

  static SlidePreview empty() => const SlidePreview(
    clipId: '',
    newStartTime: 0,
  );
}
```

### 8.8 Slip & Slide Controllers

```dart
class SlipController {
  final TimelineDataManager data;
  final ViewportState viewport;

  SlipState? _slipState;

  /// Start slip (move content within clip boundaries)
  void startSlip(String clipId) {
    final clip = data.getClip(clipId);
    if (clip == null) return;

    _slipState = SlipState(
      clip: clip,
      originalSourceIn: clip.sourceIn,
      originalSourceOut: clip.sourceOut,
    );

    HapticFeedback.lightImpact();
  }

  /// Update slip position
  SlipPreview updateSlip(double deltaX) {
    if (_slipState == null) return SlipPreview.empty();

    final timeDelta = (deltaX * viewport.microsPerPixel).round();

    var newSourceIn = _slipState!.originalSourceIn + timeDelta;
    var newSourceOut = _slipState!.originalSourceOut + timeDelta;

    // Get source bounds
    final sourceDuration = data.getSourceDuration(_slipState!.clip.mediaAssetId);

    // Clamp to source bounds
    if (newSourceIn < 0) {
      final adjustment = -newSourceIn;
      newSourceIn = 0;
      newSourceOut = _slipState!.clip.duration;
    }

    if (newSourceOut > sourceDuration) {
      newSourceOut = sourceDuration;
      newSourceIn = sourceDuration - _slipState!.clip.duration;
    }

    return SlipPreview(
      clipId: _slipState!.clip.id,
      newSourceIn: newSourceIn,
      newSourceOut: newSourceOut,
      // Clip position doesn't change
      startTime: _slipState!.clip.startTime,
      duration: _slipState!.clip.duration,
    );
  }

  void endSlip(SlipPreview preview) {
    if (_slipState == null) return;

    data.slipClip(
      preview.clipId,
      newSourceIn: preview.newSourceIn,
      newSourceOut: preview.newSourceOut,
    );

    _slipState = null;
    HapticFeedback.mediumImpact();
  }
}

class SlideController {
  final TimelineDataManager data;
  final ViewportState viewport;

  SlideState? _slideState;

  /// Start slide (move clip position, adjacent clips adjust)
  void startSlide(String clipId) {
    final clip = data.getClip(clipId);
    if (clip == null) return;

    // Find adjacent clips
    final leftClip = data.findClipBefore(clip.startTime, clip.trackId);
    final rightClip = data.findClipAfter(clip.endTime, clip.trackId);

    _slideState = SlideState(
      clip: clip,
      leftClip: leftClip,
      rightClip: rightClip,
      originalStartTime: clip.startTime,
    );

    HapticFeedback.lightImpact();
  }

  /// Update slide position
  SlidePreview updateSlide(double deltaX) {
    if (_slideState == null) return SlidePreview.empty();

    final timeDelta = (deltaX * viewport.microsPerPixel).round();
    var newStartTime = _slideState!.originalStartTime + timeDelta;

    // Calculate bounds based on adjacent clips
    TimeMicros minStart = 0;
    TimeMicros maxStart = data.totalDuration - _slideState!.clip.duration;

    if (_slideState!.leftClip != null) {
      // Can't slide past where left clip started
      minStart = _slideState!.leftClip!.startTime;
    }

    if (_slideState!.rightClip != null) {
      // Can't slide past where right clip ends
      maxStart = _slideState!.rightClip!.endTime - _slideState!.clip.duration;
    }

    newStartTime = newStartTime.clamp(minStart, maxStart);

    return SlidePreview(
      clipId: _slideState!.clip.id,
      newStartTime: newStartTime,
      leftClipNewDuration: _slideState!.leftClip != null
          ? newStartTime - _slideState!.leftClip!.startTime
          : null,
      rightClipNewStartTime: _slideState!.rightClip != null
          ? newStartTime + _slideState!.clip.duration
          : null,
    );
  }

  void endSlide(SlidePreview preview) {
    if (_slideState == null) return;

    data.slideClip(
      preview.clipId,
      newStartTime: preview.newStartTime,
      leftClipId: _slideState!.leftClip?.id,
      leftClipNewDuration: preview.leftClipNewDuration,
      rightClipId: _slideState!.rightClip?.id,
      rightClipNewStartTime: preview.rightClipNewStartTime,
    );

    _slideState = null;
    HapticFeedback.mediumImpact();
  }
}
```

---

## 9. Snapping & Alignment

### 9.1 Snap Helper Types

```dart
/// Internal edge representation for snap calculations
class _Edge {
  final TimeMicros time;
  final bool isStart;
  final String clipId;

  const _Edge({
    required this.time,
    required this.isStart,
    required this.clipId,
  });
}

/// Internal snap target representation
class _SnapTarget {
  final TimeMicros time;
  final SnapTargetType type;
  final int priority; // Lower = higher priority

  const _SnapTarget({
    required this.time,
    required this.type,
    required this.priority,
  });
}

/// Internal snap match result
class _SnapMatch {
  final _Edge edge;
  final _SnapTarget target;
  final TimeMicros distance;

  const _SnapMatch({
    required this.edge,
    required this.target,
    required this.distance,
  });
}

/// Result of snap calculation
@immutable
class SnapResult {
  final TimeMicros adjustedDelta;
  final List<SnapGuide> guides;
  final bool snappedToPlayhead;

  const SnapResult({
    required this.adjustedDelta,
    required this.guides,
    required this.snappedToPlayhead,
  });
}
```

### 9.2 Snap Controller

```dart
class SnapController {
  final TimelineDataManager data;
  final PlaybackController playback;
  final SelectionState selection;

  /// Snap enabled state
  bool isEnabled = true;

  /// Snap threshold in pixels
  static const double snapThresholdPixels = 10.0;

  /// Find snap points for clip drag
  SnapResult? findSnapPoints(
    List<TimelineClip> draggedClips,
    TimeMicros timeDelta,
    String targetTrackId,
    ViewportState viewport,
  ) {
    if (!isEnabled) return null;

    final snapThresholdMicros =
        (snapThresholdPixels * viewport.microsPerPixel).round();

    // Collect all edges of dragged clips
    final draggedEdges = <_Edge>[];
    for (final clip in draggedClips) {
      final newStart = clip.startTime + timeDelta;
      final newEnd = newStart + clip.duration;
      draggedEdges.add(_Edge(time: newStart, isStart: true, clipId: clip.id));
      draggedEdges.add(_Edge(time: newEnd, isStart: false, clipId: clip.id));
    }

    // Collect all potential snap targets
    final snapTargets = <_SnapTarget>[];

    // 1. Playhead
    snapTargets.add(_SnapTarget(
      time: playback.currentTime,
      type: SnapTargetType.playhead,
      priority: 1,
    ));

    // 2. Other clip edges (not being dragged)
    for (final clip in data.allClips) {
      if (draggedClips.any((c) => c.id == clip.id)) continue;

      snapTargets.add(_SnapTarget(
        time: clip.startTime,
        type: SnapTargetType.clipEdge,
        priority: 2,
      ));
      snapTargets.add(_SnapTarget(
        time: clip.endTime,
        type: SnapTargetType.clipEdge,
        priority: 2,
      ));
    }

    // 3. Markers
    for (final marker in data.markers) {
      snapTargets.add(_SnapTarget(
        time: marker.time,
        type: SnapTargetType.marker,
        priority: 3,
      ));
    }

    // 4. In/Out points
    if (selection.inPoint != null) {
      snapTargets.add(_SnapTarget(
        time: selection.inPoint!,
        type: SnapTargetType.inOutPoint,
        priority: 2,
      ));
    }
    if (selection.outPoint != null) {
      snapTargets.add(_SnapTarget(
        time: selection.outPoint!,
        type: SnapTargetType.inOutPoint,
        priority: 2,
      ));
    }

    // Find closest snap
    _SnapMatch? bestMatch;

    for (final edge in draggedEdges) {
      for (final target in snapTargets) {
        final distance = (edge.time - target.time).abs();

        if (distance <= snapThresholdMicros) {
          if (bestMatch == null ||
              distance < bestMatch.distance ||
              (distance == bestMatch.distance &&
               target.priority < bestMatch.target.priority)) {
            bestMatch = _SnapMatch(
              edge: edge,
              target: target,
              distance: distance,
            );
          }
        }
      }
    }

    if (bestMatch == null) return null;

    // Calculate adjusted delta to achieve snap
    final snapAdjustment = bestMatch.target.time - bestMatch.edge.time;
    final adjustedDelta = timeDelta + snapAdjustment;

    // Create snap guide for visualization
    final guide = SnapGuide(
      x: viewport.timeToPixelX(bestMatch.target.time),
      type: bestMatch.target.type,
    );

    // Trigger haptic
    HapticFeedback.selectionClick();

    return SnapResult(
      adjustedDelta: adjustedDelta,
      guides: [guide],
      snappedToPlayhead: bestMatch.target.type == SnapTargetType.playhead,
    );
  }

  /// Find snap points for trim operation
  TrimSnapResult? findTrimSnapPoints(
    TimeMicros edgeTime,
    String trackId,
    bool isLeftEdge,
    ViewportState viewport,
  ) {
    if (!isEnabled) return null;

    final snapThresholdMicros =
        (snapThresholdPixels * viewport.microsPerPixel).round();

    // Similar logic to findSnapPoints but for single edge
    final snapTargets = <_SnapTarget>[
      _SnapTarget(time: playback.currentTime, type: SnapTargetType.playhead, priority: 1),
    ];

    // Add other clip edges
    for (final clip in data.allClips) {
      if (clip.trackId != trackId) continue;

      snapTargets.add(_SnapTarget(
        time: clip.startTime,
        type: SnapTargetType.clipEdge,
        priority: 2,
      ));
      snapTargets.add(_SnapTarget(
        time: clip.endTime,
        type: SnapTargetType.clipEdge,
        priority: 2,
      ));
    }

    // Find closest
    for (final target in snapTargets) {
      final distance = (edgeTime - target.time).abs();

      if (distance <= snapThresholdMicros) {
        HapticFeedback.selectionClick();

        return TrimSnapResult(
          snapTime: target.time,
          guide: SnapGuide(
            x: viewport.timeToPixelX(target.time),
            type: target.type,
          ),
        );
      }
    }

    return null;
  }
}

enum SnapTargetType {
  playhead,
  clipEdge,
  marker,
  inOutPoint,
  beatMarker,
  gridLine,
}

class SnapGuide {
  final double x;
  final SnapTargetType type;

  Color get color {
    switch (type) {
      case SnapTargetType.playhead:
        return Colors.red;
      case SnapTargetType.clipEdge:
        return Colors.yellow;
      case SnapTargetType.marker:
        return Colors.blue;
      case SnapTargetType.inOutPoint:
        return Colors.cyan;
      case SnapTargetType.beatMarker:
        return Colors.purple;
      case SnapTargetType.gridLine:
        return Colors.white30;
    }
  }
}
```

### 9.3 Snap Guide Painter

```dart
class SnapGuidesPainter extends CustomPainter {
  final List<SnapGuide> guides;
  final ViewportState viewport;

  @override
  void paint(Canvas canvas, Size size) {
    for (final guide in guides) {
      // Main line
      canvas.drawLine(
        Offset(guide.x, 0),
        Offset(guide.x, size.height),
        Paint()
          ..color = guide.color
          ..strokeWidth = 1.5,
      );

      // Glow effect
      canvas.drawLine(
        Offset(guide.x, 0),
        Offset(guide.x, size.height),
        Paint()
          ..color = guide.color.withOpacity(0.3)
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(SnapGuidesPainter oldDelegate) {
    return guides != oldDelegate.guides;
  }
}
```

---

## 10. Markers & Annotations

### 10.1 Marker Model

```dart
@immutable
class TimelineMarker {
  final String id;
  final TimeMicros time;
  final TimeMicros? duration; // null for point markers
  final String label;
  final String? notes;
  final MarkerType type;
  final Color color;

  bool get isRange => duration != null && duration! > 0;
  TimeMicros get endTime => time + (duration ?? 0);
}

enum MarkerType {
  generic,    // General purpose marker
  chapter,    // Chapter marker for export
  todo,       // Task/review marker
  sync,       // Sync point for multi-cam
  beat,       // Music beat marker
}

extension MarkerTypeExtension on MarkerType {
  Color get defaultColor {
    switch (this) {
      case MarkerType.generic:
        return Colors.blue;
      case MarkerType.chapter:
        return Colors.green;
      case MarkerType.todo:
        return Colors.orange;
      case MarkerType.sync:
        return Colors.purple;
      case MarkerType.beat:
        return Colors.pink;
    }
  }

  IconData get icon {
    switch (this) {
      case MarkerType.generic:
        return CupertinoIcons.bookmark_fill;
      case MarkerType.chapter:
        return CupertinoIcons.list_number;
      case MarkerType.todo:
        return CupertinoIcons.checkmark_circle;
      case MarkerType.sync:
        return CupertinoIcons.arrow_right_arrow_left;
      case MarkerType.beat:
        return CupertinoIcons.music_note;
    }
  }
}
```

### 10.2 Marker Controller

```dart
class MarkerController {
  final TimelineDataManager data;

  /// Add marker at current playhead
  TimelineMarker addMarker({
    required TimeMicros time,
    String? label,
    MarkerType type = MarkerType.generic,
    Color? color,
  }) {
    final marker = TimelineMarker(
      id: const Uuid().v4(),
      time: time,
      label: label ?? 'Marker ${data.markers.length + 1}',
      type: type,
      color: color ?? type.defaultColor,
    );

    data.addMarker(marker);
    HapticFeedback.lightImpact();

    return marker;
  }

  /// Add range marker
  TimelineMarker addRangeMarker({
    required TimeMicros startTime,
    required TimeMicros endTime,
    String? label,
    MarkerType type = MarkerType.generic,
    Color? color,
  }) {
    final marker = TimelineMarker(
      id: const Uuid().v4(),
      time: startTime,
      duration: endTime - startTime,
      label: label ?? 'Range ${data.markers.length + 1}',
      type: type,
      color: color ?? type.defaultColor,
    );

    data.addMarker(marker);
    HapticFeedback.lightImpact();

    return marker;
  }

  /// Delete marker
  void deleteMarker(String markerId) {
    data.deleteMarker(markerId);
    HapticFeedback.lightImpact();
  }

  /// Update marker
  void updateMarker(String markerId, {
    String? label,
    String? notes,
    Color? color,
    TimeMicros? time,
    TimeMicros? duration,
  }) {
    final marker = data.getMarker(markerId);
    if (marker == null) return;

    data.updateMarker(marker.copyWith(
      label: label,
      notes: notes,
      color: color,
      time: time,
      duration: duration,
    ));
  }

  /// Navigate to next marker
  TimeMicros? goToNextMarker(TimeMicros currentTime) {
    final markers = data.markers
        .where((m) => m.time > currentTime)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    if (markers.isEmpty) return null;

    HapticFeedback.selectionClick();
    return markers.first.time;
  }

  /// Navigate to previous marker
  TimeMicros? goToPreviousMarker(TimeMicros currentTime) {
    final markers = data.markers
        .where((m) => m.time < currentTime)
        .toList()
      ..sort((a, b) => b.time.compareTo(a.time));

    if (markers.isEmpty) return null;

    HapticFeedback.selectionClick();
    return markers.first.time;
  }
}
```

### 10.3 Marker Painter

```dart
class MarkersPainter extends CustomPainter {
  final List<TimelineMarker> markers;
  final ViewportState viewport;
  final String? selectedMarkerId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final marker in markers) {
      final x = viewport.timeToPixelX(marker.time);

      // Skip if not visible
      if (x < -20 || x > viewport.viewportWidth + 20) continue;

      if (marker.isRange) {
        _paintRangeMarker(canvas, marker, size);
      } else {
        _paintPointMarker(canvas, marker, size);
      }
    }
  }

  void _paintPointMarker(Canvas canvas, TimelineMarker marker, Size size) {
    final x = viewport.timeToPixelX(marker.time);
    final isSelected = marker.id == selectedMarkerId;

    // Draw vertical line
    final linePaint = Paint()
      ..color = marker.color.withOpacity(isSelected ? 1.0 : 0.6)
      ..strokeWidth = isSelected ? 2.0 : 1.0;

    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      linePaint,
    );

    // Draw marker flag
    final flagPath = Path()
      ..moveTo(x, 0)
      ..lineTo(x + 12, 0)
      ..lineTo(x + 12, 10)
      ..lineTo(x + 6, 14)
      ..lineTo(x, 10)
      ..close();

    canvas.drawPath(
      flagPath,
      Paint()..color = marker.color,
    );

    // Draw icon
    // (Would need to use TextPainter with icon font)
  }

  void _paintRangeMarker(Canvas canvas, TimelineMarker marker, Size size) {
    final startX = viewport.timeToPixelX(marker.time);
    final endX = viewport.timeToPixelX(marker.endTime);

    // Draw range background
    canvas.drawRect(
      Rect.fromLTWH(startX, 0, endX - startX, size.height),
      Paint()..color = marker.color.withOpacity(0.1),
    );

    // Draw start/end lines
    final linePaint = Paint()
      ..color = marker.color.withOpacity(0.8)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), linePaint);
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), linePaint);

    // Draw top bar
    canvas.drawRect(
      Rect.fromLTWH(startX, 0, endX - startX, 4),
      Paint()..color = marker.color,
    );
  }

  @override
  bool shouldRepaint(MarkersPainter oldDelegate) {
    return markers != oldDelegate.markers ||
           viewport != oldDelegate.viewport ||
           selectedMarkerId != oldDelegate.selectedMarkerId;
  }
}
```

---

## 11. Transitions & Effects

### 11.1 Transition Model

```dart
@immutable
class ClipTransition {
  final String id;
  final String leftClipId;
  final String rightClipId;
  final String trackId;
  final TransitionType type;
  final TimeMicros duration;
  final TransitionAlignment alignment;
  final Map<String, dynamic> parameters;
  final TimeMicros editPointTime; // Time where clips meet

  const ClipTransition({
    required this.id,
    required this.leftClipId,
    required this.rightClipId,
    required this.trackId,
    required this.type,
    required this.duration,
    required this.alignment,
    required this.parameters,
    required this.editPointTime,
  });

  /// Calculate transition time range on timeline
  TimeRange get timeRange {
    // Depends on alignment
    switch (alignment) {
      case TransitionAlignment.centerOnCut:
        // Straddles the edit point
        final halfDuration = duration ~/ 2;
        return TimeRange(
          editPointTime - halfDuration,
          editPointTime + halfDuration,
        );
      case TransitionAlignment.startAtCut:
        return TimeRange(editPointTime, editPointTime + duration);
      case TransitionAlignment.endAtCut:
        return TimeRange(editPointTime - duration, editPointTime);
    }
  }
}

enum TransitionType {
  crossDissolve,
  crossfade, // Audio
  dip,
  wipe,
  slide,
  zoom,
  custom,
}

enum TransitionAlignment {
  centerOnCut,
  startAtCut,
  endAtCut,
}
```

### 11.2 Transition Painter

```dart
class TransitionsPainter extends CustomPainter {
  final List<ClipTransition> transitions;
  final ViewportState viewport;
  final String? selectedTransitionId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final transition in transitions) {
      final range = transition.timeRange;
      final startX = viewport.timeToPixelX(range.start);
      final endX = viewport.timeToPixelX(range.end);

      // Skip if not visible
      if (endX < 0 || startX > viewport.viewportWidth) continue;

      final trackTop = _getTrackTop(transition.trackId);
      final trackHeight = _getTrackHeight(transition.trackId);

      final rect = Rect.fromLTWH(
        startX,
        trackTop,
        endX - startX,
        trackHeight,
      );

      _paintTransition(canvas, transition, rect);
    }
  }

  void _paintTransition(Canvas canvas, ClipTransition transition, Rect rect) {
    final isSelected = transition.id == selectedTransitionId;

    // Draw transition icon/representation
    final iconRect = Rect.fromCenter(
      center: rect.center,
      width: 24,
      height: 24,
    );

    // Background circle
    canvas.drawOval(
      iconRect,
      Paint()..color = Colors.black54,
    );

    // Transition type icon
    final icon = _getTransitionIcon(transition.type);
    // Draw icon using TextPainter with icon font

    // Draw resize handles if selected
    if (isSelected) {
      _paintTransitionHandles(canvas, rect);
    }

    // Draw duration indicator
    final durationText = '${(transition.duration / 1000000).toStringAsFixed(1)}s';
    // Draw text above transition
  }

  IconData _getTransitionIcon(TransitionType type) {
    switch (type) {
      case TransitionType.crossDissolve:
        return CupertinoIcons.square_on_square;
      case TransitionType.crossfade:
        return CupertinoIcons.waveform;
      case TransitionType.dip:
        return CupertinoIcons.square_fill;
      case TransitionType.wipe:
        return CupertinoIcons.arrow_right;
      case TransitionType.slide:
        return CupertinoIcons.arrow_right_square;
      case TransitionType.zoom:
        return CupertinoIcons.zoom_in;
      case TransitionType.custom:
        return CupertinoIcons.sparkles;
    }
  }

  @override
  bool shouldRepaint(TransitionsPainter oldDelegate) {
    return transitions != oldDelegate.transitions ||
           viewport != oldDelegate.viewport ||
           selectedTransitionId != oldDelegate.selectedTransitionId;
  }
}
```

### 11.3 Effect Badge Painter

```dart
class EffectBadgePainter {
  /// Paint effect indicator on clip
  static void paintEffectBadge(
    Canvas canvas,
    Rect clipRect,
    int effectCount,
    bool hasColorCorrection,
    bool hasSpeedEffect,
  ) {
    const badgeSize = 16.0;
    const badgeSpacing = 4.0;
    var badgeX = clipRect.right - badgeSize - 4;
    final badgeY = clipRect.top + 4;

    // Effect count badge
    if (effectCount > 0) {
      _paintBadge(
        canvas,
        Offset(badgeX, badgeY),
        badgeSize,
        Colors.blue,
        'Fx',
        count: effectCount > 1 ? effectCount : null,
      );
      badgeX -= badgeSize + badgeSpacing;
    }

    // Color correction badge
    if (hasColorCorrection) {
      _paintBadge(
        canvas,
        Offset(badgeX, badgeY),
        badgeSize,
        Colors.orange,
        '🎨',
      );
      badgeX -= badgeSize + badgeSpacing;
    }

    // Speed effect badge
    if (hasSpeedEffect) {
      _paintBadge(
        canvas,
        Offset(badgeX, badgeY),
        badgeSize,
        Colors.purple,
        '⏱',
      );
    }
  }

  static void _paintBadge(
    Canvas canvas,
    Offset position,
    double size,
    Color color,
    String label, {
    int? count,
  }) {
    // Badge background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(position.dx, position.dy, size, size),
        const Radius.circular(4),
      ),
      Paint()..color = color,
    );

    // Badge label
    final textPainter = TextPainter(
      text: TextSpan(
        text: count != null ? '$count' : label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx + (size - textPainter.width) / 2,
        position.dy + (size - textPainter.height) / 2,
      ),
    );
  }
}
```

---

## 12. Keyframe System

### 12.1 Keyframe Track Model

```dart
@immutable
class KeyframeTrack {
  final String id;
  final String clipId;
  final String parameterName; // e.g., "opacity", "position.x", "scale"
  final ParameterType parameterType;
  final List<Keyframe> keyframes;

  /// Get interpolated value at time
  dynamic getValueAt(TimeMicros time) {
    if (keyframes.isEmpty) return parameterType.defaultValue;
    if (keyframes.length == 1) return keyframes.first.value;

    // Find surrounding keyframes
    Keyframe? before;
    Keyframe? after;

    for (final kf in keyframes) {
      if (kf.time <= time) {
        before = kf;
      } else {
        after = kf;
        break;
      }
    }

    if (before == null) return keyframes.first.value;
    if (after == null) return keyframes.last.value;

    // Interpolate
    final t = (time - before.time) / (after.time - before.time);
    final easedT = before.easing.transform(t);

    return parameterType.interpolate(before.value, after.value, easedT);
  }
}

@immutable
class Keyframe {
  final String id;
  final TimeMicros time;
  final dynamic value;
  final EasingCurve easing;
  final KeyframeInterpolation interpolation;
}

enum KeyframeInterpolation {
  linear,
  bezier,
  hold, // Step function
}

enum ParameterType {
  scalar,
  color,
  point,
  size,
  rotation,
}
```

### 12.2 Keyframe Painter

```dart
class KeyframePainter extends CustomPainter {
  final List<KeyframeTrack> tracks;
  final ViewportState viewport;
  final String? selectedKeyframeId;
  final bool showCurves;

  @override
  void paint(Canvas canvas, Size size) {
    for (final track in tracks) {
      _paintKeyframeTrack(canvas, track, size);
    }
  }

  void _paintKeyframeTrack(Canvas canvas, KeyframeTrack track, Size size) {
    final clipRect = _getClipRect(track.clipId);
    if (clipRect == null) return;

    final trackLaneHeight = 20.0;
    final trackLaneTop = clipRect.bottom - trackLaneHeight;

    // Draw keyframe lane background
    canvas.drawRect(
      Rect.fromLTWH(clipRect.left, trackLaneTop, clipRect.width, trackLaneHeight),
      Paint()..color = Colors.black26,
    );

    // Draw interpolation curves if enabled
    if (showCurves && track.keyframes.length >= 2) {
      _paintInterpolationCurve(canvas, track, trackLaneTop, trackLaneHeight);
    }

    // Draw keyframe diamonds
    for (final keyframe in track.keyframes) {
      final x = viewport.timeToPixelX(keyframe.time);

      if (x < clipRect.left - 10 || x > clipRect.right + 10) continue;

      _paintKeyframeDiamond(
        canvas,
        Offset(x, trackLaneTop + trackLaneHeight / 2),
        keyframe,
        isSelected: keyframe.id == selectedKeyframeId,
      );
    }
  }

  void _paintKeyframeDiamond(
    Canvas canvas,
    Offset center,
    Keyframe keyframe,
    {required bool isSelected},
  ) {
    const size = 8.0;

    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..lineTo(center.dx + size, center.dy)
      ..lineTo(center.dx, center.dy + size)
      ..lineTo(center.dx - size, center.dy)
      ..close();

    // Fill
    canvas.drawPath(
      path,
      Paint()..color = isSelected ? Colors.yellow : Colors.white,
    );

    // Border
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintInterpolationCurve(
    Canvas canvas,
    KeyframeTrack track,
    double top,
    double height,
  ) {
    final path = Path();
    var first = true;

    // Sample curve at regular intervals
    final firstKf = track.keyframes.first;
    final lastKf = track.keyframes.last;
    final sampleCount = 50;

    for (int i = 0; i <= sampleCount; i++) {
      final t = i / sampleCount;
      final time = firstKf.time + ((lastKf.time - firstKf.time) * t).round();
      final value = track.getValueAt(time);

      // Normalize value to 0-1 range for display
      final normalizedValue = _normalizeValue(value, track.parameterType);

      final x = viewport.timeToPixelX(time);
      final y = top + height * (1 - normalizedValue);

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.yellow.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(KeyframePainter oldDelegate) {
    return tracks != oldDelegate.tracks ||
           viewport != oldDelegate.viewport ||
           selectedKeyframeId != oldDelegate.selectedKeyframeId ||
           showCurves != oldDelegate.showCurves;
  }
}
```

### 12.3 Keyframe Editor

```dart
class KeyframeController {
  final TimelineDataManager data;

  /// Add keyframe at current time
  Keyframe addKeyframe({
    required String clipId,
    required String parameterName,
    required TimeMicros time,
    required dynamic value,
    EasingCurve easing = Curves.easeInOut,
  }) {
    final keyframe = Keyframe(
      id: const Uuid().v4(),
      time: time,
      value: value,
      easing: easing,
      interpolation: KeyframeInterpolation.bezier,
    );

    data.addKeyframe(clipId, parameterName, keyframe);
    HapticFeedback.lightImpact();

    return keyframe;
  }

  /// Move keyframe to new time
  void moveKeyframe(String keyframeId, TimeMicros newTime) {
    data.moveKeyframe(keyframeId, newTime);
  }

  /// Update keyframe value
  void updateKeyframeValue(String keyframeId, dynamic newValue) {
    data.updateKeyframeValue(keyframeId, newValue);
  }

  /// Change keyframe easing
  void changeEasing(String keyframeId, EasingCurve newEasing) {
    data.updateKeyframeEasing(keyframeId, newEasing);
  }

  /// Delete keyframe
  void deleteKeyframe(String keyframeId) {
    data.deleteKeyframe(keyframeId);
    HapticFeedback.lightImpact();
  }

  /// Copy keyframes
  void copyKeyframes(List<String> keyframeIds) {
    // Store in clipboard
  }

  /// Paste keyframes at new time
  void pasteKeyframes(TimeMicros time, String clipId, String parameterName) {
    // Paste from clipboard with time offset
  }
}
```

---

## 13. Audio Features

### 13.1 Waveform Generation

```dart
/// Parameters for waveform generation isolate
class _WaveformParams {
  final String assetPath;
  final int samplesPerSecond;

  const _WaveformParams({
    required this.assetPath,
    required this.samplesPerSecond,
  });
}

class WaveformGenerator {
  /// Generate waveform data from audio file
  static Future<WaveformData> generate(
    String assetPath,
    int targetSamplesPerSecond,
  ) async {
    // Run in isolate to avoid blocking UI
    return compute(_generateWaveform, _WaveformParams(
      assetPath: assetPath,
      samplesPerSecond: targetSamplesPerSecond,
    ));
  }

  static WaveformData _generateWaveform(_WaveformParams params) {
    // Use platform channel to native audio decoder
    // Extract peak amplitude samples at target rate
    // Return normalized Float32List (0.0 - 1.0)
    // Implementation would call native code via MethodChannel
    throw UnimplementedError('Implemented via platform channel');
  }
}

class WaveformData {
  final Float32List samples;
  final int sampleRate; // Samples per second
  final TimeMicros duration;

  /// Get samples for time range
  Float32List getSamplesForRange(
    TimeMicros start,
    TimeMicros end,
    int targetSamples,
  ) {
    final startSample = (start / 1000000 * sampleRate).round();
    final endSample = (end / 1000000 * sampleRate).round();
    final sourceSamples = endSample - startSample;

    if (sourceSamples <= targetSamples) {
      // Upsample or exact
      return Float32List.sublistView(samples, startSample, endSample);
    }

    // Downsample - find peak in each bucket
    final result = Float32List(targetSamples);
    final bucketSize = sourceSamples / targetSamples;

    for (int i = 0; i < targetSamples; i++) {
      final bucketStart = startSample + (i * bucketSize).round();
      final bucketEnd = startSample + ((i + 1) * bucketSize).round();

      var peak = 0.0;
      for (int j = bucketStart; j < bucketEnd && j < samples.length; j++) {
        if (samples[j].abs() > peak) {
          peak = samples[j].abs();
        }
      }
      result[i] = peak;
    }

    return result;
  }
}
```

### 13.2 Volume Keyframe Model

```dart
/// Volume keyframe for audio envelope
@immutable
class VolumeKeyframe {
  final String id;
  final TimeMicros time;
  final double volume; // 0.0 to 1.0

  const VolumeKeyframe({
    required this.id,
    required this.time,
    required this.volume,
  });
}
```

### 13.3 Volume Envelope

```dart
class VolumeEnvelopePainter extends CustomPainter {
  final List<VolumeKeyframe> keyframes;
  final ViewportState viewport;
  final Rect clipRect;
  final bool isEditing;
  final String? selectedKeyframeId;

  @override
  void paint(Canvas canvas, Size size) {
    if (keyframes.isEmpty) return;

    // Draw envelope line
    final path = Path();
    var first = true;

    for (final keyframe in keyframes) {
      final x = viewport.timeToPixelX(keyframe.time);
      final y = clipRect.bottom - (keyframe.volume * clipRect.height);

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    // Line style
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Draw keyframe handles if editing
    if (isEditing) {
      for (final keyframe in keyframes) {
        final x = viewport.timeToPixelX(keyframe.time);
        final y = clipRect.bottom - (keyframe.volume * clipRect.height);

        final isSelected = keyframe.id == selectedKeyframeId;

        canvas.drawCircle(
          Offset(x, y),
          isSelected ? 8 : 6,
          Paint()..color = isSelected ? Colors.yellow : Colors.white,
        );
        canvas.drawCircle(
          Offset(x, y),
          isSelected ? 8 : 6,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(VolumeEnvelopePainter oldDelegate) {
    return keyframes != oldDelegate.keyframes ||
           viewport != oldDelegate.viewport ||
           isEditing != oldDelegate.isEditing ||
           selectedKeyframeId != oldDelegate.selectedKeyframeId;
  }
}
```

### 13.4 Fade Handles

```dart
class AudioFadeController {
  final TimelineDataManager data;

  /// Set fade in duration
  void setFadeIn(String clipId, TimeMicros duration) {
    final clip = data.getClip(clipId);
    if (clip == null) return;

    // Create or update fade in keyframes
    final volumeTrack = data.getOrCreateVolumeTrack(clipId);

    // Remove existing fade in keyframes
    final fadeInEnd = clip.startTime + duration;
    volumeTrack.keyframes
        .where((k) => k.time < fadeInEnd)
        .forEach((k) => data.deleteKeyframe(k.id));

    // Add new fade in keyframes
    data.addKeyframe(
      clipId,
      'volume',
      Keyframe(
        id: const Uuid().v4(),
        time: clip.startTime,
        value: 0.0,
        easing: Curves.easeIn,
      ),
    );

    data.addKeyframe(
      clipId,
      'volume',
      Keyframe(
        id: const Uuid().v4(),
        time: fadeInEnd,
        value: 1.0,
        easing: Curves.linear,
      ),
    );

    HapticFeedback.lightImpact();
  }

  /// Set fade out duration
  void setFadeOut(String clipId, TimeMicros duration) {
    final clip = data.getClip(clipId);
    if (clip == null) return;

    final volumeTrack = data.getOrCreateVolumeTrack(clipId);

    // Remove existing fade out keyframes
    final fadeOutStart = clip.endTime - duration;
    volumeTrack.keyframes
        .where((k) => k.time > fadeOutStart)
        .forEach((k) => data.deleteKeyframe(k.id));

    // Add new fade out keyframes
    data.addKeyframe(
      clipId,
      'volume',
      Keyframe(
        id: const Uuid().v4(),
        time: fadeOutStart,
        value: 1.0,
        easing: Curves.linear,
      ),
    );

    data.addKeyframe(
      clipId,
      'volume',
      Keyframe(
        id: const Uuid().v4(),
        time: clip.endTime,
        value: 0.0,
        easing: Curves.easeOut,
      ),
    );

    HapticFeedback.lightImpact();
  }
}
```

---

## 14. Gesture System

### 14.1 Main Gesture Handler

```dart
class TimelineGestureHandler {
  final TimelineViewController controller;
  final VoidCallback onRepaint;

  /// Current gesture state
  GestureState _state = GestureState.idle;

  /// Sub-handlers
  late final ClipDragController _dragController;
  late final TrimController _trimController;
  late final SelectionController _selectionController;
  late final ZoomController _zoomController;
  late final ScrollController _scrollController;

  /// Touch tracking
  Offset? _lastTouchPosition;
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  /// Constants
  static const double doubleTapDistance = 30.0;
  static const Duration doubleTapTimeout = Duration(milliseconds: 300);

  void onScaleStart(ScaleStartDetails details) {
    _lastTouchPosition = details.localFocalPoint;

    if (details.pointerCount == 2) {
      // Two-finger: start zoom
      _state = GestureState.zooming;
      _zoomController.startZoom(details.localFocalPoint);
    } else {
      // Single finger: determine action based on hit test
      final hitResult = _hitTest(details.localFocalPoint);

      switch (hitResult.type) {
        case HitType.trimHandle:
          _state = GestureState.trimming;
          _trimController.startTrim(
            hitResult.clipId!,
            hitResult.trimEdge!,
          );
          break;

        case HitType.clip:
          // Wait for movement to distinguish tap from drag
          _state = GestureState.pendingDrag;
          _selectionController.selectClip(hitResult.clipId!);
          break;

        case HitType.playhead:
          _state = GestureState.scrubbingPlayhead;
          break;

        case HitType.ruler:
          _state = GestureState.scrubbingRuler;
          _seekToPosition(details.localFocalPoint);
          break;

        case HitType.empty:
          _state = GestureState.scrolling;
          break;
      }
    }
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    final delta = details.localFocalPoint - (_lastTouchPosition ?? details.localFocalPoint);
    _lastTouchPosition = details.localFocalPoint;

    switch (_state) {
      case GestureState.zooming:
        _zoomController.updateZoom(details.scale);
        break;

      case GestureState.pendingDrag:
        // Check if moved enough to start drag
        if (delta.distance > 5) {
          _state = GestureState.dragging;
          _dragController.startDrag(
            details.localFocalPoint,
            _selectionController.primaryId!,
          );
        }
        break;

      case GestureState.dragging:
        final preview = _dragController.updateDrag(
          details.localFocalPoint,
          details.localFocalPoint.dy,
        );
        // Update preview display
        onRepaint();
        break;

      case GestureState.trimming:
        final preview = _trimController.updateTrim(delta.dx);
        // Update preview display
        onRepaint();
        break;

      case GestureState.scrubbingPlayhead:
      case GestureState.scrubbingRuler:
        _seekToPosition(details.localFocalPoint);
        break;

      case GestureState.scrolling:
        _scrollController.scroll(delta);
        break;

      default:
        break;
    }
  }

  void onScaleEnd(ScaleEndDetails details) {
    switch (_state) {
      case GestureState.zooming:
        _zoomController.endZoom();
        // Apply momentum if velocity > threshold
        if (details.velocity.pixelsPerSecond.distance > 100) {
          _scrollController.startMomentumScroll(details.velocity);
        }
        break;

      case GestureState.dragging:
        _dragController.endDrag(_dragController.currentPreview);
        break;

      case GestureState.trimming:
        _trimController.endTrim(_trimController.currentPreview);
        break;

      case GestureState.scrolling:
        _scrollController.startMomentumScroll(details.velocity);
        break;

      default:
        break;
    }

    _state = GestureState.idle;
    onRepaint();
  }

  void onTapDown(TapDownDetails details) {
    // Record for double-tap detection
    _lastTapPosition = details.localPosition;
  }

  void onTapUp(TapUpDetails details) {
    final now = DateTime.now();

    // Check for double-tap
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) < doubleTapTimeout &&
        _lastTapPosition != null &&
        (details.localPosition - _lastTapPosition!).distance < doubleTapDistance) {
      _handleDoubleTap(details.localPosition);
      _lastTapTime = null;
      return;
    }

    _lastTapTime = now;

    // Single tap handling
    final hitResult = _hitTest(details.localPosition);

    switch (hitResult.type) {
      case HitType.clip:
        // Already selected in onScaleStart
        break;

      case HitType.marker:
        _selectionController.selectMarker(hitResult.markerId!);
        break;

      case HitType.transition:
        _selectionController.selectTransition(hitResult.transitionId!);
        break;

      case HitType.keyframe:
        _selectionController.selectKeyframe(hitResult.keyframeId!);
        break;

      case HitType.ruler:
        _seekToPosition(details.localPosition);
        break;

      case HitType.empty:
        _selectionController.clearSelection();
        break;

      default:
        break;
    }

    onRepaint();
  }

  void onLongPressStart(LongPressStartDetails details) {
    final hitResult = _hitTest(details.localPosition);

    if (hitResult.type == HitType.clip) {
      // Show context menu
      HapticFeedback.mediumImpact();
      _showClipContextMenu(hitResult.clipId!, details.globalPosition);
    } else if (hitResult.type == HitType.empty) {
      // Start marquee selection
      _state = GestureState.marqueeSelecting;
      _selectionController.startMarquee(details.localPosition);
      HapticFeedback.lightImpact();
    }
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_state == GestureState.marqueeSelecting) {
      _selectionController.updateMarquee(details.localPosition);
      onRepaint();
    }
  }

  void onLongPressEnd(LongPressEndDetails details) {
    if (_state == GestureState.marqueeSelecting) {
      _selectionController.endMarquee();
      _state = GestureState.idle;
      onRepaint();
    }
  }

  void _handleDoubleTap(Offset position) {
    final hitResult = _hitTest(position);

    switch (hitResult.type) {
      case HitType.clip:
        // Open clip properties
        _showClipProperties(hitResult.clipId!);
        break;

      case HitType.transition:
        // Open transition editor
        _showTransitionEditor(hitResult.transitionId!);
        break;

      case HitType.marker:
        // Edit marker
        _showMarkerEditor(hitResult.markerId!);
        break;

      case HitType.empty:
        // Add marker at position
        final time = controller.viewport.state.pixelXToTime(position.dx);
        controller.markers.addMarker(time: time);
        break;

      default:
        break;
    }
  }

  HitTestResult _hitTest(Offset position) {
    // Test in order of priority (top to bottom of layer stack)

    // 1. Playhead
    final playheadX = controller.viewport.state.timeToPixelX(
      controller.playback.currentTime
    );
    if ((position.dx - playheadX).abs() < 20) {
      return HitTestResult(type: HitType.playhead);
    }

    // 2. Ruler area
    if (position.dy < 30) { // Ruler height
      return HitTestResult(type: HitType.ruler);
    }

    // 3. Keyframes
    // ... test keyframes

    // 4. Trim handles (only for selected clips)
    final trimHit = _trimHitTester.hitTest(
      position,
      controller.data.visibleClips,
      controller.viewport.state,
      controller.selection.state,
    );
    if (trimHit != null) {
      return HitTestResult(
        type: HitType.trimHandle,
        clipId: trimHit.clipId,
        trimEdge: trimHit.edge,
      );
    }

    // 5. Clips
    for (final clip in controller.data.visibleClips.reversed) {
      final rect = _getClipRect(clip);
      if (rect.contains(position)) {
        return HitTestResult(type: HitType.clip, clipId: clip.id);
      }
    }

    // 6. Markers
    for (final marker in controller.data.markers) {
      final markerX = controller.viewport.state.timeToPixelX(marker.time);
      if ((position.dx - markerX).abs() < 10) {
        return HitTestResult(type: HitType.marker, markerId: marker.id);
      }
    }

    // 7. Empty space
    return HitTestResult(type: HitType.empty);
  }
}

enum GestureState {
  idle,
  scrolling,
  zooming,
  pendingDrag,
  dragging,
  trimming,
  scrubbingPlayhead,
  scrubbingRuler,
  marqueeSelecting,
}

enum HitType {
  playhead,
  ruler,
  clip,
  trimHandle,
  transition,
  marker,
  keyframe,
  empty,
}

/// Result of hit testing
class HitTestResult {
  final HitType type;
  final String? clipId;
  final String? markerId;
  final String? transitionId;
  final String? keyframeId;
  final TrimEdge? trimEdge;

  const HitTestResult({
    required this.type,
    this.clipId,
    this.markerId,
    this.transitionId,
    this.keyframeId,
    this.trimEdge,
  });
}
```

### 14.2 Momentum Scroll

```dart
class MomentumScrollController {
  final ViewportController viewport;

  AnimationController? _animationController;
  Simulation? _simulation;

  void startMomentumScroll(Velocity velocity) {
    // Cancel any existing animation
    _animationController?.stop();
    _animationController?.dispose();

    // Create friction simulation
    _simulation = FrictionSimulation(
      0.135, // iOS-like friction coefficient
      viewport.state.scrollPosition.toDouble(),
      -velocity.pixelsPerSecond.dx * viewport.state.microsPerPixel,
    );

    _animationController = AnimationController.unbounded(
      vsync: _vsync,
    );

    _animationController!.addListener(() {
      final time = _animationController!.value;
      final newScroll = _simulation!.x(time).round();

      // Clamp to bounds
      final clampedScroll = newScroll.clamp(
        0,
        viewport.maxScrollPosition,
      );

      viewport.setScrollPosition(clampedScroll);

      // Check if hit bounds or stopped
      if (_simulation!.isDone(time) || clampedScroll != newScroll) {
        _animationController!.stop();
      }
    });

    _animationController!.animateWith(_simulation!);
  }

  void stopMomentumScroll() {
    _animationController?.stop();
  }

  void dispose() {
    _animationController?.dispose();
  }
}
```

---

## 15. Undo/Redo System

### 15.1 Undo Manager (using existing implementation)

```dart
/// Leverages existing TimelineManager from Timeline V2 architecture
class TimelineUndoManager {
  final TimelineManager _timelineManager;

  /// Undo last operation
  bool undo() {
    if (!_timelineManager.canUndo) return false;

    _timelineManager.undo();
    HapticFeedback.lightImpact();
    return true;
  }

  /// Redo last undone operation
  bool redo() {
    if (!_timelineManager.canRedo) return false;

    _timelineManager.redo();
    HapticFeedback.lightImpact();
    return true;
  }

  /// Check if can undo
  bool get canUndo => _timelineManager.canUndo;

  /// Check if can redo
  bool get canRedo => _timelineManager.canRedo;

  /// Get undo stack depth
  int get undoStackDepth => _timelineManager.undoStackDepth;

  /// Get redo stack depth
  int get redoStackDepth => _timelineManager.redoStackDepth;
}
```

### 15.2 Three-Finger Gesture for Undo/Redo

```dart
class UndoRedoGestureRecognizer extends StatefulWidget {
  final Widget child;
  final TimelineUndoManager undoManager;

  @override
  State<UndoRedoGestureRecognizer> createState() => _UndoRedoGestureRecognizerState();
}

class _UndoRedoGestureRecognizerState extends State<UndoRedoGestureRecognizer> {
  Offset? _startPosition;
  int _pointerCount = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _pointerCount++,
      onPointerUp: (_) => _pointerCount--,
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          if (_pointerCount >= 3) {
            _startPosition = details.globalPosition;
          }
        },
        onHorizontalDragUpdate: (details) {
          if (_pointerCount >= 3 && _startPosition != null) {
            final delta = details.globalPosition.dx - _startPosition!.dx;

            if (delta < -50) {
              // Swipe left - Undo
              if (widget.undoManager.undo()) {
                _startPosition = details.globalPosition;
              }
            } else if (delta > 50) {
              // Swipe right - Redo
              if (widget.undoManager.redo()) {
                _startPosition = details.globalPosition;
              }
            }
          }
        },
        onHorizontalDragEnd: (_) {
          _startPosition = null;
        },
        child: widget.child,
      ),
    );
  }
}
```

---

## 16. Performance Optimizations

### 16.1 Render Optimization Checklist

```dart
/// Performance monitoring mixin
mixin TimelinePerformanceMonitor {
  final _frameTimings = <Duration>[];
  final _maxStoredFrames = 120;

  void recordFrameTime(Duration frameTime) {
    _frameTimings.add(frameTime);
    if (_frameTimings.length > _maxStoredFrames) {
      _frameTimings.removeAt(0);
    }
  }

  double get averageFrameTimeMs {
    if (_frameTimings.isEmpty) return 0;
    final total = _frameTimings.fold<int>(
      0, (sum, d) => sum + d.inMicroseconds
    );
    return total / _frameTimings.length / 1000;
  }

  double get fps {
    final avgMs = averageFrameTimeMs;
    if (avgMs <= 0) return 60;
    return 1000 / avgMs;
  }

  bool get isDroppingFrames => averageFrameTimeMs > 16.67;
}
```

### 16.2 Memory Optimization

```dart
class MemoryOptimizer {
  final ThumbnailCache thumbnailCache;
  final WaveformCache waveformCache;

  /// Respond to memory pressure
  void handleMemoryWarning(MemoryPressureLevel level) {
    switch (level) {
      case MemoryPressureLevel.warning:
        // Reduce caches by 50%
        thumbnailCache.reduceSize(0.5);
        waveformCache.reduceSize(0.5);
        break;

      case MemoryPressureLevel.critical:
        // Clear all caches
        thumbnailCache.clear();
        waveformCache.clearAllExcept(_visibleAssetIds);
        break;

      case MemoryPressureLevel.normal:
        // Restore normal cache sizes
        thumbnailCache.restoreNormalSize();
        break;
    }
  }

  /// Preload assets for smooth playback
  void preloadForPlayback(TimeMicros currentTime, TimeMicros lookAhead) {
    final clips = _data.queryRange(currentTime, currentTime + lookAhead);

    for (final clip in clips) {
      // Preload thumbnails
      if (clip.type == ClipType.video) {
        thumbnailCache.preload(clip.mediaAssetId, clip.sourceIn, clip.sourceOut);
      }

      // Preload waveforms
      if (clip.type == ClipType.audio) {
        waveformCache.preload(clip.mediaAssetId);
      }
    }
  }
}
```

### 16.3 Render Culling

```dart
class RenderCulling {
  /// Get only visible clips with margin
  static List<TimelineClip> cullClips(
    List<TimelineClip> clips,
    ViewportState viewport,
    {double marginPixels = 50}
  ) {
    final marginMicros = (marginPixels * viewport.microsPerPixel).round();
    final visibleStart = viewport.scrollPosition - marginMicros;
    final visibleEnd = viewport.scrollPosition +
        (viewport.viewportWidth * viewport.microsPerPixel).round() + marginMicros;

    return clips.where((clip) {
      return clip.endTime > visibleStart && clip.startTime < visibleEnd;
    }).toList();
  }

  /// Get visible track indices
  static (int, int) cullTracks(
    List<Track> tracks,
    double verticalOffset,
    double viewportHeight,
  ) {
    int firstVisible = 0;
    int lastVisible = tracks.length - 1;

    double y = 0;
    for (int i = 0; i < tracks.length; i++) {
      if (y + tracks[i].height > verticalOffset) {
        firstVisible = i;
        break;
      }
      y += tracks[i].height;
    }

    y = 0;
    for (int i = 0; i < tracks.length; i++) {
      y += tracks[i].height;
      if (y > verticalOffset + viewportHeight) {
        lastVisible = i;
        break;
      }
    }

    return (firstVisible, lastVisible);
  }
}
```

---

## 17. File Structure

```
lib/
├── timeline/
│   ├── timeline_widget.dart              # Main timeline widget
│   ├── timeline_controller.dart          # Central controller
│   │
│   ├── data/
│   │   ├── timeline_data_manager.dart    # Data operations
│   │   ├── viewport_state.dart           # Viewport model
│   │   ├── selection_state.dart          # Selection model
│   │   └── models/
│   │       ├── track.dart
│   │       ├── clip.dart
│   │       ├── marker.dart
│   │       ├── transition.dart
│   │       └── keyframe.dart
│   │
│   ├── rendering/
│   │   ├── timeline_painter.dart         # Main painter
│   │   ├── painters/
│   │   │   ├── ruler_painter.dart
│   │   │   ├── track_painter.dart
│   │   │   ├── clip_painter.dart
│   │   │   ├── waveform_painter.dart
│   │   │   ├── thumbnail_painter.dart
│   │   │   ├── playhead_painter.dart
│   │   │   ├── marker_painter.dart
│   │   │   ├── transition_painter.dart
│   │   │   ├── keyframe_painter.dart
│   │   │   ├── selection_painter.dart
│   │   │   └── snap_guide_painter.dart
│   │   └── minimap_painter.dart
│   │
│   ├── gestures/
│   │   ├── timeline_gesture_handler.dart # Main gesture handler
│   │   ├── drag_controller.dart
│   │   ├── trim_controller.dart
│   │   ├── zoom_controller.dart
│   │   ├── scroll_controller.dart
│   │   ├── slip_slide_controller.dart
│   │   └── hit_testing.dart
│   │
│   ├── editing/
│   │   ├── split_controller.dart
│   │   ├── clipboard_controller.dart
│   │   ├── snap_controller.dart
│   │   ├── marker_controller.dart
│   │   ├── keyframe_controller.dart
│   │   └── transition_controller.dart
│   │
│   ├── audio/
│   │   ├── waveform_generator.dart
│   │   ├── waveform_cache.dart
│   │   ├── volume_controller.dart
│   │   └── fade_controller.dart
│   │
│   ├── cache/
│   │   ├── thumbnail_cache.dart
│   │   ├── layout_cache.dart
│   │   └── memory_optimizer.dart
│   │
│   ├── widgets/
│   │   ├── track_header.dart
│   │   ├── navigation_bar.dart
│   │   ├── timecode_display.dart
│   │   ├── zoom_controls.dart
│   │   └── minimap.dart
│   │
│   └── utils/
│       ├── time_utils.dart
│       ├── render_culling.dart
│       └── performance_monitor.dart
│
└── test/
    └── timeline/
        ├── data/
        │   ├── timeline_data_manager_test.dart
        │   ├── viewport_state_test.dart
        │   └── selection_state_test.dart
        ├── gestures/
        │   ├── drag_controller_test.dart
        │   ├── trim_controller_test.dart
        │   └── snap_controller_test.dart
        ├── editing/
        │   ├── split_controller_test.dart
        │   └── clipboard_controller_test.dart
        └── rendering/
            └── clip_painter_test.dart
```

---

## 18. Implementation Phases

### Phase 1: Core Foundation (2 weeks)
- [ ] Timeline widget structure
- [ ] Viewport state management
- [ ] Basic clip rendering (rectangles only)
- [ ] Playhead rendering and playback sync
- [ ] Pinch-to-zoom and pan scrolling
- [ ] Single clip selection

### Phase 2: Clip Interactions (2 weeks)
- [ ] Clip drag-and-drop
- [ ] Basic trimming (head/tail)
- [ ] Split at playhead
- [ ] Multi-selection
- [ ] Copy/cut/paste
- [ ] Undo/redo integration

### Phase 3: Visual Polish (2 weeks)
- [ ] Thumbnail loading and caching
- [ ] Waveform generation and display
- [ ] Clip labels and badges
- [ ] Selection highlights
- [ ] Smooth animations

### Phase 4: Advanced Editing (2 weeks)
- [ ] Snap system
- [ ] Ripple/roll trim
- [ ] Slip/slide
- [ ] Markers
- [ ] In/out points

### Phase 5: Audio Features (1 week)
- [ ] Volume envelope
- [ ] Fade handles
- [ ] Audio scrubbing

### Phase 6: Effects & Keyframes (2 weeks)
- [ ] Transition indicators
- [ ] Keyframe display
- [ ] Keyframe editing
- [ ] Effect badges

### Phase 7: Polish & Performance (1 week)
- [ ] Performance profiling
- [ ] Memory optimization
- [ ] Edge case handling
- [ ] Device testing

**Total: ~12 weeks**

---

## Document Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-30 | Initial comprehensive document |
| 1.1 | 2026-01-30 | Review pass: Added missing types (TimeRange, ClipType, DragState, TrimState, RollState, SlipState, SlideState, SplitResult, VolumeKeyframe, SnapResult, HitTestResult, _WaveformParams). Fixed Material icons to CupertinoIcons. Added missing widgets (_TrackButton, _NavButton, _PlayButton). Fixed ClipTransition model with trackId and editPointTime. Updated section numbering. |

---

**Author:** Claude Code
**Reviewed:** Multiple internal reviews completed (2 passes)
**Status:** Ready for implementation
