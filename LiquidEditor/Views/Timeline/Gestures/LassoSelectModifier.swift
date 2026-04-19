// LassoSelectModifier.swift
// LiquidEditor
//
// T7-5 (Premium UI §10.3): iPad-only two-finger lasso multi-select.
//
// Two-finger drag draws a translucent selection rectangle; on finger lift
// the final CGRect is passed to `onLassoEnd` so the caller can intersect
// it with on-screen clip frames to select. Compact form factor ignores
// the gesture (iPhone uses shift-tap style interactions elsewhere).
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Two-finger lasso multi-select overlay (iPad).
struct LassoSelectModifier: ViewModifier {

    let onLassoEnd: (CGRect) -> Void

    @State private var startPoint: CGPoint?
    @State private var currentRect: CGRect = .zero

    @Environment(\.formFactor) private var formFactor

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if formFactor == .regular, currentRect != .zero {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        )
                        .frame(width: currentRect.width, height: currentRect.height)
                        .offset(x: currentRect.minX, y: currentRect.minY)
                        .allowsHitTesting(false)
                }
            }
            .gesture(formFactor == .regular ? lassoGesture : nil)
    }

    private var lassoGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let start = startPoint ?? value.startLocation
                if startPoint == nil { startPoint = start }
                currentRect = CGRect(
                    x: min(start.x, value.location.x),
                    y: min(start.y, value.location.y),
                    width: abs(value.location.x - start.x),
                    height: abs(value.location.y - start.y)
                )
            }
            .onEnded { _ in
                if currentRect != .zero { onLassoEnd(currentRect) }
                startPoint = nil
                currentRect = .zero
            }
    }
}

extension View {
    /// Attach iPad-only two-finger lasso multi-select overlay.
    func lassoSelect(onLassoEnd: @escaping (CGRect) -> Void) -> some View {
        modifier(LassoSelectModifier(onLassoEnd: onLassoEnd))
    }
}
