// TimelineCollapseGapCommand.swift
// LiquidEditor
//
// T7-31 (Premium UI §7.15): Collapse the gap at a given timeline
// position. Any `GapClip` whose interval contains `atTime` is removed,
// and because `PersistentTimeline` is packed, all subsequent clips
// ripple leftward by the gap's duration automatically.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.15
//       (collapse gap action).

import Foundation

// MARK: - TimelineCollapseGapCommand

/// Stateless command that collapses a gap clip at a given time.
enum TimelineCollapseGapCommand {

    /// Collapse the gap that contains `atTime`, rippling all downstream
    /// clips to close it.
    ///
    /// If no gap exists at that time, the input timeline is returned
    /// unchanged.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - atTime: Absolute time (microseconds) inside the gap to collapse.
    /// - Returns: A new timeline with the gap removed.
    static func collapseGap(
        timeline: PersistentTimeline,
        atTime: TimeMicros
    ) -> PersistentTimeline {
        guard let (item, _) = timeline.itemAtTime(atTime) else {
            return timeline
        }
        // Only collapse when the hit-test lands on an explicit GapClip —
        // live media is never collapsed implicitly.
        guard item is GapClip else { return timeline }
        // `remove` on a packed timeline closes the gap for us.
        return timeline.remove(item.id)
    }
}
