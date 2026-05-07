// CompoundNestingGuard.swift
// LiquidEditor
//
// T7-40: Performance guardrails for compound-clip nesting. Verifies that
// the graph of nested `CompoundClip`s never exceeds the hard depth cap or
// children-per-compound cap, and surfaces soft warnings once the user
// crosses into "deep nesting" territory.
//
// Why guardrails?
// - Each compound re-composites through MultiTrackCompositor, so every
//   level of nesting multiplies render cost. Beyond roughly eight levels
//   we observe notable playback jank even on A17 hardware.
// - Very wide compounds (hundreds of direct children) saturate the render
//   cache invalidation path and regress undo/redo snapshots.
//
// Usage:
//
//     do {
//         let report = try CompoundNestingGuard.validate(
//             compound,
//             resolver: { id in timeline.getById(id) as? CompoundClip }
//         )
//         for warning in report.warnings {
//             Log.timeline.warning("\(warning)")
//         }
//     } catch {
//         // Refuse the conversion — the user is asked to flatten first.
//     }
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.13
//       (compound clip nesting, soft/hard caps).

import Foundation

// MARK: - CompoundNestingError

/// Errors raised by ``CompoundNestingGuard/validate(_:resolver:)``.
enum CompoundNestingError: Error, Equatable, Sendable {
    /// The compound tree's depth at or past ``CompoundNestingGuard.maxNestingDepth``.
    /// Associated value is the offending measured depth.
    case maxDepthExceeded(Int)

    /// A compound has more direct children than
    /// ``CompoundNestingGuard.maxChildrenPerCompound``.
    /// Associated value is the offending count.
    case tooManyChildren(Int)
}

// MARK: - CompoundNestingReport

/// A non-fatal report of the compound's nesting characteristics. Emitted on
/// successful validation (i.e. no hard-cap violations).
struct CompoundNestingReport: Sendable, Equatable {
    /// Maximum nesting depth discovered (1 for a flat compound with no
    /// compound descendants).
    let depth: Int

    /// Total number of descendant clips across every nested level.
    let totalChildren: Int

    /// Human-readable diagnostic strings — typically soft-cap warnings.
    let warnings: [String]
}

// MARK: - CompoundNestingGuard

/// Namespaced validator. Pure value-analysis — no I/O, no UI state.
@MainActor
enum CompoundNestingGuard {

    // MARK: - Limits

    /// Hard cap on nesting depth. Validation throws at/beyond this value.
    static let maxNestingDepth: Int = 8

    /// Soft-warning threshold. Depth at or above this emits a warning but
    /// does not throw.
    static let warnNestingDepth: Int = 5

    /// Hard cap on direct children per compound. Validation throws at/beyond.
    static let maxChildrenPerCompound: Int = 200

    // MARK: - Validate

    /// Walk the compound tree rooted at `clip` and return a non-fatal
    /// report, or throw on hard-cap violations.
    ///
    /// - Parameters:
    ///   - clip: Root compound to inspect.
    ///   - resolver: Optional closure to resolve a child's ``CompoundClip``
    ///               by its ID. When `nil`, only the root is inspected.
    ///               Callers typically pass a timeline lookup, e.g.
    ///               `{ id in timeline.getById(id) as? CompoundClip }`.
    /// - Returns: A ``CompoundNestingReport`` on success.
    /// - Throws: ``CompoundNestingError`` when a hard cap is breached.
    @discardableResult
    static func validate(
        _ clip: CompoundClip,
        resolver: ((String) -> CompoundClip?)? = nil
    ) throws -> CompoundNestingReport {
        var warnings: [String] = []
        var totalChildren = 0
        var visited = Set<String>()

        let depth = try walk(
            clip,
            currentDepth: 1,
            resolver: resolver,
            visited: &visited,
            totalChildren: &totalChildren,
            warnings: &warnings
        )

        if depth >= warnNestingDepth && depth < maxNestingDepth {
            warnings.append(
                "Compound nesting depth \(depth) exceeds soft warning threshold \(warnNestingDepth); consider flattening."
            )
        }

        return CompoundNestingReport(
            depth: depth,
            totalChildren: totalChildren,
            warnings: warnings
        )
    }

    // MARK: - Private recursion

    /// Recursive worker. Returns the maximum depth observed from `clip`
    /// down the tree. Protects against reference cycles with `visited`.
    private static func walk(
        _ clip: CompoundClip,
        currentDepth: Int,
        resolver: ((String) -> CompoundClip?)?,
        visited: inout Set<String>,
        totalChildren: inout Int,
        warnings: inout [String]
    ) throws -> Int {
        if currentDepth >= maxNestingDepth {
            throw CompoundNestingError.maxDepthExceeded(currentDepth)
        }

        let directCount = clip.memberIDs.count
        if directCount >= maxChildrenPerCompound {
            throw CompoundNestingError.tooManyChildren(directCount)
        }
        totalChildren += directCount

        // Avoid revisits (defense-in-depth — the serialization format does
        // not permit cycles, but a corrupted project should not crash the
        // validator).
        guard visited.insert(clip.id).inserted else {
            warnings.append(
                "Detected compound cycle at \(clip.id); ignoring revisit."
            )
            return currentDepth
        }

        guard let resolver else {
            return currentDepth
        }

        var maxChildDepth = currentDepth
        for memberID in clip.memberIDs {
            guard let nested = resolver(memberID) else { continue }
            let childDepth = try walk(
                nested,
                currentDepth: currentDepth + 1,
                resolver: resolver,
                visited: &visited,
                totalChildren: &totalChildren,
                warnings: &warnings
            )
            if childDepth > maxChildDepth {
                maxChildDepth = childDepth
            }
        }
        return maxChildDepth
    }
}
