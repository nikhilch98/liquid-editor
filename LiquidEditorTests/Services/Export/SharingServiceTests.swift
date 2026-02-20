import Testing
import Foundation
@testable import LiquidEditor

@Suite("SharingService Tests")
struct SharingServiceTests {

    // MARK: - ShareResult Model

    @Test("ShareResult stores didShare correctly")
    func shareResultDidShare() {
        let result = ShareResult(didShare: true, activityType: "AirDrop", errorMessage: nil)
        #expect(result.didShare == true)
        #expect(result.activityType == "AirDrop")
        #expect(result.errorMessage == nil)
    }

    @Test("ShareResult stores error message")
    func shareResultError() {
        let result = ShareResult(
            didShare: false,
            activityType: nil,
            errorMessage: "User cancelled"
        )
        #expect(result.didShare == false)
        #expect(result.activityType == nil)
        #expect(result.errorMessage == "User cancelled")
    }

    @Test("ShareResult is Sendable")
    func shareResultSendable() async {
        let result = ShareResult(didShare: true, activityType: nil, errorMessage: nil)
        let task = Task { result }
        let retrieved = await task.value
        #expect(retrieved.didShare == true)
    }

    // MARK: - SharingError

    @Test("SharingError.fileNotFound has associated message")
    func sharingErrorFileNotFound() {
        let error = SharingError.fileNotFound("test path")
        switch error {
        case .fileNotFound(let message):
            #expect(message == "test path")
        default:
            Issue.record("Expected fileNotFound")
        }
    }

    @Test("SharingError.noViewController is distinct case")
    func sharingErrorNoViewController() {
        let error = SharingError.noViewController
        switch error {
        case .noViewController:
            break // Expected
        default:
            Issue.record("Expected noViewController")
        }
    }

    @Test("SharingError.saveFailed has associated message")
    func sharingErrorSaveFailed() {
        let error = SharingError.saveFailed("Write failed")
        switch error {
        case .saveFailed(let message):
            #expect(message == "Write failed")
        default:
            Issue.record("Expected saveFailed")
        }
    }

    @Test("SharingError.permissionDenied is distinct case")
    func sharingErrorPermissionDenied() {
        let error = SharingError.permissionDenied
        switch error {
        case .permissionDenied:
            break // Expected
        default:
            Issue.record("Expected permissionDenied")
        }
    }

    @Test("SharingError conforms to Error protocol")
    func sharingErrorConformsToError() {
        let error: any Error = SharingError.fileNotFound("test")
        #expect(error is SharingError)
    }

    @Test("SharingError is Sendable")
    func sharingErrorSendable() async {
        let error = SharingError.fileNotFound("path")
        let task = Task { error }
        let retrieved = await task.value
        switch retrieved {
        case .fileNotFound(let msg):
            #expect(msg == "path")
        default:
            Issue.record("Unexpected error case")
        }
    }

    // MARK: - SharingService File Validation (no UI)

    @Test("shareFile throws for non-existent file")
    @MainActor func shareFileNonExistent() async {
        let service = SharingService()
        do {
            _ = try await service.shareFile(filePath: "/nonexistent/path/video.mp4")
            Issue.record("Should have thrown")
        } catch let error as SharingError {
            switch error {
            case .fileNotFound:
                break // Expected
            default:
                Issue.record("Expected fileNotFound, got \(error)")
            }
        } catch {
            Issue.record("Expected SharingError, got \(error)")
        }
    }

    @Test("shareFiles throws for empty file list")
    @MainActor func shareFilesEmpty() async {
        let service = SharingService()
        do {
            _ = try await service.shareFiles(filePaths: ["/nonexistent/a.mp4", "/nonexistent/b.mp4"])
            Issue.record("Should have thrown")
        } catch let error as SharingError {
            switch error {
            case .fileNotFound:
                break // Expected
            default:
                Issue.record("Expected fileNotFound, got \(error)")
            }
        } catch {
            Issue.record("Expected SharingError, got \(error)")
        }
    }

    @Test("saveToPhotos throws for non-existent file")
    @MainActor func saveToPhotosNonExistent() async {
        let service = SharingService()
        do {
            try await service.saveToPhotos(filePath: "/nonexistent/video.mp4")
            Issue.record("Should have thrown")
        } catch let error as SharingError {
            switch error {
            case .fileNotFound:
                break // Expected
            default:
                Issue.record("Expected fileNotFound, got \(error)")
            }
        } catch {
            Issue.record("Expected SharingError, got \(error)")
        }
    }

    @Test("saveImageToPhotos throws for non-existent file")
    @MainActor func saveImageNonExistent() async {
        let service = SharingService()
        do {
            try await service.saveImageToPhotos(filePath: "/nonexistent/image.png")
            Issue.record("Should have thrown")
        } catch let error as SharingError {
            switch error {
            case .fileNotFound:
                break // Expected
            default:
                Issue.record("Expected fileNotFound, got \(error)")
            }
        } catch {
            Issue.record("Expected SharingError, got \(error)")
        }
    }

    // MARK: - Clipboard

    @Test("copyToClipboard does not crash")
    @MainActor func copyToClipboardNoCrash() {
        let service = SharingService()
        service.copyToClipboard(filePath: "/tmp/test.mp4")
        // No crash = success
    }
}
