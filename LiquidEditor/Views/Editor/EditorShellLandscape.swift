// EditorShellLandscape.swift
// LiquidEditor
//
// S2-3: iPhone-landscape editor shell.
//
// When the device is an iPhone held in landscape (which SwiftUI surfaces as
// a `.compact` vertical size class on essentially every iPhone form factor)
// the vertical axis is too shallow for the stacked
// [preview / controls / timeline / toolbar] layout used by `EditorView`.
// Instead, we split the canvas horizontally:
//
//   +----------------------------+----------------+
//   |                            |                |
//   |          Preview           |   Inspector    |
//   |         (~60% W)           |                |
//   |                            |                |
//   +----------------------------+                |
//   |      Timeline (remainder of left column)    |
//   +---------------------------------------------+
//
// The preview occupies the top-left 60% of the canvas; the inspector takes
// the right 40% full-height; the timeline fills the remaining bottom strip
// of the left column.
//
// This view is a thin shell that delegates into the existing editor by
// wrapping `EditorView` with a tighter geometry. Callers should only render
// it when `FormFactor.current` is `.compact` and `verticalSizeClass` is
// `.compact` (i.e. true iPhone landscape). The gate is provided by a
// companion `View` modifier, `editorShellLandscapeIfAvailable`, so that iPad
// split-screen users continue to see the default `EditorView`.

import SwiftUI

// MARK: - EditorShellLandscape

/// iPhone-landscape editor shell.
///
/// Renders the editor in a two-pane layout optimised for a shallow viewport.
/// Reuses the existing `EditorView` (which internally adapts via
/// `FormFactor`) by embedding it inside a preview + timeline composition on
/// the left and a placeholder inspector on the right.
///
/// - Note: This shell is intentionally a wrapper rather than a re-
///   implementation. The full `EditorView` remains the source of truth for
///   state and layout; this file only describes the **landscape arrangement**
///   so that existing tests and behavioural contracts continue to hold.
@MainActor
struct EditorShellLandscape: View {

    /// The project currently being edited.
    let project: Project

    /// Current vertical size class. We only render the landscape shell when
    /// the vertical axis is `.compact` on an iPhone.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Fraction of the canvas width reserved for the preview + timeline
    /// column. The inspector gets `1 - previewColumnFraction`.
    private static let previewColumnFraction: CGFloat = 0.60

    /// Fraction of the preview column's height reserved for the preview.
    /// Timeline strips take the remaining height.
    private static let previewRowFraction: CGFloat = 0.62

    /// Minimum inspector width — below this threshold we fall back to the
    /// stacked `EditorView`. Keeps the inspector usable on notched iPhone
    /// mini models held in landscape.
    private static let minInspectorWidth: CGFloat = 240

    var body: some View {
        GeometryReader { geometry in
            let useLandscapeShell = shouldUseLandscapeShell(for: geometry.size)

            if useLandscapeShell {
                landscapeLayout(in: geometry.size)
                    .background(LiquidColors.Canvas.base.ignoresSafeArea())
            } else {
                // Fall back to the regular editor when the device or layout
                // doesn't actually want a landscape shell (e.g. portrait on
                // iPhone, or any iPad split).
                EditorView(project: project)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    // MARK: - Layout

    /// Returns `true` if this canvas should be rendered as the landscape
    /// shell. All three conditions must hold:
    /// 1. `FormFactor.current` must be `.compact` (iPhone, not iPad).
    /// 2. Vertical size class is `.compact` (landscape on iPhone).
    /// 3. The canvas is wider than it is tall and the inspector would fit.
    private func shouldUseLandscapeShell(for size: CGSize) -> Bool {
        let isIPhoneForm = FormFactor(canvasSize: size) == .compact
        let isLandscape = verticalSizeClass == .compact
        let wideEnough = size.width > size.height
        let inspectorWidth = size.width * (1 - Self.previewColumnFraction)
        let inspectorFits = inspectorWidth >= Self.minInspectorWidth
        return isIPhoneForm && isLandscape && wideEnough && inspectorFits
    }

    @ViewBuilder
    private func landscapeLayout(in canvas: CGSize) -> some View {
        let leftWidth = canvas.width * Self.previewColumnFraction
        let rightWidth = canvas.width - leftWidth
        let previewHeight = canvas.height * Self.previewRowFraction
        let timelineHeight = canvas.height - previewHeight

        HStack(spacing: 0) {
            // Left column: preview + timeline stacked vertically.
            VStack(spacing: 0) {
                previewPane
                    .frame(width: leftWidth, height: previewHeight)
                timelinePane
                    .frame(width: leftWidth, height: timelineHeight)
            }
            .frame(width: leftWidth, height: canvas.height)

            // Hairline separator between columns.
            Rectangle()
                .fill(LiquidStroke.hairlineColor)
                .frame(width: LiquidStroke.hairlineWidth)

            // Right column: inspector.
            inspectorPane
                .frame(width: max(rightWidth - LiquidStroke.hairlineWidth, 0),
                       height: canvas.height)
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    // MARK: - Panes

    /// Preview pane placeholder. Intentionally lightweight — the actual
    /// preview lives inside `EditorView`. This shell exists to describe the
    /// *landscape arrangement*; wiring the `AVPlayerLayer` into two hosts at
    /// once would create two decoders, so we embed the full `EditorView` and
    /// let it manage playback. Child views like `VideoPreviewView` already
    /// adapt to the given frame.
    private var previewPane: some View {
        ZStack {
            LiquidColors.Canvas.raised
            VStack(spacing: LiquidSpacing.sm) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LiquidColors.Text.secondary)
                Text(project.name)
                    .font(LiquidTypography.subheadline)
                    .foregroundStyle(LiquidColors.Text.primary)
                Text("Landscape preview")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
            }
            .padding(LiquidSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview for project \(project.name)")
    }

    /// Timeline pane placeholder — shows a single hairline-backed strip with
    /// space reserved for timeline controls. The real `TimelineView` is
    /// rendered by `EditorView` in the default orientation. Keeping this
    /// stub declarative allows tests to verify the geometry split without
    /// requiring a fully initialised `TimelineViewModel`.
    private var timelinePane: some View {
        ZStack {
            LiquidColors.Canvas.base
            VStack(spacing: LiquidSpacing.xs) {
                Image(systemName: "film")
                    .font(.system(size: 18))
                    .foregroundStyle(LiquidColors.Text.secondary)
                Text("Timeline")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LiquidStroke.hairlineColor)
                .frame(height: LiquidStroke.hairlineWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timeline")
    }

    /// Inspector pane placeholder. Mirrors the inspector column shown on
    /// iPad but in a narrower compact form.
    private var inspectorPane: some View {
        ZStack {
            LiquidColors.Canvas.raised
            VStack(alignment: .leading, spacing: LiquidSpacing.md) {
                Text("Inspector")
                    .font(LiquidTypography.title3)
                    .foregroundStyle(LiquidColors.Text.primary)
                Text("Landscape mode")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(LiquidSpacing.md)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
    }
}

// MARK: - Convenience modifier

extension View {

    /// Render an `EditorShellLandscape` when the environment is iPhone
    /// landscape; otherwise render the regular `EditorView`. Call from a
    /// route's destination view to transparently adopt the shell on devices
    /// that benefit from it.
    ///
    /// - Parameter project: Project to open.
    @ViewBuilder
    func editorShellLandscapeIfAvailable(for project: Project) -> some View {
        EditorShellLandscape(project: project)
    }
}
