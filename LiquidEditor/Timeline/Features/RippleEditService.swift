// RippleEditService.swift
// LiquidEditor
//
// Ripple edit service for timeline clip operations.
// Provides ripple editing mode where trimming or deleting a clip
// automatically shifts subsequent clips to close gaps.
//

import Foundation
import UIKit

// MARK: - EditMode

/// Edit mode for timeline operations.
enum EditMode: String, Sendable, CaseIterable {
    /// Overwrite mode: Gaps are preserved when clips are trimmed/deleted.
    case overwrite
    /// Ripple mode: Subsequent clips shift to fill gaps.
    case ripple
}

// MARK: - RippleShift

/// Preview of how a subsequent clip will shift during a ripple operation.
struct RippleShift: Equatable, Sendable {
    /// Clip ID being shifted.
    let clipId: String

    /// Original start time.
    let originalStartTime: TimeMicros

    /// New start time after ripple.
    let newStartTime: TimeMicros

    /// Delta applied.
    let delta: TimeMicros
}

// MARK: - RippleEditResult

/// Result of a ripple edit operation.
struct RippleEditResult: Equatable, Sendable {
    /// Whether the operation succeeded.
    let success: Bool

    /// Clips that were shifted by the ripple.
    let shifts: [RippleShift]

    /// Description for undo display.
    let operationName: String

    /// Error message if failed.
    let error: String?

    /// The time delta applied to the timeline.
    let timeDelta: TimeMicros

    init(
        success: Bool,
        shifts: [RippleShift],
        operationName: String,
        error: String? = nil,
        timeDelta: TimeMicros
    ) {
        self.success = success
        self.shifts = shifts
        self.operationName = operationName
        self.error = error
        self.timeDelta = timeDelta
    }

    static func success(
        shifts: [RippleShift],
        operationName: String,
        timeDelta: TimeMicros
    ) -> RippleEditResult {
        RippleEditResult(
            success: true,
            shifts: shifts,
            operationName: operationName,
            timeDelta: timeDelta
        )
    }

    static func failure(_ error: String) -> RippleEditResult {
        RippleEditResult(
            success: false,
            shifts: [],
            operationName: "Ripple Edit",
            error: error,
            timeDelta: 0
        )
    }

    /// Number of clips shifted.
    var shiftedCount: Int { shifts.count }
}

// MARK: - RippleTrimPreview

/// Preview of a ripple trim operation.
struct RippleTrimPreview: Equatable, Sendable {
    /// Trimmed clip preview.
    let trimmedClip: TimelineClip

    /// Clips that will shift.
    let shifts: [RippleShift]

    /// Total time delta.
    let timeDelta: TimeMicros

    /// Trim edge (head or tail).
    let edge: TrimEdge
}

// MARK: - RippleDeletePreview

/// Preview of a ripple delete operation.
struct RippleDeletePreview: Equatable, Sendable {
    /// IDs of clips to delete.
    let deleteClipIds: Set<String>

    /// Clips that will shift.
    let shifts: [RippleShift]

    /// Total time delta.
    let timeDelta: TimeMicros
}

// MARK: - RippleEditService

/// Service for ripple edit operations on the timeline.
///
/// In ripple mode, when a clip is trimmed shorter or deleted,
/// all subsequent clips on the same track shift earlier to
/// fill the gap. When a clip is trimmed longer, subsequent clips
/// shift later to accommodate.
///
/// This service calculates the required shifts without modifying
/// the timeline directly. The caller is responsible for applying
/// the shifts via the timeline manager.
@Observable @MainActor
final class RippleEditService {

    /// Current edit mode.
    private(set) var mode: EditMode = .overwrite

    /// Whether ripple mode is active.
    var isRippleMode: Bool { mode == .ripple }

    /// Toggle between ripple and overwrite modes.
    func toggleMode() {
        mode = mode == .ripple ? .overwrite : .ripple
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Set the edit mode directly.
    func setMode(_ mode: EditMode) {
        self.mode = mode
    }

    // MARK: - Ripple Trim

    /// Calculate ripple shifts for a trim operation.
    ///
    /// - Parameters:
    ///   - clip: The clip being trimmed.
    ///   - edge: Which edge is being trimmed (head or tail).
    ///   - trimDelta: Change in duration (positive = longer, negative = shorter).
    ///   - allClips: All clips on the timeline.
    /// - Returns: A `RippleTrimPreview` showing the trimmed clip and shifts,
    ///   or nil if ripple mode is off or no shifts are needed.
    func calculateRippleTrim(
        clip: TimelineClip,
        edge: TrimEdge,
        trimDelta: TimeMicros,
        allClips: [TimelineClip]
    ) -> RippleTrimPreview? {
        guard isRippleMode, trimDelta != 0 else { return nil }

        let trimmedClip: TimelineClip
        let shiftDelta: TimeMicros

        if edge == .left {
            // Trimming head
            trimmedClip = clip.trimHead(clip.startTime + trimDelta)
            let durationChange = trimmedClip.duration - clip.duration
            shiftDelta = -durationChange
        } else {
            // Trimming tail
            trimmedClip = clip.trimTail(clip.endTime + trimDelta)
            let durationChange = trimmedClip.duration - clip.duration
            shiftDelta = durationChange
        }

        guard shiftDelta != 0 else { return nil }

        // Find subsequent clips on the same track that need shifting.
        let afterTime = edge == .right ? clip.endTime : clip.startTime
        let subsequentClips = findSubsequentClips(
            clip: clip,
            allClips: allClips,
            afterTime: afterTime
        )

        let shifts = calculateShifts(subsequentClips, delta: shiftDelta)

        return RippleTrimPreview(
            trimmedClip: trimmedClip,
            shifts: shifts,
            timeDelta: shiftDelta,
            edge: edge
        )
    }

    // MARK: - Ripple Delete

    /// Calculate ripple shifts for a delete operation.
    ///
    /// - Parameters:
    ///   - deleteClipIds: IDs of clips being deleted.
    ///   - allClips: All clips on the timeline.
    /// - Returns: A `RippleDeletePreview` showing which clips will shift.
    func calculateRippleDelete(
        deleteClipIds: Set<String>,
        allClips: [TimelineClip]
    ) -> RippleDeletePreview {
        guard isRippleMode, !deleteClipIds.isEmpty else {
            return RippleDeletePreview(
                deleteClipIds: deleteClipIds,
                shifts: [],
                timeDelta: 0
            )
        }

        // Group deleted clips by track.
        var deletedByTrack: [String: [TimelineClip]] = [:]
        for clip in allClips {
            if deleteClipIds.contains(clip.id) {
                deletedByTrack[clip.trackId, default: []].append(clip)
            }
        }

        var allShifts: [RippleShift] = []
        var totalDelta: TimeMicros = 0

        for (trackId, deletedClips) in deletedByTrack {
            let sortedDeleted = deletedClips.sorted { $0.startTime < $1.startTime }

            // Calculate total duration being removed from this track.
            var trackDelta: TimeMicros = 0
            for clip in sortedDeleted {
                trackDelta += clip.duration
            }

            // Find clips after the earliest deleted clip on this track.
            let earliestDeleteStart = sortedDeleted[0].startTime
            let subsequentClips = allClips
                .filter { c in
                    c.trackId == trackId &&
                    !deleteClipIds.contains(c.id) &&
                    c.startTime >= earliestDeleteStart
                }
                .sorted { $0.startTime < $1.startTime }

            let shifts = calculateShifts(subsequentClips, delta: -trackDelta)
            allShifts.append(contentsOf: shifts)

            if trackDelta > totalDelta {
                totalDelta = trackDelta
            }
        }

        return RippleDeletePreview(
            deleteClipIds: deleteClipIds,
            shifts: allShifts,
            timeDelta: -totalDelta
        )
    }

    // MARK: - Apply Operations

    /// Apply a ripple trim preview to generate the final result.
    func applyRippleTrim(_ preview: RippleTrimPreview) -> RippleEditResult {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        return .success(
            shifts: preview.shifts,
            operationName: "Ripple Trim \(preview.edge == .left ? "Head" : "Tail")",
            timeDelta: preview.timeDelta
        )
    }

    /// Apply a ripple delete preview to generate the final result.
    func applyRippleDelete(_ preview: RippleDeletePreview) -> RippleEditResult {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let count = preview.deleteClipIds.count
        return .success(
            shifts: preview.shifts,
            operationName: "Ripple Delete \(count) clip\(count == 1 ? "" : "s")",
            timeDelta: preview.timeDelta
        )
    }

    // MARK: - Gap Operations

    /// Check if a gap exists between two adjacent clips on the same track.
    ///
    /// Returns the gap duration in microseconds, or 0 if no gap.
    func findGapBetween(_ clipA: TimelineClip, _ clipB: TimelineClip) -> TimeMicros {
        guard clipA.trackId == clipB.trackId else { return 0 }

        let earlier = clipA.startTime <= clipB.startTime ? clipA : clipB
        let later = clipA.startTime <= clipB.startTime ? clipB : clipA

        let gap = later.startTime - earlier.endTime
        return gap > 0 ? gap : 0
    }

    /// Close all gaps on a specific track by shifting clips.
    ///
    /// Returns the shifts needed to remove all gaps.
    func closeAllGaps(
        trackId: String,
        allClips: [TimelineClip]
    ) -> [RippleShift] {
        let trackClips = allClips
            .filter { $0.trackId == trackId && $0.type != .gap }
            .sorted { $0.startTime < $1.startTime }

        guard !trackClips.isEmpty else { return [] }

        var shifts: [RippleShift] = []
        var expectedStart = trackClips[0].startTime

        for clip in trackClips {
            if clip.startTime > expectedStart {
                shifts.append(RippleShift(
                    clipId: clip.id,
                    originalStartTime: clip.startTime,
                    newStartTime: expectedStart,
                    delta: expectedStart - clip.startTime
                ))
                expectedStart += clip.duration
            } else {
                expectedStart = clip.endTime
            }
        }

        return shifts
    }

    // MARK: - Private Helpers

    /// Find clips on the same track that come after a given time.
    private func findSubsequentClips(
        clip: TimelineClip,
        allClips: [TimelineClip],
        afterTime: TimeMicros
    ) -> [TimelineClip] {
        allClips
            .filter { c in
                c.trackId == clip.trackId &&
                c.id != clip.id &&
                c.startTime >= afterTime &&
                c.type != .gap
            }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Calculate shift amounts for a list of clips.
    private func calculateShifts(
        _ clips: [TimelineClip],
        delta: TimeMicros
    ) -> [RippleShift] {
        guard delta != 0, !clips.isEmpty else { return [] }

        return clips.map { clip in
            let newStart = clip.startTime + delta
            let clampedStart = max(newStart, 0)

            return RippleShift(
                clipId: clip.id,
                originalStartTime: clip.startTime,
                newStartTime: clampedStart,
                delta: clampedStart - clip.startTime
            )
        }
    }
}
