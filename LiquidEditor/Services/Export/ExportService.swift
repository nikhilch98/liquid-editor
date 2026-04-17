// ExportService.swift
// LiquidEditor
//
// Main export orchestrator. Manages the full export lifecycle:
// composition build -> render -> encode -> save.
// Uses AsyncStream for structured progress reporting.

import AVFoundation
import Foundation
import os

// MARK: - ExportResult

/// Result of a completed export operation.
struct ExportResult: Sendable {
    /// Path to the exported file.
    let outputPath: String

    /// Size of the exported file in bytes.
    let fileSizeBytes: Int64

    /// Total export duration.
    let elapsed: TimeInterval

    /// The export configuration used.
    let config: ExportConfig
}

// MARK: - ExportError

/// Errors that can occur during export.
enum ExportError: Error, Sendable {
    case invalidInput(String)
    case insufficientDiskSpace(available: Int, required: Int)
    case compositionBuildFailed(String)
    case exportSessionCreationFailed
    case exportFailed(String)
    case cancelled
    case thermalThrottling
    case backgroundTimeExpired
}

// MARK: - ExportService

/// Main export orchestrator managing the full video export lifecycle.
///
/// Thread Safety:
/// - `actor` ensures serial access to mutable state.
/// - Progress is reported via `AsyncStream` for structured concurrency.
///
/// Usage:
/// ```swift
/// let service = ExportService()
/// let job = ExportJob(...)
/// for await progress in service.export(job: job, sourceURL: url) {
///     print(progress.phase, progress.overallProgress)
/// }
/// ```
actor ExportService {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "ExportService"
    )

    // MARK: - State

    /// Currently active export session (for cancel support).
    private var activeSession: AVAssetExportSession?

    /// Currently active export job ID.
    private var activeJobId: String?

    /// Background export manager.
    private let backgroundService = BackgroundExportService()

    /// Whether a cancel has been requested.
    private var cancelRequested = false

    // MARK: - Export

    /// Export a video with the given job configuration.
    ///
    /// Returns an `AsyncStream` of `ExportProgress` updates. The stream
    /// completes when the export finishes (success or failure).
    ///
    /// - Parameters:
    ///   - job: The export job describing configuration and metadata.
    ///   - sourceURL: URL to the source video/composition.
    ///   - clips: Optional per-clip segment descriptors for multi-clip composition.
    /// - Returns: An `AsyncStream<ExportProgress>` emitting progress updates.
    func export(
        job: ExportJob,
        sourceURL: URL,
        clips: [CompositionSegment] = []
    ) -> AsyncStream<ExportProgress> {
        let config = job.config
        let jobId = job.id

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            Task {
                await self.performExport(
                    jobId: jobId,
                    config: config,
                    sourceURL: sourceURL,
                    clips: clips,
                    continuation: continuation
                )
            }
        }
    }

    /// Cancel the currently active export.
    func cancelExport() async {
        cancelRequested = true
        activeSession?.cancelExport()
        await backgroundService.endBackgroundExport()
        activeSession = nil
        activeJobId = nil
    }

    /// Whether an export is currently in progress.
    var isExporting: Bool {
        activeSession != nil
    }

    // MARK: - Internal Export Pipeline

    private func performExport(
        jobId: String,
        config: ExportConfig,
        sourceURL: URL,
        clips: [CompositionSegment],
        continuation: AsyncStream<ExportProgress>.Continuation
    ) async {
        cancelRequested = false
        activeJobId = jobId
        let startTime = Date()

        // Helper to emit progress
        func emit(phase: ExportPhase, progress: Double, frames: Int = 0, totalFrames: Int = 0) {
            let elapsed = Date().timeIntervalSince(startTime)
            let elapsedMs = Int(elapsed * 1000)
            var estimatedRemainingMs: Int?
            if progress > 0.01 {
                let totalEstimated = elapsed / progress
                estimatedRemainingMs = Int((totalEstimated - elapsed) * 1000)
            }

            let update = ExportProgress(
                exportId: jobId,
                phase: phase,
                overallProgress: progress,
                framesRendered: frames,
                totalFrames: totalFrames,
                bytesWritten: 0,
                estimatedTotalBytes: 0,
                startedAt: startTime,
                elapsedMs: elapsedMs,
                estimatedRemainingMs: estimatedRemainingMs,
                thermalState: BackgroundExportService.thermalStateInt,
                availableDiskMB: BackgroundExportService.availableDiskSpaceMB()
            )
            continuation.yield(update)
        }

        // Input validation: source file must exist
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            Self.logger.error("Export \(jobId, privacy: .public) failed: source file does not exist at \(sourceURL.path, privacy: .public)")
            emit(phase: .failed, progress: -1.0)
            continuation.finish()
            return
        }

        // Input validation: output directory must be writable
        let outputDir = FileManager.default.temporaryDirectory
        guard FileManager.default.isWritableFile(atPath: outputDir.path) else {
            Self.logger.error("Export \(jobId, privacy: .public) failed: output directory is not writable at \(outputDir.path, privacy: .public)")
            emit(phase: .failed, progress: -1.0)
            continuation.finish()
            return
        }

        // Input validation: config values are sane
        guard config.outputWidth > 0, config.outputHeight > 0 else {
            Self.logger.error("Export \(jobId, privacy: .public) failed: invalid resolution \(config.outputWidth)x\(config.outputHeight)")
            emit(phase: .failed, progress: -1.0)
            continuation.finish()
            return
        }

        guard config.fps > 0 else {
            Self.logger.error("Export \(jobId, privacy: .public) failed: invalid FPS \(config.fps)")
            emit(phase: .failed, progress: -1.0)
            continuation.finish()
            return
        }

        // Phase 1: Preparing
        emit(phase: .preparing, progress: 0.0)

        // Validate disk space
        let estimatedSizeMB = estimateOutputSize(config: config, sourceURL: sourceURL)
        if let diskError = BackgroundExportService.validateDiskSpace(estimatedSizeMB: estimatedSizeMB) {
            Self.logger.error("Export \(jobId, privacy: .public) failed disk space validation: \(diskError, privacy: .public)")
            emit(phase: .failed, progress: -1.0)
            continuation.finish()
            return
        }

        // Check thermal state
        if BackgroundExportService.isThermalConcern {
            Self.logger.warning("Thermal concern detected, proceeding with caution")
        }

        // Begin background task. If the concurrent-export cap is reached,
        // the service throws and we surface a failure instead of spawning
        // an unbounded Task.
        do {
            try await backgroundService.beginBackgroundExport(exportId: jobId)
        } catch {
            Self.logger.error("Export \(jobId, privacy: .public) rejected by background service: \(error.localizedDescription, privacy: .public)")
            emit(phase: .failed, progress: -1.0)
            continuation.finish()
            return
        }

        guard !cancelRequested else {
            await backgroundService.endBackgroundExport()
            emit(phase: .cancelled, progress: 0.0)
            continuation.finish()
            return
        }

        // Phase 2: Build composition
        emit(phase: .preparing, progress: 0.1)

        let asset = AVURLAsset(url: sourceURL)
        let outputURL = generateOutputURL(config: config)

        // Remove existing file at output path if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                Self.logger.error("Export \(jobId, privacy: .public): failed to remove existing file at \(outputURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                emit(phase: .failed, progress: -1.0)
                continuation.finish()
                return
            }
        }

        // Select export preset
        let preset = selectPreset(config: config)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: preset
        ) else {
            Self.logger.error("Export \(jobId, privacy: .public) failed: could not create AVAssetExportSession with preset \(preset, privacy: .public)")
            await backgroundService.endBackgroundExport()
            backgroundService.notifyExportFailed(reason: "Could not create export session")
            emit(phase: .failed, progress: -1.0)
            continuation.finish()
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType(for: config.format)
        exportSession.shouldOptimizeForNetworkUse = true

        // Configure HDR
        if config.enableHdr {
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(
                width: config.outputWidth,
                height: config.outputHeight
            )
            videoComposition.frameDuration = CMTime(
                value: 1,
                timescale: CMTimeScale(config.fps)
            )
            videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
            videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
            exportSession.videoComposition = videoComposition
        }

        // Apply file size limit based on bitrate
        let durationSec = CMTimeGetSeconds(asset.duration)
        if durationSec > 0 && config.effectiveBitrateMbps > 0 {
            let estimatedBytes = Int64(
                config.effectiveBitrateMbps * durationSec / 8.0 * 1024.0 * 1024.0 * 1.1
            )
            exportSession.fileLengthLimit = estimatedBytes
        }

        activeSession = exportSession

        // Phase 3: Rendering + Encoding
        emit(phase: .rendering, progress: 0.15)

        // Start progress monitoring
        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                let sessionProgress = self.getSessionProgress()
                let overallProgress = 0.15 + Double(sessionProgress) * 0.75
                let phase: ExportPhase = sessionProgress > 0.8 ? .encoding : .rendering
                emit(phase: phase, progress: overallProgress)

                if sessionProgress >= 1.0 { break }
            }
        }

        // Execute export
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                resume.resume()
            }
        }

        progressTask.cancel()
        activeSession = nil
        activeJobId = nil

        // Phase 4: Finalize
        switch exportSession.status {
        case .completed:
            emit(phase: .saving, progress: 0.95)

            // Get output file size
            let fileSize: Int64
            if let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
               let size = attrs[.size] as? Int64 {
                fileSize = size
            } else {
                fileSize = 0
            }

            await backgroundService.endBackgroundExport()
            backgroundService.notifyExportComplete(exportId: jobId)

            emit(phase: .completed, progress: 1.0)

        case .failed:
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            Self.logger.error("Export \(jobId, privacy: .public) AVAssetExportSession failed: \(errorMsg, privacy: .public)")
            await backgroundService.endBackgroundExport()
            backgroundService.notifyExportFailed(reason: errorMsg)
            emit(phase: .failed, progress: -1.0)

        case .cancelled:
            await backgroundService.endBackgroundExport()
            emit(phase: .cancelled, progress: 0.0)

        default:
            Self.logger.error("Export \(jobId, privacy: .public) ended in unexpected AVAssetExportSession status: \(exportSession.status.rawValue)")
            await backgroundService.endBackgroundExport()
            emit(phase: .failed, progress: -1.0)
        }

        continuation.finish()
    }

    // MARK: - Helpers

    /// Get the current session's export progress (0-1).
    private func getSessionProgress() -> Float {
        activeSession?.progress ?? 0
    }

    /// Generate a unique output URL based on configuration.
    private func generateOutputURL(config: ExportConfig) -> URL {
        let filename = "export_\(UUID().uuidString).\(config.format.fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    /// Estimate output file size in MB.
    private func estimateOutputSize(config: ExportConfig, sourceURL: URL) -> Int {
        let asset = AVURLAsset(url: sourceURL)
        let durationSec = CMTimeGetSeconds(asset.duration)
        guard durationSec > 0 else { return 100 }

        let bytesPerSecond = config.effectiveBitrateMbps * 1024.0 * 1024.0 / 8.0
        let estimatedBytes = bytesPerSecond * durationSec * 1.1
        return Int(estimatedBytes / (1024.0 * 1024.0))
    }

    /// Select AVAssetExportSession preset based on config.
    private func selectPreset(config: ExportConfig) -> String {
        let width = config.outputWidth
        let height = config.outputHeight

        if config.enableHdr {
            if width >= 3840 || height >= 2160 {
                return AVAssetExportPresetHEVC3840x2160
            } else if width >= 1920 || height >= 1080 {
                return AVAssetExportPresetHEVC1920x1080
            }
        }

        if width >= 3840 || height >= 2160 {
            return AVAssetExportPresetHighestQuality
        } else if width >= 1920 || height >= 1080 {
            if config.effectiveBitrateMbps >= 50.0 {
                return AVAssetExportPresetHighestQuality
            }
            return AVAssetExportPreset1920x1080
        } else if width >= 1280 || height >= 720 {
            return AVAssetExportPreset1280x720
        } else {
            return AVAssetExportPreset960x540
        }
    }

    /// Map ExportFormat to AVFileType.
    private func outputFileType(for format: ExportFormat) -> AVFileType {
        switch format {
        case .mp4: return .mp4
        case .mov: return .mov
        case .m4v: return .m4v
        }
    }
}
