import Foundation

// MARK: - VideoEffect

/// A single video effect with its configuration and keyframes.
///
/// Effects are immutable value objects. Modifications produce
/// new instances via `with(...)`, integrating with the O(1) undo/redo system.
struct VideoEffect: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Effect type.
    let type: EffectType

    /// Whether this effect is enabled for rendering.
    let isEnabled: Bool

    /// Mix/intensity (0.0 = no effect, 1.0 = full effect).
    /// Controls blend with the unaffected input.
    let mix: Double

    /// Parameter values keyed by parameter name.
    let parameters: [String: EffectParameter]

    /// Per-parameter keyframe tracks.
    /// Key is the parameter name, value is the sorted list of keyframes.
    let keyframeTracks: [String: [EffectKeyframe]]

    init(
        id: String,
        type: EffectType,
        isEnabled: Bool = true,
        mix: Double = 1.0,
        parameters: [String: EffectParameter],
        keyframeTracks: [String: [EffectKeyframe]] = [:]
    ) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.mix = mix
        self.parameters = parameters
        self.keyframeTracks = keyframeTracks
    }

    /// Create a new effect with default parameters from the registry.
    static func create(_ type: EffectType) -> VideoEffect {
        VideoEffect(
            id: Foundation.UUID().uuidString,
            type: type,
            parameters: EffectRegistry.defaultParameters(type)
        )
    }

    /// Display name from the effect type.
    var displayName: String { type.displayName }

    /// Category from the effect type.
    var category: EffectCategory { type.category }

    /// SF Symbol icon name.
    var sfSymbol: String { type.sfSymbol }

    /// Whether any parameters have keyframes.
    var hasKeyframes: Bool {
        keyframeTracks.values.contains { !$0.isEmpty }
    }

    /// Total number of keyframes across all parameters.
    var totalKeyframeCount: Int {
        keyframeTracks.values.reduce(0) { $0 + $1.count }
    }

    /// Get the current value of a parameter, considering keyframes at `clipTimeMicros`.
    func getParameterValue(_ paramName: String, clipTimeMicros: TimeMicros? = nil) -> ParameterValue? {
        guard let param = parameters[paramName] else { return nil }

        if let clipTime = clipTimeMicros {
            if let track = keyframeTracks[paramName], !track.isEmpty {
                return resolveKeyframedValue(
                    keyframes: track,
                    clipTimeMicros: clipTime,
                    staticValue: param.currentValue
                )
            }
        }

        return param.currentValue
    }

    /// Get all parameter values resolved at `clipTimeMicros`.
    func resolvedParameters(clipTimeMicros: TimeMicros? = nil) -> [String: ParameterValue] {
        var result: [String: ParameterValue] = [:]
        for key in parameters.keys {
            result[key] = getParameterValue(key, clipTimeMicros: clipTimeMicros)
        }
        return result
    }

    // MARK: - Parameter Operations

    /// Update a single parameter value.
    func updateParameter(_ paramName: String, value: ParameterValue) -> VideoEffect {
        guard let param = parameters[paramName] else { return self }

        let clamped = param.clampValue(value)
        var updated = parameters
        updated[paramName] = param.with(currentValue: clamped)

        return with(parameters: updated)
    }

    /// Reset a parameter to its default value.
    func resetParameter(_ paramName: String) -> VideoEffect {
        guard let param = parameters[paramName] else { return self }

        var updated = parameters
        updated[paramName] = param.reset()

        return with(parameters: updated)
    }

    /// Reset all parameters to defaults.
    func resetAllParameters() -> VideoEffect {
        let updated = parameters.mapValues { $0.reset() }
        return with(parameters: updated, keyframeTracks: [:])
    }

    // MARK: - Keyframe Operations

    /// Add a keyframe to a parameter track.
    func addKeyframe(_ paramName: String, keyframe: EffectKeyframe) -> VideoEffect {
        var tracks = keyframeTracks
        var track = tracks[paramName] ?? []
        track.append(keyframe)
        track.sort { $0.timestampMicros < $1.timestampMicros }
        tracks[paramName] = track
        return with(keyframeTracks: tracks)
    }

    /// Remove a keyframe from a parameter track.
    func removeKeyframe(_ paramName: String, keyframeId: String) -> VideoEffect {
        var tracks = keyframeTracks
        guard var track = tracks[paramName] else { return self }

        track.removeAll { $0.id == keyframeId }
        if track.isEmpty {
            tracks.removeValue(forKey: paramName)
        } else {
            tracks[paramName] = track
        }
        return with(keyframeTracks: tracks)
    }

    /// Update a keyframe in a parameter track.
    func updateKeyframe(_ paramName: String, keyframe: EffectKeyframe) -> VideoEffect {
        var tracks = keyframeTracks
        guard var track = tracks[paramName] else { return self }

        track = track.map { $0.id == keyframe.id ? keyframe : $0 }
        track.sort { $0.timestampMicros < $1.timestampMicros }
        tracks[paramName] = track
        return with(keyframeTracks: tracks)
    }

    /// Clear all keyframes for a parameter.
    func clearKeyframes(_ paramName: String) -> VideoEffect {
        var tracks = keyframeTracks
        tracks.removeValue(forKey: paramName)
        return with(keyframeTracks: tracks)
    }

    /// Clear ALL keyframes across all parameters.
    func clearAllKeyframes() -> VideoEffect {
        with(keyframeTracks: [:])
    }

    /// Partition keyframes at an offset (for clip split operations).
    /// Returns (left, right) with right timestamps adjusted.
    func partitionKeyframes(_ offsetMicros: TimeMicros) -> (
        left: [String: [EffectKeyframe]],
        right: [String: [EffectKeyframe]]
    ) {
        var leftTracks: [String: [EffectKeyframe]] = [:]
        var rightTracks: [String: [EffectKeyframe]] = [:]

        for (paramName, track) in keyframeTracks {
            let leftKfs = track.filter { $0.timestampMicros < offsetMicros }

            let rightKfs = track
                .filter { $0.timestampMicros >= offsetMicros }
                .map { $0.with(timestampMicros: $0.timestampMicros - offsetMicros) }

            if !leftKfs.isEmpty { leftTracks[paramName] = leftKfs }
            if !rightKfs.isEmpty { rightTracks[paramName] = rightKfs }
        }

        return (left: leftTracks, right: rightTracks)
    }

    // MARK: - Copy

    /// Create a copy with updated fields.
    func with(
        id: String? = nil,
        type: EffectType? = nil,
        isEnabled: Bool? = nil,
        mix: Double? = nil,
        parameters: [String: EffectParameter]? = nil,
        keyframeTracks: [String: [EffectKeyframe]]? = nil
    ) -> VideoEffect {
        VideoEffect(
            id: id ?? self.id,
            type: type ?? self.type,
            isEnabled: isEnabled ?? self.isEnabled,
            mix: mix ?? self.mix,
            parameters: parameters ?? self.parameters,
            keyframeTracks: keyframeTracks ?? self.keyframeTracks
        )
    }

    /// Create a duplicate with a new ID.
    func duplicate() -> VideoEffect {
        with(id: Foundation.UUID().uuidString)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, type, isEnabled, mix, parameters, keyframeTracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)

        let typeName = try container.decode(String.self, forKey: .type)
        type = EffectType(rawValue: typeName) ?? .blur

        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        mix = try container.decodeIfPresent(Double.self, forKey: .mix) ?? 1.0
        parameters = try container.decode([String: EffectParameter].self, forKey: .parameters)
        keyframeTracks = try container.decodeIfPresent([String: [EffectKeyframe]].self, forKey: .keyframeTracks) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mix, forKey: .mix)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(keyframeTracks, forKey: .keyframeTracks)
    }

    // MARK: - Equatable

    static func == (lhs: VideoEffect, rhs: VideoEffect) -> Bool {
        guard lhs.id == rhs.id,
              lhs.type == rhs.type,
              lhs.isEnabled == rhs.isEnabled,
              lhs.mix == rhs.mix,
              lhs.parameters == rhs.parameters else {
            return false
        }

        // Compare keyframe tracks
        guard lhs.keyframeTracks.count == rhs.keyframeTracks.count else { return false }
        for (key, lhsTrack) in lhs.keyframeTracks {
            guard let rhsTrack = rhs.keyframeTracks[key],
                  lhsTrack == rhsTrack else {
                return false
            }
        }
        return true
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(type)
        hasher.combine(isEnabled)
        hasher.combine(mix)
        for key in parameters.keys.sorted() {
            hasher.combine(key)
            hasher.combine(parameters[key])
        }
        for key in keyframeTracks.keys.sorted() {
            hasher.combine(key)
            if let track = keyframeTracks[key] {
                for kf in track {
                    hasher.combine(kf)
                }
            }
        }
    }
}
