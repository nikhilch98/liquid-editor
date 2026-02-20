// OverlayItemView.swift
// LiquidEditor
//
// Draggable, selectable overlay item rendered on the video preview canvas.
// Supports drag to reposition, tap to select, double-tap to edit,
// and pinch-to-scale. Position stored as normalized coordinates (0.0-1.0).

import SwiftUI

// MARK: - OverlayItemView

/// A positioned, draggable, selectable overlay item on the video preview.
///
/// Uses normalized position
/// coordinates (0.0-1.0) for resolution independence. The overlay is rendered
/// within a `GeometryReader` to get preview dimensions and converts normalized
/// positions to pixel coordinates.
///
/// Supports:
/// - Drag to reposition (single finger)
/// - Tap to select (shows dashed border)
/// - Double-tap to edit
/// - Pinch-to-scale (two fingers)
/// - Position stored as normalized coordinates (0.0-1.0)
struct OverlayItemView<Content: View>: View {

    // MARK: - Properties

    /// Normalized position (0.0-1.0) of the overlay center on the preview.
    let normalizedPosition: CGPoint

    /// Rotation angle in radians.
    var rotation: Double = 0.0

    /// Scale factor (1.0 = default size).
    var scale: Double = 1.0

    /// Opacity (0.0-1.0).
    var overlayOpacity: Double = 1.0

    /// Whether this overlay is currently selected.
    var isSelected: Bool = false

    /// Whether the overlay is interactive (can be dragged/selected).
    /// Set to false during playback to allow tap-through.
    var isInteractive: Bool = true

    /// The child view to render (text or sticker content).
    @ViewBuilder let content: () -> Content

    /// Called when the overlay is tapped (for selection).
    var onTap: (() -> Void)?

    /// Called when the overlay is double-tapped (for editing).
    var onDoubleTap: (() -> Void)?

    /// Called when the overlay is dragged to a new position.
    /// Provides the new normalized position.
    var onPositionChanged: ((CGPoint) -> Void)?

    /// Called when the overlay is scaled (pinch to resize).
    var onScaleChanged: ((Double) -> Void)?

    // MARK: - Gesture State

    /// The scale value captured at the start of a magnify gesture.
    /// Used as the base to multiply against the gesture's magnification.
    @State private var baseScaleOnGestureStart: Double = 1.0

    /// Tracks whether the magnify gesture has fired its initial haptic.
    @State private var magnifyGestureDidStart: Bool = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let previewWidth = geometry.size.width
            let previewHeight = geometry.size.height
            let pixelX = normalizedPosition.x * previewWidth
            let pixelY = normalizedPosition.y * previewHeight

            content()
                .rotationEffect(.radians(rotation))
                .scaleEffect(scale)
                .opacity(overlayOpacity.clampedValue(in: 0.0...1.0))
                .overlay {
                    if isSelected {
                        DashedSelectionBorder()
                    }
                }
                .position(x: pixelX, y: pixelY)
                .allowsHitTesting(isInteractive)
                .gesture(isInteractive ? combinedGesture(previewWidth: previewWidth, previewHeight: previewHeight) : nil)
                .onTapGesture(count: 2) {
                    guard isInteractive else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onDoubleTap?()
                }
                .onTapGesture(count: 1) {
                    guard isInteractive else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    onTap?()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Overlay item")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isInteractive ? "Double-tap to edit. Drag to reposition." : "")
        }
    }

    // MARK: - Gestures

    /// Drag gesture for single-finger repositioning.
    private func dragGesture(previewWidth: CGFloat, previewHeight: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard let onPositionChanged else { return }
                let normalizedDelta = CGPoint(
                    x: value.translation.width / previewWidth,
                    y: value.translation.height / previewHeight
                )
                let newPosition = CGPoint(
                    x: (normalizedPosition.x + normalizedDelta.x).clampedValue(in: 0.05...0.95),
                    y: (normalizedPosition.y + normalizedDelta.y).clampedValue(in: 0.05...0.95)
                )
                onPositionChanged(newPosition)
            }
            .onEnded { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    /// Magnify gesture for two-finger pinch-to-scale.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !magnifyGestureDidStart {
                    magnifyGestureDidStart = true
                    baseScaleOnGestureStart = scale
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                let newScale = (baseScaleOnGestureStart * value.magnification)
                    .clampedValue(in: 0.1...5.0)
                onScaleChanged?(newScale)
            }
            .onEnded { _ in
                magnifyGestureDidStart = false
            }
    }

    /// Combined gesture: drag and magnify run simultaneously so both
    /// single-finger movement and two-finger scaling work without conflict.
    private func combinedGesture(previewWidth: CGFloat, previewHeight: CGFloat) -> some Gesture {
        dragGesture(previewWidth: previewWidth, previewHeight: previewHeight)
            .simultaneously(with: magnifyGesture)
    }
}

// MARK: - DashedSelectionBorder

/// Dashed selection border drawn around an overlay when selected.
///
/// Uses `Canvas` to draw a dashed rectangle with corner handles,
/// matching the iOS selection appearance.
struct DashedSelectionBorder: View {

    /// Dash pattern: 6pt on, 4pt off.
    private static let dashWidth: CGFloat = 6
    private static let dashSpace: CGFloat = 4

    /// Corner handle size.
    private static let handleSize: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)

                // Dashed border
                let borderPath = Path(rect)
                context.stroke(
                    borderPath,
                    with: .color(Color(.systemBlue)),
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: [Self.dashWidth, Self.dashSpace]
                    )
                )

                // Corner handles
                let corners: [CGPoint] = [
                    CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.maxX, y: rect.maxY),
                ]

                for corner in corners {
                    let handleRect = CGRect(
                        x: corner.x - Self.handleSize / 2,
                        y: corner.y - Self.handleSize / 2,
                        width: Self.handleSize,
                        height: Self.handleSize
                    )
                    context.fill(Path(handleRect), with: .color(Color(.systemBlue)))
                }
            }
        }
        .allowsHitTesting(false)
        .padding(-4) // Extend border beyond content
    }
}

// MARK: - Comparable Clamping (OverlayItemView)

private extension Comparable {
    /// Clamps the value to the given closed range.
    /// Named distinctly to avoid shadowing system or third-party extensions.
    func clampedValue(in range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
