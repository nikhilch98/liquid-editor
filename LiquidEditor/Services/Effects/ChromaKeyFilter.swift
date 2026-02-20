/// ChromaKeyFilter - CIColorCube-based chroma key for green/blue screen removal.
///
/// Uses a 3D color lookup table (CIColorCube) to map target chroma colors
/// to transparent pixels. This runs as a single GPU lookup operation (O(1) per pixel),
/// achieving 60 FPS on modern iPhones.
///
/// Thread Safety: `@unchecked Sendable` with `OSAllocatedUnfairLock`
/// protecting the cube cache. The cube build is CPU-intensive (~262K floats)
/// and is performed outside the lock, then stored atomically.
///
/// References:
/// - `ChromaKeyConfig` from Models/Compositing/ChromaKeyConfig.swift
/// - `ChromaKeyColor` from Models/Compositing/ChromaKeyConfig.swift

import CoreImage
import CoreGraphics
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "ChromaKeyFilter")

// MARK: - ChromaKeyFilter

/// Chroma key removal using CIFilter chain with 3D color cube.
///
/// Pipeline:
/// 1. Build a 3D color cube mapping chroma key colors to transparent
/// 2. Apply CIColorCube to source image
/// 3. Optionally apply spill suppression
final class ChromaKeyFilter: @unchecked Sendable {

    /// Cache for color cubes keyed by config hash.
    private var cubeCache: [Int: Data] = [:]

    /// Lock protecting cubeCache from concurrent access.
    private let cacheLock = OSAllocatedUnfairLock()

    /// Default cube size for the 3D lookup table.
    private let cubeSize = 64

    /// Minimum saturation threshold for chroma key matching.
    /// Colors below this saturation are preserved regardless of hue.
    /// Tuned to avoid keying out desaturated skin tones and grays.
    private static let minSaturation: Float = 0.15

    /// Spill suppression strength multiplier.
    /// Applied as (1.0 - strength * 0.3) to reduce the green/blue channel.
    /// Tuned to balance spill removal vs. color preservation.
    private static let spillSuppressionMultiplier: Float = 0.3

    // MARK: - Shared Instance

    /// Shared instance for convenience.
    static let shared = ChromaKeyFilter()

    // MARK: - Public API

    /// Generate chroma-keyed image from source.
    ///
    /// Pixels matching the target color become transparent,
    /// allowing lower tracks to show through.
    ///
    /// - Parameters:
    ///   - source: Input CIImage.
    ///   - config: Chroma key configuration from the model layer.
    /// - Returns: CIImage with matching pixels made transparent.
    func apply(
        source: CIImage,
        config: ChromaKeyConfig
    ) -> CIImage {
        guard config.isEnabled else { return source }

        // Generate or retrieve cached cube data
        let cubeData = getOrBuildCube(config: config)

        // Apply CIColorCube filter
        guard let colorCubeFilter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cubeSize,
            "inputCubeData": cubeData,
            kCIInputImageKey: source,
            "inputColorSpace": CGColorSpaceCreateDeviceRGB(),
        ]) else {
            logger.warning("Failed to create CIColorCubeWithColorSpace filter for chroma key")
            return source
        }

        guard let result = colorCubeFilter.outputImage else {
            logger.warning("CIColorCubeWithColorSpace filter returned nil output image")
            return source
        }

        // Apply spill suppression if enabled
        if config.spillSuppression > 0.01 {
            return applySpillSuppression(
                image: result,
                config: config
            )
        }

        return result
    }

    /// Clear the cube cache.
    func clearCache() {
        cacheLock.withLock { cubeCache.removeAll() }
    }

    // MARK: - Cube Building

    private func getOrBuildCube(config: ChromaKeyConfig) -> Data {
        let key = configHash(config)

        let cached: Data? = cacheLock.withLock { cubeCache[key] }
        if let cached { return cached }

        // Build cube outside the lock (CPU-intensive, ~262K floats).
        let cube = buildChromaKeyCube(config: config)

        return cacheLock.withLock {
            // Check again in case another thread built the same cube concurrently.
            if let existing = cubeCache[key] {
                return existing
            }
            cubeCache[key] = cube
            return cube
        }
    }

    private func configHash(_ config: ChromaKeyConfig) -> Int {
        var hasher = Hasher()
        hasher.combine(config.targetColor.rawValue)
        hasher.combine(config.customColorValue)
        hasher.combine(config.sensitivity)
        hasher.combine(config.smoothness)
        return hasher.finalize()
    }

    /// Build 3D color lookup cube for chroma key.
    ///
    /// Maps RGB colors to RGBA where the target chroma range
    /// gets alpha=0 (transparent) and everything else gets alpha=1.
    private func buildChromaKeyCube(config: ChromaKeyConfig) -> Data {
        let size = cubeSize
        var cubeData = [Float](repeating: 0, count: size * size * size * 4)
        let step = 1.0 / Float(size - 1)

        // Determine target hue based on color
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

        let minSaturation = Self.minSaturation

        for bIdx in 0..<size {
            for gIdx in 0..<size {
                for rIdx in 0..<size {
                    let rf = Float(rIdx) * step
                    let gf = Float(gIdx) * step
                    let bf = Float(bIdx) * step

                    let (h, s, _) = Self.rgbToHSV(r: rf, g: gf, b: bf)

                    // Calculate hue distance (circular)
                    var hueDist = abs(h - hueCenter)
                    if hueDist > 0.5 { hueDist = 1.0 - hueDist }

                    // Determine alpha
                    var alpha: Float = 1.0
                    if s > minSaturation && hueDist < hueTolerance {
                        let edge = hueTolerance * Float(config.smoothness)
                        if edge > 0.001 && hueDist > hueTolerance - edge {
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
    ///
    /// Reduces the target color channel by applying a color matrix that scales
    /// the channel by (1.0 - strength * spillSuppressionMultiplier).
    /// The 0.3 multiplier was empirically tuned to balance spill removal
    /// without introducing unnatural color shifts.
    private func applySpillSuppression(
        image: CIImage,
        config: ChromaKeyConfig
    ) -> CIImage {
        let strength = CGFloat(config.spillSuppression)
        let multiplier = CGFloat(Self.spillSuppressionMultiplier)

        switch config.targetColor {
        case .green:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputGVector": CIVector(x: 0, y: CGFloat(1.0 - strength * multiplier), z: 0, w: 0),
            ])
        case .blue:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(1.0 - strength * multiplier), w: 0),
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
