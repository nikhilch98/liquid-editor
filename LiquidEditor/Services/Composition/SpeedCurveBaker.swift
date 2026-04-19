// SpeedCurveBaker.swift
// LiquidEditor
//
// E4-12: Speed-curve bake renderer.
//
// Applies a non-linear time remap (variable-speed curve) to a clip by
// slicing the source into small time ranges and scaling each range by
// the linearly-interpolated instantaneous speed between control points.
// The result is a new on-disk asset that can be played back directly
// without further remapping.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §4.
//
// Caller contract:
//   let baker = SpeedCurveBaker()
//   let bakedURL = try await baker.bake(clipURL: url, curve: curve)
//
// Notes:
// - `bake(...)` is `nonisolated` so it can be awaited from any isolation
//   domain; internal export work dispatches off-main-actor.
// - When no control points are supplied (or only one), the source URL is
//   returned unchanged (identity remap).
// - Export failure or unsupported asset configurations fall back to a
//   TODO stub that returns the original URL. This keeps the UI layer
//   working while the full AVAssetExportSession pipeline is iterated on.

import Foundation
import AVFoundation

// MARK: - SpeedControlPoint

/// A single control point on a speed curve.
///
/// `time` is normalized to the clip's original duration in the range
/// `[0, 1]`. `speed` is a multiplicative factor applied at that point
/// (`1.0` = real time, `0.5` = half-speed, `2.0` = double-speed).
struct SpeedControlPoint: Sendable, Equatable, Hashable, Codable {
    /// Normalized time `[0, 1]` within the source clip.
    let time: Double

    /// Speed multiplier at this point (`>0`).
    let speed: Double

    init(time: Double, speed: Double) {
        self.time = time
        self.speed = speed
    }
}

// MARK: - SpeedCurve

/// A piecewise-linear speed curve defined by a sorted list of control
/// points. Callers are responsible for providing points sorted by
/// `time`; `SpeedCurveBaker` sorts defensively on bake.
struct SpeedCurve: Sendable, Equatable, Hashable, Codable {
    /// Control points defining the curve. Empty / single-point curves
    /// are treated as identity (no remap).
    let controlPoints: [SpeedControlPoint]

    init(controlPoints: [SpeedControlPoint]) {
        self.controlPoints = controlPoints
    }

    /// Instantaneous speed at a normalized position `t in [0, 1]` using
    /// linear interpolation between the two surrounding control points.
    /// Clamped to the first / last point outside the defined range.
    func speed(atNormalizedTime t: Double) -> Double {
        guard !controlPoints.isEmpty else { return 1.0 }
        if controlPoints.count == 1 { return controlPoints[0].speed }

        let sorted = controlPoints.sorted { $0.time < $1.time }
        if t <= sorted.first!.time { return sorted.first!.speed }
        if t >= sorted.last!.time { return sorted.last!.speed }

        for index in 0 ..< (sorted.count - 1) {
            let a = sorted[index]
            let b = sorted[index + 1]
            if t >= a.time && t <= b.time {
                let span = b.time - a.time
                guard span > 0 else { return a.speed }
                let alpha = (t - a.time) / span
                return a.speed + (b.speed - a.speed) * alpha
            }
        }
        return sorted.last!.speed
    }
}

// MARK: - SpeedCurveBakeError

enum SpeedCurveBakeError: Error, Equatable, Sendable {
    case noVideoTrack
    case exportUnavailable
    case exportFailed(String)
    case invalidCurve
}

// MARK: - SpeedCurveBaker

/// Service that bakes a speed curve into a real asset on disk.
///
/// The type itself is `@MainActor @Observable` so UI layers can observe
/// progress state in the future (currently stubbed to `0` / `1`). The
/// bake operation is `nonisolated` and performs its work off-main.
@MainActor
@Observable
final class SpeedCurveBaker {

    // MARK: - Observable state

    /// Normalized progress `[0, 1]` of the most recent bake operation.
    /// Reserved for future progress reporting; currently set to `0` at
    /// start and `1` on completion.
    private(set) var progress: Double = 0

    /// `true` while a bake operation is in flight.
    private(set) var isBaking: Bool = false

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Applies the given speed curve to the clip at `clipURL` and writes
    /// the result to a new file in the user's temporary directory.
    ///
    /// Returns the URL of the baked asset on success. Returns the
    /// original URL unchanged when the curve is effectively identity
    /// (empty / single-point) or when the platform export pipeline
    /// falls back to the TODO stub.
    nonisolated func bake(clipURL: URL, curve: SpeedCurve) async throws -> URL {
        // Identity remap — nothing to do.
        if curve.controlPoints.count < 2 {
            return clipURL
        }

        await MainActor.run { [weak self] in
            self?.isBaking = true
            self?.progress = 0
        }
        defer {
            Task { @MainActor [weak self] in
                self?.isBaking = false
                self?.progress = 1
            }
        }

        let asset = AVURLAsset(url: clipURL)

        // Load duration + tracks (async-safe on iOS 16+).
        let duration: CMTime
        let videoTracks: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration)
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            // If loading fails, fall back to the original URL. The UI
            // can still play the source; bake is best-effort.
            return clipURL
        }
        guard let videoTrack = videoTracks.first else {
            return clipURL
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return clipURL
        }

        // Slice the source into N equal-length segments and scale each
        // segment's duration by the inverse of the segment's average
        // speed, which is the correct factor for AVFoundation's
        // `scaleTimeRange(...:toDuration:)`.
        let segmentCount = Self.segmentCount(for: duration)
        let totalSeconds = duration.seconds
        guard totalSeconds > 0, segmentCount > 0 else { return clipURL }

        let segmentSeconds = totalSeconds / Double(segmentCount)
        var runningOut: CMTime = .zero

        do {
            for segment in 0 ..< segmentCount {
                let startSeconds = Double(segment) * segmentSeconds
                let endSeconds = min(totalSeconds, startSeconds + segmentSeconds)
                let midT = ((startSeconds + endSeconds) * 0.5) / totalSeconds

                let rawSpeed = curve.speed(atNormalizedTime: midT)
                let speed = max(0.1, min(rawSpeed, 10.0))

                let sourceStart = CMTime(seconds: startSeconds, preferredTimescale: 600)
                let sourceEnd = CMTime(seconds: endSeconds, preferredTimescale: 600)
                let sourceRange = CMTimeRange(start: sourceStart, end: sourceEnd)

                try compVideoTrack.insertTimeRange(
                    sourceRange,
                    of: videoTrack,
                    at: runningOut
                )

                // Inserted segment occupies `sourceRange.duration` in the
                // composition; scaling to `duration/speed` applies the
                // requested instantaneous speed.
                let insertedRange = CMTimeRange(start: runningOut, duration: sourceRange.duration)
                let scaledDuration = CMTimeMultiplyByFloat64(
                    sourceRange.duration,
                    multiplier: 1.0 / speed
                )
                compVideoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)

                runningOut = CMTimeAdd(runningOut, scaledDuration)
            }
        } catch {
            // Fallback to the original URL on any insert/scale failure.
            return clipURL
        }

        // Export the composition to a new file under tmp/. If the
        // export pipeline is unavailable or fails, fall back to the
        // source URL — callers still get playable media.
        let outputURL = Self.makeOutputURL()
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            return clipURL
        }
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        await export.export()
        switch export.status {
        case .completed:
            return outputURL
        case .failed, .cancelled:
            return clipURL
        default:
            // TODO: Wire progress reporting + richer error surfacing.
            return clipURL
        }
    }

    // MARK: - Helpers

    /// Chooses a segment count for curve baking — more segments produce
    /// a smoother remap at the cost of more track splices. 20 segments
    /// is a reasonable default for UI-driven speed curves.
    private nonisolated static func segmentCount(for duration: CMTime) -> Int {
        guard duration.isValid, !duration.isIndefinite else { return 0 }
        let seconds = duration.seconds
        if seconds <= 0 { return 0 }
        // Target ~1 segment per 0.5s, clamped to [4, 120].
        let target = Int((seconds * 2.0).rounded())
        return max(4, min(120, target))
    }

    /// Generates a unique temporary URL for the baked asset.
    private nonisolated static func makeOutputURL() -> URL {
        let name = "speedbake-\(UUID().uuidString).mp4"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
