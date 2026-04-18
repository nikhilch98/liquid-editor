// AvatarMenu.swift
// LiquidEditor
//
// Compact circular avatar button rendered in the Library header. Tapping
// opens a native SwiftUI menu with account-related shortcuts.
//
// Introduced for S2-22 (premium UI redesign: avatar menu in Library header).

import SwiftUI

// MARK: - AvatarMenuAction

/// Discrete actions that can be triggered from the avatar menu.
///
/// The menu itself is presentation-only; the owning view decides how to
/// react via the `onAction` callback. This keeps `AvatarMenu` reusable and
/// free of routing logic.
enum AvatarMenuAction: String, Hashable, Sendable, CaseIterable {
    case myAccount
    case signOut
    case switchAccount
    case settings
}

// MARK: - AvatarMenu

/// A 40pt circular avatar button that reveals an account menu on tap.
///
/// - Displays user initials (1-2 characters) or a `person.fill` SF Symbol
///   fallback when `initials` is empty.
/// - Uses the SwiftUI `Menu` API so accessibility, haptics, and keyboard
///   handling come from the platform.
struct AvatarMenu: View {

    /// User-provided initials (typically derived from display name). Empty
    /// string falls back to the `person.fill` SF Symbol.
    var initials: String = ""

    /// Invoked when the user selects a menu entry.
    var onAction: (AvatarMenuAction) -> Void

    var body: some View {
        Menu {
            Button {
                onAction(.myAccount)
            } label: {
                Label("My Account", systemImage: "person.crop.circle")
            }

            Button {
                onAction(.switchAccount)
            } label: {
                // Placeholder: multi-account support is not yet implemented.
                Label("Switch Account", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                onAction(.settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive) {
                onAction(.signOut)
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            avatarCircle
        }
        .accessibilityLabel("Account menu")
        .accessibilityHint("Opens account options")
    }

    // MARK: - Avatar

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Circle()
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            avatarContent
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
    }

    @ViewBuilder
    private var avatarContent: some View {
        let trimmed = initials.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        } else {
            // Cap initials at 2 characters to keep layout predictable.
            Text(String(trimmed.prefix(2)).uppercased())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - Preview

#Preview("Initials") {
    AvatarMenu(initials: "NC") { _ in }
}

#Preview("Fallback") {
    AvatarMenu(initials: "") { _ in }
}
