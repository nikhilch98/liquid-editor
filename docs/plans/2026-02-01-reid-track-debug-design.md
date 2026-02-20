# ReID + Track Debug Feature Design

**Date:** 2026-02-01
**Status:** Approved

## Overview

This document describes the design for two related features:
1. **ReID (Re-Identification)** - Reduce track fragmentation by recognizing people who reappear after being lost
2. **Track Debug UI** - New debugging interface to analyze tracking quality and understand why multiple IDs are created

## Problem Statement

Currently, when a person is temporarily undetectable (occlusion, out of frame, low confidence), the tracker:
1. Marks the track as "lost"
2. After 30 frames (~1 second), deletes the track
3. When the person reappears, creates a **new track ID**

This causes fragmentation: a video with 3 people might generate 10+ track IDs.

## Solution

### Part 1: ReID Architecture

#### OSNet Model Integration

We use OSNet, a lightweight person re-identification model (~2MB) that produces 128-dimensional appearance embeddings.

**New files:**
```
ios/Runner/Tracking/ReID/
├── OSNetReID.swift          # CoreML model wrapper
├── OSNetReID.mlmodel        # Converted OSNet model
├── AppearanceFeature.swift  # 128-dim embedding struct
└── TrackArchive.swift       # Archived tracks with embeddings
```

#### Track Archive System

Instead of deleting lost tracks, we archive them:

```
Track lost for 30 frames (maxTimeLost)
        ↓
Move to Archive with:
  - Appearance embedding (128-dim vector)
  - Last known position, size, velocity
  - Track metadata (ID, confidence history, etc.)
        ↓
Archive persists until:
  - Matched to new detection (track restored with original ID)
  - Tracking session ends
```

**Archive Configuration:**
| Parameter | Value | Notes |
|-----------|-------|-------|
| `archiveMaxFrames` | ∞ | Keep until tracking ends |
| `archiveCapacity` | Unlimited | No cap on archived tracks |
| `reidThreshold` | 0.65 | Cosine similarity threshold for match |
| `embeddingUpdateAlpha` | 0.8 | Blend: 80% old + 20% new appearance |
| `minDetectionsForEmbedding` | 3 | Need 3 good frames before archiving |

#### ReID Matching Flow

```
New Detection Appears
        ↓
[Check: Does it match any active track?] → YES → Update existing track
        ↓ NO
[Check: Does it match any archived track?] → YES → Restore old track ID
        ↓ NO
Create new track with new ID
```

#### Embedding Extraction

1. Crop person region from frame using bounding box
2. Resize to 256×128 (OSNet input size)
3. Run through CoreML model → 128-dim normalized vector
4. Store with exponential moving average (blend old + new appearances)

### Part 2: Track Debug UI

#### Smart Tab Changes

**Before:**
```
[ Track ] [ Reframe ] [ Captions ] [ Links ]
```

**After:**
```
[ Track ] [ Reframe ] [ Track Debug ]
```

#### Track Debug Flow

1. User taps "Track Debug" button
2. Dropdown appears with tracking algorithm options (same as Track)
3. User selects algorithm
4. Tracking runs with progress indicator
5. **No auto-reframe, No person selection sheet**
6. Debug Panel appears with detailed track information

#### Debug Panel Layout

```
┌─────────────────────────────────────────┐
│ Track Debug Results                   ✕ │
├─────────────────────────────────────────┤
│ Summary: 3 unique persons, 5 raw tracks │
│ ReID reduced fragmentation by 40%       │
├─────────────────────────────────────────┤
│ ┌─────┐ P0 (Main dancer)                │
│ │thumb│ 0:00.000 → 1:23.456 (83.4s)     │
│ └─────┘ 2492 frames, Avg conf: 0.87     │
│         Gaps: 2 (max 0.8s)              │
│         ReID: Restored 2× from archive  │
│         ▼ Show detailed stats           │
├─────────────────────────────────────────┤
│ ┌─────┐ P1 (Background person)          │
│ │thumb│ 0:12.340 → 0:45.120 (32.8s)     │
│ └─────┘ 984 frames, Avg conf: 0.71      │
│         Gaps: 5 (max 2.1s)              │
│         ⚠️ Low confidence sections      │
│         ▼ Show detailed stats           │
└─────────────────────────────────────────┘
```

#### Expanded Track Details

When user taps "Show detailed stats":

```
┌─────────────────────────────────────────┐
│ P0 - Detailed Statistics                │
├─────────────────────────────────────────┤
│ TIMELINE                                │
│ ████████░░████████████░████████████     │
│                                         │
│ CONFIDENCE OVER TIME                    │
│ ▁▂▄▆█▇▆▅▃▁▂▅▇█▇▆▅▄▃▂▄▆█▇              │
│                                         │
│ GAP DETAILS                             │
│ • Gap 1: 0:15.200→0:15.850 (0.65s)     │
│   Reason: Occlusion (ReID match)        │
│ • Gap 2: 0:42.100→0:43.300 (1.20s)     │
│   Reason: Out of frame                  │
│                                         │
│ REID EVENTS                             │
│ • 0:15.850: Restored from archive       │
│   Similarity: 0.89                      │
│                                         │
│ DETECTION QUALITY                       │
│ • Frames with conf > 0.8: 78%           │
│ • Frames with conf > 0.5: 95%           │
│                                         │
│ MOTION ANALYSIS                         │
│ • Avg velocity: 45 px/frame             │
│ • Classification: High motion           │
└─────────────────────────────────────────┘
```

### Data Models

#### Swift - TrackDebugInfo

```swift
struct TrackDebugInfo: Codable {
    let trackId: Int
    let firstFrameMs: Int64
    let lastFrameMs: Int64
    let totalFrames: Int

    // Confidence stats
    let avgConfidence: Float
    let minConfidence: Float
    let maxConfidence: Float
    let confidenceHistogram: [Float] // 10 buckets

    // Gap analysis
    let gaps: [TrackGap]
    let totalGapDurationMs: Int64

    // ReID events
    let reidRestorations: [ReIDEvent]
    let mergedFromTrackIds: [Int]

    // Bounding box stats
    let avgBboxSize: CGSize
    let avgBboxCenter: CGPoint
    let bboxSizeVariance: Float

    // Motion stats
    let avgVelocity: Float
    let maxVelocity: Float
    let motionClassification: MotionClass

    // Current state
    let state: TrackState
}

struct TrackGap: Codable {
    let startMs: Int64
    let endMs: Int64
    let likelyReason: GapReason
}

struct ReIDEvent: Codable {
    let frameMs: Int64
    let similarity: Float
    let previousTrackId: Int?
}

enum GapReason: String, Codable {
    case occlusion
    case outOfFrame
    case lowConfidence
    case unknown
}

enum MotionClass: String, Codable {
    case low
    case medium
    case high
}
```

#### Dart - TrackDebugInfo

```dart
class TrackDebugInfo {
  final int trackId;
  final Duration firstSeen;
  final Duration lastSeen;
  final int totalFrames;

  final double avgConfidence;
  final double minConfidence;
  final double maxConfidence;
  final List<double> confidenceHistogram;

  final List<TrackGap> gaps;
  final Duration totalGapDuration;

  final List<ReIDEvent> reidRestorations;
  final List<int> mergedFromTrackIds;

  final Size avgBboxSize;
  final Offset avgBboxCenter;
  final double bboxSizeVariance;

  final double avgVelocity;
  final double maxVelocity;
  final MotionClass motionClassification;

  final TrackState state;
}

class TrackGap {
  final Duration start;
  final Duration end;
  final GapReason likelyReason;

  Duration get duration => end - start;
}

class ReIDEvent {
  final Duration timestamp;
  final double similarity;
  final int? previousTrackId;
}

enum GapReason { occlusion, outOfFrame, lowConfidence, unknown }
enum MotionClass { low, medium, high }
```

## File Changes Summary

| Component | File | Change Type |
|-----------|------|-------------|
| iOS | `ios/Runner/Tracking/ReID/OSNetReID.swift` | New |
| iOS | `ios/Runner/Tracking/ReID/OSNetReID.mlmodel` | New |
| iOS | `ios/Runner/Tracking/ReID/AppearanceFeature.swift` | New |
| iOS | `ios/Runner/Tracking/ReID/TrackArchive.swift` | New |
| iOS | `ios/Runner/Tracking/YOLOByteTrack/ByteTrackAssociator.swift` | Modify |
| iOS | `ios/Runner/Tracking/TrackingService.swift` | Modify |
| Flutter | `lib/views/smart_edit/editor_bottom_toolbar.dart` | Modify |
| Flutter | `lib/views/smart_edit/smart_edit_view.dart` | Modify |
| Flutter | `lib/views/smart_edit/tracking_controller.dart` | Modify |
| Flutter | `lib/views/smart_edit/track_debug_sheet.dart` | New |
| Flutter | `lib/views/smart_edit/track_debug_detail_view.dart` | New |
| Flutter | `lib/models/track_debug_info.dart` | New |
| Flutter | `lib/core/tracking_service.dart` | Modify |

## ReID Magic Numbers

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `reidThreshold` | 0.65 | Cosine similarity to match archived track |
| `embeddingUpdateAlpha` | 0.8 | Blend ratio for appearance updates |
| `minDetectionsForEmbedding` | 3 | Minimum frames before extracting embedding |
| `osnetInputSize` | 256×128 | Model input dimensions |
| `embeddingDimension` | 512 | Output feature vector size |

## Success Criteria

1. Track fragmentation reduced by 50%+ on test videos
2. Same person maintains consistent ID across gaps up to 10+ seconds
3. Debug UI displays all track metadata accurately
4. No performance regression (tracking still real-time)
5. ReID matching adds < 5ms per frame overhead
