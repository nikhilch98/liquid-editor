import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - SelectionMode Tests

@Suite("SelectionMode Tests")
struct SelectionModeTests {

    @Test("all cases")
    func allCases() {
        #expect(SelectionMode.allCases.count == 8)
        #expect(SelectionMode.normal.rawValue == "normal")
        #expect(SelectionMode.range.rawValue == "range")
        #expect(SelectionMode.trimHead.rawValue == "trimHead")
        #expect(SelectionMode.trimTail.rawValue == "trimTail")
        #expect(SelectionMode.slip.rawValue == "slip")
        #expect(SelectionMode.slide.rawValue == "slide")
        #expect(SelectionMode.roll.rawValue == "roll")
        #expect(SelectionMode.marquee.rawValue == "marquee")
    }
}

// MARK: - SelectionState Tests

@Suite("SelectionState Tests")
struct SelectionStateTests {

    // MARK: - Empty State

    @Test("empty state")
    func emptyState() {
        let state = SelectionState.empty
        #expect(!state.hasSelection)
        #expect(!state.hasMultiSelection)
        #expect(!state.hasRange)
        #expect(state.selectionCount == 0)
        #expect(state.mode == .normal)
        #expect(state.primaryClipId == nil)
        #expect(state.selectedMarkerId == nil)
        #expect(state.selectedTransitionId == nil)
        #expect(state.selectedKeyframeId == nil)
        #expect(state.inPoint == nil)
        #expect(state.outPoint == nil)
        #expect(!state.isTrimming)
        #expect(!state.isMarqueeSelecting)
    }

    // MARK: - Clip Selection

    @Test("selectClip")
    func selectClip() {
        let state = SelectionState.empty.selectClip("clip-1")
        #expect(state.hasSelection)
        #expect(!state.hasMultiSelection)
        #expect(state.selectionCount == 1)
        #expect(state.isClipSelected("clip-1"))
        #expect(state.isPrimaryClip("clip-1"))
        #expect(state.mode == .normal)
    }

    @Test("addClipToSelection")
    func addClipToSelection() {
        let state = SelectionState.empty
            .selectClip("clip-1")
            .addClipToSelection("clip-2")
        #expect(state.hasMultiSelection)
        #expect(state.selectionCount == 2)
        #expect(state.isClipSelected("clip-1"))
        #expect(state.isClipSelected("clip-2"))
        #expect(state.isPrimaryClip("clip-2"))
    }

    @Test("removeClipFromSelection")
    func removeClipFromSelection() {
        let state = SelectionState.empty
            .selectClip("clip-1")
            .addClipToSelection("clip-2")
            .removeClipFromSelection("clip-1")
        #expect(state.selectionCount == 1)
        #expect(!state.isClipSelected("clip-1"))
        #expect(state.isClipSelected("clip-2"))
    }

    @Test("removeClipFromSelection updates primary")
    func removeUpdatesPrimary() {
        let state = SelectionState.empty
            .selectClip("clip-1")
            .addClipToSelection("clip-2")
            .removeClipFromSelection("clip-2")
        #expect(state.primaryClipId == "clip-1")
    }

    @Test("removeClipFromSelection primary when empty")
    func removePrimaryWhenEmpty() {
        let state = SelectionState.empty
            .selectClip("clip-1")
            .removeClipFromSelection("clip-1")
        #expect(state.primaryClipId == nil)
        #expect(!state.hasSelection)
    }

    @Test("toggleClipSelection adds if not selected")
    func toggleAdds() {
        let state = SelectionState.empty.toggleClipSelection("clip-1")
        #expect(state.isClipSelected("clip-1"))
    }

    @Test("toggleClipSelection removes if selected")
    func toggleRemoves() {
        let state = SelectionState.empty
            .selectClip("clip-1")
            .toggleClipSelection("clip-1")
        #expect(!state.isClipSelected("clip-1"))
    }

    @Test("selectClips multiple")
    func selectClips() {
        let state = SelectionState.empty.selectClips(["a", "b", "c"], primaryId: "b")
        #expect(state.selectionCount == 3)
        #expect(state.isPrimaryClip("b"))
    }

    @Test("clearClipSelection")
    func clearClipSelection() {
        let state = SelectionState.empty
            .selectClip("clip-1")
            .addClipToSelection("clip-2")
            .clearClipSelection()
        #expect(!state.hasSelection)
        #expect(state.primaryClipId == nil)
    }

    // MARK: - Other Selections

    @Test("selectMarker")
    func selectMarker() {
        let state = SelectionState.empty.selectMarker("marker-1")
        #expect(state.isMarkerSelected("marker-1"))
        #expect(!state.isMarkerSelected("other"))
        #expect(!state.hasSelection) // No clips selected
    }

    @Test("selectTransition")
    func selectTransition() {
        let state = SelectionState.empty.selectTransition("trans-1")
        #expect(state.isTransitionSelected("trans-1"))
    }

    @Test("selectKeyframe")
    func selectKeyframe() {
        let state = SelectionState.empty.selectKeyframe("kf-1")
        #expect(state.isKeyframeSelected("kf-1"))
    }

    @Test("clearAll resets everything")
    func clearAll() {
        let state = SelectionState.empty
            .selectClip("clip-1")
            .setInPoint(1_000_000)
            .setOutPoint(5_000_000)
            .clearAll()
        #expect(!state.hasSelection)
        #expect(!state.hasRange)
        #expect(state.mode == .normal)
    }

    // MARK: - Range Selection

    @Test("setInPoint")
    func setInPoint() {
        let state = SelectionState.empty.setInPoint(1_000_000)
        #expect(state.inPoint == 1_000_000)
        #expect(state.mode == .range)
    }

    @Test("setOutPoint")
    func setOutPoint() {
        let state = SelectionState.empty.setOutPoint(5_000_000)
        #expect(state.outPoint == 5_000_000)
        #expect(state.mode == .range)
    }

    @Test("setRange")
    func setRange() {
        let state = SelectionState.empty.setRange(inTime: 1_000_000, outTime: 5_000_000)
        #expect(state.hasRange)
        #expect(state.rangeDuration == 4_000_000)
        #expect(state.rangeAsTimeRange != nil)
        #expect(state.rangeAsTimeRange?.start == 1_000_000)
        #expect(state.rangeAsTimeRange?.end == 5_000_000)
    }

    @Test("clearRange")
    func clearRange() {
        let state = SelectionState.empty
            .setRange(inTime: 1_000_000, outTime: 5_000_000)
            .clearRange()
        #expect(!state.hasRange)
        #expect(state.mode == .normal)
    }

    @Test("rangeDuration returns nil when no range")
    func rangeDurationNil() {
        let state = SelectionState.empty
        #expect(state.rangeDuration == nil)
    }

    // MARK: - Mode Operations

    @Test("enterTrimHeadMode")
    func enterTrimHead() {
        let state = SelectionState.empty.enterTrimHeadMode()
        #expect(state.mode == .trimHead)
        #expect(state.isTrimming)
    }

    @Test("enterTrimTailMode")
    func enterTrimTail() {
        let state = SelectionState.empty.enterTrimTailMode()
        #expect(state.mode == .trimTail)
        #expect(state.isTrimming)
    }

    @Test("enterSlipMode")
    func enterSlip() {
        let state = SelectionState.empty.enterSlipMode()
        #expect(state.mode == .slip)
    }

    @Test("enterSlideMode")
    func enterSlide() {
        let state = SelectionState.empty.enterSlideMode()
        #expect(state.mode == .slide)
    }

    @Test("enterRollMode")
    func enterRoll() {
        let state = SelectionState.empty.enterRollMode()
        #expect(state.mode == .roll)
    }

    @Test("exitSpecialMode returns to normal")
    func exitSpecialMode() {
        let state = SelectionState.empty
            .enterTrimHeadMode()
            .exitSpecialMode()
        #expect(state.mode == .normal)
    }

    // MARK: - Marquee Selection

    @Test("startMarquee")
    func startMarquee() {
        let state = SelectionState.empty.startMarquee(CGPoint(x: 100, y: 100))
        #expect(state.mode == .marquee)
        #expect(state.isMarqueeSelecting)
        #expect(state.marqueeStart == CGPoint(x: 100, y: 100))
        #expect(state.marqueeEnd == CGPoint(x: 100, y: 100))
    }

    @Test("updateMarquee")
    func updateMarquee() {
        let state = SelectionState.empty
            .startMarquee(CGPoint(x: 100, y: 100))
            .updateMarquee(CGPoint(x: 200, y: 200))
        #expect(state.marqueeEnd == CGPoint(x: 200, y: 200))
    }

    @Test("marqueeRect computed property")
    func marqueeRect() {
        let state = SelectionState.empty
            .startMarquee(CGPoint(x: 200, y: 300))
            .updateMarquee(CGPoint(x: 100, y: 100))
        let rect = state.marqueeRect
        #expect(rect != nil)
        #expect(rect!.origin.x == 100) // min x
        #expect(rect!.origin.y == 100) // min y
        #expect(rect!.size.width == 100) // 200 - 100
        #expect(rect!.size.height == 200) // 300 - 100
    }

    @Test("marqueeRect nil when no marquee")
    func marqueeRectNil() {
        #expect(SelectionState.empty.marqueeRect == nil)
    }

    @Test("endMarquee clears marquee")
    func endMarquee() {
        let state = SelectionState.empty
            .startMarquee(CGPoint(x: 100, y: 100))
            .updateMarquee(CGPoint(x: 200, y: 200))
            .endMarquee()
        #expect(state.mode == .normal)
        #expect(state.marqueeStart == nil)
        #expect(state.marqueeEnd == nil)
        #expect(!state.isMarqueeSelecting)
    }

    // MARK: - Codable

    @Test("Codable roundtrip empty state")
    func codableEmpty() throws {
        let state = SelectionState.empty
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SelectionState.self, from: data)
        #expect(decoded == state)
    }

    @Test("Codable roundtrip with selections")
    func codableWithSelections() throws {
        let state = SelectionState(
            selectedClipIds: ["a", "b"],
            primaryClipId: "a",
            selectedMarkerId: "m1",
            inPoint: 1_000_000,
            outPoint: 5_000_000,
            mode: .range
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SelectionState.self, from: data)
        #expect(decoded.selectedClipIds == state.selectedClipIds)
        #expect(decoded.primaryClipId == "a")
        #expect(decoded.selectedMarkerId == "m1")
        #expect(decoded.inPoint == 1_000_000)
        #expect(decoded.outPoint == 5_000_000)
        #expect(decoded.mode == .range)
    }

    @Test("Codable roundtrip with marquee")
    func codableWithMarquee() throws {
        let state = SelectionState(
            mode: .marquee,
            marqueeStart: CGPoint(x: 50, y: 60),
            marqueeEnd: CGPoint(x: 200, y: 300)
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SelectionState.self, from: data)
        #expect(decoded.mode == .marquee)
        #expect(decoded.marqueeStart?.x == 50)
        #expect(decoded.marqueeStart?.y == 60)
        #expect(decoded.marqueeEnd?.x == 200)
        #expect(decoded.marqueeEnd?.y == 300)
    }
}
