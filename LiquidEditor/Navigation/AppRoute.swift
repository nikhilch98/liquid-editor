// AppRoute.swift
// LiquidEditor
//
// Enum defining all navigation routes in the app.
// Used with NavigationPath for type-safe SwiftUI navigation.

import Foundation

// MARK: - AppRoute

/// All top-level navigation destinations in the app.
///
/// Conforms to `Hashable` for use with SwiftUI `NavigationPath`.
/// Each case represents a distinct screen or destination.
///
/// Usage:
/// ```swift
/// NavigationStack(path: $coordinator.path) {
///     ProjectLibraryView()
///         .navigationDestination(for: AppRoute.self) { route in
///             switch route {
///             case .projectLibrary:
///                 ProjectLibraryView()
///             case .editor(let projectId):
///                 EditorView(projectId: projectId)
///             case .settings:
///                 SettingsView()
///             case .onboarding:
///                 OnboardingView()
///             case .fullscreenPreview:
///                 FullscreenPreviewView()
///             case .mediaBrowser:
///                 MediaBrowserView()
///             }
///         }
/// }
/// ```
enum AppRoute: Hashable {
    /// Project library / home screen showing all projects.
    case projectLibrary

    /// Video editor for a specific project.
    ///
    /// - Parameter projectId: Unique identifier of the project to edit.
    case editor(projectId: String)

    /// App settings screen.
    case settings

    /// First-launch onboarding flow.
    case onboarding

    /// Fullscreen video preview mode.
    case fullscreenPreview

    /// Media browser for importing assets.
    case mediaBrowser
}
