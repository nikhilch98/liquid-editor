import Testing
@testable import LiquidEditor

// MARK: - EditorTab Tests

@Suite("EditorTab Tests")
struct EditorTabTests {

    @Test("All EditorTab cases have a displayName")
    func displayNames() {
        #expect(EditorTab.edit.displayName == "Edit")
        #expect(EditorTab.fx.displayName == "FX")
        #expect(EditorTab.overlay.displayName == "Overlay")
        #expect(EditorTab.audio.displayName == "Audio")
        #expect(EditorTab.smart.displayName == "Smart")
    }

    @Test("All EditorTab cases have an iconName")
    func iconNames() {
        #expect(EditorTab.edit.iconName == "slider.horizontal.3")
        #expect(EditorTab.fx.iconName == "sparkles")
        #expect(EditorTab.overlay.iconName == "square.on.square")
        #expect(EditorTab.audio.iconName == "speaker.wave.2")
        #expect(EditorTab.smart.iconName == "brain")
    }

    @Test("EditorTab CaseIterable contains all cases")
    func allCases() {
        let cases = EditorTab.allCases
        #expect(cases.count == 5)
        #expect(cases.contains(.edit))
        #expect(cases.contains(.fx))
        #expect(cases.contains(.overlay))
        #expect(cases.contains(.audio))
        #expect(cases.contains(.smart))
    }

    @Test("EditorTab raw values are correct")
    func rawValues() {
        #expect(EditorTab.edit.rawValue == "edit")
        #expect(EditorTab.fx.rawValue == "fx")
        #expect(EditorTab.overlay.rawValue == "overlay")
        #expect(EditorTab.audio.rawValue == "audio")
        #expect(EditorTab.smart.rawValue == "smart")
    }
}

// MARK: - ActiveToolPanel Tests

@Suite("ActiveToolPanel Tests")
struct ActiveToolPanelTests {

    @Test("none panel is not presented")
    func noneNotPresented() {
        #expect(!ActiveToolPanel.none.isPresented)
    }

    @Test("All non-none panels are presented")
    func allNonNonePresented() {
        for panel in ActiveToolPanel.allCases where panel != .none {
            #expect(panel.isPresented, "Panel \(panel.rawValue) should be presented")
        }
    }

    @Test("All panels have a displayName")
    func displayNames() {
        #expect(ActiveToolPanel.none.displayName == "")
        #expect(ActiveToolPanel.colorGrading.displayName == "Color Grading")
        #expect(ActiveToolPanel.videoEffects.displayName == "Video Effects")
        #expect(ActiveToolPanel.crop.displayName == "Crop & Rotate")
        #expect(ActiveToolPanel.transition.displayName == "Transitions")
        #expect(ActiveToolPanel.audioEffects.displayName == "Audio Effects")
        #expect(ActiveToolPanel.textEditor.displayName == "Text Editor")
        #expect(ActiveToolPanel.stickerPicker.displayName == "Stickers")
        #expect(ActiveToolPanel.volume.displayName == "Volume")
        #expect(ActiveToolPanel.speed.displayName == "Speed")
        #expect(ActiveToolPanel.trackManagement.displayName == "Tracks")
        #expect(ActiveToolPanel.keyframeEditor.displayName == "Keyframes")
        #expect(ActiveToolPanel.autoReframe.displayName == "Auto Reframe")
        #expect(ActiveToolPanel.personSelection.displayName == "Person Selection")
    }

    @Test("ActiveToolPanel CaseIterable count")
    func allCasesCount() {
        // 13 panels + none = 14
        #expect(ActiveToolPanel.allCases.count == 14)
    }
}

// MARK: - EditorViewModel Tests

@Suite("EditorViewModel Tests")
@MainActor
struct EditorViewModelTests {

    // MARK: - Helpers

    private func makeProject(name: String = "Test Project") -> Project {
        Project(name: name, sourceVideoPath: "/test/video.mp4")
    }

    private func makeVM(
        timeline: PersistentTimeline = .empty
    ) -> EditorViewModel {
        EditorViewModel(project: makeProject(), timeline: timeline)
    }

    private func makeItem(_ id: String, duration: Int64 = 1_000_000) -> MockTimelineItem {
        MockTimelineItem(id: id, durationMicroseconds: duration)
    }

    // MARK: - Initial State

    @Test("Initial state has correct defaults")
    func initialState() {
        let vm = makeVM()

        #expect(vm.isPlaying == false)
        #expect(vm.selectedClipId == nil)
        #expect(vm.activeTab == .edit)
        #expect(vm.activePanel == .none)
        #expect(vm.showExportSheet == false)
        #expect(vm.showSettings == false)
        #expect(vm.isTrackingActive == false)
        #expect(vm.currentTime == 0)
        #expect(vm.zoomScale == 1.0)
        #expect(vm.multiTrackState == nil)
    }

    @Test("Initial undo/redo state is empty")
    func initialUndoRedo() {
        let vm = makeVM()
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == false)
    }

    // MARK: - Toggle Play/Pause

    @Test("togglePlayPause toggles isPlaying from false to true")
    func togglePlayPauseOn() {
        let vm = makeVM()
        #expect(vm.isPlaying == false)

        vm.togglePlayPause()
        #expect(vm.isPlaying == true)
    }

    @Test("togglePlayPause toggles isPlaying from true to false")
    func togglePlayPauseOff() {
        let vm = makeVM()
        vm.togglePlayPause() // true
        vm.togglePlayPause() // false
        #expect(vm.isPlaying == false)
    }

    @Test("play() sets isPlaying to true")
    func play() {
        let vm = makeVM()
        vm.play()
        #expect(vm.isPlaying == true)
    }

    @Test("pause() sets isPlaying to false")
    func pause() {
        let vm = makeVM()
        vm.play()
        vm.pause()
        #expect(vm.isPlaying == false)
    }

    // MARK: - Seek

    @Test("seek clamps to 0 when negative")
    func seekClampNegative() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 5_000_000))
        let vm = makeVM(timeline: tl)
        vm.seek(to: -100)
        #expect(vm.currentTime == 0)
    }

    @Test("seek clamps to totalDuration when beyond")
    func seekClampBeyond() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 5_000_000))
        let vm = makeVM(timeline: tl)
        vm.seek(to: 10_000_000)
        #expect(vm.currentTime == 5_000_000)
    }

    @Test("seek sets exact time within range")
    func seekExact() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 5_000_000))
        let vm = makeVM(timeline: tl)
        vm.seek(to: 2_500_000)
        #expect(vm.currentTime == 2_500_000)
    }

    // MARK: - Panel Management

    @Test("setActivePanel sets the panel")
    func setActivePanel() {
        let vm = makeVM()
        vm.setActivePanel(.colorGrading)
        #expect(vm.activePanel == .colorGrading)
        #expect(vm.activePanel.isPresented)
    }

    @Test("dismissPanel clears active panel")
    func dismissPanel() {
        let vm = makeVM()
        vm.setActivePanel(.crop)
        vm.dismissPanel()
        #expect(vm.activePanel == .none)
        #expect(!vm.activePanel.isPresented)
    }

    @Test("setActivePanel can switch between panels")
    func switchPanels() {
        let vm = makeVM()
        vm.setActivePanel(.colorGrading)
        #expect(vm.activePanel == .colorGrading)

        vm.setActivePanel(.videoEffects)
        #expect(vm.activePanel == .videoEffects)
    }

    // MARK: - Undo / Redo

    @Test("deleteSelected pushes undo state and enables canUndo")
    func undoAfterDelete() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 1_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectedClipId = "a"

        vm.deleteSelected()

        #expect(vm.canUndo == true)
        #expect(vm.canRedo == false)
        #expect(vm.timeline.isEmpty)
        #expect(vm.selectedClipId == nil)
    }

    @Test("undo restores previous timeline state")
    func undoRestoresState() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 1_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectedClipId = "a"

        vm.deleteSelected()
        #expect(vm.timeline.isEmpty)

        vm.undo()
        #expect(vm.timeline.count == 1)
        #expect(vm.timeline.containsId("a"))
    }

    @Test("redo restores undone state")
    func redoRestoresState() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 1_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectedClipId = "a"

        vm.deleteSelected()
        vm.undo()
        #expect(vm.timeline.count == 1)

        vm.redo()
        #expect(vm.timeline.isEmpty)
    }

    @Test("undo on empty stack does nothing")
    func undoEmpty() {
        let vm = makeVM()
        vm.undo()
        #expect(vm.canUndo == false)
    }

    @Test("redo on empty stack does nothing")
    func redoEmpty() {
        let vm = makeVM()
        vm.redo()
        #expect(vm.canRedo == false)
    }

    @Test("canUndo is true after push, canRedo is true after undo")
    func canUndoCanRedo() {
        let tl = PersistentTimeline.empty.append(makeItem("a"))
        let vm = makeVM(timeline: tl)
        vm.selectedClipId = "a"

        #expect(vm.canUndo == false)
        #expect(vm.canRedo == false)

        vm.deleteSelected()
        #expect(vm.canUndo == true)
        #expect(vm.canRedo == false)

        vm.undo()
        #expect(vm.canUndo == false)
        #expect(vm.canRedo == true)

        vm.redo()
        #expect(vm.canUndo == true)
        #expect(vm.canRedo == false)
    }

    // MARK: - Formatted Times

    @Test("formattedCurrentTime at 0 returns 00:00.00")
    func formattedTimeZero() {
        let vm = makeVM()
        #expect(vm.formattedCurrentTime == "00:00.00")
    }

    @Test("formattedCurrentTime formats correctly")
    func formattedTimeNonZero() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 90_500_000))
        let vm = makeVM(timeline: tl)
        // Set current time to 1 minute 30 seconds 500ms = 90_500_000 micros
        vm.seek(to: 90_500_000)
        #expect(vm.formattedCurrentTime == "01:30.50")
    }

    @Test("formattedTotalDuration matches timeline total")
    func formattedTotalDuration() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 60_000_000)) // 1 min
            .append(makeItem("b", duration: 30_000_000)) // 30 sec
        let vm = makeVM(timeline: tl)
        // 1:30.00
        #expect(vm.formattedTotalDuration == "01:30.00")
    }

    @Test("totalDuration computed property matches timeline")
    func totalDurationComputed() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 3_000_000))
        let vm = makeVM(timeline: tl)
        #expect(vm.totalDuration == 3_000_000)
    }

    // MARK: - Delete Selected

    @Test("deleteSelected with no selection does nothing")
    func deleteNoSelection() {
        let tl = PersistentTimeline.empty.append(makeItem("a"))
        let vm = makeVM(timeline: tl)
        vm.deleteSelected()
        #expect(vm.timeline.count == 1)
        #expect(vm.canUndo == false)
    }

    @Test("deleteSelected removes clip and clears selection")
    func deleteRemovesClip() {
        let tl = PersistentTimeline.empty
            .append(makeItem("a", duration: 1_000_000))
            .append(makeItem("b", duration: 2_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectedClipId = "a"

        vm.deleteSelected()

        #expect(vm.timeline.count == 1)
        #expect(!vm.timeline.containsId("a"))
        #expect(vm.timeline.containsId("b"))
        #expect(vm.selectedClipId == nil)
    }

    // MARK: - Split at Playhead

    @Test("splitAtPlayhead with no selection does nothing")
    func splitNoSelection() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 2_000_000))
        let vm = makeVM(timeline: tl)
        vm.splitAtPlayhead()
        #expect(vm.timeline.count == 1)
    }

    @Test("splitAtPlayhead with playhead outside clip does nothing")
    func splitPlayheadOutside() {
        let tl = PersistentTimeline.empty.append(makeItem("a", duration: 2_000_000))
        let vm = makeVM(timeline: tl)
        vm.selectedClipId = "a"
        vm.currentTime = 0 // at boundary, not within
        vm.splitAtPlayhead()
        // offset is 0, which fails guard (offsetInClip > 0)
        #expect(vm.timeline.count == 1)
    }

    // MARK: - Export / Settings Toggles

    @Test("showExportSheet can be toggled")
    func toggleExportSheet() {
        let vm = makeVM()
        #expect(vm.showExportSheet == false)
        vm.showExportSheet = true
        #expect(vm.showExportSheet == true)
        vm.showExportSheet = false
        #expect(vm.showExportSheet == false)
    }

    @Test("showSettings can be toggled")
    func toggleSettings() {
        let vm = makeVM()
        #expect(vm.showSettings == false)
        vm.showSettings = true
        #expect(vm.showSettings == true)
    }

    // MARK: - Tab Selection

    @Test("activeTab can be changed")
    func changeTab() {
        let vm = makeVM()
        #expect(vm.activeTab == .edit)

        vm.activeTab = .fx
        #expect(vm.activeTab == .fx)

        vm.activeTab = .audio
        #expect(vm.activeTab == .audio)
    }

    // MARK: - Duplicate Selected

    @Test("duplicateSelected with no selection does nothing")
    func duplicateNoSelection() {
        let tl = PersistentTimeline.empty.append(makeItem("a"))
        let vm = makeVM(timeline: tl)
        vm.duplicateSelected()
        // No undo pushed since no selection
        #expect(vm.canUndo == false)
    }
}
