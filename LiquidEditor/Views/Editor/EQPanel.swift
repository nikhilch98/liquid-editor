// EQPanel.swift
// LiquidEditor
//
// TD8-5: Three-band EQ parametric panel hosted in ContextSubPanel.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.
//
// Layout:
// - Row 1: 5 preset chips (Flat / Vocal / Bass Boost / Bright / Warm).
// - Row 2: 3 vertical sliders (Low / Mid / High), range ±12 dB,
//          center detent at 0 dB, value readout under each band.
//
// Parent owns an ``EQSettings`` binding so the panel is fully
// stateless and re-selecting a preset is undoable at the ViewModel
// layer.

import SwiftUI

// MARK: - EQSettings

/// Parametric state for the 3-band EQ panel.
///
/// Values are in decibels, clamped to `±12 dB` by the panel itself.
struct EQSettings: Equatable, Sendable {
    /// Low-shelf gain in dB.
    var lowGain: Double
    /// Mid-peak gain in dB.
    var midGain: Double
    /// High-shelf gain in dB.
    var highGain: Double

    /// Factory identity preset (all bands flat).
    static let flat = EQSettings(lowGain: 0, midGain: 0, highGain: 0)
    /// Presence bump, minor low cut — good for dialogue.
    static let vocal = EQSettings(lowGain: -2, midGain: 4, highGain: 3)
    /// Pushes sub-bass and rolls off the highs.
    static let bassBoost = EQSettings(lowGain: 8, midGain: 0, highGain: -2)
    /// Airy, extended top end.
    static let bright = EQSettings(lowGain: -1, midGain: 1, highGain: 6)
    /// Fuller lows, tamed highs.
    static let warm = EQSettings(lowGain: 4, midGain: 1, highGain: -3)
}

// MARK: - EQPanel

/// Three-band EQ panel hosted inside ``ContextSubPanel``.
@MainActor
struct EQPanel: View {

    // MARK: - Inputs

    @Binding var settings: EQSettings
    let onDismiss: () -> Void

    // MARK: - Constants

    private static let gainRange: ClosedRange<Double> = -12...12
    private static let presets: [(name: String, value: EQSettings)] = [
        ("Flat", .flat),
        ("Vocal", .vocal),
        ("Bass Boost", .bassBoost),
        ("Bright", .bright),
        ("Warm", .warm),
    ]

    // MARK: - Body

    var body: some View {
        ContextSubPanel(title: "EQ", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 10) {
                presetChips
                bandSliders
            }
        }
    }

    // MARK: - Presets row

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Self.presets, id: \.name) { preset in
                    presetChip(name: preset.name, value: preset.value)
                }
            }
        }
    }

    private func presetChip(name: String, value: EQSettings) -> some View {
        let isSelected = settings == value
        return Button {
            settings = value
        } label: {
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(
                    isSelected ? LiquidColors.Accent.amber : LiquidColors.Text.secondary
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        isSelected
                            ? LiquidColors.Accent.amberGlow
                            : LiquidColors.Canvas.elev
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) EQ preset")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Sliders row

    private var bandSliders: some View {
        HStack(alignment: .top, spacing: 12) {
            band(label: "Low", value: $settings.lowGain)
            band(label: "Mid", value: $settings.midGain)
            band(label: "High", value: $settings.highGain)
        }
        .frame(height: 140)
    }

    private func band(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiquidColors.Text.secondary)
            verticalSlider(value: value)
                .frame(maxHeight: .infinity)
            Text(String(format: "%+.1f dB", value.wrappedValue))
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.Text.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) band")
        .accessibilityValue(String(format: "%+.1f decibels", value.wrappedValue))
    }

    /// Vertical slider built by rotating a native ``Slider`` 90 degrees.
    /// Adds a center detent at 0 dB via an inline snapping binding.
    private func verticalSlider(value: Binding<Double>) -> some View {
        let snapped = Binding<Double>(
            get: { value.wrappedValue },
            set: { new in
                let tolerance = 0.8
                value.wrappedValue = abs(new - 0) < tolerance ? 0 : new
            }
        )
        return Slider(value: snapped, in: Self.gainRange)
            .tint(LiquidColors.Accent.amber)
            .rotationEffect(.degrees(-90))
            .frame(width: 100)
            .fixedSize()
            .frame(width: 30)
    }
}

// MARK: - Previews

#Preview("EQ panel") {
    StatefulPreviewWrapper(EQSettings.flat) { binding in
        VStack {
            Spacer()
            EQPanel(settings: binding, onDismiss: { })
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColors.Canvas.base)
        .preferredColorScheme(.dark)
    }
}

/// Minimal preview helper so #Preview can own @State for a binding.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
