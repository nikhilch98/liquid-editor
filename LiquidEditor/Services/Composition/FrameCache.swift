// FrameCache.swift
// LiquidEditor
//
// LRU Frame Cache with predictive prefetching for ultra-low latency scrubbing.
//
// Features:
// - LRU eviction with configurable capacity (120 normal / 60 warning / 20 critical)
// - Predictive prefetching based on scrub direction detection
// - Memory pressure handling (normal / warning / critical)
// - O(log n) nearest frame lookup via sorted per-asset time index
// - Batch prefetching with Task.sleep for UI yielding
// - Prefetch cancellation via Swift structured concurrency
// - Frame boundary rounding via Rational
// - Thread-safe via OSAllocatedUnfairLock

import Foundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "FrameCache")

// MARK: - CachedFrame

/// A single cached video frame with its pixel data and metadata.
struct CachedFrame: Sendable {
    /// Asset ID this frame belongs to.
    let assetId: String

    /// Timeline position in microseconds.
    let timeMicros: TimeMicros

    /// Raw BGRA pixel data.
    let pixels: Data

    /// Frame width in pixels.
    let width: Int

    /// Frame height in pixels.
    let height: Int

    /// Whether this is an exact frame or I-frame approximation.
    let isExact: Bool

    /// Timestamp when this frame was cached.
    let cachedAt: Date

    /// Memory size in bytes (pixel data length).
    var memorySizeBytes: Int { pixels.count }

    /// Memory size in megabytes.
    var memorySizeMB: Double { Double(memorySizeBytes) / (1024.0 * 1024.0) }

    /// Creates a cached frame with the current timestamp.
    init(
        assetId: String,
        timeMicros: TimeMicros,
        pixels: Data,
        width: Int,
        height: Int,
        isExact: Bool = true,
        cachedAt: Date = Date()
    ) {
        self.assetId = assetId
        self.timeMicros = timeMicros
        self.pixels = pixels
        self.width = width
        self.height = height
        self.isExact = isExact
        self.cachedAt = cachedAt
    }

    /// Creates a CachedFrame from a DecodedFrame, adding the asset ID.
    init(assetId: String, decodedFrame: DecodedFrame, cachedAt: Date = Date()) {
        self.assetId = assetId
        self.timeMicros = decodedFrame.timeMicros
        self.pixels = decodedFrame.pixels
        self.width = decodedFrame.width
        self.height = decodedFrame.height
        self.isExact = decodedFrame.isExact
        self.cachedAt = cachedAt
    }
}

// MARK: - MemoryPressureLevel

/// iOS memory pressure levels for adaptive cache sizing.
enum MemoryPressureLevel: Int, Sendable {
    /// Normal operation -- full cache capacity.
    case normal = 0
    /// Warning -- reduce to 60 frames.
    case warning = 1
    /// Critical -- aggressively reduce to 20 frames.
    case critical = 2
}

// MARK: - SortedTimeIndex

/// A sorted array of `TimeMicros` values for a single asset,
/// providing O(log n) nearest-frame lookup via binary search.
///
/// This replaces Dart's `SplayTreeMap<int, String>` with a simpler
/// structure that avoids external dependencies beyond swift-collections.
private struct SortedTimeIndex: Sendable {
    /// Sorted array of (timeMicros, cacheKey) pairs.
    /// Invariant: always sorted ascending by timeMicros.
    private var entries: [(time: TimeMicros, key: String)] = []

    /// Number of entries.
    var count: Int { entries.count }

    /// Whether the index is empty.
    var isEmpty: Bool { entries.isEmpty }

    /// Insert or update an entry. Maintains sorted order.
    mutating func insert(time: TimeMicros, key: String) {
        let idx = insertionIndex(for: time)
        if idx < entries.count && entries[idx].time == time {
            // Update existing entry at this time.
            entries[idx] = (time, key)
        } else {
            entries.insert((time, key), at: idx)
        }
    }

    /// Remove the entry at the given time. Returns true if removed.
    @discardableResult
    mutating func remove(time: TimeMicros) -> Bool {
        let idx = insertionIndex(for: time)
        if idx < entries.count && entries[idx].time == time {
            entries.remove(at: idx)
            return true
        }
        return false
    }

    /// Get the cache key for an exact time, or nil.
    func key(at time: TimeMicros) -> String? {
        let idx = insertionIndex(for: time)
        if idx < entries.count && entries[idx].time == time {
            return entries[idx].key
        }
        return nil
    }

    /// Find the nearest cache key to the given time.
    /// Returns nil if the index is empty.
    func nearestKey(to time: TimeMicros) -> String? {
        if entries.isEmpty { return nil }

        let idx = insertionIndex(for: time)

        // Exact match.
        if idx < entries.count && entries[idx].time == time {
            return entries[idx].key
        }

        // Candidates: the entry just before and at the insertion index.
        let beforeIdx = idx - 1
        let afterIdx = idx

        let hasBefore = beforeIdx >= 0
        let hasAfter = afterIdx < entries.count

        if hasBefore && hasAfter {
            let distBefore = abs(time - entries[beforeIdx].time)
            let distAfter = abs(entries[afterIdx].time - time)
            return distBefore <= distAfter
                ? entries[beforeIdx].key
                : entries[afterIdx].key
        } else if hasBefore {
            return entries[beforeIdx].key
        } else if hasAfter {
            return entries[afterIdx].key
        }
        return nil
    }

    /// Remove all entries.
    mutating func removeAll() {
        entries.removeAll()
    }

    // MARK: - Binary Search

    /// Returns the index where `time` would be inserted to maintain sort order.
    /// If `time` already exists, returns its index.
    private func insertionIndex(for time: TimeMicros) -> Int {
        var lo = 0
        var hi = entries.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if entries[mid].time < time {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}

// MARK: - FrameCache

/// LRU Frame Cache with predictive prefetching.
///
/// Caches decoded video frames for instant scrubbing response.
/// Automatically prefetches frames based on scrub direction.
///
/// Thread-safe: all mutable state is protected by `OSAllocatedUnfairLock`.
/// Conforms to `@unchecked Sendable` because the lock guarantees safe access.
final class FrameCache: @unchecked Sendable {

    // MARK: - Constants

    /// Default maximum number of frames to cache.
    static let defaultMaxFrames: Int = 120

    /// Maximum frames under normal conditions.
    static let normalMaxFrames: Int = 120

    /// Maximum frames under memory pressure warning.
    static let warningMaxFrames: Int = 60

    /// Maximum frames under critical memory pressure.
    static let criticalMaxFrames: Int = 20

    /// Default maximum memory usage in bytes (300 MB).
    static let defaultMaxMemoryBytes: Int = 300 * 1024 * 1024

    /// Maximum frames to prefetch in one batch before yielding to the UI thread.
    static let maxPrefetchBatchSize: Int = 10

    /// Delay between prefetch batches in nanoseconds (~16 ms, one frame at 60 fps).
    static let prefetchBatchDelayNs: UInt64 = 16_000_000

    /// Number of recent scrub positions to keep for direction detection.
    private static let positionHistorySize: Int = 5

    // MARK: - Protected State

    /// All mutable state that requires lock protection.
    private struct State: Sendable {
        /// Cached frames keyed by "$assetId:$roundedTimeMicros".
        var cache: [String: CachedFrame] = [:]

        /// LRU order tracking. Index 0 is least-recently-used.
        /// Uses an array for ordered iteration and a set for O(1) contains/remove.
        var lruKeys: [String] = []
        var lruSet: Set<String> = []

        /// Per-asset sorted time index for O(log n) nearest lookup.
        var assetTimeIndex: [String: SortedTimeIndex] = [:]

        /// Current memory usage in bytes.
        var memoryUsageBytes: Int = 0

        /// Current maximum frames (adjusted for memory pressure).
        var currentMaxFrames: Int = FrameCache.normalMaxFrames

        /// Recent scrub positions for direction detection.
        var recentPositions: [TimeMicros] = []

        /// Current prefetch target range.
        var prefetchStart: TimeMicros?
        var prefetchEnd: TimeMicros?

        /// Cache keys of frames that were successfully prefetched.
        /// Prevents redundant re-fetching of already-decoded frames.
        var successfullyPrefetched: Set<String> = []

        /// Frame rate for frame boundary calculations.
        var frameRate: Rational

        /// Frame duration in microseconds (derived from frame rate).
        var frameDurationMicros: Int64

        /// Prefetch statistics
        var prefetchFramesDecoded: Int = 0
        var prefetchFramesFailed: Int = 0
        var prefetchCacheHits: Int = 0
    }

    /// Lock-protected mutable state.
    private let state: OSAllocatedUnfairLock<State>

    /// Active prefetch task. Stored outside the lock to allow cancellation
    /// without deadlocking (Task.cancel() is safe to call from any context).
    private let prefetchTask: OSAllocatedUnfairLock<Task<Void, Never>?>

    // MARK: - Initialization

    /// Creates a frame cache.
    ///
    /// - Parameter frameRate: The frame rate used for frame boundary rounding.
    ///   Defaults to 30 fps. Can be updated later via `setFrameRate(_:)`.
    init(frameRate: Rational = .fps30) {
        let initialState = State(
            frameRate: frameRate,
            frameDurationMicros: frameRate.microsecondsPerFrame
        )
        self.state = OSAllocatedUnfairLock(initialState: initialState)
        self.prefetchTask = OSAllocatedUnfairLock(initialState: nil)
    }

    // MARK: - Frame Rate

    /// The current frame rate.
    var frameRate: Rational {
        state.withLock { $0.frameRate }
    }

    /// The current frame duration in microseconds.
    var frameDurationMicros: Int64 {
        state.withLock { $0.frameDurationMicros }
    }

    /// Updates the frame rate used for frame boundary calculations.
    ///
    /// Existing cached frames remain valid but may not align with
    /// the new frame boundaries. Call `clear()` to invalidate if needed.
    func setFrameRate(_ frameRate: Rational) {
        state.withLock {
            $0.frameRate = frameRate
            $0.frameDurationMicros = frameRate.microsecondsPerFrame
        }
    }

    // MARK: - Read-Only Properties

    /// Number of cached frames.
    var frameCount: Int {
        state.withLock { $0.cache.count }
    }

    /// Current memory usage in bytes.
    var memoryUsageBytes: Int {
        state.withLock { $0.memoryUsageBytes }
    }

    /// Current memory usage in megabytes.
    var memoryUsageMB: Double {
        Double(memoryUsageBytes) / (1024.0 * 1024.0)
    }

    /// Current maximum frames (may be reduced under memory pressure).
    var maxFrames: Int {
        state.withLock { $0.currentMaxFrames }
    }

    /// Whether the cache is empty.
    var isEmpty: Bool {
        state.withLock { $0.cache.isEmpty }
    }

    /// Whether the cache is at capacity.
    var isFull: Bool {
        state.withLock { $0.cache.count >= $0.currentMaxFrames }
    }

    /// Current scrub direction: -1 (left), 0 (stationary), 1 (right).
    var scrubDirection: Int {
        state.withLock { Self.computeScrubDirection($0.recentPositions) }
    }

    /// Compute direction from position history (pure function, called under lock).
    private static func computeScrubDirection(_ positions: [TimeMicros]) -> Int {
        guard positions.count >= 2 else { return 0 }

        var forward = 0
        var backward = 0

        for i in 1..<positions.count {
            if positions[i] > positions[i - 1] {
                forward += 1
            } else if positions[i] < positions[i - 1] {
                backward += 1
            }
        }

        if forward > backward { return 1 }
        if backward > forward { return -1 }
        return 0
    }

    // MARK: - Cache Key

    /// Generates a cache key by rounding the time to a frame boundary.
    private static func cacheKey(
        assetId: String,
        timeMicros: TimeMicros,
        frameDurationMicros: Int64
    ) -> String {
        let rounded = roundToFrameBoundary(timeMicros, frameDurationMicros: frameDurationMicros)
        return "\(assetId):\(rounded)"
    }

    /// Rounds a time to the nearest frame boundary to prevent cache fragmentation.
    private static func roundToFrameBoundary(
        _ timeMicros: TimeMicros,
        frameDurationMicros: Int64
    ) -> TimeMicros {
        (timeMicros / frameDurationMicros) * frameDurationMicros
    }

    // MARK: - Cache Access

    /// Gets the cached frame at an exact position for a specific asset.
    ///
    /// Returns `nil` if the frame is not cached.
    /// Touching the frame promotes it in the LRU order.
    func getFrame(assetId: String, timeMicros: TimeMicros) -> CachedFrame? {
        state.withLock { s in
            let key = Self.cacheKey(
                assetId: assetId,
                timeMicros: timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )
            guard let frame = s.cache[key] else { return nil }
            Self.touchLRU(key: key, state: &s)
            return frame
        }
    }

    /// Checks whether a frame is cached for a specific asset and time.
    func hasFrame(assetId: String, timeMicros: TimeMicros) -> Bool {
        state.withLock { s in
            let key = Self.cacheKey(
                assetId: assetId,
                timeMicros: timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )
            return s.cache[key] != nil
        }
    }

    /// Gets the nearest cached frame to a position for a specific asset.
    ///
    /// Uses the sorted per-asset time index for O(log n) lookup.
    /// Useful for showing an approximate frame while the exact frame decodes.
    func getNearestFrame(assetId: String, timeMicros: TimeMicros) -> CachedFrame? {
        state.withLock { s in
            guard !s.cache.isEmpty else { return nil }

            let key = Self.cacheKey(
                assetId: assetId,
                timeMicros: timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )

            // Exact match first (O(1)).
            if let frame = s.cache[key] {
                Self.touchLRU(key: key, state: &s)
                return frame
            }

            // O(log n) nearest lookup via sorted index.
            guard let index = s.assetTimeIndex[assetId], !index.isEmpty else { return nil }

            let targetTime = Self.roundToFrameBoundary(
                timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )

            if let nearestKey = index.nearestKey(to: targetTime),
               let frame = s.cache[nearestKey] {
                Self.touchLRU(key: nearestKey, state: &s)
                s.prefetchCacheHits += 1
                return frame
            }

            return nil
        }
    }

    /// Adds a frame to the cache, evicting LRU entries if necessary.
    func addFrame(_ frame: CachedFrame) {
        state.withLock { s in
            let key = Self.cacheKey(
                assetId: frame.assetId,
                timeMicros: frame.timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )
            let roundedTime = Self.roundToFrameBoundary(
                frame.timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )

            // Remove existing frame at this position.
            if let existing = s.cache.removeValue(forKey: key) {
                s.memoryUsageBytes -= existing.memorySizeBytes
                Self.removeLRU(key: key, state: &s)
                // SortedTimeIndex entry will be overwritten below.
            }

            // Evict LRU entries until there is room.
            while s.cache.count >= s.currentMaxFrames
                    || (s.memoryUsageBytes + frame.memorySizeBytes > Self.defaultMaxMemoryBytes
                        && !s.cache.isEmpty) {
                if !Self.evictLRU(state: &s) { break }
            }

            // Insert.
            s.cache[key] = frame
            Self.appendLRU(key: key, state: &s)
            s.memoryUsageBytes += frame.memorySizeBytes

            // Maintain sorted time index.
            s.assetTimeIndex[frame.assetId, default: SortedTimeIndex()]
                .insert(time: roundedTime, key: key)
        }
    }

    /// Removes a specific frame from the cache.
    func removeFrame(assetId: String, timeMicros: TimeMicros) {
        state.withLock { s in
            let key = Self.cacheKey(
                assetId: assetId,
                timeMicros: timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )
            guard let frame = s.cache.removeValue(forKey: key) else { return }

            s.memoryUsageBytes -= frame.memorySizeBytes
            Self.removeLRU(key: key, state: &s)

            let roundedTime = Self.roundToFrameBoundary(
                timeMicros,
                frameDurationMicros: s.frameDurationMicros
            )
            s.assetTimeIndex[assetId]?.remove(time: roundedTime)
            if s.assetTimeIndex[assetId]?.isEmpty == true {
                s.assetTimeIndex.removeValue(forKey: assetId)
            }

            s.successfullyPrefetched.remove(key)
        }
    }

    /// Removes all cached frames for a specific asset.
    func removeAssetFrames(assetId: String) {
        state.withLock { s in
            let prefix = "\(assetId):"
            let keysToRemove = s.cache.keys.filter { $0.hasPrefix(prefix) }
            for key in keysToRemove {
                if let frame = s.cache.removeValue(forKey: key) {
                    s.memoryUsageBytes -= frame.memorySizeBytes
                    Self.removeLRU(key: key, state: &s)
                    s.successfullyPrefetched.remove(key)
                }
            }
            s.assetTimeIndex.removeValue(forKey: assetId)
        }
    }

    // MARK: - LRU Management (static helpers operating on State)

    /// Promote a key to most-recently-used position.
    private static func touchLRU(key: String, state: inout State) {
        if state.lruSet.contains(key) {
            // Remove from current position (O(n) but acceptable for cache sizes <= 120).
            state.lruKeys.removeAll(where: { $0 == key })
        }
        state.lruKeys.append(key)
        state.lruSet.insert(key)
    }

    /// Append a new key as most-recently-used.
    private static func appendLRU(key: String, state: inout State) {
        state.lruKeys.append(key)
        state.lruSet.insert(key)
    }

    /// Remove a key from LRU tracking.
    private static func removeLRU(key: String, state: inout State) {
        state.lruSet.remove(key)
        state.lruKeys.removeAll(where: { $0 == key })
    }

    /// Evict the least recently used frame. Returns false if nothing to evict.
    @discardableResult
    private static func evictLRU(state: inout State) -> Bool {
        guard !state.lruKeys.isEmpty else { return false }

        let evictKey = state.lruKeys.removeFirst()
        state.lruSet.remove(evictKey)

        guard let evicted = state.cache.removeValue(forKey: evictKey) else { return true }

        state.memoryUsageBytes -= evicted.memorySizeBytes

        let roundedTime = roundToFrameBoundary(
            evicted.timeMicros,
            frameDurationMicros: state.frameDurationMicros
        )
        state.assetTimeIndex[evicted.assetId]?.remove(time: roundedTime)
        if state.assetTimeIndex[evicted.assetId]?.isEmpty == true {
            state.assetTimeIndex.removeValue(forKey: evicted.assetId)
        }

        state.successfullyPrefetched.remove(evictKey)
        return true
    }

    /// Evict frames until the count is at or below the target.
    private static func evictToTarget(_ targetFrames: Int, state: inout State) {
        while state.cache.count > targetFrames && !state.lruKeys.isEmpty {
            evictLRU(state: &state)
        }
    }

    // MARK: - Scrub Direction Detection

    /// Records a scrub position for direction detection.
    func recordScrubPosition(_ timeMicros: TimeMicros) {
        state.withLock { s in
            s.recentPositions.append(timeMicros)
            if s.recentPositions.count > Self.positionHistorySize {
                s.recentPositions.removeFirst()
            }
        }
    }

    /// Clears scrub direction history.
    func clearScrubHistory() {
        state.withLock { $0.recentPositions.removeAll() }
    }

    // MARK: - Prefetching

    /// Prefetches frames around a center position for a specific asset.
    ///
    /// Cancels any previously running prefetch. Frames are decoded in batches
    /// of `maxPrefetchBatchSize` with `prefetchBatchDelayNs` between batches
    /// to avoid starving the UI thread.
    ///
    /// Respects Swift structured concurrency cancellation: if the returned
    /// task is cancelled (or `cancelPrefetch()` is called), decoding stops
    /// at the next check point.
    ///
    /// - Parameters:
    ///   - assetId: Asset to prefetch frames for.
    ///   - centerMicros: Center position for the prefetch window.
    ///   - frameDurationMicros: Duration of one frame in microseconds.
    ///   - decodeFrame: Async closure that decodes a frame at the given time.
    ///     Returns `nil` if the frame could not be decoded.
    func prefetchAround(
        assetId: String,
        centerMicros: TimeMicros,
        frameDurationMicros: Int64,
        decodeFrame: @escaping @Sendable (TimeMicros) async -> CachedFrame?
    ) {
        // Cancel any in-flight prefetch.
        cancelPrefetch()

        // Snapshot the direction and build the frame list under the lock.
        let framesToPrefetch: [TimeMicros] = state.withLock { s in
            let direction = Self.computeScrubDirection(s.recentPositions)

            // Determine the asymmetric prefetch window.
            let behind: Int
            let ahead: Int
            switch direction {
            case 1:  // Scrubbing right -- more frames ahead.
                behind = 10; ahead = 50
            case -1: // Scrubbing left -- more frames behind.
                behind = 50; ahead = 10
            default: // Stationary -- balanced.
                behind = 30; ahead = 30
            }

            let startMicros = centerMicros - TimeMicros(behind) * frameDurationMicros
            let endMicros = centerMicros + TimeMicros(ahead) * frameDurationMicros

            s.prefetchStart = startMicros
            s.prefetchEnd = endMicros

            // Collect frames not already cached or successfully prefetched.
            var frames: [TimeMicros] = []
            var t = startMicros
            while t <= endMicros {
                defer { t += frameDurationMicros }
                if t < 0 { continue }

                let key = Self.cacheKey(
                    assetId: assetId,
                    timeMicros: t,
                    frameDurationMicros: s.frameDurationMicros
                )
                if s.cache[key] != nil { continue }
                if s.successfullyPrefetched.contains(key) { continue }

                frames.append(t)
            }

            // Sort by priority: favor the scrub direction, then by distance from center.
            switch direction {
            case 1:
                frames.sort { a, b in
                    let aAhead = a >= centerMicros
                    let bAhead = b >= centerMicros
                    if aAhead && !bAhead { return true }
                    if !aAhead && bAhead { return false }
                    return abs(a - centerMicros) < abs(b - centerMicros)
                }
            case -1:
                frames.sort { a, b in
                    let aBehind = a <= centerMicros
                    let bBehind = b <= centerMicros
                    if aBehind && !bBehind { return true }
                    if !aBehind && bBehind { return false }
                    return abs(a - centerMicros) < abs(b - centerMicros)
                }
            default:
                frames.sort { abs($0 - centerMicros) < abs($1 - centerMicros) }
            }

            return frames
        }

        // Launch the prefetch as an unstructured Task so it runs concurrently.
        let task = Task { [weak self] in
            guard let self else { return }
            var batchCount = 0
            var successCount = 0
            var failureCount = 0

            for t in framesToPrefetch {
                // Check cancellation.
                if Task.isCancelled { break }
                if self.isFull { break }

                do {
                    if let frame = await decodeFrame(t) {
                        if Task.isCancelled { break }
                        self.addFrame(frame)
                        successCount += 1

                        // Track successful prefetch.
                        self.state.withLock { s in
                            let key = Self.cacheKey(
                                assetId: assetId,
                                timeMicros: t,
                                frameDurationMicros: s.frameDurationMicros
                            )
                            s.successfullyPrefetched.insert(key)
                            s.prefetchFramesDecoded += 1
                        }
                    } else {
                        failureCount += 1
                        self.state.withLock { s in
                            s.prefetchFramesFailed += 1
                        }
                    }
                } catch {
                    // Ignore decode errors; the frame will be retried on the
                    // next prefetch since it is not in successfullyPrefetched.
                    failureCount += 1
                    self.state.withLock { s in
                        s.prefetchFramesFailed += 1
                    }
                }

                // Yield to the UI after each batch.
                batchCount += 1
                if batchCount >= Self.maxPrefetchBatchSize {
                    batchCount = 0
                    try? await Task.sleep(nanoseconds: Self.prefetchBatchDelayNs)
                    if Task.isCancelled { break }
                }
            }

            if successCount > 0 || failureCount > 0 {
                logger.debug("Prefetch completed: \(successCount) decoded, \(failureCount) failed")
            }
        }

        prefetchTask.withLock { $0 = task }
    }

    /// Cancels any active prefetch operation.
    func cancelPrefetch() {
        prefetchTask.withLock { task in
            task?.cancel()
            task = nil
        }
    }

    // MARK: - Memory Pressure

    /// Handles an iOS memory pressure notification by adjusting
    /// the maximum cache size and evicting excess frames.
    func handleMemoryPressure(_ level: MemoryPressureLevel) {
        state.withLock { s in
            switch level {
            case .normal:
                s.currentMaxFrames = Self.normalMaxFrames
            case .warning:
                s.currentMaxFrames = Self.warningMaxFrames
                let beforeCount = s.cache.count
                let beforeBytes = s.memoryUsageBytes
                Self.evictToTarget(Self.warningMaxFrames, state: &s)
                let remaining = s.cache.count
                let evicted = beforeCount - remaining
                let freedBytes = beforeBytes - s.memoryUsageBytes
                logger.warning("Memory pressure (warning): evicted \(evicted) frames, \(remaining) remaining, freed \(freedBytes) bytes")
            case .critical:
                s.currentMaxFrames = Self.criticalMaxFrames
                let beforeCount = s.cache.count
                let beforeBytes = s.memoryUsageBytes
                Self.evictToTarget(Self.criticalMaxFrames, state: &s)
                let remaining = s.cache.count
                let evicted = beforeCount - remaining
                let freedBytes = beforeBytes - s.memoryUsageBytes
                logger.warning("Memory pressure (critical): evicted \(evicted) frames, \(remaining) remaining, freed \(freedBytes) bytes")
            }
        }
    }

    // MARK: - Lifecycle

    /// Clears all cached frames and resets internal state.
    func clear() {
        cancelPrefetch()
        state.withLock { s in
            s.cache.removeAll()
            s.lruKeys.removeAll()
            s.lruSet.removeAll()
            s.assetTimeIndex.removeAll()
            s.successfullyPrefetched.removeAll()
            s.memoryUsageBytes = 0
            s.recentPositions.removeAll()
            s.prefetchStart = nil
            s.prefetchEnd = nil
            s.prefetchFramesDecoded = 0
            s.prefetchFramesFailed = 0
            s.prefetchCacheHits = 0
        }
    }

    /// Disposes of the cache, cancelling any prefetch and releasing all frames.
    func dispose() {
        clear()
    }

    // MARK: - Statistics

    /// Cache statistics for debugging and monitoring.
    var statistics: [String: String] {
        state.withLock { s in
            [
                "frameCount": "\(s.cache.count)",
                "memoryUsageMB": String(format: "%.2f", Double(s.memoryUsageBytes) / (1024.0 * 1024.0)),
                "maxFrames": "\(s.currentMaxFrames)",
                "scrubDirection": "\(Self.computeScrubDirection(s.recentPositions))",
                "lruOrderLength": "\(s.lruKeys.count)",
                "prefetchStart": s.prefetchStart.map { "\($0)" } ?? "nil",
                "prefetchEnd": s.prefetchEnd.map { "\($0)" } ?? "nil",
                "successfullyPrefetchedCount": "\(s.successfullyPrefetched.count)",
                "assetIndexCount": "\(s.assetTimeIndex.count)",
                "prefetchFramesDecoded": "\(s.prefetchFramesDecoded)",
                "prefetchFramesFailed": "\(s.prefetchFramesFailed)",
                "prefetchCacheHits": "\(s.prefetchCacheHits)",
            ]
        }
    }
}
