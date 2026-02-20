import Foundation
import CoreGraphics

/// Text alignment matching Flutter's TextAlign values.
enum TextAlignValue: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case center
    case justify
    case start
    case end
}

/// A preset text template combining style, position, and animation defaults.
///
/// Built-in templates are defined as static properties.
/// User-created templates are persisted as JSON in the app's documents directory.
struct TextTemplate: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this template.
    let id: String

    /// Display name shown in the template browser.
    let name: String

    /// Category for grouping in the template browser.
    /// Standard categories: "Titles", "Lower Thirds", "Social", "Cinematic", "Subtitles".
    let category: String

    /// Visual style to apply when this template is used.
    let style: TextOverlayStyle

    /// Default position (normalized 0.0-1.0) when this template is applied.
    let defaultPosition: CGPoint

    /// Default enter animation (nil = no enter animation).
    let defaultEnterAnimation: TextAnimationPreset?

    /// Default exit animation (nil = no exit animation).
    let defaultExitAnimation: TextAnimationPreset?

    /// Default sustain animation (nil = static text).
    let defaultSustainAnimation: TextAnimationPreset?

    /// Default clip duration in microseconds.
    let defaultDurationMicros: TimeMicros

    /// Default text alignment.
    let defaultAlignment: TextAlignValue

    /// Default max width fraction (0.0-1.0).
    let defaultMaxWidthFraction: Double

    /// Preview thumbnail path (bundled asset or nil for programmatic).
    let thumbnailAsset: String?

    /// Whether this is a built-in template (not deletable by user).
    let isBuiltIn: Bool

    /// Default text content for preview.
    let previewText: String

    init(
        id: String,
        name: String,
        category: String,
        style: TextOverlayStyle,
        defaultPosition: CGPoint = CGPoint(x: 0.5, y: 0.5),
        defaultEnterAnimation: TextAnimationPreset? = nil,
        defaultExitAnimation: TextAnimationPreset? = nil,
        defaultSustainAnimation: TextAnimationPreset? = nil,
        defaultDurationMicros: TimeMicros = 3_000_000,
        defaultAlignment: TextAlignValue = .center,
        defaultMaxWidthFraction: Double = 0.9,
        thumbnailAsset: String? = nil,
        isBuiltIn: Bool = true,
        previewText: String = "Sample Text"
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.style = style
        self.defaultPosition = defaultPosition
        self.defaultEnterAnimation = defaultEnterAnimation
        self.defaultExitAnimation = defaultExitAnimation
        self.defaultSustainAnimation = defaultSustainAnimation
        self.defaultDurationMicros = defaultDurationMicros
        self.defaultAlignment = defaultAlignment
        self.defaultMaxWidthFraction = defaultMaxWidthFraction
        self.thumbnailAsset = thumbnailAsset
        self.isBuiltIn = isBuiltIn
        self.previewText = previewText
    }

    /// Create a copy with optional field overrides.
    func with(
        id: String? = nil,
        name: String? = nil,
        category: String? = nil,
        style: TextOverlayStyle? = nil,
        defaultPosition: CGPoint? = nil,
        defaultEnterAnimation: TextAnimationPreset? = nil,
        defaultExitAnimation: TextAnimationPreset? = nil,
        defaultSustainAnimation: TextAnimationPreset? = nil,
        defaultDurationMicros: TimeMicros? = nil,
        defaultAlignment: TextAlignValue? = nil,
        defaultMaxWidthFraction: Double? = nil,
        thumbnailAsset: String? = nil,
        isBuiltIn: Bool? = nil,
        previewText: String? = nil,
        clearEnterAnimation: Bool = false,
        clearExitAnimation: Bool = false,
        clearSustainAnimation: Bool = false,
        clearThumbnailAsset: Bool = false
    ) -> TextTemplate {
        TextTemplate(
            id: id ?? self.id,
            name: name ?? self.name,
            category: category ?? self.category,
            style: style ?? self.style,
            defaultPosition: defaultPosition ?? self.defaultPosition,
            defaultEnterAnimation: clearEnterAnimation
                ? nil : (defaultEnterAnimation ?? self.defaultEnterAnimation),
            defaultExitAnimation: clearExitAnimation
                ? nil : (defaultExitAnimation ?? self.defaultExitAnimation),
            defaultSustainAnimation: clearSustainAnimation
                ? nil : (defaultSustainAnimation ?? self.defaultSustainAnimation),
            defaultDurationMicros: defaultDurationMicros ?? self.defaultDurationMicros,
            defaultAlignment: defaultAlignment ?? self.defaultAlignment,
            defaultMaxWidthFraction: defaultMaxWidthFraction ?? self.defaultMaxWidthFraction,
            thumbnailAsset: clearThumbnailAsset
                ? nil : (thumbnailAsset ?? self.thumbnailAsset),
            isBuiltIn: isBuiltIn ?? self.isBuiltIn,
            previewText: previewText ?? self.previewText
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, category, style, defaultPosition
        case defaultEnterAnimation, defaultExitAnimation, defaultSustainAnimation
        case defaultDurationMicros, defaultAlignment, defaultMaxWidthFraction
        case thumbnailAsset, isBuiltIn, previewText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(String.self, forKey: .category)
        style = try container.decode(TextOverlayStyle.self, forKey: .style)

        if let posDict = try container.decodeIfPresent([String: Double].self, forKey: .defaultPosition) {
            defaultPosition = CGPoint(x: posDict["x"] ?? 0.5, y: posDict["y"] ?? 0.5)
        } else {
            defaultPosition = CGPoint(x: 0.5, y: 0.5)
        }

        defaultEnterAnimation = try container.decodeIfPresent(
            TextAnimationPreset.self, forKey: .defaultEnterAnimation)
        defaultExitAnimation = try container.decodeIfPresent(
            TextAnimationPreset.self, forKey: .defaultExitAnimation)
        defaultSustainAnimation = try container.decodeIfPresent(
            TextAnimationPreset.self, forKey: .defaultSustainAnimation)
        defaultDurationMicros = try container.decodeIfPresent(
            TimeMicros.self, forKey: .defaultDurationMicros) ?? 3_000_000

        let alignName = try container.decodeIfPresent(String.self, forKey: .defaultAlignment) ?? "center"
        defaultAlignment = TextAlignValue(rawValue: alignName) ?? .center

        defaultMaxWidthFraction = try container.decodeIfPresent(
            Double.self, forKey: .defaultMaxWidthFraction) ?? 0.9
        thumbnailAsset = try container.decodeIfPresent(String.self, forKey: .thumbnailAsset)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        previewText = try container.decodeIfPresent(String.self, forKey: .previewText) ?? "Sample Text"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(style, forKey: .style)
        try container.encode(["x": defaultPosition.x, "y": defaultPosition.y], forKey: .defaultPosition)
        try container.encodeIfPresent(defaultEnterAnimation, forKey: .defaultEnterAnimation)
        try container.encodeIfPresent(defaultExitAnimation, forKey: .defaultExitAnimation)
        try container.encodeIfPresent(defaultSustainAnimation, forKey: .defaultSustainAnimation)
        try container.encode(defaultDurationMicros, forKey: .defaultDurationMicros)
        try container.encode(defaultAlignment.rawValue, forKey: .defaultAlignment)
        try container.encode(defaultMaxWidthFraction, forKey: .defaultMaxWidthFraction)
        try container.encodeIfPresent(thumbnailAsset, forKey: .thumbnailAsset)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
        try container.encode(previewText, forKey: .previewText)
    }

    // MARK: - Equatable (identity-based)

    static func == (lhs: TextTemplate, rhs: TextTemplate) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
