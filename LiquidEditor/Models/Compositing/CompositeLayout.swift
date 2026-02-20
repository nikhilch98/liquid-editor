// CompositeLayout.swift
// LiquidEditor
//
// Composite layout modes for multi-track video compositing.
// Defines how a track's content is spatially arranged in the output frame.

import Foundation

/// How a track is spatially arranged in the output frame.
enum CompositeLayout: String, Codable, CaseIterable, Sendable {
    /// Track fills entire output frame (used for main video and full-frame overlays).
    case fullFrame

    /// Track is positioned in a sub-region (Picture-in-Picture).
    case pip

    /// Track occupies one cell of a split-screen grid.
    case splitScreen

    /// Track is custom-positioned via per-clip OverlayTransform keyframes.
    ///
    /// This is the most flexible mode -- position/scale/rotation are
    /// fully keyframeable per clip.
    case freeform

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .fullFrame:
            return "Full Frame"
        case .pip:
            return "Picture in Picture"
        case .splitScreen:
            return "Split Screen"
        case .freeform:
            return "Freeform"
        }
    }
}
