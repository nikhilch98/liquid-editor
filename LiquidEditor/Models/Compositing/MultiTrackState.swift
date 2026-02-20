// MultiTrackState.swift
// LiquidEditor
//
// Immutable multi-track state for the compositing system.
// Holds all track metadata, per-track composite configs, and track ordering.
// The entire state is swapped atomically for O(1) undo/redo.

import Foundation

/// Immutable multi-track state.
///
/// Each track has its own timeline (AVL tree on the Dart side).
/// The entire state is swapped atomically for O(1) undo/redo.
/// Structural sharing ensures that editing one track does not
/// copy other tracks' trees.
struct MultiTrackState: Codable, Equatable, Hashable, Sendable {
    /// Track metadata indexed by ID.
    let tracks: [String: TrackMetadata]

    /// Track rendering order (index 0 = bottom-most = main video).
    let trackOrder: [String]

    /// Per-track composite configurations.
    let compositeConfigs: [String: TrackCompositeConfig]

    init(
        tracks: [String: TrackMetadata] = [:],
        trackOrder: [String] = [],
        compositeConfigs: [String: TrackCompositeConfig] = [:]
    ) {
        self.tracks = tracks
        self.trackOrder = trackOrder
        self.compositeConfigs = compositeConfigs
    }

    /// Empty multi-track state.
    static let empty = MultiTrackState()

    /// Number of tracks.
    var trackCount: Int { tracks.count }

    /// Whether there are any tracks.
    var isEmpty: Bool { tracks.isEmpty }

    /// Whether there are tracks.
    var isNotEmpty: Bool { !tracks.isEmpty }

    /// Get visible tracks in render order (bottom to top).
    var visibleTracksInOrder: [TrackMetadata] {
        trackOrder.compactMap { id in
            guard let track = tracks[id], track.isVisible else { return nil }
            return track
        }
    }

    /// Get all tracks in order.
    var tracksInOrder: [TrackMetadata] {
        trackOrder.compactMap { tracks[$0] }
    }

    /// Get the composite config for a track (returns default if not found).
    func configForTrack(_ trackId: String) -> TrackCompositeConfig {
        compositeConfigs[trackId] ?? TrackCompositeConfig()
    }

    /// Count of overlay video tracks.
    var overlayTrackCount: Int {
        tracks.values.filter { $0.type == .overlayVideo }.count
    }

    /// Create a copy with updated fields.
    func with(
        tracks: [String: TrackMetadata]? = nil,
        trackOrder: [String]? = nil,
        compositeConfigs: [String: TrackCompositeConfig]? = nil
    ) -> MultiTrackState {
        MultiTrackState(
            tracks: tracks ?? self.tracks,
            trackOrder: trackOrder ?? self.trackOrder,
            compositeConfigs: compositeConfigs ?? self.compositeConfigs
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case tracks
        case trackOrder
        case compositeConfigs
    }
}

// MARK: - TrackMetadata

/// Lightweight track metadata for the multi-track state.
///
/// This is the Swift equivalent of the Dart `Track` model, containing
/// the essential properties needed for compositing and rendering decisions.
struct TrackMetadata: Codable, Equatable, Hashable, Sendable {
    /// Unique track identifier.
    let id: String

    /// Track display name.
    let name: String

    /// Type of track.
    let type: TrackType

    /// Vertical position index (0 = top).
    let index: Int

    /// Track height in pixels.
    let height: Double

    /// Whether track audio is muted.
    let isMuted: Bool

    /// Whether track is soloed (only this track plays).
    let isSolo: Bool

    /// Whether track is locked (prevent editing).
    let isLocked: Bool

    /// Track color as ARGB integer.
    let color: Int

    /// Whether track is collapsed (minimized).
    let isCollapsed: Bool

    /// Whether track is visible.
    let isVisible: Bool

    init(
        id: String,
        name: String,
        type: TrackType,
        index: Int,
        height: Double = TrackMetadata.heightMedium,
        isMuted: Bool = false,
        isSolo: Bool = false,
        isLocked: Bool = false,
        color: Int = 0xFF58_56D6,
        isCollapsed: Bool = false,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.index = index
        self.height = height
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isLocked = isLocked
        self.color = color
        self.isCollapsed = isCollapsed
        self.isVisible = isVisible
    }

    // MARK: - Height Presets

    /// Small track height (collapsed or minimal).
    static let heightSmall: Double = 44.0

    /// Medium track height (default).
    static let heightMedium: Double = 64.0

    /// Large track height (more detail).
    static let heightLarge: Double = 88.0

    /// Filmstrip height (shows thumbnails).
    static let heightFilmstrip: Double = 120.0

    // MARK: - Computed Properties

    /// Whether this is a video track.
    var isVideoTrack: Bool { type.supportsVideo }

    /// Whether this is an audio-only track.
    var isAudioOnlyTrack: Bool {
        type == .audio || type == .music || type == .voiceover
    }

    /// Effective height (considering collapsed state).
    var effectiveHeight: Double { isCollapsed ? TrackMetadata.heightSmall : height }

    /// Create a copy with updated fields.
    func with(
        id: String? = nil,
        name: String? = nil,
        type: TrackType? = nil,
        index: Int? = nil,
        height: Double? = nil,
        isMuted: Bool? = nil,
        isSolo: Bool? = nil,
        isLocked: Bool? = nil,
        color: Int? = nil,
        isCollapsed: Bool? = nil,
        isVisible: Bool? = nil
    ) -> TrackMetadata {
        TrackMetadata(
            id: id ?? self.id,
            name: name ?? self.name,
            type: type ?? self.type,
            index: index ?? self.index,
            height: height ?? self.height,
            isMuted: isMuted ?? self.isMuted,
            isSolo: isSolo ?? self.isSolo,
            isLocked: isLocked ?? self.isLocked,
            color: color ?? self.color,
            isCollapsed: isCollapsed ?? self.isCollapsed,
            isVisible: isVisible ?? self.isVisible
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case index
        case height
        case isMuted
        case isSolo
        case isLocked
        case color
        case isCollapsed
        case isVisible
    }
}

// MARK: - CustomStringConvertible

extension MultiTrackState: CustomStringConvertible {
    var description: String {
        "MultiTrackState(\(tracks.count) tracks)"
    }
}
