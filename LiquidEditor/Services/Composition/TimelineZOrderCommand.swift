// TimelineZOrderCommand.swift
// LiquidEditor
//
// T7-26 (Premium UI §7.10): Bring-to-front / Send-to-back for clips on
// overlay tracks. Z-order on overlays is encoded by trackIndex in the
// compositor (higher index = renders on top), so "bring to front"
// means moving the clip to the highest overlay track, and "send to
// back" means moving it to the lowest overlay track (but not below the
// main track at index 0).
//
// Per-clip track metadata is not yet expressed on
// `TimelineItemProtocol`, so the concrete implementation is deferred.
// This file establishes the API so gesture and menu call sites compile
// today.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.10
//       (z-order on overlay tracks).

import Foundation

// MARK: - TimelineZOrderCommand

/// Stateless commands for re-ordering an overlay clip in z-space.
enum TimelineZOrderCommand {

    /// Move `clipID` to the top-most overlay track.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipID: The clip to move.
    /// - Returns: A new timeline with the clip at the top overlay.
    static func bringToFront(
        timeline: PersistentTimeline,
        clipID: String
    ) -> PersistentTimeline {
        guard timeline.containsId(clipID) else { return timeline }
        // TODO: rewrite the clip's trackIndex to (maxTrackIndex + 1),
        // then normalise indices so there are no gaps.
        return timeline
    }

    /// Move `clipID` to the bottom-most overlay track (but not below the
    /// main track at index 0).
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipID: The clip to move.
    /// - Returns: A new timeline with the clip at the lowest overlay.
    static func sendToBack(
        timeline: PersistentTimeline,
        clipID: String
    ) -> PersistentTimeline {
        guard timeline.containsId(clipID) else { return timeline }
        // TODO: rewrite the clip's trackIndex to 1 (just above main) and
        // push any existing overlays up by one index.
        return timeline
    }
}
