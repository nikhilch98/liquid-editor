// RepositoryError.swift
// LiquidEditor
//
// Errors thrown by repository layer operations.
// Provides domain-specific error cases for persistence failures,
// data corruption, and I/O issues.

import Foundation

// MARK: - RepositoryError

/// Errors thrown by repository operations.
///
/// Each case carries contextual information (e.g., the resource ID,
/// file path, or mismatch details) to aid debugging and user-facing
/// error messages.
enum RepositoryError: Error, Sendable, LocalizedError {

    /// The requested resource was not found.
    case notFound(String)

    /// Stored data is corrupted or unreadable.
    case corruptedData(String)

    /// A file system or disk I/O error occurred.
    case ioError(String)

    /// A domain validation check failed.
    case validationFailed(String)

    /// The stored version does not match the expected version.
    case versionMismatch(expected: Int, actual: Int)

    /// The computed checksum does not match the stored checksum.
    case checksumMismatch(expected: String, actual: String)

    /// File access was denied (e.g., sandbox restriction).
    case fileAccessDenied(String)

    /// The device does not have enough free storage.
    case insufficientStorage

    /// The provided file path is invalid or malformed.
    case invalidPath(String)

    /// Encoding the data for storage failed.
    case encodingFailed(String)

    /// Decoding stored data back into a model failed.
    case decodingFailed(String)

    /// A resource with the same identifier already exists.
    case duplicateEntry(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Resource not found: \(id)"
        case .corruptedData(let detail):
            return "Data corrupted: \(detail)"
        case .ioError(let detail):
            return "I/O error: \(detail)"
        case .validationFailed(let detail):
            return "Validation failed: \(detail)"
        case .versionMismatch(let expected, let actual):
            return "Version mismatch: expected \(expected), got \(actual)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected \(expected), got \(actual)"
        case .fileAccessDenied(let path):
            return "Access denied: \(path)"
        case .insufficientStorage:
            return "Insufficient storage space"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .encodingFailed(let detail):
            return "Encoding failed: \(detail)"
        case .decodingFailed(let detail):
            return "Decoding failed: \(detail)"
        case .duplicateEntry(let id):
            return "Duplicate entry: \(id)"
        }
    }
}
