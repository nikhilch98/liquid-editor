// TimelineBlendModeCommand.swift
// LiquidEditor
//
// T7-27 (Premium UI §7.11): Per-clip blend modes for overlay compositing.
// The compositor (`MultiTrackCompositor`) reads the blend mode from each
// clip's layer config when building an `MultiTrackInstruction`. This
// command records the user's chosen blend mode on a clip.
//
// Available blend modes mirror the classical Porter-Duff + Photoshop
// selection exposed by Core Image's `CIBlendWithMask` family. Because
// `TimelineItemProtocol` does not yet carry blend-mode state, the
// implementation is deferred to the follow-up that lands per-clip
// layer metadata. This file provides the API and an exhaustive `enum`.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.11
//       (blend modes per clip).

import Foundation

// MARK: - BlendMode

/// Blend modes supported by the overlay compositor. Backed by string
/// raw values so they persist cleanly in project files.
enum BlendMode: String, Sendable, CaseIterable {
    case normal
    case multiply
    case screen
    case overlay
    case softLight
    case hardLight
    case colorDodge
    case colorBurn
    case difference
    case exclusion
}

// MARK: - TimelineBlendModeCommand

/// Stateless command that sets the blend mode on a clip.
enum TimelineBlendModeCommand {

    /// Set `blendMode` on the clip identified by `clipID`.
    ///
    /// No-ops for unknown IDs. Returns a new timeline if a change was
    /// applied; otherwise returns the input unchanged.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - clipID: The clip whose blend mode should change.
    ///   - blendMode: The new blend mode.
    /// - Returns: A new timeline with the blend mode stored on the clip.
    static func setBlendMode(
        timeline: PersistentTimeline,
        clipID: String,
        blendMode: BlendMode
    ) -> PersistentTimeline {
        guard timeline.containsId(clipID) else { return timeline }
        // TODO: rewrite the clip with an updated `blendMode` field once
        // per-clip layer metadata is exposed through
        // `TimelineItemProtocol` (tracked alongside opacity / transform).
        return timeline
    }
}
