// PlayheadWithChip.swift
// LiquidEditor
//
// Playhead line + time chip composite. Replaces PlayheadView's current
// thin-line indicator for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Vertical 2pt amber line with a top-mounted amber time chip. The
/// caller positions this inside the timeline; this view only draws
/// the line+chip.
struct PlayheadWithChip: View {

    let timeText: String
    var isScrubbing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            timeChip
                .scaleEffect(isScrubbing ? 1.08 : 1.0)
                .animation(.liquid(LiquidMotion.snap, reduceMotion: reduceMotion),
                           value: isScrubbing)
            verticalLine
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playhead")
        .accessibilityValue(timeText)
    }

    private var timeChip: some View {
        Text(timeText)
            .font(LiquidTypography.MonoLarge.font)
            .foregroundStyle(LiquidColors.Text.onAccent)
            .padding(.horizontal, LiquidSpacing.sm)
            .frame(height: 30)
            .background(LiquidColors.Accent.amber, in: Capsule())
            .overlay(
                Capsule().stroke(
                    LiquidStroke.hairlineColor, lineWidth: LiquidStroke.hairlineWidth
                )
            )
            .shadow(
                color: isScrubbing
                    ? LiquidColors.Accent.amberGlow
                    : .clear,
                radius: isScrubbing ? 8 : 0
            )
    }

    private var verticalLine: some View {
        Rectangle()
            .fill(LiquidColors.Accent.amber)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
    }
}
