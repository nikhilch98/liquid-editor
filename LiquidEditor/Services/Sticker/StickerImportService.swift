// StickerImportService.swift
// LiquidEditor
//
// Import user sticker images (PNG/WebP/GIF) with validation.
// Copies imported stickers to the app's Documents/stickers/imported/
// directory and generates StickerAsset metadata.
//
// Supported import formats:
// - PNG with transparency (recommended)
// - WebP with transparency
// - GIF (animated)
//
// All imported stickers are placed in the 'imported' category.

import Foundation
import UIKit
import os

// MARK: - StickerImportResult

/// Result of a sticker import operation.
enum StickerImportResult: Sendable {
    /// Import succeeded with the new sticker asset.
    case success(StickerAsset)

    /// Import failed with an error message.
    case failure(String)

    /// Whether the import succeeded.
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// The imported sticker asset (nil on failure).
    var asset: StickerAsset? {
        if case .success(let asset) = self { return asset }
        return nil
    }

    /// Error message (nil on success).
    var error: String? {
        if case .failure(let msg) = self { return msg }
        return nil
    }
}

// MARK: - StickerImportService

/// Service for importing user sticker images.
///
/// Copies sticker files to the app's documents directory and
/// generates `StickerAsset` metadata for registry integration.
///
/// Thread Safety: All methods are `async` and use `FileManager`
/// which is thread-safe for most operations. No mutable state.
struct StickerImportService: Sendable {

    // MARK: - Constants

    /// Supported file extensions for import.
    static let supportedExtensions: Set<String> = [".png", ".webp", ".gif"]

    /// Maximum file size for import (10 MB).
    static let maxFileSizeBytes: Int = 10 * 1024 * 1024

    // MARK: - Logger

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "StickerImportService"
    )

    // MARK: - Import from File

    /// Import a sticker from a file path.
    ///
    /// Validates the file, copies it to the app's stickers directory,
    /// and returns a `StickerImportResult` with the new `StickerAsset`.
    ///
    /// - Parameters:
    ///   - sourcePath: Absolute path to the source file.
    ///   - name: Display name for the sticker (defaults to filename without extension).
    /// - Returns: Result with the imported `StickerAsset` or error message.
    func importFromFile(
        _ sourcePath: String,
        name: String? = nil
    ) async -> StickerImportResult {
        let fm = FileManager.default

        // Validate file exists
        guard fm.fileExists(atPath: sourcePath) else {
            return .failure("File not found.")
        }

        // Validate file size
        do {
            let attrs = try fm.attributesOfItem(atPath: sourcePath)
            let fileSize = (attrs[.size] as? Int) ?? 0
            if fileSize > Self.maxFileSizeBytes {
                return .failure("File too large. Maximum size is 10 MB.")
            }
        } catch {
            return .failure("Could not read file attributes: \(error.localizedDescription)")
        }

        // Validate extension
        let ext = Self.getExtension(sourcePath)
        guard Self.supportedExtensions.contains(ext) else {
            return .failure(
                "Unsupported file type \"\(ext)\". "
                + "Supported: \(Self.supportedExtensions.sorted().joined(separator: ", "))."
            )
        }

        // Validate the file is a loadable image
        guard UIImage(contentsOfFile: sourcePath) != nil else {
            return .failure("File is not a valid image.")
        }

        // Determine sticker type from extension
        let stickerType = Self.typeFromExtension(ext)

        // Generate unique ID and destination path
        let assetId = "imported_\(UUID().uuidString)"
        let destDir: URL
        do {
            destDir = try Self.importedStickersDirectory()
        } catch {
            return .failure("Could not create stickers directory: \(error.localizedDescription)")
        }
        let destPath = destDir.appendingPathComponent("\(assetId)\(ext)").path

        // Copy file to app's stickers directory
        do {
            try fm.copyItem(atPath: sourcePath, toPath: destPath)
        } catch {
            return .failure("Copy failed: \(error.localizedDescription)")
        }

        // Build display name
        let displayName = name ?? Self.displayNameFromPath(sourcePath, extension: ext)

        // Create asset metadata
        let asset = StickerAsset(
            id: assetId,
            name: displayName,
            type: stickerType,
            categoryId: "imported",
            assetPath: destPath,
            isBuiltIn: false,
            keywords: Self.generateKeywords(displayName)
        )

        logger.info("Imported sticker: \(displayName) -> \(assetId)")
        return .success(asset)
    }

    // MARK: - Import from Bytes

    /// Import a sticker from raw bytes.
    ///
    /// - Parameters:
    ///   - bytes: Raw image data.
    ///   - fileExtension: File extension including dot (e.g., ".png").
    ///   - name: Display name for the sticker.
    /// - Returns: Result with the imported `StickerAsset` or error message.
    func importFromBytes(
        _ bytes: Data,
        fileExtension: String,
        name: String
    ) async -> StickerImportResult {
        // Validate size
        if bytes.count > Self.maxFileSizeBytes {
            return .failure("Image too large. Maximum size is 10 MB.")
        }

        // Validate extension
        let normalizedExt = fileExtension.hasPrefix(".")
            ? fileExtension.lowercased()
            : ".\(fileExtension.lowercased())"

        guard Self.supportedExtensions.contains(normalizedExt) else {
            return .failure(
                "Unsupported file type \"\(normalizedExt)\". "
                + "Supported: \(Self.supportedExtensions.sorted().joined(separator: ", "))."
            )
        }

        // Validate loadable
        guard UIImage(data: bytes) != nil else {
            return .failure("Data is not a valid image.")
        }

        let stickerType = Self.typeFromExtension(normalizedExt)
        let assetId = "imported_\(UUID().uuidString)"

        let destDir: URL
        do {
            destDir = try Self.importedStickersDirectory()
        } catch {
            return .failure("Could not create stickers directory: \(error.localizedDescription)")
        }
        let destPath = destDir.appendingPathComponent("\(assetId)\(normalizedExt)").path

        // Write bytes to disk
        do {
            try bytes.write(to: URL(fileURLWithPath: destPath), options: .atomic)
        } catch {
            return .failure("Write failed: \(error.localizedDescription)")
        }

        let asset = StickerAsset(
            id: assetId,
            name: name,
            type: stickerType,
            categoryId: "imported",
            assetPath: destPath,
            isBuiltIn: false,
            keywords: Self.generateKeywords(name)
        )

        logger.info("Imported sticker from bytes: \(name) -> \(assetId)")
        return .success(asset)
    }

    // MARK: - Delete

    /// Delete an imported sticker's file from disk.
    ///
    /// Only deletes files in the imported stickers directory (safety check).
    ///
    /// - Parameter assetPath: Absolute path to the sticker file.
    /// - Returns: `true` if the file was deleted.
    func deleteImportedSticker(atPath assetPath: String) -> Bool {
        let fm = FileManager.default

        guard fm.fileExists(atPath: assetPath) else { return false }

        // Safety check: only delete from our import directory
        let importDir: URL
        do {
            importDir = try Self.importedStickersDirectory()
        } catch {
            logger.error("Could not resolve import directory: \(error.localizedDescription)")
            return false
        }

        guard assetPath.hasPrefix(importDir.path) else {
            logger.warning("Refusing to delete file outside import directory: \(assetPath)")
            return false
        }

        do {
            try fm.removeItem(atPath: assetPath)
            return true
        } catch {
            logger.error("Delete failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - List Imported

    /// List all imported sticker files in the directory.
    ///
    /// - Returns: File paths for all sticker files in the imported directory.
    func listImportedFiles() -> [String] {
        let fm = FileManager.default

        let importDir: URL
        do {
            importDir = try Self.importedStickersDirectory()
        } catch {
            return []
        }

        guard fm.fileExists(atPath: importDir.path) else { return [] }

        do {
            let contents = try fm.contentsOfDirectory(
                at: importDir,
                includingPropertiesForKeys: nil
            )
            return contents
                .map(\.path)
                .filter { Self.supportedExtensions.contains(Self.getExtension($0)) }
        } catch {
            logger.error("List failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Private Helpers

    /// Get or create the imported stickers directory.
    static func importedStickersDirectory() throws -> URL {
        let fm = FileManager.default
        let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let stickersDir = docsURL
            .appendingPathComponent("stickers", isDirectory: true)
            .appendingPathComponent("imported", isDirectory: true)

        if !fm.fileExists(atPath: stickersDir.path) {
            try fm.createDirectory(at: stickersDir, withIntermediateDirectories: true)
        }

        return stickersDir
    }

    /// Extract file extension (lowercase, with dot).
    static func getExtension(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "" : ".\(ext)"
    }

    /// Map file extension to StickerAssetType.
    static func typeFromExtension(_ ext: String) -> StickerAssetType {
        switch ext {
        case ".gif": return .gif
        default: return .staticImage
        }
    }

    /// Generate a display name from a file path.
    static func displayNameFromPath(_ path: String, extension ext: String) -> String {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent

        if filename.hasSuffix(ext) {
            return String(filename.dropLast(ext.count))
        }
        return filename
    }

    /// Generate search keywords from a name.
    static func generateKeywords(_ name: String) -> [String] {
        name.lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9\\s]",
                with: "",
                options: .regularExpression
            )
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
