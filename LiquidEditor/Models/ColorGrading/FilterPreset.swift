import Foundation

/// Source of a filter preset.
enum PresetSource: String, Codable, CaseIterable, Sendable {
    /// Built-in with the app.
    case builtin

    /// Created by the user.
    case user
}

/// A named color grade configuration.
///
/// Provides named color grade configurations that can be applied
/// to clips with adjustable intensity.
struct FilterPreset: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Display name.
    let name: String

    /// Optional description.
    let description: String?

    /// The complete color grade for this preset.
    let grade: ColorGrade

    /// Preset source.
    let source: PresetSource

    /// Category for grouping.
    let category: String?

    /// Thumbnail as base64 string (for user presets).
    let thumbnailBase64: String?

    /// Creation timestamp.
    let createdAt: Date

    init(
        id: String,
        name: String,
        description: String? = nil,
        grade: ColorGrade,
        source: PresetSource,
        category: String? = nil,
        thumbnailBase64: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.grade = grade
        self.source = source
        self.category = category
        self.thumbnailBase64 = thumbnailBase64
        self.createdAt = createdAt
    }

    /// Whether this is a built-in preset.
    var isBuiltin: Bool { source == .builtin }

    /// Whether this is a user-created preset.
    var isUser: Bool { source == .user }

    /// Apply this preset to a clip with given intensity.
    /// Intensity 0.0 = original grade, 1.0 = full preset.
    func applyWithIntensity(_ original: ColorGrade, intensity: Double) -> ColorGrade {
        if intensity >= 1.0 { return grade.with(id: original.id) }
        if intensity <= 0.0 { return original }
        return ColorGrade.lerp(original, grade, t: intensity)
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        name: String? = nil,
        description: String? = nil,
        grade: ColorGrade? = nil,
        source: PresetSource? = nil,
        category: String? = nil,
        thumbnailBase64: String? = nil,
        createdAt: Date? = nil
    ) -> FilterPreset {
        FilterPreset(
            id: id ?? self.id,
            name: name ?? self.name,
            description: description ?? self.description,
            grade: grade ?? self.grade,
            source: source ?? self.source,
            category: category ?? self.category,
            thumbnailBase64: thumbnailBase64 ?? self.thumbnailBase64,
            createdAt: createdAt ?? self.createdAt
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, description, grade, source, category, thumbnailBase64, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        grade = try container.decode(ColorGrade.self, forKey: .grade)

        let sourceName = try container.decodeIfPresent(String.self, forKey: .source) ?? "user"
        source = PresetSource(rawValue: sourceName) ?? .user

        category = try container.decodeIfPresent(String.self, forKey: .category)
        thumbnailBase64 = try container.decodeIfPresent(String.self, forKey: .thumbnailBase64)

        let createdAtStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtStr) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(grade, forKey: .grade)
        try container.encode(source.rawValue, forKey: .source)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(thumbnailBase64, forKey: .thumbnailBase64)

        let formatter = ISO8601DateFormatter()
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
    }

    // MARK: - Equatable (identity-based)

    static func == (lhs: FilterPreset, rhs: FilterPreset) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - BuiltinPresets

/// Provides the 15 built-in filter presets.
enum BuiltinPresets {
    private static let epoch: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }()

    private static func makeGrade(
        _ id: String,
        exposure: Double = 0.0,
        brightness: Double = 0.0,
        contrast: Double = 0.0,
        saturation: Double = 0.0,
        vibrance: Double = 0.0,
        temperature: Double = 0.0,
        tint: Double = 0.0,
        highlights: Double = 0.0,
        shadows: Double = 0.0,
        whites: Double = 0.0,
        blacks: Double = 0.0,
        sharpness: Double = 0.0,
        clarity: Double = 0.0,
        hue: Double = 0.0,
        hslShadows: HSLAdjustment = .identity,
        hslMidtones: HSLAdjustment = .identity,
        hslHighlights: HSLAdjustment = .identity,
        curveLuminance: CurveData = .identity,
        vignetteIntensity: Double = 0.0,
        vignetteRadius: Double = 1.0,
        vignetteSoftness: Double = 0.5
    ) -> ColorGrade {
        ColorGrade(
            id: id,
            exposure: exposure,
            brightness: brightness,
            contrast: contrast,
            saturation: saturation,
            vibrance: vibrance,
            temperature: temperature,
            tint: tint,
            highlights: highlights,
            shadows: shadows,
            whites: whites,
            blacks: blacks,
            sharpness: sharpness,
            clarity: clarity,
            hue: hue,
            hslShadows: hslShadows,
            hslMidtones: hslMidtones,
            hslHighlights: hslHighlights,
            curveLuminance: curveLuminance,
            vignetteIntensity: vignetteIntensity,
            vignetteRadius: vignetteRadius,
            vignetteSoftness: vignetteSoftness,
            createdAt: epoch,
            modifiedAt: epoch
        )
    }

    /// All 15 built-in presets.
    static var all: [FilterPreset] {
        [vivid, warm, cool, blackAndWhite, vintage, cinematic, faded,
         highContrast, muted, filmNoir, sunset, forest, ocean, neon, pastel]
    }

    static let vivid = FilterPreset(
        id: "builtin_vivid",
        name: "Vivid",
        description: "Boosted colors and contrast",
        grade: makeGrade("grade_vivid", contrast: 0.2, saturation: 0.35, vibrance: 0.3, clarity: 0.15),
        source: .builtin,
        category: "enhance",
        createdAt: epoch
    )

    static let warm = FilterPreset(
        id: "builtin_warm",
        name: "Warm",
        description: "Warm golden tones",
        grade: makeGrade(
            "grade_warm",
            temperature: -0.3, tint: 0.05, highlights: 0.1, shadows: 0.05,
            hslHighlights: HSLAdjustment(hue: 40.0, saturation: 0.1, luminance: 0.0)
        ),
        source: .builtin,
        category: "tone",
        createdAt: epoch
    )

    static let cool = FilterPreset(
        id: "builtin_cool",
        name: "Cool",
        description: "Cool blue tones",
        grade: makeGrade(
            "grade_cool",
            saturation: -0.1, temperature: 0.25, tint: -0.05,
            hslShadows: HSLAdjustment(hue: 220.0, saturation: 0.15, luminance: 0.0)
        ),
        source: .builtin,
        category: "tone",
        createdAt: epoch
    )

    static let blackAndWhite = FilterPreset(
        id: "builtin_bw",
        name: "B&W",
        description: "Classic black and white",
        grade: makeGrade("grade_bw", contrast: 0.15, saturation: -1.0, clarity: 0.1),
        source: .builtin,
        category: "bw",
        createdAt: epoch
    )

    static let vintage = FilterPreset(
        id: "builtin_vintage",
        name: "Vintage",
        description: "Faded film look with warm cast",
        grade: makeGrade(
            "grade_vintage",
            contrast: -0.15, saturation: -0.2, temperature: -0.15, blacks: 0.1,
            curveLuminance: CurveData(points: [
                CurvePoint(0.0, 0.05), CurvePoint(0.25, 0.28),
                CurvePoint(0.5, 0.52), CurvePoint(0.75, 0.73),
                CurvePoint(1.0, 0.95),
            ]),
            vignetteIntensity: 0.3, vignetteRadius: 0.8
        ),
        source: .builtin,
        category: "vintage",
        createdAt: epoch
    )

    static let cinematic = FilterPreset(
        id: "builtin_cinematic",
        name: "Cinematic",
        description: "Teal shadows, orange highlights",
        grade: makeGrade(
            "grade_cinematic",
            contrast: 0.1, saturation: -0.1, vibrance: 0.2, highlights: -0.1, shadows: 0.1,
            hslShadows: HSLAdjustment(hue: 200.0, saturation: 0.2, luminance: -0.05),
            hslHighlights: HSLAdjustment(hue: 35.0, saturation: 0.15, luminance: 0.0),
            vignetteIntensity: 0.2, vignetteRadius: 0.9
        ),
        source: .builtin,
        category: "cinematic",
        createdAt: epoch
    )

    static let faded = FilterPreset(
        id: "builtin_faded",
        name: "Faded",
        description: "Lifted blacks, low contrast",
        grade: makeGrade(
            "grade_faded",
            contrast: -0.2, saturation: -0.15, blacks: 0.15,
            curveLuminance: CurveData(points: [
                CurvePoint(0.0, 0.08), CurvePoint(0.5, 0.52), CurvePoint(1.0, 0.92),
            ])
        ),
        source: .builtin,
        category: "vintage",
        createdAt: epoch
    )

    static let highContrast = FilterPreset(
        id: "builtin_high_contrast",
        name: "High Contrast",
        description: "Punchy blacks and whites",
        grade: makeGrade(
            "grade_high_contrast",
            contrast: 0.4, whites: 0.1, blacks: -0.1, clarity: 0.2,
            curveLuminance: CurveData(points: [
                CurvePoint(0.0, 0.0), CurvePoint(0.25, 0.18),
                CurvePoint(0.5, 0.5), CurvePoint(0.75, 0.82),
                CurvePoint(1.0, 1.0),
            ])
        ),
        source: .builtin,
        category: "enhance",
        createdAt: epoch
    )

    static let muted = FilterPreset(
        id: "builtin_muted",
        name: "Muted",
        description: "Desaturated, soft tones",
        grade: makeGrade(
            "grade_muted",
            brightness: 0.05, contrast: -0.1, saturation: -0.35, vibrance: -0.2
        ),
        source: .builtin,
        category: "tone",
        createdAt: epoch
    )

    static let filmNoir = FilterPreset(
        id: "builtin_film_noir",
        name: "Film Noir",
        description: "High contrast monochrome with deep shadows",
        grade: makeGrade(
            "grade_film_noir",
            contrast: 0.35, saturation: -1.0, blacks: -0.1, clarity: 0.2,
            curveLuminance: CurveData(points: [
                CurvePoint(0.0, 0.0), CurvePoint(0.2, 0.1),
                CurvePoint(0.5, 0.5), CurvePoint(0.8, 0.9),
                CurvePoint(1.0, 1.0),
            ]),
            vignetteIntensity: 0.4, vignetteRadius: 0.7
        ),
        source: .builtin,
        category: "bw",
        createdAt: epoch
    )

    static let sunset = FilterPreset(
        id: "builtin_sunset",
        name: "Sunset",
        description: "Warm oranges and pinks",
        grade: makeGrade(
            "grade_sunset",
            saturation: 0.15, vibrance: 0.2, temperature: -0.4, tint: 0.1, highlights: 0.1,
            hslMidtones: HSLAdjustment(hue: 15.0, saturation: 0.1, luminance: 0.0),
            hslHighlights: HSLAdjustment(hue: 30.0, saturation: 0.2, luminance: 0.05)
        ),
        source: .builtin,
        category: "tone",
        createdAt: epoch
    )

    static let forest = FilterPreset(
        id: "builtin_forest",
        name: "Forest",
        description: "Rich greens and earthy tones",
        grade: makeGrade(
            "grade_forest",
            saturation: 0.1, vibrance: 0.15, temperature: 0.1,
            hslShadows: HSLAdjustment(hue: 160.0, saturation: 0.1, luminance: -0.05),
            hslMidtones: HSLAdjustment(hue: 120.0, saturation: 0.15, luminance: 0.0)
        ),
        source: .builtin,
        category: "tone",
        createdAt: epoch
    )

    static let ocean = FilterPreset(
        id: "builtin_ocean",
        name: "Ocean",
        description: "Cool blues and teals",
        grade: makeGrade(
            "grade_ocean",
            saturation: 0.1, vibrance: 0.15, temperature: 0.3,
            hslShadows: HSLAdjustment(hue: 200.0, saturation: 0.2, luminance: 0.0),
            hslMidtones: HSLAdjustment(hue: 190.0, saturation: 0.1, luminance: 0.0)
        ),
        source: .builtin,
        category: "tone",
        createdAt: epoch
    )

    static let neon = FilterPreset(
        id: "builtin_neon",
        name: "Neon",
        description: "Vibrant, high saturation colors",
        grade: makeGrade(
            "grade_neon",
            contrast: 0.15, saturation: 0.5, vibrance: 0.4, clarity: 0.1,
            hslHighlights: HSLAdjustment(hue: 280.0, saturation: 0.1, luminance: 0.05)
        ),
        source: .builtin,
        category: "creative",
        createdAt: epoch
    )

    static let pastel = FilterPreset(
        id: "builtin_pastel",
        name: "Pastel",
        description: "Soft, light pastels",
        grade: makeGrade(
            "grade_pastel",
            brightness: 0.15, contrast: -0.2, saturation: -0.15,
            vibrance: 0.1, highlights: 0.1, blacks: 0.1
        ),
        source: .builtin,
        category: "creative",
        createdAt: epoch
    )
}
