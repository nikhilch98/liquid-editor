// InspectorSectionViews.swift
// LiquidEditor
//
// IM9-2 .. IM9-6: Skeletal section views for the InspectorPanel.
//
// Each view is a thin wrapper used by the InspectorPanel section
// renderer to populate a section by `InspectorSectionID`. The actual
// data wiring (binding to selected clip's ColorGrade, EffectChain,
// Keyframe etc.) is performed by section providers in the editor view
// model when these are dropped into the panel.
//
// All views are stateless — selection-state owners pass the values in.

import SwiftUI

// MARK: - InspectorClipHeader (IM9-2)

/// Compact header row shown at the top of the inspector for any
/// clip selection: name, duration timecode, badge chips.
struct InspectorClipHeader: View {
    let name: String
    let duration: String
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(LiquidColors.Text.primary)
                    .lineLimit(1)
                Spacer()
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiquidColors.Text.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(LiquidColors.Canvas.elev)
                        )
                }
            }
            Text(duration)
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.tertiary)
        }
    }
}

// MARK: - InspectorTransformSection (IM9-3)

/// Position / scale / rotation row group. Three numeric input rows
/// bound to the underlying OverlayTransform.
struct InspectorTransformSection: View {
    @Binding var positionX: Double
    @Binding var positionY: Double
    @Binding var scale: Double
    @Binding var rotationDegrees: Double

    var body: some View {
        VStack(spacing: 4) {
            row(label: "X", value: $positionX, range: 0...1, format: "%.2f")
            row(label: "Y", value: $positionY, range: 0...1, format: "%.2f")
            row(label: "Scale", value: $scale, range: 0.1...4, format: "%.2fx")
            row(label: "Rotation", value: $rotationDegrees, range: -180...180, format: "%.0f\u{00B0}")
        }
    }

    private func row(label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(LiquidColors.Text.tertiary)
                .frame(width: 56, alignment: .leading)
            Slider(value: value, in: range)
                .tint(LiquidColors.Accent.amber)
            Text(String(format: format, value.wrappedValue))
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.Text.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - InspectorSpeedSection (IM9-4)

/// Speed multiplier with preset chips + custom slider + preserve-pitch.
struct InspectorSpeedSection: View {
    @Binding var rate: Double
    @Binding var preservePitch: Bool

    private let presets: [Double] = [0.25, 0.5, 1.0, 2.0]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(presets, id: \.self) { p in
                    Button { rate = p } label: {
                        Text(p == 1.0 ? "1x" : String(format: "%.2gx", p))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(rate == p ? LiquidColors.Accent.amber : LiquidColors.Text.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(rate == p ? LiquidColors.Accent.amberGlow : LiquidColors.Canvas.elev)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(String(format: "%.2gx", rate))
                    .font(.caption.monospaced())
                    .foregroundStyle(LiquidColors.Text.primary)
            }
            Slider(value: $rate, in: 0.1...10).tint(LiquidColors.Accent.amber)
            Toggle("Preserve pitch", isOn: $preservePitch)
                .font(.caption)
                .toggleStyle(.switch)
                .tint(LiquidColors.Accent.amber)
        }
    }
}

// MARK: - InspectorVolumeSection (IM9-5)

/// dB slider + fade-in/out compact controls.
struct InspectorVolumeSection: View {
    @Binding var volumeDB: Double
    @Binding var fadeInMs: Double
    @Binding var fadeOutMs: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Level").font(.caption).foregroundStyle(LiquidColors.Text.tertiary)
                Spacer()
                Text(String(format: "%+.1f dB", volumeDB))
                    .font(.caption.monospaced())
                    .foregroundStyle(LiquidColors.Text.primary)
            }
            Slider(value: $volumeDB, in: -60...12).tint(LiquidColors.Accent.amber)
            HStack(spacing: 6) {
                Text("Fade in").font(.caption).foregroundStyle(LiquidColors.Text.tertiary)
                Slider(value: $fadeInMs, in: 0...3000).tint(LiquidColors.Accent.amber)
                Text("\(Int(fadeInMs)) ms")
                    .font(.caption2.monospaced())
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            HStack(spacing: 6) {
                Text("Fade out").font(.caption).foregroundStyle(LiquidColors.Text.tertiary)
                Slider(value: $fadeOutMs, in: 0...3000).tint(LiquidColors.Accent.amber)
                Text("\(Int(fadeOutMs)) ms")
                    .font(.caption2.monospaced())
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

// MARK: - InspectorOpacitySection (IM9-6)

/// Single-slider opacity (0..1) with percentage readout.
struct InspectorOpacitySection: View {
    @Binding var opacity: Double

    var body: some View {
        HStack(spacing: 6) {
            Slider(value: $opacity, in: 0...1).tint(LiquidColors.Accent.amber)
            Text("\(Int(opacity * 100))%")
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.primary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
