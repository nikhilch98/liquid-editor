// TransitionRendererProtocol.swift
// LiquidEditor
//
// Protocol for CIFilter-based clip transition rendering.
// Enables dependency injection and testability.

import CoreImage
import Foundation

// MARK: - TransitionRendererProtocol

/// Protocol for rendering visual transitions between two video frames.
///
/// Implementations use CIFilter chains to produce transition effects
/// such as cross-dissolve, wipe, slide, zoom, blur, and page curl.
/// All rendering is synchronous on the caller's thread.
///
/// References:
/// - `ClipTransition` from Models/Timeline/Transition.swift
/// - `TransitionType` from Models/Timeline/Transition.swift
/// - `EasingCurve` from Models/Timeline/Transition.swift
protocol TransitionRendererProtocol: Sendable {
    /// Render a transition frame between two images.
    ///
    /// - Parameters:
    ///   - transition: The transition configuration.
    ///   - fromImage: Outgoing clip frame (source A).
    ///   - toImage: Incoming clip frame (source B).
    ///   - progress: Linear transition progress (0.0 = all A, 1.0 = all B).
    ///   - frameSize: Output frame dimensions.
    /// - Returns: Composited CIImage for the transition frame.
    func renderTransition(
        _ transition: ClipTransition,
        fromImage: CIImage,
        toImage: CIImage,
        progress: Double,
        frameSize: CGSize
    ) -> CIImage

    /// Render a transition by type with explicit parameters.
    ///
    /// Lower-level API for direct rendering without a `ClipTransition` model.
    ///
    /// - Parameters:
    ///   - type: Transition effect type.
    ///   - fromImage: Outgoing frame.
    ///   - toImage: Incoming frame.
    ///   - progress: Linear progress (0.0-1.0).
    ///   - direction: Direction for directional transitions.
    ///   - easing: Easing curve for progress remapping.
    ///   - parameters: Additional type-specific parameters.
    ///   - frameSize: Output frame dimensions.
    /// - Returns: Composited CIImage.
    func renderTransition(
        type: TransitionType,
        fromImage: CIImage,
        toImage: CIImage,
        progress: Double,
        direction: TransitionDirection,
        easing: EasingCurve,
        parameters: [String: String],
        frameSize: CGSize
    ) -> CIImage
}
