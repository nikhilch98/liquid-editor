// ProxyService.swift
// LiquidEditor
//
// Generates lower-resolution proxy files for 4K+ videos for smooth editing
// performance. Transparently switches between proxy and original for export.
//
// Architecture: `actor` for full isolation -- all state mutations are
// serialised through the actor executor. No locks required.

import AVFoundation
import Foundation

// MARK: - ProxyResolution

/// Resolution preset for proxy generation.
///
/// Choose based on the trade-off between editing smoothness and storage cost.
/// `.p720` is the recommended default for most 4K source material.
enum ProxyResolution: String, CaseIterable, Sendable {
    /// 480p -- smallest file, best for limited storage.
    case p480 = "480p"
    /// 720p -- recommended default; good balance of quality and performance.
    case p720 = "720p"
    /// 1080p -- highest proxy quality; still much smaller than 4K originals.
    case p1080 = "1080p"

    /// Maximum pixel dimension (longer edge) for this resolution.
    var maxDimension: CGFloat {
        switch self {
        case .p480:  return 480
        case .p720:  return 720
        case .p1080: return 1080
        }
    }

    /// The `AVAssetExportPreset` that best matches this resolution.
    ///
    /// Preset selection:
    /// - `.p480`  → `AVAssetExportPresetMediumQuality`   (≈ 480p)
    /// - `.p720`  → `AVAssetExportPreset960x540`          (≈ 720p)
    /// - `.p1080` → `AVAssetExportPreset1280x720`         (≈ 1080p)
    var exportPreset: String {
        switch self {
        case .p480:  return AVAssetExportPresetMediumQuality
        case .p720:  return AVAssetExportPreset960x540
        case .p1080: return AVAssetExportPreset1280x720
        }
    }

    /// Human-readable label shown in settings / progress UI.
    var displayName: String {
        rawValue
    }
}

// MARK: - ProxyAsset

/// Represents a successfully generated proxy file linked to a source URL.
struct ProxyAsset: Sendable {
    /// The original full-resolution source URL.
    let sourceURL: URL
    /// The generated lower-resolution proxy file URL.
    let proxyURL: URL
    /// Resolution preset that was used for generation.
    let resolution: ProxyResolution
    /// When the proxy was generated.
    let createdAt: Date
}

// MARK: - ProxyError

/// Errors thrown by `ProxyService`.
enum ProxyError: LocalizedError, Sendable {
    /// The `AVAssetExportSession` could not be created for the given preset.
    case exportSessionUnavailable(URL, String)
    /// Export finished with a status other than `.completed`.
    case exportFailed(AVAssetExportSession.Status, String?)
    /// The proxy directory could not be created or accessed.
    case directoryUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case .exportSessionUnavailable(let url, let preset):
            return "Cannot create export session for '\(url.lastPathComponent)' with preset '\(preset)'."
        case .exportFailed(let status, let message):
            return "Export failed with status \(status.rawValue): \(message ?? "unknown error")."
        case .directoryUnavailable(let url):
            return "Proxy directory is unavailable at '\(url.path)'."
        }
    }
}

// MARK: - ProxyService

/// Actor-based service that generates, stores, and retrieves low-resolution
/// proxy files for 4K+ source videos.
///
/// ### Workflow
/// 1. Call `needsProxy(url:)` to check if a source requires a proxy.
/// 2. Call `generateProxy(for:resolution:progressHandler:)` to transcode.
/// 3. Call `getPlaybackPath(for:)` to get the best URL for playback
///    (proxy if available, original otherwise).
/// 4. Proxies are stored in `<Documents>/Proxies/` and survive app launches.
///
/// ### Thread Safety
/// All state is isolated to the actor. Callers must `await` every method.
actor ProxyService {

    // MARK: - Singleton

    /// Shared instance for app-wide use.
    static let shared = ProxyService()

    // MARK: - State

    /// Proxy registry keyed by source URL absolute string.
    private var registry: [String: ProxyAsset] = [:]

    /// Directory where proxy `.mov` files are stored.
    let proxiesDirectory: URL

    // MARK: - Constants

    /// Width threshold above which a video is considered 4K+.
    private static let proxyThresholdWidth: Int = 3840

    // MARK: - Initialization

    /// Initialiser -- creates the `Proxies/` directory if it does not exist.
    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        proxiesDirectory = documents.appendingPathComponent("Proxies", isDirectory: true)
        // Directory creation is best-effort during init; errors surface in generateProxy.
        try? FileManager.default.createDirectory(at: proxiesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Whether a video file requires a proxy (4K or wider source).
    ///
    /// Loads the asset tracks synchronously on a background thread via async/await.
    /// Returns `false` if the resolution cannot be determined.
    ///
    /// - Parameter url: Local file URL of the source video.
    /// - Returns: `true` when the source video width ≥ 3840 pixels.
    func needsProxy(url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return false
        }
        let size = (try? await track.load(.naturalSize)) ?? .zero
        let width = Int(max(size.width, size.height)) // account for portrait rotation
        return width >= Self.proxyThresholdWidth
    }

    /// Returns the best playback URL for the given source.
    ///
    /// Returns the proxy URL if a `ProxyAsset` exists in the registry AND
    /// the proxy file is still present on disk (iOS may reclaim temp files).
    /// Falls back to the original URL otherwise.
    ///
    /// - Parameter url: Original source video URL.
    /// - Returns: Proxy URL when available, original URL otherwise.
    func getPlaybackPath(for url: URL) async -> URL {
        let key = url.absoluteString
        guard let proxy = registry[key] else { return url }
        let exists = FileManager.default.fileExists(atPath: proxy.proxyURL.path)
        if exists {
            return proxy.proxyURL
        }
        // Proxy was reclaimed by the OS -- remove stale registry entry.
        registry.removeValue(forKey: key)
        return url
    }

    /// Generate a proxy file for the given video URL.
    ///
    /// If a proxy already exists in the registry for this source and the
    /// file is still on disk, that existing `ProxyAsset` is returned
    /// immediately without re-encoding.
    ///
    /// - Parameters:
    ///   - url: Source video URL (must be a local file URL).
    ///   - resolution: Target proxy resolution (default `.p720`).
    ///   - progressHandler: Called with values in `[0, 1]` on an arbitrary
    ///     thread. Marked `@Sendable` -- update UI via `Task { @MainActor in ... }`.
    /// - Returns: The generated `ProxyAsset`.
    /// - Throws: `ProxyError` if directory creation or transcoding fails.
    func generateProxy(
        for url: URL,
        resolution: ProxyResolution = .p720,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> ProxyAsset {
        let key = url.absoluteString

        // Return cached proxy if still valid.
        if let existing = registry[key],
           FileManager.default.fileExists(atPath: existing.proxyURL.path) {
            progressHandler(1.0)
            return existing
        }

        // Ensure the proxies directory exists.
        let fm = FileManager.default
        if !fm.fileExists(atPath: proxiesDirectory.path) {
            do {
                try fm.createDirectory(at: proxiesDirectory, withIntermediateDirectories: true)
            } catch {
                throw ProxyError.directoryUnavailable(proxiesDirectory)
            }
        }

        // Build a unique output path derived from the source URL.
        let sourceName = url.deletingPathExtension().lastPathComponent
        let outputFilename = "\(sourceName)_proxy_\(resolution.rawValue)_\(UUID().uuidString).mov"
        let outputURL = proxiesDirectory.appendingPathComponent(outputFilename)

        // Remove any pre-existing file at the destination.
        try? fm.removeItem(at: outputURL)

        // Create the export session.
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: resolution.exportPreset) else {
            throw ProxyError.exportSessionUnavailable(url, resolution.exportPreset)
        }

        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false

        // Poll progress on a detached background task.
        // AVAssetExportSession is not Sendable; we wrap it in nonisolated(unsafe)
        // to cross the Swift 6 Sendable boundary safely — access is read-only
        // and AVAssetExportSession's `progress` property is documented as
        // thread-safe for reading.
        nonisolated(unsafe) let sessionForProgress = session
        let progressTask = Task.detached { @Sendable in
            while !Task.isCancelled {
                progressHandler(Double(sessionForProgress.progress))
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
            }
        }

        // Run the export (suspends until completion).
        await session.export()

        progressTask.cancel()
        progressHandler(1.0)

        // Check export result.
        switch session.status {
        case .completed:
            let proxyAsset = ProxyAsset(
                sourceURL: url,
                proxyURL: outputURL,
                resolution: resolution,
                createdAt: Date()
            )
            registry[key] = proxyAsset
            return proxyAsset

        default:
            let message = session.error?.localizedDescription
            throw ProxyError.exportFailed(session.status, message)
        }
    }

    /// Delete the proxy file (if any) for a specific source URL.
    ///
    /// Removes both the registry entry and the file on disk.
    ///
    /// - Parameter url: The original source video URL.
    func deleteProxy(for url: URL) async {
        let key = url.absoluteString
        guard let proxy = registry.removeValue(forKey: key) else { return }
        try? FileManager.default.removeItem(at: proxy.proxyURL)
    }

    /// Delete ALL proxy files and clear the registry.
    ///
    /// Iterates over all registered proxies and removes their files,
    /// then clears the in-memory registry. Errors for individual files
    /// are silently swallowed so that a single bad file does not abort
    /// the cleanup of the rest.
    func deleteAllProxies() async {
        let allProxies = registry.values
        for proxy in allProxies {
            try? FileManager.default.removeItem(at: proxy.proxyURL)
        }
        registry.removeAll()
    }

    // MARK: - Diagnostics

    /// Number of proxies currently in the registry.
    var registryCount: Int { registry.count }

    /// All registered proxy assets.
    var allProxies: [ProxyAsset] { Array(registry.values) }

    /// Returns whether a proxy exists (in registry and on disk) for a source URL.
    func hasProxy(for url: URL) -> Bool {
        guard let proxy = registry[url.absoluteString] else { return false }
        return FileManager.default.fileExists(atPath: proxy.proxyURL.path)
    }
}
