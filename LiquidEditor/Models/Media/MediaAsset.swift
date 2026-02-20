import Foundation

// MARK: - MediaType

/// Type of media asset.
enum MediaType: String, Codable, CaseIterable, Sendable {
    /// Video file (has duration, frame rate, possibly audio).
    case video
    /// Still image (no duration inherent, displayed for configured time).
    case image
    /// Audio file (has duration, no video).
    case audio
}

// MARK: - ImportSource

/// Source of an imported media file.
enum ImportSource: String, Codable, CaseIterable, Sendable {
    /// From the iOS Photo Library via PHPicker.
    case photoLibrary
    /// From Files app via UIDocumentPicker.
    case files
    /// Captured from camera.
    case camera
    /// Downloaded from a URL.
    case url
    /// Imported from Google Drive.
    case googleDrive
    /// Imported from Dropbox.
    case dropbox
}

// MARK: - TagColor

/// Color tag for organizing media assets.
enum TagColor: String, Codable, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
}

// MARK: - MediaAsset

/// Represents an imported media asset (video, image, or audio file).
///
/// Assets are identified by UUID and can be deduplicated via content hash.
/// Clips reference assets by ID, never by file path directly.
struct MediaAsset: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Unique identifier (UUID v4).
    let id: String

    /// Content hash for duplicate detection and relinking.
    ///
    /// SHA-256 of: first 1MB + last 1MB + file size.
    let contentHash: String

    /// Relative path from project documents directory.
    let relativePath: String

    /// Original filename (for display, not path resolution).
    let originalFilename: String

    /// Media type.
    let type: MediaType

    /// Duration in microseconds (0 for images).
    let durationMicroseconds: TimeMicros

    /// Frame rate as rational number (nil for images/audio).
    let frameRate: Rational?

    /// Video/image width in pixels.
    let width: Int

    /// Video/image height in pixels.
    let height: Int

    /// Codec information (e.g., "h264", "hevc", "prores").
    let codec: String?

    /// Audio sample rate in Hz (nil for images).
    let audioSampleRate: Int?

    /// Number of audio channels (nil for images).
    let audioChannels: Int?

    /// File size in bytes.
    let fileSize: Int

    /// Timestamp when file was imported.
    let importedAt: Date

    /// Whether the file is currently accessible.
    let isLinked: Bool

    /// Last known absolute path (for relinking hints).
    let lastKnownAbsolutePath: String?

    /// Timestamp when file was last verified accessible.
    let lastVerifiedAt: Date?

    /// Whether this asset is a favorite.
    let isFavorite: Bool

    /// Color tags applied to this asset.
    let colorTags: [TagColor]

    /// Custom text tags applied to this asset.
    let textTags: [String]

    /// Color space information (SDR, HDR10, DolbyVision, HLG).
    let colorSpace: String?

    /// Bit depth (8, 10, 12).
    let bitDepth: Int?

    /// Creation date of the original media (from file metadata).
    let creationDate: Date?

    /// GPS location ISO 6709 string (if available).
    let locationISO6709: String?

    /// Thumbnail file path (relative to Documents/Media/.thumbnails/).
    let thumbnailPath: String?

    /// Source of the import.
    let importSource: ImportSource?

    init(
        id: String,
        contentHash: String,
        relativePath: String,
        originalFilename: String,
        type: MediaType,
        durationMicroseconds: TimeMicros,
        frameRate: Rational? = nil,
        width: Int,
        height: Int,
        codec: String? = nil,
        audioSampleRate: Int? = nil,
        audioChannels: Int? = nil,
        fileSize: Int,
        importedAt: Date,
        isLinked: Bool = true,
        lastKnownAbsolutePath: String? = nil,
        lastVerifiedAt: Date? = nil,
        isFavorite: Bool = false,
        colorTags: [TagColor] = [],
        textTags: [String] = [],
        colorSpace: String? = nil,
        bitDepth: Int? = nil,
        creationDate: Date? = nil,
        locationISO6709: String? = nil,
        thumbnailPath: String? = nil,
        importSource: ImportSource? = nil
    ) {
        self.id = id
        self.contentHash = contentHash
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.type = type
        self.durationMicroseconds = durationMicroseconds
        self.frameRate = frameRate
        self.width = width
        self.height = height
        self.codec = codec
        self.audioSampleRate = audioSampleRate
        self.audioChannels = audioChannels
        self.fileSize = fileSize
        self.importedAt = importedAt
        self.isLinked = isLinked
        self.lastKnownAbsolutePath = lastKnownAbsolutePath
        self.lastVerifiedAt = lastVerifiedAt
        self.isFavorite = isFavorite
        self.colorTags = colorTags
        self.textTags = textTags
        self.colorSpace = colorSpace
        self.bitDepth = bitDepth
        self.creationDate = creationDate
        self.locationISO6709 = locationISO6709
        self.thumbnailPath = thumbnailPath
        self.importSource = importSource
    }

    // MARK: - Computed Properties

    /// Aspect ratio (width / height).
    var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 1.0 }

    /// Whether this is a video asset.
    var isVideo: Bool { type == .video }

    /// Whether this is an image asset.
    var isImage: Bool { type == .image }

    /// Whether this is an audio asset.
    var isAudio: Bool { type == .audio }

    /// Whether this asset has video content.
    var hasVideo: Bool { type == .video || type == .image }

    /// Whether this asset has audio content.
    var hasAudio: Bool {
        (type == .video || type == .audio) &&
        audioChannels != nil &&
        (audioChannels ?? 0) > 0
    }

    /// Total frame count (computed from duration and frame rate).
    var frameCount: Int {
        guard let fr = frameRate, durationMicroseconds > 0 else { return 0 }
        return fr.microsecondsToFrame(durationMicroseconds)
    }

    /// Convert frame number to microseconds for this asset.
    func frameToMicroseconds(_ frame: Int) -> TimeMicros {
        guard let fr = frameRate else { return 0 }
        return fr.frameToMicroseconds(frame)
    }

    /// Convert microseconds to frame number for this asset.
    func microsecondsToFrame(_ microseconds: TimeMicros) -> Int {
        guard let fr = frameRate else { return 0 }
        return fr.microsecondsToFrame(microseconds)
    }

    /// Snap time to nearest frame boundary for this asset.
    func snapToFrame(_ microseconds: TimeMicros) -> TimeMicros {
        guard let fr = frameRate else { return microseconds }
        return fr.snapToFrame(microseconds)
    }

    // MARK: - Copy With

    /// Create a copy with updated fields.
    func with(
        id: String? = nil,
        contentHash: String? = nil,
        relativePath: String? = nil,
        originalFilename: String? = nil,
        type: MediaType? = nil,
        durationMicroseconds: TimeMicros? = nil,
        frameRate: Rational?? = nil,
        width: Int? = nil,
        height: Int? = nil,
        codec: String?? = nil,
        audioSampleRate: Int?? = nil,
        audioChannels: Int?? = nil,
        fileSize: Int? = nil,
        importedAt: Date? = nil,
        isLinked: Bool? = nil,
        lastKnownAbsolutePath: String?? = nil,
        lastVerifiedAt: Date?? = nil,
        isFavorite: Bool? = nil,
        colorTags: [TagColor]? = nil,
        textTags: [String]? = nil,
        colorSpace: String?? = nil,
        bitDepth: Int?? = nil,
        creationDate: Date?? = nil,
        locationISO6709: String?? = nil,
        thumbnailPath: String?? = nil,
        importSource: ImportSource?? = nil
    ) -> MediaAsset {
        MediaAsset(
            id: id ?? self.id,
            contentHash: contentHash ?? self.contentHash,
            relativePath: relativePath ?? self.relativePath,
            originalFilename: originalFilename ?? self.originalFilename,
            type: type ?? self.type,
            durationMicroseconds: durationMicroseconds ?? self.durationMicroseconds,
            frameRate: frameRate ?? self.frameRate,
            width: width ?? self.width,
            height: height ?? self.height,
            codec: codec ?? self.codec,
            audioSampleRate: audioSampleRate ?? self.audioSampleRate,
            audioChannels: audioChannels ?? self.audioChannels,
            fileSize: fileSize ?? self.fileSize,
            importedAt: importedAt ?? self.importedAt,
            isLinked: isLinked ?? self.isLinked,
            lastKnownAbsolutePath: lastKnownAbsolutePath ?? self.lastKnownAbsolutePath,
            lastVerifiedAt: lastVerifiedAt ?? self.lastVerifiedAt,
            isFavorite: isFavorite ?? self.isFavorite,
            colorTags: colorTags ?? self.colorTags,
            textTags: textTags ?? self.textTags,
            colorSpace: colorSpace ?? self.colorSpace,
            bitDepth: bitDepth ?? self.bitDepth,
            creationDate: creationDate ?? self.creationDate,
            locationISO6709: locationISO6709 ?? self.locationISO6709,
            thumbnailPath: thumbnailPath ?? self.thumbnailPath,
            importSource: importSource ?? self.importSource
        )
    }

    /// Mark as linked with updated path.
    func markLinked(_ newPath: String) -> MediaAsset {
        with(relativePath: newPath, isLinked: true, lastVerifiedAt: .some(Date()))
    }

    /// Mark as unlinked.
    func markUnlinked() -> MediaAsset {
        with(isLinked: false)
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: MediaAsset, rhs: MediaAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
