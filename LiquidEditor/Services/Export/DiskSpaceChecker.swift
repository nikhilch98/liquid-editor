// DiskSpaceChecker.swift
// LiquidEditor
//
// Pre-export disk space check (F6-24).
//
// Estimates the output size of an export given its preset / duration and
// compares it against the volume's available capacity. Used to gate the
// export flow before the user initiates a long-running render.

import Foundation

// MARK: - DiskSpaceCheck

/// Outcome of a disk-space check.
enum DiskSpaceCheck: Equatable, Sendable {
    /// Enough free space with comfortable head-room.
    case sufficient
    /// Free space remains but falls below the safety margin.
    case lowWarning(remaining: Int64)
    /// Not enough free space to perform the export.
    case insufficient(needed: Int64, available: Int64)
}

// MARK: - DiskSpaceChecker

/// Helper that computes estimated export size and reports available disk
/// space on the user-documents volume.
///
/// Thread Safety: `@MainActor` to match the export UI lifecycle; the
/// underlying `FileManager` APIs are themselves thread-safe but the
/// checker is cheap enough to run on the main actor.
@MainActor
enum DiskSpaceChecker {

    // MARK: - Constants

    /// Safety head-room (bytes) retained beyond the estimated size. If the
    /// free space after subtracting the estimate is below this, we flag a
    /// `.lowWarning`.
    static let safetyMarginBytes: Int64 = 500_000_000 // 500 MB

    // MARK: - Public API

    /// Returns the available capacity of the user-documents volume, in
    /// bytes. Returns `0` if the attribute cannot be read.
    static func availableSpace() -> Int64 {
        let url = documentsURL()
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let important = values.volumeAvailableCapacityForImportantUsage {
                return Int64(important)
            }
        } catch {
            // Fall through to attribute-based fallback.
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return 0
    }

    /// Estimate the output file size in bytes for `preset` over `duration`.
    ///
    /// Uses the preset's configured video bitrate (in Mbps) plus its audio
    /// bitrate (kbps) to compute a byte count:
    ///   bytes = (videoMbps * 1_000_000 + audioKbps * 1_000) * duration / 8
    static func estimatedSize(preset: ExportPreset, duration: TimeInterval) -> Int64 {
        guard duration > 0 else { return 0 }
        let videoBps = preset.config.bitrateMbps * 1_000_000.0
        let audioBps = Double(preset.config.audioBitrate) * 1_000.0
        let totalBits = (videoBps + audioBps) * duration
        let bytes = totalBits / 8.0
        return Int64(bytes.rounded(.up))
    }

    /// Combine the estimate and available space into a `DiskSpaceCheck`.
    static func canExport(preset: ExportPreset, duration: TimeInterval) -> DiskSpaceCheck {
        let needed = estimatedSize(preset: preset, duration: duration)
        let available = availableSpace()
        if available < needed {
            return .insufficient(needed: needed, available: available)
        }
        let remaining = available - needed
        if remaining < safetyMarginBytes {
            return .lowWarning(remaining: remaining)
        }
        return .sufficient
    }

    // MARK: - Private

    private static func documentsURL() -> URL {
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return docs
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
}
