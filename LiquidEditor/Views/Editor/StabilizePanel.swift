// StabilizePanel.swift
// LiquidEditor
//
// E4-8: Video stabilization controls panel.
//
// Presented as an inline overlay panel styled to match the project's
// context sub-panel aesthetic. Offers three algorithm presets (Cinema,
// Handheld, Fast), a strength slider, and a "crop to fit" toggle. The
// panel is wired to nothing yet — applying simply forwards the config
// via ``onApply`` and dismisses.
//
// When ``StabilizationService`` lands (spec C5-17), the caller can hand
// the resulting ``StabilizePanel.Config`` straight into the service.

import SwiftUI

// MARK: - StabilizePanel

/// Overlay panel with stabilization controls.
@MainActor
struct StabilizePanel: View {

    // MARK: - Nested Types

    /// Algorithm preset choices offered in the UI.
    enum Algorithm: String, CaseIterable, Identifiable, Sendable {
        /// Slow, highest-quality motion smoothing for cinematic shots.
        case cinema
        /// Balanced smoothing for handheld phone shots.
        case handheld
        /// Real-time, lower-quality preview mode.
        case fast

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .cinema: "Cinema"
            case .handheld: "Handheld"
            case .fast: "Fast"
            }
        }

        var iconName: String {
            switch self {
            case .cinema: "film.stack"
            case .handheld: "hand.raised"
            case .fast: "bolt.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .cinema: "Smooth, cinematic motion"
            case .handheld: "Balanced for phone footage"
            case .fast: "Real-time preview"
            }
        }
    }

    /// Resulting configuration emitted on Apply.
    struct Config: Equatable, Sendable {
        let algorithm: Algorithm
        let strength: Double
        let cropToFit: Bool
    }

    // MARK: - Input

    /// Called when the user taps Apply with the chosen config.
    let onApply: (Config) -> Void

    /// Called when the user taps Reset or dismisses.
    let onDismiss: () -> Void

    // MARK: - State

    @State private var algorithm: Algorithm = .handheld
    @State private var strength: Double = 0.6
    @State private var cropToFit: Bool = true

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
            header

            algorithmRow

            strengthSection

            cropToggle

            actionBar
        }
        .padding(LiquidSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerXLarge, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerXLarge, style: .continuous)
                .strokeBorder(LiquidColors.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .padding(LiquidSpacing.lg)
        .frame(maxWidth: 480)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
                Text("Stabilize")
                    .font(LiquidTypography.title3)
                    .foregroundStyle(LiquidColors.textPrimary)

                Text("Reduce camera shake on this clip")
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(LiquidColors.textSecondary)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: LiquidSpacing.iconMedium, weight: .semibold))
                    .foregroundStyle(LiquidColors.textSecondary)
                    .frame(
                        width: LiquidSpacing.minTouchTarget,
                        height: LiquidSpacing.minTouchTarget
                    )
            }
            .accessibilityLabel("Close stabilize panel")
            .buttonStyle(.plain)
        }
    }

    private var algorithmRow: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text("Algorithm")
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(LiquidColors.textPrimary)

            HStack(spacing: LiquidSpacing.md) {
                ForEach(Algorithm.allCases) { option in
                    algorithmCard(option: option)
                }
            }
        }
    }

    private func algorithmCard(option: Algorithm) -> some View {
        let isSelected = option == algorithm
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            algorithm = option
        } label: {
            VStack(spacing: LiquidSpacing.xs) {
                Image(systemName: option.iconName)
                    .font(.system(size: LiquidSpacing.iconLarge, weight: .semibold))

                Text(option.displayName)
                    .font(LiquidTypography.subheadlineSemibold)

                Text(option.subtitle)
                    .font(LiquidTypography.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(LiquidSpacing.sm)
            .foregroundStyle(isSelected ? Color.white : LiquidColors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .fill(isSelected ? LiquidColors.accent : LiquidColors.fillQuaternary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .strokeBorder(
                        isSelected ? LiquidColors.accent : LiquidColors.glassBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityHint(option.subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            HStack {
                Text("Strength")
                    .font(LiquidTypography.subheadlineSemibold)
                    .foregroundStyle(LiquidColors.textPrimary)
                Spacer()
                Text("\(Int(strength * 100))%")
                    .font(LiquidTypography.monoCaption)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            Slider(value: $strength, in: 0...1)
                .accessibilityLabel("Stabilization strength")
        }
    }

    private var cropToggle: some View {
        Toggle(isOn: $cropToFit) {
            VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
                Text("Crop to Fit")
                    .font(LiquidTypography.subheadlineSemibold)
                    .foregroundStyle(LiquidColors.textPrimary)
                Text("Zoom in to hide stabilized borders")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button {
                algorithm = .handheld
                strength = 0.6
                cropToFit = true
            } label: {
                Text("Reset")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeightCompact)
            }
            .buttonStyle(.bordered)

            Button {
                // TODO: wire to StabilizationService once C5-17 lands.
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onApply(Config(
                    algorithm: algorithm,
                    strength: strength,
                    cropToFit: cropToFit
                ))
            } label: {
                Text("Apply")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeightCompact)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
