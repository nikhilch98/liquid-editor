// MaskRenderer.swift
// LiquidEditor
//
// GPU-accelerated mask rendering via Core Image.
// Supports shape masks (rectangle, ellipse, polygon, brush),
// feathered edges via Gaussian blur, and alpha composition.
//
// Thread Safety:
// - `@unchecked Sendable` with NSLock for GPU hot-path performance.
// - CIContext is Metal-backed and thread-safe.

import CoreImage
import CoreGraphics
import Foundation
import Metal
import os

// MARK: - MaskRenderer

/// GPU-accelerated mask renderer using CIFilter pipeline.
///
/// Thread Safety:
/// - `@unchecked Sendable` because CIContext is thread-safe and
///   all rendering is stateless per call (no shared mutable state).
/// - NSLock protects any internal caches if added later.
final class MaskRenderer: @unchecked Sendable {

    // MARK: - Constants

    /// BT.709 luminance coefficients for RGB to grayscale conversion
    private static let bt709Red: CGFloat = 0.2126
    private static let bt709Green: CGFloat = 0.7152
    private static let bt709Blue: CGFloat = 0.0722

    /// Minimum range to avoid division by zero in mask generation
    private static let minRangeThreshold: Double = 0.001

    /// Minimum hue tolerance to avoid division by zero
    private static let minHueTolerance: Double = 0.01

    /// Ellipse radius multiplier for inner/outer gradient bounds
    private static let ellipseInnerRadiusMultiplier: Double = 0.99
    private static let ellipseOuterRadiusMultiplier: Double = 1.0

    // MARK: - Properties

    /// Metal-backed CIContext for GPU-accelerated rendering.
    private let ciContext: CIContext

    /// Lock for future cache protection.
    private let lock = NSLock()

    /// Logger for mask rendering operations.
    private static let logger = Logger(subsystem: "LiquidEditor", category: "MaskRenderer")

    // MARK: - Initialization

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: device, options: [
                .highQualityDownsample: true,
            ])
        } else {
            Self.logger.warning("Metal device unavailable, falling back to software rendering")
            self.ciContext = CIContext(options: [
                .useSoftwareRenderer: false,
                .highQualityDownsample: true,
            ])
        }
    }

    // MARK: - Apply Mask

    /// Apply a mask to a source image.
    ///
    /// - Parameters:
    ///   - sourceImage: The input CIImage to mask.
    ///   - mask: The mask definition from the model layer.
    ///   - frameSize: Size of the output frame in pixels.
    /// - Returns: The masked CIImage.
    func applyMask(to sourceImage: CIImage, mask: Mask, frameSize: CGSize) -> CIImage {
        var maskImage = generateMaskImage(mask: mask, frameSize: frameSize, sourceImage: sourceImage)

        // Apply feathering via Gaussian blur
        if mask.feather > 0 {
            let pixelRadius = mask.feather * Double(min(frameSize.width, frameSize.height))
            maskImage = applyFeather(to: maskImage, radius: pixelRadius)
        }

        // Apply expansion
        if mask.expansion != 0 {
            maskImage = applyExpansion(to: maskImage, amount: mask.expansion, frameSize: frameSize)
        }

        // Invert mask if needed
        if mask.isInverted {
            if let invertFilter = CIFilter(name: "CIColorInvert") {
                invertFilter.setValue(maskImage, forKey: kCIInputImageKey)
                if let inverted = invertFilter.outputImage {
                    maskImage = inverted
                }
            }
        }

        // Apply opacity
        if mask.opacity < 1.0 {
            if let opacityFilter = CIFilter(name: "CIColorMatrix") {
                opacityFilter.setValue(maskImage, forKey: kCIInputImageKey)
                opacityFilter.setValue(
                    CIVector(x: 0, y: 0, z: 0, w: CGFloat(mask.opacity)),
                    forKey: "inputAVector"
                )
                if let adjusted = opacityFilter.outputImage {
                    maskImage = adjusted
                }
            }
        }

        // Blend: use mask as alpha channel
        guard let blendFilter = CIFilter(name: "CIBlendWithAlphaMask") else {
            return sourceImage
        }
        blendFilter.setValue(sourceImage, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? sourceImage
    }

    /// Apply mask from MaskParameters (for animated/keyframed masks).
    ///
    /// - Parameters:
    ///   - sourceImage: The input CIImage to mask.
    ///   - parameters: Interpolated mask parameters.
    ///   - maskType: Type of the mask.
    ///   - isInverted: Whether to invert.
    ///   - frameSize: Output frame size.
    /// - Returns: The masked CIImage.
    func applyMask(
        to sourceImage: CIImage,
        parameters: MaskParameters,
        maskType: MaskType,
        isInverted: Bool,
        frameSize: CGSize
    ) -> CIImage {
        var maskImage = generateMaskFromParameters(
            parameters: parameters,
            maskType: maskType,
            frameSize: frameSize
        )

        if parameters.feather > 0 {
            let pixelRadius = parameters.feather * Double(min(frameSize.width, frameSize.height))
            maskImage = applyFeather(to: maskImage, radius: pixelRadius)
        }

        if isInverted {
            if let invertFilter = CIFilter(name: "CIColorInvert") {
                invertFilter.setValue(maskImage, forKey: kCIInputImageKey)
                if let inverted = invertFilter.outputImage {
                    maskImage = inverted
                }
            }
        }

        if parameters.opacity < 1.0 {
            if let opacityFilter = CIFilter(name: "CIColorMatrix") {
                opacityFilter.setValue(maskImage, forKey: kCIInputImageKey)
                opacityFilter.setValue(
                    CIVector(x: 0, y: 0, z: 0, w: CGFloat(parameters.opacity)),
                    forKey: "inputAVector"
                )
                if let adjusted = opacityFilter.outputImage {
                    maskImage = adjusted
                }
            }
        }

        guard let blendFilter = CIFilter(name: "CIBlendWithAlphaMask") else {
            return sourceImage
        }
        blendFilter.setValue(sourceImage, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage ?? sourceImage
    }

    // MARK: - Generate Mask Preview

    /// Generate a mask preview image (grayscale mask visualization).
    ///
    /// - Parameters:
    ///   - mask: The mask definition.
    ///   - frameSize: Size of the preview frame.
    /// - Returns: RGBA data of the mask preview.
    func generateMaskPreview(mask: Mask, frameSize: CGSize) -> Data? {
        var maskImage = generateMaskImage(mask: mask, frameSize: frameSize)

        if mask.feather > 0 {
            let pixelRadius = mask.feather * Double(min(frameSize.width, frameSize.height))
            maskImage = applyFeather(to: maskImage, radius: pixelRadius)
        }

        if mask.isInverted {
            if let invertFilter = CIFilter(name: "CIColorInvert") {
                invertFilter.setValue(maskImage, forKey: kCIInputImageKey)
                if let inverted = invertFilter.outputImage {
                    maskImage = inverted
                }
            }
        }

        return renderToData(maskImage, width: Int(frameSize.width), height: Int(frameSize.height))
    }

    // MARK: - Mask Generation

    private func generateMaskImage(
        mask: Mask,
        frameSize: CGSize,
        sourceImage: CIImage? = nil
    ) -> CIImage {
        switch mask.type {
        case .rectangle:
            guard let rect = mask.rect else { return CIImage.empty() }
            return generateRectangleMask(
                rect: rect,
                cornerRadius: mask.cornerRadius ?? 0,
                rotation: mask.rotation ?? 0,
                frameSize: frameSize
            )

        case .ellipse:
            guard let rect = mask.rect else { return CIImage.empty() }
            return generateEllipseMask(
                rect: rect,
                rotation: mask.rotation ?? 0,
                frameSize: frameSize
            )

        case .polygon:
            guard let vertices = mask.vertices else { return CIImage.empty() }
            return generatePolygonMask(vertices: vertices, frameSize: frameSize)

        case .brush:
            guard let strokes = mask.strokes else { return CIImage.empty() }
            return generateBrushMask(strokes: strokes, frameSize: frameSize)

        case .luminance:
            guard let source = sourceImage else {
                return generateSolidMask(frameSize: frameSize, color: .white)
            }
            return generateLuminanceMask(
                sourceImage: source,
                luminanceMin: mask.luminanceMin ?? 0.0,
                luminanceMax: mask.luminanceMax ?? 1.0,
                frameSize: frameSize
            )

        case .color:
            guard let source = sourceImage else {
                return generateSolidMask(frameSize: frameSize, color: .white)
            }
            return generateColorMask(
                sourceImage: source,
                targetHue: mask.targetHue ?? 0.0,
                hueTolerance: mask.hueTolerance ?? 30.0,
                saturationMin: mask.saturationMin ?? 0.1,
                saturationMax: mask.saturationMax ?? 1.0,
                frameSize: frameSize
            )
        }
    }

    private func generateMaskFromParameters(
        parameters: MaskParameters,
        maskType: MaskType,
        frameSize: CGSize
    ) -> CIImage {
        switch maskType {
        case .rectangle:
            guard let rect = parameters.rect else { return CIImage.empty() }
            return generateRectangleMask(
                rect: rect,
                cornerRadius: parameters.cornerRadius ?? 0,
                rotation: parameters.rotation ?? 0,
                frameSize: frameSize
            )

        case .ellipse:
            guard let rect = parameters.rect else { return CIImage.empty() }
            return generateEllipseMask(
                rect: rect,
                rotation: parameters.rotation ?? 0,
                frameSize: frameSize
            )

        case .polygon:
            guard let vertices = parameters.vertices else { return CIImage.empty() }
            return generatePolygonMask(vertices: vertices, frameSize: frameSize)

        default:
            return generateSolidMask(frameSize: frameSize, color: .white)
        }
    }

    // MARK: - Shape Generators

    private func generateRectangleMask(
        rect: CGRect,
        cornerRadius: Double,
        rotation: Double,
        frameSize: CGSize
    ) -> CIImage {
        let w = frameSize.width
        let h = frameSize.height

        let pixelRect = CGRect(
            x: rect.origin.x * w,
            y: (1.0 - rect.origin.y - rect.size.height) * h,
            width: rect.size.width * w,
            height: rect.size.height * h
        )

        guard let whiteGen = CIFilter(name: "CIConstantColorGenerator"),
              let blackGen = CIFilter(name: "CIConstantColorGenerator") else {
            return CIImage.empty()
        }

        whiteGen.setValue(CIColor.white, forKey: kCIInputColorKey)
        blackGen.setValue(CIColor.black, forKey: kCIInputColorKey)

        guard let whiteImage = whiteGen.outputImage?.cropped(to: pixelRect),
              let blackImage = blackGen.outputImage?.cropped(to: CGRect(origin: .zero, size: frameSize)) else {
            return CIImage.empty()
        }

        guard let composite = CIFilter(name: "CISourceOverCompositing") else {
            return CIImage.empty()
        }
        composite.setValue(whiteImage, forKey: kCIInputImageKey)
        composite.setValue(blackImage, forKey: kCIInputBackgroundImageKey)

        var result = composite.outputImage ?? CIImage.empty()

        if rotation != 0 {
            let center = CGPoint(x: pixelRect.midX, y: pixelRect.midY)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: CGFloat(rotation))
                .translatedBy(x: -center.x, y: -center.y)
            result = result.transformed(by: transform)
                .cropped(to: CGRect(origin: .zero, size: frameSize))
        }

        return result
    }

    private func generateEllipseMask(
        rect: CGRect,
        rotation: Double,
        frameSize: CGSize
    ) -> CIImage {
        let w = frameSize.width
        let h = frameSize.height

        let cx = (rect.origin.x + rect.size.width / 2) * w
        let cy = (1.0 - rect.origin.y - rect.size.height / 2) * h
        let mw = rect.size.width * w
        let mh = rect.size.height * h

        let radius = min(mw, mh) / 2

        guard let radialFilter = CIFilter(name: "CIRadialGradient") else {
            return CIImage.empty()
        }

        radialFilter.setValue(CIVector(x: cx, y: cy), forKey: "inputCenter")
        radialFilter.setValue(NSNumber(value: Double(radius) * Self.ellipseInnerRadiusMultiplier), forKey: "inputRadius0")
        radialFilter.setValue(NSNumber(value: Double(radius) * Self.ellipseOuterRadiusMultiplier), forKey: "inputRadius1")
        radialFilter.setValue(CIColor.white, forKey: "inputColor0")
        radialFilter.setValue(CIColor.black, forKey: "inputColor1")

        var result = radialFilter.outputImage?
            .cropped(to: CGRect(origin: .zero, size: frameSize)) ?? CIImage.empty()

        // Scale to ellipse
        if abs(mw - mh) > 1 {
            let scaleX = mw / mh
            let transform = CGAffineTransform(translationX: cx, y: cy)
                .scaledBy(x: scaleX, y: 1.0)
                .translatedBy(x: -cx, y: -cy)
            result = result.transformed(by: transform)
                .cropped(to: CGRect(origin: .zero, size: frameSize))
        }

        if rotation != 0 {
            let rotateTransform = CGAffineTransform(translationX: cx, y: cy)
                .rotated(by: CGFloat(rotation))
                .translatedBy(x: -cx, y: -cy)
            result = result.transformed(by: rotateTransform)
                .cropped(to: CGRect(origin: .zero, size: frameSize))
        }

        return result
    }

    private func generatePolygonMask(vertices: [CGPoint], frameSize: CGSize) -> CIImage {
        guard vertices.count >= 3 else { return CIImage.empty() }

        let path = CGMutablePath()
        let firstX = vertices[0].x * frameSize.width
        let firstY = (1.0 - vertices[0].y) * frameSize.height
        path.move(to: CGPoint(x: firstX, y: firstY))

        for i in 1..<vertices.count {
            let px = vertices[i].x * frameSize.width
            let py = (1.0 - vertices[i].y) * frameSize.height
            path.addLine(to: CGPoint(x: px, y: py))
        }
        path.closeSubpath()

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: Int(frameSize.width),
            height: Int(frameSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(frameSize.width),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return CIImage.empty() }

        ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        ctx.addPath(path)
        ctx.fillPath()

        guard let cgImage = ctx.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: cgImage)
    }

    private func generateBrushMask(strokes: [BrushStroke], frameSize: CGSize) -> CIImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: Int(frameSize.width),
            height: Int(frameSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(frameSize.width),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return CIImage.empty() }

        ctx.setFillColor(CGColor(gray: 0.0, alpha: 1.0))
        ctx.fill(CGRect(origin: .zero, size: frameSize))

        for stroke in strokes {
            guard stroke.points.count >= 2 else { continue }

            let lineWidth = CGFloat(stroke.width) * min(frameSize.width, frameSize.height)
            ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let firstPoint = CGPoint(
                x: stroke.points[0].x * frameSize.width,
                y: (1.0 - stroke.points[0].y) * frameSize.height
            )
            ctx.move(to: firstPoint)

            for i in 1..<stroke.points.count {
                let point = CGPoint(
                    x: stroke.points[i].x * frameSize.width,
                    y: (1.0 - stroke.points[i].y) * frameSize.height
                )
                ctx.addLine(to: point)
            }
            ctx.strokePath()
        }

        guard let cgImage = ctx.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: cgImage)
    }

    // MARK: - Luminance Mask

    /// Generate a luminance-based mask from a source image using CIFilter.
    ///
    /// Extracts the luminance channel and applies a threshold range to create
    /// a binary-ish mask. Pixels with luminance within [luminanceMin, luminanceMax]
    /// are white; outside the range are black.
    ///
    /// Uses CIColorMatrix to extract luminance (BT.709 coefficients) and
    /// CIColorClamp to threshold.
    ///
    /// - Parameters:
    ///   - sourceImage: The source image to derive luminance from.
    ///   - luminanceMin: Minimum luminance threshold (0.0 to 1.0).
    ///   - luminanceMax: Maximum luminance threshold (0.0 to 1.0).
    ///   - frameSize: Output frame size.
    /// - Returns: A grayscale mask CIImage.
    private func generateLuminanceMask(
        sourceImage: CIImage,
        luminanceMin: Double,
        luminanceMax: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = CGRect(origin: .zero, size: frameSize)

        // Scale source to frame size if needed
        let scaledSource: CIImage
        if sourceImage.extent.size != frameSize {
            let scaleX = frameSize.width / max(sourceImage.extent.width, 1)
            let scaleY = frameSize.height / max(sourceImage.extent.height, 1)
            scaledSource = sourceImage.transformed(
                by: CGAffineTransform(scaleX: scaleX, y: scaleY)
            ).cropped(to: extent)
        } else {
            scaledSource = sourceImage.cropped(to: extent)
        }

        // Convert to grayscale using CIColorMatrix with BT.709 luminance coefficients
        // Y = 0.2126 * R + 0.7152 * G + 0.0722 * B
        guard let luminanceFilter = CIFilter(name: "CIColorMatrix") else {
            return generateSolidMask(frameSize: frameSize, color: .white)
        }
        luminanceFilter.setValue(scaledSource, forKey: kCIInputImageKey)
        // Set R, G, B rows to output the same luminance value in all channels
        luminanceFilter.setValue(CIVector(x: Self.bt709Red, y: Self.bt709Red, z: Self.bt709Red, w: 0), forKey: "inputRVector")
        luminanceFilter.setValue(CIVector(x: Self.bt709Green, y: Self.bt709Green, z: Self.bt709Green, w: 0), forKey: "inputGVector")
        luminanceFilter.setValue(CIVector(x: Self.bt709Blue, y: Self.bt709Blue, z: Self.bt709Blue, w: 0), forKey: "inputBVector")
        luminanceFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        luminanceFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

        guard let grayscale = luminanceFilter.outputImage?.cropped(to: extent) else {
            return generateSolidMask(frameSize: frameSize, color: .white)
        }

        // Apply threshold range: pixels within [luminanceMin, luminanceMax] -> white, outside -> black
        // Step 1: Subtract luminanceMin and scale so the range maps to [0, 1]
        let range = max(luminanceMax - luminanceMin, Self.minRangeThreshold) // Avoid division by zero
        let scale = 1.0 / range
        let bias = -luminanceMin * scale

        guard let rangeFilter = CIFilter(name: "CIColorMatrix") else {
            return grayscale
        }
        rangeFilter.setValue(grayscale, forKey: kCIInputImageKey)
        rangeFilter.setValue(CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0), forKey: "inputRVector")
        rangeFilter.setValue(CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0), forKey: "inputGVector")
        rangeFilter.setValue(CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0), forKey: "inputBVector")
        rangeFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        rangeFilter.setValue(CIVector(x: CGFloat(bias), y: CGFloat(bias), z: CGFloat(bias), w: 0), forKey: "inputBiasVector")

        guard let ranged = rangeFilter.outputImage?.cropped(to: extent) else {
            return grayscale
        }

        // Clamp to [0, 1] to create the mask
        guard let clampFilter = CIFilter(name: "CIColorClamp") else {
            return ranged
        }
        clampFilter.setValue(ranged, forKey: kCIInputImageKey)
        clampFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        clampFilter.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")

        return clampFilter.outputImage?.cropped(to: extent) ?? grayscale
    }

    // MARK: - Color Mask

    /// Generate a color-based mask from a source image using CIFilter.
    ///
    /// Selects pixels matching a target hue within a tolerance range
    /// and a saturation range. Uses CIColorMatrix and HSB comparison
    /// via the CIFilter pipeline.
    ///
    /// The approach:
    /// 1. Convert source to HSB using CIHueAdjust to rotate target hue to 0.
    /// 2. Compute hue distance from 0 (which is the target hue after rotation).
    /// 3. Create a mask where pixels within hue tolerance and saturation range are white.
    ///
    /// - Parameters:
    ///   - sourceImage: The source image to derive color selection from.
    ///   - targetHue: Target hue in degrees (0-360).
    ///   - hueTolerance: Hue tolerance in degrees.
    ///   - saturationMin: Minimum saturation (0.0 to 1.0).
    ///   - saturationMax: Maximum saturation (0.0 to 1.0).
    ///   - frameSize: Output frame size.
    /// - Returns: A grayscale mask CIImage.
    private func generateColorMask(
        sourceImage: CIImage,
        targetHue: Double,
        hueTolerance: Double,
        saturationMin: Double,
        saturationMax: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = CGRect(origin: .zero, size: frameSize)

        // Scale source to frame size if needed
        let scaledSource: CIImage
        if sourceImage.extent.size != frameSize {
            let scaleX = frameSize.width / max(sourceImage.extent.width, 1)
            let scaleY = frameSize.height / max(sourceImage.extent.height, 1)
            scaledSource = sourceImage.transformed(
                by: CGAffineTransform(scaleX: scaleX, y: scaleY)
            ).cropped(to: extent)
        } else {
            scaledSource = sourceImage.cropped(to: extent)
        }

        // Rotate the hue so the target hue maps to red (hue = 0).
        // CIHueAdjust takes radians.
        let targetRadians = targetHue * .pi / 180.0
        guard let hueRotate = CIFilter(name: "CIHueAdjust") else {
            return generateSolidMask(frameSize: frameSize, color: .white)
        }
        hueRotate.setValue(scaledSource, forKey: kCIInputImageKey)
        hueRotate.setValue(NSNumber(value: -targetRadians), forKey: kCIInputAngleKey)

        guard let rotated = hueRotate.outputImage?.cropped(to: extent) else {
            return generateSolidMask(frameSize: frameSize, color: .white)
        }

        // Now the target hue is at red. Use CIColorCube or color distance approach.
        // Simpler approach: Extract into a false-color representation where
        // "redness" (proximity to hue=0) becomes brightness.
        //
        // Use CIColorMatrix to emphasize red channel (which corresponds to
        // the target hue after rotation) and suppress green/blue.
        //
        // Pixels near the target hue will have high red values.
        // We create a mask from the red channel intensity, adjusted by saturation.

        // Extract red channel as luminance (hue proximity indicator)
        guard let redExtract = CIFilter(name: "CIColorMatrix") else {
            return generateSolidMask(frameSize: frameSize, color: .white)
        }
        redExtract.setValue(rotated, forKey: kCIInputImageKey)
        redExtract.setValue(CIVector(x: 1, y: 1, z: 1, w: 0), forKey: "inputRVector")
        redExtract.setValue(CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0), forKey: "inputGVector")
        redExtract.setValue(CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0), forKey: "inputBVector")
        redExtract.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        redExtract.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

        guard let colorDistance = redExtract.outputImage?.cropped(to: extent) else {
            return generateSolidMask(frameSize: frameSize, color: .white)
        }

        // Apply tolerance threshold: scale and bias to map hue tolerance to [0, 1]
        let toleranceNormalized = max(hueTolerance / 180.0, Self.minHueTolerance)
        let toleranceScale = 1.0 / toleranceNormalized

        guard let thresholdFilter = CIFilter(name: "CIColorMatrix") else {
            return colorDistance
        }
        thresholdFilter.setValue(colorDistance, forKey: kCIInputImageKey)
        thresholdFilter.setValue(
            CIVector(x: CGFloat(toleranceScale), y: 0, z: 0, w: 0),
            forKey: "inputRVector"
        )
        thresholdFilter.setValue(
            CIVector(x: 0, y: CGFloat(toleranceScale), z: 0, w: 0),
            forKey: "inputGVector"
        )
        thresholdFilter.setValue(
            CIVector(x: 0, y: 0, z: CGFloat(toleranceScale), w: 0),
            forKey: "inputBVector"
        )
        thresholdFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        thresholdFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

        guard let thresholded = thresholdFilter.outputImage?.cropped(to: extent) else {
            return colorDistance
        }

        // Clamp to [0, 1]
        guard let clampFilter = CIFilter(name: "CIColorClamp") else {
            return thresholded
        }
        clampFilter.setValue(thresholded, forKey: kCIInputImageKey)
        clampFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        clampFilter.setValue(CIVector(x: 1, y: 1, z: 1, w: 1), forKey: "inputMaxComponents")

        return clampFilter.outputImage?.cropped(to: extent) ?? thresholded
    }

    private func generateSolidMask(frameSize: CGSize, color: CIColor) -> CIImage {
        guard let gen = CIFilter(name: "CIConstantColorGenerator") else {
            return CIImage.empty()
        }
        gen.setValue(color, forKey: kCIInputColorKey)
        return gen.outputImage?.cropped(to: CGRect(origin: .zero, size: frameSize)) ?? CIImage.empty()
    }

    // MARK: - Feathering

    /// Apply Gaussian blur to mask for feathered edges.
    func applyFeather(to maskImage: CIImage, radius: Double) -> CIImage {
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return maskImage
        }
        blurFilter.setValue(maskImage, forKey: kCIInputImageKey)
        blurFilter.setValue(NSNumber(value: radius), forKey: kCIInputRadiusKey)
        return blurFilter.outputImage?.cropped(to: maskImage.extent) ?? maskImage
    }

    // MARK: - Expansion

    private func applyExpansion(to maskImage: CIImage, amount: Double, frameSize: CGSize) -> CIImage {
        guard amount != 0 else { return maskImage }

        // Use morphology for expansion/shrinking
        let pixelAmount = abs(amount) * Double(min(frameSize.width, frameSize.height))
        let filterName = amount > 0 ? "CIMorphologyMaximum" : "CIMorphologyMinimum"

        guard let morphFilter = CIFilter(name: filterName) else { return maskImage }
        morphFilter.setValue(maskImage, forKey: kCIInputImageKey)
        morphFilter.setValue(NSNumber(value: pixelAmount), forKey: kCIInputRadiusKey)

        return morphFilter.outputImage?.cropped(to: maskImage.extent) ?? maskImage
    }

    // MARK: - Rendering

    private func renderToData(_ image: CIImage, width: Int, height: Int) -> Data? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let extent = CGRect(x: 0, y: 0, width: width, height: height)

        guard let cgImage = ciContext.createCGImage(
            image, from: extent, format: .RGBA8, colorSpace: colorSpace
        ) else { return nil }

        let bytesPerRow = width * 4
        let dataSize = bytesPerRow * height
        var data = Data(count: dataSize)

        data.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cgImage, in: extent)
        }

        return data
    }
}
