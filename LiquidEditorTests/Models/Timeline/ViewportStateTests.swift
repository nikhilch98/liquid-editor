import Testing
import Foundation
@testable import LiquidEditor

@Suite("ViewportState Tests")
struct ViewportStateTests {

    private func makeViewport() -> ViewportState {
        ViewportState(
            scrollPosition: 0,
            microsPerPixel: 10000.0,
            viewportWidth: 400,
            viewportHeight: 300
        )
    }

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let vp = makeViewport()
        #expect(vp.scrollPosition == 0)
        #expect(vp.microsPerPixel == 10000.0)
        #expect(vp.viewportWidth == 400)
        #expect(vp.viewportHeight == 300)
        #expect(vp.verticalOffset == 0)
        #expect(vp.rulerHeight == 30)
        #expect(vp.trackHeaderWidth == 80)
    }

    @Test("initial factory method")
    func initialFactory() {
        let vp = ViewportState.initial(viewportWidth: 500, viewportHeight: 400)
        #expect(vp.scrollPosition == 0)
        #expect(vp.microsPerPixel == ViewportState.defaultMicrosPerPixel)
        #expect(vp.viewportWidth == 500)
        #expect(vp.viewportHeight == 400)
    }

    // MARK: - Computed Properties

    @Test("contentWidth subtracts track header")
    func contentWidth() {
        let vp = makeViewport()
        #expect(vp.contentWidth == 320) // 400 - 80
    }

    @Test("contentHeight subtracts ruler")
    func contentHeight() {
        let vp = makeViewport()
        #expect(vp.contentHeight == 270) // 300 - 30
    }

    @Test("visibleDuration")
    func visibleDuration() {
        let vp = makeViewport()
        // contentWidth=320, microsPerPixel=10000 => 3_200_000
        #expect(vp.visibleDuration == 3_200_000)
    }

    @Test("pixelsPerMicrosecond is inverse of zoom")
    func pixelsPerMicrosecond() {
        let vp = ViewportState(
            scrollPosition: 0,
            microsPerPixel: 5000,
            viewportWidth: 400,
            viewportHeight: 300
        )
        #expect(vp.pixelsPerMicrosecond == 1.0 / 5000.0)
    }

    @Test("visibleTimeRange")
    func visibleTimeRange() {
        let vp = ViewportState(
            scrollPosition: 1_000_000,
            microsPerPixel: 10000,
            viewportWidth: 400,
            viewportHeight: 300
        )
        let range = vp.visibleTimeRange
        #expect(range.start == 1_000_000)
        #expect(range.end == 1_000_000 + 3_200_000) // 4_200_000
    }

    // MARK: - Coordinate Conversion

    @Test("timeToPixelX at scroll=0")
    func timeToPixelXZeroScroll() {
        let vp = makeViewport()
        // 1_000_000 micros / 10000 micros/px = 100 px
        #expect(vp.timeToPixelX(1_000_000) == 100.0)
    }

    @Test("timeToPixelX with scroll offset")
    func timeToPixelXWithScroll() {
        let vp = ViewportState(
            scrollPosition: 500_000,
            microsPerPixel: 10000,
            viewportWidth: 400,
            viewportHeight: 300
        )
        // (1_000_000 - 500_000) / 10000 = 50 px
        #expect(vp.timeToPixelX(1_000_000) == 50.0)
    }

    @Test("timeToAbsolutePixelX includes track header")
    func timeToAbsolutePixelX() {
        let vp = makeViewport()
        let pixelX = vp.timeToAbsolutePixelX(1_000_000)
        #expect(pixelX == 180.0) // 80 (header) + 100
    }

    @Test("pixelXToTime converts back")
    func pixelXToTime() {
        let vp = makeViewport()
        let time = vp.pixelXToTime(100)
        #expect(time == 1_000_000) // 100 * 10000
    }

    @Test("absolutePixelXToTime accounts for header")
    func absolutePixelXToTime() {
        let vp = makeViewport()
        let time = vp.absolutePixelXToTime(180) // 180 - 80 = 100 content px
        #expect(time == 1_000_000)
    }

    @Test("trackIndexToPixelY")
    func trackIndexToPixelY() {
        let vp = makeViewport()
        let y = vp.trackIndexToPixelY(2, trackHeight: 60)
        // rulerHeight(30) + 2*60 - verticalOffset(0) = 150
        #expect(y == 150.0)
    }

    @Test("pixelYToTrackIndex")
    func pixelYToTrackIndex() {
        let vp = makeViewport()
        let index = vp.pixelYToTrackIndex(150, trackHeight: 60)
        // (150 - 30 + 0) / 60 = 2
        #expect(index == 2)
    }

    // MARK: - State Updates

    @Test("with() copy")
    func withCopy() {
        let vp = makeViewport()
        let modified = vp.with(scrollPosition: 500_000)
        #expect(modified.scrollPosition == 500_000)
        #expect(modified.microsPerPixel == vp.microsPerPixel)
    }

    @Test("withScrollPosition clamps to 0")
    func withScrollPositionClampMin() {
        let vp = makeViewport()
        let clamped = vp.withScrollPosition(-100)
        #expect(clamped.scrollPosition == 0)
    }

    @Test("withScrollPosition clamps to max")
    func withScrollPositionClampMax() {
        let vp = makeViewport()
        let clamped = vp.withScrollPosition(999, maxPosition: 500)
        #expect(clamped.scrollPosition == 500)
    }

    @Test("withZoom clamps to min")
    func withZoomClampMin() {
        let vp = makeViewport()
        let zoomed = vp.withZoom(10) // Below minMicrosPerPixel
        #expect(zoomed.microsPerPixel == ViewportState.minMicrosPerPixel)
    }

    @Test("withZoom clamps to max")
    func withZoomClampMax() {
        let vp = makeViewport()
        let zoomed = vp.withZoom(999_999) // Above maxMicrosPerPixel
        #expect(zoomed.microsPerPixel == ViewportState.maxMicrosPerPixel)
    }

    @Test("zoomCenteredOnTime preserves center")
    func zoomCenteredOnTime() {
        let vp = makeViewport()
        let centerTime: TimeMicros = 1_500_000
        let zoomed = vp.zoomCenteredOnTime(5000, centerTime: centerTime)
        // The center time should be at roughly the same pixel position
        #expect(zoomed.microsPerPixel == 5000)
    }

    @Test("withDimensions updates both")
    func withDimensions() {
        let vp = makeViewport()
        let resized = vp.withDimensions(width: 800, height: 600)
        #expect(resized.viewportWidth == 800)
        #expect(resized.viewportHeight == 600)
    }

    @Test("scrollToCenter centers on time")
    func scrollToCenter() {
        let vp = makeViewport()
        let centered = vp.scrollToCenter(5_000_000)
        // scrollPosition = time - contentWidth/2 * microsPerPixel
        // = 5_000_000 - 160 * 10000 = 5_000_000 - 1_600_000 = 3_400_000
        #expect(centered.scrollPosition == 3_400_000)
    }

    @Test("scrollByPixels adds time delta")
    func scrollByPixels() {
        let vp = makeViewport()
        let scrolled = vp.scrollByPixels(50) // 50 * 10000 = 500_000
        #expect(scrolled.scrollPosition == 500_000)
    }

    @Test("scrollVertically clamps to 0")
    func scrollVertically() {
        let vp = makeViewport()
        let scrolled = vp.scrollVertically(-100) // Would go negative
        #expect(scrolled.verticalOffset == 0)
    }

    @Test("scrollVertically clamps to max")
    func scrollVerticallyMax() {
        let vp = makeViewport()
        let scrolled = vp.scrollVertically(500, maxOffset: 200)
        #expect(scrolled.verticalOffset == 200)
    }

    // MARK: - Utility Methods

    @Test("isTimeVisible")
    func isTimeVisible() {
        let vp = makeViewport() // visible: [0, 3_200_000)
        #expect(vp.isTimeVisible(1_000_000))
        #expect(!vp.isTimeVisible(5_000_000))
    }

    @Test("isTimeRangeVisible")
    func isTimeRangeVisible() {
        let vp = makeViewport()
        #expect(vp.isTimeRangeVisible(TimeRange(1_000_000, 2_000_000)))
        #expect(!vp.isTimeRangeVisible(TimeRange(5_000_000, 6_000_000)))
        // Partially overlapping
        #expect(vp.isTimeRangeVisible(TimeRange(3_000_000, 4_000_000)))
    }

    @Test("zoomToFitDuration")
    func zoomToFitDuration() {
        let vp = makeViewport()
        let zoom = vp.zoomToFitDuration(10_000_000)
        // availableWidth = 320 * 0.8 = 256
        let expected = 10_000_000.0 / 256.0
        #expect(abs(zoom - expected) < 0.1)
    }

    // MARK: - Codable

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let vp = ViewportState(
            scrollPosition: 1_000_000,
            microsPerPixel: 5000,
            viewportWidth: 800,
            viewportHeight: 600,
            verticalOffset: 50,
            rulerHeight: 40,
            trackHeaderWidth: 100
        )
        let data = try JSONEncoder().encode(vp)
        let decoded = try JSONDecoder().decode(ViewportState.self, from: data)
        #expect(decoded == vp)
    }
}
