// ShortcutRegistryTests.swift
// TT13-8: ShortcutRegistry tests.
//
// Covers register / register-with-label / lookup / replace / count /
// unregisterAll edge cases for the central shortcut registry used by
// KeyboardShortcutProvider (P1-9, spec §10.5).

import Testing
import SwiftUI
@testable import LiquidEditor

@MainActor
@Suite("ShortcutRegistry")
struct ShortcutRegistryTests {

    // MARK: - Empty state

    @Test("Registry starts empty")
    func startsEmpty() {
        let r = ShortcutRegistry()
        #expect(r.bindings.isEmpty)
        #expect(r.bindings.count == 0)
    }

    // MARK: - register

    @Test("register appends a binding with default empty label")
    func registerDefaultLabel() {
        let r = ShortcutRegistry()
        r.register(.space) { }
        #expect(r.bindings.count == 1)
        #expect(r.bindings.first?.label == "")
    }

    @Test("register-with-label stores the provided label")
    func registerWithLabel() {
        let r = ShortcutRegistry()
        r.register(.space, label: "Play / Pause") { }
        #expect(r.bindings.count == 1)
        #expect(r.bindings.first?.label == "Play / Pause")
    }

    @Test("register preserves insertion order")
    func registerOrdered() {
        let r = ShortcutRegistry()
        r.register(.space, label: "first") { }
        r.register(.escape, label: "second") { }
        r.register(KeyboardShortcut("s", modifiers: .command), label: "third") { }
        #expect(r.bindings.count == 3)
        #expect(r.bindings.map(\.label) == ["first", "second", "third"])
    }

    // MARK: - Unique IDs

    @Test("Each registered binding has a unique id")
    func uniqueIDs() {
        let r = ShortcutRegistry()
        r.register(.space, label: "a") { }
        r.register(.space, label: "b") { }
        let ids = Set(r.bindings.map(\.id))
        #expect(ids.count == 2)
    }

    // MARK: - Replace / duplicates

    @Test("Registering the same shortcut twice keeps both bindings (append semantics)")
    func duplicateShortcutsAppend() {
        let r = ShortcutRegistry()
        r.register(.space, label: "old") { }
        r.register(.space, label: "new") { }
        #expect(r.bindings.count == 2)
        #expect(r.bindings.last?.label == "new")
    }

    // MARK: - action dispatch

    @Test("Stored action is invoked when called directly")
    func actionIsStored() {
        let r = ShortcutRegistry()
        var hits = 0
        r.register(.space, label: "inc") { hits += 1 }
        r.bindings.first?.action()
        r.bindings.first?.action()
        #expect(hits == 2)
    }

    // MARK: - unregisterAll

    @Test("unregisterAll clears every binding")
    func unregisterAll() {
        let r = ShortcutRegistry()
        r.register(.space) { }
        r.register(.escape) { }
        r.register(KeyboardShortcut("d", modifiers: .command)) { }
        #expect(r.bindings.count == 3)
        r.unregisterAll()
        #expect(r.bindings.isEmpty)
    }

    @Test("unregisterAll on empty registry is a no-op")
    func unregisterAllEmpty() {
        let r = ShortcutRegistry()
        r.unregisterAll()
        #expect(r.bindings.isEmpty)
    }

    @Test("Registry accepts new bindings after unregisterAll")
    func reRegisterAfterClear() {
        let r = ShortcutRegistry()
        r.register(.space) { }
        r.unregisterAll()
        r.register(.escape, label: "dismiss") { }
        #expect(r.bindings.count == 1)
        #expect(r.bindings.first?.label == "dismiss")
    }

    // MARK: - Built-in shortcuts

    @Test("Built-in .space and .escape shortcuts have no modifiers")
    func builtInShortcuts() {
        #expect(KeyboardShortcut.space.modifiers.isEmpty)
        #expect(KeyboardShortcut.escape.modifiers.isEmpty)
    }
}
