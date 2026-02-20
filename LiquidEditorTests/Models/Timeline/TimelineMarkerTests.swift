import Testing
import Foundation
@testable import LiquidEditor

// MARK: - TimelineMarkerType Tests

@Suite("TimelineMarkerType Tests")
struct TimelineMarkerTypeTests {

    @Test("all cases")
    func allCases() {
        #expect(TimelineMarkerType.allCases.count == 5)
        #expect(TimelineMarkerType.generic.rawValue == "generic")
        #expect(TimelineMarkerType.chapter.rawValue == "chapter")
        #expect(TimelineMarkerType.todo.rawValue == "todo")
        #expect(TimelineMarkerType.sync.rawValue == "sync")
        #expect(TimelineMarkerType.beat.rawValue == "beat")
    }

    @Test("display names")
    func displayNames() {
        #expect(TimelineMarkerType.generic.displayName == "Marker")
        #expect(TimelineMarkerType.chapter.displayName == "Chapter")
        #expect(TimelineMarkerType.todo.displayName == "To-Do")
        #expect(TimelineMarkerType.sync.displayName == "Sync Point")
        #expect(TimelineMarkerType.beat.displayName == "Beat")
    }

    @Test("default colors are non-zero")
    func defaultColors() {
        for markerType in TimelineMarkerType.allCases {
            #expect(markerType.defaultColorARGB32 != 0)
        }
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for markerType in TimelineMarkerType.allCases {
            let data = try JSONEncoder().encode(markerType)
            let decoded = try JSONDecoder().decode(TimelineMarkerType.self, from: data)
            #expect(decoded == markerType)
        }
    }
}

// MARK: - TimelineMarker Tests

@Suite("TimelineMarker Tests")
struct TimelineMarkerTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1700000000)

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let marker = TimelineMarker(
            id: "tm-1",
            time: 1_000_000,
            label: "Marker 1",
            createdAt: Self.fixedDate
        )
        #expect(marker.id == "tm-1")
        #expect(marker.time == 1_000_000)
        #expect(marker.duration == nil)
        #expect(marker.label == "Marker 1")
        #expect(marker.notes == nil)
        #expect(marker.type == .generic)
        #expect(marker.colorARGB32 == TimelineMarkerType.generic.defaultColorARGB32)
        #expect(!marker.isRange)
        #expect(marker.endTime == 1_000_000) // time + 0
        #expect(marker.timeRange == nil)
    }

    @Test("creation with type uses type's default color")
    func creationWithType() {
        let marker = TimelineMarker(
            id: "tm-ch",
            time: 0,
            label: "Chapter",
            type: .chapter,
            createdAt: Self.fixedDate
        )
        #expect(marker.colorARGB32 == TimelineMarkerType.chapter.defaultColorARGB32)
    }

    @Test("creation with custom color")
    func creationCustomColor() {
        let marker = TimelineMarker(
            id: "tm-cc",
            time: 0,
            label: "Custom",
            colorARGB32: 0xFFFF0000,
            createdAt: Self.fixedDate
        )
        #expect(marker.colorARGB32 == 0xFFFF0000)
    }

    @Test("creation with duration makes range marker")
    func creationRange() {
        let marker = TimelineMarker(
            id: "tm-r",
            time: 1_000_000,
            duration: 2_000_000,
            label: "Range",
            createdAt: Self.fixedDate
        )
        #expect(marker.isRange)
        #expect(marker.endTime == 3_000_000)
        #expect(marker.timeRange != nil)
        #expect(marker.timeRange?.start == 1_000_000)
        #expect(marker.timeRange?.end == 3_000_000)
    }

    // MARK: - Factory Methods

    @Test("point factory")
    func pointFactory() {
        let marker = TimelineMarker.point(
            id: "pm-1",
            time: 500_000,
            label: "Point",
            notes: "A note",
            type: .beat
        )
        #expect(marker.id == "pm-1")
        #expect(marker.time == 500_000)
        #expect(!marker.isRange)
        #expect(marker.notes == "A note")
        #expect(marker.type == .beat)
    }

    @Test("range factory")
    func rangeFactory() {
        let marker = TimelineMarker.range(
            id: "rm-1",
            startTime: 1_000_000,
            endTime: 4_000_000,
            label: "Range",
            type: .todo
        )
        #expect(marker.isRange)
        #expect(marker.time == 1_000_000)
        #expect(marker.duration == 3_000_000)
        #expect(marker.endTime == 4_000_000)
        #expect(marker.type == .todo)
    }

    // MARK: - Computed Properties

    @Test("color property")
    func colorProperty() {
        let marker = TimelineMarker(
            id: "tm",
            time: 0,
            label: "L",
            colorARGB32: 0xFF00FF00,
            createdAt: Self.fixedDate
        )
        #expect(marker.color == ARGBColor.fromARGB32(0xFF00FF00))
    }

    @Test("isRange false for zero duration")
    func isRangeZeroDuration() {
        let marker = TimelineMarker(
            id: "tm",
            time: 0,
            duration: 0,
            label: "L",
            createdAt: Self.fixedDate
        )
        #expect(!marker.isRange)
    }

    // MARK: - Copy With

    @Test("with() copy preserves unchanged")
    func withCopy() {
        let marker = TimelineMarker(
            id: "tm",
            time: 1_000_000,
            label: "Original",
            type: .chapter,
            createdAt: Self.fixedDate
        )
        let modified = marker.with(label: "Modified")
        #expect(modified.label == "Modified")
        #expect(modified.time == 1_000_000)
        #expect(modified.type == .chapter)
        #expect(modified.id == "tm")
    }

    @Test("with() clearDuration converts to point")
    func withClearDuration() {
        let marker = TimelineMarker(
            id: "tm",
            time: 0,
            duration: 1_000_000,
            label: "Range",
            createdAt: Self.fixedDate
        )
        #expect(marker.isRange)
        let point = marker.with(clearDuration: true)
        #expect(!point.isRange)
        #expect(point.duration == nil)
    }

    @Test("with() clearNotes")
    func withClearNotes() {
        let marker = TimelineMarker(
            id: "tm",
            time: 0,
            label: "L",
            notes: "Some notes",
            createdAt: Self.fixedDate
        )
        let cleared = marker.with(clearNotes: true)
        #expect(cleared.notes == nil)
    }

    // MARK: - Move Operations

    @Test("moveTo")
    func moveTo() {
        let marker = TimelineMarker(
            id: "tm",
            time: 1_000_000,
            label: "M",
            createdAt: Self.fixedDate
        )
        let moved = marker.moveTo(5_000_000)
        #expect(moved.time == 5_000_000)
    }

    @Test("moveBy")
    func moveBy() {
        let marker = TimelineMarker(
            id: "tm",
            time: 1_000_000,
            label: "M",
            createdAt: Self.fixedDate
        )
        let moved = marker.moveBy(500_000)
        #expect(moved.time == 1_500_000)
    }

    @Test("moveBy negative")
    func moveByNegative() {
        let marker = TimelineMarker(
            id: "tm",
            time: 3_000_000,
            label: "M",
            createdAt: Self.fixedDate
        )
        let moved = marker.moveBy(-1_000_000)
        #expect(moved.time == 2_000_000)
    }

    // MARK: - withDuration

    @Test("withDuration positive creates range")
    func withDurationPositive() {
        let marker = TimelineMarker(
            id: "tm",
            time: 0,
            label: "L",
            createdAt: Self.fixedDate
        )
        let ranged = marker.withDuration(2_000_000)
        #expect(ranged.isRange)
        #expect(ranged.duration == 2_000_000)
    }

    @Test("withDuration nil converts to point")
    func withDurationNil() {
        let marker = TimelineMarker(
            id: "tm",
            time: 0,
            duration: 1_000_000,
            label: "L",
            createdAt: Self.fixedDate
        )
        let point = marker.withDuration(nil)
        #expect(!point.isRange)
    }

    @Test("withDuration zero converts to point")
    func withDurationZero() {
        let marker = TimelineMarker(
            id: "tm",
            time: 0,
            duration: 1_000_000,
            label: "L",
            createdAt: Self.fixedDate
        )
        let point = marker.withDuration(0)
        #expect(!point.isRange)
    }

    // MARK: - Codable

    @Test("Codable roundtrip point marker")
    func codablePoint() throws {
        let marker = TimelineMarker(
            id: "tm-codec",
            time: 2_000_000,
            label: "Codec Test",
            notes: "Note text",
            type: .sync,
            colorARGB32: 0xFFABCDEF,
            createdAt: Self.fixedDate
        )
        let data = try JSONEncoder().encode(marker)
        let decoded = try JSONDecoder().decode(TimelineMarker.self, from: data)
        #expect(decoded.id == marker.id)
        #expect(decoded.time == marker.time)
        #expect(decoded.duration == nil)
        #expect(decoded.label == marker.label)
        #expect(decoded.notes == "Note text")
        #expect(decoded.type == .sync)
        #expect(decoded.colorARGB32 == 0xFFABCDEF)
    }

    @Test("Codable roundtrip range marker")
    func codableRange() throws {
        let marker = TimelineMarker.range(
            id: "tm-range-codec",
            startTime: 1_000_000,
            endTime: 4_000_000,
            label: "Range Codec",
            type: .chapter
        )
        let data = try JSONEncoder().encode(marker)
        let decoded = try JSONDecoder().decode(TimelineMarker.self, from: data)
        #expect(decoded.isRange)
        #expect(decoded.time == 1_000_000)
        #expect(decoded.duration == 3_000_000)
        #expect(decoded.type == .chapter)
    }

    @Test("Codable createdAt uses ISO8601")
    func codableCreatedAtFormat() throws {
        let marker = TimelineMarker(
            id: "tm-date",
            time: 0,
            label: "Date",
            createdAt: Self.fixedDate
        )
        let data = try JSONEncoder().encode(marker)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let dateStr = json["createdAt"] as? String
        #expect(dateStr != nil)
        // Should be ISO 8601 format
        let formatter = ISO8601DateFormatter()
        let parsed = formatter.date(from: dateStr!)
        #expect(parsed != nil)
    }
}
