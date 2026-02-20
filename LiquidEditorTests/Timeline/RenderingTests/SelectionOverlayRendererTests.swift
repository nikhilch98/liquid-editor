// SelectionOverlayRendererTests.swift
// LiquidEditorTests
//
// Tests for SelectionOverlayRenderer coordinate calculations.

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("SelectionOverlayRenderer Tests")
struct SelectionOverlayRendererTests {

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

    private func makeClip(
        id: String = "clip-1",
        trackId: String = "track-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration
        )
    }

    private func makeTrack(
        id: String = "track-1",
        index: Int = 0,
        height: Double = 64
    ) -> Track {
        Track(id: id, name: "Track", type: .mainVideo, index: index, height: height)
    }

    // MARK: - Clip Rect Calculation Tests

    @Test("calculateClipRect matches ClipsRenderer calculation")
    func clipRectConsistency() {
        let viewport = makeViewport(microsPerPixel: 1000)
        let clip = makeClip(startTime: 50_000, duration: 200_000)
        let track = makeTrack(height: 64)

        let selCalc = SelectionOverlayCalculations(
            selectedClips: [clip], tracks: [track], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )

        let clipCalc = ClipsRenderCalculations(
            clips: [clip], tracks: [track], selectedClipIds: [],
            viewport: viewport, showTrimHandles: true, cornerRadius: 6
        )

        let selRect = selCalc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        let clipRect = clipCalc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)

        #expect(selRect == clipRect)
    }

    // MARK: - Constants Tests

    @Test("selection overlay constants match expected values")
    func constants() {
        #expect(SelectionOverlayCalculations.cornerIndicatorLength == 8.0)
        #expect(SelectionOverlayCalculations.trimHandleWidth == 8.0)
        #expect(SelectionOverlayCalculations.trimHandleHeightRatio == 0.5)
        #expect(SelectionOverlayCalculations.marqueeDashLength == 6.0)
        #expect(SelectionOverlayCalculations.marqueeGapLength == 4.0)
    }

    // MARK: - Edge Cases

    @Test("empty selection draws nothing")
    func emptySelection() {
        let viewport = makeViewport()
        let calc = SelectionOverlayCalculations(
            selectedClips: [], tracks: [], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )
        // Just verify no crash with empty data
        #expect(calc.selectedClips.isEmpty)
    }

    @Test("clip outside viewport is skipped")
    func clipOutsideViewport() {
        let viewport = makeViewport(scrollPosition: 0, microsPerPixel: 1000, viewportWidth: 800)
        let clip = makeClip(startTime: 10_000_000, duration: 100_000)  // Way past viewport
        let track = makeTrack()

        let calc = SelectionOverlayCalculations(
            selectedClips: [clip], tracks: [track], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )

        let rect = calc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        // Clip starts at x = 10_000_000 / 1000 = 10000, well past 800 viewport width
        #expect(rect.minX > 800)
    }

    // MARK: - Additional Clip Rect Tests

    @Test("calculateClipRect width matches duration/microsPerPixel")
    func clipRectWidth() {
        let viewport = makeViewport(microsPerPixel: 1000)
        let clip = makeClip(startTime: 0, duration: 500_000)
        let track = makeTrack(height: 64)

        let calc = SelectionOverlayCalculations(
            selectedClips: [clip], tracks: [track], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )

        let rect = calc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        #expect(abs(rect.width - 500.0) < 0.001) // 500_000 / 1000 = 500
    }

    @Test("calculateClipRect applies padding offset")
    func clipRectPadding() {
        let viewport = makeViewport(microsPerPixel: 1000)
        let clip = makeClip(startTime: 0, duration: 100_000)
        let track = makeTrack(height: 64)

        let calc = SelectionOverlayCalculations(
            selectedClips: [clip], tracks: [track], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )

        let rect = calc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        // Height should be trackHeight - clipPadding
        #expect(abs(rect.height - (64 - SelectionOverlayCalculations.clipPadding)) < 0.001)
    }

    @Test("calculateClipRect for second track index offsets Y correctly")
    func clipRectSecondTrack() {
        let viewport = makeViewport(microsPerPixel: 1000)
        let clip = makeClip(startTime: 0, duration: 100_000)

        let calc = SelectionOverlayCalculations(
            selectedClips: [clip], tracks: [], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )

        let rect0 = calc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        let rect1 = calc.calculateClipRect(clip: clip, trackIndex: 1, trackHeight: 64)
        #expect(rect1.minY > rect0.minY)
    }

    // MARK: - Additional Constants Tests

    @Test("trim handle corner radius is positive")
    func trimHandleCornerRadius() {
        #expect(SelectionOverlayCalculations.trimHandleCornerRadius > 0)
    }

    @Test("grip line spacing is positive")
    func gripLineSpacing() {
        #expect(SelectionOverlayCalculations.gripLineSpacing > 0)
    }

    @Test("grip line height ratio is between 0 and 1")
    func gripLineHeightRatio() {
        #expect(SelectionOverlayCalculations.gripLineHeightRatio > 0)
        #expect(SelectionOverlayCalculations.gripLineHeightRatio <= 1)
    }

    @Test("selection glow alpha is positive")
    func selectionGlowAlpha() {
        #expect(SelectionOverlayCalculations.selectionGlowAlpha > 0)
        #expect(SelectionOverlayCalculations.selectionGlowAlpha <= 1)
    }

    @Test("clip padding values are positive")
    func clipPaddingValues() {
        #expect(SelectionOverlayCalculations.clipPadding > 0)
        #expect(SelectionOverlayCalculations.clipPaddingOffset >= 0)
    }

    // MARK: - Multiple Clips Tests

    @Test("multiple selected clips are stored")
    func multipleSelectedClips() {
        let viewport = makeViewport()
        let clip1 = makeClip(id: "c1", startTime: 0, duration: 100_000)
        let clip2 = makeClip(id: "c2", startTime: 200_000, duration: 100_000)
        let track = makeTrack()

        let calc = SelectionOverlayCalculations(
            selectedClips: [clip1, clip2], tracks: [track], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )
        #expect(calc.selectedClips.count == 2)
    }

    // MARK: - Selection State / Marquee Tests

    @Test("selectionState nil produces no marquee")
    func nilSelectionState() {
        let viewport = makeViewport()
        let calc = SelectionOverlayCalculations(
            selectedClips: [], tracks: [], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )
        #expect(calc.selectionState == nil)
    }

    @Test("calculations store corner radius")
    func cornerRadiusStored() {
        let viewport = makeViewport()
        let calc = SelectionOverlayCalculations(
            selectedClips: [], tracks: [], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 12
        )
        #expect(calc.cornerRadius == 12)
    }

    // MARK: - Clip on different viewport zoom levels

    @Test("calculateClipRect at high zoom shows wider clip")
    func clipRectHighZoom() {
        let viewport = makeViewport(microsPerPixel: 100) // Zoomed in
        let clip = makeClip(startTime: 0, duration: 100_000)

        let calc = SelectionOverlayCalculations(
            selectedClips: [clip], tracks: [], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )
        let rect = calc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        #expect(abs(rect.width - 1000.0) < 0.001) // 100_000 / 100 = 1000
    }

    @Test("calculateClipRect at low zoom shows narrower clip")
    func clipRectLowZoom() {
        let viewport = makeViewport(microsPerPixel: 10000) // Zoomed out
        let clip = makeClip(startTime: 0, duration: 100_000)

        let calc = SelectionOverlayCalculations(
            selectedClips: [clip], tracks: [], viewport: viewport,
            selectionState: nil, selectionColor: .blue, marqueeColor: .blue, cornerRadius: 6
        )
        let rect = calc.calculateClipRect(clip: clip, trackIndex: 0, trackHeight: 64)
        #expect(abs(rect.width - 10.0) < 0.001) // 100_000 / 10000 = 10
    }
}
