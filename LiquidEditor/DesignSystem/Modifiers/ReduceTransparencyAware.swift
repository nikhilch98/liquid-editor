// ReduceTransparencyAware.swift
// LiquidEditor
//
// Reduce Transparency accessibility fallbacks for Liquid Glass surfaces.
// When "Reduce Transparency" is enabled, materials are replaced with an
// opaque surface so legibility remains high for users who find blur
// backgrounds difficult to read against.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §10.6 (A10-5)

import SwiftUI

// MARK: - GlassWithFallbackModifier

/// ViewModifier that applies a glass material background normally
/// and an opaque surface fill when Reduce Transparency is active.
private struct GlassWithFallbackModifier: ViewModifier {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Corner radius applied to the clip shape backing the fill.
    let cornerRadius: CGFloat

    /// Underlying material used when transparency is permitted.
    let material: Material

    /// Opaque color used when Reduce Transparency is active.
    let opaqueFill: Color

    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(opaqueFill)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(material)
                    }
                }
            )
    }
}

// MARK: - View Extension

extension View {

    /// Apply a Liquid Glass material background with a Reduce
    /// Transparency fallback.
    ///
    /// When the user has enabled Reduce Transparency in Accessibility
    /// settings, the material is replaced with an opaque surface color
    /// drawn from the design system (defaulting to
    /// `LiquidColors.surface`, which is a raised secondary grouped
    /// background in both light and dark mode).
    ///
    /// - Parameters:
    ///   - material: The glass material to use normally. Defaults to `.ultraThinMaterial`.
    ///   - cornerRadius: Corner radius for the background shape.
    ///   - opaqueFill: Fallback opaque fill used when transparency is reduced.
    /// - Returns: A view whose background adapts to the transparency preference.
    func glassWithFallback(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = LiquidSpacing.cornerXLarge,
        opaqueFill: Color = LiquidColors.surface
    ) -> some View {
        modifier(GlassWithFallbackModifier(
            cornerRadius: cornerRadius,
            material: material,
            opaqueFill: opaqueFill
        ))
    }
}
