// PreferencesRepositoryTests.swift
// LiquidEditorTests
//
// Tests for PreferencesRepository: get/set primitives, codable, removal, clearAll.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a unique suite name for UserDefaults isolation.
private func makeUniqueSuite() -> String {
    "com.liquideditor.tests.prefs.\(UUID().uuidString)"
}

/// Clean up a UserDefaults suite.
private func removeSuite(_ suiteName: String) {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
}

// MARK: - Test Codable Type

/// A simple Codable struct for testing generic get/set.
private struct TestSettings: Codable, Equatable, Sendable {
    let theme: String
    let fontSize: Int
    let isDarkMode: Bool
}

// MARK: - PreferencesRepository Tests

@Suite("PreferencesRepository Tests")
struct PreferencesRepositoryTests {

    // MARK: - String

    @Suite("String Preferences")
    struct StringTests {

        @Test("Set and get string value")
        func setAndGetString() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set("1080p", forKey: "resolution")
            let value = repo.string(forKey: "resolution")
            #expect(value == "1080p")
        }

        @Test("Get non-existent string returns nil")
        func getNonExistentString() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.string(forKey: "missing") == nil)
        }
    }

    // MARK: - Int

    @Suite("Int Preferences")
    struct IntTests {

        @Test("Set and get int value")
        func setAndGetInt() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(42, forKey: "maxUndo")
            let value = repo.int(forKey: "maxUndo")
            #expect(value == 42)
        }

        @Test("Get non-existent int returns nil")
        func getNonExistentInt() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.int(forKey: "missing") == nil)
        }
    }

    // MARK: - Double

    @Suite("Double Preferences")
    struct DoubleTests {

        @Test("Set and get double value")
        func setAndGetDouble() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(29.97, forKey: "frameRate")
            let value = repo.double(forKey: "frameRate")
            #expect(value == 29.97)
        }

        @Test("Get non-existent double returns nil")
        func getNonExistentDouble() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.double(forKey: "missing") == nil)
        }
    }

    // MARK: - Bool

    @Suite("Bool Preferences")
    struct BoolTests {

        @Test("Set and get bool value")
        func setAndGetBool() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(true, forKey: "autoSave")
            let value = repo.bool(forKey: "autoSave")
            #expect(value == true)
        }

        @Test("Set and get false bool value")
        func setAndGetFalse() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(false, forKey: "showWaveforms")
            let value = repo.bool(forKey: "showWaveforms")
            #expect(value == false)
        }

        @Test("Get non-existent bool returns nil")
        func getNonExistentBool() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.bool(forKey: "missing") == nil)
        }
    }

    // MARK: - Date

    @Suite("Date Preferences")
    struct DateTests {

        @Test("Set and get date value")
        func setAndGetDate() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            let now = Date()
            repo.set(now, forKey: "lastOpened")
            let value = repo.date(forKey: "lastOpened")

            // ISO 8601 loses sub-second precision; compare within 1 second.
            #expect(value != nil)
            if let value {
                #expect(abs(value.timeIntervalSince(now)) < 1.0)
            }
        }

        @Test("Get non-existent date returns nil")
        func getNonExistentDate() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.date(forKey: "missing") == nil)
        }
    }

    // MARK: - Generic Codable

    @Suite("Generic Codable")
    struct CodableTests {

        @Test("Set and get codable struct")
        func setAndGetCodable() throws {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            let settings = TestSettings(theme: "ocean", fontSize: 14, isDarkMode: true)
            try repo.set(settings, forKey: "settings")

            let loaded: TestSettings? = repo.get(key: "settings", type: TestSettings.self)
            #expect(loaded == settings)
        }

        @Test("Get non-existent codable returns nil")
        func getNonExistentCodable() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            let value: TestSettings? = repo.get(key: "missing", type: TestSettings.self)
            #expect(value == nil)
        }

        @Test("Set and get codable array")
        func setAndGetCodableArray() throws {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            let tags = ["edit", "color", "sound"]
            try repo.set(tags, forKey: "tags")

            let loaded: [String]? = repo.get(key: "tags", type: [String].self)
            #expect(loaded == tags)
        }
    }

    // MARK: - Remove

    @Suite("Remove")
    struct RemoveTests {

        @Test("Remove deletes value")
        func removeValue() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set("test", forKey: "key")
            #expect(repo.contains(key: "key"))

            repo.remove(key: "key")
            #expect(!repo.contains(key: "key"))
            #expect(repo.string(forKey: "key") == nil)
        }

        @Test("Remove non-existent key is no-op")
        func removeNonExistent() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            // Should not throw or crash.
            repo.remove(key: "nonexistent")
        }
    }

    // MARK: - Contains

    @Suite("Contains")
    struct ContainsTests {

        @Test("Contains returns true for set key")
        func containsTrue() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(100, forKey: "count")
            #expect(repo.contains(key: "count"))
        }

        @Test("Contains returns false for unset key")
        func containsFalse() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(!repo.contains(key: "missing"))
        }
    }

    // MARK: - Clear All

    @Suite("Clear All")
    struct ClearAllTests {

        @Test("Clear all removes all LiquidEditor preferences")
        func clearAll() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set("value1", forKey: "key1")
            repo.set(42, forKey: "key2")
            repo.set(true, forKey: "key3")

            repo.clearAll()

            #expect(!repo.contains(key: "key1"))
            #expect(!repo.contains(key: "key2"))
            #expect(!repo.contains(key: "key3"))
        }
    }

    // MARK: - Convenience Methods

    @Suite("Convenience Methods")
    struct ConvenienceTests {

        @Test("Default frame rate returns nil when not set")
        func defaultFrameRateNil() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.defaultFrameRate() == nil)
        }

        @Test("Auto-save defaults to true")
        func autoSaveDefaultTrue() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.isAutoSaveEnabled() == true)
        }

        @Test("Auto-save interval defaults to 2.0")
        func autoSaveIntervalDefault() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.autoSaveIntervalSeconds() == 2.0)
        }

        @Test("Last opened project ID returns nil when not set")
        func lastOpenedProjectNil() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.lastOpenedProjectId() == nil)
        }

        @Test("Max undo steps defaults to 50")
        func maxUndoStepsDefault() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            #expect(repo.maxUndoSteps() == 50)
        }

        @Test("Set and read frame rate via known key")
        func setReadFrameRate() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(60.0, forKey: PreferencesRepository.keyDefaultFrameRate)
            #expect(repo.defaultFrameRate() == 60.0)
        }

        @Test("Set and read auto-save enabled")
        func setReadAutoSave() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(false, forKey: PreferencesRepository.keyAutoSaveEnabled)
            #expect(repo.isAutoSaveEnabled() == false)
        }
    }

    // MARK: - Overwrite

    @Suite("Overwrite")
    struct OverwriteTests {

        @Test("Overwrite string value")
        func overwriteString() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set("low", forKey: "quality")
            repo.set("high", forKey: "quality")
            #expect(repo.string(forKey: "quality") == "high")
        }

        @Test("Overwrite int value")
        func overwriteInt() {
            let suite = makeUniqueSuite()
            defer { removeSuite(suite) }
            let repo = PreferencesRepository(suiteName: suite)

            repo.set(10, forKey: "count")
            repo.set(20, forKey: "count")
            #expect(repo.int(forKey: "count") == 20)
        }
    }
}
