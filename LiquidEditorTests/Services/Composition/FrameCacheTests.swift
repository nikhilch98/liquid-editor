import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Creates a CachedFrame with minimal boilerplate for testing.
/// Generates deterministic pixel data based on assetId and timeMicros.
private func makeFrame(
    assetId: String = "asset1",
    timeMicros: TimeMicros = 0,
    width: Int = 1920,
    height: Int = 1080,
    bytesPerPixel: Int = 4,
    isExact: Bool = true,
    cachedAt: Date = Date()
) -> CachedFrame {
    // Create pixel data of the expected size (width * height * 4 bytes for BGRA).
    let dataSize = width * height * bytesPerPixel
    let pixels = Data(repeating: UInt8(timeMicros % 256), count: dataSize)
    return CachedFrame(
        assetId: assetId,
        timeMicros: timeMicros,
        pixels: pixels,
        width: width,
        height: height,
        isExact: isExact,
        cachedAt: cachedAt
    )
}

/// Creates a small CachedFrame (1x1) for tests that need many frames without huge memory.
private func makeSmallFrame(
    assetId: String = "asset1",
    timeMicros: TimeMicros = 0,
    isExact: Bool = true
) -> CachedFrame {
    makeFrame(
        assetId: assetId,
        timeMicros: timeMicros,
        width: 1,
        height: 1,
        isExact: isExact
    )
}

/// Frame duration in microseconds for 30fps.
private let fps30FrameDuration: TimeMicros = Rational.fps30.microsecondsPerFrame // 33333

// MARK: - FrameCache Tests

@Suite("FrameCache Tests")
struct FrameCacheTests {

    // MARK: - 1. Initialization

    @Suite("Initialization")
    struct InitTests {

        @Test("Creates with default fps30 frame rate")
        func defaultFrameRate() {
            let cache = FrameCache()
            #expect(cache.frameRate == .fps30)
            #expect(cache.frameDurationMicros == Rational.fps30.microsecondsPerFrame)
        }

        @Test("Creates with custom frame rate")
        func customFrameRate() {
            let cache = FrameCache(frameRate: .fps60)
            #expect(cache.frameRate == .fps60)
            #expect(cache.frameDurationMicros == Rational.fps60.microsecondsPerFrame)
        }

        @Test("Initial statistics are zeroed")
        func initialStatistics() {
            let cache = FrameCache()
            #expect(cache.frameCount == 0)
            #expect(cache.memoryUsageBytes == 0)
            #expect(cache.isEmpty == true)
            #expect(cache.isFull == false)
            #expect(cache.maxFrames == FrameCache.normalMaxFrames)
            #expect(cache.scrubDirection == 0)
        }

        @Test("Initial maxFrames matches normalMaxFrames constant")
        func initialMaxFrames() {
            let cache = FrameCache()
            #expect(cache.maxFrames == 120)
            #expect(cache.maxFrames == FrameCache.normalMaxFrames)
        }
    }

    // MARK: - 2. Put and Get

    @Suite("Put and Get")
    struct PutGetTests {

        @Test("Put a frame and get it back by assetId and timeMicros")
        func putAndGet() {
            let cache = FrameCache()
            let frame = makeSmallFrame(assetId: "video1", timeMicros: 0)
            cache.addFrame(frame)

            let retrieved = cache.getFrame(assetId: "video1", timeMicros: 0)
            #expect(retrieved != nil)
            #expect(retrieved?.assetId == "video1")
            #expect(retrieved?.width == 1)
            #expect(retrieved?.height == 1)
            #expect(retrieved?.isExact == true)
        }

        @Test("Get returns nil for non-existent frame")
        func getMissing() {
            let cache = FrameCache()
            let result = cache.getFrame(assetId: "nonexistent", timeMicros: 0)
            #expect(result == nil)
        }

        @Test("hasFrame returns true for cached frame")
        func hasFrameTrue() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(assetId: "a", timeMicros: 0))
            #expect(cache.hasFrame(assetId: "a", timeMicros: 0) == true)
        }

        @Test("hasFrame returns false for uncached frame")
        func hasFrameFalse() {
            let cache = FrameCache()
            #expect(cache.hasFrame(assetId: "a", timeMicros: 0) == false)
        }

        @Test("FrameCount increments on addFrame")
        func frameCountIncrements() {
            let cache = FrameCache()
            #expect(cache.frameCount == 0)
            cache.addFrame(makeSmallFrame(timeMicros: 0))
            #expect(cache.frameCount == 1)
            cache.addFrame(makeSmallFrame(timeMicros: fps30FrameDuration))
            #expect(cache.frameCount == 2)
        }

        @Test("Memory usage increases with added frames")
        func memoryUsageTracking() {
            let cache = FrameCache()
            let frame = makeSmallFrame(timeMicros: 0)
            cache.addFrame(frame)
            #expect(cache.memoryUsageBytes == frame.memorySizeBytes)
        }

        @Test("Adding frame at same position replaces existing")
        func replaceExisting() {
            let cache = FrameCache()
            let frame1 = makeSmallFrame(assetId: "v1", timeMicros: 0)
            cache.addFrame(frame1)
            #expect(cache.frameCount == 1)

            // Add another frame at the same rounded position.
            let frame2 = CachedFrame(
                assetId: "v1",
                timeMicros: 0,
                pixels: Data(repeating: 0xFF, count: 8),
                width: 2,
                height: 1,
                isExact: true
            )
            cache.addFrame(frame2)
            #expect(cache.frameCount == 1)

            let retrieved = cache.getFrame(assetId: "v1", timeMicros: 0)
            #expect(retrieved?.width == 2)
            #expect(retrieved?.pixels.count == 8)
        }

        @Test("Different assets with same timeMicros are stored separately")
        func differentAssets() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(assetId: "a", timeMicros: 0))
            cache.addFrame(makeSmallFrame(assetId: "b", timeMicros: 0))
            #expect(cache.frameCount == 2)

            #expect(cache.getFrame(assetId: "a", timeMicros: 0) != nil)
            #expect(cache.getFrame(assetId: "b", timeMicros: 0) != nil)
        }

        @Test("removeFrame removes specific frame")
        func removeFrame() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(assetId: "v1", timeMicros: 0))
            cache.addFrame(makeSmallFrame(assetId: "v1", timeMicros: fps30FrameDuration))
            #expect(cache.frameCount == 2)

            cache.removeFrame(assetId: "v1", timeMicros: 0)
            #expect(cache.frameCount == 1)
            #expect(cache.getFrame(assetId: "v1", timeMicros: 0) == nil)
            #expect(cache.getFrame(assetId: "v1", timeMicros: fps30FrameDuration) != nil)
        }

        @Test("removeAssetFrames removes all frames for an asset")
        func removeAssetFrames() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(assetId: "v1", timeMicros: 0))
            cache.addFrame(makeSmallFrame(assetId: "v1", timeMicros: fps30FrameDuration))
            cache.addFrame(makeSmallFrame(assetId: "v2", timeMicros: 0))
            #expect(cache.frameCount == 3)

            cache.removeAssetFrames(assetId: "v1")
            #expect(cache.frameCount == 1)
            #expect(cache.getFrame(assetId: "v1", timeMicros: 0) == nil)
            #expect(cache.getFrame(assetId: "v2", timeMicros: 0) != nil)
        }
    }

    // MARK: - 3. Frame Rounding

    @Suite("Frame Rounding")
    struct FrameRoundingTests {

        @Test("Frames are rounded to frame boundaries at 30fps")
        func roundToFrameBoundary30fps() {
            let cache = FrameCache(frameRate: .fps30)
            // fps30 frame duration is 33333 microseconds.
            // A time of 40000us should round to frame 1 = 33333us.
            let frame = makeSmallFrame(assetId: "v1", timeMicros: 40000)
            cache.addFrame(frame)

            // Querying at the original time should find it (because it rounds to same boundary).
            #expect(cache.getFrame(assetId: "v1", timeMicros: 40000) != nil)

            // Querying at the exact frame boundary should also find it.
            #expect(cache.getFrame(assetId: "v1", timeMicros: 33333) != nil)

            // Querying at a different frame boundary should not find it.
            #expect(cache.getFrame(assetId: "v1", timeMicros: 0) == nil)
        }

        @Test("Two times in the same frame map to the same cache entry")
        func sameFrameMapping() {
            let cache = FrameCache(frameRate: .fps30)
            // Both 35000 and 40000 round to frame 1 (33333us).
            cache.addFrame(makeSmallFrame(assetId: "v1", timeMicros: 35000))
            #expect(cache.getFrame(assetId: "v1", timeMicros: 40000) != nil)
            #expect(cache.frameCount == 1)
        }

        @Test("Frame rounding at 60fps uses correct duration")
        func roundToFrameBoundary60fps() {
            let cache = FrameCache(frameRate: .fps60)
            // fps60 frame duration = 16666us.
            // 20000us / 16666 = 1 -> 1 * 16666 = 16666.
            let frame = makeSmallFrame(assetId: "v1", timeMicros: 20000)
            cache.addFrame(frame)

            #expect(cache.getFrame(assetId: "v1", timeMicros: 16666) != nil)
            #expect(cache.getFrame(assetId: "v1", timeMicros: 0) == nil)
        }

        @Test("Frame at time 0 maps to frame boundary 0")
        func zeroTimeBoundary() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(timeMicros: 0))
            #expect(cache.getFrame(assetId: "asset1", timeMicros: 0) != nil)
            // Any time in the first frame window should map to 0.
            #expect(cache.getFrame(assetId: "asset1", timeMicros: 10000) != nil)
        }
    }

    // MARK: - 4. LRU Eviction

    @Suite("LRU Eviction")
    struct LRUEvictionTests {

        @Test("Evicts oldest frames when exceeding maxFrames")
        func evictsOldest() {
            let cache = FrameCache()
            // Under .critical pressure, maxFrames = 20.
            cache.handleMemoryPressure(.critical)
            #expect(cache.maxFrames == 20)

            // Add 20 frames (fills capacity).
            for i in 0..<20 {
                let t = TimeMicros(i) * fps30FrameDuration
                cache.addFrame(makeSmallFrame(timeMicros: t))
            }
            #expect(cache.frameCount == 20)

            // Adding one more should evict the LRU (frame at time 0).
            let overflowTime = TimeMicros(20) * fps30FrameDuration
            cache.addFrame(makeSmallFrame(timeMicros: overflowTime))
            #expect(cache.frameCount == 20)

            // Frame 0 should be evicted (it was LRU).
            #expect(cache.getFrame(assetId: "asset1", timeMicros: 0) == nil)
            // The newly added frame should exist.
            #expect(cache.getFrame(assetId: "asset1", timeMicros: overflowTime) != nil)
        }

        @Test("Accessing a frame promotes it in LRU order")
        func accessPromotesLRU() {
            let cache = FrameCache()
            cache.handleMemoryPressure(.critical)
            #expect(cache.maxFrames == 20)

            // Add 20 frames.
            for i in 0..<20 {
                let t = TimeMicros(i) * fps30FrameDuration
                cache.addFrame(makeSmallFrame(timeMicros: t))
            }

            // Access frame 0 to promote it (it was the oldest/LRU).
            _ = cache.getFrame(assetId: "asset1", timeMicros: 0)

            // Add a new frame to trigger eviction.
            let overflowTime = TimeMicros(20) * fps30FrameDuration
            cache.addFrame(makeSmallFrame(timeMicros: overflowTime))

            // Frame 0 should survive because it was promoted.
            #expect(cache.getFrame(assetId: "asset1", timeMicros: 0) != nil)
            // Frame 1 (was second oldest, now LRU) should be evicted.
            #expect(cache.getFrame(assetId: "asset1", timeMicros: fps30FrameDuration) == nil)
        }

        @Test("isFull returns true at capacity")
        func isFullAtCapacity() {
            let cache = FrameCache()
            cache.handleMemoryPressure(.critical)

            for i in 0..<20 {
                let t = TimeMicros(i) * fps30FrameDuration
                cache.addFrame(makeSmallFrame(timeMicros: t))
            }
            #expect(cache.isFull == true)
        }
    }

    // MARK: - 5. Memory Limit

    @Suite("Memory Limit")
    struct MemoryLimitTests {

        @Test("Large frames trigger eviction when exceeding memory budget")
        func largeFramesEviction() {
            let cache = FrameCache()
            // Create frames that are large enough to exceed 300MB budget.
            // Each 1920x1080 BGRA frame = ~8.3MB.
            // 300MB / 8.3MB ~ 36 frames before memory limit.
            let largeFrameCount = 40
            for i in 0..<largeFrameCount {
                let t = TimeMicros(i) * fps30FrameDuration
                let frame = makeFrame(
                    assetId: "asset1",
                    timeMicros: t,
                    width: 1920,
                    height: 1080
                )
                cache.addFrame(frame)
            }

            // Should be fewer than 40 due to memory eviction.
            #expect(cache.frameCount < largeFrameCount)
            // Memory should be within budget.
            #expect(cache.memoryUsageBytes <= FrameCache.defaultMaxMemoryBytes)
        }

        @Test("Memory usage decreases after removeFrame")
        func memoryDecreasesOnRemove() {
            let cache = FrameCache()
            let frame = makeSmallFrame(timeMicros: 0)
            cache.addFrame(frame)
            let usageAfterAdd = cache.memoryUsageBytes
            #expect(usageAfterAdd > 0)

            cache.removeFrame(assetId: "asset1", timeMicros: 0)
            #expect(cache.memoryUsageBytes == 0)
        }

        @Test("Memory usage is correctly tracked across multiple operations")
        func memoryTrackingAccuracy() {
            let cache = FrameCache()
            let frame1 = makeSmallFrame(assetId: "a", timeMicros: 0)
            let frame2 = makeSmallFrame(assetId: "b", timeMicros: 0)
            cache.addFrame(frame1)
            cache.addFrame(frame2)

            let expectedMemory = frame1.memorySizeBytes + frame2.memorySizeBytes
            #expect(cache.memoryUsageBytes == expectedMemory)
        }
    }

    // MARK: - 6. getNearest

    @Suite("Get Nearest Frame")
    struct GetNearestTests {

        @Test("Returns exact frame if available")
        func exactMatch() {
            let cache = FrameCache()
            let exactTime: TimeMicros = fps30FrameDuration * 5
            cache.addFrame(makeSmallFrame(timeMicros: exactTime))

            let result = cache.getNearestFrame(assetId: "asset1", timeMicros: exactTime)
            #expect(result != nil)
            #expect(result?.timeMicros == exactTime)
        }

        @Test("Returns nearest frame when exact is missing")
        func nearestWhenMissing() {
            let cache = FrameCache()
            // Add frames at 0, 2, 4 frame boundaries.
            let t0: TimeMicros = 0
            let t2: TimeMicros = fps30FrameDuration * 2
            let t4: TimeMicros = fps30FrameDuration * 4
            cache.addFrame(makeSmallFrame(timeMicros: t0))
            cache.addFrame(makeSmallFrame(timeMicros: t2))
            cache.addFrame(makeSmallFrame(timeMicros: t4))

            // Query for frame boundary 3, which is not cached.
            // Nearest should be frame 2 (distance 1 frame) or frame 4 (distance 1 frame).
            let queryTime: TimeMicros = fps30FrameDuration * 3
            let result = cache.getNearestFrame(assetId: "asset1", timeMicros: queryTime)
            #expect(result != nil)
            // It should be one of the adjacent frames.
            let resultTime = result!.timeMicros
            let isNearby = resultTime == t2 || resultTime == t4
            #expect(isNearby)
        }

        @Test("Returns nil for empty cache")
        func emptyCache() {
            let cache = FrameCache()
            let result = cache.getNearestFrame(assetId: "asset1", timeMicros: 100_000)
            #expect(result == nil)
        }

        @Test("Returns nil for different asset")
        func differentAsset() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(assetId: "a", timeMicros: 0))
            let result = cache.getNearestFrame(assetId: "b", timeMicros: 0)
            #expect(result == nil)
        }

        @Test("Nearest prefers closer frame")
        func prefersCloser() {
            let cache = FrameCache()
            // Add frames at 0 and 10 frame boundaries.
            let t0: TimeMicros = 0
            let t10: TimeMicros = fps30FrameDuration * 10
            cache.addFrame(makeSmallFrame(timeMicros: t0))
            cache.addFrame(makeSmallFrame(timeMicros: t10))

            // Query at frame 2, which is closer to frame 0.
            let queryTime: TimeMicros = fps30FrameDuration * 2
            let result = cache.getNearestFrame(assetId: "asset1", timeMicros: queryTime)
            #expect(result != nil)
            #expect(result?.timeMicros == t0)
        }
    }

    // MARK: - 7. Clear

    @Suite("Clear")
    struct ClearTests {

        @Test("Clear removes all frames")
        func clearAll() {
            let cache = FrameCache()
            for i in 0..<5 {
                cache.addFrame(makeSmallFrame(timeMicros: TimeMicros(i) * fps30FrameDuration))
            }
            #expect(cache.frameCount == 5)
            #expect(cache.isEmpty == false)

            cache.clear()
            #expect(cache.frameCount == 0)
            #expect(cache.isEmpty == true)
            #expect(cache.memoryUsageBytes == 0)
        }

        @Test("Clear resets scrub direction")
        func clearResetsScrubDirection() {
            let cache = FrameCache()
            cache.recordScrubPosition(0)
            cache.recordScrubPosition(100_000)
            cache.recordScrubPosition(200_000)
            #expect(cache.scrubDirection == 1)

            cache.clear()
            #expect(cache.scrubDirection == 0)
        }

        @Test("After clear, previously cached frames are gone")
        func clearInvalidates() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(assetId: "v1", timeMicros: 0))
            cache.clear()
            #expect(cache.getFrame(assetId: "v1", timeMicros: 0) == nil)
        }
    }

    // MARK: - 8. Set Frame Rate

    @Suite("Set Frame Rate")
    struct SetFrameRateTests {

        @Test("Changing frame rate updates frameRate property")
        func updatesFrameRate() {
            let cache = FrameCache(frameRate: .fps30)
            cache.setFrameRate(.fps60)
            #expect(cache.frameRate == .fps60)
            #expect(cache.frameDurationMicros == Rational.fps60.microsecondsPerFrame)
        }

        @Test("Changing frame rate does not automatically clear cache")
        func doesNotClearCache() {
            let cache = FrameCache(frameRate: .fps30)
            cache.addFrame(makeSmallFrame(timeMicros: 0))
            #expect(cache.frameCount == 1)

            cache.setFrameRate(.fps60)
            // The implementation note says existing frames remain valid.
            #expect(cache.frameCount == 1)
        }

        @Test("Changing frame rate then clearing empties cache")
        func clearAfterFrameRateChange() {
            let cache = FrameCache(frameRate: .fps30)
            cache.addFrame(makeSmallFrame(timeMicros: 0))
            cache.setFrameRate(.fps60)
            cache.clear()
            #expect(cache.frameCount == 0)
            #expect(cache.frameRate == .fps60)
        }

        @Test("Frame rate change updates frame duration")
        func frameDurationUpdated() {
            let cache = FrameCache()
            #expect(cache.frameDurationMicros == 33333) // 30fps

            cache.setFrameRate(.fps24)
            #expect(cache.frameDurationMicros == Rational.fps24.microsecondsPerFrame)
            // 1_000_000 / 24 = 41666
            #expect(cache.frameDurationMicros == 41666)
        }
    }

    // MARK: - 9. Memory Pressure

    @Suite("Memory Pressure Handling")
    struct MemoryPressureTests {

        @Test("Warning reduces capacity to 60")
        func warningReducesCapacity() {
            let cache = FrameCache()
            #expect(cache.maxFrames == 120)

            cache.handleMemoryPressure(.warning)
            #expect(cache.maxFrames == 60)
            #expect(cache.maxFrames == FrameCache.warningMaxFrames)
        }

        @Test("Critical reduces capacity to 20")
        func criticalReducesCapacity() {
            let cache = FrameCache()
            cache.handleMemoryPressure(.critical)
            #expect(cache.maxFrames == 20)
            #expect(cache.maxFrames == FrameCache.criticalMaxFrames)
        }

        @Test("Normal restores capacity to 120")
        func normalRestoresCapacity() {
            let cache = FrameCache()
            cache.handleMemoryPressure(.critical)
            #expect(cache.maxFrames == 20)

            cache.handleMemoryPressure(.normal)
            #expect(cache.maxFrames == 120)
            #expect(cache.maxFrames == FrameCache.normalMaxFrames)
        }

        @Test("Warning evicts excess frames")
        func warningEvictsExcess() {
            let cache = FrameCache()
            // Add 80 small frames.
            for i in 0..<80 {
                cache.addFrame(makeSmallFrame(timeMicros: TimeMicros(i) * fps30FrameDuration))
            }
            #expect(cache.frameCount == 80)

            cache.handleMemoryPressure(.warning)
            // Should evict down to 60.
            #expect(cache.frameCount <= 60)
        }

        @Test("Critical evicts down to 20 frames")
        func criticalEvictsDown() {
            let cache = FrameCache()
            for i in 0..<80 {
                cache.addFrame(makeSmallFrame(timeMicros: TimeMicros(i) * fps30FrameDuration))
            }
            #expect(cache.frameCount == 80)

            cache.handleMemoryPressure(.critical)
            #expect(cache.frameCount <= 20)
        }

        @Test("After critical then normal, capacity allows more frames again")
        func recoveryAfterCritical() {
            let cache = FrameCache()
            cache.handleMemoryPressure(.critical)
            #expect(cache.maxFrames == 20)

            cache.handleMemoryPressure(.normal)
            #expect(cache.maxFrames == 120)

            // Should be able to add more than 20 frames now.
            for i in 0..<50 {
                cache.addFrame(makeSmallFrame(timeMicros: TimeMicros(i) * fps30FrameDuration))
            }
            #expect(cache.frameCount == 50)
        }

        @Test("MemoryPressureLevel raw values are ordered")
        func rawValueOrdering() {
            #expect(MemoryPressureLevel.normal.rawValue == 0)
            #expect(MemoryPressureLevel.warning.rawValue == 1)
            #expect(MemoryPressureLevel.critical.rawValue == 2)
        }
    }

    // MARK: - 10. Dispose

    @Suite("Dispose")
    struct DisposeTests {

        @Test("Dispose clears all frames")
        func disposeClears() {
            let cache = FrameCache()
            for i in 0..<10 {
                cache.addFrame(makeSmallFrame(timeMicros: TimeMicros(i) * fps30FrameDuration))
            }
            #expect(cache.frameCount == 10)

            cache.dispose()
            #expect(cache.frameCount == 0)
            #expect(cache.isEmpty == true)
            #expect(cache.memoryUsageBytes == 0)
        }

        @Test("Dispose resets scrub history")
        func disposeClearsScrubHistory() {
            let cache = FrameCache()
            cache.recordScrubPosition(0)
            cache.recordScrubPosition(100_000)
            cache.dispose()
            #expect(cache.scrubDirection == 0)
        }
    }

    // MARK: - 11. Statistics

    @Suite("Statistics")
    struct StatisticsTests {

        @Test("Statistics returns expected keys")
        func expectedKeys() {
            let cache = FrameCache()
            let stats = cache.statistics
            #expect(stats["frameCount"] != nil)
            #expect(stats["memoryUsageMB"] != nil)
            #expect(stats["maxFrames"] != nil)
            #expect(stats["scrubDirection"] != nil)
            #expect(stats["lruOrderLength"] != nil)
            #expect(stats["prefetchStart"] != nil)
            #expect(stats["prefetchEnd"] != nil)
            #expect(stats["successfullyPrefetchedCount"] != nil)
            #expect(stats["assetIndexCount"] != nil)
        }

        @Test("Statistics reflect current state")
        func reflectsState() {
            let cache = FrameCache()
            cache.addFrame(makeSmallFrame(timeMicros: 0))
            cache.addFrame(makeSmallFrame(assetId: "b", timeMicros: 0))

            let stats = cache.statistics
            #expect(stats["frameCount"] == "2")
            #expect(stats["maxFrames"] == "120")
            #expect(stats["lruOrderLength"] == "2")
            #expect(stats["assetIndexCount"] == "2")
            #expect(stats["scrubDirection"] == "0")
        }

        @Test("Statistics memoryUsageMB is formatted")
        func memoryFormatted() {
            let cache = FrameCache()
            let stats = cache.statistics
            #expect(stats["memoryUsageMB"] == "0.00")
        }

        @Test("Statistics shows nil for prefetch when not active")
        func prefetchNilWhenInactive() {
            let cache = FrameCache()
            let stats = cache.statistics
            #expect(stats["prefetchStart"] == "nil")
            #expect(stats["prefetchEnd"] == "nil")
        }
    }

    // MARK: - 12. Scrub History

    @Suite("Scrub History")
    struct ScrubHistoryTests {

        @Test("clearScrubHistory resets direction to 0")
        func clearResetsDirection() {
            let cache = FrameCache()
            cache.recordScrubPosition(0)
            cache.recordScrubPosition(100_000)
            cache.recordScrubPosition(200_000)
            #expect(cache.scrubDirection == 1)

            cache.clearScrubHistory()
            #expect(cache.scrubDirection == 0)
        }

        @Test("Scrub direction detects forward scrubbing")
        func forwardDirection() {
            let cache = FrameCache()
            cache.recordScrubPosition(0)
            cache.recordScrubPosition(100_000)
            cache.recordScrubPosition(200_000)
            #expect(cache.scrubDirection == 1)
        }

        @Test("Scrub direction detects backward scrubbing")
        func backwardDirection() {
            let cache = FrameCache()
            cache.recordScrubPosition(200_000)
            cache.recordScrubPosition(100_000)
            cache.recordScrubPosition(0)
            #expect(cache.scrubDirection == -1)
        }

        @Test("Scrub direction is 0 when stationary")
        func stationaryDirection() {
            let cache = FrameCache()
            cache.recordScrubPosition(100_000)
            cache.recordScrubPosition(100_000)
            cache.recordScrubPosition(100_000)
            #expect(cache.scrubDirection == 0)
        }

        @Test("Scrub direction is 0 with fewer than 2 positions")
        func insufficientPositions() {
            let cache = FrameCache()
            #expect(cache.scrubDirection == 0)

            cache.recordScrubPosition(100_000)
            #expect(cache.scrubDirection == 0)
        }

        @Test("Position history limited to 5 entries")
        func historyLimit() {
            let cache = FrameCache()
            // Record 7 positions: first backward then forward.
            // After history is trimmed to 5, direction should reflect the latest entries.
            cache.recordScrubPosition(700_000) // will be evicted
            cache.recordScrubPosition(600_000) // will be evicted
            cache.recordScrubPosition(500_000)
            cache.recordScrubPosition(400_000)
            cache.recordScrubPosition(500_000)
            cache.recordScrubPosition(600_000)
            cache.recordScrubPosition(700_000)
            // History: [500000, 400000, 500000, 600000, 700000]
            // Movements: down, up, up, up -> 3 forward, 1 backward -> direction = 1
            #expect(cache.scrubDirection == 1)
        }
    }

    // MARK: - 13. Thread Safety

    @Suite("Thread Safety")
    struct ThreadSafetyTests {

        @Test("Concurrent put and get from multiple tasks")
        func concurrentPutGet() async {
            let cache = FrameCache()
            let iterations = 100

            await withTaskGroup(of: Void.self) { group in
                // Writer tasks: add frames from different "assets".
                for i in 0..<iterations {
                    group.addTask {
                        let assetId = "asset\(i % 5)"
                        let t = TimeMicros(i) * fps30FrameDuration
                        let frame = makeSmallFrame(assetId: assetId, timeMicros: t)
                        cache.addFrame(frame)
                    }
                }

                // Reader tasks: attempt to get frames (may or may not be cached yet).
                for i in 0..<iterations {
                    group.addTask {
                        let assetId = "asset\(i % 5)"
                        let t = TimeMicros(i) * fps30FrameDuration
                        // Result doesn't matter; we're testing no crash.
                        _ = cache.getFrame(assetId: assetId, timeMicros: t)
                    }
                }
            }

            // Verify cache is in a consistent state after concurrent access.
            #expect(cache.frameCount >= 0)
            #expect(cache.frameCount <= iterations)
            #expect(cache.memoryUsageBytes >= 0)
        }

        @Test("Concurrent adds and clears don't crash")
        func concurrentAddAndClear() async {
            let cache = FrameCache()

            await withTaskGroup(of: Void.self) { group in
                // Rapid adds.
                for i in 0..<50 {
                    group.addTask {
                        let t = TimeMicros(i) * fps30FrameDuration
                        cache.addFrame(makeSmallFrame(timeMicros: t))
                    }
                }

                // Interleaved clears.
                for _ in 0..<5 {
                    group.addTask {
                        cache.clear()
                    }
                }
            }

            // Should be in a consistent state.
            #expect(cache.frameCount >= 0)
            #expect(cache.memoryUsageBytes >= 0)
        }

        @Test("Concurrent memory pressure changes don't crash")
        func concurrentMemoryPressure() async {
            let cache = FrameCache()

            // Fill with some frames first.
            for i in 0..<50 {
                cache.addFrame(makeSmallFrame(timeMicros: TimeMicros(i) * fps30FrameDuration))
            }

            await withTaskGroup(of: Void.self) { group in
                let levels: [MemoryPressureLevel] = [.normal, .warning, .critical]
                for i in 0..<30 {
                    group.addTask {
                        cache.handleMemoryPressure(levels[i % 3])
                    }
                }
                for i in 0..<30 {
                    group.addTask {
                        let t = TimeMicros(i + 50) * fps30FrameDuration
                        cache.addFrame(makeSmallFrame(timeMicros: t))
                    }
                }
            }

            #expect(cache.frameCount >= 0)
            #expect(cache.memoryUsageBytes >= 0)
        }

        @Test("Concurrent getNearestFrame doesn't crash")
        func concurrentGetNearest() async {
            let cache = FrameCache()

            // Pre-populate.
            for i in 0..<30 {
                cache.addFrame(makeSmallFrame(timeMicros: TimeMicros(i) * fps30FrameDuration))
            }

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<100 {
                    group.addTask {
                        let t = TimeMicros(i) * (fps30FrameDuration / 2) // Query at half-frame positions
                        _ = cache.getNearestFrame(assetId: "asset1", timeMicros: t)
                    }
                }
            }

            #expect(cache.frameCount >= 0)
        }
    }

    // MARK: - CachedFrame Tests

    @Suite("CachedFrame")
    struct CachedFrameTests {

        @Test("memorySizeBytes returns pixel data count")
        func memorySize() {
            let pixels = Data(repeating: 0, count: 1024)
            let frame = CachedFrame(
                assetId: "a",
                timeMicros: 0,
                pixels: pixels,
                width: 16,
                height: 16
            )
            #expect(frame.memorySizeBytes == 1024)
        }

        @Test("memorySizeMB converts correctly")
        func memorySizeMB() {
            let oneMB = 1024 * 1024
            let pixels = Data(repeating: 0, count: oneMB)
            let frame = CachedFrame(
                assetId: "a",
                timeMicros: 0,
                pixels: pixels,
                width: 1,
                height: 1
            )
            #expect(abs(frame.memorySizeMB - 1.0) < 0.001)
        }

        @Test("Default isExact is true")
        func defaultIsExact() {
            let frame = CachedFrame(
                assetId: "a",
                timeMicros: 0,
                pixels: Data(),
                width: 1,
                height: 1
            )
            #expect(frame.isExact == true)
        }

        @Test("cachedAt defaults to current time")
        func defaultCachedAt() {
            let before = Date()
            let frame = CachedFrame(
                assetId: "a",
                timeMicros: 0,
                pixels: Data(),
                width: 1,
                height: 1
            )
            let after = Date()
            #expect(frame.cachedAt >= before)
            #expect(frame.cachedAt <= after)
        }
    }
}
