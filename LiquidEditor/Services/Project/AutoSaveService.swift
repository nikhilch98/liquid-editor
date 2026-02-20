// AutoSaveService.swift
// LiquidEditor
//
// Debounced auto-save with concurrent write prevention and save state tracking.
//
// Provides a higher-level auto-save interface that:
// - Debounces rapid changes (2-second delay) using Task.sleep
// - Tracks save state for UI indicators ("saving..." / "saved")
// - Prevents concurrent writes via actor-like serialization
// - Supports forced immediate saves

import Foundation
import Observation
import os

// MARK: - AutoSaveState

/// Save state for UI indicators.
///
/// Drives visual feedback (e.g., a "Saving..." badge) in the editor toolbar.
enum AutoSaveState: String, Sendable {
    /// All changes are saved.
    case saved
    /// Changes pending save (debounce timer running).
    case unsaved
    /// Currently writing to disk.
    case saving
    /// Save failed.
    case error
}

// MARK: - AutoSaveService

/// High-level auto-save service with debouncing and state tracking.
///
/// Uses `@Observable` for SwiftUI integration and `@MainActor` isolation
/// to safely drive UI state like the "saving..." indicator.
///
/// ## Usage
/// ```swift
/// let autoSave = AutoSaveService(
///     projectRepository: container.projectRepository,
///     draftRepository: container.draftRepository
/// )
/// autoSave.scheduleAutoSave(project)
/// ```
///
/// ## Debounce Behavior
/// Calling `scheduleAutoSave(_:)` marks state as `.unsaved` immediately,
/// then waits `debounceDelay` (2 seconds) before performing the actual save.
/// Subsequent calls within the debounce window cancel the pending save and
/// restart the timer.
///
/// ## Concurrent Write Prevention
/// If a save is already in progress (`state == .saving`), new save requests
/// are skipped. The debounce timer ensures rapid edits coalesce into a single
/// disk write.
@Observable
@MainActor
final class AutoSaveService {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "AutoSaveService"
    )

    // MARK: - Configuration

    /// Debounce delay before auto-save triggers (defaults to 2 seconds).
    let debounceDelay: Duration

    // MARK: - Dependencies

    private let projectRepository: any ProjectRepositoryProtocol
    private let draftRepository: any DraftRepositoryProtocol
    private let mediaImportService: MediaImportService?

    // MARK: - Observable State

    /// Current save state for UI binding.
    private(set) var state: AutoSaveState = .saved

    /// Whether a save is currently in progress.
    var isSaving: Bool { state == .saving }

    /// Whether there are unsaved changes.
    var hasUnsavedChanges: Bool { state == .unsaved }

    /// Timestamp of the last successful save.
    private(set) var lastSavedAt: Date?

    // MARK: - Internal State

    /// The currently running debounce task, if any.
    private var debounceTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create an auto-save service with the given repositories.
    ///
    /// - Parameters:
    ///   - projectRepository: Repository for persisting full project data.
    ///   - draftRepository: Repository for saving draft snapshots.
    ///   - mediaImportService: Optional service used to generate project thumbnails on first save.
    ///   - debounceDelay: Delay before auto-save triggers (default: 2 seconds).
    init(
        projectRepository: any ProjectRepositoryProtocol,
        draftRepository: any DraftRepositoryProtocol,
        mediaImportService: MediaImportService? = nil,
        debounceDelay: Duration = .seconds(2)
    ) {
        self.projectRepository = projectRepository
        self.draftRepository = draftRepository
        self.mediaImportService = mediaImportService
        self.debounceDelay = debounceDelay
    }

    // MARK: - Public API

    /// Schedule an auto-save with debouncing.
    ///
    /// Marks state as `.unsaved` immediately, then debounces the actual save
    /// by `debounceDelay`. If called again before the delay elapses, the
    /// previous pending save is cancelled and the timer restarts.
    ///
    /// - Parameter project: The current project state to save.
    func scheduleAutoSave(_ project: Project) {
        state = .unsaved

        // Cancel any existing debounce timer.
        debounceTask?.cancel()

        debounceTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: self.debounceDelay)
            } catch {
                // Task was cancelled (new save scheduled or cancelAutoSave called).
                return
            }

            await self.performSave(project, reason: .autoSave)
        }
    }

    /// Force an immediate save, bypassing the debounce timer.
    ///
    /// Cancels any pending debounce and performs the save synchronously
    /// (from the caller's perspective - the actual I/O is still async).
    ///
    /// - Parameters:
    ///   - project: The current project state to save.
    ///   - reason: The trigger reason for this save (defaults to `.manualSave`).
    func saveImmediately(
        _ project: Project,
        reason: DraftTriggerReason = .manualSave
    ) async {
        debounceTask?.cancel()
        debounceTask = nil
        await performSave(project, reason: reason)
    }

    /// Cancel any pending auto-save without saving.
    func cancelAutoSave() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Mark state as saved (e.g., after an external save).
    func markSaved() {
        state = .saved
        lastSavedAt = Date()
    }

    /// Reset to initial state.
    ///
    /// Cancels any pending auto-save and resets all state.
    func reset() {
        debounceTask?.cancel()
        debounceTask = nil
        state = .saved
        lastSavedAt = nil
    }

    // MARK: - Private

    /// Perform the actual save operation.
    ///
    /// Skips if a save is already in progress to prevent concurrent writes.
    ///
    /// - Parameters:
    ///   - project: The project to save.
    ///   - reason: Why this save was triggered.
    private func performSave(
        _ project: Project,
        reason: DraftTriggerReason
    ) async {
        // Prevent concurrent writes.
        guard state != .saving else { return }

        state = .saving

        do {
            // Save to main project file.
            try await projectRepository.save(project)

            // Also save a draft for crash recovery.
            try await draftRepository.saveDraft(
                projectId: project.id,
                project: project,
                reason: reason
            )

            // Generate thumbnail on first save if missing (best-effort).
            await generateThumbnailIfNeeded(for: project)

            state = .saved
            lastSavedAt = Date()
        } catch {
            Self.logger.error("Auto-save failed: \(error.localizedDescription)")
            state = .error
        }
    }

    /// Generate and persist a thumbnail for the project if one does not already exist on disk.
    ///
    /// Silently no-ops if `mediaImportService` is nil, the source video path is empty,
    /// or the thumbnail file already exists. All failures are swallowed so thumbnail
    /// generation never interrupts the save flow.
    private func generateThumbnailIfNeeded(for project: Project) async {
        guard let importService = mediaImportService,
              !project.sourceVideoPath.isEmpty else { return }

        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!

        let thumbnailRelativePath = "Thumbnails/\(project.id).jpg"
        let thumbnailURL = documentsDir.appendingPathComponent(thumbnailRelativePath)

        // Skip if thumbnail already exists on disk.
        guard !FileManager.default.fileExists(atPath: thumbnailURL.path) else { return }

        let sourceURL = documentsDir.appendingPathComponent(project.sourceVideoPath)
        guard let thumbData = try? await importService.generateThumbnail(
            path: sourceURL.path, maxSize: 320
        ) else { return }

        let thumbnailsDir = documentsDir.appendingPathComponent("Thumbnails")
        try? FileManager.default.createDirectory(
            at: thumbnailsDir, withIntermediateDirectories: true
        )
        guard (try? thumbData.write(to: thumbnailURL)) != nil else { return }

        // Persist the updated thumbnailPath back to the project record.
        try? await projectRepository.save(project.with(thumbnailPath: thumbnailRelativePath))
    }
}
