// TransformInterpolatorTests.swift
// LiquidEditorTests
//
// Tests for TransformInterpolator: interpolation between transforms, cache hits.

import Testing
import CoreGraphics
@testable import LiquidEditor

@Suite("TransformInterpolator Tests")
@MainActor
struct TransformInterpolatorTests {

    // MARK: - Helpers

    private func makeTimeline(keyframes: [Keyframe]) -> KeyframeTimeline {
        KeyframeTimeline(
            videoDurationMicros: 10_000_000,
            keyframes: keyframes
        )
    }

    // MARK: - Basic Interpolation

    @Test("Identity transform for empty timeline")
    func emptyTimeline() {
        TransformInterpolator.invalidateCache()
        let timeline = makeTimeline(keyframes: [])
        let result = TransformInterpolator.transform(at: 500_000, timeline: timeline)
        #expect(result.isIdentity)
    }

    @Test("Returns keyframe transform when only one keyframe exists")
    func singleKeyframe() {
        TransformInterpolator.invalidateCache()
        let kf = Keyframe(
            id: "kf_1",
            timestampMicros: 1_000_000,
            transform: VideoTransform(scale: 2.0),
            interpolation: .linear
        )
        let timeline = makeTimeline(keyframes: [kf])

        // Before the keyframe
        let before = TransformInterpolator.transform(at: 0, timeline: timeline)
        #expect(before.scale == 2.0) // Returns first keyframe's transform

        // After the keyframe
        let after = TransformInterpolator.transform(at: 5_000_000, timeline: timeline)
        #expect(after.scale == 2.0) // Returns last keyframe's transform
    }

    @Test("Linear interpolation between two keyframes")
    func linearInterpolation() {
        TransformInterpolator.invalidateCache()
        let kf1 = Keyframe(
            id: "kf_1",
            timestampMicros: 0,
            transform: VideoTransform(scale: 1.0),
            interpolation: .linear
        )
        let kf2 = Keyframe(
            id: "kf_2",
            timestampMicros: 1_000_000,
            transform: VideoTransform(scale: 3.0),
            interpolation: .linear
        )
        let timeline = makeTimeline(keyframes: [kf1, kf2])

        // At midpoint (500ms)
        let mid = TransformInterpolator.transform(at: 500_000, timeline: timeline)
        #expect(abs(mid.scale - 2.0) < 0.01)

        // At 25%
        let quarter = TransformInterpolator.transform(at: 250_000, timeline: timeline)
        #expect(abs(quarter.scale - 1.5) < 0.01)

        // At 75%
        let threeQuarter = TransformInterpolator.transform(at: 750_000, timeline: timeline)
        #expect(abs(threeQuarter.scale - 2.5) < 0.01)
    }

    @Test("Hold interpolation stays at start value")
    func holdInterpolation() {
        TransformInterpolator.invalidateCache()
        let kf1 = Keyframe(
            id: "kf_1",
            timestampMicros: 0,
            transform: VideoTransform(scale: 1.0),
            interpolation: .hold
        )
        let kf2 = Keyframe(
            id: "kf_2",
            timestampMicros: 1_000_000,
            transform: VideoTransform(scale: 3.0),
            interpolation: .linear
        )
        let timeline = makeTimeline(keyframes: [kf1, kf2])

        // Hold should return 0 for all t < 1
        let mid = TransformInterpolator.transform(at: 500_000, timeline: timeline)
        #expect(abs(mid.scale - 1.0) < 0.01)
    }

    @Test("EaseIn interpolation is slower at start")
    func easeInInterpolation() {
        TransformInterpolator.invalidateCache()
        let kf1 = Keyframe(
            id: "kf_1",
            timestampMicros: 0,
            transform: VideoTransform(scale: 1.0),
            interpolation: .easeIn
        )
        let kf2 = Keyframe(
            id: "kf_2",
            timestampMicros: 1_000_000,
            transform: VideoTransform(scale: 3.0),
            interpolation: .linear
        )
        let timeline = makeTimeline(keyframes: [kf1, kf2])

        // At 50% progress, easeIn t^2 = 0.25, so scale = 1 + 2*0.25 = 1.5
        let mid = TransformInterpolator.transform(at: 500_000, timeline: timeline)
        #expect(abs(mid.scale - 1.5) < 0.01)
    }

    @Test("Translation interpolation")
    func translationInterpolation() {
        TransformInterpolator.invalidateCache()
        let kf1 = Keyframe(
            id: "kf_1",
            timestampMicros: 0,
            transform: VideoTransform(translation: CGPoint(x: 0, y: 0)),
            interpolation: .linear
        )
        let kf2 = Keyframe(
            id: "kf_2",
            timestampMicros: 1_000_000,
            transform: VideoTransform(translation: CGPoint(x: 0.5, y: -0.5)),
            interpolation: .linear
        )
        let timeline = makeTimeline(keyframes: [kf1, kf2])

        let mid = TransformInterpolator.transform(at: 500_000, timeline: timeline)
        #expect(abs(mid.translation.x - 0.25) < 0.01)
        #expect(abs(mid.translation.y - (-0.25)) < 0.01)
    }

    // MARK: - Cache Behavior

    @Test("Cache hit returns same result")
    func cacheHit() {
        TransformInterpolator.invalidateCache()
        let kf1 = Keyframe(
            id: "kf_1",
            timestampMicros: 0,
            transform: VideoTransform(scale: 1.0),
            interpolation: .linear
        )
        let kf2 = Keyframe(
            id: "kf_2",
            timestampMicros: 1_000_000,
            transform: VideoTransform(scale: 2.0),
            interpolation: .linear
        )
        let timeline = makeTimeline(keyframes: [kf1, kf2])

        let first = TransformInterpolator.transform(at: 500_000, timeline: timeline)
        let second = TransformInterpolator.transform(at: 500_000, timeline: timeline)

        #expect(first == second)
        #expect(TransformInterpolator.cacheCount > 0)
    }

    @Test("Invalidate cache clears entries")
    func invalidateCache() {
        TransformInterpolator.invalidateCache()
        let timeline = makeTimeline(keyframes: [
            Keyframe(id: "kf_1", timestampMicros: 0, transform: .identity, interpolation: .linear)
        ])

        _ = TransformInterpolator.transform(at: 0, timeline: timeline)
        #expect(TransformInterpolator.cacheCount > 0)

        TransformInterpolator.invalidateCache()
        #expect(TransformInterpolator.cacheCount == 0)
    }

    // MARK: - Interpolate Helper

    @Test("Static interpolate helper works correctly")
    func interpolateHelper() {
        let from = VideoTransform(scale: 1.0, translation: .zero, rotation: 0)
        let to = VideoTransform(scale: 2.0, translation: CGPoint(x: 0.5, y: 0.5), rotation: 1.0)

        let mid = TransformInterpolator.interpolate(from: from, to: to, progress: 0.5)
        #expect(abs(mid.scale - 1.5) < 0.01)
        #expect(abs(mid.translation.x - 0.25) < 0.01)
        #expect(abs(mid.rotation - 0.5) < 0.01)
    }
}
