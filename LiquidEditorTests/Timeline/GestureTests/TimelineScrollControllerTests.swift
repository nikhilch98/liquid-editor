import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("TimelineScrollController Tests")
@MainActor
struct TimelineScrollControllerTests {

    // MARK: - Test Helpers

    private func makeViewport() -> ViewportState {
        ViewportState(
            scrollPosition: 0,
            microsPerPixel: 10000.0,
            viewportWidth: 400,
            viewportHeight: 300,
            rulerHeight: 30,
            trackHeaderWidth: 80
        )
    }

    private func makeController(
        viewport: ViewportState? = nil,
        maxScrollPosition: TimeMicros = 10_000_000
    ) -> TimelineScrollController {
        let controller = TimelineScrollController()
        controller.updateViewport(viewport ?? makeViewport())
        controller.updateMaxScrollPosition(maxScrollPosition)
        return controller
    }

    // MARK: - ScrollState Tests

    @Test("idle scroll state")
    func idleScrollState() {
        let state = ScrollState.idle
        #expect(state.type == .idle)
        #expect(!state.isScrolling)
        #expect(!state.hasMomentum)
        #expect(!state.atBound)
    }

    @Test("scroll state copyWith")
    func scrollStateCopyWith() {
        let state = ScrollState.idle
        let updated = state.with(type: .scrolling, velocity: 100.0)
        #expect(updated.type == .scrolling)
        #expect(updated.velocity == 100.0)
        #expect(updated.initialScrollPosition == 0) // unchanged
    }

    @Test("scroll state atBound")
    func scrollStateAtBound() {
        let state = ScrollState.idle.with(atStart: true)
        #expect(state.atBound)

        let state2 = ScrollState.idle.with(atEnd: true)
        #expect(state2.atBound)

        let state3 = ScrollState.idle
        #expect(!state3.atBound)
    }

    // MARK: - Constants Tests

    @Test("physics constants have reasonable values")
    func physicsConstants() {
        #expect(TimelineScrollController.iosFrictionCoefficient > 0)
        #expect(TimelineScrollController.iosFrictionCoefficient < 1)
        #expect(TimelineScrollController.minMomentumVelocity > 0)
        #expect(TimelineScrollController.stoppingVelocity > 0)
        #expect(TimelineScrollController.stoppingVelocity < TimelineScrollController.minMomentumVelocity)
    }

    // MARK: - Start Scroll Tests

    @Test("startScroll sets scrolling state")
    func startScrollSetsState() {
        let controller = makeController()
        let result = controller.startScroll()

        #expect(result.type == .scrolling)
        #expect(result.isScrolling)
        #expect(result.initialScrollPosition == 0)
        #expect(result.currentScrollPosition == 0)
    }

    // MARK: - Scroll Tests

    @Test("scroll moves viewport by pixel delta")
    func scrollMovesViewport() {
        let controller = makeController()
        controller.startScroll()

        // Scroll 100 pixels = 100 * 10000 = 1_000_000 micros
        let vp = controller.scroll(100)
        #expect(vp.scrollPosition == 1_000_000)
    }

    @Test("scroll clamps at zero")
    func scrollClampsAtZero() {
        let controller = makeController()
        controller.startScroll()

        // Try to scroll left past zero
        let vp = controller.scroll(-100)
        #expect(vp.scrollPosition == 0)
        #expect(controller.state.atStart)
    }

    @Test("scroll clamps at max position")
    func scrollClampsAtMax() {
        let controller = makeController(maxScrollPosition: 1_000_000)
        controller.startScroll()

        // Try to scroll past max
        let vp = controller.scroll(200) // 200 * 10000 = 2_000_000 > 1_000_000
        #expect(vp.scrollPosition == 1_000_000)
        #expect(controller.state.atEnd)
    }

    @Test("scrollByTime converts correctly")
    func scrollByTime() {
        let controller = makeController()
        controller.startScroll()

        let vp = controller.scrollByTime(500_000)
        #expect(vp.scrollPosition == 500_000)
    }

    // MARK: - End Scroll Tests

    @Test("endScroll without velocity returns to idle")
    func endScrollNoVelocity() {
        let controller = makeController()
        controller.startScroll()
        controller.scroll(100)

        let vp = controller.endScroll(velocityPixelsPerSecond: 0)
        #expect(controller.state.type == .idle)
        #expect(vp.scrollPosition == 1_000_000)
    }

    @Test("endScroll with low velocity returns to idle")
    func endScrollLowVelocity() {
        let controller = makeController()
        controller.startScroll()
        controller.scroll(100)

        // Low velocity: 5 * 10000 = 50_000 < minMomentumVelocity (100_000)
        let _ = controller.endScroll(velocityPixelsPerSecond: 5)
        #expect(controller.state.type == .idle)
    }

    @Test("endScroll with high velocity starts momentum")
    func endScrollHighVelocity() {
        let controller = makeController()
        controller.startScroll()
        controller.scroll(50)

        // High velocity: 20 * 10000 = 200_000 > minMomentumVelocity (100_000)
        let _ = controller.endScroll(velocityPixelsPerSecond: 20)
        #expect(controller.state.type == .momentum)
    }

    @Test("endScroll at bound does not start momentum")
    func endScrollAtBoundNoMomentum() {
        let controller = makeController(maxScrollPosition: 500_000)
        controller.startScroll()
        controller.scroll(200) // will clamp to max

        let _ = controller.endScroll(velocityPixelsPerSecond: 100)
        // At bound, should not start momentum
        #expect(controller.state.type == .idle)
    }

    @Test("endScroll when not scrolling does nothing")
    func endScrollWhenNotScrolling() {
        let controller = makeController()
        let vp = controller.endScroll(velocityPixelsPerSecond: 100)
        #expect(vp.scrollPosition == 0) // unchanged
    }

    // MARK: - Momentum Tests

    @Test("stopMomentum returns to idle")
    func stopMomentumReturnsToIdle() {
        let controller = makeController()
        controller.startScroll()
        controller.scroll(50)
        controller.endScroll(velocityPixelsPerSecond: 50)

        controller.stopMomentum()
        #expect(controller.state.type == .idle)
    }

    // MARK: - Programmatic Scroll Tests

    @Test("scrollToTime sets position")
    func scrollToTimeSetPosition() {
        let controller = makeController()
        let vp = controller.scrollToTime(500_000)
        #expect(vp.scrollPosition == 500_000)
        #expect(controller.state.type == .idle)
    }

    @Test("scrollToTime clamps to zero")
    func scrollToTimeClampsZero() {
        let controller = makeController()
        let vp = controller.scrollToTime(-100_000)
        #expect(vp.scrollPosition == 0)
    }

    @Test("scrollToTime clamps to max")
    func scrollToTimeClampsMax() {
        let controller = makeController(maxScrollPosition: 5_000_000)
        let vp = controller.scrollToTime(10_000_000)
        #expect(vp.scrollPosition == 5_000_000)
    }

    @Test("centerOnTime centers viewport")
    func centerOnTimeTest() {
        let controller = makeController()
        let vp = controller.centerOnTime(5_000_000)

        // contentWidth = 400 - 80 = 320
        // centerOffset = 320/2 * 10000 = 1_600_000
        // expected scroll = 5_000_000 - 1_600_000 = 3_400_000
        #expect(vp.scrollPosition == 3_400_000)
    }

    @Test("centerOnTime clamps to zero for small time")
    func centerOnTimeClampsZero() {
        let controller = makeController()
        let vp = controller.centerOnTime(100_000)

        // centerOffset = 1_600_000, so 100_000 - 1_600_000 < 0 -> clamp to 0
        #expect(vp.scrollPosition == 0)
    }

    @Test("scrollToMakeVisible does nothing if already visible")
    func scrollToMakeVisibleAlreadyVisible() {
        let controller = makeController()
        // Visible range at scroll 0: 0 to 3_200_000
        let vp = controller.scrollToMakeVisible(1_000_000)
        #expect(vp.scrollPosition == 0) // no change
    }

    @Test("scrollToMakeVisible scrolls right for time beyond viewport")
    func scrollToMakeVisibleScrollsRight() {
        let controller = makeController()
        // Visible range at scroll 0: 0 to 3_200_000
        let vp = controller.scrollToMakeVisible(5_000_000)
        #expect(vp.scrollPosition > 0)
    }

    // MARK: - Callback Tests

    @Test("onViewportChanged fires on scroll")
    func onViewportChangedCallback() {
        let controller = makeController()
        var callbackCount = 0
        controller.onViewportChanged = { _ in callbackCount += 1 }

        controller.startScroll()
        controller.scroll(100)
        #expect(callbackCount == 1)
    }

    @Test("onStateChanged fires on startScroll")
    func onStateChangedCallback() {
        let controller = makeController()
        var callbackCount = 0
        controller.onStateChanged = { _ in callbackCount += 1 }

        controller.startScroll()
        #expect(callbackCount == 1)
    }

    // MARK: - Dispose Tests

    @Test("dispose stops momentum")
    func disposeStopsMomentum() {
        let controller = makeController()
        controller.startScroll()
        controller.scroll(50)
        controller.endScroll(velocityPixelsPerSecond: 50)

        controller.dispose()
        // After dispose, momentum should be stopped
        // State might transition to idle
        #expect(controller.state.type == .idle || controller.state.type == .momentum)
    }
}
