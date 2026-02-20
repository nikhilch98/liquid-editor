import Foundation

/// Complete color grading configuration for a clip.
///
/// Contains all adjustable parameters organized by category:
/// - Basic adjustments (exposure, brightness, contrast, saturation, vibrance)
/// - White balance (temperature, tint)
/// - Tone (highlights, shadows, whites, blacks)
/// - Detail (sharpness, clarity)
/// - HSL wheels (shadows, midtones, highlights)
/// - Curves (luminance, red, green, blue)
/// - LUT filter reference
/// - Vignette (intensity, radius, softness)
struct ColorGrade: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    // MARK: - Basic Adjustments

    /// Exposure adjustment in EV (-3.0 to 3.0).
    let exposure: Double

    /// Brightness adjustment (-1.0 to 1.0).
    let brightness: Double

    /// Contrast adjustment (-1.0 to 1.0).
    let contrast: Double

    /// Saturation adjustment (-1.0 to 1.0, 0.0 = no change).
    let saturation: Double

    /// Vibrance - selective saturation boost (-1.0 to 1.0).
    let vibrance: Double

    // MARK: - White Balance

    /// Color temperature (-1.0 = warm, 1.0 = cool).
    let temperature: Double

    /// Tint (-1.0 = green, 1.0 = magenta).
    let tint: Double

    // MARK: - Tone

    /// Highlights adjustment (-1.0 to 1.0).
    let highlights: Double

    /// Shadows adjustment (-1.0 to 1.0).
    let shadows: Double

    /// Whites adjustment (-1.0 to 1.0).
    let whites: Double

    /// Blacks adjustment (-1.0 to 1.0).
    let blacks: Double

    // MARK: - Detail

    /// Sharpness (0.0 to 1.0).
    let sharpness: Double

    /// Clarity - local contrast (-1.0 to 1.0).
    let clarity: Double

    // MARK: - Hue

    /// Global hue rotation (-180 to 180 degrees).
    let hue: Double

    // MARK: - LUT Filter

    /// Optional LUT filter reference.
    let lutFilter: LUTReference?

    // MARK: - HSL Wheels

    /// Shadow color wheel adjustment.
    let hslShadows: HSLAdjustment

    /// Midtone color wheel adjustment.
    let hslMidtones: HSLAdjustment

    /// Highlight color wheel adjustment.
    let hslHighlights: HSLAdjustment

    // MARK: - Curves

    /// Luminance curve.
    let curveLuminance: CurveData

    /// Red channel curve.
    let curveRed: CurveData

    /// Green channel curve.
    let curveGreen: CurveData

    /// Blue channel curve.
    let curveBlue: CurveData

    // MARK: - Vignette

    /// Vignette intensity (0.0 to 1.0).
    let vignetteIntensity: Double

    /// Vignette radius (0.0 to 1.0, normalized).
    let vignetteRadius: Double

    /// Vignette softness (0.0 to 1.0).
    let vignetteSoftness: Double

    // MARK: - Metadata

    /// Master toggle for enabling/disabling the grade.
    let isEnabled: Bool

    /// When this grade was created.
    let createdAt: Date

    /// When this grade was last modified.
    let modifiedAt: Date

    init(
        id: String,
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
        lutFilter: LUTReference? = nil,
        hslShadows: HSLAdjustment = .identity,
        hslMidtones: HSLAdjustment = .identity,
        hslHighlights: HSLAdjustment = .identity,
        curveLuminance: CurveData = .identity,
        curveRed: CurveData = .identity,
        curveGreen: CurveData = .identity,
        curveBlue: CurveData = .identity,
        vignetteIntensity: Double = 0.0,
        vignetteRadius: Double = 1.0,
        vignetteSoftness: Double = 0.5,
        isEnabled: Bool = true,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.exposure = exposure
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.vibrance = vibrance
        self.temperature = temperature
        self.tint = tint
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.sharpness = sharpness
        self.clarity = clarity
        self.hue = hue
        self.lutFilter = lutFilter
        self.hslShadows = hslShadows
        self.hslMidtones = hslMidtones
        self.hslHighlights = hslHighlights
        self.curveLuminance = curveLuminance
        self.curveRed = curveRed
        self.curveGreen = curveGreen
        self.curveBlue = curveBlue
        self.vignetteIntensity = vignetteIntensity
        self.vignetteRadius = vignetteRadius
        self.vignetteSoftness = vignetteSoftness
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Epsilon for floating-point comparison.
    private static let epsilon: Double = 0.0001

    /// Check if any parameter deviates from defaults.
    var isIdentity: Bool {
        abs(exposure) < Self.epsilon
            && abs(brightness) < Self.epsilon
            && abs(contrast) < Self.epsilon
            && abs(saturation) < Self.epsilon
            && abs(vibrance) < Self.epsilon
            && abs(temperature) < Self.epsilon
            && abs(tint) < Self.epsilon
            && abs(highlights) < Self.epsilon
            && abs(shadows) < Self.epsilon
            && abs(whites) < Self.epsilon
            && abs(blacks) < Self.epsilon
            && abs(sharpness) < Self.epsilon
            && abs(clarity) < Self.epsilon
            && abs(hue) < Self.epsilon
            && lutFilter == nil
            && hslShadows.isIdentity
            && hslMidtones.isIdentity
            && hslHighlights.isIdentity
            && curveLuminance.isIdentity
            && curveRed.isIdentity
            && curveGreen.isIdentity
            && curveBlue.isIdentity
            && abs(vignetteIntensity) < Self.epsilon
    }

    /// Update a single parameter by name.
    func withParam(_ name: String, value: Double) -> ColorGrade {
        switch name {
        case "exposure": return with(exposure: value)
        case "brightness": return with(brightness: value)
        case "contrast": return with(contrast: value)
        case "saturation": return with(saturation: value)
        case "vibrance": return with(vibrance: value)
        case "temperature": return with(temperature: value)
        case "tint": return with(tint: value)
        case "highlights": return with(highlights: value)
        case "shadows": return with(shadows: value)
        case "whites": return with(whites: value)
        case "blacks": return with(blacks: value)
        case "sharpness": return with(sharpness: value)
        case "clarity": return with(clarity: value)
        case "hue": return with(hue: value)
        case "vignetteIntensity": return with(vignetteIntensity: value)
        case "vignetteRadius": return with(vignetteRadius: value)
        case "vignetteSoftness": return with(vignetteSoftness: value)
        default: return self
        }
    }

    /// Linearly interpolate between two color grades.
    static func lerp(_ a: ColorGrade, _ b: ColorGrade, t: Double) -> ColorGrade {
        let ct = min(max(t, 0.0), 1.0)
        let now = Date()

        return ColorGrade(
            id: b.id,
            exposure: lerpDouble(a.exposure, b.exposure, ct),
            brightness: lerpDouble(a.brightness, b.brightness, ct),
            contrast: lerpDouble(a.contrast, b.contrast, ct),
            saturation: lerpDouble(a.saturation, b.saturation, ct),
            vibrance: lerpDouble(a.vibrance, b.vibrance, ct),
            temperature: lerpDouble(a.temperature, b.temperature, ct),
            tint: lerpDouble(a.tint, b.tint, ct),
            highlights: lerpDouble(a.highlights, b.highlights, ct),
            shadows: lerpDouble(a.shadows, b.shadows, ct),
            whites: lerpDouble(a.whites, b.whites, ct),
            blacks: lerpDouble(a.blacks, b.blacks, ct),
            sharpness: lerpDouble(a.sharpness, b.sharpness, ct),
            clarity: lerpDouble(a.clarity, b.clarity, ct),
            hue: lerpDouble(a.hue, b.hue, ct),
            lutFilter: ct < 0.5 ? a.lutFilter : b.lutFilter,
            hslShadows: HSLAdjustment.lerp(a.hslShadows, b.hslShadows, t: ct),
            hslMidtones: HSLAdjustment.lerp(a.hslMidtones, b.hslMidtones, t: ct),
            hslHighlights: HSLAdjustment.lerp(a.hslHighlights, b.hslHighlights, t: ct),
            curveLuminance: CurveData.lerp(a.curveLuminance, b.curveLuminance, t: ct),
            curveRed: CurveData.lerp(a.curveRed, b.curveRed, t: ct),
            curveGreen: CurveData.lerp(a.curveGreen, b.curveGreen, t: ct),
            curveBlue: CurveData.lerp(a.curveBlue, b.curveBlue, t: ct),
            vignetteIntensity: lerpDouble(a.vignetteIntensity, b.vignetteIntensity, ct),
            vignetteRadius: lerpDouble(a.vignetteRadius, b.vignetteRadius, ct),
            vignetteSoftness: lerpDouble(a.vignetteSoftness, b.vignetteSoftness, ct),
            isEnabled: b.isEnabled,
            createdAt: a.createdAt,
            modifiedAt: now
        )
    }

    private static func lerpDouble(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Create a copy with optional field overrides.
    func with(
        id: String? = nil,
        exposure: Double? = nil,
        brightness: Double? = nil,
        contrast: Double? = nil,
        saturation: Double? = nil,
        vibrance: Double? = nil,
        temperature: Double? = nil,
        tint: Double? = nil,
        highlights: Double? = nil,
        shadows: Double? = nil,
        whites: Double? = nil,
        blacks: Double? = nil,
        sharpness: Double? = nil,
        clarity: Double? = nil,
        hue: Double? = nil,
        lutFilter: LUTReference? = nil,
        clearLut: Bool = false,
        hslShadows: HSLAdjustment? = nil,
        hslMidtones: HSLAdjustment? = nil,
        hslHighlights: HSLAdjustment? = nil,
        curveLuminance: CurveData? = nil,
        curveRed: CurveData? = nil,
        curveGreen: CurveData? = nil,
        curveBlue: CurveData? = nil,
        vignetteIntensity: Double? = nil,
        vignetteRadius: Double? = nil,
        vignetteSoftness: Double? = nil,
        isEnabled: Bool? = nil,
        createdAt: Date? = nil,
        modifiedAt: Date? = nil
    ) -> ColorGrade {
        ColorGrade(
            id: id ?? self.id,
            exposure: exposure ?? self.exposure,
            brightness: brightness ?? self.brightness,
            contrast: contrast ?? self.contrast,
            saturation: saturation ?? self.saturation,
            vibrance: vibrance ?? self.vibrance,
            temperature: temperature ?? self.temperature,
            tint: tint ?? self.tint,
            highlights: highlights ?? self.highlights,
            shadows: shadows ?? self.shadows,
            whites: whites ?? self.whites,
            blacks: blacks ?? self.blacks,
            sharpness: sharpness ?? self.sharpness,
            clarity: clarity ?? self.clarity,
            hue: hue ?? self.hue,
            lutFilter: clearLut ? nil : (lutFilter ?? self.lutFilter),
            hslShadows: hslShadows ?? self.hslShadows,
            hslMidtones: hslMidtones ?? self.hslMidtones,
            hslHighlights: hslHighlights ?? self.hslHighlights,
            curveLuminance: curveLuminance ?? self.curveLuminance,
            curveRed: curveRed ?? self.curveRed,
            curveGreen: curveGreen ?? self.curveGreen,
            curveBlue: curveBlue ?? self.curveBlue,
            vignetteIntensity: vignetteIntensity ?? self.vignetteIntensity,
            vignetteRadius: vignetteRadius ?? self.vignetteRadius,
            vignetteSoftness: vignetteSoftness ?? self.vignetteSoftness,
            isEnabled: isEnabled ?? self.isEnabled,
            createdAt: createdAt ?? self.createdAt,
            modifiedAt: modifiedAt ?? Date()
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, exposure, brightness, contrast, saturation, vibrance
        case temperature, tint, highlights, shadows, whites, blacks
        case sharpness, clarity, hue, lutFilter
        case hslShadows, hslMidtones, hslHighlights
        case curveLuminance, curveRed, curveGreen, curveBlue
        case vignetteIntensity, vignetteRadius, vignetteSoftness
        case isEnabled, createdAt, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0.0
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0.0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0.0
        vibrance = try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0.0
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.0
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0.0
        highlights = try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0.0
        shadows = try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0.0
        whites = try container.decodeIfPresent(Double.self, forKey: .whites) ?? 0.0
        blacks = try container.decodeIfPresent(Double.self, forKey: .blacks) ?? 0.0
        sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0.0
        clarity = try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0.0
        hue = try container.decodeIfPresent(Double.self, forKey: .hue) ?? 0.0
        lutFilter = try container.decodeIfPresent(LUTReference.self, forKey: .lutFilter)
        hslShadows = try container.decodeIfPresent(HSLAdjustment.self, forKey: .hslShadows) ?? .identity
        hslMidtones = try container.decodeIfPresent(HSLAdjustment.self, forKey: .hslMidtones) ?? .identity
        hslHighlights = try container.decodeIfPresent(HSLAdjustment.self, forKey: .hslHighlights) ?? .identity
        curveLuminance = try container.decodeIfPresent(CurveData.self, forKey: .curveLuminance) ?? .identity
        curveRed = try container.decodeIfPresent(CurveData.self, forKey: .curveRed) ?? .identity
        curveGreen = try container.decodeIfPresent(CurveData.self, forKey: .curveGreen) ?? .identity
        curveBlue = try container.decodeIfPresent(CurveData.self, forKey: .curveBlue) ?? .identity
        vignetteIntensity = try container.decodeIfPresent(Double.self, forKey: .vignetteIntensity) ?? 0.0
        vignetteRadius = try container.decodeIfPresent(Double.self, forKey: .vignetteRadius) ?? 1.0
        vignetteSoftness = try container.decodeIfPresent(Double.self, forKey: .vignetteSoftness) ?? 0.5
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true

        let createdAtStr = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtStr) ?? Date()

        let modifiedAtStr = try container.decode(String.self, forKey: .modifiedAt)
        modifiedAt = ISO8601DateFormatter().date(from: modifiedAtStr) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(vibrance, forKey: .vibrance)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(tint, forKey: .tint)
        try container.encode(highlights, forKey: .highlights)
        try container.encode(shadows, forKey: .shadows)
        try container.encode(whites, forKey: .whites)
        try container.encode(blacks, forKey: .blacks)
        try container.encode(sharpness, forKey: .sharpness)
        try container.encode(clarity, forKey: .clarity)
        try container.encode(hue, forKey: .hue)
        try container.encodeIfPresent(lutFilter, forKey: .lutFilter)
        try container.encode(hslShadows, forKey: .hslShadows)
        try container.encode(hslMidtones, forKey: .hslMidtones)
        try container.encode(hslHighlights, forKey: .hslHighlights)
        try container.encode(curveLuminance, forKey: .curveLuminance)
        try container.encode(curveRed, forKey: .curveRed)
        try container.encode(curveGreen, forKey: .curveGreen)
        try container.encode(curveBlue, forKey: .curveBlue)
        try container.encode(vignetteIntensity, forKey: .vignetteIntensity)
        try container.encode(vignetteRadius, forKey: .vignetteRadius)
        try container.encode(vignetteSoftness, forKey: .vignetteSoftness)
        try container.encode(isEnabled, forKey: .isEnabled)

        let formatter = ISO8601DateFormatter()
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(formatter.string(from: modifiedAt), forKey: .modifiedAt)
    }

    // MARK: - Equatable (identity-based)

    static func == (lhs: ColorGrade, rhs: ColorGrade) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
