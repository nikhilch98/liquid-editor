// ClipGroup.swift
// LiquidEditor
//
// M15-7: Lightweight grouping of timeline clips that move / trim / delete
// as a single unit. A thin bracket around members — each member still
// renders independently (unlike a true Compound Clip, see CompoundClip).
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.10.

import Foundation

// MARK: - ClipGroupColor

/// Six-color palette used to tint a group's bracket + label on the timeline.
/// Kept as a string-keyed enum so persisted values survive enum reordering.
enum ClipGroupColor: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case amber
    case red
    case green
    case blue
    case purple
    case white
}

// MARK: - ClipGroup

/// A named grouping of clip IDs. Supports nesting by storing an optional
/// `parentGroupID`; the caller (timeline model) enforces the 5-level soft
/// cap per spec §7.10.
struct ClipGroup: Codable, Equatable, Hashable, Sendable, Identifiable {

    // MARK: - Constants

    /// Soft limit on nesting depth per spec §7.10. Timeline caller enforces.
    static let maxNestingLevels = 5

    // MARK: - Properties

    /// Unique identifier for this group.
    let id: String

    /// User-visible label shown on the group bracket.
    let name: String

    /// IDs of direct members (clips and/or nested groups).
    let memberIDs: [String]

    /// Palette color for the bracket + label.
    let color: ClipGroupColor

    /// Parent group ID when this group is nested inside another; `nil` at root.
    let parentGroupID: String?

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        name: String,
        memberIDs: [String] = [],
        color: ClipGroupColor = .amber,
        parentGroupID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.color = color
        self.parentGroupID = parentGroupID
    }
}
