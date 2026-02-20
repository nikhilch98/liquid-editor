import Testing
import Foundation
@testable import LiquidEditor

@Suite("ARGBColor Tests")
struct ARGBColorTests {

    // MARK: - Creation

    @Test("Creation with explicit values")
    func creation() {
        let color = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.1)
        #expect(abs(color.alpha - 0.5) < 0.0001)
        #expect(abs(color.red - 0.3) < 0.0001)
        #expect(abs(color.green - 0.7) < 0.0001)
        #expect(abs(color.blue - 0.1) < 0.0001)
    }

    // MARK: - Common Colors

    @Test("black is opaque black")
    func black() {
        let c = ARGBColor.black
        #expect(c.alpha == 1.0)
        #expect(c.red == 0.0)
        #expect(c.green == 0.0)
        #expect(c.blue == 0.0)
        #expect(c.isBlack)
        #expect(!c.isWhite)
        #expect(!c.isTransparent)
    }

    @Test("white is opaque white")
    func white() {
        let c = ARGBColor.white
        #expect(c.alpha == 1.0)
        #expect(c.red == 1.0)
        #expect(c.green == 1.0)
        #expect(c.blue == 1.0)
        #expect(c.isWhite)
        #expect(!c.isBlack)
        #expect(!c.isTransparent)
    }

    @Test("clear is fully transparent")
    func clear() {
        let c = ARGBColor.clear
        #expect(c.alpha == 0.0)
        #expect(c.isTransparent)
        #expect(!c.isBlack)
        #expect(!c.isWhite)
    }

    // MARK: - ARGB32 Conversion

    @Test("fromARGB32 extracts components correctly for opaque red")
    func fromARGB32Red() {
        let color = ARGBColor.fromARGB32(0xFFFF_0000)
        #expect(abs(color.alpha - 1.0) < 0.01)
        #expect(abs(color.red - 1.0) < 0.01)
        #expect(abs(color.green - 0.0) < 0.01)
        #expect(abs(color.blue - 0.0) < 0.01)
    }

    @Test("fromARGB32 extracts components correctly for opaque green")
    func fromARGB32Green() {
        let color = ARGBColor.fromARGB32(0xFF00_FF00)
        #expect(abs(color.alpha - 1.0) < 0.01)
        #expect(abs(color.red - 0.0) < 0.01)
        #expect(abs(color.green - 1.0) < 0.01)
        #expect(abs(color.blue - 0.0) < 0.01)
    }

    @Test("fromARGB32 extracts components correctly for opaque blue")
    func fromARGB32Blue() {
        let color = ARGBColor.fromARGB32(0xFF00_00FF)
        #expect(abs(color.alpha - 1.0) < 0.01)
        #expect(abs(color.red - 0.0) < 0.01)
        #expect(abs(color.green - 0.0) < 0.01)
        #expect(abs(color.blue - 1.0) < 0.01)
    }

    @Test("fromARGB32 extracts semi-transparent correctly")
    func fromARGB32SemiTransparent() {
        let color = ARGBColor.fromARGB32(0x80FF_FF00) // ~50% alpha, yellow
        #expect(abs(color.alpha - 128.0 / 255.0) < 0.01)
        #expect(abs(color.red - 1.0) < 0.01)
        #expect(abs(color.green - 1.0) < 0.01)
        #expect(abs(color.blue - 0.0) < 0.01)
    }

    @Test("toARGB32 converts back to integer correctly for opaque white")
    func toARGB32White() {
        let value = ARGBColor.white.toARGB32
        #expect(value == 0xFFFF_FFFF)
    }

    @Test("toARGB32 converts back to integer correctly for opaque black")
    func toARGB32Black() {
        let value = ARGBColor.black.toARGB32
        #expect(value == 0xFF00_0000)
    }

    @Test("toARGB32 converts back to integer correctly for clear")
    func toARGB32Clear() {
        let value = ARGBColor.clear.toARGB32
        #expect(value == 0x0000_0000)
    }

    @Test("fromARGB32 and toARGB32 roundtrip for opaque red")
    func roundtripRed() {
        let original = 0xFFFF_0000
        let color = ARGBColor.fromARGB32(original)
        let result = color.toARGB32
        #expect(result == original)
    }

    @Test("fromARGB32 and toARGB32 roundtrip for opaque green")
    func roundtripGreen() {
        let original = 0xFF00_FF00
        let color = ARGBColor.fromARGB32(original)
        let result = color.toARGB32
        #expect(result == original)
    }

    @Test("fromARGB32 and toARGB32 roundtrip for opaque blue")
    func roundtripBlue() {
        let original = 0xFF00_00FF
        let color = ARGBColor.fromARGB32(original)
        let result = color.toARGB32
        #expect(result == original)
    }

    @Test("fromARGB32 and toARGB32 roundtrip for arbitrary color")
    func roundtripArbitrary() {
        let original = 0xABCD_EF12
        let color = ARGBColor.fromARGB32(original)
        let result = color.toARGB32
        #expect(result == original)
    }

    @Test("fromARGB32 and toARGB32 roundtrip for opaque white")
    func roundtripWhite() {
        let original = 0xFFFF_FFFF
        let color = ARGBColor.fromARGB32(original)
        let result = color.toARGB32
        #expect(result == original)
    }

    // MARK: - Convenience Queries

    @Test("isBlack returns false for non-black colors")
    func isBlackFalse() {
        let darkGray = ARGBColor(alpha: 1.0, red: 0.1, green: 0.0, blue: 0.0)
        #expect(!darkGray.isBlack)
    }

    @Test("isWhite returns false for off-white colors")
    func isWhiteFalse() {
        let offWhite = ARGBColor(alpha: 1.0, red: 0.99, green: 1.0, blue: 1.0)
        #expect(!offWhite.isWhite)
    }

    @Test("isTransparent returns false for opaque colors")
    func isTransparentFalse() {
        let opaque = ARGBColor(alpha: 0.01, red: 0.0, green: 0.0, blue: 0.0)
        #expect(!opaque.isTransparent)
    }

    // MARK: - Mutation

    @Test("with() creates copy with overridden alpha")
    func withAlpha() {
        let original = ARGBColor.white
        let updated = original.with(alpha: 0.5)

        #expect(abs(updated.alpha - 0.5) < 0.0001)
        #expect(updated.red == 1.0) // unchanged
        #expect(updated.green == 1.0) // unchanged
        #expect(updated.blue == 1.0) // unchanged
    }

    @Test("with() creates copy with overridden color channels")
    func withChannels() {
        let original = ARGBColor.black
        let updated = original.with(red: 0.5, blue: 0.8)

        #expect(updated.alpha == 1.0) // unchanged
        #expect(abs(updated.red - 0.5) < 0.0001)
        #expect(updated.green == 0.0) // unchanged
        #expect(abs(updated.blue - 0.8) < 0.0001)
    }

    @Test("with() without arguments returns equivalent color")
    func withNoArgs() {
        let original = ARGBColor(alpha: 0.3, red: 0.4, green: 0.5, blue: 0.6)
        let copy = original.with()

        #expect(copy == original)
    }

    // MARK: - Equatable

    @Test("Equatable detects equal colors")
    func equatableEqual() {
        let a = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.1)
        let b = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.1)
        #expect(a == b)
    }

    @Test("Equatable detects different colors")
    func equatableDifferent() {
        let a = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.1)
        let b = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.2)
        #expect(a != b)
    }

    // MARK: - Hashable

    @Test("Hashable produces same hash for equal colors")
    func hashableEqual() {
        let a = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.1)
        let b = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.1)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Colors work in a Set")
    func setMembership() {
        let a = ARGBColor.black
        let b = ARGBColor.white
        let c = ARGBColor.black // duplicate
        let set: Set<ARGBColor> = [a, b, c]
        #expect(set.count == 2)
    }

    // MARK: - Codable

    @Test("Codable roundtrip")
    func codable() throws {
        let original = ARGBColor(alpha: 0.5, red: 0.3, green: 0.7, blue: 0.1)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ARGBColor.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable roundtrip for common colors")
    func codableCommon() throws {
        let colors: [ARGBColor] = [.black, .white, .clear]
        for color in colors {
            let data = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(ARGBColor.self, from: data)
            #expect(decoded == color)
        }
    }

    @Test("Codable produces valid JSON")
    func codableJSON() throws {
        let color = ARGBColor(alpha: 1.0, red: 0.5, green: 0.25, blue: 0.75)
        let data = try JSONEncoder().encode(color)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("alpha"))
        #expect(json.contains("red"))
        #expect(json.contains("green"))
        #expect(json.contains("blue"))
    }
}
