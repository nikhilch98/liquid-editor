/// Shared interpolation utilities for keyframe animation.
///
/// Extracts easing functions into a reusable utility namespace shared by
/// both video keyframe and text keyframe interpolation pipelines.
///
/// All 21 `InterpolationType` values are supported.
/// Easing functions follow the standard formulas from https://easings.net/
///
/// Thread Safety: `Sendable` by construction (enum with only static methods,
/// no mutable state). Safe to call from any thread or actor context.

import CoreGraphics
import Foundation

// MARK: - InterpolationUtils

/// Shared interpolation math used by video and text keyframe systems.
///
/// Uses an `enum` namespace (no cases) with all-static methods.
/// No instance creation is needed or possible.
enum InterpolationUtils {

    // MARK: - Easing

    /// Apply easing function to a normalized t value (0.0-1.0).
    ///
    /// Returns an eased value, which may exceed [0, 1] for overshoot
    /// easings (spring, elastic, back).
    ///
    /// - Parameters:
    ///   - t: Normalized progress (0.0-1.0). Values outside this range are clamped.
    ///   - type: The interpolation/easing type to apply.
    ///   - bezier: Optional custom Bezier control points (only used when `type == .bezier`).
    /// - Returns: The eased progress value.
    static func applyEasing(
        _ t: Double,
        _ type: InterpolationType,
        _ bezier: BezierControlPoints? = nil
    ) -> Double {
        let clampedT = min(max(t, 0.0), 1.0)
        switch type {
        case .linear:
            return clampedT

        case .hold:
            return clampedT < 1 ? 0.0 : 1.0

        case .easeIn:
            return clampedT * clampedT

        case .easeOut:
            return 1 - (1 - clampedT) * (1 - clampedT)

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
            guard let bp = bezier else { return t }
            return evaluateCubicBezier(t, p1: bp.controlPoint1, p2: bp.controlPoint2)

        case .spring:
            return springEasing(t)

        case .bounce:
            return bounceEasing(t)

        case .elastic:
            return elasticEasing(t)

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

    // MARK: - Interpolation Helpers

    /// Linearly interpolate between two `Double` values.
    ///
    /// - Parameters:
    ///   - a: Start value.
    ///   - b: End value.
    ///   - t: Normalized progress (0.0-1.0).
    /// - Returns: Interpolated value.
    static func lerpDouble(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Linearly interpolate between two `CGPoint` values.
    ///
    /// - Parameters:
    ///   - a: Start point.
    ///   - b: End point.
    ///   - t: Normalized progress (0.0-1.0).
    /// - Returns: Interpolated point.
    static func lerpOffset(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t
        )
    }

    /// Interpolate between two angles (in radians), taking the shortest path.
    ///
    /// Normalizes the delta to [-pi, pi] to avoid spinning the long way around.
    ///
    /// - Parameters:
    ///   - a: Start angle (radians).
    ///   - b: End angle (radians).
    ///   - t: Normalized progress (0.0-1.0).
    /// - Returns: Interpolated angle (radians).
    static func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var delta = b - a
        // Normalize to [-pi, pi]
        while delta > .pi {
            delta -= 2 * .pi
        }
        while delta < -.pi {
            delta += 2 * .pi
        }
        return a + delta * t
    }

    // MARK: - Private Easing Implementations

    /// Spring easing with damped oscillation.
    private static func springEasing(_ t: Double) -> Double {
        let c4 = (2 * Double.pi) / 3
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
    }

    /// Bounce easing with piecewise quadratic segments.
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

    /// Elastic easing with overshoot oscillation.
    private static func elasticEasing(_ t: Double) -> Double {
        let c4 = (2 * Double.pi) / 3
        if t == 0 { return 0 }
        if t == 1 { return 1 }
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
    }

    /// Evaluate cubic Bezier curve for custom easing via Newton-Raphson.
    private static func evaluateCubicBezier(
        _ t: Double,
        p1: CGPoint,
        p2: CGPoint
    ) -> Double {
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

    private static func cubicBezierValue(
        _ t: Double,
        p0: Double,
        p1: Double,
        p2: Double,
        p3: Double
    ) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        return mt3 * p0 + 3 * mt2 * t * p1 + 3 * mt * t2 * p2 + t3 * p3
    }

    private static func cubicBezierDerivative(
        _ t: Double,
        p0: Double,
        p1: Double,
        p2: Double,
        p3: Double
    ) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * (p1 - p0) + 6 * mt * t * (p2 - p1) + 3 * t * t * (p3 - p2)
    }
}
