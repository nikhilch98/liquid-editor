import Testing
import Foundation
@testable import LiquidEditor

// MARK: - RippleTrimMode Tests

@Suite("RippleTrimMode Tests")
struct RippleTrimModeTests {

    @Test("All cases exist")
    func allCases() {
        #expect(RippleTrimMode.allCases.count == 3)
        #expect(RippleTrimMode.allCases.contains(.none))
        #expect(RippleTrimMode.allCases.contains(.track))
        #expect(RippleTrimMode.allCases.contains(.allTracks))
    }
}

// MARK: - RippleResult Tests

@Suite("RippleResult Tests")
struct RippleResultTests {

    @Test("None result")
    func noneResult() {
        let result = RippleResult.none
        #expect(result.rippleClips.isEmpty)
        #expect(result.durationDelta == 0)
    }

    @Test("Result with clips")
    func resultWithClips() {
        let result = RippleResult(
            rippleClips: [RipplePreview(clipId: "c1", newStartTime: 500_000)],
            durationDelta: -100_000
        )
        #expect(result.rippleClips.count == 1)
        #expect(result.durationDelta == -100_000)
    }
}

// MARK: - RippleTrimController Tests

@Suite("RippleTrimController Tests")
@MainActor
struct RippleTrimControllerTests {

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

    // MARK: - Calculate Trim Preview

    @Test("Calculate trim preview - right edge extend")
    func trimPreviewRightExtend() {
        let controller = RippleTrimController()
        controller.mode = .track

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 1_000_000)

        let preview = controller.calculateTrimPreview(
            clip: clip,
            edge: .right,
            trimDelta: 200_000,
            allClips: [clip, clipB],
            trackClips: ["track-1": [clip, clipB]]
        )

        #expect(preview.clipId == "clip-1")
        #expect(preview.newDuration == 1_200_000)
        #expect(preview.trimmedDelta == 200_000)
    }

    @Test("Calculate trim preview - left edge trim")
    func trimPreviewLeftTrim() {
        let controller = RippleTrimController()
        controller.mode = .track

        let clip = makeClip(startTime: 0, duration: 1_000_000)

        let preview = controller.calculateTrimPreview(
            clip: clip,
            edge: .left,
            trimDelta: 200_000,
            allClips: [clip],
            trackClips: ["track-1": [clip]]
        )

        #expect(preview.clipId == "clip-1")
        #expect(preview.newStartTime == 200_000)
        #expect(preview.newDuration == 800_000)
    }

    @Test("Calculate trim preview - too short returns empty")
    func trimPreviewTooShort() {
        let controller = RippleTrimController()
        let clip = makeClip(startTime: 0, duration: 100_000)

        let preview = controller.calculateTrimPreview(
            clip: clip,
            edge: .left,
            trimDelta: 90_000, // would leave ~10k duration, below min
            allClips: [clip],
            trackClips: ["track-1": [clip]]
        )

        // Empty preview returned
        #expect(preview.clipId == "")
    }

    // MARK: - Ripple Modes

    @Test("Ripple mode none - no subsequent clips affected")
    func rippleModeNone() {
        let controller = RippleTrimController()
        controller.mode = .none

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 1_000_000)

        let preview = controller.calculateTrimPreview(
            clip: clip,
            edge: .right,
            trimDelta: 200_000,
            allClips: [clip, clipB],
            trackClips: ["track-1": [clip, clipB]]
        )

        #expect(preview.rippleClips == nil || preview.rippleClips!.isEmpty)
    }

    @Test("Ripple mode track - affects same track clips only")
    func rippleModeTrack() {
        let controller = RippleTrimController()
        controller.mode = .track

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 1_000_000)
        let clipC = makeClip(id: "clip-3", trackId: "track-2", startTime: 1_000_000, duration: 500_000)

        let preview = controller.calculateTrimPreview(
            clip: clip,
            edge: .right,
            trimDelta: 200_000,
            allClips: [clip, clipB, clipC],
            trackClips: [
                "track-1": [clip, clipB],
                "track-2": [clipC],
            ]
        )

        // Only clipB should be rippled (same track), not clipC
        let rippled = preview.rippleClips ?? []
        #expect(rippled.count == 1)
        #expect(rippled[0].clipId == "clip-2")
        #expect(rippled[0].newStartTime == 1_200_000)
    }

    @Test("Ripple mode all tracks - affects all tracks")
    func rippleModeAllTracks() {
        let controller = RippleTrimController()
        controller.mode = .allTracks

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 1_000_000)
        let clipC = makeClip(id: "clip-3", trackId: "track-2", startTime: 1_000_000, duration: 500_000)

        let preview = controller.calculateTrimPreview(
            clip: clip,
            edge: .right,
            trimDelta: 200_000,
            allClips: [clip, clipB, clipC],
            trackClips: [
                "track-1": [clip, clipB],
                "track-2": [clipC],
            ]
        )

        // Both clipB and clipC should be rippled
        let rippled = preview.rippleClips ?? []
        #expect(rippled.count == 2)
    }

    // MARK: - Apply Ripple Trim

    @Test("Apply ripple trim updates clips")
    func applyRippleTrim() {
        let controller = RippleTrimController()

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 500_000)

        let preview = EditTrimPreview(
            clipId: "clip-1",
            newStartTime: 0,
            newDuration: 1_200_000,
            newSourceIn: 0,
            newSourceOut: 1_200_000,
            snapGuide: nil,
            trimmedDelta: 200_000,
            rippleClips: [RipplePreview(clipId: "clip-2", newStartTime: 1_200_000)]
        )

        let result = controller.applyRippleTrim([clip, clipB], preview: preview)
        #expect(result.count == 2)
        #expect(result[0].duration == 1_200_000)
        #expect(result[1].startTime == 1_200_000)
    }

    // MARK: - Overlap Detection

    @Test("No overlap detected for valid ripple")
    func noOverlapValid() {
        let controller = RippleTrimController()

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 500_000)

        let preview = EditTrimPreview(
            clipId: "clip-1",
            newStartTime: 0,
            newDuration: 900_000,
            newSourceIn: 0,
            newSourceOut: 900_000,
            snapGuide: nil,
            trimmedDelta: -100_000,
            rippleClips: [RipplePreview(clipId: "clip-2", newStartTime: 900_000)]
        )

        let hasOverlap = controller.wouldCauseOverlap(
            clip: clip,
            preview: preview,
            trackClips: ["track-1": [clip, clipB]]
        )
        #expect(!hasOverlap)
    }

    // MARK: - Affected Clip IDs

    @Test("Get affected clip IDs in track mode")
    func affectedClipIdsTrackMode() {
        let controller = RippleTrimController()
        controller.mode = .track

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 500_000)
        let clipC = makeClip(id: "clip-3", trackId: "track-2", startTime: 1_000_000, duration: 500_000)

        let affected = controller.getAffectedClipIds(
            clip: clip,
            edge: .right,
            allClips: [clip, clipB, clipC]
        )

        #expect(affected.count == 1)
        #expect(affected[0] == "clip-2")
    }

    @Test("Get affected clip IDs in none mode returns empty")
    func affectedClipIdsNoneMode() {
        let controller = RippleTrimController()
        controller.mode = .none

        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "clip-2", startTime: 1_000_000, duration: 500_000)

        let affected = controller.getAffectedClipIds(
            clip: clip,
            edge: .right,
            allClips: [clip, clipB]
        )

        #expect(affected.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("Trim with negative start time returns empty")
    func trimNegativeStartTime() {
        let controller = RippleTrimController()
        let clip = makeClip(startTime: 100_000, duration: 1_000_000)

        let preview = controller.calculateTrimPreview(
            clip: clip,
            edge: .left,
            trimDelta: -200_000, // would make startTime negative
            allClips: [clip],
            trackClips: ["track-1": [clip]]
        )

        // Should return empty preview since new start would be -100_000
        #expect(preview.clipId == "")
    }
}
