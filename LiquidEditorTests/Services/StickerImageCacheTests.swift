// StickerImageCacheTests.swift
// LiquidEditorTests
//
// Tests for StickerImageCache using Swift Testing.
// Validates LRU eviction, memory pressure handling,
// cache hit/miss, and load-and-cache operations.

import Testing
import Foundation
import UIKit
@testable import LiquidEditor

@Suite("StickerImageCache Tests")
struct StickerImageCacheTests {

    // MARK: - Helpers

    /// Create a test UIImage of a given size.
    private func makeImage(width: Int = 10, height: Int = 10) -> UIImage {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height)
        )
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Create a temp PNG file for load testing.
    private func createTempPNG() throws -> String {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        let data = renderer.pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }

        let tempDir = FileManager.default.temporaryDirectory
        let path = tempDir.appendingPathComponent(UUID().uuidString + ".png").path
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Initial State

    @Test("Initial state: empty cache, zero memory")
    func initialState() async {
        let cache = StickerImageCache()

        let count = await cache.count
        let memory = await cache.currentMemoryBytes
        let isEmpty = await cache.isEmpty

        #expect(count == 0)
        #expect(memory == 0)
        #expect(isEmpty)
    }

    // MARK: - Put and Get

    @Test("Put and get returns same image")
    func putAndGet() async {
        let cache = StickerImageCache()
        let image = makeImage()

        await cache.put("sticker_1", image: image)

        let retrieved = await cache.get("sticker_1")
        #expect(retrieved != nil)
        #expect(retrieved?.size == image.size)
    }

    @Test("Get nonexistent returns nil")
    func getMiss() async {
        let cache = StickerImageCache()

        let result = await cache.get("nonexistent")
        #expect(result == nil)
    }

    @Test("Put updates count and memory")
    func putUpdatesCountAndMemory() async {
        let cache = StickerImageCache()
        let image = makeImage(width: 10, height: 10)

        await cache.put("sticker_1", image: image)

        let count = await cache.count
        let memory = await cache.currentMemoryBytes

        #expect(count == 1)
        #expect(memory > 0)
    }

    @Test("Put same key replaces entry")
    func putReplaces() async {
        let cache = StickerImageCache()
        let image1 = makeImage(width: 10, height: 10)
        let image2 = makeImage(width: 20, height: 20)

        await cache.put("sticker_1", image: image1)
        await cache.put("sticker_1", image: image2)

        let count = await cache.count
        #expect(count == 1)

        let retrieved = await cache.get("sticker_1")
        #expect(retrieved?.size.width == 20)
    }

    // MARK: - Contains

    @Test("Contains returns true for cached item")
    func containsHit() async {
        let cache = StickerImageCache()
        await cache.put("sticker_1", image: makeImage())

        let result = await cache.contains("sticker_1")
        #expect(result)
    }

    @Test("Contains returns false for missing item")
    func containsMiss() async {
        let cache = StickerImageCache()

        let result = await cache.contains("nonexistent")
        #expect(!result)
    }

    // MARK: - LRU Eviction by Count

    @Test("Evicts oldest entry when max entries exceeded")
    func evictionByCount() async {
        // Cache with max 3 entries
        let cache = StickerImageCache(maxEntries: 3, maxMemoryBytes: 100 * 1024 * 1024)

        await cache.put("a", image: makeImage())
        await cache.put("b", image: makeImage())
        await cache.put("c", image: makeImage())

        // Adding a 4th should evict "a" (oldest)
        await cache.put("d", image: makeImage())

        let count = await cache.count
        #expect(count == 3)

        let hasA = await cache.contains("a")
        let hasD = await cache.contains("d")
        #expect(!hasA) // evicted
        #expect(hasD)  // still present
    }

    @Test("Get updates LRU order, preventing eviction")
    func getLRUOrder() async {
        let cache = StickerImageCache(maxEntries: 3, maxMemoryBytes: 100 * 1024 * 1024)

        await cache.put("a", image: makeImage())
        await cache.put("b", image: makeImage())
        await cache.put("c", image: makeImage())

        // Access "a" to make it most recently used
        _ = await cache.get("a")

        // Adding "d" should evict "b" (now oldest)
        await cache.put("d", image: makeImage())

        let hasA = await cache.contains("a")
        let hasB = await cache.contains("b")
        #expect(hasA) // accessed recently, not evicted
        #expect(!hasB) // evicted
    }

    // MARK: - LRU Eviction by Memory

    @Test("Evicts entries when memory budget exceeded")
    func evictionByMemory() async {
        // Image memory depends on screen scale (e.g. 2x or 3x).
        // Compute actual bytes per image: (width * scale) * (height * scale) * 4
        let sampleImage = makeImage(width: 10, height: 10)
        let scale = sampleImage.scale
        let bytesPerImage = Int(10 * scale) * Int(10 * scale) * 4

        // Budget fits 2 images but not 3.
        let maxMemory = bytesPerImage * 2 + bytesPerImage / 2
        let cache = StickerImageCache(maxEntries: 100, maxMemoryBytes: maxMemory)

        await cache.put("a", image: makeImage(width: 10, height: 10))
        await cache.put("b", image: makeImage(width: 10, height: 10))

        // This should trigger eviction of "a"
        await cache.put("c", image: makeImage(width: 10, height: 10))

        let hasA = await cache.contains("a")
        let hasC = await cache.contains("c")
        #expect(!hasA) // evicted for memory
        #expect(hasC)
    }

    @Test("Image exceeding total budget is not cached")
    func imageTooLargeForBudget() async {
        // Set max to 100 bytes
        let cache = StickerImageCache(maxEntries: 100, maxMemoryBytes: 100)

        // 10x10x4 = 400 bytes > 100 byte budget
        await cache.put("big", image: makeImage(width: 10, height: 10))

        let count = await cache.count
        #expect(count == 0) // not cached
    }

    // MARK: - Remove

    @Test("Remove removes entry and frees memory")
    func remove() async {
        let cache = StickerImageCache()
        await cache.put("sticker_1", image: makeImage())

        let memoryBefore = await cache.currentMemoryBytes
        #expect(memoryBefore > 0)

        await cache.remove("sticker_1")

        let count = await cache.count
        let memory = await cache.currentMemoryBytes
        #expect(count == 0)
        #expect(memory == 0)
    }

    @Test("Remove nonexistent is safe")
    func removeNonexistent() async {
        let cache = StickerImageCache()

        // Should not crash
        await cache.remove("nonexistent")

        let count = await cache.count
        #expect(count == 0)
    }

    // MARK: - Clear

    @Test("Clear removes all entries and resets memory")
    func clear() async {
        let cache = StickerImageCache()

        await cache.put("a", image: makeImage())
        await cache.put("b", image: makeImage())
        await cache.put("c", image: makeImage())

        await cache.clear()

        let count = await cache.count
        let memory = await cache.currentMemoryBytes
        let isEmpty = await cache.isEmpty

        #expect(count == 0)
        #expect(memory == 0)
        #expect(isEmpty)
    }

    // MARK: - Memory Pressure

    @Test("Memory pressure evicts half the cache")
    func memoryPressure() async {
        let cache = StickerImageCache(maxEntries: 100, maxMemoryBytes: 100 * 1024 * 1024)

        for i in 0..<10 {
            await cache.put("sticker_\(i)", image: makeImage())
        }

        let countBefore = await cache.count
        #expect(countBefore == 10)

        await cache.handleMemoryPressure()

        let countAfter = await cache.count
        #expect(countAfter == 5) // Half evicted
    }

    @Test("Memory pressure on empty cache is safe")
    func memoryPressureEmpty() async {
        let cache = StickerImageCache()

        // Should not crash
        await cache.handleMemoryPressure()

        let count = await cache.count
        #expect(count == 0)
    }

    // MARK: - Load and Cache from File

    @Test("loadAndCache loads image from file and caches it")
    func loadAndCacheFromFile() async throws {
        let cache = StickerImageCache()
        let path = try createTempPNG()
        defer { cleanup(path) }

        let image = await cache.loadAndCache(assetId: "file_sticker", filePath: path)
        #expect(image != nil)

        // Should be cached now
        let cached = await cache.get("file_sticker")
        #expect(cached != nil)
    }

    @Test("loadAndCache returns cached image on second call")
    func loadAndCacheCacheHit() async throws {
        let cache = StickerImageCache()
        let path = try createTempPNG()
        defer { cleanup(path) }

        let first = await cache.loadAndCache(assetId: "hit_test", filePath: path)
        let second = await cache.loadAndCache(assetId: "hit_test", filePath: path)

        #expect(first != nil)
        #expect(second != nil)
        // Both should be the same cached instance
        #expect(first === second)
    }

    @Test("loadAndCache returns nil for invalid path")
    func loadAndCacheInvalidPath() async {
        let cache = StickerImageCache()

        let image = await cache.loadAndCache(
            assetId: "invalid",
            filePath: "/nonexistent/image.png"
        )
        #expect(image == nil)
    }

    // MARK: - Load and Cache from Data

    @Test("loadFromDataAndCache decodes and caches image")
    func loadFromDataAndCache() async {
        let cache = StickerImageCache()

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let data = renderer.pngData { context in
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }

        let image = await cache.loadFromDataAndCache(assetId: "data_sticker", data: data)
        #expect(image != nil)

        let cached = await cache.get("data_sticker")
        #expect(cached != nil)
    }

    @Test("loadFromDataAndCache returns nil for invalid data")
    func loadFromDataInvalid() async {
        let cache = StickerImageCache()

        let invalidData = Data([0x00, 0x01, 0x02])
        let image = await cache.loadFromDataAndCache(assetId: "bad", data: invalidData)
        #expect(image == nil)
    }

    @Test("loadFromDataAndCache returns cached on second call")
    func loadFromDataCacheHit() async {
        let cache = StickerImageCache()

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let data = renderer.pngData { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }

        let first = await cache.loadFromDataAndCache(assetId: "data_hit", data: data)
        let second = await cache.loadFromDataAndCache(assetId: "data_hit", data: data)

        #expect(first != nil)
        #expect(second != nil)
        #expect(first === second)
    }

    // MARK: - Configuration

    @Test("Custom configuration is respected")
    func customConfig() async {
        let cache = StickerImageCache(maxEntries: 5, maxMemoryBytes: 1024)

        let maxEntries = await cache.maxEntries
        let maxMemory = await cache.maxMemoryBytes

        #expect(maxEntries == 5)
        #expect(maxMemory == 1024)
    }

    // MARK: - Memory MB

    @Test("currentMemoryMB returns correct conversion")
    func memoryMB() async {
        let cache = StickerImageCache()

        let mb = await cache.currentMemoryMB
        #expect(mb == 0.0)

        await cache.put("x", image: makeImage(width: 10, height: 10))

        let mbAfter = await cache.currentMemoryMB
        // 10*10*4 = 400 bytes = ~0.000381 MB
        #expect(mbAfter > 0)
        #expect(mbAfter < 1.0)
    }
}
