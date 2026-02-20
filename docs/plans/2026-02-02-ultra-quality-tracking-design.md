# Ultra-Quality Person Tracking System Design

**Date:** 2026-02-02
**Status:** Draft
**Priority:** High (Accuracy-First)
**Estimated Timeline:** 10-12 weeks

---

## Glossary

| Term | Definition |
|------|------------|
| **Tracklet** | A short, high-confidence sequence of detections that are reliably the same person (typically 5-30 frames) |
| **Affinity** | A similarity score between two tracklets indicating likelihood they belong to the same person |
| **Spectral Clustering** | A clustering algorithm that uses eigenvalues of a similarity matrix to reduce dimensionality before clustering |
| **Correlation Clustering** | A clustering algorithm that groups items to minimize disagreement with pairwise similarity/dissimilarity labels |
| **ReID** | Re-Identification - the task of recognizing the same person across different camera views or time |
| **IoU** | Intersection over Union - a measure of overlap between two bounding boxes |
| **Embedding** | A fixed-size vector representation of an image that captures semantic features |

---

## 1. Problem Statement

### 1.1 Current Issues

The existing person tracking system exhibits two critical failure modes:

1. **Track Swap**: When two people cross paths or come close together, their identities get exchanged. Person A's track continues following Person B and vice versa.

2. **Track Split**: A single person receives multiple track IDs throughout the video, especially when:
   - They partially enter the frame (detected as Person 3)
   - They fully enter the frame later (detected as Person 4)
   - They leave and re-enter the frame
   - Occlusion causes temporary detection loss

### 1.2 Motivating Example

**User-reported bug:** In a sports video, a person wearing jersey #96 was incorrectly labeled as "Nikhil" (a different person). The two people were close at some point, causing a track swap. This highlights the need for:
- Better appearance features during association (not just IoU)
- Jersey/number recognition for sports contexts
- Global optimization to detect and repair swaps

### 1.3 Root Cause Analysis

| Issue | Root Cause | Current Limitation |
|-------|------------|-------------------|
| Track Swap | IoU + distance cost matrix with greedy assignment | No appearance features during association |
| Track Split | Frame-by-frame local decisions | No global trajectory reasoning |
| Partial Entry | New track created when detection changes significantly | No temporal continuity model |
| Re-entry | Max 5-frame gap filling is insufficient | No long-term re-identification |

### 1.4 Design Goals

- **Primary Goal**: Maximum tracking accuracy (performance is secondary)
- **Constraint**: Tracking computed once, results cached and reused
- **Target**: Zero track swaps, zero unnecessary track splits
- **Acceptable Trade-off**: Longer processing time (≤10x current)
- **Memory Budget**: ≤500MB peak (with pruning strategies)

---

## 2. Current Architecture Summary

### 2.1 Pipeline Overview

```
Frame → Detection → Association → ReID Extraction → Post-Processing → Output
              ↓           ↓              ↓                  ↓
         VNDetect    IoU+Dist       OSNet 512d         Kalman Filter
         BodyPose    Greedy         (after track)      Integral Smooth
                    Assignment                          Gap Fill (5 frames)
```

### 2.2 Key Components

| Component | File | Current Implementation |
|-----------|------|----------------------|
| Detection | `BoundingBoxTracker.swift` | VNDetectHumanBodyPoseRequest |
| Association | `BoundingBoxTracker.swift` | Cost = 0.4×(1-IoU) + 0.6×distance, greedy |
| ReID | `ReIDExtractor.swift` | OSNet 512-dim embeddings |
| Matching | `AppearanceFeature.swift` | reidThreshold: 0.65 cosine similarity |
| Post-process | `TrackingService.swift` | Kalman → Integral → Gap Fill |

### 2.3 Current Thresholds

```swift
reidentificationIoUThreshold: 0.15
maxCenterDistance: 0.45
reidThreshold: 0.65
identificationThreshold: 0.68
maxGapFrames: 5
```

---

## 3. Proposed Ultra-Quality Tracking Pipeline

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ULTRA-QUALITY TRACKING PIPELINE                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │   Phase 1   │───▶│   Phase 2   │───▶│   Phase 3   │───▶│   Phase 4   │  │
│  │  Detection  │    │   Tracklet  │    │   Global    │    │   Merge &   │  │
│  │  + Features │    │  Formation  │    │Optimization │    │   Refine    │  │
│  └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘  │
│         │                  │                  │                  │          │
│         ▼                  ▼                  ▼                  ▼          │
│  • Multi-detector    • Short reliable   • Correlation     • Track merge    │
│  • Face + Body       • High-confidence  • Clustering      • Swap repair    │
│  • Pose keypoints    • IoU chains       • Constrained     • User oracle    │
│  • Color histogram   • Local features   • Affinity        • Final smooth   │
│  • Jersey OCR                           • Graph solve                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              DATA FLOW                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Video Frames                                                                │
│       │                                                                      │
│       ▼                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │ Phase 1: Per-Frame Feature Extraction                        │            │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │            │
│  │  │Body Pose│  │  Face   │  │  Color  │  │ Jersey  │        │            │
│  │  │Detection│  │Detection│  │Histogram│  │  OCR    │        │            │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘        │            │
│  │       └──────┬─────┴──────┬─────┴──────┬─────┘              │            │
│  │              ▼                                               │            │
│  │       MultiModalDetection[]                                  │            │
│  └─────────────────────────────────────────────────────────────┘            │
│                    │                                                         │
│                    ▼                                                         │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │ Phase 2: Tracklet Formation (Strict IoU + Appearance)        │            │
│  │       Tracklet[] (short, high-confidence chains)             │            │
│  └─────────────────────────────────────────────────────────────┘            │
│                    │                                                         │
│                    ▼                                                         │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │ Phase 3: Global Optimization                                 │            │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │            │
│  │  │   Affinity   │───▶│ Co-occurrence│───▶│ Correlation  │  │            │
│  │  │   Matrix     │    │ Constraints  │    │ Clustering   │  │            │
│  │  └──────────────┘    └──────────────┘    └──────────────┘  │            │
│  │       TrackletCluster[] (grouped by person)                  │            │
│  └─────────────────────────────────────────────────────────────┘            │
│                    │                                                         │
│                    ▼                                                         │
│  ┌─────────────────────────────────────────────────────────────┐            │
│  │ Phase 4: Merge & Refine                                      │            │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │            │
│  │  │  Merge   │  │   Swap   │  │Bidirect- │  │  People  │    │            │
│  │  │ Tracklets│─▶│  Repair  │─▶│  ional   │─▶│ Library  │    │            │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │            │
│  │       PersonTrack[] (final output)                           │            │
│  └─────────────────────────────────────────────────────────────┘            │
│                    │                                                         │
│                    ▼                                                         │
│              Flutter UI                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Core Data Structures

```swift
// MARK: - Frame Data

/// A single video frame with index and pixel buffer
struct Frame {
    let index: Int
    let timestamp: CMTime
    let pixelBuffer: CVPixelBuffer

    // Computed
    var cgImage: CGImage? { /* convert from pixelBuffer */ }
}

// MARK: - Detection Data

/// Multi-modal detection for a single person in a single frame
struct MultiModalDetection {
    // Identification
    let detectionId: UUID
    let frameIndex: Int

    // Body detection (existing)
    let bodyPose: VNHumanBodyPoseObservation?
    let bodyBoundingBox: CGRect
    let bodyConfidence: Float

    // Face detection (new)
    let faceObservation: VNFaceObservation?
    let faceLandmarks: VNFaceLandmarks2D?
    let faceEmbedding: [Float]?  // 128-dim FaceNet (nil if no face)

    // Body ReID embedding
    let bodyEmbedding: [Float]  // 512-dim OSNet (always present)

    // Auxiliary features
    let colorHistogram: ColorHistogram
    let heightEstimate: Float?  // Relative to frame height (0.0-1.0)
    let bodyProportions: BodyProportions?
    let jerseyNumber: Int?  // From OCR (nil if not detected)

    // Quality metrics
    let motionBlur: Float  // 0.0 = sharp, 1.0 = blurred
    let occlusionRatio: Float  // 0.0 = fully visible, 1.0 = fully occluded
}

/// Body proportion measurements from pose keypoints
struct BodyProportions {
    let headToBodyRatio: Float      // head height / total height
    let shoulderWidth: Float        // normalized shoulder width
    let torsoToLegRatio: Float      // torso length / leg length
    let armSpan: Float              // normalized arm span

    static func extract(from pose: VNHumanBodyPoseObservation,
                       boundingBox: CGRect) -> BodyProportions? {
        // Note: recognizedPoint returns VNRecognizedPoint? (doesn't throw)
        guard let head = pose.recognizedPoint(.nose),
              let leftShoulder = pose.recognizedPoint(.leftShoulder),
              let rightShoulder = pose.recognizedPoint(.rightShoulder),
              let leftHip = pose.recognizedPoint(.leftHip),
              let leftAnkle = pose.recognizedPoint(.leftAnkle),
              head.confidence > 0.3,
              leftShoulder.confidence > 0.3,
              rightShoulder.confidence > 0.3,
              leftHip.confidence > 0.3,
              leftAnkle.confidence > 0.3 else {
            return nil
        }

        let height = boundingBox.height
        guard height > 0 else { return nil }

        let headHeight = abs(head.location.y - leftShoulder.location.y)
        let shoulderW = abs(leftShoulder.location.x - rightShoulder.location.x)
        let torsoLen = abs(leftShoulder.location.y - leftHip.location.y)
        let legLen = abs(leftHip.location.y - leftAnkle.location.y)

        return BodyProportions(
            headToBodyRatio: Float(headHeight / height),
            shoulderWidth: Float(shoulderW / boundingBox.width),
            torsoToLegRatio: legLen > 0 ? Float(torsoLen / legLen) : 0,
            armSpan: 0  // Requires both arms visible
        )
    }

    func similarity(to other: BodyProportions) -> Float {
        let headSim = 1.0 - min(abs(headToBodyRatio - other.headToBodyRatio) / 0.2, 1.0)
        let shoulderSim = 1.0 - min(abs(shoulderWidth - other.shoulderWidth) / 0.3, 1.0)
        let ratioSim = 1.0 - min(abs(torsoToLegRatio - other.torsoToLegRatio) / 0.5, 1.0)

        return 0.4 * headSim + 0.3 * shoulderSim + 0.3 * ratioSim
    }
}

// MARK: - Tracklet Data

/// A short, high-confidence sequence of detections for one person
struct Tracklet {
    let id: UUID
    var detections: [(frameIndex: Int, detection: MultiModalDetection)]

    // Temporal span
    var startFrame: Int { detections.first?.frameIndex ?? 0 }
    var endFrame: Int { detections.last?.frameIndex ?? 0 }
    var duration: Int { endFrame - startFrame + 1 }

    // Quality metrics
    var averageConfidence: Float {
        guard !detections.isEmpty else { return 0 }
        return detections.map { $0.detection.bodyConfidence }.reduce(0, +) / Float(detections.count)
    }

    var hasFaceDetection: Bool {
        detections.contains { $0.detection.faceEmbedding != nil }
    }

    var hasConsistentAppearance: Bool {
        // Check if internal appearance variance is low
        guard detections.count >= 2 else { return true }
        let embeddings = detections.map { $0.detection.bodyEmbedding }
        let avgSimilarity = computeAveragePairwiseSimilarity(embeddings)
        return avgSimilarity > 0.85
    }

    var jerseyNumber: Int? {
        // Return most frequently detected jersey number
        let numbers = detections.compactMap { $0.detection.jerseyNumber }
        guard !numbers.isEmpty else { return nil }
        let counts = Dictionary(grouping: numbers) { $0 }.mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    // Best face embedding (highest confidence face detection)
    var bestFaceEmbedding: [Float]? {
        detections
            .filter { $0.detection.faceEmbedding != nil }
            .max(by: { ($0.detection.faceObservation?.confidence ?? 0) <
                       ($1.detection.faceObservation?.confidence ?? 0) })?
            .detection.faceEmbedding
    }

    // Aggregated body embedding (mean of all)
    var aggregatedBodyEmbedding: [Float] {
        guard !detections.isEmpty else { return [] }
        let embeddings = detections.map { $0.detection.bodyEmbedding }
        return elementWiseMean(embeddings)
    }

    // Aggregated color histogram
    var aggregatedColorHistogram: ColorHistogram {
        guard !detections.isEmpty else { return ColorHistogram.empty }
        return ColorHistogram.average(detections.map { $0.detection.colorHistogram })
    }

    func containsFrame(_ frame: Int) -> Bool {
        return frame >= startFrame && frame <= endFrame
    }

    func detectionAt(_ frame: Int) -> MultiModalDetection? {
        return detections.first { $0.frameIndex == frame }?.detection
    }
}

typealias TrackletID = UUID

// MARK: - Person Track (Final Output)

/// A complete track for one person across the entire video
struct PersonTrack {
    let id: UUID
    var tracklets: [Tracklet]

    // Identity assignment
    var assignedPersonId: UUID?  // From People Library
    var assignedPersonName: String?
    var identityConfidence: Float = 0.0

    // User confirmation
    var confirmedByUser: Bool = false
    var userConfirmedAtFrame: Int?

    // Computed properties
    var startFrame: Int { tracklets.map { $0.startFrame }.min() ?? 0 }
    var endFrame: Int { tracklets.map { $0.endFrame }.max() ?? 0 }

    var allDetections: [(frameIndex: Int, detection: MultiModalDetection)] {
        tracklets.flatMap { $0.detections }.sorted { $0.frameIndex < $1.frameIndex }
    }

    mutating func append(_ tracklet: Tracklet) {
        tracklets.append(tracklet)
        tracklets.sort { $0.startFrame < $1.startFrame }
    }

    func containsFrame(_ frame: Int) -> Bool {
        return allDetections.contains { $0.frameIndex == frame }
    }

    func detectionAt(_ frame: Int) -> MultiModalDetection? {
        return allDetections.first { $0.frameIndex == frame }?.detection
    }

    /// Interpolate missing frames between tracklets
    mutating func interpolateGaps() {
        // Linear interpolation for bounding boxes
        // Embedding interpolation not recommended - keep last known
    }

    /// Calculate appearance consistency around a frame
    func appearanceConsistency(around frame: Int, windowSize: Int = 10) -> Float {
        let relevantDetections = allDetections.filter {
            abs($0.frameIndex - frame) <= windowSize
        }
        guard relevantDetections.count >= 2 else { return 1.0 }

        let embeddings = relevantDetections.map { $0.detection.bodyEmbedding }
        return computeAveragePairwiseSimilarity(embeddings)
    }
}

/// Identity for a known person in the People Library
struct PersonIdentity {
    let personId: UUID
    let name: String
    let position: CGRect  // Bounding box position for matching
}
```

### 3.4 Phase 1: Multi-Modal Detection & Feature Extraction

#### 3.4.1 Color Histogram Features

```swift
struct ColorHistogram {
    // HSV histogram for each body region (64 bins = 8H × 4S × 2V)
    let upperBody: [Float]   // 64 bins
    let lowerBody: [Float]   // 64 bins
    let fullBody: [Float]    // 64 bins

    static let empty = ColorHistogram(
        upperBody: [Float](repeating: 0, count: 64),
        lowerBody: [Float](repeating: 0, count: 64),
        fullBody: [Float](repeating: 0, count: 64)
    )

    static func extract(from image: CGImage,
                       pose: VNHumanBodyPoseObservation?,
                       boundingBox: CGRect) -> ColorHistogram {
        // 1. Crop to bounding box
        guard let cropped = image.cropping(to: boundingBox.scaled(to: image.size)) else {
            return .empty
        }

        // 2. Convert to HSV
        let hsvPixels = convertToHSV(cropped)

        // 3. Determine upper/lower split (use pose if available, else 50%)
        // Note: recognizedPoint returns optional, doesn't throw
        let splitRatio: CGFloat
        if let pose = pose,
           let hip = pose.recognizedPoint(.root),
           hip.confidence > 0.3 {
            splitRatio = hip.location.y  // Normalized 0-1 (root = body center)
        } else {
            splitRatio = 0.5
        }

        // 4. Build histograms
        let upperPixels = hsvPixels.filter { $0.y < splitRatio }
        let lowerPixels = hsvPixels.filter { $0.y >= splitRatio }

        return ColorHistogram(
            upperBody: buildHistogram(upperPixels, bins: 64),
            lowerBody: buildHistogram(lowerPixels, bins: 64),
            fullBody: buildHistogram(hsvPixels, bins: 64)
        )
    }

    static func average(_ histograms: [ColorHistogram]) -> ColorHistogram {
        guard !histograms.isEmpty else { return .empty }
        let n = Float(histograms.count)
        return ColorHistogram(
            upperBody: elementWiseMean(histograms.map { $0.upperBody }),
            lowerBody: elementWiseMean(histograms.map { $0.lowerBody }),
            fullBody: elementWiseMean(histograms.map { $0.fullBody })
        )
    }

    /// Histogram intersection similarity (0.0 to 1.0)
    func similarity(to other: ColorHistogram) -> Float {
        let upperSim = histogramIntersection(upperBody, other.upperBody)
        let lowerSim = histogramIntersection(lowerBody, other.lowerBody)
        return 0.5 * upperSim + 0.5 * lowerSim
    }
}

/// Histogram intersection: sum of min values, normalized
func histogramIntersection(_ h1: [Float], _ h2: [Float]) -> Float {
    guard h1.count == h2.count, !h1.isEmpty else { return 0 }
    let intersection = zip(h1, h2).map { min($0, $1) }.reduce(0, +)
    let sum1 = h1.reduce(0, +)
    let sum2 = h2.reduce(0, +)
    let maxSum = max(sum1, sum2)
    guard maxSum > 0 else { return 0 }
    return intersection / maxSum
}
```

#### 3.4.2 Jersey Number OCR

```swift
class JerseyNumberDetector {
    private let textRecognizer = VNRecognizeTextRequest()

    init() {
        textRecognizer.recognitionLevel = .accurate
        textRecognizer.usesLanguageCorrection = false
        textRecognizer.customWords = (0...99).map { String($0) }  // Jersey numbers
    }

    /// Detect jersey number in a person's bounding box
    func detectNumber(in image: CGImage, boundingBox: CGRect) -> Int? {
        // 1. Crop to upper body (jersey area)
        let jerseyRegion = CGRect(
            x: boundingBox.minX,
            y: boundingBox.minY,
            width: boundingBox.width,
            height: boundingBox.height * 0.5  // Upper half
        )

        guard let cropped = image.cropping(to: jerseyRegion.scaled(to: image.size)) else {
            return nil
        }

        // 2. Run text recognition
        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try? handler.perform([textRecognizer])

        guard let observations = textRecognizer.results else { return nil }

        // 3. Find numeric strings
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)

            // Check if it's a valid jersey number (1-99 typically)
            if let number = Int(text), number >= 0 && number <= 99 {
                // Require minimum confidence
                if candidate.confidence > 0.5 {
                    return number
                }
            }
        }

        return nil
    }

    /// Jersey numbers definitively distinguish people
    static func numbersAreDifferent(_ n1: Int?, _ n2: Int?) -> Bool {
        guard let n1 = n1, let n2 = n2 else { return false }
        return n1 != n2
    }

    static func numbersAreSame(_ n1: Int?, _ n2: Int?) -> Bool {
        guard let n1 = n1, let n2 = n2 else { return false }
        return n1 == n2
    }
}
```

#### 3.4.3 Multi-Modal Detector

```swift
/// Coordinates all detection modalities for a single frame
class MultiModalDetector {
    private let config: UltraQualityConfig
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let jerseyDetector = JerseyNumberDetector()
    private let logger = Logger(subsystem: "com.liquideditor", category: "Detection")

    init(config: UltraQualityConfig) {
        self.config = config
    }

    /// Detect all people in a frame with multi-modal features
    func detect(in image: CGImage, frame: Frame) async throws -> [MultiModalDetection] {
        var detections: [MultiModalDetection] = []

        // Run body pose detection
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([bodyPoseRequest])

        guard let poseObservations = bodyPoseRequest.results else {
            return []
        }

        // Run face detection if enabled
        var faceObservations: [VNFaceObservation] = []
        if config.enableFaceDetection {
            try handler.perform([faceRequest])
            faceObservations = faceRequest.results ?? []
        }

        // Process each detected body
        for (index, poseObs) in poseObservations.enumerated() {
            // Compute bounding box from pose keypoints
            let boundingBox = computeBoundingBox(from: poseObs)
            guard !boundingBox.isEmpty else { continue }

            // Extract body embedding (OSNet)
            let bodyEmbedding = try await extractBodyEmbedding(from: image, boundingBox: boundingBox)

            // Find matching face (if any)
            let matchingFace = faceObservations.first { face in
                boundingBox.contains(face.boundingBox.center)
            }

            // Extract face embedding if face found
            var faceEmbedding: [Float]? = nil
            if let face = matchingFace, config.enableFaceDetection {
                faceEmbedding = try? await extractFaceEmbedding(from: image, faceRect: face.boundingBox)
            }

            // Extract color histogram
            let colorHistogram = config.enableColorHistogram
                ? ColorHistogram.extract(from: image, pose: poseObs, boundingBox: boundingBox)
                : ColorHistogram.empty

            // Detect jersey number
            let jerseyNumber = config.enableJerseyOCR
                ? jerseyDetector.detectNumber(in: image, boundingBox: boundingBox)
                : nil

            // Estimate height
            let heightEstimate = HeightEstimator.estimate(
                from: poseObs,
                boundingBox: boundingBox,
                frameHeight: CGFloat(image.height)
            )

            // Extract body proportions
            let bodyProportions = BodyProportions.extract(from: poseObs, boundingBox: boundingBox)

            // Estimate motion blur (simplified)
            let motionBlur: Float = 0.0  // TODO: Implement blur detection

            let detection = MultiModalDetection(
                detectionId: UUID(),
                frameIndex: frame.index,
                bodyPose: poseObs,
                bodyBoundingBox: boundingBox,
                bodyConfidence: poseObs.confidence,
                faceObservation: matchingFace,
                faceLandmarks: nil,  // Could extract if needed
                faceEmbedding: faceEmbedding,
                bodyEmbedding: bodyEmbedding,
                colorHistogram: colorHistogram,
                heightEstimate: heightEstimate,
                bodyProportions: bodyProportions,
                jerseyNumber: jerseyNumber,
                motionBlur: motionBlur,
                occlusionRatio: 0.0
            )

            detections.append(detection)
        }

        logger.debug("Frame \(frame.index): detected \(detections.count) people")
        return detections
    }

    private func computeBoundingBox(from pose: VNHumanBodyPoseObservation) -> CGRect {
        // Get all recognized points and compute bounding box
        let allPoints = pose.availableJointNames.compactMap { name -> CGPoint? in
            guard let point = pose.recognizedPoint(name), point.confidence > 0.1 else { return nil }
            return point.location
        }

        guard !allPoints.isEmpty else { return .zero }

        let xs = allPoints.map { $0.x }
        let ys = allPoints.map { $0.y }

        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!

        // Add padding
        let padding: CGFloat = 0.05
        return CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(1, maxX - minX + 2 * padding),
            height: min(1, maxY - minY + 2 * padding)
        )
    }

    private func extractBodyEmbedding(from image: CGImage, boundingBox: CGRect) async throws -> [Float] {
        // Use existing OSNet ReID extractor
        // Placeholder - actual implementation uses CoreML model
        return [Float](repeating: 0, count: 512)
    }

    private func extractFaceEmbedding(from image: CGImage, faceRect: CGRect) async throws -> [Float] {
        // Use FaceNet CoreML model
        // Placeholder - actual implementation uses CoreML model
        return [Float](repeating: 0, count: 128)
    }
}

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
```

#### 3.4.4 Height Estimation

```swift
class HeightEstimator {
    /// Estimate relative height from pose keypoints
    /// Note: VNHumanBodyPoseObservation.recognizedPoint returns optional, doesn't throw
    static func estimate(from pose: VNHumanBodyPoseObservation,
                        boundingBox: CGRect,
                        frameHeight: CGFloat) -> Float? {
        // Use head-to-ankle distance if both visible
        guard let head = pose.recognizedPoint(.nose),
              let leftAnkle = pose.recognizedPoint(.leftAnkle),
              head.confidence > 0.5,
              leftAnkle.confidence > 0.5 else {
            // Fallback to bounding box height
            guard frameHeight > 0 else { return nil }
            return Float(boundingBox.height / frameHeight)
        }

        let personHeight = abs(head.location.y - leftAnkle.location.y)
        return Float(personHeight)  // Normalized 0-1 in Vision coordinates
    }

    /// Compare heights with tolerance for pose variation
    static func similarity(_ h1: Float?, _ h2: Float?, tolerance: Float = 0.15) -> Float {
        guard let h1 = h1, let h2 = h2, h1 > 0, h2 > 0 else { return 0.5 }  // Neutral if missing
        let diff = abs(h1 - h2)
        if diff < tolerance {
            return 1.0 - (diff / tolerance) * 0.5  // 0.5-1.0 range
        } else {
            return max(0, 0.5 - (diff - tolerance) / tolerance)  // 0.0-0.5 range
        }
    }
}
```

### 3.5 Phase 2: Tracklet Formation

Create short, high-confidence tracklets using strict association criteria.

```swift
/// Thread-safe tracklet builder using serial queue for state mutations
class TrackletBuilder {
    // MARK: - Configuration

    let strictIoUThreshold: Float = 0.5       // Much stricter than current 0.15
    let strictDistanceThreshold: Float = 0.2  // Much stricter than current 0.45
    let appearanceThreshold: Float = 0.80     // High confidence only

    // MARK: - State (protected by serial queue)

    private let stateQueue = DispatchQueue(label: "com.liquideditor.trackletbuilder")
    private var activeTracklets: [UUID: Tracklet] = [:]
    private var completedTracklets: [Tracklet] = []

    // MARK: - Public API

    func processFrame(detections: [MultiModalDetection]) {
        stateQueue.sync {
            // 1. Try to extend existing tracklets
            var unmatchedDetections = detections
            var extendedTrackletIds: Set<UUID> = []

            for detection in detections {
                if let (trackletId, _) = findBestMatchUnsafe(for: detection) {
                    activeTracklets[trackletId]?.detections.append(
                        (frameIndex: detection.frameIndex, detection: detection)
                    )
                    extendedTrackletIds.insert(trackletId)
                    unmatchedDetections.removeAll { $0.detectionId == detection.detectionId }
                }
            }

            // 2. Close tracklets that weren't extended
            for (id, tracklet) in activeTracklets where !extendedTrackletIds.contains(id) {
                completedTracklets.append(tracklet)
                activeTracklets.removeValue(forKey: id)
            }

            // 3. Start new tracklets for unmatched detections
            for detection in unmatchedDetections {
                let newTracklet = Tracklet(
                    id: UUID(),
                    detections: [(frameIndex: detection.frameIndex, detection: detection)]
                )
                activeTracklets[newTracklet.id] = newTracklet
            }
        }
    }

    func finalize() -> [Tracklet] {
        return stateQueue.sync {
            // Close all remaining active tracklets
            completedTracklets.append(contentsOf: activeTracklets.values)
            activeTracklets.removeAll()

            // Filter out very short tracklets (likely noise)
            return completedTracklets.filter { $0.duration >= 3 }
        }
    }

    // MARK: - Private (must be called within stateQueue.sync)

    private func findBestMatchUnsafe(for detection: MultiModalDetection) -> (UUID, Float)? {
        var bestMatch: (UUID, Float)? = nil

        for (id, tracklet) in activeTracklets {
            guard let lastDetection = tracklet.detections.last else { continue }

            // Must be adjacent frame
            guard detection.frameIndex == lastDetection.frameIndex + 1 else { continue }

            // Check all criteria (AND logic - all must pass)
            let iou = computeIoU(detection.bodyBoundingBox, lastDetection.detection.bodyBoundingBox)
            guard iou > strictIoUThreshold else { continue }

            let dist = computeNormalizedDistance(detection.bodyBoundingBox, lastDetection.detection.bodyBoundingBox)
            guard dist < strictDistanceThreshold else { continue }

            let appearance = cosineSimilarity(detection.bodyEmbedding, lastDetection.detection.bodyEmbedding)
            guard appearance > appearanceThreshold else { continue }

            // Combined score for ranking
            let score = 0.3 * iou + 0.3 * (1 - dist) + 0.4 * appearance

            if bestMatch == nil || score > bestMatch!.1 {
                bestMatch = (id, score)
            }
        }

        return bestMatch
    }
}
```

### 3.6 Phase 3: Global Optimization

#### 3.6.1 Affinity Matrix with Constraints

```swift
class AffinityMatrixBuilder {
    /// Large negative value for "definitely different" (NOT infinity to avoid numerical issues)
    static let MUST_BE_DIFFERENT: Float = -1e6

    /// Build pairwise affinity matrix for all tracklets
    func buildAffinityMatrix(tracklets: [Tracklet]) -> (matrix: [[Float]], trackletIds: [TrackletID]) {
        let n = tracklets.count
        let trackletIds = tracklets.map { $0.id }

        // Initialize with zeros
        var affinity = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)

        // Compute pairwise similarities
        for i in 0..<n {
            for j in (i+1)..<n {
                let sim = computeTrackletSimilarity(tracklets[i], tracklets[j])
                affinity[i][j] = sim
                affinity[j][i] = sim
            }
            affinity[i][i] = 1.0  // Self-similarity
        }

        return (affinity, trackletIds)
    }

    func computeTrackletSimilarity(_ t1: Tracklet, _ t2: Tracklet) -> Float {
        // HARD CONSTRAINT: Same frame = definitely different people
        if trackletsOverlapInTime(t1, t2) {
            return Self.MUST_BE_DIFFERENT
        }

        // HARD CONSTRAINT: Different jersey numbers = definitely different
        if JerseyNumberDetector.numbersAreDifferent(t1.jerseyNumber, t2.jerseyNumber) {
            return Self.MUST_BE_DIFFERENT
        }

        // STRONG SIGNAL: Same jersey number = likely same person (but not definitive - could be same team)
        var jerseyBonus: Float = 0
        if JerseyNumberDetector.numbersAreSame(t1.jerseyNumber, t2.jerseyNumber) {
            jerseyBonus = 0.2  // Add bonus to similarity
        }

        // Body appearance similarity (always available)
        let bodySim = cosineSimilarity(t1.aggregatedBodyEmbedding, t2.aggregatedBodyEmbedding)

        // Face similarity (if both have faces)
        var faceSim: Float? = nil
        var faceWeight: Float = 0
        if let face1 = t1.bestFaceEmbedding, let face2 = t2.bestFaceEmbedding {
            faceSim = cosineSimilarity(face1, face2)
            faceWeight = 0.25
        }

        // Color histogram similarity
        let colorSim = t1.aggregatedColorHistogram.similarity(to: t2.aggregatedColorHistogram)

        // Spatial-temporal consistency (are trajectories compatible?)
        let stSim = spatialTemporalConsistency(t1, t2)

        // Height consistency
        let heightSim = computeHeightConsistency(t1, t2)

        // Weighted combination (weights adjust based on available features)
        var totalWeight: Float = 0
        var weightedSum: Float = 0

        // Body (always present)
        weightedSum += 0.35 * bodySim
        totalWeight += 0.35

        // Face (if available)
        if let faceSim = faceSim {
            weightedSum += faceWeight * faceSim
            totalWeight += faceWeight
        }

        // Color
        weightedSum += 0.15 * colorSim
        totalWeight += 0.15

        // Spatial-temporal
        weightedSum += 0.15 * stSim
        totalWeight += 0.15

        // Height
        weightedSum += 0.10 * heightSim
        totalWeight += 0.10

        let baseSimilarity = weightedSum / totalWeight
        return min(1.0, baseSimilarity + jerseyBonus)
    }

    private func trackletsOverlapInTime(_ t1: Tracklet, _ t2: Tracklet) -> Bool {
        return !(t1.endFrame < t2.startFrame || t2.endFrame < t1.startFrame)
    }

    private func spatialTemporalConsistency(_ t1: Tracklet, _ t2: Tracklet) -> Float {
        // Check if the person could physically move between tracklet endpoints
        let (earlier, later) = t1.endFrame < t2.startFrame ? (t1, t2) : (t2, t1)

        guard let lastPos = earlier.detections.last?.detection.bodyBoundingBox,
              let firstPos = later.detections.first?.detection.bodyBoundingBox else {
            return 0.5  // Neutral if can't compute
        }

        let frameDiff = later.startFrame - earlier.endFrame
        let distance = hypot(lastPos.midX - firstPos.midX, lastPos.midY - firstPos.midY)

        // Maximum reasonable movement: 0.1 normalized units per frame
        let maxDistance = Float(frameDiff) * 0.1

        if distance < maxDistance {
            return 1.0 - (Float(distance) / maxDistance) * 0.5
        } else {
            return max(0, 0.5 - (Float(distance) - maxDistance) / maxDistance)
        }
    }

    private func computeHeightConsistency(_ t1: Tracklet, _ t2: Tracklet) -> Float {
        let heights1 = t1.detections.compactMap { $0.detection.heightEstimate }
        let heights2 = t2.detections.compactMap { $0.detection.heightEstimate }

        guard !heights1.isEmpty, !heights2.isEmpty else { return 0.5 }

        let avgHeight1 = heights1.reduce(0, +) / Float(heights1.count)
        let avgHeight2 = heights2.reduce(0, +) / Float(heights2.count)

        return HeightEstimator.similarity(avgHeight1, avgHeight2)
    }
}
```

#### 3.6.2 Co-occurrence Constraints

```swift
class CooccurrenceConstraintManager {
    /// Tracklet pairs that MUST be different people (same frame)
    var mustBeDifferent: Set<TrackletPair> = []

    /// Tracklet pairs that are LIKELY different (frequently co-occur)
    var likelyDifferent: [(TrackletPair, Float)] = []  // (pair, confidence)

    struct TrackletPair: Hashable {
        let id1: TrackletID
        let id2: TrackletID

        init(_ a: TrackletID, _ b: TrackletID) {
            // Canonical ordering
            if a.uuidString < b.uuidString {
                id1 = a; id2 = b
            } else {
                id1 = b; id2 = a
            }
        }
    }

    func buildConstraints(tracklets: [Tracklet], totalFrames: Int) {
        // Build frame -> tracklets index
        var frameToTracklets: [Int: [TrackletID]] = [:]
        for tracklet in tracklets {
            for frame in tracklet.startFrame...tracklet.endFrame {
                frameToTracklets[frame, default: []].append(tracklet.id)
            }
        }

        // Find co-occurring tracklets
        var cooccurrenceCounts: [TrackletPair: Int] = [:]

        for frame in 0..<totalFrames {
            guard let trackletIds = frameToTracklets[frame], trackletIds.count >= 2 else { continue }

            for i in 0..<trackletIds.count {
                for j in (i+1)..<trackletIds.count {
                    let pair = TrackletPair(trackletIds[i], trackletIds[j])
                    mustBeDifferent.insert(pair)
                    cooccurrenceCounts[pair, default: 0] += 1
                }
            }
        }

        // Pairs that co-occur frequently are very likely different
        for (pair, count) in cooccurrenceCounts {
            let confidence = min(Float(count) / 30.0, 1.0)  // Saturate at 30 frames
            if confidence > 0.5 {
                likelyDifferent.append((pair, confidence))
            }
        }
    }

    func applyConstraints(to affinity: inout [[Float]], trackletIds: [TrackletID]) {
        let idToIndex = Dictionary(uniqueKeysWithValues: trackletIds.enumerated().map { ($1, $0) })

        for pair in mustBeDifferent {
            guard let i = idToIndex[pair.id1], let j = idToIndex[pair.id2] else { continue }
            affinity[i][j] = AffinityMatrixBuilder.MUST_BE_DIFFERENT
            affinity[j][i] = AffinityMatrixBuilder.MUST_BE_DIFFERENT
        }
    }
}
```

#### 3.6.3 Correlation Clustering (Replaces Hungarian)

```swift
/// Correlation clustering groups items to minimize disagreement with pairwise labels.
/// Unlike spectral clustering, it naturally handles negative affinities (must-not-link constraints).
class CorrelationClusterer {

    /// Cluster tracklets using greedy pivot algorithm
    /// - Parameters:
    ///   - affinity: Pairwise affinity matrix (positive = same, negative = different)
    ///   - threshold: Similarity threshold to consider "same person"
    /// - Returns: Array of clusters, each containing tracklet indices
    func cluster(affinity: [[Float]], threshold: Float = 0.5) -> [[Int]] {
        let n = affinity.count
        guard n > 0 else { return [] }

        var unclustered = Set(0..<n)
        var clusters: [[Int]] = []

        while !unclustered.isEmpty {
            // Pick pivot (highest average affinity to unclustered items)
            let pivot = selectPivot(affinity: affinity, candidates: unclustered)
            unclustered.remove(pivot)

            var cluster = [pivot]

            // Add items with positive affinity to pivot
            for item in unclustered {
                if affinity[pivot][item] > threshold {
                    // Check consistency with existing cluster members
                    // Guard against empty cluster (shouldn't happen since pivot is added, but defensive)
                    guard !cluster.isEmpty else {
                        cluster.append(item)
                        continue
                    }
                    let avgAffinityToCluster = cluster.map { affinity[item][$0] }.reduce(0, +) / Float(cluster.count)
                    if avgAffinityToCluster > threshold {
                        cluster.append(item)
                    }
                }
            }

            // Remove clustered items
            for item in cluster {
                unclustered.remove(item)
            }

            clusters.append(cluster)
        }

        return clusters
    }

    /// Advanced: Use ILP solver for optimal correlation clustering
    func clusterOptimal(affinity: [[Float]]) -> [[Int]] {
        // For small instances (< 100 tracklets), can use exact ILP
        // For larger instances, use greedy or LP relaxation

        if affinity.count < 100 {
            return clusterWithILP(affinity)
        } else {
            return cluster(affinity: affinity)
        }
    }

    private func selectPivot(affinity: [[Float]], candidates: Set<Int>) -> Int {
        var bestPivot = candidates.first!
        var bestScore: Float = -.infinity

        for candidate in candidates {
            let score = candidates.filter { $0 != candidate }
                .map { affinity[candidate][$0] }
                .reduce(0, +)
            if score > bestScore {
                bestScore = score
                bestPivot = candidate
            }
        }

        return bestPivot
    }

    private func clusterWithILP(_ affinity: [[Float]]) -> [[Int]] {
        // Placeholder for ILP formulation
        // In practice, use a library like OR-Tools or Gurobi
        // Fallback to greedy for now
        return cluster(affinity: affinity)
    }
}
```

#### 3.6.4 Hierarchical Clustering for Scalability

```swift
/// For videos with many tracklets (>500), use hierarchical approach
class HierarchicalTrackletClusterer {
    let windowSize: Int = 300  // Frames per window
    let overlapSize: Int = 50  // Overlap between windows

    func cluster(tracklets: [Tracklet], totalFrames: Int) -> [[Tracklet]] {
        // 1. Partition tracklets by time windows
        var windows: [[Tracklet]] = []
        var windowStart = 0

        while windowStart < totalFrames {
            let windowEnd = min(windowStart + windowSize, totalFrames)
            let windowTracklets = tracklets.filter { tracklet in
                tracklet.startFrame < windowEnd && tracklet.endFrame >= windowStart
            }
            windows.append(windowTracklets)
            windowStart += windowSize - overlapSize
        }

        // 2. Cluster within each window
        let correlationClusterer = CorrelationClusterer()
        var windowClusters: [[[Tracklet]]] = []

        for windowTracklets in windows {
            let builder = AffinityMatrixBuilder()
            let (affinity, ids) = builder.buildAffinityMatrix(tracklets: windowTracklets)
            let clusterIndices = correlationClusterer.cluster(affinity: affinity)
            let clusters = clusterIndices.map { indices in
                indices.map { windowTracklets[$0] }
            }
            windowClusters.append(clusters)
        }

        // 3. Merge clusters across windows using overlap regions
        return mergeAcrossWindows(windowClusters)
    }

    private func mergeAcrossWindows(_ windowClusters: [[[Tracklet]]]) -> [[Tracklet]] {
        guard !windowClusters.isEmpty else { return [] }

        var mergedClusters = windowClusters[0]

        for i in 1..<windowClusters.count {
            mergedClusters = mergeTwoWindows(mergedClusters, windowClusters[i])
        }

        return mergedClusters
    }

    private func mergeTwoWindows(_ clusters1: [[Tracklet]], _ clusters2: [[Tracklet]]) -> [[Tracklet]] {
        // Find best matching clusters based on shared or similar tracklets in overlap
        var merged: [[Tracklet]] = []
        var usedFromSecond: Set<Int> = []

        for cluster1 in clusters1 {
            var bestMatch: Int? = nil
            var bestScore: Float = 0

            for (j, cluster2) in clusters2.enumerated() {
                let score = clusterSimilarity(cluster1, cluster2)
                if score > bestScore && score > 0.5 {
                    bestScore = score
                    bestMatch = j
                }
            }

            if let match = bestMatch {
                // Merge clusters
                var combined = cluster1
                combined.append(contentsOf: clusters2[match])
                // Deduplicate by tracklet ID (values from grouping are never empty, but use compactMap for safety)
                let uniqueTracklets = Dictionary(grouping: combined) { $0.id }
                    .values
                    .compactMap { $0.first }
                merged.append(uniqueTracklets)
                usedFromSecond.insert(match)
            } else {
                merged.append(cluster1)
            }
        }

        // Add unmatched clusters from second window
        for (j, cluster2) in clusters2.enumerated() where !usedFromSecond.contains(j) {
            merged.append(cluster2)
        }

        return merged
    }

    private func clusterSimilarity(_ c1: [Tracklet], _ c2: [Tracklet]) -> Float {
        // Check for shared tracklet IDs
        let ids1 = Set(c1.map { $0.id })
        let ids2 = Set(c2.map { $0.id })
        let shared = ids1.intersection(ids2).count

        if shared > 0 {
            return Float(shared) / Float(min(ids1.count, ids2.count))
        }

        // Check appearance similarity of aggregated embeddings
        let emb1 = elementWiseMean(c1.map { $0.aggregatedBodyEmbedding })
        let emb2 = elementWiseMean(c2.map { $0.aggregatedBodyEmbedding })

        return cosineSimilarity(emb1, emb2)
    }
}
```

### 3.7 Phase 4: Merge, Repair & Refine

#### 3.7.1 Track Merger

```swift
class TrackMerger {
    func mergeTracklets(clusters: [[Tracklet]]) -> [PersonTrack] {
        var personTracks: [PersonTrack] = []

        for cluster in clusters {
            // Sort tracklets by start time
            let sorted = cluster.sorted { $0.startFrame < $1.startFrame }

            // Create person track
            var track = PersonTrack(id: UUID(), tracklets: sorted)

            // Interpolate gaps between tracklets
            track.interpolateGaps()

            personTracks.append(track)
        }

        return personTracks
    }
}
```

#### 3.7.2 Swap Detection & Repair

```swift
/// Swap detector with thread-safe track modification
class SwapDetector {
    let appearanceChangeThreshold: Float = 0.3  // Significant change
    let swapImprovementMargin: Float = 0.1      // Improvement needed to swap
    private let swapQueue = DispatchQueue(label: "com.liquideditor.swapdetector")

    func detectAndRepairSwaps(tracks: inout [PersonTrack]) {
        // Note: This method modifies tracks in-place. Caller must ensure
        // exclusive access. For concurrent access, use detectAndRepairSwapsConcurrent.
        // Find frames where multiple tracks have sudden appearance changes
        let suspiciousFrames = findSuspiciousFrames(tracks)

        for frame in suspiciousFrames {
            let tracksAtFrame = tracks.enumerated().filter { $0.element.containsFrame(frame) }
            guard tracksAtFrame.count >= 2 else { continue }

            // Check all pairs for potential swap
            for i in 0..<tracksAtFrame.count {
                for j in (i+1)..<tracksAtFrame.count {
                    let (idx1, track1) = tracksAtFrame[i]
                    let (idx2, track2) = tracksAtFrame[j]

                    if swapWouldImprove(track1, track2, atFrame: frame) {
                        swapTracks(&tracks, idx1, idx2, fromFrame: frame)
                    }
                }
            }
        }
    }

    private func findSuspiciousFrames(_ tracks: [PersonTrack]) -> [Int] {
        var suspicious: Set<Int> = []

        for track in tracks {
            let detections = track.allDetections
            for i in 1..<detections.count {
                let prev = detections[i-1].detection
                let curr = detections[i].detection

                let similarity = cosineSimilarity(prev.bodyEmbedding, curr.bodyEmbedding)
                if similarity < (1.0 - appearanceChangeThreshold) {
                    suspicious.insert(detections[i].frameIndex)
                }
            }
        }

        return suspicious.sorted()
    }

    private func swapWouldImprove(_ track1: PersonTrack,
                                  _ track2: PersonTrack,
                                  atFrame frame: Int) -> Bool {
        // Calculate consistency before swap
        let beforeConsistency = track1.appearanceConsistency(around: frame) +
                               track2.appearanceConsistency(around: frame)

        // Simulate swap and calculate consistency after
        let afterConsistency = simulatedConsistencyAfterSwap(track1, track2, atFrame: frame)

        return afterConsistency > beforeConsistency + swapImprovementMargin
    }

    private func simulatedConsistencyAfterSwap(_ track1: PersonTrack,
                                               _ track2: PersonTrack,
                                               atFrame frame: Int) -> Float {
        // Get embeddings before and after swap point
        let t1Before = track1.allDetections.filter { $0.frameIndex < frame }.map { $0.detection.bodyEmbedding }
        let t1After = track1.allDetections.filter { $0.frameIndex >= frame }.map { $0.detection.bodyEmbedding }
        let t2Before = track2.allDetections.filter { $0.frameIndex < frame }.map { $0.detection.bodyEmbedding }
        let t2After = track2.allDetections.filter { $0.frameIndex >= frame }.map { $0.detection.bodyEmbedding }

        // After swap: t1 = t1Before + t2After, t2 = t2Before + t1After
        let swapped1 = t1Before + t2After
        let swapped2 = t2Before + t1After

        let consistency1 = swapped1.isEmpty ? 1.0 : computeAveragePairwiseSimilarity(swapped1)
        let consistency2 = swapped2.isEmpty ? 1.0 : computeAveragePairwiseSimilarity(swapped2)

        return consistency1 + consistency2
    }

    private func swapTracks(_ tracks: inout [PersonTrack],
                           _ idx1: Int,
                           _ idx2: Int,
                           fromFrame frame: Int) {
        // Extract tracklets from frame onward
        let track1Tracklets = tracks[idx1].tracklets.filter { $0.startFrame >= frame }
        let track2Tracklets = tracks[idx2].tracklets.filter { $0.startFrame >= frame }

        // Remove from original tracks
        tracks[idx1].tracklets.removeAll { $0.startFrame >= frame }
        tracks[idx2].tracklets.removeAll { $0.startFrame >= frame }

        // Swap
        tracks[idx1].tracklets.append(contentsOf: track2Tracklets)
        tracks[idx2].tracklets.append(contentsOf: track1Tracklets)

        // Resort
        tracks[idx1].tracklets.sort { $0.startFrame < $1.startFrame }
        tracks[idx2].tracklets.sort { $0.startFrame < $1.startFrame }
    }
}
```

#### 3.7.3 Bidirectional Consensus

```swift
class BidirectionalTracker {
    let trackletBuilder = TrackletBuilder()

    func trackWithConsensus(frames: [Frame]) -> [PersonTrack] {
        // Forward pass
        let forwardTracklets = buildTracklets(frames: frames)

        // Backward pass
        let backwardTracklets = buildTracklets(frames: frames.reversed())

        // Cluster each direction
        let forwardClusters = clusterTracklets(forwardTracklets)
        let backwardClusters = clusterTracklets(backwardTracklets)

        // Consensus: merge where both agree
        return mergeWithConsensus(forwardClusters, backwardClusters)
    }

    private func buildTracklets(frames: [Frame]) -> [Tracklet] {
        let builder = TrackletBuilder()
        for frame in frames {
            let detections = extractDetections(from: frame)
            builder.processFrame(detections: detections)
        }
        return builder.finalize()
    }

    private func clusterTracklets(_ tracklets: [Tracklet]) -> [[Tracklet]] {
        let builder = AffinityMatrixBuilder()
        let (affinity, _) = builder.buildAffinityMatrix(tracklets: tracklets)
        let clusterer = CorrelationClusterer()
        let indices = clusterer.cluster(affinity: affinity)
        return indices.map { $0.map { tracklets[$0] } }
    }

    private func mergeWithConsensus(_ forward: [[Tracklet]],
                                   _ backward: [[Tracklet]]) -> [PersonTrack] {
        // Find clusters that agree between forward and backward
        var consensusTracks: [PersonTrack] = []

        for fCluster in forward {
            // Find best matching backward cluster
            var bestMatch: [Tracklet]? = nil
            var bestOverlap = 0

            for bCluster in backward {
                let overlap = countOverlappingFrames(fCluster, bCluster)
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestMatch = bCluster
                }
            }

            if let match = bestMatch, bestOverlap > 0 {
                // Create consensus track
                let merged = mergeClusterPair(fCluster, match)
                let track = PersonTrack(id: UUID(), tracklets: merged)
                consensusTracks.append(track)
            }
        }

        return consensusTracks
    }

    private func countOverlappingFrames(_ c1: [Tracklet], _ c2: [Tracklet]) -> Int {
        let frames1 = Set(c1.flatMap { $0.startFrame...$0.endFrame })
        let frames2 = Set(c2.flatMap { $0.startFrame...$0.endFrame })
        return frames1.intersection(frames2).count
    }

    private func mergeClusterPair(_ c1: [Tracklet], _ c2: [Tracklet]) -> [Tracklet] {
        // Keep tracklets where both directions agree on identity
        var merged: [Tracklet] = []

        for t1 in c1 {
            if c2.contains(where: { $0.id == t1.id }) {
                merged.append(t1)
            }
        }

        return merged
    }

    private func extractDetections(from frame: Frame) -> [MultiModalDetection] {
        // Placeholder - actual implementation in MultiModalDetector
        return []
    }
}
```

#### 3.7.4 People Library Integration

```swift
class PeopleLibraryMatcher {
    let personLibrary: PersonLibrary  // Existing named persons
    let matchThreshold: Float = 0.70

    init(personLibrary: PersonLibrary) {
        self.personLibrary = personLibrary
    }

    /// Assign identities from People Library to tracks
    func assignIdentities(to tracks: inout [PersonTrack]) {
        for i in 0..<tracks.count {
            // Get aggregated appearance for this track
            let trackEmbedding = tracks[i].tracklets.flatMap { $0.detections }
                .map { $0.detection.bodyEmbedding }
            guard !trackEmbedding.isEmpty else { continue }
            let avgEmbedding = elementWiseMean(trackEmbedding)

            // Find best matching person in library
            if let (personId, personName, confidence) = personLibrary.findBestMatch(
                embedding: avgEmbedding,
                threshold: matchThreshold
            ) {
                tracks[i].assignedPersonId = personId
                tracks[i].assignedPersonName = personName
                tracks[i].identityConfidence = confidence
            }
        }
    }

    /// Handle case where same person is assigned to multiple overlapping tracks
    func resolveConflicts(tracks: inout [PersonTrack]) {
        // Group tracks by assigned person
        let byPerson = Dictionary(grouping: tracks.enumerated().map { ($0, $1) }) {
            $0.1.assignedPersonId
        }

        for (personId, tracksWithIndex) in byPerson {
            guard personId != nil, tracksWithIndex.count > 1 else { continue }

            // Check for time overlaps
            for i in 0..<tracksWithIndex.count {
                for j in (i+1)..<tracksWithIndex.count {
                    let (idx1, track1) = tracksWithIndex[i]
                    let (idx2, track2) = tracksWithIndex[j]

                    if tracksOverlapInTime(track1, track2) {
                        // Keep the one with higher confidence, clear the other
                        if track1.identityConfidence >= track2.identityConfidence {
                            tracks[idx2].assignedPersonId = nil
                            tracks[idx2].assignedPersonName = nil
                            tracks[idx2].identityConfidence = 0
                        } else {
                            tracks[idx1].assignedPersonId = nil
                            tracks[idx1].assignedPersonName = nil
                            tracks[idx1].identityConfidence = 0
                        }
                    }
                }
            }
        }
    }

    private func tracksOverlapInTime(_ t1: PersonTrack, _ t2: PersonTrack) -> Bool {
        return !(t1.endFrame < t2.startFrame || t2.endFrame < t1.startFrame)
    }
}
```

#### 3.7.5 User Oracle Keyframes

```swift
protocol UserOracleDelegate: AnyObject {
    func requestUserVerification(frame: Int,
                                 boundingBox: CGRect,
                                 currentName: String?,
                                 confidence: Float) async -> UserVerificationResult
}

struct UserVerificationResult {
    let confirmed: Bool
    let correctedPersonId: UUID?
    let correctedName: String?
}

class OracleKeyframeManager {
    weak var delegate: UserOracleDelegate?

    /// User-marked keyframes for definitive identity
    var userMarkedKeyframes: [Int: [PersonIdentity]] = [:]

    /// Propagate user markings to tracks
    func propagateUserMarkings(tracks: inout [PersonTrack]) {
        for (frame, identities) in userMarkedKeyframes {
            for identity in identities {
                // Find track at this frame matching the position
                for i in 0..<tracks.count {
                    if let detection = tracks[i].detectionAt(frame),
                       boxesOverlap(detection.bodyBoundingBox, identity.position, threshold: 0.5) {
                        tracks[i].assignedPersonId = identity.personId
                        tracks[i].assignedPersonName = identity.name
                        tracks[i].identityConfidence = 1.0  // User-confirmed
                        tracks[i].confirmedByUser = true
                        tracks[i].userConfirmedAtFrame = frame
                        break
                    }
                }
            }
        }
    }

    /// Request verification for low-confidence tracks
    func requestVerificationForLowConfidence(tracks: [PersonTrack]) async {
        guard let delegate = delegate else { return }

        for track in tracks where !track.confirmedByUser && track.identityConfidence < 0.5 {
            // Find a representative frame (middle of track)
            let allFrames = track.allDetections.map { $0.frameIndex }
            guard !allFrames.isEmpty else { continue }

            let midIndex = allFrames.count / 2
            let representativeFrame = allFrames[midIndex]

            guard let detection = track.detectionAt(representativeFrame) else { continue }

            let result = await delegate.requestUserVerification(
                frame: representativeFrame,
                boundingBox: detection.bodyBoundingBox,
                currentName: track.assignedPersonName,
                confidence: track.identityConfidence
            )

            if result.confirmed {
                // User confirmed current identity
                userMarkedKeyframes[representativeFrame, default: []].append(
                    PersonIdentity(
                        personId: track.assignedPersonId ?? UUID(),
                        name: track.assignedPersonName ?? "Unknown",
                        position: detection.bodyBoundingBox
                    )
                )
            } else if let correctedId = result.correctedPersonId {
                // User corrected identity
                userMarkedKeyframes[representativeFrame, default: []].append(
                    PersonIdentity(
                        personId: correctedId,
                        name: result.correctedName ?? "Unknown",
                        position: detection.bodyBoundingBox
                    )
                )
            }
        }
    }

    private func boxesOverlap(_ b1: CGRect, _ b2: CGRect, threshold: Float) -> Bool {
        let intersection = b1.intersection(b2)
        guard !intersection.isNull else { return false }
        let unionArea = b1.area + b2.area - intersection.area
        guard unionArea > 0 else { return false }
        let iou = intersection.area / unionArea
        return iou > CGFloat(threshold)
    }
}

// Note: CGRect.area extension defined in Section 13 (Utility Functions)
```

### 3.8 Advanced Techniques

#### 3.8.1 Gait Analysis (Motion Patterns)

```swift
struct GaitSignature {
    let strideLength: Float      // Normalized stride length
    let cadence: Float           // Steps per second
    let armSwingAmplitude: Float // Arm swing range
    let bodySwayPattern: [Float] // Fourier coefficients (8 values)

    static func extract(from tracklet: Tracklet, frameRate: Float) -> GaitSignature? {
        // Need at least 1 second of data (30 frames at 30fps)
        guard tracklet.duration >= Int(frameRate) else { return nil }

        // Extract keypoint trajectories
        let poses = tracklet.detections.compactMap { $0.detection.bodyPose }
        guard poses.count >= Int(frameRate) else { return nil }

        // Hip trajectory for body sway (recognizedPoint returns optional, doesn't throw)
        let hipTrajectory = poses.compactMap { pose -> CGPoint? in
            guard let hip = pose.recognizedPoint(.root), hip.confidence > 0.3 else { return nil }
            return hip.location
        }

        // Ankle trajectory for stride
        let ankleTrajectory = poses.compactMap { pose -> CGPoint? in
            guard let ankle = pose.recognizedPoint(.leftAnkle), ankle.confidence > 0.3 else { return nil }
            return ankle.location
        }

        guard hipTrajectory.count >= Int(frameRate),
              ankleTrajectory.count >= Int(frameRate) else { return nil }

        // FFT for periodic components
        let hipFFT = performFFT(hipTrajectory.map { Float($0.y) })

        return GaitSignature(
            strideLength: computeStrideLength(ankleTrajectory),
            cadence: findDominantFrequency(hipFFT) * frameRate,
            armSwingAmplitude: computeArmSwing(poses),
            bodySwayPattern: Array(hipFFT.prefix(8))
        )
    }

    func similarity(to other: GaitSignature) -> Float {
        // Guard against division by zero
        let maxStride = max(strideLength, other.strideLength)
        let maxCadence = max(cadence, other.cadence)

        let strideSim: Float
        if maxStride > 0.001 {
            strideSim = 1.0 - min(abs(strideLength - other.strideLength) / maxStride, 1.0)
        } else {
            strideSim = 1.0  // Both near zero = same
        }

        let cadenceSim: Float
        if maxCadence > 0.001 {
            cadenceSim = 1.0 - min(abs(cadence - other.cadence) / maxCadence, 1.0)
        } else {
            cadenceSim = 1.0
        }

        let swaySim = cosineSimilaritySafe(bodySwayPattern, other.bodySwayPattern)

        return 0.3 * strideSim + 0.3 * cadenceSim + 0.4 * swaySim
    }

    private static func computeStrideLength(_ trajectory: [CGPoint]) -> Float {
        // Find peaks in vertical movement
        guard trajectory.count >= 3 else { return 0 }
        var peaks: [Int] = []
        for i in 1..<(trajectory.count - 1) {
            if trajectory[i].y > trajectory[i-1].y && trajectory[i].y > trajectory[i+1].y {
                peaks.append(i)
            }
        }
        guard peaks.count >= 2 else { return 0 }

        // Average horizontal distance between peaks
        var totalDist: CGFloat = 0
        for i in 1..<peaks.count {
            totalDist += abs(trajectory[peaks[i]].x - trajectory[peaks[i-1]].x)
        }
        return Float(totalDist / CGFloat(peaks.count - 1))
    }

    private static func computeArmSwing(_ poses: [VNHumanBodyPoseObservation]) -> Float {
        // recognizedPoint returns optional, doesn't throw
        let wristYs = poses.compactMap { pose -> Float? in
            guard let wrist = pose.recognizedPoint(.leftWrist), wrist.confidence > 0.3 else { return nil }
            return Float(wrist.location.y)
        }
        guard let minY = wristYs.min(), let maxY = wristYs.max() else { return 0 }
        return maxY - minY
    }
}

/// Safe cosine similarity that handles zero vectors
func cosineSimilaritySafe(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    let dot = zip(a, b).map(*).reduce(0, +)
    let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))

    guard normA > 1e-6, normB > 1e-6 else { return 0 }
    return dot / (normA * normB)
}
```

#### 3.8.2 Adaptive Threshold Calibration (Replaces Self-Supervised Fine-Tuning)

Since CoreML models cannot be fine-tuned at runtime, we use adaptive threshold calibration instead:

```swift
/// Calibrate thresholds based on video characteristics
class AdaptiveThresholdCalibrator {

    struct CalibratedThresholds {
        var appearanceThreshold: Float
        var iouThreshold: Float
        var distanceThreshold: Float
    }

    /// Analyze video and calibrate thresholds
    func calibrate(tracklets: [Tracklet]) -> CalibratedThresholds {
        // 1. Compute intra-tracklet similarity distribution
        var intraSimilarities: [Float] = []
        for tracklet in tracklets where tracklet.hasConsistentAppearance {
            let embeddings = tracklet.detections.map { $0.detection.bodyEmbedding }
            for i in 0..<embeddings.count {
                for j in (i+1)..<embeddings.count {
                    intraSimilarities.append(cosineSimilarity(embeddings[i], embeddings[j]))
                }
            }
        }

        // 2. Compute inter-tracklet similarity distribution (same frame = different people)
        var interSimilarities: [Float] = []
        let frameToTracklets = buildFrameIndex(tracklets)
        for (_, trackletGroup) in frameToTracklets where trackletGroup.count >= 2 {
            for i in 0..<trackletGroup.count {
                for j in (i+1)..<trackletGroup.count {
                    // Safe access to first detection (skip if empty)
                    guard let det1 = trackletGroup[i].detections.first,
                          let det2 = trackletGroup[j].detections.first else {
                        continue
                    }
                    let emb1 = det1.detection.bodyEmbedding
                    let emb2 = det2.detection.bodyEmbedding
                    interSimilarities.append(cosineSimilarity(emb1, emb2))
                }
            }
        }

        // 3. Find optimal threshold that separates distributions
        let optimalAppearanceThreshold = findOptimalThreshold(
            positives: intraSimilarities,
            negatives: interSimilarities,
            defaultValue: 0.80
        )

        return CalibratedThresholds(
            appearanceThreshold: optimalAppearanceThreshold,
            iouThreshold: 0.5,  // Keep default
            distanceThreshold: 0.2  // Keep default
        )
    }

    private func buildFrameIndex(_ tracklets: [Tracklet]) -> [Int: [Tracklet]] {
        var index: [Int: [Tracklet]] = [:]
        for tracklet in tracklets {
            for frame in tracklet.startFrame...tracklet.endFrame {
                index[frame, default: []].append(tracklet)
            }
        }
        return index
    }

    private func findOptimalThreshold(positives: [Float],
                                      negatives: [Float],
                                      defaultValue: Float) -> Float {
        guard !positives.isEmpty, !negatives.isEmpty else { return defaultValue }

        // Find threshold that maximizes F1 score
        var bestThreshold = defaultValue
        var bestF1: Float = 0

        for threshold in stride(from: 0.5, through: 0.95, by: 0.05) {
            let tp = Float(positives.filter { $0 >= Float(threshold) }.count)
            let fn = Float(positives.filter { $0 < Float(threshold) }.count)
            let fp = Float(negatives.filter { $0 >= Float(threshold) }.count)

            let precision = tp / max(tp + fp, 1)
            let recall = tp / max(tp + fn, 1)
            let f1 = 2 * precision * recall / max(precision + recall, 0.001)

            if f1 > bestF1 {
                bestF1 = f1
                bestThreshold = Float(threshold)
            }
        }

        return bestThreshold
    }
}
```

#### 3.8.3 Temporal Proximity Weighting (Handles Clothing Changes)

```swift
/// Weight appearance similarity by temporal proximity
/// People who change clothes can still be linked if other features match and time gap is small
class TemporalProximityWeighter {

    let maxGapForFullWeight: Int = 30      // Frames (~1 second)
    let decayRate: Float = 0.1             // Weight decay per 30 frames

    func adjustedSimilarity(baseSimilarity: Float,
                           frameDiff: Int,
                           hasOtherStrongSignals: Bool) -> Float {
        // No adjustment for adjacent tracklets
        if frameDiff <= maxGapForFullWeight {
            return baseSimilarity
        }

        // Decay weight for longer gaps
        let gapMultiples = Float(frameDiff) / Float(maxGapForFullWeight)
        let decay = pow(1.0 - decayRate, gapMultiples - 1)

        // If other strong signals (face match, jersey number), decay less
        let adjustedDecay = hasOtherStrongSignals ? sqrt(decay) : decay

        // Blend toward neutral (0.5) as time increases
        return baseSimilarity * adjustedDecay + 0.5 * (1 - adjustedDecay)
    }
}
```

### 3.9 Main Orchestrator Implementation

```swift
import AVFoundation
import os.log

/// Main orchestrator that coordinates all phases of ultra-quality tracking
class UltraQualityTrackingService {
    // MARK: - Dependencies

    private let config: UltraQualityConfig
    private let multiModalDetector: MultiModalDetector
    private let trackletBuilder: TrackletBuilder
    private let affinityBuilder: AffinityMatrixBuilder
    private let clusterer: CorrelationClusterer
    private let hierarchicalClusterer: HierarchicalTrackletClusterer
    private let trackMerger: TrackMerger
    private let swapDetector: SwapDetector
    private let peopleLibraryMatcher: PeopleLibraryMatcher?
    private let progressReporter: ProgressReporter
    private let thermalMonitor: ThermalMonitor
    private let memoryManager: MemoryManager
    private let backgroundTaskManager: BackgroundTaskManager

    // MARK: - State

    private var isCancelled = false
    private let logger = Logger(subsystem: "com.liquideditor", category: "UltraQualityTracking")

    // MARK: - Initialization

    init(config: UltraQualityConfig = .default,
         personLibrary: PersonLibrary? = nil,
         progressReporter: ProgressReporter) {
        self.config = config
        self.multiModalDetector = MultiModalDetector(config: config)
        self.trackletBuilder = TrackletBuilder()
        self.affinityBuilder = AffinityMatrixBuilder()
        self.clusterer = CorrelationClusterer()
        self.hierarchicalClusterer = HierarchicalTrackletClusterer()
        self.trackMerger = TrackMerger()
        self.swapDetector = SwapDetector()
        self.peopleLibraryMatcher = personLibrary.map { PeopleLibraryMatcher(personLibrary: $0) }
        self.progressReporter = progressReporter
        self.thermalMonitor = ThermalMonitor()
        self.memoryManager = MemoryManager(targetUsage: config.targetMemoryUsage)
        self.backgroundTaskManager = BackgroundTaskManager()
    }

    // MARK: - Public API

    /// Main entry point for ultra-quality tracking
    func track(videoURL: URL) async throws -> [PersonTrack] {
        // Input validation
        try validateInput(videoURL: videoURL)

        // Begin background task for iOS
        backgroundTaskManager.beginBackgroundTask()
        defer { backgroundTaskManager.endBackgroundTask() }

        isCancelled = false
        logger.info("Starting ultra-quality tracking for: \(videoURL.lastPathComponent)")

        do {
            // Phase 1: Extract frames and detect features
            logger.info("Phase 1: Multi-modal detection")
            let detections = try await extractDetections(from: videoURL)
            guard !isCancelled else { throw TrackingError.cancelled }

            // Phase 2: Build tracklets
            logger.info("Phase 2: Tracklet formation")
            let tracklets = buildTracklets(from: detections)
            guard !isCancelled else { throw TrackingError.cancelled }

            // Phase 3: Global optimization (clustering)
            logger.info("Phase 3: Global optimization (\(tracklets.count) tracklets)")
            let clusters = try clusterTracklets(tracklets)
            guard !isCancelled else { throw TrackingError.cancelled }

            // Phase 4: Merge and refine
            logger.info("Phase 4: Merge and refine")
            var tracks = mergeClusters(clusters)

            // Swap detection and repair
            if config.enableSwapRepair {
                swapDetector.detectAndRepairSwaps(tracks: &tracks)
            }

            // Assign identities from People Library
            if let matcher = peopleLibraryMatcher {
                matcher.assignIdentities(to: &tracks)
                matcher.resolveConflicts(tracks: &tracks)
            }

            logger.info("Tracking complete: \(tracks.count) person tracks")
            progressReporter.reportProgress(phase: "refinement", current: 100, total: 100)

            return tracks

        } catch {
            logger.error("Tracking failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Cancel ongoing tracking
    func cancel() {
        isCancelled = true
        logger.info("Tracking cancelled by user")
    }

    // MARK: - Input Validation

    private func validateInput(videoURL: URL) throws {
        // Check file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw TrackingError.fileNotFound(videoURL.path)
        }

        // Check file is readable
        guard FileManager.default.isReadableFile(atPath: videoURL.path) else {
            throw TrackingError.fileNotReadable(videoURL.path)
        }

        // Check it's a valid video file
        let asset = AVURLAsset(url: videoURL)
        guard !asset.tracks(withMediaType: .video).isEmpty else {
            throw TrackingError.invalidVideoFile(videoURL.path)
        }

        logger.debug("Input validation passed for: \(videoURL.lastPathComponent)")
    }

    // MARK: - Phase 1: Detection

    private func extractDetections(from videoURL: URL) async throws -> [[MultiModalDetection]] {
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw TrackingError.invalidVideoFile(videoURL.path)
        }

        let duration = asset.duration
        let frameRate = videoTrack.nominalFrameRate
        let totalFrames = Int(CMTimeGetSeconds(duration) * Double(frameRate))

        logger.debug("Video: \(totalFrames) frames at \(frameRate) fps")

        var allDetections: [[MultiModalDetection]] = []
        allDetections.reserveCapacity(totalFrames)

        // Create image generator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        for frameIndex in 0..<totalFrames {
            guard !isCancelled else { break }

            // Check thermal state and throttle if needed
            if thermalMonitor.shouldThrottle() {
                logger.warning("Thermal throttling active, reducing processing rate")
                try await Task.sleep(nanoseconds: 100_000_000)  // 100ms pause
            }

            // Check memory and prune if needed
            if memoryManager.shouldPruneEmbeddings() {
                logger.debug("Memory pressure detected, pruning will occur after tracklet formation")
            }

            let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(frameRate))

            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let frame = Frame(index: frameIndex, timestamp: time, pixelBuffer: nil)
                let detections = try await multiModalDetector.detect(in: cgImage, frame: frame)
                allDetections.append(detections)
            } catch {
                logger.warning("Failed to process frame \(frameIndex): \(error.localizedDescription)")
                allDetections.append([])  // Empty detections for failed frame
            }

            // Report progress
            if frameIndex % 10 == 0 {
                progressReporter.reportProgress(phase: "detection", current: frameIndex, total: totalFrames)
            }
        }

        return allDetections
    }

    // MARK: - Phase 2: Tracklet Formation

    private func buildTracklets(from detections: [[MultiModalDetection]]) -> [Tracklet] {
        let builder = TrackletBuilder()

        for (frameIndex, frameDetections) in detections.enumerated() {
            builder.processFrame(detections: frameDetections)

            if frameIndex % 50 == 0 {
                let progress = Float(frameIndex) / Float(detections.count)
                progressReporter.reportProgress(
                    phase: "tracklet",
                    current: Int(progress * 100),
                    total: 100
                )
            }
        }

        let tracklets = builder.finalize()
        logger.info("Built \(tracklets.count) tracklets")
        return tracklets
    }

    // MARK: - Phase 3: Clustering

    private func clusterTracklets(_ tracklets: [Tracklet]) throws -> [[Tracklet]] {
        guard !tracklets.isEmpty else { return [] }

        progressReporter.reportProgress(phase: "optimization", current: 0, total: 100)

        // Choose clustering strategy based on tracklet count
        let clusters: [[Tracklet]]

        if tracklets.count > config.maxTrackletsForDirectClustering && config.enableHierarchicalClustering {
            logger.info("Using hierarchical clustering for \(tracklets.count) tracklets")
            let totalFrames = tracklets.map { $0.endFrame }.max() ?? 0
            clusters = hierarchicalClusterer.cluster(tracklets: tracklets, totalFrames: totalFrames)
        } else {
            logger.info("Using direct correlation clustering for \(tracklets.count) tracklets")

            // Build affinity matrix
            progressReporter.reportProgress(phase: "optimization", current: 20, total: 100)
            let (affinity, _) = affinityBuilder.buildAffinityMatrix(tracklets: tracklets)

            // Apply co-occurrence constraints
            progressReporter.reportProgress(phase: "optimization", current: 40, total: 100)
            var constrainedAffinity = affinity
            let constraintManager = CooccurrenceConstraintManager()
            let totalFrames = tracklets.map { $0.endFrame }.max() ?? 0
            constraintManager.buildConstraints(tracklets: tracklets, totalFrames: totalFrames)
            constraintManager.applyConstraints(to: &constrainedAffinity, trackletIds: tracklets.map { $0.id })

            // Cluster
            progressReporter.reportProgress(phase: "optimization", current: 60, total: 100)
            let clusterIndices = clusterer.cluster(affinity: constrainedAffinity, threshold: config.clusteringThreshold)
            clusters = clusterIndices.map { indices in indices.map { tracklets[$0] } }
        }

        progressReporter.reportProgress(phase: "optimization", current: 100, total: 100)
        logger.info("Formed \(clusters.count) clusters")
        return clusters
    }

    // MARK: - Phase 4: Merge

    private func mergeClusters(_ clusters: [[Tracklet]]) -> [PersonTrack] {
        progressReporter.reportProgress(phase: "refinement", current: 0, total: 100)
        let tracks = trackMerger.mergeTracklets(clusters: clusters)
        progressReporter.reportProgress(phase: "refinement", current: 50, total: 100)
        return tracks
    }
}

// MARK: - Errors

enum TrackingError: LocalizedError {
    case fileNotFound(String)
    case fileNotReadable(String)
    case invalidVideoFile(String)
    case cancelled
    case detectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Video file not found: \(path)"
        case .fileNotReadable(let path):
            return "Video file not readable: \(path)"
        case .invalidVideoFile(let path):
            return "Invalid or corrupted video file: \(path)"
        case .cancelled:
            return "Tracking was cancelled"
        case .detectionFailed(let reason):
            return "Detection failed: \(reason)"
        }
    }
}

// MARK: - Logging Helper

extension Logger {
    func trackingEvent(_ message: String, phase: String, frameIndex: Int? = nil) {
        if let frame = frameIndex {
            self.info("[\(phase)] Frame \(frame): \(message)")
        } else {
            self.info("[\(phase)] \(message)")
        }
    }
}
```

---

## 4. Flutter API Contract

### 4.1 Method Channel Interface

```dart
// lib/services/tracking/ultra_quality_tracking_service.dart

enum TrackingQuality {
  fast,      // Current pipeline (for preview/real-time)
  standard,  // Current + minor improvements
  ultra,     // Full ultra-quality pipeline
}

class UltraQualityTrackingService {
  static const _channel = MethodChannel('com.liquideditor/ultra_tracking');
  static const _progressChannel = EventChannel('com.liquideditor/ultra_tracking/progress');

  /// Start ultra-quality tracking
  Future<List<PersonTrack>> track({
    required String videoPath,
    required TrackingQuality quality,
    List<String>? knownPersonIds,  // From People Library
  }) async {
    final result = await _channel.invokeMethod('track', {
      'videoPath': videoPath,
      'quality': quality.name,
      'knownPersonIds': knownPersonIds,
    });
    return (result as List).map((e) => PersonTrack.fromJson(e)).toList();
  }

  /// Cancel ongoing tracking
  Future<void> cancel() async {
    await _channel.invokeMethod('cancel');
  }

  /// Stream of progress updates
  Stream<TrackingProgress> get progressStream {
    return _progressChannel.receiveBroadcastStream().map((event) {
      return TrackingProgress.fromJson(event);
    });
  }
}

class TrackingProgress {
  final int currentFrame;
  final int totalFrames;
  final String phase;  // 'detection', 'tracklet', 'optimization', 'refinement'
  final double phaseProgress;  // 0.0 to 1.0

  // Phase order and cumulative weights
  static const _phaseOrder = ['detection', 'tracklet', 'optimization', 'refinement'];
  static const _phaseWeights = {
    'detection': 0.4,
    'tracklet': 0.1,
    'optimization': 0.3,
    'refinement': 0.2,
  };

  double get overallProgress {
    // Sum completed phases + current phase progress
    double completed = 0.0;
    for (final p in _phaseOrder) {
      if (p == phase) {
        // Current phase: add partial progress
        return completed + (_phaseWeights[p]! * phaseProgress);
      }
      // Previous phases: fully completed
      completed += _phaseWeights[p]!;
    }
    return completed;
  }

  TrackingProgress({
    required this.currentFrame,
    required this.totalFrames,
    required this.phase,
    required this.phaseProgress,
  });

  factory TrackingProgress.fromJson(Map<String, dynamic> json) {
    return TrackingProgress(
      currentFrame: json['currentFrame'] as int,
      totalFrames: json['totalFrames'] as int,
      phase: json['phase'] as String,
      phaseProgress: (json['phaseProgress'] as num).toDouble(),
    );
  }
}

class PersonTrack {
  final String id;
  final String? assignedPersonId;
  final String? assignedPersonName;
  final double identityConfidence;
  final bool confirmedByUser;
  final int startFrame;
  final int endFrame;
  final List<TrackDetection> detections;

  PersonTrack({
    required this.id,
    this.assignedPersonId,
    this.assignedPersonName,
    required this.identityConfidence,
    required this.confirmedByUser,
    required this.startFrame,
    required this.endFrame,
    required this.detections,
  });

  factory PersonTrack.fromJson(Map<String, dynamic> json) {
    return PersonTrack(
      id: json['id'] as String,
      assignedPersonId: json['assignedPersonId'] as String?,
      assignedPersonName: json['assignedPersonName'] as String?,
      identityConfidence: (json['identityConfidence'] as num).toDouble(),
      confirmedByUser: json['confirmedByUser'] as bool,
      startFrame: json['startFrame'] as int,
      endFrame: json['endFrame'] as int,
      detections: (json['detections'] as List)
          .map((e) => TrackDetection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'assignedPersonId': assignedPersonId,
    'assignedPersonName': assignedPersonName,
    'identityConfidence': identityConfidence,
    'confirmedByUser': confirmedByUser,
    'startFrame': startFrame,
    'endFrame': endFrame,
    'detections': detections.map((d) => d.toJson()).toList(),
  };
}

class TrackDetection {
  final int frameIndex;
  final double x, y, width, height;  // Bounding box (normalized 0-1)
  final double confidence;

  TrackDetection({
    required this.frameIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  factory TrackDetection.fromJson(Map<String, dynamic> json) {
    return TrackDetection(
      frameIndex: json['frameIndex'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'frameIndex': frameIndex,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'confidence': confidence,
  };
}
```

### 4.2 Progress Reporting Protocol

```swift
// Swift side: Report progress to Flutter
class ProgressReporter {
    var progressEventSink: FlutterEventSink?
    private let logger = Logger(subsystem: "com.liquideditor", category: "Progress")

    func reportProgress(phase: String, current: Int, total: Int) {
        let progress = Double(current) / Double(max(total, 1))
        logger.debug("Progress: \(phase) \(Int(progress * 100))%")

        DispatchQueue.main.async { [weak self] in
            self?.progressEventSink?([
                "phase": phase,
                "currentFrame": current,
                "totalFrames": total,
                "phaseProgress": progress
            ])
        }
    }
}
```

### 4.3 Error Handling in Flutter

```dart
// lib/services/tracking/tracking_errors.dart

/// Tracking-specific exceptions
class TrackingException implements Exception {
  final String message;
  final String? code;

  TrackingException(this.message, {this.code});

  @override
  String toString() => 'TrackingException: $message';
}

class VideoFileNotFoundException extends TrackingException {
  VideoFileNotFoundException(String path) : super('Video file not found: $path', code: 'FILE_NOT_FOUND');
}

class InvalidVideoFileException extends TrackingException {
  InvalidVideoFileException(String path) : super('Invalid video file: $path', code: 'INVALID_VIDEO');
}

class TrackingCancelledException extends TrackingException {
  TrackingCancelledException() : super('Tracking was cancelled', code: 'CANCELLED');
}

// In UltraQualityTrackingService:
Future<List<PersonTrack>> track({
  required String videoPath,
  required TrackingQuality quality,
  List<String>? knownPersonIds,
}) async {
  try {
    final result = await _channel.invokeMethod('track', {
      'videoPath': videoPath,
      'quality': quality.name,
      'knownPersonIds': knownPersonIds,
    });
    return (result as List).map((e) => PersonTrack.fromJson(e as Map<String, dynamic>)).toList();
  } on PlatformException catch (e) {
    // Map platform errors to typed exceptions
    switch (e.code) {
      case 'FILE_NOT_FOUND':
        throw VideoFileNotFoundException(videoPath);
      case 'INVALID_VIDEO':
        throw InvalidVideoFileException(videoPath);
      case 'CANCELLED':
        throw TrackingCancelledException();
      default:
        throw TrackingException(e.message ?? 'Unknown error', code: e.code);
    }
  }
}
```

### 4.4 Logging Strategy

The tracking system uses Apple's unified logging (`os.log`) for structured, filterable logs:

```swift
import os.log

// Logger categories for different components
extension Logger {
    static let tracking = Logger(subsystem: "com.liquideditor", category: "Tracking")
    static let detection = Logger(subsystem: "com.liquideditor", category: "Detection")
    static let clustering = Logger(subsystem: "com.liquideditor", category: "Clustering")
    static let progress = Logger(subsystem: "com.liquideditor", category: "Progress")
}

// Usage in components:
Logger.tracking.info("Starting ultra-quality tracking")
Logger.detection.debug("Detected \(count) people in frame \(frameIndex)")
Logger.clustering.warning("High affinity matrix size: \(size)x\(size)")
Logger.tracking.error("Tracking failed: \(error.localizedDescription)")

// Log levels:
// - .debug: Verbose, only in debug builds
// - .info: Normal operations
// - .warning: Recoverable issues
// - .error: Failures
// - .fault: Critical failures (crashes)
```

**Viewing logs:**
```bash
# Stream logs in real-time
log stream --predicate 'subsystem == "com.liquideditor"' --level debug

# Search historical logs
log show --predicate 'subsystem == "com.liquideditor" AND category == "Tracking"' --last 1h
```

---

## 5. Implementation Plan

### 5.1 Phase 1: Foundation (Week 1-3)

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Add face detection (VNDetectFaceRectanglesRequest) | High | 2 days | None |
| Add face embedding extraction (FaceNet CoreML) | High | 3 days | Face detection |
| Implement color histogram extraction | Medium | 2 days | None |
| Implement jersey number OCR | High | 3 days | None |
| Create MultiModalDetection structure | High | 1 day | Above features |
| Implement height/proportion estimation | Medium | 2 days | Body pose |
| Update BoundingBoxTracker to use multi-modal | High | 3 days | MultiModalDetection |
| Create Flutter API contract | High | 1 day | None |

### 5.2 Phase 2: Tracklet System (Week 3-4)

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Implement TrackletBuilder | High | 2 days | Phase 1 |
| Implement Tracklet data structure | High | 1 day | TrackletBuilder |
| Add tracklet quality metrics | Medium | 1 day | Tracklet structure |
| Implement adaptive threshold calibration | High | 2 days | Tracklets |

### 5.3 Phase 3: Global Optimization (Week 4-6)

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Implement AffinityMatrixBuilder | High | 2 days | Phase 2 |
| Implement co-occurrence constraints | High | 2 days | Affinity matrix |
| Implement correlation clustering | High | 4 days | Affinity + constraints |
| Implement hierarchical clustering for scalability | Medium | 3 days | Correlation clustering |
| Add temporal proximity weighting | Medium | 1 day | Affinity matrix |

### 5.4 Phase 4: Refinement (Week 6-8)

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Implement TrackMerger | High | 2 days | Phase 3 |
| Implement SwapDetector | High | 3 days | Merged tracks |
| Implement bidirectional consensus | Medium | 3 days | Core tracker |
| Implement PeopleLibraryMatcher | High | 2 days | Track merger |
| Add user oracle keyframe support | Medium | 2 days | Track merger |
| Final smoothing and interpolation | High | 1 day | All above |

### 5.5 Phase 5: Integration & Testing (Week 8-10)

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Flutter UI for quality selection | High | 2 days | API contract |
| Progress reporting implementation | High | 1 day | Core tracker |
| Cancellation support | Medium | 1 day | Core tracker |
| Unit tests for each component | High | 5 days | All components |
| Integration tests | High | 3 days | All components |
| Performance profiling and optimization | High | 3 days | Integration tests |

### 5.6 Phase 6: Advanced Features (Week 10-12, Optional)

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Add gait analysis | Low | 3 days | Tracklet system |
| Add MGN model (CoreML conversion) | Low | 4 days | None |
| Add PCB model (CoreML conversion) | Low | 4 days | None |
| Implement ensemble fusion | Low | 2 days | Multi-model |

### 5.7 Testing & Validation

| Test Type | Description | Success Criteria |
|-----------|-------------|------------------|
| Unit Tests | Each component in isolation | 100% pass |
| Integration Tests | Full pipeline on test videos | No crashes |
| Accuracy Tests | Benchmark videos with ground truth | >95% accuracy |
| Swap Detection | Videos with crossing people | 0 swaps |
| Split Detection | Videos with occlusion/re-entry | 0 false splits |
| Jersey Number | Sports videos with visible numbers | >90% correct |
| Performance | Processing time measurement | ≤10x current |
| Memory | Peak memory during processing | ≤500MB |

### 5.8 Benchmark Test Videos

| Video | Description | Challenge |
|-------|-------------|-----------|
| `crossing_people.mp4` | Two people walk past each other | Track swap |
| `partial_entry.mp4` | Person enters frame gradually | Track split |
| `occlusion.mp4` | Person walks behind obstacle | Gap filling |
| `reentry.mp4` | Person leaves and returns | Long-term ReID |
| `sports_jersey.mp4` | Sports game with jersey numbers | Number OCR |
| `uniform.mp4` | Multiple people in same uniform | Appearance disambiguation |
| `crowd.mp4` | 10+ people in scene | Scalability |
| `lighting_change.mp4` | Person moves shadow to sun | Appearance variation |

---

## 6. File Structure

```
ios/Runner/Tracking/
├── UltraQuality/
│   ├── Core/
│   │   ├── MultiModalDetector.swift       # Phase 1: Multi-modal detection
│   │   ├── FaceEmbedder.swift             # Phase 1: Face embedding
│   │   ├── ColorHistogram.swift           # Phase 1: Color features
│   │   ├── JerseyNumberDetector.swift     # Phase 1: OCR for jerseys
│   │   ├── HeightEstimator.swift          # Phase 1: Height from pose
│   │   └── BodyProportions.swift          # Phase 1: Body measurements
│   │
│   ├── Tracklet/
│   │   ├── Tracklet.swift                 # Phase 2: Tracklet data structure
│   │   ├── TrackletBuilder.swift          # Phase 2: Conservative formation
│   │   └── AdaptiveThresholdCalibrator.swift # Phase 2: Threshold tuning
│   │
│   ├── Optimization/
│   │   ├── AffinityMatrixBuilder.swift    # Phase 3: Pairwise similarity
│   │   ├── CooccurrenceConstraints.swift  # Phase 3: Hard constraints
│   │   ├── CorrelationClusterer.swift     # Phase 3: Clustering algorithm
│   │   ├── HierarchicalClusterer.swift    # Phase 3: Scalability
│   │   └── TemporalProximityWeighter.swift # Phase 3: Time-aware similarity
│   │
│   ├── Refinement/
│   │   ├── TrackMerger.swift              # Phase 4: Merge split tracks
│   │   ├── SwapDetector.swift             # Phase 4: Detect and repair swaps
│   │   ├── BidirectionalConsensus.swift   # Phase 4: Forward-backward
│   │   ├── PeopleLibraryMatcher.swift     # Phase 4: Named person matching
│   │   └── OracleKeyframeManager.swift    # Phase 4: User verification
│   │
│   ├── Advanced/
│   │   └── GaitAnalyzer.swift             # Phase 6: Motion patterns
│   │
│   ├── Models/
│   │   ├── MultiModalDetection.swift      # Data structures
│   │   ├── PersonTrack.swift              # Final output structure
│   │   └── PersonIdentity.swift           # People Library types
│   │
│   └── UltraQualityTrackingService.swift  # Main orchestrator
│
├── Models/
│   ├── OSNet.mlmodel                      # Body ReID (existing)
│   └── FaceNet.mlmodel                    # Face embedding (new)
│
└── Existing/
    ├── TrackingService.swift              # Keep for fast/standard modes
    ├── BoundingBoxTracker.swift           # Keep as fallback
    └── ReID/                              # Keep existing ReID
```

---

## 7. Configuration

```swift
struct UltraQualityConfig {
    // MARK: - Feature Toggles

    /// Enable face detection and embedding
    let enableFaceDetection: Bool = true

    /// Enable color histogram features
    let enableColorHistogram: Bool = true

    /// Enable jersey number OCR (useful for sports videos)
    let enableJerseyOCR: Bool = true

    /// Enable gait analysis (requires longer sequences)
    let enableGaitAnalysis: Bool = false

    // MARK: - Phase 2: Tracklet Formation

    /// IoU threshold for linking detections (strict)
    let strictIoUThreshold: Float = 0.5

    /// Max center distance for linking (strict)
    let strictDistanceThreshold: Float = 0.2

    /// Appearance similarity threshold for linking
    let trackletAppearanceThreshold: Float = 0.80

    /// Minimum tracklet duration (frames)
    let minTrackletDuration: Int = 3

    // MARK: - Phase 3: Global Optimization

    /// Threshold for correlation clustering
    let clusteringThreshold: Float = 0.5

    /// Use hierarchical clustering for large videos
    let enableHierarchicalClustering: Bool = true

    /// Window size for hierarchical clustering (frames)
    let hierarchicalWindowSize: Int = 300

    // MARK: - Phase 4: Refinement

    /// Enable swap detection and repair
    let enableSwapRepair: Bool = true

    /// Enable bidirectional tracking consensus
    let enableBidirectionalConsensus: Bool = true

    /// Margin for swap detection (higher = fewer false positives)
    let swapDetectionMargin: Float = 0.1

    /// Threshold for People Library matching
    let peopleLibraryMatchThreshold: Float = 0.70

    // MARK: - Performance

    /// Maximum tracklets before using hierarchical clustering
    let maxTrackletsForDirectClustering: Int = 500

    /// Target memory usage (bytes)
    let targetMemoryUsage: Int = 500_000_000  // 500MB

    // MARK: - Factory

    static let `default` = UltraQualityConfig()

    static let maxAccuracy = UltraQualityConfig(
        enableFaceDetection: true,
        enableColorHistogram: true,
        enableJerseyOCR: true,
        enableGaitAnalysis: true,
        strictIoUThreshold: 0.6,
        strictDistanceThreshold: 0.15,
        trackletAppearanceThreshold: 0.85,
        enableSwapRepair: true,
        enableBidirectionalConsensus: true
    )

    static let balanced = UltraQualityConfig(
        enableFaceDetection: true,
        enableColorHistogram: true,
        enableJerseyOCR: false,
        enableGaitAnalysis: false,
        enableBidirectionalConsensus: false
    )
}
```

---

## 8. iOS-Specific Considerations

### 8.1 Background Execution

```swift
class BackgroundTaskManager {
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    func beginBackgroundTask() {
        backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Time expired - save state and clean up
            self?.saveProgressAndCleanup()
            self?.endBackgroundTask()
        }
    }

    func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
    }

    func saveProgressAndCleanup() {
        // Save current tracklets and progress to disk
        // Can be resumed later
    }
}
```

### 8.2 Thermal Throttling

```swift
class ThermalMonitor {
    func shouldThrottle() -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    func adjustProcessingRate(currentFPS: Int) -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return currentFPS
        case .fair:
            return max(currentFPS * 3 / 4, 10)
        case .serious:
            return max(currentFPS / 2, 5)
        case .critical:
            return 1  // Minimal processing
        @unknown default:
            return currentFPS
        }
    }
}
```

### 8.3 Memory Management

```swift
class MemoryManager {
    let targetUsage: Int

    init(targetUsage: Int = 500_000_000) {
        self.targetUsage = targetUsage
    }

    func shouldPruneEmbeddings() -> Bool {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return info.resident_size > targetUsage
        }
        return false
    }

    func pruneOldEmbeddings(tracklets: inout [Tracklet], keepFrames: Int) {
        // Keep only recent frames' embeddings, aggregate older ones
        for i in 0..<tracklets.count {
            if tracklets[i].detections.count > keepFrames {
                // Aggregate old embeddings into single representative
                let oldDetections = tracklets[i].detections.prefix(tracklets[i].detections.count - keepFrames)
                let aggregatedEmbedding = elementWiseMean(oldDetections.map { $0.detection.bodyEmbedding })

                // Replace with aggregated
                // ... (implementation details)
            }
        }
    }
}
```

---

## 9. Migration Strategy

### 9.1 Backward Compatibility

```swift
enum TrackingQuality {
    case fast       // Current pipeline (for preview/real-time)
    case standard   // Current + minor improvements
    case ultra      // Full ultra-quality pipeline
}

class TrackingServiceRouter {
    let fastTracker: TrackingService  // Existing
    let ultraTracker: UltraQualityTrackingService  // New

    func track(video: URL, quality: TrackingQuality) async throws -> [PersonTrack] {
        switch quality {
        case .fast:
            return try await fastTracker.track(video: video)
        case .standard:
            return try await fastTracker.trackWithMinorImprovements(video: video)
        case .ultra:
            return try await ultraTracker.track(video: video)
        }
    }
}
```

### 9.2 Progressive Rollout

1. **Week 1-2**: Implement as separate service, internal testing only
2. **Week 3-4**: Add UI toggle for "High Quality Tracking" (off by default)
3. **Week 5-6**: Enable by default for export, fast mode for preview
4. **Week 7+**: Gather metrics, tune thresholds based on real usage

---

## 10. Success Metrics

| Metric | Current | Target | Measurement Method |
|--------|---------|--------|-------------------|
| Track Swap Rate | ~5% | 0% | Manual annotation on benchmark set |
| Track Split Rate | ~10% | <1% | Automatic: count track IDs per person |
| Identity Accuracy | ~85% | >98% | Ground truth comparison |
| Jersey OCR Accuracy | N/A | >90% | Sports video benchmark |
| Processing Time | 1x | ≤10x | Benchmark video timing |
| Memory Usage | ~300MB | ≤500MB | Peak during processing |
| User Corrections Needed | ~20% | <5% | Track corrections per video |

---

## 11. Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| CoreML model conversion fails | High | Medium | Pre-validate models; use only FaceNet (well-supported) |
| Correlation clustering too slow | Medium | Low | Use hierarchical approach; limit tracklet count |
| Face detection unreliable | Medium | Medium | Face is optional signal; body ReID is primary |
| Memory pressure | High | Medium | Aggressive pruning; hierarchical processing |
| User expects real-time | Low | High | Clear UI: "High Quality (slower)" vs "Fast Preview" |
| Jersey OCR false positives | Medium | Medium | Require high confidence; use as bonus not requirement |
| Thermal throttling | Medium | High | Monitor thermal state; adaptive processing rate |
| Background task killed | High | Medium | Save progress to disk; support resume |

---

## 12. References

### Academic Papers
- "Deep Learning for Person Re-Identification: A Survey" (2019)
- "Bag of Tricks for ReID" (2019) - OSNet baseline
- "Correlation Clustering" - Bansal, Blum, Chawla (2004)
- "Multiple Object Tracking: A Survey" (2021)

### Existing Code References
- `ios/Runner/Tracking/BoundingBoxTracker.swift` - Current IoU association
- `ios/Runner/Tracking/ReID/ReIDExtractor.swift` - Current OSNet wrapper
- `ios/Runner/Tracking/TrackingService.swift` - Current post-processing
- `ios/Runner/Tracking/PersonIdentifier.swift` - People Library matching

### CoreML Models
- OSNet: Already in project
- FaceNet: https://github.com/JohnAustinDev/coreml-facenet (or similar)

---

## 13. Appendix: Utility Functions

```swift
// MARK: - Vector Operations

func elementWiseMean(_ vectors: [[Float]]) -> [Float] {
    guard let first = vectors.first else { return [] }
    let n = Float(vectors.count)
    var result = [Float](repeating: 0, count: first.count)
    for vector in vectors {
        for i in 0..<min(vector.count, result.count) {
            result[i] += vector[i] / n
        }
    }
    return result
}

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    let dot = zip(a, b).map(*).reduce(0, +)
    let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
    guard normA > 1e-6, normB > 1e-6 else { return 0 }
    return dot / (normA * normB)
}

func computeAveragePairwiseSimilarity(_ embeddings: [[Float]]) -> Float {
    guard embeddings.count >= 2 else { return 1.0 }
    var total: Float = 0
    var count = 0
    for i in 0..<embeddings.count {
        for j in (i+1)..<embeddings.count {
            total += cosineSimilarity(embeddings[i], embeddings[j])
            count += 1
        }
    }
    return count > 0 ? total / Float(count) : 1.0
}

// MARK: - Geometry

func computeIoU(_ a: CGRect, _ b: CGRect) -> Float {
    let intersection = a.intersection(b)
    guard !intersection.isNull else { return 0 }
    let union = a.union(b)
    return Float(intersection.area / union.area)
}

func computeNormalizedDistance(_ a: CGRect, _ b: CGRect) -> Float {
    let dx = a.midX - b.midX
    let dy = a.midY - b.midY
    return Float(sqrt(dx * dx + dy * dy))
}

// MARK: - Signal Processing

func performFFT(_ signal: [Float]) -> [Float] {
    // Placeholder - use Accelerate framework in practice
    // vDSP_fft_zrip
    return signal
}

func findDominantFrequency(_ fft: [Float]) -> Float {
    guard let maxIdx = fft.indices.max(by: { fft[$0] < fft[$1] }) else { return 0 }
    return Float(maxIdx) / Float(fft.count)
}

// MARK: - Image Processing

func convertToHSV(_ image: CGImage) -> [(h: Float, s: Float, v: Float, x: CGFloat, y: CGFloat)] {
    // Placeholder - use Core Image or vImage in practice
    return []
}

func buildHistogram(_ pixels: [(h: Float, s: Float, v: Float, x: CGFloat, y: CGFloat)], bins: Int) -> [Float] {
    var histogram = [Float](repeating: 0, count: bins)
    // Quantize HSV values into bins
    // ...
    return histogram
}

extension CGRect {
    var area: CGFloat { width * height }

    func scaled(to size: CGSize) -> CGRect {
        return CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}
```

---

## 14. Appendix: Threshold Tuning Guide

| Parameter | Low Value Effect | High Value Effect | Recommended | Tuning Method |
|-----------|------------------|-------------------|-------------|---------------|
| strictIoUThreshold | More tracklets, shorter | Fewer tracklets, longer | 0.5 | Grid search on validation set |
| strictDistanceThreshold | More tracklets | Fewer, more accurate | 0.2 | Grid search |
| trackletAppearanceThreshold | More links, risk of errors | Fewer links, more splits | 0.80 | Adaptive calibration |
| clusteringThreshold | Over-merge (fewer people) | Over-split (more people) | 0.5 | Eigengap or validation |
| swapDetectionMargin | More swaps detected | Fewer false positives | 0.1 | Precision/recall tradeoff |
| peopleLibraryMatchThreshold | More matches, lower precision | Fewer matches, higher precision | 0.70 | ROC curve analysis |

---

## 15. Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-02 | 1.0 | Initial draft |
| 2026-02-02 | 1.1 | Added glossary, data flow diagram, Jersey OCR, People Library integration |
| 2026-02-02 | 1.2 | Replaced Hungarian with Correlation Clustering, fixed self-supervised to adaptive calibration |
| 2026-02-02 | 2.0 | **Major Review Fixes:** |
| | | - Fixed Vision API usage (recognizedPoint doesn't throw) |
| | | - Fixed Flutter overallProgress calculation |
| | | - Added empty cluster guard in correlation clustering |
| | | - Added full UltraQualityTrackingService orchestrator implementation |
| | | - Added MultiModalDetector implementation |
| | | - Removed duplicate CGRect.area extension |
| | | - Added thread safety (serial queues) for TrackletBuilder and SwapDetector |
| | | - Added PersonTrack and TrackDetection serialization (fromJson/toJson) |
| | | - Added comprehensive error handling (TrackingError enum) |
| | | - Added logging strategy with os.log |
| | | - Added input validation at API boundary |
| | | - Fixed force unwraps with safe optional binding |

---

*Document created: 2026-02-02*
*Last updated: 2026-02-02*
*Author: Claude Code*
*Version: 2.0*
*Status: Ready for Implementation*
*Estimated Timeline: 10-12 weeks*
