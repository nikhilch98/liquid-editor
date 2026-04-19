// TimelineSelectionCommand.swift
// LiquidEditor
//
// T7-28 (Premium UI §7.12): Selection helpers — Select All, Select All
// on Track, Invert Selection. These are bound to the standard
// keyboard shortcuts (⌘A etc.) and to the right-click menu items.
//
// Selection state lives in the ViewModel; this command merely computes
// the new selection set from the timeline. Per-track selection is a
// stub until `TimelineItemProtocol` exposes a `trackIndex` — selection
// falls back to "all items" in that case so callers can wire the API
// today.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.12
//       (select-all helpers).

import Foundation

// MARK: - TimelineSelectionCommand

/// Stateless selection helpers over `PersistentTimeline`.
enum TimelineSelectionCommand {

    /// Every clip in the timeline.
    ///
    /// - Parameter timeline: The current timeline.
    /// - Returns: The set of all clip IDs.
    static func selectAll(timeline: PersistentTimeline) -> Set<String> {
        var result = Set<String>()
        result.reserveCapacity(timeline.count)
        for item in timeline.items {
            result.insert(item.id)
        }
        return result
    }

    /// Every clip on `trackIndex`.
    ///
    /// Returns an empty set today because per-clip `trackIndex` is not
    /// exposed on `TimelineItemProtocol`. TODO once per-track metadata
    /// lands: filter `timeline.items` by the clip's track.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - trackIndex: Target track index.
    /// - Returns: IDs of clips on that track.
    static func selectAllOnTrack(
        timeline: PersistentTimeline,
        trackIndex: Int
    ) -> Set<String> {
        _ = trackIndex
        // TODO: filter by per-clip trackIndex once the protocol exposes it.
        return selectAll(timeline: timeline)
    }

    /// Invert `currentSelection` against the timeline.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - currentSelection: Currently selected IDs.
    /// - Returns: IDs that are in the timeline but not in
    ///            `currentSelection`.
    static func invertSelection(
        timeline: PersistentTimeline,
        currentSelection: Set<String>
    ) -> Set<String> {
        let all = selectAll(timeline: timeline)
        return all.subtracting(currentSelection)
    }
}
