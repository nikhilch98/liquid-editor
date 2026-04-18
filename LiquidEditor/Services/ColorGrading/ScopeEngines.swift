// ScopeEngines.swift
// LiquidEditor
//
// C5-12: Scope compute engines (Histogram / Waveform / Vectorscope / Parade).
//
// Each engine analyses a `CIImage` and returns a `ScopeStats` variant.
// Engines are `@MainActor` because the scope panel is UI-driven and
// updates are throttled to the preview frame cadence (samplingStride
// controls spatial downsampling to keep per-frame compute budget tight).
//
// Histogram uses `CIAreaHistogram` + `CIContext.render` into a raw
// RGBA buffer; waveform/vectorscope/parade sample the image pixels
// directly through a reusable `CIContext`.

import Foundation
import CoreImage
import CoreGraphics

// MARK: - ScopeStats

/// Union of scope engine output shapes.
///
/// Each case carries the compact, display-ready data for one scope
/// type. Values are `Sendable` — safe to hand off to renderers on
/// other actors or store in `@Observable` state.
enum ScopeStats: Sendable, Equatable {
    /// RGB histogram: 256 bins per channel, normalized to 0...1.
    case histogram(red: [Float], green: [Float], blue: [Float])

    /// Luma waveform: one column per horizontal pixel bucket,
    /// each column is a 256-bin count (rows of the scope) in 0...1.
    case waveform(columns: [[Float]])

    /// Vectorscope: 2D chroma point cloud in normalized UV (-0.5...0.5).
    case vectorscope(points: [CGPoint])

    /// RGB parade: three waveforms (R,G,B) stacked side-by-side.
    case parade(red: [[Float]], green: [[Float]], blue: [[Float]])
}

// MARK: - ScopeEngineError

enum ScopeEngineError: Error, LocalizedError, Sendable {
    case renderFailed
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .renderFailed: "Scope engine render failed"
        case .invalidInput: "Scope engine received invalid input"
        }
    }
}

// MARK: - HistogramEngine

/// Computes a 3-channel RGB histogram using `CIAreaHistogram`.
///
/// `samplingStride` downsamples the source image by that factor
/// before histogram extraction. `stride=1` keeps full resolution;
/// `stride=4` analyses every 4th pixel in each axis (16x cheaper).
@MainActor
final class HistogramEngine {
    /// Shared Core Image context. `workingFormat: .RGBAf` preserves
    /// floating-point precision through the histogram reduction.
    private let ciContext: CIContext

    init(ciContext: CIContext = CIContext(options: [
        .workingFormat: CIFormat.RGBAf,
        .cacheIntermediates: false,
    ])) {
        self.ciContext = ciContext
    }

    /// Compute a normalized RGB histogram from `image`.
    ///
    /// - Parameters:
    ///   - image: Source image (assumed sRGB or linear — bins are raw).
    ///   - samplingStride: Spatial downsample factor (>= 1).
    /// - Returns: `.histogram` with 256 bins per channel normalized to 0...1.
    func compute(image: CIImage, samplingStride: Int = 1) throws -> ScopeStats {
        let stride = max(1, samplingStride)
        let source = Self.downsample(image, stride: stride)

        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else {
            throw ScopeEngineError.invalidInput
        }

        guard let histogramFilter = CIFilter(name: "CIAreaHistogram") else {
            throw ScopeEngineError.renderFailed
        }
        histogramFilter.setValue(source, forKey: kCIInputImageKey)
        histogramFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        histogramFilter.setValue(256, forKey: "inputCount")
        histogramFilter.setValue(1.0, forKey: "inputScale")

        guard let output = histogramFilter.outputImage else {
            throw ScopeEngineError.renderFailed
        }

        // Render the 256x1 float RGBA histogram image into a buffer.
        let floatsPerPixel = 4
        let pixelCount = 256
        let byteCount = pixelCount * floatsPerPixel * MemoryLayout<Float>.size
        var buffer = [Float](repeating: 0, count: pixelCount * floatsPerPixel)

        let bytesPerRow = pixelCount * floatsPerPixel * MemoryLayout<Float>.size
        buffer.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                ciContext.render(
                    output,
                    toBitmap: base,
                    rowBytes: bytesPerRow,
                    bounds: CGRect(x: 0, y: 0, width: 256, height: 1),
                    format: .RGBAf,
                    colorSpace: nil
                )
            }
        }
        _ = byteCount // silence unused warning in some builds

        var red = [Float](repeating: 0, count: 256)
        var green = [Float](repeating: 0, count: 256)
        var blue = [Float](repeating: 0, count: 256)
        var maxVal: Float = 0

        for i in 0..<256 {
            let r = buffer[i * 4 + 0]
            let g = buffer[i * 4 + 1]
            let b = buffer[i * 4 + 2]
            red[i] = r
            green[i] = g
            blue[i] = b
            if r > maxVal { maxVal = r }
            if g > maxVal { maxVal = g }
            if b > maxVal { maxVal = b }
        }

        if maxVal > 0 {
            for i in 0..<256 {
                red[i] /= maxVal
                green[i] /= maxVal
                blue[i] /= maxVal
            }
        }

        return .histogram(red: red, green: green, blue: blue)
    }

    /// Downsample `image` by `stride` on both axes using a CIAffineTransform.
    fileprivate static func downsample(_ image: CIImage, stride: Int) -> CIImage {
        guard stride > 1 else { return image }
        let s = 1.0 / CGFloat(stride)
        return image.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
}

// MARK: - WaveformEngine

/// Manually samples the source image to produce a luma waveform.
///
/// Output is `columns` where each column is a 256-bin count of
/// pixel luma values (one row per luma level). Vertical axis is
/// luma; horizontal axis is horizontal image position.
@MainActor
final class WaveformEngine {
    private let ciContext: CIContext
    private let targetColumns: Int

    init(
        ciContext: CIContext = CIContext(options: [.cacheIntermediates: false]),
        targetColumns: Int = 256
    ) {
        self.ciContext = ciContext
        self.targetColumns = max(16, targetColumns)
    }

    func compute(image: CIImage, samplingStride: Int = 1) throws -> ScopeStats {
        let stride = max(1, samplingStride)
        let scaled = HistogramEngine.downsample(image, stride: stride)
        let pixels = try ScopeRenderer.renderRGBA8(
            image: scaled,
            context: ciContext,
            targetWidth: targetColumns
        )

        let width = pixels.width
        let height = pixels.height
        var columns = [[Float]](repeating: [Float](repeating: 0, count: 256), count: width)
        var maxCount: Float = 0

        pixels.buffer.withUnsafeBufferPointer { bp in
            guard let base = bp.baseAddress else { return }
            for x in 0..<width {
                var column = [Float](repeating: 0, count: 256)
                for y in 0..<height {
                    let idx = (y * width + x) * 4
                    let r = Float(base[idx + 0]) / 255.0
                    let g = Float(base[idx + 1]) / 255.0
                    let b = Float(base[idx + 2]) / 255.0
                    // Rec. 709 luma
                    let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    let bin = min(255, max(0, Int(luma * 255.0)))
                    column[bin] += 1
                    if column[bin] > maxCount { maxCount = column[bin] }
                }
                columns[x] = column
            }
        }

        // Normalize per-waveform max to keep bright regions visible.
        if maxCount > 0 {
            for x in 0..<columns.count {
                for bin in 0..<256 {
                    columns[x][bin] /= maxCount
                }
            }
        }

        return .waveform(columns: columns)
    }
}

// MARK: - VectorscopeEngine

/// Produces a 2D chroma scatter plot (U,V points) for a vectorscope.
///
/// Samples are drawn from a downsampled render of the input. UV is
/// computed with the BT.709 matrix. Returned points live in the
/// range `-0.5 ... 0.5` on both axes.
@MainActor
final class VectorscopeEngine {
    private let ciContext: CIContext
    private let maxPoints: Int

    init(
        ciContext: CIContext = CIContext(options: [.cacheIntermediates: false]),
        maxPoints: Int = 4096
    ) {
        self.ciContext = ciContext
        self.maxPoints = max(128, maxPoints)
    }

    func compute(image: CIImage, samplingStride: Int = 1) throws -> ScopeStats {
        let stride = max(1, samplingStride)
        let scaled = HistogramEngine.downsample(image, stride: stride)

        // Render to a small target so we always have a bounded sample set.
        let targetWidth = Int(Double(maxPoints).squareRoot())
        let pixels = try ScopeRenderer.renderRGBA8(
            image: scaled,
            context: ciContext,
            targetWidth: targetWidth
        )

        var points: [CGPoint] = []
        points.reserveCapacity(pixels.width * pixels.height)

        pixels.buffer.withUnsafeBufferPointer { bp in
            guard let base = bp.baseAddress else { return }
            for y in 0..<pixels.height {
                for x in 0..<pixels.width {
                    let idx = (y * pixels.width + x) * 4
                    let r = Float(base[idx + 0]) / 255.0
                    let g = Float(base[idx + 1]) / 255.0
                    let b = Float(base[idx + 2]) / 255.0
                    // BT.709 UV (centered at 0)
                    let u = -0.09991 * r - 0.33609 * g + 0.436 * b
                    let v = 0.615 * r - 0.55861 * g - 0.05639 * b
                    points.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
                }
            }
        }

        // Cap point count.
        if points.count > maxPoints {
            let step = points.count / maxPoints
            points = Swift.stride(from: 0, to: points.count, by: max(1, step)).map { points[$0] }
        }

        return .vectorscope(points: points)
    }
}

// MARK: - ParadeEngine

/// RGB parade: three per-channel column waveforms stacked side by side.
@MainActor
final class ParadeEngine {
    private let ciContext: CIContext
    private let targetColumns: Int

    init(
        ciContext: CIContext = CIContext(options: [.cacheIntermediates: false]),
        targetColumns: Int = 256
    ) {
        self.ciContext = ciContext
        self.targetColumns = max(16, targetColumns)
    }

    func compute(image: CIImage, samplingStride: Int = 1) throws -> ScopeStats {
        let stride = max(1, samplingStride)
        let scaled = HistogramEngine.downsample(image, stride: stride)
        let pixels = try ScopeRenderer.renderRGBA8(
            image: scaled,
            context: ciContext,
            targetWidth: targetColumns
        )

        let w = pixels.width
        let h = pixels.height
        var redColumns = [[Float]](repeating: [Float](repeating: 0, count: 256), count: w)
        var greenColumns = [[Float]](repeating: [Float](repeating: 0, count: 256), count: w)
        var blueColumns = [[Float]](repeating: [Float](repeating: 0, count: 256), count: w)
        var maxCount: Float = 0

        pixels.buffer.withUnsafeBufferPointer { bp in
            guard let base = bp.baseAddress else { return }
            for x in 0..<w {
                var rCol = [Float](repeating: 0, count: 256)
                var gCol = [Float](repeating: 0, count: 256)
                var bCol = [Float](repeating: 0, count: 256)
                for y in 0..<h {
                    let idx = (y * w + x) * 4
                    let rVal = Int(base[idx + 0])
                    let gVal = Int(base[idx + 1])
                    let bVal = Int(base[idx + 2])
                    rCol[rVal] += 1
                    gCol[gVal] += 1
                    bCol[bVal] += 1
                    if rCol[rVal] > maxCount { maxCount = rCol[rVal] }
                    if gCol[gVal] > maxCount { maxCount = gCol[gVal] }
                    if bCol[bVal] > maxCount { maxCount = bCol[bVal] }
                }
                redColumns[x] = rCol
                greenColumns[x] = gCol
                blueColumns[x] = bCol
            }
        }

        if maxCount > 0 {
            for x in 0..<w {
                for bin in 0..<256 {
                    redColumns[x][bin] /= maxCount
                    greenColumns[x][bin] /= maxCount
                    blueColumns[x][bin] /= maxCount
                }
            }
        }

        return .parade(red: redColumns, green: greenColumns, blue: blueColumns)
    }
}

// MARK: - ScopeRenderer (private helper)

/// Private helper that renders a CIImage to an RGBA8 CPU buffer.
///
/// Used by the waveform / vectorscope / parade engines to sample
/// pixels directly. The histogram engine uses `CIAreaHistogram` and
/// does not need this path.
@MainActor
private enum ScopeRenderer {

    struct RGBA8Buffer {
        let buffer: [UInt8]
        let width: Int
        let height: Int
    }

    /// Render `image` into an RGBA8 buffer at roughly `targetWidth` columns,
    /// preserving aspect ratio.
    static func renderRGBA8(
        image: CIImage,
        context: CIContext,
        targetWidth: Int
    ) throws -> RGBA8Buffer {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            throw ScopeEngineError.invalidInput
        }

        let targetW = max(16, min(targetWidth, Int(extent.width)))
        let scale = CGFloat(targetW) / extent.width
        let targetH = max(1, Int(extent.height * scale))

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let byteCount = targetW * targetH * 4
        var buffer = [UInt8](repeating: 0, count: byteCount)

        let bytesPerRow = targetW * 4
        buffer.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                context.render(
                    scaled,
                    toBitmap: base,
                    rowBytes: bytesPerRow,
                    bounds: CGRect(x: 0, y: 0, width: targetW, height: targetH),
                    format: .RGBA8,
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )
            }
        }

        return RGBA8Buffer(buffer: buffer, width: targetW, height: targetH)
    }
}
