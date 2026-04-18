// IconButton.swift
// LiquidEditor
//
// Bare-glyph tap target for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Minimum-chrome icon button. 20pt SF Symbol glyph inside a 44x44
/// tappable rectangle. Used for the close button, more menu, settings,
/// fullscreen toggle.
struct IconButton: View {

    let systemName: String
    let accessibilityLabel: String
    var tint: Color = LiquidColors.Text.primary
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: {
            HapticService.shared.play(.tapSecondary)
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .scaleEffect(pressed ? 0.94 : 1)
                .animation(.liquid(LiquidMotion.snap, reduceMotion: reduceMotion), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        .accessibilityLabel(accessibilityLabel)
    }
}
