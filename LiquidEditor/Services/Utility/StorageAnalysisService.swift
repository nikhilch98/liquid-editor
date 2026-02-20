// StorageAnalysisService.swift
// LiquidEditor
//
// App storage usage analysis. Computes per-project storage breakdown,
// detects orphaned media files, and provides cleanup suggestions.
// All heavy disk I/O runs on background threads via Swift structured
// concurrency to avoid blocking the main thread.
//
// Uses OrphanedFile and OrphanedFileCategory from Models/Project/StorageUsage.swift.

import Foundation
import os

// MARK: - ProjectStorageInfo

/// Breakdown of storage used by a single project.
struct ProjectStorageInfo: Equatable, Sendable {

    /// Project identifier.
    let projectId: String

    /// Project name (for display).
    let projectName: String

    /// Size of the project JSON file in bytes.
    let projectFileSize: Int64

    /// Total size of media files referenced by this project.
    let mediaFileSize: Int64

    /// Size of cached thumbnails for this project.
    let thumbnailSize: Int64

    /// Total size (project + media + thumbnails).
    var totalSize: Int64 { projectFileSize + mediaFileSize + thumbnailSize }
}

// MARK: - CleanupAction

/// Types of cleanup actions.
enum CleanupAction: String, CaseIterable, Sendable {
    case removeOrphanedVideos
    case removeOrphanedThumbnails
    case clearFrameCache
    case clearTemporaryFiles
    case clearProxyFiles
}

// MARK: - CleanupSuggestion

/// A cleanup suggestion for reclaiming disk space.
struct CleanupSuggestion: Equatable, Sendable {

    /// Human-readable description.
    let description: String

    /// Estimated bytes that can be freed.
    let estimatedSavings: Int64

    /// The type of cleanup action.
    let action: CleanupAction

    /// File paths involved (for targeted cleanup).
    let filePaths: [String]
}

// MARK: - StorageAnalysisResult

/// Complete storage analysis result.
struct StorageAnalysisResult: Equatable, Sendable {

    /// Per-project storage breakdown.
    let projects: [ProjectStorageInfo]

    /// Orphaned files not referenced by any project.
    let orphanedFiles: [OrphanedFile]

    /// Cleanup suggestions sorted by estimated savings (descending).
    let suggestions: [CleanupSuggestion]

    /// Total storage used by all projects (bytes).
    var totalProjectStorage: Int64 {
        projects.reduce(0) { $0 + $1.totalSize }
    }

    /// Total storage used by orphaned files (bytes).
    var totalOrphanedStorage: Int64 {
        orphanedFiles.reduce(Int64(0)) { $0 + Int64($1.fileSize) }
    }

    /// Total storage used (projects + orphaned).
    var totalStorage: Int64 { totalProjectStorage + totalOrphanedStorage }

    /// Total potential savings from all suggestions.
    var totalPotentialSavings: Int64 {
        suggestions.reduce(0) { $0 + $1.estimatedSavings }
    }
}

// MARK: - StorageAnalysisService

/// Service for analyzing and managing storage usage by Liquid Editor projects.
///
/// All heavy I/O runs on background threads using structured concurrency.
/// Call ``analyze()`` for a complete storage breakdown, or
/// ``quickStorageTotal()`` for a fast estimate.
@Observable
@MainActor
final class StorageAnalysisService {

    // MARK: - Constants

    /// Directory names for storage analysis.
    private nonisolated static let projectsDir = "Projects"
    private nonisolated static let videosDir = "Videos"
    private nonisolated static let thumbnailsDir = "Thumbnails"

    // MARK: - Logger

    private nonisolated static let logger = Logger(subsystem: "LiquidEditor", category: "StorageAnalysisService")

    // MARK: - Singleton

    static let shared = StorageAnalysisService()

    // MARK: - State

    /// Whether an analysis is currently in progress.
    private(set) var isAnalyzing: Bool = false

    /// Cached result from the last analysis.
    private(set) var lastResult: StorageAnalysisResult?

    // MARK: - File Manager

    private let fileManager = FileManager.default

    // MARK: - Initialization

    init() {}

    // MARK: - Analysis

    /// Perform a full storage analysis on a background thread.
    ///
    /// Returns a ``StorageAnalysisResult`` with per-project breakdown,
    /// orphaned files, and cleanup suggestions.
    func analyze() async -> StorageAnalysisResult {
        if isAnalyzing, let cached = lastResult {
            return cached
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempURL = fileManager.temporaryDirectory
        let documentsPath = documentsURL.path
        let tempPath = tempURL.path

        let result = await Task.detached(priority: .utility) {
            StorageAnalysisService.performAnalysis(
                documentsPath: documentsPath,
                tempPath: tempPath
            )
        }.value

        lastResult = result
        return result
    }

    /// Quick estimate of total storage used (no orphan detection).
    ///
    /// Faster than ``analyze()`` -- just sums directory sizes.
    func quickStorageTotal() async -> Int64 {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let documentsPath = documentsURL.path

        return await Task.detached(priority: .utility) {
            var total: Int64 = 0

            let projectsPath = (documentsPath as NSString).appendingPathComponent(Self.projectsDir)
            if FileManager.default.fileExists(atPath: projectsPath) {
                total += StorageAnalysisService.directorySize(atPath: projectsPath)
            }

            let videosPath = (documentsPath as NSString).appendingPathComponent(Self.videosDir)
            if FileManager.default.fileExists(atPath: videosPath) {
                total += StorageAnalysisService.directorySize(atPath: videosPath)
            }

            return total
        }.value
    }

    /// Invalidate the cached result (e.g. after cleanup).
    func invalidateCache() {
        lastResult = nil
    }

    // MARK: - Background Analysis (Sendable)

    /// Perform the full storage analysis. Runs off the main actor.
    private nonisolated static func performAnalysis(
        documentsPath: String,
        tempPath: String
    ) -> StorageAnalysisResult {
        let fm = FileManager.default
        let projectsDirPath = (documentsPath as NSString).appendingPathComponent(projectsDir)
        let videosDirPath = (documentsPath as NSString).appendingPathComponent(videosDir)
        let thumbnailsDirPath = (documentsPath as NSString).appendingPathComponent(thumbnailsDir)

        // Collect project JSON files
        var projectFiles: [String] = []
        if fm.fileExists(atPath: projectsDirPath) {
            do {
                let contents = try fm.contentsOfDirectory(atPath: projectsDirPath)
                projectFiles = contents
                    .filter { $0.hasSuffix(".json") }
                    .map { (projectsDirPath as NSString).appendingPathComponent($0) }
            } catch {
                logger.error("Failed to read projects directory: \(error.localizedDescription)")
            }
        }

        // Track referenced video paths
        var referencedVideoPaths = Set<String>()
        var projectInfos: [ProjectStorageInfo] = []

        for filePath in projectFiles {
            guard let data = fm.contents(atPath: filePath) else {
                logger.warning("Failed to read project file: \(filePath)")
                continue
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.warning("Failed to parse JSON from project file: \(filePath)")
                continue
            }

            let projectId = ((filePath as NSString).lastPathComponent as NSString)
                .deletingPathExtension
            let projectName = json["name"] as? String ?? "Unknown"
            let jsonSize = Int64((try? fm.attributesOfItem(atPath: filePath))?[.size] as? UInt64 ?? 0)

            var mediaSize: Int64 = 0
            if let videoRelPath = json["sourceVideoPath"] as? String, !videoRelPath.isEmpty {
                let videoAbsPath = (documentsPath as NSString).appendingPathComponent(videoRelPath)
                referencedVideoPaths.insert(videoAbsPath)
                if let attrs = try? fm.attributesOfItem(atPath: videoAbsPath) {
                    mediaSize = Int64(attrs[.size] as? UInt64 ?? 0)
                }
            }

            var thumbSize: Int64 = 0
            if let thumbRelPath = json["thumbnailPath"] as? String, !thumbRelPath.isEmpty {
                let thumbAbsPath = (documentsPath as NSString).appendingPathComponent(thumbRelPath)
                if let attrs = try? fm.attributesOfItem(atPath: thumbAbsPath) {
                    thumbSize = Int64(attrs[.size] as? UInt64 ?? 0)
                }
            }

            projectInfos.append(ProjectStorageInfo(
                projectId: projectId,
                projectName: projectName,
                projectFileSize: jsonSize,
                mediaFileSize: mediaSize,
                thumbnailSize: thumbSize
            ))
        }

        // Identify orphaned video files (uses OrphanedFile from StorageUsage.swift)
        var orphanedFiles: [OrphanedFile] = []
        if fm.fileExists(atPath: videosDirPath) {
            guard let videoEntries = try? fm.contentsOfDirectory(atPath: videosDirPath) else {
                logger.error("Failed to read videos directory")
                return StorageAnalysisResult(projects: projectInfos, orphanedFiles: [], suggestions: [])
            }
            for entry in videoEntries {
                let fullPath = (videosDirPath as NSString).appendingPathComponent(entry)
                if !referencedVideoPaths.contains(fullPath),
                   let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                    orphanedFiles.append(OrphanedFile(
                        path: fullPath,
                        fileSize: Int(attrs[.size] as? UInt64 ?? 0),
                        lastModified: attrs[.modificationDate] as? Date,
                        category: .video
                    ))
                }
            }
        }

        // Check for orphaned thumbnails
        if fm.fileExists(atPath: thumbnailsDirPath),
           let thumbEntries = try? fm.subpathsOfDirectory(atPath: thumbnailsDirPath) {
            for subpath in thumbEntries {
                let fullPath = (thumbnailsDirPath as NSString).appendingPathComponent(subpath)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue,
                   let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                    orphanedFiles.append(OrphanedFile(
                        path: fullPath,
                        fileSize: Int(attrs[.size] as? UInt64 ?? 0),
                        lastModified: attrs[.modificationDate] as? Date,
                        category: .thumbnail
                    ))
                }
            }
        }

        // Check for temporary files
        var tempSize: Int64 = 0
        var tempFiles: [String] = []
        if let tempEntries = try? fm.contentsOfDirectory(atPath: tempPath) {
            for entry in tempEntries {
                let fullPath = (tempPath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue,
                   let attrs = try? fm.attributesOfItem(atPath: fullPath) {
                    let size = Int64(attrs[.size] as? UInt64 ?? 0)
                    tempSize += size
                    tempFiles.append(fullPath)
                }
            }
        }

        // Build cleanup suggestions
        var suggestions: [CleanupSuggestion] = []

        let orphanedVideoTotal = orphanedFiles
            .filter { $0.category == .video }
            .reduce(Int64(0)) { $0 + Int64($1.fileSize) }
        if orphanedVideoTotal > 0 {
            let count = orphanedFiles.filter { $0.category == .video }.count
            suggestions.append(CleanupSuggestion(
                description: "Remove \(count) orphaned video file(s)",
                estimatedSavings: orphanedVideoTotal,
                action: .removeOrphanedVideos,
                filePaths: orphanedFiles.filter { $0.category == .video }.map(\.path)
            ))
        }

        if tempSize > 0 {
            suggestions.append(CleanupSuggestion(
                description: "Clear temporary files",
                estimatedSavings: tempSize,
                action: .clearTemporaryFiles,
                filePaths: tempFiles
            ))
        }

        suggestions.sort { $0.estimatedSavings > $1.estimatedSavings }

        return StorageAnalysisResult(
            projects: projectInfos,
            orphanedFiles: orphanedFiles,
            suggestions: suggestions
        )
    }

    /// Calculate the total size of a directory recursively.
    nonisolated static func directorySize(atPath path: String) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        guard let subpaths = try? fm.subpathsOfDirectory(atPath: path) else {
            logger.error("Failed to read directory for size calculation: \(path)")
            return 0
        }
        for subpath in subpaths {
            let fullPath = (path as NSString).appendingPathComponent(subpath)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let fileType = attrs[.type] as? FileAttributeType,
               fileType == .typeRegular {
                total += Int64(attrs[.size] as? UInt64 ?? 0)
            }
        }
        return total
    }
}

// MARK: - Byte Formatting (Int64 variant)

/// Format a byte count as a human-readable string.
///
/// - Parameter bytes: The byte count (Int64) to format.
/// - Returns: A formatted string (e.g., "2.5 MB").
func formatStorageBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}
