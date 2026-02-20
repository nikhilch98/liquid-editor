// SettingsViewModel.swift
// LiquidEditor
//
// ViewModel for the Settings screen.
// Manages app-wide preferences including editor behavior, performance,
// and display options. Persists settings via PreferencesRepositoryProtocol.
//
// Uses @Observable macro (iOS 17+) with @MainActor isolation
// for safe UI-bound state management.

import Foundation
import Observation
import os

// MARK: - SettingsSection

/// Logical grouping of settings for display in the settings UI.
enum SettingsSection: String, CaseIterable, Sendable, Identifiable {
    case general = "General"
    case editor = "Editor"
    case performance = "Performance"
    case about = "About"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .editor: return "slider.horizontal.3"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Preference Keys

/// Centralized preference key constants for the settings view model.
private enum SettingsKey {
    static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
    static let snapToGridEnabled = "snapToGridEnabled"
    static let gridVisible = "gridVisible"
    static let autoSaveEnabled = "autoSaveEnabled"
    static let autoSaveInterval = "autoSaveInterval"
    static let maxCacheSizeMB = "maxCacheSizeMB"
    static let timelineZoomSensitivity = "timelineZoomSensitivity"
    static let defaultFrameRate = "defaultFrameRate"
    static let defaultResolution = "defaultResolution"
    static let hasSeenOnboarding = "hasSeenOnboarding"
    static let appearanceMode = "appearanceMode"
    static let fontSizeOption = "fontSizeOption"
    static let selectedGridType = "selectedGridType"
    static let pinchSensitivity = "pinchSensitivity"
    static let swipeThreshold = "swipeThreshold"
    static let longPressDurationMs = "longPressDurationMs"
}

// MARK: - SettingsViewModel

/// ViewModel for the app settings screen.
///
/// Loads and persists user preferences through `PreferencesRepositoryProtocol`.
/// All properties are observable for automatic SwiftUI updates.
///
/// ## Usage
/// ```swift
/// let vm = SettingsViewModel(preferencesRepository: container.preferencesRepository)
/// vm.loadSettings()
/// ```
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "SettingsViewModel"
    )

    // MARK: - Default Configuration

    /// Default values for settings.
    private static let defaultHapticFeedbackEnabled = true
    private static let defaultSnapToGridEnabled = true
    private static let defaultGridVisible = false
    private static let defaultAppearanceMode = "System"
    private static let defaultFontSizeOption = "Default"
    private static let defaultAutoSaveEnabled = true
    private static let defaultAutoSaveInterval = 30
    private static let defaultSelectedGridType = "Rule of Thirds"
    private static let defaultTimelineZoomSensitivity = 1.0
    private static let defaultFrameRate = 30
    private static let defaultResolution = "1080p"
    private static let defaultMaxCacheSizeMB = 300
    private static let defaultPinchSensitivity = 1.0
    private static let defaultSwipeThreshold = 1.0
    private static let defaultLongPressDurationMs = 500.0

    /// Available auto-save interval options (in seconds).
    static let autoSaveIntervalOptions = [15, 30, 60, 120]

    /// Available frame rate options.
    static let frameRateOptions = [24, 30, 60]

    /// Available resolution options.
    static let resolutionOptions = ["720p", "1080p", "4K"]

    // MARK: - General Settings

    /// Whether haptic feedback is enabled for UI interactions.
    var hapticFeedbackEnabled: Bool = true {
        didSet { saveSettings() }
    }

    /// Whether snap-to-grid is enabled in the timeline.
    var snapToGridEnabled: Bool = true {
        didSet { saveSettings() }
    }

    /// Whether the grid overlay is visible in the editor.
    var gridVisible: Bool = false {
        didSet { saveSettings() }
    }

    /// Appearance mode (system, dark, light).
    var appearanceMode: String = "System" {
        didSet { saveSettings() }
    }

    /// Font size option (Small, Default, Large).
    var fontSizeOption: String = "Default" {
        didSet { saveSettings() }
    }

    /// Whether auto-save is enabled.
    var autoSaveEnabled: Bool = true {
        didSet { saveSettings() }
    }

    /// Auto-save interval in seconds.
    var autoSaveInterval: Int = 30 {
        didSet { saveSettings() }
    }

    // MARK: - Editor Settings

    /// Selected grid type for the editor overlay.
    var selectedGridType: String = "Rule of Thirds" {
        didSet { saveSettings() }
    }

    /// Timeline zoom gesture sensitivity multiplier.
    var timelineZoomSensitivity: Double = 1.0 {
        didSet { saveSettings() }
    }

    /// Default frame rate for new projects.
    var defaultFrameRate: Int = 30 {
        didSet { saveSettings() }
    }

    /// Default resolution label for new projects (e.g. "1080p").
    var defaultResolution: String = "1080p" {
        didSet { saveSettings() }
    }

    // MARK: - Performance Settings

    /// Maximum cache size in megabytes.
    var maxCacheSizeMB: Int = 300 {
        didSet { saveSettings() }
    }

    // MARK: - Gesture Settings

    /// Pinch zoom sensitivity (0.5 - 2.0).
    var pinchSensitivity: Double = 1.0 {
        didSet { saveSettings() }
    }

    /// Swipe threshold (0.5 - 2.0).
    var swipeThreshold: Double = 1.0 {
        didSet { saveSettings() }
    }

    /// Long press duration in milliseconds (300 - 1000).
    var longPressDurationMs: Double = 500 {
        didSet { saveSettings() }
    }

    // MARK: - Onboarding

    /// Whether the onboarding flow should be shown.
    var showOnboarding: Bool = true

    // MARK: - Read-Only State

    /// Whether a cache clearing operation is in progress.
    private(set) var isClearingCache: Bool = false

    // MARK: - Dependencies

    /// Preferences persistence layer.
    private let preferencesRepository: any PreferencesRepositoryProtocol

    /// Flag to suppress saves during initial load.
    private var isLoading: Bool = false

    // MARK: - Initialization

    /// Creates a settings view model with the given preferences repository.
    ///
    /// - Parameter preferencesRepository: The repository for reading/writing preferences.
    init(preferencesRepository: any PreferencesRepositoryProtocol) {
        self.preferencesRepository = preferencesRepository
    }

    // MARK: - Computed Properties

    /// Formatted cache usage string for display.
    var cacheUsageFormatted: String {
        let usage = currentCacheUsageMB
        if usage >= 1024 {
            let gb = Double(usage) / 1024.0
            return String(format: "%.1f GB", gb)
        }
        return "\(usage) MB"
    }

    /// Current app version from the main bundle.
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Current build number from the main bundle.
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Available auto-save interval options in seconds.
    var autoSaveIntervalOptions: [Int] {
        Self.autoSaveIntervalOptions
    }

    /// Available frame rate options.
    var frameRateOptions: [Int] {
        Self.frameRateOptions
    }

    /// Available resolution options.
    var resolutionOptions: [String] {
        Self.resolutionOptions
    }

    // MARK: - Cache Estimation

    /// Estimated current cache usage in megabytes.
    ///
    /// Calculates the size of the app's Caches directory.
    private var currentCacheUsageMB: Int {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cacheURL else { return 0 }

        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: cacheURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory,
                  let fileSize = resourceValues.fileSize else { continue }
            totalSize += Int64(fileSize)
        }

        return Int(totalSize / (1024 * 1024))
    }

    // MARK: - Load Settings

    /// Load all settings from the preferences repository.
    ///
    /// Reads each preference key and applies the stored value,
    /// falling back to defaults for missing keys.
    func loadSettings() {
        isLoading = true
        defer { isLoading = false }

        hapticFeedbackEnabled = preferencesRepository.bool(forKey: SettingsKey.hapticFeedbackEnabled) ?? Self.defaultHapticFeedbackEnabled
        snapToGridEnabled = preferencesRepository.bool(forKey: SettingsKey.snapToGridEnabled) ?? Self.defaultSnapToGridEnabled
        gridVisible = preferencesRepository.bool(forKey: SettingsKey.gridVisible) ?? Self.defaultGridVisible
        autoSaveEnabled = preferencesRepository.bool(forKey: SettingsKey.autoSaveEnabled) ?? Self.defaultAutoSaveEnabled
        autoSaveInterval = preferencesRepository.int(forKey: SettingsKey.autoSaveInterval) ?? Self.defaultAutoSaveInterval
        maxCacheSizeMB = preferencesRepository.int(forKey: SettingsKey.maxCacheSizeMB) ?? Self.defaultMaxCacheSizeMB
        timelineZoomSensitivity = preferencesRepository.double(forKey: SettingsKey.timelineZoomSensitivity) ?? Self.defaultTimelineZoomSensitivity
        defaultFrameRate = preferencesRepository.int(forKey: SettingsKey.defaultFrameRate) ?? Self.defaultFrameRate
        defaultResolution = preferencesRepository.string(forKey: SettingsKey.defaultResolution) ?? Self.defaultResolution
        showOnboarding = !(preferencesRepository.bool(forKey: SettingsKey.hasSeenOnboarding) ?? false)
        appearanceMode = preferencesRepository.string(forKey: SettingsKey.appearanceMode) ?? Self.defaultAppearanceMode
        fontSizeOption = preferencesRepository.string(forKey: SettingsKey.fontSizeOption) ?? Self.defaultFontSizeOption
        selectedGridType = preferencesRepository.string(forKey: SettingsKey.selectedGridType) ?? Self.defaultSelectedGridType
        pinchSensitivity = preferencesRepository.double(forKey: SettingsKey.pinchSensitivity) ?? Self.defaultPinchSensitivity
        swipeThreshold = preferencesRepository.double(forKey: SettingsKey.swipeThreshold) ?? Self.defaultSwipeThreshold
        longPressDurationMs = preferencesRepository.double(forKey: SettingsKey.longPressDurationMs) ?? Self.defaultLongPressDurationMs

        Self.logger.debug("Settings loaded")
    }

    // MARK: - Save Settings

    /// Persist all current settings to the preferences repository.
    ///
    /// Called automatically when any setting property changes via `didSet`.
    /// Skipped during initial load to avoid unnecessary writes.
    func saveSettings() {
        guard !isLoading else { return }

        do {
            try preferencesRepository.set(hapticFeedbackEnabled, forKey: SettingsKey.hapticFeedbackEnabled)
            try preferencesRepository.set(snapToGridEnabled, forKey: SettingsKey.snapToGridEnabled)
            try preferencesRepository.set(gridVisible, forKey: SettingsKey.gridVisible)
            try preferencesRepository.set(autoSaveEnabled, forKey: SettingsKey.autoSaveEnabled)
            try preferencesRepository.set(autoSaveInterval, forKey: SettingsKey.autoSaveInterval)
            try preferencesRepository.set(maxCacheSizeMB, forKey: SettingsKey.maxCacheSizeMB)
            try preferencesRepository.set(timelineZoomSensitivity, forKey: SettingsKey.timelineZoomSensitivity)
            try preferencesRepository.set(defaultFrameRate, forKey: SettingsKey.defaultFrameRate)
            try preferencesRepository.set(defaultResolution, forKey: SettingsKey.defaultResolution)
            try preferencesRepository.set(appearanceMode, forKey: SettingsKey.appearanceMode)
            try preferencesRepository.set(fontSizeOption, forKey: SettingsKey.fontSizeOption)
            try preferencesRepository.set(selectedGridType, forKey: SettingsKey.selectedGridType)
            try preferencesRepository.set(pinchSensitivity, forKey: SettingsKey.pinchSensitivity)
            try preferencesRepository.set(swipeThreshold, forKey: SettingsKey.swipeThreshold)
            try preferencesRepository.set(longPressDurationMs, forKey: SettingsKey.longPressDurationMs)
        } catch {
            Self.logger.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Reset to Defaults

    /// Reset all settings to their default values.
    ///
    /// Clears stored preferences and reloads defaults.
    func resetToDefaults() {
        isLoading = true
        defer {
            isLoading = false
            saveSettings()
        }

        hapticFeedbackEnabled = Self.defaultHapticFeedbackEnabled
        snapToGridEnabled = Self.defaultSnapToGridEnabled
        gridVisible = Self.defaultGridVisible
        autoSaveEnabled = Self.defaultAutoSaveEnabled
        autoSaveInterval = Self.defaultAutoSaveInterval
        maxCacheSizeMB = Self.defaultMaxCacheSizeMB
        timelineZoomSensitivity = Self.defaultTimelineZoomSensitivity
        defaultFrameRate = Self.defaultFrameRate
        defaultResolution = Self.defaultResolution
        appearanceMode = Self.defaultAppearanceMode
        fontSizeOption = Self.defaultFontSizeOption
        selectedGridType = Self.defaultSelectedGridType
        pinchSensitivity = Self.defaultPinchSensitivity
        swipeThreshold = Self.defaultSwipeThreshold
        longPressDurationMs = 500

        Self.logger.info("Settings reset to defaults")
    }

    // MARK: - Cache Management

    /// Clear the app's cache directory.
    ///
    /// Removes all files from the Caches directory asynchronously.
    func clearCache() async {
        isClearingCache = true
        defer { isClearingCache = false }

        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cacheURL else {
            Self.logger.warning("Cache directory not found")
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for fileURL in contents {
                try FileManager.default.removeItem(at: fileURL)
            }

            Self.logger.info("Cache cleared successfully")
        } catch {
            Self.logger.error("Failed to clear cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Onboarding

    /// Mark onboarding as completed.
    ///
    /// Sets the `hasSeenOnboarding` preference and hides the onboarding flow.
    func completeOnboarding() {
        showOnboarding = false
        do {
            try preferencesRepository.set(true, forKey: SettingsKey.hasSeenOnboarding)
        } catch {
            Self.logger.error("Failed to save onboarding state: \(error.localizedDescription)")
        }
    }

    /// Check whether onboarding should be shown.
    ///
    /// - Returns: `true` if the user has not yet completed onboarding.
    func shouldShowOnboarding() -> Bool {
        !(preferencesRepository.bool(forKey: SettingsKey.hasSeenOnboarding) ?? false)
    }
}
