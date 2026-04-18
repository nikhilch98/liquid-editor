// LiquidEditorApp.swift
// LiquidEditor
//
// Main app entry point. Initializes the repository container,
// sets up navigation routing, and wires together the onboarding,
// project library, editor, settings, and fullscreen preview screens.
//
// Uses AppCoordinator for centralized navigation state management.

import os
import SwiftUI

// MARK: - LiquidEditorApp

@main
struct LiquidEditorApp: App {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "LiquidEditorApp"
    )

    // MARK: - State

    /// IP16-4: UIApplicationDelegate adaptor. Provides a hook for
    /// multi-window scene configuration and external-display
    /// notifications without leaving the SwiftUI App lifecycle.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Scene phase for background/inactive lifecycle events.
    @Environment(\.scenePhase) private var scenePhase

    /// Repository container (shared singleton for production).
    private let repositories = RepositoryContainer.shared

    /// Navigation coordinator for app-wide routing.
    @State private var coordinator = AppCoordinator()

    /// Settings view model, shared so onboarding completion persists.
    @State private var settingsViewModel: SettingsViewModel?

    /// Whether the onboarding flow should be presented.
    @State private var showOnboarding = false

    /// Whether the fullscreen preview is presented.
    @State private var showFullscreenPreview = false

    /// Total duration for fullscreen preview (microseconds).
    @State private var previewTotalDuration: Int64 = 0

    /// Error from the last auto-save attempt, surfaced for UI observation.
    @State private var autoSaveError: Error?

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $coordinator.path) {
                ProjectLibraryView(
                    projectRepository: repositories.projectRepository,
                    mediaAssetRepository: repositories.mediaAssetRepository,
                    mediaImportService: ServiceContainer.shared.mediaImportService
                )
                .navigationDestination(for: AppRoute.self) { route in
                    destinationView(for: route)
                }
            }
            .environment(coordinator)
            .preferredColorScheme(.dark)
            .onAppear {
                checkOnboarding()
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    settingsViewModel?.completeOnboarding()
                    showOnboarding = false
                }
            }
            .fullScreenCover(isPresented: $showFullscreenPreview) {
                FullscreenPreviewView(
                    totalDuration: previewTotalDuration,
                    player: nil
                )
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhase(phase)
            }
            // IP16-4: multi-window — secondary scenes opened via
            // `MultiWindowController.openProjectInNewWindow(_:)` carry
            // an NSUserActivity whose userInfo names the target project.
            .onContinueUserActivity(MultiWindowController.openProjectActivityType) { activity in
                guard let projectId = activity.userInfo?[MultiWindowController.projectIdKey] as? String else {
                    return
                }
                coordinator.navigateToEditor(projectId: projectId)
            }
        }
    }

    // MARK: - Navigation Destinations

    /// Resolve a navigation route to a destination view.
    ///
    /// - Parameter route: The route to resolve.
    /// - Returns: The destination view for the route.
    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .projectLibrary:
            ProjectLibraryView(
                projectRepository: repositories.projectRepository,
                mediaAssetRepository: repositories.mediaAssetRepository,
                mediaImportService: ServiceContainer.shared.mediaImportService
            )

        case .editor(let projectId):
            editorView(for: projectId)

        case .settings:
            SettingsView(
                preferencesRepository: repositories.preferencesRepository
            )

        case .onboarding:
            OnboardingView {
                settingsViewModel?.completeOnboarding()
            }

        case .fullscreenPreview:
            FullscreenPreviewView(
                totalDuration: previewTotalDuration,
                player: nil
            )

        case .mediaBrowser:
            // MediaBrowserView requires a ProjectLibraryViewModel.
            // Create a standalone instance for the media browser route.
            MediaBrowserView(
                viewModel: ProjectLibraryViewModel(
                    projectRepository: repositories.projectRepository,
                    mediaAssetRepository: repositories.mediaAssetRepository
                )
            )
            .navigationTitle("Media")
        }
    }

    /// Create an editor view for the given project ID.
    ///
    /// Loads the project from the project repository. If loading fails
    /// (e.g., project not yet saved or corrupted), falls back to a
    /// placeholder project so the editor can still open gracefully.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: An `EditorView` configured for the project.
    @ViewBuilder
    private func editorView(for projectId: String) -> some View {
        EditorProjectLoader(
            projectId: projectId,
            projectRepository: repositories.projectRepository
        )
    }

    // MARK: - Onboarding Check

    /// Check whether the onboarding flow should be displayed.
    ///
    /// Reads the `hasSeenOnboarding` preference and shows the
    /// onboarding full-screen cover if the user has not completed it.
    private func checkOnboarding() {
        let vm = SettingsViewModel(preferencesRepository: repositories.preferencesRepository)
        vm.loadSettings()
        settingsViewModel = vm

        if vm.shouldShowOnboarding() {
            showOnboarding = true
        }
    }

    // MARK: - Scene Phase Handling

    /// Handle app lifecycle transitions.
    ///
    /// - Parameter phase: The new scene phase.
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            // Trigger auto-save when entering background
            triggerAutoSave()
        case .inactive:
            // Pause playback when app becomes inactive
            pausePlayback()
        case .active:
            break
        @unknown default:
            break
        }
    }

    /// Trigger auto-save for the current project (if enabled).
    ///
    /// Loads the active project from the repository and performs an
    /// immediate save via `AutoSaveService`. Silently returns if auto-save
    /// is disabled, no editor is active, or the project cannot be loaded.
    private func triggerAutoSave() {
        let prefs = repositories.preferencesRepository
        let autoSaveEnabled = prefs.bool(forKey: "autoSaveEnabled") ?? true
        guard autoSaveEnabled else { return }

        guard let projectId = coordinator.currentEditorProjectId else { return }

        let projectRepo = repositories.projectRepository
        let draftRepo = repositories.draftRepository
        let engine = ServiceContainer.shared.playbackEngine

        Task {
            // Pause playback before saving.
            await engine.pause()

            do {
                let project = try await projectRepo.load(id: projectId)
                let autoSaveService = AutoSaveService(
                    projectRepository: projectRepo,
                    draftRepository: draftRepo,
                    mediaImportService: ServiceContainer.shared.mediaImportService
                )
                await autoSaveService.saveImmediately(project, reason: .appBackground)
                autoSaveError = nil
            } catch {
                Self.logger.error("Auto-save failed for project \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                autoSaveError = error
            }
        }
    }

    /// Pause any active playback.
    private func pausePlayback() {
        let engine = ServiceContainer.shared.playbackEngine
        Task {
            await engine.pause()
        }
    }
}

// MARK: - EditorProjectLoader

/// Async wrapper that loads a project from the repository before
/// presenting the `EditorView`.
///
/// Shows a loading indicator while the project is being fetched.
/// Falls back to a placeholder project if loading fails.
private struct EditorProjectLoader: View {

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "EditorProjectLoader"
    )

    let projectId: String
    let projectRepository: any ProjectRepositoryProtocol

    @State private var loadedProject: Project?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let project = loadedProject {
                EditorView(project: project)
            } else if isLoading {
                ProgressView("Loading project...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .preferredColorScheme(.dark)
            } else {
                // Fallback: create a minimal project so the editor still opens.
                EditorView(project: fallbackProject)
            }
        }
        .task {
            await loadProject()
        }
    }

    /// Attempt to load the project from the repository.
    private func loadProject() async {
        defer { isLoading = false }
        do {
            let project = try await projectRepository.load(id: projectId)
            loadedProject = project
        } catch {
            Self.logger.error("Failed to load project \(projectId, privacy: .public): \(error.localizedDescription, privacy: .public) — using fallback project")
            loadedProject = nil
        }
    }

    /// Fallback project when repository loading fails.
    private var fallbackProject: Project {
        Project(
            id: projectId,
            name: "Untitled Project",
            sourceVideoPath: ""
        )
    }
}
