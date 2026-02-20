// ExportQueue.swift
// LiquidEditor
//
// Manages a queue of export operations processed sequentially.
// Supports priority ordering, cancellation, retry, and persistence.
//
// Thread Safety:
// - `actor` ensures serial access to mutable state.
// - Export jobs are processed one at a time.

import Foundation
import os

// MARK: - ExportPayload

/// Internal payload for deferred export execution.
struct ExportPayload: Sendable {
    /// URL to the source video/composition.
    let sourceURL: URL

    /// Per-clip segment descriptors for multi-clip composition.
    let clips: [CompositionSegment]
}

// MARK: - ExportQueueDelegate

/// Delegate protocol for export queue state changes.
protocol ExportQueueDelegate: AnyObject, Sendable {
    /// Called when a job's state changes.
    func exportQueue(_ queue: ExportQueue, didUpdateJob job: ExportJob)

    /// Called when the queue starts or stops processing.
    func exportQueue(_ queue: ExportQueue, isProcessing: Bool)
}

// MARK: - ExportQueue

/// Manages a queue of export operations processed sequentially.
///
/// ## Design
///
/// - Uses `actor` isolation for thread-safe, lock-free queue management.
/// - Jobs are sorted by priority within the pending set.
/// - Only one export runs at a time (serial processing).
/// - Completed/failed jobs are kept in history (capped at `maxHistorySize`).
///
/// ## Persistence
///
/// The queue state can be serialized to/from JSON for crash recovery.
/// On restore, any jobs that were running are reset to queued.
actor ExportQueue {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "ExportQueue"
    )

    // MARK: - Properties

    /// The export service used to execute jobs.
    private let exportService: ExportService

    /// Internal queue of jobs.
    private var queue: [ExportJob] = []

    /// Whether the queue is currently processing a job.
    private var _isProcessing = false

    /// Job payloads stored for deferred execution.
    private var jobPayloads: [String: ExportPayload] = [:]

    /// Maximum number of completed jobs to keep in history.
    static let maxHistorySize = 50

    /// Optional delegate for state change notifications.
    weak var delegate: ExportQueueDelegate?

    // MARK: - Init

    /// Creates an export queue with the given export service.
    ///
    /// - Parameter exportService: The service used to execute export jobs.
    init(exportService: ExportService) {
        self.exportService = exportService
    }

    // MARK: - Read-Only Accessors

    /// All jobs in the queue (pending, running, completed, failed).
    var allJobs: [ExportJob] { queue }

    /// Pending jobs only.
    var pendingJobs: [ExportJob] {
        queue.filter { $0.status == .queued }
    }

    /// Currently running job.
    var runningJob: ExportJob? {
        queue.first { $0.isRunning }
    }

    /// Completed jobs.
    var completedJobs: [ExportJob] {
        queue.filter { $0.status == .completed }
    }

    /// Failed jobs.
    var failedJobs: [ExportJob] {
        queue.filter { $0.status == .failed }
    }

    /// Whether the queue is currently processing a job.
    var isProcessing: Bool { _isProcessing }

    /// Number of pending jobs.
    var pendingCount: Int { pendingJobs.count }

    /// Total number of jobs.
    var totalCount: Int { queue.count }

    /// Whether there are any active (non-terminal) jobs.
    var hasActiveJobs: Bool {
        queue.contains { $0.isActive }
    }

    // MARK: - Enqueue

    /// Enqueue a new export job.
    ///
    /// Returns the job ID. Automatically starts processing if idle.
    ///
    /// - Parameters:
    ///   - config: The export configuration.
    ///   - sourceURL: URL to the source video/composition.
    ///   - clips: Per-clip segment descriptors.
    ///   - label: Optional user-visible label.
    ///   - priority: Job priority (default: normal).
    /// - Returns: The unique job identifier.
    @discardableResult
    func enqueue(
        config: ExportConfig,
        sourceURL: URL,
        clips: [CompositionSegment] = [],
        label: String? = nil,
        priority: ExportJobPriority = .normal
    ) -> String {
        // Validate config resolution before enqueuing.
        guard config.outputWidth > 0, config.outputHeight > 0 else {
            let jobId = UUID().uuidString
            Self.logger.error("Enqueue rejected for job \(jobId, privacy: .public): invalid resolution \(config.outputWidth)x\(config.outputHeight)")
            let job = ExportJob(
                id: jobId,
                label: label ?? "Invalid Export",
                config: config,
                status: .failed,
                priority: priority,
                createdAt: Date()
            )
            queue.append(job.with(errorMessage: .some("Invalid export resolution: \(config.outputWidth)x\(config.outputHeight)")))
            notifyJobUpdate(queue[queue.count - 1])
            return jobId
        }

        let jobId = UUID().uuidString
        let job = ExportJob(
            id: jobId,
            label: label ?? defaultLabel(for: config),
            config: config,
            status: .queued,
            priority: priority,
            createdAt: Date()
        )

        // Insert based on priority
        let insertIndex = findInsertIndex(for: priority)
        queue.insert(job, at: insertIndex)

        // Store the payload for later
        jobPayloads[jobId] = ExportPayload(
            sourceURL: sourceURL,
            clips: clips
        )

        notifyJobUpdate(job)

        // Start processing if idle
        processNextIfIdle()

        return jobId
    }

    // MARK: - Cancel

    /// Cancel a job.
    ///
    /// If the job is currently running, the active export is cancelled.
    /// If the job is pending, it is marked as cancelled immediately.
    ///
    /// - Parameter jobId: The job to cancel.
    func cancel(_ jobId: String) async {
        guard !jobId.isEmpty else {
            Self.logger.warning("Cancel called with empty jobId — ignoring")
            return
        }
        guard let index = queue.firstIndex(where: { $0.id == jobId }) else { return }

        let job = queue[index]

        if job.isRunning {
            await exportService.cancelExport()
        }

        queue[index] = job.with(
            status: .cancelled,
            completedAt: .some(Date())
        )
        // Keep payload so the job can be retried later.

        notifyJobUpdate(queue[index])

        // Process next if this was the running job
        if job.isRunning {
            _isProcessing = false
            notifyProcessingChange()
            processNextIfIdle()
        }
    }

    // MARK: - Retry

    /// Retry a failed or cancelled job.
    ///
    /// Resets the job to queued state and starts processing if idle.
    ///
    /// - Parameter jobId: The job to retry.
    func retry(_ jobId: String) {
        guard !jobId.isEmpty else {
            Self.logger.warning("Retry called with empty jobId — ignoring")
            return
        }
        guard let index = queue.firstIndex(where: { $0.id == jobId }) else { return }

        let job = queue[index]
        guard job.status == .failed || job.status == .cancelled else { return }

        // Validate payload still exists before retrying
        guard let payload = jobPayloads[jobId] else {
            Self.logger.error("Retry failed for job \(jobId, privacy: .public): payload not found")
            queue[index] = job.with(
                status: .failed,
                errorMessage: .some("Cannot retry: export payload no longer available.")
            )
            notifyJobUpdate(queue[index])
            return
        }

        // Validate source file is still accessible
        guard FileManager.default.fileExists(atPath: payload.sourceURL.path) else {
            Self.logger.error("Retry failed for job \(jobId, privacy: .public): source file missing at \(payload.sourceURL.path, privacy: .public)")
            queue[index] = job.with(
                status: .failed,
                errorMessage: .some("Cannot retry: source file no longer exists.")
            )
            notifyJobUpdate(queue[index])
            return
        }

        queue[index] = job.with(
            status: .queued,
            progress: 0.0,
            errorMessage: .some(nil)
        )

        notifyJobUpdate(queue[index])
        processNextIfIdle()
    }

    // MARK: - Remove

    /// Remove a job from the queue.
    ///
    /// - Parameter jobId: The job to remove.
    func remove(_ jobId: String) {
        guard !jobId.isEmpty else {
            Self.logger.warning("Remove called with empty jobId — ignoring")
            return
        }
        queue.removeAll { $0.id == jobId }
        jobPayloads.removeValue(forKey: jobId)
    }

    /// Clear all completed and failed jobs from history.
    func clearHistory() {
        queue.removeAll { $0.isTerminal }
    }

    // MARK: - Reorder

    /// Reorder a job in the queue.
    ///
    /// - Parameters:
    ///   - oldIndex: Current index of the job.
    ///   - newIndex: Desired index for the job.
    func reorder(from oldIndex: Int, to newIndex: Int) {
        guard oldIndex >= 0, oldIndex < queue.count else { return }
        guard newIndex >= 0, newIndex < queue.count else { return }
        guard oldIndex != newIndex else { return }

        let job = queue.remove(at: oldIndex)
        queue.insert(job, at: newIndex)
    }

    // MARK: - Internal Processing

    private func processNextIfIdle() {
        guard !_isProcessing else { return }

        // Find next pending job (respecting priority)
        guard let nextJob = queue.first(where: { $0.status == .queued }) else {
            return
        }

        _isProcessing = true
        notifyProcessingChange()

        Task {
            await processJob(nextJob)
        }
    }

    private func processJob(_ job: ExportJob) async {
        guard let payload = jobPayloads[job.id] else {
            updateJob(job.id) { j in
                j.with(
                    status: .failed,
                    errorMessage: .some("Export payload not found."),
                    completedAt: .some(Date())
                )
            }
            _isProcessing = false
            notifyProcessingChange()
            processNextIfIdle()
            return
        }

        updateJob(job.id) { j in
            j.with(
                status: .preparing,
                startedAt: .some(Date())
            )
        }

        // Execute the export and monitor progress
        let progressStream = await exportService.export(
            job: job,
            sourceURL: payload.sourceURL,
            clips: payload.clips
        )

        var lastPhase: ExportPhase = .preparing

        for await progress in progressStream {
            lastPhase = progress.phase
            updateJob(job.id) { j in
                j.with(progress: progress.overallProgress)
            }
        }

        // Determine final status based on last phase
        switch lastPhase {
        case .completed:
            updateJob(job.id) { j in
                j.with(
                    status: .completed,
                    progress: 1.0,
                    completedAt: .some(Date())
                )
            }

        case .cancelled:
            updateJob(job.id) { j in
                j.with(
                    status: .cancelled,
                    completedAt: .some(Date())
                )
            }

        case .failed:
            Self.logger.error("Export job \(job.id, privacy: .public) finished with phase .failed (last reported phase)")
            updateJob(job.id) { j in
                j.with(
                    status: .failed,
                    errorMessage: .some("Export failed"),
                    completedAt: .some(Date())
                )
            }

        default:
            Self.logger.error("Export job \(job.id, privacy: .public) ended in unexpected phase: \(lastPhase.rawValue, privacy: .public)")
            updateJob(job.id) { j in
                j.with(
                    status: .failed,
                    errorMessage: .some("Unexpected terminal phase: \(lastPhase.rawValue)"),
                    completedAt: .some(Date())
                )
            }
        }

        // Cleanup
        jobPayloads.removeValue(forKey: job.id)
        _isProcessing = false
        notifyProcessingChange()

        // Trim history
        trimHistory()

        // Process next job
        processNextIfIdle()
    }

    private func updateJob(_ jobId: String, updater: (ExportJob) -> ExportJob) {
        guard let index = queue.firstIndex(where: { $0.id == jobId }) else { return }
        queue[index] = updater(queue[index])
        notifyJobUpdate(queue[index])
    }

    private func findInsertIndex(for priority: ExportJobPriority) -> Int {
        // Find the last pending job with equal or higher priority
        var lastIndex = -1
        for i in 0..<queue.count {
            let job = queue[i]
            if job.status == .queued && job.priority.sortOrder <= priority.sortOrder {
                lastIndex = i
            }
        }
        return lastIndex + 1
    }

    private func trimHistory() {
        let terminalJobs = queue.filter(\.isTerminal)
        if terminalJobs.count > Self.maxHistorySize {
            let toRemoveCount = terminalJobs.count - Self.maxHistorySize
            let toRemoveIds = Set(terminalJobs.prefix(toRemoveCount).map(\.id))
            queue.removeAll { toRemoveIds.contains($0.id) }
        }
    }

    private func defaultLabel(for config: ExportConfig) -> String {
        if let preset = config.socialPreset {
            return preset.displayName
        }
        if config.audioOnly {
            return "Audio Export"
        }
        return "\(config.resolution.label) \(config.codec.displayName)"
    }

    // MARK: - Delegate Notifications

    private func notifyJobUpdate(_ job: ExportJob) {
        let delegate = self.delegate
        let jobCopy = job
        Task { @MainActor in
            delegate?.exportQueue(self, didUpdateJob: jobCopy)
        }
    }

    private func notifyProcessingChange() {
        let delegate = self.delegate
        let processing = _isProcessing
        Task { @MainActor in
            delegate?.exportQueue(self, isProcessing: processing)
        }
    }

    // MARK: - Persistence

    /// Serialize queue state to JSON data.
    ///
    /// - Returns: JSON-encoded queue state.
    /// - Throws: Encoding errors.
    func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(queue)
    }

    /// Restore queue from JSON data.
    ///
    /// Running jobs are reset to queued (app was killed).
    /// Terminal jobs are preserved for history.
    ///
    /// - Parameter data: JSON-encoded queue state.
    func restoreFromJSONData(_ data: Data) {
        // Basic schema validation: data must be a JSON array
        guard !data.isEmpty else {
            Self.logger.warning("Restore skipped: empty data")
            return
        }

        guard let firstByte = data.first, firstByte == UInt8(ascii: "[") else {
            Self.logger.error("Restore failed: data is not a JSON array")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let items = try decoder.decode([ExportJob].self, from: data)

            queue.removeAll()
            var restoredCount = 0
            var resetCount = 0
            for item in items {
                // Validate each item has a non-empty id
                guard !item.id.isEmpty else {
                    Self.logger.warning("Restore skipped item with empty id")
                    continue
                }
                if item.isRunning {
                    // Reset running items to pending (app was killed)
                    queue.append(item.with(status: .queued, progress: 0.0))
                    resetCount += 1
                } else if item.status == .queued || item.isTerminal {
                    queue.append(item)
                }
                restoredCount += 1
            }
            Self.logger.info("Restored \(restoredCount) jobs (\(resetCount) reset from running to queued)")
        } catch {
            Self.logger.error("Failed to restore queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Save queue state to a file in the caches directory.
    func saveToFile() async {
        do {
            let data = try toJSONData()
            let cacheDir = FileManager.default.temporaryDirectory
            let fileURL = cacheDir.appendingPathComponent("export_queue.json")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save queue to file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load queue state from the caches directory file.
    func loadFromFile() async {
        let cacheDir = FileManager.default.temporaryDirectory
        let fileURL = cacheDir.appendingPathComponent("export_queue.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            restoreFromJSONData(data)
        } catch {
            Self.logger.error("Failed to load queue from file: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - ExportJobPriority Sort Order

extension ExportJobPriority {
    /// Numeric sort order (lower = higher priority).
    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}
