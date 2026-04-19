// TimelineNudgeCommand.swift
// LiquidEditor
//
// T7-25 (Premium UI §7.9): Nudge a clip along the timeline by a whole
// number of frames. The Premium UI binds this to the Left / Right
// arrow keys (single frame) and Shift+Arrow (10 frames) from
// `EditorShortcutBindings`.
//
// Because `PersistentTimeline` is sequential, "move a clip" is really
// "remove then re-insert at the new offset". This command is a thin
// helper around that, converting the frame count to microseconds via
// the supplied `frameRate`.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.9
//       (nudge by arrow keys).

import Foundation

// MARK: - TimelineNudgeCommand

/// Stateless command that nudges a clip by a whole number of frames.
enum TimelineNudgeCommand {

    /// Move `clipID` by `byFrames` frames (positive = right, negative = left).
    ///
    /// Clamps so the clip cannot start before t=0. A nudge of zero frames
    /// or an unknown clip returns the input timeline unchanged.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipID: The clip to nudge.
    ///   - byFrames: Number of frames to shift.
    ///   - frameRate: Project frame rate (e.g. 30.0 or 29.97).
    /// - Returns: A new timeline with the clip moved.
    static func nudge(
        timeline: PersistentTimeline,
        clipID: String,
        byFrames: Int,
        frameRate: Double
    ) -> PersistentTimeline {
        guard byFrames != 0, frameRate > 0 else { return timeline }
        guard let item = timeline.getById(clipID),
              let currentStart = timeline.startTimeOf(clipID) else {
            return timeline
        }

        // Convert frames -> microseconds.
        let deltaMicros = TimeMicros(
            Double(byFrames) * (1_000_000.0 / frameRate)
        )
        let newStart = max(0, currentStart + deltaMicros)

        // Remove then re-insert at the new offset.
        let removed = timeline.remove(clipID)
        return removed.insertAt(newStart, item)
    }
}
