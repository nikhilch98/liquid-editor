// TimelineClip.swift
// LiquidEditor
//
// Enhanced timeline clip model for UI rendering.
// This wraps the underlying clip model with rendering metadata.
//

import Foundation
import CoreGraphics

// MARK: - ClipType

/// Type of clip content.
enum ClipType: String, Codable, Equatable, Hashable, Sendable {
    case video
    case audio
    case image
    case text
    case effect
    case gap
    case color

    /// Whether this type shows thumbnails.
    var showsThumbnails: Bool {
        self == .video || self == .image
    }

    /// Whether this type shows waveform.
    var showsWaveform: Bool {
        self == .audio
    }
}

// MARK: - TimelineClip

/// Immutable timeline clip for UI rendering.
/// This wraps the underlying clip model with rendering metadata.
struct TimelineClip: Codable, Equatable, Hashable, Sendable, Identifiable {

    // MARK: - Constants

    /// Minimum duration for any clip (approximately 1 frame at 30fps).
    ///
    /// Threshold Derivation:
    /// - 33,333 microseconds = 1/30 second = 1 frame at 30fps.
    /// - Prevents clips from becoming zero-length or "invisible".
    /// - Matches industry standard minimum (Final Cut Pro, Premiere use ~1 frame).
    static let minDuration: TimeMicros = 33_333

    // MARK: - Identity

    /// Unique clip identifier.
    let id: String

    /// Media asset ID (nil for generator clips).
    let mediaAssetId: String?

    /// Track ID this clip belongs to.
    let trackId: String

    /// Type of clip.
    let type: ClipType

    // MARK: - Timeline Position

    /// Start time on timeline (microseconds).
    let startTime: TimeMicros

    /// Duration on timeline (microseconds).
    let duration: TimeMicros

    // MARK: - Source Range

    /// In point in source media (microseconds).
    let sourceIn: TimeMicros

    /// Out point in source media (microseconds).
    let sourceOut: TimeMicros

    // MARK: - Speed & Direction

    /// Playback speed (1.0 = normal, 0.5 = half, 2.0 = double).
    let speed: Double

    /// Whether playback is reversed.
    let isReversed: Bool

    // MARK: - Visual Properties

    /// Clip background color as ARGB int.
    let clipColorValue: UInt32

    /// Optional clip label/name.
    let label: String?

    // MARK: - Links

    /// Linked clip ID (for A/V sync).
    let linkedClipId: String?

    // MARK: - Metadata

    /// Whether media file is offline/missing.
    let isOffline: Bool

    /// Whether clip has effects applied.
    let hasEffects: Bool

    /// Whether clip has keyframes.
    let hasKeyframes: Bool

    /// Number of effects on clip.
    let effectCount: Int

    /// Whether clip has audio.
    let hasAudio: Bool

    /// Audio volume (0.0-1.0).
    let volume: Double

    /// Whether audio is muted.
    let isMuted: Bool

    /// Color value for color clips.
    let colorValue: UInt32?

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        mediaAssetId: String? = nil,
        trackId: String,
        type: ClipType,
        startTime: TimeMicros,
        duration: TimeMicros,
        sourceIn: TimeMicros = 0,
        sourceOut: TimeMicros? = nil,
        speed: Double = 1.0,
        isReversed: Bool = false,
        clipColorValue: UInt32? = nil,
        label: String? = nil,
        linkedClipId: String? = nil,
        isOffline: Bool = false,
        hasEffects: Bool = false,
        hasKeyframes: Bool = false,
        effectCount: Int = 0,
        hasAudio: Bool = false,
        volume: Double = 1.0,
        isMuted: Bool = false,
        colorValue: UInt32? = nil
    ) {
        self.id = id
        self.mediaAssetId = mediaAssetId
        self.trackId = trackId
        self.type = type
        self.startTime = startTime
        self.duration = duration
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut ?? (sourceIn + duration)
        self.speed = speed
        self.isReversed = isReversed
        self.clipColorValue = clipColorValue ?? 0xFF808080
        self.label = label
        self.linkedClipId = linkedClipId
        self.isOffline = isOffline
        self.hasEffects = hasEffects
        self.hasKeyframes = hasKeyframes
        self.effectCount = effectCount
        self.hasAudio = hasAudio
        self.volume = volume
        self.isMuted = isMuted
        self.colorValue = colorValue
    }

    // MARK: - Computed Properties

    /// End time on timeline.
    var endTime: TimeMicros { startTime + duration }

    /// Time range on timeline.
    var timeRange: TimeRange { TimeRange(startTime, endTime) }

    /// Source duration (between in and out points).
    var sourceDuration: TimeMicros { sourceOut - sourceIn }

    /// Check if this is a generator clip (no source media).
    var isGeneratorClip: Bool {
        type == .gap || type == .color || type == .text
    }

    /// Check if time is within clip.
    func containsTime(_ time: TimeMicros) -> Bool {
        time >= startTime && time < endTime
    }

    /// Check if clip overlaps with time range.
    func overlapsRange(_ range: TimeRange) -> Bool {
        timeRange.overlaps(range)
    }

    /// Map timeline time to source time.
    func timelineToSource(_ timelineTime: TimeMicros) -> TimeMicros {
        let offsetFromStart = timelineTime - startTime
        let scaledOffset = Int64((Double(offsetFromStart) * speed).rounded())
        if isReversed {
            return sourceOut - scaledOffset
        }
        return sourceIn + scaledOffset
    }

    /// Map source time to timeline time.
    func sourceToTimeline(_ sourceTime: TimeMicros) -> TimeMicros {
        let offset: TimeMicros
        if isReversed {
            offset = sourceOut - sourceTime
        } else {
            offset = sourceTime - sourceIn
        }
        return startTime + Int64((Double(offset) / speed).rounded())
    }

    // MARK: - Copy-With-Modify

    /// Create a copy with updated values.
    func with(
        id: String? = nil,
        mediaAssetId: String? = nil,
        trackId: String? = nil,
        type: ClipType? = nil,
        startTime: TimeMicros? = nil,
        duration: TimeMicros? = nil,
        sourceIn: TimeMicros? = nil,
        sourceOut: TimeMicros? = nil,
        speed: Double? = nil,
        isReversed: Bool? = nil,
        clipColorValue: UInt32? = nil,
        label: String? = nil,
        linkedClipId: String? = nil,
        isOffline: Bool? = nil,
        hasEffects: Bool? = nil,
        hasKeyframes: Bool? = nil,
        effectCount: Int? = nil,
        hasAudio: Bool? = nil,
        volume: Double? = nil,
        isMuted: Bool? = nil,
        colorValue: UInt32? = nil,
        clearMediaAssetId: Bool = false,
        clearLabel: Bool = false,
        clearLinkedClipId: Bool = false,
        clearColorValue: Bool = false
    ) -> TimelineClip {
        TimelineClip(
            id: id ?? self.id,
            mediaAssetId: clearMediaAssetId ? nil : (mediaAssetId ?? self.mediaAssetId),
            trackId: trackId ?? self.trackId,
            type: type ?? self.type,
            startTime: startTime ?? self.startTime,
            duration: duration ?? self.duration,
            sourceIn: sourceIn ?? self.sourceIn,
            sourceOut: sourceOut ?? self.sourceOut,
            speed: speed ?? self.speed,
            isReversed: isReversed ?? self.isReversed,
            clipColorValue: clipColorValue ?? self.clipColorValue,
            label: clearLabel ? nil : (label ?? self.label),
            linkedClipId: clearLinkedClipId ? nil : (linkedClipId ?? self.linkedClipId),
            isOffline: isOffline ?? self.isOffline,
            hasEffects: hasEffects ?? self.hasEffects,
            hasKeyframes: hasKeyframes ?? self.hasKeyframes,
            effectCount: effectCount ?? self.effectCount,
            hasAudio: hasAudio ?? self.hasAudio,
            volume: volume ?? self.volume,
            isMuted: isMuted ?? self.isMuted,
            colorValue: clearColorValue ? nil : (colorValue ?? self.colorValue)
        )
    }

    // MARK: - Edit Operations

    /// Move clip to new start time.
    func moveTo(_ newStartTime: TimeMicros) -> TimelineClip {
        with(startTime: newStartTime)
    }

    /// Move clip by delta.
    func moveBy(_ delta: TimeMicros) -> TimelineClip {
        with(startTime: startTime + delta)
    }

    /// Move to different track.
    func moveToTrack(_ newTrackId: String) -> TimelineClip {
        with(trackId: newTrackId)
    }

    /// Trim from head (adjust start time and duration).
    func trimHead(_ newStartTime: TimeMicros) -> TimelineClip {
        if newStartTime < startTime {
            // Extending head - check source bounds
            let delta = startTime - newStartTime
            let newSourceIn = sourceIn - Int64((Double(delta) * speed).rounded())
            if newSourceIn < 0 { return self } // Can't extend beyond source start
            return with(
                startTime: newStartTime,
                duration: duration + delta,
                sourceIn: newSourceIn
            )
        } else {
            // Trimming head
            let delta = newStartTime - startTime
            let newDuration = duration - delta
            if newDuration < Self.minDuration { return self } // Can't trim below minimum
            let newSourceIn = sourceIn + Int64((Double(delta) * speed).rounded())
            return with(
                startTime: newStartTime,
                duration: newDuration,
                sourceIn: newSourceIn
            )
        }
    }

    /// Trim from tail (adjust duration).
    func trimTail(_ newEndTime: TimeMicros) -> TimelineClip {
        let newDuration = newEndTime - startTime
        if newDuration < Self.minDuration { return self } // Can't trim below minimum
        let newSourceOut = sourceIn + Int64((Double(newDuration) * speed).rounded())
        return with(
            duration: newDuration,
            sourceOut: newSourceOut
        )
    }

    /// Slip content (move source range without changing timeline position).
    func slip(_ sourceDelta: TimeMicros) -> TimelineClip {
        let newSourceIn = sourceIn + sourceDelta
        let newSourceOut = sourceOut + sourceDelta
        if newSourceIn < 0 { return self } // Can't slip before source start
        return with(
            sourceIn: newSourceIn,
            sourceOut: newSourceOut
        )
    }

    /// Split clip at timeline time.
    func splitAt(_ splitTime: TimeMicros, rightClipId: String) -> (left: TimelineClip, right: TimelineClip)? {
        // Validate split point
        guard splitTime > startTime, splitTime < endTime else {
            return nil
        }

        // Calculate split point in source
        let sourceTime = timelineToSource(splitTime)

        // Left clip (before split)
        let leftClip = with(
            duration: splitTime - startTime,
            sourceOut: sourceTime
        )

        // Right clip (after split)
        let rightClip = with(
            id: rightClipId,
            startTime: splitTime,
            duration: endTime - splitTime,
            sourceIn: sourceTime
        )

        return (left: leftClip, right: rightClip)
    }

    /// Change speed.
    func withSpeed(_ newSpeed: Double) -> TimelineClip {
        guard newSpeed > 0 else { return self }
        // Adjust duration to maintain source range
        let newDuration = Int64((Double(sourceDuration) / newSpeed).rounded())
        return with(
            duration: newDuration,
            speed: newSpeed
        )
    }

    /// Toggle reverse.
    func toggleReverse() -> TimelineClip {
        with(isReversed: !isReversed)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(trackId)
        hasher.combine(type)
        hasher.combine(startTime)
        hasher.combine(duration)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case mediaAssetId
        case trackId
        case type
        case startTime
        case duration
        case sourceIn
        case sourceOut
        case speed
        case isReversed
        case clipColor
        case label
        case linkedClipId
        case isOffline
        case hasEffects
        case hasKeyframes
        case effectCount
        case hasAudio
        case volume
        case isMuted
        case colorValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(mediaAssetId, forKey: .mediaAssetId)
        try container.encode(trackId, forKey: .trackId)
        try container.encode(type, forKey: .type)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(duration, forKey: .duration)
        try container.encode(sourceIn, forKey: .sourceIn)
        try container.encode(sourceOut, forKey: .sourceOut)
        try container.encode(speed, forKey: .speed)
        try container.encode(isReversed, forKey: .isReversed)
        try container.encode(clipColorValue, forKey: .clipColor)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(linkedClipId, forKey: .linkedClipId)
        try container.encode(isOffline, forKey: .isOffline)
        try container.encode(hasEffects, forKey: .hasEffects)
        try container.encode(hasKeyframes, forKey: .hasKeyframes)
        try container.encode(effectCount, forKey: .effectCount)
        try container.encode(hasAudio, forKey: .hasAudio)
        try container.encode(volume, forKey: .volume)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encodeIfPresent(colorValue, forKey: .colorValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mediaAssetId = try container.decodeIfPresent(String.self, forKey: .mediaAssetId)
        trackId = try container.decode(String.self, forKey: .trackId)
        type = try container.decode(ClipType.self, forKey: .type)
        startTime = try container.decode(TimeMicros.self, forKey: .startTime)
        duration = try container.decode(TimeMicros.self, forKey: .duration)
        sourceIn = try container.decodeIfPresent(TimeMicros.self, forKey: .sourceIn) ?? 0
        sourceOut = try container.decodeIfPresent(TimeMicros.self, forKey: .sourceOut) ?? (sourceIn + duration)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        isReversed = try container.decodeIfPresent(Bool.self, forKey: .isReversed) ?? false
        clipColorValue = try container.decodeIfPresent(UInt32.self, forKey: .clipColor) ?? 0xFF808080
        label = try container.decodeIfPresent(String.self, forKey: .label)
        linkedClipId = try container.decodeIfPresent(String.self, forKey: .linkedClipId)
        isOffline = try container.decodeIfPresent(Bool.self, forKey: .isOffline) ?? false
        hasEffects = try container.decodeIfPresent(Bool.self, forKey: .hasEffects) ?? false
        hasKeyframes = try container.decodeIfPresent(Bool.self, forKey: .hasKeyframes) ?? false
        effectCount = try container.decodeIfPresent(Int.self, forKey: .effectCount) ?? 0
        hasAudio = try container.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        colorValue = try container.decodeIfPresent(UInt32.self, forKey: .colorValue)
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "TimelineClip(\(id), type: \(type), range: \(startTime)-\(endTime), track: \(trackId))"
    }
}
