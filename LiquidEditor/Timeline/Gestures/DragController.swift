// DragController.swift
// LiquidEditor
//
// Clip drag controller with collision detection, snapping, and cross-track movement.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - DragStateType

/// State of a drag operation.
enum DragStateType: String, Sendable, Equatable {
    /// No drag in progress.
    case idle
    /// Drag started but not moved significantly.
    case pending
    /// Actively dragging.
    case dragging
    /// Validating drop position.
    case validating
    /// Drag completed successfully.
    case completed
    /// Drag cancelled.
    case cancelled
}

// MARK: - DraggedClipPreview

/// Preview information for a dragged clip.
struct DraggedClipPreview: Sendable, Equatable {
    /// Original clip being dragged.
    let originalClip: TimelineClip
    /// Preview start time (where it would be placed).
    let previewStartTime: TimeMicros
    /// Preview track ID (where it would be placed).
    let previewTrackId: String
    /// Time delta from original position.
    let timeDelta: TimeMicros
    /// Whether this position is valid (no collisions).
    let isValidPosition: Bool
    /// Collision info if position is invalid.
    let collisionInfo: String?

    /// Preview end time.
    var previewEndTime: TimeMicros { previewStartTime + originalClip.duration }

    /// Preview time range.
    var previewTimeRange: TimeRange { TimeRange(previewStartTime, previewEndTime) }

    /// Whether the clip moved to a different track.
    var changedTrack: Bool { previewTrackId != originalClip.trackId }

    /// Whether the clip moved in time.
    var changedTime: Bool { timeDelta != 0 }

    /// Whether any change occurred.
    var hasChanged: Bool { changedTrack || changedTime }

    /// Create the resulting clip if applied.
    func toResultClip() -> TimelineClip {
        originalClip.with(trackId: previewTrackId, startTime: previewStartTime)
    }
}

// MARK: - DragPreview

/// Overall drag preview state.
struct DragPreview: Sendable, Equatable {
    /// All clip previews in this drag operation.
    let clipPreviews: [DraggedClipPreview]
    /// Whether the overall drop position is valid.
    let isValid: Bool
    /// Snap time if snapping is active.
    let snapTime: TimeMicros?
    /// Snap target description (for UI feedback).
    let snapTarget: String?

    /// Empty preview (no drag).
    static let empty = DragPreview(clipPreviews: [], isValid: false, snapTime: nil, snapTarget: nil)

    /// Whether any clips are being dragged.
    var hasPreviews: Bool { !clipPreviews.isEmpty }

    /// Whether snapping is active.
    var hasSnap: Bool { snapTime != nil }
}

// MARK: - DragState

/// State of an ongoing drag operation.
struct DragState: Sendable, Equatable {
    /// Current state type.
    let type: DragStateType
    /// Clips being dragged.
    let draggedClipIds: Set<String>
    /// Initial pointer position.
    let startPosition: CGPoint
    /// Current pointer position.
    let currentPosition: CGPoint
    /// Initial time at drag start.
    let startTime: TimeMicros
    /// Current preview.
    let preview: DragPreview
    /// Whether the drag crossed the movement threshold.
    let exceededThreshold: Bool

    /// Idle state.
    static let idle = DragState(
        type: .idle,
        draggedClipIds: [],
        startPosition: .zero,
        currentPosition: .zero,
        startTime: 0,
        preview: .empty,
        exceededThreshold: false
    )

    /// Whether a drag is in progress.
    var isDragging: Bool { type == .dragging || type == .pending }

    /// Whether the drag has moved significantly.
    var hasMoved: Bool { exceededThreshold }

    /// Create copy with updated values.
    func with(
        type: DragStateType? = nil,
        draggedClipIds: Set<String>? = nil,
        startPosition: CGPoint? = nil,
        currentPosition: CGPoint? = nil,
        startTime: TimeMicros? = nil,
        preview: DragPreview? = nil,
        exceededThreshold: Bool? = nil
    ) -> DragState {
        DragState(
            type: type ?? self.type,
            draggedClipIds: draggedClipIds ?? self.draggedClipIds,
            startPosition: startPosition ?? self.startPosition,
            currentPosition: currentPosition ?? self.currentPosition,
            startTime: startTime ?? self.startTime,
            preview: preview ?? self.preview,
            exceededThreshold: exceededThreshold ?? self.exceededThreshold
        )
    }
}

// MARK: - SnapTarget

/// Snap target for magnetic snapping.
struct SnapTarget: Sendable, Equatable {
    /// Time position to snap to.
    let time: TimeMicros
    /// Description of snap target.
    let description: String
    /// Priority (lower = higher priority).
    let priority: Int

    init(time: TimeMicros, description: String, priority: Int = 0) {
        self.time = time
        self.description = description
        self.priority = priority
    }
}

// MARK: - ClipDragController

/// Controller for clip drag operations.
///
/// Manages drag state, collision detection, and snapping behavior.
@Observable @MainActor
final class ClipDragController {

    // MARK: - Constants

    /// Movement threshold before drag starts (pixels).
    static let dragThreshold: CGFloat = 8.0

    /// Snap distance in pixels.
    static let snapDistance: CGFloat = 12.0

    // MARK: - State

    /// Current drag state.
    private(set) var state: DragState = .idle

    /// All clips for collision detection.
    private var allClips: [TimelineClip] = []

    /// Tracks for track-based operations.
    private var tracks: [Track] = []

    /// Current viewport state.
    private var viewport: ViewportState = .initial()

    /// Snap targets (clip edges, playhead, markers, etc.).
    private var snapTargets: [SnapTarget] = []

    /// Callback when state changes.
    var onStateChanged: ((DragState) -> Void)?

    /// Whether a drag is in progress.
    var isDragging: Bool { state.isDragging }

    // MARK: - Context

    /// Update context for collision detection.
    func updateContext(
        clips: [TimelineClip]? = nil,
        tracks: [Track]? = nil,
        viewport: ViewportState? = nil,
        snapTargets: [SnapTarget]? = nil
    ) {
        if let clips { self.allClips = clips }
        if let tracks { self.tracks = tracks }
        if let viewport { self.viewport = viewport }
        if let snapTargets { self.snapTargets = snapTargets }
    }

    // MARK: - Drag Operations

    /// Start a drag operation.
    @discardableResult
    func startDrag(
        clipIds: Set<String>,
        position: CGPoint,
        time: TimeMicros
    ) -> DragState {
        guard !clipIds.isEmpty else { return .idle }

        state = DragState(
            type: .pending,
            draggedClipIds: clipIds,
            startPosition: position,
            currentPosition: position,
            startTime: time,
            preview: .empty,
            exceededThreshold: false
        )

        notifyStateChanged()
        return state
    }

    /// Update the drag position.
    @discardableResult
    func updateDrag(_ position: CGPoint) -> DragState {
        guard state.type != .idle else { return state }

        // Check if we've exceeded the threshold
        let dx = position.x - state.startPosition.x
        let dy = position.y - state.startPosition.y
        let distance = sqrt(dx * dx + dy * dy)
        let exceededThreshold = state.exceededThreshold || distance > Self.dragThreshold

        let newType: DragStateType = exceededThreshold ? .dragging : .pending

        // Calculate preview
        let preview = calculatePreview(position)

        // Provide haptic feedback on state transitions
        if !state.exceededThreshold && exceededThreshold {
            UISelectionFeedbackGenerator().selectionChanged()
        }

        // Provide haptic feedback on snap
        if preview.hasSnap && !state.preview.hasSnap {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        state = state.with(
            type: newType,
            currentPosition: position,
            preview: preview,
            exceededThreshold: exceededThreshold
        )

        notifyStateChanged()
        return state
    }

    /// End the drag operation.
    @discardableResult
    func endDrag() -> DragState {
        guard state.type != .idle else { return state }

        if !state.exceededThreshold || !state.preview.isValid {
            return cancelDrag()
        }

        // Complete the drag
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        state = state.with(type: .completed)
        notifyStateChanged()

        let result = state
        state = .idle
        return result
    }

    /// Cancel the drag operation.
    @discardableResult
    func cancelDrag() -> DragState {
        guard state.type != .idle else { return state }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        state = state.with(type: .cancelled)
        notifyStateChanged()

        let result = state
        state = .idle
        return result
    }

    // MARK: - Preview Calculation

    private func calculatePreview(_ position: CGPoint) -> DragPreview {
        guard !state.draggedClipIds.isEmpty else { return .empty }

        let draggedClips = allClips.filter { state.draggedClipIds.contains($0.id) }
        guard !draggedClips.isEmpty else { return .empty }

        // Calculate time delta from position delta
        let pixelDelta = position.x - state.startPosition.x
        var timeDelta = TimeMicros((viewport.microsPerPixel * Double(pixelDelta)).rounded())

        // Find target track from Y position
        let targetTrack = findTrackAtY(position.y)
        let targetTrackId = targetTrack?.id ?? draggedClips[0].trackId

        // Try to snap
        let (snappedDelta, snapTarget) = trySnap(draggedClips, timeDelta: timeDelta)
        timeDelta = snappedDelta

        // Generate previews and check collisions
        var previews: [DraggedClipPreview] = []
        var allValid = true

        for clip in draggedClips {
            let previewStartTime = clip.startTime + timeDelta
            let previewTrackId = targetTrackId

            let collision = checkCollision(
                clipId: clip.id,
                startTime: previewStartTime,
                endTime: previewStartTime + clip.duration,
                trackId: previewTrackId
            )

            let preview = DraggedClipPreview(
                originalClip: clip,
                previewStartTime: previewStartTime,
                previewTrackId: previewTrackId,
                timeDelta: timeDelta,
                isValidPosition: collision == nil && previewStartTime >= 0,
                collisionInfo: collision
            )

            previews.append(preview)

            if !preview.isValidPosition {
                allValid = false
            }
        }

        return DragPreview(
            clipPreviews: previews,
            isValid: allValid,
            snapTime: snapTarget?.time,
            snapTarget: snapTarget?.description
        )
    }

    private func findTrackAtY(_ y: CGFloat) -> Track? {
        guard !tracks.isEmpty else { return nil }

        let contentY = y - viewport.rulerHeight + viewport.verticalOffset
        guard contentY >= 0 else { return nil }

        var accumulatedHeight: Double = 0
        for track in tracks {
            accumulatedHeight += track.effectiveHeight
            if contentY < accumulatedHeight {
                return track
            }
        }

        return tracks.last
    }

    private func trySnap(
        _ clips: [TimelineClip],
        timeDelta: TimeMicros
    ) -> (TimeMicros, SnapTarget?) {
        guard !snapTargets.isEmpty else { return (timeDelta, nil) }

        let snapThresholdTime = TimeMicros((viewport.microsPerPixel * Double(Self.snapDistance)).rounded())

        var bestSnapTarget: SnapTarget?
        var bestDelta = timeDelta
        var bestDistance = snapThresholdTime + 1

        for clip in clips {
            let previewStart = clip.startTime + timeDelta
            let previewEnd = previewStart + clip.duration

            for target in snapTargets {
                // Try snapping start to target
                let startDistance = abs(previewStart - target.time)
                if startDistance < bestDistance {
                    bestDistance = startDistance
                    bestSnapTarget = target
                    bestDelta = target.time - clip.startTime
                }

                // Try snapping end to target
                let endDistance = abs(previewEnd - target.time)
                if endDistance < bestDistance {
                    bestDistance = endDistance
                    bestSnapTarget = target
                    bestDelta = target.time - clip.endTime
                }
            }
        }

        if let snap = bestSnapTarget, bestDistance <= snapThresholdTime {
            return (bestDelta, snap)
        }

        return (timeDelta, nil)
    }

    private func checkCollision(
        clipId: String,
        startTime: TimeMicros,
        endTime: TimeMicros,
        trackId: String
    ) -> String? {
        // Check for negative start time
        guard startTime >= 0 else {
            return "Cannot place before timeline start"
        }

        // Check collision with other clips on the same track
        for other in allClips {
            // Skip self
            guard other.id != clipId else { continue }

            // Skip clips being dragged together
            guard !state.draggedClipIds.contains(other.id) else { continue }

            // Skip clips on different tracks
            guard other.trackId == trackId else { continue }

            // Check for overlap
            if startTime < other.endTime && endTime > other.startTime {
                return "Overlaps with \(other.label ?? other.id)"
            }
        }

        return nil // No collision
    }

    private func notifyStateChanged() {
        onStateChanged?(state)
    }
}
