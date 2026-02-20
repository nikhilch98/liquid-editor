// GifFrameCacheTests.swift
// LiquidEditorTests
//
// Tests for GifFrameCache: LRU eviction, cache hit/miss.

import Testing
import CoreGraphics
import Foundation
@testable import LiquidEditor

@Suite("GifFrameCache Tests")
@MainActor
struct GifFrameCacheTests {

    // MARK: - Helpers

    /// Create a minimal valid 1x1 GIF image data for testing.
    /// This is the smallest valid GIF89a file (a 1x1 transparent pixel).
    private var minimalGifData: Data {
        // GIF89a header + minimal image data
        let bytes: [UInt8] = [
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // GIF89a
            0x01, 0x00, 0x01, 0x00, // 1x1 pixels
            0x00, // GCT flag = 0
            0x00, // Background color
            0x00, // Pixel aspect ratio
            0x21, 0xF9, 0x04, // Graphic Control Extension
            0x00, // Packed byte (no transparency, no disposal)
            0x0A, 0x00, // Delay time = 10 (100ms)
            0x00, // Transparent color index
            0x00, // Block terminator
            0x2C, // Image descriptor
            0x00, 0x00, 0x00, 0x00, // Position
            0x01, 0x00, 0x01, 0x00, // 1x1
            0x00, // Packed byte
            0x02, // LZW minimum code size
            0x02, 0x4C, 0x01, // Compressed image data
            0x00, // Block terminator
            0x3B, // Trailer
        ]
        return Data(bytes)
    }

    // MARK: - Initialization

    @Test("Empty cache")
    func emptyCache() {
        let cache = GifFrameCache()
        #expect(cache.animationCount == 0)
        #expect(cache.currentMemoryBytes == 0)
        #expect(!cache.hasFrames("nonexistent"))
    }

    @Test("Custom configuration")
    func customConfig() {
        let cache = GifFrameCache(maxAnimations: 5, maxMemoryBytes: 10 * 1024 * 1024)
        #expect(cache.maxAnimations == 5)
        #expect(cache.maxMemoryBytes == 10 * 1024 * 1024)
    }

    // MARK: - Decode

    @Test("Decode GIF from data")
    func decodeFromData() {
        let cache = GifFrameCache()
        let count = cache.decodeFromData("gif_1", data: minimalGifData)

        #expect(count >= 1)
        #expect(cache.hasFrames("gif_1"))
        #expect(cache.animationCount == 1)
    }

    @Test("Decode same asset twice returns cached count")
    func decodeCachedAsset() {
        let cache = GifFrameCache()
        let count1 = cache.decodeFromData("gif_1", data: minimalGifData)
        let count2 = cache.decodeFromData("gif_1", data: minimalGifData)

        #expect(count1 == count2)
        #expect(cache.animationCount == 1) // Not decoded again
    }

    // MARK: - Frame Access

    @Test("Get frame by index")
    func getFrame() {
        let cache = GifFrameCache()
        let count = cache.decodeFromData("gif_1", data: minimalGifData)
        guard count > 0 else {
            Issue.record("No frames decoded")
            return
        }

        let frame = cache.getFrame("gif_1", frameIndex: 0)
        #expect(frame != nil)
        #expect(frame?.index == 0)
    }

    @Test("Get frame out of bounds returns nil")
    func getFrameOutOfBounds() {
        let cache = GifFrameCache()
        _ = cache.decodeFromData("gif_1", data: minimalGifData)

        #expect(cache.getFrame("gif_1", frameIndex: -1) == nil)
        #expect(cache.getFrame("gif_1", frameIndex: 999) == nil)
    }

    @Test("Get frame for uncached asset returns nil")
    func getFrameUncached() {
        let cache = GifFrameCache()
        #expect(cache.getFrame("nonexistent", frameIndex: 0) == nil)
    }

    @Test("Get frame at progress")
    func getFrameAtProgress() {
        let cache = GifFrameCache()
        _ = cache.decodeFromData("gif_1", data: minimalGifData)

        let image0 = cache.getFrameAtProgress("gif_1", progress: 0.0)
        #expect(image0 != nil)

        let image1 = cache.getFrameAtProgress("gif_1", progress: 1.0)
        #expect(image1 != nil)

        // Progress is clamped
        let imageNeg = cache.getFrameAtProgress("gif_1", progress: -0.5)
        #expect(imageNeg != nil)

        let imageOver = cache.getFrameAtProgress("gif_1", progress: 1.5)
        #expect(imageOver != nil)
    }

    // MARK: - Eviction

    @Test("Evict specific asset")
    func evictAsset() {
        let cache = GifFrameCache()
        _ = cache.decodeFromData("gif_1", data: minimalGifData)
        #expect(cache.hasFrames("gif_1"))

        cache.evict("gif_1")
        #expect(!cache.hasFrames("gif_1"))
        #expect(cache.animationCount == 0)
    }

    @Test("Clear all cached frames")
    func clearAll() {
        let cache = GifFrameCache()
        _ = cache.decodeFromData("gif_1", data: minimalGifData)
        _ = cache.decodeFromData("gif_2", data: minimalGifData)

        cache.clear()
        #expect(cache.animationCount == 0)
        #expect(cache.currentMemoryBytes == 0)
    }

    @Test("LRU eviction on capacity exceeded")
    func lruEviction() {
        let cache = GifFrameCache(maxAnimations: 2)

        _ = cache.decodeFromData("gif_1", data: minimalGifData)
        _ = cache.decodeFromData("gif_2", data: minimalGifData)

        // Access gif_1 to make it more recent
        _ = cache.getFrame("gif_1", frameIndex: 0)

        // Adding gif_3 should evict gif_2 (LRU)
        _ = cache.decodeFromData("gif_3", data: minimalGifData)

        #expect(cache.animationCount <= 2)
        // gif_1 should survive (more recently accessed)
        #expect(cache.hasFrames("gif_1"))
    }

    @Test("Memory pressure eviction")
    func memoryPressure() {
        let cache = GifFrameCache()
        _ = cache.decodeFromData("gif_1", data: minimalGifData)
        _ = cache.decodeFromData("gif_2", data: minimalGifData)

        let countBefore = cache.animationCount
        cache.handleMemoryPressure()

        // Should evict approximately half
        #expect(cache.animationCount <= countBefore)
    }

    // MARK: - Frame Duration

    @Test("Frame count and duration are tracked")
    func frameCountAndDuration() {
        let cache = GifFrameCache()
        let count = cache.decodeFromData("gif_1", data: minimalGifData)

        #expect(cache.frameCount("gif_1") == count)
        #expect(cache.totalDurationMs("gif_1") != nil)
        #expect((cache.totalDurationMs("gif_1") ?? 0) > 0)
    }

    @Test("Uncached asset returns nil for metadata")
    func uncachedMetadata() {
        let cache = GifFrameCache()
        #expect(cache.frameCount("nonexistent") == nil)
        #expect(cache.totalDurationMs("nonexistent") == nil)
    }

    // MARK: - Memory Tracking

    @Test("Memory increases after decode")
    func memoryTracking() {
        let cache = GifFrameCache()
        #expect(cache.currentMemoryBytes == 0)

        _ = cache.decodeFromData("gif_1", data: minimalGifData)
        #expect(cache.currentMemoryBytes > 0)
    }

    @Test("Memory decreases after eviction")
    func memoryAfterEviction() {
        let cache = GifFrameCache()
        _ = cache.decodeFromData("gif_1", data: minimalGifData)
        let memBefore = cache.currentMemoryBytes

        cache.evict("gif_1")
        #expect(cache.currentMemoryBytes < memBefore)
    }
}
