// Toast.swift
// LiquidEditor
//
// Ephemeral notification capsule for the 2026-04-18 premium UI redesign.

import SwiftUI

enum ToastKind {
    case success
    case info
    case warning
}

/// Glass capsule anchored to the top safe area. Callers drive appearance
/// + dismissal via a binding — typical pattern is a 2s auto-hide task
/// that toggles the binding.
struct Toast: View {

    let message: String
    var kind: ToastKind = .info

    var body: some View {
        HStack(spacing: LiquidSpacing.sm) {
            Image(systemName: systemIcon)
                .foregroundStyle(iconColor)
            Text(message)
                .font(LiquidTypography.Body.font)
                .foregroundStyle(LiquidColors.Text.primary)
        }
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.vertical, LiquidSpacing.sm)
        .frame(height: 48)
        .background(LiquidMaterials.chrome, in: Capsule())
        .overlay(
            Capsule().stroke(LiquidStroke.hairlineColor, lineWidth: LiquidStroke.hairlineWidth)
        )
        .elevation(LiquidElevation.floatMd)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var systemIcon: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .info:    "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .success: LiquidColors.Accent.amber
        case .info:    LiquidColors.Text.secondary
        case .warning: LiquidColors.Accent.destructive
        }
    }
}
