// EditorViewModelStateTests.swift
// LiquidEditor
//
// TT13-1 (Premium UI §11.6): Structural state-transition tests for
// EditorViewModel. Because full snapshot testing requires an external
// library (SnapshotTesting) we verify the VM's observable state at each
// scenario — the same data that drives the views.
//
// Covered scenarios:
// - Initial / empty-timeline state.
// - Select clip → `selectedClipId` updates.
// - Switch tab → `activeTab` (legacy) and `selectedTab` (premium) update.
// - Clear selection → `selectedClipId` nil.
// - Zoom in / zoom out → `zoomScale` mutates within assigned values.
//
// NOTE: `EditorViewModel.selectedClipId` and `InspectorViewModel.selection`
// are independent — there is no binding between them today. Inspector
// section-ID routing is covered exhaustively by `InspectorViewModelTests`.
//
// Uses Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`).
// All tests are @MainActor — `EditorViewModel` is main-actor isolated.

import Testing
@testable import LiquidEditor

// MARK: - EditorViewModel State Transitions

@Suite("EditorViewModel state transitions")
@MainActor
struct EditorViewModelStateTests {

    // MARK: - Helpers

    /// Build a fresh view-model with an empty project and timeline.
    private func makeVM(timeline: PersistentTimeline = .empty) -> EditorViewModel {
        let project = Project(name: "TT13-1 Test Project", sourceVideoPath: "")
        return EditorViewModel(project: project, timeline: timeline)
    }

    /// Build a mock timeline item so we can simulate a populated timeline.
    private func makeItem(_ id: String, duration: Int64 = 1_000_000) -> MockTimelineItem {
        MockTimelineItem(id: id, durationMicroseconds: duration)
    }

    // MARK: - Initial State

    @Test("Initial state: empty timeline, no selection, default tab")
    func initialState() {
        let vm = makeVM()

        // Timeline is empty.
        #expect(vm.timeline.isEmpty)
        #expect(vm.totalDuration == 0)

        // No clip selected.
        #expect(vm.selectedClipId == nil)

        // Both the legacy and premium tab defaults.
        #expect(vm.activeTab == .edit)
        #expect(vm.selectedTab == .edit)

        // Playback / UI flags all start in neutral positions.
        #expect(vm.isPlaying == false)
        #expect(vm.activePanel == .none)
        #expect(vm.showExportSheet == false)
        #expect(vm.isTrimMode == false)
        #expect(vm.zoomScale == 1.0)
        #expect(vm.currentTime == 0)
    }

    // MARK: - Selection

    @Test("Select clip: selectedClipId updates to the assigned id")
    func selectClipUpdatesSelectedClipId() {
        let tl = PersistentTimeline.empty
            .append(makeItem("clip-a", duration: 2_000_000))
            .append(makeItem("clip-b", duration: 3_000_000))
        let vm = makeVM(timeline: tl)

        #expect(vm.selectedClipId == nil)

        vm.selectedClipId = "clip-a"
        #expect(vm.selectedClipId == "clip-a")

        vm.selectedClipId = "clip-b"
        #expect(vm.selectedClipId == "clip-b")
    }

    @Test("Clear selection: assigning nil resets selectedClipId")
    func clearSelection() {
        let tl = PersistentTimeline.empty.append(makeItem("c", duration: 1_000_000))
        let vm = makeVM(timeline: tl)

        vm.selectedClipId = "c"
        #expect(vm.selectedClipId == "c")

        vm.selectedClipId = nil
        #expect(vm.selectedClipId == nil)
    }

    // MARK: - Tab Switching

    @Test("Switch legacy activeTab: value updates for every EditorTab case")
    func switchLegacyTab() {
        let vm = makeVM()
        #expect(vm.activeTab == .edit)

        for tab in EditorTab.allCases {
            vm.activeTab = tab
            #expect(vm.activeTab == tab)
        }
    }

    @Test("Switch premium selectedTab: value updates for every EditorTabID case")
    func switchPremiumTab() {
        let vm = makeVM()
        #expect(vm.selectedTab == .edit)

        for tab in EditorTabID.allCases {
            vm.selectedTab = tab
            #expect(vm.selectedTab == tab)
        }
    }

    @Test("currentTabTools returns six tools per premium tab")
    func currentTabToolsCount() {
        let vm = makeVM()
        for tab in EditorTabID.allCases {
            vm.selectedTab = tab
            let tools = vm.currentTabTools
            // Spec §3/§4: each premium tab exposes exactly 6 tools.
            #expect(tools.count == 6, "Tab \(tab) should expose 6 tools")
            #expect(tools.allSatisfy { !$0.label.isEmpty })
            #expect(tools.allSatisfy { !$0.id.isEmpty })
        }
    }

    // MARK: - Zoom

    @Test("Apply zoom in / zoom out: zoomScale reflects assigned value")
    func zoomScaleAssignment() {
        // NOTE: EditorViewModel.zoomScale has no built-in clamping today;
        // this test asserts value propagation, not clamping behaviour.
        let vm = makeVM()
        #expect(vm.zoomScale == 1.0)

        // Zoom in.
        vm.zoomScale = 2.0
        #expect(vm.zoomScale == 2.0)

        // Zoom out (below default).
        vm.zoomScale = 0.5
        #expect(vm.zoomScale == 0.5)

        // Reset.
        vm.zoomScale = 1.0
        #expect(vm.zoomScale == 1.0)
    }

    // MARK: - Tool Panel / Trim Mode Interactions

    @Test("setActivePanel + dismissPanel round-trip leaves panel cleared")
    func panelRoundTrip() {
        let vm = makeVM()
        #expect(vm.activePanel == .none)

        vm.setActivePanel(.colorGrading)
        #expect(vm.activePanel == .colorGrading)
        #expect(vm.activePanel.isPresented)

        vm.dismissPanel()
        #expect(vm.activePanel == .none)
        #expect(!vm.activePanel.isPresented)
    }

    @Test("toggleTrimMode flips isTrimMode")
    func toggleTrim() {
        let vm = makeVM()
        #expect(vm.isTrimMode == false)

        vm.toggleTrimMode()
        #expect(vm.isTrimMode == true)

        vm.toggleTrimMode()
        #expect(vm.isTrimMode == false)
    }
}
