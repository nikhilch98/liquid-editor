/// TransitionRenderer - CIFilter-based transition rendering for clip transitions.
///
/// Renders all `TransitionType` values using CIFilter chains.
/// Supports cross-dissolve, slides, wipes, fades, zoom, blur, rotation, and page curl.
/// Integrates with the composition builder and export pipeline.
///
/// Thread Safety: `Sendable` - all methods are stateless and safe to call
/// from any thread. Uses `EffectPipeline.sharedContext` for GPU rendering.
///
/// References:
/// - `ClipTransition` from Models/Timeline/Transition.swift
/// - `TransitionType` from Models/Timeline/Transition.swift
/// - `TransitionDirection` from Models/Timeline/Transition.swift
/// - `EasingCurve` from Models/Timeline/Transition.swift

import CoreImage
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "TransitionRenderer")

// MARK: - Transition Easing

/// Maps `EasingCurve` enum values to progress transform functions.
private enum TransitionEasing {
    /// Apply easing to a linear progress value (0.0 to 1.0).
    static func apply(_ t: Double, curve: EasingCurve) -> Double {
        let clamped = min(max(t, 0), 1)
        switch curve {
        case .linear:
            return clamped
        case .easeIn:
            return clamped * clamped
        case .easeOut:
            return 1 - (1 - clamped) * (1 - clamped)
        case .easeInOut, .fastOutSlowIn:
            if clamped < 0.5 {
                return 2 * clamped * clamped
            } else {
                return 1 - pow(-2 * clamped + 2, 2) / 2
            }
        case .decelerate:
            return 1 - (1 - clamped) * (1 - clamped)
        case .bounceOut:
            return bounceOut(clamped)
        case .elasticOut:
            return elasticOut(clamped)
        }
    }

    private static func bounceOut(_ t: Double) -> Double {
        if t < 1 / 2.75 {
            return 7.5625 * t * t
        } else if t < 2 / 2.75 {
            let t2 = t - 1.5 / 2.75
            return 7.5625 * t2 * t2 + 0.75
        } else if t < 2.5 / 2.75 {
            let t2 = t - 2.25 / 2.75
            return 7.5625 * t2 * t2 + 0.9375
        } else {
            let t2 = t - 2.625 / 2.75
            return 7.5625 * t2 * t2 + 0.984375
        }
    }

    private static func elasticOut(_ t: Double) -> Double {
        if t == 0 || t == 1 { return t }
        return pow(2, -10 * t) * sin((t - 0.075) * (2 * .pi) / 0.3) + 1
    }
}

// MARK: - TransitionRenderer

/// Renders transition effects between two video frames using CIFilter chains.
///
/// All methods are stateless and safe to call from any thread.
final class TransitionRenderer: Sendable, TransitionRendererProtocol {

    // MARK: - Constants

    /// Default color for dip transitions when no color is specified.
    private static let defaultDipColor: Int = 0x000000

    /// Default softness for edge feathering in wipe transitions.
    private static let defaultWipeSoftness: Double = 0.02

    /// Softness scaling factor for clock wipe transitions.
    /// Multiplied by 200 to convert normalized softness to CIFilter width parameter.
    private static let clockWipeSoftnessScale: Double = 200.0

    /// Softness scaling factor for iris wipe transitions.
    /// Multiplied by 0.1 of the maximum radius for edge feathering.
    private static let irisWipeSoftnessScale: Double = 0.1

    /// Minimum edge softness for gradient masks (prevents artifacts).
    private static let minGradientSoftness: CGFloat = 1.0

    /// Scale delta for zoom transition (1.0 to 1.3).
    private static let zoomScaleDelta: Double = 0.3

    /// Scale delta for zoom-in transition (1.0 to 1.5).
    private static let zoomInScaleDelta: Double = 0.5

    /// Initial scale for zoom-out transition (1.5 to 1.0).
    private static let zoomOutInitialScale: Double = 1.5

    /// Maximum blur radius for blur transitions.
    private static let blurMaxRadius: Double = 30.0

    /// Fade split point (0.5 = fade out for first half, fade in for second half).
    private static let fadeSplitPoint: Double = 0.5

    /// Rotation angle for rotation transition (π/6 = 30 degrees).
    private static let rotationAngle: CGFloat = .pi / 6.0

    /// Scale delta for rotation transition (0.3 = scale from 1.0 to 0.7).
    private static let rotationScaleDelta: Double = 0.3

    /// Page curl angle (π = 180 degrees, curls from bottom-right).
    private static let pageCurlAngle: Double = .pi

    /// Page curl radius (controls tightness of the curl).
    private static let pageCurlRadius: Double = 100.0

    // MARK: - Shared Instance

    /// Shared instance for convenience.
    static let shared = TransitionRenderer()

    // MARK: - TransitionRendererProtocol (model-based)

    /// Render a transition frame from a `ClipTransition` model.
    func renderTransition(
        _ transition: ClipTransition,
        fromImage: CIImage,
        toImage: CIImage,
        progress: Double,
        frameSize: CGSize
    ) -> CIImage {
        renderTransition(
            type: transition.type,
            fromImage: fromImage,
            toImage: toImage,
            progress: progress,
            direction: transition.direction,
            easing: transition.easing,
            parameters: transition.parameters,
            frameSize: frameSize
        )
    }

    // MARK: - TransitionRendererProtocol (type-based)

    /// Render a transition by type with explicit parameters.
    func renderTransition(
        type: TransitionType,
        fromImage: CIImage,
        toImage: CIImage,
        progress: Double,
        direction: TransitionDirection,
        easing: EasingCurve,
        parameters: [String: String],
        frameSize: CGSize
    ) -> CIImage {
        let easedProgress = TransitionEasing.apply(progress, curve: easing)

        switch type {
        // Basic
        case .crossDissolve:
            return renderCrossDissolve(from: fromImage, to: toImage, progress: easedProgress)
        case .crossfade:
            return easedProgress < 0.5 ? fromImage : toImage
        case .dip:
            return renderDip(from: fromImage, to: toImage, progress: easedProgress, parameters: parameters, frameSize: frameSize)
        case .fadeToBlack:
            return renderFadeToColor(from: fromImage, to: toImage, progress: easedProgress, color: CIColor.black, frameSize: frameSize)
        case .fadeToWhite:
            return renderFadeToColor(from: fromImage, to: toImage, progress: easedProgress, color: CIColor.white, frameSize: frameSize)

        // Wipe
        case .wipe:
            let softness = Double(parameters["softness"] ?? "\(Self.defaultWipeSoftness)") ?? Self.defaultWipeSoftness
            return renderWipe(from: fromImage, to: toImage, progress: easedProgress, direction: direction, softness: softness, frameSize: frameSize)
        case .wipeClock:
            let softness = Double(parameters["softness"] ?? "\(Self.defaultWipeSoftness)") ?? Self.defaultWipeSoftness
            return renderClockWipe(from: fromImage, to: toImage, progress: easedProgress, softness: softness, frameSize: frameSize)
        case .wipeIris:
            let softness = Double(parameters["softness"] ?? "\(Self.defaultWipeSoftness)") ?? Self.defaultWipeSoftness
            return renderIrisWipe(from: fromImage, to: toImage, progress: easedProgress, softness: softness, frameSize: frameSize)

        // Slide
        case .slide:
            return renderPush(from: fromImage, to: toImage, progress: easedProgress, direction: direction, frameSize: frameSize)
        case .push:
            return renderPush(from: fromImage, to: toImage, progress: easedProgress, direction: direction, frameSize: frameSize)
        case .slideOver:
            return renderSlideOver(from: fromImage, to: toImage, progress: easedProgress, direction: direction, frameSize: frameSize)
        case .slideUnder:
            return renderSlideUnder(from: fromImage, to: toImage, progress: easedProgress, direction: direction, frameSize: frameSize)

        // Zoom
        case .zoom:
            return renderZoom(from: fromImage, to: toImage, progress: easedProgress, frameSize: frameSize)
        case .zoomIn:
            return renderZoomIn(from: fromImage, to: toImage, progress: easedProgress, frameSize: frameSize)
        case .zoomOut:
            return renderZoomOut(from: fromImage, to: toImage, progress: easedProgress, frameSize: frameSize)

        // Special
        case .blur:
            return renderBlur(from: fromImage, to: toImage, progress: easedProgress)
        case .rotation:
            return renderRotation(from: fromImage, to: toImage, progress: easedProgress, frameSize: frameSize)
        case .pageCurl:
            return renderPageCurl(from: fromImage, to: toImage, progress: easedProgress, frameSize: frameSize)

        // Custom / unknown - fall back to cross dissolve
        case .custom:
            logger.warning("Unknown transition type '\(type.rawValue)', falling back to cross dissolve")
            return renderCrossDissolve(from: fromImage, to: toImage, progress: easedProgress)
        }
    }

    // MARK: - Basic Transitions

    /// Cross dissolve: linear opacity blend between outgoing and incoming.
    private func renderCrossDissolve(from: CIImage, to: CIImage, progress: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIDissolveTransition") else {
            return progress < 0.5 ? from : to
        }
        filter.setValue(from, forKey: kCIInputImageKey)
        filter.setValue(to, forKey: kCIInputTargetImageKey)
        filter.setValue(progress, forKey: "inputTime")
        return filter.outputImage?.cropped(to: from.extent) ?? (progress < 0.5 ? from : to)
    }

    /// Dip to color: fade outgoing to color at 50%, then reveal incoming.
    private func renderDip(
        from: CIImage,
        to: CIImage,
        progress: Double,
        parameters: [String: String],
        frameSize: CGSize
    ) -> CIImage {
        let colorValue = Int(parameters["color"] ?? "0") ?? Self.defaultDipColor

        // Validate color value is within valid RGB range
        guard colorValue >= 0 && colorValue <= 0xFFFFFF else {
            logger.warning("Invalid dip color value: \(colorValue, privacy: .public). Using default black.")
            return renderFadeToColor(from: from, to: to, progress: progress, color: CIColor.black, frameSize: frameSize)
        }

        let r = CGFloat((colorValue >> 16) & 0xFF) / 255.0
        let g = CGFloat((colorValue >> 8) & 0xFF) / 255.0
        let b = CGFloat(colorValue & 0xFF) / 255.0
        let dipColor = CIColor(red: r, green: g, blue: b)

        return renderFadeToColor(from: from, to: to, progress: progress, color: dipColor, frameSize: frameSize)
    }

    /// Fade to a solid color and back.
    ///
    /// Fades out to color in the first half, then fades in from color in the second half.
    /// The split point is at 0.5 (50% progress).
    private func renderFadeToColor(
        from: CIImage,
        to: CIImage,
        progress: Double,
        color: CIColor,
        frameSize: CGSize
    ) -> CIImage {
        let colorImage = CIImage(color: color).cropped(to: from.extent)

        if progress <= Self.fadeSplitPoint {
            let subProgress = progress * 2.0
            guard let filter = CIFilter(name: "CIDissolveTransition") else { return from }
            filter.setValue(from, forKey: kCIInputImageKey)
            filter.setValue(colorImage, forKey: kCIInputTargetImageKey)
            filter.setValue(subProgress, forKey: "inputTime")
            return filter.outputImage?.cropped(to: from.extent) ?? from
        } else {
            let subProgress = (progress - Self.fadeSplitPoint) * 2.0
            guard let filter = CIFilter(name: "CIDissolveTransition") else { return to }
            filter.setValue(colorImage, forKey: kCIInputImageKey)
            filter.setValue(to, forKey: kCIInputTargetImageKey)
            filter.setValue(subProgress, forKey: "inputTime")
            return filter.outputImage?.cropped(to: from.extent) ?? to
        }
    }

    // MARK: - Wipe Transitions

    /// Directional wipe using a gradient mask.
    private func renderWipe(
        from: CIImage,
        to: CIImage,
        progress: Double,
        direction: TransitionDirection,
        softness: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let mask = generateLinearGradientMask(
            direction: direction,
            progress: progress,
            softness: softness,
            extent: extent
        )
        return blendWithMask(from: from, to: to, mask: mask, extent: extent)
    }

    /// Clock wipe: radial sweep from 12 o'clock position.
    ///
    /// Uses `CISwipeTransition` with softness scaled by 200 to convert normalized
    /// softness (0.0-1.0) to CIFilter's width parameter range.
    private func renderClockWipe(
        from: CIImage,
        to: CIImage,
        progress: Double,
        softness: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent

        guard let filter = CIFilter(name: "CISwipeTransition") else {
            return renderCrossDissolve(from: from, to: to, progress: progress)
        }

        let angle = progress * 2.0 * .pi
        filter.setValue(from, forKey: kCIInputImageKey)
        filter.setValue(to, forKey: kCIInputTargetImageKey)
        filter.setValue(progress, forKey: "inputTime")
        filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: "inputExtent")
        filter.setValue(angle, forKey: kCIInputAngleKey)
        filter.setValue(max(1.0, softness * Self.clockWipeSoftnessScale), forKey: kCIInputWidthKey)

        return filter.outputImage?.cropped(to: extent) ?? (progress < 0.5 ? from : to)
    }

    /// Iris wipe: circular reveal from center outward.
    ///
    /// Edge softness is scaled by 0.1 of the maximum radius to create smooth feathering.
    private func renderIrisWipe(
        from: CIImage,
        to: CIImage,
        progress: Double,
        softness: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let maxRadius = sqrt(extent.width * extent.width + extent.height * extent.height) / 2.0
        let currentRadius = CGFloat(progress) * maxRadius
        let edgeSoftness = max(Self.minGradientSoftness, CGFloat(softness) * maxRadius * CGFloat(Self.irisWipeSoftnessScale))

        guard let gradientFilter = CIFilter(name: "CIRadialGradient") else {
            return renderCrossDissolve(from: from, to: to, progress: progress)
        }

        let center = CIVector(x: extent.midX, y: extent.midY)
        gradientFilter.setValue(center, forKey: kCIInputCenterKey)
        gradientFilter.setValue(max(0, currentRadius - edgeSoftness), forKey: "inputRadius0")
        gradientFilter.setValue(currentRadius + edgeSoftness, forKey: "inputRadius1")
        gradientFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradientFilter.setValue(CIColor.black, forKey: "inputColor1")

        guard let mask = gradientFilter.outputImage?.cropped(to: extent) else {
            return renderCrossDissolve(from: from, to: to, progress: progress)
        }

        return blendWithMask(from: from, to: to, mask: mask, extent: extent)
    }

    // MARK: - Slide Transitions

    /// Push: incoming pushes outgoing off screen.
    private func renderPush(
        from: CIImage,
        to: CIImage,
        progress: Double,
        direction: TransitionDirection,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let vec = directionVector(direction)
        let offsetX = CGFloat(progress) * extent.width * CGFloat(vec.x)
        let offsetY = CGFloat(progress) * extent.height * CGFloat(vec.y)

        let fromTranslated = from.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        let incomingStartX = -extent.width * CGFloat(vec.x)
        let incomingStartY = -extent.height * CGFloat(vec.y)
        let toTranslated = to.transformed(by: CGAffineTransform(
            translationX: incomingStartX + offsetX,
            y: incomingStartY + offsetY
        ))

        let composite = toTranslated.applyingFilter("CISourceOverCompositing", parameters: [
            "inputBackgroundImage": fromTranslated,
        ])

        return composite.cropped(to: extent)
    }

    /// Slide over: incoming slides over stationary outgoing.
    private func renderSlideOver(
        from: CIImage,
        to: CIImage,
        progress: Double,
        direction: TransitionDirection,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let vec = directionVector(direction)

        let remainingX = extent.width * CGFloat(vec.x) * CGFloat(1.0 - progress)
        let remainingY = extent.height * CGFloat(vec.y) * CGFloat(1.0 - progress)
        let toTranslated = to.transformed(by: CGAffineTransform(
            translationX: -remainingX,
            y: -remainingY
        ))

        let composite = toTranslated.applyingFilter("CISourceOverCompositing", parameters: [
            "inputBackgroundImage": from,
        ])

        return composite.cropped(to: extent)
    }

    /// Slide under: outgoing slides away revealing incoming underneath.
    private func renderSlideUnder(
        from: CIImage,
        to: CIImage,
        progress: Double,
        direction: TransitionDirection,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let vec = directionVector(direction)
        let offsetX = CGFloat(progress) * extent.width * CGFloat(vec.x)
        let offsetY = CGFloat(progress) * extent.height * CGFloat(vec.y)

        let fromTranslated = from.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        let composite = fromTranslated.applyingFilter("CISourceOverCompositing", parameters: [
            "inputBackgroundImage": to,
        ])

        return composite.cropped(to: extent)
    }

    // MARK: - Zoom Transitions

    /// Zoom: dissolve combined with scale at cut point.
    private func renderZoom(
        from: CIImage,
        to: CIImage,
        progress: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let scale = 1.0 + progress * Self.zoomScaleDelta

        let fromScaled = scaleFromCenter(image: from, scale: CGFloat(scale), extent: extent)
        let toScaled = scaleFromCenter(image: to, scale: CGFloat(2.0 - scale), extent: extent)

        return renderCrossDissolve(from: fromScaled, to: toScaled, progress: progress)
    }

    /// Zoom in: zoom into outgoing clip while dissolving to incoming.
    private func renderZoomIn(
        from: CIImage,
        to: CIImage,
        progress: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let scale = 1.0 + progress * Self.zoomInScaleDelta

        let fromScaled = scaleFromCenter(image: from, scale: CGFloat(scale), extent: extent)

        return renderCrossDissolve(from: fromScaled, to: to, progress: progress)
    }

    /// Zoom out: incoming clip starts zoomed and scales to normal.
    private func renderZoomOut(
        from: CIImage,
        to: CIImage,
        progress: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let toScale = Self.zoomOutInitialScale - progress * Self.zoomInScaleDelta

        let toScaled = scaleFromCenter(image: to, scale: CGFloat(toScale), extent: extent)

        return renderCrossDissolve(from: from, to: toScaled, progress: progress)
    }

    // MARK: - Special Transitions

    /// Blur: blur outgoing out, blur incoming in.
    private func renderBlur(
        from: CIImage,
        to: CIImage,
        progress: Double
    ) -> CIImage {
        let maxRadius = Self.blurMaxRadius

        if progress <= Self.fadeSplitPoint {
            let blurProgress = progress * 2.0
            let radius = blurProgress * maxRadius
            return from.clampedToExtent()
                .applyingGaussianBlur(sigma: radius)
                .cropped(to: from.extent)
        } else {
            let blurProgress = (1.0 - progress) * 2.0
            let radius = blurProgress * maxRadius
            return to.clampedToExtent()
                .applyingGaussianBlur(sigma: radius)
                .cropped(to: to.extent)
        }
    }

    /// Rotation: rotate outgoing away, rotate incoming in with dissolve.
    private func renderRotation(
        from: CIImage,
        to: CIImage,
        progress: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent
        let centerX = extent.midX
        let centerY = extent.midY

        let fromAngle = CGFloat(progress) * Self.rotationAngle
        let fromScale = CGFloat(1.0 - progress * Self.rotationScaleDelta)

        var fromTransform = CGAffineTransform.identity
        fromTransform = fromTransform.translatedBy(x: centerX, y: centerY)
        fromTransform = fromTransform.rotated(by: fromAngle)
        fromTransform = fromTransform.scaledBy(x: fromScale, y: fromScale)
        fromTransform = fromTransform.translatedBy(x: -centerX, y: -centerY)
        let fromRotated = from.transformed(by: fromTransform).cropped(to: extent)

        let toAngle = CGFloat(1.0 - progress) * (-Self.rotationAngle)
        let toScale = CGFloat((1.0 - Self.rotationScaleDelta) + progress * Self.rotationScaleDelta)

        var toTransform = CGAffineTransform.identity
        toTransform = toTransform.translatedBy(x: centerX, y: centerY)
        toTransform = toTransform.rotated(by: toAngle)
        toTransform = toTransform.scaledBy(x: toScale, y: toScale)
        toTransform = toTransform.translatedBy(x: -centerX, y: -centerY)
        let toRotated = to.transformed(by: toTransform).cropped(to: extent)

        return renderCrossDissolve(from: fromRotated, to: toRotated, progress: progress)
    }

    /// Page curl: outgoing curls away like a page using CIPageCurlTransition.
    private func renderPageCurl(
        from: CIImage,
        to: CIImage,
        progress: Double,
        frameSize: CGSize
    ) -> CIImage {
        let extent = from.extent

        guard let filter = CIFilter(name: "CIPageCurlTransition") else {
            return renderCrossDissolve(from: from, to: to, progress: progress)
        }

        let shadingImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
            .cropped(to: extent)

        filter.setValue(from, forKey: kCIInputImageKey)
        filter.setValue(to, forKey: kCIInputTargetImageKey)
        filter.setValue(shadingImage, forKey: "inputShadingImage")
        filter.setValue(shadingImage, forKey: "inputBacksideImage")
        filter.setValue(progress, forKey: "inputTime")
        filter.setValue(CIVector(x: extent.origin.x, y: extent.origin.y,
                                z: extent.width, w: extent.height),
                       forKey: "inputExtent")
        filter.setValue(Self.pageCurlAngle, forKey: kCIInputAngleKey)
        filter.setValue(Self.pageCurlRadius, forKey: kCIInputRadiusKey)

        return filter.outputImage?.cropped(to: extent) ?? (progress < 0.5 ? from : to)
    }

    // MARK: - Helper Methods

    /// Get the normalized translation vector for a `TransitionDirection`.
    private func directionVector(_ direction: TransitionDirection) -> CGPoint {
        switch direction {
        case .left:  return CGPoint(x: -1, y: 0)
        case .right: return CGPoint(x: 1, y: 0)
        case .up:    return CGPoint(x: 0, y: 1)
        case .down:  return CGPoint(x: 0, y: -1)
        }
    }

    /// Generate a linear gradient mask for directional wipe transitions.
    ///
    /// Edge softness is clamped to minimum 1.0 to prevent rendering artifacts.
    private func generateLinearGradientMask(
        direction: TransitionDirection,
        progress: Double,
        softness: Double,
        extent: CGRect
    ) -> CIImage {
        guard let gradient = CIFilter(name: "CILinearGradient") else {
            return CIImage(color: progress < 0.5 ? CIColor.black : CIColor.white)
                .cropped(to: extent)
        }

        let edgeSoftness = max(Self.minGradientSoftness, CGFloat(softness) * max(extent.width, extent.height))

        let point0: CIVector
        let point1: CIVector

        switch direction {
        case .left:
            let pos = extent.width * CGFloat(progress)
            point0 = CIVector(x: pos + edgeSoftness, y: extent.midY)
            point1 = CIVector(x: pos - edgeSoftness, y: extent.midY)
        case .right:
            let pos = extent.width * CGFloat(1.0 - progress)
            point0 = CIVector(x: pos - edgeSoftness, y: extent.midY)
            point1 = CIVector(x: pos + edgeSoftness, y: extent.midY)
        case .up:
            let pos = extent.height * CGFloat(progress)
            point0 = CIVector(x: extent.midX, y: pos + edgeSoftness)
            point1 = CIVector(x: extent.midX, y: pos - edgeSoftness)
        case .down:
            let pos = extent.height * CGFloat(1.0 - progress)
            point0 = CIVector(x: extent.midX, y: pos - edgeSoftness)
            point1 = CIVector(x: extent.midX, y: pos + edgeSoftness)
        }

        gradient.setValue(point0, forKey: "inputPoint0")
        gradient.setValue(CIColor.white, forKey: "inputColor0")
        gradient.setValue(point1, forKey: "inputPoint1")
        gradient.setValue(CIColor.black, forKey: "inputColor1")

        return gradient.outputImage?.cropped(to: extent) ??
            CIImage(color: CIColor.white).cropped(to: extent)
    }

    /// Blend two images using a grayscale mask (white = to, black = from).
    private func blendWithMask(from: CIImage, to: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return from
        }
        blendFilter.setValue(to, forKey: kCIInputImageKey)
        blendFilter.setValue(from, forKey: "inputBackgroundImage")
        blendFilter.setValue(mask, forKey: "inputMaskImage")
        return blendFilter.outputImage?.cropped(to: extent) ?? from
    }

    /// Scale an image from its center point, cropping to original extent.
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
