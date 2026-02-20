// SpeedProcessor.swift
// LiquidEditor
//
// Speed processing service for video export.
// Handles uniform speed changes, variable speed ramps (keyframes),
// reverse playback, and audio time pitch algorithm selection.

import AVFoundation
import CoreMedia
import Foundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "SpeedProcessor")

// MARK: - SpeedProcessor

/// Speed processing service for video composition and export.
///
/// Provides static methods for applying speed changes to composition
/// tracks, building time remappings for variable speed, and determining
/// audio pitch algorithm based on speed.
///
/// Thread Safety:
/// - All methods are stateless (pure functions).
/// - Safe to call from any thread.
enum SpeedProcessor {

    // MARK: - Uniform Speed

    /// Apply uniform speed change to a composition track.
    ///
    /// Uses `scaleTimeRange` for simple time remapping.
    ///
    /// - Parameters:
    ///   - track: The composition track to modify.
    ///   - sourceTimeRange: The original time range of the clip.
    ///   - config: Speed configuration.
    /// - Returns: The new duration after speed change.
    static func applyUniformSpeed(
        track: AVMutableCompositionTrack,
        sourceTimeRange: CMTimeRange,
        config: SpeedConfig
    ) -> CMTime {
        guard config.speedMultiplier != 1.0 else { return sourceTimeRange.duration }

        // Validate speed multiplier is positive and within reasonable bounds
        guard config.speedMultiplier > 0 && config.speedMultiplier < 100 else {
            logger.error("Invalid speed multiplier: \(config.speedMultiplier, privacy: .public). Must be > 0 and < 100.")
            return sourceTimeRange.duration
        }

        let newDuration = CMTimeMultiplyByFloat64(
            sourceTimeRange.duration,
            multiplier: 1.0 / config.speedMultiplier
        )

        track.scaleTimeRange(sourceTimeRange, toDuration: newDuration)

        return newDuration
    }

    // MARK: - Audio Pitch Algorithm

    /// Configure audio pitch algorithm based on speed config.
    ///
    /// Uses `.spectral` for pitch-preserving playback at speeds up to 4.0x.
    /// Above 4.0x, switches to `.varispeed` as spectral algorithms become
    /// unstable at extreme speeds and introduce artifacts.
    ///
    /// - Parameter config: The speed configuration.
    /// - Returns: The appropriate audio time pitch algorithm.
    static func audioPitchAlgorithm(for config: SpeedConfig) -> AVAudioTimePitchAlgorithm {
        // Spectral pitch preservation becomes unstable above 4.0x speed
        guard config.speedMultiplier <= 4.0 else { return .varispeed }

        if config.maintainPitch {
            return .spectral
        } else {
            return .varispeed
        }
    }

    /// Determine if audio should be muted at this speed.
    static func shouldMuteAudio(config: SpeedConfig) -> Bool {
        config.speedMultiplier > 4.0 || config.speedMultiplier < 0.1
    }

    // MARK: - Variable Speed (Speed Ramp)

    /// Build time remapping for variable speed (speed ramps).
    ///
    /// Maps each output frame time to a source frame time based
    /// on the speed curve defined by keyframes.
    ///
    /// - Parameters:
    ///   - config: Speed configuration with ramp keyframes.
    ///   - sourceDuration: Duration of the source clip.
    ///   - outputFrameRate: Frame rate of the output video.
    /// - Returns: Array of (outputTime, sourceTime) mappings.
    static func buildTimeRemapping(
        config: SpeedConfig,
        sourceDuration: CMTime,
        outputFrameRate: Double = 30.0
    ) -> [(outputTime: CMTime, sourceTime: CMTime)] {
        guard !config.rampKeyframes.isEmpty else { return [] }

        // Validate frame rate is positive
        guard outputFrameRate > 0 else {
            logger.error("Invalid frame rate: \(outputFrameRate, privacy: .public). Must be > 0.")
            return []
        }

        var mapping: [(outputTime: CMTime, sourceTime: CMTime)] = []

        let frameDuration = 1.0 / outputFrameRate
        let sourceDurationSec = CMTimeGetSeconds(sourceDuration)

        var sourceAccumulator: Double = 0.0
        var outputTime: Double = 0.0

        while sourceAccumulator < sourceDurationSec {
            let timeMicros = TimeMicros(sourceAccumulator * 1_000_000)
            let speed = config.speedAtTime(timeMicros)

            mapping.append((
                outputTime: CMTime(seconds: outputTime, preferredTimescale: 600),
                sourceTime: CMTime(seconds: sourceAccumulator, preferredTimescale: 600)
            ))

            sourceAccumulator += frameDuration * speed
            outputTime += frameDuration
        }

        return mapping
    }

    // MARK: - Reverse Playback

    /// Apply reverse playback by reversing the time mapping.
    ///
    /// Creates a composition that plays frames in reverse order
    /// by inserting segments with reversed time ranges.
    ///
    /// - Parameters:
    ///   - composition: The mutable composition.
    ///   - track: The video track to reverse.
    ///   - sourceTrack: The original source track.
    ///   - sourceTimeRange: The time range to reverse.
    ///   - frameRate: Frame rate for segmented reversal.
    /// - Throws: AVFoundation errors if time range insertion fails.
    static func applyReverse(
        composition: AVMutableComposition,
        track: AVMutableCompositionTrack,
        sourceTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange,
        frameRate: Double = 30.0
    ) throws {
        // Validate frame rate is positive
        guard frameRate > 0 else {
            logger.error("Invalid frame rate for reverse: \(frameRate, privacy: .public). Must be > 0.")
            throw NSError(
                domain: "SpeedProcessor",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid frame rate: \(frameRate)"]
            )
        }

        track.removeTimeRange(CMTimeRange(start: .zero, duration: composition.duration))

        let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let totalFrames = Int(CMTimeGetSeconds(sourceTimeRange.duration) * frameRate)

        var insertTime = CMTime.zero

        for i in stride(from: totalFrames - 1, through: 0, by: -1) {
            let frameTime = CMTimeAdd(
                sourceTimeRange.start,
                CMTimeMultiplyByFloat64(frameDuration, multiplier: Double(i))
            )
            let range = CMTimeRange(start: frameTime, duration: frameDuration)

            // Propagate errors instead of catching
            try track.insertTimeRange(range, of: sourceTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, frameDuration)
        }
    }

    // MARK: - Effective Duration

    /// Calculate the effective output duration after speed changes.
    ///
    /// - Parameters:
    ///   - sourceDuration: Original clip duration.
    ///   - config: Speed configuration.
    /// - Returns: Effective output duration.
    static func effectiveDuration(
        sourceDuration: CMTime,
        config: SpeedConfig
    ) -> CMTime {
        // Validate source duration is positive
        guard CMTimeGetSeconds(sourceDuration) > 0 else {
            logger.error("Invalid source duration: \(CMTimeGetSeconds(sourceDuration), privacy: .public). Must be > 0.")
            return .zero
        }

        if config.rampKeyframes.isEmpty {
            return CMTimeMultiplyByFloat64(
                sourceDuration,
                multiplier: 1.0 / config.speedMultiplier
            )
        }

        let mapping = buildTimeRemapping(
            config: config,
            sourceDuration: sourceDuration
        )

        guard let lastMapping = mapping.last else {
            return CMTimeMultiplyByFloat64(
                sourceDuration,
                multiplier: 1.0 / config.speedMultiplier
            )
        }

        return lastMapping.outputTime
    }

    /// Calculate effective duration using microseconds.
    ///
    /// - Parameters:
    ///   - sourceDurationMicros: Source clip duration in microseconds.
    ///   - config: Speed configuration.
    /// - Returns: Effective output duration in microseconds.
    static func effectiveDurationMicros(
        sourceDurationMicros: TimeMicros,
        config: SpeedConfig
    ) -> TimeMicros {
        config.effectiveDurationMicros(sourceDurationMicros)
    }
}
