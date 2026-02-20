// PlaybackEngine.swift
// LiquidEditor
//
// Playback engine — the central orchestrator for video playback.
//
// Integrates:
// - CompositionManager for native AVPlayer playback
// - FrameCache for scrubbing frame storage
// - NativeDecoderPool for multi-source frame extraction
// - ScrubController for scrub coordination
//
// Provides a unified async interface for play, pause, seek, scrub,
// composition rebuild, and hot-swap. Uses Swift actor isolation for
// thread safety.

import Foundation
import os

// MARK: - PlaybackEngineState

/// Playback engine state machine.
///
/// Distinct from ``PlaybackState`` (which models AVPlayer state);
/// this enum models the higher-level engine lifecycle including
/// scrubbing, seeking, and composition rebuilding.
enum PlaybackEngineState: String, Sendable {
    /// Not ready (no timeline loaded, dependencies not initialized).
    case uninitialized

    /// Ready but not playing. Playhead at position 0 or reset.
    case stopped

    /// Actively playing back the composition.
    case playing

    /// Playback paused at the current playhead position.
    case paused

    /// User is scrubbing (dragging the playhead).
    case scrubbing

    /// Programmatic seek in progress.
    case seeking

    /// Building a new composition (rebuild/hot-swap cycle).
    case rebuilding

    /// An error has occurred; see ``PlaybackEngine/errorMessage``.
    case error
}

// MARK: - PlaybackEvent

/// Events emitted by the playback engine for UI observation.
enum PlaybackEvent: String, Sendable {
    /// Playback started.
    case started

    /// Playback paused.
    case paused

    /// Playback stopped (playhead reset to 0).
    case stopped

    /// Reached the end of the timeline.
    case ended

    /// Composition rebuild started.
    case rebuildStarted

    /// Composition rebuild completed (hot-swap done).
    case rebuildCompleted

    /// Scrubbing started.
    case scrubStarted

    /// Scrubbing ended.
    case scrubEnded

    /// An error occurred.
    case errorOccurred
}

// MARK: - PlaybackEngine

/// Central orchestrator for video playback.
///
/// Coordinates composition management, scrubbing, frame cache,
/// and decoder pool through a unified async API. All mutable state
/// is actor-isolated for safe concurrent access.
///
/// Usage:
/// ```swift
/// let engine = PlaybackEngine(
///     compositionManager: manager,
///     frameCache: cache,
///     decoderPool: pool,
///     scrubController: scrub
/// )
///
/// await engine.play()
///
/// for await event in engine.eventStream {
///     print("Event: \(event)")
/// }
/// ```
actor PlaybackEngine {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "PlaybackEngine"
    )

    // MARK: - Constants

    /// Playhead polling interval in nanoseconds (~30 FPS).
    private static let playheadPollIntervalNanoseconds: UInt64 = 33_000_000

    /// Microseconds per frame at 30 FPS, used for end-of-playback detection.
    private static let oneFrameMicrosecondsAt30fps: TimeMicros = 33_333

    /// Minimum allowable playback rate.
    private static let minimumPlaybackRate: Double = 0.1

    /// Maximum allowable playback rate.
    private static let maximumPlaybackRate: Double = 4.0

    // MARK: - Dependencies

    /// Composition manager for native AVPlayer playback.
    private let compositionManager: CompositionManager

    /// Frame cache for scrubbing frame storage.
    private let frameCache: FrameCache

    /// Decoder pool for multi-source frame extraction.
    private let decoderPool: NativeDecoderPool

    /// Scrub controller for scrub coordination.
    private let scrubController: ScrubController

    // MARK: - State

    /// Current engine state.
    private(set) var state: PlaybackEngineState = .uninitialized

    /// Current playhead position in microseconds.
    private(set) var playheadMicros: TimeMicros = 0

    /// Current playback rate multiplier (1.0 = normal speed).
    private(set) var playbackRate: Double = 1.0

    /// Current volume (0.0 = muted, 1.0 = full volume).
    private(set) var volume: Double = 1.0

    /// Whether looping is enabled.
    private(set) var isLooping: Bool = false

    /// Frame rate for frame snapping and frame-step operations.
    private(set) var frameRate: Rational = .fps30

    /// Error message when ``state`` is `.error`.
    private(set) var errorMessage: String?

    /// Total duration of the current timeline in microseconds.
    /// Updated via ``updateTimeline(_:)``.
    private var totalDurationMicros: TimeMicros = 0

    // MARK: - Tasks

    /// Background task polling the playhead during playback.
    private var playheadPollingTask: Task<Void, Never>?

    /// Background task listening to composition manager time updates.
    private var timeUpdateListenerTask: Task<Void, Never>?

    /// Background task listening to composition manager state updates.
    private var stateUpdateListenerTask: Task<Void, Never>?

    /// Flag indicating the engine has been disposed.
    private var isDisposed: Bool = false

    // MARK: - AsyncStream Infrastructure

    /// Continuation for the event stream.
    private var eventContinuation: AsyncStream<PlaybackEvent>.Continuation?

    /// Continuation for the playhead stream.
    private var playheadContinuation: AsyncStream<TimeMicros>.Continuation?

    /// Stream of playback events for UI observation.
    nonisolated let eventStream: AsyncStream<PlaybackEvent>

    /// Stream of playhead position updates (microseconds).
    nonisolated let playheadStream: AsyncStream<TimeMicros>

    // MARK: - Callbacks

    /// Called when a playback event occurs.
    var onPlaybackEvent: ((PlaybackEvent) -> Void)?

    /// Called when the playhead position changes.
    var onPlayheadChange: ((TimeMicros) -> Void)?

    /// Called when a scrub frame is ready.
    var onScrubFrame: ((FrameResult) -> Void)?

    /// Called when an error occurs.
    var onError: ((String) -> Void)?

    // MARK: - Initialization

    /// Creates a playback engine with injected dependencies.
    ///
    /// After creation, the engine is in the `.uninitialized` state.
    /// Call ``initialize()`` or ``updateTimeline(_:)`` to transition
    /// to `.stopped`.
    ///
    /// - Parameters:
    ///   - compositionManager: Manager for AVPlayer composition playback.
    ///   - frameCache: LRU frame cache for scrubbing frames.
    ///   - decoderPool: Pool of video frame decoders.
    ///   - scrubController: Controller for scrub gesture coordination.
    init(
        compositionManager: CompositionManager,
        frameCache: FrameCache,
        decoderPool: NativeDecoderPool,
        scrubController: ScrubController
    ) {
        self.compositionManager = compositionManager
        self.frameCache = frameCache
        self.decoderPool = decoderPool
        self.scrubController = scrubController

        // Build AsyncStreams before actor isolation takes hold.
        var eventCont: AsyncStream<PlaybackEvent>.Continuation?
        self.eventStream = AsyncStream { continuation in
            eventCont = continuation
        }
        self.eventContinuation = eventCont

        var playheadCont: AsyncStream<TimeMicros>.Continuation?
        self.playheadStream = AsyncStream { continuation in
            playheadCont = continuation
        }
        self.playheadContinuation = playheadCont
    }

    /// Initialize the engine.
    ///
    /// Transitions from `.uninitialized` to `.stopped`. Safe to call
    /// multiple times (no-op if already initialized).
    func initialize() {
        guard state == .uninitialized else { return }
        setState(.stopped)
        Self.logger.info("PlaybackEngine initialized")
    }

    // MARK: - Computed Properties

    /// Whether the engine is currently playing.
    var isPlaying: Bool { state == .playing }

    /// Whether the engine is currently paused.
    var isPaused: Bool { state == .paused }

    /// Whether the engine is stopped.
    var isStopped: Bool { state == .stopped }

    /// Whether the engine is scrubbing.
    var isScrubbing: Bool { state == .scrubbing }

    /// Whether the engine is ready for playback commands.
    var isReady: Bool { state != .uninitialized && state != .error }

    // MARK: - Playback Control

    /// Start playback from the current playhead position.
    ///
    /// If the engine is not ready or already playing, this is a no-op.
    func play() async {
        guard isReady else { return }
        guard state != .playing else { return }

        do {
            try await compositionManager.play()
            setState(.playing)
            startPlayheadPolling()
            emitEvent(.started)
        } catch {
            setError("Play failed: \(error.localizedDescription)")
        }
    }

    /// Pause playback.
    ///
    /// No-op if not currently playing.
    func pause() async {
        guard state == .playing else { return }

        do {
            try await compositionManager.pause()
            setState(.paused)
            stopPlayheadPolling()
            emitEvent(.paused)
        } catch {
            setError("Pause failed: \(error.localizedDescription)")
        }
    }

    /// Stop playback and reset the playhead to 0.
    func stop() async {
        do {
            try await compositionManager.pause()
            try await compositionManager.seek(to: 0)
            playheadMicros = 0
            setState(.stopped)
            stopPlayheadPolling()
            emitEvent(.stopped)
            emitPlayhead(0)
        } catch {
            setError("Stop failed: \(error.localizedDescription)")
        }
    }

    /// Toggle between play and pause.
    func togglePlayPause() async {
        if state == .playing {
            await pause()
        } else {
            await play()
        }
    }

    /// Seek to an absolute position.
    ///
    /// Clamps `timeMicros` to the valid timeline range `[0, totalDurationMicros]`.
    ///
    /// - Parameter timeMicros: Target position in microseconds.
    func seek(_ timeMicros: TimeMicros) async {
        guard isReady else { return }

        let clamped = clampTime(timeMicros)
        playheadMicros = clamped

        do {
            try await compositionManager.seek(to: clamped)
            emitPlayhead(clamped)
        } catch {
            setError("Seek failed: \(error.localizedDescription)")
        }
    }

    /// Seek forward by the given amount.
    ///
    /// - Parameter amountMicros: Duration to advance in microseconds.
    func seekForward(_ amountMicros: TimeMicros) async {
        await seek(playheadMicros + amountMicros)
    }

    /// Seek backward by the given amount.
    ///
    /// - Parameter amountMicros: Duration to rewind in microseconds.
    func seekBackward(_ amountMicros: TimeMicros) async {
        await seek(playheadMicros - amountMicros)
    }

    /// Advance to the next frame.
    func nextFrame() async {
        let frameMicros = frameRate.microsecondsPerFrame
        await seek(playheadMicros + frameMicros)
    }

    /// Retreat to the previous frame.
    func previousFrame() async {
        let frameMicros = frameRate.microsecondsPerFrame
        await seek(playheadMicros - frameMicros)
    }

    // MARK: - Playback Settings

    /// Set the playback rate.
    ///
    /// Clamped to the range `[minimumPlaybackRate, maximumPlaybackRate]`.
    ///
    /// - Parameter rate: Playback rate multiplier.
    func setPlaybackRate(_ rate: Double) async {
        playbackRate = min(max(rate, Self.minimumPlaybackRate), Self.maximumPlaybackRate)
        do {
            try await compositionManager.setPlaybackRate(Float(playbackRate))
        } catch {
            Self.logger.warning("Failed to set playback rate: \(error.localizedDescription)")
        }
    }

    /// Set the playback volume.
    ///
    /// Clamped to the range `[0.0, 1.0]`.
    ///
    /// - Parameter vol: Volume level.
    func setVolume(_ vol: Double) async {
        volume = min(max(vol, 0.0), 1.0)
        do {
            try await compositionManager.setVolume(Float(volume))
        } catch {
            Self.logger.warning("Failed to set volume: \(error.localizedDescription)")
        }
    }

    /// Enable or disable looping.
    ///
    /// - Parameter loop: Whether to loop when reaching the end.
    func setLooping(_ loop: Bool) {
        isLooping = loop
    }

    /// Set the frame rate used for frame-step operations and scrub snapping.
    ///
    /// Also updates the scrub controller's frame rate.
    ///
    /// - Parameter rate: The new frame rate.
    func setFrameRate(_ rate: Rational) {
        frameRate = rate
        scrubController.updateFrameRate(rate)
    }

    // MARK: - Scrubbing

    /// Begin a user-initiated scrub gesture.
    ///
    /// Pauses playhead polling and transitions to the `.scrubbing` state.
    func beginScrub() {
        guard isReady else { return }

        stopPlayheadPolling()
        setState(.scrubbing)
        scrubController.beginScrub()
        emitEvent(.scrubStarted)
    }

    /// Update the scrub position.
    ///
    /// No-op if the engine is not in the `.scrubbing` state.
    ///
    /// - Parameter timeMicros: Target scrub position in microseconds.
    func scrubTo(_ timeMicros: TimeMicros) async {
        guard state == .scrubbing else { return }

        let clamped = clampTime(timeMicros)
        playheadMicros = clamped

        let result = await scrubController.scrubTo(clamped)
        onScrubFrame?(result)
        emitPlayhead(clamped)
    }

    /// End the scrub gesture.
    ///
    /// Syncs the composition manager to the current playhead and
    /// transitions to `.paused`.
    func endScrub() async {
        guard state == .scrubbing else { return }

        scrubController.endScrub()

        // Sync composition manager to the final scrub position
        do {
            try await compositionManager.seek(to: playheadMicros)
        } catch {
            Self.logger.warning("Failed to sync after scrub: \(error.localizedDescription)")
        }

        setState(.paused)
        emitEvent(.scrubEnded)
    }

    /// Cancel an in-progress scrub gesture.
    ///
    /// Returns to `.paused` without syncing.
    func cancelScrub() {
        guard state == .scrubbing else { return }

        scrubController.cancel()
        setState(.paused)
    }

    // MARK: - Composition Management

    /// Rebuild the composition from segments and hot-swap it in.
    ///
    /// Transitions through `.rebuilding` state. If playback was in progress,
    /// it resumes after the swap. Otherwise the engine returns to `.paused`.
    ///
    /// - Parameter segments: The composition segments describing the timeline.
    func rebuildComposition(segments: [CompositionSegment]) async {
        guard state != .rebuilding else { return }

        let previousState = state
        setState(.rebuilding)
        emitEvent(.rebuildStarted)

        do {
            let handle = try await compositionManager.buildComposition(
                segments: segments
            )

            // Hot-swap at the current playhead
            try await compositionManager.hotSwap(handle, seekTo: playheadMicros)

            emitEvent(.rebuildCompleted)

            // Restore previous state
            if previousState == .playing {
                setState(.playing)
                startPlayheadPolling()
            } else {
                setState(.paused)
            }
        } catch {
            setError("Composition rebuild failed: \(error.localizedDescription)")
        }
    }

    /// Update the timeline reference.
    ///
    /// Forwards the new timeline to the scrub controller and clears
    /// the frame cache (frames may be stale after a timeline edit).
    ///
    /// - Parameter timeline: The new persistent timeline.
    func updateTimeline(_ timeline: PersistentTimeline) {
        totalDurationMicros = timeline.totalDurationMicros
        scrubController.updateTimeline(timeline)
        frameCache.clear()

        // If the engine was uninitialized, transition to stopped
        if state == .uninitialized {
            setState(.stopped)
        }
    }

    // MARK: - Memory Pressure

    /// Handle a system memory pressure notification.
    ///
    /// Forwards pressure to the frame cache and decoder pool so they
    /// can reduce their memory footprint.
    ///
    /// - Parameter level: The pressure level (0 = normal, 1 = warning, 2 = critical).
    func handleMemoryPressure(_ level: Int) {
        frameCache.handleMemoryPressure(MemoryPressureLevel(rawValue: level) ?? .normal)
        decoderPool.handleMemoryPressure(level: level)
        Self.logger.info("Memory pressure handled at level \(level)")
    }

    // MARK: - Statistics

    /// Debugging statistics for the engine and its dependencies.
    var statistics: [String: String] {
        [
            "state": state.rawValue,
            "playheadMicros": "\(playheadMicros)",
            "totalDurationMicros": "\(totalDurationMicros)",
            "playbackRate": "\(playbackRate)",
            "volume": "\(volume)",
            "isLooping": "\(isLooping)",
            "frameRate": frameRate.frameRateString,
            "decoderCount": "\(decoderPool.decoderCount)",
        ]
    }

    // MARK: - Cleanup

    /// Dispose the engine and release all resources.
    ///
    /// Cancels background tasks, disposes dependencies, and finishes
    /// all async streams. The engine should not be used after this call.
    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true

        // Cancel background tasks
        stopPlayheadPolling()
        timeUpdateListenerTask?.cancel()
        timeUpdateListenerTask = nil
        stateUpdateListenerTask?.cancel()
        stateUpdateListenerTask = nil

        // Dispose dependencies
        scrubController.dispose()
        frameCache.dispose()
        decoderPool.disposeAll()
        compositionManager.dispose()

        // Finish streams
        eventContinuation?.finish()
        playheadContinuation?.finish()

        // Clear callbacks
        onPlaybackEvent = nil
        onPlayheadChange = nil
        onScrubFrame = nil
        onError = nil

        Self.logger.info("PlaybackEngine disposed")
    }

    // MARK: - Playhead Polling

    /// Start periodic playhead polling (~30 FPS).
    ///
    /// Creates a background `Task` that sleeps for 33 ms between polls.
    /// Checks for end-of-playback and handles looping.
    private func startPlayheadPolling() {
        stopPlayheadPolling()

        playheadPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.updatePlayhead()

                do {
                    try await Task.sleep(nanoseconds: Self.playheadPollIntervalNanoseconds)
                } catch {
                    // Task was cancelled
                    return
                }
            }
        }
    }

    /// Stop the playhead polling task.
    private func stopPlayheadPolling() {
        playheadPollingTask?.cancel()
        playheadPollingTask = nil
    }

    /// Poll the composition manager for the current playhead and
    /// check for end-of-playback.
    private func updatePlayhead() async {
        guard state == .playing else { return }

        let currentMicros = await compositionManager.currentTime()
        playheadMicros = currentMicros
        emitPlayhead(currentMicros)

        // Check for end of playback (within ~1 frame of end)
        if currentMicros >= totalDurationMicros - Self.oneFrameMicrosecondsAt30fps, totalDurationMicros > 0 {
            if isLooping {
                await seek(0)
            } else {
                await pause()
                emitEvent(.ended)
            }
        }
    }

    // MARK: - Internal Helpers

    /// Clamp a time value to the valid timeline range.
    private func clampTime(_ timeMicros: TimeMicros) -> TimeMicros {
        if timeMicros < 0 { return 0 }
        if timeMicros > totalDurationMicros { return totalDurationMicros }
        return timeMicros
    }

    /// Transition to a new state.
    ///
    /// Clears the error message when transitioning away from `.error`.
    private func setState(_ newState: PlaybackEngineState) {
        guard state != newState else { return }
        state = newState
        errorMessage = nil
    }

    /// Transition to the error state with a message.
    ///
    /// Emits both the error callback and the `.errorOccurred` event.
    private func setError(_ message: String) {
        Self.logger.error("\(message)")
        errorMessage = message
        state = .error
        onError?(message)
        emitEvent(.errorOccurred)
    }

    /// Emit a playback event to both the callback and the async stream.
    private func emitEvent(_ event: PlaybackEvent) {
        onPlaybackEvent?(event)
        eventContinuation?.yield(event)
    }

    /// Emit a playhead update to both the callback and the async stream.
    private func emitPlayhead(_ timeMicros: TimeMicros) {
        onPlayheadChange?(timeMicros)
        playheadContinuation?.yield(timeMicros)
    }
}
