// LiquidSpacing.swift
// LiquidEditor
//
// Consistent spacing scale and corner radius tokens for the
// iOS 26 Liquid Glass design system.

import SwiftUI

// MARK: - LiquidSpacing

/// iOS 26 Liquid Glass design system spacing tokens.
///
/// Provides a consistent 8-point-based spacing scale and corner radius
/// presets aligned with iOS 26 Human Interface Guidelines.
///
/// Usage:
/// ```swift
/// VStack(spacing: LiquidSpacing.md) {
///     Text("Title")
///     Text("Subtitle")
/// }
/// .padding(LiquidSpacing.lg)
///
/// RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
/// ```
enum LiquidSpacing {

    // MARK: - Spacing Scale

    /// Extra-extra-small spacing: 2pt.
    static let xxs: CGFloat = 2

    /// Extra-small spacing: 4pt.
    static let xs: CGFloat = 4

    /// Small spacing: 8pt.
    static let sm: CGFloat = 8

    /// Medium spacing: 12pt.
    static let md: CGFloat = 12

    /// Large spacing: 16pt.
    static let lg: CGFloat = 16

    /// Extra-large spacing: 20pt.
    static let xl: CGFloat = 20

    /// Extra-extra-large spacing: 24pt.
    static let xxl: CGFloat = 24

    /// Extra-extra-extra-large spacing: 32pt.
    static let xxxl: CGFloat = 32

    // MARK: - Corner Radius

    /// Small corner radius: 8pt. For buttons and small cards.
    static let cornerSmall: CGFloat = 8

    /// Medium corner radius: 12pt. For cards and panels.
    static let cornerMedium: CGFloat = 12

    /// Large corner radius: 16pt. For dialogs and sheets.
    static let cornerLarge: CGFloat = 16

    /// Extra-large corner radius: 20pt. For full-width panels and Liquid Glass surfaces.
    static let cornerXLarge: CGFloat = 20

    /// Circular corner radius: 9999pt. For pill shapes and circular elements.
    static let cornerCircular: CGFloat = 9999

    // MARK: - Padding Presets

    /// Compact padding for tight layouts.
    static let paddingCompact = EdgeInsets(
        top: sm,
        leading: sm,
        bottom: sm,
        trailing: sm
    )

    /// Standard padding for most content areas.
    static let paddingStandard = EdgeInsets(
        top: lg,
        leading: lg,
        bottom: lg,
        trailing: lg
    )

    /// Spacious padding for hero sections and prominent content.
    static let paddingSpacious = EdgeInsets(
        top: xxl,
        leading: xxl,
        bottom: xxl,
        trailing: xxl
    )

    /// Horizontal padding for list rows and cells.
    static let paddingHorizontal = EdgeInsets(
        top: 0,
        leading: lg,
        bottom: 0,
        trailing: lg
    )

    /// Vertical padding for section headers.
    static let paddingSectionHeader = EdgeInsets(
        top: xl,
        leading: lg,
        bottom: sm,
        trailing: lg
    )

    // MARK: - Icon Sizes

    /// Small icon size: 16pt.
    static let iconSmall: CGFloat = 16

    /// Medium icon size: 20pt.
    static let iconMedium: CGFloat = 20

    /// Large icon size: 24pt.
    static let iconLarge: CGFloat = 24

    /// Extra-large icon size: 32pt.
    static let iconXLarge: CGFloat = 32

    // MARK: - Touch Targets

    /// Minimum touch target size per iOS HIG: 44pt.
    static let minTouchTarget: CGFloat = 44

    /// Standard button height: 50pt.
    static let buttonHeight: CGFloat = 50

    /// Compact button height: 36pt.
    static let buttonHeightCompact: CGFloat = 36

    /// Tab bar height: 49pt.
    static let tabBarHeight: CGFloat = 49

    /// Navigation bar height: 44pt.
    static let navigationBarHeight: CGFloat = 44

    /// Timeline track height: 56pt.
    static let timelineTrackHeight: CGFloat = 56
}
