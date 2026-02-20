// ProjectTemplate.swift
// LiquidEditor
//
// Project templates for preset configurations.

import Foundation

// MARK: - TemplateCategory

/// Template categories for organization.
enum TemplateCategory: String, Codable, CaseIterable, Sendable {
    case social
    case cinematic
    case standard
    case custom

    var displayName: String {
        switch self {
        case .social: return "Social"
        case .cinematic: return "Cinematic"
        case .standard: return "Standard"
        case .custom: return "My Templates"
        }
    }
}

// MARK: - ProjectTemplate

/// A project template with preset settings.
struct ProjectTemplate: Codable, Equatable, Hashable, Sendable {

    /// Unique identifier.
    let id: String

    /// Template display name.
    let name: String

    /// Template description.
    let description: String

    /// Template category.
    let category: TemplateCategory

    /// Whether this is a built-in template.
    let isBuiltIn: Bool

    /// Aspect ratio setting (nil = auto from source).
    let aspectRatio: AspectRatioSetting?

    /// Frame rate setting.
    let frameRate: FrameRateOption

    /// Target resolution.
    let resolution: Resolution?

    /// Aspect ratio adaptation mode.
    let aspectRatioMode: AspectRatioMode

    /// SF Symbol name for template icon.
    let iconSymbol: String

    /// Template creation date.
    let createdAt: Date

    // MARK: - Init with defaults

    init(
        id: String,
        name: String,
        description: String,
        category: TemplateCategory,
        isBuiltIn: Bool = false,
        aspectRatio: AspectRatioSetting? = nil,
        frameRate: FrameRateOption = .auto,
        resolution: Resolution? = nil,
        aspectRatioMode: AspectRatioMode = .zoomToFill,
        iconSymbol: String,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.aspectRatio = aspectRatio
        self.frameRate = frameRate
        self.resolution = resolution
        self.aspectRatioMode = aspectRatioMode
        self.iconSymbol = iconSymbol
        self.createdAt = createdAt
    }

    /// Convert template settings to ProjectSettings.
    func toProjectSettings() -> ProjectSettings {
        ProjectSettings(
            resolution: resolution ?? .fullHD1080p,
            frameRate: frameRate,
            aspectRatio: aspectRatio,
            aspectRatioMode: aspectRatioMode
        )
    }

    // MARK: - Built-in Templates

    private static let builtInDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }()

    static let blank = ProjectTemplate(
        id: "builtin-blank",
        name: "Blank",
        description: "No presets, uses source video settings",
        category: .standard,
        isBuiltIn: true,
        iconSymbol: "doc",
        createdAt: builtInDate
    )

    static let tiktokReels = ProjectTemplate(
        id: "builtin-tiktok",
        name: "TikTok / Reels",
        description: "Vertical short-form video (9:16, 30fps)",
        category: .social,
        isBuiltIn: true,
        aspectRatio: .portrait9x16,
        frameRate: .fixed30,
        resolution: .fullHD1080p,
        iconSymbol: "play.rectangle.fill",
        createdAt: builtInDate
    )

    static let instagramFeed = ProjectTemplate(
        id: "builtin-insta-feed",
        name: "Instagram Feed",
        description: "Square post format (1:1, 30fps)",
        category: .social,
        isBuiltIn: true,
        aspectRatio: .square1x1,
        frameRate: .fixed30,
        resolution: .fullHD1080p,
        iconSymbol: "square.fill",
        createdAt: builtInDate
    )

    static let instagramStory = ProjectTemplate(
        id: "builtin-insta-story",
        name: "Instagram Story",
        description: "Vertical story format (9:16, 30fps)",
        category: .social,
        isBuiltIn: true,
        aspectRatio: .portrait9x16,
        frameRate: .fixed30,
        resolution: .fullHD1080p,
        iconSymbol: "rectangle.portrait.fill",
        createdAt: builtInDate
    )

    static let youtube = ProjectTemplate(
        id: "builtin-youtube",
        name: "YouTube",
        description: "Standard landscape (16:9, 30fps, 1080p)",
        category: .standard,
        isBuiltIn: true,
        aspectRatio: .landscape16x9,
        frameRate: .fixed30,
        resolution: .fullHD1080p,
        iconSymbol: "play.rectangle.fill",
        createdAt: builtInDate
    )

    static let youtubeShorts = ProjectTemplate(
        id: "builtin-yt-shorts",
        name: "YouTube Shorts",
        description: "Vertical YouTube format (9:16, 30fps)",
        category: .social,
        isBuiltIn: true,
        aspectRatio: .portrait9x16,
        frameRate: .fixed30,
        resolution: .fullHD1080p,
        iconSymbol: "rectangle.portrait.fill",
        createdAt: builtInDate
    )

    static let cinematicFilm = ProjectTemplate(
        id: "builtin-cinematic",
        name: "Cinematic",
        description: "Film-style widescreen (2.35:1, 24fps)",
        category: .cinematic,
        isBuiltIn: true,
        aspectRatio: .cinematic,
        frameRate: .fixed24,
        resolution: .fullHD1080p,
        iconSymbol: "film",
        createdAt: builtInDate
    )

    static let builtIns: [ProjectTemplate] = [
        .blank,
        .tiktokReels,
        .instagramFeed,
        .instagramStory,
        .youtube,
        .youtubeShorts,
        .cinematicFilm,
    ]

    // MARK: - with(...)

    func with(
        id: String? = nil,
        name: String? = nil,
        description: String? = nil,
        category: TemplateCategory? = nil,
        isBuiltIn: Bool? = nil,
        aspectRatio: AspectRatioSetting?? = nil,
        frameRate: FrameRateOption? = nil,
        resolution: Resolution?? = nil,
        aspectRatioMode: AspectRatioMode? = nil,
        iconSymbol: String? = nil,
        createdAt: Date? = nil
    ) -> ProjectTemplate {
        ProjectTemplate(
            id: id ?? self.id,
            name: name ?? self.name,
            description: description ?? self.description,
            category: category ?? self.category,
            isBuiltIn: isBuiltIn ?? self.isBuiltIn,
            aspectRatio: aspectRatio ?? self.aspectRatio,
            frameRate: frameRate ?? self.frameRate,
            resolution: resolution ?? self.resolution,
            aspectRatioMode: aspectRatioMode ?? self.aspectRatioMode,
            iconSymbol: iconSymbol ?? self.iconSymbol,
            createdAt: createdAt ?? self.createdAt
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: ProjectTemplate, rhs: ProjectTemplate) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case category
        case isBuiltIn
        case aspectRatio
        case frameRate
        case resolution
        case aspectRatioMode
        case iconSymbol
        case createdAt
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)

        let categoryStr = try container.decode(String.self, forKey: .category)
        category = TemplateCategory(rawValue: categoryStr) ?? .custom

        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        aspectRatio = try container.decodeIfPresent(AspectRatioSetting.self, forKey: .aspectRatio)

        let frameRateStr = try container.decodeIfPresent(String.self, forKey: .frameRate)
        frameRate = frameRateStr.flatMap { FrameRateOption(rawValue: $0) } ?? .auto

        let resolutionStr = try container.decodeIfPresent(String.self, forKey: .resolution)
        resolution = resolutionStr.flatMap { Resolution(rawValue: $0) }

        let modeStr = try container.decodeIfPresent(String.self, forKey: .aspectRatioMode)
        aspectRatioMode = modeStr.flatMap { AspectRatioMode(rawValue: $0) } ?? .zoomToFill

        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol) ?? "doc"

        let dateStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
        try container.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try container.encode(frameRate.rawValue, forKey: .frameRate)
        try container.encodeIfPresent(resolution?.rawValue, forKey: .resolution)
        try container.encode(aspectRatioMode.rawValue, forKey: .aspectRatioMode)
        try container.encode(iconSymbol, forKey: .iconSymbol)
        try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
    }
}
