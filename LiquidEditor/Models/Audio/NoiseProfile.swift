import Foundation

// MARK: - NoiseProfile

/// Captured noise profile for noise reduction.
///
/// Holds metadata about a noise sample captured from an audio asset.
/// The actual spectral data is stored on the native side and
/// referenced by `nativeProfileHandle`.
struct NoiseProfile: Codable, Equatable, Hashable, Sendable {
    /// ID for caching and reference.
    let id: String

    /// Source asset ID the profile was captured from.
    let assetId: String

    /// Start time of the noise sample (microseconds).
    let startMicros: TimeMicros

    /// End time of the noise sample (microseconds).
    let endMicros: TimeMicros

    /// Native-side reference handle for the spectral data.
    let nativeProfileHandle: String

    init(
        id: String,
        assetId: String,
        startMicros: TimeMicros,
        endMicros: TimeMicros,
        nativeProfileHandle: String
    ) {
        precondition(endMicros >= startMicros, "endMicros must be >= startMicros")

        self.id = id
        self.assetId = assetId
        self.startMicros = startMicros
        self.endMicros = endMicros
        self.nativeProfileHandle = nativeProfileHandle
    }

    /// Duration of the noise sample in microseconds.
    var durationMicros: TimeMicros { endMicros - startMicros }

    /// Duration in seconds.
    var durationSeconds: Double { Double(durationMicros) / 1_000_000.0 }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case assetId
        case startMicros
        case endMicros
        case nativeProfileHandle
    }

    // MARK: - Equatable / Hashable by ID

    static func == (lhs: NoiseProfile, rhs: NoiseProfile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
