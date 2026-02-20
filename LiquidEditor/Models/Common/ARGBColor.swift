import Foundation

/// Simple ARGB color representation for platform-independent color storage.
///
/// All components are normalized to [0.0, 1.0] range.
struct ARGBColor: Codable, Equatable, Hashable, Sendable {
    /// Alpha channel (0.0 = fully transparent, 1.0 = fully opaque).
    let alpha: Double

    /// Red channel (0.0 to 1.0).
    let red: Double

    /// Green channel (0.0 to 1.0).
    let green: Double

    /// Blue channel (0.0 to 1.0).
    let blue: Double

    // MARK: - Common Colors

    static let black = ARGBColor(alpha: 1, red: 0, green: 0, blue: 0)
    static let white = ARGBColor(alpha: 1, red: 1, green: 1, blue: 1)
    static let clear = ARGBColor(alpha: 0, red: 0, green: 0, blue: 0)

    // MARK: - ARGB Int Conversion

    /// Create from a 32-bit ARGB integer value (matching Flutter's `Color(int)` format).
    ///
    /// Format: 0xAARRGGBB where each component is 8 bits.
    static func fromARGB32(_ value: Int) -> ARGBColor {
        let a = Double((value >> 24) & 0xFF) / 255.0
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return ARGBColor(alpha: a, red: r, green: g, blue: b)
    }

    /// Convert to a 32-bit ARGB integer value.
    var toARGB32: Int {
        let a = Int((alpha * 255).rounded()) & 0xFF
        let r = Int((red * 255).rounded()) & 0xFF
        let g = Int((green * 255).rounded()) & 0xFF
        let b = Int((blue * 255).rounded()) & 0xFF
        return (a << 24) | (r << 16) | (g << 8) | b
    }

    // MARK: - Convenience Queries

    /// Whether this color is fully opaque black.
    var isBlack: Bool {
        alpha == 1.0 && red == 0.0 && green == 0.0 && blue == 0.0
    }

    /// Whether this color is fully opaque white.
    var isWhite: Bool {
        alpha == 1.0 && red == 1.0 && green == 1.0 && blue == 1.0
    }

    /// Whether this color is fully transparent.
    var isTransparent: Bool {
        alpha == 0.0
    }

    // MARK: - Mutation

    /// Create a copy with optional overrides.
    func with(
        alpha: Double? = nil,
        red: Double? = nil,
        green: Double? = nil,
        blue: Double? = nil
    ) -> ARGBColor {
        ARGBColor(
            alpha: alpha ?? self.alpha,
            red: red ?? self.red,
            green: green ?? self.green,
            blue: blue ?? self.blue
        )
    }
}
