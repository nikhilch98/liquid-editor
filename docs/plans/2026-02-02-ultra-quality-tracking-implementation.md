# Ultra-Quality Person Tracking System - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a parallel ultra-quality tracking system that eliminates track swaps and splits through multi-modal detection, tracklet-based association, and global optimization.

**Architecture:** Build in `ios/Runner/Tracking/UltraQuality/` as a parallel system. Router selects between fast (existing) and ultra (new) modes. Multi-modal features feed into tracklet formation, then correlation clustering, then refinement.

**Tech Stack:** Swift, Vision framework, CoreML (OSNet, FaceNet), Flutter platform channels

**Design Doc:** `docs/plans/2026-02-02-ultra-quality-tracking-design.md`

---

## Directory Structure to Create

```
ios/Runner/Tracking/UltraQuality/
├── Core/
│   ├── MultiModalDetector.swift
│   ├── ColorHistogram.swift
│   ├── JerseyNumberDetector.swift
│   ├── HeightEstimator.swift
│   └── BodyProportions.swift
├── Tracklet/
│   ├── Tracklet.swift
│   ├── TrackletBuilder.swift
│   └── AdaptiveThresholdCalibrator.swift
├── Optimization/
│   ├── AffinityMatrixBuilder.swift
│   ├── CooccurrenceConstraints.swift
│   ├── CorrelationClusterer.swift
│   ├── HierarchicalClusterer.swift
│   └── TemporalProximityWeighter.swift
├── Refinement/
│   ├── TrackMerger.swift
│   ├── SwapDetector.swift
│   ├── BidirectionalConsensus.swift
│   ├── PeopleLibraryMatcher.swift
│   └── OracleKeyframeManager.swift
├── Advanced/
│   └── GaitAnalyzer.swift
├── Models/
│   ├── MultiModalDetection.swift
│   ├── PersonTrack.swift
│   └── UltraQualityConfig.swift
├── Support/
│   ├── VectorMath.swift
│   ├── ProgressReporter.swift
│   ├── ThermalMonitor.swift
│   ├── MemoryManager.swift
│   └── BackgroundTaskManager.swift
├── UltraQualityTrackingService.swift
└── TrackingServiceRouter.swift

lib/services/tracking/
├── ultra_quality_tracking_service.dart
└── tracking_errors.dart
```

---

## Phase 1: Foundation & Data Structures (Tasks 1-8)

### Task 1: Create Directory Structure and Base Types

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Support/VectorMath.swift`
- Create: `ios/Runner/Tracking/UltraQuality/Models/UltraQualityConfig.swift`

**Step 1: Create directory structure**

```bash
mkdir -p ios/Runner/Tracking/UltraQuality/{Core,Tracklet,Optimization,Refinement,Advanced,Models,Support}
```

**Step 2: Create VectorMath.swift**

```swift
// ios/Runner/Tracking/UltraQuality/Support/VectorMath.swift

import Foundation
import Accelerate

// MARK: - Vector Operations

/// Element-wise mean of multiple vectors
func elementWiseMean(_ vectors: [[Float]]) -> [Float] {
    guard let first = vectors.first, !first.isEmpty else { return [] }
    let n = Float(vectors.count)
    var result = [Float](repeating: 0, count: first.count)

    for vector in vectors {
        for i in 0..<min(vector.count, result.count) {
            result[i] += vector[i] / n
        }
    }
    return result
}

/// Cosine similarity between two vectors (0 to 1 for normalized vectors)
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0

    vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
    vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
    vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

    normA = sqrt(normA)
    normB = sqrt(normB)

    guard normA > 1e-6, normB > 1e-6 else { return 0 }
    return dot / (normA * normB)
}

/// Safe cosine similarity that handles zero vectors
func cosineSimilaritySafe(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))

    guard normA > 1e-6, normB > 1e-6 else { return 0 }

    let dot = zip(a, b).map(*).reduce(0, +)
    return dot / (normA * normB)
}

/// Average pairwise similarity among embeddings
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

/// Compute IoU between two bounding boxes
func computeIoU(_ a: CGRect, _ b: CGRect) -> Float {
    let intersection = a.intersection(b)
    guard !intersection.isNull else { return 0 }

    let intersectionArea = intersection.width * intersection.height
    let unionArea = a.width * a.height + b.width * b.height - intersectionArea

    guard unionArea > 0 else { return 0 }
    return Float(intersectionArea / unionArea)
}

/// Compute normalized center distance between two bounding boxes
func computeNormalizedDistance(_ a: CGRect, _ b: CGRect) -> Float {
    let dx = a.midX - b.midX
    let dy = a.midY - b.midY
    return Float(sqrt(dx * dx + dy * dy))
}

// MARK: - CGRect Extensions

extension CGRect {
    var area: CGFloat { width * height }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func scaled(to size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    func contains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

// MARK: - Signal Processing

/// Perform FFT on signal (placeholder - use Accelerate in production)
func performFFT(_ signal: [Float]) -> [Float] {
    guard signal.count > 1 else { return signal }

    // Use vDSP for real FFT
    let log2n = vDSP_Length(log2(Float(signal.count)).rounded(.up))
    let n = Int(1 << log2n)

    guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
        return signal
    }
    defer { vDSP_destroy_fftsetup(fftSetup) }

    var paddedSignal = signal + [Float](repeating: 0, count: n - signal.count)
    var realPart = [Float](repeating: 0, count: n/2)
    var imagPart = [Float](repeating: 0, count: n/2)

    realPart.withUnsafeMutableBufferPointer { realPtr in
        imagPart.withUnsafeMutableBufferPointer { imagPtr in
            var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
            paddedSignal.withUnsafeBufferPointer { signalPtr in
                signalPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n/2) { complexPtr in
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(n/2))
                }
            }
            vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        }
    }

    // Return magnitude spectrum
    var magnitudes = [Float](repeating: 0, count: n/2)
    for i in 0..<n/2 {
        magnitudes[i] = sqrt(realPart[i] * realPart[i] + imagPart[i] * imagPart[i])
    }

    return magnitudes
}

/// Find dominant frequency in FFT result
func findDominantFrequency(_ fft: [Float]) -> Float {
    guard let maxIdx = fft.indices.dropFirst().max(by: { fft[$0] < fft[$1] }) else { return 0 }
    return Float(maxIdx) / Float(fft.count)
}

// MARK: - Histogram Operations

/// Histogram intersection similarity (0.0 to 1.0)
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

**Step 3: Create UltraQualityConfig.swift**

```swift
// ios/Runner/Tracking/UltraQuality/Models/UltraQualityConfig.swift

import Foundation

/// Configuration for ultra-quality tracking pipeline
struct UltraQualityConfig {

    // MARK: - Feature Toggles

    /// Enable face detection and embedding
    let enableFaceDetection: Bool

    /// Enable color histogram features
    let enableColorHistogram: Bool

    /// Enable jersey number OCR (useful for sports videos)
    let enableJerseyOCR: Bool

    /// Enable gait analysis (requires longer sequences)
    let enableGaitAnalysis: Bool

    // MARK: - Phase 2: Tracklet Formation

    /// IoU threshold for linking detections (strict)
    let strictIoUThreshold: Float

    /// Max center distance for linking (strict)
    let strictDistanceThreshold: Float

    /// Appearance similarity threshold for linking
    let trackletAppearanceThreshold: Float

    /// Minimum tracklet duration (frames)
    let minTrackletDuration: Int

    // MARK: - Phase 3: Global Optimization

    /// Threshold for correlation clustering
    let clusteringThreshold: Float

    /// Use hierarchical clustering for large videos
    let enableHierarchicalClustering: Bool

    /// Window size for hierarchical clustering (frames)
    let hierarchicalWindowSize: Int

    /// Overlap between windows (frames)
    let hierarchicalOverlapSize: Int

    // MARK: - Phase 4: Refinement

    /// Enable swap detection and repair
    let enableSwapRepair: Bool

    /// Enable bidirectional tracking consensus
    let enableBidirectionalConsensus: Bool

    /// Margin for swap detection (higher = fewer false positives)
    let swapDetectionMargin: Float

    /// Threshold for People Library matching
    let peopleLibraryMatchThreshold: Float

    // MARK: - Performance

    /// Maximum tracklets before using hierarchical clustering
    let maxTrackletsForDirectClustering: Int

    /// Target memory usage (bytes)
    let targetMemoryUsage: Int

    /// Color histogram sample rate (every Nth frame)
    let colorHistogramSampleRate: Int

    // MARK: - Initializer

    init(
        enableFaceDetection: Bool = true,
        enableColorHistogram: Bool = true,
        enableJerseyOCR: Bool = true,
        enableGaitAnalysis: Bool = false,
        strictIoUThreshold: Float = 0.5,
        strictDistanceThreshold: Float = 0.2,
        trackletAppearanceThreshold: Float = 0.80,
        minTrackletDuration: Int = 3,
        clusteringThreshold: Float = 0.5,
        enableHierarchicalClustering: Bool = true,
        hierarchicalWindowSize: Int = 300,
        hierarchicalOverlapSize: Int = 50,
        enableSwapRepair: Bool = true,
        enableBidirectionalConsensus: Bool = true,
        swapDetectionMargin: Float = 0.1,
        peopleLibraryMatchThreshold: Float = 0.70,
        maxTrackletsForDirectClustering: Int = 500,
        targetMemoryUsage: Int = 500_000_000,
        colorHistogramSampleRate: Int = 5
    ) {
        self.enableFaceDetection = enableFaceDetection
        self.enableColorHistogram = enableColorHistogram
        self.enableJerseyOCR = enableJerseyOCR
        self.enableGaitAnalysis = enableGaitAnalysis
        self.strictIoUThreshold = strictIoUThreshold
        self.strictDistanceThreshold = strictDistanceThreshold
        self.trackletAppearanceThreshold = trackletAppearanceThreshold
        self.minTrackletDuration = minTrackletDuration
        self.clusteringThreshold = clusteringThreshold
        self.enableHierarchicalClustering = enableHierarchicalClustering
        self.hierarchicalWindowSize = hierarchicalWindowSize
        self.hierarchicalOverlapSize = hierarchicalOverlapSize
        self.enableSwapRepair = enableSwapRepair
        self.enableBidirectionalConsensus = enableBidirectionalConsensus
        self.swapDetectionMargin = swapDetectionMargin
        self.peopleLibraryMatchThreshold = peopleLibraryMatchThreshold
        self.maxTrackletsForDirectClustering = maxTrackletsForDirectClustering
        self.targetMemoryUsage = targetMemoryUsage
        self.colorHistogramSampleRate = colorHistogramSampleRate
    }

    // MARK: - Presets

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

    static let fast = UltraQualityConfig(
        enableFaceDetection: false,
        enableColorHistogram: true,
        enableJerseyOCR: false,
        enableGaitAnalysis: false,
        enableHierarchicalClustering: true,
        enableSwapRepair: false,
        enableBidirectionalConsensus: false,
        colorHistogramSampleRate: 10
    )
}
```

**Step 4: Commit**

```bash
git add ios/Runner/Tracking/UltraQuality/
git commit -m "feat(tracking): add ultra-quality foundation - VectorMath and Config"
```

---

### Task 2: Create Core Data Models

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Models/MultiModalDetection.swift`
- Create: `ios/Runner/Tracking/UltraQuality/Models/PersonTrack.swift`

**Step 1: Create MultiModalDetection.swift**

See implementation in next task file due to size.

**Step 2: Create PersonTrack.swift**

See implementation in next task file due to size.

**Step 3: Commit**

```bash
git add ios/Runner/Tracking/UltraQuality/Models/
git commit -m "feat(tracking): add MultiModalDetection and PersonTrack models"
```

---

### Task 3: Create Support Infrastructure

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Support/ProgressReporter.swift`
- Create: `ios/Runner/Tracking/UltraQuality/Support/ThermalMonitor.swift`
- Create: `ios/Runner/Tracking/UltraQuality/Support/MemoryManager.swift`
- Create: `ios/Runner/Tracking/UltraQuality/Support/BackgroundTaskManager.swift`

---

### Task 4: Create Color Histogram Extractor

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Core/ColorHistogram.swift`

---

### Task 5: Create Jersey Number Detector

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Core/JerseyNumberDetector.swift`

---

### Task 6: Create Height Estimator and Body Proportions

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Core/HeightEstimator.swift`
- Create: `ios/Runner/Tracking/UltraQuality/Core/BodyProportions.swift`

---

### Task 7: Create Multi-Modal Detector

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Core/MultiModalDetector.swift`

---

### Task 8: Create Tracklet Data Structure

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Tracklet/Tracklet.swift`

---

## Phase 2: Tracklet Formation (Tasks 9-11)

### Task 9: Create Tracklet Builder

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Tracklet/TrackletBuilder.swift`

---

### Task 10: Create Adaptive Threshold Calibrator

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Tracklet/AdaptiveThresholdCalibrator.swift`

---

### Task 11: Phase 2 Integration Test

---

## Phase 3: Global Optimization (Tasks 12-17)

### Task 12: Create Affinity Matrix Builder

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Optimization/AffinityMatrixBuilder.swift`

---

### Task 13: Create Co-occurrence Constraints

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Optimization/CooccurrenceConstraints.swift`

---

### Task 14: Create Correlation Clusterer

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Optimization/CorrelationClusterer.swift`

---

### Task 15: Create Hierarchical Clusterer

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Optimization/HierarchicalClusterer.swift`

---

### Task 16: Create Temporal Proximity Weighter

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Optimization/TemporalProximityWeighter.swift`

---

### Task 17: Phase 3 Integration Test

---

## Phase 4: Refinement (Tasks 18-23)

### Task 18: Create Track Merger

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Refinement/TrackMerger.swift`

---

### Task 19: Create Swap Detector

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Refinement/SwapDetector.swift`

---

### Task 20: Create Bidirectional Consensus

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Refinement/BidirectionalConsensus.swift`

---

### Task 21: Create People Library Matcher

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Refinement/PeopleLibraryMatcher.swift`

---

### Task 22: Create Oracle Keyframe Manager

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Refinement/OracleKeyframeManager.swift`

---

### Task 23: Phase 4 Integration Test

---

## Phase 5: Main Orchestrator & Flutter Integration (Tasks 24-28)

### Task 24: Create Ultra Quality Tracking Service

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/UltraQualityTrackingService.swift`

---

### Task 25: Create Tracking Service Router

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/TrackingServiceRouter.swift`

---

### Task 26: Create Flutter Service

**Files:**
- Create: `lib/services/tracking/ultra_quality_tracking_service.dart`
- Create: `lib/services/tracking/tracking_errors.dart`

---

### Task 27: Integrate with Existing TrackingService

**Files:**
- Modify: `ios/Runner/Tracking/TrackingService.swift`

---

### Task 28: Phase 5 Integration Test

---

## Phase 6: Advanced Features (Tasks 29-30)

### Task 29: Create Gait Analyzer

**Files:**
- Create: `ios/Runner/Tracking/UltraQuality/Advanced/GaitAnalyzer.swift`

---

### Task 30: Final Integration and Documentation

**Files:**
- Update: `docs/plans/2026-02-02-ultra-quality-tracking-design.md` (mark as implemented)

---

## Execution Summary

Total Tasks: 30
Estimated Time: 8-10 hours of implementation

**Execution Order:**
1. Tasks 1-8: Foundation (data structures, utilities)
2. Tasks 9-11: Tracklet system
3. Tasks 12-17: Global optimization
4. Tasks 18-23: Refinement pipeline
5. Tasks 24-28: Integration
6. Tasks 29-30: Advanced features

**Dependencies:**
- Task 7 depends on Tasks 4-6
- Tasks 9-11 depend on Tasks 1-8
- Tasks 12-17 depend on Tasks 9-11
- Tasks 18-23 depend on Tasks 12-17
- Tasks 24-28 depend on all previous

