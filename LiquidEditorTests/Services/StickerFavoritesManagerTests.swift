// StickerFavoritesManagerTests.swift
// LiquidEditorTests
//
// Tests for StickerFavoritesManager using Swift Testing.
// Uses a custom UserDefaults suite for test isolation.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("StickerFavoritesManager Tests")
@MainActor
struct StickerFavoritesManagerTests {

    // MARK: - Test Isolation

    /// Unique suite name for test isolation.
    private static let testSuiteName = "com.liquideditor.tests.sticker-favorites"

    /// Creates a clean manager with isolated UserDefaults.
    /// Removes the favorites key before each use to ensure a fresh state.
    private func makeManager() -> StickerFavoritesManager {
        let defaults = UserDefaults(suiteName: Self.testSuiteName)!
        defaults.removeObject(forKey: "sticker_favorites")
        defaults.synchronize()
        return StickerFavoritesManager(userDefaults: defaults)
    }

    /// Creates a manager that shares the same UserDefaults suite
    /// (without clearing), to test persistence across instances.
    private func makeManagerWithoutClearing() -> StickerFavoritesManager {
        let defaults = UserDefaults(suiteName: Self.testSuiteName)!
        return StickerFavoritesManager(userDefaults: defaults)
    }

    // MARK: - Initial State

    @Test("Initial state has empty favorites, not loaded, count is 0")
    func initialState() {
        let manager = makeManager()

        #expect(manager.favorites.isEmpty)
        #expect(!manager.isLoaded)
        #expect(manager.count == 0)
    }

    // MARK: - Load

    @Test("Load sets isLoaded to true")
    func loadSetsIsLoaded() {
        let manager = makeManager()

        manager.load()

        #expect(manager.isLoaded)
    }

    @Test("Load with no stored data results in empty favorites")
    func loadWithNoStoredData() {
        let manager = makeManager()

        manager.load()

        #expect(manager.favorites.isEmpty)
        #expect(manager.count == 0)
    }

    @Test("Load is idempotent - calling twice does not duplicate")
    func loadIsIdempotent() {
        let manager = makeManager()

        manager.load()
        manager.add("sticker_001")
        #expect(manager.count == 1)

        // Second load should be a no-op
        manager.load()
        #expect(manager.count == 1)
        #expect(manager.isLoaded)
    }

    // MARK: - Add

    @Test("Add inserts sticker into favorites")
    func addSticker() {
        let manager = makeManager()

        manager.add("sticker_001")

        #expect(manager.isFavorite("sticker_001"))
        #expect(manager.count == 1)
    }

    @Test("Add multiple stickers increases count")
    func addMultipleStickers() {
        let manager = makeManager()

        manager.add("sticker_001")
        manager.add("sticker_002")
        manager.add("sticker_003")

        #expect(manager.count == 3)
        #expect(manager.isFavorite("sticker_001"))
        #expect(manager.isFavorite("sticker_002"))
        #expect(manager.isFavorite("sticker_003"))
    }

    @Test("Add duplicate is a no-op, count stays same")
    func addDuplicate() {
        let manager = makeManager()

        manager.add("sticker_001")
        manager.add("sticker_001")

        #expect(manager.count == 1)
    }

    // MARK: - Remove

    @Test("Remove removes sticker from favorites")
    func removeSticker() {
        let manager = makeManager()

        manager.add("sticker_001")
        manager.remove("sticker_001")

        #expect(!manager.isFavorite("sticker_001"))
        #expect(manager.count == 0)
    }

    @Test("Remove non-existent sticker is a no-op")
    func removeNonExistent() {
        let manager = makeManager()

        manager.remove("sticker_nonexistent")

        #expect(manager.count == 0)
    }

    // MARK: - Toggle

    @Test("Toggle adds sticker and returns true")
    func toggleAdds() {
        let manager = makeManager()

        let result = manager.toggle("sticker_001")

        #expect(result == true)
        #expect(manager.isFavorite("sticker_001"))
        #expect(manager.count == 1)
    }

    @Test("Toggle removes sticker and returns false")
    func toggleRemoves() {
        let manager = makeManager()

        manager.add("sticker_001")
        let result = manager.toggle("sticker_001")

        #expect(result == false)
        #expect(!manager.isFavorite("sticker_001"))
        #expect(manager.count == 0)
    }

    @Test("Toggle twice returns to original state")
    func toggleTwice() {
        let manager = makeManager()

        let first = manager.toggle("sticker_001")
        let second = manager.toggle("sticker_001")

        #expect(first == true)
        #expect(second == false)
        #expect(!manager.isFavorite("sticker_001"))
        #expect(manager.count == 0)
    }

    // MARK: - Clear All

    @Test("ClearAll removes all favorites")
    func clearAll() {
        let manager = makeManager()

        manager.add("sticker_001")
        manager.add("sticker_002")
        manager.add("sticker_003")
        #expect(manager.count == 3)

        manager.clearAll()

        #expect(manager.count == 0)
        #expect(manager.favorites.isEmpty)
        #expect(!manager.isFavorite("sticker_001"))
    }

    @Test("ClearAll on empty favorites is safe")
    func clearAllEmpty() {
        let manager = makeManager()

        // Should not crash
        manager.clearAll()

        #expect(manager.count == 0)
        #expect(manager.favorites.isEmpty)
    }

    // MARK: - isFavorite

    @Test("isFavorite returns false for unknown sticker")
    func isFavoriteUnknown() {
        let manager = makeManager()

        #expect(!manager.isFavorite("sticker_unknown"))
    }

    @Test("isFavorite returns true for added sticker")
    func isFavoriteAdded() {
        let manager = makeManager()

        manager.add("sticker_001")

        #expect(manager.isFavorite("sticker_001"))
    }

    // MARK: - Persistence

    @Test("Favorites persist across manager instances")
    func persistence() {
        // First manager: add favorites
        let manager1 = makeManager()
        manager1.add("sticker_001")
        manager1.add("sticker_002")
        #expect(manager1.count == 2)

        // Second manager: load and verify (same suite, no clear)
        let manager2 = makeManagerWithoutClearing()
        manager2.load()

        #expect(manager2.isLoaded)
        #expect(manager2.count == 2)
        #expect(manager2.isFavorite("sticker_001"))
        #expect(manager2.isFavorite("sticker_002"))
    }

    @Test("ClearAll persists empty state")
    func clearAllPersists() {
        // First manager: add then clear
        let manager1 = makeManager()
        manager1.add("sticker_001")
        manager1.clearAll()

        // Second manager: load and verify empty
        let manager2 = makeManagerWithoutClearing()
        manager2.load()

        #expect(manager2.count == 0)
        #expect(manager2.favorites.isEmpty)
    }

    @Test("Remove persists across instances")
    func removePersists() {
        // First manager: add two, remove one
        let manager1 = makeManager()
        manager1.add("sticker_001")
        manager1.add("sticker_002")
        manager1.remove("sticker_001")

        // Second manager: verify
        let manager2 = makeManagerWithoutClearing()
        manager2.load()

        #expect(manager2.count == 1)
        #expect(!manager2.isFavorite("sticker_001"))
        #expect(manager2.isFavorite("sticker_002"))
    }

    @Test("Toggle persists across instances")
    func togglePersists() {
        // First manager: toggle on
        let manager1 = makeManager()
        _ = manager1.toggle("sticker_001")

        // Second manager: verify on
        let manager2 = makeManagerWithoutClearing()
        manager2.load()
        #expect(manager2.isFavorite("sticker_001"))

        // Toggle off
        _ = manager2.toggle("sticker_001")

        // Third manager: verify off
        let manager3 = makeManagerWithoutClearing()
        manager3.load()
        #expect(!manager3.isFavorite("sticker_001"))
    }
}
