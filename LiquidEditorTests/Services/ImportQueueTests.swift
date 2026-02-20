// ImportQueueTests.swift
// LiquidEditorTests
//
// Tests for ImportQueue using Swift Testing.
// Validates queue processing, concurrency control,
// cancellation, retry, and progress tracking.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - MockImportQueueDelegate

/// Test delegate that captures progress updates.
final class MockImportQueueDelegate: ImportQueueDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _updates: [ImportQueueProgress] = []
    private var _finishCount: Int = 0

    var updates: [ImportQueueProgress] {
        lock.lock()
        defer { lock.unlock() }
        return _updates
    }

    var finishCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _finishCount
    }

    var lastUpdate: ImportQueueProgress? {
        lock.lock()
        defer { lock.unlock() }
        return _updates.last
    }

    func importQueueDidUpdateProgress(_ progress: ImportQueueProgress) {
        lock.lock()
        defer { lock.unlock() }
        _updates.append(progress)
    }

    func importQueueDidFinish(_ progress: ImportQueueProgress) {
        lock.lock()
        defer { lock.unlock() }
        _finishCount += 1
    }
}

@Suite("ImportQueue Tests")
struct ImportQueueTests {

    // MARK: - Helpers

    /// Create a temporary file for testing.
    private func createTempFile(
        filename: String = "test_video.mp4",
        size: Int = 1024
    ) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let filePath = tempDir.appendingPathComponent(UUID().uuidString + "_" + filename).path
        let data = Data(repeating: 0xAB, count: size)
        try data.write(to: URL(fileURLWithPath: filePath))
        return filePath
    }

    /// Clean up a temp file.
    private func cleanupFile(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Initial State

    @Test("Initial state: not processing, no pending items")
    func initialState() async {
        let queue = ImportQueue()

        let processing = await queue.processing
        let pending = await queue.pendingCount
        let progress = await queue.currentProgress

        #expect(!processing)
        #expect(pending == 0)
        #expect(progress.totalFiles == 0)
        #expect(progress.isComplete)
    }

    // MARK: - Enqueue

    @Test("Enqueue adds tasks and starts processing")
    func enqueueStartsProcessing() async throws {
        let queue = ImportQueue()
        let filePath = try createTempFile()
        defer { cleanupFile(filePath) }

        let task = ImportTask(
            tempFilePath: filePath,
            filename: "test.mp4",
            expectedType: .video,
            source: .files
        )

        await queue.enqueue([task])

        // Give processing time to start/complete
        try await Task.sleep(for: .milliseconds(200))

        let progress = await queue.currentProgress
        #expect(progress.totalFiles == 1)
    }

    @Test("Enqueue multiple tasks tracks all progress")
    func enqueueMultiple() async throws {
        let queue = ImportQueue()

        var paths: [String] = []
        var tasks: [ImportTask] = []

        for i in 0..<3 {
            let path = try createTempFile(filename: "video_\(i).mp4")
            paths.append(path)
            tasks.append(ImportTask(
                tempFilePath: path,
                filename: "video_\(i).mp4",
                expectedType: .video,
                source: .photoLibrary
            ))
        }
        defer { paths.forEach { cleanupFile($0) } }

        await queue.enqueue(tasks)

        // Wait for processing to complete
        try await Task.sleep(for: .milliseconds(500))

        let progress = await queue.currentProgress
        #expect(progress.totalFiles == 3)
    }

    // MARK: - File Validation

    @Test("Missing file results in failed state")
    func missingFile() async throws {
        let queue = ImportQueue()

        let task = ImportTask(
            tempFilePath: "/nonexistent/path/video.mp4",
            filename: "video.mp4",
            expectedType: .video,
            source: .files
        )

        await queue.enqueue([task])
        try await Task.sleep(for: .milliseconds(200))

        let progress = await queue.currentProgress
        #expect(progress.failedFiles == 1)

        let fileProgress = progress.fileProgress.first
        #expect(fileProgress?.state == .failed)
        #expect(fileProgress?.errorMessage == "File not found")
    }

    @Test("Empty file results in failed state")
    func emptyFile() async throws {
        let queue = ImportQueue()
        let path = try createTempFile(size: 0)
        defer { cleanupFile(path) }

        let task = ImportTask(
            tempFilePath: path,
            filename: "empty.mp4",
            expectedType: .video,
            source: .files
        )

        await queue.enqueue([task])
        try await Task.sleep(for: .milliseconds(200))

        let progress = await queue.currentProgress
        #expect(progress.failedFiles == 1)

        let fileProgress = progress.fileProgress.first
        #expect(fileProgress?.state == .failed)
        #expect(fileProgress?.errorMessage == "File is empty")
    }

    // MARK: - Cancel

    @Test("CancelAll cancels queued items")
    func cancelAll() async throws {
        let queue = ImportQueue()

        // Create tasks but use nonexistent slow paths so queue stays full
        var tasks: [ImportTask] = []
        for i in 0..<5 {
            tasks.append(ImportTask(
                tempFilePath: "/nonexistent/\(i).mp4",
                filename: "file_\(i).mp4",
                expectedType: .video,
                source: .files
            ))
        }

        await queue.enqueue(tasks)
        await queue.cancelAll()

        let progress = await queue.currentProgress
        #expect(progress.isCancelled)
        // Some items may have already been picked up for processing
        // The remaining should be cancelled
        let cancelledCount = progress.fileProgress.filter { $0.state == .cancelled }.count
        let failedCount = progress.fileProgress.filter { $0.state == .failed }.count
        #expect(cancelledCount + failedCount == 5)
    }

    // MARK: - Clear Finished

    @Test("ClearFinished removes completed and failed entries")
    func clearFinished() async throws {
        let queue = ImportQueue()

        // Enqueue a task that will fail (missing file)
        let task = ImportTask(
            tempFilePath: "/nonexistent/video.mp4",
            filename: "video.mp4",
            expectedType: .video,
            source: .files
        )
        await queue.enqueue([task])
        try await Task.sleep(for: .milliseconds(200))

        // Verify failed
        var progress = await queue.currentProgress
        #expect(progress.failedFiles == 1)

        // Clear
        await queue.clearFinished()

        progress = await queue.currentProgress
        #expect(progress.totalFiles == 0)
    }

    // MARK: - Retry

    @Test("RetryFailed re-queues failed items")
    func retryFailed() async throws {
        let queue = ImportQueue()

        let task = ImportTask(
            tempFilePath: "/nonexistent/video.mp4",
            filename: "video.mp4",
            expectedType: .video,
            source: .files
        )
        await queue.enqueue([task])
        try await Task.sleep(for: .milliseconds(200))

        // Verify failed
        var progress = await queue.currentProgress
        #expect(progress.failedFiles == 1)

        // Retry
        await queue.retryFailed()
        try await Task.sleep(for: .milliseconds(200))

        // Still fails (file still doesn't exist) but was re-queued
        progress = await queue.currentProgress
        #expect(progress.failedFiles >= 1)
    }

    // MARK: - Delegate

    @Test("Delegate receives progress updates")
    func delegateUpdates() async throws {
        let queue = ImportQueue()
        let delegate = MockImportQueueDelegate()
        await queue.setDelegate(delegate)

        let task = ImportTask(
            tempFilePath: "/nonexistent/video.mp4",
            filename: "video.mp4",
            expectedType: .video,
            source: .files
        )

        await queue.enqueue([task])
        try await Task.sleep(for: .milliseconds(300))

        // Delegate should have received updates
        #expect(delegate.updates.count > 0)
        #expect(delegate.finishCount >= 1)
    }

    // MARK: - Extension Utility

    @Test("extensionFromPath extracts lowercase extension")
    func extensionFromPath() {
        #expect(ImportQueue.extensionFromPath("/path/to/video.MP4") == ".mp4")
        #expect(ImportQueue.extensionFromPath("/path/to/image.PNG") == ".png")
        #expect(ImportQueue.extensionFromPath("/path/to/noext") == "")
        #expect(ImportQueue.extensionFromPath("/path/to/file.MOV") == ".mov")
    }

    // MARK: - Progress Tracking

    @Test("Progress reports correct counts")
    func progressCounts() async throws {
        let queue = ImportQueue()

        // Mix of valid and invalid files
        let validPath = try createTempFile()
        defer { cleanupFile(validPath) }

        let tasks = [
            ImportTask(
                tempFilePath: validPath,
                filename: "good.mp4",
                expectedType: .video,
                source: .files
            ),
            ImportTask(
                tempFilePath: "/nonexistent/bad.mp4",
                filename: "bad.mp4",
                expectedType: .video,
                source: .files
            ),
        ]

        await queue.enqueue(tasks)
        try await Task.sleep(for: .milliseconds(500))

        let progress = await queue.currentProgress
        #expect(progress.totalFiles == 2)
        // Valid file should complete or fail depending on destination
        // Invalid file should fail
        #expect(progress.failedFiles + progress.completedFiles == 2)
    }
}

// MARK: - ImportQueue Helper Extension for Tests

extension ImportQueue {
    /// Set the delegate (test helper for actor-isolated property).
    func setDelegate(_ delegate: ImportQueueDelegate?) {
        self.delegate = delegate
    }
}
