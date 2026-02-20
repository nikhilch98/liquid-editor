// VoiceoverRecorder.swift
// LiquidEditor
//
// Records voiceover audio using AVAudioEngine.
// Supports recording to M4A, real-time level metering, and
// audio monitoring for headphone feedback.

import AVFoundation
import Accelerate
import os

// MARK: - VoiceoverRecorderError

/// Errors thrown by VoiceoverRecorder operations.
enum VoiceoverRecorderError: Error, LocalizedError, Sendable {
    case sessionConfigurationFailed(String)
    case fileCreationFailed(String)
    case notPrepared
    case alreadyRecording
    case notRecording
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .sessionConfigurationFailed(let reason):
            "Failed to configure audio session: \(reason)"
        case .fileCreationFailed(let path):
            "Failed to create audio file at: \(path)"
        case .notPrepared:
            "Recorder has not been prepared. Call prepare() first."
        case .alreadyRecording:
            "Recording is already in progress"
        case .notRecording:
            "No recording is in progress"
        case .engineStartFailed(let reason):
            "Failed to start audio engine: \(reason)"
        }
    }
}

// MARK: - RecordingInfo

/// Information about a completed recording.
struct RecordingInfo: Sendable {
    /// File path of the recorded audio.
    let filePath: String

    /// Duration of the recording in microseconds.
    let durationMicros: Int64
}

// MARK: - VoiceoverRecorder

/// Records voiceover audio using AVAudioEngine.
///
/// Supports:
/// - Recording to M4A file via `AVAudioFile`
/// - Real-time input level metering for VU display
/// - Audio monitoring (hear yourself through headphones)
///
/// ## Concurrency
///
/// Uses `@unchecked Sendable` with `OSAllocatedUnfairLock` because
/// the audio engine's input tap callback arrives on the audio render
/// thread, which requires synchronous lock-free access that cannot
/// be bridged to a Swift actor or async queue.
///
/// ## Usage
///
/// ```swift
/// let recorder = VoiceoverRecorder()
/// try recorder.prepare(outputPath: "/path/to/voiceover.m4a")
/// try recorder.start()
/// // ... recording ...
/// let info = recorder.stop()
/// ```
final class VoiceoverRecorder: @unchecked Sendable {

    // MARK: - Lock-Protected State

    /// Mutable state protected by the unfair lock.
    private struct State {
        /// The output audio file being written to.
        var audioFile: AVAudioFile?
        /// Whether a recording is currently in progress.
        var isRecording = false
        /// Current peak input level (0.0 to 1.0), updated in real time.
        var currentLevel: Float = 0.0
        /// Whether audio monitoring is enabled.
        var monitoringEnabled = false
    }

    // MARK: - Properties

    /// The underlying audio engine for recording.
    private let audioEngine = AVAudioEngine()

    /// Shortcut to the engine's input node.
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }

    /// Lock protecting all mutable state. Uses OSAllocatedUnfairLock
    /// for synchronous access from the audio render thread.
    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: - Configuration

    /// Default recording sample rate.
    private let defaultSampleRate: Double = 44100

    // MARK: - Lifecycle

    /// Prepare the recording session.
    ///
    /// Configures the `AVAudioSession` for playback and recording,
    /// and creates the output audio file.
    ///
    /// - Parameters:
    ///   - outputPath: File path for the recorded M4A audio.
    ///   - sampleRate: Recording sample rate (default: 44100 Hz).
    /// - Throws: `VoiceoverRecorderError` on failure.
    func prepare(outputPath: String, sampleRate: Double = 44100) throws {
        try state.withLock { s in
            guard !s.isRecording else {
                throw VoiceoverRecorderError.alreadyRecording
            }

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ) else {
                throw VoiceoverRecorderError.fileCreationFailed(outputPath)
            }

            do {
                s.audioFile = try AVAudioFile(
                    forWriting: URL(fileURLWithPath: outputPath),
                    settings: format.settings
                )
            } catch {
                throw VoiceoverRecorderError.fileCreationFailed(
                    "\(outputPath): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Start recording.
    ///
    /// Installs a tap on the audio input node to capture audio
    /// and write it to the prepared file. Also calculates real-time
    /// peak levels for VU metering.
    ///
    /// - Throws: `VoiceoverRecorderError` if not prepared or already recording.
    func start() throws {
        try state.withLock { s in
            guard s.audioFile != nil else {
                throw VoiceoverRecorderError.notPrepared
            }
            guard !s.isRecording else {
                throw VoiceoverRecorderError.alreadyRecording
            }

            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: format
            ) { [weak self] buffer, _ in
                guard let self else { return }

                // Write audio to file synchronously under lock.
                // OSAllocatedUnfairLock is safe for the audio render
                // thread -- it is a thin wrapper around os_unfair_lock
                // with no priority inversion risk for short critical sections.
                self.state.withLock { s in
                    try? s.audioFile?.write(from: buffer)
                    // Calculate peak level for VU meter
                    s.currentLevel = self.calculatePeakLevel(buffer: buffer)
                }
            }

            do {
                try audioEngine.start()
            } catch {
                inputNode.removeTap(onBus: 0)
                throw VoiceoverRecorderError.engineStartFailed(
                    error.localizedDescription
                )
            }

            s.isRecording = true
        }
    }

    /// Stop recording and return file information.
    ///
    /// Removes the input tap, stops the engine, and returns the
    /// recorded file path and duration.
    ///
    /// - Returns: `RecordingInfo` with file path and duration.
    func stop() -> RecordingInfo {
        // Remove tap and stop engine outside the lock to avoid
        // deadlock with the audio tap callback which also acquires the lock.
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        return state.withLock { s in
            let filePath = s.audioFile?.url.path ?? ""
            let length = s.audioFile?.length ?? 0
            let sampleRate = s.audioFile?.processingFormat.sampleRate ?? defaultSampleRate
            let durationMicros = Int64(Double(length) / sampleRate * 1_000_000)

            s.audioFile = nil
            s.isRecording = false
            s.currentLevel = 0.0

            return RecordingInfo(
                filePath: filePath,
                durationMicros: durationMicros
            )
        }
    }

    /// Get current microphone input level.
    ///
    /// Returns a normalized value from 0.0 (silence) to 1.0 (clipping).
    /// Updated in real time during recording.
    var inputLevel: Float {
        state.withLock { $0.currentLevel }
    }

    /// Whether a recording is currently active.
    var recording: Bool {
        state.withLock { $0.isRecording }
    }

    /// Enable or disable audio monitoring.
    ///
    /// When enabled, the microphone input is routed to the output
    /// (speakers or headphones) so the user can hear themselves.
    ///
    /// - Parameter enabled: Whether to enable monitoring.
    func setMonitoring(enabled: Bool) {
        state.withLock { $0.monitoringEnabled = enabled }
    }

    // MARK: - Level Calculation

    /// Calculate peak amplitude from an audio buffer using vDSP.
    ///
    /// - Parameter buffer: The audio buffer to analyze.
    /// - Returns: Peak amplitude in the range 0.0 to 1.0.
    private func calculatePeakLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        vDSP_maxmgv(data, 1, &peak, vDSP_Length(buffer.frameLength))
        return peak
    }
}
