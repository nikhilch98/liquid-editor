// ProjectBackupService.swift
// LiquidEditor
//
// Manages versioned backup snapshots of project directories.
// Backups are stored at: <AppSupport>/LiquidEditorBackups/<projectId>/<timestamp>/

import Foundation

// MARK: - ProjectBackupService

/// Manages versioned backup snapshots of project directories.
/// Backups are stored at: <AppSupport>/LiquidEditorBackups/<projectId>/<timestamp>/
actor ProjectBackupService {

    // MARK: - Shared Instance

    static let shared = ProjectBackupService()
    private init() {}

    // MARK: - Dependencies

    private let fileManager = FileManager.default

    // MARK: - Paths

    private func backupsRoot() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("LiquidEditorBackups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func projectBackupsDir(for projectId: String) throws -> URL {
        let dir = try backupsRoot().appendingPathComponent(projectId, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Public API

    /// Creates a timestamped backup snapshot of the given project directory.
    ///
    /// Copies the entire project directory into a new timestamped folder under
    /// `<AppSupport>/LiquidEditorBackups/<projectId>/<timestamp>/project/` and
    /// writes a `manifest.json` alongside it.
    ///
    /// - Parameters:
    ///   - projectId: The project's unique identifier.
    ///   - projectName: The project's display name at the time of backup.
    ///   - projectDirectory: Source URL of the project directory to copy.
    /// - Returns: The manifest describing the backup.
    func createBackup(
        for projectId: String,
        projectName: String,
        projectDirectory: URL
    ) async throws -> BackupManifest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]
        let now = Date()
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-") // safe for filenames

        let backupDir = try projectBackupsDir(for: projectId)
            .appendingPathComponent(timestamp, isDirectory: true)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let destDir = backupDir.appendingPathComponent("project", isDirectory: true)
        try fileManager.copyItem(at: projectDirectory, to: destDir)

        // Collect media file entries from the copied directory
        let mediaFiles = collectMediaEntries(in: destDir)
        let totalSize = mediaFiles.reduce(0) { $0 + $1.fileSize }

        let manifest = BackupManifest(
            version: BackupManifest.currentVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            appBuildNumber: Int(
                Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            ) ?? 1,
            backupDate: now,
            deviceModel: deviceModel(),
            iosVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            projectId: projectId,
            projectName: projectName,
            projectVersion: 1,
            mediaFiles: mediaFiles,
            totalSize: totalSize,
            includesMedia: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: backupDir.appendingPathComponent("manifest.json"))

        return manifest
    }

    /// Lists all backups for a project, sorted newest-first.
    func listBackups(for projectId: String) async -> [BackupManifest] {
        guard let backupDir = try? projectBackupsDir(for: projectId) else { return [] }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return entries.compactMap { dir -> BackupManifest? in
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(BackupManifest.self, from: data)
            else { return nil }
            return manifest
        }
        .sorted { $0.backupDate > $1.backupDate }
    }

    /// Restores a project from a backup, replacing the current project directory contents.
    ///
    /// - Parameters:
    ///   - manifest: The backup manifest identifying the backup to restore.
    ///   - projectDirectory: Destination URL where the project should be restored.
    func restoreBackup(_ manifest: BackupManifest, to projectDirectory: URL) async throws {
        // Locate the backup's project folder relative to the manifest's parent directory.
        // The manifest.backupDate is used to reconstruct the path from the projectId.
        let backupsRootURL = try backupsRoot()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]
        let timestampStr = formatter.string(from: manifest.backupDate)
            .replacingOccurrences(of: ":", with: "-")

        let backupProjectDir = backupsRootURL
            .appendingPathComponent(manifest.projectId)
            .appendingPathComponent(timestampStr)
            .appendingPathComponent("project")

        if fileManager.fileExists(atPath: projectDirectory.path) {
            try fileManager.removeItem(at: projectDirectory)
        }
        try fileManager.copyItem(at: backupProjectDir, to: projectDirectory)
    }

    /// Deletes old backups for a project, keeping only the N most recent.
    ///
    /// - Parameters:
    ///   - projectId: The project's unique identifier.
    ///   - keepCount: Number of recent backups to retain (default: 5).
    func pruneOldBackups(for projectId: String, keepCount: Int = 5) async throws {
        let all = await listBackups(for: projectId)
        guard all.count > keepCount else { return }
        let toDelete = all.dropFirst(keepCount)

        guard let backupDir = try? projectBackupsDir(for: projectId) else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]

        for manifest in toDelete {
            let timestampStr = formatter.string(from: manifest.backupDate)
                .replacingOccurrences(of: ":", with: "-")
            let dir = backupDir.appendingPathComponent(timestampStr)
            try? fileManager.removeItem(at: dir)
        }
    }

    // MARK: - Private Helpers

    /// Collects media file entries from a directory by walking its contents.
    private func collectMediaEntries(in directory: URL) -> [BackupMediaEntry] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [BackupMediaEntry] = []
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi"]
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff"]
        let audioExtensions: Set<String> = ["mp3", "aac", "wav", "m4a", "aiff"]

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true
            else { continue }

            let ext = fileURL.pathExtension.lowercased()
            let mediaType: String
            if videoExtensions.contains(ext) {
                mediaType = "video"
            } else if imageExtensions.contains(ext) {
                mediaType = "image"
            } else if audioExtensions.contains(ext) {
                mediaType = "audio"
            } else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(
                of: directory.path + "/",
                with: ""
            )
            let fileSize = resourceValues.fileSize ?? 0

            entries.append(BackupMediaEntry(
                originalPath: relativePath,
                archivePath: "media/\(fileURL.lastPathComponent)",
                contentHash: "",
                fileSize: fileSize,
                mediaType: mediaType
            ))
        }

        return entries
    }

    /// Returns a simplified device model string.
    private func deviceModel() -> String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { rawPtr -> String in
            let ptr = rawPtr.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        return machine
        #endif
    }
}
