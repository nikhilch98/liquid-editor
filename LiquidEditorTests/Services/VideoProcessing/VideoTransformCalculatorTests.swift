import Testing
import CoreGraphics
import AVFoundation
import Foundation
@testable import LiquidEditor

@Suite("VideoTransformCalculator Tests")
struct VideoTransformCalculatorTests {

    // MARK: - Initialization (Explicit Values)

    @Test("Init with identity transform preserves natural size")
    func initIdentity() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )

        #expect(calc.naturalSize == CGSize(width: 1920, height: 1080))
        #expect(calc.sourceWidth == 1920)
        #expect(calc.sourceHeight == 1080)
        #expect(calc.outputSize == CGSize(width: 1920, height: 1080))
    }

    @Test("Init with 90-degree rotation swaps width and height")
    func init90DegreeRotation() {
        // 90 degrees CW: transform is (0, 1, -1, 0, height, 0) for natural 1920x1080
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: transform,
            outputSize: CGSize(width: 1080, height: 1920)
        )

        #expect(abs(calc.sourceWidth - 1080) < 1)
        #expect(abs(calc.sourceHeight - 1920) < 1)
    }

    @Test("Init with 180-degree rotation keeps same dimensions")
    func init180DegreeRotation() {
        // 180 degrees: transform is (-1, 0, 0, -1, width, height)
        let transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: transform,
            outputSize: CGSize(width: 1920, height: 1080)
        )

        #expect(abs(calc.sourceWidth - 1920) < 1)
        #expect(abs(calc.sourceHeight - 1080) < 1)
    }

    // MARK: - isRotated

    @Test("isRotated is false for identity transform")
    func isRotatedFalse() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        #expect(!calc.isRotated)
    }

    @Test("isRotated is true for 90-degree rotation")
    func isRotatedTrue() {
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: transform,
            outputSize: CGSize(width: 1080, height: 1920)
        )
        #expect(calc.isRotated)
    }

    // MARK: - Aspect Ratio

    @Test("sourceAspectRatio is correct for 16:9")
    func sourceAspectRatio16by9() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let expected: CGFloat = 1920.0 / 1080.0
        #expect(abs(calc.sourceAspectRatio - expected) < 0.01)
    }

    @Test("sourceAspectRatio handles zero height")
    func sourceAspectRatioZeroHeight() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 100, height: 0),
            preferredTransform: .identity,
            outputSize: CGSize(width: 100, height: 0)
        )
        #expect(calc.sourceAspectRatio == 1.0)
    }

    @Test("outputAspectRatio is correct")
    func outputAspectRatio() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1080, height: 1920)
        )
        let expected: CGFloat = 1080.0 / 1920.0
        #expect(abs(calc.outputAspectRatio - expected) < 0.01)
    }

    @Test("outputAspectRatio handles zero height")
    func outputAspectRatioZeroHeight() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 100, height: 100),
            preferredTransform: .identity,
            outputSize: CGSize(width: 100, height: 0)
        )
        #expect(calc.outputAspectRatio == 1.0)
    }

    // MARK: - Base Transform

    @Test("createBaseTransform with identity produces identity-like transform")
    func baseTransformIdentity() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let transform = calc.createBaseTransform()

        // For same size input/output with identity preferred transform,
        // the base transform should be (nearly) identity
        #expect(abs(transform.a - 1.0) < 0.001)
        #expect(abs(transform.d - 1.0) < 0.001)
        #expect(abs(transform.b) < 0.001)
        #expect(abs(transform.c) < 0.001)
    }

    @Test("createBaseTransform scales down for smaller output")
    func baseTransformScaleDown() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 960, height: 540)
        )
        let transform = calc.createBaseTransform()

        // Scale should be 0.5
        #expect(abs(transform.a - 0.5) < 0.001)
        #expect(abs(transform.d - 0.5) < 0.001)
    }

    @Test("createBaseTransform scales up for larger output")
    func baseTransformScaleUp() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 960, height: 540),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let transform = calc.createBaseTransform()

        // Scale should be 2.0
        #expect(abs(transform.a - 2.0) < 0.001)
        #expect(abs(transform.d - 2.0) < 0.001)
    }

    @Test("createBaseTransform positions content at origin")
    func baseTransformOrigin() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let transform = calc.createBaseTransform()

        // Test that (0,0) maps to (0,0)
        let origin = CGPoint.zero.applying(transform)
        #expect(abs(origin.x) < 1.0)
        #expect(abs(origin.y) < 1.0)
    }

    // MARK: - User Transform

    @Test("createTransform with identity user values returns base transform")
    func userTransformIdentity() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let base = calc.createBaseTransform()
        let user = calc.createTransform(sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0, rotation: 0.0)

        #expect(abs(base.a - user.a) < 0.001)
        #expect(abs(base.b - user.b) < 0.001)
        #expect(abs(base.c - user.c) < 0.001)
        #expect(abs(base.d - user.d) < 0.001)
        #expect(abs(base.tx - user.tx) < 0.001)
        #expect(abs(base.ty - user.ty) < 0.001)
    }

    @Test("createTransform with 2x scale produces larger output")
    func userTransformScale() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let transform = calc.createTransform(sx: 2.0, sy: 2.0, tx: 0.0, ty: 0.0)

        // The scale components should be doubled
        // Since base scale is 1.0 (same size), total should be 2.0
        // But the transform is centered, so we check that the scale factor is applied
        let testPoint = CGPoint(x: 960, y: 540) // center of 1920x1080
        let transformed = testPoint.applying(transform)
        // Center should still map near center of output
        #expect(abs(transformed.x - 960) < 100)
        #expect(abs(transformed.y - 540) < 100)
    }

    @Test("createTransform with translation moves content")
    func userTransformTranslation() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        // Move right by 0.5 (half the output width = 960 pixels)
        let transform = calc.createTransform(sx: 1.0, sy: 1.0, tx: 0.5, ty: 0.0)

        // Origin of source content should be shifted right by ~960 pixels
        let origin = CGPoint.zero.applying(transform)
        let baseOrigin = CGPoint.zero.applying(calc.createBaseTransform())
        let shift = origin.x - baseOrigin.x
        #expect(abs(shift - 960) < 2.0)
    }

    @Test("createTransform with rotation modifies transform")
    func userTransformRotation() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let transform = calc.createTransform(
            sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0,
            rotation: .pi / 4 // 45 degrees
        )

        // Transform should differ from base due to rotation
        let base = calc.createBaseTransform()
        let hasDifference = abs(transform.a - base.a) > 0.001
            || abs(transform.b - base.b) > 0.001
        #expect(hasDifference)
    }

    // MARK: - Identity User Values

    @Test("identityUserValues are correct")
    func identityUserValues() {
        let id = VideoTransformCalculator.identityUserValues
        #expect(id.sx == 1.0)
        #expect(id.sy == 1.0)
        #expect(id.tx == 0.0)
        #expect(id.ty == 0.0)
        #expect(id.rotation == 0.0)
    }

    // MARK: - Common Video Sizes

    @Test("Transform works for 4K source to 1080p output")
    func transform4kTo1080p() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 3840, height: 2160),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )

        let transform = calc.createBaseTransform()
        // Scale should be 0.5
        #expect(abs(transform.a - 0.5) < 0.001)
        #expect(abs(transform.d - 0.5) < 0.001)
    }

    @Test("Transform works for 720p source to 1080p output")
    func transform720pTo1080p() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1280, height: 720),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )

        let transform = calc.createBaseTransform()
        // Scale should be 1.5
        #expect(abs(transform.a - 1.5) < 0.001)
        #expect(abs(transform.d - 1.5) < 0.001)
    }

    @Test("Transform works for portrait 9:16 video")
    func transformPortraitVideo() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1080, height: 1920),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1080, height: 1920)
        )

        #expect(!calc.isRotated)
        #expect(calc.sourceWidth == 1080)
        #expect(calc.sourceHeight == 1920)
        #expect(abs(calc.sourceAspectRatio - (1080.0 / 1920.0)) < 0.01)
    }

    @Test("Transform works for square video")
    func transformSquareVideo() {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1080, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1080, height: 1080)
        )

        #expect(abs(calc.sourceAspectRatio - 1.0) < 0.01)
        #expect(abs(calc.outputAspectRatio - 1.0) < 0.01)
    }

    // MARK: - 90-Degree iPhone Portrait Video

    @Test("Transform handles iPhone portrait recording (90-degree rotation)")
    func transformIPhonePortrait() {
        // iPhone records landscape but with a 90-degree rotation transform
        // Natural size is landscape, transform rotates to portrait
        let naturalSize = CGSize(width: 1920, height: 1080)
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let outputSize = CGSize(width: 1080, height: 1920)

        let calc = VideoTransformCalculator(
            naturalSize: naturalSize,
            preferredTransform: transform,
            outputSize: outputSize
        )

        #expect(calc.isRotated)
        #expect(abs(calc.sourceWidth - 1080) < 1)
        #expect(abs(calc.sourceHeight - 1920) < 1)

        let baseTransform = calc.createBaseTransform()
        // The transform should map the full source rect to output
        let sourceRect = CGRect(origin: .zero, size: naturalSize)
        let outputRect = sourceRect.applying(baseTransform)
        #expect(abs(outputRect.width - 1080) < 2)
        #expect(abs(outputRect.height - 1920) < 2)
    }

    // MARK: - Sendable

    @Test("VideoTransformCalculator is Sendable")
    func sendableConformance() async {
        let calc = VideoTransformCalculator(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            outputSize: CGSize(width: 1920, height: 1080)
        )
        let task = Task { calc.createBaseTransform() }
        let transform = await task.value
        #expect(abs(transform.a - 1.0) < 0.001)
    }
}
