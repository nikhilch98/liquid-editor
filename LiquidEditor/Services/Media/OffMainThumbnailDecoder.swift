// OffMainThumbnailDecoder.swift
// LiquidEditor
//
// PP12-2: Off-main thumbnail decode + LRU.
//
// Decodes thumbnails for local image URLs entirely off the main
// actor using ImageIO's `CGImageSourceCreateThumbnailAtIndex`.
// Results are cached in an actor-isolated LRU keyed by (URL, size)
// so that the Library grid and project-card tiles can scroll
// without repeating decode work.
//
// Decode work itself is scheduled on a detached low-QoS task to
// guarantee the caller's actor is never blocked by IO or CPU cost.
//
// NOTE: For video frames use `ClipThumbnailCache` (AVFoundation
// image generator). This decoder targets still-image sources
// (HEIC/JPEG/PNG thumbnails, cover art, project poster frames).

import CoreGraphics
import Foundation
import ImageIO
import OrderedCollections
import UniformTypeIdentifiers
import os

// MARK: - Cache key

/// Composite key for `OffMainThumbnailDecoder` cache.
///
/// Size is rounded to integer pixels to avoid float-equality
/// hazards; the max-pixel dimension used by ImageIO is derived from
/// the larger of the two axes.
private struct OffMainThumbnailKey: Hashable, Sendable {
    let url: URL
    let widthPx: Int
    let heightPx: Int

    init(url: URL, size: CGSize) {
        self.url = url
        self.widthPx = max(1, Int(size.width.rounded()))
        self.heightPx = max(1, Int(size.height.rounded()))
    }

    /// The largest pixel extent — used as `kCGImageSourceThumbnailMaxPixelSize`.
    var maxPixel: Int { max(widthPx, heightPx) }
}

// MARK: - Error

/// Errors thrown by `OffMainThumbnailDecoder.decode`.
enum OffMainThumbnailDecoderError: Error, LocalizedError, Sendable {
    case cannotCreateImageSource(URL)
    case decodeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .cannotCreateImageSource(let url):
            "Could not create image source for \(url.lastPathComponent)"
        case .decodeFailed(let url):
            "Could not decode thumbnail for \(url.lastPathComponent)"
        }
    }
}

// MARK: - Decoder

/// Actor-isolated LRU thumbnail decoder for still-image sources.
///
/// ## Usage
///
/// ```swift
/// let decoder = OffMainThumbnailDecoder()
/// let image = try await decoder.decode(
///     url: assetURL,
///     size: CGSize(width: 240, height: 240)
/// )
/// ```
///
/// ## Thread Safety
///
/// All cache access is serialized on the actor. The underlying
/// `CGImageSource` + `CGImageSourceCreateThumbnailAtIndex` decode
/// is dispatched to a detached task with `.utility` QoS so neither
/// the actor nor the main thread is blocked during decode.
actor OffMainThumbnailDecoder {

    // MARK: - Configuration

    /// Maximum number of cached thumbnails. On overflow the
    /// least-recently-used entry is evicted.
    let maxEntries: Int

    // MARK: - State

    /// LRU-ordered cache. Most-recently-used entries live at the end;
    /// `cache.first` is the LRU victim.
    private var cache: OrderedDictionary<OffMainThumbnailKey, CGImage> = [:]

    // MARK: - Logger

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "OffMainThumbnailDecoder"
    )

    // MARK: - Init

    /// Creates a thumbnail decoder.
    ///
    /// - Parameter maxEntries: Maximum cache entries before LRU
    ///   eviction. Defaults to 200.
    init(maxEntries: Int = 200) {
        self.maxEntries = max(1, maxEntries)
    }

    // MARK: - API

    /// Decode a thumbnail for a local image URL.
    ///
    /// - Parameters:
    ///   - url: File URL pointing at a still-image asset supported
    ///     by ImageIO (HEIC, JPEG, PNG, TIFF, etc.).
    ///   - size: Desired thumbnail size in pixels. The longer axis
    ///     is used as `kCGImageSourceThumbnailMaxPixelSize`;
    ///     ImageIO preserves aspect ratio.
    /// - Returns: Decoded `CGImage`. Cached for subsequent calls.
    /// - Throws: `OffMainThumbnailDecoderError` when the source
    ///   cannot be opened or the thumbnail cannot be produced.
    func decode(url: URL, size: CGSize) async throws -> CGImage {
        let key = OffMainThumbnailKey(url: url, size: size)

        // Cache hit — touch LRU position and return.
        if let cached = cache.removeValue(forKey: key) {
            cache[key] = cached
            return cached
        }

        // Capture sendable snapshot for off-actor work.
        let sendableURL = url
        let maxPixel = key.maxPixel

        // Decode off-actor on a detached task with utility QoS.
        let decoded: CGImage = try await Task.detached(priority: .utility) {
            try Self.performDecode(url: sendableURL, maxPixel: maxPixel)
        }.value

        insert(key: key, image: decoded)
        return decoded
    }

    /// Drop all cached entries.
    func clear() {
        cache.removeAll()
    }

    /// Remove all entries for a specific URL. Call when an asset
    /// changes on disk.
    func invalidate(url: URL) {
        let keys = cache.keys.filter { $0.url == url }
        for key in keys { cache.removeValue(forKey: key) }
    }

    /// Current entry count.
    var count: Int { cache.count }

    // MARK: - Eviction

    /// Insert, evicting the LRU victim if over capacity.
    private func insert(key: OffMainThumbnailKey, image: CGImage) {
        cache[key] = image
        while cache.count > maxEntries {
            guard !cache.isEmpty else { break }
            cache.removeFirst()
        }
    }

    // MARK: - Off-actor decode

    /// ImageIO decode. Runs on the detached task so it never blocks
    /// the actor or the main thread.
    ///
    /// Uses `kCGImageSourceCreateThumbnailFromImageAlways` so the
    /// returned image is always downsized from the full image data,
    /// not read from an embedded (possibly tiny) thumbnail tag.
    private static func performDecode(url: URL, maxPixel: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            throw OffMainThumbnailDecoderError.cannotCreateImageSource(url)
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary
        ) else {
            throw OffMainThumbnailDecoderError.decodeFailed(url)
        }
        return image
    }
}
