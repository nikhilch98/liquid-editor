/// FrameTransitionRenderer + strategy-pattern transition effect implementations.
///
/// C5-10 (Premium UI Redesign spec §5): Provides a minimal per-effect
/// transition strategy surface distinct from the orchestrator
/// `TransitionRenderer` class in `Services/Transitions/`. The orchestrator
/// dispatches to all `TransitionType` values; these standalone strategies
/// are used by the new Premium compositor pipeline when a single, isolated
/// transition effect needs to be rendered for preview or export.
///
/// Naming: the protocol is named `FrameTransitionRenderer` because
/// `TransitionRenderer` is an existing top-level class. Concrete strategy
/// structs use the shorter `*Transition` suffix because they are unique.
///
/// Thread Safety: All structs are stateless (`Sendable` by default). Each
/// `render` call constructs CIFilter instances locally — CIFilter is not
/// Sendable, so filters must never be stored as properties.
///
/// References:
/// - `TransitionRenderer` (orchestrator) in Services/Transitions/TransitionRenderer.swift
/// - `EffectPipeline.sharedContext` in Services/Effects/EffectPipeline.swift

import CoreImage
import CoreGraphics
import Foundation

// MARK: - FrameTransitionRenderer

/// Strategy interface for a single transition effect between two frames.
///
/// Implementations are stateless structs. `progress` is expected to be
/// linear in [0.0, 1.0]; easing should be applied by the caller.
protocol FrameTransitionRenderer: Sendable {
    /// Render a transition frame.
    /// - Parameters:
    ///   - from: Outgoing image (visible when progress == 0.0).
    ///   - to: Incoming image (visible when progress == 1.0).
    ///   - progress: Linear progress in [0.0, 1.0].
    /// - Returns: Composited CIImage cropped to `from`'s extent.
    func render(from: CIImage, to: CIImage, progress: Double) -> CIImage
}

// MARK: - Direction Types

/// Direction for wipe transitions.
enum WipeDirection: String, Sendable, CaseIterable {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop
}

/// Direction for slide transitions.
enum SlideDirection: String, Sendable, CaseIterable {
    case left
    case right
    case up
    case down
}

// MARK: - Shared Helpers

/// Shared internal helpers for transition strategies.
///
/// All helpers are stateless; CIFilter instances are created per call.
private enum TransitionHelpers {
    /// Clamp a Double to [0.0, 1.0].
    static func clamp01(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    /// Blend two images via grayscale mask (white = to, black = from).
    static func blendWithMask(from: CIImage, to: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        guard let filter = CIFilter(name: "CIBlendWithMask") else { return from }
        filter.setValue(to, forKey: kCIInputImageKey)
        filter.setValue(from, forKey: "inputBackgroundImage")
        filter.setValue(mask, forKey: "inputMaskImage")
        return filter.outputImage?.cropped(to: extent) ?? from
    }

    /// Dissolve blend (linear opacity between two images).
    static func dissolve(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let t = clamp01(progress)
        guard let filter = CIFilter(name: "CIDissolveTransition") else {
            return t < 0.5 ? from : to
        }
        filter.setValue(from, forKey: kCIInputImageKey)
        filter.setValue(to, forKey: kCIInputTargetImageKey)
        filter.setValue(t, forKey: "inputTime")
        return filter.outputImage?.cropped(to: from.extent) ?? (t < 0.5 ? from : to)
    }
}

// MARK: - CrossDissolveTransition

/// Linear opacity ramp between outgoing and incoming frames.
///
/// Uses `CIBlendWithMask` with a uniform grayscale mask at opacity `progress`
/// to achieve consistent blending semantics; falls back to `CIDissolveTransition`
/// if the mask filter is unavailable.
struct CrossDissolveTransition: FrameTransitionRenderer {
    func render(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let t = TransitionHelpers.clamp01(progress)
        let extent = from.extent

        // Uniform gray mask where luminance == progress.
        let maskColor = CIColor(red: CGFloat(t), green: CGFloat(t), blue: CGFloat(t))
        let mask = CIImage(color: maskColor).cropped(to: extent)

        return TransitionHelpers.blendWithMask(from: from, to: to, mask: mask, extent: extent)
    }
}

// MARK: - WipeTransition

/// Directional wipe using an animated linear gradient mask.
///
/// The mask boundary slides across the frame in the configured direction
/// as `progress` advances from 0 to 1.
struct WipeTransition: FrameTransitionRenderer {
    let direction: WipeDirection

    /// Default soft edge as a fraction of the frame's max dimension.
    private static let defaultSoftness: CGFloat = 0.02

    init(direction: WipeDirection) {
        self.direction = direction
    }

    func render(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let t = TransitionHelpers.clamp01(progress)
        let extent = from.extent

        guard let mask = makeGradientMask(extent: extent, progress: t) else {
            // Fallback to cross-dissolve if gradient synthesis fails.
            return TransitionHelpers.dissolve(from: from, to: to, progress: t)
        }
        return TransitionHelpers.blendWithMask(from: from, to: to, mask: mask, extent: extent)
    }

    /// Build a linear-gradient mask whose white region expands in `direction` with progress.
    private func makeGradientMask(extent: CGRect, progress: Double) -> CIImage? {
        guard let gradient = CIFilter(name: "CILinearGradient") else { return nil }
        let softness = max(1.0, Self.defaultSoftness * max(extent.width, extent.height))
        let t = CGFloat(progress)

        let point0: CIVector
        let point1: CIVector

        switch direction {
        case .leftToRight:
            // White on left side expanding right.
            let edge = extent.minX + extent.width * t
            point0 = CIVector(x: edge - softness, y: extent.midY)
            point1 = CIVector(x: edge + softness, y: extent.midY)
        case .rightToLeft:
            let edge = extent.maxX - extent.width * t
            point0 = CIVector(x: edge + softness, y: extent.midY)
            point1 = CIVector(x: edge - softness, y: extent.midY)
        case .topToBottom:
            // Note: Core Image y-axis is inverted (origin bottom-left).
            let edge = extent.maxY - extent.height * t
            point0 = CIVector(x: extent.midX, y: edge + softness)
            point1 = CIVector(x: extent.midX, y: edge - softness)
        case .bottomToTop:
            let edge = extent.minY + extent.height * t
            point0 = CIVector(x: extent.midX, y: edge - softness)
            point1 = CIVector(x: extent.midX, y: edge + softness)
        }

        gradient.setValue(point0, forKey: "inputPoint0")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(point1, forKey: "inputPoint1")
        gradient.setValue(CIColor.black, forKey: "inputColor1")

        return gradient.outputImage?.cropped(to: extent)
    }
}

// MARK: - SlideTransition

/// Incoming frame slides in from the configured side, pushing the outgoing frame off.
///
/// Implemented purely with `CGAffineTransform` translations + source-over
/// compositing; no mask required.
struct SlideTransition: FrameTransitionRenderer {
    let direction: SlideDirection

    init(direction: SlideDirection) {
        self.direction = direction
    }

    func render(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let t = TransitionHelpers.clamp01(progress)
        let extent = from.extent
        let (dx, dy) = offsetVector(direction)

        // Outgoing slides away by (dx, dy) scaled by progress.
        let outDX = CGFloat(t) * extent.width * CGFloat(dx)
        let outDY = CGFloat(t) * extent.height * CGFloat(dy)
        let fromTranslated = from.transformed(by: CGAffineTransform(translationX: outDX, y: outDY))

        // Incoming starts fully offset in opposite direction, slides into frame.
        let inStartX = -extent.width * CGFloat(dx)
        let inStartY = -extent.height * CGFloat(dy)
        let toTranslated = to.transformed(by: CGAffineTransform(
            translationX: inStartX + outDX,
            y: inStartY + outDY
        ))

        let composite = toTranslated.applyingFilter("CISourceOverCompositing", parameters: [
            "inputBackgroundImage": fromTranslated,
        ])
        return composite.cropped(to: extent)
    }

    /// Translation unit vector for slide direction (Core Image y-up).
    private func offsetVector(_ dir: SlideDirection) -> (x: Double, y: Double) {
        switch dir {
        case .left:  return (-1.0, 0.0)
        case .right: return (1.0, 0.0)
        case .up:    return (0.0, 1.0)
        case .down:  return (0.0, -1.0)
        }
    }
}

// MARK: - ZoomTransition

/// Zoom transition: outgoing scales up while incoming scales down, blended by progress.
struct ZoomTransition: FrameTransitionRenderer {
    /// Additional scale applied to outgoing frame at progress = 1.0.
    private static let outgoingScaleDelta: Double = 0.3

    /// Initial scale of incoming frame at progress = 0.0.
    private static let incomingStartScale: Double = 1.3

    func render(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let t = TransitionHelpers.clamp01(progress)
        let extent = from.extent

        let outScale = 1.0 + t * Self.outgoingScaleDelta
        let inScale = Self.incomingStartScale - t * (Self.incomingStartScale - 1.0)

        let fromScaled = scaleFromCenter(image: from, scale: CGFloat(outScale), extent: extent)
        let toScaled = scaleFromCenter(image: to, scale: CGFloat(inScale), extent: extent)

        return TransitionHelpers.dissolve(from: fromScaled, to: toScaled, progress: t)
    }

    /// Scale an image around the center of `extent` and crop back to `extent`.
    private func scaleFromCenter(image: CIImage, scale: CGFloat, extent: CGRect) -> CIImage {
        let centerX = extent.midX
        let centerY = extent.midY
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: centerX, y: centerY)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -centerX, y: -centerY)
        return image.transformed(by: transform).cropped(to: extent)
    }
}

// MARK: - DipToBlackTransition

/// Fade outgoing to black in the first half, fade in from black in the second half.
struct DipToBlackTransition: FrameTransitionRenderer {
    /// Progress value at which the fade switches from outgoing to incoming.
    private static let splitPoint: Double = 0.5

    func render(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        let t = TransitionHelpers.clamp01(progress)
        let extent = from.extent
        let black = CIImage(color: CIColor.black).cropped(to: extent)

        if t <= Self.splitPoint {
            // Fade from -> black (subProgress 0 -> 1 over first half).
            let subProgress = t / Self.splitPoint
            return TransitionHelpers.dissolve(from: from, to: black, progress: subProgress)
        } else {
            // Fade black -> to (subProgress 0 -> 1 over second half).
            let subProgress = (t - Self.splitPoint) / Self.splitPoint
            return TransitionHelpers.dissolve(from: black, to: to, progress: subProgress)
        }
    }
}
