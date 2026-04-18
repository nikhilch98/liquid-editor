// EmptyStateCard.swift
// LiquidEditor
//
// Centered empty-state card for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Rounded-16 floating glass card with a glyph, title, body, and a CTA.
/// Used by the empty editor, empty library, empty search.
///
/// The CTA is optional — pass nil to render the card as information
/// only. For views that need their own PhotosPicker wrapper, pass a
/// `AnyView(PhotosPicker { ... })` via the ``custom`` initializer.
struct EmptyStateCard: View {

    let glyph: String
    let title: String
    let bodyText: String
    let ctaTitle: String?
    let action: (() -> Void)?

    init(
        glyph: String,
        title: String,
        body: String,
        ctaTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.glyph = glyph
        self.title = title
        self.bodyText = body
        self.ctaTitle = ctaTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: LiquidSpacing.lg) {
            Image(systemName: glyph)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(LiquidColors.Accent.amber)
                .accessibilityHidden(true)
            Text(title)
                .font(LiquidTypography.Title.font)
                .foregroundStyle(LiquidColors.Text.primary)
            Text(bodyText)
                .font(LiquidTypography.Body.font)
                .foregroundStyle(LiquidColors.Text.secondary)
                .multilineTextAlignment(.center)
            if let ctaTitle, let action {
                PrimaryCTA(title: ctaTitle, leadingSystemName: "plus", action: action)
            }
        }
        .padding(LiquidSpacing.xxl)
        .frame(maxWidth: 320)
        .background(
            LiquidMaterials.float,
            in: RoundedRectangle(cornerRadius: LiquidRadius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiquidRadius.lg, style: .continuous)
                .stroke(LiquidStroke.hairlineColor, lineWidth: LiquidStroke.hairlineWidth)
        )
        .elevation(LiquidElevation.floatMd)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(bodyText)")
    }
}
