// VideoProcessingService.swift
// LiquidEditor
//
// Central video processing service for the Liquid Editor.
// Handles thumbnail generation, proxy generation, frame extraction,
// multi-clip composition rendering, and export cancel support.

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import UIKit
import os

// MARK: - VideoProcessingResult

/// Result of a video processing operation.
enum VideoProcessingResult: Sendable {
    case success(outputPath: String)
    case imageData(Data)
    case frameGrab(path: String, data: Data, width: Int, height: Int)
    case thumbnails([(timestampMs: Int, base64: String)])
    case cancelled
    case failure(VideoProcessingError)
}

// MARK: - VideoProcessingError

/// Errors that can occur during video processing.
enum VideoProcessingError: Error, Sendable {
    case fileNotFound(String)
    case noVideoTrack
    case noAudioTrack
    case compositionTrackFailed
    case insertFailed(String)
    case exportInitFailed
    case exportFailed(String)
    case exportCancelled
    case exportUnknownStatus(Int)
    case thumbnailFailed(String)
    case frameExtractionFailed(String)
    case conversionFailed(String)
    case renderFailed(String)
    case invalidConfiguration(String)

    var localizedDescription: String {
        switch self {
        case .fileNotFound(let path):
            return "Input file does not exist: \(path)"
        case .noVideoTrack:
            return "No video track found"
        case .noAudioTrack:
            return "No audio track found"
        case .compositionTrackFailed:
            return "Could not add composition track"
        case .insertFailed(let msg):
            return "Failed to insert time range: \(msg)"
        case .exportInitFailed:
            return "Failed to create export session"
        case .exportFailed(let msg):
            return "Export failed: \(msg)"
        case .exportCancelled:
            return "Export was cancelled"
        case .exportUnknownStatus(let status):
            return "Unknown export status: \(status)"
        case .thumbnailFailed(let msg):
            return "Thumbnail generation failed: \(msg)"
        case .frameExtractionFailed(let msg):
            return "Frame extraction failed: \(msg)"
        case .conversionFailed(let msg):
            return "Image conversion failed: \(msg)"
        case .renderFailed(let msg):
            return "Render failed: \(msg)"
        case .invalidConfiguration(let msg):
            return "Invalid configuration: \(msg)"
        }
    }
}

// MARK: - ClipSegment

/// A single clip segment for multi-clip composition.
struct ClipSegment: Sendable {
    /// Source in-point in milliseconds.
    let sourceInPointMs: Int

    /// Source out-point in milliseconds.
    let sourceOutPointMs: Int

    /// Order index in the composition.
    let orderIndex: Int

    /// Keyframe transforms for this clip.
    let keyframes: [KeyframeTransform]
}

// MARK: - KeyframeTransform

/// A single keyframe transform for animation.
struct KeyframeTransform: Sendable {
    /// Start time in milliseconds (relative to clip start).
    let startTimeMs: Int

    /// End time in milliseconds (relative to clip start).
    let endTimeMs: Int

    /// Start scale X.
    let sx: Double

    /// Start scale Y.
    let sy: Double

    /// Start translation X (normalized).
    let tx: Double

    /// Start translation Y (normalized).
    let ty: Double

    /// Start rotation in radians.
    let rotation: Double

    /// End scale X.
    let esx: Double

    /// End scale Y.
    let esy: Double

    /// End translation X (normalized).
    let etx: Double

    /// End translation Y (normalized).
    let ety: Double

    /// End rotation in radians.
    let erotation: Double
}

// MARK: - VideoProcessingService

/// Central video processing service.
///
/// Provides async methods for all video processing operations:
/// thumbnail generation, proxy creation, video rendering with
/// keyframe transforms, multi-clip composition export, and frame
/// extraction.
///
/// Thread Safety:
/// - `actor` ensures serial access to mutable state (active export session).
/// - All heavy processing runs via AVFoundation async APIs.
/// - Progress reporting via `AsyncStream`.
actor VideoProcessingService {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "VideoProcessingService")

    // MARK: - Properties

    /// Currently active export session (for cancel support).
    private var activeExportSession: AVAssetExportSession?

    /// Active export monitoring task.
    private var progressMonitorTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Export Cancel

    /// Cancel the currently active export session.
    func cancelExport() {
        activeExportSession?.cancelExport()
        progressMonitorTask?.cancel()
        progressMonitorTask = nil
        activeExportSession = nil
    }

    // MARK: - Thumbnail Generation

    /// Generate a single thumbnail image from a video file.
    ///
    /// - Parameter inputPath: Path to the video file.
    /// - Returns: PNG image data of the thumbnail.
    nonisolated func generateThumbnail(inputPath: String) async throws -> Data {
        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVAsset(url: inputURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = VideoConstants.thumbnailMaxSize

        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        let time = CMTime(
            seconds: VideoConstants.defaultThumbnailTimeOffset,
            preferredTimescale: VideoConstants.preferredTimescale
        )

        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)

        if let pngData = uiImage.pngData() {
            return pngData
        } else if let jpegData = uiImage.jpegData(compressionQuality: 1.0) {
            return jpegData
        } else {
            throw VideoProcessingError.thumbnailFailed("Could not encode image")
        }
    }

    /// Generate multiple thumbnails at specified timestamps for timeline scrubbing.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the video file.
    ///   - timestampsMs: Array of timestamps in milliseconds.
    /// - Returns: Array of (timestampMs, base64-encoded JPEG) tuples.
    nonisolated func generateTimelineThumbnails(
        inputPath: String,
        timestampsMs: [Int]
    ) async -> [(timestampMs: Int, base64: String)] {
        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVAsset(url: inputURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = VideoConstants.timelineThumbnailMaxSize

        let tolerance = CMTime(
            seconds: VideoConstants.timelineThumbnailTolerance,
            preferredTimescale: VideoConstants.preferredTimescale
        )
        imageGenerator.requestedTimeToleranceBefore = tolerance
        imageGenerator.requestedTimeToleranceAfter = tolerance

        var thumbnails: [(timestampMs: Int, base64: String)] = []

        for ms in timestampsMs {
            let time = CMTime(value: CMTimeValue(ms), timescale: 1000)
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                if let jpegData = uiImage.jpegData(
                    compressionQuality: VideoConstants.timelineThumbnailCompressionQuality
                ) {
                    let base64 = jpegData.base64EncodedString()
                    thumbnails.append((timestampMs: ms, base64: base64))
                }
            } catch {
                Self.logger.debug("Failed to generate thumbnail at \(ms)ms: \(error.localizedDescription, privacy: .public)")
            }
        }

        return thumbnails
    }

    // MARK: - Proxy Generation

    /// Generate a 1080p proxy video for faster processing.
    ///
    /// Returns the path to the proxy file. If a proxy already exists
    /// for this file, returns the existing path immediately.
    ///
    /// - Parameter inputPath: Path to the original video file.
    /// - Returns: Path to the proxy video file.
    func generateProxy(inputPath: String) async throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw VideoProcessingError.fileNotFound(inputPath)
        }

        let filename = inputURL.lastPathComponent
        let proxyFilename = VideoConstants.proxyFilePrefix + filename
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(proxyFilename)

        // Return existing proxy if already generated
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL.path
        }

        let asset = AVAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            throw VideoProcessingError.exportInitFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL.path)
                case .failed:
                    continuation.resume(throwing: VideoProcessingError.exportFailed(
                        exportSession.error?.localizedDescription ?? "Unknown error"
                    ))
                case .cancelled:
                    continuation.resume(throwing: VideoProcessingError.exportCancelled)
                default:
                    continuation.resume(throwing: VideoProcessingError.exportUnknownStatus(
                        exportSession.status.rawValue
                    ))
                }
            }
        }
    }

    // MARK: - Video Rendering

    /// Render a single video with keyframe transforms applied.
    ///
    /// Builds an AVMutableComposition with the source video, applies
    /// keyframe transform ramps via AVMutableVideoCompositionLayerInstruction,
    /// and exports to a temporary .mp4 file.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the source video.
    ///   - keyframes: Array of keyframe transforms.
    ///   - targetWidth: Target output width (nil to use source width).
    ///   - targetHeight: Target output height (nil to use source height).
    ///   - fps: Frames per second for output.
    ///   - bitrateMbps: Target bitrate in Mbps.
    ///   - audioOnly: If true, export audio only.
    ///   - enableHdr: If true, enable HDR output.
    /// - Returns: An AsyncStream yielding progress updates, with the final
    ///   element containing the output path on success.
    func renderVideo(
        inputPath: String,
        keyframes: [KeyframeTransform],
        targetWidth: Int?,
        targetHeight: Int?,
        fps: Int = VideoConstants.defaultExportFps,
        bitrateMbps: Double = VideoConstants.defaultExportBitrateMbps,
        audioOnly: Bool = false,
        enableHdr: Bool = false
    ) -> AsyncStream<ExportProgress> {
        let exportId = UUID().uuidString
        let startedAt = Date()

        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    let result = try await self.performRenderVideo(
                        inputPath: inputPath,
                        keyframes: keyframes,
                        targetWidth: targetWidth,
                        targetHeight: targetHeight,
                        fps: fps,
                        bitrateMbps: bitrateMbps,
                        audioOnly: audioOnly,
                        enableHdr: enableHdr,
                        exportId: exportId,
                        startedAt: startedAt,
                        continuation: continuation
                    )

                    // Final success progress
                    let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                    continuation.yield(ExportProgress(
                        exportId: exportId,
                        phase: .completed,
                        overallProgress: 1.0,
                        startedAt: startedAt,
                        elapsedMs: elapsed
                    ))
                    _ = result // suppress unused warning
                } catch {
                    let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                    continuation.yield(ExportProgress(
                        exportId: exportId,
                        phase: .failed,
                        overallProgress: 0.0,
                        startedAt: startedAt,
                        elapsedMs: elapsed
                    ))
                }
                continuation.finish()
            }
        }
    }

    /// Internal render implementation.
    private func performRenderVideo(
        inputPath: String,
        keyframes: [KeyframeTransform],
        targetWidth: Int?,
        targetHeight: Int?,
        fps: Int,
        bitrateMbps: Double,
        audioOnly: Bool,
        enableHdr: Bool,
        exportId: String,
        startedAt: Date,
        continuation: AsyncStream<ExportProgress>.Continuation
    ) async throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)
        let asset = AVAsset(url: inputURL)
        let duration = asset.duration

        if audioOnly {
            return try await exportAudioOnly(
                asset: asset,
                duration: duration,
                exportId: exportId,
                startedAt: startedAt,
                continuation: continuation
            )
        }

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoProcessingError.noVideoTrack
        }

        // Create transform calculator
        var outputSize: CGSize?
        if let w = targetWidth, let h = targetHeight, w > 0, h > 0 {
            outputSize = CGSize(width: Double(w), height: Double(h))
        }
        let transformCalculator = VideoTransformCalculator(videoTrack: videoTrack, outputSize: outputSize)
        let finalOutputSize = transformCalculator.outputSize

        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoProcessingError.compositionTrackFailed
        }

        do {
            try compTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack,
                at: .zero
            )
        } catch {
            throw VideoProcessingError.insertFailed(error.localizedDescription)
        }

        // Add audio track if present
        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let compAudioTrack = composition.addMutableTrack(
               withMediaType: .audio,
               preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)

        // Apply keyframe transforms
        if keyframes.isEmpty {
            let identityTransform = transformCalculator.createTransform(sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0)
            layerInstruction.setTransform(identityTransform, at: .zero)
        } else {
            for kf in keyframes {
                let start = CMTime(value: CMTimeValue(kf.startTimeMs), timescale: 1000)
                let end = CMTime(value: CMTimeValue(kf.endTimeMs), timescale: 1000)
                let range = CMTimeRange(start: start, duration: end - start)

                let startTransform = transformCalculator.createTransform(
                    sx: kf.sx, sy: kf.sy, tx: kf.tx, ty: kf.ty, rotation: kf.rotation
                )
                let endTransform = transformCalculator.createTransform(
                    sx: kf.esx, sy: kf.esy, tx: kf.etx, ty: kf.ety, rotation: kf.erotation
                )

                layerInstruction.setTransformRamp(
                    fromStart: startTransform,
                    toEnd: endTransform,
                    timeRange: range
                )
            }
        }

        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = finalOutputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        videoComposition.instructions = [instruction]

        if enableHdr {
            videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
            videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        }

        let filename = VideoConstants.renderedFilePrefix + UUID().uuidString + ".mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let exportPreset = Self.selectExportPreset(
            width: Int(finalOutputSize.width),
            height: Int(finalOutputSize.height),
            bitrateMbps: bitrateMbps,
            enableHdr: enableHdr
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: exportPreset
        ) else {
            throw VideoProcessingError.exportInitFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        let durationSec = CMTimeGetSeconds(duration)
        if durationSec > 0 && bitrateMbps > 0 {
            let estimatedBytes = Int64(
                bitrateMbps * durationSec / 8.0 * 1024.0 * 1024.0 * VideoConstants.fileSizeEstimateMultiplier
            )
            exportSession.fileLengthLimit = estimatedBytes
        }

        self.activeExportSession = exportSession

        // Start progress monitoring
        let monitorTask = Task {
            while !Task.isCancelled {
                let progress = Double(self.activeExportSession?.progress ?? 0)
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                let estimatedRemaining: Int? = progress > 0.05
                    ? Int(Double(elapsed) / progress * (1.0 - progress))
                    : nil

                continuation.yield(ExportProgress(
                    exportId: exportId,
                    phase: .rendering,
                    overallProgress: progress,
                    startedAt: startedAt,
                    elapsedMs: elapsed,
                    estimatedRemainingMs: estimatedRemaining
                ))

                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
        self.progressMonitorTask = monitorTask

        return try await withCheckedThrowingContinuation { innerContinuation in
            exportSession.exportAsynchronously { [weak self] in
                monitorTask.cancel()
                Task { await self?.clearActiveSession() }

                switch exportSession.status {
                case .completed:
                    innerContinuation.resume(returning: outputURL.path)
                case .failed:
                    innerContinuation.resume(throwing: VideoProcessingError.exportFailed(
                        exportSession.error?.localizedDescription ?? "Unknown error"
                    ))
                case .cancelled:
                    innerContinuation.resume(throwing: VideoProcessingError.exportCancelled)
                default:
                    innerContinuation.resume(throwing: VideoProcessingError.exportUnknownStatus(
                        exportSession.status.rawValue
                    ))
                }
            }
        }
    }

    // MARK: - Composition Rendering (Multi-clip)

    /// Render a multi-clip composition with per-clip keyframe transforms.
    ///
    /// Inserts each clip segment into a composition and applies keyframe
    /// transform ramps per clip. Uses standard AVMutableVideoCompositionLayerInstruction
    /// for efficient GPU-accelerated transform ramps.
    ///
    /// - Parameters:
    ///   - videoPath: Path to the source video.
    ///   - clips: Array of clip segments to compose.
    ///   - targetWidth: Target output width (nil to use source width).
    ///   - targetHeight: Target output height (nil to use source height).
    ///   - fps: Frames per second for output.
    ///   - bitrateMbps: Target bitrate in Mbps.
    ///   - audioOnly: If true, export audio only.
    ///   - enableHdr: If true, enable HDR output.
    /// - Returns: AsyncStream yielding ExportProgress updates.
    func renderComposition(
        videoPath: String,
        clips: [ClipSegment],
        targetWidth: Int?,
        targetHeight: Int?,
        fps: Int = VideoConstants.defaultExportFps,
        bitrateMbps: Double = VideoConstants.defaultExportBitrateMbps,
        audioOnly: Bool = false,
        enableHdr: Bool = false
    ) -> AsyncStream<ExportProgress> {
        let exportId = UUID().uuidString
        let startedAt = Date()

        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    try await self.performRenderComposition(
                        videoPath: videoPath,
                        clips: clips,
                        targetWidth: targetWidth,
                        targetHeight: targetHeight,
                        fps: fps,
                        bitrateMbps: bitrateMbps,
                        audioOnly: audioOnly,
                        enableHdr: enableHdr,
                        exportId: exportId,
                        startedAt: startedAt,
                        continuation: continuation
                    )

                    let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                    continuation.yield(ExportProgress(
                        exportId: exportId,
                        phase: .completed,
                        overallProgress: 1.0,
                        startedAt: startedAt,
                        elapsedMs: elapsed
                    ))
                } catch {
                    let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                    continuation.yield(ExportProgress(
                        exportId: exportId,
                        phase: .failed,
                        overallProgress: 0.0,
                        startedAt: startedAt,
                        elapsedMs: elapsed
                    ))
                }
                continuation.finish()
            }
        }
    }

    /// Internal composition render implementation.
    private func performRenderComposition(
        videoPath: String,
        clips: [ClipSegment],
        targetWidth: Int?,
        targetHeight: Int?,
        fps: Int,
        bitrateMbps: Double,
        audioOnly: Bool,
        enableHdr: Bool,
        exportId: String,
        startedAt: Date,
        continuation: AsyncStream<ExportProgress>.Continuation
    ) async throws {
        let inputURL = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: inputURL)

        guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
            throw VideoProcessingError.noVideoTrack
        }

        let sourceAudioTrack = asset.tracks(withMediaType: .audio).first

        // Create transform calculator
        var outputSize: CGSize?
        if let w = targetWidth, let h = targetHeight, w > 0, h > 0 {
            outputSize = CGSize(width: Double(w), height: Double(h))
        }
        let transformCalculator = VideoTransformCalculator(
            videoTrack: sourceVideoTrack,
            outputSize: outputSize
        )
        let finalOutputSize = transformCalculator.outputSize

        // Create composition
        let composition = AVMutableComposition()

        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoProcessingError.compositionTrackFailed
        }

        let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        // Build composition by inserting each clip segment
        var timelineTime = CMTime.zero
        var clipInstructions: [(CMTimeRange, [KeyframeTransform])] = []

        for clip in clips {
            let sourceStart = CMTime(value: CMTimeValue(clip.sourceInPointMs), timescale: 1000)
            let sourceEnd = CMTime(value: CMTimeValue(clip.sourceOutPointMs), timescale: 1000)
            let clipDuration = CMTimeSubtract(sourceEnd, sourceStart)
            let sourceTimeRange = CMTimeRange(start: sourceStart, duration: clipDuration)

            // Insert video segment
            do {
                try compVideoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: timelineTime)
            } catch {
                Self.logger.warning("Failed to insert video segment: \(error.localizedDescription, privacy: .public)")
                continue
            }

            // Insert audio segment
            if let srcAudio = sourceAudioTrack, let compAudio = compAudioTrack {
                try? compAudio.insertTimeRange(sourceTimeRange, of: srcAudio, at: timelineTime)
            }

            let timelineRange = CMTimeRange(start: timelineTime, duration: clipDuration)
            clipInstructions.append((timelineRange, clip.keyframes))

            timelineTime = CMTimeAdd(timelineTime, clipDuration)
        }

        let totalDuration = timelineTime

        if audioOnly {
            _ = try await exportCompositionAudioOnly(
                composition: composition,
                duration: totalDuration,
                exportId: exportId,
                startedAt: startedAt,
                continuation: continuation
            )
            return
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = finalOutputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        // Standard layer instruction path with transform ramps
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)

        for (timelineRange, keyframes) in clipInstructions {
            if keyframes.isEmpty {
                let identityTransform = transformCalculator.createTransform(
                    sx: 1.0, sy: 1.0, tx: 0.0, ty: 0.0
                )
                layerInstruction.setTransform(identityTransform, at: timelineRange.start)
            } else {
                for kf in keyframes {
                    // Keyframe times are relative to clip start
                    let kfStart = CMTimeAdd(
                        timelineRange.start,
                        CMTime(value: CMTimeValue(kf.startTimeMs), timescale: 1000)
                    )
                    let kfEnd = CMTimeAdd(
                        timelineRange.start,
                        CMTime(value: CMTimeValue(kf.endTimeMs), timescale: 1000)
                    )

                    // Clamp to clip range
                    let clampedStart = max(kfStart, timelineRange.start)
                    let clampedEnd = min(kfEnd, CMTimeAdd(timelineRange.start, timelineRange.duration))

                    guard CMTimeCompare(clampedStart, clampedEnd) < 0 else { continue }

                    let kfRange = CMTimeRange(
                        start: clampedStart,
                        duration: CMTimeSubtract(clampedEnd, clampedStart)
                    )

                    let startTransform = transformCalculator.createTransform(
                        sx: kf.sx, sy: kf.sy, tx: kf.tx, ty: kf.ty, rotation: kf.rotation
                    )
                    let endTransform = transformCalculator.createTransform(
                        sx: kf.esx, sy: kf.esy, tx: kf.etx, ty: kf.ety, rotation: kf.erotation
                    )

                    layerInstruction.setTransformRamp(
                        fromStart: startTransform,
                        toEnd: endTransform,
                        timeRange: kfRange
                    )
                }
            }
        }

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        if enableHdr {
            videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
            videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        }

        // Export
        let filename = VideoConstants.compositionFilePrefix + UUID().uuidString + ".mp4"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let exportPreset = Self.selectExportPreset(
            width: Int(finalOutputSize.width),
            height: Int(finalOutputSize.height),
            bitrateMbps: bitrateMbps,
            enableHdr: enableHdr
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: exportPreset
        ) else {
            throw VideoProcessingError.exportInitFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        let durationSec = CMTimeGetSeconds(totalDuration)
        if durationSec > 0 && bitrateMbps > 0 {
            let estimatedBytes = Int64(
                bitrateMbps * durationSec / 8.0 * 1024.0 * 1024.0 * VideoConstants.fileSizeEstimateMultiplier
            )
            exportSession.fileLengthLimit = estimatedBytes
        }

        self.activeExportSession = exportSession

        let monitorTask = Task {
            while !Task.isCancelled {
                let progress = Double(self.activeExportSession?.progress ?? 0)
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
                let estimatedRemaining: Int? = progress > 0.05
                    ? Int(Double(elapsed) / progress * (1.0 - progress))
                    : nil

                continuation.yield(ExportProgress(
                    exportId: exportId,
                    phase: .rendering,
                    overallProgress: progress,
                    startedAt: startedAt,
                    elapsedMs: elapsed,
                    estimatedRemainingMs: estimatedRemaining
                ))

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        self.progressMonitorTask = monitorTask

        try await withCheckedThrowingContinuation { (innerContinuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously { [weak self] in
                monitorTask.cancel()
                Task { await self?.clearActiveSession() }

                switch exportSession.status {
                case .completed:
                    innerContinuation.resume()
                case .failed:
                    innerContinuation.resume(throwing: VideoProcessingError.exportFailed(
                        exportSession.error?.localizedDescription ?? "Unknown error"
                    ))
                case .cancelled:
                    innerContinuation.resume(throwing: VideoProcessingError.exportCancelled)
                default:
                    innerContinuation.resume(throwing: VideoProcessingError.exportUnknownStatus(
                        exportSession.status.rawValue
                    ))
                }
            }
        }
    }

    // MARK: - Frame Extraction

    /// Extract the first frame from a video file.
    ///
    /// - Parameter videoPath: Path to the source video.
    /// - Returns: PNG image data of the first frame.
    nonisolated func extractFirstFrame(videoPath: String) async throws -> Data {
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = CMTime(value: 0, timescale: 1)
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)

        guard let pngData = uiImage.pngData() else {
            throw VideoProcessingError.conversionFailed("Failed to convert to PNG")
        }

        return pngData
    }

    /// Extract a frame at a specific progress (0.0-1.0) from a video file.
    ///
    /// Uses lower resolution and JPEG encoding for fast live preview
    /// during export.
    ///
    /// - Parameters:
    ///   - videoPath: Path to the source video.
    ///   - progress: Progress value from 0.0 to 1.0.
    /// - Returns: JPEG image data.
    nonisolated func extractFrameAtProgress(videoPath: String, progress: Double) async throws -> Data {
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let tolerance = CMTime(
            seconds: VideoConstants.previewFrameTolerance,
            preferredTimescale: VideoConstants.preferredTimescale
        )
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        generator.maximumSize = VideoConstants.previewFrameMaxSize

        let duration = asset.duration
        let clampedProgress = min(max(progress, 0.0), 1.0)
        let seconds = CMTimeGetSeconds(duration) * clampedProgress
        let time = CMTime(seconds: seconds, preferredTimescale: VideoConstants.preferredTimescale)

        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)

        guard let jpegData = uiImage.jpegData(
            compressionQuality: VideoConstants.previewFrameCompressionQuality
        ) else {
            throw VideoProcessingError.conversionFailed("Failed to convert to JPEG")
        }

        return jpegData
    }

    // MARK: - Frame Grab (Screenshot)

    /// Extract a single frame from a video at a specified time.
    ///
    /// Returns both the JPEG data and a path to the saved file,
    /// along with dimensions.
    ///
    /// - Parameters:
    ///   - videoPath: Path to the source video file.
    ///   - timeSeconds: Time offset in seconds to grab the frame from.
    ///   - maxWidth: Optional maximum width for the output image.
    ///   - maxHeight: Optional maximum height for the output image.
    /// - Returns: Frame grab result with path, data, and dimensions.
    nonisolated func grabFrame(
        videoPath: String,
        timeSeconds: Double,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) async throws -> (path: String, data: Data, width: Int, height: Int) {
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let tolerance = CMTime(
            seconds: VideoConstants.frameGrabTolerance,
            preferredTimescale: VideoConstants.preferredTimescale
        )
        imageGenerator.requestedTimeToleranceBefore = tolerance
        imageGenerator.requestedTimeToleranceAfter = tolerance

        if let w = maxWidth, let h = maxHeight, w > 0, h > 0 {
            imageGenerator.maximumSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        }

        let requestedTime = CMTime(
            seconds: timeSeconds,
            preferredTimescale: VideoConstants.preferredTimescale
        )

        let cgImage = try imageGenerator.copyCGImage(at: requestedTime, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)

        guard let jpegData = uiImage.jpegData(
            compressionQuality: VideoConstants.frameGrabCompressionQuality
        ) else {
            throw VideoProcessingError.conversionFailed("Could not encode JPEG")
        }

        let filename = VideoConstants.frameGrabFilePrefix + UUID().uuidString + ".jpg"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try jpegData.write(to: outputURL)

        return (
            path: outputURL.path,
            data: jpegData,
            width: cgImage.width,
            height: cgImage.height
        )
    }

    // MARK: - Export Preset Selection

    /// Select appropriate export preset based on resolution and settings.
    ///
    /// - Parameters:
    ///   - width: Output width in pixels.
    ///   - height: Output height in pixels.
    ///   - bitrateMbps: Target bitrate.
    ///   - enableHdr: Whether HDR is enabled.
    /// - Returns: AVAssetExportSession preset name.
    nonisolated static func selectExportPreset(
        width: Int,
        height: Int,
        bitrateMbps: Double,
        enableHdr: Bool
    ) -> String {
        if enableHdr {
            if width >= VideoConstants.resolution4KWidth
                || height >= VideoConstants.resolution4KHeight {
                return AVAssetExportPresetHEVC3840x2160
            } else if width >= VideoConstants.resolution1080pWidth
                || height >= VideoConstants.resolution1080pHeight {
                return AVAssetExportPresetHEVC1920x1080
            }
        }

        if width >= VideoConstants.resolution4KWidth
            || height >= VideoConstants.resolution4KHeight {
            return AVAssetExportPresetHighestQuality
        } else if width >= VideoConstants.resolution1080pWidth
            || height >= VideoConstants.resolution1080pHeight {
            if bitrateMbps >= VideoConstants.highBitrateThreshold {
                return AVAssetExportPresetHighestQuality
            }
            return AVAssetExportPreset1920x1080
        } else if width >= VideoConstants.resolution720pWidth
            || height >= VideoConstants.resolution720pHeight {
            return AVAssetExportPreset1280x720
        } else {
            return AVAssetExportPreset960x540
        }
    }

    // MARK: - Audio Export

    /// Export audio only from an asset.
    private func exportAudioOnly(
        asset: AVAsset,
        duration: CMTime,
        exportId: String,
        startedAt: Date,
        continuation: AsyncStream<ExportProgress>.Continuation
    ) async throws -> String {
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw VideoProcessingError.noAudioTrack
        }

        let composition = AVMutableComposition()
        guard let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoProcessingError.compositionTrackFailed
        }

        try compAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: audioTrack,
            at: .zero
        )

        let filename = VideoConstants.audioFilePrefix + UUID().uuidString + ".m4a"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VideoProcessingError.exportInitFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        self.activeExportSession = exportSession

        let monitorTask = Task {
            while !Task.isCancelled {
                let progress = Double(self.activeExportSession?.progress ?? 0)
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)

                continuation.yield(ExportProgress(
                    exportId: exportId,
                    phase: .encoding,
                    overallProgress: progress,
                    startedAt: startedAt,
                    elapsedMs: elapsed
                ))

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        defer {
            monitorTask.cancel()
            self.activeExportSession = nil
        }

        return try await withCheckedThrowingContinuation { innerContinuation in
            exportSession.exportAsynchronously {
                monitorTask.cancel()
                switch exportSession.status {
                case .completed:
                    innerContinuation.resume(returning: outputURL.path)
                case .failed:
                    innerContinuation.resume(throwing: VideoProcessingError.exportFailed(
                        exportSession.error?.localizedDescription ?? "Unknown error"
                    ))
                case .cancelled:
                    innerContinuation.resume(throwing: VideoProcessingError.exportCancelled)
                default:
                    innerContinuation.resume(throwing: VideoProcessingError.exportUnknownStatus(
                        exportSession.status.rawValue
                    ))
                }
            }
        }
    }

    /// Export audio only from a composition.
    private func exportCompositionAudioOnly(
        composition: AVMutableComposition,
        duration: CMTime,
        exportId: String,
        startedAt: Date,
        continuation: AsyncStream<ExportProgress>.Continuation
    ) async throws -> String {
        let filename = VideoConstants.audioFilePrefix + UUID().uuidString + ".m4a"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VideoProcessingError.exportInitFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        self.activeExportSession = exportSession

        let monitorTask = Task {
            while !Task.isCancelled {
                let progress = Double(self.activeExportSession?.progress ?? 0)
                let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)

                continuation.yield(ExportProgress(
                    exportId: exportId,
                    phase: .encoding,
                    overallProgress: progress,
                    startedAt: startedAt,
                    elapsedMs: elapsed
                ))

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        defer {
            monitorTask.cancel()
            self.activeExportSession = nil
        }

        return try await withCheckedThrowingContinuation { innerContinuation in
            exportSession.exportAsynchronously {
                monitorTask.cancel()
                switch exportSession.status {
                case .completed:
                    innerContinuation.resume(returning: outputURL.path)
                case .failed:
                    innerContinuation.resume(throwing: VideoProcessingError.exportFailed(
                        exportSession.error?.localizedDescription ?? "Unknown error"
                    ))
                case .cancelled:
                    innerContinuation.resume(throwing: VideoProcessingError.exportCancelled)
                default:
                    innerContinuation.resume(throwing: VideoProcessingError.exportUnknownStatus(
                        exportSession.status.rawValue
                    ))
                }
            }
        }
    }

    // MARK: - Audio Session Configuration

    /// Configure AVAudioSession for video editing.
    ///
    /// Sets up `.playAndRecord` category with video recording mode,
    /// default to speaker, Bluetooth support, and mix with others.
    @MainActor
    static func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try audioSession.setActive(true)

            Self.logger.info("Audio session configured successfully")
        } catch {
            Self.logger.error("Failed to configure audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internal Helpers

    /// Clear the active export session and monitor task.
    private func clearActiveSession() {
        activeExportSession = nil
        progressMonitorTask?.cancel()
        progressMonitorTask = nil
    }
}
