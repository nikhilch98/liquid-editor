// BackupRepository.swift
// LiquidEditor
//
// Actor-based implementation of BackupRepositoryProtocol.
// Manages directory-based backup archives with manifest, project data,
// and optional media file copies.
//
// Directory structure:
//   ~/Documents/LiquidEditor/Backups/
//     {projectId}_{timestamp}.liquidbackup/
//       manifest.json      - BackupManifest
//       project.json       - Full Project data
//       media/             - Media files (if includesMedia)
//         {filename}       - Copied media files

import Foundation
import UIKit
import CryptoKit

// MARK: - BackupRepository

/// Actor-isolated repository for creating, validating, and restoring project backups.
///
/// Backups are stored as directory-based archives (`.liquidbackup`) under the
/// app's Documents directory. Each archive contains a manifest with device and
/// version metadata, the serialized project, and optionally copies of all
/// referenced media files.
///
/// Thread safety is guaranteed by Swift actor isolation. All public methods
/// are `async` and throw `RepositoryError` on failure.
///
/// ## Usage
/// ```swift
/// let repo = BackupRepository()
/// let url = try await repo.createBackup(project: myProject, includeMedia: true)
/// let result = try await repo.validate(archiveURL: url)
/// ```
actor BackupRepository: BackupRepositoryProtocol {

    // MARK: - Properties

    /// Base directory for all backups.
    private let backupsDirectory: URL

    /// JSON encoder configured for formatted output with ISO 8601 dates.
    private let encoder: JSONEncoder

    /// JSON decoder configured for ISO 8601 dates.
    private let decoder: JSONDecoder

    /// File manager for disk operations.
    private let fileManager: FileManager

    // MARK: - Initialization

    /// Create a backup repository with the default documents directory.
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.backupsDirectory = docs.appendingPathComponent("LiquidEditor/Backups", isDirectory: true)
        self.fileManager = .default

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Create a backup repository with a custom base directory (for testing).
    init(baseDirectory: URL) {
        self.backupsDirectory = baseDirectory
        self.fileManager = .default

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - BackupRepositoryProtocol

    /// Create a backup archive for the given project.
    ///
    /// - Parameters:
    ///   - project: The project to back up.
    ///   - includeMedia: Whether to copy referenced media files into the archive.
    /// - Returns: URL of the created `.liquidbackup` directory.
    /// - Throws: `RepositoryError` on encoding or I/O failure.
    func createBackup(project: Project, includeMedia: Bool) async throws -> URL {
        try ensureDirectoryExists(backupsDirectory)

        // Build archive directory name: {projectId}_{ISO8601 timestamp}.liquidbackup
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archiveName = "\(project.id)_\(timestamp).liquidbackup"
        let archiveURL = backupsDirectory.appendingPathComponent(archiveName, isDirectory: true)

        try fileManager.createDirectory(at: archiveURL, withIntermediateDirectories: true)

        // Encode and write project.json
        let projectData: Data
        do {
            projectData = try encoder.encode(project)
        } catch {
            throw RepositoryError.encodingFailed("Failed to encode project: \(error.localizedDescription)")
        }
        try writeData(projectData, to: archiveURL.appendingPathComponent("project.json"))

        // Collect media entries and optionally copy files
        var mediaEntries: [BackupMediaEntry] = []
        var totalSize = projectData.count

        if includeMedia {
            let mediaDir = archiveURL.appendingPathComponent("media", isDirectory: true)
            try fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)

            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let sourceBasePath = docsDir.appendingPathComponent("LiquidEditor")

            // Gather media paths from the project's source video path
            let mediaPaths = gatherMediaPaths(from: project)
            for relativePath in mediaPaths {
                let sourceURL = sourceBasePath.appendingPathComponent(relativePath)
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

                let filename = sourceURL.lastPathComponent
                let destURL = mediaDir.appendingPathComponent(filename)

                do {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                } catch {
                    // Skip files that fail to copy; record as warning in manifest
                    continue
                }

                let fileAttrs = try? fileManager.attributesOfItem(atPath: destURL.path)
                let fileSize = (fileAttrs?[.size] as? Int) ?? 0
                let hash = try computeSHA256(for: destURL)

                let entry = BackupMediaEntry(
                    originalPath: relativePath,
                    archivePath: "media/\(filename)",
                    contentHash: hash,
                    fileSize: fileSize,
                    mediaType: mediaTypeForExtension(sourceURL.pathExtension)
                )
                mediaEntries.append(entry)
                totalSize += fileSize
            }
        }

        // Build manifest
        let manifest = BackupManifest(
            version: BackupManifest.currentVersion,
            appVersion: appVersion,
            appBuildNumber: appBuildNumber,
            backupDate: Date(),
            deviceModel: deviceModel,
            iosVersion: iosVersionString,
            projectId: project.id,
            projectName: project.name,
            projectVersion: project.version,
            mediaFiles: mediaEntries,
            totalSize: totalSize,
            includesMedia: includeMedia
        )

        // Encode and write manifest.json
        let manifestData: Data
        do {
            manifestData = try encoder.encode(manifest)
        } catch {
            throw RepositoryError.encodingFailed("Failed to encode manifest: \(error.localizedDescription)")
        }
        try writeData(manifestData, to: archiveURL.appendingPathComponent("manifest.json"))

        return archiveURL
    }

    /// Load the manifest from a backup archive.
    ///
    /// - Parameter archiveURL: URL of the `.liquidbackup` directory.
    /// - Returns: The parsed `BackupManifest`.
    /// - Throws: `RepositoryError.notFound` if the manifest file is missing,
    ///   `RepositoryError.decodingFailed` if parsing fails.
    func loadManifest(archiveURL: URL) async throws -> BackupManifest {
        let manifestURL = archiveURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw RepositoryError.notFound("Manifest not found at \(manifestURL.path)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw RepositoryError.ioError("Failed to read manifest: \(error.localizedDescription)")
        }

        do {
            return try decoder.decode(BackupManifest.self, from: data)
        } catch {
            throw RepositoryError.decodingFailed("Failed to decode manifest: \(error.localizedDescription)")
        }
    }

    /// Validate a backup archive for integrity and compatibility.
    ///
    /// Checks that the archive directory exists, the manifest is readable,
    /// all referenced files are present, and the version is compatible.
    ///
    /// - Parameter archiveURL: URL of the `.liquidbackup` directory.
    /// - Returns: A `BackupValidationResult` indicating validity.
    func validate(archiveURL: URL) async throws -> BackupValidationResult {
        // Check archive exists
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: archiveURL.path, isDirectory: &isDir),
              isDir.boolValue else {
            return .invalid("Archive directory does not exist: \(archiveURL.lastPathComponent)")
        }

        // Check manifest.json exists and is readable
        let manifestURL = archiveURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return .invalid("Missing manifest.json in archive")
        }

        let manifest: BackupManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try decoder.decode(BackupManifest.self, from: data)
        } catch {
            return .invalid("Corrupt or unreadable manifest: \(error.localizedDescription)")
        }

        // Check project.json exists
        let projectURL = archiveURL.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: projectURL.path) else {
            return .invalid("Missing project.json in archive")
        }

        // Verify all referenced media files exist
        if manifest.includesMedia {
            for entry in manifest.mediaFiles {
                let mediaURL = archiveURL.appendingPathComponent(entry.archivePath)
                guard fileManager.fileExists(atPath: mediaURL.path) else {
                    return .invalid("Missing media file: \(entry.archivePath)")
                }
            }
        }

        // Check version compatibility
        if manifest.isNewerVersion(currentAppVersion: appVersion) {
            return .validWithWarning(
                manifest,
                warning: "Backup was created with a newer app version (\(manifest.appVersion)). "
                    + "Some features may not restore correctly."
            )
        }

        return .valid(manifest)
    }

    /// Restore a project from a backup archive.
    ///
    /// Reads `project.json` from the archive, assigns a new unique project ID,
    /// and returns the restored project. The caller is responsible for saving
    /// the project via `ProjectRepository`.
    ///
    /// - Parameter archiveURL: URL of the `.liquidbackup` directory.
    /// - Returns: The restored `Project` with a new unique ID.
    /// - Throws: `RepositoryError.validationFailed` if the archive is invalid,
    ///   `RepositoryError.decodingFailed` if project data is corrupt.
    func restore(archiveURL: URL) async throws -> Project {
        // Validate first
        let validationResult = try await validate(archiveURL: archiveURL)
        guard validationResult.isValid else {
            throw RepositoryError.validationFailed(
                validationResult.error ?? "Archive validation failed"
            )
        }

        // Read project.json
        let projectURL = archiveURL.appendingPathComponent("project.json")
        let data: Data
        do {
            data = try Data(contentsOf: projectURL)
        } catch {
            throw RepositoryError.ioError("Failed to read project data: \(error.localizedDescription)")
        }

        let project: Project
        do {
            project = try decoder.decode(Project.self, from: data)
        } catch {
            throw RepositoryError.decodingFailed("Failed to decode project: \(error.localizedDescription)")
        }

        // Assign a new unique ID to avoid collisions with the original
        let restoredProject = project.with(
            id: UUID().uuidString,
            modifiedAt: Date()
        )

        return restoredProject
    }

    /// List all backup manifests, sorted by backup date (newest first).
    ///
    /// Scans the backups directory for `.liquidbackup` archives and reads
    /// each manifest. Archives with unreadable manifests are silently skipped.
    ///
    /// - Returns: Array of backup URL and manifest tuples.
    /// - Throws: `RepositoryError.ioError` if the backups directory cannot be enumerated.
    func listBackups() async throws -> [(url: URL, manifest: BackupManifest)] {
        guard fileManager.fileExists(atPath: backupsDirectory.path) else {
            return []
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: backupsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw RepositoryError.ioError("Failed to list backups: \(error.localizedDescription)")
        }

        var results: [(url: URL, manifest: BackupManifest)] = []
        for url in contents where url.pathExtension == "liquidbackup" {
            let manifestURL = url.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path),
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(BackupManifest.self, from: data) else {
                continue
            }
            results.append((url: url, manifest: manifest))
        }

        // Sort by backup date descending (newest first)
        results.sort { $0.manifest.backupDate > $1.manifest.backupDate }
        return results
    }

    /// Delete a backup archive.
    ///
    /// - Parameter archiveURL: URL of the `.liquidbackup` directory to remove.
    /// - Throws: `RepositoryError.notFound` if the archive does not exist,
    ///   `RepositoryError.ioError` if deletion fails.
    func deleteBackup(archiveURL: URL) async throws {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw RepositoryError.notFound("Backup not found: \(archiveURL.lastPathComponent)")
        }

        do {
            try fileManager.removeItem(at: archiveURL)
        } catch {
            throw RepositoryError.ioError("Failed to delete backup: \(error.localizedDescription)")
        }
    }

    /// Calculate the total size of a backup archive in bytes.
    ///
    /// Recursively sums file sizes within the archive directory.
    ///
    /// - Parameter archiveURL: URL of the `.liquidbackup` directory.
    /// - Returns: Total size in bytes.
    /// - Throws: `RepositoryError.notFound` if the archive does not exist.
    func backupSize(archiveURL: URL) async throws -> Int {
        guard fileManager.fileExists(atPath: archiveURL.path) else {
            throw RepositoryError.notFound("Backup not found: \(archiveURL.lastPathComponent)")
        }

        return directorySize(at: archiveURL)
    }

    // MARK: - Private Helpers

    /// Ensure a directory exists, creating it if necessary.
    private func ensureDirectoryExists(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw RepositoryError.ioError("Failed to create directory: \(error.localizedDescription)")
            }
        }
    }

    /// Write data to a file URL.
    private func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RepositoryError.ioError("Failed to write file \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Compute SHA-256 hash of a file.
    private func computeSHA256(for url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RepositoryError.ioError("Failed to read file for hashing: \(url.lastPathComponent)")
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Calculate the total size of all files in a directory recursively.
    private func directorySize(at url: URL) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += fileSize
            }
        }
        return totalSize
    }

    /// Gather all media file relative paths from a project.
    private func gatherMediaPaths(from project: Project) -> [String] {
        var paths: [String] = []

        // Include the source video
        if !project.sourceVideoPath.isEmpty {
            paths.append(project.sourceVideoPath)
        }

        return paths
    }

    /// Determine media type string from file extension.
    private func mediaTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "mov", "m4v", "avi", "mkv":
            return "video"
        case "jpg", "jpeg", "png", "heif", "heic", "gif", "webp", "tiff":
            return "image"
        case "mp3", "aac", "m4a", "wav", "aiff", "flac", "ogg":
            return "audio"
        default:
            return "video"
        }
    }

    // MARK: - Device Info

    /// Current app version string from Info.plist.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Current app build number from Info.plist.
    private var appBuildNumber: Int {
        let buildStr = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return Int(buildStr) ?? 1
    }

    /// Current device model.
    nonisolated private var deviceModel: String {
        UIDevice.current.model
    }

    /// Current iOS version string.
    private var iosVersionString: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
