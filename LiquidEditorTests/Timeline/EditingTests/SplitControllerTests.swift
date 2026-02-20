import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a test clip with sensible defaults.
private func makeClip(
    id: String = "clip-1",
    trackId: String = "track-1",
    startTime: TimeMicros = 0,
    duration: TimeMicros = 1_000_000,
    sourceIn: TimeMicros = 0,
    type: ClipType = .video
) -> TimelineClip {
    TimelineClip(
        id: id,
        trackId: trackId,
        type: type,
        startTime: startTime,
        duration: duration,
        sourceIn: sourceIn
    )
}

// MARK: - SplitValidation Tests

@Suite("SplitValidation Tests")
struct SplitValidationTests {

    @Test("Valid split")
    func validSplit() {
        let clip = makeClip()
        let validation = SplitValidation.valid([clip])
        #expect(validation.isValid)
        #expect(validation.error == nil)
        #expect(validation.validClips.count == 1)
    }

    @Test("Invalid split with error")
    func invalidSplit() {
        let validation = SplitValidation.invalid(.beforeClipStart)
        #expect(!validation.isValid)
        #expect(validation.error == .beforeClipStart)
        #expect(validation.validClips.isEmpty)
    }
}

// MARK: - SplitController Tests

@Suite("SplitController Tests")
struct SplitControllerTests {

    // MARK: - Validation

    @Test("Validate split at middle of clip succeeds")
    func validateSplitMiddle() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let validation = SplitController.validateSplit(clip, at: 500_000)
        #expect(validation.isValid)
        #expect(validation.validClips.count == 1)
    }

    @Test("Validate split before clip start fails")
    func validateSplitBeforeStart() {
        let clip = makeClip(startTime: 100_000, duration: 1_000_000)
        let validation = SplitController.validateSplit(clip, at: 50_000)
        #expect(!validation.isValid)
        #expect(validation.error == .beforeClipStart)
    }

    @Test("Validate split after clip end fails")
    func validateSplitAfterEnd() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let validation = SplitController.validateSplit(clip, at: 1_500_000)
        #expect(!validation.isValid)
        #expect(validation.error == .afterClipEnd)
    }

    @Test("Validate split at clip start fails")
    func validateSplitAtStart() {
        let clip = makeClip(startTime: 100_000, duration: 1_000_000)
        let validation = SplitController.validateSplit(clip, at: 100_000)
        #expect(!validation.isValid)
        #expect(validation.error == .beforeClipStart)
    }

    @Test("Validate split at clip end fails")
    func validateSplitAtEnd() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let validation = SplitController.validateSplit(clip, at: 1_000_000)
        #expect(!validation.isValid)
        #expect(validation.error == .afterClipEnd)
    }

    @Test("Validate split near boundary fails")
    func validateSplitNearBoundary() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        // Within 1ms tolerance of start
        let validation = SplitController.validateSplit(clip, at: 500)
        #expect(!validation.isValid)
        #expect(validation.error == .atClipBoundary)
    }

    @Test("Validate split resulting in too-short clips fails")
    func validateSplitTooShort() {
        let clip = makeClip(startTime: 0, duration: 50_000) // ~1.5 frames at 30fps
        // Split near start would create left clip < minDuration
        let validation = SplitController.validateSplit(clip, at: 10_000)
        #expect(!validation.isValid)
        #expect(validation.error == .clipsTooShort)
    }

    // MARK: - Single Clip Split

    @Test("Split clip at middle")
    func splitClipMiddle() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let result = SplitController.splitClip(clip, at: 500_000)

        #expect(result != nil)
        #expect(result!.leftClip.startTime == 0)
        #expect(result!.leftClip.duration == 500_000)
        #expect(result!.rightClip.startTime == 500_000)
        #expect(result!.rightClip.duration == 500_000)
    }

    @Test("Split clip preserves IDs")
    func splitClipPreservesIds() {
        let clip = makeClip(id: "original", startTime: 0, duration: 1_000_000)
        let result = SplitController.splitClip(clip, at: 500_000)

        #expect(result != nil)
        #expect(result!.leftClip.id == "original")
        #expect(result!.rightClip.id != "original")
    }

    @Test("Split invalid returns nil")
    func splitInvalidReturnsNil() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let result = SplitController.splitClip(clip, at: 2_000_000)
        #expect(result == nil)
    }

    // MARK: - Split at Playhead

    @Test("Split at playhead with all clips")
    func splitAtPlayheadAll() {
        let clips = [
            makeClip(id: "a", startTime: 0, duration: 1_000_000),
            makeClip(id: "b", startTime: 1_000_000, duration: 1_000_000),
        ]

        let result = SplitController.splitAtPlayhead(clips: clips, playheadTime: 500_000)
        #expect(result.clips.count == 1)
        #expect(result.clips[0].originalClipId == "a")
    }

    @Test("Split at playhead with selected clips only")
    func splitAtPlayheadSelected() {
        let clips = [
            makeClip(id: "a", startTime: 0, duration: 1_000_000),
            makeClip(id: "b", startTime: 0, duration: 1_000_000, type: .audio),
        ]

        let result = SplitController.splitAtPlayhead(
            clips: clips,
            playheadTime: 500_000,
            selectedClipIds: ["a"]
        )
        #expect(result.clips.count == 1)
        #expect(result.clips[0].originalClipId == "a")
    }

    @Test("Split at playhead with no clips at time")
    func splitAtPlayheadNoClips() {
        let clips = [
            makeClip(id: "a", startTime: 0, duration: 500_000),
        ]

        let result = SplitController.splitAtPlayhead(clips: clips, playheadTime: 700_000)
        #expect(result.clips.isEmpty)
    }

    // MARK: - Split All Tracks

    @Test("Split all tracks")
    func splitAllTracks() {
        let trackClips: [String: [TimelineClip]] = [
            "track-1": [makeClip(id: "a", trackId: "track-1", startTime: 0, duration: 1_000_000)],
            "track-2": [makeClip(id: "b", trackId: "track-2", startTime: 0, duration: 1_000_000)],
        ]

        let result = SplitController.splitAllTracks(trackClips: trackClips, splitTime: 500_000)
        #expect(result.clips.count == 2)
    }

    @Test("Split all tracks with gap")
    func splitAllTracksWithGap() {
        let trackClips: [String: [TimelineClip]] = [
            "track-1": [makeClip(id: "a", trackId: "track-1", startTime: 0, duration: 500_000)],
            "track-2": [makeClip(id: "b", trackId: "track-2", startTime: 600_000, duration: 500_000)],
        ]

        // Split at 300k - only track-1 clip is at that time
        let result = SplitController.splitAllTracks(trackClips: trackClips, splitTime: 300_000)
        #expect(result.clips.count == 1)
        #expect(result.clips[0].originalClipId == "a")
    }

    // MARK: - Split Single Track

    @Test("Split track")
    func splitTrack() {
        let clips = [
            makeClip(id: "a", startTime: 0, duration: 1_000_000),
            makeClip(id: "b", startTime: 1_000_000, duration: 1_000_000),
        ]

        let result = SplitController.splitTrack(clips: clips, splitTime: 1_500_000)
        #expect(result.clips.count == 1)
        #expect(result.clips[0].originalClipId == "b")
    }

    // MARK: - Find Clips at Time

    @Test("Find clips at time")
    func findClipsAtTime() {
        let clips = [
            makeClip(id: "a", startTime: 0, duration: 1_000_000),
            makeClip(id: "b", startTime: 500_000, duration: 1_000_000),
            makeClip(id: "c", startTime: 2_000_000, duration: 1_000_000),
        ]

        let found = SplitController.findClipsAtTime(clips, time: 700_000)
        #expect(found.count == 2)
        #expect(found.contains { $0.id == "a" })
        #expect(found.contains { $0.id == "b" })
    }

    @Test("Find clips at time with no matches")
    func findClipsAtTimeNoMatches() {
        let clips = [
            makeClip(id: "a", startTime: 0, duration: 500_000),
        ]

        let found = SplitController.findClipsAtTime(clips, time: 700_000)
        #expect(found.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("Split empty clip list")
    func splitEmptyList() {
        let result = SplitController.splitAtPlayhead(clips: [], playheadTime: 500_000)
        #expect(result.clips.isEmpty)
    }

    @Test("Split with empty track map")
    func splitEmptyTrackMap() {
        let result = SplitController.splitAllTracks(trackClips: [:], splitTime: 500_000)
        #expect(result.clips.isEmpty)
    }
}
