// ClipManager.swift
// LiquidEditor
//
// Manages timeline clips with command pattern undo/redo.

import Foundation
import Observation
import CoreGraphics

// MARK: - ClipCommand Protocol

/// Command interface for undo/redo support on clip operations.
protocol ClipCommand: Sendable {
    /// Execute the command against the manager's state.
    func execute(_ state: inout ClipManager.State)
    /// Reverse the command against the manager's state.
    func undo(_ state: inout ClipManager.State)
    /// Human-readable description for UI display.
    var description: String { get }
}

// MARK: - ClipManager

/// Manages timeline clips with command-pattern undo/redo.
///
/// All mutations go through `executeCommand(_:)` to maintain
/// full undo/redo history. The state is value-typed for safe
/// snapshot-based undo.
@Observable
@MainActor
final class ClipManager {

    // MARK: - State

    /// Value-type snapshot of the clip manager state.
    struct State: Sendable {
        /// All timeline clips, sorted by startTime.
        var clips: [TimelineClip] = []

        /// Currently selected clip ID.
        var selectedClipId: String?

        /// Get all clips sorted by start time.
        var sortedClips: [TimelineClip] {
            clips.sorted { $0.startTime < $1.startTime }
        }

        /// Total timeline duration.
        var totalDuration: TimeMicros {
            clips.map(\.endTime).max() ?? 0
        }

        /// Get clip by ID.
        func clipById(_ id: String) -> TimelineClip? {
            clips.first { $0.id == id }
        }

        /// Get index of clip by ID.
        func indexOfClip(_ id: String) -> Int? {
            clips.firstIndex { $0.id == id }
        }

        /// Get the clip at a specific timeline time.
        func clipAtTime(_ time: TimeMicros) -> TimelineClip? {
            clips.first { $0.containsTime(time) }
        }

        /// Replace clip at index.
        mutating func replaceClip(at index: Int, with clip: TimelineClip) {
            guard index >= 0, index < clips.count else { return }
            clips[index] = clip
        }
    }

    // MARK: - Properties

    /// Current state.
    private(set) var state = State()

    /// Undo stack.
    private var undoStack: [ClipCommand] = []

    /// Redo stack.
    private var redoStack: [ClipCommand] = []

    /// Maximum undo history size.
    static let maxUndoHistory = 50

    // MARK: - Computed Properties

    /// All clips sorted by start time.
    var clips: [TimelineClip] { state.sortedClips }

    /// Currently selected clip ID.
    var selectedClipId: String? { state.selectedClipId }

    /// Currently selected clip.
    var selectedClip: TimelineClip? {
        guard let id = state.selectedClipId else { return nil }
        return state.clipById(id)
    }

    /// Total timeline duration.
    var totalDuration: TimeMicros { state.totalDuration }

    /// Whether undo is available.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether redo is available.
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Initialization

    /// Initialize with clips.
    func loadClips(_ clips: [TimelineClip]) {
        state.clips = clips
        state.selectedClipId = clips.first?.id
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Initialize with a single video clip.
    func initializeWithSingleClip(
        trackId: String,
        mediaAssetId: String,
        durationMicros: TimeMicros
    ) {
        let clip = TimelineClip(
            mediaAssetId: mediaAssetId,
            trackId: trackId,
            type: .video,
            startTime: 0,
            duration: durationMicros,
            sourceIn: 0,
            sourceOut: durationMicros
        )
        state.clips = [clip]
        state.selectedClipId = clip.id
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - Command Execution

    /// Execute a command with undo support.
    func executeCommand(_ command: ClipCommand) {
        command.execute(&state)

        undoStack.append(command)
        if undoStack.count > Self.maxUndoHistory {
            undoStack.removeFirst()
        }

        redoStack.removeAll()
    }

    /// Undo the last command.
    /// - Returns: Description of the undone command, or nil if stack was empty.
    @discardableResult
    func undo() -> String? {
        guard let command = undoStack.popLast() else { return nil }
        command.undo(&state)
        redoStack.append(command)
        return command.description
    }

    /// Redo the last undone command.
    /// - Returns: Description of the redone command, or nil if stack was empty.
    @discardableResult
    func redo() -> String? {
        guard let command = redoStack.popLast() else { return nil }
        command.execute(&state)
        undoStack.append(command)
        return command.description
    }

    // MARK: - Selection

    /// Select a clip by ID.
    func selectClip(_ clipId: String?) {
        state.selectedClipId = clipId
    }

    // MARK: - Queries

    /// Get a clip by ID.
    func getClipById(_ id: String) -> TimelineClip? {
        state.clipById(id)
    }

    /// Get the clip at a timeline time.
    func clipAtTime(_ time: TimeMicros) -> TimelineClip? {
        state.clipAtTime(time)
    }

    // MARK: - Convenience Operations

    /// Split the selected clip at a timeline position.
    func splitAtTimelinePosition(_ time: TimeMicros) {
        let clipId: String?
        if let selected = state.selectedClipId, state.clipById(selected)?.containsTime(time) == true {
            clipId = selected
        } else {
            clipId = state.clipAtTime(time)?.id
        }
        guard let clipId else { return }

        executeCommand(SplitClipCommand(clipId: clipId, splitTime: time))
    }

    /// Delete the selected clip.
    func deleteSelectedClip(ripple: Bool = true) {
        guard let clipId = state.selectedClipId else { return }
        executeCommand(DeleteClipCommand(clipId: clipId, ripple: ripple))
    }

    /// Delete a specific clip.
    func deleteClip(_ clipId: String, ripple: Bool = true) {
        executeCommand(DeleteClipCommand(clipId: clipId, ripple: ripple))
    }

    /// Duplicate the selected clip.
    func duplicateSelectedClip() {
        guard let clipId = state.selectedClipId else { return }
        executeCommand(DuplicateClipCommand(clipId: clipId))
    }

    /// Reorder a clip to a new index in the sorted list.
    func reorderClip(_ clipId: String, toIndex newIndex: Int) {
        executeCommand(ReorderClipCommand(clipId: clipId, newIndex: newIndex))
    }

    /// Trim a clip's head.
    func trimClipHead(_ clipId: String, newStartTime: TimeMicros) {
        executeCommand(TrimClipCommand(clipId: clipId, newStartTime: newStartTime, newEndTime: nil))
    }

    /// Trim a clip's tail.
    func trimClipTail(_ clipId: String, newEndTime: TimeMicros) {
        executeCommand(TrimClipCommand(clipId: clipId, newStartTime: nil, newEndTime: newEndTime))
    }
}

// MARK: - Commands

/// Split a clip at a specific timeline time.
struct SplitClipCommand: ClipCommand {
    let clipId: String
    let splitTime: TimeMicros

    // Captured state for undo
    private let rightClipId = UUID().uuidString

    var description: String { "Split clip" }

    func execute(_ state: inout ClipManager.State) {
        guard let index = state.indexOfClip(clipId),
              let result = state.clips[index].splitAt(splitTime, rightClipId: rightClipId) else {
            return
        }
        state.clips.remove(at: index)
        state.clips.insert(result.right, at: index)
        state.clips.insert(result.left, at: index)
        state.selectedClipId = rightClipId
    }

    func undo(_ state: inout ClipManager.State) {
        // Remove the two halves and restore original
        guard let leftIndex = state.indexOfClip(clipId) else { return }
        let originalClip: TimelineClip
        if let left = state.clipById(clipId), let right = state.clipById(rightClipId) {
            // Reconstruct original from left and right
            originalClip = left.with(
                duration: left.duration + right.duration,
                sourceOut: right.sourceOut
            )
        } else {
            return
        }

        state.clips.removeAll { $0.id == clipId || $0.id == rightClipId }
        state.clips.insert(originalClip, at: min(leftIndex, state.clips.count))
        state.selectedClipId = clipId
    }
}

/// Delete a clip.
struct DeleteClipCommand: ClipCommand {
    let clipId: String
    let ripple: Bool

    var description: String { ripple ? "Delete clip (ripple)" : "Delete clip" }

    // We store the deleted clip and its position for undo
    // Since this is a value type command, we use a class wrapper for mutability
    private final class UndoState: @unchecked Sendable {
        var deletedClip: TimelineClip?
        var sortedIndex: Int = 0
    }
    private let undoState = UndoState()

    func execute(_ state: inout ClipManager.State) {
        // Prevent deleting the last clip
        guard state.clips.count > 1 else { return }
        guard let index = state.indexOfClip(clipId) else { return }

        undoState.deletedClip = state.clips[index]
        undoState.sortedIndex = index
        state.clips.remove(at: index)

        if !ripple, let deleted = undoState.deletedClip {
            // Insert a gap clip in its place
            let gap = TimelineClip(
                trackId: deleted.trackId,
                type: .gap,
                startTime: deleted.startTime,
                duration: deleted.duration
            )
            state.clips.insert(gap, at: min(index, state.clips.count))
        }

        state.selectedClipId = nil
    }

    func undo(_ state: inout ClipManager.State) {
        guard let deleted = undoState.deletedClip else { return }

        if !ripple {
            // Remove the gap we inserted
            state.clips.removeAll { $0.type == .gap && $0.startTime == deleted.startTime }
        }

        let insertIndex = min(undoState.sortedIndex, state.clips.count)
        state.clips.insert(deleted, at: insertIndex)
        state.selectedClipId = deleted.id
    }
}

/// Reorder a clip.
struct ReorderClipCommand: ClipCommand {
    let clipId: String
    let newIndex: Int

    var description: String { "Reorder clip" }

    private final class UndoState: @unchecked Sendable {
        var originalIndex: Int = 0
    }
    private let undoState = UndoState()

    func execute(_ state: inout ClipManager.State) {
        guard let currentIndex = state.indexOfClip(clipId) else { return }
        guard currentIndex != newIndex else { return }

        undoState.originalIndex = currentIndex
        let clip = state.clips.remove(at: currentIndex)
        let insertIndex = min(max(newIndex, 0), state.clips.count)
        state.clips.insert(clip, at: insertIndex)
    }

    func undo(_ state: inout ClipManager.State) {
        guard let currentIndex = state.indexOfClip(clipId) else { return }
        let clip = state.clips.remove(at: currentIndex)
        let insertIndex = min(max(undoState.originalIndex, 0), state.clips.count)
        state.clips.insert(clip, at: insertIndex)
    }
}

/// Trim a clip's head or tail.
struct TrimClipCommand: ClipCommand {
    let clipId: String
    let newStartTime: TimeMicros?
    let newEndTime: TimeMicros?

    var description: String { "Trim clip" }

    private final class UndoState: @unchecked Sendable {
        var originalClip: TimelineClip?
    }
    private let undoState = UndoState()

    func execute(_ state: inout ClipManager.State) {
        guard let index = state.indexOfClip(clipId) else { return }
        let clip = state.clips[index]
        undoState.originalClip = clip

        var trimmed = clip
        if let newStart = newStartTime {
            trimmed = trimmed.trimHead(newStart)
        }
        if let newEnd = newEndTime {
            trimmed = trimmed.trimTail(newEnd)
        }
        state.replaceClip(at: index, with: trimmed)
    }

    func undo(_ state: inout ClipManager.State) {
        guard let original = undoState.originalClip,
              let index = state.indexOfClip(clipId) else { return }
        state.replaceClip(at: index, with: original)
    }
}

/// Duplicate a clip.
struct DuplicateClipCommand: ClipCommand {
    let clipId: String

    var description: String { "Duplicate clip" }

    private let duplicateId = UUID().uuidString

    func execute(_ state: inout ClipManager.State) {
        guard let index = state.indexOfClip(clipId) else { return }
        let clip = state.clips[index]

        // Place duplicate immediately after original
        let duplicate = clip.with(
            id: duplicateId,
            startTime: clip.endTime
        )
        state.clips.insert(duplicate, at: index + 1)
        state.selectedClipId = duplicateId
    }

    func undo(_ state: inout ClipManager.State) {
        state.clips.removeAll { $0.id == duplicateId }
        state.selectedClipId = clipId
    }
}
