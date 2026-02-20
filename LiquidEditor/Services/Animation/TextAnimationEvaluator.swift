/// Text animation evaluation functions.
///
/// Evaluates enter, exit, and sustain animation presets at a given
/// progress value (0.0-1.0) and returns the animation state
/// (position delta, scale factor, rotation delta, opacity factor).
///
/// All animations are deterministic. Glitch animations use a seeded
/// PRNG based on clip ID hash + frame time for reproducibility.
///
/// Thread Safety: `Sendable` by construction (enum with only static methods
/// and `Sendable` return types). Safe to call from any thread or actor context.

import CoreGraphics
import Foundation

// MARK: - AnimationState

/// The computed animation state at a specific time.
///
/// Values are relative modifiers applied on top of the base text state:
/// - `positionDelta` is added to the base position (normalized coordinates).
/// - `scaleFactor` multiplies the base scale.
/// - `rotationDelta` is added to the base rotation (radians).
/// - `opacityFactor` multiplies the base opacity.
struct AnimationState: Sendable, Equatable {
    /// Position offset to add (normalized 0.0-1.0 coordinates).
    let positionDelta: CGPoint

    /// Scale multiplier (1.0 = no change).
    let scaleFactor: Double

    /// Rotation offset in radians.
    let rotationDelta: Double

    /// Opacity multiplier (0.0-1.0).
    let opacityFactor: Double

    init(
        positionDelta: CGPoint = .zero,
        scaleFactor: Double = 1.0,
        rotationDelta: Double = 0.0,
        opacityFactor: Double = 1.0
    ) {
        self.positionDelta = positionDelta
        self.scaleFactor = scaleFactor
        self.rotationDelta = rotationDelta
        self.opacityFactor = opacityFactor
    }

    /// Identity state (no animation effect).
    static let identity = AnimationState()
}

// MARK: - TextAnimationEvaluator

/// Evaluates text animation presets and keyframes.
///
/// Uses an `enum` namespace (no cases) with all-static methods.
/// No instance creation is needed or possible.
///
/// Usage:
/// ```swift
/// let state = TextAnimationEvaluator.evaluateEnterAnimation(preset, t: 0.5)
/// ```
enum TextAnimationEvaluator {

    // MARK: - Constants

    /// Default sustain loop period in microseconds (2 seconds).
    private static let defaultLoopMicros: Int64 = 2_000_000

    // MARK: - Enter Animation

    /// Evaluate an enter animation at progress `t` (0.0 to 1.0).
    ///
    /// At t=0, the text is fully hidden/off-screen.
    /// At t=1, the text is at its normal resting state.
    ///
    /// - Parameters:
    ///   - preset: The animation preset configuration.
    ///   - t: Normalized progress (0.0-1.0).
    ///   - seedHash: Deterministic seed for noise-based animations (e.g. glitch).
    /// - Returns: The computed `AnimationState` for this frame.
    static func evaluateEnterAnimation(
        _ preset: TextAnimationPreset,
        t: Double,
        seedHash: Int = 0
    ) -> AnimationState {
        let intensity = preset.intensity
        // Apply easeOut by default for enter animations
        let eased = applyDefaultEasing(t, isEnter: true)

        switch preset.type {
        case .fadeIn:
            return AnimationState(opacityFactor: eased)

        case .slideInLeft:
            return AnimationState(
                positionDelta: CGPoint(x: -(1 - eased) * 0.3 * intensity, y: 0),
                opacityFactor: eased
            )

        case .slideInRight:
            return AnimationState(
                positionDelta: CGPoint(x: (1 - eased) * 0.3 * intensity, y: 0),
                opacityFactor: eased
            )

        case .slideInTop:
            return AnimationState(
                positionDelta: CGPoint(x: 0, y: -(1 - eased) * 0.3 * intensity),
                opacityFactor: eased
            )

        case .slideInBottom:
            return AnimationState(
                positionDelta: CGPoint(x: 0, y: (1 - eased) * 0.3 * intensity),
                opacityFactor: eased
            )

        case .scaleUp:
            return AnimationState(
                scaleFactor: eased,
                opacityFactor: eased
            )

        case .bounceIn:
            let bounced = InterpolationUtils.applyEasing(t, .bounce)
            return AnimationState(
                scaleFactor: bounced,
                opacityFactor: min(max(t * 2, 0.0), 1.0)
            )

        case .typewriter:
            // Typewriter does not change position/scale/rotation/opacity.
            // The character reveal is handled by the renderer via
            // a special `visibleCharCount` field derived from t.
            return AnimationState(opacityFactor: 1.0)

        case .glitchIn:
            let noise = deterministicNoise(seedHash: seedHash, frameIndex: Int(t * 100))
            let remaining = (1 - t) * intensity
            return AnimationState(
                positionDelta: CGPoint(
                    x: noise * 0.05 * remaining,
                    y: (noise * 0.7 - 0.35) * 0.05 * remaining
                ),
                scaleFactor: 1.0 + noise * 0.1 * remaining,
                rotationDelta: noise * 0.05 * remaining,
                opacityFactor: min(max(eased + noise * 0.3 * remaining, 0.0), 1.0)
            )

        case .rotateIn:
            return AnimationState(
                rotationDelta: (1 - eased) * (.pi / 4) * intensity,
                opacityFactor: eased
            )

        case .blurIn:
            // Blur is handled by the renderer via CIGaussianBlur.
            // We signal via opacity; blur amount = (1 - t) * intensity.
            return AnimationState(opacityFactor: eased)

        case .popIn:
            let elastic = InterpolationUtils.applyEasing(t, .elastic)
            return AnimationState(
                scaleFactor: elastic,
                opacityFactor: min(max(t * 3, 0.0), 1.0)
            )

        // Exit and sustain types should not be used as enter animations,
        // but handle gracefully by returning identity.
        default:
            return .identity
        }
    }

    // MARK: - Exit Animation

    /// Evaluate an exit animation at progress `t` (0.0 to 1.0).
    ///
    /// At t=0, the text is at its normal resting state.
    /// At t=1, the text is fully hidden/exited.
    ///
    /// - Parameters:
    ///   - preset: The animation preset configuration.
    ///   - t: Normalized progress (0.0-1.0).
    ///   - seedHash: Deterministic seed for noise-based animations (e.g. glitch).
    /// - Returns: The computed `AnimationState` for this frame.
    static func evaluateExitAnimation(
        _ preset: TextAnimationPreset,
        t: Double,
        seedHash: Int = 0
    ) -> AnimationState {
        let intensity = preset.intensity
        // Apply easeIn by default for exit animations
        let eased = applyDefaultEasing(t, isEnter: false)

        switch preset.type {
        case .fadeOut:
            return AnimationState(opacityFactor: 1 - eased)

        case .slideOutLeft:
            return AnimationState(
                positionDelta: CGPoint(x: -eased * 0.3 * intensity, y: 0),
                opacityFactor: 1 - eased
            )

        case .slideOutRight:
            return AnimationState(
                positionDelta: CGPoint(x: eased * 0.3 * intensity, y: 0),
                opacityFactor: 1 - eased
            )

        case .slideOutTop:
            return AnimationState(
                positionDelta: CGPoint(x: 0, y: -eased * 0.3 * intensity),
                opacityFactor: 1 - eased
            )

        case .slideOutBottom:
            return AnimationState(
                positionDelta: CGPoint(x: 0, y: eased * 0.3 * intensity),
                opacityFactor: 1 - eased
            )

        case .scaleDown:
            return AnimationState(
                scaleFactor: 1 - eased,
                opacityFactor: 1 - eased
            )

        case .bounceOut:
            let bounced = InterpolationUtils.applyEasing(t, .bounce)
            return AnimationState(
                scaleFactor: 1 - bounced,
                opacityFactor: min(max(1 - t * 2, 0.0), 1.0)
            )

        case .glitchOut:
            let noise = deterministicNoise(seedHash: seedHash, frameIndex: Int(t * 100))
            let progress = t * intensity
            return AnimationState(
                positionDelta: CGPoint(
                    x: noise * 0.05 * progress,
                    y: (noise * 0.7 - 0.35) * 0.05 * progress
                ),
                scaleFactor: 1.0 + noise * 0.1 * progress,
                rotationDelta: noise * 0.05 * progress,
                opacityFactor: min(max(1 - eased + noise * 0.3 * progress, 0.0), 1.0)
            )

        case .rotateOut:
            return AnimationState(
                rotationDelta: eased * (.pi / 4) * intensity,
                opacityFactor: 1 - eased
            )

        case .blurOut:
            return AnimationState(opacityFactor: 1 - eased)

        case .popOut:
            let elastic = InterpolationUtils.applyEasing(t, .elastic)
            return AnimationState(
                scaleFactor: 1 - elastic,
                opacityFactor: min(max(1 - t * 3, 0.0), 1.0)
            )

        default:
            return .identity
        }
    }

    // MARK: - Sustain Animation

    /// Evaluate a sustain (looping) animation.
    ///
    /// The animation loops with a configurable period from the preset's
    /// parameters map (key `"loopDuration"` in seconds, default 2.0).
    ///
    /// - Parameters:
    ///   - preset: The animation preset configuration.
    ///   - sustainOffsetMicros: Time elapsed since the sustain phase began (microseconds).
    ///   - seedHash: Deterministic seed for noise-based animations (e.g. shake).
    /// - Returns: The computed `AnimationState` for this frame.
    static func evaluateSustainAnimation(
        _ preset: TextAnimationPreset,
        sustainOffsetMicros: Int64,
        seedHash: Int = 0
    ) -> AnimationState {
        let intensity = preset.intensity
        let loopSeconds = preset.parameters["loopDuration"] ?? 2.0
        let loopMicros = Int64(loopSeconds * 1_000_000)
        let effectiveLoopMicros = loopMicros > 0 ? loopMicros : defaultLoopMicros

        let t = Double(sustainOffsetMicros % effectiveLoopMicros)
            / Double(effectiveLoopMicros)

        switch preset.type {
        case .breathe:
            let breathe = sin(t * 2 * .pi)
            return AnimationState(
                scaleFactor: 1.0 + breathe * 0.02 * intensity
            )

        case .pulse:
            let pulse = sin(t * 2 * .pi)
            return AnimationState(
                opacityFactor: 1.0 - (1 - pulse) * 0.15 * intensity
            )

        case .float:
            let floatY = sin(t * 2 * .pi)
            return AnimationState(
                positionDelta: CGPoint(x: 0, y: floatY * 0.01 * intensity)
            )

        case .shake:
            let noise = deterministicNoise(
                seedHash: seedHash,
                frameIndex: Int(sustainOffsetMicros / 16667) // per-frame at ~60fps
            )
            let decay = sin(t * .pi) // peak in middle
            return AnimationState(
                positionDelta: CGPoint(
                    x: noise * 0.01 * intensity * decay,
                    y: 0
                )
            )

        case .flicker:
            let noise = deterministicNoise(
                seedHash: seedHash,
                frameIndex: Int(sustainOffsetMicros / 33333) // ~30fps
            )
            return AnimationState(
                opacityFactor: 0.5 + noise * 0.5 * intensity
            )

        default:
            return .identity
        }
    }

    // MARK: - Typewriter

    /// Compute the number of visible characters for typewriter animation.
    ///
    /// - Parameters:
    ///   - t: Normalized progress (0.0-1.0).
    ///   - totalChars: Total number of characters in the text.
    /// - Returns: Number of characters to display.
    static func typewriterVisibleChars(t: Double, totalChars: Int) -> Int {
        min(max(Int(t * Double(totalChars)), 0), totalChars)
    }

    // MARK: - Blur

    /// Compute blur sigma value for blur-in/blur-out animations.
    ///
    /// Returns the Gaussian blur sigma at progress `t`.
    ///
    /// - Parameters:
    ///   - type: The animation preset type (blurIn or blurOut).
    ///   - t: Normalized progress (0.0-1.0).
    ///   - intensity: Animation intensity (0.0-1.0).
    /// - Returns: The blur sigma value.
    static func computeBlurSigma(
        type: TextAnimationPresetType,
        t: Double,
        intensity: Double
    ) -> Double {
        let maxBlur = 20.0
        switch type {
        case .blurIn:
            return maxBlur * (1 - t) * intensity
        case .blurOut:
            return maxBlur * t * intensity
        default:
            return 0.0
        }
    }

    // MARK: - Private Helpers

    /// Apply default easing for enter (easeOut) or exit (easeIn) animations.
    ///
    /// - Parameters:
    ///   - t: Normalized progress (0.0-1.0).
    ///   - isEnter: `true` for enter animations (easeOut), `false` for exit (easeIn).
    /// - Returns: Eased progress value.
    private static func applyDefaultEasing(_ t: Double, isEnter: Bool) -> Double {
        if isEnter {
            // easeOut: 1 - (1 - t)^2
            return 1 - (1 - t) * (1 - t)
        } else {
            // easeIn: t^2
            return t * t
        }
    }

    /// Deterministic noise generator using a seeded approach.
    ///
    /// Returns a value in [0.0, 1.0).
    /// The seed combines clip ID hash and frame index for reproducibility
    /// across preview and export.
    ///
    /// Uses the Lehmer/Park-Miller PRNG algorithm.
    ///
    /// - Parameters:
    ///   - seedHash: Hash of the clip ID for determinism.
    ///   - frameIndex: Frame index for per-frame variation.
    /// - Returns: Pseudo-random value in [0.0, 1.0).
    private static func deterministicNoise(seedHash: Int, frameIndex: Int) -> Double {
        // Simple hash-based PRNG (Lehmer/Park-Miller)
        var seed = (seedHash ^ frameIndex) & 0x7FFFFFFF
        if seed == 0 { seed = 1 }
        seed = (seed &* 16807) % 2_147_483_647
        return Double(seed) / 2_147_483_647.0
    }
}
