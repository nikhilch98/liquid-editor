// ClipboardController.swift
// LiquidEditor
//
// Controller for copy/paste/duplicate with clipboard state.

import Foundation

// MARK: - ClipboardEntry

/// Clipboard entry with timing reference.
struct ClipboardEntry: Equatable, Sendable {
    /// Clips stored in clipboard.
    let clips: [TimelineClip]

    /// Reference time (usually the earliest clip start time).
    let referenceTime: TimeMicros

    /// Track IDs of the original clips (for paste to same track).
    let originalTrackIds: [String: String]

    /// Timestamp when copied.
    let copiedAt: Date

    /// Duration span of all clips in clipboard.
    var spanDuration: TimeMicros {
        guard !clips.isEmpty else { return 0 }

        var earliest = clips[0].startTime
        var latest = clips[0].endTime

        for clip in clips {
            if clip.startTime < earliest { earliest = clip.startTime }
            if clip.endTime > latest { latest = clip.endTime }
        }

        return latest - earliest
    }

    /// Check if clipboard is empty.
    var isEmpty: Bool { clips.isEmpty }

    /// Number of clips in clipboard.
    var clipCount: Int { clips.count }
}

// MARK: - PasteResult

/// Result of paste operation.
struct PasteResult: Equatable, Sendable {
    /// New clips to add to timeline.
    let clips: [TimelineClip]

    /// Whether paste was successful.
    let success: Bool

    /// Error message if failed.
    let error: String?

    init(clips: [TimelineClip], success: Bool, error: String? = nil) {
        self.clips = clips
        self.success = success
        self.error = error
    }

    /// Successful paste result.
    static func success(_ clips: [TimelineClip]) -> PasteResult {
        PasteResult(clips: clips, success: true)
    }

    /// Failed paste result.
    static func failed(_ error: String) -> PasteResult {
        PasteResult(clips: [], success: false, error: error)
    }
}

// MARK: - PasteAndCutResult

/// Result of paste operation that also returns cut clip IDs.
struct PasteAndCutResult: Equatable, Sendable {
    /// The paste result.
    let pasteResult: PasteResult

    /// IDs of clips to delete (from cut operation).
    let cutClipIds: Set<String>
}

// MARK: - ClipboardController

/// Controller for clipboard operations (copy/cut/paste).
///
/// Manages clipboard state and provides copy, cut, paste, and duplicate
/// operations for timeline clips.
@Observable @MainActor
final class ClipboardController {

    /// Current clipboard content.
    private(set) var clipboard: ClipboardEntry?

    /// IDs of clips marked for cut (will be deleted on paste).
    private var cutClipIds: Set<String> = []

    // MARK: - Computed Properties

    /// Check if clipboard has content.
    var hasContent: Bool { clipboard != nil && !(clipboard?.isEmpty ?? true) }

    /// Check if current clipboard content is from a cut operation.
    var isCutPending: Bool { !cutClipIds.isEmpty }

    /// IDs of clips pending cut (to be deleted after paste). Read-only copy.
    var pendingCutClipIds: Set<String> { cutClipIds }

    // MARK: - Copy

    /// Copy clips to clipboard.
    ///
    /// - Parameter clips: The clips to copy.
    /// - Returns: True if copy was successful.
    @discardableResult
    func copy(_ clips: [TimelineClip]) -> Bool {
        guard !clips.isEmpty else { return false }

        // Clear any pending cut
        cutClipIds.removeAll()

        // Find reference time (earliest clip start)
        let referenceTime = clips.map(\.startTime).min()!

        // Store original track IDs
        var originalTrackIds: [String: String] = [:]
        for clip in clips {
            originalTrackIds[clip.id] = clip.trackId
        }

        clipboard = ClipboardEntry(
            clips: clips,
            referenceTime: referenceTime,
            originalTrackIds: originalTrackIds,
            copiedAt: Date()
        )

        return true
    }

    // MARK: - Cut

    /// Cut clips to clipboard (copy + mark for deletion).
    ///
    /// - Parameter clips: The clips to cut.
    /// - Returns: True if cut was successful.
    @discardableResult
    func cut(_ clips: [TimelineClip]) -> Bool {
        guard copy(clips) else { return false }

        // Mark clips for deletion on paste
        cutClipIds.removeAll()
        for clip in clips {
            cutClipIds.insert(clip.id)
        }

        return true
    }

    // MARK: - Paste

    /// Paste clips from clipboard at playhead position.
    ///
    /// - Parameters:
    ///   - playheadTime: The time to paste at.
    ///   - targetTrackId: Optional target track (if nil, uses original tracks).
    ///   - existingClips: Current clips for collision detection.
    /// - Returns: `PasteResult` with new clips or error.
    func paste(
        playheadTime: TimeMicros,
        targetTrackId: String? = nil,
        existingClips: [TimelineClip]? = nil
    ) -> PasteResult {
        guard let entry = clipboard, !entry.isEmpty else {
            return .failed("Clipboard is empty")
        }

        var newClips: [TimelineClip] = []

        // Calculate time offset from reference to playhead
        let timeOffset = playheadTime - entry.referenceTime

        for clip in entry.clips {
            // Generate new ID
            let newId = UUID().uuidString

            // Determine target track
            let newTrackId = targetTrackId ?? entry.originalTrackIds[clip.id] ?? clip.trackId

            // Calculate new start time
            let newStartTime = clip.startTime + timeOffset

            // Create new clip with new ID, track, and position
            let newClip = clip.with(
                id: newId,
                trackId: newTrackId,
                startTime: newStartTime,
                clearLinkedClipId: true // Don't maintain links on paste
            )

            newClips.append(newClip)
        }

        return .success(newClips)
    }

    // MARK: - Paste and Get Cut IDs

    /// Paste clips and get the cut clip IDs to delete.
    ///
    /// - Parameters:
    ///   - playheadTime: The time to paste at.
    ///   - targetTrackId: Optional target track.
    ///   - existingClips: Current clips for collision detection.
    /// - Returns: Paste result and clip IDs to delete.
    func pasteAndGetCutIds(
        playheadTime: TimeMicros,
        targetTrackId: String? = nil,
        existingClips: [TimelineClip]? = nil
    ) -> PasteAndCutResult {
        let result = paste(
            playheadTime: playheadTime,
            targetTrackId: targetTrackId,
            existingClips: existingClips
        )

        let idsToDelete = cutClipIds

        // Clear cut IDs after returning them
        if result.success {
            cutClipIds.removeAll()
        }

        return PasteAndCutResult(pasteResult: result, cutClipIds: idsToDelete)
    }

    // MARK: - Paste into Range

    /// Paste clips relative to a time range.
    ///
    /// Useful for pasting into a selection or in/out range.
    func pasteIntoRange(
        range: TimeRange,
        targetTrackId: String? = nil
    ) -> PasteResult {
        paste(playheadTime: range.start, targetTrackId: targetTrackId)
    }

    // MARK: - Duplicate

    /// Duplicate clips (copy and paste in place with offset).
    ///
    /// - Parameters:
    ///   - clips: The clips to duplicate.
    ///   - timeOffset: Optional offset for duplicated clips.
    ///   - trackOffset: Function to determine new track ID.
    /// - Returns: New duplicated clips.
    func duplicate(
        _ clips: [TimelineClip],
        timeOffset: TimeMicros? = nil,
        trackOffset: ((String) -> String)? = nil
    ) -> [TimelineClip] {
        guard !clips.isEmpty else { return [] }

        var newClips: [TimelineClip] = []
        let offset = timeOffset ?? 0

        for clip in clips {
            let newId = UUID().uuidString
            let newTrackId = trackOffset?(clip.trackId) ?? clip.trackId

            let newClip = clip.with(
                id: newId,
                trackId: newTrackId,
                startTime: clip.startTime + offset,
                clearLinkedClipId: true
            )

            newClips.append(newClip)
        }

        return newClips
    }

    // MARK: - Clear

    /// Clear clipboard content.
    func clear() {
        clipboard = nil
        cutClipIds.removeAll()
    }

    /// Cancel pending cut operation (convert to copy).
    func cancelCut() {
        cutClipIds.removeAll()
    }
}
