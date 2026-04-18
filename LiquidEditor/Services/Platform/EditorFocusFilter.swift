// EditorFocusFilter.swift
// LiquidEditor
//
// Focus Filter integration (OS17-7).
//
// Allows the user to install a Focus Filter (via the Settings → Focus
// pane) that customises Liquid Editor's behaviour while a given Focus
// is active. Two capabilities are exposed:
//
//   • hideNotifications — suppress all in-app notification surfaces.
//   • simplifiedUI      — hide non-essential toolbar affordances so the
//                         editor presents a distraction-free surface.
//
// The intent is applied via `FocusFilterController`, a `@MainActor`
// singleton that broadcasts the effective state over `NotificationCenter`.
// Views/view models subscribe to these notifications and react idempotently.
//
// iOS 16+ (SetFocusFilterIntent).

import AppIntents
import Foundation
import SwiftUI
import os

// MARK: - EditorFocusFilter

/// User-installable Focus Filter controlling Liquid Editor appearance
/// while a Focus is active.
struct EditorFocusFilter: SetFocusFilterIntent {

    // MARK: - Intent Metadata

    static let title: LocalizedStringResource = "Liquid Editor Focus"

    static let description: LocalizedStringResource =
        "Customize Liquid Editor while a Focus is active — hide notifications or switch to a simplified editor UI."

    // MARK: - Parameters

    /// Whether to suppress in-app notifications during the Focus.
    @Parameter(
        title: "Hide Notifications",
        description: "Suppress in-app notification banners while this Focus is active.",
        default: false
    )
    var hideNotifications: Bool

    /// Whether to switch the editor into a simplified / distraction-free UI.
    @Parameter(
        title: "Simplified UI",
        description: "Hide non-essential toolbar affordances for a distraction-free editor.",
        default: false
    )
    var simplifiedUI: Bool

    // MARK: - Display

    static var parameterSummary: some ParameterSummary {
        Summary("Focus Mode") {
            \.$hideNotifications
            \.$simplifiedUI
        }
    }

    var displayRepresentation: DisplayRepresentation {
        var subtitleParts: [String] = []
        if hideNotifications { subtitleParts.append("Hide Notifications") }
        if simplifiedUI { subtitleParts.append("Simplified UI") }
        let subtitle = subtitleParts.isEmpty ? "Default" : subtitleParts.joined(separator: " • ")
        return DisplayRepresentation(
            title: "Liquid Editor Focus",
            subtitle: "\(subtitle)"
        )
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusFilterController.shared.apply(
            hideNotifications: hideNotifications,
            simplifiedUI: simplifiedUI
        )
        return .result()
    }
}

// MARK: - FocusFilterController

/// Shared state holder for the active Focus Filter.
///
/// Broadcasts state transitions via `NotificationCenter` so that any
/// SwiftUI view / view model can observe them without coupling to the
/// intent layer.
@MainActor
final class FocusFilterController {

    // MARK: - Singleton

    /// Shared instance. Safe to access from the main actor only.
    static let shared = FocusFilterController()

    // MARK: - Notification Names

    /// Posted whenever the Focus Filter state changes.
    ///
    /// `userInfo`:
    ///   • `"hideNotifications": Bool`
    ///   • `"simplifiedUI": Bool`
    static let didChangeNotification = Notification.Name(
        "com.liquideditor.focusFilter.didChange"
    )

    // MARK: - UserInfo Keys

    /// Key for the `hideNotifications` flag in the notification's `userInfo`.
    static let hideNotificationsKey = "hideNotifications"

    /// Key for the `simplifiedUI` flag in the notification's `userInfo`.
    static let simplifiedUIKey = "simplifiedUI"

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "FocusFilterController"
    )

    // MARK: - State

    /// Whether notifications should be hidden.
    private(set) var hideNotifications: Bool = false

    /// Whether the simplified UI should be shown.
    private(set) var simplifiedUI: Bool = false

    // MARK: - Init

    private init() {}

    // MARK: - Apply

    /// Apply new Focus Filter state and broadcast the change.
    ///
    /// - Parameters:
    ///   - hideNotifications: Whether notifications should be hidden.
    ///   - simplifiedUI: Whether the simplified UI should be shown.
    func apply(hideNotifications: Bool, simplifiedUI: Bool) {
        self.hideNotifications = hideNotifications
        self.simplifiedUI = simplifiedUI

        Self.logger.info(
            "Focus Filter applied — hideNotifications=\(hideNotifications, privacy: .public) simplifiedUI=\(simplifiedUI, privacy: .public)"
        )

        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [
                Self.hideNotificationsKey: hideNotifications,
                Self.simplifiedUIKey: simplifiedUI
            ]
        )
    }

    /// Reset the Focus Filter to the default (all-off) state.
    func reset() {
        apply(hideNotifications: false, simplifiedUI: false)
    }
}
