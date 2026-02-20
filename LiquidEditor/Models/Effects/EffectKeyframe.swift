import Foundation
import CoreGraphics

// MARK: - EffectKeyframe

/// A keyframe for a single effect parameter at a point in time.
///
/// Stores the value of one parameter at a specific timestamp
/// relative to the clip start. Interpolation between keyframes
/// uses the existing `InterpolationType` and `BezierControlPoints`
/// infrastructure.
struct EffectKeyframe: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Timestamp relative to clip start, in microseconds.
    let timestampMicros: TimeMicros

    /// Parameter value at this keyframe.
    let value: ParameterValue

    /// Interpolation type to the next keyframe.
    let interpolation: InterpolationType

    /// Custom Bezier control points (used when interpolation == .bezier).
    let bezierPoints: BezierControlPoints?

    init(
        id: String,
        timestampMicros: TimeMicros,
        value: ParameterValue,
        interpolation: InterpolationType = .easeInOut,
        bezierPoints: BezierControlPoints? = nil
    ) {
        self.id = id
        self.timestampMicros = timestampMicros
        self.value = value
        self.interpolation = interpolation
        self.bezierPoints = bezierPoints
    }

    /// Create a copy with updated fields.
    func with(
        id: String? = nil,
        timestampMicros: TimeMicros? = nil,
        value: ParameterValue? = nil,
        interpolation: InterpolationType? = nil,
        bezierPoints: BezierControlPoints?? = nil
    ) -> EffectKeyframe {
        EffectKeyframe(
            id: id ?? self.id,
            timestampMicros: timestampMicros ?? self.timestampMicros,
            value: value ?? self.value,
            interpolation: interpolation ?? self.interpolation,
            bezierPoints: bezierPoints ?? self.bezierPoints
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, timestampMicros, value, interpolation, bezierPoints
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: EffectKeyframe, rhs: EffectKeyframe) -> Bool {
        lhs.id == rhs.id &&
        lhs.timestampMicros == rhs.timestampMicros &&
        lhs.value == rhs.value &&
        lhs.interpolation == rhs.interpolation
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestampMicros)
        hasher.combine(value)
        hasher.combine(interpolation)
    }
}

// MARK: - Interpolation Functions

/// Interpolates between two keyframe values at a given progress `t` (0.0-1.0).
///
/// Supports numeric (double, int), color (ARGB int), and point ({x, y}) types.
/// Non-interpolatable types (bool, enum) use hold interpolation (snap to from value).
func interpolateEffectValue(
    from fromValue: ParameterValue,
    to toValue: ParameterValue,
    t: Double,
    interpolation: InterpolationType
) -> ParameterValue {
    let easedT = applyEffectEasing(t, type: interpolation)

    // Numeric interpolation
    if let fromD = fromValue.asDouble, let toD = toValue.asDouble {
        return .double_(fromD + (toD - fromD) * easedT)
    }

    // Color interpolation
    if let fromC = fromValue.asColorInt, let toC = toValue.asColorInt,
       isColorValue(fromC), isColorValue(toC) {
        return .color(lerpColor(from: fromC, to: toC, t: easedT))
    }

    // Point interpolation
    if let fromP = fromValue.asPoint, let toP = toValue.asPoint {
        return .point(
            x: fromP.x + (toP.x - fromP.x) * easedT,
            y: fromP.y + (toP.y - fromP.y) * easedT
        )
    }

    // Range interpolation
    if let fromR = fromValue.asRange, let toR = toValue.asRange {
        return .range(
            start: fromR.start + (toR.start - fromR.start) * easedT,
            end: fromR.end + (toR.end - fromR.end) * easedT
        )
    }

    // Non-interpolatable: hold at from value until we reach the end
    return t < 1.0 ? fromValue : toValue
}

/// Resolve the value of an effect parameter at a given clip time
/// using the parameter's keyframe track.
func resolveKeyframedValue(
    keyframes: [EffectKeyframe],
    clipTimeMicros: TimeMicros,
    staticValue: ParameterValue
) -> ParameterValue {
    if keyframes.isEmpty { return staticValue }

    // Find surrounding keyframes
    var before: EffectKeyframe?
    var after: EffectKeyframe?

    for kf in keyframes {
        if kf.timestampMicros <= clipTimeMicros {
            before = kf
        }
        if kf.timestampMicros >= clipTimeMicros, after == nil {
            after = kf
        }
    }

    guard let before else { return after?.value ?? staticValue }
    guard let after else { return before.value }
    if before.timestampMicros == after.timestampMicros { return before.value }

    // Interpolate
    let totalDuration = Double(after.timestampMicros - before.timestampMicros)
    let elapsed = Double(clipTimeMicros - before.timestampMicros)
    let t = totalDuration > 0 ? min(max(elapsed / totalDuration, 0.0), 1.0) : 0.0

    return interpolateEffectValue(
        from: before.value,
        to: after.value,
        t: t,
        interpolation: before.interpolation
    )
}

// MARK: - Private Helpers

/// Apply easing function for effect interpolation.
///
/// Uses a subset matching the Dart implementation's `_applyEasing`.
private func applyEffectEasing(_ t: Double, type: InterpolationType) -> Double {
    switch type {
    case .linear:
        return t
    case .hold:
        return 0.0
    case .easeIn:
        return t * t
    case .easeOut:
        return t * (2.0 - t)
    case .easeInOut:
        return t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
    case .cubicIn:
        return t * t * t
    case .cubicOut:
        return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
    case .cubicInOut:
        return t < 0.5
            ? 4.0 * t * t * t
            : 1.0 - (-2.0 * t + 2.0) * (-2.0 * t + 2.0) * (-2.0 * t + 2.0) / 2.0
    default:
        return t // Default to linear for other types
    }
}

/// Check if a value looks like an ARGB color (>= 0xFF000000).
private func isColorValue(_ value: Int) -> Bool {
    value >= 0xFF00_0000
}

/// Linearly interpolate ARGB color components.
private func lerpColor(from: Int, to: Int, t: Double) -> Int {
    let aFrom = Double((from >> 24) & 0xFF)
    let rFrom = Double((from >> 16) & 0xFF)
    let gFrom = Double((from >> 8) & 0xFF)
    let bFrom = Double(from & 0xFF)

    let aTo = Double((to >> 24) & 0xFF)
    let rTo = Double((to >> 16) & 0xFF)
    let gTo = Double((to >> 8) & 0xFF)
    let bTo = Double(to & 0xFF)

    let a = aFrom + (aTo - aFrom) * t
    let r = rFrom + (rTo - rFrom) * t
    let g = gFrom + (gTo - gFrom) * t
    let b = bFrom + (bTo - bFrom) * t

    return (Int(a.rounded()) << 24) | (Int(r.rounded()) << 16) | (Int(g.rounded()) << 8) | Int(b.rounded())
}
