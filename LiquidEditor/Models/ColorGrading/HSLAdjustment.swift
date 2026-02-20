import Foundation

/// HSL adjustment for a tonal range (shadows, midtones, highlights).
///
/// Represents hue/saturation/luminance offset for color wheel controls.
struct HSLAdjustment: Codable, Equatable, Hashable, Sendable {
    /// Hue offset in degrees (0.0 to 360.0).
    let hue: Double

    /// Saturation (0.0 to 1.0, 0.0 = neutral).
    let saturation: Double

    /// Luminance adjustment (-1.0 to 1.0, lift/gamma/gain).
    let luminance: Double

    init(
        hue: Double = 0.0,
        saturation: Double = 0.0,
        luminance: Double = 0.0
    ) {
        self.hue = hue
        self.saturation = saturation
        self.luminance = luminance
    }

    /// Identity (no adjustment).
    static let identity = HSLAdjustment()

    /// Epsilon for floating-point comparison.
    private static let epsilon: Double = 0.0001

    /// Whether this is an identity adjustment.
    var isIdentity: Bool {
        abs(hue) < Self.epsilon
            && abs(saturation) < Self.epsilon
            && abs(luminance) < Self.epsilon
    }

    /// Linearly interpolate between two HSL adjustments.
    static func lerp(_ a: HSLAdjustment, _ b: HSLAdjustment, t: Double) -> HSLAdjustment {
        HSLAdjustment(
            hue: a.hue + (b.hue - a.hue) * t,
            saturation: a.saturation + (b.saturation - a.saturation) * t,
            luminance: a.luminance + (b.luminance - a.luminance) * t
        )
    }

    /// Create a copy with optional overrides.
    func with(
        hue: Double? = nil,
        saturation: Double? = nil,
        luminance: Double? = nil
    ) -> HSLAdjustment {
        HSLAdjustment(
            hue: hue ?? self.hue,
            saturation: saturation ?? self.saturation,
            luminance: luminance ?? self.luminance
        )
    }

    // MARK: - Equatable (epsilon-based)

    static func == (lhs: HSLAdjustment, rhs: HSLAdjustment) -> Bool {
        abs(lhs.hue - rhs.hue) < epsilon
            && abs(lhs.saturation - rhs.saturation) < epsilon
            && abs(lhs.luminance - rhs.luminance) < epsilon
    }

    // MARK: - Hashable (rounded for epsilon tolerance)

    func hash(into hasher: inout Hasher) {
        hasher.combine((hue * 10000).rounded())
        hasher.combine((saturation * 10000).rounded())
        hasher.combine((luminance * 10000).rounded())
    }
}
