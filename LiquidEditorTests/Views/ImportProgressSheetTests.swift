import Testing
import Foundation
@testable import LiquidEditor

@Suite("ImportProgressSheet Tests")
struct ImportProgressSheetTests {

    // MARK: - ImportFileState

    @Suite("ImportFileState")
    struct ImportFileStateTests {

        @Test("allCases contains all 9 states")
        func allCasesCount() {
            #expect(ImportFileState.allCases.count == 9)
        }

        @Test("isInProgress returns true only for active states")
        func isInProgress() {
            let activeStates: [ImportFileState] = [
                .copying, .hashing, .extractingMetadata, .generatingThumbnail,
            ]
            for state in ImportFileState.allCases {
                #expect(state.isInProgress == activeStates.contains(state))
            }
        }

        @Test("isTerminal returns true only for terminal states")
        func isTerminal() {
            let terminalStates: [ImportFileState] = [
                .complete, .duplicate, .failed, .cancelled,
            ]
            for state in ImportFileState.allCases {
                #expect(state.isTerminal == terminalStates.contains(state))
            }
        }

        @Test("queued is neither in progress nor terminal")
        func queuedState() {
            #expect(ImportFileState.queued.isInProgress == false)
            #expect(ImportFileState.queued.isTerminal == false)
        }
    }

    // MARK: - ImportFileProgress

    @Suite("ImportFileProgress")
    struct ImportFileProgressTests {

        @Test("Default values are correct")
        func defaults() {
            let progress = ImportFileProgress(filename: "test.mp4")
            #expect(progress.filename == "test.mp4")
            #expect(progress.state == .queued)
            #expect(progress.progress == 0.0)
            #expect(progress.errorMessage == nil)
        }

        @Test("Custom init values are preserved")
        func customInit() {
            let progress = ImportFileProgress(
                id: "custom-id",
                filename: "video.mov",
                state: .copying,
                progress: 0.75,
                errorMessage: nil
            )
            #expect(progress.id == "custom-id")
            #expect(progress.filename == "video.mov")
            #expect(progress.state == .copying)
            #expect(progress.progress == 0.75)
        }

        @Test("with() updates only specified fields")
        func withMethod() {
            let original = ImportFileProgress(
                id: "test-id",
                filename: "clip.mp4",
                state: .queued,
                progress: 0.0
            )

            let updated = original.with(state: .copying, progress: 0.5)
            #expect(updated.id == "test-id")
            #expect(updated.filename == "clip.mp4")
            #expect(updated.state == .copying)
            #expect(updated.progress == 0.5)
            #expect(updated.errorMessage == nil)
        }

        @Test("with() can set error message")
        func withErrorMessage() {
            let original = ImportFileProgress(filename: "bad.avi", state: .copying)
            let updated = original.with(
                state: .failed,
                errorMessage: "Unsupported codec"
            )
            #expect(updated.state == .failed)
            #expect(updated.errorMessage == "Unsupported codec")
        }

        @Test("id is auto-generated when not provided")
        func autoId() {
            let a = ImportFileProgress(filename: "a.mp4")
            let b = ImportFileProgress(filename: "b.mp4")
            #expect(a.id != b.id)
        }
    }

    // MARK: - ImportQueueProgress

    @Suite("ImportQueueProgress")
    struct ImportQueueProgressTests {

        @Test("Default values are all zero")
        func defaults() {
            let progress = ImportQueueProgress()
            #expect(progress.totalFiles == 0)
            #expect(progress.completedFiles == 0)
            #expect(progress.failedFiles == 0)
            #expect(progress.duplicateFiles == 0)
            #expect(progress.fileProgress.isEmpty)
            #expect(progress.isCancelled == false)
        }

        @Test("overallProgress returns 0 when totalFiles is 0")
        func overallProgressEmpty() {
            let progress = ImportQueueProgress()
            #expect(progress.overallProgress == 0.0)
        }

        @Test("overallProgress calculates correctly")
        func overallProgressCalculation() {
            let progress = ImportQueueProgress(
                totalFiles: 10,
                completedFiles: 3,
                failedFiles: 1,
                duplicateFiles: 1
            )
            #expect(progress.overallProgress == 0.5)
        }

        @Test("overallProgress is 1.0 when all files are done")
        func overallProgressComplete() {
            let progress = ImportQueueProgress(
                totalFiles: 5,
                completedFiles: 3,
                failedFiles: 1,
                duplicateFiles: 1
            )
            #expect(progress.overallProgress == 1.0)
        }

        @Test("isComplete returns true when all files are processed")
        func isComplete() {
            let complete = ImportQueueProgress(
                totalFiles: 4,
                completedFiles: 2,
                failedFiles: 1,
                duplicateFiles: 1
            )
            #expect(complete.isComplete == true)

            let incomplete = ImportQueueProgress(
                totalFiles: 4,
                completedFiles: 2,
                failedFiles: 0,
                duplicateFiles: 0
            )
            #expect(incomplete.isComplete == false)
        }

        @Test("isComplete returns true when totalFiles is 0")
        func isCompleteEmpty() {
            let progress = ImportQueueProgress()
            #expect(progress.isComplete == true)
        }

        @Test("remainingFiles calculates correctly")
        func remainingFiles() {
            let progress = ImportQueueProgress(
                totalFiles: 10,
                completedFiles: 5,
                failedFiles: 2,
                duplicateFiles: 1
            )
            #expect(progress.remainingFiles == 2)
        }

        @Test("remainingFiles is zero when complete")
        func remainingFilesZero() {
            let progress = ImportQueueProgress(
                totalFiles: 3,
                completedFiles: 3
            )
            #expect(progress.remainingFiles == 0)
        }

        @Test("summaryText includes all non-zero categories")
        func summaryTextAll() {
            let progress = ImportQueueProgress(
                totalFiles: 10,
                completedFiles: 5,
                failedFiles: 2,
                duplicateFiles: 1
            )
            let summary = progress.summaryText
            #expect(summary.contains("5 complete"))
            #expect(summary.contains("1 duplicate"))
            #expect(summary.contains("2 failed"))
            #expect(summary.contains("2 remaining"))
        }

        @Test("summaryText omits zero categories")
        func summaryTextPartial() {
            let progress = ImportQueueProgress(
                totalFiles: 3,
                completedFiles: 3,
                failedFiles: 0,
                duplicateFiles: 0
            )
            let summary = progress.summaryText
            #expect(summary.contains("3 complete"))
            #expect(!summary.contains("duplicate"))
            #expect(!summary.contains("failed"))
            #expect(!summary.contains("remaining"))
        }

        @Test("summaryText is empty when totalFiles is 0")
        func summaryTextEmpty() {
            let progress = ImportQueueProgress()
            #expect(progress.summaryText.isEmpty)
        }

        @Test("summaryText uses pipe separator")
        func summaryTextSeparator() {
            let progress = ImportQueueProgress(
                totalFiles: 5,
                completedFiles: 2,
                failedFiles: 1
            )
            let summary = progress.summaryText
            #expect(summary.contains(" | "))
        }
    }

    // MARK: - ImportProgressSheet Constants

    @Suite("ImportProgressSheet Constants")
    struct SheetConstantsTests {

        @Test("maxVisibleFiles is 5")
        func maxVisibleFiles() {
            #expect(ImportProgressSheet.maxVisibleFiles == 5)
        }
    }
}
