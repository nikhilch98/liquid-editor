// TextStylePanel.swift
// LiquidEditor
//
// Font, size, color, weight, shadow, outline, glow, and background styling controls.
// Pure iOS 26 SwiftUI with native Cupertino styling.
//

import SwiftUI

// MARK: - TextStylePanel

/// Panel for editing text visual style properties.
///
/// All controls use native SwiftUI components with iOS 26 design:
/// sliders, segmented pickers, toggles, and color pickers.
struct TextStylePanel: View {

    // MARK: - Properties

    /// Current style binding.
    @Binding var style: TextOverlayStyle

    /// Preset colors for the color row.
    private static let presetColors: [ARGBColor] = [
        .fromARGB32(0xFFFFFFFF), // White
        .fromARGB32(0xFF000000), // Black
        .fromARGB32(0xFFFF3B30), // Red
        .fromARGB32(0xFFFF9500), // Orange
        .fromARGB32(0xFFFFCC00), // Yellow
        .fromARGB32(0xFF34C759), // Green
        .fromARGB32(0xFF007AFF), // Blue
        .fromARGB32(0xFFAF52DE), // Purple
        .fromARGB32(0xFFFF2D55), // Pink
        .fromARGB32(0xFF5AC8FA), // Light Blue
    ]

    /// Font weight options for the segmented control.
    private static let weightOptions: [(FontWeightValue, String)] = [
        (.w300, "Light"),
        (.w400, "Regular"),
        (.w600, "Semi"),
        (.w700, "Bold"),
        (.w900, "Heavy"),
    ]

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: LiquidSpacing.md) {
                // Font Size
                sliderRow(
                    label: "Font Size",
                    value: Binding(
                        get: { style.fontSize },
                        set: { style = style.with(fontSize: $0) }
                    ),
                    range: 12...200,
                    displayValue: "\(Int(style.fontSize))pt"
                )

                // Font Weight
                sectionLabel("Weight")
                Picker("Weight", selection: Binding(
                    get: { style.fontWeight },
                    set: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        style = style.with(fontWeight: $0)
                    }
                )) {
                    ForEach(Self.weightOptions, id: \.0) { weight, label in
                        Text(label).tag(weight)
                    }
                }
                .pickerStyle(.segmented)

                // Italic toggle
                switchRow(
                    label: "Italic",
                    isOn: Binding(
                        get: { style.isItalic },
                        set: { style = style.with(isItalic: $0) }
                    )
                )

                // Text Color
                colorRow(
                    label: "Text Color",
                    selectedColor: style.color,
                    onColorSelected: { color in
                        style = style.with(color: color)
                    }
                )

                // Letter Spacing
                sliderRow(
                    label: "Letter Spacing",
                    value: Binding(
                        get: { style.letterSpacing },
                        set: { style = style.with(letterSpacing: $0) }
                    ),
                    range: -5...20,
                    displayValue: String(format: "%.1f", style.letterSpacing)
                )

                // Line Height
                sliderRow(
                    label: "Line Height",
                    value: Binding(
                        get: { style.lineHeight },
                        set: { style = style.with(lineHeight: $0) }
                    ),
                    range: 0.8...3.0,
                    displayValue: String(format: "%.1f", style.lineHeight)
                )

                Divider()
                sectionLabel("Effects")

                // Shadow toggle + controls
                switchRow(
                    label: "Shadow",
                    isOn: Binding(
                        get: { style.shadow != nil },
                        set: { enabled in
                            if enabled {
                                style = style.with(shadow: TextShadowStyle())
                            } else {
                                style = style.with(clearShadow: true)
                            }
                        }
                    )
                )
                if let shadow = style.shadow {
                    sliderRow(
                        label: "  Blur",
                        value: Binding(
                            get: { shadow.blurRadius },
                            set: { style = style.with(shadow: shadow.with(blurRadius: $0)) }
                        ),
                        range: 0...30,
                        displayValue: String(format: "%.1f", shadow.blurRadius)
                    )
                }

                // Outline toggle + controls
                switchRow(
                    label: "Outline",
                    isOn: Binding(
                        get: { style.outline != nil },
                        set: { enabled in
                            if enabled {
                                style = style.with(outline: TextOutlineStyle())
                            } else {
                                style = style.with(clearOutline: true)
                            }
                        }
                    )
                )
                if let outline = style.outline {
                    sliderRow(
                        label: "  Width",
                        value: Binding(
                            get: { outline.width },
                            set: { style = style.with(outline: outline.with(width: $0)) }
                        ),
                        range: 0.5...10,
                        displayValue: String(format: "%.1f", outline.width)
                    )
                }

                // Background toggle + controls
                switchRow(
                    label: "Background",
                    isOn: Binding(
                        get: { style.background != nil },
                        set: { enabled in
                            if enabled {
                                style = style.with(background: TextBackgroundStyle())
                            } else {
                                style = style.with(clearBackground: true)
                            }
                        }
                    )
                )
                if let background = style.background {
                    sliderRow(
                        label: "  Corner Radius",
                        value: Binding(
                            get: { background.cornerRadius },
                            set: { style = style.with(background: background.with(cornerRadius: $0)) }
                        ),
                        range: 0...30,
                        displayValue: String(format: "%.0f", background.cornerRadius)
                    )
                }

                // Glow toggle + controls
                switchRow(
                    label: "Glow",
                    isOn: Binding(
                        get: { style.glow != nil },
                        set: { enabled in
                            if enabled {
                                style = style.with(glow: TextGlowStyle())
                            } else {
                                style = style.with(clearGlow: true)
                            }
                        }
                    )
                )
                if let glow = style.glow {
                    sliderRow(
                        label: "  Radius",
                        value: Binding(
                            get: { glow.radius },
                            set: { style = style.with(glow: glow.with(radius: $0)) }
                        ),
                        range: 1...30,
                        displayValue: String(format: "%.0f", glow.radius)
                    )
                    sliderRow(
                        label: "  Intensity",
                        value: Binding(
                            get: { glow.intensity },
                            set: { style = style.with(glow: glow.with(intensity: $0)) }
                        ),
                        range: 0...1.0,
                        displayValue: String(format: "%.2f", glow.intensity)
                    )
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.sm)
        }
    }

    // MARK: - Subviews

    /// Section header label.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(LiquidTypography.subheadlineSemibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Slider row with label, slider, and value readout.
    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayValue: String
    ) -> some View {
        HStack {
            Text(label)
                .font(LiquidTypography.subheadline)
                .frame(width: 110, alignment: .leading)

            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(displayValue)

            Text(displayValue)
                .font(LiquidTypography.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LiquidSpacing.xs)
    }

    /// Toggle row with label and switch.
    private func switchRow(label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isOn.wrappedValue = newValue
            }
        ))
        .font(LiquidTypography.subheadline)
        .padding(.vertical, LiquidSpacing.xs)
    }

    /// Color preset row with tappable color circles.
    private func colorRow(
        label: String,
        selectedColor: ARGBColor,
        onColorSelected: @escaping (ARGBColor) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text(label)
                .font(LiquidTypography.subheadline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LiquidSpacing.sm) {
                    ForEach(Self.presetColors, id: \.toARGB32) { presetColor in
                        let isSelected = selectedColor.toARGB32 == presetColor.toARGB32
                        Circle()
                            .fill(Color(
                                .sRGB,
                                red: presetColor.red,
                                green: presetColor.green,
                                blue: presetColor.blue,
                                opacity: presetColor.alpha
                            ))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? Color.blue : LiquidColors.separator,
                                        lineWidth: isSelected ? 3 : 1
                                    )
                            )
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onColorSelected(presetColor)
                            }
                    }
                }
            }
            .frame(height: 36)
        }
        .padding(.vertical, LiquidSpacing.xs)
    }
}

// MARK: - Testable Defaults

extension TextStylePanel {

    /// Default style for preview/testing.
    static let defaultStyle = TextOverlayStyle()

    /// All preset colors exposed for testing.
    static var testablePresetColors: [ARGBColor] { presetColors }

    /// All weight options exposed for testing.
    static var testableWeightOptions: [(FontWeightValue, String)] { weightOptions }
}
