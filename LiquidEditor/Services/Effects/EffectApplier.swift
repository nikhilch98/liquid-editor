/// EffectApplier - Strategy pattern for individual effect application.
///
/// Each implementation handles a category of CIFilter-based effects.
/// Registered in `EffectApplierRegistry` and dispatched by `EffectType`.
///
/// Thread Safety: All appliers are stateless and `Sendable`.
/// They operate on CIImage values without shared mutable state.

import CoreImage
import CoreGraphics
import AVFoundation

// MARK: - EffectApplier Protocol

/// Strategy for applying a single video effect type to a CIImage.
///
/// Implementations are stateless and safe to call from any thread.
/// The `EffectPipeline` dispatches to the appropriate applier
/// based on `EffectType` via the `EffectApplierRegistry`.
protocol EffectApplier: Sendable {
    /// Apply the effect to an input image.
    ///
    /// - Parameters:
    ///   - image: Source CIImage to process.
    ///   - parameters: Resolved parameter values for this effect.
    ///   - frameSize: Output frame dimensions.
    ///   - frameTime: Current frame time (for animated effects like film grain).
    /// - Returns: Processed CIImage with the effect applied.
    func apply(
        to image: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize,
        frameTime: CMTime
    ) -> CIImage
}

// MARK: - Parameter Extraction Helpers

/// Shared parameter extraction utilities for all EffectApplier implementations.
enum EffectParamHelper {
    /// Extract a Double from resolved parameters.
    static func double_(_ params: [String: ParameterValue], _ key: String, default defaultVal: Double) -> Double {
        params[key]?.asDouble ?? defaultVal
    }

    /// Extract a Bool from resolved parameters.
    static func bool_(_ params: [String: ParameterValue], _ key: String, default defaultVal: Bool) -> Bool {
        params[key]?.asBool ?? defaultVal
    }

    /// Extract a color Int from resolved parameters.
    static func colorInt(_ params: [String: ParameterValue], _ key: String, default defaultVal: Int) -> Int {
        params[key]?.asColorInt ?? params[key]?.asInt ?? defaultVal
    }
}

// MARK: - Blur Effects

/// Applies blur-family effects: gaussian, motion, zoom, tilt-shift, bokeh.
struct BlurEffectApplier: EffectApplier {
    let effectType: EffectType

    func apply(
        to image: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize,
        frameTime: CMTime
    ) -> CIImage {
        switch effectType {
        case .blur, .gaussianBlur:
            return applyGaussianBlur(input: image, parameters: parameters)
        case .motionBlur:
            return applyMotionBlur(input: image, parameters: parameters)
        case .zoomBlur:
            return applyZoomBlur(input: image, parameters: parameters, frameSize: frameSize)
        case .tiltShift:
            return applyTiltShift(input: image, parameters: parameters, frameSize: frameSize)
        case .bokeh:
            return applyBokeh(input: image, parameters: parameters)
        default:
            return image
        }
    }

    private func applyGaussianBlur(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let radius = EffectParamHelper.double_(parameters, "radius", default: 10.0)
        let clamped = input.clampedToExtent()
        let blurred = clamped.applyingGaussianBlur(sigma: radius)
        return blurred.cropped(to: input.extent)
    }

    private func applyMotionBlur(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let radius = EffectParamHelper.double_(parameters, "radius", default: 10.0)
        let angle = EffectParamHelper.double_(parameters, "angle", default: 0.0)
        let angleRadians = angle * .pi / 180.0

        guard let filter = CIFilter(name: "CIMotionBlur") else { return input }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(angleRadians, forKey: kCIInputAngleKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyZoomBlur(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let amount = EffectParamHelper.double_(parameters, "amount", default: 10.0)
        let centerX = EffectParamHelper.double_(parameters, "centerX", default: 0.5)
        let centerY = EffectParamHelper.double_(parameters, "centerY", default: 0.5)

        guard let filter = CIFilter(name: "CIZoomBlur") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: CGFloat(centerX) * frameSize.width,
                                y: CGFloat(centerY) * frameSize.height),
                       forKey: kCIInputCenterKey)
        filter.setValue(amount, forKey: "inputAmount")
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyTiltShift(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let focusCenterY = EffectParamHelper.double_(parameters, "focusCenterY", default: 0.5)
        let focusWidth = EffectParamHelper.double_(parameters, "focusWidth", default: 0.3)
        let blurRadius = EffectParamHelper.double_(parameters, "blurRadius", default: 15.0)

        let height = frameSize.height
        let focusCenter = CGFloat(focusCenterY) * height
        let halfWidth = CGFloat(focusWidth) * height / 2.0

        guard let topGradient = CIFilter(name: "CILinearGradient"),
              let bottomGradient = CIFilter(name: "CILinearGradient"),
              let variableBlur = CIFilter(name: "CIMaskedVariableBlur") else {
            return input
        }

        topGradient.setValue(CIVector(x: 0, y: focusCenter + halfWidth),
                           forKey: "inputPoint0")
        topGradient.setValue(CIColor.black, forKey: "inputColor0")
        topGradient.setValue(CIVector(x: 0, y: focusCenter + halfWidth + height * 0.2),
                           forKey: "inputPoint1")
        topGradient.setValue(CIColor.white, forKey: "inputColor1")

        bottomGradient.setValue(CIVector(x: 0, y: focusCenter - halfWidth),
                              forKey: "inputPoint0")
        bottomGradient.setValue(CIColor.black, forKey: "inputColor0")
        bottomGradient.setValue(CIVector(x: 0, y: focusCenter - halfWidth - height * 0.2),
                              forKey: "inputPoint1")
        bottomGradient.setValue(CIColor.white, forKey: "inputColor1")

        guard let topMask = topGradient.outputImage,
              let bottomMask = bottomGradient.outputImage else { return input }

        let combinedMask = topMask.applyingFilter("CIMaximumCompositing",
            parameters: ["inputBackgroundImage": bottomMask])
            .cropped(to: input.extent)

        variableBlur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        variableBlur.setValue(combinedMask, forKey: "inputMask")
        variableBlur.setValue(blurRadius, forKey: kCIInputRadiusKey)

        return variableBlur.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyBokeh(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let radius = EffectParamHelper.double_(parameters, "radius", default: 10.0)
        let ringAmount = EffectParamHelper.double_(parameters, "ringAmount", default: 0.0)
        let softness = EffectParamHelper.double_(parameters, "softness", default: 1.0)

        guard let filter = CIFilter(name: "CIBokehBlur") else {
            // Fallback to gaussian blur
            let clamped = input.clampedToExtent()
            let blurred = clamped.applyingGaussianBlur(sigma: radius)
            return blurred.cropped(to: input.extent)
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(ringAmount, forKey: "inputRingAmount")
        filter.setValue(softness, forKey: "inputSoftness")
        filter.setValue(1.0, forKey: "inputRingSize")
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }
}

// MARK: - Sharpen Effects

/// Applies sharpen-family effects: sharpen luminance, unsharp mask.
struct SharpenEffectApplier: EffectApplier {
    let effectType: EffectType

    func apply(
        to image: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize,
        frameTime: CMTime
    ) -> CIImage {
        switch effectType {
        case .sharpen:
            return applySharpen(input: image, parameters: parameters)
        case .unsharpMask:
            return applyUnsharpMask(input: image, parameters: parameters)
        default:
            return image
        }
    }

    private func applySharpen(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let sharpness = EffectParamHelper.double_(parameters, "sharpness", default: 0.5)
        let radius = EffectParamHelper.double_(parameters, "radius", default: 1.0)

        guard let filter = CIFilter(name: "CISharpenLuminance") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(sharpness, forKey: kCIInputSharpnessKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage ?? input
    }

    private func applyUnsharpMask(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 0.5)
        let radius = EffectParamHelper.double_(parameters, "radius", default: 2.5)

        guard let filter = CIFilter(name: "CIUnsharpMask") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage ?? input
    }
}

// MARK: - Stylistic Effects

/// Applies stylistic effects: vignette, pixelate, mosaic, film grain, glitch,
/// chromatic aberration, bloom, glow, posterize, halftone, edge detection,
/// lens flare, emboss, thermal, night vision, comic, sketch.
struct StylizeEffectApplier: EffectApplier {
    let effectType: EffectType

    func apply(
        to image: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize,
        frameTime: CMTime
    ) -> CIImage {
        switch effectType {
        case .vignette:
            return applyVignette(input: image, parameters: parameters)
        case .pixelate:
            return applyPixelate(input: image, parameters: parameters)
        case .mosaic:
            return applyMosaic(input: image, parameters: parameters)
        case .filmGrain:
            return applyFilmGrain(input: image, parameters: parameters, frameTime: frameTime)
        case .glitch:
            return applyGlitch(input: image, parameters: parameters, frameTime: frameTime, frameSize: frameSize)
        case .chromaticAberration:
            return applyChromaticAberration(input: image, parameters: parameters)
        case .bloom:
            return applyBloom(input: image, parameters: parameters)
        case .glow:
            return applyGlow(input: image, parameters: parameters)
        case .posterize:
            return applyPosterize(input: image, parameters: parameters)
        case .halftone:
            return applyHalftone(input: image, parameters: parameters, frameSize: frameSize)
        case .edgeDetection:
            return applyEdgeDetection(input: image, parameters: parameters)
        case .lensFlare:
            return applyLensFlare(input: image, parameters: parameters, frameSize: frameSize)
        case .emboss:
            return applyEmboss(input: image, parameters: parameters)
        case .thermal:
            return applyThermal(input: image, parameters: parameters)
        case .nightVision:
            return applyNightVision(input: image, parameters: parameters, frameTime: frameTime)
        case .comic:
            return applyComic(input: image)
        case .sketch:
            return applySketch(input: image, parameters: parameters)
        default:
            return image
        }
    }

    private func applyVignette(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 0.5)
        let radius = EffectParamHelper.double_(parameters, "radius", default: 1.0)

        guard let filter = CIFilter(name: "CIVignette") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage ?? input
    }

    private func applyPixelate(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let scale = EffectParamHelper.double_(parameters, "scale", default: 8.0)

        guard let filter = CIFilter(name: "CIPixellate") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: input.extent.midX, y: input.extent.midY),
                       forKey: kCIInputCenterKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyMosaic(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let radius = EffectParamHelper.double_(parameters, "radius", default: 10.0)

        guard let filter = CIFilter(name: "CICrystallize") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(CIVector(x: input.extent.midX, y: input.extent.midY),
                       forKey: kCIInputCenterKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyFilmGrain(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameTime: CMTime
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 0.3)
        let grainSize = EffectParamHelper.double_(parameters, "grainSize", default: 1.0)

        guard let noiseFilter = CIFilter(name: "CIRandomGenerator") else { return input }
        guard var noise = noiseFilter.outputImage else { return input }

        let timeValue = CMTimeGetSeconds(frameTime)
        let offset = CGFloat(timeValue.truncatingRemainder(dividingBy: 1000.0) * 100.0)
        noise = noise.transformed(by: CGAffineTransform(translationX: offset, y: offset))

        if grainSize != 1.0 {
            noise = noise.transformed(by: CGAffineTransform(scaleX: CGFloat(grainSize),
                                                            y: CGFloat(grainSize)))
        }
        noise = noise.cropped(to: input.extent)

        let grainMask = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(intensity) * 0.299,
                                     y: CGFloat(intensity) * 0.587,
                                     z: CGFloat(intensity) * 0.114, w: 0),
            "inputGVector": CIVector(x: CGFloat(intensity) * 0.299,
                                     y: CGFloat(intensity) * 0.587,
                                     z: CGFloat(intensity) * 0.114, w: 0),
            "inputBVector": CIVector(x: CGFloat(intensity) * 0.299,
                                     y: CGFloat(intensity) * 0.587,
                                     z: CGFloat(intensity) * 0.114, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])

        return input.applyingFilter("CIAdditionCompositing", parameters: [
            "inputBackgroundImage": grainMask,
        ]).cropped(to: input.extent)
    }

    private func applyGlitch(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameTime: CMTime,
        frameSize: CGSize
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 0.5)
        let channelSep = EffectParamHelper.double_(parameters, "channelSeparation", default: 10.0)
        let scanlineOpacity = EffectParamHelper.double_(parameters, "scanlineOpacity", default: 0.3)

        let offset = CGFloat(channelSep * intensity)

        let redShift = input.transformed(by: CGAffineTransform(translationX: offset, y: 0))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ]).cropped(to: input.extent)

        let greenChannel = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])

        let blueShift = input.transformed(by: CGAffineTransform(translationX: -offset, y: 0))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ]).cropped(to: input.extent)

        var result = redShift.applyingFilter("CIAdditionCompositing",
            parameters: ["inputBackgroundImage": greenChannel])
        result = result.applyingFilter("CIAdditionCompositing",
            parameters: ["inputBackgroundImage": blueShift])
        result = result.cropped(to: input.extent)

        if scanlineOpacity > 0.01 {
            guard let stripeFilter = CIFilter(name: "CIStripesGenerator") else { return result }
            stripeFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(scanlineOpacity)),
                               forKey: "inputColor0")
            stripeFilter.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0),
                               forKey: "inputColor1")
            stripeFilter.setValue(2.0, forKey: "inputWidth")
            stripeFilter.setValue(0.0, forKey: "inputSharpness")

            if let scanlines = stripeFilter.outputImage?.cropped(to: input.extent) {
                result = result.applyingFilter("CISubtractBlendMode",
                    parameters: ["inputBackgroundImage": scanlines])
                    .cropped(to: input.extent)
            }
        }

        return result
    }

    private func applyChromaticAberration(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 5.0)
        let angle = EffectParamHelper.double_(parameters, "angle", default: 0.0)
        let angleRad = angle * .pi / 180.0

        let dx = CGFloat(intensity * cos(angleRad))
        let dy = CGFloat(intensity * sin(angleRad))

        let redShift = input.transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ]).cropped(to: input.extent)

        let greenChannel = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])

        let blueShift = input.transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ]).cropped(to: input.extent)

        var result = redShift.applyingFilter("CIAdditionCompositing",
            parameters: ["inputBackgroundImage": greenChannel])
        result = result.applyingFilter("CIAdditionCompositing",
            parameters: ["inputBackgroundImage": blueShift])

        return result.cropped(to: input.extent)
    }

    private func applyBloom(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 0.5)
        let radius = EffectParamHelper.double_(parameters, "radius", default: 10.0)

        guard let filter = CIFilter(name: "CIBloom") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyGlow(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 0.5)
        let radius = EffectParamHelper.double_(parameters, "radius", default: 10.0)

        guard let filter = CIFilter(name: "CIGloom") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyLensFlare(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let posX = EffectParamHelper.double_(parameters, "positionX", default: 0.7)
        let posY = EffectParamHelper.double_(parameters, "positionY", default: 0.3)
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 0.5)
        let streakLength = EffectParamHelper.double_(parameters, "streakLength", default: 0.5)

        guard let sunbeams = CIFilter(name: "CISunbeamsGenerator") else { return input }
        sunbeams.setValue(CIVector(x: CGFloat(posX) * frameSize.width,
                                  y: CGFloat(posY) * frameSize.height),
                         forKey: kCIInputCenterKey)
        sunbeams.setValue(CIColor(red: 1, green: 0.95, blue: 0.8, alpha: CGFloat(intensity)),
                        forKey: "inputColor")
        sunbeams.setValue(CGFloat(streakLength) * 200.0, forKey: "inputSunRadius")
        sunbeams.setValue(3.0, forKey: "inputMaxStriationRadius")
        sunbeams.setValue(0.5, forKey: "inputStriationStrength")
        sunbeams.setValue(0.0, forKey: "inputTime")

        guard let flareImage = sunbeams.outputImage?.cropped(to: input.extent) else {
            return input
        }

        return input.applyingFilter("CIScreenBlendMode", parameters: [
            "inputBackgroundImage": flareImage
        ]).cropped(to: input.extent)
    }

    private func applyPosterize(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let levels = EffectParamHelper.double_(parameters, "levels", default: 6.0)

        guard let filter = CIFilter(name: "CIColorPosterize") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(levels, forKey: "inputLevels")
        return filter.outputImage ?? input
    }

    private func applyHalftone(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let width = EffectParamHelper.double_(parameters, "width", default: 6.0)
        let angle = EffectParamHelper.double_(parameters, "angle", default: 0.0)
        let sharpness = EffectParamHelper.double_(parameters, "sharpness", default: 0.7)

        guard let filter = CIFilter(name: "CIDotScreen") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: frameSize.width / 2, y: frameSize.height / 2),
                       forKey: kCIInputCenterKey)
        filter.setValue(angle * .pi / 180.0, forKey: kCIInputAngleKey)
        filter.setValue(width, forKey: kCIInputWidthKey)
        filter.setValue(sharpness, forKey: kCIInputSharpnessKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyEdgeDetection(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 1.0)

        guard let filter = CIFilter(name: "CIEdges") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyEmboss(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let intensity = EffectParamHelper.double_(parameters, "intensity", default: 1.0)

        guard let edges = CIFilter(name: "CIEdges") else { return input }
        edges.setValue(input, forKey: kCIInputImageKey)
        edges.setValue(intensity, forKey: kCIInputIntensityKey)
        guard let edgeImage = edges.outputImage?.cropped(to: input.extent) else { return input }

        return input.applyingFilter("CIAdditionCompositing", parameters: [
            "inputBackgroundImage": edgeImage
        ]).cropped(to: input.extent)
    }

    private func applyThermal(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let hotColorInt = EffectParamHelper.colorInt(parameters, "hotColor", default: 0xFFFF4500)
        let coldColorInt = EffectParamHelper.colorInt(parameters, "coldColor", default: 0xFF0000FF)

        let hotR = CGFloat((hotColorInt >> 16) & 0xFF) / 255.0
        let hotG = CGFloat((hotColorInt >> 8) & 0xFF) / 255.0
        let hotB = CGFloat(hotColorInt & 0xFF) / 255.0

        let coldR = CGFloat((coldColorInt >> 16) & 0xFF) / 255.0
        let coldG = CGFloat((coldColorInt >> 8) & 0xFF) / 255.0
        let coldB = CGFloat(coldColorInt & 0xFF) / 255.0

        guard let filter = CIFilter(name: "CIFalseColor") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIColor(red: coldR, green: coldG, blue: coldB),
                       forKey: "inputColor0")
        filter.setValue(CIColor(red: hotR, green: hotG, blue: hotB),
                       forKey: "inputColor1")
        return filter.outputImage ?? input
    }

    private func applyNightVision(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameTime: CMTime
    ) -> CIImage {
        let brightness = EffectParamHelper.double_(parameters, "brightness", default: 0.3)
        let noiseIntensity = EffectParamHelper.double_(parameters, "noiseIntensity", default: 0.15)

        guard let mono = CIFilter(name: "CIColorMonochrome") else { return input }
        mono.setValue(input, forKey: kCIInputImageKey)
        mono.setValue(CIColor(red: 0.0, green: 1.0, blue: 0.0), forKey: "inputColor")
        mono.setValue(1.0, forKey: kCIInputIntensityKey)
        guard var result = mono.outputImage else { return input }

        guard let brightnessFilter = CIFilter(name: "CIColorControls") else { return result }
        brightnessFilter.setValue(result, forKey: kCIInputImageKey)
        brightnessFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        brightnessFilter.setValue(1.2, forKey: kCIInputContrastKey)
        result = brightnessFilter.outputImage ?? result

        if noiseIntensity > 0.01 {
            guard let noiseFilter = CIFilter(name: "CIRandomGenerator"),
                  var noise = noiseFilter.outputImage else { return result }

            let timeValue = CMTimeGetSeconds(frameTime)
            let offset = CGFloat(timeValue.truncatingRemainder(dividingBy: 1000.0) * 50.0)
            noise = noise.transformed(by: CGAffineTransform(translationX: offset, y: offset))
            noise = noise.cropped(to: input.extent)

            let greenNoise = noise.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(noiseIntensity), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])

            result = result.applyingFilter("CIAdditionCompositing", parameters: [
                "inputBackgroundImage": greenNoise,
            ]).cropped(to: input.extent)
        }

        return result.cropped(to: input.extent)
    }

    private func applyComic(
        input: CIImage
    ) -> CIImage {
        guard let filter = CIFilter(name: "CIComicEffect") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applySketch(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let noiseLevel = EffectParamHelper.double_(parameters, "noiseLevel", default: 0.07)
        let sharpness = EffectParamHelper.double_(parameters, "sharpness", default: 0.71)
        let edgeIntensity = EffectParamHelper.double_(parameters, "edgeIntensity", default: 1.0)
        let threshold = EffectParamHelper.double_(parameters, "threshold", default: 0.1)
        let contrast = EffectParamHelper.double_(parameters, "contrast", default: 50.0)

        guard let filter = CIFilter(name: "CILineOverlay") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(noiseLevel, forKey: "inputNRNoiseLevel")
        filter.setValue(sharpness, forKey: "inputNRSharpness")
        filter.setValue(edgeIntensity, forKey: "inputEdgeIntensity")
        filter.setValue(threshold, forKey: "inputThreshold")
        filter.setValue(contrast, forKey: "inputContrast")
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }
}

// MARK: - Distortion Effects

/// Applies distortion effects: wave, pinch, bulge.
struct DistortEffectApplier: EffectApplier {
    let effectType: EffectType

    func apply(
        to image: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize,
        frameTime: CMTime
    ) -> CIImage {
        switch effectType {
        case .distortionWave:
            return applyDistortionWave(input: image, parameters: parameters, frameSize: frameSize)
        case .distortionPinch:
            return applyDistortionPinch(input: image, parameters: parameters, frameSize: frameSize)
        case .distortionBulge:
            return applyDistortionBulge(input: image, parameters: parameters, frameSize: frameSize)
        default:
            return image
        }
    }

    private func applyDistortionWave(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let radius = EffectParamHelper.double_(parameters, "radius", default: 300.0)
        let scale = EffectParamHelper.double_(parameters, "scale", default: 0.5)

        guard let filter = CIFilter(name: "CIBumpDistortion") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: frameSize.width / 2, y: frameSize.height / 2),
                       forKey: kCIInputCenterKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyDistortionPinch(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let radius = EffectParamHelper.double_(parameters, "radius", default: 300.0)
        let scale = EffectParamHelper.double_(parameters, "scale", default: 0.5)

        guard let filter = CIFilter(name: "CIPinchDistortion") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: frameSize.width / 2, y: frameSize.height / 2),
                       forKey: kCIInputCenterKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private func applyDistortionBulge(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let radius = EffectParamHelper.double_(parameters, "radius", default: 300.0)
        let scale = EffectParamHelper.double_(parameters, "scale", default: 0.5)

        guard let filter = CIFilter(name: "CIBumpDistortion") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: frameSize.width / 2, y: frameSize.height / 2),
                       forKey: kCIInputCenterKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(-scale, forKey: kCIInputScaleKey) // Negative for bulge
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }
}

// MARK: - Transform Effects

/// Applies transform effects: mirror/flip.
struct TransformEffectApplier: EffectApplier {
    let effectType: EffectType

    func apply(
        to image: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize,
        frameTime: CMTime
    ) -> CIImage {
        switch effectType {
        case .mirror:
            return applyMirror(input: image, parameters: parameters)
        case .kaleidoscope:
            return applyKaleidoscope(input: image, parameters: parameters, frameSize: frameSize)
        default:
            return image
        }
    }

    private func applyMirror(
        input: CIImage,
        parameters: [String: ParameterValue]
    ) -> CIImage {
        let flipH = EffectParamHelper.bool_(parameters, "flipHorizontal", default: false)
        let flipV = EffectParamHelper.bool_(parameters, "flipVertical", default: false)

        if !flipH && !flipV { return input }

        var transform = CGAffineTransform.identity
        let extent = input.extent

        if flipH {
            transform = transform
                .translatedBy(x: extent.width, y: 0)
                .scaledBy(x: -1, y: 1)
        }
        if flipV {
            transform = transform
                .translatedBy(x: 0, y: extent.height)
                .scaledBy(x: 1, y: -1)
        }

        return input.transformed(by: transform)
    }

    private func applyKaleidoscope(
        input: CIImage,
        parameters: [String: ParameterValue],
        frameSize: CGSize
    ) -> CIImage {
        let count = EffectParamHelper.double_(parameters, "count", default: 6.0)
        let angle = EffectParamHelper.double_(parameters, "angle", default: 0.0)

        guard let filter = CIFilter(name: "CIKaleidoscope") else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(count, forKey: "inputCount")
        filter.setValue(CIVector(x: frameSize.width / 2, y: frameSize.height / 2),
                       forKey: kCIInputCenterKey)
        filter.setValue(angle * .pi / 180.0, forKey: kCIInputAngleKey)
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }
}

// MARK: - EffectApplierRegistry

/// Registry mapping `EffectType` to `EffectApplier` instances.
///
/// Replaces the giant switch statement in `EffectPipeline` with a
/// dictionary lookup. All appliers are created eagerly at init time.
///
/// Thread Safety: The registry is immutable after init and `Sendable`.
final class EffectApplierRegistry: Sendable {
    /// Shared singleton instance.
    static let shared = EffectApplierRegistry()

    /// Lookup table: EffectType -> EffectApplier.
    private let appliers: [EffectType: any EffectApplier]

    private init() {
        var registry: [EffectType: any EffectApplier] = [:]

        // Blur effects
        for type in [EffectType.blur, .gaussianBlur, .motionBlur, .zoomBlur, .tiltShift, .bokeh] {
            registry[type] = BlurEffectApplier(effectType: type)
        }

        // Sharpen effects
        for type in [EffectType.sharpen, .unsharpMask] {
            registry[type] = SharpenEffectApplier(effectType: type)
        }

        // Stylistic effects
        for type: EffectType in [
            .vignette, .pixelate, .mosaic, .filmGrain, .glitch,
            .chromaticAberration, .bloom, .glow, .posterize, .halftone,
            .edgeDetection, .lensFlare, .emboss, .thermal, .nightVision,
            .comic, .sketch,
        ] {
            registry[type] = StylizeEffectApplier(effectType: type)
        }

        // Distortion effects
        for type in [EffectType.distortionWave, .distortionPinch, .distortionBulge] {
            registry[type] = DistortEffectApplier(effectType: type)
        }

        // Transform effects
        for type in [EffectType.mirror, .kaleidoscope] {
            registry[type] = TransformEffectApplier(effectType: type)
        }

        appliers = registry
    }

    /// Look up the applier for a given effect type.
    func applier(for type: EffectType) -> (any EffectApplier)? {
        appliers[type]
    }
}
