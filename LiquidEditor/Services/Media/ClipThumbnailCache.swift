// ClipThumbnailCache.swift
// LiquidEditor
//
// PP12-14: Actor-isolated thumbnail cache for timeline clip preview
// frames.
//
// Each entry is keyed by `(clipID, time, size)` — the same clip at
// the same playhead position at the same pixel size deduplicates.
// `AVAssetImageGenerator` is used with `requestedTimeToleranceBefore`
// = `.zero` and `requestedTimeToleranceAfter` = `.zero` so the
// returned frame is exact (no snapping to the nearest keyframe —
// critical for scrubbing UX where adjacent thumbnails must land on
// the right time).
//
// Eviction is a simple LRU at 200 entries. The `OrderedDictionary`
// from swift-collections gives us O(1) move-to-end and O(1)
// remove-first, which is the two operations an LRU actually needs.

import AVFoundation
import CoreGraphics
import Foundation
import OrderedCollections
import os

// MARK: - ClipThumbnailCacheKey

/// Composite cache key for `ClipThumbnailCache`.
///
/// Two thumbnails are equal if they describe the same clip, at the
/// same microsecond, rendered at the same pixel size. `Size` is
/// rounded to integer pixels to avoid float-equality hazards.
private struct ClipThumbnailCacheKey: Hashable, Sendable {
    let clipID: UUID
    let timeMicros: TimeMicros
    let widthPx: Int
    let heightPx: Int

    init(clipID: UUID, time: TimeMicros, size: CGSize) {
        self.clipID = clipID
        self.timeMicros = time
        self.widthPx = max(1, Int(size.width.rounded()))
        self.heightPx = max(1, Int(size.height.rounded()))
    }
}

// MARK: - ClipThumbnailCacheError

/// Errors thrown by `ClipThumbnailCache.thumbnail`.
enum ClipThumbnailCacheError: Error, LocalizedError, Sendable {
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .generationFailed(let reason):
            "Failed to generate thumbnail: \(reason)"
        }
    }
}

// MARK: - ClipThumbnailCache

/// Actor-isolated LRU cache of clip preview thumbnails.
///
/// Used by the timeline clip strip to render per-clip filmstrips,
/// by the Library grid for scrub previews, and by the precision
/// trim sheet for the playhead HUD.
///
/// ## Usage
///
/// ```swift
/// let cache = ClipThumbnailCache()
/// let image = try await cache.thumbnail(
///     for: clip.id,
///     at: 1_500_000,       // 1.5s in microseconds
///     asset: clip.asset,
///     size: CGSize(width: 60, height: 60)
///  )
/// ```
///
/// ## Thread Safety
///
/// All state is actor-isolated. `AVAssetImageGenerator` calls are
/// wrapped in `withCheckedThrowingContinuation` — image generation
/// happens on AVFoundation's internal background queue, so the
/// actor itself is never blocked by decode work.
actor ClipThumbnailCache {

    // MARK: - Configuration

    /// Maximum number of cached thumbnails. On overflow the
    /// least-recently-used entry is evicted.
    let maxEntries: Int

    // MARK: - State

    /// LRU-ordered cache. Most-recently-used entries live at the
    /// end; the `first` key is the LRU victim.
    private var cache: OrderedDictionary<ClipThumbnailCacheKey, CGImage> = [:]

    /// Per-asset image generators. Creating one is cheap but not
    /// free — cache them to avoid repeat construction for
    /// successive scrub frames on the same clip.
    private var generators: [ObjectIdentifier: AVAssetImageGenerator] = [:]

    // MARK: - Logger

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "ClipThumbnailCache"
    )

    // MARK: - Init

    /// Creates a thumbnail cache.
    ///
    /// - Parameter maxEntries: Maximum entries before LRU eviction
    ///   kicks in. Defaults to 200, which is roughly 30MB at
    ///   60x60 RGBA.
    init(maxEntries: Int = 200) {
        self.maxEntries = max(1, maxEntries)
    }

    // MARK: - API

    /// Fetch a thumbnail for a clip at a given time, generating
    /// it from the asset if necessary.
    ///
    /// - Parameters:
    ///   - clipID: Stable identifier for the clip. Used as part of
    ///     the cache key so that two different clips pointing at
    ///     the same asset (e.g. one copy + one original) do not
    ///     share entries.
    ///   - time: Target time in microseconds.
    ///   - asset: The `AVAsset` to decode from.
    ///   - size: Desired thumbnail size in pixels. The returned
    ///     image may be slightly smaller in one axis if the asset's
    ///     native aspect differs — AVFoundation preserves aspect.
    /// - Returns: A `CGImage` for the requested frame.
    /// - Throws: `ClipThumbnailCacheError.generationFailed` if
    ///   `AVAssetImageGenerator` fails.
    func thumbnail(
        for clipID: UUID,
        at time: TimeMicros,
        asset: AVAsset,
        size: CGSize
    ) async throws -> CGImage {
        let key = ClipThumbnailCacheKey(clipID: clipID, time: time, size: size)

        // Cache hit — move to end (LRU touch) and return.
        if let cached = cache.removeValue(forKey: key) {
            cache[key] = cached
            return cached
        }

        nonisolated(unsafe) let generator = generator(for: asset, size: size)
        let cmTime = CMTime(
            value: time,
            timescale: 1_000_000
        )

        do {
            let (image, _) = try await generator.image(at: cmTime)
            insert(key: key, image: image)
            return image
        } catch {
            logger.error("Thumbnail generation failed: \(error.localizedDescription)")
            throw ClipThumbnailCacheError.generationFailed(
                error.localizedDescription
            )
        }
    }

    /// Drop all entries, release all image generators.
    func clear() {
        cache.removeAll()
        generators.removeAll()
    }

    /// Remove all thumbnails for a specific clip. Call when a clip
    /// is deleted or its underlying asset changes.
    func invalidate(clipID: UUID) {
        let keysToRemove = cache.keys.filter { $0.clipID == clipID }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }

    /// Current entry count.
    var count: Int { cache.count }

    // MARK: - Generator management

    /// Returns a cached `AVAssetImageGenerator` for the asset, or
    /// creates one and stashes it. All generators share the same
    /// zero-tolerance + prefer-natural-transform + non-scaling
    /// configuration.
    private func generator(
        for asset: AVAsset,
        size: CGSize
    ) -> AVAssetImageGenerator {
        let key = ObjectIdentifier(asset)
        if let existing = generators[key] {
            existing.maximumSize = size
            return existing
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = size
        generators[key] = generator
        return generator
    }

    /// Insert a new entry, evicting the LRU victim if needed.
    private func insert(key: ClipThumbnailCacheKey, image: CGImage) {
        cache[key] = image
        while cache.count > maxEntries {
            guard !cache.isEmpty else { break }
            cache.removeFirst()
        }
    }

}
