// EmptyStateView.swift
// LiquidEditor
//
// P1-8: Reusable empty-state template per spec §9.6.
//
// Layout (center-aligned column):
//   hero glyph (48pt) -> title -> subtitle -> primary CTA -> escape-hatch link
//
// Instances used by:
// - Library zero-state ("No projects yet" + "+ New Project" + "try a Template")
// - Empty timeline ("Drag media or tap to import")
// - Search no-results ("No matches for <query>" + "clear filters")
// - Media picker empty ("No photos here" + switch source)
// - Export destinations empty ("Add a cloud destination")

import SwiftUI

// MARK: - EmptyStateView

/// A center-aligned empty-state panel.
///
/// The `systemImage` is rendered in a 48pt amber gradient container.
/// `primaryAction` is the amber pill CTA; `secondaryAction` is the
/// tertiary-text "escape-hatch" link shown beneath.
struct EmptyStateView: View {

    // MARK: - Inputs

    let systemImage: String
    let title: String
    let subtitle: String
    let primaryAction: EmptyStateAction?
    let secondaryAction: EmptyStateAction?

    // MARK: - Init

    init(
        systemImage: String,
        title: String,
        subtitle: String,
        primaryAction: EmptyStateAction? = nil,
        secondaryAction: EmptyStateAction? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            heroGlyph
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(LiquidColors.Text.primary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(LiquidColors.Text.secondary)
                .multilineTextAlignment(.center)
            if let primary = primaryAction {
                ctaButton(primary)
                    .padding(.top, 4)
            }
            if let secondary = secondaryAction {
                escapeHatchLink(secondary)
            }
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    private var heroGlyph: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(LiquidColors.Accent.amber)
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LiquidColors.Accent.amberGlow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LiquidColors.Accent.amber.opacity(0.3), lineWidth: 1)
            )
    }

    private func ctaButton(_ action: EmptyStateAction) -> some View {
        Button(action: action.handler) {
            Text(action.label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(LiquidColors.Text.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(LiquidColors.Accent.amber)
                )
        }
        .buttonStyle(.plain)
    }

    private func escapeHatchLink(_ action: EmptyStateAction) -> some View {
        Button(action: action.handler) {
            Text(action.label)
                .font(.footnote)
                .foregroundStyle(LiquidColors.Accent.amber)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EmptyStateAction

/// Label + closure pair for primary / secondary actions on an empty state.
struct EmptyStateAction {
    let label: String
    let handler: () -> Void

    init(_ label: String, handler: @escaping () -> Void) {
        self.label = label
        self.handler = handler
    }
}

// MARK: - Previews

#Preview("Library empty") {
    EmptyStateView(
        systemImage: "plus.rectangle.on.rectangle",
        title: "No projects yet",
        subtitle: "Import a clip or pick a template\nto start editing.",
        primaryAction: EmptyStateAction("+ New Project") { },
        secondaryAction: EmptyStateAction("or try a Template") { }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LiquidColors.Canvas.base)
    .preferredColorScheme(.dark)
}

#Preview("Search no-results") {
    EmptyStateView(
        systemImage: "magnifyingglass",
        title: "No matches",
        subtitle: "No matches for \"sunset\". Try different keywords.",
        primaryAction: nil,
        secondaryAction: EmptyStateAction("Clear filters") { }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LiquidColors.Canvas.base)
    .preferredColorScheme(.dark)
}
