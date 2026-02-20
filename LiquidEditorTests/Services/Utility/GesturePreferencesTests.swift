import Testing
import Foundation
@testable import LiquidEditor

@Suite("GesturePreferences Tests")
@MainActor
struct GesturePreferencesTests {

    /// Helper to create an isolated GesturePreferences instance for testing.
    private func makeTestPreferences() -> (GesturePreferences, PreferencesRepository) {
        let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
        let gesture = GesturePreferences(preferences: prefs)
        return (gesture, prefs)
    }

    // MARK: - Default Values

    @Suite("Default Values")
    @MainActor
    struct DefaultValueTests {

        @Test("Default pinchZoomSensitivity is 1.0")
        func defaultPinchZoom() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            #expect(gesture.pinchZoomSensitivity == 1.0)
        }

        @Test("Default swipeThreshold is 1.0")
        func defaultSwipeThreshold() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            #expect(gesture.swipeThreshold == 1.0)
        }

        @Test("Default longPressDurationMs is 500")
        func defaultLongPress() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            #expect(gesture.longPressDurationMs == 500)
        }

        @Test("Default longPressDuration is 0.5 seconds")
        func defaultLongPressDuration() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            #expect(abs(gesture.longPressDuration - 0.5) < 0.001)
        }
    }

    // MARK: - Pinch Zoom Sensitivity

    @Suite("Pinch Zoom Sensitivity")
    @MainActor
    struct PinchZoomTests {

        @Test("Setting pinch zoom sensitivity stores and reflects value")
        func setAndGet() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setPinchZoomSensitivity(1.5)
            #expect(gesture.pinchZoomSensitivity == 1.5)
        }

        @Test("Pinch zoom clamped at lower bound (0.5)")
        func clampLow() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setPinchZoomSensitivity(0.1)
            #expect(gesture.pinchZoomSensitivity == 0.5)
        }

        @Test("Pinch zoom clamped at upper bound (2.0)")
        func clampHigh() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setPinchZoomSensitivity(5.0)
            #expect(gesture.pinchZoomSensitivity == 2.0)
        }

        @Test("applyPinchSensitivity multiplies raw delta by sensitivity")
        func applySensitivity() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setPinchZoomSensitivity(1.5)
            let result = gesture.applyPinchSensitivity(10.0)
            #expect(abs(result - 15.0) < 0.001)
        }

        @Test("applyPinchSensitivity with default returns same value")
        func applyDefaultSensitivity() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            let result = gesture.applyPinchSensitivity(10.0)
            #expect(abs(result - 10.0) < 0.001)
        }
    }

    // MARK: - Swipe Threshold

    @Suite("Swipe Threshold")
    @MainActor
    struct SwipeThresholdTests {

        @Test("Setting swipe threshold stores and reflects value")
        func setAndGet() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setSwipeThreshold(0.8)
            #expect(gesture.swipeThreshold == 0.8)
        }

        @Test("Swipe threshold clamped at lower bound (0.5)")
        func clampLow() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setSwipeThreshold(0.1)
            #expect(gesture.swipeThreshold == 0.5)
        }

        @Test("Swipe threshold clamped at upper bound (2.0)")
        func clampHigh() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setSwipeThreshold(3.0)
            #expect(gesture.swipeThreshold == 2.0)
        }

        @Test("isSwipeTriggered with default threshold and 600 velocity is true")
        func swipeTriggered() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            // Default threshold = 1.0, base = 500, so 600 > 500 = true
            #expect(gesture.isSwipeTriggered(velocityPxPerSec: 600) == true)
        }

        @Test("isSwipeTriggered with default threshold and 400 velocity is false")
        func swipeNotTriggered() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            // 400 < 500 = false
            #expect(gesture.isSwipeTriggered(velocityPxPerSec: 400) == false)
        }

        @Test("isSwipeTriggered accounts for negative velocity")
        func negativeVelocity() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            #expect(gesture.isSwipeTriggered(velocityPxPerSec: -600) == true)
        }

        @Test("Higher swipe threshold requires higher velocity")
        func higherThreshold() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setSwipeThreshold(2.0)
            // Now threshold = 500 * 2.0 = 1000
            #expect(gesture.isSwipeTriggered(velocityPxPerSec: 800) == false)
            #expect(gesture.isSwipeTriggered(velocityPxPerSec: 1100) == true)
        }
    }

    // MARK: - Long Press Duration

    @Suite("Long Press Duration")
    @MainActor
    struct LongPressTests {

        @Test("Setting long press duration stores and reflects value")
        func setAndGet() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setLongPressDurationMs(700)
            #expect(gesture.longPressDurationMs == 700)
        }

        @Test("Long press clamped at lower bound (300)")
        func clampLow() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setLongPressDurationMs(100)
            #expect(gesture.longPressDurationMs == 300)
        }

        @Test("Long press clamped at upper bound (1000)")
        func clampHigh() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setLongPressDurationMs(2000)
            #expect(gesture.longPressDurationMs == 1000)
        }

        @Test("longPressDuration converts ms to seconds correctly")
        func durationConversion() {
            let prefs = PreferencesRepository(suiteName: "test.gesture.\(UUID().uuidString)")
            let gesture = GesturePreferences(preferences: prefs)
            gesture.setLongPressDurationMs(750)
            #expect(abs(gesture.longPressDuration - 0.75) < 0.001)
        }
    }

    // MARK: - Persistence

    @Suite("Persistence")
    @MainActor
    struct PersistenceTests {

        @Test("Values persist across instances with same suite")
        func persistenceRoundtrip() {
            let suiteName = "test.gesture.\(UUID().uuidString)"

            // Write values
            let prefs1 = PreferencesRepository(suiteName: suiteName)
            let gesture1 = GesturePreferences(preferences: prefs1)
            gesture1.setPinchZoomSensitivity(1.8)
            gesture1.setSwipeThreshold(0.6)
            gesture1.setLongPressDurationMs(800)

            // Read back from new instance with same suite
            let prefs2 = PreferencesRepository(suiteName: suiteName)
            let gesture2 = GesturePreferences(preferences: prefs2)
            #expect(gesture2.pinchZoomSensitivity == 1.8)
            #expect(gesture2.swipeThreshold == 0.6)
            #expect(gesture2.longPressDurationMs == 800)
        }
    }

    // MARK: - Ranges

    @Suite("Ranges")
    struct RangeTests {

        @Test("Pinch zoom range is 0.5 to 2.0")
        func pinchZoomRange() {
            #expect(GesturePreferences.pinchZoomRange == 0.5...2.0)
        }

        @Test("Swipe threshold range is 0.5 to 2.0")
        func swipeThresholdRange() {
            #expect(GesturePreferences.swipeThresholdRange == 0.5...2.0)
        }

        @Test("Long press duration range is 300 to 1000")
        func longPressRange() {
            #expect(GesturePreferences.longPressDurationMsRange == 300...1000)
        }
    }
}
