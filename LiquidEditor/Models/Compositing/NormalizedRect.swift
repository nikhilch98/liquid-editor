// NormalizedRect.swift
// LiquidEditor
//
// Normalized rectangle in 0.0-1.0 coordinate space.
// Used for resolution-independent positioning of PiP regions,
// split-screen cells, and overlay transforms.

import CoreGraphics
import Foundation

/// A rectangle defined in normalized coordinates (0.0-1.0).
///
/// This enables resolution-independent positioning. A NormalizedRect
/// can be converted to pixel coordinates via ``toRect(outputSize:)`` given an output size.
struct NormalizedRect: Codable, Equatable, Hashable, Sendable {
    /// X position of the top-left corner (0.0 = left, 1.0 = right).
    let x: Double

    /// Y position of the top-left corner (0.0 = top, 1.0 = bottom).
    let y: Double

    /// Width as a fraction of the output frame (0.0-1.0).
    let width: Double

    /// Height as a fraction of the output frame (0.0-1.0).
    let height: Double

    /// Full frame (covers entire output).
    static let fullFrame = NormalizedRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)

    /// Default PiP position (bottom-right, 35% size).
    static let defaultPip = NormalizedRect(x: 0.6, y: 0.6, width: 0.35, height: 0.35)

    /// Center of the rectangle (normalized coordinates).
    var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }

    /// Right edge position.
    var right: Double { x + width }

    /// Bottom edge position.
    var bottom: Double { y + height }

    /// Aspect ratio (width / height).
    var aspectRatio: Double { height > 0 ? width / height : 1.0 }

    /// Convert to pixel `CGRect` given output dimensions.
    func toRect(outputSize: CGSize) -> CGRect {
        CGRect(
            x: x * outputSize.width,
            y: y * outputSize.height,
            width: width * outputSize.width,
            height: height * outputSize.height
        )
    }

    /// Whether this rect is effectively full-frame.
    var isFullFrame: Bool {
        abs(x - 0.0) < 0.001
            && abs(y - 0.0) < 0.001
            && abs(width - 1.0) < 0.001
            && abs(height - 1.0) < 0.001
    }

    /// Create a copy with updated fields.
    func with(
        x: Double? = nil,
        y: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) -> NormalizedRect {
        NormalizedRect(
            x: x ?? self.x,
            y: y ?? self.y,
            width: width ?? self.width,
            height: height ?? self.height
        )
    }

    /// Clamp all values to valid range.
    func clamped() -> NormalizedRect {
        let clampedX = min(max(x, 0.0), 1.0)
        let clampedY = min(max(y, 0.0), 1.0)
        return NormalizedRect(
            x: clampedX,
            y: clampedY,
            width: min(max(width, 0.0), 1.0 - clampedX),
            height: min(max(height, 0.0), 1.0 - clampedY)
        )
    }

    /// Linearly interpolate between two normalized rects.
    static func lerp(_ a: NormalizedRect, _ b: NormalizedRect, t: Double) -> NormalizedRect {
        NormalizedRect(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }
}

// MARK: - CustomStringConvertible

extension NormalizedRect: CustomStringConvertible {
    var description: String {
        "NormalizedRect(x: \(x), y: \(y), w: \(width), h: \(height))"
    }
}
