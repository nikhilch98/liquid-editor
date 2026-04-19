// PinchZoomModifier.swift
// LiquidEditor
//
// T7-2 (Premium UI §10.3): Pinch-to-zoom with 6 snap stops + two-finger pan.
//
// - MagnifyGesture drives `zoomScale` continuously.
// - Two-finger DragGesture drives `panOffset` continuously.
// - On gesture end, `zoomScale` snaps to the nearest of 6 preset stops
//   (0.25x, 0.5x, 1x, 2x, 4x, 8x) with `.liquid` animation.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Pinch-to-zoom + two-finger pan for the timeline.
struct PinchZoomModifier: ViewModifier {

    /// Canonical snap stops (§10.3).
    static let snapStops: [Double] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]

    @Binding var zoomScale: Double
    @Binding var panOffset: CGSize

    @State private var baseZoomScale: Double = 1.0
    @State private var basePanOffset: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .gesture(magnify.simultaneously(with: twoFingerPan))
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let raw = baseZoomScale * value.magnification
                zoomScale = max(PinchZoomModifier.snapStops.first ?? 0.25,
                                min(PinchZoomModifier.snapStops.last ?? 8.0, raw))
            }
            .onEnded { _ in
                baseZoomScale = zoomScale
                let nearest = PinchZoomModifier.nearestStop(to: zoomScale)
                withAnimation(.liquid(LiquidMotion.glide, reduceMotion: reduceMotion)) {
                    zoomScale = nearest
                    baseZoomScale = nearest
                }
            }
    }

    private var twoFingerPan: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                panOffset = CGSize(
                    width: basePanOffset.width + value.translation.width,
                    height: basePanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in basePanOffset = panOffset }
    }

    /// Returns the preset stop closest to `value` in log-scale distance.
    static func nearestStop(to value: Double) -> Double {
        snapStops.min { a, b in
            abs(log2(a) - log2(value)) < abs(log2(b) - log2(value))
        } ?? 1.0
    }
}

extension View {
    /// Attach pinch-zoom + two-finger pan with 6-stop snap.
    func pinchZoomSnap(zoomScale: Binding<Double>, panOffset: Binding<CGSize>) -> some View {
        modifier(PinchZoomModifier(zoomScale: zoomScale, panOffset: panOffset))
    }
}
