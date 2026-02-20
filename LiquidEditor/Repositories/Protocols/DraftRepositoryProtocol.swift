// DraftRepositoryProtocol.swift
// LiquidEditor
//
// Protocol for draft/auto-save management operations.
// Enables dependency injection and testability for draft persistence.

import Foundation

// MARK: - DraftRepositoryProtocol

/// Protocol for managing draft auto-saves and crash recovery.
///
/// Implementations persist project drafts in a ring buffer (up to
/// `DraftMetadata.maxDrafts` slots) and track session lifecycle for
/// crash recovery. If `cleanShutdown` is `false` when a project is
/// reopened, the user should be offered crash recovery.
///
/// All I/O methods are async and throw `RepositoryError` on failure.
///
/// References:
/// - `DraftMetadata` from Models/Project/DraftMetadata.swift
/// - `DraftEntry` from Models/Project/DraftMetadata.swift
/// - `DraftTriggerReason` from Models/Project/DraftMetadata.swift
/// - `Project` from Models/Project/Project.swift
/// - `RepositoryError` from Repositories/RepositoryError.swift
protocol DraftRepositoryProtocol: Sendable {

    /// Save a draft of the project to the ring buffer.
    ///
    /// Writes the project data to the next slot in the ring buffer
    /// and updates the draft metadata with a new `DraftEntry`.
    ///
    /// - Parameters:
    ///   - projectId: The project's unique identifier.
    ///   - project: The current project state to save.
    ///   - reason: What triggered this draft save.
    /// - Throws: `RepositoryError.encodingFailed` if serialization fails,
    ///   `RepositoryError.ioError` if the write fails.
    func saveDraft(projectId: String, project: Project, reason: DraftTriggerReason) async throws

    /// Load the most recent draft for a project.
    ///
    /// Returns `nil` if no drafts exist for this project.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: The most recently saved project state, or `nil`.
    /// - Throws: `RepositoryError.decodingFailed` if stored data is unreadable.
    func loadLatestDraft(projectId: String) async throws -> Project?

    /// Load a specific draft by ring buffer index.
    ///
    /// Returns `nil` if the slot has not been written to yet.
    ///
    /// - Parameters:
    ///   - projectId: The project's unique identifier.
    ///   - index: The ring buffer slot index (0 to `DraftMetadata.maxDrafts - 1`).
    /// - Returns: The project state from that slot, or `nil`.
    /// - Throws: `RepositoryError.decodingFailed` if stored data is unreadable,
    ///   `RepositoryError.validationFailed` if the index is out of range.
    func loadDraft(projectId: String, index: Int) async throws -> Project?

    /// Load draft metadata for a project.
    ///
    /// Returns `nil` if no draft metadata exists (project was never auto-saved).
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: The draft metadata, or `nil`.
    /// - Throws: `RepositoryError.decodingFailed` if stored data is unreadable.
    func loadMetadata(projectId: String) async throws -> DraftMetadata?

    /// List all draft entries for a project, sorted by save time (newest first).
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: Array of draft entries.
    /// - Throws: `RepositoryError.ioError` if the draft directory cannot be read.
    func listDrafts(projectId: String) async throws -> [DraftEntry]

    /// Delete all drafts for a project.
    ///
    /// Removes draft data files and the metadata file. Called when a
    /// project is deleted or when the user discards recovery data.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Throws: `RepositoryError.ioError` if deletion fails.
    func deleteDrafts(projectId: String) async throws

    /// Check whether any drafts exist for a project.
    ///
    /// Fast check without loading or decoding draft data.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: `true` if at least one draft exists, `false` otherwise.
    func hasDraft(projectId: String) async -> Bool

    /// Mark the project session as cleanly shut down.
    ///
    /// Called when the user closes the project normally or the app
    /// transitions to background gracefully. Sets `cleanShutdown = true`
    /// in the draft metadata.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Throws: `RepositoryError.ioError` if the metadata update fails.
    func markCleanShutdown(projectId: String) async throws

    /// Mark a new editing session as started.
    ///
    /// Called when the user opens a project. Sets `cleanShutdown = false`
    /// so that a crash before the next clean shutdown can be detected.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Throws: `RepositoryError.ioError` if the metadata update fails.
    func markSessionStarted(projectId: String) async throws

    /// Check whether a project needs crash recovery.
    ///
    /// Returns `true` if drafts exist and the last session did not
    /// shut down cleanly (`cleanShutdown == false`).
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: `true` if crash recovery should be offered.
    /// - Throws: `RepositoryError.decodingFailed` if metadata is unreadable.
    func needsCrashRecovery(projectId: String) async throws -> Bool
}
