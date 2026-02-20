// MediaImportService.swift
// LiquidEditor
//
// Media import service handling PHPicker, UIDocumentPicker,
// metadata extraction, thumbnail generation, and content hashing.

import AVFoundation
import CoreGraphics
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import CommonCrypto

// MARK: - ImportedMedia

/// Result of a media import operation.
struct ImportedMedia: Sendable {
    /// Local file URL of the imported media.
    let url: URL

    /// Type of the imported media.
    let type: MediaType

    /// PHAsset identifier (nil for file-based imports).
    let assetIdentifier: String?

    /// Original filename.
    let originalFilename: String
}

// MARK: - MediaMetadata

/// Extracted metadata from a media file.
struct MediaMetadata: Sendable {
    let width: Int
    let height: Int
    let durationMicroseconds: TimeMicros
    let frameRate: Double?
    let codec: String?
    let colorSpace: String?
    let audioSampleRate: Int?
    let audioChannels: Int?
    let bitDepth: Int?
    let fileSize: Int
    let creationDate: Date?
    let locationISO6709: String?
}

// MARK: - MediaImportError

/// Errors that can occur during media import.
enum MediaImportError: Error, Sendable {
    case noViewController
    case noFilesSelected
    case fileAccessDenied(String)
    case metadataExtractionFailed(String)
    case thumbnailGenerationFailed(String)
    case unsupportedFormat(String)
    case hashingFailed
}

// MARK: - MediaImportService

/// Service for importing media from the photo library and file system.
///
/// Thread Safety:
/// - `actor` ensures serial access to mutable state.
/// - Picker presentation delegates to `@MainActor` for UI operations.
/// - I/O operations (metadata, thumbnails, hashing) run on background threads.
actor MediaImportService {

    // MARK: - Constants

    /// Default maximum thumbnail size in pixels.
    private static let defaultThumbnailMaxSize = 480

    /// JPEG compression quality for video thumbnails.
    private static let videoThumbnailCompressionQuality: CGFloat = 0.75

    /// JPEG compression quality for image thumbnails.
    private static let imageThumbnailCompressionQuality: CGFloat = 0.80

    /// Chunk size for content hashing (1MB).
    private static let hashingChunkSize = 1024 * 1024

    /// Supported file types for document picker.
    private static let supportedFileTypes: [UTType] = [
        .movie,
        .video,
        .mpeg4Movie,
        .quickTimeMovie,
        .image,
        .jpeg,
        .png,
        .heic,
        .audio,
        .mpeg4Audio,
        .mp3,
    ]

    /// Codec FourCC to display name lookup table.
    private static let codecLookupTable: [FourCharCode: String] = [
        1635148593: "H.264 (AVC)",
        1751479857: "H.265 (HEVC)",
        1752589105: "H.265 (HEVC)",
        1634759272: "Apple ProRes",
        1634759288: "Apple ProRes",
        1634759267: "Apple ProRes",
        1634759278: "Apple ProRes",
        1634759283: "Apple ProRes",
        1634759279: "Apple ProRes",
        1635135537: "AV1",
    ]

    // MARK: - Photo Library Import

    /// Present the photo library picker and return selected media.
    ///
    /// - Parameters:
    ///   - mediaTypes: Types to allow (e.g., ["video", "image"]).
    ///   - selectionLimit: Maximum number of items (0 = unlimited).
    /// - Returns: Array of imported media results.
    /// - Throws: `MediaImportError` if no view controller is available.
    func importFromPhotos(
        mediaTypes: [String] = ["video", "image"],
        selectionLimit: Int = 0
    ) async throws -> [ImportedMedia] {
        // Build picker configuration (no MainActor needed for data setup)
        var filters: [PHPickerFilter] = []
        for type in mediaTypes {
            switch type {
            case "video": filters.append(.videos)
            case "image": filters.append(.images)
            case "livePhoto": filters.append(.livePhotos)
            default: break
            }
        }

        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = filters.isEmpty ? .any(of: [.videos, .images]) : .any(of: filters)
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current
        config.selection = .ordered

        // Use continuation for the delegate-based picker callback
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoPickerDelegate(continuation: continuation)
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = delegate

            // Prevent delegate from being deallocated
            objc_setAssociatedObject(
                picker,
                "delegate",
                delegate,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            // Present the picker on the main actor
            Task { @MainActor in
                guard let viewController = Self.topViewController() else {
                    continuation.resume(throwing: MediaImportError.noViewController)
                    return
                }
                viewController.present(picker, animated: true)
            }
        }
    }

    // MARK: - File System Import

    /// Present the document picker and return selected media.
    ///
    /// - Parameter allowsMultipleSelection: Whether multiple files can be selected.
    /// - Returns: Array of imported media results.
    /// - Throws: `MediaImportError` if no view controller is available.
    func importFromFiles(
        allowsMultipleSelection: Bool = true
    ) async throws -> [ImportedMedia] {
        // Use continuation for the delegate-based picker callback
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DocumentPickerDelegate(continuation: continuation)
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: Self.supportedFileTypes,
                asCopy: true
            )
            picker.allowsMultipleSelection = allowsMultipleSelection
            picker.shouldShowFileExtensions = true
            picker.delegate = delegate

            objc_setAssociatedObject(
                picker,
                "delegate",
                delegate,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            // Present the picker on the main actor
            Task { @MainActor in
                guard let viewController = Self.topViewController() else {
                    continuation.resume(throwing: MediaImportError.noViewController)
                    return
                }
                viewController.present(picker, animated: true)
            }
        }
    }

    // MARK: - Metadata Extraction

    /// Extract metadata from a media file.
    ///
    /// - Parameter path: Absolute path to the media file.
    /// - Returns: Extracted metadata.
    func extractMetadata(path: String) async throws -> MediaMetadata {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        var width = 0
        var height = 0
        var frameRate: Double?
        var codec: String?
        var colorSpace: String?
        var audioSampleRate: Int?
        var audioChannels: Int?
        var bitDepth: Int?
        var durationMicros: TimeMicros = 0

        // Video track info
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let adjustedSize = naturalSize.applying(transform)
            width = Int(abs(adjustedSize.width))
            height = Int(abs(adjustedSize.height))

            let fr = try await videoTrack.load(.nominalFrameRate)
            frameRate = Double(fr)

            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            if let formatDesc = formatDescriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                codec = Self.codecDisplayName(fourCC: codecType)
            }

            let hasHDR = videoTrack.hasMediaCharacteristic(.containsHDRVideo)
            colorSpace = hasHDR ? "HDR" : "SDR"
        }

        // Audio track info
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let formatDescriptions = try await audioTrack.load(.formatDescriptions)
            if let formatDesc = formatDescriptions.first {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                    audioSampleRate = Int(asbd.mSampleRate)
                    audioChannels = Int(asbd.mChannelsPerFrame)
                    bitDepth = Int(asbd.mBitsPerChannel)
                }
            }
        }

        // Duration
        let duration = try await asset.load(.duration)
        durationMicros = TimeMicros(CMTimeGetSeconds(duration) * 1_000_000)

        // File size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0

        // Creation date
        var creationDate: Date?
        var locationISO6709: String?
        if let metadata = try? await asset.load(.metadata) {
            for item in metadata {
                if item.commonKey == .commonKeyCreationDate {
                    creationDate = try? await item.load(.dateValue)
                }
            }
            for item in metadata {
                if item.identifier == .quickTimeMetadataLocationISO6709 {
                    locationISO6709 = try? await item.load(.stringValue)
                }
            }
        }

        return MediaMetadata(
            width: width,
            height: height,
            durationMicroseconds: durationMicros,
            frameRate: frameRate,
            codec: codec,
            colorSpace: colorSpace,
            audioSampleRate: audioSampleRate,
            audioChannels: audioChannels,
            bitDepth: bitDepth,
            fileSize: fileSize,
            creationDate: creationDate,
            locationISO6709: locationISO6709
        )
    }

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail image from a media file.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the media file.
    ///   - maxSize: Maximum dimension (width or height) in pixels.
    /// - Returns: JPEG data of the thumbnail.
    func generateThumbnail(path: String, maxSize: Int = defaultThumbnailMaxSize) async throws -> Data {
        let url = URL(fileURLWithPath: path)
        let uti = UTType(filenameExtension: url.pathExtension)

        if uti?.conforms(to: .image) == true {
            return try await generateImageThumbnail(url: url, maxSize: maxSize)
        } else {
            return try await generateVideoThumbnail(url: url, maxSize: maxSize)
        }
    }

    private func generateVideoThumbnail(url: URL, maxSize: Int) async throws -> Data {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: CGFloat(maxSize), height: CGFloat(maxSize))
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1.0, preferredTimescale: 600)

        let time = CMTime(seconds: 0.0, preferredTimescale: 600)
        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
        let uiImage = UIImage(cgImage: cgImage)

        guard let jpegData = uiImage.jpegData(compressionQuality: Self.videoThumbnailCompressionQuality) else {
            throw MediaImportError.thumbnailGenerationFailed("Could not encode JPEG")
        }
        return jpegData
    }

    private func generateImageThumbnail(url: URL, maxSize: Int) async throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MediaImportError.thumbnailGenerationFailed("Could not read image")
        }

        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        let scale = min(
            CGFloat(maxSize) / CGFloat(originalWidth),
            CGFloat(maxSize) / CGFloat(originalHeight)
        )
        let newWidth = Int(CGFloat(originalWidth) * scale)
        let newHeight = Int(CGFloat(originalHeight) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MediaImportError.thumbnailGenerationFailed("Could not create graphics context")
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let resizedImage = context.makeImage() else {
            throw MediaImportError.thumbnailGenerationFailed("Could not resize image")
        }

        let uiImage = UIImage(cgImage: resizedImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: Self.imageThumbnailCompressionQuality) else {
            throw MediaImportError.thumbnailGenerationFailed("Could not encode JPEG")
        }
        return jpegData
    }

    // MARK: - Content Hashing

    /// Compute a content hash for a media file.
    ///
    /// Uses SHA-256 of: first 1MB + last 1MB + file size.
    /// This provides fast deduplication without hashing the entire file.
    ///
    /// - Parameter path: Absolute path to the media file.
    /// - Returns: Hex-encoded SHA-256 hash string.
    func computeContentHash(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int ?? 0
        let chunkSize = Self.hashingChunkSize

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        // Hash first 1MB
        let firstChunk = fileHandle.readData(ofLength: chunkSize)
        firstChunk.withUnsafeBytes { ptr in
            _ = CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(firstChunk.count))
        }

        // Hash last 1MB if file is larger
        if fileSize > chunkSize * 2 {
            fileHandle.seek(toFileOffset: UInt64(fileSize - chunkSize))
            let lastChunk = fileHandle.readData(ofLength: chunkSize)
            lastChunk.withUnsafeBytes { ptr in
                _ = CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(lastChunk.count))
            }
        }

        // Include file size in hash
        var size = fileSize
        withUnsafeBytes(of: &size) { ptr in
            _ = CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(MemoryLayout<Int>.size))
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Storage Info

    /// Get device storage information.
    ///
    /// - Returns: Dictionary with totalBytes, availableBytes, and mediaBytes.
    func getStorageInfo() async -> (totalBytes: Int, availableBytes: Int, mediaBytes: Int) {
        var totalBytes = 0
        var availableBytes = 0

        do {
            let homeURL = URL(fileURLWithPath: NSHomeDirectory())
            let resourceValues = try homeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
            ])
            totalBytes = resourceValues.volumeTotalCapacity ?? 0
            availableBytes = Int(resourceValues.volumeAvailableCapacityForImportantUsage ?? 0)
        } catch {
            // Best-effort
        }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let mediaBytes: Int
        if let mediaURL = documentsURL?.appendingPathComponent("Media") {
            mediaBytes = Self.directorySize(url: mediaURL)
        } else {
            mediaBytes = 0
        }

        return (totalBytes, availableBytes, mediaBytes)
    }

    // MARK: - Utility

    @MainActor
    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              var vc = window.rootViewController else {
            return nil
        }

        while let presented = vc.presentedViewController {
            vc = presented
        }

        return vc
    }

    nonisolated static func codecDisplayName(fourCC: FourCharCode) -> String {
        // Try lookup table first for O(1) performance
        if let name = codecLookupTable[fourCC] {
            return name
        }

        // Fall back to FourCC string representation for unknown codecs
        let c1 = Character(UnicodeScalar((fourCC >> 24) & 0xFF)!)
        let c2 = Character(UnicodeScalar((fourCC >> 16) & 0xFF)!)
        let c3 = Character(UnicodeScalar((fourCC >> 8) & 0xFF)!)
        let c4 = Character(UnicodeScalar(fourCC & 0xFF)!)
        return String([c1, c2, c3, c4])
    }

    nonisolated fileprivate static func mediaTypeFromURL(_ url: URL) -> MediaType {
        let uti = UTType(filenameExtension: url.pathExtension)
        if uti?.conforms(to: .movie) == true || uti?.conforms(to: .video) == true {
            return .video
        } else if uti?.conforms(to: .image) == true {
            return .image
        } else if uti?.conforms(to: .audio) == true {
            return .audio
        }
        return .video
    }

    nonisolated private static func directorySize(url: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += fileSize
            }
        }
        return totalSize
    }
}

// MARK: - PhotoPickerDelegate

/// Internal delegate for PHPickerViewController.
private final class PhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
    private let continuation: CheckedContinuation<[ImportedMedia], Error>

    init(continuation: CheckedContinuation<[ImportedMedia], Error>) {
        self.continuation = continuation
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else {
            continuation.resume(returning: [])
            return
        }

        Task {
            var importResults: [ImportedMedia] = []

            for pickerResult in results {
                let provider = pickerResult.itemProvider

                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    if let url = try? await Self.loadFileURL(from: provider, type: .movie) {
                        importResults.append(ImportedMedia(
                            url: url,
                            type: .video,
                            assetIdentifier: pickerResult.assetIdentifier,
                            originalFilename: url.lastPathComponent
                        ))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = try? await Self.loadFileURL(from: provider, type: .image) {
                        importResults.append(ImportedMedia(
                            url: url,
                            type: .image,
                            assetIdentifier: pickerResult.assetIdentifier,
                            originalFilename: url.lastPathComponent
                        ))
                    }
                }
            }

            continuation.resume(returning: importResults)
        }
    }

    private static func loadFileURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: MediaImportError.fileAccessDenied("No file URL"))
                    return
                }

                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)

                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - DocumentPickerDelegate

/// Internal delegate for UIDocumentPickerViewController.
private final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let continuation: CheckedContinuation<[ImportedMedia], Error>

    init(continuation: CheckedContinuation<[ImportedMedia], Error>) {
        self.continuation = continuation
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var results: [ImportedMedia] = []

        for url in urls {
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let localURL: URL
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let destURL = tempDir
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                try FileManager.default.copyItem(at: url, to: destURL)
                localURL = destURL
            } catch {
                localURL = url
            }

            let mediaType = MediaImportService.mediaTypeFromURL(localURL)
            results.append(ImportedMedia(
                url: localURL,
                type: mediaType,
                assetIdentifier: nil,
                originalFilename: url.lastPathComponent
            ))
        }

        continuation.resume(returning: results)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        continuation.resume(returning: [])
    }
}
