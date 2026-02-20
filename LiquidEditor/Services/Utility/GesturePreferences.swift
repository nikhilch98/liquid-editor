// GesturePreferences.swift
// LiquidEditor
//
// User gesture sensitivity settings for the editor. Allows
// customization of pinch zoom sensitivity, swipe thresholds,
// and long press duration. Persists via PreferencesRepository.

import Foundation

// MARK: - Preference Keys

private enum GesturePreferenceKeys {
    static let pinchZoomSensitivity = "gesture.pinchZoomSensitivity"
    static let swipeThreshold = "gesture.swipeThreshold"
    static let longPressDurationMs = "gesture.longPressDurationMs"
}

// MARK: - GesturePreferences

/// Manages gesture sensitivity settings for the editor.
///
/// All values are multipliers or durations that can be adjusted
/// through the settings screen and persisted via ``PreferencesRepository``.
@Observable
@MainActor
final class GesturePreferences {

    // MARK: - Singleton

    static let shared = GesturePreferences()

    // MARK: - Clamping Ranges

    /// Minimum and maximum for pinch zoom sensitivity.
    nonisolated static let pinchZoomRange: ClosedRange<Double> = 0.5...2.0

    /// Minimum and maximum for swipe threshold multiplier.
    nonisolated static let swipeThresholdRange: ClosedRange<Double> = 0.5...2.0

    /// Minimum and maximum for long press duration in milliseconds.
    nonisolated static let longPressDurationMsRange: ClosedRange<Int> = 300...1000

    // MARK: - State

    /// Pinch zoom sensitivity multiplier (0.5 = less sensitive, 2.0 = more sensitive).
    private(set) var pinchZoomSensitivity: Double

    /// Swipe threshold multiplier (0.5 = easier to trigger, 2.0 = harder).
    private(set) var swipeThreshold: Double

    /// Long press duration in milliseconds (300-1000).
    private(set) var longPressDurationMs: Int

    /// Preferences repository for persistence.
    private let preferences: PreferencesRepository

    // MARK: - Initialization

    init(preferences: PreferencesRepository = PreferencesRepository()) {
        self.preferences = preferences
        self.pinchZoomSensitivity = preferences.double(
            forKey: GesturePreferenceKeys.pinchZoomSensitivity
        ) ?? 1.0
        self.swipeThreshold = preferences.double(
            forKey: GesturePreferenceKeys.swipeThreshold
        ) ?? 1.0
        self.longPressDurationMs = preferences.int(
            forKey: GesturePreferenceKeys.longPressDurationMs
        ) ?? 500
    }

    // MARK: - Setters

    /// Set pinch zoom sensitivity (clamped to 0.5 - 2.0).
    func setPinchZoomSensitivity(_ value: Double) {
        let clamped = min(max(value, Self.pinchZoomRange.lowerBound), Self.pinchZoomRange.upperBound)
        pinchZoomSensitivity = clamped
        preferences.set(clamped, forKey: GesturePreferenceKeys.pinchZoomSensitivity)
    }

    /// Set swipe threshold multiplier (clamped to 0.5 - 2.0).
    func setSwipeThreshold(_ value: Double) {
        let clamped = min(max(value, Self.swipeThresholdRange.lowerBound), Self.swipeThresholdRange.upperBound)
        swipeThreshold = clamped
        preferences.set(clamped, forKey: GesturePreferenceKeys.swipeThreshold)
    }

    /// Set long press duration in milliseconds (clamped to 300 - 1000).
    func setLongPressDurationMs(_ value: Int) {
        let clamped = min(max(value, Self.longPressDurationMsRange.lowerBound), Self.longPressDurationMsRange.upperBound)
        longPressDurationMs = clamped
        preferences.set(clamped, forKey: GesturePreferenceKeys.longPressDurationMs)
    }

    // MARK: - Computed Properties

    /// The configured long press duration as a `TimeInterval` (seconds).
    var longPressDuration: TimeInterval {
        Double(longPressDurationMs) / 1000.0
    }

    // MARK: - Application Helpers

    /// Apply pinch zoom sensitivity to a raw scale delta.
    ///
    /// - Parameter rawDelta: The raw pinch gesture delta.
    /// - Returns: The delta multiplied by the sensitivity setting.
    func applyPinchSensitivity(_ rawDelta: Double) -> Double {
        rawDelta * pinchZoomSensitivity
    }

    /// Check if a velocity exceeds the configured swipe threshold.
    ///
    /// - Parameters:
    ///   - velocityPxPerSec: The gesture velocity in points/second.
    ///   - baseThreshold: The base threshold before multiplier (default 500).
    /// - Returns: `true` if the swipe should be triggered.
    func isSwipeTriggered(velocityPxPerSec: Double, baseThreshold: Double = 500) -> Bool {
        abs(velocityPxPerSec) > (baseThreshold * swipeThreshold)
    }
}
