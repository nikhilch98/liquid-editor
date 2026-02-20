---
name: multi-source-video-management
description: Use when implementing multi-source video import, MediaAsset registry, content hashing, relinking, or offline media handling
---

## Multi-Source Video Management Guide

This skill guides implementation of multi-source video support in the Timeline Architecture V2, pure Swift.

### Reference Document

**Primary Design Doc:** `docs/plans/2026-01-30-timeline-architecture-v2-design.md`

Read Sections 5 (MediaAsset Registry), 11 (Data Models), and 18 (Edge Cases) before implementation.

### Architecture Overview

```
MediaImportService (actor — picker presentation + metadata + hashing)
├── PHPickerViewController (photo library import)
├── UIDocumentPickerViewController (file system import)
├── AVURLAsset metadata extraction (codec, resolution, frame rate, etc.)
├── Thumbnail generation (AVAssetImageGenerator / CGImage)
└── Content hashing (SHA-256: first 1MB + last 1MB + file size)

MediaAssetRepository (actor — persistent registry)
├── In-memory cache (Dictionary<String, MediaAsset>)
├── ContentHashIndex (content hash -> [asset IDs])
├── JSON persistence (registry.json + .index/content_hash_index.json)
└── Relinking workflow (markLinked / markUnlinked)

MediaAsset (struct: Codable, Equatable, Hashable, Sendable, Identifiable)
├── UUID identification
├── Content hash for deduplication
├── Relative path storage
├── Full metadata (resolution, frame rate, codec, color space, etc.)
└── Link status tracking
```

### File Locations

| Component | Location |
|-----------|----------|
| MediaAsset | `LiquidEditor/Models/Media/MediaAsset.swift` |
| MediaType / ImportSource / TagColor | `LiquidEditor/Models/Media/MediaAsset.swift` |
| MediaAssetRepository | `LiquidEditor/Repositories/MediaAssetRepository.swift` |
| MediaAssetRepositoryProtocol | `LiquidEditor/Repositories/Protocols/MediaAssetRepositoryProtocol.swift` |
| MediaImportService | `LiquidEditor/Services/MediaImport/MediaImportService.swift` |
| MediaImportProtocol | `LiquidEditor/Services/Protocols/MediaImportProtocol.swift` |
| Rational (frame rates) | `LiquidEditor/Models/Timeline/Rational.swift` |
| **Tests:** | |
| MediaAssetTests | `LiquidEditorTests/Models/Media/MediaAssetTests.swift` |
| MediaAssetRepositoryTests | `LiquidEditorTests/Repositories/MediaAssetRepositoryTests.swift` |

### Key Concepts

#### MediaAsset Identification

Each imported media file is uniquely identified by:
1. **UUID:** Random `String` ID for internal references
2. **Content Hash:** SHA-256 of (first 1MB + last 1MB + file size)

```swift
// Clips reference assets by ID, NEVER by file path
struct VideoClip: MediaClip {
    let mediaAssetId: String  // UUID reference to MediaAsset
    // NOT: let filePath: String  // WRONG
}
```

#### MediaAsset Model

```swift
struct MediaAsset: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String                          // UUID v4
    let contentHash: String                 // SHA-256 for dedup + relink
    let relativePath: String                // Relative to Documents dir
    let originalFilename: String            // For display only
    let type: MediaType                     // .video | .image | .audio
    let durationMicroseconds: TimeMicros    // 0 for images
    let frameRate: Rational?                // nil for images/audio
    let width: Int
    let height: Int
    let codec: String?
    let audioSampleRate: Int?
    let audioChannels: Int?
    let fileSize: Int
    let importedAt: Date
    let isLinked: Bool                      // File currently accessible
    let lastKnownAbsolutePath: String?      // Relinking hint
    let lastVerifiedAt: Date?
    let isFavorite: Bool
    let colorTags: [TagColor]
    let textTags: [String]
    let colorSpace: String?                 // SDR/HDR
    let bitDepth: Int?
    let creationDate: Date?                 // From file metadata
    let locationISO6709: String?            // GPS
    let thumbnailPath: String?
    let importSource: ImportSource?

    // Copy-with pattern for immutable updates:
    func with(relativePath: String? = nil, isLinked: Bool? = nil, ...) -> MediaAsset
    func markLinked(_ newPath: String) -> MediaAsset
    func markUnlinked() -> MediaAsset
}
```

#### Rational Frame Rates

Broadcast frame rates are rationals, not floats:

```swift
// Common broadcast rates (defined on Rational):
static let fps24 = Rational(numerator: 24, denominator: 1)
static let fps23_976 = Rational(numerator: 24000, denominator: 1001)
static let fps29_97 = Rational(numerator: 30000, denominator: 1001)
static let fps30 = Rational(numerator: 30, denominator: 1)
static let fps60 = Rational(numerator: 60, denominator: 1)

// Convert between frames and microseconds:
let frame: Int = rational.microsecondsToFrame(timeMicros)
let micros: TimeMicros = rational.frameToMicroseconds(frame)
let snapped: TimeMicros = rational.snapToFrame(timeMicros)
```

#### MediaAssetRepository (Actor-Isolated)

The repository is an `actor` that provides thread-safe CRUD for the media registry:

```swift
actor MediaAssetRepository: MediaAssetRepositoryProtocol {
    // Directory layout:
    // ~/Documents/LiquidEditor/Media/
    //   registry.json                    - Array of all MediaAsset entries
    //   .index/
    //     content_hash_index.json        - { contentHash: [assetId] }

    // Lazy-loaded in-memory cache:
    private var registryCache: [String: MediaAsset]?
    private var hashIndex: ContentHashIndex?

    // CRUD operations:
    func save(_ asset: MediaAsset) async throws
    func load(id: String) async throws -> MediaAsset
    func loadByContentHash(_ hash: String) async throws -> [MediaAsset]
    func listAll() async throws -> [MediaAsset]
    func delete(id: String) async throws
    func exists(id: String) async -> Bool
    func updateLinkStatus(assetId: String, newRelativePath: String, isLinked: Bool) async throws
    func findUnlinkedAssets() async throws -> [MediaAsset]
}
```

### Implementation Checklist

When working with multi-source video:

- [ ] All file paths stored as relative to project documents directory
- [ ] Content hash generated on import (for deduplication)
- [ ] MediaAsset registered BEFORE creating clips that reference it
- [ ] Clips reference `mediaAssetId`, never raw file paths
- [ ] Handle `isLinked = false` for offline/missing media
- [ ] Test with mixed frame rates on same timeline
- [ ] Use `actor` isolation for repository, `@MainActor` for picker presentation
- [ ] Tests use Swift Testing framework (`@Suite`, `@Test`, `#expect`)

### Import Workflow

#### From Photo Library (PHPicker)

```swift
actor MediaImportService {
    func importFromPhotos(
        mediaTypes: [String] = ["video", "image"],
        selectionLimit: Int = 0
    ) async throws -> [ImportedMedia] {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .any(of: filters)
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current
        config.selection = .ordered

        // Delegate-based picker via continuation
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoPickerDelegate(continuation: continuation)
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = delegate

            // Prevent delegate deallocation
            objc_setAssociatedObject(picker, "delegate", delegate,
                                      .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            // Present on main actor
            Task { @MainActor in
                guard let vc = Self.topViewController() else {
                    continuation.resume(throwing: MediaImportError.noViewController)
                    return
                }
                vc.present(picker, animated: true)
            }
        }
    }
}
```

#### From File System (UIDocumentPicker)

```swift
func importFromFiles(allowsMultipleSelection: Bool = true) async throws -> [ImportedMedia] {
    let supportedTypes: [UTType] = [
        .movie, .mpeg4Movie, .quickTimeMovie,
        .image, .jpeg, .png, .heic, .heif,
        .audio, .mp3, .wav, .mpeg4Audio,
    ]

    return try await withCheckedThrowingContinuation { continuation in
        let delegate = DocumentPickerDelegate(continuation: continuation)
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: supportedTypes,
            asCopy: true  // Copy into app sandbox
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = delegate
        // ... present on main actor ...
    }
}
```

#### Full Import Pipeline

```swift
// 1. User picks files -> [ImportedMedia]
let imports = try await importService.importFromPhotos()

for imported in imports {
    // 2. Compute content hash (first+last 1MB + file size)
    let hash = try await importService.computeContentHash(path: imported.url.path)

    // 3. Check for duplicate
    let existing = try await repository.loadByContentHash(hash)
    if let dupe = existing.first {
        // Reuse existing asset, skip import
        continue
    }

    // 4. Extract metadata via AVFoundation
    let metadata = try await importService.extractMetadata(path: imported.url.path)

    // 5. Generate thumbnail
    let thumbnail = try await importService.generateThumbnail(path: imported.url.path)

    // 6. Create and register asset
    let asset = MediaAsset(
        id: UUID().uuidString,
        contentHash: hash,
        relativePath: makeRelativePath(imported.url),
        originalFilename: imported.originalFilename,
        type: imported.type,
        durationMicroseconds: metadata.durationMicroseconds,
        frameRate: metadata.frameRate.map { Rational(numerator: Int($0 * 1000), denominator: 1000) },
        width: metadata.width,
        height: metadata.height,
        codec: metadata.codec,
        audioSampleRate: metadata.audioSampleRate,
        audioChannels: metadata.audioChannels,
        fileSize: metadata.fileSize,
        importedAt: Date()
    )

    try await repository.save(asset)
}
```

### Content Hashing

```swift
// SHA-256 of: first 1MB + last 1MB + file size
// Uses CommonCrypto (CC_SHA256) for performance
func computeContentHash(path: String) async throws -> String {
    let fileHandle = try FileHandle(forReadingFrom: url)
    let chunkSize = 1024 * 1024  // 1MB

    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)

    // Hash first 1MB
    let firstChunk = fileHandle.readData(ofLength: chunkSize)
    firstChunk.withUnsafeBytes { ptr in
        CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(firstChunk.count))
    }

    // Hash last 1MB if file is larger
    if fileSize > chunkSize * 2 {
        fileHandle.seek(toFileOffset: UInt64(fileSize - chunkSize))
        let lastChunk = fileHandle.readData(ofLength: chunkSize)
        lastChunk.withUnsafeBytes { ptr in
            CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(lastChunk.count))
        }
    }

    // Include file size in hash
    var size = fileSize
    withUnsafeBytes(of: &size) { ptr in
        CC_SHA256_Update(&context, ptr.baseAddress, CC_LONG(MemoryLayout<Int>.size))
    }

    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&digest, &context)
    return digest.map { String(format: "%02x", $0) }.joined()
}
```

### Offline Media Handling (CRITICAL)

#### Detecting Missing Media

```swift
// On project load, verify all assets
func verifyMediaAssets() async throws {
    let assets = try await repository.listAll()

    for asset in assets {
        let absolutePath = resolveAbsolutePath(asset.relativePath)
        if !FileManager.default.fileExists(atPath: absolutePath) {
            try await repository.updateLinkStatus(
                assetId: asset.id,
                newRelativePath: asset.relativePath,
                isLinked: false
            )
        }
    }

    let unlinked = try await repository.findUnlinkedAssets()
    if !unlinked.isEmpty {
        await showMissingMediaBanner(unlinked)
    }
}
```

#### Relinking Workflow

```swift
// User picks a replacement file
func relinkAsset(_ asset: MediaAsset, with newURL: URL) async throws -> Bool {
    // Verify content hash matches
    let newHash = try await importService.computeContentHash(path: newURL.path)

    guard newHash == asset.contentHash else {
        // Content mismatch - warn user
        return false
    }

    // Update link status
    let newRelativePath = makeRelativePath(newURL)
    try await repository.updateLinkStatus(
        assetId: asset.id,
        newRelativePath: newRelativePath,
        isLinked: true
    )

    return true
}
```

### Repository Persistence

The repository uses JSON persistence with lazy loading:

```swift
actor MediaAssetRepository {
    private let encoder: JSONEncoder  // prettyPrinted + sortedKeys + iso8601
    private let decoder: JSONDecoder  // iso8601

    // Lazy load on first access:
    private func ensureRegistryLoaded() throws -> [String: MediaAsset] {
        if let cached = registryCache { return cached }

        // Read from ~/Documents/LiquidEditor/Media/registry.json
        let data = try Data(contentsOf: registryURL)
        let assets = try decoder.decode([MediaAsset].self, from: data)
        let registry = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        registryCache = registry
        return registry
    }

    // Content hash index for O(1) dedup lookup:
    private func ensureIndexLoaded() throws -> ContentHashIndex {
        if let cached = hashIndex { return cached }
        // Read from .index/content_hash_index.json
        // Falls back to rebuilding from registry if file missing/corrupt
    }

    // Atomic writes for durability:
    private func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}
```

### UX Flows

#### Missing Media Banner

```
+-----------------------------------------------------+
| WARNING: 2 media files are missing                   |
|    Tap to locate or relink missing files             |
|                              [Locate...] [x]         |
+-----------------------------------------------------+
```

#### During Playback (Missing Clip)

```
+-----------------------------------+
|         MEDIA OFFLINE             |
|                                   |
|   beach_sunset.mov not found      |
|                                   |
|        [Locate File]              |
+-----------------------------------+
```

#### Export Validation

Before export, check all referenced assets:

```swift
func validateForExport(timeline: PersistentTimeline) async throws -> [ExportIssue] {
    var issues: [ExportIssue] = []

    for item in timeline.toList() {
        guard let mediaClip = item as? any MediaClip else { continue }

        let assetExists = await repository.exists(id: mediaClip.mediaAssetId)
        if !assetExists {
            issues.append(.missingAsset(clipId: mediaClip.id))
            continue
        }

        let asset = try await repository.load(id: mediaClip.mediaAssetId)
        if !asset.isLinked {
            issues.append(.offlineMedia(filename: asset.originalFilename))
        }
    }

    return issues
}
```

### Metadata Extraction

Uses AVFoundation for full metadata extraction:

```swift
func extractMetadata(path: String) async throws -> MediaMetadata {
    let asset = AVURLAsset(url: url)

    // Video track: size, frame rate, codec, color space
    if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let fr = try await videoTrack.load(.nominalFrameRate)
        // ... codec from formatDescriptions, HDR detection ...
    }

    // Audio track: sample rate, channels, bit depth
    if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
        // ... from CMAudioFormatDescriptionGetStreamBasicDescription ...
    }

    // Duration, file size, creation date, GPS
    let duration = try await asset.load(.duration)
    // ...
}
```

### Testing Strategy

1. **Import Tests:**
   - Same file imported twice -> reuses existing asset (content hash match)
   - Different files with same content -> detects duplicate
   - Video, image, audio file types correctly identified
   - Metadata extraction returns expected values

2. **Offline Tests:**
   - Source file deleted -> asset marked unlinked via `findUnlinkedAssets()`
   - Relink with matching file -> succeeds, `isLinked` becomes true
   - Relink with different file -> hash mismatch, returns false

3. **Repository Tests:**
   - Save and load round-trip preserves all fields
   - Content hash index stays in sync after save/delete
   - Concurrent access (actor isolation) prevents data races
   - Empty registry on first launch

```swift
import Testing

@Suite("MediaAssetRepository")
struct MediaAssetRepositoryTests {

    @Test("Save and load preserves all fields")
    func saveAndLoad() async throws {
        let repo = MediaAssetRepository(baseDirectory: tempDir)

        let asset = MediaAsset(
            id: "test-id",
            contentHash: "abc123",
            relativePath: "video.mp4",
            originalFilename: "video.mp4",
            type: .video,
            durationMicroseconds: 5_000_000,
            width: 1920, height: 1080,
            fileSize: 10_000_000,
            importedAt: Date()
        )

        try await repo.save(asset)
        let loaded = try await repo.load(id: "test-id")

        #expect(loaded.id == asset.id)
        #expect(loaded.contentHash == asset.contentHash)
        #expect(loaded.type == .video)
        #expect(loaded.durationMicroseconds == 5_000_000)
    }

    @Test("Content hash deduplication")
    func dedup() async throws {
        let repo = MediaAssetRepository(baseDirectory: tempDir)

        let asset1 = makeTestAsset(id: "a1", hash: "same-hash")
        let asset2 = makeTestAsset(id: "a2", hash: "same-hash")

        try await repo.save(asset1)
        try await repo.save(asset2)

        let matches = try await repo.loadByContentHash("same-hash")
        #expect(matches.count == 2)
    }

    @Test("Link status updates")
    func linkStatus() async throws {
        let repo = MediaAssetRepository(baseDirectory: tempDir)
        let asset = makeTestAsset(id: "a1", hash: "h1")
        try await repo.save(asset)

        try await repo.updateLinkStatus(
            assetId: "a1",
            newRelativePath: asset.relativePath,
            isLinked: false
        )

        let unlinked = try await repo.findUnlinkedAssets()
        #expect(unlinked.count == 1)
        #expect(unlinked.first?.isLinked == false)
    }
}
```

### Common Mistakes

1. **Storing absolute paths:** Always use paths relative to the project documents directory. Absolute paths break when the app is reinstalled or files are moved.
2. **Forgetting to register:** Asset must be saved to repository BEFORE creating clips that reference `mediaAssetId`.
3. **Direct file access:** Always resolve path through the repository, never hardcode paths.
4. **Ignoring frame rates:** Use `Rational` (not `Double`) for broadcast accuracy. 29.97 fps is `Rational(30000, 1001)`, not `29.97`.
5. **Skipping hash check on relink:** Could link the wrong file, causing playback artifacts.
6. **Picker delegate deallocation:** Use `objc_setAssociatedObject` to retain the delegate for the lifetime of the picker.
7. **Blocking main thread during import:** Metadata extraction, thumbnail generation, and content hashing are all async. Never call synchronously.
8. **Forgetting security-scoped resource access:** When importing from UIDocumentPicker, call `url.startAccessingSecurityScopedResource()` and `stopAccessingSecurityScopedResource()` in a `defer` block.
9. **Not copying imported files:** Files from pickers may be in temporary locations. Always copy to app sandbox before processing.
10. **Using `CryptoKit` vs `CommonCrypto`:** The current implementation uses `CommonCrypto` (CC_SHA256) for content hashing. Both work, but be consistent.

### Data Model Serialization

```json
{
  "mediaAssets": [{
    "id": "abc-123",
    "contentHash": "sha256...",
    "relativePath": "Media/video.mp4",
    "originalFilename": "beach_sunset.mov",
    "type": "video",
    "durationMicroseconds": 5000000,
    "frameRate": {"numerator": 30000, "denominator": 1001},
    "width": 1920,
    "height": 1080,
    "codec": "H.265 (HEVC)",
    "audioSampleRate": 48000,
    "audioChannels": 2,
    "fileSize": 52428800,
    "importedAt": "2026-02-13T10:30:00Z",
    "isLinked": true
  }],
  "timeline": [{
    "itemType": "video",
    "mediaAssetId": "abc-123",
    "sourceInMicros": 0,
    "sourceOutMicros": 5000000,
    "durationMicroseconds": 5000000
  }]
}
```

### Edge Cases from Review

See Section 18 of design doc for:
- EC-1: Missing source file handling (detect on load, banner UX, relink flow)
- UF-3: Multi-source import progress (batch operations, per-file status)
- UF-5: Export with missing/offline media (validate before export, block or warn)
- UT-3: Content hash accuracy vs. import speed (first+last 1MB is a trade-off)

### Verification Commands

```bash
cd "/Users/nikhilchatragadda/Personal Projects/LiquidEditor"
xcodegen generate
xcodebuild build -project LiquidEditor.xcodeproj -scheme LiquidEditor \
    -destination 'generic/platform=iOS' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme LiquidEditor \
    -destination 'platform=iOS Simulator,id=C7A15E20-CAA1-4480-B2BA-392A94328930' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO
```
