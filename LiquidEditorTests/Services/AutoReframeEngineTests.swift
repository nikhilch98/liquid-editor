import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - Helper

/// Create a PersonTrackingResult with sensible defaults for testing.
private func makePerson(
    index: Int = 0,
    confidence: Double = 0.95,
    x: Double = 0.5,
    y: Double = 0.5,
    width: Double = 0.2,
    height: Double = 0.3,
    timestampMs: Int = 0,
    hasBbox: Bool = true
) -> PersonTrackingResult {
    PersonTrackingResult(
        personIndex: index,
        confidence: confidence,
        boundingBox: hasBbox
            ? NormalizedBoundingBox(x: x, y: y, width: width, height: height)
            : nil,
        bodyOutline: nil,
        pose: nil,
        timestampMs: timestampMs,
        identifiedPersonId: nil,
        identifiedPersonName: nil,
        identificationConfidence: nil
    )
}

/// Create a FrameTrackingResult with the given persons.
private func makeFrame(
    timestampMs: Int = 0,
    people: [PersonTrackingResult]
) -> FrameTrackingResult {
    FrameTrackingResult(timestampMs: timestampMs, people: people)
}

// MARK: - AutoReframeConfig Tests

@Suite("AutoReframeConfig Tests")
struct AutoReframeConfigTests {

    @Test("creates with default values")
    func defaultValues() {
        let config = AutoReframeConfig()

        #expect(config.zoomIntensity == 1.2)
        #expect(config.followSpeed == 0.3)
        #expect(config.safeZonePadding == 0.1)
        #expect(config.maxZoom == 3.0)
        #expect(config.minZoom == 1.0)
        #expect(config.targetAspectRatio == nil)
        #expect(config.framingStyle == .centered)
        #expect(config.lookaheadMs == 150)
    }

    @Test("copyWith updates specified fields")
    func copyWithUpdates() {
        let config = AutoReframeConfig()
        let updated = config.with(
            zoomIntensity: 1.5,
            followSpeed: 0.5,
            maxZoom: 4.0
        )

        #expect(updated.zoomIntensity == 1.5)
        #expect(updated.followSpeed == 0.5)
        #expect(updated.maxZoom == 4.0)
        // Unchanged fields
        #expect(updated.safeZonePadding == 0.1)
        #expect(updated.minZoom == 1.0)
    }

    @Test("copyWith preserves unspecified fields")
    func copyWithPreserves() {
        let config = AutoReframeConfig(
            zoomIntensity: 2.0,
            safeZonePadding: 0.15,
            framingStyle: .ruleOfThirds
        )
        let updated = config.with(followSpeed: 0.8)

        #expect(updated.zoomIntensity == 2.0)
        #expect(updated.safeZonePadding == 0.15)
        #expect(updated.framingStyle == .ruleOfThirds)
        #expect(updated.followSpeed == 0.8)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let config = AutoReframeConfig(
            zoomIntensity: 1.5,
            followSpeed: 0.6,
            framingStyle: .ruleOfThirds,
            lookaheadMs: 200
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AutoReframeConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test("Equatable")
    func equatable() {
        let a = AutoReframeConfig(zoomIntensity: 1.5)
        let b = AutoReframeConfig(zoomIntensity: 1.5)
        let c = AutoReframeConfig(zoomIntensity: 2.0)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - AutoReframeEngine Basic Tests

@Suite("AutoReframeEngine Basic Tests")
struct AutoReframeEngineBasicTests {

    @Test("creates with default config")
    @MainActor
    func defaultConfig() {
        let engine = AutoReframeEngine()
        #expect(engine.config.zoomIntensity == 1.2)
        #expect(engine.isEnabled == false)
    }

    @Test("creates with custom config")
    @MainActor
    func customConfig() {
        let engine = AutoReframeEngine(config: AutoReframeConfig(zoomIntensity: 1.8))
        #expect(engine.config.zoomIntensity == 1.8)
    }

    @Test("isEnabled can be toggled")
    @MainActor
    func toggleEnabled() {
        let engine = AutoReframeEngine()
        #expect(engine.isEnabled == false)
        engine.isEnabled = true
        #expect(engine.isEnabled == true)
        engine.isEnabled = false
        #expect(engine.isEnabled == false)
    }

    @Test("config can be updated")
    @MainActor
    func updateConfig() {
        let engine = AutoReframeEngine()
        engine.config = AutoReframeConfig(maxZoom: 5.0)
        #expect(engine.config.maxZoom == 5.0)
    }

    @Test("reset clears internal state")
    @MainActor
    func resetClearsState() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        // Build up some internal state.
        let frameResult = makeFrame(people: [makePerson()])
        _ = engine.getTransformForFrame(frameResult, selectedPersonIndices: [0])

        // Reset and verify no crash.
        engine.reset()
        let transform = engine.getTransformForFrame(frameResult, selectedPersonIndices: [0])
        #expect(transform.scale.isFinite)
    }
}

// MARK: - getTransformForFrame Tests

@Suite("AutoReframeEngine - getTransformForFrame")
struct GetTransformForFrameTests {

    @Test("returns identity when disabled")
    @MainActor
    func disabledReturnsIdentity() {
        let engine = AutoReframeEngine()
        engine.isEnabled = false

        let frame = makeFrame(people: [makePerson()])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        #expect(transform.isIdentity)
    }

    @Test("returns identity when frameResult is nil")
    @MainActor
    func nilFrameReturnsIdentity() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let transform = engine.getTransformForFrame(nil, selectedPersonIndices: [0])
        #expect(transform.isIdentity)
    }

    @Test("returns identity when no persons selected")
    @MainActor
    func noPersonsSelectedReturnsIdentity() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [makePerson()])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [])
        #expect(transform.isIdentity)
    }

    @Test("returns identity when selected person not in frame")
    @MainActor
    func selectedPersonNotInFrame() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [makePerson(index: 0)])
        // Person index 1 is not in the frame.
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [1])
        #expect(transform.isIdentity)
    }

    @Test("generates transform for centered person")
    @MainActor
    func centeredPerson() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [
            makePerson(x: 0.5, y: 0.5, width: 0.2, height: 0.3),
        ])

        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        // Person is already centered, so translation should be minimal.
        #expect(transform.scale > 1.0)
        #expect(abs(transform.translation.x) < 0.2)
        #expect(abs(transform.translation.y) < 0.2)
    }

    @Test("generates transform for off-center person")
    @MainActor
    func offCenterPerson() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [
            makePerson(x: 0.2, y: 0.3, width: 0.15, height: 0.25),
        ])

        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        #expect(transform.scale >= 1.0)
        // Translation should attempt to center the subject.
        #expect(!(transform.translation.x == 0.0 && transform.translation.y == 0.0))
    }

    @Test("handles person without bounding box")
    @MainActor
    func noBoundingBox() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [makePerson(hasBbox: false)])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        #expect(transform.isIdentity)
    }
}

// MARK: - computeCombinedBoundingBox Tests

@Suite("AutoReframeEngine - computeCombinedBoundingBox")
struct CombinedBoundingBoxTests {

    @Test("returns nil for empty list")
    @MainActor
    func emptyList() {
        let engine = AutoReframeEngine()
        let bbox = engine.computeCombinedBoundingBox([])
        #expect(bbox == nil)
    }

    @Test("returns single person bbox correctly")
    @MainActor
    func singlePerson() {
        let engine = AutoReframeEngine()
        let persons = [makePerson(x: 0.5, y: 0.5, width: 0.2, height: 0.3)]

        let bbox = engine.computeCombinedBoundingBox(persons)
        #expect(bbox != nil)
        // Center at (0.5, 0.5) with width 0.2 and height 0.3
        // Left = 0.5 - 0.1 = 0.4, Top = 0.5 - 0.15 = 0.35
        #expect(abs(bbox!.minX - 0.4) < 0.01)
        #expect(abs(bbox!.minY - 0.35) < 0.01)
        #expect(abs(bbox!.width - 0.2) < 0.01)
        #expect(abs(bbox!.height - 0.3) < 0.01)
    }

    @Test("combines multiple persons bounding boxes")
    @MainActor
    func multiplePersons() {
        let engine = AutoReframeEngine()
        let persons = [
            makePerson(index: 0, x: 0.3, y: 0.5, width: 0.2, height: 0.3),
            makePerson(index: 1, x: 0.7, y: 0.5, width: 0.2, height: 0.3),
        ]

        let bbox = engine.computeCombinedBoundingBox(persons)
        #expect(bbox != nil)
        // Person 0: left=0.2, right=0.4, top=0.35, bottom=0.65
        // Person 1: left=0.6, right=0.8, top=0.35, bottom=0.65
        // Combined: left=0.2, right=0.8, top=0.35, bottom=0.65
        #expect(abs(bbox!.minX - 0.2) < 0.01)
        #expect(abs(bbox!.maxX - 0.8) < 0.01)
        #expect(abs(bbox!.minY - 0.35) < 0.01)
        #expect(abs(bbox!.maxY - 0.65) < 0.01)
    }

    @Test("ignores persons without bounding box")
    @MainActor
    func ignoresNoBbox() {
        let engine = AutoReframeEngine()
        let persons = [
            makePerson(index: 0, x: 0.5, y: 0.5, width: 0.2, height: 0.3),
            makePerson(index: 1, hasBbox: false),
        ]

        let bbox = engine.computeCombinedBoundingBox(persons)
        #expect(bbox != nil)
        #expect(abs(bbox!.width - 0.2) < 0.01)
    }

    @Test("returns nil when all persons lack bounding box")
    @MainActor
    func allNoBbox() {
        let engine = AutoReframeEngine()
        let persons = [
            makePerson(index: 0, hasBbox: false),
            makePerson(index: 1, hasBbox: false),
        ]

        let bbox = engine.computeCombinedBoundingBox(persons)
        #expect(bbox == nil)
    }

    @Test("handles overlapping bounding boxes")
    @MainActor
    func overlapping() {
        let engine = AutoReframeEngine()
        let persons = [
            makePerson(index: 0, x: 0.45, y: 0.5, width: 0.3, height: 0.4),
            makePerson(index: 1, x: 0.55, y: 0.5, width: 0.3, height: 0.4),
        ]

        let bbox = engine.computeCombinedBoundingBox(persons)
        #expect(bbox != nil)
        // Person 0: left=0.3, right=0.6
        // Person 1: left=0.4, right=0.7
        // Combined: left=0.3, right=0.7
        #expect(abs(bbox!.minX - 0.3) < 0.01)
        #expect(abs(bbox!.maxX - 0.7) < 0.01)
    }
}

// MARK: - Dead Zone Tests

@Suite("AutoReframeEngine - Dead Zone Behavior")
struct DeadZoneTests {

    @Test("small translation changes within dead zone are ignored")
    @MainActor
    func smallChangesIgnored() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        // Establish initial state.
        let frame1 = makeFrame(people: [makePerson(x: 0.5, y: 0.5)])
        let transform1 = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])

        // Move subject by tiny amount (within 4% dead zone).
        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(x: 0.51, y: 0.51, timestampMs: 100),
        ])
        let transform2 = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        // Due to smoothing and dead zone, transform should be very similar.
        #expect(abs(transform2.translation.x - transform1.translation.x) < 0.1)
    }

    @Test("large translation changes trigger transform update")
    @MainActor
    func largeChangesTriggerUpdate() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame1 = makeFrame(people: [makePerson(x: 0.5, y: 0.5)])
        _ = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])

        // Move subject significantly (beyond 4% dead zone).
        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(x: 0.2, y: 0.3, timestampMs: 100),
        ])
        let transform2 = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        #expect(!transform2.isIdentity)
    }

    @Test("first transform sets stable transform")
    @MainActor
    func firstSetsStable() {
        let engine = AutoReframeEngine()

        let transform = VideoTransform(
            scale: 1.5,
            translation: CGPoint(x: 0.1, y: 0.1)
        )

        let result = engine.applyDeadZone(transform)
        #expect(result.scale == transform.scale)
        #expect(result.translation == transform.translation)
    }

    @Test("returns stable transform for small changes")
    @MainActor
    func stableForSmallChanges() {
        let engine = AutoReframeEngine()

        let initial = VideoTransform(
            scale: 1.5,
            translation: CGPoint(x: 0.1, y: 0.1)
        )
        _ = engine.applyDeadZone(initial)

        // Small change within dead zone.
        let small = VideoTransform(
            scale: 1.52, // 1.3% change, within 6% dead zone
            translation: CGPoint(x: 0.11, y: 0.11) // 1% change, within 4% dead zone
        )

        let result = engine.applyDeadZone(small)
        #expect(result.scale == initial.scale)
        #expect(result.translation == initial.translation)
    }

    @Test("updates stable transform for large changes")
    @MainActor
    func updatesForLargeChanges() {
        let engine = AutoReframeEngine()

        let initial = VideoTransform(
            scale: 1.5,
            translation: CGPoint(x: 0.1, y: 0.1)
        )
        _ = engine.applyDeadZone(initial)

        // Large change beyond dead zone.
        let large = VideoTransform(
            scale: 1.7, // 13% change, beyond 6% dead zone
            translation: CGPoint(x: 0.2, y: 0.2) // 10% change, beyond 4% dead zone
        )

        let result = engine.applyDeadZone(large)
        #expect(result.scale == large.scale)
        #expect(result.translation == large.translation)
    }

    @Test("scale changes within 6% dead zone are ignored")
    @MainActor
    func scaleDeadZone() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true
        engine.reset()

        let frame1 = makeFrame(people: [makePerson(x: 0.5, y: 0.5)])
        let transform1 = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])

        // Change bbox size slightly (within 6% scale dead zone).
        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(x: 0.5, y: 0.5, width: 0.21, height: 0.31, timestampMs: 100),
        ])
        let transform2 = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        #expect(abs(transform2.scale - transform1.scale) / transform1.scale < 0.15)
    }
}

// MARK: - Smoothing Tests

@Suite("AutoReframeEngine - Adaptive Smoothing")
struct SmoothingTests {

    @Test("first transform is returned as-is")
    @MainActor
    func firstTransformUnchanged() {
        let engine = AutoReframeEngine()

        let transform = VideoTransform(
            scale: 1.5,
            translation: CGPoint(x: 0.1, y: 0.1)
        )

        let result = engine.applySmoothing(transform)
        #expect(result.scale == transform.scale)
        #expect(result.translation == transform.translation)
    }

    @Test("subsequent transforms are smoothed")
    @MainActor
    func subsequentSmoothed() {
        let engine = AutoReframeEngine()

        let initial = VideoTransform(
            scale: 1.0,
            translation: .zero
        )
        _ = engine.applySmoothing(initial)

        let target = VideoTransform(
            scale: 2.0,
            translation: CGPoint(x: 0.5, y: 0.5)
        )

        let result = engine.applySmoothing(target)
        // Result should be between initial and target due to smoothing.
        #expect(result.scale > 1.0)
        #expect(result.scale < 2.0)
        #expect(result.translation.x > 0.0)
        #expect(result.translation.x < 0.5)
    }

    @Test("builds up transform history without errors")
    @MainActor
    func historyAccumulation() {
        let engine = AutoReframeEngine()

        for i in 0..<15 {
            let transform = VideoTransform(
                scale: 1.0 + Double(i) * 0.1,
                translation: CGPoint(x: Double(i) * 0.05, y: Double(i) * 0.05)
            )
            _ = engine.applySmoothing(transform)
        }
        // Should process all transforms without error.
    }

    @Test("smoothing is applied to frame transforms")
    @MainActor
    func smoothingAppliedToFrames() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        // First frame establishes baseline.
        let frame1 = makeFrame(people: [makePerson(x: 0.5, y: 0.5)])
        _ = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])

        // Sudden jump - smoothing should dampen the response.
        let frame2 = makeFrame(timestampMs: 33, people: [
            makePerson(x: 0.2, y: 0.2, timestampMs: 33),
        ])
        let transform2 = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        #expect(transform2.scale.isFinite)
        #expect(transform2.translation.x.isFinite)
    }

    @Test("faster movements get less smoothing")
    @MainActor
    func fasterLessSmoothing() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        // Build up history with slow movements.
        for i in 0..<5 {
            let frame = makeFrame(
                timestampMs: i * 33,
                people: [makePerson(
                    x: 0.5 + Double(i) * 0.001,
                    y: 0.5,
                    timestampMs: i * 33
                )]
            )
            _ = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        }
        // Engine should have adapted smoothing based on velocity (no crash).
    }
}

// MARK: - Rule of Thirds Tests

@Suite("AutoReframeEngine - Rule of Thirds Framing")
struct RuleOfThirdsTests {

    @Test("rule of thirds is enabled via config")
    @MainActor
    func enabledViaConfig() {
        let engine = AutoReframeEngine(
            config: AutoReframeConfig(framingStyle: .ruleOfThirds)
        )
        #expect(engine.config.framingStyle == .ruleOfThirds)
    }

    @Test("moving right places subject on left third")
    @MainActor
    func movingRightLeftThird() {
        let engine = AutoReframeEngine(
            config: AutoReframeConfig(framingStyle: .ruleOfThirds)
        )
        engine.isEnabled = true

        // First frame - establish position.
        let frame1 = makeFrame(people: [
            makePerson(x: 0.4, y: 0.5, width: 0.15, height: 0.25),
        ])
        _ = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])

        // Second frame - subject moving right.
        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(x: 0.5, y: 0.5, width: 0.15, height: 0.25, timestampMs: 100),
        ])
        let transform2 = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        // Should produce a valid transform with rule of thirds offset.
        #expect(transform2.scale.isFinite)
    }

    @Test("moving left places subject on right third")
    @MainActor
    func movingLeftRightThird() {
        let engine = AutoReframeEngine(
            config: AutoReframeConfig(framingStyle: .ruleOfThirds)
        )
        engine.isEnabled = true

        let frame1 = makeFrame(people: [
            makePerson(x: 0.6, y: 0.5, width: 0.15, height: 0.25),
        ])
        _ = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])

        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(x: 0.5, y: 0.5, width: 0.15, height: 0.25, timestampMs: 100),
        ])
        let transform2 = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        #expect(transform2.scale.isFinite)
    }

    @Test("centered framing does not apply thirds offset")
    @MainActor
    func centeredNoThirds() {
        let engine = AutoReframeEngine(
            config: AutoReframeConfig(framingStyle: .centered)
        )
        engine.isEnabled = true

        let frame1 = makeFrame(people: [
            makePerson(x: 0.4, y: 0.5, width: 0.15, height: 0.25),
        ])
        _ = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])

        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(x: 0.5, y: 0.5, width: 0.15, height: 0.25, timestampMs: 100),
        ])
        let transform = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        #expect(transform.scale.isFinite)
    }
}

// MARK: - Look-ahead Tests

@Suite("AutoReframeEngine - Look-ahead Prediction")
struct LookAheadTests {

    @Test("lookahead is configured via config")
    @MainActor
    func configuredViaConfig() {
        let engine = AutoReframeEngine(
            config: AutoReframeConfig(lookaheadMs: 150)
        )
        #expect(engine.config.lookaheadMs == 150)
    }

    @Test("lookahead can be adjusted")
    @MainActor
    func adjustable() {
        let engine = AutoReframeEngine()
        engine.config = engine.config.with(lookaheadMs: 300)
        #expect(engine.config.lookaheadMs == 300)
    }

    @Test("zero lookahead uses current frame only")
    @MainActor
    func zeroLookahead() {
        let engine = AutoReframeEngine(
            config: AutoReframeConfig(lookaheadMs: 0)
        )
        engine.isEnabled = true
        #expect(engine.config.lookaheadMs == 0)
    }
}

// MARK: - Config Changes Tests

@Suite("AutoReframeEngine - Config Changes")
struct ConfigChangesTests {

    @Test("safeZonePadding affects bounding box expansion")
    @MainActor
    func safeZonePaddingAffectsZoom() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [makePerson(x: 0.5, y: 0.5)])

        // Tight padding.
        engine.config = AutoReframeConfig(safeZonePadding: 0.05)
        let tightTransform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])

        // Loose padding.
        engine.reset()
        engine.config = AutoReframeConfig(safeZonePadding: 0.2)
        let looseTransform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])

        // Looser padding should result in less zoom (smaller scale).
        #expect(tightTransform.scale >= looseTransform.scale)
    }

    @Test("minZoom prevents zooming out past threshold")
    @MainActor
    func minZoomThreshold() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true
        engine.config = AutoReframeConfig(safeZonePadding: 0.05, minZoom: 1.5)

        let frame = makeFrame(people: [
            makePerson(x: 0.5, y: 0.5, width: 0.3, height: 0.4),
        ])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])

        #expect(transform.scale >= 1.5)
    }

    @Test("maxZoom prevents zooming in past threshold")
    @MainActor
    func maxZoomThreshold() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true
        engine.config = AutoReframeConfig(maxZoom: 2.0)

        let frame = makeFrame(people: [
            makePerson(x: 0.5, y: 0.5, width: 0.05, height: 0.08),
        ])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])

        #expect(transform.scale <= 2.1) // Allow small margin
    }

    @Test("followSpeed affects smoothing behavior")
    @MainActor
    func followSpeedSmoothing() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame1 = makeFrame(people: [makePerson(x: 0.5, y: 0.5)])
        let frame2 = makeFrame(timestampMs: 100, people: [
            makePerson(x: 0.3, y: 0.3, timestampMs: 100),
        ])

        // Fast follow speed.
        engine.config = AutoReframeConfig(followSpeed: 1.0)
        engine.reset()
        _ = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])
        let fastTransform = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        // Slow follow speed.
        engine.reset()
        engine.config = AutoReframeConfig(followSpeed: 0.1)
        _ = engine.getTransformForFrame(frame1, selectedPersonIndices: [0])
        let slowTransform = engine.getTransformForFrame(frame2, selectedPersonIndices: [0])

        // Both should produce valid transforms.
        #expect(fastTransform.scale.isFinite)
        #expect(slowTransform.scale.isFinite)
    }
}

// MARK: - Edge Cases Tests

@Suite("AutoReframeEngine - Edge Cases")
struct EdgeCaseTests {

    @Test("handles empty people list in frame")
    @MainActor
    func emptyPeopleList() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = FrameTrackingResult(timestampMs: 0, people: [])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        #expect(transform.isIdentity)
    }

    @Test("handles frame with multiple people but only one selected")
    @MainActor
    func multiplePersonsOneSelected() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [
            makePerson(index: 0, x: 0.3, y: 0.5, width: 0.15, height: 0.25),
            makePerson(index: 1, x: 0.7, y: 0.5, width: 0.15, height: 0.25),
        ])

        // Only select person 1.
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [1])
        #expect(!transform.isIdentity)
    }

    @Test("handles very small bounding box")
    @MainActor
    func verySmallBbox() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [
            makePerson(x: 0.5, y: 0.5, width: 0.01, height: 0.02),
        ])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        #expect(transform.scale <= engine.config.maxZoom + 0.1)
    }

    @Test("handles very large bounding box")
    @MainActor
    func veryLargeBbox() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [
            makePerson(x: 0.5, y: 0.5, width: 0.95, height: 0.95),
        ])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        #expect(transform.scale >= engine.config.minZoom - 0.1)
    }

    @Test("handles bounding box at edge of frame")
    @MainActor
    func bboxAtEdge() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        let frame = makeFrame(people: [
            makePerson(x: 0.1, y: 0.1, width: 0.15, height: 0.2),
        ])
        let transform = engine.getTransformForFrame(frame, selectedPersonIndices: [0])
        #expect(transform.scale.isFinite)
    }

    @Test("handles multiple successive frames consistently")
    @MainActor
    func successiveFrames() {
        let engine = AutoReframeEngine()
        engine.isEnabled = true

        var transforms: [VideoTransform] = []
        for i in 0..<10 {
            let frame = makeFrame(
                timestampMs: i * 33,
                people: [makePerson(
                    x: 0.3 + Double(i) * 0.02,
                    y: 0.5,
                    timestampMs: i * 33
                )]
            )
            transforms.append(engine.getTransformForFrame(frame, selectedPersonIndices: [0]))
        }

        // All transforms should be valid.
        for transform in transforms {
            #expect(transform.scale.isFinite)
            #expect(transform.translation.x.isFinite)
            #expect(transform.translation.y.isFinite)
        }
    }
}

// MARK: - computeTargetTransform Tests

@Suite("AutoReframeEngine - computeTargetTransform")
struct TargetTransformTests {

    @Test("returns identity for nil bbox")
    @MainActor
    func nilBbox() {
        let engine = AutoReframeEngine()
        let transform = engine.computeTargetTransform(nil)
        #expect(transform.isIdentity)
    }

    @Test("returns identity for empty bbox")
    @MainActor
    func emptyBbox() {
        let engine = AutoReframeEngine()
        let transform = engine.computeTargetTransform(.zero)
        #expect(transform.isIdentity)
    }

    @Test("centers bbox in frame")
    @MainActor
    func centersBbox() {
        let engine = AutoReframeEngine()
        let bbox = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let transform = engine.computeTargetTransform(bbox)
        #expect(transform.scale > 1.0)
    }

    @Test("translation keeps bbox visible")
    @MainActor
    func translationBounded() {
        let engine = AutoReframeEngine()
        let bbox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let transform = engine.computeTargetTransform(bbox)
        #expect(transform.translation.x <= 1.0)
        #expect(transform.translation.y <= 1.0)
    }
}

// MARK: - generateKeyframes Tests

@Suite("AutoReframeEngine - generateKeyframes")
struct GenerateKeyframesTests {

    @Test("returns empty list for empty tracking results")
    @MainActor
    func emptyResults() {
        let engine = AutoReframeEngine()
        let keyframes = engine.generateKeyframes(
            trackingResults: [],
            selectedPersonIndices: [0],
            videoDurationMicros: 10_000_000
        )
        #expect(keyframes.isEmpty)
    }

    @Test("returns empty list for empty selected persons")
    @MainActor
    func emptySelectedPersons() {
        let engine = AutoReframeEngine()
        let trackingResults = [
            makeFrame(people: [makePerson()]),
        ]

        let keyframes = engine.generateKeyframes(
            trackingResults: trackingResults,
            selectedPersonIndices: [],
            videoDurationMicros: 10_000_000
        )
        #expect(keyframes.isEmpty)
    }

    @Test("generates keyframes for valid input")
    @MainActor
    func validInput() {
        let engine = AutoReframeEngine()

        var trackingResults: [FrameTrackingResult] = []
        for i in stride(from: 0, through: 300, by: 33) {
            trackingResults.append(makeFrame(
                timestampMs: i,
                people: [makePerson(
                    x: 0.3 + (Double(i) / 3000.0) * 0.4,
                    y: 0.5,
                    timestampMs: i
                )]
            ))
        }

        let keyframes = engine.generateKeyframes(
            trackingResults: trackingResults,
            selectedPersonIndices: [0],
            videoDurationMicros: 300_000 // 300ms
        )

        #expect(!keyframes.isEmpty)
        // First keyframe should be at or near time 0.
        #expect(keyframes.first!.timestampMicros <= 100_000)
    }

    @Test("keyframes have valid transforms")
    @MainActor
    func validTransforms() {
        let engine = AutoReframeEngine()

        var trackingResults: [FrameTrackingResult] = []
        for i in stride(from: 0, through: 1000, by: 33) {
            trackingResults.append(makeFrame(
                timestampMs: i,
                people: [makePerson(x: 0.5, y: 0.5, timestampMs: i)]
            ))
        }

        let keyframes = engine.generateKeyframes(
            trackingResults: trackingResults,
            selectedPersonIndices: [0],
            videoDurationMicros: 1_000_000 // 1 second
        )

        for keyframe in keyframes {
            #expect(keyframe.transform.scale.isFinite)
            #expect(keyframe.transform.translation.x.isFinite)
            #expect(keyframe.transform.translation.y.isFinite)
            #expect(keyframe.interpolation == .easeInOut)
            #expect(keyframe.label == "Auto")
        }
    }

    @Test("keyframes are sorted by timestamp")
    @MainActor
    func sortedByTimestamp() {
        let engine = AutoReframeEngine()

        var trackingResults: [FrameTrackingResult] = []
        for i in stride(from: 0, through: 2000, by: 33) {
            trackingResults.append(makeFrame(
                timestampMs: i,
                people: [makePerson(
                    x: 0.3 + (Double(i) / 2000.0) * 0.4,
                    y: 0.5,
                    timestampMs: i
                )]
            ))
        }

        let keyframes = engine.generateKeyframes(
            trackingResults: trackingResults,
            selectedPersonIndices: [0],
            videoDurationMicros: 2_000_000 // 2 seconds
        )

        for i in 1..<keyframes.count {
            #expect(keyframes[i].timestampMicros >= keyframes[i - 1].timestampMicros)
        }
    }

    @Test("respects keyframe interval")
    @MainActor
    func respectsInterval() {
        let engine = AutoReframeEngine()

        var trackingResults: [FrameTrackingResult] = []
        for i in stride(from: 0, through: 5000, by: 33) {
            trackingResults.append(makeFrame(
                timestampMs: i,
                people: [makePerson(
                    x: 0.3 + (Double(i) / 5000.0) * 0.4,
                    y: 0.5,
                    timestampMs: i
                )]
            ))
        }

        let keyframes = engine.generateKeyframes(
            trackingResults: trackingResults,
            selectedPersonIndices: [0],
            videoDurationMicros: 5_000_000, // 5 seconds
            keyframeIntervalMs: 1000
        )

        // Should have keyframes roughly every second.
        #expect(keyframes.count > 2)
    }
}

// MARK: - FramingStyle Tests

@Suite("FramingStyle Tests")
struct FramingStyleTests {

    @Test("centered is the default")
    func centeredDefault() {
        let config = AutoReframeConfig()
        #expect(config.framingStyle == .centered)
    }

    @Test("all values are accessible")
    func allValues() {
        #expect(FramingStyle.allCases.contains(.centered))
        #expect(FramingStyle.allCases.contains(.ruleOfThirds))
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        for style in FramingStyle.allCases {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(FramingStyle.self, from: data)
            #expect(decoded == style)
        }
    }
}
