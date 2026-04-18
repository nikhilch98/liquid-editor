// ExportDestinationService.swift
// LiquidEditor
//
// S2-13: Export destination integrations.
//
// Centralises post-export delivery targets: Photos library, Files app,
// AirDrop, and the generic share sheet. Keeps Destination logic off the
// UI views so Sheet presenters stay tiny.
//
// This service is UI-bound because Photos authorisation & activity VC
// construction both require main-actor work. It is not a replacement for
// ExportService; it is invoked *after* a successful export.

import Foundation
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import os

// MARK: - ExportDestinationError

/// Errors surfaced by `ExportDestinationService`.
enum ExportDestinationError: LocalizedError, Sendable {
    case photosAuthorizationDenied
    case photosSaveFailed(String)
    case fileNotFound(URL)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .photosAuthorizationDenied:
            return "Access to Photos was denied. Enable it in Settings."
        case .photosSaveFailed(let msg):
            return "Saving to Photos failed: \(msg)"
        case .fileNotFound(let url):
            return "Export file not found at \(url.path)."
        case .unknown(let msg):
            return msg
        }
    }
}

// MARK: - ExportDestinationService

/// Handles post-export file delivery to Photos, Files, AirDrop, or a
/// generic share sheet.
///
/// Usage:
/// ```swift
/// let service = ExportDestinationService()
/// try await service.savePhoto(url: exportedURL)
///
/// // Present UIActivityViewController returned by airdrop(url:) from a view.
/// ```
@MainActor
final class ExportDestinationService {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "LiquidEditor",
        category: "ExportDestinationService"
    )

    // MARK: - Init

    init() {}

    // MARK: - Photos

    /// Save a video file to the user's Photos library.
    ///
    /// Prompts for Photos write authorisation on first call.
    ///
    /// - Parameter url: File URL of the finished export.
    /// - Throws: `ExportDestinationError` on failure.
    func savePhoto(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ExportDestinationError.fileNotFound(url)
        }

        let status = await requestPhotoAuthorization()
        guard status == .authorized || status == .limited else {
            Self.logger.error("Photos auth denied: \(String(describing: status))")
            throw ExportDestinationError.photosAuthorizationDenied
        }

        try await withCheckedThrowingContinuation { [url] (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else if let error {
                    continuation.resume(
                        throwing: ExportDestinationError.photosSaveFailed(
                            error.localizedDescription
                        )
                    )
                } else {
                    continuation.resume(
                        throwing: ExportDestinationError.photosSaveFailed("unknown")
                    )
                }
            })
        }

        Self.logger.info("Saved export to Photos: \(url.lastPathComponent)")
    }

    private func requestPhotoAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Files

    /// Copy the exported file into the app's Documents directory with the
    /// requested filename, making it visible to the Files app via the
    /// "File Sharing" affordance.
    ///
    /// The caller is responsible for presenting a `UIDocumentPickerViewController`
    /// (or using `.fileExporter` SwiftUI modifier) if they want the user to
    /// pick a destination outside the app sandbox.
    ///
    /// - Parameters:
    ///   - url: Source file URL.
    ///   - filename: Desired filename (extension preserved from source if missing).
    /// - Returns: `true` if the copy succeeded.
    @discardableResult
    func saveToFiles(url: URL, filename: String) async -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            Self.logger.error("saveToFiles: source missing: \(url.path)")
            return false
        }

        let documentsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? fm.temporaryDirectory
        let resolved = resolveFilename(filename, sourceExtension: url.pathExtension)
        let destination = documentsDir.appendingPathComponent(resolved)

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: url, to: destination)
            Self.logger.info("saveToFiles: copied to \(destination.path)")
            return true
        } catch {
            Self.logger.error("saveToFiles failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Build a `UIDocumentPickerViewController` for the given file URL so
    /// the user can pick a Files destination. Caller presents it.
    func makeDocumentPicker(for url: URL) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    // MARK: - AirDrop

    /// Build a `UIActivityViewController` pre-scoped to AirDrop-style
    /// sharing. The VC's `excludedActivityTypes` are pruned so that the
    /// AirDrop affordance is prominent. Caller presents it.
    func airdrop(url: URL) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        // Narrow the activity list so AirDrop is the primary action.
        vc.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .postToFacebook,
            .postToFlickr,
            .postToTencentWeibo,
            .postToTwitter,
            .postToVimeo,
            .postToWeibo,
            .print,
            .markupAsPDF
        ]
        return vc
    }

    // MARK: - Share

    /// Build a generic share sheet (`UIActivityViewController`) for the file.
    /// Caller presents it from the appropriate view controller.
    func share(url: URL) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
    }

    // MARK: - Helpers

    private func resolveFilename(_ filename: String, sourceExtension: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.isEmpty ? "Export" : trimmed
        let url = URL(fileURLWithPath: safe)
        if url.pathExtension.isEmpty, !sourceExtension.isEmpty {
            return safe + "." + sourceExtension
        }
        return safe
    }
}
