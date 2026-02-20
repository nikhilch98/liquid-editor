import Testing
import Foundation
@testable import LiquidEditor

// MARK: - SlipController Tests

@Suite("SlipController Tests")
struct SlipControllerTests {

    /// Create a test clip.
    private func makeClip(
        id: String = "clip-1",
        trackId: String = "track-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000,
        sourceIn: TimeMicros = 500_000,
        sourceOut: TimeMicros = 1_500_000
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration,
            sourceIn: sourceIn,
            sourceOut: sourceOut
        )
    }

    // MARK: - Start Slip

    @Test("Start slip captures original state")
    func startSlip() {
        let clip = makeClip(sourceIn: 500_000, sourceOut: 1_500_000)
        let state = SlipController.startSlip(clip)

        #expect(state.clip.id == "clip-1")
        #expect(state.originalSourceIn == 500_000)
        #expect(state.originalSourceOut == 1_500_000)
    }

    // MARK: - Calculate Preview

    @Test("Slip forward")
    func slipForward() {
        let clip = makeClip(sourceIn: 500_000, sourceOut: 1_500_000)
        let state = SlipController.startSlip(clip)

        let preview = SlipController.calculateSlipPreview(
            state: state,
            sourceDelta: 200_000
        )

        #expect(preview.clipId == "clip-1")
        #expect(preview.newSourceIn == 700_000)
        #expect(preview.newSourceOut == 1_700_000)
        #expect(preview.startTime == 0) // Unchanged
        #expect(preview.duration == 1_000_000) // Unchanged
    }

    @Test("Slip backward")
    func slipBackward() {
        let clip = makeClip(sourceIn: 500_000, sourceOut: 1_500_000)
        let state = SlipController.startSlip(clip)

        let preview = SlipController.calculateSlipPreview(
            state: state,
            sourceDelta: -200_000
        )

        #expect(preview.newSourceIn == 300_000)
        #expect(preview.newSourceOut == 1_300_000)
    }

    @Test("Slip clamped at source start")
    func slipClampedAtStart() {
        let clip = makeClip(sourceIn: 100_000, sourceOut: 1_100_000)
        let state = SlipController.startSlip(clip)

        let preview = SlipController.calculateSlipPreview(
            state: state,
            sourceDelta: -500_000 // Would make sourceIn negative
        )

        #expect(preview.newSourceIn == 0)
        #expect(preview.newSourceOut == 1_000_000) // sourceOut - sourceIn = original clip duration
    }

    @Test("Slip clamped at max source duration")
    func slipClampedAtMax() {
        let clip = makeClip(sourceIn: 500_000, sourceOut: 1_500_000)
        let state = SlipController.startSlip(clip)

        let preview = SlipController.calculateSlipPreview(
            state: state,
            sourceDelta: 500_000,
            maxSourceDuration: 1_800_000 // Would overshoot
        )

        #expect(preview.newSourceOut == 1_800_000)
        #expect(preview.newSourceIn == 800_000)
    }

    // MARK: - Apply Slip

    @Test("Apply slip modifies clip")
    func applySlip() {
        let clip = makeClip(sourceIn: 500_000, sourceOut: 1_500_000)
        let preview = SlipPreview(
            clipId: "clip-1",
            newSourceIn: 700_000,
            newSourceOut: 1_700_000,
            startTime: 0,
            duration: 1_000_000
        )

        let result = SlipController.applySlip(clip, preview: preview)
        #expect(result.sourceIn == 700_000)
        #expect(result.sourceOut == 1_700_000)
        #expect(result.startTime == 0) // Unchanged
        #expect(result.duration == 1_000_000) // Unchanged
    }

    // MARK: - Cancel Slip

    @Test("Cancel slip restores original state")
    func cancelSlip() {
        let clip = makeClip(sourceIn: 500_000, sourceOut: 1_500_000)
        let state = SlipController.startSlip(clip)

        // Simulate a slip
        let modifiedClip = clip.with(sourceIn: 700_000, sourceOut: 1_700_000)
        let restored = SlipController.cancelSlip(modifiedClip, state: state)

        #expect(restored.sourceIn == 500_000)
        #expect(restored.sourceOut == 1_500_000)
    }
}

// MARK: - SlideMode Tests

@Suite("SlideMode Tests")
struct SlideModeTests {

    @Test("All cases exist")
    func allCases() {
        #expect(SlideMode.allCases.count == 3)
        #expect(SlideMode.allCases.contains(.standard))
        #expect(SlideMode.allCases.contains(.overwrite))
        #expect(SlideMode.allCases.contains(.ripple))
    }
}

// MARK: - SlideValidation Tests

@Suite("SlideValidation Tests")
struct SlideValidationTests {

    @Test("Valid slide")
    func validSlide() {
        let v = SlideValidation.valid(minPosition: 100, maxPosition: 900)
        #expect(v.isValid)
        #expect(v.minPosition == 100)
        #expect(v.maxPosition == 900)
        #expect(v.error == nil)
    }

    @Test("Invalid slide")
    func invalidSlide() {
        let v = SlideValidation.invalid("Too far left")
        #expect(!v.isValid)
        #expect(v.error == "Too far left")
    }
}

// MARK: - SlideController Tests

@Suite("SlideController Tests")
@MainActor
struct SlideControllerTests {

    /// Create a test clip.
    private func makeClip(
        id: String = "clip-1",
        trackId: String = "track-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration,
            sourceIn: 0
        )
    }

    // MARK: - Start Slide

    @Test("Start slide finds adjacent clips")
    func startSlide() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)
        let left = makeClip(id: "left", startTime: 0, duration: 1_000_000)
        let right = makeClip(id: "right", startTime: 1_500_000, duration: 500_000)

        let state = controller.startSlide(clip, trackClips: [left, clip, right])

        #expect(state.clip.id == "clip-1")
        #expect(state.leftClip?.id == "left")
        #expect(state.rightClip?.id == "right")
        #expect(state.originalStartTime == 1_000_000)
    }

    @Test("Start slide with no adjacent clips")
    func startSlideNoAdjacent() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)

        let state = controller.startSlide(clip, trackClips: [clip])

        #expect(state.leftClip == nil)
        #expect(state.rightClip == nil)
    }

    // MARK: - Validate Slide

    @Test("Valid slide within bounds")
    func validateValidSlide() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)
        let left = makeClip(id: "left", startTime: 0, duration: 1_000_000)

        let state = controller.startSlide(clip, trackClips: [left, clip])
        let validation = controller.validateSlide(state, newStartTime: 800_000)

        #expect(validation.isValid)
    }

    @Test("Invalid slide past left clip")
    func validateInvalidSlideLeft() {
        let controller = SlideController()
        controller.mode = .standard
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)
        let left = makeClip(id: "left", startTime: 500_000, duration: 500_000)

        let state = controller.startSlide(clip, trackClips: [left, clip])
        let validation = controller.validateSlide(state, newStartTime: 500_000)

        #expect(!validation.isValid)
    }

    // MARK: - Calculate Slide Preview

    @Test("Slide right trims right clip")
    func slideRightTrimsRight() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)
        let right = makeClip(id: "right", startTime: 1_500_000, duration: 500_000)

        let state = controller.startSlide(clip, trackClips: [clip, right])
        let preview = controller.calculateSlidePreview(state: state, newStartTime: 1_200_000)

        #expect(preview.clipId == "clip-1")
        #expect(preview.newStartTime == 1_200_000)
        #expect(preview.rightClipNewStartTime == 1_700_000)
        #expect(preview.leftClipNewDuration == nil)
    }

    @Test("Slide left trims left clip")
    func slideLeftTrimsLeft() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)
        let left = makeClip(id: "left", startTime: 0, duration: 1_000_000)

        let state = controller.startSlide(clip, trackClips: [left, clip])
        let preview = controller.calculateSlidePreview(state: state, newStartTime: 800_000)

        #expect(preview.leftClipNewDuration == 800_000) // Trimmed by 200k
        #expect(preview.rightClipNewStartTime == nil)
    }

    @Test("Zero delta slide")
    func zeroDeltaSlide() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)

        let state = controller.startSlide(clip, trackClips: [clip])
        let preview = controller.calculateSlidePreview(state: state, newStartTime: 1_000_000)

        #expect(preview.newStartTime == 1_000_000)
        #expect(preview.leftClipNewDuration == nil)
        #expect(preview.rightClipNewStartTime == nil)
    }

    // MARK: - Apply Slide

    @Test("Apply slide moves clip")
    func applySlide() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)
        let right = makeClip(id: "right", startTime: 1_500_000, duration: 500_000)

        let state = controller.startSlide(clip, trackClips: [clip, right])
        let preview = controller.calculateSlidePreview(state: state, newStartTime: 1_200_000)
        let result = controller.applySlide([clip, right], state: state, preview: preview)

        #expect(result[0].startTime == 1_200_000) // Clip moved
    }

    // MARK: - Cancel Slide

    @Test("Cancel slide restores position")
    func cancelSlide() {
        let controller = SlideController()
        let clip = makeClip(startTime: 1_000_000, duration: 500_000)

        let state = controller.startSlide(clip, trackClips: [clip])
        let movedClip = clip.moveTo(1_200_000)
        let result = controller.cancelSlide([movedClip], state: state)

        #expect(result[0].startTime == 1_000_000)
    }

    // MARK: - Overlap Detection

    @Test("Find overlapped clips")
    func findOverlappedClips() {
        let controller = SlideController()
        let clip = makeClip(startTime: 0, duration: 500_000)
        let other = makeClip(id: "other", startTime: 400_000, duration: 500_000)

        let overlapped = controller.findOverlappedClips(
            clip: clip,
            newStartTime: 200_000,
            trackClips: [clip, other]
        )

        #expect(overlapped.contains("other"))
    }

    @Test("No overlapped clips when clear")
    func noOverlappedClips() {
        let controller = SlideController()
        let clip = makeClip(startTime: 0, duration: 500_000)
        let other = makeClip(id: "other", startTime: 2_000_000, duration: 500_000)

        let overlapped = controller.findOverlappedClips(
            clip: clip,
            newStartTime: 500_000,
            trackClips: [clip, other]
        )

        #expect(overlapped.isEmpty)
    }
}

// MARK: - SlipSlideController Tests

@Suite("SlipSlideController Tests")
@MainActor
struct SlipSlideControllerTests {

    @Test("Default mode is slip")
    func defaultMode() {
        let controller = SlipSlideController()
        #expect(controller.isSlipMode)
    }

    @Test("Toggle mode")
    func toggleMode() {
        let controller = SlipSlideController()
        controller.toggleMode()
        #expect(!controller.isSlipMode)
        controller.toggleMode()
        #expect(controller.isSlipMode)
    }

    @Test("Has slide controller")
    func hasSlideController() {
        let controller = SlipSlideController()
        #expect(controller.slide.mode == .standard)
    }
}
