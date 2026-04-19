// PerformanceBudgets.swift
// LiquidEditor
//
// PP12-7: Centralised performance-budget constants + a tiny helper that logs
// budget violations via `os.signpost` so they show up as emitted events in
// Instruments' Performance trace.
//
// Budgets track the numbers in docs/PERFORMANCE.md and the "Timeline
// Architecture Targets" table in CLAUDE.md. Update BOTH places when values
// change — this file is the programmatic source of truth.
//
// Usage:
//   let start = ContinuousClock.now
//   performTimelineLookup()
//   let elapsed = ContinuousClock.now - start
//   PerformanceBudgets.assertBudget(
//       elapsed.seconds,
//       name: "timelineLookup",
//       budget: PerformanceBudgets.timelineLookupBudget
//   )
//
// Or, to scope a region with os_signpost:
//   let state = PerformanceBudgets.beginRegion(.timelineLookup)
//   defer { PerformanceBudgets.endRegion(.timelineLookup, state: state) }

import Foundation
import os

// MARK: - Budgets

/// Static bag of performance-budget constants. Not instantiable.
@MainActor
struct PerformanceBudgets: Sendable {

    // Raw numbers — match the "Timeline Architecture Targets" table.
    static let timelineLookupMaxUs: Int64 = 100
    static let editOpMaxMs: Double = 1
    static let undoRedoMaxUs: Int64 = 10
    static let scrubCachedMaxMs: Double = 2
    static let scrubUncachedMaxMs: Double = 50
    static let compositionRebuildMaxMs: Double = 20
    static let frameCacheMaxMB: Int = 300

    // Derived seconds-precision budgets, convenient for `TimeInterval` math.
    nonisolated static let timelineLookupBudget: TimeInterval = 100.0 / 1_000_000.0
    nonisolated static let editOpBudget: TimeInterval = 1.0 / 1_000.0
    nonisolated static let undoRedoBudget: TimeInterval = 10.0 / 1_000_000.0
    nonisolated static let scrubCachedBudget: TimeInterval = 2.0 / 1_000.0
    nonisolated static let scrubUncachedBudget: TimeInterval = 50.0 / 1_000.0
    nonisolated static let compositionRebuildBudget: TimeInterval = 20.0 / 1_000.0

    private init() {}

    // MARK: - Named regions

    /// Named performance regions that can be timed + asserted against a
    /// budget. Extend as new hot paths are instrumented.
    enum Region: String, Sendable {
        case timelineLookup
        case editOp
        case undoRedo
        case scrubCached
        case scrubUncached
        case compositionRebuild

        /// Budget in seconds for this region.
        var budget: TimeInterval {
            switch self {
            case .timelineLookup:     return PerformanceBudgets.timelineLookupBudget
            case .editOp:             return PerformanceBudgets.editOpBudget
            case .undoRedo:           return PerformanceBudgets.undoRedoBudget
            case .scrubCached:        return PerformanceBudgets.scrubCachedBudget
            case .scrubUncached:      return PerformanceBudgets.scrubUncachedBudget
            case .compositionRebuild: return PerformanceBudgets.compositionRebuildBudget
            }
        }

        /// The signposter used for intervals in this region. Regions that
        /// belong to existing subsystems reuse those signposters so category
        /// filters in Instruments continue to work.
        var signposter: OSSignposter {
            switch self {
            case .timelineLookup, .editOp, .undoRedo:
                return Signposts.composition
            case .scrubCached, .scrubUncached:
                return Signposts.scrub
            case .compositionRebuild:
                return Signposts.composition
            }
        }
    }

    // MARK: - Logger

    /// Logger for budget-violation messages. Separate from signpost events
    /// so developers can filter on it in Console.app.
    static let logger = Logger(subsystem: "com.liquideditor", category: "perf-budget")

    // MARK: - Assertion

    /// Compare a measured duration against a budget. If over budget, emit an
    /// `os_signpost` event and a warning log so violations are easy to spot
    /// in Instruments / Console.
    ///
    /// - Parameters:
    ///   - measured: Elapsed time in seconds.
    ///   - name: Human-readable label included in the log.
    ///   - budget: Allowed maximum in seconds.
    static func assertBudget(
        _ measured: TimeInterval,
        name: String,
        budget: TimeInterval
    ) {
        guard measured > budget else { return }
        let measuredMs = measured * 1_000
        let budgetMs = budget * 1_000
        logger.warning(
            "Budget violation: \(name, privacy: .public) took \(measuredMs, format: .fixed(precision: 3))ms (budget \(budgetMs, format: .fixed(precision: 3))ms)"
        )
        Signposts.composition.emitEvent(
            "budget-violation",
            "name=\(name) measured_ms=\(measuredMs) budget_ms=\(budgetMs)"
        )
    }

    // MARK: - Signpost Regions

    /// Opaque handle returned by `beginRegion(_:)` and consumed by
    /// `endRegion(_:state:)`. Wraps the signpost interval state plus the
    /// start instant used for budget assertion.
    struct RegionState {
        let region: Region
        let intervalState: OSSignpostIntervalState
        let start: ContinuousClock.Instant
    }

    /// Begin timing a named region. Emits a signpost `beginInterval` on the
    /// region's signposter.
    static func beginRegion(_ region: Region) -> RegionState {
        let signposter = region.signposter
        let state = signposter.beginInterval(
            "region",
            id: signposter.makeSignpostID(),
            "region=\(region.rawValue)"
        )
        return RegionState(
            region: region,
            intervalState: state,
            start: ContinuousClock.now
        )
    }

    /// End a timed region, emitting `endInterval` and asserting the budget.
    static func endRegion(_ region: Region, state: RegionState) {
        region.signposter.endInterval("region", state.intervalState, "region=\(region.rawValue)")
        let elapsed = ContinuousClock.now - state.start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        assertBudget(seconds, name: region.rawValue, budget: region.budget)
    }
}
