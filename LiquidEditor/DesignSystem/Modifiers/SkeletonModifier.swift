// SkeletonModifier.swift
// LiquidEditor
//
// P1-7: Shimmer-based loading placeholder per spec §9.11.
//
// Behavior:
// - Default: linear-gradient sweep from tertiary-text -> secondary-text
//   cycling every 1.2s.
// - Reduce Motion: static tertiary-text fill, no sweep.
//
// Applied via the `.skeleton()` View modifier to any placeholder shape.
// Consumers (project-card thumbnail, media-picker grid, auto-captions
// list, scopes warm-up) wrap their placeholder rectangles.

import SwiftUI

// MARK: - SkeletonModifier

/// A shimmering loading placeholder modifier.
///
/// Wrap any placeholder shape (Rectangle, RoundedRectangle, Capsule)
/// with `.skeleton()` while content is loading. Respects Reduce Motion
/// by falling back to a static tertiary fill.
struct SkeletonModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animationPhase: CGFloat = -1

    private let cycleDuration: Double = 1.2

    func body(content: Content) -> some View {
        content
            .overlay(shimmerOverlay)
            .clipped()
            .accessibilityHidden(true)
            .onAppear(perform: startAnimation)
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if reduceMotion {
            LiquidColors.Text.tertiary.opacity(0.3)
        } else {
            LinearGradient(
                colors: [
                    LiquidColors.Text.tertiary.opacity(0.25),
                    LiquidColors.Text.secondary.opacity(0.15),
                    LiquidColors.Text.tertiary.opacity(0.25),
                ],
                startPoint: .init(x: animationPhase, y: 0),
                endPoint: .init(x: animationPhase + 1, y: 0)
            )
            .animation(
                .linear(duration: cycleDuration).repeatForever(autoreverses: false),
                value: animationPhase
            )
        }
    }

    private func startAnimation() {
        guard !reduceMotion else { return }
        animationPhase = 2
    }
}

// MARK: - View extension

extension View {
    /// Apply the loading-skeleton shimmer to this placeholder shape.
    ///
    /// Use on a filled placeholder (e.g., `Rectangle().fill(...)`) that
    /// represents content about to load. Falls back to a static fill
    /// under Reduce Motion.
    func skeleton() -> some View {
        modifier(SkeletonModifier())
    }
}

// MARK: - Previews

#Preview("Skeleton cards") {
    VStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LiquidColors.Canvas.raised)
            .frame(height: 80)
            .skeleton()
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LiquidColors.Canvas.raised)
            .frame(height: 80)
            .skeleton()
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LiquidColors.Canvas.raised)
            .frame(height: 80)
            .skeleton()
    }
    .padding()
    .background(LiquidColors.Canvas.base)
    .preferredColorScheme(.dark)
}
