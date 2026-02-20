// GifFrameCache.swift
// LiquidEditor
//
// GIF sticker frame LRU cache with per-asset eviction.
//
// Decodes GIF files into individual CGImage frames and caches them
// by (assetId, frameIndex). Provides frame lookup by animation
// progress (0.0-1.0) for smooth animated sticker rendering.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - GifFrame

/// A single decoded frame from a GIF animation.
struct GifFrame: Sendable {
    /// The decoded frame image.
    let image: CGImage

    /// Duration of this frame in milliseconds.
    let durationMs: Int

    /// Frame index in the animation (0-based).
    let index: Int

    /// Estimated memory footprint in bytes.
    var estimatedMemory: Int {
        image.width * image.height * 4
    }
}

// MARK: - GifFrameCache

/// Cache of decoded GIF animation frames.
///
/// Decodes GIF files lazily on first access and stores all frames
/// in memory. Supports per-asset LRU eviction and memory pressure handling.
///
/// Thread Safety: `@MainActor` -- frame access and eviction are UI-driven.
@MainActor
final class GifFrameCache {

    // MARK: - Configuration

    /// Maximum number of GIF animations to keep fully decoded.
    let maxAnimations: Int

    /// Maximum total memory in bytes (default ~80 MB for GIF frames).
    let maxMemoryBytes: Int

    // MARK: - State

    /// Decoded frames indexed by asset ID.
    private var frames: [String: [GifFrame]] = [:]

    /// Total frame count per asset.
    private var frameCounts: [String: Int] = [:]

    /// Total duration per asset in milliseconds.
    private var totalDurations: [String: Int] = [:]

    /// Access order for LRU eviction (most recent at end).
    private var accessOrder: [String] = []

    /// Current total memory usage estimate in bytes.
    private(set) var currentMemoryBytes: Int = 0

    // MARK: - Initialization

    init(maxAnimations: Int = 10, maxMemoryBytes: Int = 80 * 1_024 * 1_024) {
        self.maxAnimations = maxAnimations
        self.maxMemoryBytes = maxMemoryBytes
    }

    // MARK: - Queries

    /// Number of cached animations.
    var animationCount: Int { frames.count }

    /// Whether frames are cached for the given asset.
    func hasFrames(_ assetId: String) -> Bool {
        frames[assetId] != nil
    }

    /// Get total frame count for a cached asset.
    func frameCount(_ assetId: String) -> Int? {
        frameCounts[assetId]
    }

    /// Get total animation duration for a cached asset in milliseconds.
    func totalDurationMs(_ assetId: String) -> Int? {
        totalDurations[assetId]
    }

    /// Get a specific frame by index.
    func getFrame(_ assetId: String, frameIndex: Int) -> GifFrame? {
        guard let assetFrames = frames[assetId],
              frameIndex >= 0, frameIndex < assetFrames.count else {
            return nil
        }
        touchAccessOrder(assetId)
        return assetFrames[frameIndex]
    }

    /// Get the frame image for a given animation progress (0.0-1.0).
    ///
    /// Calculates which frame to show based on cumulative frame durations.
    func getFrameAtProgress(_ assetId: String, progress: Double) -> CGImage? {
        guard let assetFrames = frames[assetId], !assetFrames.isEmpty else { return nil }

        touchAccessOrder(assetId)

        let clampedProgress = min(max(progress, 0.0), 1.0)
        let totalDuration = totalDurations[assetId] ?? 1
        let targetMs = Int((clampedProgress * Double(totalDuration)).rounded())

        var accumulatedMs = 0
        for frame in assetFrames {
            accumulatedMs += frame.durationMs
            if accumulatedMs >= targetMs {
                return frame.image
            }
        }

        return assetFrames.last?.image
    }

    // MARK: - Decoding

    /// Decode and cache all frames from a GIF file URL.
    ///
    /// - Parameters:
    ///   - assetId: Unique identifier for this animation.
    ///   - url: File URL to the GIF.
    /// - Returns: Total frame count, or 0 if decoding fails.
    func decodeFromURL(_ assetId: String, url: URL) -> Int {
        if frames[assetId] != nil {
            touchAccessOrder(assetId)
            return frameCounts[assetId] ?? 0
        }

        guard let data = try? Data(contentsOf: url) else { return 0 }
        return decodeData(assetId, data: data)
    }

    /// Decode and cache all frames from raw GIF bytes.
    ///
    /// - Parameters:
    ///   - assetId: Unique identifier for this animation.
    ///   - data: Raw GIF data.
    /// - Returns: Total frame count, or 0 if decoding fails.
    func decodeFromData(_ assetId: String, data: Data) -> Int {
        if frames[assetId] != nil {
            touchAccessOrder(assetId)
            return frameCounts[assetId] ?? 0
        }
        return decodeData(assetId, data: data)
    }

    // MARK: - Eviction

    /// Remove all frames for a specific asset.
    func evict(_ assetId: String) {
        if let assetFrames = frames.removeValue(forKey: assetId) {
            let freedMemory = assetFrames.reduce(0) { $0 + $1.estimatedMemory }
            currentMemoryBytes -= freedMemory
        }
        frameCounts.removeValue(forKey: assetId)
        totalDurations.removeValue(forKey: assetId)
        accessOrder.removeAll { $0 == assetId }
    }

    /// Clear all cached GIF frames.
    func clear() {
        frames.removeAll()
        frameCounts.removeAll()
        totalDurations.removeAll()
        accessOrder.removeAll()
        currentMemoryBytes = 0
    }

    /// Handle memory pressure by evicting half of cached animations.
    func handleMemoryPressure() {
        let targetCount = frames.count / 2
        while frames.count > targetCount, !accessOrder.isEmpty {
            evict(accessOrder.first!)
        }
    }

    // MARK: - Private

    /// Internal: decode GIF data using ImageIO.
    private func decodeData(_ assetId: String, data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return 0 }

        // Evict if needed before decoding
        evictIfNeeded()

        var decodedFrames: [GifFrame] = []
        var totalDuration = 0
        var totalMemory = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            // Get frame duration from properties
            let durationMs = frameDuration(source: source, index: i)
            let effectiveDuration = durationMs > 0 ? durationMs : 20 // Default 20ms for 0-duration frames
            totalDuration += effectiveDuration

            let frameMemory = cgImage.width * cgImage.height * 4
            totalMemory += frameMemory

            decodedFrames.append(GifFrame(
                image: cgImage,
                durationMs: effectiveDuration,
                index: i
            ))
        }

        frames[assetId] = decodedFrames
        frameCounts[assetId] = count
        totalDurations[assetId] = totalDuration
        currentMemoryBytes += totalMemory
        touchAccessOrder(assetId)

        return count
    }

    /// Extract frame duration in milliseconds from GIF properties.
    private func frameDuration(source: CGImageSource, index: Int) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProps = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0
        }

        // Try unclampedDelayTime first, then delayTime
        let delay: Double
        if let unclamped = gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            delay = unclamped
        } else if let clamped = gifProps[kCGImagePropertyGIFDelayTime] as? Double {
            delay = clamped
        } else {
            return 0
        }

        return Int((delay * 1000).rounded())
    }

    /// Update access order for LRU tracking.
    private func touchAccessOrder(_ assetId: String) {
        accessOrder.removeAll { $0 == assetId }
        accessOrder.append(assetId)
    }

    /// Evict least-recently-used animations if at capacity.
    private func evictIfNeeded() {
        while (frames.count >= maxAnimations || currentMemoryBytes > maxMemoryBytes),
              !accessOrder.isEmpty {
            evict(accessOrder.first!)
        }
    }
}
