import Testing
import Foundation
@testable import LiquidEditor

@Suite("NoiseProfile Tests")
struct NoiseProfileTests {

    // MARK: - Creation

    @Test("creation with all fields")
    func creation() {
        let profile = NoiseProfile(
            id: "np-1",
            assetId: "asset-1",
            startMicros: 1_000_000,
            endMicros: 3_000_000,
            nativeProfileHandle: "handle-abc"
        )
        #expect(profile.id == "np-1")
        #expect(profile.assetId == "asset-1")
        #expect(profile.startMicros == 1_000_000)
        #expect(profile.endMicros == 3_000_000)
        #expect(profile.nativeProfileHandle == "handle-abc")
    }

    // MARK: - Computed Properties

    @Test("durationMicros calculates correctly")
    func durationMicros() {
        let profile = NoiseProfile(
            id: "np-1",
            assetId: "a",
            startMicros: 1_000_000,
            endMicros: 4_000_000,
            nativeProfileHandle: "h"
        )
        #expect(profile.durationMicros == 3_000_000)
    }

    @Test("durationSeconds calculates correctly")
    func durationSeconds() {
        let profile = NoiseProfile(
            id: "np-1",
            assetId: "a",
            startMicros: 0,
            endMicros: 2_500_000,
            nativeProfileHandle: "h"
        )
        #expect(abs(profile.durationSeconds - 2.5) < 0.001)
    }

    @Test("zero duration")
    func zeroDuration() {
        let profile = NoiseProfile(
            id: "np-1",
            assetId: "a",
            startMicros: 1_000_000,
            endMicros: 1_000_000,
            nativeProfileHandle: "h"
        )
        #expect(profile.durationMicros == 0)
        #expect(profile.durationSeconds == 0.0)
    }

    // MARK: - Equatable / Hashable (by ID only)

    @Test("profiles with same ID are equal regardless of other fields")
    func equalityById() {
        let a = NoiseProfile(id: "np-1", assetId: "a1", startMicros: 0, endMicros: 100, nativeProfileHandle: "h1")
        let b = NoiseProfile(id: "np-1", assetId: "a2", startMicros: 50, endMicros: 200, nativeProfileHandle: "h2")
        #expect(a == b)
    }

    @Test("profiles with different IDs are not equal")
    func inequalityById() {
        let a = NoiseProfile(id: "np-1", assetId: "a", startMicros: 0, endMicros: 100, nativeProfileHandle: "h")
        let b = NoiseProfile(id: "np-2", assetId: "a", startMicros: 0, endMicros: 100, nativeProfileHandle: "h")
        #expect(a != b)
    }

    @Test("hash is based on ID")
    func hashById() {
        let a = NoiseProfile(id: "np-1", assetId: "a1", startMicros: 0, endMicros: 100, nativeProfileHandle: "h1")
        let b = NoiseProfile(id: "np-1", assetId: "a2", startMicros: 50, endMicros: 200, nativeProfileHandle: "h2")
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = NoiseProfile(
            id: "np-test",
            assetId: "asset-test",
            startMicros: 500_000,
            endMicros: 1_500_000,
            nativeProfileHandle: "handle-xyz"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NoiseProfile.self, from: data)
        #expect(decoded == original)
        #expect(decoded.id == "np-test")
        #expect(decoded.assetId == "asset-test")
        #expect(decoded.nativeProfileHandle == "handle-xyz")
    }
}
