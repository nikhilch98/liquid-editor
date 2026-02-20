//
//  TrackingDataStore.swift
//  LiquidEditor
//
//  Thread-safe storage for tracking results with time-keyed access.
//  Delegates smoothing, gap filling, noise filtering, bbox smoothing,
//  and spatial proximity merging to `TrackingAlgorithms`.
//
//  Uses `actor` isolation for thread safety.
//

import CoreGraphics
import CoreMedia
import Foundation

// MARK: - TrackingDataStore

/// Thread-safe store for tracking results with millisecond-keyed access.
///
/// Uses `actor` isolation for all mutable state, replacing the
/// `NSLock`-based approach from the Flutter-era implementation.
///
/// Pure computation (smoothing, merging, filtering) is delegated to
/// `TrackingAlgorithms` -- this actor handles only storage and coordination.
actor TrackingDataStore {

    // MARK: - Configuration Constants

    /// Maximum number of frames to store before cleanup (prevents unbounded memory growth).
    /// Default: 18000 frames = 10 minutes at 30fps.
    private let maxFrameCount: Int = 18000

    /// Cleanup threshold: when exceeding this ratio of maxFrameCount, trim oldest frames.
    private let cleanupThreshold: Double = 0.9

    // MARK: - Storage

    /// Results indexed by timestamp in milliseconds.
    private var frameResults: [Int: FrameTrackingResult] = [:]

    /// Sorted timestamps for efficient range queries.
    private var sortedTimestamps: [Int] = []

    /// Kalman filters per person for trajectory smoothing.
    private var kalmanFilters: [Int: KalmanFilter2D] = [:]

    /// Kalman filters per person per joint for pose smoothing.
    /// Key: personIndex -> jointName -> filter.
    private var jointKalmanFilters: [Int: [String: KalmanFilter2D]] = [:]

    /// Forward-pass Kalman snapshots per person for RTS backward smoothing.
    /// Key: personIndex -> array of (timestampMs, snapshot) pairs.
    private var bboxKalmanSnapshots: [Int: [(timestampMs: Int, snapshot: KalmanSnapshot)]] = [:]

    /// Forward-pass joint Kalman snapshots per person per joint for RTS backward smoothing.
    /// Key: personIndex -> jointName -> array of (timestampMs, snapshot) pairs.
    private var jointKalmanSnapshots: [Int: [String: [(timestampMs: Int, snapshot: KalmanSnapshot)]]] = [:]

    /// First detection timestamp for each person (personIndex -> timestampMs).
    private var firstDetectionTimestamps: [Int: Int] = [:]

    /// First detection bounding box for each person (for thumbnails).
    private var firstDetectionBoxes: [Int: NormalizedBoundingBox] = [:]

    /// Identification results for each person (personIndex -> identification info).
    private var personIdentifications: [Int: (personId: String?, personName: String?, confidence: Double?)] = [:]

    /// Video duration.
    private(set) var videoDuration: CMTime = .zero

    /// Tracking algorithm used.
    private(set) var algorithmType: String = ""

    // MARK: - Configuration

    func configure(algorithmType: String, videoDuration: CMTime) {
        self.algorithmType = algorithmType
        self.videoDuration = videoDuration
        clear()
    }

    // MARK: - Storage Operations

    /// Store tracking result for a frame.
    func store(_ result: FrameTrackingResult, smooth: Bool = true) {
        let timestampMs = result.timestampMs

        var processedResult = result

        if smooth {
            processedResult = TrackingAlgorithms.applySmoothing(
                to: result,
                kalmanFilters: &kalmanFilters,
                jointKalmanFilters: &jointKalmanFilters,
                bboxKalmanSnapshots: &bboxKalmanSnapshots,
                jointKalmanSnapshots: &jointKalmanSnapshots
            )
        }

        frameResults[timestampMs] = processedResult

        // Track first detection for each person (for person selection thumbnails)
        for person in processedResult.people {
            if firstDetectionTimestamps[person.personIndex] == nil {
                firstDetectionTimestamps[person.personIndex] = timestampMs
                if let bbox = person.boundingBox {
                    firstDetectionBoxes[person.personIndex] = bbox
                }
            }

            // Store identification info when first available
            if person.isIdentified && personIdentifications[person.personIndex] == nil {
                personIdentifications[person.personIndex] = (
                    person.identifiedPersonId,
                    person.identifiedPersonName,
                    person.identificationConfidence
                )
            }
        }

        // Maintain sorted order using binary search for O(log n) insertion point
        let insertIdx = binarySearchInsertionPoint(for: timestampMs)
        if insertIdx < sortedTimestamps.count && sortedTimestamps[insertIdx] == timestampMs {
            // Timestamp already exists, no need to insert
        } else {
            sortedTimestamps.insert(timestampMs, at: insertIdx)
        }

        // Memory management: cleanup old frames if exceeding threshold
        performMemoryCleanupIfNeeded()
    }

    // MARK: - Memory Management

    /// Perform memory cleanup if frame count exceeds threshold.
    private func performMemoryCleanupIfNeeded() {
        let threshold = Int(Double(maxFrameCount) * cleanupThreshold)
        guard frameResults.count > threshold else { return }

        let targetCount = Int(Double(maxFrameCount) * 0.8)
        let removeCount = frameResults.count - targetCount

        guard removeCount > 0 else { return }

        let timestampsToRemove = Array(sortedTimestamps.prefix(removeCount))
        for ts in timestampsToRemove {
            frameResults.removeValue(forKey: ts)
        }
        sortedTimestamps.removeFirst(removeCount)

        cleanupOrphanedKalmanFilters()
    }

    /// Remove Kalman filters for persons not seen in recent frames.
    private func cleanupOrphanedKalmanFilters() {
        var activePersonIndices = Set<Int>()
        for (_, result) in frameResults {
            for person in result.people {
                activePersonIndices.insert(person.personIndex)
            }
        }

        let filterKeys = Set(kalmanFilters.keys)
        for key in filterKeys {
            if !activePersonIndices.contains(key) {
                kalmanFilters.removeValue(forKey: key)
            }
        }
        let jointFilterKeys = Set(jointKalmanFilters.keys)
        for key in jointFilterKeys {
            if !activePersonIndices.contains(key) {
                jointKalmanFilters.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Binary Search Helpers

    /// Binary search to find insertion point for timestamp (O(log n)).
    private func binarySearchInsertionPoint(for timestampMs: Int) -> Int {
        var low = 0
        var high = sortedTimestamps.count

        while low < high {
            let mid = (low + high) / 2
            if sortedTimestamps[mid] < timestampMs {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// Binary search to find index of timestamp or closest lower bound (O(log n)).
    private func binarySearchLowerBound(for timestampMs: Int) -> Int? {
        guard !sortedTimestamps.isEmpty else { return nil }

        var low = 0
        var high = sortedTimestamps.count - 1
        var result: Int?

        while low <= high {
            let mid = (low + high) / 2
            if sortedTimestamps[mid] <= timestampMs {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// Binary search to find index of timestamp or closest upper bound (O(log n)).
    private func binarySearchUpperBound(for timestampMs: Int) -> Int? {
        guard !sortedTimestamps.isEmpty else { return nil }

        var low = 0
        var high = sortedTimestamps.count - 1
        var result: Int?

        while low <= high {
            let mid = (low + high) / 2
            if sortedTimestamps[mid] >= timestampMs {
                result = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return result
    }

    // MARK: - Query Operations

    /// Get result for exact timestamp.
    func getResult(at timestamp: CMTime) -> FrameTrackingResult? {
        let ms = Int(timestamp.seconds * 1000)
        return frameResults[ms]
    }

    /// Get results in time range.
    func getResults(from start: CMTime, to end: CMTime) -> [FrameTrackingResult] {
        let startMs = Int(start.seconds * 1000)
        let endMs = Int(end.seconds * 1000)

        return sortedTimestamps
            .filter { $0 >= startMs && $0 <= endMs }
            .compactMap { frameResults[$0] }
    }

    /// Get interpolated result for a timestamp between frames.
    /// Uses binary search for O(log n) performance.
    func getInterpolatedResult(at timestamp: CMTime) -> FrameTrackingResult? {
        let targetMs = Int(timestamp.seconds * 1000)

        guard !sortedTimestamps.isEmpty else { return nil }

        let beforeIdx = binarySearchLowerBound(for: targetMs)
        let afterIdx = binarySearchUpperBound(for: targetMs)

        var beforeMs: Int?
        var afterMs: Int?

        if let idx = beforeIdx {
            beforeMs = sortedTimestamps[idx]
        }

        if let idx = afterIdx, sortedTimestamps[idx] > targetMs {
            afterMs = sortedTimestamps[idx]
        } else if let idx = beforeIdx, idx + 1 < sortedTimestamps.count {
            if sortedTimestamps[idx] == targetMs {
                return frameResults[targetMs]
            }
            afterMs = sortedTimestamps[idx + 1]
        }

        // If exact match
        if let before = beforeMs, before == targetMs {
            return frameResults[before]
        }

        // Interpolate between frames
        guard let before = beforeMs, let after = afterMs,
              let beforeResult = frameResults[before],
              let afterResult = frameResults[after] else {
            return beforeMs.flatMap { frameResults[$0] } ?? afterMs.flatMap { frameResults[$0] }
        }

        let t = Double(targetMs - before) / Double(after - before)

        return TrackingAlgorithms.interpolateResults(from: beforeResult, to: afterResult, t: t, at: targetMs)
    }

    /// Get all results.
    func getAllResults() -> [FrameTrackingResult] {
        sortedTimestamps.compactMap { frameResults[$0] }
    }

    /// Clear all stored data.
    func clear() {
        frameResults.removeAll()
        sortedTimestamps.removeAll()
        kalmanFilters.removeAll()
        jointKalmanFilters.removeAll()
        bboxKalmanSnapshots.removeAll()
        jointKalmanSnapshots.removeAll()
        firstDetectionTimestamps.removeAll()
        firstDetectionBoxes.removeAll()
        personIdentifications.removeAll()
    }

    /// Replace all results with new merged results.
    /// Used after post-tracking merge to update the data store.
    func replaceAllResults(_ results: [FrameTrackingResult]) {
        clear()
        for result in results {
            store(result, smooth: false)
        }
    }

    /// Number of stored frames.
    var frameCount: Int {
        frameResults.count
    }

    // MARK: - Detected Persons

    /// Detected person info including identification.
    struct DetectedPersonInfo {
        let personIndex: Int
        let firstTimestampMs: Int
        let boundingBox: NormalizedBoundingBox?
        let identifiedPersonId: String?
        let identifiedPersonName: String?
        let identificationConfidence: Double?
    }

    /// Get all detected persons with their first detection info and identification.
    /// Returns array of DetectedPersonInfo sorted by personIndex.
    func getDetectedPersons() -> [DetectedPersonInfo] {
        firstDetectionTimestamps
            .sorted { $0.key < $1.key }
            .map { entry in
                let identification = personIdentifications[entry.key]
                return DetectedPersonInfo(
                    personIndex: entry.key,
                    firstTimestampMs: entry.value,
                    boundingBox: firstDetectionBoxes[entry.key],
                    identifiedPersonId: identification?.personId,
                    identifiedPersonName: identification?.personName,
                    identificationConfidence: identification?.confidence
                )
            }
    }

    // MARK: - RTS Backward Smoothing

    /// Apply Rauch-Tung-Striebel backward smoother to all stored tracking data.
    /// Delegates computation to `TrackingAlgorithms.applyRTSSmoothing`.
    func applyRTSSmoothing(fps: Double = 30.0) {
        TrackingAlgorithms.applyRTSSmoothing(
            frameResults: &frameResults,
            bboxKalmanSnapshots: &bboxKalmanSnapshots,
            jointKalmanSnapshots: &jointKalmanSnapshots,
            fps: fps
        )
    }

    // MARK: - Post-Processing

    /// Fill tracking gaps using autoregressive motion prediction.
    /// Delegates computation to `TrackingAlgorithms.fillTrackingGaps`.
    func fillTrackingGaps(maxGapFrames: Int = 5) -> Int {
        let allResults = getAllResults()
        let (updatedFrames, gapsFilled) = TrackingAlgorithms.fillTrackingGaps(
            allResults: allResults,
            maxGapFrames: maxGapFrames,
            personIdentifications: personIdentifications
        )

        // Apply updated frames
        for (timestampMs, frame) in updatedFrames {
            frameResults[timestampMs] = frame
        }

        return gapsFilled
    }

    // MARK: - Temporal Bounding Box Smoothing

    /// Smooth bounding box sizes to prevent sudden shrinkage during fast motion.
    /// Delegates computation to `TrackingAlgorithms.smoothBoundingBoxes`.
    func smoothBoundingBoxes() {
        let allResults = getAllResults()
        let smoothedResults = TrackingAlgorithms.smoothBoundingBoxes(allResults: allResults)

        // Replace stored results with smoothed versions
        frameResults.removeAll()
        for result in smoothedResults {
            frameResults[result.timestampMs] = result
        }
    }

    // MARK: - Noise Track Filtering

    /// Remove tracks that appear for too few frames (spurious detections).
    /// Delegates computation to `TrackingAlgorithms`.
    func filterNoiseTracks(minDurationSeconds: Double = 1.0, fps: Double = 30.0) {
        let allResults = getAllResults()

        guard let filterResult = TrackingAlgorithms.computeNoiseTrackFilter(
            allResults: allResults,
            minDurationSeconds: minDurationSeconds,
            fps: fps
        ) else { return }

        let filteredResults = TrackingAlgorithms.applyNoiseTrackFilter(
            allResults: allResults,
            tracksToRemove: filterResult.tracksToRemove,
            remapToContiguous: filterResult.remapToContiguous
        )

        // Replace stored results
        frameResults.removeAll()
        sortedTimestamps.removeAll()
        firstDetectionTimestamps.removeAll()
        firstDetectionBoxes.removeAll()
        personIdentifications.removeAll()
        for result in filteredResults {
            store(result, smooth: false)
        }
    }

    // MARK: - Spatial/Temporal Track Merging

    /// Merge fragmented tracks that are likely the same person.
    /// Delegates computation to `TrackingAlgorithms`.
    func mergeTracksBySpatialProximity() {
        let allResults = getAllResults()

        guard let mergeResult = TrackingAlgorithms.computeTrackMergeMapping(allResults: allResults) else {
            return
        }

        let mergedResults = TrackingAlgorithms.applyTrackMerge(
            allResults: allResults,
            mergeMap: mergeResult.mergeMap,
            remapToContiguous: mergeResult.remapToContiguous
        )

        // Replace stored results
        frameResults.removeAll()
        sortedTimestamps.removeAll()
        firstDetectionTimestamps.removeAll()
        firstDetectionBoxes.removeAll()
        personIdentifications.removeAll()
        for result in mergedResults {
            store(result, smooth: false)
        }
    }

    // MARK: - Post-Tracking Identification

    /// Update identification data for all frames of a given track.
    func updateIdentification(
        forTrack personIndex: Int,
        personId: String,
        personName: String,
        confidence: Double
    ) {
        personIdentifications[personIndex] = (personId, personName, confidence)

        for (timestampMs, frame) in frameResults {
            var updated = false
            let updatedPeople = frame.people.map { person -> PersonTrackingResult in
                guard person.personIndex == personIndex else { return person }
                updated = true
                return person.with(
                    identifiedPersonId: personId,
                    identifiedPersonName: personName,
                    identificationConfidence: confidence
                )
            }
            if updated {
                frameResults[timestampMs] = frame.with(people: updatedPeople)
            }
        }
    }

    /// Get all unique track IDs present in the data store.
    func getUniqueTrackIds() -> Set<Int> {
        var trackIds = Set<Int>()
        for (_, frame) in frameResults {
            for person in frame.people {
                trackIds.insert(person.personIndex)
            }
        }
        return trackIds
    }

    /// Get frames for a specific track, sorted by timestamp.
    func getFramesForTrack(_ personIndex: Int, limit: Int? = nil) -> [(timestampMs: Int, bbox: NormalizedBoundingBox, confidence: Double)] {
        var frames: [(timestampMs: Int, bbox: NormalizedBoundingBox, confidence: Double)] = []
        for ts in sortedTimestamps {
            guard let frame = frameResults[ts] else { continue }
            guard let person = frame.people.first(where: { $0.personIndex == personIndex }),
                  let bbox = person.boundingBox else { continue }
            frames.append((ts, bbox, person.confidence))
        }

        guard let limit = limit, frames.count > limit else { return frames }

        let sorted = frames.sorted { $0.confidence > $1.confidence }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Serialization

    /// Export all results as JSON data.
    func exportJSON() throws -> Data {
        let allResults = getAllResults()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(allResults)
    }

    /// Import results from JSON data.
    func importJSON(_ data: Data) throws {
        let decoder = JSONDecoder()
        let results = try decoder.decode([FrameTrackingResult].self, from: data)

        clear()
        for result in results {
            store(result, smooth: false)
        }
    }
}
