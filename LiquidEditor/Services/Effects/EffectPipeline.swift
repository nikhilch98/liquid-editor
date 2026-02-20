/// EffectPipeline - GPU-accelerated CIFilter chain for video effects.
///
/// Builds and executes CIFilter chains from `VideoEffect` model objects.
/// Single pipeline used for both preview and export rendering.
///
/// Effect dispatch is handled by `EffectApplierRegistry` using the
/// strategy pattern -- each `EffectType` maps to an `EffectApplier`
/// implementation via dictionary lookup.
///
/// Thread Safety: `@unchecked Sendable` with `OSAllocatedUnfairLock`
/// protecting the shared CIContext. CIContext is thread-safe for rendering
/// but we guard context creation and any future mutable state.
///
/// References:
/// - `VideoEffect` from Models/Effects/VideoEffect.swift
/// - `EffectType` from Models/Effects/EffectTypes.swift
/// - `EffectChain` from Models/Effects/EffectChain.swift
/// - `EffectApplier` from Services/Effects/EffectApplier.swift

import CoreImage
import CoreGraphics
import AVFoundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "EffectPipeline")

// MARK: - EffectPipeline

/// Builds and executes CIFilter chains from `VideoEffect` model objects.
///
/// Uses a static shared CIContext backed by Metal for GPU-accelerated rendering.
/// All methods are safe to call from any thread.
final class EffectPipeline: @unchecked Sendable, EffectPipelineProtocol {

    // MARK: - Shared Context

    /// Shared CIContext with Metal GPU acceleration.
    /// Created lazily on first use, reused across all frames.
    static let sharedContext: CIContext = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            ])
        }
        return CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: false,
        ])
    }()

    /// Protocol conformance: instance-level access to the shared context.
    var sharedContext: CIContext { Self.sharedContext }

    // MARK: - Singleton

    /// Shared instance for convenience.
    static let shared = EffectPipeline()

    // MARK: - Registry

    /// Effect applier registry for dispatch.
    private let registry = EffectApplierRegistry.shared

    // MARK: - EffectPipelineProtocol

    /// Apply a chain of video effects to a source image.
    ///
    /// Effects are applied in order. Each effect's `mix` controls blending
    /// with the unprocessed input. Disabled effects are skipped.
    func applyEffectChain(
        effects: [VideoEffect],
        to inputImage: CIImage,
        frameTime: TimeMicros,
        frameSize: CGSize
    ) -> CIImage {
        let cmTime = CMTime(value: CMTimeValue(frameTime), timescale: 1_000_000)
        var currentImage = inputImage

        for effect in effects {
            guard effect.isEnabled else { continue }

            // Resolve parameters at current clip time (handles keyframes)
            let resolvedParams = effect.resolvedParameters(clipTimeMicros: frameTime)

            let filtered = applyEffect(
                type: effect.type,
                input: currentImage,
                parameters: resolvedParams,
                frameSize: frameSize,
                frameTime: cmTime
            )

            // Apply mix (blend with original)
            if effect.mix < 1.0 {
                currentImage = blendImages(
                    original: currentImage,
                    filtered: filtered,
                    amount: effect.mix
                )
            } else {
                currentImage = filtered
            }
        }

        return currentImage
    }

    // MARK: - Effect Dispatch

    /// Apply a single effect by its `EffectType`.
    ///
    /// Dispatches to the appropriate `EffectApplier` via registry lookup.
    /// Falls back to returning the input image if no applier is registered.
    func applyEffect(
        type: EffectType,
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize,
        frameTime: CMTime
    ) -> CIImage {
        guard let applier = registry.applier(for: type) else {
            logger.warning("No applier registered for effect type '\(type.rawValue)', returning input image unchanged")
            return input
        }
        return applier.apply(to: input, parameters: parameters, frameSize: frameSize, frameTime: frameTime)
    }

    // MARK: - Blending

    /// Blend filtered image with original based on mix amount.
    private func blendImages(
        original: CIImage,
        filtered: CIImage,
        amount: Double
    ) -> CIImage {
        guard let dissolve = CIFilter(name: "CIDissolveTransition") else {
            logger.warning("Failed to create CIDissolveTransition filter for effect blending")
            return filtered
        }
        dissolve.setValue(original, forKey: kCIInputImageKey)
        dissolve.setValue(filtered, forKey: kCIInputTargetImageKey)
        dissolve.setValue(amount, forKey: "inputTime")

        guard let output = dissolve.outputImage?.cropped(to: original.extent) else {
            logger.warning("CIDissolveTransition returned nil output image")
            return filtered
        }

        return output
    }
}
