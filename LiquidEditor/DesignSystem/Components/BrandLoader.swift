// BrandLoader.swift
// LiquidEditor
//
// Pulsing amber brand loader for the 2026-04-18 premium UI redesign.
// Replaces the generic ProgressView() in the editor shell.

import SwiftUI

struct BrandLoader: View {

    var caption: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: LiquidSpacing.sm) {
            Image(systemName: "film.stack.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(LiquidColors.Accent.amber)
                .opacity(reduceMotion ? 1.0 : (isPulsing ? 1.0 : 0.5))
                .animation(
                    reduceMotion ? nil :
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: isPulsing
                )
            if let caption {
                Text(caption)
                    .font(LiquidTypography.Caption.font)
                    .foregroundStyle(LiquidColors.Text.secondary)
            }
        }
        .onAppear { isPulsing = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption ?? "Loading")
    }
}
