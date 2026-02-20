// BackupRepositoryTests.swift
// LiquidEditorTests
//
// Tests for BackupRepository: create, validate, restore, list, delete, size.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a minimal test Project.
private func makeProject(
    id: String = UUID().uuidString.lowercased(),
    name: String = "Backup Test",
    sourceVideoPath: String = "Videos/test.mov",
    durationMicros: Int64 = 5_000_000
) -> Project {
    Project(
        id: id,
        name: name,
        sourceVideoPath: sourceVideoPath,
        durationMicros: durationMicros
    )
}

/// Create a temporary directory.
private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("BackupRepoTests_\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Remove a temporary directory.
private func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - BackupRepository Tests

@Suite("BackupRepository Tests")
struct BackupRepositoryTests {

    // MARK: - Create Backup

    @Suite("Create Backup")
    struct CreateTests {

        @Test("Create backup without media produces archive with manifest and project")
        func createBackupNoMedia() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let project = makeProject(name: "My Backup")
            let archiveURL = try await repo.createBackup(project: project, includeMedia: false)

            // Archive directory should exist.
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: archiveURL.path, isDirectory: &isDir))
            #expect(isDir.boolValue)

            // Should contain manifest.json and project.json.
            let manifestURL = archiveURL.appendingPathComponent("manifest.json")
            let projectURL = archiveURL.appendingPathComponent("project.json")
            #expect(FileManager.default.fileExists(atPath: manifestURL.path))
            #expect(FileManager.default.fileExists(atPath: projectURL.path))
        }

        @Test("Created backup has .liquidbackup extension")
        func backupExtension() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let project = makeProject()
            let archiveURL = try await repo.createBackup(project: project, includeMedia: false)

            #expect(archiveURL.pathExtension == "liquidbackup")
        }
    }

    // MARK: - Load Manifest

    @Suite("Load Manifest")
    struct ManifestTests {

        @Test("Load manifest from created backup returns valid manifest")
        func loadManifest() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let project = makeProject(name: "Manifest Test")
            let archiveURL = try await repo.createBackup(project: project, includeMedia: false)

            let manifest = try await repo.loadManifest(archiveURL: archiveURL)
            #expect(manifest.projectName == "Manifest Test")
            #expect(manifest.projectId == project.id)
            #expect(!manifest.includesMedia)
        }

        @Test("Load manifest from non-existent archive throws notFound")
        func loadManifestNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let fakeURL = tempDir.appendingPathComponent("nonexistent.liquidbackup")
            await #expect(throws: RepositoryError.self) {
                _ = try await repo.loadManifest(archiveURL: fakeURL)
            }
        }
    }

    // MARK: - Validate

    @Suite("Validate")
    struct ValidateTests {

        @Test("Validate valid backup returns valid result")
        func validateValid() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let project = makeProject()
            let archiveURL = try await repo.createBackup(project: project, includeMedia: false)

            let result = try await repo.validate(archiveURL: archiveURL)
            #expect(result.isValid)
            #expect(result.manifest != nil)
            #expect(result.error == nil)
        }

        @Test("Validate non-existent archive returns invalid")
        func validateNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let fakeURL = tempDir.appendingPathComponent("fake.liquidbackup")
            let result = try await repo.validate(archiveURL: fakeURL)
            #expect(!result.isValid)
        }

        @Test("Validate archive missing manifest returns invalid")
        func validateMissingManifest() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            // Create a fake archive directory without manifest.json.
            let archiveURL = tempDir.appendingPathComponent("broken.liquidbackup")
            try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)

            let result = try await repo.validate(archiveURL: archiveURL)
            #expect(!result.isValid)
        }

        @Test("Validate archive missing project.json returns invalid")
        func validateMissingProject() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            // Create archive with manifest but no project.json.
            let archiveURL = tempDir.appendingPathComponent("partial.liquidbackup")
            try FileManager.default.createDirectory(at: archiveURL, withIntermediateDirectories: true)

            let manifest = BackupManifest(
                version: 1,
                appVersion: "1.0.0",
                appBuildNumber: 1,
                backupDate: Date(),
                deviceModel: "iPhone",
                iosVersion: "26.0",
                projectId: "test-id",
                projectName: "Test",
                projectVersion: 2,
                mediaFiles: [],
                totalSize: 100,
                includesMedia: false
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: archiveURL.appendingPathComponent("manifest.json"))

            let result = try await repo.validate(archiveURL: archiveURL)
            #expect(!result.isValid)
        }
    }

    // MARK: - Restore

    @Suite("Restore")
    struct RestoreTests {

        @Test("Restore returns project with new ID")
        func restoreNewId() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let original = makeProject(name: "Restorable")
            let archiveURL = try await repo.createBackup(project: original, includeMedia: false)

            let restored = try await repo.restore(archiveURL: archiveURL)
            // Restored project gets a new UUID.
            #expect(restored.id != original.id)
            #expect(restored.name == original.name)
            #expect(restored.sourceVideoPath == original.sourceVideoPath)
        }

        @Test("Restore from invalid archive throws")
        func restoreInvalid() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let fakeURL = tempDir.appendingPathComponent("invalid.liquidbackup")
            try FileManager.default.createDirectory(at: fakeURL, withIntermediateDirectories: true)

            await #expect(throws: RepositoryError.self) {
                _ = try await repo.restore(archiveURL: fakeURL)
            }
        }
    }

    // MARK: - List Backups

    @Suite("List Backups")
    struct ListTests {

        @Test("List backups returns all created backups")
        func listBackups() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let p1 = makeProject(name: "First")
            let p2 = makeProject(name: "Second")

            _ = try await repo.createBackup(project: p1, includeMedia: false)
            // ISO 8601 has second-level precision; wait >1s for distinct timestamps.
            try await Task.sleep(for: .milliseconds(1100))
            _ = try await repo.createBackup(project: p2, includeMedia: false)

            let backups = try await repo.listBackups()
            #expect(backups.count == 2)
            // Sorted newest first.
            #expect(backups[0].manifest.projectName == "Second")
            #expect(backups[1].manifest.projectName == "First")
        }

        @Test("List backups on empty directory returns empty array")
        func listBackupsEmpty() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let backups = try await repo.listBackups()
            #expect(backups.isEmpty)
        }
    }

    // MARK: - Delete Backup

    @Suite("Delete Backup")
    struct DeleteTests {

        @Test("Delete backup removes archive")
        func deleteBackup() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let project = makeProject()
            let archiveURL = try await repo.createBackup(project: project, includeMedia: false)

            try await repo.deleteBackup(archiveURL: archiveURL)
            #expect(!FileManager.default.fileExists(atPath: archiveURL.path))
        }

        @Test("Delete non-existent backup throws notFound")
        func deleteNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let fakeURL = tempDir.appendingPathComponent("missing.liquidbackup")
            await #expect(throws: RepositoryError.self) {
                try await repo.deleteBackup(archiveURL: fakeURL)
            }
        }
    }

    // MARK: - Backup Size

    @Suite("Backup Size")
    struct SizeTests {

        @Test("Backup size returns positive value for created backup")
        func backupSize() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let project = makeProject()
            let archiveURL = try await repo.createBackup(project: project, includeMedia: false)

            let size = try await repo.backupSize(archiveURL: archiveURL)
            #expect(size > 0)
        }

        @Test("Backup size for non-existent archive throws notFound")
        func backupSizeNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = BackupRepository(baseDirectory: tempDir)

            let fakeURL = tempDir.appendingPathComponent("missing.liquidbackup")
            await #expect(throws: RepositoryError.self) {
                _ = try await repo.backupSize(archiveURL: fakeURL)
            }
        }
    }

    // MARK: - Persistence

    @Suite("Persistence")
    struct PersistenceTests {

        @Test("Backups persist across repository instances")
        func persistsAcrossInstances() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }

            let project = makeProject(name: "Persistent Backup")

            let repo1 = BackupRepository(baseDirectory: tempDir)
            let archiveURL = try await repo1.createBackup(project: project, includeMedia: false)

            let repo2 = BackupRepository(baseDirectory: tempDir)
            let manifest = try await repo2.loadManifest(archiveURL: archiveURL)
            #expect(manifest.projectName == "Persistent Backup")
        }
    }
}
