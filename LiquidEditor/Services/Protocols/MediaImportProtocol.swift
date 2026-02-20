// MediaImportProtocol.swift
// LiquidEditor
//
// Protocol for media import operations.
// Enables dependency injection and testability.

import Foundation

// MARK: - MediaImportProtocol

/// Protocol for importing media from various sources.
///
/// Implementations handle Photos library access, file picker,
/// metadata extraction, and thumbnail generation.
///
/// References:
/// - `MediaType` from Models/Media/MediaAsset.swift
/// - `MediaAsset` from Models/Media/MediaAsset.swift
protocol MediaImportProtocol: Sendable {
    /// Import media from the Photos library via PHPicker.
    ///
    /// Presents the system photo picker and copies selected items
    /// to the project's media directory.
    ///
    /// - Parameters:
    ///   - mediaTypes: Filter for media types to show.
    ///   - selectionLimit: Maximum number of items the user can select (0 = unlimited).
    /// - Returns: Array of imported media descriptors.
    /// - Throws: If the user cancels or import fails.
    func importFromPhotos(
        mediaTypes: [MediaType],
        selectionLimit: Int
    ) async throws -> [ImportedMedia]

    /// Import media from the file system via UIDocumentPicker.
    ///
    /// Presents the system file picker and copies selected items
    /// to the project's media directory.
    ///
    /// - Parameter allowsMultiple: Whether to allow selecting multiple files.
    /// - Returns: Array of imported media descriptors.
    /// - Throws: If the user cancels or import fails.
    func importFromFiles(
        allowsMultiple: Bool
    ) async throws -> [ImportedMedia]

    /// Extract metadata from a media file.
    ///
    /// Reads video/audio/image metadata using AVAsset and CGImageSource.
    ///
    /// - Parameter url: URL of the media file.
    /// - Returns: Extracted metadata.
    /// - Throws: If the file cannot be read.
    func extractMetadata(url: URL) async throws -> ImportedMediaMetadata

    /// Generate a thumbnail image for a media file.
    ///
    /// For video, captures a frame at the midpoint. For images, creates
    /// a scaled-down version.
    ///
    /// - Parameters:
    ///   - url: URL of the media file.
    ///   - size: Target thumbnail size in points.
    /// - Returns: JPEG-encoded thumbnail data.
    /// - Throws: If the file cannot be read or thumbnail generation fails.
    func generateThumbnail(
        url: URL,
        size: CGSize
    ) async throws -> Data

    /// Get device storage information.
    ///
    /// - Returns: Storage usage details.
    func getStorageInfo() async throws -> StorageInfo
}

// MARK: - ImportedMediaMetadata

/// Metadata extracted from an imported media file.
///
/// Named differently from `MediaMetadata` to avoid collision
/// with any existing types. Contains the raw probe data before
/// creating a full `MediaAsset`.
struct ImportedMediaMetadata: Sendable, Codable {
    /// Duration in microseconds (nil for images).
    let duration: TimeMicros?

    /// Width in pixels (nil for audio-only).
    let width: Int?

    /// Height in pixels (nil for audio-only).
    let height: Int?

    /// Frame rate (nil for images/audio).
    let frameRate: Double?

    /// Video codec identifier (e.g., "h264", "hevc").
    let codec: String?

    /// File size in bytes.
    let fileSize: Int64

    /// Original creation date from file metadata.
    let creationDate: Date?
}

// MARK: - StorageInfo

/// Device storage information.
struct StorageInfo: Sendable {
    /// Total device storage in bytes.
    let totalBytes: Int64

    /// Available (free) storage in bytes.
    let availableBytes: Int64

    /// Storage used by this app's media files in bytes.
    let mediaUsageBytes: Int64
}
