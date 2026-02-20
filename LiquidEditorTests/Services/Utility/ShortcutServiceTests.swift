import Testing
import Foundation
import SwiftUI
@testable import LiquidEditor

@Suite("ShortcutService Tests")
@MainActor
struct ShortcutServiceTests {

    // MARK: - Bindings

    @Suite("Bindings")
    struct BindingsTests {

        @Test("Has expected number of bindings")
        @MainActor
        func bindingCount() {
            let service = ShortcutService.shared
            #expect(service.bindings.count == 12)
        }

        @Test("Each binding has a non-empty label")
        @MainActor
        func labelsNonEmpty() {
            let service = ShortcutService.shared
            for binding in service.bindings {
                #expect(!binding.label.isEmpty)
            }
        }

        @Test("Each binding has a non-empty category")
        @MainActor
        func categoriesNonEmpty() {
            let service = ShortcutService.shared
            for binding in service.bindings {
                #expect(!binding.category.isEmpty)
            }
        }

        @Test("Each binding has a non-empty displayString")
        @MainActor
        func displayStringsNonEmpty() {
            let service = ShortcutService.shared
            for binding in service.bindings {
                #expect(!binding.displayString.isEmpty)
            }
        }

        @Test("Each binding has a unique id")
        @MainActor
        func uniqueIds() {
            let service = ShortcutService.shared
            let ids = service.bindings.map(\.id)
            let uniqueIds = Set(ids)
            // There are two "Delete Clip" entries in Flutter but we only have one here
            #expect(uniqueIds.count == ids.count)
        }
    }

    // MARK: - Categories

    @Suite("Categories")
    struct CategoryTests {

        @Test("Has 3 categories: Playback, Editing, File")
        @MainActor
        func categoryNames() {
            let service = ShortcutService.shared
            let categories = service.categories
            #expect(categories.count == 3)
            #expect(categories.contains("Playback"))
            #expect(categories.contains("Editing"))
            #expect(categories.contains("File"))
        }

        @Test("Playback category has 4 shortcuts")
        @MainActor
        func playbackCount() {
            let service = ShortcutService.shared
            #expect(service.count(inCategory: "Playback") == 4)
        }

        @Test("Editing category has 6 shortcuts")
        @MainActor
        func editingCount() {
            let service = ShortcutService.shared
            #expect(service.count(inCategory: "Editing") == 6)
        }

        @Test("File category has 2 shortcuts")
        @MainActor
        func fileCount() {
            let service = ShortcutService.shared
            #expect(service.count(inCategory: "File") == 2)
        }

        @Test("Unknown category returns 0")
        @MainActor
        func unknownCategory() {
            let service = ShortcutService.shared
            #expect(service.count(inCategory: "Nonexistent") == 0)
        }
    }

    // MARK: - Grouped Bindings

    @Suite("Grouped Bindings")
    struct GroupedTests {

        @Test("groupedBindings matches categories")
        @MainActor
        func groupedKeys() {
            let service = ShortcutService.shared
            let grouped = service.groupedBindings
            #expect(grouped.keys.count == 3)
            #expect(grouped["Playback"] != nil)
            #expect(grouped["Editing"] != nil)
            #expect(grouped["File"] != nil)
        }
    }

    // MARK: - Lookup

    @Suite("Lookup")
    struct LookupTests {

        @Test("Can find binding by label")
        @MainActor
        func findByLabel() {
            let service = ShortcutService.shared
            let undoBinding = service.binding(forLabel: "Undo")
            #expect(undoBinding != nil)
            #expect(undoBinding?.category == "Editing")
            #expect(undoBinding?.displayString == "\u{2318}Z")
        }

        @Test("Returns nil for unknown label")
        @MainActor
        func unknownLabel() {
            let service = ShortcutService.shared
            #expect(service.binding(forLabel: "Nonexistent") == nil)
        }

        @Test("Play/Pause binding uses Space key")
        @MainActor
        func playPauseKey() {
            let service = ShortcutService.shared
            let binding = service.binding(forLabel: "Play / Pause")
            #expect(binding != nil)
            #expect(binding?.displayString == "Space")
        }
    }

    // MARK: - Modifier Description

    @Suite("Modifier Description")
    struct ModifierTests {

        @Test("Command modifier produces command symbol")
        @MainActor
        func commandSymbol() {
            let desc = ShortcutService.describeModifiers(.command)
            #expect(desc == "\u{2318}")
        }

        @Test("Shift modifier produces shift symbol")
        @MainActor
        func shiftSymbol() {
            let desc = ShortcutService.describeModifiers(.shift)
            #expect(desc == "\u{21E7}")
        }

        @Test("Empty modifiers produces empty string")
        @MainActor
        func emptyModifiers() {
            let desc = ShortcutService.describeModifiers([])
            #expect(desc == "")
        }

        @Test("Combined modifiers produce combined symbols")
        @MainActor
        func combinedModifiers() {
            let desc = ShortcutService.describeModifiers([.command, .shift])
            #expect(desc.contains("\u{2318}"))
            #expect(desc.contains("\u{21E7}"))
        }
    }

    // MARK: - EditorAction

    @Suite("EditorAction")
    struct ActionTests {

        @Test("allCases contains 12 actions")
        func allCasesCount() {
            #expect(EditorAction.allCases.count == 12)
        }

        @Test("Each action has a unique rawValue")
        func uniqueRawValues() {
            let rawValues = Set(EditorAction.allCases.map(\.rawValue))
            #expect(rawValues.count == EditorAction.allCases.count)
        }
    }
}
