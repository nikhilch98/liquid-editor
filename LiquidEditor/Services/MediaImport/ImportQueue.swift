// ImportQueue.swift
// LiquidEditor
//
// Import task queuing with concurrency control and progress tracking.
// Manages batched file imports through the import pipeline with
// sequential processing, progress reporting, cancellation, and retry.
//
// Uses actor isolation for thread-safe mutable state.
//
// Note: ImportFileState, ImportFileProgress, and ImportQueueProgress
// are defined in ImportProgressSheet.swift and shared with the UI layer.

import Foundation
import os

// MARK: - ImportTask

/// An individual import job with source path and expected type.
struct ImportTask: Sendable {
    /// Path to the temporary file to import.
    let tempFilePath: String

    /// Original filename for display.
    let filename: String

    /// Expected media type based on file extension or picker type.
    let expectedType: MediaType

    /// Source of the import.
    let source: ImportSource
}

// MARK: - QueueEntry

/// Internal entry pairing a task with its progress index.
private struct QueueEntry: Sendable {
    let task: ImportTask
    let index: Int
}

// MARK: - ImportQueueDelegate

/// Delegate protocol for import queue progress notifications.
protocol ImportQueueDelegate: AnyObject, Sendable {
    /// Called when progress changes.
    func importQueueDidUpdateProgress(_ progress: ImportQueueProgress)

    /// Called when all imports are finished.
    func importQueueDidFinish(_ progress: ImportQueueProgress)
}

// MARK: - ImportQueue

/// Controls the import queue processing pipeline.
///
/// Manages queued imports with:
/// - Up to 3 concurrent imports per batch
/// - Progress tracking per file and overall
/// - Cancellation support
/// - Retry for failed imports
///
/// Thread Safety: `actor` isolation ensures all mutable state
/// is accessed serially.
actor ImportQueue {

    // MARK: - Constants

    /// Maximum file size (4 GB).
    static let maxFileSizeBytes: Int = 4_294_967_296

    // MARK: - Properties

    /// Maximum concurrent imports per batch.
    private let maxConcurrent: Int

    // MARK: - State

    private var queue: [QueueEntry] = []
    private var progress: [ImportFileProgress] = []
    private var tasks: [ImportTask] = []
    private var isProcessing: Bool = false
    private var isCancelled: Bool = false

    // MARK: - Delegate

    weak var delegate: ImportQueueDelegate?

    // MARK: - Logger

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "ImportQueue"
    )

    // MARK: - Init

    /// Initialize the import queue with configurable concurrency.
    ///
    /// - Parameter maxConcurrent: Maximum number of concurrent imports (default: 3).
    init(maxConcurrent: Int = 3) {
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Computed Properties

    /// Whether imports are currently processing.
    var processing: Bool { isProcessing }

    /// Number of pending items.
    var pendingCount: Int {
        progress.filter { $0.state == .queued }.count
    }

    /// Current queue progress snapshot.
    var currentProgress: ImportQueueProgress {
        ImportQueueProgress(
            totalFiles: progress.count,
            completedFiles: progress.filter { $0.state == .complete }.count,
            failedFiles: progress.filter { $0.state == .failed }.count,
            duplicateFiles: progress.filter { $0.state == .duplicate }.count,
            fileProgress: progress,
            isCancelled: isCancelled
        )
    }

    // MARK: - Enqueue

    /// Add tasks to the import queue and begin processing.
    ///
    /// - Parameter newTasks: Tasks to add to the queue.
    func enqueue(_ newTasks: [ImportTask]) {
        for task in newTasks {
            let index = progress.count
            queue.append(QueueEntry(task: task, index: index))
            tasks.append(task)
            progress.append(ImportFileProgress(
                filename: task.filename,
                state: .queued
            ))
        }

        notifyProgress()

        if !isProcessing {
            Task { await processQueue() }
        }
    }

    // MARK: - Cancel

    /// Cancel all pending imports.
    ///
    /// Items already being processed will complete, but queued
    /// items are immediately marked cancelled.
    func cancelAll() {
        isCancelled = true
        for i in 0..<progress.count {
            if progress[i].state == .queued {
                progress[i] = progress[i].with(state: .cancelled)
            }
        }
        queue.removeAll()
        notifyProgress()
    }

    // MARK: - Clear Finished

    /// Clear completed, failed, cancelled, and duplicate entries.
    func clearFinished() {
        // Use filter to remove finished entries in a single pass
        let finishedStates: Set<ImportFileState> = [.complete, .failed, .cancelled, .duplicate]
        let indicesToKeep = progress.enumerated().compactMap { index, item in
            finishedStates.contains(item.state) ? nil : index
        }

        progress = indicesToKeep.map { progress[$0] }
        tasks = indicesToKeep.compactMap { $0 < tasks.count ? tasks[$0] : nil }

        if queue.isEmpty {
            isProcessing = false
            isCancelled = false
        }
        notifyProgress()
    }

    // MARK: - Retry

    /// Re-queue all failed imports for retry.
    func retryFailed() {
        for i in 0..<progress.count {
            if progress[i].state == .failed, i < tasks.count {
                queue.append(QueueEntry(task: tasks[i], index: i))
                progress[i] = progress[i].with(
                    state: .queued,
                    progress: 0.0,
                    errorMessage: .some(nil)
                )
            }
        }

        notifyProgress()

        if !isProcessing, !queue.isEmpty {
            Task { await processQueue() }
        }
    }

    // MARK: - Processing

    /// Process the queue in batches of maxConcurrent.
    private func processQueue() async {
        isProcessing = true
        isCancelled = false
        notifyProgress()

        while !queue.isEmpty, !isCancelled {
            // Collect a batch
            var batch: [QueueEntry] = []
            while batch.count < maxConcurrent, !queue.isEmpty {
                batch.append(queue.removeFirst())
            }

            // Process batch concurrently
            await withTaskGroup(of: Void.self) { group in
                for entry in batch {
                    group.addTask { [self] in
                        await self.processEntry(entry)
                    }
                }
            }
        }

        isProcessing = false
        notifyProgress()

        let finalProgress = currentProgress
        delegate?.importQueueDidFinish(finalProgress)
    }

    /// Process a single import entry.
    private func processEntry(_ entry: QueueEntry) async {
        let index = entry.index
        let task = entry.task

        do {
            // Step 1: Validate file exists
            let fm = FileManager.default
            guard fm.fileExists(atPath: task.tempFilePath) else {
                updateProgress(index, state: .failed, errorMessage: "File not found")
                return
            }

            let attrs = try fm.attributesOfItem(atPath: task.tempFilePath)
            let fileSize = (attrs[.size] as? Int) ?? 0

            if fileSize == 0 {
                updateProgress(index, state: .failed, errorMessage: "File is empty")
                return
            }

            if fileSize > Self.maxFileSizeBytes {
                updateProgress(index, state: .failed, errorMessage: "File too large (max 4 GB)")
                return
            }

            // Step 2: Copy to Documents/Media/
            updateProgress(index, state: .copying, progress: 0.1)

            let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            let mediaDir = docsURL.appendingPathComponent("Media", isDirectory: true)

            if !fm.fileExists(atPath: mediaDir.path) {
                try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
            }

            let ext = Self.extensionFromPath(task.tempFilePath)
            let assetId = UUID().uuidString
            let destRelativePath = "Media/\(assetId)\(ext)"
            let destURL = docsURL.appendingPathComponent(destRelativePath)

            try fm.copyItem(
                at: URL(fileURLWithPath: task.tempFilePath),
                to: destURL
            )
            updateProgress(index, progress: 0.3)

            // Step 3-8: Metadata, thumbnail, etc. would be handled by
            // MediaImportService. For the queue, we track completion.
            updateProgress(index, state: .complete, progress: 1.0)

            // Clean up temp file if different from dest
            if task.tempFilePath != destURL.path {
                try? fm.removeItem(atPath: task.tempFilePath)
            }

            logger.info("Imported \(task.filename) -> \(destRelativePath)")

        } catch {
            updateProgress(index, state: .failed, errorMessage: error.localizedDescription)
            logger.error("Import failed for \(task.filename): \(error.localizedDescription)")
        }
    }

    // MARK: - Progress Updates

    private func updateProgress(
        _ index: Int,
        state: ImportFileState? = nil,
        progress progressValue: Double? = nil,
        errorMessage: String? = nil
    ) {
        guard index < progress.count else { return }
        progress[index] = progress[index].with(
            state: state,
            progress: progressValue,
            errorMessage: errorMessage.map { .some($0) }
        )
        notifyProgress()
    }

    private func notifyProgress() {
        let snapshot = currentProgress
        delegate?.importQueueDidUpdateProgress(snapshot)
    }

    // MARK: - Utility

    /// Extract file extension (lowercase, with dot) from a path.
    nonisolated static func extensionFromPath(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "" : ".\(ext)"
    }
}
