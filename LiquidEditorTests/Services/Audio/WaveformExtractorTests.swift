// WaveformExtractorTests.swift
// LiquidEditorTests
//
// Tests for WaveformExtractor focusing on:
// - Correctness of downsampled peak output
// - Bounded memory footprint for long (10M-sample) inputs after the
//   streaming-chunk refactor (no full-sample accumulation buffer)
// - Error cases for missing files and tracks
//
// Input fixtures are synthesised as mono Int16 WAV files on disk; the
// extractor transparently converts them to mono Float32 @ 44.1 kHz via
// its AVAssetReader output settings.

import Testing
import Foundation
import Darwin.Mach
@testable import LiquidEditor

// MARK: - Mach memory helper

/// Resident memory of the current task, in bytes. Returns nil if the
/// Mach call fails (shouldn't happen on simulator/device).
private func currentResidentBytes() -> UInt64? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
    )
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                rebound,
                &count
            )
        }
    }
    return kerr == KERN_SUCCESS ? info.resident_size : nil
}

// MARK: - WAV Fixture Writer

/// Writes a mono Int16 PCM WAV at 44.1 kHz to `url`. Samples are streamed
/// to disk in 64 KiB chunks so the fixture itself does not force the test
/// process to allocate the whole buffer in memory.
///
/// - Parameters:
///   - url: Destination file URL.
///   - sampleCount: Total Int16 samples to write.
///   - generator: Closure returning the Int16 sample at a given index.
private func writeMonoInt16WAV(
    to url: URL,
    sampleCount: Int,
    generator: (Int) -> Int16
) throws {
    let sampleRate: UInt32 = 44_100
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
    let blockAlign: UInt16 = channels * bitsPerSample / 8
    let dataBytes: UInt32 = UInt32(sampleCount) * UInt32(blockAlign)
    let riffChunkSize: UInt32 = 36 + dataBytes

    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }

    // RIFF header
    var header = Data()
    header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    header.append(contentsOf: UInt32LE(riffChunkSize))
    header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    // fmt subchunk (PCM, format code 1)
    header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    header.append(contentsOf: UInt32LE(16))                          // subchunk size
    header.append(contentsOf: UInt16LE(1))                           // audio format: PCM
    header.append(contentsOf: UInt16LE(channels))
    header.append(contentsOf: UInt32LE(sampleRate))
    header.append(contentsOf: UInt32LE(byteRate))
    header.append(contentsOf: UInt16LE(blockAlign))
    header.append(contentsOf: UInt16LE(bitsPerSample))
    // data subchunk
    header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    header.append(contentsOf: UInt32LE(dataBytes))
    try handle.write(contentsOf: header)

    // Stream samples in 32 Ki-sample (64 KiB) chunks.
    let chunkSamples = 32 * 1024
    var buffer = Data(count: chunkSamples * MemoryLayout<Int16>.size)
    var written = 0
    while written < sampleCount {
        let n = min(chunkSamples, sampleCount - written)
        buffer.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: Int16.self).baseAddress!
            for i in 0..<n {
                p[i] = generator(written + i).littleEndian
            }
        }
        try handle.write(contentsOf: buffer.prefix(n * MemoryLayout<Int16>.size))
        written += n
    }
}

private func UInt32LE(_ value: UInt32) -> [UInt8] {
    let v = value.littleEndian
    return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
}

private func UInt16LE(_ value: UInt16) -> [UInt8] {
    let v = value.littleEndian
    return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
}

// MARK: - Tests

@Suite("WaveformExtractor Tests")
struct WaveformExtractorTests {

    // MARK: - Error cases

    @Test("Missing file throws invalidPath")
    func missingFileThrows() async {
        let extractor = WaveformExtractor()
        let bogus = "/tmp/definitely-not-a-real-file-\(UUID().uuidString).wav"
        await #expect(throws: WaveformExtractorError.self) {
            _ = try await extractor.extractWaveform(
                assetPath: bogus,
                levelOfDetail: .low
            )
        }
    }

    // MARK: - Streaming correctness + bounded memory (10M samples)

    /// Writes a ~10M-sample mono Int16 WAV, runs `extractWaveform`, and
    /// verifies:
    ///   - the routine completes without OOM on a long input,
    ///   - the peak count matches ceil(sampleCount / samplesPerBucket),
    ///   - the normalized peaks are plausible (non-empty, within [0, 1],
    ///     with max == 1.0 after normalization),
    ///   - the resident memory growth during extraction stays well below
    ///     the size of the raw sample buffer (40 MB for Float32 × 10M).
    ///     The streaming refactor must keep extra memory O(peaks) rather
    ///     than O(samples); we assert < 20 MB of growth as a loose bound
    ///     that still catches an accidental re-introduction of a full
    ///     sample accumulator.
    @Test("Long 10M-sample input extracts with bounded peak memory")
    func longInputStreamsWithBoundedMemory() async throws {
        let sampleCount = 10_000_000
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent(
            "waveform-stream-\(UUID().uuidString).wav"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        // A slowly ramping sine-ish pattern so peaks vary across buckets.
        // Magnitude is bounded by ~Int16.max / 2 -> ~0.5 before normalize,
        // which then normalizes to 1.0.
        let amplitude: Int16 = 16_000
        try writeMonoInt16WAV(to: url, sampleCount: sampleCount) { i in
            // Alternating sign square-ish wave with a slow envelope so
            // every bucket sees a non-zero peak.
            let phase = (i / 1024) % 2 == 0 ? Int16(1) : Int16(-1)
            return phase &* amplitude
        }

        let extractor = WaveformExtractor()

        // Measure resident memory before and during/after extraction. We
        // cannot sample mid-call without a timer; asserting the delta on
        // the way out still catches the regression where the extractor
        // accumulates all samples before downsampling (that would leave
        // a large allocation reachable at return time, or at minimum
        // cause autoreleased buffers well above our bound).
        let before = currentResidentBytes() ?? 0

        let waveform = try await extractor.extractWaveform(
            assetPath: url.path,
            levelOfDetail: .low // 4410 samples / bucket
        )

        let after = currentResidentBytes() ?? 0
        let growth = after > before ? after - before : 0

        // Correctness: bucket count.
        let samplesPerBucket = WaveformLevelOfDetail.low
            .samplesPerBucket(sampleRate: 44_100)
        let expectedBuckets = (sampleCount + samplesPerBucket - 1) / samplesPerBucket
        // AVAssetReader may drop or pad by a handful of frames at the
        // container boundary; allow a small tolerance.
        #expect(abs(waveform.samples.count - expectedBuckets) <= 4)

        // Correctness: normalized range.
        #expect(!waveform.samples.isEmpty)
        let maxPeak = waveform.samples.max() ?? 0
        let minPeak = waveform.samples.min() ?? 0
        #expect(maxPeak <= 1.0 + 1e-5)
        #expect(minPeak >= 0)
        #expect(maxPeak > 0.99) // normalization should push max to 1.0

        // Bounded memory: growth must stay well under the size of a full
        // Float32 accumulator for 10M samples (40 MB). A 20 MB cap still
        // comfortably catches a regression to whole-file buffering while
        // giving headroom for the peaks array (~2,300 floats), the WAV
        // fixture cache, and AVAssetReader's own decode buffers.
        let boundedBytes: UInt64 = 20 * 1024 * 1024
        #expect(
            growth < boundedBytes,
            "Resident memory grew by \(growth) bytes, expected < \(boundedBytes). The streaming refactor may have regressed."
        )
    }
}
