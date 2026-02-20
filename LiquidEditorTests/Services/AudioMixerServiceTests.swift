// AudioMixerServiceTests.swift
// LiquidEditorTests
//
// Tests for AudioMixerService: volume computation, fade linearization,
// envelope linearization, and ducking envelope generation.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Volume Computation Tests

@Suite("AudioMixerService - Volume Computation")
struct AudioMixerVolumeTests {

    @Test("Full volume when not muted with no fades or envelope")
    func fullVolumeNoEffects() {
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 1.0,
            isMuted: false,
            timeMicros: 500_000,
            clipDurationMicros: 1_000_000
        )
        #expect(volume == 1.0)
    }

    @Test("Zero volume when muted")
    func zeroWhenMuted() {
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 1.0,
            isMuted: true,
            timeMicros: 500_000,
            clipDurationMicros: 1_000_000
        )
        #expect(volume == 0.0)
    }

    @Test("Custom clip volume is preserved")
    func customClipVolume() {
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 0.5,
            isMuted: false,
            timeMicros: 500_000,
            clipDurationMicros: 1_000_000
        )
        #expect(volume == 0.5)
    }

    @Test("Volume clamped to 2.0 maximum")
    func volumeClampedMax() {
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 3.0,
            isMuted: false,
            timeMicros: 500_000,
            clipDurationMicros: 1_000_000
        )
        #expect(volume == 2.0)
    }

    @Test("Volume clamped to 0.0 minimum")
    func volumeClampedMin() {
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: -1.0,
            isMuted: false,
            timeMicros: 500_000,
            clipDurationMicros: 1_000_000
        )
        #expect(volume == 0.0)
    }

    @Test("Fade in reduces volume at start of clip")
    func fadeInReducesVolumeAtStart() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 1.0,
            isMuted: false,
            timeMicros: 0,
            clipDurationMicros: 1_000_000,
            fadeIn: fade
        )
        #expect(volume == 0.0)
    }

    @Test("Fade in at midpoint produces partial volume")
    func fadeInMidpoint() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 1.0,
            isMuted: false,
            timeMicros: 250_000,
            clipDurationMicros: 1_000_000,
            fadeIn: fade
        )
        #expect(abs(volume - 0.5) < 0.01)
    }

    @Test("Fade in has no effect after fade duration")
    func fadeInNoEffectAfterDuration() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 1.0,
            isMuted: false,
            timeMicros: 750_000,
            clipDurationMicros: 1_000_000,
            fadeIn: fade
        )
        #expect(volume == 1.0)
    }

    @Test("Fade out reduces volume at end of clip")
    func fadeOutReducesVolumeAtEnd() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 1.0,
            isMuted: false,
            timeMicros: 1_000_000,
            clipDurationMicros: 1_000_000,
            fadeOut: fade
        )
        #expect(volume < 0.01)
    }

    @Test("Volume envelope interpolation applied correctly")
    func envelopeInterpolation() {
        let envelope = VolumeEnvelope(keyframes: [
            VolumeKeyframe(id: "k1", time: 0, volume: 1.0),
            VolumeKeyframe(id: "k2", time: 1_000_000, volume: 0.5),
        ])
        let volume = AudioMixerService.computeEffectiveVolume(
            clipVolume: 1.0,
            isMuted: false,
            timeMicros: 500_000,
            clipDurationMicros: 1_000_000,
            envelope: envelope
        )
        // Midpoint of 1.0 -> 0.5 = 0.75
        #expect(abs(volume - 0.75) < 0.01)
    }
}

// MARK: - Fade Linearization Tests

@Suite("AudioMixerService - Fade Linearization")
struct AudioMixerFadeLinearizationTests {

    @Test("Linearize fade-in produces correct segment count")
    func fadeInSegmentCount() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let points = AudioMixerService.linearizeFade(
            fade: fade,
            startTimeMicros: 0,
            isFadeIn: true,
            segmentCount: 8
        )
        #expect(points.count == 9) // 0 through 8 inclusive
    }

    @Test("Linearize fade-in starts at 0 and ends at 1 for linear curve")
    func fadeInLinearStartEnd() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let points = AudioMixerService.linearizeFade(
            fade: fade,
            startTimeMicros: 0,
            isFadeIn: true,
            segmentCount: 4
        )
        #expect(abs(points.first!.volume - 0.0) < 0.001)
        #expect(abs(points.last!.volume - 1.0) < 0.001)
    }

    @Test("Linearize fade-out starts at 1 and ends at 0 for linear curve")
    func fadeOutLinearStartEnd() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let points = AudioMixerService.linearizeFade(
            fade: fade,
            startTimeMicros: 0,
            isFadeIn: false,
            segmentCount: 4
        )
        #expect(abs(points.first!.volume - 1.0) < 0.001)
        #expect(abs(points.last!.volume - 0.0) < 0.001)
    }

    @Test("Linearize fade respects start time offset")
    func fadeStartTimeOffset() {
        let fade = AudioFade(durationMicros: 500_000, curveType: .linear)
        let startTime: TimeMicros = 1_000_000
        let points = AudioMixerService.linearizeFade(
            fade: fade,
            startTimeMicros: startTime,
            isFadeIn: true,
            segmentCount: 4
        )
        #expect(points.first!.time == startTime)
        #expect(points.last!.time == startTime + fade.durationMicros)
    }
}

// MARK: - Envelope Linearization Tests

@Suite("AudioMixerService - Envelope Linearization")
struct AudioMixerEnvelopeLinearizationTests {

    @Test("Empty envelope returns empty points")
    func emptyEnvelope() {
        let points = AudioMixerService.linearizeEnvelope(envelope: .empty)
        #expect(points.isEmpty)
    }

    @Test("Single keyframe returns single point")
    func singleKeyframe() {
        let envelope = VolumeEnvelope(keyframes: [
            VolumeKeyframe(id: "k1", time: 100_000, volume: 0.8),
        ])
        let points = AudioMixerService.linearizeEnvelope(envelope: envelope)
        #expect(points.count == 1)
        #expect(points[0].time == 100_000)
        #expect(abs(points[0].volume - 0.8) < 0.001)
    }

    @Test("Two keyframes produce correct interpolation")
    func twoKeyframeInterpolation() {
        let envelope = VolumeEnvelope(keyframes: [
            VolumeKeyframe(id: "k1", time: 0, volume: 0.0),
            VolumeKeyframe(id: "k2", time: 1_000_000, volume: 1.0),
        ])
        let points = AudioMixerService.linearizeEnvelope(
            envelope: envelope,
            segmentsPerSpan: 4
        )
        // 5 points: 0, 0.25, 0.5, 0.75, 1.0
        #expect(points.count == 5)
        #expect(abs(points[0].volume - 0.0) < 0.001)
        #expect(abs(points[2].volume - 0.5) < 0.001)
        #expect(abs(points[4].volume - 1.0) < 0.001)
    }

    @Test("Volume clamped to valid range in linearization")
    func volumeClampedInLinearization() {
        let envelope = VolumeEnvelope(keyframes: [
            VolumeKeyframe(id: "k1", time: 0, volume: 0.0),
            VolumeKeyframe(id: "k2", time: 1_000_000, volume: 1.0),
        ])
        let points = AudioMixerService.linearizeEnvelope(envelope: envelope)
        for point in points {
            #expect(point.volume >= 0.0)
            #expect(point.volume <= 2.0)
        }
    }
}

// MARK: - Ducking Tests

@Suite("AudioMixerService - Ducking")
struct AudioMixerDuckingTests {

    @Test("Empty speech segments produce empty envelope")
    func emptySpeechSegments() {
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover"
        )
        let envelope = AudioMixerService.generateDuckingEnvelope(
            speechSegments: [],
            config: config
        )
        #expect(envelope.keyframes.isEmpty)
    }

    @Test("Disabled config produces empty envelope")
    func disabledConfig() {
        let config = AudioDuckingConfig(
            isEnabled: false,
            targetTrackId: "music",
            triggerTrackId: "voiceover"
        )
        let envelope = AudioMixerService.generateDuckingEnvelope(
            speechSegments: [SpeechSegment(start: 1_000_000, end: 2_000_000)],
            config: config
        )
        #expect(envelope.keyframes.isEmpty)
    }

    @Test("Single speech segment produces 4 keyframes")
    func singleSpeechSegment() {
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover",
            duckAmountDB: -12.0,
            attackMs: 200,
            releaseMs: 500
        )
        let envelope = AudioMixerService.generateDuckingEnvelope(
            speechSegments: [SpeechSegment(start: 1_000_000, end: 2_000_000)],
            config: config
        )
        // Each segment produces 4 keyframes: ramp down start, speech start, speech end, ramp up end
        #expect(envelope.keyframes.count == 4)
    }

    @Test("Multiple speech segments produce correct keyframe count")
    func multipleSpeechSegments() {
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover"
        )
        let segments = [
            SpeechSegment(start: 1_000_000, end: 2_000_000),
            SpeechSegment(start: 4_000_000, end: 5_000_000),
            SpeechSegment(start: 7_000_000, end: 8_000_000),
        ]
        let envelope = AudioMixerService.generateDuckingEnvelope(
            speechSegments: segments,
            config: config
        )
        #expect(envelope.keyframes.count == 12) // 3 segments * 4 keyframes
    }

    @Test("Ducking keyframes have correct volume levels")
    func duckingVolumeLevels() {
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover",
            duckAmountDB: -12.0
        )
        let envelope = AudioMixerService.generateDuckingEnvelope(
            speechSegments: [SpeechSegment(start: 1_000_000, end: 2_000_000)],
            config: config
        )
        let duckVolume = pow(10.0, -12.0 / 20.0)

        // First keyframe: full volume (before ramp)
        #expect(abs(envelope.keyframes[0].volume - 1.0) < 0.001)
        // Second keyframe: ducked volume (at speech start)
        #expect(abs(envelope.keyframes[1].volume - duckVolume) < 0.001)
        // Third keyframe: ducked volume (at speech end)
        #expect(abs(envelope.keyframes[2].volume - duckVolume) < 0.001)
        // Fourth keyframe: full volume (after ramp)
        #expect(abs(envelope.keyframes[3].volume - 1.0) < 0.001)
    }

    @Test("Ramp down start respects attack time")
    func rampDownRespectsAttack() {
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover",
            attackMs: 200
        )
        let speechStart: TimeMicros = 1_000_000
        let envelope = AudioMixerService.generateDuckingEnvelope(
            speechSegments: [SpeechSegment(start: speechStart, end: 2_000_000)],
            config: config
        )
        let expectedRampStart = speechStart - 200 * 1000
        #expect(envelope.keyframes[0].time == expectedRampStart)
    }

    @Test("Ramp up end respects release time")
    func rampUpRespectsRelease() {
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover",
            releaseMs: 500
        )
        let speechEnd: TimeMicros = 2_000_000
        let envelope = AudioMixerService.generateDuckingEnvelope(
            speechSegments: [SpeechSegment(start: 1_000_000, end: speechEnd)],
            config: config
        )
        let expectedRampEnd = speechEnd + 500 * 1000
        #expect(envelope.keyframes[3].time == expectedRampEnd)
    }
}

// MARK: - Ducking Configuration Tests

@Suite("AudioMixerService - Ducking Configuration")
struct AudioMixerDuckingConfigTests {

    @Test("Configure ducking sets config")
    @MainActor
    func configureDucking() {
        let service = AudioMixerService()
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover"
        )
        service.configureDucking(config)
        #expect(service.duckingConfig != nil)
        #expect(service.isDuckingActive == true)
    }

    @Test("Disable ducking sets isEnabled to false")
    @MainActor
    func disableDucking() {
        let service = AudioMixerService()
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover"
        )
        service.configureDucking(config)
        service.disableDucking()
        #expect(service.duckingConfig != nil)
        #expect(service.isDuckingActive == false)
    }

    @Test("Clear ducking removes config entirely")
    @MainActor
    func clearDucking() {
        let service = AudioMixerService()
        let config = AudioDuckingConfig(
            targetTrackId: "music",
            triggerTrackId: "voiceover"
        )
        service.configureDucking(config)
        service.clearDucking()
        #expect(service.duckingConfig == nil)
        #expect(service.isDuckingActive == false)
    }
}
