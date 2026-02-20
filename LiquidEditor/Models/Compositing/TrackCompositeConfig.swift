// TrackCompositeConfig.swift
// LiquidEditor
//
// Per-track compositing configuration.
// Defines how a track's content is positioned and blended
// in the multi-track composition output.

import Foundation

/// How a track's content is positioned and blended in the composition.
///
/// Each track has a `TrackCompositeConfig` that determines its spatial
/// layout (full-frame, PiP, split-screen, freeform), blend mode,
/// opacity, and optional chroma key.
struct TrackCompositeConfig: Codable, Equatable, Hashable, Sendable {
    /// Spatial layout mode.
    let layout: CompositeLayout

    /// Opacity (0.0 = invisible, 1.0 = fully opaque).
    let opacity: Double

    /// Blend mode for compositing.
    let blendMode: CompBlendMode

    /// Chroma key configuration (nil = no chroma key).
    let chromaKey: ChromaKeyConfig?

    /// PiP region (used when layout == .pip).
    /// Normalized coordinates (0.0-1.0) relative to output frame.
    let pipRegion: NormalizedRect?

    /// Split screen cell index (used when layout == .splitScreen).
    let splitScreenCell: Int?

    /// Split screen layout template.
    let splitScreenTemplate: SplitScreenTemplate?

    /// Audio volume for this track (0.0-1.0).
    let volume: Double

    init(
        layout: CompositeLayout = .fullFrame,
        opacity: Double = 1.0,
        blendMode: CompBlendMode = .normal,
        chromaKey: ChromaKeyConfig? = nil,
        pipRegion: NormalizedRect? = nil,
        splitScreenCell: Int? = nil,
        splitScreenTemplate: SplitScreenTemplate? = nil,
        volume: Double = 1.0
    ) {
        self.layout = layout
        self.opacity = opacity
        self.blendMode = blendMode
        self.chromaKey = chromaKey
        self.pipRegion = pipRegion
        self.splitScreenCell = splitScreenCell
        self.splitScreenTemplate = splitScreenTemplate
        self.volume = volume
    }

    /// Default configuration for the main video track.
    static let mainTrack = TrackCompositeConfig()

    /// Default configuration for a PiP overlay track.
    static let defaultOverlay = TrackCompositeConfig(
        layout: .pip,
        pipRegion: .defaultPip
    )

    /// Default configuration for a chroma key overlay track.
    static let defaultChromaKey = TrackCompositeConfig(
        layout: .fullFrame,
        chromaKey: .defaultGreen
    )

    /// Whether this track has chroma key enabled.
    var hasChromaKey: Bool { chromaKey != nil && (chromaKey?.isEnabled ?? false) }

    /// Whether this track is a PiP overlay.
    var isPip: Bool { layout == .pip }

    /// Whether this track is a split screen cell.
    var isSplitScreen: Bool { layout == .splitScreen }

    /// Create a copy with updated fields.
    ///
    /// Use the `clear*` parameters to explicitly set optional fields to nil.
    func with(
        layout: CompositeLayout? = nil,
        opacity: Double? = nil,
        blendMode: CompBlendMode? = nil,
        chromaKey: ChromaKeyConfig? = nil,
        clearChromaKey: Bool = false,
        pipRegion: NormalizedRect? = nil,
        clearPipRegion: Bool = false,
        splitScreenCell: Int? = nil,
        clearSplitScreenCell: Bool = false,
        splitScreenTemplate: SplitScreenTemplate? = nil,
        clearSplitScreenTemplate: Bool = false,
        volume: Double? = nil
    ) -> TrackCompositeConfig {
        TrackCompositeConfig(
            layout: layout ?? self.layout,
            opacity: opacity ?? self.opacity,
            blendMode: blendMode ?? self.blendMode,
            chromaKey: clearChromaKey ? nil : (chromaKey ?? self.chromaKey),
            pipRegion: clearPipRegion ? nil : (pipRegion ?? self.pipRegion),
            splitScreenCell: clearSplitScreenCell ? nil : (splitScreenCell ?? self.splitScreenCell),
            splitScreenTemplate: clearSplitScreenTemplate
                ? nil : (splitScreenTemplate ?? self.splitScreenTemplate),
            volume: volume ?? self.volume
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case layout
        case opacity
        case blendMode
        case chromaKey
        case pipRegion
        case splitScreenCell
        case splitScreenTemplate
        case volume
    }
}

// MARK: - CustomStringConvertible

extension TrackCompositeConfig: CustomStringConvertible {
    var description: String {
        "TrackCompositeConfig(\(layout.rawValue), opacity: \(opacity), blend: \(blendMode.rawValue))"
    }
}
