import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Creates a simple WaveformData with a linear ramp for testing.
private func makeWaveformData(
    sampleCount: Int = 100,
    sampleRate: Int = 44100,
    durationMicros: Int64 = 1_000_000,
    lod: WaveformLevelOfDetail = .low
) -> WaveformData {
    var samples = [Float](repeating: 0.0, count: sampleCount)
    for i in 0..<sampleCount {
        samples[i] = Float(i) / Float(sampleCount)  // Linear ramp 0.0 -> ~1.0
    }
    return WaveformData(
        samples: samples,
        sampleRate: sampleRate,
        durationMicros: durationMicros,
        levelOfDetail: lod
    )
}

// MARK: - WaveformLOD Extension Tests

@Suite("WaveformLOD Extension Tests")
struct WaveformLODExtensionTests {

    @Test("microsPerSample values are correct")
    func microsPerSampleValues() {
        #expect(WaveformLOD.low.microsPerSample == 100_000)
        #expect(WaveformLOD.medium.microsPerSample == 10_000)
        #expect(WaveformLOD.high.microsPerSample == 1_000)
    }

    @Test("selectForZoom returns low for large microsPerPixel")
    func selectLow() {
        #expect(WaveformLOD.selectForZoom(60_000) == .low)
        #expect(WaveformLOD.selectForZoom(100_000) == .low)
    }

    @Test("selectForZoom returns medium for mid-range microsPerPixel")
    func selectMedium() {
        #expect(WaveformLOD.selectForZoom(10_000) == .medium)
        #expect(WaveformLOD.selectForZoom(30_000) == .medium)
    }

    @Test("selectForZoom returns high for small microsPerPixel")
    func selectHigh() {
        #expect(WaveformLOD.selectForZoom(1_000) == .high)
        #expect(WaveformLOD.selectForZoom(3_000) == .high)
    }

    @Test("CaseIterable contains all three cases")
    func allCases() {
        #expect(WaveformLOD.allCases.count == 3)
        #expect(WaveformLOD.allCases.contains(.low))
        #expect(WaveformLOD.allCases.contains(.medium))
        #expect(WaveformLOD.allCases.contains(.high))
    }
}

// MARK: - WaveformData Extension Tests

@Suite("WaveformData Extension Tests")
struct WaveformDataExtensionTests {

    @Test("sizeBytes computes correctly")
    func sizeBytes() {
        let data = makeWaveformData(sampleCount: 50)
        #expect(data.sizeBytes == 200)  // 50 * 4 bytes
    }

    @Test("sampleCount returns correct value")
    func sampleCount() {
        let data = makeWaveformData(sampleCount: 42)
        #expect(data.sampleCount == 42)
    }

    @Test("isEmpty returns true for empty data")
    func emptyCheck() {
        let data = WaveformData(
            samples: [],
            sampleRate: 44100,
            durationMicros: 0,
            levelOfDetail: .low
        )
        #expect(data.isEmpty == true)
        #expect(data.isNotEmpty == false)
    }

    @Test("isEmpty returns false for non-empty data")
    func nonEmptyCheck() {
        let data = makeWaveformData(sampleCount: 10)
        #expect(data.isEmpty == false)
        #expect(data.isNotEmpty == true)
    }

    @Test("getSamplesForRange returns correct subrange")
    func getSamplesForRange() {
        // 100 samples over 1 second at 100Hz sample rate.
        let data = makeWaveformData(sampleCount: 100, sampleRate: 100, durationMicros: 1_000_000)
        let result = data.getSamplesForRange(startMicros: 0, endMicros: 500_000, targetSamples: 50)
        #expect(!result.isEmpty)
        #expect(result.count == 50)
    }

    @Test("getSamplesForRange returns empty for zero target")
    func getSamplesForRangeZeroTarget() {
        let data = makeWaveformData()
        let result = data.getSamplesForRange(startMicros: 0, endMicros: 500_000, targetSamples: 0)
        #expect(result.isEmpty)
    }

    @Test("getSamplesForRange returns empty for empty data")
    func getSamplesForRangeEmptyData() {
        let data = WaveformData(
            samples: [],
            sampleRate: 44100,
            durationMicros: 0,
            levelOfDetail: .low
        )
        let result = data.getSamplesForRange(startMicros: 0, endMicros: 500_000, targetSamples: 10)
        #expect(result.isEmpty)
    }
}

// MARK: - WaveformCacheKey Tests

@Suite("WaveformCacheKey Tests")
struct WaveformCacheKeyTests {

    @Test("Equal keys with same fields")
    func equalKeys() {
        let a = WaveformCacheKey(assetId: "asset1", lod: .low)
        let b = WaveformCacheKey(assetId: "asset1", lod: .low)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different assetId produces different keys")
    func differentAssetId() {
        let a = WaveformCacheKey(assetId: "asset1", lod: .low)
        let b = WaveformCacheKey(assetId: "asset2", lod: .low)
        #expect(a != b)
    }

    @Test("Different LOD produces different keys")
    func differentLOD() {
        let a = WaveformCacheKey(assetId: "asset1", lod: .low)
        let b = WaveformCacheKey(assetId: "asset1", lod: .high)
        #expect(a != b)
    }

    @Test("Hashable conformance works in Set")
    func hashableInSet() {
        let key1 = WaveformCacheKey(assetId: "a", lod: .low)
        let key2 = WaveformCacheKey(assetId: "a", lod: .low)
        let key3 = WaveformCacheKey(assetId: "a", lod: .high)

        let set: Set<WaveformCacheKey> = [key1, key2, key3]
        #expect(set.count == 2)
    }
}

// MARK: - WaveformCache Tests

@Suite("WaveformCache Tests")
struct WaveformCacheTests {

    // MARK: - Initialization

    @Suite("Initialization")
    struct InitTests {

        @Test("Default memory limit is 20MB")
        func defaultLimit() async {
            let cache = WaveformCache()
            #expect(await cache.maxMemoryBytes == 20 * 1024 * 1024)
        }

        @Test("Custom memory limit is respected")
        func customLimit() async {
            let cache = WaveformCache(maxMemoryBytes: 5_000)
            #expect(await cache.maxMemoryBytes == 5_000)
        }

        @Test("Initial state is empty")
        func initialEmpty() async {
            let cache = WaveformCache()
            let count = await cache.cachedCount
            let memory = await cache.currentMemoryBytes
            #expect(count == 0)
            #expect(memory == 0)
        }
    }

    // MARK: - Cache Hit/Miss

    @Suite("Cache Hit and Miss")
    struct CacheHitMissTests {

        @Test("Returns empty for uncached waveform")
        func cacheMiss() async {
            let cache = WaveformCache()
            let result = await cache.getWaveformSamples(
                assetId: "a",
                startMicros: 0,
                endMicros: 500_000,
                targetSamples: 50,
                microsPerPixel: 60_000
            )
            #expect(result.isEmpty)
        }

        @Test("hasWaveform returns false for uncached")
        func hasWaveformFalse() async {
            let cache = WaveformCache()
            let has = await cache.hasWaveform(assetId: "nonexistent")
            #expect(has == false)
        }
    }

    // MARK: - Memory Management

    @Suite("Memory Management")
    struct MemoryTests {

        @Test("Evicts oldest when memory exceeded")
        func evictsOnMemoryOverflow() async {
            // Each waveform ~400 bytes (100 samples * 4 bytes).
            // Limit to 1000 bytes = ~2 waveforms.
            let cache = WaveformCache(maxMemoryBytes: 1000)

            await cache.setWaveformGenerator { _, lod in
                makeWaveformData(sampleCount: 100, lod: .low)
            }

            // Trigger 5 generations.
            for i in 0..<5 {
                _ = await cache.getWaveformSamples(
                    assetId: "asset\(i)",
                    startMicros: 0,
                    endMicros: 500_000,
                    targetSamples: 50,
                    microsPerPixel: 60_000
                )
            }

            try? await Task.sleep(nanoseconds: 500_000_000)

            let memory = await cache.currentMemoryBytes
            #expect(memory <= 1000)
        }
    }

    // MARK: - Clear Operations

    @Suite("Clear Operations")
    struct ClearTests {

        @Test("Clear resets all state")
        func clearAll() async {
            let cache = WaveformCache()

            await cache.setWaveformGenerator { _, _ in makeWaveformData() }

            _ = await cache.getWaveformSamples(
                assetId: "a", startMicros: 0, endMicros: 500_000,
                targetSamples: 50, microsPerPixel: 60_000
            )
            try? await Task.sleep(nanoseconds: 200_000_000)

            await cache.clear()

            let count = await cache.cachedCount
            let memory = await cache.currentMemoryBytes
            #expect(count == 0)
            #expect(memory == 0)
        }

        @Test("clearAsset removes only that asset")
        func clearAsset() async {
            let cache = WaveformCache()

            await cache.setWaveformGenerator { _, _ in makeWaveformData() }

            _ = await cache.getWaveformSamples(
                assetId: "a", startMicros: 0, endMicros: 500_000,
                targetSamples: 50, microsPerPixel: 60_000
            )
            _ = await cache.getWaveformSamples(
                assetId: "b", startMicros: 0, endMicros: 500_000,
                targetSamples: 50, microsPerPixel: 60_000
            )
            try? await Task.sleep(nanoseconds: 300_000_000)

            await cache.clearAsset("a")

            let hasA = await cache.hasWaveform(assetId: "a")
            let hasB = await cache.hasWaveform(assetId: "b")
            #expect(hasA == false)
            #expect(hasB == true)
        }

        @Test("clearAllExcept retains specified assets")
        func clearAllExcept() async {
            let cache = WaveformCache()

            await cache.setWaveformGenerator { _, _ in makeWaveformData() }

            _ = await cache.getWaveformSamples(
                assetId: "a", startMicros: 0, endMicros: 500_000,
                targetSamples: 50, microsPerPixel: 60_000
            )
            _ = await cache.getWaveformSamples(
                assetId: "b", startMicros: 0, endMicros: 500_000,
                targetSamples: 50, microsPerPixel: 60_000
            )
            _ = await cache.getWaveformSamples(
                assetId: "c", startMicros: 0, endMicros: 500_000,
                targetSamples: 50, microsPerPixel: 60_000
            )
            try? await Task.sleep(nanoseconds: 300_000_000)

            await cache.clearAllExcept(["b"])

            let hasA = await cache.hasWaveform(assetId: "a")
            let hasB = await cache.hasWaveform(assetId: "b")
            let hasC = await cache.hasWaveform(assetId: "c")
            #expect(hasA == false)
            #expect(hasB == true)
            #expect(hasC == false)
        }

        @Test("Dispose clears everything")
        func dispose() async {
            let cache = WaveformCache()

            await cache.setWaveformGenerator { _, _ in makeWaveformData() }
            _ = await cache.getWaveformSamples(
                assetId: "a", startMicros: 0, endMicros: 500_000,
                targetSamples: 50, microsPerPixel: 60_000
            )
            try? await Task.sleep(nanoseconds: 200_000_000)

            await cache.dispose()

            let count = await cache.cachedCount
            #expect(count == 0)
        }
    }

    // MARK: - Reduce Size

    @Suite("Reduce Size")
    struct ReduceSizeTests {

        @Test("reduceSize evicts to target percentage")
        func reduceSizeEvicts() async {
            let cache = WaveformCache(maxMemoryBytes: 100 * 1024 * 1024)

            await cache.setWaveformGenerator { _, _ in
                makeWaveformData(sampleCount: 10)
            }

            for i in 0..<10 {
                _ = await cache.getWaveformSamples(
                    assetId: "asset\(i)", startMicros: 0, endMicros: 500_000,
                    targetSamples: 50, microsPerPixel: 60_000
                )
            }
            try? await Task.sleep(nanoseconds: 300_000_000)

            let countBefore = await cache.cachedCount
            #expect(countBefore == 10)

            // Reduce to ~10% of the max memory budget.
            await cache.reduceSize(0.1)

            let memoryAfter = await cache.currentMemoryBytes
            let targetBytes = Int(Double(await cache.maxMemoryBytes) * 0.1)
            #expect(memoryAfter <= targetBytes)
        }
    }

    // MARK: - Concurrent Access

    @Suite("Concurrent Access")
    struct ConcurrentAccessTests {

        @Test("Concurrent getWaveformSamples calls do not crash")
        func concurrentAccess() async {
            let cache = WaveformCache()
            await cache.setWaveformGenerator { _, _ in makeWaveformData() }

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<30 {
                    group.addTask {
                        _ = await cache.getWaveformSamples(
                            assetId: "asset\(i % 5)",
                            startMicros: 0,
                            endMicros: 500_000,
                            targetSamples: 50,
                            microsPerPixel: Double(i * 5_000 + 1_000)
                        )
                    }
                }
            }

            let count = await cache.cachedCount
            #expect(count >= 0)
        }

        @Test("Concurrent clear and get do not crash")
        func concurrentClearAndGet() async {
            let cache = WaveformCache()
            await cache.setWaveformGenerator { _, _ in makeWaveformData() }

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<20 {
                    group.addTask {
                        _ = await cache.getWaveformSamples(
                            assetId: "asset\(i)",
                            startMicros: 0,
                            endMicros: 500_000,
                            targetSamples: 50,
                            microsPerPixel: 60_000
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
