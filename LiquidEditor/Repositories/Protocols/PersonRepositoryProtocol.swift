// PersonRepositoryProtocol.swift
// LiquidEditor
//
// Protocol for Person persistence operations.
// Enables dependency injection and testability.

import Foundation

// MARK: - PersonRepositoryProtocol

/// Protocol for persisting and retrieving people from the People library.
///
/// Implementations store `Person` objects with their reference images
/// and embeddings for re-identification.
protocol PersonRepositoryProtocol: Sendable {
    /// List all people in the library.
    ///
    /// - Returns: Array of all stored Person objects.
    /// - Throws: If the underlying storage cannot be read.
    func listAll() async throws -> [Person]

    /// Load a single person by ID.
    ///
    /// - Parameter id: The person's unique identifier.
    /// - Returns: The Person object.
    /// - Throws: If the person is not found or storage cannot be read.
    func load(id: String) async throws -> Person

    /// Save (create or update) a person.
    ///
    /// - Parameter person: The Person to save.
    /// - Throws: If the person cannot be persisted.
    func save(_ person: Person) async throws

    /// Delete a person by ID.
    ///
    /// - Parameter id: The person's unique identifier.
    /// - Throws: If the person cannot be deleted.
    func delete(id: String) async throws

    /// Check if a person exists.
    ///
    /// - Parameter id: The person's unique identifier.
    /// - Returns: True if the person exists.
    func exists(id: String) async -> Bool
}
