// RippleEditController.swift
// LiquidEditor
//
// P1-13: Central handler for ripple-vs-non-ripple edits per spec §10.3.
//
// A "ripple" edit, when deleting / splitting / trimming a clip, closes
// any gap that would otherwise be left behind by shifting subsequent
// clips leftward on the same track. A "non-ripple" edit leaves the gap
// intact (useful when aligning to markers or preserving downstream sync).
//
// This controller is the single source of truth for the ripple MODE;
// callers (Trim Precision, Cut, Delete, Split, Collapse gap) ask the
// controller "should this edit ripple?" before committing to
// PersistentTimeline. The default mode comes from D0-5; per-project
// override lives in ProjectUIState.rippleEditOverride.

import Foundation
import Observation

// MARK: - RippleMode

enum RippleMode: String, Codable, Sendable {
    /// Gaps close automatically after a destructive edit.
    case on
    /// Gaps persist; timing of later clips is preserved.
    case off
}

// MARK: - RippleEditController

/// Observable controller exposing the current ripple mode.
///
/// - The `globalDefault` comes from the app-wide preference (D0-5).
/// - The `projectOverride` is set by the open project's `ProjectUIState`
///   and takes precedence when present.
@Observable
@MainActor
final class RippleEditController {

    // MARK: - State

    /// App-wide preference (D0-5).
    var globalDefault: RippleMode

    /// Per-project override. `nil` = follow global.
    var projectOverride: RippleMode?

    // MARK: - Init

    init(globalDefault: RippleMode = .on, projectOverride: RippleMode? = nil) {
        self.globalDefault = globalDefault
        self.projectOverride = projectOverride
    }

    // MARK: - API

    /// The effective mode to apply to the next edit.
    var effectiveMode: RippleMode {
        projectOverride ?? globalDefault
    }

    /// Does the next edit ripple?
    var shouldRipple: Bool { effectiveMode == .on }

    /// Temporarily invert the mode for a single gesture (e.g., shift-delete
    /// forces ripple, or plain delete forces non-ripple when the mode is on).
    /// Callers use this inside a `do { ... }` scope, passing the result
    /// to their edit command, then discarding — DO NOT mutate persistent
    /// state.
    func overridingForGesture(inverted: Bool) -> RippleMode {
        if !inverted { return effectiveMode }
        return effectiveMode == .on ? .off : .on
    }

    /// Update the project override (called when a new project opens or
    /// the user toggles via the Trim Precision chip).
    func setProjectOverride(_ mode: RippleMode?) {
        projectOverride = mode
    }

    /// Update the app-wide default (called when the user flips the
    /// toggle in App Settings ▸ Preferences).
    func setGlobalDefault(_ mode: RippleMode) {
        globalDefault = mode
    }
}
