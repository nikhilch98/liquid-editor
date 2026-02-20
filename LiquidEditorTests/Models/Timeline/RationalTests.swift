import Testing
import Foundation
import CoreMedia
@testable import LiquidEditor

@Suite("Rational Number Tests")
struct RationalTests {

    // MARK: - Basic Creation

    @Test("Creates rational with numerator and denominator")
    func basicCreation() {
        let r = Rational(30000, 1001)
        #expect(r.numerator == 30000)
        #expect(r.denominator == 1001)
    }

    @Test("Default denominator is 1")
    func defaultDenominator() {
        let r = Rational(30)
        #expect(r.numerator == 30)
        #expect(r.denominator == 1)
    }

    @Test("Value returns floating point")
    func valueComputation() {
        let r = Rational(30000, 1001)
        #expect(abs(r.value - 29.97) < 0.01)
    }

    // MARK: - Frame Rate Constants

    @Test("Standard frame rates have correct values")
    func frameRateConstants() {
        #expect(abs(Rational.fps23_976.value - 23.976) < 0.001)
        #expect(Rational.fps24.value == 24.0)
        #expect(Rational.fps25.value == 25.0)
        #expect(abs(Rational.fps29_97.value - 29.97) < 0.01)
        #expect(Rational.fps30.value == 30.0)
        #expect(Rational.fps60.value == 60.0)
        #expect(Rational.fps120.value == 120.0)
        #expect(Rational.fps240.value == 240.0)
    }

    // MARK: - Arithmetic

    @Test("Addition works correctly")
    func addition() {
        let a = Rational(1, 3)
        let b = Rational(1, 6)
        let sum = a + b
        #expect(sum == Rational(1, 2))
    }

    @Test("Subtraction works correctly")
    func subtraction() {
        let a = Rational(3, 4)
        let b = Rational(1, 4)
        let diff = a - b
        #expect(diff == Rational(1, 2))
    }

    @Test("Multiplication works correctly")
    func multiplication() {
        let a = Rational(2, 3)
        let b = Rational(3, 4)
        let product = a * b
        #expect(product == Rational(1, 2))
    }

    @Test("Division works correctly")
    func division() {
        let a = Rational(1, 2)
        let b = Rational(3, 4)
        let quotient = a / b
        #expect(quotient == Rational(2, 3))
    }

    @Test("Negation works correctly")
    func negation() {
        let r = Rational(3, 4)
        let neg = -r
        #expect(neg.numerator == -3)
        #expect(neg.denominator == 4)
    }

    // MARK: - Equality & Comparison

    @Test("Equality compares reduced forms")
    func equalityReduced() {
        let a = Rational(2, 4)
        let b = Rational(1, 2)
        #expect(a == b)
    }

    @Test("Comparison works correctly")
    func comparison() {
        let a = Rational(1, 3)
        let b = Rational(1, 2)
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test("Hash equality for equivalent rationals")
    func hashEquality() {
        let a = Rational(2, 4)
        let b = Rational(1, 2)
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Reduction

    @Test("Reduced returns simplified form")
    func reduced() {
        let r = Rational(12, 8).reduced()
        #expect(r.numerator == 3)
        #expect(r.denominator == 2)
    }

    @Test("Zero reduces to 0/1")
    func zeroReduced() {
        let r = Rational(0, 5).reduced()
        #expect(r.numerator == 0)
        #expect(r.denominator == 1)
    }

    // MARK: - Frame/Time Conversions

    @Test("Microseconds per frame at 30fps")
    func microsecondsPerFrame30fps() {
        let fps30 = Rational.fps30
        #expect(fps30.microsecondsPerFrame == 33333)
    }

    @Test("Frame to microseconds roundtrip")
    func frameTimeRoundtrip() {
        let fps = Rational.fps30
        let micros = fps.frameToMicroseconds(150)
        let frame = fps.microsecondsToFrame(micros)
        #expect(frame == 150)
    }

    @Test("Snap to frame boundary")
    func snapToFrame() {
        let fps = Rational.fps30
        let exactFrame = fps.frameToMicroseconds(10)
        let offset = exactFrame + 5000 // 5ms offset
        let snapped = fps.snapToFrame(offset)
        #expect(snapped == exactFrame)
    }

    @Test("Snap to next frame boundary")
    func snapToNextFrame() {
        let fps = Rational.fps30
        let exactFrame = fps.frameToMicroseconds(10)
        let offset = exactFrame + 5000
        let snapped = fps.snapToNextFrame(offset)
        let nextFrame = fps.frameToMicroseconds(11)
        #expect(snapped == nextFrame)
    }

    @Test("Snap to next frame when already on boundary returns same")
    func snapToNextFrameOnBoundary() {
        let fps = Rational.fps30
        let exactFrame = fps.frameToMicroseconds(10)
        let snapped = fps.snapToNextFrame(exactFrame)
        #expect(snapped == exactFrame)
    }

    @Test("Frame and offset decomposition")
    func frameAndOffset() {
        let fps = Rational.fps30
        let time = fps.frameToMicroseconds(5) + 10000
        let (frame, offset) = fps.frameAndOffset(time)
        #expect(frame == 5)
        #expect(offset == 10000)
    }

    // MARK: - Factory Methods

    @Test("fromFrameRateString parses known rates")
    func fromFrameRateString() {
        #expect(Rational.fromFrameRateString("29.97") == .fps29_97)
        #expect(Rational.fromFrameRateString("30") == .fps30)
        #expect(Rational.fromFrameRateString("23.976") == .fps23_976)
        #expect(Rational.fromFrameRateString("60") == .fps60)
    }

    @Test("fromFrameRateString returns nil for invalid")
    func fromFrameRateStringInvalid() {
        #expect(Rational.fromFrameRateString("abc") == nil)
    }

    @Test("fromDouble approximates correctly")
    func fromDouble() {
        let r = Rational.fromDouble(29.97, maxDenominator: 10001)
        #expect(abs(r.value - 29.97) < 0.001)
    }

    @Test("fromDouble zero returns zero")
    func fromDoubleZero() {
        let r = Rational.fromDouble(0)
        #expect(r == Rational(0))
    }

    // MARK: - CMTime Interop

    @Test("CMTime conversion roundtrip")
    func cmTimeRoundtrip() {
        let original = Rational(30000, 1001)
        let cmTime = original.cmTime
        let restored = Rational.fromCMTime(cmTime)
        #expect(restored == original)
    }

    @Test("CMTime values are correct")
    func cmTimeValues() {
        let r = Rational(24)
        let ct = r.cmTime
        #expect(ct.value == 24)
        #expect(ct.timescale == 1)
    }

    // MARK: - Codable

    @Test("JSON encoding uses Dart-compatible keys")
    func jsonEncoding() throws {
        let r = Rational(30000, 1001)
        let data = try JSONEncoder().encode(r)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["num"] as? Int == 30000)
        #expect(json["den"] as? Int == 1001)
    }

    @Test("JSON decoding from Dart-compatible format")
    func jsonDecoding() throws {
        let json = #"{"num": 24000, "den": 1001}"#
        let data = json.data(using: .utf8)!
        let r = try JSONDecoder().decode(Rational.self, from: data)
        #expect(r == Rational.fps23_976)
    }

    @Test("JSON decoding with missing denominator defaults to 1")
    func jsonDecodingMissingDen() throws {
        let json = #"{"num": 30}"#
        let data = json.data(using: .utf8)!
        let r = try JSONDecoder().decode(Rational.self, from: data)
        #expect(r == Rational.fps30)
    }

    @Test("Codable roundtrip preserves value")
    func codableRoundtrip() throws {
        let original = Rational(60000, 1001)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Rational.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Display

    @Test("frameRateString for known rates")
    func frameRateString() {
        #expect(Rational.fps29_97.frameRateString == "29.97 fps")
        #expect(Rational.fps30.frameRateString == "30 fps")
        #expect(Rational.fps24.frameRateString == "24 fps")
        #expect(Rational.fps23_976.frameRateString == "23.976 fps")
    }

    @Test("frameRateString for integer rates with den=1")
    func frameRateStringInteger() {
        let r = Rational(48)
        #expect(r.frameRateString == "48 fps")
    }

    // MARK: - GCD

    @Test("GCD computes correctly")
    func gcdComputation() {
        #expect(Rational.gcd(12, 8) == 4)
        #expect(Rational.gcd(17, 13) == 1) // primes
        #expect(Rational.gcd(100, 75) == 25)
    }
}
