import Foundation

// MARK: - EffectCategory

/// Categories for organizing effects in the browser UI.
enum EffectCategory: String, Codable, CaseIterable, Sendable {
    case blur
    case sharpen
    case stylize
    case distortion
    case color
    case transform

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .blur: "Blur"
        case .sharpen: "Sharpen & Denoise"
        case .stylize: "Stylize"
        case .distortion: "Distortion"
        case .color: "Color"
        case .transform: "Transform"
        }
    }

    /// SF Symbol icon name.
    var sfSymbol: String {
        switch self {
        case .blur: "aqi.medium"
        case .sharpen: "slider.horizontal.3"
        case .stylize: "sparkles"
        case .distortion: "wand.and.rays"
        case .color: "paintpalette"
        case .transform: "crop.rotate"
        }
    }
}

// MARK: - EffectType

/// All available video effect types.
///
/// Each type maps to one or more CIFilter operations on the native side.
/// Reverse, freezeFrame, speedRamp are excluded -- they are clip properties /
/// timeline operations, not CIFilter effects.
enum EffectType: String, Codable, CaseIterable, Sendable {
    // Blur effects
    case blur
    case gaussianBlur
    case motionBlur
    case zoomBlur
    case tiltShift
    case bokeh

    // Sharpen & Enhancement
    case sharpen
    case unsharpMask

    // Stylistic effects
    case vignette
    case pixelate
    case mosaic
    case filmGrain
    case glitch
    case chromaticAberration
    case lensFlare
    case bloom
    case glow
    case posterize
    case halftone

    // Edge & Artistic
    case edgeDetection
    case kaleidoscope
    case mirror

    // Additional Stylistic
    case emboss
    case thermal
    case nightVision
    case comic
    case sketch

    // Distortion
    case distortionWave
    case distortionPinch
    case distortionBulge

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .blur: "Blur"
        case .gaussianBlur: "Gaussian Blur"
        case .motionBlur: "Motion Blur"
        case .zoomBlur: "Zoom Blur"
        case .tiltShift: "Tilt Shift"
        case .bokeh: "Bokeh"
        case .sharpen: "Sharpen"
        case .unsharpMask: "Unsharp Mask"
        case .vignette: "Vignette"
        case .pixelate: "Pixelate"
        case .mosaic: "Mosaic"
        case .filmGrain: "Film Grain"
        case .glitch: "Glitch"
        case .chromaticAberration: "Chromatic Aberration"
        case .lensFlare: "Lens Flare"
        case .bloom: "Bloom"
        case .glow: "Glow"
        case .posterize: "Posterize"
        case .halftone: "Halftone"
        case .edgeDetection: "Edge Detection"
        case .kaleidoscope: "Kaleidoscope"
        case .mirror: "Mirror"
        case .emboss: "Emboss"
        case .thermal: "Thermal"
        case .nightVision: "Night Vision"
        case .comic: "Comic"
        case .sketch: "Sketch"
        case .distortionWave: "Wave Distortion"
        case .distortionPinch: "Pinch"
        case .distortionBulge: "Bulge"
        }
    }

    /// Category for browser grouping.
    var category: EffectCategory {
        switch self {
        case .blur, .gaussianBlur, .motionBlur, .zoomBlur, .tiltShift, .bokeh:
            return .blur
        case .sharpen, .unsharpMask:
            return .sharpen
        case .vignette, .pixelate, .mosaic, .filmGrain, .glitch,
             .chromaticAberration, .lensFlare, .bloom, .glow,
             .posterize, .halftone, .edgeDetection, .emboss,
             .thermal, .nightVision, .comic, .sketch:
            return .stylize
        case .kaleidoscope, .distortionWave, .distortionPinch, .distortionBulge:
            return .distortion
        case .mirror:
            return .transform
        }
    }

    /// Native CIFilter name (or "custom.*" for Metal shaders).
    var ciFilterName: String {
        switch self {
        case .blur: "CIGaussianBlur"
        case .gaussianBlur: "CIGaussianBlur"
        case .motionBlur: "CIMotionBlur"
        case .zoomBlur: "CIZoomBlur"
        case .tiltShift: "CIMaskedVariableBlur"
        case .bokeh: "CIBokehBlur"
        case .sharpen: "CISharpenLuminance"
        case .unsharpMask: "CIUnsharpMask"
        case .vignette: "CIVignette"
        case .pixelate: "CIPixellate"
        case .mosaic: "CICrystallize"
        case .filmGrain: "custom.filmGrain"
        case .glitch: "custom.glitch"
        case .chromaticAberration: "custom.chromaticAberration"
        case .lensFlare: "custom.lensFlare"
        case .bloom: "CIBloom"
        case .glow: "CIGloom"
        case .posterize: "CIColorPosterize"
        case .halftone: "CIDotScreen"
        case .edgeDetection: "CIEdges"
        case .kaleidoscope: "CIKaleidoscope"
        case .mirror: "CIAffineTransform"
        case .emboss: "CIHeightFieldFromMask"
        case .thermal: "CIFalseColor"
        case .nightVision: "custom.nightVision"
        case .comic: "CIComicEffect"
        case .sketch: "CILineOverlay"
        case .distortionWave: "CIBumpDistortion"
        case .distortionPinch: "CIPinchDistortion"
        case .distortionBulge: "CIBumpDistortion"
        }
    }

    /// SF Symbol icon name.
    var sfSymbol: String {
        switch self {
        case .blur: "aqi.medium"
        case .gaussianBlur: "aqi.medium"
        case .motionBlur: "wind"
        case .zoomBlur: "circle.dashed"
        case .tiltShift: "line.3.horizontal"
        case .bokeh: "circle.hexagongrid"
        case .sharpen: "diamond"
        case .unsharpMask: "diamond"
        case .vignette: "circle.bottomhalf.filled"
        case .pixelate: "square.grid.3x3"
        case .mosaic: "rectangle.split.3x3"
        case .filmGrain: "circle.grid.3x3"
        case .glitch: "tv"
        case .chromaticAberration: "rainbow"
        case .lensFlare: "sun.max"
        case .bloom: "sun.haze"
        case .glow: "sparkle"
        case .posterize: "squares.below.rectangle"
        case .halftone: "circle.grid.2x2"
        case .edgeDetection: "square.dashed"
        case .kaleidoscope: "star.circle"
        case .mirror: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .emboss: "square.3.layers.3d"
        case .thermal: "thermometer.medium"
        case .nightVision: "moon.fill"
        case .comic: "text.bubble"
        case .sketch: "pencil.tip"
        case .distortionWave: "water.waves"
        case .distortionPinch: "hand.pinch"
        case .distortionBulge: "circle.fill"
        }
    }

    /// Whether this effect uses a custom Metal shader.
    var isCustomShader: Bool {
        ciFilterName.hasPrefix("custom.")
    }

    /// Whether this effect supports keyframing.
    var supportsKeyframing: Bool { true }
}

// MARK: - EffectRegistry

/// Static registry providing default parameters for each effect type.
enum EffectRegistry {
    /// Maximum number of effects per clip.
    static let maxEffectsPerClip = 8

    /// Get default parameters for an effect type.
    static func defaultParameters(_ type: EffectType) -> [String: EffectParameter] {
        switch type {
        case .blur, .gaussianBlur:
            return gaussianBlurParams()
        case .motionBlur:
            return motionBlurParams()
        case .zoomBlur:
            return zoomBlurParams()
        case .tiltShift:
            return tiltShiftParams()
        case .bokeh:
            return bokehParams()
        case .sharpen:
            return sharpenParams()
        case .unsharpMask:
            return unsharpMaskParams()
        case .vignette:
            return vignetteParams()
        case .pixelate:
            return pixelateParams()
        case .mosaic:
            return mosaicParams()
        case .filmGrain:
            return filmGrainParams()
        case .glitch:
            return glitchParams()
        case .chromaticAberration:
            return chromaticAberrationParams()
        case .lensFlare:
            return lensFlareParams()
        case .bloom:
            return bloomParams()
        case .glow:
            return glowParams()
        case .posterize:
            return posterizeParams()
        case .halftone:
            return halftoneParams()
        case .edgeDetection:
            return edgeDetectionParams()
        case .kaleidoscope:
            return kaleidoscopeParams()
        case .mirror:
            return mirrorParams()
        case .emboss:
            return embossParams()
        case .thermal:
            return thermalParams()
        case .nightVision:
            return nightVisionParams()
        case .comic:
            return comicParams()
        case .sketch:
            return sketchParams()
        case .distortionWave:
            return distortionWaveParams()
        case .distortionPinch:
            return distortionPinchParams()
        case .distortionBulge:
            return distortionBulgeParams()
        }
    }

    /// Get parameter groups for an effect type.
    static func parameterGroups(_ type: EffectType) -> [EffectParameterGroup] {
        let params = defaultParameters(type)
        var groups: [String: [String]] = [:]
        for param in params.values {
            let groupName = param.group ?? "General"
            groups[groupName, default: []].append(param.name)
        }
        return groups.map { key, value in
            EffectParameterGroup(
                name: key,
                displayName: key,
                parameterNames: value
            )
        }
    }

    // MARK: - Parameter Definitions

    private static func gaussianBlurParams() -> [String: EffectParameter] {
        [
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(0.0),
                maxValue: .double_(100.0),
                unit: "px"
            ),
        ]
    }

    private static func motionBlurParams() -> [String: EffectParameter] {
        [
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(0.0),
                maxValue: .double_(100.0),
                unit: "px"
            ),
            "angle": .withDefault(
                name: "angle",
                displayName: "Angle",
                type: .double_,
                defaultValue: .double_(0.0),
                minValue: .double_(0.0),
                maxValue: .double_(360.0),
                unit: "deg"
            ),
        ]
    }

    private static func zoomBlurParams() -> [String: EffectParameter] {
        [
            "amount": .withDefault(
                name: "amount",
                displayName: "Amount",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(0.0),
                maxValue: .double_(100.0)
            ),
            "centerX": .withDefault(
                name: "centerX",
                displayName: "Center X",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "centerY": .withDefault(
                name: "centerY",
                displayName: "Center Y",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
        ]
    }

    private static func tiltShiftParams() -> [String: EffectParameter] {
        [
            "focusCenterY": .withDefault(
                name: "focusCenterY",
                displayName: "Focus Position",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "focusWidth": .withDefault(
                name: "focusWidth",
                displayName: "Focus Width",
                type: .double_,
                defaultValue: .double_(0.3),
                minValue: .double_(0.05),
                maxValue: .double_(1.0)
            ),
            "blurRadius": .withDefault(
                name: "blurRadius",
                displayName: "Blur Radius",
                type: .double_,
                defaultValue: .double_(15.0),
                minValue: .double_(0.0),
                maxValue: .double_(80.0),
                unit: "px"
            ),
        ]
    }

    private static func bokehParams() -> [String: EffectParameter] {
        [
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(0.0),
                maxValue: .double_(50.0),
                unit: "px"
            ),
            "ringAmount": .withDefault(
                name: "ringAmount",
                displayName: "Ring Amount",
                type: .double_,
                defaultValue: .double_(0.0),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "softness": .withDefault(
                name: "softness",
                displayName: "Softness",
                type: .double_,
                defaultValue: .double_(1.0),
                minValue: .double_(0.0),
                maxValue: .double_(10.0)
            ),
        ]
    }

    private static func sharpenParams() -> [String: EffectParameter] {
        [
            "sharpness": .withDefault(
                name: "sharpness",
                displayName: "Sharpness",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(1.0),
                minValue: .double_(0.0),
                maxValue: .double_(20.0),
                unit: "px"
            ),
        ]
    }

    private static func unsharpMaskParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(2.5),
                minValue: .double_(0.0),
                maxValue: .double_(20.0),
                unit: "px"
            ),
        ]
    }

    private static func vignetteParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(1.0),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
        ]
    }

    private static func pixelateParams() -> [String: EffectParameter] {
        [
            "scale": .withDefault(
                name: "scale",
                displayName: "Pixel Size",
                type: .double_,
                defaultValue: .double_(8.0),
                minValue: .double_(1.0),
                maxValue: .double_(100.0),
                unit: "px"
            ),
        ]
    }

    private static func mosaicParams() -> [String: EffectParameter] {
        [
            "radius": .withDefault(
                name: "radius",
                displayName: "Crystal Size",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(1.0),
                maxValue: .double_(100.0),
                unit: "px"
            ),
        ]
    }

    private static func filmGrainParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(0.3),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "grainSize": .withDefault(
                name: "grainSize",
                displayName: "Grain Size",
                type: .double_,
                defaultValue: .double_(1.0),
                minValue: .double_(0.5),
                maxValue: .double_(5.0)
            ),
        ]
    }

    private static func glitchParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "channelSeparation": .withDefault(
                name: "channelSeparation",
                displayName: "Channel Separation",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(0.0),
                maxValue: .double_(50.0),
                unit: "px"
            ),
            "blockSize": .withDefault(
                name: "blockSize",
                displayName: "Block Size",
                type: .double_,
                defaultValue: .double_(0.1),
                minValue: .double_(0.01),
                maxValue: .double_(0.5)
            ),
            "scanlineOpacity": .withDefault(
                name: "scanlineOpacity",
                displayName: "Scanline Opacity",
                type: .double_,
                defaultValue: .double_(0.3),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
        ]
    }

    private static func chromaticAberrationParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(5.0),
                minValue: .double_(0.0),
                maxValue: .double_(30.0),
                unit: "px"
            ),
            "angle": .withDefault(
                name: "angle",
                displayName: "Angle",
                type: .double_,
                defaultValue: .double_(0.0),
                minValue: .double_(0.0),
                maxValue: .double_(360.0),
                unit: "deg"
            ),
        ]
    }

    private static func lensFlareParams() -> [String: EffectParameter] {
        [
            "positionX": .withDefault(
                name: "positionX",
                displayName: "Position X",
                type: .double_,
                defaultValue: .double_(0.7),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "positionY": .withDefault(
                name: "positionY",
                displayName: "Position Y",
                type: .double_,
                defaultValue: .double_(0.3),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "streakLength": .withDefault(
                name: "streakLength",
                displayName: "Streak Length",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
        ]
    }

    private static func bloomParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(0.0),
                maxValue: .double_(50.0),
                unit: "px"
            ),
        ]
    }

    private static func glowParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(10.0),
                minValue: .double_(0.0),
                maxValue: .double_(50.0),
                unit: "px"
            ),
        ]
    }

    private static func posterizeParams() -> [String: EffectParameter] {
        [
            "levels": .withDefault(
                name: "levels",
                displayName: "Levels",
                type: .double_,
                defaultValue: .double_(6.0),
                minValue: .double_(2.0),
                maxValue: .double_(30.0),
                step: 1.0
            ),
        ]
    }

    private static func halftoneParams() -> [String: EffectParameter] {
        [
            "width": .withDefault(
                name: "width",
                displayName: "Dot Size",
                type: .double_,
                defaultValue: .double_(6.0),
                minValue: .double_(1.0),
                maxValue: .double_(50.0),
                unit: "px"
            ),
            "angle": .withDefault(
                name: "angle",
                displayName: "Angle",
                type: .double_,
                defaultValue: .double_(0.0),
                minValue: .double_(0.0),
                maxValue: .double_(360.0),
                unit: "deg"
            ),
            "sharpness": .withDefault(
                name: "sharpness",
                displayName: "Sharpness",
                type: .double_,
                defaultValue: .double_(0.7),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
        ]
    }

    private static func edgeDetectionParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(1.0),
                minValue: .double_(0.0),
                maxValue: .double_(10.0)
            ),
        ]
    }

    private static func kaleidoscopeParams() -> [String: EffectParameter] {
        [
            "count": .withDefault(
                name: "count",
                displayName: "Segments",
                type: .double_,
                defaultValue: .double_(6.0),
                minValue: .double_(2.0),
                maxValue: .double_(24.0),
                step: 1.0
            ),
            "angle": .withDefault(
                name: "angle",
                displayName: "Angle",
                type: .double_,
                defaultValue: .double_(0.0),
                minValue: .double_(0.0),
                maxValue: .double_(360.0),
                unit: "deg"
            ),
        ]
    }

    private static func mirrorParams() -> [String: EffectParameter] {
        [
            "flipHorizontal": .withDefault(
                name: "flipHorizontal",
                displayName: "Horizontal",
                type: .bool_,
                defaultValue: .bool_(true),
                isKeyframeable: false
            ),
            "flipVertical": .withDefault(
                name: "flipVertical",
                displayName: "Vertical",
                type: .bool_,
                defaultValue: .bool_(false),
                isKeyframeable: false
            ),
        ]
    }

    private static func distortionWaveParams() -> [String: EffectParameter] {
        [
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(300.0),
                minValue: .double_(0.0),
                maxValue: .double_(600.0),
                unit: "px"
            ),
            "scale": .withDefault(
                name: "scale",
                displayName: "Scale",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(-1.0),
                maxValue: .double_(1.0)
            ),
        ]
    }

    private static func distortionPinchParams() -> [String: EffectParameter] {
        [
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(300.0),
                minValue: .double_(0.0),
                maxValue: .double_(1000.0),
                unit: "px"
            ),
            "scale": .withDefault(
                name: "scale",
                displayName: "Scale",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
        ]
    }

    private static func distortionBulgeParams() -> [String: EffectParameter] {
        [
            "radius": .withDefault(
                name: "radius",
                displayName: "Radius",
                type: .double_,
                defaultValue: .double_(300.0),
                minValue: .double_(0.0),
                maxValue: .double_(600.0),
                unit: "px"
            ),
            "scale": .withDefault(
                name: "scale",
                displayName: "Scale",
                type: .double_,
                defaultValue: .double_(0.5),
                minValue: .double_(-1.0),
                maxValue: .double_(1.0)
            ),
        ]
    }

    private static func embossParams() -> [String: EffectParameter] {
        [
            "intensity": .withDefault(
                name: "intensity",
                displayName: "Intensity",
                type: .double_,
                defaultValue: .double_(1.0),
                minValue: .double_(0.0),
                maxValue: .double_(5.0)
            ),
        ]
    }

    private static func thermalParams() -> [String: EffectParameter] {
        [
            "hotColor": .withDefault(
                name: "hotColor",
                displayName: "Hot Color",
                type: .color,
                defaultValue: .color(0xFFFF4500), // Orange-red
                isKeyframeable: false
            ),
            "coldColor": .withDefault(
                name: "coldColor",
                displayName: "Cold Color",
                type: .color,
                defaultValue: .color(0xFF0000FF), // Blue
                isKeyframeable: false
            ),
        ]
    }

    private static func nightVisionParams() -> [String: EffectParameter] {
        [
            "brightness": .withDefault(
                name: "brightness",
                displayName: "Brightness",
                type: .double_,
                defaultValue: .double_(0.3),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "noiseIntensity": .withDefault(
                name: "noiseIntensity",
                displayName: "Noise",
                type: .double_,
                defaultValue: .double_(0.15),
                minValue: .double_(0.0),
                maxValue: .double_(0.5)
            ),
        ]
    }

    private static func comicParams() -> [String: EffectParameter] {
        // CIComicEffect has no user-adjustable parameters.
        // Mix/intensity is controlled via the effect-level mix slider.
        [:]
    }

    private static func sketchParams() -> [String: EffectParameter] {
        [
            "noiseLevel": .withDefault(
                name: "noiseLevel",
                displayName: "Noise Level",
                type: .double_,
                defaultValue: .double_(0.07),
                minValue: .double_(0.0),
                maxValue: .double_(0.1)
            ),
            "sharpness": .withDefault(
                name: "sharpness",
                displayName: "Sharpness",
                type: .double_,
                defaultValue: .double_(0.71),
                minValue: .double_(0.0),
                maxValue: .double_(2.0)
            ),
            "edgeIntensity": .withDefault(
                name: "edgeIntensity",
                displayName: "Edge Intensity",
                type: .double_,
                defaultValue: .double_(1.0),
                minValue: .double_(0.0),
                maxValue: .double_(5.0)
            ),
            "threshold": .withDefault(
                name: "threshold",
                displayName: "Threshold",
                type: .double_,
                defaultValue: .double_(0.1),
                minValue: .double_(0.0),
                maxValue: .double_(1.0)
            ),
            "contrast": .withDefault(
                name: "contrast",
                displayName: "Contrast",
                type: .double_,
                defaultValue: .double_(50.0),
                minValue: .double_(0.25),
                maxValue: .double_(200.0)
            ),
        ]
    }
}
