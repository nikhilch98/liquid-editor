// PlayheadView.swift
// LiquidEditor
//
// Playhead indicator — a simple vertical red line with a draggable
// triangle handle at the top. No time label, no glow shadow.
// Overlaid on the timeline via ZStack.
//
// Pure SwiftUI, iOS 26 native styling.
// Matches Flutter PlayheadPainter layout.

import SwiftUI

// MARK: - PlayheadView

struct PlayheadView: View {

    // MARK: - Properties

    /// X position of the playhead in the coordinate space of the timeline.
    let xPosition: CGFloat

    /// Total height of the timeline area.
    let height: CGFloat

    /// Current playhead time (for potential external use).
    let currentTime: TimeMicros

    /// Called during drag with the new X position.
    var onDrag: ((CGFloat) -> Void)?

    /// Called when drag ends.
    var onDragEnded: (() -> Void)?

    // MARK: - Local State

    @State private var isDragging: Bool = false
    @State private var dragStartX: CGFloat = 0

    // MARK: - Constants

    private let lineWidth: CGFloat = 1.5
    private let handleSize: CGFloat = 14

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Vertical playhead line (no glow shadow).
            Rectangle()
                .fill(LiquidColors.timelinePlayhead)
                .frame(width: lineWidth, height: height)

            // Triangle handle at the top.
            playheadHandle
        }
        .position(x: xPosition, y: height / 2)
        .allowsHitTesting(true)
        .accessibilityElement()
        .accessibilityLabel("Playhead")
        .accessibilityHint("Drag to scrub through the timeline")
    }

    // MARK: - Handle

    @ViewBuilder
    private var playheadHandle: some View {
        Triangle()
            .fill(LiquidColors.timelinePlayhead)
            .frame(width: handleSize, height: handleSize * 0.8)
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            .offset(y: -(height / 2) + handleSize * 0.4)
            .gesture(playheadDragGesture)
            .contentShape(Rectangle().size(width: handleSize + 20, height: handleSize + 20))
    }

    // MARK: - Gesture

    private var playheadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartX = xPosition
                }
                let newX = dragStartX + value.translation.width
                onDrag?(newX)
            }
            .onEnded { _ in
                isDragging = false
                onDragEnded?()
            }
    }
}

// MARK: - Triangle Shape

/// A downward-pointing triangle for the playhead handle.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
