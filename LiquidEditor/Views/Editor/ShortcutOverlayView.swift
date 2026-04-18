// ShortcutOverlayView.swift
// LiquidEditor
//
// K11-6: Keyboard-shortcut discoverability overlay.
//
// Presents every editor shortcut from `EditorShortcutCatalog` grouped by
// category over a translucent Liquid-Glass background. Dismissable via the
// Escape key.
//
// Design decision: hold-⌘ detection is brittle on iOS/iPadOS and
// iOS-SwiftUI does not expose reliable "modifier-only" events. We therefore
// toggle visibility with a concrete shortcut (⌘?) that is also listed in
// the overlay itself for discoverability, matching what Apple ships in
// macOS-class apps running on iPadOS.

import SwiftUI

// MARK: - ShortcutOverlayView

/// Translucent overlay that enumerates every editor keyboard shortcut
/// grouped by category. Visibility is controlled by a binding owned by
/// the presenter (`EditorView`).
@MainActor
struct ShortcutOverlayView: View {

    // MARK: - Inputs

    /// Whether the overlay is visible. Setting this to `false` dismisses
    /// the overlay.
    @Binding var isVisible: Bool

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimmed, blurred backdrop — tapping anywhere dismisses.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
                header

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: LiquidSpacing.xl) {
                        ForEach(EditorShortcutCatalog.categories, id: \.self) { category in
                            if let entries = EditorShortcutCatalog.grouped[category] {
                                categorySection(title: category, entries: entries)
                            }
                        }
                    }
                    .padding(.vertical, LiquidSpacing.sm)
                }

                footer
            }
            .padding(LiquidSpacing.xl)
            .frame(maxWidth: 560)
            .frame(maxHeight: 640)
            .background(.ultraThinMaterial)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: LiquidSpacing.cornerLarge,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .padding(LiquidSpacing.xl)
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Keyboard shortcuts overlay")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: LiquidSpacing.md) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            Text("Keyboard Shortcuts")
                .font(LiquidTypography.title3)
                .foregroundStyle(.white)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss shortcuts overlay")
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Category Section

    private func categorySection(
        title: String,
        entries: [EditorShortcutCatalog.Entry]
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text(title)
                .font(LiquidTypography.footnoteSemibold)
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    shortcutRow(entry: entry)
                    if entry.id != entries.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.08))
                    }
                }
            }
            .padding(LiquidSpacing.md)
            .background(Color.white.opacity(0.04))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: LiquidSpacing.cornerMedium,
                    style: .continuous
                )
            )
        }
    }

    // MARK: - Shortcut Row

    private func shortcutRow(entry: EditorShortcutCatalog.Entry) -> some View {
        HStack(spacing: LiquidSpacing.md) {
            Text(entry.label)
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.white)

            Spacer()

            Text(entry.displayString)
                .font(LiquidTypography.footnoteSemibold)
                .foregroundStyle(.white)
                .padding(.horizontal, LiquidSpacing.sm)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(
                        cornerRadius: LiquidSpacing.cornerSmall,
                        style: .continuous
                    )
                    .fill(Color.white.opacity(0.12))
                )
        }
        .padding(.vertical, LiquidSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.label), \(entry.displayString)")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Press Esc to close")
                .font(LiquidTypography.caption)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
    }

    // MARK: - Actions

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isVisible = false
        }
    }
}
