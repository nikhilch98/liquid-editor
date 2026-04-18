// LiquidMotion.swift
// LiquidEditor
//
// Spring and easing tokens for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Animation tokens tuned to the spec's stiffness / damping targets.
/// All values are static constants — no allocation during interaction.
enum LiquidMotion {
    /// Button taps, haptic-coupled flips. Stiffness 500 / damping 24.
    static let snap = Animation.spring(response: 0.22, dampingFraction: 0.75)

    /// Panel swap, sheet present/dismiss. Stiffness 300 / damping 26.
    static let smooth = Animation.spring(response: 0.3, dampingFraction: 0.85)

    /// Tab pill indicator, selection-ring appearance. Stiffness 220 / damping 18.
    static let bounce = Animation.spring(response: 0.35, dampingFraction: 0.62)

    /// Timeline zoom, scroll snap-to-edge. Stiffness 180 / damping 30.
    static let glide = Animation.spring(response: 0.4, dampingFraction: 0.9)

    /// Opacity fades, shimmer, auto-hide overlays.
    static let easeOut = Animation.easeOut(duration: 0.18)

    /// The Reduce-Motion substitute for every other token. Consumers
    /// should pick this via ``Animation.liquid(_ base:, reduceMotion:)``.
    static let reduced = Animation.easeOut(duration: 0.12)
}

extension Animation {
    /// Pick a motion token, or its Reduce-Motion-safe replacement.
    ///
    /// Use at every site that would animate: ``.animation(.liquid(.bounce, reduceMotion: reduce))``.
    static func liquid(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? LiquidMotion.reduced : base
    }
}
