// ExportViewModel.swift
// LiquidEditor
//
// ViewModel for export configuration and progress tracking.

import Foundation
import SwiftUI
import os

// MARK: - ExportState

/// Current state of the export operation.
enum ExportState: Sendable {
    case idle
    case preparing
    case exporting
    case complete(outputURL: URL)
    case failed(message: String)
}

// MARK: - ExportViewModel

@Observable
@MainActor
final class ExportViewModel {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "ExportViewModel"
    )

    // MARK: - Configuration Constants

    /// Reference duration for file size estimation (60 seconds).
    private static let referenceDurationSeconds: Double = 60.0

    /// Reference pixel count for size scaling (1080p).
    private static let referencePixels: Double = 1920.0 * 1080.0

    /// Codec complexity multipliers (relative to real-time).
    private static let codecMultipliers: [ExportCodec: Double] = [
        .h264: 1.0,
        .h265: 1.5,
        .proRes: 0.5
    ]

    /// Resolution scaling factors for export time.
    private static let resolutionScalingFactors: [ExportResolution: Double] = [
        .r720p: 0.6,
        .r1080p: 1.0,
        .r4K: 2.0
    ]

    // MARK: - Published State

    /// Current export configuration.
    var config = ExportConfig()

    /// Whether an export is currently in progress.
    var isExporting = false

    /// Export progress from 0.0 to 1.0.
    var progress: Double = 0.0

    /// Current export state.
    var exportState: ExportState = .idle

    /// Error message if export failed.
    var errorMessage: String?

    /// Timeline duration in microseconds, for estimated export time calculation.
    var timelineDurationMicros: TimeMicros = 0

    /// The active export handle, if any.
    private var activeExportHandle: ExportHandle?

    /// The export service to delegate work to.
    private let exportService: (any ExportServiceProtocol)?

    // MARK: - Resolution Presets

    /// Available resolution presets for the picker.
    static let resolutionPresets: [ExportResolution] = [.r720p, .r1080p, .r4K]

    /// Available FPS options.
    static let fpsOptions: [Int] = [24, 30, 60]

    // MARK: - Init

    init(exportService: (any ExportServiceProtocol)? = nil) {
        self.exportService = exportService
    }

    // MARK: - Computed Properties

    /// Estimated file size string based on current config.
    var estimatedFileSize: String {
        let width = config.outputWidth
        let height = config.outputHeight
        let pixels = Double(width * height)
        let bitrate = config.effectiveBitrateMbps * 1_000_000.0 // bits per second
        let durationSeconds = Self.referenceDurationSeconds
        let sizeBytes = (bitrate * durationSeconds) / 8.0
        let sizeMB = sizeBytes / (1024.0 * 1024.0)

        // Scale by pixel count relative to 1080p reference.
        let scaleFactor = pixels / Self.referencePixels

        let adjustedMB = sizeMB * scaleFactor
        if adjustedMB >= 1024 {
            return String(format: "~%.1f GB/min", adjustedMB / 1024.0)
        }
        return String(format: "~%.0f MB/min", adjustedMB)
    }

    /// Estimated export duration based on timeline duration, codec, and resolution.
    ///
    /// Uses complexity multipliers defined in `codecMultipliers` dictionary.
    /// Higher resolutions scale export time proportionally.
    var estimatedDuration: String {
        let timelineDurationSec = Double(timelineDurationMicros) / 1_000_000.0
        guard timelineDurationSec > 0 else { return "No content" }

        // Get codec complexity multiplier from configuration.
        let codecMultiplier = Self.codecMultipliers[config.codec] ?? 1.0

        // Calculate resolution scale relative to 1080p reference.
        let pixels = Double(config.outputWidth * config.outputHeight)
        let resolutionScale = max(pixels / Self.referencePixels, 0.5)

        let estimatedSeconds = timelineDurationSec * codecMultiplier * resolutionScale
        let rounded = Int(estimatedSeconds.rounded(.up))

        if rounded < 60 {
            return "~\(rounded)s"
        } else {
            let minutes = rounded / 60
            let seconds = rounded % 60
            return seconds > 0 ? "~\(minutes)m \(seconds)s" : "~\(minutes)m"
        }
    }

    /// Whether the export completed successfully.
    var isComplete: Bool {
        if case .complete = exportState { return true }
        return false
    }

    /// The output URL if export is complete.
    var completedOutputURL: URL? {
        if case .complete(let url) = exportState { return url }
        return nil
    }

    // MARK: - Actions

    /// Update the resolution preset.
    func updateResolution(_ resolution: ExportResolution) {
        config = config.with(resolution: resolution)
    }

    /// Update the video codec.
    func updateCodec(_ codec: ExportCodec) {
        config = config.with(codec: codec)
    }

    /// Update frames per second.
    func updateFPS(_ fps: Int) {
        config = config.with(fps: fps)
    }

    /// Update export quality.
    func updateQuality(_ quality: ExportQuality) {
        config = config.with(quality: quality)
    }

    /// Update container format.
    func updateFormat(_ format: ExportFormat) {
        config = config.with(format: format)
    }

    /// Start the export process.
    func startExport() async {
        guard !isExporting else {
            Self.logger.warning("startExport called while export already in progress")
            return
        }

        Self.logger.info("Starting export: \(String(describing: self.config.resolution)) @ \(self.config.fps)fps, codec=\(String(describing: self.config.codec))")
        isExporting = true
        progress = 0.0
        exportState = .preparing
        errorMessage = nil

        guard let service = exportService else {
            Self.logger.error("Export failed: service unavailable")
            exportState = .failed(message: "Export service unavailable")
            errorMessage = "Export service unavailable. Please try again."
            isExporting = false
            return
        }

        do {
            let handle = try await service.startExport(config: config)
            activeExportHandle = handle
            exportState = .exporting
            Self.logger.info("Export started with ID: \(handle.id)")

            for await progressUpdate in service.progressStream(exportId: handle.id) {
                progress = progressUpdate.overallProgress
                if progressUpdate.phase == .completed {
                    exportState = .complete(outputURL: handle.outputURL)
                    isExporting = false
                    Self.logger.info("Export completed: \(handle.outputURL.path)")
                    return
                }
                if progressUpdate.phase == .failed {
                    exportState = .failed(message: "Export failed")
                    errorMessage = "Export failed"
                    isExporting = false
                    Self.logger.error("Export failed during processing")
                    return
                }
            }
        } catch {
            Self.logger.error("Export error: \(error.localizedDescription)")
            exportState = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
            isExporting = false
        }
    }

    /// Cancel the current export.
    func cancelExport() async {
        guard isExporting, let handle = activeExportHandle else {
            Self.logger.warning("cancelExport called but no export is active")
            return
        }

        Self.logger.info("Canceling export with ID: \(handle.id)")
        if let service = exportService {
            do {
                try await service.cancelExport(exportId: handle.id)
                Self.logger.info("Export canceled successfully")
            } catch {
                Self.logger.error("Error during export cancellation: \(error.localizedDescription)")
            }
        }

        isExporting = false
        progress = 0.0
        exportState = .idle
        activeExportHandle = nil
    }

    /// Share the exported video via system share sheet.
    func shareExportedVideo() -> URL? {
        completedOutputURL
    }

    /// Reset to idle state for a new export.
    func reset() {
        isExporting = false
        progress = 0.0
        exportState = .idle
        errorMessage = nil
        activeExportHandle = nil
    }

}
