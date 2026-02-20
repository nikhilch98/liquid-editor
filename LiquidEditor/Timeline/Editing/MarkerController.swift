// MarkerController.swift
// LiquidEditor
//
// Controller for point and range marker management.

import Foundation

// MARK: - MarkerNavigationResult

/// Result of marker navigation.
struct MarkerNavigationResult: Equatable, Sendable {
    /// Target marker.
    let marker: TimelineMarker?

    /// Time to navigate to.
    let time: TimeMicros?

    /// Whether navigation was successful.
    let found: Bool

    init(marker: TimelineMarker? = nil, time: TimeMicros? = nil, found: Bool) {
        self.marker = marker
        self.time = time
        self.found = found
    }

    /// Successful navigation.
    static func found(_ marker: TimelineMarker) -> MarkerNavigationResult {
        MarkerNavigationResult(marker: marker, time: marker.time, found: true)
    }

    /// No marker found.
    static let notFound = MarkerNavigationResult(found: false)
}

// MARK: - MarkerUpdate

/// Marker update parameters.
struct MarkerUpdate: Equatable, Sendable {
    let label: String?
    let notes: String?
    let colorARGB32: Int?
    let time: TimeMicros?
    let duration: TimeMicros?
    let type: TimelineMarkerType?
    let clearNotes: Bool
    let clearDuration: Bool

    init(
        label: String? = nil,
        notes: String? = nil,
        colorARGB32: Int? = nil,
        time: TimeMicros? = nil,
        duration: TimeMicros? = nil,
        type: TimelineMarkerType? = nil,
        clearNotes: Bool = false,
        clearDuration: Bool = false
    ) {
        self.label = label
        self.notes = notes
        self.colorARGB32 = colorARGB32
        self.time = time
        self.duration = duration
        self.type = type
        self.clearNotes = clearNotes
        self.clearDuration = clearDuration
    }
}

// MARK: - MarkerUpdateResult

/// Result of a marker update operation.
struct MarkerUpdateResult: Equatable, Sendable {
    /// Updated list of markers.
    let markers: [TimelineMarker]

    /// The updated marker (nil if not found).
    let updatedMarker: TimelineMarker?
}

// MARK: - MarkerController

/// Controller for marker management operations.
///
/// Provides creation, deletion, update, navigation, and query
/// operations for point and range timeline markers.
enum MarkerController {

    /// Navigation threshold in microseconds (1ms) - defines "same time" for next/previous navigation.
    /// When navigating from current playhead position, markers within this threshold are considered
    /// "at the current position" and skipped to find the next distinct marker.
    static let navigationThreshold: TimeMicros = 1_000 // 1 ms

    // MARK: - Create Markers

    /// Add a point marker at the specified time.
    ///
    /// - Parameters:
    ///   - time: The marker position.
    ///   - label: The marker name.
    ///   - type: The marker type (defaults to generic).
    ///   - colorARGB32: Optional custom color.
    ///   - notes: Optional description.
    /// - Returns: The created marker.
    static func addMarker(
        time: TimeMicros,
        label: String,
        type: TimelineMarkerType = .generic,
        colorARGB32: Int? = nil,
        notes: String? = nil
    ) -> TimelineMarker {
        TimelineMarker.point(
            id: UUID().uuidString,
            time: time,
            label: label,
            notes: notes,
            type: type,
            colorARGB32: colorARGB32
        )
    }

    /// Add a range marker spanning a time range.
    ///
    /// - Parameters:
    ///   - startTime: The range start.
    ///   - endTime: The range end.
    ///   - label: The marker name.
    ///   - type: The marker type (defaults to generic).
    ///   - colorARGB32: Optional custom color.
    ///   - notes: Optional description.
    /// - Returns: The created marker.
    static func addRangeMarker(
        startTime: TimeMicros,
        endTime: TimeMicros,
        label: String,
        type: TimelineMarkerType = .generic,
        colorARGB32: Int? = nil,
        notes: String? = nil
    ) -> TimelineMarker {
        // Ensure startTime is before endTime
        let actualStart = min(startTime, endTime)
        let actualEnd = max(startTime, endTime)

        return TimelineMarker.range(
            id: UUID().uuidString,
            startTime: actualStart,
            endTime: actualEnd,
            label: label,
            notes: notes,
            type: type,
            colorARGB32: colorARGB32
        )
    }

    // MARK: - Delete Markers

    /// Delete a marker by ID.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - markerId: The ID of the marker to delete.
    /// - Returns: Updated marker list.
    static func deleteMarker(_ markers: [TimelineMarker], markerId: String) -> [TimelineMarker] {
        markers.filter { $0.id != markerId }
    }

    /// Delete multiple markers by ID.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - markerIds: The IDs of markers to delete.
    /// - Returns: Updated marker list.
    static func deleteMarkers(_ markers: [TimelineMarker], markerIds: Set<String>) -> [TimelineMarker] {
        markers.filter { !markerIds.contains($0.id) }
    }

    // MARK: - Update Marker

    /// Update a marker's properties.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - markerId: The ID of the marker to update.
    ///   - update: The properties to change.
    /// - Returns: Updated marker list and the updated marker.
    static func updateMarker(
        _ markers: [TimelineMarker],
        markerId: String,
        update: MarkerUpdate
    ) -> MarkerUpdateResult {
        var updatedMarker: TimelineMarker?
        let updatedList = markers.map { marker -> TimelineMarker in
            guard marker.id == markerId else { return marker }

            let updated = marker.with(
                time: update.time,
                duration: update.duration.map { .some($0) },
                label: update.label,
                notes: update.notes.map { .some($0) },
                type: update.type,
                colorARGB32: update.colorARGB32,
                clearDuration: update.clearDuration,
                clearNotes: update.clearNotes
            )
            updatedMarker = updated
            return updated
        }

        return MarkerUpdateResult(markers: updatedList, updatedMarker: updatedMarker)
    }

    // MARK: - Navigation

    /// Navigate to next marker from current time.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - currentTime: The current playhead time.
    /// - Returns: Navigation result with next marker.
    static func goToNextMarker(
        _ markers: [TimelineMarker],
        currentTime: TimeMicros
    ) -> MarkerNavigationResult {
        guard !markers.isEmpty else { return .notFound }

        // Sort markers by time
        let sorted = markers.sorted { $0.time < $1.time }

        // Find first marker after current time
        // Use small offset to avoid getting stuck on current marker
        let threshold = currentTime + navigationThreshold
        for marker in sorted {
            if marker.time > threshold {
                return .found(marker)
            }
        }

        // Wrap around to first marker if no marker found after current time
        return .found(sorted[0])
    }

    /// Navigate to previous marker from current time.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - currentTime: The current playhead time.
    /// - Returns: Navigation result with previous marker.
    static func goToPreviousMarker(
        _ markers: [TimelineMarker],
        currentTime: TimeMicros
    ) -> MarkerNavigationResult {
        guard !markers.isEmpty else { return .notFound }

        // Sort markers by time descending
        let sorted = markers.sorted { $0.time > $1.time }

        // Find first marker before current time
        // Use small offset to avoid getting stuck on current marker
        let threshold = currentTime - navigationThreshold
        for marker in sorted {
            if marker.time < threshold {
                return .found(marker)
            }
        }

        // Wrap around to last marker (first in descending sort)
        return .found(sorted[0])
    }

    // MARK: - Search

    /// Find marker at or near a specific time.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - time: The time to search at.
    ///   - toleranceMicros: The search tolerance (default: 100ms).
    /// - Returns: The closest marker within tolerance, or nil.
    static func findMarkerAtTime(
        _ markers: [TimelineMarker],
        time: TimeMicros,
        toleranceMicros: TimeMicros = 100_000
    ) -> TimelineMarker? {
        var closest: TimelineMarker?
        var closestDistance: TimeMicros = toleranceMicros + 1

        for marker in markers {
            let distance = abs(marker.time - time)
            if distance <= toleranceMicros && distance < closestDistance {
                closest = marker
                closestDistance = distance
            }
        }

        return closest
    }

    /// Get markers within a time range.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - range: The time range to search in.
    /// - Returns: Markers within the range.
    static func getMarkersInRange(
        _ markers: [TimelineMarker],
        range: TimeRange
    ) -> [TimelineMarker] {
        markers.filter { marker in
            if marker.isRange {
                // Check if range marker overlaps with search range
                guard let markerRange = marker.timeRange else { return false }
                return markerRange.overlaps(range)
            } else {
                // Check if point marker is within range
                return range.contains(marker.time)
            }
        }
    }

    /// Get markers of a specific type.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - type: The marker type to filter by.
    /// - Returns: Markers of the specified type.
    static func getMarkersByType(
        _ markers: [TimelineMarker],
        type: TimelineMarkerType
    ) -> [TimelineMarker] {
        markers.filter { $0.type == type }
    }

    // MARK: - Move

    /// Move a marker to a new time.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - markerId: The ID of the marker to move.
    ///   - newTime: The new time position.
    /// - Returns: Updated marker list.
    static func moveMarker(
        _ markers: [TimelineMarker],
        markerId: String,
        to newTime: TimeMicros
    ) -> [TimelineMarker] {
        markers.map { marker in
            if marker.id == markerId {
                return marker.moveTo(newTime)
            }
            return marker
        }
    }

    /// Move a marker by a delta.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - markerId: The ID of the marker to move.
    ///   - delta: The time offset to apply.
    /// - Returns: Updated marker list.
    static func moveMarkerBy(
        _ markers: [TimelineMarker],
        markerId: String,
        delta: TimeMicros
    ) -> [TimelineMarker] {
        markers.map { marker in
            if marker.id == markerId {
                return marker.moveBy(delta)
            }
            return marker
        }
    }

    // MARK: - Conversion

    /// Convert a point marker to a range marker.
    ///
    /// - Parameters:
    ///   - marker: The point marker to convert.
    ///   - duration: The range duration.
    /// - Returns: The updated marker.
    static func convertToRange(_ marker: TimelineMarker, duration: TimeMicros) -> TimelineMarker {
        if marker.isRange { return marker }
        return marker.withDuration(duration)
    }

    /// Convert a range marker to a point marker.
    ///
    /// - Parameter marker: The range marker to convert.
    /// - Returns: The updated marker (point at range start).
    static func convertToPoint(_ marker: TimelineMarker) -> TimelineMarker {
        if !marker.isRange { return marker }
        return marker.withDuration(nil)
    }

    // MARK: - Sorting

    /// Get sorted markers.
    ///
    /// - Parameters:
    ///   - markers: The current list of markers.
    ///   - ascending: Sort order.
    /// - Returns: Sorted marker list.
    static func getSortedMarkers(
        _ markers: [TimelineMarker],
        ascending: Bool = true
    ) -> [TimelineMarker] {
        markers.sorted { a, b in
            ascending ? a.time < b.time : a.time > b.time
        }
    }
}
