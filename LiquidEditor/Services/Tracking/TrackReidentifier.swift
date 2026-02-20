//
//  TrackReidentifier.swift
//  LiquidEditor
//
//  Post-processes tracking results to merge fragmented tracks using
//  color histogram and spatial cues.
//
//

import AVFoundation
import CoreImage
import Foundation
import os.log

// MARK: - Track Features

/// Features extracted from a track for re-identification.
struct TrackFeatures: Sendable {
    let trackId: Int
    let colorHistogram: ColorHistogram
    let averageSize: CGSize
    let averageAspectRatio: Float
    let entryPosition: CGPoint
    let exitPosition: CGPoint
    let startFrame: Int
    let endFrame: Int
    let startMs: Int
    let endMs: Int
    let frameCount: Int
}

// MARK: - Merge Result

/// Result of track merging.
struct TrackMergeResult: Sendable {
    let originalTrackId: Int
    let mergedTrackId: Int
    let similarity: Float?
    var wasMerged: Bool { originalTrackId != mergedTrackId }
}

// MARK: - Merge Statistics

/// Statistics about the merging process.
struct TrackMergeStatistics: Sendable {
    let tracksBeforeMerge: Int
    let tracksAfterMerge: Int
    let mergeCount: Int
    let mergeDetails: [MergeDetail]
    /// Per-track ReID restoration events captured during merging.
    let reidEvents: [TrackReIDEvent]

    var fragmentationReduction: Float {
        guard tracksBeforeMerge > 0 else { return 0 }
        return Float(tracksBeforeMerge - tracksAfterMerge) / Float(tracksBeforeMerge) * 100
    }

    struct MergeDetail: Sendable {
        let fromTrackId: Int
        let toTrackId: Int
        let similarity: Float
        let gapMs: Int
    }
}

// MARK: - Configuration

/// Configuration for track re-identification.
struct TrackReidentifierConfig: Sendable {
    var maxGapMs: Int = 10000
    var colorSimilarityThreshold: Float = 0.55
    var maxSpatialDistance: Float = 0.4
    var minSizeConsistency: Float = 0.6
    var framesToSample: Int = 5
    var minTrackFrames: Int = 3

    static let `default` = TrackReidentifierConfig()

    static let strict = TrackReidentifierConfig(
        maxGapMs: 5000,
        colorSimilarityThreshold: 0.65,
        maxSpatialDistance: 0.3,
        minSizeConsistency: 0.7
    )

    static let lenient = TrackReidentifierConfig(
        maxGapMs: 15000,
        colorSimilarityThreshold: 0.45,
        maxSpatialDistance: 0.5,
        minSizeConsistency: 0.5
    )
}

// MARK: - Track Reidentifier

/// Post-processes tracking results to merge fragmented tracks.
///
/// Thread Safety: `@unchecked Sendable` because `config` is an immutable
/// `let` value type, `logger` is thread-safe, and all methods operate
/// on local variables only.
final class TrackReidentifier: @unchecked Sendable {

    private let config: TrackReidentifierConfig
    private let logger = Logger(subsystem: "com.liquideditor.tracking", category: "TrackReidentifier")

    init(config: TrackReidentifierConfig = .default) {
        self.config = config
    }

    // MARK: - Main API

    /// Merge fragmented tracks in the results.
    func mergeFragmentedTracks(
        results: [FrameTrackingResult],
        videoURL: URL
    ) async -> (results: [FrameTrackingResult], statistics: TrackMergeStatistics) {
        guard !results.isEmpty else {
            return (results, TrackMergeStatistics(tracksBeforeMerge: 0, tracksAfterMerge: 0, mergeCount: 0, mergeDetails: [], reidEvents: []))
        }

        let trackInfos = buildTrackInfos(from: results)
        let originalTrackCount = trackInfos.count

        guard originalTrackCount > 1 else {
            return (results, TrackMergeStatistics(tracksBeforeMerge: originalTrackCount, tracksAfterMerge: originalTrackCount, mergeCount: 0, mergeDetails: [], reidEvents: []))
        }

        let features = await extractFeatures(trackInfos: trackInfos, videoURL: videoURL)

        guard features.count > 1 else {
            return (results, TrackMergeStatistics(tracksBeforeMerge: originalTrackCount, tracksAfterMerge: originalTrackCount, mergeCount: 0, mergeDetails: [], reidEvents: []))
        }

        let mergeCandidates = findMergeCandidates(features: features)
        let (mergeMap, mergeDetails, reidEvents) = performGreedyMerge(candidates: mergeCandidates, features: features)
        let mergedResults = applyMergeMap(results: results, mergeMap: mergeMap)

        let finalTrackIds = Set(mergedResults.flatMap { $0.people.map(\.personIndex) })

        return (mergedResults, TrackMergeStatistics(
            tracksBeforeMerge: originalTrackCount,
            tracksAfterMerge: finalTrackIds.count,
            mergeCount: mergeDetails.count,
            mergeDetails: mergeDetails,
            reidEvents: reidEvents
        ))
    }

    // MARK: - Track Info

    private struct TrackInfo {
        let trackId: Int
        var frames: [(timestampMs: Int, bbox: NormalizedBoundingBox, confidence: Double)]
        var firstMs: Int { frames.first?.timestampMs ?? 0 }
        var lastMs: Int { frames.last?.timestampMs ?? 0 }
    }

    private func buildTrackInfos(from results: [FrameTrackingResult]) -> [Int: TrackInfo] {
        var trackInfos: [Int: TrackInfo] = [:]

        for frame in results {
            for person in frame.people {
                guard let bbox = person.boundingBox else { continue }

                if trackInfos[person.personIndex] == nil {
                    trackInfos[person.personIndex] = TrackInfo(trackId: person.personIndex, frames: [])
                }
                trackInfos[person.personIndex]?.frames.append((
                    timestampMs: frame.timestampMs,
                    bbox: bbox,
                    confidence: person.confidence
                ))
            }
        }

        for trackId in trackInfos.keys {
            trackInfos[trackId]?.frames.sort { $0.timestampMs < $1.timestampMs }
        }

        return trackInfos
    }

    // MARK: - Feature Extraction

    private func extractFeatures(
        trackInfos: [Int: TrackInfo],
        videoURL: URL
    ) async -> [TrackFeatures] {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var features: [TrackFeatures] = []

        for (trackId, trackInfo) in trackInfos {
            guard trackInfo.frames.count >= config.minTrackFrames else { continue }

            let sampleIndices = selectSampleFrameIndices(trackInfo: trackInfo)
            var histograms: [ColorHistogram] = []

            for idx in sampleIndices {
                let frame = trackInfo.frames[idx]
                let time = CMTime(value: CMTimeValue(frame.timestampMs), timescale: 1000)

                do {
                    let (cgImage, _) = try await imageGenerator.image(at: time)
                    let histogram = ColorHistogram.extract(from: cgImage, boundingBox: frame.bbox)
                    histograms.append(histogram)
                } catch {
                    continue
                }
            }

            guard !histograms.isEmpty else { continue }

            let aggregatedHistogram = ColorHistogram.aggregate(histograms)
            let avgWidth = trackInfo.frames.map { $0.bbox.width }.reduce(0, +) / Double(trackInfo.frames.count)
            let avgHeight = trackInfo.frames.map { $0.bbox.height }.reduce(0, +) / Double(trackInfo.frames.count)
            let avgAspectRatio = avgHeight > 0 ? Float(avgWidth / avgHeight) : 1.0

            let firstBbox = trackInfo.frames.first!.bbox
            let lastBbox = trackInfo.frames.last!.bbox

            let entryPosition = CGPoint(x: firstBbox.x, y: firstBbox.y)
            let exitPosition = CGPoint(x: lastBbox.x, y: lastBbox.y)

            let startFrame = Int(Double(trackInfo.firstMs) / 1000.0 * 30.0)
            let endFrame = Int(Double(trackInfo.lastMs) / 1000.0 * 30.0)

            features.append(TrackFeatures(
                trackId: trackId,
                colorHistogram: aggregatedHistogram,
                averageSize: CGSize(width: avgWidth, height: avgHeight),
                averageAspectRatio: avgAspectRatio,
                entryPosition: entryPosition,
                exitPosition: exitPosition,
                startFrame: startFrame,
                endFrame: endFrame,
                startMs: trackInfo.firstMs,
                endMs: trackInfo.lastMs,
                frameCount: trackInfo.frames.count
            ))
        }

        return features
    }

    private func selectSampleFrameIndices(trackInfo: TrackInfo) -> [Int] {
        let count = trackInfo.frames.count
        guard count > 0 else { return [] }

        let marginFrames = max(1, count / 10)
        let validStart = marginFrames
        let validEnd = max(marginFrames, count - marginFrames - 1)

        if validStart >= validEnd {
            return [count / 2]
        }

        let validFrames = (validStart...validEnd).map { idx in
            (idx: idx, confidence: trackInfo.frames[idx].confidence)
        }.sorted { $0.confidence > $1.confidence }

        let samplesToTake = min(config.framesToSample, validFrames.count)
        return validFrames.prefix(samplesToTake).map(\.idx)
    }

    // MARK: - Merge Candidate Finding

    private struct MergeCandidate: Comparable {
        let earlierTrackId: Int
        let laterTrackId: Int
        let similarity: Float
        let gapMs: Int

        static func < (lhs: MergeCandidate, rhs: MergeCandidate) -> Bool {
            lhs.similarity > rhs.similarity
        }
    }

    private func findMergeCandidates(features: [TrackFeatures]) -> [MergeCandidate] {
        var candidates: [MergeCandidate] = []

        for i in 0..<features.count {
            for j in 0..<features.count where i != j {
                let earlier = features[i]
                let later = features[j]
                guard earlier.endMs < later.startMs else { continue }

                let gapMs = later.startMs - earlier.endMs
                guard gapMs <= config.maxGapMs else { continue }

                let similarity = computeMergeSimilarity(earlier: earlier, later: later, gapMs: gapMs)
                guard similarity >= config.colorSimilarityThreshold else { continue }

                candidates.append(MergeCandidate(
                    earlierTrackId: earlier.trackId,
                    laterTrackId: later.trackId,
                    similarity: similarity,
                    gapMs: gapMs
                ))
            }
        }

        return candidates.sorted()
    }

    private func computeMergeSimilarity(earlier: TrackFeatures, later: TrackFeatures, gapMs: Int) -> Float {
        let colorSim = earlier.colorHistogram.similarity(to: later.colorHistogram)

        let exitToEntryDistance = hypot(
            earlier.exitPosition.x - later.entryPosition.x,
            earlier.exitPosition.y - later.entryPosition.y
        )
        let spatialSim = max(0, 1.0 - Float(exitToEntryDistance) / config.maxSpatialDistance)

        let sizeRatio = min(
            Float(earlier.averageSize.width * earlier.averageSize.height),
            Float(later.averageSize.width * later.averageSize.height)
        ) / max(
            Float(earlier.averageSize.width * earlier.averageSize.height),
            Float(later.averageSize.width * later.averageSize.height)
        )
        let sizeSim = sizeRatio >= config.minSizeConsistency ? sizeRatio : 0

        let aspectRatio = min(earlier.averageAspectRatio, later.averageAspectRatio) /
            max(earlier.averageAspectRatio, later.averageAspectRatio)

        let gapPenalty = 1.0 - Float(gapMs) / Float(config.maxGapMs)

        return colorSim * 0.45 + spatialSim * 0.25 + sizeSim * 0.15 + aspectRatio * 0.05 + gapPenalty * 0.10
    }

    // MARK: - Greedy Merging

    private func performGreedyMerge(
        candidates: [MergeCandidate],
        features: [TrackFeatures]
    ) -> (mergeMap: [Int: Int], details: [TrackMergeStatistics.MergeDetail], reidEvents: [TrackReIDEvent]) {
        // Build lookup for feature data by track ID.
        let featuresByTrackId = Dictionary(uniqueKeysWithValues: features.map { ($0.trackId, $0) })

        var mergeMap: [Int: Int] = [:]
        var mergedTracks = Set<Int>()
        var mergeDetails: [TrackMergeStatistics.MergeDetail] = []
        var reidEvents: [TrackReIDEvent] = []

        for candidate in candidates {
            if mergedTracks.contains(candidate.laterTrackId) { continue }

            var rootId = candidate.earlierTrackId
            var visited: Set<Int> = []
            while let mappedId = mergeMap[rootId], !visited.contains(mappedId) {
                visited.insert(rootId)
                rootId = mappedId
            }

            if mergedTracks.contains(rootId) { continue }

            mergeMap[candidate.laterTrackId] = rootId
            mergedTracks.insert(candidate.laterTrackId)

            mergeDetails.append(TrackMergeStatistics.MergeDetail(
                fromTrackId: candidate.laterTrackId,
                toTrackId: rootId,
                similarity: candidate.similarity,
                gapMs: candidate.gapMs
            ))

            // Capture ReID event at the start of the later track (the restoration point).
            let laterFeature = featuresByTrackId[candidate.laterTrackId]
            reidEvents.append(TrackReIDEvent(
                frameNumber: laterFeature?.startFrame ?? 0,
                timestampMs: laterFeature?.startMs ?? 0,
                similarity: candidate.similarity,
                restoredTrackId: rootId,
                wouldHaveBeenTrackId: candidate.laterTrackId
            ))
        }

        return (mergeMap, mergeDetails, reidEvents)
    }

    // MARK: - Apply Merge Map

    private func applyMergeMap(
        results: [FrameTrackingResult],
        mergeMap: [Int: Int]
    ) -> [FrameTrackingResult] {
        results.map { frame in
            let updatedPeople = frame.people.map { person -> PersonTrackingResult in
                var finalId = person.personIndex
                var visited: Set<Int> = []
                while let mappedId = mergeMap[finalId], !visited.contains(mappedId) {
                    visited.insert(finalId)
                    finalId = mappedId
                }

                if finalId != person.personIndex {
                    return person.with(personIndex: finalId)
                }
                return person
            }
            return frame.with(people: updatedPeople)
        }
    }
}
