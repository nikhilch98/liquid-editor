// TabBarItem.swift
// LiquidEditor
//
// Bottom tab bar cell for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Icon-only tab cell with a 4pt amber pill beneath when active.
struct TabBarItem: View {

    let systemName: String
    /// Spoken label (icons are unlabelled visually, but VoiceOver needs text).
    let label: String
    var isActive: Bool = false
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            HapticService.shared.play(.selection)
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(
                        isActive ? LiquidColors.Accent.amber : LiquidColors.Text.secondary
                    )
                Capsule()
                    .fill(LiquidColors.Accent.amber)
                    .frame(width: isActive ? 16 : 0, height: 3)
                    .animation(.liquid(LiquidMotion.bounce, reduceMotion: reduceMotion),
                               value: isActive)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
