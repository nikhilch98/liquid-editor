// TimelineZoomController.swift
// LiquidEditor
//
// Pinch-to-zoom with anchor point preservation for the timeline.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - ZoomStateType

/// State of a zoom operation.
enum ZoomStateType: String, Sendable, Equatable {
    /// No zoom in progress.
    case idle
    /// Pinch zoom gesture active.
    case pinching
    /// Animated zoom in progress.
    case animating
}

// MARK: - ZoomState

/// State of an ongoing zoom operation.
struct ZoomState: Sendable, Equatable {
    /// Current state type.
    let type: ZoomStateType
    /// Initial scale when zoom started.
    let initialScale: Double
    /// Current scale factor (relative to initial).
    let currentScale: Double
    /// Focal point of the zoom (in viewport coordinates).
    let focalPoint: CGPoint
    /// Time at focal point (for anchor preservation).
    let anchorTime: TimeMicros
    /// Initial microsPerPixel when zoom started.
    let initialMicrosPerPixel: Double
    /// Current microsPerPixel.
    let currentMicrosPerPixel: Double

    /// Idle state.
    static let idle = ZoomState(
        type: .idle,
        initialScale: 1.0,
        currentScale: 1.0,
        focalPoint: .zero,
        anchorTime: 0,
        initialMicrosPerPixel: ViewportState.defaultMicrosPerPixel,
        currentMicrosPerPixel: ViewportState.defaultMicrosPerPixel
    )

    /// Whether a zoom is in progress.
    var isZooming: Bool { type != .idle }

    /// Whether zoom is animating.
    var isAnimating: Bool { type == .animating }

    /// Relative scale change from initial.
    var scaleChange: Double { currentScale / initialScale }

    /// Create copy with updated values.
    func with(
        type: ZoomStateType? = nil,
        initialScale: Double? = nil,
        currentScale: Double? = nil,
        focalPoint: CGPoint? = nil,
        anchorTime: TimeMicros? = nil,
        initialMicrosPerPixel: Double? = nil,
        currentMicrosPerPixel: Double? = nil
    ) -> ZoomState {
        ZoomState(
            type: type ?? self.type,
            initialScale: initialScale ?? self.initialScale,
            currentScale: currentScale ?? self.currentScale,
            focalPoint: focalPoint ?? self.focalPoint,
            anchorTime: anchorTime ?? self.anchorTime,
            initialMicrosPerPixel: initialMicrosPerPixel ?? self.initialMicrosPerPixel,
            currentMicrosPerPixel: currentMicrosPerPixel ?? self.currentMicrosPerPixel
        )
    }
}

// MARK: - TimelineZoomController

/// Controller for timeline zoom operations.
///
/// Manages pinch-to-zoom gestures and animated zooming with proper
/// anchor point preservation.
@Observable @MainActor
final class TimelineZoomController {

    // MARK: - Constants

    /// Minimum scale factor for pinch zoom.
    static let minScaleFactor: Double = 0.1

    /// Maximum scale factor for pinch zoom.
    static let maxScaleFactor: Double = 10.0

    /// Default animation duration.
    static let defaultAnimationDuration: TimeInterval = 0.3

    // MARK: - State

    /// Current zoom state.
    private(set) var state: ZoomState = .idle

    /// Current viewport state.
    private var viewport: ViewportState = .initial()

    /// Callback when state changes.
    var onStateChanged: ((ZoomState) -> Void)?

    /// Callback when viewport should update.
    var onViewportChanged: ((ViewportState) -> Void)?

    /// Whether a zoom is in progress.
    var isZooming: Bool { state.isZooming }

    // MARK: - Configuration

    /// Update the current viewport state.
    func updateViewport(_ vp: ViewportState) {
        viewport = vp
    }

    // MARK: - Pinch Zoom

    /// Start a pinch zoom gesture.
    @discardableResult
    func startZoom(scale: Double, focalPoint: CGPoint) -> ZoomState {
        let anchorTime = viewport.absolutePixelXToTime(focalPoint.x)

        state = ZoomState(
            type: .pinching,
            initialScale: scale,
            currentScale: scale,
            focalPoint: focalPoint,
            anchorTime: anchorTime,
            initialMicrosPerPixel: viewport.microsPerPixel,
            currentMicrosPerPixel: viewport.microsPerPixel
        )

        onStateChanged?(state)
        return state
    }

    /// Update the pinch zoom gesture.
    @discardableResult
    func updateZoom(scale: Double, focalPoint: CGPoint? = nil) -> ViewportState {
        guard state.type == .pinching else { return viewport }

        // Calculate new microsPerPixel based on scale change
        let scaleChange = scale / state.initialScale
        let newMicrosPerPixel = state.initialMicrosPerPixel / scaleChange

        // Clamp to limits
        let clampedMicrosPerPixel = min(
            max(newMicrosPerPixel, ViewportState.minMicrosPerPixel),
            ViewportState.maxMicrosPerPixel
        )

        // Check if we hit a limit
        let hitMinLimit = clampedMicrosPerPixel == ViewportState.minMicrosPerPixel
        let hitMaxLimit = clampedMicrosPerPixel == ViewportState.maxMicrosPerPixel
        let wasAtLimit = state.currentMicrosPerPixel == ViewportState.minMicrosPerPixel ||
                         state.currentMicrosPerPixel == ViewportState.maxMicrosPerPixel

        // Haptic feedback when hitting limits
        if (hitMinLimit || hitMaxLimit) && !wasAtLimit {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }

        state = state.with(
            currentScale: scale,
            focalPoint: focalPoint ?? state.focalPoint,
            currentMicrosPerPixel: clampedMicrosPerPixel
        )

        // Calculate new viewport maintaining anchor point
        viewport = viewport.zoomCenteredOnTime(clampedMicrosPerPixel, centerTime: state.anchorTime)

        onStateChanged?(state)
        onViewportChanged?(viewport)

        return viewport
    }

    /// End the pinch zoom gesture.
    @discardableResult
    func endZoom() -> ViewportState {
        guard state.type == .pinching else { return viewport }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        state = ZoomState.idle.with(currentMicrosPerPixel: viewport.microsPerPixel)
        onStateChanged?(state)

        return viewport
    }

    // MARK: - Programmatic Zoom

    /// Zoom to a specific microsPerPixel value (immediate, no animation).
    @discardableResult
    func zoomTo(
        targetMicrosPerPixel: Double,
        anchorTime: TimeMicros? = nil
    ) -> ViewportState {
        let clamped = min(
            max(targetMicrosPerPixel, ViewportState.minMicrosPerPixel),
            ViewportState.maxMicrosPerPixel
        )

        if let anchorTime {
            viewport = viewport.zoomCenteredOnTime(clamped, centerTime: anchorTime)
        } else {
            viewport = viewport.zoomCenteredOnViewport(clamped)
        }

        state = ZoomState.idle.with(currentMicrosPerPixel: clamped)
        onStateChanged?(state)
        onViewportChanged?(viewport)

        return viewport
    }

    /// Zoom in by a factor.
    @discardableResult
    func zoomIn(factor: Double = 2.0, anchorTime: TimeMicros? = nil) -> ViewportState {
        let targetMicrosPerPixel = viewport.microsPerPixel / factor
        return zoomTo(targetMicrosPerPixel: targetMicrosPerPixel, anchorTime: anchorTime)
    }

    /// Zoom out by a factor.
    @discardableResult
    func zoomOut(factor: Double = 2.0, anchorTime: TimeMicros? = nil) -> ViewportState {
        let targetMicrosPerPixel = viewport.microsPerPixel * factor
        return zoomTo(targetMicrosPerPixel: targetMicrosPerPixel, anchorTime: anchorTime)
    }

    /// Zoom to fit all content in the viewport.
    @discardableResult
    func zoomToFitAll(totalDuration: TimeMicros, marginPercent: Double = 0.05) -> ViewportState {
        guard totalDuration > 0 else { return viewport }

        let targetMicrosPerPixel = viewport.zoomToFitDuration(totalDuration, margin: marginPercent)
        return zoomTo(targetMicrosPerPixel: targetMicrosPerPixel, anchorTime: totalDuration / 2)
    }

    /// Zoom to fit a selection in the viewport.
    @discardableResult
    func zoomToSelection(startTime: TimeMicros, endTime: TimeMicros, marginPercent: Double = 0.1) -> ViewportState {
        let duration = endTime - startTime
        guard duration > 0 else { return viewport }

        let targetMicrosPerPixel = viewport.zoomToFitDuration(duration, margin: marginPercent)
        let centerTime = startTime + duration / 2
        return zoomTo(targetMicrosPerPixel: targetMicrosPerPixel, anchorTime: centerTime)
    }

    /// Zoom to fit a specific time range.
    @discardableResult
    func zoomToTimeRange(_ range: TimeRange, marginPercent: Double = 0.1) -> ViewportState {
        zoomToSelection(startTime: range.start, endTime: range.end, marginPercent: marginPercent)
    }

    /// Reset zoom to default level.
    @discardableResult
    func resetZoom(anchorTime: TimeMicros? = nil) -> ViewportState {
        zoomTo(targetMicrosPerPixel: ViewportState.defaultMicrosPerPixel, anchorTime: anchorTime)
    }

    // MARK: - Cleanup

    func dispose() {
        // No display link to clean up in zoom controller
    }
}
