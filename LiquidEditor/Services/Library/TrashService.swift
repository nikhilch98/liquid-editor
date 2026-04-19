// TrashService.swift
// LiquidEditor
//
// F6-15: Trash flow — soft-delete, restore, empty-trash, auto-purge.
//
// When the user deletes a project from the library it is moved into the
// trash rather than being destroyed immediately. Projects sit in trash
// for up to `autoPurgeDays` (default 30) before being permanently
// purged. The user may also manually empty the trash.
//
// Storage:
//   • Metadata list  → UserDefaults (small Codable blob)
//   • Project bundles → FileManager-managed trash directory under
//     Application Support. Each trashed project gets its own file keyed
//     by UUID so restore() can return the original metadata payload.

import Foundation
import Observation

// MARK: - TrashError

enum TrashError: Error, Sendable, Equatable {
    case trashDirectoryUnavailable
    case writeFailed
    case removeFailed
}

// MARK: - TrashService

/// Main-actor @Observable service managing the project trash.
@MainActor
@Observable
final class TrashService {

    // MARK: - Nested Types

    /// One entry in the trash, capturing the project that was deleted.
    struct TrashedProject: Identifiable, Codable, Sendable, Equatable, Hashable {
        /// Unique identifier of the project that was deleted.
        let id: UUID

        /// Encoded project payload to allow full restoration.
        let originalMetadata: Data

        /// Timestamp at which the project was trashed.
        let deletedAt: Date

        init(id: UUID, originalMetadata: Data, deletedAt: Date) {
            self.id = id
            self.originalMetadata = originalMetadata
            self.deletedAt = deletedAt
        }
    }

    // MARK: - Constants

    /// UserDefaults key for the persisted trash index.
    static let storageKey: String = "com.liquideditor.library.trash.v1"

    /// Directory name under Application Support where trashed bundles
    /// live on disk.
    static let trashDirectoryName: String = "LiquidEditor-Trash"

    /// Default auto-purge horizon.
    static let defaultAutoPurgeDays: Int = 30

    // MARK: - Observable State

    /// All currently trashed projects, ordered newest-first.
    private(set) var trashedProjects: [TrashedProject] = []

    // MARK: - Dependencies

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let fileManager: FileManager

    @ObservationIgnored
    private let now: @MainActor () -> Date

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.now = now
        load()
    }

    // MARK: - Public API

    /// Soft-delete a project — adds it to trash and writes its metadata
    /// payload to disk. Replaces any previous trash entry with the same
    /// id.
    ///
    /// - Parameters:
    ///   - projectID: UUID of the project being deleted.
    ///   - metadata: encoded metadata / project payload to retain for
    ///     later restore.
    func softDelete(projectID: UUID, metadata: Data) {
        // Remove prior entry for the same id if one exists.
        trashedProjects.removeAll { $0.id == projectID }

        let entry = TrashedProject(
            id: projectID,
            originalMetadata: metadata,
            deletedAt: now()
        )
        trashedProjects.insert(entry, at: 0)

        // Best-effort file-system mirror so large metadata blobs don't
        // bloat UserDefaults when the trash is long.
        try? writeBundle(id: projectID, data: metadata)

        persist()
    }

    /// Restore a trashed project, returning its original metadata.
    ///
    /// - Returns: the stored metadata if the entry existed, else `nil`.
    @discardableResult
    func restore(id: UUID) -> Data? {
        guard let idx = trashedProjects.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let entry = trashedProjects.remove(at: idx)
        try? removeBundle(id: id)
        persist()
        return entry.originalMetadata
    }

    /// Empty the trash entirely. Files are best-effort removed; index
    /// is cleared.
    func emptyTrash() async throws {
        let ids = trashedProjects.map(\.id)
        trashedProjects.removeAll()
        persist()

        for id in ids {
            try? removeBundle(id: id)
        }

        // Best-effort: remove the directory if empty.
        if let dir = try? trashDirectoryURL() {
            if (try? fileManager.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
                try? fileManager.removeItem(at: dir)
            }
        }
    }

    /// Purge any trash entries older than `days` from now.
    ///
    /// Pass `0` to purge everything regardless of age.
    func purgeOlderThan(days: Int) {
        let cutoff = now().addingTimeInterval(-TimeInterval(days) * 86_400)
        let expired = trashedProjects.filter { $0.deletedAt <= cutoff }
        guard !expired.isEmpty else { return }

        for entry in expired {
            try? removeBundle(id: entry.id)
        }

        trashedProjects.removeAll { $0.deletedAt <= cutoff }
        persist()
    }

    /// Convenience for the default 30-day retention policy.
    func runAutoPurge() {
        purgeOlderThan(days: Self.defaultAutoPurgeDays)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([TrashedProject].self, from: data)
            trashedProjects = decoded
        } catch {
            trashedProjects = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(trashedProjects)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // Ignore: Codable failure is near-impossible here.
        }
    }

    // MARK: - FileManager helpers

    private func trashDirectoryURL() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(Self.trashDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }
        return dir
    }

    private func bundleURL(for id: UUID) throws -> URL {
        try trashDirectoryURL().appendingPathComponent("\(id.uuidString).trashbin")
    }

    private func writeBundle(id: UUID, data: Data) throws {
        let url = try bundleURL(for: id)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw TrashError.writeFailed
        }
    }

    private func removeBundle(id: UUID) throws {
        let url = try bundleURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw TrashError.removeFailed
            }
        }
    }
}
