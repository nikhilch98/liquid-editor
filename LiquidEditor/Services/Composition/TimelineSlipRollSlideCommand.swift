// TimelineSlipRollSlideCommand.swift
// LiquidEditor
//
// T7-18 (Premium UI §7.4): Slip / Roll / Slide professional edit tools.
//
// Definitions (classical NLE semantics):
//  - SLIP  — shift the SOURCE media window inside a clip without
//            changing its timeline position or duration. Only the
//            clip's in/out points move.
//  - ROLL  — move the boundary between two adjacent clips. The left
//            clip's out-point and the right clip's in-point change in
//            lockstep; the overall timeline length is preserved.
//  - SLIDE — move a clip along the timeline. The clip's own duration
//            stays the same; the neighbouring clips shrink/grow to
//            compensate so total duration is unchanged.
//
// These operations touch per-clip in/out points which live on the
// concrete clip types (`VideoClip`, `AudioClip`, ...), not on
// `TimelineItemProtocol`. The full implementation requires specialised
// paths per clip kind. This file establishes the API; each function is
// a guarded stub that returns the input timeline until those paths
// land.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.4
//       (slip / roll / slide).

import Foundation

// MARK: - TimelineSlipRollSlideCommand

/// Stateless commands for the three professional boundary-edits.
enum TimelineSlipRollSlideCommand {

    /// SLIP: shift the source-media window inside `clipId` by
    /// `deltaMicros`. Clip duration and timeline position are unchanged.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipId: Clip whose source window should slip.
    ///   - deltaMicros: Positive shifts the window forward in the source
    ///     (reveals later media); negative shifts it backward.
    /// - Returns: A new timeline with the clip's in/out points shifted.
    static func slip(
        timeline: PersistentTimeline,
        clipId: String,
        deltaMicros: TimeMicros
    ) -> PersistentTimeline {
        guard timeline.containsId(clipId), deltaMicros != 0 else {
            return timeline
        }
        // TODO: implement per-clip-type source-window shift (VideoClip /
        // AudioClip expose startTime/endTime on their source asset).
        return timeline
    }

    /// ROLL: move the boundary between `leftClipId` and `rightClipId`
    /// by `deltaMicros`. Total timeline duration is preserved.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - leftClipId: The clip whose out-point moves.
    ///   - rightClipId: The adjacent clip whose in-point moves.
    ///   - deltaMicros: Positive rolls the boundary to the right
    ///     (extends left clip, shrinks right clip).
    /// - Returns: A new timeline with the boundary adjusted.
    static func roll(
        timeline: PersistentTimeline,
        leftClipId: String,
        rightClipId: String,
        deltaMicros: TimeMicros
    ) -> PersistentTimeline {
        guard timeline.containsId(leftClipId),
              timeline.containsId(rightClipId),
              deltaMicros != 0 else {
            return timeline
        }
        // TODO: adjust left.outPoint and right.inPoint by deltaMicros
        // within each clip's source media constraints.
        return timeline
    }

    /// SLIDE: move `clipId` along the timeline by `deltaMicros`,
    /// absorbing the shift into the adjacent clips' durations.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipId: Clip to slide.
    ///   - deltaMicros: Positive slides the clip to the right.
    /// - Returns: A new timeline with the clip slid and neighbours
    ///            resized.
    static func slide(
        timeline: PersistentTimeline,
        clipId: String,
        deltaMicros: TimeMicros
    ) -> PersistentTimeline {
        guard timeline.containsId(clipId), deltaMicros != 0 else {
            return timeline
        }
        // TODO: find immediate neighbours via startTimeOf/itemAtIndex,
        // grow/shrink them, keep `clipId` duration constant.
        return timeline
    }
}
