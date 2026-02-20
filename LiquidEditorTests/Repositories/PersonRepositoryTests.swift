// PersonRepositoryTests.swift
// LiquidEditorTests
//
// Tests for PersonRepository: CRUD, listing, persistence.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a minimal test Person.
private func makePerson(
    id: String = UUID().uuidString,
    name: String = "Test Person",
    createdAt: Date = Date(),
    modifiedAt: Date = Date(),
    images: [PersonImage] = []
) -> Person {
    Person(
        id: id,
        name: name,
        createdAt: createdAt,
        modifiedAt: modifiedAt,
        images: images
    )
}

/// Create a test PersonImage.
private func makePersonImage(
    id: String = UUID().uuidString,
    imagePath: String = "People/face.jpg",
    embedding: [Double] = [0.1, 0.2, 0.3, 0.4, 0.5],
    qualityScore: Double = 0.85,
    addedAt: Date = Date()
) -> PersonImage {
    PersonImage(
        id: id,
        imagePath: imagePath,
        embedding: embedding,
        qualityScore: qualityScore,
        addedAt: addedAt
    )
}

/// Create a temporary directory.
private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PersonRepoTests_\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Remove a temporary directory.
private func removeTempDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - PersonRepository Tests

@Suite("PersonRepository Tests")
struct PersonRepositoryTests {

    // MARK: - Save & Load

    @Suite("Save and Load")
    struct SaveLoadTests {

        @Test("Save and load returns person with matching fields")
        func saveAndLoad() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let person = makePerson(name: "Alice")
            try await repo.save(person)

            let loaded = try await repo.load(id: person.id)
            #expect(loaded.id == person.id)
            #expect(loaded.name == "Alice")
        }

        @Test("Save person with images preserves image data")
        func saveWithImages() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let image = makePersonImage(qualityScore: 0.9)
            let person = makePerson(name: "Bob", images: [image])
            try await repo.save(person)

            let loaded = try await repo.load(id: person.id)
            #expect(loaded.images.count == 1)
            #expect(loaded.images[0].id == image.id)
            #expect(loaded.images[0].qualityScore == 0.9)
            #expect(loaded.images[0].embedding == image.embedding)
        }

        @Test("Overwrite existing person with same ID")
        func overwriteExisting() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let person = makePerson(name: "Version 1")
            try await repo.save(person)

            let updated = person.with(name: "Version 2", modifiedAt: Date())
            try await repo.save(updated)

            let loaded = try await repo.load(id: person.id)
            #expect(loaded.name == "Version 2")
        }

        @Test("Load non-existent person throws notFound")
        func loadNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            await #expect(throws: RepositoryError.self) {
                _ = try await repo.load(id: "nonexistent-id")
            }
        }
    }

    // MARK: - List All

    @Suite("List All")
    struct ListAllTests {

        @Test("List all returns all saved people sorted by modifiedAt descending")
        func listAllSorted() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let now = Date()
            let p1 = makePerson(name: "Older", modifiedAt: now.addingTimeInterval(-100))
            let p2 = makePerson(name: "Newer", modifiedAt: now)

            try await repo.save(p1)
            try await repo.save(p2)

            let all = try await repo.listAll()
            #expect(all.count == 2)
            #expect(all[0].name == "Newer")
            #expect(all[1].name == "Older")
        }

        @Test("List all on empty directory returns empty array")
        func listAllEmpty() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let all = try await repo.listAll()
            #expect(all.isEmpty)
        }

        @Test("List all returns correct count after multiple saves")
        func listAllCount() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            for i in 0..<5 {
                try await repo.save(makePerson(name: "Person \(i)"))
            }

            let all = try await repo.listAll()
            #expect(all.count == 5)
        }
    }

    // MARK: - Delete

    @Suite("Delete")
    struct DeleteTests {

        @Test("Delete removes person")
        func deletePerson() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let person = makePerson()
            try await repo.save(person)
            #expect(await repo.exists(id: person.id))

            try await repo.delete(id: person.id)
            #expect(await !repo.exists(id: person.id))
        }

        @Test("Delete non-existent person throws notFound")
        func deleteNonExistent() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            await #expect(throws: RepositoryError.self) {
                try await repo.delete(id: "nonexistent-id")
            }
        }

        @Test("Delete only removes targeted person")
        func deleteOnlyTarget() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let keep = makePerson(name: "Keep")
            let remove = makePerson(name: "Remove")
            try await repo.save(keep)
            try await repo.save(remove)

            try await repo.delete(id: remove.id)

            #expect(await repo.exists(id: keep.id))
            #expect(await !repo.exists(id: remove.id))

            let all = try await repo.listAll()
            #expect(all.count == 1)
            #expect(all[0].name == "Keep")
        }
    }

    // MARK: - Exists

    @Suite("Exists")
    struct ExistsTests {

        @Test("Exists returns true for saved person")
        func existsTrue() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let person = makePerson()
            try await repo.save(person)

            #expect(await repo.exists(id: person.id))
        }

        @Test("Exists returns false for non-existent person")
        func existsFalse() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            #expect(await !repo.exists(id: "nonexistent"))
        }
    }

    // MARK: - Persistence Across Instances

    @Suite("Persistence")
    struct PersistenceTests {

        @Test("Data persists across repository instances")
        func persistsAcrossInstances() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }

            let person = makePerson(name: "Persistent Person")

            let repo1 = PersonRepository(storageDirectory: tempDir)
            try await repo1.save(person)

            let repo2 = PersonRepository(storageDirectory: tempDir)
            let loaded = try await repo2.load(id: person.id)
            #expect(loaded.name == "Persistent Person")
        }
    }

    // MARK: - Multiple Images

    @Suite("Multiple Images")
    struct MultipleImagesTests {

        @Test("Person with multiple images round-trips correctly")
        func multipleImages() async throws {
            let tempDir = makeTempDir()
            defer { removeTempDir(tempDir) }
            let repo = PersonRepository(storageDirectory: tempDir)

            let images = (0..<3).map { i in
                makePersonImage(
                    imagePath: "People/face_\(i).jpg",
                    embedding: Array(repeating: Double(i), count: 5),
                    qualityScore: Double(i) * 0.3
                )
            }
            let person = makePerson(name: "Multi Image", images: images)
            try await repo.save(person)

            let loaded = try await repo.load(id: person.id)
            #expect(loaded.images.count == 3)

            for i in 0..<3 {
                #expect(loaded.images[i].imagePath == "People/face_\(i).jpg")
                #expect(loaded.images[i].qualityScore == Double(i) * 0.3)
            }
        }
    }
}
