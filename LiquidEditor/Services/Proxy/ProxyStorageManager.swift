// ProxyStorageManager.swift
// LiquidEditor
//
// PP12-11: Observable manager for on-disk proxy storage.
//
// Tracks the current footprint of generated proxy files inside the
// `Application Support/Proxies/` directory and enforces a user-configured
// quota by evicting the oldest proxies (LRU based on file modification
// date) when needed.
//
// The manager is `@Observable` so SwiftUI Settings / Storage views bind
// directly to `currentSizeBytes` and `quotaBytes` without `@Published`.
//
// Architecture:
// - `@MainActor` — all UI consumers bind from the main actor.
// - `@Observable` — fine-grained change tracking.
// - File I/O is wrapped in `Task.detached` where appropriate so the main
//   actor never blocks on disk traversal for large proxy directories.

import Foundation
import Observation

// MARK: - ProxyStorageManager

/// Tracks and enforces the on-disk proxy storage budget.
///
/// ### Quota
/// `quotaBytes` is user-configurable (defaults to 10 GB) and represents the
/// upper bound for the total size of all `.mov` files inside the proxies
/// directory. `availableQuota()` returns `quota − current`.
///
/// ### Eviction
/// `evictLRU(targetBytes:)` deletes the oldest files (by modification date)
/// until the total size drops by at least `targetBytes`. Errors during
/// individual file deletion are swallowed so one bad file cannot abort a
/// cleanup pass.
///
/// ### Thread Safety
/// `@MainActor` isolated. File-system traversal runs off-actor inside
/// `Task.detached` so the main actor is never blocked on I/O.
@MainActor
@Observable
final class ProxyStorageManager {

    // MARK: - Public State (Observable)

    /// Last measured on-disk size of the proxies directory, in bytes.
    /// Updated whenever `currentSize()` is called.
    private(set) var currentSizeBytes: Int64 = 0

    /// User-configured quota in bytes. Defaults to 10 GB. Settings UI
    /// mutates this value directly.
    var quotaBytes: Int64 = ProxyStorageManager.defaultQuotaBytes

    // MARK: - Constants

    /// Default quota if the user has not overridden it: 10 GB.
    static let defaultQuotaBytes: Int64 = 10 * 1_024 * 1_024 * 1_024

    // MARK: - Storage Location

    /// `Application Support/Proxies/` directory URL.
    let storageDirectory: URL

    // MARK: - Init

    /// Creates a manager anchored at the standard Application Support
    /// proxies directory. The directory is created if it doesn't exist.
    init() {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let proxies = base.appendingPathComponent("Proxies", isDirectory: true)
        try? fm.createDirectory(at: proxies, withIntermediateDirectories: true)
        self.storageDirectory = proxies
    }

    // MARK: - Size Query

    /// Returns the total size (in bytes) of every file inside the proxies
    /// directory.
    ///
    /// Runs off-actor via `Task.detached` to avoid blocking UI on large
    /// directories. Updates the `currentSizeBytes` observable before
    /// returning.
    ///
    /// - Returns: Sum of `.totalFileAllocatedSize` (falling back to
    ///   `.fileSize`) for every regular file under `storageDirectory`.
    @discardableResult
    func currentSize() async -> Int64 {
        let dir = storageDirectory
        let size = await Task.detached(priority: .utility) {
            Self.sumFileSizes(in: dir)
        }.value
        self.currentSizeBytes = size
        return size
    }

    /// Available bytes = `quotaBytes − currentSizeBytes`. Can be negative
    /// if the user just lowered the quota; callers should treat negative
    /// values as "over-quota, evict".
    ///
    /// Note: this is a *synchronous* accessor against the last measured
    /// size. Call `currentSize()` first if you need a fresh measurement.
    func availableQuota() -> Int64 {
        quotaBytes - currentSizeBytes
    }

    // MARK: - Eviction

    /// Delete oldest proxies (by modification date) until at least
    /// `targetBytes` of storage is freed.
    ///
    /// - Parameter targetBytes: Minimum number of bytes to free. If the
    ///   directory is already below that, the function returns immediately.
    /// - Throws: Rethrows only if enumeration of the directory fails.
    ///   Individual file-deletion errors are swallowed.
    func evictLRU(targetBytes: Int64) async throws {
        guard targetBytes > 0 else { return }
        let dir = storageDirectory

        let entries = await Task.detached(priority: .utility) {
            Self.lruSortedEntries(in: dir)
        }.value

        var freed: Int64 = 0
        let fm = FileManager.default
        for entry in entries where freed < targetBytes {
            do {
                try fm.removeItem(at: entry.url)
                freed &+= entry.size
            } catch {
                // Swallow per-file errors so one bad file doesn't abort the
                // cleanup pass. Logged via os_log in a full implementation.
                continue
            }
        }

        // Refresh the observable size after eviction.
        _ = await currentSize()
    }

    /// Delete every file in the proxies directory.
    ///
    /// Directory itself is re-created afterwards so subsequent proxy
    /// generation does not need to handle a missing parent.
    func clearAll() async throws {
        let dir = storageDirectory
        try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            ) else {
                return
            }
            for url in contents {
                try? fm.removeItem(at: url)
            }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }.value
        currentSizeBytes = 0
    }

    // MARK: - Off-actor Helpers

    /// Sum the size of every regular file under `dir`. Runs off-actor.
    nonisolated private static func sumFileSizes(in dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ])
            guard values?.isRegularFile == true else { continue }
            let bytes = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            total &+= bytes
        }
        return total
    }

    /// A single proxy file entry with size + modification date.
    private struct Entry: Sendable {
        let url: URL
        let size: Int64
        let modified: Date
    }

    /// Enumerate every regular file under `dir` and return entries sorted
    /// oldest-first. Runs off-actor.
    nonisolated private static func lruSortedEntries(in dir: URL) -> [Entry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [Entry] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ])
            guard values?.isRegularFile == true else { continue }
            let bytes = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? .distantPast
            entries.append(Entry(url: url, size: bytes, modified: date))
        }

        // Oldest first — least-recently-modified is evicted first.
        return entries.sorted { $0.modified < $1.modified }
    }
}
