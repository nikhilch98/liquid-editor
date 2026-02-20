// ProjectDuplicateService.swift
// LiquidEditor
//
// Deep copy projects with new identities.
//
// Creates independent copies of projects where:
// - A new UUID is generated for the project
// - Timestamps are reset to now
// - Name is auto-incremented ("Copy", "Copy 2", etc.)
// - Media file references are shared (not duplicated on disk)

import Foundation
import os

// MARK: - ProjectDuplicateService

/// Service for duplicating projects with new identities.
///
/// Uses the `ProjectRepositoryProtocol` for persistence. The duplicate
/// gets a new UUID, fresh timestamps, and an auto-incremented name.
/// Media asset references are shared (no file duplication).
///
/// ## Usage
/// ```swift
/// let service = ProjectDuplicateService(
///     projectRepository: container.projectRepository
/// )
/// let copy = try await service.duplicateProject(id: "abc-123")
/// ```
///
/// ## Name Generation
/// The copy name follows this pattern:
/// - First copy: "{Original Name} Copy"
/// - Subsequent copies: "{Original Name} Copy 2", "Copy 3", etc.
///
/// Thread safety: Methods are `async` and delegate to the actor-isolated
/// `ProjectRepository`. No mutable state is held by this service.
struct ProjectDuplicateService: Sendable {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "ProjectDuplicateService"
    )

    // MARK: - Dependencies

    private let projectRepository: any ProjectRepositoryProtocol

    // MARK: - Initialization

    /// Create a duplicate service with the given repository.
    ///
    /// - Parameter projectRepository: Repository for loading and saving projects.
    init(projectRepository: any ProjectRepositoryProtocol) {
        self.projectRepository = projectRepository
    }

    // MARK: - Public API

    /// Duplicate a project by its ID.
    ///
    /// Loads the project from the repository, creates a deep copy with:
    /// - New UUID for the project
    /// - New name: "{originalName} Copy" (auto-incremented if name exists)
    /// - Reset timestamps (createdAt/modifiedAt = now)
    /// - Shared media references (no file duplication)
    ///
    /// - Parameters:
    ///   - id: The source project's unique identifier.
    ///   - existingNames: Optional pre-fetched list of existing project names
    ///     for uniqueness checking. If nil, names are loaded from the repository.
    /// - Returns: The newly created duplicate project.
    /// - Throws: `RepositoryError.notFound` if the source project does not exist.
    func duplicateProject(
        id: String,
        existingNames: [String]? = nil
    ) async throws -> Project {
        let original = try await projectRepository.load(id: id)
        return try await duplicateProjectData(
            original,
            existingNames: existingNames
        )
    }

    /// Duplicate a project from an in-memory Project object.
    ///
    /// If `existingNames` is provided, uses it for name uniqueness check
    /// instead of loading all project metadata from disk.
    ///
    /// - Parameters:
    ///   - original: The project to duplicate.
    ///   - existingNames: Optional pre-fetched list of existing project names.
    /// - Returns: The newly created duplicate project.
    func duplicateProjectData(
        _ original: Project,
        existingNames: [String]? = nil
    ) async throws -> Project {
        let newId = UUID().uuidString.lowercased()

        // Generate unique name.
        let names: [String]
        if let existingNames {
            names = existingNames
        } else {
            let allMetadata = try await projectRepository.listMetadata()
            names = allMetadata.map(\.name)
        }
        let newName = Self.generateUniqueCopyName(
            originalName: original.name,
            existingNames: names
        )

        // Create duplicate via repository's duplicate method.
        let duplicate = try await projectRepository.duplicate(
            id: original.id,
            newId: newId,
            newName: newName
        )

        Self.logger.info("Duplicated project '\(original.name)' as '\(newName)' (id: \(newId))")
        return duplicate
    }

    // MARK: - Name Generation

    /// Generate a unique copy name by checking against existing names.
    ///
    /// - Parameters:
    ///   - originalName: The source project's name.
    ///   - existingNames: All current project names.
    /// - Returns: A unique name like "MyProject Copy" or "MyProject Copy 2".
    static func generateUniqueCopyName(
        originalName: String,
        existingNames: [String]
    ) -> String {
        let nameSet = Set(existingNames)
        var candidate = "\(originalName) Copy"
        var counter = 2

        while nameSet.contains(candidate) {
            candidate = "\(originalName) Copy \(counter)"
            counter += 1
        }

        return candidate
    }
}
