import Foundation
import CoreGraphics

/// A keyframe for color grade animation.
///
/// Each keyframe captures the full `ColorGrade` state at a specific
/// timestamp, with an interpolation type controlling the transition
/// to the next keyframe.
struct ColorKeyframe: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Timestamp relative to clip start (microseconds).
    let timestampMicros: TimeMicros

    /// Full color grade state at this keyframe.
    let grade: ColorGrade

    /// Interpolation type to the next keyframe.
    let interpolation: InterpolationType

    /// Custom bezier control points (for `InterpolationType.bezier`).
    let bezierPoints: [CGPoint]?

    /// Creation timestamp.
    let createdAt: Date

    init(
        id: String,
        timestampMicros: TimeMicros,
        grade: ColorGrade,
        interpolation: InterpolationType = .linear,
        bezierPoints: [CGPoint]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timestampMicros = timestampMicros
        self.grade = grade
        self.interpolation = interpolation
        self.bezierPoints = bezierPoints
        self.createdAt = createdAt
    }

    /// Timestamp in milliseconds.
    var timeMillis: Int64 { timestampMicros / 1000 }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        timestampMicros: TimeMicros? = nil,
        grade: ColorGrade? = nil,
        interpolation: InterpolationType? = nil,
        bezierPoints: [CGPoint]? = nil,
        createdAt: Date? = nil
    ) -> ColorKeyframe {
        ColorKeyframe(
            id: id ?? self.id,
            timestampMicros: timestampMicros ?? self.timestampMicros,
            grade: grade ?? self.grade,
            interpolation: interpolation ?? self.interpolation,
            bezierPoints: bezierPoints ?? self.bezierPoints,
            createdAt: createdAt ?? self.createdAt
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, timestampMicros, grade, interpolation, bezierPoints, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        timestampMicros = try container.decode(TimeMicros.self, forKey: .timestampMicros)
        grade = try container.decode(ColorGrade.self, forKey: .grade)

        let interpName = try container.decodeIfPresent(String.self, forKey: .interpolation) ?? "linear"
        interpolation = InterpolationType(rawValue: interpName) ?? .linear

        if let pointsArray = try container.decodeIfPresent([[String: Double]].self, forKey: .bezierPoints) {
            bezierPoints = pointsArray.map { dict in
                CGPoint(x: dict["x"] ?? 0, y: dict["y"] ?? 0)
            }
        } else {
            bezierPoints = nil
        }

        let createdAtStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtStr) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestampMicros, forKey: .timestampMicros)
        try container.encode(grade, forKey: .grade)
        try container.encode(interpolation.rawValue, forKey: .interpolation)

        if let bp = bezierPoints {
            let pointDicts = bp.map { ["x": $0.x, "y": $0.y] }
            try container.encode(pointDicts, forKey: .bezierPoints)
        }

        let formatter = ISO8601DateFormatter()
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
    }

    // MARK: - Equatable (identity-based)

    static func == (lhs: ColorKeyframe, rhs: ColorKeyframe) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
