// RepositoryContainer.swift
// LiquidEditor
//
// Dependency injection container for all repository instances.
// Provides a shared singleton with default implementations and
// an initializer for injecting test doubles.

import Foundation

// MARK: - RepositoryContainer

/// Dependency injection container for all repository instances.
///
/// Holds references to every repository protocol, allowing the app to
/// access persistence through a single entry point. The shared singleton
/// uses default (file-backed) implementations; the custom initializer
/// accepts any conforming types for testing.
///
/// ## Production Usage
/// ```swift
/// let container = RepositoryContainer.shared
/// let project = try await container.projectRepository.load(id: "abc")
/// let manifests = try await container.backupRepository.listBackups()
/// ```
///
/// ## Testing Usage
/// ```swift
/// let testContainer = RepositoryContainer(
///     projectRepository: MockProjectRepository(),
///     mediaAssetRepository: MockMediaAssetRepository(),
///     draftRepository: MockDraftRepository(),
///     backupRepository: MockBackupRepository(),
///     preferencesRepository: MockPreferencesRepository(),
///     personRepository: MockPersonRepository()
/// )
/// ```
///
/// Thread safety: The container itself is immutable after initialization.
/// Individual repositories handle their own concurrency (actors or locks).
/// Marked `@unchecked Sendable` because all stored properties are `Sendable`
/// protocol existentials whose underlying types guarantee thread safety.
final class RepositoryContainer: @unchecked Sendable {

    // MARK: - Shared Instance

    /// Shared singleton instance with default implementations.
    ///
    /// Uses file-backed repositories that persist data to the app's
    /// Documents directory and UserDefaults.
    static let shared = RepositoryContainer()

    // MARK: - Repository References

    /// Repository for persisting and retrieving full projects.
    let projectRepository: any ProjectRepositoryProtocol

    /// Repository for the media asset registry.
    let mediaAssetRepository: any MediaAssetRepositoryProtocol

    /// Repository for draft auto-saves and crash recovery.
    let draftRepository: any DraftRepositoryProtocol

    /// Repository for creating and restoring project backups.
    let backupRepository: any BackupRepositoryProtocol

    /// Repository for user preferences (UserDefaults-backed).
    let preferencesRepository: any PreferencesRepositoryProtocol

    /// Repository for the People library (person detection data).
    let personRepository: any PersonRepositoryProtocol

    // MARK: - Default Initialization

    /// Create a container with default (production) implementations.
    ///
    /// Each repository is instantiated with its default configuration,
    /// storing data under the app's Documents directory.
    init() {
        self.projectRepository = ProjectRepository()
        self.mediaAssetRepository = MediaAssetRepository()
        self.draftRepository = DraftRepository()
        self.backupRepository = BackupRepository()
        self.preferencesRepository = PreferencesRepository()
        self.personRepository = PersonRepository()
    }

    // MARK: - Custom Initialization (Testing)

    /// Create a container with custom repository implementations.
    ///
    /// Use this initializer to inject mock or stub repositories for
    /// unit and integration testing.
    ///
    /// - Parameters:
    ///   - projectRepository: Project persistence implementation.
    ///   - mediaAssetRepository: Media asset registry implementation.
    ///   - draftRepository: Draft/auto-save implementation.
    ///   - backupRepository: Backup archive implementation.
    ///   - preferencesRepository: Preferences storage implementation.
    ///   - personRepository: Person persistence implementation.
    init(
        projectRepository: any ProjectRepositoryProtocol,
        mediaAssetRepository: any MediaAssetRepositoryProtocol,
        draftRepository: any DraftRepositoryProtocol,
        backupRepository: any BackupRepositoryProtocol,
        preferencesRepository: any PreferencesRepositoryProtocol,
        personRepository: any PersonRepositoryProtocol = PersonRepository()
    ) {
        self.projectRepository = projectRepository
        self.mediaAssetRepository = mediaAssetRepository
        self.draftRepository = draftRepository
        self.backupRepository = backupRepository
        self.preferencesRepository = preferencesRepository
        self.personRepository = personRepository
    }
}
