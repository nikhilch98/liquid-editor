// ClipsRendererTests.swift
// LiquidEditorTests
//
// Tests for ClipsRenderer coordinate calculations and rendering logic.

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("ClipsRenderer Tests")
struct ClipsRendererTests {

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

    private func makeTrack(
        id: String = "track-1",
        index: Int = 0,
        height: Double = 64
    ) -> Track {
        Track(id: id, name: "Track \(index)", type: .mainVideo, index: index, height: height)
    }

    private func makeClip(
        id: String = "clip-1",
        trackId: String = "track-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000,
        speed: Double = 1.0,
        isReversed: Bool = false,
        hasEffects: Bool = false,
        effectCount: Int = 0,
        isOffline: Bool = false,
        label: String? = "Test Clip"
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration,
            speed: speed,
            isReversed: isReversed,
            label: label,
            isOffline: isOffline,
            hasEffects: hasEffects,
            effectCount: effectCount
        )
    }

    // MARK: - Clip Rect Calculation Tests

    @Test("calculateClipRect returns correct rect for clip at origin")
    func clipRectAtOrigin() {
        let viewport = makeViewport(microsPerPixel: 1000)
        let track = makeTrack(height: 64)
        let clip = makeClip(startTime: 0, duration: 100_000)

        let calculations = ClipsRenderCalculations(
            clips: [clip], tracks: [track], selectedClipIds: [],
            viewport: viewport, showTrimHandles: true, cornerRadius: 6
        )

        let rect = calculations.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)

        // x = (0 - 0) / 1000 = 0
        // width = 100_000 / 1000 = 100
        // y = rulerHeight + (0 * 64) - verticalOffset + paddingOffset = 30 + 2 = 32
        // height = 64 - 4 = 60
        #expect(rect.origin.x == 0)
        #expect(rect.width == 100)
        #expect(rect.origin.y == 32)
        #expect(rect.height == 60)
    }

    @Test("calculateClipRect accounts for scroll position")
    func clipRectWithScroll() {
        let viewport = makeViewport(scrollPosition: 50_000, microsPerPixel: 1000)
        let track = makeTrack(height: 64)
        let clip = makeClip(startTime: 100_000, duration: 50_000)

        let calculations = ClipsRenderCalculations(
            clips: [clip], tracks: [track], selectedClipIds: [],
            viewport: viewport, showTrimHandles: true, cornerRadius: 6
        )

        let rect = calculations.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)

        // x = (100_000 - 50_000) / 1000 = 50
        #expect(rect.origin.x == 50)
        #expect(rect.width == 50)
    }

    @Test("calculateClipRect for second track")
    func clipRectSecondTrack() {
        let viewport = makeViewport(microsPerPixel: 1000)
        let track = makeTrack(height: 64)
        let clip = makeClip(trackId: "track-2", startTime: 0, duration: 100_000)

        let calculations = ClipsRenderCalculations(
            clips: [clip], tracks: [track], selectedClipIds: [],
            viewport: viewport, showTrimHandles: true, cornerRadius: 6
        )

        let rect = calculations.calculateClipRect(clip: clip, trackIndex: 1, trackHeight: 64)

        // y = 30 + (1 * 64) - 0 + 2 = 96
        #expect(rect.origin.y == 96)
    }

    @Test("calculateClipRect with zero duration returns zero width")
    func clipRectZeroDuration() {
        let viewport = makeViewport(microsPerPixel: 1000)
        let track = makeTrack(height: 64)
        let clip = makeClip(startTime: 0, duration: 0)

        let calculations = ClipsRenderCalculations(
            clips: [clip], tracks: [track], selectedClipIds: [],
            viewport: viewport, showTrimHandles: true, cornerRadius: 6
        )

        let rect = calculations.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        #expect(rect.width == 0)
    }

    // MARK: - Speed Text Tests

    @Test("speedText for normal speed")
    func speedTextNormal() {
        #expect(ClipsRenderCalculations.speedText(for: 1.0) == "1x")
    }

    @Test("speedText for fast speed")
    func speedTextFast() {
        #expect(ClipsRenderCalculations.speedText(for: 2.0) == "2x")
    }

    @Test("speedText for fractional fast speed")
    func speedTextFractionalFast() {
        #expect(ClipsRenderCalculations.speedText(for: 1.5) == "1.5x")
    }

    @Test("speedText for slow speed")
    func speedTextSlow() {
        #expect(ClipsRenderCalculations.speedText(for: 0.5) == "50%")
    }

    @Test("speedText for very slow speed")
    func speedTextVerySlow() {
        #expect(ClipsRenderCalculations.speedText(for: 0.25) == "25%")
    }

    // MARK: - Speed Color Tests

    @Test("speedColor for fast is orange")
    func speedColorFast() {
        let color = ClipsRenderCalculations.speedColor(for: 2.0)
        // Just verify it returns without error; Color comparison is limited
        #expect(color == Color(red: 1.0, green: 0.584, blue: 0.0))
    }

    @Test("speedColor for slow is green")
    func speedColorSlow() {
        let color = ClipsRenderCalculations.speedColor(for: 0.5)
        #expect(color == Color(red: 0.204, green: 0.78, blue: 0.349))
    }

    // MARK: - Width Threshold Tests

    @Test("minimum width constants are reasonable")
    func widthThresholds() {
        #expect(ClipsRenderCalculations.minWidthForLabel == 30.0)
        #expect(ClipsRenderCalculations.minWidthForSpeedIndicator == 40.0)
        #expect(ClipsRenderCalculations.minWidthForEffectBadge == 50.0)
        #expect(ClipsRenderCalculations.minWidthForReverseIndicator == 30.0)
    }

    // MARK: - Extreme Zoom Tests

    @Test("calculateClipRect at extreme zoom in")
    func clipRectExtremeZoomIn() {
        let viewport = makeViewport(microsPerPixel: 100) // Very zoomed in
        let track = makeTrack(height: 64)
        let clip = makeClip(startTime: 0, duration: 1_000_000)

        let calculations = ClipsRenderCalculations(
            clips: [clip], tracks: [track], selectedClipIds: [],
            viewport: viewport, showTrimHandles: true, cornerRadius: 6
        )

        let rect = calculations.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)

        // width = 1_000_000 / 100 = 10_000 pixels
        #expect(rect.width == 10_000)
    }

    @Test("calculateClipRect at extreme zoom out")
    func clipRectExtremeZoomOut() {
        let viewport = makeViewport(microsPerPixel: 100_000) // Very zoomed out
        let track = makeTrack(height: 64)
        let clip = makeClip(startTime: 0, duration: 1_000_000)

        let calculations = ClipsRenderCalculations(
            clips: [clip], tracks: [track], selectedClipIds: [],
            viewport: viewport, showTrimHandles: true, cornerRadius: 6
        )

        let rect = calculations.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)

        // width = 1_000_000 / 100_000 = 10 pixels
        #expect(rect.width == 10)
    }
}
