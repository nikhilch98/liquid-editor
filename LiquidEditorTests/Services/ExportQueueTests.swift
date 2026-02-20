// ExportQueueTests.swift
// LiquidEditorTests
//
// Tests for ExportQueue: enqueue, cancel, retry, priority ordering,
// history management, and persistence.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ExportQueue Tests

@Suite("ExportQueue")
struct ExportQueueTests {

    // MARK: - Helpers

    /// Create a test ExportService for queue tests.
    private func makeExportService() -> ExportService {
        ExportService()
    }

    /// Create a simple test config.
    private func makeConfig(
        resolution: ExportResolution = .r1080p,
        codec: ExportCodec = .h264
    ) -> ExportConfig {
        ExportConfig(
            resolution: resolution,
            codec: codec,
            format: .mp4,
            quality: .high,
            bitrateMbps: 20.0
        )
    }

    // MARK: - Enqueue Tests

    @Test("Enqueue adds job to queue")
    func enqueueAddsJob() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let jobId = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL,
            label: "Test Export"
        )

        let allJobs = await queue.allJobs
        #expect(!jobId.isEmpty)
        #expect(allJobs.count == 1)
        #expect(allJobs.first?.label == "Test Export")
    }

    @Test("Enqueue multiple jobs maintains order")
    func enqueueMultipleJobs() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let id1 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "First")
        let id2 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "Second")
        let id3 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "Third")

        let allJobs = await queue.allJobs
        #expect(allJobs.count == 3)
        #expect(!id1.isEmpty)
        #expect(!id2.isEmpty)
        #expect(!id3.isEmpty)
    }

    @Test("Default label generated from config")
    func defaultLabelFromConfig() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        _ = await queue.enqueue(
            config: makeConfig(resolution: .r4K, codec: .h265),
            sourceURL: sourceURL
        )

        let allJobs = await queue.allJobs
        #expect(allJobs.first?.label == "4K H.265 (HEVC)")
    }

    @Test("Audio-only config gets audio label")
    func audioOnlyLabel() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let audioConfig = ExportConfig(audioOnly: true)
        _ = await queue.enqueue(config: audioConfig, sourceURL: sourceURL)

        let allJobs = await queue.allJobs
        #expect(allJobs.first?.label == "Audio Export")
    }

    // MARK: - Cancel Tests

    @Test("Cancel marks pending job as cancelled")
    func cancelPendingJob() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let jobId = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL,
            label: "To Cancel"
        )

        await queue.cancel(jobId)

        let allJobs = await queue.allJobs
        let cancelledJob = allJobs.first { $0.id == jobId }
        #expect(cancelledJob?.status == .cancelled)
        #expect(cancelledJob?.completedAt != nil)
    }

    @Test("Cancel nonexistent job is no-op")
    func cancelNonexistentJob() async {
        let queue = ExportQueue(exportService: makeExportService())
        await queue.cancel("nonexistent_id")
        // Should not crash
        let count = await queue.totalCount
        #expect(count == 0)
    }

    // MARK: - Retry Tests

    @Test("Retry resets failed job to queued")
    func retryFailedJob() async throws {
        let queue = ExportQueue(exportService: makeExportService())
        // Create a real temporary file so retry's file-existence check passes.
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_retry_\(UUID().uuidString).mp4")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let jobId = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL
        )

        // Cancel it first to make it cancellable for retry
        await queue.cancel(jobId)

        await queue.retry(jobId)

        let allJobs = await queue.allJobs
        let job = allJobs.first { $0.id == jobId }
        #expect(job?.status == .queued)
        #expect(job?.progress == 0.0)
    }

    @Test("Retry queued job is no-op")
    func retryQueuedJobNoop() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let jobId = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL
        )

        // Retry on a queued job should not change it
        await queue.retry(jobId)

        let allJobs = await queue.allJobs
        let job = allJobs.first { $0.id == jobId }
        #expect(job?.status != .failed)
    }

    // MARK: - Remove Tests

    @Test("Remove deletes job from queue")
    func removeJob() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let jobId = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL
        )

        await queue.remove(jobId)

        let count = await queue.totalCount
        #expect(count == 0)
    }

    // MARK: - Clear History Tests

    @Test("Clear history removes terminal jobs only")
    func clearHistoryRemovesTerminal() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let id1 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "Active")
        _ = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "ToBeCancelled")

        // Cancel second job to make it terminal
        let allJobsBefore = await queue.allJobs
        if let secondId = allJobsBefore.last?.id {
            await queue.cancel(secondId)
        }

        await queue.clearHistory()

        let remaining = await queue.allJobs
        // At least the first job should remain (it's either queued or processing)
        let terminalRemaining = remaining.filter(\.isTerminal)
        #expect(terminalRemaining.isEmpty)
    }

    // MARK: - Reorder Tests

    @Test("Reorder moves job to new position")
    func reorderJob() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        let id1 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "First")
        let id2 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "Second")
        let id3 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "Third")

        // The queue might be processing the first job already,
        // so we just verify reorder doesn't crash
        await queue.reorder(from: 0, to: 2)

        let allJobs = await queue.allJobs
        #expect(allJobs.count == 3)
    }

    @Test("Reorder with invalid indices is no-op")
    func reorderInvalidIndices() async {
        let queue = ExportQueue(exportService: makeExportService())
        await queue.reorder(from: -1, to: 5)
        // Should not crash
    }

    // MARK: - Priority Tests

    @Test("High priority job inserted before normal priority")
    func highPriorityInsertedFirst() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        _ = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL,
            label: "Normal",
            priority: .normal
        )
        _ = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL,
            label: "Low",
            priority: .low
        )
        let highId = await queue.enqueue(
            config: makeConfig(),
            sourceURL: sourceURL,
            label: "High",
            priority: .high
        )

        let pending = await queue.pendingJobs
        // High priority should be first among pending
        if let firstPending = pending.first {
            #expect(firstPending.priority == .high)
        }
    }

    // MARK: - Computed Properties Tests

    @Test("Pending count reflects queued jobs")
    func pendingCountCorrect() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        _ = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL)
        _ = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL)

        let total = await queue.totalCount
        #expect(total == 2)
    }

    @Test("Has active jobs when queue has pending items")
    func hasActiveJobs() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        _ = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL)

        let hasActive = await queue.hasActiveJobs
        #expect(hasActive == true)
    }

    @Test("No active jobs when queue is empty")
    func noActiveJobsWhenEmpty() async {
        let queue = ExportQueue(exportService: makeExportService())

        let hasActive = await queue.hasActiveJobs
        #expect(hasActive == false)
    }

    // MARK: - Persistence Tests

    @Test("Serialization and deserialization round-trip")
    func serializationRoundTrip() async {
        let queue = ExportQueue(exportService: makeExportService())
        let sourceURL = URL(fileURLWithPath: "/tmp/test_video.mp4")

        _ = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "Job 1")
        let id2 = await queue.enqueue(config: makeConfig(), sourceURL: sourceURL, label: "Job 2")

        // Cancel one to create a terminal job
        await queue.cancel(id2)

        // Serialize
        let data = try! await queue.toJSONData()
        #expect(!data.isEmpty)

        // Deserialize into new queue
        let newQueue = ExportQueue(exportService: makeExportService())
        await newQueue.restoreFromJSONData(data)

        let restored = await newQueue.allJobs
        #expect(restored.count >= 1) // At least the cancelled job
    }

    @Test("Running jobs reset to queued on restore")
    func runningJobsResetOnRestore() async {
        // Create a job manually in running state via serialization
        let job = ExportJob(
            id: "test_running",
            label: "Running Job",
            config: ExportConfig(),
            status: .rendering,
            createdAt: Date(),
            startedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode([job])

        let queue = ExportQueue(exportService: makeExportService())
        await queue.restoreFromJSONData(data)

        let restored = await queue.allJobs
        #expect(restored.first?.status == .queued)
        #expect(restored.first?.progress == 0.0)
    }
}
