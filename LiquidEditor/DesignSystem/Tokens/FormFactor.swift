// FormFactor.swift
// LiquidEditor
//
// Derived adaptivity flag for the 2026-04-18 premium UI redesign.
// EditorView measures its canvas with GeometryReader and picks a
// FormFactor that drives tap targets, font scale, lane heights.

import SwiftUI

/// Two-step responsive flag used across the editor shell.
/// `.compact` targets iPhone / split-view iPad; `.regular` is iPad
/// full-canvas.
///
/// Derivation uses the smaller of width/height so that an iPad rotated
/// into portrait or squeezed into slideover still lands correctly.
enum FormFactor: Equatable, Sendable {
    case compact
    case regular

    /// Threshold in points at which the layout flips. Match to the
    /// iPad's smallest bounding dimension in a side-by-side split
    /// (around 640 pt on a 12.9" device at 1/2 split).
    static let regularMinDimension: CGFloat = 640

    init(canvasSize: CGSize) {
        let minDim = min(canvasSize.width, canvasSize.height)
        self = minDim >= Self.regularMinDimension ? .regular : .compact
    }

    // MARK: - Sizing tokens

    /// Tool button width.
    var toolButtonWidth: CGFloat { self == .compact ? 48 : 52 }

    /// Tool button height.
    var toolButtonHeight: CGFloat { self == .compact ? 72 : 80 }

    /// Track lane height on the timeline.
    var trackLaneHeight: CGFloat { self == .compact ? 56 : 72 }

    /// Playback controls row height.
    var playbackControlsHeight: CGFloat { self == .compact ? 56 : 64 }

    /// Timeline card height.
    var timelineHeight: CGFloat { self == .compact ? 180 : 240 }

    /// Primary CTA height.
    var primaryCTAHeight: CGFloat { self == .compact ? 44 : 48 }

    /// iPad max-width for nav bar + toolbar (timeline stretches full-canvas).
    var chromeMaxWidth: CGFloat { self == .compact ? .infinity : 1180 }
}

// MARK: - Environment

private struct FormFactorKey: EnvironmentKey {
    static let defaultValue: FormFactor = .compact
}

extension EnvironmentValues {
    /// Current form factor, injected at the EditorView root.
    var formFactor: FormFactor {
        get { self[FormFactorKey.self] }
        set { self[FormFactorKey.self] = newValue }
    }
}
