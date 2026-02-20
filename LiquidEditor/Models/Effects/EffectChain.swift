import Foundation
import os

// MARK: - EffectChain

/// Ordered list of effects applied to a clip.
///
/// The chain represents a sequential processing pipeline:
/// `Source -> [Effect 0] -> [Effect 1] -> ... -> [Effect N] -> Output`
///
/// All operations return new immutable instances, integrating
/// with the O(1) undo/redo system.
struct EffectChain: Codable, Equatable, Hashable, Sendable {
    /// Logger for schema migration warnings.
    private static let logger = Logger(subsystem: "LiquidEditor", category: "EffectChain")

    /// Schema version for forward compatibility.
    static let schemaVersion = 1

    /// Maximum effects per clip (soft limit).
    static let maxEffects = 8

    /// Ordered list of effects.
    let effects: [VideoEffect]

    init(effects: [VideoEffect] = []) {
        self.effects = effects
    }

    /// Number of effects in the chain.
    var length: Int { effects.count }

    /// Whether the chain is empty.
    var isEmpty: Bool { effects.isEmpty }

    /// Whether the chain has effects.
    var isNotEmpty: Bool { !effects.isEmpty }

    /// Number of enabled effects.
    var enabledCount: Int { effects.filter(\.isEnabled).count }

    /// Whether chain has any enabled effects.
    var hasEnabledEffects: Bool { effects.contains { $0.isEnabled } }

    /// Whether the chain is at the soft limit.
    var isAtLimit: Bool { effects.count >= Self.maxEffects }

    /// Get effect by ID.
    func getById(_ effectId: String) -> VideoEffect? {
        effects.first { $0.id == effectId }
    }

    /// Get effect at index.
    func effectAt(_ index: Int) -> VideoEffect? {
        guard index >= 0, index < effects.count else { return nil }
        return effects[index]
    }

    /// Index of effect by ID, or -1 if not found.
    func indexOf(_ effectId: String) -> Int {
        effects.firstIndex { $0.id == effectId } ?? -1
    }

    // MARK: - Chain Operations

    /// Add effect at end of chain.
    func addEffect(_ effect: VideoEffect) -> EffectChain {
        guard effects.count < Self.maxEffects else { return self }
        return EffectChain(effects: effects + [effect])
    }

    /// Insert effect at specific index.
    func insertEffect(_ index: Int, effect: VideoEffect) -> EffectChain {
        guard effects.count < Self.maxEffects else { return self }
        var list = effects
        let clampedIndex = min(max(index, 0), list.count)
        list.insert(effect, at: clampedIndex)
        return EffectChain(effects: list)
    }

    /// Remove effect by ID.
    func removeEffect(_ effectId: String) -> EffectChain {
        EffectChain(effects: effects.filter { $0.id != effectId })
    }

    /// Remove effect at index.
    func removeAt(_ index: Int) -> EffectChain {
        guard index >= 0, index < effects.count else { return self }
        var list = effects
        list.remove(at: index)
        return EffectChain(effects: list)
    }

    /// Move effect from `oldIndex` to `newIndex`.
    func reorderEffect(from oldIndex: Int, to newIndex: Int) -> EffectChain {
        guard oldIndex >= 0, oldIndex < effects.count else { return self }
        var list = effects
        let item = list.remove(at: oldIndex)
        let insertIndex = min(max(newIndex, 0), list.count)
        list.insert(item, at: insertIndex)
        return EffectChain(effects: list)
    }

    /// Update a specific effect.
    func updateEffect(_ updated: VideoEffect) -> EffectChain {
        EffectChain(
            effects: effects.map { $0.id == updated.id ? updated : $0 }
        )
    }

    /// Toggle an effect on/off.
    func toggleEffect(_ effectId: String) -> EffectChain {
        EffectChain(
            effects: effects.map { e in
                e.id == effectId ? e.with(isEnabled: !e.isEnabled) : e
            }
        )
    }

    /// Set mix/intensity for an effect.
    func setEffectMix(_ effectId: String, mix: Double) -> EffectChain {
        EffectChain(
            effects: effects.map { e in
                e.id == effectId ? e.with(mix: min(max(mix, 0.0), 1.0)) : e
            }
        )
    }

    /// Duplicate an effect (copies with new ID, inserts after original).
    func duplicateEffect(_ effectId: String) -> EffectChain {
        guard effects.count < Self.maxEffects else { return self }
        let index = indexOf(effectId)
        guard index != -1 else { return self }

        let duplicate = effects[index].duplicate()
        var list = effects
        list.insert(duplicate, at: index + 1)
        return EffectChain(effects: list)
    }

    /// Disable all effects.
    func disableAll() -> EffectChain {
        EffectChain(effects: effects.map { $0.with(isEnabled: false) })
    }

    /// Enable all effects.
    func enableAll() -> EffectChain {
        EffectChain(effects: effects.map { $0.with(isEnabled: true) })
    }

    /// Remove all effects.
    func clear() -> EffectChain {
        EffectChain()
    }

    // MARK: - Validation

    /// Validate effect chain and return warnings.
    func validate() -> [String] {
        var warnings: [String] = []

        // Check for blur after sharpen
        var hasSharpen = false
        for effect in effects {
            guard effect.isEnabled else { continue }

            if effect.type == .sharpen || effect.type == .unsharpMask {
                hasSharpen = true
            }
            if hasSharpen &&
                (effect.type == .blur || effect.type == .gaussianBlur || effect.type == .motionBlur) {
                warnings.append("Blur after Sharpen may produce artifacts")
            }
        }

        // Check for effect count warning
        if effects.filter(\.isEnabled).count > 5 {
            warnings.append("Many active effects may affect preview performance")
        }

        return warnings
    }

    // MARK: - Native Serialization

    /// Serialize for platform channel transmission to native.
    ///
    /// `clipTimeMicros` is passed through to each effect so keyframe values
    /// can be resolved at the current playback time.
    func toNativeJson(clipTimeMicros: TimeMicros? = nil) -> [[String: Any]] {
        effects
            .filter(\.isEnabled)
            .map { effect in
                var dict: [String: Any] = [
                    "id": effect.id,
                    "type": effect.type.rawValue,
                    "isEnabled": effect.isEnabled,
                    "mix": effect.mix,
                    "ciFilterName": effect.type.ciFilterName,
                ]
                // Resolve parameters, encoding ParameterValue to Any
                var paramDict: [String: Any] = [:]
                let resolved = effect.resolvedParameters(clipTimeMicros: clipTimeMicros)
                for (key, value) in resolved {
                    paramDict[key] = parameterValueToAny(value)
                }
                dict["parameters"] = paramDict
                return dict
            }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case schemaVersion, effects
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        if version > Self.schemaVersion {
            Self.logger.warning("Effect chain schema version \(version) is newer than supported \(Self.schemaVersion)")
        }

        effects = try container.decodeIfPresent([VideoEffect].self, forKey: .effects) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(effects, forKey: .effects)
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: EffectChain, rhs: EffectChain) -> Bool {
        lhs.effects == rhs.effects
    }

    func hash(into hasher: inout Hasher) {
        for effect in effects {
            hasher.combine(effect)
        }
    }
}

// MARK: - EffectPreset

/// A named preset combining multiple effects with pre-configured parameters.
struct EffectPreset: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Display name.
    let name: String

    /// Description.
    let description: String

    /// Category for browsing.
    let category: String

    /// The effect chain template.
    let chain: EffectChain

    /// Whether this is a built-in preset (vs user-created).
    let isBuiltIn: Bool

    init(
        id: String,
        name: String,
        description: String = "",
        category: String = "Custom",
        chain: EffectChain,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.chain = chain
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, description, category, chain, isBuiltIn
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: EffectPreset, rhs: EffectPreset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Built-in presets.
    static var builtInPresets: [EffectPreset] {
        [
            EffectPreset(
                id: "preset_dreamy",
                name: "Dreamy",
                description: "Soft bloom with subtle vignette",
                category: "Creative",
                chain: EffectChain(effects: [
                    VideoEffect.create(.bloom)
                        .updateParameter("intensity", value: .double_(0.4))
                        .updateParameter("radius", value: .double_(15.0))
                        .with(mix: 0.6),
                    VideoEffect.create(.vignette)
                        .updateParameter("intensity", value: .double_(0.3)),
                ]),
                isBuiltIn: true
            ),
            EffectPreset(
                id: "preset_retro",
                name: "Retro Film",
                description: "Film grain with warm tones",
                category: "Creative",
                chain: EffectChain(effects: [
                    VideoEffect.create(.filmGrain)
                        .updateParameter("intensity", value: .double_(0.4))
                        .updateParameter("grainSize", value: .double_(1.5)),
                    VideoEffect.create(.vignette)
                        .updateParameter("intensity", value: .double_(0.5)),
                ]),
                isBuiltIn: true
            ),
            EffectPreset(
                id: "preset_sharp",
                name: "Crisp",
                description: "Enhanced sharpness",
                category: "Enhancement",
                chain: EffectChain(effects: [
                    VideoEffect.create(.sharpen)
                        .updateParameter("sharpness", value: .double_(0.8))
                        .updateParameter("radius", value: .double_(1.5)),
                ]),
                isBuiltIn: true
            ),
        ]
    }
}

// MARK: - Private Helpers

/// Convert a `ParameterValue` to an untyped `Any` for native channel serialization.
private func parameterValueToAny(_ value: ParameterValue) -> Any {
    switch value {
    case .double_(let v): return v
    case .int_(let v): return v
    case .bool_(let v): return v
    case .color(let v): return v
    case .point(let x, let y): return ["x": x, "y": y]
    case .range(let start, let end): return ["start": start, "end": end]
    case .enumChoice(let v): return v
    }
}
