// ProjectUIState.swift
// LiquidEditor
//
// M15-5: Per-project UI state that persists so the user returns to
// exactly where they left off — tool rail ordering, timeline zoom tier,
// last-selected tool, scopes dock state, active tab, preview overlays,
// snap settings, and ripple / auto-follow preferences.
//
// Scope note: this is DISTINCT from `LibraryUIState` (which lives at the
// Library level and covers sidebar/sort/view mode). `ProjectUIState` is
// stored *inside* each project's metadata so two open projects can keep
// different zoom levels, different rail customization, etc.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md
//       §10.4 (tool rail), §10.11.4 (zoom tiers), §T7-20/T7-23/T7-35.

import Foundation

// MARK: - TimelineZoomTier

/// Timeline zoom level buckets per spec §10.11.4. LOD rendering keys off this.
enum TimelineZoomTier: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// Every frame visible.
    case frame
    /// Major ticks every 0.5s.
    case subSecond
    /// Major ticks every 1s.
    case second
    /// Major ticks every 5s (strip thumbs only).
    case multiSecond
    /// Major ticks every 10s+, project-fit view (gradient thumbs).
    case projectFit
}

// MARK: - ScopeDockState

/// iPad Color-tab scopes panel dock placement. iPhone ignores (scopes are
/// opt-in overlay only).
enum ScopeDockState: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case hidden
    /// Docked above the InspectorPanel (right rail).
    case docked
    /// Detached as a floating glass window, drag by title bar.
    case floating
}

// MARK: - EditorTabID

/// The five spec-compliant bottom-bar tabs per §3.1 / §6. Namespaced
/// as `EditorTabID` to avoid colliding with the legacy `EditorTab` enum
/// in ViewModels/EditorViewModel.swift (which has a different case set
/// pre-redesign: .edit/.fx/.overlay/.audio/.smart).
enum EditorTabID: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case edit
    case audio
    case text
    case fx
    case color
}

// MARK: - PreviewOverlays

/// Per-project preview-overlay toggle set (T7-23).
struct PreviewOverlays: Codable, Equatable, Hashable, Sendable {
    var grid: Bool
    var safeZone: Bool
    var centerCross: Bool

    static let off = PreviewOverlays(grid: false, safeZone: false, centerCross: false)

    init(grid: Bool = false, safeZone: Bool = false, centerCross: Bool = false) {
        self.grid = grid
        self.safeZone = safeZone
        self.centerCross = centerCross
    }
}

// MARK: - SnapSettings

/// Global snap-target toggles (T7-20). Active in all drag / trim gestures.
struct SnapSettings: Codable, Equatable, Hashable, Sendable {
    var playhead: Bool
    var beat: Bool
    var marker: Bool
    var grid: Bool

    static let `default` = SnapSettings(
        playhead: true, beat: true, marker: true, grid: false
    )

    init(playhead: Bool = true, beat: Bool = true, marker: Bool = true, grid: Bool = false) {
        self.playhead = playhead
        self.beat = beat
        self.marker = marker
        self.grid = grid
    }
}

// MARK: - ProjectUIState

/// Per-project UI state blob. Persisted inside the project file.
struct ProjectUIState: Codable, Equatable, Hashable, Sendable {

    // MARK: - Tool rail (§10.4)

    /// User-customized tool-rail ordering (stable tool IDs). Empty = project default.
    var toolRailItemIDs: [String]

    // MARK: - Timeline

    /// Current LOD bucket for the timeline.
    var zoomTier: TimelineZoomTier

    /// ID of the most-recently-selected tool within `activeTab`.
    var lastSelectedToolID: String?

    // MARK: - Active surfaces

    /// Active bottom-bar tab.
    var activeTab: EditorTabID

    /// iPad Color-tab scopes panel dock state.
    var scopeDockState: ScopeDockState

    // MARK: - Preview (§T7-23)

    var previewOverlays: PreviewOverlays

    // MARK: - Timeline behavior

    /// Snap-target toggles (T7-20).
    var snap: SnapSettings

    /// Project-level override of D0-5 ripple-delete default. `nil` = follow global default.
    var rippleEditOverride: Bool?

    /// Auto-scroll timeline to keep playhead in view during playback (T7-35).
    var autoFollowPlayhead: Bool

    /// Scrub-with-audio while dragging playhead (T7-9).
    var scrubWithAudio: Bool

    // MARK: - Initialization

    init(
        toolRailItemIDs: [String] = [],
        zoomTier: TimelineZoomTier = .second,
        lastSelectedToolID: String? = nil,
        activeTab: EditorTabID = .edit,
        scopeDockState: ScopeDockState = .hidden,
        previewOverlays: PreviewOverlays = .off,
        snap: SnapSettings = .default,
        rippleEditOverride: Bool? = nil,
        autoFollowPlayhead: Bool = true,
        scrubWithAudio: Bool = true
    ) {
        self.toolRailItemIDs = toolRailItemIDs
        self.zoomTier = zoomTier
        self.lastSelectedToolID = lastSelectedToolID
        self.activeTab = activeTab
        self.scopeDockState = scopeDockState
        self.previewOverlays = previewOverlays
        self.snap = snap
        self.rippleEditOverride = rippleEditOverride
        self.autoFollowPlayhead = autoFollowPlayhead
        self.scrubWithAudio = scrubWithAudio
    }

    /// Default state for a brand-new project.
    static let defaults = ProjectUIState()
}
