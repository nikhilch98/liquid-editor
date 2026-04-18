// MultiWindowController.swift
// LiquidEditor
//
// IP16-4 (per 2026-04-18 premium UI redesign spec §16 — iPad platform):
// Multi-window activation. Opens a project in a new window scene by
// requesting a `UISceneSession` activation with a carefully-typed
// NSUserActivity payload. The scene delegate inspects this activity
// in `scene(_:willConnectTo:options:)` and routes to the editor.
//
// iPhone: `UIApplication.supportsMultipleScenes` returns false, so
// `requestSceneSessionActivation` silently no-ops. We still expose
// the API — iPhone callers get a benign false return.

import Foundation
import SwiftUI
import UIKit
import os

// MARK: - MultiWindowController

/// Requests new window scenes for project editing.
@MainActor
final class MultiWindowController {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "MultiWindowController"
    )

    // MARK: - Constants

    /// User activity type for opening a project in a new scene.
    ///
    /// Declared in Info.plist under `NSUserActivityTypes` when the
    /// feature ships; kept internal today because the only caller
    /// is in-process.
    static let openProjectActivityType = "com.liquideditor.openProject"

    /// `userInfo` key under the activity for the project ID.
    static let projectIdKey = "projectId"

    // MARK: - Public API

    /// Open the given project in a new window scene.
    ///
    /// On iPad returns immediately after scheduling the activation;
    /// the new scene will be connected asynchronously by `SceneDelegate`.
    /// On iPhone or any device that does not support multiple scenes,
    /// returns `false` and does nothing.
    ///
    /// - Parameter projectId: The project identifier to open.
    /// - Returns: `true` if activation was requested; `false` if the
    ///   device does not support multi-window.
    @discardableResult
    func openProjectInNewWindow(_ projectId: UUID) -> Bool {
        openProjectInNewWindow(projectIdString: projectId.uuidString)
    }

    /// String-ID overload for callers that already have a stringified
    /// project ID (most of the repo uses `String` IDs).
    @discardableResult
    func openProjectInNewWindow(projectIdString: String) -> Bool {
        guard UIApplication.shared.supportsMultipleScenes else {
            Self.logger.info("Multi-window not supported on this device — ignoring open request.")
            return false
        }

        let activity = NSUserActivity(activityType: Self.openProjectActivityType)
        activity.userInfo = [Self.projectIdKey: projectIdString]
        activity.title = "Open Project"

        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil
        ) { error in
            Self.logger.error("Scene activation failed: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    /// Close the scene that currently hosts the given project.
    ///
    /// - Parameter projectId: The project identifier whose scene to
    ///   dismiss.
    func closeProjectWindow(_ projectId: UUID) {
        let sessions = UIApplication.shared.openSessions
        let match = sessions.first { session in
            guard let info = session.stateRestorationActivity?.userInfo,
                  let existing = info[Self.projectIdKey] as? String else {
                return false
            }
            return existing == projectId.uuidString
        }
        guard let match else { return }
        UIApplication.shared.requestSceneSessionDestruction(match, options: nil) { error in
            Self.logger.error("Scene destruction failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
