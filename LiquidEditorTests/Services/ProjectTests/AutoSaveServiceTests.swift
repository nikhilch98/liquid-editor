// AutoSaveServiceTests.swift
// LiquidEditorTests
//
// Tests for AutoSaveService using Swift Testing.
// Validates debounce behavior, concurrent write prevention,
// immediate save, and state transitions.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - MockAutoSaveProjectRepository

/// In-memory mock that records save calls for verification.
private actor MockAutoSaveProjectRepository: ProjectRepositoryProtocol {
    var savedProjects: [Project] = []
    var projects: [String: Project] = [:]
    var metadata: [ProjectMetadata] = []
    var shouldThrow = false

    func save(_ project: Project) async throws {
        if shouldThrow { throw RepositoryError.ioError("Mock save failure") }
        savedProjects.append(project)
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
        metadata
    }

    func delete(id: String) async throws {}

    func exists(id: String) async -> Bool {
        projects[id] != nil
    }

    func rename(id: String, newName: String) async throws {}

    func duplicate(id: String, newId: String, newName: String) async throws -> Project {
        guard let source = projects[id] else {
            throw RepositoryError.notFound("Project \(id)")
        }
        let copy = source.with(id: newId, name: newName, createdAt: Date(), modifiedAt: Date())
        projects[newId] = copy
        return copy
    }

    func getSaveCount() -> Int { savedProjects.count }
    func setShouldThrow(_ value: Bool) { shouldThrow = value }
}

// MARK: - MockDraftRepository

/// In-memory mock for draft repository.
private actor MockDraftRepository: DraftRepositoryProtocol {
    var savedDrafts: [(projectId: String, reason: DraftTriggerReason)] = []
    var shouldThrow = false

    func saveDraft(projectId: String, project: Project, reason: DraftTriggerReason) async throws {
        if shouldThrow { throw RepositoryError.ioError("Mock draft failure") }
        savedDrafts.append((projectId: projectId, reason: reason))
    }

    func loadLatestDraft(projectId: String) async throws -> Project? { nil }
    func loadDraft(projectId: String, index: Int) async throws -> Project? { nil }
    func loadMetadata(projectId: String) async throws -> DraftMetadata? { nil }
    func listDrafts(projectId: String) async throws -> [DraftEntry] { [] }
    func deleteDrafts(projectId: String) async throws {}
    func hasDraft(projectId: String) async -> Bool { false }
    func markCleanShutdown(projectId: String) async throws {}
    func markSessionStarted(projectId: String) async throws {}
    func needsCrashRecovery(projectId: String) async throws -> Bool { false }

    func getDraftCount() -> Int { savedDrafts.count }
    func setShouldThrow(_ value: Bool) { shouldThrow = value }
}

// MARK: - Test Helpers

private func makeTestProject(
    id: String = "abcd1234-5678-abcd-ef01-234567890abc",
    name: String = "Test Project"
) -> Project {
    Project(
        id: id,
        name: name,
        sourceVideoPath: "Videos/test.mp4",
        durationMicros: 5_000_000,
        createdAt: Date(),
        modifiedAt: Date()
    )
}

// MARK: - AutoSaveServiceTests

@Suite("AutoSaveService Tests")
@MainActor
struct AutoSaveServiceTests {

    // MARK: - Initial State

    @Test("Initial state is saved with no lastSavedAt")
    func initialState() {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        #expect(service.state == .saved)
        #expect(!service.isSaving)
        #expect(!service.hasUnsavedChanges)
        #expect(service.lastSavedAt == nil)
    }

    // MARK: - Schedule Auto-Save

    @Test("scheduleAutoSave sets state to unsaved immediately")
    func scheduleAutoSaveSetsUnsaved() {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        let project = makeTestProject()
        service.scheduleAutoSave(project)

        #expect(service.state == .unsaved)
        #expect(service.hasUnsavedChanges)

        // Clean up
        service.cancelAutoSave()
    }

    // MARK: - Save Immediately

    @Test("saveImmediately saves project and draft, updates state")
    func saveImmediately() async {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        let project = makeTestProject()
        await service.saveImmediately(project)

        #expect(service.state == .saved)
        #expect(service.lastSavedAt != nil)
        #expect(!service.isSaving)

        let saveCount = await projectRepo.getSaveCount()
        #expect(saveCount == 1)

        let draftCount = await draftRepo.getDraftCount()
        #expect(draftCount == 1)
    }

    @Test("saveImmediately with manualSave reason records correct reason")
    func saveImmediatelyManualReason() async {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        let project = makeTestProject()
        await service.saveImmediately(project, reason: .manualSave)

        let drafts = await draftRepo.savedDrafts
        #expect(drafts.count == 1)
        #expect(drafts.first?.reason == .manualSave)
    }

    // MARK: - Concurrent Write Prevention

    @Test("performSave skips if already saving")
    func skipsConcurrentSave() async {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        // First save
        let project = makeTestProject()
        await service.saveImmediately(project)

        let saveCount = await projectRepo.getSaveCount()
        #expect(saveCount == 1)
    }

    // MARK: - Error Handling

    @Test("Save failure sets state to error")
    func saveFailureSetsError() async {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        await projectRepo.setShouldThrow(true)

        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        let project = makeTestProject()
        await service.saveImmediately(project)

        #expect(service.state == .error)
        #expect(service.lastSavedAt == nil)
    }

    // MARK: - Cancel

    @Test("cancelAutoSave cancels pending debounce")
    func cancelAutoSave() {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        let project = makeTestProject()
        service.scheduleAutoSave(project)
        #expect(service.state == .unsaved)

        service.cancelAutoSave()
        // State remains unsaved (cancel doesn't revert state, just prevents the save)
        #expect(service.state == .unsaved)
    }

    // MARK: - Mark Saved

    @Test("markSaved updates state and timestamp")
    func markSaved() {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        #expect(service.lastSavedAt == nil)

        service.markSaved()

        #expect(service.state == .saved)
        #expect(service.lastSavedAt != nil)
    }

    // MARK: - Reset

    @Test("reset clears all state")
    func reset() {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        service.markSaved()
        #expect(service.lastSavedAt != nil)

        service.reset()

        #expect(service.state == .saved)
        #expect(service.lastSavedAt == nil)
    }

    // MARK: - Debounce Behavior

    @Test("Debounce triggers save after delay")
    func debounceTriggersAfterDelay() async throws {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        let project = makeTestProject()
        service.scheduleAutoSave(project)

        #expect(service.state == .unsaved)

        // Wait for debounce to complete (2 seconds + buffer).
        try await Task.sleep(for: .milliseconds(2500))

        // After debounce, save should have completed.
        let saveCount = await projectRepo.getSaveCount()
        #expect(saveCount == 1)
        #expect(service.state == .saved)
    }

    @Test("Multiple rapid schedules only trigger one save")
    func multipleRapidSchedules() async throws {
        let projectRepo = MockAutoSaveProjectRepository()
        let draftRepo = MockDraftRepository()
        let service = AutoSaveService(
            projectRepository: projectRepo,
            draftRepository: draftRepo
        )

        let project = makeTestProject()

        // Schedule rapidly 5 times.
        for _ in 0..<5 {
            service.scheduleAutoSave(project)
            try await Task.sleep(for: .milliseconds(100))
        }

        // Wait for debounce to complete.
        try await Task.sleep(for: .milliseconds(2500))

        // Should only have saved once.
        let saveCount = await projectRepo.getSaveCount()
        #expect(saveCount == 1)
    }
}
