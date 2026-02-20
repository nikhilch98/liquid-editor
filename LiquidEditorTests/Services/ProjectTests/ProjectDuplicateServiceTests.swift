// ProjectDuplicateServiceTests.swift
// LiquidEditorTests
//
// Tests for ProjectDuplicateService using Swift Testing.
// Validates new ID generation, name uniqueness, data integrity,
// and media reference sharing.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - MockProjectRepoForDuplicate

/// In-memory mock that supports load, save, listMetadata, and duplicate.
private actor MockProjectRepoForDuplicate: ProjectRepositoryProtocol {
    var projects: [String: Project] = [:]
    var metadataList: [ProjectMetadata] = []

    func save(_ project: Project) async throws {
        projects[project.id] = project
    }

    func load(id: String) async throws -> Project {
        guard let p = projects[id] else {
            throw RepositoryError.notFound("Project \(id)")
        }
        return p
    }

    func loadMetadata(id: String) async throws -> ProjectMetadata {
        throw RepositoryError.notFound("Metadata \(id)")
    }

    func listMetadata() async throws -> [ProjectMetadata] {
        metadataList
    }

    func delete(id: String) async throws {
        projects.removeValue(forKey: id)
    }

    func exists(id: String) async -> Bool {
        projects[id] != nil
    }

    func rename(id: String, newName: String) async throws {}

    func duplicate(id: String, newId: String, newName: String) async throws -> Project {
        guard let source = projects[id] else {
            throw RepositoryError.notFound("Project \(id)")
        }
        guard projects[newId] == nil else {
            throw RepositoryError.duplicateEntry("Project \(newId) already exists")
        }
        let now = Date()
        let copy = source.with(id: newId, name: newName, createdAt: now, modifiedAt: now)
        projects[newId] = copy
        return copy
    }

    func addProject(_ project: Project) {
        projects[project.id] = project
    }

    func addMetadata(_ metadata: ProjectMetadata) {
        metadataList.append(metadata)
    }
}

// MARK: - Test Helpers

private let testProjectId = "abcd1234-5678-abcd-ef01-234567890abc"

private func makeTestProject(
    id: String = testProjectId,
    name: String = "My Video"
) -> Project {
    Project(
        id: id,
        name: name,
        sourceVideoPath: "Videos/source.mp4",
        frameRate: .fixed30,
        durationMicros: 10_000_000,
        createdAt: Date(),
        modifiedAt: Date()
    )
}

// MARK: - ProjectDuplicateServiceTests

@Suite("ProjectDuplicateService Tests")
struct ProjectDuplicateServiceTests {

    // MARK: - Name Generation

    @Test("generateUniqueCopyName produces 'Name Copy' when no conflict")
    func uniqueNameNoConflict() {
        let result = ProjectDuplicateService.generateUniqueCopyName(
            originalName: "My Video",
            existingNames: ["Other Project", "Another"]
        )
        #expect(result == "My Video Copy")
    }

    @Test("generateUniqueCopyName increments when 'Copy' exists")
    func uniqueNameWithConflict() {
        let result = ProjectDuplicateService.generateUniqueCopyName(
            originalName: "My Video",
            existingNames: ["My Video Copy"]
        )
        #expect(result == "My Video Copy 2")
    }

    @Test("generateUniqueCopyName increments past multiple conflicts")
    func uniqueNameMultipleConflicts() {
        let result = ProjectDuplicateService.generateUniqueCopyName(
            originalName: "My Video",
            existingNames: ["My Video Copy", "My Video Copy 2", "My Video Copy 3"]
        )
        #expect(result == "My Video Copy 4")
    }

    @Test("generateUniqueCopyName with empty existing names")
    func uniqueNameEmptyExisting() {
        let result = ProjectDuplicateService.generateUniqueCopyName(
            originalName: "Test",
            existingNames: []
        )
        #expect(result == "Test Copy")
    }

    // MARK: - Duplicate Project by ID

    @Test("duplicateProject creates a project with a new ID")
    func duplicateCreatesNewId() async throws {
        let repo = MockProjectRepoForDuplicate()
        let original = makeTestProject()
        await repo.addProject(original)

        let service = ProjectDuplicateService(projectRepository: repo)
        let duplicate = try await service.duplicateProject(
            id: original.id,
            existingNames: []
        )

        #expect(duplicate.id != original.id)
        #expect(!duplicate.id.isEmpty)
    }

    @Test("duplicateProject preserves source video path")
    func duplicatePreservesMediaReference() async throws {
        let repo = MockProjectRepoForDuplicate()
        let original = makeTestProject()
        await repo.addProject(original)

        let service = ProjectDuplicateService(projectRepository: repo)
        let duplicate = try await service.duplicateProject(
            id: original.id,
            existingNames: []
        )

        #expect(duplicate.sourceVideoPath == original.sourceVideoPath)
    }

    @Test("duplicateProject sets correct copy name")
    func duplicateSetsName() async throws {
        let repo = MockProjectRepoForDuplicate()
        let original = makeTestProject(name: "Holiday Montage")
        await repo.addProject(original)

        let service = ProjectDuplicateService(projectRepository: repo)
        let duplicate = try await service.duplicateProject(
            id: original.id,
            existingNames: []
        )

        #expect(duplicate.name == "Holiday Montage Copy")
    }

    @Test("duplicateProject resets timestamps")
    func duplicateResetsTimestamps() async throws {
        let repo = MockProjectRepoForDuplicate()
        let oldDate = Date(timeIntervalSince1970: 1_000_000)
        let original = makeTestProject().with(createdAt: oldDate, modifiedAt: oldDate)
        await repo.addProject(original)

        let beforeDuplicate = Date()
        let service = ProjectDuplicateService(projectRepository: repo)
        let duplicate = try await service.duplicateProject(
            id: original.id,
            existingNames: []
        )

        #expect(duplicate.createdAt >= beforeDuplicate)
        #expect(duplicate.modifiedAt >= beforeDuplicate)
    }

    @Test("duplicateProject preserves frame rate")
    func duplicatePreservesFrameRate() async throws {
        let repo = MockProjectRepoForDuplicate()
        let original = makeTestProject().with(frameRate: .fixed24)
        await repo.addProject(original)

        let service = ProjectDuplicateService(projectRepository: repo)
        let duplicate = try await service.duplicateProject(
            id: original.id,
            existingNames: []
        )

        #expect(duplicate.frameRate == .fixed24)
    }

    // MARK: - Duplicate with Existing Names from Repository

    @Test("duplicateProjectData loads names from repository when not provided")
    func duplicateLoadsNamesFromRepo() async throws {
        let repo = MockProjectRepoForDuplicate()
        let original = makeTestProject(name: "Clip")
        await repo.addProject(original)
        await repo.addMetadata(ProjectMetadata(
            id: "other-id",
            name: "Clip Copy",
            createdAt: Date(),
            modifiedAt: Date(),
            timelineDurationMs: 0,
            clipCount: 0,
            version: 2
        ))

        let service = ProjectDuplicateService(projectRepository: repo)
        let duplicate = try await service.duplicateProjectData(original)

        #expect(duplicate.name == "Clip Copy 2")
    }

    // MARK: - Error Cases

    @Test("duplicateProject throws notFound for missing project")
    func duplicateMissingProjectThrows() async {
        let repo = MockProjectRepoForDuplicate()
        let service = ProjectDuplicateService(projectRepository: repo)

        await #expect(throws: RepositoryError.self) {
            _ = try await service.duplicateProject(id: "nonexistent-id")
        }
    }
}
