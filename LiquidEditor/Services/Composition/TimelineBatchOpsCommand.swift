// TimelineBatchOpsCommand.swift
// LiquidEditor
//
// T7-15 (Premium UI §7.1): Multi-clip batch operations. Applies a single
// operation to every clip in a selection, returning a new
// `PersistentTimeline`. Mirrors the pattern used by
// `TimelineCutCommand` / `TimelineDeleteCommand`: a pure function over
// the timeline, owning neither selection state nor undo history.
//
// The supported ops cover the common batch actions from the spec:
//  - `.delete`  — remove every selected clip, leaving `GapClip` spacers.
//  - `.ripple`  — remove every selected clip and close the resulting gaps.
//  - `.mute`    — TODO: per-clip mute flag (audio + video tracks).
//  - `.lock`    — TODO: per-clip lock flag preventing edits.
//  - `.unlink`  — TODO: detach A/V-linked pairs so each can be edited
//                 independently.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.1
//       (multi-clip batch ops).

import Foundation

// MARK: - TimelineBatchOpsCommand

/// Stateless command that applies a batch operation across a selection.
enum TimelineBatchOpsCommand {

    // MARK: - Op

    /// Supported batch operations.
    enum Op: String, Sendable, CaseIterable {
        /// Non-ripple delete — leaves `GapClip` spacers.
        case delete
        /// Ripple delete — closes the gap left by each removed clip.
        case ripple
        /// Toggle mute on every selected clip. TODO: wire to per-clip flag.
        case mute
        /// Toggle lock on every selected clip. TODO: wire to per-clip flag.
        case lock
        /// Detach linked A/V pairs. TODO: emit separate audio + video clips.
        case unlink
    }

    // MARK: - Apply

    /// Apply `op` to every clip in `selection`, returning a new timeline.
    ///
    /// Unknown IDs in `selection` are ignored. The returned timeline is
    /// always safe to assign back onto a view-model (value-typed, immutable).
    ///
    /// - Parameters:
    ///   - timeline: The timeline to transform.
    ///   - selection: Stable IDs of the clips to operate on.
    ///   - op: Which operation to perform.
    /// - Returns: A new timeline with the op applied.
    static func applyToAll(
        timeline: PersistentTimeline,
        selection: Set<String>,
        op: Op
    ) -> PersistentTimeline {
        guard !selection.isEmpty else { return timeline }

        switch op {
        case .delete:
            // Non-ripple: replace each selected clip with a GapClip of the
            // same duration so downstream clips keep their positions.
            var next = timeline
            for id in selection {
                guard let item = next.getById(id) else { continue }
                let gap = GapClip(
                    id: UUID().uuidString,
                    durationMicroseconds: item.durationMicroseconds
                )
                next = next.updateItem(id, gap)
            }
            return next

        case .ripple:
            // Ripple: remove each selected clip — PersistentTimeline is
            // packed, so this closes the gap automatically.
            var next = timeline
            for id in selection {
                next = next.remove(id)
            }
            return next

        case .mute, .lock, .unlink:
            // TODO: implement mute/lock/unlink once per-clip flags land on
            // `TimelineItemProtocol`. For now the op is a no-op so the
            // call site can wire up UI without a separate branch.
            return timeline
        }
    }
}
