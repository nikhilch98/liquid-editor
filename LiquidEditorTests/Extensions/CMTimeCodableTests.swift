import Testing
import Foundation
import CoreMedia
@testable import LiquidEditor

@Suite("CodableCMTime Tests")
struct CodableCMTimeTests {

    // MARK: - Creation

    @Test("Creates from CMTime")
    func createFromCMTime() {
        let cmTime = CMTime(seconds: 2.5, preferredTimescale: 600)
        let codable = CodableCMTime(cmTime)
        #expect(abs(codable.time.seconds - 2.5) < 0.001)
    }

    @Test("Creates from seconds")
    func createFromSeconds() {
        let codable = CodableCMTime(seconds: 1.5)
        #expect(abs(codable.time.seconds - 1.5) < 0.001)
        #expect(codable.time.timescale == 600)
    }

    // MARK: - Codable

    @Test("Encodes as Double seconds")
    func encoding() throws {
        let codable = CodableCMTime(seconds: 3.5)
        let data = try JSONEncoder().encode(codable)
        let value = try JSONDecoder().decode(Double.self, from: data)
        #expect(abs(value - 3.5) < 0.001)
    }

    @Test("Decodes from Double seconds")
    func decoding() throws {
        let json = "2.0"
        let data = json.data(using: .utf8)!
        let codable = try JSONDecoder().decode(CodableCMTime.self, from: data)
        #expect(abs(codable.time.seconds - 2.0) < 0.001)
    }

    @Test("Codable roundtrip preserves value")
    func codableRoundtrip() throws {
        let original = CodableCMTime(seconds: 5.123)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodableCMTime.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Equality

    @Test("Equal times are equal")
    func equality() {
        let a = CodableCMTime(seconds: 1.0)
        let b = CodableCMTime(CMTime(seconds: 1.0, preferredTimescale: 44100))
        #expect(a == b) // Same time, different timescale
    }

    @Test("Different times are not equal")
    func inequality() {
        let a = CodableCMTime(seconds: 1.0)
        let b = CodableCMTime(seconds: 2.0)
        #expect(a != b)
    }

    // MARK: - Hashable

    @Test("Equal times have equal hashes")
    func hashEquality() {
        let a = CodableCMTime(seconds: 1.5)
        let b = CodableCMTime(seconds: 1.5)
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - CMTime Normalized Extension

    @Test("Normalized CMTime uses timescale 600")
    func normalizedTimescale() {
        let cmTime = CMTime(seconds: 1.0, preferredTimescale: 44100)
        let normalized = cmTime.normalized
        #expect(normalized.timescale == 600)
        #expect(abs(normalized.seconds - 1.0) < 0.001)
    }

    @Test("Normalized preserves zero")
    func normalizedZero() {
        let cmTime = CMTime(seconds: 0, preferredTimescale: 600)
        let normalized = cmTime.normalized
        #expect(normalized.seconds == 0)
    }
}
