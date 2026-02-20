// ProjectSettings.swift
// LiquidEditor
//
// Per-project settings for resolution, FPS, background color, and aspect ratio.

import Foundation

// MARK: - FrameRate

/// Supported project frame rates.
enum FrameRate: String, Codable, CaseIterable, Sendable {
    case fps24
    case fps30
    case fps60

    var value: Int {
        switch self {
        case .fps24: return 24
        case .fps30: return 30
        case .fps60: return 60
        }
    }

    var displayName: String { "\(value) FPS" }

    /// Detect frame rate from video FPS value.
    static func fromFps(_ fps: Double) -> FrameRate {
        if fps >= 55 { return .fps60 }
        if fps >= 28 { return .fps30 }
        return .fps24
    }
}

// MARK: - FrameRateOption

/// Frame rate option including Auto (from source).
enum FrameRateOption: String, Codable, CaseIterable, Sendable {
    case auto
    case fixed24
    case fixed30
    case fixed60

    var displayName: String {
        switch self {
        case .auto: return "Auto (from source)"
        case .fixed24: return "24 FPS"
        case .fixed30: return "30 FPS"
        case .fixed60: return "60 FPS"
        }
    }

    var fixedRate: FrameRate? {
        switch self {
        case .auto: return nil
        case .fixed24: return .fps24
        case .fixed30: return .fps30
        case .fixed60: return .fps60
        }
    }
}

// MARK: - Resolution

/// Supported export resolutions.
enum Resolution: String, Codable, CaseIterable, Sendable {
    case sd480p
    case hd720p
    case fullHD1080p
    case qhd1440p
    case uhd4k

    var displayName: String {
        switch self {
        case .sd480p: return "480p"
        case .hd720p: return "720p"
        case .fullHD1080p: return "1080p"
        case .qhd1440p: return "1440p"
        case .uhd4k: return "4K"
        }
    }

    var width: Int {
        switch self {
        case .sd480p: return 854
        case .hd720p: return 1280
        case .fullHD1080p: return 1920
        case .qhd1440p: return 2560
        case .uhd4k: return 3840
        }
    }

    var height: Int {
        switch self {
        case .sd480p: return 480
        case .hd720p: return 720
        case .fullHD1080p: return 1080
        case .qhd1440p: return 1440
        case .uhd4k: return 2160
        }
    }
}

// MARK: - ProjectSettings

/// Per-project settings that control rendering and export behavior.
struct ProjectSettings: Codable, Equatable, Hashable, Sendable {

    /// Target resolution for export.
    let resolution: Resolution

    /// Frame rate setting.
    let frameRate: FrameRateOption

    /// Aspect ratio setting (nil = auto from source).
    let aspectRatio: AspectRatioSetting?

    /// How clips adapt when aspect ratio differs from source.
    let aspectRatioMode: AspectRatioMode

    /// Background color as ARGB integer (default black).
    let backgroundColor: Int

    // MARK: - Init with defaults

    init(
        resolution: Resolution = .fullHD1080p,
        frameRate: FrameRateOption = .auto,
        aspectRatio: AspectRatioSetting? = nil,
        aspectRatioMode: AspectRatioMode = .letterbox,
        backgroundColor: Int = 0xFF000000
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.aspectRatio = aspectRatio
        self.aspectRatioMode = aspectRatioMode
        self.backgroundColor = backgroundColor
    }

    /// Default settings for a new project.
    static let defaultSettings = ProjectSettings()

    // MARK: - with(...)

    func with(
        resolution: Resolution? = nil,
        frameRate: FrameRateOption? = nil,
        aspectRatio: AspectRatioSetting?? = nil,
        aspectRatioMode: AspectRatioMode? = nil,
        backgroundColor: Int? = nil
    ) -> ProjectSettings {
        ProjectSettings(
            resolution: resolution ?? self.resolution,
            frameRate: frameRate ?? self.frameRate,
            aspectRatio: aspectRatio ?? self.aspectRatio,
            aspectRatioMode: aspectRatioMode ?? self.aspectRatioMode,
            backgroundColor: backgroundColor ?? self.backgroundColor
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case resolution
        case frameRate
        case aspectRatio
        case aspectRatioMode
        case backgroundColor
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let resolutionStr = try container.decodeIfPresent(String.self, forKey: .resolution)
        resolution = resolutionStr.flatMap { Resolution(rawValue: $0) } ?? .fullHD1080p

        let frameRateStr = try container.decodeIfPresent(String.self, forKey: .frameRate)
        frameRate = frameRateStr.flatMap { FrameRateOption(rawValue: $0) } ?? .auto

        aspectRatio = try container.decodeIfPresent(AspectRatioSetting.self, forKey: .aspectRatio)

        let modeStr = try container.decodeIfPresent(String.self, forKey: .aspectRatioMode)
        aspectRatioMode = modeStr.flatMap { AspectRatioMode(rawValue: $0) } ?? .letterbox

        backgroundColor = try container.decodeIfPresent(Int.self, forKey: .backgroundColor) ?? 0xFF000000
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resolution.rawValue, forKey: .resolution)
        try container.encode(frameRate.rawValue, forKey: .frameRate)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try container.encode(aspectRatioMode.rawValue, forKey: .aspectRatioMode)
        try container.encode(backgroundColor, forKey: .backgroundColor)
    }
}
