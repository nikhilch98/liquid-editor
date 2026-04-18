// VFRHandler.swift
// LiquidEditor
//
// Variable-Frame-Rate (VFR) handling on import (F6-25).
//
// Many phone/action-cam sources record at a variable frame rate. The
// timeline and compositor work best on constant-frame-rate (CFR) clips,
// so we detect VFR on import and (eventually) transcode to CFR.
//
// Current state:
//   - detectVFR(...)                 — implemented (samples first 100
//                                       frames' PTS intervals).
//   - conformToConstantFrameRate(...) — stub returning the original URL
//                                       with a TODO for the AVAssetWriter
//                                       re-encode pipeline.

import AVFoundation
import CoreMedia
import Foundation

// MARK: - VFRHandler

/// Stateless helper for detecting and (later) conforming variable
/// frame rate video assets.
///
/// Marked `@MainActor` for dependency injection symmetry with other
/// media-import services; the core APIs are `nonisolated async` and
/// therefore safe to call from any actor.
@MainActor
enum VFRHandler {

    // MARK: - Constants

    /// Number of frames sampled when probing for VFR.
    nonisolated static let sampleFrameCount = 100

    /// Tolerance for considering two PTS intervals "equal".
    ///
    /// ±1 millisecond — tighter than this and rounding in AV-stack
    /// timescales produces false positives.
    nonisolated static let intervalToleranceSeconds: Double = 0.001

    // MARK: - Errors

    enum VFRError: LocalizedError {
        case noVideoTrack
        case couldNotReadSamples

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "Asset has no video track."
            case .couldNotReadSamples: return "Could not read sample timing information."
            }
        }
    }

    // MARK: - Detection

    /// Returns `true` if the asset's first 100 frames have non-uniform
    /// presentation-time intervals (outside ±1ms), i.e. the asset is VFR.
    ///
    /// Uses `AVAssetReader` with no output settings (pass-through) so
    /// nothing is decoded; we only read sample buffer timings.
    nonisolated static func detectVFR(asset: AVAsset) async throws -> Bool {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw VFRError.noVideoTrack }

        let reader = try AVAssetReader(asset: asset)
        // nil outputSettings -> pass-through, so decoding is skipped.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VFRError.couldNotReadSamples }
        reader.add(output)
        guard reader.startReading() else { throw VFRError.couldNotReadSamples }

        var ptsTimes: [CMTime] = []
        ptsTimes.reserveCapacity(sampleFrameCount)

        while ptsTimes.count < sampleFrameCount,
              let buffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
            if pts.isValid {
                ptsTimes.append(pts)
            }
        }
        reader.cancelReading()

        guard ptsTimes.count >= 2 else {
            // Too few samples to draw any conclusion — assume CFR.
            return false
        }

        // Compute intervals in seconds.
        var intervals: [Double] = []
        intervals.reserveCapacity(ptsTimes.count - 1)
        for i in 1..<ptsTimes.count {
            let delta = CMTimeSubtract(ptsTimes[i], ptsTimes[i - 1])
            let seconds = CMTimeGetSeconds(delta)
            if seconds.isFinite, seconds > 0 {
                intervals.append(seconds)
            }
        }
        guard let first = intervals.first else { return false }

        for interval in intervals.dropFirst() {
            if abs(interval - first) > intervalToleranceSeconds {
                return true
            }
        }
        return false
    }

    // MARK: - Conform (stub)

    /// Re-encode the asset to a constant frame rate at `targetFPS`.
    ///
    /// TODO(F6-25): full AVAssetWriter pipeline.
    ///   1. AVAssetReader(track: video, outputSettings: YUV420 full-range)
    ///   2. AVAssetWriter with H.264/HEVC video + AAC audio inputs.
    ///   3. Resample video frames at `1/targetFPS` cadence, duplicating or
    ///      dropping as needed; remux audio unchanged.
    ///   4. Write to a deterministic temp URL and return it.
    ///
    /// For now we return the asset's original URL unchanged so that the
    /// import path can be wired up end-to-end without blocking on the
    /// encoder. Callers MUST treat the return value as potentially VFR
    /// until the TODO is resolved.
    nonisolated static func conformToConstantFrameRate(
        asset: AVAsset,
        targetFPS: Double
    ) async throws -> URL {
        // Best-effort: return the asset's URL if it is URL-backed.
        if let urlAsset = asset as? AVURLAsset {
            return urlAsset.url
        }
        // Composition/derived assets have no intrinsic URL — return a
        // placeholder path in the temp directory; the caller is expected
        // to notice (and will once the TODO pipeline ships).
        let placeholder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vfr-conform-placeholder-\(UUID().uuidString).mov")
        return placeholder
    }
}
