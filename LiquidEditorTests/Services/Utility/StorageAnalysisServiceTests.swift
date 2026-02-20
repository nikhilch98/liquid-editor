import Testing
import Foundation
@testable import LiquidEditor

@Suite("StorageAnalysisService Tests")
struct StorageAnalysisServiceTests {

    // MARK: - ProjectStorageInfo

    @Suite("ProjectStorageInfo")
    struct ProjectStorageInfoTests {

        @Test("totalSize is sum of all components")
        func totalSize() {
            let info = ProjectStorageInfo(
                projectId: "test-id",
                projectName: "Test Project",
                projectFileSize: 1000,
                mediaFileSize: 50000,
                thumbnailSize: 2000
            )
            #expect(info.totalSize == 53000)
        }

        @Test("totalSize is 0 when all components are 0")
        func zeroTotal() {
            let info = ProjectStorageInfo(
                projectId: "empty",
                projectName: "Empty",
                projectFileSize: 0,
                mediaFileSize: 0,
                thumbnailSize: 0
            )
            #expect(info.totalSize == 0)
        }

        @Test("Equatable works correctly")
        func equality() {
            let a = ProjectStorageInfo(
                projectId: "id1",
                projectName: "P1",
                projectFileSize: 100,
                mediaFileSize: 200,
                thumbnailSize: 50
            )
            let b = ProjectStorageInfo(
                projectId: "id1",
                projectName: "P1",
                projectFileSize: 100,
                mediaFileSize: 200,
                thumbnailSize: 50
            )
            #expect(a == b)
        }
    }

    // MARK: - OrphanedFileCategory

    @Suite("OrphanedFileCategory")
    struct CategoryTests {

        @Test("allCases contains 4 categories")
        func allCasesCount() {
            #expect(OrphanedFileCategory.allCases.count == 4)
        }

        @Test("Contains expected categories")
        func expectedCategories() {
            let cases = OrphanedFileCategory.allCases
            #expect(cases.contains(.video))
            #expect(cases.contains(.thumbnail))
            #expect(cases.contains(.cache))
            #expect(cases.contains(.temporary))
        }
    }

    // MARK: - CleanupAction

    @Suite("CleanupAction")
    struct ActionTests {

        @Test("allCases contains 5 actions")
        func allCasesCount() {
            #expect(CleanupAction.allCases.count == 5)
        }

        @Test("Each action has a unique rawValue")
        func uniqueRawValues() {
            let rawValues = Set(CleanupAction.allCases.map(\.rawValue))
            #expect(rawValues.count == CleanupAction.allCases.count)
        }
    }

    // MARK: - StorageAnalysisResult

    @Suite("StorageAnalysisResult")
    struct ResultTests {

        @Test("totalProjectStorage sums all project totals")
        func totalProjectStorage() {
            let result = StorageAnalysisResult(
                projects: [
                    ProjectStorageInfo(
                        projectId: "1",
                        projectName: "P1",
                        projectFileSize: 100,
                        mediaFileSize: 1000,
                        thumbnailSize: 50
                    ),
                    ProjectStorageInfo(
                        projectId: "2",
                        projectName: "P2",
                        projectFileSize: 200,
                        mediaFileSize: 2000,
                        thumbnailSize: 100
                    ),
                ],
                orphanedFiles: [],
                suggestions: []
            )
            #expect(result.totalProjectStorage == 3450)
        }

        @Test("totalOrphanedStorage sums all orphaned files")
        func totalOrphanedStorage() {
            let result = StorageAnalysisResult(
                projects: [],
                orphanedFiles: [
                    OrphanedFile(path: "/a.mp4", fileSize: 5000, lastModified: Date(), category: .video),
                    OrphanedFile(path: "/b.mp4", fileSize: 3000, lastModified: Date(), category: .video),
                ],
                suggestions: []
            )
            #expect(result.totalOrphanedStorage == 8000)
        }

        @Test("totalStorage is projects + orphaned")
        func totalStorage() {
            let result = StorageAnalysisResult(
                projects: [
                    ProjectStorageInfo(
                        projectId: "1",
                        projectName: "P1",
                        projectFileSize: 100,
                        mediaFileSize: 0,
                        thumbnailSize: 0
                    ),
                ],
                orphanedFiles: [
                    OrphanedFile(path: "/a.mp4", fileSize: 200, lastModified: Date(), category: .video),
                ],
                suggestions: []
            )
            #expect(result.totalStorage == 300)
        }

        @Test("totalPotentialSavings sums all suggestions")
        func totalPotentialSavings() {
            let result = StorageAnalysisResult(
                projects: [],
                orphanedFiles: [],
                suggestions: [
                    CleanupSuggestion(
                        description: "Remove orphans",
                        estimatedSavings: 5000,
                        action: .removeOrphanedVideos,
                        filePaths: []
                    ),
                    CleanupSuggestion(
                        description: "Clear temp",
                        estimatedSavings: 1000,
                        action: .clearTemporaryFiles,
                        filePaths: []
                    ),
                ]
            )
            #expect(result.totalPotentialSavings == 6000)
        }

        @Test("Empty result has all zeros")
        func emptyResult() {
            let result = StorageAnalysisResult(
                projects: [],
                orphanedFiles: [],
                suggestions: []
            )
            #expect(result.totalProjectStorage == 0)
            #expect(result.totalOrphanedStorage == 0)
            #expect(result.totalStorage == 0)
            #expect(result.totalPotentialSavings == 0)
        }
    }

    // MARK: - Directory Size Calculation

    @Suite("Directory Size")
    struct DirectorySizeTests {

        @Test("directorySize returns 0 for nonexistent path")
        func nonexistentPath() {
            let size = StorageAnalysisService.directorySize(
                atPath: "/nonexistent/\(UUID().uuidString)"
            )
            #expect(size == 0)
        }
    }

    // MARK: - Byte Formatting

    @Suite("Byte Formatting")
    struct FormattingTests {

        @Test("formatStorageBytes produces non-empty string for positive values")
        func formatsPositive() {
            let formatted = formatStorageBytes(1_048_576)
            #expect(!formatted.isEmpty)
        }

        @Test("formatStorageBytes handles zero bytes")
        func formatsZero() {
            let formatted = formatStorageBytes(0)
            #expect(!formatted.isEmpty)
        }
    }
}
