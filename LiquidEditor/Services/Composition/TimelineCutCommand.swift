// TimelineCutCommand.swift
// LiquidEditor
//
// T7-30 (Premium UI §7.11): Cut (⌘X) for the timeline. Copies the
// clip's state to an in-memory clipboard then delegates the removal
// to `TimelineDeleteCommand` so ripple-mode is honored by the same
// central policy.
//
// Clipboard storage:
// - `ClipboardStore` is a singleton `@MainActor` @Observable class with a
//   single-slot `TimelineClipboardEntry` payload (Premium UI only needs
//   one clip at a time; multi-selection cut is future work tracked in
//   the spec backlog).
// - The stored clip keeps its original `TimelineItemProtocol` payload
//   plus the source track ID (if known) so Paste can place it back on
//   the correct track.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.11
//       (operations catalog — cut / copy / paste).

import Foundation
import Observation

// MARK: - TimelineClipboardEntry

/// A single clipboard payload captured by Cut or Copy.
struct TimelineClipboardEntry: Sendable {
    /// The snapshot of the clip's state at cut-time.
    let clip: any TimelineItemProtocol

    /// Source track ID when known. `nil` means paste onto the primary track.
    let sourceTrackId: String?

    /// Wall-clock timestamp for debugging / telemetry.
    let capturedAt: Date

    init(
        clip: any TimelineItemProtocol,
        sourceTrackId: String?,
        capturedAt: Date = Date()
    ) {
        self.clip = clip
        self.sourceTrackId = sourceTrackId
        self.capturedAt = capturedAt
    }
}

// MARK: - ClipboardStore

/// Singleton, @MainActor, @Observable in-memory clipboard for timeline
/// clips. Survives for the lifetime of the process; not persisted.
@Observable
@MainActor
final class ClipboardStore {

    // MARK: - Singleton

    static let shared = ClipboardStore()

    // MARK: - Payload

    /// The most recent clip captured by Cut or Copy. `nil` when empty.
    private(set) var current: TimelineClipboardEntry?

    // MARK: - Init

    /// Public init so tests can build a fresh instance; production code
    /// uses ``shared``.
    init() {}

    // MARK: - API

    /// Store a clip in the clipboard (single-slot; replaces any prior entry).
    func write(_ clip: any TimelineItemProtocol, sourceTrackId: String? = nil) {
        current = TimelineClipboardEntry(
            clip: clip,
            sourceTrackId: sourceTrackId
        )
    }

    /// Clear the clipboard contents.
    func clear() {
        current = nil
    }

    /// `true` if the clipboard holds a clip.
    var hasContents: Bool { current != nil }
}

// MARK: - TimelineCutCommand

/// Stateless command that performs a Cut.
///
/// Usage:
/// ```swift
/// if let result = TimelineCutCommand.execute(
///     clipId: "abc",
///     timeline: vm.timeline,
///     sourceTrackId: trackId,
///     ripple: vm.rippleController,
///     clipboard: .shared
/// ) {
///     vm.setTimeline(result.timeline, pushUndo: true)
/// }
/// ```
enum TimelineCutCommand {

    // MARK: - Execute

    /// Copy `clipId`'s state to the clipboard, then delete via
    /// `TimelineDeleteCommand` (ripple-aware).
    ///
    /// - Returns: The delete-command result, or `nil` if the clip wasn't
    ///            found (in which case nothing was written to the
    ///            clipboard either).
    @MainActor
    static func execute(
        clipId: String,
        timeline: PersistentTimeline,
        sourceTrackId: String? = nil,
        ripple: RippleEditController,
        clipboard: ClipboardStore = .shared,
        forceInvertRipple: Bool = false
    ) -> TimelineDeleteCommand.Result? {
        guard let clip = timeline.getById(clipId) else { return nil }

        // Write to clipboard BEFORE deleting so we never lose the payload
        // if the delete fails (deletion below can't fail given the same
        // guard, but the ordering is defensive).
        clipboard.write(clip, sourceTrackId: sourceTrackId)

        return TimelineDeleteCommand.execute(
            clipId: clipId,
            timeline: timeline,
            ripple: ripple,
            forceInvertRipple: forceInvertRipple
        )
    }
}
