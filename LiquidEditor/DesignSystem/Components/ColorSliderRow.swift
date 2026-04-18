// ColorSliderRow.swift
// LiquidEditor
//
// TD8-12: Reusable dual-slider row for the Color tab's parametric
// controls (Temp / Tint / Exposure / Contrast / Highlights / Lows /
// Saturation / Vibrance).
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.
//
// Layout per row:
//
//   ┌──────────┬─────────────────────────────┬────────────┐
//   │  Label   │ ────────◎────────────────── │  value     │
//   └──────────┴─────────────────────────────┴────────────┘
//
// The `ColorSliderRow` is purposefully minimal — it only knows how to
// render a label, a slider, and a numeric readout. Ranges, units, and
// formatting come from static factories so callers can spell out
// `ColorSliderRow.exposure($settings.exposure)` without repeating
// configuration.

import SwiftUI

// MARK: - ColorSliderRow

/// Generic labeled row used by the Color tab's parameter sheet.
struct ColorSliderRow: View {

    // MARK: - Inputs

    /// Left-hand label, e.g. "Temp".
    let label: String
    /// Clamped range for the slider.
    let range: ClosedRange<Double>
    /// Optional step — `nil` means continuous.
    let step: Double?
    /// `printf`-style format passed to `String(format:)`.
    let format: String
    /// Value to center-snap onto (e.g. 0 for bipolar sliders).
    let centerDetent: Double?
    /// Parent-owned parameter binding.
    @Binding var value: Double

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiquidColors.Text.secondary)
                .frame(width: 72, alignment: .leading)

            slider
                .tint(LiquidColors.Accent.amber)

            Text(formattedValue)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LiquidColors.Text.secondary)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(formattedValue)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var slider: some View {
        if let step {
            Slider(value: binding, in: range, step: step)
        } else {
            Slider(value: binding, in: range)
        }
    }

    // MARK: - Helpers

    /// Applies the center detent (if any) on top of the raw binding.
    private var binding: Binding<Double> {
        guard let center = centerDetent else { return $value }
        return Binding<Double>(
            get: { value },
            set: { new in
                let tolerance = (range.upperBound - range.lowerBound) * 0.01
                if abs(new - center) < tolerance {
                    value = center
                } else {
                    value = new
                }
            }
        )
    }

    private var formattedValue: String {
        String(format: format, value)
    }
}

// MARK: - Static factories (TD8-12 prebuilt rows)

extension ColorSliderRow {

    /// Color temperature: bipolar −100 (cooler) to +100 (warmer).
    static func temperature(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Temp",
            range: -100...100,
            step: nil,
            format: "%+.0f",
            centerDetent: 0,
            value: value
        )
    }

    /// Tint: bipolar −100 (green) to +100 (magenta).
    static func tint(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Tint",
            range: -100...100,
            step: nil,
            format: "%+.0f",
            centerDetent: 0,
            value: value
        )
    }

    /// Exposure: ±2 stops.
    static func exposure(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Exposure",
            range: -2...2,
            step: nil,
            format: "%+.2f EV",
            centerDetent: 0,
            value: value
        )
    }

    /// Contrast: bipolar −100..+100.
    static func contrast(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Contrast",
            range: -100...100,
            step: nil,
            format: "%+.0f",
            centerDetent: 0,
            value: value
        )
    }

    /// Highlights (top-range): −100..+100, center detent at 0.
    static func highlights(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Highlights",
            range: -100...100,
            step: nil,
            format: "%+.0f",
            centerDetent: 0,
            value: value
        )
    }

    /// Lows / shadows: −100..+100, center detent at 0.
    static func lows(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Lows",
            range: -100...100,
            step: nil,
            format: "%+.0f",
            centerDetent: 0,
            value: value
        )
    }

    /// Saturation: 0..200 (%), 100 is neutral, detent snaps to 100.
    static func saturation(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Saturation",
            range: 0...200,
            step: nil,
            format: "%.0f%%",
            centerDetent: 100,
            value: value
        )
    }

    /// Vibrance: bipolar −100..+100, detent at 0.
    static func vibrance(_ value: Binding<Double>) -> ColorSliderRow {
        ColorSliderRow(
            label: "Vibrance",
            range: -100...100,
            step: nil,
            format: "%+.0f",
            centerDetent: 0,
            value: value
        )
    }
}

// MARK: - Previews

#Preview("Color slider rows") {
    ColorSliderRowPreviewHost()
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(LiquidColors.Canvas.raised)
        .preferredColorScheme(.dark)
}

private struct ColorSliderRowPreviewHost: View {
    @State private var temp: Double = 0
    @State private var tint: Double = 0
    @State private var exposure: Double = 0
    @State private var contrast: Double = 0
    @State private var highlights: Double = 0
    @State private var lows: Double = 0
    @State private var saturation: Double = 100
    @State private var vibrance: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            ColorSliderRow.temperature($temp)
            ColorSliderRow.tint($tint)
            ColorSliderRow.exposure($exposure)
            ColorSliderRow.contrast($contrast)
            ColorSliderRow.highlights($highlights)
            ColorSliderRow.lows($lows)
            ColorSliderRow.saturation($saturation)
            ColorSliderRow.vibrance($vibrance)
        }
    }
}
