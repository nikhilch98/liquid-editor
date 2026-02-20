//
//  TrackDebugInfo.swift
//  LiquidEditor
//
//  Debug information for tracked persons, including time ranges,
//  confidence statistics, gap analysis, and ReID events.
//
//

import CoreGraphics
import Foundation

// MARK: - Gap Reason

/// Reason why a track had a gap (was lost temporarily).
enum GapReason: String, Codable, Sendable {
    /// Person was occluded by another person or object.
    case occlusion
    /// Person moved out of frame.
    case outOfFrame
    /// Detection confidence dropped below threshold.
    case lowConfidence
    /// Unknown reason.
    case unknown
}

// MARK: - Motion Classification

/// Classification of track motion intensity.
enum MotionClass: String, Codable, Sendable {
    /// Low motion (< 5 px/frame avg velocity).
    case low
    /// Medium motion (5-20 px/frame avg velocity).
    case medium
    /// High motion (> 20 px/frame avg velocity).
    case high
}

// MARK: - Track Gap

/// Information about a gap in tracking.
struct TrackGap: Codable, Sendable {
    /// Frame number when gap started.
    let startFrame: Int
    /// Frame number when gap ended.
    let endFrame: Int
    /// Timestamp in milliseconds when gap started.
    let startMs: Int
    /// Timestamp in milliseconds when gap ended.
    let endMs: Int
    /// Likely reason for the gap.
    let likelyReason: GapReason

    /// Duration of the gap in milliseconds.
    var durationMs: Int {
        endMs - startMs
    }
}

// MARK: - ReID Event

/// Information about a ReID restoration event.
struct TrackReIDEvent: Codable, Sendable {
    /// Frame number when restoration occurred.
    let frameNumber: Int
    /// Timestamp in milliseconds.
    let timestampMs: Int
    /// Cosine similarity score.
    let similarity: Float
    /// Track ID that was restored (this track's ID).
    let restoredTrackId: Int
    /// Track ID that would have been created without ReID.
    let wouldHaveBeenTrackId: Int?
}

// MARK: - Track Debug Info

/// Comprehensive debug information for a tracked person.
struct TrackDebugInfo: Codable, Sendable {
    /// Track ID.
    let trackId: Int

    /// Frame number when track was first detected.
    let firstFrame: Int
    /// Frame number when track was last detected.
    let lastFrame: Int
    /// Timestamp in milliseconds when first detected.
    let firstFrameMs: Int
    /// Timestamp in milliseconds when last detected.
    let lastFrameMs: Int

    /// Total number of frames where this track was detected.
    let totalFrames: Int

    // MARK: Confidence Statistics

    /// Average detection confidence.
    let avgConfidence: Float
    /// Minimum detection confidence.
    let minConfidence: Float
    /// Maximum detection confidence.
    let maxConfidence: Float
    /// Confidence histogram (10 buckets: 0-0.1, 0.1-0.2, ..., 0.9-1.0).
    let confidenceHistogram: [Int]

    // MARK: Gap Analysis

    /// List of gaps in tracking.
    let gaps: [TrackGap]
    /// Total duration of all gaps in milliseconds.
    let totalGapDurationMs: Int
    /// Number of gaps.
    var gapCount: Int { gaps.count }
    /// Longest gap duration in milliseconds.
    var longestGapMs: Int {
        gaps.map { $0.durationMs }.max() ?? 0
    }

    // MARK: ReID Information

    /// ReID restoration events.
    let reidRestorations: [TrackReIDEvent]
    /// Number of times restored via ReID.
    var reidRestorationCount: Int { reidRestorations.count }
    /// Track IDs that were merged into this one.
    let mergedFromTrackIds: [Int]

    // MARK: People Library Identification

    /// Identified person ID from People Library (nil if not identified).
    let identifiedPersonId: String?
    /// Identified person name from People Library (nil if not identified).
    let identifiedPersonName: String?
    /// Confidence of identification match (nil if not identified).
    let identificationConfidence: Double?
    /// Whether this track has been identified against People Library.
    var isIdentified: Bool { identifiedPersonId != nil }

    // MARK: Bounding Box Statistics

    /// Average bounding box size (normalized).
    let avgBboxSize: CGSize
    /// Average bounding box center position (normalized).
    let avgBboxCenter: CGPoint
    /// Variance in bounding box size.
    let bboxSizeVariance: Float

    // MARK: Motion Statistics

    /// Average velocity in normalized units per frame.
    let avgVelocity: Float
    /// Maximum velocity observed.
    let maxVelocity: Float
    /// Motion classification.
    let motionClassification: MotionClass

    // MARK: Current State

    /// Current track state ("confirmed", "lost", "tentative", "archived").
    let state: String
}

// MARK: - Track Merge Detail

/// Details about a track merge operation.
struct TrackMergeDebugDetail: Codable, Sendable {
    /// Track ID that was merged (disappeared).
    let fromTrackId: Int
    /// Track ID that absorbed the merge (remained).
    let toTrackId: Int
    /// Similarity score that triggered the merge.
    let similarity: Float
    /// Gap duration between tracks in milliseconds.
    let gapMs: Int
}

// MARK: - Tracking Debug Summary

/// Summary of all tracking debug information.
struct TrackingDebugSummary: Codable, Sendable {
    /// Total unique persons detected (after ReID merging).
    let uniquePersonCount: Int
    /// Total raw track IDs created (before ReID).
    let rawTrackCount: Int
    /// Number of tracks merged by ReID.
    let reidMergeCount: Int
    /// Fragmentation reduction percentage.
    var fragmentationReduction: Float {
        guard rawTrackCount > 0 else { return 0 }
        return Float(rawTrackCount - uniquePersonCount) / Float(rawTrackCount) * 100
    }
    /// Whether ReID was enabled during tracking.
    let reidEnabled: Bool
    /// Per-track debug info.
    let tracks: [TrackDebugInfo]

    // MARK: - Post-Tracking Merge Statistics

    /// Number of tracks before post-tracking merge.
    let tracksBeforeMerge: Int
    /// Number of tracks after post-tracking merge.
    let tracksAfterMerge: Int
    /// Number of merge operations performed in post-tracking.
    let postTrackingMergeCount: Int
    /// Details of each post-tracking merge.
    let postTrackingMergeDetails: [TrackMergeDebugDetail]
    /// Whether post-tracking merge was enabled.
    let postTrackingMergeEnabled: Bool

    /// Post-tracking fragmentation reduction percentage.
    var postTrackingFragmentationReduction: Float {
        guard tracksBeforeMerge > 0 else { return 0 }
        return Float(tracksBeforeMerge - tracksAfterMerge) / Float(tracksBeforeMerge) * 100
    }

    /// Number of tracks identified against People Library.
    var identifiedTrackCount: Int {
        tracks.filter { $0.isIdentified }.count
    }

    /// Percentage of tracks that were identified.
    var identificationRate: Float {
        guard uniquePersonCount > 0 else { return 0 }
        return Float(identifiedTrackCount) / Float(uniquePersonCount) * 100
    }

    init(
        uniquePersonCount: Int,
        rawTrackCount: Int,
        reidMergeCount: Int,
        reidEnabled: Bool,
        tracks: [TrackDebugInfo],
        tracksBeforeMerge: Int = 0,
        tracksAfterMerge: Int = 0,
        postTrackingMergeCount: Int = 0,
        postTrackingMergeDetails: [TrackMergeDebugDetail] = [],
        postTrackingMergeEnabled: Bool = false
    ) {
        self.uniquePersonCount = uniquePersonCount
        self.rawTrackCount = rawTrackCount
        self.reidMergeCount = reidMergeCount
        self.reidEnabled = reidEnabled
        self.tracks = tracks
        self.tracksBeforeMerge = tracksBeforeMerge > 0 ? tracksBeforeMerge : rawTrackCount
        self.tracksAfterMerge = tracksAfterMerge > 0 ? tracksAfterMerge : uniquePersonCount
        self.postTrackingMergeCount = postTrackingMergeCount
        self.postTrackingMergeDetails = postTrackingMergeDetails
        self.postTrackingMergeEnabled = postTrackingMergeEnabled
    }
}
