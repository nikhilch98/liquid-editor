// ColorWheelControl.swift
// LiquidEditor
//
// P1-10: 3-way color-wheel primitive per spec §8.5.
//
// 52pt conic-gradient hue disc with a draggable white puck representing
// hue (polar angle) + saturation (radius from center). A short luma
// slider below maps -1...+1 (lift/gain offset). Numeric readout shows
// the luma value with 2-decimal precision.
//
// Used by ColorWheelsPanel (C5-6) to render Lift / Gamma / Gain wheels.

import SwiftUI
import CoreGraphics

// MARK: - ColorWheelValue

/// Polar puck position (hue + saturation) plus a separate luma offset.
struct ColorWheelValue: Equatable, Hashable, Sendable {
    /// Hue in revolutions (0..1).
    var hue: Double
    /// Saturation 0..1 (radius from center as a fraction of disc radius).
    var saturation: Double
    /// Luma offset −1..+1 (lift/gain shift).
    var luma: Double

    init(hue: Double = 0, saturation: Double = 0, luma: Double = 0) {
        self.hue = hue
        self.saturation = saturation
        self.luma = luma
    }
}

// MARK: - ColorWheelControl

/// 52pt color wheel + luma slider + numeric readout.
struct ColorWheelControl: View {
    let title: String
    @Binding var value: ColorWheelValue

    private let discSize: CGFloat = 52

    var body: some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LiquidColors.Text.tertiary)
            wheel
            lumaSlider
            Text(String(format: "%+.2f", value.luma))
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.Text.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) wheel, hue \(Int(value.hue * 360))\u00B0, saturation \(Int(value.saturation * 100))%, luma \(String(format: "%+.2f", value.luma))")
    }

    // MARK: - Subviews

    private var wheel: some View {
        ZStack {
            AngularGradient(
                gradient: Gradient(colors: [
                    .red, .yellow, .green, .cyan, .blue, .purple, .red
                ]),
                center: .center
            )
            .clipShape(Circle())
            .frame(width: discSize, height: discSize)
            .overlay(
                Circle().stroke(LiquidColors.Text.tertiary.opacity(0.4), lineWidth: 0.5)
            )
            puck
        }
        .frame(width: discSize, height: discSize)
        .gesture(dragGesture)
    }

    private var puck: some View {
        let radius = discSize / 2 * value.saturation
        let angle = value.hue * 2 * .pi
        let x = radius * cos(angle)
        let y = radius * sin(angle)
        return Circle()
            .fill(.white)
            .overlay(Circle().stroke(LiquidColors.Canvas.base, lineWidth: 1))
            .frame(width: 8, height: 8)
            .offset(x: x, y: y)
    }

    private var lumaSlider: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [.black, .white],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 5)
            .clipShape(Capsule())
            GeometryReader { geo in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(LiquidColors.Canvas.base, lineWidth: 1))
                    .frame(width: 9, height: 9)
                    .offset(x: geo.size.width * (value.luma + 1) / 2 - 4.5, y: -2)
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                let frac = max(0, min(1, drag.location.x / geo.size.width))
                                value.luma = (frac * 2) - 1
                            }
                    )
            }
            .frame(width: discSize, height: 9)
        }
        .frame(width: discSize, height: 9)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let center = CGPoint(x: discSize / 2, y: discSize / 2)
                let dx = drag.location.x - center.x
                let dy = drag.location.y - center.y
                let r = sqrt(dx * dx + dy * dy)
                let maxR = discSize / 2
                value.saturation = min(1, max(0, r / maxR))
                let angle = atan2(dy, dx)
                value.hue = (angle / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
            }
    }
}

// MARK: - C5-6 ColorWheelsPanel (3-way)

/// Lift / Gamma / Gain three-wheel panel + Temp/Tint/Saturation sliders
/// per spec §8.5.
struct ColorWheelsPanel: View {
    @Binding var lift: ColorWheelValue
    @Binding var gamma: ColorWheelValue
    @Binding var gain: ColorWheelValue
    @Binding var temperature: Double  // -1 (warm) ... +1 (cool)
    @Binding var tint: Double         // -1 (green) ... +1 (magenta)
    @Binding var saturation: Double   // 0...2 (1 = neutral)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ColorWheelControl(title: "Lift", value: $lift)
                ColorWheelControl(title: "Gamma", value: $gamma)
                ColorWheelControl(title: "Gain", value: $gain)
            }
            slider("Temp",       $temperature, -1...1, fmt: "%+.2f", gradient: tempGradient)
            slider("Tint",       $tint,        -1...1, fmt: "%+.2f", gradient: tintGradient)
            slider("Saturation", $saturation,   0...2, fmt: "%.2fx")
        }
        .padding(8)
        .background(LiquidColors.Canvas.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, fmt: String, gradient: LinearGradient? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).foregroundStyle(LiquidColors.Text.tertiary).frame(width: 64, alignment: .leading)
            ZStack(alignment: .leading) {
                if let gradient {
                    Capsule().fill(gradient).frame(height: 4)
                }
                Slider(value: value, in: range).tint(LiquidColors.Accent.amber)
            }
            Text(String(format: fmt, value.wrappedValue)).font(.caption2.monospaced()).foregroundStyle(LiquidColors.Text.secondary).frame(width: 56, alignment: .trailing)
        }
    }

    private var tempGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.7, blue: 0.4), Color(red: 1.0, green: 1.0, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0)],
                       startPoint: .leading, endPoint: .trailing)
    }
    private var tintGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.4, green: 1.0, blue: 0.5), Color(red: 1.0, green: 1.0, blue: 1.0), Color(red: 1.0, green: 0.4, blue: 0.8)],
                       startPoint: .leading, endPoint: .trailing)
    }
}
