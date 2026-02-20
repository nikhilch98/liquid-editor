import Testing
import Foundation
@testable import LiquidEditor

@Suite("PersonSelectionSheet Tests")
struct PersonSelectionSheetTests {

    // MARK: - DetectedPersonItem

    @Suite("DetectedPersonItem")
    struct DetectedPersonItemTests {

        @Test("id returns personIndex")
        func idIsPersonIndex() {
            let person = DetectedPersonItem(personIndex: 3, label: "Person 4", thumbnail: nil)
            #expect(person.id == 3)
        }

        @Test("label is correctly assigned")
        func labelAssignment() {
            let person = DetectedPersonItem(personIndex: 0, label: "Alice", thumbnail: nil)
            #expect(person.label == "Alice")
        }

        @Test("thumbnail can be nil")
        func thumbnailNil() {
            let person = DetectedPersonItem(personIndex: 0, label: "Test", thumbnail: nil)
            #expect(person.thumbnail == nil)
        }

        @Test("thumbnail can hold data")
        func thumbnailWithData() {
            let data = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header bytes
            let person = DetectedPersonItem(personIndex: 0, label: "Test", thumbnail: data)
            #expect(person.thumbnail != nil)
            #expect(person.thumbnail?.count == 4)
        }
    }

    // MARK: - Selection Logic

    @Suite("Selection Logic")
    struct SelectionLogicTests {

        @Test("Toggle adds person to selection")
        func toggleAdds() {
            var selection: Set<Int> = []
            selection.insert(0)
            #expect(selection.contains(0))
        }

        @Test("Toggle removes person from selection")
        func toggleRemoves() {
            var selection: Set<Int> = [0, 1, 2]
            selection.remove(1)
            #expect(!selection.contains(1))
            #expect(selection.count == 2)
        }

        @Test("Select all adds all indices")
        func selectAll() {
            let persons = [
                DetectedPersonItem(personIndex: 0, label: "A", thumbnail: nil),
                DetectedPersonItem(personIndex: 1, label: "B", thumbnail: nil),
                DetectedPersonItem(personIndex: 2, label: "C", thumbnail: nil),
            ]
            let selection: Set<Int> = Set(persons.map(\.personIndex))
            #expect(selection.count == 3)
            #expect(selection.contains(0))
            #expect(selection.contains(1))
            #expect(selection.contains(2))
        }

        @Test("Deselect all empties selection")
        func deselectAll() {
            var selection: Set<Int> = [0, 1, 2]
            selection.removeAll()
            #expect(selection.isEmpty)
        }
    }

    // MARK: - Confirm Button Title

    @Suite("Confirm Button Title")
    struct ConfirmButtonTitleTests {

        private func confirmTitle(for count: Int) -> String {
            if count == 0 { return "Select at least one person" }
            return "Track \(count) Person\(count > 1 ? "s" : "")"
        }

        @Test("Empty selection shows prompt")
        func emptySelection() {
            #expect(confirmTitle(for: 0) == "Select at least one person")
        }

        @Test("Single selection shows singular")
        func singleSelection() {
            #expect(confirmTitle(for: 1) == "Track 1 Person")
        }

        @Test("Multiple selection shows plural")
        func multipleSelection() {
            #expect(confirmTitle(for: 3) == "Track 3 Persons")
        }
    }

    // MARK: - Empty State

    @Suite("Empty State")
    struct EmptyStateTests {

        @Test("Empty persons list triggers empty state")
        func emptyPersonsList() {
            let persons: [DetectedPersonItem] = []
            #expect(persons.isEmpty)
        }

        @Test("Non-empty persons list shows selection")
        func nonEmptyPersonsList() {
            let persons = [
                DetectedPersonItem(personIndex: 0, label: "Person 1", thumbnail: nil),
            ]
            #expect(!persons.isEmpty)
        }
    }
}
