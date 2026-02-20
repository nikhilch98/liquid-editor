// Project.swift
// LiquidEditor
//
// Project model and related types for video editing projects.
//
// Contains the core Project struct representing a video editing project
// with multi-clip NLE support, along with supporting types for frame rates,
// resolutions, and timeline management.
//

import Foundation
import CoreGraphics

// MARK: - Project

/// Represents a video editing project with multi-clip NLE support.
///
/// This struct is immutable. Use `with(...)` to create modified copies.
/// Use `touched()` to update the modification timestamp.
///
/// ## Migration
///
/// When loading projects from older versions (version < 2), use `migrateToMultiClip()`
/// to convert from single-clip to multi-clip format.
///
/// ## File Resolution
///
/// Video file paths are stored as relative paths. Resolve them to actual files
/// using the appropriate file service.
struct Project: Codable, Equatable, Hashable, Sendable, Identifiable {

    // MARK: - Default Values

    /// Default values for missing fields during decoding (backward compatibility).
    private enum Defaults {
        static let frameRate: FrameRateOption = .auto
        static let durationMicros: Int64 = 0
        static let clips: [[String: AnyCodableValue]] = []
        static let inPointMicros: Int64 = 0
        static let version: Int = 1
        static let cropAspectRatio: Double = 0.0
        static let cropAspectRatioLabel: String = ""
        static let cropRotation90: Int = 0
        static let cropFlipHorizontal: Bool = false
        static let cropFlipVertical: Bool = false
        static let noiseReductionIntensity: Double = 0.5
        static let noiseReductionEnabled: Bool = false
        static let playbackSpeed: Double = 1.0
        static let textOverlays: [TextClip] = []
        static let stickerOverlays: [StickerClip] = []
        static let overlayStartTimesMicros: [String: Int64] = [:]
    }

    // MARK: - Properties

    /// Unique project identifier.
    let id: String

    /// Project display name.
    let name: String

    /// Source video file path (relative to documents directory).
    let sourceVideoPath: String

    /// Project frame rate setting.
    let frameRate: FrameRateOption

    /// Original video duration in microseconds (immutable, from source).
    let durationMicros: Int64

    /// Timeline clips as serialized JSON array.
    /// Each element is a dictionary representing a timeline item.
    let clips: [[String: AnyCodableValue]]

    /// Trim in-point in microseconds (DEPRECATED - use clips instead).
    let inPointMicros: Int64

    /// Trim out-point in microseconds (DEPRECATED - use clips instead).
    let outPointMicros: Int64?

    /// Creation date.
    let createdAt: Date

    /// Last modified date.
    let modifiedAt: Date

    /// Thumbnail image path (relative).
    let thumbnailPath: String?

    /// Version number for migration (1 = old single-clip, 2 = multi-clip NLE).
    let version: Int

    // MARK: - Editing State Persistence

    /// Crop aspect ratio (width / height), or 0.0 for no crop / original.
    let cropAspectRatio: Double

    /// Crop aspect ratio display label (e.g. "16:9", "Original").
    let cropAspectRatioLabel: String

    /// Rotation in 90-degree increments (0, 1, 2, 3).
    let cropRotation90: Int

    /// Whether the video is flipped horizontally.
    let cropFlipHorizontal: Bool

    /// Whether the video is flipped vertically.
    let cropFlipVertical: Bool

    /// Compressor audio effect parameters (serialized).
    let compressorParams: [String: AnyCodableValue]?

    /// Noise gate audio effect parameters (serialized).
    let noiseGateParams: [String: AnyCodableValue]?

    /// Noise reduction intensity (0.0 - 1.0).
    let noiseReductionIntensity: Double

    /// Whether noise reduction is enabled.
    let noiseReductionEnabled: Bool

    /// Playback speed multiplier.
    let playbackSpeed: Double

    /// Text overlay clips (serialized).
    let textOverlays: [TextClip]

    /// Sticker overlay clips (serialized).
    let stickerOverlays: [StickerClip]

    /// Overlay start times (clip ID -> start time in microseconds).
    let overlayStartTimesMicros: [String: Int64]

    /// Full multi-track state JSON (text/sticker tracks + clips).
    /// When present, this is the authoritative source for overlay data.
    let multiTrackStateJson: [String: AnyCodableValue]?

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        sourceVideoPath: String,
        frameRate: FrameRateOption = .auto,
        durationMicros: Int64 = 0,
        clips: [[String: AnyCodableValue]] = [],
        inPointMicros: Int64 = 0,
        outPointMicros: Int64? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        thumbnailPath: String? = nil,
        version: Int = 2,
        cropAspectRatio: Double = 0.0,
        cropAspectRatioLabel: String = "",
        cropRotation90: Int = 0,
        cropFlipHorizontal: Bool = false,
        cropFlipVertical: Bool = false,
        compressorParams: [String: AnyCodableValue]? = nil,
        noiseGateParams: [String: AnyCodableValue]? = nil,
        noiseReductionIntensity: Double = 0.5,
        noiseReductionEnabled: Bool = false,
        playbackSpeed: Double = 1.0,
        textOverlays: [TextClip] = [],
        stickerOverlays: [StickerClip] = [],
        overlayStartTimesMicros: [String: Int64] = [:],
        multiTrackStateJson: [String: AnyCodableValue]? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceVideoPath = sourceVideoPath
        self.frameRate = frameRate
        self.durationMicros = durationMicros
        self.clips = clips
        self.inPointMicros = inPointMicros
        self.outPointMicros = outPointMicros
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.thumbnailPath = thumbnailPath
        self.version = version
        self.cropAspectRatio = cropAspectRatio
        self.cropAspectRatioLabel = cropAspectRatioLabel
        self.cropRotation90 = cropRotation90
        self.cropFlipHorizontal = cropFlipHorizontal
        self.cropFlipVertical = cropFlipVertical
        self.compressorParams = compressorParams
        self.noiseGateParams = noiseGateParams
        self.noiseReductionIntensity = noiseReductionIntensity
        self.noiseReductionEnabled = noiseReductionEnabled
        self.playbackSpeed = playbackSpeed
        self.textOverlays = textOverlays
        self.stickerOverlays = stickerOverlays
        self.overlayStartTimesMicros = overlayStartTimesMicros
        self.multiTrackStateJson = multiTrackStateJson
    }

    // MARK: - Computed Properties

    /// Duration in seconds (from source).
    var durationSeconds: Double {
        Double(durationMicros) / 1_000_000.0
    }

    /// Clip count.
    var clipCount: Int { clips.count }

    /// Formatted duration string.
    var formattedDuration: String {
        let totalSeconds = Int(durationMicros / 1_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        } else {
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
    }

    // MARK: - Copy-With-Modify

    /// Create a copy with optional field overrides.
    ///
    /// To explicitly clear nullable fields to nil, pass the corresponding
    /// `clearFieldName: true` parameter.
    func with(
        id: String? = nil,
        name: String? = nil,
        sourceVideoPath: String? = nil,
        frameRate: FrameRateOption? = nil,
        durationMicros: Int64? = nil,
        clips: [[String: AnyCodableValue]]? = nil,
        inPointMicros: Int64? = nil,
        outPointMicros: Int64? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        thumbnailPath: String? = nil,
        version: Int? = nil,
        cropAspectRatio: Double? = nil,
        cropAspectRatioLabel: String? = nil,
        cropRotation90: Int? = nil,
        cropFlipHorizontal: Bool? = nil,
        cropFlipVertical: Bool? = nil,
        compressorParams: [String: AnyCodableValue]? = nil,
        noiseGateParams: [String: AnyCodableValue]? = nil,
        noiseReductionIntensity: Double? = nil,
        noiseReductionEnabled: Bool? = nil,
        playbackSpeed: Double? = nil,
        textOverlays: [TextClip]? = nil,
        stickerOverlays: [StickerClip]? = nil,
        overlayStartTimesMicros: [String: Int64]? = nil,
        multiTrackStateJson: [String: AnyCodableValue]? = nil,
        clearOutPointMicros: Bool = false,
        clearThumbnailPath: Bool = false,
        clearCompressorParams: Bool = false,
        clearNoiseGateParams: Bool = false,
        clearMultiTrackStateJson: Bool = false
    ) -> Project {
        Project(
            id: id ?? self.id,
            name: name ?? self.name,
            sourceVideoPath: sourceVideoPath ?? self.sourceVideoPath,
            frameRate: frameRate ?? self.frameRate,
            durationMicros: durationMicros ?? self.durationMicros,
            clips: clips ?? self.clips,
            inPointMicros: inPointMicros ?? self.inPointMicros,
            outPointMicros: clearOutPointMicros ? nil : (outPointMicros ?? self.outPointMicros),
            createdAt: createdAt ?? self.createdAt,
            modifiedAt: modifiedAt ?? self.modifiedAt,
            thumbnailPath: clearThumbnailPath ? nil : (thumbnailPath ?? self.thumbnailPath),
            version: version ?? self.version,
            cropAspectRatio: cropAspectRatio ?? self.cropAspectRatio,
            cropAspectRatioLabel: cropAspectRatioLabel ?? self.cropAspectRatioLabel,
            cropRotation90: cropRotation90 ?? self.cropRotation90,
            cropFlipHorizontal: cropFlipHorizontal ?? self.cropFlipHorizontal,
            cropFlipVertical: cropFlipVertical ?? self.cropFlipVertical,
            compressorParams: clearCompressorParams ? nil : (compressorParams ?? self.compressorParams),
            noiseGateParams: clearNoiseGateParams ? nil : (noiseGateParams ?? self.noiseGateParams),
            noiseReductionIntensity: noiseReductionIntensity ?? self.noiseReductionIntensity,
            noiseReductionEnabled: noiseReductionEnabled ?? self.noiseReductionEnabled,
            playbackSpeed: playbackSpeed ?? self.playbackSpeed,
            textOverlays: textOverlays ?? self.textOverlays,
            stickerOverlays: stickerOverlays ?? self.stickerOverlays,
            overlayStartTimesMicros: overlayStartTimesMicros ?? self.overlayStartTimesMicros,
            multiTrackStateJson: clearMultiTrackStateJson ? nil : (multiTrackStateJson ?? self.multiTrackStateJson)
        )
    }

    /// Return a new Project with updated modification timestamp.
    func touched() -> Project {
        with(modifiedAt: Date())
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Equatable (by ID)

    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceVideoPath
        case frameRate
        case durationMicros = "duration"
        case clips
        case inPointMicros = "inPoint"
        case outPointMicros = "outPoint"
        case createdAt
        case modifiedAt
        case thumbnailPath
        case version
        case cropAspectRatio
        case cropAspectRatioLabel
        case cropRotation90
        case cropFlipHorizontal
        case cropFlipVertical
        case compressorParams
        case noiseGateParams
        case noiseReductionIntensity
        case noiseReductionEnabled
        case playbackSpeed
        case textOverlays
        case stickerOverlays
        case overlayStartTimesMicros
        case multiTrackStateJson
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(sourceVideoPath, forKey: .sourceVideoPath)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(durationMicros, forKey: .durationMicros)
        try container.encode(clips, forKey: .clips)
        try container.encode(inPointMicros, forKey: .inPointMicros)
        try container.encodeIfPresent(outPointMicros, forKey: .outPointMicros)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
        try container.encode(version, forKey: .version)
        if cropAspectRatio != 0.0 {
            try container.encode(cropAspectRatio, forKey: .cropAspectRatio)
        }
        if !cropAspectRatioLabel.isEmpty {
            try container.encode(cropAspectRatioLabel, forKey: .cropAspectRatioLabel)
        }
        if cropRotation90 != 0 {
            try container.encode(cropRotation90, forKey: .cropRotation90)
        }
        if cropFlipHorizontal {
            try container.encode(cropFlipHorizontal, forKey: .cropFlipHorizontal)
        }
        if cropFlipVertical {
            try container.encode(cropFlipVertical, forKey: .cropFlipVertical)
        }
        try container.encodeIfPresent(compressorParams, forKey: .compressorParams)
        try container.encodeIfPresent(noiseGateParams, forKey: .noiseGateParams)
        if noiseReductionIntensity != 0.5 {
            try container.encode(noiseReductionIntensity, forKey: .noiseReductionIntensity)
        }
        if noiseReductionEnabled {
            try container.encode(noiseReductionEnabled, forKey: .noiseReductionEnabled)
        }
        if playbackSpeed != 1.0 {
            try container.encode(playbackSpeed, forKey: .playbackSpeed)
        }
        if !textOverlays.isEmpty {
            try container.encode(textOverlays, forKey: .textOverlays)
        }
        if !stickerOverlays.isEmpty {
            try container.encode(stickerOverlays, forKey: .stickerOverlays)
        }
        if !overlayStartTimesMicros.isEmpty {
            try container.encode(overlayStartTimesMicros, forKey: .overlayStartTimesMicros)
        }
        try container.encodeIfPresent(multiTrackStateJson, forKey: .multiTrackStateJson)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceVideoPath = try container.decode(String.self, forKey: .sourceVideoPath)
        frameRate = try container.decodeIfPresent(FrameRateOption.self, forKey: .frameRate) ?? Defaults.frameRate
        durationMicros = try container.decodeIfPresent(Int64.self, forKey: .durationMicros) ?? Defaults.durationMicros
        clips = try container.decodeIfPresent([[String: AnyCodableValue]].self, forKey: .clips) ?? Defaults.clips
        inPointMicros = try container.decodeIfPresent(Int64.self, forKey: .inPointMicros) ?? Defaults.inPointMicros
        outPointMicros = try container.decodeIfPresent(Int64.self, forKey: .outPointMicros)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Defaults.version
        cropAspectRatio = try container.decodeIfPresent(Double.self, forKey: .cropAspectRatio) ?? Defaults.cropAspectRatio
        cropAspectRatioLabel = try container.decodeIfPresent(String.self, forKey: .cropAspectRatioLabel) ?? Defaults.cropAspectRatioLabel
        cropRotation90 = try container.decodeIfPresent(Int.self, forKey: .cropRotation90) ?? Defaults.cropRotation90
        cropFlipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .cropFlipHorizontal) ?? Defaults.cropFlipHorizontal
        cropFlipVertical = try container.decodeIfPresent(Bool.self, forKey: .cropFlipVertical) ?? Defaults.cropFlipVertical
        compressorParams = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .compressorParams)
        noiseGateParams = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .noiseGateParams)
        noiseReductionIntensity = try container.decodeIfPresent(Double.self, forKey: .noiseReductionIntensity) ?? Defaults.noiseReductionIntensity
        noiseReductionEnabled = try container.decodeIfPresent(Bool.self, forKey: .noiseReductionEnabled) ?? Defaults.noiseReductionEnabled
        playbackSpeed = try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? Defaults.playbackSpeed
        textOverlays = try container.decodeIfPresent([TextClip].self, forKey: .textOverlays) ?? Defaults.textOverlays
        stickerOverlays = try container.decodeIfPresent([StickerClip].self, forKey: .stickerOverlays) ?? Defaults.stickerOverlays
        overlayStartTimesMicros = try container.decodeIfPresent([String: Int64].self, forKey: .overlayStartTimesMicros) ?? Defaults.overlayStartTimesMicros
        multiTrackStateJson = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .multiTrackStateJson)
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "Project(id: \(id), name: \(name), clips: \(clips.count), version: \(version))"
    }
}

// MARK: - AnyCodableValue

/// Type-erased Codable value for storing heterogeneous JSON data.
///
/// Supports the standard JSON value types: null, bool, int, double, string,
/// array, and object. Used for fields like `compressorParams`, `noiseGateParams`,
/// and `multiTrackStateJson` that store arbitrary JSON structures.
enum AnyCodableValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let intVal = try? container.decode(Int64.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else if let arrayVal = try? container.decode([AnyCodableValue].self) {
            self = .array(arrayVal)
        } else if let objectVal = try? container.decode([String: AnyCodableValue].self) {
            self = .object(objectVal)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let val):
            try container.encode(val)
        case .int(let val):
            try container.encode(val)
        case .double(let val):
            try container.encode(val)
        case .string(let val):
            try container.encode(val)
        case .array(let val):
            try container.encode(val)
        case .object(let val):
            try container.encode(val)
        }
    }
}
