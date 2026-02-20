// EffectStore.swift
// LiquidEditor
//
// Per-clip effect chain management with copy/paste.
//
// All mutations produce new EffectChain instances (immutable).
// Integrates with the clip manager for undo/redo semantics.

import Foundation
import Observation

// MARK: - EffectStore

/// Manages per-clip effect chains with undo-aware modifications.
///
/// The store wraps a `ClipEffectRegistry` (dictionary of clipId -> EffectChain)
/// and provides high-level CRUD, copy/paste, and preset operations.
///
/// Thread Safety: `@MainActor` -- all UI-driving state lives on the main thread.
@Observable
@MainActor
final class EffectStore {

    // MARK: - Types

    /// Callback to persist effect chain changes.
    /// The consumer (e.g. timeline manager) implements this to update the clip.
    typealias PersistHandler = (String, EffectChain) -> Void

    // MARK: - Properties

    /// Per-clip effect chains.
    private var registry: [String: EffectChain] = [:]

    /// Clipboard for copy/paste operations.
    private(set) var clipboard: EffectChain?

    /// Callback to persist changes externally.
    var onPersist: PersistHandler?

    // MARK: - Computed

    /// Whether there is an effect chain on the clipboard.
    var hasClipboard: Bool { clipboard != nil && (clipboard?.isNotEmpty ?? false) }

    // MARK: - Queries

    /// Get the effect chain for a clip by ID.
    func getEffectChain(_ clipId: String) -> EffectChain {
        registry[clipId] ?? EffectChain()
    }

    /// Whether a clip has any enabled effects.
    func hasEffects(_ clipId: String) -> Bool {
        getEffectChain(clipId).hasEnabledEffects
    }

    /// Get enabled effect count for a clip.
    func effectCount(_ clipId: String) -> Int {
        getEffectChain(clipId).enabledCount
    }

    // MARK: - Registration

    /// Register a clip's effect chain (e.g. on load).
    func register(_ clipId: String, chain: EffectChain) {
        registry[clipId] = chain
    }

    /// Unregister a clip (e.g. on delete).
    func unregister(_ clipId: String) {
        registry.removeValue(forKey: clipId)
    }

    // MARK: - Mutations

    /// Add an effect to a clip.
    func addEffect(_ clipId: String, effect: VideoEffect) {
        let chain = getEffectChain(clipId).addEffect(effect)
        persistChain(clipId, chain: chain)
    }

    /// Add an effect by type (creates with default parameters).
    @discardableResult
    func addEffectByType(_ clipId: String, type: EffectType) -> VideoEffect {
        let effect = VideoEffect.create(type)
        addEffect(clipId, effect: effect)
        return effect
    }

    /// Remove an effect from a clip.
    func removeEffect(_ clipId: String, effectId: String) {
        let chain = getEffectChain(clipId).removeEffect(effectId)
        persistChain(clipId, chain: chain)
    }

    /// Toggle an effect on/off.
    func toggleEffect(_ clipId: String, effectId: String) {
        let chain = getEffectChain(clipId).toggleEffect(effectId)
        persistChain(clipId, chain: chain)
    }

    /// Reorder an effect in the chain.
    func reorderEffect(_ clipId: String, from oldIndex: Int, to newIndex: Int) {
        let chain = getEffectChain(clipId).reorderEffect(from: oldIndex, to: newIndex)
        persistChain(clipId, chain: chain)
    }

    /// Update an effect's parameter.
    func updateParameter(
        _ clipId: String,
        effectId: String,
        paramName: String,
        value: ParameterValue
    ) {
        let chain = getEffectChain(clipId)
        guard let effect = chain.getById(effectId) else { return }

        let updatedEffect = effect.updateParameter(paramName, value: value)
        let updatedChain = chain.updateEffect(updatedEffect)
        persistChain(clipId, chain: updatedChain)
    }

    /// Set the mix/intensity for an effect.
    func setEffectMix(_ clipId: String, effectId: String, mix: Double) {
        let chain = getEffectChain(clipId).setEffectMix(effectId, mix: mix)
        persistChain(clipId, chain: chain)
    }

    /// Duplicate an effect in the chain.
    func duplicateEffect(_ clipId: String, effectId: String) {
        let chain = getEffectChain(clipId).duplicateEffect(effectId)
        persistChain(clipId, chain: chain)
    }

    /// Replace the entire effect chain for a clip.
    func setEffectChain(_ clipId: String, chain: EffectChain) {
        persistChain(clipId, chain: chain)
    }

    /// Clear all effects from a clip.
    func clearEffects(_ clipId: String) {
        persistChain(clipId, chain: EffectChain())
    }

    // MARK: - Copy/Paste

    /// Copy a clip's effect chain to the clipboard.
    func copyEffects(_ clipId: String) {
        clipboard = getEffectChain(clipId)
    }

    /// Paste the clipboard effect chain to a clip.
    func pasteEffects(_ clipId: String) {
        guard let clip = clipboard, clip.isNotEmpty else { return }

        // Create new IDs for pasted effects to avoid collisions
        let pastedEffects = clip.effects.map { $0.duplicate() }
        persistChain(clipId, chain: EffectChain(effects: pastedEffects))
    }

    /// Paste a single effect from clipboard to a clip.
    func pasteSingleEffect(_ clipId: String, effectIndex: Int) {
        guard let clip = clipboard,
              effectIndex >= 0,
              effectIndex < clip.length else { return }

        let effect = clip.effects[effectIndex].duplicate()
        addEffect(clipId, effect: effect)
    }

    /// Clear the clipboard.
    func clearClipboard() {
        clipboard = nil
    }

    // MARK: - Presets

    /// Apply a preset to a clip.
    func applyPreset(_ clipId: String, preset: EffectPreset) {
        let presetEffects = preset.chain.effects.map { $0.duplicate() }
        persistChain(clipId, chain: EffectChain(effects: presetEffects))
    }

    /// Create a preset from a clip's current effect chain.
    func createPreset(
        _ clipId: String,
        name: String,
        description: String = "",
        category: String = "Custom"
    ) -> EffectPreset {
        let chain = getEffectChain(clipId)
        return EffectPreset(
            id: "user_\(Int(Date().timeIntervalSince1970 * 1000))",
            name: name,
            description: description,
            category: category,
            chain: chain
        )
    }

    // MARK: - Validation

    /// Validate the effect chain for a clip and return warnings.
    func validateChain(_ clipId: String) -> [String] {
        getEffectChain(clipId).validate()
    }

    // MARK: - Private

    private func persistChain(_ clipId: String, chain: EffectChain) {
        registry[clipId] = chain
        onPersist?(clipId, chain)
    }
}
