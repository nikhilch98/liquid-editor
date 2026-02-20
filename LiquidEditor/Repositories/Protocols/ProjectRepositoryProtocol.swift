// ProjectRepositoryProtocol.swift
// LiquidEditor
//
// Protocol for project persistence operations.
// Enables dependency injection and testability for project storage.

import Foundation

// MARK: - ProjectRepositoryProtocol

/// Protocol for persisting and retrieving video editing projects.
///
/// Implementations handle encoding/decoding `Project` instances to disk,
/// managing lightweight `ProjectMetadata` for fast listing, and supporting
/// operations like rename, duplicate, and delete.
///
/// All I/O methods are async and throw `RepositoryError` on failure.
///
/// References:
/// - `Project` from Models/Project/Project.swift
/// - `ProjectMetadata` from Models/Project/ProjectMetadata.swift
/// - `RepositoryError` from Repositories/RepositoryError.swift
protocol ProjectRepositoryProtocol: Sendable {

    /// Persist a project to storage.
    ///
    /// Creates a new record or overwrites an existing one with the same ID.
    /// The modification timestamp on the project should already be updated
    /// by the caller (via `project.touched()`).
    ///
    /// - Parameter project: The project to save.
    /// - Throws: `RepositoryError.encodingFailed` if serialization fails,
    ///   `RepositoryError.ioError` if the write fails,
    ///   `RepositoryError.insufficientStorage` if disk space is low.
    func save(_ project: Project) async throws

    /// Load a full project by its identifier.
    ///
    /// Returns the complete project including timeline clips and all
    /// editing state.
    ///
    /// - Parameter id: The project's unique identifier.
    /// - Returns: The loaded project.
    /// - Throws: `RepositoryError.notFound` if no project with that ID exists,
    ///   `RepositoryError.decodingFailed` if the stored data is unreadable.
    func load(id: String) async throws -> Project

    /// Load lightweight metadata for a single project.
    ///
    /// Faster than `load(id:)` because it skips timeline clip data.
    ///
    /// - Parameter id: The project's unique identifier.
    /// - Returns: The project's metadata.
    /// - Throws: `RepositoryError.notFound` if no project with that ID exists.
    func loadMetadata(id: String) async throws -> ProjectMetadata

    /// List metadata for all projects, sorted by modification date (newest first).
    ///
    /// Used for rendering the project library without loading full project data.
    ///
    /// - Returns: Array of project metadata entries.
    /// - Throws: `RepositoryError.ioError` if the storage directory cannot be read.
    func listMetadata() async throws -> [ProjectMetadata]

    /// Delete a project and its associated files.
    ///
    /// Removes the project JSON, metadata, and any project-specific caches.
    /// Does **not** remove shared media assets (use `MediaAssetRepositoryProtocol`
    /// for that).
    ///
    /// - Parameter id: The project's unique identifier.
    /// - Throws: `RepositoryError.notFound` if no project with that ID exists,
    ///   `RepositoryError.ioError` if deletion fails.
    func delete(id: String) async throws

    /// Check whether a project with the given ID exists in storage.
    ///
    /// This is a fast check that does not load or decode the project.
    ///
    /// - Parameter id: The project's unique identifier.
    /// - Returns: `true` if the project exists, `false` otherwise.
    func exists(id: String) async -> Bool

    /// Rename a project.
    ///
    /// Updates the project name and modification timestamp in storage.
    ///
    /// - Parameters:
    ///   - id: The project's unique identifier.
    ///   - newName: The new display name.
    /// - Throws: `RepositoryError.notFound` if no project with that ID exists,
    ///   `RepositoryError.validationFailed` if the name is empty.
    func rename(id: String, newName: String) async throws

    /// Duplicate a project with a new ID and name.
    ///
    /// Creates a deep copy of the project data under a new identifier.
    /// Media asset references are shared (not duplicated on disk).
    ///
    /// - Parameters:
    ///   - id: The source project's unique identifier.
    ///   - newId: The identifier for the duplicated project.
    ///   - newName: The display name for the duplicated project.
    /// - Returns: The newly created project.
    /// - Throws: `RepositoryError.notFound` if the source does not exist,
    ///   `RepositoryError.duplicateEntry` if `newId` is already in use.
    func duplicate(id: String, newId: String, newName: String) async throws -> Project
}
