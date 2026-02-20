import Testing
import Foundation
@testable import LiquidEditor

@Suite("AudioDuckingConfig Tests")
struct AudioDuckingConfigTests {

    // MARK: - Creation

    @Test("creation with defaults uses expected values")
    func creationDefaults() {
        let config = AudioDuckingConfig(
            targetTrackId: "music-1",
            triggerTrackId: "voice-1"
        )
        #expect(config.isEnabled == true)
        #expect(config.targetTrackId == "music-1")
        #expect(config.triggerTrackId == "voice-1")
        #expect(config.duckAmountDB == -12.0)
        #expect(config.attackMs == 200)
        #expect(config.releaseMs == 500)
        #expect(config.speechThreshold == 0.3)
    }

    @Test("creation with custom values")
    func creationCustom() {
        let config = AudioDuckingConfig(
            isEnabled: false,
            targetTrackId: "bg-music",
            triggerTrackId: "narrator",
            duckAmountDB: -18.0,
            attackMs: 100,
            releaseMs: 800,
            speechThreshold: 0.5
        )
        #expect(config.isEnabled == false)
        #expect(config.targetTrackId == "bg-music")
        #expect(config.triggerTrackId == "narrator")
        #expect(config.duckAmountDB == -18.0)
        #expect(config.attackMs == 100)
        #expect(config.releaseMs == 800)
        #expect(config.speechThreshold == 0.5)
    }

    // MARK: - Computed Properties

    @Test("duckVolumeLinear converts dB to linear")
    func duckVolumeLinear() {
        let config = AudioDuckingConfig(
            targetTrackId: "t",
            triggerTrackId: "s",
            duckAmountDB: -20.0
        )
        // -20 dB = 10^(-20/20) = 10^(-1) = 0.1
        #expect(abs(config.duckVolumeLinear - 0.1) < 0.001)
    }

    @Test("duckVolumeLinear returns 1.0 for zero dB")
    func duckVolumeLinearZero() {
        let config = AudioDuckingConfig(
            targetTrackId: "t",
            triggerTrackId: "s",
            duckAmountDB: 0.0
        )
        #expect(config.duckVolumeLinear == 1.0)
    }

    @Test("duckVolumeLinear returns 1.0 for positive dB")
    func duckVolumeLinearPositive() {
        let config = AudioDuckingConfig(
            targetTrackId: "t",
            triggerTrackId: "s",
            duckAmountDB: 6.0
        )
        #expect(config.duckVolumeLinear == 1.0)
    }

    @Test("duckVolumeLinear for -6dB is approximately 0.5")
    func duckVolumeLinearSixDB() {
        let config = AudioDuckingConfig(
            targetTrackId: "t",
            triggerTrackId: "s",
            duckAmountDB: -6.0
        )
        // -6 dB ~= 0.501
        #expect(abs(config.duckVolumeLinear - 0.501) < 0.01)
    }

    // MARK: - Copy-With

    @Test("with() preserves unchanged fields")
    func withPreservesUnchanged() {
        let original = AudioDuckingConfig(
            isEnabled: true,
            targetTrackId: "music",
            triggerTrackId: "voice",
            duckAmountDB: -12.0,
            attackMs: 200,
            releaseMs: 500,
            speechThreshold: 0.3
        )
        let modified = original.with(attackMs: 100)
        #expect(modified.attackMs == 100)
        #expect(modified.isEnabled == true)
        #expect(modified.targetTrackId == "music")
        #expect(modified.triggerTrackId == "voice")
        #expect(modified.duckAmountDB == -12.0)
        #expect(modified.releaseMs == 500)
        #expect(modified.speechThreshold == 0.3)
    }

    @Test("with() can override all fields")
    func withOverridesAll() {
        let original = AudioDuckingConfig(
            targetTrackId: "t1",
            triggerTrackId: "s1"
        )
        let modified = original.with(
            isEnabled: false,
            targetTrackId: "t2",
            triggerTrackId: "s2",
            duckAmountDB: -24.0,
            attackMs: 50,
            releaseMs: 1000,
            speechThreshold: 0.8
        )
        #expect(modified.isEnabled == false)
        #expect(modified.targetTrackId == "t2")
        #expect(modified.triggerTrackId == "s2")
        #expect(modified.duckAmountDB == -24.0)
        #expect(modified.attackMs == 50)
        #expect(modified.releaseMs == 1000)
        #expect(modified.speechThreshold == 0.8)
    }

    // MARK: - Equatable / Hashable

    @Test("equal configs are equal")
    func equality() {
        let a = AudioDuckingConfig(targetTrackId: "t", triggerTrackId: "s")
        let b = AudioDuckingConfig(targetTrackId: "t", triggerTrackId: "s")
        #expect(a == b)
    }

    @Test("different configs are not equal")
    func inequality() {
        let a = AudioDuckingConfig(targetTrackId: "t1", triggerTrackId: "s1")
        let b = AudioDuckingConfig(targetTrackId: "t2", triggerTrackId: "s2")
        #expect(a != b)
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = AudioDuckingConfig(
            isEnabled: false,
            targetTrackId: "music-track",
            triggerTrackId: "voice-track",
            duckAmountDB: -18.0,
            attackMs: 150,
            releaseMs: 700,
            speechThreshold: 0.45
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioDuckingConfig.self, from: data)
        #expect(decoded == original)
        #expect(decoded.isEnabled == false)
        #expect(decoded.targetTrackId == "music-track")
        #expect(decoded.duckAmountDB == -18.0)
        #expect(decoded.attackMs == 150)
        #expect(decoded.releaseMs == 700)
        #expect(decoded.speechThreshold == 0.45)
    }
}
