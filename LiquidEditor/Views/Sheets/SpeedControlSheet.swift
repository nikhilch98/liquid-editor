// SpeedControlSheet.swift
// LiquidEditor
//
// Speed control sheet view matching Flutter predecessor layout.
// Pure iOS 26 SwiftUI with native styling.

import SwiftUI

struct SpeedControlSheet: View {

    @State private var speedMultiplier: Double
    @State private var maintainPitch: Bool

    @Environment(\.dismiss) private var dismiss

    let onApply: (SpeedConfig) -> Void

    /// Speed presets: 8 presets as specified.
    private let presets: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    init(
        initialConfig: SpeedConfig = .normal,
        onApply: @escaping (SpeedConfig) -> Void
    ) {
        _speedMultiplier = State(initialValue: initialConfig.speedMultiplier)
        _maintainPitch = State(initialValue: initialConfig.maintainPitch)
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title, speed badge, X close
            headerRow
                .padding(.horizontal)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: LiquidSpacing.xl) {
                    // Slider with tortoise/hare icons
                    sliderRow

                    // Maintain Audio Pitch toggle
                    pitchToggleRow

                    // Audio muted warning for extreme speeds
                    if speedMultiplier > 4.0 {
                        audioMutedWarning
                    }

                    // "Presets" label
                    Text("Presets")
                        .font(LiquidTypography.subheadlineMedium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Preset buttons (Wrap-like layout using LazyVGrid)
                    presetButtonsSection
                }
                .padding(.vertical, LiquidSpacing.sm)
            }

            Divider()
                .padding(.horizontal)

            // Full-width Apply button
            Button {
                let clamped = SpeedConfig.clampSpeed(speedMultiplier)
                let config = SpeedConfig(
                    speedMultiplier: clamped,
                    maintainPitch: maintainPitch
                )
                onApply(config)
                dismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
            .accessibilityLabel("Apply speed \(formattedSpeed)")
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            Text("Playback Speed")
                .font(LiquidTypography.headline)

            Spacer()

            // Animated speed icon (tortoise / play / hare)
            Image(systemName: speedIcon(for: speedMultiplier))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
                .animation(.snappy, value: speedMultiplier)

            // Speed badge — orange pill showing e.g. "1.5×"
            Text(formattedSpeed)
                .font(LiquidTypography.footnoteSemibold)
                .foregroundStyle(.orange)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                .accessibilityLabel("Current speed: \(formattedSpeed)")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Slider Row

    private var sliderRow: some View {
        HStack(spacing: LiquidSpacing.md) {
            Image(systemName: "tortoise.fill")
                .font(LiquidTypography.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Slider(
                value: $speedMultiplier,
                in: 0.25...4.0
            )
            .tint(.orange)
            .accessibilityLabel("Playback speed")
            .accessibilityValue(formattedSpeed)

            Image(systemName: "hare.fill")
                .font(LiquidTypography.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal)
    }

    // MARK: - Pitch Toggle

    private var pitchToggleRow: some View {
        Toggle("Maintain Audio Pitch", isOn: $maintainPitch)
            .tint(.orange)
            .padding(.horizontal)
    }

    // MARK: - Audio Muted Warning

    private var audioMutedWarning: some View {
        HStack(spacing: LiquidSpacing.xs + 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(LiquidTypography.caption)
            Text("Audio will be muted above 4\u{00D7} speed")
                .font(LiquidTypography.caption)
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Audio will be muted above 4 times speed")
    }

    // MARK: - Preset Buttons

    private var presetButtonsSection: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: LiquidSpacing.sm), count: 4)

        return LazyVGrid(columns: columns, spacing: LiquidSpacing.sm) {
            ForEach(presets, id: \.self) { preset in
                presetButton(preset)
            }
        }
        .padding(.horizontal)
    }

    private func presetButton(_ preset: Double) -> some View {
        let isSelected = abs(speedMultiplier - preset) < 0.01

        return Button {
            withAnimation(.snappy) {
                speedMultiplier = preset
            }
        } label: {
            Text(formatPresetLabel(preset))
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiquidSpacing.sm)
                .background(
                    isSelected
                        ? Color.orange.opacity(0.2)
                        : Color(.secondarySystemGroupedBackground)
                )
                .foregroundStyle(isSelected ? .orange : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set playback speed to \(formatPresetLabel(preset))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Helpers

    private var formattedSpeed: String {
        if speedMultiplier == 1.0 { return "1×" }
        if speedMultiplier == Double(Int(speedMultiplier)) {
            return "\(Int(speedMultiplier))×"
        }
        return String(format: "%.2f×", speedMultiplier)
    }

    private func formatPresetLabel(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return "\(Int(value))×"
        }
        return "\(value)×"
    }

    /// Returns the SF Symbol name appropriate for the given speed value.
    ///
    /// - Parameter speed: The playback speed multiplier.
    /// - Returns: `"tortoise.fill"` for speeds below 0.75×, `"hare.fill"` for speeds above 1.5×,
    ///   and `"play.fill"` for the range in between.
    private func speedIcon(for speed: Double) -> String {
        if speed < 0.75 { return "tortoise.fill" }
        if speed > 1.5 { return "hare.fill" }
        return "play.fill"
    }

    private var speedIconName: String {
        speedIcon(for: speedMultiplier)
    }
}

// MARK: - SpeedInlinePanel

/// Compact inline speed panel for embedding directly in the editor layout.
///
/// Shows:
/// - Large centered speed display (36pt font)
/// - Slider spanning 0.1× to 8.0× with tortoise/hare end icons
/// - Horizontally scrollable preset buttons (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0)
/// - Preset snapping: snaps to a preset when within 0.08 of it, with haptic feedback
///
/// Height is approximately 160pt. Calls `onChanged` on every change for real-time preview.
struct SpeedInlinePanel: View {

    @Binding var speed: Double
    var onChanged: (Double) -> Void = { _ in }

    private static let presets: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    private static let snapThreshold: Double = 0.08

    var body: some View {
        VStack(spacing: LiquidSpacing.md) {
            // Large speed display
            Text(formattedSpeed)
                .font(.system(size: 36, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Speed: \(formattedSpeed)")

            // Slider with tortoise / hare end icons
            HStack(spacing: LiquidSpacing.md) {
                Image(systemName: "tortoise.fill")
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Slider(
                    value: Binding(
                        get: { speed.clamped(to: 0.1...8.0) },
                        set: { newValue in
                            let snapped = Self.snap(newValue)
                            speed = snapped
                            onChanged(snapped)
                        }
                    ),
                    in: 0.1...8.0
                )
                .tint(.orange)
                .accessibilityLabel("Playback speed")
                .accessibilityValue(formattedSpeed)

                Image(systemName: "hare.fill")
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LiquidSpacing.lg)

            // Scrollable preset buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LiquidSpacing.sm) {
                    ForEach(Self.presets, id: \.self) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.horizontal, LiquidSpacing.lg)
            }
        }
        .frame(height: 160)
    }

    // MARK: Private helpers

    private func presetChip(_ preset: Double) -> some View {
        let isSelected = abs(speed - preset) < 0.01

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            speed = preset
            onChanged(preset)
        } label: {
            Text(formatPresetLabel(preset))
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, LiquidSpacing.xs + 2)
                .background(
                    isSelected
                        ? Color.orange.opacity(0.2)
                        : Color(.secondarySystemGroupedBackground)
                )
                .foregroundStyle(isSelected ? .orange : .primary)
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                            .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set speed to \(formatPresetLabel(preset))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var formattedSpeed: String {
        if speed == 1.0 { return "1×" }
        if speed == Double(Int(speed)) { return "\(Int(speed))×" }
        return String(format: "%.2f×", speed)
    }

    private func formatPresetLabel(_ value: Double) -> String {
        if value == Double(Int(value)) { return "\(Int(value))×" }
        return "\(value)×"
    }

    /// Snaps `value` to the nearest preset if within `snapThreshold`, triggering haptic feedback.
    private static func snap(_ value: Double) -> Double {
        for preset in presets {
            if abs(value - preset) < snapThreshold {
                UISelectionFeedbackGenerator().selectionChanged()
                return preset
            }
        }
        return value
    }
}

// MARK: - Double clamped helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview("Sheet") {
    SpeedControlSheet { _ in }
}

#Preview("Inline Panel") {
    @Previewable @State var speed: Double = 1.0
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            SpeedInlinePanel(speed: $speed) { _ in
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge))
            .padding()
        }
    }
}
