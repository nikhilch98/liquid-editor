// IncreaseContrastAware.swift
// LiquidEditor
//
// Increase Contrast accessibility fallbacks for stroke / separator
// colors. When "Increase Contrast" (reported by SwiftUI as
// `\.colorSchemeContrast == .increased`) or "Differentiate Without
// Color" is active, strokes swap from a hairline color to a bumped,
// higher-contrast color so borders remain visible for low-vision
// users.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §10.6 (A10-6)

import SwiftUI

// MARK: - ContrastAwareStrokeModifier

/// ViewModifier that overlays a rounded-rect stroke whose color
/// switches from a hairline to a bumped contrast color based on
/// the user's accessibility preferences.
private struct ContrastAwareStrokeModifier: ViewModifier {

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let hairline: Color
    let bumped: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    private var shouldBump: Bool {
        colorSchemeContrast == .increased || differentiateWithoutColor
    }

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(shouldBump ? bumped : hairline, lineWidth: lineWidth)
            )
    }
}

// MARK: - View Extension

extension View {

    /// Overlay a stroke that adapts its color to the user's contrast
    /// preferences.
    ///
    /// When Increase Contrast is enabled (`\.colorSchemeContrast ==
    /// .increased`) or Differentiate Without Color is on, the
    /// `bumped` color is used so borders remain perceptible. In all
    /// other cases the `hairline` color is used.
    ///
    /// - Parameters:
    ///   - hairline: Stroke color used under normal contrast.
    ///   - bumped: Stroke color used under increased contrast.
    ///   - cornerRadius: Corner radius of the stroke shape. Defaults to `LiquidSpacing.cornerMedium`.
    ///   - lineWidth: Stroke width. Defaults to `0.5`.
    /// - Returns: A view with a contrast-aware stroke overlay.
    func contrastAwareStroke(
        hairline: Color,
        bumped: Color,
        cornerRadius: CGFloat = LiquidSpacing.cornerMedium,
        lineWidth: CGFloat = 0.5
    ) -> some View {
        modifier(ContrastAwareStrokeModifier(
            hairline: hairline,
            bumped: bumped,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth
        ))
    }
}
