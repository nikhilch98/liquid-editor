import Testing
@testable import LiquidEditor

// MARK: - TimelineViewModel Tests

@Suite("TimelineViewModel Tests")
@MainActor
struct TimelineViewModelTests {

    // MARK: - Helpers

    private func makeItem(_ id: String, duration: Int64 = 1_000_000) -> MockTimelineItem {
        MockTimelineItem(id: id, durationMicroseconds: duration)
    }

    private func makeVM(
        timeline: PersistentTimeline = .empty,
        tracks: [Track] = []
    ) -> TimelineViewModel {
        TimelineViewModel(timeline: timeline, tracks: tracks)
    }

    // MARK: - Initial State

    @Suite("Initial State")
    @MainActor
    struct InitialStateTests {

        @Test("Default init has empty timeline")
        func defaultInitEmpty() {
            let vm = TimelineViewModel()
            #expect(vm.totalDuration == 0)
            #expect(vm.tracks.isEmpty)
            #expect(vm.playheadPosition == 0)
        }

        @Test("Default selection is empty")
        func defaultSelectionEmpty() {
            let vm = TimelineViewModel()
            #expect(!vm.selection.hasSelection)
            #expect(vm.selection.primaryClipId == nil)
        }

        @Test("Default interaction flags are false")
        func defaultInteractionFlags() {
            let vm = TimelineViewModel()
            #expect(vm.isDragging == false)
            #expect(vm.isTrimming == false)
            #expect(vm.isScrubbingTimeline == false)
        }

        @Test("Snap is enabled by default")
        func snapEnabledByDefault() {
            let vm = TimelineViewModel()
            #expect(vm.snapEnabled == true)
        }

        @Test("Default undo/redo stacks are empty")
        func defaultUndoRedo() {
            let vm = TimelineViewModel()
            #expect(vm.canUndo == false)
            #expect(vm.canRedo == false)
        }

        @Test("Default scroll offset is 0")
        func defaultScrollOffset() {
            let vm = TimelineViewModel()
            #expect(vm.scrollOffset == 0)
        }
    }

    // MARK: - Selection

    @Suite("Selection")
    @MainActor
    struct SelectionTests {

        private func makeItem(_ id: String, duration: Int64 = 1_000_000) -> MockTimelineItem {
            MockTimelineItem(id: id, durationMicroseconds: duration)
        }

        @Test("selectClip selects a single clip")
        func selectClip() {
            let tl = PersistentTimeline.empty.append(makeItem("a"))
            let vm = TimelineViewModel(timeline: tl, tracks: [])

            vm.selectClip(id: "a")

            #expect(vm.selection.hasSelection)
            #expect(vm.selection.primaryClipId == "a")
            #expect(vm.selection.selectedClipIds.contains("a"))
        }

        @Test("deselectAll clears all selections")
        func deselectAll() {
            let tl = PersistentTimeline.empty.append(makeItem("a"))
            let vm = TimelineViewModel(timeline: tl, tracks: [])

            vm.selectClip(id: "a")
            vm.deselectAll()

            #expect(!vm.selection.hasSelection)
            #expect(vm.selection.primaryClipId == nil)
        }

        @Test("selectClip replaces previous selection")
        func selectClipReplacesSelection() {
            let tl = PersistentTimeline.empty
                .append(makeItem("a"))
                .append(makeItem("b"))
            let vm = TimelineViewModel(timeline: tl, tracks: [])

            vm.selectClip(id: "a")
            vm.selectClip(id: "b")

            #expect(vm.selection.primaryClipId == "b")
            #expect(!vm.selection.selectedClipIds.contains("a"))
            #expect(vm.selection.selectedClipIds.contains("b"))
        }

        @Test("toggleClipSelection adds and removes clips")
        func toggleClipSelection() {
            let tl = PersistentTimeline.empty
                .append(makeItem("a"))
                .append(makeItem("b"))
            let vm = TimelineViewModel(timeline: tl, tracks: [])

            vm.toggleClipSelection(id: "a")
            #expect(vm.selection.selectedClipIds.contains("a"))

            vm.toggleClipSelection(id: "b")
            #expect(vm.selection.selectedClipIds.contains("b"))
            #expect(vm.selection.hasMultiSelection)

            vm.toggleClipSelection(id: "a")
            #expect(!vm.selection.selectedClipIds.contains("a"))
            #expect(vm.selection.selectedClipIds.contains("b"))
        }
    }

    // MARK: - Zoom Level

    @Test("Zoom level reflects viewport pixelsPerMicrosecond")
    func zoomLevelGetter() {
        let vm = makeVM()
        let expected = vm.viewport.pixelsPerMicrosecond
        #expect(vm.zoomLevel == expected)
    }

    @Test("Setting zoom level updates viewport")
    func zoomLevelSetter() {
        let vm = makeVM()
        let newZoom = 0.001
        vm.zoomLevel = newZoom
        // After setting, the zoom level should match (within viewport clamping)
        #expect(vm.zoomLevel > 0)
    }

    // MARK: - Scroll Offset

    @Test("Scroll offset can be set")
    func scrollOffsetSet() {
        let vm = makeVM()
        vm.scrollOffset = 100
        #expect(vm.scrollOffset == 100)
    }

    // MARK: - Coordinate Conversion

    @Test("timeToX and xToTime are inverse operations")
    func coordinateConversionRoundTrip() {
        let vm = makeVM()
        let time: TimeMicros = 5_000_000

        let x = vm.timeToX(time)
        let recoveredTime = vm.xToTime(x)

        #expect(recoveredTime == time)
    }

    @Test("timeToX returns 0 for time 0 at scroll position 0")
    func timeToXAtZero() {
        let vm = makeVM()
        let x = vm.timeToX(0)
        #expect(x == 0.0)
    }

    @Test("xToTime returns 0 for x 0 at scroll position 0")
    func xToTimeAtZero() {
        let vm = makeVM()
        let time = vm.xToTime(0)
        #expect(time == 0)
    }

    // MARK: - Snap To Nearest Edge

    @Test("snapToNearestEdge returns original time when snap disabled")
    func snapDisabled() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
        let vm = makeVM(timeline: tl)
        vm.snapEnabled = false

        let time: TimeMicros = 500_000
        let snapped = vm.snapToNearestEdge(time: time)
        #expect(snapped == time)
    }

    @Test("snapToNearestEdge snaps to playhead when within tolerance")
    func snapToPlayhead() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 10_000_000))
        let vm = makeVM(timeline: tl)
        vm.playheadPosition = 5_000_000

        // Use a time very close to the playhead (within 8 pixels of snap tolerance)
        let nearPlayhead = vm.playheadPosition + 1 // 1 microsecond off
        let snapped = vm.snapToNearestEdge(time: nearPlayhead)
        #expect(snapped == vm.playheadPosition)
    }

    @Test("snapToNearestEdge snaps to clip start edge")
    func snapToClipStartEdge() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 5_000_000))
            .append(makeItem("b", duration: 5_000_000))
        let vm = makeVM(timeline: tl)

        // Time very close to the start of "b" (at 5_000_000)
        let nearStart = 5_000_001 as TimeMicros
        let snapped = vm.snapToNearestEdge(time: nearStart)
        #expect(snapped == 5_000_000)
    }

    // MARK: - Total Duration

    @Test("totalDuration matches timeline total")
    func totalDuration() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 2_000_000))
            .append(makeItem("b", duration: 3_000_000))
        let vm = makeVM(timeline: tl)

        #expect(vm.totalDuration == 5_000_000)
    }

    @Test("totalDuration is 0 for empty timeline")
    func totalDurationEmpty() {
        let vm = makeVM()
        #expect(vm.totalDuration == 0)
    }

    @Test("formattedTotalDuration is formatted correctly")
    func formattedTotalDuration() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 65_000_000)) // 1:05.00
        let vm = makeVM(timeline: tl)
        #expect(vm.formattedTotalDuration == "01:05.00")
    }

    // MARK: - Total Timeline Width

    @Test("totalTimelineWidth is 0 for empty timeline")
    func totalTimelineWidthEmpty() {
        let vm = makeVM()
        #expect(vm.totalTimelineWidth == 0)
    }

    @Test("totalTimelineWidth scales with zoom")
    func totalTimelineWidthScalesWithZoom() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 10_000_000))
        let vm = makeVM(timeline: tl)

        let width1 = vm.totalTimelineWidth

        // Zoom in (double zoom level)
        vm.zoom(scale: 2.0, anchor: 0)
        let width2 = vm.totalTimelineWidth

        // Width should approximately double (zoom in makes timeline wider)
        #expect(width2 > width1)
    }

    // MARK: - Interaction Flags

    @Test("isDragging can be set")
    func isDragging() {
        let vm = makeVM()
        vm.isDragging = true
        #expect(vm.isDragging == true)
        vm.isDragging = false
        #expect(vm.isDragging == false)
    }

    @Test("isTrimming can be set")
    func isTrimming() {
        let vm = makeVM()
        vm.isTrimming = true
        #expect(vm.isTrimming == true)
    }

    @Test("isScrubbingTimeline can be set")
    func isScrubbingTimeline() {
        let vm = makeVM()
        vm.isScrubbingTimeline = true
        #expect(vm.isScrubbingTimeline == true)
    }

    // MARK: - Undo / Redo

    @Test("deleteSelectedClips enables undo")
    func deleteEnablesUndo() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectClip(id: "a")

        vm.deleteSelectedClips()

        #expect(vm.canUndo == true)
        #expect(vm.timeline.isEmpty)
    }

    @Test("undo restores timeline after delete")
    func undoAfterDelete() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectClip(id: "a")

        vm.deleteSelectedClips()
        #expect(vm.timeline.isEmpty)

        vm.undo()
        #expect(vm.timeline.count == 1)
        #expect(vm.timeline.containsId("a"))
    }

    @Test("redo after undo restores deleted state")
    func redoAfterUndo() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectClip(id: "a")

        vm.deleteSelectedClips()
        vm.undo()
        vm.redo()

        #expect(vm.timeline.isEmpty)
    }

    @Test("New operation clears redo stack")
    func newOperationClearsRedo() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a"))
            .append(makeItem("b"))
        let vm = makeVM(timeline: tl)

        vm.selectClip(id: "a")
        vm.deleteSelectedClips()
        vm.undo()
        #expect(vm.canRedo == true)

        // New operation should clear redo stack
        vm.selectClip(id: "b")
        vm.deleteSelectedClips()
        #expect(vm.canRedo == false)
    }

    // MARK: - Track Management

    @Test("addTrack adds a track to the list")
    func addTrack() {
        let vm = makeVM()
        #expect(vm.tracks.isEmpty)

        vm.addTrack(name: "Video 1", type: .mainVideo)
        #expect(vm.tracks.count == 1)
        #expect(vm.tracks[0].name == "Video 1")
        #expect(vm.tracks[0].type == .mainVideo)
        #expect(vm.tracks[0].index == 0)
    }

    @Test("removeTrack removes track and re-indexes")
    func removeTrack() {
        let vm = makeVM()
        vm.addTrack(name: "Track A")
        vm.addTrack(name: "Track B")
        vm.addTrack(name: "Track C")

        let trackBId = vm.tracks[1].id
        vm.removeTrack(id: trackBId)

        #expect(vm.tracks.count == 2)
        #expect(vm.tracks[0].index == 0)
        #expect(vm.tracks[1].index == 1)
    }

    @Test("reorderTrack moves track to new position")
    func reorderTrack() {
        let vm = makeVM()
        vm.addTrack(name: "Track A")
        vm.addTrack(name: "Track B")
        vm.addTrack(name: "Track C")

        let trackCId = vm.tracks[2].id
        vm.reorderTrack(id: trackCId, to: 0)

        #expect(vm.tracks[0].id == trackCId)
        #expect(vm.tracks[0].index == 0)
        #expect(vm.tracks[1].index == 1)
        #expect(vm.tracks[2].index == 2)
    }

    // MARK: - Viewport Updates

    @Test("updateViewportSize changes viewport dimensions")
    func updateViewportSize() {
        let vm = makeVM()
        vm.updateViewportSize(width: 800, height: 600)
        #expect(vm.viewport.viewportWidth == 800)
        #expect(vm.viewport.viewportHeight == 600)
    }

    @Test("zoomToFit adjusts zoom for timeline duration")
    func zoomToFit() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 10_000_000))
        let vm = makeVM(timeline: tl)
        vm.updateViewportSize(width: 800, height: 600)

        vm.zoomToFit()

        // After zoom to fit, the total width should roughly match the viewport content width
        let contentWidth = vm.viewport.contentWidth
        let timelineWidth = Double(vm.totalTimelineWidth)
        // Within 20% margin
        let ratio = timelineWidth / contentWidth
        #expect(ratio > 0.7)
        #expect(ratio < 1.3)
    }

    @Test("zoomToFit on empty timeline does nothing")
    func zoomToFitEmpty() {
        let vm = makeVM()
        let originalZoom = vm.viewport.microsPerPixel
        vm.zoomToFit()
        // Should not change since totalDuration is 0
        #expect(vm.viewport.microsPerPixel == originalZoom)
    }
}
