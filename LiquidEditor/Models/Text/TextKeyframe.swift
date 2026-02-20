import Foundation
import CoreGraphics

/// A keyframe for text clip animation.
///
/// Timestamps are relative to the clip start.
/// Position uses normalized coordinates (0.0-1.0) where (0.5, 0.5) is center.
struct TextKeyframe: Codable, Equatable, Hashable, Sendable {
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

    /// Create a copy with optional field overrides.
    func with(
        id: String? = nil,
        timestampMicros: TimeMicros? = nil,
        position: CGPoint? = nil,
        scale: Double? = nil,
        rotation: Double? = nil,
        opacity: Double? = nil,
        interpolation: InterpolationType? = nil,
        bezierPoints: BezierControlPoints? = nil,
        clearBezierPoints: Bool = false
    ) -> TextKeyframe {
        TextKeyframe(
            id: id ?? self.id,
            timestampMicros: timestampMicros ?? self.timestampMicros,
            position: position ?? self.position,
            scale: scale ?? self.scale,
            rotation: rotation ?? self.rotation,
            opacity: opacity ?? self.opacity,
            interpolation: interpolation ?? self.interpolation,
            bezierPoints: clearBezierPoints ? nil : (bezierPoints ?? self.bezierPoints)
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, timestampMicros, position, scale, rotation, opacity
        case interpolation, bezierPoints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        timestampMicros = try container.decode(TimeMicros.self, forKey: .timestampMicros)

        if let posDict = try container.decodeIfPresent([String: Double].self, forKey: .position) {
            position = CGPoint(x: posDict["x"] ?? 0.5, y: posDict["y"] ?? 0.5)
        } else {
            position = CGPoint(x: 0.5, y: 0.5)
        }

        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0

        let interpName = try container.decodeIfPresent(String.self, forKey: .interpolation) ?? "easeInOut"
        interpolation = InterpolationType(rawValue: interpName) ?? .easeInOut

        bezierPoints = try container.decodeIfPresent(BezierControlPoints.self, forKey: .bezierPoints)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestampMicros, forKey: .timestampMicros)
        try container.encode(["x": position.x, "y": position.y], forKey: .position)
        try container.encode(scale, forKey: .scale)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(interpolation.rawValue, forKey: .interpolation)
        try container.encodeIfPresent(bezierPoints, forKey: .bezierPoints)
    }
}
