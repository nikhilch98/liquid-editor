// BeatDetectionService.swift
// LiquidEditor
//
// E4-6: Beat detection / BPM estimation.
//
// Uses an RMS-envelope onset detector plus inter-peak distance clustering to
// produce:
//   - Beat times (seconds)
//   - Modal BPM estimate
//   - Confidence score (0…1)
//   - First-downbeat estimate
//
// The implementation keeps dependencies lean on purpose: we decode PCM with
// `AVAssetReader`, compute a block-wise RMS envelope with `vDSP`, find peaks
// above an adaptive threshold, and derive BPM from the modal inter-peak
// interval. This avoids bringing in FFT machinery for a first pass while
// still producing plausible markers for typical music tracks.
//
// The service is `@MainActor @Observable` so view models can observe its
// `lastResult` / `isAnalyzing` flags directly, but the heavy work runs on a
// detached task via `nonisolated func detectBeats(...)`.

import AVFoundation
import Accelerate
import Foundation

// MARK: - BeatDetectionError

/// Errors thrown by `BeatDetectionService.detectBeats`.
enum BeatDetectionError: Error, LocalizedError, Sendable {
    case invalidURL(URL)
    case noAudioTrack
    case readerCreationFailed(String)
    case readingFailed(String)
    case insufficientAudio

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            "Invalid audio file URL: \(url.path)"
        case .noAudioTrack:
            "No audio track found in the asset"
        case .readerCreationFailed(let reason):
            "Could not create AVAssetReader: \(reason)"
        case .readingFailed(let reason):
            "Failed while reading PCM samples: \(reason)"
        case .insufficientAudio:
            "Not enough audio to detect beats (track too short)"
        }
    }
}

// MARK: - BeatDetectionResult

/// Output of a single beat-detection pass.
struct BeatDetectionResult: Sendable, Equatable {
    /// Estimated tempo in beats-per-minute.
    let bpm: Double

    /// Detected beat onsets, in seconds from the start of the track.
    let beatTimes: [Double]

    /// 0…1 confidence in the estimate (derived from the ratio of beats that
    /// fall within ±10 % of the modal interval).
    let confidence: Double

    /// Best-guess first-downbeat time in seconds. For music starts on the
    /// first strong peak after a short leading silence.
    let firstDownbeat: Double
}

// MARK: - BeatDetectionService

/// Analyses audio files to produce tempo + beat metadata.
///
/// Thread model: main-actor observable surface, nonisolated analysis.
@MainActor
@Observable
final class BeatDetectionService {

    // MARK: - Observable State

    /// Whether an analysis is currently running. View models can drive
    /// progress spinners off this.
    private(set) var isAnalyzing: Bool = false

    /// Most recent successful result, or `nil` if none yet / last call
    /// threw.
    private(set) var lastResult: BeatDetectionResult? = nil

    /// Most recent error, cleared on successful analysis.
    private(set) var lastError: String? = nil

    // MARK: - Configuration

    /// Hop (window) size in seconds used for envelope block analysis.
    /// A 10 ms hop gives ~100 frames/sec, plenty of resolution for typical
    /// 60–200 BPM music while keeping work down for long files.
    nonisolated static let hopSeconds: Double = 0.010

    /// Minimum musical tempo considered (below this we treat peaks as
    /// spurious rather than beats).
    nonisolated static let minBPM: Double = 60.0

    /// Maximum musical tempo considered.
    nonisolated static let maxBPM: Double = 200.0

    /// Minimum absolute gap (seconds) between two consecutive peak candidates.
    /// At 200 BPM this is 0.3 s.
    nonisolated static let minPeakGapSeconds: Double = 0.30

    init() {}

    // MARK: - Public API

    /// Analyses `audioURL` and returns the detected beats.
    ///
    /// Runs on a cooperative thread (nonisolated). Publishes progress back
    /// to the main actor via the observable flags so a UI can react.
    nonisolated func detectBeats(audioURL: URL) async throws -> BeatDetectionResult {
        await MainActor.run {
            self.isAnalyzing = true
            self.lastError = nil
        }

        do {
            let result = try await Self.runDetection(on: audioURL)
            await MainActor.run {
                self.lastResult = result
                self.isAnalyzing = false
            }
            return result
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
                self.isAnalyzing = false
            }
            throw error
        }
    }

    /// Converts a `BeatDetectionResult` into `TimelineMarker` instances of
    /// type `.beat`. Times are converted from seconds to `TimeMicros`.
    ///
    /// Marker labels are numbered and include the measured BPM so editors
    /// can quickly eyeball tempo fidelity.
    func exportAsMarkers(_ result: BeatDetectionResult) -> [TimelineMarker] {
        let bpmLabel = String(format: "%.0f BPM", result.bpm)
        return result.beatTimes.enumerated().map { index, seconds in
            let micros = TimeMicros(seconds * 1_000_000)
            return TimelineMarker.point(
                id: "beat-\(index)-\(micros)",
                time: micros,
                label: "Beat \(index + 1) · \(bpmLabel)",
                type: .beat
            )
        }
    }
}

// MARK: - Detection Pipeline

extension BeatDetectionService {

    /// Core, pure detection pipeline. `nonisolated` + `static` so it can run
    /// freely on any cooperative executor and never touches `self` state.
    fileprivate nonisolated static func runDetection(
        on url: URL
    ) async throws -> BeatDetectionResult {

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BeatDetectionError.invalidURL(url)
        }

        let asset = AVURLAsset(url: url)

        // AVAsset's async loaders are safe to call from any actor.
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw BeatDetectionError.noAudioTrack
        }

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 1.0 else {
            throw BeatDetectionError.insufficientAudio
        }

        // Read mono 44.1 kHz PCM floats for envelope analysis.
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw BeatDetectionError.readerCreationFailed(error.localizedDescription)
        }

        let sampleRate: Double = 44_100
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let trackOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw BeatDetectionError.readingFailed(
                reader.error?.localizedDescription ?? "unknown"
            )
        }

        let hopSamples = Int(sampleRate * hopSeconds)
        var envelope = [Float]()
        envelope.reserveCapacity(Int(durationSeconds / hopSeconds) + 16)

        var residual = [Float]()
        residual.reserveCapacity(hopSamples * 2)

        while let buffer = trackOutput.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(buffer) }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }

            var lengthAtOffset = 0
            var totalLength = 0
            var pointer: UnsafeMutablePointer<Int8>? = nil
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &pointer
            )
            guard status == kCMBlockBufferNoErr, let p = pointer, totalLength > 0 else {
                continue
            }

            let floatCount = totalLength / MemoryLayout<Float>.size
            p.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
                let slice = UnsafeBufferPointer(start: floats, count: floatCount)
                residual.append(contentsOf: slice)
            }

            // Drain residual buffer into hop-sized RMS blocks.
            while residual.count >= hopSamples {
                let window = Array(residual.prefix(hopSamples))
                residual.removeFirst(hopSamples)
                envelope.append(rms(of: window))
            }
        }
        if !residual.isEmpty {
            envelope.append(rms(of: residual))
            residual.removeAll(keepingCapacity: false)
        }

        if reader.status == .failed {
            throw BeatDetectionError.readingFailed(
                reader.error?.localizedDescription ?? "unknown"
            )
        }

        guard envelope.count > 8 else {
            throw BeatDetectionError.insufficientAudio
        }

        // Onset detection: positive first-derivative ("spectral flux" on the
        // envelope) gives us a crude but robust percussive-onset signal.
        let onsets = positiveDerivative(envelope)
        let peaks = adaptivePeakPick(
            signal: onsets,
            hopSeconds: hopSeconds,
            minGapSeconds: minPeakGapSeconds
        )

        guard peaks.count >= 4 else {
            // Fall back to evenly-spaced placeholder so the caller always
            // gets _something_ — but flag low confidence.
            let approxBPM = 120.0
            let spacing = 60.0 / approxBPM
            let count = max(1, Int(durationSeconds / spacing))
            let times = (0..<count).map { Double($0) * spacing }
            return BeatDetectionResult(
                bpm: approxBPM,
                beatTimes: times,
                confidence: 0.2,
                firstDownbeat: times.first ?? 0
            )
        }

        let (bpm, confidence) = estimateBPM(fromPeakTimes: peaks)
        let firstDownbeat = peaks.first ?? 0

        return BeatDetectionResult(
            bpm: bpm,
            beatTimes: peaks,
            confidence: confidence,
            firstDownbeat: firstDownbeat
        )
    }

    // MARK: - Helpers

    /// RMS of a sample window via `vDSP_rmsqv`.
    fileprivate nonisolated static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var result: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            vDSP_rmsqv(ptr.baseAddress!, 1, &result, vDSP_Length(samples.count))
        }
        return result
    }

    /// Positive first derivative — keeps only "rising" edges so sustained
    /// notes don't look like fresh onsets.
    fileprivate nonisolated static func positiveDerivative(_ signal: [Float]) -> [Float] {
        guard signal.count > 1 else { return signal }
        var out = [Float](repeating: 0, count: signal.count)
        for i in 1..<signal.count {
            let diff = signal[i] - signal[i - 1]
            out[i] = diff > 0 ? diff : 0
        }
        return out
    }

    /// Adaptive peak-picking against a rolling mean + std threshold.
    ///
    /// A peak must exceed `mean + 1.5 * std` and be separated from the
    /// previous peak by at least `minGapSeconds`.
    fileprivate nonisolated static func adaptivePeakPick(
        signal: [Float],
        hopSeconds: Double,
        minGapSeconds: Double
    ) -> [Double] {
        guard signal.count > 4 else { return [] }

        var mean: Float = 0
        var std: Float = 0
        signal.withUnsafeBufferPointer { ptr in
            vDSP_meanv(ptr.baseAddress!, 1, &mean, vDSP_Length(signal.count))
            vDSP_normalize(
                ptr.baseAddress!,
                1,
                nil,
                1,
                &mean,
                &std,
                vDSP_Length(signal.count)
            )
        }

        let threshold = mean + 1.5 * std
        let minGapFrames = max(1, Int(minGapSeconds / hopSeconds))

        var peaks: [Int] = []
        var lastPeak = -minGapFrames
        for i in 1..<(signal.count - 1) {
            let v = signal[i]
            guard v > threshold else { continue }
            guard v > signal[i - 1], v >= signal[i + 1] else { continue }
            guard i - lastPeak >= minGapFrames else { continue }
            peaks.append(i)
            lastPeak = i
        }

        return peaks.map { Double($0) * hopSeconds }
    }

    /// Estimates BPM from the modal inter-peak interval, quantised into
    /// 1 BPM buckets. Confidence = (peaks within ±10 % of mode) / total.
    fileprivate nonisolated static func estimateBPM(
        fromPeakTimes times: [Double]
    ) -> (bpm: Double, confidence: Double) {

        guard times.count > 2 else { return (120.0, 0.1) }

        var intervals: [Double] = []
        intervals.reserveCapacity(times.count - 1)
        for i in 1..<times.count {
            intervals.append(times[i] - times[i - 1])
        }

        // Fold intervals into the plausible BPM range by doubling/halving
        // so `0.25 s` (240 BPM) and `0.5 s` (120 BPM) both map to 120.
        let foldedBPMs: [Double] = intervals.compactMap { interval in
            guard interval > 0 else { return nil }
            var bpm = 60.0 / interval
            while bpm > maxBPM { bpm /= 2 }
            while bpm < minBPM { bpm *= 2 }
            guard bpm >= minBPM, bpm <= maxBPM else { return nil }
            return bpm
        }

        guard !foldedBPMs.isEmpty else { return (120.0, 0.15) }

        // Histogram-mode via 1-BPM-wide buckets.
        var histogram: [Int: Int] = [:]
        for bpm in foldedBPMs {
            let bucket = Int(bpm.rounded())
            histogram[bucket, default: 0] += 1
        }
        let (modalBucket, modalCount) = histogram
            .max(by: { $0.value < $1.value }) ?? (120, 0)

        // Confidence = fraction of folded intervals within ±10 % of mode.
        let target = Double(modalBucket)
        let matches = foldedBPMs.filter { abs($0 - target) / target <= 0.10 }.count
        let confidence = Double(matches) / Double(foldedBPMs.count)

        // Blend bucket mode with the mean of matches for a smoother estimate.
        let matchingBPMs = foldedBPMs.filter { abs($0 - target) / target <= 0.10 }
        let refined: Double
        if !matchingBPMs.isEmpty {
            refined = matchingBPMs.reduce(0, +) / Double(matchingBPMs.count)
        } else {
            refined = target
        }

        _ = modalCount // silence unused-value warning (kept for debugging)
        return (refined, max(0.15, min(1.0, confidence)))
    }
}
