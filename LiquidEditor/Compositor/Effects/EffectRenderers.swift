/// EffectRenderer protocol + nine stateless strategy-pattern effect implementations.
///
/// C5-11 (Premium UI Redesign spec §5): Provides a minimal per-effect strategy
/// surface for the Premium compositor pipeline. Each effect conforms to the
/// same `EffectRenderer` protocol and accepts an `intensity` parameter
/// normalized to [0.0, 1.0], which is mapped internally to the underlying
/// CIFilter's expected range.
///
/// Distinct from `EffectApplier` (in Services/Effects/): `EffectApplier` is
/// parameter-dictionary-driven and dispatches by `EffectType` via a registry;
/// these renderers are typed, direct, and single-parameter for Premium
/// integration paths that know the specific effect at call site.
///
/// Thread Safety: All structs are stateless (`Sendable` by default). CIFilter
/// instances are created inside each `apply` call — CIFilter is not Sendable
/// and must not be stored.
///
/// References:
/// - `EffectApplier` in Services/Effects/EffectApplier.swift
/// - `EffectPipeline` in Services/Effects/EffectPipeline.swift

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

// MARK: - EffectRenderer

/// Strategy interface for applying a single video effect to a frame.
///
/// `intensity` is normalized to [0.0, 1.0]; implementations map this to the
/// underlying CIFilter's expected parameter range.
protocol EffectRenderer: Sendable {
    /// Apply the effect to `image`.
    /// - Parameters:
    ///   - image: Source CIImage.
    ///   - intensity: Normalized intensity in [0.0, 1.0].
    /// - Returns: Filtered CIImage cropped to the input's extent.
    func apply(_ image: CIImage, intensity: Double) -> CIImage
}

// MARK: - Internal Helpers

private enum EffectHelpers {
    /// Clamp a Double to [0.0, 1.0].
    static func clamp01(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    /// Linearly interpolate between `min` and `max` by `t` in [0.0, 1.0].
    static func lerp(_ minValue: Double, _ maxValue: Double, _ t: Double) -> Double {
        minValue + (maxValue - minValue) * clamp01(t)
    }

    /// Crop the filter output to the source extent, returning the source on nil.
    static func output(_ filter: CIFilter?, fallback: CIImage, extent: CGRect) -> CIImage {
        filter?.outputImage?.cropped(to: extent) ?? fallback
    }
}

// MARK: - BlurEffect

/// Gaussian blur (CIGaussianBlur). Intensity 0.0 -> 0 px, 1.0 -> 50 px radius.
struct BlurEffect: EffectRenderer {
    /// Maximum blur radius in pixels at intensity = 1.0.
    private static let maxRadius: Double = 50.0

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let radius = EffectHelpers.lerp(0.0, Self.maxRadius, intensity)
        // clampedToExtent avoids transparent edges from the blur spreading.
        return image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: image.extent)
    }
}

// MARK: - SharpenEffect

/// Unsharp mask (CIUnsharpMask). Intensity 0.0 -> 0, 1.0 -> 2.0 (CIFilter max).
struct SharpenEffect: EffectRenderer {
    /// Maximum unsharp-mask intensity at intensity = 1.0.
    private static let maxIntensity: Double = 2.0

    /// Fixed radius; Apple recommends 2.5 px for typical content.
    private static let radius: Double = 2.5

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(Self.radius, forKey: kCIInputRadiusKey)
        filter.setValue(EffectHelpers.lerp(0.0, Self.maxIntensity, intensity), forKey: kCIInputIntensityKey)
        return EffectHelpers.output(filter, fallback: image, extent: extent)
    }
}

// MARK: - VignetteEffect

/// Vignette (CIVignette). Intensity 0.0 -> 0, 1.0 -> 2.0 (CIFilter max).
struct VignetteEffect: EffectRenderer {
    /// Maximum vignette strength at intensity = 1.0.
    private static let maxIntensity: Double = 2.0

    /// Fixed vignette radius (1.5 = balanced falloff).
    private static let radius: Double = 1.5

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        guard let filter = CIFilter(name: "CIVignette") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(EffectHelpers.lerp(0.0, Self.maxIntensity, intensity), forKey: kCIInputIntensityKey)
        filter.setValue(Self.radius, forKey: kCIInputRadiusKey)
        return EffectHelpers.output(filter, fallback: image, extent: extent)
    }
}

// MARK: - GrainEffect

/// Film grain via CIRandomGenerator + CIScreenBlend.
///
/// Generates animated noise each call (CIRandomGenerator yields the same
/// deterministic pattern — for per-frame variation, callers should composite
/// at different extents or translate the noise image via time). Intensity
/// controls blend opacity from 0.0 to 1.0.
struct GrainEffect: EffectRenderer {
    /// Opacity of grain layer at intensity = 1.0.
    private static let maxOpacity: Double = 0.6

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        let opacity = EffectHelpers.lerp(0.0, Self.maxOpacity, intensity)
        guard opacity > 0.0 else { return image }

        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else {
            return image
        }

        // Desaturate noise so it contributes brightness variation only.
        let mono = noise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.5,
        ])

        // Scale opacity via CIColorMatrix alpha channel.
        let faded = mono.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ]).cropped(to: extent)

        guard let blend = CIFilter(name: "CIScreenBlendMode") else { return image }
        blend.setValue(faded, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return EffectHelpers.output(blend, fallback: image, extent: extent)
    }
}

// MARK: - GlitchEffect

/// Glitch via CIGlassDistortion + chromatic aberration offsets on RGB channels.
struct GlitchEffect: EffectRenderer {
    /// Maximum glass distortion scale at intensity = 1.0.
    ///
    /// CIGlassDistortion's `inputScale` controls displacement magnitude.
    /// 200 gives a strong-but-recognizable wobble at full intensity.
    private static let maxDistortionScale: Double = 200.0

    /// Maximum RGB channel offset in pixels at intensity = 1.0.
    private static let maxChannelOffset: Double = 10.0

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let t = EffectHelpers.clamp01(intensity)
        guard t > 0.0 else { return image }
        let extent = image.extent

        // Step 1: glass distortion (uses CIRandomGenerator as displacement texture).
        let distorted = distort(image, intensity: t, extent: extent)

        // Step 2: chromatic aberration via RGB channel offsets.
        return chromaticAberration(distorted, intensity: t, extent: extent)
    }

    private func distort(_ image: CIImage, intensity: Double, extent: CGRect) -> CIImage {
        guard let texture = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        guard let filter = CIFilter(name: "CIGlassDistortion") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(texture, forKey: "inputTexture")
        filter.setValue(EffectHelpers.lerp(0.0, Self.maxDistortionScale, intensity), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
        return EffectHelpers.output(filter, fallback: image, extent: extent)
    }

    /// Offset red to the left, blue to the right, leave green — fake CA.
    private func chromaticAberration(_ image: CIImage, intensity: Double, extent: CGRect) -> CIImage {
        let offset = EffectHelpers.lerp(0.0, Self.maxChannelOffset, intensity)

        let redOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 1, y: 0, z: 0, w: 0),
        ]).transformed(by: CGAffineTransform(translationX: CGFloat(-offset), y: 0))

        let blueOnly = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 1, w: 0),
        ]).transformed(by: CGAffineTransform(translationX: CGFloat(offset), y: 0))

        // Additive composite of the RGB-separated layers over the original
        // (which carries green + untouched base luminance).
        let redOverBase = redOnly.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
        ])
        let composite = blueOnly.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: redOverBase,
        ])
        return composite.cropped(to: extent)
    }
}

// MARK: - MirrorEffect

/// Horizontal mirror via CIAffineTile on a half-flipped source.
///
/// The left half of the image is reflected onto the right half, producing
/// a symmetric mirror. Intensity is used as a linear fade with the original
/// so callers can dial in the effect gradually.
struct MirrorEffect: EffectRenderer {
    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let t = EffectHelpers.clamp01(intensity)
        guard t > 0.0 else { return image }

        let extent = image.extent
        let halfWidth = extent.width / 2.0

        // Crop the left half, flip horizontally, and composite over the right half.
        let leftHalf = image.cropped(to: CGRect(
            x: extent.minX,
            y: extent.minY,
            width: halfWidth,
            height: extent.height
        ))

        // Flip horizontally around the crop center.
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: extent.minX + extent.width, y: 0)
        transform = transform.scaledBy(x: -1.0, y: 1.0)
        transform = transform.translatedBy(x: -extent.minX, y: 0)
        let flippedLeft = leftHalf.transformed(by: transform)

        let mirrored = flippedLeft.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
        ]).cropped(to: extent)

        // Fade original -> mirrored by `t`.
        let maskColor = CIColor(red: CGFloat(t), green: CGFloat(t), blue: CGFloat(t))
        let mask = CIImage(color: maskColor).cropped(to: extent)
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return mirrored }
        blend.setValue(mirrored, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: "inputBackgroundImage")
        blend.setValue(mask, forKey: "inputMaskImage")
        return EffectHelpers.output(blend, fallback: mirrored, extent: extent)
    }
}

// MARK: - KaleidoscopeEffect

/// Kaleidoscope (CIKaleidoscope). Intensity controls segment count 2 -> 12.
struct KaleidoscopeEffect: EffectRenderer {
    /// Minimum segment count at intensity = 0.0.
    private static let minCount: Double = 2.0

    /// Maximum segment count at intensity = 1.0.
    private static let maxCount: Double = 12.0

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        let count = Int(EffectHelpers.lerp(Self.minCount, Self.maxCount, intensity).rounded())

        guard let filter = CIFilter(name: "CIKaleidoscope") else { return image }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(count, forKey: "inputCount")
        filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
        filter.setValue(0.0, forKey: kCIInputAngleKey)
        return EffectHelpers.output(filter, fallback: image, extent: extent)
    }
}

// MARK: - PixelateEffect

/// Pixelate (CIPixellate). Intensity 0.0 -> 1 px, 1.0 -> 50 px scale.
struct PixelateEffect: EffectRenderer {
    /// Minimum pixel size at intensity = 0.0.
    private static let minScale: Double = 1.0

    /// Maximum pixel size at intensity = 1.0.
    private static let maxScale: Double = 50.0

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        let scale = EffectHelpers.lerp(Self.minScale, Self.maxScale, intensity)

        guard let filter = CIFilter(name: "CIPixellate") else { return image }
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
        return EffectHelpers.output(filter, fallback: image, extent: extent)
    }
}

// MARK: - BloomEffect

/// Bloom (CIBloom). Intensity 0.0 -> 0, 1.0 -> 2.0 (CIFilter max intensity).
struct BloomEffect: EffectRenderer {
    /// Maximum CIBloom intensity at intensity = 1.0.
    private static let maxIntensity: Double = 2.0

    /// Fixed bloom radius in pixels.
    private static let radius: Double = 10.0

    func apply(_ image: CIImage, intensity: Double) -> CIImage {
        let extent = image.extent
        guard let filter = CIFilter(name: "CIBloom") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(Self.radius, forKey: kCIInputRadiusKey)
        filter.setValue(EffectHelpers.lerp(0.0, Self.maxIntensity, intensity), forKey: kCIInputIntensityKey)
        return EffectHelpers.output(filter, fallback: image, extent: extent)
    }
}
