// SharingService.swift
// LiquidEditor
//
// Share exported videos via UIActivityViewController.
// Supports AirDrop, Messages, Mail, Files, and third-party apps.
// All UI operations run on @MainActor.

import UIKit
import Photos
import Foundation

// MARK: - ShareResult

/// Result of a share operation.
struct ShareResult: Sendable {
    /// Whether the user completed the share action.
    let didShare: Bool

    /// The activity type selected (e.g., "com.apple.UIKit.activity.AirDrop").
    let activityType: String?

    /// Error message if sharing failed.
    let errorMessage: String?
}

// MARK: - SharingError

/// Errors that can occur during sharing.
enum SharingError: Error, Sendable {
    case fileNotFound(String)
    case noViewController
    case saveFailed(String)
    case permissionDenied
}

// MARK: - SharingService

/// Service for sharing exported videos and media.
///
/// Thread Safety:
/// - `@MainActor` ensures all UI operations run on the main thread.
/// - File operations use async/await for non-blocking I/O.
@MainActor
final class SharingService {

    // MARK: - Share File

    /// Present UIActivityViewController for a file.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the file to share.
    ///   - excludedTypes: Activity types to exclude from the share sheet.
    /// - Returns: The share result indicating whether the user completed the action.
    /// - Throws: `SharingError` if the file is not found or no view controller is available.
    func shareFile(
        filePath: String,
        excludedTypes: [UIActivity.ActivityType] = []
    ) async throws -> ShareResult {
        let url = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SharingError.fileNotFound("File not found at path: \(filePath)")
        }

        guard let rootVC = Self.topViewController() else {
            throw SharingError.noViewController
        }

        return await withCheckedContinuation { continuation in
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            activityVC.excludedActivityTypes = excludedTypes.isEmpty ? nil : excludedTypes

            // iPad popover configuration
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: rootVC.view.bounds.midX,
                    y: rootVC.view.bounds.midY,
                    width: 1,
                    height: 1
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }

            activityVC.completionWithItemsHandler = { activityType, completed, _, error in
                let result = ShareResult(
                    didShare: completed,
                    activityType: activityType?.rawValue,
                    errorMessage: error?.localizedDescription
                )
                continuation.resume(returning: result)
            }

            rootVC.present(activityVC, animated: true)
        }
    }

    /// Share multiple files simultaneously.
    ///
    /// - Parameter filePaths: Array of absolute file paths to share.
    /// - Returns: The share result.
    /// - Throws: `SharingError` if files are not found or no view controller is available.
    func shareFiles(filePaths: [String]) async throws -> ShareResult {
        let urls: [URL] = filePaths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }

        guard !urls.isEmpty else {
            throw SharingError.fileNotFound("No valid files found")
        }

        guard let rootVC = Self.topViewController() else {
            throw SharingError.noViewController
        }

        return await withCheckedContinuation { continuation in
            let activityVC = UIActivityViewController(
                activityItems: urls,
                applicationActivities: nil
            )

            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = rootVC.view
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: rootVC.view.bounds.midX,
                    y: rootVC.view.bounds.midY,
                    width: 1,
                    height: 1
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }

            activityVC.completionWithItemsHandler = { activityType, completed, _, error in
                let result = ShareResult(
                    didShare: completed,
                    activityType: activityType?.rawValue,
                    errorMessage: error?.localizedDescription
                )
                continuation.resume(returning: result)
            }

            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Save to Photos

    /// Save a video file to the Photos library.
    ///
    /// - Parameter filePath: Absolute path to the video file.
    /// - Throws: `SharingError` if the file is not found or save fails.
    func saveToPhotos(filePath: String) async throws {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SharingError.fileNotFound("File not found: \(filePath)")
        }

        let url = URL(fileURLWithPath: filePath)

        // Request authorization
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SharingError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    /// Save an image file to the Photos library.
    ///
    /// - Parameter filePath: Absolute path to the image file.
    /// - Throws: `SharingError` if the file is not found or save fails.
    func saveImageToPhotos(filePath: String) async throws {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SharingError.fileNotFound("File not found: \(filePath)")
        }

        let url = URL(fileURLWithPath: filePath)

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SharingError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }
    }

    // MARK: - Copy to Clipboard

    /// Copy a video file URL to the clipboard.
    ///
    /// - Parameter filePath: Absolute path to the file.
    func copyToClipboard(filePath: String) {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            return // File doesn't exist, don't copy invalid URL
        }
        UIPasteboard.general.url = url
    }

    // MARK: - Helpers

    /// Find the topmost presented view controller.
    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}
