import Foundation

/// A solid color clip on the timeline.
///
/// Renders a solid color for the specified duration.
/// Useful for fade-ins, fade-outs, or color backgrounds.
struct ColorClip: GeneratorClip, Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Duration in microseconds.
    let durationMicroseconds: Int64

    /// Color as ARGB 32-bit integer.
    let colorValue: Int

    /// Optional display name.
    let name: String?

    var displayName: String { name ?? "Color" }

    var itemType: TimelineItemType { .color }

    init(
        id: String,
        durationMicroseconds: Int64,
        colorValue: Int,
        name: String? = nil
    ) {
        self.id = id
        self.durationMicroseconds = durationMicroseconds
        self.colorValue = colorValue
        self.name = name
    }

    // MARK: - Color Queries

    /// Get as ARGBColor.
    var color: ARGBColor { ARGBColor.fromARGB32(colorValue) }

    /// Whether this is a black clip.
    var isBlack: Bool { colorValue == 0xFF00_0000 }

    /// Whether this is a white clip.
    var isWhite: Bool { colorValue == 0xFFFF_FFFF }

    /// Whether this is transparent.
    var isTransparent: Bool { (colorValue >> 24) & 0xFF == 0 }

    // MARK: - Factory Constructors

    /// Create a black clip.
    static func black(id: String, durationMicroseconds: Int64) -> ColorClip {
        ColorClip(
            id: id,
            durationMicroseconds: durationMicroseconds,
            colorValue: 0xFF00_0000,
            name: "Black"
        )
    }

    /// Create a white clip.
    static func white(id: String, durationMicroseconds: Int64) -> ColorClip {
        ColorClip(
            id: id,
            durationMicroseconds: durationMicroseconds,
            colorValue: 0xFFFF_FFFF,
            name: "White"
        )
    }

    /// Create a transparent clip.
    static func transparent(id: String, durationMicroseconds: Int64) -> ColorClip {
        ColorClip(
            id: id,
            durationMicroseconds: durationMicroseconds,
            colorValue: 0x0000_0000,
            name: "Transparent"
        )
    }

    /// Create from an ARGBColor.
    static func fromColor(
        id: String,
        durationMicroseconds: Int64,
        color: ARGBColor,
        name: String? = nil
    ) -> ColorClip {
        ColorClip(
            id: id,
            durationMicroseconds: durationMicroseconds,
            colorValue: color.toARGB32,
            name: name
        )
    }

    // MARK: - Modification

    /// Change duration.
    func withDuration(_ newDurationMicros: TimeMicros) -> ColorClip {
        precondition(newDurationMicros > 0, "Duration must be positive")
        return ColorClip(
            id: id,
            durationMicroseconds: newDurationMicros,
            colorValue: colorValue,
            name: name
        )
    }

    /// Change color.
    func withColor(_ newColorValue: Int) -> ColorClip {
        ColorClip(
            id: id,
            durationMicroseconds: durationMicroseconds,
            colorValue: newColorValue,
            name: name
        )
    }

    /// Change color from ARGBColor.
    func withARGBColor(_ newColor: ARGBColor) -> ColorClip {
        ColorClip(
            id: id,
            durationMicroseconds: durationMicroseconds,
            colorValue: newColor.toARGB32,
            name: name
        )
    }

    /// Create a copy with optional field overrides.
    func with(
        id: String? = nil,
        durationMicroseconds: Int64? = nil,
        colorValue: Int? = nil,
        name: String? = nil,
        clearName: Bool = false
    ) -> ColorClip {
        let newDuration = durationMicroseconds ?? self.durationMicroseconds
        precondition(newDuration > 0, "Duration must be positive")
        return ColorClip(
            id: id ?? self.id,
            durationMicroseconds: newDuration,
            colorValue: colorValue ?? self.colorValue,
            name: clearName ? nil : (name ?? self.name)
        )
    }

    /// Create a duplicate with a new UUID.
    func duplicate() -> ColorClip {
        ColorClip(
            id: UUID().uuidString,
            durationMicroseconds: durationMicroseconds,
            colorValue: colorValue,
            name: name != nil ? "\(name!) (copy)" : nil
        )
    }

    /// Split at offset.
    ///
    /// Returns left and right portions, or nil if the split offset
    /// would produce a portion smaller than the minimum duration (100ms).
    func splitAt(_ offsetMicros: TimeMicros) -> (left: ColorClip, right: ColorClip)? {
        let minDuration: TimeMicros = 100_000 // 100ms minimum

        guard offsetMicros >= minDuration,
              offsetMicros <= durationMicroseconds - minDuration
        else {
            return nil
        }

        let left = ColorClip(
            id: UUID().uuidString,
            durationMicroseconds: offsetMicros,
            colorValue: colorValue,
            name: name != nil ? "\(name!) (1)" : nil
        )

        let right = ColorClip(
            id: UUID().uuidString,
            durationMicroseconds: durationMicroseconds - offsetMicros,
            colorValue: colorValue,
            name: name != nil ? "\(name!) (2)" : nil
        )

        return (left, right)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case itemType
        case id
        case durationMicros
        case colorValue
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        durationMicroseconds = try container.decode(Int64.self, forKey: .durationMicros)
        colorValue = try container.decode(Int.self, forKey: .colorValue)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType.rawValue, forKey: .itemType)
        try container.encode(id, forKey: .id)
        try container.encode(durationMicroseconds, forKey: .durationMicros)
        try container.encode(colorValue, forKey: .colorValue)
        try container.encodeIfPresent(name, forKey: .name)
    }
}
