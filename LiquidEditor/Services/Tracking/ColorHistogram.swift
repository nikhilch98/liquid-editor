//
//  ColorHistogram.swift
//  LiquidEditor
//
//  HSV color histogram extraction for person appearance matching.
//  Extracts separate histograms for upper body, lower body, and full body regions.
//
//

import Accelerate
import CoreGraphics
import CoreImage
import Foundation
import Vision

// MARK: - Color Histogram

/// HSV histogram for body regions used in appearance matching.
public struct ColorHistogram: Sendable, Codable, Equatable {

    // MARK: - Properties

    /// HSV histogram for upper body (64 bins = 8H x 4S x 2V).
    public let upperBody: [Float]

    /// HSV histogram for lower body (64 bins = 8H x 4S x 2V).
    public let lowerBody: [Float]

    /// HSV histogram for full body (64 bins = 8H x 4S x 2V).
    public let fullBody: [Float]

    /// Number of bins in each histogram.
    public static let binCount = 64

    /// Hue bins (8).
    public static let hueBins = 8

    /// Saturation bins (4).
    public static let saturationBins = 4

    /// Value/brightness bins (2).
    public static let valueBins = 2

    // MARK: - Initialization

    public init(upperBody: [Float], lowerBody: [Float], fullBody: [Float]) {
        precondition(upperBody.count == Self.binCount, "upperBody must have \(Self.binCount) bins")
        precondition(lowerBody.count == Self.binCount, "lowerBody must have \(Self.binCount) bins")
        precondition(fullBody.count == Self.binCount, "fullBody must have \(Self.binCount) bins")

        self.upperBody = upperBody
        self.lowerBody = lowerBody
        self.fullBody = fullBody
    }

    // MARK: - Static Constructors

    /// Empty histogram (all zeros).
    public static let empty = ColorHistogram(
        upperBody: [Float](repeating: 0, count: binCount),
        lowerBody: [Float](repeating: 0, count: binCount),
        fullBody: [Float](repeating: 0, count: binCount)
    )

    /// Extract color histogram from a CGImage with optional pose information.
    /// - Parameters:
    ///   - image: Source image.
    ///   - pose: Body pose observation for determining upper/lower split.
    ///   - boundingBox: Normalized bounding box of the person.
    /// - Returns: ColorHistogram with upper, lower, and full body histograms.
    public static func extract(
        from image: CGImage,
        pose: VNHumanBodyPoseObservation?,
        boundingBox: CGRect
    ) -> ColorHistogram {
        // Convert normalized bounding box to pixel coordinates
        let imageSize = CGSize(width: image.width, height: image.height)
        let pixelRect = scaledRect(boundingBox, to: imageSize)

        // Ensure rect is within image bounds
        let clampedRect = CGRect(
            x: max(0, pixelRect.minX),
            y: max(0, pixelRect.minY),
            width: min(pixelRect.width, CGFloat(image.width) - pixelRect.minX),
            height: min(pixelRect.height, CGFloat(image.height) - pixelRect.minY)
        )

        guard clampedRect.width > 0, clampedRect.height > 0,
              let cropped = image.cropping(to: clampedRect) else {
            return .empty
        }

        // Convert to HSV pixels
        let hsvPixels = convertToHSV(cropped)
        guard !hsvPixels.isEmpty else { return .empty }

        // Determine upper/lower split ratio
        let splitRatio: CGFloat
        if let pose = pose,
           let hip = try? pose.recognizedPoint(.root),
           hip.confidence > 0.3 {
            splitRatio = hip.location.y
        } else {
            splitRatio = 0.5
        }

        // Separate upper and lower body pixels
        let upperPixels = hsvPixels.filter { $0.y < Float(splitRatio) }
        let lowerPixels = hsvPixels.filter { $0.y >= Float(splitRatio) }

        // Build histograms
        let upperHist = buildHSVHistogram(upperPixels)
        let lowerHist = buildHSVHistogram(lowerPixels)
        let fullHist = buildHSVHistogram(hsvPixels)

        return ColorHistogram(
            upperBody: upperHist,
            lowerBody: lowerHist,
            fullBody: fullHist
        )
    }

    /// Compute average of multiple histograms.
    public static func average(_ histograms: [ColorHistogram]) -> ColorHistogram {
        guard !histograms.isEmpty else { return .empty }

        let count = Float(histograms.count)
        var avgUpper = [Float](repeating: 0, count: binCount)
        var avgLower = [Float](repeating: 0, count: binCount)
        var avgFull = [Float](repeating: 0, count: binCount)

        for hist in histograms {
            for i in 0..<binCount {
                avgUpper[i] += hist.upperBody[i] / count
                avgLower[i] += hist.lowerBody[i] / count
                avgFull[i] += hist.fullBody[i] / count
            }
        }

        return ColorHistogram(upperBody: avgUpper, lowerBody: avgLower, fullBody: avgFull)
    }

    /// Alias for average -- aggregate multiple histograms into one.
    public static func aggregate(_ histograms: [ColorHistogram]) -> ColorHistogram {
        average(histograms)
    }

    /// Extract color histogram from a CGImage with NormalizedBoundingBox (no pose info).
    /// Used by TrackReidentifier for box tracking post-processing.
    /// - Parameters:
    ///   - image: Source CGImage.
    ///   - boundingBox: Normalized bounding box (center-based, Double coordinates).
    /// - Returns: ColorHistogram with upper, lower, and full body histograms.
    static func extract(
        from image: CGImage,
        boundingBox: NormalizedBoundingBox
    ) -> ColorHistogram {
        // Convert NormalizedBoundingBox (center-based) to CGRect (origin-based)
        let cgRect = CGRect(
            x: boundingBox.x - boundingBox.width / 2,
            y: boundingBox.y - boundingBox.height / 2,
            width: boundingBox.width,
            height: boundingBox.height
        )
        return extract(from: image, pose: nil, boundingBox: cgRect)
    }

    // MARK: - Similarity

    /// Compute histogram intersection similarity (0.0 to 1.0).
    /// Higher values indicate more similar color distributions.
    public func similarity(to other: ColorHistogram) -> Float {
        let upperSim = Self.histogramIntersectionSimilarity(upperBody, other.upperBody)
        let lowerSim = Self.histogramIntersectionSimilarity(lowerBody, other.lowerBody)
        return 0.5 * upperSim + 0.5 * lowerSim
    }

    /// Full body similarity only.
    public func fullBodySimilarity(to other: ColorHistogram) -> Float {
        Self.histogramIntersectionSimilarity(fullBody, other.fullBody)
    }

    // MARK: - Private Helpers

    /// Scale a normalized rect to pixel coordinates.
    private static func scaledRect(_ rect: CGRect, to size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    /// Histogram intersection similarity (0.0 to 1.0).
    private static func histogramIntersectionSimilarity(_ h1: [Float], _ h2: [Float]) -> Float {
        guard h1.count == h2.count, !h1.isEmpty else { return 0 }

        let intersection = zip(h1, h2).map { min($0, $1) }.reduce(0, +)
        let sum1 = h1.reduce(0, +)
        let sum2 = h2.reduce(0, +)
        let maxSum = max(sum1, sum2)

        guard maxSum > 0 else { return 0 }
        return intersection / maxSum
    }

    /// HSV pixel with position information.
    private struct HSVPixel {
        let h: Float  // Hue: 0-1
        let s: Float  // Saturation: 0-1
        let v: Float  // Value: 0-1
        let x: Float  // Normalized x position: 0-1
        let y: Float  // Normalized y position: 0-1
    }

    /// Convert CGImage to HSV pixel arrays using Accelerate for SIMD performance.
    ///
    /// Uses vImage for pixel extraction and vDSP for vectorized RGB-to-HSV
    /// conversion, avoiding per-pixel Swift iteration.
    private static func convertToHSV(_ image: CGImage) -> [HSVPixel] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        let pixelCount = width * height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        // Render into RGBA8 buffer
        var pixelData = [UInt8](repeating: 0, count: pixelCount * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // De-interleave RGBA UInt8 into separate Float channels using Accelerate
        var rF = [Float](repeating: 0, count: pixelCount)
        var gF = [Float](repeating: 0, count: pixelCount)
        var bF = [Float](repeating: 0, count: pixelCount)

        let len = vDSP_Length(pixelCount)

        // Extract R, G, B channels with stride-4 access and convert UInt8 -> Float / 255
        pixelData.withUnsafeBufferPointer { rawBuf in
            let base = rawBuf.baseAddress!
            // Use vDSP to convert strided UInt8 to Float
            // Step 1: Copy strided bytes into contiguous UInt8 arrays
            var rU8 = [UInt8](repeating: 0, count: pixelCount)
            var gU8 = [UInt8](repeating: 0, count: pixelCount)
            var bU8 = [UInt8](repeating: 0, count: pixelCount)

            for i in 0..<pixelCount {
                rU8[i] = base[i * 4]
                gU8[i] = base[i * 4 + 1]
                bU8[i] = base[i * 4 + 2]
            }

            // Convert UInt8 -> Float using vDSP
            vDSP_vfltu8(rU8, 1, &rF, 1, len)
            vDSP_vfltu8(gU8, 1, &gF, 1, len)
            vDSP_vfltu8(bU8, 1, &bF, 1, len)
        }

        // Scale to 0-1 range: divide by 255
        var scale: Float = 1.0 / 255.0
        vDSP_vsmul(rF, 1, &scale, &rF, 1, len)
        vDSP_vsmul(gF, 1, &scale, &gF, 1, len)
        vDSP_vsmul(bF, 1, &scale, &bF, 1, len)

        // Vectorized RGB -> HSV conversion using vDSP
        // maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var maxRG = [Float](repeating: 0, count: pixelCount)
        var maxC = [Float](repeating: 0, count: pixelCount)
        var minRG = [Float](repeating: 0, count: pixelCount)
        var minC = [Float](repeating: 0, count: pixelCount)
        var delta = [Float](repeating: 0, count: pixelCount)

        vDSP_vmax(rF, 1, gF, 1, &maxRG, 1, len)
        vDSP_vmax(maxRG, 1, bF, 1, &maxC, 1, len)
        vDSP_vmin(rF, 1, gF, 1, &minRG, 1, len)
        vDSP_vmin(minRG, 1, bF, 1, &minC, 1, len)
        vDSP_vsub(minC, 1, maxC, 1, &delta, 1, len) // delta = maxC - minC

        // V = maxC (already computed)
        // S = delta / maxC (where maxC > 0)
        // H computed per-pixel (hue sector logic is branchy, done in a tight loop)
        var hArray = [Float](repeating: 0, count: pixelCount)
        var sArray = [Float](repeating: 0, count: pixelCount)

        for i in 0..<pixelCount {
            let mc = maxC[i]
            let d = delta[i]

            if mc > 0 {
                sArray[i] = d / mc
            }

            if d > 0 {
                var h: Float
                if mc == rF[i] {
                    h = (gF[i] - bF[i]) / d
                    if h < 0 { h += 6 }
                } else if mc == gF[i] {
                    h = 2 + (bF[i] - rF[i]) / d
                } else {
                    h = 4 + (rF[i] - gF[i]) / d
                }
                hArray[i] = h / 6.0
            }
        }

        // Build HSVPixel array with normalized positions
        var hsvPixels: [HSVPixel] = []
        hsvPixels.reserveCapacity(pixelCount)

        let wf = Float(width)
        let hf = Float(height)

        for i in 0..<pixelCount {
            let px = i % width
            let py = i / width
            hsvPixels.append(HSVPixel(
                h: hArray[i], s: sArray[i], v: maxC[i],
                x: Float(px) / wf,
                y: Float(py) / hf
            ))
        }

        return hsvPixels
    }

    /// Build HSV histogram from pixels using vectorized operations.
    private static func buildHSVHistogram(_ pixels: [HSVPixel]) -> [Float] {
        guard !pixels.isEmpty else {
            return [Float](repeating: 0, count: binCount)
        }

        var histogram = [Float](repeating: 0, count: binCount)

        let hBinsF = Float(hueBins)
        let sBinsF = Float(saturationBins)
        let vBinsF = Float(valueBins)
        let svProduct = saturationBins * valueBins

        for pixel in pixels {
            let hBin = min(Int(pixel.h * hBinsF), hueBins - 1)
            let sBin = min(Int(pixel.s * sBinsF), saturationBins - 1)
            let vBin = min(Int(pixel.v * vBinsF), valueBins - 1)

            let binIndex = hBin * svProduct + sBin * valueBins + vBin
            histogram[binIndex] += 1
        }

        // Normalize histogram using vDSP
        var total: Float = 0
        vDSP_sve(histogram, 1, &total, vDSP_Length(binCount))
        if total > 0 {
            vDSP_vsdiv(histogram, 1, &total, &histogram, 1, vDSP_Length(binCount))
        }

        return histogram
    }
}

// MARK: - CustomStringConvertible

extension ColorHistogram: CustomStringConvertible {
    public var description: String {
        let upperSum = upperBody.reduce(0, +)
        let lowerSum = lowerBody.reduce(0, +)
        return "ColorHistogram(upper: \(String(format: "%.2f", upperSum)), lower: \(String(format: "%.2f", lowerSum)))"
    }
}
