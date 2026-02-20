import Foundation

/// Available animation preset types for text clips.
///
/// Grouped into enter, exit, and sustain categories.
/// Enter animations play when the text clip begins.
/// Exit animations play when the text clip ends.
/// Sustain animations loop during the visible duration between enter and exit.
enum TextAnimationPresetType: String, Codable, CaseIterable, Sendable {
    // Enter animations
    case fadeIn
    case slideInLeft
    case slideInRight
    case slideInTop
    case slideInBottom
    case scaleUp
    case bounceIn
    case typewriter
    case glitchIn
    case rotateIn
    case blurIn
    case popIn

    // Exit animations
    case fadeOut
    case slideOutLeft
    case slideOutRight
    case slideOutTop
    case slideOutBottom
    case scaleDown
    case bounceOut
    case glitchOut
    case rotateOut
    case blurOut
    case popOut

    // Sustain animations (loop during visible duration)
    case breathe
    case pulse
    case float
    case shake
    case flicker
}

/// Configuration for a text animation preset.
///
/// Wraps a `TextAnimationPresetType` with intensity and custom parameters.
struct TextAnimationPreset: Codable, Equatable, Hashable, Sendable {
    /// The animation preset type.
    let type: TextAnimationPresetType

    /// Animation intensity (0.0-1.0). Controls amplitude of movement/scale.
    let intensity: Double

    /// Custom parameters per animation type.
    ///
    /// Examples:
    /// - `"easing": "spring"` value for override
    /// - `"loopDuration": 2.0` for sustain loop period in seconds
    /// - `"direction": 45.0` for slide angle in degrees
    let parameters: [String: Double]

    init(
        type: TextAnimationPresetType,
        intensity: Double = 1.0,
        parameters: [String: Double] = [:]
    ) {
        self.type = type
        self.intensity = intensity
        self.parameters = parameters
    }

    /// Create a copy with optional field overrides.
    func with(
        type: TextAnimationPresetType? = nil,
        intensity: Double? = nil,
        parameters: [String: Double]? = nil
    ) -> TextAnimationPreset {
        TextAnimationPreset(
            type: type ?? self.type,
            intensity: intensity ?? self.intensity,
            parameters: parameters ?? self.parameters
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type, intensity, parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let typeName = try container.decodeIfPresent(String.self, forKey: .type) ?? "fadeIn"
        type = TextAnimationPresetType(rawValue: typeName) ?? .fadeIn

        intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 1.0
        parameters = try container.decodeIfPresent([String: Double].self, forKey: .parameters) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(parameters, forKey: .parameters)
    }
}
