// PitchPanel.swift
// LiquidEditor
//
// TD8-6: Pitch shift parametric panel hosted in ContextSubPanel.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.
//
// Layout:
// - Single horizontal slider, range −12..+12 semitones, step 1,
//   center-detent at 0 (`±0 st`).
// - Value readout formatted as "+3 st" / "-2 st".
// - Reset button sets pitch back to 0.
// - "Preserve formants" toggle (parent decides how to wire this up
//   to the audio effects engine).

import SwiftUI

// MARK: - PitchSettings

/// Parametric state for the pitch-shift panel.
struct PitchSettings: Equatable, Sendable {
    /// Semitone offset, clamped to ±12 by the panel.
    var semitones: Int
    /// When true, formants are preserved (prevents the "chipmunk" effect).
    var preserveFormants: Bool

    /// Neutral default — no shift, formants preserved.
    static let neutral = PitchSettings(semitones: 0, preserveFormants: true)
}

// MARK: - PitchPanel

/// Pitch-shift panel hosted inside ``ContextSubPanel``.
@MainActor
struct PitchPanel: View {

    // MARK: - Inputs

    @Binding var settings: PitchSettings
    let onDismiss: () -> Void

    // MARK: - Constants

    private static let semitoneRange: ClosedRange<Double> = -12...12

    // MARK: - Body

    var body: some View {
        ContextSubPanel(title: "Pitch", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 8) {
                readoutRow
                semitoneSlider
                Toggle("Preserve formants", isOn: $settings.preserveFormants)
                    .font(.caption2)
                    .tint(LiquidColors.Accent.amber)
            }
        }
    }

    // MARK: - Readout + reset

    private var readoutRow: some View {
        HStack {
            Text(readout(for: settings.semitones))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(LiquidColors.Accent.amber)
            Spacer()
            Button {
                settings.semitones = 0
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(LiquidColors.Canvas.elev)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset pitch to zero semitones")
            .disabled(settings.semitones == 0)
            .opacity(settings.semitones == 0 ? 0.4 : 1)
        }
    }

    // MARK: - Slider

    private var semitoneSlider: some View {
        Slider(
            value: Binding<Double>(
                get: { Double(settings.semitones) },
                set: { new in
                    // Step = 1 semitone; rounding + clamp gives the detent at 0.
                    let clamped = min(12.0, max(-12.0, new))
                    settings.semitones = Int(clamped.rounded())
                }
            ),
            in: Self.semitoneRange,
            step: 1
        )
        .tint(LiquidColors.Accent.amber)
        .accessibilityLabel("Pitch shift")
        .accessibilityValue(readout(for: settings.semitones))
    }

    // MARK: - Formatting

    /// Readable label like "+3 st" / "-2 st" / "±0 st".
    private func readout(for semitones: Int) -> String {
        if semitones == 0 { return "\u{00B10} st" } // ±0 st
        let sign = semitones > 0 ? "+" : "\u{2212}" // Unicode minus
        return "\(sign)\(abs(semitones)) st"
    }
}

// MARK: - Previews

#Preview("Pitch panel") {
    PitchPanelPreviewHost()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColors.Canvas.base)
        .preferredColorScheme(.dark)
}

private struct PitchPanelPreviewHost: View {
    @State private var settings: PitchSettings = .neutral
    var body: some View {
        VStack {
            Spacer()
            PitchPanel(settings: $settings, onDismiss: { })
                .padding(.horizontal, 20)
        }
    }
}
