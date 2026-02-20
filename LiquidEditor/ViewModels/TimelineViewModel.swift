// TimelineViewModel.swift
// LiquidEditor
//
// ViewModel for the timeline UI — manages timeline state, selection,
// viewport, clip operations, undo/redo, and coordinate conversion.
//
// Uses @Observable macro (iOS 26) for SwiftUI reactivity.
// All mutable UI state is @MainActor-isolated.

import Foundation
import SwiftUI

// MARK: - TimelineViewModel

@Observable
@MainActor
final class TimelineViewModel {

    // MARK: - Configuration Constants

    /// Minimum clip duration for trim and split operations (100ms).
    let minClipDurationMicros: TimeMicros

    /// Maximum undo stack depth.
    let maxUndoDepth: Int

    /// Snap tolerance in points for edge snapping.
    let snapTolerancePoints: CGFloat

    // MARK: - Timeline Data

    /// The immutable persistent timeline tree (source of truth for clip order/duration).
    private(set) var timeline: PersistentTimeline = .empty

    /// Tracks in the project (ordered by index).
    var tracks: [Track] = []

    /// Viewport state (scroll position, zoom, dimensions).
    var viewport: ViewportState = .initial()

    /// Selection state (selected clips, mode, range).
    var selection: SelectionState = .empty

    // MARK: - Playhead

    /// Current playhead position in microseconds.
    var playheadPosition: TimeMicros = 0

    // MARK: - Interaction State

    /// Whether the user is currently dragging a clip.
    var isDragging: Bool = false

    /// Whether the user is currently trimming a clip edge.
    var isTrimming: Bool = false

    /// Whether the user is scrubbing on the timeline ruler.
    var isScrubbingTimeline: Bool = false

    // MARK: - Settings

    /// Whether snapping to clip edges is enabled.
    var snapEnabled: Bool = true

    /// Zoom level expressed as pixels per microsecond.
    /// Derived from viewport but exposed for convenience.
    var zoomLevel: Double {
        get { viewport.pixelsPerMicrosecond }
        set {
            let newMicrosPerPixel = 1.0 / max(newValue, 1e-10)
            viewport = viewport.withZoom(newMicrosPerPixel)
        }
    }

    /// Horizontal scroll offset in points (for ScrollView integration).
    var scrollOffset: CGFloat = 0

    // MARK: - Undo / Redo

    /// Stack of previous timeline states for undo.
    private var undoStack: [PersistentTimeline] = []

    /// Stack of undone timeline states for redo.
    private var redoStack: [PersistentTimeline] = []

    /// Whether undo is available.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether redo is available.
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Computed Properties

    /// Total duration of the timeline in microseconds.
    var totalDuration: TimeMicros {
        timeline.totalDurationMicros
    }

    /// Total duration formatted as a simple time string.
    var formattedTotalDuration: String {
        totalDuration.simpleTimeString
    }

    /// Total width of the timeline in points at the current zoom level.
    var totalTimelineWidth: CGFloat {
        CGFloat(Double(totalDuration) * viewport.pixelsPerMicrosecond)
    }

    // MARK: - Initialization

    /// Initialize with default configuration.
    init(
        minClipDurationMicros: TimeMicros = 100_000,
        maxUndoDepth: Int = 100,
        snapTolerancePoints: CGFloat = 8
    ) {
        self.minClipDurationMicros = minClipDurationMicros
        self.maxUndoDepth = maxUndoDepth
        self.snapTolerancePoints = snapTolerancePoints
    }

    /// Initialize with an existing timeline and tracks.
    init(
        timeline: PersistentTimeline,
        tracks: [Track],
        minClipDurationMicros: TimeMicros = 100_000,
        maxUndoDepth: Int = 100,
        snapTolerancePoints: CGFloat = 8
    ) {
        self.timeline = timeline
        self.tracks = tracks
        self.minClipDurationMicros = minClipDurationMicros
        self.maxUndoDepth = maxUndoDepth
        self.snapTolerancePoints = snapTolerancePoints
    }

    // MARK: - Selection

    /// Select a single clip by ID (clears other selections).
    func selectClip(id: String) {
        selection = selection.selectClip(id)
    }

    /// Deselect all clips and clear selection state.
    func deselectAll() {
        selection = selection.clearAll()
    }

    /// Toggle selection of a clip (for multi-select).
    func toggleClipSelection(id: String) {
        selection = selection.toggleClipSelection(id)
    }

    // MARK: - Clip Operations

    /// Move a clip to a new time position on the timeline.
    func moveClip(id: String, toTime: TimeMicros) {
        guard let item = timeline.getById(id) else { return }
        pushUndo()
        // Remove and re-insert at the new position.
        let updated = timeline.remove(id)
        timeline = updated.insertAt(toTime, item)
    }

    /// Trim the start (head) of a clip by a delta in microseconds.
    ///
    /// Positive delta trims inward (shortens clip from start).
    /// Negative delta extends outward (lengthens clip from start).
    /// Supports all clip types: GapClip, VideoClip, AudioClip, ImageClip,
    /// TextClip, StickerClip, ColorClip.
    func trimClipStart(id: String, delta: TimeMicros) {
        guard let item = timeline.getById(id) else { return }

        let minDuration: TimeMicros = 100_000 // 100ms minimum

        if let gapClip = item as? GapClip {
            let newDuration = gapClip.durationMicroseconds - delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = gapClip.withDuration(newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let videoClip = item as? VideoClip {
            let newInMicros = videoClip.sourceInMicros + delta
            guard let trimmed = videoClip.trimStart(newInMicros) else { return }
            pushUndo()
            timeline = timeline.updateItem(id, trimmed)
        } else if let audioClip = item as? AudioClip {
            let newInMicros = audioClip.sourceInMicros + delta
            guard let trimmed = audioClip.trimStart(newInMicros) else { return }
            pushUndo()
            timeline = timeline.updateItem(id, trimmed)
        } else if let imageClip = item as? ImageClip {
            let newDuration = imageClip.durationMicroseconds - delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = imageClip.withDuration(newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let textClip = item as? TextClip {
            let newDuration = textClip.durationMicroseconds - delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = textClip.with(durationMicroseconds: newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let stickerClip = item as? StickerClip {
            let newDuration = stickerClip.durationMicroseconds - delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = stickerClip.with(durationMicroseconds: newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let colorClip = item as? ColorClip {
            let newDuration = colorClip.durationMicroseconds - delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = colorClip.withDuration(newDuration)
            timeline = timeline.updateItem(id, trimmed)
        }
    }

    /// Trim the end (tail) of a clip by a delta in microseconds.
    ///
    /// Positive delta extends the clip (lengthens from end).
    /// Negative delta trims inward (shortens from end).
    /// Supports all clip types: GapClip, VideoClip, AudioClip, ImageClip,
    /// TextClip, StickerClip, ColorClip.
    func trimClipEnd(id: String, delta: TimeMicros) {
        guard let item = timeline.getById(id) else { return }

        let minDuration: TimeMicros = 100_000 // 100ms minimum

        if let gapClip = item as? GapClip {
            let newDuration = gapClip.durationMicroseconds + delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = gapClip.withDuration(newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let videoClip = item as? VideoClip {
            let newOutMicros = videoClip.sourceOutMicros + delta
            guard let trimmed = videoClip.trimEnd(newOutMicros) else { return }
            pushUndo()
            timeline = timeline.updateItem(id, trimmed)
        } else if let audioClip = item as? AudioClip {
            let newOutMicros = audioClip.sourceOutMicros + delta
            guard let trimmed = audioClip.trimEnd(newOutMicros) else { return }
            pushUndo()
            timeline = timeline.updateItem(id, trimmed)
        } else if let imageClip = item as? ImageClip {
            let newDuration = imageClip.durationMicroseconds + delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = imageClip.withDuration(newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let textClip = item as? TextClip {
            let newDuration = textClip.durationMicroseconds + delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = textClip.with(durationMicroseconds: newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let stickerClip = item as? StickerClip {
            let newDuration = stickerClip.durationMicroseconds + delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = stickerClip.with(durationMicroseconds: newDuration)
            timeline = timeline.updateItem(id, trimmed)
        } else if let colorClip = item as? ColorClip {
            let newDuration = colorClip.durationMicroseconds + delta
            guard newDuration >= minDuration else { return }
            pushUndo()
            let trimmed = colorClip.withDuration(newDuration)
            timeline = timeline.updateItem(id, trimmed)
        }
    }

    /// Split the selected clip at the current playhead position.
    ///
    /// Supports all clip types: GapClip, VideoClip, AudioClip, ImageClip,
    /// TextClip, StickerClip, ColorClip.
    func splitClipAtPlayhead() {
        guard let primaryId = selection.primaryClipId else { return }
        guard let startTime = timeline.startTimeOf(primaryId) else { return }
        guard let item = timeline.getById(primaryId) else { return }

        let offsetWithinClip = playheadPosition - startTime
        guard offsetWithinClip > 0, offsetWithinClip < item.durationMicroseconds else { return }

        // Delegate split to the concrete clip type's splitAt() method.
        let splitResult: (left: any TimelineItemProtocol, right: any TimelineItemProtocol)?

        if let gapClip = item as? GapClip {
            splitResult = gapClip.splitAt(offsetWithinClip).map { ($0.left, $0.right) }
        } else if let videoClip = item as? VideoClip {
            splitResult = videoClip.splitAt(offsetWithinClip).map { ($0.left, $0.right) }
        } else if let audioClip = item as? AudioClip {
            splitResult = audioClip.splitAt(offsetWithinClip).map { ($0.left, $0.right) }
        } else if let textClip = item as? TextClip {
            splitResult = textClip.splitAt(offsetWithinClip).map { ($0.left, $0.right) }
        } else if let stickerClip = item as? StickerClip {
            splitResult = stickerClip.splitAt(offsetWithinClip).map { ($0.left, $0.right) }
        } else if let colorClip = item as? ColorClip {
            splitResult = colorClip.splitAt(offsetWithinClip).map { ($0.left, $0.right) }
        } else if let imageClip = item as? ImageClip {
            // ImageClip: split into two image clips with proportional durations
            let minDuration: TimeMicros = 100_000
            if offsetWithinClip >= minDuration,
               offsetWithinClip <= imageClip.durationMicroseconds - minDuration {
                let left = imageClip.with(
                    id: UUID().uuidString,
                    durationMicroseconds: offsetWithinClip
                )
                let right = imageClip.with(
                    id: UUID().uuidString,
                    durationMicroseconds: imageClip.durationMicroseconds - offsetWithinClip
                )
                splitResult = (left, right)
            } else {
                splitResult = nil
            }
        } else {
            return // Unsupported clip type
        }

        guard let (leftClip, rightClip) = splitResult else { return }

        pushUndo()
        var updated = timeline.remove(primaryId)
        updated = updated.insertAt(startTime, leftClip)
        updated = updated.insertAt(startTime + leftClip.durationMicroseconds, rightClip)
        timeline = updated
        selection = selection.selectClip(rightClip.id)
    }

    /// Delete all currently selected clips.
    func deleteSelectedClips() {
        guard selection.hasSelection else { return }
        pushUndo()
        var updated = timeline
        for clipId in selection.selectedClipIds {
            updated = updated.remove(clipId)
        }
        timeline = updated
        selection = selection.clearAll()
    }

    // MARK: - Zoom & Scroll

    /// Zoom by a scale factor, anchored at a specific X position in points.
    ///
    /// - Parameters:
    ///   - scale: Multiplier (> 1 zooms in, < 1 zooms out).
    ///   - anchor: X position in the viewport content area to anchor the zoom.
    func zoom(scale: Double, anchor: CGFloat) {
        let anchorTime = viewport.pixelXToTime(Double(anchor))
        let newMicrosPerPixel = viewport.microsPerPixel / scale
        viewport = viewport.zoomCenteredOnTime(newMicrosPerPixel, centerTime: anchorTime)
    }

    /// Scroll the timeline by a horizontal delta in points.
    func scroll(delta: CGFloat) {
        viewport = viewport.scrollByPixels(Double(delta), maxPosition: totalDuration)
        scrollOffset += delta
    }

    // MARK: - Snapping

    /// Snap tolerance in microseconds (varies with zoom level).
    private var snapToleranceMicros: TimeMicros {
        // ~8 pixels worth of time at current zoom.
        TimeMicros((8.0 * viewport.microsPerPixel).rounded())
    }

    /// Snap a time position to the nearest clip edge if within tolerance.
    func snapToNearestEdge(time: TimeMicros) -> TimeMicros {
        guard snapEnabled else { return time }

        var bestSnap = time
        var bestDistance: TimeMicros = .max

        // Check playhead.
        let playheadDist = abs(time - playheadPosition)
        if playheadDist < snapToleranceMicros && playheadDist < bestDistance {
            bestSnap = playheadPosition
            bestDistance = playheadDist
        }

        // Check clip edges by walking the timeline.
        var runningTime: TimeMicros = 0
        for item in timeline.items {
            // Start edge.
            let startDist = abs(time - runningTime)
            if startDist < snapToleranceMicros && startDist < bestDistance {
                bestSnap = runningTime
                bestDistance = startDist
            }

            runningTime += item.durationMicroseconds

            // End edge.
            let endDist = abs(time - runningTime)
            if endDist < snapToleranceMicros && endDist < bestDistance {
                bestSnap = runningTime
                bestDistance = endDist
            }
        }

        // Check timeline start and end.
        if time < snapToleranceMicros && time < bestDistance {
            bestSnap = 0
        }

        return bestSnap
    }

    // MARK: - Coordinate Conversion

    /// Convert a time in microseconds to an X position in points.
    func timeToX(_ time: TimeMicros) -> CGFloat {
        CGFloat(viewport.timeToPixelX(time))
    }

    /// Convert an X position in points to a time in microseconds.
    func xToTime(_ x: CGFloat) -> TimeMicros {
        viewport.pixelXToTime(Double(x))
    }

    // MARK: - Undo / Redo

    /// Undo the last timeline operation.
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(timeline)
        timeline = previous
    }

    /// Redo the last undone timeline operation.
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(timeline)
        timeline = next
    }

    /// Push the current timeline onto the undo stack.
    private func pushUndo() {
        undoStack.append(timeline)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        // Clear redo stack on new operation.
        redoStack.removeAll()
    }

    // MARK: - Track Management

    /// Add a new track of the given type.
    func addTrack(name: String? = nil, type: TrackType = .mainVideo) {
        let newIndex = tracks.count
        let trackName = name ?? "\(type.displayName) \(newIndex + 1)"
        let track = Track.create(
            id: UUID().uuidString,
            name: trackName,
            type: type,
            index: newIndex
        )
        tracks.append(track)
    }

    /// Remove a track by ID.
    func removeTrack(id: String) {
        tracks.removeAll { $0.id == id }
        // Re-index remaining tracks.
        tracks = tracks.enumerated().map { index, track in
            track.with(index: index)
        }
    }

    /// Reorder a track from its current position to a new index.
    func reorderTrack(id: String, to newIndex: Int) {
        guard let currentIndex = tracks.firstIndex(where: { $0.id == id }) else { return }
        let track = tracks.remove(at: currentIndex)
        let clampedIndex = min(max(newIndex, 0), tracks.count)
        tracks.insert(track, at: clampedIndex)
        // Re-index all tracks.
        tracks = tracks.enumerated().map { index, t in
            t.with(index: index)
        }
    }

    // MARK: - Viewport Updates

    /// Update viewport dimensions (called from GeometryReader).
    func updateViewportSize(width: CGFloat, height: CGFloat) {
        viewport = viewport.withDimensions(width: Double(width), height: Double(height))
    }

    /// Zoom to fit the entire timeline in the viewport.
    func zoomToFit() {
        guard totalDuration > 0 else { return }
        let newMicrosPerPixel = viewport.zoomToFitDuration(totalDuration)
        viewport = viewport.withZoom(newMicrosPerPixel).withScrollPosition(0)
    }
}
