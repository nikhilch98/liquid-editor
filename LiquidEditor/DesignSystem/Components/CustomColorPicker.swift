// CustomColorPicker.swift
// LiquidEditor
//
// P1-17: HSB + hex + eyedropper + saved-colors color picker per spec
// §8.1.2 and §7.9 (used by Text swatches, chroma fill-behind, and any
// color pad that needs more than the 7 predefined swatches).
//
// Tabs:
// - HSB: three sliders (hue 0-360, saturation 0-100, brightness 0-100)
//   with a live swatch preview
// - Hex: single-line text field ("#E6B340"), validates on commit
// - Saved: horizontal row of user-saved colors, tap to pick,
//   long-press to remove
//
// Optional eyedropper toggle — when on, the parent view is responsible
// for reading a color from the preview and calling `onEyedrop(Color)`.

import SwiftUI
import Observation

// MARK: - HSBComponents

struct HSBComponents: Equatable, Sendable {
    var hue: Double       // 0.0 – 1.0
    var saturation: Double // 0.0 – 1.0
    var brightness: Double // 0.0 – 1.0

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    var hexString: String {
        let ui = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(r * 255), Int(g * 255), Int(b * 255)
        )
    }

    static func from(hex: String) -> HSBComponents? {
        var s = hex.uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &sat, brightness: &br, alpha: nil)
        return HSBComponents(hue: h, saturation: sat, brightness: br)
    }
}

// MARK: - CustomColorPicker

struct CustomColorPicker: View {

    @Binding var hsb: HSBComponents
    let savedColors: [HSBComponents]
    let onSaveColor: (HSBComponents) -> Void
    let onEyedrop: (() -> Void)?

    @State private var tab: Tab = .hsb
    @State private var hexDraft: String = ""

    private enum Tab: String, CaseIterable {
        case hsb, hex, saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            tabBar
            Group {
                switch tab {
                case .hsb:   hsbTab
                case .hex:   hexTab
                case .saved: savedTab
                }
            }
        }
        .padding(10)
        .background(LiquidColors.Canvas.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(LiquidColors.Text.tertiary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Preview swatch + save / eyedropper

    private var preview: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(hsb.color)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
            Text(hsb.hexString)
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.primary)
            Spacer()
            if let onEyedrop {
                Button(action: onEyedrop) {
                    Image(systemName: "eyedropper")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LiquidColors.Text.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick color from preview")
            }
            Button { onSaveColor(hsb) } label: {
                Image(systemName: "plus.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiquidColors.Accent.amber)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save this color")
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    Text(t.rawValue.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tab == t ? LiquidColors.Accent.amber : LiquidColors.Text.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(tab == t ? LiquidColors.Accent.amberGlow : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - HSB tab

    private var hsbTab: some View {
        VStack(spacing: 6) {
            slider(label: "H", value: $hsb.hue, range: 0...1)
            slider(label: "S", value: $hsb.saturation, range: 0...1)
            slider(label: "B", value: $hsb.brightness, range: 0...1)
        }
    }

    private func slider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(LiquidColors.Text.tertiary)
                .frame(width: 14, alignment: .leading)
            Slider(value: value, in: range)
                .tint(LiquidColors.Accent.amber)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption2.monospaced())
                .foregroundStyle(LiquidColors.Text.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Hex tab

    private var hexTab: some View {
        HStack {
            TextField("#E6B340", text: $hexDraft)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .foregroundStyle(LiquidColors.Text.primary)
                .padding(8)
                .background(LiquidColors.Canvas.elev, in: RoundedRectangle(cornerRadius: 6))
                .onSubmit {
                    if let parsed = HSBComponents.from(hex: hexDraft) {
                        hsb = parsed
                    }
                }
                .onAppear { hexDraft = hsb.hexString }
        }
    }

    // MARK: - Saved tab

    private var savedTab: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(savedColors.enumerated()), id: \.offset) { _, saved in
                    Button { hsb = saved } label: {
                        Circle()
                            .fill(saved.color)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                if savedColors.isEmpty {
                    Text("No saved colors yet. Tap + above to save.")
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.Text.tertiary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Color picker") {
    struct Demo: View {
        @State private var hsb = HSBComponents(hue: 0.12, saturation: 0.72, brightness: 0.9)
        @State private var saved: [HSBComponents] = []
        var body: some View {
            CustomColorPicker(
                hsb: $hsb,
                savedColors: saved,
                onSaveColor: { saved.append($0) },
                onEyedrop: nil
            )
            .padding()
            .background(LiquidColors.Canvas.base)
            .preferredColorScheme(.dark)
        }
    }
    return Demo()
}
