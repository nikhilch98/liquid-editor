// ClipThumbnailServiceTests.swift
// LiquidEditorTests
//
// Tests for ClipThumbnailService and ClipThumbnailConfig.

import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("ClipThumbnailService")
struct ClipThumbnailServiceTests {

    // MARK: - ClipThumbnailConfig Tests

    @Test("thumbnailCount computes correctly")
    func thumbnailCount() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 0,
            sourceOut: 10_000_000,
            clipWidthPixels: 400,
            thumbnailWidth: 80
        )
        #expect(config.thumbnailCount == 5) // 400/80 = 5
    }

    @Test("thumbnailCount returns 0 for zero width")
    func thumbnailCountZeroWidth() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 0,
            sourceOut: 10_000_000,
            clipWidthPixels: 0
        )
        #expect(config.thumbnailCount == 0)
    }

    @Test("thumbnailCount clamps to minimum of 1")
    func thumbnailCountMinimum() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 0,
            sourceOut: 10_000_000,
            clipWidthPixels: 10, // Very narrow
            thumbnailWidth: 80
        )
        #expect(config.thumbnailCount == 1)
    }

    @Test("thumbnailCount clamps to maximum of 50")
    func thumbnailCountMaximum() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 0,
            sourceOut: 10_000_000,
            clipWidthPixels: 10000,
            thumbnailWidth: 10 // Would be 1000 thumbs
        )
        #expect(config.thumbnailCount == 50)
    }

    @Test("sourceDuration computed correctly")
    func sourceDuration() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 2_000_000,
            sourceOut: 8_000_000,
            clipWidthPixels: 400
        )
        #expect(config.sourceDuration == 6_000_000)
    }

    @Test("thumbnailTimes generates correct center times")
    func thumbnailTimes() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 0,
            sourceOut: 10_000_000,
            clipWidthPixels: 400,
            thumbnailWidth: 100 // 4 thumbnails
        )
        let times = config.thumbnailTimes
        #expect(times.count == 4)
        // Each step = 10M/4 = 2.5M
        // Centers: 1.25M, 3.75M, 6.25M, 8.75M
        #expect(times[0] == 1_250_000)
        #expect(times[1] == 3_750_000)
        #expect(times[2] == 6_250_000)
        #expect(times[3] == 8_750_000)
    }

    @Test("thumbnailTimes clamps to source bounds")
    func thumbnailTimesClamp() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 5_000_000,
            sourceOut: 5_100_000, // Very short
            clipWidthPixels: 400,
            thumbnailWidth: 80
        )
        let times = config.thumbnailTimes
        for time in times {
            #expect(time >= 5_000_000)
            #expect(time <= 5_100_000)
        }
    }

    @Test("thumbnailTimes empty for zero duration")
    func thumbnailTimesZeroDuration() {
        let config = ClipThumbnailConfig(
            assetId: "asset-1",
            sourceIn: 5_000_000,
            sourceOut: 5_000_000,
            clipWidthPixels: 400
        )
        #expect(config.thumbnailTimes.isEmpty)
    }

    @Test("equality checks all fields")
    func equality() {
        let a = ClipThumbnailConfig(
            assetId: "a", sourceIn: 0, sourceOut: 10, clipWidthPixels: 400
        )
        let b = ClipThumbnailConfig(
            assetId: "a", sourceIn: 0, sourceOut: 10, clipWidthPixels: 400
        )
        let c = ClipThumbnailConfig(
            assetId: "b", sourceIn: 0, sourceOut: 10, clipWidthPixels: 400
        )
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - configFromClip

    @Test("configFromClip creates correct config")
    func configFromClip() {
        let clip = TimelineClip(
            id: "clip-1",
            mediaAssetId: "asset-1",
            trackId: "track-1",
            type: .video,
            startTime: 0,
            duration: 5_000_000,
            sourceIn: 1_000_000,
            sourceOut: 6_000_000
        )
        let config = ClipThumbnailService.configFromClip(
            clip,
            clipPixelWidth: 300,
            trackHeight: 64
        )
        #expect(config.assetId == "asset-1")
        #expect(config.sourceIn == 1_000_000)
        #expect(config.sourceOut == 6_000_000)
        #expect(config.clipWidthPixels == 300)
        #expect(config.thumbnailHeight == 64)
    }

    @Test("configFromClip uses clip ID when no mediaAssetId")
    func configFromClipNoAssetId() {
        let clip = TimelineClip(
            id: "clip-1",
            trackId: "track-1",
            type: .video,
            startTime: 0,
            duration: 5_000_000
        )
        let config = ClipThumbnailService.configFromClip(
            clip,
            clipPixelWidth: 300
        )
        #expect(config.assetId == "clip-1")
    }

    // MARK: - Cache Operations

    @Test("getThumbnail returns nil for uncached entry")
    func getCacheEmpty() async {
        let service = ClipThumbnailService()
        let result = await service.getThumbnail(assetId: "a", timeMicros: 0, width: 80)
        #expect(result == nil)
    }

    @Test("storeThumbnail and retrieve")
    func storeAndRetrieve() async {
        let service = ClipThumbnailService(maxCacheSize: 10)
        let key = ThumbnailKey(assetId: "a", timeMicros: 1000, width: 80)

        // Create a tiny 1x1 CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            Issue.record("Failed to create test image")
            return
        }

        await service.storeThumbnail(image, key: key)
        let result = await service.getThumbnail(assetId: "a", timeMicros: 1000, width: 80)
        #expect(result != nil)
    }

    @Test("cache evicts oldest entries at capacity")
    func cacheEviction() async {
        let service = ClipThumbnailService(maxCacheSize: 2)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            return
        }

        // Fill cache to capacity
        let key1 = ThumbnailKey(assetId: "a", timeMicros: 1, width: 80)
        let key2 = ThumbnailKey(assetId: "a", timeMicros: 2, width: 80)
        let key3 = ThumbnailKey(assetId: "a", timeMicros: 3, width: 80)

        await service.storeThumbnail(image, key: key1)
        await service.storeThumbnail(image, key: key2)
        // This should evict key1
        await service.storeThumbnail(image, key: key3)

        let result1 = await service.getThumbnail(assetId: "a", timeMicros: 1, width: 80)
        let result3 = await service.getThumbnail(assetId: "a", timeMicros: 3, width: 80)
        #expect(result1 == nil)
        #expect(result3 != nil)
    }

    @Test("clearAsset removes only that asset's entries")
    func clearAsset() async {
        let service = ClipThumbnailService()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            return
        }

        await service.storeThumbnail(image, key: ThumbnailKey(assetId: "a", timeMicros: 1, width: 80))
        await service.storeThumbnail(image, key: ThumbnailKey(assetId: "b", timeMicros: 1, width: 80))

        await service.clearAsset("a")

        let resultA = await service.getThumbnail(assetId: "a", timeMicros: 1, width: 80)
        let resultB = await service.getThumbnail(assetId: "b", timeMicros: 1, width: 80)
        #expect(resultA == nil)
        #expect(resultB != nil)
    }

    // MARK: - Pause/Resume

    @Test("pauseLoading and resumeLoading toggle state")
    func pauseResume() async {
        let service = ClipThumbnailService()
        await service.pauseLoading()
        await service.resumeLoading()
        // No assertion needed - just verifying no crash
    }
}
