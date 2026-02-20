// ImageClip.swift
// LiquidEditor
//
// Image clip - a still image displayed for a configurable duration.
//

import Foundation

// MARK: - ImageClip

/// An image clip on the timeline.
///
/// Displays a still image from a MediaAsset for a specified duration.
/// The sourceIn/Out are set to 0/duration since images have
/// no inherent timeline.
struct ImageClip: TimelineItemProtocol, Codable, Equatable, Hashable, Sendable {

    // MARK: - Properties

    /// Unique identifier for this clip.
    let id: String

    /// ID of the source MediaAsset.
    let mediaAssetId: String

    /// How long to display the image (microseconds).
    /// Maps to sourceOutMicros internally.
    let durationMicroseconds: Int64

    /// Optional display name.
    let name: String?

    // MARK: - Derived media clip properties

    /// Start point in source (always 0 for images).
    var sourceInMicros: Int64 { 0 }

    /// End point in source (equals duration for images).
    var sourceOutMicros: Int64 { durationMicroseconds }

    // MARK: - Initialization

    /// Creates an image clip.
    ///
    /// - Parameters:
    ///   - id: Unique identifier.
    ///   - mediaAssetId: ID of the source MediaAsset.
    ///   - durationMicroseconds: How long to display the image.
    ///   - name: Optional display name.
    init(
        id: String = UUID().uuidString,
        mediaAssetId: String,
        durationMicroseconds: Int64,
        name: String? = nil
    ) {
        precondition(durationMicroseconds > 0, "Duration must be positive")
        self.id = id
        self.mediaAssetId = mediaAssetId
        self.durationMicroseconds = durationMicroseconds
        self.name = name
    }

    // MARK: - Computed Properties

    /// Human-readable display name.
    var displayName: String {
        name ?? "Image"
    }

    /// Item type identifier for serialization.
    var itemType: String { "image" }

    /// Whether this item references external media.
    var isMediaClip: Bool { true }

    /// Source time range.
    var sourceRange: (start: Int64, end: Int64) {
        (sourceInMicros, sourceOutMicros)
    }

    // MARK: - Copy-With-Modify

    /// Create a copy with optional field overrides.
    func with(
        id: String? = nil,
        mediaAssetId: String? = nil,
        durationMicroseconds: Int64? = nil,
        name: String? = nil,
        clearName: Bool = false
    ) -> ImageClip {
        let newDuration = durationMicroseconds ?? self.durationMicroseconds
        precondition(newDuration > 0, "Duration must be positive")
        return ImageClip(
            id: id ?? self.id,
            mediaAssetId: mediaAssetId ?? self.mediaAssetId,
            durationMicroseconds: newDuration,
            name: clearName ? nil : (name ?? self.name)
        )
    }

    // MARK: - Modification

    /// Change duration of the image clip.
    func withDuration(_ newDurationMicros: Int64) -> ImageClip {
        precondition(newDurationMicros > 0, "Duration must be positive")
        return with(durationMicroseconds: newDurationMicros)
    }

    // MARK: - Duplication

    /// Create a duplicate with new ID.
    func duplicate() -> ImageClip {
        ImageClip(
            id: UUID().uuidString,
            mediaAssetId: mediaAssetId,
            durationMicroseconds: durationMicroseconds,
            name: name.map { "\($0) (copy)" }
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
        case durationMicros
        case name
        case itemType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(id, forKey: .id)
        try container.encode(mediaAssetId, forKey: .mediaAssetId)
        try container.encode(durationMicroseconds, forKey: .durationMicros)
        try container.encodeIfPresent(name, forKey: .name)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mediaAssetId = try container.decode(String.self, forKey: .mediaAssetId)
        durationMicroseconds = try container.decode(Int64.self, forKey: .durationMicros)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    // MARK: - CustomStringConvertible

    var description: String {
        let durationMs = durationMicroseconds / 1000
        return "ImageClip(\(id), asset=\(mediaAssetId), \(durationMs)ms)"
    }
}
