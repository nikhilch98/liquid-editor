# Timeline Architecture V2 - Ultra-Low Latency Design

**Document Version:** 1.0
**Created:** 2026-01-30
**Status:** Draft - Pending Review
**Authors:** Development Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Goals & Requirements](#2-goals--requirements)
3. [Current State Analysis](#3-current-state-analysis)
4. [Proposed Architecture Overview](#4-proposed-architecture-overview)
5. [Component Design: MediaAsset Registry](#5-component-design-mediaasset-registry)
6. [Component Design: Persistent Timeline Index](#6-component-design-persistent-timeline-index)
7. [Component Design: Time & Frame System](#7-component-design-time--frame-system)
8. [Component Design: Clip Type Hierarchy](#8-component-design-clip-type-hierarchy)
9. [Component Design: Playback Engine](#9-component-design-playback-engine)
10. [Component Design: Frame Cache System](#10-component-design-frame-cache-system)
11. [Data Models & Serialization](#11-data-models--serialization)
12. [Migration Strategy](#12-migration-strategy)
13. [Implementation Plan](#13-implementation-plan)
14. [Testing Strategy](#14-testing-strategy)
15. [Performance Benchmarks](#15-performance-benchmarks)
16. [Risk Analysis](#16-risk-analysis)
17. [Appendix](#17-appendix)

---

## 1. Executive Summary

### 1.1 Purpose

This document specifies a complete redesign of Liquid Editor's timeline and clip management architecture to achieve:

- **Ultra-low latency** (<16ms for all interactive operations)
- **Zero UX tradeoffs** (no hiccups, no stale frames, no interruptions)
- **Professional-grade quality** (frame-accurate, broadcast-standard)
- **Full extensibility** (multiple source videos, custom clip types, future multi-cam)

### 1.2 Key Architectural Decisions

| Component | Current | Proposed | Benefit |
|-----------|---------|----------|---------|
| Timeline Index | O(n) linear scan | Persistent Order Statistic Tree | O(log n) everything |
| Undo/Redo | Command pattern | Persistent tree (pointer swap) | O(1) instant undo |
| Time Storage | Milliseconds (int) | Microseconds (int64) + frame snap | Zero precision loss |
| Source Videos | Single path string | MediaAsset registry | Multi-source support |
| Clip Types | VideoClip + Gap | Full type hierarchy | Extensible |
| Playback | Single composition | Double-buffered hot-swap | Zero interruption |
| Scrubbing | Seek on demand | Frame cache + prefetch | <16ms latency |
| Multi-source | Same video A/B | Pre-warmed decoder pool | 0ms transitions |

### 1.3 Success Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Timeline lookup | <1ms | Profiler instrumentation |
| Edit operation | <1ms | Profiler instrumentation |
| Undo/Redo | <1ms | Profiler instrumentation |
| Scrub (cached) | <16ms | Frame timing measurement |
| Scrub (uncached) | <50ms | Frame timing measurement |
| Clip transition | 0ms visible | Visual inspection + timing |
| Edit during playback | 0ms interruption | Visual inspection + timing |
| Memory (100 clips) | <50MB overhead | Memory profiler |
| Memory (frame cache) | <300MB | Memory profiler |

---

## 2. Goals & Requirements

### 2.1 Functional Requirements

#### FR-1: Multiple Source Video Support
- **FR-1.1:** Import multiple video files into a single project (V1, V2, V3, ...)
- **FR-1.2:** Create clips from any imported source video
- **FR-1.3:** Mix clips from different sources on the same timeline
- **FR-1.4:** Track source video metadata (duration, resolution, frame rate, codec)
- **FR-1.5:** Detect duplicate imports via content hashing
- **FR-1.6:** Support relinking when source files move

#### FR-2: Frame-Accurate Editing
- **FR-2.1:** All cut points snap to source video frame boundaries
- **FR-2.2:** Store time with microsecond precision (no floating-point drift)
- **FR-2.3:** Support variable export frame rates without data loss
- **FR-2.4:** Display proper SMPTE timecode (HH:MM:SS:FF)
- **FR-2.5:** Support both drop-frame and non-drop-frame timecode

#### FR-3: Timeline Operations
- **FR-3.1:** O(log n) lookup of clip at any time position
- **FR-3.2:** O(log n) insert, delete, split, trim operations
- **FR-3.3:** O(1) instant undo/redo via persistent data structures
- **FR-3.4:** Support 1000+ clips without performance degradation
- **FR-3.5:** Maintain sorted order automatically

#### FR-4: Extensible Clip Types
- **FR-4.1:** Video clips (references to source video segments)
- **FR-4.2:** Image clips (still images with duration)
- **FR-4.3:** Audio clips (audio-only segments)
- **FR-4.4:** Generator clips (solid colors, titles, patterns)
- **FR-4.5:** Gap clips (empty space / silence)
- **FR-4.6:** Compound clips (nested timelines) - future

#### FR-5: Seamless Playback
- **FR-5.1:** Zero-glitch transitions between clips
- **FR-5.2:** Zero interruption when editing during playback
- **FR-5.3:** Seamless playback across different source videos
- **FR-5.4:** Gapless audio at clip boundaries

#### FR-6: Responsive Scrubbing
- **FR-6.1:** <16ms frame display for cached frames
- **FR-6.2:** <50ms frame display for uncached frames
- **FR-6.3:** Predictive prefetching based on scrub direction
- **FR-6.4:** Smooth thumbnail strip during rapid scrubbing

### 2.2 Non-Functional Requirements

#### NFR-1: Performance
- **NFR-1.1:** All interactive operations complete within one frame (16ms at 60fps)
- **NFR-1.2:** Background operations must not block UI thread
- **NFR-1.3:** Memory usage scales linearly with content, not quadratically
- **NFR-1.4:** Support 4K video sources without degradation

#### NFR-2: Quality
- **NFR-2.1:** Zero quality tradeoffs in any user scenario
- **NFR-2.2:** Broadcast-standard frame accuracy
- **NFR-2.3:** Professional-grade export output
- **NFR-2.4:** No visible artifacts at clip transitions

#### NFR-3: Reliability
- **NFR-3.1:** No data loss on crash (auto-save)
- **NFR-3.2:** Graceful handling of missing source files
- **NFR-3.3:** Corruption detection via checksums
- **NFR-3.4:** Unlimited undo history (bounded by memory)

#### NFR-4: Extensibility
- **NFR-4.1:** New clip types addable without core changes
- **NFR-4.2:** New effects attachable to any clip type
- **NFR-4.3:** Future multi-cam support without redesign
- **NFR-4.4:** Future collaboration support without redesign

### 2.3 Non-Goals (Explicit Exclusions)

- Real-time collaboration (future consideration)
- Cloud storage integration (future consideration)
- Audio waveform editing (future consideration)
- Multi-track video compositing (future consideration)
- 3D effects and transitions (out of scope)

---

## 3. Current State Analysis

### 3.1 Current Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CURRENT ARCHITECTURE                          │
│                                                                  │
│  Project                                                         │
│  ├─ sourceVideoPath: String  ← Single source only               │
│  ├─ clips: List<TimelineItem>  ← Linear list, O(n) operations   │
│  │   ├─ TimelineClip                                            │
│  │   │   ├─ sourceVideoPath: String  ← Duplicated per clip      │
│  │   │   ├─ sourceInPoint: Duration  ← Milliseconds             │
│  │   │   ├─ sourceOutPoint: Duration ← Milliseconds             │
│  │   │   └─ keyframes: List<Keyframe>                           │
│  │   └─ TimelineGap                                             │
│  │       └─ duration: Duration                                  │
│  └─ timeline: KeyframeTimeline  ← Legacy, deprecated            │
│                                                                  │
│  ClipManager                                                     │
│  ├─ _items: List<TimelineItem>  ← Mutable list                  │
│  ├─ _undoStack: List<ClipCommand>  ← Command pattern            │
│  └─ Methods: O(n) for most operations                           │
│                                                                  │
│  PlaybackController                                              │
│  ├─ _controllerA, _controllerB  ← Same video on both            │
│  └─ preBufferPosition()  ← Single source only                   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Current Limitations

| Limitation | Impact | Severity |
|------------|--------|----------|
| Single source video | Cannot mix clips from different videos | Critical |
| O(n) timeline lookup | Slow for large timelines (>100 clips) | High |
| O(n) rebuild on edit | Lag during rapid trim dragging | High |
| Millisecond precision | Potential frame misalignment | Medium |
| No frame cache | Jerky scrubbing | High |
| Same video on A/B players | No multi-source seamless playback | Critical |
| Command pattern undo | Undo may have latency for complex ops | Medium |
| String paths per clip | No deduplication, no relinking | Medium |
| Only VideoClip + Gap | Cannot add images, colors, titles | High |

### 3.3 What Works Well (Preserve)

| Component | Strength | Action |
|-----------|----------|--------|
| Keyframe system | Well-designed, extensible | Preserve, integrate with new clips |
| Transform interpolation | 18 easing types, LRU cached | Preserve as-is |
| Tracking system | Vision framework integration | Preserve, attach to clips |
| Export presets | Flexible, well-structured | Preserve as-is |
| Project persistence | JSON serialization works | Extend for new models |
| Dual A/B players | Good foundation | Extend to decoder pool |

### 3.4 Migration Constraints

- **Backward Compatibility:** Must load existing v2 projects
- **Data Preservation:** No loss of keyframes, tracking data, or settings
- **Incremental Migration:** Can migrate components independently
- **Rollback Capability:** Keep old code paths until stable

---

## 4. Proposed Architecture Overview

### 4.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PROPOSED ARCHITECTURE V2                              │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                         PROJECT                                        │  │
│  │  ┌─────────────────┐  ┌─────────────────────────────────────────────┐ │  │
│  │  │  MEDIA ASSET    │  │           PERSISTENT TIMELINE               │ │  │
│  │  │    REGISTRY     │  │                                             │ │  │
│  │  │                 │  │  ┌─────────────────────────────────────┐   │ │  │
│  │  │  V1: {          │  │  │     ORDER STATISTIC TREE            │   │ │  │
│  │  │    id: "abc",   │  │  │         (Immutable)                 │   │ │  │
│  │  │    hash: "x1",  │  │  │                                     │   │ │  │
│  │  │    path: "...", │  │  │           [Root: 38s]               │   │ │  │
│  │  │    fps: 30000/  │  │  │          /          \               │   │ │  │
│  │  │         1001,   │  │  │      [15s]        [23s]             │   │ │  │
│  │  │    frames: 1800 │  │  │      /   \            \             │   │ │  │
│  │  │  }              │  │  │  [C1:10s][C2:5s]  [C3:15s][C4:8s]  │   │ │  │
│  │  │                 │  │  │                                     │   │ │  │
│  │  │  V2: { ... }    │  │  └─────────────────────────────────────┘   │ │  │
│  │  │  V3: { ... }    │  │                                             │ │  │
│  │  └─────────────────┘  │  Version History: [R₀, R₁, R₂, R₃, ...]    │ │  │
│  │                       │  Current: R₃  ← O(1) undo = swap to R₂     │ │  │
│  │                       └─────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                      │                                       │
│                                      ▼                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                       PLAYBACK ENGINE                                  │  │
│  │                                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐    │  │
│  │  │ COMPOSITION  │  │   DECODER    │  │      FRAME CACHE         │    │  │
│  │  │ DOUBLE-BUFFER│  │    POOL      │  │                          │    │  │
│  │  │              │  │              │  │  LRU: 120 frames         │    │  │
│  │  │ Active: A    │  │ V1: active   │  │  Prefetch: ±60 frames    │    │  │
│  │  │ Building: B  │  │ V2: warm     │  │  Memory: ~250MB          │    │  │
│  │  │              │  │ V3: standby  │  │                          │    │  │
│  │  │ Hot-swap ↔   │  │              │  │  [Frame 940..1060]       │    │  │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘    │  │
│  │                              │                                        │  │
│  │                              ▼                                        │  │
│  │                    ┌──────────────────┐                              │  │
│  │                    │    AVPlayer      │                              │  │
│  │                    │   (rendering)    │                              │  │
│  │                    └──────────────────┘                              │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Component Responsibilities

| Component | Responsibility | Key Characteristics |
|-----------|---------------|---------------------|
| **MediaAsset Registry** | Track all imported source videos | UUID + hash identification, metadata storage |
| **Persistent Timeline** | Store and query clip arrangement | O(log n) operations, immutable snapshots |
| **Order Statistic Tree** | Index clips by time position | Augmented AVL, subtree duration sums |
| **Clip Hierarchy** | Define clip types and behaviors | Polymorphic, extensible base classes |
| **Time System** | Handle time/frame conversions | Microseconds, rational frame rates |
| **Composition Manager** | Build AVComposition from timeline | Double-buffered, hot-swap capable |
| **Decoder Pool** | Manage video decoders per source | Pre-warm next source, 3 decoder limit |
| **Frame Cache** | Cache decoded frames for scrubbing | LRU eviction, predictive prefetch |
| **Playback Controller** | Orchestrate playback and scrubbing | Coordinates all playback components |

### 4.3 Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DATA FLOW DIAGRAM                                  │
│                                                                              │
│  USER ACTION                                                                 │
│       │                                                                      │
│       ▼                                                                      │
│  ┌─────────┐    ┌──────────────┐    ┌─────────────────────────────────┐    │
│  │ Edit Op │───▶│ Timeline     │───▶│ New Immutable Tree Root         │    │
│  │ (split, │    │ Manager      │    │ (shares unchanged subtrees)     │    │
│  │  trim)  │    └──────────────┘    └─────────────────────────────────┘    │
│  └─────────┘           │                           │                        │
│                        │                           ▼                        │
│                        │            ┌─────────────────────────────────┐    │
│                        │            │ Push old root to undo stack     │    │
│                        │            └─────────────────────────────────┘    │
│                        │                           │                        │
│                        ▼                           ▼                        │
│            ┌──────────────────┐      ┌─────────────────────────────────┐   │
│            │ Mark composition │      │ Notify UI of change             │   │
│            │ dirty            │      └─────────────────────────────────┘   │
│            └──────────────────┘                                             │
│                        │                                                    │
│                        ▼                                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    ON PLAY / SCRUB                                   │   │
│  │                                                                      │   │
│  │  Is composition dirty?                                               │   │
│  │       │                                                              │   │
│  │       ├─── YES ──▶ Rebuild composition (background)                 │   │
│  │       │                    │                                         │   │
│  │       │                    ▼                                         │   │
│  │       │           Hot-swap when ready                                │   │
│  │       │                                                              │   │
│  │       └─── NO ───▶ Continue playback                                │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    SCRUBBING FLOW                                    │   │
│  │                                                                      │   │
│  │  Scrub to time T                                                     │   │
│  │       │                                                              │   │
│  │       ▼                                                              │   │
│  │  Query timeline: O(log n) ──▶ Get clip at T                         │   │
│  │       │                                                              │   │
│  │       ▼                                                              │   │
│  │  Check frame cache                                                   │   │
│  │       │                                                              │   │
│  │       ├─── HIT ───▶ Display frame (<1ms)                            │   │
│  │       │                                                              │   │
│  │       └─── MISS ──▶ Show nearest I-frame (instant)                  │   │
│  │                           │                                          │   │
│  │                           ▼                                          │   │
│  │                     Decode exact frame (background)                  │   │
│  │                           │                                          │   │
│  │                           ▼                                          │   │
│  │                     Swap to exact frame when ready                   │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.4 Latency Analysis

| Operation | Steps | Latency Breakdown | Total |
|-----------|-------|-------------------|-------|
| **Lookup clip at time** | Tree traversal | O(log n) × ~1μs | <10μs |
| **Split clip** | Find + create 2 nodes + rebalance | O(log n) × 3 | <30μs |
| **Undo** | Swap root pointer | O(1) | <1μs |
| **Scrub (cached)** | Lookup + cache fetch | 10μs + 1ms | <2ms |
| **Scrub (uncached)** | Lookup + I-frame + decode | 10μs + 20ms + 30ms | <50ms |
| **Play (dirty comp)** | Rebuild + swap | 15ms + 1ms | <20ms |
| **Edit during play** | Edit + background rebuild + swap | <1ms + async | 0ms visible |

---

## 5. Component Design: MediaAsset Registry

### 5.1 Overview

The MediaAsset Registry manages all imported source media files. It provides:
- Unique identification via UUID
- Duplicate detection via content hash
- Metadata storage (dimensions, frame rate, duration, codec)
- Relinking support when files move

### 5.2 Data Model

```dart
/// Represents a rational number for precise frame rates
/// Example: 30000/1001 = 29.97fps (NTSC)
class Rational {
  final int numerator;
  final int denominator;

  const Rational(this.numerator, [this.denominator = 1]);

  double get value => numerator / denominator;

  /// Common broadcast frame rates
  static const Rational fps23_976 = Rational(24000, 1001);
  static const Rational fps24 = Rational(24);
  static const Rational fps25 = Rational(25);
  static const Rational fps29_97 = Rational(30000, 1001);
  static const Rational fps30 = Rational(30);
  static const Rational fps50 = Rational(50);
  static const Rational fps59_94 = Rational(60000, 1001);
  static const Rational fps60 = Rational(60);

  /// Microseconds per frame
  int get microsecondsPerFrame => (1000000 * denominator) ~/ numerator;

  /// Convert frame number to microseconds
  int frameToMicroseconds(int frame) =>
      (frame * 1000000 * denominator) ~/ numerator;

  /// Convert microseconds to frame number (floor)
  int microsecondsToFrame(int microseconds) =>
      (microseconds * numerator) ~/ (1000000 * denominator);

  /// Snap microseconds to nearest frame boundary
  int snapToFrame(int microseconds) {
    final frame = microsecondsToFrame(microseconds);
    return frameToMicroseconds(frame);
  }

  Map<String, dynamic> toJson() => {
    'num': numerator,
    'den': denominator,
  };

  factory Rational.fromJson(Map<String, dynamic> json) => Rational(
    json['num'] as int,
    json['den'] as int? ?? 1,
  );

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator * other.denominator == other.numerator * denominator;

  @override
  int get hashCode => (numerator / denominator).hashCode;
}

/// Media type enumeration
enum MediaType {
  video,
  image,
  audio,
}

/// Represents an imported media asset (video, image, or audio file)
class MediaAsset {
  /// Unique identifier (UUID v4)
  final String id;

  /// Content hash for duplicate detection and relinking
  /// SHA-256 of: first 1MB + last 1MB + file size
  final String contentHash;

  /// Relative path from project documents directory
  String relativePath;

  /// Original filename (for display)
  final String originalFilename;

  /// Media type
  final MediaType type;

  /// Duration in microseconds (0 for images)
  final int durationMicroseconds;

  /// Frame rate as rational number (null for images/audio)
  final Rational? frameRate;

  /// Total frame count (computed from duration and frame rate)
  int get frameCount {
    if (frameRate == null || durationMicroseconds == 0) return 0;
    return frameRate!.microsecondsToFrame(durationMicroseconds);
  }

  /// Video/image dimensions
  final int width;
  final int height;

  /// Codec information (e.g., "h264", "hevc", "prores")
  final String? codec;

  /// Audio sample rate (null for images)
  final int? audioSampleRate;

  /// Audio channel count (null for images)
  final int? audioChannels;

  /// File size in bytes
  final int fileSize;

  /// Import timestamp
  final DateTime importedAt;

  /// Whether the file is currently accessible
  bool isLinked;

  MediaAsset({
    required this.id,
    required this.contentHash,
    required this.relativePath,
    required this.originalFilename,
    required this.type,
    required this.durationMicroseconds,
    this.frameRate,
    required this.width,
    required this.height,
    this.codec,
    this.audioSampleRate,
    this.audioChannels,
    required this.fileSize,
    DateTime? importedAt,
    this.isLinked = true,
  }) : importedAt = importedAt ?? DateTime.now();

  /// Duration as Duration object
  Duration get duration => Duration(microseconds: durationMicroseconds);

  /// Aspect ratio
  double get aspectRatio => width / height;

  /// Convert frame number to microseconds for this asset
  int frameToMicroseconds(int frame) {
    if (frameRate == null) return 0;
    return frameRate!.frameToMicroseconds(frame);
  }

  /// Convert microseconds to frame number for this asset
  int microsecondsToFrame(int microseconds) {
    if (frameRate == null) return 0;
    return frameRate!.microsecondsToFrame(microseconds);
  }

  /// Snap time to nearest frame boundary
  int snapToFrame(int microseconds) {
    if (frameRate == null) return microseconds;
    return frameRate!.snapToFrame(microseconds);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'contentHash': contentHash,
    'relativePath': relativePath,
    'originalFilename': originalFilename,
    'type': type.name,
    'durationMicroseconds': durationMicroseconds,
    'frameRate': frameRate?.toJson(),
    'width': width,
    'height': height,
    'codec': codec,
    'audioSampleRate': audioSampleRate,
    'audioChannels': audioChannels,
    'fileSize': fileSize,
    'importedAt': importedAt.toIso8601String(),
    'isLinked': isLinked,
  };

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
    id: json['id'] as String,
    contentHash: json['contentHash'] as String,
    relativePath: json['relativePath'] as String,
    originalFilename: json['originalFilename'] as String,
    type: MediaType.values.byName(json['type'] as String),
    durationMicroseconds: json['durationMicroseconds'] as int,
    frameRate: json['frameRate'] != null
        ? Rational.fromJson(json['frameRate'] as Map<String, dynamic>)
        : null,
    width: json['width'] as int,
    height: json['height'] as int,
    codec: json['codec'] as String?,
    audioSampleRate: json['audioSampleRate'] as int?,
    audioChannels: json['audioChannels'] as int?,
    fileSize: json['fileSize'] as int,
    importedAt: DateTime.parse(json['importedAt'] as String),
    isLinked: json['isLinked'] as bool? ?? true,
  );
}
```

### 5.3 Registry Implementation

```dart
/// Registry for managing all media assets in a project
class MediaAssetRegistry {
  /// Assets indexed by ID
  final Map<String, MediaAsset> _assetsById = {};

  /// Assets indexed by content hash (for duplicate detection)
  final Map<String, String> _idByHash = {};

  /// Get all assets
  Iterable<MediaAsset> get assets => _assetsById.values;

  /// Get asset count
  int get count => _assetsById.length;

  /// Get asset by ID
  MediaAsset? getById(String id) => _assetsById[id];

  /// Get asset by content hash
  MediaAsset? getByHash(String hash) {
    final id = _idByHash[hash];
    return id != null ? _assetsById[id] : null;
  }

  /// Check if an asset with this hash already exists
  bool hasDuplicate(String contentHash) => _idByHash.containsKey(contentHash);

  /// Register a new asset
  /// Returns existing asset if duplicate detected
  MediaAsset register(MediaAsset asset) {
    // Check for duplicate
    final existing = getByHash(asset.contentHash);
    if (existing != null) {
      return existing; // Return existing instead of adding duplicate
    }

    _assetsById[asset.id] = asset;
    _idByHash[asset.contentHash] = asset.id;
    return asset;
  }

  /// Remove an asset (only if not referenced by any clips)
  bool remove(String id) {
    final asset = _assetsById[id];
    if (asset == null) return false;

    _assetsById.remove(id);
    _idByHash.remove(asset.contentHash);
    return true;
  }

  /// Update asset path (for relinking)
  void updatePath(String id, String newPath) {
    final asset = _assetsById[id];
    if (asset != null) {
      asset.relativePath = newPath;
      asset.isLinked = true;
    }
  }

  /// Mark asset as unlinked (file not found)
  void markUnlinked(String id) {
    final asset = _assetsById[id];
    if (asset != null) {
      asset.isLinked = false;
    }
  }

  /// Find potential relink candidates by hash
  MediaAsset? findRelinkCandidate(String contentHash) {
    return getByHash(contentHash);
  }

  /// Serialize to JSON
  List<Map<String, dynamic>> toJson() =>
      _assetsById.values.map((a) => a.toJson()).toList();

  /// Deserialize from JSON
  void fromJson(List<dynamic> json) {
    _assetsById.clear();
    _idByHash.clear();

    for (final item in json) {
      final asset = MediaAsset.fromJson(item as Map<String, dynamic>);
      _assetsById[asset.id] = asset;
      _idByHash[asset.contentHash] = asset.id;
    }
  }
}
```

### 5.4 Content Hash Algorithm

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Generate content hash for duplicate detection and relinking
/// Hash is based on: first 1MB + last 1MB + file size
/// This is fast even for large files and highly unique
Future<String> generateContentHash(File file) async {
  final fileSize = await file.length();
  final raf = await file.open(mode: FileMode.read);

  try {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    // Add file size as part of hash
    final sizeBytes = ByteData(8)..setInt64(0, fileSize);
    input.add(sizeBytes.buffer.asUint8List());

    // Read first 1MB
    const chunkSize = 1024 * 1024; // 1MB
    final firstChunk = await raf.read(chunkSize);
    input.add(firstChunk);

    // Read last 1MB (if file is larger than 2MB)
    if (fileSize > chunkSize * 2) {
      await raf.setPosition(fileSize - chunkSize);
      final lastChunk = await raf.read(chunkSize);
      input.add(lastChunk);
    } else if (fileSize > chunkSize) {
      // File is between 1-2MB, read the rest
      final remaining = await raf.read(fileSize - chunkSize);
      input.add(remaining);
    }

    input.close();
    return output.events.single.toString();
  } finally {
    await raf.close();
  }
}
```

### 5.5 Import Workflow

```dart
/// Service for importing media assets
class MediaImportService {
  final MediaAssetRegistry _registry;

  MediaImportService(this._registry);

  /// Import a media file
  /// Returns (asset, isNew) - isNew is false if duplicate was detected
  Future<(MediaAsset, bool)> importFile(File file) async {
    // 1. Generate content hash
    final hash = await generateContentHash(file);

    // 2. Check for duplicate
    final existing = _registry.getByHash(hash);
    if (existing != null) {
      return (existing, false); // Return existing, not new
    }

    // 3. Extract metadata via native platform channel
    final metadata = await _extractMetadata(file);

    // 4. Create asset
    final asset = MediaAsset(
      id: const Uuid().v4(),
      contentHash: hash,
      relativePath: _makeRelativePath(file),
      originalFilename: file.uri.pathSegments.last,
      type: metadata.type,
      durationMicroseconds: metadata.durationMicroseconds,
      frameRate: metadata.frameRate,
      width: metadata.width,
      height: metadata.height,
      codec: metadata.codec,
      audioSampleRate: metadata.audioSampleRate,
      audioChannels: metadata.audioChannels,
      fileSize: await file.length(),
    );

    // 5. Register
    _registry.register(asset);

    return (asset, true);
  }

  /// Extract metadata using native AVFoundation
  Future<_MediaMetadata> _extractMetadata(File file) async {
    // Call native iOS code via platform channel
    final result = await _channel.invokeMethod('extractMetadata', {
      'path': file.path,
    });

    return _MediaMetadata.fromMap(result);
  }
}
```

---

## 6. Component Design: Persistent Timeline Index

### 6.1 Overview

The Persistent Timeline Index is the core data structure enabling O(log n) operations and O(1) undo/redo. It is an **Order Statistic Tree** (augmented AVL tree) with **persistent/immutable** semantics.

**Key Properties:**
- Every node stores the total duration of its subtree
- Tree is always balanced (AVL invariant)
- Mutations create new nodes, preserving old tree structure
- Undo/redo is instant pointer swap between tree roots

### 6.2 Theory: Order Statistic Tree

An Order Statistic Tree augments a balanced BST with additional information at each node:

```
Standard BST Node:
  - key (clip ID)
  - left, right children

Order Statistic Tree Node (augmented):
  - key (clip ID)
  - left, right children
  - subtreeDuration: total duration of this subtree (self + left + right)
  - subtreeCount: number of clips in subtree
```

This augmentation enables:
- **Find clip at time T:** Traverse tree using subtreeDurations to navigate
- **Insert/Delete:** Standard AVL operations + update ancestor subtreeDurations
- **Total duration:** Just read root.subtreeDuration (O(1))

### 6.3 Theory: Persistent Data Structures

A **persistent** data structure preserves previous versions after mutations:

```
Traditional (Ephemeral):
  tree.insert(clip)  // Modifies tree in place, old version lost

Persistent:
  newTree = tree.insert(clip)  // Returns new tree, old tree unchanged
                               // New tree shares unchanged subtrees with old tree
```

**Path Copying:** When inserting/deleting, only nodes on the path from root to modification point are copied. Unchanged subtrees are shared.

```
Before insert:
        A
       / \
      B   C
     / \
    D   E

Insert under B (creating B'):
        A'         A (old, still valid)
       / \        / \
      B'  C      B   C
     / \        / \
    D   E'     D   E

Only A, B, and the modified leaf are copied.
Subtree C and node D are shared between versions.
```

**Memory Efficiency:** For a tree of n nodes, an edit creates O(log n) new nodes.
100 edits on a 1000-node tree: ~100 × 10 = 1000 new nodes, not 100 × 1000.

### 6.4 Data Model

```dart
/// Immutable node in the persistent order statistic tree
class TimelineNode {
  /// Unique node ID
  final String id;

  /// The clip/gap stored at this node
  final TimelineItem item;

  /// Left child (items before this one)
  final TimelineNode? left;

  /// Right child (items after this one)
  final TimelineNode? right;

  /// Height for AVL balancing
  final int height;

  /// Total duration of this subtree (self + left + right)
  final int subtreeDurationMicros;

  /// Number of items in this subtree
  final int subtreeCount;

  const TimelineNode({
    required this.id,
    required this.item,
    this.left,
    this.right,
    required this.height,
    required this.subtreeDurationMicros,
    required this.subtreeCount,
  });

  /// Duration of just this item
  int get itemDurationMicros => item.durationMicroseconds;

  /// Create a leaf node
  factory TimelineNode.leaf(TimelineItem item) => TimelineNode(
    id: item.id,
    item: item,
    left: null,
    right: null,
    height: 1,
    subtreeDurationMicros: item.durationMicroseconds,
    subtreeCount: 1,
  );

  /// Create updated node with new children (for persistent updates)
  TimelineNode withChildren({
    TimelineNode? left,
    TimelineNode? right,
  }) {
    final newLeft = left ?? this.left;
    final newRight = right ?? this.right;

    final leftDuration = newLeft?.subtreeDurationMicros ?? 0;
    final rightDuration = newRight?.subtreeDurationMicros ?? 0;
    final leftCount = newLeft?.subtreeCount ?? 0;
    final rightCount = newRight?.subtreeCount ?? 0;
    final leftHeight = newLeft?.height ?? 0;
    final rightHeight = newRight?.height ?? 0;

    return TimelineNode(
      id: id,
      item: item,
      left: newLeft,
      right: newRight,
      height: 1 + (leftHeight > rightHeight ? leftHeight : rightHeight),
      subtreeDurationMicros: leftDuration + itemDurationMicros + rightDuration,
      subtreeCount: leftCount + 1 + rightCount,
    );
  }

  /// Create node with updated item
  TimelineNode withItem(TimelineItem newItem) => TimelineNode(
    id: id,
    item: newItem,
    left: left,
    right: right,
    height: height,
    subtreeDurationMicros: (left?.subtreeDurationMicros ?? 0) +
        newItem.durationMicroseconds +
        (right?.subtreeDurationMicros ?? 0),
    subtreeCount: subtreeCount,
  );

  /// Balance factor for AVL
  int get balanceFactor =>
      (left?.height ?? 0) - (right?.height ?? 0);
}
```

### 6.5 Persistent Tree Operations

```dart
/// Persistent Order Statistic Tree for timeline management
class PersistentTimeline {
  /// Root of the tree (null if empty)
  final TimelineNode? root;

  const PersistentTimeline([this.root]);

  /// Empty timeline
  static const PersistentTimeline empty = PersistentTimeline(null);

  /// Total duration of timeline
  int get totalDurationMicros => root?.subtreeDurationMicros ?? 0;

  Duration get totalDuration => Duration(microseconds: totalDurationMicros);

  /// Number of items
  int get count => root?.subtreeCount ?? 0;

  /// Check if empty
  bool get isEmpty => root == null;

  // ============ QUERIES (O(log n)) ============

  /// Find item at a specific time position
  /// Returns (item, offsetWithinItem) or null if past end
  (TimelineItem, int)? itemAtTime(int timeMicros) {
    if (root == null || timeMicros < 0) return null;
    if (timeMicros >= totalDurationMicros) return null;

    return _itemAtTime(root!, timeMicros);
  }

  (TimelineItem, int)? _itemAtTime(TimelineNode node, int timeMicros) {
    final leftDuration = node.left?.subtreeDurationMicros ?? 0;

    if (timeMicros < leftDuration) {
      // Target is in left subtree
      return _itemAtTime(node.left!, timeMicros);
    }

    final timeAfterLeft = timeMicros - leftDuration;

    if (timeAfterLeft < node.itemDurationMicros) {
      // Target is at this node
      return (node.item, timeAfterLeft);
    }

    // Target is in right subtree
    final timeInRight = timeAfterLeft - node.itemDurationMicros;
    return _itemAtTime(node.right!, timeInRight);
  }

  /// Get the timeline start time of a specific item
  int? startTimeOf(String itemId) {
    if (root == null) return null;
    return _startTimeOf(root!, itemId, 0);
  }

  int? _startTimeOf(TimelineNode node, String itemId, int accumulated) {
    final leftDuration = node.left?.subtreeDurationMicros ?? 0;

    // Check left subtree
    if (node.left != null) {
      final found = _startTimeOf(node.left!, itemId, accumulated);
      if (found != null) return found;
    }

    // Check this node
    if (node.item.id == itemId) {
      return accumulated + leftDuration;
    }

    // Check right subtree
    if (node.right != null) {
      final rightAccum = accumulated + leftDuration + node.itemDurationMicros;
      return _startTimeOf(node.right!, itemId, rightAccum);
    }

    return null;
  }

  /// Get item by ID
  TimelineItem? getById(String itemId) {
    return _getById(root, itemId);
  }

  TimelineItem? _getById(TimelineNode? node, String itemId) {
    if (node == null) return null;
    if (node.item.id == itemId) return node.item;
    return _getById(node.left, itemId) ?? _getById(node.right, itemId);
  }

  /// Get all items in order (for serialization)
  List<TimelineItem> toList() {
    final result = <TimelineItem>[];
    _inOrder(root, result);
    return result;
  }

  void _inOrder(TimelineNode? node, List<TimelineItem> result) {
    if (node == null) return;
    _inOrder(node.left, result);
    result.add(node.item);
    _inOrder(node.right, result);
  }

  // ============ MUTATIONS (Return new tree, O(log n)) ============

  /// Insert item at a specific time position
  /// Returns new timeline with item inserted
  PersistentTimeline insertAt(int timeMicros, TimelineItem item) {
    if (root == null) {
      return PersistentTimeline(TimelineNode.leaf(item));
    }
    return PersistentTimeline(_insertAt(root!, timeMicros, item));
  }

  TimelineNode _insertAt(TimelineNode node, int timeMicros, TimelineItem item) {
    final leftDuration = node.left?.subtreeDurationMicros ?? 0;

    TimelineNode newNode;

    if (timeMicros <= leftDuration) {
      // Insert in left subtree
      final newLeft = node.left != null
          ? _insertAt(node.left!, timeMicros, item)
          : TimelineNode.leaf(item);
      newNode = node.withChildren(left: newLeft);
    } else {
      // Insert in right subtree
      final timeInRight = timeMicros - leftDuration - node.itemDurationMicros;
      final newRight = node.right != null
          ? _insertAt(node.right!, timeInRight.clamp(0, double.maxFinite.toInt()), item)
          : TimelineNode.leaf(item);
      newNode = node.withChildren(right: newRight);
    }

    return _balance(newNode);
  }

  /// Append item at end of timeline
  PersistentTimeline append(TimelineItem item) {
    return insertAt(totalDurationMicros, item);
  }

  /// Remove item by ID
  /// Returns new timeline without the item
  PersistentTimeline remove(String itemId) {
    if (root == null) return this;
    final newRoot = _remove(root!, itemId);
    return PersistentTimeline(newRoot);
  }

  TimelineNode? _remove(TimelineNode node, String itemId) {
    if (node.item.id == itemId) {
      // Found the node to remove
      if (node.left == null) return node.right;
      if (node.right == null) return node.left;

      // Has two children - replace with in-order successor
      final (successor, newRight) = _removeMin(node.right!);
      return _balance(TimelineNode(
        id: successor.id,
        item: successor.item,
        left: node.left,
        right: newRight,
        height: node.height,
        subtreeDurationMicros: 0, // Will be recalculated
        subtreeCount: 0,
      ).withChildren(left: node.left, right: newRight));
    }

    // Search in subtrees
    TimelineNode newNode;
    if (node.left != null && _contains(node.left!, itemId)) {
      newNode = node.withChildren(left: _remove(node.left!, itemId));
    } else if (node.right != null) {
      newNode = node.withChildren(right: _remove(node.right!, itemId));
    } else {
      return node; // Item not found
    }

    return _balance(newNode);
  }

  bool _contains(TimelineNode node, String itemId) {
    if (node.item.id == itemId) return true;
    if (node.left != null && _contains(node.left!, itemId)) return true;
    if (node.right != null && _contains(node.right!, itemId)) return true;
    return false;
  }

  (TimelineNode, TimelineNode?) _removeMin(TimelineNode node) {
    if (node.left == null) {
      return (node, node.right);
    }
    final (min, newLeft) = _removeMin(node.left!);
    return (min, _balance(node.withChildren(left: newLeft)));
  }

  /// Update an item (e.g., after trim)
  PersistentTimeline updateItem(String itemId, TimelineItem newItem) {
    if (root == null) return this;
    return PersistentTimeline(_updateItem(root!, itemId, newItem));
  }

  TimelineNode _updateItem(TimelineNode node, String itemId, TimelineItem newItem) {
    if (node.item.id == itemId) {
      return node.withItem(newItem);
    }

    if (node.left != null && _contains(node.left!, itemId)) {
      return node.withChildren(left: _updateItem(node.left!, itemId, newItem));
    }

    if (node.right != null && _contains(node.right!, itemId)) {
      return node.withChildren(right: _updateItem(node.right!, itemId, newItem));
    }

    return node;
  }

  // ============ AVL BALANCING ============

  TimelineNode _balance(TimelineNode node) {
    final bf = node.balanceFactor;

    if (bf > 1) {
      // Left heavy
      if ((node.left?.balanceFactor ?? 0) < 0) {
        // Left-Right case
        return _rotateRight(node.withChildren(
          left: _rotateLeft(node.left!),
        ));
      }
      // Left-Left case
      return _rotateRight(node);
    }

    if (bf < -1) {
      // Right heavy
      if ((node.right?.balanceFactor ?? 0) > 0) {
        // Right-Left case
        return _rotateLeft(node.withChildren(
          right: _rotateRight(node.right!),
        ));
      }
      // Right-Right case
      return _rotateLeft(node);
    }

    return node;
  }

  TimelineNode _rotateRight(TimelineNode y) {
    final x = y.left!;
    final t2 = x.right;

    return x.withChildren(
      right: y.withChildren(left: t2),
    );
  }

  TimelineNode _rotateLeft(TimelineNode x) {
    final y = x.right!;
    final t2 = y.left;

    return y.withChildren(
      left: x.withChildren(right: t2),
    );
  }

  // ============ SERIALIZATION ============

  List<Map<String, dynamic>> toJson() =>
      toList().map((item) => item.toJson()).toList();

  factory PersistentTimeline.fromList(List<TimelineItem> items) {
    var timeline = PersistentTimeline.empty;
    for (final item in items) {
      timeline = timeline.append(item);
    }
    return timeline;
  }
}
```

### 6.6 Timeline Manager with Undo/Redo

```dart
/// Manages timeline state with undo/redo support
class TimelineManager extends ChangeNotifier {
  /// Current timeline (immutable)
  PersistentTimeline _current;

  /// Undo stack (previous timeline roots)
  final List<PersistentTimeline> _undoStack = [];

  /// Redo stack (undone timeline roots)
  final List<PersistentTimeline> _redoStack = [];

  /// Maximum undo history
  static const int maxUndoHistory = 100;

  /// Currently selected item ID
  String? _selectedItemId;

  /// Dirty flag for composition rebuild
  bool _compositionDirty = true;

  TimelineManager() : _current = PersistentTimeline.empty;

  // ============ GETTERS ============

  PersistentTimeline get timeline => _current;
  int get totalDurationMicros => _current.totalDurationMicros;
  Duration get totalDuration => _current.totalDuration;
  int get itemCount => _current.count;
  bool get isEmpty => _current.isEmpty;

  String? get selectedItemId => _selectedItemId;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get compositionDirty => _compositionDirty;

  // ============ QUERIES (O(log n)) ============

  (TimelineItem, int)? itemAtTime(int timeMicros) =>
      _current.itemAtTime(timeMicros);

  int? startTimeOf(String itemId) => _current.startTimeOf(itemId);

  TimelineItem? getById(String itemId) => _current.getById(itemId);

  List<TimelineItem> get items => _current.toList();

  // ============ MUTATIONS ============

  /// Execute a mutation that returns a new timeline
  void _execute(PersistentTimeline Function() mutation) {
    // Save current state for undo
    _undoStack.add(_current);
    if (_undoStack.length > maxUndoHistory) {
      _undoStack.removeAt(0);
    }

    // Clear redo stack
    _redoStack.clear();

    // Apply mutation
    _current = mutation();
    _compositionDirty = true;

    notifyListeners();
  }

  /// Insert item at time position
  void insertAt(int timeMicros, TimelineItem item) {
    _execute(() => _current.insertAt(timeMicros, item));
  }

  /// Append item at end
  void append(TimelineItem item) {
    _execute(() => _current.append(item));
  }

  /// Remove item by ID
  void remove(String itemId) {
    _execute(() => _current.remove(itemId));
    if (_selectedItemId == itemId) {
      _selectedItemId = null;
    }
  }

  /// Update item
  void updateItem(String itemId, TimelineItem newItem) {
    _execute(() => _current.updateItem(itemId, newItem));
  }

  /// Split item at time position
  void splitAt(int timeMicros) {
    final result = _current.itemAtTime(timeMicros);
    if (result == null) return;

    final (item, offsetWithin) = result;
    if (item is! VideoClip) return; // Can only split video clips

    // Don't split at very start or end
    if (offsetWithin < 100000 || // 100ms minimum
        offsetWithin > item.durationMicroseconds - 100000) {
      return;
    }

    final split = item.splitAt(offsetWithin);
    if (split == null) return;

    _execute(() {
      var timeline = _current.remove(item.id);
      final startTime = _current.startTimeOf(item.id) ?? 0;
      timeline = timeline.insertAt(startTime, split.left);
      timeline = timeline.insertAt(startTime + split.left.durationMicroseconds, split.right);
      return timeline;
    });

    _selectedItemId = split.right.id;
  }

  /// Trim item start
  void trimStart(String itemId, int newInPointMicros) {
    final item = _current.getById(itemId);
    if (item == null || item is! VideoClip) return;

    final trimmed = item.trimStart(newInPointMicros);
    if (trimmed == null) return;

    _execute(() => _current.updateItem(itemId, trimmed));
  }

  /// Trim item end
  void trimEnd(String itemId, int newOutPointMicros) {
    final item = _current.getById(itemId);
    if (item == null || item is! VideoClip) return;

    final trimmed = item.trimEnd(newOutPointMicros);
    if (trimmed == null) return;

    _execute(() => _current.updateItem(itemId, trimmed));
  }

  // ============ UNDO / REDO (O(1)) ============

  /// Undo last operation - O(1) pointer swap
  void undo() {
    if (_undoStack.isEmpty) return;

    _redoStack.add(_current);
    _current = _undoStack.removeLast();
    _compositionDirty = true;

    notifyListeners();
  }

  /// Redo last undone operation - O(1) pointer swap
  void redo() {
    if (_redoStack.isEmpty) return;

    _undoStack.add(_current);
    _current = _redoStack.removeLast();
    _compositionDirty = true;

    notifyListeners();
  }

  // ============ SELECTION ============

  void selectItem(String? itemId) {
    _selectedItemId = itemId;
    notifyListeners();
  }

  // ============ COMPOSITION ============

  void markCompositionClean() {
    _compositionDirty = false;
  }

  // ============ SERIALIZATION ============

  List<Map<String, dynamic>> toJson() => _current.toJson();

  void loadFromJson(List<dynamic> json) {
    final items = json
        .map((item) => TimelineItem.fromJson(item as Map<String, dynamic>))
        .toList();
    _current = PersistentTimeline.fromList(items);
    _undoStack.clear();
    _redoStack.clear();
    _compositionDirty = true;
    notifyListeners();
  }

  void clear() {
    _current = PersistentTimeline.empty;
    _undoStack.clear();
    _redoStack.clear();
    _selectedItemId = null;
    _compositionDirty = true;
    notifyListeners();
  }
}
```

### 6.7 Complexity Analysis

| Operation | Complexity | Notes |
|-----------|------------|-------|
| `itemAtTime(t)` | O(log n) | Binary search via subtree durations |
| `startTimeOf(id)` | O(n) | Could optimize with additional index |
| `getById(id)` | O(n) | Could optimize with HashMap |
| `insertAt(t, item)` | O(log n) | Path copying + rebalancing |
| `remove(id)` | O(log n) | Path copying + rebalancing |
| `updateItem(id, item)` | O(log n) | Path copying only |
| `splitAt(t)` | O(log n) | One remove + two inserts |
| `undo()` | O(1) | Pointer swap |
| `redo()` | O(1) | Pointer swap |
| `toList()` | O(n) | In-order traversal |
| Memory per edit | O(log n) | Only path nodes copied |

### 6.8 Memory Analysis

For a timeline with n items and k edits:

```
Base tree:         O(n) nodes
After k edits:     O(n + k log n) nodes total
Undo stack (100):  O(1) pointers (trees share structure)

Example:
- 500 clips
- 100 edits
- ~500 + 100×10 = 1500 nodes total
- Each node ~100 bytes = 150KB

Very memory efficient due to structural sharing.
```

---

## 7. Component Design: Time & Frame System

### 7.1 Overview

The Time & Frame System provides:
- Microsecond-precision time storage (no floating-point drift)
- Rational frame rates for broadcast accuracy
- Frame snapping to source video boundaries
- SMPTE timecode display

### 7.2 Core Time Types

```dart
/// Time value in microseconds
/// Use this for all internal time storage
typedef TimeMicros = int;

/// Extension methods for working with microsecond times
extension TimeMicrosExtension on int {
  /// Convert to Duration
  Duration get asDuration => Duration(microseconds: this);

  /// Convert to seconds (for display only)
  double get asSeconds => this / 1000000.0;

  /// Convert to milliseconds (for legacy compatibility)
  int get asMilliseconds => this ~/ 1000;

  /// Format as timecode (HH:MM:SS.mmm)
  String formatTimecode() {
    final hours = this ~/ 3600000000;
    final minutes = (this ~/ 60000000) % 60;
    final seconds = (this ~/ 1000000) % 60;
    final millis = (this ~/ 1000) % 1000;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}.'
          '${millis.toString().padLeft(3, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  /// Format as SMPTE timecode with frame number
  String formatSMPTE(Rational frameRate, {bool dropFrame = false}) {
    final totalFrames = frameRate.microsecondsToFrame(this);
    return _framesToSMPTE(totalFrames, frameRate, dropFrame: dropFrame);
  }
}

/// Convert frame count to SMPTE timecode
String _framesToSMPTE(int frames, Rational fps, {bool dropFrame = false}) {
  final fpsRounded = fps.value.round();

  int f = frames;

  // Drop frame compensation for 29.97/59.94
  if (dropFrame && (fpsRounded == 30 || fpsRounded == 60)) {
    final dropRate = fpsRounded == 30 ? 2 : 4;
    final framesPerMin = fpsRounded * 60 - dropRate;
    final framesPer10Min = framesPerMin * 10 + dropRate;

    final d = f ~/ framesPer10Min;
    final m = f % framesPer10Min;

    if (m >= dropRate) {
      f += dropRate * (9 * d + (m - dropRate) ~/ framesPerMin);
    } else {
      f += dropRate * 9 * d;
    }
  }

  final ff = f % fpsRounded;
  final ss = (f ~/ fpsRounded) % 60;
  final mm = (f ~/ (fpsRounded * 60)) % 60;
  final hh = f ~/ (fpsRounded * 3600);

  final separator = dropFrame ? ';' : ':';

  return '${hh.toString().padLeft(2, '0')}:'
      '${mm.toString().padLeft(2, '0')}:'
      '${ss.toString().padLeft(2, '0')}$separator'
      '${ff.toString().padLeft(2, '0')}';
}

/// Duration extension for microseconds
extension DurationMicrosExtension on Duration {
  /// Get microseconds as int64
  int get inMicrosecondsInt => inMicroseconds;
}
```

### 7.3 Frame Snapping

```dart
/// Utility for snapping times to frame boundaries
class FrameSnapper {
  final Rational frameRate;

  const FrameSnapper(this.frameRate);

  /// Snap time to nearest frame boundary
  int snapToNearestFrame(int timeMicros) {
    final frame = frameRate.microsecondsToFrame(timeMicros);
    return frameRate.frameToMicroseconds(frame);
  }

  /// Snap time to previous frame boundary (floor)
  int snapToPreviousFrame(int timeMicros) {
    final frame = frameRate.microsecondsToFrame(timeMicros);
    return frameRate.frameToMicroseconds(frame);
  }

  /// Snap time to next frame boundary (ceiling)
  int snapToNextFrame(int timeMicros) {
    final frame = frameRate.microsecondsToFrame(timeMicros);
    final snapped = frameRate.frameToMicroseconds(frame);
    if (snapped < timeMicros) {
      return frameRate.frameToMicroseconds(frame + 1);
    }
    return snapped;
  }

  /// Get frame number at time
  int frameAt(int timeMicros) => frameRate.microsecondsToFrame(timeMicros);

  /// Get time at frame
  int timeAt(int frame) => frameRate.frameToMicroseconds(frame);

  /// Get frame duration in microseconds
  int get frameDurationMicros => frameRate.microsecondsPerFrame;
}
```

### 7.4 Time Range

```dart
/// Represents a time range with microsecond precision
class TimeRange {
  final int startMicros;
  final int endMicros;

  const TimeRange(this.startMicros, this.endMicros);

  /// Duration of the range
  int get durationMicros => endMicros - startMicros;

  Duration get duration => Duration(microseconds: durationMicros);

  /// Check if a time is within this range
  bool contains(int timeMicros) =>
      timeMicros >= startMicros && timeMicros < endMicros;

  /// Check if ranges overlap
  bool overlaps(TimeRange other) =>
      startMicros < other.endMicros && endMicros > other.startMicros;

  /// Get intersection with another range
  TimeRange? intersection(TimeRange other) {
    final start = startMicros > other.startMicros ? startMicros : other.startMicros;
    final end = endMicros < other.endMicros ? endMicros : other.endMicros;
    if (start >= end) return null;
    return TimeRange(start, end);
  }

  /// Snap to frame boundaries
  TimeRange snapToFrames(FrameSnapper snapper) => TimeRange(
    snapper.snapToPreviousFrame(startMicros),
    snapper.snapToNextFrame(endMicros),
  );

  @override
  bool operator ==(Object other) =>
      other is TimeRange &&
      startMicros == other.startMicros &&
      endMicros == other.endMicros;

  @override
  int get hashCode => Object.hash(startMicros, endMicros);

  Map<String, dynamic> toJson() => {
    'startMicros': startMicros,
    'endMicros': endMicros,
  };

  factory TimeRange.fromJson(Map<String, dynamic> json) => TimeRange(
    json['startMicros'] as int,
    json['endMicros'] as int,
  );
}
```

---

## 8. Component Design: Clip Type Hierarchy

### 8.1 Overview

The clip type hierarchy provides a polymorphic, extensible system for different content types on the timeline.

### 8.2 Class Hierarchy

```
TimelineItem (abstract)
├── MediaClip (abstract) - clips that reference external media
│   ├── VideoClip - video segment from a MediaAsset
│   ├── ImageClip - still image with duration
│   └── AudioClip - audio-only segment
├── GeneratorClip (abstract) - clips that generate content
│   ├── GapClip - empty space / silence
│   ├── ColorClip - solid color
│   └── TitleClip - text overlay (future)
└── CompoundClip - nested timeline (future)
```

### 8.3 Base Classes

```dart
/// Abstract base for all timeline items
abstract class TimelineItem {
  /// Unique identifier
  final String id;

  /// Duration in microseconds
  int get durationMicroseconds;

  /// Duration as Duration object
  Duration get duration => Duration(microseconds: durationMicroseconds);

  /// Human-readable name
  String get displayName;

  /// Item type for serialization
  String get itemType;

  const TimelineItem({required this.id});

  /// Serialize to JSON
  Map<String, dynamic> toJson();

  /// Deserialize from JSON
  static TimelineItem fromJson(Map<String, dynamic> json) {
    final type = json['itemType'] as String;

    switch (type) {
      case 'video':
        return VideoClip.fromJson(json);
      case 'image':
        return ImageClip.fromJson(json);
      case 'audio':
        return AudioClip.fromJson(json);
      case 'gap':
        return GapClip.fromJson(json);
      case 'color':
        return ColorClip.fromJson(json);
      default:
        throw ArgumentError('Unknown item type: $type');
    }
  }
}

/// Abstract base for clips that reference external media
abstract class MediaClip extends TimelineItem {
  /// ID of the source MediaAsset
  final String mediaAssetId;

  /// Start point in source media (microseconds)
  final int sourceInMicros;

  /// End point in source media (microseconds)
  final int sourceOutMicros;

  @override
  int get durationMicroseconds => sourceOutMicros - sourceInMicros;

  /// Source time range
  TimeRange get sourceRange => TimeRange(sourceInMicros, sourceOutMicros);

  const MediaClip({
    required super.id,
    required this.mediaAssetId,
    required this.sourceInMicros,
    required this.sourceOutMicros,
  });

  /// Map timeline offset to source time
  int timelineToSource(int offsetMicros) => sourceInMicros + offsetMicros;

  /// Map source time to timeline offset
  int sourceToTimeline(int sourceMicros) => sourceMicros - sourceInMicros;
}

/// Abstract base for clips that generate content (no external media)
abstract class GeneratorClip extends TimelineItem {
  /// Duration in microseconds
  final int _durationMicroseconds;

  @override
  int get durationMicroseconds => _durationMicroseconds;

  const GeneratorClip({
    required super.id,
    required int durationMicroseconds,
  }) : _durationMicroseconds = durationMicroseconds;
}
```

### 8.4 Concrete Clip Types

```dart
/// Video clip - segment from a video MediaAsset
class VideoClip extends MediaClip {
  /// Keyframes for this clip (timestamps relative to clip start)
  final List<Keyframe> keyframes;

  /// Optional display name override
  final String? name;

  @override
  String get displayName => name ?? 'Video Clip';

  @override
  String get itemType => 'video';

  const VideoClip({
    required super.id,
    required super.mediaAssetId,
    required super.sourceInMicros,
    required super.sourceOutMicros,
    this.keyframes = const [],
    this.name,
  });

  /// Split clip at offset (relative to clip start)
  /// Returns (left, right) clips or null if invalid
  ({VideoClip left, VideoClip right})? splitAt(int offsetMicros) {
    // Validate split point
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
        .map((kf) => kf.withTimestamp(kf.timestampMicros - offsetMicros))
        .toList();

    final left = VideoClip(
      id: const Uuid().v4(),
      mediaAssetId: mediaAssetId,
      sourceInMicros: sourceInMicros,
      sourceOutMicros: sourceInMicros + offsetMicros,
      keyframes: leftKeyframes,
      name: name != null ? '$name (1)' : null,
    );

    final right = VideoClip(
      id: const Uuid().v4(),
      mediaAssetId: mediaAssetId,
      sourceInMicros: sourceInMicros + offsetMicros,
      sourceOutMicros: sourceOutMicros,
      keyframes: rightKeyframes,
      name: name != null ? '$name (2)' : null,
    );

    return (left: left, right: right);
  }

  /// Trim start, returns new clip or null if invalid
  VideoClip? trimStart(int newInMicros) {
    if (newInMicros <= sourceInMicros || newInMicros >= sourceOutMicros) {
      return null;
    }

    const minDuration = 100000;
    if (sourceOutMicros - newInMicros < minDuration) return null;

    final trimAmount = newInMicros - sourceInMicros;

    // Remove keyframes before trim, adjust remaining
    final newKeyframes = keyframes
        .where((kf) => kf.timestampMicros >= trimAmount)
        .map((kf) => kf.withTimestamp(kf.timestampMicros - trimAmount))
        .toList();

    return VideoClip(
      id: id,
      mediaAssetId: mediaAssetId,
      sourceInMicros: newInMicros,
      sourceOutMicros: sourceOutMicros,
      keyframes: newKeyframes,
      name: name,
    );
  }

  /// Trim end, returns new clip or null if invalid
  VideoClip? trimEnd(int newOutMicros) {
    if (newOutMicros >= sourceOutMicros || newOutMicros <= sourceInMicros) {
      return null;
    }

    const minDuration = 100000;
    if (newOutMicros - sourceInMicros < minDuration) return null;

    final newDuration = newOutMicros - sourceInMicros;

    // Remove keyframes after trim
    final newKeyframes = keyframes
        .where((kf) => kf.timestampMicros < newDuration)
        .toList();

    return VideoClip(
      id: id,
      mediaAssetId: mediaAssetId,
      sourceInMicros: sourceInMicros,
      sourceOutMicros: newOutMicros,
      keyframes: newKeyframes,
      name: name,
    );
  }

  /// Add keyframe
  VideoClip addKeyframe(Keyframe keyframe) => VideoClip(
    id: id,
    mediaAssetId: mediaAssetId,
    sourceInMicros: sourceInMicros,
    sourceOutMicros: sourceOutMicros,
    keyframes: [...keyframes, keyframe],
    name: name,
  );

  /// Remove keyframe
  VideoClip removeKeyframe(String keyframeId) => VideoClip(
    id: id,
    mediaAssetId: mediaAssetId,
    sourceInMicros: sourceInMicros,
    sourceOutMicros: sourceOutMicros,
    keyframes: keyframes.where((kf) => kf.id != keyframeId).toList(),
    name: name,
  );

  @override
  Map<String, dynamic> toJson() => {
    'itemType': itemType,
    'id': id,
    'mediaAssetId': mediaAssetId,
    'sourceInMicros': sourceInMicros,
    'sourceOutMicros': sourceOutMicros,
    'keyframes': keyframes.map((kf) => kf.toJson()).toList(),
    'name': name,
  };

  factory VideoClip.fromJson(Map<String, dynamic> json) => VideoClip(
    id: json['id'] as String,
    mediaAssetId: json['mediaAssetId'] as String,
    sourceInMicros: json['sourceInMicros'] as int,
    sourceOutMicros: json['sourceOutMicros'] as int,
    keyframes: (json['keyframes'] as List?)
        ?.map((kf) => Keyframe.fromJson(kf as Map<String, dynamic>))
        .toList() ?? [],
    name: json['name'] as String?,
  );
}

/// Image clip - still image displayed for a duration
class ImageClip extends MediaClip {
  /// Optional display name
  final String? name;

  @override
  String get displayName => name ?? 'Image';

  @override
  String get itemType => 'image';

  const ImageClip({
    required super.id,
    required super.mediaAssetId,
    required int durationMicroseconds,
    this.name,
  }) : super(
    sourceInMicros: 0,
    sourceOutMicros: durationMicroseconds,
  );

  /// Change duration
  ImageClip withDuration(int newDurationMicros) => ImageClip(
    id: id,
    mediaAssetId: mediaAssetId,
    durationMicroseconds: newDurationMicros,
    name: name,
  );

  @override
  Map<String, dynamic> toJson() => {
    'itemType': itemType,
    'id': id,
    'mediaAssetId': mediaAssetId,
    'durationMicros': durationMicroseconds,
    'name': name,
  };

  factory ImageClip.fromJson(Map<String, dynamic> json) => ImageClip(
    id: json['id'] as String,
    mediaAssetId: json['mediaAssetId'] as String,
    durationMicroseconds: json['durationMicros'] as int,
    name: json['name'] as String?,
  );
}

/// Audio clip - audio segment from an audio/video MediaAsset
class AudioClip extends MediaClip {
  /// Optional display name
  final String? name;

  /// Volume level (0.0 - 1.0)
  final double volume;

  @override
  String get displayName => name ?? 'Audio';

  @override
  String get itemType => 'audio';

  const AudioClip({
    required super.id,
    required super.mediaAssetId,
    required super.sourceInMicros,
    required super.sourceOutMicros,
    this.name,
    this.volume = 1.0,
  });

  @override
  Map<String, dynamic> toJson() => {
    'itemType': itemType,
    'id': id,
    'mediaAssetId': mediaAssetId,
    'sourceInMicros': sourceInMicros,
    'sourceOutMicros': sourceOutMicros,
    'name': name,
    'volume': volume,
  };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
    id: json['id'] as String,
    mediaAssetId: json['mediaAssetId'] as String,
    sourceInMicros: json['sourceInMicros'] as int,
    sourceOutMicros: json['sourceOutMicros'] as int,
    name: json['name'] as String?,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
  );
}

/// Gap clip - empty space / silence
class GapClip extends GeneratorClip {
  @override
  String get displayName => 'Gap';

  @override
  String get itemType => 'gap';

  const GapClip({
    required super.id,
    required super.durationMicroseconds,
  });

  /// Change duration
  GapClip withDuration(int newDurationMicros) => GapClip(
    id: id,
    durationMicroseconds: newDurationMicros,
  );

  @override
  Map<String, dynamic> toJson() => {
    'itemType': itemType,
    'id': id,
    'durationMicros': durationMicroseconds,
  };

  factory GapClip.fromJson(Map<String, dynamic> json) => GapClip(
    id: json['id'] as String,
    durationMicroseconds: json['durationMicros'] as int,
  );
}

/// Color clip - solid color for a duration
class ColorClip extends GeneratorClip {
  /// Color as ARGB int
  final int colorValue;

  @override
  String get displayName => 'Color';

  @override
  String get itemType => 'color';

  const ColorClip({
    required super.id,
    required super.durationMicroseconds,
    required this.colorValue,
  });

  /// Get as Flutter Color
  Color get color => Color(colorValue);

  /// Create black clip
  factory ColorClip.black({
    required String id,
    required int durationMicroseconds,
  }) => ColorClip(
    id: id,
    durationMicroseconds: durationMicroseconds,
    colorValue: 0xFF000000,
  );

  /// Create white clip
  factory ColorClip.white({
    required String id,
    required int durationMicroseconds,
  }) => ColorClip(
    id: id,
    durationMicroseconds: durationMicroseconds,
    colorValue: 0xFFFFFFFF,
  );

  @override
  Map<String, dynamic> toJson() => {
    'itemType': itemType,
    'id': id,
    'durationMicros': durationMicroseconds,
    'colorValue': colorValue,
  };

  factory ColorClip.fromJson(Map<String, dynamic> json) => ColorClip(
    id: json['id'] as String,
    durationMicroseconds: json['durationMicros'] as int,
    colorValue: json['colorValue'] as int,
  );
}
```

---

## 9. Component Design: Playback Engine

### 9.1 Overview

The Playback Engine provides seamless, uninterrupted video playback with:
- Double-buffered AVComposition for zero-interruption editing during playback
- Pre-warmed decoder pool for instant multi-source transitions
- Background composition rebuilding with atomic hot-swap

### 9.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PLAYBACK ENGINE                                      │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    COMPOSITION MANAGER                               │   │
│  │                                                                      │   │
│  │    ┌──────────────────┐      ┌──────────────────┐                  │   │
│  │    │   ACTIVE         │      │   BUILDING       │                  │   │
│  │    │   Composition A  │      │   Composition B  │                  │   │
│  │    │   (playing)      │◄────►│   (background)   │                  │   │
│  │    └──────────────────┘      └──────────────────┘                  │   │
│  │              │                        ▲                             │   │
│  │              │                        │                             │   │
│  │              ▼                        │                             │   │
│  │    ┌──────────────────┐      ┌──────────────────┐                  │   │
│  │    │    AVPlayer      │      │  Build Thread    │                  │   │
│  │    │    (rendering)   │      │  (async rebuild) │                  │   │
│  │    └──────────────────┘      └──────────────────┘                  │   │
│  │                                                                      │   │
│  │    On timeline edit:                                                │   │
│  │    1. Continue playing Composition A                                │   │
│  │    2. Build new Composition B in background                         │   │
│  │    3. At safe point, atomic swap A ↔ B                             │   │
│  │    4. Seek B to current playhead                                    │   │
│  │    5. Zero visible interruption                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     DECODER POOL                                     │   │
│  │                                                                      │   │
│  │    For scrubbing across multi-source clips:                         │   │
│  │                                                                      │   │
│  │    ┌────────────┐  ┌────────────┐  ┌────────────┐                  │   │
│  │    │  Decoder 1 │  │  Decoder 2 │  │  Decoder 3 │                  │   │
│  │    │  V1 (active)│  │  V2 (warm) │  │  (standby) │                  │   │
│  │    └────────────┘  └────────────┘  └────────────┘                  │   │
│  │                                                                      │   │
│  │    Warm = seeked to next clip's start, ready for instant switch    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 9.3 Composition Manager

```dart
/// Manages AVComposition building and hot-swapping
class CompositionManager {
  /// Media asset registry for resolving asset paths
  final MediaAssetRegistry _assetRegistry;

  /// Platform channel for native AVComposition
  static const _channel = MethodChannel('com.liquideditor/composition');

  /// Active composition ID (native side)
  String? _activeCompositionId;

  /// Building composition ID (native side)
  String? _buildingCompositionId;

  /// Whether a build is in progress
  bool _isBuilding = false;

  /// Queued timeline for rebuild (if edit during build)
  PersistentTimeline? _queuedTimeline;

  /// Callback when composition is ready
  void Function()? onCompositionReady;

  CompositionManager(this._assetRegistry);

  /// Build composition from timeline (background thread)
  Future<void> buildComposition(PersistentTimeline timeline) async {
    if (_isBuilding) {
      // Queue this timeline for after current build
      _queuedTimeline = timeline;
      return;
    }

    _isBuilding = true;

    try {
      // Build composition data
      final segments = <Map<String, dynamic>>[];

      for (final item in timeline.toList()) {
        if (item is VideoClip) {
          final asset = _assetRegistry.getById(item.mediaAssetId);
          if (asset == null) continue;

          segments.add({
            'type': 'video',
            'assetPath': asset.relativePath,
            'startMicros': item.sourceInMicros,
            'endMicros': item.sourceOutMicros,
          });
        } else if (item is ImageClip) {
          final asset = _assetRegistry.getById(item.mediaAssetId);
          if (asset == null) continue;

          segments.add({
            'type': 'image',
            'assetPath': asset.relativePath,
            'durationMicros': item.durationMicroseconds,
          });
        } else if (item is GapClip) {
          segments.add({
            'type': 'gap',
            'durationMicros': item.durationMicroseconds,
          });
        } else if (item is ColorClip) {
          segments.add({
            'type': 'color',
            'colorValue': item.colorValue,
            'durationMicros': item.durationMicroseconds,
          });
        }
      }

      // Call native to build composition
      final result = await _channel.invokeMethod('buildComposition', {
        'segments': segments,
      });

      _buildingCompositionId = result['compositionId'] as String;

      onCompositionReady?.call();
    } finally {
      _isBuilding = false;

      // Process queued timeline if any
      if (_queuedTimeline != null) {
        final queued = _queuedTimeline!;
        _queuedTimeline = null;
        await buildComposition(queued);
      }
    }
  }

  /// Hot-swap to the newly built composition
  /// Returns the playhead position to seek to
  Future<void> hotSwap(int currentPlayheadMicros) async {
    if (_buildingCompositionId == null) return;

    await _channel.invokeMethod('hotSwapComposition', {
      'newCompositionId': _buildingCompositionId,
      'seekToMicros': currentPlayheadMicros,
    });

    // Swap IDs
    final oldActive = _activeCompositionId;
    _activeCompositionId = _buildingCompositionId;
    _buildingCompositionId = oldActive; // Reuse for next build
  }

  /// Check if hot-swap is ready
  bool get isSwapReady => _buildingCompositionId != null && !_isBuilding;

  /// Dispose compositions
  Future<void> dispose() async {
    if (_activeCompositionId != null) {
      await _channel.invokeMethod('disposeComposition', {
        'compositionId': _activeCompositionId,
      });
    }
    if (_buildingCompositionId != null) {
      await _channel.invokeMethod('disposeComposition', {
        'compositionId': _buildingCompositionId,
      });
    }
  }
}
```

### 9.4 Decoder Pool (for Scrubbing)

```dart
/// Pool of video decoders for multi-source scrubbing
class DecoderPool {
  /// Maximum number of decoders
  static const int maxDecoders = 3;

  /// Platform channel
  static const _channel = MethodChannel('com.liquideditor/decoder_pool');

  /// Active decoders by asset ID
  final Map<String, String> _decodersByAsset = {}; // assetId -> decoderId

  /// LRU order for eviction
  final List<String> _lruOrder = [];

  /// Currently active decoder
  String? _activeDecoderId;

  /// Get or create decoder for an asset
  Future<String> getDecoder(MediaAsset asset) async {
    // Check if already have decoder for this asset
    if (_decodersByAsset.containsKey(asset.id)) {
      final decoderId = _decodersByAsset[asset.id]!;
      _touchLRU(asset.id);
      return decoderId;
    }

    // Need to create new decoder
    // First, evict if at capacity
    if (_decodersByAsset.length >= maxDecoders) {
      await _evictLRU();
    }

    // Create decoder
    final result = await _channel.invokeMethod('createDecoder', {
      'assetPath': asset.relativePath,
    });

    final decoderId = result['decoderId'] as String;
    _decodersByAsset[asset.id] = decoderId;
    _lruOrder.add(asset.id);

    return decoderId;
  }

  /// Pre-warm decoder for upcoming clip
  Future<void> warmDecoder(MediaAsset asset, int seekToMicros) async {
    final decoderId = await getDecoder(asset);

    await _channel.invokeMethod('seekDecoder', {
      'decoderId': decoderId,
      'seekToMicros': seekToMicros,
    });
  }

  /// Switch active decoder
  Future<void> switchTo(MediaAsset asset) async {
    final decoderId = await getDecoder(asset);

    if (_activeDecoderId != decoderId) {
      _activeDecoderId = decoderId;
      await _channel.invokeMethod('activateDecoder', {
        'decoderId': decoderId,
      });
    }
  }

  /// Decode frame at position
  Future<void> seekActive(int timeMicros) async {
    if (_activeDecoderId == null) return;

    await _channel.invokeMethod('seekDecoder', {
      'decoderId': _activeDecoderId,
      'seekToMicros': timeMicros,
    });
  }

  void _touchLRU(String assetId) {
    _lruOrder.remove(assetId);
    _lruOrder.add(assetId);
  }

  Future<void> _evictLRU() async {
    if (_lruOrder.isEmpty) return;

    final evictAssetId = _lruOrder.removeAt(0);
    final evictDecoderId = _decodersByAsset.remove(evictAssetId);

    if (evictDecoderId != null) {
      await _channel.invokeMethod('disposeDecoder', {
        'decoderId': evictDecoderId,
      });
    }
  }

  Future<void> dispose() async {
    for (final decoderId in _decodersByAsset.values) {
      await _channel.invokeMethod('disposeDecoder', {
        'decoderId': decoderId,
      });
    }
    _decodersByAsset.clear();
    _lruOrder.clear();
    _activeDecoderId = null;
  }
}
```

### 9.5 Playback Controller (Orchestrator)

```dart
/// Main playback controller orchestrating all playback components
class PlaybackEngineController extends ChangeNotifier {
  final TimelineManager _timelineManager;
  final MediaAssetRegistry _assetRegistry;

  late final CompositionManager _compositionManager;
  late final DecoderPool _decoderPool;
  late final FrameCache _frameCache;

  /// Platform channel for player control
  static const _channel = MethodChannel('com.liquideditor/player');

  /// Current playhead position (microseconds)
  int _playheadMicros = 0;

  /// Whether currently playing
  bool _isPlaying = false;

  /// Current playback rate
  double _playbackRate = 1.0;

  /// Volume
  double _volume = 1.0;

  /// Loading state
  bool _isLoading = true;

  /// Error state
  String? _error;

  PlaybackEngineController({
    required TimelineManager timelineManager,
    required MediaAssetRegistry assetRegistry,
  }) : _timelineManager = timelineManager,
       _assetRegistry = assetRegistry {
    _compositionManager = CompositionManager(_assetRegistry);
    _decoderPool = DecoderPool();
    _frameCache = FrameCache();

    // Listen for timeline changes
    _timelineManager.addListener(_onTimelineChanged);

    // Set up composition ready callback
    _compositionManager.onCompositionReady = _onCompositionReady;
  }

  // ============ GETTERS ============

  int get playheadMicros => _playheadMicros;
  Duration get playhead => Duration(microseconds: _playheadMicros);
  bool get isPlaying => _isPlaying;
  double get playbackRate => _playbackRate;
  double get volume => _volume;
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get progress {
    final total = _timelineManager.totalDurationMicros;
    if (total == 0) return 0;
    return _playheadMicros / total;
  }

  // ============ TIMELINE CHANGE HANDLING ============

  void _onTimelineChanged() {
    if (_timelineManager.compositionDirty) {
      // Trigger background rebuild
      _compositionManager.buildComposition(_timelineManager.timeline);
    }
  }

  void _onCompositionReady() {
    if (_isPlaying && _compositionManager.isSwapReady) {
      // Hot-swap while playing
      _compositionManager.hotSwap(_playheadMicros);
      _timelineManager.markCompositionClean();
    }
  }

  // ============ PLAYBACK CONTROLS ============

  Future<void> play() async {
    if (_isPlaying) return;

    // Ensure composition is current
    if (_timelineManager.compositionDirty) {
      await _compositionManager.buildComposition(_timelineManager.timeline);
      await _compositionManager.hotSwap(_playheadMicros);
      _timelineManager.markCompositionClean();
    }

    _isPlaying = true;
    await _channel.invokeMethod('play');
    _startPlayheadUpdates();
    notifyListeners();
  }

  Future<void> pause() async {
    if (!_isPlaying) return;

    _isPlaying = false;
    await _channel.invokeMethod('pause');
    _stopPlayheadUpdates();
    notifyListeners();
  }

  Future<void> togglePlayback() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(int timeMicros) async {
    _playheadMicros = timeMicros.clamp(0, _timelineManager.totalDurationMicros);

    // For scrubbing, use decoder pool for multi-source
    final result = _timelineManager.itemAtTime(_playheadMicros);
    if (result != null) {
      final (item, offsetWithin) = result;
      if (item is VideoClip) {
        final asset = _assetRegistry.getById(item.mediaAssetId);
        if (asset != null) {
          await _decoderPool.switchTo(asset);
          await _decoderPool.seekActive(item.sourceInMicros + offsetWithin);
        }
      }
    }

    // If playing, also update composition player
    if (_isPlaying) {
      await _channel.invokeMethod('seek', {'timeMicros': _playheadMicros});
    }

    // Pre-warm next clip's decoder
    _preWarmNextClip();

    notifyListeners();
  }

  Future<void> seekToProgress(double progress) async {
    final timeMicros = (progress * _timelineManager.totalDurationMicros).round();
    await seek(timeMicros);
  }

  Future<void> setPlaybackRate(double rate) async {
    _playbackRate = rate;
    await _channel.invokeMethod('setPlaybackRate', {'rate': rate});
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _channel.invokeMethod('setVolume', {'volume': _volume});
    notifyListeners();
  }

  // ============ PRE-WARMING ============

  void _preWarmNextClip() {
    // Find current clip and next clip
    final items = _timelineManager.items;
    int accumulated = 0;
    int currentIndex = -1;

    for (int i = 0; i < items.length; i++) {
      if (_playheadMicros < accumulated + items[i].durationMicroseconds) {
        currentIndex = i;
        break;
      }
      accumulated += items[i].durationMicroseconds;
    }

    // Pre-warm next video clip
    for (int i = currentIndex + 1; i < items.length; i++) {
      final item = items[i];
      if (item is VideoClip) {
        final asset = _assetRegistry.getById(item.mediaAssetId);
        if (asset != null) {
          _decoderPool.warmDecoder(asset, item.sourceInMicros);
        }
        break;
      }
    }
  }

  // ============ PLAYHEAD UPDATES ============

  Timer? _playheadTimer;

  void _startPlayheadUpdates() {
    _playheadTimer?.cancel();
    _playheadTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _updatePlayhead();
    });
  }

  void _stopPlayheadUpdates() {
    _playheadTimer?.cancel();
    _playheadTimer = null;
  }

  Future<void> _updatePlayhead() async {
    if (!_isPlaying) return;

    final result = await _channel.invokeMethod('getPlayhead');
    final newPlayhead = result['timeMicros'] as int;

    if (newPlayhead != _playheadMicros) {
      _playheadMicros = newPlayhead;
      notifyListeners();

      // Check if approaching clip boundary, pre-warm next
      final result = _timelineManager.itemAtTime(_playheadMicros);
      if (result != null) {
        final (item, offsetWithin) = result;
        final remainingInClip = item.durationMicroseconds - offsetWithin;

        // Pre-warm when within 500ms of clip end
        if (remainingInClip < 500000) {
          _preWarmNextClip();
        }
      }
    }
  }

  // ============ INITIALIZATION ============

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Build initial composition
      await _compositionManager.buildComposition(_timelineManager.timeline);
      await _compositionManager.hotSwap(0);
      _timelineManager.markCompositionClean();

      _isLoading = false;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _timelineManager.removeListener(_onTimelineChanged);
    _playheadTimer?.cancel();
    _compositionManager.dispose();
    _decoderPool.dispose();
    _frameCache.dispose();
    super.dispose();
  }
}
```

---

## 10. Component Design: Frame Cache System

### 10.1 Overview

The Frame Cache System provides ultra-low latency scrubbing by:
- Caching decoded frames around the playhead
- Predictive prefetching based on scrub direction
- Instant display of cached frames (<1ms)
- Graceful degradation for cache misses (show I-frame, refine)

### 10.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FRAME CACHE SYSTEM                                   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        LRU FRAME CACHE                               │   │
│  │                                                                      │   │
│  │    Capacity: 120 frames (~2 seconds @ 60fps)                        │   │
│  │    Memory: ~250MB (1080p BGRA frames)                               │   │
│  │                                                                      │   │
│  │    ┌─────────────────────────────────────────────────────────┐     │   │
│  │    │  Frame 940 │ 941 │ 942 │ ... │ 1000 │ ... │ 1059 │ 1060 │     │   │
│  │    └─────────────────────────────────────────────────────────┘     │   │
│  │                              ▲                                       │   │
│  │                         playhead                                     │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     PREFETCH STRATEGY                                │   │
│  │                                                                      │   │
│  │    Scrub direction detection:                                        │   │
│  │    - Track last N scrub positions                                   │   │
│  │    - Calculate velocity and direction                               │   │
│  │    - Prefetch in predicted direction                                │   │
│  │                                                                      │   │
│  │    Prefetch zones:                                                  │   │
│  │    ┌────────────────┬────────────┬────────────────┐                │   │
│  │    │   Behind (20)  │  Current   │   Ahead (40)   │                │   │
│  │    └────────────────┴────────────┴────────────────┘                │   │
│  │                                                                      │   │
│  │    Ratio shifts based on scrub direction:                           │   │
│  │    - Scrubbing right: 10 behind, 50 ahead                          │   │
│  │    - Scrubbing left:  50 behind, 10 ahead                          │   │
│  │    - Stationary:      30 behind, 30 ahead                          │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    CACHE MISS HANDLING                               │   │
│  │                                                                      │   │
│  │    On cache miss (scrub to uncached position):                      │   │
│  │    1. Find nearest I-frame (keyframe) - instant                     │   │
│  │    2. Display I-frame immediately                                   │   │
│  │    3. Decode exact frame in background                              │   │
│  │    4. Swap to exact frame when ready (~30ms)                        │   │
│  │                                                                      │   │
│  │    User perception: Instant response, then refines                  │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 10.3 Implementation

```dart
/// Cached frame data
class CachedFrame {
  /// Timeline position in microseconds
  final int timeMicros;

  /// Frame image data (BGRA pixels)
  final Uint8List pixels;

  /// Frame dimensions
  final int width;
  final int height;

  /// Whether this is an exact frame or I-frame approximation
  final bool isExact;

  CachedFrame({
    required this.timeMicros,
    required this.pixels,
    required this.width,
    required this.height,
    this.isExact = true,
  });

  /// Memory size in bytes
  int get memorySizeBytes => pixels.length;
}

/// LRU Frame Cache with predictive prefetching
class FrameCache {
  /// Maximum number of frames to cache
  static const int maxFrames = 120;

  /// Maximum memory usage (bytes)
  static const int maxMemoryBytes = 300 * 1024 * 1024; // 300MB

  /// Platform channel for frame decoding
  static const _channel = MethodChannel('com.liquideditor/frame_cache');

  /// Cached frames by timeline position
  final Map<int, CachedFrame> _cache = {};

  /// LRU order (most recent at end)
  final List<int> _lruOrder = [];

  /// Current memory usage
  int _memoryUsageBytes = 0;

  /// Prefetch isolate for background decoding
  Isolate? _prefetchIsolate;
  SendPort? _prefetchSendPort;

  /// Recent scrub positions for direction detection
  final List<int> _recentPositions = [];
  static const int _positionHistorySize = 5;

  /// Current prefetch target range
  int? _prefetchStart;
  int? _prefetchEnd;

  // ============ CACHE ACCESS ============

  /// Get frame at position (instant if cached)
  CachedFrame? getFrame(int timeMicros) {
    // Round to frame boundary (assuming 60fps for cache keys)
    final cacheKey = (timeMicros ~/ 16667) * 16667;

    final frame = _cache[cacheKey];
    if (frame != null) {
      _touchLRU(cacheKey);
      return frame;
    }
    return null;
  }

  /// Check if frame is cached
  bool hasFrame(int timeMicros) {
    final cacheKey = (timeMicros ~/ 16667) * 16667;
    return _cache.containsKey(cacheKey);
  }

  /// Add frame to cache
  void addFrame(CachedFrame frame) {
    final cacheKey = (frame.timeMicros ~/ 16667) * 16667;

    // Evict if necessary
    while (_cache.length >= maxFrames ||
           _memoryUsageBytes + frame.memorySizeBytes > maxMemoryBytes) {
      if (!_evictLRU()) break;
    }

    _cache[cacheKey] = frame;
    _lruOrder.add(cacheKey);
    _memoryUsageBytes += frame.memorySizeBytes;
  }

  void _touchLRU(int cacheKey) {
    _lruOrder.remove(cacheKey);
    _lruOrder.add(cacheKey);
  }

  bool _evictLRU() {
    if (_lruOrder.isEmpty) return false;

    final evictKey = _lruOrder.removeAt(0);
    final evicted = _cache.remove(evictKey);
    if (evicted != null) {
      _memoryUsageBytes -= evicted.memorySizeBytes;
    }
    return true;
  }

  // ============ SCRUB DIRECTION DETECTION ============

  /// Record a scrub position for direction detection
  void recordScrubPosition(int timeMicros) {
    _recentPositions.add(timeMicros);
    if (_recentPositions.length > _positionHistorySize) {
      _recentPositions.removeAt(0);
    }
  }

  /// Get current scrub direction (-1 = left, 0 = stationary, 1 = right)
  int get scrubDirection {
    if (_recentPositions.length < 2) return 0;

    int forward = 0;
    int backward = 0;

    for (int i = 1; i < _recentPositions.length; i++) {
      if (_recentPositions[i] > _recentPositions[i - 1]) {
        forward++;
      } else if (_recentPositions[i] < _recentPositions[i - 1]) {
        backward++;
      }
    }

    if (forward > backward) return 1;
    if (backward > forward) return -1;
    return 0;
  }

  // ============ PREFETCHING ============

  /// Start prefetching around a position
  Future<void> prefetchAround(
    int centerMicros,
    int frameDurationMicros,
    Future<CachedFrame?> Function(int timeMicros) decodeFrame,
  ) async {
    final direction = scrubDirection;

    // Calculate prefetch range based on direction
    int behind, ahead;
    if (direction > 0) {
      behind = 10;
      ahead = 50;
    } else if (direction < 0) {
      behind = 50;
      ahead = 10;
    } else {
      behind = 30;
      ahead = 30;
    }

    final startMicros = centerMicros - (behind * frameDurationMicros);
    final endMicros = centerMicros + (ahead * frameDurationMicros);

    // Skip if already prefetching this range
    if (_prefetchStart == startMicros && _prefetchEnd == endMicros) {
      return;
    }

    _prefetchStart = startMicros;
    _prefetchEnd = endMicros;

    // Prefetch frames not in cache
    for (int t = startMicros; t <= endMicros; t += frameDurationMicros) {
      if (t < 0) continue;
      if (hasFrame(t)) continue;

      // Decode frame (this should be async/background)
      final frame = await decodeFrame(t);
      if (frame != null) {
        addFrame(frame);
      }
    }
  }

  /// Clear cache
  void clear() {
    _cache.clear();
    _lruOrder.clear();
    _memoryUsageBytes = 0;
    _recentPositions.clear();
  }

  /// Dispose resources
  void dispose() {
    clear();
    _prefetchIsolate?.kill();
  }

  // ============ STATISTICS ============

  int get frameCount => _cache.length;
  int get memoryUsageBytes => _memoryUsageBytes;
  double get memoryUsageMB => _memoryUsageBytes / (1024 * 1024);
}
```

### 10.4 Integration with Scrubbing

```dart
/// Scrub controller integrating frame cache
class ScrubController {
  final FrameCache _frameCache;
  final DecoderPool _decoderPool;
  final MediaAssetRegistry _assetRegistry;
  final TimelineManager _timelineManager;

  /// Current displayed frame
  CachedFrame? _displayedFrame;

  /// Pending exact frame decode
  bool _pendingExactDecode = false;

  /// Callback when frame is ready
  void Function(CachedFrame)? onFrameReady;

  ScrubController({
    required FrameCache frameCache,
    required DecoderPool decoderPool,
    required MediaAssetRegistry assetRegistry,
    required TimelineManager timelineManager,
  }) : _frameCache = frameCache,
       _decoderPool = decoderPool,
       _assetRegistry = assetRegistry,
       _timelineManager = timelineManager;

  /// Scrub to a position
  Future<void> scrubTo(int timeMicros) async {
    _frameCache.recordScrubPosition(timeMicros);

    // Try to get from cache first
    final cached = _frameCache.getFrame(timeMicros);
    if (cached != null && cached.isExact) {
      _displayedFrame = cached;
      onFrameReady?.call(cached);
      _triggerPrefetch(timeMicros);
      return;
    }

    // Cache miss - find the clip and decode
    final result = _timelineManager.itemAtTime(timeMicros);
    if (result == null) return;

    final (item, offsetWithin) = result;

    if (item is VideoClip) {
      final asset = _assetRegistry.getById(item.mediaAssetId);
      if (asset == null) return;

      // Get or create decoder
      await _decoderPool.switchTo(asset);

      // If we have an approximate frame, show it immediately
      if (cached != null && !cached.isExact) {
        _displayedFrame = cached;
        onFrameReady?.call(cached);
      }

      // Decode exact frame
      _pendingExactDecode = true;
      final sourceTime = item.sourceInMicros + offsetWithin;

      final frame = await _decodeFrame(asset, sourceTime, timeMicros);
      if (frame != null) {
        _frameCache.addFrame(frame);
        _displayedFrame = frame;
        onFrameReady?.call(frame);
      }

      _pendingExactDecode = false;
    }

    _triggerPrefetch(timeMicros);
  }

  Future<CachedFrame?> _decodeFrame(
    MediaAsset asset,
    int sourceTimeMicros,
    int timelineTimeMicros,
  ) async {
    // Call native decoder
    final result = await DecoderPool._channel.invokeMethod('decodeFrame', {
      'assetPath': asset.relativePath,
      'timeMicros': sourceTimeMicros,
    });

    if (result == null) return null;

    return CachedFrame(
      timeMicros: timelineTimeMicros,
      pixels: result['pixels'] as Uint8List,
      width: result['width'] as int,
      height: result['height'] as int,
      isExact: true,
    );
  }

  void _triggerPrefetch(int centerMicros) {
    // Calculate frame duration (assuming 30fps if unknown)
    const frameDurationMicros = 33333; // ~30fps

    _frameCache.prefetchAround(
      centerMicros,
      frameDurationMicros,
      (timeMicros) async {
        final result = _timelineManager.itemAtTime(timeMicros);
        if (result == null) return null;

        final (item, offsetWithin) = result;
        if (item is! VideoClip) return null;

        final asset = _assetRegistry.getById(item.mediaAssetId);
        if (asset == null) return null;

        return _decodeFrame(
          asset,
          item.sourceInMicros + offsetWithin,
          timeMicros,
        );
      },
    );
  }
}
```

---

## 11. Data Models & Serialization

### 11.1 Project Model (Updated)

```dart
/// Updated Project model with new architecture
class ProjectV3 {
  /// Unique project identifier
  final String id;

  /// Project display name
  String name;

  /// Media asset registry
  final MediaAssetRegistry mediaAssets;

  /// Timeline (persistent tree)
  PersistentTimeline timeline;

  /// Project frame rate setting
  FrameRateOption frameRate;

  /// Creation date
  final DateTime createdAt;

  /// Last modified date
  DateTime modifiedAt;

  /// Thumbnail image path (relative)
  String? thumbnailPath;

  /// Schema version
  static const int currentVersion = 3;

  ProjectV3({
    required this.id,
    required this.name,
    MediaAssetRegistry? mediaAssets,
    PersistentTimeline? timeline,
    this.frameRate = FrameRateOption.auto,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.thumbnailPath,
  }) : mediaAssets = mediaAssets ?? MediaAssetRegistry(),
       timeline = timeline ?? PersistentTimeline.empty,
       createdAt = createdAt ?? DateTime.now(),
       modifiedAt = modifiedAt ?? DateTime.now();

  /// Total timeline duration
  Duration get duration => timeline.totalDuration;

  /// Touch modification date
  void touch() {
    modifiedAt = DateTime.now();
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'id': id,
    'name': name,
    'mediaAssets': mediaAssets.toJson(),
    'timeline': timeline.toJson(),
    'frameRate': frameRate.name,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
    'thumbnailPath': thumbnailPath,
  };

  /// Deserialize from JSON
  factory ProjectV3.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;

    // Handle version migration
    if (version < 3) {
      return _migrateFromV2(json);
    }

    final mediaAssets = MediaAssetRegistry();
    mediaAssets.fromJson(json['mediaAssets'] as List);

    final timelineItems = (json['timeline'] as List)
        .map((item) => TimelineItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return ProjectV3(
      id: json['id'] as String,
      name: json['name'] as String,
      mediaAssets: mediaAssets,
      timeline: PersistentTimeline.fromList(timelineItems),
      frameRate: FrameRateOption.values.byName(json['frameRate'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }

  /// Migrate from V2 project format
  static ProjectV3 _migrateFromV2(Map<String, dynamic> json) {
    // Create media asset from old sourceVideoPath
    final sourceVideoPath = json['sourceVideoPath'] as String;
    final oldTimeline = KeyframeTimeline.fromJson(
      json['timeline'] as Map<String, dynamic>,
    );

    final mediaAsset = MediaAsset(
      id: const Uuid().v4(),
      contentHash: 'migrated-${sourceVideoPath.hashCode}',
      relativePath: sourceVideoPath,
      originalFilename: sourceVideoPath.split('/').last,
      type: MediaType.video,
      durationMicroseconds: oldTimeline.videoDuration.inMicroseconds,
      frameRate: const Rational(30), // Assume 30fps for migration
      width: 1920,  // Assume 1080p for migration
      height: 1080,
      fileSize: 0,
    );

    final mediaAssets = MediaAssetRegistry();
    mediaAssets.register(mediaAsset);

    // Convert old clips to new format
    final oldClips = json['clips'] as List? ?? [];
    final newItems = <TimelineItem>[];

    for (final oldClip in oldClips) {
      final type = oldClip['type'] as String;

      if (type == 'clip') {
        // Migrate keyframes
        final oldKeyframes = (oldClip['keyframes'] as List?)
            ?.map((kf) => Keyframe.fromJson(kf as Map<String, dynamic>))
            .toList() ?? [];

        // Convert keyframe timestamps from milliseconds to microseconds
        final newKeyframes = oldKeyframes.map((kf) => Keyframe(
          id: kf.id,
          timestampMicros: kf.timestamp.inMicroseconds,
          transform: kf.transform,
          interpolation: kf.interpolation,
        )).toList();

        newItems.add(VideoClip(
          id: oldClip['id'] as String,
          mediaAssetId: mediaAsset.id,
          sourceInMicros: (oldClip['sourceInPointMs'] as int) * 1000,
          sourceOutMicros: (oldClip['sourceOutPointMs'] as int) * 1000,
          keyframes: newKeyframes,
          name: oldClip['name'] as String?,
        ));
      } else if (type == 'gap') {
        newItems.add(GapClip(
          id: oldClip['id'] as String,
          durationMicroseconds: (oldClip['durationMs'] as int) * 1000,
        ));
      }
    }

    return ProjectV3(
      id: json['id'] as String,
      name: json['name'] as String,
      mediaAssets: mediaAssets,
      timeline: PersistentTimeline.fromList(newItems),
      frameRate: FrameRateOption.values.firstWhere(
        (e) => e.name == json['frameRate'],
        orElse: () => FrameRateOption.auto,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }
}
```

---

## 12. Migration Strategy

### 12.1 Migration Phases

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MIGRATION PHASES                                     │
│                                                                              │
│  Phase 1: Foundation (Week 1-2)                                             │
│  ├─ Implement Rational frame rate type                                      │
│  ├─ Implement microsecond time utilities                                    │
│  ├─ Implement MediaAsset and Registry                                       │
│  └─ Unit tests for all new types                                           │
│                                                                              │
│  Phase 2: Timeline Core (Week 3-4)                                          │
│  ├─ Implement TimelineNode and PersistentTimeline                          │
│  ├─ Implement TimelineManager with undo/redo                               │
│  ├─ Implement clip type hierarchy                                          │
│  └─ Unit tests for tree operations                                         │
│                                                                              │
│  Phase 3: Playback Engine (Week 5-6)                                        │
│  ├─ Implement CompositionManager (native Swift)                            │
│  ├─ Implement DecoderPool (native Swift)                                   │
│  ├─ Implement FrameCache                                                   │
│  └─ Integration tests                                                       │
│                                                                              │
│  Phase 4: Integration (Week 7-8)                                            │
│  ├─ Update SmartEditViewModel to use new components                        │
│  ├─ Update UI to work with new timeline                                    │
│  ├─ Implement project migration                                            │
│  └─ End-to-end tests                                                        │
│                                                                              │
│  Phase 5: Polish (Week 9-10)                                                │
│  ├─ Performance optimization                                                │
│  ├─ Edge case handling                                                      │
│  ├─ Documentation                                                           │
│  └─ Final testing                                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 12.2 Backward Compatibility

The migration maintains full backward compatibility:

1. **Project Loading:** V2 projects automatically migrate to V3 on load
2. **Data Preservation:** All keyframes, tracking data, and settings preserved
3. **Graceful Fallback:** If V3 components fail, can fall back to V2 code paths
4. **No Data Loss:** Original V2 project files are never modified

### 12.3 Feature Flags

```dart
/// Feature flags for gradual rollout
class FeatureFlags {
  /// Use new persistent timeline (vs old list)
  static bool usePersistentTimeline = true;

  /// Use new composition manager (vs old PlaybackController)
  static bool useCompositionManager = true;

  /// Use frame cache for scrubbing
  static bool useFrameCache = true;

  /// Use decoder pool for multi-source
  static bool useDecoderPool = true;
}
```

---

## 13. Implementation Plan

### 13.1 Task Breakdown

#### Phase 1: Foundation

| Task | Est. Hours | Dependencies | Files |
|------|------------|--------------|-------|
| 1.1 Implement Rational type | 4 | None | `lib/models/rational.dart` |
| 1.2 Implement time utilities | 4 | 1.1 | `lib/models/time_utils.dart` |
| 1.3 Implement MediaAsset | 6 | 1.1 | `lib/models/media_asset.dart` |
| 1.4 Implement MediaAssetRegistry | 4 | 1.3 | `lib/core/media_asset_registry.dart` |
| 1.5 Implement content hashing | 4 | None | `lib/core/content_hash.dart` |
| 1.6 Unit tests | 8 | 1.1-1.5 | `test/foundation_test.dart` |

#### Phase 2: Timeline Core

| Task | Est. Hours | Dependencies | Files |
|------|------------|--------------|-------|
| 2.1 Implement TimelineNode | 8 | 1.2 | `lib/models/timeline_node.dart` |
| 2.2 Implement PersistentTimeline | 12 | 2.1 | `lib/models/persistent_timeline.dart` |
| 2.3 Implement TimelineManager | 8 | 2.2 | `lib/core/timeline_manager.dart` |
| 2.4 Implement clip hierarchy | 12 | 1.2, 1.3 | `lib/models/clips/*.dart` |
| 2.5 Unit tests | 12 | 2.1-2.4 | `test/timeline_test.dart` |

#### Phase 3: Playback Engine

| Task | Est. Hours | Dependencies | Files |
|------|------------|--------------|-------|
| 3.1 Native CompositionManager | 16 | None | `ios/Runner/CompositionManager.swift` |
| 3.2 Flutter CompositionManager | 8 | 3.1 | `lib/core/composition_manager.dart` |
| 3.3 Native DecoderPool | 12 | None | `ios/Runner/DecoderPool.swift` |
| 3.4 Flutter DecoderPool | 6 | 3.3 | `lib/core/decoder_pool.dart` |
| 3.5 Implement FrameCache | 8 | None | `lib/core/frame_cache.dart` |
| 3.6 Integration tests | 12 | 3.1-3.5 | `test/playback_test.dart` |

#### Phase 4: Integration

| Task | Est. Hours | Dependencies | Files |
|------|------------|--------------|-------|
| 4.1 Update SmartEditViewModel | 12 | 2.3, 3.2 | `lib/views/smart_edit/smart_edit_view_model.dart` |
| 4.2 Update timeline UI | 8 | 2.3 | `lib/views/smart_edit/keyframe_timeline_view.dart` |
| 4.3 Update project persistence | 6 | 1.4, 2.3 | `lib/core/project_storage.dart` |
| 4.4 Implement migration | 8 | 4.3 | `lib/core/project_migration.dart` |
| 4.5 End-to-end tests | 12 | 4.1-4.4 | `test/e2e_test.dart` |

**Total Estimated Hours: ~180 hours (~4.5 weeks full-time)**

---

## 14. Testing Strategy

### 14.1 Unit Tests

```dart
// Example: PersistentTimeline tests
void main() {
  group('PersistentTimeline', () {
    test('insert maintains sorted order', () {
      var timeline = PersistentTimeline.empty;

      final clip1 = VideoClip(id: '1', ...);
      final clip2 = VideoClip(id: '2', ...);

      timeline = timeline.append(clip1);
      timeline = timeline.append(clip2);

      expect(timeline.count, 2);
      expect(timeline.toList()[0].id, '1');
      expect(timeline.toList()[1].id, '2');
    });

    test('itemAtTime returns correct clip', () {
      var timeline = PersistentTimeline.empty;

      // Add 10-second clip
      final clip = VideoClip(
        id: '1',
        mediaAssetId: 'asset1',
        sourceInMicros: 0,
        sourceOutMicros: 10000000, // 10 seconds
      );

      timeline = timeline.append(clip);

      // Query at 5 seconds
      final result = timeline.itemAtTime(5000000);

      expect(result, isNotNull);
      expect(result!.$1.id, '1');
      expect(result.$2, 5000000); // Offset within clip
    });

    test('undo restores previous state', () {
      final manager = TimelineManager();

      final clip = VideoClip(id: '1', ...);
      manager.append(clip);

      expect(manager.itemCount, 1);

      manager.remove('1');
      expect(manager.itemCount, 0);

      manager.undo();
      expect(manager.itemCount, 1);
    });

    test('O(log n) performance for large timeline', () {
      var timeline = PersistentTimeline.empty;

      // Add 1000 clips
      for (int i = 0; i < 1000; i++) {
        timeline = timeline.append(VideoClip(
          id: '$i',
          mediaAssetId: 'asset',
          sourceInMicros: 0,
          sourceOutMicros: 1000000, // 1 second each
        ));
      }

      // Measure lookup time
      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 10000; i++) {
        timeline.itemAtTime(500000000); // Middle of timeline
      }
      stopwatch.stop();

      // 10000 lookups should complete in < 100ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
```

### 14.2 Integration Tests

```dart
// Example: Playback integration test
void main() {
  testWidgets('edit during playback causes no interruption', (tester) async {
    // Setup
    final project = await loadTestProject();
    final viewModel = SmartEditViewModel(project);

    await tester.pumpWidget(TestApp(viewModel: viewModel));

    // Start playback
    await viewModel.play();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify playing
    expect(viewModel.isPlaying, true);

    // Edit during playback
    viewModel.splitAt(viewModel.playheadMicros);

    // Playback should continue without pause
    await tester.pump(const Duration(milliseconds: 100));
    expect(viewModel.isPlaying, true);

    // Playhead should continue advancing
    final playheadBefore = viewModel.playheadMicros;
    await tester.pump(const Duration(milliseconds: 200));
    expect(viewModel.playheadMicros, greaterThan(playheadBefore));
  });
}
```

### 14.3 Performance Tests

```dart
// Example: Performance benchmark
void main() {
  test('timeline operations meet latency targets', () {
    final benchmarks = <String, Duration>{};

    // Benchmark lookup
    var timeline = _create1000ClipTimeline();
    benchmarks['lookup'] = _benchmark(() {
      timeline.itemAtTime(500000000);
    }, iterations: 10000);

    // Benchmark insert
    benchmarks['insert'] = _benchmark(() {
      timeline = timeline.insertAt(250000000, _createClip());
    }, iterations: 100);

    // Benchmark undo
    final manager = TimelineManager();
    manager.loadFromJson(timeline.toJson());
    for (int i = 0; i < 50; i++) {
      manager.append(_createClip());
    }
    benchmarks['undo'] = _benchmark(() {
      manager.undo();
      manager.redo();
    }, iterations: 1000);

    // Assert targets
    expect(benchmarks['lookup']!.inMicroseconds, lessThan(100)); // <0.1ms
    expect(benchmarks['insert']!.inMicroseconds, lessThan(1000)); // <1ms
    expect(benchmarks['undo']!.inMicroseconds, lessThan(10)); // <0.01ms
  });
}
```

---

## 15. Performance Benchmarks

### 15.1 Target Metrics

| Operation | Target Latency | Measurement |
|-----------|---------------|-------------|
| Timeline lookup | <100μs | `Stopwatch` in unit test |
| Insert/Delete | <1ms | `Stopwatch` in unit test |
| Undo/Redo | <10μs | `Stopwatch` in unit test |
| Scrub (cached) | <2ms | Frame timing in widget test |
| Scrub (uncached) | <50ms | Frame timing in widget test |
| Composition rebuild | <20ms | Native profiler |
| Hot-swap | <5ms | Native profiler |

### 15.2 Memory Targets

| Component | Target | Notes |
|-----------|--------|-------|
| Timeline (1000 clips) | <1MB | Tree nodes ~100 bytes each |
| Undo history (100 edits) | <10MB | Structural sharing |
| Frame cache | <300MB | 120 frames @ 1080p |
| Decoder pool | <100MB | 3 decoders |
| Total overhead | <500MB | For typical project |

---

## 16. Risk Analysis

### 16.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| AVComposition hot-swap glitches | Medium | High | Extensive testing, fallback to pause-rebuild |
| Persistent tree bugs | Low | High | Formal verification of tree operations |
| Frame cache memory pressure | Medium | Medium | Aggressive eviction, memory warnings |
| Multi-source sync issues | Medium | High | Use AVComposition (native sync) |
| Migration data loss | Low | Critical | Backup before migration, validation |

### 16.2 Schedule Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Native code complexity | High | Medium | Start native work early |
| Integration issues | Medium | Medium | Continuous integration testing |
| Performance tuning | Medium | Low | Built-in benchmarks from start |

---

## 17. Appendix

### 17.1 Glossary

| Term | Definition |
|------|------------|
| **AVComposition** | Apple's native class for composing multiple video/audio segments |
| **Order Statistic Tree** | BST augmented with subtree statistics (size, sum, etc.) |
| **Persistent Data Structure** | Data structure that preserves previous versions on mutation |
| **Path Copying** | Technique for persistent trees: copy only modified path |
| **I-frame** | Keyframe in video compression; can be decoded independently |
| **SMPTE Timecode** | Standard time format: HH:MM:SS:FF (hours:minutes:seconds:frames) |
| **Drop Frame** | Timecode that skips frame numbers to match NTSC timing |

### 17.2 References

- Apple AVFoundation Documentation: https://developer.apple.com/av-foundation/
- Persistent Data Structures: Okasaki, "Purely Functional Data Structures"
- AVL Trees: Adelson-Velsky and Landis, 1962
- Order Statistic Trees: CLRS "Introduction to Algorithms", Chapter 14

### 17.3 Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-30 | Dev Team | Initial draft |

---

## Review Checklist

Before implementation, verify:

- [ ] All latency targets are achievable with proposed algorithms
- [ ] Memory estimates are realistic for target devices
- [ ] Migration preserves all existing data
- [ ] Native APIs support required functionality
- [ ] Test coverage plan is comprehensive
- [ ] Rollback strategy is defined

---

## 18. Architecture Review: Edge Cases & UX Tradeoffs

**Review Date:** 2026-01-30
**Reviewer:** Architecture Review

This section documents identified edge cases, potential UX issues, and recommended mitigations discovered during architecture review.

### 18.1 Critical Edge Cases Identified

#### EC-1: Missing Source File Handling

**Issue:** When a MediaAsset's source file is deleted, moved, or becomes inaccessible, the current design marks `isLinked = false` but doesn't define UX behavior.

**Impact:** Users see broken clips with no clear path to recovery.

**Recommended Additions:**
```dart
/// Enhanced MediaAsset with offline handling
class MediaAsset {
  // ... existing fields ...

  /// Last known working path (for relinking hints)
  String? lastKnownAbsolutePath;

  /// Timestamp when file was last verified accessible
  DateTime? lastVerifiedAt;

  /// User-provided replacement path (temporary relink)
  String? temporaryRelinkPath;
}

/// Offline clip placeholder strategy
enum OfflineClipBehavior {
  /// Show placeholder with "Media Offline" badge
  showPlaceholder,
  /// Show last cached thumbnail
  showCachedThumbnail,
  /// Render as black/colored gap during playback
  renderAsGap,
}
```

**UX Flows to Add:**
1. On project load, verify all MediaAssets exist. Show banner: "2 media files missing. Tap to relink."
2. During playback, show "Media Offline" overlay on missing clips
3. On export, block with specific message about missing media
4. Provide "Locate..." dialog with file picker for relinking

---

#### EC-2: Memory Pressure During Frame Caching

**Issue:** FrameCache targets 300MB, but iOS can kill app if total memory exceeds ~1GB. No handling for `didReceiveMemoryWarning`.

**Impact:** App crash on older devices or during heavy multitasking.

**Recommended Additions:**
```dart
class FrameCache {
  // ... existing code ...

  /// Memory pressure levels
  static const int normalMaxFrames = 120;
  static const int pressureMaxFrames = 60;
  static const int criticalMaxFrames = 20;

  int _currentMaxFrames = normalMaxFrames;

  /// Called from iOS memory warning observer
  void onMemoryWarning(MemoryPressureLevel level) {
    switch (level) {
      case MemoryPressureLevel.normal:
        _currentMaxFrames = normalMaxFrames;
        break;
      case MemoryPressureLevel.warning:
        _currentMaxFrames = pressureMaxFrames;
        _evictToTarget(pressureMaxFrames);
        break;
      case MemoryPressureLevel.critical:
        _currentMaxFrames = criticalMaxFrames;
        _evictToTarget(criticalMaxFrames);
        break;
    }
  }

  void _evictToTarget(int target) {
    while (_cache.length > target) {
      _evictLRU();
    }
  }
}
```

---

#### EC-3: Corrupted Project File Recovery

**Issue:** `ProjectV3.fromJson` throws on invalid JSON. No recovery strategy for partial corruption.

**Impact:** Complete project loss if single field corrupted.

**Recommended Additions:**
```dart
class ProjectV3 {
  /// Attempt to load with graceful degradation
  static (ProjectV3?, List<String> warnings) fromJsonSafe(Map<String, dynamic> json) {
    final warnings = <String>[];

    try {
      // Validate required fields
      if (json['id'] == null) {
        warnings.add('Missing project ID - generating new');
        json['id'] = const Uuid().v4();
      }

      // Load timeline with clip recovery
      final timelineItems = <TimelineItem>[];
      for (final item in (json['timeline'] as List? ?? [])) {
        try {
          timelineItems.add(TimelineItem.fromJson(item));
        } catch (e) {
          warnings.add('Skipped corrupted clip: ${item['id'] ?? 'unknown'}');
        }
      }

      // Load media assets with recovery
      final mediaAssets = MediaAssetRegistry();
      for (final asset in (json['mediaAssets'] as List? ?? [])) {
        try {
          mediaAssets.register(MediaAsset.fromJson(asset));
        } catch (e) {
          warnings.add('Skipped corrupted asset: ${asset['id'] ?? 'unknown'}');
        }
      }

      return (ProjectV3(...), warnings);
    } catch (e) {
      return (null, ['Fatal error: $e']);
    }
  }
}
```

**Auto-Save Strategy:**
- Save to `project.json.tmp` first
- Verify integrity by reading back
- Only then rename to `project.json`
- Keep last 3 versions as `project.json.backup.1`, etc.

---

#### EC-4: Decoder Pool Exhaustion with Rapid Source Switching

**Issue:** With 3 decoder limit, rapid scrubbing across 5+ different source videos causes constant decoder creation/destruction.

**Impact:** Latency spikes during scrubbing when crossing multiple source boundaries.

**Recommended Additions:**
```dart
class DecoderPool {
  // ... existing code ...

  /// Pending decoder requests (avoid thrashing)
  final Set<String> _pendingCreations = {};

  /// Minimum time to keep a decoder alive (prevents thrashing)
  static const Duration minDecoderLifetime = Duration(seconds: 2);

  /// Timestamp when each decoder was created
  final Map<String, DateTime> _decoderCreatedAt = {};

  Future<void> _evictLRU() async {
    if (_lruOrder.isEmpty) return;

    // Find oldest decoder that's past minimum lifetime
    for (int i = 0; i < _lruOrder.length; i++) {
      final assetId = _lruOrder[i];
      final createdAt = _decoderCreatedAt[assetId];

      if (createdAt != null &&
          DateTime.now().difference(createdAt) > minDecoderLifetime) {
        _lruOrder.removeAt(i);
        final decoderId = _decodersByAsset.remove(assetId);
        _decoderCreatedAt.remove(assetId);
        // ... dispose ...
        return;
      }
    }

    // If all decoders are new, wait before evicting
    // (prevents thrashing during rapid scrubbing)
  }
}
```

---

#### EC-5: AVComposition Hot-Swap Audio Glitches

**Issue:** Hot-swapping AVComposition during playback may cause brief audio discontinuity if swap happens mid-audio-sample.

**Impact:** Audible "click" or "pop" during edit while playing.

**Recommended Mitigations:**
1. Sync hot-swap to audio frame boundaries (1/48000 second precision)
2. Cross-fade audio over 20ms during swap
3. Use AVMutableAudioMix with volume ramping

```swift
// Native iOS: Audio-safe hot-swap
func hotSwapComposition(
    from: AVMutableComposition,
    to: AVMutableComposition,
    atTime: CMTime
) {
    // Calculate next audio sample boundary
    let sampleRate: Double = 48000
    let currentSample = atTime.seconds * sampleRate
    let nextBoundary = ceil(currentSample) / sampleRate

    // Schedule swap at boundary
    DispatchQueue.main.asyncAfter(deadline: .now() + (nextBoundary - atTime.seconds)) {
        // Perform atomic swap
        self.playerItem.seek(to: CMTime(seconds: nextBoundary, preferredTimescale: 600))
    }
}
```

---

### 18.2 Missing UX Flows

#### UF-1: User Cancellation During Long Operations

**Missing:** No cancellation tokens for:
- Content hash generation (large files)
- Composition rebuild
- Batch import

**Recommended Pattern:**
```dart
class CancellableOperation {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void checkCancellation() {
    if (_cancelled) throw CancelledException();
  }
}

// Usage in content hash
Future<String?> generateContentHashCancellable(
  File file,
  CancellableOperation op,
) async {
  // ... every chunk read:
  op.checkCancellation();
  input.add(chunk);
}
```

---

#### UF-2: Undo/Redo UI Feedback

**Missing:** No UI indication of:
- What operation will be undone (hover preview)
- Undo stack depth
- Whether redo is available

**Recommended:**
- Show operation name in undo button tooltip: "Undo: Split clip"
- Show stack indicator: "⏪ 5/100"
- Dim redo button when stack empty

---

#### UF-3: Multi-Source Import Progress

**Missing:** When importing multiple videos, no:
- Per-file progress
- Total progress
- Ability to skip/cancel individual imports

**Recommended UI:**
```
Importing 3 of 5 videos...
✅ beach_sunset.mov (100%)
✅ interview_a.mp4 (100%)
⏳ wedding_ceremony.mov (45%) [Cancel]
⏸ reception.mov (pending)
⏸ speeches.mov (pending)

[Cancel All] [Import in Background]
```

---

#### UF-4: Timeline Zoom and Navigation

**Gap in Design:** Design focuses on data structures but doesn't specify:
- How zoom affects frame cache (should prefetch based on visible range)
- Keyboard navigation (J/K/L for shuttle, arrow keys for frame stepping)
- Snap-to behavior (snap to clip boundaries, snap to playhead)

**Recommended Additions to TimelineManager:**
```dart
class TimelineManager {
  // ... existing code ...

  /// Current visible time range (for smart prefetching)
  TimeRange? _visibleRange;

  void setVisibleRange(TimeRange range) {
    _visibleRange = range;
    // Notify frame cache to prioritize this range
  }

  /// Find nearest snap point
  int nearestSnapPoint(int timeMicros, {Set<SnapType>? types}) {
    final candidates = <int>[];

    if (types?.contains(SnapType.clipBoundary) ?? true) {
      // Add all clip start/end times
      int accumulated = 0;
      for (final item in items) {
        candidates.add(accumulated);
        accumulated += item.durationMicroseconds;
      }
      candidates.add(accumulated); // End of timeline
    }

    // Find nearest
    return candidates.reduce((a, b) =>
      (a - timeMicros).abs() < (b - timeMicros).abs() ? a : b);
  }
}
```

---

#### UF-5: Export with Missing/Offline Media

**Missing:** Export flow when some clips reference offline media.

**Recommended Flow:**
1. Before export, validate all media accessible
2. If missing: Show dialog listing missing files
3. Options:
   - "Locate Missing Media" → file picker
   - "Export Without Missing" → renders black/color for missing
   - "Cancel Export"
4. If rendering without: Show warning in export filename/metadata

---

### 18.3 Potential UX Tradeoffs

#### UT-1: Frame Cache Memory vs. Scrub Responsiveness

**Tradeoff:** 300MB frame cache vs. device memory constraints.

**Recommendation:**
- Detect device class (iPhone 15 Pro vs SE)
- Scale cache size: 300MB (Pro), 150MB (standard), 60MB (SE/older)
- User setting: "High quality scrubbing" toggle

---

#### UT-2: Composition Rebuild Latency vs. Edit Responsiveness

**Tradeoff:** Background rebuild adds latency before changes are audible/visible in playback.

**Current Mitigation:** Hot-swap when ready.

**Additional Recommendation:**
- Show subtle indicator during rebuild: "Updating timeline..."
- If rebuild takes >500ms, show progress
- Option to pause playback for instant-feeling edits

---

#### UT-3: Content Hash Accuracy vs. Import Speed

**Tradeoff:** SHA-256 of first+last 1MB is fast but could miss middle-file corruption.

**Recommendation:**
- Keep current fast hash for import
- Full verification on first playback (background)
- "Verify Project Integrity" menu option for manual check

---

#### UT-4: Persistent Tree Memory vs. Undo Depth

**Tradeoff:** More undo history = more memory from path-copied nodes.

**Analysis:**
- 100 edits on 500-clip tree: ~1500 nodes × 100 bytes = 150KB
- This is acceptable; keep 100 undo limit
- Consider: Project-level undo history save/restore

---

### 18.4 Race Conditions to Guard Against

#### RC-1: Edit During Composition Rebuild

**Scenario:** User edits timeline while previous edit's composition is still building.

**Current Handling:** Queue timeline for rebuild after current completes.

**Gap:** Multiple rapid edits could queue multiple rebuilds.

**Fix:**
```dart
class CompositionManager {
  // Only keep latest queued timeline
  PersistentTimeline? _queuedTimeline;

  // NOT a queue - just the latest
  Future<void> buildComposition(PersistentTimeline timeline) async {
    if (_isBuilding) {
      _queuedTimeline = timeline; // Overwrites previous queued
      return;
    }
    // ... build ...
  }
}
```
✅ Already correctly implemented in design.

---

#### RC-2: Frame Cache Population During Scrub Direction Change

**Scenario:** User scrubs right (prefetch ahead), then quickly reverses (prefetch behind). Two prefetch operations could conflict.

**Fix:** Cancel in-flight prefetch when direction changes.

```dart
class FrameCache {
  CancelToken? _activePrefetchToken;

  Future<void> prefetchAround(...) async {
    // Cancel previous prefetch
    _activePrefetchToken?.cancel();
    _activePrefetchToken = CancelToken();

    // ... prefetch with cancellation checks ...
  }
}
```

---

#### RC-3: Decoder Pool Access During Eviction

**Scenario:** Thread A uses decoder while Thread B evicts it.

**Fix:** Add mutex/lock around decoder pool operations or use actor-based single-thread access.

---

### 18.5 Performance Edge Cases

#### PE-1: 1000+ Clips Timeline

**Concern:** Tree rebalancing during rapid edits.

**Analysis:**
- log₂(1000) ≈ 10 levels
- Path copy: 10 nodes × 100 bytes = 1KB per edit
- Rebalance: max 2 rotations = O(1)
- ✅ Acceptable

---

#### PE-2: Very Long Clips (2+ hours)

**Concern:** Single clip dominates timeline, tree becomes unbalanced in practice.

**Analysis:**
- Tree balances by node count, not duration
- Long clip is single node regardless of duration
- ✅ Acceptable

---

#### PE-3: Microsecond Overflow

**Concern:** int64 microseconds overflow?

**Analysis:**
- int64 max: 9.2 × 10¹⁸
- 1 year in microseconds: 3.15 × 10¹³
- ✅ Safe for 292,000+ years of content

---

### 18.6 Recommended Implementation Priorities

Based on review, prioritize these additions:

1. **Critical (Block Implementation):**
   - Memory pressure handling (EC-2)
   - Offline media handling UX (EC-1)
   - Cancellation support (UF-1)

2. **High (Before Beta):**
   - Corrupted project recovery (EC-3)
   - Audio-safe hot-swap (EC-5)
   - Export validation (UF-5)

3. **Medium (Before Release):**
   - Decoder thrashing prevention (EC-4)
   - Multi-source import progress (UF-3)
   - Undo/redo UI feedback (UF-2)

4. **Nice-to-Have:**
   - Timeline snap-to (UF-4)
   - Device-scaled cache (UT-1)
   - Full integrity verification (UT-3)

---

### 18.7 Updated Review Checklist

Before implementation, verify:

- [x] All latency targets are achievable with proposed algorithms
- [x] Memory estimates are realistic for target devices
- [x] Migration preserves all existing data
- [x] Native APIs support required functionality
- [x] Test coverage plan is comprehensive
- [x] Rollback strategy is defined
- [ ] **NEW:** Memory pressure handling implemented
- [ ] **NEW:** Offline media UX flows defined
- [ ] **NEW:** Cancellation tokens for long operations
- [ ] **NEW:** Race conditions guarded against
- [ ] **NEW:** Export validation added

---

## Document History (Updated)

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-30 | Dev Team | Initial draft |
| 1.1 | 2026-01-30 | Architecture Review | Added Section 18: Edge Cases & UX Tradeoffs |

---

**End of Design Document**
