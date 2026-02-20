// KeyframeManager.swift
// LiquidEditor
//
// Manages keyframes with session-based undo/redo (timeline snapshot approach).

import Foundation
import Observation
import CoreGraphics

// MARK: - KeyframeManager

/// Manages keyframes with unlimited session-based undo/redo.
///
/// Undo/redo works by snapshotting the entire `KeyframeTimeline` before
/// each mutation. This is the "DaVinci Resolve" style: simple and robust.
///
/// Thread Safety: `@MainActor` -- all UI-driving state lives on the main thread.
@Observable
@MainActor
final class KeyframeManager {

    // MARK: - Constants

    /// Maximum undo/redo stack size to prevent unbounded memory growth.
    private static let maxUndoStackSize = 100

    // MARK: - Properties

    /// Current keyframe timeline (immutable value type -- mutations produce new instances).
    private(set) var timeline: KeyframeTimeline

    /// Undo stack -- previous timeline states.
    private var undoStack: [KeyframeTimeline] = []

    /// Redo stack -- future timeline states.
    private var redoStack: [KeyframeTimeline] = []

    /// Selected keyframe ID.
    var selectedKeyframeId: String?

    /// Cached sorted keyframes (invalidated on mutation).
    private var sortedKeyframesCache: [Keyframe]?

    // MARK: - Computed Properties

    /// Whether undo is available.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether redo is available.
    var canRedo: Bool { !redoStack.isEmpty }

    /// All keyframes (sorted order from timeline).
    var keyframes: [Keyframe] { timeline.keyframes }

    /// Number of keyframes.
    var keyframeCount: Int { timeline.keyframes.count }

    /// Sorted keyframes (cached for performance).
    var sortedKeyframes: [Keyframe] {
        if let cached = sortedKeyframesCache { return cached }
        let sorted = timeline.keyframes.sorted { $0.timestampMicros < $1.timestampMicros }
        sortedKeyframesCache = sorted
        return sorted
    }

    /// Currently selected keyframe.
    var selectedKeyframe: Keyframe? {
        guard let id = selectedKeyframeId else { return nil }
        return timeline.keyframes.first { $0.id == id }
    }

    // MARK: - Initialization

    /// Create with an existing timeline.
    init(timeline: KeyframeTimeline) {
        self.timeline = timeline
    }

    /// Create with a video duration.
    convenience init(videoDurationMicros: TimeMicros) {
        self.init(timeline: KeyframeTimeline(videoDurationMicros: videoDurationMicros))
    }

    // MARK: - Keyframe Operations

    /// Add a new keyframe. Replaces any existing keyframe within 50ms tolerance.
    func addKeyframe(_ keyframe: Keyframe) {
        saveUndoState()

        var tl = timeline
        // Remove existing keyframe at same timestamp (within 50ms = 50_000 micros)
        if let existing = tl.keyframeNear(keyframe.timestampMicros, toleranceMicros: 50_000) {
            tl = tl.removing(id: existing.id)
        }
        timeline = tl.adding(keyframe)
        selectedKeyframeId = keyframe.id
        sortedKeyframesCache = nil
    }

    /// Remove a keyframe by ID.
    func removeKeyframe(_ id: String) {
        saveUndoState()
        timeline = timeline.removing(id: id)
        if selectedKeyframeId == id {
            selectedKeyframeId = nil
        }
        sortedKeyframesCache = nil
    }

    /// Update an existing keyframe.
    func updateKeyframe(_ keyframe: Keyframe) {
        guard timeline.keyframes.contains(where: { $0.id == keyframe.id }) else { return }
        saveUndoState()
        timeline = timeline.updating(keyframe)
        sortedKeyframesCache = nil
    }

    /// Move a keyframe to a new timestamp.
    func moveKeyframe(_ id: String, to timestampMicros: TimeMicros) {
        guard let kf = timeline.keyframes.first(where: { $0.id == id }) else { return }
        saveUndoState()
        let updated = kf.with(timestampMicros: timestampMicros)
        timeline = timeline.updating(updated)
        sortedKeyframesCache = nil
    }

    /// Change interpolation type for a keyframe.
    func setInterpolation(_ id: String, type: InterpolationType) {
        guard let kf = timeline.keyframes.first(where: { $0.id == id }) else { return }
        saveUndoState()
        let updated = kf.with(interpolation: type)
        timeline = timeline.updating(updated)
    }

    /// Set custom Bezier control points for a keyframe.
    func setBezierPoints(_ id: String, points: BezierControlPoints) {
        guard let kf = timeline.keyframes.first(where: { $0.id == id }) else { return }
        saveUndoState()
        let updated = kf.with(interpolation: .bezier, bezierPoints: points)
        timeline = timeline.updating(updated)
    }

    /// Delete all keyframes.
    func clearAllKeyframes() {
        guard !timeline.keyframes.isEmpty else { return }
        saveUndoState()
        timeline = KeyframeTimeline(videoDurationMicros: timeline.videoDurationMicros)
        selectedKeyframeId = nil
        sortedKeyframesCache = nil
    }

    // MARK: - Selection

    /// Select the keyframe nearest to a timestamp.
    func selectKeyframe(near timestampMicros: TimeMicros) {
        selectedKeyframeId = timeline.keyframeNear(timestampMicros)?.id
    }

    /// Clear selection.
    func clearSelection() {
        selectedKeyframeId = nil
    }

    // MARK: - Query

    /// Get interpolated transform at a timestamp.
    func transform(at timestampMicros: TimeMicros) -> VideoTransform {
        TransformInterpolator.transform(at: timestampMicros, timeline: timeline)
    }

    /// Check if there's a keyframe near a timestamp (50ms tolerance).
    func hasKeyframe(at timestampMicros: TimeMicros) -> Bool {
        timeline.keyframeNear(timestampMicros, toleranceMicros: 50_000) != nil
    }

    /// Get keyframe at exact position (50ms tolerance).
    func keyframe(at timestampMicros: TimeMicros) -> Keyframe? {
        timeline.keyframeNear(timestampMicros, toleranceMicros: 50_000)
    }

    // MARK: - Undo/Redo

    /// Undo last operation.
    /// - Returns: Timestamp of affected keyframe for UI scrolling, or nil.
    @discardableResult
    func undo() -> TimeMicros? {
        guard !undoStack.isEmpty else { return nil }

        let oldTimeline = timeline
        redoStack.append(timeline)
        timeline = undoStack.removeLast()
        sortedKeyframesCache = nil

        return findAffectedTimestamp(old: oldTimeline, new: timeline)
    }

    /// Redo last undone operation.
    /// - Returns: Timestamp of affected keyframe for UI scrolling, or nil.
    @discardableResult
    func redo() -> TimeMicros? {
        guard !redoStack.isEmpty else { return nil }

        let oldTimeline = timeline
        undoStack.append(timeline)
        timeline = redoStack.removeLast()
        sortedKeyframesCache = nil

        return findAffectedTimestamp(old: oldTimeline, new: timeline)
    }

    /// Clear undo/redo history (e.g., on project close).
    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Serialization

    /// Export timeline data for saving.
    func exportTimeline() -> KeyframeTimeline { timeline }

    /// Import timeline data.
    func importTimeline(_ newTimeline: KeyframeTimeline) {
        saveUndoState()
        timeline = newTimeline
        selectedKeyframeId = nil
        sortedKeyframesCache = nil
    }

    // MARK: - Private

    private func saveUndoState() {
        undoStack.append(timeline)

        // Evict oldest undo states if stack exceeds limit
        if undoStack.count > Self.maxUndoStackSize {
            undoStack.removeFirst(undoStack.count - Self.maxUndoStackSize)
        }

        redoStack.removeAll()
        TransformInterpolator.invalidateCache()
    }

    /// Find the timestamp of the keyframe that changed between two states.
    private func findAffectedTimestamp(old: KeyframeTimeline, new: KeyframeTimeline) -> TimeMicros? {
        let oldIds = Set(old.keyframes.map(\.id))
        let newIds = Set(new.keyframes.map(\.id))

        // Added keyframes
        let addedIds = newIds.subtracting(oldIds)
        if let addedId = addedIds.first,
           let kf = new.keyframes.first(where: { $0.id == addedId }) {
            return kf.timestampMicros
        }

        // Removed keyframes
        let removedIds = oldIds.subtracting(newIds)
        if let removedId = removedIds.first,
           let kf = old.keyframes.first(where: { $0.id == removedId }) {
            return kf.timestampMicros
        }

        // Modified keyframes (same ID, different timestamp)
        for newKf in new.keyframes {
            if let oldKf = old.keyframes.first(where: { $0.id == newKf.id }),
               oldKf.timestampMicros != newKf.timestampMicros {
                return newKf.timestampMicros
            }
        }

        return nil
    }
}
