// WhatsNewSheet.swift
// LiquidEditor
//
// Post-update release-notes sheet. Presents a bulleted list of new features
// after the app has been updated to a new `CFBundleShortVersionString`.
// Paired with `WhatsNewTracker`, which compares the last-shown version
// stored in `UserDefaults` to the current bundle version.
//
// Introduced for S2-27 (premium UI redesign: What's New sheet after update).

import SwiftUI

// MARK: - WhatsNewEntry

/// A single bullet entry in the What's New sheet.
struct WhatsNewEntry: Identifiable, Sendable, Hashable {

    /// SwiftUI stable identifier.
    let id: UUID

    /// SF Symbol shown at the start of the row.
    let icon: String

    /// Short feature title (one line).
    let title: String

    /// Longer description (2-3 lines max).
    let detail: String

    init(id: UUID = UUID(), icon: String, title: String, detail: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.detail = detail
    }
}

// MARK: - WhatsNewSheet

/// Sheet listing what's new in the current version.
///
/// Content is injectable so release-note copy can be updated without
/// touching the view (default list is `WhatsNewSheet.defaultEntries`).
struct WhatsNewSheet: View {

    /// Version number displayed in the title (e.g. "1.2").
    var version: String = "1.2"

    /// Release-note entries rendered as a bulleted list.
    var entries: [WhatsNewEntry] = WhatsNewSheet.defaultEntries

    /// Invoked when the user taps the Continue CTA (after dismiss).
    var onContinue: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
                    header
                    ForEach(entries) { entry in
                        WhatsNewRow(entry: entry)
                    }
                }
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.xxl)
            }
            .safeAreaInset(edge: .bottom) {
                continueButton
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close What's New")
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text("What's New in \(version)")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.leading)
            Text("Fresh features and polish, just for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Continue CTA

    private var continueButton: some View {
        VStack {
            Button {
                onContinue()
                dismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: LiquidSpacing.cornerLarge))
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Defaults

    /// Default release-note entries for v1.2 (update in lockstep with the
    /// `MARKETING_VERSION` bump in `project.yml`).
    static let defaultEntries: [WhatsNewEntry] = [
        WhatsNewEntry(
            icon: "sparkles",
            title: "Redesigned Library",
            detail: "A fresh grid with richer thumbnails, sort options, and quality stars."
        ),
        WhatsNewEntry(
            icon: "rectangle.stack.badge.plus",
            title: "Starter Templates",
            detail: "Kickstart a project with curated templates for Reels, trailers, and vlogs."
        ),
        WhatsNewEntry(
            icon: "wand.and.stars",
            title: "Smarter Onboarding",
            detail: "A cleaner welcome experience with sample projects ready to explore."
        ),
        WhatsNewEntry(
            icon: "person.crop.circle.badge.checkmark",
            title: "You Tab",
            detail: "Profile, settings, and support shortcuts all in one place."
        ),
        WhatsNewEntry(
            icon: "bolt.heart",
            title: "Performance Polish",
            detail: "Faster launch, smoother scrubbing, and snappier playback."
        ),
    ]
}

// MARK: - WhatsNewRow

/// Single bullet row: icon + title + detail.
private struct WhatsNewRow: View {
    let entry: WhatsNewEntry

    var body: some View {
        HStack(alignment: .top, spacing: LiquidSpacing.md) {
            Image(systemName: entry.icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
                Text(entry.title)
                    .font(.headline)
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - WhatsNewTracker

/// Decides whether the What's New sheet should be presented.
///
/// Compares the current bundle `CFBundleShortVersionString` against the last
/// version for which the sheet was acknowledged (stored in `UserDefaults`).
/// When they differ, `shouldPresent()` returns `true` and callers should
/// show `WhatsNewSheet`; `markPresented()` updates the stored version.
///
/// Isolation: `@MainActor` because the canonical call site is SwiftUI view
/// lifecycle (`.onAppear`).
@MainActor
final class WhatsNewTracker {

    /// Shared singleton used by the app entry point.
    static let shared = WhatsNewTracker()

    /// UserDefaults key for the last acknowledged version.
    private static let lastShownVersionKey = "whatsNewLastShownVersion"

    /// Injectable defaults (defaults to `.standard`).
    private let defaults: UserDefaults

    /// Injectable bundle (defaults to `.main`) for test contexts.
    private let bundle: Bundle

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
    }

    // MARK: - Queries

    /// Current app marketing version, or "0.0" if unknown.
    var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// Version the sheet was most recently shown for, or `nil` if never.
    var lastShownVersion: String? {
        defaults.string(forKey: Self.lastShownVersionKey)
    }

    /// Whether the sheet should be shown on this launch.
    ///
    /// Returns `true` when the current bundle version differs from the
    /// last-shown version -- this includes the first launch after install.
    func shouldPresent() -> Bool {
        lastShownVersion != currentVersion
    }

    // MARK: - Mutations

    /// Record that the sheet has been shown for the current version.
    func markPresented() {
        defaults.set(currentVersion, forKey: Self.lastShownVersionKey)
    }

    /// Reset for testing / QA.
    func resetForTesting() {
        defaults.removeObject(forKey: Self.lastShownVersionKey)
    }
}

// MARK: - Preview

#Preview {
    WhatsNewSheet()
}
