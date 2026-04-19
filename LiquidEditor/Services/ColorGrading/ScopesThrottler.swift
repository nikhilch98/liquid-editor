// ScopesThrottler.swift
// LiquidEditor
//
// PP12-6: Scopes refresh-rate throttler driven by thermal state.
//
// Under sustained load, `ProcessInfo.thermalState` escalates from `.nominal`
// through `.fair`, `.serious`, and `.critical`. Scope rendering (histogram,
// vectorscope, RGB-parade) is CPU/GPU-heavy and can compound thermal rise,
// so we step the refresh rate down when the device is warm.
//
// Mapping (see docs/PERFORMANCE.md — "Scopes thermal governor"):
//   .nominal  -> 30 Hz
//   .fair     -> 30 Hz
//   .serious  -> 15 Hz
//   .critical ->  5 Hz
//
// Usage:
//   let throttler = ScopesThrottler()
//   // Read `throttler.intervalSeconds` to drive a timer or debounce.
//   // SwiftUI views observe via @Observable and re-render on change.

import Foundation
import Observation

/// Publishes the current scope refresh rate based on `ProcessInfo.thermalState`.
///
/// `@MainActor` because scope UI consumes this directly. `@Observable` so
/// SwiftUI views automatically re-render when `currentTargetHz` changes.
@MainActor
@Observable
final class ScopesThrottler {

    // MARK: - Target Rates

    /// Nominal / Fair — full fidelity.
    static let nominalHz: Double = 30.0

    /// Serious — halved to relieve the GPU / encoder and lower junction temp.
    static let seriousHz: Double = 15.0

    /// Critical — minimal refresh; user should still see motion.
    static let criticalHz: Double = 5.0

    // MARK: - State

    /// Current thermal state, cached to avoid repeated `ProcessInfo` calls.
    private(set) var thermalState: ProcessInfo.ThermalState

    /// Current target refresh rate in Hz. Driven by `thermalState`.
    private(set) var currentTargetHz: Double

    /// Convenience: the interval (seconds) between refreshes = `1 / Hz`.
    var intervalSeconds: Double {
        guard currentTargetHz > 0 else { return .infinity }
        return 1.0 / currentTargetHz
    }

    // MARK: - Observation

    /// Retained observer token for `NSProcessInfoThermalStateDidChange`.
    private var observer: NSObjectProtocol?

    // MARK: - Lifecycle

    init() {
        let state = ProcessInfo.processInfo.thermalState
        self.thermalState = state
        self.currentTargetHz = Self.targetHz(for: state)

        // Observe thermal-state changes. The notification is delivered on an
        // arbitrary queue, so we hop to the main actor to mutate state.
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            let newState = ProcessInfo.processInfo.thermalState
            Task { @MainActor [weak self] in
                self?.updateThermalState(newState)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Updates

    /// Recompute refresh rate for a given thermal state. Idempotent.
    func updateThermalState(_ state: ProcessInfo.ThermalState) {
        thermalState = state
        currentTargetHz = Self.targetHz(for: state)
    }

    /// Pure mapping from thermal state -> Hz. Isolated for testability.
    static func targetHz(for state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal, .fair:
            return nominalHz
        case .serious:
            return seriousHz
        case .critical:
            return criticalHz
        @unknown default:
            // Conservative: treat unknown escalations as `.serious`.
            return seriousHz
        }
    }
}
