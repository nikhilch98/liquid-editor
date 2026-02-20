// ProjectRepositoryTests.swift
// LiquidEditorTests
//
// Tests for ProjectRepository: CRUD, persistence, metadata, rename, duplicate.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a minimal test Project with a valid hex-UUID ID.
private func makeProject(
    id: String = UUID().uuidString.lowercased(),
    name: String = "Test Project",
    sourceVideoPath: String = "Videos/test.mov",
    durationMicros: Int64 = 5_000_000,
    createdAt: Date = Date(),
    modifiedAt: Date = Date()
) -> Project {
    Project(
        id: id,
        name: name,
        sourceVideoPath: sourceVideoPath,
        durationMicros: durationMicros,
        createdAt: createdAt,
        modifiedAt: modifiedAt
    )
}

/// Create a temporary directory and return its URL.
private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ProjectRepoTests_\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Remove a temporary directory.
private func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - ProjectRepository Tests

@Suite("ProjectRepository Tests")
struct ProjectRepositoryTests {

    // MARK: - Save & Load

    @Suite("Save and Load")
    struct SaveLoadTests {

        @Test("Save and load returns project with matching fields")
        func saveAndLoad() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject(name: "My Video")
            try await repo.save(project)

            let loaded = try await repo.load(id: project.id)
            #expect(loaded.id == project.id)
            #expect(loaded.name == project.name)
            #expect(loaded.sourceVideoPath == project.sourceVideoPath)
            #expect(loaded.durationMicros == project.durationMicros)
        }

        @Test("Overwrite existing project with same ID")
        func overwriteExisting() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject(name: "Version 1")
            try await repo.save(project)

            let updated = project.with(name: "Version 2", modifiedAt: Date())
            try await repo.save(updated)

            let loaded = try await repo.load(id: project.id)
            #expect(loaded.name == "Version 2")
        }

        @Test("Load non-existent project throws notFound")
        func loadNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let validId = UUID().uuidString.lowercased()
            await #expect(throws: RepositoryError.self) {
                _ = try await repo.load(id: validId)
            }
        }

        @Test("Save preserves all editing state fields")
        func preservesEditingState() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject()
                .with(
                    cropAspectRatio: 1.777,
                    cropAspectRatioLabel: "16:9",
                    cropRotation90: 1,
                    cropFlipHorizontal: true,
                    noiseReductionIntensity: 0.8,
                    noiseReductionEnabled: true,
                    playbackSpeed: 2.0
                )
            try await repo.save(project)

            let loaded = try await repo.load(id: project.id)
            #expect(loaded.cropAspectRatio == 1.777)
            #expect(loaded.cropAspectRatioLabel == "16:9")
            #expect(loaded.cropRotation90 == 1)
            #expect(loaded.cropFlipHorizontal == true)
            #expect(loaded.playbackSpeed == 2.0)
            #expect(loaded.noiseReductionEnabled == true)
            #expect(loaded.noiseReductionIntensity == 0.8)
        }
    }

    // MARK: - Metadata

    @Suite("Metadata")
    struct MetadataTests {

        @Test("Load metadata for saved project")
        func loadMetadata() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject(name: "Metadata Test", durationMicros: 10_000_000)
            try await repo.save(project)

            let metadata = try await repo.loadMetadata(id: project.id)
            #expect(metadata.id == project.id)
            #expect(metadata.name == "Metadata Test")
            #expect(metadata.timelineDurationMs == 10000)
        }

        @Test("Load metadata for non-existent project throws notFound")
        func loadMetadataNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let validId = UUID().uuidString.lowercased()
            await #expect(throws: RepositoryError.self) {
                _ = try await repo.loadMetadata(id: validId)
            }
        }

        @Test("List metadata returns all saved projects sorted by modifiedAt descending")
        func listMetadata() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let now = Date()
            let p1 = makeProject(name: "Older", modifiedAt: now.addingTimeInterval(-100))
            let p2 = makeProject(name: "Newer", modifiedAt: now)

            try await repo.save(p1)
            try await repo.save(p2)

            let list = try await repo.listMetadata()
            #expect(list.count == 2)
            // Newest first
            #expect(list[0].name == "Newer")
            #expect(list[1].name == "Older")
        }

        @Test("List metadata on empty directory returns empty array")
        func listMetadataEmpty() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let list = try await repo.listMetadata()
            #expect(list.isEmpty)
        }
    }

    // MARK: - Delete

    @Suite("Delete")
    struct DeleteTests {

        @Test("Delete removes project")
        func deleteProject() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject()
            try await repo.save(project)
            #expect(await repo.exists(id: project.id))

            try await repo.delete(id: project.id)
            #expect(await !repo.exists(id: project.id))
        }

        @Test("Delete non-existent project throws notFound")
        func deleteNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let validId = UUID().uuidString.lowercased()
            await #expect(throws: RepositoryError.self) {
                try await repo.delete(id: validId)
            }
        }
    }

    // MARK: - Exists

    @Suite("Exists")
    struct ExistsTests {

        @Test("Exists returns true for saved project")
        func existsTrue() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject()
            try await repo.save(project)

            #expect(await repo.exists(id: project.id))
        }

        @Test("Exists returns false for non-existent project")
        func existsFalse() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let validId = UUID().uuidString.lowercased()
            #expect(await !repo.exists(id: validId))
        }

        @Test("Exists returns false for invalid ID format")
        func existsInvalidId() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            #expect(await !repo.exists(id: "INVALID_ID!"))
        }
    }

    // MARK: - Rename

    @Suite("Rename")
    struct RenameTests {

        @Test("Rename updates project name")
        func rename() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject(name: "Original")
            try await repo.save(project)

            try await repo.rename(id: project.id, newName: "Renamed")

            let loaded = try await repo.load(id: project.id)
            #expect(loaded.name == "Renamed")
        }

        @Test("Rename with empty name throws validationFailed")
        func renameEmptyName() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = makeProject()
            try await repo.save(project)

            await #expect(throws: RepositoryError.self) {
                try await repo.rename(id: project.id, newName: "  ")
            }
        }

        @Test("Rename non-existent project throws notFound")
        func renameNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let validId = UUID().uuidString.lowercased()
            await #expect(throws: RepositoryError.self) {
                try await repo.rename(id: validId, newName: "New Name")
            }
        }
    }

    // MARK: - Duplicate

    @Suite("Duplicate")
    struct DuplicateTests {

        @Test("Duplicate creates copy with new ID and name")
        func duplicate() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let original = makeProject(name: "Original", durationMicros: 8_000_000)
            try await repo.save(original)

            let newId = UUID().uuidString.lowercased()
            let copy = try await repo.duplicate(
                id: original.id,
                newId: newId,
                newName: "Copy of Original"
            )

            #expect(copy.id == newId)
            #expect(copy.name == "Copy of Original")
            #expect(copy.sourceVideoPath == original.sourceVideoPath)
            #expect(copy.durationMicros == original.durationMicros)

            // Both original and copy should exist.
            #expect(await repo.exists(id: original.id))
            #expect(await repo.exists(id: newId))
        }

        @Test("Duplicate with existing newId throws duplicateEntry")
        func duplicateExistingId() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let p1 = makeProject(name: "First")
            let p2 = makeProject(name: "Second")
            try await repo.save(p1)
            try await repo.save(p2)

            await #expect(throws: RepositoryError.self) {
                _ = try await repo.duplicate(id: p1.id, newId: p2.id, newName: "Dup")
            }
        }

        @Test("Duplicate non-existent source throws notFound")
        func duplicateNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let sourceId = UUID().uuidString.lowercased()
            let newId = UUID().uuidString.lowercased()
            await #expect(throws: RepositoryError.self) {
                _ = try await repo.duplicate(id: sourceId, newId: newId, newName: "Copy")
            }
        }
    }

    // MARK: - ID Validation

    @Suite("ID Validation")
    struct IdValidationTests {

        @Test("Invalid ID format throws invalidPath on save")
        func invalidIdOnSave() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            let project = Project(
                id: "INVALID_ID!@#",
                name: "Bad ID",
                sourceVideoPath: "test.mov"
            )

            await #expect(throws: RepositoryError.self) {
                try await repo.save(project)
            }
        }

        @Test("Invalid ID format throws invalidPath on load")
        func invalidIdOnLoad() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = ProjectRepository(baseDirectory: tempDir)

            await #expect(throws: RepositoryError.self) {
                _ = try await repo.load(id: "INVALID!")
            }
        }
    }

    // MARK: - Persistence Across Instances

    @Suite("Persistence")
    struct PersistenceTests {

        @Test("Data persists across repository instances")
        func persistsAcrossInstances() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }

            let project = makeProject(name: "Persistent")

            // Save with first instance.
            let repo1 = ProjectRepository(baseDirectory: tempDir)
            try await repo1.save(project)

            // Load with second instance.
            let repo2 = ProjectRepository(baseDirectory: tempDir)
            let loaded = try await repo2.load(id: project.id)
            #expect(loaded.name == "Persistent")
        }
    }
}
