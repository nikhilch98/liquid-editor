// AccessibilityIdentifiers.swift
// LiquidEditor
//
// Stable accessibility identifiers for Switch Control, Voice Control,
// and UI testing. Identifiers are namespaced as
// "<scope>.<role>.<action>" (e.g. "editor.toolbar.split") so they
// remain stable across refactors and localization changes.
//
// Accessibility identifiers are NOT user-visible text — VoiceOver still
// reads `.accessibilityLabel`. They are consumed by:
// - Voice Control ("Tap editor toolbar split")
// - Switch Control (directional scanning)
// - UI tests (XCUIElement queries)
//
// See Apple HIG: Accessibility / Voice Control.

import SwiftUI

// MARK: - AccessibilityIdentifiers

/// Namespaced stable identifiers for Voice Control / Switch Control / UI tests.
///
/// Keep identifiers short and consistent. Prefer the established
/// "scope.role.action" pattern; all segments are lowercase with dots
/// as separators and no whitespace.
enum AccessibilityIdentifiers {

    // MARK: - Editor Toolbar

    enum EditorToolbar {
        static let trim = "editor.toolbar.trim"
        static let split = "editor.toolbar.split"
        static let copy = "editor.toolbar.copy"
        static let delete = "editor.toolbar.delete"
        static let tracks = "editor.toolbar.tracks"

        static let filters = "editor.toolbar.filters"
        static let effects = "editor.toolbar.effects"
        static let transition = "editor.toolbar.transition"
        static let adjust = "editor.toolbar.adjust"
        static let crop = "editor.toolbar.crop"

        static let text = "editor.toolbar.text"
        static let sticker = "editor.toolbar.sticker"

        static let volume = "editor.toolbar.volume"
        static let speed = "editor.toolbar.speed"
        static let voice = "editor.toolbar.voice"
        static let mute = "editor.toolbar.mute"

        static let track = "editor.toolbar.track"
        static let reframe = "editor.toolbar.reframe"
        static let debug = "editor.toolbar.debug"
    }

    // MARK: - Editor Tabs

    enum EditorTab {
        static let edit = "editor.tab.edit"
        static let fx = "editor.tab.fx"
        static let overlay = "editor.tab.overlay"
        static let audio = "editor.tab.audio"
        static let smart = "editor.tab.smart"
    }

    // MARK: - Editor Navigation Bar

    enum EditorNav {
        static let close = "editor.nav.close"
        static let project = "editor.nav.project"
        static let more = "editor.nav.more"
        static let export = "editor.nav.export"
    }

    // MARK: - Timeline

    enum Timeline {
        static let ruler = "timeline.ruler"
        static let playhead = "timeline.playhead"

        /// Per-clip identifier builder: "timeline.clip.<id>".
        static func clip(_ id: String) -> String { "timeline.clip.\(id)" }

        /// Per-track mute button: "timeline.track.mute.<id>".
        static func trackMute(_ id: String) -> String { "timeline.track.mute.\(id)" }

        /// Per-track lock button: "timeline.track.lock.<id>".
        static func trackLock(_ id: String) -> String { "timeline.track.lock.\(id)" }
    }

    // MARK: - Sheets (Primary Actions)

    enum Sheet {
        static let exportConfirm = "sheet.export.confirm"
        static let exportCancel = "sheet.export.cancel"
        static let saveConfirm = "sheet.save.confirm"
        static let saveCancel = "sheet.save.cancel"
        static let importConfirm = "sheet.import.confirm"
        static let importCancel = "sheet.import.cancel"
    }

    // MARK: - Project Library

    enum Library {
        /// Per-project card identifier: "library.card.<id>".
        static func projectCard(_ id: String) -> String { "library.card.\(id)" }
    }
}
