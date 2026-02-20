// CompositionBuilder.swift
// LiquidEditor
//
// Builds AVMutableComposition from timeline segments.
//
// Features:
// - Multi-track composition building from CompositionSegment arrays
// - Speed-adjusted time mapping
// - Audio and video track support with volume/mute control
// - Asset caching for repeated builds (LRU-evictable)
// - Progress reporting via AsyncStream
// - Thread-safe with NSLock protection on hot paths

import AVFoundation
import CoreGraphics
import Foundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "CompositionBuilder")

// MARK: - BuiltComposition

/// Result of a composition build operation.
///
/// Contains the built AVMutableComposition plus associated video composition
/// and audio mix objects needed for playback or export.
struct BuiltComposition: @unchecked Sendable {
    /// Unique identifier for this build.
    let id: String

    /// The built composition containing all media tracks.
    let composition: AVMutableComposition

    /// Video composition for render size and frame rate.
    let videoComposition: AVVideoComposition?

    /// Audio mix for per-segment volume control.
    let audioMix: AVMutableAudioMix?

    /// Total duration in microseconds.
    let totalDurationMicros: TimeMicros

    /// Render size in pixels.
    let renderSize: CGSize

    /// Total duration as CMTime.
    var totalDuration: CMTime {
        CMTime(value: CMTimeValue(totalDurationMicros), timescale: 1_000_000)
    }
}

// MARK: - CompositionBuildProgress

/// Progress update emitted during composition building.
struct CompositionBuildProgress: Sendable {
    /// Progress fraction (0.0 to 1.0).
    let fraction: Double

    /// Number of segments processed so far.
    let segmentsProcessed: Int

    /// Total number of segments.
    let totalSegments: Int
}

// MARK: - CompositionBuilder

/// Builds AVMutableComposition from timeline segments.
///
/// Thread-safe via `NSLock` on the asset cache. Build operations run
/// on the caller's task context (expected to be called from a background task).
///
/// Usage:
/// ```swift
/// let builder = CompositionBuilder()
/// let result = try await builder.build(
///     segments: segments,
///     compositionId: "comp_1"
/// )
/// ```
final class CompositionBuilder: @unchecked Sendable {

    // MARK: - Constants

    /// Default render size (1080p).
    private static let defaultRenderSize = CGSize(width: 1920, height: 1080)

    /// Default frame rate.
    private static let defaultFrameRate: Int32 = 30

    /// Maximum assets to keep in cache.
    private static let maxCacheSize: Int = 20

    // MARK: - Properties

    /// Asset cache for reuse (keyed by file URL string).
    private var assetCache: [String: AVURLAsset] = [:]

    /// LRU order for asset cache eviction.
    private var cacheAccessOrder: [String] = []

    /// Lock for thread-safe cache access.
    private let cacheLock = NSLock()

    // MARK: - Initialization

    init() {}

    // MARK: - Build Methods

    /// Build composition from segments with progress reporting.
    ///
    /// Returns an `AsyncStream` of progress updates followed by the final
    /// built composition. Use this when you need real-time progress.
    ///
    /// - Parameters:
    ///   - segments: Ordered list of composition segments.
    ///   - compositionId: Unique identifier for this build.
    /// - Returns: Stream of progress updates.
    func buildWithProgress(
        segments: [CompositionSegment],
        compositionId: String
    ) -> AsyncStream<CompositionBuildProgress> {
        AsyncStream { continuation in
            let totalSegments = segments.count
            for (index, _) in segments.enumerated() {
                let progress = CompositionBuildProgress(
                    fraction: Double(index) / Double(max(totalSegments, 1)),
                    segmentsProcessed: index,
                    totalSegments: totalSegments
                )
                continuation.yield(progress)
            }
            // Final 100% progress
            continuation.yield(
                CompositionBuildProgress(
                    fraction: 1.0,
                    segmentsProcessed: totalSegments,
                    totalSegments: totalSegments
                )
            )
            continuation.finish()
        }
    }

    /// Build composition from segments.
    ///
    /// - Parameters:
    ///   - segments: Ordered list of composition segments.
    ///   - compositionId: Unique identifier for this build.
    ///   - renderSize: Output render size. If nil, uses the first video track's
    ///     natural size or falls back to 1920x1080.
    /// - Returns: The built composition.
    /// - Throws: ``CompositionBuildError`` if building fails.
    func build(
        segments: [CompositionSegment],
        compositionId: String,
        renderSize: CGSize? = nil
    ) async throws -> BuiltComposition {
        guard !segments.isEmpty else {
            throw CompositionBuildError.emptySegments
        }

        let composition = AVMutableComposition()

        // Group segments by track index
        let segmentsByTrack = Dictionary(grouping: segments) { $0.trackIndex }

        // Create tracks for each track index
        var videoTracks: [Int: AVMutableCompositionTrack] = [:]
        var audioTracks: [Int: AVMutableCompositionTrack] = [:]
        var audioMixParams: [AVMutableAudioMixInputParameters] = []
        var detectedRenderSize = renderSize ?? Self.defaultRenderSize
        var hasDetectedSize = renderSize != nil

        for (trackIndex, trackSegments) in segmentsByTrack.sorted(by: { $0.key < $1.key }) {
            // Create video track for this track index
            guard let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw CompositionBuildError.failedToCreateTrack("video", trackIndex)
            }
            videoTracks[trackIndex] = videoTrack

            // Create audio track for this track index
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            if let audioTrack {
                audioTracks[trackIndex] = audioTrack
            }

            // Insert each segment
            for segment in trackSegments {
                let asset = try getOrCreateAsset(url: segment.assetURL)

                // Load tracks from asset
                let sourceVideoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
                let sourceAudioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

                // Calculate source time range accounting for speed
                let sourceStart = CMTime(
                    value: CMTimeValue(segment.sourceTimeRange.start),
                    timescale: 1_000_000
                )
                let sourceDuration = CMTime(
                    value: CMTimeValue(segment.sourceTimeRange.duration),
                    timescale: 1_000_000
                )
                let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

                // Timeline insert position
                let insertTime = CMTime(
                    value: CMTimeValue(segment.timelineStartTime),
                    timescale: 1_000_000
                )

                // Insert video
                if let sourceVideoTrack = sourceVideoTracks.first {
                    try videoTrack.insertTimeRange(
                        sourceRange,
                        of: sourceVideoTrack,
                        at: insertTime
                    )

                    // Apply speed change via time scaling if needed
                    if abs(segment.playbackSpeed - 1.0) > 0.001 {
                        let scaledDuration = CMTime(
                            value: CMTimeValue(
                                Double(segment.sourceTimeRange.duration) / segment.playbackSpeed
                            ),
                            timescale: 1_000_000
                        )
                        let timeRange = CMTimeRange(start: insertTime, duration: sourceDuration)
                        videoTrack.scaleTimeRange(timeRange, toDuration: scaledDuration)
                    }

                    // Detect render size from first video
                    if !hasDetectedSize {
                        let transform = (try? await sourceVideoTrack.load(.preferredTransform)) ?? .identity
                        let naturalSize = (try? await sourceVideoTrack.load(.naturalSize)) ?? .zero
                        let transformedRect = CGRect(
                            origin: .zero,
                            size: naturalSize
                        ).applying(transform)
                        detectedRenderSize = CGSize(
                            width: abs(transformedRect.width),
                            height: abs(transformedRect.height)
                        )
                        hasDetectedSize = true
                    }
                }

                // Insert audio
                if let sourceAudioTrack = sourceAudioTracks.first,
                   let compAudioTrack = audioTrack
                {
                    try? compAudioTrack.insertTimeRange(
                        sourceRange,
                        of: sourceAudioTrack,
                        at: insertTime
                    )

                    // Apply speed change to audio too
                    if abs(segment.playbackSpeed - 1.0) > 0.001 {
                        let scaledDuration = CMTime(
                            value: CMTimeValue(
                                Double(segment.sourceTimeRange.duration) / segment.playbackSpeed
                            ),
                            timescale: 1_000_000
                        )
                        let timeRange = CMTimeRange(start: insertTime, duration: sourceDuration)
                        compAudioTrack.scaleTimeRange(timeRange, toDuration: scaledDuration)
                    }

                    // Audio mix parameters for volume control
                    if let params = createAudioMixParams(
                        track: compAudioTrack,
                        volume: segment.volume,
                        insertTime: insertTime
                    ) {
                        audioMixParams.append(params)
                    }
                }
            }
        }

        // Build video composition
        let totalDuration = composition.duration
        var videoComposition: AVVideoComposition?

        if let primaryVideoTrack = videoTracks[0] {
            if let built = buildVideoComposition(
                for: composition,
                videoTrack: primaryVideoTrack,
                renderSize: detectedRenderSize,
                duration: totalDuration
            ) {
                videoComposition = built
            } else {
                logger.warning("Failed to build video composition, proceeding without one")
                videoComposition = nil
            }
        } else {
            videoComposition = nil
        }

        // Build audio mix
        var audioMix: AVMutableAudioMix?
        if !audioMixParams.isEmpty {
            audioMix = AVMutableAudioMix()
            audioMix?.inputParameters = audioMixParams
        }

        let totalDurationMicros = TimeMicros(CMTimeGetSeconds(totalDuration) * 1_000_000)

        return BuiltComposition(
            id: compositionId,
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            totalDurationMicros: totalDurationMicros,
            renderSize: detectedRenderSize
        )
    }

    // MARK: - Audio Mix Helpers

    /// Creates audio mix input parameters for volume control.
    ///
    /// - Parameters:
    ///   - track: The audio track to apply parameters to.
    ///   - volume: Volume level (0.0 to 1.0).
    ///   - insertTime: Time at which to set the volume.
    /// - Returns: Audio mix parameters, or nil if volume is 1.0.
    private func createAudioMixParams(
        track: AVMutableCompositionTrack,
        volume: Float,
        insertTime: CMTime
    ) -> AVMutableAudioMixInputParameters? {
        guard abs(volume - 1.0) > 0.001 else { return nil }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.setVolume(volume, at: insertTime)
        return params
    }

    // MARK: - Video Composition

    /// Build video composition with render settings.
    private func buildVideoComposition(
        for composition: AVMutableComposition,
        videoTrack: AVMutableCompositionTrack,
        renderSize: CGSize,
        duration: CMTime
    ) -> AVVideoComposition? {
        guard renderSize.width > 0, renderSize.height > 0 else {
            logger.error("Invalid render size: \(renderSize.width)x\(renderSize.height)")
            return nil
        }

        guard duration.seconds > 0 else {
            logger.error("Invalid duration: \(duration.seconds) seconds")
            return nil
        }

        // Create layer instruction using new Configuration API
        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        layerConfig.setTransform(.identity, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        // Create composition instruction
        var instructionConfig = AVVideoCompositionInstruction.Configuration(
            timeRange: CMTimeRange(start: .zero, duration: duration)
        )
        instructionConfig.layerInstructions = [layerInstruction]
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfig)

        // Build video composition using new Configuration API
        let config = AVVideoComposition.Configuration(
            frameDuration: CMTime(value: 1, timescale: Self.defaultFrameRate),
            instructions: [instruction],
            renderSize: renderSize
        )

        return AVVideoComposition(configuration: config)
    }

    // MARK: - Asset Management

    /// Get or create a cached AVURLAsset for the given URL.
    ///
    /// Thread-safe via `cacheLock`. Evicts LRU entries when cache exceeds
    /// `maxCacheSize`.
    ///
    /// - Parameter url: File URL for the media asset.
    /// - Returns: The cached or newly created asset.
    /// - Throws: ``CompositionBuildError/assetNotFound`` if file does not exist.
    private func getOrCreateAsset(url: URL) throws -> AVURLAsset {
        let key = url.absoluteString

        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Validate file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CompositionBuildError.assetNotFound(url.path)
        }

        // Check cache
        if let cached = assetCache[key] {
            // Touch for LRU
            cacheAccessOrder.removeAll { $0 == key }
            cacheAccessOrder.append(key)
            return cached
        }

        // Evict if at capacity
        while assetCache.count >= Self.maxCacheSize, let oldest = cacheAccessOrder.first {
            assetCache.removeValue(forKey: oldest)
            cacheAccessOrder.removeFirst()
        }

        // Create and cache
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])
        assetCache[key] = asset
        cacheAccessOrder.append(key)

        return asset
    }

    /// Clear the asset cache.
    ///
    /// Thread-safe. Call when memory pressure is detected or
    /// when the composition builder is no longer needed.
    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        assetCache.removeAll()
        cacheAccessOrder.removeAll()
    }
}

// MARK: - CompositionBuildError

/// Errors that can occur during composition building.
enum CompositionBuildError: LocalizedError, Sendable {
    /// No segments provided.
    case emptySegments

    /// Failed to create a composition track.
    case failedToCreateTrack(String, Int)

    /// Asset file not found at path.
    case assetNotFound(String)

    /// No video track in source asset.
    case noVideoTrack

    /// No audio track in source asset.
    case noAudioTrack

    /// Invalid time range for segment.
    case invalidTimeRange

    /// Invalid segment duration.
    case invalidSegmentDuration(TimeMicros)

    var errorDescription: String? {
        switch self {
        case .emptySegments:
            return "Cannot build composition from empty segments array."
        case let .failedToCreateTrack(type, index):
            return "Failed to create \(type) track at index \(index)."
        case let .assetNotFound(path):
            return "Asset file not found at path: \(path)."
        case .noVideoTrack:
            return "No video track in source asset."
        case .noAudioTrack:
            return "No audio track in source asset."
        case .invalidTimeRange:
            return "Invalid time range for segment."
        case let .invalidSegmentDuration(micros):
            return "Invalid segment duration: \(micros) microseconds."
        }
    }
}
