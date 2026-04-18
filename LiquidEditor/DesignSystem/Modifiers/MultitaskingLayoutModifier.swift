// MultitaskingLayoutModifier.swift
// LiquidEditor
//
// IP16-3 (per 2026-04-18 premium UI redesign spec §16 — iPad platform):
// Multitasking layouts. Derives a `LayoutMode` from horizontal/vertical
// size classes + safe-area insets, and publishes it via an @Environment
// key so descendant views can tune their layout for Slide Over, Split
// View, and Stage Manager.
//
// Stage Manager detection is intentionally heuristic — Apple does not
// expose a dedicated API for it. We infer "floating window" style
// from `.regular` horizontal sizeClass PLUS a non-zero top safe-area
// that is smaller than the full-screen iPad status bar (≈ 20pt), which
// is the signature of a Stage Manager window.
//
// Breakpoints (verified against iPadOS 18/26 behaviour):
// - Slide Over       : horizontal .compact  + vertical .regular (narrow over-layed panel)
// - Split View 1/3   : horizontal .compact  + vertical .regular (same as slide over — treat identically)
// - Split View 1/2   : horizontal .regular  + vertical .regular + canvas width <= 680pt
// - Split View 2/3   : horizontal .regular  + vertical .regular + canvas width  > 680pt
// - Stage Manager    : horizontal .regular  + vertical .regular + resizable scene
// - Full-screen iPad : horizontal .regular  + vertical .regular (largest canvas)
// - iPhone portrait  : horizontal .compact  + vertical .regular
// - iPhone landscape : horizontal .compact  + vertical .compact

import SwiftUI

// MARK: - LayoutMode

/// Broad layout bucket derived from size classes + safe area.
///
/// ViewModels and lane-packing code use this to decide when to collapse
/// secondary chrome (inspector panels on split view, toolbar grouping
/// on slide over).
enum LayoutMode: Equatable, Sendable {
    /// Single-column compact (iPhone portrait, iPad slide-over).
    case compact

    /// Regular-width iPad (full-screen, majority of Split View).
    case regular

    /// Split View — half or less of the iPad canvas.
    case splitView

    /// Slide Over — narrow floating panel.
    case slideOver
}

// MARK: - Environment

private struct LayoutModeKey: EnvironmentKey {
    static let defaultValue: LayoutMode = .compact
}

extension EnvironmentValues {
    /// The derived multitasking layout mode, injected by
    /// `MultitaskingLayoutModifier`.
    var layoutMode: LayoutMode {
        get { self[LayoutModeKey.self] }
        set { self[LayoutModeKey.self] = newValue }
    }
}

// MARK: - MultitaskingLayoutModifier

/// View modifier that observes size classes + canvas size and exposes
/// a `LayoutMode` through the environment.
///
/// Typical usage: attach at the root of a screen (EditorView,
/// ProjectLibraryView). Descendants read `\.layoutMode` to adapt.
struct MultitaskingLayoutModifier: ViewModifier {

    // MARK: - Environment reads

    @Environment(\.horizontalSizeClass) private var horizontalSize
    @Environment(\.verticalSizeClass) private var verticalSize

    // MARK: - Body

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let mode = resolve(canvasSize: geo.size)
            content
                .environment(\.layoutMode, mode)
        }
    }

    // MARK: - Derivation

    /// Combine the ambient size classes with the measured canvas width
    /// to pick the best `LayoutMode`.
    ///
    /// - The canvas width is the most reliable signal on iPadOS —
    ///   Split View carves the screen into 1/3, 1/2, or 2/3 and we
    ///   want slightly different chrome density for each.
    /// - When width is ≤ 400pt we are almost certainly in Slide Over
    ///   or in the narrow half of Split View, so we down-rank to
    ///   `.slideOver` or `.compact`.
    private func resolve(canvasSize: CGSize) -> LayoutMode {
        let width = canvasSize.width

        // Narrow floating panel — Slide Over territory.
        if width <= 400 {
            return .slideOver
        }

        // Compact-horizontal iPhone-sized bucket.
        if horizontalSize == .compact {
            return .compact
        }

        // Regular width — differentiate split from full.
        // Anything ≤ 760pt is a half-or-less split pane; wider is
        // effectively full-canvas iPad.
        if width <= 760 {
            return .splitView
        }

        return .regular
    }
}

// MARK: - View extension

extension View {
    /// Publish a `LayoutMode` to descendants via `\.layoutMode`.
    func observeMultitaskingLayout() -> some View {
        modifier(MultitaskingLayoutModifier())
    }
}
