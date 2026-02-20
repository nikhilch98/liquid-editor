import Foundation
import CoreGraphics

// MARK: - StickerKeyframe

/// A keyframe for sticker clip animation.
///
/// Timestamps are relative to the clip start.
/// Position uses normalized coordinates (0.0-1.0) where (0.5, 0.5) is center.
///
/// Architecturally parallel to TextKeyframe -- intentionally kept separate
/// to allow future divergence (e.g., tint color animation, flip state
/// animation, or animation playback offset).
struct StickerKeyframe: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this keyframe.
    let id: String

    /// Timestamp relative to clip start (microseconds).
    let timestampMicros: TimeMicros

    /// Position (normalized 0.0-1.0).
    let position: CGPoint

    /// Scale factor.
    let scale: Double

    /// Rotation in radians.
    let rotation: Double

    /// Opacity (0.0-1.0).
    let opacity: Double

    /// Interpolation type to next keyframe.
    let interpolation: InterpolationType

    /// Custom bezier control points (when interpolation == .bezier).
    let bezierPoints: BezierControlPoints?

    init(
        id: String,
        timestampMicros: TimeMicros,
        position: CGPoint,
        scale: Double = 1.0,
        rotation: Double = 0.0,
        opacity: Double = 1.0,
        interpolation: InterpolationType = .easeInOut,
        bezierPoints: BezierControlPoints? = nil
    ) {
        self.id = id
        self.timestampMicros = timestampMicros
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.interpolation = interpolation
        self.bezierPoints = bezierPoints
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        timestampMicros: TimeMicros? = nil,
        position: CGPoint? = nil,
        scale: Double? = nil,
        rotation: Double? = nil,
        opacity: Double? = nil,
        interpolation: InterpolationType? = nil,
        bezierPoints: BezierControlPoints?? = nil
    ) -> StickerKeyframe {
        StickerKeyframe(
            id: id ?? self.id,
            timestampMicros: timestampMicros ?? self.timestampMicros,
            position: position ?? self.position,
            scale: scale ?? self.scale,
            rotation: rotation ?? self.rotation,
            opacity: opacity ?? self.opacity,
            interpolation: interpolation ?? self.interpolation,
            bezierPoints: bezierPoints ?? self.bezierPoints
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMicros
        case position
        case scale
        case rotation
        case opacity
        case interpolation
        case bezierPoints
    }

    private enum PositionKeys: String, CodingKey {
        case x, y
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        timestampMicros = try container.decode(TimeMicros.self, forKey: .timestampMicros)

        if let posContainer = try? container.nestedContainer(keyedBy: PositionKeys.self, forKey: .position) {
            let x = try posContainer.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
            let y = try posContainer.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
            position = CGPoint(x: x, y: y)
        } else {
            position = CGPoint(x: 0.5, y: 0.5)
        }

        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0

        let interpStr = try container.decodeIfPresent(String.self, forKey: .interpolation)
        interpolation = interpStr.flatMap { InterpolationType(rawValue: $0) } ?? .easeInOut

        bezierPoints = try container.decodeIfPresent(BezierControlPoints.self, forKey: .bezierPoints)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestampMicros, forKey: .timestampMicros)

        var posContainer = container.nestedContainer(keyedBy: PositionKeys.self, forKey: .position)
        try posContainer.encode(position.x, forKey: .x)
        try posContainer.encode(position.y, forKey: .y)

        try container.encode(scale, forKey: .scale)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(interpolation.rawValue, forKey: .interpolation)
        try container.encodeIfPresent(bezierPoints, forKey: .bezierPoints)
    }
}
