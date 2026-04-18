// TransportButton.swift
// LiquidEditor
//
// Play/pause-style circle for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Kind drives the visual weight of the button:
/// - `.primary`: 56pt diameter, amber fill, tapPrimary haptic.
///   For play/pause.
/// - `.secondary`: 40pt diameter, no fill, tapSecondary haptic.
///   For undo/redo/skip.
enum TransportButtonKind {
    case primary
    case secondary
}

struct TransportButton: View {

    let systemName: String
    let kind: TransportButtonKind
    var accessibilityLabel: String?
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: {
            HapticService.shared.play(kind == .primary ? .tapPrimary : .tapSecondary)
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: kind == .primary ? 22 : 16, weight: .medium))
                .foregroundStyle(
                    kind == .primary ? LiquidColors.Text.onAccent : LiquidColors.Text.primary
                )
                .frame(width: kind == .primary ? 56 : 40,
                       height: kind == .primary ? 56 : 40)
                .background(
                    kind == .primary
                    ? AnyShapeStyle(LiquidColors.Accent.amber)
                    : AnyShapeStyle(Color.clear),
                    in: Circle()
                )
                .overlay(
                    Circle().stroke(
                        kind == .primary ? Color.clear : LiquidStroke.hairlineColor,
                        lineWidth: LiquidStroke.hairlineWidth
                    )
                )
                .scaleEffect(pressed ? 0.94 : 1)
                .animation(.liquid(LiquidMotion.snap, reduceMotion: reduceMotion), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}
