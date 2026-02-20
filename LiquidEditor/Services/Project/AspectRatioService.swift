// AspectRatioService.swift
// LiquidEditor
//
// Calculates export dimensions, letterbox/pillarbox bars,
// zoom-to-fill scales, and translation clamping for aspect
// ratio conversions between source and target frames.

import Foundation

// MARK: - AspectRatioService

/// Service for aspect ratio calculations used during export and preview.
///
/// Handles export dimension derivation, letterbox/pillarbox bar sizing,
/// zoom-to-fill scale factors, and translation clamping so clips always
/// cover their canvas in fill-mode.
final class AspectRatioService: Sendable {

    // MARK: - Constants

    /// Tolerance for "ratios match" comparisons (avoids floating-point drift).
    private static let ratioTolerance: Double = 0.01

    // MARK: - Singleton

    static let shared = AspectRatioService()
    private init() {}

    // MARK: - Export Dimensions

    /// Calculate export pixel dimensions for a base resolution and optional ratio.
    ///
    /// When `ratio` is nil, the base width and height are returned as-is.
    /// When a ratio is provided, one dimension is constrained so the output
    /// fits within the base resolution at the target aspect ratio.
    ///
    /// - Parameters:
    ///   - baseWidth: Maximum output width in pixels (e.g. 1920 for 1080p).
    ///   - baseHeight: Maximum output height in pixels (e.g. 1080 for 1080p).
    ///   - ratio: Target aspect ratio, or nil to use the base dimensions.
    /// - Returns: Clamped (width, height) in pixels.
    func exportDimensions(
        baseWidth: Int,
        baseHeight: Int,
        ratio: AspectRatioSetting?
    ) -> (width: Int, height: Int) {
        guard let ratio else {
            return (width: baseWidth, height: baseHeight)
        }

        let targetAR = ratio.value
        let resWidth = Double(baseWidth)
        let resHeight = Double(baseHeight)

        if targetAR > resWidth / resHeight {
            // Target is wider than the base resolution — constrain by width.
            let h = Int((resWidth / targetAR).rounded())
            return (width: baseWidth, height: h)
        } else {
            // Target is taller than the base resolution — constrain by height.
            let w = Int((resHeight * targetAR).rounded())
            return (width: w, height: baseHeight)
        }
    }

    // MARK: - Letterbox / Pillarbox Bars

    /// Calculate normalized bar sizes for letterbox or pillarbox display.
    ///
    /// Returns bar sizes as fractions of the canvas dimension (0.0 – 0.5).
    /// A horizontal bar of 0.1 means 10% of the canvas height is black on
    /// each side (top and bottom), for a total of 20% bars.
    ///
    /// - Parameters:
    ///   - sourceRatio: Aspect ratio of the source content.
    ///   - targetRatio: Aspect ratio of the display canvas.
    /// - Returns: `(horizontal: leftRight, vertical: topBottom)` bar fractions.
    func calculateBars(
        sourceRatio: Double,
        targetRatio: Double
    ) -> (horizontal: Double, vertical: Double) {
        guard abs(sourceRatio - targetRatio) >= Self.ratioTolerance else {
            // Ratios match — no bars needed.
            return (horizontal: 0.0, vertical: 0.0)
        }

        if sourceRatio > targetRatio {
            // Source is wider than canvas — letterbox (top/bottom bars).
            let scaledHeight = targetRatio / sourceRatio
            let barSize = (1.0 - scaledHeight) / 2.0
            return (horizontal: 0.0, vertical: barSize)
        } else {
            // Source is taller than canvas — pillarbox (left/right bars).
            let scaledWidth = sourceRatio / targetRatio
            let barSize = (1.0 - scaledWidth) / 2.0
            return (horizontal: barSize, vertical: 0.0)
        }
    }

    // MARK: - Zoom-to-Fill Scale

    /// Calculate the minimum scale to fill the target frame with the source.
    ///
    /// The returned scale is the smallest factor that ensures every pixel
    /// of the target canvas is covered by the source.
    ///
    /// - Parameters:
    ///   - sourceRatio: Aspect ratio of the source content.
    ///   - targetRatio: Aspect ratio of the display canvas.
    /// - Returns: Scale factor ≥ 1.0.
    func zoomToFillScale(sourceRatio: Double, targetRatio: Double) -> Double {
        guard abs(sourceRatio - targetRatio) >= Self.ratioTolerance else {
            return 1.0
        }

        if sourceRatio > targetRatio {
            // Source is wider — scale to fill height.
            return sourceRatio / targetRatio
        } else {
            // Source is taller — scale to fill width.
            return targetRatio / sourceRatio
        }
    }

    // MARK: - Translation Clamping

    /// Clamp a normalized translation so the scaled source covers the canvas.
    ///
    /// When a source is zoomed to fill, panning must be limited so the source
    /// edges never become visible. Returns the clamped translation.
    ///
    /// - Parameters:
    ///   - translation: Proposed normalized translation (-0.5 to 0.5).
    ///   - scale: Current zoom scale (must be > 1.0 to have any effect).
    ///   - sourceRatio: Aspect ratio of the source content.
    ///   - targetRatio: Aspect ratio of the display canvas.
    ///   - isHorizontal: true = X axis clamp, false = Y axis clamp.
    /// - Returns: Translation clamped to keep source covering the canvas.
    func clampTranslation(
        translation: Double,
        scale: Double,
        sourceRatio: Double,
        targetRatio: Double,
        isHorizontal: Bool
    ) -> Double {
        guard scale > 1.0 else { return translation }

        let maxTranslation: Double

        if isHorizontal {
            if sourceRatio > targetRatio {
                maxTranslation = (scale - 1.0) / (2.0 * scale)
            } else {
                maxTranslation = (scale * sourceRatio / targetRatio - 1.0) / (2.0 * scale)
            }
        } else {
            if sourceRatio > targetRatio {
                maxTranslation = (scale * targetRatio / sourceRatio - 1.0) / (2.0 * scale)
            } else {
                maxTranslation = (scale - 1.0) / (2.0 * scale)
            }
        }

        return max(-maxTranslation, min(maxTranslation, translation))
    }

    // MARK: - Preset Access

    /// All available aspect ratio presets.
    var presets: [AspectRatioSetting] {
        AspectRatioSetting.presets
    }

    /// Display labels for all presets, in order.
    var presetLabels: [String] {
        AspectRatioSetting.presets.map(\.label)
    }
}
