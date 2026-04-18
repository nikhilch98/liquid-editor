// LiquidElevation.swift
// LiquidEditor
//
// Shadow tokens for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Shadow tokens to emulate depth for floating surfaces. Use sparingly —
/// material alone sells most of the depth on iOS 26.
enum LiquidElevation {
    /// Small floating shadow: 4pt blur, 8% alpha.
    static let floatSm = Shadow(radius: 4, alpha: 0.08, y: 2)
    /// Medium floating shadow: 12pt blur, 14% alpha.
    static let floatMd = Shadow(radius: 12, alpha: 0.14, y: 4)
    /// Large floating shadow: 24pt blur, 22% alpha.
    static let floatLg = Shadow(radius: 24, alpha: 0.22, y: 8)

    struct Shadow {
        let radius: CGFloat
        let alpha: Double
        let y: CGFloat
        let color: Color = .black
    }
}

extension View {
    /// Apply a `LiquidElevation.Shadow` token to this view.
    func elevation(_ shadow: LiquidElevation.Shadow) -> some View {
        self.shadow(
            color: shadow.color.opacity(shadow.alpha),
            radius: shadow.radius,
            x: 0,
            y: shadow.y
        )
    }
}
