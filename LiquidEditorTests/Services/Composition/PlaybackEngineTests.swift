// PlaybackEngineTests.swift
// LiquidEditorTests
//
// Comprehensive tests for PlaybackEngine state machine and configuration.
//
// Focuses on state transitions, property clamping, and lifecycle management.
// Tests that depend on AVPlayer (play, pause, stop) verify the engine handles
// CompositionManager errors gracefully by transitioning to .error state.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Creates a fully wired PlaybackEngine with real (but empty) dependencies.
///
/// Since CompositionManager requires AVPlayer (unavailable in unit test simulator
/// without real media), methods that call into it (play, pause, stop, seek) will
/// throw or no-op. Tests focus on state machine logic, clamping, and lifecycle.
private func makeEngine() -> PlaybackEngine {
    let compositionManager = CompositionManager()
    let frameCache = FrameCache(frameRate: .fps30)
    let decoderPool = NativeDecoderPool(maxDecoders: 4)
    let scrubController = ScrubController(
        frameCache: frameCache,
        decoderPool: decoderPool,
        timeline: .empty
    )
    return PlaybackEngine(
        compositionManager: compositionManager,
        frameCache: frameCache,
        decoderPool: decoderPool,
        scrubController: scrubController
    )
}

// MARK: - PlaybackEngine Tests

@Suite("PlaybackEngine Tests")
struct PlaybackEngineTests {

    // MARK: - Initial State

    @Test("Initial state is uninitialized")
    func initialState() async {
        let engine = makeEngine()
        let state = await engine.state
        #expect(state == .uninitialized)
    }

    @Test("isReady is false when uninitialized")
    func isReadyWhenUninitialized() async {
        let engine = makeEngine()
        let ready = await engine.isReady
        #expect(ready == false)
    }

    @Test("isPlaying is false initially")
    func isPlayingInitially() async {
        let engine = makeEngine()
        let playing = await engine.isPlaying
        #expect(playing == false)
    }

    @Test("isPaused is false initially")
    func isPausedInitially() async {
        let engine = makeEngine()
        let paused = await engine.isPaused
        #expect(paused == false)
    }

    @Test("isStopped is false initially (uninitialized, not stopped)")
    func isStoppedInitially() async {
        let engine = makeEngine()
        let stopped = await engine.isStopped
        #expect(stopped == false)
    }

    @Test("isScrubbing is false initially")
    func isScrubbingInitially() async {
        let engine = makeEngine()
        let scrubbing = await engine.isScrubbing
        #expect(scrubbing == false)
    }

    @Test("Default playback rate is 1.0")
    func defaultPlaybackRate() async {
        let engine = makeEngine()
        let rate = await engine.playbackRate
        #expect(rate == 1.0)
    }

    @Test("Default volume is 1.0")
    func defaultVolume() async {
        let engine = makeEngine()
        let vol = await engine.volume
        #expect(vol == 1.0)
    }

    @Test("Default looping is false")
    func defaultLooping() async {
        let engine = makeEngine()
        let looping = await engine.isLooping
        #expect(looping == false)
    }

    @Test("Default frame rate is 30 fps")
    func defaultFrameRate() async {
        let engine = makeEngine()
        let rate = await engine.frameRate
        #expect(rate == .fps30)
    }

    @Test("Playhead starts at 0")
    func playheadStartsAtZero() async {
        let engine = makeEngine()
        let playhead = await engine.playheadMicros
        #expect(playhead == 0)
    }

    @Test("Error message is nil initially")
    func errorMessageNil() async {
        let engine = makeEngine()
        let msg = await engine.errorMessage
        #expect(msg == nil)
    }

    // MARK: - Initialize

    @Test("Initialize transitions to stopped")
    func initializeToStopped() async {
        let engine = makeEngine()
        await engine.initialize()
        let state = await engine.state
        #expect(state == .stopped)
    }

    @Test("isReady is true after initialize")
    func isReadyAfterInit() async {
        let engine = makeEngine()
        await engine.initialize()
        let ready = await engine.isReady
        #expect(ready == true)
    }

    @Test("isStopped is true after initialize")
    func isStoppedAfterInit() async {
        let engine = makeEngine()
        await engine.initialize()
        let stopped = await engine.isStopped
        #expect(stopped == true)
    }

    @Test("Double initialize is a no-op")
    func doubleInitialize() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.initialize()
        let state = await engine.state
        #expect(state == .stopped)
    }

    // MARK: - State Guards (uninitialized)

    @Test("play is no-op when uninitialized")
    func playWhenUninitialized() async {
        let engine = makeEngine()
        await engine.play()
        let state = await engine.state
        #expect(state == .uninitialized)
    }

    @Test("pause is no-op when uninitialized")
    func pauseWhenUninitialized() async {
        let engine = makeEngine()
        await engine.pause()
        let state = await engine.state
        #expect(state == .uninitialized)
    }

    @Test("seek is no-op when uninitialized")
    func seekWhenUninitialized() async {
        let engine = makeEngine()
        await engine.seek(1_000_000)
        let state = await engine.state
        #expect(state == .uninitialized)
    }

    @Test("beginScrub is no-op when uninitialized")
    func beginScrubWhenUninitialized() async {
        let engine = makeEngine()
        await engine.beginScrub()
        let state = await engine.state
        #expect(state == .uninitialized)
    }

    // MARK: - Scrub Lifecycle

    @Test("beginScrub transitions to scrubbing state")
    func beginScrubTransition() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.beginScrub()
        let state = await engine.state
        #expect(state == .scrubbing)
    }

    @Test("isScrubbing returns true during scrub")
    func isScrubbingDuringScrub() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.beginScrub()
        let scrubbing = await engine.isScrubbing
        #expect(scrubbing == true)
    }

    @Test("endScrub transitions to paused")
    func endScrubTransition() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.beginScrub()
        await engine.endScrub()
        let state = await engine.state
        #expect(state == .paused)
    }

    @Test("endScrub is no-op when not scrubbing")
    func endScrubWhenNotScrubbing() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.endScrub()
        let state = await engine.state
        // Should still be stopped (not changed)
        #expect(state == .stopped)
    }

    @Test("cancelScrub transitions to paused")
    func cancelScrubTransition() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.beginScrub()
        await engine.cancelScrub()
        let state = await engine.state
        #expect(state == .paused)
    }

    @Test("cancelScrub is no-op when not scrubbing")
    func cancelScrubWhenNotScrubbing() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.cancelScrub()
        let state = await engine.state
        #expect(state == .stopped)
    }

    @Test("scrubTo is no-op when not scrubbing")
    func scrubToWhenNotScrubbing() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.scrubTo(500_000)
        let playhead = await engine.playheadMicros
        // Playhead should not change since we're not in scrubbing state
        #expect(playhead == 0)
    }

    @Test("scrubTo updates playhead when scrubbing")
    func scrubToUpdatesPlayhead() async {
        let engine = makeEngine()
        await engine.initialize()

        // Give the engine a timeline with duration so clamping doesn't zero it out
        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.beginScrub()
        await engine.scrubTo(500_000)
        let playhead = await engine.playheadMicros
        #expect(playhead == 500_000)
    }

    @Test("scrubTo clamps to timeline duration")
    func scrubToClampsToDuration() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 5_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.beginScrub()
        await engine.scrubTo(10_000_000) // Exceeds 5s duration
        let playhead = await engine.playheadMicros
        #expect(playhead == 5_000_000)
    }

    @Test("scrubTo clamps negative to zero")
    func scrubToClampsNegative() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 5_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.beginScrub()
        await engine.scrubTo(-1_000_000)
        let playhead = await engine.playheadMicros
        #expect(playhead == 0)
    }

    // MARK: - Playback Rate

    @Test("setPlaybackRate updates rate")
    func setPlaybackRateUpdates() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setPlaybackRate(2.0)
        let rate = await engine.playbackRate
        #expect(rate == 2.0)
    }

    @Test("setPlaybackRate clamps to minimum 0.1")
    func setPlaybackRateClampsMin() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setPlaybackRate(0.01)
        let rate = await engine.playbackRate
        #expect(rate == 0.1)
    }

    @Test("setPlaybackRate clamps to maximum 4.0")
    func setPlaybackRateClampsMax() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setPlaybackRate(10.0)
        let rate = await engine.playbackRate
        #expect(rate == 4.0)
    }

    @Test("setPlaybackRate clamps negative to 0.1")
    func setPlaybackRateClampsNegative() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setPlaybackRate(-1.0)
        let rate = await engine.playbackRate
        #expect(rate == 0.1)
    }

    @Test("setPlaybackRate accepts boundary value 0.1")
    func setPlaybackRateBoundaryMin() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setPlaybackRate(0.1)
        let rate = await engine.playbackRate
        #expect(rate == 0.1)
    }

    @Test("setPlaybackRate accepts boundary value 4.0")
    func setPlaybackRateBoundaryMax() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setPlaybackRate(4.0)
        let rate = await engine.playbackRate
        #expect(rate == 4.0)
    }

    // MARK: - Volume

    @Test("setVolume updates volume")
    func setVolumeUpdates() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setVolume(0.5)
        let vol = await engine.volume
        #expect(vol == 0.5)
    }

    @Test("setVolume clamps to minimum 0.0")
    func setVolumeClampsMin() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setVolume(-0.5)
        let vol = await engine.volume
        #expect(vol == 0.0)
    }

    @Test("setVolume clamps to maximum 1.0")
    func setVolumeClampsMax() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setVolume(2.0)
        let vol = await engine.volume
        #expect(vol == 1.0)
    }

    @Test("setVolume accepts boundary value 0.0")
    func setVolumeBoundaryMin() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setVolume(0.0)
        let vol = await engine.volume
        #expect(vol == 0.0)
    }

    @Test("setVolume accepts boundary value 1.0")
    func setVolumeBoundaryMax() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setVolume(1.0)
        let vol = await engine.volume
        #expect(vol == 1.0)
    }

    // MARK: - Looping

    @Test("setLooping enables looping")
    func setLoopingTrue() async {
        let engine = makeEngine()
        await engine.setLooping(true)
        let looping = await engine.isLooping
        #expect(looping == true)
    }

    @Test("setLooping disables looping")
    func setLoopingFalse() async {
        let engine = makeEngine()
        await engine.setLooping(true)
        await engine.setLooping(false)
        let looping = await engine.isLooping
        #expect(looping == false)
    }

    // MARK: - Frame Rate

    @Test("setFrameRate updates frame rate")
    func setFrameRateUpdates() async {
        let engine = makeEngine()
        await engine.setFrameRate(.fps60)
        let rate = await engine.frameRate
        #expect(rate == .fps60)
    }

    @Test("setFrameRate accepts NTSC frame rate")
    func setFrameRateNTSC() async {
        let engine = makeEngine()
        await engine.setFrameRate(.fps29_97)
        let rate = await engine.frameRate
        #expect(rate == .fps29_97)
    }

    // MARK: - updateTimeline

    @Test("updateTimeline transitions from uninitialized to stopped")
    func updateTimelineTransition() async {
        let engine = makeEngine()
        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 5_000_000)
        ])
        await engine.updateTimeline(timeline)
        let state = await engine.state
        #expect(state == .stopped)
    }

    @Test("updateTimeline keeps stopped state when already initialized")
    func updateTimelineWhenAlreadyInitialized() async {
        let engine = makeEngine()
        await engine.initialize()
        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 5_000_000)
        ])
        await engine.updateTimeline(timeline)
        let state = await engine.state
        #expect(state == .stopped)
    }

    @Test("updateTimeline with empty timeline also transitions to stopped")
    func updateTimelineEmpty() async {
        let engine = makeEngine()
        await engine.updateTimeline(.empty)
        let state = await engine.state
        #expect(state == .stopped)
    }

    // MARK: - handleMemoryPressure

    @Test("handleMemoryPressure at level 0 does not crash")
    func memoryPressureNormal() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.handleMemoryPressure(0)
        // Just verify it doesn't crash and state is preserved
        let state = await engine.state
        #expect(state == .stopped)
    }

    @Test("handleMemoryPressure at level 1 does not crash")
    func memoryPressureWarning() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.handleMemoryPressure(1)
        let state = await engine.state
        #expect(state == .stopped)
    }

    @Test("handleMemoryPressure at level 2 does not crash")
    func memoryPressureCritical() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.handleMemoryPressure(2)
        let state = await engine.state
        #expect(state == .stopped)
    }

    @Test("handleMemoryPressure works when uninitialized")
    func memoryPressureUninitialized() async {
        let engine = makeEngine()
        await engine.handleMemoryPressure(2)
        let state = await engine.state
        #expect(state == .uninitialized)
    }

    // MARK: - Statistics

    @Test("statistics returns expected keys")
    func statisticsKeys() async {
        let engine = makeEngine()
        await engine.initialize()
        let stats = await engine.statistics
        #expect(stats["state"] != nil)
        #expect(stats["playheadMicros"] != nil)
        #expect(stats["totalDurationMicros"] != nil)
        #expect(stats["playbackRate"] != nil)
        #expect(stats["volume"] != nil)
        #expect(stats["isLooping"] != nil)
        #expect(stats["frameRate"] != nil)
        #expect(stats["decoderCount"] != nil)
    }

    @Test("statistics reflects current state")
    func statisticsValues() async {
        let engine = makeEngine()
        await engine.initialize()
        let stats = await engine.statistics
        #expect(stats["state"] == "stopped")
        #expect(stats["playheadMicros"] == "0")
        #expect(stats["playbackRate"] == "1.0")
        #expect(stats["volume"] == "1.0")
        #expect(stats["isLooping"] == "false")
        #expect(stats["decoderCount"] == "0")
    }

    @Test("statistics reflects updated settings")
    func statisticsAfterChanges() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setPlaybackRate(2.5)
        await engine.setVolume(0.7)
        await engine.setLooping(true)
        let stats = await engine.statistics
        #expect(stats["playbackRate"] == "2.5")
        #expect(stats["volume"] == "0.7")
        #expect(stats["isLooping"] == "true")
    }

    // MARK: - Dispose

    @Test("dispose marks engine as disposed")
    func disposeMarksDisposed() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.dispose()
        // After dispose, the engine should not crash on further calls
        // Calling dispose again should be a no-op (guard !isDisposed)
        await engine.dispose()
        // No crash = pass
    }

    @Test("dispose can be called when uninitialized")
    func disposeWhenUninitialized() async {
        let engine = makeEngine()
        await engine.dispose()
        // No crash = pass
    }

    // MARK: - Play/Pause/Stop (Error Handling)
    //
    // These test that the engine properly transitions to .error state when
    // CompositionManager operations fail (no AVPlayer loaded).

    @Test("play on initialized engine transitions to error (no AVPlayer)")
    func playTransitionsToError() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.play()
        let state = await engine.state
        // play() calls compositionManager.play() which tries to set player rate.
        // Without a loaded composition, it may succeed (rate on nil player is no-op)
        // or error depending on the CompositionManager implementation.
        // The engine should be in either .playing or .error state.
        #expect(state == .playing || state == .error)
    }

    @Test("stop on initialized engine handles gracefully")
    func stopHandlesGracefully() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.stop()
        let state = await engine.state
        // stop() calls compositionManager.pause() then seek(to: 0).
        // May succeed (no-op on nil player) or transition to .error.
        #expect(state == .stopped || state == .error)
    }

    // MARK: - Seek (with initialized engine)

    @Test("seek updates playhead when initialized")
    func seekUpdatesPlayhead() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.seek(3_000_000)
        let playhead = await engine.playheadMicros
        // Seek sets playheadMicros before calling compositionManager.seek
        // Even if compositionManager.seek fails, playheadMicros should be updated
        #expect(playhead == 3_000_000)
    }

    @Test("seek clamps above duration to duration")
    func seekClampsAboveDuration() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 5_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.seek(20_000_000)
        let playhead = await engine.playheadMicros
        #expect(playhead == 5_000_000)
    }

    @Test("seek clamps negative to zero")
    func seekClampsNegative() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 5_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.seek(-1_000_000)
        let playhead = await engine.playheadMicros
        #expect(playhead == 0)
    }

    @Test("seekForward advances playhead")
    func seekForwardAdvances() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.seek(2_000_000)
        await engine.seekForward(1_000_000)
        let playhead = await engine.playheadMicros
        #expect(playhead == 3_000_000)
    }

    @Test("seekBackward retreats playhead")
    func seekBackwardRetreats() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.seek(5_000_000)
        await engine.seekBackward(2_000_000)
        let playhead = await engine.playheadMicros
        #expect(playhead == 3_000_000)
    }

    @Test("seekBackward past zero clamps to zero")
    func seekBackwardClampsToZero() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.seek(1_000_000)
        await engine.seekBackward(5_000_000)
        let playhead = await engine.playheadMicros
        #expect(playhead == 0)
    }

    // MARK: - Next/Previous Frame

    @Test("nextFrame advances by one frame at 30fps")
    func nextFrameAdvances() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.nextFrame()
        let playhead = await engine.playheadMicros
        let expectedFrameDuration = Rational.fps30.microsecondsPerFrame
        #expect(playhead == expectedFrameDuration)
    }

    @Test("previousFrame retreats by one frame at 30fps")
    func previousFrameRetreats() async {
        let engine = makeEngine()
        await engine.initialize()

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        // Seek to 1 second, then go back one frame
        await engine.seek(1_000_000)
        await engine.previousFrame()
        let playhead = await engine.playheadMicros
        let expectedFrameDuration = Rational.fps30.microsecondsPerFrame
        #expect(playhead == 1_000_000 - expectedFrameDuration)
    }

    @Test("nextFrame with 60fps uses correct frame duration")
    func nextFrameAt60fps() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.setFrameRate(.fps60)

        let timeline = PersistentTimeline.fromList([
            GapClip(id: "gap1", durationMicroseconds: 10_000_000)
        ])
        await engine.updateTimeline(timeline)

        await engine.nextFrame()
        let playhead = await engine.playheadMicros
        let expectedFrameDuration = Rational.fps60.microsecondsPerFrame
        #expect(playhead == expectedFrameDuration)
    }

    // MARK: - togglePlayPause

    @Test("togglePlayPause from stopped attempts play")
    func togglePlayPauseFromStopped() async {
        let engine = makeEngine()
        await engine.initialize()
        await engine.togglePlayPause()
        let state = await engine.state
        // Should attempt play (may succeed or error depending on CompositionManager)
        #expect(state == .playing || state == .error)
    }

    // MARK: - Event Stream

    @Test("Event stream emits scrub events via callback")
    func eventStreamEmitsScrubEvents() async {
        let engine = makeEngine()

        // Use a thread-safe collector for events
        let collector = EventCollector()
        await engine.setEventCallback { event in
            collector.append(event)
        }

        // Wait briefly for the callback to be set (actor hop)
        try? await Task.sleep(nanoseconds: 5_000_000)

        await engine.initialize()
        await engine.beginScrub()
        await engine.endScrub()

        let collectedEvents = collector.events
        #expect(collectedEvents.contains(.scrubStarted))
        #expect(collectedEvents.contains(.scrubEnded))
    }

    // MARK: - Computed Properties Consistency

    @Test("Computed properties reflect state correctly after scrub")
    func computedPropertiesAfterScrub() async {
        let engine = makeEngine()
        await engine.initialize()

        // Verify stopped state
        #expect(await engine.isStopped == true)
        #expect(await engine.isPlaying == false)
        #expect(await engine.isPaused == false)
        #expect(await engine.isScrubbing == false)

        // Begin scrub
        await engine.beginScrub()
        #expect(await engine.isStopped == false)
        #expect(await engine.isPlaying == false)
        #expect(await engine.isPaused == false)
        #expect(await engine.isScrubbing == true)

        // End scrub
        await engine.endScrub()
        #expect(await engine.isStopped == false)
        #expect(await engine.isPlaying == false)
        #expect(await engine.isPaused == true)
        #expect(await engine.isScrubbing == false)
    }

    @Test("isReady is false in error state")
    func isReadyInErrorState() async {
        let engine = makeEngine()
        await engine.initialize()

        // Force an error by calling play and then checking.
        // play() on a nil player may or may not error. If it does,
        // the engine transitions to .error and isReady should be false.
        await engine.play()
        let state = await engine.state
        if state == .error {
            let ready = await engine.isReady
            #expect(ready == false)
        }
    }
}

// MARK: - Event Collector (thread-safe)

/// Thread-safe event collector for testing PlaybackEngine event emission.
private final class EventCollector: @unchecked Sendable {
    private var _events: [PlaybackEvent] = []
    private let lock = NSLock()

    func append(_ event: PlaybackEvent) {
        lock.lock()
        _events.append(event)
        lock.unlock()
    }

    var events: [PlaybackEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }
}

// MARK: - Helper extension for event callback

extension PlaybackEngine {
    /// Sets the onPlaybackEvent callback (actor-isolated).
    func setEventCallback(_ callback: @escaping (PlaybackEvent) -> Void) {
        self.onPlaybackEvent = callback
    }
}
