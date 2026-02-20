// SlipSlideController.swift
// LiquidEditor
//
// Controllers for slip (content within clip) and slide (clip position) operations.

import Foundation

// ============================================================================
// MARK: - SlipController
// ============================================================================

/// Controller for slip editing operations.
///
/// Slip editing moves the source content within a clip's bounds without
/// changing the clip's position or duration on the timeline.
enum SlipController {

    /// Start a slip operation.
    ///
    /// - Parameter clip: The clip to slip.
    /// - Returns: The initial slip state.
    static func startSlip(_ clip: TimelineClip) -> SlipState {
        SlipState(
            clip: clip,
            originalSourceIn: clip.sourceIn,
            originalSourceOut: clip.sourceOut
        )
    }

    /// Calculate slip preview.
    ///
    /// - Parameters:
    ///   - state: The current slip state.
    ///   - sourceDelta: The source offset in microseconds.
    ///   - maxSourceDuration: The total source duration (optional limit).
    /// - Returns: The slip preview.
    static func calculateSlipPreview(
        state: SlipState,
        sourceDelta: TimeMicros,
        maxSourceDuration: TimeMicros? = nil
    ) -> SlipPreview {
        let clip = state.clip

        // Calculate new source range
        var newSourceIn = state.originalSourceIn + sourceDelta
        var newSourceOut = state.originalSourceOut + sourceDelta

        // Clamp to source bounds
        if newSourceIn < 0 {
            // Shift both back to make in point 0
            newSourceIn = 0
            newSourceOut = state.originalSourceOut - state.originalSourceIn
        }

        if let maxDuration = maxSourceDuration, newSourceOut > maxDuration {
            // Shift both back to keep within source duration
            let overshoot = newSourceOut - maxDuration
            newSourceOut = maxDuration
            newSourceIn = newSourceIn - overshoot
            if newSourceIn < 0 { newSourceIn = 0 }
        }

        return SlipPreview(
            clipId: clip.id,
            newSourceIn: newSourceIn,
            newSourceOut: newSourceOut,
            startTime: clip.startTime,
            duration: clip.duration
        )
    }

    /// Apply slip to clip.
    ///
    /// - Parameters:
    ///   - clip: The clip to modify.
    ///   - preview: The calculated slip preview.
    /// - Returns: The modified clip.
    static func applySlip(_ clip: TimelineClip, preview: SlipPreview) -> TimelineClip {
        clip.with(
            sourceIn: preview.newSourceIn,
            sourceOut: preview.newSourceOut
        )
    }

    /// Cancel slip and restore original state.
    ///
    /// - Parameters:
    ///   - clip: The current clip.
    ///   - state: The original slip state.
    /// - Returns: The restored clip.
    static func cancelSlip(_ clip: TimelineClip, state: SlipState) -> TimelineClip {
        clip.with(
            sourceIn: state.originalSourceIn,
            sourceOut: state.originalSourceOut
        )
    }
}

// ============================================================================
// MARK: - SlideMode
// ============================================================================

/// Slide mode for adjusting adjacent clips.
enum SlideMode: String, Sendable, CaseIterable {
    /// Standard slide -- adjacent clips are trimmed to accommodate.
    case standard
    /// Overwrite slide -- no adjustment to adjacent clips, may cause overlap.
    case overwrite
    /// Ripple slide -- adjacent clips move, no trimming.
    case ripple
}

// ============================================================================
// MARK: - SlideValidation
// ============================================================================

/// Result of slide validation.
struct SlideValidation: Equatable, Sendable {
    /// Whether the slide is valid.
    let isValid: Bool

    /// Minimum allowed position (limited by left clip).
    let minPosition: TimeMicros

    /// Maximum allowed position (limited by right clip).
    let maxPosition: TimeMicros

    /// Error message if invalid.
    let error: String?

    init(isValid: Bool, minPosition: TimeMicros, maxPosition: TimeMicros, error: String? = nil) {
        self.isValid = isValid
        self.minPosition = minPosition
        self.maxPosition = maxPosition
        self.error = error
    }

    /// Valid slide.
    static func valid(minPosition: TimeMicros, maxPosition: TimeMicros) -> SlideValidation {
        SlideValidation(isValid: true, minPosition: minPosition, maxPosition: maxPosition)
    }

    /// Invalid slide.
    static func invalid(_ error: String) -> SlideValidation {
        SlideValidation(isValid: false, minPosition: 0, maxPosition: 0, error: error)
    }
}

// ============================================================================
// MARK: - SlideController
// ============================================================================

/// Controller for slide editing operations.
///
/// Slide editing moves a clip's position on the timeline, with adjacent
/// clips adjusting to fill the gaps or accommodate the new position.
@Observable @MainActor
final class SlideController {

    /// Current slide mode.
    var mode: SlideMode = .standard

    // MARK: - Start Slide

    /// Start a slide operation.
    ///
    /// - Parameters:
    ///   - clip: The clip to slide.
    ///   - trackClips: All clips on the same track.
    /// - Returns: The initial slide state.
    func startSlide(_ clip: TimelineClip, trackClips: [TimelineClip]) -> SlideState {
        // Find adjacent clips
        var leftClip: TimelineClip?
        var rightClip: TimelineClip?

        for c in trackClips {
            if c.id == clip.id { continue }

            // Check for left adjacent (ends at or before clip start)
            if c.endTime <= clip.startTime {
                if leftClip == nil || c.endTime > leftClip!.endTime {
                    leftClip = c
                }
            }

            // Check for right adjacent (starts at or after clip end)
            if c.startTime >= clip.endTime {
                if rightClip == nil || c.startTime < rightClip!.startTime {
                    rightClip = c
                }
            }
        }

        return SlideState(
            clip: clip,
            leftClip: leftClip,
            rightClip: rightClip,
            originalStartTime: clip.startTime
        )
    }

    // MARK: - Validate Slide

    /// Validate slide operation.
    ///
    /// - Parameters:
    ///   - state: The current slide state.
    ///   - newStartTime: The proposed new start time.
    /// - Returns: Validation result.
    func validateSlide(_ state: SlideState, newStartTime: TimeMicros) -> SlideValidation {
        let clip = state.clip

        // Calculate limits based on adjacent clips
        var minPosition: TimeMicros = 0
        // Use Int64.max/2 as sentinel value instead of Int64.max to prevent overflow during
        // arithmetic operations (additions/subtractions). Int64.max/2 ≈ 4.6e18 microseconds
        // ≈ 146,000 years, which is effectively unlimited for video editing while maintaining
        // safe arithmetic margins. This prevents overflow when adding clip durations or deltas.
        var maxPosition: TimeMicros = Int64.max / 2

        if let leftClip = state.leftClip, mode == .standard {
            // Can't slide past the left clip's start (would need to trim it to 0)
            minPosition = leftClip.startTime + TimelineClip.minDuration
        }

        if let rightClip = state.rightClip, mode == .standard {
            // Can't slide past the right clip's end (would need to trim it to 0)
            let maxEndTime = rightClip.endTime - TimelineClip.minDuration
            maxPosition = maxEndTime - clip.duration
        }

        if newStartTime < minPosition {
            return .invalid("Cannot slide past adjacent clip minimum position")
        }

        if newStartTime > maxPosition {
            return .invalid("Cannot slide past adjacent clip maximum position")
        }

        return .valid(minPosition: minPosition, maxPosition: maxPosition)
    }

    // MARK: - Calculate Slide Preview

    /// Calculate slide preview.
    ///
    /// - Parameters:
    ///   - state: The current slide state.
    ///   - newStartTime: The proposed new start time.
    /// - Returns: The slide preview.
    func calculateSlidePreview(
        state: SlideState,
        newStartTime: TimeMicros
    ) -> SlidePreview {
        let clip = state.clip
        let delta = newStartTime - state.originalStartTime

        if delta == 0 {
            return SlidePreview(
                clipId: clip.id,
                newStartTime: clip.startTime,
                leftClipNewDuration: nil,
                rightClipNewStartTime: nil
            )
        }

        var leftClipNewDuration: TimeMicros?
        var rightClipNewStartTime: TimeMicros?

        if mode == .standard {
            if delta < 0, let leftClip = state.leftClip {
                // Sliding left - trim left clip's tail
                leftClipNewDuration = leftClip.duration + delta
            } else if delta > 0, let rightClip = state.rightClip {
                // Sliding right - trim right clip's head
                rightClipNewStartTime = rightClip.startTime + delta
            }
        }

        return SlidePreview(
            clipId: clip.id,
            newStartTime: newStartTime,
            leftClipNewDuration: leftClipNewDuration,
            rightClipNewStartTime: rightClipNewStartTime
        )
    }

    // MARK: - Apply Slide

    /// Apply slide to clips.
    ///
    /// - Parameters:
    ///   - clips: All clips to potentially modify.
    ///   - state: The slide state.
    ///   - preview: The calculated preview.
    /// - Returns: The modified clip list.
    func applySlide(
        _ clips: [TimelineClip],
        state: SlideState,
        preview: SlidePreview
    ) -> [TimelineClip] {
        clips.map { clip in
            if clip.id == preview.clipId {
                // Move the sliding clip
                return clip.moveTo(preview.newStartTime)
            } else if let leftClip = state.leftClip,
                      clip.id == leftClip.id,
                      let newDuration = preview.leftClipNewDuration {
                // Trim left clip's tail
                let newEndTime = clip.startTime + newDuration
                return clip.trimTail(newEndTime)
            } else if let rightClip = state.rightClip,
                      clip.id == rightClip.id,
                      let newStart = preview.rightClipNewStartTime {
                // Trim right clip's head
                return clip.trimHead(newStart)
            }
            return clip
        }
    }

    // MARK: - Cancel Slide

    /// Cancel slide and restore original positions.
    ///
    /// **IMPORTANT LIMITATION**: This method only restores the sliding clip to its original
    /// position. Adjacent clips that may have been trimmed during `applySlide` are NOT restored.
    /// For complete undo/redo support, callers MUST maintain a snapshot of the full timeline
    /// state before calling `startSlide` and restore from that snapshot.
    ///
    /// This is intentional: slide operations should be committed via proper undo/redo commands
    /// that capture complete before/after state, not via incremental restoration.
    ///
    /// - Parameters:
    ///   - clips: Current clips.
    ///   - state: The original slide state.
    /// - Returns: Clips with sliding clip restored (adjacent clips unchanged).
    func cancelSlide(
        _ clips: [TimelineClip],
        state: SlideState
    ) -> [TimelineClip] {
        clips.map { clip in
            if clip.id == state.clip.id {
                return clip.moveTo(state.originalStartTime)
            }
            // Adjacent clips NOT restored - caller handles via undo system
            return clip
        }
    }

    // MARK: - Overlap Detection

    /// Find overlapping clips for overwrite mode.
    ///
    /// - Parameters:
    ///   - clip: The sliding clip.
    ///   - newStartTime: The proposed position.
    ///   - trackClips: Clips on the same track.
    /// - Returns: Clip IDs that would be overlapped.
    func findOverlappedClips(
        clip: TimelineClip,
        newStartTime: TimeMicros,
        trackClips: [TimelineClip]
    ) -> [String] {
        let newRange = TimeRange(newStartTime, newStartTime + clip.duration)
        var overlapped: [String] = []

        for c in trackClips {
            if c.id == clip.id { continue }
            if c.timeRange.overlaps(newRange) {
                overlapped.append(c.id)
            }
        }

        return overlapped
    }
}

// ============================================================================
// MARK: - SlipSlideController
// ============================================================================

/// Combined controller for slip/slide operations.
///
/// Provides a unified interface for both slip and slide editing.
@Observable @MainActor
final class SlipSlideController {

    /// Slide controller instance.
    let slide = SlideController()

    /// Whether currently in slip mode (vs slide).
    var isSlipMode: Bool = true

    /// Toggle between slip and slide modes.
    func toggleMode() {
        isSlipMode = !isSlipMode
    }
}
