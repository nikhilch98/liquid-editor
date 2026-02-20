// HitTesting.swift
// LiquidEditor
//
// Priority-based hit detection for timeline elements.
// Priority order: playhead > ruler > trim handles > clips > markers > empty
//

import Foundation
import CoreGraphics

// MARK: - Constants

/// Touch target size for trim handles (20 points).
let kHandleTouchTarget: CGFloat = 20.0

/// Touch target size for playhead.
let kPlayheadTouchTarget: CGFloat = 24.0

/// Touch target size for markers.
let kMarkerTouchTarget: CGFloat = 16.0

// MARK: - HitTestType

/// Type of element hit during hit testing.
enum HitTestType: String, Sendable, Equatable, Hashable {
    /// Playhead was hit.
    case playhead
    /// Ruler area was hit.
    case ruler
    /// Left (head) trim handle was hit.
    case trimHandleLeft
    /// Right (tail) trim handle was hit.
    case trimHandleRight
    /// Clip body was hit.
    case clip
    /// Marker was hit.
    case marker
    /// Empty area (no element).
    case empty
}

// MARK: - HitTestResult

/// Result of a hit test operation.
struct HitTestResult: Equatable, Hashable, Sendable {
    /// Type of element that was hit.
    let type: HitTestType

    /// ID of the hit element (clip, marker).
    let elementId: String?

    /// Track ID if a track element was hit.
    let trackId: String?

    /// Time at hit position.
    let hitTime: TimeMicros

    /// Original hit position in pixels.
    let hitPosition: CGPoint

    /// Distance from the center of the hit element (for prioritization).
    let distanceFromCenter: CGFloat

    init(
        type: HitTestType,
        elementId: String? = nil,
        trackId: String? = nil,
        hitTime: TimeMicros,
        hitPosition: CGPoint,
        distanceFromCenter: CGFloat = 0.0
    ) {
        self.type = type
        self.elementId = elementId
        self.trackId = trackId
        self.hitTime = hitTime
        self.hitPosition = hitPosition
        self.distanceFromCenter = distanceFromCenter
    }

    /// Empty hit result.
    static func empty(hitTime: TimeMicros, hitPosition: CGPoint) -> HitTestResult {
        HitTestResult(
            type: .empty,
            hitTime: hitTime,
            hitPosition: hitPosition
        )
    }

    // MARK: - Convenience Queries

    /// Check if hit was on an element.
    var hasHit: Bool { type != .empty }

    /// Check if hit was on a trim handle.
    var isTrimHandle: Bool {
        type == .trimHandleLeft || type == .trimHandleRight
    }

    /// Check if hit was on the playhead.
    var isPlayhead: Bool { type == .playhead }

    /// Check if hit was on the ruler.
    var isRuler: Bool { type == .ruler }

    /// Check if hit was on a clip.
    var isClip: Bool { type == .clip }

    /// Check if hit was on a marker.
    var isMarker: Bool { type == .marker }

    // MARK: - Equatable & Hashable

    static func == (lhs: HitTestResult, rhs: HitTestResult) -> Bool {
        lhs.type == rhs.type &&
        lhs.elementId == rhs.elementId &&
        lhs.trackId == rhs.trackId &&
        lhs.hitTime == rhs.hitTime
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(elementId)
        hasher.combine(trackId)
        hasher.combine(hitTime)
    }
}

// MARK: - TrimHandleInfo

/// Trim handle information for clip hit testing.
struct TrimHandleInfo: Sendable, Equatable {
    /// Clip this handle belongs to.
    let clip: TimelineClip

    /// Whether this is the left (head) handle.
    let isLeftHandle: Bool

    /// Pixel rect of the handle area.
    let handleRect: CGRect
}

// MARK: - TimelineHitTester

/// Hit tester for timeline elements.
///
/// Performs hit testing against timeline elements with proper priority ordering
/// and touch target sizes.
struct TimelineHitTester: Sendable {
    /// Clips available for hit testing.
    let clips: [TimelineClip]

    /// Markers available for hit testing.
    let markers: [TimelineMarker]

    /// Current viewport state.
    let viewport: ViewportState

    /// Current playhead position.
    let playheadPosition: TimeMicros

    /// Track heights by track ID.
    let trackHeights: [String: CGFloat]

    /// Track vertical positions by track ID.
    let trackYPositions: [String: CGFloat]

    /// Whether the playhead is being dragged (makes it easier to hit).
    let playheadActive: Bool

    init(
        clips: [TimelineClip],
        markers: [TimelineMarker],
        viewport: ViewportState,
        playheadPosition: TimeMicros,
        trackHeights: [String: CGFloat],
        trackYPositions: [String: CGFloat],
        playheadActive: Bool = false
    ) {
        self.clips = clips
        self.markers = markers
        self.viewport = viewport
        self.playheadPosition = playheadPosition
        self.trackHeights = trackHeights
        self.trackYPositions = trackYPositions
        self.playheadActive = playheadActive
    }

    // MARK: - Hit Test

    /// Perform a hit test at the given position.
    ///
    /// Priority order:
    /// 1. Playhead (if within touch target)
    /// 2. Ruler area (if in ruler region)
    /// 3. Trim handles (if within clip and near edge)
    /// 4. Clips (if within clip body)
    /// 5. Markers (if near marker)
    /// 6. Empty space
    func hitTest(_ position: CGPoint) -> HitTestResult {
        let hitTime = viewport.absolutePixelXToTime(position.x)

        // 1. Test playhead first (highest priority)
        if let playheadResult = hitTestPlayhead(position, hitTime: hitTime) {
            return playheadResult
        }

        // 2. Test ruler area
        if position.y < viewport.rulerHeight {
            return HitTestResult(
                type: .ruler,
                hitTime: hitTime,
                hitPosition: position
            )
        }

        // 3. Test trim handles (before clip body)
        if let trimResult = hitTestTrimHandles(position, hitTime: hitTime) {
            return trimResult
        }

        // 4. Test clip bodies
        if let clipResult = hitTestClips(position, hitTime: hitTime) {
            return clipResult
        }

        // 5. Test markers
        if let markerResult = hitTestMarkers(position, hitTime: hitTime) {
            return markerResult
        }

        // 6. Empty space
        return .empty(hitTime: hitTime, hitPosition: position)
    }

    /// Hit test specifically for trim handles.
    func hitTestTrimHandle(_ position: CGPoint) -> TrimHandleInfo? {
        for clip in clips {
            guard let clipRect = getClipRect(clip) else { continue }

            // Check left handle
            let leftHandleRect = CGRect(
                x: clipRect.minX - kHandleTouchTarget / 2,
                y: clipRect.minY,
                width: kHandleTouchTarget,
                height: clipRect.height
            )
            if leftHandleRect.contains(position) {
                return TrimHandleInfo(clip: clip, isLeftHandle: true, handleRect: leftHandleRect)
            }

            // Check right handle
            let rightHandleRect = CGRect(
                x: clipRect.maxX - kHandleTouchTarget / 2,
                y: clipRect.minY,
                width: kHandleTouchTarget,
                height: clipRect.height
            )
            if rightHandleRect.contains(position) {
                return TrimHandleInfo(clip: clip, isLeftHandle: false, handleRect: rightHandleRect)
            }
        }
        return nil
    }

    /// Find all clips that intersect with the given rect.
    func findClipsInRect(_ rect: CGRect) -> [TimelineClip] {
        clips.filter { clip in
            guard let clipRect = getClipRect(clip) else { return false }
            return clipRect.intersects(rect)
        }
    }

    /// Find all markers that intersect with the given rect.
    func findMarkersInRect(_ rect: CGRect) -> [TimelineMarker] {
        markers.filter { marker in
            let markerX = viewport.timeToAbsolutePixelX(marker.time)
            let markerRect = CGRect(
                x: markerX - kMarkerTouchTarget / 2,
                y: viewport.rulerHeight / 2 - kMarkerTouchTarget / 2,
                width: kMarkerTouchTarget,
                height: kMarkerTouchTarget
            )
            return markerRect.intersects(rect)
        }
    }

    // MARK: - Private Hit Test Methods

    private func hitTestPlayhead(_ position: CGPoint, hitTime: TimeMicros) -> HitTestResult? {
        let playheadX = viewport.timeToAbsolutePixelX(playheadPosition)
        let touchTarget = playheadActive ? kPlayheadTouchTarget * 1.5 : kPlayheadTouchTarget
        let distance = abs(position.x - playheadX)

        guard distance <= touchTarget / 2 else { return nil }

        return HitTestResult(
            type: .playhead,
            hitTime: playheadPosition,
            hitPosition: position,
            distanceFromCenter: distance
        )
    }

    private func hitTestTrimHandles(_ position: CGPoint, hitTime: TimeMicros) -> HitTestResult? {
        for clip in clips {
            guard let clipRect = getClipRect(clip) else { continue }

            // Only test handles if we're within or very near the clip vertically
            let expandedVertical = clipRect.insetBy(dx: 0, dy: -4.0)
            guard position.y >= expandedVertical.minY,
                  position.y <= expandedVertical.maxY else { continue }

            // Check left handle
            let leftEdge = clipRect.minX
            if abs(position.x - leftEdge) <= kHandleTouchTarget / 2 {
                return HitTestResult(
                    type: .trimHandleLeft,
                    elementId: clip.id,
                    trackId: clip.trackId,
                    hitTime: clip.startTime,
                    hitPosition: position,
                    distanceFromCenter: abs(position.x - leftEdge)
                )
            }

            // Check right handle
            let rightEdge = clipRect.maxX
            if abs(position.x - rightEdge) <= kHandleTouchTarget / 2 {
                return HitTestResult(
                    type: .trimHandleRight,
                    elementId: clip.id,
                    trackId: clip.trackId,
                    hitTime: clip.endTime,
                    hitPosition: position,
                    distanceFromCenter: abs(position.x - rightEdge)
                )
            }
        }
        return nil
    }

    private func hitTestClips(_ position: CGPoint, hitTime: TimeMicros) -> HitTestResult? {
        for clip in clips {
            guard let clipRect = getClipRect(clip),
                  clipRect.contains(position) else { continue }

            let center = CGPoint(x: clipRect.midX, y: clipRect.midY)
            let distance = abs(position.x - center.x) + abs(position.y - center.y)

            return HitTestResult(
                type: .clip,
                elementId: clip.id,
                trackId: clip.trackId,
                hitTime: hitTime,
                hitPosition: position,
                distanceFromCenter: distance
            )
        }
        return nil
    }

    private func hitTestMarkers(_ position: CGPoint, hitTime: TimeMicros) -> HitTestResult? {
        // Only test markers in/near the ruler area
        guard position.y <= viewport.rulerHeight * 1.5 else { return nil }

        for marker in markers {
            let markerX = viewport.timeToAbsolutePixelX(marker.time)
            let distance = abs(position.x - markerX)

            guard distance <= kMarkerTouchTarget / 2 else { continue }

            return HitTestResult(
                type: .marker,
                elementId: marker.id,
                hitTime: marker.time,
                hitPosition: position,
                distanceFromCenter: distance
            )
        }
        return nil
    }

    // MARK: - Helper Methods

    func getClipRect(_ clip: TimelineClip) -> CGRect? {
        guard let trackY = trackYPositions[clip.trackId],
              let trackHeight = trackHeights[clip.trackId] else { return nil }

        let left = viewport.timeToAbsolutePixelX(clip.startTime)
        let right = viewport.timeToAbsolutePixelX(clip.endTime)

        return CGRect(x: left, y: trackY, width: right - left, height: trackHeight)
    }
}
