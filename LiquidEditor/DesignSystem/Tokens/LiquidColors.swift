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

    // MARK: - Legacy aliases (premium-redesign migration)
    //
    // The following top-level tokens used to map to iOS system colors
    // (systemBackground, .label, .systemRed, etc.) so views rendered
    // with iOS dynamic colors regardless of brand palette. The premium
    // 2026-04-18 redesign locks the app to a dark-only, near-black +
    // bone-white + amber palette (see `Canvas`, `Text`, `Accent` below),
    // but ~50 view files still reference the legacy names. Rather than
    // rewrite every call-site at once, each legacy token now aliases
    // its premium counterpart so the brand palette renders app-wide.

    // Backgrounds
    static let background = Canvas.base                              // #07070A
    static let secondaryBackground = Canvas.raised                   // #0F0F12
    static let tertiaryBackground = Canvas.elev                      // #1A1A1F

    // Surfaces
    static let surface = Canvas.raised
    static let glassSurface = Canvas.raised.opacity(0.70)
    static let glassSurfaceProminent = Canvas.raised.opacity(0.85)
    static let glassSurfaceSubtle = Canvas.raised.opacity(0.50)

    // Brand / Accent
    static let primary = Accent.amber
    static let secondary = Text.secondary
    static let accent = Accent.amber

    // Text
    static let textPrimary = Text.primary
    static let textSecondary = Text.secondary
    static let textTertiary = Text.tertiary
    static let textQuaternary = Text.tertiary.opacity(0.60)

    // Separators (spec §2.1: hairline stroke / prominent stroke)
    static let separator = Color.white.opacity(0.06)
    static let separatorOpaque = Color.white.opacity(0.12)

    // Semantic Colors
    static let error = Accent.destructive                            // #E5534A
    static let success = Accent.success                              // #6BCB77
    static let warning = Accent.warning                              // #E5A14A
    static let info = Accent.amber

    // Fill Colors
    static let fillPrimary = Canvas.raised
    static let fillSecondary = Canvas.elev
    static let fillTertiary = Canvas.elev.opacity(0.80)
    static let fillQuaternary = Canvas.elev.opacity(0.50)

    // Glass Border (routes to hairline/prominent stroke tokens)
    static let glassBorder = Color.white.opacity(0.06)
    static let glassBorderProminent = Color.white.opacity(0.12)

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

    // MARK: - Premium UI scopes (2026-04-18 redesign)

    /// Canvas layers used by the editor shell and sheets.
    /// See docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §2.1.
    enum Canvas {
        /// Deepest layer — app background behind chrome. #07070A.
        static let base = Color(red: 7 / 255, green: 7 / 255, blue: 10 / 255)
        /// Preview + timeline background. #0F0F12.
        static let raised = Color(red: 15 / 255, green: 15 / 255, blue: 18 / 255)
        /// Elevated cell — tool buttons, segmented items, filled chips. #1A1A1F.
        static let elev = Color(red: 26 / 255, green: 26 / 255, blue: 31 / 255)
    }

    /// Text colors tuned for the Edits-style bone-white on near-black palette.
    enum Text {
        /// Primary labels / titles. #F3EEE6.
        static let primary = Color(red: 243 / 255, green: 238 / 255, blue: 230 / 255)
        /// Captions / inactive tabs. #9C9A93.
        static let secondary = Color(red: 156 / 255, green: 154 / 255, blue: 147 / 255)
        /// Disabled / hints. #5A5852.
        static let tertiary = Color(red: 90 / 255, green: 88 / 255, blue: 82 / 255)
        /// Text on amber surfaces. #07070A.
        static let onAccent = Color(red: 7 / 255, green: 7 / 255, blue: 10 / 255)
    }

    /// Single active-state accent plus its glow and a destructive-action color.
    enum Accent {
        /// Mustard-amber active accent. #E6B340.
        static let amber = Color(red: 230 / 255, green: 179 / 255, blue: 64 / 255)
        /// Amber glow @ 37% alpha — used for halos behind selected clips.
        static let amberGlow = Color(
            red: 230 / 255, green: 179 / 255, blue: 64 / 255
        ).opacity(0.37)
        /// Destructive confirmation color. #E5534A.
        static let destructive = Color(red: 229 / 255, green: 83 / 255, blue: 74 / 255)
        /// Positive / completion-state accent. #6BCB77.
        static let success = Color(red: 107 / 255, green: 203 / 255, blue: 119 / 255)
        /// Warning / caution-state accent. #E5A14A.
        static let warning = Color(red: 229 / 255, green: 161 / 255, blue: 74 / 255)
    }
}
