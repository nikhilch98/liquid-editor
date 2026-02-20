import Foundation
import CoreGraphics

/// Represents the transformation state of a video at a specific point in time.
///
/// Immutable value type. All transform properties are normalized:
/// - `scale`: 0.1 to 5.0 (1.0 = original size)
/// - `translation`: -1.0 to 1.0 (normalized to video dimensions)
/// - `rotation`: angle in radians
/// - `anchor`: 0.0 to 1.0 (normalized anchor point)
struct VideoTransform: Codable, Equatable, Hashable, Sendable {
    /// Scale factor (0.1 to 5.0, where 1.0 = original size).
    let scale: Double

    /// Translation offset normalized to video dimensions (-1.0 to 1.0).
    let translation: CGPoint

    /// Rotation angle in radians.
    let rotation: Double

    /// Anchor point for transformations (normalized 0.0 to 1.0).
    let anchor: CGPoint

    init(
        scale: Double = 1.0,
        translation: CGPoint = .zero,
        rotation: Double = 0.0,
        anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) {
        self.scale = scale
        self.translation = translation
        self.rotation = rotation
        self.anchor = anchor
    }

    /// Identity transform (no changes).
    static let identity = VideoTransform()

    /// Check if this is effectively an identity transform.
    var isIdentity: Bool {
        abs(scale - 1.0) < 0.001
            && abs(translation.x) < 0.001
            && abs(translation.y) < 0.001
            && abs(rotation) < 0.001
    }

    /// Returns a clamped copy.
    func clamped() -> VideoTransform {
        VideoTransform(
            scale: min(max(scale, 0.1), 5.0),
            translation: CGPoint(
                x: min(max(translation.x, -1.0), 1.0),
                y: min(max(translation.y, -1.0), 1.0)
            ),
            rotation: rotation,
            anchor: CGPoint(
                x: min(max(anchor.x, 0.0), 1.0),
                y: min(max(anchor.y, 0.0), 1.0)
            )
        )
    }

    /// Create a copy with optional overrides.
    func with(
        scale: Double? = nil,
        translation: CGPoint? = nil,
        rotation: Double? = nil,
        anchor: CGPoint? = nil
    ) -> VideoTransform {
        VideoTransform(
            scale: scale ?? self.scale,
            translation: translation ?? self.translation,
            rotation: rotation ?? self.rotation,
            anchor: anchor ?? self.anchor
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case scale
        case translationX
        case translationY
        case rotation
        case anchorX
        case anchorY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        let tx = try container.decodeIfPresent(Double.self, forKey: .translationX) ?? 0.0
        let ty = try container.decodeIfPresent(Double.self, forKey: .translationY) ?? 0.0
        translation = CGPoint(x: tx, y: ty)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        let ax = try container.decodeIfPresent(Double.self, forKey: .anchorX) ?? 0.5
        let ay = try container.decodeIfPresent(Double.self, forKey: .anchorY) ?? 0.5
        anchor = CGPoint(x: ax, y: ay)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scale, forKey: .scale)
        try container.encode(translation.x, forKey: .translationX)
        try container.encode(translation.y, forKey: .translationY)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(anchor.x, forKey: .anchorX)
        try container.encode(anchor.y, forKey: .anchorY)
    }
}
