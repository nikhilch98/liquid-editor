// MediaRelinkService.swift
// LiquidEditor
//
// F6-16: Media relink flow — detect missing source files for a
// project, then either auto-relink (by walking a set of search roots
// looking for a file with matching filename + size) or manually
// relink (user-supplied URL).
//
// The service is intentionally lightweight — it does not mutate the
// canonical project storage. Callers are responsible for taking the
// returned URL and updating the project's MediaAsset records.

import Foundation
import Observation

// MARK: - MediaRelinkError

enum MediaRelinkError: Error, Sendable, Equatable {
    /// Provided replacement URL does not point to an existing file.
    case replacementMissing
    /// Replacement file size mismatches the expected size.
    case sizeMismatch
}

// MARK: - MediaRelinkService

/// Main-actor @Observable helper for the media relink flow.
@MainActor
@Observable
final class MediaRelinkService {

    // MARK: - Nested Types

    /// Descriptor of a media asset that could not be resolved on disk.
    struct MissingAsset: Identifiable, Sendable, Equatable, Hashable {
        /// Stable unique identifier.
        let id: UUID

        /// The URL the asset was expected to live at.
        let originalURL: URL

        /// Duration of the asset in seconds, for filename-agnostic
        /// disambiguation (e.g. "a 0.5s clip is probably not a 42m
        /// long file even if names match").
        let expectedDuration: TimeInterval

        /// Expected on-disk size in bytes — primary relinking signal.
        let expectedSize: Int64

        init(
            id: UUID = UUID(),
            originalURL: URL,
            expectedDuration: TimeInterval,
            expectedSize: Int64
        ) {
            self.id = id
            self.originalURL = originalURL
            self.expectedDuration = expectedDuration
            self.expectedSize = expectedSize
        }
    }

    // MARK: - Observable State

    /// Most-recent scan results. Empty after a successful scan when the
    /// project had no missing assets.
    private(set) var lastMissingAssets: [MissingAsset] = []

    // MARK: - Dependencies

    @ObservationIgnored
    private let fileManager: FileManager

    // MARK: - Init

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Scan `project`'s media assets and return those whose underlying
    /// file is missing from disk.
    ///
    /// - Parameter project: the project whose media to validate.
    /// - Returns: array of missing assets. Empty when everything links.
    ///
    /// - Note: The canonical `Project` / `ProjectMetadata` models do
    ///   not currently embed a fully-typed `[MediaAsset]`, so the scan
    ///   returns empty until the caller wires in a media list via
    ///   `scan(assets:)`. Kept as a stable public entry point.
    @discardableResult
    func scan(project: ProjectMetadata) -> [MissingAsset] {
        // With only metadata, there are no concrete file paths to
        // validate. Real callers should prefer `scan(assets:)`.
        lastMissingAssets = []
        return []
    }

    /// Scan a typed list of media assets and return those missing.
    ///
    /// - Parameter assets: asset descriptors pulled from the project
    ///   document.
    /// - Returns: array of missing assets.
    @discardableResult
    func scan(assets: [MediaAsset]) -> [MissingAsset] {
        let missing = assets.compactMap { asset -> MissingAsset? in
            guard let url = resolvedURL(for: asset) else {
                return MissingAsset(
                    originalURL: URL(fileURLWithPath: asset.relativePath),
                    expectedDuration: Double(asset.durationMicroseconds) / 1_000_000.0,
                    expectedSize: Int64(asset.fileSize)
                )
            }

            if fileManager.fileExists(atPath: url.path) {
                return nil
            }

            return MissingAsset(
                originalURL: url,
                expectedDuration: Double(asset.durationMicroseconds) / 1_000_000.0,
                expectedSize: Int64(asset.fileSize)
            )
        }

        lastMissingAssets = missing
        return missing
    }

    /// Attempt to auto-relink a missing asset by walking one or more
    /// search roots and matching on filename + file size.
    ///
    /// - Parameters:
    ///   - missing: asset to relink.
    ///   - searchRoots: directories to search (typically the user's
    ///     Photos export folder, Files app provider folders, etc.).
    /// - Returns: the URL of a matching file, or `nil` if nothing
    ///   plausible was found.
    func attemptAutoRelink(
        missing: MissingAsset,
        searchRoots: [URL]
    ) async -> URL? {
        let targetName = missing.originalURL.lastPathComponent
        let targetSize = missing.expectedSize
        let roots = searchRoots

        // Use a detached task with only Sendable captures to satisfy
        // Swift 6 strict concurrency. `FileManager.default` is safe
        // to access from any thread.
        return await Task.detached { () -> URL? in
            for root in roots {
                if let match = Self.searchForMatch(
                    in: root,
                    filename: targetName,
                    expectedSize: targetSize
                ) {
                    return match
                }
            }
            return nil
        }.value
    }

    /// Replace a missing asset's resolved URL with a user-supplied one.
    ///
    /// Throws if the replacement doesn't exist or has a wildly
    /// different file size (guarding against corrupt substitutions).
    ///
    /// - Parameters:
    ///   - missing: descriptor of the missing asset.
    ///   - newURL: replacement URL chosen by the user.
    func manualRelink(missing: MissingAsset, to newURL: URL) throws {
        guard fileManager.fileExists(atPath: newURL.path) else {
            throw MediaRelinkError.replacementMissing
        }

        // Only enforce size check when we have a known expected size.
        if missing.expectedSize > 0 {
            if let attrs = try? fileManager.attributesOfItem(atPath: newURL.path),
               let size = attrs[.size] as? NSNumber {
                // Allow 5% tolerance for minor container differences.
                let tolerance = max(1024, Int64(Double(missing.expectedSize) * 0.05))
                if abs(size.int64Value - missing.expectedSize) > tolerance {
                    throw MediaRelinkError.sizeMismatch
                }
            }
        }

        // Remove the resolved entry from the missing list; caller is
        // responsible for writing the replacement URL back into the
        // project document.
        lastMissingAssets.removeAll { $0.id == missing.id }
    }

    // MARK: - Helpers

    private func resolvedURL(for asset: MediaAsset) -> URL? {
        if let absolute = asset.lastKnownAbsolutePath, !absolute.isEmpty {
            return URL(fileURLWithPath: absolute)
        }
        if !asset.relativePath.isEmpty {
            return URL(fileURLWithPath: asset.relativePath)
        }
        return nil
    }

    /// Depth-first walk of `root` looking for a file with the exact
    /// same last-path-component and (when known) matching size.
    ///
    /// Uses `FileManager.default` (safe to access from any thread).
    nonisolated private static func searchForMatch(
        in root: URL,
        filename: String,
        expectedSize: Int64
    ) -> URL? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return nil
        }

        for case let candidate as URL in enumerator {
            guard candidate.lastPathComponent == filename else { continue }

            let values = try? candidate.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true else { continue }

            if expectedSize <= 0 {
                return candidate
            }

            if let size = values?.fileSize, Int64(size) == expectedSize {
                return candidate
            }
        }

        return nil
    }
}
