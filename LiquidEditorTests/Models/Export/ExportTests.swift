import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ExportResolution Tests

@Suite("ExportResolution Tests")
struct ExportResolutionTests {

    @Test("All cases exist")
    func allCases() {
        #expect(ExportResolution.allCases.count == 6)
    }

    @Test("Width and height for standard resolutions")
    func widthHeight() {
        #expect(ExportResolution.r480p.width == 854)
        #expect(ExportResolution.r480p.height == 480)
        #expect(ExportResolution.r720p.width == 1280)
        #expect(ExportResolution.r720p.height == 720)
        #expect(ExportResolution.r1080p.width == 1920)
        #expect(ExportResolution.r1080p.height == 1080)
        #expect(ExportResolution.r1440p.width == 2560)
        #expect(ExportResolution.r1440p.height == 1440)
        #expect(ExportResolution.r4K.width == 3840)
        #expect(ExportResolution.r4K.height == 2160)
    }

    @Test("Custom resolution returns 0")
    func customResolution() {
        #expect(ExportResolution.custom.width == 0)
        #expect(ExportResolution.custom.height == 0)
    }

    @Test("Labels")
    func labels() {
        #expect(ExportResolution.r1080p.label == "1080p")
        #expect(ExportResolution.r4K.label == "4K")
        #expect(ExportResolution.custom.label == "Custom")
    }
}

// MARK: - ExportCodec Tests

@Suite("ExportCodec Tests")
struct ExportCodecTests {

    @Test("Display names")
    func displayNames() {
        #expect(ExportCodec.h264.displayName == "H.264")
        #expect(ExportCodec.h265.displayName == "H.265 (HEVC)")
        #expect(ExportCodec.proRes.displayName == "ProRes")
    }

    @Test("AVFoundation keys")
    func avFoundationKeys() {
        #expect(ExportCodec.h264.avFoundationKey == "avc1")
        #expect(ExportCodec.h265.avFoundationKey == "hvc1")
        #expect(ExportCodec.proRes.avFoundationKey == "apcn")
    }
}

// MARK: - ExportFormat Tests

@Suite("ExportFormat Tests")
struct ExportFormatTests {

    @Test("File extensions")
    func fileExtensions() {
        #expect(ExportFormat.mp4.fileExtension == "mp4")
        #expect(ExportFormat.mov.fileExtension == "mov")
        #expect(ExportFormat.m4v.fileExtension == "m4v")
    }

    @Test("MIME types")
    func mimeTypes() {
        #expect(ExportFormat.mp4.mimeType == "video/mp4")
        #expect(ExportFormat.mov.mimeType == "video/quicktime")
        #expect(ExportFormat.m4v.mimeType == "video/x-m4v")
    }

    @Test("Display names")
    func displayNames() {
        #expect(ExportFormat.mp4.displayName == "MP4")
        #expect(ExportFormat.mov.displayName == "MOV")
    }
}

// MARK: - ExportQuality Tests

@Suite("ExportQuality Tests")
struct ExportQualityTests {

    @Test("Bitrate multipliers")
    func bitrateMultipliers() {
        #expect(ExportQuality.draft.bitrateMultiplier == 0.3)
        #expect(ExportQuality.standard.bitrateMultiplier == 0.6)
        #expect(ExportQuality.high.bitrateMultiplier == 1.0)
        #expect(ExportQuality.maximum.bitrateMultiplier == 1.5)
    }

    @Test("Labels")
    func labels() {
        #expect(ExportQuality.draft.label == "Draft")
        #expect(ExportQuality.maximum.label == "Maximum")
    }
}

// MARK: - ExportAudioCodec Tests

@Suite("ExportAudioCodec Tests")
struct ExportAudioCodecTests {

    @Test("Display names")
    func displayNames() {
        #expect(ExportAudioCodec.aac.displayName == "AAC")
        #expect(ExportAudioCodec.alac.displayName == "ALAC")
        #expect(ExportAudioCodec.wav.displayName == "WAV")
        #expect(ExportAudioCodec.flac.displayName == "FLAC")
    }

    @Test("File extensions")
    func fileExtensions() {
        #expect(ExportAudioCodec.aac.fileExtension == "m4a")
        #expect(ExportAudioCodec.alac.fileExtension == "m4a")
        #expect(ExportAudioCodec.wav.fileExtension == "wav")
        #expect(ExportAudioCodec.flac.fileExtension == "flac")
    }
}

// MARK: - SocialMediaPreset Tests

@Suite("SocialMediaPreset Tests")
struct SocialMediaPresetTests {

    @Test("Instagram properties")
    func instagram() {
        let preset = SocialMediaPreset.instagram
        #expect(preset.width == 1080)
        #expect(preset.height == 1920)
        #expect(preset.maxFps == 30)
        #expect(preset.aspectRatioWidth == 9)
        #expect(preset.aspectRatioHeight == 16)
        #expect(preset.supportsHdr == false)
    }

    @Test("YouTube properties")
    func youtube() {
        let preset = SocialMediaPreset.youtube
        #expect(preset.width == 3840)
        #expect(preset.height == 2160)
        #expect(preset.maxFps == 60)
        #expect(preset.supportsHdr == true)
        #expect(preset.aspectRatioWidth == 16)
        #expect(preset.aspectRatioHeight == 9)
    }

    @Test("TikTok properties")
    func tiktok() {
        let preset = SocialMediaPreset.tiktok
        #expect(preset.width == 1080)
        #expect(preset.height == 1920)
        #expect(preset.maxFps == 60)
        #expect(preset.maxDurationSeconds == 600)
    }

    @Test("Aspect ratio computed correctly")
    func aspectRatio() {
        let yt = SocialMediaPreset.youtube
        let expected = 16.0 / 9.0
        #expect(abs(yt.aspectRatio - expected) < 0.0001)
    }

    @Test("toExportConfig produces valid config")
    func toExportConfig() {
        let config = SocialMediaPreset.instagram.toExportConfig()
        #expect(config.resolution == .custom)
        #expect(config.customWidth == 1080)
        #expect(config.customHeight == 1920)
        #expect(config.fps == 30)
        #expect(config.codec == .h264)
        #expect(config.format == .mp4)
        #expect(config.quality == .high)
        #expect(config.socialPreset == .instagram)
    }

    @Test("All presets use H.264 codec")
    func allPresetsCodec() {
        for preset in SocialMediaPreset.allCases {
            #expect(preset.codec == .h264)
        }
    }

    @Test("All presets use MP4 format")
    func allPresetsFormat() {
        for preset in SocialMediaPreset.allCases {
            #expect(preset.format == .mp4)
        }
    }
}

// MARK: - ExportConfig Tests

@Suite("ExportConfig Tests")
struct ExportConfigTests {

    @Test("Default creation")
    func defaults() {
        let config = ExportConfig()
        #expect(config.resolution == .r1080p)
        #expect(config.fps == 30)
        #expect(config.codec == .h264)
        #expect(config.format == .mp4)
        #expect(config.quality == .high)
        #expect(config.bitrateMbps == 20.0)
        #expect(config.audioCodec == .aac)
        #expect(config.audioBitrate == 256)
        #expect(config.enableHdr == false)
        #expect(config.audioOnly == false)
        #expect(config.socialPreset == nil)
        #expect(config.customWidth == nil)
        #expect(config.customHeight == nil)
    }

    @Test("Output width/height for standard resolution")
    func outputDimensionsStandard() {
        let config = ExportConfig(resolution: .r720p)
        #expect(config.outputWidth == 1280)
        #expect(config.outputHeight == 720)
    }

    @Test("Output width/height for custom resolution")
    func outputDimensionsCustom() {
        let config = ExportConfig(resolution: .custom, customWidth: 1440, customHeight: 900)
        #expect(config.outputWidth == 1440)
        #expect(config.outputHeight == 900)
    }

    @Test("Output width/height for custom with nil values defaults")
    func outputDimensionsCustomNil() {
        let config = ExportConfig(resolution: .custom)
        #expect(config.outputWidth == 1920) // fallback
        #expect(config.outputHeight == 1080) // fallback
    }

    @Test("Effective bitrate applies quality multiplier")
    func effectiveBitrate() {
        let config = ExportConfig(resolution: .r1080p, quality: .draft, bitrateMbps: 20.0)
        #expect(abs(config.effectiveBitrateMbps - 6.0) < 0.01) // 20 * 0.3
    }

    @Test("Effective bitrate high quality")
    func effectiveBitrateHigh() {
        let config = ExportConfig(resolution: .r1080p, quality: .high, bitrateMbps: 20.0)
        #expect(abs(config.effectiveBitrateMbps - 20.0) < 0.01) // 20 * 1.0
    }

    @Test("Effective bitrate maximum quality")
    func effectiveBitrateMax() {
        let config = ExportConfig(resolution: .r1080p, quality: .maximum, bitrateMbps: 20.0)
        #expect(abs(config.effectiveBitrateMbps - 30.0) < 0.01) // 20 * 1.5
    }

    @Test("with() copy method")
    func withCopy() {
        let original = ExportConfig()
        let modified = original.with(fps: 60, codec: .h265, enableHdr: true)
        #expect(modified.fps == 60)
        #expect(modified.codec == .h265)
        #expect(modified.enableHdr == true)
        #expect(modified.resolution == .r1080p) // unchanged
        #expect(modified.format == .mp4) // unchanged
    }

    @Test("with() can set social preset")
    func withSocialPreset() {
        let config = ExportConfig().with(socialPreset: .some(.tiktok))
        #expect(config.socialPreset == .tiktok)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = ExportConfig(
            resolution: .r4K,
            customWidth: nil,
            customHeight: nil,
            fps: 60,
            codec: .h265,
            format: .mov,
            quality: .maximum,
            bitrateMbps: 50.0,
            audioCodec: .alac,
            audioBitrate: 320,
            enableHdr: true,
            audioOnly: false,
            socialPreset: .youtube
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportConfig.self, from: data)
        #expect(decoded.resolution == .r4K)
        #expect(decoded.fps == 60)
        #expect(decoded.codec == .h265)
        #expect(decoded.format == .mov)
        #expect(decoded.quality == .maximum)
        #expect(abs(decoded.bitrateMbps - 50.0) < 0.01)
        #expect(decoded.audioCodec == .alac)
        #expect(decoded.audioBitrate == 320)
        #expect(decoded.enableHdr == true)
        #expect(decoded.socialPreset == .youtube)
    }

    @Test("Codable roundtrip with defaults")
    func codableRoundtripDefaults() throws {
        let original = ExportConfig()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportConfig.self, from: data)
        #expect(decoded.resolution == original.resolution)
        #expect(decoded.fps == original.fps)
        #expect(decoded.codec == original.codec)
    }
}

// MARK: - ExportJob Tests

@Suite("ExportJob Tests")
struct ExportJobTests {

    func makeJob(
        id: String = "job-1",
        status: ExportJobStatus = .queued
    ) -> ExportJob {
        ExportJob(
            id: id,
            label: "Export 1080p",
            config: ExportConfig(),
            status: status,
            createdAt: Date(timeIntervalSince1970: 1700000000)
        )
    }

    @Test("Creation with defaults")
    func creation() {
        let job = makeJob()
        #expect(job.id == "job-1")
        #expect(job.label == "Export 1080p")
        #expect(job.status == .queued)
        #expect(job.priority == .normal)
        #expect(job.progress == 0.0)
        #expect(job.outputPath == nil)
        #expect(job.outputSizeBytes == nil)
        #expect(job.errorMessage == nil)
        #expect(job.startedAt == nil)
        #expect(job.completedAt == nil)
    }

    @Test("isActive for active states")
    func isActive() {
        #expect(makeJob(status: .queued).isActive == true)
        #expect(makeJob(status: .preparing).isActive == true)
        #expect(makeJob(status: .rendering).isActive == true)
        #expect(makeJob(status: .encoding).isActive == true)
        #expect(makeJob(status: .saving).isActive == true)
        #expect(makeJob(status: .paused).isActive == true)
        #expect(makeJob(status: .completed).isActive == false)
        #expect(makeJob(status: .failed).isActive == false)
        #expect(makeJob(status: .cancelled).isActive == false)
    }

    @Test("isTerminal for terminal states")
    func isTerminal() {
        #expect(makeJob(status: .completed).isTerminal == true)
        #expect(makeJob(status: .failed).isTerminal == true)
        #expect(makeJob(status: .cancelled).isTerminal == true)
        #expect(makeJob(status: .queued).isTerminal == false)
        #expect(makeJob(status: .rendering).isTerminal == false)
    }

    @Test("isRunning for running states")
    func isRunning() {
        #expect(makeJob(status: .preparing).isRunning == true)
        #expect(makeJob(status: .rendering).isRunning == true)
        #expect(makeJob(status: .encoding).isRunning == true)
        #expect(makeJob(status: .saving).isRunning == true)
        #expect(makeJob(status: .queued).isRunning == false)
        #expect(makeJob(status: .completed).isRunning == false)
        #expect(makeJob(status: .paused).isRunning == false)
    }

    @Test("Output size string formatting")
    func outputSizeString() {
        let job = makeJob().with(outputSizeBytes: .some(104_857_600)) // 100 MB
        #expect(job.outputSizeString == "100.0 MB")
    }

    @Test("Output size string empty when nil")
    func outputSizeStringNil() {
        let job = makeJob()
        #expect(job.outputSizeString == "")
    }

    @Test("Output size string GB formatting")
    func outputSizeStringGB() {
        let job = makeJob().with(outputSizeBytes: .some(1_610_612_736)) // ~1.5 GB
        #expect(job.outputSizeString == "1.5 GB")
    }

    @Test("Export duration computed")
    func exportDuration() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 1060)
        let job = ExportJob(
            id: "j",
            label: "L",
            config: ExportConfig(),
            createdAt: Date(),
            startedAt: start,
            completedAt: end
        )
        #expect(abs((job.exportDuration ?? 0) - 60.0) < 0.01)
    }

    @Test("Export duration nil when not started")
    func exportDurationNil() {
        let job = makeJob()
        #expect(job.exportDuration == nil)
    }

    @Test("with() copy method")
    func withCopy() {
        let original = makeJob()
        let modified = original.with(
            status: .rendering,
            progress: 0.5,
            errorMessage: nil
        )
        #expect(modified.status == .rendering)
        #expect(modified.progress == 0.5)
        #expect(modified.id == "job-1")
    }

    @Test("Equatable by id only")
    func equatable() {
        let a = makeJob(id: "same")
        let b = ExportJob(
            id: "same",
            label: "Different",
            config: ExportConfig(fps: 60),
            status: .completed,
            createdAt: Date()
        )
        #expect(a == b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = ExportJob(
            id: "job-1",
            label: "Export",
            config: ExportConfig(resolution: .r720p, fps: 24),
            status: .completed,
            priority: .high,
            progress: 1.0,
            outputPath: "/tmp/out.mp4",
            outputSizeBytes: 5000,
            createdAt: Date(timeIntervalSince1970: 1700000000),
            startedAt: Date(timeIntervalSince1970: 1700000100),
            completedAt: Date(timeIntervalSince1970: 1700000200)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportJob.self, from: data)
        #expect(decoded == original)
        #expect(decoded.status == .completed)
        #expect(decoded.priority == .high)
        #expect(decoded.progress == 1.0)
        #expect(decoded.outputPath == "/tmp/out.mp4")
    }
}

// MARK: - ExportProgress Tests

@Suite("ExportProgress Tests")
struct ExportProgressTests {

    @Test("ETA string for seconds")
    func etaStringSeconds() {
        let progress = ExportProgress(
            exportId: "e",
            phase: .rendering,
            overallProgress: 0.5,
            startedAt: Date(),
            elapsedMs: 5000,
            estimatedRemainingMs: 30000
        )
        #expect(progress.etaString == "30s remaining")
    }

    @Test("ETA string for minutes")
    func etaStringMinutes() {
        let progress = ExportProgress(
            exportId: "e",
            phase: .rendering,
            overallProgress: 0.2,
            startedAt: Date(),
            elapsedMs: 5000,
            estimatedRemainingMs: 150000
        )
        #expect(progress.etaString == "2m 30s remaining")
    }

    @Test("ETA string calculating when nil")
    func etaStringCalculating() {
        let progress = ExportProgress(
            exportId: "e",
            phase: .preparing,
            overallProgress: 0.0,
            startedAt: Date(),
            elapsedMs: 0
        )
        #expect(progress.etaString == "Calculating...")
    }

    @Test("Percentage string")
    func percentageString() {
        let progress = ExportProgress(
            exportId: "e",
            phase: .rendering,
            overallProgress: 0.75,
            startedAt: Date(),
            elapsedMs: 5000
        )
        #expect(progress.percentageString == "75%")
    }

    @Test("Thermal concern thresholds")
    func thermalConcern() {
        let nominal = ExportProgress(
            exportId: "e", phase: .rendering, overallProgress: 0.5,
            startedAt: Date(), elapsedMs: 0, thermalState: 0
        )
        let serious = ExportProgress(
            exportId: "e", phase: .rendering, overallProgress: 0.5,
            startedAt: Date(), elapsedMs: 0, thermalState: 2
        )
        #expect(nominal.isThermalConcern == false)
        #expect(serious.isThermalConcern == true)
    }

    @Test("Disk low detection")
    func diskLow() {
        let ok = ExportProgress(
            exportId: "e", phase: .rendering, overallProgress: 0.5,
            startedAt: Date(), elapsedMs: 0, availableDiskMB: 1000
        )
        let low = ExportProgress(
            exportId: "e", phase: .rendering, overallProgress: 0.5,
            startedAt: Date(), elapsedMs: 0, availableDiskMB: 200
        )
        #expect(ok.isDiskLow == false)
        #expect(low.isDiskLow == true)
    }
}

// MARK: - FileSizeEstimator Tests

@Suite("FileSizeEstimator Legacy Tests")
struct FileSizeEstimatorLegacyTests {

    @Test("Video size estimation - basic calculation")
    func videoSizeBasic() {
        let config = ExportConfig(resolution: .r1080p, quality: .high, bitrateMbps: 20.0)
        let bytes = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 60.0)
        // 20 Mbps * 1.0 (high) = 20 Mbps video
        // 256 kbps audio
        // (20_000_000 + 256_000) * 60 / 8 * 1.1
        let expected = Int(((20_000_000.0 + 256_000.0) * 60.0 / 8.0 * 1.1).rounded())
        #expect(bytes == expected)
    }

    @Test("Video size estimation - zero duration")
    func videoSizeZero() {
        let config = ExportConfig()
        let bytes = FileSizeEstimator.estimateVideoSizeBytes(config: config, duration: 0)
        #expect(bytes == 0)
    }

    @Test("Audio size estimation - AAC")
    func audioSizeAAC() {
        let bytes = FileSizeEstimator.estimateAudioSizeBytes(codec: .aac, bitrate: 256, duration: 60.0)
        // 256 * 1000 * 60 / 8 * 1.05
        let expected = Int((256.0 * 1000.0 * 60.0 / 8.0 * 1.05).rounded())
        #expect(bytes == expected)
    }

    @Test("Audio size estimation - WAV")
    func audioSizeWAV() {
        let bytes = FileSizeEstimator.estimateAudioSizeBytes(codec: .wav, bitrate: 0, duration: 10.0)
        // PCM: 48000 * 16 * 2 / 8 * 10 * 1.01
        let pcmBytesPerSecond: Double = 48000.0 * 16.0 * 2.0 / 8.0
        let expected = Int((pcmBytesPerSecond * 10.0 * 1.01).rounded())
        #expect(bytes == expected)
    }

    @Test("Audio size estimation - ALAC (lossless compressed)")
    func audioSizeALAC() {
        let bytes = FileSizeEstimator.estimateAudioSizeBytes(codec: .alac, bitrate: 0, duration: 10.0)
        // Lossless: PCM * 0.6
        let pcm = 48000.0 * 16.0 * 2.0 / 8.0 * 10.0
        let expected = Int((pcm * 0.6).rounded())
        #expect(bytes == expected)
    }

    @Test("Audio size estimation - FLAC (lossless compressed)")
    func audioSizeFLAC() {
        let bytes = FileSizeEstimator.estimateAudioSizeBytes(codec: .flac, bitrate: 0, duration: 10.0)
        let pcm = 48000.0 * 16.0 * 2.0 / 8.0 * 10.0
        let expected = Int((pcm * 0.6).rounded())
        #expect(bytes == expected)
    }

    @Test("Audio size estimation - zero duration")
    func audioSizeZero() {
        #expect(FileSizeEstimator.estimateAudioSizeBytes(codec: .aac, bitrate: 256, duration: 0) == 0)
    }

    @Test("Format bytes")
    func formatBytesTest() {
        #expect(FileSizeEstimator.formatBytes(0) == "0 B")
        #expect(FileSizeEstimator.formatBytes(500) == "500 B")
        #expect(FileSizeEstimator.formatBytes(1024) == "1.0 KB")
        #expect(FileSizeEstimator.formatBytes(1_048_576) == "1.0 MB")
        #expect(FileSizeEstimator.formatBytes(1_073_741_824) == "1.0 GB")
    }

    @Test("Storage warning when insufficient")
    func storageWarningInsufficient() {
        let warning = FileSizeEstimator.checkStorageWarning(
            estimatedSizeBytes: 1_000_000_000,
            availableDiskBytes: 500_000_000
        )
        #expect(warning != nil)
    }

    @Test("Storage warning when sufficient")
    func storageWarningSufficient() {
        let warning = FileSizeEstimator.checkStorageWarning(
            estimatedSizeBytes: 100_000_000,
            availableDiskBytes: 2_000_000_000
        )
        #expect(warning == nil)
    }

    @Test("Platform size warning when exceeds limit")
    func platformSizeWarning() {
        // Instagram limit is 250 MB
        let oversized = 300 * 1024 * 1024
        let warning = FileSizeEstimator.checkPlatformSizeWarning(
            estimatedSizeBytes: oversized,
            preset: .instagram
        )
        #expect(warning != nil)
    }

    @Test("Platform size warning when within limit")
    func platformSizeWarningOk() {
        let undersized = 100 * 1024 * 1024
        let warning = FileSizeEstimator.checkPlatformSizeWarning(
            estimatedSizeBytes: undersized,
            preset: .instagram
        )
        #expect(warning == nil)
    }

    @Test("Duration warning when exceeds limit")
    func durationWarning() {
        // TikTok limit is 600 seconds
        let warning = FileSizeEstimator.checkDurationWarning(
            duration: 700.0,
            preset: .tiktok
        )
        #expect(warning != nil)
    }

    @Test("Duration warning when within limit")
    func durationWarningOk() {
        let warning = FileSizeEstimator.checkDurationWarning(
            duration: 300.0,
            preset: .tiktok
        )
        #expect(warning == nil)
    }
}

// MARK: - ExportPhase Tests

@Suite("ExportPhase Tests")
struct ExportPhaseTests {

    @Test("All phases exist")
    func allCases() {
        #expect(ExportPhase.allCases.count == 7)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for phase in ExportPhase.allCases {
            let data = try JSONEncoder().encode(phase)
            let decoded = try JSONDecoder().decode(ExportPhase.self, from: data)
            #expect(decoded == phase)
        }
    }
}

// MARK: - ExportJobStatus Tests

@Suite("ExportJobStatus Tests")
struct ExportJobStatusTests {

    @Test("All statuses exist")
    func allCases() {
        #expect(ExportJobStatus.allCases.count == 9)
    }
}

// MARK: - ExportJobPriority Tests

@Suite("ExportJobPriority Tests")
struct ExportJobPriorityTests {

    @Test("All priorities exist")
    func allCases() {
        #expect(ExportJobPriority.allCases.count == 3)
    }
}
