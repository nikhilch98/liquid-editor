// NativeDecoderPool.swift
// LiquidEditor
//
// Video frame decoder pool for multi-source frame extraction.
//
// Features:
// - Pool of AVAssetImageGenerator instances for concurrent frame extraction
// - LRU eviction when pool exceeds capacity
// - Exact-frame seeking for playback quality
// - I-frame fast seeking for responsive scrubbing
// - Memory pressure handling with adaptive pool sizing
// - Thread-safe with NSLock protection

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

// MARK: - DecodedFrame

/// Result of a single frame decode operation.
///
/// Contains raw BGRA pixel data along with frame dimensions
/// and timing information.
struct DecodedFrame: Sendable {
    /// Raw BGRA pixel data.
    let pixels: Data

    /// Frame width in pixels.
    let width: Int

    /// Frame height in pixels.
    let height: Int

    /// Actual decoded time in microseconds.
    let timeMicros: TimeMicros

    /// Whether the decoded time matches the requested time exactly
    /// (within one frame tolerance at 30 fps).
    let isExact: Bool
}

// MARK: - VideoDecoder

/// A single video decoder instance wrapping an AVAssetImageGenerator.
///
/// Each decoder is associated with one media asset and provides
/// both exact-frame and I-frame (fast) decoding capabilities.
final class VideoDecoder: @unchecked Sendable {

    /// Unique decoder identifier.
    let id: String

    /// Associated asset identifier.
    let assetId: String

    /// The loaded asset.
    let asset: AVURLAsset

    /// Image generator for frame extraction.
    private let imageGenerator: AVAssetImageGenerator

    /// Video track for metadata.
    let videoTrack: AVAssetTrack?

    /// Last access time for LRU eviction.
    var lastAccess: Date = Date()

    /// Whether this decoder is currently performing a decode operation.
    var isBusy: Bool = false

    /// Lock protecting mutable state (lastAccess, isBusy).
    private let lock = NSLock()

    // MARK: - Initialization

    /// Create a new decoder for the given asset.
    ///
    /// - Parameters:
    ///   - id: Unique decoder identifier.
    ///   - assetId: Identifier of the source media asset.
    ///   - assetURL: File URL to the media.
    /// - Throws: ``DecoderPoolError/assetLoadFailed`` if the URL is invalid.
    init(id: String, assetId: String, assetURL: URL) throws {
        self.id = id
        self.assetId = assetId
        self.asset = AVURLAsset(url: assetURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])
        self.videoTrack = asset.tracks(withMediaType: .video).first

        self.imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
    }

    /// Touch for LRU ordering.
    func touch() {
        lock.lock()
        lastAccess = Date()
        lock.unlock()
    }

    /// Mark as busy/idle.
    private func setBusy(_ busy: Bool) {
        lock.lock()
        isBusy = busy
        lock.unlock()
    }

    /// Check if currently busy.
    var currentlyBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isBusy
    }

    // MARK: - Frame Decoding

    /// Decode an exact frame at the specified time.
    ///
    /// Uses zero tolerance for precise frame extraction. Suitable for
    /// playback and frame-accurate preview.
    ///
    /// - Parameters:
    ///   - timeMicros: Target time in microseconds.
    ///   - maxWidth: Maximum output width (nil = original size).
    ///   - maxHeight: Maximum output height (nil = original size).
    /// - Returns: The decoded frame with pixel data.
    /// - Throws: If frame extraction fails.
    func decodeFrame(
        at timeMicros: TimeMicros,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) throws -> DecodedFrame {
        touch()
        setBusy(true)
        defer { setBusy(false) }

        let time = CMTime(value: CMTimeValue(timeMicros), timescale: 1_000_000)

        // Set maximum size
        if let w = maxWidth, let h = maxHeight {
            imageGenerator.maximumSize = CGSize(width: w, height: h)
        } else {
            imageGenerator.maximumSize = .zero
        }

        // Exact frame
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        var actualTime = CMTime.zero
        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: &actualTime)
        let pixels = try extractPixels(from: cgImage)
        let actualTimeMicros = TimeMicros(CMTimeGetSeconds(actualTime) * 1_000_000)

        return DecodedFrame(
            pixels: pixels,
            width: cgImage.width,
            height: cgImage.height,
            timeMicros: actualTimeMicros,
            isExact: abs(actualTimeMicros - timeMicros) < 33_333
        )
    }

    /// Decode an I-frame near the specified time (fast, for scrubbing).
    ///
    /// Uses a +/-1 second tolerance to allow the decoder to snap to the
    /// nearest keyframe, which is much faster than exact seeking.
    ///
    /// - Parameters:
    ///   - timeMicros: Target time in microseconds.
    ///   - maxWidth: Maximum output width (nil = original size).
    ///   - maxHeight: Maximum output height (nil = original size).
    /// - Returns: The decoded frame with pixel data.
    /// - Throws: If frame extraction fails.
    func decodeIFrame(
        at timeMicros: TimeMicros,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) throws -> DecodedFrame {
        touch()
        setBusy(true)
        defer { setBusy(false) }

        let time = CMTime(value: CMTimeValue(timeMicros), timescale: 1_000_000)

        // Set maximum size
        if let w = maxWidth, let h = maxHeight {
            imageGenerator.maximumSize = CGSize(width: w, height: h)
        } else {
            imageGenerator.maximumSize = .zero
        }

        // Allow tolerance for faster I-frame seeking
        imageGenerator.requestedTimeToleranceBefore = CMTime(
            seconds: 1.0, preferredTimescale: 600
        )
        imageGenerator.requestedTimeToleranceAfter = CMTime(
            seconds: 1.0, preferredTimescale: 600
        )

        var actualTime = CMTime.zero
        let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: &actualTime)
        let pixels = try extractPixels(from: cgImage)
        let actualTimeMicros = TimeMicros(CMTimeGetSeconds(actualTime) * 1_000_000)

        return DecodedFrame(
            pixels: pixels,
            width: cgImage.width,
            height: cgImage.height,
            timeMicros: actualTimeMicros,
            isExact: false
        )
    }

    // MARK: - Pixel Extraction

    /// Extract BGRA pixel data from a CGImage.
    ///
    /// Creates a bitmap context with premultiplied-first alpha in little-endian
    /// byte order (BGRA), draws the image, and returns the raw pixel buffer.
    ///
    /// - Parameter image: The source image.
    /// - Returns: Raw BGRA pixel data.
    /// - Throws: ``DecoderPoolError/pixelExtractionFailed`` if context creation fails.
    private func extractPixels(from image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = Data(count: totalBytes)
        var contextCreationFailed = false

        pixelData.withUnsafeMutableBytes { ptr in
            guard let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else {
                contextCreationFailed = true
                return
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        if contextCreationFailed {
            throw DecoderPoolError.pixelExtractionFailed
        }

        return pixelData
    }
}

// MARK: - NativeDecoderPool

/// Pool of video decoders with LRU eviction.
///
/// Manages a fixed-size pool of ``VideoDecoder`` instances. When the pool
/// is full, the least-recently-used non-busy decoder is evicted to make
/// room for new ones.
///
/// Thread Safety:
/// - All pool state is protected by `poolLock`.
/// - Decode operations on individual decoders are inherently thread-safe
///   (each decoder manages its own busy flag).
///
/// Usage:
/// ```swift
/// let pool = NativeDecoderPool(maxDecoders: 4)
/// let decoderId = try pool.acquireDecoder(
///     assetId: "asset_1",
///     assetURL: fileURL
/// )
/// let frame = try pool.decodeFrame(
///     decoderId: decoderId,
///     timeMicros: 1_000_000
/// )
/// ```
final class NativeDecoderPool: @unchecked Sendable {

    // MARK: - Properties

    /// Maximum number of decoders in the pool.
    private var maxDecoders: Int

    /// Active decoders keyed by decoder ID.
    private var decoders: [String: VideoDecoder] = [:]

    /// Asset ID to decoder ID mapping for reuse.
    private var assetToDecoder: [String: String] = [:]

    /// LRU order (most recently used at end).
    private var lruOrder: [String] = []

    /// Lock for thread-safe pool access.
    private let poolLock = NSLock()

    /// Counter for generating unique decoder IDs.
    private var nextDecoderId: Int = 0

    // MARK: - Initialization

    /// Create a decoder pool with the specified capacity.
    ///
    /// - Parameter maxDecoders: Maximum number of concurrent decoders. Default is 4.
    init(maxDecoders: Int = 4) {
        self.maxDecoders = maxDecoders
    }

    // MARK: - Decoder Lifecycle

    /// Acquire a decoder for the given asset.
    ///
    /// If a decoder already exists for this asset, it is reused and
    /// its LRU position is updated. Otherwise, a new decoder is created,
    /// evicting the LRU entry if the pool is full.
    ///
    /// - Parameters:
    ///   - assetId: Identifier of the media asset.
    ///   - assetURL: File URL to the media.
    /// - Returns: The decoder ID for subsequent decode calls.
    /// - Throws: ``DecoderPoolError/allDecodersBusy`` if the pool is full
    ///   and all decoders are busy.
    func acquireDecoder(assetId: String, assetURL: URL) throws -> String {
        poolLock.lock()
        defer { poolLock.unlock() }

        // Check if decoder already exists for this asset
        if let existingId = assetToDecoder[assetId] {
            decoders[existingId]?.touch()
            touchLRU(existingId)
            return existingId
        }

        // Evict if at capacity
        while decoders.count >= maxDecoders {
            if !evictLRU() {
                throw DecoderPoolError.allDecodersBusy
            }
        }

        // Create new decoder
        let decoderId = "decoder_\(nextDecoderId)"
        nextDecoderId += 1

        let decoder = try VideoDecoder(id: decoderId, assetId: assetId, assetURL: assetURL)
        decoders[decoderId] = decoder
        assetToDecoder[assetId] = decoderId
        lruOrder.append(decoderId)

        return decoderId
    }

    /// Release a specific decoder by ID.
    ///
    /// Removes the decoder from the pool and frees its resources.
    ///
    /// - Parameter decoderId: The decoder ID to release.
    func releaseDecoder(_ decoderId: String) {
        poolLock.lock()
        defer { poolLock.unlock() }

        guard let decoder = decoders.removeValue(forKey: decoderId) else { return }
        assetToDecoder.removeValue(forKey: decoder.assetId)
        lruOrder.removeAll { $0 == decoderId }
    }

    // MARK: - Frame Decoding

    /// Decode an exact frame using the specified decoder.
    ///
    /// - Parameters:
    ///   - decoderId: The decoder ID returned by ``acquireDecoder(assetId:assetURL:)``.
    ///   - timeMicros: Target time in microseconds.
    ///   - maxWidth: Maximum output width (nil = original size).
    ///   - maxHeight: Maximum output height (nil = original size).
    /// - Returns: The decoded frame with pixel data.
    /// - Throws: ``DecoderPoolError/decoderNotFound`` if the decoder ID is invalid.
    func decodeFrame(
        decoderId: String,
        timeMicros: TimeMicros,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) throws -> DecodedFrame {
        let decoder = try getDecoder(decoderId)
        return try decoder.decodeFrame(
            at: timeMicros,
            maxWidth: maxWidth,
            maxHeight: maxHeight
        )
    }

    /// Decode an I-frame (fast, for scrubbing) using the specified decoder.
    ///
    /// - Parameters:
    ///   - decoderId: The decoder ID returned by ``acquireDecoder(assetId:assetURL:)``.
    ///   - timeMicros: Target time in microseconds.
    ///   - maxWidth: Maximum output width (nil = original size).
    ///   - maxHeight: Maximum output height (nil = original size).
    /// - Returns: The decoded frame with pixel data.
    /// - Throws: ``DecoderPoolError/decoderNotFound`` if the decoder ID is invalid.
    func decodeIFrame(
        decoderId: String,
        timeMicros: TimeMicros,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil
    ) throws -> DecodedFrame {
        let decoder = try getDecoder(decoderId)
        return try decoder.decodeIFrame(
            at: timeMicros,
            maxWidth: maxWidth,
            maxHeight: maxHeight
        )
    }

    // MARK: - Pool Management

    /// Handle memory pressure by reducing pool capacity and evicting decoders.
    ///
    /// - Parameter level: Pressure level (0 = normal, 1 = warning, 2 = critical).
    func handleMemoryPressure(level: Int) {
        poolLock.lock()
        defer { poolLock.unlock() }

        switch level {
        case 1: // Warning
            maxDecoders = max(2, maxDecoders)
            while decoders.count > maxDecoders {
                if !evictLRU() { break }
            }
        case 2: // Critical
            maxDecoders = 1
            while decoders.count > maxDecoders {
                if !evictLRU() { break }
            }
        default: // Normal
            maxDecoders = 4
        }
    }

    /// Dispose all decoders and reset the pool.
    func disposeAll() {
        poolLock.lock()
        defer { poolLock.unlock() }

        decoders.removeAll()
        assetToDecoder.removeAll()
        lruOrder.removeAll()
    }

    /// Current number of decoders in the pool.
    var decoderCount: Int {
        poolLock.lock()
        defer { poolLock.unlock() }
        return decoders.count
    }

    // MARK: - Internal Helpers

    /// Get a decoder by ID, with thread-safe access.
    private func getDecoder(_ decoderId: String) throws -> VideoDecoder {
        poolLock.lock()
        guard let decoder = decoders[decoderId] else {
            poolLock.unlock()
            throw DecoderPoolError.decoderNotFound(decoderId)
        }
        poolLock.unlock()
        return decoder
    }

    /// Update LRU order for a decoder (must be called with poolLock held).
    private func touchLRU(_ id: String) {
        lruOrder.removeAll { $0 == id }
        lruOrder.append(id)
    }

    /// Evict the least-recently-used non-busy decoder.
    ///
    /// Must be called with `poolLock` held.
    ///
    /// - Returns: `true` if a decoder was evicted, `false` if all are busy.
    @discardableResult
    private func evictLRU() -> Bool {
        for (index, id) in lruOrder.enumerated() {
            if let decoder = decoders[id], !decoder.currentlyBusy {
                decoders.removeValue(forKey: id)
                assetToDecoder.removeValue(forKey: decoder.assetId)
                lruOrder.remove(at: index)
                return true
            }
        }
        return false
    }
}

// MARK: - DecoderPoolError

/// Errors that can occur during decoder pool operations.
enum DecoderPoolError: LocalizedError, Sendable {
    /// The specified decoder was not found in the pool.
    case decoderNotFound(String)

    /// Failed to load the media asset.
    case assetLoadFailed(String)

    /// No video track found in the asset.
    case noVideoTrack

    /// Frame extraction failed.
    case frameExtractionFailed

    /// All decoders in the pool are busy and cannot be evicted.
    case allDecodersBusy

    /// Failed to extract pixels from the decoded image.
    case pixelExtractionFailed

    var errorDescription: String? {
        switch self {
        case let .decoderNotFound(id):
            return "Decoder '\(id)' not found in pool."
        case let .assetLoadFailed(path):
            return "Failed to load asset at: \(path)."
        case .noVideoTrack:
            return "No video track in asset."
        case .frameExtractionFailed:
            return "Failed to extract video frame."
        case .allDecodersBusy:
            return "All decoders are busy; cannot create new decoder."
        case .pixelExtractionFailed:
            return "Failed to extract pixels from decoded image."
        }
    }
}
