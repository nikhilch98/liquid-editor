import Testing
import Foundation
@testable import LiquidEditor

// MARK: - MarkerStoreMarkerType Tests

@Suite("MarkerStoreMarkerType Tests")
struct MarkerStoreMarkerTypeTests {

    @Test("all cases")
    func allCases() {
        #expect(MarkerStoreMarkerType.allCases.count == 5)
        #expect(MarkerStoreMarkerType.standard.rawValue == "standard")
        #expect(MarkerStoreMarkerType.chapter.rawValue == "chapter")
        #expect(MarkerStoreMarkerType.todo.rawValue == "todo")
        #expect(MarkerStoreMarkerType.sync.rawValue == "sync")
        #expect(MarkerStoreMarkerType.beat.rawValue == "beat")
    }

    @Test("display names")
    func displayNames() {
        #expect(MarkerStoreMarkerType.standard.displayName == "Marker")
        #expect(MarkerStoreMarkerType.chapter.displayName == "Chapter")
        #expect(MarkerStoreMarkerType.todo.displayName == "To-Do")
        #expect(MarkerStoreMarkerType.sync.displayName == "Sync Point")
        #expect(MarkerStoreMarkerType.beat.displayName == "Beat")
    }

    @Test("default colors are non-zero")
    func defaultColors() {
        for markerType in MarkerStoreMarkerType.allCases {
            #expect(markerType.defaultColorARGB32 != 0)
        }
    }
}

// MARK: - Marker Tests

@Suite("Marker Tests")
struct MarkerTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1700000000)

    @Test("creation with defaults")
    func creationDefaults() {
        let marker = Marker(
            id: "m-1",
            timeMicros: 1_000_000,
            label: "Test Marker",
            createdAt: Self.fixedDate
        )
        #expect(marker.id == "m-1")
        #expect(marker.timeMicros == 1_000_000)
        #expect(marker.label == "Test Marker")
        #expect(marker.notes == nil)
        #expect(marker.type == .standard)
        // Default color is the standard type's default
        #expect(marker.colorValue == MarkerStoreMarkerType.standard.defaultColorARGB32)
    }

    @Test("creation with type uses type's default color")
    func creationWithType() {
        let marker = Marker(
            id: "m-ch",
            timeMicros: 0,
            label: "Chapter 1",
            type: .chapter,
            createdAt: Self.fixedDate
        )
        #expect(marker.colorValue == MarkerStoreMarkerType.chapter.defaultColorARGB32)
    }

    @Test("creation with custom color overrides type default")
    func creationCustomColor() {
        let marker = Marker(
            id: "m-cc",
            timeMicros: 0,
            label: "Custom",
            colorValue: 0xFFFF0000,
            type: .standard,
            createdAt: Self.fixedDate
        )
        #expect(marker.colorValue == 0xFFFF0000)
    }

    @Test("color computed property")
    func colorProperty() {
        let marker = Marker(id: "m", timeMicros: 0, label: "L", colorValue: 0xFF00FF00, createdAt: Self.fixedDate)
        let color = marker.color
        #expect(color == ARGBColor.fromARGB32(0xFF00FF00))
    }

    @Test("with() copy")
    func withCopy() {
        let marker = Marker(id: "m", timeMicros: 1_000_000, label: "Original", createdAt: Self.fixedDate)
        let modified = marker.with(timeMicros: 2_000_000, label: "Modified")
        #expect(modified.label == "Modified")
        #expect(modified.timeMicros == 2_000_000)
        #expect(modified.id == "m")
    }

    @Test("with() clearNotes")
    func withClearNotes() {
        let marker = Marker(id: "m", timeMicros: 0, label: "L", notes: "Some notes", createdAt: Self.fixedDate)
        #expect(marker.notes == "Some notes")
        let cleared = marker.with(clearNotes: true)
        #expect(cleared.notes == nil)
    }

    @Test("Equatable is by id")
    func equatableById() {
        let a = Marker(id: "same", timeMicros: 0, label: "A", createdAt: Self.fixedDate)
        let b = Marker(id: "same", timeMicros: 100, label: "B", createdAt: Self.fixedDate)
        #expect(a == b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let marker = Marker(
            id: "m-codec",
            timeMicros: 5_000_000,
            label: "Codec Test",
            notes: "Some notes",
            colorValue: 0xFF112233,
            type: .todo,
            createdAt: Self.fixedDate
        )
        let data = try JSONEncoder().encode(marker)
        let decoded = try JSONDecoder().decode(Marker.self, from: data)
        #expect(decoded.id == marker.id)
        #expect(decoded.timeMicros == marker.timeMicros)
        #expect(decoded.label == marker.label)
        #expect(decoded.notes == "Some notes")
        #expect(decoded.type == .todo)
        #expect(decoded.colorValue == 0xFF112233)
    }
}

// MARK: - MarkerStore Tests

@Suite("MarkerStore Tests")
struct MarkerStoreTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1700000000)

    private func makeMarkers() -> [Marker] {
        [
            Marker(id: "m1", timeMicros: 1_000_000, label: "First", type: .standard, createdAt: Self.fixedDate),
            Marker(id: "m2", timeMicros: 3_000_000, label: "Second", type: .chapter, createdAt: Self.fixedDate),
            Marker(id: "m3", timeMicros: 5_000_000, label: "Third", type: .todo, createdAt: Self.fixedDate),
            Marker(id: "m4", timeMicros: 7_000_000, label: "Fourth", type: .chapter, createdAt: Self.fixedDate),
        ]
    }

    @Test("empty store")
    func emptyStore() {
        let store = MarkerStore()
        #expect(store.isEmpty)
        #expect(!store.isNotEmpty)
        #expect(store.count == 0)
    }

    @Test("creation sorts by time")
    func creationSorts() {
        // Provide markers in unsorted order
        let markers = [
            Marker(id: "b", timeMicros: 3_000_000, label: "B", createdAt: Self.fixedDate),
            Marker(id: "a", timeMicros: 1_000_000, label: "A", createdAt: Self.fixedDate),
            Marker(id: "c", timeMicros: 2_000_000, label: "C", createdAt: Self.fixedDate),
        ]
        let store = MarkerStore(markers: markers)
        #expect(store.markers[0].id == "a")
        #expect(store.markers[1].id == "c")
        #expect(store.markers[2].id == "b")
    }

    @Test("count and isEmpty")
    func countAndEmpty() {
        let store = MarkerStore(markers: makeMarkers())
        #expect(store.count == 4)
        #expect(!store.isEmpty)
        #expect(store.isNotEmpty)
    }

    @Test("getById")
    func getById() {
        let store = MarkerStore(markers: makeMarkers())
        #expect(store.getById("m2")?.label == "Second")
        #expect(store.getById("nonexistent") == nil)
    }

    @Test("markersOfType")
    func markersOfType() {
        let store = MarkerStore(markers: makeMarkers())
        let chapters = store.markersOfType(.chapter)
        #expect(chapters.count == 2)
        let todos = store.markersOfType(.todo)
        #expect(todos.count == 1)
    }

    @Test("chapters convenience property")
    func chapters() {
        let store = MarkerStore(markers: makeMarkers())
        #expect(store.chapters.count == 2)
    }

    @Test("adding a marker")
    func adding() {
        let store = MarkerStore(markers: makeMarkers())
        let newMarker = Marker(id: "m5", timeMicros: 2_000_000, label: "Inserted", createdAt: Self.fixedDate)
        let updated = store.adding(newMarker)
        #expect(updated.count == 5)
        // Should be sorted: m1(1M), m5(2M), m2(3M), m3(5M), m4(7M)
        #expect(updated.markers[1].id == "m5")
    }

    @Test("updating a marker")
    func updating() {
        let store = MarkerStore(markers: makeMarkers())
        let modified = Marker(id: "m2", timeMicros: 3_500_000, label: "Updated", createdAt: Self.fixedDate)
        let updated = store.updating(modified)
        #expect(updated.count == 4)
        #expect(updated.getById("m2")?.label == "Updated")
        #expect(updated.getById("m2")?.timeMicros == 3_500_000)
    }

    @Test("updating nonexistent marker does not add")
    func updatingNonexistent() {
        let store = MarkerStore(markers: makeMarkers())
        let missing = Marker(id: "nope", timeMicros: 0, label: "Missing", createdAt: Self.fixedDate)
        let updated = store.updating(missing)
        #expect(updated.count == 4) // Unchanged
    }

    @Test("removing a marker")
    func removing() {
        let store = MarkerStore(markers: makeMarkers())
        let updated = store.removing("m2")
        #expect(updated.count == 3)
        #expect(updated.getById("m2") == nil)
    }

    @Test("removing nonexistent marker is no-op")
    func removingNonexistent() {
        let store = MarkerStore(markers: makeMarkers())
        let updated = store.removing("nope")
        #expect(updated.count == 4)
    }

    @Test("nextMarker after time")
    func nextMarker() {
        let store = MarkerStore(markers: makeMarkers())
        let next = store.nextMarker(after: 2_000_000)
        #expect(next?.id == "m2") // timeMicros: 3_000_000
    }

    @Test("nextMarker after last returns nil")
    func nextMarkerAfterLast() {
        let store = MarkerStore(markers: makeMarkers())
        #expect(store.nextMarker(after: 8_000_000) == nil)
    }

    @Test("previousMarker before time")
    func previousMarker() {
        let store = MarkerStore(markers: makeMarkers())
        let prev = store.previousMarker(before: 4_000_000)
        #expect(prev?.id == "m2") // timeMicros: 3_000_000
    }

    @Test("previousMarker before first returns nil")
    func previousMarkerBeforeFirst() {
        let store = MarkerStore(markers: makeMarkers())
        #expect(store.previousMarker(before: 500_000) == nil)
    }

    @Test("snapToMarker within threshold")
    func snapToMarker() {
        let store = MarkerStore(markers: makeMarkers())
        let snapped = store.snapToMarker(1_050_000, thresholdMicros: 100_000)
        #expect(snapped?.id == "m1")
    }

    @Test("snapToMarker outside threshold returns nil")
    func snapToMarkerOutsideThreshold() {
        let store = MarkerStore(markers: makeMarkers())
        let snapped = store.snapToMarker(2_000_000, thresholdMicros: 100_000)
        #expect(snapped == nil) // m1 is at 1M (1M away), m2 is at 3M (1M away)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let store = MarkerStore(markers: makeMarkers())
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(MarkerStore.self, from: data)
        #expect(decoded.count == store.count)
        #expect(decoded.markers[0].id == store.markers[0].id)
    }
}
