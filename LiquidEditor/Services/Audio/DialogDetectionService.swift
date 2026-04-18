// DialogDetectionService.swift
// LiquidEditor
//
// C5-18: Energy-based Voice Activity Detection (VAD) for Auto-Mix.
//
// Splits an audio file into 100 ms windows, computes the RMS energy
// of each window, thresholds against the noise floor, and merges
// consecutive "voiced" windows into `DialogSegment` ranges.
//
// Pure Swift implementation — no ML models. Good enough for the
// Auto-Mix ducking feature and deterministic for testing. The heavy
// lifting is a `nonisolated static` helper so it can run off the
// main actor; the instance method just awaits it.

import Foundation
import AVFoundation
import Accelerate
import Observation

// MARK: - DialogSegment

/// A detected voice-activity region in the input audio.
///
/// Times are in seconds from the start of the asset. `confidence`
/// is a rough normalized score (RMS relative to the global peak).
struct DialogSegment: Sendable, Equatable {
    let startSec: Double
    let endSec: Double
    let confidence: Double

    var durationSec: Double { max(0, endSec - startSec) }
}

// MARK: - DialogDetectionError

enum DialogDetectionError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case noAudioTrack
    case readerFailed(String)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): "Audio file not found: \(p)"
        case .noAudioTrack: "No audio track in asset"
        case .readerFailed(let r): "AVAssetReader creation failed: \(r)"
        case .readFailed(let r): "Audio read failed: \(r)"
        }
    }
}

// MARK: - DialogDetectionService

/// Detects dialog / voice-activity regions in an audio file using
/// an RMS energy threshold over 100 ms windows.
///
/// Thread safety: `@MainActor @Observable` so UI can bind to
/// `isRunning` / `lastSegments`. Heavy computation runs in a
/// nonisolated `static` helper that performs all audio I/O off
/// the main actor.
@Observable
@MainActor
final class DialogDetectionService {

    // MARK: - Observable state

    /// Whether a detection pass is in flight.
    private(set) var isRunning: Bool = false

    /// Segments from the most recent successful pass.
    private(set) var lastSegments: [DialogSegment] = []

    // MARK: - Tuning

    /// Window width in seconds (100 ms).
    nonisolated static let windowSec: Double = 0.1

    /// RMS threshold expressed as a multiplier of the global mean RMS.
    /// Windows with RMS > `threshold * meanRMS` are considered voiced.
    nonisolated static let threshold: Double = 1.4

    /// Minimum segment duration to emit (merge / drop shorter hits).
    nonisolated static let minSegmentSec: Double = 0.25

    /// Merge gap: consecutive voiced regions separated by less than
    /// this (seconds) of silence are fused into a single segment.
    nonisolated static let mergeGapSec: Double = 0.3

    // MARK: - Public API

    /// Detect dialog segments in the audio file at `audioURL`.
    ///
    /// Declared `nonisolated` so callers can invoke it from any
    /// context without jumping to the main actor. All heavy work is
    /// delegated to the `static` helper below, which means this
    /// function intentionally touches zero instance state — that's
    /// required to stay compatible with strict concurrency on an
    /// `@Observable` type.
    nonisolated func detectDialog(audioURL: URL) async throws -> [DialogSegment] {
        try await Self.runDetection(audioURL: audioURL)
    }

    /// Convenience wrapper that also updates observable state on
    /// the main actor. Call this from UI flows where binding to
    /// `isRunning` / `lastSegments` is useful.
    func detectAndStore(audioURL: URL) async throws -> [DialogSegment] {
        isRunning = true
        defer { isRunning = false }
        let segments = try await Self.runDetection(audioURL: audioURL)
        lastSegments = segments
        return segments
    }

    // MARK: - Nonisolated detection core

    /// Perform the full VAD pass: read PCM float32 mono, bucket by
    /// window, compute RMS, threshold, and merge.
    nonisolated static func runDetection(audioURL: URL) async throws -> [DialogSegment] {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw DialogDetectionError.fileNotFound(audioURL.path)
        }

        let asset = AVURLAsset(url: audioURL)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw DialogDetectionError.noAudioTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw DialogDetectionError.readerFailed(error.localizedDescription)
        }

        let sampleRate = 44_100
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw DialogDetectionError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }

        let windowSamples = Int(Double(sampleRate) * windowSec)
        guard windowSamples > 0 else { return [] }

        var windowRMS: [Double] = []

        var runningSumSquares: Double = 0
        var runningCount: Int = 0

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let block = CMSampleBufferGetDataBuffer(buffer) else {
                continue
            }

            var dataPointer: UnsafeMutablePointer<Int8>?
            var length = 0
            CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )
            guard let ptr = dataPointer else {
                CMSampleBufferInvalidate(buffer)
                continue
            }

            let floatCount = length / MemoryLayout<Float>.size
            let floatPtr = UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: floatCount)

            var offset = 0
            while offset < floatCount {
                let remaining = windowSamples - runningCount
                let take = min(remaining, floatCount - offset)

                var sumSq: Float = 0
                vDSP_svesq(floatPtr.advanced(by: offset), 1, &sumSq, vDSP_Length(take))

                runningSumSquares += Double(sumSq)
                runningCount += take
                offset += take

                if runningCount >= windowSamples {
                    let mean = runningSumSquares / Double(windowSamples)
                    let rms = mean > 0 ? (mean.squareRoot()) : 0
                    windowRMS.append(rms)

                    runningSumSquares = 0
                    runningCount = 0
                }
            }

            CMSampleBufferInvalidate(buffer)
        }

        // Flush trailing partial window.
        if runningCount > 0 {
            let mean = runningSumSquares / Double(runningCount)
            windowRMS.append(mean > 0 ? mean.squareRoot() : 0)
        }

        if reader.status == .failed {
            throw DialogDetectionError.readFailed(reader.error?.localizedDescription ?? "unknown")
        }

        return mergeVoicedWindows(windowRMS: windowRMS, windowSec: windowSec)
    }

    // MARK: - Threshold + merge

    /// Turn a per-window RMS series into merged `DialogSegment`s.
    nonisolated static func mergeVoicedWindows(
        windowRMS: [Double],
        windowSec: Double
    ) -> [DialogSegment] {
        guard !windowRMS.isEmpty else { return [] }

        let meanRMS = windowRMS.reduce(0, +) / Double(windowRMS.count)
        let peakRMS = windowRMS.max() ?? 0
        guard meanRMS > 0 else { return [] }

        let cut = meanRMS * threshold
        let voiced = windowRMS.map { $0 > cut }

        var segments: [DialogSegment] = []
        var segStartIdx: Int?

        for (idx, isVoiced) in voiced.enumerated() {
            if isVoiced {
                if segStartIdx == nil { segStartIdx = idx }
            } else if let startIdx = segStartIdx {
                let endIdx = idx
                segments.append(makeSegment(
                    startIdx: startIdx,
                    endIdx: endIdx,
                    windowRMS: windowRMS,
                    peakRMS: peakRMS,
                    windowSec: windowSec
                ))
                segStartIdx = nil
            }
        }

        // Tail segment.
        if let startIdx = segStartIdx {
            segments.append(makeSegment(
                startIdx: startIdx,
                endIdx: windowRMS.count,
                windowRMS: windowRMS,
                peakRMS: peakRMS,
                windowSec: windowSec
            ))
        }

        // Merge segments separated by less than `mergeGapSec`.
        var merged: [DialogSegment] = []
        for seg in segments {
            if var last = merged.last, seg.startSec - last.endSec < mergeGapSec {
                merged.removeLast()
                last = DialogSegment(
                    startSec: last.startSec,
                    endSec: seg.endSec,
                    confidence: max(last.confidence, seg.confidence)
                )
                merged.append(last)
            } else {
                merged.append(seg)
            }
        }

        // Drop too-short segments.
        return merged.filter { $0.durationSec >= minSegmentSec }
    }

    private nonisolated static func makeSegment(
        startIdx: Int,
        endIdx: Int,
        windowRMS: [Double],
        peakRMS: Double,
        windowSec: Double
    ) -> DialogSegment {
        let startSec = Double(startIdx) * windowSec
        let endSec = Double(endIdx) * windowSec
        var sum: Double = 0
        let count = max(1, endIdx - startIdx)
        for i in startIdx..<min(endIdx, windowRMS.count) {
            sum += windowRMS[i]
        }
        let avg = sum / Double(count)
        let confidence = peakRMS > 0 ? min(1.0, avg / peakRMS) : 0
        return DialogSegment(startSec: startSec, endSec: endSec, confidence: confidence)
    }
}
