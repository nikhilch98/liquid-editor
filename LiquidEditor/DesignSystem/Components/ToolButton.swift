// ToolButton.swift
// LiquidEditor
//
// Two-row toolbar cell for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Vertical [glyph, caption] inside a rounded-12 capsule-ish hit area.
/// Width + height come from the FormFactor env (48x72 / 52x80).
struct ToolButton: View {

    let systemName: String
    let caption: String
    var isActive: Bool = false
    var action: () -> Void

    @Environment(\.formFactor) private var formFactor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: {
            HapticService.shared.play(.selection)
            action()
        }) {
            VStack(spacing: LiquidSpacing.xs) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .medium))
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(
                isActive ? LiquidColors.Accent.amber : LiquidColors.Text.secondary
            )
            .frame(width: formFactor.toolButtonWidth,
                   height: formFactor.toolButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(pressed ? Color.white.opacity(0.04) : .clear)
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.liquid(LiquidMotion.snap, reduceMotion: reduceMotion), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        .accessibilityLabel(caption)
    }
}
