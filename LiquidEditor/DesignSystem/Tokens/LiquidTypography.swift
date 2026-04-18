// LiquidTypography.swift
// LiquidEditor
//
// SF Pro font styles matching iOS 26 Human Interface Guidelines.
// Uses the system font with rounded design for the Liquid Glass aesthetic.

import SwiftUI

// MARK: - LiquidTypography

/// iOS 26 Liquid Glass design system typography tokens.
///
/// All fonts use `Font.system()` to leverage SF Pro with appropriate
/// weight and design parameters. The `.rounded` design complements
/// the Liquid Glass visual language.
///
/// Usage:
/// ```swift
/// Text("Projects")
///     .font(LiquidTypography.largeTitle)
///
/// Text("Edit video")
///     .font(LiquidTypography.bodyMedium)
/// ```
enum LiquidTypography {

    // MARK: - Large Titles

    /// Extra-large title for hero sections (34pt bold rounded).
    static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// Large title light variant for subtler emphasis.
    static let largeTitleLight = Font.system(.largeTitle, design: .rounded, weight: .regular)

    // MARK: - Titles

    /// Title style (28pt bold rounded).
    static let title = Font.system(.title, design: .rounded, weight: .bold)

    /// Title 2 style (22pt semibold rounded).
    static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)

    /// Title 3 style (20pt semibold rounded).
    static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)

    // MARK: - Headline

    /// Headline style (17pt semibold).
    static let headline = Font.system(.headline, design: .default, weight: .semibold)

    /// Headline emphasized style (17pt bold).
    static let headlineBold = Font.system(.headline, design: .default, weight: .bold)

    // MARK: - Body

    /// Body text (17pt regular).
    static let body = Font.system(.body, design: .default, weight: .regular)

    /// Body medium weight (17pt medium).
    static let bodyMedium = Font.system(.body, design: .default, weight: .medium)

    /// Body semibold (17pt semibold).
    static let bodySemibold = Font.system(.body, design: .default, weight: .semibold)

    // MARK: - Callout

    /// Callout text (16pt regular).
    static let callout = Font.system(.callout, design: .default, weight: .regular)

    /// Callout medium (16pt medium).
    static let calloutMedium = Font.system(.callout, design: .default, weight: .medium)

    // MARK: - Subheadline

    /// Subheadline text (15pt regular).
    static let subheadline = Font.system(.subheadline, design: .default, weight: .regular)

    /// Subheadline medium (15pt medium).
    static let subheadlineMedium = Font.system(.subheadline, design: .default, weight: .medium)

    /// Subheadline semibold (15pt semibold).
    static let subheadlineSemibold = Font.system(.subheadline, design: .default, weight: .semibold)

    // MARK: - Footnote

    /// Footnote text (13pt regular).
    static let footnote = Font.system(.footnote, design: .default, weight: .regular)

    /// Footnote medium (13pt medium).
    static let footnoteMedium = Font.system(.footnote, design: .default, weight: .medium)

    /// Footnote semibold (13pt semibold).
    static let footnoteSemibold = Font.system(.footnote, design: .default, weight: .semibold)

    // MARK: - Caption

    /// Caption text (12pt regular).
    static let caption = Font.system(.caption, design: .default, weight: .regular)

    /// Caption medium (12pt medium).
    static let captionMedium = Font.system(.caption, design: .default, weight: .medium)

    /// Caption 2 text (11pt regular).
    static let caption2 = Font.system(.caption2, design: .default, weight: .regular)

    /// Caption 2 semibold (11pt semibold).
    static let caption2Semibold = Font.system(.caption2, design: .default, weight: .semibold)

    // MARK: - Monospaced (Timecodes, Metrics)

    /// Monospaced body for timecodes and numeric displays (17pt).
    static let monoBody = Font.system(.body, design: .monospaced, weight: .regular)

    /// Monospaced caption for small numeric displays (12pt).
    static let monoCaption = Font.system(.caption, design: .monospaced, weight: .medium)

    /// Monospaced subheadline for timeline displays (15pt).
    static let monoSubheadline = Font.system(.subheadline, design: .monospaced, weight: .medium)

    // MARK: - Premium UI scale (2026-04-18 redesign)

    /// Project name, sheet titles.
    enum Display {
        static let font = Font.system(size: 28, weight: .semibold, design: .rounded)
    }

    /// Nav titles, primary labels.
    enum Title {
        static let font = Font.system(size: 17, weight: .semibold, design: .default)
    }

    /// Tool labels, menu items.
    enum Body {
        static let font = Font.system(size: 15, weight: .regular, design: .default)
    }

    /// Metadata, aspect chip.
    enum Caption {
        static let font = Font.system(size: 12, weight: .medium, design: .default)
    }

    /// All timecodes — signature Edits cue.
    enum Mono {
        static let font = Font.system(size: 13, weight: .medium, design: .monospaced)
    }

    /// Playhead time chip.
    enum MonoLarge {
        static let font = Font.system(size: 18, weight: .semibold, design: .monospaced)
    }
}
