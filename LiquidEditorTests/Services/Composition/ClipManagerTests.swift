// ClipManagerTests.swift
// LiquidEditorTests
//
// Comprehensive tests for ClipManager: command pattern undo/redo,
// clip operations, selection, queries, and edge cases.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Creates a TimelineClip with minimal boilerplate for testing.
private func makeClip(
    id: String = UUID().uuidString,
    trackId: String = "track1",
    type: ClipType = .video,
    startTime: TimeMicros = 0,
    duration: TimeMicros = 1_000_000,
    mediaAssetId: String? = "asset1",
    label: String? = nil
) -> TimelineClip {
    TimelineClip(
        id: id,
        mediaAssetId: mediaAssetId,
        trackId: trackId,
        type: type,
        startTime: startTime,
        duration: duration,
        sourceIn: 0,
        sourceOut: duration,
        label: label
    )
}

/// Creates a set of sequential clips for testing.
private func makeSequentialClips(count: Int, duration: TimeMicros = 1_000_000) -> [TimelineClip] {
    (0..<count).map { i in
        makeClip(
            id: "clip\(i)",
            startTime: TimeMicros(i) * duration,
            duration: duration
        )
    }
}

// MARK: - ClipManager Initial State Tests

@Suite("ClipManager - Initial State")
@MainActor
struct ClipManagerInitialStateTests {

    @Test("Starts with empty clips")
    func startsEmpty() {
        let manager = ClipManager()
        #expect(manager.clips.isEmpty)
        #expect(manager.totalDuration == 0)
    }

    @Test("Starts with no selection")
    func noInitialSelection() {
        let manager = ClipManager()
        #expect(manager.selectedClipId == nil)
        #expect(manager.selectedClip == nil)
    }

    @Test("Cannot undo initially")
    func cannotUndoInitially() {
        let manager = ClipManager()
        #expect(manager.canUndo == false)
    }

    @Test("Cannot redo initially")
    func cannotRedoInitially() {
        let manager = ClipManager()
        #expect(manager.canRedo == false)
    }
}

// MARK: - loadClips Tests

@Suite("ClipManager - loadClips")
@MainActor
struct ClipManagerLoadClipsTests {

    @Test("Loading clips sets them in the manager")
    func loadClipsSetsClips() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        #expect(manager.clips.count == 3)
    }

    @Test("Loading clips selects the first clip")
    func loadClipsSelectsFirst() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        #expect(manager.selectedClipId == "clip0")
    }

    @Test("Loading clips clears undo/redo stacks")
    func loadClipsClearsHistory() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        // Perform an operation to create undo history
        manager.deleteClip("clip0")
        #expect(manager.canUndo == true)

        // Reload should clear undo
        manager.loadClips(clips)
        #expect(manager.canUndo == false)
        #expect(manager.canRedo == false)
    }

    @Test("Loading empty array results in empty manager")
    func loadEmptyArray() {
        let manager = ClipManager()
        manager.loadClips([])
        #expect(manager.clips.isEmpty)
        #expect(manager.selectedClipId == nil)
    }

    @Test("Clips are sorted by start time")
    func clipsSortedByStartTime() {
        let manager = ClipManager()
        let clip1 = makeClip(id: "a", startTime: 2_000_000)
        let clip2 = makeClip(id: "b", startTime: 0)
        let clip3 = makeClip(id: "c", startTime: 1_000_000)

        manager.loadClips([clip1, clip2, clip3])

        let ids = manager.clips.map(\.id)
        #expect(ids == ["b", "c", "a"])
    }

    @Test("Total duration reflects latest end time")
    func totalDurationReflectsEndTime() {
        let manager = ClipManager()
        let clips = [
            makeClip(id: "a", startTime: 0, duration: 1_000_000),
            makeClip(id: "b", startTime: 1_000_000, duration: 2_000_000),
        ]
        manager.loadClips(clips)

        // Clip b ends at 3_000_000
        #expect(manager.totalDuration == 3_000_000)
    }
}

// MARK: - initializeWithSingleClip Tests

@Suite("ClipManager - initializeWithSingleClip")
@MainActor
struct ClipManagerSingleClipTests {

    @Test("Creates a single video clip")
    func createsSingleClip() {
        let manager = ClipManager()
        manager.initializeWithSingleClip(
            trackId: "track1",
            mediaAssetId: "video1",
            durationMicros: 5_000_000
        )

        #expect(manager.clips.count == 1)
        #expect(manager.clips[0].type == .video)
        #expect(manager.clips[0].mediaAssetId == "video1")
        #expect(manager.clips[0].trackId == "track1")
        #expect(manager.clips[0].duration == 5_000_000)
        #expect(manager.clips[0].startTime == 0)
    }

    @Test("Selects the created clip")
    func selectsCreatedClip() {
        let manager = ClipManager()
        manager.initializeWithSingleClip(
            trackId: "t1",
            mediaAssetId: "v1",
            durationMicros: 1_000_000
        )

        #expect(manager.selectedClipId != nil)
        #expect(manager.selectedClip != nil)
        #expect(manager.selectedClip?.mediaAssetId == "v1")
    }

    @Test("Clears undo/redo stacks")
    func clearsUndoRedo() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)
        manager.deleteClip("clip0")

        manager.initializeWithSingleClip(
            trackId: "t", mediaAssetId: "v", durationMicros: 1_000_000
        )

        #expect(manager.canUndo == false)
        #expect(manager.canRedo == false)
    }
}

// MARK: - Selection Tests

@Suite("ClipManager - Selection")
@MainActor
struct ClipManagerSelectionTests {

    @Test("Select a clip by ID")
    func selectClipById() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.selectClip("clip1")
        #expect(manager.selectedClipId == "clip1")
        #expect(manager.selectedClip?.id == "clip1")
    }

    @Test("Select nil deselects")
    func selectNilDeselects() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        manager.selectClip(nil)
        #expect(manager.selectedClipId == nil)
        #expect(manager.selectedClip == nil)
    }

    @Test("Selecting non-existent ID results in nil selectedClip")
    func selectNonExistentId() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        manager.selectClip("nonexistent")
        #expect(manager.selectedClipId == "nonexistent")
        #expect(manager.selectedClip == nil)
    }
}

// MARK: - Query Tests

@Suite("ClipManager - Queries")
@MainActor
struct ClipManagerQueryTests {

    @Test("getClipById returns correct clip")
    func getClipByIdFindsClip() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        let clip = manager.getClipById("clip1")
        #expect(clip?.id == "clip1")
        #expect(clip?.startTime == 1_000_000)
    }

    @Test("getClipById returns nil for non-existent ID")
    func getClipByIdMissing() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        #expect(manager.getClipById("missing") == nil)
    }

    @Test("clipAtTime returns correct clip")
    func clipAtTimeFindsClip() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        // Time 1_500_000 is within clip1 (1_000_000 to 2_000_000)
        let clip = manager.clipAtTime(1_500_000)
        #expect(clip?.id == "clip1")
    }

    @Test("clipAtTime returns nil for time outside all clips")
    func clipAtTimeOutsideRange() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        // Total duration is 2_000_000, so time 3_000_000 is outside
        #expect(manager.clipAtTime(3_000_000) == nil)
    }

    @Test("clipAtTime at exact start time returns that clip")
    func clipAtTimeExactStart() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        let clip = manager.clipAtTime(1_000_000)
        #expect(clip?.id == "clip1")
    }

    @Test("clipAtTime at exact end time does not return that clip")
    func clipAtTimeExactEnd() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        // clip0 ends at 1_000_000 (exclusive), clip1 starts at 1_000_000
        let clip = manager.clipAtTime(1_000_000)
        #expect(clip?.id == "clip1")
    }
}

// MARK: - Split Tests

@Suite("ClipManager - Split")
@MainActor
struct ClipManagerSplitTests {

    @Test("Split creates two clips from one")
    func splitCreatesTwo() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.splitAtTimelinePosition(1_000_000)

        #expect(manager.clips.count == 2)
    }

    @Test("Split preserves total duration")
    func splitPreservesTotalDuration() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.splitAtTimelinePosition(1_000_000)

        // Left duration + right duration should equal original
        let totalDuration = manager.clips.map(\.duration).reduce(0, +)
        #expect(totalDuration == 2_000_000)
    }

    @Test("Split selects the right clip")
    func splitSelectsRight() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.selectClip("clip0")
        manager.splitAtTimelinePosition(1_000_000)

        // The selected clip should be the right half (new clip)
        #expect(manager.selectedClipId != "clip0")
        #expect(manager.selectedClipId != nil)
    }

    @Test("Split at invalid position does nothing")
    func splitAtInvalidPosition() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        // Split at time outside any clip
        manager.splitAtTimelinePosition(5_000_000)
        #expect(manager.clips.count == 1)
    }

    @Test("Split at start time does nothing")
    func splitAtStartTime() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.splitAtTimelinePosition(0)
        #expect(manager.clips.count == 1)
    }

    @Test("Split at end time does nothing")
    func splitAtEndTime() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.splitAtTimelinePosition(2_000_000)
        #expect(manager.clips.count == 1)
    }

    @Test("Split is undoable")
    func splitUndoable() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.splitAtTimelinePosition(1_000_000)
        #expect(manager.clips.count == 2)

        let desc = manager.undo()
        #expect(desc == "Split clip")
        #expect(manager.clips.count == 1)
        #expect(manager.clips[0].duration == 2_000_000)
    }

    @Test("Split auto-finds clip at time when selected clip is not at position")
    func splitAutoFindsClip() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        // Select clip0, but split at a time within clip2
        manager.selectClip("clip0")
        manager.splitAtTimelinePosition(2_500_000)

        // clip2 should be split
        #expect(manager.clips.count == 4)
    }
}

// MARK: - Delete Tests

@Suite("ClipManager - Delete")
@MainActor
struct ClipManagerDeleteTests {

    @Test("Delete selected clip with ripple removes the clip")
    func deleteSelectedRipple() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.selectClip("clip1")
        manager.deleteSelectedClip(ripple: true)

        #expect(manager.clips.count == 2)
        #expect(manager.getClipById("clip1") == nil)
        #expect(manager.selectedClipId == nil)
    }

    @Test("Delete does not remove last remaining clip")
    func deleteDoesNotRemoveLast() {
        let manager = ClipManager()
        let clips = [makeClip(id: "only_clip")]
        manager.loadClips(clips)

        manager.selectClip("only_clip")
        manager.deleteSelectedClip()

        // Should still have 1 clip (cannot delete the last one)
        #expect(manager.clips.count == 1)
    }

    @Test("Delete without ripple inserts a gap clip")
    func deleteWithoutRipple() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.deleteClip("clip1", ripple: false)

        // Should still have 3 clips (original minus clip1 plus gap)
        #expect(manager.clips.count == 3)
        let gapClip = manager.clips.first { $0.type == .gap }
        #expect(gapClip != nil)
        #expect(gapClip?.startTime == 1_000_000)
        #expect(gapClip?.duration == 1_000_000)
    }

    @Test("Delete with ripple is undoable")
    func deleteRippleUndoable() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.deleteClip("clip1", ripple: true)
        #expect(manager.clips.count == 2)

        let desc = manager.undo()
        #expect(desc == "Delete clip (ripple)")
        #expect(manager.clips.count == 3)
        #expect(manager.getClipById("clip1") != nil)
    }

    @Test("Delete without ripple is undoable")
    func deleteNoRippleUndoable() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.deleteClip("clip1", ripple: false)
        #expect(manager.clips.first(where: { $0.type == .gap }) != nil)

        let desc = manager.undo()
        #expect(desc == "Delete clip")
        #expect(manager.clips.count == 3)
        #expect(manager.clips.allSatisfy { $0.type != .gap })
    }

    @Test("Delete non-existent clip does nothing")
    func deleteNonExistent() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        manager.deleteClip("nonexistent")
        #expect(manager.clips.count == 2)
    }

    @Test("deleteSelectedClip with no selection does nothing")
    func deleteSelectedNoSelection() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        manager.selectClip(nil)
        manager.deleteSelectedClip()
        #expect(manager.clips.count == 2)
    }
}

// MARK: - Duplicate Tests

@Suite("ClipManager - Duplicate")
@MainActor
struct ClipManagerDuplicateTests {

    @Test("Duplicate creates a copy after the original")
    func duplicateCreatesClip() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 1_000_000)]
        manager.loadClips(clips)

        manager.selectClip("clip0")
        manager.duplicateSelectedClip()

        #expect(manager.clips.count == 2)
    }

    @Test("Duplicate places copy at original's end time")
    func duplicatePlacement() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 1_000_000)]
        manager.loadClips(clips)

        manager.selectClip("clip0")
        manager.duplicateSelectedClip()

        let duplicated = manager.clips.first { $0.id != "clip0" }
        #expect(duplicated?.startTime == 1_000_000)
    }

    @Test("Duplicate selects the new clip")
    func duplicateSelectsNew() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 1_000_000)]
        manager.loadClips(clips)

        manager.selectClip("clip0")
        manager.duplicateSelectedClip()

        #expect(manager.selectedClipId != "clip0")
        #expect(manager.selectedClipId != nil)
    }

    @Test("Duplicate is undoable")
    func duplicateUndoable() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 1_000_000)]
        manager.loadClips(clips)

        manager.selectClip("clip0")
        manager.duplicateSelectedClip()
        #expect(manager.clips.count == 2)

        let desc = manager.undo()
        #expect(desc == "Duplicate clip")
        #expect(manager.clips.count == 1)
        #expect(manager.selectedClipId == "clip0")
    }

    @Test("Duplicate with no selection does nothing")
    func duplicateNoSelection() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0")]
        manager.loadClips(clips)

        manager.selectClip(nil)
        manager.duplicateSelectedClip()
        #expect(manager.clips.count == 1)
    }
}

// MARK: - Reorder Tests

@Suite("ClipManager - Reorder")
@MainActor
struct ClipManagerReorderTests {

    @Test("Reorder moves clip to new index")
    func reorderMovesClip() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        // Move clip0 to index 2
        manager.reorderClip("clip0", toIndex: 2)

        // After reorder, clip0 should be at a different position
        let currentIds = manager.state.clips.map(\.id)
        #expect(currentIds.last == "clip0")
    }

    @Test("Reorder is undoable")
    func reorderUndoable() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        let originalOrder = manager.state.clips.map(\.id)

        manager.reorderClip("clip0", toIndex: 2)

        let desc = manager.undo()
        #expect(desc == "Reorder clip")

        let restoredOrder = manager.state.clips.map(\.id)
        #expect(restoredOrder == originalOrder)
    }

    @Test("Reorder to same position does nothing")
    func reorderSamePosition() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        let originalOrder = manager.state.clips.map(\.id)

        // clip0 is at index 0, reorder to 0
        manager.reorderClip("clip0", toIndex: 0)

        let currentOrder = manager.state.clips.map(\.id)
        #expect(currentOrder == originalOrder)
    }

    @Test("Reorder non-existent clip does nothing")
    func reorderNonExistent() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 2)
        manager.loadClips(clips)

        let originalOrder = manager.state.clips.map(\.id)
        manager.reorderClip("nonexistent", toIndex: 0)
        let currentOrder = manager.state.clips.map(\.id)
        #expect(currentOrder == originalOrder)
    }

    @Test("Reorder clamps to valid index range")
    func reorderClampsIndex() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        // Reorder to a large index should clamp
        manager.reorderClip("clip0", toIndex: 100)
        #expect(manager.state.clips.last?.id == "clip0")
    }
}

// MARK: - Trim Tests

@Suite("ClipManager - Trim")
@MainActor
struct ClipManagerTrimTests {

    @Test("Trim head adjusts start time")
    func trimHead() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.trimClipHead("clip0", newStartTime: 500_000)

        let clip = manager.getClipById("clip0")
        #expect(clip?.startTime == 500_000)
        #expect(clip?.duration == 1_500_000)
    }

    @Test("Trim tail adjusts end time")
    func trimTail() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.trimClipTail("clip0", newEndTime: 1_500_000)

        let clip = manager.getClipById("clip0")
        #expect(clip?.duration == 1_500_000)
    }

    @Test("Trim head is undoable")
    func trimHeadUndoable() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.trimClipHead("clip0", newStartTime: 500_000)

        let desc = manager.undo()
        #expect(desc == "Trim clip")

        let clip = manager.getClipById("clip0")
        #expect(clip?.startTime == 0)
        #expect(clip?.duration == 2_000_000)
    }

    @Test("Trim tail is undoable")
    func trimTailUndoable() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 2_000_000)]
        manager.loadClips(clips)

        manager.trimClipTail("clip0", newEndTime: 1_000_000)

        let desc = manager.undo()
        #expect(desc == "Trim clip")

        let clip = manager.getClipById("clip0")
        #expect(clip?.duration == 2_000_000)
    }

    @Test("Trim below minimum duration does not change clip")
    func trimBelowMinDuration() {
        let manager = ClipManager()
        let clips = [makeClip(id: "clip0", startTime: 0, duration: 100_000)]
        manager.loadClips(clips)

        // Try to trim to less than minDuration
        manager.trimClipTail("clip0", newEndTime: 1_000)

        let clip = manager.getClipById("clip0")
        #expect(clip?.duration == 100_000)
    }
}

// MARK: - Undo/Redo Tests

@Suite("ClipManager - Undo/Redo")
@MainActor
struct ClipManagerUndoRedoTests {

    @Test("Undo returns nil when stack is empty")
    func undoEmptyReturnsNil() {
        let manager = ClipManager()
        #expect(manager.undo() == nil)
    }

    @Test("Redo returns nil when stack is empty")
    func redoEmptyReturnsNil() {
        let manager = ClipManager()
        #expect(manager.redo() == nil)
    }

    @Test("Execute -> Undo -> Redo restores state")
    func undoRedoCycle() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.deleteClip("clip1", ripple: true)
        #expect(manager.clips.count == 2)

        manager.undo()
        #expect(manager.clips.count == 3)

        manager.redo()
        #expect(manager.clips.count == 2)
    }

    @Test("Executing new command clears redo stack")
    func newCommandClearsRedo() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.deleteClip("clip1", ripple: true)
        manager.undo()
        #expect(manager.canRedo == true)

        // New command should clear redo
        manager.deleteClip("clip2", ripple: true)
        #expect(manager.canRedo == false)
    }

    @Test("Undo stack limited to maxUndoHistory")
    func undoStackLimit() {
        let manager = ClipManager()
        // We need at least maxUndoHistory + 1 clips to test
        let manyClips = (0..<55).map { i in
            makeClip(id: "clip\(i)", startTime: TimeMicros(i) * 1_000_000)
        }
        manager.loadClips(manyClips)

        // Perform more operations than maxUndoHistory
        for i in 0..<(ClipManager.maxUndoHistory + 5) {
            let trimId = "clip\(i)"
            manager.trimClipTail(trimId, newEndTime: TimeMicros(i) * 1_000_000 + 500_000)
        }

        // Undo should only go back maxUndoHistory times
        var undoCount = 0
        while manager.undo() != nil {
            undoCount += 1
        }
        #expect(undoCount == ClipManager.maxUndoHistory)
    }

    @Test("Multiple undos in sequence")
    func multipleUndos() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 5)
        manager.loadClips(clips)

        manager.deleteClip("clip1", ripple: true)
        manager.deleteClip("clip3", ripple: true)

        #expect(manager.clips.count == 3)

        manager.undo()
        #expect(manager.clips.count == 4)

        manager.undo()
        #expect(manager.clips.count == 5)
    }

    @Test("Undo description matches command")
    func undoDescription() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.deleteClip("clip1", ripple: true)

        let desc = manager.undo()
        #expect(desc == "Delete clip (ripple)")
    }

    @Test("Redo description matches command")
    func redoDescription() {
        let manager = ClipManager()
        let clips = makeSequentialClips(count: 3)
        manager.loadClips(clips)

        manager.duplicateSelectedClip()
        manager.undo()

        let desc = manager.redo()
        #expect(desc == "Duplicate clip")
    }
}

// MARK: - State Tests

@Suite("ClipManager - State")
@MainActor
struct ClipManagerStateTests {

    @Test("State sortedClips returns clips in order")
    func stateSortedClips() {
        var state = ClipManager.State()
        state.clips = [
            makeClip(id: "c", startTime: 2_000_000),
            makeClip(id: "a", startTime: 0),
            makeClip(id: "b", startTime: 1_000_000),
        ]

        let sorted = state.sortedClips
        #expect(sorted.map(\.id) == ["a", "b", "c"])
    }

    @Test("State totalDuration returns zero for empty clips")
    func stateTotalDurationEmpty() {
        let state = ClipManager.State()
        #expect(state.totalDuration == 0)
    }

    @Test("State clipById returns correct clip")
    func stateClipById() {
        var state = ClipManager.State()
        state.clips = makeSequentialClips(count: 3)

        #expect(state.clipById("clip1")?.id == "clip1")
        #expect(state.clipById("missing") == nil)
    }

    @Test("State indexOfClip returns correct index")
    func stateIndexOfClip() {
        var state = ClipManager.State()
        state.clips = makeSequentialClips(count: 3)

        #expect(state.indexOfClip("clip0") == 0)
        #expect(state.indexOfClip("clip2") == 2)
        #expect(state.indexOfClip("missing") == nil)
    }

    @Test("State clipAtTime finds clip containing time")
    func stateClipAtTime() {
        var state = ClipManager.State()
        state.clips = makeSequentialClips(count: 3)

        let clip = state.clipAtTime(1_500_000)
        #expect(clip?.id == "clip1")
    }

    @Test("State replaceClip at valid index replaces")
    func stateReplaceClip() {
        var state = ClipManager.State()
        state.clips = makeSequentialClips(count: 2)

        let replacement = makeClip(id: "replaced", startTime: 0, duration: 500_000)
        state.replaceClip(at: 0, with: replacement)

        #expect(state.clips[0].id == "replaced")
        #expect(state.clips[0].duration == 500_000)
    }

    @Test("State replaceClip at invalid index does nothing")
    func stateReplaceClipInvalid() {
        var state = ClipManager.State()
        state.clips = makeSequentialClips(count: 2)

        let replacement = makeClip(id: "x")
        state.replaceClip(at: -1, with: replacement)
        state.replaceClip(at: 5, with: replacement)

        #expect(state.clips.count == 2)
        #expect(state.clips[0].id == "clip0")
    }
}

// MARK: - Command Description Tests

@Suite("ClipManager - Command Descriptions")
@MainActor
struct ClipManagerCommandDescriptionTests {

    @Test("SplitClipCommand description")
    func splitDescription() {
        let cmd = SplitClipCommand(clipId: "x", splitTime: 1_000_000)
        #expect(cmd.description == "Split clip")
    }

    @Test("DeleteClipCommand ripple description")
    func deleteRippleDescription() {
        let cmd = DeleteClipCommand(clipId: "x", ripple: true)
        #expect(cmd.description == "Delete clip (ripple)")
    }

    @Test("DeleteClipCommand no-ripple description")
    func deleteNoRippleDescription() {
        let cmd = DeleteClipCommand(clipId: "x", ripple: false)
        #expect(cmd.description == "Delete clip")
    }

    @Test("ReorderClipCommand description")
    func reorderDescription() {
        let cmd = ReorderClipCommand(clipId: "x", newIndex: 2)
        #expect(cmd.description == "Reorder clip")
    }

    @Test("TrimClipCommand description")
    func trimDescription() {
        let cmd = TrimClipCommand(clipId: "x", newStartTime: 100, newEndTime: nil)
        #expect(cmd.description == "Trim clip")
    }

    @Test("DuplicateClipCommand description")
    func duplicateDescription() {
        let cmd = DuplicateClipCommand(clipId: "x")
        #expect(cmd.description == "Duplicate clip")
    }
}
