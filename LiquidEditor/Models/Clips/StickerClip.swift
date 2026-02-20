// StickerClip.swift
// LiquidEditor
//
// Sticker clip - visual sticker overlay displayed for a duration.
//
// Sticker clips are generator clips (no external media reference) that
// render a sticker image with configurable position, rotation, scale,
// opacity, flip, tint, and animation properties.
//

import Foundation
import CoreGraphics

// MARK: - StickerClip

/// A sticker overlay clip on the timeline.
///
/// Renders a sticker image for the specified duration.
/// Supports positioning, rotation, scaling, opacity, flip,
/// tint color, animated playback, and keyframe-based custom animation.
struct StickerClip: TimelineItemProtocol, Codable, Equatable, Hashable, Sendable {

    // MARK: - Constants

    /// Minimum duration for each resulting clip after split (100ms).
    static let minSplitDuration: Int64 = 100_000

    // MARK: - Properties

    /// Unique identifier for this clip.
    let id: String

    /// Duration in microseconds.
    let durationMicroseconds: Int64

    /// Reference to the sticker asset (by asset ID).
    /// Identifies which sticker image/animation to render.
    let stickerAssetId: String

    /// Position X of the sticker center on the video canvas (normalized 0.0-1.0).
    let positionX: Double

    /// Position Y of the sticker center on the video canvas (normalized 0.0-1.0).
    let positionY: Double

    /// Rotation angle in radians.
    let rotation: Double

    /// Scale factor (1.0 = default sticker size).
    let scale: Double

    /// Opacity (0.0-1.0).
    let opacity: Double

    /// Whether the sticker is horizontally flipped.
    let isFlippedHorizontally: Bool

    /// Whether the sticker is vertically flipped.
    let isFlippedVertically: Bool

    /// Keyframes for custom property animation.
    /// Timestamps are relative to clip start.
    let keyframes: [StickerKeyframe]

    /// Optional display name override.
    let name: String?

    /// Tint color applied as a color multiply on the sticker (ARGB int).
    /// Nil means no tint (render as-is).
    let tintColorValue: UInt32?

    /// For animated stickers (Lottie/GIF): playback speed multiplier.
    /// 1.0 = normal speed, 0.5 = half speed, 2.0 = double speed.
    /// Ignored for static stickers.
    let animationSpeed: Double

    /// For animated stickers: whether animation loops.
    /// If false, the animation plays once and holds the last frame.
    let animationLoops: Bool

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        durationMicroseconds: Int64,
        stickerAssetId: String,
        positionX: Double = 0.5,
        positionY: Double = 0.5,
        rotation: Double = 0.0,
        scale: Double = 1.0,
        opacity: Double = 1.0,
        isFlippedHorizontally: Bool = false,
        isFlippedVertically: Bool = false,
        keyframes: [StickerKeyframe] = [],
        name: String? = nil,
        tintColorValue: UInt32? = nil,
        animationSpeed: Double = 1.0,
        animationLoops: Bool = true
    ) {
        precondition(durationMicroseconds > 0, "Duration must be positive")
        precondition((0.0...1.0).contains(positionX), "positionX must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(positionY), "positionY must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(opacity), "opacity must be in range 0.0-1.0")
        precondition(scale > 0, "scale must be positive")
        precondition(animationSpeed > 0, "animationSpeed must be positive")

        self.id = id
        self.durationMicroseconds = durationMicroseconds
        self.stickerAssetId = stickerAssetId
        self.positionX = positionX
        self.positionY = positionY
        self.rotation = rotation
        self.scale = scale
        self.opacity = opacity
        self.isFlippedHorizontally = isFlippedHorizontally
        self.isFlippedVertically = isFlippedVertically
        self.keyframes = keyframes
        self.name = name
        self.tintColorValue = tintColorValue
        self.animationSpeed = animationSpeed
        self.animationLoops = animationLoops
    }

    // MARK: - Computed Properties

    /// Human-readable display name.
    var displayName: String {
        name ?? "Sticker"
    }

    /// Item type identifier for serialization.
    var itemType: String { "sticker" }

    /// Whether this item generates content (no external media).
    var isGeneratorClip: Bool { true }

    /// Whether this clip has any keyframes.
    var hasKeyframes: Bool { !keyframes.isEmpty }

    /// Number of keyframes.
    var keyframeCount: Int { keyframes.count }

    /// Get keyframes sorted by timestamp.
    var sortedKeyframes: [StickerKeyframe] {
        keyframes.sorted { $0.timestampMicros < $1.timestampMicros }
    }

    /// A truncated label suitable for timeline UI display.
    /// Returns the display name, truncated to 30 characters.
    var shortLabel: String {
        let label = displayName
        if label.count <= 30 { return label }
        return String(label.prefix(27)) + "..."
    }

    /// Position as CGPoint.
    var position: CGPoint {
        CGPoint(x: positionX, y: positionY)
    }

    // MARK: - Copy-With-Modify

    /// Create a copy with optional field overrides.
    ///
    /// To explicitly clear nullable fields to nil, pass the corresponding
    /// `clearFieldName: true` parameter.
    func with(
        id: String? = nil,
        durationMicroseconds: Int64? = nil,
        stickerAssetId: String? = nil,
        positionX: Double? = nil,
        positionY: Double? = nil,
        rotation: Double? = nil,
        scale: Double? = nil,
        opacity: Double? = nil,
        isFlippedHorizontally: Bool? = nil,
        isFlippedVertically: Bool? = nil,
        keyframes: [StickerKeyframe]? = nil,
        name: String? = nil,
        tintColorValue: UInt32? = nil,
        animationSpeed: Double? = nil,
        animationLoops: Bool? = nil,
        clearName: Bool = false,
        clearTintColorValue: Bool = false
    ) -> StickerClip {
        let newDuration = durationMicroseconds ?? self.durationMicroseconds
        let newPositionX = positionX ?? self.positionX
        let newPositionY = positionY ?? self.positionY
        let newOpacity = opacity ?? self.opacity
        let newScale = scale ?? self.scale
        let newAnimationSpeed = animationSpeed ?? self.animationSpeed

        precondition(newDuration > 0, "Duration must be positive")
        precondition((0.0...1.0).contains(newPositionX), "positionX must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(newPositionY), "positionY must be in range 0.0-1.0")
        precondition((0.0...1.0).contains(newOpacity), "opacity must be in range 0.0-1.0")
        precondition(newScale > 0, "scale must be positive")
        precondition(newAnimationSpeed > 0, "animationSpeed must be positive")

        return StickerClip(
            id: id ?? self.id,
            durationMicroseconds: newDuration,
            stickerAssetId: stickerAssetId ?? self.stickerAssetId,
            positionX: newPositionX,
            positionY: newPositionY,
            rotation: rotation ?? self.rotation,
            scale: newScale,
            opacity: newOpacity,
            isFlippedHorizontally: isFlippedHorizontally ?? self.isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically ?? self.isFlippedVertically,
            keyframes: keyframes ?? self.keyframes,
            name: clearName ? nil : (name ?? self.name),
            tintColorValue: clearTintColorValue ? nil : (tintColorValue ?? self.tintColorValue),
            animationSpeed: newAnimationSpeed,
            animationLoops: animationLoops ?? self.animationLoops
        )
    }

    // MARK: - Split Operation

    /// Split clip at offset (relative to clip start).
    ///
    /// Returns (left, right) tuple or nil if offset is invalid.
    /// - Keyframes are partitioned and re-timed relative to each clip.
    /// - Both halves share the same sticker asset, tint, flip, and animation settings.
    func splitAt(_ offsetMicros: Int64) -> (left: StickerClip, right: StickerClip)? {
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

        let left = StickerClip(
            id: UUID().uuidString,
            durationMicroseconds: leftDuration,
            stickerAssetId: stickerAssetId,
            positionX: positionX,
            positionY: positionY,
            rotation: rotation,
            scale: scale,
            opacity: opacity,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            keyframes: leftKeyframes,
            name: name.map { "\($0) (1)" },
            tintColorValue: tintColorValue,
            animationSpeed: animationSpeed,
            animationLoops: animationLoops
        )

        let right = StickerClip(
            id: UUID().uuidString,
            durationMicroseconds: rightDuration,
            stickerAssetId: stickerAssetId,
            positionX: positionX,
            positionY: positionY,
            rotation: rotation,
            scale: scale,
            opacity: opacity,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            keyframes: rightKeyframes,
            name: name.map { "\($0) (2)" },
            tintColorValue: tintColorValue,
            animationSpeed: animationSpeed,
            animationLoops: animationLoops
        )

        return (left: left, right: right)
    }

    // MARK: - Duplication

    /// Create a duplicate with new ID.
    func duplicate() -> StickerClip {
        StickerClip(
            id: UUID().uuidString,
            durationMicroseconds: durationMicroseconds,
            stickerAssetId: stickerAssetId,
            positionX: positionX,
            positionY: positionY,
            rotation: rotation,
            scale: scale,
            opacity: opacity,
            isFlippedHorizontally: isFlippedHorizontally,
            isFlippedVertically: isFlippedVertically,
            keyframes: keyframes,
            name: name.map { "\($0) (copy)" },
            tintColorValue: tintColorValue,
            animationSpeed: animationSpeed,
            animationLoops: animationLoops
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
        case stickerAssetId
        case position
        case rotation
        case scale
        case opacity
        case isFlippedHorizontally
        case isFlippedVertically
        case keyframes
        case name
        case tintColorValue
        case animationSpeed
        case animationLoops
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
        try container.encode(stickerAssetId, forKey: .stickerAssetId)
        try container.encode(PositionJSON(x: positionX, y: positionY), forKey: .position)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(scale, forKey: .scale)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(isFlippedHorizontally, forKey: .isFlippedHorizontally)
        try container.encode(isFlippedVertically, forKey: .isFlippedVertically)
        try container.encode(keyframes, forKey: .keyframes)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(tintColorValue, forKey: .tintColorValue)
        try container.encode(animationSpeed, forKey: .animationSpeed)
        try container.encode(animationLoops, forKey: .animationLoops)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        durationMicroseconds = try container.decode(Int64.self, forKey: .durationMicros)
        stickerAssetId = try container.decode(String.self, forKey: .stickerAssetId)
        let positionJSON = try container.decodeIfPresent(PositionJSON.self, forKey: .position)
        positionX = positionJSON?.x ?? 0.5
        positionY = positionJSON?.y ?? 0.5
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        isFlippedHorizontally = try container.decodeIfPresent(Bool.self, forKey: .isFlippedHorizontally) ?? false
        isFlippedVertically = try container.decodeIfPresent(Bool.self, forKey: .isFlippedVertically) ?? false
        keyframes = try container.decodeIfPresent([StickerKeyframe].self, forKey: .keyframes) ?? []
        name = try container.decodeIfPresent(String.self, forKey: .name)
        tintColorValue = try container.decodeIfPresent(UInt32.self, forKey: .tintColorValue)
        animationSpeed = try container.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? 1.0
        animationLoops = try container.decodeIfPresent(Bool.self, forKey: .animationLoops) ?? true
    }

    // MARK: - CustomStringConvertible

    var description: String {
        let durationMs = durationMicroseconds / 1000
        return "StickerClip(\(id), asset: \(stickerAssetId), \(durationMs)ms)"
    }
}
