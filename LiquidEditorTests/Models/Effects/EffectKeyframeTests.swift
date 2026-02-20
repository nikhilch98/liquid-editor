import Testing
import Foundation
@testable import LiquidEditor

// MARK: - EffectKeyframe Tests

@Suite("EffectKeyframe Tests")
struct EffectKeyframeTests {

    // MARK: - Creation

    @Test("EffectKeyframe creation with all parameters")
    func fullCreation() {
        let kf = EffectKeyframe(
            id: "kf1",
            timestampMicros: 500_000,
            value: .double_(0.75),
            interpolation: .easeIn,
            bezierPoints: BezierControlPoints.easeInOut
        )
        #expect(kf.id == "kf1")
        #expect(kf.timestampMicros == 500_000)
        #expect(kf.value == .double_(0.75))
        #expect(kf.interpolation == .easeIn)
        #expect(kf.bezierPoints != nil)
    }

    @Test("EffectKeyframe default interpolation is easeInOut")
    func defaultInterpolation() {
        let kf = EffectKeyframe(
            id: "kf1",
            timestampMicros: 0,
            value: .double_(1.0)
        )
        #expect(kf.interpolation == .easeInOut)
        #expect(kf.bezierPoints == nil)
    }

    // MARK: - with() Copy

    @Test("with() updates timestampMicros while preserving other fields")
    func withTimestamp() {
        let original = EffectKeyframe(
            id: "kf1",
            timestampMicros: 100_000,
            value: .double_(0.5),
            interpolation: .linear
        )
        let updated = original.with(timestampMicros: 200_000)
        #expect(updated.timestampMicros == 200_000)
        #expect(updated.id == "kf1")
        #expect(updated.value == .double_(0.5))
        #expect(updated.interpolation == .linear)
    }

    @Test("with() updates value")
    func withValue() {
        let original = EffectKeyframe(
            id: "kf1",
            timestampMicros: 0,
            value: .double_(0.0)
        )
        let updated = original.with(value: .double_(1.0))
        #expect(updated.value == .double_(1.0))
    }

    @Test("with() updates interpolation")
    func withInterpolation() {
        let original = EffectKeyframe(
            id: "kf1",
            timestampMicros: 0,
            value: .double_(0.5),
            interpolation: .linear
        )
        let updated = original.with(interpolation: .easeOut)
        #expect(updated.interpolation == .easeOut)
    }

    // MARK: - Equatable

    @Test("Identical keyframes are equal")
    func equality() {
        let kf1 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(1.0), interpolation: .linear)
        let kf2 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(1.0), interpolation: .linear)
        #expect(kf1 == kf2)
    }

    @Test("Keyframes with different IDs are not equal")
    func inequalityId() {
        let kf1 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(1.0))
        let kf2 = EffectKeyframe(id: "b", timestampMicros: 100, value: .double_(1.0))
        #expect(kf1 != kf2)
    }

    @Test("Keyframes with different values are not equal")
    func inequalityValue() {
        let kf1 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(1.0))
        let kf2 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(2.0))
        #expect(kf1 != kf2)
    }

    @Test("Keyframes with different timestamps are not equal")
    func inequalityTimestamp() {
        let kf1 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(1.0))
        let kf2 = EffectKeyframe(id: "a", timestampMicros: 200, value: .double_(1.0))
        #expect(kf1 != kf2)
    }

    // MARK: - Hashable

    @Test("Equal keyframes have same hash")
    func hashConsistency() {
        let kf1 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(1.0), interpolation: .linear)
        let kf2 = EffectKeyframe(id: "a", timestampMicros: 100, value: .double_(1.0), interpolation: .linear)
        #expect(kf1.hashValue == kf2.hashValue)
    }

    // MARK: - Codable Roundtrip

    @Test("EffectKeyframe Codable roundtrip with double value")
    func codableDouble() throws {
        let original = EffectKeyframe(
            id: "kf1",
            timestampMicros: 500_000,
            value: .double_(0.75),
            interpolation: .easeIn
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectKeyframe.self, from: data)
        #expect(decoded == original)
    }

    @Test("EffectKeyframe Codable roundtrip with bool value")
    func codableBool() throws {
        let original = EffectKeyframe(
            id: "kf2",
            timestampMicros: 0,
            value: .bool_(true),
            interpolation: .hold
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectKeyframe.self, from: data)
        #expect(decoded == original)
    }

    @Test("EffectKeyframe Codable roundtrip with color value")
    func codableColor() throws {
        let original = EffectKeyframe(
            id: "kf3",
            timestampMicros: 1_000_000,
            value: .color(0xFFFF0000),
            interpolation: .linear
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectKeyframe.self, from: data)
        #expect(decoded == original)
    }

    @Test("EffectKeyframe Codable roundtrip with point value")
    func codablePoint() throws {
        let original = EffectKeyframe(
            id: "kf4",
            timestampMicros: 250_000,
            value: .point(x: 0.3, y: 0.7),
            interpolation: .easeInOut
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectKeyframe.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - Interpolation Function Tests

@Suite("Effect Interpolation Tests")
struct EffectInterpolationTests {

    // MARK: - Linear Interpolation

    @Test("Linear interpolation at t=0 returns from value")
    func linearAtZero() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(10.0),
            t: 0.0,
            interpolation: .linear
        )
        #expect(result.asDouble == 0.0)
    }

    @Test("Linear interpolation at t=1 returns to value")
    func linearAtOne() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(10.0),
            t: 1.0,
            interpolation: .linear
        )
        #expect(result.asDouble == 10.0)
    }

    @Test("Linear interpolation at t=0.5 returns midpoint")
    func linearAtHalf() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(10.0),
            t: 0.5,
            interpolation: .linear
        )
        #expect(result.asDouble == 5.0)
    }

    @Test("Linear interpolation at t=0.25")
    func linearAtQuarter() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(100.0),
            t: 0.25,
            interpolation: .linear
        )
        #expect(result.asDouble == 25.0)
    }

    // MARK: - EaseIn Interpolation

    @Test("EaseIn at t=0 returns from value")
    func easeInAtZero() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 0.0,
            interpolation: .easeIn
        )
        #expect(result.asDouble == 0.0)
    }

    @Test("EaseIn at t=1 returns to value")
    func easeInAtOne() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 1.0,
            interpolation: .easeIn
        )
        #expect(result.asDouble == 1.0)
    }

    @Test("EaseIn at t=0.5 produces value less than linear midpoint")
    func easeInSlowerThanLinear() {
        let easeResult = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 0.5,
            interpolation: .easeIn
        )
        // easeIn(0.5) = 0.5^2 = 0.25 => interpolated = 0.25
        #expect(easeResult.asDouble! < 0.5)
        let expected = 0.25 // t*t at 0.5
        #expect(abs(easeResult.asDouble! - expected) < 0.001)
    }

    // MARK: - EaseOut Interpolation

    @Test("EaseOut at t=0.5 produces value greater than linear midpoint")
    func easeOutFasterThanLinear() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 0.5,
            interpolation: .easeOut
        )
        // easeOut(0.5) = 0.5 * (2.0 - 0.5) = 0.75
        #expect(result.asDouble! > 0.5)
        let expected = 0.75
        #expect(abs(result.asDouble! - expected) < 0.001)
    }

    // MARK: - EaseInOut Interpolation

    @Test("EaseInOut at t=0.5 returns midpoint")
    func easeInOutAtHalf() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 0.5,
            interpolation: .easeInOut
        )
        // easeInOut(0.5) = 2*0.25 = 0.5
        #expect(abs(result.asDouble! - 0.5) < 0.001)
    }

    @Test("EaseInOut at t=0.25 is slower than linear")
    func easeInOutFirstHalf() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 0.25,
            interpolation: .easeInOut
        )
        // First half uses easeIn curve, so value < 0.25
        #expect(result.asDouble! < 0.25)
    }

    // MARK: - Hold Interpolation

    @Test("Hold interpolation returns from value until t=1")
    func holdBeforeEnd() {
        let result = interpolateEffectValue(
            from: .double_(10.0),
            to: .double_(20.0),
            t: 0.5,
            interpolation: .hold
        )
        // hold returns 0.0 as eased t, so interpolated = from + (to - from) * 0 = from
        #expect(result.asDouble == 10.0)
    }

    @Test("Hold interpolation returns from value at t=0.99")
    func holdNearEnd() {
        let result = interpolateEffectValue(
            from: .double_(10.0),
            to: .double_(20.0),
            t: 0.99,
            interpolation: .hold
        )
        #expect(result.asDouble == 10.0)
    }

    // MARK: - CubicIn Interpolation

    @Test("CubicIn at t=0.5 returns correct value")
    func cubicInAtHalf() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 0.5,
            interpolation: .cubicIn
        )
        // cubicIn(0.5) = 0.125
        #expect(abs(result.asDouble! - 0.125) < 0.001)
    }

    // MARK: - CubicOut Interpolation

    @Test("CubicOut at t=0.5 returns correct value")
    func cubicOutAtHalf() {
        let result = interpolateEffectValue(
            from: .double_(0.0),
            to: .double_(1.0),
            t: 0.5,
            interpolation: .cubicOut
        )
        // cubicOut(0.5) = 1 - (0.5)^3 = 0.875
        #expect(abs(result.asDouble! - 0.875) < 0.001)
    }

    // MARK: - Point Interpolation

    @Test("Point values are interpolated component-wise")
    func pointInterpolation() {
        let result = interpolateEffectValue(
            from: .point(x: 0.0, y: 0.0),
            to: .point(x: 1.0, y: 1.0),
            t: 0.5,
            interpolation: .linear
        )
        let point = result.asPoint
        #expect(point != nil)
        #expect(abs(point!.x - 0.5) < 0.001)
        #expect(abs(point!.y - 0.5) < 0.001)
    }

    @Test("Point interpolation at t=0 returns from point")
    func pointAtZero() {
        let result = interpolateEffectValue(
            from: .point(x: 0.2, y: 0.3),
            to: .point(x: 0.8, y: 0.9),
            t: 0.0,
            interpolation: .linear
        )
        let point = result.asPoint
        #expect(abs(point!.x - 0.2) < 0.001)
        #expect(abs(point!.y - 0.3) < 0.001)
    }

    // MARK: - Range Interpolation

    @Test("Range values are interpolated component-wise")
    func rangeInterpolation() {
        let result = interpolateEffectValue(
            from: .range(start: 0.0, end: 0.5),
            to: .range(start: 0.5, end: 1.0),
            t: 0.5,
            interpolation: .linear
        )
        let range = result.asRange
        #expect(range != nil)
        #expect(abs(range!.start - 0.25) < 0.001)
        #expect(abs(range!.end - 0.75) < 0.001)
    }

    // MARK: - Color Interpolation

    @Test("Color interpolation between black and white at midpoint")
    func colorInterpolation() {
        let black = 0xFF000000 // ARGB black
        let white = 0xFFFFFFFF // ARGB white
        let result = interpolateEffectValue(
            from: .color(black),
            to: .color(white),
            t: 0.5,
            interpolation: .linear
        )
        let colorInt = result.asColorInt
        #expect(colorInt != nil)
        // Mid-grey should be approximately 0xFF808080
        let r = (colorInt! >> 16) & 0xFF
        let g = (colorInt! >> 8) & 0xFF
        let b = colorInt! & 0xFF
        #expect(abs(r - 128) <= 1)
        #expect(abs(g - 128) <= 1)
        #expect(abs(b - 128) <= 1)
    }

    // MARK: - Type Mismatch

    @Test("Mismatched types use hold behavior: returns from value before t=1")
    func typeMismatchHold() {
        let result = interpolateEffectValue(
            from: .double_(5.0),
            to: .bool_(true),
            t: 0.5,
            interpolation: .linear
        )
        // Non-interpolatable types: returns fromValue when t < 1
        #expect(result == .double_(5.0))
    }

    @Test("Mismatched types return to value at t=1")
    func typeMismatchAtEnd() {
        let result = interpolateEffectValue(
            from: .double_(5.0),
            to: .bool_(true),
            t: 1.0,
            interpolation: .linear
        )
        #expect(result == .bool_(true))
    }

    @Test("Bool values use hold interpolation")
    func boolHoldInterpolation() {
        let result = interpolateEffectValue(
            from: .bool_(false),
            to: .bool_(true),
            t: 0.5,
            interpolation: .linear
        )
        #expect(result == .bool_(false))
    }
}

// MARK: - resolveKeyframedValue Tests

@Suite("resolveKeyframedValue Tests")
struct ResolveKeyframedValueTests {

    @Test("Empty keyframes returns static value")
    func emptyKeyframes() {
        let result = resolveKeyframedValue(
            keyframes: [],
            clipTimeMicros: 500_000,
            staticValue: .double_(0.5)
        )
        #expect(result == .double_(0.5))
    }

    @Test("Single keyframe at exact time returns its value")
    func singleKeyframeExact() {
        let kf = EffectKeyframe(id: "1", timestampMicros: 500_000, value: .double_(0.8))
        let result = resolveKeyframedValue(
            keyframes: [kf],
            clipTimeMicros: 500_000,
            staticValue: .double_(0.0)
        )
        #expect(result == .double_(0.8))
    }

    @Test("Time before first keyframe returns first keyframe value")
    func beforeFirstKeyframe() {
        let kf = EffectKeyframe(id: "1", timestampMicros: 500_000, value: .double_(0.8))
        let result = resolveKeyframedValue(
            keyframes: [kf],
            clipTimeMicros: 100_000,
            staticValue: .double_(0.0)
        )
        #expect(result == .double_(0.8))
    }

    @Test("Time after last keyframe returns last keyframe value")
    func afterLastKeyframe() {
        let kf = EffectKeyframe(id: "1", timestampMicros: 500_000, value: .double_(0.8))
        let result = resolveKeyframedValue(
            keyframes: [kf],
            clipTimeMicros: 1_000_000,
            staticValue: .double_(0.0)
        )
        #expect(result == .double_(0.8))
    }

    @Test("Interpolation between two keyframes at midpoint")
    func twoKeyframesMidpoint() {
        let kf1 = EffectKeyframe(id: "1", timestampMicros: 0, value: .double_(0.0), interpolation: .linear)
        let kf2 = EffectKeyframe(id: "2", timestampMicros: 1_000_000, value: .double_(1.0))
        let result = resolveKeyframedValue(
            keyframes: [kf1, kf2],
            clipTimeMicros: 500_000,
            staticValue: .double_(0.0)
        )
        #expect(abs(result.asDouble! - 0.5) < 0.001)
    }

    @Test("Interpolation between two keyframes at quarter point")
    func twoKeyframesQuarter() {
        let kf1 = EffectKeyframe(id: "1", timestampMicros: 0, value: .double_(0.0), interpolation: .linear)
        let kf2 = EffectKeyframe(id: "2", timestampMicros: 1_000_000, value: .double_(100.0))
        let result = resolveKeyframedValue(
            keyframes: [kf1, kf2],
            clipTimeMicros: 250_000,
            staticValue: .double_(0.0)
        )
        #expect(abs(result.asDouble! - 25.0) < 0.01)
    }

    @Test("Three keyframes, time in second segment")
    func threeKeyframes() {
        let kf1 = EffectKeyframe(id: "1", timestampMicros: 0, value: .double_(0.0), interpolation: .linear)
        let kf2 = EffectKeyframe(id: "2", timestampMicros: 500_000, value: .double_(1.0), interpolation: .linear)
        let kf3 = EffectKeyframe(id: "3", timestampMicros: 1_000_000, value: .double_(0.0))
        let result = resolveKeyframedValue(
            keyframes: [kf1, kf2, kf3],
            clipTimeMicros: 750_000, // midpoint between kf2 and kf3
            staticValue: .double_(0.0)
        )
        #expect(abs(result.asDouble! - 0.5) < 0.001)
    }

    @Test("Keyframes at same timestamp returns last-in-array value")
    func sameTimestamp() {
        let kf1 = EffectKeyframe(id: "1", timestampMicros: 500_000, value: .double_(1.0))
        let kf2 = EffectKeyframe(id: "2", timestampMicros: 500_000, value: .double_(2.0))
        let result = resolveKeyframedValue(
            keyframes: [kf1, kf2],
            clipTimeMicros: 500_000,
            staticValue: .double_(0.0)
        )
        // When multiple keyframes share the same timestamp, the loop overwrites `before`
        // with each successive keyframe, so the last one in array order wins
        #expect(result == .double_(2.0))
    }
}
