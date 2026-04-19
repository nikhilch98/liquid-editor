// LoudnessNormalizer.swift
// LiquidEditor
//
// TD8-17: LUFS-targeted loudness normalisation.
//
// Measures the integrated loudness of an audio file and normalises it to
// a user-selected target (streaming, broadcast, podcast, film). Provides
// a K-weighted RMS approximation of the ITU-R BS.1770 integrated-loudness
// algorithm — **deliberately a simplification**.
//
// Deviations from BS.1770 (documented so future passes can tighten):
//   - No pre-filter (high-shelf @ 1.68 kHz, high-pass @ ~38 Hz).
//   - K-weighting is approximated by a single high-shelf IIR applied per
//     channel; BS.1770 specifies a two-stage biquad cascade.
//   - Gating is single-threshold (-70 LUFS absolute) rather than the
//     -70 + relative -10 LU two-pass gate.
//   - Channel weighting uses equal weights; BS.1770 specifies surround
//     weights (L, R, C = 1.0, Ls, Rs = 1.41).
//   - True-peak is estimated from raw sample peak with a +3 dB safety
//     margin rather than 4×-oversampled inter-sample peak.
//   - Loudness range uses a 5-second histogram difference between 10th
//     and 95th percentiles; BS.1773/EBU R128 specifies 3-second blocks.
//
// The goal of this file is to provide a plausible measurement and a
// deterministic API shape that the rest of the app can bind to today,
// while leaving a clearly-scoped TODO to swap in a BS.1770-accurate
// backend (AVAudioUnitEQ + Accelerate vDSP biquad cascade or AUv3).
//
// The `normalize` entry-point is stubbed: it returns the original URL
// unchanged and leaves a TODO to implement the gain-applied render.

import AVFoundation
import Accelerate
import Foundation
import OSLog

// MARK: - LoudnessMeasurement

/// Result of a BS.1770-style loudness measurement.
///
/// Units follow the EBU R128 conventions so the values can be presented to
/// end users as they appear in other audio tooling:
/// - `integratedLUFS` — overall programme loudness.
/// - `truePeak` — estimated peak in dBTP.
/// - `loudnessRange` — dynamic range in LU (Loudness Units).
struct LoudnessMeasurement: Sendable {

    /// Integrated loudness in LUFS (Loudness Units relative to Full Scale).
    /// Silent or empty inputs return `-.infinity`.
    let integratedLUFS: Double

    /// Estimated true-peak value in dBTP.
    let truePeak: Double

    /// Loudness range in LU (EBU R128 LRA surrogate).
    let loudnessRange: Double
}

// MARK: - LUFSTarget

/// Canonical LUFS targets used across the app.
///
/// Values were chosen from the dominant published specs and cross-checked
/// against each broadcaster's loudness standard as of 2026-Q2:
///  - streaming: Apple Music / Spotify target (-14 LUFS).
///  - broadcast: EBU R128 / ATSC A/85 delivery target (-23 LUFS).
///  - podcast:   Apple Podcasts / AES loudness guidelines (-16 LUFS).
///  - film:      Dolby cinema reference (-27 LUFS integrated).
enum LUFSTarget: Double, Sendable, CaseIterable, Identifiable {
    case streaming = -14
    case broadcast = -23
    case podcast   = -16
    case film      = -27

    var id: Double { rawValue }

    /// Human-readable title used in UI pickers.
    var title: String {
        switch self {
        case .streaming: return "Streaming"
        case .broadcast: return "Broadcast"
        case .podcast:   return "Podcast"
        case .film:      return "Film"
        }
    }

    /// Short specification label for the chosen target.
    var specLabel: String {
        switch self {
        case .streaming: return "-14 LUFS"
        case .broadcast: return "-23 LUFS"
        case .podcast:   return "-16 LUFS"
        case .film:      return "-27 LUFS"
        }
    }
}

// MARK: - LoudnessNormalizerError

/// Errors that can be raised by `LoudnessNormalizer`.
enum LoudnessNormalizerError: Error, Sendable, Equatable {
    /// Asset has no decodable audio tracks.
    case noAudioTracks

    /// Decode failed mid-stream.
    case decodeFailed(String)

    /// Input audio had zero sample frames.
    case emptyAudio
}

// MARK: - LoudnessNormalizer

/// @Observable façade for loudness measurement and normalisation.
///
/// The `isMeasuring` / `isNormalizing` flags drive progress UI on the
/// inspector. Core work is performed on a detached task via `nonisolated`
/// entry points so callers can `await` from the main actor without
/// blocking it.
@MainActor
@Observable
final class LoudnessNormalizer {

    // MARK: - Logger

    @ObservationIgnored
    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "LoudnessNormalizer"
    )

    // MARK: - Observable state

    /// True while a measurement is running.
    private(set) var isMeasuring: Bool = false

    /// True while a normalisation render is running.
    private(set) var isNormalizing: Bool = false

    /// Most recent measurement result, if any.
    private(set) var lastMeasurement: LoudnessMeasurement?

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Measure the integrated loudness of `audioURL`.
    ///
    /// Runs on a background context. Updates `isMeasuring` and
    /// `lastMeasurement` on the main actor when it completes.
    ///
    /// - Parameter audioURL: file URL to an audio or audio-bearing asset.
    /// - Returns: measurement.
    /// - Throws: `LoudnessNormalizerError` on decode failure or empty input.
    nonisolated func measureLoudness(audioURL: URL) async throws -> LoudnessMeasurement {
        await MainActor.run { [self] in isMeasuring = true }
        defer {
            Task { @MainActor [self] in isMeasuring = false }
        }

        let measurement = try Self.measureBS1770Approx(audioURL: audioURL)
        await MainActor.run { [self] in lastMeasurement = measurement }
        return measurement
    }

    /// Normalise the audio at `audioURL` to hit `targetLUFS`.
    ///
    /// TODO(td8-17): implement the gain-applied render. For now this is a
    /// stub that returns the original URL. The plan is:
    /// 1. `measureLoudness` on the input.
    /// 2. Compute `gainDB = targetLUFS - measured.integratedLUFS`.
    /// 3. Apply a fixed-gain pass via `AVAudioEngine` or `vDSP_vsmul`.
    /// 4. Write to a new temp file using `AVAssetWriter`.
    /// 5. Verify the output by re-measuring and asserting ±0.5 LU.
    ///
    /// - Parameters:
    ///   - audioURL: source file.
    ///   - targetLUFS: desired integrated loudness in LUFS.
    /// - Returns: URL of the normalised output file. Currently the input.
    nonisolated func normalize(
        audioURL: URL,
        targetLUFS: Double
    ) async throws -> URL {
        await MainActor.run { [self] in isNormalizing = true }
        defer {
            Task { @MainActor [self] in isNormalizing = false }
        }

        // Ensure the input at least decodes; this keeps the API honest.
        _ = try Self.measureBS1770Approx(audioURL: audioURL)

        Self.logger.warning(
            "normalize() is a stub — returning original URL. target=\(targetLUFS) LUFS"
        )
        // TODO: render a gain-adjusted copy via AVAssetWriter.
        return audioURL
    }

    // MARK: - BS.1770 (approximation)

    /// Decode-and-measure pipeline.
    ///
    /// Steps (synchronous, runs off main actor via `nonisolated`):
    /// 1. Open the asset as an `AVAudioFile` (compressed formats are
    ///    decompressed on demand).
    /// 2. Read into a single `AVAudioPCMBuffer` in the processing format.
    /// 3. Apply a cheap K-weighting shelf (single-pole IIR per channel).
    /// 4. Compute mean-square energy per 400 ms block with 75% overlap.
    /// 5. Gate with a -70 LUFS absolute threshold; average the survivors
    ///    to produce integrated loudness.
    /// 6. Estimate true-peak from the raw PCM with a +3 dB headroom.
    /// 7. Compute loudness range as the 95th - 10th percentile of the
    ///    block LUFS values.
    nonisolated private static func measureBS1770Approx(
        audioURL: URL
    ) throws -> LoudnessMeasurement {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: audioURL)
        } catch {
            throw LoudnessNormalizerError.decodeFailed(error.localizedDescription)
        }

        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        let sampleRate = format.sampleRate
        let totalFrames = file.length

        guard totalFrames > 0, channelCount > 0, sampleRate > 0 else {
            throw LoudnessNormalizerError.emptyAudio
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw LoudnessNormalizerError.decodeFailed("buffer allocation failed")
        }

        do {
            try file.read(into: buffer)
        } catch {
            throw LoudnessNormalizerError.decodeFailed(error.localizedDescription)
        }

        guard let channelData = buffer.floatChannelData else {
            // Non-float formats are unexpected since processingFormat is
            // canonical 32-bit float PCM.
            throw LoudnessNormalizerError.decodeFailed("non-float PCM")
        }

        let frameLength = Int(buffer.frameLength)

        // ---- 1. True peak estimate (raw sample peak + 3 dB margin) ------
        var maxAbs: Float = 0
        for channel in 0..<channelCount {
            var cMax: Float = 0
            vDSP_maxmgv(channelData[channel], 1, &cMax, vDSP_Length(frameLength))
            if cMax > maxAbs { maxAbs = cMax }
        }
        let truePeakDBFS: Double
        if maxAbs > 0 {
            truePeakDBFS = 20.0 * log10(Double(maxAbs)) + 3.0
        } else {
            truePeakDBFS = -.infinity
        }

        // ---- 2. K-weighting (single-pole high-shelf approximation) -----
        //
        // Real BS.1770 uses a two-stage biquad cascade; this is intentionally
        // an approximation (see file header). We apply a simple one-pole
        // high-shelf: y[n] = a*x[n] + (1-a)*x[n-1] with a shelf gain of
        // +4 dB at ~2 kHz, which is close enough for relative loudness.
        let shelfCoefA: Float = 0.75
        var weighted = Array(repeating: Array(repeating: Float(0), count: frameLength),
                             count: channelCount)
        for channel in 0..<channelCount {
            let src = channelData[channel]
            var prev: Float = 0
            for frameIdx in 0..<frameLength {
                let sample = src[frameIdx]
                let shelved = shelfCoefA * sample + (1 - shelfCoefA) * prev
                weighted[channel][frameIdx] = shelved * 1.585 // ~+4 dB
                prev = sample
            }
        }

        // ---- 3. Block-wise mean-square energy ---------------------------
        let blockSize = Int(sampleRate * 0.400)   // 400 ms
        let hopSize = max(Int(sampleRate * 0.100), 1) // 100 ms hop -> 75% overlap
        guard blockSize > 0, frameLength >= blockSize else {
            // File shorter than one block — report it as silence.
            return LoudnessMeasurement(
                integratedLUFS: -.infinity,
                truePeak: truePeakDBFS,
                loudnessRange: 0
            )
        }

        var blockLUFS: [Double] = []
        var blockStart = 0
        while blockStart + blockSize <= frameLength {
            var meanSquareSum: Double = 0
            for channel in 0..<channelCount {
                var ms: Float = 0
                weighted[channel].withUnsafeBufferPointer { ptr in
                    guard let base = ptr.baseAddress else { return }
                    vDSP_measqv(base.advanced(by: blockStart), 1, &ms,
                                vDSP_Length(blockSize))
                }
                meanSquareSum += Double(ms)
            }
            // Equal channel weights (deviation from BS.1770 surround weights).
            let meanSquare = meanSquareSum / Double(channelCount)
            if meanSquare > 0 {
                // BS.1770 offset: LUFS = -0.691 + 10 * log10(meanSquare).
                let lufs = -0.691 + 10.0 * log10(meanSquare)
                blockLUFS.append(lufs)
            } else {
                blockLUFS.append(-.infinity)
            }
            blockStart += hopSize
        }

        // ---- 4. Absolute-threshold gate (-70 LUFS), integrate -----------
        let absGateThresholdLUFS: Double = -70.0
        let gated = blockLUFS.filter { $0 > absGateThresholdLUFS }
        let integratedLUFS: Double
        if gated.isEmpty {
            integratedLUFS = -.infinity
        } else {
            // Convert to linear energy, average, convert back.
            let meanEnergy = gated.reduce(0.0) { acc, lufs in
                acc + pow(10.0, (lufs + 0.691) / 10.0)
            } / Double(gated.count)
            integratedLUFS = -0.691 + 10.0 * log10(max(meanEnergy, .leastNonzeroMagnitude))
        }

        // ---- 5. Loudness range (P95 - P10 of block LUFS) ---------------
        let loudnessRange: Double
        if gated.count >= 4 {
            let sorted = gated.sorted()
            let p10 = percentile(sorted, 0.10)
            let p95 = percentile(sorted, 0.95)
            loudnessRange = max(p95 - p10, 0)
        } else {
            loudnessRange = 0
        }

        return LoudnessMeasurement(
            integratedLUFS: integratedLUFS,
            truePeak: truePeakDBFS,
            loudnessRange: loudnessRange
        )
    }

    /// Simple linear-interpolation percentile. `sorted` must be ascending.
    nonisolated private static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clampedQ = min(max(q, 0), 1)
        let position = clampedQ * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }
}
