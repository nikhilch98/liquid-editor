import Testing
import Foundation
@testable import LiquidEditor

@Suite("AudioEffect Tests")
struct AudioEffectTests {

    // MARK: - AudioEffectType

    @Test("All effect types have non-empty display names",
          arguments: AudioEffectType.allCases)
    func displayNames(type: AudioEffectType) {
        #expect(!type.displayName.isEmpty)
    }

    @Test("All effect types have non-empty SF symbol names",
          arguments: AudioEffectType.allCases)
    func sfSymbolNames(type: AudioEffectType) {
        #expect(!type.sfSymbolName.isEmpty)
    }

    // MARK: - DistortionType

    @Test("All distortion types have non-empty display names",
          arguments: DistortionType.allCases)
    func distortionDisplayNames(type: DistortionType) {
        #expect(!type.displayName.isEmpty)
    }

    // MARK: - Reverb Creation

    @Test("Reverb effect creation and properties")
    func reverbCreation() {
        let params = ReverbParams(id: "r1", roomSize: 0.7, damping: 0.3)
        let effect = AudioEffect.reverb(params)
        #expect(effect.id == "r1")
        #expect(effect.type == .reverb)
        #expect(effect.isEnabled == true)
        #expect(effect.mix == 0.3) // default
    }

    @Test("Reverb default parameter values")
    func reverbDefaults() {
        let params = ReverbParams(id: "r1")
        #expect(params.isEnabled == true)
        #expect(params.mix == 0.3)
        #expect(params.roomSize == 0.5)
        #expect(params.damping == 0.5)
    }

    // MARK: - Echo Creation

    @Test("Echo effect creation and properties")
    func echoCreation() {
        let params = EchoParams(id: "e1", delayTime: 0.5, feedback: 0.6)
        let effect = AudioEffect.echo(params)
        #expect(effect.id == "e1")
        #expect(effect.type == .echo)
        #expect(effect.isEnabled == true)
    }

    @Test("Echo default parameter values")
    func echoDefaults() {
        let params = EchoParams(id: "e1")
        #expect(params.mix == 0.3)
        #expect(params.delayTime == 0.3)
        #expect(params.feedback == 0.4)
    }

    // MARK: - PitchShift Creation

    @Test("PitchShift effect creation and properties")
    func pitchShiftCreation() {
        let params = PitchShiftParams(id: "ps1", semitones: 3.0, cents: 25.0)
        let effect = AudioEffect.pitchShift(params)
        #expect(effect.id == "ps1")
        #expect(effect.type == .pitchShift)
        #expect(effect.mix == 1.0) // default
    }

    @Test("PitchShift default parameter values")
    func pitchShiftDefaults() {
        let params = PitchShiftParams(id: "ps1")
        #expect(params.mix == 1.0)
        #expect(params.semitones == 0.0)
        #expect(params.cents == 0.0)
    }

    // MARK: - EQ Creation

    @Test("EQ effect creation and properties")
    func eqCreation() {
        let params = EQParams(id: "eq1", bassGain: 3.0, midGain: -2.0, trebleGain: 1.0)
        let effect = AudioEffect.eq(params)
        #expect(effect.id == "eq1")
        #expect(effect.type == .eq)
    }

    @Test("EQ default parameter values")
    func eqDefaults() {
        let params = EQParams(id: "eq1")
        #expect(params.mix == 1.0)
        #expect(params.bassGain == 0.0)
        #expect(params.bassFrequency == 100.0)
        #expect(params.midGain == 0.0)
        #expect(params.midFrequency == 1000.0)
        #expect(params.midQ == 1.0)
        #expect(params.trebleGain == 0.0)
        #expect(params.trebleFrequency == 8000.0)
    }

    // MARK: - Compressor Creation

    @Test("Compressor effect creation and properties")
    func compressorCreation() {
        let params = CompressorParams(id: "c1", threshold: -30.0, ratio: 8.0)
        let effect = AudioEffect.compressor(params)
        #expect(effect.id == "c1")
        #expect(effect.type == .compressor)
    }

    @Test("Compressor default parameter values")
    func compressorDefaults() {
        let params = CompressorParams(id: "c1")
        #expect(params.mix == 1.0)
        #expect(params.threshold == -20.0)
        #expect(params.ratio == 4.0)
        #expect(params.attack == 0.01)
        #expect(params.release == 0.1)
        #expect(params.makeupGain == 0.0)
    }

    // MARK: - Distortion Creation

    @Test("Distortion effect creation and properties")
    func distortionCreation() {
        let params = DistortionParams(id: "d1", drive: 0.7, distortionType: .fuzz)
        let effect = AudioEffect.distortion(params)
        #expect(effect.id == "d1")
        #expect(effect.type == .distortion)
    }

    @Test("Distortion default parameter values")
    func distortionDefaults() {
        let params = DistortionParams(id: "d1")
        #expect(params.mix == 0.5)
        #expect(params.drive == 0.3)
        #expect(params.distortionType == .overdrive)
    }

    // MARK: - NoiseGate Creation

    @Test("NoiseGate effect creation and properties")
    func noiseGateCreation() {
        let params = NoiseGateParams(id: "ng1", threshold: -50.0)
        let effect = AudioEffect.noiseGate(params)
        #expect(effect.id == "ng1")
        #expect(effect.type == .noiseGate)
    }

    @Test("NoiseGate default parameter values")
    func noiseGateDefaults() {
        let params = NoiseGateParams(id: "ng1")
        #expect(params.mix == 1.0)
        #expect(params.threshold == -40.0)
        #expect(params.attack == 0.005)
        #expect(params.release == 0.05)
    }

    // MARK: - Toggle

    @Test("Toggle reverses isEnabled state")
    func toggle() {
        let effect = AudioEffect.reverb(ReverbParams(id: "r1", isEnabled: true))
        let toggled = effect.toggled()
        #expect(toggled.isEnabled == false)

        let toggledBack = toggled.toggled()
        #expect(toggledBack.isEnabled == true)
    }

    @Test("Toggle works for all effect types")
    func toggleAllTypes() {
        let effects: [AudioEffect] = [
            .reverb(ReverbParams(id: "r1")),
            .echo(EchoParams(id: "e1")),
            .pitchShift(PitchShiftParams(id: "ps1")),
            .eq(EQParams(id: "eq1")),
            .compressor(CompressorParams(id: "c1")),
            .distortion(DistortionParams(id: "d1")),
            .noiseGate(NoiseGateParams(id: "ng1")),
        ]
        for effect in effects {
            #expect(effect.isEnabled == true)
            let toggled = effect.toggled()
            #expect(toggled.isEnabled == false, "Toggle failed for \(effect.type)")
        }
    }

    // MARK: - with() Copy Methods

    @Test("ReverbParams with() preserves unchanged fields")
    func reverbWith() {
        let original = ReverbParams(id: "r1", mix: 0.3, roomSize: 0.5, damping: 0.5)
        let copy = original.with(roomSize: 0.8)
        #expect(copy.id == "r1")
        #expect(copy.mix == 0.3)
        #expect(copy.roomSize == 0.8)
        #expect(copy.damping == 0.5)
    }

    @Test("EchoParams with() preserves unchanged fields")
    func echoWith() {
        let original = EchoParams(id: "e1", delayTime: 0.3, feedback: 0.4)
        let copy = original.with(feedback: 0.8)
        #expect(copy.delayTime == 0.3)
        #expect(copy.feedback == 0.8)
    }

    @Test("PitchShiftParams with() preserves unchanged fields")
    func pitchShiftWith() {
        let original = PitchShiftParams(id: "ps1", semitones: 0.0, cents: 0.0)
        let copy = original.with(semitones: 5.0)
        #expect(copy.semitones == 5.0)
        #expect(copy.cents == 0.0)
    }

    @Test("CompressorParams with() preserves unchanged fields")
    func compressorWith() {
        let original = CompressorParams(id: "c1")
        let copy = original.with(threshold: -10.0, ratio: 12.0)
        #expect(copy.threshold == -10.0)
        #expect(copy.ratio == 12.0)
        #expect(copy.attack == 0.01) // Preserved
    }

    @Test("DistortionParams with() preserves unchanged fields")
    func distortionWith() {
        let original = DistortionParams(id: "d1")
        let copy = original.with(drive: 0.9, distortionType: .bitcrush)
        #expect(copy.drive == 0.9)
        #expect(copy.distortionType == .bitcrush)
        #expect(copy.mix == 0.5) // Preserved
    }

    @Test("NoiseGateParams with() preserves unchanged fields")
    func noiseGateWith() {
        let original = NoiseGateParams(id: "ng1")
        let copy = original.with(threshold: -60.0)
        #expect(copy.threshold == -60.0)
        #expect(copy.attack == 0.005) // Preserved
    }

    // MARK: - toNativeParams

    @Test("toNativeParams includes type and id for reverb")
    func nativeParamsReverb() {
        let effect = AudioEffect.reverb(ReverbParams(id: "r1", roomSize: 0.7))
        let params = effect.toNativeParams()
        #expect(params["type"] as? String == "reverb")
        #expect(params["id"] as? String == "r1")
        #expect(params["roomSize"] as? Double == 0.7)
    }

    @Test("toNativeParams includes correct fields for echo")
    func nativeParamsEcho() {
        let effect = AudioEffect.echo(EchoParams(id: "e1", delayTime: 0.5, feedback: 0.7))
        let params = effect.toNativeParams()
        #expect(params["type"] as? String == "echo")
        #expect(params["delayTime"] as? Double == 0.5)
        #expect(params["feedback"] as? Double == 0.7)
    }

    @Test("toNativeParams includes distortionType for distortion")
    func nativeParamsDistortion() {
        let effect = AudioEffect.distortion(
            DistortionParams(id: "d1", distortionType: .fuzz)
        )
        let params = effect.toNativeParams()
        #expect(params["distortionType"] as? String == "fuzz")
    }

    // MARK: - Codable Roundtrip

    @Test("Reverb Codable roundtrip")
    func reverbCodable() throws {
        let original = AudioEffect.reverb(
            ReverbParams(id: "r1", mix: 0.5, roomSize: 0.7, damping: 0.3)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEffect.self, from: data)
        #expect(decoded.id == "r1")
        #expect(decoded.type == AudioEffectType.reverb)
        if case .reverb(let p) = decoded {
            #expect(p.mix == 0.5)
            #expect(p.roomSize == 0.7)
            #expect(p.damping == 0.3)
        } else {
            Issue.record("Expected reverb, got \(decoded)")
        }
    }

    @Test("Echo Codable roundtrip")
    func echoCodable() throws {
        let original = AudioEffect.echo(
            EchoParams(id: "e1", delayTime: 0.6, feedback: 0.8)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEffect.self, from: data)
        #expect(decoded.id == "e1")
        #expect(decoded.type == AudioEffectType.echo)
        if case .echo(let p) = decoded {
            #expect(p.delayTime == 0.6)
            #expect(p.feedback == 0.8)
        } else {
            Issue.record("Expected echo, got \(decoded)")
        }
    }

    @Test("PitchShift Codable roundtrip")
    func pitchShiftCodable() throws {
        let original = AudioEffect.pitchShift(
            PitchShiftParams(id: "ps1", semitones: 5.0, cents: 25.0)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEffect.self, from: data)
        #expect(decoded.id == "ps1")
        #expect(decoded.type == AudioEffectType.pitchShift)
        if case .pitchShift(let p) = decoded {
            #expect(p.semitones == 5.0)
            #expect(p.cents == 25.0)
        } else {
            Issue.record("Expected pitchShift, got \(decoded)")
        }
    }

    @Test("EQ Codable roundtrip")
    func eqCodable() throws {
        let original = AudioEffect.eq(
            EQParams(id: "eq1", bassGain: 6.0, midGain: -3.0, trebleGain: 2.0)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEffect.self, from: data)
        #expect(decoded.id == "eq1")
        #expect(decoded.type == AudioEffectType.eq)
        if case .eq(let p) = decoded {
            #expect(p.bassGain == 6.0)
            #expect(p.midGain == -3.0)
            #expect(p.trebleGain == 2.0)
        } else {
            Issue.record("Expected eq, got \(decoded)")
        }
    }

    @Test("Compressor Codable roundtrip")
    func compressorCodable() throws {
        let original = AudioEffect.compressor(
            CompressorParams(id: "c1", threshold: -30.0, ratio: 8.0, makeupGain: 5.0)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEffect.self, from: data)
        #expect(decoded.id == "c1")
        #expect(decoded.type == AudioEffectType.compressor)
        if case .compressor(let p) = decoded {
            #expect(p.threshold == -30.0)
            #expect(p.ratio == 8.0)
            #expect(p.makeupGain == 5.0)
        } else {
            Issue.record("Expected compressor, got \(decoded)")
        }
    }

    @Test("Distortion Codable roundtrip")
    func distortionCodable() throws {
        let original = AudioEffect.distortion(
            DistortionParams(id: "d1", drive: 0.8, distortionType: .bitcrush)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEffect.self, from: data)
        #expect(decoded.id == "d1")
        #expect(decoded.type == AudioEffectType.distortion)
        if case .distortion(let p) = decoded {
            #expect(p.drive == 0.8)
            #expect(p.distortionType == DistortionType.bitcrush)
        } else {
            Issue.record("Expected distortion, got \(decoded)")
        }
    }

    @Test("NoiseGate Codable roundtrip")
    func noiseGateCodable() throws {
        let original = AudioEffect.noiseGate(
            NoiseGateParams(id: "ng1", threshold: -50.0, attack: 0.01, release: 0.1)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioEffect.self, from: data)
        #expect(decoded.id == "ng1")
        #expect(decoded.type == AudioEffectType.noiseGate)
        if case .noiseGate(let p) = decoded {
            #expect(p.threshold == -50.0)
            #expect(p.attack == 0.01)
            #expect(p.release == 0.1)
        } else {
            Issue.record("Expected noiseGate, got \(decoded)")
        }
    }

    // MARK: - Equality (by ID)

    @Test("Effects with same ID are equal regardless of params")
    func equalityById() {
        let a = AudioEffect.reverb(ReverbParams(id: "same", roomSize: 0.3))
        let b = AudioEffect.reverb(ReverbParams(id: "same", roomSize: 0.9))
        #expect(a == b) // Equality is by ID
    }

    @Test("Effects with different IDs are not equal")
    func inequalityById() {
        let a = AudioEffect.reverb(ReverbParams(id: "r1"))
        let b = AudioEffect.reverb(ReverbParams(id: "r2"))
        #expect(a != b)
    }

    // MARK: - AudioEffectChain

    @Test("Empty chain has zero effects")
    func emptyChain() {
        let chain = AudioEffectChain.empty
        #expect(chain.isEmpty)
        #expect(chain.count == 0)
        #expect(chain.enabledCount == 0)
    }

    @Test("Adding effect to chain")
    func addToChain() {
        let chain = AudioEffectChain.empty
        let effect = AudioEffect.reverb(ReverbParams(id: "r1"))
        let updated = chain.adding(effect)
        #expect(updated.count == 1)
        #expect(!updated.isEmpty)
    }

    @Test("Removing effect from chain by ID")
    func removeFromChain() {
        let effect = AudioEffect.reverb(ReverbParams(id: "r1"))
        let chain = AudioEffectChain(effects: [effect])
        let updated = chain.removing(effectId: "r1")
        #expect(updated.isEmpty)
    }

    @Test("Updating effect in chain")
    func updateInChain() {
        let effect = AudioEffect.reverb(ReverbParams(id: "r1", isEnabled: true))
        let chain = AudioEffectChain(effects: [effect])
        let toggled = effect.toggled()
        let updated = chain.updating(toggled)
        #expect(updated.effect(withId: "r1")?.isEnabled == false)
    }

    @Test("Reordering effects in chain")
    func reorderChain() {
        let e1 = AudioEffect.reverb(ReverbParams(id: "r1"))
        let e2 = AudioEffect.echo(EchoParams(id: "e1"))
        let e3 = AudioEffect.distortion(DistortionParams(id: "d1"))
        let chain = AudioEffectChain(effects: [e1, e2, e3])

        let reordered = chain.reordered(from: 0, to: 2)
        #expect(reordered.effects[0].id == "e1")
        #expect(reordered.effects[1].id == "r1")
        #expect(reordered.effects[2].id == "d1")
    }

    @Test("Toggling effect in chain")
    func toggleInChain() {
        let effect = AudioEffect.reverb(ReverbParams(id: "r1", isEnabled: true))
        let chain = AudioEffectChain(effects: [effect])
        let updated = chain.toggling(effectId: "r1")
        #expect(updated.effect(withId: "r1")?.isEnabled == false)
    }

    @Test("enabledCount excludes disabled effects")
    func enabledCount() {
        let e1 = AudioEffect.reverb(ReverbParams(id: "r1", isEnabled: true))
        let e2 = AudioEffect.echo(EchoParams(id: "e1", isEnabled: false))
        let chain = AudioEffectChain(effects: [e1, e2])
        #expect(chain.enabledCount == 1)
    }

    @Test("toNativeParams only includes enabled effects")
    func nativeParamsEnabledOnly() {
        let e1 = AudioEffect.reverb(ReverbParams(id: "r1", isEnabled: true))
        let e2 = AudioEffect.echo(EchoParams(id: "e1", isEnabled: false))
        let chain = AudioEffectChain(effects: [e1, e2])
        let params = chain.toNativeParams()
        #expect(params.count == 1)
        #expect(params[0]["id"] as? String == "r1")
    }
}
