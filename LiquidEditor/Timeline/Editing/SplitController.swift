// SplitController.swift
// LiquidEditor
//
// Controller for splitting clips at specific times with validation.

import Foundation

// MARK: - ClipSplitPair

/// Result of a single clip split.
struct ClipSplitPair: Equatable, Sendable {
    /// The left clip (before split point).
    let leftClip: TimelineClip

    /// The right clip (after split point).
    let rightClip: TimelineClip
}

// MARK: - SplitValidationError

/// Validation error for split operations.
enum SplitValidationError: String, Sendable, CaseIterable {
    /// Split point is before clip start.
    case beforeClipStart
    /// Split point is after clip end.
    case afterClipEnd
    /// Split point is at clip boundary (no split needed).
    case atClipBoundary
    /// Resulting clips would be too short.
    case clipsTooShort
    /// No clips found at split point.
    case noClipsAtTime
}

// MARK: - SplitValidation

/// Result of split validation.
struct SplitValidation: Equatable, Sendable {
    /// Whether the split is valid.
    let isValid: Bool

    /// Error if invalid.
    let error: SplitValidationError?

    /// Clips that can be split.
    let validClips: [TimelineClip]

    init(isValid: Bool, error: SplitValidationError? = nil, validClips: [TimelineClip] = []) {
        self.isValid = isValid
        self.error = error
        self.validClips = validClips
    }

    /// Valid split with clips.
    static func valid(_ clips: [TimelineClip]) -> SplitValidation {
        SplitValidation(isValid: true, validClips: clips)
    }

    /// Invalid split with error.
    static func invalid(_ error: SplitValidationError) -> SplitValidation {
        SplitValidation(isValid: false, error: error)
    }
}

// MARK: - SplitController

/// Controller for clip split operations.
///
/// Provides validation and execution of split operations on timeline clips.
/// Split operations divide a single clip into two clips at a specified time.
enum SplitController {

    /// Standard frame rate used for minimum clip duration calculation (default: 30fps).
    /// Can be adjusted for projects with different frame rates (e.g., 24fps for film, 60fps for gaming).
    static let standardFrameRate: Double = 30.0

    /// Minimum duration for resulting clips after split (1 frame at standard frame rate).
    ///
    /// Threshold Derivation:
    /// - Calculated as 1/standardFrameRate seconds in microseconds.
    /// - At 30fps: 33,333 μs = 1 frame.
    /// - At 24fps: 41,667 μs = 1 frame.
    /// - At 60fps: 16,667 μs = 1 frame.
    /// - Prevents clips from becoming too short to display or play.
    /// - Matches TimelineClip.minDuration.
    static var minClipDuration: TimeMicros {
        TimeMicros((1_000_000.0 / standardFrameRate).rounded())
    }

    /// Tolerance for boundary detection in microseconds (1ms).
    /// Split points within this tolerance of clip boundaries are rejected to avoid edge cases.
    private static let boundaryTolerance: TimeMicros = 1_000

    // MARK: - Validation

    /// Validate if a split can be performed at the given time for a specific clip.
    static func validateSplit(_ clip: TimelineClip, at splitTime: TimeMicros) -> SplitValidation {
        // Check if split point is within clip bounds
        if splitTime <= clip.startTime {
            return .invalid(.beforeClipStart)
        }

        if splitTime >= clip.endTime {
            return .invalid(.afterClipEnd)
        }

        // Check if split point is at exact boundary (with small tolerance)
        if abs(splitTime - clip.startTime) < boundaryTolerance ||
           abs(splitTime - clip.endTime) < boundaryTolerance {
            return .invalid(.atClipBoundary)
        }

        // Check if resulting clips would be too short
        let leftDuration = splitTime - clip.startTime
        let rightDuration = clip.endTime - splitTime

        if leftDuration < minClipDuration || rightDuration < minClipDuration {
            return .invalid(.clipsTooShort)
        }

        return .valid([clip])
    }

    // MARK: - Single Clip Split

    /// Split a single clip at the specified time.
    ///
    /// Returns a `ClipSplitPair` with the left and right clips, or nil if invalid.
    static func splitClip(_ clip: TimelineClip, at splitTime: TimeMicros) -> ClipSplitPair? {
        let validation = validateSplit(clip, at: splitTime)
        guard validation.isValid else { return nil }

        // Generate new ID for the right clip
        let rightClipId = UUID().uuidString

        // Use the clip's built-in split method
        guard let result = clip.splitAt(splitTime, rightClipId: rightClipId) else {
            return nil
        }

        return ClipSplitPair(leftClip: result.left, rightClip: result.right)
    }

    // MARK: - Split at Playhead

    /// Split clips at playhead position.
    ///
    /// - Parameters:
    ///   - clips: All clips to consider for splitting.
    ///   - playheadTime: The time to split at.
    ///   - selectedClipIds: If provided, only split selected clips; otherwise split all clips at playhead.
    /// - Returns: A `SplitResult` with all split operations.
    static func splitAtPlayhead(
        clips: [TimelineClip],
        playheadTime: TimeMicros,
        selectedClipIds: Set<String>? = nil
    ) -> SplitResult {
        var results: [SplitClipResult] = []

        for clip in clips {
            // Skip if we have a selection and this clip isn't selected
            if let selectedIds = selectedClipIds, !selectedIds.contains(clip.id) {
                continue
            }

            // Check if playhead is within this clip
            guard clip.containsTime(playheadTime) else { continue }

            // Try to split
            if let splitPair = splitClip(clip, at: playheadTime) {
                results.append(SplitClipResult(
                    originalClipId: clip.id,
                    leftClip: splitPair.leftClip,
                    rightClip: splitPair.rightClip
                ))
            }
        }

        return SplitResult(clips: results)
    }

    // MARK: - Split All Tracks

    /// Split all clips across all tracks at a specific time.
    ///
    /// - Parameters:
    ///   - trackClips: Map of track ID to clips on that track.
    ///   - splitTime: The time to split at.
    /// - Returns: A `SplitResult` with all split operations.
    static func splitAllTracks(
        trackClips: [String: [TimelineClip]],
        splitTime: TimeMicros
    ) -> SplitResult {
        var results: [SplitClipResult] = []

        for (_, clips) in trackClips {
            for clip in clips {
                guard clip.containsTime(splitTime) else { continue }

                if let splitPair = splitClip(clip, at: splitTime) {
                    results.append(SplitClipResult(
                        originalClipId: clip.id,
                        leftClip: splitPair.leftClip,
                        rightClip: splitPair.rightClip
                    ))
                }
            }
        }

        return SplitResult(clips: results)
    }

    // MARK: - Split Single Track

    /// Split clips on a specific track at a time.
    ///
    /// - Parameters:
    ///   - clips: Clips on the target track.
    ///   - splitTime: The time to split at.
    /// - Returns: A `SplitResult` with split operations for the track.
    static func splitTrack(
        clips: [TimelineClip],
        splitTime: TimeMicros
    ) -> SplitResult {
        var results: [SplitClipResult] = []

        for clip in clips {
            guard clip.containsTime(splitTime) else { continue }

            if let splitPair = splitClip(clip, at: splitTime) {
                results.append(SplitClipResult(
                    originalClipId: clip.id,
                    leftClip: splitPair.leftClip,
                    rightClip: splitPair.rightClip
                ))
            }
        }

        return SplitResult(clips: results)
    }

    // MARK: - Find Splittable Clips

    /// Find clips at a specific time that can be split.
    static func findClipsAtTime(_ clips: [TimelineClip], time: TimeMicros) -> [TimelineClip] {
        clips.filter { clip in
            guard clip.containsTime(time) else { return false }
            let validation = validateSplit(clip, at: time)
            return validation.isValid
        }
    }
}
