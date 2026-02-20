import Foundation

/// A gap on the timeline.
///
/// Represents empty space that renders as black/transparent video
/// and silence for audio. Used for spacing between clips.
struct GapClip: GeneratorClip, Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Duration in microseconds.
    let durationMicroseconds: Int64

    var displayName: String { "Gap" }

    var itemType: TimelineItemType { .gap }

    init(id: String, durationMicroseconds: Int64) {
        precondition(durationMicroseconds > 0, "Duration must be positive")
        self.id = id
        self.durationMicroseconds = durationMicroseconds
    }

    /// Change duration of the gap.
    func withDuration(_ newDurationMicros: TimeMicros) -> GapClip {
        precondition(newDurationMicros > 0, "Duration must be positive")
        return GapClip(id: id, durationMicroseconds: newDurationMicros)
    }

    /// Create a copy with optional field overrides.
    func with(
        id: String? = nil,
        durationMicroseconds: Int64? = nil
    ) -> GapClip {
        let newDuration = durationMicroseconds ?? self.durationMicroseconds
        precondition(newDuration > 0, "Duration must be positive")
        return GapClip(
            id: id ?? self.id,
            durationMicroseconds: newDuration
        )
    }

    /// Create a duplicate with a new UUID.
    func duplicate() -> GapClip {
        GapClip(
            id: UUID().uuidString,
            durationMicroseconds: durationMicroseconds
        )
    }

    /// Split gap at offset.
    ///
    /// Returns left and right portions, or nil if the split offset
    /// would produce a portion smaller than the minimum duration (100ms).
    func splitAt(_ offsetMicros: TimeMicros) -> (left: GapClip, right: GapClip)? {
        let minDuration: TimeMicros = 100_000 // 100ms minimum

        guard offsetMicros >= minDuration,
              offsetMicros <= durationMicroseconds - minDuration
        else {
            return nil
        }

        let left = GapClip(
            id: UUID().uuidString,
            durationMicroseconds: offsetMicros
        )
        let right = GapClip(
            id: UUID().uuidString,
            durationMicroseconds: durationMicroseconds - offsetMicros
        )

        return (left, right)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case itemType
        case id
        case durationMicros
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        durationMicroseconds = try container.decode(Int64.self, forKey: .durationMicros)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType.rawValue, forKey: .itemType)
        try container.encode(id, forKey: .id)
        try container.encode(durationMicroseconds, forKey: .durationMicros)
    }
}
