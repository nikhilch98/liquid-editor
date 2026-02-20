import Foundation
import CoreMedia

/// Rational number representation for precise frame rate calculations.
///
/// Broadcast video uses fractional frame rates (e.g., 29.97fps = 30000/1001)
/// that cannot be precisely represented as floating-point numbers.
/// This struct provides exact arithmetic for these values.
struct Rational: Codable, Equatable, Hashable, Comparable, Sendable {
    /// The numerator of the fraction.
    let numerator: Int

    /// The denominator of the fraction (must be positive).
    let denominator: Int

    /// Creates a rational number.
    ///
    /// - Parameters:
    ///   - numerator: Can be any integer.
    ///   - denominator: Must be positive. Defaults to 1.
    init(_ numerator: Int, _ denominator: Int = 1) {
        precondition(denominator > 0, "Denominator must be positive")
        self.numerator = numerator
        self.denominator = denominator
    }

    /// Returns the floating-point value (for display only, not calculations).
    var value: Double { Double(numerator) / Double(denominator) }

    // MARK: - Common Broadcast Frame Rates

    /// 23.976 fps (Film to NTSC)
    static let fps23_976 = Rational(24000, 1001)
    /// 24 fps (Film)
    static let fps24 = Rational(24)
    /// 25 fps (PAL)
    static let fps25 = Rational(25)
    /// 29.97 fps (NTSC)
    static let fps29_97 = Rational(30000, 1001)
    /// 30 fps
    static let fps30 = Rational(30)
    /// 50 fps (PAL high frame rate)
    static let fps50 = Rational(50)
    /// 59.94 fps (NTSC high frame rate)
    static let fps59_94 = Rational(60000, 1001)
    /// 60 fps
    static let fps60 = Rational(60)
    /// 120 fps (High speed)
    static let fps120 = Rational(120)
    /// 240 fps (Slow motion)
    static let fps240 = Rational(240)

    // MARK: - Frame/Time Conversions

    /// Microseconds per frame at this frame rate.
    var microsecondsPerFrame: Int64 {
        (1_000_000 * Int64(denominator)) / Int64(numerator)
    }

    /// Convert frame number to microseconds using integer arithmetic.
    func frameToMicroseconds(_ frame: Int) -> Int64 {
        (Int64(frame) * 1_000_000 * Int64(denominator)) / Int64(numerator)
    }

    /// Convert microseconds to frame number (floor).
    func microsecondsToFrame(_ microseconds: Int64) -> Int {
        Int((microseconds * Int64(numerator)) / (1_000_000 * Int64(denominator)))
    }

    /// Snap microseconds to nearest frame boundary.
    func snapToFrame(_ microseconds: Int64) -> Int64 {
        let frame = microsecondsToFrame(microseconds)
        return frameToMicroseconds(frame)
    }

    /// Snap microseconds to next frame boundary (ceiling).
    func snapToNextFrame(_ microseconds: Int64) -> Int64 {
        let frame = microsecondsToFrame(microseconds)
        let snapped = frameToMicroseconds(frame)
        if snapped < microseconds {
            return frameToMicroseconds(frame + 1)
        }
        return snapped
    }

    /// Get frame number and offset within frame for a given time.
    func frameAndOffset(_ microseconds: Int64) -> (frame: Int, offset: Int64) {
        let frame = microsecondsToFrame(microseconds)
        let frameStart = frameToMicroseconds(frame)
        return (frame, microseconds - frameStart)
    }

    // MARK: - Arithmetic Operations

    /// Returns the reduced form of this rational.
    func reduced() -> Rational {
        if numerator == 0 { return Rational(0) }
        let g = Rational.gcd(abs(numerator), denominator)
        return Rational(numerator / g, denominator / g)
    }

    static func + (lhs: Rational, rhs: Rational) -> Rational {
        let num = lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator
        let den = lhs.denominator * rhs.denominator
        return Rational(num, den).reduced()
    }

    static func - (lhs: Rational, rhs: Rational) -> Rational {
        let num = lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator
        let den = lhs.denominator * rhs.denominator
        return Rational(num, den).reduced()
    }

    static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator).reduced()
    }

    static func / (lhs: Rational, rhs: Rational) -> Rational {
        precondition(rhs.numerator != 0, "Division by zero")
        return Rational(
            lhs.numerator * rhs.denominator,
            lhs.denominator * abs(rhs.numerator)
        ).reduced()
    }

    /// Negation.
    static prefix func - (value: Rational) -> Rational {
        Rational(-value.numerator, value.denominator)
    }

    // MARK: - Comparable

    static func < (lhs: Rational, rhs: Rational) -> Bool {
        let left = lhs.numerator * rhs.denominator
        let right = rhs.numerator * lhs.denominator
        return left < right
    }

    // MARK: - Equatable (compare reduced forms)

    static func == (lhs: Rational, rhs: Rational) -> Bool {
        let a = lhs.reduced()
        let b = rhs.reduced()
        return a.numerator == b.numerator && a.denominator == b.denominator
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        let r = reduced()
        hasher.combine(r.numerator)
        hasher.combine(r.denominator)
    }

    // MARK: - GCD

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 {
            let t = b
            b = a % b
            a = t
        }
        return a
    }

    // MARK: - Factory Methods

    /// Parse from common frame rate string (e.g., "29.97", "30", "23.976").
    static func fromFrameRateString(_ fps: String) -> Rational? {
        switch fps {
        case "23.976", "23.98": return .fps23_976
        case "24": return .fps24
        case "25": return .fps25
        case "29.97": return .fps29_97
        case "30": return .fps30
        case "50": return .fps50
        case "59.94": return .fps59_94
        case "60": return .fps60
        case "120": return .fps120
        case "240": return .fps240
        default:
            guard let doubleValue = Double(fps) else { return nil }
            return Rational.fromDouble(doubleValue)
        }
    }

    /// Create a rational approximation of a double using continued fractions.
    static func fromDouble(_ value: Double, maxDenominator: Int = 10001) -> Rational {
        if value == 0 { return Rational(0) }
        precondition(!value.isNaN && !value.isInfinite, "Cannot convert \(value) to Rational")

        let negative = value < 0
        var x = abs(value)

        var num1 = 1, num2 = 0
        var den1 = 0, den2 = 1

        while true {
            let a = Int(x)
            let num = a * num1 + num2
            let den = a * den1 + den2

            if den > maxDenominator { break }

            num2 = num1; num1 = num
            den2 = den1; den1 = den

            let remainder = x - Double(a)
            if remainder < 1e-10 { break }
            x = 1.0 / remainder
        }

        return Rational(negative ? -num1 : num1, den1)
    }

    // MARK: - CMTime Interop

    /// Convert to CMTime.
    var cmTime: CMTime {
        CMTime(value: CMTimeValue(numerator), timescale: CMTimeScale(denominator))
    }

    /// Create from CMTime.
    static func fromCMTime(_ time: CMTime) -> Rational {
        Rational(Int(time.value), Int(time.timescale))
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case numerator = "num"
        case denominator = "den"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        numerator = try container.decode(Int.self, forKey: .numerator)
        denominator = try container.decodeIfPresent(Int.self, forKey: .denominator) ?? 1
        precondition(denominator > 0, "Denominator must be positive")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(numerator, forKey: .numerator)
        try container.encode(denominator, forKey: .denominator)
    }

    // MARK: - Display

    /// Returns a human-readable frame rate string (e.g., "29.97 fps").
    var frameRateString: String {
        if self == .fps23_976 { return "23.976 fps" }
        if self == .fps24 { return "24 fps" }
        if self == .fps25 { return "25 fps" }
        if self == .fps29_97 { return "29.97 fps" }
        if self == .fps30 { return "30 fps" }
        if self == .fps50 { return "50 fps" }
        if self == .fps59_94 { return "59.94 fps" }
        if self == .fps60 { return "60 fps" }
        if self == .fps120 { return "120 fps" }
        if self == .fps240 { return "240 fps" }
        if denominator == 1 { return "\(numerator) fps" }
        return String(format: "%.2f fps", value)
    }
}
