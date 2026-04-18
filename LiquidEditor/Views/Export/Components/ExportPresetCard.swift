// ExportPresetCard.swift
// LiquidEditor
//
// A tappable card showing one `ExportPreset` with codec/resolution/bitrate
// summary and an estimated file size + duration. Shared between the iPhone
// and iPad Export screens (S2-8 / S2-9).

import SwiftUI

// MARK: - ExportPresetCategory

/// Visual grouping used by the redesigned Export screens.
///
/// Maps preset IDs coming from `ExportPresetService` into a small set of
/// top-level buckets (Quick, Social, Pro, Custom) so we can render
/// section headers and pick an appropriate accent tint.
enum ExportPresetCategory: String, CaseIterable, Identifiable, Sendable {
    case quick
    case social
    case pro
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quick: return "Quick"
        case .social: return "Social"
        case .pro: return "Pro"
        case .custom: return "Custom"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .quick: return "bolt.fill"
        case .social: return "person.2.fill"
        case .pro: return "sparkles"
        case .custom: return "slider.horizontal.3"
        }
    }

    var accentColor: Color {
        switch self {
        case .quick: return .blue
        case .social: return .pink
        case .pro: return .purple
        case .custom: return .orange
        }
    }

    /// Infer a category from an `ExportPreset`.
    static func infer(from preset: ExportPreset) -> ExportPresetCategory {
        if preset.id.hasPrefix("social_") { return .social }
        if !preset.isBuiltIn { return .custom }
        switch preset.id {
        case "quick_share", "standard": return .quick
        case "high_quality", "4k", "audio_only": return .pro
        default: return .quick
        }
    }
}

// MARK: - ExportPresetCard

/// Card row displaying one export preset.
///
/// - Highlights when selected via an accent border.
/// - Uses Liquid Glass material background.
/// - Exposes codec / resolution / bitrate as a compact subtitle.
struct ExportPresetCard: View {

    // MARK: - Inputs

    /// The preset to render.
    let preset: ExportPreset

    /// Visual category (drives icon tint + label).
    let category: ExportPresetCategory

    /// Whether this card is currently selected.
    let isSelected: Bool

    /// Estimated clip duration in seconds used for file-size estimation.
    let estimatedDurationSeconds: Double

    /// Tap handler.
    let onTap: () -> Void

    // MARK: - Constants

    private static let cornerRadius: CGFloat = LiquidSpacing.cornerLarge
    private static let selectedBorderWidth: CGFloat = 2
    private static let iconSize: CGFloat = 44
    private static let verticalPadding: CGFloat = LiquidSpacing.md
    private static let horizontalPadding: CGFloat = LiquidSpacing.lg

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(preset.name) preset"))
        .accessibilityValue(Text(summaryLine))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityHint(Text("Selects this export preset"))
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: LiquidSpacing.lg) {
            iconBadge

            VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
                Text(preset.name)
                    .font(LiquidTypography.bodySemibold)
                    .foregroundStyle(LiquidColors.textPrimary)
                    .lineLimit(1)

                Text(summaryLine)
                    .font(LiquidTypography.caption)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .lineLimit(1)

                Text(metaLine)
                    .font(LiquidTypography.caption2)
                    .foregroundStyle(LiquidColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: LiquidSpacing.sm)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(category.accentColor)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? category.accentColor : LiquidColors.glassBorder,
                    lineWidth: isSelected ? Self.selectedBorderWidth : 1
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .animation(.snappy(duration: 0.18), value: isSelected)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                .fill(category.accentColor.opacity(0.18))
                .frame(width: Self.iconSize, height: Self.iconSize)

            Image(systemName: preset.sfSymbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(category.accentColor)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Derived Copy

    /// "H.264 · 1080p · 20 Mbps" style line.
    private var summaryLine: String {
        let resolution = preset.config.resolution == .custom
            ? "\(preset.config.outputWidth)x\(preset.config.outputHeight)"
            : preset.config.resolution.label
        let codec = preset.config.codec.displayName
        let bitrate = String(format: "%.0f Mbps", preset.config.effectiveBitrateMbps)
        return "\(codec) · \(resolution) · \(bitrate)"
    }

    /// "~128 MB · ~45s" style line.
    private var metaLine: String {
        "\(estimatedSizeString) · \(estimatedDurationString)"
    }

    private var estimatedSizeString: String {
        let duration = max(estimatedDurationSeconds, 1.0)
        let mbps = preset.config.effectiveBitrateMbps
        let sizeMB = (mbps / 8.0) * duration
        if sizeMB >= 1024 {
            return String(format: "~%.2f GB", sizeMB / 1024.0)
        }
        return String(format: "~%.0f MB", sizeMB)
    }

    private var estimatedDurationString: String {
        let seconds = Int(estimatedDurationSeconds.rounded())
        if seconds < 60 { return "~\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return remaining > 0 ? "~\(minutes)m \(remaining)s" : "~\(minutes)m"
    }
}

#Preview {
    VStack(spacing: LiquidSpacing.md) {
        ExportPresetCard(
            preset: ExportPresetService.builtInPresets[0],
            category: .quick,
            isSelected: false,
            estimatedDurationSeconds: 60,
            onTap: {}
        )
        ExportPresetCard(
            preset: ExportPresetService.builtInPresets[2],
            category: .pro,
            isSelected: true,
            estimatedDurationSeconds: 120,
            onTap: {}
        )
    }
    .padding()
    .background(LiquidColors.background)
}
