// AudioEffectsEngineTests.swift
// LiquidEditorTests
//
// Comprehensive tests for AudioEffectsEngine:
// - Lifecycle (initialize/shutdown)
// - Effect chain setup, removal, and re-setup
// - Effect parameter updates
// - Error conditions (uninitialised engine, missing clip, missing effect)
// - Edge cases (empty chain, disabled effects, multiple clips)

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Test Helpers

/// Create a reverb AudioEffect.
private func makeReverb(
    id: String = "reverb-1",
    isEnabled: Bool = true,
    mix: Double = 0.5
) -> AudioEffect {
    .reverb(ReverbParams(id: id, isEnabled: isEnabled, mix: mix))
}

/// Create an echo AudioEffect.
private func makeEcho(
    id: String = "echo-1",
    isEnabled: Bool = true,
    mix: Double = 0.4,
    delayTime: Double = 0.3,
    feedback: Double = 0.5
) -> AudioEffect {
    .echo(EchoParams(id: id, isEnabled: isEnabled, mix: mix, delayTime: delayTime, feedback: feedback))
}

/// Create a pitch shift AudioEffect.
private func makePitchShift(
    id: String = "pitch-1",
    isEnabled: Bool = true,
    semitones: Double = 2.0,
    cents: Double = 0.0
) -> AudioEffect {
    .pitchShift(PitchShiftParams(id: id, isEnabled: isEnabled, semitones: semitones, cents: cents))
}

/// Create an EQ AudioEffect.
private func makeEQ(id: String = "eq-1", isEnabled: Bool = true) -> AudioEffect {
    .eq(EQParams(id: id, isEnabled: isEnabled))
}

/// Create a compressor AudioEffect.
private func makeCompressor(id: String = "comp-1", isEnabled: Bool = true) -> AudioEffect {
    .compressor(CompressorParams(id: id, isEnabled: isEnabled))
}

/// Create a distortion AudioEffect.
private func makeDistortion(
    id: String = "dist-1",
    isEnabled: Bool = true,
    distortionType: DistortionType = .overdrive
) -> AudioEffect {
    .distortion(DistortionParams(id: id, isEnabled: isEnabled, distortionType: distortionType))
}

/// Create a noise gate AudioEffect.
private func makeNoiseGate(id: String = "gate-1", isEnabled: Bool = true) -> AudioEffect {
    .noiseGate(NoiseGateParams(id: id, isEnabled: isEnabled))
}

// MARK: - AudioEffectsEngine Tests

@Suite("AudioEffectsEngine Tests")
struct AudioEffectsEngineTests {

    // MARK: - Lifecycle

    @Test("Engine starts with zero active chains and not running")
    func initialState() {
        let engine = AudioEffectsEngine()
        #expect(engine.activeChainCount == 0)
        #expect(engine.isRunning == false)
    }

    @Test("Initialize creates engine, shutdown destroys it")
    func initializeAndShutdown() {
        let engine = AudioEffectsEngine()
        engine.initialize()

        // After initialize, engine exists but is not running until a chain is set up
        #expect(engine.activeChainCount == 0)

        engine.shutdown()
        #expect(engine.activeChainCount == 0)
        #expect(engine.isRunning == false)
    }

    @Test("Double initialize is safe (no-op on second call)")
    func doubleInitialize() {
        let engine = AudioEffectsEngine()
        engine.initialize()
        engine.initialize() // should not crash
        #expect(engine.activeChainCount == 0)
        engine.shutdown()
    }

    @Test("Shutdown without initialize is safe (no-op)")
    func shutdownWithoutInitialize() {
        let engine = AudioEffectsEngine()
        engine.shutdown() // should not crash
        #expect(engine.activeChainCount == 0)
    }

    // MARK: - Error Conditions

    @Test("Setup chain without initialize throws engineNotInitialized")
    func setupChainWithoutInit() {
        let engine = AudioEffectsEngine()
        #expect(throws: AudioEffectsError.self) {
            try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb()])
        }
    }

    @Test("Remove chain without initialize throws engineNotInitialized")
    func removeChainWithoutInit() {
        let engine = AudioEffectsEngine()
        #expect(throws: AudioEffectsError.self) {
            try engine.removeEffectChain(clipId: "clip-1")
        }
    }

    @Test("Remove nonexistent clip throws clipNotFound")
    func removeNonexistentClip() {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        #expect(throws: AudioEffectsError.self) {
            try engine.removeEffectChain(clipId: "nonexistent")
        }
    }

    @Test("Update effect for nonexistent clip throws clipNotFound")
    func updateEffectNonexistentClip() {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        #expect(throws: AudioEffectsError.self) {
            try engine.updateEffect(clipId: "no-such-clip", effect: makeReverb())
        }
    }

    @Test("Update effect with nonexistent effect ID throws effectNotFound")
    func updateNonexistentEffect() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb(id: "r1")])

        #expect(throws: AudioEffectsError.self) {
            try engine.updateEffect(
                clipId: "clip-1",
                effect: makeReverb(id: "nonexistent-id")
            )
        }
    }

    // MARK: - Effect Chain Setup

    @Test("Setup single effect chain increments activeChainCount")
    func setupSingleChain() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb()])
        #expect(engine.activeChainCount == 1)
    }

    @Test("Setup multiple clip chains tracks count correctly")
    func setupMultipleChains() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb()])
        try engine.setupEffectChain(clipId: "clip-2", effects: [makeEcho()])
        try engine.setupEffectChain(clipId: "clip-3", effects: [makePitchShift()])
        #expect(engine.activeChainCount == 3)
    }

    @Test("Setup chain with empty effects creates chain with no effect nodes")
    func setupEmptyChain() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        try engine.setupEffectChain(clipId: "clip-1", effects: [])
        #expect(engine.activeChainCount == 1)
    }

    @Test("Setup chain with only disabled effects creates chain without those nodes")
    func setupDisabledEffects() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        let effects: [AudioEffect] = [
            makeReverb(id: "r1", isEnabled: false),
            makeEcho(id: "e1", isEnabled: false),
        ]
        try engine.setupEffectChain(clipId: "clip-1", effects: effects)
        #expect(engine.activeChainCount == 1)
    }

    @Test("Re-setup chain for same clip replaces existing chain")
    func reSetupChain() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb()])
        #expect(engine.activeChainCount == 1)

        // Replace the chain with different effects
        try engine.setupEffectChain(clipId: "clip-1", effects: [makeEcho(), makePitchShift()])
        #expect(engine.activeChainCount == 1) // still 1 clip
    }

    @Test("Setup chain with all seven effect types succeeds")
    func setupAllEffectTypes() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        let effects: [AudioEffect] = [
            makeReverb(id: "r1"),
            makeEcho(id: "e1"),
            makePitchShift(id: "p1"),
            makeEQ(id: "eq1"),
            makeCompressor(id: "c1"),
            makeDistortion(id: "d1"),
            makeNoiseGate(id: "g1"),
        ]

        try engine.setupEffectChain(clipId: "clip-1", effects: effects)
        #expect(engine.activeChainCount == 1)
    }

    @Test("Setup distortion with all sub-types succeeds")
    func setupDistortionSubTypes() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        for subType in DistortionType.allCases {
            let effects: [AudioEffect] = [
                makeDistortion(id: "d-\(subType.rawValue)", distortionType: subType)
            ]
            try engine.setupEffectChain(clipId: "clip-\(subType.rawValue)", effects: effects)
        }
        #expect(engine.activeChainCount == DistortionType.allCases.count)
    }

    // MARK: - Effect Chain Removal

    @Test("Remove chain decrements activeChainCount")
    func removeChain() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb()])
        try engine.setupEffectChain(clipId: "clip-2", effects: [makeEcho()])
        #expect(engine.activeChainCount == 2)

        try engine.removeEffectChain(clipId: "clip-1")
        #expect(engine.activeChainCount == 1)
    }

    @Test("Remove all chains clears everything")
    func removeAllChains() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb()])
        try engine.setupEffectChain(clipId: "clip-2", effects: [makeEcho()])
        try engine.setupEffectChain(clipId: "clip-3", effects: [makePitchShift()])
        #expect(engine.activeChainCount == 3)

        engine.removeAllEffectChains()
        #expect(engine.activeChainCount == 0)
    }

    @Test("Remove all chains with no chains is safe")
    func removeAllNoChains() {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        engine.removeAllEffectChains() // should not crash
        #expect(engine.activeChainCount == 0)
    }

    // MARK: - Effect Parameter Updates

    @Test("Update effect parameters on existing chain succeeds")
    func updateEffectParams() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        let reverb = makeReverb(id: "r1", mix: 0.3)
        try engine.setupEffectChain(clipId: "clip-1", effects: [reverb])

        // Update the reverb mix
        let updatedReverb = makeReverb(id: "r1", mix: 0.8)
        try engine.updateEffect(clipId: "clip-1", effect: updatedReverb)
        // No error means success -- the actual parameter is applied to the audio node
    }

    @Test("Update echo parameters succeeds")
    func updateEchoParams() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        let echo = makeEcho(id: "e1", delayTime: 0.3, feedback: 0.4)
        try engine.setupEffectChain(clipId: "clip-1", effects: [echo])

        let updatedEcho = makeEcho(id: "e1", delayTime: 0.5, feedback: 0.8)
        try engine.updateEffect(clipId: "clip-1", effect: updatedEcho)
    }

    @Test("Update pitch shift parameters succeeds")
    func updatePitchShiftParams() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        let pitch = makePitchShift(id: "p1", semitones: 2.0, cents: 0.0)
        try engine.setupEffectChain(clipId: "clip-1", effects: [pitch])

        let updatedPitch = makePitchShift(id: "p1", semitones: -3.0, cents: 25.0)
        try engine.updateEffect(clipId: "clip-1", effect: updatedPitch)
    }

    // MARK: - Mixed Enabled/Disabled Effects

    @Test("Only enabled effects are included in chain, disabled ones are skipped")
    func mixedEnabledDisabled() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()
        defer { engine.shutdown() }

        let effects: [AudioEffect] = [
            makeReverb(id: "r1", isEnabled: true),
            makeEcho(id: "e1", isEnabled: false),
            makePitchShift(id: "p1", isEnabled: true),
        ]
        try engine.setupEffectChain(clipId: "clip-1", effects: effects)
        #expect(engine.activeChainCount == 1)

        // Updating the disabled effect by ID should fail because it was not included
        #expect(throws: AudioEffectsError.self) {
            try engine.updateEffect(
                clipId: "clip-1",
                effect: makeEcho(id: "e1", isEnabled: false)
            )
        }

        // Updating an enabled effect should succeed
        try engine.updateEffect(
            clipId: "clip-1",
            effect: makeReverb(id: "r1", mix: 0.9)
        )
    }

    // MARK: - Shutdown Cleans Up

    @Test("Shutdown removes all chains and stops engine")
    func shutdownCleansUp() throws {
        let engine = AudioEffectsEngine()
        engine.initialize()

        try engine.setupEffectChain(clipId: "clip-1", effects: [makeReverb()])
        try engine.setupEffectChain(clipId: "clip-2", effects: [makeEcho()])
        #expect(engine.activeChainCount == 2)

        engine.shutdown()
        #expect(engine.activeChainCount == 0)
        #expect(engine.isRunning == false)
    }

    // MARK: - AudioEffectsError description coverage

    @Test("Error descriptions are non-empty and descriptive")
    func errorDescriptions() {
        let errors: [AudioEffectsError] = [
            .engineNotInitialized,
            .formatCreationFailed,
            .engineStartFailed("test reason"),
            .clipNotFound("clip-xyz"),
            .effectNotFound(effectId: "eff-1", clipId: "clip-1"),
            .nodeCreationFailed(.reverb),
        ]

        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty, "Error \(error) should have a description")
        }
    }
}
