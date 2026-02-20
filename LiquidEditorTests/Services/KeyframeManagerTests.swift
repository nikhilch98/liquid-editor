// KeyframeManagerTests.swift
// LiquidEditorTests
//
// Tests for KeyframeManager: add/update/remove keyframes, undo/redo.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("KeyframeManager Tests")
@MainActor
struct KeyframeManagerTests {

    // MARK: - Helpers

    private func makeManager(videoDuration: TimeMicros = 10_000_000) -> KeyframeManager {
        KeyframeManager(videoDurationMicros: videoDuration)
    }

    private func makeKeyframe(
        id: String = "kf_\(UUID().uuidString.prefix(8))",
        at micros: TimeMicros,
        scale: Double = 1.0,
        interpolation: InterpolationType = .easeInOut
    ) -> Keyframe {
        Keyframe(
            id: id,
            timestampMicros: micros,
            transform: VideoTransform(scale: scale),
            interpolation: interpolation
        )
    }

    // MARK: - Add

    @Test("Add keyframe increases count")
    func addKeyframe() {
        let manager = makeManager()
        let kf = makeKeyframe(at: 1_000_000)
        manager.addKeyframe(kf)

        #expect(manager.keyframeCount == 1)
        #expect(manager.selectedKeyframeId == kf.id)
    }

    @Test("Add keyframe at same timestamp replaces existing")
    func addKeyframeReplacesNearby() {
        let manager = makeManager()
        let kf1 = makeKeyframe(id: "kf_1", at: 1_000_000, scale: 1.5)
        let kf2 = makeKeyframe(id: "kf_2", at: 1_020_000, scale: 2.0) // Within 50ms tolerance

        manager.addKeyframe(kf1)
        manager.addKeyframe(kf2)

        #expect(manager.keyframeCount == 1) // kf1 was replaced
        #expect(manager.selectedKeyframeId == "kf_2")
    }

    // MARK: - Remove

    @Test("Remove keyframe decreases count")
    func removeKeyframe() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000)
        manager.addKeyframe(kf)
        manager.removeKeyframe("kf_1")

        #expect(manager.keyframeCount == 0)
        #expect(manager.selectedKeyframeId == nil)
    }

    // MARK: - Update

    @Test("Update keyframe preserves count")
    func updateKeyframe() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000, scale: 1.0)
        manager.addKeyframe(kf)

        let updated = kf.with(transform: VideoTransform(scale: 2.5))
        manager.updateKeyframe(updated)

        #expect(manager.keyframeCount == 1)
        #expect(manager.keyframes.first?.transform.scale == 2.5)
    }

    // MARK: - Move

    @Test("Move keyframe changes timestamp")
    func moveKeyframe() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000)
        manager.addKeyframe(kf)

        manager.moveKeyframe("kf_1", to: 5_000_000)
        #expect(manager.keyframes.first?.timestampMicros == 5_000_000)
    }

    // MARK: - Interpolation

    @Test("Set interpolation type")
    func setInterpolation() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000, interpolation: .linear)
        manager.addKeyframe(kf)

        manager.setInterpolation("kf_1", type: .cubicInOut)
        #expect(manager.keyframes.first?.interpolation == .cubicInOut)
    }

    @Test("Set bezier points")
    func setBezierPoints() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000)
        manager.addKeyframe(kf)

        let points = BezierControlPoints()
        manager.setBezierPoints("kf_1", points: points)

        let result = manager.keyframes.first!
        #expect(result.interpolation == .bezier)
        #expect(result.bezierPoints != nil)
    }

    // MARK: - Clear

    @Test("Clear all keyframes")
    func clearAll() {
        let manager = makeManager()
        manager.addKeyframe(makeKeyframe(at: 1_000_000))
        manager.addKeyframe(makeKeyframe(at: 2_000_000))
        manager.addKeyframe(makeKeyframe(at: 3_000_000))

        manager.clearAllKeyframes()
        #expect(manager.keyframeCount == 0)
        #expect(manager.selectedKeyframeId == nil)
    }

    // MARK: - Selection

    @Test("Select keyframe near timestamp")
    func selectNear() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000)
        manager.addKeyframe(kf)

        manager.clearSelection()
        #expect(manager.selectedKeyframeId == nil)

        manager.selectKeyframe(near: 1_050_000) // Within default tolerance
        #expect(manager.selectedKeyframeId == "kf_1")
    }

    // MARK: - Query

    @Test("Has keyframe at timestamp")
    func hasKeyframe() {
        let manager = makeManager()
        manager.addKeyframe(makeKeyframe(at: 1_000_000))

        #expect(manager.hasKeyframe(at: 1_020_000)) // Within tolerance
        #expect(!manager.hasKeyframe(at: 5_000_000))
    }

    @Test("Transform interpolation with two keyframes")
    func transformInterpolation() {
        let manager = makeManager()

        let kf1 = Keyframe(
            id: "kf_1",
            timestampMicros: 0,
            transform: VideoTransform(scale: 1.0),
            interpolation: .linear
        )
        let kf2 = Keyframe(
            id: "kf_2",
            timestampMicros: 1_000_000,
            transform: VideoTransform(scale: 2.0),
            interpolation: .linear
        )
        manager.addKeyframe(kf1)
        manager.addKeyframe(kf2)

        let midTransform = manager.transform(at: 500_000)
        // Linear interpolation at midpoint should be ~1.5
        #expect(abs(midTransform.scale - 1.5) < 0.01)
    }

    // MARK: - Undo/Redo

    @Test("Undo restores previous state")
    func undo() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000)
        manager.addKeyframe(kf)
        #expect(manager.keyframeCount == 1)

        let timestamp = manager.undo()
        #expect(manager.keyframeCount == 0)
        #expect(timestamp == 1_000_000)
    }

    @Test("Redo re-applies operation")
    func redo() {
        let manager = makeManager()
        let kf = makeKeyframe(id: "kf_1", at: 1_000_000)
        manager.addKeyframe(kf)
        manager.undo()
        #expect(manager.keyframeCount == 0)

        let timestamp = manager.redo()
        #expect(manager.keyframeCount == 1)
        #expect(timestamp == 1_000_000)
    }

    @Test("Multiple undo/redo cycles")
    func multipleUndoRedo() {
        let manager = makeManager()

        manager.addKeyframe(makeKeyframe(at: 1_000_000))
        manager.addKeyframe(makeKeyframe(at: 2_000_000))
        manager.addKeyframe(makeKeyframe(at: 3_000_000))
        #expect(manager.keyframeCount == 3)

        manager.undo()
        #expect(manager.keyframeCount == 2)

        manager.undo()
        #expect(manager.keyframeCount == 1)

        manager.redo()
        #expect(manager.keyframeCount == 2)

        manager.redo()
        #expect(manager.keyframeCount == 3)
    }

    @Test("New operation clears redo stack")
    func newOperationClearsRedo() {
        let manager = makeManager()
        manager.addKeyframe(makeKeyframe(at: 1_000_000))
        manager.undo()
        #expect(manager.canRedo)

        manager.addKeyframe(makeKeyframe(at: 2_000_000))
        #expect(!manager.canRedo)
    }

    @Test("Clear history empties stacks")
    func clearHistory() {
        let manager = makeManager()
        manager.addKeyframe(makeKeyframe(at: 1_000_000))
        manager.addKeyframe(makeKeyframe(at: 2_000_000))
        manager.undo()

        manager.clearHistory()
        #expect(!manager.canUndo)
        #expect(!manager.canRedo)
    }

    // MARK: - Serialization

    @Test("Export and import timeline")
    func exportImport() {
        let manager = makeManager()
        manager.addKeyframe(makeKeyframe(at: 1_000_000))
        manager.addKeyframe(makeKeyframe(at: 2_000_000))

        let exported = manager.exportTimeline()
        #expect(exported.keyframes.count == 2)

        let manager2 = makeManager()
        manager2.importTimeline(exported)
        #expect(manager2.keyframeCount == 2)
    }
}
