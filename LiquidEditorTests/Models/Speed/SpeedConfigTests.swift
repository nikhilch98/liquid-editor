import Testing
import Foundation
@testable import LiquidEditor

// MARK: - FrameBlendMode Tests

@Suite("FrameBlendMode Tests")
struct FrameBlendModeTests {

    @Test("All 3 blend modes exist")
    func allCases() {
        #expect(FrameBlendMode.allCases.count == 3)
    }

    @Test("Raw values are correct")
    func rawValues() {
        #expect(FrameBlendMode.none.rawValue == "none")
        #expect(FrameBlendMode.blend.rawValue == "blend")
        #expect(FrameBlendMode.opticalFlow.rawValue == "opticalFlow")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for mode in FrameBlendMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(FrameBlendMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}

// MARK: - SpeedKeyframe Tests

@Suite("SpeedKeyframe Tests")
struct SpeedKeyframeTests {

    @Test("SpeedKeyframe creation with valid values")
    func validCreation() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 2.0)
        #expect(kf.id == "sk1")
        #expect(kf.timeMicros == 0)
        #expect(kf.speedMultiplier == 2.0)
        #expect(kf.interpolation == .easeInOut)
    }

    @Test("SpeedKeyframe creation with custom interpolation")
    func customInterpolation() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 500_000, speedMultiplier: 0.5, interpolation: .linear)
        #expect(kf.interpolation == .linear)
    }

    @Test("SpeedKeyframe minimum speed 0.1")
    func minimumSpeed() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 0.1)
        #expect(kf.speedMultiplier == 0.1)
    }

    @Test("SpeedKeyframe maximum speed 16.0")
    func maximumSpeed() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 16.0)
        #expect(kf.speedMultiplier == 16.0)
    }

    @Test("SpeedKeyframe with() updates speedMultiplier")
    func withSpeedMultiplier() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 1.0)
        let updated = kf.with(speedMultiplier: 3.0)
        #expect(updated.speedMultiplier == 3.0)
        #expect(updated.id == "sk1")
    }

    @Test("SpeedKeyframe with() updates timeMicros")
    func withTimeMicros() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 1.0)
        let updated = kf.with(timeMicros: 500_000)
        #expect(updated.timeMicros == 500_000)
    }

    @Test("SpeedKeyframe Codable roundtrip")
    func codableRoundtrip() throws {
        let original = SpeedKeyframe(
            id: "sk1",
            timeMicros: 1_000_000,
            speedMultiplier: 2.5,
            interpolation: .cubicIn
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeedKeyframe.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.timeMicros == original.timeMicros)
        #expect(decoded.speedMultiplier == original.speedMultiplier)
        #expect(decoded.interpolation == .cubicIn)
    }

    @Test("SpeedKeyframe Equatable")
    func equality() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 100, speedMultiplier: 1.0)
        let kf2 = SpeedKeyframe(id: "a", timeMicros: 100, speedMultiplier: 1.0)
        #expect(kf1 == kf2)
    }
}

// MARK: - SpeedConfig Tests

@Suite("SpeedConfig Tests")
struct SpeedConfigTests {

    // MARK: - Default Config

    @Test("Default config is 1x speed, not reverse, not ramped")
    func defaultConfig() {
        let config = SpeedConfig()
        #expect(config.speedMultiplier == 1.0)
        #expect(config.isReverse == false)
        #expect(config.maintainPitch == true)
        #expect(config.blendMode == .none)
        #expect(config.rampKeyframes.isEmpty)
    }

    @Test("normal static property returns default config")
    func normalConfig() {
        let config = SpeedConfig.normal
        #expect(config.isDefault)
    }

    @Test("isDefault returns true for normal config")
    func isDefaultTrue() {
        let config = SpeedConfig()
        #expect(config.isDefault)
    }

    @Test("isDefault returns false when speed differs")
    func isDefaultFalseSpeed() {
        let config = SpeedConfig(speedMultiplier: 2.0)
        #expect(!config.isDefault)
    }

    @Test("isDefault returns false when reversed")
    func isDefaultFalseReverse() {
        let config = SpeedConfig(isReverse: true)
        #expect(!config.isDefault)
    }

    @Test("isDefault returns false when has ramp keyframes")
    func isDefaultFalseRamp() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 1.0)
        let config = SpeedConfig(rampKeyframes: [kf])
        #expect(!config.isDefault)
    }

    // MARK: - hasSpeedRamp

    @Test("hasSpeedRamp false when no keyframes")
    func noSpeedRamp() {
        #expect(!SpeedConfig().hasSpeedRamp)
    }

    @Test("hasSpeedRamp true when keyframes present")
    func hasSpeedRamp() {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 1.0)
        let config = SpeedConfig(rampKeyframes: [kf])
        #expect(config.hasSpeedRamp)
    }

    // MARK: - shouldMuteAudio

    @Test("shouldMuteAudio false at 1x speed")
    func muteAtNormalSpeed() {
        #expect(!SpeedConfig().shouldMuteAudio)
    }

    @Test("shouldMuteAudio false at 4x speed")
    func muteAt4x() {
        let config = SpeedConfig(speedMultiplier: 4.0)
        #expect(!config.shouldMuteAudio)
    }

    @Test("shouldMuteAudio true above 4x speed")
    func muteAbove4x() {
        let config = SpeedConfig(speedMultiplier: 4.1)
        #expect(config.shouldMuteAudio)
    }

    @Test("shouldMuteAudio true at 16x speed")
    func muteAt16x() {
        let config = SpeedConfig(speedMultiplier: 16.0)
        #expect(config.shouldMuteAudio)
    }

    // MARK: - effectiveDurationMicros (Constant Speed)

    @Test("effectiveDuration at 1x returns source duration")
    func effectiveDurationNormal() {
        let config = SpeedConfig()
        let source: TimeMicros = 10_000_000 // 10s
        #expect(config.effectiveDurationMicros(source) == 10_000_000)
    }

    @Test("effectiveDuration at 2x returns half duration")
    func effectiveDuration2x() {
        let config = SpeedConfig(speedMultiplier: 2.0)
        let source: TimeMicros = 10_000_000 // 10s
        #expect(config.effectiveDurationMicros(source) == 5_000_000)
    }

    @Test("effectiveDuration at 0.5x returns double duration")
    func effectiveDurationHalf() {
        let config = SpeedConfig(speedMultiplier: 0.5)
        let source: TimeMicros = 10_000_000 // 10s
        #expect(config.effectiveDurationMicros(source) == 20_000_000)
    }

    @Test("effectiveDuration at 0.25x returns 4x duration")
    func effectiveDurationQuarter() {
        let config = SpeedConfig(speedMultiplier: 0.25)
        let source: TimeMicros = 10_000_000 // 10s
        #expect(config.effectiveDurationMicros(source) == 40_000_000)
    }

    @Test("effectiveDuration at 4x returns quarter duration")
    func effectiveDuration4x() {
        let config = SpeedConfig(speedMultiplier: 4.0)
        let source: TimeMicros = 12_000_000 // 12s
        #expect(config.effectiveDurationMicros(source) == 3_000_000)
    }

    @Test("effectiveDuration at 10x")
    func effectiveDuration10x() {
        let config = SpeedConfig(speedMultiplier: 10.0)
        let source: TimeMicros = 10_000_000 // 10s
        #expect(config.effectiveDurationMicros(source) == 1_000_000)
    }

    // MARK: - effectiveDurationMicros (Speed Ramp)

    @Test("Constant speed ramp matches non-ramp behavior")
    func rampConstantSpeed() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 0, speedMultiplier: 2.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 10_000_000, speedMultiplier: 2.0)
        let config = SpeedConfig(speedMultiplier: 2.0, rampKeyframes: [kf1, kf2])
        let source: TimeMicros = 10_000_000

        let rampDuration = config.effectiveDurationMicros(source)
        let constantDuration = SpeedConfig(speedMultiplier: 2.0).effectiveDurationMicros(source)

        // Should be approximately equal (numerical integration vs exact)
        let tolerance: TimeMicros = 20_000 // 20ms tolerance for integration error
        #expect(abs(rampDuration - constantDuration) < tolerance)
    }

    @Test("Speed ramp from 1x to 2x produces shorter output than 1x")
    func rampFrom1xTo2x() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 0, speedMultiplier: 1.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 10_000_000, speedMultiplier: 2.0)
        let config = SpeedConfig(speedMultiplier: 1.0, rampKeyframes: [kf1, kf2])
        let source: TimeMicros = 10_000_000

        let rampDuration = config.effectiveDurationMicros(source)
        let normalDuration = SpeedConfig().effectiveDurationMicros(source) // 10s

        #expect(rampDuration < normalDuration)
        #expect(rampDuration > 0)
    }

    @Test("Speed ramp from 2x to 0.5x produces specific output range")
    func rampFrom2xToHalf() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 0, speedMultiplier: 2.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 10_000_000, speedMultiplier: 0.5)
        let config = SpeedConfig(speedMultiplier: 2.0, rampKeyframes: [kf1, kf2])
        let source: TimeMicros = 10_000_000

        let rampDuration = config.effectiveDurationMicros(source)
        // Average speed is between 0.5 and 2.0, so duration should be between 5s and 20s
        #expect(rampDuration > 5_000_000)
        #expect(rampDuration < 20_000_000)
    }

    // MARK: - speedAtTime

    @Test("speedAtTime without ramp returns constant speed")
    func speedAtTimeConstant() {
        let config = SpeedConfig(speedMultiplier: 2.5)
        #expect(config.speedAtTime(0) == 2.5)
        #expect(config.speedAtTime(5_000_000) == 2.5)
    }

    @Test("speedAtTime at first keyframe returns its speed")
    func speedAtTimeFirstKeyframe() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 0, speedMultiplier: 1.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 1_000_000, speedMultiplier: 4.0)
        let config = SpeedConfig(rampKeyframes: [kf1, kf2])
        #expect(config.speedAtTime(0) == 1.0)
    }

    @Test("speedAtTime at last keyframe returns its speed")
    func speedAtTimeLastKeyframe() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 0, speedMultiplier: 1.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 1_000_000, speedMultiplier: 4.0)
        let config = SpeedConfig(rampKeyframes: [kf1, kf2])
        #expect(config.speedAtTime(1_000_000) == 4.0)
    }

    @Test("speedAtTime before first keyframe returns first keyframe speed")
    func speedAtTimeBeforeFirst() {
        let kf = SpeedKeyframe(id: "a", timeMicros: 500_000, speedMultiplier: 2.0)
        let config = SpeedConfig(rampKeyframes: [kf])
        #expect(config.speedAtTime(0) == 2.0)
    }

    @Test("speedAtTime after last keyframe returns last keyframe speed")
    func speedAtTimeAfterLast() {
        let kf = SpeedKeyframe(id: "a", timeMicros: 500_000, speedMultiplier: 2.0)
        let config = SpeedConfig(rampKeyframes: [kf])
        #expect(config.speedAtTime(1_000_000) == 2.0)
    }

    @Test("speedAtTime at midpoint of linear ramp")
    func speedAtTimeMidpoint() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 0, speedMultiplier: 1.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 1_000_000, speedMultiplier: 3.0)
        let config = SpeedConfig(rampKeyframes: [kf1, kf2])
        let speed = config.speedAtTime(500_000)
        #expect(abs(speed - 2.0) < 0.001)
    }

    @Test("speedAtTime at quarter point of linear ramp")
    func speedAtTimeQuarter() {
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 0, speedMultiplier: 1.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 1_000_000, speedMultiplier: 5.0)
        let config = SpeedConfig(rampKeyframes: [kf1, kf2])
        let speed = config.speedAtTime(250_000)
        #expect(abs(speed - 2.0) < 0.001)
    }

    // MARK: - clampSpeed

    @Test("clampSpeed within range returns same value")
    func clampSpeedInRange() {
        #expect(SpeedConfig.clampSpeed(1.0) == 1.0)
        #expect(SpeedConfig.clampSpeed(5.0) == 5.0)
    }

    @Test("clampSpeed below min clamps to 0.1")
    func clampSpeedBelowMin() {
        #expect(SpeedConfig.clampSpeed(0.05) == 0.1)
        #expect(SpeedConfig.clampSpeed(-1.0) == 0.1)
        #expect(SpeedConfig.clampSpeed(0.0) == 0.1)
    }

    @Test("clampSpeed above max clamps to 16.0")
    func clampSpeedAboveMax() {
        #expect(SpeedConfig.clampSpeed(20.0) == 16.0)
        #expect(SpeedConfig.clampSpeed(100.0) == 16.0)
    }

    @Test("clampSpeed at boundaries returns boundary values")
    func clampSpeedBoundaries() {
        #expect(SpeedConfig.clampSpeed(0.1) == 0.1)
        #expect(SpeedConfig.clampSpeed(16.0) == 16.0)
    }

    // MARK: - with() Copy

    @Test("with() updates speedMultiplier")
    func withSpeed() {
        let config = SpeedConfig()
        let updated = config.with(speedMultiplier: 3.0)
        #expect(updated.speedMultiplier == 3.0)
        #expect(updated.isReverse == false)
        #expect(updated.maintainPitch == true)
    }

    @Test("with() updates isReverse")
    func withReverse() {
        let config = SpeedConfig()
        let updated = config.with(isReverse: true)
        #expect(updated.isReverse == true)
        #expect(updated.speedMultiplier == 1.0)
    }

    @Test("with() updates maintainPitch")
    func withMaintainPitch() {
        let config = SpeedConfig()
        let updated = config.with(maintainPitch: false)
        #expect(updated.maintainPitch == false)
    }

    @Test("with() updates blendMode")
    func withBlendMode() {
        let config = SpeedConfig()
        let updated = config.with(blendMode: .opticalFlow)
        #expect(updated.blendMode == .opticalFlow)
    }

    @Test("with() updates rampKeyframes")
    func withRampKeyframes() {
        let config = SpeedConfig()
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 0, speedMultiplier: 2.0)
        let updated = config.with(rampKeyframes: [kf])
        #expect(updated.rampKeyframes.count == 1)
        #expect(updated.hasSpeedRamp)
    }

    // MARK: - Codable

    @Test("SpeedConfig Codable roundtrip with defaults")
    func codableDefault() throws {
        let original = SpeedConfig()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeedConfig.self, from: data)
        #expect(decoded.speedMultiplier == 1.0)
        #expect(decoded.isReverse == false)
        #expect(decoded.maintainPitch == true)
        #expect(decoded.blendMode == .none)
        #expect(decoded.rampKeyframes.isEmpty)
    }

    @Test("SpeedConfig Codable roundtrip with custom values")
    func codableCustom() throws {
        let kf = SpeedKeyframe(id: "sk1", timeMicros: 500_000, speedMultiplier: 3.0, interpolation: .linear)
        let original = SpeedConfig(
            speedMultiplier: 2.0,
            isReverse: true,
            maintainPitch: false,
            blendMode: .opticalFlow,
            rampKeyframes: [kf]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeedConfig.self, from: data)
        #expect(decoded.speedMultiplier == 2.0)
        #expect(decoded.isReverse == true)
        #expect(decoded.maintainPitch == false)
        #expect(decoded.blendMode == .opticalFlow)
        #expect(decoded.rampKeyframes.count == 1)
        #expect(decoded.rampKeyframes[0].speedMultiplier == 3.0)
    }

    @Test("SpeedConfig decoding with missing fields uses defaults")
    func codableMissingFields() throws {
        // Minimal JSON with no fields
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SpeedConfig.self, from: data)
        #expect(decoded.speedMultiplier == 1.0)
        #expect(decoded.isReverse == false)
        #expect(decoded.maintainPitch == true)
        #expect(decoded.blendMode == .none)
        #expect(decoded.rampKeyframes.isEmpty)
    }

    // MARK: - Static Constants

    @Test("minSpeed is 0.1")
    func minSpeed() {
        #expect(SpeedConfig.minSpeed == 0.1)
    }

    @Test("maxSpeed is 16.0")
    func maxSpeed() {
        #expect(SpeedConfig.maxSpeed == 16.0)
    }

    // MARK: - Edge Cases

    @Test("effectiveDuration at minimum speed 0.1x")
    func effectiveDurationMinSpeed() {
        let config = SpeedConfig(speedMultiplier: 0.1)
        let source: TimeMicros = 1_000_000 // 1s
        let result = config.effectiveDurationMicros(source)
        #expect(result == 10_000_000) // 10s
    }

    @Test("effectiveDuration at maximum speed 16x")
    func effectiveDurationMaxSpeed() {
        let config = SpeedConfig(speedMultiplier: 16.0)
        let source: TimeMicros = 16_000_000 // 16s
        let result = config.effectiveDurationMicros(source)
        #expect(result == 1_000_000) // 1s
    }

    @Test("Multiple speed keyframes are sorted before interpolation")
    func multipleRampKeyframes() {
        // Deliberately unsorted
        let kf1 = SpeedKeyframe(id: "a", timeMicros: 1_000_000, speedMultiplier: 4.0)
        let kf2 = SpeedKeyframe(id: "b", timeMicros: 0, speedMultiplier: 1.0)
        let kf3 = SpeedKeyframe(id: "c", timeMicros: 2_000_000, speedMultiplier: 1.0)
        let config = SpeedConfig(rampKeyframes: [kf1, kf2, kf3])

        // At time 0, speed should be 1.0 (first keyframe when sorted)
        #expect(config.speedAtTime(0) == 1.0)
        // At time 1_000_000, speed should be 4.0
        #expect(config.speedAtTime(1_000_000) == 4.0)
        // At time 2_000_000, speed should be 1.0
        #expect(config.speedAtTime(2_000_000) == 1.0)
    }
}
