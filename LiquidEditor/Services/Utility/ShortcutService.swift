// ShortcutService.swift
// LiquidEditor
//
// Keyboard shortcut bindings for iPad and Mac Catalyst.
// Defines all editor shortcuts with their key combinations,
// categories, and display symbols. Provides grouped access
// for settings UI and key equivalent descriptions.

import SwiftUI

// MARK: - ShortcutBinding

/// Defines a single keyboard shortcut binding.
struct ShortcutBinding: Identifiable, Sendable {

    /// Unique identifier (derived from label + key).
    var id: String { "\(category).\(label)" }

    /// Human-readable label for the shortcut.
    let label: String

    /// Category for grouping in settings display.
    let category: String

    /// The key equivalent (e.g., "z", " ").
    let key: KeyEquivalent

    /// Modifier keys (e.g., .command, .shift).
    let modifiers: EventModifiers

    /// Human-readable description of the key combination (e.g., "\u{2318}Z").
    let displayString: String
}

// MARK: - EditorAction

/// Actions that can be triggered by keyboard shortcuts.
enum EditorAction: String, CaseIterable, Sendable {
    case playPause
    case stepForward
    case stepBackward
    case toggleFullscreen
    case undo
    case redo
    case deleteClip
    case splitAtPlayhead
    case copyClip
    case pasteClip
    case save
    case export
}

// MARK: - ShortcutService

/// Manages keyboard shortcuts for the editor.
///
/// Provides a list of all registered bindings, grouped access by
/// category, and human-readable descriptions of key combinations
/// for display in the settings screen.
@MainActor
final class ShortcutService: Sendable {

    // MARK: - Singleton

    static let shared = ShortcutService()

    // MARK: - Bindings

    /// All registered shortcut bindings.
    let bindings: [ShortcutBinding] = [
        // Playback
        ShortcutBinding(
            label: "Play / Pause",
            category: "Playback",
            key: " ",
            modifiers: [],
            displayString: "Space"
        ),
        ShortcutBinding(
            label: "Step Forward",
            category: "Playback",
            key: .rightArrow,
            modifiers: [],
            displayString: "\u{2192}"
        ),
        ShortcutBinding(
            label: "Step Backward",
            category: "Playback",
            key: .leftArrow,
            modifiers: [],
            displayString: "\u{2190}"
        ),
        ShortcutBinding(
            label: "Toggle Fullscreen",
            category: "Playback",
            key: "f",
            modifiers: [],
            displayString: "F"
        ),

        // Editing
        ShortcutBinding(
            label: "Undo",
            category: "Editing",
            key: "z",
            modifiers: .command,
            displayString: "\u{2318}Z"
        ),
        ShortcutBinding(
            label: "Redo",
            category: "Editing",
            key: "z",
            modifiers: [.command, .shift],
            displayString: "\u{2318}\u{21E7}Z"
        ),
        ShortcutBinding(
            label: "Delete Clip",
            category: "Editing",
            key: .delete,
            modifiers: [],
            displayString: "\u{232B}"
        ),
        ShortcutBinding(
            label: "Split at Playhead",
            category: "Editing",
            key: "b",
            modifiers: .command,
            displayString: "\u{2318}B"
        ),
        ShortcutBinding(
            label: "Copy Clip",
            category: "Editing",
            key: "c",
            modifiers: .command,
            displayString: "\u{2318}C"
        ),
        ShortcutBinding(
            label: "Paste Clip",
            category: "Editing",
            key: "v",
            modifiers: .command,
            displayString: "\u{2318}V"
        ),

        // File
        ShortcutBinding(
            label: "Save",
            category: "File",
            key: "s",
            modifiers: .command,
            displayString: "\u{2318}S"
        ),
        ShortcutBinding(
            label: "Export",
            category: "File",
            key: "e",
            modifiers: .command,
            displayString: "\u{2318}E"
        ),
    ]

    // MARK: - Grouped Access

    /// Get bindings grouped by category for settings display.
    var groupedBindings: [String: [ShortcutBinding]] {
        Dictionary(grouping: bindings, by: \.category)
    }

    /// Get all unique category names in registration order.
    var categories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for binding in bindings {
            if seen.insert(binding.category).inserted {
                result.append(binding.category)
            }
        }
        return result
    }

    /// Find a binding by label.
    ///
    /// - Parameter label: The binding label to search for.
    /// - Returns: The first matching binding, or `nil`.
    func binding(forLabel label: String) -> ShortcutBinding? {
        bindings.first { $0.label == label }
    }

    /// Get the number of bindings in a category.
    ///
    /// - Parameter category: The category name.
    /// - Returns: The count of bindings in that category.
    func count(inCategory category: String) -> Int {
        bindings.filter { $0.category == category }.count
    }

    // MARK: - Key Symbol Helpers

    /// Human-readable description for modifier flags.
    ///
    /// - Parameter modifiers: The event modifiers to describe.
    /// - Returns: A string of modifier symbols (e.g., "\u{2318}\u{21E7}").
    static func describeModifiers(_ modifiers: EventModifiers) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option) { parts.append("\u{2325}") }
        if modifiers.contains(.shift) { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }
        return parts.joined()
    }
}
