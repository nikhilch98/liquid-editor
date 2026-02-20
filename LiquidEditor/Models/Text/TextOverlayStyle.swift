import Foundation
import CoreGraphics

// MARK: - TextShadowStyle

/// Shadow effect applied to text.
struct TextShadowStyle: Codable, Equatable, Hashable, Sendable {
    /// Shadow color as ARGB.
    let color: ARGBColor

    /// Shadow offset X normalized to font size units.
    let offsetX: CGFloat

    /// Shadow offset Y normalized to font size units.
    let offsetY: CGFloat

    /// Blur radius in logical pixels.
    let blurRadius: Double

    init(
        color: ARGBColor = .fromARGB32(0x80000000),
        offsetX: CGFloat = 0.02,
        offsetY: CGFloat = 0.02,
        blurRadius: Double = 4.0
    ) {
        self.color = color
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.blurRadius = blurRadius
    }

    func with(
        color: ARGBColor? = nil,
        offsetX: CGFloat? = nil,
        offsetY: CGFloat? = nil,
        blurRadius: Double? = nil
    ) -> TextShadowStyle {
        TextShadowStyle(
            color: color ?? self.color,
            offsetX: offsetX ?? self.offsetX,
            offsetY: offsetY ?? self.offsetY,
            blurRadius: blurRadius ?? self.blurRadius
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case color, offsetX, offsetY, blurRadius
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let colorInt = try container.decodeIfPresent(Int.self, forKey: .color) ?? 0x80000000
        color = .fromARGB32(colorInt)
        offsetX = try container.decodeIfPresent(CGFloat.self, forKey: .offsetX) ?? 0.02
        offsetY = try container.decodeIfPresent(CGFloat.self, forKey: .offsetY) ?? 0.02
        blurRadius = try container.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 4.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color.toARGB32, forKey: .color)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
        try container.encode(blurRadius, forKey: .blurRadius)
    }
}

// MARK: - TextOutlineStyle

/// Outline/stroke effect applied to text.
struct TextOutlineStyle: Codable, Equatable, Hashable, Sendable {
    /// Outline color as ARGB.
    let color: ARGBColor

    /// Stroke width in logical pixels.
    let width: Double

    init(
        color: ARGBColor = .fromARGB32(0xFF000000),
        width: Double = 2.0
    ) {
        self.color = color
        self.width = width
    }

    func with(
        color: ARGBColor? = nil,
        width: Double? = nil
    ) -> TextOutlineStyle {
        TextOutlineStyle(
            color: color ?? self.color,
            width: width ?? self.width
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case color, width
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let colorInt = try container.decodeIfPresent(Int.self, forKey: .color) ?? 0xFF000000
        color = .fromARGB32(colorInt)
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 2.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color.toARGB32, forKey: .color)
        try container.encode(width, forKey: .width)
    }
}

// MARK: - TextBackgroundStyle

/// Background box rendered behind text.
struct TextBackgroundStyle: Codable, Equatable, Hashable, Sendable {
    /// Background color as ARGB.
    let color: ARGBColor

    /// Corner radius of the background box.
    let cornerRadius: Double

    /// Horizontal padding around the text content in logical pixels.
    let paddingHorizontal: Double

    /// Vertical padding around the text content in logical pixels.
    let paddingVertical: Double

    init(
        color: ARGBColor = .fromARGB32(0x80000000),
        cornerRadius: Double = 8.0,
        paddingHorizontal: Double = 12.0,
        paddingVertical: Double = 6.0
    ) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.paddingHorizontal = paddingHorizontal
        self.paddingVertical = paddingVertical
    }

    func with(
        color: ARGBColor? = nil,
        cornerRadius: Double? = nil,
        paddingHorizontal: Double? = nil,
        paddingVertical: Double? = nil
    ) -> TextBackgroundStyle {
        TextBackgroundStyle(
            color: color ?? self.color,
            cornerRadius: cornerRadius ?? self.cornerRadius,
            paddingHorizontal: paddingHorizontal ?? self.paddingHorizontal,
            paddingVertical: paddingVertical ?? self.paddingVertical
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case color, cornerRadius, paddingHorizontal, paddingVertical
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let colorInt = try container.decodeIfPresent(Int.self, forKey: .color) ?? 0x80000000
        color = .fromARGB32(colorInt)
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 8.0
        paddingHorizontal = try container.decodeIfPresent(Double.self, forKey: .paddingHorizontal) ?? 12.0
        paddingVertical = try container.decodeIfPresent(Double.self, forKey: .paddingVertical) ?? 6.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color.toARGB32, forKey: .color)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(paddingHorizontal, forKey: .paddingHorizontal)
        try container.encode(paddingVertical, forKey: .paddingVertical)
    }
}

// MARK: - TextGlowStyle

/// Glow effect around text.
struct TextGlowStyle: Codable, Equatable, Hashable, Sendable {
    /// Glow color as ARGB.
    let color: ARGBColor

    /// Glow blur radius in logical pixels.
    let radius: Double

    /// Glow intensity (0.0-1.0).
    let intensity: Double

    init(
        color: ARGBColor = .fromARGB32(0xFF007AFF),
        radius: Double = 10.0,
        intensity: Double = 0.5
    ) {
        self.color = color
        self.radius = radius
        self.intensity = intensity
    }

    func with(
        color: ARGBColor? = nil,
        radius: Double? = nil,
        intensity: Double? = nil
    ) -> TextGlowStyle {
        TextGlowStyle(
            color: color ?? self.color,
            radius: radius ?? self.radius,
            intensity: intensity ?? self.intensity
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case color, radius, intensity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let colorInt = try container.decodeIfPresent(Int.self, forKey: .color) ?? 0xFF007AFF
        color = .fromARGB32(colorInt)
        radius = try container.decodeIfPresent(Double.self, forKey: .radius) ?? 10.0
        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.5
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color.toARGB32, forKey: .color)
        try container.encode(radius, forKey: .radius)
        try container.encode(intensity, forKey: .intensity)
    }
}

// MARK: - TextDecorationType

/// Text decoration flags matching Flutter's TextDecoration.
struct TextDecorationType: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let none = TextDecorationType([])
    static let underline = TextDecorationType(rawValue: 1 << 0)
    static let overline = TextDecorationType(rawValue: 1 << 1)
    static let lineThrough = TextDecorationType(rawValue: 1 << 2)

    /// Decode from a list of string flags (matching Dart format).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let flags = try container.decode([String].self)
        var value = 0
        if flags.contains("underline") { value |= Self.underline.rawValue }
        if flags.contains("overline") { value |= Self.overline.rawValue }
        if flags.contains("lineThrough") { value |= Self.lineThrough.rawValue }
        self.rawValue = value
    }

    /// Encode as a list of string flags (matching Dart format).
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var flags: [String] = []
        if contains(.underline) { flags.append("underline") }
        if contains(.overline) { flags.append("overline") }
        if contains(.lineThrough) { flags.append("lineThrough") }
        try container.encode(flags)
    }
}

// MARK: - FontWeightValue

/// Font weight numeric value (100-900) matching Flutter's FontWeight.
enum FontWeightValue: Int, Codable, CaseIterable, Sendable {
    case w100 = 100
    case w200 = 200
    case w300 = 300
    case w400 = 400
    case w500 = 500
    case w600 = 600
    case w700 = 700
    case w800 = 800
    case w900 = 900

    static let thin = w100
    static let extraLight = w200
    static let light = w300
    static let regular = w400
    static let medium = w500
    static let semiBold = w600
    static let bold = w700
    static let extraBold = w800
    static let black = w900
}

// MARK: - TextOverlayStyle

/// Complete visual style for a text overlay.
///
/// Contains font, color, and effect properties.
/// All values are designed for 1080p reference resolution and
/// scale proportionally for other resolutions.
struct TextOverlayStyle: Codable, Equatable, Hashable, Sendable {
    /// Font family name (system or custom).
    let fontFamily: String

    /// Font size in logical pixels at 1080p reference.
    let fontSize: Double

    /// Text color as ARGB.
    let color: ARGBColor

    /// Font weight (100-900 numeric value).
    let fontWeight: FontWeightValue

    /// Whether text is italic.
    let isItalic: Bool

    /// Letter spacing (0.0 = normal).
    let letterSpacing: Double

    /// Line height multiplier (1.0 = normal).
    let lineHeight: Double

    /// Text shadow (nil = no shadow).
    let shadow: TextShadowStyle?

    /// Text outline/stroke (nil = no outline).
    let outline: TextOutlineStyle?

    /// Background box behind text (nil = no background).
    let background: TextBackgroundStyle?

    /// Glow effect around text (nil = no glow).
    let glow: TextGlowStyle?

    /// Text decoration (underline, strikethrough, etc.).
    let decoration: TextDecorationType

    /// Whether the font is a custom imported font.
    let isCustomFont: Bool

    /// Custom font file path (only if isCustomFont is true).
    let customFontPath: String?

    init(
        fontFamily: String = ".SF Pro Display",
        fontSize: Double = 48.0,
        color: ARGBColor = .fromARGB32(0xFFFFFFFF),
        fontWeight: FontWeightValue = .bold,
        isItalic: Bool = false,
        letterSpacing: Double = 0.0,
        lineHeight: Double = 1.2,
        shadow: TextShadowStyle? = nil,
        outline: TextOutlineStyle? = nil,
        background: TextBackgroundStyle? = nil,
        glow: TextGlowStyle? = nil,
        decoration: TextDecorationType = .none,
        isCustomFont: Bool = false,
        customFontPath: String? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.color = color
        self.fontWeight = fontWeight
        self.isItalic = isItalic
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.shadow = shadow
        self.outline = outline
        self.background = background
        self.glow = glow
        self.decoration = decoration
        self.isCustomFont = isCustomFont
        self.customFontPath = customFontPath
    }

    /// Create a copy with optional field overrides.
    func with(
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        color: ARGBColor? = nil,
        fontWeight: FontWeightValue? = nil,
        isItalic: Bool? = nil,
        letterSpacing: Double? = nil,
        lineHeight: Double? = nil,
        shadow: TextShadowStyle? = nil,
        outline: TextOutlineStyle? = nil,
        background: TextBackgroundStyle? = nil,
        glow: TextGlowStyle? = nil,
        decoration: TextDecorationType? = nil,
        isCustomFont: Bool? = nil,
        customFontPath: String? = nil,
        clearShadow: Bool = false,
        clearOutline: Bool = false,
        clearBackground: Bool = false,
        clearGlow: Bool = false,
        clearCustomFontPath: Bool = false
    ) -> TextOverlayStyle {
        TextOverlayStyle(
            fontFamily: fontFamily ?? self.fontFamily,
            fontSize: fontSize ?? self.fontSize,
            color: color ?? self.color,
            fontWeight: fontWeight ?? self.fontWeight,
            isItalic: isItalic ?? self.isItalic,
            letterSpacing: letterSpacing ?? self.letterSpacing,
            lineHeight: lineHeight ?? self.lineHeight,
            shadow: clearShadow ? nil : (shadow ?? self.shadow),
            outline: clearOutline ? nil : (outline ?? self.outline),
            background: clearBackground ? nil : (background ?? self.background),
            glow: clearGlow ? nil : (glow ?? self.glow),
            decoration: decoration ?? self.decoration,
            isCustomFont: isCustomFont ?? self.isCustomFont,
            customFontPath: clearCustomFontPath ? nil : (customFontPath ?? self.customFontPath)
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case fontFamily, fontSize, color, fontWeight, isItalic
        case letterSpacing, lineHeight
        case shadow, outline, background, glow
        case decoration, isCustomFont, customFontPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? ".SF Pro Display"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 48.0

        let colorInt = try container.decodeIfPresent(Int.self, forKey: .color) ?? 0xFFFFFFFF
        color = .fromARGB32(colorInt)

        let weightValue = try container.decodeIfPresent(Int.self, forKey: .fontWeight) ?? 700
        fontWeight = FontWeightValue(rawValue: weightValue) ?? .bold

        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        letterSpacing = try container.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? 0.0
        lineHeight = try container.decodeIfPresent(Double.self, forKey: .lineHeight) ?? 1.2
        shadow = try container.decodeIfPresent(TextShadowStyle.self, forKey: .shadow)
        outline = try container.decodeIfPresent(TextOutlineStyle.self, forKey: .outline)
        background = try container.decodeIfPresent(TextBackgroundStyle.self, forKey: .background)
        glow = try container.decodeIfPresent(TextGlowStyle.self, forKey: .glow)
        decoration = try container.decodeIfPresent(TextDecorationType.self, forKey: .decoration) ?? .none
        isCustomFont = try container.decodeIfPresent(Bool.self, forKey: .isCustomFont) ?? false
        customFontPath = try container.decodeIfPresent(String.self, forKey: .customFontPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(color.toARGB32, forKey: .color)
        try container.encode(fontWeight.rawValue, forKey: .fontWeight)
        try container.encode(isItalic, forKey: .isItalic)
        try container.encode(letterSpacing, forKey: .letterSpacing)
        try container.encode(lineHeight, forKey: .lineHeight)
        try container.encodeIfPresent(shadow, forKey: .shadow)
        try container.encodeIfPresent(outline, forKey: .outline)
        try container.encodeIfPresent(background, forKey: .background)
        try container.encodeIfPresent(glow, forKey: .glow)
        try container.encode(decoration, forKey: .decoration)
        try container.encode(isCustomFont, forKey: .isCustomFont)
        try container.encodeIfPresent(customFontPath, forKey: .customFontPath)
    }
}
