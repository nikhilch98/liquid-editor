// WaveformPrecomputeService.swift
// LiquidEditor
//
// PP12-3: Precomputes peak + RMS waveform data for audio assets.
//
// Unlike the existing `WaveformExtractor` which emits a single
// `[Float]` peak stream, this service computes BOTH the absolute
// peak and the root-mean-square (RMS) for every sample window —
// giving the UI enough information to render LumaFusion-style
// two-layer waveforms (outline peak + filled RMS).
//
// Architecture:
// - `@MainActor @Observable` front-end for SwiftUI ViewModels.
// - `nonisolated` async `precompute(...)` method does the heavy
//   lifting on a cooperative-pool task (AVAssetReader + Accelerate),
//   then returns a `Sendable` `PrecomputedWaveform` snapshot.
// - Results are memoized in `WaveformPrecomputeCache` (in-memory,
//   keyed by `URL`) so repeat calls for the same URL short-circuit.
//
// The produced `PrecomputedWaveform` is distinct from the existing
// `WaveformData` type in WaveformExtractor.swift — that one stores
// only normalized peaks and a `WaveformLevelOfDetail`. This one
// stores paired peak/RMS arrays and is optimized for the
// samples-per-second API shape the premium UI redesign needs.

import AVFoundation
import Accelerate
import Foundation
import Observation
import os

// MARK: - PrecomputedWaveform

/// Precomputed peak + RMS waveform data for an audio asset.
///
/// Arrays are parallel — `peaks[i]` and `rms[i]` describe the same
/// sample window. Values are normalized to 0.0 ... 1.0 (peak is the
/// absolute max, RMS is the root-mean-square energy).
///
/// `Sendable` so it can be passed freely between actors.
struct PrecomputedWaveform: Sendable, Equatable {
    /// Absolute-peak samples, normalized 0.0 ... 1.0.
    let peaks: [Float]

    /// RMS samples, normalized 0.0 ... 1.0. Always <= peaks[i].
    let rms: [Float]

    /// Total duration of the source audio in seconds.
    let durationSec: Double

    /// Effective samples-per-second resolution for `peaks` / `rms`.
    let samplesPerSecond: Int

    /// Whether both arrays are empty (e.g. a zero-length audio track).
    var isEmpty: Bool { peaks.isEmpty && rms.isEmpty }
}

// MARK: - WaveformPrecomputeError

/// Errors thrown by `WaveformPrecomputeService.precompute`.
enum WaveformPrecomputeError: Error, LocalizedError, Sendable {
    case noAudioTrack
    case readerCreationFailed(String)
    case readingFailed(String)
    case invalidSamplesPerSecond(Int)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            "No audio track found in asset."
        case .readerCreationFailed(let reason):
            "Failed to create asset reader: \(reason)"
        case .readingFailed(let reason):
            "Audio reading failed: \(reason)"
        case .invalidSamplesPerSecond(let value):
            "Invalid samplesPerSecond: \(value). Must be >= 1."
        }
    }
}

// MARK: - WaveformPrecomputeCache

/// In-memory cache of `PrecomputedWaveform` results keyed by URL.
///
/// This is a simple actor-backed dictionary — no LRU eviction, no
/// memory-pressure response. The audio waveform cache is small
/// (<= a few hundred KB per asset at 100 sps) and the expectation
/// is that one project has ~dozens of audio clips max.
///
/// If cache size becomes a concern, swap the underlying store for
/// an `OrderedDictionary` + LRU eviction similar to
/// `StickerImageCache`.
actor WaveformPrecomputeCache {

    /// Singleton shared instance. Backing store for
    /// `WaveformPrecomputeService`.
    static let shared = WaveformPrecomputeCache()

    private var storage: [URL: PrecomputedWaveform] = [:]

    /// Lookup a cached waveform.
    func get(_ url: URL) -> PrecomputedWaveform? {
        storage[url]
    }

    /// Store a waveform in the cache, replacing any prior entry.
    func put(_ url: URL, _ waveform: PrecomputedWaveform) {
        storage[url] = waveform
    }

    /// Drop all cached entries.
    func clear() {
        storage.removeAll()
    }

    /// Number of cached entries.
    var count: Int { storage.count }
}

// MARK: - WaveformPrecomputeService

/// @Observable service for precomputing audio waveforms.
///
/// SwiftUI views can observe `lastError` and `isBusy` to drive
/// loading / error UI. The actual precompute runs on a detached
/// background task (`nonisolated`) and returns a `Sendable`
/// `PrecomputedWaveform` value.
///
/// ## Usage
///
/// ```swift
/// let service = WaveformPrecomputeService()
/// let waveform = try await service.precompute(audioURL: url)
/// // waveform.peaks, waveform.rms — render side-by-side.
/// ```
@MainActor
@Observable
final class WaveformPrecomputeService {

    // MARK: - Observable State

    /// Most recent error from `precompute`, or nil if the last call
    /// succeeded. Views can render an error chip off this.
    private(set) var lastError: WaveformPrecomputeError?

    /// True while at least one precompute is in flight.
    private(set) var inFlightCount: Int = 0
    var isBusy: Bool { inFlightCount > 0 }

    // MARK: - Logger

    @ObservationIgnored
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.liquideditor",
        category: "WaveformPrecomputeService"
    )

    // MARK: - Init

    init() {}

    // MARK: - API

    /// Precompute peak + RMS waveform data for an audio file.
    ///
    /// If a precomputed result for `audioURL` already exists in the
    /// shared `WaveformPrecomputeCache`, it is returned immediately.
    /// Otherwise the audio is read via `AVAssetReader`, converted to
    /// mono Float32 PCM, and walked in fixed-width windows to
    /// produce one peak + one RMS sample per window.
    ///
    /// This method is `nonisolated` and safe to call from any actor
    /// context. The returned value is `Sendable`.
    ///
    /// - Parameters:
    ///   - audioURL: File URL to the audio asset.
    ///   - samplesPerSecond: Output resolution in samples per second
    ///     of source audio. Must be >= 1. Defaults to 100.
    /// - Returns: `PrecomputedWaveform` with parallel peaks/rms arrays.
    /// - Throws: `WaveformPrecomputeError` on reader or track
    ///   failures.
    nonisolated func precompute(
        audioURL: URL,
        samplesPerSecond: Int = 100
    ) async throws -> PrecomputedWaveform {
        guard samplesPerSecond >= 1 else {
            throw WaveformPrecomputeError.invalidSamplesPerSecond(samplesPerSecond)
        }

        // Cache hit — short-circuit.
        if let cached = await WaveformPrecomputeCache.shared.get(audioURL) {
            return cached
        }

        await markBusy(delta: +1)
        defer { Task { @MainActor [weak self] in self?.markBusy(delta: -1) } }

        do {
            let waveform = try await Self.computeUncached(
                audioURL: audioURL,
                samplesPerSecond: samplesPerSecond
            )
            await WaveformPrecomputeCache.shared.put(audioURL, waveform)
            await setLastError(nil)
            return waveform
        } catch let error as WaveformPrecomputeError {
            await setLastError(error)
            throw error
        } catch {
            let wrapped = WaveformPrecomputeError.readingFailed(
                error.localizedDescription
            )
            await setLastError(wrapped)
            throw wrapped
        }
    }

    // MARK: - MainActor helpers

    @MainActor
    private func markBusy(delta: Int) {
        inFlightCount = max(0, inFlightCount + delta)
    }

    @MainActor
    private func setLastError(_ error: WaveformPrecomputeError?) {
        lastError = error
    }

    // MARK: - Compute core

    /// Read `audioURL` with AVAssetReader and produce paired
    /// peak+RMS arrays at `samplesPerSecond` resolution.
    ///
    /// Runs fully off the main actor on the async executor.
    private static func computeUncached(
        audioURL: URL,
        samplesPerSecond: Int
    ) async throws -> PrecomputedWaveform {
        let asset = AVURLAsset(url: audioURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw WaveformPrecomputeError.noAudioTrack
        }

        let durationCM = try await asset.load(.duration)
        let durationSec = CMTimeGetSeconds(durationCM)

        // Output settings: mono, Float32, linear PCM. 44.1 kHz is
        // our target source rate (AVAssetReader will resample).
        let sourceSampleRate: Double = 44_100
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sourceSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw WaveformPrecomputeError.readerCreationFailed(
                error.localizedDescription
            )
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: outputSettings
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw WaveformPrecomputeError.readerCreationFailed(
                "Cannot add track output"
            )
        }
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformPrecomputeError.readingFailed(
                reader.error?.localizedDescription ?? "startReading() returned false"
            )
        }

        // One output sample per `samplesPerBucket` source samples.
        // e.g. 44100 source samples / 100 sps = 441 samples/bucket.
        let samplesPerBucket = max(1, Int(sourceSampleRate) / samplesPerSecond)

        var peaks: [Float] = []
        var rms: [Float] = []
        peaks.reserveCapacity(Int(durationSec * Double(samplesPerSecond)))
        rms.reserveCapacity(Int(durationSec * Double(samplesPerSecond)))

        // Carry-over buffer for partial buckets spanning CMSampleBuffer
        // boundaries.
        var carry: [Float] = []
        carry.reserveCapacity(samplesPerBucket)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }

            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: nil,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let dataPointer else {
                continue
            }

            let floatCount = length / MemoryLayout<Float>.size
            let floatPointer = UnsafeRawPointer(dataPointer)
                .assumingMemoryBound(to: Float.self)
            let samples = UnsafeBufferPointer(
                start: floatPointer,
                count: floatCount
            )

            processSamples(
                samples: samples,
                samplesPerBucket: samplesPerBucket,
                carry: &carry,
                peaks: &peaks,
                rms: &rms
            )
        }

        // Flush trailing partial bucket, if any.
        if !carry.isEmpty {
            let (peak, rmsValue) = peakAndRMS(of: carry)
            peaks.append(peak)
            rms.append(rmsValue)
            carry.removeAll(keepingCapacity: false)
        }

        if reader.status == .failed {
            throw WaveformPrecomputeError.readingFailed(
                reader.error?.localizedDescription ?? "reader.status == .failed"
            )
        }

        return PrecomputedWaveform(
            peaks: peaks,
            rms: rms,
            durationSec: durationSec.isFinite ? durationSec : 0,
            samplesPerSecond: samplesPerSecond
        )
    }

    // MARK: - Sample processing

    /// Walks `samples` in `samplesPerBucket`-wide windows, emitting
    /// one peak + one RMS per full window. Leftover (< bucket)
    /// samples are placed into `carry` for the next call.
    private static func processSamples(
        samples: UnsafeBufferPointer<Float>,
        samplesPerBucket: Int,
        carry: inout [Float],
        peaks: inout [Float],
        rms: inout [Float]
    ) {
        var offset = 0
        let total = samples.count

        // Drain the carry buffer first if we can complete a bucket.
        if !carry.isEmpty {
            let needed = samplesPerBucket - carry.count
            if needed <= total {
                carry.append(contentsOf: samples[0..<needed])
                let (peak, rmsValue) = peakAndRMS(of: carry)
                peaks.append(peak)
                rms.append(rmsValue)
                carry.removeAll(keepingCapacity: true)
                offset = needed
            } else {
                carry.append(contentsOf: samples[0..<total])
                return
            }
        }

        // Process aligned full buckets via vDSP.
        while offset + samplesPerBucket <= total {
            let window = samples.baseAddress!.advanced(by: offset)
            let (peak, rmsValue) = peakAndRMS(
                pointer: window,
                count: samplesPerBucket
            )
            peaks.append(peak)
            rms.append(rmsValue)
            offset += samplesPerBucket
        }

        // Stash remainder for next call.
        if offset < total {
            carry.append(contentsOf: samples[offset..<total])
        }
    }

    /// Peak + RMS of a `[Float]` window (used for the trailing
    /// partial bucket and carry-over buffer). Values are clamped
    /// to 0.0 ... 1.0.
    private static func peakAndRMS(of window: [Float]) -> (peak: Float, rms: Float) {
        guard !window.isEmpty else { return (0, 0) }
        return window.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return (0, 0) }
            return peakAndRMS(pointer: base, count: buffer.count)
        }
    }

    /// Peak + RMS of a contiguous `Float` buffer, using Accelerate.
    /// Values are clamped to 0.0 ... 1.0.
    private static func peakAndRMS(
        pointer: UnsafePointer<Float>,
        count: Int
    ) -> (peak: Float, rms: Float) {
        guard count > 0 else { return (0, 0) }
        var peak: Float = 0
        var rmsValue: Float = 0
        let n = vDSP_Length(count)

        vDSP_maxmgv(pointer, 1, &peak, n) // max absolute value
        vDSP_rmsqv(pointer, 1, &rmsValue, n) // root-mean-square

        let clampedPeak = min(max(peak, 0), 1)
        let clampedRMS = min(max(rmsValue, 0), 1)
        return (clampedPeak, clampedRMS)
    }
}
