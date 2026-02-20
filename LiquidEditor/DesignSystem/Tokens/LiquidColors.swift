// LiquidColors.swift
// LiquidEditor
//
// iOS 26 Liquid Glass color palette.
// Uses system colors for automatic dark mode support and accessibility.

import SwiftUI

// MARK: - LiquidColors

/// iOS 26 Liquid Glass design system color tokens.
///
/// All colors use `Color(uiColor:)` or `Color(.system*)` for native
/// system integration, ensuring correct appearance in light/dark mode
/// and accessibility settings.
///
/// Usage:
/// ```swift
/// Text("Hello")
///     .foregroundStyle(LiquidColors.textPrimary)
///
/// Rectangle()
///     .fill(LiquidColors.glassSurface)
/// ```
enum LiquidColors {

    // MARK: - Backgrounds

    /// Primary background color. Adapts to light/dark mode.
    static let background = Color(.systemBackground)

    /// Secondary background for grouped content.
    static let secondaryBackground = Color(.secondarySystemBackground)

    /// Tertiary background for nested grouped content.
    static let tertiaryBackground = Color(.tertiarySystemBackground)

    // MARK: - Surfaces

    /// Elevated surface color for cards and panels.
    static let surface = Color(.secondarySystemGroupedBackground)

    /// Glass surface for Liquid Glass components.
    /// Uses a translucent system material appearance.
    static let glassSurface = Color(.systemBackground).opacity(0.7)

    /// Glass surface with stronger opacity for prominent elements.
    static let glassSurfaceProminent = Color(.systemBackground).opacity(0.85)

    /// Glass surface with lighter opacity for subtle elements.
    static let glassSurfaceSubtle = Color(.systemBackground).opacity(0.5)

    // MARK: - Brand / Accent

    /// Primary brand color.
    static let primary = Color(.systemBlue)

    /// Secondary brand color.
    static let secondary = Color(.systemIndigo)

    /// Accent color for interactive elements and highlights.
    static let accent = Color(.tintColor)

    // MARK: - Text

    /// Primary text color for headings and body text.
    static let textPrimary = Color(.label)

    /// Secondary text color for subtitles and descriptions.
    static let textSecondary = Color(.secondaryLabel)

    /// Tertiary text color for placeholders and hints.
    static let textTertiary = Color(.tertiaryLabel)

    /// Quaternary text color for disabled or very subtle text.
    static let textQuaternary = Color(.quaternaryLabel)

    // MARK: - Separators

    /// Standard separator color for dividers and borders.
    static let separator = Color(.separator)

    /// Opaque separator for contexts where transparency is undesirable.
    static let separatorOpaque = Color(.opaqueSeparator)

    // MARK: - Semantic Colors

    /// Error state color.
    static let error = Color(.systemRed)

    /// Success state color.
    static let success = Color(.systemGreen)

    /// Warning state color.
    static let warning = Color(.systemOrange)

    /// Informational state color.
    static let info = Color(.systemBlue)

    // MARK: - Fill Colors

    /// Primary fill for large shapes.
    static let fillPrimary = Color(.systemFill)

    /// Secondary fill for medium-sized shapes.
    static let fillSecondary = Color(.secondarySystemFill)

    /// Tertiary fill for small shapes.
    static let fillTertiary = Color(.tertiarySystemFill)

    /// Quaternary fill for very subtle elements.
    static let fillQuaternary = Color(.quaternarySystemFill)

    // MARK: - Glass Border

    /// Subtle glass border for Liquid Glass components.
    static let glassBorder = Color(.separator).opacity(0.2)

    /// Prominent glass border for focused/active elements.
    static let glassBorderProminent = Color(.separator).opacity(0.4)

    // MARK: - Timeline Colors

    /// Video clip color on the timeline.
    static let timelineVideo = Color(.systemBlue)

    /// Audio clip color on the timeline.
    static let timelineAudio = Color(.systemGreen)

    /// Text overlay color on the timeline.
    static let timelineText = Color(.systemPurple)

    /// Sticker overlay color on the timeline.
    static let timelineSticker = Color(.systemOrange)

    /// Transition region color on the timeline.
    static let timelineTransition = Color(.systemYellow)

    /// Playhead indicator color.
    static let timelinePlayhead = Color(.systemRed)
}
