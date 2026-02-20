import Foundation

// MARK: - FadeCurveType

/// Type of fade curve.
enum FadeCurveType: String, Codable, CaseIterable, Sendable {
    /// Straight line (0 to 1 or 1 to 0).
    case linear

    /// Slow start, fast finish (perceptual loudness curve).
    case logarithmic

    /// S-shaped curve (slow start, fast middle, slow end).
    case sCurve

    /// Equal power crossfade (constant perceived loudness).
    case equalPower

    /// Exponential (fast start, slow finish).
    case exponential

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .linear: "Linear"
        case .logarithmic: "Logarithmic"
        case .sCurve: "S-Curve"
        case .equalPower: "Equal Power"
        case .exponential: "Exponential"
        }
    }
}

// MARK: - AudioFade

/// Immutable audio fade descriptor.
///
/// Represents a fade-in or fade-out with a duration and curve shape.
/// The gain at any normalized position (0.0 to 1.0) can be computed
/// using ``gainAtNormalized(_:)``.
///
/// For fade-in: t=0 -> silent, t=1 -> full volume.
/// For fade-out: use ``fadeOutGainAtNormalized(_:)``.
struct AudioFade: Codable, Equatable, Hashable, Sendable {
    /// Duration of the fade in microseconds.
    let durationMicros: TimeMicros

    /// Curve shape for the fade.
    let curveType: FadeCurveType

    init(
        durationMicros: TimeMicros,
        curveType: FadeCurveType = .sCurve
    ) {
        precondition(durationMicros >= Self.minDurationMicros && durationMicros <= Self.maxDurationMicros,
                     "durationMicros must be in range \(Self.minDurationMicros)...\(Self.maxDurationMicros)")
        self.durationMicros = durationMicros
        self.curveType = curveType
    }

    /// Default fade in (500ms, S-curve).
    static let defaultFadeIn = AudioFade(
        durationMicros: 500_000,
        curveType: .sCurve
    )

    /// Default fade out (500ms, S-curve).
    static let defaultFadeOut = AudioFade(
        durationMicros: 500_000,
        curveType: .sCurve
    )

    /// Minimum fade duration (~2 frames at 30fps).
    static let minDurationMicros: TimeMicros = 66_666

    /// Maximum fade duration (10 seconds).
    static let maxDurationMicros: TimeMicros = 10_000_000

    /// Duration in seconds.
    var durationSeconds: Double { Double(durationMicros) / 1_000_000.0 }

    /// Compute gain multiplier at normalized position t (0.0 to 1.0).
    ///
    /// For fade-in: t=0 -> 0.0 (silent), t=1 -> 1.0 (full volume).
    func gainAtNormalized(_ t: Double) -> Double {
        let clamped = min(max(t, 0.0), 1.0)
        switch curveType {
        case .linear:
            return clamped
        case .logarithmic:
            // Perceptual loudness curve: sqrt(t)
            return sqrt(clamped)
        case .sCurve:
            // Hermite S-curve: 3t^2 - 2t^3
            return 3 * clamped * clamped - 2 * clamped * clamped * clamped
        case .equalPower:
            // Sine curve for constant perceived loudness
            return sin(clamped * .pi / 2)
        case .exponential:
            // Quadratic (fast start, slow finish)
            return clamped * clamped
        }
    }

    /// Compute the fade-out gain at normalized position t.
    ///
    /// t=0 -> 1.0 (full volume), t=1 -> 0.0 (silent).
    func fadeOutGainAtNormalized(_ t: Double) -> Double {
        gainAtNormalized(1.0 - min(max(t, 0.0), 1.0))
    }

    /// Create a copy with optional overrides.
    func with(
        durationMicros: TimeMicros? = nil,
        curveType: FadeCurveType? = nil
    ) -> AudioFade {
        let newDuration = durationMicros ?? self.durationMicros
        precondition(newDuration >= Self.minDurationMicros && newDuration <= Self.maxDurationMicros,
                     "durationMicros must be in range \(Self.minDurationMicros)...\(Self.maxDurationMicros)")
        return AudioFade(
            durationMicros: newDuration,
            curveType: curveType ?? self.curveType
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case durationMicros
        case curveType
    }
}
