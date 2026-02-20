// DraftRepository.swift
// LiquidEditor
//
// Concrete implementation of DraftRepositoryProtocol.
// Manages a per-project ring buffer of auto-saved project snapshots
// with crash-recovery detection.

import Foundation
import OSLog

// MARK: - DraftRepository

/// Actor-isolated repository for managing draft auto-saves.
///
/// ## Directory Layout
/// ```
/// ~/Documents/LiquidEditor/Drafts/{projectId}/
///   metadata.json       – DraftMetadata (ring buffer state, crash flag)
///   draft_0.json        – Project snapshot at slot 0
///   draft_1.json        – Project snapshot at slot 1
///   ...                 – Up to draft_4.json (5-slot ring buffer)
/// ```
///
/// ## Ring Buffer
/// Drafts are written to slots `0 ..< DraftMetadata.maxDrafts` in round-robin
/// order. `DraftMetadata.currentIndex` tracks the last written slot, and
/// `nextIndex` gives `(currentIndex + 1) % maxDrafts`.
///
/// ## Crash Recovery
/// On session start, `cleanShutdown` is set to `false`. If the app
/// terminates without calling `markCleanShutdown()`, the next launch can
/// detect the dirty flag via `needsCrashRecovery()` and offer to restore
/// the latest draft.
actor DraftRepository: DraftRepositoryProtocol {

    // MARK: - Constants

    private static let draftsSubpath = "LiquidEditor/Drafts"
    private static let metadataFileName = "metadata.json"
    private static let logger = Logger(subsystem: "LiquidEditor", category: "DraftRepository")

    /// Regex for validating project IDs (lowercase hex + hyphens only).
    private static let validIdPattern = try! NSRegularExpression(
        pattern: "^[a-f0-9-]+$"
    )

    // MARK: - State

    /// Base directory for all draft data.
    private let baseDirectory: URL

    // MARK: - JSON Coders

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Init

    init() {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        self.baseDirectory = documentsURL
            .appendingPathComponent(Self.draftsSubpath)
    }

    /// Designated initializer for testing with a custom base path.
    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // MARK: - Public API

    /// Save a project snapshot as a new draft.
    ///
    /// 1. Loads (or creates) the project's `DraftMetadata`.
    /// 2. Writes the full `Project` to `draft_{nextIndex}.json`.
    /// 3. Creates a `DraftEntry` with current statistics.
    /// 4. Updates the metadata via `withNewDraft()` and persists it.
    ///
    /// - Parameters:
    ///   - projectId: The project's unique identifier.
    ///   - project: The project snapshot to save.
    ///   - reason: Why this draft was triggered.
    /// - Throws: `RepositoryError.encodingFailed`, `RepositoryError.ioError`.
    func saveDraft(
        projectId: String,
        project: Project,
        reason: DraftTriggerReason
    ) async throws {
        try validateId(projectId)

        let projectDir = directoryURL(for: projectId)
        try ensureDirectory(at: projectDir)

        var metadata = try loadOrCreateMetadata(projectId: projectId)
        let slotIndex = metadata.nextIndex

        // Write project snapshot to the slot file.
        let slotFileName = draftFileName(for: slotIndex)
        let slotURL = projectDir.appendingPathComponent(slotFileName)

        let projectData: Data
        do {
            projectData = try encoder.encode(project)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode draft for project \(projectId): \(error.localizedDescription)"
            )
        }

        try writeData(projectData, to: slotURL)

        // Create the draft entry.
        let entry = DraftEntry(
            index: slotIndex,
            savedAt: Date(),
            clipCount: project.clipCount,
            timelineDurationMicros: project.durationMicros,
            triggerReason: reason
        )

        // Update and persist metadata.
        metadata = metadata.withNewDraft(entry)
        try persistMetadata(metadata, projectId: projectId)
    }

    /// Load the most recent draft snapshot for a project.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: The project snapshot from the latest draft slot, or nil if no drafts exist.
    /// - Throws: `RepositoryError.decodingFailed` if stored data is unreadable.
    func loadLatestDraft(projectId: String) async throws -> Project? {
        try validateId(projectId)

        guard let metadata = try? loadMetadataSync(projectId: projectId) else {
            return nil
        }

        guard let latestEntry = metadata.latestDraft else {
            return nil
        }

        return try loadDraftAtSlot(
            projectId: projectId,
            slotIndex: latestEntry.index
        )
    }

    /// Load a specific draft by its ring buffer slot index.
    ///
    /// - Parameters:
    ///   - projectId: The project's unique identifier.
    ///   - index: The ring buffer slot (0 ..< DraftMetadata.maxDrafts).
    /// - Returns: The project snapshot, or nil if slot is empty.
    /// - Throws: `RepositoryError.decodingFailed` if stored data is unreadable.
    func loadDraft(
        projectId: String,
        index: Int
    ) async throws -> Project? {
        // Validate index range
        guard index >= 0 && index < DraftMetadata.maxDrafts else {
            Self.logger.warning("Invalid draft index \(index) for project \(projectId). Valid range: 0..<\(DraftMetadata.maxDrafts)")
            return nil
        }
        return try loadDraftAtSlot(projectId: projectId, slotIndex: index)
    }

    /// Internal method to load draft by slot index.
    private func loadDraftAtSlot(
        projectId: String,
        slotIndex: Int
    ) throws -> Project? {
        let projectDir = directoryURL(for: projectId)
        let slotFileName = draftFileName(for: slotIndex)
        let slotURL = projectDir.appendingPathComponent(slotFileName)

        guard FileManager.default.fileExists(atPath: slotURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: slotURL)
        } catch {
            throw RepositoryError.ioError(
                "Failed to read draft slot \(slotIndex) for project \(projectId): \(error.localizedDescription)"
            )
        }

        do {
            return try decoder.decode(Project.self, from: data)
        } catch {
            throw RepositoryError.decodingFailed(
                "Failed to decode draft slot \(slotIndex) for project \(projectId): \(error.localizedDescription)"
            )
        }
    }

    /// Check whether the last session for a project shut down cleanly.
    ///
    /// If `false`, crash recovery should be offered to the user.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: `true` if crash recovery is needed.
    func needsCrashRecovery(projectId: String) async throws -> Bool {
        try validateId(projectId)

        let projectDir = directoryURL(for: projectId)
        let metadataURL = projectDir.appendingPathComponent(Self.metadataFileName)

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            // No draft metadata at all: nothing to recover.
            return false
        }

        guard let metadata = try? loadMetadataSync(projectId: projectId) else {
            return false
        }
        return !metadata.cleanShutdown
    }

    /// Mark the project session as cleanly shut down.
    ///
    /// Call this when the user explicitly saves and exits, or
    /// when the app transitions to background after a successful save.
    ///
    /// - Parameter projectId: The project's unique identifier.
    func markCleanShutdown(projectId: String) async throws {
        try validateId(projectId)

        var metadata = try loadOrCreateMetadata(projectId: projectId)
        metadata = metadata.markCleanShutdown()
        try persistMetadata(metadata, projectId: projectId)
    }

    /// Mark a new editing session as started (dirty state).
    ///
    /// Sets `cleanShutdown` to `false` so that an abnormal exit
    /// can be detected later via `needsCrashRecovery()`.
    ///
    /// - Parameter projectId: The project's unique identifier.
    func markSessionStarted(projectId: String) async throws {
        try validateId(projectId)

        var metadata = try loadOrCreateMetadata(projectId: projectId)
        metadata = metadata.markSessionStarted()
        try persistMetadata(metadata, projectId: projectId)
    }

    /// Check if any drafts exist for a project.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: `true` if at least one draft exists.
    func hasDraft(projectId: String) async -> Bool {
        (try? loadMetadataSync(projectId: projectId)) != nil
    }

    /// Load the draft metadata for a project.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: The draft metadata, or nil if it doesn't exist.
    /// - Throws: `RepositoryError.decodingFailed` if stored data is unreadable.
    func loadMetadata(projectId: String) async throws -> DraftMetadata? {
        try loadMetadataSync(projectId: projectId)
    }

    /// Internal synchronous method to load metadata.
    private func loadMetadataSync(projectId: String) throws -> DraftMetadata? {
        let projectDir = directoryURL(for: projectId)
        let metadataURL = projectDir.appendingPathComponent(Self.metadataFileName)

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw RepositoryError.notFound(
                "Draft metadata for project \(projectId)"
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: metadataURL)
        } catch {
            throw RepositoryError.ioError(
                "Failed to read draft metadata for project \(projectId): \(error.localizedDescription)"
            )
        }

        do {
            return try decoder.decode(DraftMetadata.self, from: data)
        } catch {
            throw RepositoryError.decodingFailed(
                "Failed to decode draft metadata for project \(projectId): \(error.localizedDescription)"
            )
        }
    }

    /// Delete all draft data for a project.
    ///
    /// - Parameter projectId: The project's unique identifier.
    func deleteDrafts(projectId: String) async throws {
        try validateId(projectId)

        let projectDir = directoryURL(for: projectId)
        guard FileManager.default.fileExists(atPath: projectDir.path) else {
            return // Nothing to delete.
        }

        do {
            try FileManager.default.removeItem(at: projectDir)
        } catch {
            throw RepositoryError.ioError(
                "Failed to delete drafts for project \(projectId): \(error.localizedDescription)"
            )
        }
    }

    /// List all draft entries for a project, sorted by save date (newest first).
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: Array of draft entries.
    func listDrafts(projectId: String) async throws -> [DraftEntry] {
        try validateId(projectId)

        let metadata = try loadOrCreateMetadata(projectId: projectId)
        return metadata.drafts.sorted { $0.savedAt > $1.savedAt }
    }

    // MARK: - Private Helpers

    /// Returns the directory URL for a given project's drafts.
    private func directoryURL(for projectId: String) -> URL {
        baseDirectory.appendingPathComponent(projectId)
    }

    /// Returns the draft slot filename for a given index.
    private func draftFileName(for slotIndex: Int) -> String {
        "draft_\(slotIndex).json"
    }

    /// Validates that a project ID matches the expected hex-UUID pattern.
    private func validateId(_ id: String) throws {
        let range = NSRange(id.startIndex..., in: id)
        guard Self.validIdPattern.firstMatch(in: id, range: range) != nil else {
            throw RepositoryError.invalidPath(
                "Invalid project ID: '\(id)'. Must match ^[a-f0-9-]+$"
            )
        }
    }

    /// Loads existing metadata or creates an empty one for new projects.
    private func loadOrCreateMetadata(projectId: String) throws -> DraftMetadata {
        let projectDir = directoryURL(for: projectId)
        let metadataURL = projectDir.appendingPathComponent(Self.metadataFileName)

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return DraftMetadata.empty(projectId: projectId)
        }

        let data: Data
        do {
            data = try Data(contentsOf: metadataURL)
        } catch {
            throw RepositoryError.ioError(
                "Failed to read draft metadata for project \(projectId): \(error.localizedDescription)"
            )
        }

        do {
            return try decoder.decode(DraftMetadata.self, from: data)
        } catch {
            // If metadata is corrupted, start fresh rather than crashing.
            Self.logger.error("Failed to decode draft metadata for project \(projectId): \(error.localizedDescription). Starting fresh.")
            return DraftMetadata.empty(projectId: projectId)
        }
    }

    /// Persists draft metadata to disk.
    private func persistMetadata(
        _ metadata: DraftMetadata,
        projectId: String
    ) throws {
        let projectDir = directoryURL(for: projectId)
        try ensureDirectory(at: projectDir)

        let data: Data
        do {
            data = try encoder.encode(metadata)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode draft metadata for project \(projectId): \(error.localizedDescription)"
            )
        }

        let metadataURL = projectDir.appendingPathComponent(Self.metadataFileName)
        try writeData(data, to: metadataURL)
    }

    /// Ensures a directory exists, creating it (and intermediates) if needed.
    private func ensureDirectory(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            } catch {
                throw RepositoryError.ioError(
                    "Failed to create directory at \(url.path): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Atomically writes data to a file URL.
    private func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RepositoryError.ioError(
                "Failed to write file at \(url.path): \(error.localizedDescription)"
            )
        }
    }
}
