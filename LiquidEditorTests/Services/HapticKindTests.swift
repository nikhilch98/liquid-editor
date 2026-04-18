// HapticKindTests.swift
// LiquidEditorTests

import Testing
import Foundation
@testable import LiquidEditor

@Suite("HapticKind")
@MainActor
struct HapticKindTests {

    @Test("Each HapticKind maps to a UIKit feedback style")
    func kindToStyle() {
        #expect(HapticKind.tapPrimary.feedbackStyle == .mediumImpact)
        #expect(HapticKind.tapSecondary.feedbackStyle == .lightImpact)
        #expect(HapticKind.selection.feedbackStyle == .selection)
        #expect(HapticKind.pickup.feedbackStyle == .mediumImpact)
        #expect(HapticKind.drop.feedbackStyle == .lightImpact)
        #expect(HapticKind.boundary.feedbackStyle == .heavyImpact)
        #expect(HapticKind.success.feedbackStyle == .notification)
        #expect(HapticKind.warning.feedbackStyle == .notification)
        #expect(HapticKind.error.feedbackStyle == .notification)
    }

    @Test("play(_:) throttles identical kinds fired < 40 ms apart")
    func throttleSameKind() async throws {
        let service = HapticService.shared
        service.setEnabled(true)
        service.resetThrottleForTesting()

        #expect(service.playForTesting(.tapPrimary) == true)
        #expect(service.playForTesting(.tapPrimary) == false, "second call within 40ms should be throttled")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(service.playForTesting(.tapPrimary) == true, "after >40ms it should fire again")
    }

    @Test("play(_:) does not throttle different kinds")
    func throttleIsPerKind() {
        let service = HapticService.shared
        service.setEnabled(true)
        service.resetThrottleForTesting()

        #expect(service.playForTesting(.tapPrimary) == true)
        #expect(service.playForTesting(.selection) == true, "different kind fires immediately")
        #expect(service.playForTesting(.boundary) == true)
    }

    @Test("play(_:) respects the global isEnabled toggle")
    func disabledBlocksAll() {
        let service = HapticService.shared
        service.resetThrottleForTesting()
        service.setEnabled(false)

        #expect(service.playForTesting(.tapPrimary) == false)
        #expect(service.playForTesting(.selection) == false)

        service.setEnabled(true)
        #expect(service.playForTesting(.tapPrimary) == true)
    }
}
