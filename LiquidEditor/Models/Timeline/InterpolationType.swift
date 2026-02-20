import Foundation
import CoreGraphics

/// Available interpolation/easing types between keyframes.
/// 21 easing types matching standard formulas from https://easings.net/
enum InterpolationType: String, Codable, CaseIterable, Sendable {
    // Basic
    case linear
    case hold

    // Standard Easing
    case easeIn
    case easeOut
    case easeInOut

    // Cubic Bezier
    case cubicIn
    case cubicOut
    case cubicInOut
    case bezier

    // Advanced
    case spring
    case bounce
    case elastic

    // Circular
    case circIn
    case circOut
    case circInOut

    // Exponential
    case expoIn
    case expoOut
    case expoInOut

    // Overshoot
    case backIn
    case backOut
    case backInOut

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .linear: "Linear"
        case .hold: "Hold"
        case .easeIn: "Ease In"
        case .easeOut: "Ease Out"
        case .easeInOut: "Ease In-Out"
        case .cubicIn: "Cubic In"
        case .cubicOut: "Cubic Out"
        case .cubicInOut: "Cubic In-Out"
        case .bezier: "Bezier (Custom)"
        case .spring: "Spring"
        case .bounce: "Bounce"
        case .elastic: "Elastic"
        case .circIn: "Circular In"
        case .circOut: "Circular Out"
        case .circInOut: "Circular In-Out"
        case .expoIn: "Exponential In"
        case .expoOut: "Exponential Out"
        case .expoInOut: "Exponential In-Out"
        case .backIn: "Back In"
        case .backOut: "Back Out"
        case .backInOut: "Back In-Out"
        }
    }

    /// SF Symbol name for UI display.
    var sfSymbolName: String {
        switch self {
        case .linear: "chart.line.uptrend.xyaxis"
        case .hold: "stairs"
        case .easeIn, .easeOut, .easeInOut: "point.topleft.down.to.point.bottomright.curvepath"
        case .spring, .elastic: "waveform"
        case .bounce: "basketball"
        case .bezier: "scribble.variable"
        default: "function"
        }
    }

    /// Apply this easing function to a normalized t value (0.0-1.0).
    ///
    /// Returns an eased value, which may exceed [0,1] for overshoot
    /// easings (spring, elastic, back).
    func apply(_ t: Double, bezierPoints: BezierControlPoints? = nil) -> Double {
        switch self {
        case .linear:
            return t

        case .hold:
            return t < 1 ? 0.0 : 1.0

        case .easeIn:
            return t * t

        case .easeOut:
            return 1 - (1 - t) * (1 - t)

        case .easeInOut:
            return t < 0.5
                ? 2 * t * t
                : 1 - pow(-2 * t + 2, 2) / 2

        case .cubicIn:
            return t * t * t

        case .cubicOut:
            return 1 - pow(1 - t, 3)

        case .cubicInOut:
            return t < 0.5
                ? 4 * t * t * t
                : 1 - pow(-2 * t + 2, 3) / 2

        case .bezier:
            guard let bp = bezierPoints else { return t }
            return Self.evaluateCubicBezier(t, p1: bp.controlPoint1, p2: bp.controlPoint2)

        case .spring:
            return Self.springEasing(t)

        case .bounce:
            return Self.bounceEasing(t)

        case .elastic:
            return Self.elasticEasing(t)

        case .circIn:
            return 1 - sqrt(1 - t * t)

        case .circOut:
            return sqrt(1 - pow(t - 1, 2))

        case .circInOut:
            if t < 0.5 {
                return (1 - sqrt(1 - pow(2 * t, 2))) / 2
            } else {
                return (sqrt(1 - pow(-2 * t + 2, 2)) + 1) / 2
            }

        case .expoIn:
            return t == 0 ? 0.0 : pow(2, 10 * t - 10)

        case .expoOut:
            return t == 1 ? 1.0 : 1 - pow(2, -10 * t)

        case .expoInOut:
            if t == 0 { return 0.0 }
            if t == 1 { return 1.0 }
            if t < 0.5 {
                return pow(2, 20 * t - 10) / 2
            } else {
                return (2 - pow(2, -20 * t + 10)) / 2
            }

        case .backIn:
            let c1 = 1.70158
            let c3 = c1 + 1
            return c3 * t * t * t - c1 * t * t

        case .backOut:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)

        case .backInOut:
            let c1 = 1.70158
            let c2 = c1 * 1.525
            if t < 0.5 {
                return (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
            } else {
                return (pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2
            }
        }
    }

    // MARK: - Private Easing Implementations

    private static func springEasing(_ t: Double) -> Double {
        let c4 = (2 * Double.pi) / 3
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
    }

    private static func bounceEasing(_ t: Double) -> Double {
        let n1 = 7.5625
        let d1 = 2.75

        if t < 1 / d1 {
            return n1 * t * t
        } else if t < 2 / d1 {
            let t2 = t - 1.5 / d1
            return n1 * t2 * t2 + 0.75
        } else if t < 2.5 / d1 {
            let t2 = t - 2.25 / d1
            return n1 * t2 * t2 + 0.9375
        } else {
            let t2 = t - 2.625 / d1
            return n1 * t2 * t2 + 0.984375
        }
    }

    private static func elasticEasing(_ t: Double) -> Double {
        let c4 = (2 * Double.pi) / 3
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
    }

    private static func evaluateCubicBezier(_ t: Double, p1: CGPoint, p2: CGPoint) -> Double {
        let p0 = CGPoint.zero
        let p3 = CGPoint(x: 1, y: 1)

        // Newton-Raphson to find t parameter for x coordinate
        var guess = t
        for _ in 0..<8 {
            let x = cubicBezierValue(guess, p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x)
            let dx = cubicBezierDerivative(guess, p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x)
            if abs(dx) < 0.00001 { break }
            guess -= (x - t) / dx
        }

        return cubicBezierValue(guess, p0: p0.y, p1: p1.y, p2: p2.y, p3: p3.y)
    }

    private static func cubicBezierValue(_ t: Double, p0: Double, p1: Double, p2: Double, p3: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        return mt3 * p0 + 3 * mt2 * t * p1 + 3 * mt * t2 * p2 + t3 * p3
    }

    private static func cubicBezierDerivative(_ t: Double, p0: Double, p1: Double, p2: Double, p3: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * (p1 - p0) + 6 * mt * t * (p2 - p1) + 3 * t * t * (p3 - p2)
    }
}

// MARK: - BezierControlPoints

/// Custom Bezier curve control points for user-defined easing.
struct BezierControlPoints: Codable, Equatable, Hashable, Sendable {
    let controlPoint1: CGPoint
    let controlPoint2: CGPoint

    init(
        controlPoint1: CGPoint = CGPoint(x: 0.25, y: 0.1),
        controlPoint2: CGPoint = CGPoint(x: 0.25, y: 1.0)
    ) {
        self.controlPoint1 = controlPoint1
        self.controlPoint2 = controlPoint2
    }

    /// Standard ease-in-out preset.
    static let easeInOut = BezierControlPoints(
        controlPoint1: CGPoint(x: 0.42, y: 0.0),
        controlPoint2: CGPoint(x: 0.58, y: 1.0)
    )

    func with(controlPoint1: CGPoint? = nil, controlPoint2: CGPoint? = nil) -> BezierControlPoints {
        BezierControlPoints(
            controlPoint1: controlPoint1 ?? self.controlPoint1,
            controlPoint2: controlPoint2 ?? self.controlPoint2
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case cp1x, cp1y, cp2x, cp2y
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cp1x = try container.decodeIfPresent(Double.self, forKey: .cp1x) ?? 0.25
        let cp1y = try container.decodeIfPresent(Double.self, forKey: .cp1y) ?? 0.1
        let cp2x = try container.decodeIfPresent(Double.self, forKey: .cp2x) ?? 0.25
        let cp2y = try container.decodeIfPresent(Double.self, forKey: .cp2y) ?? 1.0
        controlPoint1 = CGPoint(x: cp1x, y: cp1y)
        controlPoint2 = CGPoint(x: cp2x, y: cp2y)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(controlPoint1.x, forKey: .cp1x)
        try container.encode(controlPoint1.y, forKey: .cp1y)
        try container.encode(controlPoint2.x, forKey: .cp2x)
        try container.encode(controlPoint2.y, forKey: .cp2y)
    }
}
