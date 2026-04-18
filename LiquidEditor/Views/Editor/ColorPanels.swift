// ColorPanels.swift
// LiquidEditor
//
// C5-7 Curves Editor + C5-8 HSL Panel per spec §8.6 + §8.7.
// Both bind to existing ColorGrade / CurveData / HSLAdjustment models.

import SwiftUI

// MARK: - C5-7 Curves Editor

struct CurvesEditor: View {
    @Binding var lumaPoints: [CGPoint]
    @Binding var redPoints: [CGPoint]
    @Binding var greenPoints: [CGPoint]
    @Binding var bluePoints: [CGPoint]
    @Binding var activeChannel: ColorChannel
    let onResetChannel: () -> Void
    let onResetAll: () -> Void

    enum ColorChannel: String, CaseIterable, Identifiable {
        case luma, red, green, blue
        var id: String { rawValue }
        var label: String {
            switch self {
            case .luma: return "L"
            case .red: return "R"
            case .green: return "G"
            case .blue: return "B"
            }
        }
        var color: Color {
            switch self {
            case .luma: return LiquidColors.Text.primary
            case .red: return Color(red: 1, green: 0.3, blue: 0.3)
            case .green: return LiquidColors.Accent.success
            case .blue: return Color(red: 0.4, green: 0.6, blue: 1)
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            channelPicker
            curveCanvas
            actionRow
        }
        .padding(8)
        .background(LiquidColors.Canvas.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private var channelPicker: some View {
        Picker("", selection: $activeChannel) {
            ForEach(ColorChannel.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var curveCanvas: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Rectangle()
                    .fill(LiquidColors.Canvas.elev)
                    .frame(width: size, height: size)
                gridLines(in: CGSize(width: size, height: size))
                curvePath(in: CGSize(width: size, height: size))
                ForEach(activePoints.indices, id: \.self) { i in
                    let p = activePoints[i]
                    Circle()
                        .fill(activeChannel.color)
                        .frame(width: 8, height: 8)
                        .position(x: p.x * size, y: (1 - p.y) * size)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxHeight: 240)
    }

    private var activePoints: [CGPoint] {
        switch activeChannel {
        case .luma: return lumaPoints
        case .red: return redPoints
        case .green: return greenPoints
        case .blue: return bluePoints
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        Path { p in
            for i in 1..<4 {
                let x = size.width * CGFloat(i) / 4
                let y = size.height * CGFloat(i) / 4
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(LiquidColors.Text.tertiary.opacity(0.3), lineWidth: 0.5)
    }

    private func curvePath(in size: CGSize) -> some View {
        let pts = activePoints.sorted { $0.x < $1.x }
        return Path { p in
            guard let first = pts.first else { return }
            p.move(to: CGPoint(x: first.x * size.width, y: (1 - first.y) * size.height))
            for pt in pts.dropFirst() {
                p.addLine(to: CGPoint(x: pt.x * size.width, y: (1 - pt.y) * size.height))
            }
        }
        .stroke(activeChannel.color, lineWidth: 1.5)
    }

    private var actionRow: some View {
        HStack {
            Button("Reset \(activeChannel.label)", action: onResetChannel)
            Spacer()
            Button("Reset all", action: onResetAll)
        }
        .font(.caption)
        .foregroundStyle(LiquidColors.Accent.amber)
        .buttonStyle(.plain)
    }
}

// MARK: - C5-8 HSL Panel

struct HSLPanel: View {
    @Binding var activeChannel: HSLChannel
    @Binding var hueShift: Double
    @Binding var saturationShift: Double
    @Binding var luminanceShift: Double
    let onResetChannel: () -> Void
    let onPickChannel: () -> Void

    enum HSLChannel: String, CaseIterable, Identifiable {
        case red, orange, yellow, green, aqua, blue, purple, magenta
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .red:     return Color(red: 1.0, green: 0.3, blue: 0.3)
            case .orange:  return Color(red: 1.0, green: 0.6, blue: 0.2)
            case .yellow:  return Color(red: 1.0, green: 0.9, blue: 0.3)
            case .green:   return Color(red: 0.3, green: 0.8, blue: 0.4)
            case .aqua:    return Color(red: 0.3, green: 0.8, blue: 0.8)
            case .blue:    return Color(red: 0.3, green: 0.5, blue: 1.0)
            case .purple:  return Color(red: 0.6, green: 0.4, blue: 0.9)
            case .magenta: return Color(red: 1.0, green: 0.4, blue: 0.7)
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            channelChips
            slider("Hue", $hueShift, -180...180, fmt: "%+.0f\u{00B0}")
            slider("Saturation", $saturationShift, -1...1, fmt: "%+.0f%%", scale: 100)
            slider("Luminance", $luminanceShift, -1...1, fmt: "%+.0f%%", scale: 100)
            actionRow
        }
        .padding(8)
        .background(LiquidColors.Canvas.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private var channelChips: some View {
        HStack(spacing: 4) {
            ForEach(HSLChannel.allCases) { c in
                Button { activeChannel = c } label: {
                    Circle()
                        .fill(c.color)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(
                                c == activeChannel ? LiquidColors.Accent.amber : Color.clear,
                                lineWidth: 2
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.rawValue.capitalized)
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

    private var actionRow: some View {
        HStack {
            Button {
                onPickChannel()
            } label: {
                Label("Pick", systemImage: "eyedropper").font(.caption).foregroundStyle(LiquidColors.Text.secondary)
            }
            Spacer()
            Button("Reset \(activeChannel.rawValue.capitalized)", action: onResetChannel)
                .font(.caption).foregroundStyle(LiquidColors.Accent.amber)
        }
        .buttonStyle(.plain)
    }
}
