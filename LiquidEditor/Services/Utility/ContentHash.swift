// ContentHash.swift
// LiquidEditor
//
// SHA-256 content hashing for media file duplicate detection and relinking.
// Uses CryptoKit for native SHA-256 (no third-party dependencies).
//
// Strategy: SHA-256 of (file size bytes + first 1MB + last 1MB).
// Fast even for large files while being highly unique.

import CryptoKit
import Foundation

// MARK: - ContentHashError

/// Errors that can occur during content hash generation.
enum ContentHashError: Error, Sendable {
    case cancelled
    case fileNotFound(String)
    case readFailed(String)
}

// MARK: - ContentHashCancellationToken

/// Cancellation token for long-running hash operations.
final class ContentHashCancellationToken: @unchecked Sendable {
    private var _cancelled = false
    private let lock = NSLock()

    /// Whether cancellation has been requested.
    var isCancelled: Bool {
        lock.withLock { _cancelled }
    }

    /// Request cancellation.
    func cancel() {
        lock.withLock { _cancelled = true }
    }

    /// Throw if cancelled.
    func throwIfCancelled() throws {
        if isCancelled { throw ContentHashError.cancelled }
    }
}

// MARK: - ContentHash

/// SHA-256 content hashing utilities for media files.
///
/// Uses an `actor` to ensure file I/O happens off the main thread.
/// All methods are async and safe to call from any context.
actor ContentHash {


    // MARK: - Constants

    /// Size of each chunk to read for fast hashing (1 MB).
    private static let fastHashChunkSize = 1_024 * 1_024

    /// Buffer size for full file hashing (64 KB).
    private static let fullHashBufferSize = 64 * 1024

    /// Buffer size for quick hash (64 KB).
    private static let quickHashBufferSize = 64 * 1024

    // MARK: - Fast Hash (first 1MB + last 1MB + file size)

    /// Generate content hash for a media file.
    ///
    /// The hash is based on:
    /// - File size (8 bytes, big-endian)
    /// - First 1MB of content
    /// - Last 1MB of content (if file > 2MB)
    ///
    /// - Parameters:
    ///   - url: File URL to hash.
    ///   - cancellationToken: Optional token to cancel the operation.
    /// - Returns: SHA-256 hash as a lowercase hex string.
    static func generateContentHash(
        _ url: URL,
        cancellationToken: ContentHashCancellationToken? = nil
    ) async throws -> String {
        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ContentHashError.fileNotFound(url.path)
        }

        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        try cancellationToken?.throwIfCancelled()

        var hasher = SHA256()

        // Add file size as part of hash (8 bytes, big-endian)
        var sizeValue = UInt64(fileSize).bigEndian
        let sizeData = Data(bytes: &sizeValue, count: 8)
        hasher.update(data: sizeData)

        try cancellationToken?.throwIfCancelled()

        // Read first 1MB
        let firstChunkSize = min(Int(fileSize), Self.fastHashChunkSize)
        guard let firstChunk = try fileHandle.read(upToCount: firstChunkSize) else {
            throw ContentHashError.readFailed("Failed to read first chunk")
        }
        hasher.update(data: firstChunk)

        try cancellationToken?.throwIfCancelled()

        // Read last 1MB (if file is larger than 2MB)
        if fileSize > UInt64(Self.fastHashChunkSize * 2) {
            try fileHandle.seek(toOffset: fileSize - UInt64(Self.fastHashChunkSize))
            if let lastChunk = try fileHandle.read(upToCount: Self.fastHashChunkSize) {
                hasher.update(data: lastChunk)
            }
        } else if fileSize > UInt64(Self.fastHashChunkSize) {
            // File is between 1-2MB, read the rest
            let remaining = Int(fileSize) - Self.fastHashChunkSize
            if let rest = try fileHandle.read(upToCount: remaining) {
                hasher.update(data: rest)
            }
        }

        try cancellationToken?.throwIfCancelled()

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Synchronous Hash

    /// Generate content hash synchronously (for smaller files).
    ///
    /// - Warning: **This method blocks the calling thread.** It performs synchronous file I/O,
    /// which can cause UI freezes if called on the main thread with large files. For files larger
    /// than a few MB, prefer the async `generateContentHash(_:cancellationToken:)` method.
    static func generateContentHashSync(_ url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        var hasher = SHA256()

        // Add file size
        var sizeValue = UInt64(fileSize).bigEndian
        let sizeData = Data(bytes: &sizeValue, count: 8)
        hasher.update(data: sizeData)

        // Read first 1MB
        let firstChunkSize = min(Int(fileSize), Self.fastHashChunkSize)
        guard let firstChunk = try fileHandle.read(upToCount: firstChunkSize) else {
            throw ContentHashError.readFailed("Failed to read first chunk")
        }
        hasher.update(data: firstChunk)

        // Read last 1MB (if file is larger than 2MB)
        if fileSize > UInt64(Self.fastHashChunkSize * 2) {
            try fileHandle.seek(toOffset: fileSize - UInt64(Self.fastHashChunkSize))
            if let lastChunk = try fileHandle.read(upToCount: Self.fastHashChunkSize) {
                hasher.update(data: lastChunk)
            }
        } else if fileSize > UInt64(Self.fastHashChunkSize) {
            let remaining = Int(fileSize) - Self.fastHashChunkSize
            if let rest = try fileHandle.read(upToCount: remaining) {
                hasher.update(data: rest)
            }
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Verification

    /// Verify that a file matches a known content hash.
    ///
    /// - Parameters:
    ///   - url: File URL to verify.
    ///   - expectedHash: The expected SHA-256 hex string.
    ///   - cancellationToken: Optional cancellation token.
    /// - Returns: `true` if the file's hash matches.
    static func verifyContentHash(
        _ url: URL,
        expectedHash: String,
        cancellationToken: ContentHashCancellationToken? = nil
    ) async -> Bool {
        do {
            let actual = try await generateContentHash(url, cancellationToken: cancellationToken)
            return actual == expectedHash
        } catch {
            return false
        }
    }

    // MARK: - Full Hash

    /// Generate a full content hash (entire file).
    ///
    /// Slower but more thorough. Use for integrity verification.
    ///
    /// - Parameters:
    ///   - url: File URL to hash.
    ///   - cancellationToken: Optional cancellation token.
    ///   - onProgress: Optional callback with (bytesRead, totalBytes).
    /// - Returns: SHA-256 hash as a lowercase hex string.
    static func generateFullContentHash(
        _ url: URL,
        cancellationToken: ContentHashCancellationToken? = nil,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        var hasher = SHA256()
        var bytesRead = 0
        let bufferSize = Self.fullHashBufferSize

        while bytesRead < Int(fileSize) {
            try cancellationToken?.throwIfCancelled()

            guard let chunk = try fileHandle.read(upToCount: bufferSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            bytesRead += chunk.count
            onProgress?(bytesRead, Int(fileSize))
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Quick Hash

    /// Quick hash for thumbnail/preview cache keys (first 64KB only).
    ///
    /// Not suitable for duplicate detection, but good for cache keys.
    static func generateQuickHash(_ url: URL) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        guard let chunk = try fileHandle.read(upToCount: Self.quickHashBufferSize) else {
            throw ContentHashError.readFailed("Failed to read file")
        }

        let digest = SHA256.hash(data: chunk)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
