// JLCutService.swift
// LiquidEditor
//
// J/L cut service for audio/video split editing.
// Manages J-cuts (audio leads video) and L-cuts (audio trails video)
// by adjusting audio and video linked clip boundaries independently.
//

import Foundation
import UIKit

// MARK: - JLCutType

/// Type of J/L cut.
enum JLCutType: String, Sendable, CaseIterable {
    /// J-cut: Audio from next clip starts before its video.
    /// Audio leads, video follows.
    case jCut

    /// L-cut: Audio from current clip continues after its video ends.
    /// Video cuts, audio trails.
    case lCut
}

// MARK: - JLCutValidation

/// Result of a J/L cut validation.
struct JLCutValidation: Equatable, Sendable {
    /// Whether the J/L cut is valid.
    let isValid: Bool

    /// Error message if invalid.
    let error: String?

    /// The video clip involved.
    let videoClip: TimelineClip?

    /// The audio clip involved.
    let audioClip: TimelineClip?

    /// Maximum allowed overlap in microseconds.
    let maxOverlap: TimeMicros

    init(
        isValid: Bool,
        error: String? = nil,
        videoClip: TimelineClip? = nil,
        audioClip: TimelineClip? = nil,
        maxOverlap: TimeMicros = 0
    ) {
        self.isValid = isValid
        self.error = error
        self.videoClip = videoClip
        self.audioClip = audioClip
        self.maxOverlap = maxOverlap
    }

    static func valid(
        videoClip: TimelineClip,
        audioClip: TimelineClip,
        maxOverlap: TimeMicros
    ) -> JLCutValidation {
        JLCutValidation(
            isValid: true,
            videoClip: videoClip,
            audioClip: audioClip,
            maxOverlap: maxOverlap
        )
    }

    static func invalid(_ error: String) -> JLCutValidation {
        JLCutValidation(isValid: false, error: error)
    }
}

// MARK: - JLCutPreview

/// Preview of a J/L cut operation showing the resulting clip states.
struct JLCutPreview: Equatable, Sendable {
    /// Type of cut.
    let cutType: JLCutType

    /// Updated video clip after the cut.
    let updatedVideoClip: TimelineClip

    /// Updated audio clip after the cut.
    let updatedAudioClip: TimelineClip

    /// Overlap duration in microseconds.
    let overlapDuration: TimeMicros

    /// Description for display.
    let description: String
}

// MARK: - JLCutResult

/// Result of applying a J/L cut.
struct JLCutResult: Equatable, Sendable {
    /// Whether the operation succeeded.
    let success: Bool

    /// Updated video clip.
    let updatedVideoClip: TimelineClip?

    /// Updated audio clip.
    let updatedAudioClip: TimelineClip?

    /// Error message if failed.
    let error: String?

    /// Description for undo display.
    let operationName: String

    init(
        success: Bool,
        updatedVideoClip: TimelineClip? = nil,
        updatedAudioClip: TimelineClip? = nil,
        error: String? = nil,
        operationName: String
    ) {
        self.success = success
        self.updatedVideoClip = updatedVideoClip
        self.updatedAudioClip = updatedAudioClip
        self.error = error
        self.operationName = operationName
    }

    static func success(
        updatedVideoClip: TimelineClip,
        updatedAudioClip: TimelineClip,
        operationName: String
    ) -> JLCutResult {
        JLCutResult(
            success: true,
            updatedVideoClip: updatedVideoClip,
            updatedAudioClip: updatedAudioClip,
            operationName: operationName
        )
    }

    static func failure(_ error: String) -> JLCutResult {
        JLCutResult(success: false, error: error, operationName: "J/L Cut")
    }
}

// MARK: - JLCutDragHandleOffsets

/// Drag handle offset information for J/L cut visualization.
struct JLCutDragHandleOffsets: Equatable, Sendable {
    let audioLeadPixels: Double
    let audioTrailPixels: Double
}

// MARK: - JLCutService

/// Service for managing J-cut and L-cut audio/video split edits.
///
/// J-cuts and L-cuts are achieved by offsetting the audio and video
/// portions of linked clips so that audio from the incoming clip
/// starts before its video (J-cut) or audio from the outgoing clip
/// continues after its video ends (L-cut).
///
/// This service operates on linked clip pairs (video + audio) identified
/// by `TimelineClip.linkedClipId`.
@MainActor
final class JLCutService: Sendable {

    /// Minimum overlap duration for a J/L cut in microseconds (100ms ≈ 3 frames at 30fps).
    /// Prevents imperceptibly short J/L cuts that confuse users.
    static let minOverlap: TimeMicros = 100_000 // 100,000 μs = 100 ms

    /// Maximum overlap as a fraction of the shorter clip's duration (0.5 = 50%).
    /// Prevents J/L cuts from extending beyond half the shorter clip's length,
    /// which would make the split boundary unclear.
    static let maxOverlapFraction: Double = 0.5

    // MARK: - Find Linked Clips

    /// Find the linked audio clip for a video clip.
    func findLinkedAudioClip(
        _ videoClip: TimelineClip,
        allClips: [TimelineClip]
    ) -> TimelineClip? {
        guard let linkedId = videoClip.linkedClipId else { return nil }
        return allClips.first { $0.id == linkedId }
    }

    /// Find the linked video clip for an audio clip.
    func findLinkedVideoClip(
        _ audioClip: TimelineClip,
        allClips: [TimelineClip]
    ) -> TimelineClip? {
        guard let linkedId = audioClip.linkedClipId else { return nil }
        return allClips.first { $0.id == linkedId }
    }

    // MARK: - Validation

    /// Validate whether a J/L cut can be performed on a clip pair.
    ///
    /// - Parameters:
    ///   - clipId: The clip to perform the cut on.
    ///   - allClips: All clips on the timeline.
    func validateJLCut(
        _ clipId: String,
        allClips: [TimelineClip]
    ) -> JLCutValidation {
        guard let clip = allClips.first(where: { $0.id == clipId }) else {
            return .invalid("Clip not found")
        }

        guard let linkedClipId = clip.linkedClipId else {
            return .invalid(
                "Clip has no linked audio/video partner. " +
                "J/L cuts require a linked A/V clip pair."
            )
        }

        guard let linkedClip = allClips.first(where: { $0.id == linkedClipId }) else {
            return .invalid("Linked clip not found")
        }

        // Determine which is video and which is audio.
        let videoClip: TimelineClip
        let audioClip: TimelineClip

        if clip.type == .video {
            videoClip = clip
            audioClip = linkedClip
        } else if clip.type == .audio {
            audioClip = clip
            videoClip = linkedClip
        } else {
            return .invalid("J/L cuts require video+audio clip pairs")
        }

        if audioClip.type != .audio || videoClip.type != .video {
            return .invalid("Linked clips must be a video+audio pair")
        }

        // Calculate maximum allowed overlap.
        let shorterDuration = min(videoClip.duration, audioClip.duration)
        let maxOverlap = TimeMicros((Double(shorterDuration) * Self.maxOverlapFraction).rounded())

        if maxOverlap < Self.minOverlap {
            return .invalid("Clips are too short for J/L cut")
        }

        return .valid(
            videoClip: videoClip,
            audioClip: audioClip,
            maxOverlap: maxOverlap
        )
    }

    // MARK: - J-Cut Preview

    /// Create a J-cut preview.
    ///
    /// J-cut: Audio from the next clip starts before its video.
    /// The audio clip extends earlier (or video clip is trimmed later).
    ///
    /// - Parameters:
    ///   - videoClip: The video clip.
    ///   - audioClip: The linked audio clip.
    ///   - overlapDuration: How much the audio should lead the video (microseconds).
    func createJCutPreview(
        videoClip: TimelineClip,
        audioClip: TimelineClip,
        overlapDuration: TimeMicros
    ) -> JLCutPreview? {
        guard overlapDuration >= Self.minOverlap else { return nil }

        // For a J-cut, audio starts earlier than video.
        let newAudioStartTime = audioClip.startTime - overlapDuration
        guard newAudioStartTime >= 0 else { return nil }

        // Check if audio has enough source material to extend.
        let newAudioSourceIn = audioClip.sourceIn - TimeMicros((Double(overlapDuration) * audioClip.speed).rounded())
        guard newAudioSourceIn >= 0 else { return nil }

        let updatedAudioClip = audioClip.with(
            startTime: newAudioStartTime,
            duration: audioClip.duration + overlapDuration,
            sourceIn: newAudioSourceIn
        )

        let seconds = String(format: "%.1f", Double(overlapDuration) / 1_000_000.0)
        return JLCutPreview(
            cutType: .jCut,
            updatedVideoClip: videoClip,
            updatedAudioClip: updatedAudioClip,
            overlapDuration: overlapDuration,
            description: "J-Cut: Audio leads by \(seconds)s"
        )
    }

    // MARK: - L-Cut Preview

    /// Create an L-cut preview.
    ///
    /// L-cut: Audio from the current clip continues after its video ends.
    /// The audio clip extends beyond the video clip's end.
    ///
    /// - Parameters:
    ///   - videoClip: The video clip.
    ///   - audioClip: The linked audio clip.
    ///   - overlapDuration: How much the audio should trail the video (microseconds).
    func createLCutPreview(
        videoClip: TimelineClip,
        audioClip: TimelineClip,
        overlapDuration: TimeMicros
    ) -> JLCutPreview? {
        guard overlapDuration >= Self.minOverlap else { return nil }

        // For an L-cut, audio extends beyond the video end.
        let newAudioDuration = audioClip.duration + overlapDuration
        let newAudioSourceOut = audioClip.sourceIn + TimeMicros((Double(newAudioDuration) * audioClip.speed).rounded())

        let updatedAudioClip = audioClip.with(
            duration: newAudioDuration,
            sourceOut: newAudioSourceOut
        )

        let seconds = String(format: "%.1f", Double(overlapDuration) / 1_000_000.0)
        return JLCutPreview(
            cutType: .lCut,
            updatedVideoClip: videoClip,
            updatedAudioClip: updatedAudioClip,
            overlapDuration: overlapDuration,
            description: "L-Cut: Audio trails by \(seconds)s"
        )
    }

    // MARK: - Apply

    /// Apply a J/L cut from a preview.
    ///
    /// Returns the updated clips to be committed to the timeline.
    func applyJLCut(_ preview: JLCutPreview) -> JLCutResult {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        return .success(
            updatedVideoClip: preview.updatedVideoClip,
            updatedAudioClip: preview.updatedAudioClip,
            operationName: preview.cutType == .jCut ? "Apply J-Cut" : "Apply L-Cut"
        )
    }

    // MARK: - Reset

    /// Reset a J/L cut by re-synchronizing audio and video clip boundaries.
    ///
    /// - Parameters:
    ///   - videoClip: The video clip to sync to.
    ///   - audioClip: The audio clip to reset.
    func resetJLCut(
        videoClip: TimelineClip,
        audioClip: TimelineClip
    ) -> JLCutResult {
        // Reset audio to match video boundaries.
        let resetAudioClip = audioClip.with(
            startTime: videoClip.startTime,
            duration: videoClip.duration,
            sourceIn: videoClip.sourceIn,
            sourceOut: videoClip.sourceOut
        )

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        return .success(
            updatedVideoClip: videoClip,
            updatedAudioClip: resetAudioClip,
            operationName: "Reset J/L Cut"
        )
    }

    // MARK: - Detection

    /// Detect if a clip pair currently has a J or L cut applied.
    ///
    /// Returns the cut type and overlap, or nil if clips are in sync.
    func detectExistingCut(
        videoClip: TimelineClip,
        audioClip: TimelineClip
    ) -> (type: JLCutType, overlap: TimeMicros)? {
        if videoClip.startTime == audioClip.startTime &&
           videoClip.endTime == audioClip.endTime {
            return nil // Clips are in sync, no J/L cut.
        }

        if audioClip.startTime < videoClip.startTime {
            // Audio starts before video: J-cut.
            let overlap = videoClip.startTime - audioClip.startTime
            return (.jCut, overlap)
        }

        if audioClip.endTime > videoClip.endTime {
            // Audio ends after video: L-cut.
            let overlap = audioClip.endTime - videoClip.endTime
            return (.lCut, overlap)
        }

        return nil
    }

    // MARK: - Drag Handle Positions

    /// Calculate the drag handle positions for J/L cut adjustment.
    ///
    /// Returns the audio split offset relative to the video boundary
    /// for use in rendering drag handles.
    func getDragHandleOffsets(
        videoClip: TimelineClip,
        audioClip: TimelineClip,
        microsPerPixel: Double
    ) -> JLCutDragHandleOffsets {
        let audioLeadMicros = videoClip.startTime - audioClip.startTime
        let audioTrailMicros = audioClip.endTime - videoClip.endTime

        return JLCutDragHandleOffsets(
            audioLeadPixels: audioLeadMicros > 0 ? Double(audioLeadMicros) / microsPerPixel : 0.0,
            audioTrailPixels: audioTrailMicros > 0 ? Double(audioTrailMicros) / microsPerPixel : 0.0
        )
    }
}
