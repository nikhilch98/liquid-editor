import Testing
import Foundation
@testable import LiquidEditor

@Suite("HapticService Tests")
struct HapticServiceTests {

    // MARK: - EditorHapticType

    @Suite("EditorHapticType")
    struct HapticTypeTests {

        @Test("allCases contains 10 haptic types")
        func allCasesCount() {
            #expect(EditorHapticType.allCases.count == 10)
        }

        @Test("Each haptic type has a unique rawValue")
        func uniqueRawValues() {
            let rawValues = Set(EditorHapticType.allCases.map(\.rawValue))
            #expect(rawValues.count == EditorHapticType.allCases.count)
        }
    }

    // MARK: - Feedback Style Mapping

    @Suite("Feedback Style Mapping")
    struct FeedbackStyleTests {

        @Test("timelineScrub maps to lightImpact")
        func timelineScrub() {
            #expect(HapticService.feedbackStyle(for: .timelineScrub) == .lightImpact)
        }

        @Test("clipSnap maps to mediumImpact")
        func clipSnap() {
            #expect(HapticService.feedbackStyle(for: .clipSnap) == .mediumImpact)
        }

        @Test("splitDelete maps to heavyImpact")
        func splitDelete() {
            #expect(HapticService.feedbackStyle(for: .splitDelete) == .heavyImpact)
        }

        @Test("selection maps to selection")
        func selection() {
            #expect(HapticService.feedbackStyle(for: .selection) == .selection)
        }

        @Test("playPause maps to mediumImpact")
        func playPause() {
            #expect(HapticService.feedbackStyle(for: .playPause) == .mediumImpact)
        }

        @Test("navigation maps to lightImpact")
        func navigation() {
            #expect(HapticService.feedbackStyle(for: .navigation) == .lightImpact)
        }

        @Test("destructive maps to heavyImpact")
        func destructive() {
            #expect(HapticService.feedbackStyle(for: .destructive) == .heavyImpact)
        }

        @Test("keyframeAdd maps to lightImpact")
        func keyframeAdd() {
            #expect(HapticService.feedbackStyle(for: .keyframeAdd) == .lightImpact)
        }

        @Test("exportComplete maps to notification")
        func exportComplete() {
            #expect(HapticService.feedbackStyle(for: .exportComplete) == .notification)
        }

        @Test("Every haptic type has a defined feedback style")
        func allTypesCovered() {
            for type in EditorHapticType.allCases {
                let style = HapticService.feedbackStyle(for: type)
                #expect(HapticFeedbackStyle.allCases.contains(style))
            }
        }
    }

    // MARK: - HapticFeedbackStyle

    @Suite("HapticFeedbackStyle")
    struct StyleTests {

        @Test("allCases contains 5 styles")
        func allCasesCount() {
            #expect(HapticFeedbackStyle.allCases.count == 5)
        }

        @Test("Each style has a unique rawValue")
        func uniqueRawValues() {
            let rawValues = Set(HapticFeedbackStyle.allCases.map(\.rawValue))
            #expect(rawValues.count == HapticFeedbackStyle.allCases.count)
        }
    }

    // MARK: - Enabled State

    @Suite("Enabled State")
    @MainActor
    struct EnabledStateTests {

        @Test("Service can be created with test preferences")
        func creation() {
            let prefs = PreferencesRepository(suiteName: "test.haptic.\(UUID().uuidString)")
            let service = HapticService(preferences: prefs)
            #expect(service.isEnabled == true) // Default when no pref stored
        }

        @Test("setEnabled persists and reflects state")
        func setEnabled() {
            let prefs = PreferencesRepository(suiteName: "test.haptic.\(UUID().uuidString)")
            let service = HapticService(preferences: prefs)

            service.setEnabled(false)
            #expect(service.isEnabled == false)

            service.setEnabled(true)
            #expect(service.isEnabled == true)
        }

        @Test("Service reads stored preference on init")
        func readsStoredPref() {
            let suiteName = "test.haptic.\(UUID().uuidString)"
            let prefs = PreferencesRepository(suiteName: suiteName)
            prefs.set(false, forKey: HapticService.hapticsEnabledKey)

            let service = HapticService(preferences: prefs)
            #expect(service.isEnabled == false)
        }
    }
}
