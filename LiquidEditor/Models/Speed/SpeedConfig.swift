import Foundation

// MARK: - FrameBlendMode

/// Frame blending mode for speed changes.
enum FrameBlendMode: String, Codable, CaseIterable, Sendable {
    /// No blending, nearest frame (produces stuttery playback at extreme slow-mo).
    case none

    /// Linear blend between adjacent frames (ghosting on fast motion).
    case blend

    /// Optical flow interpolation (highest quality, most expensive).
    case opticalFlow
}

// MARK: - SpeedKeyframe

/// A single keyframe for variable speed within a clip.
///
/// Speed keyframes define the speed multiplier at specific points
/// in the clip timeline. Between keyframes, speed is interpolated
/// using the specified interpolation type.
struct SpeedKeyframe: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this keyframe.
    let id: String

    /// Position in the clip timeline (microseconds from clip start).
    let timeMicros: TimeMicros

    /// Speed multiplier at this point (0.1 to 16.0).
    let speedMultiplier: Double

    /// Interpolation type to the next speed keyframe.
    let interpolation: InterpolationType

    init(
        id: String,
        timeMicros: TimeMicros,
        speedMultiplier: Double,
        interpolation: InterpolationType = .easeInOut
    ) {
        precondition(
            speedMultiplier >= 0.1 && speedMultiplier <= 16.0,
            "Speed must be between 0.1x and 16.0x"
        )
        precondition(timeMicros >= 0, "Time must be non-negative")
        self.id = id
        self.timeMicros = timeMicros
        self.speedMultiplier = speedMultiplier
        self.interpolation = interpolation
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        timeMicros: TimeMicros? = nil,
        speedMultiplier: Double? = nil,
        interpolation: InterpolationType? = nil
    ) -> SpeedKeyframe {
        SpeedKeyframe(
            id: id ?? self.id,
            timeMicros: timeMicros ?? self.timeMicros,
            speedMultiplier: speedMultiplier ?? self.speedMultiplier,
            interpolation: interpolation ?? self.interpolation
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case timeMicros
        case speedMultiplier
        case interpolation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        timeMicros = try container.decode(TimeMicros.self, forKey: .timeMicros)
        speedMultiplier = try container.decode(Double.self, forKey: .speedMultiplier)

        let interpName = try container.decodeIfPresent(String.self, forKey: .interpolation)
        interpolation = interpName.flatMap { InterpolationType(rawValue: $0) } ?? .easeInOut
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timeMicros, forKey: .timeMicros)
        try container.encode(speedMultiplier, forKey: .speedMultiplier)
        try container.encode(interpolation.rawValue, forKey: .interpolation)
    }
}

// MARK: - SpeedConfig

/// Per-clip speed configuration.
///
/// Defines how fast a clip plays back, whether it plays in reverse,
/// and whether audio pitch should be maintained during speed changes.
///
/// For variable speed (speed ramps), use `rampKeyframes` to define
/// speed changes over time within the clip.
struct SpeedConfig: Codable, Equatable, Hashable, Sendable {
    /// Constant speed multiplier (0.1 = 10x slow, 1.0 = normal, 16.0 = 16x fast).
    ///
    /// When `rampKeyframes` is non-empty, this serves as the default/base speed.
    let speedMultiplier: Double

    /// Whether the clip plays in reverse.
    let isReverse: Bool

    /// Whether to maintain audio pitch when changing speed.
    ///
    /// Uses AVAudioTimePitchAlgorithm.spectral on iOS.
    /// Only effective for speeds between 0.5x and 4.0x.
    /// Audio is muted automatically above 4.0x regardless of this setting.
    let maintainPitch: Bool

    /// Frame blending mode for speed changes.
    let blendMode: FrameBlendMode

    /// Speed ramp keyframes for variable speed within a clip.
    ///
    /// If empty, `speedMultiplier` applies uniformly across the clip.
    /// If non-empty, speed is interpolated between keyframes.
    let rampKeyframes: [SpeedKeyframe]

    /// Minimum allowed speed multiplier.
    static let minSpeed: Double = 0.1

    /// Maximum allowed speed multiplier.
    static let maxSpeed: Double = 16.0

    /// Default (normal speed) configuration.
    static let normal = SpeedConfig()

    init(
        speedMultiplier: Double = 1.0,
        isReverse: Bool = false,
        maintainPitch: Bool = true,
        blendMode: FrameBlendMode = .none,
        rampKeyframes: [SpeedKeyframe] = []
    ) {
        precondition(
            speedMultiplier >= 0.1 && speedMultiplier <= 16.0,
            "Speed must be between 0.1x and 16.0x"
        )
        self.speedMultiplier = speedMultiplier
        self.isReverse = isReverse
        self.maintainPitch = maintainPitch
        self.blendMode = blendMode
        self.rampKeyframes = rampKeyframes
    }

    /// Whether this is the default (normal speed, no changes) configuration.
    var isDefault: Bool {
        speedMultiplier == 1.0
            && !isReverse
            && rampKeyframes.isEmpty
    }

    /// Whether this clip has variable speed (speed ramp).
    var hasSpeedRamp: Bool { !rampKeyframes.isEmpty }

    /// Whether audio should be muted at this speed.
    ///
    /// Audio quality degrades significantly above 4x speed.
    var shouldMuteAudio: Bool { speedMultiplier > 4.0 }

    /// Compute the effective timeline duration after speed change.
    ///
    /// For constant speed: sourceDuration / speedMultiplier.
    /// For speed ramps: numerical integration of the ramp curve.
    func effectiveDurationMicros(_ sourceDurationMicros: TimeMicros) -> TimeMicros {
        if rampKeyframes.isEmpty {
            return TimeMicros((Double(sourceDurationMicros) / speedMultiplier).rounded())
        }
        return computeRampDuration(sourceDurationMicros)
    }

    /// Get the interpolated speed at a specific time within the clip.
    func speedAtTime(_ timeMicros: TimeMicros) -> Double {
        if rampKeyframes.isEmpty { return speedMultiplier }
        let sorted = rampKeyframes.sorted { $0.timeMicros < $1.timeMicros }
        return interpolateSpeed(timeMicros, sorted: sorted)
    }

    /// Clamp speed multiplier to valid range.
    static func clampSpeed(_ speed: Double) -> Double {
        min(max(speed, minSpeed), maxSpeed)
    }

    /// Create a copy with optional overrides.
    func with(
        speedMultiplier: Double? = nil,
        isReverse: Bool? = nil,
        maintainPitch: Bool? = nil,
        blendMode: FrameBlendMode? = nil,
        rampKeyframes: [SpeedKeyframe]? = nil
    ) -> SpeedConfig {
        SpeedConfig(
            speedMultiplier: speedMultiplier ?? self.speedMultiplier,
            isReverse: isReverse ?? self.isReverse,
            maintainPitch: maintainPitch ?? self.maintainPitch,
            blendMode: blendMode ?? self.blendMode,
            rampKeyframes: rampKeyframes ?? self.rampKeyframes
        )
    }

    // MARK: - Private Speed Interpolation

    /// Compute duration for speed-ramped clips via numerical integration.
    ///
    /// Divides the clip into small segments and accumulates the output
    /// time based on the speed at each segment.
    private func computeRampDuration(_ sourceDurationMicros: TimeMicros) -> TimeMicros {
        if rampKeyframes.isEmpty {
            return TimeMicros((Double(sourceDurationMicros) / speedMultiplier).rounded())
        }

        let sorted = rampKeyframes.sorted { $0.timeMicros < $1.timeMicros }
        var outputTime: Double = 0.0
        let stepMicros: TimeMicros = 10_000 // 10ms steps for integration

        var t: TimeMicros = 0
        while t < sourceDurationMicros {
            let speed = interpolateSpeed(t, sorted: sorted)
            let segmentDuration = (t + stepMicros > sourceDurationMicros)
                ? sourceDurationMicros - t
                : stepMicros
            outputTime += Double(segmentDuration) / speed
            t += stepMicros
        }

        return TimeMicros(outputTime.rounded())
    }

    /// Interpolate speed at a given time from sorted keyframes.
    private func interpolateSpeed(
        _ timeMicros: TimeMicros,
        sorted: [SpeedKeyframe]
    ) -> Double {
        if sorted.isEmpty { return speedMultiplier }

        // Before first keyframe
        if timeMicros <= sorted.first!.timeMicros {
            return sorted.first!.speedMultiplier
        }

        // After last keyframe
        if timeMicros >= sorted.last!.timeMicros {
            return sorted.last!.speedMultiplier
        }

        // Find surrounding keyframes
        for i in 0..<(sorted.count - 1) {
            if timeMicros >= sorted[i].timeMicros
                && timeMicros < sorted[i + 1].timeMicros
            {
                let range = sorted[i + 1].timeMicros - sorted[i].timeMicros
                if range == 0 { return sorted[i].speedMultiplier }

                let t = Double(timeMicros - sorted[i].timeMicros) / Double(range)
                // Linear interpolation (matching the interpolation type would
                // require the full easing engine; linear is sufficient for
                // duration estimation).
                return sorted[i].speedMultiplier
                    + (sorted[i + 1].speedMultiplier - sorted[i].speedMultiplier) * t
            }
        }

        return speedMultiplier
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case speedMultiplier
        case isReverse
        case maintainPitch
        case blendMode
        case rampKeyframes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speedMultiplier = try container.decodeIfPresent(Double.self, forKey: .speedMultiplier) ?? 1.0
        isReverse = try container.decodeIfPresent(Bool.self, forKey: .isReverse) ?? false
        maintainPitch = try container.decodeIfPresent(Bool.self, forKey: .maintainPitch) ?? true

        let blendName = try container.decodeIfPresent(String.self, forKey: .blendMode)
        blendMode = blendName.flatMap { FrameBlendMode(rawValue: $0) } ?? .none

        rampKeyframes = try container.decodeIfPresent([SpeedKeyframe].self, forKey: .rampKeyframes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(speedMultiplier, forKey: .speedMultiplier)
        try container.encode(isReverse, forKey: .isReverse)
        try container.encode(maintainPitch, forKey: .maintainPitch)
        try container.encode(blendMode.rawValue, forKey: .blendMode)
        try container.encode(rampKeyframes, forKey: .rampKeyframes)
    }
}
