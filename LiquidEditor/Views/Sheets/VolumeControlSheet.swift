// VolumeControlSheet.swift
// LiquidEditor
//
// Volume adjustment sheet view matching Flutter predecessor layout.
// Pure iOS 26 SwiftUI with native styling.

import SwiftUI

struct VolumeControlSheet: View {

    @State private var volume: Double

    @Environment(\.dismiss) private var dismiss

    let onApply: (_ volume: Double, _ isMuted: Bool, _ fadeIn: Double, _ fadeOut: Double) -> Void

    init(
        initialVolume: Double = 1.0,
        initialMuted: Bool = false,
        initialFadeIn: Double = 0.0,
        initialFadeOut: Double = 0.0,
        onApply: @escaping (_ volume: Double, _ isMuted: Bool, _ fadeIn: Double, _ fadeOut: Double) -> Void
    ) {
        _volume = State(initialValue: initialVolume)
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with "Volume" label, dynamic icon, percentage badge, X close
            headerRow
                .padding(.horizontal)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: LiquidSpacing.xl) {
                    // Slider with speaker icons
                    sliderRow

                    // Preset chips
                    presetChipsRow
                }
                .padding(.vertical, LiquidSpacing.sm)
            }

            Divider()
                .padding(.horizontal)

            // Full-width Apply button
            Button {
                onApply(volume, volume == 0, 0, 0)
                dismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Volume")
                .font(LiquidTypography.headline)

            Spacer()

            Image(systemName: volumeIcon)
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)

            Text(String(format: "%.0f%%", volume * 100))
                .font(LiquidTypography.footnoteSemibold)
                .foregroundStyle(.cyan)
                .padding(.horizontal, LiquidSpacing.sm + 2)
                .padding(.vertical, LiquidSpacing.xs)
                .background(Color.cyan.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                .accessibilityLabel("Volume \(Int(volume * 100)) percent")

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

    // MARK: - Slider

    private var sliderRow: some View {
        HStack(spacing: LiquidSpacing.md) {
            Image(systemName: "speaker.fill")
                .font(LiquidTypography.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Slider(value: $volume, in: 0...1)
                .tint(.cyan)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int(volume * 100)) percent")

            Image(systemName: "speaker.wave.3.fill")
                .font(LiquidTypography.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal)
    }

    // MARK: - Preset Chips

    private var presetChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.sm) {
                presetChip(label: "Mute", value: 0.0)
                presetChip(label: "25%", value: 0.25)
                presetChip(label: "50%", value: 0.5)
                presetChip(label: "75%", value: 0.75)
                presetChip(label: "100%", value: 1.0)
            }
            .padding(.horizontal)
        }
    }

    private func presetChip(label: String, value presetValue: Double) -> some View {
        let isSelected = abs(volume - presetValue) < 0.01

        return Button {
            withAnimation(.snappy) {
                volume = presetValue
            }
        } label: {
            Text(label)
                .font(isSelected ? LiquidTypography.captionMedium : LiquidTypography.caption)
                .padding(.horizontal, LiquidSpacing.md + 2)
                .padding(.vertical, LiquidSpacing.sm)
                .background(
                    isSelected
                        ? Color.cyan.opacity(0.2)
                        : LiquidColors.surface
                )
                .foregroundStyle(isSelected ? .cyan : .primary)
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var volumeIcon: String {
        if volume == 0 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

#Preview {
    VolumeControlSheet { _, _, _, _ in }
}
