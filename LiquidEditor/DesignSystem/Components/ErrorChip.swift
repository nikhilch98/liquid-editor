// ErrorChip.swift
// LiquidEditor
//
// Inline error banner for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Glass capsule with a warning triangle + short error message.
/// Callers embed it into their view and drive dismiss themselves
/// (usually via auto-timer or user gesture).
struct ErrorChip: View {

    let message: String

    var body: some View {
        HStack(spacing: LiquidSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(LiquidColors.Accent.destructive)
            Text(message)
                .font(LiquidTypography.Caption.font)
                .foregroundStyle(LiquidColors.Text.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.sm)
        .background(LiquidMaterials.chrome, in: Capsule())
        .overlay(
            Capsule().stroke(LiquidStroke.hairlineColor, lineWidth: LiquidStroke.hairlineWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}
