// EffectStoreTests.swift
// LiquidEditorTests
//
// Tests for EffectStore: apply/remove/copy/paste effect chains.

import Testing
@testable import LiquidEditor

@Suite("EffectStore Tests")
@MainActor
struct EffectStoreTests {

    // MARK: - Helpers

    private func makeStore() -> EffectStore {
        let store = EffectStore()
        // Register a clip with an empty chain
        store.register("clip_1", chain: EffectChain())
        store.register("clip_2", chain: EffectChain())
        return store
    }

    // MARK: - Queries

    @Test("Empty chain by default")
    func emptyChain() {
        let store = makeStore()
        #expect(store.getEffectChain("clip_1").isEmpty)
        #expect(!store.hasEffects("clip_1"))
        #expect(store.effectCount("clip_1") == 0)
    }

    @Test("Unregistered clip returns empty chain")
    func unregisteredClip() {
        let store = makeStore()
        let chain = store.getEffectChain("nonexistent")
        #expect(chain.isEmpty)
    }

    // MARK: - Add/Remove

    @Test("Add effect by type")
    func addEffectByType() {
        let store = makeStore()
        let effect = store.addEffectByType("clip_1", type: .blur)

        #expect(store.effectCount("clip_1") == 1)
        #expect(store.hasEffects("clip_1"))
        #expect(effect.type == .blur)
    }

    @Test("Remove effect")
    func removeEffect() {
        let store = makeStore()
        let effect = store.addEffectByType("clip_1", type: .blur)
        store.removeEffect("clip_1", effectId: effect.id)

        #expect(store.effectCount("clip_1") == 0)
    }

    @Test("Toggle effect")
    func toggleEffect() {
        let store = makeStore()
        let effect = store.addEffectByType("clip_1", type: .vignette)

        // Effect starts enabled
        #expect(store.getEffectChain("clip_1").effects.first?.isEnabled == true)

        store.toggleEffect("clip_1", effectId: effect.id)
        #expect(store.getEffectChain("clip_1").effects.first?.isEnabled == false)

        store.toggleEffect("clip_1", effectId: effect.id)
        #expect(store.getEffectChain("clip_1").effects.first?.isEnabled == true)
    }

    // MARK: - Reorder

    @Test("Reorder effects")
    func reorderEffects() {
        let store = makeStore()
        let e1 = store.addEffectByType("clip_1", type: .blur)
        let e2 = store.addEffectByType("clip_1", type: .vignette)

        #expect(store.getEffectChain("clip_1").effects[0].type == .blur)

        store.reorderEffect("clip_1", from: 0, to: 1)
        #expect(store.getEffectChain("clip_1").effects[0].type == .vignette)
    }

    // MARK: - Duplicate

    @Test("Duplicate effect")
    func duplicateEffect() {
        let store = makeStore()
        let effect = store.addEffectByType("clip_1", type: .bloom)
        store.duplicateEffect("clip_1", effectId: effect.id)

        #expect(store.effectCount("clip_1") == 2)
        // Duplicated effect should have different ID
        let chain = store.getEffectChain("clip_1")
        #expect(chain.effects[0].id != chain.effects[1].id)
        #expect(chain.effects[0].type == chain.effects[1].type)
    }

    // MARK: - Mix

    @Test("Set effect mix")
    func setMix() {
        let store = makeStore()
        let effect = store.addEffectByType("clip_1", type: .blur)
        store.setEffectMix("clip_1", effectId: effect.id, mix: 0.5)

        #expect(store.getEffectChain("clip_1").effects.first?.mix == 0.5)
    }

    // MARK: - Clear

    @Test("Clear effects")
    func clearEffects() {
        let store = makeStore()
        store.addEffectByType("clip_1", type: .blur)
        store.addEffectByType("clip_1", type: .vignette)
        store.clearEffects("clip_1")

        #expect(store.effectCount("clip_1") == 0)
    }

    // MARK: - Copy/Paste

    @Test("Copy and paste effects")
    func copyPaste() {
        let store = makeStore()
        store.addEffectByType("clip_1", type: .blur)
        store.addEffectByType("clip_1", type: .vignette)

        #expect(!store.hasClipboard)

        store.copyEffects("clip_1")
        #expect(store.hasClipboard)

        store.pasteEffects("clip_2")
        #expect(store.effectCount("clip_2") == 2)

        // Pasted effects should have new IDs
        let chain1 = store.getEffectChain("clip_1")
        let chain2 = store.getEffectChain("clip_2")
        #expect(chain1.effects[0].id != chain2.effects[0].id)
    }

    @Test("Paste single effect")
    func pasteSingleEffect() {
        let store = makeStore()
        store.addEffectByType("clip_1", type: .blur)
        store.addEffectByType("clip_1", type: .vignette)

        store.copyEffects("clip_1")
        store.pasteSingleEffect("clip_2", effectIndex: 1)

        #expect(store.effectCount("clip_2") == 1)
        #expect(store.getEffectChain("clip_2").effects.first?.type == .vignette)
    }

    @Test("Clear clipboard")
    func clearClipboard() {
        let store = makeStore()
        store.addEffectByType("clip_1", type: .blur)
        store.copyEffects("clip_1")
        #expect(store.hasClipboard)

        store.clearClipboard()
        #expect(!store.hasClipboard)
    }

    // MARK: - Presets

    @Test("Apply preset")
    func applyPreset() {
        let store = makeStore()
        let presets = EffectPreset.builtInPresets
        guard let dreamyPreset = presets.first(where: { $0.id == "preset_dreamy" }) else {
            Issue.record("Dreamy preset not found")
            return
        }

        store.applyPreset("clip_1", preset: dreamyPreset)
        #expect(store.effectCount("clip_1") == 2)
    }

    @Test("Create preset from chain")
    func createPreset() {
        let store = makeStore()
        store.addEffectByType("clip_1", type: .blur)
        store.addEffectByType("clip_1", type: .sharpen)

        let preset = store.createPreset("clip_1", name: "My Preset")
        #expect(preset.name == "My Preset")
        #expect(preset.chain.length == 2)
    }

    // MARK: - Validation

    @Test("Validate chain returns warnings")
    func validateChain() {
        let store = makeStore()

        // Add sharpen then blur (should produce warning)
        store.addEffectByType("clip_1", type: .sharpen)
        store.addEffectByType("clip_1", type: .blur)

        let warnings = store.validateChain("clip_1")
        #expect(warnings.count > 0)
    }

    // MARK: - Persist Handler

    @Test("Persist handler is called on mutations")
    func persistHandler() {
        let store = makeStore()
        var persistedClipId: String?
        var persistedChain: EffectChain?

        store.onPersist = { clipId, chain in
            persistedClipId = clipId
            persistedChain = chain
        }

        store.addEffectByType("clip_1", type: .bloom)
        #expect(persistedClipId == "clip_1")
        #expect(persistedChain?.length == 1)
    }
}
