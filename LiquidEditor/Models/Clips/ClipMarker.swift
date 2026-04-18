// ClipMarker.swift
// LiquidEditor
//
// M15-12: Per-clip marker that travels with the clip on trim / move /
// group operations. Distinct from timeline-level markers (beat markers,
// chapter markers) which live on the timeline itself.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.17.

import Foundation

// MARK: - ClipMarkerColor

/// Six-color palette for clip markers (scene / review / take flags).
enum ClipMarkerColor: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case amber
    case red
    case green
    case blue
    case purple
    case white
}

// MARK: - ClipMarker

/// A single marker anchored to a specific position inside its parent clip.
///
/// The `positionInClip` is measured from the clip's source-in boundary,
/// so markers survive trimming: a left-trim does not shift markers in
/// source-time, it only hides those that fall outside the visible range.
struct ClipMarker: Codable, Equatable, Hashable, Sendable, Identifiable {

    /// Unique identifier for this marker.
    let id: String

    /// Offset (microseconds) from the clip's source-in boundary.
    let positionInClip: TimeMicros

    /// User-visible short label shown in the pop-over.
    let label: String

    /// Pip color on the clip tile.
    let color: ClipMarkerColor

    init(
        id: String = UUID().uuidString,
        positionInClip: TimeMicros,
        label: String,
        color: ClipMarkerColor = .amber
    ) {
        self.id = id
        self.positionInClip = positionInClip
        self.label = label
        self.color = color
    }
}
