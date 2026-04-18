// EditorShortcutCatalog.swift
// LiquidEditor
//
// Expanded keyboard-shortcut catalog for the editor (K11-1..6).
//
// Provides the display metadata used by `ShortcutOverlayView` to render
// the hold-for-help overlay grouped by category. The actual key bindings
// live in `EditorView.keyboardShortcutButtons` (SwiftUI `.keyboardShortcut`
// modifiers) so the two layers stay declaratively in sync.
//
// `ShortcutService` is the persistent/settings-display source of truth and
// is intentionally left untouched (its tests pin its shape). This catalog
// is an *additive* UI-facing list used solely by the discoverability
// overlay.

import SwiftUI

// MARK: - EditorShortcutCatalog

/// Display catalog of editor keyboard shortcuts (overlay use only).
///
/// Organised by category matching the six subtasks of K11:
///   - Playback (K11-1)
///   - Editing (K11-2)
///   - Navigation & Zoom (K11-3)
///   - Modal & View (K11-4)
///   - Markers (K11-5)
///   - Help (K11-6 — the overlay itself)
@MainActor
enum EditorShortcutCatalog {

    // MARK: - Entry

    /// Display metadata for a single shortcut in the overlay.
    struct Entry: Identifiable, Sendable {
        let label: String
        let category: String
        let displayString: String

        var id: String { "\(category).\(label)" }
    }

    // MARK: - All Entries

    /// Full list of editor shortcuts presented in the overlay, in
    /// registration order. Grouping is preserved via `category`.
    static let entries: [Entry] = [
        // K11-1: Playback
        Entry(label: "Play / Pause", category: "Playback", displayString: "Space"),
        Entry(label: "Half Speed", category: "Playback", displayString: "J"),
        Entry(label: "Pause", category: "Playback", displayString: "K"),
        Entry(label: "Double Speed", category: "Playback", displayString: "L"),

        // K11-2: Editing
        Entry(label: "Save", category: "Editing", displayString: "\u{2318}S"),
        Entry(label: "Copy", category: "Editing", displayString: "\u{2318}C"),
        Entry(label: "Paste", category: "Editing", displayString: "\u{2318}V"),
        Entry(label: "Duplicate", category: "Editing", displayString: "\u{2318}D"),
        Entry(label: "Delete", category: "Editing", displayString: "\u{232B}"),
        Entry(label: "Split at Playhead", category: "Editing", displayString: "T"),
        Entry(label: "Mark In", category: "Editing", displayString: "I"),
        Entry(label: "Mark Out", category: "Editing", displayString: "O"),

        // K11-3: Navigation & Zoom
        Entry(label: "Undo", category: "Navigation", displayString: "\u{2318}Z"),
        Entry(label: "Redo", category: "Navigation", displayString: "\u{2318}\u{21E7}Z"),
        Entry(label: "Zoom In", category: "Navigation", displayString: "\u{2318}+"),
        Entry(label: "Zoom Out", category: "Navigation", displayString: "\u{2318}-"),
        Entry(label: "Step \u{2013} Frame", category: "Navigation", displayString: "\u{2190}"),
        Entry(label: "Step + Frame", category: "Navigation", displayString: "\u{2192}"),
        Entry(label: "Step \u{2013} Second", category: "Navigation", displayString: "\u{21E7}\u{2190}"),
        Entry(label: "Step + Second", category: "Navigation", displayString: "\u{21E7}\u{2192}"),

        // K11-4: Modal & View
        Entry(label: "Dismiss / Close", category: "View", displayString: "Esc"),
        Entry(label: "Toggle Fullscreen", category: "View", displayString: "F"),
        Entry(label: "Export", category: "View", displayString: "\u{2318}E"),
        Entry(label: "New Project", category: "View", displayString: "\u{2318}N"),
        Entry(label: "Search", category: "View", displayString: "\u{2318}F"),
        Entry(label: "Cycle Tab", category: "View", displayString: "Tab"),

        // K11-5: Markers
        Entry(label: "Add Marker", category: "Markers", displayString: "M"),

        // K11-6: Help
        Entry(label: "Show Shortcuts", category: "Help", displayString: "\u{2318}?"),
    ]

    // MARK: - Derived Access

    /// Entries grouped by category, keyed by category name.
    static var grouped: [String: [Entry]] {
        Dictionary(grouping: entries, by: \.category)
    }

    /// Unique category names in the order they first appear.
    static var categories: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for entry in entries where seen.insert(entry.category).inserted {
            ordered.append(entry.category)
        }
        return ordered
    }
}
