import Foundation

/// Source of a LUT file.
enum LUTSource: String, Codable, CaseIterable, Sendable {
    /// Bundled with the app.
    case bundled

    /// Imported by the user.
    case custom
}

/// Reference to a LUT file for color grading.
///
/// Supports both bundled and custom user-imported LUTs.
/// Paths use URI scheme: "bundled://category/name" or "custom://uuid".
struct LUTReference: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Display name.
    let name: String

    /// Path to the LUT file.
    let lutAssetPath: String

    /// Source type (bundled or custom).
    let source: LUTSource

    /// LUT dimension (typically 33 or 65).
    let dimension: Int

    /// Blend intensity (0.0 to 1.0, 1.0 = full strength).
    let intensity: Double

    /// Category for grouping (e.g., "cinematic", "vintage", "bw").
    let category: String?

    /// Path to a cached preview thumbnail.
    let thumbnailPath: String?

    init(
        id: String,
        name: String,
        lutAssetPath: String,
        source: LUTSource,
        dimension: Int = 33,
        intensity: Double = 1.0,
        category: String? = nil,
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lutAssetPath = lutAssetPath
        self.source = source
        self.dimension = dimension
        self.intensity = intensity
        self.category = category
        self.thumbnailPath = thumbnailPath
    }

    /// Whether this LUT is bundled with the app.
    var isBundled: Bool { source == .bundled }

    /// Whether this LUT was imported by the user.
    var isCustom: Bool { source == .custom }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        name: String? = nil,
        lutAssetPath: String? = nil,
        source: LUTSource? = nil,
        dimension: Int? = nil,
        intensity: Double? = nil,
        category: String? = nil,
        thumbnailPath: String? = nil
    ) -> LUTReference {
        LUTReference(
            id: id ?? self.id,
            name: name ?? self.name,
            lutAssetPath: lutAssetPath ?? self.lutAssetPath,
            source: source ?? self.source,
            dimension: dimension ?? self.dimension,
            intensity: intensity ?? self.intensity,
            category: category ?? self.category,
            thumbnailPath: thumbnailPath ?? self.thumbnailPath
        )
    }

    // MARK: - Equatable (identity-based)

    static func == (lhs: LUTReference, rhs: LUTReference) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
