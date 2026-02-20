import Testing
import Foundation
@testable import LiquidEditor

@Suite("AudioFade Tests")
struct AudioFadeTests {

    // MARK: - Creation

    @Test("Default fade in has 500ms duration and S-curve")
    func defaultFadeIn() {
        let fade = AudioFade.defaultFadeIn
        #expect(fade.durationMicros == 500_000)
        #expect(fade.curveType == .sCurve)
        #expect(fade.durationSeconds == 0.5)
    }

    @Test("Default fade out has 500ms duration and S-curve")
    func defaultFadeOut() {
        let fade = AudioFade.defaultFadeOut
        #expect(fade.durationMicros == 500_000)
        #expect(fade.curveType == .sCurve)
    }

    @Test("Custom init stores values correctly")
    func customInit() {
        let fade = AudioFade(durationMicros: 1_000_000, curveType: .exponential)
        #expect(fade.durationMicros == 1_000_000)
        #expect(fade.curveType == .exponential)
        #expect(fade.durationSeconds == 1.0)
    }

    @Test("Default curve type is S-curve when not specified")
    func defaultCurveType() {
        let fade = AudioFade(durationMicros: 250_000)
        #expect(fade.curveType == .sCurve)
    }

    @Test("Duration in seconds conversion")
    func durationConversion() {
        let fade = AudioFade(durationMicros: 2_500_000)
        #expect(fade.durationSeconds == 2.5)
    }

    // MARK: - Static Constants

    @Test("Min and max duration constants")
    func durationConstants() {
        #expect(AudioFade.minDurationMicros == 66_666)
        #expect(AudioFade.maxDurationMicros == 10_000_000)
    }

    // MARK: - gainAtNormalized - All Curve Types

    @Test("All curve types return 0 at t=0",
          arguments: FadeCurveType.allCases)
    func allCurvesStartAtZero(curveType: FadeCurveType) {
        let fade = AudioFade(durationMicros: 500_000, curveType: curveType)
        let gain = fade.gainAtNormalized(0.0)
        #expect(gain == 0.0, "Curve \(curveType) should return 0.0 at t=0, got \(gain)")
    }

    @Test("All curve types return 1 at t=1",
          arguments: FadeCurveType.allCases)
    func allCurvesEndAtOne(curveType: FadeCurveType) {
        let fade = AudioFade(durationMicros: 500_000, curveType: curveType)
        let gain = fade.gainAtNormalized(1.0)
        #expect(abs(gain - 1.0) < 1e-10, "Curve \(curveType) should return 1.0 at t=1, got \(gain)")
    }

    @Test("All curve types produce values in [0, 1] range",
          arguments: FadeCurveType.allCases)
    func allCurvesInRange(curveType: FadeCurveType) {
        let fade = AudioFade(durationMicros: 500_000, curveType: curveType)
        for i in 0...100 {
            let t = Double(i) / 100.0
            let gain = fade.gainAtNormalized(t)
            #expect(gain >= 0.0, "Curve \(curveType) at t=\(t): gain \(gain) < 0")
            #expect(gain <= 1.0, "Curve \(curveType) at t=\(t): gain \(gain) > 1")
        }
    }

    @Test("Linear curve returns t directly")
    func linearCurve() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(fade.gainAtNormalized(0.0) == 0.0)
        #expect(fade.gainAtNormalized(0.25) == 0.25)
        #expect(fade.gainAtNormalized(0.5) == 0.5)
        #expect(fade.gainAtNormalized(0.75) == 0.75)
        #expect(fade.gainAtNormalized(1.0) == 1.0)
    }

    @Test("Logarithmic curve returns sqrt(t)")
    func logarithmicCurve() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .logarithmic)
        #expect(abs(fade.gainAtNormalized(0.25) - 0.5) < 1e-10)
        #expect(abs(fade.gainAtNormalized(1.0) - 1.0) < 1e-10)
    }

    @Test("S-curve uses Hermite formula 3t^2 - 2t^3")
    func sCurve() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .sCurve)
        let t = 0.5
        let expected = 3.0 * t * t - 2.0 * t * t * t // 0.5
        #expect(abs(fade.gainAtNormalized(0.5) - expected) < 1e-10)
    }

    @Test("Equal power curve returns sin(t * pi/2)")
    func equalPowerCurve() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .equalPower)
        let expected = sin(0.5 * .pi / 2)
        #expect(abs(fade.gainAtNormalized(0.5) - expected) < 1e-10)
    }

    @Test("Exponential curve returns t^2")
    func exponentialCurve() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .exponential)
        #expect(abs(fade.gainAtNormalized(0.5) - 0.25) < 1e-10)
        #expect(abs(fade.gainAtNormalized(0.3) - 0.09) < 1e-10)
    }

    // MARK: - Input Clamping

    @Test("gainAtNormalized clamps negative input to 0")
    func clampNegative() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(fade.gainAtNormalized(-0.5) == 0.0)
        #expect(fade.gainAtNormalized(-100.0) == 0.0)
    }

    @Test("gainAtNormalized clamps input above 1 to 1")
    func clampAboveOne() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(fade.gainAtNormalized(1.5) == 1.0)
        #expect(fade.gainAtNormalized(100.0) == 1.0)
    }

    // MARK: - fadeOutGainAtNormalized

    @Test("Fade out returns 1 at t=0 (full volume)")
    func fadeOutAtStart() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(fade.fadeOutGainAtNormalized(0.0) == 1.0)
    }

    @Test("Fade out returns 0 at t=1 (silent)")
    func fadeOutAtEnd() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(fade.fadeOutGainAtNormalized(1.0) == 0.0)
    }

    @Test("Fade out linear at t=0.5 returns 0.5")
    func fadeOutMidpoint() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(abs(fade.fadeOutGainAtNormalized(0.5) - 0.5) < 1e-10)
    }

    @Test("Fade out clamps out-of-range input")
    func fadeOutClamping() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(fade.fadeOutGainAtNormalized(-1.0) == 1.0)
        #expect(fade.fadeOutGainAtNormalized(2.0) == 0.0)
    }

    // MARK: - with() Copy Method

    @Test("with() creates copy preserving unchanged fields")
    func withPreservesFields() {
        let original = AudioFade(durationMicros: 500_000, curveType: .sCurve)
        let copy = original.with(durationMicros: 1_000_000)
        #expect(copy.durationMicros == 1_000_000)
        #expect(copy.curveType == .sCurve) // Preserved
    }

    @Test("with() can change curve type")
    func withCurveType() {
        let original = AudioFade(durationMicros: 500_000, curveType: .linear)
        let copy = original.with(curveType: .exponential)
        #expect(copy.durationMicros == 500_000) // Preserved
        #expect(copy.curveType == .exponential)
    }

    @Test("with() can change all fields")
    func withAllFields() {
        let original = AudioFade(durationMicros: 500_000, curveType: .linear)
        let copy = original.with(durationMicros: 2_000_000, curveType: .equalPower)
        #expect(copy.durationMicros == 2_000_000)
        #expect(copy.curveType == .equalPower)
    }

    @Test("with() with no arguments returns equal copy")
    func withNoArgs() {
        let original = AudioFade(durationMicros: 500_000, curveType: .sCurve)
        let copy = original.with()
        #expect(copy == original)
    }

    // MARK: - Equatable

    @Test("Equal fades are equal")
    func equality() {
        let a = AudioFade(durationMicros: 500_000, curveType: .sCurve)
        let b = AudioFade(durationMicros: 500_000, curveType: .sCurve)
        #expect(a == b)
    }

    @Test("Different fades are not equal")
    func inequality() {
        let a = AudioFade(durationMicros: 500_000, curveType: .sCurve)
        let b = AudioFade(durationMicros: 500_000, curveType: .linear)
        #expect(a != b)

        let c = AudioFade(durationMicros: 1_000_000, curveType: .sCurve)
        #expect(a != c)
    }

    // MARK: - Codable Roundtrip

    @Test("Codable roundtrip preserves all fields",
          arguments: FadeCurveType.allCases)
    func codableRoundtrip(curveType: FadeCurveType) throws {
        let original = AudioFade(durationMicros: 750_000, curveType: curveType)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioFade.self, from: data)
        #expect(decoded == original)
        #expect(decoded.durationMicros == 750_000)
        #expect(decoded.curveType == curveType)
    }

    // MARK: - FadeCurveType Display Names

    @Test("All fade curve types have non-empty display names",
          arguments: FadeCurveType.allCases)
    func displayNames(curveType: FadeCurveType) {
        #expect(!curveType.displayName.isEmpty)
    }
}
