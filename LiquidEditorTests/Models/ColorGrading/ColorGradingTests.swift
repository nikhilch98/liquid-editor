import Testing
import CoreGraphics
import Foundation
@testable import LiquidEditor

// MARK: - HSLAdjustment Tests

@Suite("HSLAdjustment Tests")
struct HSLAdjustmentTests {

    @Test("Default creation is identity")
    func defaultCreation() {
        let adj = HSLAdjustment()
        #expect(adj.hue == 0.0)
        #expect(adj.saturation == 0.0)
        #expect(adj.luminance == 0.0)
        #expect(adj.isIdentity)
    }

    @Test("identity static constant is identity")
    func identityConstant() {
        let adj = HSLAdjustment.identity
        #expect(adj.isIdentity)
    }

    @Test("Custom values creation")
    func customValues() {
        let adj = HSLAdjustment(hue: 120.0, saturation: 0.5, luminance: -0.3)
        #expect(adj.hue == 120.0)
        #expect(adj.saturation == 0.5)
        #expect(adj.luminance == -0.3)
        #expect(!adj.isIdentity)
    }

    @Test("isIdentity uses epsilon comparison")
    func isIdentityEpsilon() {
        let adj = HSLAdjustment(hue: 0.00001, saturation: 0.00001, luminance: 0.00001)
        #expect(adj.isIdentity)
    }

    @Test("isIdentity returns false for significant values")
    func isIdentityFalse() {
        let adj = HSLAdjustment(hue: 1.0, saturation: 0.0, luminance: 0.0)
        #expect(!adj.isIdentity)
    }

    @Test("Epsilon-based equality treats near-zero as equal")
    func epsilonEquality() {
        let a = HSLAdjustment(hue: 0.0, saturation: 0.0, luminance: 0.0)
        let b = HSLAdjustment(hue: 0.00005, saturation: 0.00005, luminance: 0.00005)
        #expect(a == b)
    }

    @Test("Equality detects significant differences")
    func equalityDifference() {
        let a = HSLAdjustment(hue: 0.0, saturation: 0.0, luminance: 0.0)
        let b = HSLAdjustment(hue: 1.0, saturation: 0.0, luminance: 0.0)
        #expect(a != b)
    }

    @Test("lerp at t=0 returns first adjustment")
    func lerpZero() {
        let a = HSLAdjustment(hue: 10.0, saturation: 0.2, luminance: 0.1)
        let b = HSLAdjustment(hue: 50.0, saturation: 0.8, luminance: -0.5)
        let result = HSLAdjustment.lerp(a, b, t: 0.0)

        #expect(abs(result.hue - 10.0) < 0.0001)
        #expect(abs(result.saturation - 0.2) < 0.0001)
        #expect(abs(result.luminance - 0.1) < 0.0001)
    }

    @Test("lerp at t=1 returns second adjustment")
    func lerpOne() {
        let a = HSLAdjustment(hue: 10.0, saturation: 0.2, luminance: 0.1)
        let b = HSLAdjustment(hue: 50.0, saturation: 0.8, luminance: -0.5)
        let result = HSLAdjustment.lerp(a, b, t: 1.0)

        #expect(abs(result.hue - 50.0) < 0.0001)
        #expect(abs(result.saturation - 0.8) < 0.0001)
        #expect(abs(result.luminance - (-0.5)) < 0.0001)
    }

    @Test("lerp at t=0.5 returns midpoint")
    func lerpHalf() {
        let a = HSLAdjustment(hue: 0.0, saturation: 0.0, luminance: 0.0)
        let b = HSLAdjustment(hue: 100.0, saturation: 1.0, luminance: -1.0)
        let result = HSLAdjustment.lerp(a, b, t: 0.5)

        #expect(abs(result.hue - 50.0) < 0.0001)
        #expect(abs(result.saturation - 0.5) < 0.0001)
        #expect(abs(result.luminance - (-0.5)) < 0.0001)
    }

    @Test("with() creates copy with overridden fields")
    func withCopy() {
        let adj = HSLAdjustment(hue: 30.0, saturation: 0.5, luminance: 0.1)
        let updated = adj.with(hue: 60.0)

        #expect(abs(updated.hue - 60.0) < 0.0001)
        #expect(abs(updated.saturation - 0.5) < 0.0001) // unchanged
        #expect(abs(updated.luminance - 0.1) < 0.0001) // unchanged
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let adj = HSLAdjustment(hue: 45.0, saturation: 0.7, luminance: -0.3)
        let data = try JSONEncoder().encode(adj)
        let decoded = try JSONDecoder().decode(HSLAdjustment.self, from: data)

        #expect(decoded == adj)
    }

    @Test("Hashable produces same hash for identical values")
    func hashable() {
        let a = HSLAdjustment(hue: 10.0, saturation: 0.5, luminance: -0.3)
        let b = HSLAdjustment(hue: 10.0, saturation: 0.5, luminance: -0.3)
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - CurvePoint Tests

@Suite("CurvePoint Tests")
struct CurvePointTests {

    @Test("Creation with positional args")
    func creation() {
        let p = CurvePoint(0.3, 0.7)
        #expect(abs(p.x - 0.3) < 0.0001)
        #expect(abs(p.y - 0.7) < 0.0001)
    }

    @Test("Epsilon-based equality")
    func epsilonEquality() {
        let a = CurvePoint(0.5, 0.5)
        let b = CurvePoint(0.50005, 0.49995)
        #expect(a == b)
    }

    @Test("Equality detects significant differences")
    func equalityDifference() {
        let a = CurvePoint(0.5, 0.5)
        let b = CurvePoint(0.6, 0.5)
        #expect(a != b)
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let point = CurvePoint(0.25, 0.75)
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(CurvePoint.self, from: data)
        #expect(decoded == point)
    }
}

// MARK: - CurveData Tests

@Suite("CurveData Tests")
struct CurveDataTests {

    @Test("identity is a straight diagonal")
    func identity() {
        let curve = CurveData.identity
        #expect(curve.isIdentity)
        #expect(curve.pointCount == 2)
        #expect(abs(curve.points[0].x - 0.0) < 0.0001)
        #expect(abs(curve.points[0].y - 0.0) < 0.0001)
        #expect(abs(curve.points[1].x - 1.0) < 0.0001)
        #expect(abs(curve.points[1].y - 1.0) < 0.0001)
    }

    @Test("isIdentity returns false for non-identity curve")
    func isIdentityFalse() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.8),
            CurvePoint(1.0, 1.0),
        ])
        #expect(!curve.isIdentity)
    }

    @Test("canAddPoint returns true when under limit")
    func canAddPoint() {
        let curve = CurveData.identity
        #expect(curve.canAddPoint)
    }

    @Test("canAddPoint returns false at 16 points")
    func canAddPointAtLimit() {
        let points = (0..<16).map { i in
            CurvePoint(Double(i) / 15.0, Double(i) / 15.0)
        }
        let curve = CurveData(points: points)
        #expect(!curve.canAddPoint)
    }

    @Test("addPoint adds and sorts correctly")
    func addPoint() {
        let curve = CurveData.identity
        let result = curve.addPoint(CurvePoint(0.5, 0.7))

        #expect(result != nil)
        #expect(result!.pointCount == 3)
        #expect(abs(result!.points[1].x - 0.5) < 0.0001)
        #expect(abs(result!.points[1].y - 0.7) < 0.0001)
    }

    @Test("addPoint returns nil when at limit")
    func addPointAtLimit() {
        let points = (0..<16).map { i in
            CurvePoint(Double(i) / 15.0, Double(i) / 15.0)
        }
        let curve = CurveData(points: points)
        let result = curve.addPoint(CurvePoint(0.5, 0.5))
        #expect(result == nil)
    }

    @Test("removePointAt removes interior points")
    func removePoint() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        let result = curve.removePointAt(1)
        #expect(result != nil)
        #expect(result!.pointCount == 2)
    }

    @Test("removePointAt cannot remove first point")
    func removeFirstPoint() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        let result = curve.removePointAt(0)
        #expect(result == nil)
    }

    @Test("removePointAt cannot remove last point")
    func removeLastPoint() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        let result = curve.removePointAt(2)
        #expect(result == nil)
    }

    @Test("removePointAt cannot reduce below 2 points")
    func removePointMinimum() {
        let curve = CurveData.identity // 2 points
        let result = curve.removePointAt(0)
        #expect(result == nil)
    }

    @Test("movePoint clamps Y to valid range")
    func movePointClampsY() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        let moved = curve.movePoint(1, newX: 0.5, newY: 1.5)
        #expect(abs(moved.points[1].y - 1.0) < 0.0001)

        let movedNeg = curve.movePoint(1, newX: 0.5, newY: -0.5)
        #expect(abs(movedNeg.points[1].y - 0.0) < 0.0001)
    }

    @Test("movePoint locks endpoints X values")
    func movePointEndpoints() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        let movedFirst = curve.movePoint(0, newX: 0.5, newY: 0.3)
        #expect(abs(movedFirst.points[0].x - 0.0) < 0.0001) // X locked

        let movedLast = curve.movePoint(2, newX: 0.5, newY: 0.7)
        #expect(abs(movedLast.points[2].x - 1.0) < 0.0001) // X locked
    }

    @Test("movePoint constrains X between neighbors")
    func movePointConstrainX() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        // Try to move middle point past right neighbor
        let moved = curve.movePoint(1, newX: 1.5, newY: 0.5)
        #expect(moved.points[1].x < 1.0)
    }

    @Test("evaluate returns input for identity curve")
    func evaluateIdentity() {
        let curve = CurveData.identity
        #expect(abs(curve.evaluate(0.0) - 0.0) < 0.001)
        #expect(abs(curve.evaluate(0.5) - 0.5) < 0.001)
        #expect(abs(curve.evaluate(1.0) - 1.0) < 0.001)
    }

    @Test("evaluate clamps input to 0-1 range")
    func evaluateClamp() {
        let curve = CurveData.identity
        #expect(abs(curve.evaluate(-0.5) - 0.0) < 0.001)
        #expect(abs(curve.evaluate(1.5) - 1.0) < 0.001)
    }

    @Test("evaluate with 3+ points uses monotone cubic interpolation")
    func evaluateCubic() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.8),
            CurvePoint(1.0, 1.0),
        ])
        let midVal = curve.evaluate(0.5)
        #expect(abs(midVal - 0.8) < 0.001) // should hit control point

        // Values between points should be smoothly interpolated
        let quarterVal = curve.evaluate(0.25)
        #expect(quarterVal > 0.0 && quarterVal < 0.8)
    }

    @Test("evaluate returns endpoint values at boundaries")
    func evaluateBoundaries() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.1),
            CurvePoint(1.0, 0.9),
        ])
        #expect(abs(curve.evaluate(0.0) - 0.1) < 0.001)
        #expect(abs(curve.evaluate(1.0) - 0.9) < 0.001)
    }

    @Test("sample returns correct number of samples")
    func sample() {
        let curve = CurveData.identity
        let samples = curve.sample(10)
        #expect(samples.count == 10)
        #expect(abs(samples[0] - 0.0) < 0.001)
        #expect(abs(samples[9] - 1.0) < 0.001)
    }

    @Test("lerp between identities returns identity")
    func lerpIdentities() {
        let result = CurveData.lerp(.identity, .identity, t: 0.5)
        #expect(result.isIdentity)
    }

    @Test("lerp at t=0 returns first curve")
    func lerpZero() {
        let a = CurveData.identity
        let b = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.8),
            CurvePoint(1.0, 1.0),
        ])
        let result = CurveData.lerp(a, b, t: 0.0)
        #expect(result.pointCount == a.pointCount)
    }

    @Test("lerp at t=1 returns second curve")
    func lerpOne() {
        let a = CurveData.identity
        let b = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.8),
            CurvePoint(1.0, 1.0),
        ])
        let result = CurveData.lerp(a, b, t: 1.0)
        #expect(result.pointCount == b.pointCount)
    }

    @Test("lerp with matching point count interpolates per-point")
    func lerpMatchingCount() {
        let a = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        let b = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.8),
            CurvePoint(1.0, 1.0),
        ])
        let result = CurveData.lerp(a, b, t: 0.5)
        #expect(result.pointCount == 3)
        #expect(abs(result.points[1].y - 0.65) < 0.001) // midpoint between 0.5 and 0.8
    }

    @Test("lerp with different point count samples at 17 points")
    func lerpDifferentCount() {
        let a = CurveData.identity
        let b = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.3, 0.5),
            CurvePoint(0.7, 0.5),
            CurvePoint(1.0, 1.0),
        ])
        let result = CurveData.lerp(a, b, t: 0.5)
        #expect(result.pointCount == 17) // sampled
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.3, 0.5),
            CurvePoint(0.7, 0.8),
            CurvePoint(1.0, 1.0),
        ])
        let data = try JSONEncoder().encode(curve)
        let decoded = try JSONDecoder().decode(CurveData.self, from: data)

        #expect(decoded.pointCount == curve.pointCount)
        for i in 0..<curve.pointCount {
            #expect(decoded.points[i] == curve.points[i])
        }
    }
}

// MARK: - LUTReference Tests

@Suite("LUTReference Tests")
struct LUTReferenceTests {

    @Test("Creation with all fields")
    func creation() {
        let lut = LUTReference(
            id: "lut1",
            name: "Cinematic LUT",
            lutAssetPath: "bundled://cinematic/lut01",
            source: .bundled,
            dimension: 33,
            intensity: 0.8,
            category: "cinematic",
            thumbnailPath: "/path/to/thumb.png"
        )

        #expect(lut.id == "lut1")
        #expect(lut.name == "Cinematic LUT")
        #expect(lut.lutAssetPath == "bundled://cinematic/lut01")
        #expect(lut.source == .bundled)
        #expect(lut.dimension == 33)
        #expect(lut.intensity == 0.8)
        #expect(lut.category == "cinematic")
        #expect(lut.thumbnailPath == "/path/to/thumb.png")
        #expect(lut.isBundled)
        #expect(!lut.isCustom)
    }

    @Test("Default values for optional parameters")
    func defaults() {
        let lut = LUTReference(
            id: "lut1",
            name: "Test",
            lutAssetPath: "test://path",
            source: .custom
        )

        #expect(lut.dimension == 33)
        #expect(lut.intensity == 1.0)
        #expect(lut.category == nil)
        #expect(lut.thumbnailPath == nil)
        #expect(!lut.isBundled)
        #expect(lut.isCustom)
    }

    @Test("Equatable is identity-based on id")
    func equatable() {
        let a = LUTReference(id: "lut1", name: "A", lutAssetPath: "p1", source: .bundled)
        let b = LUTReference(id: "lut1", name: "B", lutAssetPath: "p2", source: .custom)
        let c = LUTReference(id: "lut2", name: "A", lutAssetPath: "p1", source: .bundled)

        #expect(a == b) // same id
        #expect(a != c) // different id
    }

    @Test("Hashable is identity-based on id")
    func hashable() {
        let a = LUTReference(id: "lut1", name: "A", lutAssetPath: "p1", source: .bundled)
        let b = LUTReference(id: "lut1", name: "B", lutAssetPath: "p2", source: .custom)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("with() creates copy with overridden fields")
    func withCopy() {
        let lut = LUTReference(
            id: "lut1",
            name: "Original",
            lutAssetPath: "test://path",
            source: .bundled,
            intensity: 0.5
        )
        let updated = lut.with(name: "Updated", intensity: 0.9)

        #expect(updated.id == "lut1") // unchanged
        #expect(updated.name == "Updated")
        #expect(updated.intensity == 0.9)
        #expect(updated.source == .bundled) // unchanged
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let lut = LUTReference(
            id: "lut1",
            name: "Test LUT",
            lutAssetPath: "bundled://test/lut",
            source: .bundled,
            dimension: 65,
            intensity: 0.7,
            category: "vintage"
        )
        let data = try JSONEncoder().encode(lut)
        let decoded = try JSONDecoder().decode(LUTReference.self, from: data)

        // id-based equality
        #expect(decoded == lut)
        #expect(decoded.name == lut.name)
        #expect(decoded.dimension == lut.dimension)
    }

    @Test("LUTSource CaseIterable")
    func lutSourceCaseIterable() {
        let cases = LUTSource.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.bundled))
        #expect(cases.contains(.custom))
    }
}

// MARK: - ColorGrade Tests

@Suite("ColorGrade Tests")
struct ColorGradeTests {

    private static let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeGrade(
        id: String = "grade1",
        exposure: Double = 0.0,
        brightness: Double = 0.0,
        contrast: Double = 0.0,
        saturation: Double = 0.0
    ) -> ColorGrade {
        ColorGrade(
            id: id,
            exposure: exposure,
            brightness: brightness,
            contrast: contrast,
            saturation: saturation,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
    }

    @Test("Default creation is identity")
    func defaultCreation() {
        let grade = makeGrade()
        #expect(grade.isIdentity)
        #expect(grade.isEnabled)
    }

    @Test("isIdentity returns false for non-zero parameters")
    func isIdentityFalse() {
        let grade = makeGrade(exposure: 0.5)
        #expect(!grade.isIdentity)
    }

    @Test("isIdentity checks LUT filter")
    func isIdentityWithLUT() {
        let lut = LUTReference(id: "l1", name: "T", lutAssetPath: "p", source: .bundled)
        let grade = ColorGrade(
            id: "g1",
            lutFilter: lut,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        #expect(!grade.isIdentity)
    }

    @Test("isIdentity checks HSL shadows")
    func isIdentityWithHSL() {
        let hsl = HSLAdjustment(hue: 30.0, saturation: 0.0, luminance: 0.0)
        let grade = ColorGrade(
            id: "g1",
            hslShadows: hsl,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        #expect(!grade.isIdentity)
    }

    @Test("isIdentity checks curves")
    func isIdentityWithCurves() {
        let curve = CurveData(points: [
            CurvePoint(0.0, 0.0),
            CurvePoint(0.5, 0.8),
            CurvePoint(1.0, 1.0),
        ])
        let grade = ColorGrade(
            id: "g1",
            curveLuminance: curve,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        #expect(!grade.isIdentity)
    }

    @Test("isIdentity checks vignette")
    func isIdentityWithVignette() {
        let grade = ColorGrade(
            id: "g1",
            vignetteIntensity: 0.5,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        #expect(!grade.isIdentity)
    }

    @Test("withParam updates named parameter")
    func withParam() {
        let grade = makeGrade()
        let updated = grade.withParam("exposure", value: 1.5)
        #expect(abs(updated.exposure - 1.5) < 0.0001)
        #expect(abs(updated.brightness - 0.0) < 0.0001) // unchanged
    }

    @Test("withParam handles all known parameter names")
    func withParamAllNames() {
        let grade = makeGrade()
        let params = [
            "exposure", "brightness", "contrast", "saturation", "vibrance",
            "temperature", "tint", "highlights", "shadows", "whites", "blacks",
            "sharpness", "clarity", "hue", "vignetteIntensity", "vignetteRadius",
            "vignetteSoftness",
        ]

        for param in params {
            let updated = grade.withParam(param, value: 0.42)
            // Verify it didn't crash and returned a grade
            #expect(updated.id == grade.id)
        }
    }

    @Test("withParam returns self for unknown name")
    func withParamUnknown() {
        let grade = makeGrade(exposure: 0.5)
        let result = grade.withParam("nonexistent", value: 1.0)
        // Should return self unchanged - equality is by id, but exposure should match
        #expect(result.exposure == 0.5)
    }

    @Test("lerp at t=0 returns first grade parameters")
    func lerpZero() {
        let a = makeGrade(exposure: 1.0, contrast: 0.5)
        let b = makeGrade(id: "grade2", exposure: -1.0, contrast: -0.5)
        let result = ColorGrade.lerp(a, b, t: 0.0)

        #expect(abs(result.exposure - 1.0) < 0.0001)
        #expect(abs(result.contrast - 0.5) < 0.0001)
    }

    @Test("lerp at t=1 returns second grade parameters")
    func lerpOne() {
        let a = makeGrade(exposure: 1.0, contrast: 0.5)
        let b = makeGrade(id: "grade2", exposure: -1.0, contrast: -0.5)
        let result = ColorGrade.lerp(a, b, t: 1.0)

        #expect(abs(result.exposure - (-1.0)) < 0.0001)
        #expect(abs(result.contrast - (-0.5)) < 0.0001)
    }

    @Test("lerp at t=0.5 returns midpoint")
    func lerpHalf() {
        let a = makeGrade(exposure: 0.0, brightness: 0.0)
        let b = makeGrade(id: "grade2", exposure: 2.0, brightness: 1.0)
        let result = ColorGrade.lerp(a, b, t: 0.5)

        #expect(abs(result.exposure - 1.0) < 0.0001)
        #expect(abs(result.brightness - 0.5) < 0.0001)
    }

    @Test("lerp clamps t to 0-1 range")
    func lerpClamp() {
        let a = makeGrade(exposure: 0.0)
        let b = makeGrade(id: "grade2", exposure: 2.0)

        let resultUnder = ColorGrade.lerp(a, b, t: -0.5)
        #expect(abs(resultUnder.exposure - 0.0) < 0.0001)

        let resultOver = ColorGrade.lerp(a, b, t: 1.5)
        #expect(abs(resultOver.exposure - 2.0) < 0.0001)
    }

    @Test("lerp selects LUT based on t threshold")
    func lerpLUT() {
        let lutA = LUTReference(id: "lA", name: "A", lutAssetPath: "pA", source: .bundled)
        let lutB = LUTReference(id: "lB", name: "B", lutAssetPath: "pB", source: .bundled)

        let a = ColorGrade(
            id: "g1",
            lutFilter: lutA,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        let b = ColorGrade(
            id: "g2",
            lutFilter: lutB,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )

        let beforeHalf = ColorGrade.lerp(a, b, t: 0.3)
        #expect(beforeHalf.lutFilter?.id == "lA")

        let afterHalf = ColorGrade.lerp(a, b, t: 0.7)
        #expect(afterHalf.lutFilter?.id == "lB")
    }

    @Test("lerp uses second grade's id")
    func lerpUsesSecondId() {
        let a = makeGrade(id: "gradeA")
        let b = makeGrade(id: "gradeB")
        let result = ColorGrade.lerp(a, b, t: 0.5)
        #expect(result.id == "gradeB")
    }

    @Test("with() creates copy with updated fields")
    func withCopy() {
        let grade = makeGrade(exposure: 0.5, contrast: 0.3)
        let updated = grade.with(exposure: 1.0, brightness: 0.2)

        #expect(updated.exposure == 1.0)
        #expect(updated.brightness == 0.2)
        #expect(updated.contrast == 0.3) // unchanged
    }

    @Test("with() clearLut removes LUT filter")
    func withClearLut() {
        let lut = LUTReference(id: "l1", name: "T", lutAssetPath: "p", source: .bundled)
        let grade = ColorGrade(
            id: "g1",
            lutFilter: lut,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        #expect(grade.lutFilter != nil)

        let cleared = grade.with(clearLut: true)
        #expect(cleared.lutFilter == nil)
    }

    @Test("Equatable is identity-based on id")
    func equatable() {
        let a = makeGrade(id: "g1", exposure: 0.0)
        let b = makeGrade(id: "g1", exposure: 1.0) // different exposure, same id
        let c = makeGrade(id: "g2", exposure: 0.0)

        #expect(a == b) // same id
        #expect(a != c) // different id
    }

    @Test("Codable roundtrip")
    func codable() throws {
        let grade = ColorGrade(
            id: "grade1",
            exposure: 0.5,
            brightness: -0.1,
            contrast: 0.2,
            saturation: 0.3,
            vibrance: 0.1,
            temperature: -0.2,
            tint: 0.05,
            highlights: -0.1,
            shadows: 0.15,
            whites: 0.1,
            blacks: -0.05,
            sharpness: 0.3,
            clarity: 0.2,
            hue: 10.0,
            hslShadows: HSLAdjustment(hue: 200.0, saturation: 0.2, luminance: -0.05),
            curveLuminance: CurveData(points: [
                CurvePoint(0.0, 0.0),
                CurvePoint(0.5, 0.6),
                CurvePoint(1.0, 1.0),
            ]),
            vignetteIntensity: 0.3,
            vignetteRadius: 0.8,
            vignetteSoftness: 0.6,
            isEnabled: true,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )

        let data = try JSONEncoder().encode(grade)
        let decoded = try JSONDecoder().decode(ColorGrade.self, from: data)

        // id-based equality
        #expect(decoded == grade)
        // Also verify decoded values
        #expect(abs(decoded.exposure - 0.5) < 0.0001)
        #expect(abs(decoded.contrast - 0.2) < 0.0001)
        #expect(abs(decoded.vignetteIntensity - 0.3) < 0.0001)
    }

    @Test("Codable decoding uses defaults for missing optional fields")
    func codableDefaults() throws {
        // Minimal JSON with only required fields
        let json = """
        {
            "id": "test_grade",
            "createdAt": "2026-01-01T00:00:00Z",
            "modifiedAt": "2026-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ColorGrade.self, from: data)

        #expect(decoded.id == "test_grade")
        #expect(decoded.exposure == 0.0)
        #expect(decoded.brightness == 0.0)
        #expect(decoded.isEnabled == true)
        #expect(decoded.hslShadows.isIdentity)
        #expect(decoded.curveLuminance.isIdentity)
    }
}

// MARK: - ColorKeyframe Tests

@Suite("ColorKeyframe Tests")
struct ColorKeyframeTests {

    private static let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeGrade(_ id: String = "g1") -> ColorGrade {
        ColorGrade(
            id: id,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
    }

    @Test("Creation with required fields")
    func creation() {
        let grade = makeGrade()
        let keyframe = ColorKeyframe(
            id: "kf1",
            timestampMicros: 5_000_000,
            grade: grade,
            createdAt: Self.fixedDate
        )

        #expect(keyframe.id == "kf1")
        #expect(keyframe.timestampMicros == 5_000_000)
        #expect(keyframe.interpolation == .linear) // default
        #expect(keyframe.bezierPoints == nil)
    }

    @Test("timeMillis converts correctly")
    func timeMillis() {
        let keyframe = ColorKeyframe(
            id: "kf1",
            timestampMicros: 5_000_000,
            grade: makeGrade(),
            createdAt: Self.fixedDate
        )
        #expect(keyframe.timeMillis == 5000)
    }

    @Test("Custom interpolation type")
    func customInterpolation() {
        let keyframe = ColorKeyframe(
            id: "kf1",
            timestampMicros: 0,
            grade: makeGrade(),
            interpolation: .easeInOut,
            createdAt: Self.fixedDate
        )
        #expect(keyframe.interpolation == .easeInOut)
    }

    @Test("with() creates copy with overridden fields")
    func withCopy() {
        let keyframe = ColorKeyframe(
            id: "kf1",
            timestampMicros: 1_000_000,
            grade: makeGrade(),
            interpolation: .linear,
            createdAt: Self.fixedDate
        )
        let updated = keyframe.with(
            timestampMicros: 2_000_000,
            interpolation: .easeIn
        )

        #expect(updated.id == "kf1") // unchanged
        #expect(updated.timestampMicros == 2_000_000)
        #expect(updated.interpolation == .easeIn)
    }

    @Test("Equatable is identity-based on id")
    func equatable() {
        let grade = makeGrade()
        let a = ColorKeyframe(id: "kf1", timestampMicros: 100, grade: grade, createdAt: Self.fixedDate)
        let b = ColorKeyframe(id: "kf1", timestampMicros: 200, grade: grade, createdAt: Self.fixedDate)
        let c = ColorKeyframe(id: "kf2", timestampMicros: 100, grade: grade, createdAt: Self.fixedDate)

        #expect(a == b) // same id
        #expect(a != c) // different id
    }

    @Test("Hashable is identity-based on id")
    func hashable() {
        let grade = makeGrade()
        let a = ColorKeyframe(id: "kf1", timestampMicros: 100, grade: grade, createdAt: Self.fixedDate)
        let b = ColorKeyframe(id: "kf1", timestampMicros: 200, grade: grade, createdAt: Self.fixedDate)
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - FilterPreset Tests

@Suite("FilterPreset Tests")
struct FilterPresetTests {

    private static let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeGrade(_ id: String = "g1") -> ColorGrade {
        ColorGrade(
            id: id,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
    }

    @Test("Creation with all fields")
    func creation() {
        let grade = makeGrade()
        let preset = FilterPreset(
            id: "preset1",
            name: "My Preset",
            description: "A custom preset",
            grade: grade,
            source: .user,
            category: "custom",
            thumbnailBase64: "base64data",
            createdAt: Self.fixedDate
        )

        #expect(preset.id == "preset1")
        #expect(preset.name == "My Preset")
        #expect(preset.description == "A custom preset")
        #expect(preset.source == .user)
        #expect(preset.category == "custom")
        #expect(preset.thumbnailBase64 == "base64data")
        #expect(preset.isUser)
        #expect(!preset.isBuiltin)
    }

    @Test("Builtin source properties")
    func builtinSource() {
        let preset = FilterPreset(
            id: "p1",
            name: "Built-in",
            grade: makeGrade(),
            source: .builtin,
            createdAt: Self.fixedDate
        )
        #expect(preset.isBuiltin)
        #expect(!preset.isUser)
    }

    @Test("applyWithIntensity at 0.0 returns original")
    func applyIntensityZero() {
        let original = ColorGrade(
            id: "orig",
            exposure: 0.5,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        let presetGrade = ColorGrade(
            id: "preset_g",
            exposure: 2.0,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        let preset = FilterPreset(
            id: "p1",
            name: "P",
            grade: presetGrade,
            source: .builtin,
            createdAt: Self.fixedDate
        )

        let result = preset.applyWithIntensity(original, intensity: 0.0)
        #expect(result.exposure == 0.5) // original value
    }

    @Test("applyWithIntensity at 1.0 returns preset grade with original id")
    func applyIntensityFull() {
        let original = ColorGrade(
            id: "orig",
            exposure: 0.5,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        let presetGrade = ColorGrade(
            id: "preset_g",
            exposure: 2.0,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        let preset = FilterPreset(
            id: "p1",
            name: "P",
            grade: presetGrade,
            source: .builtin,
            createdAt: Self.fixedDate
        )

        let result = preset.applyWithIntensity(original, intensity: 1.0)
        #expect(result.id == "orig") // gets original id
        #expect(abs(result.exposure - 2.0) < 0.0001) // preset exposure
    }

    @Test("applyWithIntensity at 0.5 interpolates")
    func applyIntensityHalf() {
        let original = ColorGrade(
            id: "orig",
            exposure: 0.0,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        let presetGrade = ColorGrade(
            id: "preset_g",
            exposure: 2.0,
            createdAt: Self.fixedDate,
            modifiedAt: Self.fixedDate
        )
        let preset = FilterPreset(
            id: "p1",
            name: "P",
            grade: presetGrade,
            source: .builtin,
            createdAt: Self.fixedDate
        )

        let result = preset.applyWithIntensity(original, intensity: 0.5)
        #expect(abs(result.exposure - 1.0) < 0.0001) // midpoint
    }

    @Test("Equatable is identity-based on id")
    func equatable() {
        let a = FilterPreset(id: "p1", name: "A", grade: makeGrade(), source: .user, createdAt: Self.fixedDate)
        let b = FilterPreset(id: "p1", name: "B", grade: makeGrade(), source: .builtin, createdAt: Self.fixedDate)
        let c = FilterPreset(id: "p2", name: "A", grade: makeGrade(), source: .user, createdAt: Self.fixedDate)

        #expect(a == b) // same id
        #expect(a != c) // different id
    }

    @Test("with() creates copy with overridden fields")
    func withCopy() {
        let preset = FilterPreset(
            id: "p1",
            name: "Original",
            grade: makeGrade(),
            source: .user,
            createdAt: Self.fixedDate
        )
        let updated = preset.with(name: "Updated", category: "new_cat")

        #expect(updated.id == "p1") // unchanged
        #expect(updated.name == "Updated")
        #expect(updated.category == "new_cat")
        #expect(updated.source == .user) // unchanged
    }

    @Test("Codable roundtrip for user preset")
    func codable() throws {
        let preset = FilterPreset(
            id: "p1",
            name: "Test Preset",
            description: "A test",
            grade: makeGrade("pg1"),
            source: .user,
            category: "test",
            createdAt: Self.fixedDate
        )

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(FilterPreset.self, from: data)

        #expect(decoded == preset)
        #expect(decoded.name == "Test Preset")
        #expect(decoded.description == "A test")
        #expect(decoded.source == .user)
    }

    @Test("PresetSource CaseIterable")
    func presetSourceCaseIterable() {
        let cases = PresetSource.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.builtin))
        #expect(cases.contains(.user))
    }
}

// MARK: - BuiltinPresets Tests

@Suite("BuiltinPresets Tests")
struct BuiltinPresetsTests {

    @Test("All returns 15 presets")
    func allPresetsCount() {
        let presets = BuiltinPresets.all
        #expect(presets.count == 15)
    }

    @Test("All presets have unique IDs")
    func uniqueIds() {
        let presets = BuiltinPresets.all
        let ids = Set(presets.map(\.id))
        #expect(ids.count == 15)
    }

    @Test("All presets are builtin source")
    func allBuiltin() {
        for preset in BuiltinPresets.all {
            #expect(preset.source == .builtin)
            #expect(preset.isBuiltin)
        }
    }

    @Test("Vivid preset has correct values")
    func vivid() {
        let preset = BuiltinPresets.vivid
        #expect(preset.id == "builtin_vivid")
        #expect(preset.name == "Vivid")
        #expect(preset.category == "enhance")
        #expect(abs(preset.grade.contrast - 0.2) < 0.0001)
        #expect(abs(preset.grade.saturation - 0.35) < 0.0001)
    }

    @Test("B&W preset fully desaturates")
    func blackAndWhite() {
        let preset = BuiltinPresets.blackAndWhite
        #expect(preset.id == "builtin_bw")
        #expect(abs(preset.grade.saturation - (-1.0)) < 0.0001)
    }

    @Test("Cinematic preset has HSL adjustments")
    func cinematic() {
        let preset = BuiltinPresets.cinematic
        #expect(preset.id == "builtin_cinematic")
        #expect(!preset.grade.hslShadows.isIdentity)
        #expect(!preset.grade.hslHighlights.isIdentity)
        #expect(preset.grade.vignetteIntensity > 0.0)
    }

    @Test("Vintage preset has custom curve")
    func vintage() {
        let preset = BuiltinPresets.vintage
        #expect(preset.id == "builtin_vintage")
        #expect(!preset.grade.curveLuminance.isIdentity)
        #expect(preset.grade.vignetteIntensity > 0.0)
    }

    @Test("All presets have categories")
    func categories() {
        for preset in BuiltinPresets.all {
            #expect(preset.category != nil)
        }
    }

    @Test("All presets have non-empty names")
    func nonEmptyNames() {
        for preset in BuiltinPresets.all {
            #expect(!preset.name.isEmpty)
        }
    }
}
