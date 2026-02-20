// GestureCaptureEngine.swift
// LiquidEditor
//
// Captures gesture states during Smart Editing and converts them to keyframes.

import Foundation
import Observation
import CoreGraphics

// MARK: - GestureCaptureEngine

/// Captures and accumulates gesture states during Smart Editing playback.
///
/// Converts gesture end events into keyframes. Manages pinch (zoom),
/// pan (translate), and rotation gestures with alignment snapping.
///
/// Thread Safety: `@MainActor` -- all gesture handling is on the main thread.
@Observable
@MainActor
final class GestureCaptureEngine {

    // MARK: - Configuration

    static let minScale: Double = 0.1
    static let maxScale: Double = 5.0
    static let doubleTapZoom: Double = 2.0
    static let alignmentThreshold: Double = 0.02

    // MARK: - Properties

    /// Current accumulated transform from gestures.
    private(set) var currentTransform: VideoTransform = .identity

    /// Whether a gesture is currently in progress.
    private(set) var isCapturing = false

    /// Alignment state for visual guides.
    private(set) var isHorizontallyAligned = false
    private(set) var isVerticallyAligned = false

    /// Whether centered (both aligned).
    var isCentered: Bool { isHorizontallyAligned && isVerticallyAligned }

    // MARK: - Private State

    /// Transform at the start of current gesture sequence.
    private var baseTransform: VideoTransform = .identity

    /// Temporary gesture values (reset after each gesture ends).
    private var gestureScale: Double = 1.0
    private var gestureTranslation: CGPoint = .zero
    private var gestureRotation: Double = 0.0

    /// Track previous alignment state for haptic edge-trigger.
    private var wasHorizontallyAligned = false
    private var wasVerticallyAligned = false

    /// Callback for alignment snap haptic feedback.
    var onAlignmentSnap: (() -> Void)?

    // MARK: - Initialization

    init(initialTransform: VideoTransform? = nil) {
        if let t = initialTransform {
            currentTransform = t
            baseTransform = t
        }
    }

    // MARK: - Gesture Lifecycle

    /// Called when gesture begins -- resets accumulated values.
    func gestureStarted() {
        isCapturing = true
        gestureScale = 1.0
        gestureTranslation = .zero
        gestureRotation = 0.0
        baseTransform = currentTransform
    }

    /// Called when a pinch gesture changes (for zoom).
    func handlePinch(_ scale: Double) {
        isCapturing = true
        gestureScale = scale
        updateCurrentTransform()
    }

    /// Called when a pan gesture changes (for translation while zoomed).
    func handlePan(_ translationDelta: CGPoint) {
        isCapturing = true
        gestureTranslation = CGPoint(
            x: gestureTranslation.x + translationDelta.x,
            y: gestureTranslation.y + translationDelta.y
        )
        updateCurrentTransform()
    }

    /// Called when a rotation gesture changes.
    func handleRotation(_ angle: Double) {
        isCapturing = true
        gestureRotation = angle
        updateCurrentTransform()
    }

    /// Called when a double-tap occurs (quick zoom toggle).
    func handleDoubleTap() {
        if abs(currentTransform.scale - 1.0) < 0.1 {
            // Currently at 1x, zoom to 2x
            currentTransform = currentTransform.with(scale: Self.doubleTapZoom)
        } else {
            // Reset to 1x
            currentTransform = .identity
        }
        baseTransform = currentTransform
    }

    /// Called when all gestures end -- prepares for keyframe creation.
    func gestureEnded() {
        isCapturing = false
        baseTransform = currentTransform.clamped()

        gestureScale = 1.0
        gestureTranslation = .zero
        gestureRotation = 0.0

        wasHorizontallyAligned = false
        wasVerticallyAligned = false
    }

    // MARK: - Keyframe Creation

    /// Create a keyframe from the current transform state.
    func createKeyframe(
        at timestampMicros: TimeMicros,
        interpolation: InterpolationType = .easeInOut
    ) -> Keyframe {
        Keyframe(
            id: UUID().uuidString,
            timestampMicros: timestampMicros,
            transform: currentTransform.clamped(),
            interpolation: interpolation
        )
    }

    // MARK: - Transform Control

    /// Set the transform to a specific value.
    func setTransform(_ transform: VideoTransform) {
        currentTransform = transform
        baseTransform = transform
        gestureScale = 1.0
        gestureTranslation = .zero
        gestureRotation = 0.0
    }

    /// Reset to identity transform.
    func reset() {
        currentTransform = .identity
        baseTransform = .identity
        gestureScale = 1.0
        gestureTranslation = .zero
        gestureRotation = 0.0
        isCapturing = false
        isHorizontallyAligned = false
        isVerticallyAligned = false
    }

    // MARK: - Private

    private func updateCurrentTransform() {
        // Apply scale
        let newScale = min(max(baseTransform.scale * gestureScale, Self.minScale), Self.maxScale)

        // Apply translation (scaled by current zoom level)
        var newTx = baseTransform.translation.x + gestureTranslation.x / newScale
        var newTy = baseTransform.translation.y + gestureTranslation.y / newScale

        // Bounds restriction
        if newScale >= 1.0 {
            let limit = (newScale - 1.0) / 2.0
            newTx = min(max(newTx, -limit), limit)
            newTy = min(max(newTy, -limit), limit)
        } else {
            newTx = 0.0
            newTy = 0.0
        }

        // Alignment snapping detection
        let newHorizAligned = abs(newTy) < Self.alignmentThreshold
        let newVertAligned = abs(newTx) < Self.alignmentThreshold

        // Trigger haptic on edge crossing
        if newHorizAligned && !wasHorizontallyAligned {
            onAlignmentSnap?()
        }
        if newVertAligned && !wasVerticallyAligned {
            onAlignmentSnap?()
        }

        wasHorizontallyAligned = newHorizAligned
        wasVerticallyAligned = newVertAligned
        isHorizontallyAligned = newHorizAligned
        isVerticallyAligned = newVertAligned

        // Apply rotation
        let newRotation = baseTransform.rotation + gestureRotation

        currentTransform = VideoTransform(
            scale: newScale,
            translation: CGPoint(x: newTx, y: newTy),
            rotation: newRotation,
            anchor: baseTransform.anchor
        ).clamped()
    }
}
