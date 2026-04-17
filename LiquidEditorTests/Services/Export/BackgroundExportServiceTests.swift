import Testing
import Foundation
@testable import LiquidEditor

@Suite("BackgroundExportService Tests")
struct BackgroundExportServiceTests {

    // MARK: - Disk Space

    @Test("availableDiskSpaceBytes returns non-negative value")
    func availableDiskSpaceBytes() {
        let bytes = BackgroundExportService.availableDiskSpaceBytes()
        #expect(bytes >= 0)
    }

    @Test("availableDiskSpaceMB returns non-negative value")
    func availableDiskSpaceMB() {
        let mb = BackgroundExportService.availableDiskSpaceMB()
        #expect(mb >= 0)
    }

    @Test("availableDiskSpaceMB is consistent with bytes")
    func diskSpaceConsistency() {
        let bytes = BackgroundExportService.availableDiskSpaceBytes()
        let mb = BackgroundExportService.availableDiskSpaceMB()
        let expectedMB = Int(bytes / (1024 * 1024))
        #expect(mb == expectedMB)
    }

    // MARK: - Disk Space Validation

    @Test("validateDiskSpace returns nil when space is sufficient")
    func validateDiskSpaceSufficient() {
        // Request very small amount, should pass on any system
        let result = BackgroundExportService.validateDiskSpace(estimatedSizeMB: 1)
        #expect(result == nil)
    }

    @Test("validateDiskSpace returns error for extremely large requests")
    func validateDiskSpaceInsufficient() {
        // Request an absurdly large amount
        let result = BackgroundExportService.validateDiskSpace(estimatedSizeMB: 999_999_999)
        #expect(result != nil)
        #expect(result?.contains("Insufficient disk space") == true)
    }

    @Test("validateDiskSpace includes 500MB safety margin")
    func validateDiskSpaceSafetyMargin() {
        let availableMB = BackgroundExportService.availableDiskSpaceMB()
        // Request exactly what's available minus a small buffer but within safety margin
        let justOverLimit = availableMB - 400 // Inside the 500MB margin
        if justOverLimit > 0 {
            let result = BackgroundExportService.validateDiskSpace(estimatedSizeMB: justOverLimit)
            // Should fail because estimated + 500 > available
            #expect(result != nil)
        }
    }

    // MARK: - Thermal Monitoring

    @Test("thermalStateInt returns valid range 0-3")
    func thermalStateInt() {
        let state = BackgroundExportService.thermalStateInt
        #expect(state >= 0)
        #expect(state <= 3)
    }

    @Test("isThermalConcern is based on state >= 2")
    func isThermalConcern() {
        let state = BackgroundExportService.thermalStateInt
        let concern = BackgroundExportService.isThermalConcern
        if state >= 2 {
            #expect(concern == true)
        } else {
            #expect(concern == false)
        }
    }

    // MARK: - Actor Initialization

    @Test("BackgroundExportService initializes without crash")
    func initializesSuccessfully() async {
        let service = BackgroundExportService()
        let isPaused = await service.isPaused
        #expect(isPaused == false)
    }

    @Test("endBackgroundExport resets state")
    func endBackgroundExport() async {
        let service = BackgroundExportService()
        await service.endBackgroundExport()
        let isPaused = await service.isPaused
        #expect(isPaused == false)
    }

    // MARK: - Concurrent Export Cap

    @Test("beginBackgroundExport enforces maxConcurrentExports cap")
    func beginBackgroundExportCapEnforced() async {
        let limit = 2
        let service = BackgroundExportService(maxConcurrentExports: limit)

        var accepted = 0
        var rejected = 0
        var lastError: BackgroundExportService.ExportQueueError?

        // Attempt 5 concurrent exports; only `limit` should succeed, the
        // rest must be rejected with .queueFull BEFORE spawning a Task.
        for index in 0..<5 {
            do {
                try await service.beginBackgroundExport(exportId: "export_\(index)")
                accepted += 1
            } catch let error as BackgroundExportService.ExportQueueError {
                rejected += 1
                lastError = error
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }

        #expect(accepted == limit)
        #expect(rejected == 3)

        let activeCount = await service.activeExportCount
        #expect(activeCount == limit)

        if case .queueFull(_, let reportedLimit) = lastError {
            #expect(reportedLimit == limit)
        } else {
            Issue.record("Expected .queueFull error, got \(String(describing: lastError))")
        }
    }

    // MARK: - Temp File Cleanup

    @Test("cleanupOldExports runs without crash")
    func cleanupOldExports() {
        // Just ensure it doesn't crash -- no files should be affected in test
        BackgroundExportService.cleanupOldExports(olderThanDays: 7)
    }

    @Test("cleanupOldExports with zero days runs without crash")
    func cleanupOldExportsZeroDays() {
        BackgroundExportService.cleanupOldExports(olderThanDays: 0)
    }

    @Test("cleanupOldExports removes matching old files")
    func cleanupRemovesOldFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        let oldFile = tempDir.appendingPathComponent("rendered_test_cleanup.mp4")

        // Create a test file
        FileManager.default.createFile(atPath: oldFile.path, contents: Data("test".utf8))

        // Set creation date to 30 days ago
        let oldDate = Date().addingTimeInterval(-30 * 24 * 3600)
        try? FileManager.default.setAttributes(
            [.creationDate: oldDate],
            ofItemAtPath: oldFile.path
        )

        BackgroundExportService.cleanupOldExports(olderThanDays: 7)

        // File should be removed
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
    }

    @Test("cleanupOldExports does not remove non-matching files")
    func cleanupIgnoresNonMatching() {
        let tempDir = FileManager.default.temporaryDirectory
        let safeFile = tempDir.appendingPathComponent("safe_file_\(UUID().uuidString).txt")

        FileManager.default.createFile(atPath: safeFile.path, contents: Data("safe".utf8))
        defer { try? FileManager.default.removeItem(at: safeFile) }

        let oldDate = Date().addingTimeInterval(-30 * 24 * 3600)
        try? FileManager.default.setAttributes(
            [.creationDate: oldDate],
            ofItemAtPath: safeFile.path
        )

        BackgroundExportService.cleanupOldExports(olderThanDays: 7)

        // Safe file should still exist (doesn't match prefix patterns)
        #expect(FileManager.default.fileExists(atPath: safeFile.path))
    }
}
