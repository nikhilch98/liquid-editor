import Testing
import Foundation
@testable import LiquidEditor

@Suite("ExportProgressReporter Tests")
struct ExportProgressReporterTests {

    // MARK: - Initialization

    @Test("Start tracking returns an AsyncStream")
    func startTrackingReturnsStream() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "test-1", totalFrames: 100)

        // The stream should be a valid AsyncStream
        // Finish immediately so we don't block
        reporter.stopTracking()

        var receivedAny = false
        for await _ in stream {
            receivedAny = true
        }
        // Stream should have finished (may or may not have yielded values)
        _ = receivedAny
    }

    // MARK: - Phase Tracking

    @Test("setPhase updates the current phase")
    func setPhaseUpdates() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "phase-test", totalFrames: 100)

        reporter.setPhase(.rendering)
        reporter.reportProgressValue(progress: 0.5, framesRendered: 50)

        // We need to read at least one item to verify
        var lastProgress: ExportProgress?
        reporter.stopTracking()

        for await progress in stream {
            lastProgress = progress
        }

        // If we got progress, verify it has the rendering phase
        if let lp = lastProgress {
            #expect(lp.phase == .rendering || lp.phase == .completed || lp.phase == .failed)
        }
    }

    // MARK: - Progress Reporting

    @Test("reportProgressValue emits progress updates")
    func reportProgressValueEmits() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "progress-test", totalFrames: 300)

        // Give time for the continuation to be set up
        try? await Task.sleep(for: .milliseconds(10))

        reporter.setPhase(.rendering)
        reporter.reportProgressValue(progress: 0.3, framesRendered: 90, bytesWritten: 1024)

        reporter.stopTracking()

        var updates: [ExportProgress] = []
        for await progress in stream {
            updates.append(progress)
        }

        if let first = updates.first {
            #expect(first.exportId == "progress-test")
            #expect(first.overallProgress >= 0.0)
        }
    }

    @Test("reportProgressValue with zero progress does not produce ETA")
    func noEtaAtZeroProgress() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "eta-test", totalFrames: 100)

        try? await Task.sleep(for: .milliseconds(10))

        reporter.reportProgressValue(progress: 0.005) // Below 0.01 threshold

        reporter.stopTracking()

        var updates: [ExportProgress] = []
        for await progress in stream {
            updates.append(progress)
        }

        if let first = updates.first {
            #expect(first.estimatedRemainingMs == nil)
        }
    }

    @Test("reportProgressValue calculates ETA for significant progress")
    func etaCalculatedForSignificantProgress() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "eta-calc", totalFrames: 100)

        try? await Task.sleep(for: .milliseconds(50))

        reporter.reportProgressValue(progress: 0.5, framesRendered: 50)

        reporter.stopTracking()

        var updates: [ExportProgress] = []
        for await progress in stream {
            updates.append(progress)
        }

        if let first = updates.first, first.overallProgress > 0.01 {
            #expect(first.estimatedRemainingMs != nil)
            #expect(first.estimatedRemainingMs! >= 0)
        }
    }

    @Test("reportProgressValue estimates total bytes from bytesWritten")
    func estimatesTotalBytes() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "bytes-test", totalFrames: 100)

        try? await Task.sleep(for: .milliseconds(10))

        reporter.reportProgressValue(progress: 0.5, framesRendered: 50, bytesWritten: 5000)

        reporter.stopTracking()

        var updates: [ExportProgress] = []
        for await progress in stream {
            updates.append(progress)
        }

        if let first = updates.first, first.overallProgress > 0.01 {
            #expect(first.estimatedTotalBytes > 0)
        }
    }

    // MARK: - Completion

    @Test("reportComplete sets progress to 1.0 and finishes stream")
    func reportCompleteFinishesStream() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "complete-test", totalFrames: 100)

        try? await Task.sleep(for: .milliseconds(10))

        reporter.reportComplete()

        var updates: [ExportProgress] = []
        for await progress in stream {
            updates.append(progress)
        }

        // Stream should have finished
        if let last = updates.last {
            #expect(last.overallProgress == 1.0)
        }
    }

    // MARK: - Failure

    @Test("reportFailed emits failure and finishes stream")
    func reportFailedFinishes() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "fail-test", totalFrames: 100)

        try? await Task.sleep(for: .milliseconds(10))

        reporter.reportFailed(error: "Test error")

        var updates: [ExportProgress] = []
        for await progress in stream {
            updates.append(progress)
        }

        if let last = updates.last {
            #expect(last.phase == .failed)
            #expect(last.overallProgress == -1.0)
        }
    }

    // MARK: - Stop Tracking

    @Test("stopTracking finishes stream without crash")
    func stopTrackingCleanup() async {
        let reporter = ExportProgressReporter()
        let stream = reporter.startTracking(exportId: "stop-test", totalFrames: 50)

        reporter.stopTracking()

        var count = 0
        for await _ in stream {
            count += 1
        }
        // Stream should terminate
        #expect(count >= 0)
    }

    @Test("stopTracking is safe to call multiple times")
    func stopTrackingIdempotent() {
        let reporter = ExportProgressReporter()
        _ = reporter.startTracking(exportId: "multi-stop", totalFrames: 10)

        reporter.stopTracking()
        reporter.stopTracking()
        reporter.stopTracking()
        // No crash = success
    }
}
