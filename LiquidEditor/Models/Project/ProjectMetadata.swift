// ProjectMetadata.swift
// LiquidEditor
//
// Lightweight project metadata for listing without loading full project data.

import Foundation

// MARK: - ProjectColor

/// Color labels for project organization.
enum ProjectColor: String, Codable, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink

    var displayName: String {
        switch self {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        }
    }
}

// MARK: - ProjectMetadata

/// Lightweight metadata extracted from a full project.
///
/// Used for displaying project cards in the library without loading
/// the full timeline data. This enables fast project list rendering.
struct ProjectMetadata: Codable, Equatable, Hashable, Sendable {

    /// Unique project identifier.
    let id: String

    /// Project display name.
    let name: String

    /// Creation date.
    let createdAt: Date

    /// Last modified date.
    let modifiedAt: Date

    /// Relative path to thumbnail image.
    let thumbnailPath: String?

    /// Total timeline duration in milliseconds.
    let timelineDurationMs: Int

    /// Number of clips in the timeline.
    let clipCount: Int

    /// File size in bytes.
    let fileSizeBytes: Int64

    /// Project schema version.
    let version: Int

    /// Optional description.
    let description: String?

    /// User-assigned tags.
    let tags: [String]

    /// Whether marked as favorite.
    let isFavorite: Bool

    /// Color label for visual organization.
    let colorLabel: ProjectColor?

    /// Quality score for the project (0.0 - 1.0).
    /// Derived from source video analysis or user rating.
    /// Nil means unrated / not yet analyzed.
    let qualityScore: Double?

    // MARK: - Init with defaults

    init(
        id: String,
        name: String,
        createdAt: Date,
        modifiedAt: Date,
        thumbnailPath: String? = nil,
        timelineDurationMs: Int = 0,
        clipCount: Int = 0,
        fileSizeBytes: Int64 = 0,
        version: Int = 2,
        description: String? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        colorLabel: ProjectColor? = nil,
        qualityScore: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.thumbnailPath = thumbnailPath
        self.timelineDurationMs = timelineDurationMs
        self.clipCount = clipCount
        self.fileSizeBytes = fileSizeBytes
        self.version = version
        self.description = description
        self.tags = tags
        self.isFavorite = isFavorite
        self.colorLabel = colorLabel
        self.qualityScore = qualityScore
    }

    // MARK: - Computed Properties

    /// Formatted duration string (e.g., "1:30").
    var formattedDuration: String {
        let totalSeconds = timelineDurationMs / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// Formatted relative time (e.g., "2h ago", "Yesterday").
    var formattedModifiedAgo: String {
        let now = Date()
        let diff = now.timeIntervalSince(modifiedAt)
        let diffMinutes = Int(diff / 60)
        let diffHours = Int(diff / 3600)
        let diffDays = Int(diff / 86400)

        if diffMinutes < 1 { return "Just now" }
        if diffMinutes < 60 { return "\(diffMinutes)m ago" }
        if diffHours < 24 { return "\(diffHours)h ago" }
        if diffDays < 7 { return "\(diffDays)d ago" }
        if diffDays < 30 { return "\(diffDays / 7)w ago" }

        let calendar = Calendar.current
        let month = calendar.component(.month, from: modifiedAt)
        let day = calendar.component(.day, from: modifiedAt)
        let year = calendar.component(.year, from: modifiedAt)
        return "\(month)/\(day)/\(year)"
    }

    /// Compact relative time without trailing "ago" suffix (e.g., "2h", "3d", "1w").
    /// Used for tight card layouts where space is limited.
    var formattedModifiedCompact: String {
        let now = Date()
        let diff = now.timeIntervalSince(modifiedAt)
        let diffMinutes = Int(diff / 60)
        let diffHours = Int(diff / 3600)
        let diffDays = Int(diff / 86400)

        if diffMinutes < 1 { return "now" }
        if diffMinutes < 60 { return "\(diffMinutes)m" }
        if diffHours < 24 { return "\(diffHours)h" }
        if diffDays < 7 { return "\(diffDays)d" }
        return "\(diffDays / 7)w"
    }

    /// Quality star count (1-5), derived from qualityScore.
    /// Returns nil when qualityScore is nil (unrated).
    var qualityStarCount: Int? {
        guard let score = qualityScore else { return nil }
        return max(1, min(5, Int((score * 5).rounded())))
    }

    /// Formatted file size string (e.g., "12 MB", "1.2 GB").
    var formattedFileSize: String {
        if fileSizeBytes <= 0 { return "" }
        let kb = Double(fileSizeBytes) / 1_000
        let mb = kb / 1_000
        let gb = mb / 1_000

        if gb >= 1.0 {
            return gb >= 10.0
                ? "\(Int(gb)) GB"
                : String(format: "%.1f GB", gb)
        } else if mb >= 1.0 {
            return mb >= 10.0
                ? "\(Int(mb)) MB"
                : String(format: "%.1f MB", mb)
        } else if kb >= 1.0 {
            return "\(Int(kb)) KB"
        } else {
            return "\(fileSizeBytes) B"
        }
    }

    // MARK: - with(...)

    func with(
        id: String? = nil,
        name: String? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil,
        thumbnailPath: String?? = nil,
        timelineDurationMs: Int? = nil,
        clipCount: Int? = nil,
        fileSizeBytes: Int64? = nil,
        version: Int? = nil,
        description: String?? = nil,
        tags: [String]? = nil,
        isFavorite: Bool? = nil,
        colorLabel: ProjectColor?? = nil,
        qualityScore: Double?? = nil
    ) -> ProjectMetadata {
        ProjectMetadata(
            id: id ?? self.id,
            name: name ?? self.name,
            createdAt: createdAt ?? self.createdAt,
            modifiedAt: modifiedAt ?? self.modifiedAt,
            thumbnailPath: thumbnailPath ?? self.thumbnailPath,
            timelineDurationMs: timelineDurationMs ?? self.timelineDurationMs,
            clipCount: clipCount ?? self.clipCount,
            fileSizeBytes: fileSizeBytes ?? self.fileSizeBytes,
            version: version ?? self.version,
            description: description ?? self.description,
            tags: tags ?? self.tags,
            isFavorite: isFavorite ?? self.isFavorite,
            colorLabel: colorLabel ?? self.colorLabel,
            qualityScore: qualityScore ?? self.qualityScore
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: ProjectMetadata, rhs: ProjectMetadata) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case modifiedAt
        case thumbnailPath
        case timelineDurationMs
        case clipCount
        case fileSizeBytes
        case version
        case description
        case tags
        case isFavorite
        case colorLabel
        case qualityScore
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        let createdAtStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtStr) ?? Date()

        let modifiedAtStr = try container.decode(String.self, forKey: .modifiedAt)
        modifiedAt = ISO8601DateFormatter().date(from: modifiedAtStr) ?? Date()

        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
        timelineDurationMs = try container.decodeIfPresent(Int.self, forKey: .timelineDurationMs) ?? 0
        clipCount = try container.decodeIfPresent(Int.self, forKey: .clipCount) ?? 0
        fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes) ?? 0
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        description = try container.decodeIfPresent(String.self, forKey: .description)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        colorLabel = try container.decodeIfPresent(ProjectColor.self, forKey: .colorLabel)
        qualityScore = try container.decodeIfPresent(Double.self, forKey: .qualityScore)
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
        try container.encode(ISO8601DateFormatter().string(from: modifiedAt), forKey: .modifiedAt)
        try container.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
        try container.encode(timelineDurationMs, forKey: .timelineDurationMs)
        try container.encode(clipCount, forKey: .clipCount)
        try container.encode(fileSizeBytes, forKey: .fileSizeBytes)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(tags, forKey: .tags)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(colorLabel, forKey: .colorLabel)
        try container.encodeIfPresent(qualityScore, forKey: .qualityScore)
    }
}
