// StickerImportServiceTests.swift
// LiquidEditorTests
//
// Tests for StickerImportService using Swift Testing.
// Validates file import, bytes import, validation, deletion,
// and listing of imported sticker files.

import Testing
import Foundation
import UIKit
@testable import LiquidEditor

@Suite("StickerImportService Tests")
struct StickerImportServiceTests {

    // MARK: - Helpers

    private let service = StickerImportService()

    /// Create a minimal valid PNG file at a temp path.
    private func createTempPNG(filename: String = "sticker.png") throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let filePath = tempDir.appendingPathComponent(
            UUID().uuidString + "_" + filename
        ).path

        // Create a 1x1 red pixel PNG via UIImage
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let data = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        try data.write(to: URL(fileURLWithPath: filePath))
        return filePath
    }

    /// Create a temp file with arbitrary data (not a valid image).
    private func createTempInvalidFile(
        filename: String = "invalid.png"
    ) throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let filePath = tempDir.appendingPathComponent(
            UUID().uuidString + "_" + filename
        ).path
        let data = Data([0x00, 0x01, 0x02, 0x03])
        try data.write(to: URL(fileURLWithPath: filePath))
        return filePath
    }

    /// Create valid PNG data in memory.
    private func createPNGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Import from File

    @Test("Import valid PNG file succeeds")
    func importValidPNG() async throws {
        let path = try createTempPNG()
        defer { cleanup(path) }

        let result = await service.importFromFile(path)

        #expect(result.isSuccess)
        #expect(result.asset != nil)
        #expect(result.asset?.type == .staticImage)
        #expect(result.asset?.categoryId == "imported")
        #expect(result.asset?.isBuiltIn == false)
        #expect(result.asset?.id.hasPrefix("imported_") == true)

        // Clean up imported file
        if let assetPath = result.asset?.assetPath {
            cleanup(assetPath)
        }
    }

    @Test("Import with custom name uses provided name")
    func importWithCustomName() async throws {
        let path = try createTempPNG()
        defer { cleanup(path) }

        let result = await service.importFromFile(path, name: "My Custom Sticker")

        #expect(result.isSuccess)
        #expect(result.asset?.name == "My Custom Sticker")

        if let assetPath = result.asset?.assetPath {
            cleanup(assetPath)
        }
    }

    @Test("Import missing file fails")
    func importMissingFile() async {
        let result = await service.importFromFile("/nonexistent/sticker.png")

        #expect(!result.isSuccess)
        #expect(result.error == "File not found.")
    }

    @Test("Import unsupported extension fails")
    func importUnsupportedExtension() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let path = tempDir.appendingPathComponent(
            UUID().uuidString + "_sticker.bmp"
        ).path
        // Create a minimal file
        try Data([0x42, 0x4D]).write(to: URL(fileURLWithPath: path))
        defer { cleanup(path) }

        let result = await service.importFromFile(path)

        #expect(!result.isSuccess)
        #expect(result.error?.contains("Unsupported file type") == true)
    }

    @Test("Import file exceeding max size fails")
    func importTooLargeFile() async throws {
        // Create a file that claims to be > 10 MB
        let tempDir = FileManager.default.temporaryDirectory
        let path = tempDir.appendingPathComponent(
            UUID().uuidString + "_large.png"
        ).path
        // Write 10 MB + 1 byte
        let data = Data(repeating: 0xFF, count: StickerImportService.maxFileSizeBytes + 1)
        try data.write(to: URL(fileURLWithPath: path))
        defer { cleanup(path) }

        let result = await service.importFromFile(path)

        #expect(!result.isSuccess)
        #expect(result.error?.contains("too large") == true)
    }

    @Test("Import invalid image data fails")
    func importInvalidImageData() async throws {
        let path = try createTempInvalidFile()
        defer { cleanup(path) }

        let result = await service.importFromFile(path)

        #expect(!result.isSuccess)
        #expect(result.error?.contains("not a valid image") == true)
    }

    // MARK: - Import from Bytes

    @Test("Import valid PNG bytes succeeds")
    func importValidPNGBytes() async {
        let data = createPNGData()

        let result = await service.importFromBytes(
            data,
            fileExtension: ".png",
            name: "Blue Square"
        )

        #expect(result.isSuccess)
        #expect(result.asset?.name == "Blue Square")
        #expect(result.asset?.type == .staticImage)

        if let assetPath = result.asset?.assetPath {
            cleanup(assetPath)
        }
    }

    @Test("Import bytes with extension without dot normalizes it")
    func importBytesNormalizeExtension() async {
        let data = createPNGData()

        let result = await service.importFromBytes(
            data,
            fileExtension: "png",
            name: "NoDot"
        )

        #expect(result.isSuccess)

        if let assetPath = result.asset?.assetPath {
            cleanup(assetPath)
        }
    }

    @Test("Import bytes exceeding max size fails")
    func importBytesTooLarge() async {
        let largeData = Data(repeating: 0xFF, count: StickerImportService.maxFileSizeBytes + 1)

        let result = await service.importFromBytes(
            largeData,
            fileExtension: ".png",
            name: "TooLarge"
        )

        #expect(!result.isSuccess)
        #expect(result.error?.contains("too large") == true)
    }

    @Test("Import bytes with unsupported extension fails")
    func importBytesUnsupportedExtension() async {
        let data = createPNGData()

        let result = await service.importFromBytes(
            data,
            fileExtension: ".bmp",
            name: "Unsupported"
        )

        #expect(!result.isSuccess)
        #expect(result.error?.contains("Unsupported file type") == true)
    }

    // MARK: - Delete

    @Test("Delete imported sticker removes file")
    func deleteImportedSticker() async throws {
        let path = try createTempPNG()
        defer { cleanup(path) }

        let result = await service.importFromFile(path)
        guard let assetPath = result.asset?.assetPath else {
            Issue.record("Import should succeed")
            return
        }

        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: assetPath))

        // Delete
        let deleted = service.deleteImportedSticker(atPath: assetPath)
        #expect(deleted)
        #expect(!FileManager.default.fileExists(atPath: assetPath))
    }

    @Test("Delete nonexistent file returns false")
    func deleteNonexistent() {
        let deleted = service.deleteImportedSticker(atPath: "/nonexistent/sticker.png")
        #expect(!deleted)
    }

    @Test("Delete file outside import directory is refused")
    func deleteOutsideImportDir() throws {
        // Create a temp file in the system temp directory
        let path = try createTempPNG()
        defer { cleanup(path) }

        let deleted = service.deleteImportedSticker(atPath: path)
        #expect(!deleted)
        // File should still exist
        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - List Imported

    @Test("List imported files returns sticker paths")
    func listImportedFiles() async throws {
        let path = try createTempPNG()
        defer { cleanup(path) }

        let result = await service.importFromFile(path)
        guard let assetPath = result.asset?.assetPath else {
            Issue.record("Import should succeed")
            return
        }
        defer { cleanup(assetPath) }

        let files = service.listImportedFiles()
        #expect(files.contains(assetPath))
    }

    // MARK: - Supported Formats

    @Test("Supported extensions include PNG, WebP, GIF")
    func supportedExtensions() {
        #expect(StickerImportService.supportedExtensions.contains(".png"))
        #expect(StickerImportService.supportedExtensions.contains(".webp"))
        #expect(StickerImportService.supportedExtensions.contains(".gif"))
        #expect(!StickerImportService.supportedExtensions.contains(".jpg"))
        #expect(!StickerImportService.supportedExtensions.contains(".bmp"))
    }

    // MARK: - Type from Extension

    @Test("GIF extension maps to gif type")
    func gifExtension() {
        #expect(StickerImportService.typeFromExtension(".gif") == .gif)
    }

    @Test("PNG extension maps to staticImage type")
    func pngExtension() {
        #expect(StickerImportService.typeFromExtension(".png") == .staticImage)
    }

    @Test("WebP extension maps to staticImage type")
    func webpExtension() {
        #expect(StickerImportService.typeFromExtension(".webp") == .staticImage)
    }

    // MARK: - Keyword Generation

    @Test("Generate keywords splits and lowercases name")
    func generateKeywords() {
        let keywords = StickerImportService.generateKeywords("My Cool Sticker")
        #expect(keywords == ["my", "cool", "sticker"])
    }

    @Test("Generate keywords strips special characters")
    func generateKeywordsSpecialChars() {
        let keywords = StickerImportService.generateKeywords("star-burst #1!")
        #expect(keywords == ["starburst", "1"])
    }

    // MARK: - Display Name

    @Test("Display name strips extension from filename")
    func displayName() {
        let name = StickerImportService.displayNameFromPath(
            "/path/to/my_sticker.png",
            extension: ".png"
        )
        #expect(name == "my_sticker")
    }

    @Test("Display name handles path without extension")
    func displayNameNoExtension() {
        let name = StickerImportService.displayNameFromPath(
            "/path/to/my_sticker",
            extension: ".png"
        )
        #expect(name == "my_sticker")
    }

    // MARK: - Extension Extraction

    @Test("getExtension extracts lowercase extension")
    func getExtension() {
        #expect(StickerImportService.getExtension("/path/sticker.PNG") == ".png")
        #expect(StickerImportService.getExtension("/path/sticker.gif") == ".gif")
        #expect(StickerImportService.getExtension("/path/noext") == "")
    }
}
