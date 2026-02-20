// ExportConfig.swift
// LiquidEditor
//
// Export configuration models for the Liquid Editor export pipeline.

import Foundation

// MARK: - ExportResolution

/// Supported export resolutions.
enum ExportResolution: String, Codable, CaseIterable, Sendable {
    case r480p
    case r720p
    case r1080p
    case r1440p
    case r4K
    case custom

    var width: Int {
        switch self {
        case .r480p: return 854
        case .r720p: return 1280
        case .r1080p: return 1920
        case .r1440p: return 2560
        case .r4K: return 3840
        case .custom: return 0
        }
    }

    var height: Int {
        switch self {
        case .r480p: return 480
        case .r720p: return 720
        case .r1080p: return 1080
        case .r1440p: return 1440
        case .r4K: return 2160
        case .custom: return 0
        }
    }

    var label: String {
        switch self {
        case .r480p: return "480p"
        case .r720p: return "720p"
        case .r1080p: return "1080p"
        case .r1440p: return "1440p"
        case .r4K: return "4K"
        case .custom: return "Custom"
        }
    }
}

// MARK: - ExportCodec

/// Supported video codecs.
enum ExportCodec: String, Codable, CaseIterable, Sendable {
    case h264
    case h265
    case proRes

    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .h265: return "H.265 (HEVC)"
        case .proRes: return "ProRes"
        }
    }

    var avFoundationKey: String {
        switch self {
        case .h264: return "avc1"
        case .h265: return "hvc1"
        case .proRes: return "apcn"
        }
    }
}

// MARK: - ExportFormat

/// Supported container formats.
enum ExportFormat: String, Codable, CaseIterable, Sendable {
    case mp4
    case mov
    case m4v

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mov: return "mov"
        case .m4v: return "m4v"
        }
    }

    var displayName: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "MOV"
        case .m4v: return "M4V"
        }
    }

    var mimeType: String {
        switch self {
        case .mp4: return "video/mp4"
        case .mov: return "video/quicktime"
        case .m4v: return "video/x-m4v"
        }
    }
}

// MARK: - ExportQuality

/// Export quality presets.
enum ExportQuality: String, Codable, CaseIterable, Sendable {
    case draft
    case standard
    case high
    case maximum

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .standard: return "Standard"
        case .high: return "High"
        case .maximum: return "Maximum"
        }
    }

    var bitrateMultiplier: Double {
        switch self {
        case .draft: return 0.3
        case .standard: return 0.6
        case .high: return 1.0
        case .maximum: return 1.5
        }
    }
}

// MARK: - ExportAudioCodec

/// Supported audio codecs for export.
enum ExportAudioCodec: String, Codable, CaseIterable, Sendable {
    case aac
    case alac
    case wav
    case flac

    var displayName: String {
        switch self {
        case .aac: return "AAC"
        case .alac: return "ALAC"
        case .wav: return "WAV"
        case .flac: return "FLAC"
        }
    }

    var fileExtension: String {
        switch self {
        case .aac: return "m4a"
        case .alac: return "m4a"
        case .wav: return "wav"
        case .flac: return "flac"
        }
    }
}

// MARK: - SocialMediaPreset

/// Social media platform presets.
enum SocialMediaPreset: String, Codable, CaseIterable, Sendable {
    case instagram
    case tiktok
    case youtube
    case twitter
    case facebook

    var displayName: String {
        switch self {
        case .instagram: return "Instagram Reels"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .twitter: return "X (Twitter)"
        case .facebook: return "Facebook"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .instagram: return "camera.on.rectangle"
        case .tiktok: return "music.note"
        case .youtube: return "play.rectangle"
        case .twitter: return "bubble.left"
        case .facebook: return "person.2"
        }
    }

    var width: Int {
        switch self {
        case .instagram: return 1080
        case .tiktok: return 1080
        case .youtube: return 3840
        case .twitter: return 1920
        case .facebook: return 1080
        }
    }

    var height: Int {
        switch self {
        case .instagram: return 1920
        case .tiktok: return 1920
        case .youtube: return 2160
        case .twitter: return 1200
        case .facebook: return 1350
        }
    }

    var maxFps: Int {
        switch self {
        case .instagram: return 30
        case .tiktok: return 60
        case .youtube: return 60
        case .twitter: return 60
        case .facebook: return 30
        }
    }

    var maxBitrateMbps: Double {
        switch self {
        case .instagram: return 25.0
        case .tiktok: return 30.0
        case .youtube: return 68.0
        case .twitter: return 25.0
        case .facebook: return 16.0
        }
    }

    var maxDurationSeconds: Int {
        switch self {
        case .instagram: return 900
        case .tiktok: return 600
        case .youtube: return 43200
        case .twitter: return 140
        case .facebook: return 14400
        }
    }

    var maxFileSizeMB: Int {
        switch self {
        case .instagram: return 250
        case .tiktok: return 287
        case .youtube: return 128000
        case .twitter: return 512
        case .facebook: return 10240
        }
    }

    var codec: ExportCodec {
        // All presets currently use H.264
        .h264
    }

    var format: ExportFormat {
        // All presets currently use MP4
        .mp4
    }

    var aspectRatioWidth: Int {
        switch self {
        case .instagram: return 9
        case .tiktok: return 9
        case .youtube: return 16
        case .twitter: return 16
        case .facebook: return 4
        }
    }

    var aspectRatioHeight: Int {
        switch self {
        case .instagram: return 16
        case .tiktok: return 16
        case .youtube: return 9
        case .twitter: return 9
        case .facebook: return 5
        }
    }

    var supportsHdr: Bool {
        switch self {
        case .youtube: return true
        default: return false
        }
    }

    var aspectRatio: Double {
        Double(aspectRatioWidth) / Double(aspectRatioHeight)
    }

    /// Convert this preset to an ExportConfig.
    func toExportConfig() -> ExportConfig {
        ExportConfig(
            resolution: .custom,
            customWidth: width,
            customHeight: height,
            fps: maxFps,
            codec: codec,
            format: format,
            quality: .high,
            bitrateMbps: maxBitrateMbps,
            audioCodec: .aac,
            audioBitrate: 256,
            enableHdr: supportsHdr,
            socialPreset: self
        )
    }
}

// MARK: - ExportPhase

/// Phases of an export operation.
enum ExportPhase: String, Codable, CaseIterable, Sendable {
    case preparing
    case rendering
    case encoding
    case saving
    case completed
    case failed
    case cancelled
}

// MARK: - ExportConfig

/// Complete export configuration.
struct ExportConfig: Codable, Equatable, Hashable, Sendable {

    /// Output resolution preset.
    let resolution: ExportResolution

    /// Custom width (used when resolution == custom).
    let customWidth: Int?

    /// Custom height (used when resolution == custom).
    let customHeight: Int?

    /// Frames per second.
    let fps: Int

    /// Video codec.
    let codec: ExportCodec

    /// Container format.
    let format: ExportFormat

    /// Quality preset (affects bitrate).
    let quality: ExportQuality

    /// Target bitrate in megabits per second.
    let bitrateMbps: Double

    /// Audio codec.
    let audioCodec: ExportAudioCodec

    /// Audio bitrate in kbps.
    let audioBitrate: Int

    /// Whether to enable HDR output.
    let enableHdr: Bool

    /// Whether to export audio only.
    let audioOnly: Bool

    /// Social media preset (nil for custom).
    let socialPreset: SocialMediaPreset?

    // MARK: - Init with defaults

    init(
        resolution: ExportResolution = .r1080p,
        customWidth: Int? = nil,
        customHeight: Int? = nil,
        fps: Int = 30,
        codec: ExportCodec = .h264,
        format: ExportFormat = .mp4,
        quality: ExportQuality = .high,
        bitrateMbps: Double = 20.0,
        audioCodec: ExportAudioCodec = .aac,
        audioBitrate: Int = 256,
        enableHdr: Bool = false,
        audioOnly: Bool = false,
        socialPreset: SocialMediaPreset? = nil
    ) {
        self.resolution = resolution
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.fps = fps
        self.codec = codec
        self.format = format
        self.quality = quality
        self.bitrateMbps = bitrateMbps
        self.audioCodec = audioCodec
        self.audioBitrate = audioBitrate
        self.enableHdr = enableHdr
        self.audioOnly = audioOnly
        self.socialPreset = socialPreset
    }

    // MARK: - Computed Properties

    /// Effective output width.
    var outputWidth: Int {
        if resolution == .custom {
            return customWidth ?? 1920
        }
        return resolution.width
    }

    /// Effective output height.
    var outputHeight: Int {
        if resolution == .custom {
            return customHeight ?? 1080
        }
        return resolution.height
    }

    /// Effective bitrate after quality multiplier.
    var effectiveBitrateMbps: Double {
        bitrateMbps * quality.bitrateMultiplier
    }

    // MARK: - with(...)

    func with(
        resolution: ExportResolution? = nil,
        customWidth: Int?? = nil,
        customHeight: Int?? = nil,
        fps: Int? = nil,
        codec: ExportCodec? = nil,
        format: ExportFormat? = nil,
        quality: ExportQuality? = nil,
        bitrateMbps: Double? = nil,
        audioCodec: ExportAudioCodec? = nil,
        audioBitrate: Int? = nil,
        enableHdr: Bool? = nil,
        audioOnly: Bool? = nil,
        socialPreset: SocialMediaPreset?? = nil
    ) -> ExportConfig {
        ExportConfig(
            resolution: resolution ?? self.resolution,
            customWidth: customWidth ?? self.customWidth,
            customHeight: customHeight ?? self.customHeight,
            fps: fps ?? self.fps,
            codec: codec ?? self.codec,
            format: format ?? self.format,
            quality: quality ?? self.quality,
            bitrateMbps: bitrateMbps ?? self.bitrateMbps,
            audioCodec: audioCodec ?? self.audioCodec,
            audioBitrate: audioBitrate ?? self.audioBitrate,
            enableHdr: enableHdr ?? self.enableHdr,
            audioOnly: audioOnly ?? self.audioOnly,
            socialPreset: socialPreset ?? self.socialPreset
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case resolution
        case customWidth
        case customHeight
        case fps
        case codec
        case format
        case quality
        case bitrateMbps
        case audioCodec
        case audioBitrate
        case enableHdr
        case audioOnly
        case socialPreset
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let resStr = try container.decodeIfPresent(String.self, forKey: .resolution)
        resolution = resStr.flatMap { ExportResolution(rawValue: $0) } ?? .r1080p

        customWidth = try container.decodeIfPresent(Int.self, forKey: .customWidth)
        customHeight = try container.decodeIfPresent(Int.self, forKey: .customHeight)
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 30

        let codecStr = try container.decodeIfPresent(String.self, forKey: .codec)
        codec = codecStr.flatMap { ExportCodec(rawValue: $0) } ?? .h264

        let formatStr = try container.decodeIfPresent(String.self, forKey: .format)
        format = formatStr.flatMap { ExportFormat(rawValue: $0) } ?? .mp4

        let qualityStr = try container.decodeIfPresent(String.self, forKey: .quality)
        quality = qualityStr.flatMap { ExportQuality(rawValue: $0) } ?? .high

        bitrateMbps = try container.decodeIfPresent(Double.self, forKey: .bitrateMbps) ?? 20.0

        let audioStr = try container.decodeIfPresent(String.self, forKey: .audioCodec)
        audioCodec = audioStr.flatMap { ExportAudioCodec(rawValue: $0) } ?? .aac

        audioBitrate = try container.decodeIfPresent(Int.self, forKey: .audioBitrate) ?? 256
        enableHdr = try container.decodeIfPresent(Bool.self, forKey: .enableHdr) ?? false
        audioOnly = try container.decodeIfPresent(Bool.self, forKey: .audioOnly) ?? false

        let presetStr = try container.decodeIfPresent(String.self, forKey: .socialPreset)
        socialPreset = presetStr.flatMap { SocialMediaPreset(rawValue: $0) }
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resolution.rawValue, forKey: .resolution)
        try container.encodeIfPresent(customWidth, forKey: .customWidth)
        try container.encodeIfPresent(customHeight, forKey: .customHeight)
        try container.encode(fps, forKey: .fps)
        try container.encode(codec.rawValue, forKey: .codec)
        try container.encode(format.rawValue, forKey: .format)
        try container.encode(quality.rawValue, forKey: .quality)
        try container.encode(bitrateMbps, forKey: .bitrateMbps)
        try container.encode(audioCodec.rawValue, forKey: .audioCodec)
        try container.encode(audioBitrate, forKey: .audioBitrate)
        try container.encode(enableHdr, forKey: .enableHdr)
        try container.encode(audioOnly, forKey: .audioOnly)
        try container.encodeIfPresent(socialPreset?.rawValue, forKey: .socialPreset)
    }
}
