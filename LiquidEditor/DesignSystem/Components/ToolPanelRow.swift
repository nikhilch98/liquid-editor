// ToolPanelRow.swift
// LiquidEditor
//
// Parameter row for inline tool panels and sheet bodies.
// Part of the 2026-04-18 premium UI redesign.

import SwiftUI

/// One labelled parameter row: `[label, spacer, value]` on top, the
/// caller-supplied control below.
struct ToolPanelRow: View {

    let label: String
    let value: String
    let control: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(LiquidTypography.Body.font)
                    .foregroundStyle(LiquidColors.Text.primary)
                Spacer(minLength: LiquidSpacing.sm)
                Text(value)
                    .font(LiquidTypography.Mono.font)
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .monospacedDigit()
            }
            control
        }
        .padding(.vertical, LiquidSpacing.sm)
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label), \(value)")
    }
}
