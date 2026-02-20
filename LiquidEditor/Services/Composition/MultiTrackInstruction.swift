// MultiTrackInstruction.swift
// LiquidEditor
//
// Custom AVVideoCompositionInstruction for multi-track compositing.
//
// Carries per-track compositing configuration (layout, blend mode, opacity,
// chroma key, PiP region) to the MultiTrackCompositor for rendering.

import AVFoundation
import CoreMedia
import Foundation

// MARK: - MultiTrackInstruction

/// Custom instruction carrying per-track compositing configuration.
///
/// Conforms to `AVVideoCompositionInstructionProtocol` so the
/// ``MultiTrackCompositor`` can access track configs during rendering.
///
/// Each instruction covers a time range and contains:
/// - Per-track ``TrackCompositeConfig`` (layout, blend mode, opacity, chroma key)
/// - Mapping from logical track IDs to AVComposition track IDs
/// - Track rendering order (bottom-to-top)
///
/// Thread Safety:
/// - All properties are immutable after initialization.
/// - NSValue/NSNumber bridging for `requiredSourceTrackIDs` uses value semantics.
final class MultiTrackInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {

    // MARK: - AVVideoCompositionInstructionProtocol

    /// Time range this instruction covers.
    let timeRange: CMTimeRange

    /// Whether post-processing is needed (always false for our compositor).
    let enablePostProcessing: Bool = false

    /// Whether the instruction contains tweening (always true for multi-track).
    let containsTweening: Bool = true

    /// Source track IDs required for this instruction.
    let requiredSourceTrackIDs: [NSValue]?

    /// Passthrough track ID (invalid = no passthrough, always composites).
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    // MARK: - Compositing Configuration

    /// Per-track composite configurations keyed by logical track ID.
    let trackConfigs: [String: TrackCompositeConfig]

    /// Mapping from logical track ID to AVComposition track ID.
    ///
    /// These are the `CMPersistentTrackID` values assigned when tracks
    /// are added to the `AVMutableComposition`.
    let compositionTrackIDs: [String: CMPersistentTrackID]

    /// Track rendering order (bottom-to-top).
    ///
    /// Index 0 is the bottom-most layer (typically the main video).
    /// Higher indices are rendered on top.
    let trackOrder: [String]

    // MARK: - Initialization

    /// Create a multi-track instruction.
    ///
    /// - Parameters:
    ///   - timeRange: Time range this instruction covers.
    ///   - trackConfigs: Per-track composite configurations.
    ///   - compositionTrackIDs: Mapping from track IDs to composition track IDs.
    ///   - trackOrder: Track rendering order (bottom-to-top).
    init(
        timeRange: CMTimeRange,
        trackConfigs: [String: TrackCompositeConfig],
        compositionTrackIDs: [String: CMPersistentTrackID],
        trackOrder: [String]
    ) {
        self.timeRange = timeRange
        self.trackConfigs = trackConfigs
        self.compositionTrackIDs = compositionTrackIDs
        self.trackOrder = trackOrder

        // Build required source track IDs from all composition tracks.
        // CMPersistentTrackID is Int32; NSNumber(value:) correctly encodes it
        // as an NSValue with the proper objCType for AVFoundation consumption.
        self.requiredSourceTrackIDs = compositionTrackIDs.values.map { trackID in
            NSNumber(value: trackID)
        }

        super.init()
    }

    /// Convenience initializer from a ``MultiTrackState``.
    ///
    /// Extracts track configs and ordering from the multi-track state.
    ///
    /// - Parameters:
    ///   - timeRange: Time range this instruction covers.
    ///   - multiTrackState: The current multi-track state.
    ///   - compositionTrackIDs: Mapping from track IDs to composition track IDs.
    convenience init(
        timeRange: CMTimeRange,
        multiTrackState: MultiTrackState,
        compositionTrackIDs: [String: CMPersistentTrackID]
    ) {
        self.init(
            timeRange: timeRange,
            trackConfigs: multiTrackState.compositeConfigs,
            compositionTrackIDs: compositionTrackIDs,
            trackOrder: multiTrackState.trackOrder
        )
    }
}

// MARK: - CustomStringConvertible

extension MultiTrackInstruction {
    override var description: String {
        let startSec = CMTimeGetSeconds(timeRange.start)
        let durSec = CMTimeGetSeconds(timeRange.duration)
        return "MultiTrackInstruction(start: \(startSec)s, dur: \(durSec)s, tracks: \(trackOrder.count))"
    }
}
