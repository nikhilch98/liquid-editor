// OverlayTransform.swift
// LiquidEditor
//
// Overlay transform for spatial positioning of overlay clips.
// All coordinates are normalized (0.0-1.0) relative to the output frame,
// enabling resolution-independent positioning.

import CoreGraphics
import Foundation

/// Spatial transform for an overlay clip.
///
/// Controls position, scale, rotation, and opacity of an overlay.
/// Can be interpolated between keyframes for animation.
struct OverlayTransform: Codable, Equatable, Hashable, Sendable {
    /// Position of overlay center (0.0, 0.0) = top-left, (1.0, 1.0) = bottom-right.
    let position: CGPoint

    /// Scale relative to source size (1.0 = original size).
    let scale: Double

    /// Rotation in radians.
    let rotation: Double

    /// Opacity (0.0 = invisible, 1.0 = fully opaque).
    let opacity: Double

    /// Anchor point for rotation/scale (0.5, 0.5 = center).
    let anchor: CGPoint

    init(
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: Double = 1.0,
        rotation: Double = 0.0,
        opacity: Double = 1.0,
        anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) {
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.anchor = anchor
    }

    /// Identity transform (centered, full size, no rotation, full opacity).
    static let identity = OverlayTransform()

    /// Default PiP transform (bottom-right corner, 30% size).
    static let defaultPip = OverlayTransform(
        position: CGPoint(x: 0.75, y: 0.75),
        scale: 0.3
    )

    /// Whether this is effectively an identity transform.
    var isIdentity: Bool {
        abs(position.x - 0.5) < 0.001
            && abs(position.y - 0.5) < 0.001
            && abs(scale - 1.0) < 0.001
            && abs(rotation) < 0.001
            && abs(opacity - 1.0) < 0.001
    }

    /// Whether the overlay is visible (opacity > 0 and scale > 0).
    var isVisible: Bool { opacity > 0.001 && scale > 0.001 }

    /// Linearly interpolate between two transforms for animation.
    static func lerp(_ a: OverlayTransform, _ b: OverlayTransform, t: Double) -> OverlayTransform {
        let clampedT = t
        return OverlayTransform(
            position: CGPoint(
                x: a.position.x + (b.position.x - a.position.x) * clampedT,
                y: a.position.y + (b.position.y - a.position.y) * clampedT
            ),
            scale: a.scale + (b.scale - a.scale) * clampedT,
            rotation: a.rotation + (b.rotation - a.rotation) * clampedT,
            opacity: min(max(a.opacity + (b.opacity - a.opacity) * clampedT, 0.0), 1.0),
            anchor: CGPoint(
                x: a.anchor.x + (b.anchor.x - a.anchor.x) * clampedT,
                y: a.anchor.y + (b.anchor.y - a.anchor.y) * clampedT
            )
        )
    }

    /// Create a copy with updated fields.
    func with(
        position: CGPoint? = nil,
        scale: Double? = nil,
        rotation: Double? = nil,
        opacity: Double? = nil,
        anchor: CGPoint? = nil
    ) -> OverlayTransform {
        OverlayTransform(
            position: position ?? self.position,
            scale: scale ?? self.scale,
            rotation: rotation ?? self.rotation,
            opacity: opacity ?? self.opacity,
            anchor: anchor ?? self.anchor
        )
    }

    /// Clamp values to valid ranges.
    func clamped() -> OverlayTransform {
        OverlayTransform(
            position: position,
            scale: min(max(scale, 0.01), 5.0),
            rotation: rotation,
            opacity: min(max(opacity, 0.0), 1.0),
            anchor: CGPoint(
                x: min(max(anchor.x, 0.0), 1.0),
                y: min(max(anchor.y, 0.0), 1.0)
            )
        )
    }

    // MARK: - Codable

    /// Custom coding keys matching the Dart JSON key names for backward compatibility.
    enum CodingKeys: String, CodingKey {
        case positionX
        case positionY
        case scale
        case rotation
        case opacity
        case anchorX
        case anchorY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let posX = try container.decodeIfPresent(Double.self, forKey: .positionX) ?? 0.5
        let posY = try container.decodeIfPresent(Double.self, forKey: .positionY) ?? 0.5
        position = CGPoint(x: posX, y: posY)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        let ancX = try container.decodeIfPresent(Double.self, forKey: .anchorX) ?? 0.5
        let ancY = try container.decodeIfPresent(Double.self, forKey: .anchorY) ?? 0.5
        anchor = CGPoint(x: ancX, y: ancY)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position.x, forKey: .positionX)
        try container.encode(position.y, forKey: .positionY)
        try container.encode(scale, forKey: .scale)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(anchor.x, forKey: .anchorX)
        try container.encode(anchor.y, forKey: .anchorY)
    }
}

// MARK: - CustomStringConvertible

extension OverlayTransform: CustomStringConvertible {
    var description: String {
        "OverlayTransform(pos: (\(position.x), \(position.y)), scale: \(scale), rot: \(rotation), opacity: \(opacity))"
    }
}
