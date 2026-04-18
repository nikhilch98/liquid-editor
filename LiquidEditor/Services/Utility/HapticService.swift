// HapticService.swift
// LiquidEditor
//
// Context-aware haptic feedback patterns for the editor.
// Respects user preference to disable haptics globally via
// PreferencesRepository. Maps editor-specific actions to
// UIKit haptic feedback generators.

import UIKit

// MARK: - EditorHapticType

/// Types of editor-specific haptic feedback patterns.
enum EditorHapticType: String, CaseIterable, Sendable {
    /// Light impact for timeline scrubbing feedback.
    case timelineScrub

    /// Medium impact when a clip snaps to a guide.
    case clipSnap

    /// Heavy impact for split/delete operations.
    case splitDelete

    /// Selection click for tab changes and selections.
    case selection

    /// Medium impact for play/pause toggle.
    case playPause

    /// Light impact for navigation transitions.
    case navigation

    /// Heavy impact for destructive actions.
    case destructive

    /// Light impact for keyframe operations.
    case keyframeAdd

    /// Medium impact for export completion.
    case exportComplete
}

// MARK: - HapticService

/// Centralized haptic feedback manager.
///
/// All haptic feedback in the app routes through this service to
/// respect the user's haptics preference and provide consistent
/// feedback patterns across the editor.
///
/// Uses `@Observable` to allow SwiftUI views to react to the
/// `isEnabled` state. Reads and writes the preference via
/// ``PreferencesRepository``.
@Observable
@MainActor
final class HapticService {

    // MARK: - Preference Keys

    static let hapticsEnabledKey = "hapticsEnabled"

    // MARK: - Singleton

    static let shared = HapticService()

    // MARK: - State

    /// Whether haptic feedback is currently enabled.
    /// Defaults to `true` when no preference is stored.
    private(set) var isEnabled: Bool

    /// Preferences repository for persistence.
    private let preferences: PreferencesRepository

    // MARK: - Generators (eagerly initialized, reusable)

    // Note: Cannot use `lazy` with @Observable (macro transforms stored
    // properties into computed properties). Generators are cheap to create.
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    // MARK: - Initialization

    init(preferences: PreferencesRepository = PreferencesRepository()) {
        self.preferences = preferences
        self.isEnabled = preferences.bool(forKey: HapticService.hapticsEnabledKey) ?? true
    }

    // MARK: - Enable / Disable

    /// Enable or disable haptic feedback globally.
    ///
    /// Persists the preference to ``PreferencesRepository``.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        preferences.set(enabled, forKey: HapticService.hapticsEnabledKey)
    }

    // MARK: - Premium-UI play(_:) + throttle

    /// Minimum interval between two plays of the same `HapticKind`.
    /// Lower than this gets swallowed to prevent scrub-drag spam.
    private static let throttleInterval: TimeInterval = 0.040

    /// Last-fire timestamp per kind. Cleared by `resetThrottleForTesting()`.
    private var lastFireDates: [HapticKind: Date] = [:]

    /// Play a premium-UI haptic. Does nothing if `isEnabled` is false or
    /// if the same kind fired within the throttle window.
    func play(_ kind: HapticKind) {
        _ = playForTesting(kind)
    }

    /// Test-visible variant of ``play(_:)``. Returns whether the feedback
    /// actually fired (true) or was suppressed by the throttle / disabled
    /// state (false). Not part of the production API — only meant for
    /// unit tests.
    @discardableResult
    func playForTesting(_ kind: HapticKind) -> Bool {
        guard isEnabled else { return false }

        let now = Date()
        if let last = lastFireDates[kind],
           now.timeIntervalSince(last) < Self.throttleInterval {
            return false
        }
        lastFireDates[kind] = now

        switch kind.feedbackStyle {
        case .lightImpact:
            lightImpactGenerator.impactOccurred()
        case .mediumImpact:
            mediumImpactGenerator.impactOccurred()
        case .heavyImpact:
            heavyImpactGenerator.impactOccurred()
        case .selection:
            selectionGenerator.selectionChanged()
        case .notification:
            if let t = kind.notificationType {
                notificationGenerator.notificationOccurred(t)
            }
        }
        return true
    }

    /// Reset the throttle window. Test-only helper.
    func resetThrottleForTesting() {
        lastFireDates.removeAll()
    }

    // MARK: - Trigger

    /// Trigger a haptic feedback event of the specified type.
    ///
    /// Does nothing if haptics are disabled.
    ///
    /// - Parameter type: The editor haptic pattern to trigger.
    func trigger(_ type: EditorHapticType) {
        guard isEnabled else { return }

        switch type {
        case .timelineScrub:
            lightImpactGenerator.impactOccurred()
        case .clipSnap:
            mediumImpactGenerator.impactOccurred()
        case .splitDelete:
            heavyImpactGenerator.impactOccurred()
        case .selection:
            selectionGenerator.selectionChanged()
        case .playPause:
            mediumImpactGenerator.impactOccurred()
        case .navigation:
            lightImpactGenerator.impactOccurred()
        case .destructive:
            heavyImpactGenerator.impactOccurred()
        case .keyframeAdd:
            lightImpactGenerator.impactOccurred()
        case .exportComplete:
            notificationGenerator.notificationOccurred(.success)
        }
    }

    // MARK: - Convenience

    /// Light impact feedback. Does nothing if haptics are disabled.
    func lightImpact() {
        guard isEnabled else { return }
        lightImpactGenerator.impactOccurred()
    }

    /// Medium impact feedback. Does nothing if haptics are disabled.
    func mediumImpact() {
        guard isEnabled else { return }
        mediumImpactGenerator.impactOccurred()
    }

    /// Heavy impact feedback. Does nothing if haptics are disabled.
    func heavyImpact() {
        guard isEnabled else { return }
        heavyImpactGenerator.impactOccurred()
    }

    /// Selection click feedback. Does nothing if haptics are disabled.
    func selectionClick() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    /// Prepare generators for imminent use (reduces latency).
    func prepare() {
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    // MARK: - Feedback Style Mapping (Testable)

    /// Returns the UIKit feedback style associated with a haptic type.
    ///
    /// Exposed for unit testing to verify correct mapping without
    /// requiring actual haptic hardware.
    nonisolated static func feedbackStyle(for type: EditorHapticType) -> HapticFeedbackStyle {
        switch type {
        case .timelineScrub:  .lightImpact
        case .clipSnap:       .mediumImpact
        case .splitDelete:    .heavyImpact
        case .selection:      .selection
        case .playPause:      .mediumImpact
        case .navigation:     .lightImpact
        case .destructive:    .heavyImpact
        case .keyframeAdd:    .lightImpact
        case .exportComplete: .notification
        }
    }
}

// MARK: - HapticFeedbackStyle

/// Categorized feedback style for haptic type mapping.
enum HapticFeedbackStyle: String, Sendable, CaseIterable {
    case lightImpact
    case mediumImpact
    case heavyImpact
    case selection
    case notification
}

// MARK: - HapticKind (2026-04-18 premium UI redesign)

/// Premium-UI haptic vocabulary added for the 2026-04-18 redesign.
/// Consumers use this via `HapticService.shared.play(.<kind>)`.
/// The legacy `EditorHapticType` remains for views not yet on the new
/// design system.
enum HapticKind: String, CaseIterable, Sendable {
    case tapPrimary
    case tapSecondary
    case selection
    case pickup
    case drop
    case boundary
    case success
    case warning
    case error

    /// The UIKit feedback style each kind resolves to.
    var feedbackStyle: HapticFeedbackStyle {
        switch self {
        case .tapPrimary:   .mediumImpact
        case .tapSecondary: .lightImpact
        case .selection:    .selection
        case .pickup:       .mediumImpact
        case .drop:         .lightImpact
        case .boundary:     .heavyImpact
        case .success:      .notification
        case .warning:      .notification
        case .error:        .notification
        }
    }

    /// Notification generator sub-style (only meaningful for notification kinds).
    var notificationType: UINotificationFeedbackGenerator.FeedbackType? {
        switch self {
        case .success: .success
        case .warning: .warning
        case .error:   .error
        default: nil
        }
    }
}
