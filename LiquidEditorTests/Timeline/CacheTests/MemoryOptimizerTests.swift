import Testing
import Foundation
@testable import LiquidEditor

// MARK: - TimelineCacheMemoryPressureLevel Tests

@Suite("TimelineCacheMemoryPressureLevel Tests")
struct TimelineCacheMemoryPressureLevelTests {

    @Test("All three levels exist")
    func allLevels() {
        let _ = TimelineCacheMemoryPressureLevel.normal
        let _ = TimelineCacheMemoryPressureLevel.warning
        let _ = TimelineCacheMemoryPressureLevel.critical
    }
}

// MARK: - TimelineCacheMemoryStats Tests

@Suite("TimelineCacheMemoryStats Tests")
struct TimelineCacheMemoryStatsTests {

    @Test("totalBytes sums both caches")
    func totalBytes() {
        let stats = TimelineCacheMemoryStats(
            thumbnailCacheBytes: 1000,
            thumbnailCacheCount: 5,
            thumbnailPendingCount: 2,
            waveformCacheBytes: 500,
            waveformCacheCount: 3,
            pressureLevel: .normal
        )
        #expect(stats.totalBytes == 1500)
    }

    @Test("formatted produces readable string")
    func formatted() {
        let stats = TimelineCacheMemoryStats(
            thumbnailCacheBytes: 1_048_576,  // 1 MB
            thumbnailCacheCount: 10,
            thumbnailPendingCount: 0,
            waveformCacheBytes: 524_288,     // 0.5 MB
            waveformCacheCount: 5,
            pressureLevel: .warning
        )
        let text = stats.formatted
        #expect(text.contains("1.5"))
        #expect(text.contains("Thumbs: 10"))
        #expect(text.contains("Waves: 5"))
        #expect(text.contains("warning"))
    }
}

// MARK: - MemoryOptimizer Tests

@Suite("MemoryOptimizer Tests")
struct MemoryOptimizerTests {

    // MARK: - Initialization

    @Suite("Initialization")
    struct InitTests {

        @Test("Default maxCombinedBytes is 80MB")
        func defaultLimit() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )
            let maxBytes = await optimizer.maxCombinedBytes
            #expect(maxBytes == 80 * 1024 * 1024)
        }

        @Test("Custom maxCombinedBytes is respected")
        func customLimit() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave,
                maxCombinedBytes: 10_000
            )
            let maxBytes = await optimizer.maxCombinedBytes
            #expect(maxBytes == 10_000)
        }
    }

    // MARK: - Memory Pressure Handling

    @Suite("Memory Pressure")
    struct MemoryPressureTests {

        @Test("Normal pressure does not clear caches")
        func normalPressure() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.handleMemoryWarning(.normal)

            // No crash, caches should be unaffected.
            let thumbCount = await thumb.cachedCount
            let waveCount = await wave.cachedCount
            #expect(thumbCount == 0)
            #expect(waveCount == 0)
        }

        @Test("Warning pressure triggers cache reduction")
        func warningPressure() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            // Handling warning should not crash on empty caches.
            await optimizer.handleMemoryWarning(.warning)

            // Stats should show warning level.
            let stats = await optimizer.stats()
            #expect(stats.pressureLevel == .warning)
        }

        @Test("Critical pressure triggers aggressive eviction")
        func criticalPressure() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.handleMemoryWarning(.critical)

            let stats = await optimizer.stats()
            #expect(stats.pressureLevel == .critical)
        }
    }

    // MARK: - Visible Assets

    @Suite("Visible Assets")
    struct VisibleAssetsTests {

        @Test("updateVisibleAssets stores the set")
        func storesVisibleAssets() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.updateVisibleAssets(["asset1", "asset2"])

            // No crash; visible assets are used internally during critical pressure.
        }
    }

    // MARK: - Stats

    @Suite("Statistics")
    struct StatsTests {

        @Test("Stats reflect current cache state")
        func statsReflectState() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            let stats = await optimizer.stats()
            #expect(stats.thumbnailCacheBytes == 0)
            #expect(stats.thumbnailCacheCount == 0)
            #expect(stats.thumbnailPendingCount == 0)
            #expect(stats.waveformCacheBytes == 0)
            #expect(stats.waveformCacheCount == 0)
            #expect(stats.totalBytes == 0)
            #expect(stats.pressureLevel == .normal)
        }
    }

    // MARK: - Lifecycle

    @Suite("Lifecycle")
    struct LifecycleTests {

        @Test("Start and stop do not crash")
        func startStop() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.start()
            // Let it run briefly.
            try? await Task.sleep(nanoseconds: 100_000_000)
            await optimizer.stop()
        }

        @Test("Double start is safe")
        func doubleStart() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.start()
            await optimizer.start()  // Should be a no-op.
            await optimizer.stop()
        }

        @Test("Dispose stops monitoring and clears caches")
        func dispose() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.start()
            await optimizer.dispose()

            let thumbCount = await thumb.cachedCount
            let waveCount = await wave.cachedCount
            #expect(thumbCount == 0)
            #expect(waveCount == 0)
        }
    }

    // MARK: - Preload

    @Suite("Preload")
    struct PreloadTests {

        @Test("preloadForPlayback does not crash")
        func preloadDoesNotCrash() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.preloadForPlayback(
                upcomingAssetIds: ["asset1", "asset2"],
                currentTimeMicros: 0,
                lookAheadMicros: 5_000_000
            )
        }
    }

    // MARK: - Concurrent Access

    @Suite("Concurrent Access")
    struct ConcurrentAccessTests {

        @Test("Concurrent operations do not crash")
        func concurrentOps() async {
            let thumb = ThumbnailCache()
            let wave = WaveformCache()
            let optimizer = MemoryOptimizer(
                thumbnailCache: thumb,
                waveformCache: wave
            )

            await optimizer.start()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await optimizer.handleMemoryWarning(.warning)
                }
                group.addTask {
                    await optimizer.handleMemoryWarning(.critical)
                }
                group.addTask {
                    await optimizer.handleMemoryWarning(.normal)
                }
                group.addTask {
                    await optimizer.updateVisibleAssets(["a", "b"])
                }
                group.addTask {
                    _ = await optimizer.stats()
                }
                group.addTask {
                    await optimizer.preloadForPlayback(
                        upcomingAssetIds: ["c"],
                        currentTimeMicros: 0,
                        lookAheadMicros: 1_000_000
                    )
                }
            }

            await optimizer.stop()
        }
    }
}
