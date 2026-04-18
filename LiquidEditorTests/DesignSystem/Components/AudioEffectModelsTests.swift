// AudioEffectModelsTests.swift
// TT13-3: Audio panel logic tests.
//
// Verifies default parameter values for each audio effect's params
// struct so the Audio effect panels have deterministic starting
// values per spec §11.6.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("Audio effect model defaults")
struct AudioEffectModelsTests {

    // MARK: - ReverbParams

    @Test("ReverbParams has sane defaults")
    func reverbDefaults() {
        let p = ReverbParams(id: "r")
        #expect(p.isEnabled == true)
        #expect(p.mix == 0.3)
        #expect(p.roomSize == 0.5)
        #expect(p.damping == 0.5)
    }

    // MARK: - EchoParams

    @Test("EchoParams has sane defaults")
    func echoDefaults() {
        let p = EchoParams(id: "e")
        #expect(p.isEnabled == true)
        #expect(p.mix == 0.3)
        #expect(p.delayTime == 0.3)
        #expect(p.feedback == 0.4)
    }

    // MARK: - PitchShiftParams

    @Test("PitchShiftParams has sane defaults")
    func pitchShiftDefaults() {
        let p = PitchShiftParams(id: "p")
        #expect(p.isEnabled == true)
        #expect(p.mix == 1.0)
        #expect(p.semitones == 0.0)
        #expect(p.cents == 0.0)
    }

    // MARK: - EQParams

    @Test("EQParams has sane defaults for all three bands")
    func eqDefaults() {
        let p = EQParams(id: "eq")
        #expect(p.isEnabled == true)
        #expect(p.mix == 1.0)
        #expect(p.bassGain == 0.0)
        #expect(p.bassFrequency == 100.0)
        #expect(p.midGain == 0.0)
        #expect(p.midFrequency == 1000.0)
        #expect(p.midQ == 1.0)
        #expect(p.trebleGain == 0.0)
        #expect(p.trebleFrequency == 8000.0)
    }

    // MARK: - CompressorParams

    @Test("CompressorParams has sane defaults")
    func compressorDefaults() {
        let p = CompressorParams(id: "c")
        #expect(p.isEnabled == true)
        #expect(p.mix == 1.0)
        #expect(p.threshold == -20.0)
        #expect(p.ratio == 4.0)
        #expect(p.attack == 0.01)
        #expect(p.release == 0.1)
        #expect(p.makeupGain == 0.0)
    }

    // MARK: - DistortionParams

    @Test("DistortionParams has sane defaults")
    func distortionDefaults() {
        let p = DistortionParams(id: "d")
        #expect(p.isEnabled == true)
        #expect(p.mix == 0.5)
        #expect(p.drive == 0.3)
        #expect(p.distortionType == .overdrive)
    }

    // MARK: - NoiseGateParams

    @Test("NoiseGateParams has sane defaults")
    func noiseGateDefaults() {
        let p = NoiseGateParams(id: "n")
        #expect(p.isEnabled == true)
        #expect(p.mix == 1.0)
        #expect(p.threshold == -40.0)
        #expect(p.attack == 0.005)
        #expect(p.release == 0.05)
    }

    // MARK: - AudioEffectChain

    @Test("AudioEffectChain is empty by default")
    func chainEmptyByDefault() {
        let chain = AudioEffectChain()
        #expect(chain.isEmpty)
        #expect(chain.count == 0)
        #expect(chain.enabledCount == 0)
        #expect(AudioEffectChain.empty.isEmpty)
    }
}
