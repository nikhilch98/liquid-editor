// CollectionsService.swift
// LiquidEditor
//
// F6-13: Collections CRUD + move-to-collection.
//
// Users can group projects into named, color-labelled collections
// (e.g. "Reels", "Client Work"). A project may belong to at most one
// collection at a time — moving to a new collection removes it from any
// previous collection, and moving to `nil` removes membership.
//
// Persistence is via UserDefaults as a Codable blob. This suffices for
// a lightweight metadata list; larger datasets should migrate to a
// dedicated SQLite/CoreData store, but F6 specs call for UserDefaults.

import Foundation
import Observation

// MARK: - CollectionsService

/// Main-actor @Observable store for user-defined project collections.
@MainActor
@Observable
final class CollectionsService {

    // MARK: - Nested Types

    /// A user-defined, named group of projects.
    struct Collection: Identifiable, Codable, Sendable, Equatable, Hashable {
        /// Stable unique identifier.
        let id: UUID

        /// Display name shown in the library UI.
        var name: String

        /// Hex string (e.g. `"#FF5733"`) used as the collection's tint.
        var colorHex: String

        /// Member project IDs. Order is preserved so users can reorder
        /// projects inside a collection in the UI.
        var projectIDs: [UUID]

        init(
            id: UUID = UUID(),
            name: String,
            colorHex: String,
            projectIDs: [UUID] = []
        ) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.projectIDs = projectIDs
        }
    }

    // MARK: - Constants

    /// UserDefaults key used for the persisted collections blob.
    static let storageKey: String = "com.liquideditor.library.collections.v1"

    // MARK: - Observable State

    /// All collections, ordered as last persisted.
    private(set) var collections: [Collection] = []

    // MARK: - Dependencies

    @ObservationIgnored
    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - CRUD

    /// Create a new collection with the given name and color.
    @discardableResult
    func create(name: String, colorHex: String) -> Collection {
        let collection = Collection(name: name, colorHex: colorHex)
        collections.append(collection)
        persist()
        return collection
    }

    /// Rename an existing collection. No-op if `id` is unknown.
    func rename(id: UUID, to newName: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].name = newName
        persist()
    }

    /// Recolor an existing collection.
    func recolor(id: UUID, to newColorHex: String) {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].colorHex = newColorHex
        persist()
    }

    /// Delete a collection. Projects previously in the collection are
    /// not themselves removed — only the grouping is discarded.
    func delete(id: UUID) {
        collections.removeAll { $0.id == id }
        persist()
    }

    /// Move a project to a target collection, or remove it from any
    /// collection if `collectionID` is `nil`.
    ///
    /// - Parameters:
    ///   - projectID: project UUID to move.
    ///   - collectionID: destination collection UUID, or `nil` to
    ///     detach from all collections.
    func move(projectID: UUID, to collectionID: UUID?) {
        // First, remove the project from every collection it's in.
        for i in collections.indices {
            collections[i].projectIDs.removeAll { $0 == projectID }
        }

        // Then add to the target, if any.
        if let collectionID,
           let targetIdx = collections.firstIndex(where: { $0.id == collectionID }) {
            collections[targetIdx].projectIDs.append(projectID)
        }

        persist()
    }

    // MARK: - Queries

    /// Returns the collection currently containing `projectID`, if any.
    func collection(for projectID: UUID) -> Collection? {
        collections.first { $0.projectIDs.contains(projectID) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([Collection].self, from: data)
            collections = decoded
        } catch {
            // Corrupted blob — start fresh rather than crashing.
            collections = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(collections)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // Encoding Codable arrays is near-guaranteed; ignore.
        }
    }
}
