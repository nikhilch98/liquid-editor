// PermissionPrimerSheet.swift
// LiquidEditor
//
// P1-15: Generic permission-primer sheet per spec §9.13.
//
// Layout: hero glyph + title + 2-sentence rationale + amber grant
// button + tertiary "Not now" link.
//
// Used by: Photos, Microphone, Camera, Notifications primers (F6-9).

import SwiftUI

// MARK: - PermissionPrimerSheet

struct PermissionPrimerSheet: View {

    // MARK: - Inputs

    let systemImage: String
    let title: String
    let rationale: String
    let grantLabel: String
    let onGrant: () -> Void
    let onNotNow: () -> Void

    init(
        systemImage: String,
        title: String,
        rationale: String,
        grantLabel: String = "Continue",
        onGrant: @escaping () -> Void,
        onNotNow: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.rationale = rationale
        self.grantLabel = grantLabel
        self.onGrant = onGrant
        self.onNotNow = onNotNow
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            heroGlyph
            VStack(spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LiquidColors.Text.primary)
                    .multilineTextAlignment(.center)
                Text(rationale)
                    .font(.callout)
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            VStack(spacing: 10) {
                Button(action: onGrant) {
                    Text(grantLabel)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LiquidColors.Text.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(LiquidColors.Accent.amber)
                        )
                }
                .buttonStyle(.plain)
                Button("Not now", action: onNotNow)
                    .font(.callout)
                    .foregroundStyle(LiquidColors.Text.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(LiquidColors.Canvas.base)
        .accessibilityElement(children: .combine)
    }

    private var heroGlyph: some View {
        Image(systemName: systemImage)
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(LiquidColors.Accent.amber)
            .frame(width: 80, height: 80)
            .background(
                Circle().fill(LiquidColors.Accent.amberGlow)
            )
            .overlay(
                Circle().stroke(LiquidColors.Accent.amber.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Preview

#Preview("Photos primer") {
    PermissionPrimerSheet(
        systemImage: "photo.on.rectangle.angled",
        title: "Allow Photos access",
        rationale: "Liquid Editor needs read access so you can import videos and photos into your projects. We never share or upload your library.",
        grantLabel: "Grant access",
        onGrant: { },
        onNotNow: { }
    )
    .preferredColorScheme(.dark)
}
