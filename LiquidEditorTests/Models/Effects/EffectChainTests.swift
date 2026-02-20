import Testing
import Foundation
@testable import LiquidEditor

@Suite("EffectChain Tests")
struct EffectChainTests {

    // MARK: - Helpers

    private func makeEffect(_ type: EffectType, id: String? = nil) -> VideoEffect {
        let effect = VideoEffect.create(type)
        if let id = id {
            return effect.with(id: id)
        }
        return effect
    }

    private func makeBlur(id: String = "blur1") -> VideoEffect {
        makeEffect(.blur, id: id)
    }

    private func makeVignette(id: String = "vig1") -> VideoEffect {
        makeEffect(.vignette, id: id)
    }

    private func makeSharpen(id: String = "sharp1") -> VideoEffect {
        makeEffect(.sharpen, id: id)
    }

    // MARK: - Creation

    @Test("Empty chain has no effects")
    func emptyChain() {
        let chain = EffectChain()
        #expect(chain.length == 0)
        #expect(chain.isEmpty)
        #expect(!chain.isNotEmpty)
        #expect(chain.enabledCount == 0)
        #expect(!chain.hasEnabledEffects)
        #expect(!chain.isAtLimit)
    }

    @Test("Chain with effects")
    func chainWithEffects() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        #expect(chain.length == 2)
        #expect(!chain.isEmpty)
        #expect(chain.isNotEmpty)
    }

    // MARK: - Adding Effects

    @Test("addEffect appends to end")
    func addEffect() {
        let chain = EffectChain()
        let updated = chain.addEffect(makeBlur())
        #expect(updated.length == 1)
        #expect(updated.effects[0].id == "blur1")
    }

    @Test("addEffect respects max limit of 8")
    func addEffectAtLimit() {
        var chain = EffectChain()
        for i in 0..<8 {
            chain = chain.addEffect(makeBlur(id: "blur\(i)"))
        }
        #expect(chain.length == 8)
        #expect(chain.isAtLimit)

        // Adding beyond limit returns the same chain
        let overflow = chain.addEffect(makeBlur(id: "blur8"))
        #expect(overflow.length == 8)
    }

    @Test("insertEffect at specific index")
    func insertEffect() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        let sharpen = makeSharpen()
        let updated = chain.insertEffect(1, effect: sharpen)
        #expect(updated.length == 3)
        #expect(updated.effects[0].id == "blur1")
        #expect(updated.effects[1].id == "sharp1")
        #expect(updated.effects[2].id == "vig1")
    }

    @Test("insertEffect clamps index to valid range")
    func insertEffectClampedIndex() {
        let chain = EffectChain(effects: [makeBlur()])
        let vig = makeVignette()

        // Negative index clamped to 0
        let insertedAtStart = chain.insertEffect(-5, effect: vig)
        #expect(insertedAtStart.effects[0].id == "vig1")

        // Oversized index clamped to end
        let insertedAtEnd = chain.insertEffect(100, effect: vig)
        #expect(insertedAtEnd.effects.last?.id == "vig1")
    }

    @Test("insertEffect respects max limit")
    func insertEffectAtLimit() {
        var chain = EffectChain()
        for i in 0..<8 {
            chain = chain.addEffect(makeBlur(id: "blur\(i)"))
        }
        let overflow = chain.insertEffect(0, effect: makeVignette())
        #expect(overflow.length == 8) // Not inserted
    }

    // MARK: - Removing Effects

    @Test("removeEffect by ID")
    func removeEffect() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        let updated = chain.removeEffect("blur1")
        #expect(updated.length == 1)
        #expect(updated.effects[0].id == "vig1")
    }

    @Test("removeEffect with non-existent ID returns same chain")
    func removeNonExistent() {
        let chain = EffectChain(effects: [makeBlur()])
        let updated = chain.removeEffect("nonexistent")
        #expect(updated.length == 1)
    }

    @Test("removeAt removes by index")
    func removeAt() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette(), makeSharpen()])
        let updated = chain.removeAt(1)
        #expect(updated.length == 2)
        #expect(updated.effects[0].id == "blur1")
        #expect(updated.effects[1].id == "sharp1")
    }

    @Test("removeAt with invalid index returns same chain")
    func removeAtInvalid() {
        let chain = EffectChain(effects: [makeBlur()])
        let sameNeg = chain.removeAt(-1)
        #expect(sameNeg.length == 1)

        let sameOver = chain.removeAt(5)
        #expect(sameOver.length == 1)
    }

    // MARK: - Reordering

    @Test("reorderEffect moves effect from one index to another")
    func reorderEffect() {
        let chain = EffectChain(effects: [
            makeBlur(id: "a"),
            makeVignette(id: "b"),
            makeSharpen(id: "c"),
        ])
        // Move first to last: remove "a" -> [b, c], insert at index 2 -> [b, c, a]
        let updated = chain.reorderEffect(from: 0, to: 2)
        #expect(updated.effects[0].id == "b")
        #expect(updated.effects[1].id == "c")
        #expect(updated.effects[2].id == "a")
    }

    @Test("reorderEffect with invalid oldIndex returns same chain")
    func reorderInvalid() {
        let chain = EffectChain(effects: [makeBlur()])
        let same = chain.reorderEffect(from: -1, to: 0)
        #expect(same.length == 1)

        let same2 = chain.reorderEffect(from: 5, to: 0)
        #expect(same2.length == 1)
    }

    @Test("reorderEffect clamps newIndex")
    func reorderClampNewIndex() {
        let chain = EffectChain(effects: [
            makeBlur(id: "a"),
            makeVignette(id: "b"),
        ])
        // Move to way beyond end -- should clamp to end
        let updated = chain.reorderEffect(from: 0, to: 100)
        #expect(updated.effects[0].id == "b")
        #expect(updated.effects[1].id == "a")
    }

    // MARK: - Update / Toggle / Mix

    @Test("updateEffect replaces effect with matching ID")
    func updateEffect() {
        let chain = EffectChain(effects: [makeBlur()])
        let modified = makeBlur().with(mix: 0.5)
        let updated = chain.updateEffect(modified)
        #expect(updated.effects[0].mix == 0.5)
    }

    @Test("toggleEffect flips enabled state")
    func toggleEffect() {
        let chain = EffectChain(effects: [makeBlur()])
        #expect(chain.effects[0].isEnabled == true)
        let updated = chain.toggleEffect("blur1")
        #expect(updated.effects[0].isEnabled == false)
    }

    @Test("setEffectMix changes mix and clamps to [0, 1]")
    func setEffectMix() {
        let chain = EffectChain(effects: [makeBlur()])
        let updated = chain.setEffectMix("blur1", mix: 0.5)
        #expect(updated.effects[0].mix == 0.5)

        // Clamp above 1
        let clamped = chain.setEffectMix("blur1", mix: 2.0)
        #expect(clamped.effects[0].mix == 1.0)

        // Clamp below 0
        let clampedLow = chain.setEffectMix("blur1", mix: -0.5)
        #expect(clampedLow.effects[0].mix == 0.0)
    }

    // MARK: - Duplicate Effect

    @Test("duplicateEffect creates copy after original")
    func duplicateEffect() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        let updated = chain.duplicateEffect("blur1")
        #expect(updated.length == 3)
        #expect(updated.effects[0].id == "blur1")
        #expect(updated.effects[1].id != "blur1") // New ID
        #expect(updated.effects[1].type == .blur) // Same type
        #expect(updated.effects[2].id == "vig1")
    }

    @Test("duplicateEffect respects max limit")
    func duplicateEffectAtLimit() {
        var chain = EffectChain()
        for i in 0..<8 {
            chain = chain.addEffect(makeBlur(id: "blur\(i)"))
        }
        let result = chain.duplicateEffect("blur0")
        #expect(result.length == 8) // Not duplicated
    }

    @Test("duplicateEffect with non-existent ID returns same chain")
    func duplicateNonExistent() {
        let chain = EffectChain(effects: [makeBlur()])
        let result = chain.duplicateEffect("nonexistent")
        #expect(result.length == 1)
    }

    // MARK: - Enable/Disable/Clear All

    @Test("disableAll disables all effects")
    func disableAll() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        let disabled = chain.disableAll()
        #expect(disabled.enabledCount == 0)
        #expect(!disabled.hasEnabledEffects)
    }

    @Test("enableAll enables all effects")
    func enableAll() {
        let chain = EffectChain(effects: [
            makeBlur().with(isEnabled: false),
            makeVignette().with(isEnabled: false),
        ])
        let enabled = chain.enableAll()
        #expect(enabled.enabledCount == 2)
        #expect(enabled.hasEnabledEffects)
    }

    @Test("clear removes all effects")
    func clearChain() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        let cleared = chain.clear()
        #expect(cleared.isEmpty)
        #expect(cleared.length == 0)
    }

    // MARK: - Lookup

    @Test("getById returns matching effect")
    func getById() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        #expect(chain.getById("blur1")?.type == .blur)
        #expect(chain.getById("vig1")?.type == .vignette)
    }

    @Test("getById returns nil for non-existent")
    func getByIdNil() {
        let chain = EffectChain(effects: [makeBlur()])
        #expect(chain.getById("nonexistent") == nil)
    }

    @Test("effectAt returns effect at index")
    func effectAt() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        #expect(chain.effectAt(0)?.id == "blur1")
        #expect(chain.effectAt(1)?.id == "vig1")
    }

    @Test("effectAt returns nil for invalid index")
    func effectAtInvalid() {
        let chain = EffectChain(effects: [makeBlur()])
        #expect(chain.effectAt(-1) == nil)
        #expect(chain.effectAt(5) == nil)
    }

    @Test("indexOf returns correct index")
    func indexOf() {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        #expect(chain.indexOf("blur1") == 0)
        #expect(chain.indexOf("vig1") == 1)
        #expect(chain.indexOf("nonexistent") == -1)
    }

    // MARK: - Validation

    @Test("validate warns about blur after sharpen")
    func validateBlurAfterSharpen() {
        let chain = EffectChain(effects: [makeSharpen(), makeBlur()])
        let warnings = chain.validate()
        #expect(warnings.contains { $0.contains("Blur after Sharpen") })
    }

    @Test("validate no warning when sharpen is after blur")
    func validateSharpenAfterBlur() {
        let chain = EffectChain(effects: [makeBlur(), makeSharpen()])
        let warnings = chain.validate()
        #expect(!warnings.contains { $0.contains("Blur after Sharpen") })
    }

    @Test("validate warns about many active effects")
    func validateManyEffects() {
        var chain = EffectChain()
        for i in 0..<6 {
            chain = chain.addEffect(makeBlur(id: "blur\(i)"))
        }
        let warnings = chain.validate()
        #expect(warnings.contains { $0.contains("performance") })
    }

    @Test("validate skips disabled effects for blur-after-sharpen check")
    func validateSkipsDisabled() {
        let chain = EffectChain(effects: [
            makeSharpen().with(isEnabled: false),
            makeBlur(),
        ])
        let warnings = chain.validate()
        #expect(!warnings.contains { $0.contains("Blur after Sharpen") })
    }

    // MARK: - Max Effects Constant

    @Test("maxEffects is 8")
    func maxEffectsConstant() {
        #expect(EffectChain.maxEffects == 8)
    }

    @Test("schemaVersion is 1")
    func schemaVersionConstant() {
        #expect(EffectChain.schemaVersion == 1)
    }

    // MARK: - Codable

    @Test("Empty EffectChain Codable roundtrip")
    func emptyCodable() throws {
        let original = EffectChain()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EffectChain.self, from: data)
        #expect(decoded.isEmpty)
    }

    @Test("EffectChain with effects Codable roundtrip")
    func codableRoundtrip() throws {
        let chain = EffectChain(effects: [makeBlur(), makeVignette()])
        let data = try JSONEncoder().encode(chain)
        let decoded = try JSONDecoder().decode(EffectChain.self, from: data)
        #expect(decoded.length == 2)
        #expect(decoded.effects[0].type == EffectType.blur)
        #expect(decoded.effects[1].type == EffectType.vignette)
    }

    // MARK: - Equality

    @Test("Chains with same effects are equal")
    func equality() {
        let a = EffectChain(effects: [makeBlur()])
        let b = EffectChain(effects: [makeBlur()])
        #expect(a == b)
    }

    @Test("Chains with different effects are not equal")
    func inequality() {
        let a = EffectChain(effects: [makeBlur()])
        let b = EffectChain(effects: [makeVignette()])
        #expect(a != b)
    }

    // MARK: - Built-in Presets

    @Test("Built-in presets exist and are non-empty")
    func builtInPresets() {
        let presets = EffectPreset.builtInPresets
        #expect(!presets.isEmpty)
        for preset in presets {
            #expect(!preset.name.isEmpty)
            #expect(preset.isBuiltIn == true)
            #expect(!preset.chain.isEmpty)
        }
    }

    @Test("Dreamy preset has bloom and vignette")
    func dreamyPreset() {
        let presets = EffectPreset.builtInPresets
        let dreamy = presets.first { $0.id == "preset_dreamy" }
        #expect(dreamy != nil)
        #expect(dreamy!.chain.length == 2)
        #expect(dreamy!.chain.effects[0].type == .bloom)
        #expect(dreamy!.chain.effects[1].type == .vignette)
    }

    @Test("Retro preset has film grain and vignette")
    func retroPreset() {
        let presets = EffectPreset.builtInPresets
        let retro = presets.first { $0.id == "preset_retro" }
        #expect(retro != nil)
        #expect(retro!.chain.length == 2)
        #expect(retro!.chain.effects[0].type == .filmGrain)
        #expect(retro!.chain.effects[1].type == .vignette)
    }

    @Test("Crisp preset has sharpen")
    func crispPreset() {
        let presets = EffectPreset.builtInPresets
        let crisp = presets.first { $0.id == "preset_sharp" }
        #expect(crisp != nil)
        #expect(crisp!.chain.length == 1)
        #expect(crisp!.chain.effects[0].type == .sharpen)
    }

    @Test("EffectPreset Codable roundtrip")
    func presetCodable() throws {
        let preset = EffectPreset.builtInPresets[0]
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(EffectPreset.self, from: data)
        #expect(decoded == preset)
    }
}
