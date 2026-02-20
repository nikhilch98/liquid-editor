// WaveformExtractor.swift
// LiquidEditor
//
// Extracts waveform peak data from audio assets for visual display.
// Uses AVAssetReader for PCM extraction and Accelerate/vDSP for
// efficient peak detection.

import AVFoundation
import Accelerate

// MARK: - WaveformLevelOfDetail

/// Level of detail for waveform extraction.
///
/// Controls the temporal resolution of the output waveform data.
/// Higher detail produces more samples per second of audio.
enum WaveformLevelOfDetail: String, Sendable {
    /// 1 sample per 100ms (~10 samples/second).
    case low

    /// 1 sample per 10ms (~100 samples/second).
    case medium

    /// 1 sample per 1ms (~1000 samples/second).
    case high

    /// Number of source samples per output bucket at the given sample rate.
    func samplesPerBucket(sampleRate: Int = 44100) -> Int {
        switch self {
        case .low:    sampleRate / 10     // 4410 samples -> 100ms
        case .medium: sampleRate / 100    // 441 samples -> 10ms
        case .high:   sampleRate / 1000   // ~44 samples -> 1ms
        }
    }

    /// Output sample rate for this LOD (samples per second).
    var outputSampleRate: Int {
        switch self {
        case .low:    10
        case .medium: 100
        case .high:   1000
        }
    }
}

// MARK: - WaveformData

/// Result of waveform extraction.
///
/// Contains normalized peak samples suitable for drawing waveform
/// visualizations. All samples are in the range 0.0 to 1.0.
struct WaveformData: Sendable {
    /// Normalized peak amplitude samples (0.0 to 1.0).
    let samples: [Float]

    /// Output sample rate (samples per second).
    let sampleRate: Int

    /// Total duration of the source audio in microseconds.
    let durationMicros: Int64

    /// Level of detail used for extraction.
    let levelOfDetail: WaveformLevelOfDetail
}

// MARK: - WaveformExtractorError

/// Errors thrown by WaveformExtractor operations.
enum WaveformExtractorError: Error, LocalizedError, Sendable {
    case invalidPath(String)
    case noAudioTrack
    case readerCreationFailed(String)
    case readingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            "Invalid audio file path: \(path)"
        case .noAudioTrack:
            "No audio track found in asset"
        case .readerCreationFailed(let reason):
            "Failed to create asset reader: \(reason)"
        case .readingFailed(let reason):
            "Audio reading failed: \(reason)"
        }
    }
}

// MARK: - WaveformExtractor

/// Extracts waveform peak data from audio assets.
///
/// Uses `AVAssetReader` for PCM extraction and Accelerate `vDSP`
/// for efficient peak detection. All I/O runs on the actor's
/// serial executor.
///
/// ## Usage
///
/// ```swift
/// let extractor = WaveformExtractor()
/// let waveform = try await extractor.extractWaveform(
///     assetPath: "/path/to/audio.m4a",
///     levelOfDetail: .medium
/// )
/// // waveform.samples contains normalized peaks
/// ```
actor WaveformExtractor {

    /// Standard sample rate for PCM conversion.
    private let standardSampleRate: Int = 44100

    // MARK: - Extraction

    /// Extract waveform peak data from an audio file.
    ///
    /// Reads the audio file, converts to mono PCM Float32, and computes
    /// peak amplitudes at the specified level of detail. The output
    /// samples are normalized to the range 0.0 to 1.0.
    ///
    /// - Parameters:
    ///   - assetPath: File path to the audio asset.
    ///   - levelOfDetail: Temporal resolution for the output waveform.
    /// - Returns: `WaveformData` with normalized peak samples.
    /// - Throws: `WaveformExtractorError` on failure.
    func extractWaveform(
        assetPath: String,
        levelOfDetail: WaveformLevelOfDetail
    ) throws -> WaveformData {
        let url = URL(fileURLWithPath: assetPath)

        guard FileManager.default.fileExists(atPath: assetPath) else {
            throw WaveformExtractorError.invalidPath(assetPath)
        }

        let asset = AVURLAsset(url: url)

        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw WaveformExtractorError.noAudioTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw WaveformExtractorError.readerCreationFailed(error.localizedDescription)
        }

        // Request PCM Float32 mono output at standard sample rate
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: standardSampleRate,
            AVNumberOfChannelsKey: 1,
        ]

        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        reader.add(output)
        reader.startReading()

        let samplesPerBucket = levelOfDetail.samplesPerBucket(sampleRate: standardSampleRate)
        var peaks: [Float] = []

        // Residual buffer for leftover samples that don't fill a complete bucket.
        // Bounded to at most samplesPerBucket-1 elements (~4KB at most for low LOD).
        var residual: [Float] = []

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else {
                continue
            }

            var dataPointer: UnsafeMutablePointer<Int8>?
            var length = 0
            CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            )

            guard let ptr = dataPointer else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            let floatPointer = UnsafeRawPointer(ptr)
                .bindMemory(to: Float.self, capacity: floatCount)

            // Process directly from the raw pointer without copying into a growing buffer.
            var offset = 0

            // First, complete any partial bucket from the residual
            if !residual.isEmpty {
                let needed = samplesPerBucket - residual.count
                let available = min(needed, floatCount)
                residual.append(contentsOf: UnsafeBufferPointer(
                    start: floatPointer,
                    count: available
                ))
                offset = available

                if residual.count >= samplesPerBucket {
                    var peak: Float = 0
                    vDSP_maxmgv(residual, 1, &peak, vDSP_Length(residual.count))
                    peaks.append(peak)
                    residual.removeAll(keepingCapacity: true)
                }
            }

            // Process complete buckets directly from the pointer (zero-copy)
            while offset + samplesPerBucket <= floatCount {
                var peak: Float = 0
                vDSP_maxmgv(
                    floatPointer.advanced(by: offset), 1,
                    &peak,
                    vDSP_Length(samplesPerBucket)
                )
                peaks.append(peak)
                offset += samplesPerBucket
            }

            // Store leftover samples in the residual (always < samplesPerBucket)
            if offset < floatCount {
                residual.append(contentsOf: UnsafeBufferPointer(
                    start: floatPointer.advanced(by: offset),
                    count: floatCount - offset
                ))
            }

            CMSampleBufferInvalidate(buffer)
        }

        if reader.status == .failed {
            throw WaveformExtractorError.readingFailed(
                reader.error?.localizedDescription ?? "Unknown error"
            )
        }

        // Process remaining samples in the residual
        if !residual.isEmpty {
            var peak: Float = 0
            vDSP_maxmgv(residual, 1, &peak, vDSP_Length(residual.count))
            peaks.append(peak)
        }

        // Normalize peaks to 0.0 - 1.0
        normalizePeaks(&peaks)

        let durationMicros = Int64(CMTimeGetSeconds(asset.duration) * 1_000_000)

        return WaveformData(
            samples: peaks,
            sampleRate: levelOfDetail.outputSampleRate,
            durationMicros: durationMicros,
            levelOfDetail: levelOfDetail
        )
    }

    // MARK: - Normalization

    /// Normalize peak values to the range 0.0 to 1.0.
    private func normalizePeaks(_ peaks: inout [Float]) {
        guard !peaks.isEmpty else { return }

        var maxPeak: Float = 0
        vDSP_maxv(peaks, 1, &maxPeak, vDSP_Length(peaks.count))

        guard maxPeak > 0 else { return }

        var divisor = maxPeak
        vDSP_vsdiv(peaks, 1, &divisor, &peaks, 1, vDSP_Length(peaks.count))
    }
}
