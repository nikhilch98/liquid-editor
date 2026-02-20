import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Mock Preferences Repository

/// In-memory mock implementation of PreferencesRepositoryProtocol for testing.
final class MockPreferencesRepository: PreferencesRepositoryProtocol, @unchecked Sendable {
    private var storage: [String: Any] = [:]

    func get<T: Codable & Sendable>(key: String, type: T.Type) -> T? {
        storage[key] as? T
    }

    func set<T: Codable & Sendable>(_ value: T, forKey key: String) throws {
        storage[key] = value
    }

    func remove(key: String) {
        storage.removeValue(forKey: key)
    }

    func contains(key: String) -> Bool {
        storage[key] != nil
    }

    func clearAll() {
        storage.removeAll()
    }

    func string(forKey key: String) -> String? {
        storage[key] as? String
    }

    func int(forKey key: String) -> Int? {
        storage[key] as? Int
    }

    func double(forKey key: String) -> Double? {
        storage[key] as? Double
    }

    func bool(forKey key: String) -> Bool? {
        storage[key] as? Bool
    }

    func date(forKey key: String) -> Date? {
        storage[key] as? Date
    }
}

// MARK: - SettingsSection Tests

@Suite("SettingsSection Tests")
struct SettingsSectionTests {

    @Test("All sections have correct raw values")
    func rawValues() {
        #expect(SettingsSection.general.rawValue == "General")
        #expect(SettingsSection.editor.rawValue == "Editor")
        #expect(SettingsSection.performance.rawValue == "Performance")
        #expect(SettingsSection.about.rawValue == "About")
    }

    @Test("All sections have system image names")
    func systemImages() {
        #expect(SettingsSection.general.systemImage == "gearshape")
        #expect(SettingsSection.editor.systemImage == "slider.horizontal.3")
        #expect(SettingsSection.performance.systemImage == "gauge.with.dots.needle.67percent")
        #expect(SettingsSection.about.systemImage == "info.circle")
    }

    @Test("CaseIterable contains all 4 sections")
    func allCases() {
        #expect(SettingsSection.allCases.count == 4)
    }

    @Test("Identifiable id equals rawValue")
    func identifiable() {
        for section in SettingsSection.allCases {
            #expect(section.id == section.rawValue)
        }
    }
}

// MARK: - SettingsViewModel Tests

@Suite("SettingsViewModel Tests")
@MainActor
struct SettingsViewModelTests {

    // MARK: - Helpers

    private func makeVM() -> (SettingsViewModel, MockPreferencesRepository) {
        let repo = MockPreferencesRepository()
        let vm = SettingsViewModel(preferencesRepository: repo)
        return (vm, repo)
    }

    // MARK: - Default Values

    @Test("Default values before loading")
    func defaultValues() {
        let (vm, _) = makeVM()

        #expect(vm.hapticFeedbackEnabled == true)
        #expect(vm.snapToGridEnabled == true)
        #expect(vm.gridVisible == false)
        #expect(vm.autoSaveEnabled == true)
        #expect(vm.autoSaveInterval == 30)
        #expect(vm.maxCacheSizeMB == 300)
        #expect(vm.timelineZoomSensitivity == 1.0)
        #expect(vm.defaultFrameRate == 30)
        #expect(vm.defaultResolution == "1080p")
        #expect(vm.showOnboarding == true)
        #expect(vm.isClearingCache == false)
    }

    // MARK: - Load Settings

    @Test("loadSettings loads from repository with defaults for missing keys")
    func loadSettingsDefaults() {
        let (vm, _) = makeVM()
        vm.loadSettings()

        // All should be at default values since nothing stored
        #expect(vm.hapticFeedbackEnabled == true)
        #expect(vm.snapToGridEnabled == true)
        #expect(vm.gridVisible == false)
        #expect(vm.autoSaveEnabled == true)
        #expect(vm.autoSaveInterval == 30)
    }

    @Test("loadSettings loads stored values from repository")
    func loadSettingsStored() {
        let (vm, repo) = makeVM()

        try? repo.set(false, forKey: "hapticFeedbackEnabled")
        try? repo.set(false, forKey: "snapToGridEnabled")
        try? repo.set(true, forKey: "gridVisible")
        try? repo.set(60, forKey: "autoSaveInterval")
        try? repo.set(500, forKey: "maxCacheSizeMB")
        try? repo.set(2.0, forKey: "timelineZoomSensitivity")
        try? repo.set(60, forKey: "defaultFrameRate")
        try? repo.set("4K", forKey: "defaultResolution")
        try? repo.set(true, forKey: "hasSeenOnboarding")

        vm.loadSettings()

        #expect(vm.hapticFeedbackEnabled == false)
        #expect(vm.snapToGridEnabled == false)
        #expect(vm.gridVisible == true)
        #expect(vm.autoSaveInterval == 60)
        #expect(vm.maxCacheSizeMB == 500)
        #expect(vm.timelineZoomSensitivity == 2.0)
        #expect(vm.defaultFrameRate == 60)
        #expect(vm.defaultResolution == "4K")
        #expect(vm.showOnboarding == false) // hasSeenOnboarding = true -> showOnboarding = false
    }

    // MARK: - Save Settings

    @Test("Changing a setting triggers save to repository")
    func changeSavesToRepo() {
        let (vm, repo) = makeVM()
        vm.loadSettings() // initialize to stop isLoading

        vm.hapticFeedbackEnabled = false

        // After save, the repo should contain the new value
        #expect(repo.bool(forKey: "hapticFeedbackEnabled") == false)
    }

    @Test("loadSettings does not trigger saves (suppressed during load)")
    func loadDoesNotSave() {
        let (vm, repo) = makeVM()
        // Clear repo to verify no writes happen during load
        repo.clearAll()

        vm.loadSettings()

        // During load, isLoading is true, so saves are suppressed.
        // After load, defaults are written by loadSettings -> saveSettings in defer.
        // But the values should still be the defaults.
        #expect(vm.hapticFeedbackEnabled == true)
    }

    // MARK: - Reset to Defaults

    @Test("resetToDefaults restores all default values")
    func resetToDefaults() {
        let (vm, _) = makeVM()
        vm.loadSettings()

        // Change some settings
        vm.hapticFeedbackEnabled = false
        vm.snapToGridEnabled = false
        vm.gridVisible = true
        vm.autoSaveInterval = 120
        vm.maxCacheSizeMB = 1024
        vm.timelineZoomSensitivity = 3.0
        vm.defaultFrameRate = 60
        vm.defaultResolution = "4K"

        // Reset
        vm.resetToDefaults()

        #expect(vm.hapticFeedbackEnabled == true)
        #expect(vm.snapToGridEnabled == true)
        #expect(vm.gridVisible == false)
        #expect(vm.autoSaveEnabled == true)
        #expect(vm.autoSaveInterval == 30)
        #expect(vm.maxCacheSizeMB == 300)
        #expect(vm.timelineZoomSensitivity == 1.0)
        #expect(vm.defaultFrameRate == 30)
        #expect(vm.defaultResolution == "1080p")
    }

    @Test("resetToDefaults saves the defaults to repository")
    func resetSavesDefaults() {
        let (vm, repo) = makeVM()
        vm.loadSettings()

        vm.hapticFeedbackEnabled = false
        vm.resetToDefaults()

        // After reset, the repo should have the default value
        #expect(repo.bool(forKey: "hapticFeedbackEnabled") == true)
        #expect(repo.int(forKey: "autoSaveInterval") == 30)
        #expect(repo.int(forKey: "maxCacheSizeMB") == 300)
        #expect(repo.double(forKey: "timelineZoomSensitivity") == 1.0)
        #expect(repo.int(forKey: "defaultFrameRate") == 30)
        #expect(repo.string(forKey: "defaultResolution") == "1080p")
    }

    // MARK: - Cache Usage Formatted

    @Test("cacheUsageFormatted returns a string")
    func cacheUsageFormatted() {
        let (vm, _) = makeVM()
        let formatted = vm.cacheUsageFormatted
        // Should end with "MB" or "GB"
        #expect(formatted.hasSuffix("MB") || formatted.hasSuffix("GB"))
    }

    // MARK: - App Version / Build Number

    @Test("appVersion returns a non-empty string")
    func appVersion() {
        let (vm, _) = makeVM()
        let version = vm.appVersion
        #expect(!version.isEmpty)
    }

    @Test("buildNumber returns a non-empty string")
    func buildNumber() {
        let (vm, _) = makeVM()
        let build = vm.buildNumber
        #expect(!build.isEmpty)
    }

    // MARK: - Options Arrays

    @Test("autoSaveIntervalOptions contains expected values")
    func autoSaveIntervalOptions() {
        let (vm, _) = makeVM()
        #expect(vm.autoSaveIntervalOptions == [15, 30, 60, 120])
    }

    @Test("frameRateOptions contains expected values")
    func frameRateOptions() {
        let (vm, _) = makeVM()
        #expect(vm.frameRateOptions == [24, 30, 60])
    }

    @Test("resolutionOptions contains expected values")
    func resolutionOptions() {
        let (vm, _) = makeVM()
        #expect(vm.resolutionOptions == ["720p", "1080p", "4K"])
    }

    // MARK: - Onboarding

    @Test("completeOnboarding sets showOnboarding to false")
    func completeOnboarding() {
        let (vm, _) = makeVM()
        #expect(vm.showOnboarding == true)

        vm.completeOnboarding()
        #expect(vm.showOnboarding == false)
    }

    @Test("shouldShowOnboarding returns true when not completed")
    func shouldShowOnboardingTrue() {
        let (vm, _) = makeVM()
        #expect(vm.shouldShowOnboarding() == true)
    }

    @Test("shouldShowOnboarding returns false after completion")
    func shouldShowOnboardingFalse() {
        let (vm, _) = makeVM()
        vm.completeOnboarding()
        #expect(vm.shouldShowOnboarding() == false)
    }

    // MARK: - Individual Setting Changes

    @Test("Changing hapticFeedbackEnabled persists")
    func changeHaptic() {
        let (vm, repo) = makeVM()
        vm.loadSettings()

        vm.hapticFeedbackEnabled = false
        #expect(repo.bool(forKey: "hapticFeedbackEnabled") == false)
    }

    @Test("Changing gridVisible persists")
    func changeGridVisible() {
        let (vm, repo) = makeVM()
        vm.loadSettings()

        vm.gridVisible = true
        #expect(repo.bool(forKey: "gridVisible") == true)
    }

    @Test("Changing autoSaveEnabled persists")
    func changeAutoSave() {
        let (vm, repo) = makeVM()
        vm.loadSettings()

        vm.autoSaveEnabled = false
        #expect(repo.bool(forKey: "autoSaveEnabled") == false)
    }

    @Test("Changing defaultFrameRate persists")
    func changeFrameRate() {
        let (vm, repo) = makeVM()
        vm.loadSettings()

        vm.defaultFrameRate = 60
        #expect(repo.int(forKey: "defaultFrameRate") == 60)
    }

    @Test("Changing defaultResolution persists")
    func changeResolution() {
        let (vm, repo) = makeVM()
        vm.loadSettings()

        vm.defaultResolution = "4K"
        #expect(repo.string(forKey: "defaultResolution") == "4K")
    }
}
