// TimelineTrackReorderCommand.swift
// LiquidEditor
//
// T7-16 (Premium UI §7.2): Vertical track reordering. The Premium UI
// lets the user drag a whole track up or down to change its z-order on
// the preview canvas (the main track always stays at index 0). This
// command produces a new `PersistentTimeline` reflecting a reorder from
// `from` -> `to`.
//
// `PersistentTimeline` is a single packed sequence today — track
// metadata (track index, name, visibility) lives alongside each item
// via `TrackLayerClip` / overlay wrappers. A full reorder therefore
// requires rewriting every clip's stored track index. The concrete
// implementation is deferred; this file establishes the API surface so
// call sites (EditorViewModel / gesture handlers) can compile against
// it today.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.2
//       (vertical track reordering).

import Foundation

// MARK: - TimelineTrackReorderCommand

/// Stateless command that reorders a whole track.
enum TimelineTrackReorderCommand {

    /// Move the track currently at `from` to index `to`, shifting
    /// intermediate tracks by one.
    ///
    /// Out-of-range indices and `from == to` return the input unchanged
    /// so callers don't need to guard.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - from: The source track index.
    ///   - to: The destination track index.
    /// - Returns: A new timeline with tracks reordered.
    static func reorderTrack(
        timeline: PersistentTimeline,
        from: Int,
        to: Int
    ) -> PersistentTimeline {
        // Guard invalid or no-op cases.
        guard from >= 0, to >= 0, from != to else { return timeline }

        // TODO: implement full reorder once per-clip track metadata is
        // exposed on `TimelineItemProtocol`. The high-level algorithm:
        //  1. Enumerate items and extract each clip's current trackIndex.
        //  2. Compute a permutation mapping old trackIndex -> new index.
        //  3. Rebuild clips with updated trackIndex via updateItem.
        //  4. Return the resulting timeline; order within a track is
        //     preserved by PersistentTimeline's in-order traversal.
        return timeline
    }
}
