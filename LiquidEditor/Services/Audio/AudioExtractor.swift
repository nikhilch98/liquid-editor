// AudioExtractor.swift
// LiquidEditor
//
// TD8-4: Extract audio from a video clip to a standalone .m4a file.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.
//
// Uses AVAssetExportSession with `.m4a` (AppleM4A) to produce an
// AAC-encoded audio track in the system temp directory. Surfaces a
// sync convenience wrapper for SwiftUI button taps so the Audio tab
// can invoke the extract action without composing its own Task.
//
// Threading:
// - `extractAudio(from:)` is `nonisolated` and async — safe to call
//   from any actor. Work is delegated to AVAssetExportSession which
//   runs off the main actor internally.
// - `extract(from:completion:)` is a main-actor convenience that
//   wraps the async call in a Task and hops the completion back to
//   the main actor.

import AVFoundation
import Foundation

// MARK: - AudioExtractor

/// Extracts an audio-only `.m4a` track from a video URL.
///
/// Usage from a SwiftUI view:
/// ```swift
/// Button("Extract audio") {
///     AudioExtractor.extract(from: clip.url) { result in
///         switch result {
///         case .success(let url): viewModel.addAudioClip(from: url)
///         case .failure(let error): viewModel.showError(error)
///         }
///     }
/// }
/// ```
@MainActor
enum AudioExtractor {

    // MARK: - Errors

    /// Errors surfaced by ``extractAudio(from:)``.
    enum ExtractError: LocalizedError {
        /// The export session could not be created (preset unsupported).
        case exportSessionUnavailable
        /// The export finished in a non-`.completed` state.
        case exportFailed(status: AVAssetExportSession.Status, underlying: Error?)
        /// The source asset contains no audio tracks.
        case noAudioTrack

        var errorDescription: String? {
            switch self {
            case .exportSessionUnavailable:
                return "Audio export session could not be created."
            case .exportFailed(let status, let underlying):
                if let underlying { return "Audio export failed (\(status.rawValue)): \(underlying.localizedDescription)" }
                return "Audio export failed with status \(status.rawValue)."
            case .noAudioTrack:
                return "The selected video does not contain an audio track."
            }
        }
    }

    // MARK: - Async API

    /// Extract the first audio track of `videoURL` into a temp-dir `.m4a`.
    ///
    /// - Parameter videoURL: File URL to a video asset readable by AVFoundation.
    /// - Returns: URL of the freshly-written `.m4a` file in the system temp dir.
    /// - Throws: ``ExtractError`` on missing tracks / export failure.
    nonisolated static func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)

        // Verify the source actually has an audio track before we spin up the
        // export session — otherwise AVAssetExportSession emits a vague failure.
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw ExtractError.noAudioTrack
        }

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExtractError.exportSessionUnavailable
        }

        let outputURL = makeOutputURL(for: videoURL)

        session.outputFileType = .m4a
        session.outputURL = outputURL
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        switch session.status {
        case .completed:
            return outputURL
        default:
            throw ExtractError.exportFailed(status: session.status, underlying: session.error)
        }
    }

    // MARK: - Sync-style SwiftUI convenience

    /// Fire-and-forget wrapper for button taps. Performs the async extraction
    /// off the main actor and hops the result back for UI updates.
    ///
    /// - Parameters:
    ///   - videoURL: Source video file.
    ///   - completion: Called on the main actor with the written URL or error.
    static func extract(
        from videoURL: URL,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        Task.detached {
            do {
                let url = try await extractAudio(from: videoURL)
                await MainActor.run { completion(.success(url)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Private helpers

    /// Build a unique, deterministic-looking temp-dir URL for the extracted m4a.
    private nonisolated static func makeOutputURL(for videoURL: URL) -> URL {
        let stem = videoURL.deletingPathExtension().lastPathComponent
        let suffix = UUID().uuidString.prefix(8)
        let filename = "\(stem)-audio-\(suffix).m4a"
        return FileManager.default
            .temporaryDirectory
            .appendingPathComponent(filename, isDirectory: false)
    }
}
