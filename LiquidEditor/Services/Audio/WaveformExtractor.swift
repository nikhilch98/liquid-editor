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

        // Streaming bucket state: we never materialise a residual sample buffer.
        // When a bucket spans a chunk boundary we carry forward only the running
        // peak (a single Float) and the number of samples already counted. This
        // keeps peak memory O(1) with respect to file length.
        var bucketPeak: Float = 0
        var bucketFilled: Int = 0

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

            guard let ptr = dataPointer else {
                CMSampleBufferInvalidate(buffer)
                continue
            }

            let floatCount = length / MemoryLayout<Float>.size
            let floatPointer = UnsafeRawPointer(ptr)
                .bindMemory(to: Float.self, capacity: floatCount)

            // Process the chunk in-place against the raw pointer. No sample
            // arrays are allocated — we only update scalar bucket state.
            processChunk(
                pointer: floatPointer,
                count: floatCount,
                samplesPerBucket: samplesPerBucket,
                bucketPeak: &bucketPeak,
                bucketFilled: &bucketFilled,
                peaks: &peaks
            )

            CMSampleBufferInvalidate(buffer)
        }

        if reader.status == .failed {
            throw WaveformExtractorError.readingFailed(
                reader.error?.localizedDescription ?? "Unknown error"
            )
        }

        // Flush the trailing partial bucket (if any) as a final peak.
        if bucketFilled > 0 {
            peaks.append(bucketPeak)
            bucketPeak = 0
            bucketFilled = 0
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

    // MARK: - Streaming Chunk Processing

    /// Process a single decoded PCM chunk, emitting completed bucket peaks
    /// directly into `peaks` and carrying the running scalar state forward
    /// for any bucket that straddles the chunk boundary.
    ///
    /// Memory cost is O(1) per chunk — the only state kept across chunks is
    /// the current bucket's running peak magnitude and the count of samples
    /// already folded into it. The chunk itself is read through the raw
    /// pointer and never copied into a Swift array.
    ///
    /// - Parameters:
    ///   - pointer: Base pointer to the decoded Float32 PCM chunk.
    ///   - count: Number of Float samples in the chunk.
    ///   - samplesPerBucket: Target bucket width for the requested LOD.
    ///   - bucketPeak: Running max-magnitude for the in-progress bucket.
    ///   - bucketFilled: Samples already folded into the in-progress bucket.
    ///   - peaks: Output buffer — completed bucket peaks are appended here.
    private nonisolated func processChunk(
        pointer: UnsafePointer<Float>,
        count: Int,
        samplesPerBucket: Int,
        bucketPeak: inout Float,
        bucketFilled: inout Int,
        peaks: inout [Float]
    ) {
        guard count > 0, samplesPerBucket > 0 else { return }

        var offset = 0

        // Finish the in-progress bucket first (if one is carried from the
        // previous chunk) by folding in just enough samples to complete it.
        if bucketFilled > 0 {
            let needed = samplesPerBucket - bucketFilled
            let take = min(needed, count)
            var slicePeak: Float = 0
            vDSP_maxmgv(pointer, 1, &slicePeak, vDSP_Length(take))
            bucketPeak = max(bucketPeak, slicePeak)
            bucketFilled += take
            offset = take

            if bucketFilled >= samplesPerBucket {
                peaks.append(bucketPeak)
                bucketPeak = 0
                bucketFilled = 0
            }
        }

        // Emit complete buckets directly from the pointer (zero-copy).
        while offset + samplesPerBucket <= count {
            var peak: Float = 0
            vDSP_maxmgv(
                pointer.advanced(by: offset), 1,
                &peak,
                vDSP_Length(samplesPerBucket)
            )
            peaks.append(peak)
            offset += samplesPerBucket
        }

        // Fold any trailing partial bucket into the running state (scalar
        // only — the samples themselves are discarded with the chunk).
        if offset < count {
            let remaining = count - offset
            var slicePeak: Float = 0
            vDSP_maxmgv(
                pointer.advanced(by: offset), 1,
                &slicePeak,
                vDSP_Length(remaining)
            )
            bucketPeak = max(bucketPeak, slicePeak)
            bucketFilled += remaining
        }
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
