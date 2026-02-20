import Testing
import Foundation
@testable import LiquidEditor

// MARK: - MarkerNavigationResult Tests

@Suite("MarkerNavigationResult Tests")
struct MarkerNavigationResultTests {

    @Test("Not found result")
    func notFound() {
        let result = MarkerNavigationResult.notFound
        #expect(!result.found)
        #expect(result.marker == nil)
        #expect(result.time == nil)
    }

    @Test("Found result")
    func found() {
        let marker = TimelineMarker.point(id: "m1", time: 500_000, label: "Test")
        let result = MarkerNavigationResult.found(marker)
        #expect(result.found)
        #expect(result.marker?.id == "m1")
        #expect(result.time == 500_000)
    }
}

// MARK: - MarkerController Tests

@Suite("MarkerController Tests")
struct MarkerControllerTests {

    /// Create test markers.
    private func makeMarkers() -> [TimelineMarker] {
        [
            TimelineMarker.point(id: "m1", time: 100_000, label: "Start"),
            TimelineMarker.point(id: "m2", time: 500_000, label: "Middle"),
            TimelineMarker.point(id: "m3", time: 900_000, label: "End"),
        ]
    }

    // MARK: - Add Markers

    @Test("Add point marker")
    func addPointMarker() {
        let marker = MarkerController.addMarker(
            time: 500_000,
            label: "Test Marker",
            type: .generic
        )

        #expect(!marker.id.isEmpty)
        #expect(marker.time == 500_000)
        #expect(marker.label == "Test Marker")
        #expect(marker.type == .generic)
        #expect(!marker.isRange)
    }

    @Test("Add range marker")
    func addRangeMarker() {
        let marker = MarkerController.addRangeMarker(
            startTime: 100_000,
            endTime: 500_000,
            label: "Range"
        )

        #expect(marker.time == 100_000)
        #expect(marker.duration == 400_000)
        #expect(marker.isRange)
    }

    @Test("Add range marker with swapped times normalizes order")
    func addRangeMarkerSwapped() {
        let marker = MarkerController.addRangeMarker(
            startTime: 500_000,
            endTime: 100_000,
            label: "Swapped"
        )

        #expect(marker.time == 100_000)
        #expect(marker.endTime == 500_000)
    }

    @Test("Add marker with custom color")
    func addMarkerWithColor() {
        let marker = MarkerController.addMarker(
            time: 300_000,
            label: "Colored",
            colorARGB32: 0xFFFF0000
        )

        #expect(marker.colorARGB32 == 0xFFFF0000)
    }

    @Test("Add marker with notes")
    func addMarkerWithNotes() {
        let marker = MarkerController.addMarker(
            time: 300_000,
            label: "Noted",
            notes: "Some notes"
        )

        #expect(marker.notes == "Some notes")
    }

    // MARK: - Delete Markers

    @Test("Delete marker by ID")
    func deleteMarker() {
        let markers = makeMarkers()
        let result = MarkerController.deleteMarker(markers, markerId: "m2")
        #expect(result.count == 2)
        #expect(!result.contains { $0.id == "m2" })
    }

    @Test("Delete multiple markers")
    func deleteMultipleMarkers() {
        let markers = makeMarkers()
        let result = MarkerController.deleteMarkers(markers, markerIds: ["m1", "m3"])
        #expect(result.count == 1)
        #expect(result[0].id == "m2")
    }

    @Test("Delete non-existent marker returns unchanged list")
    func deleteNonExistent() {
        let markers = makeMarkers()
        let result = MarkerController.deleteMarker(markers, markerId: "nonexistent")
        #expect(result.count == 3)
    }

    // MARK: - Update Marker

    @Test("Update marker label")
    func updateMarkerLabel() {
        let markers = makeMarkers()
        let result = MarkerController.updateMarker(
            markers,
            markerId: "m2",
            update: MarkerUpdate(label: "Updated")
        )

        #expect(result.updatedMarker?.label == "Updated")
        #expect(result.markers.count == 3)
    }

    @Test("Update marker time")
    func updateMarkerTime() {
        let markers = makeMarkers()
        let result = MarkerController.updateMarker(
            markers,
            markerId: "m1",
            update: MarkerUpdate(time: 200_000)
        )

        #expect(result.updatedMarker?.time == 200_000)
    }

    @Test("Update non-existent marker returns nil updated")
    func updateNonExistent() {
        let markers = makeMarkers()
        let result = MarkerController.updateMarker(
            markers,
            markerId: "nonexistent",
            update: MarkerUpdate(label: "Nope")
        )

        #expect(result.updatedMarker == nil)
        #expect(result.markers.count == 3)
    }

    // MARK: - Navigation

    @Test("Go to next marker")
    func goToNextMarker() {
        let markers = makeMarkers()
        let result = MarkerController.goToNextMarker(markers, currentTime: 200_000)
        #expect(result.found)
        #expect(result.marker?.id == "m2")
    }

    @Test("Go to next marker wraps around")
    func goToNextMarkerWraps() {
        let markers = makeMarkers()
        let result = MarkerController.goToNextMarker(markers, currentTime: 900_000)
        #expect(result.found)
        #expect(result.marker?.id == "m1") // Wraps to first
    }

    @Test("Go to next marker with empty list")
    func goToNextMarkerEmpty() {
        let result = MarkerController.goToNextMarker([], currentTime: 0)
        #expect(!result.found)
    }

    @Test("Go to previous marker")
    func goToPreviousMarker() {
        let markers = makeMarkers()
        let result = MarkerController.goToPreviousMarker(markers, currentTime: 600_000)
        #expect(result.found)
        #expect(result.marker?.id == "m2")
    }

    @Test("Go to previous marker wraps around")
    func goToPreviousMarkerWraps() {
        let markers = makeMarkers()
        let result = MarkerController.goToPreviousMarker(markers, currentTime: 50_000)
        #expect(result.found)
        #expect(result.marker?.id == "m3") // Wraps to last
    }

    @Test("Go to previous marker with empty list")
    func goToPreviousMarkerEmpty() {
        let result = MarkerController.goToPreviousMarker([], currentTime: 0)
        #expect(!result.found)
    }

    // MARK: - Search

    @Test("Find marker at time within tolerance")
    func findMarkerAtTime() {
        let markers = makeMarkers()
        let found = MarkerController.findMarkerAtTime(markers, time: 502_000, toleranceMicros: 10_000)
        #expect(found?.id == "m2")
    }

    @Test("Find marker at time outside tolerance")
    func findMarkerOutsideTolerance() {
        let markers = makeMarkers()
        let found = MarkerController.findMarkerAtTime(markers, time: 300_000, toleranceMicros: 10_000)
        #expect(found == nil)
    }

    @Test("Find marker at time picks closest")
    func findMarkerClosest() {
        let markers = [
            TimelineMarker.point(id: "m1", time: 100_000, label: "A"),
            TimelineMarker.point(id: "m2", time: 110_000, label: "B"),
        ]
        let found = MarkerController.findMarkerAtTime(markers, time: 108_000, toleranceMicros: 50_000)
        #expect(found?.id == "m2") // Closer to 110k
    }

    @Test("Get markers in range - point markers")
    func getMarkersInRange() {
        let markers = makeMarkers()
        let found = MarkerController.getMarkersInRange(markers, range: TimeRange(200_000, 800_000))
        #expect(found.count == 1)
        #expect(found[0].id == "m2")
    }

    @Test("Get markers in range - range marker overlap")
    func getMarkersInRangeOverlap() {
        let markers = [
            TimelineMarker.range(id: "r1", startTime: 100_000, endTime: 300_000, label: "Range1"),
        ]
        let found = MarkerController.getMarkersInRange(markers, range: TimeRange(200_000, 400_000))
        #expect(found.count == 1) // Overlaps with search range
    }

    @Test("Get markers by type")
    func getMarkersByType() {
        let markers = [
            TimelineMarker.point(id: "m1", time: 100_000, label: "A", type: .chapter),
            TimelineMarker.point(id: "m2", time: 200_000, label: "B", type: .generic),
            TimelineMarker.point(id: "m3", time: 300_000, label: "C", type: .chapter),
        ]

        let chapters = MarkerController.getMarkersByType(markers, type: .chapter)
        #expect(chapters.count == 2)
    }

    // MARK: - Move

    @Test("Move marker to new time")
    func moveMarker() {
        let markers = makeMarkers()
        let result = MarkerController.moveMarker(markers, markerId: "m2", to: 600_000)
        let moved = result.first { $0.id == "m2" }
        #expect(moved?.time == 600_000)
    }

    @Test("Move marker by delta")
    func moveMarkerByDelta() {
        let markers = makeMarkers()
        let result = MarkerController.moveMarkerBy(markers, markerId: "m2", delta: 50_000)
        let moved = result.first { $0.id == "m2" }
        #expect(moved?.time == 550_000)
    }

    // MARK: - Conversion

    @Test("Convert point to range")
    func convertToRange() {
        let marker = TimelineMarker.point(id: "m1", time: 100_000, label: "Point")
        let range = MarkerController.convertToRange(marker, duration: 200_000)
        #expect(range.isRange)
        #expect(range.duration == 200_000)
    }

    @Test("Convert range to point")
    func convertToPoint() {
        let marker = TimelineMarker.range(id: "r1", startTime: 100_000, endTime: 300_000, label: "Range")
        let point = MarkerController.convertToPoint(marker)
        #expect(!point.isRange)
    }

    @Test("Convert already-range marker is no-op")
    func convertAlreadyRange() {
        let marker = TimelineMarker.range(id: "r1", startTime: 100_000, endTime: 300_000, label: "Range")
        let result = MarkerController.convertToRange(marker, duration: 500_000)
        #expect(result == marker)
    }

    @Test("Convert already-point marker is no-op")
    func convertAlreadyPoint() {
        let marker = TimelineMarker.point(id: "m1", time: 100_000, label: "Point")
        let result = MarkerController.convertToPoint(marker)
        #expect(result == marker)
    }

    // MARK: - Sorting

    @Test("Get sorted markers ascending")
    func sortedAscending() {
        let markers = [
            TimelineMarker.point(id: "m3", time: 900_000, label: "C"),
            TimelineMarker.point(id: "m1", time: 100_000, label: "A"),
            TimelineMarker.point(id: "m2", time: 500_000, label: "B"),
        ]

        let sorted = MarkerController.getSortedMarkers(markers, ascending: true)
        #expect(sorted[0].id == "m1")
        #expect(sorted[1].id == "m2")
        #expect(sorted[2].id == "m3")
    }

    @Test("Get sorted markers descending")
    func sortedDescending() {
        let markers = makeMarkers()
        let sorted = MarkerController.getSortedMarkers(markers, ascending: false)
        #expect(sorted[0].id == "m3")
        #expect(sorted[2].id == "m1")
    }

    // MARK: - Edge Cases

    @Test("Operations on empty list")
    func operationsOnEmpty() {
        let markers: [TimelineMarker] = []
        #expect(MarkerController.deleteMarker(markers, markerId: "any").isEmpty)
        #expect(MarkerController.getMarkersInRange(markers, range: TimeRange(0, 1_000_000)).isEmpty)
        #expect(MarkerController.findMarkerAtTime(markers, time: 0) == nil)
        #expect(MarkerController.getSortedMarkers(markers).isEmpty)
    }
}
