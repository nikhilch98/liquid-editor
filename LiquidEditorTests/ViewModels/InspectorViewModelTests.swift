// InspectorViewModelTests.swift
// TT13-7: Inspector matrix tests per spec §10.2.
//
// Verifies that InspectorViewModel.sectionIDs routes each
// InspectorSelectionType case to the correct ordered list of
// section IDs. The matrix is documented in-line in
// InspectorViewModel.swift.

import Testing
@testable import LiquidEditor

@MainActor
@Suite("InspectorViewModel selection routing")
struct InspectorViewModelTests {

    // MARK: - Default / init

    @Test("Default init produces .none routing")
    func defaultInit() {
        let vm = InspectorViewModel()
        #expect(vm.selection == .none)
        #expect(vm.sectionIDs == [.projectMeta, .playhead])
        #expect(vm.collapsedByDefault.isEmpty)
        #expect(vm.isMultiSelection == false)
    }

    // MARK: - .none

    @Test("No selection routes to project-meta + playhead")
    func noSelection() {
        let vm = InspectorViewModel(selection: .none)
        #expect(vm.sectionIDs == [.projectMeta, .playhead])
        #expect(vm.collapsedByDefault.isEmpty)
    }

    // MARK: - .playheadOnly

    @Test("Playhead-only collapses project meta")
    func playheadOnly() {
        let vm = InspectorViewModel(selection: .playheadOnly)
        #expect(vm.sectionIDs == [.playhead, .projectMeta])
        #expect(vm.collapsedByDefault == [.projectMeta])
    }

    // MARK: - .videoClip

    @Test("Video clip without audio omits volume and audioPan")
    func videoClipNoAudio() {
        let vm = InspectorViewModel(selection: .videoClip(hasAudio: false))
        #expect(vm.sectionIDs == [
            .clipHeader, .transform, .transformOps, .speed,
            .opacity, .blendMode, .colorGrade, .animation,
            .clipMarkers, .linkGroup, .proxy, .clipProperties,
        ])
        #expect(!vm.sectionIDs.contains(.volume))
        #expect(!vm.sectionIDs.contains(.audioPan))
    }

    @Test("Video clip with audio includes volume and audioPan after speed")
    func videoClipWithAudio() {
        let vm = InspectorViewModel(selection: .videoClip(hasAudio: true))
        #expect(vm.sectionIDs == [
            .clipHeader, .transform, .transformOps, .speed,
            .volume, .audioPan,
            .opacity, .blendMode, .colorGrade, .animation,
            .clipMarkers, .linkGroup, .proxy, .clipProperties,
        ])
    }

    // MARK: - .textClip

    @Test("Text clip includes text content but omits speed/volume")
    func textClip() {
        let vm = InspectorViewModel(selection: .textClip)
        #expect(vm.sectionIDs == [
            .clipHeader, .textContent, .transform, .opacity,
            .animation, .clipMarkers, .clipProperties,
        ])
        #expect(!vm.sectionIDs.contains(.speed))
        #expect(!vm.sectionIDs.contains(.volume))
        #expect(!vm.sectionIDs.contains(.colorGrade))
    }

    // MARK: - .audioClip

    @Test("Audio clip exposes audio-specific sections and omits transform/opacity")
    func audioClip() {
        let vm = InspectorViewModel(selection: .audioClip)
        #expect(vm.sectionIDs == [
            .clipHeader, .speed, .volume, .audioPan,
            .audioEffectsStack, .audioNormalize,
            .clipMarkers, .linkGroup, .clipProperties,
        ])
        #expect(!vm.sectionIDs.contains(.transform))
        #expect(!vm.sectionIDs.contains(.opacity))
        #expect(!vm.sectionIDs.contains(.colorGrade))
    }

    // MARK: - .captionClip

    @Test("Caption clip exposes caption style + animation")
    func captionClip() {
        let vm = InspectorViewModel(selection: .captionClip)
        #expect(vm.sectionIDs == [
            .clipHeader, .captionStyle, .opacity, .animation,
        ])
    }

    // MARK: - .multiSelect

    @Test("Multi-select collapses shared sections by default")
    func multiSelectCollapsed() {
        let vm = InspectorViewModel(selection: .multiSelect(count: 3))
        #expect(vm.isMultiSelection == true)
        #expect(vm.sectionIDs == [
            .clipHeader, .transform, .speed, .volume,
            .opacity, .colorGrade, .animation,
        ])
        // Clip header is always expanded; all editable sections collapsed.
        #expect(vm.collapsedByDefault == [
            .transform, .speed, .volume, .opacity,
            .colorGrade, .animation,
        ])
        #expect(!vm.collapsedByDefault.contains(.clipHeader))
    }

    @Test("isMultiSelection is false for single-clip selections")
    func isMultiSelectionFalse() {
        #expect(InspectorViewModel(selection: .none).isMultiSelection == false)
        #expect(InspectorViewModel(selection: .playheadOnly).isMultiSelection == false)
        #expect(InspectorViewModel(selection: .videoClip(hasAudio: true)).isMultiSelection == false)
        #expect(InspectorViewModel(selection: .textClip).isMultiSelection == false)
        #expect(InspectorViewModel(selection: .audioClip).isMultiSelection == false)
        #expect(InspectorViewModel(selection: .captionClip).isMultiSelection == false)
    }

    // MARK: - Recomputation

    @Test("Changing selection recomputes sectionIDs")
    func recomputesOnSelectionChange() {
        let vm = InspectorViewModel(selection: .none)
        #expect(vm.sectionIDs == [.projectMeta, .playhead])

        vm.selection = .audioClip
        #expect(vm.sectionIDs.first == .clipHeader)
        #expect(vm.sectionIDs.contains(.audioEffectsStack))

        vm.selection = .multiSelect(count: 2)
        #expect(vm.isMultiSelection == true)
        #expect(vm.collapsedByDefault.contains(.transform))

        vm.selection = .none
        #expect(vm.sectionIDs == [.projectMeta, .playhead])
        #expect(vm.collapsedByDefault.isEmpty)
    }
}
