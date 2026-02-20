// SyncStatus.swift
// LiquidEditor
//
// iCloud sync status models.

import Foundation

// MARK: - SyncStatus

/// iCloud sync status for a project.
enum SyncStatus: String, Codable, CaseIterable, Sendable {
    /// Not synced, local only.
    case local
    /// Synced and up to date.
    case synced
    /// Local changes pending upload.
    case pendingUpload
    /// Remote changes pending download.
    case pendingDownload
    /// Conflict detected, needs resolution.
    case conflict
    /// Sync error occurred.
    case error
    /// Currently syncing.
    case syncing

    var displayName: String {
        switch self {
        case .local: return "Local only"
        case .synced: return "Synced"
        case .pendingUpload: return "Uploading..."
        case .pendingDownload: return "Downloading..."
        case .conflict: return "Conflict"
        case .error: return "Sync error"
        case .syncing: return "Syncing..."
        }
    }

    /// Whether sync is in an active/pending state.
    var isActive: Bool {
        self == .syncing || self == .pendingUpload || self == .pendingDownload
    }
}

// MARK: - SyncOperationType

/// Type of sync operation.
enum SyncOperationType: String, Codable, CaseIterable, Sendable {
    case upload
    case download
    case delete
}

// MARK: - SyncOperation

/// A queued sync operation for offline support.
struct SyncOperation: Codable, Equatable, Hashable, Sendable {

    /// Unique operation ID.
    let id: String

    /// Operation type.
    let type: SyncOperationType

    /// Project this operation affects.
    let projectId: String

    /// When the operation was queued.
    let queuedAt: Date

    /// Number of retry attempts so far.
    let retryCount: Int

    /// Last error message (nil if no error).
    let error: String?

    /// Maximum retry attempts before giving up.
    static let maxRetries: Int = 5

    // MARK: - Init with defaults

    init(
        id: String,
        type: SyncOperationType,
        projectId: String,
        queuedAt: Date,
        retryCount: Int = 0,
        error: String? = nil
    ) {
        self.id = id
        self.type = type
        self.projectId = projectId
        self.queuedAt = queuedAt
        self.retryCount = retryCount
        self.error = error
    }

    /// Whether this operation can be retried.
    var canRetry: Bool { retryCount < Self.maxRetries }

    /// Create a copy with incremented retry count.
    func withRetry(errorMessage: String?) -> SyncOperation {
        SyncOperation(
            id: id,
            type: type,
            projectId: projectId,
            queuedAt: queuedAt,
            retryCount: retryCount + 1,
            error: errorMessage
        )
    }

    // MARK: - with(...)

    func with(
        id: String? = nil,
        type: SyncOperationType? = nil,
        projectId: String? = nil,
        queuedAt: Date? = nil,
        retryCount: Int? = nil,
        error: String?? = nil
    ) -> SyncOperation {
        SyncOperation(
            id: id ?? self.id,
            type: type ?? self.type,
            projectId: projectId ?? self.projectId,
            queuedAt: queuedAt ?? self.queuedAt,
            retryCount: retryCount ?? self.retryCount,
            error: error ?? self.error
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: SyncOperation, rhs: SyncOperation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case projectId
        case queuedAt
        case retryCount
        case error
    }

    // MARK: - Custom Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)

        let typeStr = try container.decode(String.self, forKey: .type)
        type = SyncOperationType(rawValue: typeStr) ?? .upload

        projectId = try container.decode(String.self, forKey: .projectId)

        let queuedAtStr = try container.decode(String.self, forKey: .queuedAt)
        queuedAt = ISO8601DateFormatter().date(from: queuedAtStr) ?? Date()

        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }

    // MARK: - Custom Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(ISO8601DateFormatter().string(from: queuedAt), forKey: .queuedAt)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(error, forKey: .error)
    }
}
