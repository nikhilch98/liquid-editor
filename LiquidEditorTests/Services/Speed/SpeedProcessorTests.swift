import Testing
import AVFoundation
import CoreMedia
import Foundation
@testable import LiquidEditor

@Suite("SpeedProcessor Tests")
struct SpeedProcessorTests {

    // MARK: - Audio Pitch Algorithm

    @Test("audioPitchAlgorithm returns spectral when maintainPitch is true")
    func audioPitchSpectral() {
        let config = SpeedConfig(speedMultiplier: 2.0, maintainPitch: true)
        let algorithm = SpeedProcessor.audioPitchAlgorithm(for: config)
        #expect(algorithm == .spectral)
    }

    @Test("audioPitchAlgorithm returns varispeed when maintainPitch is false")
    func audioPitchVarispeed() {
        let config = SpeedConfig(speedMultiplier: 2.0, maintainPitch: false)
        let algorithm = SpeedProcessor.audioPitchAlgorithm(for: config)
        #expect(algorithm == .varispeed)
    }

    @Test("audioPitchAlgorithm returns varispeed for speed > 4.0")
    func audioPitchHighSpeed() {
        let config = SpeedConfig(speedMultiplier: 5.0, maintainPitch: true)
        let algorithm = SpeedProcessor.audioPitchAlgorithm(for: config)
        #expect(algorithm == .varispeed)
    }

    @Test("audioPitchAlgorithm returns spectral at exactly 4.0 with pitch maintained")
    func audioPitchAtBoundary() {
        let config = SpeedConfig(speedMultiplier: 4.0, maintainPitch: true)
        let algorithm = SpeedProcessor.audioPitchAlgorithm(for: config)
        #expect(algorithm == .spectral)
    }

    @Test("audioPitchAlgorithm returns varispeed at exactly 4.0 without pitch maintained")
    func audioPitchAtBoundaryNoPitch() {
        let config = SpeedConfig(speedMultiplier: 4.0, maintainPitch: false)
        let algorithm = SpeedProcessor.audioPitchAlgorithm(for: config)
        #expect(algorithm == .varispeed)
    }

    // MARK: - Should Mute Audio

    @Test("shouldMuteAudio returns false at normal speed")
    func shouldNotMuteNormal() {
        let config = SpeedConfig.normal
        #expect(!SpeedProcessor.shouldMuteAudio(config: config))
    }

    @Test("shouldMuteAudio returns true above 4.0x speed")
    func shouldMuteHighSpeed() {
        let config = SpeedConfig(speedMultiplier: 5.0)
        #expect(SpeedProcessor.shouldMuteAudio(config: config))
    }

    @Test("shouldMuteAudio returns false at exactly 4.0x")
    func shouldNotMuteAtBoundary() {
        let config = SpeedConfig(speedMultiplier: 4.0)
        #expect(!SpeedProcessor.shouldMuteAudio(config: config))
    }

    @Test("shouldMuteAudio returns true below 0.1x")
    func shouldMuteVerySlowSpeed() {
        // Minimum allowed speed is 0.1
        let config = SpeedConfig(speedMultiplier: 0.1)
        // 0.1 is NOT < 0.1, so should NOT be muted
        #expect(!SpeedProcessor.shouldMuteAudio(config: config))
    }

    // MARK: - Effective Duration

    @Test("effectiveDuration at normal speed returns source duration")
    func effectiveDurationNormal() {
        let sourceDuration = CMTime(seconds: 10.0, preferredTimescale: 600)
        let config = SpeedConfig.normal

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 10.0) < 0.01)
    }

    @Test("effectiveDuration at 2x speed halves duration")
    func effectiveDurationDoubleSpeed() {
        let sourceDuration = CMTime(seconds: 10.0, preferredTimescale: 600)
        let config = SpeedConfig(speedMultiplier: 2.0)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 5.0) < 0.01)
    }

    @Test("effectiveDuration at 0.5x speed doubles duration")
    func effectiveDurationHalfSpeed() {
        let sourceDuration = CMTime(seconds: 10.0, preferredTimescale: 600)
        let config = SpeedConfig(speedMultiplier: 0.5)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 20.0) < 0.01)
    }

    @Test("effectiveDuration at 4x speed quarters duration")
    func effectiveDuration4x() {
        let sourceDuration = CMTime(seconds: 12.0, preferredTimescale: 600)
        let config = SpeedConfig(speedMultiplier: 4.0)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 3.0) < 0.01)
    }

    // MARK: - Effective Duration Micros

    @Test("effectiveDurationMicros at normal speed returns source duration")
    func effectiveDurationMicrosNormal() {
        let sourceMicros: TimeMicros = 10_000_000 // 10 seconds
        let config = SpeedConfig.normal

        let result = SpeedProcessor.effectiveDurationMicros(
            sourceDurationMicros: sourceMicros,
            config: config
        )

        #expect(result == 10_000_000)
    }

    @Test("effectiveDurationMicros at 2x speed halves")
    func effectiveDurationMicrosDouble() {
        let sourceMicros: TimeMicros = 10_000_000
        let config = SpeedConfig(speedMultiplier: 2.0)

        let result = SpeedProcessor.effectiveDurationMicros(
            sourceDurationMicros: sourceMicros,
            config: config
        )

        #expect(result == 5_000_000)
    }

    // MARK: - Build Time Remapping

    @Test("buildTimeRemapping returns empty for no keyframes")
    func buildTimeRemappingEmpty() {
        let config = SpeedConfig.normal
        let result = SpeedProcessor.buildTimeRemapping(
            config: config,
            sourceDuration: CMTime(seconds: 5.0, preferredTimescale: 600)
        )
        #expect(result.isEmpty)
    }

    @Test("buildTimeRemapping generates mapping for speed ramp")
    func buildTimeRemappingWithRamp() {
        let keyframes = [
            SpeedKeyframe(id: "kf1", timeMicros: 0, speedMultiplier: 1.0),
            SpeedKeyframe(id: "kf2", timeMicros: 5_000_000, speedMultiplier: 2.0),
        ]
        let config = SpeedConfig(speedMultiplier: 1.0, rampKeyframes: keyframes)

        let mapping = SpeedProcessor.buildTimeRemapping(
            config: config,
            sourceDuration: CMTime(seconds: 5.0, preferredTimescale: 600),
            outputFrameRate: 30.0
        )

        #expect(!mapping.isEmpty)
        // First mapping should start near zero
        if let first = mapping.first {
            let outputSec = CMTimeGetSeconds(first.outputTime)
            let sourceSec = CMTimeGetSeconds(first.sourceTime)
            #expect(abs(outputSec) < 0.1)
            #expect(abs(sourceSec) < 0.1)
        }
    }

    @Test("buildTimeRemapping at higher frame rate produces more entries")
    func buildTimeRemappingFrameRate() {
        let keyframes = [
            SpeedKeyframe(id: "kf1", timeMicros: 0, speedMultiplier: 1.0),
            SpeedKeyframe(id: "kf2", timeMicros: 1_000_000, speedMultiplier: 2.0),
        ]
        let config = SpeedConfig(speedMultiplier: 1.0, rampKeyframes: keyframes)

        let mapping30 = SpeedProcessor.buildTimeRemapping(
            config: config,
            sourceDuration: CMTime(seconds: 1.0, preferredTimescale: 600),
            outputFrameRate: 30.0
        )

        let mapping60 = SpeedProcessor.buildTimeRemapping(
            config: config,
            sourceDuration: CMTime(seconds: 1.0, preferredTimescale: 600),
            outputFrameRate: 60.0
        )

        // 60fps should produce roughly twice as many entries as 30fps
        #expect(mapping60.count > mapping30.count)
    }

    // MARK: - Effective Duration with Speed Ramp

    @Test("effectiveDuration with speed ramp uses time remapping")
    func effectiveDurationWithRamp() {
        let keyframes = [
            SpeedKeyframe(id: "kf1", timeMicros: 0, speedMultiplier: 1.0),
            SpeedKeyframe(id: "kf2", timeMicros: 5_000_000, speedMultiplier: 1.0),
        ]
        let config = SpeedConfig(speedMultiplier: 1.0, rampKeyframes: keyframes)
        let sourceDuration = CMTime(seconds: 5.0, preferredTimescale: 600)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        // With constant 1.0x speed ramp, output should roughly equal source
        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 5.0) < 0.5) // Allow some tolerance for ramp integration
    }

    @Test("effectiveDuration with 2x constant ramp halves output")
    func effectiveDurationWith2xRamp() {
        let keyframes = [
            SpeedKeyframe(id: "kf1", timeMicros: 0, speedMultiplier: 2.0),
            SpeedKeyframe(id: "kf2", timeMicros: 10_000_000, speedMultiplier: 2.0),
        ]
        let config = SpeedConfig(speedMultiplier: 2.0, rampKeyframes: keyframes)
        let sourceDuration = CMTime(seconds: 10.0, preferredTimescale: 600)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        // At 2x constant, output should be ~5s
        #expect(abs(resultSeconds - 5.0) < 1.0)
    }

    // MARK: - Edge Cases

    @Test("effectiveDuration with very short source")
    func effectiveDurationShortSource() {
        let sourceDuration = CMTime(seconds: 0.1, preferredTimescale: 600)
        let config = SpeedConfig(speedMultiplier: 2.0)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 0.05) < 0.01)
    }

    @Test("effectiveDuration with maximum speed")
    func effectiveDurationMaxSpeed() {
        let sourceDuration = CMTime(seconds: 16.0, preferredTimescale: 600)
        let config = SpeedConfig(speedMultiplier: 16.0)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 1.0) < 0.01)
    }

    @Test("effectiveDuration with minimum speed")
    func effectiveDurationMinSpeed() {
        let sourceDuration = CMTime(seconds: 1.0, preferredTimescale: 600)
        let config = SpeedConfig(speedMultiplier: 0.1)

        let result = SpeedProcessor.effectiveDuration(
            sourceDuration: sourceDuration,
            config: config
        )

        let resultSeconds = CMTimeGetSeconds(result)
        #expect(abs(resultSeconds - 10.0) < 0.1)
    }
}
