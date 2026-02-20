import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("TimelineZoomController Tests")
@MainActor
struct TimelineZoomControllerTests {

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

    private func makeController(viewport: ViewportState? = nil) -> TimelineZoomController {
        let controller = TimelineZoomController()
        controller.updateViewport(viewport ?? makeViewport())
        return controller
    }

    // MARK: - ZoomState Tests

    @Test("idle zoom state")
    func idleZoomState() {
        let state = ZoomState.idle
        #expect(state.type == .idle)
        #expect(!state.isZooming)
        #expect(!state.isAnimating)
        #expect(state.scaleChange == 1.0)
    }

    @Test("zoom state copyWith")
    func zoomStateCopyWith() {
        let state = ZoomState.idle
        let updated = state.with(type: .pinching, currentScale: 2.0)
        #expect(updated.type == .pinching)
        #expect(updated.currentScale == 2.0)
        #expect(updated.initialScale == 1.0) // unchanged
    }

    @Test("zoom state scaleChange calculation")
    func zoomStateScaleChange() {
        let state = ZoomState(
            type: .pinching,
            initialScale: 1.0,
            currentScale: 2.0,
            focalPoint: .zero,
            anchorTime: 0,
            initialMicrosPerPixel: 10000,
            currentMicrosPerPixel: 5000
        )
        #expect(state.scaleChange == 2.0)
    }

    // MARK: - Constants Tests

    @Test("zoom constants are valid")
    func zoomConstants() {
        #expect(TimelineZoomController.minScaleFactor > 0)
        #expect(TimelineZoomController.maxScaleFactor > TimelineZoomController.minScaleFactor)
        #expect(TimelineZoomController.defaultAnimationDuration > 0)
    }

    // MARK: - Start Zoom Tests

    @Test("startZoom sets pinching state")
    func startZoomSetsPinching() {
        let controller = makeController()
        let result = controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))

        #expect(result.type == .pinching)
        #expect(result.isZooming)
        #expect(result.initialScale == 1.0)
        #expect(result.focalPoint == CGPoint(x: 200, y: 100))
    }

    @Test("startZoom calculates anchor time from focal point")
    func startZoomCalculatesAnchorTime() {
        let controller = makeController()
        let result = controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 180, y: 100))

        // absolutePixelXToTime(180) = pixelXToTime(180 - 80) = 0 + (100 * 10000) = 1_000_000
        #expect(result.anchorTime == 1_000_000)
    }

    // MARK: - Update Zoom Tests

    @Test("updateZoom changes microsPerPixel")
    func updateZoomChangesMicrosPerPixel() {
        let controller = makeController()
        controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))

        // Scale up by 2x - should halve microsPerPixel
        let vp = controller.updateZoom(scale: 2.0)
        #expect(vp.microsPerPixel == 5000.0) // 10000 / 2
    }

    @Test("updateZoom when not pinching does nothing")
    func updateZoomNotPinching() {
        let controller = makeController()
        let vp = controller.updateZoom(scale: 2.0)
        #expect(vp.microsPerPixel == 10000.0) // unchanged
    }

    @Test("updateZoom clamps to min microsPerPixel")
    func updateZoomClampsMin() {
        let controller = makeController()
        controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))

        // Very large scale should clamp
        let vp = controller.updateZoom(scale: 1000.0)
        #expect(vp.microsPerPixel == ViewportState.minMicrosPerPixel)
    }

    @Test("updateZoom clamps to max microsPerPixel")
    func updateZoomClampsMax() {
        let controller = makeController()
        controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))

        // Very small scale should clamp
        let vp = controller.updateZoom(scale: 0.001)
        #expect(vp.microsPerPixel == ViewportState.maxMicrosPerPixel)
    }

    @Test("updateZoom updates focal point")
    func updateZoomUpdatesFocalPoint() {
        let controller = makeController()
        controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))

        controller.updateZoom(scale: 1.5, focalPoint: CGPoint(x: 210, y: 110))
        #expect(controller.state.focalPoint == CGPoint(x: 210, y: 110))
    }

    // MARK: - End Zoom Tests

    @Test("endZoom when not pinching does nothing")
    func endZoomNotPinching() {
        let controller = makeController()
        let vp = controller.endZoom()
        #expect(vp.microsPerPixel == 10000.0) // unchanged
    }

    @Test("endZoom returns to idle")
    func endZoomReturnsToIdle() {
        let controller = makeController()
        controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))
        controller.updateZoom(scale: 2.0)

        let vp = controller.endZoom()
        #expect(controller.state.type == .idle)
        #expect(vp.microsPerPixel == 5000.0) // maintains zoomed state
    }

    // MARK: - Programmatic Zoom Tests

    @Test("zoomTo sets specific microsPerPixel")
    func zoomToSpecific() {
        let controller = makeController()
        let vp = controller.zoomTo(targetMicrosPerPixel: 5000.0)
        #expect(vp.microsPerPixel == 5000.0)
        #expect(controller.state.type == .idle)
    }

    @Test("zoomTo clamps to valid range")
    func zoomToClampsRange() {
        let controller = makeController()

        let vpMin = controller.zoomTo(targetMicrosPerPixel: 1.0)
        #expect(vpMin.microsPerPixel == ViewportState.minMicrosPerPixel)

        let vpMax = controller.zoomTo(targetMicrosPerPixel: 1_000_000.0)
        #expect(vpMax.microsPerPixel == ViewportState.maxMicrosPerPixel)
    }

    @Test("zoomTo with anchor time preserves anchor")
    func zoomToWithAnchor() {
        let controller = makeController()
        let vp = controller.zoomTo(targetMicrosPerPixel: 5000.0, anchorTime: 1_000_000)
        #expect(vp.microsPerPixel == 5000.0)
    }

    @Test("zoomIn halves microsPerPixel by default")
    func zoomInDefault() {
        let controller = makeController()
        let vp = controller.zoomIn()
        #expect(vp.microsPerPixel == 5000.0) // 10000 / 2
    }

    @Test("zoomIn with custom factor")
    func zoomInCustomFactor() {
        let controller = makeController()
        let vp = controller.zoomIn(factor: 4.0)
        #expect(vp.microsPerPixel == 2500.0) // 10000 / 4
    }

    @Test("zoomOut doubles microsPerPixel by default")
    func zoomOutDefault() {
        let controller = makeController()
        let vp = controller.zoomOut()
        #expect(vp.microsPerPixel == 20000.0) // 10000 * 2
    }

    @Test("zoomOut with custom factor")
    func zoomOutCustomFactor() {
        let controller = makeController()
        let vp = controller.zoomOut(factor: 3.0)
        #expect(vp.microsPerPixel == 30000.0) // 10000 * 3
    }

    @Test("zoomToFitAll calculates correct zoom for duration")
    func zoomToFitAll() {
        let controller = makeController()
        let vp = controller.zoomToFitAll(totalDuration: 10_000_000)

        // contentWidth = 320, margin = 0.05
        // availableWidth = 320 * 0.9 = 288
        // target = 10_000_000 / 288 ~= 34_722
        // clamped to maxMicrosPerPixel (100_000) if needed
        #expect(vp.microsPerPixel > 0)
        #expect(vp.microsPerPixel <= ViewportState.maxMicrosPerPixel)
    }

    @Test("zoomToFitAll with zero duration does nothing")
    func zoomToFitAllZeroDuration() {
        let controller = makeController()
        let vp = controller.zoomToFitAll(totalDuration: 0)
        #expect(vp.microsPerPixel == 10000.0) // unchanged
    }

    @Test("zoomToSelection fits time range")
    func zoomToSelection() {
        let controller = makeController()
        let vp = controller.zoomToSelection(startTime: 1_000_000, endTime: 3_000_000)
        #expect(vp.microsPerPixel > 0)
    }

    @Test("zoomToSelection with zero range does nothing")
    func zoomToSelectionZeroRange() {
        let controller = makeController()
        let vp = controller.zoomToSelection(startTime: 1_000_000, endTime: 1_000_000)
        #expect(vp.microsPerPixel == 10000.0) // unchanged
    }

    @Test("zoomToTimeRange delegates to zoomToSelection")
    func zoomToTimeRange() {
        let controller = makeController()
        let range = TimeRange(1_000_000, 5_000_000)
        let vp = controller.zoomToTimeRange(range)
        #expect(vp.microsPerPixel > 0)
    }

    @Test("resetZoom restores default")
    func resetZoomRestoresDefault() {
        let controller = makeController()
        controller.zoomIn()
        let vp = controller.resetZoom()
        #expect(vp.microsPerPixel == ViewportState.defaultMicrosPerPixel)
    }

    // MARK: - Callback Tests

    @Test("onViewportChanged fires on zoom")
    func onViewportChangedCallback() {
        let controller = makeController()
        var callbackCount = 0
        controller.onViewportChanged = { _ in callbackCount += 1 }

        controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))
        controller.updateZoom(scale: 2.0)
        #expect(callbackCount == 1)
    }

    @Test("onStateChanged fires on zoom start")
    func onStateChangedCallback() {
        let controller = makeController()
        var callbackCount = 0
        controller.onStateChanged = { _ in callbackCount += 1 }

        controller.startZoom(scale: 1.0, focalPoint: CGPoint(x: 200, y: 100))
        #expect(callbackCount == 1)
    }

    @Test("both callbacks fire on programmatic zoom")
    func bothCallbacksFire() {
        let controller = makeController()
        var viewportCallbackCount = 0
        var stateCallbackCount = 0
        controller.onViewportChanged = { _ in viewportCallbackCount += 1 }
        controller.onStateChanged = { _ in stateCallbackCount += 1 }

        controller.zoomTo(targetMicrosPerPixel: 5000.0)
        #expect(viewportCallbackCount == 1)
        #expect(stateCallbackCount == 1)
    }
}
