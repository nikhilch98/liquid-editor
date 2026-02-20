// BackupManifest.swift
// LiquidEditor
//
// Backup manifest model for project backup/restore.

import Foundation

// MARK: - BackupMediaEntry

/// Media file entry within a backup archive.
struct BackupMediaEntry: Codable, Equatable, Hashable, Sendable {

    /// Original relative path in the project (e.g., "Videos/abc.mov").
    let originalPath: String

    /// Path within the archive (e.g., "media/abc.mov").
    let archivePath: String

    /// SHA-256 content hash for integrity verification.
    let contentHash: String

    /// File size in bytes.
    let fileSize: Int

    /// Media type identifier ("video", "image", "audio").
    let mediaType: String

    // MARK: - with(...)

    func with(
        originalPath: String? = nil,
        archivePath: String? = nil,
        contentHash: String? = nil,
        fileSize: Int? = nil,
        mediaType: String? = nil
    ) -> BackupMediaEntry {
        BackupMediaEntry(
            originalPath: originalPath ?? self.originalPath,
            archivePath: archivePath ?? self.archivePath,
            contentHash: contentHash ?? self.contentHash,
            fileSize: fileSize ?? self.fileSize,
            mediaType: mediaType ?? self.mediaType
        )
    }

    /// Format bytes into human-readable string.
    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        if bytes < 1_073_741_824 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        }
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: BackupMediaEntry, rhs: BackupMediaEntry) -> Bool {
        lhs.contentHash == rhs.contentHash
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contentHash)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case originalPath
        case archivePath
        case contentHash
        case fileSize
        case mediaType
    }
}

// MARK: - BackupManifest

/// Backup manifest metadata stored in manifest.json inside the archive.
struct BackupManifest: Codable, Equatable, Hashable, Sendable {

    /// Manifest schema version.
    let version: Int

    /// Application version that created the backup.
    let appVersion: String

    /// Application build number.
    let appBuildNumber: Int

    /// When the backup was created.
    let backupDate: Date

    /// Device model that created the backup.
    let deviceModel: String

    /// iOS version on the creating device.
    let iosVersion: String

    /// Original project ID (a new ID is assigned on restore).
    let projectId: String

    /// Project name at time of backup.
    let projectName: String

    /// Project schema version (for migration compatibility).
    let projectVersion: Int

    /// List of media files included in the backup.
    let mediaFiles: [BackupMediaEntry]

    /// Total archive size in bytes.
    let totalSize: Int

    /// Whether media files are included (full vs metadata-only backup).
    let includesMedia: Bool

    /// Current manifest schema version.
    static let currentVersion: Int = 1

    /// Whether this backup was created by a newer app version.
    func isNewerVersion(currentAppVersion: String) -> Bool {
        let backupParts = appVersion.split(separator: ".").compactMap { Int($0) }
        let currentParts = currentAppVersion.split(separator: ".").compactMap { Int($0) }

        for i in 0..<3 {
            let bp = i < backupParts.count ? backupParts[i] : 0
            let cp = i < currentParts.count ? currentParts[i] : 0
            if bp > cp { return true }
            if bp < cp { return false }
        }
        return false
    }

    /// Formatted total size for display.
    var formattedTotalSize: String { BackupMediaEntry.formatBytes(totalSize) }

    /// Total number of media files.
    var mediaFileCount: Int { mediaFiles.count }

    // MARK: - with(...)

    func with(
        version: Int? = nil,
        appVersion: String? = nil,
        appBuildNumber: Int? = nil,
        backupDate: Date? = nil,
        deviceModel: String? = nil,
        iosVersion: String? = nil,
        projectId: String? = nil,
        projectName: String? = nil,
        projectVersion: Int? = nil,
        mediaFiles: [BackupMediaEntry]? = nil,
        totalSize: Int? = nil,
        includesMedia: Bool? = nil
    ) -> BackupManifest {
        BackupManifest(
            version: version ?? self.version,
            appVersion: appVersion ?? self.appVersion,
            appBuildNumber: appBuildNumber ?? self.appBuildNumber,
            backupDate: backupDate ?? self.backupDate,
            deviceModel: deviceModel ?? self.deviceModel,
            iosVersion: iosVersion ?? self.iosVersion,
            projectId: projectId ?? self.projectId,
            projectName: projectName ?? self.projectName,
            projectVersion: projectVersion ?? self.projectVersion,
            mediaFiles: mediaFiles ?? self.mediaFiles,
            totalSize: totalSize ?? self.totalSize,
            includesMedia: includesMedia ?? self.includesMedia
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: BackupManifest, rhs: BackupManifest) -> Bool {
        lhs.projectId == rhs.projectId && lhs.backupDate == rhs.backupDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(projectId)
        hasher.combine(backupDate)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case version
        case appVersion
        case appBuildNumber
        case backupDate
        case deviceModel
        case iosVersion
        case projectId
        case projectName
        case projectVersion
        case mediaFiles
        case totalSize
        case includesMedia
    }

    // MARK: - Custom Decoding

    init(
        version: Int,
        appVersion: String,
        appBuildNumber: Int,
        backupDate: Date,
        deviceModel: String,
        iosVersion: String,
        projectId: String,
        projectName: String,
        projectVersion: Int,
        mediaFiles: [BackupMediaEntry],
        totalSize: Int,
        includesMedia: Bool
    ) {
        self.version = version
        self.appVersion = appVersion
        self.appBuildNumber = appBuildNumber
        self.backupDate = backupDate
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
        self.projectId = projectId
        self.projectName = projectName
        self.projectVersion = projectVersion
        self.mediaFiles = mediaFiles
        self.totalSize = totalSize
        self.includesMedia = includesMedia
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        appBuildNumber = try container.decode(Int.self, forKey: .appBuildNumber)

        let dateStr = try container.decode(String.self, forKey: .backupDate)
        backupDate = ISO8601DateFormatter().date(from: dateStr) ?? Date()

        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        iosVersion = try container.decode(String.self, forKey: .iosVersion)
        projectId = try container.decode(String.self, forKey: .projectId)
        projectName = try container.decode(String.self, forKey: .projectName)
        projectVersion = try container.decode(Int.self, forKey: .projectVersion)
        mediaFiles = try container.decode([BackupMediaEntry].self, forKey: .mediaFiles)
        totalSize = try container.decode(Int.self, forKey: .totalSize)
        includesMedia = try container.decode(Bool.self, forKey: .includesMedia)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(appBuildNumber, forKey: .appBuildNumber)
        try container.encode(ISO8601DateFormatter().string(from: backupDate), forKey: .backupDate)
        try container.encode(deviceModel, forKey: .deviceModel)
        try container.encode(iosVersion, forKey: .iosVersion)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(projectVersion, forKey: .projectVersion)
        try container.encode(mediaFiles, forKey: .mediaFiles)
        try container.encode(totalSize, forKey: .totalSize)
        try container.encode(includesMedia, forKey: .includesMedia)
    }
}

// MARK: - BackupValidationResult

/// Result of validating a backup archive.
struct BackupValidationResult: Sendable {

    /// Whether the backup is valid and can be restored.
    let isValid: Bool

    /// The parsed manifest (nil if archive is corrupt).
    let manifest: BackupManifest?

    /// Warning message (e.g., newer version compatibility).
    let warning: String?

    /// Error message if invalid.
    let error: String?

    /// Create a valid result.
    static func valid(_ manifest: BackupManifest) -> BackupValidationResult {
        BackupValidationResult(isValid: true, manifest: manifest, warning: nil, error: nil)
    }

    /// Create a valid result with a warning.
    static func validWithWarning(_ manifest: BackupManifest, warning: String) -> BackupValidationResult {
        BackupValidationResult(isValid: true, manifest: manifest, warning: warning, error: nil)
    }

    /// Create an invalid result.
    static func invalid(_ error: String) -> BackupValidationResult {
        BackupValidationResult(isValid: false, manifest: nil, warning: nil, error: error)
    }
}
