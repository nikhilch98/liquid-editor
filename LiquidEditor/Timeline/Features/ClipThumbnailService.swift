// ClipThumbnailService.swift
// LiquidEditor
//
// Clip thumbnail service for generating filmstrip thumbnails.
// Generates thumbnail images for video clips at evenly-spaced intervals.
// Adapts thumbnail count based on zoom level and clip width.
// Combines service and rendering logic (painter).
//
//         and lib/timeline/features/clip_thumbnail_painter.dart

import Foundation
import CoreGraphics
import AVFoundation
import UIKit
import os

// MARK: - ClipThumbnailConfig

/// Configuration for thumbnail generation for a clip.
struct ClipThumbnailConfig: Equatable, Hashable, Sendable {
    /// Maximum number of thumbnails to generate for a single clip (prevents memory issues).
    static let maxThumbnailCount = 50

    /// Media asset ID.
    let assetId: String

    /// Source in point (microseconds).
    let sourceIn: TimeMicros

    /// Source out point (microseconds).
    let sourceOut: TimeMicros

    /// Clip rectangle width in pixels.
    let clipWidthPixels: Double

    /// Target thumbnail width in pixels.
    let thumbnailWidth: Int

    /// Target thumbnail height in pixels.
    let thumbnailHeight: Int

    init(
        assetId: String,
        sourceIn: TimeMicros,
        sourceOut: TimeMicros,
        clipWidthPixels: Double,
        thumbnailWidth: Int = 80,
        thumbnailHeight: Int = 60
    ) {
        self.assetId = assetId
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.clipWidthPixels = clipWidthPixels
        self.thumbnailWidth = thumbnailWidth
        self.thumbnailHeight = thumbnailHeight
    }

    /// Compute the number of thumbnails to display.
    /// Based on clip pixel width divided by thumbnail width,
    /// clamped to a reasonable range.
    var thumbnailCount: Int {
        guard clipWidthPixels > 0 else { return 0 }
        let count = Int(ceil(clipWidthPixels / Double(thumbnailWidth)))
        return min(max(count, 1), Self.maxThumbnailCount)
    }

    /// Source duration in microseconds.
    var sourceDuration: TimeMicros { sourceOut - sourceIn }

    /// Compute the source times for each thumbnail.
    var thumbnailTimes: [TimeMicros] {
        let count = thumbnailCount
        guard count > 0, sourceDuration > 0 else { return [] }

        let step = Double(sourceDuration) / Double(count)
        return (0..<count).map { i in
            // Place thumbnail at the center of each segment.
            let time = Double(sourceIn) + (step * Double(i) + step / 2.0)
            return min(max(TimeMicros(time.rounded()), sourceIn), sourceOut)
        }
    }
}

// MARK: - ResolvedThumbnail

/// A resolved thumbnail for rendering.
struct ResolvedThumbnail: Sendable {
    /// The thumbnail image (nil if not yet loaded).
    let image: CGImage?

    /// X offset in clip-local coordinates.
    let x: Double

    /// Width of the thumbnail slot.
    let width: Double

    /// Source time this thumbnail represents.
    let sourceTimeMicros: TimeMicros

    /// Whether this thumbnail is still loading.
    let isLoading: Bool

    init(
        image: CGImage? = nil,
        x: Double,
        width: Double,
        sourceTimeMicros: TimeMicros,
        isLoading: Bool = false
    ) {
        self.image = image
        self.x = x
        self.width = width
        self.sourceTimeMicros = sourceTimeMicros
        self.isLoading = isLoading
    }
}

// MARK: - ThumbnailKey

/// Cache key for a thumbnail.
struct ThumbnailKey: Hashable, Sendable {
    let assetId: String
    let timeMicros: TimeMicros
    let width: Int
}

// MARK: - ClipThumbnailService

/// Service for generating and managing clip filmstrip thumbnails.
///
/// Uses AVAssetImageGenerator for native thumbnail extraction.
/// Manages an LRU cache of generated CGImages.
actor ClipThumbnailService {

    private static let logger = Logger(subsystem: "LiquidEditor", category: "ClipThumbnailService")

    /// Retina scale multiplier for thumbnail generation (2x for sharp display on retina screens).
    static let retinaScale = 2

    /// Time tolerance for AVAssetImageGenerator in frames (1/30s allows ±1 frame at 30fps).
    static let timeTolerance = CMTime(value: 1, timescale: 30)

    /// Cache of generated thumbnails.
    private var cache: [ThumbnailKey: CGImage] = [:]

    /// Maximum cache size (number of thumbnails).
    private let maxCacheSize: Int

    /// Whether loading is paused (during fast scroll/zoom).
    private var isPaused: Bool = false

    /// Active generation tasks.
    private var activeGenerations: Set<ThumbnailKey> = []

    /// LRU access order (most recent last).
    private var accessOrder: [ThumbnailKey] = []

    init(maxCacheSize: Int = 500) {
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Cache Access

    /// Get a cached thumbnail, or nil if not available.
    func getThumbnail(assetId: String, timeMicros: TimeMicros, width: Int) -> CGImage? {
        let key = ThumbnailKey(assetId: assetId, timeMicros: timeMicros, width: width)
        if let image = cache[key] {
            // Update access order for LRU
            updateAccessOrder(key)
            return image
        }
        return nil
    }

    /// Store a thumbnail in the cache.
    func storeThumbnail(_ image: CGImage, key: ThumbnailKey) {
        // Evict if at capacity
        while cache.count >= maxCacheSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }

        cache[key] = image
        updateAccessOrder(key)
    }

    /// Get resolved thumbnails for a clip configuration.
    func getThumbnailsForClip(_ config: ClipThumbnailConfig) -> [ResolvedThumbnail] {
        let count = config.thumbnailCount
        guard count > 0 else { return [] }

        let times = config.thumbnailTimes
        let slotWidth = config.clipWidthPixels / Double(count)

        return times.enumerated().map { (i, time) in
            let image = getThumbnail(
                assetId: config.assetId,
                timeMicros: time,
                width: config.thumbnailWidth
            )

            return ResolvedThumbnail(
                image: image,
                x: Double(i) * slotWidth,
                width: slotWidth,
                sourceTimeMicros: time,
                isLoading: image == nil
            )
        }
    }

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail from an AVAsset.
    ///
    /// - Parameters:
    ///   - asset: The AVAsset to generate from.
    ///   - timeMicros: The time in microseconds.
    ///   - width: The desired width.
    ///   - assetId: The asset identifier for caching.
    /// - Returns: The generated CGImage, or nil.
    func generateThumbnail(
        from asset: AVAsset,
        at timeMicros: TimeMicros,
        width: Int,
        assetId: String
    ) async -> CGImage? {
        let key = ThumbnailKey(assetId: assetId, timeMicros: timeMicros, width: width)

        // Check cache first
        if let cached = cache[key] {
            updateAccessOrder(key)
            return cached
        }

        // Skip if already generating or paused
        guard !isPaused, !activeGenerations.contains(key) else { return nil }

        activeGenerations.insert(key)
        defer { activeGenerations.remove(key) }

        nonisolated(unsafe) let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width * Self.retinaScale, height: 0)
        generator.requestedTimeToleranceBefore = Self.timeTolerance
        generator.requestedTimeToleranceAfter = Self.timeTolerance

        let cmTime = CMTime(
            value: CMTimeValue(timeMicros),
            timescale: 1_000_000
        )

        do {
            let (image, _) = try await generator.image(at: cmTime)
            storeThumbnail(image, key: key)
            return image
        } catch {
            Self.logger.error("Failed to generate thumbnail for asset \(assetId) at time \(timeMicros): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Loading Control

    /// Pause thumbnail loading during fast scrolling/zooming.
    func pauseLoading() {
        isPaused = true
    }

    /// Resume thumbnail loading after scroll/zoom settles.
    func resumeLoading() {
        isPaused = false
    }

    /// Clear thumbnails for a specific asset.
    func clearAsset(_ assetId: String) {
        let keysToRemove = cache.keys.filter { $0.assetId == assetId }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }

    /// Clear all cached thumbnails.
    func clearAll() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    // MARK: - Static Helpers

    /// Create a thumbnail config from a TimelineClip.
    ///
    /// - Parameters:
    ///   - clip: The timeline clip.
    ///   - clipPixelWidth: Width of the clip in pixels at current zoom.
    ///   - trackHeight: Height of the track for thumbnail sizing.
    static func configFromClip(
        _ clip: TimelineClip,
        clipPixelWidth: Double,
        trackHeight: Double = 64
    ) -> ClipThumbnailConfig {
        ClipThumbnailConfig(
            assetId: clip.mediaAssetId ?? clip.id,
            sourceIn: clip.sourceIn,
            sourceOut: clip.sourceOut,
            clipWidthPixels: clipPixelWidth,
            thumbnailWidth: thumbnailWidthForZoom(clipPixelWidth, trackHeight: trackHeight),
            thumbnailHeight: Int(trackHeight)
        )
    }

    /// Thumbnail aspect ratio (width/height), defaults to 16:9 widescreen.
    static let thumbnailAspectRatio = 16.0 / 9.0

    /// Minimum thumbnail width in pixels (prevents pixelation at high zoom).
    static let minThumbnailWidth = 40

    /// Maximum thumbnail width in pixels (prevents excessive memory use at low zoom).
    static let maxThumbnailWidth = 120

    /// Compute adaptive thumbnail width based on zoom level.
    private static func thumbnailWidthForZoom(
        _ clipPixelWidth: Double,
        trackHeight: Double
    ) -> Int {
        // Use aspect ratio close to 16:9 but adapt to track height.
        let idealWidth = Int((trackHeight * thumbnailAspectRatio).rounded())
        // Clamp between min and max to balance quality and memory.
        return min(max(idealWidth, minThumbnailWidth), maxThumbnailWidth)
    }

    // MARK: - Private

    private func updateAccessOrder(_ key: ThumbnailKey) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}

// MARK: - ClipThumbnailRenderer

/// Renders filmstrip thumbnails in a CoreGraphics context.
///
/// Draws resolved thumbnails from `ClipThumbnailService` in their
/// designated slots. Shows subtle gradient placeholders for loading
/// thumbnails.
enum ClipThumbnailRenderer {

    /// Draw filmstrip thumbnails into a CGContext.
    ///
    /// - Parameters:
    ///   - context: The graphics context to draw into.
    ///   - thumbnails: Resolved thumbnails to render.
    ///   - clipRect: Clip rectangle for clipping bounds.
    ///   - cornerRadius: Corner radius for the clip shape.
    ///   - opacity: Opacity for the thumbnails.
    ///   - showOverlay: Whether to show a darkened overlay (selected state).
    ///   - overlayColor: Overlay color when `showOverlay` is true.
    static func draw(
        in context: CGContext,
        thumbnails: [ResolvedThumbnail],
        clipRect: CGRect,
        cornerRadius: Double = 6.0,
        opacity: Double = 1.0,
        showOverlay: Bool = false,
        overlayColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.25)
    ) {
        guard !thumbnails.isEmpty else { return }

        context.saveGState()

        // Clip to rounded rectangle
        let path = CGPath(
            roundedRect: clipRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.clip()

        for thumbnail in thumbnails {
            let slotRect = CGRect(
                x: clipRect.origin.x + thumbnail.x,
                y: clipRect.origin.y,
                width: thumbnail.width,
                height: clipRect.height
            )

            if let image = thumbnail.image {
                drawThumbnail(context, image: image, slotRect: slotRect, opacity: opacity)
            } else {
                drawPlaceholder(context, slotRect: slotRect)
            }
        }

        // Draw overlay for selection state.
        if showOverlay {
            context.setFillColor(overlayColor)
            context.fill(clipRect)
        }

        context.restoreGState()
    }

    /// Paint a loaded thumbnail image, scaling to fill the slot.
    private static func drawThumbnail(
        _ context: CGContext,
        image: CGImage,
        slotRect: CGRect,
        opacity: Double
    ) {
        context.saveGState()
        context.setAlpha(opacity)

        // Scale to fill: maintain aspect ratio, covering the slot.
        let imageAspect = Double(image.width) / Double(image.height)
        let slotAspect = slotRect.width / slotRect.height

        let dstRect: CGRect
        if imageAspect > slotAspect {
            // Image is wider - crop sides.
            let scale = slotRect.height / Double(image.height)
            let scaledWidth = Double(image.width) * scale
            let xOffset = (scaledWidth - slotRect.width) / 2
            dstRect = CGRect(
                x: slotRect.origin.x - xOffset,
                y: slotRect.origin.y,
                width: scaledWidth,
                height: slotRect.height
            )
        } else {
            // Image is taller - crop top/bottom.
            let scale = slotRect.width / Double(image.width)
            let scaledHeight = Double(image.height) * scale
            let yOffset = (scaledHeight - slotRect.height) / 2
            dstRect = CGRect(
                x: slotRect.origin.x,
                y: slotRect.origin.y - yOffset,
                width: slotRect.width,
                height: scaledHeight
            )
        }

        // Clip to the slot to handle overflow from aspect fill.
        context.clip(to: slotRect)
        context.draw(image, in: dstRect)
        context.restoreGState()

        // Draw thin separator between thumbnails.
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.125))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: slotRect.maxX, y: slotRect.minY))
        context.addLine(to: CGPoint(x: slotRect.maxX, y: slotRect.maxY))
        context.strokePath()
        context.restoreGState()
    }

    /// Paint a loading placeholder for thumbnails not yet available.
    private static func drawPlaceholder(
        _ context: CGContext,
        slotRect: CGRect
    ) {
        // Subtle gradient placeholder.
        context.saveGState()
        context.clip(to: slotRect)

        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.08),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.03),
        ] as CFArray

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: slotRect.origin,
                end: CGPoint(x: slotRect.maxX, y: slotRect.maxY),
                options: []
            )
        }

        context.restoreGState()

        // Draw thin separator.
        context.saveGState()
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.125))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: slotRect.maxX, y: slotRect.minY))
        context.addLine(to: CGPoint(x: slotRect.maxX, y: slotRect.maxY))
        context.strokePath()
        context.restoreGState()
    }
}
