import Foundation

// MARK: - TimelineItemType

/// Identifies the concrete type of a timeline item for serialization dispatch.
enum TimelineItemType: String, Codable, Sendable {
    case video
    case image
    case audio
    case gap
    case color
    case text
    case sticker
    case effect

    /// Whether this type shows thumbnails.
    var showsThumbnails: Bool {
        self == .video || self == .image
    }

    /// Whether this type shows waveform.
    var showsWaveform: Bool {
        self == .audio
    }
}

// MARK: - TimelineItem Protocol

/// Protocol for all items that can be placed on a timeline.
///
/// Every item on the timeline must have:
/// - Unique ID
/// - Duration in microseconds
/// - Display name for UI
/// - Serialization support
///
/// Conforms to `TimelineItemProtocol` from TimelineNode.swift for
/// integration with the persistent order statistic tree.
protocol TimelineItem: TimelineItemProtocol, Codable, Equatable, Hashable, Sendable {
    /// Duration in microseconds.
    var durationMicroseconds: Int64 { get }

    /// Human-readable name for display.
    var displayName: String { get }

    /// Item type identifier for serialization.
    var itemType: TimelineItemType { get }

    /// Whether this item references external media.
    var isMediaClip: Bool { get }

    /// Whether this item generates content (no external media).
    var isGeneratorClip: Bool { get }
}

/// Default implementations for TimelineItem.
extension TimelineItem {
    var isMediaClip: Bool { false }
    var isGeneratorClip: Bool { false }
}

// MARK: - MediaClip Protocol

/// Protocol for clips that reference external media.
///
/// Media clips have:
/// - Reference to a MediaAsset (by ID)
/// - In/out points within the source media
/// - Computed duration based on in/out points
protocol MediaClip: TimelineItem {
    /// ID of the source MediaAsset.
    var mediaAssetId: String { get }

    /// Start point in source media (microseconds).
    var sourceInMicros: TimeMicros { get }

    /// End point in source media (microseconds).
    var sourceOutMicros: TimeMicros { get }
}

extension MediaClip {
    var isMediaClip: Bool { true }

    /// Duration derived from in/out points.
    var mediaDurationMicroseconds: Int64 { sourceOutMicros - sourceInMicros }

    /// Source time range as a tuple.
    var sourceRange: (start: TimeMicros, end: TimeMicros) {
        (sourceInMicros, sourceOutMicros)
    }

    /// Map timeline offset (relative to clip start) to source time.
    func timelineToSource(_ offsetMicros: TimeMicros) -> TimeMicros {
        sourceInMicros + offsetMicros
    }

    /// Map source time to timeline offset (relative to clip start).
    func sourceToTimeline(_ sourceMicros: TimeMicros) -> TimeMicros {
        sourceMicros - sourceInMicros
    }

    /// Whether a source time is within this clip's range.
    func containsSourceTime(_ sourceMicros: TimeMicros) -> Bool {
        sourceMicros >= sourceInMicros && sourceMicros < sourceOutMicros
    }
}

// MARK: - GeneratorClip Protocol

/// Protocol for clips that generate content (no external media).
///
/// Generator clips have:
/// - Configurable duration
/// - No external file reference
protocol GeneratorClip: TimelineItem {}

extension GeneratorClip {
    var isGeneratorClip: Bool { true }
}

// MARK: - TimelineItemDecoder (Type-Erased Deserialization)

/// Utility for deserializing timeline items from JSON dictionaries.
///
/// Uses the `itemType` field to determine the concrete type.
/// Unknown types are preserved as `GapClip` for forward compatibility
/// (R2-C6): a project saved with newer features can still be opened
/// on an older app version without crashing.
enum TimelineItemDecoder {
    /// Decode a timeline item from a JSON dictionary.
    ///
    /// Supports all clip types: video, audio, image, text, sticker, gap, color.
    /// Unknown types fall back to GapClip for forward compatibility.
    static func decode(from json: [String: Any]) throws -> any TimelineItemProtocol {
        guard let typeString = json["itemType"] as? String else {
            // Forward compatibility: unknown item -> gap
            return GapClip(
                id: json["id"] as? String ?? "unknown",
                durationMicroseconds: json["durationMicros"] as? TimeMicros ?? 1_000_000
            )
        }

        let data = try JSONSerialization.data(withJSONObject: json)

        switch typeString {
        case "video":
            return try JSONDecoder().decode(VideoClip.self, from: data)
        case "audio":
            return try JSONDecoder().decode(AudioClip.self, from: data)
        case "image":
            return try JSONDecoder().decode(ImageClip.self, from: data)
        case "text":
            return try JSONDecoder().decode(TextClip.self, from: data)
        case "sticker":
            return try JSONDecoder().decode(StickerClip.self, from: data)
        case "gap":
            return try JSONDecoder().decode(GapClip.self, from: data)
        case "color":
            return try JSONDecoder().decode(ColorClip.self, from: data)
        default:
            // Forward compatibility: unknown types preserved as gaps
            return GapClip(
                id: json["id"] as? String ?? "unknown",
                durationMicroseconds: json["durationMicros"] as? TimeMicros ?? 1_000_000
            )
        }
    }
}
