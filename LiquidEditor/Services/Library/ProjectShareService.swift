// ProjectShareService.swift
// LiquidEditor
//
// F6-12: Project share sheet wiring.
//
// Bundles a project into a `.lrproj` archive and hands it to
// `UIActivityViewController` so the user can share via AirDrop, Files,
// Mail, or any other registered activity.
//
// The archive format is a placeholder for the production-ready
// project bundler (which will include media assets, timeline JSON, and
// thumbnails). For now we write the encoded `ProjectMetadata` JSON into
// a temporary directory with a `.lrproj` extension — enough for share
// sheet plumbing and UI testing.

import Foundation
import UIKit

// MARK: - ProjectShareError

/// Errors raised while preparing a project for sharing.
enum ProjectShareError: Error, Sendable, Equatable {
    /// Temporary directory could not be created.
    case temporaryDirectoryUnavailable
    /// JSON encoding of `ProjectMetadata` failed.
    case encodingFailed
    /// Writing the archive file failed.
    case writeFailed
}

// MARK: - ProjectShareService

/// Main-actor share sheet orchestration for projects.
///
/// The service is deliberately side-effect light — callers own the
/// returned `UIActivityViewController` and present it through SwiftUI's
/// `.sheet` / UIViewControllerRepresentable wrappers.
@MainActor
final class ProjectShareService {

    // MARK: - Constants

    /// File extension used for exported project bundles.
    static let projectBundleExtension: String = "lrproj"

    /// Subdirectory under `FileManager.default.temporaryDirectory` where
    /// bundles are staged. Cleared on demand via `clearStagingDirectory`.
    static let stagingSubdirectory: String = "LiquidEditor-Shares"

    // MARK: - Dependencies

    private let fileManager: FileManager

    // MARK: - Init

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Build an activity view controller pre-loaded with the project
    /// bundle URL.
    ///
    /// - Parameter project: project metadata to share.
    /// - Returns: activity VC ready to present. The returned controller
    ///   references a URL on disk that lives until the next call to
    ///   `clearStagingDirectory()` or app termination.
    func makeShareSheet(project: ProjectMetadata) -> UIActivityViewController {
        let url: URL
        do {
            url = try writeBundleSynchronously(for: project)
        } catch {
            // Fallback: share the project name as plain text so the UI
            // still functions if disk staging fails.
            return UIActivityViewController(
                activityItems: [project.name],
                applicationActivities: nil
            )
        }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // Sensible defaults for a project bundle.
        activityVC.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .postToWeibo,
            .postToTencentWeibo
        ]

        return activityVC
    }

    /// Export a project bundle to disk asynchronously.
    ///
    /// - Parameter project: project metadata to archive.
    /// - Returns: URL of the written `.lrproj` file.
    func exportProjectBundle(project: ProjectMetadata) async throws -> URL {
        try writeBundleSynchronously(for: project)
    }

    /// Remove any staged bundle files from the temporary directory.
    ///
    /// Safe to call if the directory does not exist — errors are
    /// swallowed because this is a best-effort cleanup.
    func clearStagingDirectory() {
        let dir = stagingDirectoryURL()
        try? fileManager.removeItem(at: dir)
    }

    // MARK: - Helpers

    private func stagingDirectoryURL() -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent(Self.stagingSubdirectory, isDirectory: true)
    }

    private func writeBundleSynchronously(for project: ProjectMetadata) throws -> URL {
        let dir = stagingDirectoryURL()

        do {
            try fileManager.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        } catch {
            throw ProjectShareError.temporaryDirectoryUnavailable
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let payload: Data
        do {
            payload = try encoder.encode(project)
        } catch {
            throw ProjectShareError.encodingFailed
        }

        let safeName = sanitizedFilename(project.name)
        let fileURL = dir
            .appendingPathComponent("\(safeName)-\(project.id)")
            .appendingPathExtension(Self.projectBundleExtension)

        do {
            try payload.write(to: fileURL, options: .atomic)
        } catch {
            throw ProjectShareError.writeFailed
        }

        return fileURL
    }

    /// Reduce a user-provided name to a filename-safe ASCII slug.
    private func sanitizedFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "project" : collapsed
    }
}
