// TextClip.swift
// LiquidEditor
//
// Text clip - styled text overlay displayed for a duration.
//
// Text clips are generator clips (no external media reference) that
// render text content with configurable style, position, and animation.
//

import Foundation
import CoreGraphics

// MARK: - Text Alignment

/// Text alignment within the bounding box.
/// Matches Dart's TextAlign enum values.
enum TextClipAlignment: String, Codable, Sendable {
    case left
    case right
    case center
    case justify
    case start
    case end
}

// MARK: - TextClip

/// A text overlay clip on the timeline.
///
/// Renders styled text for the specified duration.
/// Supports positioning, rotation, scaling, opacity, animations,
/// and keyframe-based custom animation.
struct TextClip: TimelineItemProtocol, Codable, Equatable, Hashable, Sendable {

    // MARK: - Constants

    /// Minimum duration for each resulting clip after split (100ms).
    static let minSplitDuration: Int64 = 100_000

    // MARK: - Properties

    /// Unique identifier for this clip.
    let id: String

    /// Duration in microseconds.
    let durationMicroseconds: Int64

    /// The text content (supports multi-line via \n).
    let text: String

    /// Visual style of the text.
    let style: TextOverlayStyle

    /// Position X of the text center on the video canvas (normalized 0.0-1.0).
    let positionX: Double

    /// Position Y component (normalized 0.0-1.0).
    let positionY: Double

    /// Rotation angle in radians.
    let rotation: Double

    /// Scale factor (1.0 = default size as defined by style.fontSize).
    let scale: Double

    /// Opacity (0.0-1.0).
    let opacity: Double

    /// Enter animation preset (nil = no enter animation).
    let enterAnimation: TextAnimationPreset?

    /// Exit animation preset (nil = no exit animation).
    let exitAnimation: TextAnimationPreset?

    /// Sustain animation preset (nil = static text).
    let sustainAnimation: TextAnimationPreset?

    /// Duration of enter animation in microseconds.
    /// Clamped to [0, durationMicroseconds / 2].
    let enterDurationMicros: Int64

    /// Duration of exit animation in microseconds.
    /// Clamped to [0, durationMicroseconds / 2].
    let exitDurationMicros: Int64

    /// Keyframes for custom property animation.
    /// Timestamps are relative to clip start.
    let keyframes: [TextKeyframe]

    /// Template ID this was created from (nil if custom).
    let templateId: String?

    /// Optional display name.
    let name: String?

    /// Whether this is a subtitle clip (affects rendering layer and behavior).
    let isSubtitle: Bool

    /// Text alignment within the bounding box.
    let textAlign: TextClipAlignment

    /// Maximum width as fraction of video width (0.0-1.0).
    /// Text wraps when it exceeds this width. Default 0.9.
    let maxWidthFraction: Double

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        durationMicroseconds: Int64,
        text: String,
        style: TextOverlayStyle,
        positionX: Double = 0.5,
        positionY: Double = 0.5,
        rotation: Double = 0.0,
        scale: Double = 1.0,
        opacity: Double = 1.0,
        enterAnimation: TextAnimationPreset? = nil,
        exitAnimation: TextAnimationPreset? = nil,
        sustainAnimation: TextAnimationPreset? = nil,
        enterDurationMicros: Int64 = 300_000,
        exitDurationMicros: Int64 = 300_000,
        keyframes: [TextKeyframe] = [],
        templateId: String? = nil,
        name: String? = nil,
        isSubtitle: Bool = false,
        textAlign: TextClipAlignment = .center,
        maxWidthFraction: Double = 0.9
    ) {
        // Validate style parameters.
        precondition(style.fontSize > 0, "TextClip style.fontSize must be > 0, got \(style.fontSize)")
        precondition(!style.fontFamily.isEmpty, "TextClip style.fontFamily must not be empty")

        // Validate other parameters
        precondition(durationMicroseconds > 0, "Duration must be positive")
        precondition((0.0...1.0).contains(positionX), "positionX must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(positionY), "positionY must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(opacity), "opacity must be in range 0.0-1.0")
        precondition(scale > 0, "scale must be positive")
        precondition(enterDurationMicros >= 0, "enterDurationMicros must be non-negative")
        precondition(exitDurationMicros >= 0, "exitDurationMicros must be non-negative")
        precondition((0.0...1.0).contains(maxWidthFraction), "maxWidthFraction must be in range 0.0-1.0")

        self.id = id
        self.durationMicroseconds = durationMicroseconds
        self.text = text
        self.style = style
        self.positionX = positionX
        self.positionY = positionY
        self.rotation = rotation
        self.scale = scale
        self.opacity = opacity
        self.enterAnimation = enterAnimation
        self.exitAnimation = exitAnimation
        self.sustainAnimation = sustainAnimation
        self.enterDurationMicros = enterDurationMicros
        self.exitDurationMicros = exitDurationMicros
        self.keyframes = keyframes
        self.templateId = templateId
        self.name = name
        self.isSubtitle = isSubtitle
        self.textAlign = textAlign
        self.maxWidthFraction = maxWidthFraction
    }

    // MARK: - Computed Properties

    /// Human-readable display name.
    var displayName: String {
        name ?? (isSubtitle ? "Subtitle" : "Text")
    }

    /// Item type identifier for serialization.
    var itemType: String { "text" }

    /// Whether this item generates content (no external media).
    var isGeneratorClip: Bool { true }

    /// Whether this clip has any keyframes.
    var hasKeyframes: Bool { !keyframes.isEmpty }

    /// Number of keyframes.
    var keyframeCount: Int { keyframes.count }

    /// Get keyframes sorted by timestamp.
    var sortedKeyframes: [TextKeyframe] {
        keyframes.sorted { $0.timestampMicros < $1.timestampMicros }
    }

    /// A truncated label suitable for timeline UI display.
    /// Returns the first line of text, truncated to 30 characters.
    var shortLabel: String {
        if text.isEmpty { return "[Empty]" }
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        if firstLine.count <= 30 { return firstLine }
        return String(firstLine.prefix(27)) + "..."
    }

    /// Position as CGPoint.
    var position: CGPoint {
        CGPoint(x: positionX, y: positionY)
    }

    // MARK: - Factory Constructors

    /// Create a subtitle text clip with subtitle-appropriate defaults.
    static func subtitle(
        id: String = UUID().uuidString,
        durationMicroseconds: Int64,
        text: String,
        style: TextOverlayStyle? = nil
    ) -> TextClip {
        TextClip(
            id: id,
            durationMicroseconds: durationMicroseconds,
            text: text,
            style: style ?? TextOverlayStyle(
                fontSize: 32.0,
                fontWeight: .w600,
                outline: TextOutlineStyle(color: .fromARGB32(0xFF000000), width: 1.5)
            ),
            positionX: 0.5,
            positionY: 0.85, // Bottom center
            enterDurationMicros: 0,
            exitDurationMicros: 0,
            isSubtitle: true
        )
    }

    // MARK: - Copy-With-Modify

    /// Create a copy with optional field overrides.
    ///
    /// To explicitly clear nullable fields to nil, pass the corresponding
    /// `clearFieldName: true` parameter.
    func with(
        id: String? = nil,
        durationMicroseconds: Int64? = nil,
        text: String? = nil,
        style: TextOverlayStyle? = nil,
        positionX: Double? = nil,
        positionY: Double? = nil,
        rotation: Double? = nil,
        scale: Double? = nil,
        opacity: Double? = nil,
        enterAnimation: TextAnimationPreset? = nil,
        exitAnimation: TextAnimationPreset? = nil,
        sustainAnimation: TextAnimationPreset? = nil,
        enterDurationMicros: Int64? = nil,
        exitDurationMicros: Int64? = nil,
        keyframes: [TextKeyframe]? = nil,
        templateId: String? = nil,
        name: String? = nil,
        isSubtitle: Bool? = nil,
        textAlign: TextClipAlignment? = nil,
        maxWidthFraction: Double? = nil,
        clearEnterAnimation: Bool = false,
        clearExitAnimation: Bool = false,
        clearSustainAnimation: Bool = false,
        clearTemplateId: Bool = false,
        clearName: Bool = false
    ) -> TextClip {
        let newDuration = durationMicroseconds ?? self.durationMicroseconds
        let newPositionX = positionX ?? self.positionX
        let newPositionY = positionY ?? self.positionY
        let newOpacity = opacity ?? self.opacity
        let newScale = scale ?? self.scale
        let newEnterDuration = enterDurationMicros ?? self.enterDurationMicros
        let newExitDuration = exitDurationMicros ?? self.exitDurationMicros
        let newMaxWidthFraction = maxWidthFraction ?? self.maxWidthFraction

        precondition(newDuration > 0, "Duration must be positive")
        precondition((0.0...1.0).contains(newPositionX), "positionX must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(newPositionY), "positionY must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(newOpacity), "opacity must be in range 0.0-1.0")
        precondition(newScale > 0, "scale must be positive")
        precondition(newEnterDuration >= 0, "enterDurationMicros must be non-negative")
        precondition(newExitDuration >= 0, "exitDurationMicros must be non-negative")
        precondition((0.0...1.0).contains(newMaxWidthFraction), "maxWidthFraction must be in range 0.0-1.0")

        return TextClip(
            id: id ?? self.id,
            durationMicroseconds: newDuration,
            text: text ?? self.text,
            style: style ?? self.style,
            positionX: newPositionX,
            positionY: newPositionY,
            rotation: rotation ?? self.rotation,
            scale: newScale,
            opacity: newOpacity,
            enterAnimation: clearEnterAnimation ? nil : (enterAnimation ?? self.enterAnimation),
            exitAnimation: clearExitAnimation ? nil : (exitAnimation ?? self.exitAnimation),
            sustainAnimation: clearSustainAnimation ? nil : (sustainAnimation ?? self.sustainAnimation),
            enterDurationMicros: newEnterDuration,
            exitDurationMicros: newExitDuration,
            keyframes: keyframes ?? self.keyframes,
            templateId: clearTemplateId ? nil : (templateId ?? self.templateId),
            name: clearName ? nil : (name ?? self.name),
            isSubtitle: isSubtitle ?? self.isSubtitle,
            textAlign: textAlign ?? self.textAlign,
            maxWidthFraction: newMaxWidthFraction
        )
    }

    // MARK: - Split Operation

    /// Split clip at offset (relative to clip start).
    ///
    /// Returns (left, right) tuple or nil if offset is invalid.
    /// - Left clip retains enter animation; no exit animation.
    /// - Right clip retains exit animation; no enter animation.
    /// - Keyframes are partitioned and re-timed relative to each clip.
    /// - Both halves share the same text content and style.
    func splitAt(_ offsetMicros: Int64) -> (left: TextClip, right: TextClip)? {
        guard offsetMicros >= Self.minSplitDuration,
              offsetMicros <= durationMicroseconds - Self.minSplitDuration else {
            return nil
        }

        // Partition keyframes
        let leftKeyframes = keyframes
            .filter { $0.timestampMicros < offsetMicros }

        let rightKeyframes = keyframes
            .filter { $0.timestampMicros >= offsetMicros }
            .map { $0.with(timestampMicros: $0.timestampMicros - offsetMicros) }

        let leftDuration = offsetMicros
        let rightDuration = durationMicroseconds - offsetMicros

        let left = TextClip(
            id: UUID().uuidString,
            durationMicroseconds: leftDuration,
            text: text,
            style: style,
            positionX: positionX,
            positionY: positionY,
            rotation: rotation,
            scale: scale,
            opacity: opacity,
            enterAnimation: enterAnimation,
            exitAnimation: nil, // No exit on left half
            sustainAnimation: sustainAnimation,
            enterDurationMicros: min(enterDurationMicros, leftDuration / 2),
            exitDurationMicros: 0,
            keyframes: leftKeyframes,
            templateId: templateId,
            name: name.map { "\($0) (1)" },
            isSubtitle: isSubtitle,
            textAlign: textAlign,
            maxWidthFraction: maxWidthFraction
        )

        let right = TextClip(
            id: UUID().uuidString,
            durationMicroseconds: rightDuration,
            text: text,
            style: style,
            positionX: positionX,
            positionY: positionY,
            rotation: rotation,
            scale: scale,
            opacity: opacity,
            enterAnimation: nil, // No enter on right half
            exitAnimation: exitAnimation,
            sustainAnimation: sustainAnimation,
            enterDurationMicros: 0,
            exitDurationMicros: min(exitDurationMicros, rightDuration / 2),
            keyframes: rightKeyframes,
            templateId: templateId,
            name: name.map { "\($0) (2)" },
            isSubtitle: isSubtitle,
            textAlign: textAlign,
            maxWidthFraction: maxWidthFraction
        )

        return (left: left, right: right)
    }

    // MARK: - Duplication

    /// Create a duplicate with new ID.
    func duplicate() -> TextClip {
        TextClip(
            id: UUID().uuidString,
            durationMicroseconds: durationMicroseconds,
            text: text,
            style: style,
            positionX: positionX,
            positionY: positionY,
            rotation: rotation,
            scale: scale,
            opacity: opacity,
            enterAnimation: enterAnimation,
            exitAnimation: exitAnimation,
            sustainAnimation: sustainAnimation,
            enterDurationMicros: enterDurationMicros,
            exitDurationMicros: exitDurationMicros,
            keyframes: keyframes,
            templateId: templateId,
            name: name.map { "\($0) (copy)" },
            isSubtitle: isSubtitle,
            textAlign: textAlign,
            maxWidthFraction: maxWidthFraction
        )
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case durationMicros
        case text
        case style
        case position
        case rotation
        case scale
        case opacity
        case enterAnimation
        case exitAnimation
        case sustainAnimation
        case enterDurationMicros
        case exitDurationMicros
        case keyframes
        case templateId
        case name
        case isSubtitle
        case textAlign
        case maxWidthFraction
        case itemType
    }

    /// Position JSON wrapper for encoding/decoding.
    private struct PositionJSON: Codable {
        let x: Double
        let y: Double
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(id, forKey: .id)
        try container.encode(durationMicroseconds, forKey: .durationMicros)
        try container.encode(text, forKey: .text)
        try container.encode(style, forKey: .style)
        try container.encode(PositionJSON(x: positionX, y: positionY), forKey: .position)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(scale, forKey: .scale)
        try container.encode(opacity, forKey: .opacity)
        try container.encodeIfPresent(enterAnimation, forKey: .enterAnimation)
        try container.encodeIfPresent(exitAnimation, forKey: .exitAnimation)
        try container.encodeIfPresent(sustainAnimation, forKey: .sustainAnimation)
        try container.encode(enterDurationMicros, forKey: .enterDurationMicros)
        try container.encode(exitDurationMicros, forKey: .exitDurationMicros)
        try container.encode(keyframes, forKey: .keyframes)
        try container.encodeIfPresent(templateId, forKey: .templateId)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(isSubtitle, forKey: .isSubtitle)
        try container.encode(textAlign.rawValue, forKey: .textAlign)
        try container.encode(maxWidthFraction, forKey: .maxWidthFraction)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        durationMicroseconds = try container.decode(Int64.self, forKey: .durationMicros)
        text = try container.decode(String.self, forKey: .text)
        style = try container.decode(TextOverlayStyle.self, forKey: .style)
        let positionJSON = try container.decodeIfPresent(PositionJSON.self, forKey: .position)
        positionX = positionJSON?.x ?? 0.5
        positionY = positionJSON?.y ?? 0.5
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        enterAnimation = try container.decodeIfPresent(TextAnimationPreset.self, forKey: .enterAnimation)
        exitAnimation = try container.decodeIfPresent(TextAnimationPreset.self, forKey: .exitAnimation)
        sustainAnimation = try container.decodeIfPresent(TextAnimationPreset.self, forKey: .sustainAnimation)
        enterDurationMicros = try container.decodeIfPresent(Int64.self, forKey: .enterDurationMicros) ?? 300_000
        exitDurationMicros = try container.decodeIfPresent(Int64.self, forKey: .exitDurationMicros) ?? 300_000
        keyframes = try container.decodeIfPresent([TextKeyframe].self, forKey: .keyframes) ?? []
        templateId = try container.decodeIfPresent(String.self, forKey: .templateId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isSubtitle = try container.decodeIfPresent(Bool.self, forKey: .isSubtitle) ?? false
        let textAlignRaw = try container.decodeIfPresent(String.self, forKey: .textAlign) ?? "center"
        textAlign = TextClipAlignment(rawValue: textAlignRaw) ?? .center
        maxWidthFraction = try container.decodeIfPresent(Double.self, forKey: .maxWidthFraction) ?? 0.9
    }

    // MARK: - CustomStringConvertible

    var description: String {
        let truncatedText = text.count > 20 ? String(text.prefix(17)) + "..." : text
        let durationMs = durationMicroseconds / 1000
        return "TextClip(\(id), \"\(truncatedText)\", \(durationMs)ms)"
    }
}
