// RulerRendererTests.swift
// LiquidEditorTests
//
// Tests for RulerRenderer tick calculations and time formatting.

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("RulerRenderer Tests")
struct RulerRendererTests {

    // MARK: - Test Fixtures

    private func makeViewport(
        scrollPosition: TimeMicros = 0,
        microsPerPixel: Double = 1000,
        viewportWidth: Double = 800,
        viewportHeight: Double = 400
    ) -> ViewportState {
        ViewportState(
            scrollPosition: scrollPosition,
            microsPerPixel: microsPerPixel,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            rulerHeight: 30,
            trackHeaderWidth: 80
        )
    }

    private func makeCalculations(
        microsPerPixel: Double = 1000,
        scrollPosition: TimeMicros = 0
    ) -> RulerRenderCalculations {
        RulerRenderCalculations(
            viewport: makeViewport(scrollPosition: scrollPosition, microsPerPixel: microsPerPixel),
            inPoint: nil,
            outPoint: nil,
            height: 30,
            backgroundColor: .black,
            tickColor: .gray,
            textColor: .white,
            rangeColor: .blue
        )
    }

    // MARK: - Tick Config Tests

    @Test("getTickConfig returns finest ticks at high zoom")
    func tickConfigHighZoom() {
        let calc = makeCalculations(microsPerPixel: 100) // Very zoomed in
        let config = calc.getTickConfig()

        // At 100 us/px, targetMajorMicros = 100 * 80 = 8000
        // First config where majorInterval >= 4000: (1000, 10) -> majorInterval = 10000
        #expect(config.interval == 1_000)
        #expect(config.majorEvery == 10)
    }

    @Test("getTickConfig returns coarsest ticks at low zoom")
    func tickConfigLowZoom() {
        let calc = makeCalculations(microsPerPixel: 100_000) // Very zoomed out
        let config = calc.getTickConfig()

        // At 100000 us/px, targetMajorMicros = 100000 * 80 = 8_000_000
        // Need majorInterval >= 4_000_000: (1_000_000, 10) -> 10_000_000 >= 4_000_000
        #expect(config.interval >= 1_000_000)
    }

    @Test("getTickConfig at default zoom level")
    func tickConfigDefaultZoom() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        let config = calc.getTickConfig()

        // targetMajorMicros = 10000 * 80 = 800_000
        // Need majorInterval >= 400_000
        // (100_000, 10) -> 1_000_000 >= 400_000
        #expect(config.interval == 100_000)
        #expect(config.majorEvery == 10)
    }

    // MARK: - Time Format Tests

    @Test("formatTime for 0 seconds at normal zoom")
    func formatTimeZero() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        #expect(calc.formatTime(0) == "0s")
    }

    @Test("formatTime for 5 seconds at normal zoom")
    func formatTimeFiveSeconds() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        #expect(calc.formatTime(5_000_000) == "5s")
    }

    @Test("formatTime for 1 minute 30 seconds")
    func formatTimeOneMinuteThirty() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        #expect(calc.formatTime(90_000_000) == "1:30")
    }

    @Test("formatTime for 1 hour 5 minutes 30 seconds")
    func formatTimeOneHour() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        #expect(calc.formatTime(3_930_000_000) == "1:05:30")
    }

    @Test("formatTime shows milliseconds at high zoom")
    func formatTimeHighZoom() {
        let calc = makeCalculations(microsPerPixel: 100) // Very zoomed: < 5000
        let result = calc.formatTime(1_500_000) // 1.5 seconds
        #expect(result == "1.50")
    }

    @Test("formatTime for exactly 1 minute")
    func formatTimeOneMinute() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        #expect(calc.formatTime(60_000_000) == "1:00")
    }

    @Test("formatTime for zero with high zoom shows milliseconds")
    func formatTimeZeroHighZoom() {
        let calc = makeCalculations(microsPerPixel: 100)
        #expect(calc.formatTime(0) == "0.00")
    }

    // MARK: - Tick Config Table Tests

    @Test("tickConfigs list has correct count")
    func tickConfigCount() {
        #expect(RulerRenderCalculations.tickConfigs.count == 11)
    }

    @Test("tickConfigs are in ascending order")
    func tickConfigsAscending() {
        let configs = RulerRenderCalculations.tickConfigs
        for i in 1..<configs.count {
            let prevMajor = configs[i - 1].interval * configs[i - 1].majorEvery
            let currMajor = configs[i].interval * configs[i].majorEvery
            #expect(currMajor >= prevMajor, "Config \(i) should have major interval >= config \(i-1)")
        }
    }

    // MARK: - Constants Tests

    @Test("ruler constants are reasonable")
    func rulerConstants() {
        #expect(RulerConstants.defaultHeight == 30.0)
        #expect(RulerConstants.targetMajorSpacing == 80.0)
        #expect(RulerConstants.majorTickHeightRatio > RulerConstants.mediumTickHeightRatio)
        #expect(RulerConstants.mediumTickHeightRatio > RulerConstants.minorTickHeightRatio)
    }

    // MARK: - Additional Tick Config Tests

    @Test("getTickConfig returns valid config at all zoom levels")
    func tickConfigAllZooms() {
        let zoomLevels: [Double] = [10, 100, 1_000, 5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000]
        for zoom in zoomLevels {
            let calc = makeCalculations(microsPerPixel: zoom)
            let config = calc.getTickConfig()
            #expect(config.interval > 0, "Tick interval should be positive at zoom \(zoom)")
            #expect(config.majorEvery > 0, "majorEvery should be positive at zoom \(zoom)")
        }
    }

    @Test("getTickConfig at extreme zoom returns a wide interval config")
    func tickConfigExtremeZoom() {
        let calc = makeCalculations(microsPerPixel: 10_000_000) // Extremely zoomed out
        let config = calc.getTickConfig()
        // At extreme zoom-out, should return a config with large interval
        #expect(config.interval >= 300_000_000)
    }

    @Test("tickConfigs intervals are all positive")
    func tickConfigsPositive() {
        for config in RulerRenderCalculations.tickConfigs {
            #expect(config.interval > 0)
            #expect(config.majorEvery > 0)
        }
    }

    @Test("tickConfigs major intervals are all positive")
    func tickConfigsMajorPositive() {
        for config in RulerRenderCalculations.tickConfigs {
            let major = config.interval * config.majorEvery
            #expect(major > 0)
        }
    }

    // MARK: - Additional Time Format Tests

    @Test("formatTime for 30 seconds")
    func formatTimeThirtySeconds() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        #expect(calc.formatTime(30_000_000) == "30s")
    }

    @Test("formatTime for 59 seconds shows as seconds")
    func formatTimeFiftyNineSeconds() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        #expect(calc.formatTime(59_000_000) == "59s")
    }

    @Test("formatTime for exactly 2 hours")
    func formatTimeTwoHours() {
        let calc = makeCalculations(microsPerPixel: 10_000)
        let twoHours: TimeMicros = 7_200_000_000
        let result = calc.formatTime(twoHours)
        #expect(result == "2:00:00")
    }

    @Test("formatTime for high zoom at 1.5 seconds")
    func formatTimeHighZoomOnePointFive() {
        let calc = makeCalculations(microsPerPixel: 100)
        let result = calc.formatTime(1_500_000)
        #expect(result == "1.50")
    }

    @Test("formatTime for high zoom at 0.1 seconds")
    func formatTimeHighZoomTenth() {
        let calc = makeCalculations(microsPerPixel: 100)
        let result = calc.formatTime(100_000)
        #expect(result == "0.10")
    }

    @Test("formatTime boundary at microsPerPixel = 5000 shows seconds format")
    func formatTimeBoundaryZoom() {
        let calc = makeCalculations(microsPerPixel: 5000)
        let result = calc.formatTime(2_000_000)
        #expect(result == "2s")
    }

    @Test("formatTime boundary just below 5000 shows decimal format")
    func formatTimeBelowBoundaryZoom() {
        let calc = makeCalculations(microsPerPixel: 4999)
        let result = calc.formatTime(2_000_000)
        #expect(result == "2.00")
    }

    // MARK: - Additional Constants Tests

    @Test("ruler tick stroke widths are positive")
    func tickStrokeWidths() {
        #expect(RulerConstants.majorTickStroke > 0)
        #expect(RulerConstants.minorTickStroke > 0)
        #expect(RulerConstants.majorTickStroke >= RulerConstants.minorTickStroke)
    }

    @Test("ruler opacity values are in valid range")
    func opacityValues() {
        #expect(RulerConstants.borderOpacity > 0 && RulerConstants.borderOpacity <= 1)
        #expect(RulerConstants.rangeHighlightOpacity > 0 && RulerConstants.rangeHighlightOpacity <= 1)
        #expect(RulerConstants.mediumTickOpacity > 0 && RulerConstants.mediumTickOpacity <= 1)
        #expect(RulerConstants.minorTickOpacity > 0 && RulerConstants.minorTickOpacity <= 1)
    }

    @Test("ruler label constants are reasonable")
    func labelConstants() {
        #expect(RulerConstants.labelFontSize > 0)
        #expect(RulerConstants.labelTopOffset >= 0)
        #expect(RulerConstants.labelEdgePadding >= 0)
    }

    @Test("ruler range marker constants are positive")
    func rangeMarkerConstants() {
        #expect(RulerConstants.rangeMarkerWidth > 0)
        #expect(RulerConstants.triangleIndicatorSize > 0)
    }

    // MARK: - RulerRenderCalculations with In/Out Points

    @Test("calculations store in/out points correctly")
    func calculationsWithInOutPoints() {
        let calc = RulerRenderCalculations(
            viewport: makeViewport(),
            inPoint: 1_000_000,
            outPoint: 5_000_000,
            height: 30,
            backgroundColor: .black,
            tickColor: .gray,
            textColor: .white,
            rangeColor: .blue
        )
        #expect(calc.inPoint == 1_000_000)
        #expect(calc.outPoint == 5_000_000)
    }

    @Test("calculations store nil in/out points")
    func calculationsWithNilInOutPoints() {
        let calc = makeCalculations()
        #expect(calc.inPoint == nil)
        #expect(calc.outPoint == nil)
    }

    // MARK: - Scrolled Viewport Tests

    @Test("getTickConfig with scrolled viewport still works")
    func tickConfigScrolledViewport() {
        let calc = makeCalculations(microsPerPixel: 10_000, scrollPosition: 5_000_000)
        let config = calc.getTickConfig()
        #expect(config.interval > 0)
    }
}
