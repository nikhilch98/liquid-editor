// CompoundClip.swift
// LiquidEditor
//
// M15-10: True compound clip — an EXTENDED grouping (see ClipGroup) that
// flattens an internal timeline through MultiTrackCompositor into a
// single renderable source used in the parent timeline.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.13.
//
// Relationship to ClipGroup:
// - ClipGroup is a THIN bracket whose members render independently in
//   the parent timeline (see Models/Clips/ClipGroup.swift).
// - CompoundClip is the FLATTENED variant: the inner timeline is pre-
//   composited into a single clip, which then plays as one source.
// - Convert: Group -> CompoundClip (captures per-member state)
// - Revert:  CompoundClip -> Group (restores original members)
//
// Rendering:
// - The compound's internal timeline composites through the existing
//   MultiTrackCompositor to a video+audio source.
// - The composited output is render-cached by (compoundID, contentHash).
// - Invalidated when ANY descendant edit commits.
//
// Nesting: soft cap at 10, hard cap at 20 (PersistentTimeline enforces).

import Foundation

// MARK: - CompoundClip

/// A timeline clip whose source is produced by compositing an internal
/// `PersistentTimeline`. Persisted by-reference: the inner timeline's
/// tree is serialized with the project (not exported to a separate
/// asset), so undo / redo operate normally across the boundary.
struct CompoundClip: Codable, Equatable, Hashable, Sendable, Identifiable {

    // MARK: - Constants

    /// Soft-warn nesting level per spec §7.13.
    static let softCapLevels = 10

    /// Hard cap — further conversion is rejected at/above this.
    static let hardCapLevels = 20

    // MARK: - Properties

    /// Unique identifier (used as the render-cache primary key).
    let id: String

    /// Human-readable label shown on the compound's tile + breadcrumb.
    let name: String

    /// IDs of the direct members wrapped by this compound. Lives alongside
    /// the members' own records inside `PersistentTimeline`, same as
    /// `ClipGroup.memberIDs`.
    let memberIDs: [String]

    /// Optional back-reference to the `ClipGroup.id` this compound was
    /// converted from. Present when the user can revert to the original
    /// Group; absent when the compound was constructed ab initio.
    let originatingGroupID: String?

    /// Parent compound ID when nested; `nil` at the outer level.
    let parentCompoundID: String?

    /// Content hash of the internal composition used for render-cache
    /// invalidation. Updated on every descendant-edit commit by the
    /// timeline mutation pipeline.
    let contentHash: String

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        name: String,
        memberIDs: [String],
        originatingGroupID: String? = nil,
        parentCompoundID: String? = nil,
        contentHash: String = ""
    ) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.originatingGroupID = originatingGroupID
        self.parentCompoundID = parentCompoundID
        self.contentHash = contentHash
    }
}
