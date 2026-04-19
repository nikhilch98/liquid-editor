// ClipDragReorderModifier.swift
// LiquidEditor
//
// T7-3 (Premium UI §10.3): Drag a clip to reorder within its track, or
// drop it onto a different track (cross-track drop).
//
// The modifier only emits callbacks — the caller owns actual reordering
// logic. Visually the wrapped view follows the finger at 0.8 opacity.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Attaches a reorder / cross-track drop gesture to a clip view.
struct ClipDragReorderModifier: ViewModifier {

    let clipID: String

    /// Fired when the drag begins (after minimum-distance threshold).
    let onDragStart: (String) -> Void

    /// Fired continuously with the current drag translation in the parent
    /// coordinate space. Caller resolves translation into track/time.
    let onDragUpdate: (String, CGPoint) -> Void

    /// Fired when finger lifts. Caller commits the new placement.
    let onDragEnd: (String, CGPoint) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isDragging ? 0.8 : 1.0)
            .offset(dragOffset)
            .zIndex(isDragging ? 10 : 0)
            .animation(.liquid(LiquidMotion.snap, reduceMotion: reduceMotion), value: isDragging)
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onDragStart(clipID)
                }
                dragOffset = value.translation
                onDragUpdate(clipID, value.location)
            }
            .onEnded { value in
                onDragEnd(clipID, value.location)
                isDragging = false
                dragOffset = .zero
            }
    }
}

extension View {
    /// Wrap a clip view in drag-to-reorder + cross-track drop.
    func clipDragReorder(
        clipID: String,
        onDragStart: @escaping (String) -> Void,
        onDragUpdate: @escaping (String, CGPoint) -> Void,
        onDragEnd: @escaping (String, CGPoint) -> Void
    ) -> some View {
        modifier(ClipDragReorderModifier(
            clipID: clipID,
            onDragStart: onDragStart,
            onDragUpdate: onDragUpdate,
            onDragEnd: onDragEnd
        ))
    }
}
