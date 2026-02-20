// GlassEffect.swift
// LiquidEditor
//
// SwiftUI ViewModifier for iOS 26 Liquid Glass effect.
// Provides frosted glass blur with configurable material thickness,
// rounded corners, subtle border, and shadow.

import SwiftUI

// MARK: - GlassStyle

/// Intensity style for the Liquid Glass effect.
///
/// Maps to SwiftUI `Material` variants for native system integration.
enum GlassStyle: Sendable {
    /// Ultra-thin glass with heavy transparency.
    case thin

    /// Standard glass effect for most UI surfaces.
    case regular

    /// Thicker glass with less transparency.
    case thick

    /// Nearly opaque glass for prominent surfaces.
    case ultraThick
}

// MARK: - GlassEffectModifier

/// ViewModifier that applies an iOS 26 Liquid Glass effect.
///
/// Combines a system material background with rounded corners,
/// a subtle border, and a soft shadow to create the frosted glass
/// appearance characteristic of iOS 26's Liquid Glass design language.
///
/// Usage via the `.glassEffect()` View extension:
/// ```swift
/// VStack {
///     Text("Timeline Controls")
/// }
/// .glassEffect()
///
/// HStack {
///     Button("Export") { ... }
/// }
/// .glassEffect(style: .thick, cornerRadius: 20)
/// ```
struct GlassEffectModifier: ViewModifier {

    /// Glass material thickness.
    let style: GlassStyle

    /// Corner radius for the glass surface.
    let cornerRadius: CGFloat

    /// Whether to show the subtle border.
    let showBorder: Bool

    /// Whether to show the shadow.
    let showShadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        showBorder ? LiquidColors.glassBorder : .clear,
                        lineWidth: 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: showShadow ? .black.opacity(0.1) : .clear,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }

    // MARK: - Private Helpers

    /// Maps `GlassStyle` to the corresponding SwiftUI `Material`.
    private var material: Material {
        switch style {
        case .thin:
            .ultraThinMaterial
        case .regular:
            .regularMaterial
        case .thick:
            .thickMaterial
        case .ultraThick:
            .ultraThickMaterial
        }
    }

    /// Shadow radius based on glass style.
    private var shadowRadius: CGFloat {
        switch style {
        case .thin:
            4
        case .regular:
            8
        case .thick:
            12
        case .ultraThick:
            16
        }
    }

    /// Shadow Y offset based on glass style.
    private var shadowY: CGFloat {
        switch style {
        case .thin:
            2
        case .regular:
            4
        case .thick:
            6
        case .ultraThick:
            8
        }
    }
}

// MARK: - View Extension

extension View {

    /// Apply an iOS 26 Liquid Glass effect to this view.
    ///
    /// Adds a frosted glass material background with rounded corners,
    /// a subtle border, and a soft shadow.
    ///
    /// - Parameters:
    ///   - style: Glass material thickness (default: `.regular`).
    ///   - cornerRadius: Corner radius for the glass surface (default: 20).
    ///   - showBorder: Whether to show the subtle glass border (default: true).
    ///   - showShadow: Whether to show the drop shadow (default: true).
    /// - Returns: The modified view with the glass effect applied.
    func glassEffect(
        style: GlassStyle = .regular,
        cornerRadius: CGFloat = LiquidSpacing.cornerXLarge,
        showBorder: Bool = true,
        showShadow: Bool = true
    ) -> some View {
        modifier(GlassEffectModifier(
            style: style,
            cornerRadius: cornerRadius,
            showBorder: showBorder,
            showShadow: showShadow
        ))
    }
}
