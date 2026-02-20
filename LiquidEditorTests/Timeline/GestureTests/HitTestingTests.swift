import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("TimelineHitTester Tests")
struct HitTestingTests {

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

    private func makeClip(
        id: String = "clip1",
        trackId: String = "track1",
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

    private func makeMarker(
        id: String = "marker1",
        time: TimeMicros = 500_000
    ) -> TimelineMarker {
        TimelineMarker.point(id: id, time: time, label: "Test Marker")
    }

    private func makeTester(
        clips: [TimelineClip] = [],
        markers: [TimelineMarker] = [],
        viewport: ViewportState? = nil,
        playheadPosition: TimeMicros = 0,
        trackHeights: [String: CGFloat] = ["track1": 64],
        trackYPositions: [String: CGFloat] = ["track1": 30],
        playheadActive: Bool = false
    ) -> TimelineHitTester {
        TimelineHitTester(
            clips: clips,
            markers: markers,
            viewport: viewport ?? makeViewport(),
            playheadPosition: playheadPosition,
            trackHeights: trackHeights,
            trackYPositions: trackYPositions,
            playheadActive: playheadActive
        )
    }

    // MARK: - HitTestType Tests

    @Test("HitTestType equality")
    func hitTestTypeEquality() {
        #expect(HitTestType.playhead == HitTestType.playhead)
        #expect(HitTestType.clip != HitTestType.marker)
    }

    // MARK: - HitTestResult Tests

    @Test("empty result has correct type")
    func emptyResultType() {
        let result = HitTestResult.empty(hitTime: 0, hitPosition: .zero)
        #expect(result.type == .empty)
        #expect(!result.hasHit)
        #expect(!result.isPlayhead)
        #expect(!result.isClip)
        #expect(!result.isTrimHandle)
    }

    @Test("clip result has correct properties")
    func clipResultProperties() {
        let result = HitTestResult(
            type: .clip,
            elementId: "clip1",
            trackId: "track1",
            hitTime: 500_000,
            hitPosition: CGPoint(x: 100, y: 50)
        )
        #expect(result.hasHit)
        #expect(result.isClip)
        #expect(!result.isPlayhead)
        #expect(!result.isTrimHandle)
        #expect(result.elementId == "clip1")
    }

    @Test("trim handle result detection")
    func trimHandleResult() {
        let leftResult = HitTestResult(type: .trimHandleLeft, hitTime: 0, hitPosition: .zero)
        let rightResult = HitTestResult(type: .trimHandleRight, hitTime: 0, hitPosition: .zero)

        #expect(leftResult.isTrimHandle)
        #expect(rightResult.isTrimHandle)
        #expect(!leftResult.isClip)
    }

    @Test("result equality ignores distanceFromCenter")
    func resultEquality() {
        let a = HitTestResult(type: .clip, elementId: "c1", hitTime: 100, hitPosition: .zero, distanceFromCenter: 5)
        let b = HitTestResult(type: .clip, elementId: "c1", hitTime: 100, hitPosition: .zero, distanceFromCenter: 20)
        #expect(a == b)
    }

    // MARK: - Hit Test Priority Tests

    @Test("empty timeline returns empty result")
    func emptyTimeline() {
        let tester = makeTester()
        let result = tester.hitTest(CGPoint(x: 200, y: 100))
        #expect(result.type == .empty)
    }

    @Test("playhead has highest priority")
    func playheadPriority() {
        let vp = makeViewport()
        // Playhead at time 0 => x = 80 (track header width)
        let clip = makeClip(startTime: 0, duration: 2_000_000)
        let tester = makeTester(
            clips: [clip],
            playheadPosition: 0,
            trackHeights: ["track1": 64],
            trackYPositions: ["track1": 30]
        )

        // Hit at playhead X position (80), within clip area
        let result = tester.hitTest(CGPoint(x: 80, y: 60))
        #expect(result.type == .playhead)
    }

    @Test("ruler area detection")
    func rulerArea() {
        let tester = makeTester()
        // y=15 is within ruler (height=30)
        let result = tester.hitTest(CGPoint(x: 200, y: 15))
        #expect(result.type == .ruler)
    }

    @Test("clip hit detection")
    func clipHitDetection() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let tester = makeTester(clips: [clip])

        // Clip starts at x=80, ends at x=80+100=180 (1_000_000/10000=100 pixels)
        // Track starts at y=30, height=64, so y range is 30-94
        let result = tester.hitTest(CGPoint(x: 130, y: 60))
        #expect(result.type == .clip)
        #expect(result.elementId == "clip1")
    }

    @Test("trim handle left detection near clip edge")
    func trimHandleLeftDetection() {
        let clip = makeClip(startTime: 1_000_000, duration: 2_000_000)
        let tester = makeTester(clips: [clip])

        // Clip left edge at x = 80 + 1_000_000/10000 = 80 + 100 = 180
        // Trim handle touch target is 20px, so 170-190 area
        let result = tester.hitTest(CGPoint(x: 180, y: 60))
        #expect(result.type == .trimHandleLeft)
        #expect(result.elementId == "clip1")
    }

    @Test("trim handle right detection near clip edge")
    func trimHandleRightDetection() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let tester = makeTester(clips: [clip])

        // Clip right edge at x = 80 + 1_000_000/10000 = 80 + 100 = 180
        let result = tester.hitTest(CGPoint(x: 180, y: 60))
        #expect(result.type == .trimHandleRight)
        #expect(result.elementId == "clip1")
    }

    @Test("marker hit detection")
    func markerHitDetection() {
        let marker = makeMarker(time: 500_000)
        let tester = makeTester(markers: [marker])

        // Marker at x = 80 + 500_000/10000 = 80 + 50 = 130
        // Markers only detected near ruler area (y < rulerHeight * 1.5 = 45)
        // y must be >= rulerHeight (30) to avoid returning .ruler result
        let result = tester.hitTest(CGPoint(x: 130, y: 35))
        #expect(result.type == .marker)
        #expect(result.elementId == "marker1")
    }

    @Test("marker not detected far from ruler")
    func markerNotDetectedFarFromRuler() {
        let marker = makeMarker(time: 500_000)
        let tester = makeTester(markers: [marker])

        // y=100 is far below ruler area
        let result = tester.hitTest(CGPoint(x: 130, y: 100))
        #expect(result.type == .empty)
    }

    @Test("playhead active increases touch target")
    func playheadActiveTouchTarget() {
        let tester = makeTester(playheadPosition: 1_000_000, playheadActive: true)
        // Playhead at x = 80 + 100 = 180
        // Active playhead has 1.5x touch target = 36px, so +/- 18px
        let result = tester.hitTest(CGPoint(x: 197, y: 60))
        #expect(result.type == .playhead)
    }

    @Test("playhead not hit when inactive at same distance")
    func playheadNotHitInactive() {
        let tester = makeTester(playheadPosition: 1_000_000, playheadActive: false)
        // Normal touch target = 24px, so +/- 12px
        // 180 + 17 = 197 is outside normal range
        let result = tester.hitTest(CGPoint(x: 197, y: 60))
        #expect(result.type != .playhead)
    }

    // MARK: - findClipsInRect Tests

    @Test("findClipsInRect returns matching clips")
    func findClipsInRect() {
        let clip1 = makeClip(id: "c1", startTime: 0, duration: 500_000)
        let clip2 = makeClip(id: "c2", startTime: 1_000_000, duration: 500_000)
        let tester = makeTester(clips: [clip1, clip2])

        // Rect covering first clip area
        let rect = CGRect(x: 80, y: 30, width: 50, height: 64)
        let found = tester.findClipsInRect(rect)
        #expect(found.count == 1)
        #expect(found[0].id == "c1")
    }

    @Test("findClipsInRect returns empty for no overlap")
    func findClipsInRectEmpty() {
        let clip = makeClip(startTime: 0, duration: 500_000)
        let tester = makeTester(clips: [clip])

        let rect = CGRect(x: 300, y: 30, width: 50, height: 64)
        let found = tester.findClipsInRect(rect)
        #expect(found.isEmpty)
    }

    // MARK: - findMarkersInRect Tests

    @Test("findMarkersInRect returns matching markers")
    func findMarkersInRect() {
        let marker = makeMarker(time: 500_000)
        let tester = makeTester(markers: [marker])

        // Marker at x=130, ruler area
        let rect = CGRect(x: 120, y: 0, width: 20, height: 30)
        let found = tester.findMarkersInRect(rect)
        #expect(found.count == 1)
        #expect(found[0].id == "marker1")
    }

    // MARK: - Clip with missing track info

    @Test("clip without track info returns nil clipRect")
    func clipWithoutTrackInfo() {
        let clip = makeClip(trackId: "unknownTrack")
        let tester = makeTester(clips: [clip])

        let result = tester.hitTest(CGPoint(x: 100, y: 60))
        #expect(result.type == .empty)
    }
}
