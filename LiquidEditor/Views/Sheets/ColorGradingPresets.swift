// ColorGradingPresets.swift
// LiquidEditor
//
// Horizontal scrollable row of quick-apply color grading preset chips.
// Matches the Flutter ColorGradingPresets widget: glass background,
// SF Symbol icon, label text, orange selection ring, light haptic on tap.
// Pure SwiftUI, iOS 26 Liquid Glass design system.

import SwiftUI

// MARK: - ColorGradingPresets

/// Horizontal scrollable list of built-in filter preset chips.
///
/// Shows a "None" chip at the start (calls `onReset`) followed by
/// chips for every entry in `BuiltinPresets.all`. Active preset
/// is highlighted with an orange border and tinted icon/text.
struct ColorGradingPresets: View {

    /// The ID of the currently active preset, or `nil` if no preset is active.
    let activePresetId: String?

    /// Called when the user taps a preset chip.
    let onPresetSelected: (FilterPreset) -> Void

    /// Called when the user taps the "None" chip to reset.
    let onReset: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // "None" chip – resets to no active preset
                PresetChip(
                    label: "None",
                    systemImage: "xmark.circle",
                    isSelected: activePresetId == nil
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onReset()
                }

                // Built-in preset chips
                ForEach(BuiltinPresets.all, id: \.id) { preset in
                    PresetChip(
                        label: preset.name,
                        systemImage: systemImage(for: preset.id),
                        isSelected: activePresetId == preset.id
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onPresetSelected(preset)
                    }
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
        }
        .frame(height: 80)
    }

    // MARK: - Icon Mapping

    /// Map preset ID to an appropriate SF Symbol name.
    private func systemImage(for presetId: String) -> String {
        switch presetId {
        case "builtin_vivid":         return "sparkles"
        case "builtin_warm":          return "sun.max.fill"
        case "builtin_cool":          return "snowflake"
        case "builtin_bw":            return "circle.lefthalf.filled"
        case "builtin_vintage":       return "film"
        case "builtin_cinematic":     return "movieclapper"
        case "builtin_faded":         return "photo.fill"
        case "builtin_high_contrast": return "circle.fill"
        case "builtin_muted":         return "drop.fill"
        case "builtin_film_noir":     return "moon.stars.fill"
        case "builtin_sunset":        return "sunset.fill"
        case "builtin_forest":        return "leaf.fill"
        case "builtin_ocean":         return "wave.3.forward"
        case "builtin_neon":          return "bolt.fill"
        case "builtin_pastel":        return "paintpalette.fill"
        default:                      return "slider.horizontal.3"
        }
    }
}

// MARK: - PresetChip

/// A single preset chip with Liquid Glass styling.
///
/// Displays an SF Symbol icon above a label text.
/// When selected, shows an orange border, tinted icon and text.
private struct PresetChip: View {
    let label: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? .orange : .secondary)

                Text(label)
                    .font(LiquidTypography.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.orange : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 68)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.orange.opacity(0.7) : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) preset")
        .accessibilityHint(isSelected ? "Currently selected" : "Applies the \(label) color preset")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
