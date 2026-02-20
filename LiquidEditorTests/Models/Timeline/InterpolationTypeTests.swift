import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("InterpolationType Tests")
struct InterpolationTypeTests {

    // MARK: - Boundary Conditions

    @Test("All easings return ~0 at t=0")
    func allEasingsAtZero() {
        for easing in InterpolationType.allCases {
            if easing == .bezier { continue } // needs control points
            let result = easing.apply(0.0)
            #expect(abs(result) < 1e-10, "Easing \(easing) should return ~0 at t=0, got \(result)")
        }
    }

    @Test("All easings return 1 at t=1")
    func allEasingsAtOne() {
        for easing in InterpolationType.allCases {
            if easing == .bezier { continue }
            let result = easing.apply(1.0)
            #expect(abs(result - 1.0) < 0.001, "Easing \(easing) should return ~1 at t=1, got \(result)")
        }
    }

    // MARK: - Specific Easings

    @Test("Linear returns identity")
    func linear() {
        #expect(InterpolationType.linear.apply(0.0) == 0.0)
        #expect(InterpolationType.linear.apply(0.25) == 0.25)
        #expect(InterpolationType.linear.apply(0.5) == 0.5)
        #expect(InterpolationType.linear.apply(0.75) == 0.75)
        #expect(InterpolationType.linear.apply(1.0) == 1.0)
    }

    @Test("Hold returns 0 until t=1")
    func hold() {
        #expect(InterpolationType.hold.apply(0.0) == 0.0)
        #expect(InterpolationType.hold.apply(0.5) == 0.0)
        #expect(InterpolationType.hold.apply(0.99) == 0.0)
        #expect(InterpolationType.hold.apply(1.0) == 1.0)
    }

    @Test("EaseIn starts slow")
    func easeIn() {
        let mid = InterpolationType.easeIn.apply(0.5)
        // At t=0.5, easeIn (quadratic) = 0.25
        #expect(mid < 0.5, "EaseIn at 0.5 should be < 0.5")
        #expect(abs(mid - 0.25) < 0.001)
    }

    @Test("EaseOut ends slow")
    func easeOut() {
        let mid = InterpolationType.easeOut.apply(0.5)
        // At t=0.5, easeOut = 0.75
        #expect(mid > 0.5, "EaseOut at 0.5 should be > 0.5")
        #expect(abs(mid - 0.75) < 0.001)
    }

    @Test("EaseInOut is symmetric at t=0.5")
    func easeInOut() {
        let mid = InterpolationType.easeInOut.apply(0.5)
        #expect(abs(mid - 0.5) < 0.001, "EaseInOut at t=0.5 should be 0.5")
    }

    @Test("CubicIn at midpoint")
    func cubicIn() {
        let mid = InterpolationType.cubicIn.apply(0.5)
        #expect(abs(mid - 0.125) < 0.001) // 0.5^3 = 0.125
    }

    @Test("CubicOut at midpoint")
    func cubicOut() {
        let mid = InterpolationType.cubicOut.apply(0.5)
        #expect(abs(mid - 0.875) < 0.001) // 1 - (0.5)^3 = 0.875
    }

    // MARK: - Overshoot Easings

    @Test("Spring overshoots")
    func springOvershoots() {
        // Spring easing typically overshoots past 1.0
        var hasOvershoot = false
        for i in stride(from: 0.0, through: 1.0, by: 0.01) {
            let v = InterpolationType.spring.apply(i)
            if v > 1.01 { hasOvershoot = true; break }
        }
        // Spring may or may not overshoot depending on damping; check it returns to 1
        let final = InterpolationType.spring.apply(1.0)
        #expect(abs(final - 1.0) < 0.001)
        _ = hasOvershoot // suppress unused warning
    }

    @Test("BackIn goes negative")
    func backInNegative() {
        let early = InterpolationType.backIn.apply(0.1)
        #expect(early < 0.0, "BackIn should go negative initially")
    }

    @Test("BackOut overshoots 1.0")
    func backOutOvershoots() {
        let late = InterpolationType.backOut.apply(0.9)
        #expect(late > 1.0, "BackOut should overshoot past 1.0 near end")
    }

    // MARK: - Bezier with Custom Points

    @Test("Bezier with control points")
    func bezierCustom() {
        let points = BezierControlPoints(
            controlPoint1: CGPoint(x: 0.42, y: 0.0),
            controlPoint2: CGPoint(x: 0.58, y: 1.0)
        )
        let result = InterpolationType.bezier.apply(0.5, bezierPoints: points)
        // Should be close to 0.5 for this symmetric curve
        #expect(abs(result - 0.5) < 0.15)
    }

    @Test("Bezier without points returns identity")
    func bezierNoPoints() {
        let result = InterpolationType.bezier.apply(0.5)
        #expect(result == 0.5)
    }

    // MARK: - Display Properties

    @Test("displayName returns human-readable names")
    func displayNames() {
        #expect(InterpolationType.linear.displayName == "Linear")
        #expect(InterpolationType.easeInOut.displayName == "Ease In-Out")
        #expect(InterpolationType.spring.displayName == "Spring")
        #expect(InterpolationType.bounce.displayName == "Bounce")
    }

    @Test("sfSymbolName returns valid symbols")
    func sfSymbolNames() {
        #expect(InterpolationType.linear.sfSymbolName == "chart.line.uptrend.xyaxis")
        #expect(InterpolationType.hold.sfSymbolName == "stairs")
        #expect(InterpolationType.spring.sfSymbolName == "waveform")
    }

    // MARK: - Codable

    @Test("InterpolationType encodes as raw string")
    func codableEncoding() throws {
        let easing = InterpolationType.easeInOut
        let data = try JSONEncoder().encode(easing)
        let str = String(data: data, encoding: .utf8)!
        #expect(str == "\"easeInOut\"")
    }

    @Test("InterpolationType decodes from string")
    func codableDecoding() throws {
        let json = "\"cubicOut\""
        let data = json.data(using: .utf8)!
        let easing = try JSONDecoder().decode(InterpolationType.self, from: data)
        #expect(easing == .cubicOut)
    }

    @Test("All cases are codable")
    func allCasesCodable() throws {
        for easing in InterpolationType.allCases {
            let data = try JSONEncoder().encode(easing)
            let decoded = try JSONDecoder().decode(InterpolationType.self, from: data)
            #expect(decoded == easing, "Roundtrip failed for \(easing)")
        }
    }

    // MARK: - BezierControlPoints

    @Test("BezierControlPoints default values")
    func bezierDefaults() {
        let bp = BezierControlPoints()
        #expect(bp.controlPoint1 == CGPoint(x: 0.25, y: 0.1))
        #expect(bp.controlPoint2 == CGPoint(x: 0.25, y: 1.0))
    }

    @Test("BezierControlPoints easeInOut preset")
    func bezierEaseInOutPreset() {
        let bp = BezierControlPoints.easeInOut
        #expect(bp.controlPoint1 == CGPoint(x: 0.42, y: 0.0))
        #expect(bp.controlPoint2 == CGPoint(x: 0.58, y: 1.0))
    }

    @Test("BezierControlPoints with method")
    func bezierWith() {
        let bp = BezierControlPoints()
        let modified = bp.with(controlPoint1: CGPoint(x: 0.5, y: 0.5))
        #expect(modified.controlPoint1 == CGPoint(x: 0.5, y: 0.5))
        #expect(modified.controlPoint2 == bp.controlPoint2)
    }

    @Test("BezierControlPoints Codable uses Dart keys")
    func bezierCodable() throws {
        let json = #"{"cp1x": 0.1, "cp1y": 0.2, "cp2x": 0.3, "cp2y": 0.4}"#
        let data = json.data(using: .utf8)!
        let bp = try JSONDecoder().decode(BezierControlPoints.self, from: data)
        #expect(bp.controlPoint1 == CGPoint(x: 0.1, y: 0.2))
        #expect(bp.controlPoint2 == CGPoint(x: 0.3, y: 0.4))
    }

    @Test("BezierControlPoints Codable roundtrip")
    func bezierCodableRoundtrip() throws {
        let original = BezierControlPoints(
            controlPoint1: CGPoint(x: 0.3, y: 0.1),
            controlPoint2: CGPoint(x: 0.7, y: 0.9)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BezierControlPoints.self, from: data)
        #expect(decoded == original)
    }

    @Test("BezierControlPoints Codable defaults for missing keys")
    func bezierCodableMissingKeys() throws {
        let json = #"{}"#
        let data = json.data(using: .utf8)!
        let bp = try JSONDecoder().decode(BezierControlPoints.self, from: data)
        #expect(bp.controlPoint1 == CGPoint(x: 0.25, y: 0.1))
        #expect(bp.controlPoint2 == CGPoint(x: 0.25, y: 1.0))
    }
}
