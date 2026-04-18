// ChromaKeyView.swift
// LiquidEditor
//
// E4-9: Chroma key (green/blue screen) configuration sheet.
//
// Exposes the knobs of ``ChromaKeyConfig`` with an iOS 26 Liquid Glass
// sheet. Provides a color picker for the key color, tolerance /
// edge-smoothness / spill-suppression sliders, an eyedropper stub for
// sampling the preview, and a small live-preview thumbnail.
//
// The view is decoupled from any service; Apply forwards the resulting
// ``ChromaKeyConfig`` via a closure so it can be wired to the compositor
// once the ``ChromaKeyService`` (spec C5-14) lands.

import SwiftUI

// MARK: - ChromaKeyView

/// Sheet for configuring chroma-key (green-screen) removal.
@MainActor
struct ChromaKeyView: View {

    // MARK: - Input

    /// Starting configuration (defaults to green-screen preset).
    let initialConfig: ChromaKeyConfig

    /// Called when the user taps Apply with the updated configuration.
    let onApply: (ChromaKeyConfig) -> Void

    // MARK: - State

    @State private var targetColorKind: ChromaKeyColor
    @State private var keyColor: Color
    @State private var tolerance: Double
    @State private var edgeSmoothness: Double
    @State private var spillSuppression: Double
    @State private var isEnabled: Bool
    @State private var isSamplingEyedropper: Bool = false

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(
        initialConfig: ChromaKeyConfig = .defaultGreen,
        onApply: @escaping (ChromaKeyConfig) -> Void
    ) {
        self.initialConfig = initialConfig
        self.onApply = onApply

        _targetColorKind = State(initialValue: initialConfig.targetColor)

        let seededColor: Color
        switch initialConfig.targetColor {
        case .green:
            seededColor = Color.green
        case .blue:
            seededColor = Color.blue
        case .custom:
            if let argb = initialConfig.customColorValue {
                seededColor = Color.fromARGB(argb)
            } else {
                seededColor = Color.green
            }
        }
        _keyColor = State(initialValue: seededColor)

        // ChromaKeyConfig uses the name "sensitivity" for the tolerance knob.
        _tolerance = State(initialValue: initialConfig.sensitivity * 100)
        _edgeSmoothness = State(initialValue: initialConfig.smoothness * 50)
        _spillSuppression = State(initialValue: initialConfig.spillSuppression * 100)
        _isEnabled = State(initialValue: initialConfig.isEnabled)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LiquidSpacing.xl) {
                    preview

                    colorSection

                    slidersSection

                    enabledToggle

                    actionBar
                }
                .padding(LiquidSpacing.xl)
            }
            .background(LiquidColors.background.ignoresSafeArea())
            .navigationTitle("Chroma Key")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Subviews

    private var preview: some View {
        VStack(spacing: LiquidSpacing.sm) {
            Text("Preview")
                .font(LiquidTypography.captionMedium)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .fill(LiquidColors.fillTertiary)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: LiquidSpacing.iconXLarge))
                    .foregroundStyle(LiquidColors.textTertiary)

                // Thin overlay tinted by the chosen key color to hint
                // at the sensitivity effect on the preview.
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .fill(keyColor.opacity(0.15))
                    .allowsHitTesting(false)
            }
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .strokeBorder(LiquidColors.glassBorder, lineWidth: 0.5)
            )
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text("Key Color")
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(LiquidColors.textPrimary)

            HStack(spacing: LiquidSpacing.md) {
                ForEach([ChromaKeyColor.green, .blue, .custom], id: \.self) { kind in
                    presetSwatch(kind: kind)
                }

                Spacer()

                eyedropperButton
            }

            if targetColorKind == .custom {
                ColorPicker("Custom Color", selection: $keyColor, supportsOpacity: false)
                    .font(LiquidTypography.subheadlineMedium)
                    .foregroundStyle(LiquidColors.textPrimary)
            }
        }
        .padding(LiquidSpacing.lg)
        .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerLarge)
    }

    private func presetSwatch(kind: ChromaKeyColor) -> some View {
        let isSelected = kind == targetColorKind
        let swatchColor: Color
        switch kind {
        case .green:
            swatchColor = Color.green
        case .blue:
            swatchColor = Color.blue
        case .custom:
            swatchColor = keyColor
        }

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            targetColorKind = kind
            if kind == .green {
                keyColor = .green
            } else if kind == .blue {
                keyColor = .blue
            }
        } label: {
            VStack(spacing: LiquidSpacing.xxs) {
                Circle()
                    .fill(swatchColor)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().stroke(
                            isSelected ? LiquidColors.accent : LiquidColors.glassBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                    )
                Text(kind.displayName)
                    .font(LiquidTypography.caption2Semibold)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.displayName) key color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var eyedropperButton: some View {
        Button {
            // TODO: wire to preview sampling once ChromaKeyService (C5-14) lands.
            isSamplingEyedropper.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Image(systemName: isSamplingEyedropper ? "eyedropper.halffull" : "eyedropper")
                .font(.system(size: LiquidSpacing.iconMedium, weight: .semibold))
                .frame(
                    width: LiquidSpacing.minTouchTarget,
                    height: LiquidSpacing.minTouchTarget
                )
                .foregroundStyle(LiquidColors.accent)
                .background(
                    Circle().fill(LiquidColors.fillQuaternary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sample color from preview")
    }

    private var slidersSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
            sliderRow(
                title: "Tolerance",
                value: $tolerance,
                range: 0...100,
                format: "%.0f"
            )

            sliderRow(
                title: "Edge Smoothness",
                value: $edgeSmoothness,
                range: 0...50,
                format: "%.0f"
            )

            sliderRow(
                title: "Spill Suppression",
                value: $spillSuppression,
                range: 0...100,
                format: "%.0f"
            )
        }
        .padding(LiquidSpacing.lg)
        .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerLarge)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            HStack {
                Text(title)
                    .font(LiquidTypography.subheadlineSemibold)
                    .foregroundStyle(LiquidColors.textPrimary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(LiquidTypography.monoCaption)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private var enabledToggle: some View {
        Toggle(isOn: $isEnabled) {
            Text("Enable chroma key")
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(LiquidColors.textPrimary)
        }
        .padding(.horizontal, LiquidSpacing.lg)
    }

    private var actionBar: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.bordered)

            Button {
                // TODO: wire to ChromaKeyService (C5-14).
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onApply(buildConfig())
                dismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func buildConfig() -> ChromaKeyConfig {
        ChromaKeyConfig(
            targetColor: targetColorKind,
            customColorValue: targetColorKind == .custom ? keyColor.toARGB() : nil,
            sensitivity: tolerance / 100.0,
            smoothness: edgeSmoothness / 50.0,
            spillSuppression: spillSuppression / 100.0,
            isEnabled: isEnabled
        )
    }
}

// MARK: - Color <-> ARGB

private extension Color {

    /// Convert an ARGB integer (0xAARRGGBB) to a SwiftUI ``Color``.
    static func fromARGB(_ argb: Int) -> Color {
        let alpha = Double((argb >> 24) & 0xFF) / 255.0
        let red = Double((argb >> 16) & 0xFF) / 255.0
        let green = Double((argb >> 8) & 0xFF) / 255.0
        let blue = Double(argb & 0xFF) / 255.0
        return Color(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: alpha == 0 ? 1.0 : alpha
        )
    }

    /// Convert this color to an ARGB integer. Uses UIKit conversion for a
    /// best-effort round-trip of the resolved components.
    func toARGB() -> Int {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let a = Int(max(0, min(255, alpha * 255)))
        let r = Int(max(0, min(255, red * 255)))
        let g = Int(max(0, min(255, green * 255)))
        let b = Int(max(0, min(255, blue * 255)))
        return (a << 24) | (r << 16) | (g << 8) | b
    }
}
