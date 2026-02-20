// MultiSelectManagerTests.swift
// LiquidEditorTests
//
// Tests for MultiSelectManager.

import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("MultiSelectManager")
@MainActor
struct MultiSelectManagerTests {

    // MARK: - Helpers

    private func makeManager() -> MultiSelectManager {
        MultiSelectManager()
    }

    private func makeClip(
        id: String,
        trackId: String = "track-1",
        type: ClipType = .video,
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: type,
            startTime: startTime,
            duration: duration
        )
    }

    // MARK: - Initial State

    @Test("Initial state has no selection")
    func initialState() {
        let manager = makeManager()
        #expect(manager.selectedIds.isEmpty)
        #expect(manager.primaryClipId == nil)
        #expect(manager.selectionCount == 0)
        #expect(manager.hasSelection == false)
        #expect(manager.hasMultiSelection == false)
        #expect(manager.isMultiSelectActive == false)
    }

    // MARK: - Select Clip

    @Test("selectClip selects a single clip")
    func selectClip() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        #expect(manager.selectedIds == ["clip-1"])
        #expect(manager.primaryClipId == "clip-1")
        #expect(manager.selectionCount == 1)
        #expect(manager.hasSelection == true)
        #expect(manager.hasMultiSelection == false)
        #expect(manager.isMultiSelectActive == false)
    }

    @Test("selectClip clears previous selection")
    func selectClipClearsPrevious() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.selectClip("clip-2")
        #expect(manager.selectedIds == ["clip-2"])
        #expect(manager.primaryClipId == "clip-2")
    }

    // MARK: - Toggle Clip

    @Test("toggleClip adds clip to selection")
    func toggleClipAdd() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.toggleClip("clip-2")
        #expect(manager.selectedIds.count == 2)
        #expect(manager.selectedIds.contains("clip-1"))
        #expect(manager.selectedIds.contains("clip-2"))
        #expect(manager.primaryClipId == "clip-2")
        #expect(manager.isMultiSelectActive == true)
    }

    @Test("toggleClip removes clip from selection")
    func toggleClipRemove() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.toggleClip("clip-2")
        manager.toggleClip("clip-1")
        #expect(manager.selectedIds == ["clip-2"])
        #expect(manager.isMultiSelectActive == false)
    }

    @Test("toggleClip updates primary when primary is removed")
    func toggleClipPrimaryUpdate() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.toggleClip("clip-2")
        manager.toggleClip("clip-2")
        #expect(manager.primaryClipId == "clip-1")
    }

    // MARK: - addToSelection / removeFromSelection

    @Test("addToSelection adds clip")
    func addToSelection() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.addToSelection("clip-2")
        #expect(manager.selectedIds.count == 2)
        #expect(manager.primaryClipId == "clip-2")
    }

    @Test("addToSelection is no-op for already selected clip")
    func addToSelectionDuplicate() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.addToSelection("clip-1")
        #expect(manager.selectionCount == 1)
    }

    @Test("removeFromSelection removes clip")
    func removeFromSelection() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.addToSelection("clip-2")
        manager.removeFromSelection("clip-1")
        #expect(manager.selectedIds == ["clip-2"])
    }

    @Test("removeFromSelection is no-op for unselected clip")
    func removeFromSelectionNotFound() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.removeFromSelection("clip-99")
        #expect(manager.selectionCount == 1)
    }

    // MARK: - selectClips

    @Test("selectClips selects multiple clips at once")
    func selectMultiple() {
        let manager = makeManager()
        manager.selectClips(["clip-1", "clip-2", "clip-3"])
        #expect(manager.selectionCount == 3)
        #expect(manager.isMultiSelectActive == true)
    }

    @Test("selectClips with empty set clears selection")
    func selectEmpty() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.selectClips([])
        #expect(manager.hasSelection == false)
        #expect(manager.primaryClipId == nil)
    }

    // MARK: - Select All on Track

    @Test("selectAllOnTrack selects all non-gap clips on track")
    func selectAllOnTrack() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1", trackId: "track-1"),
            makeClip(id: "v2", trackId: "track-1"),
            makeClip(id: "gap-1", trackId: "track-1", type: .gap),
            makeClip(id: "v3", trackId: "track-2"),
        ]
        manager.selectAllOnTrack("track-1", allClips: clips)
        #expect(manager.selectionCount == 2)
        #expect(manager.isSelected("v1"))
        #expect(manager.isSelected("v2"))
        #expect(!manager.isSelected("gap-1"))
        #expect(!manager.isSelected("v3"))
    }

    // MARK: - Select All

    @Test("selectAll selects all non-gap clips")
    func selectAll() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1", trackId: "track-1"),
            makeClip(id: "v2", trackId: "track-2"),
            makeClip(id: "gap-1", trackId: "track-1", type: .gap),
        ]
        manager.selectAll(clips)
        #expect(manager.selectionCount == 2)
        #expect(manager.isSelected("v1"))
        #expect(manager.isSelected("v2"))
        #expect(!manager.isSelected("gap-1"))
    }

    // MARK: - Clear Selection

    @Test("clearSelection removes all selections")
    func clearSelection() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.addToSelection("clip-2")
        manager.clearSelection()
        #expect(manager.hasSelection == false)
        #expect(manager.primaryClipId == nil)
        #expect(manager.isMultiSelectActive == false)
    }

    // MARK: - isSelected

    @Test("isSelected returns correct values")
    func isSelectedCheck() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        #expect(manager.isSelected("clip-1") == true)
        #expect(manager.isSelected("clip-2") == false)
    }

    // MARK: - findClipsInRect

    @Test("findClipsInRect finds intersecting clips")
    func findClipsInRect() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1"),
            makeClip(id: "v2"),
            makeClip(id: "gap-1", type: .gap),
        ]
        let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = manager.findClipsInRect(
            clips,
            marqueeRect: marquee,
            clipRectProvider: { _ in CGRect(x: 10, y: 10, width: 50, height: 50) }
        )
        #expect(result.count == 2) // v1 and v2, not gap
    }

    @Test("findClipsInRect ignores non-overlapping clips")
    func findClipsInRectNoOverlap() {
        let manager = makeManager()
        let clips = [makeClip(id: "v1")]
        let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = manager.findClipsInRect(
            clips,
            marqueeRect: marquee,
            clipRectProvider: { _ in CGRect(x: 200, y: 200, width: 50, height: 50) }
        )
        #expect(result.isEmpty)
    }

    // MARK: - Group Operations

    @Test("getSelectedClips returns matching clips")
    func getSelectedClips() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1"),
            makeClip(id: "v2"),
            makeClip(id: "v3"),
        ]
        manager.selectClips(["v1", "v3"])
        let selected = manager.getSelectedClips(clips)
        #expect(selected.count == 2)
        #expect(selected.map(\.id).contains("v1"))
        #expect(selected.map(\.id).contains("v3"))
    }

    @Test("calculateGroupMove computes correct positions")
    func calculateGroupMove() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1", startTime: 1_000_000),
            makeClip(id: "v2", startTime: 3_000_000),
        ]
        manager.selectClips(["v1", "v2"])
        let moves = manager.calculateGroupMove(delta: 500_000, allClips: clips)
        #expect(moves["v1"] == 1_500_000)
        #expect(moves["v2"] == 3_500_000)
    }

    @Test("calculateGroupMove clamps to zero")
    func calculateGroupMoveClamped() {
        let manager = makeManager()
        let clips = [makeClip(id: "v1", startTime: 500_000)]
        manager.selectClip("v1")
        let moves = manager.calculateGroupMove(delta: -1_000_000, allClips: clips)
        #expect(moves["v1"] == 0)
    }

    // MARK: - validateGroupDelete

    @Test("validateGroupDelete returns failure for empty selection")
    func validateGroupDeleteEmpty() {
        let manager = makeManager()
        let result = manager.validateGroupDelete([])
        #expect(result.success == false)
        #expect(result.error != nil)
    }

    @Test("validateGroupDelete includes linked clips")
    func validateGroupDeleteLinked() {
        let manager = makeManager()
        let clips = [
            TimelineClip(id: "v1", trackId: "t1", type: .video, startTime: 0, duration: 1_000_000, linkedClipId: "a1"),
            TimelineClip(id: "a1", trackId: "t2", type: .audio, startTime: 0, duration: 1_000_000, linkedClipId: "v1"),
        ]
        manager.selectClip("v1")
        let result = manager.validateGroupDelete(clips)
        #expect(result.success == true)
        #expect(result.affectedClipIds.contains("v1"))
        #expect(result.affectedClipIds.contains("a1"))
    }

    // MARK: - getSelectionTimeRange

    @Test("getSelectionTimeRange returns correct range")
    func selectionTimeRange() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1", startTime: 1_000_000, duration: 2_000_000),
            makeClip(id: "v2", startTime: 5_000_000, duration: 1_000_000),
        ]
        manager.selectClips(["v1", "v2"])
        let range = manager.getSelectionTimeRange(clips)
        #expect(range != nil)
        #expect(range?.start == 1_000_000)
        #expect(range?.end == 6_000_000)
    }

    @Test("getSelectionTimeRange returns nil for empty selection")
    func selectionTimeRangeEmpty() {
        let manager = makeManager()
        let range = manager.getSelectionTimeRange([])
        #expect(range == nil)
    }

    // MARK: - toSelectionState

    @Test("toSelectionState produces correct SelectionState")
    func toSelectionState() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.addToSelection("clip-2")

        let state = manager.toSelectionState()
        #expect(state.selectedClipIds.count == 2)
        #expect(state.selectedClipIds.contains("clip-1"))
        #expect(state.selectedClipIds.contains("clip-2"))
        #expect(state.mode == .normal)
    }

    // MARK: - Additional Toggle Edge Cases

    @Test("toggleClip on empty selection adds first clip")
    func toggleClipEmpty() {
        let manager = makeManager()
        manager.toggleClip("clip-1")
        #expect(manager.selectionCount == 1)
        #expect(manager.primaryClipId == "clip-1")
        #expect(manager.isMultiSelectActive == false)
    }

    @Test("toggleClip removing last clip clears primaryClipId")
    func toggleClipRemoveLast() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.toggleClip("clip-1")
        #expect(manager.selectedIds.isEmpty)
        #expect(manager.primaryClipId == nil)
        #expect(manager.isMultiSelectActive == false)
    }

    // MARK: - removeFromSelection Updates Primary

    @Test("removeFromSelection updates primary when primary removed")
    func removeFromSelectionPrimaryUpdate() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.addToSelection("clip-2")
        manager.addToSelection("clip-3")
        // Primary is clip-3 (most recently added)
        #expect(manager.primaryClipId == "clip-3")
        manager.removeFromSelection("clip-3")
        // Primary should be reassigned
        #expect(manager.primaryClipId != nil)
        #expect(manager.primaryClipId != "clip-3")
    }

    @Test("removeFromSelection keeps primary when non-primary removed")
    func removeFromSelectionKeepsPrimary() {
        let manager = makeManager()
        manager.selectClip("clip-1")
        manager.addToSelection("clip-2")
        // Primary is clip-2
        manager.removeFromSelection("clip-1")
        #expect(manager.primaryClipId == "clip-2")
    }

    // MARK: - selectAllOnTrack Edge Cases

    @Test("selectAllOnTrack with empty matching track")
    func selectAllOnTrackEmpty() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1", trackId: "track-2"),
        ]
        manager.selectAllOnTrack("track-1", allClips: clips)
        #expect(manager.hasSelection == false)
        #expect(manager.primaryClipId == nil)
    }

    @Test("selectAllOnTrack ignores gap clips")
    func selectAllOnTrackIgnoresGaps() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "gap-1", trackId: "track-1", type: .gap),
            makeClip(id: "gap-2", trackId: "track-1", type: .gap),
        ]
        manager.selectAllOnTrack("track-1", allClips: clips)
        #expect(manager.hasSelection == false)
    }

    // MARK: - selectAll Edge Cases

    @Test("selectAll with only gap clips selects nothing")
    func selectAllOnlyGaps() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "gap-1", type: .gap),
            makeClip(id: "gap-2", type: .gap),
        ]
        manager.selectAll(clips)
        #expect(manager.hasSelection == false)
    }

    @Test("selectAll with empty array")
    func selectAllEmpty() {
        let manager = makeManager()
        manager.selectAll([])
        #expect(manager.hasSelection == false)
        #expect(manager.primaryClipId == nil)
    }

    // MARK: - calculateGroupMove Edge Cases

    @Test("calculateGroupMove only moves selected clips")
    func calculateGroupMoveSelective() {
        let manager = makeManager()
        let clips = [
            makeClip(id: "v1", startTime: 1_000_000),
            makeClip(id: "v2", startTime: 3_000_000),
            makeClip(id: "v3", startTime: 5_000_000),
        ]
        manager.selectClips(["v1", "v3"])
        let moves = manager.calculateGroupMove(delta: 100_000, allClips: clips)
        #expect(moves.count == 2)
        #expect(moves["v1"] == 1_100_000)
        #expect(moves["v3"] == 5_100_000)
        #expect(moves["v2"] == nil) // Not selected
    }

    @Test("calculateGroupMove with zero delta")
    func calculateGroupMoveZeroDelta() {
        let manager = makeManager()
        let clips = [makeClip(id: "v1", startTime: 1_000_000)]
        manager.selectClip("v1")
        let moves = manager.calculateGroupMove(delta: 0, allClips: clips)
        #expect(moves["v1"] == 1_000_000) // Unchanged
    }

    // MARK: - validateGroupDelete Edge Cases

    @Test("validateGroupDelete with single non-linked clip")
    func validateGroupDeleteSingle() {
        let manager = makeManager()
        let clips = [makeClip(id: "v1")]
        manager.selectClip("v1")
        let result = manager.validateGroupDelete(clips)
        #expect(result.success == true)
        #expect(result.affectedClipIds == ["v1"])
        #expect(result.operationName == "Delete 1 clip")
    }

    @Test("validateGroupDelete with multiple clips uses plural")
    func validateGroupDeletePlural() {
        let manager = makeManager()
        let clips = [makeClip(id: "v1"), makeClip(id: "v2")]
        manager.selectClips(["v1", "v2"])
        let result = manager.validateGroupDelete(clips)
        #expect(result.success == true)
        #expect(result.operationName == "Delete 2 clips")
    }

    // MARK: - getSelectionTimeRange Edge Cases

    @Test("getSelectionTimeRange with single clip")
    func selectionTimeRangeSingleClip() {
        let manager = makeManager()
        let clips = [makeClip(id: "v1", startTime: 2_000_000, duration: 1_000_000)]
        manager.selectClip("v1")
        let range = manager.getSelectionTimeRange(clips)
        #expect(range?.start == 2_000_000)
        #expect(range?.end == 3_000_000)
    }

    @Test("getSelectionTimeRange with selected ID not in clip list")
    func selectionTimeRangeMissingClip() {
        let manager = makeManager()
        manager.selectClip("nonexistent")
        let range = manager.getSelectionTimeRange([])
        #expect(range == nil)
    }

    // MARK: - findClipsInRect Edge Cases

    @Test("findClipsInRect with zero-size marquee")
    func findClipsInRectZeroSize() {
        let manager = makeManager()
        let clips = [makeClip(id: "v1")]
        // Zero-size rect at (50,50) is a point inside clip rect (10,10)-(60,60), so CGRect.intersects returns true
        let marquee = CGRect(x: 50, y: 50, width: 0, height: 0)
        let result = manager.findClipsInRect(
            clips, marqueeRect: marquee,
            clipRectProvider: { _ in CGRect(x: 10, y: 10, width: 50, height: 50) }
        )
        #expect(result.count == 1)
    }

    @Test("findClipsInRect with empty clips list")
    func findClipsInRectEmptyClips() {
        let manager = makeManager()
        let marquee = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = manager.findClipsInRect(
            [], marqueeRect: marquee,
            clipRectProvider: { _ in .zero }
        )
        #expect(result.isEmpty)
    }

    // MARK: - GroupOperationResult

    @Test("GroupOperationResult.success factory")
    func groupOperationSuccess() {
        let result = GroupOperationResult.success(
            affectedClipIds: ["a", "b"],
            operationName: "Test Op"
        )
        #expect(result.success == true)
        #expect(result.affectedClipIds.count == 2)
        #expect(result.error == nil)
    }

    @Test("GroupOperationResult.failure factory")
    func groupOperationFailure() {
        let result = GroupOperationResult.failure(
            operationName: "Test",
            error: "Something failed"
        )
        #expect(result.success == false)
        #expect(result.affectedClipIds.isEmpty)
        #expect(result.error == "Something failed")
    }

    // MARK: - toSelectionState includes primary

    @Test("toSelectionState includes primary clip ID")
    func toSelectionStateWithPrimary() {
        let manager = makeManager()
        manager.selectClip("clip-A")
        let state = manager.toSelectionState()
        #expect(state.primaryClipId == "clip-A")
    }

    @Test("toSelectionState with no selection")
    func toSelectionStateEmpty() {
        let manager = makeManager()
        let state = manager.toSelectionState()
        #expect(state.selectedClipIds.isEmpty)
        #expect(state.primaryClipId == nil)
    }
}
