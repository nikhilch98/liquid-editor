// ExportCompositor.swift
// LiquidEditor
//
// Custom AVVideoCompositing implementation for export rendering.
// Applies effects, color grading, crop/rotation, and transitions
// to each frame during export using CIFilter pipelines.
//
// Thread Safety:
// - `@unchecked Sendable` with serial dispatch queue for GPU hot-path.
// - CIContext is Metal-backed and thread-safe.
// - All pipeline calls are stateless (no shared mutable state).

import AVFoundation
import CoreImage
import Foundation
import os

// MARK: - ExportCompositor

/// Custom compositor implementing AVVideoCompositing protocol for export.
///
/// Pipeline order per frame:
///   1. Crop / Rotation / Flip
///   2. Video Effects (CIFilter chain)
///   3. Color Grading (CIFilter chain)
///   4. Transitions (blend with previous clip frame)
///   5. Scale to output render size
final class ExportCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {

    // MARK: - Private Properties

    private static let logger = Logger(subsystem: "LiquidEditor", category: "ExportCompositor")

    // MARK: - AVVideoCompositing Protocol Properties

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
    }

    // MARK: - Private Properties

    /// Metal-backed CIContext for GPU-accelerated rendering.
    private let ciContext: CIContext = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return CIContext(options: [.useSoftwareRenderer: false])
        }
        return CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .highQualityDownsample: true,
        ])
    }()

    /// Serial render queue for deterministic frame ordering during export.
    private let renderQueue = DispatchQueue(
        label: "com.liquideditor.exportCompositor.render",
        qos: .userInteractive
    )

    // MARK: - AVVideoCompositing Protocol Methods

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // No-op: render context is accessed directly from each request.
    }

    func startRequest(_ asyncRequest: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self else {
                asyncRequest.finish(with: Self.makeError(code: -1, message: "Compositor deallocated"))
                return
            }
            self.processRequest(asyncRequest)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderQueue.async(flags: .barrier) {
            // Pending tasks on the serial queue will complete naturally.
            // AVFoundation handles cancellation by ignoring late-delivered frames.
        }
    }

    // MARK: - Frame Processing

    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? ExportCompositionInstruction else {
            // Fallback: pass through first available source frame
            if let trackID = request.sourceTrackIDs.first?.int32Value,
               let sourceBuffer = request.sourceFrame(byTrackID: trackID) {
                request.finish(withComposedVideoFrame: sourceBuffer)
            } else {
                request.finish(with: Self.makeError(code: -1, message: "Invalid instruction type"))
            }
            return
        }

        // Get source frame
        guard let sourceBuffer = request.sourceFrame(byTrackID: instruction.sourceTrackID) else {
            request.finish(with: Self.makeError(
                code: -2,
                message: "No source frame for track \(instruction.sourceTrackID)"
            ))
            return
        }

        var image = CIImage(cvPixelBuffer: sourceBuffer)
        let renderSize = request.renderContext.size
        let compositionTime = request.compositionTime

        // 1. Apply crop/rotation/flip
        if let cropParams = instruction.cropParams {
            image = applyCrop(image, params: cropParams)
        }

        // 2. Apply video effects via CIFilter chain
        if let effects = instruction.effectChain, !effects.isEmpty {
            image = applyEffects(image, effects: effects, time: compositionTime, renderSize: renderSize)
        }

        // 3. Apply color grading via CIFilter chain
        if let gradeParams = instruction.colorGradeParams {
            image = applyColorGrading(image, params: gradeParams)
        }

        // 4. Handle transitions (blend with previous clip frame)
        if let transitionData = instruction.transitionData,
           let prevTrackID = instruction.previousTrackID,
           let prevBuffer = request.sourceFrame(byTrackID: prevTrackID) {
            let prevImage = CIImage(cvPixelBuffer: prevBuffer)
            image = applyTransition(
                from: prevImage,
                to: image,
                data: transitionData,
                time: compositionTime
            )
        }

        // 5. Scale image to render size if needed
        let extent = image.extent
        if extent.width > 0 && extent.height > 0 {
            let scaleX = renderSize.width / extent.width
            let scaleY = renderSize.height / extent.height
            if abs(scaleX - 1.0) > 0.001 || abs(scaleY - 1.0) > 0.001 {
                image = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            }
        }

        // Render to output pixel buffer
        guard let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: Self.makeError(code: -3, message: "Failed to create output buffer"))
            return
        }

        ciContext.render(
            image,
            to: outputBuffer,
            bounds: CGRect(origin: .zero, size: renderSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        request.finish(withComposedVideoFrame: outputBuffer)
    }

    // MARK: - Crop / Rotation / Flip

    private func applyCrop(_ image: CIImage, params: CropParameters) -> CIImage {
        var result = image

        // Apply 90-degree rotation increments
        if params.rotation90 != 0 {
            let radians = CGFloat(params.rotation90) * .pi / 180.0
            result = result.transformed(by: CGAffineTransform(rotationAngle: radians))
            let extent = result.extent
            result = result.transformed(
                by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            )
        }

        // Apply horizontal flip
        if params.flipHorizontal {
            let width = result.extent.width
            result = result.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            result = result.transformed(by: CGAffineTransform(translationX: width, y: 0))
        }

        // Apply vertical flip
        if params.flipVertical {
            let height = result.extent.height
            result = result.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            result = result.transformed(by: CGAffineTransform(translationX: 0, y: height))
        }

        return result
    }

    // MARK: - Effects

    /// Shared effect applier registry -- delegates to the same EffectApplier
    /// instances used by EffectPipeline, eliminating duplicated CIFilter logic.
    private static let effectRegistry = EffectApplierRegistry.shared

    private func applyEffects(
        _ image: CIImage,
        effects: [[String: Any]],
        time: CMTime,
        renderSize: CGSize
    ) -> CIImage {
        var result = image
        for effect in effects {
            guard let isEnabled = effect["isEnabled"] as? Bool, isEnabled else { continue }
            let mix = effect["mix"] as? Double ?? 1.0
            guard mix > 0.001 else { continue }

            if let filtered = applyEffect(result, effect: effect, frameTime: time, renderSize: renderSize) {
                if mix >= 0.999 {
                    result = filtered
                } else {
                    // Blend original and filtered using dissolve for proper mix
                    if let dissolve = CIFilter(name: "CIDissolveTransition") {
                        dissolve.setValue(result, forKey: kCIInputImageKey)
                        dissolve.setValue(filtered, forKey: kCIInputTargetImageKey)
                        dissolve.setValue(mix, forKey: "inputTime")
                        result = dissolve.outputImage?.cropped(to: result.extent) ?? filtered
                    } else {
                        Self.logger.warning("Failed to create CIDissolveTransition for effect blending")
                        result = filtered.composited(over: result)
                    }
                }
            }
        }
        return result
    }

    /// Apply a single effect by delegating to EffectApplierRegistry.
    ///
    /// Converts dictionary-based effect parameters to typed `ParameterValue`
    /// and dispatches to the shared `EffectApplier` implementations,
    /// ensuring consistent rendering between preview and export.
    private func applyEffect(
        _ image: CIImage,
        effect: [String: Any],
        frameTime: CMTime,
        renderSize: CGSize
    ) -> CIImage? {
        guard let typeString = effect["type"] as? String,
              let effectType = EffectType(rawValue: typeString),
              let applier = Self.effectRegistry.applier(for: effectType) else {
            Self.logger.warning("Failed to get effect applier for type: \(effect["type"] as? String ?? "unknown")")
            return nil
        }

        // Convert [String: Any] parameters to [String: ParameterValue]
        var typedParams: [String: ParameterValue] = [:]
        for (key, value) in effect {
            guard key != "type" && key != "isEnabled" && key != "mix" else { continue }
            if let doubleVal = value as? Double {
                typedParams[key] = .double_(doubleVal)
            } else if let intVal = value as? Int {
                typedParams[key] = .int_(intVal)
            } else if let boolVal = value as? Bool {
                typedParams[key] = .bool_(boolVal)
            }
        }

        return applier.apply(
            to: image,
            parameters: typedParams,
            frameSize: renderSize,
            frameTime: frameTime
        )
    }

    // MARK: - Color Grading

    private func applyColorGrading(_ image: CIImage, params: [String: Any]) -> CIImage {
        var result = image

        // Brightness / Contrast / Saturation
        if let brightness = params["brightness"] as? Double,
           let contrast = params["contrast"] as? Double,
           let saturation = params["saturation"] as? Double {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(result, forKey: kCIInputImageKey)
                filter.setValue(brightness, forKey: kCIInputBrightnessKey)
                filter.setValue(contrast, forKey: kCIInputContrastKey)
                filter.setValue(saturation, forKey: kCIInputSaturationKey)
                if let output = filter.outputImage {
                    result = output
                }
            } else {
                Self.logger.warning("Failed to create CIColorControls filter")
            }
        }

        // Temperature / Tint
        if let temperature = params["temperature"] as? Double {
            if let filter = CIFilter(name: "CITemperatureAndTint") {
                filter.setValue(result, forKey: kCIInputImageKey)
                filter.setValue(CIVector(x: CGFloat(temperature), y: 0), forKey: "inputNeutral")
                if let output = filter.outputImage {
                    result = output
                }
            } else {
                Self.logger.warning("Failed to create CITemperatureAndTint filter")
            }
        }

        // Exposure
        if let exposure = params["exposure"] as? Double, exposure != 0.0 {
            if let filter = CIFilter(name: "CIExposureAdjust") {
                filter.setValue(result, forKey: kCIInputImageKey)
                filter.setValue(exposure, forKey: kCIInputEVKey)
                if let output = filter.outputImage {
                    result = output
                }
            } else {
                Self.logger.warning("Failed to create CIExposureAdjust filter")
            }
        }

        return result
    }

    // MARK: - Transitions

    private func applyTransition(
        from: CIImage,
        to: CIImage,
        data: TransitionParameters,
        time: CMTime
    ) -> CIImage {
        let currentTime = CMTimeGetSeconds(time)
        let progress = data.duration > 0
            ? min(max((currentTime - data.startTime) / data.duration, 0.0), 1.0)
            : 1.0

        // Cross-dissolve is the default and most common transition
        let filter = CIFilter(name: "CIDissolveTransition")
        filter?.setValue(from, forKey: kCIInputImageKey)
        filter?.setValue(to, forKey: kCIInputTargetImageKey)
        filter?.setValue(progress, forKey: kCIInputTimeKey)

        return filter?.outputImage ?? to
    }

    // MARK: - Error Helpers

    private static func makeError(code: Int, message: String) -> NSError {
        NSError(
            domain: "com.liquideditor.ExportCompositor",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

// MARK: - ExportCompositionInstruction

/// Custom video composition instruction for export that carries editing parameters.
///
/// All properties are immutable after init for thread safety.
class ExportCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {

    // MARK: - AVVideoCompositionInstructionProtocol

    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = true
    let containsTweening: Bool = true
    private let _requiredSourceTrackIDs: [NSValue]?
    var requiredSourceTrackIDs: [NSValue]? { _requiredSourceTrackIDs }
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    // MARK: - Editing Parameters

    /// Composition track ID for the primary source video frame.
    let sourceTrackID: CMPersistentTrackID

    /// Color grading parameters.
    let colorGradeParams: [String: Any]?

    /// Video effects chain.
    let effectChain: [[String: Any]]?

    /// Crop / rotation / flip parameters.
    let cropParams: CropParameters?

    /// Transition parameters.
    let transitionData: TransitionParameters?

    /// Track ID of the previous clip (for transition blending).
    let previousTrackID: CMPersistentTrackID?

    /// Playback speed multiplier.
    let playbackSpeed: Double

    // MARK: - Init

    init(
        timeRange: CMTimeRange,
        sourceTrackID: CMPersistentTrackID,
        colorGradeParams: [String: Any]? = nil,
        effectChain: [[String: Any]]? = nil,
        cropParams: CropParameters? = nil,
        playbackSpeed: Double = 1.0,
        transitionData: TransitionParameters? = nil,
        previousTrackID: CMPersistentTrackID? = nil
    ) {
        self.timeRange = timeRange
        self.sourceTrackID = sourceTrackID
        self.colorGradeParams = colorGradeParams
        self.effectChain = effectChain
        self.cropParams = cropParams
        self.playbackSpeed = playbackSpeed
        self.transitionData = transitionData
        self.previousTrackID = previousTrackID

        var trackIDs: [NSValue] = [NSNumber(value: sourceTrackID)]
        if let prevID = previousTrackID {
            trackIDs.append(NSNumber(value: prevID))
        }
        self._requiredSourceTrackIDs = trackIDs

        super.init()
    }
}

// MARK: - TransitionParameters

/// Immutable transition parameters.
struct TransitionParameters: Sendable {
    /// Transition type name.
    let type: String

    /// Start time in seconds.
    let startTime: Double

    /// Duration in seconds.
    let duration: Double

    /// Direction of the transition.
    let direction: String

    /// Easing function name.
    let easing: String

    init(
        type: String = "crossDissolve",
        startTime: Double = 0,
        duration: Double = 0.5,
        direction: String = "left",
        easing: String = "easeInOut"
    ) {
        self.type = type
        self.startTime = startTime
        self.duration = duration
        self.direction = direction
        self.easing = easing
    }
}
