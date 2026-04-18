// ReduceMotionAware.swift
// LiquidEditor
//
// Reduce Motion accessibility fallbacks for SwiftUI animations.
// When the user has enabled "Reduce Motion" in iOS Accessibility
// settings, this modifier swaps out the caller's animation for an
// instantaneous / near-instantaneous one, preserving state changes
// without animating transform- and position-based effects that can
// trigger motion sickness.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §10.6 (A10-4)

import SwiftUI

// MARK: - ReduceMotionAwareModifier

/// ViewModifier that substitutes a reduced animation when the
/// `accessibilityReduceMotion` environment value is `true`.
///
/// When Reduce Motion is enabled we return `.linear(duration: 0)`
/// so state transitions still happen but without animated movement.
private struct ReduceMotionAwareModifier<Value: Equatable>: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .linear(duration: 0) : animation, value: value)
    }
}

// MARK: - View Extension

extension View {

    /// Apply an animation that respects the user's Reduce Motion setting.
    ///
    /// When Reduce Motion is on, the animation is swapped for a
    /// zero-duration linear animation so state changes are applied
    /// without visible motion. Otherwise, the supplied animation is
    /// used as-is.
    ///
    /// - Parameters:
    ///   - animation: The preferred animation when Reduce Motion is off.
    ///   - value: The value whose changes drive the animation.
    /// - Returns: A view whose animation adapts to accessibility preferences.
    func liquidAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(ReduceMotionAwareModifier(animation: animation, value: value))
    }
}

// MARK: - WithAnimation Helper

/// Perform an animated mutation that respects Reduce Motion.
///
/// Use in place of `withAnimation(_:_:)` when you need an imperative
/// animation block in a gesture handler or callback. Callers can pass
/// the current `accessibilityReduceMotion` environment value; when
/// `true`, the underlying animation is dropped so state is updated
/// synchronously.
///
/// ```swift
/// @Environment(\.accessibilityReduceMotion) private var reduceMotion
/// ...
/// liquidWithAnimation(.easeInOut, reduceMotion: reduceMotion) {
///     isPresented.toggle()
/// }
/// ```
///
/// - Parameters:
///   - animation: The preferred animation.
///   - reduceMotion: The current Reduce Motion flag from the environment.
///   - body: The mutation to perform.
@MainActor
func liquidWithAnimation<Result>(
    _ animation: Animation?,
    reduceMotion: Bool,
    _ body: () throws -> Result
) rethrows -> Result {
    if reduceMotion {
        return try withAnimation(.linear(duration: 0), body)
    }
    return try withAnimation(animation, body)
}
