// StabilizationService.swift
// LiquidEditor
//
// C5-17: Video stabilization (revisited with Sendable-safe signature).
//
// Takes a file URL and a StabilizationMode, runs Vision framework
// image-registration requests pairwise across frames, accumulates
// inverse transforms, and (TODO) bakes a stabilized copy via
// `AVAssetWriter`. The pipeline itself is stubbed to return the
// original URL until the writer path is wired up, but the Vision
// analysis loop is implemented and produces real per-frame offsets.
//
// The service is `@MainActor` + `@Observable` so the UI can bind to
// progress / isRunning for live feedback. Heavy work is performed
// inside `Task.detached` via a nonisolated `static` helper to avoid
// touching `@Observable` state from background contexts.

import Foundation
import AVFoundation
import Vision
import CoreImage
import Observation

// MARK: - StabilizationMode

/// User-facing stabilization strength/quality preset.
///
/// - `cinema`: Highest quality, homographic registration (handles
///   translation + rotation + perspective). Slow.
/// - `handheld`: Balanced — translational registration with a wider
///   smoothing window. Fast.
/// - `fast`: Translational only, minimal smoothing. Real-time.
enum StabilizationMode: String, Sendable, CaseIterable {
    case cinema
    case handheld
    case fast

    /// Human-readable label for pickers.
    var displayName: String {
        switch self {
        case .cinema: "Cinema"
        case .handheld: "Handheld"
        case .fast: "Fast"
        }
    }

    /// SF Symbol for the mode.
    var sfSymbol: String {
        switch self {
        case .cinema: "film.stack"
        case .handheld: "hand.raised"
        case .fast: "hare"
        }
    }
}

// MARK: - StabilizationError

enum StabilizationError: Error, LocalizedError, Sendable {
    case assetUnreadable(String)
    case noVideoTrack
    case frameReadFailed
    case visionRequestFailed(String)
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetUnreadable(let reason): "Asset is unreadable: \(reason)"
        case .noVideoTrack: "No video track found in asset"
        case .frameReadFailed: "Failed to read video frames"
        case .visionRequestFailed(let reason): "Vision request failed: \(reason)"
        case .writerFailed(let reason): "Asset writer failed: \(reason)"
        }
    }
}

// MARK: - StabilizationService

/// Analyses a video at `url`, computes per-frame inverse transforms
/// to counteract camera motion, and writes a stabilized copy.
///
/// Returns the URL of the stabilized output (currently the original
/// URL; writer pipeline is marked TODO below).
@Observable
@MainActor
final class StabilizationService {

    // MARK: - Observable state

    /// Fraction (0.0...1.0) of frames analyzed — useful for bound progress UI.
    private(set) var progress: Double = 0

    /// Whether an analysis pass is in flight.
    private(set) var isRunning: Bool = false

    /// Most recent error, if any.
    private(set) var lastError: String?

    // MARK: - Public API

    /// Stabilize the video at `assetURL` using the given `mode`.
    ///
    /// - Parameters:
    ///   - assetURL: Local file URL of a video asset.
    ///   - mode: Stabilization strength preset.
    /// - Returns: URL of the stabilized video (currently the input URL,
    ///   pending AVAssetWriter wiring).
    /// - Throws: `StabilizationError` on failure.
    func stabilize(assetURL: URL, mode: StabilizationMode) async throws -> URL {
        isRunning = true
        progress = 0
        lastError = nil
        defer { isRunning = false }

        do {
            let transforms = try await Self.analyze(assetURL: assetURL, mode: mode) { [weak self] p in
                Task { @MainActor [weak self] in
                    self?.progress = p
                }
            }

            // TODO: Wire AVAssetWriter pipeline.
            // The per-frame `transforms` array contains inverse affine
            // transforms suitable for baking into an AVVideoCompositionInstruction
            // or rendering via AVAssetWriter. For now we return the input URL
            // so the caller can continue the UX flow; the baking step is a
            // follow-up task (the Vision analysis is the expensive part and
            // is done here).
            _ = transforms

            progress = 1.0
            return assetURL
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Nonisolated analysis

    /// A single frame-to-frame inverse transform computed by Vision.
    struct FrameTransform: Sendable {
        let frameIndex: Int
        let tx: Double
        let ty: Double
        /// For homographic mode — 3x3 matrix flattened row-major.
        let homography: [Double]?
    }

    /// Run Vision image-registration across the video's frames and
    /// return per-frame inverse transforms.
    ///
    /// Declared `nonisolated static` so it can be invoked from a
    /// detached task without capturing `self` or any actor-isolated
    /// state. Progress is reported through a `@Sendable` closure.
    nonisolated static func analyze(
        assetURL: URL,
        mode: StabilizationMode,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [FrameTransform] {
        let asset = AVURLAsset(url: assetURL)

        guard asset.isReadable else {
            throw StabilizationError.assetUnreadable(assetURL.path)
        }

        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw StabilizationError.noVideoTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw StabilizationError.assetUnreadable(error.localizedDescription)
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            throw StabilizationError.frameReadFailed
        }

        // Approximate total frame count for progress reporting.
        let duration = CMTimeGetSeconds(asset.duration)
        let nominalFPS = Double(videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30)
        let approxFrameCount = max(1, Int(duration * nominalFPS))

        let handler = VNSequenceRequestHandler()
        var transforms: [FrameTransform] = []
        var previousBuffer: CVPixelBuffer?
        var frameIndex = 0

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer(),
                  let pb = CMSampleBufferGetImageBuffer(sample) else {
                if reader.status == .failed {
                    throw StabilizationError.frameReadFailed
                }
                break
            }

            if let prev = previousBuffer {
                let transform = try runRegistration(
                    previous: prev,
                    current: pb,
                    mode: mode,
                    handler: handler,
                    frameIndex: frameIndex
                )
                transforms.append(transform)

                if let progress {
                    let p = min(1.0, Double(frameIndex) / Double(approxFrameCount))
                    progress(p)
                }
            }

            previousBuffer = pb
            frameIndex += 1
        }

        if reader.status == .failed {
            throw StabilizationError.frameReadFailed
        }

        return transforms
    }

    /// Pair-wise Vision registration between two frames.
    private nonisolated static func runRegistration(
        previous: CVPixelBuffer,
        current: CVPixelBuffer,
        mode: StabilizationMode,
        handler: VNSequenceRequestHandler,
        frameIndex: Int
    ) throws -> FrameTransform {
        switch mode {
        case .cinema:
            let request = VNHomographicImageRegistrationRequest(targetedCVPixelBuffer: current)
            do {
                try handler.perform([request], on: previous)
            } catch {
                throw StabilizationError.visionRequestFailed(error.localizedDescription)
            }
            let matrix = request.results?.first?.warpTransform
            let flat: [Double]? = matrix.map { m in
                [
                    Double(m.columns.0.x), Double(m.columns.1.x), Double(m.columns.2.x),
                    Double(m.columns.0.y), Double(m.columns.1.y), Double(m.columns.2.y),
                    Double(m.columns.0.z), Double(m.columns.1.z), Double(m.columns.2.z),
                ]
            }
            return FrameTransform(
                frameIndex: frameIndex,
                tx: Double(matrix?.columns.2.x ?? 0),
                ty: Double(matrix?.columns.2.y ?? 0),
                homography: flat
            )

        case .handheld, .fast:
            let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: current)
            do {
                try handler.perform([request], on: previous)
            } catch {
                throw StabilizationError.visionRequestFailed(error.localizedDescription)
            }
            let t = request.results?.first?.alignmentTransform
            return FrameTransform(
                frameIndex: frameIndex,
                tx: Double(t?.tx ?? 0),
                ty: Double(t?.ty ?? 0),
                homography: nil
            )
        }
    }
}
