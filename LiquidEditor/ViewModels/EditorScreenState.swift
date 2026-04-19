// EditorScreenState.swift
// LiquidEditor
//
// S2-4: screen-state machine for the editor.
//
// The editor has several high-level lifecycle phases that need to drive
// chrome (progress bars, overlays, disabled CTAs, error toasts). Prior to
// this file those phases lived as loose `Bool` flags on `EditorViewModel`
// (`isLoading`, `errorMessage`, `showExportSheet`, etc.) which made it
// easy to produce impossible combinations such as "loading AND error AND
// ready". Centralising the phase into a finite state machine restores the
// invariant that the editor is in **exactly one** screen state at a time.
//
// States:
//   - empty     — no project content yet, awaiting import.
//   - importing — user is bringing media in (photos picker, drag-drop).
//   - analyzing — post-import analysis (waveform, scene detect, people).
//   - rendering — export or background composition render.
//   - error     — terminal for the current flow, user must acknowledge.
//   - ready     — normal editing.
//
// Illegal transitions are a no-op plus a warning-level log so we can catch
// them in QA without crashing production.

import Foundation
import OSLog

// MARK: - EditorScreenState

/// High-level phase of the editor screen.
///
/// Designed to be `Equatable` so SwiftUI can diff it cheaply, and
/// `Sendable` so the machine can be driven from background tasks.
enum EditorScreenState: Sendable, Equatable {

    /// Empty project — no media imported yet.
    case empty

    /// Importing media from an external source. `progress` is 0...1.
    case importing(progress: Double)

    /// Running post-import analysis. `step` is a human-readable label
    /// ("Generating waveform", "Detecting scenes", …).
    case analyzing(step: String)

    /// Export or background render in progress. `progress` is 0...1.
    case rendering(progress: Double)

    /// Terminal error for the current flow. `message` is user-facing.
    case error(message: String)

    /// Normal editing state.
    case ready

    /// Debug tag used in logs.
    var tag: String {
        switch self {
        case .empty:       return "empty"
        case .importing:   return "importing"
        case .analyzing:   return "analyzing"
        case .rendering:   return "rendering"
        case .error:       return "error"
        case .ready:       return "ready"
        }
    }

    /// Whether this state should disable destructive editor actions.
    var blocksEditing: Bool {
        switch self {
        case .importing, .analyzing, .rendering, .error:
            return true
        case .empty, .ready:
            return false
        }
    }
}

// MARK: - EditorScreenStateMachine

/// @Observable state machine for the editor screen.
///
/// Guards every mutation through a `canTransition(from:to:)` predicate so
/// illegal paths (e.g. `ready -> importing(progress:)` after an export has
/// already started) are rejected at the source. Rejected transitions do not
/// crash; they log a warning and leave state untouched, which matches the
/// "zero-defect but fail-soft" contract of the editor.
@MainActor
@Observable
final class EditorScreenStateMachine {

    // MARK: - Logger

    @ObservationIgnored
    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "EditorScreenState"
    )

    // MARK: - Public state

    /// Current state. External callers should treat this as read-only and
    /// use the `*Started` / `*Progress` / `*Completed` API below.
    private(set) var state: EditorScreenState = .empty

    // MARK: - Init

    init(initial: EditorScreenState = .empty) {
        self.state = initial
    }

    // MARK: - Transition API — Import

    /// User kicked off an import (PhotosPicker, drag-drop, share sheet).
    func importStarted() {
        transition(to: .importing(progress: 0.0))
    }

    /// Report import progress. Values are clamped to `[0, 1]`. If the
    /// machine is not currently in `.importing`, the update is ignored.
    func importProgress(_ value: Double) {
        guard case .importing = state else {
            Self.logger.warning("importProgress ignored in state \(self.state.tag)")
            return
        }
        let clamped = min(max(value, 0.0), 1.0)
        transition(to: .importing(progress: clamped), logIfBlocked: false)
    }

    /// Import finished successfully. Moves to analysing if the caller
    /// intends to run post-import analysis, otherwise to `.ready`.
    /// Defaults to analysing because every real import produces derivables.
    func importCompleted(runAnalysis: Bool = true) {
        if runAnalysis {
            transition(to: .analyzing(step: "Preparing media"))
        } else {
            transition(to: .ready)
        }
    }

    // MARK: - Transition API — Analyse

    /// Analysis phase started (may be called immediately after import or
    /// independently when the user triggers a re-analyse from settings).
    func analysisStarted(step: String = "Analyzing") {
        transition(to: .analyzing(step: step))
    }

    /// Update the human-readable analysis step.
    func analysisStep(_ step: String) {
        guard case .analyzing = state else {
            Self.logger.warning("analysisStep ignored in state \(self.state.tag)")
            return
        }
        transition(to: .analyzing(step: step), logIfBlocked: false)
    }

    /// Analysis phase completed. Moves to `.ready`.
    func analysisCompleted() {
        transition(to: .ready)
    }

    // MARK: - Transition API — Render / Export

    /// Export or background render started. Only valid from `.ready`.
    func renderStarted() {
        transition(to: .rendering(progress: 0.0))
    }

    /// Report render progress. Values are clamped to `[0, 1]`.
    func renderProgress(_ value: Double) {
        guard case .rendering = state else {
            Self.logger.warning("renderProgress ignored in state \(self.state.tag)")
            return
        }
        let clamped = min(max(value, 0.0), 1.0)
        transition(to: .rendering(progress: clamped), logIfBlocked: false)
    }

    /// Render finished successfully.
    func renderCompleted() {
        transition(to: .ready)
    }

    // MARK: - Transition API — Error / Reset

    /// Transition into `.error`. Allowed from any state.
    func errored(_ message: String) {
        transition(to: .error(message: message))
    }

    /// Acknowledge the current error and return to `.ready` if media is
    /// present, otherwise `.empty`.
    func clearError(hasMedia: Bool) {
        guard case .error = state else { return }
        transition(to: hasMedia ? .ready : .empty)
    }

    /// Force-reset to `.empty`. Used when closing a project or swapping
    /// projects inside a multi-project library flow.
    func reset() {
        // Reset is always allowed — it bypasses the transition guard.
        state = .empty
    }

    // MARK: - Introspection

    /// Is the machine currently busy with a background operation?
    var isBusy: Bool {
        switch state {
        case .importing, .analyzing, .rendering: return true
        case .empty, .ready, .error:            return false
        }
    }

    /// Last known progress value for progress-bearing states. Returns nil
    /// when the state has no meaningful progress.
    var progress: Double? {
        switch state {
        case .importing(let p), .rendering(let p):
            return p
        case .empty, .analyzing, .error, .ready:
            return nil
        }
    }

    // MARK: - Private — transition guard

    /// Core transition method. Validates the move and logs a warning for
    /// illegal transitions.
    private func transition(to next: EditorScreenState, logIfBlocked: Bool = true) {
        let current = state
        guard Self.canTransition(from: current, to: next) else {
            if logIfBlocked {
                Self.logger.warning(
                    "Illegal transition \(current.tag) -> \(next.tag); staying in \(current.tag)"
                )
            }
            return
        }
        state = next
    }

    /// Transition predicate.
    ///
    /// Rules:
    /// - `.error` can be entered from any state.
    /// - `.empty` can only be entered by `reset()` (not via `transition`).
    /// - `.importing` is only legal from `.empty` or `.ready` (re-import).
    /// - `.analyzing` is legal from `.importing` (auto-flow) or `.ready`.
    /// - `.rendering` is legal only from `.ready`.
    /// - `.ready` can be reached from any non-empty non-error state, and
    ///   from `.error` via `clearError`.
    /// - Intra-state progress updates (e.g. `.importing(p1) -> .importing(p2)`)
    ///   are always legal; handled by the case pattern below.
    static func canTransition(
        from current: EditorScreenState,
        to next: EditorScreenState
    ) -> Bool {
        // Intra-state progress updates: importing -> importing, rendering -> rendering,
        // analyzing -> analyzing. Always legal.
        switch (current, next) {
        case (.importing, .importing),
             (.rendering, .rendering),
             (.analyzing, .analyzing):
            return true
        default:
            break
        }

        // Error is an absorbing state reachable from everywhere.
        if case .error = next { return true }

        switch (current, next) {
        case (.empty, .importing),
             (.empty, .ready):
            return true

        case (.importing, .analyzing),
             (.importing, .ready):
            return true

        case (.analyzing, .ready):
            return true

        case (.rendering, .ready):
            return true

        case (.ready, .importing),
             (.ready, .analyzing),
             (.ready, .rendering):
            return true

        case (.error, .ready),
             (.error, .empty):
            return true

        default:
            return false
        }
    }
}
