import Foundation

// MARK: - MarkerType (Marker Store)

/// Type of marker (for Marker model used by MarkerStore).
enum MarkerStoreMarkerType: String, Codable, CaseIterable, Sendable {
    /// General purpose marker.
    case standard
    /// Chapter marker for export metadata.
    case chapter
    /// Task/review marker.
    case todo
    /// Sync point for multi-cam alignment.
    case sync
    /// Music beat marker from audio beat detection.
    case beat

    /// Display name for this marker type.
    var displayName: String {
        switch self {
        case .standard: "Marker"
        case .chapter: "Chapter"
        case .todo: "To-Do"
        case .sync: "Sync Point"
        case .beat: "Beat"
        }
    }

    /// Default ARGB32 color for this marker type.
    var defaultColorARGB32: Int {
        switch self {
        case .standard: 0xFF007AFF  // iOS blue
        case .chapter: 0xFF34C759   // iOS green
        case .todo: 0xFFFF9500      // iOS orange
        case .sync: 0xFFAF52DE      // iOS purple
        case .beat: 0xFFFF2D55      // iOS pink
        }
    }
}

// MARK: - Marker (MarkerStore's Marker)

/// A single timeline marker.
struct Marker: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Time position on timeline (microseconds).
    let timeMicros: TimeMicros

    /// Human-readable label.
    let label: String

    /// Optional notes/description.
    let notes: String?

    /// Marker color (ARGB32).
    let colorValue: Int

    /// Marker type.
    let type: MarkerStoreMarkerType

    /// When this marker was created.
    let createdAt: Date

    init(
        id: String,
        timeMicros: TimeMicros,
        label: String,
        notes: String? = nil,
        colorValue: Int? = nil,
        type: MarkerStoreMarkerType = .standard,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timeMicros = timeMicros
        self.label = label
        self.notes = notes
        self.colorValue = colorValue ?? type.defaultColorARGB32
        self.type = type
        self.createdAt = createdAt
    }

    /// Get color as ARGBColor.
    var color: ARGBColor { ARGBColor.fromARGB32(colorValue) }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        timeMicros: TimeMicros? = nil,
        label: String? = nil,
        notes: String?? = nil,
        colorValue: Int? = nil,
        type: MarkerStoreMarkerType? = nil,
        createdAt: Date? = nil,
        clearNotes: Bool = false
    ) -> Marker {
        Marker(
            id: id ?? self.id,
            timeMicros: timeMicros ?? self.timeMicros,
            label: label ?? self.label,
            notes: clearNotes ? nil : (notes ?? self.notes),
            colorValue: colorValue ?? self.colorValue,
            type: type ?? self.type,
            createdAt: createdAt ?? self.createdAt
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: Marker, rhs: Marker) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - MarkerStore (Data-only struct)

/// Marker store data model.
///
/// Markers are stored sorted by time for efficient navigation.
/// This is the pure data representation (no ChangeNotifier).
struct MarkerStore: Codable, Equatable, Hashable, Sendable {
    /// Markers sorted by time.
    let markers: [Marker]

    init(markers: [Marker] = []) {
        self.markers = markers.sorted { $0.timeMicros < $1.timeMicros }
    }

    /// Number of markers.
    var count: Int { markers.count }

    /// Whether there are any markers.
    var isEmpty: Bool { markers.isEmpty }

    /// Whether there are markers.
    var isNotEmpty: Bool { !markers.isEmpty }

    /// Get markers of a specific type.
    func markersOfType(_ type: MarkerStoreMarkerType) -> [Marker] {
        markers.filter { $0.type == type }
    }

    /// Get chapter markers only.
    var chapters: [Marker] { markersOfType(.chapter) }

    /// Get marker by ID.
    func getById(_ id: String) -> Marker? {
        markers.first { $0.id == id }
    }

    /// Add a marker.
    func adding(_ marker: Marker) -> MarkerStore {
        var newMarkers = markers
        newMarkers.append(marker)
        return MarkerStore(markers: newMarkers)
    }

    /// Update an existing marker.
    func updating(_ marker: Marker) -> MarkerStore {
        var newMarkers = markers
        if let index = newMarkers.firstIndex(where: { $0.id == marker.id }) {
            newMarkers[index] = marker
        }
        return MarkerStore(markers: newMarkers)
    }

    /// Remove a marker by ID.
    func removing(_ markerId: String) -> MarkerStore {
        MarkerStore(markers: markers.filter { $0.id != markerId })
    }

    /// Find the next marker after the given time.
    func nextMarker(after timeMicros: TimeMicros) -> Marker? {
        markers.first { $0.timeMicros > timeMicros }
    }

    /// Find the previous marker before the given time.
    func previousMarker(before timeMicros: TimeMicros) -> Marker? {
        var previous: Marker?
        for marker in markers {
            if marker.timeMicros >= timeMicros { break }
            previous = marker
        }
        return previous
    }

    /// Find the marker nearest to a time within a snap threshold.
    func snapToMarker(_ timeMicros: TimeMicros, thresholdMicros: TimeMicros = 100000) -> Marker? {
        var nearest: Marker?
        var nearestDistance = thresholdMicros
        for marker in markers {
            let distance = abs(marker.timeMicros - timeMicros)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = marker
            }
        }
        return nearest
    }
}
