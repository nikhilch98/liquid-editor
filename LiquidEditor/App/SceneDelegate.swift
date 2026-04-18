// SceneDelegate.swift
// LiquidEditor
//
// IP16-4 (per 2026-04-18 premium UI redesign spec §16 — iPad platform):
// Multi-window support. SwiftUI's `App` lifecycle already creates one
// scene automatically, but to open additional scenes (via
// `UIApplication.requestSceneSessionActivation`) the app needs an
// explicit `UISceneConfiguration` with a `UISceneDelegate`.
//
// This delegate is intentionally minimal — it simply hosts the same
// EditorView-rooted SwiftUI hierarchy that `LiquidEditorApp.body`
// builds. The AppCoordinator stored inside SwiftUI state means each
// scene gets its own navigation stack automatically.

import SwiftUI
import UIKit

// MARK: - AppDelegate

/// UIApplicationDelegate bridge that registers our `SceneDelegate` with
/// iOS. SwiftUI's `@main App` + `WindowGroup` flow auto-creates a scene
/// delegate, but to plug in a custom `UIWindowSceneDelegate` that can
/// inspect scene activation payloads (for multi-window project open),
/// we need to return a configuration referencing our delegate class
/// from `application(_:configurationForConnecting:options:)`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    // NOTE: We intentionally do NOT override
    // `application(_:configurationForConnecting:)` to set a custom
    // `delegateClass`. SwiftUI's `WindowGroup` supplies its own
    // scene delegate that handles connection and restoration; wiring
    // our own would bypass SwiftUI's scene machinery and break
    // the primary lifecycle.
    //
    // `SceneDelegate` below is retained for future use when we migrate
    // away from `WindowGroup` to explicit scene configurations (e.g.
    // to host a dedicated "preview on external display" scene type).
    // The multi-window request path in `MultiWindowController` works
    // today without this delegate because `WindowGroup` honors
    // `NSUserActivity` payloads via the standard
    // `onContinueUserActivity` modifier.
}

// MARK: - SceneDelegate

/// `UIWindowSceneDelegate` wiring for multi-window iPad support.
///
/// Registered via `INFOPLIST_KEY_UIApplicationSceneManifest_Generation`
/// in `project.yml` and surfaced through `UIApplicationSupportsMultipleScenes`.
///
/// On iPhone this delegate still runs (iOS always instantiates a scene
/// delegate), but new-scene requests from `MultiWindowController`
/// silently no-op because iPhone only ever has one foreground scene.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: - Window

    /// The window associated with this scene.
    var window: UIWindow?

    // MARK: - Scene Connection

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Root view — the hosting controller wraps a minimal SwiftUI
        // stack that mirrors `LiquidEditorApp.body`. The real nav stack
        // (project library → editor) belongs to the SwiftUI side.
        let rootView = SceneRootView(connectionOptions: connectionOptions)
        let hosting = UIHostingController(rootView: rootView)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        self.window = window
    }
}

// MARK: - SceneRootView

/// Root SwiftUI view hosted inside a secondary window scene.
///
/// Kept minimal: reads the scene's activation user-activity and routes
/// to the right screen (library by default, editor when activated with
/// a project ID).
private struct SceneRootView: View {

    let connectionOptions: UIScene.ConnectionOptions

    @State private var coordinator = AppCoordinator()

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ProjectLibraryView(
                projectRepository: RepositoryContainer.shared.projectRepository,
                mediaAssetRepository: RepositoryContainer.shared.mediaAssetRepository,
                mediaImportService: ServiceContainer.shared.mediaImportService
            )
        }
        .environment(coordinator)
        .preferredColorScheme(.dark)
        .onAppear {
            applyUserActivity()
        }
    }

    /// If the scene was activated with a project-open user activity,
    /// push the editor route onto the coordinator.
    private func applyUserActivity() {
        guard let activity = connectionOptions.userActivities.first,
              activity.activityType == MultiWindowController.openProjectActivityType,
              let projectId = activity.userInfo?[MultiWindowController.projectIdKey] as? String else {
            return
        }
        coordinator.navigateToEditor(projectId: projectId)
    }
}
