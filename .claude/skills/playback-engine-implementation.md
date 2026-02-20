---
name: playback-engine-implementation
description: Use when implementing video playback, composition management, scrubbing, frame caching, or decoder pool functionality
---

## Playback Engine Implementation Guide

This skill guides implementation of the Timeline Architecture V2's playback system in pure Swift.

### Reference Document

**Primary Design Doc:** `docs/plans/2026-01-30-timeline-architecture-v2-design.md`

Read Sections 9 (Playback Engine), 10 (Frame Cache System), and 18 (Edge Cases) before implementation.

### Architecture Overview

```
PlaybackEngine (actor — central orchestrator)
├── CompositionManager (final class, @unchecked Sendable + OSAllocatedUnfairLock)
│   ├── CompositionBuilder (builds AVMutableComposition from segments)
│   ├── AVPlayer + AVPlayerLayer (main-thread-bound playback)
│   └── Double-buffered active/pending composition slots
├── NativeDecoderPool (final class, @unchecked Sendable + OSAllocatedUnfairLock)
│   └── Per-asset AVAssetImageGenerator instances with LRU eviction
├── FrameCache (final class, @unchecked Sendable + OSAllocatedUnfairLock)
│   └── LRU cache with predictive prefetch + sorted per-asset time index
└── ScrubController (coordinates scrub gestures with cache + decoders)
```

### File Locations

| Component | Location |
|-----------|----------|
| PlaybackEngine | `LiquidEditor/Services/Composition/PlaybackEngine.swift` |
| CompositionManager | `LiquidEditor/Services/Composition/CompositionManager.swift` |
| CompositionBuilder | `LiquidEditor/Services/Composition/CompositionBuilder.swift` |
| NativeDecoderPool | `LiquidEditor/Services/Composition/NativeDecoderPool.swift` |
| FrameCache | `LiquidEditor/Services/Composition/FrameCache.swift` |
| ScrubController | `LiquidEditor/Services/Composition/ScrubController.swift` |
| CompositionHandle | `LiquidEditor/Services/Protocols/CompositionServiceProtocol.swift` |
| CompositionSegment | `LiquidEditor/Services/Protocols/CompositionServiceProtocol.swift` |
| PlaybackState | `LiquidEditor/Services/Protocols/CompositionServiceProtocol.swift` |
| **Tests:** | |
| FrameCacheTests | `LiquidEditorTests/Services/Composition/FrameCacheTests.swift` |

### Thread Safety Patterns

Each component uses the appropriate Swift concurrency pattern:

| Component | Isolation | Why |
|-----------|-----------|-----|
| `PlaybackEngine` | `actor` | Central orchestrator; I/O-bound async operations |
| `CompositionManager` | `final class: @unchecked Sendable` + `OSAllocatedUnfairLock` | AVPlayer is main-thread-bound; lock protects state accessed from multiple threads |
| `FrameCache` | `final class: @unchecked Sendable` + `OSAllocatedUnfairLock` | GPU hot-path; lock avoids actor hop overhead during scrubbing |
| `NativeDecoderPool` | `final class: @unchecked Sendable` + `OSAllocatedUnfairLock` | High-frequency decoder access during scrubbing |
| `ScrubController` | Non-isolated; delegates to cache + pool | Coordinates between engine and cache |

### Implementation Priorities

From the architecture review (Section 18.6):

1. **Critical:** Memory pressure handling, offline media UX
2. **High:** Audio-safe hot-swap, export validation
3. **Medium:** Decoder thrashing prevention, progress UI

### Key Patterns

#### PlaybackEngine State Machine

```swift
enum PlaybackEngineState: String, Sendable {
    case uninitialized  // No timeline loaded
    case stopped        // Ready, playhead at 0
    case playing        // Active playback
    case paused         // Playback paused
    case scrubbing      // User dragging playhead
    case seeking        // Programmatic seek in progress
    case rebuilding     // Composition rebuild/hot-swap cycle
    case error          // Error occurred
}
```

State transitions are guarded in each method:

```swift
actor PlaybackEngine {
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
}
```

#### Double-Buffer Hot-Swap (CompositionManager)

The CompositionManager maintains two composition slots (active + pending) and swaps atomically:

```swift
final class CompositionManager: @unchecked Sendable {
    private var activeComposition: BuiltComposition?
    private var pendingComposition: BuiltComposition?
    private var _player: AVPlayer?
    private let stateLock = OSAllocatedUnfairLock()

    func buildComposition(segments: [CompositionSegment]) async throws -> CompositionHandle {
        // Build on background thread
        let built = try await builder.build(segments: segments, compositionId: id)

        // Store as pending (lock-protected)
        stateLock.withLock { pendingComposition = built }

        return CompositionHandle(
            id: built.id,
            composition: built.composition,
            videoComposition: built.videoComposition,
            audioMix: built.audioMix,
            duration: built.totalDurationMicros
        )
    }

    func hotSwap(_ handle: CompositionHandle, seekTo time: TimeMicros) async throws {
        // Validate pending matches handle (under lock)
        let (pending, wasPlaying, rate) = try stateLock.withLock { ... }

        // Create new player item on main actor
        let newItem = await MainActor.run { AVPlayerItem(asset: pending.composition) }

        // Swap on main thread for UI safety
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
}
```

**Critical:** AVPlayer operations MUST be on the main thread. Use `await MainActor.run { }` for all player interactions.

#### FrameCache with LRU + Predictive Prefetch

```swift
final class FrameCache: @unchecked Sendable {
    // Protected by OSAllocatedUnfairLock for GPU hot-path performance
    private let state: OSAllocatedUnfairLock<State>

    // Active prefetch task (stored outside lock for safe cancellation)
    private let prefetchTask: OSAllocatedUnfairLock<Task<Void, Never>?>

    // Memory pressure tiers:
    // Normal:   120 frames max, 300MB max
    // Warning:   60 frames max
    // Critical:  20 frames max

    func getFrame(assetId: String, timeMicros: TimeMicros) -> CachedFrame? {
        state.withLock { s in
            let key = Self.cacheKey(assetId: assetId, timeMicros: timeMicros,
                                     frameDurationMicros: s.frameDurationMicros)
            guard let frame = s.cache[key] else { return nil }
            Self.touchLRU(key: key, state: &s)  // Promote in LRU
            return frame
        }
    }

    func addFrame(_ frame: CachedFrame) {
        state.withLock { s in
            // Evict LRU entries until there is room
            while s.cache.count >= s.currentMaxFrames || overMemoryBudget {
                if !Self.evictLRU(state: &s) { break }
            }
            // Insert frame + update LRU + update sorted time index
            s.cache[key] = frame
            Self.appendLRU(key: key, state: &s)
            s.assetTimeIndex[frame.assetId, default: SortedTimeIndex()]
                .insert(time: roundedTime, key: key)
        }
    }
}
```

#### Frame Cache Key Generation

Frames are keyed by `"$assetId:$roundedTimeMicros"` where time is rounded to the nearest frame boundary:

```swift
private static func cacheKey(
    assetId: String,
    timeMicros: TimeMicros,
    frameDurationMicros: Int64
) -> String {
    let rounded = (timeMicros / frameDurationMicros) * frameDurationMicros
    return "\(assetId):\(rounded)"
}
```

#### Predictive Prefetching

Prefetch direction is detected from recent scrub positions:

```swift
func prefetchAround(
    assetId: String,
    centerMicros: TimeMicros,
    frameDurationMicros: Int64,
    decodeFrame: @escaping @Sendable (TimeMicros) async -> CachedFrame?
) {
    cancelPrefetch()

    // Snapshot direction + build prioritized frame list under lock
    let framesToPrefetch: [TimeMicros] = state.withLock { s in
        let direction = Self.computeScrubDirection(s.recentPositions)

        // Asymmetric window based on direction:
        // Scrubbing right:  10 behind, 50 ahead
        // Scrubbing left:   50 behind, 10 ahead
        // Stationary:       30 behind, 30 ahead

        // ... collect uncached frames, sort by priority ...
    }

    // Launch unstructured Task for background prefetching
    let task = Task { [weak self] in
        for t in framesToPrefetch {
            if Task.isCancelled { break }
            if let frame = await decodeFrame(t) {
                self?.addFrame(frame)
            }
            // Yield to UI every maxPrefetchBatchSize frames
        }
    }

    prefetchTask.withLock { $0 = task }
}
```

#### Nearest Frame Lookup (O(log n))

```swift
// Each asset has a SortedTimeIndex (sorted array with binary search):
func getNearestFrame(assetId: String, timeMicros: TimeMicros) -> CachedFrame? {
    state.withLock { s in
        // Try exact match first (O(1))
        if let frame = s.cache[key] { return frame }

        // O(log n) nearest via sorted per-asset index
        if let nearestKey = s.assetTimeIndex[assetId]?.nearestKey(to: targetTime),
           let frame = s.cache[nearestKey] {
            return frame
        }
        return nil
    }
}
```

#### Memory Pressure Handling (CRITICAL)

The FrameCache responds to iOS memory pressure notifications by reducing capacity:

```swift
func handleMemoryPressure(_ level: MemoryPressureLevel) {
    state.withLock { s in
        switch level {
        case .normal:
            s.currentMaxFrames = Self.normalMaxFrames  // 120
        case .warning:
            s.currentMaxFrames = Self.warningMaxFrames  // 60
            Self.evictToTarget(Self.warningMaxFrames, state: &s)
        case .critical:
            s.currentMaxFrames = Self.criticalMaxFrames  // 20
            Self.evictToTarget(Self.criticalMaxFrames, state: &s)
        }
    }
}
```

The PlaybackEngine forwards system memory warnings to both cache and decoder pool:

```swift
func handleMemoryPressure(_ level: Int) {
    frameCache.handleMemoryPressure(MemoryPressureLevel(rawValue: level) ?? .normal)
    decoderPool.handleMemoryPressure(level: level)
}
```

#### Playhead Polling (~30 FPS)

```swift
private func startPlayheadPolling() {
    stopPlayheadPolling()
    playheadPollingTask = Task { [weak self] in
        let pollInterval: UInt64 = 33_000_000  // 33ms ~ 30 FPS
        while !Task.isCancelled {
            guard let self else { return }
            await self.updatePlayhead()
            try? await Task.sleep(nanoseconds: pollInterval)
        }
    }
}
```

#### AsyncStream Event Broadcasting

The PlaybackEngine uses dual broadcast mechanisms (callbacks + AsyncStream):

```swift
actor PlaybackEngine {
    // Callbacks for simple observation
    var onPlaybackEvent: ((PlaybackEvent) -> Void)?
    var onPlayheadChange: ((TimeMicros) -> Void)?

    // AsyncStreams for structured concurrency consumers
    nonisolated let eventStream: AsyncStream<PlaybackEvent>
    nonisolated let playheadStream: AsyncStream<TimeMicros>

    private func emitEvent(_ event: PlaybackEvent) {
        onPlaybackEvent?(event)
        eventContinuation?.yield(event)
    }
}
```

### Scrubbing Flow

```
1. User starts drag      -> engine.beginScrub()
                             - stopPlayheadPolling()
                             - setState(.scrubbing)
                             - scrubController.beginScrub()

2. User drags             -> engine.scrubTo(timeMicros)
                             - clamp time
                             - scrubController.scrubTo(clamped)
                               -> check cache -> decode if miss -> return frame
                             - emit playhead update

3. User releases          -> engine.endScrub()
                             - scrubController.endScrub()
                             - compositionManager.seek(to: playheadMicros)
                             - setState(.paused)
```

### Composition Rebuild Flow

```
1. Timeline edited        -> engine.rebuildComposition(segments:)
                             - Save previous state
                             - setState(.rebuilding)
                             - emitEvent(.rebuildStarted)

2. Build in background    -> compositionManager.buildComposition(segments:)
                             - CompositionBuilder creates AVMutableComposition
                             - Store as pending composition

3. Hot-swap               -> compositionManager.hotSwap(handle, seekTo:)
                             - Create AVPlayerItem on main actor
                             - Replace current item atomically
                             - Remove old time observer, add new one
                             - Seek to playhead position
                             - Resume if was playing

4. Complete               -> emitEvent(.rebuildCompleted)
                             - Restore previous state (playing or paused)
```

### Performance Targets

| Operation | Target | Measurement |
|-----------|--------|-------------|
| Scrub (cached) | < 2ms | Frame timing |
| Scrub (uncached) | < 50ms | Frame timing |
| Hot-swap | < 5ms | Native profiler |
| Composition rebuild | < 20ms | Native profiler |
| Frame cache lookup | O(1) exact, O(log n) nearest | |
| Prefetch batch yield | ~16ms between batches | One frame at 60fps |

### Testing Strategy

1. **Unit Tests:** Cache eviction, LRU ordering, direction detection, nearest frame lookup
2. **Integration Tests:** Edit during playback, multi-source transitions, hot-swap during playback
3. **Memory Tests:** Simulate memory warnings at all levels, verify eviction targets
4. **Performance Tests:** Benchmark scrubbing latency at various cache states

```swift
import Testing

@Suite("FrameCache")
struct FrameCacheTests {

    @Test("LRU eviction removes least recently used frame")
    func lruEviction() {
        let cache = FrameCache(frameRate: .fps30)

        // Fill cache to capacity
        for i in 0..<FrameCache.normalMaxFrames {
            let frame = CachedFrame(
                assetId: "asset1",
                timeMicros: TimeMicros(i) * 33_333,
                pixels: Data(repeating: 0, count: 100),
                width: 10, height: 10
            )
            cache.addFrame(frame)
        }

        #expect(cache.frameCount == FrameCache.normalMaxFrames)

        // Add one more -> should evict the oldest
        let newFrame = CachedFrame(
            assetId: "asset1",
            timeMicros: TimeMicros(FrameCache.normalMaxFrames) * 33_333,
            pixels: Data(repeating: 0, count: 100),
            width: 10, height: 10
        )
        cache.addFrame(newFrame)

        #expect(cache.frameCount == FrameCache.normalMaxFrames)
        // First frame should have been evicted
        #expect(!cache.hasFrame(assetId: "asset1", timeMicros: 0))
    }

    @Test("Memory pressure reduces capacity")
    func memoryPressure() {
        let cache = FrameCache(frameRate: .fps30)

        // Fill with 100 frames
        for i in 0..<100 {
            let frame = CachedFrame(
                assetId: "asset1",
                timeMicros: TimeMicros(i) * 33_333,
                pixels: Data(repeating: 0, count: 100),
                width: 10, height: 10
            )
            cache.addFrame(frame)
        }

        cache.handleMemoryPressure(.warning)
        #expect(cache.frameCount <= FrameCache.warningMaxFrames)

        cache.handleMemoryPressure(.critical)
        #expect(cache.frameCount <= FrameCache.criticalMaxFrames)
    }
}
```

### Common Mistakes

1. **Blocking main thread:** All decoding/composition building must be on background threads. Use `async` methods and `Task { }`.
2. **Memory leaks:** Dispose all resources via `PlaybackEngine.dispose()` which cascades to all dependencies. Use `[weak self]` in Task closures.
3. **Race conditions:** Use `OSAllocatedUnfairLock` for hot-path state (FrameCache, NativeDecoderPool, CompositionManager). Use `actor` for I/O-bound orchestration (PlaybackEngine).
4. **Audio glitches:** Align hot-swap to audio sample boundaries. Use `toleranceBefore: .zero, toleranceAfter: .zero` on seek operations.
5. **Ignoring memory warnings:** App WILL be killed without proper handling. Always forward `handleMemoryPressure` to both cache and decoder pool.
6. **AVPlayer off main thread:** All AVPlayer mutations (`replaceCurrentItem`, `seek`, `rate`, `pause`) must be dispatched via `await MainActor.run { }`.
7. **Forgetting to cancel prefetch:** Always call `cancelPrefetch()` before starting a new prefetch to prevent stale Task accumulation.
8. **Lock contention:** Keep lock-protected sections minimal. Extract computation outside the lock where possible.
9. **AsyncStream continuation leak:** Always call `continuation.finish()` in `dispose()` to prevent consumer tasks from hanging.

### Edge Cases from Review

See Section 18 of design doc for detailed handling of:
- EC-2: Memory pressure during frame caching
- EC-4: Decoder pool exhaustion
- EC-5: AVComposition hot-swap audio glitches
- RC-2: Frame cache prefetch direction change
- RC-3: Decoder pool race conditions

### Verification Commands

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
    -destination 'generic/platform=iOS' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme LiquidEditor \
    -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```
