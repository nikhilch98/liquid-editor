import Testing
@testable import LiquidEditor

// MARK: - TextStylePanel Tests

@Suite("TextStylePanel")
struct TextStylePanelTests {

    @Test("Default style has expected values")
    func defaultStyle() {
        let style = TextStylePanel.defaultStyle
        #expect(style.fontSize == 48.0)
        #expect(style.fontWeight == .bold)
        #expect(style.isItalic == false)
        #expect(style.letterSpacing == 0.0)
        #expect(style.lineHeight == 1.2)
        #expect(style.shadow == nil)
        #expect(style.outline == nil)
        #expect(style.background == nil)
        #expect(style.glow == nil)
    }

    @Test("Preset colors has 10 entries")
    func presetColorsCount() {
        let colors = TextStylePanel.testablePresetColors
        #expect(colors.count == 10)
    }

    @Test("Preset colors include white and black")
    func presetColorsContainWhiteAndBlack() {
        let colors = TextStylePanel.testablePresetColors
        let white = ARGBColor.fromARGB32(0xFFFFFFFF)
        let black = ARGBColor.fromARGB32(0xFF000000)
        #expect(colors.contains(where: { $0.toARGB32 == white.toARGB32 }))
        #expect(colors.contains(where: { $0.toARGB32 == black.toARGB32 }))
    }

    @Test("Weight options has 5 entries")
    func weightOptionsCount() {
        let options = TextStylePanel.testableWeightOptions
        #expect(options.count == 5)
    }

    @Test("Weight options include Light through Heavy")
    func weightOptionsRange() {
        let options = TextStylePanel.testableWeightOptions
        let weights = options.map { $0.0 }
        #expect(weights.contains(.w300))
        #expect(weights.contains(.w400))
        #expect(weights.contains(.w600))
        #expect(weights.contains(.w700))
        #expect(weights.contains(.w900))
    }

    @Test("Style copyWith fontSize preserves other fields")
    func styleWithFontSize() {
        let original = TextOverlayStyle(
            fontSize: 48.0, fontWeight: .bold, isItalic: true, letterSpacing: 2.0
        )
        let modified = original.with(fontSize: 72.0)
        #expect(modified.fontSize == 72.0)
        #expect(modified.fontWeight == .bold)
        #expect(modified.isItalic == true)
        #expect(modified.letterSpacing == 2.0)
    }

    @Test("Style copyWith enables shadow")
    func styleEnableShadow() {
        let style = TextOverlayStyle()
        #expect(style.shadow == nil)
        let withShadow = style.with(shadow: TextShadowStyle())
        #expect(withShadow.shadow != nil)
    }

    @Test("Style copyWith clearShadow removes shadow")
    func styleClearShadow() {
        let style = TextOverlayStyle(shadow: TextShadowStyle())
        #expect(style.shadow != nil)
        let cleared = style.with(clearShadow: true)
        #expect(cleared.shadow == nil)
    }

    @Test("Style copyWith enables outline")
    func styleEnableOutline() {
        let style = TextOverlayStyle()
        let withOutline = style.with(outline: TextOutlineStyle())
        #expect(withOutline.outline != nil)
        #expect(withOutline.outline?.width == 2.0)
    }

    @Test("Style copyWith enables background")
    func styleEnableBackground() {
        let style = TextOverlayStyle()
        let withBg = style.with(background: TextBackgroundStyle())
        #expect(withBg.background != nil)
        #expect(withBg.background?.cornerRadius == 8.0)
    }

    @Test("Style copyWith enables glow")
    func styleEnableGlow() {
        let style = TextOverlayStyle()
        let withGlow = style.with(glow: TextGlowStyle())
        #expect(withGlow.glow != nil)
        #expect(withGlow.glow?.intensity == 0.5)
    }
}
