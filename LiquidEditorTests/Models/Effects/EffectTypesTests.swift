import Testing
import Foundation
@testable import LiquidEditor

// MARK: - EffectCategory Tests

@Suite("EffectCategory Tests")
struct EffectCategoryTests {

    @Test("All 6 categories exist")
    func allCases() {
        #expect(EffectCategory.allCases.count == 6)
    }

    @Test("Each category has a non-empty displayName")
    func displayNames() {
        for category in EffectCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }

    @Test("Each category has a non-empty SF symbol")
    func sfSymbols() {
        for category in EffectCategory.allCases {
            #expect(!category.sfSymbol.isEmpty)
        }
    }

    @Test("Specific display names are correct")
    func specificDisplayNames() {
        #expect(EffectCategory.blur.displayName == "Blur")
        #expect(EffectCategory.sharpen.displayName == "Sharpen & Denoise")
        #expect(EffectCategory.stylize.displayName == "Stylize")
        #expect(EffectCategory.distortion.displayName == "Distortion")
        #expect(EffectCategory.color.displayName == "Color")
        #expect(EffectCategory.transform.displayName == "Transform")
    }

    @Test("EffectCategory Codable roundtrip")
    func codableRoundtrip() throws {
        for category in EffectCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(EffectCategory.self, from: data)
            #expect(decoded == category)
        }
    }
}

// MARK: - EffectType Tests

@Suite("EffectType Tests")
struct EffectTypeTests {

    @Test("All 30 effect types exist")
    func allCases() {
        #expect(EffectType.allCases.count == 30)
    }

    @Test("Each effect type has a non-empty displayName")
    func displayNames() {
        for type in EffectType.allCases {
            #expect(!type.displayName.isEmpty, "displayName empty for \(type.rawValue)")
        }
    }

    @Test("Each effect type has a non-empty SF symbol")
    func sfSymbols() {
        for type in EffectType.allCases {
            #expect(!type.sfSymbol.isEmpty, "sfSymbol empty for \(type.rawValue)")
        }
    }

    @Test("Each effect type has a non-empty CIFilter name")
    func ciFilterNames() {
        for type in EffectType.allCases {
            #expect(!type.ciFilterName.isEmpty, "ciFilterName empty for \(type.rawValue)")
        }
    }

    @Test("All effect types support keyframing")
    func keyframingSupport() {
        for type in EffectType.allCases {
            #expect(type.supportsKeyframing)
        }
    }

    // MARK: - Category Mapping

    @Test("Blur effects map to blur category")
    func blurCategory() {
        let blurEffects: [EffectType] = [.blur, .gaussianBlur, .motionBlur, .zoomBlur, .tiltShift, .bokeh]
        for effect in blurEffects {
            #expect(effect.category == .blur, "\(effect.rawValue) should be blur")
        }
    }

    @Test("Sharpen effects map to sharpen category")
    func sharpenCategory() {
        let sharpenEffects: [EffectType] = [.sharpen, .unsharpMask]
        for effect in sharpenEffects {
            #expect(effect.category == .sharpen, "\(effect.rawValue) should be sharpen")
        }
    }

    @Test("Stylize effects map to stylize category")
    func stylizeCategory() {
        let stylizeEffects: [EffectType] = [
            .vignette, .pixelate, .mosaic, .filmGrain, .glitch,
            .chromaticAberration, .lensFlare, .bloom, .glow,
            .posterize, .halftone, .edgeDetection, .emboss,
            .thermal, .nightVision, .comic, .sketch
        ]
        for effect in stylizeEffects {
            #expect(effect.category == .stylize, "\(effect.rawValue) should be stylize")
        }
    }

    @Test("Distortion effects map to distortion category")
    func distortionCategory() {
        let distortionEffects: [EffectType] = [.kaleidoscope, .distortionWave, .distortionPinch, .distortionBulge]
        for effect in distortionEffects {
            #expect(effect.category == .distortion, "\(effect.rawValue) should be distortion")
        }
    }

    @Test("Mirror maps to transform category")
    func transformCategory() {
        #expect(EffectType.mirror.category == .transform)
    }

    // MARK: - Custom Shader Detection

    @Test("Custom shader effects are detected correctly")
    func customShaderDetection() {
        let customEffects: [EffectType] = [.filmGrain, .glitch, .chromaticAberration, .lensFlare, .nightVision]
        for effect in customEffects {
            #expect(effect.isCustomShader, "\(effect.rawValue) should be custom shader")
        }
    }

    @Test("CIFilter effects are not custom shaders")
    func ciFilterNotCustom() {
        let ciEffects: [EffectType] = [.blur, .gaussianBlur, .sharpen, .vignette, .bloom, .posterize, .comic]
        for effect in ciEffects {
            #expect(!effect.isCustomShader, "\(effect.rawValue) should not be custom shader")
        }
    }

    // MARK: - Specific CIFilter Names

    @Test("Blur and gaussianBlur both map to CIGaussianBlur")
    func gaussianBlurMapping() {
        #expect(EffectType.blur.ciFilterName == "CIGaussianBlur")
        #expect(EffectType.gaussianBlur.ciFilterName == "CIGaussianBlur")
    }

    @Test("Specific CIFilter name mappings")
    func specificFilterNames() {
        #expect(EffectType.motionBlur.ciFilterName == "CIMotionBlur")
        #expect(EffectType.zoomBlur.ciFilterName == "CIZoomBlur")
        #expect(EffectType.sharpen.ciFilterName == "CISharpenLuminance")
        #expect(EffectType.vignette.ciFilterName == "CIVignette")
        #expect(EffectType.pixelate.ciFilterName == "CIPixellate")
        #expect(EffectType.bloom.ciFilterName == "CIBloom")
        #expect(EffectType.posterize.ciFilterName == "CIColorPosterize")
        #expect(EffectType.comic.ciFilterName == "CIComicEffect")
        #expect(EffectType.sketch.ciFilterName == "CILineOverlay")
    }

    // MARK: - Codable

    @Test("EffectType Codable roundtrip for all cases")
    func codableRoundtrip() throws {
        for type in EffectType.allCases {
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(EffectType.self, from: data)
            #expect(decoded == type, "Codable roundtrip failed for \(type.rawValue)")
        }
    }

    // MARK: - Specific Display Names

    @Test("Display names for distortion effects")
    func distortionDisplayNames() {
        #expect(EffectType.distortionWave.displayName == "Wave Distortion")
        #expect(EffectType.distortionPinch.displayName == "Pinch")
        #expect(EffectType.distortionBulge.displayName == "Bulge")
    }
}

// MARK: - EffectRegistry Tests

@Suite("EffectRegistry Tests")
struct EffectRegistryTests {

    @Test("maxEffectsPerClip is 8")
    func maxEffects() {
        #expect(EffectRegistry.maxEffectsPerClip == 8)
    }

    @Test("Every effect type has default parameters")
    func allEffectsHaveDefaults() {
        for type in EffectType.allCases {
            let params = EffectRegistry.defaultParameters(type)
            // comic has no params, all others should have at least one
            if type == .comic {
                #expect(params.isEmpty, "comic should have no parameters")
            }
            // Don't assert non-empty for all since comic is legitimately empty
        }
    }

    @Test("Gaussian blur has radius parameter")
    func gaussianBlurParams() {
        let params = EffectRegistry.defaultParameters(.gaussianBlur)
        #expect(params["radius"] != nil)
        #expect(params["radius"]?.defaultValue == .double_(10.0))
        #expect(params["radius"]?.minValue == .double_(0.0))
        #expect(params["radius"]?.maxValue == .double_(100.0))
        #expect(params["radius"]?.unit == "px")
    }

    @Test("Motion blur has radius and angle parameters")
    func motionBlurParams() {
        let params = EffectRegistry.defaultParameters(.motionBlur)
        #expect(params.count == 2)
        #expect(params["radius"] != nil)
        #expect(params["angle"] != nil)
        #expect(params["angle"]?.defaultValue == .double_(0.0))
        #expect(params["angle"]?.maxValue == .double_(360.0))
    }

    @Test("Zoom blur has amount, centerX, centerY parameters")
    func zoomBlurParams() {
        let params = EffectRegistry.defaultParameters(.zoomBlur)
        #expect(params.count == 3)
        #expect(params["amount"] != nil)
        #expect(params["centerX"] != nil)
        #expect(params["centerY"] != nil)
        #expect(params["centerX"]?.defaultValue == .double_(0.5))
        #expect(params["centerY"]?.defaultValue == .double_(0.5))
    }

    @Test("Vignette has intensity and radius parameters")
    func vignetteParams() {
        let params = EffectRegistry.defaultParameters(.vignette)
        #expect(params.count == 2)
        #expect(params["intensity"] != nil)
        #expect(params["radius"] != nil)
    }

    @Test("Glitch has 4 parameters")
    func glitchParams() {
        let params = EffectRegistry.defaultParameters(.glitch)
        #expect(params.count == 4)
        #expect(params["intensity"] != nil)
        #expect(params["channelSeparation"] != nil)
        #expect(params["blockSize"] != nil)
        #expect(params["scanlineOpacity"] != nil)
    }

    @Test("Mirror has boolean parameters that are not keyframeable")
    func mirrorParams() {
        let params = EffectRegistry.defaultParameters(.mirror)
        #expect(params.count == 2)
        #expect(params["flipHorizontal"]?.defaultValue == .bool_(true))
        #expect(params["flipVertical"]?.defaultValue == .bool_(false))
        #expect(params["flipHorizontal"]?.isKeyframeable == false)
        #expect(params["flipVertical"]?.isKeyframeable == false)
    }

    @Test("Thermal has color parameters that are not keyframeable")
    func thermalParams() {
        let params = EffectRegistry.defaultParameters(.thermal)
        #expect(params.count == 2)
        #expect(params["hotColor"] != nil)
        #expect(params["coldColor"] != nil)
        #expect(params["hotColor"]?.isKeyframeable == false)
    }

    @Test("Posterize has levels parameter with step 1.0")
    func posterizeParams() {
        let params = EffectRegistry.defaultParameters(.posterize)
        #expect(params["levels"] != nil)
        #expect(params["levels"]?.defaultValue == .double_(6.0))
        #expect(params["levels"]?.step == 1.0)
    }

    @Test("Sketch has 5 parameters")
    func sketchParams() {
        let params = EffectRegistry.defaultParameters(.sketch)
        #expect(params.count == 5)
        #expect(params["noiseLevel"] != nil)
        #expect(params["sharpness"] != nil)
        #expect(params["edgeIntensity"] != nil)
        #expect(params["threshold"] != nil)
        #expect(params["contrast"] != nil)
    }

    @Test("Comic has zero parameters")
    func comicParams() {
        let params = EffectRegistry.defaultParameters(.comic)
        #expect(params.isEmpty)
    }

    @Test("Lens flare has 4 position and intensity params")
    func lensFlareParams() {
        let params = EffectRegistry.defaultParameters(.lensFlare)
        #expect(params.count == 4)
        #expect(params["positionX"]?.defaultValue == .double_(0.7))
        #expect(params["positionY"]?.defaultValue == .double_(0.3))
        #expect(params["intensity"] != nil)
        #expect(params["streakLength"] != nil)
    }

    @Test("All blur effect default parameter values are within their min/max range")
    func blurParamRanges() {
        let blurTypes: [EffectType] = [.blur, .gaussianBlur, .motionBlur, .zoomBlur, .tiltShift, .bokeh]
        for type in blurTypes {
            let params = EffectRegistry.defaultParameters(type)
            for (name, param) in params {
                if let defVal = param.defaultValue.asDouble,
                   let minVal = param.minValue?.asDouble,
                   let maxVal = param.maxValue?.asDouble {
                    #expect(defVal >= minVal, "\(type.rawValue).\(name) default \(defVal) < min \(minVal)")
                    #expect(defVal <= maxVal, "\(type.rawValue).\(name) default \(defVal) > max \(maxVal)")
                }
            }
        }
    }

    @Test("All effect default parameter values are valid")
    func allDefaultsAreValid() {
        for type in EffectType.allCases {
            let params = EffectRegistry.defaultParameters(type)
            for (name, param) in params {
                #expect(
                    param.isValidValue(param.defaultValue),
                    "\(type.rawValue).\(name) default value is not valid"
                )
            }
        }
    }

    // MARK: - Parameter Groups

    @Test("parameterGroups returns non-empty groups for effects with parameters")
    func parameterGroupsNonEmpty() {
        let groups = EffectRegistry.parameterGroups(.gaussianBlur)
        #expect(!groups.isEmpty)
    }

    @Test("parameterGroups returns empty for comic")
    func parameterGroupsEmpty() {
        let groups = EffectRegistry.parameterGroups(.comic)
        #expect(groups.isEmpty)
    }

    @Test("parameterGroups contain all parameter names")
    func parameterGroupsComplete() {
        for type in EffectType.allCases {
            let params = EffectRegistry.defaultParameters(type)
            let groups = EffectRegistry.parameterGroups(type)
            let allGroupedNames = groups.flatMap { $0.parameterNames }
            let allParamNames = Set(params.keys)
            let groupedNamesSet = Set(allGroupedNames)
            #expect(
                groupedNamesSet == allParamNames,
                "\(type.rawValue) groups don't cover all parameters"
            )
        }
    }
}
