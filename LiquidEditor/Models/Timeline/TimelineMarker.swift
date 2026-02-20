import Foundation

// MARK: - TimelineMarkerType

/// Type of timeline marker.
enum TimelineMarkerType: String, Codable, CaseIterable, Sendable {
    /// General purpose marker.
    case generic
    /// Chapter marker for export.
    case chapter
    /// Task/review marker.
    case todo
    /// Sync point for multi-cam.
    case sync
    /// Music beat marker.
    case beat

    /// Display name.
    var displayName: String {
        switch self {
        case .generic: "Marker"
        case .chapter: "Chapter"
        case .todo: "To-Do"
        case .sync: "Sync Point"
        case .beat: "Beat"
        }
    }

    /// Default ARGB32 color for this marker type.
    var defaultColorARGB32: Int {
        switch self {
        case .generic: 0xFF007AFF   // Blue
        case .chapter: 0xFF34C759   // Green
        case .todo: 0xFFFF9500      // Orange
        case .sync: 0xFFAF52DE      // Purple
        case .beat: 0xFFFF2D55      // Pink
        }
    }
}

// MARK: - TimelineMarker

/// Immutable timeline marker.
struct TimelineMarker: Codable, Equatable, Hashable, Sendable {
    /// Unique marker identifier.
    let id: String

    /// Time position on timeline (microseconds).
    let time: TimeMicros

    /// Duration for range markers (nil for point markers).
    let duration: TimeMicros?

    /// Marker label/name.
    let label: String

    /// Optional notes/description.
    let notes: String?

    /// Type of marker.
    let type: TimelineMarkerType

    /// Marker color (ARGB32 int).
    let colorARGB32: Int

    /// Creation timestamp.
    let createdAt: Date

    init(
        id: String,
        time: TimeMicros,
        duration: TimeMicros? = nil,
        label: String,
        notes: String? = nil,
        type: TimelineMarkerType = .generic,
        colorARGB32: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.time = time
        self.duration = duration
        self.label = label
        self.notes = notes
        self.type = type
        self.colorARGB32 = colorARGB32 ?? type.defaultColorARGB32
        self.createdAt = createdAt
    }

    // MARK: - Factory Methods

    /// Create a point marker.
    static func point(
        id: String,
        time: TimeMicros,
        label: String,
        notes: String? = nil,
        type: TimelineMarkerType = .generic,
        colorARGB32: Int? = nil
    ) -> TimelineMarker {
        TimelineMarker(
            id: id,
            time: time,
            label: label,
            notes: notes,
            type: type,
            colorARGB32: colorARGB32 ?? type.defaultColorARGB32
        )
    }

    /// Create a range marker.
    static func range(
        id: String,
        startTime: TimeMicros,
        endTime: TimeMicros,
        label: String,
        notes: String? = nil,
        type: TimelineMarkerType = .generic,
        colorARGB32: Int? = nil
    ) -> TimelineMarker {
        TimelineMarker(
            id: id,
            time: startTime,
            duration: endTime - startTime,
            label: label,
            notes: notes,
            type: type,
            colorARGB32: colorARGB32 ?? type.defaultColorARGB32
        )
    }

    // MARK: - Computed Properties

    /// Marker color as ARGBColor.
    var color: ARGBColor { ARGBColor.fromARGB32(colorARGB32) }

    /// Whether this is a range marker.
    var isRange: Bool { duration != nil && (duration ?? 0) > 0 }

    /// End time for range markers.
    var endTime: TimeMicros { time + (duration ?? 0) }

    /// Time range for range markers.
    var timeRange: TimeRange? {
        guard isRange else { return nil }
        return TimeRange(time, endTime)
    }

    // MARK: - Copy With

    /// Create a copy with updated values.
    func with(
        id: String? = nil,
        time: TimeMicros? = nil,
        duration: TimeMicros?? = nil,
        label: String? = nil,
        notes: String?? = nil,
        type: TimelineMarkerType? = nil,
        colorARGB32: Int? = nil,
        createdAt: Date? = nil,
        clearDuration: Bool = false,
        clearNotes: Bool = false
    ) -> TimelineMarker {
        TimelineMarker(
            id: id ?? self.id,
            time: time ?? self.time,
            duration: clearDuration ? nil : (duration ?? self.duration),
            label: label ?? self.label,
            notes: clearNotes ? nil : (notes ?? self.notes),
            type: type ?? self.type,
            colorARGB32: colorARGB32 ?? self.colorARGB32,
            createdAt: createdAt ?? self.createdAt
        )
    }

    /// Move marker to new time.
    func moveTo(_ newTime: TimeMicros) -> TimelineMarker {
        with(time: newTime)
    }

    /// Move marker by delta.
    func moveBy(_ delta: TimeMicros) -> TimelineMarker {
        with(time: time + delta)
    }

    /// Change duration (convert to range or point).
    func withDuration(_ newDuration: TimeMicros?) -> TimelineMarker {
        if let d = newDuration, d > 0 {
            return with(duration: .some(d))
        }
        return with(clearDuration: true)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, time, duration, label, notes, type, color, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        time = try container.decode(TimeMicros.self, forKey: .time)
        duration = try container.decodeIfPresent(TimeMicros.self, forKey: .duration)
        label = try container.decode(String.self, forKey: .label)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        let typeStr = try container.decodeIfPresent(String.self, forKey: .type) ?? "generic"
        type = TimelineMarkerType(rawValue: typeStr) ?? .generic
        colorARGB32 = try container.decode(Int.self, forKey: .color)
        let dateStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(time, forKey: .time)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(colorARGB32, forKey: .color)
        try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
    }
}
