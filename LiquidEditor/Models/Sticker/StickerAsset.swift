import Foundation

// MARK: - StickerAssetType

/// Type of sticker asset.
///
/// SVG is intentionally excluded from V1 scope.
enum StickerAssetType: String, Codable, CaseIterable, Sendable {
    /// Static raster image (PNG with transparency).
    case staticImage

    /// Animated Lottie JSON file.
    case lottie

    /// Animated GIF.
    case gif
}

// MARK: - StickerAsset

/// Metadata about a single sticker resource (bundled or imported).
struct StickerAsset: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this sticker asset.
    let id: String

    /// Display name (e.g., "Star", "Heart", "Fire").
    let name: String

    /// Asset type.
    let type: StickerAssetType

    /// Category ID this sticker belongs to.
    let categoryId: String

    /// Path to the asset file.
    /// For bundled: relative to assets/stickers/ (e.g., "emoji/star.png").
    /// For imported: absolute path in app's documents directory.
    let assetPath: String

    /// Whether this is a bundled (built-in) sticker.
    let isBuiltIn: Bool

    /// Intrinsic width at 1080p reference resolution (logical pixels).
    /// Used to calculate default scale.
    let intrinsicWidth: Double

    /// Intrinsic height at 1080p reference resolution (logical pixels).
    let intrinsicHeight: Double

    /// For animated stickers: total animation duration in milliseconds.
    /// Nil for static stickers.
    let animationDurationMs: Int?

    /// For animated stickers: number of frames.
    /// Nil for static stickers.
    let frameCount: Int?

    /// Search keywords for this sticker.
    let keywords: [String]

    /// Preview thumbnail path (smaller version for browser grid).
    let thumbnailPath: String?

    init(
        id: String,
        name: String,
        type: StickerAssetType,
        categoryId: String,
        assetPath: String,
        isBuiltIn: Bool = true,
        intrinsicWidth: Double = 120.0,
        intrinsicHeight: Double = 120.0,
        animationDurationMs: Int? = nil,
        frameCount: Int? = nil,
        keywords: [String] = [],
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.categoryId = categoryId
        self.assetPath = assetPath
        self.isBuiltIn = isBuiltIn
        self.intrinsicWidth = intrinsicWidth
        self.intrinsicHeight = intrinsicHeight
        self.animationDurationMs = animationDurationMs
        self.frameCount = frameCount
        self.keywords = keywords
        self.thumbnailPath = thumbnailPath
    }

    /// Whether this is an animated sticker.
    var isAnimated: Bool {
        type == .lottie || type == .gif
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        name: String? = nil,
        type: StickerAssetType? = nil,
        categoryId: String? = nil,
        assetPath: String? = nil,
        isBuiltIn: Bool? = nil,
        intrinsicWidth: Double? = nil,
        intrinsicHeight: Double? = nil,
        animationDurationMs: Int?? = nil,
        frameCount: Int?? = nil,
        keywords: [String]? = nil,
        thumbnailPath: String?? = nil
    ) -> StickerAsset {
        StickerAsset(
            id: id ?? self.id,
            name: name ?? self.name,
            type: type ?? self.type,
            categoryId: categoryId ?? self.categoryId,
            assetPath: assetPath ?? self.assetPath,
            isBuiltIn: isBuiltIn ?? self.isBuiltIn,
            intrinsicWidth: intrinsicWidth ?? self.intrinsicWidth,
            intrinsicHeight: intrinsicHeight ?? self.intrinsicHeight,
            animationDurationMs: animationDurationMs ?? self.animationDurationMs,
            frameCount: frameCount ?? self.frameCount,
            keywords: keywords ?? self.keywords,
            thumbnailPath: thumbnailPath ?? self.thumbnailPath
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case categoryId
        case assetPath
        case isBuiltIn
        case intrinsicWidth
        case intrinsicHeight
        case animationDurationMs
        case frameCount
        case keywords
        case thumbnailPath
    }

    // MARK: - Equatable / Hashable by ID

    static func == (lhs: StickerAsset, rhs: StickerAsset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
