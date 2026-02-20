// AudioClip.swift
// LiquidEditor
//
// Audio clip - an audio segment from a MediaAsset.
//
// Enhanced with fade, effects chain, volume envelope,
// linked video clip support, pan, and speed control.
//

import Foundation

// MARK: - AudioClip

/// An audio clip on the timeline.
///
/// References a segment of an audio or video MediaAsset,
/// using only the audio track.
struct AudioClip: TimelineItemProtocol, Codable, Equatable, Hashable, Sendable {

    // MARK: - Constants

    /// Minimum duration for split/trim results (100ms).
    static let minDuration: Int64 = 100_000

    // MARK: - Properties

    /// Unique identifier for this clip.
    let id: String

    /// ID of the source MediaAsset.
    let mediaAssetId: String

    /// Start point in source media (microseconds).
    let sourceInMicros: Int64

    /// End point in source media (microseconds).
    let sourceOutMicros: Int64

    /// Optional display name.
    let name: String?

    /// Volume level (0.0 - 2.0, supports boost up to 200%).
    let volume: Double

    /// Whether the audio is muted.
    let isMuted: Bool

    /// Fade in descriptor (nil = no fade in).
    let fadeIn: AudioFade?

    /// Fade out descriptor (nil = no fade out).
    let fadeOut: AudioFade?

    /// Ordered audio effects chain.
    let effects: [AudioEffect]

    /// Volume envelope with keyframes.
    let envelope: VolumeEnvelope

    /// ID of linked video clip (for detached audio).
    let linkedVideoClipId: String?

    /// Playback speed multiplier (0.25 - 4.0, default 1.0).
    let speed: Double

    /// Stereo pan position (-1.0 = full left, 0.0 = center, 1.0 = full right).
    let pan: Double

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        mediaAssetId: String,
        sourceInMicros: Int64,
        sourceOutMicros: Int64,
        name: String? = nil,
        volume: Double = 1.0,
        isMuted: Bool = false,
        fadeIn: AudioFade? = nil,
        fadeOut: AudioFade? = nil,
        effects: [AudioEffect] = [],
        envelope: VolumeEnvelope = VolumeEnvelope(),
        linkedVideoClipId: String? = nil,
        speed: Double = 1.0,
        pan: Double = 0.0
    ) {
        precondition(sourceOutMicros >= sourceInMicros, "Out point must be >= in point")
        self.id = id
        self.mediaAssetId = mediaAssetId
        self.sourceInMicros = sourceInMicros
        self.sourceOutMicros = sourceOutMicros
        self.name = name
        self.volume = volume
        self.isMuted = isMuted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.effects = effects
        self.envelope = envelope
        self.linkedVideoClipId = linkedVideoClipId
        self.speed = speed
        self.pan = pan
    }

    // MARK: - Computed Properties

    /// Duration in microseconds, adjusted for speed.
    var durationMicroseconds: Int64 {
        Int64((Double(sourceOutMicros - sourceInMicros) / speed).rounded())
    }

    /// Human-readable display name.
    var displayName: String {
        name ?? "Audio"
    }

    /// Item type identifier for serialization.
    var itemType: String { "audio" }

    /// Whether this item references external media.
    var isMediaClip: Bool { true }

    /// Effective volume (0 if muted).
    var effectiveVolume: Double {
        isMuted ? 0.0 : volume
    }

    /// Whether this clip has any audio effects.
    var hasEffects: Bool { !effects.isEmpty }

    /// Number of effects in the chain.
    var effectCount: Int { effects.count }

    /// Whether this clip has a volume envelope.
    var hasEnvelope: Bool { !envelope.keyframes.isEmpty }

    /// Whether this clip has a fade in.
    var hasFadeIn: Bool { fadeIn != nil }

    /// Whether this clip has a fade out.
    var hasFadeOut: Bool { fadeOut != nil }

    /// Whether this clip is linked to a video clip.
    var isLinked: Bool { linkedVideoClipId != nil }

    /// Source time range.
    var sourceRange: (start: Int64, end: Int64) {
        (sourceInMicros, sourceOutMicros)
    }

    // MARK: - Copy-With-Modify

    /// Create a copy with optional field overrides.
    ///
    /// To explicitly clear nullable fields to nil, pass the corresponding
    /// `clearFieldName: true` parameter.
    func with(
        id: String? = nil,
        mediaAssetId: String? = nil,
        sourceInMicros: Int64? = nil,
        sourceOutMicros: Int64? = nil,
        name: String? = nil,
        volume: Double? = nil,
        isMuted: Bool? = nil,
        fadeIn: AudioFade? = nil,
        fadeOut: AudioFade? = nil,
        effects: [AudioEffect]? = nil,
        envelope: VolumeEnvelope? = nil,
        linkedVideoClipId: String? = nil,
        speed: Double? = nil,
        pan: Double? = nil,
        clearName: Bool = false,
        clearFadeIn: Bool = false,
        clearFadeOut: Bool = false,
        clearLinkedVideoClipId: Bool = false
    ) -> AudioClip {
        let newVolume = volume ?? self.volume
        let newSpeed = speed ?? self.speed
        let newPan = pan ?? self.pan

        precondition(newVolume >= 0.0 && newVolume <= 2.0, "volume must be in range 0.0-2.0")
        precondition(newSpeed >= 0.25 && newSpeed <= 4.0, "speed must be in range 0.25-4.0")
        precondition(newPan >= -1.0 && newPan <= 1.0, "pan must be in range -1.0 to 1.0")

        return AudioClip(
            id: id ?? self.id,
            mediaAssetId: mediaAssetId ?? self.mediaAssetId,
            sourceInMicros: sourceInMicros ?? self.sourceInMicros,
            sourceOutMicros: sourceOutMicros ?? self.sourceOutMicros,
            name: clearName ? nil : (name ?? self.name),
            volume: newVolume,
            isMuted: isMuted ?? self.isMuted,
            fadeIn: clearFadeIn ? nil : (fadeIn ?? self.fadeIn),
            fadeOut: clearFadeOut ? nil : (fadeOut ?? self.fadeOut),
            effects: effects ?? self.effects,
            envelope: envelope ?? self.envelope,
            linkedVideoClipId: clearLinkedVideoClipId ? nil : (linkedVideoClipId ?? self.linkedVideoClipId),
            speed: newSpeed,
            pan: newPan
        )
    }

    // MARK: - Split Operation

    /// Split clip at offset (relative to clip start).
    ///
    /// Returns (left, right) tuple or nil if offset is invalid.
    /// Minimum duration for each resulting clip is 100ms.
    /// Fade in goes to left clip, fade out goes to right clip.
    func splitAt(_ offsetMicros: Int64) -> (left: AudioClip, right: AudioClip)? {
        guard offsetMicros >= Self.minDuration,
              offsetMicros <= durationMicroseconds - Self.minDuration else {
            return nil
        }

        // Convert timeline offset to source offset accounting for speed
        let sourceOffset = Int64((Double(offsetMicros) * speed).rounded())
        let splitSourceTime = sourceInMicros + sourceOffset

        // Redistribute fades: fade-in stays on left, fade-out stays on right
        let effectiveFadeIn: AudioFade?
        if let fi = fadeIn, fi.durationMicros > offsetMicros {
            effectiveFadeIn = fi.with(durationMicros: offsetMicros)
        } else {
            effectiveFadeIn = fadeIn
        }

        let remainingDuration = durationMicroseconds - offsetMicros
        let effectiveFadeOut: AudioFade?
        if let fo = fadeOut, fo.durationMicros > remainingDuration {
            effectiveFadeOut = fo.with(durationMicros: remainingDuration)
        } else {
            effectiveFadeOut = fadeOut
        }

        // Split envelope keyframes
        let leftKeyframes = envelope.keyframes
            .filter { $0.time < offsetMicros }
        let rightKeyframes = envelope.keyframes
            .filter { $0.time >= offsetMicros }
            .map { $0.with(time: $0.time - offsetMicros) }

        let left = AudioClip(
            id: UUID().uuidString,
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceInMicros,
            sourceOutMicros: splitSourceTime,
            name: name.map { "\($0) (1)" },
            volume: volume,
            isMuted: isMuted,
            fadeIn: effectiveFadeIn,
            fadeOut: nil,
            effects: effects,
            envelope: VolumeEnvelope(keyframes: leftKeyframes),
            speed: speed,
            pan: pan
        )

        let right = AudioClip(
            id: UUID().uuidString,
            mediaAssetId: mediaAssetId,
            sourceInMicros: splitSourceTime,
            sourceOutMicros: sourceOutMicros,
            name: name.map { "\($0) (2)" },
            volume: volume,
            isMuted: isMuted,
            fadeIn: nil,
            fadeOut: effectiveFadeOut,
            effects: effects,
            envelope: VolumeEnvelope(keyframes: rightKeyframes),
            speed: speed,
            pan: pan
        )

        return (left: left, right: right)
    }

    // MARK: - Trim Operations

    /// Trim start of clip.
    func trimStart(_ newInMicros: Int64) -> AudioClip? {
        guard newInMicros > sourceInMicros,
              newInMicros < sourceOutMicros else {
            return nil
        }

        guard sourceOutMicros - newInMicros >= Self.minDuration else {
            return nil
        }

        let trimAmountMicros = Int64((Double(newInMicros - sourceInMicros) / speed).rounded())

        // Adjust fade-in if it extends past the new duration
        let newDuration = Int64((Double(sourceOutMicros - newInMicros) / speed).rounded())
        let adjustedFadeIn: AudioFade?
        if let fi = fadeIn, fi.durationMicros > newDuration {
            adjustedFadeIn = fi.with(durationMicros: newDuration / 2)
        } else {
            adjustedFadeIn = fadeIn
        }

        // Shift envelope keyframes
        let newKeyframes = envelope.keyframes
            .filter { $0.time >= trimAmountMicros }
            .map { $0.with(time: $0.time - trimAmountMicros) }

        return AudioClip(
            id: id,
            mediaAssetId: mediaAssetId,
            sourceInMicros: newInMicros,
            sourceOutMicros: sourceOutMicros,
            name: name,
            volume: volume,
            isMuted: isMuted,
            fadeIn: adjustedFadeIn,
            fadeOut: fadeOut,
            effects: effects,
            envelope: VolumeEnvelope(keyframes: newKeyframes),
            linkedVideoClipId: linkedVideoClipId,
            speed: speed,
            pan: pan
        )
    }

    /// Trim end of clip.
    func trimEnd(_ newOutMicros: Int64) -> AudioClip? {
        guard newOutMicros < sourceOutMicros,
              newOutMicros > sourceInMicros else {
            return nil
        }

        guard newOutMicros - sourceInMicros >= Self.minDuration else {
            return nil
        }

        let newDuration = Int64((Double(newOutMicros - sourceInMicros) / speed).rounded())

        // Adjust fade-out if it extends past the new duration
        let adjustedFadeOut: AudioFade?
        if let fo = fadeOut, fo.durationMicros > newDuration {
            adjustedFadeOut = fo.with(durationMicros: newDuration / 2)
        } else {
            adjustedFadeOut = fadeOut
        }

        // Remove keyframes beyond new duration
        let newKeyframes = envelope.keyframes
            .filter { $0.time < newDuration }

        return AudioClip(
            id: id,
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceInMicros,
            sourceOutMicros: newOutMicros,
            name: name,
            volume: volume,
            isMuted: isMuted,
            fadeIn: fadeIn,
            fadeOut: adjustedFadeOut,
            effects: effects,
            envelope: VolumeEnvelope(keyframes: newKeyframes),
            linkedVideoClipId: linkedVideoClipId,
            speed: speed,
            pan: pan
        )
    }

    // MARK: - Convenience Methods

    /// Set volume level (clamped to 0.0 - 2.0).
    func withVolume(_ newVolume: Double) -> AudioClip {
        with(volume: min(max(newVolume, 0.0), 2.0))
    }

    /// Toggle mute.
    func withMuted(_ muted: Bool) -> AudioClip {
        with(isMuted: muted)
    }

    /// Set speed (clamped to 0.25 - 4.0).
    func withSpeed(_ newSpeed: Double) -> AudioClip {
        with(speed: min(max(newSpeed, 0.25), 4.0))
    }

    /// Set pan (clamped to -1.0 - 1.0).
    func withPan(_ newPan: Double) -> AudioClip {
        with(pan: min(max(newPan, -1.0), 1.0))
    }

    /// Set fade in.
    func withFadeIn(_ fade: AudioFade?) -> AudioClip {
        fade == nil ? with(clearFadeIn: true) : with(fadeIn: fade)
    }

    /// Set fade out.
    func withFadeOut(_ fade: AudioFade?) -> AudioClip {
        fade == nil ? with(clearFadeOut: true) : with(fadeOut: fade)
    }

    /// Add an effect to the chain.
    func addingEffect(_ effect: AudioEffect) -> AudioClip {
        with(effects: effects + [effect])
    }

    /// Remove an effect by ID.
    func removingEffect(_ effectId: String) -> AudioClip {
        with(effects: effects.filter { $0.id != effectId })
    }

    /// Update an effect in the chain.
    func updatingEffect(_ effect: AudioEffect) -> AudioClip {
        with(effects: effects.map { e in
            e.id == effect.id ? effect : e
        })
    }

    // MARK: - Duplication

    /// Create a duplicate with new ID.
    func duplicate() -> AudioClip {
        AudioClip(
            id: UUID().uuidString,
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceInMicros,
            sourceOutMicros: sourceOutMicros,
            name: name.map { "\($0) (copy)" },
            volume: volume,
            isMuted: isMuted,
            fadeIn: fadeIn,
            fadeOut: fadeOut,
            effects: effects,
            envelope: envelope,
            speed: speed,
            pan: pan
        )
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case mediaAssetId
        case sourceInMicros
        case sourceOutMicros
        case name
        case volume
        case isMuted
        case fadeIn
        case fadeOut
        case effects
        case envelope
        case linkedVideoClipId
        case speed
        case pan
        case itemType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(id, forKey: .id)
        try container.encode(mediaAssetId, forKey: .mediaAssetId)
        try container.encode(sourceInMicros, forKey: .sourceInMicros)
        try container.encode(sourceOutMicros, forKey: .sourceOutMicros)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(volume, forKey: .volume)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encodeIfPresent(fadeIn, forKey: .fadeIn)
        try container.encodeIfPresent(fadeOut, forKey: .fadeOut)
        if !effects.isEmpty {
            try container.encode(effects, forKey: .effects)
        }
        if !envelope.keyframes.isEmpty {
            try container.encode(envelope, forKey: .envelope)
        }
        try container.encodeIfPresent(linkedVideoClipId, forKey: .linkedVideoClipId)
        try container.encode(speed, forKey: .speed)
        try container.encode(pan, forKey: .pan)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mediaAssetId = try container.decode(String.self, forKey: .mediaAssetId)
        sourceInMicros = try container.decode(Int64.self, forKey: .sourceInMicros)
        sourceOutMicros = try container.decode(Int64.self, forKey: .sourceOutMicros)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        fadeIn = try container.decodeIfPresent(AudioFade.self, forKey: .fadeIn)
        fadeOut = try container.decodeIfPresent(AudioFade.self, forKey: .fadeOut)
        effects = try container.decodeIfPresent([AudioEffect].self, forKey: .effects) ?? []
        envelope = try container.decodeIfPresent(VolumeEnvelope.self, forKey: .envelope) ?? VolumeEnvelope()
        linkedVideoClipId = try container.decodeIfPresent(String.self, forKey: .linkedVideoClipId)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        pan = try container.decodeIfPresent(Double.self, forKey: .pan) ?? 0.0
    }

    // MARK: - CustomStringConvertible

    var description: String {
        let durationMs = durationMicroseconds / 1000
        let volPercent = Int((volume * 100).rounded())
        return "AudioClip(\(id), asset=\(mediaAssetId), \(durationMs)ms, vol=\(volPercent)%, speed=\(speed)x)"
    }
}
