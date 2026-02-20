// ExportProgressReporter.swift
// LiquidEditor
//
// Structured progress reporting for export operations.
// Phase-based progress with ETA estimation and system metrics.
// Uses AsyncStream for structured concurrency integration.

import AVFoundation
import Foundation

// MARK: - ExportProgressReporter

/// Structured progress reporter for export operations.
///
/// Tracks export phases (preparing, rendering, encoding, finalizing),
/// estimates time remaining, and monitors system health (thermal state,
/// disk space).
///
/// Thread Safety:
/// - All mutable state is accessed on a serial queue.
/// - Progress is emitted via `AsyncStream` for safe consumption.
final class ExportProgressReporter: @unchecked Sendable {

    // MARK: - Properties

    /// Minimum progress threshold for ETA calculation.
    private static let minProgressForETA: Double = 0.01

    /// Lock protecting mutable state.
    private let lock = NSLock()

    /// When the export started.
    private var startTime: Date?

    /// Total number of frames expected.
    private var totalFrames: Int = 0

    /// The export identifier.
    private var exportId: String = ""

    /// Current phase of the export.
    private var currentPhase: ExportPhase = .preparing

    /// AsyncStream continuation for emitting progress.
    private var continuation: AsyncStream<ExportProgress>.Continuation?

    // MARK: - Lifecycle

    deinit {
        // Ensure continuation is finished on cleanup
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }

    /// Begin tracking progress for an export.
    ///
    /// - Parameters:
    ///   - exportId: Unique identifier for this export.
    ///   - totalFrames: Estimated total frames (duration * fps).
    /// - Returns: An `AsyncStream<ExportProgress>` for consuming progress updates.
    func startTracking(exportId: String, totalFrames: Int) -> AsyncStream<ExportProgress> {
        precondition(totalFrames > 0, "totalFrames must be positive")

        lock.lock()
        self.exportId = exportId
        self.totalFrames = totalFrames
        self.startTime = Date()
        self.currentPhase = .preparing
        lock.unlock()

        return AsyncStream { [weak self] continuation in
            self?.lock.lock()
            self?.continuation = continuation
            self?.lock.unlock()
        }
    }

    /// Update the current phase.
    func setPhase(_ phase: ExportPhase) {
        lock.lock()
        currentPhase = phase
        lock.unlock()
    }

    /// Report progress from an AVAssetExportSession.
    ///
    /// - Parameters:
    ///   - session: The active export session.
    ///   - framesRendered: Estimated frames rendered so far.
    func reportProgress(
        session: AVAssetExportSession?,
        framesRendered: Int = 0
    ) {
        lock.lock()
        let total = totalFrames
        lock.unlock()

        let progress = session?.progress ?? Float(framesRendered) / Float(max(total, 1))
        reportProgressValue(
            progress: Double(progress),
            framesRendered: framesRendered
        )
    }

    /// Report raw progress value.
    ///
    /// - Parameters:
    ///   - progress: Progress from 0.0 to 1.0.
    ///   - framesRendered: Number of frames rendered so far.
    ///   - bytesWritten: Bytes written to output so far.
    func reportProgressValue(
        progress: Double,
        framesRendered: Int = 0,
        bytesWritten: Int64 = 0
    ) {
        // Clamp progress to valid range
        let clampedProgress = min(max(progress, 0.0), 1.0)

        lock.lock()
        let start = startTime ?? Date()
        let phase = currentPhase
        let id = exportId
        let total = totalFrames
        let cont = continuation
        lock.unlock()

        let elapsed = Date().timeIntervalSince(start)

        // ETA calculation
        var estimatedRemainingMs: Int?
        if clampedProgress > Self.minProgressForETA {
            let totalEstimated = elapsed / clampedProgress
            let remaining = totalEstimated - elapsed
            estimatedRemainingMs = Int(remaining * 1000)
        }

        // Estimate total bytes
        let estimatedTotalBytes: Int
        if bytesWritten > 0 && clampedProgress > Self.minProgressForETA {
            estimatedTotalBytes = Int(Double(bytesWritten) / clampedProgress)
        } else {
            estimatedTotalBytes = 0
        }

        let update = ExportProgress(
            exportId: id,
            phase: phase,
            overallProgress: clampedProgress,
            framesRendered: framesRendered,
            totalFrames: total,
            bytesWritten: Int(bytesWritten),
            estimatedTotalBytes: estimatedTotalBytes,
            startedAt: start,
            elapsedMs: Int(elapsed * 1000),
            estimatedRemainingMs: estimatedRemainingMs,
            thermalState: BackgroundExportService.thermalStateInt,
            availableDiskMB: BackgroundExportService.availableDiskSpaceMB()
        )

        cont?.yield(update)
    }

    /// Report export completion.
    func reportComplete() {
        lock.lock()
        currentPhase = .completed
        let cont = continuation
        lock.unlock()

        reportProgressValue(progress: 1.0, framesRendered: totalFrames)
        cont?.finish()
    }

    /// Report export failure.
    func reportFailed(error: String) {
        lock.lock()
        currentPhase = .failed
        let cont = continuation
        let id = exportId
        lock.unlock()

        let update = ExportProgress(
            exportId: id,
            phase: .failed,
            overallProgress: -1.0,
            startedAt: startTime ?? Date(),
            elapsedMs: 0
        )

        cont?.yield(update)
        cont?.finish()
    }

    /// Stop tracking and clean up.
    func stopTracking() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()

        cont?.finish()
    }
}
