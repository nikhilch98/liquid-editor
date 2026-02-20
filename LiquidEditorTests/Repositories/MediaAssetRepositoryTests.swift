// MediaAssetRepositoryTests.swift
// LiquidEditorTests
//
// Tests for MediaAssetRepository: CRUD, content hash indexing, link status, dedup.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a minimal test MediaAsset.
private func makeAsset(
    id: String = UUID().uuidString,
    contentHash: String = UUID().uuidString,
    relativePath: String = "Videos/test.mov",
    originalFilename: String = "test.mov",
    type: MediaType = .video,
    durationMicroseconds: TimeMicros = 5_000_000,
    width: Int = 1920,
    height: Int = 1080,
    fileSize: Int = 10_000_000,
    importedAt: Date = Date(),
    isLinked: Bool = true
) -> MediaAsset {
    MediaAsset(
        id: id,
        contentHash: contentHash,
        relativePath: relativePath,
        originalFilename: originalFilename,
        type: type,
        durationMicroseconds: durationMicroseconds,
        width: width,
        height: height,
        fileSize: fileSize,
        importedAt: importedAt,
        isLinked: isLinked
    )
}

/// Create a temporary directory and return its URL.
private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("MediaAssetRepoTests_\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Remove a temporary directory.
private func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - MediaAssetRepository Tests

@Suite("MediaAssetRepository Tests")
struct MediaAssetRepositoryTests {

    // MARK: - Save & Load

    @Suite("Save and Load")
    struct SaveLoadTests {

        @Test("Save and load returns asset with matching fields")
        func saveAndLoad() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let asset = makeAsset(originalFilename: "clip.mov")
            try await repo.save(asset)

            let loaded = try await repo.load(id: asset.id)
            #expect(loaded.id == asset.id)
            #expect(loaded.originalFilename == "clip.mov")
            #expect(loaded.contentHash == asset.contentHash)
            #expect(loaded.type == .video)
            #expect(loaded.width == 1920)
            #expect(loaded.height == 1080)
        }

        @Test("Overwrite existing asset with same ID")
        func overwriteExisting() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let asset = makeAsset(originalFilename: "v1.mov")
            try await repo.save(asset)

            let updated = asset.with(originalFilename: "v2.mov")
            try await repo.save(updated)

            let loaded = try await repo.load(id: asset.id)
            #expect(loaded.originalFilename == "v2.mov")
        }

        @Test("Load non-existent asset throws notFound")
        func loadNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            await #expect(throws: RepositoryError.self) {
                _ = try await repo.load(id: "nonexistent-id")
            }
        }
    }

    // MARK: - List All

    @Suite("List All")
    struct ListAllTests {

        @Test("List all returns all saved assets")
        func listAll() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let a1 = makeAsset(originalFilename: "a.mov")
            let a2 = makeAsset(originalFilename: "b.mov")
            let a3 = makeAsset(originalFilename: "c.png", type: .image)

            try await repo.save(a1)
            try await repo.save(a2)
            try await repo.save(a3)

            let all = try await repo.listAll()
            #expect(all.count == 3)
            let ids = Set(all.map(\.id))
            #expect(ids.contains(a1.id))
            #expect(ids.contains(a2.id))
            #expect(ids.contains(a3.id))
        }

        @Test("List all on empty registry returns empty array")
        func listAllEmpty() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let all = try await repo.listAll()
            #expect(all.isEmpty)
        }
    }

    // MARK: - Delete

    @Suite("Delete")
    struct DeleteTests {

        @Test("Delete removes asset")
        func deleteAsset() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let asset = makeAsset()
            try await repo.save(asset)
            #expect(await repo.exists(id: asset.id))

            try await repo.delete(id: asset.id)
            #expect(await !repo.exists(id: asset.id))
        }

        @Test("Delete non-existent asset throws notFound")
        func deleteNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            await #expect(throws: RepositoryError.self) {
                try await repo.delete(id: "nonexistent-id")
            }
        }

        @Test("Delete removes asset from content hash index")
        func deleteUpdatesHashIndex() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let hash = "shared-hash-123"
            let asset = makeAsset(contentHash: hash)
            try await repo.save(asset)

            let beforeDelete = try await repo.loadByContentHash(hash)
            #expect(beforeDelete.count == 1)

            try await repo.delete(id: asset.id)

            let afterDelete = try await repo.loadByContentHash(hash)
            #expect(afterDelete.isEmpty)
        }
    }

    // MARK: - Exists

    @Suite("Exists")
    struct ExistsTests {

        @Test("Exists returns true for saved asset")
        func existsTrue() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let asset = makeAsset()
            try await repo.save(asset)

            #expect(await repo.exists(id: asset.id))
        }

        @Test("Exists returns false for non-existent asset")
        func existsFalse() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            #expect(await !repo.exists(id: "nonexistent"))
        }
    }

    // MARK: - Content Hash Index

    @Suite("Content Hash Index")
    struct ContentHashTests {

        @Test("Load by content hash finds matching assets")
        func loadByContentHash() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let sharedHash = "abc123def456"
            let a1 = makeAsset(contentHash: sharedHash)
            let a2 = makeAsset(contentHash: sharedHash)
            let a3 = makeAsset(contentHash: "different-hash")

            try await repo.save(a1)
            try await repo.save(a2)
            try await repo.save(a3)

            let matches = try await repo.loadByContentHash(sharedHash)
            #expect(matches.count == 2)
            let ids = Set(matches.map(\.id))
            #expect(ids.contains(a1.id))
            #expect(ids.contains(a2.id))
        }

        @Test("Load by content hash returns empty for unknown hash")
        func loadByContentHashEmpty() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let asset = makeAsset(contentHash: "known-hash")
            try await repo.save(asset)

            let matches = try await repo.loadByContentHash("unknown-hash")
            #expect(matches.isEmpty)
        }

        @Test("Overwriting asset updates content hash index")
        func overwriteUpdatesHashIndex() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let oldHash = "old-hash"
            let newHash = "new-hash"
            let asset = makeAsset(contentHash: oldHash)
            try await repo.save(asset)

            // Overwrite with new hash.
            let updated = asset.with(contentHash: newHash)
            try await repo.save(updated)

            let oldMatches = try await repo.loadByContentHash(oldHash)
            #expect(oldMatches.isEmpty)

            let newMatches = try await repo.loadByContentHash(newHash)
            #expect(newMatches.count == 1)
            #expect(newMatches[0].id == asset.id)
        }
    }

    // MARK: - Link Status

    @Suite("Link Status")
    struct LinkStatusTests {

        @Test("Update link status to unlinked")
        func markUnlinked() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let asset = makeAsset(isLinked: true)
            try await repo.save(asset)

            try await repo.updateLinkStatus(
                assetId: asset.id,
                newRelativePath: asset.relativePath,
                isLinked: false
            )

            let loaded = try await repo.load(id: asset.id)
            #expect(!loaded.isLinked)
        }

        @Test("Update link status to linked with new path")
        func markLinked() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let asset = makeAsset(relativePath: "old/path.mov", isLinked: false)
            try await repo.save(asset)

            try await repo.updateLinkStatus(
                assetId: asset.id,
                newRelativePath: "new/path.mov",
                isLinked: true
            )

            let loaded = try await repo.load(id: asset.id)
            #expect(loaded.isLinked)
            #expect(loaded.relativePath == "new/path.mov")
        }

        @Test("Update link status for non-existent asset throws notFound")
        func updateLinkNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            await #expect(throws: RepositoryError.self) {
                try await repo.updateLinkStatus(
                    assetId: "nonexistent",
                    newRelativePath: "path.mov",
                    isLinked: true
                )
            }
        }

        @Test("Find unlinked assets returns only unlinked")
        func findUnlinked() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            let linked = makeAsset(isLinked: true)
            let unlinked = makeAsset(isLinked: false)

            try await repo.save(linked)
            try await repo.save(unlinked)

            let results = try await repo.findUnlinkedAssets()
            #expect(results.count == 1)
            #expect(results[0].id == unlinked.id)
        }

        @Test("Find unlinked returns empty when all linked")
        func findUnlinkedEmpty() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = MediaAssetRepository(baseDirectory: tempDir)

            try await repo.save(makeAsset(isLinked: true))
            try await repo.save(makeAsset(isLinked: true))

            let results = try await repo.findUnlinkedAssets()
            #expect(results.isEmpty)
        }
    }

    // MARK: - Persistence Across Instances

    @Suite("Persistence")
    struct PersistenceTests {

        @Test("Data persists across repository instances")
        func persistsAcrossInstances() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }

            let asset = makeAsset(originalFilename: "persistent.mov")

            let repo1 = MediaAssetRepository(baseDirectory: tempDir)
            try await repo1.save(asset)

            let repo2 = MediaAssetRepository(baseDirectory: tempDir)
            let loaded = try await repo2.load(id: asset.id)
            #expect(loaded.originalFilename == "persistent.mov")
        }

        @Test("Content hash index persists across instances")
        func hashIndexPersists() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }

            let hash = "persistent-hash"
            let asset = makeAsset(contentHash: hash)

            let repo1 = MediaAssetRepository(baseDirectory: tempDir)
            try await repo1.save(asset)

            let repo2 = MediaAssetRepository(baseDirectory: tempDir)
            let matches = try await repo2.loadByContentHash(hash)
            #expect(matches.count == 1)
            #expect(matches[0].id == asset.id)
        }
    }
}
