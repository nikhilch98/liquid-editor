// BackupRepositoryProtocol.swift
// LiquidEditor
//
// Protocol for backup archive management operations.
// Enables dependency injection and testability for backup/restore.

import Foundation

// MARK: - BackupRepositoryProtocol

/// Protocol for creating, validating, and restoring project backups.
///
/// Implementations handle building ZIP archives containing the project
/// JSON and optionally media files, along with a `BackupManifest` for
/// integrity verification.
///
/// All I/O methods are async and throw `RepositoryError` on failure.
///
/// References:
/// - `BackupManifest` from Models/Project/BackupManifest.swift
/// - `BackupValidationResult` from Models/Project/BackupManifest.swift
/// - `Project` from Models/Project/Project.swift
/// - `RepositoryError` from Repositories/RepositoryError.swift
protocol BackupRepositoryProtocol: Sendable {

    /// Create a backup archive for a project.
    ///
    /// Builds a ZIP archive containing the project JSON, manifest,
    /// and optionally all referenced media files.
    ///
    /// - Parameters:
    ///   - project: The project to back up.
    ///   - includeMedia: Whether to include media files in the archive.
    /// - Returns: URL of the created archive file.
    /// - Throws: `RepositoryError.encodingFailed` if serialization fails,
    ///   `RepositoryError.ioError` if archive creation fails,
    ///   `RepositoryError.insufficientStorage` if disk space is low.
    func createBackup(project: Project, includeMedia: Bool) async throws -> URL

    /// Load the manifest from a backup archive without restoring it.
    ///
    /// Used for previewing backup contents before restoring.
    ///
    /// - Parameter archiveURL: URL of the backup archive.
    /// - Returns: The parsed backup manifest.
    /// - Throws: `RepositoryError.invalidPath` if the URL is inaccessible,
    ///   `RepositoryError.corruptedData` if the manifest cannot be parsed.
    func loadManifest(archiveURL: URL) async throws -> BackupManifest

    /// Validate a backup archive for integrity and compatibility.
    ///
    /// Checks the manifest, verifies checksums of included media files,
    /// and reports any version compatibility warnings.
    ///
    /// - Parameter archiveURL: URL of the backup archive.
    /// - Returns: Validation result with status, warnings, and errors.
    /// - Throws: `RepositoryError.invalidPath` if the URL is inaccessible,
    ///   `RepositoryError.ioError` if the archive cannot be read.
    func validate(archiveURL: URL) async throws -> BackupValidationResult

    /// Restore a project from a backup archive.
    ///
    /// Extracts the project data and media files, assigns a new project ID,
    /// and registers any included media assets.
    ///
    /// - Parameter archiveURL: URL of the backup archive.
    /// - Returns: The restored project (with a new ID).
    /// - Throws: `RepositoryError.corruptedData` if the archive is invalid,
    ///   `RepositoryError.decodingFailed` if project data cannot be parsed,
    ///   `RepositoryError.insufficientStorage` if disk space is low.
    func restore(archiveURL: URL) async throws -> Project

    /// List all backup archives in the app's backup directory.
    ///
    /// Returns each archive URL paired with its parsed manifest.
    ///
    /// - Returns: Array of (URL, manifest) tuples, sorted by backup date (newest first).
    /// - Throws: `RepositoryError.ioError` if the backup directory cannot be read.
    func listBackups() async throws -> [(url: URL, manifest: BackupManifest)]

    /// Delete a backup archive.
    ///
    /// - Parameter archiveURL: URL of the backup archive to delete.
    /// - Throws: `RepositoryError.notFound` if the archive does not exist,
    ///   `RepositoryError.ioError` if deletion fails.
    func deleteBackup(archiveURL: URL) async throws

    /// Get the file size of a backup archive in bytes.
    ///
    /// - Parameter archiveURL: URL of the backup archive.
    /// - Returns: Archive size in bytes.
    /// - Throws: `RepositoryError.notFound` if the archive does not exist,
    ///   `RepositoryError.ioError` if the file attributes cannot be read.
    func backupSize(archiveURL: URL) async throws -> Int
}
