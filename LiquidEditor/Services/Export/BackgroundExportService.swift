// BackgroundExportService.swift
// LiquidEditor
//
// iOS background task management for video exports.
// Registers UIApplication background tasks to allow exports to continue
// when the app is backgrounded. Sends local notifications for
// completion, pause, and failure events.

import UIKit
import UserNotifications
import Foundation
import os

/// Sendable weak reference wrapper for passing actor references across isolation boundaries.
private final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

// MARK: - BackgroundExportService

/// Manages background export lifecycle for video exports.
///
/// Thread Safety:
/// - `actor` ensures serial access to mutable state.
/// - UIApplication APIs are called on `@MainActor` as required.
actor BackgroundExportService {

    // MARK: - Properties

    private static let logger = Logger(subsystem: "LiquidEditor", category: "BackgroundExportService")

    /// Background task identifier.
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    /// Whether the export is currently paused due to background time expiring.
    private(set) var isPaused: Bool = false

    /// The export ID currently being managed.
    private var currentExportId: String?

    /// Callback invoked when background time is about to expire.
    private var onBackgroundTimeExpiring: (() -> Void)?

    // MARK: - Background Task Management

    /// Begin a background task for an export operation.
    ///
    /// - Parameter exportId: Unique identifier for the export.
    func beginBackgroundExport(exportId: String) {
        let weakSelf = WeakRef(self)
        Task { @MainActor in
            let taskId = UIApplication.shared.beginBackgroundTask(
                withName: "LiquidEditorExport_\(exportId)"
            ) {
                Task {
                    await weakSelf.value?.handleBackgroundTimeExpiring()
                }
            }

            await weakSelf.value?.setBackgroundState(taskId: taskId, exportId: exportId)

            Self.logger.info("Background task started for \(exportId, privacy: .public)")
            Self.logger.debug("Remaining time: \(UIApplication.shared.backgroundTimeRemaining)s")
        }
    }

    /// End the background task after export completes.
    func endBackgroundExport() {
        let taskId = backgroundTaskId
        if taskId != .invalid {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
        backgroundTaskId = .invalid
        currentExportId = nil
        isPaused = false

        Self.logger.info("Background task ended")
    }

    // MARK: - Notifications

    /// Send a local notification that the export completed.
    nonisolated func notifyExportComplete(exportId: String) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("export.notification.complete.title", value: "Export Complete", comment: "")
        content.body = NSLocalizedString("export.notification.complete.body", value: "Your video has been exported successfully.", comment: "")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "export_complete_\(exportId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to send completion notification: \(error.localizedDescription)")
            }
        }
    }

    /// Send a local notification that the export was paused.
    nonisolated func notifyExportPaused() {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("export.notification.paused.title", value: "Export Paused", comment: "")
        content.body = NSLocalizedString("export.notification.paused.body", value: "Return to Liquid Editor to continue your export.", comment: "")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "export_paused",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to send paused notification: \(error.localizedDescription)")
            }
        }
    }

    /// Send a local notification that the export failed.
    nonisolated func notifyExportFailed(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("export.notification.failed.title", value: "Export Failed", comment: "")
        content.body = reason
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "export_failed",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to send failure notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Disk Space

    /// Default disk space safety margin in MB.
    private static let defaultDiskSpaceMarginMB = 500

    /// Check available disk space in bytes.
    nonisolated static func availableDiskSpaceBytes() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: NSTemporaryDirectory()
            )
            return (attrs[.systemFreeSize] as? Int64) ?? 0
        } catch {
            return 0
        }
    }

    /// Check available disk space in megabytes.
    nonisolated static func availableDiskSpaceMB() -> Int {
        Int(availableDiskSpaceBytes() / (1024 * 1024))
    }

    /// Validate that sufficient disk space is available for an export.
    ///
    /// - Parameters:
    ///   - estimatedSizeMB: Estimated output file size in MB.
    ///   - safetyMarginMB: Safety margin in MB (default: 500MB).
    /// - Returns: Error message if insufficient space, nil otherwise.
    nonisolated static func validateDiskSpace(estimatedSizeMB: Int, safetyMarginMB: Int = defaultDiskSpaceMarginMB) -> String? {
        let availableMB = availableDiskSpaceMB()
        let requiredMB = estimatedSizeMB + safetyMarginMB

        if availableMB < requiredMB {
            return "Insufficient disk space. Available: \(availableMB)MB, Required: \(requiredMB)MB."
        }
        return nil
    }

    // MARK: - Thermal Monitoring

    /// Current thermal state as an integer (0=nominal, 1=fair, 2=serious, 3=critical).
    nonisolated static var thermalStateInt: Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    /// Whether the device is in a concerning thermal state.
    nonisolated static var isThermalConcern: Bool {
        thermalStateInt >= 2
    }

    // MARK: - Temp File Cleanup

    /// Temporary file prefixes to clean up.
    private static let tempFilePrefixes = ["rendered_", "composition_", "export_", "audio_", "frame_grab_", "gif_"]

    /// Temporary file suffixes to clean up.
    private static let tempFileSuffixes = [".liquidproject"]

    /// Clean up old export temp files older than the specified number of days.
    ///
    /// - Parameters:
    ///   - olderThanDays: Files older than this many days will be deleted (default: 7).
    ///   - prefixes: File prefixes to match (default: built-in list).
    ///   - suffixes: File suffixes to match (default: built-in list).
    nonisolated static func cleanupOldExports(
        olderThanDays: Int = 7,
        prefixes: [String] = tempFilePrefixes,
        suffixes: [String] = tempFileSuffixes
    ) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: []
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 24 * 3600)

        for url in contents {
            let filename = url.lastPathComponent
            let matchesPrefix = prefixes.contains { filename.hasPrefix($0) }
            let matchesSuffix = suffixes.contains { filename.hasSuffix($0) }
            guard matchesPrefix || matchesSuffix else { continue }

            if let attrs = try? url.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate,
               created < cutoff {
                try? fileManager.removeItem(at: url)

                Self.logger.info("Cleaned up old file: \(filename, privacy: .public)")
            }
        }
    }

    // MARK: - Private

    private func setBackgroundState(taskId: UIBackgroundTaskIdentifier, exportId: String) {
        backgroundTaskId = taskId
        currentExportId = exportId
        isPaused = false
    }

    private func handleBackgroundTimeExpiring() {
        Self.logger.warning("Background time expiring")

        isPaused = true
        onBackgroundTimeExpiring?()
        notifyExportPaused()

        let taskId = backgroundTaskId
        backgroundTaskId = .invalid
        currentExportId = nil

        if taskId != .invalid {
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(taskId)
            }
        }
    }
}
