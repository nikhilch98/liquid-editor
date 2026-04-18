// LiquidStroke.swift
// LiquidEditor
//
// Stroke width + color tokens for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Stroke widths and styles. Pair with the color tokens from
/// ``LiquidColors``.
enum LiquidStroke {
    /// Hairline divider width.
    static let hairlineWidth: CGFloat = 0.5
    /// Active / selected stroke width.
    static let activeWidth: CGFloat = 1.5
    /// Amber glow halo radius used alongside the active stroke.
    static let activeGlowRadius: CGFloat = 6

    /// Subtle hairline divider color (`white.opacity(0.08)`).
    static let hairlineColor = Color.white.opacity(0.08)
}
