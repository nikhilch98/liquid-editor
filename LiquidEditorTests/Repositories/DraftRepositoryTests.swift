// DraftRepositoryTests.swift
// LiquidEditorTests
//
// Tests for DraftRepository: ring buffer drafts, crash recovery, session lifecycle.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// A valid hex-UUID project ID for tests.
private func makeProjectId() -> String {
    UUID().uuidString.lowercased()
}

/// Create a minimal test Project.
private func makeProject(
    id: String = UUID().uuidString.lowercased(),
    name: String = "Test Project",
    clipCount: Int = 2,
    durationMicros: Int64 = 5_000_000
) -> Project {
    Project(
        id: id,
        name: name,
        sourceVideoPath: "Videos/test.mov",
        durationMicros: durationMicros
    )
}

/// Create a temporary directory.
private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DraftRepoTests_\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Remove a temporary directory.
private func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - DraftRepository Tests

@Suite("DraftRepository Tests")
struct DraftRepositoryTests {

    // MARK: - Save and Load Draft

    @Suite("Save and Load Draft")
    struct SaveLoadTests {

        @Test("Save draft and load latest returns project")
        func saveAndLoadLatest() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId, name: "Draft Test")

            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .autoSave
            )

            let loaded = try await repo.loadLatestDraft(projectId: projectId)
            #expect(loaded != nil)
            #expect(loaded?.id == projectId)
            #expect(loaded?.name == "Draft Test")
        }

        @Test("Load latest draft when no drafts returns nil")
        func loadLatestNoDrafts() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let loaded = try await repo.loadLatestDraft(projectId: projectId)
            #expect(loaded == nil)
        }

        @Test("Load draft by specific index")
        func loadDraftByIndex() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId, name: "Indexed Draft")

            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .manualSave
            )

            // The first draft goes to slot index determined by nextIndex (starts at 1 for empty metadata).
            let metadata = try await repo.loadMetadata(projectId: projectId)
            #expect(metadata != nil)

            let slotIndex = metadata!.currentIndex
            let loaded = try await repo.loadDraft(projectId: projectId, index: slotIndex)
            #expect(loaded != nil)
            #expect(loaded?.name == "Indexed Draft")
        }

        @Test("Load draft from empty slot returns nil")
        func loadDraftEmptySlot() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let loaded = try await repo.loadDraft(projectId: projectId, index: 0)
            #expect(loaded == nil)
        }

        @Test("Multiple drafts cycle through ring buffer slots")
        func ringBufferCycling() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()

            // Save drafts to fill the ring buffer.
            for i in 0..<DraftMetadata.maxDrafts {
                let project = makeProject(
                    id: projectId,
                    name: "Draft \(i)"
                )
                try await repo.saveDraft(
                    projectId: projectId,
                    project: project,
                    reason: .autoSave
                )
            }

            let metadata = try await repo.loadMetadata(projectId: projectId)
            #expect(metadata != nil)
            #expect(metadata!.drafts.count == DraftMetadata.maxDrafts)

            // Save one more to wrap around.
            let overflowProject = makeProject(id: projectId, name: "Overflow")
            try await repo.saveDraft(
                projectId: projectId,
                project: overflowProject,
                reason: .autoSave
            )

            // Latest should be the overflow.
            let latest = try await repo.loadLatestDraft(projectId: projectId)
            #expect(latest?.name == "Overflow")
        }
    }

    // MARK: - Has Draft

    @Suite("Has Draft")
    struct HasDraftTests {

        @Test("Has draft returns true after saving")
        func hasDraftTrue() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId)

            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .autoSave
            )

            #expect(await repo.hasDraft(projectId: projectId))
        }

        @Test("Has draft returns false for new project")
        func hasDraftFalse() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            #expect(await !repo.hasDraft(projectId: makeProjectId()))
        }
    }

    // MARK: - Delete Drafts

    @Suite("Delete Drafts")
    struct DeleteTests {

        @Test("Delete drafts removes all draft data")
        func deleteDrafts() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId)

            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .autoSave
            )
            #expect(await repo.hasDraft(projectId: projectId))

            try await repo.deleteDrafts(projectId: projectId)
            #expect(await !repo.hasDraft(projectId: projectId))
        }

        @Test("Delete drafts for non-existent project is no-op")
        func deleteNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            // Should not throw.
            try await repo.deleteDrafts(projectId: makeProjectId())
        }
    }

    // MARK: - List Drafts

    @Suite("List Drafts")
    struct ListTests {

        @Test("List drafts returns entries sorted newest first")
        func listDraftsSorted() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()

            for _ in 0..<3 {
                let project = makeProject(id: projectId)
                try await repo.saveDraft(
                    projectId: projectId,
                    project: project,
                    reason: .autoSave
                )
                // Small delay to ensure different timestamps.
                try await Task.sleep(for: .milliseconds(10))
            }

            let drafts = try await repo.listDrafts(projectId: projectId)
            #expect(drafts.count == 3)
            // Verify sorted newest first.
            for i in 0..<(drafts.count - 1) {
                #expect(drafts[i].savedAt >= drafts[i + 1].savedAt)
            }
        }
    }

    // MARK: - Crash Recovery

    @Suite("Crash Recovery")
    struct CrashRecoveryTests {

        @Test("New project does not need crash recovery")
        func noRecoveryNeeded() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let needsRecovery = try await repo.needsCrashRecovery(projectId: makeProjectId())
            #expect(!needsRecovery)
        }

        @Test("Session started without clean shutdown needs recovery")
        func needsRecoveryAfterDirtySession() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId)

            // Save a draft (this also marks cleanShutdown = false).
            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .autoSave
            )

            // Marking session started sets cleanShutdown = false.
            try await repo.markSessionStarted(projectId: projectId)

            let needsRecovery = try await repo.needsCrashRecovery(projectId: projectId)
            #expect(needsRecovery)
        }

        @Test("Clean shutdown prevents crash recovery")
        func cleanShutdownPreventsRecovery() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId)

            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .autoSave
            )
            try await repo.markSessionStarted(projectId: projectId)
            try await repo.markCleanShutdown(projectId: projectId)

            let needsRecovery = try await repo.needsCrashRecovery(projectId: projectId)
            #expect(!needsRecovery)
        }
    }

    // MARK: - Session Lifecycle

    @Suite("Session Lifecycle")
    struct SessionLifecycleTests {

        @Test("Mark session started sets cleanShutdown to false")
        func markSessionStarted() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId)

            // Saving a draft creates metadata.
            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .autoSave
            )
            try await repo.markCleanShutdown(projectId: projectId)

            let metaBefore = try await repo.loadMetadata(projectId: projectId)
            #expect(metaBefore?.cleanShutdown == true)

            try await repo.markSessionStarted(projectId: projectId)

            let metaAfter = try await repo.loadMetadata(projectId: projectId)
            #expect(metaAfter?.cleanShutdown == false)
        }

        @Test("Mark clean shutdown sets cleanShutdown to true")
        func markCleanShutdown() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId)

            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .autoSave
            )
            // After saveDraft, cleanShutdown is false.
            try await repo.markCleanShutdown(projectId: projectId)

            let metadata = try await repo.loadMetadata(projectId: projectId)
            #expect(metadata?.cleanShutdown == true)
        }
    }

    // MARK: - Trigger Reasons

    @Suite("Trigger Reasons")
    struct TriggerReasonTests {

        @Test("Draft entry preserves trigger reason")
        func triggerReasonPreserved() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let projectId = makeProjectId()
            let project = makeProject(id: projectId)

            try await repo.saveDraft(
                projectId: projectId,
                project: project,
                reason: .significantEdit
            )

            let drafts = try await repo.listDrafts(projectId: projectId)
            #expect(drafts.count == 1)
            #expect(drafts[0].triggerReason == .significantEdit)
        }
    }

    // MARK: - ID Validation

    @Suite("ID Validation")
    struct IdValidationTests {

        @Test("Invalid project ID throws invalidPath")
        func invalidProjectId() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = DraftRepository(baseDirectory: tempDir)

            let project = makeProject()
            await #expect(throws: RepositoryError.self) {
                try await repo.saveDraft(
                    projectId: "INVALID!@#$",
                    project: project,
                    reason: .autoSave
                )
            }
        }
    }

    // MARK: - Persistence

    @Suite("Persistence")
    struct PersistenceTests {

        @Test("Drafts persist across repository instances")
        func persistsAcrossInstances() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }

            let projectId = makeProjectId()
            let project = makeProject(id: projectId, name: "Persistent Draft")

            let repo1 = DraftRepository(baseDirectory: tempDir)
            try await repo1.saveDraft(
                projectId: projectId,
                project: project,
                reason: .manualSave
            )

            let repo2 = DraftRepository(baseDirectory: tempDir)
            let loaded = try await repo2.loadLatestDraft(projectId: projectId)
            #expect(loaded != nil)
            #expect(loaded?.name == "Persistent Draft")
        }
    }
}
