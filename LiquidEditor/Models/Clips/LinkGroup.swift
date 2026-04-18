// LinkGroup.swift
// LiquidEditor
//
// M15-11: Sync-preserving link between clips — typically a video clip and
// its embedded-audio sibling imported from the same source asset.
//
// Orthogonal to ClipGroup: a clip can be in both a ClipGroup (for
// move-as-unit) and a LinkGroup (for sync preservation).
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.16.

import Foundation

// MARK: - LinkKind

/// Distinguishes implicitly-linked (matching-duration import) from
/// explicitly user-created link groups. Stored as a string so the kind
/// survives round-trips through older/newer schema versions.
enum LinkKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// Auto-linked on import when video and audio share duration + source.
    case sync
    /// User-created manually via context menu or keyboard shortcut.
    case manual
}

// MARK: - LinkGroup

/// A small set of clip IDs whose timeline operations (move, trim, delete)
/// propagate across all members. Ripple-aware callers should treat the
/// group's members atomically unless the user holds the `⌥` override.
struct LinkGroup: Codable, Equatable, Hashable, Sendable, Identifiable {

    /// Unique identifier for this link group.
    let id: String

    /// IDs of the linked clips.
    let memberIDs: [String]

    /// Whether the link was auto-created on import or manually established.
    let kind: LinkKind

    init(
        id: String = UUID().uuidString,
        memberIDs: [String],
        kind: LinkKind
    ) {
        self.id = id
        self.memberIDs = memberIDs
        self.kind = kind
    }
}
