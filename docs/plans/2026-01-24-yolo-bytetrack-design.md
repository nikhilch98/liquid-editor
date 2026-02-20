# YOLO-Pose + ByteTrack Integration Design

**Date:** 2026-01-24
**Status:** Approved

## Overview

Integrate YOLOv8-Pose with ByteTrack for robust multi-person tracking on iPhone 17 Pro Max.

## Architecture

```
Flutter UI → TrackingController → MethodChannel → TrackingService
                                                        ↓
                                              ┌─────────────────┐
                                              │ Algorithm       │
                                              │ Registry        │
                                              └────────┬────────┘
                                    ┌─────────────────┼─────────────────┐
                                    ↓                 ↓                 ↓
                            VisionTracker    YOLOByteTracker    MediaPipeTracker
                            (existing)       (NEW)              (existing)
```

## New Files

### iOS Native (Swift)

```
ios/Runner/Tracking/
├── YOLOByteTrack/
│   ├── YOLOByteTracker.swift      # Main tracker implementing TrackingAlgorithm
│   ├── YOLOPoseDetector.swift     # CoreML inference wrapper
│   ├── ByteTrackAssociator.swift  # Two-stage association logic
│   ├── KalmanBoxTracker.swift     # Per-track Kalman filter
│   └── HungarianAlgorithm.swift   # Optimal assignment solver
└── Models/
    └── yolov8n-pose.mlpackage     # CoreML model (download separately)
```

### Model Specification

- **Model:** YOLOv8n-pose (nano variant)
- **Input:** [1, 3, 640, 640] RGB normalized
- **Output:** [1, 56, 8400] predictions
- **Size:** ~25MB
- **Source:** Ultralytics, convert via coremltools

## ByteTrack Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| High confidence threshold | 0.6 | First association |
| Low confidence threshold | 0.25 | Second association |
| IoU threshold (NMS) | 0.45 | Standard YOLO |
| IoU threshold (matching) | 0.3 | Track association |
| Max frames lost | 30 | ~1 second at 30fps |
| Min hits to confirm | 3 | Reduce false positives |

## Data Flow

1. CVPixelBuffer → Preprocess (resize, normalize)
2. MLMultiArray → YOLOv8-Pose inference
3. Raw output → NMS → Detections
4. Detections → ByteTrack → TrackedPersons
5. TrackedPersons → JSON → Flutter

## Integration Points

- Register in `TrackingService.registerTrackers()` as "yoloByteTrack"
- Conforms to existing `TrackingAlgorithm` protocol
- Output compatible with existing `PersonTrackingResult` model

## Performance Targets

- Inference: < 25ms per frame
- Total pipeline: < 35ms (28+ FPS)
- Memory: < 200MB
- Works alongside existing trackers
