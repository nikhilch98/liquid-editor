// AppReviewPrompter.swift
// LiquidEditor
//
// Tracks successful exports and presents the App Store review prompt
// via `SKStoreReviewController.requestReview(in:)` when all of the
// following conditions are met:
//
//   1. The user has completed at least `minSuccessfulExports` successful
//      exports (default: 3).
//   2. At least `minDaysSinceInstall` days have elapsed since first
//      launch (default: 7).
//   3. The last prompt (if any) happened more than `minDaysBetweenPrompts`
//      days ago (default: 90).
//
// These thresholds intentionally err on the side of under-prompting.
// Users who have a good, sustained experience are more likely to leave
// positive reviews than users interrupted mid-task.

import Foundation
import Observation
import StoreKit
import SwiftUI
import UIKit
import os

// MARK: - AppReviewPrompter

/// Coordinates App Store review prompts based on product usage signals.
///
/// Thread Safety:
/// - `@MainActor` — `SKStoreReviewController.requestReview(in:)` requires
///   the main actor, and all usage counters are written/read from UI
///   flows that already run on the main actor.
/// - `@Observable` so the editor/export view can reactively bind to
///   `successfulExportCount` if desired.
@MainActor
@Observable
final class AppReviewPrompter {

    // MARK: - UserDefaults Keys

    @ObservationIgnored
    private static let keySuccessfulExportCount = "AppReviewPrompter.successfulExportCount"

    @ObservationIgnored
    private static let keyInstallDate = "AppReviewPrompter.installDate"

    @ObservationIgnored
    private static let keyLastPromptDate = "AppReviewPrompter.lastPromptDate"

    // MARK: - Trigger Thresholds

    /// Minimum number of successful exports before eligibility.
    @ObservationIgnored
    static let minSuccessfulExports = 3

    /// Minimum days between app install and first prompt.
    @ObservationIgnored
    static let minDaysSinceInstall = 7

    /// Minimum days between consecutive prompts (Apple also rate-limits
    /// to ~3 per year, but we additionally enforce our own quiet period).
    @ObservationIgnored
    static let minDaysBetweenPrompts = 90

    // MARK: - Logger

    @ObservationIgnored
    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "AppReviewPrompter"
    )

    // MARK: - Dependencies

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let now: @MainActor () -> Date

    // MARK: - Observable State

    /// Number of successful exports the user has completed.
    var successfulExportCount: Int

    // MARK: - Init

    /// - Parameters:
    ///   - defaults: `UserDefaults` instance (inject for tests).
    ///   - now: Clock source (inject for tests).
    init(
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.now = now
        self.successfulExportCount = defaults.integer(forKey: Self.keySuccessfulExportCount)

        // Stamp install date on first run.
        if defaults.object(forKey: Self.keyInstallDate) == nil {
            defaults.set(now(), forKey: Self.keyInstallDate)
        }
    }

    // MARK: - Public API

    /// Record a successful export and, if trigger conditions are met,
    /// present the App Store review prompt.
    ///
    /// This is the single entry point. Call from the export completion
    /// handler when the exported file has been written successfully.
    func recordSuccessfulExport() {
        successfulExportCount += 1
        defaults.set(successfulExportCount, forKey: Self.keySuccessfulExportCount)
        Self.logger.info("Recorded successful export, total=\(self.successfulExportCount, privacy: .public)")

        if shouldRequestReview() {
            requestReviewIfPossible()
        }
    }

    // MARK: - Trigger Evaluation

    /// Evaluate whether a review prompt should be shown given the
    /// current counters and timestamps.
    ///
    /// Exposed internally for tests.
    func shouldRequestReview() -> Bool {
        guard successfulExportCount >= Self.minSuccessfulExports else {
            return false
        }

        let currentDate = now()

        // Days since install.
        if let installDate = defaults.object(forKey: Self.keyInstallDate) as? Date {
            let days = Self.daysBetween(installDate, currentDate)
            guard days >= Self.minDaysSinceInstall else {
                return false
            }
        } else {
            // No install date recorded — be conservative, don't prompt.
            return false
        }

        // Quiet period since last prompt.
        if let lastPrompt = defaults.object(forKey: Self.keyLastPromptDate) as? Date {
            let days = Self.daysBetween(lastPrompt, currentDate)
            guard days >= Self.minDaysBetweenPrompts else {
                return false
            }
        }

        return true
    }

    /// Ask StoreKit to present the review prompt in the active window
    /// scene. iOS ultimately decides whether to display it.
    private func requestReviewIfPossible() {
        guard let scene = Self.activeWindowScene() else {
            Self.logger.error("No active window scene; cannot request review")
            return
        }
        defaults.set(now(), forKey: Self.keyLastPromptDate)
        Self.logger.info("Requesting App Store review")
        AppStore.requestReview(in: scene)
    }

    // MARK: - Helpers

    /// Number of whole days between two dates (rounded down to 0 if
    /// negative).
    private static func daysBetween(_ start: Date, _ end: Date) -> Int {
        let interval = end.timeIntervalSince(start)
        guard interval > 0 else { return 0 }
        return Int(interval / 86_400)
    }

    /// Find the currently foreground-active `UIWindowScene`, if any.
    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    // MARK: - Testing Hooks

    /// Reset all tracked state. Test-only.
    func resetForTesting() {
        defaults.removeObject(forKey: Self.keySuccessfulExportCount)
        defaults.removeObject(forKey: Self.keyInstallDate)
        defaults.removeObject(forKey: Self.keyLastPromptDate)
        successfulExportCount = 0
    }
}
