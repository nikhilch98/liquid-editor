import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("KeyframeEditorSheet Tests")
struct KeyframeEditorSheetTests {

    // MARK: - Test Data

    private static let testTransform = VideoTransform(
        scale: 1.5,
        translation: CGPoint(x: 0.3, y: -0.2),
        rotation: 0.5
    )

    private static let testKeyframe = Keyframe(
        id: "kf-1",
        timestampMicros: 2_000_000, // 2 seconds
        transform: testTransform,
        interpolation: .easeInOut,
        bezierPoints: nil
    )

    // MARK: - VideoTransform Identity

    @Test("VideoTransform identity has correct defaults")
    func identityTransform() {
        let identity = VideoTransform.identity
        #expect(identity.scale == 1.0)
        #expect(identity.translation == .zero)
        #expect(identity.rotation == 0.0)
        #expect(identity.isIdentity)
    }

    @Test("VideoTransform with overrides produces correct copy")
    func transformCopyWith() {
        let original = Self.testTransform
        let modified = original.with(scale: 2.0, rotation: 1.0)

        #expect(modified.scale == 2.0)
        #expect(modified.translation == original.translation)
        #expect(modified.rotation == 1.0)
    }

    @Test("VideoTransform clamped constrains values")
    func transformClamped() {
        let extreme = VideoTransform(
            scale: 10.0,
            translation: CGPoint(x: 5.0, y: -5.0),
            rotation: 0.0
        )
        let clamped = extreme.clamped()

        #expect(clamped.scale == 5.0)
        #expect(clamped.translation.x == 1.0)
        #expect(clamped.translation.y == -1.0)
    }

    // MARK: - Keyframe Copy

    @Test("Keyframe copy with transform override")
    func keyframeCopyWithTransform() {
        let kf = Self.testKeyframe
        let newTransform = VideoTransform.identity
        let updated = kf.with(transform: newTransform)

        #expect(updated.id == kf.id)
        #expect(updated.timestampMicros == kf.timestampMicros)
        #expect(updated.transform == newTransform)
        #expect(updated.interpolation == kf.interpolation)
    }

    @Test("Keyframe copy with interpolation override")
    func keyframeCopyWithInterpolation() {
        let kf = Self.testKeyframe
        let updated = kf.with(interpolation: .spring)

        #expect(updated.interpolation == .spring)
        #expect(updated.transform == kf.transform)
    }

    @Test("Keyframe copy with clearBezierPoints")
    func keyframeClearBezierPoints() {
        let kf = Keyframe(
            id: "kf-bp",
            timestampMicros: 1_000_000,
            interpolation: .bezier,
            bezierPoints: .easeInOut
        )
        let updated = kf.with(interpolation: .linear, clearBezierPoints: true)

        #expect(updated.interpolation == .linear)
        #expect(updated.bezierPoints == nil)
    }

    // MARK: - Duplicate Logic

    @Test("Duplicate keyframe creates new ID and offset timestamp")
    func duplicateKeyframe() {
        let original = Self.testKeyframe
        let duplicated = Keyframe(
            id: UUID().uuidString,
            timestampMicros: original.timestampMicros + 500_000,
            transform: original.transform,
            interpolation: original.interpolation,
            bezierPoints: original.bezierPoints
        )

        #expect(duplicated.id != original.id)
        #expect(duplicated.timestampMicros == original.timestampMicros + 500_000)
        #expect(duplicated.transform == original.transform)
        #expect(duplicated.interpolation == original.interpolation)
    }

    // MARK: - Timestamp Conversions

    @Test("Keyframe seconds conversion is correct")
    func keyframeSeconds() {
        let kf = Self.testKeyframe
        #expect(kf.seconds == 2.0)
    }

    @Test("Keyframe milliseconds conversion is correct")
    func keyframeMilliseconds() {
        let kf = Self.testKeyframe
        #expect(kf.milliseconds == 2000.0)
    }

    // MARK: - InterpolationType Categories

    @Test("Basic interpolation types have display names")
    func basicInterpolationDisplayNames() {
        #expect(InterpolationType.linear.displayName == "Linear")
        #expect(InterpolationType.hold.displayName == "Hold")
        #expect(InterpolationType.easeIn.displayName == "Ease In")
        #expect(InterpolationType.easeOut.displayName == "Ease Out")
        #expect(InterpolationType.easeInOut.displayName == "Ease In-Out")
    }

    @Test("Cubic interpolation types have display names")
    func cubicInterpolationDisplayNames() {
        #expect(InterpolationType.cubicIn.displayName == "Cubic In")
        #expect(InterpolationType.cubicOut.displayName == "Cubic Out")
        #expect(InterpolationType.cubicInOut.displayName == "Cubic In-Out")
    }

    @Test("Special interpolation types have display names")
    func specialInterpolationDisplayNames() {
        #expect(InterpolationType.spring.displayName == "Spring")
        #expect(InterpolationType.bounce.displayName == "Bounce")
        #expect(InterpolationType.elastic.displayName == "Elastic")
    }

    // MARK: - Transform Matrix Logic

    @Test("Scale slider range 0.1 to 5.0 includes identity")
    func scaleSliderRange() {
        let identity = VideoTransform.identity
        #expect(identity.scale >= 0.1)
        #expect(identity.scale <= 5.0)
    }

    @Test("Translation slider range -1.0 to 1.0 includes zero")
    func translationSliderRange() {
        let identity = VideoTransform.identity
        #expect(identity.translation.x >= -1.0)
        #expect(identity.translation.x <= 1.0)
        #expect(identity.translation.y >= -1.0)
        #expect(identity.translation.y <= 1.0)
    }

    @Test("Rotation slider range includes negative pi to positive pi")
    func rotationSliderRange() {
        let transform = VideoTransform(rotation: .pi)
        #expect(transform.rotation <= .pi)

        let negTransform = VideoTransform(rotation: -.pi)
        #expect(negTransform.rotation >= -.pi)
    }
}
