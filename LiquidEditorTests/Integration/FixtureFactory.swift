// FixtureFactory.swift
// LiquidEditorTests
//
// Generates small media fixtures for integration tests.
//
// Fixtures are generated lazily at runtime into a cached temp directory
// (keyed on hardcoded parameters) so they persist across tests in the
// same test-run but are never checked into source control.
//
// ## Design
//
// We deliberately generate fixtures at RUNTIME rather than bundling pre-built
// binaries for three reasons:
//
// 1. Keeps the repo slim — no 500 KB video blob committed.
// 2. Parameters (duration, fps, tone, resolution) stay visible in Swift code.
// 3. Sidesteps `xcodegen`/Xcode resource-copy quirks — the fixtures live in
//    the test process's cache directory, which is always writable.
//
// If you later want to check in pre-built fixtures, drop them into
// `LiquidEditorTests/Fixtures/` and `FixtureFactory` will prefer them over
// runtime generation.
//
// ## Usage
//
// ```swift
// let videoURL = try await FixtureFactory.sampleVideoURL()
// let audioURL = try await FixtureFactory.sampleAudioURL()
// ```
//
// The produced files match the task spec:
//   - sample_video.mp4 — 2s, 320x240, 30 fps, black with moving red dot.
//   - sample_audio.wav — 2s, 44.1 kHz mono, 440 Hz sine.

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

enum FixtureFactoryError: Error, CustomStringConvertible {
    case writerCreationFailed(String)
    case writerStartFailed(String)
    case writerAppendFailed(String)
    case writerFinishFailed(String)
    case pixelBufferCreationFailed
    case audioFormatCreationFailed
    case audioBufferCreationFailed
    case audioWriteFailed(String)

    var description: String {
        switch self {
        case .writerCreationFailed(let m): return "AVAssetWriter creation failed: \(m)"
        case .writerStartFailed(let m): return "AVAssetWriter start failed: \(m)"
        case .writerAppendFailed(let m): return "AVAssetWriter append failed: \(m)"
        case .writerFinishFailed(let m): return "AVAssetWriter finish failed: \(m)"
        case .pixelBufferCreationFailed: return "CVPixelBuffer creation failed"
        case .audioFormatCreationFailed: return "AVAudioFormat creation failed"
        case .audioBufferCreationFailed: return "AVAudioPCMBuffer creation failed"
        case .audioWriteFailed(let m): return "Audio write failed: \(m)"
        }
    }
}

/// Generates and caches tiny media fixtures for integration tests.
///
/// All methods return file URLs pointing at existing files. The files persist
/// for the lifetime of the test process's tmp directory (typically the entire
/// simulator session) and are regenerated on demand.
enum FixtureFactory {

    // MARK: - Constants

    /// Duration of every generated fixture, in seconds.
    static let durationSeconds: Double = 2.0

    /// Video dimensions — deliberately tiny to keep the file well under 500 KB.
    static let videoWidth: Int = 320
    static let videoHeight: Int = 240
    static let videoFPS: Int32 = 30

    /// Audio parameters — deliberately simple to keep the file well under 200 KB.
    static let audioSampleRate: Double = 44_100
    static let audioFrequency: Double = 440
    static let audioChannels: AVAudioChannelCount = 1

    // MARK: - Public API

    /// Returns a URL to a 2 s / 320x240 / 30 fps H.264 MP4 with a moving red dot.
    ///
    /// The first call generates the file in the process tmp directory; subsequent
    /// calls return the cached URL immediately.
    static func sampleVideoURL() async throws -> URL {
        let url = cacheDir.appendingPathComponent("sample_video.mp4")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        if let bundled = bundledFixtureURL(name: "sample_video", ext: "mp4") {
            try? FileManager.default.copyItem(at: bundled, to: url)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        try await generateSampleVideo(at: url)
        return url
    }

    /// Returns a URL to a 2 s / 44.1 kHz / mono WAV of a 440 Hz sine wave.
    static func sampleAudioURL() async throws -> URL {
        let url = cacheDir.appendingPathComponent("sample_audio.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        if let bundled = bundledFixtureURL(name: "sample_audio", ext: "wav") {
            try? FileManager.default.copyItem(at: bundled, to: url)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        try generateSampleAudio(at: url)
        return url
    }

    /// Remove all cached fixtures. Useful if a test corrupts one.
    static func purgeCache() {
        try? FileManager.default.removeItem(at: cacheDir)
    }

    // MARK: - Paths

    private static let cacheDir: URL = {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiquidEditorFixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// Looks for a pre-built fixture inside the test bundle's `Fixtures/` folder.
    /// Returns `nil` if not present, allowing fallback to runtime generation.
    private static func bundledFixtureURL(name: String, ext: String) -> URL? {
        let bundle = Bundle(for: BundleMarker.self)
        if let direct = bundle.url(forResource: name, withExtension: ext) {
            return direct
        }
        if let subdir = bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") {
            return subdir
        }
        return nil
    }

    private final class BundleMarker {}

    // MARK: - Video Generation

    private static func generateSampleVideo(at outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw FixtureFactoryError.writerCreationFailed(error.localizedDescription)
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 400_000, // ~400 kbps -> ~100 KB/2s
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
            ],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(input) else {
            throw FixtureFactoryError.writerStartFailed("cannot add video input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw FixtureFactoryError.writerStartFailed(
                writer.error?.localizedDescription ?? "unknown"
            )
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = Int(Double(videoFPS) * durationSeconds)
        let frameDuration = CMTime(value: 1, timescale: videoFPS)

        for frameIndex in 0..<totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }

            guard let pool = adaptor.pixelBufferPool else {
                throw FixtureFactoryError.pixelBufferCreationFailed
            }

            var maybeBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &maybeBuffer)
            guard let buffer = maybeBuffer else {
                throw FixtureFactoryError.pixelBufferCreationFailed
            }

            try drawFrame(into: buffer, frameIndex: frameIndex, totalFrames: totalFrames)

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            if !adaptor.append(buffer, withPresentationTime: presentationTime) {
                throw FixtureFactoryError.writerAppendFailed(
                    writer.error?.localizedDescription ?? "unknown"
                )
            }
        }

        input.markAsFinished()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                cont.resume()
            }
        }

        if writer.status != .completed {
            throw FixtureFactoryError.writerFinishFailed(
                writer.error?.localizedDescription ?? "status=\(writer.status.rawValue)"
            )
        }
    }

    /// Draw a single frame: black background with a red dot moving left-to-right.
    /// Gives motion trackers something to lock onto.
    private static func drawFrame(
        into buffer: CVPixelBuffer,
        frameIndex: Int,
        totalFrames: Int
    ) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FixtureFactoryError.pixelBufferCreationFailed
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw FixtureFactoryError.pixelBufferCreationFailed
        }

        // Black background
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Red dot moving L->R across the width
        let progress = Double(frameIndex) / Double(max(totalFrames - 1, 1))
        let dotRadius: CGFloat = 12
        let margin: CGFloat = dotRadius + 4
        let cx = margin + CGFloat(progress) * (CGFloat(width) - 2 * margin)
        let cy = CGFloat(height) / 2

        context.setFillColor(red: 1, green: 0.1, blue: 0.1, alpha: 1)
        context.fillEllipse(in: CGRect(
            x: cx - dotRadius,
            y: cy - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))
    }

    // MARK: - Audio Generation

    private static func generateSampleAudio(at outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audioSampleRate,
            channels: audioChannels,
            interleaved: false
        ) else {
            throw FixtureFactoryError.audioFormatCreationFailed
        }

        // Write WAV Int16 PCM — smaller file, broader compatibility.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audioSampleRate,
            AVNumberOfChannelsKey: Int(audioChannels),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: outputURL, settings: settings)
        } catch {
            throw FixtureFactoryError.audioWriteFailed(error.localizedDescription)
        }

        let totalFrames = AVAudioFrameCount(audioSampleRate * durationSeconds)
        let chunkFrames: AVAudioFrameCount = 4_096
        var framesWritten: AVAudioFrameCount = 0
        var phase: Double = 0
        let phaseIncrement = 2.0 * .pi * audioFrequency / audioSampleRate

        while framesWritten < totalFrames {
            let framesThisChunk = min(chunkFrames, totalFrames - framesWritten)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesThisChunk
            ) else {
                throw FixtureFactoryError.audioBufferCreationFailed
            }
            buffer.frameLength = framesThisChunk

            if let channel = buffer.floatChannelData?[0] {
                for i in 0..<Int(framesThisChunk) {
                    channel[i] = Float(sin(phase) * 0.3) // -10 dBFS peak
                    phase += phaseIncrement
                    if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                }
            }

            do {
                try file.write(from: buffer)
            } catch {
                throw FixtureFactoryError.audioWriteFailed(error.localizedDescription)
            }
            framesWritten += framesThisChunk
        }
    }
}
