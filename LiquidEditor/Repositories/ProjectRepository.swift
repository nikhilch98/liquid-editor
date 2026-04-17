// ProjectRepository.swift
// LiquidEditor
//
// Concrete implementation of ProjectRepositoryProtocol.
// Persists Project and ProjectMetadata to disk with SHA-256
// checksum envelopes for data integrity verification.

import Foundation
import CryptoKit

// MARK: - ChecksumEnvelope

/// JSON envelope that wraps encoded data with a SHA-256 checksum.
///
/// On write, the checksum is computed over the raw JSON bytes of `data`.
/// On read, the checksum is re-computed and compared to detect corruption.
private struct ChecksumEnvelope<T: Codable>: Codable {
    let checksum: String
    let data: T
}

// MARK: - ProjectRepository

/// Actor-isolated repository for persisting video editing projects.
///
/// ## Directory Layout
/// ```
/// ~/Documents/LiquidEditor/Projects/{projectId}/
///   project.json     – Full Project wrapped in a ChecksumEnvelope
///   metadata.json    – Extracted ProjectMetadata for fast listing
/// ```
///
/// ## Thread Safety
/// All mutable state is isolated to this actor, so no locks are required.
///
/// ## Data Integrity
/// Every `project.json` is wrapped in a checksum envelope. On load, the
/// SHA-256 checksum is re-computed and verified against the stored value.
actor ProjectRepository: ProjectRepositoryProtocol {

    // MARK: - Constants

    private static let projectFileName = "project.json"
    private static let metadataFileName = "metadata.json"
    private static let projectsSubpath = "LiquidEditor/Projects"


    // MARK: - Cached State

    /// Lazily resolved base directory for all projects.
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
            .appendingPathComponent(Self.projectsSubpath)
    }

    /// Designated initializer for testing with a custom base path.
    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // MARK: - ProjectRepositoryProtocol

    func save(_ project: Project) async throws {
        try validateId(project.id)

        let projectDir = directoryURL(for: project.id)
        try ensureDirectory(at: projectDir)

        // Encode project data.
        let projectData: Data
        do {
            projectData = try encoder.encode(project)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode project \(project.id): \(error.localizedDescription)"
            )
        }

        // Compute checksum and wrap in envelope.
        let checksum = computeChecksum(projectData)
        let envelope = ChecksumEnvelope(checksum: checksum, data: project)

        let envelopeData: Data
        do {
            envelopeData = try encoder.encode(envelope)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode envelope for project \(project.id): \(error.localizedDescription)"
            )
        }

        // Write project.json.
        let projectFileURL = projectDir.appendingPathComponent(Self.projectFileName)
        try writeData(envelopeData, to: projectFileURL)

        // Extract and write metadata.json alongside.
        let metadata = extractMetadata(from: project)
        let metadataData: Data
        do {
            metadataData = try encoder.encode(metadata)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode metadata for project \(project.id): \(error.localizedDescription)"
            )
        }

        let metadataFileURL = projectDir.appendingPathComponent(Self.metadataFileName)
        try writeData(metadataData, to: metadataFileURL)
    }

    func load(id: String) async throws -> Project {
        try validateId(id)

        let projectFileURL = directoryURL(for: id)
            .appendingPathComponent(Self.projectFileName)

        guard FileManager.default.fileExists(atPath: projectFileURL.path) else {
            throw RepositoryError.notFound("Project \(id)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: projectFileURL)
        } catch {
            throw RepositoryError.ioError(
                "Failed to read project file for \(id): \(error.localizedDescription)"
            )
        }

        let envelope: ChecksumEnvelope<Project>
        do {
            envelope = try decoder.decode(ChecksumEnvelope<Project>.self, from: data)
        } catch {
            throw RepositoryError.decodingFailed(
                "Failed to decode project \(id): \(error.localizedDescription)"
            )
        }

        // Re-encode the project from the envelope to verify checksum.
        let projectData: Data
        do {
            projectData = try encoder.encode(envelope.data)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to re-encode project \(id) for checksum verification: \(error.localizedDescription)"
            )
        }

        let computedChecksum = computeChecksum(projectData)
        guard computedChecksum == envelope.checksum else {
            throw RepositoryError.checksumMismatch(
                expected: envelope.checksum,
                actual: computedChecksum
            )
        }

        return envelope.data
    }

    func loadMetadata(id: String) async throws -> ProjectMetadata {
        try validateId(id)

        let metadataFileURL = directoryURL(for: id)
            .appendingPathComponent(Self.metadataFileName)

        guard FileManager.default.fileExists(atPath: metadataFileURL.path) else {
            throw RepositoryError.notFound("Metadata for project \(id)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: metadataFileURL)
        } catch {
            throw RepositoryError.ioError(
                "Failed to read metadata for project \(id): \(error.localizedDescription)"
            )
        }

        do {
            return try decoder.decode(ProjectMetadata.self, from: data)
        } catch {
            throw RepositoryError.decodingFailed(
                "Failed to decode metadata for project \(id): \(error.localizedDescription)"
            )
        }
    }

    func listMetadata() async throws -> [ProjectMetadata] {
        try ensureDirectory(at: baseDirectory)

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw RepositoryError.ioError(
                "Failed to enumerate projects directory: \(error.localizedDescription)"
            )
        }

        var metadataList: [ProjectMetadata] = []
        for dirURL in contents {
            let isDirectory = (try? dirURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { continue }

            let metadataFileURL = dirURL.appendingPathComponent(Self.metadataFileName)
            guard FileManager.default.fileExists(atPath: metadataFileURL.path) else { continue }

            do {
                let data = try Data(contentsOf: metadataFileURL)
                let metadata = try decoder.decode(ProjectMetadata.self, from: data)
                metadataList.append(metadata)
            } catch {
                // Skip corrupted entries; log in production.
                continue
            }
        }

        // Sort by modification date, newest first.
        metadataList.sort { $0.modifiedAt > $1.modifiedAt }
        return metadataList
    }

    func delete(id: String) async throws {
        try validateId(id)

        let projectDir = directoryURL(for: id)
        guard FileManager.default.fileExists(atPath: projectDir.path) else {
            throw RepositoryError.notFound("Project \(id)")
        }

        do {
            try FileManager.default.removeItem(at: projectDir)
        } catch {
            throw RepositoryError.ioError(
                "Failed to delete project \(id): \(error.localizedDescription)"
            )
        }
    }

    func exists(id: String) async -> Bool {
        guard (try? validateId(id)) != nil else { return false }
        let projectFileURL = directoryURL(for: id)
            .appendingPathComponent(Self.projectFileName)
        return FileManager.default.fileExists(atPath: projectFileURL.path)
    }

    func rename(id: String, newName: String) async throws {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.validationFailed("Project name cannot be empty")
        }

        var project = try await load(id: id)
        project = project.with(name: newName, modifiedAt: Date())
        try await save(project)
    }

    func duplicate(
        id: String,
        newId: String,
        newName: String
    ) async throws -> Project {
        try validateId(newId)

        guard !(await exists(id: newId)) else {
            throw RepositoryError.duplicateEntry("Project \(newId) already exists")
        }

        let source = try await load(id: id)
        let now = Date()
        let copy = source.with(
            id: newId,
            name: newName,
            createdAt: now,
            modifiedAt: now
        )

        try await save(copy)
        return copy
    }

    // MARK: - Private Helpers

    /// Returns the directory URL for a given project ID.
    private func directoryURL(for projectId: String) -> URL {
        baseDirectory.appendingPathComponent(projectId)
    }

    /// Validates that a project ID contains only lowercase hex digits and
    /// hyphens (equivalent to the pattern `^[a-f0-9-]+$`).
    private func validateId(_ id: String) throws {
        guard !id.isEmpty, id.allSatisfy(Self.isValidIdCharacter) else {
            throw RepositoryError.invalidPath(
                "Invalid project ID: '\(id)'. Must match ^[a-f0-9-]+$"
            )
        }
    }

    private static func isValidIdCharacter(_ c: Character) -> Bool {
        ("0"..."9").contains(c) || ("a"..."f").contains(c) || c == "-"
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

    /// Computes a truncated SHA-256 checksum (first 16 bytes as hex) over raw data.
    private func computeChecksum(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Extracts lightweight `ProjectMetadata` from a full `Project`.
    private func extractMetadata(from project: Project) -> ProjectMetadata {
        ProjectMetadata(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            modifiedAt: project.modifiedAt,
            thumbnailPath: project.thumbnailPath,
            timelineDurationMs: Int(project.durationMicros / 1000),
            clipCount: project.clipCount,
            version: project.version
        )
    }
}
