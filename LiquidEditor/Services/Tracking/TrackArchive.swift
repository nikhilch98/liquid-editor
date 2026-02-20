//
//  TrackArchive.swift
//  LiquidEditor
//
//  Archive system for lost tracks, enabling re-identification when people reappear.
//  Tracks are archived instead of deleted, and matched against new detections.
//
//  Enhanced for dance videos with:
//  - Appearance-first matching (bypasses spatial checks for high similarity)
//  - Adaptive archive thresholds for edge/partial detections
//  - Tiered archive lifetime based on track quality
//  - Geometry similarity for disambiguation
//
//

import CoreGraphics
import Foundation

// MARK: - Archive Configuration

/// Configuration for archive thresholds and matching behavior.
struct ArchiveConfig {

    // MARK: - Archive Thresholds

    /// Minimum detections for standard (center-frame) tracks.
    static let minDetectionsStandard: Int = 3

    /// Minimum detections for edge/partial body tracks.
    static let minDetectionsEdge: Int = 1

    /// Minimum quality score for single-frame archives.
    static let minQualityForSingleFrame: Float = 0.6

    /// Edge detection zone (normalized coordinates from frame edge).
    static let edgeThreshold: Float = 0.08

    // MARK: - Archive Lifetime (in frames, assuming 30fps)

    /// Premium lifetime: high-quality tracks (>30 frames, >0.75 confidence).
    static let premiumLifetimeFrames: Int = 300  // 10 seconds

    /// Standard lifetime: normal tracks (3+ frames, decent confidence).
    static let standardLifetimeFrames: Int = 120  // 4 seconds

    /// Minimum lifetime: edge/partial detections.
    static let minimumLifetimeFrames: Int = 60   // 2 seconds

    // MARK: - Matching Thresholds

    /// Long gap threshold (frames) -- disable spatial check beyond this.
    static let longGapThreshold: Int = 45  // 1.5 seconds

    /// Base spatial distance threshold.
    static let baseSpatialThreshold: CGFloat = 0.4

    /// Spatial threshold growth per frame.
    static let spatialThresholdGrowth: CGFloat = 0.015

    /// Maximum spatial threshold.
    static let maxSpatialThreshold: CGFloat = 1.2
}

// MARK: - ArchivedTrack

/// An archived track waiting to be re-identified.
struct ArchivedTrack: Sendable {
    /// Original track ID to restore if matched.
    let trackId: Int

    /// Appearance embedding for matching.
    let appearance: AppearanceFeature

    /// Last known bounding box (normalized coordinates).
    let lastBoundingBox: CGRect

    /// Last known center position.
    let lastCenter: CGPoint

    /// Last known velocity (pixels per frame, normalized).
    let lastVelocity: CGPoint

    /// Frame number when this track was archived.
    let archivedAtFrame: Int

    /// Frame number when this track was first seen.
    let firstSeenFrame: Int

    /// Total frames this track was active.
    let totalActiveFrames: Int

    /// Average confidence during tracking.
    let avgConfidence: Float

    /// Number of times this track was previously restored via ReID.
    let previousRestorations: Int

    /// Whether this was an edge/partial detection.
    let wasEdgeDetection: Bool

    // MARK: - People Library Identification (persisted through archive)

    /// Identified person's ID from People library (nil if not identified).
    let identifiedPersonId: String?

    /// Identified person's name from People library (nil if not identified).
    let identifiedPersonName: String?

    /// Confidence of identification (best similarity score).
    let identificationConfidence: Double?

    /// Computed archive lifetime based on track quality.
    var lifetime: Int {
        if totalActiveFrames > 30 &&
           avgConfidence > 0.75 &&
           appearance.qualityScore > 0.7 {
            return ArchiveConfig.premiumLifetimeFrames
        }

        if totalActiveFrames >= 3 && avgConfidence > 0.5 {
            return ArchiveConfig.standardLifetimeFrames
        }

        return ArchiveConfig.minimumLifetimeFrames
    }

    /// Check if this archived track has expired.
    func isExpired(currentFrame: Int) -> Bool {
        (currentFrame - archivedAtFrame) > lifetime
    }
}

// MARK: - ReID Restoration Event

/// ReID event recorded when a track is restored from archive.
struct ReIDRestorationEvent: Sendable, Codable {
    /// Frame number when restoration occurred.
    let frameNumber: Int

    /// Timestamp in milliseconds.
    let timestampMs: Int

    /// Cosine similarity score that triggered the match.
    let similarity: Float

    /// Original track ID that was restored.
    let restoredTrackId: Int

    /// Track ID that would have been created without ReID (for debugging).
    let wouldHaveBeenTrackId: Int?
}

// MARK: - TrackArchive

/// Manages archived tracks for re-identification.
///
/// Thread Safety: `@unchecked Sendable` because mutable state
/// is protected by `NSLock` for thread-safe access.
final class TrackArchive: @unchecked Sendable {

    // MARK: - Configuration

    /// Minimum similarity score to consider a ReID match.
    private let reidThreshold: Float

    // MARK: - State

    /// Archived tracks waiting for re-identification.
    private var archivedTracks: [ArchivedTrack] = []

    /// Record of all ReID restoration events (for debug info).
    private(set) var restorationEvents: [ReIDRestorationEvent] = []

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Initialization

    init(reidThreshold: Float = AppearanceFeature.reidThreshold) {
        self.reidThreshold = reidThreshold
    }

    // MARK: - Edge Detection Helper

    /// Check if a bounding box is near the frame edge (partial body likely).
    static func isNearFrameEdge(_ bbox: CGRect) -> Bool {
        let t = CGFloat(ArchiveConfig.edgeThreshold)
        return bbox.minX < t ||
               bbox.maxX > (1.0 - t) ||
               bbox.minY < t ||
               bbox.maxY > (1.0 - t)
    }

    // MARK: - Archive Operations

    /// Determine if a track should be archived based on adaptive thresholds.
    func shouldArchive(
        totalActiveFrames: Int,
        wasEdgeDetection: Bool,
        appearanceQuality: Float
    ) -> Bool {
        let requiredFrames = wasEdgeDetection ?
            ArchiveConfig.minDetectionsEdge :
            ArchiveConfig.minDetectionsStandard

        guard totalActiveFrames >= requiredFrames else { return false }

        if totalActiveFrames == 1 {
            return appearanceQuality >= ArchiveConfig.minQualityForSingleFrame
        }

        return true
    }

    /// Archive a lost track for potential future re-identification.
    func archive(
        trackId: Int,
        appearance: AppearanceFeature,
        lastBbox: CGRect,
        lastVelocity: CGPoint,
        currentFrame: Int,
        firstSeenFrame: Int,
        totalActiveFrames: Int,
        avgConfidence: Float,
        previousRestorations: Int,
        wasEdgeDetection: Bool = false,
        identifiedPersonId: String? = nil,
        identifiedPersonName: String? = nil,
        identificationConfidence: Double? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        let wasEdge = wasEdgeDetection || Self.isNearFrameEdge(lastBbox)

        guard shouldArchive(
            totalActiveFrames: totalActiveFrames,
            wasEdgeDetection: wasEdge,
            appearanceQuality: appearance.qualityScore
        ) else {
            return
        }

        if archivedTracks.contains(where: { $0.trackId == trackId }) {
            return
        }

        let archived = ArchivedTrack(
            trackId: trackId,
            appearance: appearance,
            lastBoundingBox: lastBbox,
            lastCenter: CGPoint(x: lastBbox.midX, y: lastBbox.midY),
            lastVelocity: lastVelocity,
            archivedAtFrame: currentFrame,
            firstSeenFrame: firstSeenFrame,
            totalActiveFrames: totalActiveFrames,
            avgConfidence: avgConfidence,
            previousRestorations: previousRestorations,
            wasEdgeDetection: wasEdge,
            identifiedPersonId: identifiedPersonId,
            identifiedPersonName: identifiedPersonName,
            identificationConfidence: identificationConfidence
        )

        archivedTracks.append(archived)
    }

    /// Clean up expired archived tracks.
    func cleanupExpired(currentFrame: Int) {
        lock.lock()
        defer { lock.unlock() }
        archivedTracks.removeAll { $0.isExpired(currentFrame: currentFrame) }
    }

    /// Compute geometry similarity between two bounding boxes.
    private func computeGeometrySimilarity(_ bbox1: CGRect, _ bbox2: CGRect) -> Float {
        let aspect1 = bbox1.width / bbox1.height
        let aspect2 = bbox2.width / bbox2.height
        let aspectSim = Float(1.0 - abs(aspect1 - aspect2) / max(aspect1, aspect2))

        let area1 = bbox1.width * bbox1.height
        let area2 = bbox2.width * bbox2.height
        let sizeSim = Float(min(area1, area2) / max(area1, area2))

        return aspectSim * 0.6 + sizeSim * 0.4
    }

    /// Find a matching archived track using appearance-first matching.
    ///
    /// Matching tiers:
    /// - TIER 1 (>=0.78 similarity): Skip all spatial checks.
    /// - TIER 2 (>=0.68 + long gap): Trust appearance for extended absences.
    /// - TIER 3 (>=0.65): Apply spatial + geometry checks.
    func findMatch(
        appearance: AppearanceFeature,
        bbox: CGRect,
        currentFrame: Int,
        wouldBeTrackId: Int? = nil
    ) -> ArchivedTrack? {
        lock.lock()
        defer { lock.unlock() }

        archivedTracks.removeAll { $0.isExpired(currentFrame: currentFrame) }

        var bestMatch: ArchivedTrack?
        var bestScore: Float = 0

        for archived in archivedTracks {
            let similarity = appearance.cosineSimilarity(with: archived.appearance)
            let framesSinceArchived = currentFrame - archived.archivedAtFrame

            // TIER 1: Very high appearance similarity
            if similarity >= AppearanceFeature.highConfidenceThreshold {
                if similarity > bestScore {
                    bestMatch = archived
                    bestScore = similarity
                }
                continue
            }

            // TIER 2: Good appearance + long gap
            if similarity >= AppearanceFeature.mediumConfidenceThreshold &&
               framesSinceArchived > ArchiveConfig.longGapThreshold {
                if similarity > bestScore {
                    bestMatch = archived
                    bestScore = similarity
                }
                continue
            }

            // TIER 3: Moderate appearance + geometry/spatial matching
            if similarity >= reidThreshold {
                var geometryBonus: Float = 0

                let geometrySim = computeGeometrySimilarity(bbox, archived.lastBoundingBox)
                geometryBonus += geometrySim * 0.1

                if framesSinceArchived <= ArchiveConfig.longGapThreshold {
                    let predictedCenter = CGPoint(
                        x: archived.lastCenter.x + archived.lastVelocity.x * CGFloat(framesSinceArchived),
                        y: archived.lastCenter.y + archived.lastVelocity.y * CGFloat(framesSinceArchived)
                    )

                    let detectionCenter = CGPoint(x: bbox.midX, y: bbox.midY)
                    let distance = hypot(
                        predictedCenter.x - detectionCenter.x,
                        predictedCenter.y - detectionCenter.y
                    )

                    let maxDistance = min(
                        ArchiveConfig.baseSpatialThreshold + ArchiveConfig.spatialThresholdGrowth * CGFloat(framesSinceArchived),
                        ArchiveConfig.maxSpatialThreshold
                    )

                    if distance <= maxDistance {
                        let proxBonus = Float(1.0 - distance / maxDistance) * 0.15
                        geometryBonus += proxBonus
                    } else {
                        continue
                    }
                }

                let totalScore = similarity + geometryBonus
                if totalScore > bestScore {
                    bestMatch = archived
                    bestScore = totalScore
                }
            }
        }

        if let match = bestMatch {
            let event = ReIDRestorationEvent(
                frameNumber: currentFrame,
                timestampMs: currentFrame * 33,
                similarity: bestScore,
                restoredTrackId: match.trackId,
                wouldHaveBeenTrackId: wouldBeTrackId
            )
            restorationEvents.append(event)

            archivedTracks.removeAll { $0.trackId == match.trackId }
        }

        return bestMatch
    }

    /// Remove an archived track.
    func remove(trackId: Int) {
        lock.lock()
        defer { lock.unlock() }
        archivedTracks.removeAll { $0.trackId == trackId }
    }

    /// Clear all archived tracks.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        archivedTracks.removeAll()
        restorationEvents.removeAll()
    }

    /// Get number of currently archived tracks.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return archivedTracks.count
    }

    /// Get all archived track IDs (for debugging).
    var archivedTrackIds: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return archivedTracks.map { $0.trackId }
    }

    /// Get restoration events for a specific track.
    func restorations(for trackId: Int) -> [ReIDRestorationEvent] {
        lock.lock()
        defer { lock.unlock() }
        return restorationEvents.filter { $0.restoredTrackId == trackId }
    }
}
