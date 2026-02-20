import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - TextShadowStyle Tests

@Suite("TextShadowStyle Tests")
struct TextShadowStyleTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let shadow = TextShadowStyle()
        #expect(shadow.offsetX == 0.02)
        #expect(shadow.offsetY == 0.02)
        #expect(shadow.blurRadius == 4.0)
        #expect(shadow.color == ARGBColor.fromARGB32(0x80000000))
    }

    @Test("creation with custom values")
    func creationCustom() {
        let color = ARGBColor.fromARGB32(0xFFFF0000)
        let shadow = TextShadowStyle(color: color, offsetX: 0.1, offsetY: 0.2, blurRadius: 8.0)
        #expect(shadow.color == color)
        #expect(shadow.offsetX == 0.1)
        #expect(shadow.offsetY == 0.2)
        #expect(shadow.blurRadius == 8.0)
    }

    @Test("with() copy preserves unchanged fields")
    func withCopy() {
        let shadow = TextShadowStyle()
        let modified = shadow.with(blurRadius: 10.0)
        #expect(modified.blurRadius == 10.0)
        #expect(modified.offsetX == shadow.offsetX)
        #expect(modified.offsetY == shadow.offsetY)
        #expect(modified.color == shadow.color)
    }

    @Test("with() copy changes specified fields")
    func withCopyChanges() {
        let shadow = TextShadowStyle()
        let newColor = ARGBColor.fromARGB32(0xFF00FF00)
        let modified = shadow.with(color: newColor, offsetX: 0.5)
        #expect(modified.color == newColor)
        #expect(modified.offsetX == 0.5)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let shadow = TextShadowStyle(
            color: .fromARGB32(0xFFAABBCC),
            offsetX: 0.05,
            offsetY: 0.03,
            blurRadius: 6.0
        )
        let data = try JSONEncoder().encode(shadow)
        let decoded = try JSONDecoder().decode(TextShadowStyle.self, from: data)
        #expect(decoded == shadow)
    }

    @Test("Codable encodes color as integer")
    func codableColorFormat() throws {
        let shadow = TextShadowStyle(color: .fromARGB32(0xFF112233))
        let data = try JSONEncoder().encode(shadow)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["color"] as? Int == 0xFF112233)
    }
}

// MARK: - TextOutlineStyle Tests

@Suite("TextOutlineStyle Tests")
struct TextOutlineStyleTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let outline = TextOutlineStyle()
        #expect(outline.color == ARGBColor.fromARGB32(0xFF000000))
        #expect(outline.width == 2.0)
    }

    @Test("with() copy")
    func withCopy() {
        let outline = TextOutlineStyle()
        let modified = outline.with(width: 5.0)
        #expect(modified.width == 5.0)
        #expect(modified.color == outline.color)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let outline = TextOutlineStyle(color: .fromARGB32(0xFFDDEEFF), width: 3.5)
        let data = try JSONEncoder().encode(outline)
        let decoded = try JSONDecoder().decode(TextOutlineStyle.self, from: data)
        #expect(decoded == outline)
    }
}

// MARK: - TextBackgroundStyle Tests

@Suite("TextBackgroundStyle Tests")
struct TextBackgroundStyleTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let bg = TextBackgroundStyle()
        #expect(bg.color == ARGBColor.fromARGB32(0x80000000))
        #expect(bg.cornerRadius == 8.0)
        #expect(bg.paddingHorizontal == 12.0)
        #expect(bg.paddingVertical == 6.0)
    }

    @Test("with() copy")
    func withCopy() {
        let bg = TextBackgroundStyle()
        let modified = bg.with(cornerRadius: 16.0, paddingHorizontal: 20.0)
        #expect(modified.cornerRadius == 16.0)
        #expect(modified.paddingHorizontal == 20.0)
        #expect(modified.paddingVertical == bg.paddingVertical)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let bg = TextBackgroundStyle(
            color: .fromARGB32(0x40FFFFFF),
            cornerRadius: 12.0,
            paddingHorizontal: 16.0,
            paddingVertical: 8.0
        )
        let data = try JSONEncoder().encode(bg)
        let decoded = try JSONDecoder().decode(TextBackgroundStyle.self, from: data)
        #expect(decoded == bg)
    }
}

// MARK: - TextGlowStyle Tests

@Suite("TextGlowStyle Tests")
struct TextGlowStyleTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let glow = TextGlowStyle()
        #expect(glow.color == ARGBColor.fromARGB32(0xFF007AFF))
        #expect(glow.radius == 10.0)
        #expect(glow.intensity == 0.5)
    }

    @Test("with() copy")
    func withCopy() {
        let glow = TextGlowStyle()
        let modified = glow.with(radius: 20.0, intensity: 0.8)
        #expect(modified.radius == 20.0)
        #expect(modified.intensity == 0.8)
        #expect(modified.color == glow.color)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let glow = TextGlowStyle(
            color: .fromARGB32(0xFFFF00FF),
            radius: 15.0,
            intensity: 0.7
        )
        let data = try JSONEncoder().encode(glow)
        let decoded = try JSONDecoder().decode(TextGlowStyle.self, from: data)
        #expect(decoded == glow)
    }
}

// MARK: - TextDecorationType Tests

@Suite("TextDecorationType Tests")
struct TextDecorationTypeTests {

    @Test("none has rawValue 0")
    func noneRawValue() {
        #expect(TextDecorationType.none.rawValue == 0)
    }

    @Test("underline flag")
    func underlineFlag() {
        #expect(TextDecorationType.underline.rawValue == 1)
    }

    @Test("overline flag")
    func overlineFlag() {
        #expect(TextDecorationType.overline.rawValue == 2)
    }

    @Test("lineThrough flag")
    func lineThroughFlag() {
        #expect(TextDecorationType.lineThrough.rawValue == 4)
    }

    @Test("combining flags")
    func combiningFlags() {
        let combined: TextDecorationType = [.underline, .lineThrough]
        #expect(combined.contains(.underline))
        #expect(combined.contains(.lineThrough))
        #expect(!combined.contains(.overline))
        #expect(combined.rawValue == 5)
    }

    @Test("Codable encodes as string array")
    func codableEncodesAsArray() throws {
        let decoration: TextDecorationType = [.underline, .overline]
        let data = try JSONEncoder().encode(decoration)
        let array = try JSONDecoder().decode([String].self, from: data)
        #expect(array.contains("underline"))
        #expect(array.contains("overline"))
        #expect(!array.contains("lineThrough"))
    }

    @Test("Codable roundtrip with combined flags")
    func codableRoundtrip() throws {
        let decoration: TextDecorationType = [.underline, .lineThrough]
        let data = try JSONEncoder().encode(decoration)
        let decoded = try JSONDecoder().decode(TextDecorationType.self, from: data)
        #expect(decoded == decoration)
    }

    @Test("Codable roundtrip with none")
    func codableRoundtripNone() throws {
        let decoration: TextDecorationType = .none
        let data = try JSONEncoder().encode(decoration)
        let decoded = try JSONDecoder().decode(TextDecorationType.self, from: data)
        #expect(decoded == decoration)
    }
}

// MARK: - FontWeightValue Tests

@Suite("FontWeightValue Tests")
struct FontWeightValueTests {

    @Test("all cases have correct rawValues")
    func allCasesRawValues() {
        #expect(FontWeightValue.w100.rawValue == 100)
        #expect(FontWeightValue.w200.rawValue == 200)
        #expect(FontWeightValue.w300.rawValue == 300)
        #expect(FontWeightValue.w400.rawValue == 400)
        #expect(FontWeightValue.w500.rawValue == 500)
        #expect(FontWeightValue.w600.rawValue == 600)
        #expect(FontWeightValue.w700.rawValue == 700)
        #expect(FontWeightValue.w800.rawValue == 800)
        #expect(FontWeightValue.w900.rawValue == 900)
    }

    @Test("aliases match cases")
    func aliases() {
        #expect(FontWeightValue.thin == .w100)
        #expect(FontWeightValue.extraLight == .w200)
        #expect(FontWeightValue.light == .w300)
        #expect(FontWeightValue.regular == .w400)
        #expect(FontWeightValue.medium == .w500)
        #expect(FontWeightValue.semiBold == .w600)
        #expect(FontWeightValue.bold == .w700)
        #expect(FontWeightValue.extraBold == .w800)
        #expect(FontWeightValue.black == .w900)
    }

    @Test("CaseIterable has 9 cases")
    func caseCount() {
        #expect(FontWeightValue.allCases.count == 9)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for weight in FontWeightValue.allCases {
            let data = try JSONEncoder().encode(weight)
            let decoded = try JSONDecoder().decode(FontWeightValue.self, from: data)
            #expect(decoded == weight)
        }
    }
}

// MARK: - TextAnimationPreset Tests

@Suite("TextAnimationPreset Tests")
struct TextAnimationPresetTests {

    @Test("TextAnimationPresetType has 28 cases")
    func presetTypeCount() {
        #expect(TextAnimationPresetType.allCases.count == 28)
    }

    @Test("all preset type rawValues are strings")
    func allRawValues() {
        for preset in TextAnimationPresetType.allCases {
            #expect(!preset.rawValue.isEmpty)
        }
    }

    @Test("creation with defaults")
    func creationDefaults() {
        let preset = TextAnimationPreset(type: .fadeIn)
        #expect(preset.type == .fadeIn)
        #expect(preset.intensity == 1.0)
        #expect(preset.parameters.isEmpty)
    }

    @Test("creation with custom values")
    func creationCustom() {
        let preset = TextAnimationPreset(
            type: .bounceIn,
            intensity: 0.7,
            parameters: ["loopDuration": 2.0]
        )
        #expect(preset.type == .bounceIn)
        #expect(preset.intensity == 0.7)
        #expect(preset.parameters["loopDuration"] == 2.0)
    }

    @Test("with() copy")
    func withCopy() {
        let preset = TextAnimationPreset(type: .fadeIn, intensity: 0.5)
        let modified = preset.with(type: .slideInLeft)
        #expect(modified.type == .slideInLeft)
        #expect(modified.intensity == 0.5)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let preset = TextAnimationPreset(
            type: .glitchIn,
            intensity: 0.8,
            parameters: ["speed": 1.5, "direction": 45.0]
        )
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(TextAnimationPreset.self, from: data)
        #expect(decoded == preset)
    }

    @Test("Codable roundtrip for all types")
    func codableAllTypes() throws {
        for presetType in TextAnimationPresetType.allCases {
            let preset = TextAnimationPreset(type: presetType)
            let data = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(TextAnimationPreset.self, from: data)
            #expect(decoded.type == presetType)
        }
    }
}

// MARK: - TextKeyframe Tests

@Suite("TextKeyframe Tests")
struct TextKeyframeTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let kf = TextKeyframe(
            id: "kf1",
            timestampMicros: 1_000_000,
            position: CGPoint(x: 0.5, y: 0.5)
        )
        #expect(kf.id == "kf1")
        #expect(kf.timestampMicros == 1_000_000)
        #expect(kf.position == CGPoint(x: 0.5, y: 0.5))
        #expect(kf.scale == 1.0)
        #expect(kf.rotation == 0.0)
        #expect(kf.opacity == 1.0)
        #expect(kf.interpolation == .easeInOut)
        #expect(kf.bezierPoints == nil)
    }

    @Test("creation with custom values")
    func creationCustom() {
        let kf = TextKeyframe(
            id: "kf2",
            timestampMicros: 2_000_000,
            position: CGPoint(x: 0.3, y: 0.7),
            scale: 1.5,
            rotation: 0.785,
            opacity: 0.8,
            interpolation: .linear
        )
        #expect(kf.scale == 1.5)
        #expect(kf.rotation == 0.785)
        #expect(kf.opacity == 0.8)
        #expect(kf.interpolation == .linear)
    }

    @Test("with() copy preserves unchanged")
    func withCopy() {
        let kf = TextKeyframe(
            id: "kf1",
            timestampMicros: 1_000_000,
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 2.0
        )
        let modified = kf.with(opacity: 0.5)
        #expect(modified.opacity == 0.5)
        #expect(modified.scale == 2.0)
        #expect(modified.id == "kf1")
    }

    @Test("with() clearBezierPoints")
    func withClearBezier() {
        let bp = BezierControlPoints()
        let kf = TextKeyframe(
            id: "kf1",
            timestampMicros: 0,
            position: .zero,
            bezierPoints: bp
        )
        #expect(kf.bezierPoints != nil)
        let cleared = kf.with(clearBezierPoints: true)
        #expect(cleared.bezierPoints == nil)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let kf = TextKeyframe(
            id: "kf-test",
            timestampMicros: 500_000,
            position: CGPoint(x: 0.25, y: 0.75),
            scale: 1.2,
            rotation: 1.57,
            opacity: 0.9,
            interpolation: .spring
        )
        let data = try JSONEncoder().encode(kf)
        let decoded = try JSONDecoder().decode(TextKeyframe.self, from: data)
        #expect(decoded.id == kf.id)
        #expect(decoded.timestampMicros == kf.timestampMicros)
        #expect(decoded.position.x == kf.position.x)
        #expect(decoded.position.y == kf.position.y)
        #expect(decoded.scale == kf.scale)
        #expect(decoded.rotation == kf.rotation)
        #expect(decoded.opacity == kf.opacity)
        #expect(decoded.interpolation == kf.interpolation)
    }
}

// MARK: - TextTemplate Tests

@Suite("TextTemplate Tests")
struct TextTemplateTests {

    private func makeTemplate() -> TextTemplate {
        TextTemplate(
            id: "tpl-1",
            name: "Bold Title",
            category: "Titles",
            style: TextOverlayStyle(fontSize: 72.0, fontWeight: .w900)
        )
    }

    @Test("creation with defaults")
    func creationDefaults() {
        let tpl = makeTemplate()
        #expect(tpl.id == "tpl-1")
        #expect(tpl.name == "Bold Title")
        #expect(tpl.category == "Titles")
        #expect(tpl.defaultPosition == CGPoint(x: 0.5, y: 0.5))
        #expect(tpl.defaultEnterAnimation == nil)
        #expect(tpl.defaultExitAnimation == nil)
        #expect(tpl.defaultSustainAnimation == nil)
        #expect(tpl.defaultDurationMicros == 3_000_000)
        #expect(tpl.defaultAlignment == .center)
        #expect(tpl.defaultMaxWidthFraction == 0.9)
        #expect(tpl.isBuiltIn == true)
        #expect(tpl.previewText == "Sample Text")
    }

    @Test("with() copy")
    func withCopy() {
        let tpl = makeTemplate()
        let modified = tpl.with(name: "New Name", category: "Subtitles")
        #expect(modified.name == "New Name")
        #expect(modified.category == "Subtitles")
        #expect(modified.id == tpl.id)
    }

    @Test("with() clear animations")
    func withClearAnimations() {
        let enter = TextAnimationPreset(type: .fadeIn)
        let tpl = TextTemplate(
            id: "tpl-2",
            name: "Animated",
            category: "Titles",
            style: TextOverlayStyle(),
            defaultEnterAnimation: enter
        )
        #expect(tpl.defaultEnterAnimation != nil)
        let cleared = tpl.with(clearEnterAnimation: true)
        #expect(cleared.defaultEnterAnimation == nil)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let tpl = TextTemplate(
            id: "tpl-codec",
            name: "Codec Test",
            category: "Social",
            style: TextOverlayStyle(fontSize: 36.0),
            defaultPosition: CGPoint(x: 0.3, y: 0.8),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInBottom),
            defaultDurationMicros: 5_000_000,
            defaultAlignment: .left,
            isBuiltIn: false,
            previewText: "Hello World"
        )
        let data = try JSONEncoder().encode(tpl)
        let decoded = try JSONDecoder().decode(TextTemplate.self, from: data)
        // TextTemplate equality is by id only
        #expect(decoded.id == tpl.id)
        #expect(decoded.name == tpl.name)
        #expect(decoded.category == tpl.category)
        #expect(decoded.defaultDurationMicros == tpl.defaultDurationMicros)
        #expect(decoded.defaultAlignment == tpl.defaultAlignment)
        #expect(decoded.previewText == tpl.previewText)
    }

    @Test("Equatable is identity-based")
    func equatableById() {
        let a = TextTemplate(id: "same-id", name: "A", category: "C1", style: TextOverlayStyle())
        let b = TextTemplate(id: "same-id", name: "B", category: "C2", style: TextOverlayStyle(fontSize: 100))
        #expect(a == b) // Same ID = equal
        let c = TextTemplate(id: "diff-id", name: "A", category: "C1", style: TextOverlayStyle())
        #expect(a != c)
    }
}

// MARK: - TextAlignValue Tests

@Suite("TextAlignValue Tests")
struct TextAlignValueTests {

    @Test("all cases")
    func allCases() {
        #expect(TextAlignValue.allCases.count == 6)
        #expect(TextAlignValue.left.rawValue == "left")
        #expect(TextAlignValue.right.rawValue == "right")
        #expect(TextAlignValue.center.rawValue == "center")
        #expect(TextAlignValue.justify.rawValue == "justify")
        #expect(TextAlignValue.start.rawValue == "start")
        #expect(TextAlignValue.end.rawValue == "end")
    }
}

// MARK: - SubtitleEntry Tests

@Suite("SubtitleEntry Tests")
struct SubtitleEntryTests {

    @Test("creation")
    func creation() {
        let entry = SubtitleEntry(
            index: 1,
            startMicros: 1_000_000,
            endMicros: 3_000_000,
            text: "Hello"
        )
        #expect(entry.index == 1)
        #expect(entry.startMicros == 1_000_000)
        #expect(entry.endMicros == 3_000_000)
        #expect(entry.text == "Hello")
        #expect(entry.speaker == nil)
        #expect(entry.styleOverride == nil)
    }

    @Test("durationMicros computed property")
    func duration() {
        let entry = SubtitleEntry(index: 1, startMicros: 1_000_000, endMicros: 3_000_000, text: "Hi")
        #expect(entry.durationMicros == 2_000_000)
    }

    @Test("isValid computed property")
    func isValid() {
        let valid = SubtitleEntry(index: 1, startMicros: 0, endMicros: 1_000_000, text: "Hi")
        #expect(valid.isValid)

        let invalidTiming = SubtitleEntry(index: 1, startMicros: 5_000_000, endMicros: 1_000_000, text: "Hi")
        #expect(!invalidTiming.isValid)

        let emptyText = SubtitleEntry(index: 1, startMicros: 0, endMicros: 1_000_000, text: "")
        #expect(!emptyText.isValid)
    }

    @Test("with() copy")
    func withCopy() {
        let entry = SubtitleEntry(
            index: 1,
            startMicros: 0,
            endMicros: 1_000_000,
            text: "Hello",
            speaker: "Alice"
        )
        let modified = entry.with(text: "Modified", clearSpeaker: true)
        #expect(modified.text == "Modified")
        #expect(modified.speaker == nil)
        #expect(modified.index == 1)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let entry = SubtitleEntry(
            index: 3,
            startMicros: 5_000_000,
            endMicros: 8_000_000,
            text: "World",
            speaker: "Bob"
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(SubtitleEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test("Equatable compares index, times, and text")
    func equatable() {
        let a = SubtitleEntry(index: 1, startMicros: 0, endMicros: 100, text: "Hi", speaker: "A")
        let b = SubtitleEntry(index: 1, startMicros: 0, endMicros: 100, text: "Hi", speaker: "B")
        // Speaker not included in ==
        #expect(a == b)
    }
}

// MARK: - TextOverlayStyle Tests

@Suite("TextOverlayStyle Tests")
struct TextOverlayStyleTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let style = TextOverlayStyle()
        #expect(style.fontFamily == ".SF Pro Display")
        #expect(style.fontSize == 48.0)
        #expect(style.color == ARGBColor.fromARGB32(0xFFFFFFFF))
        #expect(style.fontWeight == .bold)
        #expect(style.isItalic == false)
        #expect(style.letterSpacing == 0.0)
        #expect(style.lineHeight == 1.2)
        #expect(style.shadow == nil)
        #expect(style.outline == nil)
        #expect(style.background == nil)
        #expect(style.glow == nil)
        #expect(style.decoration == .none)
        #expect(style.isCustomFont == false)
        #expect(style.customFontPath == nil)
    }

    @Test("with() copy preserves unchanged")
    func withCopy() {
        let style = TextOverlayStyle(fontSize: 64.0, fontWeight: .w900)
        let modified = style.with(isItalic: true)
        #expect(modified.isItalic == true)
        #expect(modified.fontSize == 64.0)
        #expect(modified.fontWeight == .w900)
    }

    @Test("with() clear nullable fields")
    func withClearFields() {
        let shadow = TextShadowStyle()
        let outline = TextOutlineStyle()
        let style = TextOverlayStyle(shadow: shadow, outline: outline)
        #expect(style.shadow != nil)
        #expect(style.outline != nil)

        let cleared = style.with(clearShadow: true, clearOutline: true)
        #expect(cleared.shadow == nil)
        #expect(cleared.outline == nil)
    }

    @Test("Codable roundtrip without optionals")
    func codableBasic() throws {
        let style = TextOverlayStyle(fontSize: 36.0, fontWeight: .w600)
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(TextOverlayStyle.self, from: data)
        #expect(decoded == style)
    }

    @Test("Codable roundtrip with all effects")
    func codableAllEffects() throws {
        let style = TextOverlayStyle(
            fontFamily: "Helvetica",
            fontSize: 72.0,
            color: .fromARGB32(0xFFFF0000),
            fontWeight: .w800,
            isItalic: true,
            letterSpacing: 2.0,
            lineHeight: 1.5,
            shadow: TextShadowStyle(blurRadius: 8.0),
            outline: TextOutlineStyle(width: 3.0),
            background: TextBackgroundStyle(cornerRadius: 16.0),
            glow: TextGlowStyle(radius: 20.0),
            decoration: [.underline, .lineThrough],
            isCustomFont: true,
            customFontPath: "/fonts/custom.ttf"
        )
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(TextOverlayStyle.self, from: data)
        #expect(decoded == style)
    }

    @Test("Codable encodes fontWeight as integer")
    func codableFontWeightFormat() throws {
        let style = TextOverlayStyle(fontWeight: .w600)
        let data = try JSONEncoder().encode(style)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["fontWeight"] as? Int == 600)
    }
}

// MARK: - TextClip Model Tests

@Suite("TextClip Model Tests")
struct TextClipModelTests {

    private func makeClip() -> TextClip {
        TextClip(
            id: "tc-1",
            durationMicroseconds: 3_000_000,
            text: "Hello World",
            style: TextOverlayStyle(),
            name: "Test Clip"
        )
    }

    @Test("creation with defaults")
    func creationDefaults() {
        let clip = makeClip()
        #expect(clip.id == "tc-1")
        #expect(clip.durationMicroseconds == 3_000_000)
        #expect(clip.text == "Hello World")
        #expect(clip.positionX == 0.5)
        #expect(clip.positionY == 0.5)
        #expect(clip.rotation == 0.0)
        #expect(clip.scale == 1.0)
        #expect(clip.opacity == 1.0)
        #expect(clip.isSubtitle == false)
        #expect(clip.textAlign == .center)
        #expect(clip.maxWidthFraction == 0.9)
        #expect(clip.itemType == "text")
        #expect(clip.isGeneratorClip == true)
    }

    @Test("subtitle factory")
    func subtitleFactory() {
        let clip = TextClip.subtitle(
            id: "sub-1",
            durationMicroseconds: 2_000_000,
            text: "Subtitle text"
        )
        #expect(clip.isSubtitle == true)
        #expect(clip.positionY == 0.85)
        #expect(clip.enterDurationMicros == 0)
        #expect(clip.exitDurationMicros == 0)
        #expect(clip.displayName == "Subtitle")
    }

    @Test("displayName logic")
    func displayName() {
        let named = TextClip(id: "a", durationMicroseconds: 1_000_000, text: "Hi", style: TextOverlayStyle(), name: "Custom")
        #expect(named.displayName == "Custom")

        let unnamed = TextClip(id: "b", durationMicroseconds: 1_000_000, text: "Hi", style: TextOverlayStyle())
        #expect(unnamed.displayName == "Text")

        let subtitle = TextClip(id: "c", durationMicroseconds: 1_000_000, text: "Hi", style: TextOverlayStyle(), isSubtitle: true)
        #expect(subtitle.displayName == "Subtitle")
    }

    @Test("shortLabel truncation")
    func shortLabel() {
        let short = TextClip(id: "a", durationMicroseconds: 1_000_000, text: "Short text", style: TextOverlayStyle())
        #expect(short.shortLabel == "Short text")

        let long = TextClip(id: "b", durationMicroseconds: 1_000_000, text: String(repeating: "A", count: 50), style: TextOverlayStyle())
        #expect(long.shortLabel.count == 30)
        #expect(long.shortLabel.hasSuffix("..."))

        let empty = TextClip(id: "c", durationMicroseconds: 1_000_000, text: "", style: TextOverlayStyle())
        #expect(empty.shortLabel == "[Empty]")

        let multiline = TextClip(id: "d", durationMicroseconds: 1_000_000, text: "Line1\nLine2", style: TextOverlayStyle())
        #expect(multiline.shortLabel == "Line1")
    }

    @Test("splitAt valid offset")
    func splitAtValid() {
        let clip = TextClip(
            id: "tc-split",
            durationMicroseconds: 2_000_000,
            text: "Split me",
            style: TextOverlayStyle(),
            enterAnimation: TextAnimationPreset(type: .fadeIn),
            exitAnimation: TextAnimationPreset(type: .fadeOut),
            name: "Original"
        )
        let result = clip.splitAt(1_000_000)
        #expect(result != nil)
        let (left, right) = result!
        #expect(left.durationMicroseconds == 1_000_000)
        #expect(right.durationMicroseconds == 1_000_000)
        #expect(left.text == "Split me")
        #expect(right.text == "Split me")
        // Left keeps enter, no exit
        #expect(left.enterAnimation != nil)
        #expect(left.exitAnimation == nil)
        // Right keeps exit, no enter
        #expect(right.enterAnimation == nil)
        #expect(right.exitAnimation != nil)
        // Names
        #expect(left.name == "Original (1)")
        #expect(right.name == "Original (2)")
        // Different IDs
        #expect(left.id != right.id)
        #expect(left.id != clip.id)
    }

    @Test("splitAt too close to edges returns nil")
    func splitAtEdges() {
        let clip = makeClip()
        // Too close to start
        #expect(clip.splitAt(50_000) == nil)
        // Too close to end
        #expect(clip.splitAt(2_950_000) == nil)
    }

    @Test("splitAt partitions keyframes")
    func splitAtKeyframes() {
        let kf1 = TextKeyframe(id: "k1", timestampMicros: 200_000, position: CGPoint(x: 0.1, y: 0.1))
        let kf2 = TextKeyframe(id: "k2", timestampMicros: 1_500_000, position: CGPoint(x: 0.9, y: 0.9))
        let clip = TextClip(
            id: "tc-kf",
            durationMicroseconds: 2_000_000,
            text: "KF",
            style: TextOverlayStyle(),
            keyframes: [kf1, kf2]
        )
        let result = clip.splitAt(1_000_000)!
        #expect(result.left.keyframes.count == 1)
        #expect(result.left.keyframes[0].id == "k1")
        #expect(result.right.keyframes.count == 1)
        #expect(result.right.keyframes[0].id == "k2")
        // Right keyframe re-timed relative to right clip start
        #expect(result.right.keyframes[0].timestampMicros == 500_000)
    }

    @Test("duplicate creates new ID")
    func duplicate() {
        let clip = makeClip()
        let dup = clip.duplicate()
        #expect(dup.id != clip.id)
        #expect(dup.text == clip.text)
        #expect(dup.durationMicroseconds == clip.durationMicroseconds)
        #expect(dup.name == "Test Clip (copy)")
    }

    @Test("with() copy")
    func withCopy() {
        let clip = makeClip()
        let modified = clip.with(text: "Changed", opacity: 0.5)
        #expect(modified.text == "Changed")
        #expect(modified.opacity == 0.5)
        #expect(modified.id == clip.id)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let clip = TextClip(
            id: "tc-codec",
            durationMicroseconds: 5_000_000,
            text: "Codec test",
            style: TextOverlayStyle(fontSize: 36.0),
            positionX: 0.3,
            positionY: 0.7,
            rotation: 0.5,
            scale: 1.5,
            opacity: 0.8,
            enterAnimation: TextAnimationPreset(type: .slideInLeft),
            exitAnimation: TextAnimationPreset(type: .fadeOut),
            keyframes: [
                TextKeyframe(id: "k1", timestampMicros: 0, position: CGPoint(x: 0.1, y: 0.1))
            ],
            name: "Named",
            isSubtitle: false,
            textAlign: .left,
            maxWidthFraction: 0.8
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(TextClip.self, from: data)
        #expect(decoded.id == clip.id)
        #expect(decoded.durationMicroseconds == clip.durationMicroseconds)
        #expect(decoded.text == clip.text)
        #expect(decoded.positionX == clip.positionX)
        #expect(decoded.positionY == clip.positionY)
        #expect(decoded.rotation == clip.rotation)
        #expect(decoded.scale == clip.scale)
        #expect(decoded.opacity == clip.opacity)
        #expect(decoded.enterAnimation?.type == .slideInLeft)
        #expect(decoded.exitAnimation?.type == .fadeOut)
        #expect(decoded.keyframes.count == 1)
        #expect(decoded.name == "Named")
        #expect(decoded.textAlign == .left)
        #expect(decoded.maxWidthFraction == 0.8)
    }
}
