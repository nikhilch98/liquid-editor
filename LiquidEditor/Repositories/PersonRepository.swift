// PersonRepository.swift
// LiquidEditor
//
// File-backed persistence for the People library.
// Stores Person objects as JSON files in the app's Documents directory.

import Foundation

// MARK: - PersonRepository

/// File-backed implementation of `PersonRepositoryProtocol`.
///
/// Stores each `Person` as a JSON file under `Documents/People/{id}.json`.
/// Thread safety is provided by the actor isolation.
actor PersonRepository: PersonRepositoryProtocol {

    // MARK: - Properties

    /// Root directory for people storage.
    private let storageDirectory: URL

    /// JSON encoder configured for ISO 8601 dates.
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    /// JSON decoder configured for ISO 8601 dates.
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Init

    init() {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        self.storageDirectory = documentsDir.appendingPathComponent("People", isDirectory: true)
    }

    /// Initialize with a custom storage directory (for testing).
    init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    // MARK: - PersonRepositoryProtocol

    func listAll() async throws -> [Person] {
        try ensureDirectoryExists()

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        var people: [Person] = []
        for fileURL in contents where fileURL.pathExtension == "json" {
            let data = try Data(contentsOf: fileURL)
            let person = try decoder.decode(Person.self, from: data)
            people.append(person)
        }

        return people.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func load(id: String) async throws -> Person {
        let fileURL = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RepositoryError.notFound(id)
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Person.self, from: data)
    }

    func save(_ person: Person) async throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(person)
        try data.write(to: fileURL(for: person.id), options: .atomic)
    }

    func delete(id: String) async throws {
        let fileURL = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RepositoryError.notFound(id)
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    func exists(id: String) async -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    // MARK: - Helpers

    private func fileURL(for id: String) -> URL {
        storageDirectory.appendingPathComponent("\(id).json")
    }

    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try fileManager.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
