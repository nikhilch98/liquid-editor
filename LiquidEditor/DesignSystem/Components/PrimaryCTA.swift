// PrimaryCTA.swift
// LiquidEditor
//
// Amber capsule primary button for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Primary call-to-action capsule: amber fill, dark text, min-width 96,
/// height driven by FormFactor. Used for Export, Import Media, Apply.
struct PrimaryCTA: View {

    let title: String
    var leadingSystemName: String? = nil
    var isEnabled: Bool = true
    var action: () -> Void

    @Environment(\.formFactor) private var formFactor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: {
            HapticService.shared.play(.tapPrimary)
            action()
        }) {
            HStack(spacing: LiquidSpacing.xs) {
                if let leadingSystemName {
                    Image(systemName: leadingSystemName)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title).font(LiquidTypography.Title.font)
            }
            .foregroundStyle(LiquidColors.Text.onAccent)
            .padding(.horizontal, LiquidSpacing.lg)
            .frame(minWidth: 96)
            .frame(height: formFactor.primaryCTAHeight)
            .background(LiquidColors.Accent.amber, in: Capsule())
            .opacity(isEnabled ? 1.0 : 0.4)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.liquid(LiquidMotion.snap, reduceMotion: reduceMotion), value: pressed)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        .accessibilityLabel(title)
    }
}
