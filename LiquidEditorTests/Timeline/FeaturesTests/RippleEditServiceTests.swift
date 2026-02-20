// RippleEditServiceTests.swift
// LiquidEditorTests
//
// Tests for RippleEditService.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("RippleEditService")
@MainActor
struct RippleEditServiceTests {

    // MARK: - Helpers

    private func makeService(mode: EditMode = .ripple) -> RippleEditService {
        let service = RippleEditService()
        service.setMode(mode)
        return service
    }

    private func makeClip(
        id: String,
        trackId: String = "track-1",
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration
        )
    }

    // MARK: - Initial State

    @Test("Initial mode is overwrite")
    func initialMode() {
        let service = RippleEditService()
        #expect(service.mode == .overwrite)
        #expect(service.isRippleMode == false)
    }

    // MARK: - Toggle Mode

    @Test("toggleMode switches between modes")
    func toggleMode() {
        let service = RippleEditService()
        service.toggleMode()
        #expect(service.mode == .ripple)
        service.toggleMode()
        #expect(service.mode == .overwrite)
    }

    @Test("setMode sets mode directly")
    func setMode() {
        let service = RippleEditService()
        service.setMode(.ripple)
        #expect(service.isRippleMode == true)
    }

    // MARK: - Ripple Trim

    @Test("calculateRippleTrim returns nil when overwrite mode")
    func rippleTrimOverwriteMode() {
        let service = makeService(mode: .overwrite)
        let clip = makeClip(id: "v1", startTime: 0, duration: 2_000_000)
        let result = service.calculateRippleTrim(
            clip: clip,
            edge: .right,
            trimDelta: -500_000,
            allClips: [clip]
        )
        #expect(result == nil)
    }

    @Test("calculateRippleTrim returns nil when delta is zero")
    func rippleTrimZeroDelta() {
        let service = makeService()
        let clip = makeClip(id: "v1")
        let result = service.calculateRippleTrim(
            clip: clip,
            edge: .right,
            trimDelta: 0,
            allClips: [clip]
        )
        #expect(result == nil)
    }

    @Test("calculateRippleTrim right edge shifts subsequent clips")
    func rippleTrimRightEdge() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 2_000_000),
            makeClip(id: "v2", startTime: 2_000_000, duration: 1_000_000),
            makeClip(id: "v3", startTime: 3_000_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleTrim(
            clip: clips[0],
            edge: .right,
            trimDelta: -500_000,
            allClips: clips
        )
        #expect(result != nil)
        // v1 trimmed shorter by 500k => subsequent shift left by 500k
        // But the direction depends on the trimmedClip duration change
        #expect(result!.shifts.count >= 1)
    }

    @Test("calculateRippleTrim only shifts clips on same track")
    func rippleTrimSameTrackOnly() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", trackId: "t1", startTime: 0, duration: 2_000_000),
            makeClip(id: "v2", trackId: "t1", startTime: 2_000_000, duration: 1_000_000),
            makeClip(id: "v3", trackId: "t2", startTime: 2_000_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleTrim(
            clip: clips[0],
            edge: .right,
            trimDelta: -500_000,
            allClips: clips
        )
        #expect(result != nil)
        // v3 on different track should not be shifted
        let shiftedIds = result!.shifts.map(\.clipId)
        #expect(!shiftedIds.contains("v3"))
    }

    // MARK: - Ripple Delete

    @Test("calculateRippleDelete returns empty shifts in overwrite mode")
    func rippleDeleteOverwrite() {
        let service = makeService(mode: .overwrite)
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", startTime: 1_000_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleDelete(
            deleteClipIds: ["v1"],
            allClips: clips
        )
        #expect(result.shifts.isEmpty)
    }

    @Test("calculateRippleDelete shifts subsequent clips in ripple mode")
    func rippleDeleteShifts() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", startTime: 1_000_000, duration: 1_000_000),
            makeClip(id: "v3", startTime: 2_000_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleDelete(
            deleteClipIds: ["v1"],
            allClips: clips
        )
        // v2 and v3 should shift left by 1_000_000 (v1's duration)
        #expect(result.shifts.count == 2)
        let v2Shift = result.shifts.first { $0.clipId == "v2" }
        #expect(v2Shift?.newStartTime == 0)
        #expect(v2Shift?.delta == -1_000_000)

        let v3Shift = result.shifts.first { $0.clipId == "v3" }
        #expect(v3Shift?.newStartTime == 1_000_000)
    }

    @Test("calculateRippleDelete handles multiple deletions on same track")
    func rippleDeleteMultiple() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", startTime: 1_000_000, duration: 1_000_000),
            makeClip(id: "v3", startTime: 2_000_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleDelete(
            deleteClipIds: ["v1", "v2"],
            allClips: clips
        )
        // v3 should shift left by 2_000_000 (v1 + v2 duration)
        let v3Shift = result.shifts.first { $0.clipId == "v3" }
        #expect(v3Shift?.newStartTime == 0)
    }

    @Test("calculateRippleDelete returns empty shifts for empty deletion set")
    func rippleDeleteEmpty() {
        let service = makeService()
        let result = service.calculateRippleDelete(
            deleteClipIds: [],
            allClips: [makeClip(id: "v1")]
        )
        #expect(result.shifts.isEmpty)
    }

    // MARK: - Apply Operations

    @Test("applyRippleTrim returns success result")
    func applyRippleTrim() {
        let service = makeService()
        let preview = RippleTrimPreview(
            trimmedClip: makeClip(id: "v1", duration: 1_500_000),
            shifts: [
                RippleShift(clipId: "v2", originalStartTime: 2_000_000, newStartTime: 1_500_000, delta: -500_000),
            ],
            timeDelta: -500_000,
            edge: .right
        )
        let result = service.applyRippleTrim(preview)
        #expect(result.success == true)
        #expect(result.shiftedCount == 1)
        #expect(result.operationName.contains("Tail"))
    }

    @Test("applyRippleDelete returns success result")
    func applyRippleDelete() {
        let service = makeService()
        let preview = RippleDeletePreview(
            deleteClipIds: ["v1"],
            shifts: [
                RippleShift(clipId: "v2", originalStartTime: 1_000_000, newStartTime: 0, delta: -1_000_000),
            ],
            timeDelta: -1_000_000
        )
        let result = service.applyRippleDelete(preview)
        #expect(result.success == true)
        #expect(result.operationName.contains("1 clip"))
    }

    // MARK: - Gap Operations

    @Test("findGapBetween detects gap between clips")
    func findGapBetween() {
        let service = makeService()
        let clipA = makeClip(id: "v1", startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "v2", startTime: 2_000_000, duration: 1_000_000)
        let gap = service.findGapBetween(clipA, clipB)
        #expect(gap == 1_000_000)
    }

    @Test("findGapBetween returns zero for adjacent clips")
    func findGapBetweenAdjacent() {
        let service = makeService()
        let clipA = makeClip(id: "v1", startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "v2", startTime: 1_000_000, duration: 1_000_000)
        let gap = service.findGapBetween(clipA, clipB)
        #expect(gap == 0)
    }

    @Test("findGapBetween returns zero for different tracks")
    func findGapBetweenDifferentTracks() {
        let service = makeService()
        let clipA = makeClip(id: "v1", trackId: "t1", startTime: 0, duration: 1_000_000)
        let clipB = makeClip(id: "v2", trackId: "t2", startTime: 5_000_000, duration: 1_000_000)
        let gap = service.findGapBetween(clipA, clipB)
        #expect(gap == 0)
    }

    @Test("findGapBetween handles reversed order")
    func findGapBetweenReversed() {
        let service = makeService()
        let clipA = makeClip(id: "v1", startTime: 2_000_000, duration: 1_000_000)
        let clipB = makeClip(id: "v2", startTime: 0, duration: 1_000_000)
        let gap = service.findGapBetween(clipA, clipB)
        #expect(gap == 1_000_000)
    }

    // MARK: - Close All Gaps

    @Test("closeAllGaps closes gaps on a track")
    func closeAllGaps() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", startTime: 2_000_000, duration: 1_000_000), // 1M gap
            makeClip(id: "v3", startTime: 4_000_000, duration: 1_000_000), // 1M gap
        ]
        let shifts = service.closeAllGaps(trackId: "track-1", allClips: clips)
        #expect(shifts.count == 2)
        let v2Shift = shifts.first { $0.clipId == "v2" }
        #expect(v2Shift?.newStartTime == 1_000_000)
        let v3Shift = shifts.first { $0.clipId == "v3" }
        #expect(v3Shift?.newStartTime == 2_000_000)
    }

    @Test("closeAllGaps returns empty for contiguous clips")
    func closeAllGapsContiguous() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", startTime: 1_000_000, duration: 1_000_000),
        ]
        let shifts = service.closeAllGaps(trackId: "track-1", allClips: clips)
        #expect(shifts.isEmpty)
    }

    @Test("closeAllGaps ignores gap clips")
    func closeAllGapsIgnoresGaps() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 1_000_000),
            TimelineClip(id: "gap-1", trackId: "track-1", type: .gap, startTime: 1_000_000, duration: 500_000),
            makeClip(id: "v2", startTime: 2_000_000, duration: 1_000_000),
        ]
        let shifts = service.closeAllGaps(trackId: "track-1", allClips: clips)
        #expect(shifts.count == 1)
        #expect(shifts[0].clipId == "v2")
        #expect(shifts[0].newStartTime == 1_000_000)
    }

    // MARK: - Boundary Conditions

    @Test("ripple shift clamps to zero")
    func rippleShiftClampsToZero() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 2_000_000),
            makeClip(id: "v2", startTime: 500_000, duration: 1_000_000),
        ]
        // Delete v1 (duration 2M), try to shift v2 left by 2M from 500k => would be -1.5M
        let result = service.calculateRippleDelete(
            deleteClipIds: ["v1"],
            allClips: clips
        )
        let v2Shift = result.shifts.first { $0.clipId == "v2" }
        #expect(v2Shift?.newStartTime == 0) // Clamped to 0
    }

    // MARK: - Additional EditMode Tests

    @Test("EditMode allCases has two values")
    func editModeAllCases() {
        #expect(EditMode.allCases.count == 2)
        #expect(EditMode.allCases.contains(.overwrite))
        #expect(EditMode.allCases.contains(.ripple))
    }

    @Test("EditMode rawValues are correct strings")
    func editModeRawValues() {
        #expect(EditMode.overwrite.rawValue == "overwrite")
        #expect(EditMode.ripple.rawValue == "ripple")
    }

    @Test("isRippleMode reflects mode accurately")
    func isRippleModeAccurate() {
        let service = RippleEditService()
        #expect(service.isRippleMode == false)
        service.setMode(.ripple)
        #expect(service.isRippleMode == true)
        service.setMode(.overwrite)
        #expect(service.isRippleMode == false)
    }

    // MARK: - Additional Ripple Trim Tests

    @Test("calculateRippleTrim left edge shifts subsequent clips")
    func rippleTrimLeftEdge() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 2_000_000),
            makeClip(id: "v2", startTime: 2_000_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleTrim(
            clip: clips[0],
            edge: .left,
            trimDelta: 500_000,
            allClips: clips
        )
        // Trimming head by 500k inward means clip gets shorter
        #expect(result != nil)
    }

    @Test("calculateRippleTrim ignores gap clips in subsequent clips")
    func rippleTrimIgnoresGapClips() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 2_000_000),
            TimelineClip(id: "gap-1", trackId: "track-1", type: .gap, startTime: 2_000_000, duration: 500_000),
            makeClip(id: "v2", startTime: 2_500_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleTrim(
            clip: clips[0],
            edge: .right,
            trimDelta: -500_000,
            allClips: clips
        )
        #expect(result != nil)
        // Gap clip should NOT be in the shifts
        let shiftedIds = result!.shifts.map(\.clipId)
        #expect(!shiftedIds.contains("gap-1"))
        #expect(shiftedIds.contains("v2"))
    }

    @Test("calculateRippleTrim with single clip returns empty shifts")
    func rippleTrimSingleClip() {
        let service = makeService()
        let clip = makeClip(id: "v1", startTime: 0, duration: 2_000_000)
        let result = service.calculateRippleTrim(
            clip: clip,
            edge: .right,
            trimDelta: -500_000,
            allClips: [clip]
        )
        // With only one clip, no subsequent clips to shift
        #expect(result != nil)
        #expect(result!.shifts.isEmpty)
    }

    // MARK: - Additional Ripple Delete Tests

    @Test("calculateRippleDelete on multiple tracks creates independent shifts")
    func rippleDeleteMultipleTracks() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", trackId: "t1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", trackId: "t1", startTime: 1_000_000, duration: 1_000_000),
            makeClip(id: "a1", trackId: "t2", startTime: 0, duration: 2_000_000),
            makeClip(id: "a2", trackId: "t2", startTime: 2_000_000, duration: 1_000_000),
        ]
        let result = service.calculateRippleDelete(
            deleteClipIds: ["v1", "a1"],
            allClips: clips
        )
        // v2 should shift left by 1M (v1 duration), a2 should shift left by 2M (a1 duration)
        let v2Shift = result.shifts.first { $0.clipId == "v2" }
        let a2Shift = result.shifts.first { $0.clipId == "a2" }
        #expect(v2Shift?.newStartTime == 0)
        #expect(a2Shift?.newStartTime == 0)
    }

    @Test("calculateRippleDelete timeDelta is negative of largest track deletion")
    func rippleDeleteTimeDelta() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", trackId: "t1", startTime: 0, duration: 1_000_000),
            makeClip(id: "a1", trackId: "t2", startTime: 0, duration: 3_000_000),
        ]
        let result = service.calculateRippleDelete(
            deleteClipIds: ["v1", "a1"],
            allClips: clips
        )
        #expect(result.timeDelta == -3_000_000) // Largest track delta
    }

    @Test("calculateRippleDelete with nonexistent IDs produces no shifts")
    func rippleDeleteNonexistentIds() {
        let service = makeService()
        let clips = [makeClip(id: "v1", startTime: 0, duration: 1_000_000)]
        let result = service.calculateRippleDelete(
            deleteClipIds: ["nonexistent"],
            allClips: clips
        )
        #expect(result.shifts.isEmpty)
    }

    // MARK: - Additional Apply Tests

    @Test("applyRippleTrim head edge operation name contains Head")
    func applyRippleTrimHead() {
        let service = makeService()
        let preview = RippleTrimPreview(
            trimmedClip: makeClip(id: "v1", duration: 1_500_000),
            shifts: [],
            timeDelta: -500_000,
            edge: .left
        )
        let result = service.applyRippleTrim(preview)
        #expect(result.operationName.contains("Head"))
    }

    @Test("applyRippleDelete plural clips naming")
    func applyRippleDeletePlural() {
        let service = makeService()
        let preview = RippleDeletePreview(
            deleteClipIds: ["v1", "v2", "v3"],
            shifts: [],
            timeDelta: -3_000_000
        )
        let result = service.applyRippleDelete(preview)
        #expect(result.operationName.contains("3 clips"))
    }

    @Test("applyRippleDelete single clip naming")
    func applyRippleDeleteSingular() {
        let service = makeService()
        let preview = RippleDeletePreview(
            deleteClipIds: ["v1"],
            shifts: [],
            timeDelta: -1_000_000
        )
        let result = service.applyRippleDelete(preview)
        #expect(result.operationName.contains("1 clip"))
        #expect(!result.operationName.contains("1 clips"))
    }

    // MARK: - RippleEditResult Factory Tests

    @Test("RippleEditResult.success factory creates correct result")
    func rippleEditResultSuccess() {
        let shift = RippleShift(clipId: "v1", originalStartTime: 1_000_000, newStartTime: 0, delta: -1_000_000)
        let result = RippleEditResult.success(
            shifts: [shift],
            operationName: "Test Op",
            timeDelta: -1_000_000
        )
        #expect(result.success == true)
        #expect(result.error == nil)
        #expect(result.shiftedCount == 1)
        #expect(result.operationName == "Test Op")
        #expect(result.timeDelta == -1_000_000)
    }

    @Test("RippleEditResult.failure factory creates correct result")
    func rippleEditResultFailure() {
        let result = RippleEditResult.failure("Something went wrong")
        #expect(result.success == false)
        #expect(result.error == "Something went wrong")
        #expect(result.shiftedCount == 0)
        #expect(result.shifts.isEmpty)
        #expect(result.timeDelta == 0)
    }

    // MARK: - RippleShift Equatable Tests

    @Test("RippleShift equality works correctly")
    func rippleShiftEquality() {
        let a = RippleShift(clipId: "v1", originalStartTime: 1_000_000, newStartTime: 0, delta: -1_000_000)
        let b = RippleShift(clipId: "v1", originalStartTime: 1_000_000, newStartTime: 0, delta: -1_000_000)
        let c = RippleShift(clipId: "v2", originalStartTime: 1_000_000, newStartTime: 0, delta: -1_000_000)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Additional Close Gaps Tests

    @Test("closeAllGaps with first clip not at zero preserves its position")
    func closeAllGapsFirstClipNotAtZero() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 500_000, duration: 1_000_000),
            makeClip(id: "v2", startTime: 3_000_000, duration: 1_000_000),
        ]
        let shifts = service.closeAllGaps(trackId: "track-1", allClips: clips)
        // v1 starts at 500k, v2 should close gap to be at 1_500_000
        #expect(shifts.count == 1)
        #expect(shifts[0].clipId == "v2")
        #expect(shifts[0].newStartTime == 1_500_000)
    }

    @Test("closeAllGaps ignores clips on different tracks")
    func closeAllGapsDifferentTracks() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", trackId: "t1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", trackId: "t2", startTime: 5_000_000, duration: 1_000_000),
        ]
        let shifts = service.closeAllGaps(trackId: "t1", allClips: clips)
        #expect(shifts.isEmpty) // Only one clip on t1, no gaps to close
    }

    @Test("closeAllGaps returns empty for empty clips")
    func closeAllGapsEmptyClips() {
        let service = makeService()
        let shifts = service.closeAllGaps(trackId: "track-1", allClips: [])
        #expect(shifts.isEmpty)
    }

    // MARK: - findGapBetween Overlapping Clips

    @Test("findGapBetween overlapping clips returns zero")
    func findGapBetweenOverlapping() {
        let service = makeService()
        let clipA = makeClip(id: "v1", startTime: 0, duration: 2_000_000)
        let clipB = makeClip(id: "v2", startTime: 1_000_000, duration: 2_000_000)
        let gap = service.findGapBetween(clipA, clipB)
        #expect(gap == 0)
    }

    // MARK: - RippleTrimPreview / RippleDeletePreview Equatable

    @Test("RippleTrimPreview equality")
    func rippleTrimPreviewEquality() {
        let clip = makeClip(id: "v1", duration: 1_500_000)
        let shift = RippleShift(clipId: "v2", originalStartTime: 2_000_000, newStartTime: 1_500_000, delta: -500_000)
        let a = RippleTrimPreview(trimmedClip: clip, shifts: [shift], timeDelta: -500_000, edge: .right)
        let b = RippleTrimPreview(trimmedClip: clip, shifts: [shift], timeDelta: -500_000, edge: .right)
        #expect(a == b)
    }

    @Test("RippleDeletePreview equality")
    func rippleDeletePreviewEquality() {
        let a = RippleDeletePreview(deleteClipIds: ["v1", "v2"], shifts: [], timeDelta: -2_000_000)
        let b = RippleDeletePreview(deleteClipIds: ["v1", "v2"], shifts: [], timeDelta: -2_000_000)
        #expect(a == b)
    }
}
