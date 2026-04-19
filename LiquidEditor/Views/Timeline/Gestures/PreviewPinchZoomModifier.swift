// PreviewPinchZoomModifier.swift
// LiquidEditor
//
// T7-21 (Premium UI §10.3): Pinch-to-zoom the preview player between 1x
// and 5x, with a DragGesture for panning while zoomed.
//
// When the user releases the pinch and the scale has returned to <= 1x,
// pan is reset with `.liquid` animation.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Preview-player pinch-zoom (1x..5x) + pan.
struct PreviewPinchZoomModifier: ViewModifier {

    @Binding var zoomScale: Double
    @Binding var panOffset: CGSize

    let minZoom: Double
    let maxZoom: Double

    @State private var baseZoomScale: Double = 1.0
    @State private var basePanOffset: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        zoomScale: Binding<Double>,
        panOffset: Binding<CGSize>,
        minZoom: Double = 1.0,
        maxZoom: Double = 5.0
    ) {
        self._zoomScale = zoomScale
        self._panOffset = panOffset
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }

    func body(content: Content) -> some View {
        content.gesture(magnify.simultaneously(with: pan))
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let raw = baseZoomScale * value.magnification
                zoomScale = min(max(raw, minZoom), maxZoom)
            }
            .onEnded { _ in
                baseZoomScale = zoomScale
                if zoomScale <= minZoom {
                    withAnimation(.liquid(LiquidMotion.smooth, reduceMotion: reduceMotion)) {
                        zoomScale = minZoom
                        baseZoomScale = minZoom
                        panOffset = .zero
                        basePanOffset = .zero
                    }
                }
            }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard zoomScale > minZoom else { return }
                panOffset = CGSize(
                    width: basePanOffset.width + value.translation.width,
                    height: basePanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard zoomScale > minZoom else { return }
                basePanOffset = panOffset
            }
    }
}

extension View {
    /// Attach preview-player pinch-zoom + pan.
    func previewPinchZoom(
        zoomScale: Binding<Double>,
        panOffset: Binding<CGSize>,
        minZoom: Double = 1.0,
        maxZoom: Double = 5.0
    ) -> some View {
        modifier(PreviewPinchZoomModifier(
            zoomScale: zoomScale,
            panOffset: panOffset,
            minZoom: minZoom,
            maxZoom: maxZoom
        ))
    }
}
