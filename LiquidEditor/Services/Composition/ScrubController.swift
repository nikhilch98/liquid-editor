// ScrubController.swift
// LiquidEditor
//
// Controller for scrubbing operations — coordinates frame cache with user
// scrubbing gestures.
//
// Responsibilities:
// - Track scrub state (idle, scrubbing, settling, seeking)
// - Request frames from decoder pool via frame cache
// - Manage prefetch based on scrub velocity and direction
// - Handle graceful degradation (show I-frames when scrubbing fast)
//
// Thread Safety:
// - All mutable state is protected by `OSAllocatedUnfairLock`.
// - Async work (settling, prefetch) uses `Task` with cancellation.
//

import Foundation
import os

// MARK: - ScrubState

/// Scrub state for the controller.
enum ScrubState: String, Sendable {
    /// Not scrubbing, playhead stationary.
    case idle

    /// Actively scrubbing (finger on timeline).
    case scrubbing

    /// Just released, settling (momentum scrolling).
    case settling

    /// Seeking to a specific position.
    case seeking
}

// MARK: - ScrubVelocity

/// Scrub velocity category for adaptive quality.
enum ScrubVelocity: String, Sendable {
    /// Slow scrub - show exact frames.
    case slow

    /// Medium scrub - show exact frames if cached, I-frames otherwise.
    case medium

    /// Fast scrub - show I-frames only.
    case fast
}

// MARK: - FrameResult

/// Frame request result.
struct FrameResult: Sendable {
    /// The frame data, or nil if not available.
    let frame: CachedFrame?

    /// Whether this is an exact frame or I-frame approximation.
    let isExact: Bool

    /// Asset ID this frame belongs to.
    let assetId: String?

    /// Timeline position of this frame.
    let timeMicros: TimeMicros

    /// Whether frame is from cache (instant) or freshly decoded.
    let wasCached: Bool

    /// Whether a frame is available.
    var hasFrame: Bool { frame != nil }

    /// Creates a frame result.
    init(
        frame: CachedFrame? = nil,
        isExact: Bool = true,
        assetId: String? = nil,
        timeMicros: TimeMicros,
        wasCached: Bool = false
    ) {
        self.frame = frame
        self.isExact = isExact
        self.assetId = assetId
        self.timeMicros = timeMicros
        self.wasCached = wasCached
    }
}

// MARK: - VelocitySample

/// Velocity sample for tracking scrub speed.
private struct VelocitySample: Sendable {
    let fromMicros: TimeMicros
    let toMicros: TimeMicros
    let timestamp: ContinuousClock.Instant
}

// MARK: - ScrubController

/// Controller for scrubbing operations.
///
/// Coordinates between user gestures, frame cache, and decoder pool
/// to provide smooth scrubbing experience.
///
/// Uses `OSAllocatedUnfairLock` for thread-safe access to mutable state
/// and `Task`-based concurrency for settling and prefetch timers.
final class ScrubController: @unchecked Sendable {

    // MARK: - Constants

    /// Maximum velocity samples to track.
    private static let maxVelocitySamples = 5

    /// Velocity threshold: below this is "slow" (microseconds per second).
    private static let slowThreshold: Int64 = 500_000 // 0.5 sec/sec

    /// Velocity threshold: above this is "fast" (microseconds per second).
    private static let fastThreshold: Int64 = 2_000_000 // 2 sec/sec

    /// Duration to wait after scrub release before transitioning to idle.
    private static let settlingDuration: UInt64 = 300_000_000 // 300ms in nanoseconds

    /// Debounce delay before scheduling prefetch.
    private static let prefetchDelay: UInt64 = 50_000_000 // 50ms in nanoseconds

    // MARK: - Dependencies

    /// Frame cache for instant frame access.
    private let frameCache: FrameCache

    /// Decoder pool for multi-source decoding.
    private let decoderPool: NativeDecoderPool

    // MARK: - Mutable State (protected by lock)

    /// State container for lock-protected fields.
    private struct State: Sendable {
        var timeline: PersistentTimeline
        var frameRate: Rational
        var scrubState: ScrubState = .idle
        var playheadMicros: TimeMicros = 0
        var velocitySamples: [VelocitySample] = []
    }

    /// Lock protecting all mutable state.
    private let lock: OSAllocatedUnfairLock<State>

    // MARK: - Task Handles

    /// Settling timer task (cancelled on new scrub or cancel).
    private let settlingTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    /// Prefetch debounce task.
    private let prefetchTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    // MARK: - Callbacks

    /// Callback when frame is ready.
    var onFrameReady: (@Sendable (FrameResult) -> Void)?

    /// Callback when scrub state changes.
    var onStateChange: (@Sendable (ScrubState) -> Void)?

    /// Closure to resolve asset URL from asset ID.
    /// Required for acquiring decoders from the pool.
    var resolveAssetURL: (@Sendable (String) -> URL?)?

    // MARK: - Initialization

    /// Creates a scrub controller.
    ///
    /// - Parameters:
    ///   - frameCache: Frame cache for instant frame access.
    ///   - decoderPool: Decoder pool for multi-source decoding.
    ///   - timeline: Initial persistent timeline.
    ///   - frameRate: Frame rate for frame boundary snapping (defaults to 30fps).
    init(
        frameCache: FrameCache,
        decoderPool: NativeDecoderPool,
        timeline: PersistentTimeline,
        frameRate: Rational = .fps30
    ) {
        self.frameCache = frameCache
        self.decoderPool = decoderPool
        self.lock = OSAllocatedUnfairLock(
            initialState: State(timeline: timeline, frameRate: frameRate)
        )
    }

    // MARK: - Getters

    /// Current scrub state.
    var state: ScrubState {
        lock.withLock { $0.scrubState }
    }

    /// Whether actively scrubbing.
    var isScrubbing: Bool { state == .scrubbing }

    /// Whether settling after scrub.
    var isSettling: Bool { state == .settling }

    /// Whether seeking.
    var isSeeking: Bool { state == .seeking }

    /// Whether idle.
    var isIdle: Bool { state == .idle }

    /// Current playhead position in microseconds.
    var playheadMicros: TimeMicros {
        lock.withLock { $0.playheadMicros }
    }

    /// Current frame rate.
    var frameRate: Rational {
        lock.withLock { $0.frameRate }
    }

    /// Current velocity category.
    var velocity: ScrubVelocity {
        lock.withLock { Self.calculateVelocity(from: $0.velocitySamples) }
    }

    // MARK: - Configuration

    /// Update timeline reference.
    func updateTimeline(_ timeline: PersistentTimeline) {
        lock.withLock { $0.timeline = timeline }
    }

    /// Update frame rate.
    func updateFrameRate(_ frameRate: Rational) {
        lock.withLock { $0.frameRate = frameRate }
    }

    // MARK: - Scrub Control

    /// Begin scrubbing (finger down on timeline).
    func beginScrub() {
        cancelSettlingTask()

        lock.withLock { state in
            state.velocitySamples.removeAll()
        }

        setState(.scrubbing)
        frameCache.cancelPrefetch()
    }

    /// Update scrub position.
    ///
    /// Returns a frame result (may be from cache or async decode).
    func scrubTo(_ timeMicros: TimeMicros) async -> FrameResult {
        let (clampedTime, previousPosition) = lock.withLock { state -> (TimeMicros, TimeMicros) in
            let previous = state.playheadMicros
            let clamped = Self.clampToTimeline(timeMicros, totalDuration: state.timeline.totalDurationMicros)
            state.playheadMicros = clamped

            // Record velocity sample
            let now = ContinuousClock.now
            state.velocitySamples.append(VelocitySample(
                fromMicros: previous,
                toMicros: clamped,
                timestamp: now
            ))

            // Trim old samples
            while state.velocitySamples.count > Self.maxVelocitySamples {
                state.velocitySamples.removeFirst()
            }

            return (clamped, previous)
        }

        // Record for cache direction detection
        frameCache.recordScrubPosition(clampedTime)

        // Get frame based on velocity
        let result = await getFrameForPosition(clampedTime)

        // Schedule prefetch
        schedulePrefetch()

        return result
    }

    /// End scrubbing (finger lifted).
    func endScrub() {
        setState(.settling)

        // Cancel any existing settling task
        cancelSettlingTask()

        // Start settling timer
        let task = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: Self.settlingDuration)
            } catch {
                // Task was cancelled
                return
            }

            self.setState(.idle)
            self.lock.withLock { $0.velocitySamples.removeAll() }

            // Trigger final frame decode at exact position
            let playhead = self.playheadMicros
            await self.decodeExactFrame(playhead)
        }

        settlingTask.withLock { $0 = task }
    }

    /// Seek to specific position (programmatic, not user scrub).
    func seekTo(_ timeMicros: TimeMicros) async -> FrameResult {
        cancelSettlingTask()
        setState(.seeking)

        let clamped = lock.withLock { state -> TimeMicros in
            let clamped = Self.clampToTimeline(timeMicros, totalDuration: state.timeline.totalDurationMicros)
            state.playheadMicros = clamped
            return clamped
        }

        let result = await getFrameForPosition(clamped, forceExact: true)

        setState(.idle)
        schedulePrefetch()

        return result
    }

    /// Cancel any ongoing operations.
    func cancel() {
        cancelPrefetchTask()
        cancelSettlingTask()
        frameCache.cancelPrefetch()
        setState(.idle)
    }

    // MARK: - Frame Retrieval

    /// Get frame for a timeline position.
    ///
    /// Determines which clip is at the given time and retrieves
    /// the appropriate frame based on clip type and scrub velocity.
    private func getFrameForPosition(
        _ timeMicros: TimeMicros,
        forceExact: Bool = false
    ) async -> FrameResult {
        // Read timeline snapshot under lock
        let timeline = lock.withLock { $0.timeline }

        // Find which clip is at this time
        guard let clipResult = timeline.itemAtTime(timeMicros) else {
            return FrameResult(timeMicros: timeMicros)
        }

        let (item, offsetWithin) = clipResult

        // Handle different clip types
        if let videoClip = item as? VideoClip {
            return await getVideoFrame(videoClip, offsetWithin: offsetWithin,
                                       timelineMicros: timeMicros, forceExact: forceExact)
        } else if let imageClip = item as? ImageClip {
            return await getImageFrame(imageClip, timelineMicros: timeMicros)
        } else if item is ColorClip {
            return getColorFrame(timeMicros: timeMicros)
        } else if item is GapClip {
            // Gap clips show black/transparent
            return FrameResult(
                isExact: true,
                assetId: nil,
                timeMicros: timeMicros
            )
        }

        return FrameResult(timeMicros: timeMicros)
    }

    /// Get a video frame using the cache/decoder pipeline.
    private func getVideoFrame(
        _ clip: VideoClip,
        offsetWithin: Int64,
        timelineMicros: TimeMicros,
        forceExact: Bool
    ) async -> FrameResult {
        // Calculate source time within the clip
        let sourceMicros = clip.sourceInMicros + offsetWithin

        // Check cache first (instant)
        if let cached = frameCache.getFrame(assetId: clip.mediaAssetId, timeMicros: sourceMicros) {
            let result = FrameResult(
                frame: cached,
                isExact: cached.isExact,
                assetId: clip.mediaAssetId,
                timeMicros: timelineMicros,
                wasCached: true
            )
            onFrameReady?(result)
            return result
        }

        // Determine decode strategy based on velocity
        let velocityCat = velocity
        var frame: CachedFrame?

        if forceExact || velocityCat == .slow {
            // Decode exact frame
            frame = await decodeFrameFromPool(
                assetId: clip.mediaAssetId,
                timeMicros: sourceMicros,
                exact: true
            )
        } else if velocityCat == .medium {
            // Try nearest cached, else I-frame
            let nearest = frameCache.getNearestFrame(assetId: clip.mediaAssetId, timeMicros: sourceMicros)
            if nearest != nil {
                frame = nearest
            } else {
                frame = await decodeFrameFromPool(
                    assetId: clip.mediaAssetId,
                    timeMicros: sourceMicros,
                    exact: false
                )
            }
        } else {
            // Fast scrub - I-frame only
            frame = await decodeFrameFromPool(
                assetId: clip.mediaAssetId,
                timeMicros: sourceMicros,
                exact: false
            )
        }

        // Cache the frame if we got one
        if let frame {
            frameCache.addFrame(frame)
        }

        let result = FrameResult(
            frame: frame,
            isExact: frame?.isExact ?? false,
            assetId: clip.mediaAssetId,
            timeMicros: timelineMicros,
            wasCached: false
        )

        onFrameReady?(result)
        return result
    }

    /// Get a frame for an image clip.
    private func getImageFrame(
        _ clip: ImageClip,
        timelineMicros: TimeMicros
    ) async -> FrameResult {
        // Images are static - check cache at time 0
        if let cached = frameCache.getFrame(assetId: clip.mediaAssetId, timeMicros: 0) {
            return FrameResult(
                frame: cached,
                isExact: true,
                assetId: clip.mediaAssetId,
                timeMicros: timelineMicros,
                wasCached: true
            )
        }

        // Decode image
        let frame = await decodeFrameFromPool(
            assetId: clip.mediaAssetId,
            timeMicros: 0,
            exact: true
        )

        if let frame {
            frameCache.addFrame(frame)
        }

        return FrameResult(
            frame: frame,
            isExact: true,
            assetId: clip.mediaAssetId,
            timeMicros: timelineMicros,
            wasCached: false
        )
    }

    /// Get a result for a color clip.
    ///
    /// Color clips are generated by the rendering layer using `colorValue`.
    /// No decoding needed.
    private func getColorFrame(timeMicros: TimeMicros) -> FrameResult {
        FrameResult(
            isExact: true,
            assetId: nil,
            timeMicros: timeMicros
        )
    }

    /// Decode exact frame at the current playhead (used after settling).
    private func decodeExactFrame(_ timeMicros: TimeMicros) async {
        let result = await getFrameForPosition(timeMicros, forceExact: true)
        onFrameReady?(result)
    }

    // MARK: - Decoder Pool Integration

    /// Decode a frame using the decoder pool.
    ///
    /// Acquires (or reuses) a decoder for the given asset, then decodes
    /// either an exact frame or an I-frame depending on the `exact` flag.
    ///
    /// - Parameters:
    ///   - assetId: The media asset ID.
    ///   - timeMicros: Target source time in microseconds.
    ///   - exact: If true, decode exact frame; if false, decode I-frame (fast).
    /// - Returns: A `CachedFrame` if decoding succeeded, or nil on failure.
    private func decodeFrameFromPool(
        assetId: String,
        timeMicros: TimeMicros,
        exact: Bool
    ) async -> CachedFrame? {
        guard let resolveURL = resolveAssetURL,
              let url = resolveURL(assetId) else {
            return nil
        }

        do {
            let decoderId = try decoderPool.acquireDecoder(assetId: assetId, assetURL: url)

            let decoded: DecodedFrame
            if exact {
                decoded = try decoderPool.decodeFrame(decoderId: decoderId, timeMicros: timeMicros)
            } else {
                decoded = try decoderPool.decodeIFrame(decoderId: decoderId, timeMicros: timeMicros)
            }

            return CachedFrame(
                assetId: assetId,
                timeMicros: decoded.timeMicros,
                pixels: decoded.pixels,
                width: decoded.width,
                height: decoded.height,
                isExact: decoded.isExact
            )
        } catch {
            return nil
        }
    }

    // MARK: - Prefetching

    /// Schedule prefetch with debounce.
    private func schedulePrefetch() {
        cancelPrefetchTask()

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: Self.prefetchDelay)
            } catch {
                // Task was cancelled
                return
            }

            await self.executePrefetch()
        }

        prefetchTask.withLock { $0 = task }
    }

    /// Execute prefetch around the current playhead.
    private func executePrefetch() async {
        let currentState = state
        guard currentState == .scrubbing || currentState == .idle else {
            return
        }

        // Read current position and timeline under lock
        let (playhead, timeline, frameDuration) = lock.withLock { state in
            (state.playheadMicros, state.timeline, state.frameRate.microsecondsPerFrame)
        }

        // Find current clip
        guard let clipResult = timeline.itemAtTime(playhead) else { return }

        let (item, offsetWithin) = clipResult
        guard let clip = item as? VideoClip else { return }

        let sourceMicros = clip.sourceInMicros + offsetWithin
        let assetId = clip.mediaAssetId

        // Prefetch around current position
        await frameCache.prefetchAround(
            assetId: assetId,
            centerMicros: sourceMicros,
            frameDurationMicros: frameDuration,
            decodeFrame: { [weak self] timeMicros in
                guard let self else { return nil }
                return await self.decodeFrameFromPool(
                    assetId: assetId,
                    timeMicros: timeMicros,
                    exact: true
                )
            }
        )
    }

    // MARK: - Velocity Tracking

    /// Calculate velocity category from velocity samples.
    private static func calculateVelocity(from samples: [VelocitySample]) -> ScrubVelocity {
        guard samples.count >= 2 else {
            return .slow
        }

        // Calculate average velocity
        var totalDelta: Int64 = 0
        var totalDuration: Duration = .zero

        for i in 1 ..< samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]

            totalDelta += abs(curr.toMicros - prev.toMicros)
            totalDuration += curr.timestamp.duration(to: prev.timestamp)
        }

        // Convert duration to milliseconds
        let totalMs = abs(totalDuration.components.seconds) * 1000
            + abs(totalDuration.components.attoseconds) / 1_000_000_000_000_000

        guard totalMs > 0 else { return .slow }

        // Microseconds per second
        let velocityMicrosPerSecond = (totalDelta * 1000) / totalMs

        if velocityMicrosPerSecond < slowThreshold {
            return .slow
        } else if velocityMicrosPerSecond < fastThreshold {
            return .medium
        } else {
            return .fast
        }
    }

    // MARK: - Helpers

    /// Clamp time to timeline bounds.
    private static func clampToTimeline(_ timeMicros: TimeMicros, totalDuration: TimeMicros) -> TimeMicros {
        if timeMicros < 0 { return 0 }
        if timeMicros > totalDuration { return totalDuration }
        return timeMicros
    }

    /// Set scrub state and notify.
    private func setState(_ newState: ScrubState) {
        let changed = lock.withLock { state -> Bool in
            guard state.scrubState != newState else { return false }
            state.scrubState = newState
            return true
        }

        if changed {
            onStateChange?(newState)
        }
    }

    /// Cancel the settling task.
    private func cancelSettlingTask() {
        settlingTask.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    /// Cancel the prefetch task.
    private func cancelPrefetchTask() {
        prefetchTask.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    // MARK: - Cleanup

    /// Cancel all tasks and reset state.
    ///
    /// Call this when the controller is being deinitialized or
    /// when a new editing session starts.
    func dispose() {
        cancelPrefetchTask()
        cancelSettlingTask()
        frameCache.cancelPrefetch()
    }

    deinit {
        // Cancel tasks synchronously on deinit
        settlingTask.withLock { $0?.cancel() }
        prefetchTask.withLock { $0?.cancel() }
    }

    // MARK: - Statistics

    /// Get scrub statistics for debugging.
    var statistics: [String: Any] {
        let (currentState, playhead, velocitySampleCount) = lock.withLock { state in
            (state.scrubState.rawValue, state.playheadMicros, state.velocitySamples.count)
        }

        return [
            "state": currentState,
            "playheadMicros": playhead,
            "velocity": velocity.rawValue,
            "velocitySamples": velocitySampleCount,
        ]
    }
}
