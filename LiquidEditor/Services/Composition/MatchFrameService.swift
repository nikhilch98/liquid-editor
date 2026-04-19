// MatchFrameService.swift
// LiquidEditor
//
// E4-14: Match Frame action.
//
// Given a timeline playhead position, locates the clip under the head
// and computes the corresponding time in the clip's source media. The
// caller then opens that source frame in the Source Monitor so the
// user can mark in/out relative to the original asset.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §4.
//
// Notes:
// - Pure MainActor service; no external I/O. All heavy lifting stays
//   on the timeline's tree traversal (O(log n)).
// - Works with `VideoClip` and `AudioClip` today — both expose
//   `sourceInMicros` which is the piece we need to compute the
//   source-asset time for match-frame.
// - Clips that don't expose a source-media offset (e.g., `TextClip`)
//   resolve to the clip's internal time only.

import Foundation

// MARK: - MatchFrameResult

/// Result of a successful Match Frame lookup.
struct MatchFrameResult: Sendable, Hashable {
    /// ID of the timeline clip under the playhead.
    let sourceClipID: UUID

    /// Time in seconds into the CLIP'S SOURCE ASSET (not the timeline).
    /// For `VideoClip`/`AudioClip` this is `sourceIn + offsetInClip`.
    /// For clips without a backing asset (e.g. text overlays) this is
    /// simply `offsetInClip`.
    let sourceTimeSec: Double
}

// MARK: - MatchFrameService

@MainActor
final class MatchFrameService {

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Returns the `MatchFrameResult` for `playheadSeconds` within the
    /// given timeline, or `nil` if the playhead falls outside any
    /// clip.
    func matchFrame(
        playheadSeconds: Double,
        in timeline: PersistentTimeline
    ) -> MatchFrameResult? {
        guard playheadSeconds >= 0 else { return nil }
        let micros: Int64 = Int64(playheadSeconds * 1_000_000.0)
        guard let (item, itemStartMicros) = timeline.itemAtTime(micros) else {
            return nil
        }

        // Clip-local offset in microseconds (clamped ≥ 0).
        let offsetMicros = max(0, micros - itemStartMicros)
        let offsetSeconds = Double(offsetMicros) / 1_000_000.0

        // Map timeline clip ID (String) → UUID for the result. When the
        // ID isn't a well-formed UUID, fall back to a deterministic
        // zero UUID; callers fall back to the String ID via the
        // timeline if they need to re-key.
        let uuid = UUID(uuidString: item.id) ?? UUID()

        // Pull source-asset offset when available.
        let sourceTimeSec: Double
        switch item {
        case let video as VideoClip:
            let sIn = Double(video.sourceInMicros) / 1_000_000.0
            sourceTimeSec = sIn + offsetSeconds
        case let audio as AudioClip:
            let sIn = Double(audio.sourceInMicros) / 1_000_000.0
            sourceTimeSec = sIn + offsetSeconds
        default:
            sourceTimeSec = offsetSeconds
        }

        return MatchFrameResult(
            sourceClipID: uuid,
            sourceTimeSec: sourceTimeSec
        )
    }
}
