import Testing
import Foundation
@testable import LiquidEditor

// MARK: - applySlowMotion Tests

@Suite("SlowMotionService - applySlowMotion")
struct ApplySlowMotionTests {

    let service = SlowMotionService.shared

    // MARK: - High FPS Sources

    @Test("120fps at 0.5x uses no blend (native resampling)")
    func highFps120_halfSpeed() {
        // 120fps / 30fps = 4x native limit. 0.5x = 2x slow-mo, within limit.
        let config = service.applySlowMotion(sourceFrameRate: 120, slowFactor: 0.5)

        #expect(config.speedMultiplier == 0.5)
        #expect(config.blendMode == .none)
        #expect(config.maintainPitch == true)
    }

    @Test("120fps at 0.25x uses no blend (at native limit)")
    func highFps120_quarterSpeed() {
        // 120fps / 30fps = 4x native limit. 0.25x = 4x slow-mo, exactly at limit.
        let config = service.applySlowMotion(sourceFrameRate: 120, slowFactor: 0.25)

        #expect(config.speedMultiplier == 0.25)
        #expect(config.blendMode == .none)
        #expect(config.maintainPitch == true)
    }

    @Test("120fps at 0.2x uses optical flow (beyond native limit)")
    func highFps120_beyondNative() {
        // 120fps / 30fps = 4x native limit. 0.2x = 5x slow-mo, beyond limit.
        let config = service.applySlowMotion(sourceFrameRate: 120, slowFactor: 0.2)

        #expect(config.speedMultiplier == 0.2)
        #expect(config.blendMode == .opticalFlow)
        #expect(config.maintainPitch == true)
    }

    @Test("240fps at 0.125x uses no blend (at native limit)")
    func highFps240_eighthSpeed() {
        // 240fps / 30fps = 8x native limit. 0.125x = 8x slow-mo, at limit.
        let config = service.applySlowMotion(sourceFrameRate: 240, slowFactor: 0.125)

        #expect(config.speedMultiplier == 0.125)
        #expect(config.blendMode == .none)
        #expect(config.maintainPitch == true)
    }

    @Test("240fps at 0.1x uses optical flow (beyond native limit)")
    func highFps240_beyondNative() {
        // 240fps / 30fps = 8x native limit. 0.1x = 10x slow-mo, beyond limit.
        let config = service.applySlowMotion(sourceFrameRate: 240, slowFactor: 0.1)

        #expect(config.speedMultiplier == 0.1)
        #expect(config.blendMode == .opticalFlow)
        #expect(config.maintainPitch == true)
    }

    // MARK: - Standard FPS Sources

    @Test("30fps at 0.5x uses blend mode")
    func standardFps30_halfSpeed() {
        // Standard fps at 0.5x: clamped >= 0.5 → .blend
        let config = service.applySlowMotion(sourceFrameRate: 30, slowFactor: 0.5)

        #expect(config.speedMultiplier == 0.5)
        #expect(config.blendMode == .blend)
        #expect(config.maintainPitch == true)
    }

    @Test("30fps at 0.25x uses optical flow")
    func standardFps30_quarterSpeed() {
        // Standard fps at 0.25x: clamped < 0.5 → .opticalFlow
        let config = service.applySlowMotion(sourceFrameRate: 30, slowFactor: 0.25)

        #expect(config.speedMultiplier == 0.25)
        #expect(config.blendMode == .opticalFlow)
        #expect(config.maintainPitch == true)
    }

    @Test("24fps at 0.5x uses blend mode")
    func standardFps24_halfSpeed() {
        let config = service.applySlowMotion(sourceFrameRate: 24, slowFactor: 0.5)

        #expect(config.speedMultiplier == 0.5)
        #expect(config.blendMode == .blend)
    }

    @Test("24fps at 0.3x uses optical flow")
    func standardFps24_slowSpeed() {
        let config = service.applySlowMotion(sourceFrameRate: 24, slowFactor: 0.3)

        #expect(config.speedMultiplier == 0.3)
        #expect(config.blendMode == .opticalFlow)
    }

    // MARK: - Edge Cases

    @Test("1.0x factor returns normal speed with no blend")
    func normalSpeed() {
        // 1.0x on high-fps: requestedSlowMo = 1.0, maxNative = 4.0, within limit → .none
        let configHigh = service.applySlowMotion(sourceFrameRate: 120, slowFactor: 1.0)
        #expect(configHigh.speedMultiplier == 1.0)
        #expect(configHigh.blendMode == .none)

        // 1.0x on standard-fps: clamped >= 0.5 → .blend
        let configStd = service.applySlowMotion(sourceFrameRate: 30, slowFactor: 1.0)
        #expect(configStd.speedMultiplier == 1.0)
        #expect(configStd.blendMode == .blend)
    }

    @Test("very small factor (0.01x) is clamped to 0.1x")
    func verySmallFactor() {
        // slowFactor 0.01 is clamped to 0.1
        let config = service.applySlowMotion(sourceFrameRate: 30, slowFactor: 0.01)

        #expect(config.speedMultiplier == 0.1)
        #expect(config.blendMode == .opticalFlow) // 0.1 < 0.5 → opticalFlow
    }

    @Test("factor above 1.0 is clamped to 1.0")
    func factorAboveOne() {
        let config = service.applySlowMotion(sourceFrameRate: 120, slowFactor: 2.0)

        #expect(config.speedMultiplier == 1.0)
        #expect(config.blendMode == .none)
    }

    @Test("exactly at high fps threshold (60fps)")
    func exactlyAtThreshold() {
        // 60fps is >= 60 threshold, so treated as high-fps.
        // maxNative = 60 / 30 = 2x. At 0.5x = 2x slow-mo, at limit → .none
        let config = service.applySlowMotion(sourceFrameRate: 60, slowFactor: 0.5)

        #expect(config.speedMultiplier == 0.5)
        #expect(config.blendMode == .none)
    }

    @Test("just below high fps threshold (59fps) uses standard path")
    func justBelowThreshold() {
        // 59fps < 60 threshold → standard fps path.
        let config = service.applySlowMotion(sourceFrameRate: 59, slowFactor: 0.5)

        #expect(config.speedMultiplier == 0.5)
        #expect(config.blendMode == .blend) // standard fps, clamped >= 0.5
    }

    @Test("all configs maintain pitch")
    func allMaintainPitch() {
        let configs = [
            service.applySlowMotion(sourceFrameRate: 120, slowFactor: 0.5),
            service.applySlowMotion(sourceFrameRate: 120, slowFactor: 0.1),
            service.applySlowMotion(sourceFrameRate: 30, slowFactor: 0.5),
            service.applySlowMotion(sourceFrameRate: 30, slowFactor: 0.25),
        ]

        for config in configs {
            #expect(config.maintainPitch == true)
        }
    }
}

// MARK: - buildResult (detectHighFps) Tests

@Suite("SlowMotionService - detectHighFps via buildResult")
struct DetectHighFpsTests {

    let service = SlowMotionService.shared

    @Test("120fps is detected as high fps")
    func detect120fps() {
        let result = service.buildResult(fps: 120)

        #expect(result.isHighFps == true)
        #expect(result.sourceFrameRate == 120)
        #expect(result.maxNativeSlowMo == 4.0) // 120 / 30 = 4x
    }

    @Test("240fps is detected as high fps")
    func detect240fps() {
        let result = service.buildResult(fps: 240)

        #expect(result.isHighFps == true)
        #expect(result.sourceFrameRate == 240)
        #expect(result.maxNativeSlowMo == 8.0) // 240 / 30 = 8x
    }

    @Test("60fps is detected as high fps (at threshold)")
    func detect60fps() {
        let result = service.buildResult(fps: 60)

        #expect(result.isHighFps == true)
        #expect(result.sourceFrameRate == 60)
        #expect(result.maxNativeSlowMo == 2.0) // 60 / 30 = 2x
    }

    @Test("30fps is detected as standard fps")
    func detect30fps() {
        let result = service.buildResult(fps: 30)

        #expect(result.isHighFps == false)
        #expect(result.sourceFrameRate == 30)
        #expect(result.maxNativeSlowMo == 1.0) // No native slow-mo
    }

    @Test("24fps is detected as standard fps")
    func detect24fps() {
        let result = service.buildResult(fps: 24)

        #expect(result.isHighFps == false)
        #expect(result.sourceFrameRate == 24)
        #expect(result.maxNativeSlowMo == 1.0)
    }

    @Test("59fps is detected as standard fps (below threshold)")
    func detect59fps() {
        let result = service.buildResult(fps: 59)

        #expect(result.isHighFps == false)
        #expect(result.maxNativeSlowMo == 1.0)
    }

    // MARK: - Recommended Config

    @Test("120fps recommended config uses native slow-mo with no blend")
    func recommendedConfig120fps() {
        let result = service.buildResult(fps: 120)
        let config = result.recommendedConfig

        // halfNative = 4.0 / 2 = 2.0, clampedMultiplier = 1/2 = 0.5
        #expect(config.speedMultiplier == 0.5)
        #expect(config.blendMode == .none)
        #expect(config.maintainPitch == true)
    }

    @Test("240fps recommended config uses native slow-mo with no blend")
    func recommendedConfig240fps() {
        let result = service.buildResult(fps: 240)
        let config = result.recommendedConfig

        // halfNative = 8.0 / 2 = 4.0, clampedMultiplier = 1/4 = 0.25
        #expect(config.speedMultiplier == 0.25)
        #expect(config.blendMode == .none)
        #expect(config.maintainPitch == true)
    }

    @Test("30fps recommended config uses optical flow at 0.5x")
    func recommendedConfig30fps() {
        let result = service.buildResult(fps: 30)
        let config = result.recommendedConfig

        #expect(config.speedMultiplier == 0.5)
        #expect(config.blendMode == .opticalFlow)
        #expect(config.maintainPitch == true)
    }

    @Test("60fps recommended config")
    func recommendedConfig60fps() {
        let result = service.buildResult(fps: 60)
        let config = result.recommendedConfig

        // halfNative = 2.0 / 2 = 1.0, clampedMultiplier = 1/1 = 1.0
        #expect(config.speedMultiplier == 1.0)
        #expect(config.blendMode == .none)
        #expect(config.maintainPitch == true)
    }
}

// MARK: - Constants Tests

@Suite("SlowMotionService - Constants")
struct SlowMotionConstantsTests {

    @Test("standard output fps is 30")
    func standardOutputFps() {
        #expect(SlowMotionService.standardOutputFps == 30.0)
    }

    @Test("high fps threshold is 60")
    func highFpsThreshold() {
        #expect(SlowMotionService.highFpsThreshold == 60.0)
    }

    @Test("shared singleton is available")
    func sharedSingleton() {
        let a = SlowMotionService.shared
        let b = SlowMotionService.shared
        #expect(a === b)
    }
}
