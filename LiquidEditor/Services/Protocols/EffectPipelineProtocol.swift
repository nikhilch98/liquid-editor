// EffectPipelineProtocol.swift
// LiquidEditor
//
// Protocol for GPU-accelerated video effects processing.
// Enables dependency injection and testability.

import CoreImage
import Foundation

// MARK: - EffectPipelineProtocol

/// Protocol for GPU-accelerated video effects processing.
///
/// Implementations apply chains of `VideoEffect` to CIImage frames
/// using the shared Metal-backed CIContext. All rendering is synchronous
/// on the caller's thread (typically the video composition thread).
///
/// References:
/// - `VideoEffect` from Models/Effects/VideoEffect.swift
/// - `EffectType` from Models/Effects/EffectTypes.swift
protocol EffectPipelineProtocol: Sendable {
    /// Apply a chain of effects to an input image.
    ///
    /// Effects are applied in order. Each effect's parameters may be
    /// resolved at `frameTime` for keyframed animation.
    ///
    /// - Parameters:
    ///   - effects: Ordered list of video effects to apply.
    ///   - inputImage: The source CIImage to process.
    ///   - frameTime: Current frame time in microseconds (for keyframe resolution).
    ///   - frameSize: Output frame dimensions.
    /// - Returns: The processed CIImage with all effects applied.
    func applyEffectChain(
        effects: [VideoEffect],
        to inputImage: CIImage,
        frameTime: TimeMicros,
        frameSize: CGSize
    ) -> CIImage

    /// The shared CIContext backed by Metal GPU for rendering.
    ///
    /// Use this context for all CIImage rendering to avoid
    /// creating multiple GPU contexts.
    var sharedContext: CIContext { get }
}
