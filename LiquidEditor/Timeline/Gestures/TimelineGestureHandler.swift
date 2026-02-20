// TimelineGestureHandler.swift
// LiquidEditor
//
// Central gesture coordinator for all timeline interactions.
// Coordinates scrolling, pinch-to-zoom, clip dragging, trim handles,
// selection (tap, double-tap, long-press), and marquee selection.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - GestureState

/// Current gesture state of the timeline.
enum GestureState: String, Sendable, Equatable {
    /// No gesture in progress.
    case idle
    /// Horizontal scrolling.
    case scrolling
    /// Pinch-to-zoom.
    case zooming
    /// Dragging clip(s).
    case dragging
    /// Trimming clip edge.
    case trimming
    /// Dragging playhead.
    case scrubbingPlayhead
    /// Marquee selection.
    case marqueeSelecting
    /// Reordering clips via card mode.
    case reordering
}

// MARK: - DoubleTapAction

/// Double-tap action result.
enum DoubleTapAction: String, Sendable, Equatable {
    /// Open clip editor.
    case openClipEditor
    /// Open marker editor.
    case openMarkerEditor
    /// Zoom to fit clip.
    case zoomToFitClip
    /// No action.
    case none
}

// MARK: - TimelineGestureEvent

/// Event data for timeline gesture events.
struct TimelineGestureEvent: Sendable, Equatable {
    /// Current gesture state.
    let state: GestureState
    /// Hit test result if applicable.
    let hitResult: HitTestResult?
    /// Viewport state.
    let viewport: ViewportState
    /// Selection state.
    let selection: SelectionState
    /// Drag preview if dragging.
    let dragPreview: DragPreview?
    /// Trim preview if trimming.
    let trimPreview: TrimPreview?
    /// Marquee rect if marquee selecting.
    let marqueeRect: CGRect?
    /// Playhead position if scrubbing.
    let playheadPosition: TimeMicros?
}

// MARK: - TimelineGestureHandler

/// Central handler for all timeline gestures.
///
/// Coordinates between specialized controllers and manages state transitions.
@Observable @MainActor
final class TimelineGestureHandler {

    // MARK: - Sub-controllers

    /// Scroll controller.
    let scrollController = TimelineScrollController()

    /// Zoom controller.
    let zoomController = TimelineZoomController()

    /// Drag controller for clips.
    let dragController = ClipDragController()

    /// Trim controller for clip edges.
    let trimController = TrimController()

    // MARK: - State

    /// Current gesture state.
    private(set) var gestureState: GestureState = .idle

    /// Current viewport state.
    private var _viewport: ViewportState = .initial()

    /// Current selection state.
    private var _selection: SelectionState = .empty

    /// All clips for hit testing.
    private var clips: [TimelineClip] = []

    /// All markers for hit testing.
    private var markers: [TimelineMarker] = []

    /// All tracks.
    private var tracks: [Track] = []

    /// Track Y positions.
    private var trackYPositions: [String: CGFloat] = [:]

    /// Track heights.
    private var trackHeights: [String: CGFloat] = [:]

    /// Current playhead position.
    private(set) var playheadPosition: TimeMicros = 0

    /// Maximum timeline duration.
    private var maxDuration: TimeMicros = 0

    /// Whether playhead is being scrubbed.
    private var isScrubbing = false

    /// Snap targets for various operations.
    private var snapTargets: [SnapTarget] = []

    /// Snap times for trim operations.
    private var trimSnapTargets: [TimeMicros] = []

    /// Marquee start position.
    private var marqueeStart: CGPoint?

    /// Marquee current position.
    private var marqueeCurrent: CGPoint?

    /// Last tap position for double-tap detection.
    private var lastTapPosition: CGPoint?

    /// Last tap time for double-tap detection.
    private var lastTapTime: Date?

    /// Double-tap timer for clearing state.
    private var doubleTapWorkItem: DispatchWorkItem?

    // MARK: - Constants

    /// Double-tap time window.
    static let doubleTapWindow: TimeInterval = 0.3

    /// Double-tap distance threshold.
    static let doubleTapDistance: CGFloat = 40.0

    // MARK: - Callbacks

    /// Called when gesture event occurs.
    var onGestureEvent: ((TimelineGestureEvent) -> Void)?

    /// Called when viewport changes.
    var onViewportChanged: ((ViewportState) -> Void)?

    /// Called when selection changes.
    var onSelectionChanged: ((SelectionState) -> Void)?

    /// Called when playhead position changes (during scrub).
    var onPlayheadChanged: ((TimeMicros) -> Void)?

    /// Called on double-tap.
    var onDoubleTap: ((DoubleTapAction, String?) -> Void)?

    /// Called when clip reorder mode starts (long press on clip).
    var onReorderStart: ((String, String, CGPoint) -> Void)?

    /// Called when drag position updates during reorder.
    var onReorderUpdate: ((CGPoint) -> Void)?

    /// Called when reorder drag ends.
    var onReorderEnd: (() -> Void)?

    /// Called when drag completes.
    var onDragComplete: ((DragState) -> Void)?

    /// Called when trim completes.
    var onTrimComplete: ((TrimState) -> Void)?

    // MARK: - Getters

    /// Current viewport.
    var viewport: ViewportState { _viewport }

    /// Current selection.
    var selection: SelectionState { _selection }

    /// Whether a gesture is in progress.
    var hasActiveGesture: Bool { gestureState != .idle }

    // MARK: - Initialization

    /// Initialize the gesture handler and wire up sub-controller callbacks.
    func initialize() {
        scrollController.onViewportChanged = { [weak self] vp in
            self?.handleViewportChanged(vp)
        }
        zoomController.onViewportChanged = { [weak self] vp in
            self?.handleViewportChanged(vp)
        }
        dragController.onStateChanged = { [weak self] dragState in
            self?.handleDragStateChanged(dragState)
        }
        trimController.onStateChanged = { [weak self] trimState in
            self?.handleTrimStateChanged(trimState)
        }
    }

    /// Update context data.
    func updateContext(
        viewport: ViewportState? = nil,
        selection: SelectionState? = nil,
        clips: [TimelineClip]? = nil,
        markers: [TimelineMarker]? = nil,
        tracks: [Track]? = nil,
        trackYPositions: [String: CGFloat]? = nil,
        trackHeights: [String: CGFloat]? = nil,
        playheadPosition: TimeMicros? = nil,
        maxDuration: TimeMicros? = nil,
        snapTargets: [SnapTarget]? = nil,
        trimSnapTargets: [TimeMicros]? = nil
    ) {
        if let viewport {
            self._viewport = viewport
            scrollController.updateViewport(viewport)
            zoomController.updateViewport(viewport)
        }
        if let selection { self._selection = selection }
        if let clips { self.clips = clips }
        if let markers { self.markers = markers }
        if let tracks { self.tracks = tracks }
        if let trackYPositions { self.trackYPositions = trackYPositions }
        if let trackHeights { self.trackHeights = trackHeights }
        if let playheadPosition { self.playheadPosition = playheadPosition }
        if let maxDuration {
            self.maxDuration = maxDuration
            scrollController.updateMaxScrollPosition(maxDuration)
        }
        if let snapTargets { self.snapTargets = snapTargets }
        if let trimSnapTargets { self.trimSnapTargets = trimSnapTargets }

        dragController.updateContext(
            clips: self.clips,
            tracks: self.tracks,
            viewport: self._viewport,
            snapTargets: self.snapTargets
        )

        trimController.updateContext(
            clips: self.clips,
            viewport: self._viewport,
            snapTargets: self.trimSnapTargets
        )
    }

    // MARK: - Gesture Handlers

    /// Handle scale gesture start (pinch zoom or scroll).
    func onScaleStart(position: CGPoint, pointerCount: Int) {
        guard gestureState == .idle else { return }

        if pointerCount >= 2 {
            // Pinch zoom
            gestureState = .zooming
            zoomController.startZoom(scale: 1.0, focalPoint: position)
        } else {
            // Single finger - could be scroll, drag, or trim
            let hitResult = performHitTest(position)

            if hitResult.isPlayhead {
                gestureState = .scrubbingPlayhead
                isScrubbing = true
                UISelectionFeedbackGenerator().selectionChanged()
            } else if hitResult.isTrimHandle {
                gestureState = .trimming
                let trimType: TrimType = hitResult.type == .trimHandleLeft ? .head : .tail
                trimController.startTrim(
                    clipId: hitResult.elementId!,
                    trimType: trimType,
                    position: position
                )
            } else if hitResult.isClip && _selection.isClipSelected(hitResult.elementId!) {
                gestureState = .dragging
                dragController.startDrag(
                    clipIds: _selection.selectedClipIds,
                    position: position,
                    time: hitResult.hitTime
                )
            } else if hitResult.isRuler {
                gestureState = .scrubbingPlayhead
                isScrubbing = true
                playheadPosition = hitResult.hitTime
                onPlayheadChanged?(playheadPosition)
                UISelectionFeedbackGenerator().selectionChanged()
            } else {
                gestureState = .scrolling
                scrollController.startScroll()
            }
        }

        notifyGestureEvent()
    }

    /// Handle scale gesture update.
    func onScaleUpdate(position: CGPoint, scale: Double, focalPointDelta: CGPoint) {
        switch gestureState {
        case .zooming:
            zoomController.updateZoom(scale: scale, focalPoint: position)

        case .scrolling:
            scrollController.scroll(-Double(focalPointDelta.x))

        case .dragging:
            dragController.updateDrag(position)

        case .trimming:
            trimController.updateTrim(position)

        case .scrubbingPlayhead:
            playheadPosition = _viewport.absolutePixelXToTime(position.x)
            if playheadPosition < 0 { playheadPosition = 0 }
            if playheadPosition > maxDuration { playheadPosition = maxDuration }
            onPlayheadChanged?(playheadPosition)

        case .marqueeSelecting:
            marqueeCurrent = position
            updateMarqueeSelection()

        default:
            break
        }

        notifyGestureEvent()
    }

    /// Handle scale gesture end.
    func onScaleEnd(velocityX: Double) {
        switch gestureState {
        case .zooming:
            zoomController.endZoom()

        case .scrolling:
            scrollController.endScroll(velocityPixelsPerSecond: -velocityX)

        case .dragging:
            let result = dragController.endDrag()
            if result.type == .completed {
                onDragComplete?(result)
            }

        case .trimming:
            let result = trimController.endTrim()
            if result.type == .completed {
                onTrimComplete?(result)
            }

        case .scrubbingPlayhead:
            isScrubbing = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .marqueeSelecting:
            endMarqueeSelection()

        default:
            break
        }

        gestureState = .idle
        notifyGestureEvent()
    }

    /// Handle tap down.
    func onTapDown(position: CGPoint) {
        let now = Date()

        // Check for double-tap
        if let lastPos = lastTapPosition, let lastTime = lastTapTime {
            let timeSinceLast = now.timeIntervalSince(lastTime)
            let dx = position.x - lastPos.x
            let dy = position.y - lastPos.y
            let distanceFromLast = sqrt(dx * dx + dy * dy)

            if timeSinceLast < Self.doubleTapWindow && distanceFromLast < Self.doubleTapDistance {
                handleDoubleTap(position)
                lastTapPosition = nil
                lastTapTime = nil
                return
            }
        }

        // Record tap for potential double-tap
        lastTapPosition = position
        lastTapTime = now

        // Clear after window expires
        doubleTapWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.lastTapPosition = nil
            self?.lastTapTime = nil
        }
        doubleTapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleTapWindow, execute: workItem)
    }

    /// Handle tap up (selection).
    func onTapUp(position: CGPoint) {
        let hitResult = performHitTest(position)

        if hitResult.isClip {
            UISelectionFeedbackGenerator().selectionChanged()

            if !_selection.isClipSelected(hitResult.elementId!) {
                _selection = _selection.selectClip(hitResult.elementId!)
                onSelectionChanged?(_selection)
            }
        } else if hitResult.isMarker {
            UISelectionFeedbackGenerator().selectionChanged()
            _selection = _selection.selectMarker(hitResult.elementId!)
            onSelectionChanged?(_selection)
        } else if hitResult.isRuler {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            playheadPosition = hitResult.hitTime
            onPlayheadChanged?(playheadPosition)
        } else if hitResult.type == .empty {
            if _selection.hasSelection {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                _selection = _selection.clearClipSelection()
                onSelectionChanged?(_selection)
            }
        }

        notifyGestureEvent()
    }

    /// Handle long press start (reorder mode or marquee).
    func onLongPressStart(position: CGPoint) {
        let hitResult = performHitTest(position)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if hitResult.isClip {
            gestureState = .reordering

            if !_selection.isClipSelected(hitResult.elementId!) {
                _selection = _selection.selectClip(hitResult.elementId!)
                onSelectionChanged?(_selection)
            }

            let clip = clips.first { $0.id == hitResult.elementId }
            if let clip {
                onReorderStart?(hitResult.elementId!, clip.trackId, position)
            }
        } else if hitResult.type == .empty {
            gestureState = .marqueeSelecting
            marqueeStart = position
            marqueeCurrent = position
            _selection = _selection.startMarquee(position)
            onSelectionChanged?(_selection)
        }

        notifyGestureEvent()
    }

    /// Handle long press move (reorder or marquee update).
    func onLongPressMoveUpdate(position: CGPoint) {
        if gestureState == .reordering {
            onReorderUpdate?(position)
        } else if gestureState == .marqueeSelecting {
            marqueeCurrent = position
            updateMarqueeSelection()
            notifyGestureEvent()
        }
    }

    /// Handle long press end.
    func onLongPressEnd() {
        if gestureState == .reordering {
            onReorderEnd?()
        } else if gestureState == .marqueeSelecting {
            endMarqueeSelection()
        }

        gestureState = .idle
        notifyGestureEvent()
    }

    // MARK: - Private Methods

    private func performHitTest(_ position: CGPoint) -> HitTestResult {
        let hitTester = TimelineHitTester(
            clips: clips,
            markers: markers,
            viewport: _viewport,
            playheadPosition: playheadPosition,
            trackHeights: trackHeights,
            trackYPositions: trackYPositions,
            playheadActive: isScrubbing
        )
        return hitTester.hitTest(position)
    }

    private func handleDoubleTap(_ position: CGPoint) {
        let hitResult = performHitTest(position)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if hitResult.isClip {
            onDoubleTap?(.openClipEditor, hitResult.elementId)
        } else if hitResult.isMarker {
            onDoubleTap?(.openMarkerEditor, hitResult.elementId)
        } else {
            onDoubleTap?(.none, nil)
        }
    }

    private func updateMarqueeSelection() {
        guard let start = marqueeStart, let current = marqueeCurrent else { return }

        _selection = _selection.updateMarquee(current)

        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        let hitTester = TimelineHitTester(
            clips: clips,
            markers: markers,
            viewport: _viewport,
            playheadPosition: playheadPosition,
            trackHeights: trackHeights,
            trackYPositions: trackYPositions
        )

        let clipsInRect = hitTester.findClipsInRect(rect)
        let clipIds = Set(clipsInRect.map(\.id))

        _selection = _selection.selectClips(clipIds)
        onSelectionChanged?(_selection)
    }

    private func endMarqueeSelection() {
        _selection = _selection.endMarquee()
        marqueeStart = nil
        marqueeCurrent = nil
        onSelectionChanged?(_selection)
    }

    private func handleViewportChanged(_ vp: ViewportState) {
        _viewport = vp
        onViewportChanged?(vp)
        notifyGestureEvent()
    }

    private func handleDragStateChanged(_ dragState: DragState) {
        notifyGestureEvent()
    }

    private func handleTrimStateChanged(_ trimState: TrimState) {
        notifyGestureEvent()
    }

    private func notifyGestureEvent() {
        let event = TimelineGestureEvent(
            state: gestureState,
            hitResult: nil,
            viewport: _viewport,
            selection: _selection,
            dragPreview: gestureState == .dragging ? dragController.state.preview : nil,
            trimPreview: gestureState == .trimming ? trimController.state.preview : nil,
            marqueeRect: gestureState == .marqueeSelecting ? _selection.marqueeRect : nil,
            playheadPosition: gestureState == .scrubbingPlayhead ? playheadPosition : nil
        )
        onGestureEvent?(event)
    }

    /// Cancel any active gesture.
    func cancelGesture() {
        switch gestureState {
        case .scrolling:
            scrollController.stopMomentum()
        case .dragging:
            dragController.cancelDrag()
        case .trimming:
            trimController.cancelTrim()
        case .marqueeSelecting:
            endMarqueeSelection()
        case .scrubbingPlayhead:
            isScrubbing = false
        default:
            break
        }

        gestureState = .idle
        notifyGestureEvent()
    }

    /// Dispose resources.
    func dispose() {
        doubleTapWorkItem?.cancel()
        scrollController.dispose()
        zoomController.dispose()
    }
}
