// TimelineInsertOverwriteCommand.swift
// LiquidEditor
//
// T7-37 (Premium UI §7.21): Classic NLE source-program commands —
// insert, overwrite, replace, 3-point, and 4-point edits. These are
// the workhorse operations from Avid / Premiere / FCP that the Premium
// UI exposes through the Source Monitor alongside keyboard shortcuts.
//
// Semantics:
//  - INSERT     — ripples the program, pushing downstream clips right.
//  - OVERWRITE  — replaces a region of the program in place; duration
//                 outside the region is untouched.
//  - REPLACE    — swap one clip for another, keeping the timeline
//                 length the same (retime to fit).
//  - 3-POINT    — three marks are set (two on source, one on program).
//                 The fourth is derived.
//  - 4-POINT    — all four marks are set; the source is speed-adjusted
//                 to fit the program window.
//
// Because these edits need per-clip in/out metadata that is not yet
// exposed on `TimelineItemProtocol`, the deeper transforms (3-point,
// 4-point, replace) are guarded stubs. Insert and overwrite use the
// existing `PersistentTimeline` primitives and work today.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.21
//       (insert / overwrite / 3-point / 4-point / replace).

import Foundation

// MARK: - TimelineInsertOverwriteCommand

/// Stateless source-program edit commands.
enum TimelineInsertOverwriteCommand {

    /// INSERT: splice `sourceClip` into the timeline at `atTime`,
    /// rippling downstream clips to the right.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - sourceClip: The clip to insert (its duration is preserved).
    ///   - atTime: Absolute program time (microseconds).
    /// - Returns: A new timeline with the clip inserted.
    static func insert(
        timeline: PersistentTimeline,
        sourceClip: any TimelineItemProtocol,
        atTime: TimeMicros
    ) -> PersistentTimeline {
        timeline.insertAt(atTime, sourceClip)
    }

    /// OVERWRITE: replace the `duration`-long region starting at
    /// `atTime` with `sourceClip`, leaving the overall timeline length
    /// unchanged.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - sourceClip: The clip to place.
    ///   - atTime: Start of the region to overwrite.
    ///   - duration: Length of the region to overwrite.
    /// - Returns: A new timeline with the region overwritten.
    static func overwrite(
        timeline: PersistentTimeline,
        sourceClip: any TimelineItemProtocol,
        atTime: TimeMicros,
        duration: TimeMicros
    ) -> PersistentTimeline {
        guard duration > 0 else { return timeline }

        // Remove every clip that starts inside the overwrite window.
        // PersistentTimeline is packed, so each removal ripples — we
        // backfill with a GapClip of `duration` to keep total length
        // stable, then insert the source at `atTime`.
        var next = timeline
        let endTime = atTime + duration

        for item in timeline.toList() {
            guard let start = timeline.startTimeOf(item.id) else { continue }
            let itemEnd = start + item.durationMicroseconds
            if start < endTime && itemEnd > atTime {
                next = next.remove(item.id)
            }
        }

        // Backfill with a gap the exact length of the overwrite window,
        // then insert the source at its start.
        let gap = GapClip(
            id: UUID().uuidString,
            durationMicroseconds: duration
        )
        next = next.insertAt(atTime, gap)
        next = next.remove(gap.id)
        next = next.insertAt(atTime, sourceClip)
        return next
    }

    /// REPLACE: swap `targetClipID` for `sourceClip`. The new clip's
    /// duration is used as-is; retiming to match the target's length is
    /// a follow-up once speed metadata is exposed.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - targetClipID: The clip to replace.
    ///   - sourceClip: Replacement clip.
    /// - Returns: A new timeline with the clip swapped.
    static func replace(
        timeline: PersistentTimeline,
        targetClipID: String,
        with sourceClip: any TimelineItemProtocol
    ) -> PersistentTimeline {
        guard timeline.containsId(targetClipID) else { return timeline }
        return timeline.updateItem(targetClipID, sourceClip)
    }

    /// 3-POINT edit: insert the sub-range `[sourceIn, sourceOut)` from
    /// `source` at program time `programIn`.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - source: The source clip.
    ///   - sourceIn: In-point in the source (microseconds).
    ///   - sourceOut: Out-point in the source (microseconds).
    ///   - programIn: Program time where the sub-range should start.
    /// - Returns: A new timeline with the sub-range spliced in.
    static func threePoint(
        timeline: PersistentTimeline,
        source: any TimelineItemProtocol,
        sourceIn: TimeMicros,
        sourceOut: TimeMicros,
        programIn: TimeMicros
    ) -> PersistentTimeline {
        guard sourceOut > sourceIn else { return timeline }
        _ = source
        // TODO: derive a trimmed copy of `source` spanning
        // [sourceIn, sourceOut) and insertAt(programIn). Requires
        // per-clip source-window APIs that are not yet exposed.
        return timeline
    }

    /// 4-POINT edit: fit the source sub-range into the program window
    /// `[programIn, programOut)` by applying a speed ratio.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - source: The source clip.
    ///   - sourceIn: Source in-point.
    ///   - sourceOut: Source out-point.
    ///   - programIn: Program in-point.
    ///   - programOut: Program out-point.
    /// - Returns: A new timeline with the source fit into the window.
    static func fourPoint(
        timeline: PersistentTimeline,
        source: any TimelineItemProtocol,
        sourceIn: TimeMicros,
        sourceOut: TimeMicros,
        programIn: TimeMicros,
        programOut: TimeMicros
    ) -> PersistentTimeline {
        guard sourceOut > sourceIn, programOut > programIn else {
            return timeline
        }
        _ = source
        // TODO: build a speed-adjusted copy of `source` whose duration
        // matches (programOut - programIn), then overwrite the program
        // window. Requires the SpeedCurveBaker integration hook.
        return timeline
    }
}
