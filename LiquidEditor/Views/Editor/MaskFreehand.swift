// MaskFreehand.swift
// LiquidEditor
//
// Minimal SwiftUI scaffold that demonstrates `pencilFreehandDraw(_:)`
// — the Apple Pencil-only freehand drawing surface defined in
// `PencilOnlyGestureModifier.swift`.
//
// A full MaskEditor will eventually host this view and route the sampled
// points into the masking pipeline. For now this scaffold serves as a
// smoke test / preview and ensures the modifier is compiled into the app.
//
// Pure SwiftUI, iOS 26 native styling.

import SwiftUI

// MARK: - MaskFreehandView

/// Freehand-drawn mask authoring view.
///
/// Provides a transparent canvas on top of the preview that accepts only
/// Apple Pencil input. The most recent stroke's sampled points are shown
/// in a small badge so the author can verify capture; real usage will
/// forward `strokePoints` into the mask renderer.
struct MaskFreehandView: View {

    /// Most recent stroke's sampled points, populated by the Pencil modifier.
    @State private var strokePoints: [CGPoint] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            LiquidColors.background
                .ignoresSafeArea()

            // Content underneath the Pencil canvas (placeholder preview).
            VStack(spacing: LiquidSpacing.md) {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Apple Pencil Mask")
                    .font(LiquidTypography.title3)
                    .foregroundStyle(.primary)

                Text("Draw a freehand mask with Apple Pencil. Finger taps are ignored.")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LiquidSpacing.xxxl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // HUD badge showing captured point count (debug/verification).
            if !strokePoints.isEmpty {
                Text("\(strokePoints.count) points")
                    .font(LiquidTypography.caption2Semibold)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, LiquidSpacing.sm)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(.black.opacity(0.6))
                    )
                    .padding(LiquidSpacing.md)
                    .accessibilityLabel("Captured \(strokePoints.count) stroke points")
            }
        }
        // Apple Pencil-only freehand drawing overlay.
        .pencilFreehandDraw($strokePoints)
        .accessibilityLabel("Mask freehand canvas")
        .accessibilityHint("Use Apple Pencil to draw a mask. Finger touches pass through.")
    }
}

// MARK: - Preview

#Preview("Mask Freehand") {
    MaskFreehandView()
}
