// VideoConstants.swift
// LiquidEditor
//
// Centralized constants for video processing operations.
// Eliminates magic numbers for improved maintainability and consistency.

import CoreGraphics
import Foundation

// MARK: - VideoConstants

/// Centralized constants for video processing operations.
///
/// Groups related constants by domain: thumbnail sizing, compression
/// quality, timing tolerances, export settings, resolution thresholds,
/// proxy generation, and frame cache.
///
/// Thread Safety:
/// - All values are static let (immutable) - safe from any thread.
enum VideoConstants {

    // MARK: - Thumbnail Sizes

    /// Maximum size for single thumbnail generation (project thumbnails, library view).
    static let thumbnailMaxSize = CGSize(width: 360, height: 640)

    /// Maximum size for timeline scrubbing thumbnails (smaller for performance).
    static let timelineThumbnailMaxSize = CGSize(width: 120, height: 200)

    /// Maximum size for preview frame extraction (export preview, debug).
    static let previewFrameMaxSize = CGSize(width: 320, height: 568)

    // MARK: - Compression Quality

    /// JPEG compression quality for timeline thumbnails (faster, smaller).
    static let timelineThumbnailCompressionQuality: CGFloat = 0.6

    /// JPEG compression quality for preview frames (higher quality for visibility).
    static let previewFrameCompressionQuality: CGFloat = 0.7

    /// JPEG compression quality for frame grabs / screenshots.
    static let frameGrabCompressionQuality: CGFloat = 0.92

    /// PNG is preferred for lossless thumbnail output when size is acceptable.
    static let thumbnailPrefersPNG: Bool = true

    // MARK: - Timing

    /// Default time offset for thumbnail extraction (avoids black frames at video start).
    static let defaultThumbnailTimeOffset: Double = 0.1

    /// Time tolerance for timeline thumbnails (allows faster seeking with acceptable accuracy).
    static let timelineThumbnailTolerance: Double = 0.5

    /// Time tolerance for preview frame extraction.
    static let previewFrameTolerance: Double = 0.1

    /// Time tolerance for frame grab operations.
    static let frameGrabTolerance: Double = 0.1

    /// Preferred timescale for CMTime values (ticks per second).
    static let preferredTimescale: Int32 = 600

    // MARK: - Export Settings

    /// Default frames per second for video export.
    static let defaultExportFps: Int = 30

    /// Default bitrate in Mbps for video export.
    static let defaultExportBitrateMbps: Double = 20.0

    /// File size estimate multiplier (headroom for encoding overhead).
    static let fileSizeEstimateMultiplier: Double = 1.1

    /// Export progress polling interval in seconds.
    static let exportProgressInterval: TimeInterval = 0.1

    // MARK: - Resolution Thresholds (for preset selection)

    /// 4K resolution threshold (width).
    static let resolution4KWidth: Int = 3840

    /// 4K resolution threshold (height).
    static let resolution4KHeight: Int = 2160

    /// 1080p resolution threshold (width).
    static let resolution1080pWidth: Int = 1920

    /// 1080p resolution threshold (height).
    static let resolution1080pHeight: Int = 1080

    /// 720p resolution threshold (width).
    static let resolution720pWidth: Int = 1280

    /// 720p resolution threshold (height).
    static let resolution720pHeight: Int = 720

    /// High bitrate threshold (Mbps) for selecting highest quality preset.
    static let highBitrateThreshold: Double = 50.0

    // MARK: - Proxy Generation

    /// Prefix for proxy video files.
    static let proxyFilePrefix: String = "proxy_1080p_"

    /// Proxy resolution target width.
    static let proxyTargetWidth: Int = 1920

    /// Proxy resolution target height.
    static let proxyTargetHeight: Int = 1080

    // MARK: - Frame Cache Settings

    /// Maximum number of frames to cache (at 1080p, ~300MB).
    static let frameCacheMaxCount: Int = 120

    /// Maximum total memory for frame cache in bytes (~300MB).
    static let frameCacheMaxBytes: Int = 300 * 1024 * 1024

    /// Number of frames to prefetch ahead of playhead.
    static let framePrefetchCount: Int = 15

    /// Number of frames to prefetch behind playhead.
    static let framePrefetchBehindCount: Int = 5

    /// Frame cache eviction batch size.
    static let frameCacheEvictionBatch: Int = 10

    // MARK: - Temporary File Management

    /// Prefix for rendered output files.
    static let renderedFilePrefix: String = "rendered_"

    /// Prefix for composition output files.
    static let compositionFilePrefix: String = "composition_"

    /// Prefix for audio export output files.
    static let audioFilePrefix: String = "audio_"

    /// Prefix for frame grab output files.
    static let frameGrabFilePrefix: String = "frame_grab_"

    /// Prefix for GIF export output files.
    static let gifFilePrefix: String = "gif_"

    /// Maximum age (in days) for temporary export files before cleanup.
    static let tempFileMaxAgeDays: Int = 7

    /// Temporary file prefixes eligible for cleanup.
    static let cleanupPrefixes: [String] = [
        renderedFilePrefix,
        compositionFilePrefix,
        audioFilePrefix,
        frameGrabFilePrefix,
        gifFilePrefix,
        "export_",
    ]

    /// File extension for project files eligible for cleanup.
    static let projectFileExtension: String = ".liquidproject"

    // MARK: - Audio Session

    /// Default audio session category for video editing.
    static let audioSessionMixWithOthers: Bool = true
}
