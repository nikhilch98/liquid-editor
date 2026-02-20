//
//  ReIDExtractor.swift
//  LiquidEditor
//
//  CoreML wrapper for OSNet person re-identification model.
//  Extracts 512-dimensional appearance embeddings from cropped person images.
//
//  Model: OSNet (Omni-Scale Network) - lightweight ReID model
//  Input: 256x128 RGB image (person crop)
//  Output: 512-dim normalized feature vector
//
//

import CoreImage
import CoreML
import Foundation
import os
import Vision

// MARK: - ReID Error

/// Error types for ReID operations.
enum ReIDError: Error {
    case modelNotLoaded
    case imageProcessingFailed
    case inferenceError(String)
    case invalidOutput
    case poorQualityCrop
}

// MARK: - Bounding Box Quality Assessment

/// Quality assessment result for a bounding box crop.
struct BoundingBoxQuality: Sendable {
    /// Ratio of visible area to total bounding box area (0-1).
    let visibilityRatio: Float

    /// Whether this crop is valid for embedding extraction.
    let isValid: Bool

    /// Overall quality score (0-1).
    let qualityScore: Float

    /// Minimum visibility ratio for valid embedding.
    static let minVisibilityRatio: Float = 0.4

    /// Minimum bounding box width (as fraction of frame).
    static let minWidth: CGFloat = 0.05

    /// Minimum bounding box height (as fraction of frame).
    static let minHeight: CGFloat = 0.10
}

// MARK: - Lighting Assessment

/// Assessment of lighting conditions for a frame or crop.
struct LightingAssessment: Sendable {
    /// Whether strobe lighting is detected (rapid brightness changes).
    let isStrobe: Bool

    /// Average brightness (0-1).
    let avgBrightness: Float

    /// Brightness variance (high = uneven lighting).
    let brightnessVariance: Float

    /// Whether lighting is considered extreme (very dark or very bright).
    let isExtreme: Bool

    /// Suggested preprocessing intensity (0-1).
    var preprocessingIntensity: Float {
        if isStrobe { return 0.8 }
        if isExtreme { return 0.6 }
        if brightnessVariance > 0.2 { return 0.4 }
        return 0.0
    }
}

// MARK: - ReIDExtractor

/// OSNet-based person re-identification feature extractor.
/// Enhanced with lighting-robust preprocessing for dance videos.
///
/// Thread Safety: `@unchecked Sendable` because:
/// - `model`, `rawModel`, `isReady`, `cropBufferPool` are set once during `init()`
///   and never mutated afterward -- safe for concurrent reads after construction.
/// - `previousBrightness` is mutable state protected by `brightnessLock`.
/// - `ciContext` is thread-safe per Apple documentation.
final class ReIDExtractor: @unchecked Sendable {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "ReIDExtractor")

    // MARK: - Configuration

    /// Expected input size for OSNet.
    static let inputWidth = 128
    static let inputHeight = 256

    /// Output embedding dimension.
    static let embeddingDimension = 512

    // MARK: - Model

    /// CoreML model instance (Vision-wrapped).
    /// Set once during init via loadModel(); never mutated afterward.
    private var model: VNCoreMLModel?

    /// Raw CoreML model for direct inference.
    /// Set once during init via loadModel(); never mutated afterward.
    private var rawModel: MLModel?

    /// Whether the model is loaded and ready.
    /// Set once during init via loadModel(); never mutated afterward.
    private(set) var isReady: Bool = false

    /// Shared instance for convenience.
    static let shared = ReIDExtractor()

    /// CIContext for image processing (reused for performance, thread-safe per Apple docs).
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Reusable pixel buffer pool for fixed-size ReID crops (128x256 BGRA).
    /// Set once during init via loadModel(); never mutated afterward.
    private var cropBufferPool: CVPixelBufferPool?

    // MARK: - Initialization

    init() {
        loadModel()
    }

    /// Load the CoreML model.
    private func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "OSNetReID", withExtension: "mlmodelc") else {
            Self.logger.warning("Model not found in bundle. ReID will be disabled.")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all

            let mlModel = try MLModel(contentsOf: modelURL, configuration: config)
            model = try VNCoreMLModel(for: mlModel)
            rawModel = mlModel
            isReady = true

            initCropBufferPool()

            Self.logger.info("Model loaded successfully")
        } catch {
            Self.logger.error("Failed to load model: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Initialize the CVPixelBufferPool for fixed-size crop outputs.
    private func initCropBufferPool() {
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 2,
        ]
        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.inputWidth,
            kCVPixelBufferHeightKey as String: Self.inputHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &pool)
        cropBufferPool = pool
    }

    // MARK: - Bounding Box Quality Assessment

    /// Assess the quality of a bounding box for embedding extraction.
    /// - Parameter boundingBox: Normalized bounding box (0-1 coordinates).
    /// - Returns: Quality assessment with visibility ratio and validity.
    func assessBoundingBoxQuality(_ boundingBox: CGRect) -> BoundingBoxQuality {
        let leftClip = max(0, -boundingBox.minX)
        let rightClip = max(0, boundingBox.maxX - 1.0)
        let topClip = max(0, -boundingBox.minY)
        let bottomClip = max(0, boundingBox.maxY - 1.0)

        let visibleWidth = max(0, boundingBox.width - leftClip - rightClip)
        let visibleHeight = max(0, boundingBox.height - topClip - bottomClip)

        let totalArea = boundingBox.width * boundingBox.height
        let visibleArea = visibleWidth * visibleHeight
        let visibilityRatio = totalArea > 0 ? Float(visibleArea / totalArea) : 0

        let meetsMinWidth = boundingBox.width >= BoundingBoxQuality.minWidth
        let meetsMinHeight = boundingBox.height >= BoundingBoxQuality.minHeight
        let meetsMinVisibility = visibilityRatio >= BoundingBoxQuality.minVisibilityRatio

        let isValid = meetsMinWidth && meetsMinHeight && meetsMinVisibility

        let sizeScore = min(1.0, Float(boundingBox.width * boundingBox.height) / 0.1)
        let qualityScore = visibilityRatio * 0.7 + sizeScore * 0.3

        return BoundingBoxQuality(
            visibilityRatio: visibilityRatio,
            isValid: isValid,
            qualityScore: qualityScore
        )
    }

    // MARK: - Lighting Assessment & Preprocessing

    /// Previous frame brightness for strobe detection.
    /// Protected by `brightnessLock` for thread-safe access.
    private var previousBrightness: Float = 0.5

    /// Lock protecting mutable `previousBrightness` state.
    private let brightnessLock = NSLock()

    /// Assess lighting conditions of a cropped image.
    /// - Parameter image: CIImage to assess.
    /// - Returns: Lighting assessment with strobe detection and brightness metrics.
    func assessLighting(_ image: CIImage) -> LightingAssessment {
        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 else {
            return LightingAssessment(isStrobe: false, avgBrightness: 0.5, brightnessVariance: 0, isExtreme: false)
        }

        let avgFilter = CIFilter(name: "CIAreaAverage")!
        avgFilter.setValue(image, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: extent), forKey: "inputExtent")

        var avgBrightness: Float = 0.5
        if let avgImage = avgFilter.outputImage {
            var pixel = [UInt8](repeating: 0, count: 4)
            ciContext.render(
                avgImage, toBitmap: &pixel, rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )

            let r = Float(pixel[0]) / 255.0
            let g = Float(pixel[1]) / 255.0
            let b = Float(pixel[2]) / 255.0
            avgBrightness = 0.299 * r + 0.587 * g + 0.114 * b
        }

        brightnessLock.lock()
        defer { brightnessLock.unlock() }

        let brightnessDelta = abs(avgBrightness - previousBrightness)
        let isStrobe = brightnessDelta > 0.3
        previousBrightness = avgBrightness

        let brightnessVariance = brightnessDelta
        let isExtreme = avgBrightness < 0.15 || avgBrightness > 0.85

        return LightingAssessment(
            isStrobe: isStrobe,
            avgBrightness: avgBrightness,
            brightnessVariance: brightnessVariance,
            isExtreme: isExtreme
        )
    }

    /// Preprocess image for lighting robustness.
    /// - Parameters:
    ///   - image: Input CIImage.
    ///   - lighting: Pre-computed lighting assessment.
    ///   - intensity: Preprocessing intensity (0-1).
    /// - Returns: Preprocessed CIImage.
    func preprocessForLighting(_ image: CIImage, lighting: LightingAssessment, intensity: Float = 0.5) -> CIImage {
        guard intensity > 0 else { return image }

        var result = image

        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(result, forKey: kCIInputImageKey)
            colorControls.setValue(1.0 + Double(intensity) * 0.3, forKey: kCIInputContrastKey)
            colorControls.setValue(0.0, forKey: kCIInputBrightnessKey)
            colorControls.setValue(1.0 - Double(intensity) * 0.2, forKey: kCIInputSaturationKey)

            if let output = colorControls.outputImage {
                result = output
            }
        }

        if let exposureAdjust = CIFilter(name: "CIExposureAdjust") {
            var exposureValue: Double = 0
            if lighting.avgBrightness < 0.3 {
                exposureValue = Double(0.3 - lighting.avgBrightness) * Double(intensity) * 2.0
            } else if lighting.avgBrightness > 0.7 {
                exposureValue = -Double(lighting.avgBrightness - 0.7) * Double(intensity) * 2.0
            }

            if abs(exposureValue) > 0.1 {
                exposureAdjust.setValue(result, forKey: kCIInputImageKey)
                exposureAdjust.setValue(exposureValue, forKey: kCIInputEVKey)

                if let output = exposureAdjust.outputImage {
                    result = output
                }
            }
        }

        return result
    }

    // MARK: - Feature Extraction

    /// Extract appearance embedding from a pixel buffer.
    /// - Parameters:
    ///   - pixelBuffer: The full frame pixel buffer.
    ///   - boundingBox: Normalized bounding box (0-1 coordinates).
    ///   - skipQualityCheck: If true, skip quality validation.
    /// - Returns: Appearance feature with quality score, or nil if extraction fails.
    func extractFeature(
        from pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect,
        skipQualityCheck: Bool = false
    ) -> AppearanceFeature? {
        guard isReady, rawModel != nil else {
            return nil
        }

        let quality = assessBoundingBoxQuality(boundingBox)

        if !skipQualityCheck && !quality.isValid {
            return nil
        }

        let clampedBox = CGRect(
            x: max(0, boundingBox.minX),
            y: max(0, boundingBox.minY),
            width: min(1.0 - max(0, boundingBox.minX), boundingBox.width),
            height: min(1.0 - max(0, boundingBox.minY), boundingBox.height)
        )

        guard let croppedBuffer = cropAndResize(
            pixelBuffer: pixelBuffer,
            boundingBox: clampedBox,
            targetWidth: Self.inputWidth,
            targetHeight: Self.inputHeight
        ) else {
            return nil
        }

        do {
            let embedding = try runInference(on: croppedBuffer)
            return AppearanceFeature(rawEmbedding: embedding, qualityScore: quality.qualityScore)
        } catch {
            Self.logger.warning("Inference failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Extract appearance embedding from a CGImage.
    /// - Parameters:
    ///   - cgImage: The source image.
    ///   - boundingBox: Normalized bounding box (0-1 coordinates).
    ///   - skipQualityCheck: If true, skip quality validation.
    /// - Returns: Appearance feature with quality score, or nil if extraction fails.
    func extractFeature(
        from cgImage: CGImage,
        boundingBox: CGRect,
        skipQualityCheck: Bool = false
    ) -> AppearanceFeature? {
        guard isReady else { return nil }

        let quality = assessBoundingBoxQuality(boundingBox)

        if !skipQualityCheck && !quality.isValid {
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        let clampedBox = CGRect(
            x: max(0, boundingBox.minX),
            y: max(0, boundingBox.minY),
            width: min(1.0 - max(0, boundingBox.minX), boundingBox.width),
            height: min(1.0 - max(0, boundingBox.minY), boundingBox.height)
        )

        let cropRect = CGRect(
            x: clampedBox.minX * imageWidth,
            y: clampedBox.minY * imageHeight,
            width: clampedBox.width * imageWidth,
            height: clampedBox.height * imageHeight
        ).integral

        guard let croppedImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        guard let resizedImage = resize(
            cgImage: croppedImage,
            to: CGSize(width: Self.inputWidth, height: Self.inputHeight)
        ) else {
            return nil
        }

        guard let pixelBuffer = pixelBuffer(from: resizedImage) else {
            return nil
        }

        do {
            let embedding = try runInference(on: pixelBuffer)
            return AppearanceFeature(rawEmbedding: embedding, qualityScore: quality.qualityScore)
        } catch {
            Self.logger.warning("Inference failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Private Methods

    /// Run inference on a prepared pixel buffer using direct CoreML.
    private func runInference(on pixelBuffer: CVPixelBuffer) throws -> [Float] {
        guard let mlModel = rawModel else {
            throw ReIDError.modelNotLoaded
        }

        let featureValue = MLFeatureValue(pixelBuffer: pixelBuffer)
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": featureValue])
        let output = try mlModel.prediction(from: input)

        guard let embeddingValue = output.featureValue(for: "embedding"),
              let multiArray = embeddingValue.multiArrayValue else {
            throw ReIDError.invalidOutput
        }

        let count = multiArray.count
        guard count == Self.embeddingDimension else {
            throw ReIDError.invalidOutput
        }

        let embedding = (0..<count).map { Float(truncating: multiArray[$0]) }
        return embedding
    }

    /// Crop and resize a region from a pixel buffer with lighting-robust preprocessing.
    private func cropAndResize(
        pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect,
        targetWidth: Int,
        targetHeight: Int,
        applyLightingPreprocessing: Bool = true
    ) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height

        // CIImage origin is bottom-left, flip Y
        let cropRect = CGRect(
            x: boundingBox.minX * imageWidth,
            y: (1 - boundingBox.maxY) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )

        var cropped = ciImage.cropped(to: cropRect)

        if applyLightingPreprocessing {
            let lighting = assessLighting(cropped)
            let intensity = lighting.preprocessingIntensity

            if intensity > 0 {
                cropped = preprocessForLighting(cropped, lighting: lighting, intensity: intensity)
            }
        }

        let scaleX = CGFloat(targetWidth) / cropped.extent.width
        let scaleY = CGFloat(targetHeight) / cropped.extent.height

        let scaled = cropped
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(
                translationX: -cropped.extent.minX * scaleX,
                y: -cropped.extent.minY * scaleY
            ))

        var outputBuffer: CVPixelBuffer?
        if targetWidth == Self.inputWidth && targetHeight == Self.inputHeight,
           let pool = cropBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ]
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                targetWidth,
                targetHeight,
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &outputBuffer
            )
        }

        guard let output = outputBuffer else { return nil }

        ciContext.render(scaled, to: output)
        return output
    }

    /// Resize a CGImage to target size.
    private func resize(cgImage: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        context?.interpolationQuality = .high
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))

        return context?.makeImage()
    }

    /// Convert CGImage to CVPixelBuffer.
    private func pixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}

// MARK: - Batch Processing

extension ReIDExtractor {
    /// Extract features for multiple bounding boxes in a single frame.
    func extractFeatures(
        from pixelBuffer: CVPixelBuffer,
        boundingBoxes: [CGRect]
    ) -> [AppearanceFeature?] {
        boundingBoxes.map { bbox in
            extractFeature(from: pixelBuffer, boundingBox: bbox)
        }
    }
}
