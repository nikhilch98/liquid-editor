// RippleTrimController.swift
// LiquidEditor
//
// Controller for trimming with automatic clip repositioning (ripple).

import Foundation
import os

// MARK: - RippleTrimMode

/// Ripple mode for trim operations.
enum RippleTrimMode: String, Sendable, CaseIterable {
    /// Only trim the selected clip.
    case none
    /// Ripple subsequent clips on the same track.
    case track
    /// Ripple subsequent clips on all tracks.
    case allTracks
}

// MARK: - RippleResult

/// Result of ripple calculation.
struct RippleResult: Equatable, Sendable {
    /// Clips affected by ripple with their new positions.
    let rippleClips: [RipplePreview]

    /// Total duration change caused by trim.
    let durationDelta: TimeMicros

    /// No ripple effect.
    static let none = RippleResult(rippleClips: [], durationDelta: 0)
}

// MARK: - RippleTrimController

/// Controller for ripple trim operations.
///
/// Ripple trim extends the standard trim behavior by automatically
/// moving subsequent clips to maintain timing relationships.
@Observable @MainActor
final class RippleTrimController {

    private static let logger = Logger(subsystem: "LiquidEditor", category: "RippleTrimController")

    /// Current ripple mode.
    var mode: RippleTrimMode = .track

    // MARK: - Calculate Trim Preview

    /// Calculate trim preview with ripple effect.
    ///
    /// - Parameters:
    ///   - clip: The clip being trimmed.
    ///   - edge: The edge being trimmed (left or right).
    ///   - trimDelta: The trim amount in microseconds.
    ///   - allClips: All clips in the timeline.
    ///   - trackClips: Maps track ID to clips for that track.
    /// - Returns: An `EditTrimPreview` with ripple information.
    func calculateTrimPreview(
        clip: TimelineClip,
        edge: TrimEdge,
        trimDelta: TimeMicros,
        allClips: [TimelineClip],
        trackClips: [String: [TimelineClip]]
    ) -> EditTrimPreview {
        // Calculate the basic trim first
        guard let trimmedClip = applyTrim(clip, edge: edge, delta: trimDelta) else {
            Self.logger.warning("Ripple trim preview failed: trim would violate min duration constraint for clip \(clip.id) (edge: \(edge.rawValue), delta: \(trimDelta))")
            return .empty()
        }

        // Calculate duration change
        let durationDelta = trimmedClip.duration - clip.duration

        // Calculate ripple effect
        let rippleResult = calculateRipple(
            clip: clip,
            edge: edge,
            durationDelta: durationDelta,
            allClips: allClips,
            trackClips: trackClips
        )

        return EditTrimPreview(
            clipId: clip.id,
            newStartTime: trimmedClip.startTime,
            newDuration: trimmedClip.duration,
            newSourceIn: trimmedClip.sourceIn,
            newSourceOut: trimmedClip.sourceOut,
            snapGuide: nil,
            trimmedDelta: durationDelta,
            rippleClips: rippleResult.rippleClips
        )
    }

    // MARK: - Apply Trim

    /// Apply trim to a clip.
    private func applyTrim(_ clip: TimelineClip, edge: TrimEdge, delta: TimeMicros) -> TimelineClip? {
        if edge == .left {
            // Trim head
            let newStartTime = clip.startTime + delta
            if newStartTime < 0 { return nil }

            let newDuration = clip.duration - delta
            if newDuration < TimelineClip.minDuration { return nil }

            return clip.trimHead(newStartTime)
        } else {
            // Trim tail
            let newEndTime = clip.endTime + delta
            if newEndTime <= clip.startTime + TimelineClip.minDuration { return nil }

            return clip.trimTail(newEndTime)
        }
    }

    // MARK: - Calculate Ripple

    /// Calculate ripple effect on subsequent clips.
    private func calculateRipple(
        clip: TimelineClip,
        edge: TrimEdge,
        durationDelta: TimeMicros,
        allClips: [TimelineClip],
        trackClips: [String: [TimelineClip]]
    ) -> RippleResult {
        if mode == .none || durationDelta == 0 {
            return .none
        }

        var rippleClips: [RipplePreview] = []

        // Determine the ripple threshold time
        // For left edge trim: clips starting after clip.startTime
        // For right edge trim: clips starting after clip.endTime
        let thresholdTime = edge == .left ? clip.startTime : clip.endTime

        if mode == .track {
            // Ripple only on the same track
            let sameTrackClips = trackClips[clip.trackId] ?? []
            addRippleClips(
                to: &rippleClips,
                clips: sameTrackClips,
                excludeClipId: clip.id,
                thresholdTime: thresholdTime,
                delta: durationDelta
            )
        } else if mode == .allTracks {
            // Ripple on all tracks
            addRippleClips(
                to: &rippleClips,
                clips: allClips,
                excludeClipId: clip.id,
                thresholdTime: thresholdTime,
                delta: durationDelta
            )
        }

        return RippleResult(rippleClips: rippleClips, durationDelta: durationDelta)
    }

    /// Add clips affected by ripple.
    private func addRippleClips(
        to rippleClips: inout [RipplePreview],
        clips: [TimelineClip],
        excludeClipId: String,
        thresholdTime: TimeMicros,
        delta: TimeMicros
    ) {
        for c in clips {
            // Skip the clip being trimmed
            if c.id == excludeClipId { continue }

            // Only ripple clips that start after the threshold
            if c.startTime >= thresholdTime {
                rippleClips.append(RipplePreview(
                    clipId: c.id,
                    newStartTime: c.startTime + delta
                ))
            }
        }
    }

    // MARK: - Apply Ripple Trim

    /// Apply ripple trim result to clips.
    ///
    /// - Parameters:
    ///   - allClips: All clips in the timeline.
    ///   - preview: The calculated trim preview.
    /// - Returns: Updated clip list.
    func applyRippleTrim(_ allClips: [TimelineClip], preview: EditTrimPreview) -> [TimelineClip] {
        var rippleMap: [String: TimeMicros] = [:]
        if let rippleClips = preview.rippleClips {
            for ripple in rippleClips {
                rippleMap[ripple.clipId] = ripple.newStartTime
            }
        }

        return allClips.map { clip in
            if clip.id == preview.clipId {
                // Apply trim to the target clip
                return clip.with(
                    startTime: preview.newStartTime,
                    duration: preview.newDuration,
                    sourceIn: preview.newSourceIn,
                    sourceOut: preview.newSourceOut
                )
            } else if let newStart = rippleMap[clip.id] {
                // Apply ripple offset
                return clip.with(startTime: newStart)
            }
            return clip
        }
    }

    // MARK: - Overlap Detection

    /// Check if ripple would create overlaps.
    ///
    /// - Parameters:
    ///   - clip: The clip being trimmed.
    ///   - preview: The calculated trim preview.
    ///   - trackClips: Maps track ID to clips for collision detection.
    /// - Returns: True if ripple would cause overlaps.
    func wouldCauseOverlap(
        clip: TimelineClip,
        preview: EditTrimPreview,
        trackClips: [String: [TimelineClip]]
    ) -> Bool {
        // Collect all affected clip positions after ripple
        var affectedPositions: [String: TimeRange] = [:]

        // The trimmed clip's new position
        let trimmedRange = TimeRange(
            preview.newStartTime,
            preview.newStartTime + preview.newDuration
        )
        affectedPositions[clip.id] = trimmedRange

        // Rippled clips
        if let rippleClips = preview.rippleClips {
            for ripple in rippleClips {
                let originalClip = trackClips[clip.trackId]?.first { $0.id == ripple.clipId }
                if let originalClip {
                    affectedPositions[ripple.clipId] = TimeRange(
                        ripple.newStartTime,
                        ripple.newStartTime + originalClip.duration
                    )
                }
            }
        }

        // Check for overlaps within each track
        for (trackId, clips) in trackClips {
            var trackRanges: [TimeRange] = []
            for c in clips {
                if c.trackId != trackId { continue }

                if let affected = affectedPositions[c.id] {
                    trackRanges.append(affected)
                } else if c.id != clip.id {
                    trackRanges.append(c.timeRange)
                }
            }

            // Check each pair for overlap
            for i in 0..<trackRanges.count {
                for j in (i + 1)..<trackRanges.count {
                    if trackRanges[i].overlaps(trackRanges[j]) {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - Affected Clips

    /// Get clips that would be affected by ripple.
    ///
    /// - Parameters:
    ///   - clip: The clip being trimmed.
    ///   - edge: The trim edge.
    ///   - allClips: All clips in the timeline.
    /// - Returns: List of clip IDs that would be rippled.
    func getAffectedClipIds(
        clip: TimelineClip,
        edge: TrimEdge,
        allClips: [TimelineClip]
    ) -> [String] {
        if mode == .none { return [] }

        let thresholdTime = edge == .left ? clip.startTime : clip.endTime
        var affectedIds: [String] = []

        for c in allClips {
            if c.id == clip.id { continue }

            // Check track filter
            if mode == .track && c.trackId != clip.trackId {
                continue
            }

            if c.startTime >= thresholdTime {
                affectedIds.append(c.id)
            }
        }

        return affectedIds
    }
}
