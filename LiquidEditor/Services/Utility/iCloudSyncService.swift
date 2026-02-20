// iCloudSyncService.swift
// LiquidEditor
//
// Abstract interface for iCloud sync operations. Current implementation
// returns "not available" for all operations. The interface is designed
// for a future native implementation using NSUbiquitousKeyValueStore
// and CloudKit.

import Foundation

// MARK: - ICloudSyncStatus

/// Current iCloud sync status of a project.
///
/// Named `ICloudSyncStatus` to avoid collision with
/// `SyncStatus` in `Models/Project/SyncStatus.swift`.
enum ICloudSyncStatus: String, CaseIterable, Codable, Sendable {
    /// Project exists only locally (not synced).
    case localOnly

    /// Project is fully synced with iCloud.
    case synced

    /// Project has local changes not yet uploaded.
    case pendingUpload

    /// Project has remote changes not yet downloaded.
    case pendingDownload

    /// Sync is currently in progress.
    case syncing

    /// Sync conflict detected (both local and remote changes).
    case conflict

    /// Sync failed with an error.
    case error

    /// iCloud sync is not available on this device.
    case unavailable
}

// MARK: - ConflictResolution

/// Conflict resolution strategy.
enum ConflictResolution: String, CaseIterable, Codable, Sendable {
    /// Keep the local version.
    case keepLocal

    /// Keep the remote (iCloud) version.
    case keepRemote

    /// Keep both (duplicate the project).
    case keepBoth

    /// Merge changes (requires manual review).
    case merge
}

// MARK: - SyncConflict

/// Information about a sync conflict.
struct SyncConflict: Equatable, Sendable {

    /// Project identifier.
    let projectId: String

    /// Project name.
    let projectName: String

    /// When the local version was last modified.
    let localModifiedAt: Date

    /// When the remote version was last modified.
    let remoteModifiedAt: Date

    /// Size of the local version in bytes.
    let localSize: Int64

    /// Size of the remote version in bytes.
    let remoteSize: Int64
}

// MARK: - SyncResult

/// Result of a sync operation.
struct SyncResult: Equatable, Sendable {

    /// Whether the operation succeeded.
    let success: Bool

    /// Error message if the operation failed.
    let error: String?

    /// Number of projects synced.
    let syncedCount: Int

    /// Number of conflicts detected.
    let conflictCount: Int

    /// Convenience for a successful result.
    static func success(syncedCount: Int = 0, conflictCount: Int = 0) -> SyncResult {
        SyncResult(success: true, error: nil, syncedCount: syncedCount, conflictCount: conflictCount)
    }

    /// Convenience for a failure result.
    static func failure(_ error: String) -> SyncResult {
        SyncResult(success: false, error: error, syncedCount: 0, conflictCount: 0)
    }

    /// Result for when iCloud sync is not available.
    static let unavailable = SyncResult.failure(
        "iCloud sync is not available. Ensure you are signed into iCloud and have sufficient storage."
    )
}

// MARK: - ICloudSyncServiceProtocol

/// Abstract interface for iCloud sync operations.
///
/// Defines the full API surface for syncing projects across devices.
/// The current implementation ``ICloudSyncServiceStub`` returns
/// "not available" for all operations.
protocol ICloudSyncServiceProtocol: Sendable {

    /// Whether iCloud sync is available on this device.
    func isAvailable() async -> Bool

    /// Get the current sync status of a specific project.
    func getSyncStatus(projectId: String) async -> ICloudSyncStatus

    /// Get sync status for all projects.
    func getAllSyncStatuses() async -> [String: ICloudSyncStatus]

    /// Sync a single project to iCloud.
    func syncProject(projectId: String) async -> SyncResult

    /// Sync all projects that have pending changes.
    func syncAll() async -> SyncResult

    /// Download a project from iCloud that exists only remotely.
    func downloadProject(projectId: String) async -> SyncResult

    /// Resolve a sync conflict for a specific project.
    func resolveConflict(projectId: String, resolution: ConflictResolution) async -> SyncResult

    /// Get all unresolved sync conflicts.
    func getConflicts() async -> [SyncConflict]

    /// Enable or disable automatic sync.
    func setAutoSyncEnabled(_ enabled: Bool) async

    /// Whether automatic sync is currently enabled.
    func isAutoSyncEnabled() async -> Bool

    /// Get the last time a successful sync occurred.
    func lastSyncTime() async -> Date?

    /// Force a full re-sync of all projects.
    func forceFullSync() async -> SyncResult

    /// Remove a project from iCloud (keep local copy).
    func removeFromCloud(projectId: String) async -> SyncResult
}

// MARK: - ICloudSyncServiceStub

/// Stub implementation of ``ICloudSyncServiceProtocol``.
///
/// Returns "not available" for all operations. This is the current
/// implementation until native iCloud integration is built via
/// NSUbiquitousKeyValueStore and CloudKit.
final class ICloudSyncServiceStub: ICloudSyncServiceProtocol, @unchecked Sendable {

    // MARK: - Singleton

    static let shared = ICloudSyncServiceStub()
    private init() {}

    // MARK: - ICloudSyncServiceProtocol

    func isAvailable() async -> Bool { false }

    func getSyncStatus(projectId: String) async -> ICloudSyncStatus { .unavailable }

    func getAllSyncStatuses() async -> [String: ICloudSyncStatus] { [:] }

    func syncProject(projectId: String) async -> SyncResult { .unavailable }

    func syncAll() async -> SyncResult { .unavailable }

    func downloadProject(projectId: String) async -> SyncResult { .unavailable }

    func resolveConflict(projectId: String, resolution: ConflictResolution) async -> SyncResult {
        .unavailable
    }

    func getConflicts() async -> [SyncConflict] { [] }

    func setAutoSyncEnabled(_ enabled: Bool) async {
        // No-op: iCloud sync not available.
    }

    func isAutoSyncEnabled() async -> Bool { false }

    func lastSyncTime() async -> Date? { nil }

    func forceFullSync() async -> SyncResult { .unavailable }

    func removeFromCloud(projectId: String) async -> SyncResult { .unavailable }
}
