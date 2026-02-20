// AudioMixerService.swift
// LiquidEditor
//
// Manages audio mixing: per-clip volume, pan, mute,
// volume envelope application, fade curves, and auto-ducking.
//
// Thread Safety:
// - `@Observable @MainActor` since it drives UI state (ducking config).
// - Static methods are pure and can be called from any context.

import AVFoundation
import Foundation
import Observation

// MARK: - SpeechSegment

/// A time range representing detected speech.
struct SpeechSegment: Sendable, Equatable {
    /// Start time in microseconds.
    let start: TimeMicros

    /// End time in microseconds.
    let end: TimeMicros
}

// MARK: - AudioMixerError

/// Errors thrown by AudioMixerService operations.
enum AudioMixerError: Error, LocalizedError, Sendable {
    case speechDetectionFailed(String)
    case effectChainSetupFailed(String)
    case effectChainRemovalFailed(String)
    case effectPreviewFailed(String)

    var errorDescription: String? {
        switch self {
        case .speechDetectionFailed(let reason):
            "Speech detection failed: \(reason)"
        case .effectChainSetupFailed(let reason):
            "Failed to setup effect chain: \(reason)"
        case .effectChainRemovalFailed(let reason):
            "Failed to remove effect chain: \(reason)"
        case .effectPreviewFailed(let reason):
            "Failed to preview effect: \(reason)"
        }
    }
}

// MARK: - AudioMixerService

/// Manages audio mixing: per-clip volume, fade curves, envelopes, and auto-ducking.
///
/// ## Volume Computation
///
/// The effective volume at a given clip-relative time is:
/// ```
/// clipVolume * fadeMultiplier * envelopeMultiplier * (isMuted ? 0 : 1)
/// ```
/// Track volume is applied separately at the composition level.
///
/// ## Ducking
///
/// Auto-ducking reduces a target track's volume when speech is detected
/// on a trigger track. The generated ducking envelope uses attack/release
/// ramps to smoothly duck and restore volume.
@Observable
@MainActor
final class AudioMixerService {

    // MARK: - Properties

    /// Current ducking configuration.
    private(set) var duckingConfig: AudioDuckingConfig?

    /// Whether ducking is active.
    var isDuckingActive: Bool {
        duckingConfig?.isEnabled == true
    }

    // MARK: - Volume Computation

    /// Compute the effective volume at a given clip-relative time.
    ///
    /// The final volume is:
    /// `clipVolume * fadeMultiplier * envelopeMultiplier * (isMuted ? 0 : 1)`
    ///
    /// Track volume is applied separately at the composition level.
    ///
    /// - Parameters:
    ///   - clipVolume: Base volume for the clip (0.0 to 2.0).
    ///   - isMuted: Whether the clip is muted.
    ///   - timeMicros: Current time position relative to clip start (microseconds).
    ///   - clipDurationMicros: Total clip duration (microseconds).
    ///   - fadeIn: Optional fade-in descriptor.
    ///   - fadeOut: Optional fade-out descriptor.
    ///   - envelope: Optional volume envelope.
    /// - Returns: Effective volume clamped to [0.0, 2.0].
    nonisolated static func computeEffectiveVolume(
        clipVolume: Double,
        isMuted: Bool,
        timeMicros: TimeMicros,
        clipDurationMicros: TimeMicros,
        fadeIn: AudioFade? = nil,
        fadeOut: AudioFade? = nil,
        envelope: VolumeEnvelope? = nil
    ) -> Double {
        guard !isMuted else { return 0.0 }

        var volume = clipVolume

        // Apply fade in
        if let fadeIn, timeMicros < fadeIn.durationMicros {
            let t = Double(timeMicros) / Double(fadeIn.durationMicros)
            volume *= fadeIn.gainAtNormalized(t)
        }

        // Apply fade out
        if let fadeOut {
            let fadeOutStart = clipDurationMicros - fadeOut.durationMicros
            if timeMicros > fadeOutStart {
                let t = Double(timeMicros - fadeOutStart) / Double(fadeOut.durationMicros)
                volume *= fadeOut.fadeOutGainAtNormalized(t)
            }
        }

        // Apply volume envelope
        if let envelope, !envelope.keyframes.isEmpty {
            volume *= envelope.getVolumeAt(timeMicros)
        }

        return min(max(volume, 0.0), 2.0)
    }

    // MARK: - Fade Curve Computation

    /// Generate linearized volume ramp segments for a fade.
    ///
    /// Used by the export pipeline to convert fade curves into
    /// `AVMutableAudioMixInputParameters` volume ramps.
    ///
    /// - Parameters:
    ///   - fade: The fade descriptor.
    ///   - startTimeMicros: Start time of the fade on the timeline (microseconds).
    ///   - isFadeIn: Whether this is a fade-in (true) or fade-out (false).
    ///   - segmentCount: Number of linear segments to generate.
    /// - Returns: Array of (timeMicros, volume) pairs.
    nonisolated static func linearizeFade(
        fade: AudioFade,
        startTimeMicros: TimeMicros,
        isFadeIn: Bool,
        segmentCount: Int = 8
    ) -> [(time: TimeMicros, volume: Double)] {
        var points: [(time: TimeMicros, volume: Double)] = []
        points.reserveCapacity(segmentCount + 1)

        for i in 0...segmentCount {
            let t = Double(i) / Double(segmentCount)
            let time = startTimeMicros + TimeMicros(Double(fade.durationMicros) * t)
            let gain = isFadeIn
                ? fade.gainAtNormalized(t)
                : fade.fadeOutGainAtNormalized(t)
            points.append((time: time, volume: gain))
        }

        return points
    }

    /// Generate linearized volume ramp segments for a volume envelope.
    ///
    /// Converts bezier/hold interpolation to linear segments
    /// for `AVMutableAudioMixInputParameters`.
    ///
    /// - Parameters:
    ///   - envelope: The volume envelope.
    ///   - segmentsPerSpan: Number of linear segments per keyframe span.
    /// - Returns: Array of (timeMicros, volume) pairs.
    nonisolated static func linearizeEnvelope(
        envelope: VolumeEnvelope,
        segmentsPerSpan: Int = 8
    ) -> [(time: TimeMicros, volume: Double)] {
        guard !envelope.keyframes.isEmpty else { return [] }
        if envelope.keyframes.count == 1 {
            let kf = envelope.keyframes[0]
            return [(time: kf.time, volume: kf.volume)]
        }

        var points: [(time: TimeMicros, volume: Double)] = []

        for i in 0..<(envelope.keyframes.count - 1) {
            let start = envelope.keyframes[i]
            let end = envelope.keyframes[i + 1]

            for s in 0...segmentsPerSpan {
                // Skip the first point for all segments except the first
                if s == 0 && i > 0 { continue }

                let t = Double(s) / Double(segmentsPerSpan)
                let time = start.time + TimeMicros(Double(end.time - start.time) * t)
                let vol = start.volume + (end.volume - start.volume) * t
                points.append((time: time, volume: min(max(vol, 0.0), 2.0)))
            }
        }

        return points
    }

    // MARK: - Ducking

    /// Configure auto-ducking.
    ///
    /// - Parameter config: The ducking configuration to apply.
    func configureDucking(_ config: AudioDuckingConfig) {
        duckingConfig = config
    }

    /// Disable auto-ducking.
    func disableDucking() {
        duckingConfig = duckingConfig?.with(isEnabled: false)
    }

    /// Clear ducking configuration.
    func clearDucking() {
        duckingConfig = nil
    }

    /// Generate a ducking envelope from speech segments.
    ///
    /// Returns a `VolumeEnvelope` that ducks the target track
    /// wherever speech is detected on the trigger track.
    ///
    /// - Parameters:
    ///   - speechSegments: Array of speech time ranges.
    ///   - config: The ducking configuration.
    /// - Returns: A volume envelope with duck ramps.
    nonisolated static func generateDuckingEnvelope(
        speechSegments: [SpeechSegment],
        config: AudioDuckingConfig
    ) -> VolumeEnvelope {
        guard !speechSegments.isEmpty, config.isEnabled else {
            return .empty
        }

        var keyframes: [VolumeKeyframe] = []
        let duckVolume = min(max(pow(10.0, config.duckAmountDB / 20.0), 0.0), 1.0)
        var idCounter = 0

        for segment in speechSegments {
            // Ramp down before speech starts
            let rampDownStart = segment.start - TimeMicros(config.attackMs) * 1000
            keyframes.append(VolumeKeyframe(
                id: "duck_\(idCounter)",
                time: max(0, min(rampDownStart, segment.start)),
                volume: 1.0
            ))
            idCounter += 1

            keyframes.append(VolumeKeyframe(
                id: "duck_\(idCounter)",
                time: segment.start,
                volume: duckVolume
            ))
            idCounter += 1

            // Hold during speech
            keyframes.append(VolumeKeyframe(
                id: "duck_\(idCounter)",
                time: segment.end,
                volume: duckVolume
            ))
            idCounter += 1

            // Ramp up after speech ends
            let rampUpEnd = segment.end + TimeMicros(config.releaseMs) * 1000
            keyframes.append(VolumeKeyframe(
                id: "duck_\(idCounter)",
                time: rampUpEnd,
                volume: 1.0
            ))
            idCounter += 1
        }

        return VolumeEnvelope(keyframes: keyframes)
    }
}
