// PencilOnlyGestureModifier.swift
// LiquidEditor
//
// Apple Pencil-only freehand drawing surface.
// Wraps `PKCanvasView` via `UIViewRepresentable` because SwiftUI has no
// native Pencil drawing primitive. The canvas is configured with
// `drawingPolicy = .pencilOnly` so finger input is ignored, ensuring
// precise mask / curve / text path authoring.
//
// Exposed as the `.pencilFreehandDraw(_:)` view modifier, which binds a
// `[CGPoint]` array of the most recent stroke's sampled points (screen
// coordinates). Callers can transform or persist the points as needed.

import PencilKit
import SwiftUI
import UIKit

// MARK: - PencilFreehandCanvas

/// SwiftUI-wrapped `PKCanvasView` that accepts Apple Pencil input only.
///
/// Each finished stroke emits its sampled points through `points`. The
/// canvas is transparent so it composites over any existing SwiftUI
/// content (e.g. a video preview or mask layer).
struct PencilFreehandCanvas: UIViewRepresentable {

    /// Binding to the most recent stroke's sampled points in canvas
    /// coordinate space. Replaced (not appended) on each stroke end.
    @Binding var points: [CGPoint]

    /// Ink type for the drawing tool. Default `.pen`.
    var inkType: PKInk.InkType = .pen

    /// Ink color. Default white (visible over dark editor canvas).
    var inkColor: UIColor = .white

    /// Canvas tool width in points. Default 4.
    var toolWidth: CGFloat = 4

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly          // Ignore finger input.
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.tool = PKInkingTool(inkType, color: inkColor, width: toolWidth)
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(inkType, color: inkColor, width: toolWidth)
    }

    // MARK: - Coordinator

    /// Bridges `PKCanvasViewDelegate` callbacks to the SwiftUI binding.
    final class Coordinator: NSObject, PKCanvasViewDelegate {

        var parent: PencilFreehandCanvas

        init(parent: PencilFreehandCanvas) {
            self.parent = parent
        }

        /// Called when the user lifts the Pencil; extract the most recent
        /// stroke and forward its sampled points to the binding.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let lastStroke = canvasView.drawing.strokes.last else { return }

            // `PKStrokePath` is indexable; convert to [CGPoint].
            let path = lastStroke.path
            var sampled: [CGPoint] = []
            sampled.reserveCapacity(path.count)
            for index in 0..<path.count {
                sampled.append(path[index].location)
            }

            // Writing to a binding must happen on the main actor.
            DispatchQueue.main.async { [weak self] in
                self?.parent.points = sampled
            }
        }
    }
}

// MARK: - PencilFreehandDrawModifier

/// Overlays a Pencil-only drawing canvas on the modified view. The canvas
/// is positioned on top and matches the host view's frame. Finger input
/// falls through to the underlying view because `drawingPolicy` is
/// `.pencilOnly`.
struct PencilFreehandDrawModifier: ViewModifier {

    @Binding var points: [CGPoint]

    func body(content: Content) -> some View {
        content
            .overlay(
                PencilFreehandCanvas(points: $points)
                    .allowsHitTesting(true)
            )
    }
}

extension View {

    /// Adds an Apple Pencil-only freehand drawing layer on top of this view.
    ///
    /// Finger taps pass through to the underlying content. The binding
    /// receives each completed stroke's sampled path as `[CGPoint]`.
    func pencilFreehandDraw(_ points: Binding<[CGPoint]>) -> some View {
        modifier(PencilFreehandDrawModifier(points: points))
    }
}
