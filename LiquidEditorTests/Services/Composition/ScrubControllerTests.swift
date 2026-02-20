// ScrubControllerTests.swift
// LiquidEditorTests
//
// Comprehensive tests for ScrubController state management,
// scrub lifecycle, and configuration updates.

import Testing
import Foundation
import os
@testable import LiquidEditor

// MARK: - Helper

/// Creates a ScrubController with default empty dependencies for testing.
private func makeScrubController(
    timeline: PersistentTimeline = .empty,
    frameRate: Rational = .fps30
) -> ScrubController {
    let frameCache = FrameCache(frameRate: frameRate)
    let decoderPool = NativeDecoderPool(maxDecoders: 4)
    return ScrubController(
        frameCache: frameCache,
        decoderPool: decoderPool,
        timeline: timeline,
        frameRate: frameRate
    )
}

// MARK: - Initial State

@Suite("ScrubController - Initial State")
struct ScrubControllerInitialStateTests {

    @Test("Starts in idle state")
    func startsIdle() {
        let controller = makeScrubController()
        #expect(controller.state == .idle)
    }

    @Test("isIdle is true initially")
    func isIdleInitially() {
        let controller = makeScrubController()
        #expect(controller.isIdle == true)
    }

    @Test("isScrubbing is false initially")
    func isNotScrubbingInitially() {
        let controller = makeScrubController()
        #expect(controller.isScrubbing == false)
    }

    @Test("isSettling is false initially")
    func isNotSettlingInitially() {
        let controller = makeScrubController()
        #expect(controller.isSettling == false)
    }

    @Test("isSeeking is false initially")
    func isNotSeekingInitially() {
        let controller = makeScrubController()
        #expect(controller.isSeeking == false)
    }

    @Test("Playhead starts at zero")
    func playheadStartsAtZero() {
        let controller = makeScrubController()
        #expect(controller.playheadMicros == 0)
    }

    @Test("Frame rate matches initialization parameter")
    func frameRateMatchesInit() {
        let controller = makeScrubController(frameRate: .fps60)
        #expect(controller.frameRate == .fps60)
    }

    @Test("Default frame rate is 30fps")
    func defaultFrameRateIs30() {
        let controller = makeScrubController()
        #expect(controller.frameRate == .fps30)
    }

    @Test("Initial velocity is slow with no samples")
    func initialVelocityIsSlow() {
        let controller = makeScrubController()
        #expect(controller.velocity == .slow)
    }
}

// MARK: - beginScrub

@Suite("ScrubController - beginScrub")
struct ScrubControllerBeginScrubTests {

    @Test("Transitions to scrubbing state")
    func transitionsToScrubbing() {
        let controller = makeScrubController()
        controller.beginScrub()
        #expect(controller.state == .scrubbing)
        #expect(controller.isScrubbing == true)
        #expect(controller.isIdle == false)
    }

    @Test("Fires state change callback")
    func firesStateChangeCallback() {
        let controller = makeScrubController()
        let stateChanges = OSAllocatedUnfairLock<[ScrubState]>(initialState: [])
        controller.onStateChange = { newState in
            stateChanges.withLock { $0.append(newState) }
        }

        controller.beginScrub()
        let changes = stateChanges.withLock { $0 }
        #expect(changes == [ScrubState.scrubbing])
    }

    @Test("Can call beginScrub multiple times without crash")
    func multipleBeginScrubCalls() {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.beginScrub()
        #expect(controller.state == .scrubbing)
    }
}

// MARK: - endScrub

@Suite("ScrubController - endScrub")
struct ScrubControllerEndScrubTests {

    @Test("Transitions to settling state immediately")
    func transitionsToSettling() {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.endScrub()
        #expect(controller.state == .settling)
        #expect(controller.isSettling == true)
    }

    @Test("Eventually transitions to idle after settling duration")
    func transitionsToIdleAfterSettling() async throws {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.endScrub()

        // Wait for settling duration (300ms) plus buffer
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(controller.state == .idle)
        #expect(controller.isIdle == true)
    }

    @Test("Fires state change callbacks for settling and idle")
    func firesStateChangeCallbacks() async throws {
        let controller = makeScrubController()
        let stateChanges = OSAllocatedUnfairLock<[ScrubState]>(initialState: [])

        controller.onStateChange = { newState in
            stateChanges.withLock { $0.append(newState) }
        }

        controller.beginScrub()
        controller.endScrub()

        // Wait for settling to complete
        try await Task.sleep(nanoseconds: 500_000_000)

        let changes = stateChanges.withLock { $0 }
        #expect(changes.contains(ScrubState.scrubbing))
        #expect(changes.contains(ScrubState.settling))
        #expect(changes.contains(ScrubState.idle))
    }
}

// MARK: - cancel

@Suite("ScrubController - cancel")
struct ScrubControllerCancelTests {

    @Test("Returns to idle from scrubbing")
    func cancelsFromScrubbing() {
        let controller = makeScrubController()
        controller.beginScrub()
        #expect(controller.state == .scrubbing)

        controller.cancel()
        #expect(controller.state == .idle)
        #expect(controller.isIdle == true)
    }

    @Test("Returns to idle from settling")
    func cancelsFromSettling() {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.endScrub()
        #expect(controller.state == .settling)

        controller.cancel()
        #expect(controller.state == .idle)
    }

    @Test("Cancel when already idle has no effect")
    func cancelWhenIdle() {
        let controller = makeScrubController()
        #expect(controller.state == .idle)
        controller.cancel()
        #expect(controller.state == .idle)
    }

    @Test("Cancel fires state change callback when state changes")
    func cancelFiresCallback() {
        let controller = makeScrubController()
        controller.beginScrub()

        let stateChanges = OSAllocatedUnfairLock<[ScrubState]>(initialState: [])
        controller.onStateChange = { newState in
            stateChanges.withLock { $0.append(newState) }
        }

        controller.cancel()
        let changes = stateChanges.withLock { $0 }
        #expect(changes == [ScrubState.idle])
    }

    @Test("Cancel does not fire callback when already idle")
    func cancelNoCallbackWhenIdle() {
        let controller = makeScrubController()
        let callbackCalled = OSAllocatedUnfairLock<Bool>(initialState: false)
        controller.onStateChange = { _ in
            callbackCalled.withLock { $0 = true }
        }

        controller.cancel()
        #expect(callbackCalled.withLock({ $0 }) == false)
    }

    @Test("Cancel prevents settling from completing")
    func cancelPreventsSettling() async throws {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.endScrub()
        #expect(controller.state == .settling)

        controller.cancel()
        #expect(controller.state == .idle)

        // Wait past settling duration to confirm no transition occurs
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(controller.state == .idle)
    }
}

// MARK: - scrubTo

@Suite("ScrubController - scrubTo")
struct ScrubControllerScrubToTests {

    @Test("Returns FrameResult with correct timeMicros for empty timeline")
    func returnsFrameResultWithTimeMicros() async {
        let controller = makeScrubController()
        controller.beginScrub()

        let result = await controller.scrubTo(500_000)
        // With empty timeline (0 duration), time gets clamped to 0
        #expect(result.timeMicros == 0)
    }

    @Test("Returns FrameResult with no frame for empty timeline")
    func noFrameForEmptyTimeline() async {
        let controller = makeScrubController()
        controller.beginScrub()

        let result = await controller.scrubTo(1_000_000)
        #expect(result.frame == nil)
        #expect(result.hasFrame == false)
    }

    @Test("Result has no assetId for empty timeline")
    func noAssetIdForEmptyTimeline() async {
        let controller = makeScrubController()
        controller.beginScrub()

        let result = await controller.scrubTo(0)
        #expect(result.assetId == nil)
    }

    @Test("Result is not cached for empty timeline")
    func notCachedForEmptyTimeline() async {
        let controller = makeScrubController()
        controller.beginScrub()

        let result = await controller.scrubTo(0)
        #expect(result.wasCached == false)
    }

    @Test("Updates playhead position after scrub")
    func updatesPlayheadPosition() async {
        let controller = makeScrubController()
        controller.beginScrub()

        _ = await controller.scrubTo(500_000)
        #expect(controller.playheadMicros == 0)
    }

    @Test("Clamps negative time to zero")
    func clampsNegativeTime() async {
        let controller = makeScrubController()
        controller.beginScrub()

        let result = await controller.scrubTo(-1_000_000)
        #expect(result.timeMicros == 0)
        #expect(controller.playheadMicros == 0)
    }

    @Test("Multiple scrubTo calls update playhead each time")
    func multipleScrubToCalls() async {
        let controller = makeScrubController()
        controller.beginScrub()

        _ = await controller.scrubTo(100_000)
        _ = await controller.scrubTo(200_000)
        _ = await controller.scrubTo(300_000)

        #expect(controller.playheadMicros == 0)
    }
}

// MARK: - seekTo

@Suite("ScrubController - seekTo")
struct ScrubControllerSeekToTests {

    @Test("Transitions through seeking then back to idle")
    func seekTransitionsToIdle() async {
        let controller = makeScrubController()
        let result = await controller.seekTo(500_000)

        #expect(controller.state == .idle)
        #expect(result.timeMicros == 0)
    }

    @Test("Seek cancels any active settling")
    func seekCancelsSettling() async {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.endScrub()
        #expect(controller.state == .settling)

        _ = await controller.seekTo(0)
        #expect(controller.state == .idle)
    }

    @Test("Seek returns FrameResult with no frame for empty timeline")
    func seekNoFrameEmptyTimeline() async {
        let controller = makeScrubController()
        let result = await controller.seekTo(0)
        #expect(result.frame == nil)
        #expect(result.hasFrame == false)
    }
}

// MARK: - updateTimeline

@Suite("ScrubController - updateTimeline")
struct ScrubControllerUpdateTimelineTests {

    @Test("Accepts a new empty timeline")
    func updatesWithEmptyTimeline() {
        let controller = makeScrubController()
        controller.updateTimeline(.empty)
        #expect(controller.state == .idle)
    }

    @Test("Accepts the same timeline twice")
    func updatesSameTimelineTwice() {
        let controller = makeScrubController()
        let tl = PersistentTimeline.empty
        controller.updateTimeline(tl)
        controller.updateTimeline(tl)
        #expect(controller.state == .idle)
    }
}

// MARK: - updateFrameRate

@Suite("ScrubController - updateFrameRate")
struct ScrubControllerUpdateFrameRateTests {

    @Test("Changes frame rate to 60fps")
    func changesFrameRateTo60() {
        let controller = makeScrubController(frameRate: .fps30)
        #expect(controller.frameRate == .fps30)

        controller.updateFrameRate(.fps60)
        #expect(controller.frameRate == .fps60)
    }

    @Test("Changes frame rate to 24fps")
    func changesFrameRateTo24() {
        let controller = makeScrubController()
        controller.updateFrameRate(.fps24)
        #expect(controller.frameRate == .fps24)
    }

    @Test("Changes frame rate to 29.97fps (NTSC)")
    func changesFrameRateToNTSC() {
        let controller = makeScrubController()
        controller.updateFrameRate(.fps29_97)
        #expect(controller.frameRate == .fps29_97)
    }

    @Test("Frame rate update does not affect scrub state")
    func frameRateUpdatePreservesState() {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.updateFrameRate(.fps60)
        #expect(controller.state == .scrubbing)
        #expect(controller.frameRate == .fps60)
    }
}

// MARK: - dispose

@Suite("ScrubController - dispose")
struct ScrubControllerDisposeTests {

    @Test("Dispose does not crash on idle controller")
    func disposeWhenIdle() {
        let controller = makeScrubController()
        controller.dispose()
        #expect(controller.state == .idle)
    }

    @Test("Dispose can be called while scrubbing")
    func disposeWhileScrubbing() {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.dispose()
    }

    @Test("Dispose can be called while settling")
    func disposeWhileSettling() {
        let controller = makeScrubController()
        controller.beginScrub()
        controller.endScrub()
        controller.dispose()
    }

    @Test("Dispose can be called multiple times")
    func disposeMultipleTimes() {
        let controller = makeScrubController()
        controller.dispose()
        controller.dispose()
        controller.dispose()
    }
}

// MARK: - State Transitions

@Suite("ScrubController - State Transitions")
struct ScrubControllerStateTransitionTests {

    @Test("Full scrub lifecycle: idle -> scrubbing -> settling -> idle")
    func fullScrubLifecycle() async throws {
        let controller = makeScrubController()
        #expect(controller.state == .idle)

        controller.beginScrub()
        #expect(controller.state == .scrubbing)

        _ = await controller.scrubTo(0)

        controller.endScrub()
        #expect(controller.state == .settling)

        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(controller.state == .idle)
    }

    @Test("Interrupted scrub: begin -> end -> begin cancels settling")
    func interruptedScrub() {
        let controller = makeScrubController()

        controller.beginScrub()
        controller.endScrub()
        #expect(controller.state == .settling)

        controller.beginScrub()
        #expect(controller.state == .scrubbing)
    }

    @Test("Seek lifecycle: idle -> seeking -> idle")
    func seekLifecycle() async {
        let controller = makeScrubController()
        #expect(controller.state == .idle)

        let stateChanges = OSAllocatedUnfairLock<[ScrubState]>(initialState: [])
        controller.onStateChange = { newState in
            stateChanges.withLock { $0.append(newState) }
        }

        _ = await controller.seekTo(0)

        let changes = stateChanges.withLock { $0 }
        #expect(changes.contains(ScrubState.seeking))
        #expect(changes.last == ScrubState.idle)
        #expect(controller.state == .idle)
    }

    @Test("Rapid begin/end cycles do not corrupt state")
    func rapidBeginEndCycles() {
        let controller = makeScrubController()
        for _ in 0..<20 {
            controller.beginScrub()
            controller.endScrub()
        }
        #expect(controller.state == .settling)

        controller.cancel()
        #expect(controller.state == .idle)
    }
}

// MARK: - Statistics

@Suite("ScrubController - Statistics")
struct ScrubControllerStatisticsTests {

    @Test("Statistics returns expected keys")
    func statisticsContainsExpectedKeys() {
        let controller = makeScrubController()
        let stats = controller.statistics

        #expect(stats["state"] as? String == "idle")
        #expect(stats["playheadMicros"] as? TimeMicros == 0)
        #expect(stats["velocity"] as? String == "slow")
        #expect(stats["velocitySamples"] as? Int == 0)
    }

    @Test("Statistics reflects state change")
    func statisticsReflectsStateChange() {
        let controller = makeScrubController()
        controller.beginScrub()
        let stats = controller.statistics
        #expect(stats["state"] as? String == "scrubbing")
    }
}

// MARK: - Velocity

@Suite("ScrubController - Velocity")
struct ScrubControllerVelocityTests {

    @Test("Velocity is slow with no samples")
    func velocitySlowWithNoSamples() {
        let controller = makeScrubController()
        #expect(controller.velocity == .slow)
    }

    @Test("Velocity is slow with only one sample")
    func velocitySlowWithOneSample() async {
        let controller = makeScrubController()
        controller.beginScrub()
        _ = await controller.scrubTo(0)
        #expect(controller.velocity == .slow)
    }

    @Test("Velocity samples are cleared on beginScrub")
    func velocitySamplesClearedOnBegin() async {
        let controller = makeScrubController()
        controller.beginScrub()
        _ = await controller.scrubTo(0)
        _ = await controller.scrubTo(0)

        controller.beginScrub()
        #expect(controller.velocity == .slow)
    }
}

// MARK: - FrameResult

@Suite("ScrubController - FrameResult")
struct FrameResultTests {

    @Test("FrameResult with defaults has no frame")
    func defaultFrameResultHasNoFrame() {
        let result = FrameResult(timeMicros: 1_000_000)
        #expect(result.frame == nil)
        #expect(result.hasFrame == false)
        #expect(result.isExact == true)
        #expect(result.assetId == nil)
        #expect(result.timeMicros == 1_000_000)
        #expect(result.wasCached == false)
    }

    @Test("FrameResult hasFrame returns true when frame is present")
    func hasFrameWithFrame() {
        let frame = CachedFrame(
            assetId: "test",
            timeMicros: 0,
            pixels: Data(count: 4),
            width: 1,
            height: 1,
            isExact: true
        )
        let result = FrameResult(
            frame: frame,
            isExact: true,
            assetId: "test",
            timeMicros: 0,
            wasCached: true
        )
        #expect(result.hasFrame == true)
        #expect(result.frame != nil)
        #expect(result.wasCached == true)
    }

    @Test("FrameResult stores timeMicros correctly")
    func storesTimeMicros() {
        let result = FrameResult(timeMicros: 999_999)
        #expect(result.timeMicros == 999_999)
    }

    @Test("FrameResult stores assetId correctly")
    func storesAssetId() {
        let result = FrameResult(
            isExact: false,
            assetId: "asset_42",
            timeMicros: 0,
            wasCached: false
        )
        #expect(result.assetId == "asset_42")
        #expect(result.isExact == false)
    }
}

// MARK: - ScrubState Enum

@Suite("ScrubState")
struct ScrubStateTests {

    @Test("Raw values are correct strings")
    func rawValues() {
        #expect(ScrubState.idle.rawValue == "idle")
        #expect(ScrubState.scrubbing.rawValue == "scrubbing")
        #expect(ScrubState.settling.rawValue == "settling")
        #expect(ScrubState.seeking.rawValue == "seeking")
    }

    @Test("All cases are equatable")
    func equatable() {
        #expect(ScrubState.idle == ScrubState.idle)
        #expect(ScrubState.idle != ScrubState.scrubbing)
        #expect(ScrubState.settling != ScrubState.seeking)
    }
}

// MARK: - ScrubVelocity Enum

@Suite("ScrubVelocity")
struct ScrubVelocityTests {

    @Test("Raw values are correct strings")
    func rawValues() {
        #expect(ScrubVelocity.slow.rawValue == "slow")
        #expect(ScrubVelocity.medium.rawValue == "medium")
        #expect(ScrubVelocity.fast.rawValue == "fast")
    }
}

// MARK: - Callback Tests

@Suite("ScrubController - Callbacks")
struct ScrubControllerCallbackTests {

    @Test("onStateChange is called for each unique state transition")
    func stateChangeCallbackTracksTransitions() async throws {
        let controller = makeScrubController()
        let stateChanges = OSAllocatedUnfairLock<[ScrubState]>(initialState: [])

        controller.onStateChange = { newState in
            stateChanges.withLock { $0.append(newState) }
        }

        controller.beginScrub()
        controller.endScrub()

        try await Task.sleep(nanoseconds: 500_000_000)

        let changes = stateChanges.withLock { $0 }
        #expect(changes.count == 3)
        #expect(changes[0] == ScrubState.scrubbing)
        #expect(changes[1] == ScrubState.settling)
        #expect(changes[2] == ScrubState.idle)
    }

    @Test("onStateChange is not called for duplicate state")
    func noCallbackForDuplicateState() {
        let controller = makeScrubController()
        let callCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        controller.onStateChange = { _ in
            callCount.withLock { $0 += 1 }
        }

        controller.cancel()
        #expect(callCount.withLock({ $0 }) == 0)
    }

    @Test("onFrameReady is not called for empty timeline scrub")
    func noFrameReadyForEmptyTimeline() async {
        let controller = makeScrubController()
        let frameReadyCalled = OSAllocatedUnfairLock<Bool>(initialState: false)
        controller.onFrameReady = { _ in
            frameReadyCalled.withLock { $0 = true }
        }

        controller.beginScrub()
        _ = await controller.scrubTo(0)

        #expect(frameReadyCalled.withLock({ $0 }) == false)
    }
}

// MARK: - Convenience Properties

@Suite("ScrubController - Convenience Properties")
struct ScrubControllerConvenienceTests {

    @Test("isScrubbing reflects scrubbing state")
    func isScrubbingProperty() {
        let controller = makeScrubController()
        #expect(controller.isScrubbing == false)
        controller.beginScrub()
        #expect(controller.isScrubbing == true)
        controller.cancel()
        #expect(controller.isScrubbing == false)
    }

    @Test("isSettling reflects settling state")
    func isSettlingProperty() {
        let controller = makeScrubController()
        #expect(controller.isSettling == false)
        controller.beginScrub()
        controller.endScrub()
        #expect(controller.isSettling == true)
        controller.cancel()
        #expect(controller.isSettling == false)
    }

    @Test("isIdle reflects idle state")
    func isIdleProperty() {
        let controller = makeScrubController()
        #expect(controller.isIdle == true)
        controller.beginScrub()
        #expect(controller.isIdle == false)
        controller.cancel()
        #expect(controller.isIdle == true)
    }
}
