// DynamicTypeWrap.swift
// LiquidEditor
//
// Dynamic Type breakpoints helper for accessibility-aware chip rows.
// At standard sizes, children lay out horizontally; at .accessibility3
// and above, children wrap to a two-column VStack so very large text
// remains legible without horizontal clipping.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §10.6 (A10-3)

import SwiftUI

// MARK: - DynamicTypeWrappedRow

/// A row container that collapses from a horizontal layout to a stacked
/// two-per-line layout when the user's Dynamic Type size reaches an
/// accessibility size (`.accessibility3` or larger).
///
/// Use for chip rows, segmented-style toolbars, or any control cluster
/// where horizontal scrolling is not desirable and text must remain
/// readable at large sizes.
///
/// ```swift
/// DynamicTypeWrappedRow {
///     ChipView(text: "Trim")
///     ChipView(text: "Split")
///     ChipView(text: "Duplicate")
///     ChipView(text: "Delete")
/// }
/// ```
struct DynamicTypeWrappedRow<Content: View>: View {

    // MARK: - Environment

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - Inputs

    /// Spacing between children in both layouts.
    let spacing: CGFloat

    /// Content builder for the row children.
    @ViewBuilder let content: Content

    // MARK: - Init

    /// Create a wrapped row.
    /// - Parameters:
    ///   - spacing: Spacing between child views. Defaults to `LiquidSpacing.sm`.
    ///   - content: The row content (`@ViewBuilder`).
    init(spacing: CGFloat = LiquidSpacing.sm, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    // MARK: - Body

    var body: some View {
        if dynamicTypeSize >= .accessibility3 {
            // At very large sizes, fall back to a VStack so children can
            // each take a full line without horizontal clipping.
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        } else {
            HStack(spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - View Extension

extension View {

    /// Wrap this view in a Dynamic Type aware container.
    ///
    /// At `.accessibility3` and above, the view is embedded in a
    /// `VStack` so content can reflow vertically; otherwise it is
    /// returned unchanged.
    ///
    /// - Parameter spacing: Vertical spacing when wrapped. Defaults to `LiquidSpacing.sm`.
    /// - Returns: A view that reflows at accessibility sizes.
    func dynamicTypeWrapped(spacing: CGFloat = LiquidSpacing.sm) -> some View {
        modifier(DynamicTypeWrappedModifier(spacing: spacing))
    }
}

// MARK: - DynamicTypeWrappedModifier

/// ViewModifier backing `View.dynamicTypeWrapped(spacing:)`.
private struct DynamicTypeWrappedModifier: ViewModifier {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let spacing: CGFloat

    func body(content: Content) -> some View {
        if dynamicTypeSize >= .accessibility3 {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
