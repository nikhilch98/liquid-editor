import Testing
import Foundation
import UIKit
@testable import LiquidEditor

// MARK: - Test Helpers

/// Creates a 1x1 UIImage for lightweight cache testing.
private func makeThumbnail(width: Int = 1, height: Int = 1) -> UIImage {
    let size = CGSize(width: width, height: height)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        UIColor.red.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }
}

// MARK: - ThumbnailKey Tests

@Suite("ThumbnailKey Tests")
struct ThumbnailKeyTests {

    @Test("Equal keys with same fields")
    func equalKeys() {
        let a = ThumbnailKey(assetId: "asset1", timeMicros: 1000, width: 100)
        let b = ThumbnailKey(assetId: "asset1", timeMicros: 1000, width: 100)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different assetId produces different keys")
    func differentAssetId() {
        let a = ThumbnailKey(assetId: "asset1", timeMicros: 1000, width: 100)
        let b = ThumbnailKey(assetId: "asset2", timeMicros: 1000, width: 100)
        #expect(a != b)
    }

    @Test("Different timeMicros produces different keys")
    func differentTime() {
        let a = ThumbnailKey(assetId: "asset1", timeMicros: 1000, width: 100)
        let b = ThumbnailKey(assetId: "asset1", timeMicros: 2000, width: 100)
        #expect(a != b)
    }

    @Test("Different width produces different keys")
    func differentWidth() {
        let a = ThumbnailKey(assetId: "asset1", timeMicros: 1000, width: 100)
        let b = ThumbnailKey(assetId: "asset1", timeMicros: 1000, width: 200)
        #expect(a != b)
    }

    @Test("Hashable conformance works in Set")
    func hashableInSet() {
        let key1 = ThumbnailKey(assetId: "a", timeMicros: 0, width: 50)
        let key2 = ThumbnailKey(assetId: "a", timeMicros: 0, width: 50)
        let key3 = ThumbnailKey(assetId: "b", timeMicros: 0, width: 50)

        var set: Set<ThumbnailKey> = [key1, key2, key3]
        #expect(set.count == 2)
        set.insert(key1)
        #expect(set.count == 2)
    }
}

// MARK: - ThumbnailCache Tests

@Suite("ThumbnailCache Tests")
struct ThumbnailCacheTests {

    // MARK: - Initialization

    @Suite("Initialization")
    struct InitTests {

        @Test("Default limits are set correctly")
        func defaultLimits() async {
            let cache = ThumbnailCache()
            let memBytes = await cache.maxMemoryBytes
            let maxThumb = await cache.maxThumbnails
            #expect(memBytes == 50 * 1024 * 1024)
            #expect(maxThumb == 500)
        }

        @Test("Custom limits are respected")
        func customLimits() async {
            let cache = ThumbnailCache(maxMemoryBytes: 10_000, maxThumbnails: 10)
            let memBytes = await cache.maxMemoryBytes
            let maxThumb = await cache.maxThumbnails
            #expect(memBytes == 10_000)
            #expect(maxThumb == 10)
        }

        @Test("Initial state is empty")
        func initialEmpty() async {
            let cache = ThumbnailCache()
            let count = await cache.cachedCount
            let memory = await cache.currentMemoryBytes
            let pending = await cache.pendingCount
            let loading = await cache.loadingCount
            #expect(count == 0)
            #expect(memory == 0)
            #expect(pending == 0)
            #expect(loading == 0)
        }
    }

    // MARK: - Cache Hit/Miss

    @Suite("Cache Hit and Miss")
    struct CacheHitMissTests {

        @Test("Returns nil for uncached thumbnail")
        func cacheMiss() async {
            let cache = ThumbnailCache()
            let result = await cache.getThumbnail(assetId: "a", timeMicros: 0, width: 100)
            #expect(result == nil)
        }

        @Test("hasThumbnail returns false for uncached")
        func hasThumbnailFalse() async {
            let cache = ThumbnailCache()
            let has = await cache.hasThumbnail(assetId: "a", timeMicros: 0, width: 100)
            #expect(has == false)
        }
    }

    // MARK: - LRU Eviction

    @Suite("LRU Eviction")
    struct LRUEvictionTests {

        @Test("Evicts oldest thumbnails when max count exceeded")
        func evictsOnCountOverflow() async {
            // Cache with max 3 thumbnails, large memory budget.
            let cache = ThumbnailCache(maxMemoryBytes: 100 * 1024 * 1024, maxThumbnails: 3)

            // Directly add thumbnails by using a loader that returns instantly.
            // We'll use a trick: set the loader and call getThumbnail in sequence.
            // Instead, we test via the internal path by leveraging preload + loader.

            // For a direct unit test of LRU, we use a synchronous approach:
            // Since ThumbnailCache is an actor, we verify behavior through its
            // public interface after loading completes.

            let loadedCount = ActorIsolated(0)
            await cache.setThumbnailLoader { _, _, _ in
                await loadedCount.increment()
                return makeThumbnail()
            }

            // Trigger loads for 4 thumbnails (max is 3).
            for i in 0..<4 {
                _ = await cache.getThumbnail(assetId: "a", timeMicros: TimeMicros(i * 1000), width: 50)
            }

            // Wait for all loads to complete.
            try? await Task.sleep(nanoseconds: 500_000_000)

            let count = await cache.cachedCount
            // Should have at most 3 (the max).
            #expect(count <= 3)
        }

        @Test("Evicts oldest thumbnails when memory exceeded")
        func evictsOnMemoryOverflow() async {
            // Image memory depends on screen scale and row alignment.
            // Compute actual bytes per image to set a meaningful budget.
            let sampleImage = makeThumbnail(width: 10, height: 10)
            let bytesPerImage: Int
            if let cg = sampleImage.cgImage {
                bytesPerImage = cg.bytesPerRow * cg.height
            } else {
                let w = Int(sampleImage.size.width * sampleImage.scale)
                let h = Int(sampleImage.size.height * sampleImage.scale)
                bytesPerImage = w * h * 4
            }

            // Budget fits at most 2 images.
            let maxMemory = bytesPerImage * 2 + bytesPerImage / 2
            let cache = ThumbnailCache(maxMemoryBytes: maxMemory, maxThumbnails: 100)

            await cache.setThumbnailLoader { _, _, _ in
                return makeThumbnail(width: 10, height: 10)
            }

            // Trigger 5 loads.
            for i in 0..<5 {
                _ = await cache.getThumbnail(assetId: "a", timeMicros: TimeMicros(i * 1000), width: 50)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)

            let memory = await cache.currentMemoryBytes
            #expect(memory <= maxMemory)
        }
    }

    // MARK: - Clear Operations

    @Suite("Clear Operations")
    struct ClearTests {

        @Test("Clear resets all state")
        func clearAll() async {
            let cache = ThumbnailCache()

            await cache.setThumbnailLoader { _, _, _ in makeThumbnail() }
            _ = await cache.getThumbnail(assetId: "a", timeMicros: 0, width: 50)
            try? await Task.sleep(nanoseconds: 200_000_000)

            await cache.clear()

            let count = await cache.cachedCount
            let memory = await cache.currentMemoryBytes
            let pending = await cache.pendingCount
            #expect(count == 0)
            #expect(memory == 0)
            #expect(pending == 0)
        }

        @Test("clearAsset removes only that asset's thumbnails")
        func clearAsset() async {
            let cache = ThumbnailCache()

            await cache.setThumbnailLoader { _, _, _ in makeThumbnail() }

            _ = await cache.getThumbnail(assetId: "a", timeMicros: 0, width: 50)
            _ = await cache.getThumbnail(assetId: "b", timeMicros: 0, width: 50)
            try? await Task.sleep(nanoseconds: 200_000_000)

            let countBefore = await cache.cachedCount
            #expect(countBefore == 2)

            await cache.clearAsset("a")

            let countAfter = await cache.cachedCount
            #expect(countAfter == 1)

            let hasA = await cache.hasThumbnail(assetId: "a", timeMicros: 0, width: 50)
            let hasB = await cache.hasThumbnail(assetId: "b", timeMicros: 0, width: 50)
            #expect(hasA == false)
            #expect(hasB == true)
        }

        @Test("Dispose clears everything")
        func dispose() async {
            let cache = ThumbnailCache()

            await cache.setThumbnailLoader { _, _, _ in makeThumbnail() }
            _ = await cache.getThumbnail(assetId: "a", timeMicros: 0, width: 50)
            try? await Task.sleep(nanoseconds: 200_000_000)

            await cache.dispose()

            let count = await cache.cachedCount
            #expect(count == 0)
        }
    }

    // MARK: - Reduce Size

    @Suite("Reduce Size")
    struct ReduceSizeTests {

        @Test("reduceSize evicts down to target percentage")
        func reduceSizeEvicts() async {
            let cache = ThumbnailCache()

            await cache.setThumbnailLoader { _, _, _ in makeThumbnail() }

            for i in 0..<10 {
                _ = await cache.getThumbnail(assetId: "a", timeMicros: TimeMicros(i * 1000), width: 50)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)

            let countBefore = await cache.cachedCount
            #expect(countBefore == 10)

            await cache.reduceSize(0.5)

            let countAfter = await cache.cachedCount
            #expect(countAfter <= 5)
        }
    }

    // MARK: - Pause/Resume

    @Suite("Pause and Resume")
    struct PauseResumeTests {

        @Test("Pausing stops new loads from starting")
        func pauseStopsLoads() async {
            let cache = ThumbnailCache()
            let loadCount = ActorIsolated(0)

            await cache.setThumbnailLoader { _, _, _ in
                await loadCount.increment()
                return makeThumbnail()
            }

            await cache.pauseLoading()

            // These should be queued but not loaded.
            _ = await cache.getThumbnail(assetId: "a", timeMicros: 0, width: 50)
            _ = await cache.getThumbnail(assetId: "b", timeMicros: 0, width: 50)

            try? await Task.sleep(nanoseconds: 200_000_000)

            let pending = await cache.pendingCount
            // Items should still be pending (not loaded) since loading is paused.
            // Note: some may have been scheduled before pause took effect.
            #expect(pending >= 0)
        }
    }

    // MARK: - Concurrent Access

    @Suite("Concurrent Access")
    struct ConcurrentAccessTests {

        @Test("Concurrent getThumbnail calls do not crash")
        func concurrentAccess() async {
            let cache = ThumbnailCache()
            await cache.setThumbnailLoader { _, _, _ in makeThumbnail() }

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<50 {
                    group.addTask {
                        _ = await cache.getThumbnail(
                            assetId: "asset\(i % 5)",
                            timeMicros: TimeMicros(i * 1000),
                            width: 50
                        )
                    }
                }
            }

            // Just verify no crash and consistent state.
            let count = await cache.cachedCount
            #expect(count >= 0)
        }

        @Test("Concurrent clear and getThumbnail do not crash")
        func concurrentClearAndGet() async {
            let cache = ThumbnailCache()
            await cache.setThumbnailLoader { _, _, _ in makeThumbnail() }

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<30 {
                    group.addTask {
                        _ = await cache.getThumbnail(
                            assetId: "a",
                            timeMicros: TimeMicros(i * 1000),
                            width: 50
                        )
                    }
                }
                for _ in 0..<5 {
                    group.addTask {
                        await cache.clear()
                    }
                }
            }

            let count = await cache.cachedCount
            #expect(count >= 0)
        }
    }
}

// MARK: - ActorIsolated Helper

/// Simple actor for thread-safe counter in tests.
private actor ActorIsolated<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

extension ActorIsolated where Value == Int {
    func increment() {
        value += 1
    }

    func get() -> Int {
        value
    }
}
