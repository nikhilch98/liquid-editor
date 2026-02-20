// StickerPositionHandle.swift
// LiquidEditor
//
// Sticker position handle - draggable/rotatable/scalable gesture handler.
//
// Provides touch gesture handling for sticker manipulation on the
// video preview canvas. Supports drag (move), pinch (scale), and
// two-finger rotate. Emits transform updates as normalized coordinates.
//
// Pure iOS 26 SwiftUI with native gesture combinators.

import SwiftUI

// MARK: - StickerTransformUpdate

/// Values emitted during a sticker transform gesture.
struct StickerTransformUpdate: Equatable, Sendable {
    /// Updated position (normalized 0.0-1.0), nil if unchanged.
    var position: CGPoint?
    /// Updated rotation in radians, nil if unchanged.
    var rotation: Double?
    /// Updated scale factor, nil if unchanged.
    var scale: Double?
}

// MARK: - StickerPositionHandle

/// Gesture handler for manipulating stickers on the video preview canvas.
///
/// Wraps its content and intercepts drag, rotation, and magnification
/// gestures. Provides haptic feedback when snapping to center/edge guides.
struct StickerPositionHandle<Content: View>: View {

    // MARK: - Configuration

    /// Current position in normalized coordinates (0.0-1.0).
    let position: CGPoint

    /// Current rotation in radians.
    let rotation: Double

    /// Current scale factor.
    let scale: Double

    /// Size of the canvas (for coordinate conversion).
    let canvasSize: CGSize

    /// Whether snap guides are enabled.
    let snapEnabled: Bool

    /// Called when the transform changes during a gesture.
    let onTransformUpdate: (StickerTransformUpdate) -> Void

    /// Called when a gesture ends (for committing the change).
    let onTransformEnd: (() -> Void)?

    /// Called on double-tap (open editor panel).
    let onDoubleTap: (() -> Void)?

    /// The content (sticker visual) to wrap.
    @ViewBuilder let content: () -> Content

    // MARK: - State

    @State private var dragOffset: CGSize = .zero
    @State private var startRotation: Double = 0
    @State private var startScale: Double = 1.0
    @State private var didSnap: Bool = false

    // MARK: - Constants

    /// Threshold for snapping in normalized coordinates.
    static var snapThreshold: Double { 0.02 }

    // MARK: - Init

    init(
        position: CGPoint,
        rotation: Double,
        scale: Double,
        canvasSize: CGSize,
        snapEnabled: Bool = true,
        onTransformUpdate: @escaping (StickerTransformUpdate) -> Void,
        onTransformEnd: (() -> Void)? = nil,
        onDoubleTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.canvasSize = canvasSize
        self.snapEnabled = snapEnabled
        self.onTransformUpdate = onTransformUpdate
        self.onTransformEnd = onTransformEnd
        self.onDoubleTap = onDoubleTap
        self.content = content
    }

    // MARK: - Body

    var body: some View {
        content()
            .gesture(dragGesture)
            .gesture(magnificationGesture)
            .gesture(rotationGesture)
            .onTapGesture(count: 2) {
                onDoubleTap?()
            }
            .accessibilityLabel("Sticker")
            .accessibilityHint("Drag to move, pinch to scale, twist to rotate, double tap to edit")
            .accessibilityValue("Position \(Int(position.x * 100))% by \(Int(position.y * 100))%, scale \(Int(scale * 100))%")
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard canvasSize.width > 0, canvasSize.height > 0 else { return }

                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height

                var newX = position.x + dx
                var newY = position.y + dy

                if snapEnabled {
                    let snapped = applySnap(x: newX, y: newY)
                    newX = snapped.x
                    newY = snapped.y
                }

                onTransformUpdate(StickerTransformUpdate(
                    position: CGPoint(x: newX, y: newY)
                ))
            }
            .onEnded { _ in
                onTransformEnd?()
            }
    }

    // MARK: - Magnification Gesture

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = (startScale * value).clamped(to: 0.1...5.0)
                onTransformUpdate(StickerTransformUpdate(scale: newScale))
            }
            .onEnded { _ in
                startScale = scale
                onTransformEnd?()
            }
    }

    // MARK: - Rotation Gesture

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { angle in
                let newRotation = startRotation + angle.radians
                onTransformUpdate(StickerTransformUpdate(rotation: newRotation))
            }
            .onEnded { _ in
                startRotation = rotation
                onTransformEnd?()
            }
    }

    // MARK: - Snap Guides

    /// Apply snap guides to position, returning snapped coordinates.
    func applySnap(x: Double, y: Double) -> CGPoint {
        var snappedX = x
        var snappedY = y
        var didSnapNow = false

        let threshold = Self.snapThreshold

        // Snap to horizontal center
        if abs(x - 0.5) < threshold {
            snappedX = 0.5
            didSnapNow = true
        }

        // Snap to vertical center
        if abs(y - 0.5) < threshold {
            snappedY = 0.5
            didSnapNow = true
        }

        // Snap to left edge
        if abs(x) < threshold {
            snappedX = 0.0
            didSnapNow = true
        }

        // Snap to right edge
        if abs(x - 1.0) < threshold {
            snappedX = 1.0
            didSnapNow = true
        }

        // Snap to top edge
        if abs(y) < threshold {
            snappedY = 0.0
            didSnapNow = true
        }

        // Snap to bottom edge
        if abs(y - 1.0) < threshold {
            snappedY = 1.0
            didSnapNow = true
        }

        // Haptic feedback on snap transition
        if didSnapNow && !didSnap {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        }
        didSnap = didSnapNow

        return CGPoint(x: snappedX, y: snappedY)
    }
}

// MARK: - Comparable Clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
