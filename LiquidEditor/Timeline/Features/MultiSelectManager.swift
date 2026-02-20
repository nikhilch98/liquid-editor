// MultiSelectManager.swift
// LiquidEditor
//
// Multi-select manager for timeline clip selection.
// Manages multi-clip selection state including tap-to-select,
// tap-to-deselect, select-all-in-track, and group operations.
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - GroupOperationResult

/// Result of a group operation on selected clips.
struct GroupOperationResult: Equatable, Sendable {
    /// Clip IDs affected by the operation.
    let affectedClipIds: Set<String>

    /// Description of the operation for undo display.
    let operationName: String

    /// Whether the operation succeeded.
    let success: Bool

    /// Error message if the operation failed.
    let error: String?

    init(
        affectedClipIds: Set<String>,
        operationName: String,
        success: Bool,
        error: String? = nil
    ) {
        self.affectedClipIds = affectedClipIds
        self.operationName = operationName
        self.success = success
        self.error = error
    }

    /// Successful operation.
    static func success(
        affectedClipIds: Set<String>,
        operationName: String
    ) -> GroupOperationResult {
        GroupOperationResult(
            affectedClipIds: affectedClipIds,
            operationName: operationName,
            success: true
        )
    }

    /// Failed operation.
    static func failure(
        operationName: String,
        error: String
    ) -> GroupOperationResult {
        GroupOperationResult(
            affectedClipIds: [],
            operationName: operationName,
            success: false,
            error: error
        )
    }
}

// MARK: - MultiSelectManager

/// Manages multi-clip selection on the timeline.
///
/// Provides:
/// - Tap-to-select / tap-to-deselect individual clips
/// - Range selection via long-press-drag
/// - Select all clips on a specific track
/// - Group operations on selection (delete, copy, split, move)
/// - Selection highlight state for rendering
@Observable @MainActor
final class MultiSelectManager {

    // MARK: - State

    /// Currently selected clip IDs.
    private(set) var selectedIds: Set<String> = []

    /// Primary selected clip (most recently selected).
    private(set) var primaryClipId: String?

    /// Whether multi-select mode is active.
    private(set) var isMultiSelectActive: Bool = false

    // MARK: - Computed Properties

    /// Number of selected clips.
    var selectionCount: Int { selectedIds.count }

    /// Whether any clips are selected.
    var hasSelection: Bool { !selectedIds.isEmpty }

    /// Whether multiple clips are selected.
    var hasMultiSelection: Bool { selectedIds.count > 1 }

    /// Check if a specific clip is selected.
    func isSelected(_ clipId: String) -> Bool {
        selectedIds.contains(clipId)
    }

    // MARK: - Selection Operations

    /// Select a single clip, clearing previous selection.
    func selectClip(_ clipId: String) {
        selectedIds = [clipId]
        primaryClipId = clipId
        isMultiSelectActive = false
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Toggle selection of a clip (add or remove from selection).
    ///
    /// Used for tap-to-add/remove behavior in multi-select mode.
    func toggleClip(_ clipId: String) {
        var newSelection = selectedIds
        if newSelection.contains(clipId) {
            newSelection.remove(clipId)
            if primaryClipId == clipId {
                primaryClipId = newSelection.isEmpty ? nil : newSelection.first
            }
        } else {
            newSelection.insert(clipId)
            primaryClipId = clipId
        }
        selectedIds = newSelection
        isMultiSelectActive = newSelection.count > 1
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Add a clip to the current selection.
    func addToSelection(_ clipId: String) {
        guard !selectedIds.contains(clipId) else { return }
        var newSelection = selectedIds
        newSelection.insert(clipId)
        selectedIds = newSelection
        primaryClipId = clipId
        isMultiSelectActive = newSelection.count > 1
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Remove a clip from the current selection.
    func removeFromSelection(_ clipId: String) {
        guard selectedIds.contains(clipId) else { return }
        var newSelection = selectedIds
        newSelection.remove(clipId)
        selectedIds = newSelection
        if primaryClipId == clipId {
            primaryClipId = newSelection.isEmpty ? nil : newSelection.first
        }
        isMultiSelectActive = newSelection.count > 1
    }

    /// Select multiple clips at once (e.g., from marquee selection).
    func selectClips(_ clipIds: Set<String>) {
        selectedIds = clipIds
        primaryClipId = clipIds.isEmpty ? nil : clipIds.first
        isMultiSelectActive = clipIds.count > 1
        if !clipIds.isEmpty {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Select all clips on a specific track.
    func selectAllOnTrack(_ trackId: String, allClips: [TimelineClip]) {
        let trackClips = allClips
            .filter { $0.trackId == trackId && $0.type != .gap }
            .map(\.id)
        let trackClipIds = Set(trackClips)
        selectedIds = trackClipIds
        primaryClipId = trackClipIds.isEmpty ? nil : trackClipIds.first
        isMultiSelectActive = trackClipIds.count > 1
        if !trackClipIds.isEmpty {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    /// Select all clips on the timeline.
    func selectAll(_ allClips: [TimelineClip]) {
        let allIds = Set(
            allClips
                .filter { $0.type != .gap }
                .map(\.id)
        )
        selectedIds = allIds
        primaryClipId = allIds.isEmpty ? nil : allIds.first
        isMultiSelectActive = allIds.count > 1
        if !allIds.isEmpty {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    /// Clear all selections.
    func clearSelection() {
        selectedIds = []
        primaryClipId = nil
        isMultiSelectActive = false
    }

    // MARK: - Range Selection

    /// Find clips that intersect a rectangular area (marquee selection).
    ///
    /// - Parameters:
    ///   - allClips: All clips on the timeline.
    ///   - marqueeRect: The selection rectangle in viewport coordinates.
    ///   - clipRectProvider: Function to get the viewport rect for a clip.
    /// - Returns: Set of clip IDs within the marquee.
    func findClipsInRect(
        _ allClips: [TimelineClip],
        marqueeRect: CGRect,
        clipRectProvider: (TimelineClip) -> CGRect
    ) -> Set<String> {
        var selected = Set<String>()
        for clip in allClips {
            if clip.type == .gap { continue }
            let clipRect = clipRectProvider(clip)
            if clipRect.intersects(marqueeRect) {
                selected.insert(clip.id)
            }
        }
        return selected
    }

    // MARK: - Group Operations

    /// Get the selected clips from all clips.
    func getSelectedClips(_ allClips: [TimelineClip]) -> [TimelineClip] {
        allClips.filter { selectedIds.contains($0.id) }
    }

    /// Calculate group move -- compute new positions for all selected clips.
    ///
    /// - Parameters:
    ///   - delta: Time delta to move by.
    ///   - allClips: All clips on the timeline.
    /// - Returns: A map of clip ID to new start time.
    func calculateGroupMove(
        delta: TimeMicros,
        allClips: [TimelineClip]
    ) -> [String: TimeMicros] {
        var moves: [String: TimeMicros] = [:]
        for clip in allClips {
            guard selectedIds.contains(clip.id) else { continue }
            let newStart = clip.startTime + delta
            moves[clip.id] = max(newStart, 0)
        }
        return moves
    }

    /// Validate that a group delete is safe.
    ///
    /// Checks for linked clips that may also need deletion.
    func validateGroupDelete(_ allClips: [TimelineClip]) -> GroupOperationResult {
        guard hasSelection else {
            return .failure(
                operationName: "Delete",
                error: "No clips selected"
            )
        }

        // Include linked partners in the affected set
        var affected = selectedIds
        for clip in allClips {
            if selectedIds.contains(clip.id), let linkedId = clip.linkedClipId {
                affected.insert(linkedId)
            }
        }

        let count = affected.count
        return .success(
            affectedClipIds: affected,
            operationName: "Delete \(count) clip\(count == 1 ? "" : "s")"
        )
    }

    /// Get the time range covered by the current selection.
    func getSelectionTimeRange(_ allClips: [TimelineClip]) -> TimeRange? {
        guard hasSelection else { return nil }

        var minStart: TimeMicros?
        var maxEnd: TimeMicros?

        for clip in allClips {
            guard selectedIds.contains(clip.id) else { continue }
            if minStart == nil || clip.startTime < minStart! {
                minStart = clip.startTime
            }
            if maxEnd == nil || clip.endTime > maxEnd! {
                maxEnd = clip.endTime
            }
        }

        guard let start = minStart, let end = maxEnd else { return nil }
        return TimeRange(start, end)
    }

    /// Convert selection state to an immutable SelectionState for rendering.
    func toSelectionState() -> SelectionState {
        SelectionState(
            selectedClipIds: selectedIds,
            primaryClipId: primaryClipId,
            mode: .normal
        )
    }
}
