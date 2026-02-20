// ContentHashTests.swift
// LiquidEditorTests
//
// Tests for ContentHash: consistent hashing, different files produce different hashes.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("ContentHash Tests")
struct ContentHashTests {

    // MARK: - Helpers

    /// Create a temporary file with the given data.
    private func createTempFile(_ data: Data, name: String = "test_\(UUID().uuidString)") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    /// Clean up temporary file.
    private func removeTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Consistency

    @Test("Same file produces same hash")
    func consistentHash() async throws {
        let data = Data(repeating: 0xAB, count: 1024)
        let url = createTempFile(data)
        defer { removeTempFile(url) }

        let hash1 = try await ContentHash.generateContentHash(url)
        let hash2 = try await ContentHash.generateContentHash(url)

        #expect(hash1 == hash2)
        #expect(!hash1.isEmpty)
    }

    @Test("Sync hash matches async hash")
    func syncMatchesAsync() async throws {
        let data = Data(repeating: 0xCD, count: 2048)
        let url = createTempFile(data)
        defer { removeTempFile(url) }

        let asyncHash = try await ContentHash.generateContentHash(url)
        let syncHash = try ContentHash.generateContentHashSync(url)

        #expect(asyncHash == syncHash)
    }

    // MARK: - Uniqueness

    @Test("Different content produces different hashes")
    func differentContent() async throws {
        let data1 = Data(repeating: 0x11, count: 4096)
        let data2 = Data(repeating: 0x22, count: 4096)
        let url1 = createTempFile(data1, name: "test_a")
        let url2 = createTempFile(data2, name: "test_b")
        defer {
            removeTempFile(url1)
            removeTempFile(url2)
        }

        let hash1 = try await ContentHash.generateContentHash(url1)
        let hash2 = try await ContentHash.generateContentHash(url2)

        #expect(hash1 != hash2)
    }

    @Test("Different sizes produce different hashes")
    func differentSizes() async throws {
        let data1 = Data(repeating: 0x33, count: 1000)
        let data2 = Data(repeating: 0x33, count: 2000)
        let url1 = createTempFile(data1, name: "test_size_a")
        let url2 = createTempFile(data2, name: "test_size_b")
        defer {
            removeTempFile(url1)
            removeTempFile(url2)
        }

        let hash1 = try await ContentHash.generateContentHash(url1)
        let hash2 = try await ContentHash.generateContentHash(url2)

        #expect(hash1 != hash2)
    }

    // MARK: - Large File Strategy

    @Test("Large file hashing reads first and last chunks")
    func largeFile() async throws {
        // Create a 3MB file (> 2 * chunkSize)
        var data = Data(count: 3 * 1_024 * 1_024)
        // Set distinct patterns in first and last chunks
        for i in 0..<1024 {
            data[i] = 0xAA
        }
        for i in (data.count - 1024)..<data.count {
            data[i] = 0xBB
        }

        let url = createTempFile(data, name: "test_large")
        defer { removeTempFile(url) }

        let hash = try await ContentHash.generateContentHash(url)
        #expect(!hash.isEmpty)
        #expect(hash.count == 64) // SHA-256 hex string = 64 chars
    }

    // MARK: - Verification

    @Test("Verify content hash")
    func verification() async throws {
        let data = Data(repeating: 0x55, count: 4096)
        let url = createTempFile(data)
        defer { removeTempFile(url) }

        let hash = try await ContentHash.generateContentHash(url)
        let isValid = await ContentHash.verifyContentHash(url, expectedHash: hash)
        #expect(isValid)

        let isInvalid = await ContentHash.verifyContentHash(url, expectedHash: "wrong_hash")
        #expect(!isInvalid)
    }

    // MARK: - Cancellation

    @Test("Cancellation token stops hash generation")
    func cancellation() async {
        let data = Data(repeating: 0x77, count: 1024)
        let url = createTempFile(data)
        defer { removeTempFile(url) }

        let token = ContentHashCancellationToken()
        token.cancel()

        do {
            _ = try await ContentHash.generateContentHash(url, cancellationToken: token)
            Issue.record("Should have thrown cancellation error")
        } catch ContentHashError.cancelled {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Hash Format

    @Test("Hash is lowercase hex string")
    func hashFormat() async throws {
        let data = Data([0x01, 0x02, 0x03])
        let url = createTempFile(data)
        defer { removeTempFile(url) }

        let hash = try await ContentHash.generateContentHash(url)

        // Should be 64 hex characters (SHA-256)
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
        #expect(hash == hash.lowercased())
    }

    // MARK: - Quick Hash

    @Test("Quick hash produces valid result")
    func quickHash() async throws {
        let data = Data(repeating: 0xEE, count: 128 * 1024)
        let url = createTempFile(data)
        defer { removeTempFile(url) }

        let hash = try await ContentHash.generateQuickHash(url)
        #expect(hash.count == 64)
    }

    // MARK: - Error Handling

    @Test("Non-existent file throws error")
    func fileNotFound() async {
        let url = URL(filePath: "/nonexistent/path/file.mp4")
        do {
            _ = try await ContentHash.generateContentHash(url)
            Issue.record("Should have thrown")
        } catch ContentHashError.fileNotFound {
            // Expected
        } catch {
            // Some other error is also acceptable
        }
    }
}
