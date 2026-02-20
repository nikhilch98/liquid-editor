// MediaAssetRepositoryProtocol.swift
// LiquidEditor
//
// Protocol for media asset registry operations.
// Enables dependency injection and testability for asset storage.

import Foundation

// MARK: - MediaAssetRepositoryProtocol

/// Protocol for persisting and querying the media asset registry.
///
/// Implementations manage the index of imported media files (video, image,
/// audio). Assets are identified by UUID and can be deduplicated by content
/// hash. Link status tracking supports offline/relink workflows.
///
/// All I/O methods are async and throw `RepositoryError` on failure.
///
/// References:
/// - `MediaAsset` from Models/Media/MediaAsset.swift
/// - `MediaType` from Models/Media/MediaAsset.swift
/// - `TimeMicros` from Models/Timeline/TimeTypes.swift
/// - `RepositoryError` from Repositories/RepositoryError.swift
protocol MediaAssetRepositoryProtocol: Sendable {

    /// Persist a media asset to the registry.
    ///
    /// Creates a new record or overwrites an existing one with the same ID.
    ///
    /// - Parameter asset: The media asset to save.
    /// - Throws: `RepositoryError.encodingFailed` if serialization fails,
    ///   `RepositoryError.ioError` if the write fails.
    func save(_ asset: MediaAsset) async throws

    /// Load a media asset by its identifier.
    ///
    /// - Parameter id: The asset's unique identifier (UUID).
    /// - Returns: The loaded media asset.
    /// - Throws: `RepositoryError.notFound` if no asset with that ID exists,
    ///   `RepositoryError.decodingFailed` if stored data is unreadable.
    func load(id: String) async throws -> MediaAsset

    /// Find all assets with the given content hash.
    ///
    /// Used for deduplication: before importing a new file, check if an
    /// asset with the same hash already exists.
    ///
    /// - Parameter hash: SHA-256 content hash to search for.
    /// - Returns: Array of matching assets (may be empty).
    /// - Throws: `RepositoryError.ioError` if the registry cannot be read.
    func loadByContentHash(_ hash: String) async throws -> [MediaAsset]

    /// List all media assets in the registry.
    ///
    /// - Returns: Array of all registered media assets.
    /// - Throws: `RepositoryError.ioError` if the registry cannot be read.
    func listAll() async throws -> [MediaAsset]

    /// List media assets associated with a specific project.
    ///
    /// Returns assets that are referenced by clips in the given project.
    ///
    /// - Parameter projectId: The project's unique identifier.
    /// - Returns: Array of media assets used by the project.
    /// - Throws: `RepositoryError.ioError` if the registry cannot be read.
    func listForProject(projectId: String) async throws -> [MediaAsset]

    /// Delete a media asset from the registry.
    ///
    /// Removes the registry entry. Callers are responsible for deleting
    /// the underlying file if no other projects reference it.
    ///
    /// - Parameter id: The asset's unique identifier.
    /// - Throws: `RepositoryError.notFound` if no asset with that ID exists,
    ///   `RepositoryError.ioError` if deletion fails.
    func delete(id: String) async throws

    /// Check whether an asset with the given ID exists in the registry.
    ///
    /// - Parameter id: The asset's unique identifier.
    /// - Returns: `true` if the asset exists, `false` otherwise.
    func exists(id: String) async -> Bool

    /// Update the link status and relative path for an asset.
    ///
    /// Used when a previously missing file is relocated or when a file
    /// becomes inaccessible.
    ///
    /// - Parameters:
    ///   - assetId: The asset's unique identifier.
    ///   - newRelativePath: The updated relative path.
    ///   - isLinked: Whether the file is currently accessible.
    /// - Throws: `RepositoryError.notFound` if no asset with that ID exists.
    func updateLinkStatus(assetId: String, newRelativePath: String, isLinked: Bool) async throws

    /// Find all assets whose files are currently unlinked (inaccessible).
    ///
    /// Used by the relink workflow to show the user which media files
    /// need to be relocated.
    ///
    /// - Returns: Array of unlinked media assets.
    /// - Throws: `RepositoryError.ioError` if the registry cannot be read.
    func findUnlinkedAssets() async throws -> [MediaAsset]
}
