// MediaAssetRepository.swift
// LiquidEditor
//
// Concrete implementation of MediaAssetRepositoryProtocol.
// Manages a registry of imported media assets with content-hash
// indexing for deduplication and O(1) lookups.

import Foundation
import CryptoKit

// MARK: - ContentHashIndex

/// Persistent index mapping content hashes to asset IDs for deduplication.
private struct ContentHashIndex: Codable, Sendable {
    /// Map from content hash -> array of asset IDs sharing that hash.
    var entries: [String: [String]]

    init(entries: [String: [String]] = [:]) {
        self.entries = entries
    }

    /// Add an asset ID under a content hash.
    mutating func add(assetId: String, contentHash: String) {
        var ids = entries[contentHash, default: []]
        if !ids.contains(assetId) {
            ids.append(assetId)
        }
        entries[contentHash] = ids
    }

    /// Remove an asset ID from a content hash entry.
    mutating func remove(assetId: String, contentHash: String) {
        guard var ids = entries[contentHash] else { return }
        ids.removeAll { $0 == assetId }
        if ids.isEmpty {
            entries.removeValue(forKey: contentHash)
        } else {
            entries[contentHash] = ids
        }
    }

    /// Look up asset IDs by content hash.
    func assetIds(for contentHash: String) -> [String] {
        entries[contentHash] ?? []
    }
}

// MARK: - MediaAssetRepository

/// Actor-isolated repository for managing the media asset registry.
///
/// ## Directory Layout
/// ```
/// ~/Documents/LiquidEditor/Media/
///   registry.json                    – Array of all MediaAsset entries
///   .index/
///     content_hash_index.json        – { contentHash: [assetId] }
/// ```
///
/// ## Caching
/// The full registry and content-hash index are loaded into memory on
/// first access and kept in sync with disk on every mutation.
actor MediaAssetRepository: MediaAssetRepositoryProtocol {

    // MARK: - Constants

    private static let mediaSubpath = "LiquidEditor/Media"
    private static let registryFileName = "registry.json"
    private static let indexDirName = ".index"
    private static let contentHashIndexFileName = "content_hash_index.json"

    // MARK: - Cached State

    /// Base directory for media storage.
    private let baseDirectory: URL

    /// In-memory cache of all assets, keyed by ID.
    private var registryCache: [String: MediaAsset]?

    /// In-memory content-hash index.
    private var hashIndex: ContentHashIndex?

    // MARK: - JSON Coders

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Init

    init() {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        self.baseDirectory = documentsURL
            .appendingPathComponent(Self.mediaSubpath)
    }

    /// Designated initializer for testing with a custom base path.
    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // MARK: - MediaAssetRepositoryProtocol

    func save(_ asset: MediaAsset) async throws {
        var registry = try ensureRegistryLoaded()
        var index = try ensureIndexLoaded()

        // If replacing, remove old hash index entry.
        if let existing = registry[asset.id] {
            index.remove(assetId: existing.id, contentHash: existing.contentHash)
        }

        registry[asset.id] = asset
        index.add(assetId: asset.id, contentHash: asset.contentHash)

        registryCache = registry
        hashIndex = index

        try persistRegistry(registry)
        try persistIndex(index)
    }

    func load(id: String) async throws -> MediaAsset {
        let registry = try ensureRegistryLoaded()
        guard let asset = registry[id] else {
            throw RepositoryError.notFound("MediaAsset \(id)")
        }
        return asset
    }

    func loadByContentHash(_ hash: String) async throws -> [MediaAsset] {
        let registry = try ensureRegistryLoaded()
        let index = try ensureIndexLoaded()
        let ids = index.assetIds(for: hash)
        return ids.compactMap { registry[$0] }
    }

    func listAll() async throws -> [MediaAsset] {
        let registry = try ensureRegistryLoaded()
        return Array(registry.values)
    }

    func listForProject(projectId: String) async throws -> [MediaAsset] {
        // Return all assets; project-level filtering is done by the caller
        // who knows which asset IDs are referenced by the project's clips.
        // A future enhancement could store a per-project asset manifest.
        let registry = try ensureRegistryLoaded()
        return Array(registry.values)
    }

    func delete(id: String) async throws {
        var registry = try ensureRegistryLoaded()
        var index = try ensureIndexLoaded()

        guard let existing = registry.removeValue(forKey: id) else {
            throw RepositoryError.notFound("MediaAsset \(id)")
        }

        index.remove(assetId: existing.id, contentHash: existing.contentHash)

        registryCache = registry
        hashIndex = index

        try persistRegistry(registry)
        try persistIndex(index)
    }

    func exists(id: String) async -> Bool {
        guard let registry = try? ensureRegistryLoaded() else { return false }
        return registry[id] != nil
    }

    func updateLinkStatus(
        assetId: String,
        newRelativePath: String,
        isLinked: Bool
    ) async throws {
        var registry = try ensureRegistryLoaded()

        guard let existing = registry[assetId] else {
            throw RepositoryError.notFound("MediaAsset \(assetId)")
        }

        let updated: MediaAsset
        if isLinked {
            updated = existing.markLinked(newRelativePath)
        } else {
            updated = existing.markUnlinked()
        }

        registry[assetId] = updated
        registryCache = registry

        try persistRegistry(registry)
    }

    func findUnlinkedAssets() async throws -> [MediaAsset] {
        let registry = try ensureRegistryLoaded()
        return registry.values.filter { !$0.isLinked }
    }

    // MARK: - Private Helpers

    /// Lazily loads and caches the registry from disk.
    private func ensureRegistryLoaded() throws -> [String: MediaAsset] {
        if let cached = registryCache { return cached }

        try ensureDirectory(at: baseDirectory)

        let registryURL = baseDirectory.appendingPathComponent(Self.registryFileName)

        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            // First use: empty registry.
            let empty: [String: MediaAsset] = [:]
            registryCache = empty
            return empty
        }

        let data: Data
        do {
            data = try Data(contentsOf: registryURL)
        } catch {
            throw RepositoryError.ioError(
                "Failed to read media registry: \(error.localizedDescription)"
            )
        }

        let assets: [MediaAsset]
        do {
            assets = try decoder.decode([MediaAsset].self, from: data)
        } catch {
            throw RepositoryError.decodingFailed(
                "Failed to decode media registry: \(error.localizedDescription)"
            )
        }

        let registry = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        registryCache = registry
        return registry
    }

    /// Lazily loads and caches the content-hash index from disk.
    private func ensureIndexLoaded() throws -> ContentHashIndex {
        if let cached = hashIndex { return cached }

        let indexDir = baseDirectory.appendingPathComponent(Self.indexDirName)
        try ensureDirectory(at: indexDir)

        let indexURL = indexDir.appendingPathComponent(Self.contentHashIndexFileName)

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            // First use or missing index: rebuild from registry.
            let index = rebuildIndex()
            hashIndex = index
            return index
        }

        let data: Data
        do {
            data = try Data(contentsOf: indexURL)
        } catch {
            // Fall back to rebuilding if read fails.
            let index = rebuildIndex()
            hashIndex = index
            return index
        }

        do {
            let index = try decoder.decode(ContentHashIndex.self, from: data)
            hashIndex = index
            return index
        } catch {
            // Rebuild on decode failure.
            let index = rebuildIndex()
            hashIndex = index
            return index
        }
    }

    /// Rebuilds the content-hash index from the current in-memory registry.
    private func rebuildIndex() -> ContentHashIndex {
        var index = ContentHashIndex()
        if let registry = registryCache {
            for asset in registry.values {
                index.add(assetId: asset.id, contentHash: asset.contentHash)
            }
        }
        return index
    }

    /// Persists the registry dictionary to disk as a JSON array.
    private func persistRegistry(_ registry: [String: MediaAsset]) throws {
        let assets = Array(registry.values)
        let data: Data
        do {
            data = try encoder.encode(assets)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode media registry: \(error.localizedDescription)"
            )
        }

        let registryURL = baseDirectory.appendingPathComponent(Self.registryFileName)
        try writeData(data, to: registryURL)
    }

    /// Persists the content-hash index to disk.
    private func persistIndex(_ index: ContentHashIndex) throws {
        let indexDir = baseDirectory.appendingPathComponent(Self.indexDirName)
        try ensureDirectory(at: indexDir)

        let data: Data
        do {
            data = try encoder.encode(index)
        } catch {
            throw RepositoryError.encodingFailed(
                "Failed to encode content hash index: \(error.localizedDescription)"
            )
        }

        let indexURL = indexDir.appendingPathComponent(Self.contentHashIndexFileName)
        try writeData(data, to: indexURL)
    }

    /// Ensures a directory exists, creating it (and intermediates) if needed.
    private func ensureDirectory(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
            } catch {
                throw RepositoryError.ioError(
                    "Failed to create directory at \(url.path): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Atomically writes data to a file URL.
    private func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RepositoryError.ioError(
                "Failed to write file at \(url.path): \(error.localizedDescription)"
            )
        }
    }
}
