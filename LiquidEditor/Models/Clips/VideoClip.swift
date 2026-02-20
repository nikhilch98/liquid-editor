// VideoClip.swift
// LiquidEditor
//
// Video clip - a segment from a video MediaAsset.
//
// Video clips reference a portion of a source video file,
// defined by in/out points. They can have keyframes attached
// for transform animations and an effect chain for video effects.
//

import Foundation
import CoreGraphics

// MARK: - VideoClip

/// A video clip on the timeline.
///
/// References a segment of a MediaAsset video file.
/// Has optional keyframes for pan/zoom/rotate animations
/// and an optional effect chain for video effects.
struct VideoClip: TimelineItemProtocol, Codable, Equatable, Hashable, Sendable {

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

    /// Keyframes for this clip (timestamps relative to clip start).
    let keyframes: [Keyframe]

    /// Optional display name override.
    let name: String?

    /// Effect chain applied to this clip.
    let effectChain: EffectChain

    /// Speed settings for variable speed / slow-mo / reverse.
    let speedSettings: SpeedConfig?

    /// Masks applied to this clip for selective effect application.
    let masks: [Mask]?

    /// Pan & scan (Ken Burns effect) keyframes for animated crop regions.
    let panScanKeyframes: PanScanConfig?

    /// ID of an associated motion tracking path.
    let trackingPathId: String?

    /// Multi-cam group ID for grouping clips in multi-camera editing.
    let multiCamGroupId: String?

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        mediaAssetId: String,
        sourceInMicros: Int64,
        sourceOutMicros: Int64,
        keyframes: [Keyframe] = [],
        name: String? = nil,
        effectChain: EffectChain = EffectChain(),
        speedSettings: SpeedConfig? = nil,
        masks: [Mask]? = nil,
        panScanKeyframes: PanScanConfig? = nil,
        trackingPathId: String? = nil,
        multiCamGroupId: String? = nil
    ) {
        precondition(sourceOutMicros >= sourceInMicros, "Out point must be >= in point")
        self.id = id
        self.mediaAssetId = mediaAssetId
        self.sourceInMicros = sourceInMicros
        self.sourceOutMicros = sourceOutMicros
        self.keyframes = keyframes
        self.name = name
        self.effectChain = effectChain
        self.speedSettings = speedSettings
        self.masks = masks
        self.panScanKeyframes = panScanKeyframes
        self.trackingPathId = trackingPathId
        self.multiCamGroupId = multiCamGroupId
    }

    // MARK: - Computed Properties

    /// Duration in microseconds (source out - source in).
    var durationMicroseconds: Int64 {
        sourceOutMicros - sourceInMicros
    }

    /// Human-readable display name.
    var displayName: String {
        name ?? "Video Clip"
    }

    /// Item type identifier for serialization.
    var itemType: String { "video" }

    /// Whether this item references external media.
    var isMediaClip: Bool { true }

    /// Whether this clip has any keyframes.
    var hasKeyframes: Bool { !keyframes.isEmpty }

    /// Number of keyframes.
    var keyframeCount: Int { keyframes.count }

    /// Whether this clip has custom speed settings.
    var hasSpeedSettings: Bool {
        guard let settings = speedSettings else { return false }
        return !settings.isDefault
    }

    /// Whether this clip has masks.
    var hasMasks: Bool {
        guard let m = masks else { return false }
        return !m.isEmpty
    }

    /// Whether this clip has pan & scan animation.
    var hasPanScan: Bool {
        guard let ps = panScanKeyframes else { return false }
        return ps.isEnabled
    }

    /// Whether this clip has a tracking path associated.
    var hasTrackingPath: Bool { trackingPathId != nil }

    /// Whether this clip is part of a multi-cam group.
    var isMultiCam: Bool { multiCamGroupId != nil }

    /// Whether this clip has any enabled effects.
    var hasEffects: Bool { effectChain.hasEnabledEffects }

    /// Number of enabled effects.
    var effectCount: Int { effectChain.enabledCount }

    /// Source time range.
    var sourceRange: (start: Int64, end: Int64) {
        (sourceInMicros, sourceOutMicros)
    }

    /// Get keyframes sorted by timestamp.
    var sortedKeyframes: [Keyframe] {
        keyframes.sorted { $0.timestampMicros < $1.timestampMicros }
    }

    // MARK: - Source Time Mapping

    /// Map timeline offset (relative to clip start) to source time.
    func timelineToSource(_ offsetMicros: Int64) -> Int64 {
        sourceInMicros + offsetMicros
    }

    /// Map source time to timeline offset (relative to clip start).
    func sourceToTimeline(_ sourceMicros: Int64) -> Int64 {
        sourceMicros - sourceInMicros
    }

    /// Whether a source time is within this clip's range.
    func containsSourceTime(_ sourceMicros: Int64) -> Bool {
        sourceMicros >= sourceInMicros && sourceMicros < sourceOutMicros
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
        keyframes: [Keyframe]? = nil,
        name: String? = nil,
        effectChain: EffectChain? = nil,
        speedSettings: SpeedConfig? = nil,
        masks: [Mask]? = nil,
        panScanKeyframes: PanScanConfig? = nil,
        trackingPathId: String? = nil,
        multiCamGroupId: String? = nil,
        clearName: Bool = false,
        clearSpeedSettings: Bool = false,
        clearMasks: Bool = false,
        clearPanScanKeyframes: Bool = false,
        clearTrackingPathId: Bool = false,
        clearMultiCamGroupId: Bool = false
    ) -> VideoClip {
        VideoClip(
            id: id ?? self.id,
            mediaAssetId: mediaAssetId ?? self.mediaAssetId,
            sourceInMicros: sourceInMicros ?? self.sourceInMicros,
            sourceOutMicros: sourceOutMicros ?? self.sourceOutMicros,
            keyframes: keyframes ?? self.keyframes,
            name: clearName ? nil : (name ?? self.name),
            effectChain: effectChain ?? self.effectChain,
            speedSettings: clearSpeedSettings ? nil : (speedSettings ?? self.speedSettings),
            masks: clearMasks ? nil : (masks ?? self.masks),
            panScanKeyframes: clearPanScanKeyframes ? nil : (panScanKeyframes ?? self.panScanKeyframes),
            trackingPathId: clearTrackingPathId ? nil : (trackingPathId ?? self.trackingPathId),
            multiCamGroupId: clearMultiCamGroupId ? nil : (multiCamGroupId ?? self.multiCamGroupId)
        )
    }

    // MARK: - Split Operation

    /// Split clip at offset (relative to clip start).
    ///
    /// Returns (left, right) tuple or nil if offset is invalid.
    /// Minimum duration for each resulting clip is 100ms.
    /// Effect chain is duplicated to both halves.
    func splitAt(_ offsetMicros: Int64) -> (left: VideoClip, right: VideoClip)? {
        guard offsetMicros >= Self.minDuration,
              offsetMicros <= durationMicroseconds - Self.minDuration else {
            return nil
        }

        let splitSourceTime = sourceInMicros + offsetMicros

        // Partition keyframes
        let leftKeyframes = keyframes
            .filter { $0.timestampMicros < offsetMicros }

        let rightKeyframes = keyframes
            .filter { $0.timestampMicros >= offsetMicros }
            .map { kf in
                Keyframe(
                    id: kf.id,
                    timestampMicros: kf.timestampMicros - offsetMicros,
                    transform: kf.transform,
                    interpolation: kf.interpolation,
                    bezierPoints: kf.bezierPoints,
                    label: kf.label,
                    createdAt: kf.createdAt
                )
            }

        let left = VideoClip(
            id: UUID().uuidString,
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceInMicros,
            sourceOutMicros: splitSourceTime,
            keyframes: leftKeyframes,
            name: name.map { "\($0) (1)" },
            effectChain: effectChain,
            speedSettings: speedSettings,
            masks: masks,
            panScanKeyframes: panScanKeyframes,
            trackingPathId: trackingPathId,
            multiCamGroupId: multiCamGroupId
        )

        let right = VideoClip(
            id: UUID().uuidString,
            mediaAssetId: mediaAssetId,
            sourceInMicros: splitSourceTime,
            sourceOutMicros: sourceOutMicros,
            keyframes: rightKeyframes,
            name: name.map { "\($0) (2)" },
            effectChain: effectChain,
            speedSettings: speedSettings,
            masks: masks,
            panScanKeyframes: panScanKeyframes,
            trackingPathId: trackingPathId,
            multiCamGroupId: multiCamGroupId
        )

        return (left: left, right: right)
    }

    // MARK: - Trim Operations

    /// Trim start of clip, returns new clip or nil if invalid.
    ///
    /// `newInMicros` is the new source in point (not offset).
    func trimStart(_ newInMicros: Int64) -> VideoClip? {
        guard newInMicros > sourceInMicros,
              newInMicros < sourceOutMicros else {
            return nil
        }

        guard sourceOutMicros - newInMicros >= Self.minDuration else {
            return nil
        }

        let trimAmount = newInMicros - sourceInMicros

        // Remove keyframes before trim, adjust remaining timestamps
        let newKeyframes = keyframes
            .filter { $0.timestampMicros >= trimAmount }
            .map { kf in
                Keyframe(
                    id: kf.id,
                    timestampMicros: kf.timestampMicros - trimAmount,
                    transform: kf.transform,
                    interpolation: kf.interpolation,
                    bezierPoints: kf.bezierPoints,
                    label: kf.label,
                    createdAt: kf.createdAt
                )
            }

        return VideoClip(
            id: id, // Keep same ID for trim
            mediaAssetId: mediaAssetId,
            sourceInMicros: newInMicros,
            sourceOutMicros: sourceOutMicros,
            keyframes: newKeyframes,
            name: name,
            effectChain: effectChain,
            speedSettings: speedSettings,
            masks: masks,
            panScanKeyframes: panScanKeyframes,
            trackingPathId: trackingPathId,
            multiCamGroupId: multiCamGroupId
        )
    }

    /// Trim end of clip, returns new clip or nil if invalid.
    ///
    /// `newOutMicros` is the new source out point.
    func trimEnd(_ newOutMicros: Int64) -> VideoClip? {
        guard newOutMicros < sourceOutMicros,
              newOutMicros > sourceInMicros else {
            return nil
        }

        guard newOutMicros - sourceInMicros >= Self.minDuration else {
            return nil
        }

        let newDuration = newOutMicros - sourceInMicros

        // Remove keyframes after trim
        let newKeyframes = keyframes
            .filter { $0.timestampMicros < newDuration }

        return VideoClip(
            id: id, // Keep same ID for trim
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceInMicros,
            sourceOutMicros: newOutMicros,
            keyframes: newKeyframes,
            name: name,
            effectChain: effectChain,
            speedSettings: speedSettings,
            masks: masks,
            panScanKeyframes: panScanKeyframes,
            trackingPathId: trackingPathId,
            multiCamGroupId: multiCamGroupId
        )
    }

    // MARK: - Keyframe Operations

    /// Add a keyframe.
    func addingKeyframe(_ keyframe: Keyframe) -> VideoClip {
        with(keyframes: keyframes + [keyframe])
    }

    /// Remove a keyframe by ID.
    func removingKeyframe(_ keyframeId: String) -> VideoClip {
        with(keyframes: keyframes.filter { $0.id != keyframeId })
    }

    /// Update a keyframe.
    func updatingKeyframe(_ keyframe: Keyframe) -> VideoClip {
        with(keyframes: keyframes.map { kf in
            kf.id == keyframe.id ? keyframe : kf
        })
    }

    /// Clear all keyframes.
    func clearingKeyframes() -> VideoClip {
        with(keyframes: [])
    }

    // MARK: - Effect Chain Operations

    /// Update the effect chain.
    func withEffectChain(_ chain: EffectChain) -> VideoClip {
        with(effectChain: chain)
    }

    /// Add an effect to the chain.
    func addingEffect(_ effect: VideoEffect) -> VideoClip {
        withEffectChain(effectChain.addEffect(effect))
    }

    /// Remove an effect from the chain.
    func removingEffect(_ effectId: String) -> VideoClip {
        withEffectChain(effectChain.removeEffect(effectId))
    }

    /// Toggle an effect on/off.
    func togglingEffect(_ effectId: String) -> VideoClip {
        withEffectChain(effectChain.toggleEffect(effectId))
    }

    /// Clear all effects.
    func clearingEffects() -> VideoClip {
        withEffectChain(EffectChain())
    }

    // MARK: - Duplication

    /// Create a duplicate with new ID.
    func duplicate() -> VideoClip {
        VideoClip(
            id: UUID().uuidString,
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceInMicros,
            sourceOutMicros: sourceOutMicros,
            keyframes: keyframes,
            name: name.map { "\($0) (copy)" },
            effectChain: effectChain,
            speedSettings: speedSettings,
            masks: masks,
            panScanKeyframes: panScanKeyframes,
            trackingPathId: trackingPathId,
            multiCamGroupId: multiCamGroupId
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
        case keyframes
        case name
        case effectChain
        case speedSettings
        case masks
        case panScanKeyframes
        case trackingPathId
        case multiCamGroupId
        case itemType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(id, forKey: .id)
        try container.encode(mediaAssetId, forKey: .mediaAssetId)
        try container.encode(sourceInMicros, forKey: .sourceInMicros)
        try container.encode(sourceOutMicros, forKey: .sourceOutMicros)
        try container.encode(keyframes, forKey: .keyframes)
        try container.encodeIfPresent(name, forKey: .name)
        if effectChain.isNotEmpty {
            try container.encode(effectChain, forKey: .effectChain)
        }
        try container.encodeIfPresent(speedSettings, forKey: .speedSettings)
        if let masks = masks, !masks.isEmpty {
            try container.encode(masks, forKey: .masks)
        }
        try container.encodeIfPresent(panScanKeyframes, forKey: .panScanKeyframes)
        try container.encodeIfPresent(trackingPathId, forKey: .trackingPathId)
        try container.encodeIfPresent(multiCamGroupId, forKey: .multiCamGroupId)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mediaAssetId = try container.decode(String.self, forKey: .mediaAssetId)
        sourceInMicros = try container.decode(Int64.self, forKey: .sourceInMicros)
        sourceOutMicros = try container.decode(Int64.self, forKey: .sourceOutMicros)
        keyframes = try container.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        name = try container.decodeIfPresent(String.self, forKey: .name)
        effectChain = try container.decodeIfPresent(EffectChain.self, forKey: .effectChain) ?? EffectChain()
        speedSettings = try container.decodeIfPresent(SpeedConfig.self, forKey: .speedSettings)
        masks = try container.decodeIfPresent([Mask].self, forKey: .masks)
        panScanKeyframes = try container.decodeIfPresent(PanScanConfig.self, forKey: .panScanKeyframes)
        trackingPathId = try container.decodeIfPresent(String.self, forKey: .trackingPathId)
        multiCamGroupId = try container.decodeIfPresent(String.self, forKey: .multiCamGroupId)
    }

    // MARK: - CustomStringConvertible

    var description: String {
        let durationMs = durationMicroseconds / 1000
        return "VideoClip(\(id), asset=\(mediaAssetId), \(durationMs)ms, \(keyframes.count) keyframes, \(effectChain.length) effects)"
    }
}
