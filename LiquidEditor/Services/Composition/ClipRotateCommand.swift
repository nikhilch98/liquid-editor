// ClipRotateCommand.swift
// LiquidEditor
//
// T7-33 (Premium UI §7.17): Quick 90/180/270 rotation on a clip. The
// Premium UI exposes this via a cycle button in the Transform
// inspector — each press advances through `.none -> .right -> .upsideDown
// -> .left -> .none`.
//
// Rotation is a transform property on the clip's layer config. Because
// that field is not yet part of `TimelineItemProtocol`, this command
// provides the API and enum so UI code can compile; the timeline
// mutation is deferred.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.17
//       (quick rotate 0/90/180/270).

import Foundation

// MARK: - Rotation

/// Fixed-step rotation in degrees. Raw value matches the rotation angle
/// so it persists cleanly and is easy to apply as a Metal transform.
enum Rotation: Int, Sendable, CaseIterable {
    case none = 0
    case right = 90
    case upsideDown = 180
    case left = 270
}

// MARK: - ClipRotateCommand

/// Stateless command that sets a fixed-step rotation on a clip.
enum ClipRotateCommand {

    /// Set `rotation` on the clip identified by `clipID`.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipID: The clip to update.
    ///   - rotation: The new rotation.
    /// - Returns: A new timeline with the rotation stored on the clip.
    static func setRotation(
        timeline: PersistentTimeline,
        clipID: String,
        rotation: Rotation
    ) -> PersistentTimeline {
        guard timeline.containsId(clipID) else { return timeline }
        _ = rotation
        // TODO: rewrite the clip with an updated rotation field on its
        // transform config once that lands on `TimelineItemProtocol`.
        return timeline
    }
}
