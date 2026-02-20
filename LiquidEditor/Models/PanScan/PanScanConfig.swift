import Foundation
import CoreGraphics

// MARK: - PanScanRegion

/// A single viewport/crop region at a specific point in time.
///
/// Defines a normalized crop rectangle within the source frame,
/// plus optional rotation. Regions are interpolated between
/// keyframes to create smooth animated movement.
struct PanScanRegion: Codable, Equatable, Hashable, Sendable {
    /// Crop rectangle in normalized coordinates (0.0-1.0 relative to source frame).
    let cropRect: CGRect

    /// Rotation angle in radians (for tilted crops).
    let rotation: Double

    /// Default region (full frame, no crop).
    static let fullFrame = PanScanRegion(
        cropRect: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
    )

    init(cropRect: CGRect, rotation: Double = 0.0) {
        self.cropRect = cropRect
        self.rotation = rotation
    }

    /// Whether this region covers the full frame (no crop).
    var isFullFrame: Bool {
        cropRect.origin.x <= 0.001 &&
        cropRect.origin.y <= 0.001 &&
        cropRect.size.width >= 0.999 &&
        cropRect.size.height >= 0.999 &&
        abs(rotation) < 0.001
    }

    /// Effective zoom level (1.0 = no zoom, 2.0 = 2x zoom).
    var zoomLevel: Double {
        let average = (cropRect.width + cropRect.height) / 2.0
        guard average > 0 else { return 1.0 }
        return 1.0 / average
    }

    /// Center of the crop region.
    var center: CGPoint {
        CGPoint(
            x: cropRect.midX,
            y: cropRect.midY
        )
    }

    /// Interpolate between two regions.
    static func lerp(_ a: PanScanRegion, _ b: PanScanRegion, t: Double) -> PanScanRegion {
        PanScanRegion(
            cropRect: CGRect(
                x: a.cropRect.origin.x + (b.cropRect.origin.x - a.cropRect.origin.x) * t,
                y: a.cropRect.origin.y + (b.cropRect.origin.y - a.cropRect.origin.y) * t,
                width: a.cropRect.width + (b.cropRect.width - a.cropRect.width) * t,
                height: a.cropRect.height + (b.cropRect.height - a.cropRect.height) * t
            ),
            rotation: a.rotation + (b.rotation - a.rotation) * t
        )
    }

    /// Create a copy with optional overrides.
    func with(
        cropRect: CGRect? = nil,
        rotation: Double? = nil
    ) -> PanScanRegion {
        PanScanRegion(
            cropRect: cropRect ?? self.cropRect,
            rotation: rotation ?? self.rotation
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case left, top, right, bottom, rotation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let left = try container.decode(Double.self, forKey: .left)
        let top = try container.decode(Double.self, forKey: .top)
        let right = try container.decode(Double.self, forKey: .right)
        let bottom = try container.decode(Double.self, forKey: .bottom)
        cropRect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cropRect.origin.x, forKey: .left)
        try container.encode(cropRect.origin.y, forKey: .top)
        try container.encode(cropRect.origin.x + cropRect.width, forKey: .right)
        try container.encode(cropRect.origin.y + cropRect.height, forKey: .bottom)
        try container.encode(rotation, forKey: .rotation)
    }
}

// MARK: - PanScanKeyframe

/// A keyframe for pan & scan animation.
struct PanScanKeyframe: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier.
    let id: String

    /// Time position (microseconds from clip start).
    let timeMicros: TimeMicros

    /// Viewport region at this keyframe.
    let region: PanScanRegion

    /// Interpolation type to the next keyframe.
    let interpolation: InterpolationType

    init(
        id: String,
        timeMicros: TimeMicros,
        region: PanScanRegion,
        interpolation: InterpolationType = .easeInOut
    ) {
        self.id = id
        self.timeMicros = timeMicros
        self.region = region
        self.interpolation = interpolation
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        timeMicros: TimeMicros? = nil,
        region: PanScanRegion? = nil,
        interpolation: InterpolationType? = nil
    ) -> PanScanKeyframe {
        PanScanKeyframe(
            id: id ?? self.id,
            timeMicros: timeMicros ?? self.timeMicros,
            region: region ?? self.region,
            interpolation: interpolation ?? self.interpolation
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: PanScanKeyframe, rhs: PanScanKeyframe) -> Bool {
        lhs.id == rhs.id && lhs.timeMicros == rhs.timeMicros
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timeMicros)
    }
}

// MARK: - PanScanConfig

/// Complete pan & scan configuration for a clip.
///
/// Contains keyframes for multi-point camera movement (Ken Burns effect).
struct PanScanConfig: Codable, Equatable, Hashable, Sendable {
    /// Whether pan & scan is enabled for this clip.
    let isEnabled: Bool

    /// Keyframes defining the camera movement path.
    ///
    /// Must have at least 2 keyframes for animation.
    /// If empty and `isEnabled` is true, no crop is applied.
    let keyframes: [PanScanKeyframe]

    /// Default (disabled) configuration.
    static let disabled = PanScanConfig()

    init(
        isEnabled: Bool = false,
        keyframes: [PanScanKeyframe] = []
    ) {
        self.isEnabled = isEnabled
        self.keyframes = keyframes
    }

    /// Quick factory for simple start-to-end Ken Burns.
    static func simple(
        startId: String,
        endId: String,
        startRegion: PanScanRegion,
        endRegion: PanScanRegion,
        clipDurationMicros: TimeMicros
    ) -> PanScanConfig {
        PanScanConfig(
            isEnabled: true,
            keyframes: [
                PanScanKeyframe(
                    id: startId,
                    timeMicros: 0,
                    region: startRegion
                ),
                PanScanKeyframe(
                    id: endId,
                    timeMicros: clipDurationMicros,
                    region: endRegion
                ),
            ]
        )
    }

    /// Whether this config has animation keyframes.
    var hasKeyframes: Bool { keyframes.count >= 2 }

    /// Get sorted keyframes.
    var sortedKeyframes: [PanScanKeyframe] {
        keyframes.sorted { $0.timeMicros < $1.timeMicros }
    }

    /// Interpolate the crop region at a specific time within the clip.
    func regionAtTime(_ timeMicros: TimeMicros) -> PanScanRegion {
        guard !keyframes.isEmpty else { return .fullFrame }

        let sorted = sortedKeyframes

        // Before first keyframe.
        if timeMicros <= sorted.first!.timeMicros {
            return sorted.first!.region
        }

        // After last keyframe.
        if timeMicros >= sorted.last!.timeMicros {
            return sorted.last!.region
        }

        // Find surrounding keyframes and interpolate.
        for i in 0..<(sorted.count - 1) {
            if timeMicros >= sorted[i].timeMicros && timeMicros < sorted[i + 1].timeMicros {
                let range = sorted[i + 1].timeMicros - sorted[i].timeMicros
                if range == 0 { return sorted[i].region }

                let t = Double(timeMicros - sorted[i].timeMicros) / Double(range)
                return PanScanRegion.lerp(sorted[i].region, sorted[i + 1].region, t: t)
            }
        }

        return sorted.last!.region
    }

    /// Create a copy with optional overrides.
    func with(
        isEnabled: Bool? = nil,
        keyframes: [PanScanKeyframe]? = nil
    ) -> PanScanConfig {
        PanScanConfig(
            isEnabled: isEnabled ?? self.isEnabled,
            keyframes: keyframes ?? self.keyframes
        )
    }
}
