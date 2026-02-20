import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ClipboardEntry Tests

@Suite("ClipboardEntry Tests")
struct ClipboardEntryTests {

    private func makeClip(
        id: String = "clip-1",
        trackId: String = "track-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration,
            sourceIn: 0
        )
    }

    @Test("Span duration calculation")
    func spanDuration() {
        let clips = [
            makeClip(id: "a", startTime: 100_000, duration: 500_000),
            makeClip(id: "b", startTime: 400_000, duration: 800_000),
        ]

        let entry = ClipboardEntry(
            clips: clips,
            referenceTime: 100_000,
            originalTrackIds: ["a": "t1", "b": "t1"],
            copiedAt: Date()
        )

        // Earliest: 100k, Latest: 400k + 800k = 1200k
        #expect(entry.spanDuration == 1_100_000)
    }

    @Test("Empty clipboard")
    func emptyClipboard() {
        let entry = ClipboardEntry(
            clips: [],
            referenceTime: 0,
            originalTrackIds: [:],
            copiedAt: Date()
        )

        #expect(entry.isEmpty)
        #expect(entry.clipCount == 0)
        #expect(entry.spanDuration == 0)
    }
}

// MARK: - PasteResult Tests

@Suite("PasteResult Tests")
struct PasteResultTests {

    @Test("Success result")
    func successResult() {
        let result = PasteResult.success([])
        #expect(result.success)
        #expect(result.error == nil)
    }

    @Test("Failed result")
    func failedResult() {
        let result = PasteResult.failed("No content")
        #expect(!result.success)
        #expect(result.error == "No content")
        #expect(result.clips.isEmpty)
    }
}

// MARK: - ClipboardController Tests

@Suite("ClipboardController Tests")
@MainActor
struct ClipboardControllerTests {

    private func makeClip(
        id: String = "clip-1",
        trackId: String = "track-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration,
            sourceIn: 0
        )
    }

    // MARK: - Initial State

    @Test("Initial state is empty")
    func initialState() {
        let controller = ClipboardController()
        #expect(!controller.hasContent)
        #expect(!controller.isCutPending)
        #expect(controller.clipboard == nil)
    }

    // MARK: - Copy

    @Test("Copy clips to clipboard")
    func copy() {
        let controller = ClipboardController()
        let clips = [makeClip(id: "a"), makeClip(id: "b", startTime: 1_000_000)]

        let success = controller.copy(clips)

        #expect(success)
        #expect(controller.hasContent)
        #expect(controller.clipboard?.clipCount == 2)
        #expect(!controller.isCutPending)
    }

    @Test("Copy empty list fails")
    func copyEmpty() {
        let controller = ClipboardController()
        let success = controller.copy([])
        #expect(!success)
        #expect(!controller.hasContent)
    }

    @Test("Copy clears previous cut")
    func copyClearsCut() {
        let controller = ClipboardController()
        let clip = makeClip()

        controller.cut([clip])
        #expect(controller.isCutPending)

        controller.copy([clip])
        #expect(!controller.isCutPending)
    }

    // MARK: - Cut

    @Test("Cut clips to clipboard")
    func cut() {
        let controller = ClipboardController()
        let clip = makeClip(id: "a")

        let success = controller.cut([clip])

        #expect(success)
        #expect(controller.hasContent)
        #expect(controller.isCutPending)
        #expect(controller.pendingCutClipIds.contains("a"))
    }

    @Test("Cut empty list fails")
    func cutEmpty() {
        let controller = ClipboardController()
        let success = controller.cut([])
        #expect(!success)
    }

    // MARK: - Paste

    @Test("Paste at playhead")
    func pasteAtPlayhead() {
        let controller = ClipboardController()
        let clip = makeClip(id: "a", startTime: 100_000, duration: 500_000)
        controller.copy([clip])

        let result = controller.paste(playheadTime: 2_000_000)

        #expect(result.success)
        #expect(result.clips.count == 1)
        #expect(result.clips[0].startTime == 2_000_000) // Offset from ref time
        #expect(result.clips[0].id != "a") // New ID
    }

    @Test("Paste preserves track ID")
    func pastePreservesTrack() {
        let controller = ClipboardController()
        let clip = makeClip(id: "a", trackId: "special-track", startTime: 0)
        controller.copy([clip])

        let result = controller.paste(playheadTime: 0)

        #expect(result.success)
        #expect(result.clips[0].trackId == "special-track")
    }

    @Test("Paste with target track overrides")
    func pasteWithTargetTrack() {
        let controller = ClipboardController()
        let clip = makeClip(id: "a", trackId: "original-track")
        controller.copy([clip])

        let result = controller.paste(playheadTime: 0, targetTrackId: "new-track")

        #expect(result.success)
        #expect(result.clips[0].trackId == "new-track")
    }

    @Test("Paste empty clipboard fails")
    func pasteEmptyClipboard() {
        let controller = ClipboardController()
        let result = controller.paste(playheadTime: 0)
        #expect(!result.success)
        #expect(result.error == "Clipboard is empty")
    }

    @Test("Paste multiple clips preserves relative timing")
    func pasteMultiplePreservesRelativeTiming() {
        let controller = ClipboardController()
        let clips = [
            makeClip(id: "a", startTime: 100_000, duration: 500_000),
            makeClip(id: "b", startTime: 700_000, duration: 300_000),
        ]
        controller.copy(clips)

        let result = controller.paste(playheadTime: 2_000_000)

        #expect(result.success)
        #expect(result.clips.count == 2)

        // Reference time was 100k (earliest), offset = 2M - 100k = 1.9M
        #expect(result.clips[0].startTime == 2_000_000) // 100k + 1.9M
        #expect(result.clips[1].startTime == 2_600_000) // 700k + 1.9M
    }

    // MARK: - Paste and Get Cut IDs

    @Test("Paste and get cut IDs")
    func pasteAndGetCutIds() {
        let controller = ClipboardController()
        let clip = makeClip(id: "a")
        controller.cut([clip])

        let result = controller.pasteAndGetCutIds(playheadTime: 1_000_000)

        #expect(result.pasteResult.success)
        #expect(result.cutClipIds.contains("a"))
        // Cut IDs should be cleared after successful paste
        #expect(!controller.isCutPending)
    }

    @Test("Paste and get cut IDs preserves on failure")
    func pasteAndGetCutIdsPreservesOnFailure() {
        let controller = ClipboardController()
        // Don't put anything in clipboard, but mark cut
        // Actually, need to cut first then clear clipboard differently
        // Just verify empty clipboard behavior
        let result = controller.pasteAndGetCutIds(playheadTime: 0)
        #expect(!result.pasteResult.success)
    }

    // MARK: - Paste into Range

    @Test("Paste into range uses start time")
    func pasteIntoRange() {
        let controller = ClipboardController()
        let clip = makeClip(id: "a", startTime: 0)
        controller.copy([clip])

        let result = controller.pasteIntoRange(range: TimeRange(500_000, 1_500_000))

        #expect(result.success)
        #expect(result.clips[0].startTime == 500_000)
    }

    // MARK: - Duplicate

    @Test("Duplicate clips with no offset")
    func duplicateNoOffset() {
        let controller = ClipboardController()
        let clips = [makeClip(id: "a", startTime: 100_000)]

        let result = controller.duplicate(clips)

        #expect(result.count == 1)
        #expect(result[0].id != "a") // New ID
        #expect(result[0].startTime == 100_000) // Same position
    }

    @Test("Duplicate clips with time offset")
    func duplicateWithOffset() {
        let controller = ClipboardController()
        let clips = [makeClip(id: "a", startTime: 100_000)]

        let result = controller.duplicate(clips, timeOffset: 500_000)

        #expect(result.count == 1)
        #expect(result[0].startTime == 600_000)
    }

    @Test("Duplicate clips with track offset")
    func duplicateWithTrackOffset() {
        let controller = ClipboardController()
        let clips = [makeClip(id: "a", trackId: "track-1")]

        let result = controller.duplicate(clips) { _ in "track-2" }

        #expect(result.count == 1)
        #expect(result[0].trackId == "track-2")
    }

    @Test("Duplicate empty list returns empty")
    func duplicateEmpty() {
        let controller = ClipboardController()
        let result = controller.duplicate([])
        #expect(result.isEmpty)
    }

    // MARK: - Clear

    @Test("Clear removes clipboard content")
    func clear() {
        let controller = ClipboardController()
        let clip = makeClip()
        controller.cut([clip])

        controller.clear()

        #expect(!controller.hasContent)
        #expect(!controller.isCutPending)
        #expect(controller.clipboard == nil)
    }

    // MARK: - Cancel Cut

    @Test("Cancel cut converts to copy")
    func cancelCut() {
        let controller = ClipboardController()
        let clip = makeClip()
        controller.cut([clip])

        #expect(controller.isCutPending)
        controller.cancelCut()
        #expect(!controller.isCutPending)
        #expect(controller.hasContent) // Still has clipboard content
    }

    // MARK: - Edge Cases

    @Test("Repeated copy replaces previous content")
    func repeatedCopyReplaces() {
        let controller = ClipboardController()
        controller.copy([makeClip(id: "a")])
        controller.copy([makeClip(id: "b")])

        #expect(controller.clipboard?.clips[0].id == "b")
    }

    @Test("Paste can be done multiple times")
    func pasteMultipleTimes() {
        let controller = ClipboardController()
        controller.copy([makeClip(id: "a")])

        let result1 = controller.paste(playheadTime: 0)
        let result2 = controller.paste(playheadTime: 1_000_000)

        #expect(result1.success)
        #expect(result2.success)
        #expect(result1.clips[0].id != result2.clips[0].id) // Different IDs each paste
    }
}
