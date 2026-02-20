/// ColorGradingPipeline - CIFilter chain for per-clip color grading.
///
/// Maps the `ColorGrade` model to a native CIFilter pipeline.
/// Pipeline stages follow the professional color grading order
/// (matching DaVinci Resolve node order):
///   1. Exposure (CIExposureAdjust)
///   2. White Balance (CITemperatureAndTint)
///   3. Highlights / Shadows (CIHighlightShadowAdjust)
///   4. Whites / Blacks (CIToneCurve)
///   5. Contrast / Brightness / Saturation (CIColorControls)
///   6. Vibrance (selective saturation boost)
///  6b. Hue Rotation (CIHueAdjust)
///   7. HSL Color Wheels (CIColorMatrix per tonal range)
///   8. Tone Curves - Luminance, R, G, B (CIToneCurve / CIColorPolynomial)
///   9. LUT (CIColorCubeWithColorSpace)
///  10. Sharpen / Clarity (CISharpenLuminance / CIUnsharpMask)
///  11. Vignette (CIVignetteEffect / CIVignette)
///
/// All stages skip processing when parameters are at identity (default) values.
/// Uses `EffectPipeline.sharedContext` for GPU-accelerated Metal rendering.
///
/// Thread Safety: `@unchecked Sendable` with `OSAllocatedUnfairLock`
/// protecting the LUT cache. All other methods are stateless and safe
/// to call from any thread.
///
/// References:
/// - `ColorGrade` from Models/ColorGrading/ColorGrade.swift
/// - `HSLAdjustment` from Models/ColorGrading/HSLAdjustment.swift
/// - `CurveData` from Models/ColorGrading/CurveData.swift
/// - `LUTReference` from Models/ColorGrading/LUTReference.swift

import Foundation
import CoreImage
import CoreGraphics
import os

// MARK: - ColorGradingPipeline

/// Builds and applies a CIFilter chain for color grading parameters.
///
/// Uses `OSAllocatedUnfairLock` for LUT cache protection on the render thread.
final class ColorGradingPipeline: @unchecked Sendable, ColorGradingProtocol {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "ColorGradingPipeline")

    /// Epsilon for floating-point zero checks.
    private static let epsilon: Double = 0.0001

    /// Shared instance for convenience.
    static let shared = ColorGradingPipeline()

    /// Maximum number of LUT entries cached before LRU eviction.
    private static let maxLUTCacheSize = 20

    /// Lock protecting the LUT cache.
    private let lutLock = OSAllocatedUnfairLock()

    /// Cache for parsed LUT cube data, keyed by file path.
    private var lutCache: [String: (data: Data, dimension: Int)] = [:]

    /// LRU access order for LUT cache keys (most recently used at the end).
    private var lutAccessOrder: [String] = []

    // MARK: - ColorGradingProtocol

    /// Apply a color grade configuration to an image.
    ///
    /// The grade is applied as a multi-stage pipeline. Identity grades
    /// (all defaults) return the input unchanged.
    ///
    /// - Parameters:
    ///   - grade: The `ColorGrade` configuration.
    ///   - image: Source CIImage.
    /// - Returns: Color-graded CIImage.
    func apply(grade: ColorGrade, to image: CIImage) -> CIImage {
        guard grade.isEnabled else { return image }
        if grade.isIdentity { return image }

        var current = image

        // Stage 1: Exposure
        current = applyExposure(current, grade: grade)

        // Stage 2: White Balance (Temperature + Tint)
        current = applyWhiteBalance(current, grade: grade)

        // Stage 3: Highlights / Shadows
        current = applyHighlightsShadows(current, grade: grade)

        // Stage 4: Whites / Blacks (tonal curve endpoints)
        current = applyWhitesBlacks(current, grade: grade)

        // Stage 5: Contrast / Brightness / Saturation
        current = applyContrastBrightnessSaturation(current, grade: grade)

        // Stage 6: Vibrance (selective saturation boost)
        current = applyVibrance(current, grade: grade)

        // Stage 6b: Hue Rotation (global hue shift)
        current = applyHueRotation(current, grade: grade)

        // Stage 7: HSL Color Wheels
        current = applyHSLWheels(current, grade: grade)

        // Stage 8: Tone Curves (Luminance, R, G, B)
        current = applyCurves(current, grade: grade)

        // Stage 9: LUT
        current = applyLUT(current, grade: grade)

        // Stage 10: Sharpen / Clarity
        current = applySharpenClarity(current, grade: grade)

        // Stage 11: Vignette
        current = applyVignette(current, grade: grade)

        return current
    }

    /// Clear the LUT cache (call on memory pressure or when done).
    func clearLUTCache() {
        lutLock.withLock {
            lutCache.removeAll()
            lutAccessOrder.removeAll()
        }
    }

    // MARK: - Stage 1: Exposure

    private func applyExposure(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.exposure) > Self.epsilon else { return image }

        guard let filter = CIFilter(name: "CIExposureAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(grade.exposure, forKey: kCIInputEVKey)
        return filter.outputImage ?? image
    }

    // MARK: - Stage 2: White Balance

    private func applyWhiteBalance(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.temperature) > Self.epsilon || abs(grade.tint) > Self.epsilon else { return image }

        guard let filter = CIFilter(name: "CITemperatureAndTint") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        // Temperature mapping: -1.0..1.0 -> 2500K..10500K (6500K = neutral)
        // Tint mapping: -1.0..1.0 -> -150..150 (0 = neutral)
        let targetTemp = 6500.0 + grade.temperature * 4000.0
        let targetTint = grade.tint * 150.0

        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: CGFloat(targetTemp), y: CGFloat(targetTint)),
                       forKey: "inputTargetNeutral")

        return filter.outputImage ?? image
    }

    // MARK: - Stage 3: Highlights / Shadows

    private func applyHighlightsShadows(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.highlights) > Self.epsilon || abs(grade.shadows) > Self.epsilon else {
            return image
        }

        guard let filter = CIFilter(name: "CIHighlightShadowAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        // For highlights: map -1..1 to 0..2 (1.0 = neutral)
        filter.setValue(1.0 + grade.highlights, forKey: "inputHighlightAmount")
        // For shadows: direct mapping -1..1 (0 = neutral)
        filter.setValue(grade.shadows, forKey: "inputShadowAmount")

        return filter.outputImage ?? image
    }

    // MARK: - Stage 4: Whites / Blacks

    private func applyWhitesBlacks(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.whites) > Self.epsilon || abs(grade.blacks) > Self.epsilon else {
            return image
        }

        guard let filter = CIFilter(name: "CIToneCurve") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        let blackPoint = grade.blacks * 0.15
        let whitePoint = 1.0 + grade.whites * 0.15

        filter.setValue(CIVector(x: 0.0, y: CGFloat(blackPoint)), forKey: "inputPoint0")
        filter.setValue(CIVector(x: 0.25, y: 0.25), forKey: "inputPoint1")
        filter.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
        filter.setValue(CIVector(x: 0.75, y: 0.75), forKey: "inputPoint3")
        filter.setValue(CIVector(x: 1.0, y: CGFloat(min(1.5, whitePoint))), forKey: "inputPoint4")

        return filter.outputImage ?? image
    }

    // MARK: - Stage 5: Contrast / Brightness / Saturation

    private func applyContrastBrightnessSaturation(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.contrast) > Self.epsilon
            || abs(grade.brightness) > Self.epsilon
            || abs(grade.saturation) > Self.epsilon else {
            return image
        }

        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        // inputContrast: neutral=1.0, map -1..1 -> 0.25..1.75
        // inputBrightness: neutral=0.0, range -1..1
        // inputSaturation: neutral=1.0, map -1..1 -> 0.0..2.0
        filter.setValue(1.0 + grade.contrast * 0.75, forKey: kCIInputContrastKey)
        filter.setValue(grade.brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(1.0 + grade.saturation, forKey: kCIInputSaturationKey)

        return filter.outputImage ?? image
    }

    // MARK: - Stage 6: Vibrance

    private func applyVibrance(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.vibrance) > Self.epsilon else { return image }

        guard let satFilter = CIFilter(name: "CIColorControls") else { return image }
        satFilter.setValue(image, forKey: kCIInputImageKey)

        let satBoost = 1.0 + abs(grade.vibrance) * 0.5
        if grade.vibrance > 0 {
            satFilter.setValue(satBoost, forKey: kCIInputSaturationKey)
        } else {
            satFilter.setValue(1.0 / satBoost, forKey: kCIInputSaturationKey)
        }
        satFilter.setValue(0.0, forKey: kCIInputBrightnessKey)
        satFilter.setValue(1.0, forKey: kCIInputContrastKey)

        guard let saturatedImage = satFilter.outputImage else { return image }

        guard let dissolve = CIFilter(name: "CIDissolveTransition") else { return saturatedImage }
        dissolve.setValue(image, forKey: kCIInputImageKey)
        dissolve.setValue(saturatedImage, forKey: kCIInputTargetImageKey)
        dissolve.setValue(min(1.0, abs(grade.vibrance) * 0.7), forKey: "inputTime")
        return dissolve.outputImage ?? image
    }

    // MARK: - Stage 6b: Hue Rotation

    private func applyHueRotation(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.hue) > Self.epsilon else { return image }

        guard let filter = CIFilter(name: "CIHueAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        let hueRadians = grade.hue * .pi / 180.0
        filter.setValue(hueRadians, forKey: kCIInputAngleKey)
        return filter.outputImage ?? image
    }

    // MARK: - Stage 7: HSL Color Wheels

    private func applyHSLWheels(_ image: CIImage, grade: ColorGrade) -> CIImage {
        let allIdentity = grade.hslShadows.isIdentity
            && grade.hslMidtones.isIdentity
            && grade.hslHighlights.isIdentity
        guard !allIdentity else { return image }

        var current = image

        if !grade.hslShadows.isIdentity {
            current = applyTonalTint(current, hsl: grade.hslShadows, range: .shadows)
        }
        if !grade.hslMidtones.isIdentity {
            current = applyTonalTint(current, hsl: grade.hslMidtones, range: .midtones)
        }
        if !grade.hslHighlights.isIdentity {
            current = applyTonalTint(current, hsl: grade.hslHighlights, range: .highlights)
        }

        return current
    }

    /// Tonal range for HSL wheel application.
    private enum TonalRange {
        case shadows, midtones, highlights
    }

    /// Apply a tint to a specific tonal range using CIColorMatrix bias.
    private func applyTonalTint(
        _ image: CIImage,
        hsl: HSLAdjustment,
        range: TonalRange
    ) -> CIImage {
        let hueRad = hsl.hue * .pi / 180.0
        let r = hsl.saturation * cos(hueRad) * 0.1
        let g = hsl.saturation * cos(hueRad - 2.0 * .pi / 3.0) * 0.1
        let b = hsl.saturation * cos(hueRad + 2.0 * .pi / 3.0) * 0.1
        let lumOffset = hsl.luminance * 0.1

        let biasR: CGFloat
        let biasG: CGFloat
        let biasB: CGFloat

        switch range {
        case .shadows:
            biasR = CGFloat(r + lumOffset) * 0.5
            biasG = CGFloat(g + lumOffset) * 0.5
            biasB = CGFloat(b + lumOffset) * 0.5
        case .midtones:
            biasR = CGFloat(r + lumOffset)
            biasG = CGFloat(g + lumOffset)
            biasB = CGFloat(b + lumOffset)
        case .highlights:
            biasR = CGFloat(r + lumOffset) * 0.5
            biasG = CGFloat(g + lumOffset) * 0.5
            biasB = CGFloat(b + lumOffset) * 0.5
        }

        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: biasR, y: biasG, z: biasB, w: 0),
        ])
    }

    // MARK: - Stage 8: Tone Curves

    private func applyCurves(_ image: CIImage, grade: ColorGrade) -> CIImage {
        let lumIdentity = grade.curveLuminance.isIdentity
        let redIdentity = grade.curveRed.isIdentity
        let greenIdentity = grade.curveGreen.isIdentity
        let blueIdentity = grade.curveBlue.isIdentity

        guard !lumIdentity || !redIdentity || !greenIdentity || !blueIdentity else {
            return image
        }

        var current = image

        // Apply luminance curve
        if !lumIdentity {
            current = applySingleCurve(current, curveData: grade.curveLuminance, channel: .luminance)
        }

        // Apply per-channel curves
        if !redIdentity || !greenIdentity || !blueIdentity {
            current = applyRGBCurves(
                current,
                red: redIdentity ? nil : grade.curveRed,
                green: greenIdentity ? nil : grade.curveGreen,
                blue: blueIdentity ? nil : grade.curveBlue
            )
        }

        return current
    }

    /// Curve channel types.
    private enum CurveChannel {
        case luminance, red, green, blue
    }

    /// Apply a single tone curve using CIToneCurve (5-point approximation).
    private func applySingleCurve(_ image: CIImage, curveData: CurveData, channel: CurveChannel) -> CIImage {
        guard let filter = CIFilter(name: "CIToneCurve") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        // CIToneCurve requires exactly 5 points. Sample the input curve.
        let sampleXs: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let sampledY = sampleXs.map { curveData.evaluate($0) }

        filter.setValue(CIVector(x: CGFloat(sampleXs[0]), y: CGFloat(sampledY[0])), forKey: "inputPoint0")
        filter.setValue(CIVector(x: CGFloat(sampleXs[1]), y: CGFloat(sampledY[1])), forKey: "inputPoint1")
        filter.setValue(CIVector(x: CGFloat(sampleXs[2]), y: CGFloat(sampledY[2])), forKey: "inputPoint2")
        filter.setValue(CIVector(x: CGFloat(sampleXs[3]), y: CGFloat(sampledY[3])), forKey: "inputPoint3")
        filter.setValue(CIVector(x: CGFloat(sampleXs[4]), y: CGFloat(sampledY[4])), forKey: "inputPoint4")

        return filter.outputImage ?? image
    }

    /// Apply per-channel RGB curves using CIColorPolynomial for channel separation.
    private func applyRGBCurves(
        _ image: CIImage,
        red: CurveData?,
        green: CurveData?,
        blue: CurveData?
    ) -> CIImage {
        var current = image

        if let redCurve = red {
            current = applyChannelCurve(current, curveData: redCurve, channel: .red)
        }
        if let greenCurve = green {
            current = applyChannelCurve(current, curveData: greenCurve, channel: .green)
        }
        if let blueCurve = blue {
            current = applyChannelCurve(current, curveData: blueCurve, channel: .blue)
        }

        return current
    }

    /// Apply a tone curve to a single color channel using CIColorPolynomial.
    private func applyChannelCurve(_ image: CIImage, curveData: CurveData, channel: CurveChannel) -> CIImage {
        guard let filter = CIFilter(name: "CIColorPolynomial") else { return image }

        // Sample curve at 4 points and fit a cubic polynomial
        let y0 = curveData.evaluate(0.0)
        let y1 = curveData.evaluate(0.33)
        let y2 = curveData.evaluate(0.66)
        let y3 = curveData.evaluate(1.0)

        // Approximate curve as a + b*x + c*x^2 + d*x^3
        let a = y0
        let d = y3 - 3 * y2 + 3 * y1 - y0
        let c = y2 - 2 * y1 + y0
        let b = y1 - y0 - c / 3

        let coefficients = CIVector(x: CGFloat(a), y: CGFloat(b), z: CGFloat(c), w: CGFloat(d))
        let identity = CIVector(x: 0, y: 1, z: 0, w: 0) // Identity: 0 + 1*x

        filter.setValue(image, forKey: kCIInputImageKey)

        switch channel {
        case .red:
            filter.setValue(coefficients, forKey: "inputRedCoefficients")
            filter.setValue(identity, forKey: "inputGreenCoefficients")
            filter.setValue(identity, forKey: "inputBlueCoefficients")
        case .green:
            filter.setValue(identity, forKey: "inputRedCoefficients")
            filter.setValue(coefficients, forKey: "inputGreenCoefficients")
            filter.setValue(identity, forKey: "inputBlueCoefficients")
        case .blue:
            filter.setValue(identity, forKey: "inputRedCoefficients")
            filter.setValue(identity, forKey: "inputGreenCoefficients")
            filter.setValue(coefficients, forKey: "inputBlueCoefficients")
        case .luminance:
            filter.setValue(coefficients, forKey: "inputRedCoefficients")
            filter.setValue(coefficients, forKey: "inputGreenCoefficients")
            filter.setValue(coefficients, forKey: "inputBlueCoefficients")
        }

        filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputAlphaCoefficients")

        return filter.outputImage ?? image
    }

    // MARK: - Stage 9: LUT

    private func applyLUT(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard let lutRef = grade.lutFilter else { return image }
        guard lutRef.intensity > Self.epsilon else { return image }

        let resolvedPath = resolveLUTPath(lutRef.lutAssetPath)
        guard let path = resolvedPath else {
            Self.logger.warning("LUT file not found: \(lutRef.lutAssetPath, privacy: .public)")
            return image
        }

        guard FileManager.default.fileExists(atPath: path) else {
            Self.logger.warning("LUT file not found at path: \(path, privacy: .public)")
            return image
        }

        guard let (cubeData, cubeDimension) = loadLUTCubeData(from: path, requestedDimension: lutRef.dimension) else {
            Self.logger.error("Failed to load LUT data: \(path, privacy: .public)")
            return image
        }

        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": cubeDimension,
            "inputCubeData": cubeData,
            kCIInputImageKey: image,
            "inputColorSpace": CGColorSpaceCreateDeviceRGB(),
        ]) else {
            return image
        }

        guard let lutResult = filter.outputImage else { return image }

        // Blend with original based on intensity
        if lutRef.intensity < 1.0 - Self.epsilon {
            guard let dissolve = CIFilter(name: "CIDissolveTransition") else { return lutResult }
            dissolve.setValue(image, forKey: kCIInputImageKey)
            dissolve.setValue(lutResult, forKey: kCIInputTargetImageKey)
            dissolve.setValue(lutRef.intensity, forKey: "inputTime")
            return dissolve.outputImage ?? lutResult
        }

        return lutResult
    }

    // MARK: - LUT Path Resolution

    /// Resolve a LUT asset path to an absolute file path.
    private func resolveLUTPath(_ lutPath: String) -> String? {
        if lutPath.hasPrefix("bundled://") {
            let bundleName = lutPath.replacingOccurrences(of: "bundled://", with: "")
            if let path = Bundle.main.path(forResource: bundleName, ofType: nil) {
                return path
            }
            if let path = Bundle.main.path(forResource: bundleName, ofType: "cube") {
                return path
            }
            if let path = Bundle.main.path(forResource: bundleName, ofType: "png") {
                return path
            }
            if let path = Bundle.main.path(forResource: bundleName, ofType: nil, inDirectory: "LUTs") {
                return path
            }
            return nil
        } else if lutPath.hasPrefix("custom://") {
            return lutPath.replacingOccurrences(of: "custom://", with: "")
        } else {
            return lutPath
        }
    }

    // MARK: - LUT Loading

    /// Load LUT cube data from a file, supporting both .cube text format and .png strip images.
    ///
    /// Uses LRU eviction: when the cache exceeds `maxLUTCacheSize`, the least
    /// recently used entry is removed.
    private func loadLUTCubeData(from path: String, requestedDimension: Int) -> (Data, Int)? {
        // Check cache first (and promote to most-recently-used)
        let cached: (Data, Int)? = lutLock.withLock {
            guard let entry = lutCache[path] else { return nil }
            // Promote to end (most recently used)
            if let idx = lutAccessOrder.firstIndex(of: path) {
                lutAccessOrder.remove(at: idx)
            }
            lutAccessOrder.append(path)
            return (entry.data, entry.dimension)
        }
        if let cached { return cached }

        let ext = (path as NSString).pathExtension.lowercased()
        var result: (Data, Int)?

        if ext == "cube" || ext == "3dl" {
            result = parseCubeFile(at: path)
        } else {
            result = extractCubeDataFromImage(at: path, dimension: requestedDimension)
        }

        // Cache the result with LRU eviction
        if let result {
            lutLock.withLock {
                lutCache[path] = (data: result.0, dimension: result.1)
                lutAccessOrder.append(path)

                // Evict least recently used entries if over limit
                while lutCache.count > Self.maxLUTCacheSize,
                      let oldest = lutAccessOrder.first {
                    lutAccessOrder.removeFirst()
                    lutCache.removeValue(forKey: oldest)
                }
            }
        }

        return result
    }

    /// Parse a .cube format LUT file into float RGBA cube data.
    private func parseCubeFile(at path: String) -> (Data, Int)? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        var dimension = 0
        var rgbData: [Float] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let dim = Int(parts[1]) {
                    dimension = dim
                }
                continue
            }

            if trimmed.hasPrefix("TITLE") || trimmed.hasPrefix("DOMAIN_MIN") ||
               trimmed.hasPrefix("DOMAIN_MAX") || trimmed.hasPrefix("LUT_1D_SIZE") {
                continue
            }

            let components = trimmed.split(separator: " ")
            if components.count >= 3,
               let r = Float(components[0]),
               let g = Float(components[1]),
               let b = Float(components[2]) {
                rgbData.append(r)
                rgbData.append(g)
                rgbData.append(b)
            }
        }

        guard dimension > 0 else { return nil }

        let expectedCount = dimension * dimension * dimension * 3
        guard rgbData.count >= expectedCount else { return nil }

        // Convert RGB triples to RGBA float array
        let totalEntries = dimension * dimension * dimension
        var cubeData = [Float](repeating: 0, count: totalEntries * 4)

        for i in 0..<totalEntries {
            cubeData[i * 4 + 0] = rgbData[i * 3 + 0]
            cubeData[i * 4 + 1] = rgbData[i * 3 + 1]
            cubeData[i * 4 + 2] = rgbData[i * 3 + 2]
            cubeData[i * 4 + 3] = 1.0
        }

        let data = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        return (data, dimension)
    }

    /// Extract cube data from a PNG strip LUT image.
    private func extractCubeDataFromImage(at path: String, dimension: Int) -> (Data, Int)? {
        guard let lutImage = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let context = EffectPipeline.sharedContext
        let totalEntries = dimension * dimension * dimension

        let lutExtent = lutImage.extent
        guard lutExtent.width > 0, lutExtent.height > 0 else { return nil }
        guard Int(lutExtent.width) * Int(lutExtent.height) >= totalEntries else { return nil }

        let bytesPerRow = Int(lutExtent.width) * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * Int(lutExtent.height))

        context.render(lutImage, toBitmap: &pixelData, rowBytes: bytesPerRow,
                      bounds: lutExtent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        var cubeData = [Float](repeating: 0, count: totalEntries * 4)
        let imageWidth = Int(lutExtent.width)

        for z in 0..<dimension {
            for y in 0..<dimension {
                for x in 0..<dimension {
                    let pixelX = x + z * dimension
                    let pixelY = y
                    let pixelIndex = (pixelY * imageWidth + pixelX) * 4

                    guard pixelIndex + 3 < pixelData.count else { continue }

                    let cubeIndex = (z * dimension * dimension + y * dimension + x) * 4
                    cubeData[cubeIndex + 0] = Float(pixelData[pixelIndex + 0]) / 255.0
                    cubeData[cubeIndex + 1] = Float(pixelData[pixelIndex + 1]) / 255.0
                    cubeData[cubeIndex + 2] = Float(pixelData[pixelIndex + 2]) / 255.0
                    cubeData[cubeIndex + 3] = 1.0
                }
            }
        }

        let data = Data(bytes: cubeData, count: cubeData.count * MemoryLayout<Float>.size)
        return (data, dimension)
    }

    // MARK: - Stage 10: Sharpen / Clarity

    private func applySharpenClarity(_ image: CIImage, grade: ColorGrade) -> CIImage {
        var current = image

        if abs(grade.sharpness) > Self.epsilon {
            guard let filter = CIFilter(name: "CISharpenLuminance") else { return current }
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(grade.sharpness * 2.0, forKey: kCIInputSharpnessKey)
            filter.setValue(1.5, forKey: kCIInputRadiusKey)
            current = filter.outputImage ?? current
        }

        if abs(grade.clarity) > Self.epsilon {
            guard let filter = CIFilter(name: "CIUnsharpMask") else { return current }
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(abs(grade.clarity) * 1.5, forKey: kCIInputIntensityKey)
            filter.setValue(10.0, forKey: kCIInputRadiusKey)
            current = filter.outputImage ?? current
        }

        return current
    }

    // MARK: - Stage 11: Vignette

    private func applyVignette(_ image: CIImage, grade: ColorGrade) -> CIImage {
        guard abs(grade.vignetteIntensity) > Self.epsilon else { return image }

        guard let filter = CIFilter(name: "CIVignetteEffect") else {
            guard let basicFilter = CIFilter(name: "CIVignette") else { return image }
            basicFilter.setValue(image, forKey: kCIInputImageKey)
            basicFilter.setValue(grade.vignetteIntensity * 2.0, forKey: kCIInputIntensityKey)
            basicFilter.setValue(grade.vignetteRadius, forKey: kCIInputRadiusKey)
            return basicFilter.outputImage ?? image
        }

        let extent = image.extent
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
        filter.setValue(grade.vignetteIntensity * 2.0, forKey: kCIInputIntensityKey)
        let maxDim = max(extent.width, extent.height)
        filter.setValue(grade.vignetteRadius * maxDim * 0.5, forKey: kCIInputRadiusKey)
        filter.setValue(grade.vignetteSoftness, forKey: "inputFalloff")

        return filter.outputImage ?? image
    }
}
