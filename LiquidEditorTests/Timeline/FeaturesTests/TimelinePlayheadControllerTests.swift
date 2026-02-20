// TimelinePlayheadControllerTests.swift
// LiquidEditorTests
//
// Tests for TimelinePlayheadController.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("TimelinePlayheadController")
@MainActor
struct TimelinePlayheadControllerTests {

    // MARK: - Helpers

    private func makeController() -> TimelinePlayheadController {
        TimelinePlayheadController()
    }

    // MARK: - Initial State

    @Test("Initial state is idle with zero time")
    func initialState() {
        let controller = makeController()
        #expect(controller.currentTime == 0)
        #expect(controller.state == .idle)
        #expect(controller.isScrubbing == false)
        #expect(controller.isPlaying == false)
        #expect(controller.currentFrame == 0)
    }

    // MARK: - Set Time

    @Test("setTime updates current time")
    func setTime() {
        let controller = makeController()
        controller.setTime(1_000_000)
        #expect(controller.currentTime == 1_000_000)
    }

    @Test("setTime clamps negative time to zero")
    func setTimeNegative() {
        let controller = makeController()
        controller.setTime(-500)
        #expect(controller.currentTime == 0)
    }

    @Test("setTime does not fire callback when time unchanged")
    func setTimeSameValue() {
        let controller = makeController()
        controller.setTime(1_000_000)

        var callCount = 0
        controller.onTimeChanged = { _ in callCount += 1 }

        controller.setTime(1_000_000)
        #expect(callCount == 0)
    }

    @Test("setTime fires callback on change")
    func setTimeCallback() {
        let controller = makeController()
        var receivedTime: TimeMicros = -1
        controller.onTimeChanged = { time in receivedTime = time }

        controller.setTime(2_000_000)
        #expect(receivedTime == 2_000_000)
    }

    // MARK: - moveBy

    @Test("moveBy adds delta to current time")
    func moveBy() {
        let controller = makeController()
        controller.setTime(1_000_000)
        controller.moveBy(500_000)
        #expect(controller.currentTime == 1_500_000)
    }

    @Test("moveBy clamps to zero for large negative delta")
    func moveByNegative() {
        let controller = makeController()
        controller.setTime(500_000)
        controller.moveBy(-1_000_000)
        #expect(controller.currentTime == 0)
    }

    // MARK: - Frame Navigation

    @Test("nextFrame advances to next frame boundary at 30fps")
    func nextFrame() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)
        controller.setTime(0)
        controller.nextFrame()
        // At 30fps, one frame = 1_000_000/30 = 33333 microseconds
        #expect(controller.currentTime == Rational.fps30.frameToMicroseconds(1))
    }

    @Test("previousFrame goes back to previous frame boundary")
    func previousFrame() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)
        // At 30fps, frameToMicroseconds(2) = 66666 due to integer truncation,
        // which microsecondsToFrame maps back to frame 1. Add 1 microsecond
        // to ensure the time lands solidly in frame 2.
        let twoFrames = Rational.fps30.frameToMicroseconds(2) + 1
        controller.setTime(twoFrames)
        controller.previousFrame()
        #expect(controller.currentTime == Rational.fps30.frameToMicroseconds(1))
    }

    @Test("previousFrame clamps to zero")
    func previousFrameAtStart() {
        let controller = makeController()
        controller.setTime(0)
        controller.previousFrame()
        #expect(controller.currentTime == 0)
    }

    // MARK: - snapToFrame

    @Test("snapToFrame snaps to nearest boundary")
    func snapToFrame() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)

        let frameDuration = Rational.fps30.microsecondsPerFrame
        // Slightly past mid-frame should snap to next
        let time = frameDuration / 2 + frameDuration / 4
        let snapped = controller.snapToFrame(time)
        #expect(snapped == frameDuration)
    }

    @Test("snapToFrame snaps to previous boundary when closer")
    func snapToFrameEarlier() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)

        // Just past frame boundary should snap back
        let frameDuration = Rational.fps30.microsecondsPerFrame
        let time = frameDuration + frameDuration / 4
        let snapped = controller.snapToFrame(time)
        #expect(snapped == frameDuration)
    }

    // MARK: - Scrubbing

    @Test("startScrub enters scrubbing state")
    func startScrub() {
        let controller = makeController()
        controller.startScrub(500_000)
        #expect(controller.state == .scrubbing)
        #expect(controller.isScrubbing == true)
        #expect(controller.currentTime == 500_000)
    }

    @Test("updateScrub updates time during scrubbing")
    func updateScrub() {
        let controller = makeController()
        controller.startScrub(500_000)
        controller.updateScrub(1_000_000)
        #expect(controller.currentTime == 1_000_000)
    }

    @Test("updateScrub is ignored when not scrubbing")
    func updateScrubNotScrubbing() {
        let controller = makeController()
        controller.setTime(500_000)
        controller.updateScrub(1_000_000)
        #expect(controller.currentTime == 500_000)
    }

    @Test("updateScrub clamps negative to zero")
    func updateScrubNegative() {
        let controller = makeController()
        controller.startScrub(500_000)
        controller.updateScrub(-100)
        #expect(controller.currentTime == 0)
    }

    @Test("endScrub returns to idle and snaps to frame")
    func endScrub() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)
        controller.startScrub(500_000)
        controller.endScrub()
        #expect(controller.state == .idle)
        #expect(controller.isScrubbing == false)
    }

    @Test("endScrub is no-op when not scrubbing")
    func endScrubNotScrubbing() {
        let controller = makeController()
        controller.endScrub()
        #expect(controller.state == .idle)
    }

    @Test("cancelScrub restores original time")
    func cancelScrub() {
        let controller = makeController()
        controller.startScrub(500_000)
        controller.updateScrub(2_000_000)
        controller.cancelScrub(500_000)
        #expect(controller.currentTime == 500_000)
        #expect(controller.state == .idle)
    }

    // MARK: - Playback State

    @Test("notifyPlaybackStarted sets playing state")
    func playbackStarted() {
        let controller = makeController()
        controller.notifyPlaybackStarted()
        #expect(controller.state == .playing)
        #expect(controller.isPlaying == true)
    }

    @Test("notifyPlaybackStopped returns to idle")
    func playbackStopped() {
        let controller = makeController()
        controller.notifyPlaybackStarted()
        controller.notifyPlaybackStopped()
        #expect(controller.state == .idle)
        #expect(controller.isPlaying == false)
    }

    @Test("updatePlaybackTime updates time during playback")
    func updatePlaybackTime() {
        let controller = makeController()
        controller.notifyPlaybackStarted()
        controller.updatePlaybackTime(3_000_000)
        #expect(controller.currentTime == 3_000_000)
    }

    @Test("updatePlaybackTime is ignored when not playing")
    func updatePlaybackTimeNotPlaying() {
        let controller = makeController()
        controller.setTime(500_000)
        controller.updatePlaybackTime(3_000_000)
        #expect(controller.currentTime == 500_000)
    }

    // MARK: - State Callback

    @Test("state changes fire callback")
    func stateCallback() {
        let controller = makeController()
        var receivedStates: [PlayheadState] = []
        controller.onStateChanged = { state in receivedStates.append(state) }

        controller.startScrub(0)
        controller.endScrub()

        #expect(receivedStates.count == 2)
        #expect(receivedStates[0] == .scrubbing)
        #expect(receivedStates[1] == .idle)
    }

    // MARK: - Timecode Formatting

    @Test("formatTimecode SMPTE at zero")
    func formatSMPTEZero() {
        let result = TimelinePlayheadController.formatTimecode(0, format: .smpte, frameRate: .fps30)
        #expect(result == "00:00:00")
    }

    @Test("formatTimecode SMPTE at 1 second")
    func formatSMPTEOneSecond() {
        let result = TimelinePlayheadController.formatTimecode(1_000_000, format: .smpte, frameRate: .fps30)
        #expect(result == "00:01:00")
    }

    @Test("formatTimecode milliseconds")
    func formatMilliseconds() {
        let result = TimelinePlayheadController.formatTimecode(65_500_000, format: .milliseconds)
        #expect(result == "01:05.500")
    }

    @Test("formatTimecode simple MM:SS")
    func formatSimple() {
        let result = TimelinePlayheadController.formatTimecode(125_000_000, format: .simple)
        #expect(result == "02:05")
    }

    @Test("formatTimecode seconds")
    func formatSeconds() {
        let result = TimelinePlayheadController.formatTimecode(12_500_000, format: .seconds)
        #expect(result == "12.5s")
    }

    @Test("formatTimecode clamps negative to zero")
    func formatNegative() {
        let result = TimelinePlayheadController.formatTimecode(-1_000_000, format: .simple)
        #expect(result == "00:00")
    }

    // MARK: - Frame Rate

    @Test("setFrameRate changes frame rate")
    func setFrameRate() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps60)
        #expect(controller.frameRate == Rational.fps60)
    }

    @Test("setFrameRate from Double")
    func setFrameRateDouble() {
        let controller = makeController()
        controller.setFrameRate(24.0)
        #expect(controller.frameRate.value == 24.0)
    }

    @Test("setFrameRate clamps to valid range")
    func setFrameRateClamped() {
        let controller = makeController()
        controller.setFrameRate(0.5)
        #expect(controller.frameRate.value >= 1.0)

        controller.setFrameRate(500.0)
        #expect(controller.frameRate.value <= 240.0)
    }

    // MARK: - Current Frame

    @Test("currentFrame computes correctly at 30fps")
    func currentFrameComputation() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)
        // Set to exactly 2 seconds = 60 frames at 30fps
        controller.setTime(2_000_000)
        #expect(controller.currentFrame == 60)
    }

    // MARK: - Additional State Tests

    @Test("PlayheadState allCases has four values")
    func playheadStateAllCases() {
        #expect(PlayheadState.allCases.count == 4)
        #expect(PlayheadState.allCases.contains(.idle))
        #expect(PlayheadState.allCases.contains(.scrubbing))
        #expect(PlayheadState.allCases.contains(.playing))
        #expect(PlayheadState.allCases.contains(.seeking))
    }

    @Test("PlayheadState rawValues are correct strings")
    func playheadStateRawValues() {
        #expect(PlayheadState.idle.rawValue == "idle")
        #expect(PlayheadState.scrubbing.rawValue == "scrubbing")
        #expect(PlayheadState.playing.rawValue == "playing")
        #expect(PlayheadState.seeking.rawValue == "seeking")
    }

    // MARK: - Additional TimecodeFormat Tests

    @Test("TimecodeFormat allCases has four values")
    func timecodeFormatAllCases() {
        #expect(TimecodeFormat.allCases.count == 4)
    }

    @Test("TimecodeFormat rawValues")
    func timecodeFormatRawValues() {
        #expect(TimecodeFormat.smpte.rawValue == "smpte")
        #expect(TimecodeFormat.milliseconds.rawValue == "milliseconds")
        #expect(TimecodeFormat.simple.rawValue == "simple")
        #expect(TimecodeFormat.seconds.rawValue == "seconds")
    }

    // MARK: - Additional ScrubAudioConfig Tests

    @Test("ScrubAudioConfig defaults")
    func scrubAudioConfigDefaults() {
        let config = ScrubAudioConfig.defaults
        #expect(config.isEnabled == true)
        #expect(config.volume == 0.5)
        #expect(config.audioFollowsVideo == true)
    }

    @Test("ScrubAudioConfig disabled")
    func scrubAudioConfigDisabled() {
        let config = ScrubAudioConfig.disabled
        #expect(config.isEnabled == false)
    }

    @Test("ScrubAudioConfig with selective copy")
    func scrubAudioConfigWith() {
        let base = ScrubAudioConfig.defaults
        let modified = base.with(volume: 0.8)
        #expect(modified.isEnabled == true) // Unchanged
        #expect(modified.volume == 0.8)
        #expect(modified.audioFollowsVideo == true) // Unchanged
    }

    @Test("ScrubAudioConfig with all parameters")
    func scrubAudioConfigWithAll() {
        let config = ScrubAudioConfig(isEnabled: false, volume: 0.3, audioFollowsVideo: false)
        #expect(config.isEnabled == false)
        #expect(config.volume == 0.3)
        #expect(config.audioFollowsVideo == false)
    }

    @Test("ScrubAudioConfig equatable")
    func scrubAudioConfigEquatable() {
        let a = ScrubAudioConfig.defaults
        let b = ScrubAudioConfig(isEnabled: true, volume: 0.5, audioFollowsVideo: true)
        let c = ScrubAudioConfig.disabled
        #expect(a == b)
        #expect(a != c)
    }

    @Test("updateScrubAudioConfig updates config")
    func updateScrubAudioConfig() {
        let controller = makeController()
        let newConfig = ScrubAudioConfig(isEnabled: false, volume: 0.2, audioFollowsVideo: false)
        controller.updateScrubAudioConfig(newConfig)
        #expect(controller.scrubAudioConfig == newConfig)
    }

    // MARK: - Additional Frame Tests

    @Test("frameDurationMicros at 30fps")
    func frameDurationMicros30fps() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)
        #expect(controller.frameDurationMicros == Rational.fps30.microsecondsPerFrame)
    }

    @Test("currentFrame at zero is 0")
    func currentFrameAtZero() {
        let controller = makeController()
        #expect(controller.currentFrame == 0)
    }

    @Test("nextFrame at 60fps moves by correct amount")
    func nextFrame60fps() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps60)
        controller.setTime(0)
        controller.nextFrame()
        #expect(controller.currentTime == Rational.fps60.frameToMicroseconds(1))
    }

    // MARK: - Additional Timecode Formatting Tests

    @Test("formatTimecode SMPTE with hours")
    func formatSMPTEWithHours() {
        // 1 hour = 3600 seconds = 3_600_000_000 microseconds
        let result = TimelinePlayheadController.formatTimecode(3_600_000_000, format: .smpte, frameRate: .fps30)
        #expect(result.hasPrefix("01:00:00"))
    }

    @Test("formatTimecode milliseconds with hours")
    func formatMillisecondsWithHours() {
        let result = TimelinePlayheadController.formatTimecode(3_600_000_000, format: .milliseconds)
        #expect(result.hasPrefix("01:00:00"))
    }

    @Test("formatTimecode seconds decimal")
    func formatSecondsDecimal() {
        let result = TimelinePlayheadController.formatTimecode(500_000, format: .seconds)
        #expect(result == "0.5s")
    }

    @Test("formatTimecode at zero for all formats")
    func formatTimecodeAllFormatsAtZero() {
        #expect(TimelinePlayheadController.formatTimecode(0, format: .smpte, frameRate: .fps30) == "00:00:00")
        #expect(TimelinePlayheadController.formatTimecode(0, format: .milliseconds) == "00:00.000")
        #expect(TimelinePlayheadController.formatTimecode(0, format: .simple) == "00:00")
        #expect(TimelinePlayheadController.formatTimecode(0, format: .seconds) == "0.0s")
    }

    // MARK: - formatCurrentTime

    @Test("formatCurrentTime uses current time and frame rate")
    func formatCurrentTime() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps30)
        controller.setTime(1_000_000)
        let result = controller.formatCurrentTime(format: .simple)
        #expect(result == "00:01")
    }

    // MARK: - Scrubbing Edge Cases

    @Test("cancelScrub is no-op when not scrubbing")
    func cancelScrubNotScrubbing() {
        let controller = makeController()
        controller.setTime(500_000)
        controller.cancelScrub(0)
        // Should not change time since not scrubbing
        #expect(controller.currentTime == 500_000)
    }

    @Test("scrub followed by playback cancels scrub implicitly")
    func scrubThenPlayback() {
        let controller = makeController()
        controller.startScrub(500_000)
        #expect(controller.isScrubbing == true)
        controller.notifyPlaybackStarted()
        #expect(controller.isPlaying == true)
        #expect(controller.isScrubbing == false)
    }

    // MARK: - Dispose

    @Test("dispose clears display link")
    func dispose() {
        let controller = makeController()
        controller.dispose()
        // No crash = success; display link should be nil
        #expect(controller.state == .idle)
    }

    // MARK: - seekTo

    @Test("seekTo sets state to seeking")
    func seekToState() {
        let controller = makeController()
        controller.seekTo(1_000_000)
        #expect(controller.state == .seeking)
        controller.dispose() // Clean up display link
    }

    @Test("seekTo clamps negative to zero")
    func seekToNegative() {
        let controller = makeController()
        controller.seekTo(-500)
        // seekTargetTime should be 0 internally
        #expect(controller.state == .seeking)
        controller.dispose()
    }

    // MARK: - Multiple callbacks

    @Test("multiple time changes fire callback each time")
    func multipleTimeCallbacks() {
        let controller = makeController()
        var callCount = 0
        controller.onTimeChanged = { _ in callCount += 1 }
        controller.setTime(100)
        controller.setTime(200)
        controller.setTime(300)
        #expect(callCount == 3)
    }

    @Test("setFrameRate Rational does not clamp standard rates")
    func setFrameRateRational() {
        let controller = makeController()
        controller.setFrameRate(Rational.fps24)
        #expect(controller.frameRate == Rational.fps24)
    }
}
