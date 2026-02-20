import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ClipType Tests

@Suite("ClipType Tests")
struct ClipTypeTests {

    @Test("showsThumbnails returns true for video and image")
    func showsThumbnails() {
        #expect(ClipType.video.showsThumbnails == true)
        #expect(ClipType.image.showsThumbnails == true)
        #expect(ClipType.audio.showsThumbnails == false)
        #expect(ClipType.text.showsThumbnails == false)
        #expect(ClipType.effect.showsThumbnails == false)
        #expect(ClipType.gap.showsThumbnails == false)
        #expect(ClipType.color.showsThumbnails == false)
    }

    @Test("showsWaveform returns true only for audio")
    func showsWaveform() {
        #expect(ClipType.audio.showsWaveform == true)
        #expect(ClipType.video.showsWaveform == false)
        #expect(ClipType.image.showsWaveform == false)
        #expect(ClipType.text.showsWaveform == false)
    }

    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(ClipType.video.rawValue == "video")
        #expect(ClipType.audio.rawValue == "audio")
        #expect(ClipType.image.rawValue == "image")
        #expect(ClipType.text.rawValue == "text")
        #expect(ClipType.effect.rawValue == "effect")
        #expect(ClipType.gap.rawValue == "gap")
        #expect(ClipType.color.rawValue == "color")
    }
}

// MARK: - TimelineClip Tests

@Suite("TimelineClip Tests")
struct TimelineClipTests {

    // MARK: - Test Helpers

    /// Creates a standard video clip for testing.
    static func makeVideoClip(
        id: String = "clip-1",
        mediaAssetId: String? = "asset-1",
        trackId: String = "track-v0",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000,
        sourceIn: TimeMicros = 0,
        sourceOut: TimeMicros? = nil,
        speed: Double = 1.0,
        isReversed: Bool = false,
        label: String? = nil,
        linkedClipId: String? = nil,
        hasEffects: Bool = false,
        effectCount: Int = 0,
        hasAudio: Bool = false,
        volume: Double = 1.0,
        isMuted: Bool = false,
        colorValue: UInt32? = nil
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            mediaAssetId: mediaAssetId,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            speed: speed,
            isReversed: isReversed,
            label: label,
            linkedClipId: linkedClipId,
            hasEffects: hasEffects,
            effectCount: effectCount,
            hasAudio: hasAudio,
            volume: volume,
            isMuted: isMuted,
            colorValue: colorValue
        )
    }

    // MARK: - Creation Tests

    @Test("Creation with minimal parameters")
    func creationMinimal() {
        let clip = TimelineClip(
            trackId: "track-v0",
            type: .video,
            startTime: 0,
            duration: 1_000_000
        )
        #expect(clip.trackId == "track-v0")
        #expect(clip.type == .video)
        #expect(clip.startTime == 0)
        #expect(clip.duration == 1_000_000)
        // Defaults
        #expect(clip.mediaAssetId == nil)
        #expect(clip.sourceIn == 0)
        #expect(clip.sourceOut == 1_000_000) // sourceIn + duration
        #expect(clip.speed == 1.0)
        #expect(clip.isReversed == false)
        #expect(clip.clipColorValue == 0xFF808080) // default gray
        #expect(clip.label == nil)
        #expect(clip.linkedClipId == nil)
        #expect(clip.isOffline == false)
        #expect(clip.hasEffects == false)
        #expect(clip.hasKeyframes == false)
        #expect(clip.effectCount == 0)
        #expect(clip.hasAudio == false)
        #expect(clip.volume == 1.0)
        #expect(clip.isMuted == false)
        #expect(clip.colorValue == nil)
    }

    @Test("Creation with all custom parameters")
    func creationFull() {
        let clip = TimelineClip(
            id: "my-clip",
            mediaAssetId: "asset-42",
            trackId: "track-v1",
            type: .audio,
            startTime: 500_000,
            duration: 2_000_000,
            sourceIn: 100_000,
            sourceOut: 2_100_000,
            speed: 1.5,
            isReversed: true,
            clipColorValue: 0xFF0000FF,
            label: "My Audio Clip",
            linkedClipId: "clip-linked",
            isOffline: true,
            hasEffects: true,
            hasKeyframes: true,
            effectCount: 3,
            hasAudio: true,
            volume: 0.75,
            isMuted: true,
            colorValue: 0xFFFF0000
        )
        #expect(clip.id == "my-clip")
        #expect(clip.mediaAssetId == "asset-42")
        #expect(clip.trackId == "track-v1")
        #expect(clip.type == .audio)
        #expect(clip.startTime == 500_000)
        #expect(clip.duration == 2_000_000)
        #expect(clip.sourceIn == 100_000)
        #expect(clip.sourceOut == 2_100_000)
        #expect(clip.speed == 1.5)
        #expect(clip.isReversed == true)
        #expect(clip.clipColorValue == 0xFF0000FF)
        #expect(clip.label == "My Audio Clip")
        #expect(clip.linkedClipId == "clip-linked")
        #expect(clip.isOffline == true)
        #expect(clip.hasEffects == true)
        #expect(clip.hasKeyframes == true)
        #expect(clip.effectCount == 3)
        #expect(clip.hasAudio == true)
        #expect(clip.volume == 0.75)
        #expect(clip.isMuted == true)
        #expect(clip.colorValue == 0xFFFF0000)
    }

    @Test("ID is auto-generated UUID when not specified")
    func autoGeneratedId() {
        let clip1 = TimelineClip(trackId: "t", type: .video, startTime: 0, duration: 1_000_000)
        let clip2 = TimelineClip(trackId: "t", type: .video, startTime: 0, duration: 1_000_000)
        #expect(!clip1.id.isEmpty)
        #expect(!clip2.id.isEmpty)
        #expect(clip1.id != clip2.id)
    }

    @Test("sourceOut defaults to sourceIn + duration when not specified")
    func sourceOutDefault() {
        let clip = TimelineClip(
            trackId: "t",
            type: .video,
            startTime: 0,
            duration: 2_000_000,
            sourceIn: 500_000
        )
        #expect(clip.sourceOut == 2_500_000) // 500_000 + 2_000_000
    }

    @Test("clipColorValue defaults to gray when not specified")
    func defaultClipColor() {
        let clip = TimelineClip(trackId: "t", type: .video, startTime: 0, duration: 1_000_000)
        #expect(clip.clipColorValue == 0xFF808080)
    }

    // MARK: - Computed Properties

    @Test("endTime is startTime + duration")
    func endTime() {
        let clip = Self.makeVideoClip(startTime: 500_000, duration: 2_000_000)
        #expect(clip.endTime == 2_500_000)
    }

    @Test("timeRange returns correct range")
    func timeRange() {
        let clip = Self.makeVideoClip(startTime: 100_000, duration: 400_000)
        let range = clip.timeRange
        #expect(range.start == 100_000)
        #expect(range.end == 500_000)
    }

    @Test("sourceDuration is sourceOut - sourceIn")
    func sourceDuration() {
        let clip = Self.makeVideoClip(sourceIn: 200_000, sourceOut: 1_200_000)
        #expect(clip.sourceDuration == 1_000_000)
    }

    @Test("isGeneratorClip returns true for gap, color, text")
    func isGeneratorClipTrue() {
        let gap = TimelineClip(trackId: "t", type: .gap, startTime: 0, duration: 1_000_000)
        let color = TimelineClip(trackId: "t", type: .color, startTime: 0, duration: 1_000_000)
        let text = TimelineClip(trackId: "t", type: .text, startTime: 0, duration: 1_000_000)
        #expect(gap.isGeneratorClip == true)
        #expect(color.isGeneratorClip == true)
        #expect(text.isGeneratorClip == true)
    }

    @Test("isGeneratorClip returns false for video, audio, image, effect")
    func isGeneratorClipFalse() {
        let video = TimelineClip(trackId: "t", type: .video, startTime: 0, duration: 1_000_000)
        let audio = TimelineClip(trackId: "t", type: .audio, startTime: 0, duration: 1_000_000)
        let image = TimelineClip(trackId: "t", type: .image, startTime: 0, duration: 1_000_000)
        let effect = TimelineClip(trackId: "t", type: .effect, startTime: 0, duration: 1_000_000)
        #expect(video.isGeneratorClip == false)
        #expect(audio.isGeneratorClip == false)
        #expect(image.isGeneratorClip == false)
        #expect(effect.isGeneratorClip == false)
    }

    // MARK: - containsTime

    @Test("containsTime inclusive start, exclusive end")
    func containsTime() {
        let clip = Self.makeVideoClip(startTime: 1_000_000, duration: 2_000_000)
        // endTime = 3_000_000
        #expect(clip.containsTime(1_000_000) == true)   // start inclusive
        #expect(clip.containsTime(2_000_000) == true)    // middle
        #expect(clip.containsTime(2_999_999) == true)    // just before end
        #expect(clip.containsTime(3_000_000) == false)   // end exclusive
        #expect(clip.containsTime(999_999) == false)     // before start
        #expect(clip.containsTime(3_000_001) == false)   // after end
    }

    // MARK: - overlapsRange

    @Test("overlapsRange detects overlap")
    func overlapsRangeTrue() {
        let clip = Self.makeVideoClip(startTime: 100, duration: 100)
        // clip range: 100-200
        let range = TimeRange(150, 250)
        #expect(clip.overlapsRange(range) == true)
    }

    @Test("overlapsRange returns false for adjacent ranges")
    func overlapsRangeFalseAdjacent() {
        let clip = Self.makeVideoClip(startTime: 100, duration: 100)
        // clip range: 100-200
        let range = TimeRange(200, 300) // starts exactly at clip end
        #expect(clip.overlapsRange(range) == false)
    }

    @Test("overlapsRange returns false for non-overlapping ranges")
    func overlapsRangeFalseDisjoint() {
        let clip = Self.makeVideoClip(startTime: 100, duration: 100)
        let range = TimeRange(300, 400)
        #expect(clip.overlapsRange(range) == false)
    }

    // MARK: - timelineToSource (normal speed, forward)

    @Test("timelineToSource at normal speed maps correctly")
    func timelineToSourceNormalSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 1_000_000,
            duration: 2_000_000,
            sourceIn: 500_000,
            sourceOut: 2_500_000
        )
        // At clip start -> sourceIn
        #expect(clip.timelineToSource(1_000_000) == 500_000)
        // At 500ms into clip -> sourceIn + 500ms
        #expect(clip.timelineToSource(1_500_000) == 1_000_000)
        // At clip end -> sourceOut
        #expect(clip.timelineToSource(3_000_000) == 2_500_000)
    }

    @Test("timelineToSource with 2x speed")
    func timelineToSourceDoubleSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000,
            speed: 2.0
        )
        // At start -> sourceIn
        #expect(clip.timelineToSource(0) == 0)
        // At 500ms into timeline -> 1000ms into source (2x speed)
        #expect(clip.timelineToSource(500_000) == 1_000_000)
        // At clip end -> 2000ms into source
        #expect(clip.timelineToSource(1_000_000) == 2_000_000)
    }

    @Test("timelineToSource with 0.5x speed")
    func timelineToSourceHalfSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 2_000_000,
            sourceIn: 0,
            sourceOut: 1_000_000,
            speed: 0.5
        )
        // At start -> sourceIn
        #expect(clip.timelineToSource(0) == 0)
        // At 1000ms in timeline -> 500ms in source (0.5x speed)
        #expect(clip.timelineToSource(1_000_000) == 500_000)
    }

    @Test("timelineToSource reversed")
    func timelineToSourceReversed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 1_000_000,
            isReversed: true
        )
        // At start -> sourceOut (reversed plays from end)
        #expect(clip.timelineToSource(0) == 1_000_000)
        // At 500ms -> 500ms from end
        #expect(clip.timelineToSource(500_000) == 500_000)
        // At end -> sourceIn
        #expect(clip.timelineToSource(1_000_000) == 0)
    }

    @Test("timelineToSource reversed with 2x speed")
    func timelineToSourceReversedDoubleSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000,
            speed: 2.0,
            isReversed: true
        )
        // At start -> sourceOut
        #expect(clip.timelineToSource(0) == 2_000_000)
        // At 500ms in timeline -> 1000ms of source consumed -> sourceOut - 1000ms
        #expect(clip.timelineToSource(500_000) == 1_000_000)
    }

    // MARK: - sourceToTimeline

    @Test("sourceToTimeline at normal speed maps correctly")
    func sourceToTimelineNormalSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 1_000_000,
            duration: 2_000_000,
            sourceIn: 500_000,
            sourceOut: 2_500_000
        )
        // sourceIn -> clip start
        #expect(clip.sourceToTimeline(500_000) == 1_000_000)
        // 500ms into source -> 500ms into timeline
        #expect(clip.sourceToTimeline(1_000_000) == 1_500_000)
        // sourceOut -> clip end
        #expect(clip.sourceToTimeline(2_500_000) == 3_000_000)
    }

    @Test("sourceToTimeline with 2x speed")
    func sourceToTimelineDoubleSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000,
            speed: 2.0
        )
        // 1000ms in source -> 500ms in timeline (at 2x)
        #expect(clip.sourceToTimeline(1_000_000) == 500_000)
    }

    @Test("sourceToTimeline reversed")
    func sourceToTimelineReversed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 1_000_000,
            isReversed: true
        )
        // sourceOut -> start of timeline (reversed starts from out)
        #expect(clip.sourceToTimeline(1_000_000) == 0)
        // sourceIn -> end of timeline
        #expect(clip.sourceToTimeline(0) == 1_000_000)
    }

    @Test("timelineToSource and sourceToTimeline are inverses")
    func timeSourceRoundtrip() {
        let clip = Self.makeVideoClip(
            startTime: 1_000_000,
            duration: 2_000_000,
            sourceIn: 500_000,
            sourceOut: 2_500_000,
            speed: 1.5
        )
        let timelineTime: TimeMicros = 1_500_000
        let sourceTime = clip.timelineToSource(timelineTime)
        let roundtrip = clip.sourceToTimeline(sourceTime)
        // Allow 1 microsecond rounding tolerance
        #expect(abs(roundtrip - timelineTime) <= 1)
    }

    @Test("timelineToSource and sourceToTimeline roundtrip with reversed")
    func timeSourceRoundtripReversed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000,
            speed: 2.0,
            isReversed: true
        )
        let timelineTime: TimeMicros = 250_000
        let sourceTime = clip.timelineToSource(timelineTime)
        let roundtrip = clip.sourceToTimeline(sourceTime)
        #expect(abs(roundtrip - timelineTime) <= 1)
    }

    // MARK: - Edit Operations: moveTo

    @Test("moveTo changes startTime")
    func moveTo() {
        let clip = Self.makeVideoClip(startTime: 0, duration: 1_000_000)
        let moved = clip.moveTo(500_000)
        #expect(moved.startTime == 500_000)
        #expect(moved.duration == 1_000_000) // duration unchanged
        #expect(moved.id == clip.id) // identity preserved
    }

    // MARK: - Edit Operations: moveBy

    @Test("moveBy shifts startTime by delta")
    func moveBy() {
        let clip = Self.makeVideoClip(startTime: 1_000_000, duration: 1_000_000)
        let moved = clip.moveBy(500_000)
        #expect(moved.startTime == 1_500_000)
    }

    @Test("moveBy with negative delta")
    func moveByNegative() {
        let clip = Self.makeVideoClip(startTime: 1_000_000, duration: 1_000_000)
        let moved = clip.moveBy(-500_000)
        #expect(moved.startTime == 500_000)
    }

    // MARK: - Edit Operations: moveToTrack

    @Test("moveToTrack changes trackId")
    func moveToTrack() {
        let clip = Self.makeVideoClip(trackId: "track-v0")
        let moved = clip.moveToTrack("track-v1")
        #expect(moved.trackId == "track-v1")
        #expect(moved.startTime == clip.startTime) // position unchanged
        #expect(moved.id == clip.id)
    }

    // MARK: - Edit Operations: trimHead

    @Test("trimHead shrinks clip from the beginning")
    func trimHeadShrink() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 2_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000
        )
        let trimmed = clip.trimHead(500_000)
        #expect(trimmed.startTime == 500_000)
        #expect(trimmed.duration == 1_500_000)
        #expect(trimmed.sourceIn == 500_000) // source in shifts
        #expect(trimmed.sourceOut == 2_000_000) // source out unchanged
    }

    @Test("trimHead extends clip backward")
    func trimHeadExtend() {
        let clip = Self.makeVideoClip(
            startTime: 500_000,
            duration: 1_000_000,
            sourceIn: 500_000,
            sourceOut: 1_500_000
        )
        let extended = clip.trimHead(200_000) // extend left by 300ms
        #expect(extended.startTime == 200_000)
        #expect(extended.duration == 1_300_000)
        #expect(extended.sourceIn == 200_000) // source in shifts earlier
    }

    @Test("trimHead refuses to extend beyond source start")
    func trimHeadRefusesBeyondSource() {
        let clip = Self.makeVideoClip(
            startTime: 500_000,
            duration: 1_000_000,
            sourceIn: 100_000,  // only 100ms of media before sourceIn
            sourceOut: 1_100_000
        )
        // Try to extend by 500ms (would make sourceIn = -400_000)
        let result = clip.trimHead(0)
        // Should return self unchanged since newSourceIn would be negative
        #expect(result == clip)
    }

    @Test("trimHead refuses to trim below minimum duration")
    func trimHeadMinDuration() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 100_000, // 100ms, close to minimum
            sourceIn: 0,
            sourceOut: 100_000
        )
        // trimming to 90_000 leaves only 10_000 duration (< 33_333 min)
        let result = clip.trimHead(90_000)
        #expect(result == clip) // unchanged
    }

    @Test("trimHead with speed adjustment scales source delta")
    func trimHeadWithSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 2_000_000,
            sourceIn: 0,
            sourceOut: 4_000_000,
            speed: 2.0
        )
        let trimmed = clip.trimHead(500_000) // trim 500ms from head
        #expect(trimmed.startTime == 500_000)
        #expect(trimmed.duration == 1_500_000)
        // At 2x speed, 500ms of timeline = 1000ms of source
        #expect(trimmed.sourceIn == 1_000_000)
    }

    // MARK: - Edit Operations: trimTail

    @Test("trimTail shrinks clip from the end")
    func trimTailShrink() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 2_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000
        )
        let trimmed = clip.trimTail(1_500_000) // new end time
        #expect(trimmed.startTime == 0)
        #expect(trimmed.duration == 1_500_000)
        #expect(trimmed.sourceOut == 1_500_000)
    }

    @Test("trimTail refuses to trim below minimum duration")
    func trimTailMinDuration() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 1_000_000
        )
        // Try to make duration just 10_000 (< 33_333 min)
        let result = clip.trimTail(10_000)
        #expect(result == clip) // unchanged
    }

    @Test("trimTail with speed adjustment")
    func trimTailWithSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 2_000_000,
            sourceIn: 0,
            sourceOut: 4_000_000,
            speed: 2.0
        )
        let trimmed = clip.trimTail(1_000_000) // new end at 1s
        #expect(trimmed.duration == 1_000_000)
        // At 2x speed, 1000ms of timeline = 2000ms of source
        #expect(trimmed.sourceOut == 2_000_000)
    }

    // MARK: - Edit Operations: slip

    @Test("slip shifts source range without changing timeline position")
    func slipBasic() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 500_000,
            sourceOut: 1_500_000
        )
        let slipped = clip.slip(200_000)
        #expect(slipped.startTime == 0) // unchanged
        #expect(slipped.duration == 1_000_000) // unchanged
        #expect(slipped.sourceIn == 700_000)
        #expect(slipped.sourceOut == 1_700_000)
    }

    @Test("slip negative delta")
    func slipNegative() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 500_000,
            sourceOut: 1_500_000
        )
        let slipped = clip.slip(-200_000)
        #expect(slipped.sourceIn == 300_000)
        #expect(slipped.sourceOut == 1_300_000)
    }

    @Test("slip refuses to go before source start")
    func slipRefusesBeyondStart() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 100_000,
            sourceOut: 1_100_000
        )
        // Slip by -200_000 would make sourceIn = -100_000
        let result = clip.slip(-200_000)
        #expect(result == clip) // unchanged
    }

    // MARK: - Edit Operations: splitAt

    @Test("splitAt creates two clips")
    func splitAtBasic() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 2_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000
        )
        let result = clip.splitAt(1_000_000, rightClipId: "right-id")
        #expect(result != nil)

        let left = result!.left
        let right = result!.right

        // Left clip
        #expect(left.id == clip.id)
        #expect(left.startTime == 0)
        #expect(left.duration == 1_000_000)
        #expect(left.sourceIn == 0)
        #expect(left.sourceOut == 1_000_000)

        // Right clip
        #expect(right.id == "right-id")
        #expect(right.startTime == 1_000_000)
        #expect(right.duration == 1_000_000)
        #expect(right.sourceIn == 1_000_000)
        #expect(right.sourceOut == 2_000_000)
    }

    @Test("splitAt returns nil when split at start")
    func splitAtStart() {
        let clip = Self.makeVideoClip(startTime: 0, duration: 1_000_000)
        let result = clip.splitAt(0, rightClipId: "r")
        #expect(result == nil)
    }

    @Test("splitAt returns nil when split at end")
    func splitAtEnd() {
        let clip = Self.makeVideoClip(startTime: 0, duration: 1_000_000)
        let result = clip.splitAt(1_000_000, rightClipId: "r")
        #expect(result == nil)
    }

    @Test("splitAt returns nil when split outside range")
    func splitAtOutside() {
        let clip = Self.makeVideoClip(startTime: 100, duration: 100)
        #expect(clip.splitAt(50, rightClipId: "r") == nil)
        #expect(clip.splitAt(300, rightClipId: "r") == nil)
    }

    @Test("splitAt preserves total duration")
    func splitAtPreservesTotalDuration() {
        let clip = Self.makeVideoClip(
            startTime: 500_000,
            duration: 3_000_000,
            sourceIn: 100_000,
            sourceOut: 3_100_000
        )
        let result = clip.splitAt(1_500_000, rightClipId: "right")!
        let totalDuration = result.left.duration + result.right.duration
        #expect(totalDuration == clip.duration)
    }

    @Test("splitAt with speed produces correct source points")
    func splitAtWithSpeed() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 2_000_000,
            speed: 2.0
        )
        let result = clip.splitAt(500_000, rightClipId: "r")!
        // At 2x speed, 500ms timeline = 1000ms source
        #expect(result.left.sourceOut == 1_000_000)
        #expect(result.right.sourceIn == 1_000_000)
    }

    // MARK: - Edit Operations: withSpeed

    @Test("withSpeed adjusts duration proportionally")
    func withSpeedBasic() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 1_000_000
        )
        let fast = clip.withSpeed(2.0)
        #expect(fast.speed == 2.0)
        // sourceDuration = 1_000_000; at 2x -> 500ms timeline
        #expect(fast.duration == 500_000)
    }

    @Test("withSpeed halves the speed doubles the duration")
    func withSpeedHalf() {
        let clip = Self.makeVideoClip(
            startTime: 0,
            duration: 1_000_000,
            sourceIn: 0,
            sourceOut: 1_000_000
        )
        let slow = clip.withSpeed(0.5)
        #expect(slow.speed == 0.5)
        #expect(slow.duration == 2_000_000) // source / 0.5 = 2x
    }

    @Test("withSpeed rejects zero speed")
    func withSpeedZero() {
        let clip = Self.makeVideoClip()
        let result = clip.withSpeed(0.0)
        #expect(result == clip) // unchanged
    }

    @Test("withSpeed rejects negative speed")
    func withSpeedNegative() {
        let clip = Self.makeVideoClip()
        let result = clip.withSpeed(-1.0)
        #expect(result == clip) // unchanged
    }

    // MARK: - Edit Operations: toggleReverse

    @Test("toggleReverse flips isReversed")
    func toggleReverse() {
        let clip = Self.makeVideoClip(isReversed: false)
        let reversed = clip.toggleReverse()
        #expect(reversed.isReversed == true)

        let back = reversed.toggleReverse()
        #expect(back.isReversed == false)
    }

    // MARK: - with() Copy Method

    @Test("with() preserves all values when no changes specified")
    func withNoChanges() {
        let clip = Self.makeVideoClip(
            id: "c1",
            mediaAssetId: "a1",
            trackId: "t1",
            startTime: 100,
            duration: 200,
            sourceIn: 50,
            sourceOut: 250,
            speed: 1.5,
            isReversed: true,
            label: "Test",
            linkedClipId: "linked"
        )
        let copy = clip.with()
        #expect(copy == clip)
    }

    @Test("with() changes only specified values")
    func withPartialChanges() {
        let clip = Self.makeVideoClip(
            id: "c1",
            trackId: "t1",
            startTime: 100,
            duration: 200,
            label: "Original"
        )
        let updated = clip.with(startTime: 500, label: "Updated")
        #expect(updated.id == "c1")
        #expect(updated.trackId == "t1")
        #expect(updated.startTime == 500)
        #expect(updated.duration == 200)
        #expect(updated.label == "Updated")
    }

    @Test("with() clearMediaAssetId sets it to nil")
    func withClearMediaAssetId() {
        let clip = Self.makeVideoClip(mediaAssetId: "asset-1")
        let cleared = clip.with(clearMediaAssetId: true)
        #expect(cleared.mediaAssetId == nil)
    }

    @Test("with() clearLabel sets it to nil")
    func withClearLabel() {
        let clip = Self.makeVideoClip(label: "My Label")
        let cleared = clip.with(clearLabel: true)
        #expect(cleared.label == nil)
    }

    @Test("with() clearLinkedClipId sets it to nil")
    func withClearLinkedClipId() {
        let clip = Self.makeVideoClip(linkedClipId: "linked-1")
        let cleared = clip.with(clearLinkedClipId: true)
        #expect(cleared.linkedClipId == nil)
    }

    @Test("with() clearColorValue sets it to nil")
    func withClearColorValue() {
        let clip = Self.makeVideoClip(colorValue: 0xFF0000FF)
        let cleared = clip.with(clearColorValue: true)
        #expect(cleared.colorValue == nil)
    }

    @Test("with() clear flag overrides new value")
    func withClearOverridesNewValue() {
        let clip = Self.makeVideoClip(label: "old")
        // clearLabel should win even if a new label is provided
        let result = clip.with(label: "new", clearLabel: true)
        #expect(result.label == nil)
    }

    // MARK: - Codable Roundtrip

    @Test("Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let clip = TimelineClip(
            id: "codec-test",
            mediaAssetId: "asset-99",
            trackId: "track-v0",
            type: .video,
            startTime: 1_000_000,
            duration: 2_000_000,
            sourceIn: 500_000,
            sourceOut: 2_500_000,
            speed: 1.5,
            isReversed: true,
            clipColorValue: 0xFF00FF00,
            label: "Test Clip",
            linkedClipId: "linked-42",
            isOffline: true,
            hasEffects: true,
            hasKeyframes: true,
            effectCount: 5,
            hasAudio: true,
            volume: 0.8,
            isMuted: true,
            colorValue: 0xFFFF0000
        )

        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(TimelineClip.self, from: data)

        #expect(decoded.id == clip.id)
        #expect(decoded.mediaAssetId == clip.mediaAssetId)
        #expect(decoded.trackId == clip.trackId)
        #expect(decoded.type == clip.type)
        #expect(decoded.startTime == clip.startTime)
        #expect(decoded.duration == clip.duration)
        #expect(decoded.sourceIn == clip.sourceIn)
        #expect(decoded.sourceOut == clip.sourceOut)
        #expect(decoded.speed == clip.speed)
        #expect(decoded.isReversed == clip.isReversed)
        #expect(decoded.clipColorValue == clip.clipColorValue)
        #expect(decoded.label == clip.label)
        #expect(decoded.linkedClipId == clip.linkedClipId)
        #expect(decoded.isOffline == clip.isOffline)
        #expect(decoded.hasEffects == clip.hasEffects)
        #expect(decoded.hasKeyframes == clip.hasKeyframes)
        #expect(decoded.effectCount == clip.effectCount)
        #expect(decoded.hasAudio == clip.hasAudio)
        #expect(decoded.volume == clip.volume)
        #expect(decoded.isMuted == clip.isMuted)
        #expect(decoded.colorValue == clip.colorValue)
    }

    @Test("Codable roundtrip with nil optional fields")
    func codableRoundtripNils() throws {
        let clip = TimelineClip(
            id: "nil-test",
            trackId: "track-v0",
            type: .audio,
            startTime: 0,
            duration: 500_000
        )

        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(TimelineClip.self, from: data)

        #expect(decoded.mediaAssetId == nil)
        #expect(decoded.label == nil)
        #expect(decoded.linkedClipId == nil)
        #expect(decoded.colorValue == nil)
        #expect(decoded.speed == 1.0)
        #expect(decoded.isReversed == false)
        #expect(decoded.isOffline == false)
    }

    @Test("Codable roundtrip equality")
    func codableEquality() throws {
        let clip = Self.makeVideoClip(
            id: "eq-test",
            startTime: 500_000,
            duration: 1_500_000,
            sourceIn: 200_000,
            sourceOut: 1_700_000
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(TimelineClip.self, from: data)
        #expect(decoded == clip)
    }

    @Test("JSON uses correct coding keys")
    func jsonCodingKeys() throws {
        let clip = Self.makeVideoClip(
            id: "key-test",
            startTime: 100,
            duration: 200
        )
        let data = try JSONEncoder().encode(clip)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Check key names
        #expect(json["id"] != nil)
        #expect(json["trackId"] != nil)
        #expect(json["type"] != nil)
        #expect(json["startTime"] != nil)
        #expect(json["duration"] != nil)
        #expect(json["sourceIn"] != nil)
        #expect(json["sourceOut"] != nil)
        #expect(json["speed"] != nil)
        #expect(json["isReversed"] != nil)
        #expect(json["clipColor"] != nil)  // Note: coded as "clipColor"
        #expect(json["isOffline"] != nil)
    }

    // MARK: - Hashable

    @Test("Hash function uses id, trackId, type, startTime, duration")
    func hashFunction() {
        let clip1 = Self.makeVideoClip(id: "c1", trackId: "t1", startTime: 100, duration: 200)
        let clip2 = Self.makeVideoClip(id: "c1", trackId: "t1", startTime: 100, duration: 200)
        #expect(clip1.hashValue == clip2.hashValue)
    }

    @Test("Different clips produce different hashes")
    func hashDiffers() {
        let clip1 = Self.makeVideoClip(id: "c1", startTime: 100, duration: 200)
        let clip2 = Self.makeVideoClip(id: "c2", startTime: 100, duration: 200)
        // Different ids -> likely different hash (not guaranteed but highly probable)
        #expect(clip1.hashValue != clip2.hashValue)
    }

    @Test("Clips can be used in Set")
    func setUsage() {
        let clip1 = Self.makeVideoClip(id: "c1")
        let clip2 = Self.makeVideoClip(id: "c2")
        let clip3 = Self.makeVideoClip(id: "c1") // same id as clip1
        var clipSet: Set<TimelineClip> = [clip1, clip2]
        #expect(clipSet.count == 2)
        clipSet.insert(clip3)
        // clip3 has same hash components as clip1 but may differ in other fields.
        // Equatable uses all fields, so if truly equal it's 2, otherwise 3.
        // Here clip1 and clip3 have same mediaAssetId, same defaults.
        #expect(clipSet.count == 2)
    }

    // MARK: - Identifiable

    @Test("Identifiable id property")
    func identifiable() {
        let clip = Self.makeVideoClip(id: "ident-test")
        #expect(clip.id == "ident-test")
    }

    // MARK: - Min Duration Constant

    @Test("minDuration is approximately one frame at 30fps")
    func minDurationValue() {
        #expect(TimelineClip.minDuration == 33_333)
    }

    // MARK: - Equatable

    @Test("Equal clips are equal")
    func equalityTrue() {
        let clip1 = Self.makeVideoClip(id: "eq", startTime: 100, duration: 200)
        let clip2 = Self.makeVideoClip(id: "eq", startTime: 100, duration: 200)
        #expect(clip1 == clip2)
    }

    @Test("Different clips are not equal")
    func equalityFalse() {
        let clip1 = Self.makeVideoClip(id: "a", startTime: 100, duration: 200)
        let clip2 = Self.makeVideoClip(id: "b", startTime: 100, duration: 200)
        #expect(clip1 != clip2)
    }

    // MARK: - Edge Cases

    @Test("Zero duration clip")
    func zeroDuration() {
        let clip = Self.makeVideoClip(startTime: 0, duration: 0)
        #expect(clip.endTime == 0)
        #expect(clip.sourceDuration == 0)
        #expect(clip.containsTime(0) == false) // start >= 0 && time < 0 is false
    }

    @Test("Very large time values")
    func largeTimeValues() {
        let startTime: TimeMicros = 3_600_000_000 // 1 hour in microseconds
        let duration: TimeMicros = 7_200_000_000  // 2 hours
        let clip = Self.makeVideoClip(startTime: startTime, duration: duration)
        #expect(clip.endTime == 10_800_000_000) // 3 hours
    }

    @Test("Sendable conformance allows cross-actor use")
    func sendableConformance() async {
        let clip = Self.makeVideoClip(id: "sendable-test")
        let result = await Task.detached { clip.id }.value
        #expect(result == "sendable-test")
    }
}
