// EndToEndSmokeTests.swift
// LiquidEditorTests
//
// I14-2: End-to-end editor smoke test.
//
// Unit-level smoke coverage of the create -> import -> edit -> export flow.
// No UI driving and no real video files — purely constructs models and
// commands to verify the major service contracts still compile and behave
// correctly after the premium UI redesign.
//
// Scope of each @Test (in call order):
//   1. EditorViewModel initial state (empty timeline, no selection).
//   2. TimelineClip duration parsing (no real asset — stub duration).
//   3. ClipEffectStack equivalent (EffectChain + VideoEffect) — verify add.
//   4. TimelineCutCommand on a 2-clip timeline — verify one remains.
//   5. ExportPreset + FilenameTemplate.resolve produces a non-empty name.

import Foundation
import Testing
@testable import LiquidEditor

@Suite("End-to-end editor smoke")
@MainActor
struct EndToEndSmokeTests {

    // MARK: - Helpers

    /// Build a stub `Project` — matches the pattern used in existing
    /// `EditorViewModelTests`.
    private func makeStubProject(name: String = "Smoke Project") -> Project {
        Project(name: name, sourceVideoPath: "/stub/video.mp4")
    }

    /// Build a one-second `VideoClip` with a stub media asset ID.
    private func makeStubVideoClip(
        id: String = "stub-clip-\(UUID().uuidString)",
        durationMicros: TimeMicros = 1_000_000
    ) -> VideoClip {
        VideoClip(
            id: id,
            mediaAssetId: "stub-asset",
            sourceInMicros: 0,
            sourceOutMicros: durationMicros
        )
    }

    // MARK: - 1. Initial EditorViewModel state

    @Test("EditorViewModel starts with an empty timeline and no selection")
    func editorViewModelInitialState() {
        let project = makeStubProject()
        let vm = EditorViewModel(project: project, timeline: .empty)

        #expect(vm.project.name == "Smoke Project")
        #expect(vm.timeline.count == 0)
        #expect(vm.selectedClipId == nil)
        #expect(vm.currentTime == 0)
        #expect(vm.isPlaying == false)
        #expect(vm.activePanel == .none)
        #expect(!vm.canUndo)
        #expect(!vm.canRedo)
    }

    // MARK: - 2. TimelineClip constructed from a stub asset URL

    @Test("TimelineClip duration is parsed from the stub source range")
    func timelineClipFromStubAsset() {
        // Stub "asset URL" — not loaded, just a reference for traceability.
        let stubURL = URL(fileURLWithPath: "/stub/assets/stub.mov")

        // Known source duration (2.5 s) drives the test assertion.
        let durationMicros: TimeMicros = 2_500_000

        let clip = TimelineClip(
            id: "clip-\(stubURL.lastPathComponent)",
            mediaAssetId: stubURL.path,
            trackId: "v1",
            type: .video,
            startTime: 0,
            duration: durationMicros,
            sourceIn: 0,
            sourceOut: durationMicros
        )

        #expect(clip.duration == durationMicros)
        #expect(clip.endTime == durationMicros)
        #expect(clip.sourceDuration == durationMicros)
        #expect(clip.type == .video)
        #expect(clip.mediaAssetId == stubURL.path)
    }

    // MARK: - 3. Apply a single effect to an EffectChain (ClipEffectStack proxy)

    @Test("Applying a single effect yields a chain of length 1")
    func effectChainAppliesSingleEffect() {
        // EffectChain is the per-clip effect stack used across the codebase
        // wherever a "ClipEffectStack" is referenced in the premium-UI spec.
        let chain = EffectChain()
        #expect(chain.isEmpty)

        let effect = VideoEffect.create(.vignette)
        let updated = chain.addEffect(effect)

        #expect(updated.length == 1)
        #expect(updated.isNotEmpty)
        #expect(updated.hasEnabledEffects)
        #expect(updated.effectAt(0)?.id == effect.id)
        #expect(updated.effectAt(0)?.type == .vignette)
    }

    // MARK: - 4. TimelineCutCommand on a 2-clip timeline

    @Test("Cutting one clip from a 2-clip timeline leaves the other behind")
    func timelineCutCommandOnTwoClipTimeline() {
        let clipA = makeStubVideoClip(id: "clip-a")
        let clipB = makeStubVideoClip(id: "clip-b")

        let timeline = PersistentTimeline.empty
            .append(clipA)
            .append(clipB)

        #expect(timeline.count == 2)

        let ripple = RippleEditController(globalDefault: .on)
        let clipboard = ClipboardStore()

        let result = TimelineCutCommand.execute(
            clipId: clipA.id,
            timeline: timeline,
            sourceTrackId: "v1",
            ripple: ripple,
            clipboard: clipboard
        )

        #expect(result != nil, "TimelineCutCommand should return a result for a valid clip")
        if let cut = result {
            #expect(cut.timeline.count == 1)
            #expect(cut.timeline.containsId(clipB.id) == true)
            #expect(cut.timeline.containsId(clipA.id) == false)
            #expect(cut.mode == .on)
            #expect(cut.removedDurationMicros == clipA.durationMicroseconds)
        }

        // Cut stores the removed clip on the clipboard.
        #expect(clipboard.hasContents)
        #expect(clipboard.current?.clip.id == clipA.id)
    }

    // MARK: - 5. ExportPreset + FilenameTemplate.resolve

    @Test("ExportPreset drives a non-empty FilenameTemplate resolution")
    func exportPresetResolvesFilename() {
        // Pick any built-in preset — "standard" is always present by contract.
        let preset = ExportPresetService.findById("standard")
        #expect(preset != nil, "built-in 'standard' preset must exist")
        #expect(preset?.name == "Standard")
        #expect(preset?.isBuiltIn == true)

        let template = FilenameTemplate.default
        let context = TemplateContext(
            projectName: "Smoke Project",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            preset: preset?.name ?? "Standard",
            counter: 1
        )
        let resolved = template.resolve(context: context)

        #expect(!resolved.isEmpty)
        #expect(resolved.contains("Smoke_Project"))
        #expect(resolved.contains("001"))
    }
}
