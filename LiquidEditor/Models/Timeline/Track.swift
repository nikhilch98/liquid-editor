import Foundation

// MARK: - TrackType

/// Type of track in the timeline.
enum TrackType: String, Codable, CaseIterable, Sendable {
    /// Primary video track (main storyline).
    case mainVideo
    /// Overlay video track (B-roll, picture-in-picture).
    case overlayVideo
    /// Audio track (sound effects, ambient).
    case audio
    /// Music track (background music).
    case music
    /// Voiceover track (narration, dialogue).
    case voiceover
    /// Effect/adjustment layer.
    case effect
    /// Text and titles track.
    case text
    /// Sticker overlay track.
    case sticker

    /// Default ARGB32 color for this track type.
    var defaultColorARGB32: Int {
        switch self {
        case .mainVideo: 0xFF5856D6     // Purple
        case .overlayVideo: 0xFFAF52DE  // Light purple
        case .audio: 0xFF34C759         // Green
        case .music: 0xFF30B0C7         // Teal
        case .voiceover: 0xFFFF9500     // Orange
        case .effect: 0xFF007AFF        // Blue
        case .text: 0xFFFF2D55          // Pink
        case .sticker: 0xFFFFD60A       // Yellow
        }
    }

    /// Display name for this track type.
    var displayName: String {
        switch self {
        case .mainVideo: "Main Video"
        case .overlayVideo: "Overlay"
        case .audio: "Audio"
        case .music: "Music"
        case .voiceover: "Voiceover"
        case .effect: "Effects"
        case .text: "Text"
        case .sticker: "Sticker"
        }
    }

    /// Whether this track type supports video content.
    var supportsVideo: Bool {
        self == .mainVideo || self == .overlayVideo
    }

    /// Whether this track type supports audio content.
    var supportsAudio: Bool {
        self == .audio || self == .music || self == .voiceover ||
        self == .mainVideo || self == .overlayVideo
    }

    /// Whether this track type supports effects.
    var supportsEffects: Bool { self == .effect }

    /// Whether this track type supports text.
    var supportsText: Bool { self == .text }

    /// Whether this track type supports stickers.
    var supportsSticker: Bool { self == .sticker }
}

// MARK: - TrackHeightPreset

/// Track height presets.
enum TrackHeightPreset: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
    case filmstrip
}

// MARK: - Track

/// Immutable track model.
struct Track: Codable, Equatable, Hashable, Sendable {
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

    /// Track color (ARGB32 int).
    let colorARGB32: Int

    /// Whether track is collapsed (minimized).
    let isCollapsed: Bool

    /// Whether track is visible.
    let isVisible: Bool

    // Height presets
    static let heightSmall: Double = 44.0
    static let heightMedium: Double = 64.0
    static let heightLarge: Double = 88.0
    static let heightFilmstrip: Double = 120.0

    init(
        id: String,
        name: String,
        type: TrackType,
        index: Int,
        height: Double = Track.heightMedium,
        isMuted: Bool = false,
        isSolo: Bool = false,
        isLocked: Bool = false,
        colorARGB32: Int? = nil,
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
        self.colorARGB32 = colorARGB32 ?? type.defaultColorARGB32
        self.isCollapsed = isCollapsed
        self.isVisible = isVisible
    }

    /// Create a new track with default settings.
    static func create(
        id: String,
        name: String,
        type: TrackType,
        index: Int
    ) -> Track {
        Track(id: id, name: name, type: type, index: index, colorARGB32: type.defaultColorARGB32)
    }

    // MARK: - Computed Properties

    /// Track color as ARGBColor.
    var color: ARGBColor { ARGBColor.fromARGB32(colorARGB32) }

    /// Height when collapsed.
    var collapsedHeight: Double { Track.heightSmall }

    /// Effective height (considering collapsed state).
    var effectiveHeight: Double { isCollapsed ? collapsedHeight : height }

    /// Whether this is a video track.
    var isVideoTrack: Bool { type.supportsVideo }

    /// Whether this is an audio-only track.
    var isAudioOnlyTrack: Bool {
        type == .audio || type == .music || type == .voiceover
    }

    // MARK: - Copy With

    /// Create a copy with updated values.
    func with(
        id: String? = nil,
        name: String? = nil,
        type: TrackType? = nil,
        index: Int? = nil,
        height: Double? = nil,
        isMuted: Bool? = nil,
        isSolo: Bool? = nil,
        isLocked: Bool? = nil,
        colorARGB32: Int? = nil,
        isCollapsed: Bool? = nil,
        isVisible: Bool? = nil
    ) -> Track {
        Track(
            id: id ?? self.id,
            name: name ?? self.name,
            type: type ?? self.type,
            index: index ?? self.index,
            height: height ?? self.height,
            isMuted: isMuted ?? self.isMuted,
            isSolo: isSolo ?? self.isSolo,
            isLocked: isLocked ?? self.isLocked,
            colorARGB32: colorARGB32 ?? self.colorARGB32,
            isCollapsed: isCollapsed ?? self.isCollapsed,
            isVisible: isVisible ?? self.isVisible
        )
    }

    /// Toggle mute state.
    func toggleMute() -> Track { with(isMuted: !isMuted) }

    /// Toggle solo state.
    func toggleSolo() -> Track { with(isSolo: !isSolo) }

    /// Toggle lock state.
    func toggleLock() -> Track { with(isLocked: !isLocked) }

    /// Toggle collapsed state.
    func toggleCollapsed() -> Track { with(isCollapsed: !isCollapsed) }

    /// Set height to preset.
    func withHeightPreset(_ preset: TrackHeightPreset) -> Track {
        switch preset {
        case .small: with(height: Track.heightSmall)
        case .medium: with(height: Track.heightMedium)
        case .large: with(height: Track.heightLarge)
        case .filmstrip: with(height: Track.heightFilmstrip)
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, type, index, height
        case isMuted, isSolo, isLocked
        case color, isCollapsed, isVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let typeStr = try container.decode(String.self, forKey: .type)
        type = TrackType(rawValue: typeStr) ?? .effect
        index = try container.decode(Int.self, forKey: .index)
        height = try container.decode(Double.self, forKey: .height)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSolo = try container.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        colorARGB32 = try container.decode(Int.self, forKey: .color)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(index, forKey: .index)
        try container.encode(height, forKey: .height)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(isSolo, forKey: .isSolo)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(colorARGB32, forKey: .color)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encode(isVisible, forKey: .isVisible)
    }
}
