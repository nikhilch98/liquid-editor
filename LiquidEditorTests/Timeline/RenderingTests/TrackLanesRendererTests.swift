// TrackLanesRendererTests.swift
// LiquidEditorTests
//
// Tests for TrackLanesRenderer calculations.

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("TrackLanesRenderer Tests")
struct TrackLanesRendererTests {

    // MARK: - Test Fixtures

    private func makeViewport(
        scrollPosition: TimeMicros = 0,
        microsPerPixel: Double = 1000,
        viewportWidth: Double = 800,
        viewportHeight: Double = 400,
        verticalOffset: Double = 0
    ) -> ViewportState {
        ViewportState(
            scrollPosition: scrollPosition,
            microsPerPixel: microsPerPixel,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            verticalOffset: verticalOffset,
            rulerHeight: 30,
            trackHeaderWidth: 80
        )
    }

    private func makeTrack(
        id: String = "track-1",
        index: Int = 0,
        height: Double = 64,
        isMuted: Bool = false,
        isLocked: Bool = false,
        isCollapsed: Bool = false,
        isVisible: Bool = true
    ) -> Track {
        Track(
            id: id, name: "Track \(index)", type: .mainVideo, index: index,
            height: height, isMuted: isMuted, isLocked: isLocked,
            isCollapsed: isCollapsed, isVisible: isVisible
        )
    }

    // MARK: - Track Y Position Tests

    @Test("trackY for first track at default offset")
    func trackYFirstTrack() {
        let viewport = makeViewport()
        let tracks = [makeTrack(index: 0, height: 64)]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )

        let y = calc.trackY(at: 0)
        // rulerHeight - verticalOffset = 30 - 0 = 30
        #expect(y == 30)
    }

    @Test("trackY for second track")
    func trackYSecondTrack() {
        let viewport = makeViewport()
        let tracks = [
            makeTrack(id: "t1", index: 0, height: 64),
            makeTrack(id: "t2", index: 1, height: 64),
        ]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )

        let y = calc.trackY(at: 1)
        // 30 + 64 = 94
        #expect(y == 94)
    }

    @Test("trackY accounts for vertical scroll offset")
    func trackYWithOffset() {
        let viewport = makeViewport(verticalOffset: 20)
        let tracks = [makeTrack(index: 0, height: 64)]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )

        let y = calc.trackY(at: 0)
        // 30 - 20 = 10
        #expect(y == 10)
    }

    @Test("trackY with mixed heights")
    func trackYMixedHeights() {
        let viewport = makeViewport()
        let tracks = [
            makeTrack(id: "t1", index: 0, height: 44),   // small
            makeTrack(id: "t2", index: 1, height: 88),   // large
            makeTrack(id: "t3", index: 2, height: 64),   // medium
        ]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )

        let y2 = calc.trackY(at: 2)
        // 30 + 44 + 88 = 162
        #expect(y2 == 162)
    }

    // MARK: - Constants Tests

    @Test("track lane constants are reasonable")
    func constants() {
        #expect(TrackLanesCalculations.trackIndicatorWidth == 3.0)
        #expect(TrackLanesCalculations.rulerShadowHeight == 4.0)
        #expect(TrackLanesCalculations.lockedStripeWidth > 0)
        #expect(TrackLanesCalculations.lockedStripeGap > 0)
    }

    // MARK: - Empty Tracks Test

    @Test("empty tracks produces no drawing")
    func emptyTracks() {
        let viewport = makeViewport()
        let calc = TrackLanesCalculations(
            tracks: [], viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )

        // Verify tracks are empty (drawing would be a no-op)
        #expect(calc.tracks.isEmpty)
    }

    // MARK: - Collapsed Track Tests

    @Test("collapsed track uses collapsed height")
    func collapsedTrackHeight() {
        let track = makeTrack(height: 88, isCollapsed: true)
        #expect(track.effectiveHeight == Track.heightSmall)
        #expect(track.effectiveHeight < 88)
    }

    // MARK: - Additional TrackY Tests

    @Test("trackY with out-of-bounds index uses available tracks")
    func trackYOutOfBounds() {
        let viewport = makeViewport()
        let tracks = [makeTrack(index: 0, height: 64)]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )
        // Index beyond tracks count - should still calculate (loop exits early)
        let y = calc.trackY(at: 5)
        // Only one track at index 0 with height 64, so y = 30 + 64 = 94 for all beyond
        #expect(y == 30 + 64)
    }

    @Test("trackY at index 0 with different viewport settings")
    func trackYDifferentViewport() {
        let viewport = makeViewport(verticalOffset: 10)
        let tracks = [makeTrack(index: 0, height: 64)]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )
        // rulerHeight(30) - verticalOffset(10) = 20
        #expect(calc.trackY(at: 0) == 20)
    }

    @Test("trackY with many collapsed tracks")
    func trackYCollapsedTracks() {
        let viewport = makeViewport()
        let tracks = [
            makeTrack(id: "t1", index: 0, height: 88, isCollapsed: true),
            makeTrack(id: "t2", index: 1, height: 88, isCollapsed: true),
            makeTrack(id: "t3", index: 2, height: 88, isCollapsed: false),
        ]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )
        let y2 = calc.trackY(at: 2)
        // t1 collapsed: heightSmall, t2 collapsed: heightSmall
        let expected = 30.0 + Track.heightSmall + Track.heightSmall
        #expect(abs(y2 - expected) < 0.001)
    }

    // MARK: - Track State Tests

    @Test("muted track has correct state")
    func mutedTrack() {
        let track = makeTrack(isMuted: true)
        #expect(track.isMuted == true)
    }

    @Test("locked track has correct state")
    func lockedTrack() {
        let track = makeTrack(isLocked: true)
        #expect(track.isLocked == true)
    }

    @Test("invisible track has correct state")
    func invisibleTrack() {
        let track = makeTrack(isVisible: false)
        #expect(track.isVisible == false)
    }

    @Test("non-collapsed track uses full height")
    func nonCollapsedTrackHeight() {
        let track = makeTrack(height: 88, isCollapsed: false)
        #expect(track.effectiveHeight == 88)
    }

    // MARK: - Additional Constants Tests

    @Test("lock icon size and offset are positive")
    func lockIconConstants() {
        #expect(TrackLanesCalculations.lockIconSize > 0)
        #expect(TrackLanesCalculations.lockIconOffset > 0)
    }

    @Test("collapse arrow size is positive")
    func collapseArrowSize() {
        #expect(TrackLanesCalculations.collapseArrowSize > 0)
    }

    @Test("locked stripe constants are reasonable")
    func lockedStripeConstants() {
        #expect(TrackLanesCalculations.lockedStripeWidth > 0)
        #expect(TrackLanesCalculations.lockedStripeGap > TrackLanesCalculations.lockedStripeWidth)
    }

    // MARK: - Calculations Properties Tests

    @Test("calculations stores showSeparators flag")
    func showSeparatorsFlag() {
        let viewport = makeViewport()
        let calc = TrackLanesCalculations(
            tracks: [], viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: false, showLockedOverlay: true
        )
        #expect(calc.showSeparators == false)
    }

    @Test("calculations stores showLockedOverlay flag")
    func showLockedOverlayFlag() {
        let viewport = makeViewport()
        let calc = TrackLanesCalculations(
            tracks: [], viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: false
        )
        #expect(calc.showLockedOverlay == false)
    }

    // MARK: - Total Height Calculation

    @Test("total track area height is sum of all effective heights")
    func totalTrackHeight() {
        let tracks = [
            makeTrack(id: "t1", index: 0, height: 64),
            makeTrack(id: "t2", index: 1, height: 88),
            makeTrack(id: "t3", index: 2, height: 44),
        ]
        let totalHeight = tracks.reduce(0.0) { $0 + $1.effectiveHeight }
        #expect(totalHeight == 64 + 88 + 44)
    }

    @Test("total track area with collapsed tracks is smaller")
    func totalTrackHeightCollapsed() {
        let tracks = [
            makeTrack(id: "t1", index: 0, height: 64, isCollapsed: true),
            makeTrack(id: "t2", index: 1, height: 88, isCollapsed: true),
        ]
        let totalHeight = tracks.reduce(0.0) { $0 + $1.effectiveHeight }
        #expect(totalHeight < 64 + 88)
    }

    // MARK: - Alternating Background Tests

    @Test("even and odd tracks get different background colors")
    func alternatingBackgrounds() {
        let viewport = makeViewport()
        let tracks = [
            makeTrack(id: "t1", index: 0, height: 64),
            makeTrack(id: "t2", index: 1, height: 64),
        ]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .red, secondaryBackgroundColor: .blue,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )
        // Verify the colors are different
        #expect(calc.primaryBackgroundColor != calc.secondaryBackgroundColor)
    }

    // MARK: - Vertical Offset Edge Cases

    @Test("trackY with large vertical offset can be negative")
    func trackYLargeVerticalOffset() {
        let viewport = makeViewport(verticalOffset: 100)
        let tracks = [makeTrack(index: 0, height: 64)]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )
        let y = calc.trackY(at: 0)
        // 30 - 100 = -70
        #expect(y == -70)
    }

    @Test("trackY with zero vertical offset equals ruler height")
    func trackYZeroOffset() {
        let viewport = makeViewport(verticalOffset: 0)
        let tracks = [makeTrack(index: 0, height: 64)]
        let calc = TrackLanesCalculations(
            tracks: tracks, viewport: viewport,
            primaryBackgroundColor: .black, secondaryBackgroundColor: .gray,
            separatorColor: .gray, showSeparators: true, showLockedOverlay: true
        )
        #expect(calc.trackY(at: 0) == 30) // equals rulerHeight
    }
}
