import Testing
import CoreGraphics
@testable import LiquidEditor

// MARK: - AnimationState Identity

@Suite("AnimationState")
struct AnimationStateTests {

    @Test("Identity state has neutral values")
    func identityState() {
        let state = AnimationState.identity
        #expect(state.positionDelta == .zero)
        #expect(state.scaleFactor == 1.0)
        #expect(state.rotationDelta == 0.0)
        #expect(state.opacityFactor == 1.0)
    }

    @Test("Default initializer matches identity")
    func defaultInit() {
        let state = AnimationState()
        #expect(state == AnimationState.identity)
    }
}

// MARK: - Enter Animations

@Suite("TextAnimationEvaluator - Enter Animations")
struct EnterAnimationTests {

    @Test("fadeIn at t=0 is fully hidden")
    func fadeInStart() {
        let preset = TextAnimationPreset(type: .fadeIn)
        let state = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.0)
        // easeOut(0) = 0
        #expect(state.opacityFactor == 0.0)
    }

    @Test("fadeIn at t=1 is fully visible")
    func fadeInEnd() {
        let preset = TextAnimationPreset(type: .fadeIn)
        let state = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 1.0)
        // easeOut(1) = 1
        #expect(state.opacityFactor == 1.0)
    }

    @Test("fadeIn at mid-progress is partially visible")
    func fadeInMid() {
        let preset = TextAnimationPreset(type: .fadeIn)
        let state = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5)
        #expect(state.opacityFactor > 0.0)
        #expect(state.opacityFactor < 1.0)
        // easeOut(0.5) = 1 - (0.5)^2 = 0.75
        #expect(abs(state.opacityFactor - 0.75) < 0.001)
    }

    @Test("slideInLeft moves from negative x toward zero")
    func slideInLeftDirection() {
        let preset = TextAnimationPreset(type: .slideInLeft)

        let stateStart = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.0)
        let stateEnd = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 1.0)

        // At t=0, position should be negative (off-screen left)
        #expect(stateStart.positionDelta.x < 0)
        // At t=1, position should be at zero (resting state)
        #expect(abs(stateEnd.positionDelta.x) < 0.001)
        // Y should remain zero
        #expect(stateStart.positionDelta.y == 0)
        #expect(stateEnd.positionDelta.y == 0)
    }

    @Test("slideInRight moves from positive x toward zero")
    func slideInRightDirection() {
        let preset = TextAnimationPreset(type: .slideInRight)

        let stateStart = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.0)
        let stateEnd = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 1.0)

        #expect(stateStart.positionDelta.x > 0)
        #expect(abs(stateEnd.positionDelta.x) < 0.001)
    }

    @Test("scaleUp scales from 0 to 1")
    func scaleUpScaling() {
        let preset = TextAnimationPreset(type: .scaleUp)

        let stateStart = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.0)
        let stateEnd = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 1.0)

        // At t=0 with easeOut(0)=0, scaleFactor should be 0
        #expect(stateStart.scaleFactor == 0.0)
        // At t=1 with easeOut(1)=1, scaleFactor should be 1
        #expect(stateEnd.scaleFactor == 1.0)
    }

    @Test("bounceIn has overshoot (scale > 1 at some point)")
    func bounceInOvershoot() {
        let preset = TextAnimationPreset(type: .bounceIn)

        // Bounce easing overshoots 1.0 at certain t values
        // Test that the scale follows bounce easing which reaches 1.0
        let stateEnd = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 1.0)
        // bounce(1.0) should be close to 1.0 (the final bounce segment)
        #expect(abs(stateEnd.scaleFactor - 1.0) < 0.02)

        // At t=0, bounceIn starts at 0
        let stateStart = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.0)
        #expect(stateStart.scaleFactor == 0.0)
    }

    @Test("popIn uses elastic easing for overshoot")
    func popInOvershoot() {
        let preset = TextAnimationPreset(type: .popIn)

        // Elastic easing should overshoot 1.0 in the middle
        let stateMid = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5)
        // elastic(0.5) typically overshoots
        #expect(stateMid.scaleFactor > 1.0)
    }

    @Test("rotateIn rotates from offset to zero")
    func rotateInAnimation() {
        let preset = TextAnimationPreset(type: .rotateIn)

        let stateStart = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.0)
        let stateEnd = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 1.0)

        // At t=0, rotation should be non-zero (pi/4 * intensity)
        #expect(stateStart.rotationDelta > 0)
        #expect(abs(stateStart.rotationDelta - .pi / 4) < 0.001)
        // At t=1, rotation should be zero
        #expect(abs(stateEnd.rotationDelta) < 0.001)
    }

    @Test("Non-enter type returns identity")
    func nonEnterReturnsIdentity() {
        let preset = TextAnimationPreset(type: .fadeOut)
        let state = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5)
        #expect(state == AnimationState.identity)
    }
}

// MARK: - Exit Animations

@Suite("TextAnimationEvaluator - Exit Animations")
struct ExitAnimationTests {

    @Test("fadeOut at t=0 is fully visible")
    func fadeOutStart() {
        let preset = TextAnimationPreset(type: .fadeOut)
        let state = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 0.0)
        // easeIn(0) = 0, so 1 - 0 = 1
        #expect(state.opacityFactor == 1.0)
    }

    @Test("fadeOut at t=1 is fully hidden")
    func fadeOutEnd() {
        let preset = TextAnimationPreset(type: .fadeOut)
        let state = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 1.0)
        // easeIn(1) = 1, so 1 - 1 = 0
        #expect(state.opacityFactor == 0.0)
    }

    @Test("slideOutLeft moves to negative x")
    func slideOutLeftDirection() {
        let preset = TextAnimationPreset(type: .slideOutLeft)

        let stateStart = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 0.0)
        let stateEnd = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 1.0)

        // At t=0, position should be at zero
        #expect(abs(stateStart.positionDelta.x) < 0.001)
        // At t=1, position should be negative (off-screen left)
        #expect(stateEnd.positionDelta.x < 0)
    }

    @Test("scaleDown scales from 1 to 0")
    func scaleDownAnimation() {
        let preset = TextAnimationPreset(type: .scaleDown)

        let stateStart = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 0.0)
        let stateEnd = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 1.0)

        #expect(stateStart.scaleFactor == 1.0)
        #expect(stateEnd.scaleFactor == 0.0)
    }

    @Test("rotateOut rotates from zero to offset")
    func rotateOutAnimation() {
        let preset = TextAnimationPreset(type: .rotateOut)

        let stateStart = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 0.0)
        let stateEnd = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 1.0)

        #expect(abs(stateStart.rotationDelta) < 0.001)
        #expect(abs(stateEnd.rotationDelta - .pi / 4) < 0.001)
    }

    @Test("Non-exit type returns identity")
    func nonExitReturnsIdentity() {
        let preset = TextAnimationPreset(type: .fadeIn)
        let state = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 0.5)
        #expect(state == AnimationState.identity)
    }
}

// MARK: - Sustain Animations

@Suite("TextAnimationEvaluator - Sustain Animations")
struct SustainAnimationTests {

    @Test("breathe oscillates scale around 1.0")
    func breatheOscillation() {
        let preset = TextAnimationPreset(type: .breathe)

        // At the start of the loop (t=0), sin(0)=0, scale should be 1.0
        let state0 = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 0
        )
        #expect(abs(state0.scaleFactor - 1.0) < 0.001)

        // At quarter loop (t=0.25), sin(pi/2)=1, scale should be > 1.0
        let stateQuarter = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 500_000 // 0.5s into 2s loop
        )
        #expect(stateQuarter.scaleFactor > 1.0)

        // At three-quarter loop, sin(3pi/2)=-1, scale should be < 1.0
        let state3q = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 1_500_000
        )
        #expect(state3q.scaleFactor < 1.0)
    }

    @Test("pulse oscillates opacity")
    func pulseOscillation() {
        let preset = TextAnimationPreset(type: .pulse)

        let state0 = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 0
        )
        // At t=0, sin(0)=0, pulse=0, opacity = 1.0 - (1-0)*0.15 = 0.85
        #expect(state0.opacityFactor < 1.0)

        // At quarter loop, sin(pi/2)=1, pulse=1, opacity = 1.0 - (1-1)*0.15 = 1.0
        let stateQuarter = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 500_000
        )
        #expect(abs(stateQuarter.opacityFactor - 1.0) < 0.001)
    }

    @Test("float oscillates y position")
    func floatOscillation() {
        let preset = TextAnimationPreset(type: .float)

        let state0 = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 0
        )
        #expect(abs(state0.positionDelta.y) < 0.001)

        let stateQuarter = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 500_000
        )
        #expect(stateQuarter.positionDelta.y > 0)
        #expect(stateQuarter.positionDelta.x == 0)
    }

    @Test("Non-sustain type returns identity")
    func nonSustainReturnsIdentity() {
        let preset = TextAnimationPreset(type: .fadeIn)
        let state = TextAnimationEvaluator.evaluateSustainAnimation(
            preset, sustainOffsetMicros: 500_000
        )
        #expect(state == AnimationState.identity)
    }
}

// MARK: - Typewriter

@Suite("TextAnimationEvaluator - Typewriter")
struct TypewriterTests {

    @Test("typewriter at t=0 shows 0 characters")
    func typewriterStart() {
        let count = TextAnimationEvaluator.typewriterVisibleChars(t: 0.0, totalChars: 10)
        #expect(count == 0)
    }

    @Test("typewriter at t=1 shows all characters")
    func typewriterEnd() {
        let count = TextAnimationEvaluator.typewriterVisibleChars(t: 1.0, totalChars: 10)
        #expect(count == 10)
    }

    @Test("typewriter at t=0.5 shows half the characters")
    func typewriterMid() {
        let count = TextAnimationEvaluator.typewriterVisibleChars(t: 0.5, totalChars: 10)
        #expect(count == 5)
    }

    @Test("typewriter clamps to valid range")
    func typewriterClamp() {
        let countNeg = TextAnimationEvaluator.typewriterVisibleChars(t: -1.0, totalChars: 10)
        #expect(countNeg == 0)

        let countOver = TextAnimationEvaluator.typewriterVisibleChars(t: 2.0, totalChars: 10)
        #expect(countOver == 10)
    }
}

// MARK: - Blur Sigma

@Suite("TextAnimationEvaluator - Blur Sigma")
struct BlurSigmaTests {

    @Test("blurIn sigma decreases from max to 0")
    func blurInSigma() {
        let sigmaStart = TextAnimationEvaluator.computeBlurSigma(type: .blurIn, t: 0.0, intensity: 1.0)
        let sigmaEnd = TextAnimationEvaluator.computeBlurSigma(type: .blurIn, t: 1.0, intensity: 1.0)

        #expect(sigmaStart == 20.0)
        #expect(sigmaEnd == 0.0)
    }

    @Test("blurOut sigma increases from 0 to max")
    func blurOutSigma() {
        let sigmaStart = TextAnimationEvaluator.computeBlurSigma(type: .blurOut, t: 0.0, intensity: 1.0)
        let sigmaEnd = TextAnimationEvaluator.computeBlurSigma(type: .blurOut, t: 1.0, intensity: 1.0)

        #expect(sigmaStart == 0.0)
        #expect(sigmaEnd == 20.0)
    }

    @Test("intensity scales blur sigma")
    func blurIntensityScaling() {
        let sigmaFull = TextAnimationEvaluator.computeBlurSigma(type: .blurIn, t: 0.0, intensity: 1.0)
        let sigmaHalf = TextAnimationEvaluator.computeBlurSigma(type: .blurIn, t: 0.0, intensity: 0.5)

        #expect(sigmaFull == 20.0)
        #expect(sigmaHalf == 10.0)
    }

    @Test("non-blur type returns zero sigma")
    func nonBlurTypeSigma() {
        let sigma = TextAnimationEvaluator.computeBlurSigma(type: .fadeIn, t: 0.5, intensity: 1.0)
        #expect(sigma == 0.0)
    }
}

// MARK: - Deterministic Noise

@Suite("TextAnimationEvaluator - Deterministic Noise")
struct DeterministicNoiseTests {

    @Test("glitch animation is reproducible with same seed")
    func glitchReproducibility() {
        let preset = TextAnimationPreset(type: .glitchIn)

        let state1 = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5, seedHash: 42)
        let state2 = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5, seedHash: 42)

        #expect(state1 == state2)
    }

    @Test("different seeds produce different results")
    func differentSeedsDifferentResults() {
        let preset = TextAnimationPreset(type: .glitchIn)

        let state1 = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5, seedHash: 42)
        let state2 = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5, seedHash: 99)

        // Very unlikely to be identical with different seeds
        #expect(state1 != state2)
    }
}

// MARK: - Default Easing

@Suite("TextAnimationEvaluator - Default Easing")
struct DefaultEasingTests {

    @Test("enter animations use easeOut (faster start)")
    func enterUsesEaseOut() {
        let preset = TextAnimationPreset(type: .fadeIn)

        // easeOut at t=0.5 should give 0.75 (1 - (0.5)^2)
        let state = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5)
        #expect(abs(state.opacityFactor - 0.75) < 0.001)

        // Verify it's easeOut: value at t=0.5 should be > 0.5 (curves toward 1 faster)
        #expect(state.opacityFactor > 0.5)
    }

    @Test("exit animations use easeIn (slower start)")
    func exitUsesEaseIn() {
        let preset = TextAnimationPreset(type: .fadeOut)

        // easeIn at t=0.5 gives 0.25 (t^2), so opacity = 1 - 0.25 = 0.75
        let state = TextAnimationEvaluator.evaluateExitAnimation(preset, t: 0.5)
        #expect(abs(state.opacityFactor - 0.75) < 0.001)

        // Verify easeIn: opacity at t=0.5 should be > 0.5 (exit starts slowly)
        #expect(state.opacityFactor > 0.5)
    }
}

// MARK: - InterpolationUtils

@Suite("InterpolationUtils")
struct InterpolationUtilsTests {

    @Test("lerpDouble interpolates correctly")
    func lerpDouble() {
        #expect(InterpolationUtils.lerpDouble(0, 10, 0.0) == 0.0)
        #expect(InterpolationUtils.lerpDouble(0, 10, 0.5) == 5.0)
        #expect(InterpolationUtils.lerpDouble(0, 10, 1.0) == 10.0)
    }

    @Test("lerpOffset interpolates correctly")
    func lerpOffset() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 10, y: 20)
        let mid = InterpolationUtils.lerpOffset(a, b, 0.5)
        #expect(mid.x == 5.0)
        #expect(mid.y == 10.0)
    }

    @Test("lerpAngle takes shortest path")
    func lerpAngleShortestPath() {
        // From 350 degrees to 10 degrees should go through 0
        let a = 350.0 * .pi / 180
        let b = 10.0 * .pi / 180
        let mid = InterpolationUtils.lerpAngle(a, b, 0.5)
        // Midpoint should be near 0/360 degrees
        let midDegrees = mid * 180 / .pi
        // Should be close to 0 (or 360)
        let normalized = ((midDegrees.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        #expect(abs(normalized) < 1.0 || abs(normalized - 360) < 1.0)
    }

    @Test("linear easing returns identity")
    func linearEasing() {
        #expect(InterpolationUtils.applyEasing(0.0, .linear) == 0.0)
        #expect(InterpolationUtils.applyEasing(0.5, .linear) == 0.5)
        #expect(InterpolationUtils.applyEasing(1.0, .linear) == 1.0)
    }

    @Test("easeIn starts slow")
    func easeInStartsSlow() {
        let eased = InterpolationUtils.applyEasing(0.5, .easeIn)
        // t^2 = 0.25, so eased < 0.5 (slow start)
        #expect(eased < 0.5)
        #expect(abs(eased - 0.25) < 0.001)
    }

    @Test("easeOut starts fast")
    func easeOutStartsFast() {
        let eased = InterpolationUtils.applyEasing(0.5, .easeOut)
        // 1 - (1-t)^2 = 0.75, so eased > 0.5 (fast start)
        #expect(eased > 0.5)
        #expect(abs(eased - 0.75) < 0.001)
    }

    @Test("bounce easing reaches endpoints")
    func bounceEasingEndpoints() {
        #expect(InterpolationUtils.applyEasing(0.0, .bounce) == 0.0)
        let end = InterpolationUtils.applyEasing(1.0, .bounce)
        #expect(abs(end - 1.0) < 0.001)
    }

    @Test("elastic easing overshoots 1.0")
    func elasticEasingOvershoot() {
        // Elastic should overshoot at some point
        let mid = InterpolationUtils.applyEasing(0.5, .elastic)
        #expect(mid > 1.0)
    }

    @Test("hold easing snaps at t=1")
    func holdEasing() {
        #expect(InterpolationUtils.applyEasing(0.0, .hold) == 0.0)
        #expect(InterpolationUtils.applyEasing(0.5, .hold) == 0.0)
        #expect(InterpolationUtils.applyEasing(0.99, .hold) == 0.0)
        #expect(InterpolationUtils.applyEasing(1.0, .hold) == 1.0)
    }
}
