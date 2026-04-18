// TimelineDeleteCommand.swift
// LiquidEditor
//
// T7-7 (Premium UI §7.11): Centralizes clip-delete semantics for the
// timeline. Uses the `RippleEditController` to decide whether the
// destructive edit should CLOSE the gap (ripple) or LEAVE a GapClip
// behind (non-ripple) in the same track slot.
//
// Design:
// - Pure-function API over `PersistentTimeline` — the caller owns
//   undo/redo and selection. This keeps commands testable without a
//   full `TimelineViewModel` instance, and avoids exposing a
//   public setter on the viewmodel's `timeline` field.
// - Ripple path: `timeline.remove(id)` — PersistentTimeline is packed,
//   so removing a node already closes the gap.
// - Non-ripple path: replace the clip in place with a `GapClip` of the
//   same duration via `updateItem`.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.11
//       (operations catalog — delete-with-ripple vs delete-with-gap).

import Foundation

// MARK: - TimelineDeleteCommand

/// Stateless command that computes a new timeline after deleting a clip.
///
/// Usage:
/// ```swift
/// if let newTimeline = TimelineDeleteCommand.execute(
///     clipId: "abc",
///     timeline: vm.timeline,
///     ripple: vm.rippleController
/// ) {
///     vm.setTimeline(newTimeline, pushUndo: true)
/// }
/// ```
enum TimelineDeleteCommand {

    // MARK: - Result

    /// The outcome of a delete operation.
    struct Result: Equatable, Sendable {
        /// The updated timeline.
        let timeline: PersistentTimeline

        /// The mode that was used (for haptic / toast wording).
        let mode: RippleMode

        /// Duration of the clip that was deleted / replaced by a gap,
        /// in microseconds. Zero if the clip was not found.
        let removedDurationMicros: TimeMicros
    }

    // MARK: - Execute

    /// Compute a new timeline with the given clip removed.
    ///
    /// - Parameters:
    ///   - clipId: Stable identifier of the clip to delete.
    ///   - timeline: The current timeline.
    ///   - ripple: The `RippleEditController` — its `effectiveMode` decides
    ///             whether the gap closes (`.on`) or is preserved (`.off`).
    ///   - forceInvertRipple: If `true`, the gesture inverts the ripple mode
    ///                       for this one edit (e.g., shift-delete).
    /// - Returns: A `Result` containing the new timeline and applied mode,
    ///            or `nil` if the clip was not found.
    @MainActor
    static func execute(
        clipId: String,
        timeline: PersistentTimeline,
        ripple: RippleEditController,
        forceInvertRipple: Bool = false
    ) -> Result? {
        guard let item = timeline.getById(clipId) else { return nil }

        let mode = ripple.overridingForGesture(inverted: forceInvertRipple)
        let duration = item.durationMicroseconds

        switch mode {
        case .on:
            // Packed remove — no gap.
            let newTimeline = timeline.remove(clipId)
            return Result(
                timeline: newTimeline,
                mode: .on,
                removedDurationMicros: duration
            )

        case .off:
            // Leave a GapClip in place so downstream clips keep their timing.
            // A GapClip with positive duration > 0 is required (GapClip
            // precondition). Clips that hit the edge already have duration
            // > 0 by construction — no special case needed.
            let gap = GapClip(
                id: UUID().uuidString,
                durationMicroseconds: duration
            )
            let newTimeline = timeline.updateItem(clipId, gap)
            return Result(
                timeline: newTimeline,
                mode: .off,
                removedDurationMicros: duration
            )
        }
    }
}
