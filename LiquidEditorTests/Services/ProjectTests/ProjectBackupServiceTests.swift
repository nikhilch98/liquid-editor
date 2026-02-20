// ProjectBackupServiceTests.swift
// LiquidEditorTests
//
// Tests for ProjectBackupService using Swift Testing.
// Validates backup creation, listing, restore, pruning,
// and edge cases like empty directories and nonexistent projects.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ProjectBackupServiceTests

@Suite("ProjectBackupService Tests")
struct ProjectBackupServiceTests {

    // MARK: - Test Helpers

    /// Unique project ID for test isolation.
    private let testProjectId = "backup-test-\(UUID().uuidString)"

    /// Creates a temporary project directory with sample content.
    /// Returns the temp directory URL and a cleanup closure.
    private func makeTempProjectDir(
        files: [String: String] = ["test.txt": "hello world"]
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        for (name, content) in files {
            try content.write(
                to: tempDir.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        return tempDir
    }

    /// Removes the backup root for the given project ID from Application Support.
    private func cleanupBackups(for projectId: String) {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        let backupsDir = appSupport
            .appendingPathComponent("LiquidEditorBackups")
            .appendingPathComponent(projectId)
        try? FileManager.default.removeItem(at: backupsDir)
    }

    // MARK: - Shared Singleton

    @Test("Shared singleton returns the same instance")
    func sharedSingleton() async {
        let a = ProjectBackupService.shared
        let b = ProjectBackupService.shared
        #expect(a === b)
    }

    // MARK: - Create Backup

    @Test("createBackup produces a manifest with correct project ID and name")
    func createBackupManifestProperties() async throws {
        let projectId = "create-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared
        let manifest = try await service.createBackup(
            for: projectId,
            projectName: "Test Project",
            projectDirectory: projectDir
        )

        #expect(manifest.projectId == projectId)
        #expect(manifest.projectName == "Test Project")
        #expect(manifest.version == BackupManifest.currentVersion)
        #expect(manifest.includesMedia == true)
        #expect(manifest.projectVersion == 1)
    }

    @Test("createBackup writes manifest.json to the backup directory")
    func createBackupWritesManifestFile() async throws {
        let projectId = "manifest-file-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared
        let manifest = try await service.createBackup(
            for: projectId,
            projectName: "Manifest File Test",
            projectDirectory: projectDir
        )

        // Reconstruct backup directory path using the same logic as the service
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withDashSeparatorInDate,
            .withColonSeparatorInTime
        ]
        let timestampStr = formatter.string(from: manifest.backupDate)
            .replacingOccurrences(of: ":", with: "-")

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let backupDir = appSupport
            .appendingPathComponent("LiquidEditorBackups")
            .appendingPathComponent(projectId)
            .appendingPathComponent(timestampStr)

        let manifestURL = backupDir.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        // Verify the project subdirectory was copied
        let projectCopyDir = backupDir.appendingPathComponent("project")
        #expect(FileManager.default.fileExists(atPath: projectCopyDir.path))
    }

    @Test("createBackup with media files populates mediaFiles and totalSize")
    func createBackupWithMediaFiles() async throws {
        let projectId = "media-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir(files: [:])
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        // Write a fake video file to trigger media detection
        let videoData = Data(repeating: 0xFF, count: 1024)
        try videoData.write(to: projectDir.appendingPathComponent("clip.mp4"))

        // Write a fake image file
        let imageData = Data(repeating: 0xAA, count: 512)
        try imageData.write(to: projectDir.appendingPathComponent("thumb.png"))

        let service = ProjectBackupService.shared
        let manifest = try await service.createBackup(
            for: projectId,
            projectName: "Media Project",
            projectDirectory: projectDir
        )

        #expect(manifest.mediaFiles.count == 2)
        #expect(manifest.totalSize > 0)

        let mediaTypes = Set(manifest.mediaFiles.map(\.mediaType))
        #expect(mediaTypes.contains("video"))
        #expect(mediaTypes.contains("image"))
    }

    @Test("createBackup with empty directory succeeds with no media files")
    func createBackupEmptyDirectory() async throws {
        let projectId = "empty-dir-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir(files: [:])
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared
        let manifest = try await service.createBackup(
            for: projectId,
            projectName: "Empty Project",
            projectDirectory: projectDir
        )

        #expect(manifest.projectId == projectId)
        #expect(manifest.mediaFiles.isEmpty)
        #expect(manifest.totalSize == 0)
    }

    @Test("createBackup records backupDate close to current time")
    func createBackupRecordsCurrentDate() async throws {
        let projectId = "date-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let before = Date()
        let service = ProjectBackupService.shared
        let manifest = try await service.createBackup(
            for: projectId,
            projectName: "Date Test",
            projectDirectory: projectDir
        )
        let after = Date()

        #expect(manifest.backupDate >= before)
        #expect(manifest.backupDate <= after)
    }

    // MARK: - List Backups

    @Test("listBackups returns empty array for nonexistent project")
    func listBackupsNonexistentProject() async {
        let projectId = "nonexistent-\(UUID().uuidString)"
        defer { cleanupBackups(for: projectId) }

        let service = ProjectBackupService.shared
        let backups = await service.listBackups(for: projectId)
        #expect(backups.isEmpty)
    }

    @Test("listBackups returns correct count after multiple backups")
    func listBackupsCorrectCount() async throws {
        let projectId = "list-count-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared

        // Create 3 backups with a small delay so timestamps differ
        _ = try await service.createBackup(
            for: projectId,
            projectName: "Project V1",
            projectDirectory: projectDir
        )
        try await Task.sleep(for: .seconds(1.1))

        _ = try await service.createBackup(
            for: projectId,
            projectName: "Project V2",
            projectDirectory: projectDir
        )
        try await Task.sleep(for: .seconds(1.1))

        _ = try await service.createBackup(
            for: projectId,
            projectName: "Project V3",
            projectDirectory: projectDir
        )

        let backups = await service.listBackups(for: projectId)
        #expect(backups.count == 3)
    }

    @Test("listBackups returns backups sorted newest first")
    func listBackupsSortedNewestFirst() async throws {
        let projectId = "sort-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared

        _ = try await service.createBackup(
            for: projectId,
            projectName: "First",
            projectDirectory: projectDir
        )
        try await Task.sleep(for: .seconds(1.1))

        _ = try await service.createBackup(
            for: projectId,
            projectName: "Second",
            projectDirectory: projectDir
        )

        let backups = await service.listBackups(for: projectId)
        #expect(backups.count == 2)
        #expect(backups[0].backupDate >= backups[1].backupDate)
        #expect(backups[0].projectName == "Second")
        #expect(backups[1].projectName == "First")
    }

    // MARK: - Restore Backup

    @Test("restoreBackup restores content matching original")
    func restoreBackupMatchesOriginal() async throws {
        let projectId = "restore-test-\(UUID().uuidString)"
        let originalContent = "This is the original project content for restore test."
        let projectDir = try makeTempProjectDir(
            files: ["document.txt": originalContent]
        )
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared
        let manifest = try await service.createBackup(
            for: projectId,
            projectName: "Restore Project",
            projectDirectory: projectDir
        )

        // Modify the original to simulate changes
        try "modified content".write(
            to: projectDir.appendingPathComponent("document.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Restore the backup over the project directory
        try await service.restoreBackup(manifest, to: projectDir)

        // Verify restored content matches the original
        let restoredContent = try String(
            contentsOf: projectDir.appendingPathComponent("document.txt"),
            encoding: .utf8
        )
        #expect(restoredContent == originalContent)
    }

    @Test("restoreBackup creates destination directory if it does not exist")
    func restoreBackupCreatesDestination() async throws {
        let projectId = "restore-new-dest-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir(
            files: ["data.txt": "backup data"]
        )
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared
        let manifest = try await service.createBackup(
            for: projectId,
            projectName: "Restore New Dest",
            projectDirectory: projectDir
        )

        // Create a new destination that does not exist
        let newDest = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreTarget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: newDest) }

        try await service.restoreBackup(manifest, to: newDest)

        let restoredContent = try String(
            contentsOf: newDest.appendingPathComponent("data.txt"),
            encoding: .utf8
        )
        #expect(restoredContent == "backup data")
    }

    // MARK: - Prune Old Backups

    @Test("pruneOldBackups keeps only the specified number of recent backups")
    func pruneKeepsOnlyRecent() async throws {
        let projectId = "prune-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared

        // Create 4 backups with delays to ensure unique timestamps
        for i in 1...4 {
            _ = try await service.createBackup(
                for: projectId,
                projectName: "Version \(i)",
                projectDirectory: projectDir
            )
            if i < 4 {
                try await Task.sleep(for: .seconds(1.1))
            }
        }

        // Verify we have 4
        var backups = await service.listBackups(for: projectId)
        #expect(backups.count == 4)

        // Prune to keep only 2
        try await service.pruneOldBackups(for: projectId, keepCount: 2)

        // Verify only 2 remain
        backups = await service.listBackups(for: projectId)
        #expect(backups.count == 2)

        // Verify the newest 2 were kept
        #expect(backups[0].projectName == "Version 4")
        #expect(backups[1].projectName == "Version 3")
    }

    @Test("pruneOldBackups with keepCount >= backup count does not delete anything")
    func pruneNoOpWhenUnderLimit() async throws {
        let projectId = "prune-noop-test-\(UUID().uuidString)"
        let projectDir = try makeTempProjectDir()
        defer {
            try? FileManager.default.removeItem(at: projectDir)
            cleanupBackups(for: projectId)
        }

        let service = ProjectBackupService.shared

        _ = try await service.createBackup(
            for: projectId,
            projectName: "Only Backup",
            projectDirectory: projectDir
        )

        // Prune with keepCount of 5 when only 1 backup exists
        try await service.pruneOldBackups(for: projectId, keepCount: 5)

        let backups = await service.listBackups(for: projectId)
        #expect(backups.count == 1)
    }

    @Test("pruneOldBackups for nonexistent project does not throw")
    func pruneNonexistentProject() async throws {
        let projectId = "prune-nonexistent-\(UUID().uuidString)"
        defer { cleanupBackups(for: projectId) }

        let service = ProjectBackupService.shared
        // Should not throw
        try await service.pruneOldBackups(for: projectId, keepCount: 3)
    }

    // MARK: - BackupManifest Model

    @Test("BackupManifest formattedTotalSize formats bytes correctly")
    func manifestFormattedTotalSize() {
        let manifest = BackupManifest(
            version: 1,
            appVersion: "1.0.0",
            appBuildNumber: 1,
            backupDate: Date(),
            deviceModel: "Simulator",
            iosVersion: "26.0",
            projectId: "test",
            projectName: "Test",
            projectVersion: 1,
            mediaFiles: [],
            totalSize: 2_097_152, // 2 MB
            includesMedia: false
        )

        #expect(manifest.formattedTotalSize == "2.0 MB")
    }

    @Test("BackupManifest mediaFileCount reflects media array length")
    func manifestMediaFileCount() {
        let entries = [
            BackupMediaEntry(
                originalPath: "video.mp4",
                archivePath: "media/video.mp4",
                contentHash: "abc",
                fileSize: 1000,
                mediaType: "video"
            ),
            BackupMediaEntry(
                originalPath: "image.png",
                archivePath: "media/image.png",
                contentHash: "def",
                fileSize: 500,
                mediaType: "image"
            )
        ]

        let manifest = BackupManifest(
            version: 1,
            appVersion: "1.0.0",
            appBuildNumber: 1,
            backupDate: Date(),
            deviceModel: "Simulator",
            iosVersion: "26.0",
            projectId: "test",
            projectName: "Test",
            projectVersion: 1,
            mediaFiles: entries,
            totalSize: 1500,
            includesMedia: true
        )

        #expect(manifest.mediaFileCount == 2)
    }

    @Test("BackupManifest isNewerVersion detects newer app version")
    func manifestIsNewerVersion() {
        let manifest = BackupManifest(
            version: 1,
            appVersion: "2.1.0",
            appBuildNumber: 1,
            backupDate: Date(),
            deviceModel: "Simulator",
            iosVersion: "26.0",
            projectId: "test",
            projectName: "Test",
            projectVersion: 1,
            mediaFiles: [],
            totalSize: 0,
            includesMedia: false
        )

        #expect(manifest.isNewerVersion(currentAppVersion: "1.5.0") == true)
        #expect(manifest.isNewerVersion(currentAppVersion: "2.1.0") == false)
        #expect(manifest.isNewerVersion(currentAppVersion: "3.0.0") == false)
    }

    @Test("BackupManifest Codable roundtrip preserves all fields")
    func manifestCodableRoundtrip() throws {
        let entry = BackupMediaEntry(
            originalPath: "Videos/clip.mov",
            archivePath: "media/clip.mov",
            contentHash: "sha256hash",
            fileSize: 4096,
            mediaType: "video"
        )

        let original = BackupManifest(
            version: 1,
            appVersion: "1.2.3",
            appBuildNumber: 42,
            backupDate: Date(timeIntervalSince1970: 1_700_000_000),
            deviceModel: "iPhone16,1",
            iosVersion: "26.0",
            projectId: "proj-123",
            projectName: "My Movie",
            projectVersion: 2,
            mediaFiles: [entry],
            totalSize: 4096,
            includesMedia: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BackupManifest.self, from: data)

        #expect(decoded.version == original.version)
        #expect(decoded.appVersion == original.appVersion)
        #expect(decoded.appBuildNumber == original.appBuildNumber)
        #expect(decoded.deviceModel == original.deviceModel)
        #expect(decoded.iosVersion == original.iosVersion)
        #expect(decoded.projectId == original.projectId)
        #expect(decoded.projectName == original.projectName)
        #expect(decoded.projectVersion == original.projectVersion)
        #expect(decoded.mediaFiles.count == 1)
        #expect(decoded.totalSize == original.totalSize)
        #expect(decoded.includesMedia == original.includesMedia)
    }

    // MARK: - BackupMediaEntry Model

    @Test("BackupMediaEntry formatBytes formats various sizes correctly")
    func mediaEntryFormatBytes() {
        #expect(BackupMediaEntry.formatBytes(500) == "500 B")
        #expect(BackupMediaEntry.formatBytes(1536) == "1.5 KB")
        #expect(BackupMediaEntry.formatBytes(5_242_880) == "5.0 MB")
        #expect(BackupMediaEntry.formatBytes(1_610_612_736) == "1.5 GB")
    }

    @Test("BackupMediaEntry with() creates a modified copy")
    func mediaEntryWith() {
        let entry = BackupMediaEntry(
            originalPath: "a.mp4",
            archivePath: "media/a.mp4",
            contentHash: "hash1",
            fileSize: 100,
            mediaType: "video"
        )

        let modified = entry.with(fileSize: 200, mediaType: "audio")
        #expect(modified.originalPath == "a.mp4")
        #expect(modified.fileSize == 200)
        #expect(modified.mediaType == "audio")
    }
}
