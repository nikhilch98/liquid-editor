// GestureCaptureEngineTests.swift
// LiquidEditorTests
//
// Comprehensive tests for GestureCaptureEngine: gesture lifecycle,
// transform calculations, alignment snapping, keyframe creation,
// double-tap, and reset.

import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - GestureCaptureEngine Initial State Tests

@Suite("GestureCaptureEngine - Initial State")
@MainActor
struct GestureCaptureEngineInitialStateTests {

    @Test("Starts with identity transform")
    func startsWithIdentity() {
        let engine = GestureCaptureEngine()
        #expect(engine.currentTransform.isIdentity)
    }

    @Test("Starts not capturing")
    func startsNotCapturing() {
        let engine = GestureCaptureEngine()
        #expect(engine.isCapturing == false)
    }

    @Test("Starts not aligned")
    func startsNotAligned() {
        let engine = GestureCaptureEngine()
        #expect(engine.isHorizontallyAligned == false)
        #expect(engine.isVerticallyAligned == false)
        #expect(engine.isCentered == false)
    }

    @Test("Initializes with custom transform")
    func customInitialTransform() {
        let transform = VideoTransform(scale: 2.0, translation: CGPoint(x: 0.1, y: 0.2))
        let engine = GestureCaptureEngine(initialTransform: transform)

        #expect(engine.currentTransform.scale == 2.0)
        #expect(abs(engine.currentTransform.translation.x - 0.1) < 0.001)
        #expect(abs(engine.currentTransform.translation.y - 0.2) < 0.001)
    }

    @Test("Initializes with nil transform uses identity")
    func nilInitialTransform() {
        let engine = GestureCaptureEngine(initialTransform: nil)
        #expect(engine.currentTransform.isIdentity)
    }
}

// MARK: - Gesture Lifecycle Tests

@Suite("GestureCaptureEngine - Gesture Lifecycle")
@MainActor
struct GestureCaptureEngineLifecycleTests {

    @Test("gestureStarted sets isCapturing to true")
    func gestureStartedCapturing() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()
        #expect(engine.isCapturing == true)
    }

    @Test("gestureEnded sets isCapturing to false")
    func gestureEndedStopsCapturing() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()
        engine.gestureEnded()
        #expect(engine.isCapturing == false)
    }

    @Test("Full gesture lifecycle: started -> interaction -> ended")
    func fullLifecycle() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        #expect(engine.isCapturing == true)

        engine.handlePinch(1.5)
        #expect(engine.isCapturing == true)

        engine.gestureEnded()
        #expect(engine.isCapturing == false)
    }

    @Test("gestureStarted resets gesture accumulators")
    func gestureStartedResetsAccumulators() {
        let engine = GestureCaptureEngine()

        // First gesture
        engine.gestureStarted()
        engine.handlePinch(2.0)
        engine.gestureEnded()

        let scaleAfterFirst = engine.currentTransform.scale

        // Second gesture should start from the current state
        engine.gestureStarted()
        engine.handlePinch(1.0) // 1.0 means no change
        engine.gestureEnded()

        // Scale should remain the same since second gesture had no change
        #expect(abs(engine.currentTransform.scale - scaleAfterFirst) < 0.01)
    }
}

// MARK: - Pinch/Zoom Tests

@Suite("GestureCaptureEngine - Pinch/Zoom")
@MainActor
struct GestureCaptureEnginePinchTests {

    @Test("Pinch increases scale")
    func pinchIncreasesScale() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()
        engine.handlePinch(2.0)

        #expect(engine.currentTransform.scale > 1.0)
    }

    @Test("Pinch decreases scale")
    func pinchDecreasesScale() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()
        engine.handlePinch(0.5)

        #expect(engine.currentTransform.scale < 1.0)
    }

    @Test("Scale is clamped to minimum")
    func scaleClampedMin() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()
        engine.handlePinch(0.01) // Very small scale

        #expect(engine.currentTransform.scale >= GestureCaptureEngine.minScale)
    }

    @Test("Scale is clamped to maximum")
    func scaleClampedMax() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()
        engine.handlePinch(100.0) // Very large scale

        #expect(engine.currentTransform.scale <= GestureCaptureEngine.maxScale)
    }

    @Test("Pinch sets isCapturing to true")
    func pinchSetsCapturing() {
        let engine = GestureCaptureEngine()
        engine.handlePinch(1.5)
        #expect(engine.isCapturing == true)
    }

    @Test("Multiple pinch updates accumulate correctly")
    func multiplePinchUpdates() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()

        // Each handlePinch replaces the gesture scale (not accumulative within gesture)
        engine.handlePinch(2.0)
        let scaleAt2 = engine.currentTransform.scale

        engine.handlePinch(3.0)
        let scaleAt3 = engine.currentTransform.scale

        #expect(scaleAt3 > scaleAt2)
    }
}

// MARK: - Pan Tests

@Suite("GestureCaptureEngine - Pan")
@MainActor
struct GestureCaptureEnginePanTests {

    @Test("Pan updates translation when zoomed")
    func panUpdatesTranslation() {
        let engine = GestureCaptureEngine()

        // First zoom in so translation is allowed
        engine.gestureStarted()
        engine.handlePinch(2.0)
        engine.gestureEnded()

        // Now pan
        engine.gestureStarted()
        engine.handlePan(CGPoint(x: 0.1, y: 0.1))

        let tx = engine.currentTransform.translation.x
        let ty = engine.currentTransform.translation.y

        // Translation should be non-zero when zoomed
        #expect(abs(tx) > 0 || abs(ty) > 0)
    }

    @Test("Pan accumulates deltas within a gesture")
    func panAccumulatesDeltas() {
        let engine = GestureCaptureEngine()

        // Zoom in first
        engine.gestureStarted()
        engine.handlePinch(3.0)
        engine.gestureEnded()

        engine.gestureStarted()
        engine.handlePan(CGPoint(x: 0.1, y: 0.0))
        let tx1 = engine.currentTransform.translation.x

        engine.handlePan(CGPoint(x: 0.1, y: 0.0))
        let tx2 = engine.currentTransform.translation.x

        // Second pan should increase translation further
        #expect(abs(tx2) >= abs(tx1))
    }

    @Test("Pan at scale 1.0 is bounded")
    func panBoundedAtScale1() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        // At scale 1.0, translation should be restricted
        engine.handlePan(CGPoint(x: 100.0, y: 100.0))

        // At scale < 1.0, translations are zeroed. At scale = 1.0, limit = 0.
        let tx = engine.currentTransform.translation.x
        let ty = engine.currentTransform.translation.y
        #expect(abs(tx) < 0.01)
        #expect(abs(ty) < 0.01)
    }

    @Test("Pan sets isCapturing to true")
    func panSetsCapturing() {
        let engine = GestureCaptureEngine()
        engine.handlePan(CGPoint(x: 0.5, y: 0.5))
        #expect(engine.isCapturing == true)
    }
}

// MARK: - Rotation Tests

@Suite("GestureCaptureEngine - Rotation")
@MainActor
struct GestureCaptureEngineRotationTests {

    @Test("Rotation updates the transform")
    func rotationUpdatesTransform() {
        let engine = GestureCaptureEngine()
        engine.gestureStarted()
        engine.handleRotation(.pi / 4)

        #expect(abs(engine.currentTransform.rotation - .pi / 4) < 0.01)
    }

    @Test("Rotation sets isCapturing to true")
    func rotationSetsCapturing() {
        let engine = GestureCaptureEngine()
        engine.handleRotation(0.5)
        #expect(engine.isCapturing == true)
    }

    @Test("Rotation is additive to base transform")
    func rotationAdditive() {
        let engine = GestureCaptureEngine(
            initialTransform: VideoTransform(rotation: .pi / 4)
        )

        engine.gestureStarted()
        engine.handleRotation(.pi / 4)

        // Should be approximately pi/4 + pi/4 = pi/2
        #expect(abs(engine.currentTransform.rotation - .pi / 2) < 0.01)
    }
}

// MARK: - Double-Tap Tests

@Suite("GestureCaptureEngine - Double Tap")
@MainActor
struct GestureCaptureEngineDoubleTapTests {

    @Test("Double-tap at 1x zooms to 2x")
    func doubleTapZoomsIn() {
        let engine = GestureCaptureEngine()
        #expect(abs(engine.currentTransform.scale - 1.0) < 0.1)

        engine.handleDoubleTap()
        #expect(abs(engine.currentTransform.scale - GestureCaptureEngine.doubleTapZoom) < 0.01)
    }

    @Test("Double-tap when zoomed resets to identity")
    func doubleTapResetsWhenZoomed() {
        let engine = GestureCaptureEngine()

        // Zoom in first
        engine.handleDoubleTap()
        #expect(engine.currentTransform.scale > 1.0)

        // Double-tap again to reset
        engine.handleDoubleTap()
        #expect(engine.currentTransform.isIdentity)
    }

    @Test("Double-tap toggles between 1x and 2x")
    func doubleTapToggles() {
        let engine = GestureCaptureEngine()

        engine.handleDoubleTap()
        #expect(abs(engine.currentTransform.scale - 2.0) < 0.01)

        engine.handleDoubleTap()
        #expect(engine.currentTransform.isIdentity)

        engine.handleDoubleTap()
        #expect(abs(engine.currentTransform.scale - 2.0) < 0.01)
    }

    @Test("Double-tap when close to 1x zooms in")
    func doubleTapCloseToOneZoomsIn() {
        let engine = GestureCaptureEngine(
            initialTransform: VideoTransform(scale: 0.95) // Close to 1.0
        )

        engine.handleDoubleTap()
        #expect(abs(engine.currentTransform.scale - GestureCaptureEngine.doubleTapZoom) < 0.01)
    }
}

// MARK: - Alignment Snapping Tests

@Suite("GestureCaptureEngine - Alignment Snapping")
@MainActor
struct GestureCaptureEngineAlignmentTests {

    @Test("Alignment detected when translation is near zero")
    func alignmentDetected() {
        let engine = GestureCaptureEngine()

        // Zoom in, then translate to near-center
        engine.gestureStarted()
        engine.handlePinch(2.0)
        // At scale 2.0, small translation should trigger alignment
        // The gesture translation scaled by zoom should result in near-zero actual translation

        // With scale 2.0, the limit is (2.0 - 1.0)/2 = 0.5
        // A small pan should keep us within alignment threshold
        engine.handlePan(CGPoint(x: 0.001, y: 0.001))

        // Should be near-center aligned
        #expect(engine.isHorizontallyAligned == true)
        #expect(engine.isVerticallyAligned == true)
        #expect(engine.isCentered == true)
    }

    @Test("Alignment snap callback fires on edge crossing")
    func alignmentSnapCallback() {
        let engine = GestureCaptureEngine()
        var snapCount = 0
        engine.onAlignmentSnap = { snapCount += 1 }

        // Zoom in so we can pan
        engine.gestureStarted()
        engine.handlePinch(3.0)
        engine.gestureEnded()

        // Pan far enough to not be aligned
        engine.gestureStarted()
        engine.handlePan(CGPoint(x: 2.0, y: 2.0))

        // Now pan back toward center to cross alignment threshold
        engine.handlePan(CGPoint(x: -2.0, y: -2.0))

        // Snap callback should have fired
        #expect(snapCount > 0)
    }

    @Test("isCentered is true when both alignments are true")
    func isCenteredWhenBothAligned() {
        let engine = GestureCaptureEngine()

        // With identity transform at scale 1, translation is forced to 0
        // which should be within alignment threshold
        engine.gestureStarted()
        engine.handlePinch(1.5)
        // At 1.5x, limit = 0.25. Small pan keeps us aligned.
        engine.handlePan(CGPoint(x: 0.001, y: 0.001))

        if engine.isHorizontallyAligned && engine.isVerticallyAligned {
            #expect(engine.isCentered == true)
        }
    }
}

// MARK: - Keyframe Creation Tests

@Suite("GestureCaptureEngine - Keyframe Creation")
@MainActor
struct GestureCaptureEngineKeyframeTests {

    @Test("createKeyframe captures current transform")
    func keyframeCapturesTransform() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        engine.handlePinch(2.0)

        let keyframe = engine.createKeyframe(at: 1_000_000)

        #expect(abs(keyframe.transform.scale - 2.0) < 0.01)
        #expect(keyframe.timestampMicros == 1_000_000)
    }

    @Test("createKeyframe uses specified interpolation")
    func keyframeInterpolation() {
        let engine = GestureCaptureEngine()

        let keyframe = engine.createKeyframe(at: 500_000, interpolation: .linear)
        #expect(keyframe.interpolation == .linear)
    }

    @Test("createKeyframe default interpolation is easeInOut")
    func keyframeDefaultInterpolation() {
        let engine = GestureCaptureEngine()

        let keyframe = engine.createKeyframe(at: 0)
        #expect(keyframe.interpolation == .easeInOut)
    }

    @Test("createKeyframe generates unique IDs")
    func keyframeUniqueIds() {
        let engine = GestureCaptureEngine()

        let kf1 = engine.createKeyframe(at: 0)
        let kf2 = engine.createKeyframe(at: 1_000_000)

        #expect(kf1.id != kf2.id)
    }

    @Test("createKeyframe transform is clamped")
    func keyframeTransformClamped() {
        let engine = GestureCaptureEngine()

        // Set an extreme transform
        engine.setTransform(VideoTransform(
            scale: 100.0,
            translation: CGPoint(x: 50.0, y: 50.0)
        ))

        let keyframe = engine.createKeyframe(at: 0)

        // The transform in the keyframe should be clamped
        #expect(keyframe.transform.scale <= 5.0)
        #expect(keyframe.transform.translation.x <= 1.0)
        #expect(keyframe.transform.translation.y <= 1.0)
    }
}

// MARK: - Transform Control Tests

@Suite("GestureCaptureEngine - Transform Control")
@MainActor
struct GestureCaptureEngineTransformControlTests {

    @Test("setTransform updates current transform")
    func setTransformUpdates() {
        let engine = GestureCaptureEngine()

        let newTransform = VideoTransform(
            scale: 1.5,
            translation: CGPoint(x: 0.2, y: -0.1),
            rotation: .pi / 6
        )
        engine.setTransform(newTransform)

        #expect(abs(engine.currentTransform.scale - 1.5) < 0.001)
        #expect(abs(engine.currentTransform.rotation - .pi / 6) < 0.001)
    }

    @Test("setTransform resets gesture accumulators")
    func setTransformResetsAccumulators() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        engine.handlePinch(3.0)

        engine.setTransform(.identity)
        #expect(engine.currentTransform.isIdentity)

        // Starting a new gesture should use the set transform as base
        engine.gestureStarted()
        engine.handlePinch(1.0) // No change
        #expect(engine.currentTransform.isIdentity)
    }

    @Test("reset returns to identity")
    func resetToIdentity() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        engine.handlePinch(2.5)
        engine.handleRotation(1.0)
        engine.gestureEnded()

        engine.reset()

        #expect(engine.currentTransform.isIdentity)
        #expect(engine.isCapturing == false)
        #expect(engine.isHorizontallyAligned == false)
        #expect(engine.isVerticallyAligned == false)
    }

    @Test("reset clears all state")
    func resetClearsAll() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        engine.handlePinch(3.0)
        engine.handlePan(CGPoint(x: 1.0, y: 1.0))
        engine.handleRotation(2.0)

        engine.reset()

        #expect(engine.currentTransform.isIdentity)
        #expect(engine.isCapturing == false)
    }
}

// MARK: - Combined Gestures Tests

@Suite("GestureCaptureEngine - Combined Gestures")
@MainActor
struct GestureCaptureEngineCombinedTests {

    @Test("Pinch and rotation combine correctly")
    func pinchAndRotation() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        engine.handlePinch(2.0)
        engine.handleRotation(.pi / 4)

        #expect(engine.currentTransform.scale > 1.0)
        #expect(abs(engine.currentTransform.rotation) > 0)
    }

    @Test("Multiple gesture sequences accumulate")
    func multipleGestureSequences() {
        let engine = GestureCaptureEngine()

        // First gesture: zoom in
        engine.gestureStarted()
        engine.handlePinch(2.0)
        engine.gestureEnded()
        let scaleAfterFirst = engine.currentTransform.scale

        // Second gesture: zoom in more
        engine.gestureStarted()
        engine.handlePinch(1.5)
        engine.gestureEnded()
        let scaleAfterSecond = engine.currentTransform.scale

        // Second gesture should multiply on top of first
        #expect(scaleAfterSecond > scaleAfterFirst)
    }

    @Test("Gesture ended clamps the transform")
    func gestureEndedClampsTransform() {
        let engine = GestureCaptureEngine()

        engine.gestureStarted()
        engine.handlePinch(100.0) // Way beyond max
        engine.gestureEnded()

        #expect(engine.currentTransform.scale <= GestureCaptureEngine.maxScale)
    }

    @Test("Rapid gesture start/end does not crash")
    func rapidStartEnd() {
        let engine = GestureCaptureEngine()

        for _ in 0..<100 {
            engine.gestureStarted()
            engine.handlePinch(Double.random(in: 0.5...2.0))
            engine.handlePan(CGPoint(
                x: Double.random(in: -1...1),
                y: Double.random(in: -1...1)
            ))
            engine.handleRotation(Double.random(in: -Double.pi...Double.pi))
            engine.gestureEnded()
        }

        // Should be in a valid state
        #expect(engine.currentTransform.scale >= GestureCaptureEngine.minScale)
        #expect(engine.currentTransform.scale <= GestureCaptureEngine.maxScale)
        #expect(engine.isCapturing == false)
    }
}

// MARK: - Constants Tests

@Suite("GestureCaptureEngine - Constants")
@MainActor
struct GestureCaptureEngineConstantsTests {

    @Test("minScale is 0.1")
    func minScale() {
        #expect(GestureCaptureEngine.minScale == 0.1)
    }

    @Test("maxScale is 5.0")
    func maxScale() {
        #expect(GestureCaptureEngine.maxScale == 5.0)
    }

    @Test("doubleTapZoom is 2.0")
    func doubleTapZoom() {
        #expect(GestureCaptureEngine.doubleTapZoom == 2.0)
    }

    @Test("alignmentThreshold is 0.02")
    func alignmentThreshold() {
        #expect(GestureCaptureEngine.alignmentThreshold == 0.02)
    }
}
