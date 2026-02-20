// CompositionManager.swift
// LiquidEditor
//
// Double-buffered composition management for zero-interruption playback.
//
// Features:
// - Hot-swap compositions without playback interruption
// - Double-buffered A/B composition switching
// - Play, pause, seek, rate control, volume control
// - AsyncStream for time updates and state changes
// - Thread-safe with OSAllocatedUnfairLock protection

import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "CompositionManager")

// MARK: - CompositionTimeUpdate

/// Time update emitted during playback.
struct CompositionTimeUpdate: Sendable {
    /// Current playhead time in microseconds.
    let timeMicros: TimeMicros

    /// Total composition duration in microseconds.
    let durationMicros: TimeMicros

    /// Whether playback is currently active.
    let isPlaying: Bool
}

// MARK: - CompositionManager

/// Double-buffered composition manager for zero-interruption playback.
///
/// Manages an AVPlayer with hot-swap capability. When a new composition
/// is built in the background, it can be swapped in without stopping
/// playback using ``hotSwap(_:seekTo:)``.
///
/// Thread Safety:
/// - All mutable state is protected by `stateLock` (`OSAllocatedUnfairLock`).
/// - AVPlayer operations are dispatched to the main thread where required.
/// - Time updates are emitted via AsyncStream from the player's periodic observer.
///
/// Usage:
/// ```swift
/// let manager = CompositionManager()
/// let handle = try await builder.build(segments: segments, compositionId: "1")
/// try await manager.hotSwap(handle, seekTo: 0)
/// try await manager.play()
///
/// for await update in manager.timeUpdates {
///     print("Time: \(update.timeMicros)")
/// }
/// ```
final class CompositionManager: @unchecked Sendable {

    // MARK: - Constants

    /// Time observer polling rate (30 FPS).
    private static let timeObserverFPS: Int32 = 30

    // MARK: - Properties

    /// Active composition (currently loaded in player).
    private var activeComposition: BuiltComposition?

    /// Pending composition (built but not yet swapped in).
    private var pendingComposition: BuiltComposition?

    /// The AVPlayer instance.
    private var _player: AVPlayer?

    /// Read-only access to the underlying AVPlayer for UI display.
    ///
    /// The player is created lazily during the first ``hotSwap(_:seekTo:)``
    /// call. Returns `nil` before any composition has been loaded.
    /// Must be accessed from the main actor since AVPlayer is main-thread bound.
    var player: AVPlayer? { _player }

    /// Current player item.
    private var playerItem: AVPlayerItem?

    /// Player layer for video display.
    private(set) var playerLayer: AVPlayerLayer?

    /// Time observer token.
    private var timeObserverToken: Any?

    /// Current playback rate (preserved across swaps).
    private var currentPlaybackRate: Float = 1.0

    /// Whether playback is active.
    private var _isPlaying: Bool = false

    /// Lock for all mutable state.
    private let stateLock = OSAllocatedUnfairLock()

    /// Composition builder for building new compositions.
    private let builder = CompositionBuilder()

    /// Next composition ID counter.
    private var nextCompositionId: Int = 0

    // MARK: - AsyncStream Infrastructure

    /// Time update continuation for the async stream.
    private var timeUpdateContinuation: AsyncStream<CompositionTimeUpdate>.Continuation?

    /// State update continuation for the async stream.
    private var stateUpdateContinuation: AsyncStream<PlaybackState>.Continuation?

    /// Stream of playback time updates emitted during playback.
    ///
    /// Updates are emitted at ~30 FPS while playing.
    let timeUpdates: AsyncStream<CompositionTimeUpdate>

    /// Stream of playback state changes.
    let stateUpdates: AsyncStream<PlaybackState>

    // MARK: - Initialization

    init() {
        var timeCont: AsyncStream<CompositionTimeUpdate>.Continuation?
        timeUpdates = AsyncStream { continuation in
            timeCont = continuation
        }
        timeUpdateContinuation = timeCont

        var stateCont: AsyncStream<PlaybackState>.Continuation?
        stateUpdates = AsyncStream { continuation in
            stateCont = continuation
        }
        stateUpdateContinuation = stateCont
    }

    // MARK: - Build & Swap

    /// Build a composition from segments.
    ///
    /// Builds the composition in the background and stores it as the
    /// pending composition. Call ``hotSwap(_:seekTo:)`` to activate it.
    ///
    /// - Parameter segments: Ordered list of composition segments.
    /// - Returns: The built composition handle.
    /// - Throws: ``CompositionBuildError`` if building fails.
    func buildComposition(
        segments: [CompositionSegment]
    ) async throws -> CompositionHandle {
        let compositionId: String = stateLock.withLock {
            let id = "comp_\(nextCompositionId)"
            nextCompositionId += 1
            return id
        }

        let built = try await builder.build(
            segments: segments,
            compositionId: compositionId
        )

        stateLock.withLock {
            pendingComposition = built
        }

        return CompositionHandle(
            id: built.id,
            composition: built.composition,
            videoComposition: built.videoComposition,
            audioMix: built.audioMix,
            duration: built.totalDurationMicros
        )
    }

    /// Hot-swap to a new composition without playback interruption.
    ///
    /// The pending composition is swapped into the active slot. If
    /// playback was in progress, it resumes at the specified seek time.
    ///
    /// - Parameters:
    ///   - handle: The composition handle to swap in.
    ///   - time: Time position (microseconds) to seek to after swap.
    /// - Throws: ``CompositionManagerError/compositionNotFound`` if the handle
    ///   does not match the pending composition.
    func hotSwap(
        _ handle: CompositionHandle,
        seekTo time: TimeMicros
    ) async throws {
        let (pending, wasPlaying, rate) = try stateLock.withLock {
            guard let pending = pendingComposition, pending.id == handle.id else {
                throw CompositionManagerError.compositionNotFound(handle.id)
            }
            return (pending, _isPlaying, currentPlaybackRate)
        }

        // Create new player item on main actor (AVPlayerItem.init(asset:) is main-actor-isolated)
        let newItem = await MainActor.run {
            let item = AVPlayerItem(asset: pending.composition)
            if let videoComp = pending.videoComposition {
                item.videoComposition = videoComp
            }
            if let audioMix = pending.audioMix {
                item.audioMix = audioMix
            }
            return item
        }

        // Perform player swap on main thread for UI safety
        await MainActor.run {
            self.performPlayerSwap(
                newItem: newItem,
                pending: pending,
                seekTimeMicros: time,
                wasPlaying: wasPlaying,
                rate: rate
            )
        }
    }

    /// Internal player swap logic. Must be called on main thread.
    @MainActor
    private func performPlayerSwap(
        newItem: AVPlayerItem,
        pending: BuiltComposition,
        seekTimeMicros: TimeMicros,
        wasPlaying: Bool,
        rate: Float
    ) {
        // Remove old end-of-playback observer FIRST
        if let oldItem = playerItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: oldItem
            )
        }

        // Remove old time observer BEFORE creating new one
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        // Create or replace player
        if _player == nil {
            _player = AVPlayer(playerItem: newItem)
            playerLayer = AVPlayerLayer(player: _player)
            playerLayer?.videoGravity = .resizeAspect
        } else {
            _player?.replaceCurrentItem(with: newItem)
        }

        playerItem = newItem

        // Seek to position
        let seekTime = CMTime(value: CMTimeValue(seekTimeMicros), timescale: 1_000_000)
        player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)

        // Swap composition references
        stateLock.withLock {
            activeComposition = pending
            pendingComposition = nil
        }

        // Set up NEW time observer after cleanup
        setupTimeObserver()

        // Observe end of playback
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: newItem
        )

        // Resume if was playing
        if wasPlaying {
            player?.rate = rate
            stateLock.withLock {
                _isPlaying = true
            }
        }
    }

    // MARK: - Playback Control

    /// Start playback from the current position.
    func play() async throws {
        let rate = stateLock.withLock { currentPlaybackRate }

        await MainActor.run {
            self.player?.rate = rate
        }

        stateLock.withLock {
            _isPlaying = true
        }

        stateUpdateContinuation?.yield(.playing)
    }

    /// Pause playback.
    func pause() async throws {
        await MainActor.run {
            self.player?.pause()
        }

        stateLock.withLock {
            _isPlaying = false
        }

        stateUpdateContinuation?.yield(.paused)
    }

    /// Seek to a specific time position.
    ///
    /// - Parameter time: Target time in microseconds.
    func seek(to time: TimeMicros) async throws {
        let cmTime = CMTime(value: CMTimeValue(time), timescale: 1_000_000)
        await MainActor.run {
            self.player?.seek(
                to: cmTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    /// Set the playback rate.
    ///
    /// - Parameter rate: Playback rate multiplier (1.0 = normal speed).
    func setPlaybackRate(_ rate: Float) async throws {
        let playing = stateLock.withLock {
            currentPlaybackRate = rate
            return _isPlaying
        }

        if playing {
            await MainActor.run {
                self.player?.rate = rate
            }
        }
    }

    /// Set the playback volume.
    ///
    /// - Parameter volume: Volume level (0.0 = muted, 1.0 = full volume).
    func setVolume(_ volume: Float) async throws {
        await MainActor.run {
            self.player?.volume = volume
        }
    }

    /// Get the current playhead position in microseconds.
    func currentTime() async -> TimeMicros {
        await MainActor.run {
            guard let currentTime = self.player?.currentTime() else { return 0 }
            return TimeMicros(CMTimeGetSeconds(currentTime) * 1_000_000)
        }
    }

    /// Whether the player is currently playing.
    var isPlaying: Bool {
        stateLock.withLock { _isPlaying }
    }

    /// Duration of the active composition in microseconds, or 0 if none.
    var activeDuration: TimeMicros {
        stateLock.withLock { activeComposition?.totalDurationMicros ?? 0 }
    }

    /// The active composition ID, or nil.
    var activeCompositionId: String? {
        stateLock.withLock { activeComposition?.id }
    }

    // MARK: - Time Observer

    /// Set up periodic time observer on the player.
    ///
    /// Must be called on main thread.
    @MainActor
    private func setupTimeObserver() {
        guard let player else { return }

        let interval = CMTime(value: 1, timescale: Self.timeObserverFPS)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let micros = TimeMicros(CMTimeGetSeconds(time) * 1_000_000)

            let (playing, duration) = self.stateLock.withLock {
                (self._isPlaying, self.activeComposition?.totalDurationMicros ?? 0)
            }

            let update = CompositionTimeUpdate(
                timeMicros: micros,
                durationMicros: duration,
                isPlaying: playing
            )
            self.timeUpdateContinuation?.yield(update)
        }
    }

    @MainActor
    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        stateLock.withLock {
            _isPlaying = false
        }

        stateUpdateContinuation?.yield(.paused)
    }

    // MARK: - Dispose

    /// Dispose a specific composition by ID.
    ///
    /// Clears the composition from active or pending slots.
    func disposeComposition(id: String) {
        stateLock.withLock {
            if activeComposition?.id == id {
                activeComposition = nil
            }
            if pendingComposition?.id == id {
                pendingComposition = nil
            }
        }
    }

    /// Dispose the manager and release all resources.
    ///
    /// After calling this, the manager should not be used.
    func dispose() {
        // Capture references before Task to avoid retaining self
        let player = _player
        let token = timeObserverToken

        // AVPlayer operations must be on main actor
        Task { @MainActor in
            if let token = token {
                player?.removeTimeObserver(token)
            }
            player?.pause()
        }

        // Synchronous cleanup (safe from any thread)
        NotificationCenter.default.removeObserver(self)
        timeObserverToken = nil
        _player = nil
        playerItem = nil
        playerLayer = nil

        stateLock.withLock {
            activeComposition = nil
            pendingComposition = nil
            _isPlaying = false
        }

        builder.clearCache()

        timeUpdateContinuation?.finish()
        stateUpdateContinuation?.finish()
    }

    deinit {
        // Capture references before creating Task to avoid self-capture during deinit
        let player = _player
        let token = timeObserverToken

        NotificationCenter.default.removeObserver(self)

        timeUpdateContinuation?.finish()
        stateUpdateContinuation?.finish()

        // Fire-and-forget cleanup on main actor without capturing self
        Task { @MainActor in
            if let token = token {
                player?.removeTimeObserver(token)
            }
            player?.pause()
        }
    }
}

// MARK: - CompositionManagerError

/// Errors specific to the composition manager.
enum CompositionManagerError: LocalizedError, Sendable {
    /// The specified composition was not found in the pending slot.
    case compositionNotFound(String)

    /// Player is not initialized.
    case playerNotInitialized

    var errorDescription: String? {
        switch self {
        case let .compositionNotFound(id):
            return "Composition '\(id)' not found in pending slot."
        case .playerNotInitialized:
            return "Player has not been initialized. Build and swap a composition first."
        }
    }
}
