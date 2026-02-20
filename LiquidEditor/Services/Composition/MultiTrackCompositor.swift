// MultiTrackCompositor.swift
// LiquidEditor
//
// AVVideoCompositing implementation for multi-track compositing.
//
// Features:
// - Custom AVVideoCompositing for multi-track rendering
// - Picture-in-Picture layout with normalized positioning
// - Split screen with configurable cell templates
// - Chroma key compositing (green/blue screen via CIColorCube)
// - 17+ blend modes via CIFilter
// - Per-track opacity and spatial transforms
// - GPU-accelerated rendering with CIContext (Metal backend)
// - Thread-safe concurrent render queue
//

import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "MultiTrackCompositor")

// MARK: - MultiTrackCompositor

/// Custom compositor implementing `AVVideoCompositing` for multi-track compositing.
///
/// For each output frame:
/// 1. Requests source pixel buffers from all visible tracks.
/// 2. Applies per-track spatial transforms (full-frame, PiP, split screen, freeform).
/// 3. Applies chroma key if configured (via ``ChromaKeyCIFilter``).
/// 4. Composites layers bottom-to-top with blend modes and opacity.
/// 5. Renders composited CIImage to output CVPixelBuffer.
///
/// Thread Safety:
/// - `startRequest(_:)` dispatches to a concurrent render queue for parallel frame rendering.
/// - `CIContext` is thread-safe and shared across all render requests.
/// - Dynamic track config updates are protected by `configLock`.
///
/// Integration:
/// - Used as `customVideoCompositorClass` on AVMutableVideoComposition.
/// - Receives ``MultiTrackInstruction`` with per-track configs and track ordering.
/// - Works with both preview playback (AVPlayerItem) and export (AVAssetExportSession).
final class MultiTrackCompositor: NSObject, AVVideoCompositing {

    // MARK: - AVVideoCompositing Protocol Properties

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    // MARK: - Private Properties

    /// GPU-accelerated CIContext for rendering (Metal backend).
    private let ciContext: CIContext = {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .useSoftwareRenderer: false,
            .highQualityDownsample: true,
        ]
        return CIContext(options: options)
    }()

    /// Chroma key filter for green/blue screen removal.
    private let chromaKeyFilter = ChromaKeyCIFilter()

    /// Concurrent rendering queue (userInteractive QoS for frame deadline).
    private let renderQueue = DispatchQueue(
        label: "com.liquideditor.compositor.render",
        qos: .userInteractive,
        attributes: .concurrent
    )

    /// Dynamic track configurations (updated from UI at runtime).
    /// Protected by `configLock`; `nonisolated(unsafe)` suppresses Sendable warning.
    private nonisolated(unsafe) var dynamicTrackConfigs: [String: TrackCompositeConfig]?

    /// Lock protecting `dynamicTrackConfigs`.
    private let configLock = NSLock()

    // MARK: - AVVideoCompositing Protocol Methods

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // No-op. Render context is accessed directly from each request via
        // AVAsynchronousVideoCompositionRequest.renderContext, which is
        // inherently thread-safe.
    }

    func startRequest(_ asyncRequest: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self else {
                asyncRequest.finish(
                    with: Self.makeError(code: -1, message: "Compositor deallocated")
                )
                return
            }
            self.processRequest(asyncRequest)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Rendering tasks on the concurrent queue complete naturally.
        // AVFoundation handles cancellation by ignoring late-delivered frames.
    }

    // MARK: - Dynamic Configuration

    /// Update track configurations at runtime (e.g., from user dragging PiP).
    ///
    /// The next rendered frame will use these configs instead of the
    /// instruction's built-in configs.
    ///
    /// - Parameter configs: Per-track composite configurations keyed by track ID.
    func updateTrackConfigs(_ configs: [String: TrackCompositeConfig]) {
        configLock.lock()
        dynamicTrackConfigs = configs
        configLock.unlock()
    }

    /// Clear dynamic track configs (revert to instruction-based configs).
    func clearDynamicConfigs() {
        configLock.lock()
        dynamicTrackConfigs = nil
        configLock.unlock()
    }

    // MARK: - Frame Processing

    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction
            as? MultiTrackInstruction
        else {
            request.finish(
                with: Self.makeError(code: -1, message: "Invalid instruction type")
            )
            return
        }

        let outputSize = request.renderContext.size
        let outputExtent = CGRect(origin: .zero, size: outputSize)

        // Start with opaque black background
        var composited = CIImage(color: .black).cropped(to: outputExtent)

        // Use dynamic configs if available, else fall back to instruction configs
        let effectiveConfigs: [String: TrackCompositeConfig]
        configLock.lock()
        effectiveConfigs = dynamicTrackConfigs ?? instruction.trackConfigs
        configLock.unlock()

        // Composite layers bottom-to-top (track order)
        for trackId in instruction.trackOrder {
            guard let config = effectiveConfigs[trackId],
                  let compositionTrackID = instruction.compositionTrackIDs[trackId],
                  let sourceBuffer = request.sourceFrame(byTrackID: compositionTrackID)
            else {
                continue
            }

            var layerImage = CIImage(cvPixelBuffer: sourceBuffer)

            // Step 1: Spatial transform based on layout mode
            layerImage = applySpatialTransform(
                image: layerImage,
                config: config,
                outputSize: outputSize
            )

            // Step 2: Chroma key if configured
            if let chromaConfig = config.chromaKey, chromaConfig.isEnabled {
                layerImage = chromaKeyFilter.apply(
                    source: layerImage,
                    config: chromaConfig
                )
            }

            // Step 3: Composite with blend mode and opacity
            composited = compositeWithBlendMode(
                foreground: layerImage,
                background: composited,
                blendMode: config.blendMode,
                opacity: config.opacity,
                outputExtent: outputExtent
            )
        }

        // Render composited CIImage to output pixel buffer
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(
                with: Self.makeError(code: -2, message: "Failed to create output buffer")
            )
            return
        }

        ciContext.render(composited, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }

    // MARK: - Spatial Transforms

    /// Apply spatial transform for a track based on its layout mode.
    private func applySpatialTransform(
        image: CIImage,
        config: TrackCompositeConfig,
        outputSize: CGSize
    ) -> CIImage {
        switch config.layout {
        case .fullFrame:
            return scaleToFill(image, outputSize: outputSize)

        case .pip:
            if let region = config.pipRegion {
                return applyPipTransform(
                    overlayImage: image,
                    region: region,
                    outputSize: outputSize
                )
            }
            return scaleToFill(image, outputSize: outputSize)

        case .splitScreen:
            if let cellIndex = config.splitScreenCell,
               let template = config.splitScreenTemplate,
               cellIndex < template.cells.count
            {
                return renderSplitScreenCell(
                    sourceImage: image,
                    cell: template.cells[cellIndex],
                    outputSize: outputSize
                )
            }
            return scaleToFill(image, outputSize: outputSize)

        case .freeform:
            return applyFreeformTransform(
                overlayImage: image,
                outputSize: outputSize
            )
        }
    }

    /// Scale image to fill the entire output frame (aspect-fill with center crop).
    private func scaleToFill(_ image: CIImage, outputSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let scaleX = outputSize.width / extent.width
        let scaleY = outputSize.height / extent.height
        let scale = max(scaleX, scaleY)

        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let offsetX = (outputSize.width - scaledWidth) / 2
        let offsetY = (outputSize.height - scaledHeight) / 2

        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: offsetX / scale, y: offsetY / scale)

        return image.transformed(by: transform)
            .cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    /// Apply PiP transform: position overlay in a normalized sub-region.
    ///
    /// The region uses normalized coordinates (0.0-1.0) relative to the output frame.
    /// CIImage coordinate system is bottom-up, so Y is flipped.
    private func applyPipTransform(
        overlayImage: CIImage,
        region: NormalizedRect,
        outputSize: CGSize
    ) -> CIImage {
        let targetRect = region.toRect(outputSize: outputSize)
        let extent = overlayImage.extent
        guard extent.width > 0, extent.height > 0 else { return overlayImage }

        // Scale overlay to fit target rect (aspect-fit to maintain ratio)
        let scaleX = targetRect.width / extent.width
        let scaleY = targetRect.height / extent.height
        let scale = min(scaleX, scaleY)

        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale

        // CIImage is bottom-up: convert top-down Y to bottom-up Y
        let offsetX = targetRect.midX - scaledWidth / 2
        let ciY = outputSize.height - targetRect.midY - scaledHeight / 2

        var transform = CGAffineTransform(scaleX: scale, y: scale)
        transform = transform.translatedBy(x: offsetX / scale, y: ciY / scale)

        return overlayImage.transformed(by: transform)
    }

    /// Render a source image into a split-screen cell.
    ///
    /// Scales the image to fill the cell (aspect-fill with center crop).
    private func renderSplitScreenCell(
        sourceImage: CIImage,
        cell: NormalizedRect,
        outputSize: CGSize
    ) -> CIImage {
        let cellRect = cell.toRect(outputSize: outputSize)
        let extent = sourceImage.extent
        guard extent.width > 0, extent.height > 0 else { return sourceImage }

        // Aspect-fill the cell
        let scaleX = cellRect.width / extent.width
        let scaleY = cellRect.height / extent.height
        let scale = max(scaleX, scaleY)

        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale

        // CIImage is bottom-up
        let ciCellY = outputSize.height - cellRect.origin.y - cellRect.height
        let offsetX = cellRect.origin.x + (cellRect.width - scaledWidth) / 2
        let offsetY = ciCellY + (cellRect.height - scaledHeight) / 2

        var transform = CGAffineTransform(scaleX: scale, y: scale)
        transform = transform.translatedBy(x: offsetX / scale, y: offsetY / scale)

        let positioned = sourceImage.transformed(by: transform)

        // Crop to cell bounds (in CIImage bottom-up coordinates)
        let cropRect = CGRect(
            x: cellRect.origin.x,
            y: ciCellY,
            width: cellRect.width,
            height: cellRect.height
        )
        return positioned.cropped(to: cropRect)
    }

    /// Apply freeform transform (position/scale/rotation from overlay keyframes).
    ///
    /// Currently scales to fill; per-clip transform keyframes will be resolved
    /// by the caller and sent via dynamic config updates.
    private func applyFreeformTransform(
        overlayImage: CIImage,
        outputSize: CGSize
    ) -> CIImage {
        return scaleToFill(overlayImage, outputSize: outputSize)
    }

    // MARK: - Blend Mode Compositing

    /// Composite foreground onto background using the specified blend mode.
    ///
    /// Applies opacity to the foreground before blending. Uses GPU-accelerated
    /// CIFilter operations for all blend modes.
    private func compositeWithBlendMode(
        foreground: CIImage,
        background: CIImage,
        blendMode: CompBlendMode,
        opacity: Double,
        outputExtent: CGRect
    ) -> CIImage {
        // Apply opacity via alpha channel matrix
        var fg = foreground
        if opacity < 0.999 {
            fg = foreground.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
            ])
        }

        let filterName = blendMode.ciFilterName

        // Normal blend (source-over compositing)
        if filterName == "CISourceOverCompositing" {
            return fg.composited(over: background).cropped(to: outputExtent)
        }

        // Named blend mode filter
        guard let filter = CIFilter(name: filterName) else {
            // Fallback to source-over if unknown blend mode
            logger.warning("Blend mode filter '\(filterName)' not found, falling back to source-over")
            return fg.composited(over: background).cropped(to: outputExtent)
        }

        filter.setValue(fg, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)

        guard let outputImage = filter.outputImage else {
            logger.warning("Blend mode filter '\(filterName)' returned nil output, falling back to source-over")
            return fg.composited(over: background).cropped(to: outputExtent)
        }

        return outputImage.cropped(to: outputExtent)
    }

    // MARK: - Error Helpers

    private static func makeError(code: Int, message: String) -> NSError {
        NSError(
            domain: "com.liquideditor.MultiTrackCompositor",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

// MARK: - ChromaKeyCIFilter

/// Chroma key removal using CIColorCube-based 3D lookup table.
///
/// Uses a 3D color lookup table to map target chroma colors to transparent
/// pixels. Runs as a single GPU lookup operation (O(1) per pixel),
/// achieving 60 FPS on modern iPhones.
///
/// Thread Safety:
/// - Cube cache is protected by `cacheLock`.
/// - The `apply` method can be called concurrently from multiple render threads.
final class ChromaKeyCIFilter: @unchecked Sendable {

    /// Maximum number of chroma key cubes cached before LRU eviction.
    private static let maxCubeCacheSize = 10

    /// Cache for computed color cubes keyed by config hash.
    private var cubeCache: [Int: Data] = [:]

    /// LRU access order for cube cache keys (most recently used at the end).
    private var cubeCacheOrder: [Int] = []

    /// Lock protecting `cubeCache` and `cubeCacheOrder`.
    private let cacheLock = NSLock()

    /// Cube dimension for the 3D lookup table.
    private let cubeSize = 64

    // MARK: - Public API

    /// Apply chroma key to a source image.
    ///
    /// Pixels matching the target color become transparent, allowing
    /// lower tracks to show through.
    ///
    /// - Parameters:
    ///   - source: The source CIImage.
    ///   - config: Chroma key configuration.
    /// - Returns: Image with chroma key applied.
    func apply(source: CIImage, config: ChromaKeyConfig) -> CIImage {
        guard config.isEnabled else { return source }

        // Get or build cube data
        let cubeData = getOrBuildCube(config: config)

        // Apply CIColorCubeWithColorSpace filter
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cubeSize,
            "inputCubeData": cubeData,
            kCIInputImageKey: source,
            "inputColorSpace": CGColorSpaceCreateDeviceRGB(),
        ]) else {
            logger.error("Failed to create CIColorCubeWithColorSpace filter for chroma key")
            return source
        }

        guard let result = filter.outputImage else {
            logger.error("CIColorCubeWithColorSpace filter returned nil output")
            return source
        }

        // Apply spill suppression if configured
        if config.spillSuppression > 0.01 {
            return applySpillSuppression(image: result, config: config)
        }

        return result
    }

    /// Clear the cube cache.
    func clearCache() {
        cacheLock.lock()
        cubeCache.removeAll()
        cubeCacheOrder.removeAll()
        cacheLock.unlock()
    }

    // MARK: - Cube Building

    private func getOrBuildCube(config: ChromaKeyConfig) -> Data {
        let key = configHash(config)

        cacheLock.lock()
        if let cached = cubeCache[key] {
            // Promote to most recently used
            if let idx = cubeCacheOrder.firstIndex(of: key) {
                cubeCacheOrder.remove(at: idx)
            }
            cubeCacheOrder.append(key)
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Build cube outside the lock (CPU-intensive).
        logger.debug("Building chroma key cube for config hash \(key)")
        let cube = buildChromaKeyCube(config: config)

        cacheLock.lock()
        if let existing = cubeCache[key] {
            // Promote to most recently used
            if let idx = cubeCacheOrder.firstIndex(of: key) {
                cubeCacheOrder.remove(at: idx)
            }
            cubeCacheOrder.append(key)
            cacheLock.unlock()
            return existing
        }
        cubeCache[key] = cube
        cubeCacheOrder.append(key)

        // Evict least recently used entries if over limit
        var evictedCount = 0
        while cubeCache.count > Self.maxCubeCacheSize,
              let oldest = cubeCacheOrder.first {
            cubeCacheOrder.removeFirst()
            cubeCache.removeValue(forKey: oldest)
            evictedCount += 1
        }
        if evictedCount > 0 {
            logger.debug("Evicted \(evictedCount) chroma key cube(s) from cache")
        }
        cacheLock.unlock()

        return cube
    }

    private func configHash(_ config: ChromaKeyConfig) -> Int {
        var hasher = Hasher()
        hasher.combine(config.targetColor)
        hasher.combine(config.customColorValue)
        hasher.combine(config.sensitivity)
        hasher.combine(config.smoothness)
        return hasher.finalize()
    }

    /// Build 3D color lookup cube for chroma key.
    ///
    /// Maps RGB -> RGBA where pixels matching the target chroma range
    /// get alpha=0 (transparent) and everything else gets alpha=1.
    private func buildChromaKeyCube(config: ChromaKeyConfig) -> Data {
        let size = cubeSize
        var cubeData = [Float](repeating: 0, count: size * size * size * 4)
        let step = 1.0 / Float(size - 1)

        // Target hue in 0-1 range
        let hueCenter: Float
        let hueTolerance: Float = Float(config.sensitivity) * 0.25

        switch config.targetColor {
        case .green:
            hueCenter = 120.0 / 360.0
        case .blue:
            hueCenter = 240.0 / 360.0
        case .custom:
            if let colorValue = config.customColorValue {
                let r = Float((colorValue >> 16) & 0xFF) / 255.0
                let g = Float((colorValue >> 8) & 0xFF) / 255.0
                let b = Float(colorValue & 0xFF) / 255.0
                hueCenter = Self.rgbToHue(r: r, g: g, b: b)
            } else {
                hueCenter = 120.0 / 360.0
            }
        }

        let minSaturation: Float = 0.15

        for bIdx in 0..<size {
            for gIdx in 0..<size {
                for rIdx in 0..<size {
                    let rf = Float(rIdx) * step
                    let gf = Float(gIdx) * step
                    let bf = Float(bIdx) * step

                    let (h, s, _) = Self.rgbToHSV(r: rf, g: gf, b: bf)

                    // Circular hue distance
                    var hueDist = abs(h - hueCenter)
                    if hueDist > 0.5 { hueDist = 1.0 - hueDist }

                    // Determine alpha
                    var alpha: Float = 1.0
                    if s > minSaturation, hueDist < hueTolerance {
                        let edge = hueTolerance * Float(config.smoothness)
                        if edge > 0.001, hueDist > hueTolerance - edge {
                            alpha = (hueDist - (hueTolerance - edge)) / edge
                        } else {
                            alpha = 0.0
                        }
                    }

                    // Premultiplied alpha
                    let offset = (bIdx * size * size + gIdx * size + rIdx) * 4
                    cubeData[offset + 0] = rf * alpha
                    cubeData[offset + 1] = gf * alpha
                    cubeData[offset + 2] = bf * alpha
                    cubeData[offset + 3] = alpha
                }
            }
        }

        return Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
    }

    // MARK: - Spill Suppression

    /// Suppress color spill from the green/blue screen on foreground edges.
    private func applySpillSuppression(
        image: CIImage,
        config: ChromaKeyConfig
    ) -> CIImage {
        let strength = CGFloat(config.spillSuppression)

        switch config.targetColor {
        case .green:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputGVector": CIVector(
                    x: 0, y: CGFloat(1.0 - strength * 0.3), z: 0, w: 0
                ),
            ])
        case .blue:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputBVector": CIVector(
                    x: 0, y: 0, z: CGFloat(1.0 - strength * 0.3), w: 0
                ),
            ])
        case .custom:
            return image
        }
    }

    // MARK: - Color Conversion Helpers

    /// Convert RGB to HSV. Returns (hue 0-1, saturation 0-1, value 0-1).
    static func rgbToHSV(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        let v = maxVal
        let s = maxVal > 0.001 ? delta / maxVal : 0.0

        var h: Float = 0.0
        if delta > 0.001 {
            if maxVal == r {
                h = (g - b) / delta
                if h < 0 { h += 6.0 }
            } else if maxVal == g {
                h = 2.0 + (b - r) / delta
            } else {
                h = 4.0 + (r - g) / delta
            }
            h /= 6.0
        }

        return (h, s, v)
    }

    /// Extract hue from RGB color. Returns hue in 0-1 range.
    static func rgbToHue(r: Float, g: Float, b: Float) -> Float {
        rgbToHSV(r: r, g: g, b: b).0
    }
}
