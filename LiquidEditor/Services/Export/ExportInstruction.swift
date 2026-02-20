// ExportInstruction.swift
// LiquidEditor
//
// Re-exports ExportCompositionInstruction from ExportCompositor.swift
// for backward compatibility and naming clarity.
//
// The main ExportCompositionInstruction class is defined in ExportCompositor.swift
// as it is tightly coupled with the compositor's rendering pipeline.
//
// This file provides a convenient type alias and factory methods for creating
// export instructions from model types.

import AVFoundation
import Foundation

// MARK: - ExportInstructionFactory

/// Factory for creating ExportCompositionInstruction objects from model types.
enum ExportInstructionFactory {

    /// Create an export instruction from export config and clip parameters.
    ///
    /// - Parameters:
    ///   - timeRange: Time range in the composition timeline.
    ///   - sourceTrackID: Track ID of the source video.
    ///   - config: Export configuration.
    ///   - colorGradeParams: Color grading parameters dictionary.
    ///   - effectChain: Array of effect parameter dictionaries.
    ///   - cropParams: Crop/rotation/flip parameters.
    ///   - speedConfig: Speed configuration for the clip.
    ///   - transitionData: Transition parameters (nil if no transition).
    ///   - previousTrackID: Track ID of the previous clip for transitions.
    /// - Returns: A configured ExportCompositionInstruction.
    static func makeInstruction(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        config: ExportConfig,
        colorGradeParams: [String: Any]? = nil,
        effectChain: [[String: Any]]? = nil,
        cropParams: CropParameters? = nil,
        speedConfig: SpeedConfig = .normal,
        transitionData: TransitionParameters? = nil,
        previousTrackID: CMPersistentTrackID? = nil
    ) -> ExportCompositionInstruction {
        // Validate parameters
        precondition(CMTIME_IS_VALID(timeRange.start), "Invalid timeRange.start")
        precondition(CMTIME_IS_VALID(timeRange.duration), "Invalid timeRange.duration")
        precondition(timeRange.duration.value > 0, "timeRange.duration must be positive")
        precondition(sourceTrackID != kCMPersistentTrackID_Invalid, "sourceTrackID must be valid")
        precondition(speedConfig.speedMultiplier > 0, "speedMultiplier must be positive")

        if let previousID = previousTrackID {
            precondition(previousID != kCMPersistentTrackID_Invalid, "previousTrackID must be valid if provided")
        }

        return ExportCompositionInstruction(
            timeRange: timeRange,
            sourceTrackID: sourceTrackID,
            colorGradeParams: colorGradeParams,
            effectChain: effectChain,
            cropParams: cropParams,
            playbackSpeed: speedConfig.speedMultiplier,
            transitionData: transitionData,
            previousTrackID: previousTrackID
        )
    }

    /// Create a passthrough instruction (no effects, just source frame).
    ///
    /// - Parameters:
    ///   - timeRange: Time range in the composition timeline.
    ///   - sourceTrackID: Track ID of the source video.
    /// - Returns: A minimal ExportCompositionInstruction.
    static func makePassthrough(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID
    ) -> ExportCompositionInstruction {
        // Validate parameters
        precondition(CMTIME_IS_VALID(timeRange.start), "Invalid timeRange.start")
        precondition(CMTIME_IS_VALID(timeRange.duration), "Invalid timeRange.duration")
        precondition(timeRange.duration.value > 0, "timeRange.duration must be positive")
        precondition(sourceTrackID != kCMPersistentTrackID_Invalid, "sourceTrackID must be valid")

        return ExportCompositionInstruction(
            timeRange: timeRange,
            sourceTrackID: sourceTrackID
        )
    }
}
