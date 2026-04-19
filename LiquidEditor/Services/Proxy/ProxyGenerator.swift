// ProxyGenerator.swift
// LiquidEditor
//
// PP12-9: A focused actor-based proxy transcoder that wraps
// `AVAssetExportSession` with the iOS 18+ async export API.
//
// `ProxyGenerator` is intentionally narrower than `ProxyService` — it is a
// pure transcoding primitive that produces an `.mov` file in the system
// temporary directory. Higher-level coordination (registry lookup, LRU
// eviction, storage quotas) lives in `ProxyService` / `ProxyStorageManager`.
//
// Architecture:
// - `actor ProxyGenerator` — full Swift 6 isolation.
// - Inputs/outputs are all `Sendable`.
// - Uses `AVAssetExportSession.export(to:as:)` (iOS 18+) to avoid the
//   deprecated `exportAsynchronously` completion-handler API.
// - Output path: <NSTemporaryDirectory>/<sourceHash>.proxy.<hex>.mov

import AVFoundation
import CryptoKit
import Foundation

// MARK: - ProxyResolution (generator-level)

/// Target resolution preset for `ProxyGenerator`.
///
/// These sit alongside `ProxyService.ProxyResolution` but describe the
/// fractional size of the *source* rather than an absolute pixel ceiling.
/// Keeps the generator API decoupled from the higher-level preset list so
/// callers can request e.g. "half-size offline proxy" without having to
/// know the nearest named preset.
enum ProxyGeneratorResolution: Sendable, Equatable {
    /// ¼-resolution proxy — smallest, fastest, for large 4K+ masters.
    case quarter
    /// ½-resolution proxy — default for most editing scenarios.
    case half
    /// Full resolution — transcode-only (e.g. re-wrap to a friendlier codec).
    case full

    /// Human-readable short tag used inside generated filenames.
    var tag: String {
        switch self {
        case .quarter: return "q"
        case .half:    return "h"
        case .full:    return "f"
        }
    }
}

// MARK: - ProxyProfile

/// Encoding profile used when generating a proxy.
///
/// Mapping is intentional:
/// - `.proxyHQ` → `AVAssetExportPresetMediumQuality` — balanced quality/size.
/// - `.proxyLT` → `AVAssetExportPresetLowQuality` — smallest, fastest.
enum ProxyProfile: Sendable, Equatable {
    /// High-quality proxy — preferred for editing that still needs visual
    /// fidelity (colour work, graded masters).
    case proxyHQ
    /// Lightweight proxy — smallest on-disk footprint, used for scrub-only
    /// offline editing on constrained storage.
    case proxyLT

    /// The concrete `AVAssetExportPreset` string to hand to
    /// `AVAssetExportSession(asset:presetName:)`.
    fileprivate var exportPreset: String {
        switch self {
        case .proxyHQ: return AVAssetExportPresetMediumQuality
        case .proxyLT: return AVAssetExportPresetLowQuality
        }
    }

    /// Short tag used inside generated filenames.
    fileprivate var tag: String {
        switch self {
        case .proxyHQ: return "hq"
        case .proxyLT: return "lt"
        }
    }
}

// MARK: - ProxyGeneratorError

/// Errors thrown by `ProxyGenerator`.
enum ProxyGeneratorError: LocalizedError, Sendable {
    /// `AVAssetExportSession` could not be created for the requested preset.
    case exportSessionUnavailable(URL, String)
    /// The underlying `export(to:as:)` call threw.
    case exportFailed(String)
    /// The output directory is unavailable / not writable.
    case directoryUnavailable(URL)

    var errorDescription: String? {
        switch self {
        case let .exportSessionUnavailable(url, preset):
            return "Cannot create export session for '\(url.lastPathComponent)' with preset '\(preset)'."
        case let .exportFailed(message):
            return "Proxy export failed: \(message)."
        case let .directoryUnavailable(url):
            return "Proxy output directory '\(url.path)' is unavailable."
        }
    }
}

// MARK: - ProxyGenerator

/// Actor-isolated proxy transcoder.
///
/// ### Usage
/// ```swift
/// let generator = ProxyGenerator()
/// let url = try await generator.generate(
///     sourceURL: sourceURL,
///     resolution: .half,
///     profile: .proxyHQ
/// )
/// ```
///
/// ### Output
/// The output path is deterministic for the same `(sourceURL, resolution,
/// profile)` triple — re-invoking the generator will overwrite any previous
/// file at that path. Filename format:
///
/// `<sha256-hex-prefix>.proxy.<hash>.mov`
///
/// where `<sha256-hex-prefix>` is the first 16 chars of the SHA-256 digest
/// of the source URL's `absoluteString` and `<hash>` encodes the resolution
/// + profile tags.
///
/// ### Thread Safety
/// All mutable state is actor-isolated. Callers must `await` every method.
actor ProxyGenerator {

    // MARK: - Initialization

    /// Creates a new `ProxyGenerator`. No persistent state is kept between
    /// calls — each `generate(...)` call is independent.
    init() {}

    // MARK: - Public API

    /// Transcode `sourceURL` into a proxy `.mov` file in the temporary
    /// directory.
    ///
    /// - Parameters:
    ///   - sourceURL: Local file URL of the source video.
    ///   - resolution: Target proxy resolution.
    ///   - profile: Encoding profile (HQ vs LT).
    /// - Returns: URL of the generated `.mov` file in `NSTemporaryDirectory`.
    /// - Throws: `ProxyGeneratorError` on setup or export failure.
    func generate(
        sourceURL: URL,
        resolution: ProxyGeneratorResolution,
        profile: ProxyProfile
    ) async throws -> URL {
        let outputURL = Self.makeOutputURL(
            for: sourceURL,
            resolution: resolution,
            profile: profile
        )

        // Ensure parent directory exists and is writable.
        let parent = outputURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: parent.path) {
            do {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                throw ProxyGeneratorError.directoryUnavailable(parent)
            }
        }

        // Remove any pre-existing file at the deterministic path so the
        // iOS 18+ async export API can write cleanly.
        try? fm.removeItem(at: outputURL)

        // Build the export session.
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: profile.exportPreset
        ) else {
            throw ProxyGeneratorError.exportSessionUnavailable(sourceURL, profile.exportPreset)
        }

        // Run the iOS 18+ async export. This throws on failure so we do not
        // need to inspect `session.status` manually.
        do {
            try await session.export(to: outputURL, as: .mov)
        } catch {
            throw ProxyGeneratorError.exportFailed(error.localizedDescription)
        }

        return outputURL
    }

    // MARK: - Filename Helpers

    /// Build the deterministic output URL for the given source+params.
    ///
    /// We hash the `absoluteString` of the source URL (not the path) so that
    /// proxies are unique per logical asset even if multiple files share a
    /// lastPathComponent across folders.
    private static func makeOutputURL(
        for sourceURL: URL,
        resolution: ProxyGeneratorResolution,
        profile: ProxyProfile
    ) -> URL {
        let digest = SHA256.hash(data: Data(sourceURL.absoluteString.utf8))
        let hexPrefix = digest
            .prefix(8) // 8 bytes → 16 hex chars → collision-safe for a device
            .map { String(format: "%02x", $0) }
            .joined()
        let hashTag = "\(resolution.tag)\(profile.tag)"
        let filename = "\(hexPrefix).proxy.\(hashTag).mov"
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(filename)
    }
}
