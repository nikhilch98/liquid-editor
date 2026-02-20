// StickerFavoritesManager.swift
// LiquidEditor
//
// Manages the user's favorited sticker assets.
// Persists the set of favorited sticker asset IDs to UserDefaults
// as a string array for lightweight key-value persistence.
//
// The favorites set is loaded lazily on first access and cached
// in memory for synchronous reads.
//
// Uses @Observable macro (iOS 17+) with @MainActor isolation
// for safe UI-bound state management.

import Foundation
import Observation
import os

// MARK: - StickerFavoritesManager

/// Manages the user's favorited sticker assets.
///
/// Persists favorites to `UserDefaults` as a string array.
/// Uses `@Observable` for reactive UI updates.
///
/// Usage:
/// ```swift
/// let manager = StickerFavoritesManager()
/// manager.load()
/// let isFav = manager.isFavorite("sticker_001")
/// let nowFavorited = manager.toggle("sticker_001")
/// ```
@Observable
@MainActor
final class StickerFavoritesManager {

    // MARK: - Constants

    /// UserDefaults key for the favorites list.
    private static let prefsKey = "sticker_favorites"

    /// Maximum number of favorites allowed (prevents unbounded growth).
    private static let maxFavorites = 1000

    // MARK: - Dependencies

    /// The UserDefaults instance used for persistence.
    /// Injected via init for testability.
    private let userDefaults: UserDefaults

    // MARK: - State

    /// In-memory set of favorited asset IDs.
    private(set) var favorites: Set<String> = []

    /// Whether favorites have been loaded from disk.
    private(set) var isLoaded: Bool = false

    // MARK: - Logger

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "StickerFavoritesManager"
    )

    // MARK: - Computed Properties

    /// Number of favorited stickers.
    var count: Int { favorites.count }

    // MARK: - Initialization

    /// Creates a new `StickerFavoritesManager`.
    ///
    /// - Parameter userDefaults: The `UserDefaults` instance to use for persistence.
    ///   Defaults to `.standard`. Pass a custom suite for test isolation.
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Query

    /// Check if a sticker is favorited.
    ///
    /// - Parameter assetId: The asset ID to check.
    /// - Returns: `true` if the sticker is in the favorites set.
    func isFavorite(_ assetId: String) -> Bool {
        favorites.contains(assetId)
    }

    // MARK: - Loading

    /// Load favorites from UserDefaults.
    ///
    /// Called once at app startup. Safe to call multiple times
    /// (no-op after first load).
    func load() {
        if isLoaded { return }

        if let stored = userDefaults.stringArray(forKey: Self.prefsKey) {
            favorites = Set(stored)
        }

        isLoaded = true
        logger.debug("Loaded \(self.favorites.count) sticker favorites")
    }

    // MARK: - Mutations

    /// Toggle a sticker's favorite status.
    ///
    /// - Parameter assetId: The asset ID to toggle.
    /// - Returns: `true` if the sticker is now favorited, `false` if unfavorited.
    @discardableResult
    func toggle(_ assetId: String) -> Bool {
        guard !assetId.isEmpty else {
            logger.warning("Attempted to toggle favorite with empty assetId")
            return false
        }

        let isNowFavorite = !favorites.contains(assetId)

        if isNowFavorite {
            guard favorites.count < Self.maxFavorites else {
                logger.warning("Cannot add favorite: limit of \(Self.maxFavorites) reached")
                return false
            }
            favorites.insert(assetId)
        } else {
            favorites.remove(assetId)
        }

        persist()
        return isNowFavorite
    }

    /// Add a sticker to favorites.
    ///
    /// No-op if already favorited or if max limit reached.
    ///
    /// - Parameter assetId: The asset ID to add.
    func add(_ assetId: String) {
        guard !assetId.isEmpty else {
            logger.warning("Attempted to add favorite with empty assetId")
            return
        }
        guard !favorites.contains(assetId) else { return }
        guard favorites.count < Self.maxFavorites else {
            logger.warning("Cannot add favorite: limit of \(Self.maxFavorites) reached")
            return
        }

        favorites.insert(assetId)
        persist()
    }

    /// Remove a sticker from favorites.
    ///
    /// No-op if not favorited or if assetId is empty.
    ///
    /// - Parameter assetId: The asset ID to remove.
    func remove(_ assetId: String) {
        guard !assetId.isEmpty else {
            logger.warning("Attempted to remove favorite with empty assetId")
            return
        }
        guard favorites.contains(assetId) else { return }

        favorites.remove(assetId)
        persist()
    }

    /// Clear all favorites.
    func clearAll() {
        guard !favorites.isEmpty else { return }

        favorites = []
        persist()
    }

    // MARK: - Persistence

    /// Persist current favorites to UserDefaults.
    private func persist() {
        userDefaults.set(Array(favorites), forKey: Self.prefsKey)
        logger.debug("Persisted \(self.favorites.count) sticker favorites")
    }
}
