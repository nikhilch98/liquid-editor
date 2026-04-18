// ExportCleanupCoordinator.swift
// LiquidEditor
//
// S2-23: Cancel-mid-render cleanup.
//
// When the user cancels an in-flight export, AVFoundation frequently leaves
// a partially-written output file behind and the job may still be tracked by
// the surrounding export-queue state. This coordinator is the single
// place that sweeps both: it removes the partial file, detaches the job from
// any queue-adjacent bookkeeping, and writes a concise os.log audit trail
// so we can forensically reconstruct why a file went away.
//
// It is intentionally narrow — it does NOT try to cancel the underlying
// AVAssetExportSession (ExportService owns that lifecycle); it just cleans
// up once cancellation has been requested/acknowledged.

import Foundation
import os

// MARK: - ExportCleanupCoordinator

/// Coordinates the post-cancel cleanup of a video export.
///
/// Usage:
/// ```swift
/// let coordinator = ExportCleanupCoordinator()
/// await coordinator.cleanupCancelledExport(jobId: job.id, partialFileURL: outputURL)
/// ```
@MainActor
final class ExportCleanupCoordinator {

    // MARK: - Logger

    nonisolated(unsafe) private static let logger = Logger(
        subsystem: "LiquidEditor",
        category: "ExportCleanupCoordinator"
    )

    // MARK: - Optional dependencies

    /// Optional hook invoked to detach the job from an active export queue.
    /// Declared as an async throwing closure so call-sites can delegate into
    /// `ExportService`'s actor without this coordinator taking a hard
    /// dependency on that type.
    typealias QueueDetachment = @Sendable (UUID) async throws -> Void

    private let queueDetachment: QueueDetachment?

    // MARK: - Init

    /// Create a coordinator.
    ///
    /// - Parameter queueDetachment: Optional hook for removing the job from
    ///   an external queue (e.g. `ExportService`). If nil, queue detachment
    ///   is skipped and the coordinator only cleans up local files.
    init(queueDetachment: QueueDetachment? = nil) {
        self.queueDetachment = queueDetachment
    }

    // MARK: - Cleanup

    /// Perform full post-cancel cleanup for the given export job.
    ///
    /// Steps:
    /// 1. Remove the partial output file (if any).
    /// 2. Remove the job from any active export queue via the injected hook.
    /// 3. Log each step to `os.log` at `.info` level; failures at `.error`.
    ///
    /// Never throws; a failed file removal is logged but does not propagate.
    ///
    /// - Parameters:
    ///   - jobId: Unique identifier of the cancelled job.
    ///   - partialFileURL: URL of the partially written output, if one exists.
    func cleanupCancelledExport(jobId: UUID, partialFileURL: URL?) async {
        Self.logger.info("Begin cleanup for cancelled export job \(jobId.uuidString, privacy: .public)")

        // 1. Remove partial file.
        if let url = partialFileURL {
            await removePartialFile(at: url, jobId: jobId)
        } else {
            Self.logger.info("No partial file URL provided for job \(jobId.uuidString, privacy: .public); skipping file cleanup.")
        }

        // 2. Detach from queue (if caller provided a hook).
        if let detach = queueDetachment {
            do {
                try await detach(jobId)
                Self.logger.info("Detached job \(jobId.uuidString, privacy: .public) from export queue.")
            } catch {
                Self.logger.error("Queue detachment failed for \(jobId.uuidString, privacy: .public): \(error.localizedDescription)")
            }
        } else {
            Self.logger.debug("No queue detachment hook configured; skipping queue removal for \(jobId.uuidString, privacy: .public).")
        }

        Self.logger.info("Cleanup finished for cancelled export job \(jobId.uuidString, privacy: .public)")
    }

    // MARK: - File Removal

    /// Remove the partial output file, hopping to a background thread so
    /// that filesystem I/O never blocks the main actor.
    private func removePartialFile(at url: URL, jobId: UUID) async {
        // Capture a plain URL (Sendable) for the detached task.
        let target = url
        let id = jobId
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard fm.fileExists(atPath: target.path) else {
                Self.logger.info("Partial file already absent for \(id.uuidString, privacy: .public): \(target.path, privacy: .public)")
                return
            }
            do {
                try fm.removeItem(at: target)
                Self.logger.info("Removed partial export file for \(id.uuidString, privacy: .public): \(target.path, privacy: .public)")
            } catch {
                Self.logger.error("Failed to remove partial file for \(id.uuidString, privacy: .public): \(error.localizedDescription)")
            }
        }.value
    }
}
