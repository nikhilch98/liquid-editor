// FavoriteProjectsService.swift
// LiquidEditor
//
// F6-14: Starred / favorite projects.
//
// Tracks which project UUIDs the user has starred. Storage is a small
// set kept in UserDefaults — suitable for O(100) favorites. Entries
// persist across launches.
//
// Observable so that library UI can react to favorite toggles in real
// time.

import Foundation
import Observation

// MARK: - FavoriteProjectsService

/// Main-actor @Observable store for starred project IDs.
@MainActor
@Observable
final class FavoriteProjectsService {

    // MARK: - Constants

    /// UserDefaults key used for the persisted starred-ID blob.
    static let storageKey: String = "com.liquideditor.library.favorites.v1"

    // MARK: - Observable State

    /// Currently starred project IDs.
    private(set) var starredIDs: Set<UUID> = []

    // MARK: - Dependencies

    @ObservationIgnored
    private let defaults: UserDefaults

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Public API

    /// Mark `id` as starred. No-op if already starred.
    func star(_ id: UUID) {
        guard !starredIDs.contains(id) else { return }
        starredIDs.insert(id)
        persist()
    }

    /// Remove `id` from the starred set. No-op if not starred.
    func unstar(_ id: UUID) {
        guard starredIDs.contains(id) else { return }
        starredIDs.remove(id)
        persist()
    }

    /// Returns true iff `id` is currently starred.
    func isStarred(_ id: UUID) -> Bool {
        starredIDs.contains(id)
    }

    /// Flip the starred state for `id`.
    func toggle(_ id: UUID) {
        if starredIDs.contains(id) {
            starredIDs.remove(id)
        } else {
            starredIDs.insert(id)
        }
        persist()
    }

    /// Remove all stars. Useful for tests and settings-level "clear all"
    /// actions.
    func clearAll() {
        guard !starredIDs.isEmpty else { return }
        starredIDs.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([UUID].self, from: data)
            starredIDs = Set(decoded)
        } catch {
            starredIDs = []
        }
    }

    private func persist() {
        do {
            // Persist as a sorted array so the blob is deterministic —
            // easier to diff in tests and backups.
            let encoded = try JSONEncoder().encode(starredIDs.sorted(by: { $0.uuidString < $1.uuidString }))
            defaults.set(encoded, forKey: Self.storageKey)
        } catch {
            // Ignore: encoding UUIDs is infallible in practice.
        }
    }
}
