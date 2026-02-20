import Testing
import CoreGraphics
import Foundation
@testable import LiquidEditor

// MARK: - NormalizedRect Tests

@Suite("NormalizedRect Tests")
struct NormalizedRectTests {

    @Test("Creation with explicit values")
    func creation() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(rect.x == 0.1)
        #expect(rect.y == 0.2)
        #expect(rect.width == 0.3)
        #expect(rect.height == 0.4)
    }

    @Test("fullFrame static constant covers entire frame")
    func fullFrame() {
        let rect = NormalizedRect.fullFrame
        #expect(rect.x == 0.0)
        #expect(rect.y == 0.0)
        #expect(rect.width == 1.0)
        #expect(rect.height == 1.0)
        #expect(rect.isFullFrame)
    }

    @Test("defaultPip static constant has correct values")
    func defaultPip() {
        let rect = NormalizedRect.defaultPip
        #expect(rect.x == 0.6)
        #expect(rect.y == 0.6)
        #expect(rect.width == 0.35)
        #expect(rect.height == 0.35)
        #expect(!rect.isFullFrame)
    }

    @Test("center computes correctly")
    func center() {
        let rect = NormalizedRect(x: 0.2, y: 0.4, width: 0.6, height: 0.2)
        let c = rect.center
        #expect(abs(c.x - 0.5) < 0.0001)
        #expect(abs(c.y - 0.5) < 0.0001)
    }

    @Test("right and bottom edges compute correctly")
    func edges() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(abs(rect.right - 0.4) < 0.0001)
        #expect(abs(rect.bottom - 0.6) < 0.0001)
    }

    @Test("aspectRatio computes correctly")
    func aspectRatio() {
        let rect = NormalizedRect(x: 0, y: 0, width: 0.8, height: 0.4)
        #expect(abs(rect.aspectRatio - 2.0) < 0.0001)
    }

    @Test("aspectRatio returns 1.0 for zero height")
    func aspectRatioZeroHeight() {
        let rect = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.0)
        #expect(rect.aspectRatio == 1.0)
    }

    @Test("toRect converts to pixel coordinates")
    func toRect() {
        let rect = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let outputSize = CGSize(width: 1920, height: 1080)
        let pixelRect = rect.toRect(outputSize: outputSize)

        #expect(abs(pixelRect.origin.x - 480.0) < 0.001)
        #expect(abs(pixelRect.origin.y - 540.0) < 0.001)
        #expect(abs(pixelRect.size.width - 960.0) < 0.001)
        #expect(abs(pixelRect.size.height - 270.0) < 0.001)
    }

    @Test("isFullFrame returns true within tolerance")
    func isFullFrameTolerance() {
        let rect = NormalizedRect(x: 0.0005, y: 0.0005, width: 0.9995, height: 0.9995)
        #expect(rect.isFullFrame)
    }

    @Test("isFullFrame returns false for non-full-frame rect")
    func isFullFrameFalse() {
        let rect = NormalizedRect(x: 0.1, y: 0.0, width: 0.9, height: 1.0)
        #expect(!rect.isFullFrame)
    }

    @Test("with() creates copy with updated fields")
    func withCopy() {
        let original = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let updated = original.with(x: 0.5, height: 0.8)

        #expect(updated.x == 0.5)
        #expect(updated.y == 0.2) // unchanged
        #expect(updated.width == 0.3) // unchanged
        #expect(updated.height == 0.8)
    }

    @Test("clamped restricts values to valid range")
    func clamped() {
        let rect = NormalizedRect(x: -0.1, y: 1.5, width: 2.0, height: 0.5)
        let clamped = rect.clamped()

        #expect(clamped.x == 0.0)
        #expect(clamped.y == 1.0)
        #expect(clamped.width == 1.0) // 1.0 - 0.0
        #expect(clamped.height == 0.0) // 1.0 - 1.0
    }

    @Test("clamped preserves valid values")
    func clampedValid() {
        let rect = NormalizedRect(x: 0.2, y: 0.3, width: 0.5, height: 0.4)
        let clamped = rect.clamped()

        #expect(clamped.x == 0.2)
        #expect(clamped.y == 0.3)
        #expect(clamped.width == 0.5)
        #expect(clamped.height == 0.4)
    }

    @Test("lerp at t=0 returns first rect")
    func lerpAtZero() {
        let a = NormalizedRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        let b = NormalizedRect(x: 1.0, y: 1.0, width: 1.0, height: 1.0)
        let result = NormalizedRect.lerp(a, b, t: 0.0)

        #expect(abs(result.x - 0.0) < 0.0001)
        #expect(abs(result.y - 0.0) < 0.0001)
        #expect(abs(result.width - 0.5) < 0.0001)
        #expect(abs(result.height - 0.5) < 0.0001)
    }

    @Test("lerp at t=1 returns second rect")
    func lerpAtOne() {
        let a = NormalizedRect(x: 0.0, y: 0.0, width: 0.5, height: 0.5)
        let b = NormalizedRect(x: 1.0, y: 1.0, width: 1.0, height: 1.0)
        let result = NormalizedRect.lerp(a, b, t: 1.0)

        #expect(abs(result.x - 1.0) < 0.0001)
        #expect(abs(result.y - 1.0) < 0.0001)
        #expect(abs(result.width - 1.0) < 0.0001)
        #expect(abs(result.height - 1.0) < 0.0001)
    }

    @Test("lerp at t=0.5 returns midpoint")
    func lerpAtHalf() {
        let a = NormalizedRect(x: 0.0, y: 0.0, width: 0.0, height: 0.0)
        let b = NormalizedRect(x: 1.0, y: 1.0, width: 1.0, height: 1.0)
        let result = NormalizedRect.lerp(a, b, t: 0.5)

        #expect(abs(result.x - 0.5) < 0.0001)
        #expect(abs(result.y - 0.5) < 0.0001)
        #expect(abs(result.width - 0.5) < 0.0001)
        #expect(abs(result.height - 0.5) < 0.0001)
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let b = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let c = NormalizedRect(x: 0.5, y: 0.2, width: 0.3, height: 0.4)

        #expect(a == b)
        #expect(a != c)
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let original = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NormalizedRect.self, from: data)

        #expect(decoded == original)
    }

    @Test("Hashable conformance")
    func hashable() {
        let a = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let b = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("description format")
    func descriptionFormat() {
        let rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let desc = rect.description
        #expect(desc.contains("NormalizedRect"))
        #expect(desc.contains("0.1"))
    }
}

// MARK: - ChromaKeyConfig Tests

@Suite("ChromaKeyConfig Tests")
struct ChromaKeyConfigTests {

    @Test("Default creation uses green screen defaults")
    func defaultCreation() {
        let config = ChromaKeyConfig()
        #expect(config.targetColor == .green)
        #expect(config.customColorValue == nil)
        #expect(abs(config.sensitivity - 0.4) < 0.0001)
        #expect(abs(config.smoothness - 0.1) < 0.0001)
        #expect(abs(config.spillSuppression - 0.5) < 0.0001)
        #expect(config.isEnabled)
    }

    @Test("defaultGreen static constant matches defaults")
    func defaultGreen() {
        let config = ChromaKeyConfig.defaultGreen
        #expect(config.targetColor == .green)
        #expect(config.isEnabled)
    }

    @Test("defaultBlue static constant uses blue target")
    func defaultBlue() {
        let config = ChromaKeyConfig.defaultBlue
        #expect(config.targetColor == .blue)
    }

    @Test("Custom color creation")
    func customColor() {
        let config = ChromaKeyConfig(
            targetColor: .custom,
            customColorValue: 0xFFFF_0000,
            sensitivity: 0.6,
            smoothness: 0.3,
            spillSuppression: 0.8,
            isEnabled: false
        )

        #expect(config.targetColor == .custom)
        #expect(config.customColorValue == 0xFFFF_0000)
        #expect(abs(config.sensitivity - 0.6) < 0.0001)
        #expect(abs(config.smoothness - 0.3) < 0.0001)
        #expect(abs(config.spillSuppression - 0.8) < 0.0001)
        #expect(!config.isEnabled)
    }

    @Test("effectiveColorARGB returns correct color for green")
    func effectiveColorGreen() {
        let config = ChromaKeyConfig(targetColor: .green)
        #expect(config.effectiveColorARGB == 0xFF00_FF00)
    }

    @Test("effectiveColorARGB returns correct color for blue")
    func effectiveColorBlue() {
        let config = ChromaKeyConfig(targetColor: .blue)
        #expect(config.effectiveColorARGB == 0xFF00_00FF)
    }

    @Test("effectiveColorARGB returns custom color value")
    func effectiveColorCustom() {
        let config = ChromaKeyConfig(targetColor: .custom, customColorValue: 0xFFAB_CDEF)
        #expect(config.effectiveColorARGB == 0xFFAB_CDEF)
    }

    @Test("effectiveColorARGB falls back to green for custom with nil value")
    func effectiveColorCustomNil() {
        let config = ChromaKeyConfig(targetColor: .custom, customColorValue: nil)
        #expect(config.effectiveColorARGB == 0xFF00_FF00)
    }

    @Test("with() creates copy with updated sensitivity")
    func withCopy() {
        let original = ChromaKeyConfig()
        let updated = original.with(sensitivity: 0.8, isEnabled: false)

        #expect(abs(updated.sensitivity - 0.8) < 0.0001)
        #expect(!updated.isEnabled)
        #expect(updated.targetColor == .green) // unchanged
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let original = ChromaKeyConfig(
            targetColor: .blue,
            sensitivity: 0.6,
            smoothness: 0.3,
            spillSuppression: 0.7,
            isEnabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChromaKeyConfig.self, from: data)

        #expect(decoded == original)
    }

    @Test("Codable roundtrip with custom color")
    func codableCustomColor() throws {
        let original = ChromaKeyConfig(
            targetColor: .custom,
            customColorValue: 0xFFAA_BBCC
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChromaKeyConfig.self, from: data)

        #expect(decoded.targetColor == .custom)
        #expect(decoded.customColorValue == 0xFFAA_BBCC)
    }

    @Test("ChromaKeyColor displayName")
    func chromaKeyColorDisplayName() {
        #expect(ChromaKeyColor.green.displayName == "Green")
        #expect(ChromaKeyColor.blue.displayName == "Blue")
        #expect(ChromaKeyColor.custom.displayName == "Custom")
    }

    @Test("ChromaKeyColor CaseIterable")
    func chromaKeyColorCaseIterable() {
        let allCases = ChromaKeyColor.allCases
        #expect(allCases.count == 3)
        #expect(allCases.contains(.green))
        #expect(allCases.contains(.blue))
        #expect(allCases.contains(.custom))
    }

    @Test("description format")
    func descriptionFormat() {
        let config = ChromaKeyConfig()
        let desc = config.description
        #expect(desc.contains("ChromaKeyConfig"))
        #expect(desc.contains("green"))
    }
}

// MARK: - CompBlendMode Tests

@Suite("CompBlendMode Tests")
struct CompBlendModeTests {

    @Test("All cases exist")
    func allCases() {
        let cases = CompBlendMode.allCases
        #expect(cases.count == 17)
        #expect(cases.contains(.normal))
        #expect(cases.contains(.multiply))
        #expect(cases.contains(.screen))
        #expect(cases.contains(.overlay))
        #expect(cases.contains(.softLight))
        #expect(cases.contains(.hardLight))
        #expect(cases.contains(.colorDodge))
        #expect(cases.contains(.colorBurn))
        #expect(cases.contains(.darken))
        #expect(cases.contains(.lighten))
        #expect(cases.contains(.difference))
        #expect(cases.contains(.exclusion))
        #expect(cases.contains(.add))
        #expect(cases.contains(.luminosity))
        #expect(cases.contains(.hue))
        #expect(cases.contains(.saturation))
        #expect(cases.contains(.color))
    }

    @Test("ciFilterName maps correctly")
    func ciFilterName() {
        #expect(CompBlendMode.normal.ciFilterName == "CISourceOverCompositing")
        #expect(CompBlendMode.multiply.ciFilterName == "CIMultiplyBlendMode")
        #expect(CompBlendMode.screen.ciFilterName == "CIScreenBlendMode")
        #expect(CompBlendMode.overlay.ciFilterName == "CIOverlayBlendMode")
        #expect(CompBlendMode.add.ciFilterName == "CIAdditionCompositing")
        #expect(CompBlendMode.luminosity.ciFilterName == "CILuminosityBlendMode")
        #expect(CompBlendMode.hue.ciFilterName == "CIHueBlendMode")
        #expect(CompBlendMode.saturation.ciFilterName == "CISaturationBlendMode")
        #expect(CompBlendMode.color.ciFilterName == "CIColorBlendMode")
    }

    @Test("displayName returns readable names")
    func displayName() {
        #expect(CompBlendMode.normal.displayName == "Normal")
        #expect(CompBlendMode.softLight.displayName == "Soft Light")
        #expect(CompBlendMode.hardLight.displayName == "Hard Light")
        #expect(CompBlendMode.colorDodge.displayName == "Color Dodge")
        #expect(CompBlendMode.colorBurn.displayName == "Color Burn")
    }

    @Test("category groups blend modes correctly")
    func category() {
        #expect(CompBlendMode.normal.category == "Normal")
        #expect(CompBlendMode.multiply.category == "Darken")
        #expect(CompBlendMode.darken.category == "Darken")
        #expect(CompBlendMode.colorBurn.category == "Darken")
        #expect(CompBlendMode.screen.category == "Lighten")
        #expect(CompBlendMode.lighten.category == "Lighten")
        #expect(CompBlendMode.colorDodge.category == "Lighten")
        #expect(CompBlendMode.add.category == "Lighten")
        #expect(CompBlendMode.overlay.category == "Contrast")
        #expect(CompBlendMode.softLight.category == "Contrast")
        #expect(CompBlendMode.hardLight.category == "Contrast")
        #expect(CompBlendMode.difference.category == "Comparative")
        #expect(CompBlendMode.exclusion.category == "Comparative")
        #expect(CompBlendMode.hue.category == "Component")
        #expect(CompBlendMode.saturation.category == "Component")
        #expect(CompBlendMode.color.category == "Component")
        #expect(CompBlendMode.luminosity.category == "Component")
    }

    @Test("Codable roundtrip for all cases")
    func codable() throws {
        for mode in CompBlendMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(CompBlendMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test("blendModeCategories global has correct structure")
    func blendModeCategoriesGlobal() {
        #expect(blendModeCategories.count == 6)
        #expect(blendModeCategories["Normal"]?.count == 1)
        #expect(blendModeCategories["Darken"]?.count == 3)
        #expect(blendModeCategories["Lighten"]?.count == 4)
        #expect(blendModeCategories["Contrast"]?.count == 3)
        #expect(blendModeCategories["Comparative"]?.count == 2)
        #expect(blendModeCategories["Component"]?.count == 4)
    }
}

// MARK: - CompositeLayout Tests

@Suite("CompositeLayout Tests")
struct CompositeLayoutTests {

    @Test("All cases exist")
    func allCases() {
        let cases = CompositeLayout.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.fullFrame))
        #expect(cases.contains(.pip))
        #expect(cases.contains(.splitScreen))
        #expect(cases.contains(.freeform))
    }

    @Test("displayName returns readable names")
    func displayName() {
        #expect(CompositeLayout.fullFrame.displayName == "Full Frame")
        #expect(CompositeLayout.pip.displayName == "Picture in Picture")
        #expect(CompositeLayout.splitScreen.displayName == "Split Screen")
        #expect(CompositeLayout.freeform.displayName == "Freeform")
    }

    @Test("Codable roundtrip for all cases")
    func codable() throws {
        for layout in CompositeLayout.allCases {
            let data = try JSONEncoder().encode(layout)
            let decoded = try JSONDecoder().decode(CompositeLayout.self, from: data)
            #expect(decoded == layout)
        }
    }

    @Test("rawValue matches expected strings")
    func rawValues() {
        #expect(CompositeLayout.fullFrame.rawValue == "fullFrame")
        #expect(CompositeLayout.pip.rawValue == "pip")
        #expect(CompositeLayout.splitScreen.rawValue == "splitScreen")
        #expect(CompositeLayout.freeform.rawValue == "freeform")
    }
}

// MARK: - TrackCompositeConfig Tests

@Suite("TrackCompositeConfig Tests")
struct TrackCompositeConfigTests {

    @Test("Default creation has correct values")
    func defaultCreation() {
        let config = TrackCompositeConfig()
        #expect(config.layout == .fullFrame)
        #expect(config.opacity == 1.0)
        #expect(config.blendMode == .normal)
        #expect(config.chromaKey == nil)
        #expect(config.pipRegion == nil)
        #expect(config.splitScreenCell == nil)
        #expect(config.splitScreenTemplate == nil)
        #expect(config.volume == 1.0)
    }

    @Test("mainTrack static constant is default")
    func mainTrack() {
        let config = TrackCompositeConfig.mainTrack
        #expect(config.layout == .fullFrame)
        #expect(config.opacity == 1.0)
        #expect(config.blendMode == .normal)
        #expect(config.chromaKey == nil)
    }

    @Test("defaultOverlay has PiP layout with default region")
    func defaultOverlay() {
        let config = TrackCompositeConfig.defaultOverlay
        #expect(config.layout == .pip)
        #expect(config.pipRegion != nil)
        #expect(config.pipRegion?.x == 0.6)
    }

    @Test("defaultChromaKey has full frame layout with green chroma key")
    func defaultChromaKey() {
        let config = TrackCompositeConfig.defaultChromaKey
        #expect(config.layout == .fullFrame)
        #expect(config.chromaKey != nil)
        #expect(config.chromaKey?.targetColor == .green)
        #expect(config.hasChromaKey)
    }

    @Test("hasChromaKey returns false when nil")
    func hasChromaKeyNil() {
        let config = TrackCompositeConfig()
        #expect(!config.hasChromaKey)
    }

    @Test("hasChromaKey returns false when disabled")
    func hasChromaKeyDisabled() {
        let config = TrackCompositeConfig(
            chromaKey: ChromaKeyConfig(isEnabled: false)
        )
        #expect(!config.hasChromaKey)
    }

    @Test("isPip returns correct value")
    func isPip() {
        #expect(TrackCompositeConfig(layout: .pip).isPip)
        #expect(!TrackCompositeConfig(layout: .fullFrame).isPip)
    }

    @Test("isSplitScreen returns correct value")
    func isSplitScreen() {
        #expect(TrackCompositeConfig(layout: .splitScreen).isSplitScreen)
        #expect(!TrackCompositeConfig(layout: .fullFrame).isSplitScreen)
    }

    @Test("with() creates copy preserving unchanged fields")
    func withCopy() {
        let config = TrackCompositeConfig(
            layout: .pip,
            opacity: 0.8,
            blendMode: .multiply,
            pipRegion: .defaultPip,
            volume: 0.5
        )
        let updated = config.with(opacity: 0.5, blendMode: .screen)

        #expect(updated.layout == .pip) // unchanged
        #expect(updated.opacity == 0.5)
        #expect(updated.blendMode == .screen)
        #expect(updated.pipRegion != nil) // unchanged
        #expect(updated.volume == 0.5) // unchanged
    }

    @Test("with() clearChromaKey sets chromaKey to nil")
    func withClearChromaKey() {
        let config = TrackCompositeConfig.defaultChromaKey
        #expect(config.chromaKey != nil)

        let cleared = config.with(clearChromaKey: true)
        #expect(cleared.chromaKey == nil)
    }

    @Test("with() clearPipRegion sets pipRegion to nil")
    func withClearPipRegion() {
        let config = TrackCompositeConfig.defaultOverlay
        #expect(config.pipRegion != nil)

        let cleared = config.with(clearPipRegion: true)
        #expect(cleared.pipRegion == nil)
    }

    @Test("with() clearSplitScreenCell sets splitScreenCell to nil")
    func withClearSplitScreenCell() {
        let config = TrackCompositeConfig(splitScreenCell: 2)
        #expect(config.splitScreenCell == 2)

        let cleared = config.with(clearSplitScreenCell: true)
        #expect(cleared.splitScreenCell == nil)
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let config = TrackCompositeConfig(
            layout: .pip,
            opacity: 0.7,
            blendMode: .screen,
            chromaKey: .defaultGreen,
            pipRegion: .defaultPip,
            volume: 0.8
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(TrackCompositeConfig.self, from: data)

        #expect(decoded.layout == config.layout)
        #expect(decoded.opacity == config.opacity)
        #expect(decoded.blendMode == config.blendMode)
        #expect(decoded.volume == config.volume)
    }

    @Test("description format")
    func descriptionFormat() {
        let config = TrackCompositeConfig(layout: .pip, blendMode: .screen)
        let desc = config.description
        #expect(desc.contains("TrackCompositeConfig"))
        #expect(desc.contains("pip"))
        #expect(desc.contains("screen"))
    }
}

// MARK: - OverlayTransform Tests

@Suite("OverlayTransform Tests")
struct OverlayTransformTests {

    @Test("Identity transform has correct default values")
    func identity() {
        let transform = OverlayTransform.identity
        #expect(abs(transform.position.x - 0.5) < 0.0001)
        #expect(abs(transform.position.y - 0.5) < 0.0001)
        #expect(abs(transform.scale - 1.0) < 0.0001)
        #expect(abs(transform.rotation - 0.0) < 0.0001)
        #expect(abs(transform.opacity - 1.0) < 0.0001)
        #expect(abs(transform.anchor.x - 0.5) < 0.0001)
        #expect(abs(transform.anchor.y - 0.5) < 0.0001)
        #expect(transform.isIdentity)
    }

    @Test("Custom values creation")
    func customValues() {
        let transform = OverlayTransform(
            position: CGPoint(x: 0.2, y: 0.8),
            scale: 0.5,
            rotation: 1.57,
            opacity: 0.7,
            anchor: CGPoint(x: 0.0, y: 1.0)
        )
        #expect(abs(transform.position.x - 0.2) < 0.0001)
        #expect(abs(transform.position.y - 0.8) < 0.0001)
        #expect(abs(transform.scale - 0.5) < 0.0001)
        #expect(abs(transform.rotation - 1.57) < 0.0001)
        #expect(abs(transform.opacity - 0.7) < 0.0001)
        #expect(!transform.isIdentity)
    }

    @Test("defaultPip has correct values")
    func defaultPip() {
        let pip = OverlayTransform.defaultPip
        #expect(abs(pip.position.x - 0.75) < 0.0001)
        #expect(abs(pip.position.y - 0.75) < 0.0001)
        #expect(abs(pip.scale - 0.3) < 0.0001)
        #expect(!pip.isIdentity)
    }

    @Test("isVisible returns true for visible transform")
    func isVisible() {
        let visible = OverlayTransform(opacity: 0.5, anchor: CGPoint(x: 0.5, y: 0.5))
        #expect(visible.isVisible)
    }

    @Test("isVisible returns false for zero opacity")
    func isVisibleZeroOpacity() {
        let invisible = OverlayTransform(
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0,
            rotation: 0.0,
            opacity: 0.0
        )
        #expect(!invisible.isVisible)
    }

    @Test("isVisible returns false for zero scale")
    func isVisibleZeroScale() {
        let invisible = OverlayTransform(
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 0.0
        )
        #expect(!invisible.isVisible)
    }

    @Test("lerp at t=0 returns first transform")
    func lerpZero() {
        let a = OverlayTransform.identity
        let b = OverlayTransform(
            position: CGPoint(x: 0.0, y: 0.0),
            scale: 2.0,
            rotation: 3.14,
            opacity: 0.5
        )
        let result = OverlayTransform.lerp(a, b, t: 0.0)
        #expect(abs(result.position.x - a.position.x) < 0.0001)
        #expect(abs(result.scale - a.scale) < 0.0001)
    }

    @Test("lerp at t=1 returns second transform")
    func lerpOne() {
        let a = OverlayTransform.identity
        let b = OverlayTransform(
            position: CGPoint(x: 0.0, y: 0.0),
            scale: 2.0,
            rotation: 3.14,
            opacity: 0.5
        )
        let result = OverlayTransform.lerp(a, b, t: 1.0)
        #expect(abs(result.position.x - b.position.x) < 0.0001)
        #expect(abs(result.scale - b.scale) < 0.0001)
    }

    @Test("lerp at t=0.5 returns midpoint")
    func lerpHalf() {
        let a = OverlayTransform(
            position: CGPoint(x: 0.0, y: 0.0),
            scale: 0.0,
            rotation: 0.0,
            opacity: 0.0
        )
        let b = OverlayTransform(
            position: CGPoint(x: 1.0, y: 1.0),
            scale: 2.0,
            rotation: 2.0,
            opacity: 1.0
        )
        let result = OverlayTransform.lerp(a, b, t: 0.5)
        #expect(abs(result.position.x - 0.5) < 0.0001)
        #expect(abs(result.scale - 1.0) < 0.0001)
        #expect(abs(result.rotation - 1.0) < 0.0001)
        #expect(abs(result.opacity - 0.5) < 0.0001)
    }

    @Test("lerp clamps opacity to 0.0-1.0")
    func lerpClampsOpacity() {
        let a = OverlayTransform(
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0,
            rotation: 0.0,
            opacity: 0.9
        )
        let b = OverlayTransform(
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0,
            rotation: 0.0,
            opacity: 1.5
        )
        let result = OverlayTransform.lerp(a, b, t: 1.0)
        #expect(result.opacity <= 1.0)
    }

    @Test("with() creates copy with updated fields")
    func withCopy() {
        let original = OverlayTransform.identity
        let updated = original.with(
            position: CGPoint(x: 0.1, y: 0.9),
            scale: 2.0
        )
        #expect(abs(updated.position.x - 0.1) < 0.0001)
        #expect(abs(updated.scale - 2.0) < 0.0001)
        #expect(abs(updated.rotation - 0.0) < 0.0001) // unchanged
        #expect(abs(updated.opacity - 1.0) < 0.0001) // unchanged
    }

    @Test("clamped restricts values to valid ranges")
    func clamped() {
        let transform = OverlayTransform(
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 10.0,
            rotation: 6.28,
            opacity: 2.0,
            anchor: CGPoint(x: -1.0, y: 2.0)
        )
        let clamped = transform.clamped()

        #expect(clamped.scale <= 5.0)
        #expect(clamped.opacity <= 1.0)
        #expect(clamped.anchor.x >= 0.0)
        #expect(clamped.anchor.y <= 1.0)
    }

    @Test("clamped enforces minimum scale")
    func clampedMinScale() {
        let transform = OverlayTransform(
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 0.001,
            rotation: 0.0,
            opacity: 1.0
        )
        let clamped = transform.clamped()
        #expect(clamped.scale >= 0.01)
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let original = OverlayTransform(
            position: CGPoint(x: 0.3, y: 0.7),
            scale: 1.5,
            rotation: 0.785,
            opacity: 0.8,
            anchor: CGPoint(x: 0.25, y: 0.75)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OverlayTransform.self, from: data)

        #expect(abs(decoded.position.x - 0.3) < 0.0001)
        #expect(abs(decoded.position.y - 0.7) < 0.0001)
        #expect(abs(decoded.scale - 1.5) < 0.0001)
        #expect(abs(decoded.rotation - 0.785) < 0.0001)
        #expect(abs(decoded.opacity - 0.8) < 0.0001)
        #expect(abs(decoded.anchor.x - 0.25) < 0.0001)
        #expect(abs(decoded.anchor.y - 0.75) < 0.0001)
    }

    @Test("Codable decoding uses defaults for missing fields")
    func codableDefaults() throws {
        // Minimal JSON with no optional fields
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(OverlayTransform.self, from: data)

        #expect(abs(decoded.position.x - 0.5) < 0.0001)
        #expect(abs(decoded.position.y - 0.5) < 0.0001)
        #expect(abs(decoded.scale - 1.0) < 0.0001)
        #expect(abs(decoded.rotation - 0.0) < 0.0001)
        #expect(abs(decoded.opacity - 1.0) < 0.0001)
    }

    @Test("description format")
    func descriptionFormat() {
        let transform = OverlayTransform.identity
        let desc = transform.description
        #expect(desc.contains("OverlayTransform"))
    }
}

// MARK: - SplitScreenTemplate Tests

@Suite("SplitScreenTemplate Tests")
struct SplitScreenTemplateTests {

    @Test("sideBySide has 2 cells")
    func sideBySide() {
        let template = SplitScreenTemplate.sideBySide
        #expect(template.id == "side_by_side")
        #expect(template.name == "Side by Side")
        #expect(template.rows == 1)
        #expect(template.columns == 2)
        #expect(template.cellCount == 2)
    }

    @Test("topBottom has 2 cells")
    func topBottom() {
        let template = SplitScreenTemplate.topBottom
        #expect(template.id == "top_bottom")
        #expect(template.name == "Top & Bottom")
        #expect(template.rows == 2)
        #expect(template.columns == 1)
        #expect(template.cellCount == 2)
    }

    @Test("grid2x2 has 4 cells")
    func grid2x2() {
        let template = SplitScreenTemplate.grid2x2
        #expect(template.id == "grid_2x2")
        #expect(template.name == "2x2 Grid")
        #expect(template.rows == 2)
        #expect(template.columns == 2)
        #expect(template.cellCount == 4)
    }

    @Test("threeUp has 3 cells")
    func threeUp() {
        let template = SplitScreenTemplate.threeUp
        #expect(template.id == "three_up")
        #expect(template.name == "3-Up (1 + 2)")
        #expect(template.rows == 2)
        #expect(template.columns == 2)
        #expect(template.cellCount == 3)
    }

    @Test("builtInTemplates contains all 4 templates")
    func builtInTemplates() {
        let templates = SplitScreenTemplate.builtInTemplates
        #expect(templates.count == 4)
    }

    @Test("default gapWidth is 0.005")
    func defaultGapWidth() {
        let template = SplitScreenTemplate(
            id: "test",
            name: "Test",
            rows: 1,
            columns: 1,
            cells: [.fullFrame]
        )
        #expect(abs(template.gapWidth - 0.005) < 0.0001)
    }

    @Test("Equatable is identity-based on id")
    func equatable() {
        let a = SplitScreenTemplate(
            id: "test",
            name: "A",
            rows: 1,
            columns: 1,
            cells: [.fullFrame]
        )
        let b = SplitScreenTemplate(
            id: "test",
            name: "B",  // different name, same id
            rows: 2,
            columns: 2,
            cells: [.fullFrame, .defaultPip]
        )
        #expect(a == b)
    }

    @Test("Hashable is identity-based on id")
    func hashable() {
        let a = SplitScreenTemplate(
            id: "test",
            name: "A",
            rows: 1,
            columns: 1,
            cells: [.fullFrame]
        )
        let b = SplitScreenTemplate(
            id: "test",
            name: "B",
            rows: 2,
            columns: 2,
            cells: [.fullFrame]
        )
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let template = SplitScreenTemplate.grid2x2
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(SplitScreenTemplate.self, from: data)

        #expect(decoded.id == template.id)
        #expect(decoded.name == template.name)
        #expect(decoded.rows == template.rows)
        #expect(decoded.columns == template.columns)
        #expect(decoded.cells.count == template.cells.count)
    }

    @Test("description format")
    func descriptionFormat() {
        let template = SplitScreenTemplate.sideBySide
        let desc = template.description
        #expect(desc.contains("SplitScreenTemplate"))
        #expect(desc.contains("Side by Side"))
        #expect(desc.contains("2 cells"))
    }
}

// MARK: - CompositeLayer Tests

@Suite("CompositeLayer Tests")
struct CompositeLayerTests {

    @Test("Creation with all fields")
    func creation() {
        let config = TrackCompositeConfig(
            layout: .pip,
            opacity: 0.8,
            blendMode: .screen,
            pipRegion: .defaultPip
        )
        let layer = CompositeLayer(
            trackId: "track1",
            trackIndex: 1,
            clipId: "clip1",
            clipType: "video",
            mediaAssetId: "asset1",
            sourceTimeMicros: 5_000_000,
            clipOffsetMicros: 1_000_000,
            timelineMicros: 10_000_000,
            compositeConfig: config
        )

        #expect(layer.trackId == "track1")
        #expect(layer.trackIndex == 1)
        #expect(layer.clipId == "clip1")
        #expect(layer.clipType == "video")
        #expect(layer.mediaAssetId == "asset1")
        #expect(layer.sourceTimeMicros == 5_000_000)
        #expect(layer.clipOffsetMicros == 1_000_000)
        #expect(layer.timelineMicros == 10_000_000)
    }

    @Test("toChannelMap contains required fields")
    func toChannelMap() {
        let config = TrackCompositeConfig(
            layout: .pip,
            opacity: 0.8,
            blendMode: .screen,
            pipRegion: .defaultPip
        )
        let layer = CompositeLayer(
            trackId: "t1",
            trackIndex: 0,
            clipId: "c1",
            clipType: "video",
            mediaAssetId: "a1",
            sourceTimeMicros: 1000,
            clipOffsetMicros: 500,
            timelineMicros: 2000,
            compositeConfig: config
        )

        let map = layer.toChannelMap()
        #expect(map["trackId"] as? String == "t1")
        #expect(map["trackIndex"] as? Int == 0)
        #expect(map["clipId"] as? String == "c1")
        #expect(map["clipType"] as? String == "video")
        #expect(map["layout"] as? String == "pip")
        #expect(map["opacity"] as? Double == 0.8)
        #expect(map["blendMode"] as? String == "CIScreenBlendMode")
        #expect(map["mediaAssetId"] as? String == "a1")
        #expect(map["sourceTimeMicros"] as? Int == 1000)
    }

    @Test("toChannelMap includes pipRegion when present")
    func toChannelMapPipRegion() {
        let config = TrackCompositeConfig(
            layout: .pip,
            pipRegion: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        )
        let layer = CompositeLayer(
            trackId: "t1",
            trackIndex: 0,
            clipId: "c1",
            clipType: "video",
            mediaAssetId: nil,
            sourceTimeMicros: nil,
            clipOffsetMicros: 0,
            timelineMicros: 0,
            compositeConfig: config
        )

        let map = layer.toChannelMap()
        let pipMap = map["pipRegion"] as? [String: Double]
        #expect(pipMap != nil)
        #expect(pipMap?["x"] == 0.1)
        #expect(pipMap?["y"] == 0.2)
        #expect(pipMap?["width"] == 0.3)
        #expect(pipMap?["height"] == 0.4)
    }

    @Test("toChannelMap includes chromaKey when present")
    func toChannelMapChromaKey() {
        let config = TrackCompositeConfig(chromaKey: .defaultGreen)
        let layer = CompositeLayer(
            trackId: "t1",
            trackIndex: 0,
            clipId: "c1",
            clipType: "video",
            mediaAssetId: nil,
            sourceTimeMicros: nil,
            clipOffsetMicros: 0,
            timelineMicros: 0,
            compositeConfig: config
        )

        let map = layer.toChannelMap()
        let chromaMap = map["chromaKey"] as? [String: Any]
        #expect(chromaMap != nil)
        #expect(chromaMap?["targetColor"] as? String == "green")
    }

    @Test("toChannelMap excludes nil optional fields")
    func toChannelMapExcludesNils() {
        let config = TrackCompositeConfig()
        let layer = CompositeLayer(
            trackId: "t1",
            trackIndex: 0,
            clipId: "c1",
            clipType: "video",
            mediaAssetId: nil,
            sourceTimeMicros: nil,
            clipOffsetMicros: 0,
            timelineMicros: 0,
            compositeConfig: config
        )

        let map = layer.toChannelMap()
        #expect(map["mediaAssetId"] == nil)
        #expect(map["sourceTimeMicros"] == nil)
        #expect(map["pipRegion"] == nil)
        #expect(map["chromaKey"] == nil)
    }

    @Test("description format")
    func descriptionFormat() {
        let layer = CompositeLayer(
            trackId: "track1",
            trackIndex: 0,
            clipId: "clip1",
            clipType: "video",
            mediaAssetId: nil,
            sourceTimeMicros: nil,
            clipOffsetMicros: 500,
            timelineMicros: 1000,
            compositeConfig: TrackCompositeConfig()
        )
        let desc = layer.description
        #expect(desc.contains("CompositeLayer"))
        #expect(desc.contains("track1"))
        #expect(desc.contains("clip1"))
    }
}

// MARK: - MultiTrackState Tests

@Suite("MultiTrackState Tests")
struct MultiTrackStateTests {

    private func makeTrack(
        _ id: String,
        type: TrackType = .overlayVideo,
        isVisible: Bool = true
    ) -> TrackMetadata {
        TrackMetadata(id: id, name: "Track \(id)", type: type, index: 0, isVisible: isVisible)
    }

    @Test("Empty state has correct defaults")
    func emptyState() {
        let state = MultiTrackState.empty
        #expect(state.trackCount == 0)
        #expect(state.isEmpty)
        #expect(!state.isNotEmpty)
        #expect(state.trackOrder.isEmpty)
        #expect(state.visibleTracksInOrder.isEmpty)
    }

    @Test("Creating state with tracks")
    func creatingWithTracks() {
        let track1 = makeTrack("t1")
        let track2 = makeTrack("t2")
        let state = MultiTrackState(
            tracks: ["t1": track1, "t2": track2],
            trackOrder: ["t1", "t2"],
            compositeConfigs: [
                "t1": .mainTrack,
                "t2": .defaultOverlay,
            ]
        )

        #expect(state.trackCount == 2)
        #expect(!state.isEmpty)
        #expect(state.isNotEmpty)
    }

    @Test("visibleTracksInOrder filters invisible tracks")
    func visibleTracksInOrder() {
        let visible = makeTrack("t1", isVisible: true)
        let invisible = makeTrack("t2", isVisible: false)
        let state = MultiTrackState(
            tracks: ["t1": visible, "t2": invisible],
            trackOrder: ["t1", "t2"]
        )

        let visibleTracks = state.visibleTracksInOrder
        #expect(visibleTracks.count == 1)
        #expect(visibleTracks[0].id == "t1")
    }

    @Test("tracksInOrder respects trackOrder")
    func tracksInOrder() {
        let t1 = makeTrack("t1")
        let t2 = makeTrack("t2")
        let t3 = makeTrack("t3")
        let state = MultiTrackState(
            tracks: ["t1": t1, "t2": t2, "t3": t3],
            trackOrder: ["t3", "t1", "t2"]
        )

        let ordered = state.tracksInOrder
        #expect(ordered.count == 3)
        #expect(ordered[0].id == "t3")
        #expect(ordered[1].id == "t1")
        #expect(ordered[2].id == "t2")
    }

    @Test("configForTrack returns config when present")
    func configForTrackPresent() {
        let config = TrackCompositeConfig(layout: .pip, opacity: 0.5)
        let state = MultiTrackState(
            compositeConfigs: ["t1": config]
        )

        let result = state.configForTrack("t1")
        #expect(result.layout == .pip)
        #expect(result.opacity == 0.5)
    }

    @Test("configForTrack returns default when missing")
    func configForTrackMissing() {
        let state = MultiTrackState.empty
        let result = state.configForTrack("nonexistent")
        #expect(result.layout == .fullFrame)
        #expect(result.opacity == 1.0)
    }

    @Test("overlayTrackCount counts overlay video tracks")
    func overlayTrackCount() {
        let main = makeTrack("t1", type: .mainVideo)
        let overlay1 = makeTrack("t2", type: .overlayVideo)
        let overlay2 = makeTrack("t3", type: .overlayVideo)
        let audio = makeTrack("t4", type: .audio)

        let state = MultiTrackState(
            tracks: ["t1": main, "t2": overlay1, "t3": overlay2, "t4": audio],
            trackOrder: ["t1", "t2", "t3", "t4"]
        )

        #expect(state.overlayTrackCount == 2)
    }

    @Test("with() creates copy with updated tracks")
    func withCopy() {
        let t1 = makeTrack("t1")
        let state = MultiTrackState(
            tracks: ["t1": t1],
            trackOrder: ["t1"]
        )

        let t2 = makeTrack("t2")
        let updated = state.with(
            tracks: ["t1": t1, "t2": t2],
            trackOrder: ["t1", "t2"]
        )

        #expect(updated.trackCount == 2)
        #expect(state.trackCount == 1) // original unchanged
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let t1 = makeTrack("t1", type: .mainVideo)
        let config = TrackCompositeConfig(layout: .fullFrame, opacity: 1.0)
        let state = MultiTrackState(
            tracks: ["t1": t1],
            trackOrder: ["t1"],
            compositeConfigs: ["t1": config]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MultiTrackState.self, from: data)

        #expect(decoded.trackCount == 1)
        #expect(decoded.trackOrder == ["t1"])
        #expect(decoded.tracks["t1"]?.id == "t1")
    }

    @Test("description format")
    func descriptionFormat() {
        let state = MultiTrackState.empty
        #expect(state.description.contains("MultiTrackState"))
        #expect(state.description.contains("0 tracks"))
    }
}

// MARK: - TrackMetadata Tests

@Suite("TrackMetadata Tests")
struct TrackMetadataTests {

    @Test("Default creation with required fields")
    func defaultCreation() {
        let track = TrackMetadata(id: "t1", name: "Track 1", type: .mainVideo, index: 0)
        #expect(track.id == "t1")
        #expect(track.name == "Track 1")
        #expect(track.type == .mainVideo)
        #expect(track.index == 0)
        #expect(track.height == TrackMetadata.heightMedium)
        #expect(!track.isMuted)
        #expect(!track.isSolo)
        #expect(!track.isLocked)
        #expect(track.color == 0xFF58_56D6)
        #expect(!track.isCollapsed)
        #expect(track.isVisible)
    }

    @Test("isVideoTrack returns true for video types")
    func isVideoTrack() {
        let mainVideo = TrackMetadata(id: "t1", name: "V", type: .mainVideo, index: 0)
        let overlay = TrackMetadata(id: "t2", name: "O", type: .overlayVideo, index: 1)
        let audio = TrackMetadata(id: "t3", name: "A", type: .audio, index: 2)

        #expect(mainVideo.isVideoTrack)
        #expect(overlay.isVideoTrack)
        #expect(!audio.isVideoTrack)
    }

    @Test("isAudioOnlyTrack returns true for audio types")
    func isAudioOnlyTrack() {
        let audio = TrackMetadata(id: "t1", name: "A", type: .audio, index: 0)
        let music = TrackMetadata(id: "t2", name: "M", type: .music, index: 1)
        let voiceover = TrackMetadata(id: "t3", name: "V", type: .voiceover, index: 2)
        let video = TrackMetadata(id: "t4", name: "Vid", type: .mainVideo, index: 3)

        #expect(audio.isAudioOnlyTrack)
        #expect(music.isAudioOnlyTrack)
        #expect(voiceover.isAudioOnlyTrack)
        #expect(!video.isAudioOnlyTrack)
    }

    @Test("effectiveHeight returns small height when collapsed")
    func effectiveHeightCollapsed() {
        let track = TrackMetadata(
            id: "t1", name: "T", type: .mainVideo, index: 0,
            height: TrackMetadata.heightLarge,
            isCollapsed: true
        )
        #expect(track.effectiveHeight == TrackMetadata.heightSmall)
    }

    @Test("effectiveHeight returns normal height when not collapsed")
    func effectiveHeightNormal() {
        let track = TrackMetadata(
            id: "t1", name: "T", type: .mainVideo, index: 0,
            height: TrackMetadata.heightLarge,
            isCollapsed: false
        )
        #expect(track.effectiveHeight == TrackMetadata.heightLarge)
    }

    @Test("Height presets have correct values")
    func heightPresets() {
        #expect(TrackMetadata.heightSmall == 44.0)
        #expect(TrackMetadata.heightMedium == 64.0)
        #expect(TrackMetadata.heightLarge == 88.0)
        #expect(TrackMetadata.heightFilmstrip == 120.0)
    }

    @Test("with() creates copy with updated fields")
    func withCopy() {
        let track = TrackMetadata(id: "t1", name: "Track 1", type: .mainVideo, index: 0)
        let updated = track.with(name: "Renamed", index: 2, isMuted: true)

        #expect(updated.id == "t1") // unchanged
        #expect(updated.name == "Renamed")
        #expect(updated.isMuted)
        #expect(updated.index == 2)
        #expect(updated.type == track.type) // unchanged
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let track = TrackMetadata(
            id: "t1",
            name: "Main",
            type: .mainVideo,
            index: 0,
            height: 88.0,
            isMuted: true,
            isSolo: false,
            isLocked: true,
            color: 0xFFFF_0000,
            isCollapsed: false,
            isVisible: true
        )

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(TrackMetadata.self, from: data)

        #expect(decoded.id == track.id)
        #expect(decoded.name == track.name)
        #expect(decoded.type == track.type)
        #expect(decoded.height == track.height)
        #expect(decoded.isMuted == track.isMuted)
        #expect(decoded.isLocked == track.isLocked)
        #expect(decoded.color == track.color)
    }
}

// MARK: - ContentFit Tests

@Suite("ContentFit Tests")
struct ContentFitTests {

    @Test("All cases exist")
    func allCases() {
        let cases = ContentFit.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.fill))
        #expect(cases.contains(.fit))
        #expect(cases.contains(.stretch))
    }

    @Test("displayName returns readable names")
    func displayName() {
        #expect(ContentFit.fill.displayName == "Fill")
        #expect(ContentFit.fit.displayName == "Fit")
        #expect(ContentFit.stretch.displayName == "Stretch")
    }

    @Test("Codable roundtrip")
    func codable() throws {
        for fit in ContentFit.allCases {
            let data = try JSONEncoder().encode(fit)
            let decoded = try JSONDecoder().decode(ContentFit.self, from: data)
            #expect(decoded == fit)
        }
    }
}
