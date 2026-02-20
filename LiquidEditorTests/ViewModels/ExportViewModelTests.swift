import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ExportState Tests

@Suite("ExportState Tests")
struct ExportStateTests {

    @Test("idle state is the default")
    func idleDefault() {
        let state: ExportState = .idle
        if case .idle = state {
            // Pass
        } else {
            Issue.record("Expected idle state")
        }
    }

    @Test("complete state carries output URL")
    func completeWithURL() {
        let url = URL(fileURLWithPath: "/tmp/export.mp4")
        let state: ExportState = .complete(outputURL: url)

        if case .complete(let outputURL) = state {
            #expect(outputURL == url)
        } else {
            Issue.record("Expected complete state")
        }
    }

    @Test("failed state carries message")
    func failedWithMessage() {
        let state: ExportState = .failed(message: "Disk full")

        if case .failed(let message) = state {
            #expect(message == "Disk full")
        } else {
            Issue.record("Expected failed state")
        }
    }
}

// MARK: - ExportViewModel Tests

@Suite("ExportViewModel Tests")
@MainActor
struct ExportViewModelTests {

    // MARK: - Helpers

    private func makeVM() -> ExportViewModel {
        ExportViewModel()
    }

    // MARK: - Initial State

    @Suite("Initial State")
    @MainActor
    struct InitialStateTests {

        @Test("Not exporting on init")
        func notExporting() {
            let vm = ExportViewModel()
            #expect(vm.isExporting == false)
        }

        @Test("Progress is 0 on init")
        func progressZero() {
            let vm = ExportViewModel()
            #expect(vm.progress == 0.0)
        }

        @Test("Export state is idle on init")
        func idleState() {
            let vm = ExportViewModel()
            if case .idle = vm.exportState {
                // Pass
            } else {
                Issue.record("Expected idle state on init")
            }
        }

        @Test("No error message on init")
        func noErrorMessage() {
            let vm = ExportViewModel()
            #expect(vm.errorMessage == nil)
        }

        @Test("Default config is 1080p H.264 MP4")
        func defaultConfig() {
            let vm = ExportViewModel()
            #expect(vm.config.resolution == .r1080p)
            #expect(vm.config.codec == .h264)
            #expect(vm.config.format == .mp4)
            #expect(vm.config.fps == 30)
            #expect(vm.config.quality == .high)
        }

        @Test("isComplete is false on init")
        func notComplete() {
            let vm = ExportViewModel()
            #expect(vm.isComplete == false)
        }

        @Test("completedOutputURL is nil on init")
        func noOutputURL() {
            let vm = ExportViewModel()
            #expect(vm.completedOutputURL == nil)
        }
    }

    // MARK: - Resolution Update

    @Test("updateResolution changes config resolution")
    func updateResolution() {
        let vm = makeVM()
        vm.updateResolution(.r4K)
        #expect(vm.config.resolution == .r4K)
    }

    @Test("updateResolution to 720p")
    func updateResolution720p() {
        let vm = makeVM()
        vm.updateResolution(.r720p)
        #expect(vm.config.resolution == .r720p)
        #expect(vm.config.outputWidth == 1280)
        #expect(vm.config.outputHeight == 720)
    }

    // MARK: - Codec Update

    @Test("updateCodec changes codec")
    func updateCodec() {
        let vm = makeVM()
        vm.updateCodec(.h265)
        #expect(vm.config.codec == .h265)
    }

    @Test("updateCodec to ProRes")
    func updateCodecProRes() {
        let vm = makeVM()
        vm.updateCodec(.proRes)
        #expect(vm.config.codec == .proRes)
    }

    // MARK: - Format Update

    @Test("updateFormat changes container format")
    func updateFormat() {
        let vm = makeVM()
        vm.updateFormat(.mov)
        #expect(vm.config.format == .mov)
    }

    @Test("updateFormat to M4V")
    func updateFormatM4V() {
        let vm = makeVM()
        vm.updateFormat(.m4v)
        #expect(vm.config.format == .m4v)
    }

    // MARK: - FPS Update

    @Test("updateFPS changes frame rate")
    func updateFPS() {
        let vm = makeVM()
        vm.updateFPS(60)
        #expect(vm.config.fps == 60)
    }

    @Test("updateFPS to 24")
    func updateFPS24() {
        let vm = makeVM()
        vm.updateFPS(24)
        #expect(vm.config.fps == 24)
    }

    // MARK: - Quality Update

    @Test("updateQuality changes quality preset")
    func updateQuality() {
        let vm = makeVM()
        vm.updateQuality(.maximum)
        #expect(vm.config.quality == .maximum)
    }

    @Test("updateQuality to draft")
    func updateQualityDraft() {
        let vm = makeVM()
        vm.updateQuality(.draft)
        #expect(vm.config.quality == .draft)
    }

    // MARK: - Reset

    @Test("reset clears export state to idle")
    func reset() {
        let vm = makeVM()
        vm.isExporting = true
        vm.progress = 0.75
        vm.errorMessage = "Some error"

        vm.reset()

        #expect(vm.isExporting == false)
        #expect(vm.progress == 0.0)
        #expect(vm.errorMessage == nil)

        if case .idle = vm.exportState {
            // Pass
        } else {
            Issue.record("Expected idle state after reset")
        }
    }

    // MARK: - Estimated File Size

    @Test("estimatedFileSize returns a non-empty string")
    func estimatedFileSizeNotEmpty() {
        let vm = makeVM()
        let size = vm.estimatedFileSize
        #expect(!size.isEmpty)
    }

    @Test("estimatedFileSize changes with resolution")
    func estimatedFileSizeChangesWithResolution() {
        let vm = makeVM()
        let size1080 = vm.estimatedFileSize

        vm.updateResolution(.r4K)
        let size4K = vm.estimatedFileSize

        // 4K should report a larger estimated size than 1080p
        #expect(size1080 != size4K)
    }

    // MARK: - Estimated Duration

    @Test("estimatedDuration returns 'No content' when timeline is empty")
    func estimatedDurationEmpty() {
        let vm = makeVM()
        #expect(vm.estimatedDuration == "No content")
    }

    @Test("estimatedDuration returns formatted time for 60s H.264 1080p")
    func estimatedDuration60sH264() {
        let vm = makeVM()
        vm.timelineDurationMicros = 60_000_000 // 60 seconds
        // H.264 = 1.0x, 1080p = 1.0x scale => 60s
        #expect(vm.estimatedDuration == "~1m")
    }

    @Test("estimatedDuration scales with codec complexity")
    func estimatedDurationCodecScaling() {
        let vm = makeVM()
        vm.timelineDurationMicros = 60_000_000 // 60 seconds
        vm.updateCodec(.h265)
        // H.265 = 1.5x => 90s => "~1m 30s"
        #expect(vm.estimatedDuration == "~1m 30s")
    }

    @Test("estimatedDuration scales with resolution")
    func estimatedDurationResolutionScaling() {
        let vm = makeVM()
        vm.timelineDurationMicros = 60_000_000 // 60 seconds
        vm.updateResolution(.r4K)
        // H.264 = 1.0x, 4K (3840x2160) / 1080p (1920x1080) = 4.0x => 240s => "~4m"
        #expect(vm.estimatedDuration == "~4m")
    }

    @Test("estimatedDuration returns seconds format for short content")
    func estimatedDurationShortContent() {
        let vm = makeVM()
        vm.timelineDurationMicros = 10_000_000 // 10 seconds
        // H.264 = 1.0x, 1080p = 1.0x => 10s
        #expect(vm.estimatedDuration == "~10s")
    }

    // MARK: - Share

    @Test("shareExportedVideo returns nil when not complete")
    func shareNotComplete() {
        let vm = makeVM()
        #expect(vm.shareExportedVideo() == nil)
    }

    // MARK: - Resolution Presets

    @Test("Resolution presets contain expected values")
    func resolutionPresets() {
        let presets = ExportViewModel.resolutionPresets
        #expect(presets.contains(.r720p))
        #expect(presets.contains(.r1080p))
        #expect(presets.contains(.r4K))
        #expect(presets.count == 3)
    }

    // MARK: - FPS Options

    @Test("FPS options contain expected values")
    func fpsOptions() {
        let options = ExportViewModel.fpsOptions
        #expect(options.contains(24))
        #expect(options.contains(30))
        #expect(options.contains(60))
        #expect(options.count == 3)
    }

    // MARK: - isComplete / completedOutputURL

    @Test("isComplete reflects export state")
    func isCompleteReflectsState() {
        let vm = makeVM()
        #expect(vm.isComplete == false)

        let url = URL(fileURLWithPath: "/tmp/done.mp4")
        vm.exportState = .complete(outputURL: url)
        #expect(vm.isComplete == true)

        vm.exportState = .failed(message: "oops")
        #expect(vm.isComplete == false)
    }

    @Test("completedOutputURL returns URL when complete")
    func completedOutputURLWhenComplete() {
        let vm = makeVM()
        let url = URL(fileURLWithPath: "/tmp/done.mp4")
        vm.exportState = .complete(outputURL: url)
        #expect(vm.completedOutputURL == url)
    }

    @Test("completedOutputURL returns nil when not complete")
    func completedOutputURLWhenNotComplete() {
        let vm = makeVM()
        vm.exportState = .exporting
        #expect(vm.completedOutputURL == nil)
    }

    // MARK: - Config Chaining

    @Test("Multiple config updates chain correctly")
    func configChaining() {
        let vm = makeVM()
        vm.updateResolution(.r4K)
        vm.updateCodec(.h265)
        vm.updateFormat(.mov)
        vm.updateFPS(60)
        vm.updateQuality(.maximum)

        #expect(vm.config.resolution == .r4K)
        #expect(vm.config.codec == .h265)
        #expect(vm.config.format == .mov)
        #expect(vm.config.fps == 60)
        #expect(vm.config.quality == .maximum)
    }
}
