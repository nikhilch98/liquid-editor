# Media Import & Management System - Design Document

**Date:** 2026-02-06
**Status:** Draft
**Author:** Claude + Nikhil

---

## Table of Contents

1. [Overview](#1-overview)
2. [Current State Analysis](#2-current-state-analysis)
3. [Photo Library Integration](#3-photo-library-integration)
4. [Files App Integration](#4-files-app-integration)
5. [Multi-Select Import](#5-multi-select-import)
6. [Camera Capture](#6-camera-capture)
7. [Media Browser](#7-media-browser)
8. [Favorites & Tagging](#8-favorites--tagging)
9. [Metadata Display](#9-metadata-display)
10. [Cloud Import](#10-cloud-import)
11. [Import from URL](#11-import-from-url)
12. [Media Thumbnails](#12-media-thumbnails)
13. [File Management](#13-file-management)
14. [Platform Channels](#14-platform-channels)
15. [Data Model Changes](#15-data-model-changes)
16. [UI Design](#16-ui-design)
17. [Edge Cases](#17-edge-cases)
18. [Performance](#18-performance)
19. [Security & Privacy](#19-security--privacy)
20. [Implementation Plan](#20-implementation-plan)
21. [File Structure](#21-file-structure)
22. [Test Plan](#22-test-plan)

---

## 1. Overview

### 1.1 Summary

The **Media Import & Management System** replaces the current single-video-per-project import workflow with a comprehensive media management layer. Users will be able to import videos, photos, and audio from multiple sources (Photo Library, Files app, camera, cloud services, URLs), manage them in a centralized Media Browser, and assign them to projects with full metadata, favorites, and tagging support.

### 1.2 Goals

| Goal | Description |
|------|-------------|
| **Multi-source import** | Import from Photo Library, Files app, camera, cloud, and URL |
| **Batch import** | Select and import multiple files at once with progress tracking |
| **Media browsing** | Browse, search, filter, and sort all imported media |
| **Organization** | Favorites, color tags, and custom text tags for quick access |
| **Rich metadata** | Display resolution, duration, codec, frame rate, file size, date, GPS |
| **Efficient storage** | Content-hash deduplication, lazy thumbnails, intelligent cleanup |
| **Background processing** | Import and thumbnail generation must never block UI or editing |
| **Native iOS experience** | All UI uses iOS 26 Liquid Glass components per CLAUDE.md requirements |

### 1.3 Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Photo picker | PHPickerViewController (iOS 14+) | Privacy-first, no permission prompt needed for basic use |
| File picker | UIDocumentPickerViewController | System-provided, supports iCloud Drive and third-party providers |
| Camera | AVCaptureSession via platform channel | Full control over resolution, frame rate, and recording parameters |
| Storage model | Copy-to-project + MediaAsset registry | Existing pattern, reliable, no external file dependency after import |
| Deduplication | Content hash (SHA-256 of first 1MB + last 1MB + size) | Already implemented in `content_hash.dart`, fast and reliable |
| Thumbnails | Native AVAssetImageGenerator + disk cache | Already proven in VideoProcessingService, consistent approach |
| Cloud auth | Per-service OAuth in native | Google Drive via `google_sign_in`, Dropbox via `flutter_appauth` |
| Media browser location | New tab in Project Library | Reuse existing tab bar pattern, add "Media" tab alongside Projects/People |
| Tag persistence | Stored in MediaAsset + separate tags index | Tags travel with asset, index enables fast filtering |

### 1.4 Non-Goals (v1)

- Automatic AI-based tagging or scene detection
- Audio file import from streaming services (Spotify, Apple Music)
- Real-time collaborative media sharing between devices
- AirDrop receive (system handles this, user can import from Files after)
- Batch renaming
- Media library iCloud sync across devices

---

## 2. Current State Analysis

### 2.1 How Import Currently Works

The current import flow is minimal and lives entirely in `project_library_view.dart` in the `_importVideo()` method:

1. **Picker:** Uses `image_picker` package (`ImagePicker.pickVideo(source: ImageSource.gallery)`) which presents a system photo picker limited to a single video selection.
2. **Confirmation dialog:** Shows a `CupertinoAlertDialog` asking the user to confirm import.
3. **File copy:** Copies the picked video file to `Documents/Videos/{uuid}.mov` using `dart:io`.
4. **Duration extraction:** Creates a `VideoPlayerController.file()`, initializes it, reads `controller.value.duration`, then disposes the controller. Has a 30-second timeout.
5. **Project creation:** Creates a new `Project` with `sourceVideoPath: 'Videos/$filename'` and saves via `ProjectStorage`.
6. **Navigation:** Opens the project in `SmartEditView`.

**Limitations:**
- Single file selection only (no multi-select)
- Videos only (no photos, no audio)
- No metadata extraction beyond duration
- No content hash generation or deduplication
- No MediaAsset creation (the V2 architecture's `MediaAsset` model exists but is not used during import)
- No thumbnail generation at import time (thumbnails are generated lazily per project card)
- No progress indication during file copy
- No Files app integration
- No camera capture integration
- Import and project creation are tightly coupled (cannot import media without creating a project)

### 2.2 MediaAsset Registry

The `MediaAsset` model (`lib/models/media_asset.dart`) and `MediaAssetRegistry` class are fully implemented as part of Timeline Architecture V2:

**MediaAsset fields:**
- `id` (UUID v4)
- `contentHash` (SHA-256 of first 1MB + last 1MB + file size)
- `relativePath` (from app Documents directory)
- `originalFilename`
- `type` (video, image, audio)
- `durationMicroseconds`
- `frameRate` (Rational)
- `width`, `height`
- `codec`
- `audioSampleRate`, `audioChannels`
- `fileSize`
- `importedAt`
- `isLinked`, `lastKnownAbsolutePath`, `lastVerifiedAt`

**MediaAssetRegistry capabilities:**
- Lookup by ID and content hash
- Duplicate detection via `hasDuplicate(contentHash)`
- Register with automatic dedup (returns existing asset if hash matches)
- Unlinked asset tracking for relinking
- Full JSON serialization

### 2.3 Content Hash

The `content_hash.dart` module provides:
- `generateContentHash(File)` -- SHA-256 of (first 1MB + last 1MB + file size), async with cancellation support
- `generateContentHashSync(File)` -- synchronous variant
- `verifyContentHash(File, expectedHash)` -- verification utility
- `generateFullContentHash(File)` -- entire file hash with progress callback
- `generateQuickHash(File)` -- first 64KB only, for cache keys

### 2.4 File Storage Structure

```
Documents/
  Projects/         # Project JSON files
    {uuid}.json
  Videos/           # Video files (current pattern)
    {uuid}.mov
  People/           # People library images
    {personId}/
      {imageId}.jpg
```

### 2.5 Native Capabilities Already Available

| Capability | Service | Platform Channel |
|------------|---------|-----------------|
| Thumbnail generation (single) | `VideoProcessingService.generateThumbnail()` | `com.liquideditor/video_processing` |
| Thumbnail generation (batch) | `VideoProcessingService.generateTimelineThumbnails()` | `com.liquideditor/video_processing` |
| Proxy generation (480p) | `VideoProcessingService.generateProxy()` | `com.liquideditor/video_processing` |
| Frame extraction | `VideoProcessingService.extractFirstFrame()` | `com.liquideditor/video_processing` |
| Audio session (playback+record) | `VideoProcessingService.configureAudioSession()` | Already configured |

### 2.6 Existing Dependencies

From `pubspec.yaml`:
- `image_picker: ^1.1.2` -- current single-file picker
- `video_player: ^2.9.2` -- used for duration extraction
- `path_provider: ^2.1.5` -- app directory paths
- `permission_handler: ^12.0.1` -- photo library permissions
- `uuid: ^4.5.2` -- ID generation
- `crypto: ^3.0.6` -- SHA-256 hashing
- `video_thumbnail: ^0.5.6` -- thumbnail generation (Flutter plugin)

---

## 3. Photo Library Integration

### 3.1 PHPickerViewController Approach (Recommended)

**PHPickerViewController** (iOS 14+) is the modern, privacy-friendly photo picker. It runs in a separate process with its own data protection, meaning the app does not need `NSPhotoLibraryUsageDescription` permission for basic selection. The system grants temporary access only to selected assets.

#### 3.1.1 Why PHPicker Over PHAsset Enumeration

| Aspect | PHPickerViewController | PHAsset Enumeration |
|--------|----------------------|---------------------|
| Privacy | No permission prompt needed | Requires `NSPhotoLibraryUsageDescription` |
| Multi-select | Built-in | Manual UI implementation |
| Search | Built-in search bar | Manual |
| Smart Albums | Automatic access | Requires permission |
| Live Photos | Native support | Manual handling |
| Performance | System-managed, memory efficient | App must manage memory |

#### 3.1.2 Supported Media Types

| Media Type | UTType | Extensions | Notes |
|------------|--------|------------|-------|
| Video (H.264) | `public.mpeg-4`, `com.apple.quicktime-movie` | .mp4, .mov, .m4v | Most common |
| Video (HEVC) | `public.hevc` | .mov, .mp4 | iPhone 7+ default |
| Video (ProRes) | `com.apple.prores-raw` | .mov | iPhone 13 Pro+ |
| Photo (JPEG) | `public.jpeg` | .jpg, .jpeg | Universal |
| Photo (HEIF) | `public.heif` | .heic | iPhone 7+ default |
| Photo (PNG) | `public.png` | .png | Screenshots |
| Photo (RAW) | `com.adobe.raw-image` | .dng | ProRAW |
| Live Photo | composite | .heic + .mov | Handled as pair |

#### 3.1.3 iCloud Asset Handling

PHPickerViewController items may reference iCloud-stored assets not yet downloaded to the device:

1. **Detection:** Check `PHAsset.isLocallyAvailable` after picker selection (requires limited photo library access if fetching PHAsset metadata).
2. **Download workflow:**
   - Show progress indicator per asset: "Downloading from iCloud... (X of Y)"
   - Use `PHImageManager.requestAVAsset(forVideo:)` with `deliveryMode: .highQualityFormat` and `isNetworkAccessAllowed: true`
   - Monitor progress via `PHImageRequestOptions.progressHandler`
   - Allow cancellation per asset
3. **Failure handling:**
   - Network error: Offer "Retry" or "Skip" per asset
   - Insufficient iCloud storage: Show warning, skip asset
   - Timeout (60s per asset): Show warning, allow retry

#### 3.1.4 Special Video Types

**Slow-Motion Videos:**
- Stored with `PHAssetMediaSubtype.videoHighFrameRate`
- Native frame rate preserved (120fps or 240fps)
- Speed ramp metadata in `PHAsset.creationDate` / `PHAsset` properties
- Import strategy: Copy the full-speed source, preserve frame rate metadata in `MediaAsset.frameRate`
- Let user decide speed handling in the editor, not during import

**Time-Lapse Videos:**
- Stored with `PHAssetMediaSubtype.videoTimelapse`
- Already rendered at standard frame rate (typically 30fps)
- Import as regular video; no special handling needed

**Cinematic Mode Videos (iPhone 13+):**
- Contain depth data and focus metadata
- Import the rendered video; depth data not currently used by the editor
- Future: Could use depth data for blur effects

**HDR Video (Dolby Vision / HLG):**
- Stored with `PHAssetMediaSubtype.videoHDR` (available via `PHAsset`)
- Preserve HDR metadata during copy
- Set `MediaAsset.codec` to include "HDR" identifier (e.g., "hevc-hdr")
- Export pipeline already supports HDR via `enableHdr` flag

**ProRes Video:**
- Available on iPhone 13 Pro+ in ProRes format
- Very large file sizes (1-6 GB per minute)
- Set `MediaAsset.codec` to "prores"
- Show file size warning before import if > 1GB

#### 3.1.5 Native Implementation (Swift)

```swift
// MediaImportService.swift

import PhotosUI

class MediaImportService: NSObject {
    private var pickerCompletion: (([MediaImportResult]) -> Void)?

    func presentPhotoPicker(
        from viewController: UIViewController,
        mediaTypes: [PHPickerFilter],
        selectionLimit: Int,  // 0 = unlimited
        completion: @escaping ([MediaImportResult]) -> Void
    ) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = PHPickerFilter.any(of: mediaTypes)
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current  // Avoid transcoding

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        pickerCompletion = completion

        viewController.present(picker, animated: true)
    }
}

extension MediaImportService: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else {
            pickerCompletion?([])
            return
        }

        Task {
            var importResults: [MediaImportResult] = []

            for result in results {
                let itemProvider = result.itemProvider

                if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    if let url = try? await loadFileURL(from: itemProvider, type: .movie) {
                        importResults.append(.video(url: url, assetId: result.assetIdentifier))
                    }
                } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = try? await loadFileURL(from: itemProvider, type: .image) {
                        importResults.append(.image(url: url, assetId: result.assetIdentifier))
                    }
                } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier) {
                    // Handle live photo as video component + still image
                    if let url = try? await loadFileURL(from: itemProvider, type: .movie) {
                        importResults.append(.livePhoto(videoURL: url, assetId: result.assetIdentifier))
                    }
                }
            }

            await MainActor.run {
                self.pickerCompletion?(importResults)
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider, type: UTType) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url = url else {
                    continuation.resume(throwing: MediaImportError.noFileURL)
                    return
                }

                // The URL is temporary and will be deleted after this callback.
                // Copy to a stable temporary location.
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
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

enum MediaImportResult {
    case video(url: URL, assetId: String?)
    case image(url: URL, assetId: String?)
    case livePhoto(videoURL: URL, assetId: String?)
}

enum MediaImportError: Error {
    case noFileURL
    case iCloudDownloadFailed
    case unsupportedFormat
    case fileTooLarge
}
```

#### 3.1.6 Permission Strategy

| Scenario | Permission Needed | When |
|----------|------------------|------|
| Select media via PHPicker | None | Always available (iOS 14+) |
| Read selected media metadata | Limited (`PHAccessLevel.limited`) | Only if we want PHAsset details |
| Enumerate full photo library | Full (`PHAccessLevel.readWrite`) | NOT needed for import |
| Save to photo library | `NSPhotoLibraryAddUsageDescription` | Only for export "Save to Photos" |

**Strategy:** Use PHPickerViewController exclusively for import. No photo library permission needed. Only request `.addOnly` permission if user wants to save exported video back to Photos.

---

## 4. Files App Integration

### 4.1 UIDocumentPickerViewController

The Files app integration uses `UIDocumentPickerViewController` which provides a full file browser supporting:
- iCloud Drive
- On My iPhone
- Third-party file providers (Google Drive app, Dropbox app, OneDrive app, etc.)
- Recent files
- Favorites
- Tags

#### 4.1.1 Supported UTTypes

```swift
import UniformTypeIdentifiers

let supportedTypes: [UTType] = [
    // Video
    .movie,          // .mov
    .mpeg4Movie,     // .mp4
    .quickTimeMovie, // .mov
    .avi,            // .avi

    // Image
    .image,          // All image types
    .jpeg,           // .jpg, .jpeg
    .png,            // .png
    .heic,           // .heic
    .heif,           // .heif
    .rawImage,       // .dng, .arw, etc.

    // Audio
    .audio,          // All audio types
    .mp3,            // .mp3
    .wav,            // .wav
    .mpeg4Audio,     // .m4a, .aac
]
```

#### 4.1.2 Security-Scoped Bookmarks

When a user picks a file from a file provider (especially iCloud Drive), iOS returns a security-scoped URL. The app must:

1. **Start accessing:** Call `url.startAccessingSecurityScopedResource()` before reading
2. **Copy to local storage:** Copy the file to `Documents/Media/` before releasing access
3. **Stop accessing:** Call `url.stopAccessingSecurityScopedResource()` after copy completes
4. **Do NOT store bookmarks:** Since we copy files locally, there is no need for persistent security-scoped bookmarks

```swift
func importFromDocumentPicker(urls: [URL]) async -> [MediaImportResult] {
    var results: [MediaImportResult] = []

    for url in urls {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Copy to temp staging area
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        do {
            try FileManager.default.copyItem(at: url, to: tempURL)

            let uti = UTType(filenameExtension: url.pathExtension)
            if uti?.conforms(to: .movie) == true || uti?.conforms(to: .video) == true {
                results.append(.video(url: tempURL, assetId: nil))
            } else if uti?.conforms(to: .image) == true {
                results.append(.image(url: tempURL, assetId: nil))
            } else if uti?.conforms(to: .audio) == true {
                results.append(.audio(url: tempURL))
            }
        } catch {
            // Log error, continue with next file
        }
    }

    return results
}
```

#### 4.1.3 Large File Handling

For files from iCloud Drive or other cloud providers, the file may need to be downloaded before copy:

| File Size | Strategy | User Experience |
|-----------|----------|----------------|
| < 100MB | Direct copy, show spinner | "Importing..." with activity indicator |
| 100MB - 1GB | Copy with progress | "Importing file_name.mov... 45%" progress bar |
| 1GB - 4GB | Copy with progress + size warning | "Large file (2.3 GB). This may take a while." |
| > 4GB | Block with explanation | "Files larger than 4GB are not supported." |

#### 4.1.4 Native Implementation (Swift)

```swift
func presentDocumentPicker(
    from viewController: UIViewController,
    allowsMultipleSelection: Bool,
    completion: @escaping ([URL]) -> Void
) {
    let picker = UIDocumentPickerViewController(
        forOpeningContentTypes: supportedTypes,
        asCopy: false  // We'll copy ourselves for progress tracking
    )
    picker.allowsMultipleSelection = allowsMultipleSelection
    picker.shouldShowFileExtensions = true
    picker.delegate = self  // UIDocumentPickerDelegate

    documentPickerCompletion = completion
    viewController.present(picker, animated: true)
}
```

---

## 5. Multi-Select Import

### 5.1 Import Queue Architecture

When the user selects multiple files (from any source), they enter an **Import Queue** that processes files sequentially with parallel metadata extraction.

```
User Selection (N files)
        |
        v
+------------------+
| Import Queue     |
| - Ordered list   |
| - Progress state |
| - Cancel support |
+------------------+
        |
        v (for each file, up to 3 concurrent)
+------------------+
| Import Pipeline  |
|  1. Validate     |
|  2. Copy to      |
|     Documents/   |
|     Media/       |
|  3. Hash         |
|  4. Dedup check  |
|  5. Extract      |
|     metadata     |
|  6. Generate     |
|     thumbnail    |
|  7. Create       |
|     MediaAsset   |
|  8. Register     |
+------------------+
        |
        v
+------------------+
| MediaAsset       |
| Registry         |
| (notifyListeners)|
+------------------+
```

### 5.2 Import Pipeline Steps (Per File)

| Step | Operation | Blocking? | Failure Behavior |
|------|-----------|-----------|-----------------|
| 1. Validate | Check file exists, readable, size < 4GB, supported format | No | Skip file, report error |
| 2. Copy | Copy from temp/picker URL to `Documents/Media/{uuid}.{ext}` | Background isolate | Skip file, clean up partial copy |
| 3. Hash | Generate content hash using `generateContentHash()` | Background isolate | Skip file (hash is required) |
| 4. Dedup | Check `MediaAssetRegistry.hasDuplicate(hash)` | No (O(1) lookup) | Return existing asset, skip copy, delete new copy |
| 5. Metadata | Extract via native platform channel (AVAsset inspection) | Native background queue | Use defaults for missing fields |
| 6. Thumbnail | Generate via `generateThumbnail()` platform channel | Native background queue | Use placeholder, generate later |
| 7. Create | Construct `MediaAsset` with all extracted data | No | Should not fail (data assembly) |
| 8. Register | Call `MediaAssetRegistry.register(asset)` | No | Should not fail |

### 5.3 Concurrency Model

```
Main Thread (UI)
  |
  +-- ImportQueueController (ChangeNotifier)
  |     - Manages queue state
  |     - Reports progress to UI
  |     - Handles cancel requests
  |
  +-- Background Isolate Pool (max 3)
        - File copy operations
        - Content hash generation
        - (Heavy I/O isolated from main thread)
  |
  +-- Native Background Queue (via platform channel)
        - Metadata extraction (AVAsset)
        - Thumbnail generation (AVAssetImageGenerator)
```

### 5.4 Progress Reporting

```dart
/// Import progress for a single file
@immutable
class ImportFileProgress {
  final String filename;
  final ImportFileState state;
  final double progress;  // 0.0 - 1.0
  final String? errorMessage;
  final MediaAsset? resultAsset;

  const ImportFileProgress({
    required this.filename,
    required this.state,
    this.progress = 0.0,
    this.errorMessage,
    this.resultAsset,
  });
}

enum ImportFileState {
  queued,
  copying,
  hashing,
  extractingMetadata,
  generatingThumbnail,
  complete,
  duplicate,  // Already exists, returned existing asset
  failed,
  cancelled,
}

/// Overall import queue progress
@immutable
class ImportQueueProgress {
  final int totalFiles;
  final int completedFiles;
  final int failedFiles;
  final int duplicateFiles;
  final List<ImportFileProgress> fileProgress;
  final bool isCancelled;

  double get overallProgress =>
      totalFiles > 0 ? completedFiles / totalFiles : 0.0;

  bool get isComplete =>
      completedFiles + failedFiles + duplicateFiles >= totalFiles;
}
```

### 5.5 Duplicate Detection During Batch Import

Within a single batch import, duplicates can occur in two ways:

1. **Same file selected twice in picker:** Deduplicated by content hash after copy+hash step. Second copy is deleted, existing `MediaAsset` returned.
2. **File already in registry from previous import:** Detected at step 4 (dedup check). New copy is deleted, existing `MediaAsset` returned.
3. **Same content, different filename:** Content hash matches. Treated as duplicate.
4. **Different content, same filename:** Content hash differs. Imported as separate asset. Original filename preserved for display.

### 5.6 Error Handling Strategy

| Error | User Action | System Action |
|-------|-------------|---------------|
| Single file fails | "1 file could not be imported" toast | Skip, continue others |
| Multiple files fail | "3 of 10 files could not be imported" with "View Details" | Skip, continue, log errors |
| All files fail | "Import failed" alert with error detail | Stop queue |
| Disk space exhaustion | "Not enough storage. Free X MB to continue." alert | Pause queue, clean up partial |
| App backgrounded during import | Continue in background (up to 30s) | Request background task via `BGTaskRequest` |
| App killed during import | Partial imports remain in Media/ | On next launch, scan for orphaned files |

---

## 6. Camera Capture

### 6.1 Architecture

Camera capture runs entirely in native Swift via a platform view embedded in Flutter. The native layer handles AVCaptureSession, preview, and recording. Flutter controls the UI chrome (buttons, settings) around the native preview.

```
Flutter Layer
+---------------------------------------+
| CameraCaptureView (StatefulWidget)    |
|  - Record button (CNButton.icon)      |
|  - Camera toggle button               |
|  - Flash toggle button                |
|  - Resolution selector                |
|  - Frame rate selector                |
|  - Timer display                      |
|  - Close button                       |
|                                       |
|  +-------------------------------+    |
|  | NativeCameraPreview           |    |
|  | (UiKitView / PlatformView)   |    |
|  +-------------------------------+    |
+---------------------------------------+

Native Layer (Swift)
+---------------------------------------+
| CameraCaptureService                  |
|  - AVCaptureSession                   |
|  - AVCaptureVideoDataOutput          |
|  - AVCaptureAudioDataOutput          |
|  - AVCaptureMovieFileOutput          |
|  - AVCaptureVideoPreviewLayer        |
|  - Camera/flash/resolution control   |
+---------------------------------------+
```

### 6.2 Camera Configuration Options

| Setting | Options | Default | Storage |
|---------|---------|---------|---------|
| Camera position | Front, Back | Back | User preference (persist) |
| Flash/Torch | Off, On, Auto | Off | Per-session |
| Resolution | 720p, 1080p, 4K | 1080p | User preference (persist) |
| Frame rate | 24, 30, 60 fps | 30 fps | User preference (persist) |
| Stabilization | Off, Standard, Cinematic | Standard | User preference (persist) |
| HDR | Off, On | Off | User preference (persist) |

### 6.3 Recording Flow

1. **Setup:** Initialize `AVCaptureSession` with selected camera, resolution, and frame rate
2. **Preview:** Display `AVCaptureVideoPreviewLayer` in a `UiKitView`
3. **Record start:** User taps record button; begin `AVCaptureMovieFileOutput` recording to temp file
4. **Timer:** Display recording duration on Flutter UI (updated via platform channel event stream)
5. **Record stop:** User taps stop button; finalize recording
6. **Auto-import:** Recorded clip is automatically imported into MediaAsset registry using the standard import pipeline
7. **Navigate:** Optionally open the clip in the editor or return to Media Browser

### 6.4 Native Implementation Outline

```swift
class CameraCaptureService: NSObject {
    private let session = AVCaptureSession()
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentCamera: AVCaptureDevice?
    private var isRecording = false

    func configure(resolution: CaptureResolution, frameRate: Int, position: AVCaptureDevice.Position) {
        session.beginConfiguration()

        // Set session preset based on resolution
        session.sessionPreset = resolution.avPreset

        // Configure camera
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        ) else { return }

        // Set frame rate
        try? camera.lockForConfiguration()
        let desiredRange = camera.activeFormat.videoSupportedFrameRateRanges.first {
            $0.maxFrameRate >= Double(frameRate)
        }
        if let range = desiredRange {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        }
        camera.unlockForConfiguration()

        // Add inputs and outputs...
        session.commitConfiguration()
    }

    func startRecording(to url: URL) {
        movieOutput?.startRecording(to: url, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording() {
        movieOutput?.stopRecording()
        isRecording = false
    }
}
```

### 6.5 Permissions

| Permission | Info.plist Key | When Requested |
|------------|---------------|----------------|
| Camera | `NSCameraUsageDescription` | First time user opens camera capture |
| Microphone | `NSMicrophoneUsageDescription` | First time recording with audio |

**Note:** Both permissions are required for video recording. If denied, show explanatory message with a button to open Settings.

---

## 7. Media Browser

### 7.1 Overview

The Media Browser is a new tab in the Project Library screen that displays all imported media assets. It provides grid/list views, search, filtering, sorting, and actions on media items.

### 7.2 Tab Integration

The Project Library currently has two tabs: **Projects** and **People**. The Media Browser adds a third tab: **Media**.

```dart
// Updated CNTabBar in project_library_view.dart
CNTabBar(
  items: [
    CNTabBarItem(
      label: 'Projects',
      icon: CNSymbol('square.grid.2x2'),
      activeIcon: CNSymbol('square.grid.2x2.fill'),
    ),
    CNTabBarItem(
      label: 'Media',
      icon: CNSymbol('photo.on.rectangle.angled'),
      activeIcon: CNSymbol('photo.on.rectangle.angled.fill'),  // SF Symbol name TBD
    ),
    CNTabBarItem(
      label: 'People',
      icon: CNSymbol('person.2'),
      activeIcon: CNSymbol('person.2.fill'),
    ),
  ],
  currentIndex: _currentTabIndex,
  onTap: (index) {
    HapticFeedback.selectionClick();
    setState(() => _currentTabIndex = index);
  },
  shrinkCentered: false,
)
```

**Note:** Tab bar width should increase from 220 to ~320 to accommodate three tabs.

### 7.3 Grid View (Default)

The default view shows media as a thumbnail grid, similar to the Projects grid:

| Property | Value |
|----------|-------|
| Columns | 3 (portrait), 4 (landscape) |
| Aspect ratio | 1:1 (square thumbnails) |
| Spacing | 2px (tight grid, like Apple Photos) |
| Thumbnail size | ~120x120pt |
| Lazy loading | Only load visible + 1 screen buffer |
| Scroll physics | Bouncing (iOS default) |

**Thumbnail overlays:**
- Bottom-left: Duration badge for videos (e.g., "0:42")
- Bottom-right: Type icon for non-video (photo icon, audio waveform)
- Top-right: Favorite heart icon (if favorited)
- Top-left: Color tag dot (if tagged)

### 7.4 List View (Optional)

Toggle between grid and list with a button in the navigation bar:

| Column | Width | Content |
|--------|-------|---------|
| Thumbnail | 60pt | Square thumbnail |
| Name | Flex | Original filename |
| Type | 40pt | Video/Photo/Audio icon |
| Duration | 50pt | "0:42" or "--:--" for photos |
| Size | 50pt | "45 MB" |
| Date | 80pt | "Jan 15, 2026" |

### 7.5 Search

CupertinoSearchTextField at the top of the scrollable area (below the large title navigation bar):

**Searchable fields:**
- Original filename (substring match, case-insensitive)
- Custom tags (exact match)
- Date (formatted string match, e.g., "January" or "2026")

**Implementation:** Local in-memory search over the `MediaAssetRegistry` contents. Filter as user types with 300ms debounce.

### 7.6 Filtering

Filter chips below the search bar (horizontally scrollable):

| Filter | Options | Multi-select? |
|--------|---------|---------------|
| Type | All, Video, Photo, Audio | Single select |
| Favorites | All, Favorites Only | Toggle |
| Tags | Each color tag, each custom tag | Multi-select |
| Linked | All, Linked, Unlinked | Single select |

### 7.7 Sorting

Sort options accessible from the trailing navigation bar button (same pattern as current Projects tab):

| Sort | Direction | Default |
|------|-----------|---------|
| Date Imported | Newest First / Oldest First | Newest First (default) |
| Date Created | Newest First / Oldest First | |
| Name | A-Z / Z-A | |
| Duration | Longest / Shortest | |
| File Size | Largest / Smallest | |

### 7.8 Context Menu Actions

Long-press on any media item shows a `CupertinoContextMenu` (same pattern as project cards):

```dart
CupertinoContextMenu.builder(
  enableHapticFeedback: true,
  actions: [
    CupertinoContextMenuAction(
      onPressed: () => _addToTimeline(asset),
      trailingIcon: CupertinoIcons.add,
      child: const Text('Add to Timeline'),
    ),
    CupertinoContextMenuAction(
      onPressed: () => _showMetadata(asset),
      trailingIcon: CupertinoIcons.info,
      child: const Text('Info'),
    ),
    CupertinoContextMenuAction(
      onPressed: () => _toggleFavorite(asset),
      trailingIcon: asset.isFavorite
          ? CupertinoIcons.heart_fill
          : CupertinoIcons.heart,
      child: Text(asset.isFavorite ? 'Unfavorite' : 'Favorite'),
    ),
    CupertinoContextMenuAction(
      onPressed: () => _showTagPicker(asset),
      trailingIcon: CupertinoIcons.tag,
      child: const Text('Tag'),
    ),
    CupertinoContextMenuAction(
      isDestructiveAction: true,
      onPressed: () => _deleteAsset(asset),
      trailingIcon: CupertinoIcons.trash,
      child: const Text('Delete'),
    ),
  ],
  // ... builder with scale animation
)
```

### 7.9 Swipe to Delete

Swipe-to-delete in list view using `CupertinoListTile` with delete confirmation via `CupertinoAlertDialog`.

### 7.10 Pull-to-Refresh

Using `CupertinoSliverRefreshControl` (same pattern as current Projects tab) to re-scan and verify all media assets.

---

## 8. Favorites & Tagging

### 8.1 Favorites

Simple boolean toggle on each `MediaAsset`. Favorited items show a filled heart overlay on their thumbnail and can be filtered in the Media Browser.

**Interaction:** Tap the heart icon in the context menu or a dedicated button in the metadata detail sheet.

### 8.2 Color Tags

Predefined color tags for visual organization:

| Tag | Color (CupertinoColors) | SF Symbol |
|-----|------------------------|-----------|
| Red | `.systemRed` | `circle.fill` (tinted red) |
| Orange | `.systemOrange` | `circle.fill` (tinted orange) |
| Yellow | `.systemYellow` | `circle.fill` (tinted yellow) |
| Green | `.systemGreen` | `circle.fill` (tinted green) |
| Blue | `.systemBlue` | `circle.fill` (tinted blue) |
| Purple | `.systemPurple` | `circle.fill` (tinted purple) |

**Interaction:** Tag picker sheet presented from context menu. User taps a color dot to toggle it. Multiple colors allowed per asset.

### 8.3 Custom Text Tags

Free-form text tags for flexible organization:

- User types a tag name (e.g., "interview", "b-roll", "drone")
- Autocomplete from existing tags in the project
- Multiple tags per asset
- Tags displayed as chips in metadata detail view
- Filterable in Media Browser

### 8.4 Data Model

```dart
/// Tag applied to a media asset
@immutable
class MediaTag {
  /// Unique tag identifier
  final String id;

  /// Tag type
  final MediaTagType type;

  /// For color tags: the color enum value
  final TagColor? color;

  /// For text tags: the tag text
  final String? text;

  const MediaTag.color(this.color)
      : id = 'color_${color!.name}',
        type = MediaTagType.color,
        text = null;

  const MediaTag.text(this.text)
      : id = 'text_$text',
        type = MediaTagType.text,
        color = null;
}

enum MediaTagType { color, text }

enum TagColor { red, orange, yellow, green, blue, purple }
```

### 8.5 Persistence

Tags are stored in two locations:

1. **Per-asset:** Each `MediaAsset` stores its own tags (travels with the asset through serialization)
2. **Global tag index:** A separate `MediaTagIndex` maintains a set of all known text tags for autocomplete, stored at `Documents/Media/tags.json`

---

## 9. Metadata Display

### 9.1 Metadata Detail Sheet

Presented as a `CupertinoActionSheet`-style bottom sheet when user taps "Info" in the context menu.

### 9.2 Metadata Fields

| Field | Source | Display Format | Example |
|-------|--------|---------------|---------|
| Filename | `MediaAsset.originalFilename` | As-is | "IMG_4521.MOV" |
| Type | `MediaAsset.type` | Capitalized | "Video" |
| Resolution | `MediaAsset.width` x `MediaAsset.height` | "W x H" | "3840 x 2160" |
| Duration | `MediaAsset.duration` | "HH:MM:SS.ms" | "00:01:42.500" |
| File Size | `MediaAsset.fileSize` | Formatted | "1.2 GB" |
| Codec | `MediaAsset.codec` | Human-readable | "H.265 (HEVC)" |
| Frame Rate | `MediaAsset.frameRate` | "X.XX fps" | "29.97 fps" |
| Audio | `MediaAsset.audioChannels` + `audioSampleRate` | "Channels @ Rate" | "Stereo @ 48 kHz" |
| Color Space | New field | SDR / HDR10 / Dolby Vision / HLG | "HDR (Dolby Vision)" |
| Bit Depth | New field | "X-bit" | "10-bit" |
| Creation Date | New field from AVAsset metadata | Date + time | "Jan 15, 2026 3:42 PM" |
| Import Date | `MediaAsset.importedAt` | Date + time | "Feb 6, 2026 10:15 AM" |
| GPS Location | New field from AVAsset metadata | Coordinates + optional place name | "37.7749, -122.4194 (San Francisco)" |
| Content Hash | `MediaAsset.contentHash` | Truncated | "a3f2b1...c8d9e0" |
| Asset ID | `MediaAsset.id` | UUID (copyable) | "550e8400-e29b-..." |

### 9.3 Metadata Extraction (Native)

Metadata extraction happens during the import pipeline via a new native platform channel method:

```swift
func extractMetadata(inputPath: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
        let url = URL(fileURLWithPath: inputPath)
        let asset = AVURLAsset(url: url)

        var metadata: [String: Any] = [:]

        // Video track info
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            let size = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
            metadata["width"] = Int(abs(size.width))
            metadata["height"] = Int(abs(size.height))
            metadata["frameRate"] = videoTrack.nominalFrameRate
            metadata["codec"] = videoTrack.mediaType.rawValue

            // Detect codec from format descriptions
            if let formatDesc = videoTrack.formatDescriptions.first {
                let desc = formatDesc as! CMFormatDescription
                let codecType = CMFormatDescriptionGetMediaSubType(desc)
                metadata["codecFourCC"] = String(fourCC: codecType)
            }

            // HDR detection
            if #available(iOS 14.0, *) {
                metadata["hasHDR"] = videoTrack.hasMediaCharacteristic(.containsHDRVideo)
            }
        }

        // Audio track info
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            if let formatDesc = audioTrack.formatDescriptions.first {
                let desc = formatDesc as! CMFormatDescription
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
                metadata["audioSampleRate"] = Int(asbd?.mSampleRate ?? 0)
                metadata["audioChannels"] = Int(asbd?.mChannelsPerFrame ?? 0)
                metadata["audioBitDepth"] = Int(asbd?.mBitsPerChannel ?? 0)
            }
        }

        // Duration
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        metadata["durationMicroseconds"] = Int(durationSeconds * 1_000_000)

        // File size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: inputPath)[.size] as? Int) ?? 0
        metadata["fileSize"] = fileSize

        // Creation date from metadata
        let commonMetadata = asset.metadata(forFormat: .quickTimeMetadata)
        for item in commonMetadata {
            if item.commonKey == .commonKeyCreationDate, let dateValue = item.dateValue {
                metadata["creationDate"] = ISO8601DateFormatter().string(from: dateValue)
            }
        }

        // GPS location from metadata
        for item in asset.metadata {
            if item.identifier == .quickTimeMetadataLocationISO6709 {
                metadata["locationISO6709"] = item.stringValue
            }
        }

        DispatchQueue.main.async {
            result(metadata)
        }
    }
}
```

### 9.4 Codec Display Names

| FourCC / Identifier | Display Name |
|---------------------|-------------|
| `avc1` | H.264 (AVC) |
| `hvc1`, `hev1` | H.265 (HEVC) |
| `ap4h`, `ap4x`, `apch`, `apcn`, `apcs`, `apco` | Apple ProRes |
| `av01` | AV1 |
| `vp09` | VP9 |
| Unknown | "Unknown ({fourCC})" |

---

## 10. Cloud Import

### 10.1 Strategy

Cloud import is primarily handled through existing system integration:

1. **iCloud Drive:** Already accessible via Files app picker (UIDocumentPickerViewController). No additional code needed.
2. **Third-party cloud apps:** If the user has Google Drive, Dropbox, or OneDrive apps installed, they appear as file providers in the Files picker. No additional code needed.
3. **Direct API integration:** For users without cloud apps installed, provide direct Google Drive and Dropbox integration.

### 10.2 iCloud Drive

Fully handled by the Files app integration (Section 4). No additional work needed.

### 10.3 Google Drive Integration

**Dependencies:**
```yaml
# pubspec.yaml additions
google_sign_in: ^6.2.2
googleapis: ^13.2.0
```

**Architecture:**
```
Flutter: CloudImportService
  |
  +-- GoogleDriveImporter
  |     - google_sign_in for auth
  |     - googleapis (DriveApi) for file listing + download
  |     - Shows native-style file browser
  |     - Downloads to temp, then runs import pipeline
  |
  +-- DropboxImporter (future)
        - flutter_appauth for OAuth 2.0
        - Dropbox HTTP API for file listing + download
```

**Google Drive Flow:**
1. User taps "Import from Google Drive" in import source picker
2. Present Google Sign-In (via `google_sign_in` package, uses system credential)
3. Request `drive.readonly` scope
4. Show file browser (custom UI listing files via `DriveApi.files.list()`)
5. User selects files
6. Download files with progress tracking (`DriveApi.files.get()` with `downloadOptions: DownloadOptions.fullMedia`)
7. Pass downloaded temp files into standard import pipeline

### 10.4 Dropbox Integration

**Dependencies:**
```yaml
# pubspec.yaml additions
flutter_appauth: ^7.0.1
http: ^1.2.0
```

**Flow:** Similar to Google Drive but using Dropbox OAuth 2.0 PKCE flow and REST API for file listing and download.

### 10.5 Download Progress and Cancellation

```dart
class CloudDownloadProgress {
  final String filename;
  final int bytesDownloaded;
  final int totalBytes;
  final CloudDownloadState state;

  double get progress => totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;
}

enum CloudDownloadState {
  queued,
  authenticating,
  downloading,
  importing,  // Handed off to import pipeline
  complete,
  failed,
  cancelled,
}
```

### 10.6 Error Handling

| Error | Handling |
|-------|---------|
| Auth failure | Show "Sign in failed" dialog with retry |
| Token expired | Auto-refresh, re-auth if refresh fails |
| Network lost during download | Pause, show "Waiting for network..." |
| Quota exceeded | Show "Storage quota exceeded" message |
| File not found (deleted on cloud) | Skip, show "File no longer available" |
| Rate limited | Back off exponentially, retry after delay |

---

## 11. Import from URL

### 11.1 UI Flow

1. User taps "Import from URL" in import source picker
2. Present a `CupertinoAlertDialog` with a `CupertinoTextField` for URL input
3. User pastes or types URL, taps "Download"
4. Validate URL format
5. Send HEAD request to check Content-Type and Content-Length
6. Show download progress sheet
7. Download file to temp directory
8. Pass downloaded file into standard import pipeline

### 11.2 URL Validation

```dart
class URLImporter {
  static const _supportedVideoTypes = [
    'video/mp4',
    'video/quicktime',
    'video/x-msvideo',
    'video/x-matroska',
    'video/webm',
  ];

  static const _supportedImageTypes = [
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/gif',
  ];

  static const _supportedAudioTypes = [
    'audio/mpeg',
    'audio/mp4',
    'audio/wav',
    'audio/x-wav',
    'audio/aac',
  ];

  static const _maxDownloadSize = 4 * 1024 * 1024 * 1024;  // 4GB

  Future<URLValidationResult> validateURL(String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri == null || !uri.hasScheme) {
      return URLValidationResult.invalid('Invalid URL format');
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return URLValidationResult.invalid('Only HTTP/HTTPS URLs are supported');
    }

    // HEAD request to check content type and size
    final response = await http.head(uri);

    final contentType = response.headers['content-type']?.split(';').first;
    final contentLength = int.tryParse(
        response.headers['content-length'] ?? '');

    if (contentType == null) {
      return URLValidationResult.invalid('Could not determine file type');
    }

    final isSupported = _supportedVideoTypes.contains(contentType) ||
        _supportedImageTypes.contains(contentType) ||
        _supportedAudioTypes.contains(contentType);

    if (!isSupported) {
      return URLValidationResult.invalid(
          'Unsupported file type: $contentType');
    }

    if (contentLength != null && contentLength > _maxDownloadSize) {
      return URLValidationResult.invalid(
          'File too large (${_formatSize(contentLength)})');
    }

    return URLValidationResult.valid(
      contentType: contentType,
      contentLength: contentLength,
      filename: uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'download',
    );
  }
}
```

### 11.3 Download Implementation

```dart
Future<File?> downloadFromURL(
  Uri uri, {
  required void Function(int downloaded, int total) onProgress,
  required CancellationToken cancellationToken,
}) async {
  final client = http.Client();
  try {
    final request = http.Request('GET', uri);
    final streamedResponse = await client.send(request);

    final totalBytes = streamedResponse.contentLength ?? 0;
    final tempDir = await getTemporaryDirectory();
    final extension = _extensionFromContentType(
        streamedResponse.headers['content-type'] ?? '');
    final tempFile = File(
        '${tempDir.path}/${const Uuid().v4()}$extension');

    final sink = tempFile.openWrite();
    int downloadedBytes = 0;

    await for (final chunk in streamedResponse.stream) {
      cancellationToken.throwIfCancelled();

      sink.add(chunk);
      downloadedBytes += chunk.length;
      onProgress(downloadedBytes, totalBytes);
    }

    await sink.close();
    return tempFile;
  } catch (e) {
    // Clean up partial download
    // ...
    rethrow;
  } finally {
    client.close();
  }
}
```

### 11.4 Resume Support

For large downloads, implement HTTP Range request resume:

1. If download is interrupted, record `bytesDownloaded` and temp file path
2. On retry, send `Range: bytes={bytesDownloaded}-` header
3. If server returns `206 Partial Content`, append to existing temp file
4. If server returns `200 OK` (no range support), restart download

---

## 12. Media Thumbnails

### 12.1 Thumbnail Generation Strategy

| Media Type | Generation Method | Size | Format |
|------------|------------------|------|--------|
| Video | `AVAssetImageGenerator` (native) at time 0 | 240x240pt (@2x: 480x480px) | JPEG 75% |
| Photo | `UIImage` downscale (native) | 240x240pt | JPEG 80% |
| Audio | Static waveform icon (no generation needed) | N/A | SF Symbol |

### 12.2 Thumbnail Cache

```
Documents/
  Media/
    .thumbnails/        # Hidden directory for thumbnail cache
      {assetId}.jpg     # One thumbnail per asset
```

**Cache policy:**
- Generated once at import time
- Never regenerated unless explicitly requested (e.g., user taps "Regenerate Thumbnail")
- Cleaned up when asset is deleted
- Total cache size is small (~100KB per thumbnail, 1000 assets = 100MB)

### 12.3 Lazy Loading in Grid View

```dart
class MediaThumbnailWidget extends StatefulWidget {
  final String assetId;
  final String? thumbnailPath;

  const MediaThumbnailWidget({
    super.key,
    required this.assetId,
    this.thumbnailPath,
  });

  @override
  State<MediaThumbnailWidget> createState() => _MediaThumbnailWidgetState();
}

class _MediaThumbnailWidgetState extends State<MediaThumbnailWidget> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    if (widget.thumbnailPath == null || _isLoading) return;
    _isLoading = true;

    final file = File(widget.thumbnailPath!);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _thumbnailBytes = bytes;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailBytes != null) {
      return Image.memory(
        _thumbnailBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,  // Prevents flicker on rebuild
      );
    }

    // Placeholder while loading
    return Container(
      color: CupertinoColors.systemGrey6.darkColor,
      child: const Center(
        child: Icon(
          CupertinoIcons.photo,
          color: CupertinoColors.systemGrey,
          size: 24,
        ),
      ),
    );
  }
}
```

### 12.4 Multiple Thumbnail Sizes

| Use Case | Size | When Generated |
|----------|------|----------------|
| Grid cell (Media Browser) | 240x240pt | At import time |
| List row (Media Browser) | 60x60pt | Downscaled from grid thumbnail |
| Timeline clip preview | 80x45pt | At clip creation time |
| Metadata detail | 400x400pt (max) | On-demand from source file |

### 12.5 Video Duration Overlay

For video thumbnails in the grid, overlay the duration in the bottom-right corner:

```dart
Positioned(
  bottom: 4,
  right: 4,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: CupertinoColors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      _formatDuration(asset.duration),
      style: const TextStyle(
        color: CupertinoColors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        fontFamily: '.SF Pro Text',
      ),
    ),
  ),
)
```

---

## 13. File Management

### 13.1 Storage Location Strategy

**New directory structure:**

```
Documents/
  Projects/                 # Project JSON files (unchanged)
    {projectId}.json
  Media/                    # ALL imported media (replaces Videos/)
    {assetId}.mov           # Video files
    {assetId}.mp4
    {assetId}.jpg           # Photo files
    {assetId}.png
    {assetId}.m4a           # Audio files
    .thumbnails/            # Thumbnail cache
      {assetId}.jpg
    tags.json               # Global tag index
    registry.json           # MediaAssetRegistry serialized state
  Videos/                   # LEGACY (migrate existing files)
    {uuid}.mov
  People/                   # People library (unchanged)
    {personId}/
      {imageId}.jpg
```

### 13.2 Migration from Legacy Structure

On first launch after update:
1. Check if `Documents/Videos/` exists and has files
2. For each file in `Videos/`:
   a. Generate content hash
   b. Create `MediaAsset` with metadata extracted from file
   c. Move (not copy) file to `Documents/Media/{assetId}.{ext}`
   d. Update all `Project` files that reference the old path to use the new path
3. Delete `Documents/Videos/` if empty
4. Save `MediaAssetRegistry` to `Documents/Media/registry.json`

### 13.3 Cleanup: Remove Unused Media

**Manual cleanup** (user-triggered from Settings or Media Browser):

1. Scan all `Project` files to collect referenced `MediaAsset` IDs
2. Compare against `MediaAssetRegistry` to find unreferenced assets
3. Show list of unreferenced assets with total size
4. User confirms deletion
5. Delete files and remove from registry

**Automatic cleanup** is NOT performed (too risky for user data).

### 13.4 Storage Usage Display

In Settings or Media Browser header, show:

```
Media Storage: 2.3 GB
  Videos: 2.1 GB (12 files)
  Photos: 180 MB (45 files)
  Audio: 20 MB (3 files)
  Thumbnails: 12 MB

  Total Device Storage: 128 GB
  Available: 45.2 GB
```

### 13.5 File Format Validation

Before importing, validate the file:

| Check | Method | Action on Failure |
|-------|--------|-------------------|
| File exists | `File.exists()` | Skip with error |
| File readable | `File.open()` try/catch | Skip with error |
| Size > 0 bytes | `File.length()` | Skip with error |
| Size < 4GB | `File.length()` | Show size warning, block |
| Extension supported | Check against known extensions | Show "Unsupported format" |
| Can create AVAsset | Native: `AVAsset(url:)` + track check | Show "Cannot read file" |
| Has video or audio track | Native: `asset.tracks(withMediaType:)` | Show "No media tracks found" |

### 13.6 Corrupted File Detection

During metadata extraction, if AVAsset cannot read the file:
1. Mark the import as failed
2. Delete the copied file from `Documents/Media/`
3. Show error: "This file appears to be corrupted and cannot be imported."

---

## 14. Platform Channels

### 14.1 New Platform Channel: MediaImportChannel

**Channel name:** `com.liquideditor/media_import`

| Method | Arguments | Returns | Purpose |
|--------|-----------|---------|---------|
| `importFromPhotos` | `{mediaTypes: [String], selectionLimit: int}` | `[{url: String, type: String, assetId: String?}]` | Present PHPicker |
| `importFromFiles` | `{allowsMultipleSelection: bool}` | `[{url: String, type: String}]` | Present UIDocumentPicker |
| `extractMetadata` | `{path: String}` | `{width, height, duration, codec, frameRate, audioChannels, audioSampleRate, creationDate, location, ...}` | Extract all metadata from a media file |
| `generateImportThumbnail` | `{path: String, size: int}` | `Uint8List` (JPEG bytes) | Generate square thumbnail |
| `startCameraCapture` | `{resolution: String, frameRate: int, position: String}` | void (uses event channel) | Start camera session |
| `stopCameraCapture` | none | `{path: String, duration: int}` | Stop recording, return file |
| `switchCamera` | none | void | Toggle front/back |
| `toggleFlash` | `{mode: String}` | void | Set flash mode |
| `getStorageInfo` | none | `{totalBytes: int, availableBytes: int, mediaBytes: int}` | Get device storage info |

### 14.2 Event Channel: Import Progress

**Channel name:** `com.liquideditor/media_import/progress`

Events sent during import operations:

```dart
// Event format
{
  'event': 'icloud_download_progress',
  'assetId': 'xxx',
  'progress': 0.45,  // 0.0 - 1.0
}

{
  'event': 'camera_recording_time',
  'durationMs': 5234,
}

{
  'event': 'camera_error',
  'message': 'Camera access denied',
}
```

### 14.3 Existing Channel Extensions

The existing `com.liquideditor/video_processing` channel already has:
- `generateThumbnail` -- reuse for import thumbnails
- `extractFirstFrame` -- reuse for photo/video previews
- `extractFrameAtProgress` -- reuse for thumbnail at specific time

No changes needed to the existing channel.

### 14.4 Native Service Registration

In `AppDelegate.swift` `setupPlatformChannels()`:

```swift
// Initialize media import service
let mediaImportChannel = FlutterMethodChannel(
    name: "com.liquideditor/media_import",
    binaryMessenger: messenger
)

let mediaImportEventChannel = FlutterEventChannel(
    name: "com.liquideditor/media_import/progress",
    binaryMessenger: messenger
)

let mediaImportService = MediaImportService()
mediaImportService.register(
    methodChannel: mediaImportChannel,
    eventChannel: mediaImportEventChannel
)
```

---

## 15. Data Model Changes

### 15.1 MediaAsset Extensions

Add new fields to `MediaAsset`:

```dart
@immutable
class MediaAsset {
  // ... existing fields ...

  /// Whether this asset is a favorite
  final bool isFavorite;

  /// Color tags applied to this asset
  final List<TagColor> colorTags;

  /// Custom text tags applied to this asset
  final List<String> textTags;

  /// Color space information (SDR, HDR10, DolbyVision, HLG)
  final String? colorSpace;

  /// Bit depth (8, 10, 12)
  final int? bitDepth;

  /// Creation date of the original media (from file metadata)
  final DateTime? creationDate;

  /// GPS location ISO 6709 string (if available)
  final String? locationISO6709;

  /// Thumbnail file path (relative to Documents/Media/.thumbnails/)
  final String? thumbnailPath;

  /// Source of the import (photoLibrary, files, camera, url, cloud)
  final ImportSource? importSource;
}

enum ImportSource {
  photoLibrary,
  files,
  camera,
  url,
  googleDrive,
  dropbox,
}
```

### 15.2 MediaAssetRegistry Persistence

Currently the registry lives only in memory. For the media management system, it needs to be persisted independently of projects:

```dart
class MediaAssetRegistry extends ChangeNotifier {
  // ... existing methods ...

  /// Path to the registry persistence file
  static const _registryFilename = 'registry.json';

  /// Load registry from disk
  Future<void> loadFromDisk() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File('${docsDir.path}/Media/$_registryFilename');

    if (await file.exists()) {
      final json = jsonDecode(await file.readAsString());
      fromJson(json as List<dynamic>);
    }
  }

  /// Save registry to disk (debounced)
  Future<void> saveToDisk() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File('${docsDir.path}/Media/$_registryFilename');

    // Ensure directory exists
    final dir = Directory('${docsDir.path}/Media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Atomic write
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(toJson()));
    await tempFile.rename(file.path);
  }

  /// Filter assets by type
  Iterable<MediaAsset> ofType(MediaType type) =>
      assets.where((a) => a.type == type);

  /// Filter favorites
  Iterable<MediaAsset> get favorites =>
      assets.where((a) => a.isFavorite);

  /// Filter by color tag
  Iterable<MediaAsset> withColorTag(TagColor color) =>
      assets.where((a) => a.colorTags.contains(color));

  /// Filter by text tag
  Iterable<MediaAsset> withTextTag(String tag) =>
      assets.where((a) => a.textTags.contains(tag));

  /// Search by filename
  Iterable<MediaAsset> search(String query) {
    final lower = query.toLowerCase();
    return assets.where((a) =>
        a.originalFilename.toLowerCase().contains(lower) ||
        a.textTags.any((t) => t.toLowerCase().contains(lower)));
  }
}
```

### 15.3 Project Model Updates

The `Project` model needs to transition from `sourceVideoPath` to MediaAsset references:

```dart
class Project {
  // ... existing fields ...

  /// Media assets used in this project (by ID)
  /// Replaces the single sourceVideoPath field
  final List<String> mediaAssetIds;

  /// Primary media asset ID (first imported video)
  /// For backward compatibility with single-video projects
  String? get primaryMediaAssetId =>
      mediaAssetIds.isNotEmpty ? mediaAssetIds.first : null;
}
```

**Migration:** Existing projects with `sourceVideoPath` will be migrated to reference a `MediaAsset` in the registry. The `sourceVideoPath` field is kept for backward compatibility.

### 15.4 ImportQueueController

```dart
class ImportQueueController extends ChangeNotifier {
  final MediaAssetRegistry _registry;
  final List<ImportTask> _queue = [];
  final List<ImportFileProgress> _progress = [];
  bool _isProcessing = false;

  /// Current queue state
  ImportQueueProgress get progress => ImportQueueProgress(
    totalFiles: _queue.length,
    completedFiles: _progress.where(
        (p) => p.state == ImportFileState.complete).length,
    failedFiles: _progress.where(
        (p) => p.state == ImportFileState.failed).length,
    duplicateFiles: _progress.where(
        (p) => p.state == ImportFileState.duplicate).length,
    fileProgress: List.unmodifiable(_progress),
    isCancelled: false,
  );

  /// Add files to the import queue
  void enqueue(List<ImportTask> tasks) {
    _queue.addAll(tasks);
    _progress.addAll(tasks.map((t) => ImportFileProgress(
      filename: t.filename,
      state: ImportFileState.queued,
    )));
    notifyListeners();

    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Cancel all pending imports
  void cancelAll() {
    _queue.clear();
    // Mark remaining queued items as cancelled
    notifyListeners();
  }
}

@immutable
class ImportTask {
  final String tempFilePath;
  final String filename;
  final MediaType expectedType;
  final ImportSource source;

  const ImportTask({
    required this.tempFilePath,
    required this.filename,
    required this.expectedType,
    required this.source,
  });
}
```

---

## 16. UI Design

### 16.1 Import Source Picker

When user taps the "+" FAB button on the Media tab, show a `CupertinoActionSheet`:

```dart
CupertinoActionSheet(
  title: const Text('Import Media'),
  message: const Text('Choose a source to import from'),
  actions: [
    CupertinoActionSheetAction(
      onPressed: () => _importFromPhotos(),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.photo_on_rectangle, size: 20),
          SizedBox(width: 8),
          Text('Photo Library'),
        ],
      ),
    ),
    CupertinoActionSheetAction(
      onPressed: () => _importFromFiles(),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.folder, size: 20),
          SizedBox(width: 8),
          Text('Files'),
        ],
      ),
    ),
    CupertinoActionSheetAction(
      onPressed: () => _captureFromCamera(),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.camera, size: 20),
          SizedBox(width: 8),
          Text('Camera'),
        ],
      ),
    ),
    CupertinoActionSheetAction(
      onPressed: () => _importFromURL(),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.link, size: 20),
          SizedBox(width: 8),
          Text('URL'),
        ],
      ),
    ),
    CupertinoActionSheetAction(
      onPressed: () => _importFromCloud(),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.cloud_download, size: 20),
          SizedBox(width: 8),
          Text('Cloud Storage'),
        ],
      ),
    ),
  ],
  cancelButton: CupertinoActionSheetAction(
    isDefaultAction: true,
    onPressed: () => Navigator.pop(context),
    child: const Text('Cancel'),
  ),
)
```

### 16.2 Import Progress Sheet

During batch import, show a bottom sheet with progress:

```
+------------------------------------------+
| Importing Media              [Cancel]     |
|                                          |
| file_001.mov        [=========>  ] 75%   |
| file_002.jpg        [===>       ] 30%    |
| file_003.mov        Queued               |
|                                          |
| 2 of 5 complete                          |
| 1 duplicate skipped                      |
+------------------------------------------+
```

### 16.3 Media Detail Sheet

Full metadata view presented as a draggable bottom sheet:

```
+------------------------------------------+
|           [Drag handle bar]              |
|                                          |
|  +------------------+                    |
|  |                  |                    |
|  |   Large Preview  |  Filename.MOV      |
|  |                  |  Video - 1:42      |
|  +------------------+  1.2 GB            |
|                                          |
|  [heart] [tag]  [share]  [delete]        |
|                                          |
|  ---- Details ----                       |
|  Resolution    3840 x 2160              |
|  Frame Rate    29.97 fps                |
|  Codec         H.265 (HEVC)            |
|  Color Space   HDR (Dolby Vision)       |
|  Bit Depth     10-bit                   |
|  Audio         Stereo @ 48 kHz          |
|  Created       Jan 15, 2026 3:42 PM    |
|  Imported      Feb 6, 2026 10:15 AM    |
|  Location      San Francisco, CA        |
|  Content Hash  a3f2b1...c8d9e0         |
|                                          |
|  ---- Tags ----                         |
|  [Red] [Blue]  #interview  #b-roll      |
|  [+ Add Tag]                            |
|                                          |
+------------------------------------------+
```

### 16.4 Camera Capture View

Full-screen camera view with iOS-native controls:

```
+------------------------------------------+
|  [X Close]              [Flash: Auto]    |
|                                          |
|                                          |
|                                          |
|        [ Native Camera Preview ]         |
|                                          |
|                                          |
|                                          |
|  1080p  30fps                            |
|                                          |
|  [Flip]    ( Record )    [Settings]      |
|                    00:00:42              |
+------------------------------------------+
```

### 16.5 FAB Behavior by Tab

| Tab | FAB Action |
|-----|-----------|
| Projects | Show import source picker, then create project with selected media |
| Media | Show import source picker, import to Media library |
| People | Show "Add Person" sheet (unchanged) |

---

## 17. Edge Cases

### 17.1 File System Edge Cases

| Edge Case | Detection | Handling |
|-----------|-----------|---------|
| Very large files (>4GB) | `File.length()` check | Block import, show "File too large (max 4GB)" |
| Unsupported codecs | Native metadata extraction fails or returns unknown codec | Import file, flag as "Unknown codec - may not play correctly" |
| Portrait vs landscape orientation | `preferredTransform` on video track | Store orientation in metadata, `MediaAsset.width`/`height` should reflect post-transform dimensions |
| Corrupted files | AVAsset fails to read tracks | Delete copied file, show "File appears corrupted" |
| Zero-byte files | `File.length() == 0` | Skip with error "File is empty" |
| Extremely long videos (>4 hours) | Duration check after metadata extraction | Allow but show warning "Very long video may impact performance" |
| Files with special characters in name | Stored as `originalFilename` for display, file renamed to UUID on disk | No issue (UUID filenames avoid encoding problems) |
| File with no extension | UTType detection from file content (magic bytes) | Fall back to content sniffing via native code |

### 17.2 Import Interruption Edge Cases

| Edge Case | Detection | Handling |
|-----------|-----------|---------|
| App backgrounded during import | `AppLifecycleState.paused` | Request background execution time (30s), continue if possible |
| App killed during import | Orphaned temp files or partial copies in `Documents/Media/` | On next launch, scan for files not in registry, offer import or cleanup |
| Disk space exhaustion | `FileSystemException` or check before copy | Show "Not enough storage" alert, calculate needed space, pause queue |
| Memory pressure | `didReceiveMemoryWarning` | Reduce concurrent imports to 1, release thumbnail caches |
| Network lost during iCloud/URL download | `URLSession` error or timeout | Pause download, show "Waiting for connection...", auto-retry |

### 17.3 Data Integrity Edge Cases

| Edge Case | Detection | Handling |
|-----------|-----------|---------|
| Duplicate file with different name | Content hash match | Return existing `MediaAsset`, show "Already imported as {name}" |
| File moved/deleted after import | `MediaAsset.isLinked` check fails | Mark as unlinked, show broken file icon, offer relinking dialog |
| Registry corruption | JSON parse error on load | Fall back to scanning `Documents/Media/` and rebuilding registry |
| Thumbnail cache corruption | File exists but cannot be decoded | Delete thumbnail, regenerate on next display |
| Project references deleted asset | `MediaAssetRegistry.getById()` returns null | Show "Missing media" placeholder in editor, offer reimport |

### 17.4 Permission Edge Cases

| Edge Case | Detection | Handling |
|-----------|-----------|---------|
| Camera permission denied | `AVCaptureDevice.authorizationStatus == .denied` | Show explanation dialog with "Open Settings" button |
| Microphone permission denied | `AVAudioSession` auth check | Show "Audio will not be recorded" warning, allow video-only recording |
| Photo library limited access | `PHAuthorizationStatus.limited` | PHPicker works normally (no issue) |
| iCloud not signed in | iCloud container returns nil | Show "Sign in to iCloud to access iCloud Drive" |

---

## 18. Performance

### 18.1 Performance Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Thumbnail generation | < 100ms per file | Native `AVAssetImageGenerator` on background queue |
| Content hash generation | < 200ms per file | Background isolate, SHA-256 of 2MB max |
| Metadata extraction | < 50ms per file | Native `AVAsset` property reads |
| Import pipeline (per file) | < 500ms (small) to < 5s (large) | Dominated by file copy I/O |
| Import queue throughput | 3 concurrent | Balance speed vs memory |
| Media browser scroll | 60fps with 1000+ items | Lazy loading, recycled thumbnails |
| Search response | < 100ms | In-memory filter, debounced input |
| Registry load | < 50ms for 1000 assets | JSON parse, single file read |
| Registry save | < 20ms for 1000 assets | Atomic write, debounced |

### 18.2 Memory Budget

| Component | Budget | Notes |
|-----------|--------|-------|
| Thumbnail cache (in-memory) | < 30MB | ~50 visible thumbnails at 240x240 JPEG |
| Import queue buffers | < 20MB | File copy chunks, hash buffers |
| Media browser list | < 5MB | `MediaAsset` objects in registry |
| Camera preview | < 50MB | Native `AVCaptureSession` managed |
| Total media system | < 100MB | Well within 200MB app limit |

### 18.3 Optimization Strategies

1. **Thumbnail lazy loading:** Only load thumbnails for visible grid cells + 1 screen buffer. Use `Image.memory` with `gaplessPlayback: true` to prevent flicker.

2. **Import concurrency cap:** Maximum 3 concurrent import pipelines. Each pipeline runs file copy and hash on a background isolate, metadata/thumbnail on native background queue.

3. **Registry save debounce:** After any mutation, debounce registry save by 2 seconds. Prevents excessive disk I/O during batch operations.

4. **Search debounce:** 300ms debounce on search text input. Filter runs on main thread since it is an in-memory operation over `MediaAsset` list (fast for < 10,000 items).

5. **Grid view recycling:** Use `SliverGrid` with builder pattern. Widget recycling is automatic. Thumbnails are loaded per-widget lifecycle.

6. **Large file copy:** Use `File.copy()` (which delegates to the OS kernel for zero-copy when possible) rather than stream-based copy.

---

## 19. Security & Privacy

### 19.1 Privacy Principles

1. **Minimal permissions:** PHPickerViewController requires NO photo library permission. Only request camera/microphone when user opens camera.
2. **Local-first:** All media is copied to app sandbox. No data leaves the device unless user explicitly exports.
3. **No tracking:** GPS location metadata is stored locally, never transmitted.
4. **No analytics:** Import statistics are not sent to any server.

### 19.2 Data Protection

| Data | Protection | Notes |
|------|-----------|-------|
| Media files | iOS Data Protection (Complete Until First Unlock) | Default for app Documents/ |
| Thumbnails | Same as media files | In Documents/Media/.thumbnails/ |
| Registry JSON | Same as media files | Contains metadata only, no file content |
| Cloud auth tokens | iOS Keychain | Managed by `google_sign_in` / `flutter_appauth` |
| Camera frames | Never written to disk except as recording output | Processed in memory only |

### 19.3 Sandboxing

- All imported files are copied INTO the app sandbox (`Documents/Media/`).
- Original files are never modified.
- Security-scoped resource access is released immediately after copy.
- No persistent file bookmarks are stored (we copy, not reference).
- All file paths stored in the registry are relative to the Documents directory.

---

## 20. Implementation Plan

### Phase 1: Foundation (Import Pipeline + Photo Library + Files App)
**Priority:** High
**Estimated Effort:** 3-5 days

| Task | Files | Dependencies |
|------|-------|-------------|
| 1.1 Create `MediaImportService.swift` with PHPicker integration | `ios/Runner/MediaImport/MediaImportService.swift` | None |
| 1.2 Create `MediaImportService.swift` UIDocumentPicker integration | Same file | 1.1 |
| 1.3 Create `com.liquideditor/media_import` platform channel | `ios/Runner/AppDelegate.swift`, `lib/services/media_import_channel.dart` | 1.1, 1.2 |
| 1.4 Add `extractMetadata` to native service | `ios/Runner/MediaImport/MediaImportService.swift` | 1.1 |
| 1.5 Extend `MediaAsset` with new fields (favorites, tags, colorSpace, etc.) | `lib/models/media_asset.dart` | None |
| 1.6 Add registry persistence (`loadFromDisk`, `saveToDisk`) | `lib/models/media_asset.dart` | 1.5 |
| 1.7 Create `ImportQueueController` | `lib/core/import_queue_controller.dart` | 1.3, 1.5, 1.6 |
| 1.8 Create `MediaImportService` (Dart) coordinating import pipeline | `lib/services/media_import_service.dart` | 1.3, 1.7 |
| 1.9 Update `_importVideo()` in project library to use new pipeline | `lib/views/library/project_library_view.dart` | 1.8 |
| 1.10 Legacy migration (`Videos/` to `Media/`) | `lib/core/media_migration.dart` | 1.6, 1.7 |
| 1.11 Tests for import pipeline, registry persistence, migration | `test/core/import_queue_test.dart`, `test/models/media_asset_test.dart` | 1.7, 1.6 |

### Phase 2: Media Browser + Thumbnails + Metadata
**Priority:** High
**Estimated Effort:** 3-4 days

| Task | Files | Dependencies |
|------|-------|-------------|
| 2.1 Add "Media" tab to Project Library | `lib/views/library/project_library_view.dart` | Phase 1 |
| 2.2 Create `MediaBrowserView` (grid view) | `lib/views/library/media_browser_view.dart` | 2.1 |
| 2.3 Create `MediaThumbnailWidget` with lazy loading | `lib/views/library/media_thumbnail_widget.dart` | 2.2 |
| 2.4 Add thumbnail generation to import pipeline | `lib/services/media_import_service.dart`, native | 1.8 |
| 2.5 Create `MediaDetailSheet` (metadata display) | `lib/views/library/media_detail_sheet.dart` | 2.2 |
| 2.6 Add context menu actions (info, favorite, delete) | `lib/views/library/media_browser_view.dart` | 2.2, 2.5 |
| 2.7 Search and filter functionality | `lib/views/library/media_browser_view.dart` | 2.2 |
| 2.8 Sort options | `lib/views/library/media_browser_view.dart` | 2.2 |
| 2.9 List view toggle | `lib/views/library/media_browser_view.dart` | 2.2 |
| 2.10 Import progress sheet UI | `lib/views/library/import_progress_sheet.dart` | 1.7 |
| 2.11 Tests for browser, search, filtering | `test/views/media_browser_test.dart` | 2.2 |

### Phase 3: Camera Capture
**Priority:** Medium
**Estimated Effort:** 3-4 days

| Task | Files | Dependencies |
|------|-------|-------------|
| 3.1 Create `CameraCaptureService.swift` | `ios/Runner/Camera/CameraCaptureService.swift` | None |
| 3.2 Create `CameraCaptureViewFactory.swift` (PlatformView) | `ios/Runner/Camera/CameraCaptureViewFactory.swift` | 3.1 |
| 3.3 Register camera platform view in `AppDelegate` | `ios/Runner/AppDelegate.swift` | 3.1, 3.2 |
| 3.4 Create `CameraCaptureView` (Flutter) | `lib/views/camera/camera_capture_view.dart` | 3.3 |
| 3.5 Camera settings (resolution, fps, flash) | `lib/views/camera/camera_settings_sheet.dart` | 3.4 |
| 3.6 Auto-import recorded clip | `lib/views/camera/camera_capture_view.dart` | 3.4, 1.8 |
| 3.7 Permission handling (camera, microphone) | `lib/views/camera/camera_capture_view.dart` | 3.4 |
| 3.8 Tests for camera service integration | `test/camera/camera_capture_test.dart` | 3.4 |

### Phase 4: Favorites, Tagging, Cloud Import
**Priority:** Low
**Estimated Effort:** 3-4 days

| Task | Files | Dependencies |
|------|-------|-------------|
| 4.1 Favorite toggle implementation | `lib/models/media_asset.dart`, `lib/views/library/media_browser_view.dart` | Phase 2 |
| 4.2 Color tag picker sheet | `lib/views/library/tag_picker_sheet.dart` | Phase 2 |
| 4.3 Custom text tag input with autocomplete | `lib/views/library/tag_picker_sheet.dart` | 4.2 |
| 4.4 Tag filtering in Media Browser | `lib/views/library/media_browser_view.dart` | 4.2, 4.3 |
| 4.5 Global tag index persistence | `lib/models/media_tag_index.dart` | 4.3 |
| 4.6 Google Drive import | `lib/services/cloud/google_drive_importer.dart` | Phase 1 |
| 4.7 URL import | `lib/services/url_importer.dart` | Phase 1 |
| 4.8 Storage usage display | `lib/views/settings/storage_usage_view.dart` | Phase 2 |
| 4.9 Unused media cleanup | `lib/core/media_cleanup.dart` | Phase 2 |
| 4.10 Tests for tags, cloud import, URL import | Various test files | 4.1-4.9 |

---

## 21. File Structure

### 21.1 New Dart Files

```
lib/
  models/
    media_asset.dart              # MODIFY: Add isFavorite, colorTags, textTags, colorSpace, etc.
    media_tag.dart                # NEW: MediaTag, TagColor, MediaTagType
    media_tag_index.dart          # NEW: Global tag index for autocomplete

  core/
    import_queue_controller.dart  # NEW: Import queue with progress
    media_migration.dart          # NEW: Legacy Videos/ to Media/ migration

  services/
    media_import_channel.dart     # NEW: Platform channel wrapper for native import
    media_import_service.dart     # NEW: Dart-side import orchestrator
    url_importer.dart             # NEW: Download from URL
    cloud/
      google_drive_importer.dart  # NEW: Google Drive API integration
      dropbox_importer.dart       # NEW: Dropbox API integration (future)

  views/
    library/
      project_library_view.dart   # MODIFY: Add Media tab
      media_browser_view.dart     # NEW: Grid/list media browser
      media_thumbnail_widget.dart # NEW: Lazy-loading thumbnail widget
      media_detail_sheet.dart     # NEW: Metadata display sheet
      import_progress_sheet.dart  # NEW: Import queue progress UI
      import_source_sheet.dart    # NEW: Import source picker
      tag_picker_sheet.dart       # NEW: Color/text tag picker
    camera/
      camera_capture_view.dart    # NEW: Camera capture screen
      camera_settings_sheet.dart  # NEW: Camera settings
    settings/
      storage_usage_view.dart     # NEW: Storage usage display
```

### 21.2 New Swift Files

```
ios/Runner/
  MediaImport/
    MediaImportService.swift        # NEW: PHPicker + UIDocumentPicker + metadata extraction
    MediaImportMethodChannel.swift  # NEW: Platform channel handler
  Camera/
    CameraCaptureService.swift      # NEW: AVCaptureSession management
    CameraCaptureViewFactory.swift  # NEW: PlatformView factory for camera preview
```

### 21.3 Modified Files

| File | Changes |
|------|---------|
| `lib/models/media_asset.dart` | Add `isFavorite`, `colorTags`, `textTags`, `colorSpace`, `bitDepth`, `creationDate`, `locationISO6709`, `thumbnailPath`, `importSource` fields; add registry persistence methods; add filtering methods |
| `lib/models/project.dart` | Add `mediaAssetIds` field; migration from `sourceVideoPath` |
| `lib/views/library/project_library_view.dart` | Add Media tab to CNTabBar; change FAB behavior per tab; increase tab bar width |
| `ios/Runner/AppDelegate.swift` | Register `MediaImportService` and `CameraCaptureService`; add platform channels |
| `pubspec.yaml` | Add `google_sign_in`, `googleapis`, `http` dependencies (Phase 4) |

---

## 22. Test Plan

### 22.1 Unit Tests

| Test File | Coverage |
|-----------|----------|
| `test/models/media_asset_extended_test.dart` | New MediaAsset fields, serialization, favorites, tags |
| `test/models/media_tag_test.dart` | MediaTag, TagColor, serialization |
| `test/core/import_queue_test.dart` | Import queue controller, progress tracking, cancellation, error handling |
| `test/core/media_migration_test.dart` | Legacy Videos/ to Media/ migration |
| `test/services/media_import_service_test.dart` | Import pipeline orchestration, dedup detection |
| `test/services/url_importer_test.dart` | URL validation, content type checking |

### 22.2 Widget Tests

| Test File | Coverage |
|-----------|----------|
| `test/views/media_browser_test.dart` | Grid rendering, search, filtering, sorting, context menu |
| `test/views/media_thumbnail_test.dart` | Lazy loading, placeholder, error states |
| `test/views/media_detail_sheet_test.dart` | Metadata display formatting |
| `test/views/import_progress_sheet_test.dart` | Progress UI states |
| `test/views/tag_picker_test.dart` | Color tag selection, text tag input |

### 22.3 Integration Tests

| Scenario | What to Verify |
|----------|---------------|
| Single video import | File copied, hash generated, metadata extracted, thumbnail created, MediaAsset registered, appears in browser |
| Batch import (5 files) | All 5 processed, progress reported correctly, duplicates detected |
| Duplicate detection | Same file imported twice results in single MediaAsset |
| App backgrounded during import | Import continues or resumes correctly |
| Large file (1GB+) | Import completes, memory stays within budget |
| Corrupt file | Error reported, partial file cleaned up, other imports continue |
| Search and filter | Results match query, filters combine correctly |
| Favorite toggle | State persisted, reflected in UI, filter works |
| Tag add/remove | Tags persisted, autocomplete works, filter works |
| Legacy migration | Existing projects still work, files moved correctly |

### 22.4 Performance Tests

| Test | Target | Method |
|------|--------|--------|
| Thumbnail generation speed | < 100ms per file | Benchmark 100 files, measure p50/p99 |
| Import throughput | 3 files concurrent | Measure total time for 10 file batch |
| Browser scroll FPS | 60fps with 1000 items | Profile with Flutter DevTools |
| Search latency | < 100ms | Measure time from query change to results |
| Registry save/load | < 50ms for 1000 assets | Benchmark serialization round-trip |

---

## Appendix A: Supported File Formats

### Video

| Format | Extension | Codec | Supported |
|--------|-----------|-------|-----------|
| MPEG-4 | .mp4 | H.264, H.265 | Yes |
| QuickTime | .mov | H.264, H.265, ProRes | Yes |
| MPEG-4 Video | .m4v | H.264, H.265 | Yes |
| AVI | .avi | Various | Best effort |
| WebM | .webm | VP8, VP9 | iOS 14+ (limited) |
| MKV | .mkv | Various | Not natively supported |

### Image

| Format | Extension | Supported |
|--------|-----------|-----------|
| JPEG | .jpg, .jpeg | Yes |
| PNG | .png | Yes |
| HEIF/HEIC | .heic, .heif | Yes |
| GIF | .gif | Yes (first frame for editing, animated for preview) |
| RAW/DNG | .dng | Yes (via native conversion) |
| TIFF | .tiff, .tif | Yes |
| WebP | .webp | iOS 14+ |
| BMP | .bmp | Yes |

### Audio

| Format | Extension | Supported |
|--------|-----------|-----------|
| AAC | .m4a, .aac | Yes |
| MP3 | .mp3 | Yes |
| WAV | .wav | Yes |
| AIFF | .aiff, .aif | Yes |
| FLAC | .flac | iOS 11+ |
| ALAC | .m4a | Yes |

---

## Appendix B: Error Messages

| Error Code | User Message | Detail |
|------------|-------------|--------|
| `IMPORT_FILE_NOT_FOUND` | "The selected file could not be found." | File was deleted between selection and import |
| `IMPORT_FILE_TOO_LARGE` | "This file is too large to import (max 4 GB)." | File exceeds size limit |
| `IMPORT_UNSUPPORTED_FORMAT` | "This file format is not supported." | Unknown UTType or codec |
| `IMPORT_CORRUPTED` | "This file appears to be corrupted." | AVAsset cannot read tracks |
| `IMPORT_DISK_FULL` | "Not enough storage space. Free {X} to continue." | Disk space exhaustion |
| `IMPORT_PERMISSION_DENIED` | "Access denied. Check permissions in Settings." | Camera or photo library permission denied |
| `IMPORT_ICLOUD_FAILED` | "Could not download from iCloud. Check your connection." | iCloud download failure |
| `IMPORT_NETWORK_ERROR` | "Download failed. Check your internet connection." | URL or cloud download failure |
| `IMPORT_CANCELLED` | "Import cancelled." | User cancelled |
| `CAMERA_PERMISSION_DENIED` | "Camera access is required to record video." | Camera permission denied |
| `CAMERA_MICROPHONE_DENIED` | "Microphone access denied. Video will be recorded without audio." | Microphone permission denied |

---

**Last Updated:** 2026-02-06
**Document Version:** 1.0

---

## Review 1 - Architecture & Completeness

**Reviewer:** Claude Opus 4.6 (Architecture Review)
**Date:** 2026-02-06
**Scope:** Full document review against codebase for architectural soundness, completeness, and technical feasibility.

---

### Summary

The design document is exceptionally thorough -- one of the most complete feature design documents I have reviewed. It covers all 10 import features with detailed native code samples, data models, edge cases, and phased implementation. However, I have identified several issues ranging from critical architectural gaps to minor clarifications needed.

**Overall Assessment:** Strong design with 3 critical issues, 8 important issues, 6 minor issues, and 5 open questions that need resolution before implementation begins.

---

### CRITICAL Issues

#### CRITICAL-1: Live Photo Type Check Ordering Bug in PHPicker Delegate (Section 3.1.5)

The `PHPickerViewControllerDelegate` implementation checks types in the order: movie, image, livePhoto. This is incorrect because `NSItemProvider.hasItemConformingToTypeIdentifier` for `UTType.image` will match Live Photos (since a Live Photo conforms to the image UTI hierarchy). The live photo branch will never be reached.

**Current code (lines ~296-309):**
```swift
if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
    // ...
} else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
    // This catches Live Photos too!
} else if itemProvider.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier) {
    // DEAD CODE -- never reached
}
```

**Fix:** Check `UTType.livePhoto` BEFORE `UTType.image`:
```swift
if itemProvider.hasItemConformingToTypeIdentifier(UTType.livePhoto.identifier) {
    // Handle live photo first
} else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
    // Then video
} else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
    // Then image
}
```

#### CRITICAL-2: MediaAsset is @immutable But Design Adds Mutable Fields Without copyWith Updates (Section 15.1)

The existing `MediaAsset` class (at `/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/models/media_asset.dart`) is `@immutable` and has a `copyWith` method with named parameters for every existing field. The design proposes adding 8 new fields (`isFavorite`, `colorTags`, `textTags`, `colorSpace`, `bitDepth`, `creationDate`, `locationISO6709`, `thumbnailPath`, `importSource`) but does not update:

1. The `copyWith` method to include these new fields
2. The `toJson` / `fromJson` serialization to handle these new fields
3. The constructor to accept them

Without these updates, favorites and tags cannot be toggled (since the object is immutable -- you must create a copy with the new value). The design must explicitly specify the full updated `copyWith`, `toJson`, and `fromJson` signatures or risk incomplete implementation.

**Additionally:** `colorTags` is `List<TagColor>` which is mutable by default. For an `@immutable` class, this must be `List.unmodifiable` in the constructor, matching the pattern used by `Project.clips`.

#### CRITICAL-3: Registry Persistence Race Condition -- No Locking or Debounce Implementation (Section 15.2)

The design mentions "debounced" save in Section 18.3 ("Registry save debounce: After any mutation, debounce registry save by 2 seconds") but the actual `saveToDisk` implementation in Section 15.2 is a bare `Future<void>` with no debounce logic. During batch import of, say, 20 files, `notifyListeners()` is called on every `register()` call. If each listener triggers `saveToDisk()`, you get 20 concurrent writes to the same file.

**Required additions:**
1. A `Timer`-based debounce mechanism in `saveToDisk` (or a wrapper method `scheduleSave`)
2. A `Completer`-based lock to prevent concurrent writes
3. A `_dirty` flag to skip unnecessary saves
4. Call `saveToDisk` on app lifecycle events (`AppLifecycleState.paused`) for data safety

The atomic write via temp file rename is good, but concurrent renames can still corrupt data.

---

### IMPORTANT Issues

#### IMPORTANT-1: UIDocumentPickerViewController `asCopy: false` Requires Careful Handling (Section 4.1.4)

The design uses `asCopy: false` with the comment "We'll copy ourselves for progress tracking." This is technically correct but has an important implication: the returned URLs are security-scoped and may become invalid if the user modifies the file in the source location during copy. Also, `asCopy: false` means the picker returns the original file URL, not a copy -- if the source is a cloud provider, iOS may need to download the file first, and the download is NOT under your control (no progress reporting from the system).

**Recommendation:** Consider using `asCopy: true` for small files (under 100MB) where progress reporting is not essential, and `asCopy: false` only for large files where you need explicit control. Alternatively, document the trade-off and accept that progress reporting for Files app imports from cloud providers will be limited to an indeterminate spinner.

#### IMPORTANT-2: Project Model Backward Compatibility Strategy is Incomplete (Section 15.3)

The design adds `mediaAssetIds` to `Project` but the migration strategy is vague: "Existing projects with sourceVideoPath will be migrated to reference a MediaAsset in the registry. The sourceVideoPath field is kept for backward compatibility."

The existing `Project.fromJson` (at line 378 of `project.dart`) does not handle `mediaAssetIds`. The migration needs explicit answers:

1. **When does migration happen?** At app launch? When a project is opened? Lazily?
2. **What if the registry has not loaded yet?** The legacy migration (Section 13.2) moves files and creates MediaAssets, but what if a user opens a project before migration completes?
3. **What about `TimelineClip.sourceVideoPath`?** Each clip has its own `sourceVideoPath` field (see `timeline_clip.dart`). These also need migration to reference MediaAsset IDs.
4. **Version bump?** The current `Project.version` is 2 (for multi-clip). Should this become version 3? The `fromJson` needs version-aware parsing.

#### IMPORTANT-3: Background Import Continuation is Insufficient (Section 5.6 / 17.2)

The design says "Request background task via BGTaskRequest" for app backgrounded during import, but `BGTaskRequest` is for scheduled background work (like periodic fetches), NOT for continuing active foreground work. The correct API is:

```swift
UIApplication.shared.beginBackgroundTask { /* expiration handler */ }
```

This gives approximately 30 seconds of execution time, which is stated in the doc but the API reference is wrong. `BGTaskRequest` would be used for scheduling a cleanup/verification task on next launch, not for continuing an import.

**Recommendation:** Use `UIApplication.beginBackgroundTask` for short continuation, and implement a proper resume mechanism for long imports that cannot complete in 30s (persist queue state, resume on foreground).

#### IMPORTANT-4: `extractMetadata` Uses Deprecated `asset.tracks(withMediaType:)` (Section 9.3)

The native metadata extraction code uses the synchronous `asset.tracks(withMediaType: .video)` which is deprecated since iOS 15. The modern API is:

```swift
let tracks = try await asset.loadTracks(withMediaType: .video)
```

Since the app targets iOS 14+ (per PHPicker usage), you need a runtime check:

```swift
if #available(iOS 15.0, *) {
    let tracks = try await asset.loadTracks(withMediaType: .video)
    // ...
} else {
    let tracks = asset.tracks(withMediaType: .video)
    // ...
}
```

This also applies to `videoTrack.naturalSize`, `videoTrack.preferredTransform`, `videoTrack.nominalFrameRate`, and `videoTrack.formatDescriptions` which all have async `load(.property)` replacements in iOS 15+.

#### IMPORTANT-5: No Audio Import Pipeline for Images and Audio-Only Files (Section 5.2)

The import pipeline step 5 says "Extract via native platform channel (AVAsset inspection)" but `AVAsset` cannot extract metadata from still images (JPEG, PNG, HEIC). For images, you need `CGImageSource` or `UIImage` APIs:

```swift
// For images:
let source = CGImageSourceCreateWithURL(url as CFURL, nil)
let properties = CGImageSourceCopyPropertiesAtIndex(source!, 0, nil) as? [String: Any]
// Read kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyExifDictionary, etc.
```

The design should specify separate metadata extraction paths for each media type:
- **Video:** `AVAsset` + `AVAssetTrack` (as currently designed)
- **Image:** `CGImageSource` + `CGImageProperties` (missing from design)
- **Audio:** `AVAsset` + `AVAssetTrack` (works for audio, but different properties to extract)

#### IMPORTANT-6: `MediaTag.text` Constructor Uses `const` Incorrectly (Section 8.4)

```dart
const MediaTag.text(this.text)
    : id = 'text_$text',  // String interpolation cannot be used in const constructors
      type = MediaTagType.text,
      color = null;
```

String interpolation (`'text_$text'`) is not allowed in `const` constructors because the result is not a compile-time constant. Remove `const` or use a factory constructor.

#### IMPORTANT-7: Max File Size Overflow -- 4GB Constant Overflows 32-bit int (Section 11.2)

```dart
static const _maxDownloadSize = 4 * 1024 * 1024 * 1024;  // 4GB
```

On 32-bit Dart VMs (some iOS devices), `4 * 1024 * 1024 * 1024 = 4294967296` overflows a 32-bit signed integer (max 2,147,483,647). Use a `num` literal or explicit `int` with caution:

```dart
static const _maxDownloadSize = 4294967296;  // 4GB, explicit to avoid overflow
```

Or better yet, compare in units:
```dart
static const _maxDownloadSizeGB = 4;
// Then: if (contentLength > _maxDownloadSizeGB * 1024 * 1024 * 1024)
```

**Note:** Dart uses 64-bit integers on 64-bit platforms and arbitrary precision on the web. However, the explicit constant avoids any ambiguity.

#### IMPORTANT-8: Missing `http` Dependency for URL Import (Section 11)

The URL import feature uses `http.Client()`, `http.head()`, `http.Request()` which come from the `http` package. This dependency is not in the current `pubspec.yaml` and is only listed under Phase 4 cloud import additions. However, URL import is conceptually simpler than cloud import and might be implemented in Phase 1 or 2.

**Recommendation:** List `http` as a Phase 1 dependency since it is needed for URL validation even if the full URL import is Phase 4.

---

### MINOR Issues

#### MINOR-1: Tab Bar Width Approximation (Section 7.2)

The note says "Tab bar width should increase from 220 to ~320 to accommodate three tabs." The current CNTabBar has `width: 220` for 2 tabs (110px per tab). For 3 tabs at the same density, 330 would be more exact. However, `CNTabBar` with `shrinkCentered: false` may auto-size its items. This should be tested empirically rather than guessed.

#### MINOR-2: Thumbnail Size Discrepancy (Section 12.1 vs 12.4)

Section 12.1 says "240x240pt (@2x: 480x480px)" but Section 12.4 says "240x240pt" for grid cell and then specifies "@2x" separately in the generation method. The actual generated JPEG should be 480x480px to support @2x displays. Make sure the native `AVAssetImageGenerator.maximumSize` is set to `CGSize(width: 480, height: 480)` not `CGSize(width: 240, height: 240)`.

Also consider @3x displays (iPhone Plus/Max models): 720x720px. A single 480px thumbnail downscaled to 240pt on @2x is fine, but on @3x devices it will look slightly blurry. Decide whether to generate at @3x (720px) or accept the quality trade-off.

#### MINOR-3: Camera Capture `asCopy: false` Comment in Wrong Section (Section 4.1.4)

The comment "We'll copy ourselves for progress tracking" appears in the document picker section but the rationale is about progress tracking. The actual benefit is also about getting the original file URL for security-scoped bookmark access. The comment should be updated for clarity.

#### MINOR-4: Missing `.audio` Case in `MediaImportResult` Enum (Section 3.1.5)

The `MediaImportResult` Swift enum defines `.video`, `.image`, and `.livePhoto` but no `.audio` case. However, the `importFromDocumentPicker` function (Section 4.1.2) does return `.audio`. The PHPicker can also be configured to allow audio selection. Add the `.audio` case to the enum:

```swift
enum MediaImportResult {
    case video(url: URL, assetId: String?)
    case image(url: URL, assetId: String?)
    case livePhoto(videoURL: URL, assetId: String?)
    case audio(url: URL)  // Missing from Section 3.1.5
}
```

#### MINOR-5: `CancellationToken` Already Exists in `content_hash.dart` (Section 11.3)

The URL download implementation references `CancellationToken` but does not specify that it should reuse the existing implementation from `/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/core/content_hash.dart`. The existing `CancellationToken` class should be extracted to a shared location (e.g., `lib/core/cancellation_token.dart`) rather than duplicated.

#### MINOR-6: `ImportQueueProgress` Missing `const` Constructor (Section 5.4)

`ImportQueueProgress` is marked `@immutable` but the class shown in the design has no constructor at all -- just field declarations and getters. It needs a proper constructor (and since it has computed getters referencing fields, it should be a regular constructor, not `const`):

```dart
const ImportQueueProgress({
    required this.totalFiles,
    required this.completedFiles,
    // ...
});
```

---

### QUESTIONS

#### QUESTION-1: Should the MediaAssetRegistry Be Global or Per-Project?

The design positions the registry as a global singleton (`Documents/Media/registry.json`) shared across all projects. This means:
- All imported media is visible in the Media Browser regardless of which project it belongs to
- Deleting a project does not delete its media (by design)
- Multiple projects can share the same media asset

Is this the intended behavior? The Timeline Architecture V2 design doc uses `MediaAssetRegistry` per-project (embedded in the timeline state). This design proposes a global registry. Which is the source of truth? Both approaches have merit, but they are architecturally incompatible. **This needs a decision before implementation.**

#### QUESTION-2: What Happens When the User Taps "+" on the Projects Tab?

Section 16.5 says the FAB on the Projects tab should "Show import source picker, then create project with selected media." But the current behavior (in `project_library_view.dart` line 157) directly calls `_importVideo()` which uses `image_picker` and creates a project in one flow.

The new design decouples import from project creation. So when the user taps "+" on Projects:
1. Do they first import media (if not already imported), then create a project referencing it?
2. Or do they pick existing media from the Media Browser and create a project?
3. Or is it a combined flow: pick media -> import if needed -> create project?

This user flow needs explicit documentation.

#### QUESTION-3: How Does `asCopy: false` Interact With the 4GB Size Limit?

For `UIDocumentPickerViewController` with `asCopy: false`, the returned URL points to the original file. If the file is on iCloud Drive, iOS downloads it to a temporary cache. However, the design blocks files > 4GB. Who enforces this -- your code (after getting the URL and checking size) or the system? If the user picks a 5GB ProRes file from iCloud Drive, iOS may start downloading it before your code can check the size. Consider adding the size check to the native picker delegate to fail fast.

#### QUESTION-4: What Is the Migration Strategy for `video_thumbnail` Package?

The current codebase uses the `video_thumbnail` Flutter plugin (line 59 of `pubspec.yaml`) for thumbnail generation in `_PremiumProjectCardState._loadData()`. The design proposes using native `AVAssetImageGenerator` via the platform channel for all new thumbnails. Should the `video_thumbnail` dependency be:
1. Kept for backward compatibility with existing project card thumbnails?
2. Replaced entirely with the native implementation?
3. Deprecated gradually?

This affects the dependency list and the migration plan.

#### QUESTION-5: Is the `ImageFilter.blur` in the Document Picker Section Intentional?

The Files app integration (Section 4) does not mention any blur/glass effects in its UI, but the Media Browser grid cell in Section 7.3 and the existing project card both use `BackdropFilter`. Should the Media Browser cards have the same Liquid Glass treatment as project cards? The design shows a tight photo-grid (2px spacing, Apple Photos style) which typically does NOT have glass blur per-cell. Clarify the visual style: is it a tight photo grid (no glass) or a card grid with glass effects?

---

### Validation Against Codebase

#### Confirmed Accurate
- Current import flow in `project_library_view.dart` matches Section 2.1 description exactly
- `MediaAsset` model fields match Section 2.2 accurately
- `MediaAssetRegistry` capabilities match Section 2.2
- `content_hash.dart` utilities match Section 2.3
- File storage structure matches Section 2.4
- Existing native capabilities match Section 2.5
- Dependencies in `pubspec.yaml` match Section 2.6
- Info.plist already contains all 4 required permission keys (`NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`)
- AppDelegate structure with `setupPlatformChannels` method matches the integration point described in Section 14.4
- Native code organization (subdirectories like `Tracking/`, `Timeline/`, `People/`) validates the proposed `MediaImport/` and `Camera/` subdirectory structure

#### Needs Verification
- The `PHPickerConfiguration` `preferredAssetRepresentationMode: .current` setting -- verify this actually avoids transcoding for HEVC videos. Some reports indicate iOS still transcodes in certain scenarios.
- The `String(fourCC: codecType)` initializer in the metadata extraction code -- this is not a standard Swift initializer. It would need a custom extension on `String` to convert a `FourCharCode` (UInt32) to a human-readable string.
- The `asset.metadata(forFormat: .quickTimeMetadata)` call -- verify this works for all video containers, not just QuickTime/MOV files. MP4 files may store metadata differently.

---

### Positive Highlights

1. **PHPickerViewController choice is correct** -- privacy-first, no permission needed, system-managed UI. This is the right approach for iOS 14+.
2. **Content hash deduplication strategy is well-proven** -- the existing `content_hash.dart` implementation is solid and the design correctly leverages it.
3. **Security-scoped bookmark handling is correct** -- the start/copy/stop pattern in Section 4.1.2 follows Apple's recommended approach.
4. **Phased implementation plan is realistic** -- the dependency ordering is sound, and the 3-5 day estimates per phase are reasonable.
5. **Edge case coverage is exceptional** -- Sections 17.1-17.4 cover more edge cases than most production designs I have reviewed.
6. **Copy-to-project storage model eliminates external file dependency** -- files are self-contained after import, which is correct for a video editor.
7. **Atomic write for registry persistence** -- the temp file + rename pattern prevents corruption.
8. **The design correctly identifies and plans to deprecate `image_picker`** -- moving to native PHPicker via platform channel is the right long-term approach.

---

**Next Review:** Review 2 will focus on UI/UX compliance with iOS 26 Liquid Glass guidelines, widget selection correctness, and interaction design.

**Action Required:** Resolve CRITICAL-1, CRITICAL-2, CRITICAL-3, and QUESTION-1 before proceeding to implementation.

---

## Review 2 - Implementation Viability & Integration Risk

**Reviewer:** Claude Opus 4.6 (Senior Architect - Integration Review)
**Date:** 2026-02-06
**Scope:** Codebase verification, integration feasibility, and risk assessment for all proposed changes against the actual implementation.

---

### Codebase Verification Results

I examined every file referenced in the design document against the actual codebase. Below are the verification results organized by design section.

#### 2.1 MediaAsset Model -- VERIFIED WITH GAPS

**File:** `/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/models/media_asset.dart`

The existing `MediaAsset` class (449 lines) matches the design's Section 2.2 description accurately. All 16 fields listed in the design exist in the actual model, including `id`, `contentHash`, `relativePath`, `originalFilename`, `type`, `durationMicroseconds`, `frameRate`, `width`, `height`, `codec`, `audioSampleRate`, `audioChannels`, `fileSize`, `importedAt`, `isLinked`, `lastKnownAbsolutePath`, and `lastVerifiedAt`.

The `MediaAssetRegistry` class (lines 284-448) also matches: it has `_assetsById`, `_idByHash`, `register()`, `hasDuplicate()`, `getByHash()`, `unlinkedAssets`, and full JSON serialization. This is a solid foundation.

**Gap identified:** The design proposes adding 9 new fields to `MediaAsset` (Section 15.1), but the existing `copyWith` method at line 158 has explicit parameters for all 16 current fields. Adding 9 more fields means updating `copyWith` (9 new parameters), `toJson` (9 new entries), `fromJson` (9 new parsers), and the constructor (9 new parameters). This is straightforward but labor-intensive. R1's CRITICAL-2 correctly identified this gap.

**Risk: LOW** -- The model is well-structured, immutable, and follows established patterns. Extension is mechanical.

#### 2.2 MediaAssetRegistry -- VERIFIED WITH ARCHITECTURE CONCERN

The registry at line 284 extends `ChangeNotifier` and uses `Map<String, MediaAsset>` for ID lookup and `Map<String, String>` for hash-to-ID lookup. Both are O(1) operations.

**Architecture conflict confirmed (R1 QUESTION-1):** The existing registry is used as a per-project in-memory structure (created as part of Timeline V2 state). The design proposes making it a global singleton persisted at `Documents/Media/registry.json`. These two uses are fundamentally different:

- **V2 clips** (`/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/models/clips/video_clip.dart` line 29) reference assets via `mediaAssetId`. These clips expect the registry to contain the referenced asset.
- **The global registry** would contain ALL assets across ALL projects.
- **Per-project usage** would contain only assets used in THAT project.

**Resolution path:** The global registry should be the single source of truth. Per-project state should hold asset ID references that resolve against the global registry. The `MediaClip.mediaAssetId` field already works this way -- it is just an ID string, not a registry reference. The actual resolution happens at playback/export time via the registry. This means the global registry approach is compatible IF the registry is loaded before any project is opened, and IF the registry is a singleton accessible from timeline operations.

**Recommended implementation:** Make `MediaAssetRegistry` a singleton with `static final shared = MediaAssetRegistry()`. Load from disk at app startup. All `MediaClip` lookups resolve through `MediaAssetRegistry.shared.getById(mediaAssetId)`.

**Risk: MEDIUM** -- Requires careful initialization ordering and ensuring the registry is loaded before any project opens.

#### 2.3 Content Hash -- VERIFIED, PERFORMANCE CONFIRMED

**File:** `/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/core/content_hash.dart` (225 lines)

The `generateContentHash()` function reads exactly first 1MB + last 1MB + file size (8 bytes), totaling at most 2MB + 8 bytes of I/O per file. SHA-256 of 2MB on modern iOS hardware (A12+) completes in approximately 5-15ms. The design's target of < 200ms per file is conservative and easily achievable.

The existing `CancellationToken` class (lines 38-51) is minimal but functional. R1's MINOR-5 correctly identified it should be extracted to a shared location since the URL importer also needs it.

**Verification of dedup claim:** The hash combines file size + first 1MB + last 1MB. For two different files to produce the same hash, they would need identical size, identical first 1MB, and identical last 1MB. The probability of a false positive is astronomically low for media files (which have unique header/trailer data). This is a sound dedup strategy.

**Risk: LOW** -- Existing implementation is production-ready. No changes needed to the core hashing logic.

#### 2.4 ProjectFileService -- VERIFIED, NEEDS EXTENSION

**File:** `/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/core/project_file_service.dart` (111 lines)

The service is a singleton with cached `documentsPath` and handles three path resolution cases: relative, absolute with `/Documents/`, and other absolute. The design proposes a new storage location (`Documents/Media/` instead of `Documents/Videos/`) which means:

1. `resolveVideoFile()` works correctly for new paths since `Media/{assetId}.mov` is a relative path that resolves via Case 1.
2. The legacy migration (Section 13.2) needs to update existing `Project.sourceVideoPath` values from `Videos/{uuid}.mov` to `Media/{assetId}.{ext}`.
3. The `TimelineClip.sourceVideoPath` field (line 44 of `timeline_clip.dart`) also stores relative paths. These need migration too.

**Important finding:** There are TWO clip systems in the codebase:
- **Legacy clips** in `lib/models/timeline_clip.dart` with `sourceVideoPath: String` (path-based)
- **V2 clips** in `lib/models/clips/video_clip.dart` with `mediaAssetId: String` (ID-based)

The V2 clips are already designed for the MediaAsset registry pattern. The legacy clips are not. The migration plan in Section 15.3 must address BOTH clip systems.

**Risk: MEDIUM** -- Two clip systems with different reference mechanisms require careful dual migration.

#### 2.5 Project Model -- VERIFIED, MIGRATION COMPLEXITY HIGH

**File:** `/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/models/project.dart` (491 lines)

The `Project` model is at version 2 (multi-clip NLE). Key observations:

1. `sourceVideoPath` (line 143) is still the primary video reference for legacy single-video projects.
2. `clips` (line 156) is `List<TimelineItem>` which can contain both `TimelineClip` (legacy, path-based) and items from the V2 system (ID-based).
3. `fromJson` (line 378) handles version 1 to version 2 migration but has NO concept of version 3 or media asset IDs.
4. `toJson` (line 362) serializes `sourceVideoPath`, not `mediaAssetIds`.

The design proposes adding `mediaAssetIds: List<String>` to `Project`. This would require:
- Version bump to 3
- Updated `fromJson` with version 3 parsing
- Updated `toJson` with `mediaAssetIds`
- Updated `copyWith` with `mediaAssetIds`
- Backward compatibility: projects at version 2 must still load correctly

**Risk: HIGH** -- This is the most complex migration point. The `Project` model already went through one migration (v1 to v2). A second migration introduces combinatorial complexity (v1->v3, v2->v3). The design must specify explicit migration paths for both source versions.

#### 2.6 AppDelegate / Native Integration -- VERIFIED, INTEGRATION POINT CLEAR

**File:** `/Users/nikhilchatragadda/Personal Projects/liquid-editor/ios/Runner/AppDelegate.swift` (340 lines)

The `setupPlatformChannels(with:)` method (line 80) is the registration point for all native services. It currently registers:
- `com.liquideditor/video_processing` (method channel)
- `com.liquideditor/video_processing/progress` (event channel)
- Composition player platform view
- Tracking service
- People library channel
- Timeline V2 services (CompositionManager, DecoderPool)
- Glass FAB factory

Adding `com.liquideditor/media_import` (method channel) and `com.liquideditor/media_import/progress` (event channel) follows the exact same pattern. The `MediaImportService` would be initialized and stored as an instance variable on `AppDelegate`, same as `videoProcessingService`, `trackingService`, etc.

The native code organization already uses subdirectories (`Tracking/`, `Timeline/`, `People/`), validating the proposed `MediaImport/` and `Camera/` subdirectory structure.

**Risk: LOW** -- Clean integration point with established pattern.

#### 2.7 iOS Deployment Target -- CRITICAL DISCREPANCY

The design document states PHPickerViewController requires "iOS 14+" (Section 3.1.1, title). However, the actual app deployment target is **iOS 18.0** (verified in `project.pbxproj` lines 619, 749, 800). This means:

1. All `#available(iOS 14.0, *)` and `#available(iOS 15.0, *)` checks in the design's Swift code are UNNECESSARY -- iOS 18 is guaranteed.
2. The deprecated `asset.tracks(withMediaType:)` flagged in R1's IMPORTANT-4 can be replaced unconditionally with `try await asset.loadTracks(withMediaType:)` -- no runtime check needed.
3. All modern Swift concurrency features (async/await, structured concurrency) are available.
4. PHPickerViewController is unconditionally available.
5. `PHImageManager.requestAVAsset(forVideo:)` async variant is available.

This simplifies the native code significantly. The design should remove all iOS version conditional checks and use modern APIs directly.

**Risk: LOW (positive)** -- iOS 18 minimum means cleaner, simpler code.

#### 2.8 Existing Library View -- VERIFIED, TAB INTEGRATION FEASIBLE

**File:** `/Users/nikhilchatragadda/Personal Projects/liquid-editor/lib/views/library/project_library_view.dart` (1168 lines)

The current implementation has:
- `_currentTabIndex` state variable (line 35)
- `IndexedStack` with 2 children at line 109-115
- `CNTabBar` with 2 items at lines 123-143
- `CNButton.icon` FAB at lines 147-158 with conditional action: `_currentTabIndex == 0 ? _importVideo : _addNewPerson`

Adding a third "Media" tab requires:
1. Adding a third `CNTabBarItem` to the `CNTabBar`
2. Adding a third child to the `IndexedStack`
3. Updating the FAB's `onPressed` to handle 3 tab states
4. Widening the tab bar from 220 to ~330 (R1's MINOR-1)

The existing `_importVideo()` method (lines 484-613) uses `ImagePicker.pickVideo(source: ImageSource.gallery)` which would be replaced by the new native PHPicker-based import service. This is a direct replacement, not a parallel addition.

**Risk: LOW** -- Straightforward UI extension of established pattern.

---

### Integration Risk Assessment

#### IR-1: CRITICAL -- Two Parallel Clip Systems Create Migration Hazard

The codebase contains two distinct clip model systems:

**System A (Legacy):** `lib/models/timeline_clip.dart`
- `TimelineClip` with `sourceVideoPath: String` (relative file path)
- `TimelineGap` with duration only
- Used by `Project.clips` field
- Mutable (`orderIndex`, `sourceInPoint`, `sourceOutPoint` are mutable)

**System B (V2):** `lib/models/clips/*.dart`
- `VideoClip` extends `MediaClip` with `mediaAssetId: String` (asset ID reference)
- `ImageClip`, `AudioClip`, `GapClip`, `ColorClip`
- Immutable (`@immutable` annotation)
- Used by `PersistentTimeline` tree structure

The design assumes System B exists and uses `mediaAssetId` correctly. However, the `Project.clips` field (line 156 of `project.dart`) stores `List<TimelineItem>` from System A, not System B. The `Project.fromJson` at line 383 calls `TimelineItem.fromJson` which dispatches to `TimelineClip.fromJson` (System A), not `VideoClip.fromJson` (System B).

**Impact:** The design's assumption that clips already reference media assets by ID is only true for System B. Projects saved with System A clips still use file paths. The migration must either:
1. Convert System A clips to System B clips, OR
2. Add `mediaAssetId` to System A's `TimelineClip`, OR
3. Maintain both systems indefinitely with a bridge

**Recommendation:** Option 2 is the least disruptive for v1 of the import system. Add an optional `mediaAssetId` field to `TimelineClip` and resolve via either `mediaAssetId` (preferred) or `sourceVideoPath` (fallback). This provides backward compatibility without a full clip system migration.

#### IR-2: HIGH -- Registry Load Ordering Creates Race Condition

The proposed flow is:
1. App starts
2. `MediaAssetRegistry.shared.loadFromDisk()` (async, reads `Documents/Media/registry.json`)
3. User opens a project
4. Project clips reference `mediaAssetId`
5. Clips resolve via `MediaAssetRegistry.shared.getById(id)`

If step 3 happens before step 2 completes (e.g., user opens the app quickly and taps a project), all asset lookups will fail because the registry is empty.

**Mitigation options:**
1. **Blocking load:** Load registry synchronously during app startup splash screen. For 1000 assets, this takes ~50ms (per design's performance target), which is acceptable.
2. **Dependency gate:** Use a `Completer<void>` that gates project opening until registry is loaded.
3. **Lazy resolution:** Clips store both `mediaAssetId` and `sourceVideoPath`. If registry lookup fails, fall back to path resolution.

**Recommendation:** Option 3 is most resilient. Option 1 is simplest. I recommend implementing Option 1 with Option 3 as a safety fallback.

#### IR-3: HIGH -- `FlutterImplicitEngineBridge` UIViewController Access for Pickers

The design's PHPicker and UIDocumentPicker both require a `UIViewController` to present from:
```swift
viewController.present(picker, animated: true)
```

In the current `AppDelegate`, there is no stored reference to the root `UIViewController`. The `FlutterImplicitEngineBridge` provides access to the plugin registrar's messenger but not directly to a view controller. To present system pickers, the native service needs access to the key window's root view controller:

```swift
guard let viewController = UIApplication.shared.connectedScenes
    .compactMap({ $0 as? UIWindowScene })
    .flatMap({ $0.windows })
    .first(where: { $0.isKeyWindow })?
    .rootViewController else { return }
```

This is a common pattern but is NOT documented in the design. The design's `presentPhotoPicker(from viewController:)` assumes a view controller is passed in, but the platform channel handler does not have one readily available.

**Recommendation:** Add a utility method to `MediaImportService` that resolves the top-most presented view controller from the key window. This is standard iOS practice for plugin-presented system pickers.

#### IR-4: MEDIUM -- Event Channel Conflicts with Existing Stream Handler

The `AppDelegate` currently implements `FlutterStreamHandler` (lines 329-339) for the video processing progress event channel. The design proposes a second event channel (`com.liquideditor/media_import/progress`). Since `FlutterStreamHandler` can only handle one stream at a time per conformance, the media import event channel needs its own stream handler object.

The current architecture uses `AppDelegate` as the stream handler:
```swift
eventChannel.setStreamHandler(self)  // self = AppDelegate
```

For the media import event channel, `MediaImportService` should implement `FlutterStreamHandler` itself, not delegate to `AppDelegate`. This is already implied by the design's Section 14.4 (`mediaImportService.register(methodChannel:, eventChannel:)`) but the `MediaImportService` class in Section 3.1.5 does not show `FlutterStreamHandler` conformance.

**Risk: MEDIUM** -- Easy to fix but easy to miss.

#### IR-5: MEDIUM -- Camera PlatformView Registration Conflict Potential

The design proposes registering a `CameraCaptureViewFactory` as a platform view. The app already registers two platform views:
- `liquid_editor/composition_player` (line 100 of AppDelegate)
- `liquid_editor/composition_manager` (line 148 of AppDelegate)

Adding a third (`liquid_editor/camera_preview`) follows the same pattern and should work. However, the design does not specify the platform view ID string. Additionally, camera preview requires careful lifecycle management -- the `AVCaptureSession` must be stopped when the platform view is disposed, and restarted if the user navigates back. The design mentions this in the recording flow but does not specify the `dispose()` lifecycle handler.

**Risk: MEDIUM** -- Platform view lifecycle for camera is more complex than composition player views.

#### IR-6: LOW -- `google_sign_in` and `googleapis` Package Viability

The design proposes `google_sign_in: ^6.2.2` and `googleapis: ^13.2.0` for Google Drive integration. Both packages are actively maintained and widely used in Flutter iOS apps. `google_sign_in` uses ASWebAuthenticationSession on iOS, which is system-managed and privacy-compliant. No native code modifications needed -- the package handles everything via its own plugin registration.

However, adding `google_sign_in` requires:
1. Google Cloud Console project setup with OAuth client ID
2. `GoogleService-Info.plist` added to the iOS bundle
3. URL scheme registration in `Info.plist`

These are external setup steps not mentioned in the design's implementation plan.

**Risk: LOW** -- Well-proven packages, but requires external configuration.

---

### Critical Findings

#### CRITICAL-4: iOS Deployment Target Mismatch Simplifies But Invalidates Design Code

The design repeatedly references "iOS 14+" compatibility (Sections 3.1.1, 3.1.6, 9.3, and others) and includes `#available` runtime checks for iOS 14 and iOS 15 features. The actual deployment target is **iOS 18.0**. This means:

1. **All `#available` checks in the design are unnecessary** and should be removed for clarity.
2. **The deprecated `asset.tracks(withMediaType:)` API** (R1's IMPORTANT-4) should be replaced unconditionally with the modern async API:
   ```swift
   let tracks = try await asset.loadTracks(withMediaType: .video)
   ```
3. **All modern AVFoundation APIs are available**, including:
   - `AVAsset.load(.tracks)` (async property loading, iOS 15+)
   - `PHPickerViewController` with `PHPickerConfiguration.Selection.ordered` (iOS 15+)
   - `PHPickerViewController` ordered selection (iOS 15+)
   - `AVAssetImageGenerator.images(for:)` async sequence (iOS 16+)
   - Structured concurrency in all native code

4. The metadata extraction code in Section 9.3 should use exclusively modern async APIs:
   ```swift
   // iOS 18 -- use load() for all properties
   let tracks = try await asset.loadTracks(withMediaType: .video)
   if let videoTrack = tracks.first {
       let size = try await videoTrack.load(.naturalSize)
       let transform = try await videoTrack.load(.preferredTransform)
       let frameRate = try await videoTrack.load(.nominalFrameRate)
       let formatDescriptions = try await videoTrack.load(.formatDescriptions)
   }
   ```

This is a positive finding -- the code will be cleaner and more maintainable. But the design must be updated to reflect reality.

#### CRITICAL-5: Legacy `TimelineClip.sourceVideoPath` Is Not Addressed in Migration

The design's Section 15.3 discusses migrating `Project.sourceVideoPath` to `mediaAssetIds`, but completely misses `TimelineClip.sourceVideoPath` (line 44 of `timeline_clip.dart`). Every legacy clip stored in every project file has a `sourceVideoPath` string embedded in it. The migration must:

1. For each existing project, iterate through `clips`
2. For each `TimelineClip`, find or create the corresponding `MediaAsset` in the global registry
3. Store the `mediaAssetId` on the clip (or create a mapping)
4. Update the serialized project JSON

Without this, legacy projects will not be able to resolve their clips against the global registry. The V2 `VideoClip` already uses `mediaAssetId` and is not affected.

**Severity:** This is a data integrity issue that will cause legacy projects to fail after migration. The design must add explicit handling for `TimelineClip.sourceVideoPath` migration.

---

### Important Findings

#### IMPORTANT-9: `loadFileRepresentation(forTypeIdentifier:)` Creates a Copy -- Double Copy Issue

In the PHPicker delegate (Section 3.1.5, lines 318-345), the code calls `provider.loadFileRepresentation(forTypeIdentifier:)` which provides a temporary file URL. The design correctly notes this URL is temporary and copies it to another temp location. Then the import pipeline copies it AGAIN to `Documents/Media/`.

This means every imported file is copied TWICE:
1. PHPicker temp directory -> app temp directory (in the picker delegate)
2. App temp directory -> `Documents/Media/` (in the import pipeline)

For a 2GB ProRes video, this means 4GB of write I/O and temporarily 6GB of disk usage (original + temp copy + final copy).

**Optimization:** Use `loadFileRepresentation` but pass the temp URL directly to the import pipeline without an intermediate copy. The temp URL remains valid for the duration of the `loadFileRepresentation` callback. The import pipeline's "copy to Documents/Media/" step replaces the intermediate copy. This eliminates 2GB of unnecessary I/O.

Alternatively, use `loadInPlaceFileRepresentation(forTypeIdentifier:)` which provides the original file URL with security-scoped access (no system copy), but this is only available for on-device files (not iCloud). For iCloud assets, the double-copy is unavoidable since the system must download first.

#### IMPORTANT-10: Background Import -- `beginBackgroundTask` API Discrepancy Confirmed

R1's IMPORTANT-3 correctly identified that `BGTaskRequest` is wrong for continuing active imports. The correct API is `UIApplication.shared.beginBackgroundTask(expirationHandler:)`. However, there is an additional concern:

The current `AppDelegate` already has background task handling (lines 315-324) for background URL sessions, but does NOT use `beginBackgroundTask`. The media import service needs to call:

```swift
var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

backgroundTaskID = UIApplication.shared.beginBackgroundTask {
    // Expiration handler -- save state, stop imports
    UIApplication.shared.endBackgroundTask(backgroundTaskID)
    backgroundTaskID = .invalid
}
```

This must be called from the import queue controller when the app enters the background, and ended when the import completes or the queue is paused.

#### IMPORTANT-11: `VideoProcessingService.generateThumbnail` Generates PNG, Not JPEG

The existing thumbnail generation in `VideoProcessingService.swift` (lines 31-64) generates thumbnails as **PNG** data (`uiImage.pngData()`), falling back to JPEG only if PNG fails. The design proposes "JPEG 75%" thumbnails (Section 12.1).

This is a performance/storage discrepancy:
- PNG at 480x480: ~300KB-1MB per thumbnail
- JPEG at 480x480, 75% quality: ~30-80KB per thumbnail

For 1000 assets, this is the difference between 300MB-1GB (PNG) and 30-80MB (JPEG) of thumbnail cache. The design's 100MB estimate for 1000 thumbnails assumes JPEG.

**Recommendation:** The new `generateImportThumbnail` method should explicitly use JPEG compression at the specified quality. Do NOT reuse the existing `generateThumbnail` method without modification, as it defaults to PNG. Either create a new method or add a `format` parameter to the existing one.

#### IMPORTANT-12: Content Hash on Background Isolate vs. Main Thread

The design says content hash generation runs on a "Background Isolate" (Section 5.3). The existing `generateContentHash()` in `content_hash.dart` is a Dart `Future<String>` that performs file I/O using `dart:io`. While the `File.open()` and `RandomAccessFile.read()` calls are async, they still run on the main isolate's event loop.

For true background execution, the hash generation must be wrapped in `Isolate.run()` or `compute()`:

```dart
final hash = await Isolate.run(() => generateContentHashSync(file));
```

The synchronous variant `generateContentHashSync()` already exists at line 112 of `content_hash.dart` and is suitable for isolate execution. The async variant should NOT be used inside an isolate because `dart:io` async operations may not work correctly across isolate boundaries.

**Risk: MEDIUM** -- Using the async variant on the main isolate will not block the UI (it uses async I/O), but true isolate execution provides better guarantees during heavy batch imports.

#### IMPORTANT-13: Missing `services/` Directory in Current Codebase

The design proposes new files under `lib/services/` (Section 21.1):
- `lib/services/media_import_channel.dart`
- `lib/services/media_import_service.dart`
- `lib/services/url_importer.dart`
- `lib/services/cloud/google_drive_importer.dart`

However, the current codebase has NO `lib/services/` directory. Existing "service-like" classes live in `lib/core/` (e.g., `project_file_service.dart`, `content_hash.dart`). Creating a new top-level directory introduces an organizational inconsistency.

**Options:**
1. Place import services in `lib/core/` (consistent with existing pattern)
2. Create `lib/services/` as proposed (new organizational layer)
3. Use `lib/core/import/` subdirectory (compromise)

**Recommendation:** Option 2 is acceptable if this becomes the standard going forward, but the existing `project_file_service.dart` and `content_hash.dart` should eventually be moved there too. Option 1 avoids the inconsistency but makes `lib/core/` larger. Document the decision either way.

---

### Security-Scoped Bookmark Verification (Section 4.1.2)

The design correctly states:
1. Call `url.startAccessingSecurityScopedResource()` before reading
2. Copy the file to `Documents/Media/`
3. Call `url.stopAccessingSecurityScopedResource()` after copy
4. Do NOT store persistent bookmarks (we copy, not reference)

**Verification result:** This is CORRECT for the copy-to-local-storage model. Since files are fully copied into the app sandbox, no persistent access is needed. The `defer` block pattern in the Swift code (Section 4.1.2, lines 429-431) is the proper way to ensure `stopAccessing` is always called.

**One nuance:** The `isSecurityScoped` return value from `startAccessingSecurityScopedResource()` can be `false` for files already in the app's sandbox (e.g., files from "On My iPhone" that are in the app's own container). The design correctly checks this with `if isSecurityScoped` before calling `stopAccessing`. This is verified as correct.

---

### Cloud Import Feasibility (Section 10)

#### Google Drive Integration

The `google_sign_in: ^6.2.2` package uses ASWebAuthenticationSession on iOS 18, which presents a system-managed authentication flow. The `googleapis: ^13.2.0` package provides the `DriveApi` client for file listing and download.

**Feasibility confirmed** with caveats:
- Requires Google Cloud Console project with iOS OAuth client ID
- Requires `GoogleService-Info.plist` in the iOS bundle
- Requires URL scheme in `Info.plist` for OAuth redirect
- `drive.readonly` scope is sufficient for browsing and downloading
- File download uses `DriveApi.files.get()` with `DownloadOptions.fullMedia` which returns a `Media` stream

The design's flow (authenticate -> list files -> select -> download -> import pipeline) is standard and proven.

#### Dropbox Integration

The `flutter_appauth: ^7.0.1` package handles OAuth 2.0 PKCE flow. Dropbox's API uses standard HTTP endpoints for file listing and download.

**Feasibility confirmed** with one concern: Dropbox's content download endpoint (`https://content.dropboxapi.com/2/files/download`) returns the file content directly. For large files, this requires streaming the response body to disk rather than buffering in memory. The `http` package's `StreamedResponse` supports this.

#### iCloud Drive

Handled entirely by `UIDocumentPickerViewController` -- confirmed as no additional work needed. Third-party cloud apps (Google Drive, Dropbox, OneDrive iOS apps) automatically appear as file providers in the picker.

---

### Content Hash Performance Verification

**Test scenario:** 4GB ProRes video file

The `generateContentHash()` function reads:
- 8 bytes (file size as big-endian int64)
- 1MB (first chunk)
- 1MB (last chunk, since 4GB > 2MB threshold)
- Total I/O: 2,000,008 bytes

On iPhone 12+ (NVMe storage with ~2GB/s sequential read), reading 2MB takes approximately 1ms. SHA-256 hashing 2MB on A14+ chip takes approximately 3-5ms. Total: approximately 4-6ms.

The design's target of < 200ms is extremely conservative. Actual performance will be 5-10ms per file, even for the largest files.

**For batch imports of 20 files:** Total hash time approximately 100-200ms (sequential). With 3 concurrent isolates, approximately 40-70ms wall clock time. This is excellent.

**Collision risk assessment:** For the hash to produce a false duplicate, two files would need:
1. Same file size (exact byte count)
2. Same first 1MB content
3. Same last 1MB content

For media files (video, image, audio), this is effectively impossible because:
- Video files have unique container headers (atom sizes, timestamps)
- The last 1MB contains unique frame data or container trailer
- Even re-encoded copies differ in byte content

**Verdict:** The hashing strategy is sound for duplicate detection in a media editor context.

---

### Storage Impact Verification

**Scenario: Heavy user with 500 imported assets**

| Component | Per-Asset | 500 Assets | Notes |
|-----------|-----------|------------|-------|
| Video files (avg 200MB) | 200 MB | ~100 GB | Only ~50 videos realistically |
| Photo files (avg 5MB) | 5 MB | ~1 GB | ~200 photos |
| Audio files (avg 10MB) | 10 MB | ~250 MB | ~25 audio files |
| Thumbnails (JPEG 75%) | 50 KB | 25 MB | 480x480 JPEG |
| Registry JSON | ~500 bytes | 250 KB | Metadata only |
| Tag index | ~100 bytes | 50 KB | Tag names only |

**Total metadata overhead:** ~25.3 MB (thumbnails + registry + tags)
**User content:** Dominated by video files, as expected

**Device storage concern:** A user with 50 imported videos at 200MB average uses ~10GB. The design's 4GB per-file limit and the "storage usage display" (Section 13.4) are appropriate safeguards.

The design should add a **storage check BEFORE import** to verify sufficient space:
```dart
final requiredSpace = fileSize * 1.1; // 10% overhead for temp + thumbnail
final availableSpace = await getAvailableStorage();
if (availableSpace < requiredSpace) {
  throw ImportError.insufficientStorage(needed: requiredSpace, available: availableSpace);
}
```

The `getStorageInfo` platform channel method (Section 14.1) provides this data, but the pre-import check is not explicitly called in the pipeline steps (Section 5.2). It should be added as Step 0 or incorporated into Step 1 (Validate).

---

### Action Items for Review 3

Review 3 should focus on **UI/UX compliance with iOS 26 Liquid Glass guidelines** and address the following items from Reviews 1 and 2:

| ID | Priority | Item | Owner |
|----|----------|------|-------|
| **R1-CRITICAL-1** | P0 | Fix Live Photo type check ordering in PHPicker delegate | Design Author |
| **R1-CRITICAL-2** | P0 | Specify full `copyWith`, `toJson`, `fromJson` for new MediaAsset fields | Design Author |
| **R1-CRITICAL-3** | P0 | Add debounce/locking implementation for registry persistence | Design Author |
| **R2-CRITICAL-4** | P0 | Remove all iOS 14/15 availability checks, use iOS 18+ APIs unconditionally | Design Author |
| **R2-CRITICAL-5** | P0 | Add `TimelineClip.sourceVideoPath` migration to design | Design Author |
| **R2-IR-1** | P0 | Decide on clip system unification strategy (System A vs System B) | Architecture Decision |
| **R2-IR-2** | P1 | Define registry load ordering and fallback strategy | Design Author |
| **R2-IR-3** | P1 | Document UIViewController resolution for picker presentation | Design Author |
| **R1-IMPORTANT-2** | P1 | Complete Project model migration strategy with version 3 | Design Author |
| **R2-IMPORTANT-9** | P1 | Eliminate double-copy in PHPicker flow | Design Author |
| **R2-IMPORTANT-11** | P1 | Ensure thumbnail generation uses JPEG, not PNG | Design Author |
| **R2-IMPORTANT-12** | P1 | Specify `Isolate.run()` for content hash in batch imports | Design Author |
| **R2-IMPORTANT-13** | P2 | Decide on `lib/services/` vs `lib/core/` directory structure | Design Author |
| **R1-QUESTION-1** | P0 | Resolve global vs per-project registry (recommendation: global singleton) | Architecture Decision |
| **R1-QUESTION-2** | P1 | Document "+" FAB behavior on Projects tab (import -> create project flow) | Design Author |
| **R2-Storage** | P1 | Add pre-import storage availability check to pipeline Step 1 | Design Author |
| **R2-IR-4** | P2 | Ensure media import event channel uses separate `FlutterStreamHandler` | Design Author |
| **R2-IR-5** | P2 | Document camera platform view lifecycle (start/stop/dispose) | Design Author |
| **R2-IR-6** | P2 | Document Google Cloud Console setup requirements for cloud import | Design Author |

---

### Summary

The design is well-crafted and the underlying codebase is in excellent shape to support this feature. The V2 clip system (`lib/models/clips/`) is already built around `mediaAssetId` references, which validates the design's core approach. The main risks center around:

1. **Dual clip system migration** (System A legacy path-based vs System B ID-based) -- this is the highest-risk area
2. **Registry initialization ordering** -- solvable with a blocking load at startup
3. **iOS deployment target mismatch** -- positive finding that simplifies native code

The content hash, PHPicker, Files app, and cloud import sections are all viable and well-designed. Performance targets are achievable. Storage impact is reasonable.

**Overall viability assessment: HIGH** -- The design can be implemented as specified with the corrections noted above. No fundamental architectural blockers exist.

**Recommended next step:** Resolve the P0 action items (especially the dual clip system decision and registry scoping), then proceed to Review 3 for UI/UX compliance verification.

---

## Review 3 - Final Implementation Readiness

**Reviewer:** Claude Opus 4.6 (Senior Architect - Final Sign-off)
**Date:** 2026-02-06
**Scope:** Final review resolving all outstanding issues from R1 and R2, risk register, implementation checklist, and go/no-go decision.

---

### Critical Issues Status

All 5 critical issues from R1 and R2 are evaluated below with resolution paths and implementation guidance.

#### C1 (R1-CRITICAL-1): Live Photo Type Check Ordering Bug -- RESOLVED

**Status:** Resolution path clear, fix is trivial.

The PHPicker delegate must check `UTType.livePhoto` before `UTType.image`. The corrected order is:

1. `UTType.livePhoto` -- most specific, must come first
2. `UTType.movie` -- video files
3. `UTType.image` -- still images (catch-all)

**Implementation note:** Since iOS 18 is the deployment target, `UTType.livePhoto` is fully supported without availability checks. The implementer should add a code comment explaining why this ordering matters to prevent future regressions.

**Risk after resolution:** None.

#### C2 (R1-CRITICAL-2): MediaAsset @immutable Field Additions Without copyWith/toJson/fromJson -- RESOLVED

**Status:** Resolution path clear, mechanical work.

The 9 new fields (`isFavorite`, `colorTags`, `textTags`, `colorSpace`, `bitDepth`, `creationDate`, `locationISO6709`, `thumbnailPath`, `importSource`) require updates to:

1. **Constructor:** Add all 9 as optional named parameters with defaults (`isFavorite = false`, `colorTags = const []`, `textTags = const []`, others nullable).
2. **copyWith:** Add all 9 as optional parameters following the existing pattern (lines 158-197 of `media_asset.dart`).
3. **toJson:** Add all 9 fields. `colorTags` serialized as `List<String>` of enum names. `textTags` as `List<String>`. `creationDate` as ISO 8601. `importSource` as enum name.
4. **fromJson:** Parse all 9 with appropriate defaults for backward compatibility. Missing fields must default to `isFavorite: false`, `colorTags: []`, `textTags: []`, others `null`.
5. **Immutability:** `colorTags` and `textTags` must be `List.unmodifiable()` in the constructor body, matching the `Project.clips` pattern at line 221 of `project.dart`.

**Backward compatibility:** Existing serialized `MediaAsset` JSON (e.g., from Timeline V2 state) will not have these fields. The `fromJson` parser must handle their absence gracefully with defaults. This is verified as safe because `fromJson` already handles optional fields like `codec`, `audioSampleRate`, etc. with null defaults.

**Risk after resolution:** None. The pattern is established and well-tested.

#### C3 (R1-CRITICAL-3): Registry Persistence Race Condition -- RESOLVED

**Status:** Resolution path clear, requires careful implementation.

The debounced save mechanism must include:

1. **Timer-based debounce:** A `Timer?` field that resets on each mutation. After 2 seconds of inactivity, trigger save.
2. **In-flight write protection:** A `bool _isSaving` flag. If a save is already in progress when the timer fires, set a `_pendingSave` flag and trigger another save when the current one completes.
3. **Dirty tracking:** A `bool _isDirty` flag set on every mutation (`register`, `update`, `remove`, `updatePath`, `markUnlinked`). The `saveToDisk` method clears it after successful write.
4. **Lifecycle save:** Listen to `AppLifecycleState.paused` via `WidgetsBindingObserver` and call an immediate (non-debounced) save if `_isDirty`.
5. **Atomic write:** Already specified in the design (temp file + rename). This is correct.

```dart
// Pseudocode for the debounce mechanism
Timer? _saveTimer;
bool _isSaving = false;
bool _pendingSave = false;
bool _isDirty = false;

void _scheduleSave() {
  _isDirty = true;
  _saveTimer?.cancel();
  _saveTimer = Timer(const Duration(seconds: 2), _executeSave);
}

Future<void> _executeSave() async {
  if (_isSaving) {
    _pendingSave = true;
    return;
  }
  _isSaving = true;
  try {
    await _writeRegistryToDisk();
    _isDirty = false;
  } finally {
    _isSaving = false;
    if (_pendingSave) {
      _pendingSave = false;
      _executeSave();
    }
  }
}
```

Every mutating method in `MediaAssetRegistry` (`register`, `remove`, `update`, `updatePath`, `markUnlinked`, `clear`, `fromJson`) should call `_scheduleSave()` after `notifyListeners()`.

**Risk after resolution:** Low. The debounce pattern is standard. The atomic write prevents corruption even under concurrent access.

#### C4 (R2-CRITICAL-4): iOS Deployment Target Mismatch -- RESOLVED

**Status:** Resolution is a simplification, no new risk.

The app targets iOS 18.0. All native code in the design must:

1. **Remove all `#available(iOS 14.0, *)` and `#available(iOS 15.0, *)` checks.** These are dead code.
2. **Use modern async APIs unconditionally:**
   - `try await asset.loadTracks(withMediaType: .video)` instead of `asset.tracks(withMediaType: .video)`
   - `try await videoTrack.load(.naturalSize)` instead of `videoTrack.naturalSize`
   - `try await videoTrack.load(.preferredTransform)` instead of `videoTrack.preferredTransform`
   - `try await videoTrack.load(.nominalFrameRate)` instead of `videoTrack.nominalFrameRate`
   - `try await videoTrack.load(.formatDescriptions)` instead of `videoTrack.formatDescriptions`
3. **Use Swift structured concurrency** throughout the native import service. `DispatchQueue.global().async` can be replaced with `Task { }` and `await` for cleaner code.
4. **PHPickerConfiguration.Selection.ordered** (iOS 15+) is available and should be used for predictable import ordering.

**Risk after resolution:** Negative risk (code becomes simpler and more maintainable).

#### C5 (R2-CRITICAL-5): Legacy TimelineClip.sourceVideoPath Migration -- RESOLVED

**Status:** Resolution path defined. This is the most complex migration item.

The migration must handle `TimelineClip.sourceVideoPath` in addition to `Project.sourceVideoPath`. The recommended approach:

**Phase 1 (Minimum viable -- implement with media import system):**

1. Add an **optional** `mediaAssetId` field to `TimelineClip`:
   ```dart
   class TimelineClip extends TimelineItem {
     final String sourceVideoPath;
     final String? mediaAssetId; // NEW -- optional for backward compat
     // ...
   }
   ```
2. Update `TimelineClip.toJson` to include `mediaAssetId` when present.
3. Update `TimelineClip.fromJson` to parse `mediaAssetId` if present.
4. Resolution logic: If `mediaAssetId` is non-null, resolve via `MediaAssetRegistry.shared.getById()`. If null, fall back to `ProjectFileService.resolveVideoFile(sourceVideoPath)`.

**Phase 2 (Full migration -- can be deferred):**

5. During the legacy `Videos/` to `Media/` migration (Section 13.2), for each migrated file:
   a. Create a `MediaAsset` and register it.
   b. Update all `Project` JSON files: for each `TimelineClip` in `clips`, set `mediaAssetId` to the new asset's ID and update `sourceVideoPath` to the new relative path.
6. Bump `Project.version` to 3 for migrated projects.
7. `Project.fromJson` handles version 3: parses `mediaAssetIds` and ensures clips have `mediaAssetId` set.

**Coexistence:** During the transition period, both `sourceVideoPath` and `mediaAssetId` coexist on `TimelineClip`. The `mediaAssetId` takes precedence when present. The V2 `VideoClip` already uses `mediaAssetId` exclusively and is unaffected.

**Risk after resolution:** Medium. The dual-field approach avoids a breaking migration but introduces code complexity. The implementer must add clear documentation and a TODO for eventual cleanup.

---

### Integration Risks Resolution

The 6 integration risks from R2 are addressed below.

| IR | Risk | Severity | Resolution | Residual Risk |
|----|------|----------|------------|--------------|
| IR-1 | Dual clip system (System A path-based vs System B ID-based) | CRITICAL | Add optional `mediaAssetId` to `TimelineClip` (System A). Do NOT attempt full unification in this feature. System B is forward-compatible and needs no changes. | Medium -- technical debt accumulates. Schedule System A deprecation for a future release. |
| IR-2 | Registry load ordering race condition | HIGH | **Blocking load at app startup.** The registry loads in < 50ms for 1000 assets. Add the load call in `main()` or the splash screen's `initState` before any navigation is possible. Add fallback: if `getById()` returns null, attempt `ProjectFileService.resolveVideoFile()` as backup. | Low -- blocking load is fast, fallback is safe. |
| IR-3 | UIViewController access for pickers | HIGH | Add a utility method to `MediaImportService.swift`: `private var topViewController: UIViewController?` that resolves via `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController` and walks the presentation chain to find the topmost presented controller. This is standard iOS practice. | Low -- well-established pattern. |
| IR-4 | Event channel stream handler conflict | MEDIUM | `MediaImportService` must implement `FlutterStreamHandler` itself with its own `EventSink`. Do NOT use `AppDelegate` as the stream handler for the import channel. Register via `eventChannel.setStreamHandler(mediaImportService)`. | Low -- straightforward. |
| IR-5 | Camera PlatformView lifecycle | MEDIUM | Register with ID `liquid_editor/camera_preview`. Implement `dispose()` on the native view to stop `AVCaptureSession`. Implement `onFlutterViewAppeared` / `onFlutterViewDisappeared` for background/foreground transitions. Stop session on `dispose()` and when the Flutter view disappears; restart on reappear. | Medium -- camera lifecycle is inherently complex, but the pattern is established with the composition player. |
| IR-6 | Google Cloud Console setup for Drive integration | LOW | Defer to Phase 4. Document the setup requirements (OAuth client ID, `GoogleService-Info.plist`, URL scheme) in the Phase 4 task description. This is external configuration, not code. | Low -- Phase 4 is lowest priority. |

---

### Registry Architecture Decision: GLOBAL SINGLETON

**Decision:** The `MediaAssetRegistry` is a **global singleton** shared across all projects.

**Rationale:**

1. The V2 `VideoClip.mediaAssetId` is already a plain string ID with no embedded registry reference. It resolves against whatever registry is available at runtime.
2. A per-project registry would require duplicating assets that appear in multiple projects, defeating the dedup strategy.
3. The Media Browser (Section 7) inherently requires a global view of all assets.
4. The existing `MediaAssetRegistry` class already works as a singleton -- it just needs `static final shared = MediaAssetRegistry()` and `loadFromDisk()` / `saveToDisk()` methods.

**Implementation:**
```dart
class MediaAssetRegistry extends ChangeNotifier {
  static final shared = MediaAssetRegistry._();
  MediaAssetRegistry._();
  // ... existing methods unchanged ...
  // ADD: loadFromDisk(), saveToDisk() with debounce
}
```

**App startup sequence:**
1. `main()` calls `WidgetsFlutterBinding.ensureInitialized()`
2. `await MediaAssetRegistry.shared.loadFromDisk()` -- blocking, < 50ms
3. `runApp(LiquidEditorApp())`

This guarantees the registry is loaded before any widget builds.

---

### Legacy Migration Path

The migration from `Videos/` to `Media/` is a one-time operation. The complete sequence:

1. **Detection:** Check if `Documents/Videos/` exists and has `.mov` or `.mp4` files.
2. **Per-file migration:**
   a. Generate content hash via `generateContentHashSync()` (in isolate for large files).
   b. Extract metadata via native platform channel `extractMetadata`.
   c. Generate thumbnail via native platform channel `generateImportThumbnail`.
   d. Create `MediaAsset` with all extracted data.
   e. Move (not copy) file from `Documents/Videos/{uuid}.ext` to `Documents/Media/{assetId}.ext`.
   f. Register asset in `MediaAssetRegistry.shared`.
3. **Project update:** For each `Project` JSON in `Documents/Projects/`:
   a. Load project.
   b. Update `sourceVideoPath` from `Videos/{uuid}.ext` to `Media/{assetId}.ext`.
   c. For each `TimelineClip` in `clips`, update `sourceVideoPath` and set `mediaAssetId`.
   d. Bump `version` to 3.
   e. Save project.
4. **Cleanup:** Delete `Documents/Videos/` if empty.
5. **Persist:** Call `MediaAssetRegistry.shared.saveToDisk()`.

**Error handling:** If any single file fails migration, skip it and leave it in `Videos/`. The fallback path resolution in `ProjectFileService` will still find it. Log the error for later manual resolution.

**Timing:** Run migration on first launch after update. Show a brief "Migrating library..." indicator if there are > 5 files. For typical users (1-3 projects), migration completes in < 1 second.

---

### Risk Register

| ID | Risk | Probability | Impact | Severity | Mitigation | Owner |
|----|------|-------------|--------|----------|------------|-------|
| R1 | Dual clip system creates maintenance burden | High | Medium | **HIGH** | Add `mediaAssetId` to `TimelineClip` now; schedule full System A deprecation for Q2 2026 | Architecture |
| R2 | Registry corruption from power loss during save | Low | High | **MEDIUM** | Atomic write via temp file + rename already in design. Add SHA-256 checksum header to `registry.json` for corruption detection on load. | Implementation |
| R3 | Legacy migration fails silently, leaves orphaned files | Medium | Medium | **MEDIUM** | Migration produces a structured report (`Documents/Media/migration_log.json`) with per-file status. Verify all projects load after migration before deleting `Videos/`. | Implementation |
| R4 | Large file import (> 1GB) causes memory spike | Medium | Medium | **MEDIUM** | File copy uses `File.copy()` (kernel-level, zero-copy). Content hash reads max 2MB. Thumbnail generation is native (separate memory space). Cap concurrent imports at 3. | Design (already addressed) |
| R5 | PHPicker returns iCloud asset that fails to download | Medium | Low | **LOW** | Design already covers this with per-asset retry/skip (Section 3.1.3). Implement 60s timeout with user-facing "Retry" / "Skip" buttons. | Implementation |
| R6 | Camera AVCaptureSession conflicts with composition player | Low | Medium | **LOW** | Never present camera capture while a project is open in the editor. Add `assert` that composition player is not active when camera session starts. | Implementation |
| R7 | `google_sign_in` OAuth setup misconfigured | Medium | Low | **LOW** | Phase 4 only. Add integration test that verifies Google Sign-In flow on CI. Document setup steps in Phase 4 task. | Phase 4 Owner |
| R8 | Thumbnail cache grows unbounded over time | Low | Low | **LOW** | Thumbnails are only generated at import and deleted with the asset. For 1000 assets, cache is ~50MB. Add a "Clear thumbnail cache" option in Settings (regenerates on demand). | Implementation |
| R9 | `TimelineItem` class name collision between System A (`timeline_clip.dart`) and System B (`clips/timeline_item.dart`) | High | High | **HIGH** | Both classes are named `TimelineItem`. They MUST be imported with prefixes or one must be renamed. Recommendation: Rename System A's `TimelineItem` to `LegacyTimelineItem` in a preparatory PR BEFORE this feature. | Architecture (pre-work) |

---

### Implementation Checklist

Ordered by dependency. Each item lists the file(s) to create or modify and any blocking dependencies.

#### Pre-work (Before Phase 1)

| # | Task | Files | Dependencies | Est. |
|---|------|-------|-------------|------|
| 0.1 | Rename System A `TimelineItem` to `LegacyTimelineItem` to resolve class name collision | `lib/models/timeline_clip.dart`, `lib/models/project.dart`, all files importing `timeline_clip.dart` | None | 0.5 day |
| 0.2 | Extract `CancellationToken` to shared location | `lib/core/cancellation_token.dart` (new), update `lib/core/content_hash.dart` | None | 0.25 day |

#### Phase 1: Foundation (3-5 days)

| # | Task | Files | Dependencies | Est. |
|---|------|-------|-------------|------|
| 1.1 | Extend `MediaAsset` with 9 new fields + updated `copyWith`/`toJson`/`fromJson` | `lib/models/media_asset.dart` | None | 0.5 day |
| 1.2 | Create `MediaTag` model | `lib/models/media_tag.dart` (new) | None | 0.25 day |
| 1.3 | Add registry persistence (`loadFromDisk`, `saveToDisk` with debounce, singleton pattern) | `lib/models/media_asset.dart` | 1.1 | 0.5 day |
| 1.4 | Add `mediaAssetId` to `TimelineClip` with fallback resolution | `lib/models/timeline_clip.dart` | 0.1, 1.3 | 0.5 day |
| 1.5 | Create `MediaImportService.swift` (PHPicker + UIDocumentPicker + metadata extraction) | `ios/Runner/MediaImport/MediaImportService.swift` (new) | None | 1 day |
| 1.6 | Create `MediaImportMethodChannel.swift` (platform channel handler) | `ios/Runner/MediaImport/MediaImportMethodChannel.swift` (new) | 1.5 | 0.5 day |
| 1.7 | Register channels in `AppDelegate.setupPlatformChannels` | `ios/Runner/AppDelegate.swift` | 1.6 | 0.25 day |
| 1.8 | Create `MediaImportChannel` (Dart platform channel wrapper) | `lib/services/media_import_channel.dart` (new) | 1.7 | 0.25 day |
| 1.9 | Create `ImportQueueController` | `lib/core/import_queue_controller.dart` (new) | 1.8, 1.3 | 0.5 day |
| 1.10 | Create `MediaImportService` (Dart orchestrator) | `lib/services/media_import_service.dart` (new) | 1.8, 1.9, 1.3 | 0.5 day |
| 1.11 | Create `MediaMigrationService` (Videos/ to Media/) | `lib/core/media_migration.dart` (new) | 1.3, 1.4, 1.10 | 0.5 day |
| 1.12 | Update `_importVideo()` in project library to use new pipeline | `lib/views/library/project_library_view.dart` | 1.10 | 0.5 day |
| 1.13 | Add registry load to app startup | `lib/main.dart` | 1.3 | 0.25 day |
| 1.14 | Unit tests for Phase 1 | `test/models/media_asset_extended_test.dart`, `test/core/import_queue_test.dart`, `test/core/media_migration_test.dart` | 1.1-1.11 | 1 day |

#### Phase 2: Media Browser + UI (3-4 days)

| # | Task | Files | Dependencies | Est. |
|---|------|-------|-------------|------|
| 2.1 | Add "Media" tab to Project Library (3-tab CNTabBar, IndexedStack update) | `lib/views/library/project_library_view.dart` | Phase 1 | 0.5 day |
| 2.2 | Create `MediaBrowserView` (grid view with lazy thumbnails) | `lib/views/library/media_browser_view.dart` (new) | 2.1 | 1 day |
| 2.3 | Create `MediaThumbnailWidget` | `lib/views/library/media_thumbnail_widget.dart` (new) | 2.2 | 0.25 day |
| 2.4 | Add JPEG thumbnail generation to native import service | `ios/Runner/MediaImport/MediaImportService.swift` | 1.5 | 0.25 day |
| 2.5 | Create `MediaDetailSheet` (metadata display) | `lib/views/library/media_detail_sheet.dart` (new) | 2.2 | 0.5 day |
| 2.6 | Context menu actions (info, favorite, tag, delete) | `lib/views/library/media_browser_view.dart` | 2.2, 2.5 | 0.5 day |
| 2.7 | Search and filter bar | `lib/views/library/media_browser_view.dart` | 2.2 | 0.5 day |
| 2.8 | Sort options | `lib/views/library/media_browser_view.dart` | 2.2 | 0.25 day |
| 2.9 | Import progress sheet | `lib/views/library/import_progress_sheet.dart` (new) | 1.9 | 0.5 day |
| 2.10 | Import source picker (CupertinoActionSheet) | `lib/views/library/import_source_sheet.dart` (new) | 1.10 | 0.25 day |
| 2.11 | Widget and integration tests for Phase 2 | `test/views/media_browser_test.dart`, `test/views/media_detail_sheet_test.dart` | 2.1-2.10 | 1 day |

#### Phase 3: Camera Capture (3-4 days)

| # | Task | Files | Dependencies | Est. |
|---|------|-------|-------------|------|
| 3.1 | Create `CameraCaptureService.swift` (AVCaptureSession, recording) | `ios/Runner/Camera/CameraCaptureService.swift` (new) | None | 1.5 days |
| 3.2 | Create `CameraCaptureViewFactory.swift` (PlatformView) | `ios/Runner/Camera/CameraCaptureViewFactory.swift` (new) | 3.1 | 0.5 day |
| 3.3 | Register camera platform view in AppDelegate | `ios/Runner/AppDelegate.swift` | 3.2 | 0.25 day |
| 3.4 | Create `CameraCaptureView` (Flutter UI chrome) | `lib/views/camera/camera_capture_view.dart` (new) | 3.3 | 0.5 day |
| 3.5 | Camera settings sheet (resolution, fps, flash) | `lib/views/camera/camera_settings_sheet.dart` (new) | 3.4 | 0.25 day |
| 3.6 | Auto-import recorded clip into registry | `lib/views/camera/camera_capture_view.dart` | 3.4, 1.10 | 0.25 day |
| 3.7 | Permission handling (camera, microphone) | `lib/views/camera/camera_capture_view.dart` | 3.4 | 0.25 day |
| 3.8 | Tests for camera integration | `test/camera/camera_capture_test.dart` | 3.4-3.7 | 0.5 day |

#### Phase 4: Tags, Cloud, Polish (3-4 days)

| # | Task | Files | Dependencies | Est. |
|---|------|-------|-------------|------|
| 4.1 | Favorite toggle with persistence | `lib/models/media_asset.dart`, `lib/views/library/media_browser_view.dart` | Phase 2 | 0.25 day |
| 4.2 | Color tag picker sheet | `lib/views/library/tag_picker_sheet.dart` (new) | Phase 2 | 0.5 day |
| 4.3 | Custom text tag input with autocomplete | `lib/views/library/tag_picker_sheet.dart` | 4.2 | 0.5 day |
| 4.4 | Tag filtering in Media Browser | `lib/views/library/media_browser_view.dart` | 4.2, 4.3 | 0.25 day |
| 4.5 | Global tag index persistence | `lib/models/media_tag_index.dart` (new) | 4.3 | 0.25 day |
| 4.6 | URL import | `lib/services/url_importer.dart` (new) | Phase 1 | 0.5 day |
| 4.7 | Google Drive import (requires Cloud Console setup) | `lib/services/cloud/google_drive_importer.dart` (new) | Phase 1 | 1 day |
| 4.8 | Storage usage display | `lib/views/settings/storage_usage_view.dart` (new) | Phase 2 | 0.25 day |
| 4.9 | Unused media cleanup | `lib/core/media_cleanup.dart` (new) | Phase 2 | 0.5 day |
| 4.10 | Tests for Phase 4 | Various | 4.1-4.9 | 0.5 day |

---

### Test Plan Verification

The test plan from Section 22 is evaluated against the implementation checklist.

| Test Category | Coverage | Gaps | Assessment |
|---------------|----------|------|------------|
| **Unit Tests** | MediaAsset extension, MediaTag, ImportQueueController, MediaMigration, MediaImportService, URLImporter | Missing: `CancellationToken` extraction test, registry persistence debounce test, `TimelineClip.mediaAssetId` resolution test | Needs 3 additional test files |
| **Widget Tests** | MediaBrowser, MediaThumbnail, MediaDetailSheet, ImportProgressSheet, TagPicker | Missing: Import source picker test, 3-tab CNTabBar integration test | Needs 2 additional test files |
| **Integration Tests** | Single import, batch import, dedup, backgrounding, large file, corruption, search/filter, favorites, tags, legacy migration | Missing: Registry race condition test (concurrent writes), camera-to-import pipeline test | Needs 2 additional scenarios |
| **Performance Tests** | Thumbnail speed, import throughput, browser scroll FPS, search latency, registry serialization | Missing: Content hash throughput on isolate vs main thread comparison, migration speed for large libraries (50+ projects) | Needs 2 additional benchmarks |

**Additional required tests:**

1. `test/core/cancellation_token_test.dart` -- Verify shared CancellationToken works across import and hash contexts.
2. `test/models/media_asset_registry_persistence_test.dart` -- Verify debounce behavior: N rapid mutations produce at most 1-2 disk writes.
3. `test/models/timeline_clip_asset_resolution_test.dart` -- Verify `mediaAssetId` takes precedence over `sourceVideoPath`; verify fallback when registry lookup fails.
4. `test/views/import_source_sheet_test.dart` -- Verify all 5 import sources are displayed; verify correct callback invocation per source.
5. `test/views/project_library_tabs_test.dart` -- Verify 3-tab layout renders correctly; verify FAB action changes per tab.

---

### Remaining Open Questions

#### Q1 (from R1-QUESTION-2): "+" FAB Behavior on Projects Tab -- NEEDS OWNER DECISION

The design decouples media import from project creation, but the Projects tab FAB still needs a defined flow. Two viable options:

**Option A -- Import-then-create (recommended for v1):**
1. User taps "+" on Projects tab
2. Same import source picker appears (Photo Library / Files / Camera / URL / Cloud)
3. User selects media, import completes
4. System creates a new `Project` with the imported media as the primary asset
5. Project opens in the editor

This preserves the current single-tap-to-create UX while using the new import infrastructure.

**Option B -- Pick-from-library:**
1. User taps "+" on Projects tab
2. Media Browser opens in selection mode ("Select media for new project")
3. User picks one or more already-imported assets
4. System creates a new `Project` with selected assets

This is more powerful but adds a step for new users who have not imported anything yet.

**Recommendation:** Implement Option A for v1 (matches current UX). Add Option B as a secondary option ("Create from Library") in a future release.

#### Q2 (from R1-QUESTION-5): Media Browser Visual Style -- NEEDS DESIGN DECISION

The Media Browser should use a **tight photo grid** (2px spacing, no glass blur per cell) for the default grid view, matching Apple Photos. The Liquid Glass treatment applies to:
- The navigation bar (`CupertinoSliverNavigationBar`)
- The search bar
- The filter chips (glass pill background)
- The context menu (system `CupertinoContextMenu`)
- The detail sheet background

Individual grid cells should be plain thumbnails with minimal overlays (duration badge, favorite heart) for maximum information density.

#### Q3: `lib/services/` Directory -- RECOMMENDATION

Create `lib/services/` as proposed. This is the correct long-term organizational structure:
- `lib/core/` -- Pure logic, data structures, utilities (no I/O, no Flutter dependencies)
- `lib/services/` -- I/O services, platform channels, network, file system
- `lib/models/` -- Data models (no I/O)
- `lib/views/` -- UI widgets

Defer moving existing `lib/core/project_file_service.dart` to `lib/services/` to avoid churn. New services go in `lib/services/`.

#### Q4: `video_thumbnail` Package Deprecation

**Recommendation:** Keep `video_thumbnail` for now. The existing `_PremiumProjectCard` uses it. New Media Browser thumbnails should use the native `generateImportThumbnail` platform channel method. After the Media Browser is complete and project cards are updated to use `MediaAsset.thumbnailPath`, remove the `video_thumbnail` dependency. This is a Phase 2 cleanup task, not a Phase 1 blocker.

---

### Dependency Additions Summary

| Phase | Package | Purpose | Notes |
|-------|---------|---------|-------|
| Phase 1 | `http: ^1.2.0` | URL import validation (HEAD requests) | Also needed for Phase 4 cloud/URL import |
| Phase 4 | `google_sign_in: ^6.2.2` | Google Drive authentication | Requires Cloud Console setup |
| Phase 4 | `googleapis: ^13.2.0` | Google Drive file API | Paired with `google_sign_in` |
| Phase 4 | `flutter_appauth: ^7.0.1` | Dropbox OAuth 2.0 PKCE | Future, can be deferred further |

No new native dependencies. All native functionality uses AVFoundation, PhotosUI, and UIKit (all system frameworks).

---

### Final Assessment: GO

**Verdict: GO with conditions.**

The Media Import & Management design is architecturally sound, technically feasible, and well-documented. All 5 critical issues have clear resolution paths. The integration risks are manageable with the mitigations described above. The phased implementation plan is realistic and properly dependency-ordered.

**Conditions for proceeding:**

1. **MUST complete Pre-work 0.1** (rename `TimelineItem` in System A) BEFORE starting Phase 1. The class name collision between `lib/models/timeline_clip.dart:TimelineItem` and `lib/models/clips/timeline_item.dart:TimelineItem` will cause import conflicts as soon as both systems are used in the same file.

2. **MUST implement C3 resolution** (debounced registry persistence) in Phase 1.3, not deferred. Without it, batch imports will corrupt the registry.

3. **MUST add pre-import storage check** (R2 storage check) to the import pipeline validation step. Without it, a user importing a 3GB file with only 2GB free will get a corrupt partial copy.

4. **MUST resolve Q1** (Projects tab FAB behavior) before Phase 1.12. Recommend Option A (import-then-create).

5. **SHOULD address IMPORTANT-9** (eliminate double-copy in PHPicker flow) in Phase 1.5. For ProRes files, the double-copy adds 2-4GB of unnecessary I/O and temporary disk usage. Pass the PHPicker temp URL directly to the import pipeline's copy step.

**What does NOT block implementation:**
- Q2 (visual style) -- Can be finalized during Phase 2 implementation.
- Q3 (directory structure) -- Organizational preference, not functional.
- Q4 (`video_thumbnail` deprecation) -- Cleanup task, no functional impact.
- Phase 4 cloud import setup -- Entirely deferred, no impact on Phases 1-3.
- System A full deprecation -- Deferred to a future release. The `mediaAssetId` bridge approach is sufficient.

**Estimated total effort:** 14-19 working days across all 4 phases, including pre-work and testing.

**Implementation order:** Pre-work (0.75 day) -> Phase 1 (5 days) -> Phase 2 (4 days) -> Phase 3 (3.5 days) -> Phase 4 (4 days). Phases 3 and 4 can be parallelized if resources allow.

---

**Sign-off: APPROVED FOR IMPLEMENTATION**

This design document, with the resolutions specified in this review, provides sufficient detail and architectural clarity to begin implementation. The implementer should treat this review's resolutions as binding amendments to the original design.
