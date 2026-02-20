// FileSizeEstimator.swift
// LiquidEditor
//
// File size estimation for export operations.

import Foundation

// MARK: - FileSizeEstimator

/// Estimates file sizes for video and audio exports.
enum FileSizeEstimator {

    /// Estimate output file size in bytes for a video export.
    ///
    /// Uses the formula: size = (video_bitrate + audio_bitrate) * duration / 8
    /// with a 10% overhead multiplier for container metadata and encoding overhead.
    static func estimateVideoSizeBytes(
        config: ExportConfig,
        duration: TimeInterval
    ) -> Int {
        guard duration > 0 else { return 0 }

        // Video bitrate in bits per second
        let videoBitsPerSecond = config.effectiveBitrateMbps * 1_000_000.0

        // Audio bitrate in bits per second
        let audioBitsPerSecond = Double(config.audioBitrate) * 1_000.0

        // Total bits
        let totalBits = (videoBitsPerSecond + audioBitsPerSecond) * duration

        // Convert to bytes with 10% overhead
        return Int((totalBits / 8.0 * 1.1).rounded())
    }

    /// Estimate output file size in bytes for an audio-only export.
    static func estimateAudioSizeBytes(
        codec: ExportAudioCodec,
        bitrate: Int,
        duration: TimeInterval
    ) -> Int {
        guard duration > 0 else { return 0 }

        // For lossless formats, estimate based on sample rate and bit depth
        if codec == .wav {
            // PCM: sample_rate * bit_depth * channels / 8
            // Assume 48kHz, 16-bit, stereo
            return Int((48000.0 * 16.0 * 2.0 / 8.0 * duration * 1.01).rounded())
        }

        if codec == .alac || codec == .flac {
            // Lossless compression typically ~50-70% of PCM
            let pcmSize = 48000.0 * 16.0 * 2.0 / 8.0 * duration
            return Int((pcmSize * 0.6).rounded())
        }

        // AAC: bitrate * duration / 8
        let bits = Double(bitrate) * 1000.0 * duration
        return Int((bits / 8.0 * 1.05).rounded())
    }

    /// Format bytes into a human-readable string.
    static func formatBytes(_ bytes: Int) -> String {
        if bytes <= 0 { return "0 B" }

        let kb = 1024
        let mb = kb * 1024
        let gb = mb * 1024

        if bytes >= gb {
            return String(format: "%.1f GB", Double(bytes) / Double(gb))
        } else if bytes >= mb {
            return String(format: "%.1f MB", Double(bytes) / Double(mb))
        } else if bytes >= kb {
            return String(format: "%.1f KB", Double(bytes) / Double(kb))
        }
        return "\(bytes) B"
    }

    /// Check if estimated file size exceeds available storage.
    ///
    /// Returns a warning message if storage is insufficient, nil otherwise.
    /// `availableDiskBytes` is the available disk space in bytes.
    static func checkStorageWarning(
        estimatedSizeBytes: Int,
        availableDiskBytes: Int
    ) -> String? {
        // 500 MB safety margin
        let safetyMarginBytes = 500 * 1024 * 1024
        let requiredBytes = estimatedSizeBytes + safetyMarginBytes

        if availableDiskBytes < requiredBytes {
            let available = formatBytes(availableDiskBytes)
            let required = formatBytes(requiredBytes)
            return "Insufficient storage. Available: \(available), " +
                   "Required: \(required) (including 500 MB safety margin)."
        }

        return nil
    }

    /// Check if estimated file size exceeds a social platform limit.
    static func checkPlatformSizeWarning(
        estimatedSizeBytes: Int,
        preset: SocialMediaPreset
    ) -> String? {
        let maxBytes = preset.maxFileSizeMB * 1024 * 1024
        if estimatedSizeBytes > maxBytes {
            let estimated = formatBytes(estimatedSizeBytes)
            let max = formatBytes(maxBytes)
            return "Estimated file size (\(estimated)) exceeds " +
                   "\(preset.displayName) limit (\(max)). " +
                   "Consider reducing quality or bitrate."
        }
        return nil
    }

    /// Check if duration exceeds a social platform limit.
    static func checkDurationWarning(
        duration: TimeInterval,
        preset: SocialMediaPreset
    ) -> String? {
        let durationSeconds = Int(duration)
        if durationSeconds > preset.maxDurationSeconds {
            let maxMinutes = preset.maxDurationSeconds / 60
            let maxSeconds = preset.maxDurationSeconds % 60
            let maxStr = maxSeconds > 0 ? "\(maxMinutes)m \(maxSeconds)s" : "\(maxMinutes)m"
            return "Video duration exceeds \(preset.displayName) limit of \(maxStr). " +
                   "Trim your video before exporting."
        }
        return nil
    }
}
