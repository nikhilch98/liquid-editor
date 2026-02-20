import Testing
import Foundation
@testable import LiquidEditor

// MARK: - TrimEdge Tests

@Suite("TrimEdge Tests")
struct TrimEdgeTests {

    @Test("All cases exist")
    func allCases() {
        #expect(TrimEdge.allCases.count == 2)
        #expect(TrimEdge.allCases.contains(.left))
        #expect(TrimEdge.allCases.contains(.right))
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for edge in TrimEdge.allCases {
            let data = try JSONEncoder().encode(edge)
            let decoded = try JSONDecoder().decode(TrimEdge.self, from: data)
            #expect(decoded == edge)
        }
    }
}

// MARK: - SnapTargetType Tests

@Suite("SnapTargetType Tests")
struct SnapTargetTypeTests {

    @Test("All cases exist")
    func allCases() {
        #expect(SnapTargetType.allCases.count == 6)
    }
}

// MARK: - SnapGuide Tests

@Suite("SnapGuide Tests")
struct SnapGuideTests {

    @Test("Creation")
    func creation() {
        let guide = SnapGuide(x: 100.0, type: .playhead)
        #expect(guide.x == 100.0)
        #expect(guide.type == .playhead)
    }

    @Test("Equatable")
    func equatable() {
        let a = SnapGuide(x: 50.0, type: .clipEdge)
        let b = SnapGuide(x: 50.0, type: .clipEdge)
        let c = SnapGuide(x: 50.0, type: .marker)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - SnapResult Tests

@Suite("SnapResult Tests")
struct SnapResultTests {

    @Test("Creation")
    func creation() {
        let guides = [SnapGuide(x: 100, type: .playhead)]
        let result = SnapResult(
            adjustedDelta: 500,
            guides: guides,
            snappedToPlayhead: true
        )
        #expect(result.adjustedDelta == 500)
        #expect(result.guides.count == 1)
        #expect(result.snappedToPlayhead == true)
    }

    @Test("Equatable")
    func equatable() {
        let a = SnapResult(adjustedDelta: 100, guides: [], snappedToPlayhead: false)
        let b = SnapResult(adjustedDelta: 100, guides: [], snappedToPlayhead: false)
        #expect(a == b)
    }
}

// MARK: - EditHitTestResult Tests

@Suite("EditHitTestResult Tests")
struct EditHitTestResultTests {

    @Test("Empty factory")
    func emptyFactory() {
        let result = EditHitTestResult.empty
        #expect(result.type == .empty)
        #expect(result.clipId == nil)
        #expect(result.markerId == nil)
        #expect(result.transitionId == nil)
        #expect(result.keyframeId == nil)
        #expect(result.trimEdge == nil)
    }

    @Test("Playhead factory")
    func playheadFactory() {
        let result = EditHitTestResult.playhead
        #expect(result.type == .playhead)
    }

    @Test("Ruler factory")
    func rulerFactory() {
        let result = EditHitTestResult.ruler
        #expect(result.type == .ruler)
    }

    @Test("Clip factory")
    func clipFactory() {
        let result = EditHitTestResult.clip("clip-1")
        #expect(result.type == .clip)
        #expect(result.clipId == "clip-1")
    }

    @Test("TrimHandle factory")
    func trimHandleFactory() {
        let result = EditHitTestResult.trimHandle("clip-2", edge: .left)
        #expect(result.type == .trimHandle)
        #expect(result.clipId == "clip-2")
        #expect(result.trimEdge == .left)
    }

    @Test("TrimHandle right edge")
    func trimHandleRight() {
        let result = EditHitTestResult.trimHandle("clip-3", edge: .right)
        #expect(result.trimEdge == .right)
    }

    @Test("Marker factory")
    func markerFactory() {
        let result = EditHitTestResult.marker("marker-1")
        #expect(result.type == .marker)
        #expect(result.markerId == "marker-1")
    }

    @Test("Transition factory")
    func transitionFactory() {
        let result = EditHitTestResult.transition("trans-1")
        #expect(result.type == .transition)
        #expect(result.transitionId == "trans-1")
    }

    @Test("Keyframe factory")
    func keyframeFactory() {
        let result = EditHitTestResult.keyframe("kf-1")
        #expect(result.type == .keyframe)
        #expect(result.keyframeId == "kf-1")
    }

    @Test("Equatable - same type and ids")
    func equatable() {
        let a = EditHitTestResult.clip("clip-1")
        let b = EditHitTestResult.clip("clip-1")
        #expect(a == b)
    }

    @Test("Equatable - different clips")
    func equatableDifferent() {
        let a = EditHitTestResult.clip("clip-1")
        let b = EditHitTestResult.clip("clip-2")
        #expect(a != b)
    }

    @Test("Equatable - different types")
    func equatableDifferentTypes() {
        let a = EditHitTestResult.empty
        let b = EditHitTestResult.playhead
        #expect(a != b)
    }
}

// MARK: - EditHitType Tests

@Suite("EditHitType Tests")
struct EditHitTypeTests {

    @Test("All cases exist")
    func allCases() {
        #expect(EditHitType.allCases.count == 8)
    }
}

// MARK: - EditTrimPreview Tests

@Suite("EditTrimPreview Tests")
struct EditTrimPreviewTests {

    @Test("Empty factory")
    func emptyFactory() {
        let preview = EditTrimPreview.empty()
        #expect(preview.clipId == "")
        #expect(preview.newStartTime == 0)
        #expect(preview.newDuration == 0)
        #expect(preview.newSourceIn == 0)
        #expect(preview.newSourceOut == 0)
        #expect(preview.snapGuide == nil)
        #expect(preview.trimmedDelta == 0)
        #expect(preview.rippleClips == nil)
    }

    @Test("Creation with values")
    func creation() {
        let preview = EditTrimPreview(
            clipId: "clip-1",
            newStartTime: 1_000_000,
            newDuration: 3_000_000,
            newSourceIn: 500_000,
            newSourceOut: 3_500_000,
            snapGuide: SnapGuide(x: 50, type: .clipEdge),
            trimmedDelta: -200_000,
            rippleClips: nil
        )
        #expect(preview.clipId == "clip-1")
        #expect(preview.newStartTime == 1_000_000)
        #expect(preview.newDuration == 3_000_000)
        #expect(preview.snapGuide?.type == .clipEdge)
    }

    @Test("with() adds ripple clips")
    func withRippleClips() {
        let preview = EditTrimPreview.empty()
        let ripples = [RipplePreview(clipId: "clip-2", newStartTime: 5_000_000)]
        let updated = preview.with(rippleClips: ripples)
        #expect(updated.rippleClips?.count == 1)
        #expect(updated.rippleClips?[0].clipId == "clip-2")
    }
}

// MARK: - RollPreview Tests

@Suite("RollPreview Tests")
struct RollPreviewTests {

    @Test("Empty factory")
    func emptyFactory() {
        let preview = RollPreview.empty()
        #expect(preview.leftClipId == "")
        #expect(preview.rightClipId == "")
        #expect(preview.editPoint == 0)
        #expect(preview.leftNewDuration == 0)
        #expect(preview.rightNewStartTime == 0)
        #expect(preview.rightNewDuration == 0)
    }

    @Test("Creation with values")
    func creation() {
        let preview = RollPreview(
            leftClipId: "clip-1",
            rightClipId: "clip-2",
            editPoint: 5_000_000,
            leftNewDuration: 4_800_000,
            rightNewStartTime: 5_000_000,
            rightNewDuration: 3_200_000
        )
        #expect(preview.leftClipId == "clip-1")
        #expect(preview.editPoint == 5_000_000)
    }
}

// MARK: - SlipPreview Tests

@Suite("SlipPreview Tests")
struct SlipPreviewTests {

    @Test("Empty factory")
    func emptyFactory() {
        let preview = SlipPreview.empty()
        #expect(preview.clipId == "")
        #expect(preview.newSourceIn == 0)
        #expect(preview.newSourceOut == 0)
        #expect(preview.startTime == 0)
        #expect(preview.duration == 0)
    }

    @Test("Creation with values")
    func creation() {
        let preview = SlipPreview(
            clipId: "clip-1",
            newSourceIn: 1_000_000,
            newSourceOut: 4_000_000,
            startTime: 0,
            duration: 3_000_000
        )
        #expect(preview.clipId == "clip-1")
        #expect(preview.newSourceIn == 1_000_000)
        #expect(preview.newSourceOut == 4_000_000)
    }
}

// MARK: - SlidePreview Tests

@Suite("SlidePreview Tests")
struct SlidePreviewTests {

    @Test("Empty factory")
    func emptyFactory() {
        let preview = SlidePreview.empty()
        #expect(preview.clipId == "")
        #expect(preview.newStartTime == 0)
        #expect(preview.leftClipNewDuration == nil)
        #expect(preview.rightClipNewStartTime == nil)
    }

    @Test("Creation with values")
    func creation() {
        let preview = SlidePreview(
            clipId: "clip-1",
            newStartTime: 2_000_000,
            leftClipNewDuration: 1_500_000,
            rightClipNewStartTime: 5_000_000
        )
        #expect(preview.clipId == "clip-1")
        #expect(preview.leftClipNewDuration == 1_500_000)
        #expect(preview.rightClipNewStartTime == 5_000_000)
    }
}

// MARK: - EditDragPreview Tests

@Suite("EditDragPreview Tests")
struct EditDragPreviewTests {

    @Test("Empty factory")
    func emptyFactory() {
        let preview = EditDragPreview.empty
        #expect(preview.clips.isEmpty)
        #expect(preview.snapGuides.isEmpty)
        #expect(preview.isValid == false)
        #expect(preview.errorMessage == nil)
    }

    @Test("Creation with error")
    func creationWithError() {
        let preview = EditDragPreview(
            clips: [],
            snapGuides: [],
            isValid: false,
            errorMessage: "Overlap detected"
        )
        #expect(preview.isValid == false)
        #expect(preview.errorMessage == "Overlap detected")
    }
}

// MARK: - ClipMove Tests

@Suite("ClipMove Tests")
struct ClipMoveTests {

    @Test("Creation")
    func creation() {
        let move = ClipMove(
            clipId: "clip-1",
            newStartTime: 3_000_000,
            newTrackId: "track-2"
        )
        #expect(move.clipId == "clip-1")
        #expect(move.newStartTime == 3_000_000)
        #expect(move.newTrackId == "track-2")
    }
}

// MARK: - RipplePreview Tests

@Suite("RipplePreview Tests")
struct RipplePreviewTests {

    @Test("Creation")
    func creation() {
        let ripple = RipplePreview(clipId: "clip-3", newStartTime: 8_000_000)
        #expect(ripple.clipId == "clip-3")
        #expect(ripple.newStartTime == 8_000_000)
    }

    @Test("Equatable")
    func equatable() {
        let a = RipplePreview(clipId: "c", newStartTime: 100)
        let b = RipplePreview(clipId: "c", newStartTime: 100)
        #expect(a == b)
    }
}
