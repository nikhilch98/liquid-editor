// MusicLibraryService.swift
// LiquidEditor
//
// Provides access to the device music library via MediaPlayer framework.
// Supports browsing, importing tracks, and audio preview.

import AVFoundation
import MediaPlayer

// MARK: - MusicLibraryError

/// Errors thrown by MusicLibraryService operations.
enum MusicLibraryError: Error, LocalizedError, Sendable {
    case authorizationDenied
    case authorizationRestricted
    case invalidAssetURL(String)
    case exportSessionCreationFailed
    case exportFailed(String)
    case playbackFailed(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Music library access was denied. Please enable in Settings."
        case .authorizationRestricted:
            "Music library access is restricted on this device."
        case .invalidAssetURL(let url):
            "Invalid asset URL: \(url)"
        case .exportSessionCreationFailed:
            "Failed to create audio export session"
        case .exportFailed(let reason):
            "Audio export failed: \(reason)"
        case .playbackFailed(let reason):
            "Audio playback failed: \(reason)"
        case .fileNotFound(let path):
            "Audio file not found at: \(path)"
        }
    }
}

// MARK: - MusicTrackInfo

/// Metadata for a music track from the device library.
struct MusicTrackInfo: Sendable {
    /// Track title.
    let title: String

    /// Artist name.
    let artist: String

    /// Album name, if available.
    let album: String?

    /// Duration in microseconds.
    let durationMicros: Int64

    /// Asset URL for importing the track.
    let assetURL: String?
}

// MARK: - MusicLibraryService

/// Service for accessing the device music library and importing tracks.
///
/// Provides an async API for:
/// - Checking and requesting music library authorization
/// - Querying tracks from the device library
/// - Importing tracks to the app's document directory
/// - Previewing audio files
///
/// Uses `actor` isolation for I/O-bound operations (importing,
/// file management). Preview playback is actor-isolated since
/// all access occurs through actor methods.
actor MusicLibraryService {

    // MARK: - Properties

    /// Audio player for preview playback.
    /// Actor-isolated -- all access goes through actor methods.
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Authorization

    /// Check current music library authorization status.
    ///
    /// - Returns: The current authorization status.
    nonisolated func authorizationStatus() -> MPMediaLibraryAuthorizationStatus {
        MPMediaLibrary.authorizationStatus()
    }

    /// Request music library access.
    ///
    /// - Returns: The resulting authorization status.
    /// - Throws: `MusicLibraryError` if access is denied or restricted.
    func requestAuthorization() async throws -> MPMediaLibraryAuthorizationStatus {
        let status = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        switch status {
        case .denied:
            throw MusicLibraryError.authorizationDenied
        case .restricted:
            throw MusicLibraryError.authorizationRestricted
        case .authorized, .notDetermined:
            return status
        @unknown default:
            return status
        }
    }

    // MARK: - Library Browsing

    /// Query tracks from the device music library.
    ///
    /// Returns metadata for all music items on the device,
    /// optionally filtered by a search term.
    ///
    /// - Parameter searchTerm: Optional search string to filter results
    ///   by title or artist.
    /// - Returns: Array of `MusicTrackInfo` for matching tracks.
    func queryTracks(searchTerm: String? = nil) -> [MusicTrackInfo] {
        let query = MPMediaQuery.songs()

        if let searchTerm, !searchTerm.isEmpty {
            let titlePredicate = MPMediaPropertyPredicate(
                value: searchTerm,
                forProperty: MPMediaItemPropertyTitle,
                comparisonType: .contains
            )
            query.addFilterPredicate(titlePredicate)
        }

        guard let items = query.items else { return [] }

        return items.map { item in
            MusicTrackInfo(
                title: item.title ?? "Unknown",
                artist: item.artist ?? "Unknown Artist",
                album: item.albumTitle,
                durationMicros: Int64(item.playbackDuration * 1_000_000),
                assetURL: item.assetURL?.absoluteString
            )
        }
    }

    // MARK: - Track Import

    /// Import a music track to the app's documents directory.
    ///
    /// Exports the track as M4A using `AVAssetExportSession`.
    ///
    /// - Parameters:
    ///   - assetURLString: The asset URL string from `MusicTrackInfo`.
    ///   - outputPath: Destination file path for the imported track.
    /// - Returns: The output file path on success.
    /// - Throws: `MusicLibraryError` on failure.
    func importTrack(
        assetURLString: String,
        outputPath: String
    ) async throws -> String {
        guard let url = URL(string: assetURLString) else {
            throw MusicLibraryError.invalidAssetURL(assetURLString)
        }

        let asset = AVURLAsset(url: url)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MusicLibraryError.exportSessionCreationFailed
        }

        let outputURL = URL(fileURLWithPath: outputPath)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputPath
        case .failed:
            throw MusicLibraryError.exportFailed(
                exportSession.error?.localizedDescription ?? "Unknown error"
            )
        case .cancelled:
            throw MusicLibraryError.exportFailed("Export was cancelled")
        default:
            throw MusicLibraryError.exportFailed(
                "Unexpected export status: \(exportSession.status.rawValue)"
            )
        }
    }

    // MARK: - Audio Preview

    /// Preview an audio file.
    ///
    /// Stops any currently playing preview and starts playback
    /// of the specified file.
    ///
    /// - Parameter assetPath: File path or bundle resource name.
    /// - Throws: `MusicLibraryError.playbackFailed` on failure.
    func previewAudio(assetPath: String) throws {
        stopPreview()

        let url: URL

        // Try bundle resource first, then file path
        if let bundleURL = Bundle.main.url(forResource: assetPath, withExtension: nil) {
            url = bundleURL
        } else {
            let fileURL = URL(fileURLWithPath: assetPath)
            guard FileManager.default.fileExists(atPath: assetPath) else {
                throw MusicLibraryError.fileNotFound(assetPath)
            }
            url = fileURL
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.play()
        } catch {
            throw MusicLibraryError.playbackFailed(error.localizedDescription)
        }
    }

    /// Stop any currently playing audio preview.
    func stopPreview() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// Whether a preview is currently playing.
    var isPreviewPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }
}
