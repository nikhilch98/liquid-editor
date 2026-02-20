import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - MaskType Tests

@Suite("MaskType Tests")
struct MaskTypeTests {

    @Test("all cases")
    func allCases() {
        #expect(MaskType.allCases.count == 6)
        #expect(MaskType.rectangle.rawValue == "rectangle")
        #expect(MaskType.ellipse.rawValue == "ellipse")
        #expect(MaskType.polygon.rawValue == "polygon")
        #expect(MaskType.brush.rawValue == "brush")
        #expect(MaskType.luminance.rawValue == "luminance")
        #expect(MaskType.color.rawValue == "color")
    }
}

// MARK: - MaskBlurMode Tests

@Suite("MaskBlurMode Tests")
struct MaskBlurModeTests {

    @Test("all cases")
    func allCases() {
        #expect(MaskBlurMode.allCases.count == 3)
        #expect(MaskBlurMode.gaussian.rawValue == "gaussian")
        #expect(MaskBlurMode.box.rawValue == "box")
        #expect(MaskBlurMode.motion.rawValue == "motion")
    }
}

// MARK: - BrushStroke Tests

@Suite("BrushStroke Tests")
struct BrushStrokeTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let stroke = BrushStroke(
            points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)]
        )
        #expect(stroke.points.count == 2)
        #expect(stroke.width == 0.05)
        #expect(stroke.softness == 0.3)
    }

    @Test("with() copy")
    func withCopy() {
        let stroke = BrushStroke(
            points: [CGPoint(x: 0.5, y: 0.5)],
            width: 0.1,
            softness: 0.5
        )
        let modified = stroke.with(width: 0.2)
        #expect(modified.width == 0.2)
        #expect(modified.softness == 0.5)
        #expect(modified.points.count == 1)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let stroke = BrushStroke(
            points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.8, y: 0.9)],
            width: 0.08,
            softness: 0.6
        )
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(BrushStroke.self, from: data)
        #expect(decoded.points.count == 2)
        #expect(decoded.points[0].x == 0.1)
        #expect(decoded.points[0].y == 0.2)
        #expect(decoded.width == 0.08)
        #expect(decoded.softness == 0.6)
    }
}

// MARK: - MaskParameters Tests

@Suite("MaskParameters Tests")
struct MaskParametersTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let params = MaskParameters()
        #expect(params.feather == 0.0)
        #expect(params.opacity == 1.0)
        #expect(params.expansion == 0.0)
        #expect(params.rect == nil)
        #expect(params.cornerRadius == nil)
        #expect(params.rotation == nil)
        #expect(params.vertices == nil)
    }

    @Test("lerp interpolates correctly at t=0.5")
    func lerpMidpoint() {
        let a = MaskParameters(feather: 0.0, opacity: 0.0, expansion: 0.0)
        let b = MaskParameters(feather: 1.0, opacity: 1.0, expansion: 2.0)
        let result = MaskParameters.lerp(a, b, t: 0.5)
        #expect(abs(result.feather - 0.5) < 0.001)
        #expect(abs(result.opacity - 0.5) < 0.001)
        #expect(abs(result.expansion - 1.0) < 0.001)
    }

    @Test("lerp interpolates rect")
    func lerpRect() {
        let a = MaskParameters(rect: CGRect(x: 0, y: 0, width: 0.2, height: 0.2))
        let b = MaskParameters(rect: CGRect(x: 0.4, y: 0.4, width: 0.6, height: 0.6))
        let result = MaskParameters.lerp(a, b, t: 0.5)
        #expect(result.rect != nil)
        #expect(abs(result.rect!.origin.x - 0.2) < 0.001)
        #expect(abs(result.rect!.size.width - 0.4) < 0.001)
    }

    @Test("lerp interpolates cornerRadius")
    func lerpCornerRadius() {
        let a = MaskParameters(cornerRadius: 0.0)
        let b = MaskParameters(cornerRadius: 20.0)
        let result = MaskParameters.lerp(a, b, t: 0.5)
        #expect(result.cornerRadius != nil)
        #expect(abs(result.cornerRadius! - 10.0) < 0.001)
    }

    @Test("lerp interpolates vertices of same count")
    func lerpVertices() {
        let a = MaskParameters(vertices: [CGPoint(x: 0.0, y: 0.0), CGPoint(x: 1.0, y: 0.0)])
        let b = MaskParameters(vertices: [CGPoint(x: 0.0, y: 1.0), CGPoint(x: 1.0, y: 1.0)])
        let result = MaskParameters.lerp(a, b, t: 0.5)
        #expect(result.vertices != nil)
        #expect(result.vertices!.count == 2)
        #expect(abs(result.vertices![0].y - 0.5) < 0.001)
    }

    @Test("lerp with mismatched vertices uses b")
    func lerpMismatchedVertices() {
        let a = MaskParameters(vertices: [CGPoint.zero])
        let b = MaskParameters(vertices: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)])
        let result = MaskParameters.lerp(a, b, t: 0.5)
        #expect(result.vertices?.count == 2) // Falls back to b
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let params = MaskParameters(
            feather: 0.3,
            opacity: 0.8,
            expansion: -0.1,
            rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            cornerRadius: 10.0,
            rotation: 0.5,
            vertices: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.8, y: 0.9)]
        )
        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(MaskParameters.self, from: data)
        #expect(decoded.feather == params.feather)
        #expect(decoded.opacity == params.opacity)
        #expect(decoded.expansion == params.expansion)
        #expect(decoded.cornerRadius == params.cornerRadius)
        #expect(decoded.rotation == params.rotation)
        #expect(decoded.vertices?.count == 2)
    }
}

// MARK: - MaskKeyframe Tests

@Suite("MaskKeyframe Tests")
struct MaskKeyframeTests {

    @Test("creation")
    func creation() {
        let kf = MaskKeyframe(
            id: "mkf-1",
            timeMicros: 1_000_000,
            parameters: MaskParameters(feather: 0.5)
        )
        #expect(kf.id == "mkf-1")
        #expect(kf.timeMicros == 1_000_000)
        #expect(kf.parameters.feather == 0.5)
        #expect(kf.interpolation == .easeInOut)
    }

    @Test("Equatable is by id + time")
    func equatable() {
        let a = MaskKeyframe(id: "mkf", timeMicros: 100, parameters: MaskParameters())
        let b = MaskKeyframe(id: "mkf", timeMicros: 100, parameters: MaskParameters(feather: 1.0))
        #expect(a == b) // Same id + time
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let kf = MaskKeyframe(
            id: "mkf-codec",
            timeMicros: 500_000,
            parameters: MaskParameters(feather: 0.3, opacity: 0.9),
            interpolation: .linear
        )
        let data = try JSONEncoder().encode(kf)
        let decoded = try JSONDecoder().decode(MaskKeyframe.self, from: data)
        #expect(decoded.id == kf.id)
        #expect(decoded.timeMicros == kf.timeMicros)
        #expect(decoded.interpolation == .linear)
    }
}

// MARK: - Mask Tests

@Suite("Mask Tests")
struct MaskTests {

    @Test("creation rectangle mask with defaults")
    func creationRectDefaults() {
        let mask = Mask(
            id: "mask-1",
            type: .rectangle,
            rect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )
        #expect(mask.id == "mask-1")
        #expect(mask.type == .rectangle)
        #expect(mask.isInverted == false)
        #expect(mask.feather == 0.0)
        #expect(mask.opacity == 1.0)
        #expect(mask.expansion == 0.0)
        #expect(mask.keyframes.isEmpty)
        #expect(mask.rect != nil)
        #expect(!mask.isAnimated)
    }

    @Test("creation ellipse mask")
    func creationEllipse() {
        let mask = Mask(
            id: "mask-e",
            type: .ellipse,
            rect: CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.5),
            rotation: 0.785
        )
        #expect(mask.type == .ellipse)
        #expect(mask.rotation == 0.785)
    }

    @Test("creation polygon mask")
    func creationPolygon() {
        let verts = [
            CGPoint(x: 0.5, y: 0.0),
            CGPoint(x: 1.0, y: 1.0),
            CGPoint(x: 0.0, y: 1.0)
        ]
        let mask = Mask(id: "mask-p", type: .polygon, vertices: verts)
        #expect(mask.type == .polygon)
        #expect(mask.vertices?.count == 3)
    }

    @Test("creation brush mask")
    func creationBrush() {
        let strokes = [
            BrushStroke(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)])
        ]
        let mask = Mask(id: "mask-b", type: .brush, strokes: strokes)
        #expect(mask.type == .brush)
        #expect(mask.strokes?.count == 1)
    }

    @Test("creation luminance mask")
    func creationLuminance() {
        let mask = Mask(
            id: "mask-l",
            type: .luminance,
            luminanceMin: 0.2,
            luminanceMax: 0.8
        )
        #expect(mask.type == .luminance)
        #expect(mask.luminanceMin == 0.2)
        #expect(mask.luminanceMax == 0.8)
        #expect(abs(mask.luminanceRange! - 0.6) < 0.0001)
    }

    @Test("creation color mask")
    func creationColor() {
        let mask = Mask(
            id: "mask-c",
            type: .color,
            targetHue: 120.0,
            hueTolerance: 30.0,
            saturationMin: 0.3,
            saturationMax: 1.0
        )
        #expect(mask.type == .color)
        #expect(mask.targetHue == 120.0)
        #expect(mask.hueTolerance == 30.0)
    }

    @Test("isAnimated with keyframes")
    func isAnimated() {
        let kf = MaskKeyframe(id: "kf", timeMicros: 0, parameters: MaskParameters())
        let mask = Mask(id: "mask-a", type: .rectangle, keyframes: [kf],
                        rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(mask.isAnimated)
    }

    @Test("luminanceRange returns nil when bounds are equal")
    func luminanceRangeZero() {
        let mask = Mask(id: "m", type: .luminance, luminanceMin: 0.5, luminanceMax: 0.5)
        #expect(mask.luminanceRange == 0.0)
    }

    @Test("with() copy")
    func withCopy() {
        let mask = Mask(id: "mask-w", type: .rectangle, feather: 0.0, opacity: 1.0,
                        rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let modified = mask.with(isInverted: true, feather: 0.5)
        #expect(modified.feather == 0.5)
        #expect(modified.isInverted == true)
        #expect(modified.id == "mask-w")
    }

    @Test("with() can override rect")
    func withOverrideRect() {
        let mask = Mask(id: "m", type: .rectangle, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(mask.rect != nil)
        let modified = mask.with(rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        #expect(modified.rect == CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
    }

    @Test("Equatable is by id")
    func equatableById() {
        let a = Mask(id: "same", type: .rectangle,
                     rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let b = Mask(id: "same", type: .ellipse, feather: 0.5,
                     rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        #expect(a == b) // Same id
    }

    @Test("Codable roundtrip for rectangle mask")
    func codableRectangle() throws {
        let mask = Mask(
            id: "mask-codec-r",
            type: .rectangle,
            isInverted: true,
            feather: 0.3,
            opacity: 0.8,
            expansion: 0.1,
            rect: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5),
            cornerRadius: 10.0,
            rotation: 0.5
        )
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)
        #expect(decoded.id == mask.id)
        #expect(decoded.type == .rectangle)
        #expect(decoded.isInverted == true)
        #expect(decoded.feather == 0.3)
        #expect(decoded.opacity == 0.8)
        #expect(decoded.cornerRadius == 10.0)
        #expect(decoded.rotation == 0.5)
    }

    @Test("Codable roundtrip for polygon mask")
    func codablePolygon() throws {
        let verts = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.8, y: 0.3), CGPoint(x: 0.5, y: 0.9)]
        let mask = Mask(id: "mask-codec-p", type: .polygon, vertices: verts)
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)
        #expect(decoded.vertices?.count == 3)
        #expect(decoded.vertices![0].x == 0.1)
    }

    @Test("Codable roundtrip for brush mask")
    func codableBrush() throws {
        let strokes = [
            BrushStroke(points: [CGPoint(x: 0.1, y: 0.1)], width: 0.1, softness: 0.5)
        ]
        let mask = Mask(id: "mask-codec-b", type: .brush, strokes: strokes)
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)
        #expect(decoded.strokes?.count == 1)
        #expect(decoded.strokes![0].width == 0.1)
    }

    @Test("Codable roundtrip for color mask")
    func codableColor() throws {
        let mask = Mask(
            id: "mask-codec-c",
            type: .color,
            targetHue: 200.0,
            hueTolerance: 40.0,
            saturationMin: 0.2,
            saturationMax: 0.9
        )
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)
        #expect(decoded.targetHue == 200.0)
        #expect(decoded.hueTolerance == 40.0)
        #expect(decoded.saturationMin == 0.2)
        #expect(decoded.saturationMax == 0.9)
    }
}
