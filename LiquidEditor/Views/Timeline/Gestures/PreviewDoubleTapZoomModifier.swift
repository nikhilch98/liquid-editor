// PreviewDoubleTapZoomModifier.swift
// LiquidEditor
//
// T7-22 (Premium UI §10.3): Double-tap the preview to toggle between 1x
// and a target zoom (default 2x).
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Double-tap to toggle preview zoom between 1x and `targetZoom`.
struct PreviewDoubleTapZoomModifier: ViewModifier {

    @Binding var zoomScale: Double

    /// Zoom level to toggle into. Spec default is 2x.
    let targetZoom: Double

    /// Epsilon for "at 1x" comparison.
    let epsilon: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(zoomScale: Binding<Double>, targetZoom: Double = 2.0, epsilon: Double = 0.05) {
        self._zoomScale = zoomScale
        self.targetZoom = targetZoom
        self.epsilon = epsilon
    }

    func body(content: Content) -> some View {
        content.onTapGesture(count: 2) {
            withAnimation(.liquid(LiquidMotion.smooth, reduceMotion: reduceMotion)) {
                zoomScale = isAtOne ? targetZoom : 1.0
            }
        }
    }

    private var isAtOne: Bool { abs(zoomScale - 1.0) < epsilon }
}

extension View {
    /// Attach a double-tap-zoom-toggle gesture to a preview view.
    func previewDoubleTapZoom(
        zoomScale: Binding<Double>,
        targetZoom: Double = 2.0
    ) -> some View {
        modifier(PreviewDoubleTapZoomModifier(
            zoomScale: zoomScale,
            targetZoom: targetZoom
        ))
    }
}
