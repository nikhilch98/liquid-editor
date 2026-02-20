import Foundation

// MARK: - AudioDuckingConfig

/// Configuration for automatic audio ducking.
///
/// When enabled, automatically reduces volume on a target track
/// (e.g., music) when audio is detected on a trigger track
/// (e.g., voiceover).
struct AudioDuckingConfig: Codable, Equatable, Hashable, Sendable {
    /// Whether ducking is enabled.
    let isEnabled: Bool

    /// Target track ID to duck (usually music track).
    let targetTrackId: String

    /// Trigger track ID (usually voiceover track).
    let triggerTrackId: String

    /// Amount to reduce volume in dB (negative value, e.g., -12).
    let duckAmountDB: Double

    /// Attack time: how fast to duck (milliseconds).
    let attackMs: Int

    /// Release time: how fast to restore (milliseconds).
    let releaseMs: Int

    /// Threshold for speech detection (0.0 - 1.0).
    let speechThreshold: Double

    init(
        isEnabled: Bool = true,
        targetTrackId: String,
        triggerTrackId: String,
        duckAmountDB: Double = -12.0,
        attackMs: Int = 200,
        releaseMs: Int = 500,
        speechThreshold: Double = 0.3
    ) {
        precondition(attackMs > 0, "attackMs must be positive")
        precondition(releaseMs > 0, "releaseMs must be positive")
        precondition((0.0...1.0).contains(speechThreshold), "speechThreshold must be in range 0.0-1.0")

        self.isEnabled = isEnabled
        self.targetTrackId = targetTrackId
        self.triggerTrackId = triggerTrackId
        self.duckAmountDB = duckAmountDB
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.speechThreshold = speechThreshold
    }

    /// The ducking volume as a linear multiplier.
    ///
    /// Converts dB to linear: 10^(dB/20).
    var duckVolumeLinear: Double {
        guard duckAmountDB < 0 else { return 1.0 }
        return min(max(pow(10.0, duckAmountDB / 20.0), 0.0), 1.0)
    }

    /// Create a copy with optional overrides.
    func with(
        isEnabled: Bool? = nil,
        targetTrackId: String? = nil,
        triggerTrackId: String? = nil,
        duckAmountDB: Double? = nil,
        attackMs: Int? = nil,
        releaseMs: Int? = nil,
        speechThreshold: Double? = nil
    ) -> AudioDuckingConfig {
        let newDuckAmountDB = duckAmountDB ?? self.duckAmountDB
        let newAttackMs = attackMs ?? self.attackMs
        let newReleaseMs = releaseMs ?? self.releaseMs
        let newSpeechThreshold = speechThreshold ?? self.speechThreshold

        precondition(newAttackMs > 0, "attackMs must be positive")
        precondition(newReleaseMs > 0, "releaseMs must be positive")
        precondition((0.0...1.0).contains(newSpeechThreshold), "speechThreshold must be in range 0.0-1.0")

        return AudioDuckingConfig(
            isEnabled: isEnabled ?? self.isEnabled,
            targetTrackId: targetTrackId ?? self.targetTrackId,
            triggerTrackId: triggerTrackId ?? self.triggerTrackId,
            duckAmountDB: newDuckAmountDB,
            attackMs: newAttackMs,
            releaseMs: newReleaseMs,
            speechThreshold: newSpeechThreshold
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case targetTrackId
        case triggerTrackId
        case duckAmountDB
        case attackMs
        case releaseMs
        case speechThreshold
    }
}
