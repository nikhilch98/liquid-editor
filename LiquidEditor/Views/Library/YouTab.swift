// YouTab.swift
// LiquidEditor
//
// The "You" tab rendered inside the Library: surfaces profile, app
// preferences, and help shortcuts. Destination views are stubbed for now
// and will be wired in follow-up tasks.
//
// Introduced for S2-21 (premium UI redesign: You tab with profile and
// app-settings links).

import SwiftUI

// MARK: - YouTab

/// The Library "You" tab listing profile and app-level navigation rows.
///
/// Each row is a `NavigationLink` that pushes a placeholder destination
/// via `YouTabRouteDestination`, which concrete Settings/Account/Help
/// screens will replace as they land.
struct YouTab: View {

    /// Optional display name; falls back to a localized placeholder.
    var displayName: String = "Your Account"

    /// Optional user initials shown in the avatar (defaults to "YA").
    var initials: String = "YA"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LiquidSpacing.lg) {
                    profileHeader
                    accountSection
                    appSection
                    supportSection
                }
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.lg)
            }
            .navigationTitle("You")
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        HStack(spacing: LiquidSpacing.md) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                Text("Manage profile & preferences")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(LiquidSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(style: .regular, cornerRadius: LiquidSpacing.cornerLarge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile: \(displayName)")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: 56, height: 56)
            Text(initials)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Row Sections

    private var accountSection: some View {
        YouTabSection(title: "Account") {
            YouTabRow(
                icon: "person.crop.circle",
                label: "Account",
                destination: .account
            )
            YouTabRow(
                icon: "creditcard",
                label: "Subscription",
                destination: .subscription
            )
        }
    }

    private var appSection: some View {
        YouTabSection(title: "App") {
            YouTabRow(
                icon: "gearshape",
                label: "Settings",
                destination: .settings
            )
            YouTabRow(
                icon: "lock.shield",
                label: "Privacy",
                destination: .privacy
            )
            YouTabRow(
                icon: "paintbrush",
                label: "Appearance",
                destination: .appearance
            )
        }
    }

    private var supportSection: some View {
        YouTabSection(title: "Support") {
            YouTabRow(
                icon: "questionmark.circle",
                label: "Help & Support",
                destination: .help
            )
            YouTabRow(
                icon: "info.circle",
                label: "About",
                destination: .about
            )
        }
    }
}

// MARK: - YouTabSection

/// Grouped rounded card section used within the You tab.
private struct YouTabSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, LiquidSpacing.sm)

            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous))
        }
    }
}

// MARK: - YouTabRow

/// A single navigation row: icon + label + chevron, pushes a destination.
private struct YouTabRow: View {
    let icon: String
    let label: String
    let destination: YouTabRoute

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: LiquidSpacing.md) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, alignment: .center)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .navigationDestination(for: YouTabRoute.self) { route in
            YouTabRouteDestination(route: route)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Routing

/// Navigation routes pushed from the You tab rows.
///
/// Concrete destinations are stubs until the relevant Settings / Account /
/// Help flows land (tracked by follow-up spec tasks).
enum YouTabRoute: String, Hashable, CaseIterable {
    case account
    case subscription
    case settings
    case privacy
    case appearance
    case help
    case about
}

/// Placeholder destination view for `YouTabRoute` entries.
///
/// Each case renders a simple "TODO" placeholder so navigation is functional
/// while the detailed screens are implemented.
private struct YouTabRouteDestination: View {
    let route: YouTabRoute

    var body: some View {
        // TODO: Replace with concrete screens once available:
        //   - .account       -> AccountView
        //   - .subscription  -> SubscriptionView
        //   - .settings      -> SettingsView
        //   - .privacy       -> PrivacyView
        //   - .appearance    -> AppearanceView
        //   - .help          -> HelpSupportView
        //   - .about         -> AboutView
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "hammer")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(route.rawValue.capitalized)
                .font(.title2.weight(.semibold))
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(route.rawValue.capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    YouTab()
}
