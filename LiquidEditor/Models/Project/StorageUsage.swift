// StorageUsage.swift
// LiquidEditor
//
// Storage usage models for disk space monitoring.

import Foundation
import OSLog

// MARK: - Format Bytes Utility

/// Format bytes into human-readable string.
///
/// Shared utility used by storage-related models and services.
func formatBytes(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1_048_576 {
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }
    if bytes < 1_073_741_824 {
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
    return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
}

// MARK: - ProjectStorageUsage

/// Storage usage for a single project.
struct ProjectStorageUsage: Codable, Equatable, Hashable, Sendable {

    /// Project identifier.
    let projectId: String

    /// Project name (for display).
    let projectName: String

    /// Size of the project JSON file in bytes.
    let projectFileBytes: Int

    /// Size of all referenced media files in bytes.
    let mediaBytes: Int

    /// Size of thumbnail files in bytes.
    let thumbnailBytes: Int

    /// Total storage used by this project.
    var totalBytes: Int { projectFileBytes + mediaBytes + thumbnailBytes }

    /// Formatted total size for display.
    var formattedTotal: String { formatBytes(totalBytes) }

    /// Formatted media size for display.
    var formattedMedia: String { formatBytes(mediaBytes) }

    // MARK: - with(...)

    func with(
        projectId: String? = nil,
        projectName: String? = nil,
        projectFileBytes: Int? = nil,
        mediaBytes: Int? = nil,
        thumbnailBytes: Int? = nil
    ) -> ProjectStorageUsage {
        ProjectStorageUsage(
            projectId: projectId ?? self.projectId,
            projectName: projectName ?? self.projectName,
            projectFileBytes: projectFileBytes ?? self.projectFileBytes,
            mediaBytes: mediaBytes ?? self.mediaBytes,
            thumbnailBytes: thumbnailBytes ?? self.thumbnailBytes
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: ProjectStorageUsage, rhs: ProjectStorageUsage) -> Bool {
        lhs.projectId == rhs.projectId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(projectId)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case projectId
        case projectName
        case projectFileBytes
        case mediaBytes
        case thumbnailBytes
    }
}

// MARK: - OrphanedFileCategory

/// Category of orphaned files.
enum OrphanedFileCategory: String, Codable, CaseIterable, Sendable {
    /// Video file in Videos/ not referenced by any project.
    case video
    /// Thumbnail file not referenced by any project.
    case thumbnail
    /// Cache file that can be safely deleted.
    case cache
    /// Temporary file from interrupted operations.
    case temporary
}

// MARK: - OrphanedFile

/// Orphaned file detected during storage analysis.
struct OrphanedFile: Codable, Equatable, Hashable, Sendable {

    /// Absolute file path.
    let path: String

    /// File size in bytes.
    let fileSize: Int

    /// When the file was last modified (nil if unknown).
    let lastModified: Date?

    /// Category of the orphaned file.
    let category: OrphanedFileCategory

    /// Alias for `fileSize` for backward compatibility.
    var size: Int { fileSize }

    var formattedSize: String { formatBytes(fileSize) }

    // MARK: - with(...)

    func with(
        path: String? = nil,
        fileSize: Int? = nil,
        lastModified: Date?? = nil,
        category: OrphanedFileCategory? = nil
    ) -> OrphanedFile {
        OrphanedFile(
            path: path ?? self.path,
            fileSize: fileSize ?? self.fileSize,
            lastModified: lastModified ?? self.lastModified,
            category: category ?? self.category
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case path
        case fileSize
        case lastModified
        case category
    }
}

// MARK: - StorageUsage

/// Complete storage usage breakdown.
struct StorageUsage: Codable, Equatable, Sendable {

    /// Size of all project JSON files.
    let projectFilesBytes: Int

    /// Size of all video files.
    let videoFilesBytes: Int

    /// Size of the People library.
    let peopleLibraryBytes: Int

    /// Size of all thumbnails.
    let thumbnailsBytes: Int

    /// Size of app cache.
    let appCacheBytes: Int

    /// Size of other files.
    let otherBytes: Int

    /// Per-project storage breakdown.
    let perProjectUsage: [ProjectStorageUsage]

    /// When this calculation was performed.
    let calculatedAt: Date

    /// Total bytes used across all categories.
    var totalBytes: Int {
        projectFilesBytes + videoFilesBytes + peopleLibraryBytes +
        thumbnailsBytes + appCacheBytes + otherBytes
    }

    /// Formatted total size for display.
    var formattedTotal: String { formatBytes(totalBytes) }

    /// Formatted per-category sizes.
    var formattedProjects: String { formatBytes(projectFilesBytes) }
    var formattedVideos: String { formatBytes(videoFilesBytes) }
    var formattedPeople: String { formatBytes(peopleLibraryBytes) }
    var formattedThumbnails: String { formatBytes(thumbnailsBytes) }
    var formattedCache: String { formatBytes(appCacheBytes) }
    var formattedOther: String { formatBytes(otherBytes) }

    /// Per-project list sorted by total size (largest first).
    var sortedBySize: [ProjectStorageUsage] {
        perProjectUsage.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - with(...)

    func with(
        projectFilesBytes: Int? = nil,
        videoFilesBytes: Int? = nil,
        peopleLibraryBytes: Int? = nil,
        thumbnailsBytes: Int? = nil,
        appCacheBytes: Int? = nil,
        otherBytes: Int? = nil,
        perProjectUsage: [ProjectStorageUsage]? = nil,
        calculatedAt: Date? = nil
    ) -> StorageUsage {
        StorageUsage(
            projectFilesBytes: projectFilesBytes ?? self.projectFilesBytes,
            videoFilesBytes: videoFilesBytes ?? self.videoFilesBytes,
            peopleLibraryBytes: peopleLibraryBytes ?? self.peopleLibraryBytes,
            thumbnailsBytes: thumbnailsBytes ?? self.thumbnailsBytes,
            appCacheBytes: appCacheBytes ?? self.appCacheBytes,
            otherBytes: otherBytes ?? self.otherBytes,
            perProjectUsage: perProjectUsage ?? self.perProjectUsage,
            calculatedAt: calculatedAt ?? self.calculatedAt
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case projectFilesBytes
        case videoFilesBytes
        case peopleLibraryBytes
        case thumbnailsBytes
        case appCacheBytes
        case otherBytes
        case perProjectUsage
        case calculatedAt
    }

    // MARK: - Custom Decoding

    init(
        projectFilesBytes: Int,
        videoFilesBytes: Int,
        peopleLibraryBytes: Int,
        thumbnailsBytes: Int,
        appCacheBytes: Int,
        otherBytes: Int,
        perProjectUsage: [ProjectStorageUsage],
        calculatedAt: Date
    ) {
        self.projectFilesBytes = projectFilesBytes
        self.videoFilesBytes = videoFilesBytes
        self.peopleLibraryBytes = peopleLibraryBytes
        self.thumbnailsBytes = thumbnailsBytes
        self.appCacheBytes = appCacheBytes
        self.otherBytes = otherBytes
        self.perProjectUsage = perProjectUsage
        self.calculatedAt = calculatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectFilesBytes = try container.decode(Int.self, forKey: .projectFilesBytes)
        videoFilesBytes = try container.decode(Int.self, forKey: .videoFilesBytes)
        peopleLibraryBytes = try container.decode(Int.self, forKey: .peopleLibraryBytes)
        thumbnailsBytes = try container.decode(Int.self, forKey: .thumbnailsBytes)
        appCacheBytes = try container.decode(Int.self, forKey: .appCacheBytes)
        otherBytes = try container.decode(Int.self, forKey: .otherBytes)
        perProjectUsage = try container.decode([ProjectStorageUsage].self, forKey: .perProjectUsage)

        let dateStr = try container.decode(String.self, forKey: .calculatedAt)
        if let parsedDate = ISO8601DateFormatter().date(from: dateStr) {
            calculatedAt = parsedDate
        } else {
            Logger(subsystem: "LiquidEditor", category: "StorageUsage")
                .warning("Failed to parse calculatedAt date '\(dateStr)' for StorageUsage. Using current date.")
            calculatedAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectFilesBytes, forKey: .projectFilesBytes)
        try container.encode(videoFilesBytes, forKey: .videoFilesBytes)
        try container.encode(peopleLibraryBytes, forKey: .peopleLibraryBytes)
        try container.encode(thumbnailsBytes, forKey: .thumbnailsBytes)
        try container.encode(appCacheBytes, forKey: .appCacheBytes)
        try container.encode(otherBytes, forKey: .otherBytes)
        try container.encode(perProjectUsage, forKey: .perProjectUsage)
        try container.encode(ISO8601DateFormatter().string(from: calculatedAt), forKey: .calculatedAt)
    }
}
