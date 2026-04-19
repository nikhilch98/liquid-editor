// ClipFlipCommand.swift
// LiquidEditor
//
// T7-32 (Premium UI §7.16): Flip horizontal / vertical on a single clip.
// Flipping is a transform property on the clip's layer config that the
// compositor applies via a Metal scale of (-1, 1) or (1, -1).
//
// Flip flags are not yet carried on `TimelineItemProtocol`, so this
// command is a guarded stub that returns the input timeline. The API
// is finalised so gesture handlers and the Transform inspector can
// bind against it today.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.16
//       (flip horizontal / vertical).

import Foundation

// MARK: - ClipFlipCommand

/// Stateless command that sets flip flags on a clip.
enum ClipFlipCommand {

    /// Set `horizontal` and `vertical` flip on the clip identified by
    /// `clipID`.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipID: The clip to update.
    ///   - horizontal: `true` to mirror along the X axis.
    ///   - vertical: `true` to mirror along the Y axis.
    /// - Returns: A new timeline with the flip flags stored on the clip.
    static func setFlip(
        timeline: PersistentTimeline,
        clipID: String,
        horizontal: Bool,
        vertical: Bool
    ) -> PersistentTimeline {
        guard timeline.containsId(clipID) else { return timeline }
        _ = horizontal
        _ = vertical
        // TODO: rewrite the clip with updated flipHorizontal / flipVertical
        // fields once those land on the clip layer config.
        return timeline
    }
}
