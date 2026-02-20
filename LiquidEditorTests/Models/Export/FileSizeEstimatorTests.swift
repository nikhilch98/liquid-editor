import Testing
import Foundation
@testable import LiquidEditor

// MARK: - FileSizeEstimator Comprehensive Tests

@Suite("FileSizeEstimator Comprehensive Tests")
struct FileSizeEstimatorComprehensiveTests {

    // MARK: - estimateVideoSizeBytes

    @Test("Zero duration returns 0 bytes")
    func zeroDuration() {
        let config = ExportConfig()
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 0.0)
        #expect(size == 0)
    }

    @Test("Negative duration returns 0 bytes")
    func negativeDuration() {
        let config = ExportConfig()
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: -5.0)
        #expect(size == 0)
    }

    @Test("Default config 1080p H.264 10s estimate is positive")
    func default1080p10s() {
        let config = ExportConfig() // 1080p, H.264, 20Mbps, high quality
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 10.0)
        #expect(size > 0)
    }

    @Test("Longer duration produces proportionally larger file")
    func durationScaling() {
        let config = ExportConfig()
        let size10s = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 10.0)
        let size20s = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 20.0)
        // 20s should be exactly double 10s (linear scaling)
        #expect(size20s == 2 * size10s)
    }

    @Test("Higher bitrate produces larger file")
    func higherBitrate() {
        let lowBitrate = ExportConfig(bitrateMbps: 10.0)
        let highBitrate = ExportConfig(bitrateMbps: 40.0)
        let sizeLow = FileSizeEstimator.estimateVideoSizeBytes(config: lowBitrate, duration: 60.0)
        let sizeHigh = FileSizeEstimator.estimateVideoSizeBytes(config: highBitrate, duration: 60.0)
        #expect(sizeHigh > sizeLow)
    }

    @Test("Quality multiplier affects file size")
    func qualityMultiplier() {
        let draft = ExportConfig(quality: .draft) // 0.3x multiplier
        let maximum = ExportConfig(quality: .maximum) // 1.5x multiplier
        let sizeDraft = FileSizeEstimator.estimateVideoSizeBytes(config: draft, duration: 60.0)
        let sizeMax = FileSizeEstimator.estimateVideoSizeBytes(config: maximum, duration: 60.0)
        #expect(sizeMax > sizeDraft)
    }

    @Test("Higher audio bitrate produces slightly larger file")
    func audioBitrateEffect() {
        let lowAudio = ExportConfig(audioBitrate: 128)
        let highAudio = ExportConfig(audioBitrate: 320)
        let sizeLow = FileSizeEstimator.estimateVideoSizeBytes(config: lowAudio, duration: 60.0)
        let sizeHigh = FileSizeEstimator.estimateVideoSizeBytes(config: highAudio, duration: 60.0)
        #expect(sizeHigh > sizeLow)
    }

    @Test("Default 1080p 60s estimate is approximately correct")
    func approximateAccuracy() {
        // Default: 20Mbps * 1.0 (high quality) = 20Mbps video + 256kbps audio
        // 60s: (20_000_000 + 256_000) * 60 / 8 * 1.1 = ~167MB
        let config = ExportConfig()
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 60.0)
        let expectedBytes = Int(((20_000_000.0 + 256_000.0) * 60.0 / 8.0 * 1.1).rounded())
        #expect(size == expectedBytes)
    }

    @Test("4K video at high bitrate produces large file")
    func fourK() {
        let config = ExportConfig(resolution: .r4K, quality: .high, bitrateMbps: 60.0)
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 120.0) // 2 min
        // effectiveBitrate = 60 * 1.0 = 60 Mbps, 2 min video -> ~994 MB
        #expect(size > 900_000_000)
    }

    @Test("720p at low bitrate produces small file")
    func sevenTwentyP() {
        let config = ExportConfig(resolution: .r720p, quality: .draft, bitrateMbps: 5.0)
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 30.0)
        // 5 * 0.3 = 1.5Mbps, 30s -> ~7MB
        #expect(size > 0)
        #expect(size < 50_000_000) // Should be well under 50MB
    }

    @Test("effectiveBitrateMbps reflects quality multiplier")
    func effectiveBitrate() {
        let draftConfig = ExportConfig(resolution: .r1080p, quality: .draft, bitrateMbps: 20.0)
        #expect(draftConfig.effectiveBitrateMbps == 6.0) // 20 * 0.3

        let standardConfig = ExportConfig(resolution: .r1080p, quality: .standard, bitrateMbps: 20.0)
        #expect(standardConfig.effectiveBitrateMbps == 12.0) // 20 * 0.6

        let highConfig = ExportConfig(resolution: .r1080p, quality: .high, bitrateMbps: 20.0)
        #expect(highConfig.effectiveBitrateMbps == 20.0) // 20 * 1.0

        let maxConfig = ExportConfig(resolution: .r1080p, quality: .maximum, bitrateMbps: 20.0)
        #expect(maxConfig.effectiveBitrateMbps == 30.0) // 20 * 1.5
    }

    @Test("Very short video (0.1s) produces non-zero result")
    func veryShortVideo() {
        let config = ExportConfig()
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 0.1)
        #expect(size > 0)
    }

    @Test("Very long video (1 hour) produces large result")
    func veryLongVideo() {
        let config = ExportConfig()
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 3600.0)
        // 1 hour at 20Mbps = ~10GB
        #expect(size > 5_000_000_000)
    }

    // MARK: - estimateAudioSizeBytes

    @Test("AAC audio estimate for 60s")
    func aacEstimate() {
        let size = FileSizeEstimator.estimateAudioSizeBytes(
            codec: .aac,
            bitrate: 256,
            duration: 60.0
        )
        #expect(size > 0)
        let expected = Int((256.0 * 1000.0 * 60.0 / 8.0 * 1.05).rounded())
        #expect(size == expected)
    }

    @Test("AAC zero duration returns 0")
    func aacZeroDuration() {
        let size = FileSizeEstimator.estimateAudioSizeBytes(
            codec: .aac,
            bitrate: 256,
            duration: 0.0
        )
        #expect(size == 0)
    }

    @Test("WAV estimate is larger than AAC for same duration")
    func wavLargerThanAac() {
        let aacSize = FileSizeEstimator.estimateAudioSizeBytes(
            codec: .aac,
            bitrate: 256,
            duration: 60.0
        )
        let wavSize = FileSizeEstimator.estimateAudioSizeBytes(
            codec: .wav,
            bitrate: 256, // bitrate ignored for WAV
            duration: 60.0
        )
        #expect(wavSize > aacSize)
    }

    @Test("WAV PCM estimate is approximately correct")
    func wavEstimate() {
        let duration = 10.0
        let expected = Int((48000.0 * 16.0 * 2.0 / 8.0 * duration * 1.01).rounded())
        let size = FileSizeEstimator.estimateAudioSizeBytes(
            codec: .wav,
            bitrate: 256,
            duration: duration
        )
        #expect(size == expected)
    }

    @Test("ALAC estimate is approximately 60% of PCM")
    func alacEstimate() {
        let duration = 10.0
        let pcmSize = 48000.0 * 16.0 * 2.0 / 8.0 * duration
        let expected = Int((pcmSize * 0.6).rounded())
        let size = FileSizeEstimator.estimateAudioSizeBytes(
            codec: .alac,
            bitrate: 256,
            duration: duration
        )
        #expect(size == expected)
    }

    @Test("FLAC estimate equals ALAC estimate")
    func flacEstimate() {
        let duration = 10.0
        let alacSize = FileSizeEstimator.estimateAudioSizeBytes(codec: .alac, bitrate: 256, duration: duration)
        let flacSize = FileSizeEstimator.estimateAudioSizeBytes(codec: .flac, bitrate: 256, duration: duration)
        #expect(flacSize == alacSize)
    }

    @Test("Audio negative duration returns 0")
    func audioNegativeDuration() {
        let size = FileSizeEstimator.estimateAudioSizeBytes(
            codec: .aac,
            bitrate: 256,
            duration: -1.0
        )
        #expect(size == 0)
    }

    @Test("Higher AAC bitrate produces larger file")
    func aacBitrateScaling() {
        let low = FileSizeEstimator.estimateAudioSizeBytes(codec: .aac, bitrate: 128, duration: 60.0)
        let high = FileSizeEstimator.estimateAudioSizeBytes(codec: .aac, bitrate: 320, duration: 60.0)
        #expect(high > low)
    }

    @Test("WAV ignores bitrate parameter")
    func wavIgnoresBitrate() {
        let low = FileSizeEstimator.estimateAudioSizeBytes(codec: .wav, bitrate: 128, duration: 10.0)
        let high = FileSizeEstimator.estimateAudioSizeBytes(codec: .wav, bitrate: 320, duration: 10.0)
        #expect(low == high)
    }

    // MARK: - formatBytes

    @Test("formatBytes for 0 returns '0 B'")
    func formatZero() {
        #expect(FileSizeEstimator.formatBytes(0) == "0 B")
    }

    @Test("formatBytes for negative returns '0 B'")
    func formatNegative() {
        #expect(FileSizeEstimator.formatBytes(-100) == "0 B")
    }

    @Test("formatBytes for bytes range")
    func formatBytesRange() {
        #expect(FileSizeEstimator.formatBytes(500) == "500 B")
        #expect(FileSizeEstimator.formatBytes(1) == "1 B")
        #expect(FileSizeEstimator.formatBytes(1023) == "1023 B")
    }

    @Test("formatBytes for KB range")
    func formatKB() {
        let result = FileSizeEstimator.formatBytes(1024)
        #expect(result == "1.0 KB")
    }

    @Test("formatBytes for MB range")
    func formatMB() {
        let result = FileSizeEstimator.formatBytes(1024 * 1024)
        #expect(result == "1.0 MB")

        let result50 = FileSizeEstimator.formatBytes(50 * 1024 * 1024)
        #expect(result50 == "50.0 MB")
    }

    @Test("formatBytes for GB range")
    func formatGB() {
        let result = FileSizeEstimator.formatBytes(1024 * 1024 * 1024)
        #expect(result == "1.0 GB")

        let result2_5 = FileSizeEstimator.formatBytes(Int(2.5 * 1024 * 1024 * 1024))
        #expect(result2_5 == "2.5 GB")
    }

    @Test("formatBytes for specific values")
    func formatSpecific() {
        #expect(FileSizeEstimator.formatBytes(512 * 1024) == "512.0 KB")
        #expect(FileSizeEstimator.formatBytes(100 * 1024 * 1024) == "100.0 MB")
    }

    // MARK: - checkStorageWarning

    @Test("No warning when sufficient storage")
    func sufficientStorage() {
        let warning = FileSizeEstimator.checkStorageWarning(
            estimatedSizeBytes: 100 * 1024 * 1024, // 100MB
            availableDiskBytes: 10 * 1024 * 1024 * 1024 // 10GB
        )
        #expect(warning == nil)
    }

    @Test("Warning when insufficient storage")
    func insufficientStorage() {
        let warning = FileSizeEstimator.checkStorageWarning(
            estimatedSizeBytes: 9 * 1024 * 1024 * 1024, // 9GB
            availableDiskBytes: 9 * 1024 * 1024 * 1024 // 9GB (not enough with 500MB margin)
        )
        #expect(warning != nil)
        #expect(warning!.contains("Insufficient storage"))
    }

    @Test("Warning includes 500MB safety margin")
    func safetyMargin() {
        let warning = FileSizeEstimator.checkStorageWarning(
            estimatedSizeBytes: 100 * 1024 * 1024, // 100MB
            availableDiskBytes: 599 * 1024 * 1024 // 599MB < 600MB required
        )
        #expect(warning != nil)
        #expect(warning!.contains("500 MB safety margin"))
    }

    @Test("No warning when exactly at safety margin")
    func exactSafetyMargin() {
        let warning = FileSizeEstimator.checkStorageWarning(
            estimatedSizeBytes: 100 * 1024 * 1024, // 100MB
            availableDiskBytes: 600 * 1024 * 1024 // 600MB == 600MB required
        )
        #expect(warning == nil)
    }

    // MARK: - checkPlatformSizeWarning

    @Test("No warning when within Instagram limit")
    func instagramWithinLimit() {
        let warning = FileSizeEstimator.checkPlatformSizeWarning(
            estimatedSizeBytes: 100 * 1024 * 1024, // 100MB
            preset: .instagram // 250MB limit
        )
        #expect(warning == nil)
    }

    @Test("Warning when exceeding Instagram limit")
    func instagramExceedsLimit() {
        let warning = FileSizeEstimator.checkPlatformSizeWarning(
            estimatedSizeBytes: 300 * 1024 * 1024, // 300MB
            preset: .instagram // 250MB limit
        )
        #expect(warning != nil)
        #expect(warning!.contains("Instagram Reels"))
    }

    @Test("Warning when exceeding Twitter limit")
    func twitterExceedsLimit() {
        let warning = FileSizeEstimator.checkPlatformSizeWarning(
            estimatedSizeBytes: 600 * 1024 * 1024, // 600MB
            preset: .twitter // 512MB limit
        )
        #expect(warning != nil)
        #expect(warning!.contains("X (Twitter)"))
    }

    @Test("No warning for YouTube with large file")
    func youtubeNoWarning() {
        let warning = FileSizeEstimator.checkPlatformSizeWarning(
            estimatedSizeBytes: 10 * 1024 * 1024 * 1024, // 10GB
            preset: .youtube // 128GB limit
        )
        #expect(warning == nil)
    }

    @Test("Platform warning includes suggestion to reduce quality")
    func platformWarningSuggestion() {
        let warning = FileSizeEstimator.checkPlatformSizeWarning(
            estimatedSizeBytes: 300 * 1024 * 1024,
            preset: .instagram
        )
        #expect(warning!.contains("reducing quality or bitrate"))
    }

    // MARK: - checkDurationWarning

    @Test("No duration warning when within limit")
    func durationWithinLimit() {
        let warning = FileSizeEstimator.checkDurationWarning(
            duration: 60.0, // 1 minute
            preset: .instagram // 15 minute limit
        )
        #expect(warning == nil)
    }

    @Test("Duration warning when exceeding Twitter limit")
    func durationExceedsTwitter() {
        let warning = FileSizeEstimator.checkDurationWarning(
            duration: 180.0, // 3 minutes
            preset: .twitter // 140 second limit
        )
        #expect(warning != nil)
        #expect(warning!.contains("X (Twitter)"))
    }

    @Test("Duration warning when exceeding TikTok limit")
    func durationExceedsTikTok() {
        let warning = FileSizeEstimator.checkDurationWarning(
            duration: 700.0, // 11m 40s
            preset: .tiktok // 600s = 10 minute limit
        )
        #expect(warning != nil)
        #expect(warning!.contains("TikTok"))
    }

    @Test("Duration warning includes trim suggestion")
    func durationWarningSuggestion() {
        let warning = FileSizeEstimator.checkDurationWarning(
            duration: 200.0,
            preset: .twitter
        )
        #expect(warning!.contains("Trim your video"))
    }

    @Test("No duration warning at exact limit")
    func durationAtExactLimit() {
        let warning = FileSizeEstimator.checkDurationWarning(
            duration: 140.0, // exactly 140s
            preset: .twitter // 140s limit
        )
        #expect(warning == nil)
    }

    // MARK: - Integration: Social Media Preset to EstimateSize

    @Test("Instagram preset export estimate is within limit")
    func instagramPresetEstimate() {
        let config = SocialMediaPreset.instagram.toExportConfig()
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 30.0)
        let maxBytes = SocialMediaPreset.instagram.maxFileSizeMB * 1024 * 1024
        #expect(size < maxBytes)
    }

    @Test("TikTok preset export estimate for short video is within limit")
    func tiktokPresetEstimate() {
        let config = SocialMediaPreset.tiktok.toExportConfig()
        let size = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 60.0)
        let maxBytes = SocialMediaPreset.tiktok.maxFileSizeMB * 1024 * 1024
        #expect(size < maxBytes)
    }
}
