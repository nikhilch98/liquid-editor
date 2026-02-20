// SlowMotionService.swift
// LiquidEditor
//
// Detects high-fps video sources and computes optimal slow-motion
// SpeedConfig values. High-fps sources (120/240fps) can slow down
// natively without interpolation. Standard-fps sources need optical
// flow interpolation for quality slow motion.

import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "LiquidEditor", category: "SlowMotionService")

// MARK: - HighFpsDetectionResult

/// Result of high-fps source detection.
struct HighFpsDetectionResult: Sendable {
    /// Detected source frame rate.
    let sourceFrameRate: Double

    /// Whether the source is high-fps (≥ 60fps).
    let isHighFps: Bool

    /// Maximum native slow-motion factor without interpolation.
    ///
    /// For 120fps source at 30fps output: 4.0x slow-mo.
    /// For 240fps source at 30fps output: 8.0x slow-mo.
    /// For standard-fps source: 1.0 (no native slow-mo).
    let maxNativeSlowMo: Double

    /// Recommended SpeedConfig for best quality slow-mo.
    let recommendedConfig: SpeedConfig
}

// MARK: - SlowMotionService

/// Detects high-fps sources and applies optimal slow-motion configurations.
///
/// High-fps sources (≥ 60fps) can use native frame resampling up to their
/// native limit. Beyond that limit — or for standard-fps sources — optical
/// flow interpolation is required for smooth results.
final class SlowMotionService: Sendable {

    // MARK: - Constants

    /// Standard output frame rate for slow-motion calculations.
    static let standardOutputFps: Double = 30.0

    /// Frame rate threshold above which a source is considered high-fps.
    static let highFpsThreshold: Double = 60.0

    // MARK: - Singleton

    static let shared = SlowMotionService()
    private init() {}

    // MARK: - Detection

    /// Detect whether a video asset is high-fps.
    ///
    /// Reads the nominal frame rate from the asset's video track.
    /// Returns a detection result with recommended slow-motion settings.
    ///
    /// - Parameter asset: The AVAsset to inspect.
    /// - Returns: Detection result with frame rate and recommended config.
    func detectHighFps(asset: AVAsset) async -> HighFpsDetectionResult {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else {
                logger.warning("No video track found, falling back to standard fps")
                return buildResult(fps: Self.standardOutputFps)
            }
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let fps = Double(nominalFrameRate)
            logger.debug("Detected source frame rate: \(fps, privacy: .public) fps")
            return buildResult(fps: fps)
        } catch {
            logger.error("Failed to detect frame rate: \(error.localizedDescription, privacy: .public)")
            return buildResult(fps: Self.standardOutputFps)
        }
    }

    /// Detect whether a video at the given URL is high-fps.
    ///
    /// - Parameter url: URL of the video file.
    /// - Returns: Detection result with frame rate and recommended config.
    func detectHighFps(url: URL) async -> HighFpsDetectionResult {
        let asset = AVURLAsset(url: url)
        return await detectHighFps(asset: asset)
    }

    // MARK: - Slow Motion Application

    /// Compute optimal SpeedConfig for applying slow motion to a clip.
    ///
    /// For high-fps sources, uses native frame resampling up to the
    /// native slow-mo limit. Beyond the limit, or for standard-fps
    /// sources, optical flow interpolation is used.
    ///
    /// - Parameters:
    ///   - sourceFrameRate: The clip's source frame rate.
    ///   - slowFactor: Desired speed multiplier (0.1 = 10x slower, 1.0 = real time).
    ///                 Must be in range [0.1, 1.0] for slow motion.
    /// - Returns: Optimized SpeedConfig for the given parameters.
    func applySlowMotion(sourceFrameRate: Double, slowFactor: Double) -> SpeedConfig {
        let clamped = max(0.1, min(1.0, slowFactor))
        let isHighFps = sourceFrameRate >= Self.highFpsThreshold

        if isHighFps {
            let maxNative = sourceFrameRate / Self.standardOutputFps
            let requestedSlowMo = 1.0 / clamped

            if requestedSlowMo <= maxNative {
                // Pure native slow-mo — no interpolation needed.
                return SpeedConfig(
                    speedMultiplier: clamped,
                    maintainPitch: true,
                    blendMode: .none
                )
            } else {
                // Beyond native limit — use optical flow for extra frames.
                return SpeedConfig(
                    speedMultiplier: clamped,
                    maintainPitch: true,
                    blendMode: .opticalFlow
                )
            }
        }

        // Standard fps: quality depends on how much slow-mo is requested.
        let blendMode: FrameBlendMode = clamped >= 0.5 ? .blend : .opticalFlow
        return SpeedConfig(
            speedMultiplier: clamped,
            maintainPitch: true,
            blendMode: blendMode
        )
    }

    // MARK: - Private

    /// Build a detection result for a given frame rate.
    ///
    /// Internal for testability via `@testable import`.
    func buildResult(fps: Double) -> HighFpsDetectionResult {
        let isHighFps = fps >= Self.highFpsThreshold
        let maxNativeSlowMo = isHighFps ? fps / Self.standardOutputFps : 1.0

        let recommended: SpeedConfig
        if isHighFps {
            // Recommend half of native slow-mo (e.g., 120fps → 0.25x speed = 4x slow).
            let halfNative = maxNativeSlowMo / 2.0
            let clampedMultiplier = max(0.1, min(1.0, 1.0 / halfNative))
            recommended = SpeedConfig(
                speedMultiplier: clampedMultiplier,
                maintainPitch: true,
                blendMode: .none
            )
        } else {
            // Standard fps: recommend 0.5x with optical flow.
            recommended = SpeedConfig(
                speedMultiplier: 0.5,
                maintainPitch: true,
                blendMode: .opticalFlow
            )
        }

        return HighFpsDetectionResult(
            sourceFrameRate: fps,
            isHighFps: isHighFps,
            maxNativeSlowMo: maxNativeSlowMo,
            recommendedConfig: recommended
        )
    }
}
