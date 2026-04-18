// ExportJobState.swift
// LiquidEditor
//
// Finite state machine for an individual export job's lifecycle.
//
// NOTE: `ExportState` already exists in ExportViewModel.swift and is used by
// the legacy ExportSheet. `ExportJobState` is a parallel, more expressive
// state model introduced for the redesigned Export screens (S2-8 / S2-9).
// Migration of ExportViewModel to drive its state from this machine is a
// follow-up; for now the two coexist intentionally.

import Foundation
import os

// MARK: - ExportJobState

/// State of a single export job as seen by the redesigned Export UI.
///
/// This is a presentation-oriented state separate from `ExportJobStatus`
/// (queue-level granularity) and `ExportPhase` (pipeline granularity).
///
/// Usage:
/// ```swift
/// let machine = ExportJobStateMachine()
/// machine.transition(to: .exporting(progress: 0.42, eta: 12))
/// ```
enum ExportJobState: Sendable, Equatable {

    /// No export has been started.
    case idle

    /// An export is running.
    ///
    /// - `progress`: 0.0 to 1.0.
    /// - `eta`: estimated seconds remaining.
    case exporting(progress: Double, eta: TimeInterval)

    /// An export finished successfully. `url` points to the output file.
    case success(url: URL)

    /// An export failed. `message` is a user-visible reason.
    case error(message: String)

    /// The export was cancelled by the user.
    case cancelled

    // MARK: - Convenience Flags

    /// Whether the state represents an actively running export.
    var isRunning: Bool {
        if case .exporting = self { return true }
        return false
    }

    /// Whether the state is a terminal one (success / error / cancelled).
    var isTerminal: Bool {
        switch self {
        case .idle, .exporting:
            return false
        case .success, .error, .cancelled:
            return true
        }
    }

    /// Progress value if currently exporting, else nil.
    var progressValue: Double? {
        if case let .exporting(progress, _) = self { return progress }
        return nil
    }

    /// ETA in seconds if currently exporting, else nil.
    var etaSeconds: TimeInterval? {
        if case let .exporting(_, eta) = self { return eta }
        return nil
    }

    /// User-visible label for the state.
    var displayLabel: String {
        switch self {
        case .idle: return "Idle"
        case .exporting: return "Exporting"
        case .success: return "Done"
        case .error: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - ExportJobStateMachine

/// Observable wrapper that manages the current `ExportJobState` for a single
/// export UI.
///
/// Transitions are validated against a small reachability table to prevent
/// nonsensical moves (e.g. success -> exporting). Invalid transitions are
/// logged and ignored.
@Observable
@MainActor
final class ExportJobStateMachine {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "ExportJobStateMachine"
    )

    // MARK: - State

    /// The current state. Observable by SwiftUI views.
    private(set) var state: ExportJobState = .idle

    // MARK: - Init

    init(initial: ExportJobState = .idle) {
        self.state = initial
    }

    // MARK: - Transitions

    /// Attempt to transition to the given state.
    ///
    /// - Parameter newState: The desired next state.
    /// - Returns: `true` if the transition was accepted, `false` if it was
    ///   rejected as invalid.
    @discardableResult
    func transition(to newState: ExportJobState) -> Bool {
        guard Self.isValid(from: state, to: newState) else {
            Self.logger.warning(
                "Rejected invalid transition \(String(describing: self.state), privacy: .public) -> \(String(describing: newState), privacy: .public)"
            )
            return false
        }
        state = newState
        return true
    }

    /// Cancel the current export, if one is running or queued.
    ///
    /// No-op when already terminal.
    func cancel() {
        switch state {
        case .idle, .exporting:
            state = .cancelled
        case .success, .error, .cancelled:
            // Terminal — nothing to cancel.
            Self.logger.info("cancel() called on terminal state \(String(describing: self.state), privacy: .public)")
        }
    }

    /// Reset the machine back to idle. Always allowed.
    func reset() {
        state = .idle
    }

    // MARK: - Validity Table

    /// Whether a transition from `from` to `to` is valid.
    ///
    /// - idle -> exporting, cancelled
    /// - exporting -> exporting (progress ticks), success, error, cancelled
    /// - success / error / cancelled -> idle (reset only)
    static func isValid(from: ExportJobState, to: ExportJobState) -> Bool {
        switch (from, to) {
        case (.idle, .exporting),
             (.idle, .cancelled),
             (.exporting, .exporting),
             (.exporting, .success),
             (.exporting, .error),
             (.exporting, .cancelled),
             (.success, .idle),
             (.error, .idle),
             (.cancelled, .idle):
            return true

        // Same-state idempotent stays (rare but harmless).
        case (.idle, .idle),
             (.success, .success),
             (.error, .error),
             (.cancelled, .cancelled):
            return true

        default:
            return false
        }
    }
}
