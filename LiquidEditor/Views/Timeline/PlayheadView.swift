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

    // MARK: - Body

    var body: some View {
        PlayheadWithChip(
            timeText: currentTime.simpleTimeString,
            isScrubbing: isDragging
        )
        .frame(height: height)
        .position(x: xPosition, y: height / 2)
        .gesture(playheadDragGesture)
        .allowsHitTesting(true)
        .accessibilityHint("Drag to scrub through the timeline")
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

