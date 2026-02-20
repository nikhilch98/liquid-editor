// ExportServiceProtocol.swift
// LiquidEditor
//
// Protocol for video export operations.
// Enables dependency injection and testability.

import Foundation

// MARK: - ExportServiceProtocol

/// Protocol for video export operations.
///
/// Implementations handle the full export pipeline: composition building,
/// effect rendering, encoding, and output file writing. Progress is
/// reported via AsyncStream.
///
/// References:
/// - `ExportConfig` from Models/Export/ExportConfig.swift
/// - `ExportProgress` from Models/Export/ExportJob.swift
/// - `ExportPhase` from Models/Export/ExportConfig.swift
protocol ExportServiceProtocol: Sendable {
    /// Start an export with the given configuration.
    ///
    /// The export runs asynchronously. Progress is available via
    /// `progressStream(exportId:)`.
    ///
    /// - Parameter config: Export configuration (resolution, codec, format, etc.).
    /// - Returns: Handle for tracking the export.
    /// - Throws: If the export cannot be started (e.g., insufficient disk space).
    func startExport(config: ExportConfig) async throws -> ExportHandle

    /// Cancel an active export.
    ///
    /// The export transitions to the `.cancelled` phase. Partial output
    /// files are cleaned up.
    ///
    /// - Parameter exportId: Identifier of the export to cancel.
    /// - Throws: If the export does not exist or is already complete.
    func cancelExport(exportId: String) async throws

    /// Progress stream for an active export.
    ///
    /// Emits `ExportProgress` updates as the export proceeds through
    /// its phases (preparing, rendering, encoding, finalizing).
    ///
    /// - Parameter exportId: Identifier of the export.
    /// - Returns: AsyncStream of progress updates.
    func progressStream(exportId: String) -> AsyncStream<ExportProgress>

    /// Check available disk space on the device.
    ///
    /// - Returns: Available disk space in bytes.
    func availableDiskSpace() async -> Int64
}

// MARK: - ExportHandle

/// Handle for tracking an active export operation.
struct ExportHandle: Sendable, Identifiable {
    /// Unique identifier for this export.
    let id: String

    /// Output file URL where the export will be written.
    let outputURL: URL

    /// Estimated total duration of the content being exported.
    let estimatedDuration: TimeMicros
}
