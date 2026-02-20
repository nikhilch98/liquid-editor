// AppCoordinator.swift
// LiquidEditor
//
// Central navigation coordinator managing NavigationPath and sheet state.
// Uses @Observable for automatic SwiftUI view updates.

import SwiftUI
import os

// MARK: - ActiveSheet

/// Enum representing all possible modal sheet presentations.
///
/// Each case corresponds to a distinct editor panel or modal
/// that can be presented as a sheet over the current content.
enum ActiveSheet: Identifiable, Equatable {
    /// Export settings and progress sheet.
    case export

    /// Color grading controls panel.
    case colorGrading

    /// Video effects browser and controls.
    case videoEffects

    /// Transition picker and editor.
    case transitions

    /// Audio mixer and effects panel.
    case audio

    /// Text overlay editor.
    case textEditor

    /// Sticker/emoji picker.
    case stickerPicker

    /// Track management panel (reorder, toggle visibility, etc.).
    case trackManagement

    /// Speed control panel (constant speed, speed ramps).
    case speedControl

    /// Per-clip volume control.
    case volumeControl

    /// Crop and transform editor.
    case crop

    /// Person selection for tracking-based effects.
    case personSelection

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .export: "export"
        case .colorGrading: "colorGrading"
        case .videoEffects: "videoEffects"
        case .transitions: "transitions"
        case .audio: "audio"
        case .textEditor: "textEditor"
        case .stickerPicker: "stickerPicker"
        case .trackManagement: "trackManagement"
        case .speedControl: "speedControl"
        case .volumeControl: "volumeControl"
        case .crop: "crop"
        case .personSelection: "personSelection"
        }
    }
}

// MARK: - AppCoordinator

/// Central navigation coordinator for the app.
///
/// Manages the `NavigationPath` for push/pop navigation and
/// `ActiveSheet` for modal sheet presentations. Observed by
/// SwiftUI views via `@Observable`.
///
/// Usage:
/// ```swift
/// @State private var coordinator = AppCoordinator()
///
/// NavigationStack(path: $coordinator.path) {
///     ProjectLibraryView()
///         .navigationDestination(for: AppRoute.self) { route in
///             destinationView(for: route)
///         }
/// }
/// .sheet(item: $coordinator.activeSheet) { sheet in
///     sheetView(for: sheet)
/// }
/// .environment(coordinator)
/// ```
@MainActor
@Observable
final class AppCoordinator {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "AppCoordinator"
    )

    // MARK: - Navigation State

    /// Navigation path for push/pop navigation.
    var path = NavigationPath()

    /// Currently active modal sheet, or nil if no sheet is presented.
    var activeSheet: ActiveSheet?

    /// The project ID currently open in the editor, or nil if no editor is active.
    ///
    /// Set when navigating to the editor and cleared when popping back.
    /// Used by auto-save to determine which project to persist on background transition.
    private(set) var currentEditorProjectId: String?

    // MARK: - Push Navigation

    /// Navigate to the video editor for a project.
    ///
    /// - Parameter projectId: Unique identifier of the project to open (must be non-empty).
    func navigateToEditor(projectId: String) {
        guard !projectId.isEmpty else {
            Self.logger.warning("Cannot navigate to editor: projectId is empty")
            return
        }
        currentEditorProjectId = projectId
        path.append(AppRoute.editor(projectId: projectId))
    }

    /// Navigate to the app settings screen.
    func navigateToSettings() {
        path.append(AppRoute.settings)
    }

    /// Navigate to the onboarding flow.
    func navigateToOnboarding() {
        path.append(AppRoute.onboarding)
    }

    /// Navigate to fullscreen video preview.
    func navigateToFullscreenPreview() {
        path.append(AppRoute.fullscreenPreview)
    }

    /// Navigate to the media browser.
    func navigateToMediaBrowser() {
        path.append(AppRoute.mediaBrowser)
    }

    /// Push an arbitrary route onto the navigation stack.
    ///
    /// **Important:** This method bypasses typed navigation convenience methods.
    /// When pushing `.editor(projectId:)` directly, ensure `currentEditorProjectId`
    /// is also set manually for auto-save to function correctly. Prefer using
    /// `navigateToEditor(projectId:)` instead.
    ///
    /// - Parameter route: The route to navigate to.
    func push(_ route: AppRoute) {
        path.append(route)
    }

    // MARK: - Pop Navigation

    /// Pop the top route from the navigation stack.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
        // If the path is now empty or only contains non-editor routes,
        // clear the active editor project ID.
        if path.isEmpty {
            currentEditorProjectId = nil
        }
    }

    /// Pop all routes and return to the root view.
    func popToRoot() {
        path = NavigationPath()
        currentEditorProjectId = nil
    }

    // MARK: - Sheet Presentation

    /// Present a modal sheet.
    ///
    /// - Parameter sheet: The sheet to present.
    func presentSheet(_ sheet: ActiveSheet) {
        activeSheet = sheet
    }

    /// Dismiss the currently presented sheet.
    func dismissSheet() {
        activeSheet = nil
    }

    // MARK: - Sheet Convenience Methods

    /// Present the export sheet.
    func presentExport() {
        presentSheet(.export)
    }

    /// Present the color grading panel.
    func presentColorGrading() {
        presentSheet(.colorGrading)
    }

    /// Present the video effects browser.
    func presentVideoEffects() {
        presentSheet(.videoEffects)
    }

    /// Present the transition picker.
    func presentTransitions() {
        presentSheet(.transitions)
    }

    /// Present the audio mixer.
    func presentAudio() {
        presentSheet(.audio)
    }

    /// Present the text editor.
    func presentTextEditor() {
        presentSheet(.textEditor)
    }

    /// Present the sticker picker.
    func presentStickerPicker() {
        presentSheet(.stickerPicker)
    }

    /// Present the track management panel.
    func presentTrackManagement() {
        presentSheet(.trackManagement)
    }

    /// Present the speed control panel.
    func presentSpeedControl() {
        presentSheet(.speedControl)
    }

    /// Present the volume control panel.
    func presentVolumeControl() {
        presentSheet(.volumeControl)
    }

    /// Present the crop editor.
    func presentCrop() {
        presentSheet(.crop)
    }

    /// Present the person selection panel.
    func presentPersonSelection() {
        presentSheet(.personSelection)
    }
}
