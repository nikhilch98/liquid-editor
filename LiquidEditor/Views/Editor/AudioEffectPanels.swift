// AudioEffectPanels.swift
// LiquidEditor
//
// C5-22..26: Audio effect sub-panels per spec §7.18.
//
// Each panel is a stateless SwiftUI view that binds to a parameter
// struct; consumers (Audio tab tool wiring, T3-3) own the binding
// state and apply changes through AudioEffectsEngine.
//
// All panels share the ContextSubPanel container for a consistent
// look and dismiss behavior.

import SwiftUI

// MARK: - C5-22 Reverb

struct ReverbPanel: View {
    @Binding var preset: String
    @Binding var size: Double
    @Binding var decay: Double
    @Binding var preDelay: Double
    @Binding var mix: Double
    @Binding var bypass: Bool
    let onDismiss: () -> Void

    private let presets = ["Room", "Hall", "Cathedral", "Plate", "Spring"]

    var body: some View {
        ContextSubPanel(title: "Reverb", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 6) {
                presetChips
                slider("Size", $size, 0...1, fmt: "%.0f%%", scale: 100)
                slider("Decay", $decay, 0...10, fmt: "%.1f s")
                slider("Pre-delay", $preDelay, 0...200, fmt: "%.0f ms")
                slider("Mix", $mix, 0...1, fmt: "%.0f%%", scale: 100)
                Toggle("Bypass", isOn: $bypass).font(.caption2).tint(LiquidColors.Accent.amber)
            }
        }
    }

    private var presetChips: some View {
        HStack(spacing: 4) {
            ForEach(presets, id: \.self) { p in
                Button { preset = p } label: {
                    Text(p)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(preset == p ? LiquidColors.Accent.amber : LiquidColors.Text.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(preset == p ? LiquidColors.Accent.amberGlow : LiquidColors.Canvas.elev))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, fmt: String, scale: Double = 1) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(LiquidColors.Text.tertiary).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range).tint(LiquidColors.Accent.amber)
            Text(String(format: fmt, value.wrappedValue * scale)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - C5-23 Delay

struct DelayPanel: View {
    @Binding var timeMs: Double
    @Binding var feedback: Double
    @Binding var mix: Double
    @Binding var syncToBeat: Bool
    @Binding var bypass: Bool
    let onDismiss: () -> Void

    var body: some View {
        ContextSubPanel(title: "Delay", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 6) {
                slider("Time", $timeMs, 1...2000, fmt: "%.0f ms")
                slider("Feedback", $feedback, 0...1, fmt: "%.0f%%", scale: 100)
                slider("Mix", $mix, 0...1, fmt: "%.0f%%", scale: 100)
                HStack {
                    Toggle("Sync to beat", isOn: $syncToBeat).font(.caption2).tint(LiquidColors.Accent.amber)
                    Spacer()
                    Toggle("Bypass", isOn: $bypass).font(.caption2).tint(LiquidColors.Accent.amber)
                }
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, fmt: String, scale: Double = 1) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(LiquidColors.Text.tertiary).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range).tint(LiquidColors.Accent.amber)
            Text(String(format: fmt, value.wrappedValue * scale)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - C5-24 Compression

struct CompressionPanel: View {
    @Binding var thresholdDB: Double
    @Binding var ratio: Double
    @Binding var attackMs: Double
    @Binding var releaseMs: Double
    @Binding var makeupDB: Double
    @Binding var bypass: Bool
    let gainReductionDB: Double
    let onDismiss: () -> Void

    var body: some View {
        ContextSubPanel(title: "Compression", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 6) {
                gainReductionMeter
                slider("Threshold", $thresholdDB, -60...0, fmt: "%+.1f dB")
                slider("Ratio", $ratio, 1...20, fmt: "%.1f:1")
                slider("Attack", $attackMs, 0...500, fmt: "%.0f ms")
                slider("Release", $releaseMs, 10...2000, fmt: "%.0f ms")
                slider("Makeup", $makeupDB, 0...24, fmt: "%+.1f dB")
                Toggle("Bypass", isOn: $bypass).font(.caption2).tint(LiquidColors.Accent.amber)
            }
        }
    }

    private var gainReductionMeter: some View {
        HStack(spacing: 4) {
            Text("GR").font(.caption2).foregroundStyle(LiquidColors.Text.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LiquidColors.Canvas.elev).frame(height: 6)
                    Capsule().fill(LiquidColors.Accent.amber).frame(width: max(0, min(geo.size.width, geo.size.width * (abs(gainReductionDB) / 24))), height: 6)
                }
            }
            .frame(height: 6)
            Text(String(format: "%+.1f dB", gainReductionDB)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, fmt: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(LiquidColors.Text.tertiary).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range).tint(LiquidColors.Accent.amber)
            Text(String(format: fmt, value.wrappedValue)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - C5-25 Gate

struct GatePanel: View {
    @Binding var thresholdDB: Double
    @Binding var attackMs: Double
    @Binding var holdMs: Double
    @Binding var releaseMs: Double
    @Binding var bypass: Bool
    let onDismiss: () -> Void

    var body: some View {
        ContextSubPanel(title: "Gate", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 6) {
                slider("Threshold", $thresholdDB, -80...0, fmt: "%+.1f dB")
                slider("Attack", $attackMs, 0...500, fmt: "%.0f ms")
                slider("Hold", $holdMs, 0...2000, fmt: "%.0f ms")
                slider("Release", $releaseMs, 10...2000, fmt: "%.0f ms")
                Toggle("Bypass", isOn: $bypass).font(.caption2).tint(LiquidColors.Accent.amber)
            }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, fmt: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(LiquidColors.Text.tertiary).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range).tint(LiquidColors.Accent.amber)
            Text(String(format: fmt, value.wrappedValue)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - C5-26 Limiter

struct LimiterPanel: View {
    @Binding var ceilingDB: Double
    @Binding var autoRelease: Bool
    @Binding var bypass: Bool
    let outputPeakDB: Double
    let onDismiss: () -> Void

    var body: some View {
        ContextSubPanel(title: "Limiter", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 6) {
                outputMeter
                HStack(spacing: 6) {
                    Text("Ceiling").font(.caption2).foregroundStyle(LiquidColors.Text.tertiary).frame(width: 64, alignment: .leading)
                    Slider(value: $ceilingDB, in: -24...0).tint(LiquidColors.Accent.amber)
                    Text(String(format: "%+.1f dB", ceilingDB)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
                }
                Toggle("Auto-release", isOn: $autoRelease).font(.caption2).tint(LiquidColors.Accent.amber)
                Toggle("Bypass", isOn: $bypass).font(.caption2).tint(LiquidColors.Accent.amber)
            }
        }
    }

    private var outputMeter: some View {
        HStack(spacing: 4) {
            Text("Out").font(.caption2).foregroundStyle(LiquidColors.Text.tertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LiquidColors.Canvas.elev).frame(height: 6)
                    let fraction = max(0, min(1, (outputPeakDB + 60) / 60))
                    let isClipping = outputPeakDB > -3
                    Capsule().fill(isClipping ? LiquidColors.Accent.destructive : LiquidColors.Accent.amber).frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
            Text(String(format: "%+.1f dB", outputPeakDB)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
        }
    }
}
