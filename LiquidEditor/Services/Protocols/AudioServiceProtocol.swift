// AudioServiceProtocol.swift
// LiquidEditor
//
// Protocols for audio effects, waveform extraction, and voiceover recording.
// Enables dependency injection and testability.

import Foundation

// MARK: - AudioEffectsProtocol

/// Protocol for real-time audio effects processing via AVAudioEngine.
///
/// Implementations manage per-clip effect chains that process audio
/// in real-time during playback. Parameters can be updated without
/// rebuilding the chain.
///
/// References:
/// - `AudioEffect` from Models/Audio/AudioEffect.swift
/// - `ParameterValue` from Models/Effects/EffectParameter.swift
protocol AudioEffectsProtocol: Sendable {
    /// Initialize the audio engine and prepare for playback.
    ///
    /// Must be called before setting up any effect chains.
    func initialize() async throws

    /// Set up an effects chain for a clip.
    ///
    /// Creates AVAudioUnit nodes for each effect and connects them
    /// in the audio graph.
    ///
    /// - Parameters:
    ///   - clipId: Identifier of the clip to attach effects to.
    ///   - effects: Ordered list of audio effects for the chain.
    func setupEffectChain(clipId: String, effects: [AudioEffect]) async throws

    /// Remove the effects chain for a clip.
    ///
    /// Disconnects and deallocates all audio nodes for the clip.
    ///
    /// - Parameter clipId: Identifier of the clip.
    func removeEffectChain(clipId: String) async throws

    /// Update effect parameters in real-time during playback.
    ///
    /// Parameter changes are applied immediately without rebuilding
    /// the audio graph.
    ///
    /// - Parameters:
    ///   - clipId: Identifier of the clip.
    ///   - effectId: Identifier of the effect within the chain.
    ///   - params: Dictionary of parameter name to new value.
    func updateEffectParameter(
        clipId: String,
        effectId: String,
        params: [String: ParameterValue]
    ) async throws

    /// Shutdown the audio engine and release all resources.
    func shutdown() async
}

// MARK: - WaveformExtractorProtocol

/// Protocol for extracting waveform peak data from audio assets.
///
/// Implementations read audio samples and compute peak amplitude
/// values at the requested level of detail.
protocol WaveformExtractorProtocol: Sendable {
    /// Extract waveform peaks from an audio asset.
    ///
    /// - Parameters:
    ///   - assetURL: URL of the audio or video file.
    ///   - levelOfDetail: Desired sampling resolution.
    /// - Returns: Waveform peak data.
    /// - Throws: If the asset cannot be read or has no audio track.
    func extractWaveform(
        assetURL: URL,
        levelOfDetail: WaveformLOD
    ) async throws -> WaveformData
}

// MARK: - WaveformLOD

/// Waveform level of detail (sampling resolution).
enum WaveformLOD: Sendable {
    /// Low resolution: 1 sample per 100ms. Fast, for overview display.
    case low

    /// Medium resolution: 1 sample per 10ms. Balanced.
    case medium

    /// High resolution: 1 sample per 1ms. Detailed, for zoomed-in views.
    case high
}

// MARK: - VoiceoverRecorderProtocol

/// Protocol for voiceover recording via the device microphone.
///
/// Implementations manage AVAudioSession and AVAudioEngine for
/// recording audio with monitoring support.
protocol VoiceoverRecorderProtocol: Sendable {
    /// Prepare the recording session.
    ///
    /// Configures AVAudioSession and sets up the recording pipeline.
    ///
    /// - Parameters:
    ///   - outputURL: File URL to write the recorded audio to.
    ///   - sampleRate: Desired sample rate in Hz.
    func prepare(outputURL: URL, sampleRate: Double) async throws

    /// Start recording.
    ///
    /// Must call `prepare` first.
    func start() async throws

    /// Stop recording and finalize the output file.
    ///
    /// - Returns: Information about the recorded file.
    func stop() async throws -> RecordingResult

    /// Get the current input level from the microphone.
    ///
    /// - Returns: Normalized input level (0.0-1.0).
    func getInputLevel() async -> Float

    /// Enable or disable audio monitoring (playback through speakers/headphones).
    ///
    /// - Parameter enabled: Whether to enable monitoring.
    func setMonitoring(enabled: Bool) async throws
}

// MARK: - RecordingResult

/// Result of a voiceover recording session.
struct RecordingResult: Sendable {
    /// URL of the recorded audio file.
    let fileURL: URL

    /// Duration of the recording in microseconds.
    let duration: TimeMicros

    /// File size in bytes.
    let fileSize: Int64
}
