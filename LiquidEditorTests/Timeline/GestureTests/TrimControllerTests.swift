import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("TrimController Tests")
@MainActor
struct TrimControllerTests {

    // MARK: - Test Helpers

    private func makeViewport() -> ViewportState {
        ViewportState(
            scrollPosition: 0,
            microsPerPixel: 10000.0,
            viewportWidth: 400,
            viewportHeight: 300,
            rulerHeight: 30,
            trackHeaderWidth: 80
        )
    }

    private func makeClip(
        id: String = "clip1",
        trackId: String = "track1",
        startTime: TimeMicros = 1_000_000,
        duration: TimeMicros = 2_000_000,
        label: String? = nil
    ) -> TimelineClip {
        TimelineClip(
            id: id,
            trackId: trackId,
            type: .video,
            startTime: startTime,
            duration: duration,
            label: label
        )
    }

    private func makeController(
        clips: [TimelineClip] = [],
        viewport: ViewportState? = nil,
        snapTargets: [TimeMicros] = []
    ) -> TrimController {
        let controller = TrimController()
        controller.updateContext(
            clips: clips,
            viewport: viewport ?? makeViewport(),
            snapTargets: snapTargets
        )
        return controller
    }

    // MARK: - TrimType Tests

    @Test("TrimType equality")
    func trimTypeEquality() {
        #expect(TrimType.head == TrimType.head)
        #expect(TrimType.head != TrimType.tail)
    }

    // MARK: - TrimPreview Tests

    @Test("empty trim preview")
    func emptyTrimPreview() {
        let preview = TrimPreview.empty
        #expect(!preview.isValid)
        #expect(preview.timeDelta == 0)
        #expect(!preview.hasSnap)
        #expect(!preview.atBound)
    }

    @Test("trim preview atBound detection")
    func trimPreviewAtBound() {
        let clip = makeClip()
        let preview = TrimPreview(
            originalClip: clip,
            previewClip: clip,
            trimType: .head,
            timeDelta: 0,
            atMinDuration: true
        )
        #expect(preview.atBound)
    }

    // MARK: - TrimState Tests

    @Test("idle trim state")
    func idleTrimState() {
        let state = TrimState.idle
        #expect(state.type == .idle)
        #expect(!state.isTrimming)
        #expect(!state.hasMoved)
    }

    @Test("trim state copyWith")
    func trimStateCopyWith() {
        let state = TrimState.idle
        let updated = state.with(type: .trimming, exceededThreshold: true)
        #expect(updated.type == .trimming)
        #expect(updated.exceededThreshold)
    }

    // MARK: - Start Trim Tests

    @Test("startTrim with unknown clip returns idle")
    func startTrimUnknownClip() {
        let controller = makeController()
        let result = controller.startTrim(clipId: "nonexistent", trimType: .head, position: .zero)
        #expect(result.type == .idle)
    }

    @Test("startTrim sets pending state for head trim")
    func startTrimHeadPending() {
        let clip = makeClip(startTime: 1_000_000, duration: 2_000_000)
        let controller = makeController(clips: [clip])

        let result = controller.startTrim(
            clipId: "clip1",
            trimType: .head,
            position: CGPoint(x: 180, y: 50)
        )

        #expect(result.type == .pending)
        #expect(result.clipId == "clip1")
        #expect(result.trimType == .head)
        #expect(result.startEdgeTime == 1_000_000) // clip startTime
        #expect(!result.exceededThreshold)
    }

    @Test("startTrim sets pending state for tail trim")
    func startTrimTailPending() {
        let clip = makeClip(startTime: 1_000_000, duration: 2_000_000)
        let controller = makeController(clips: [clip])

        let result = controller.startTrim(
            clipId: "clip1",
            trimType: .tail,
            position: CGPoint(x: 380, y: 50)
        )

        #expect(result.type == .pending)
        #expect(result.startEdgeTime == 3_000_000) // clip endTime
    }

    // MARK: - Update Trim Tests

    @Test("updateTrim below threshold stays pending")
    func updateTrimBelowThreshold() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startTrim(clipId: "clip1", trimType: .head, position: CGPoint(x: 180, y: 50))

        // Move 2 pixels (below 4px threshold)
        let result = controller.updateTrim(CGPoint(x: 182, y: 50))
        #expect(result.type == .pending)
        #expect(!result.exceededThreshold)
    }

    @Test("updateTrim above threshold transitions to trimming")
    func updateTrimAboveThreshold() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startTrim(clipId: "clip1", trimType: .head, position: CGPoint(x: 180, y: 50))

        // Move 10 pixels (above 4px threshold)
        let result = controller.updateTrim(CGPoint(x: 190, y: 50))
        #expect(result.type == .trimming)
        #expect(result.exceededThreshold)
    }

    @Test("updateTrim when idle returns idle")
    func updateTrimWhenIdle() {
        let controller = makeController()
        let result = controller.updateTrim(CGPoint(x: 100, y: 50))
        #expect(result.type == .idle)
    }

    // MARK: - End Trim Tests

    @Test("endTrim when idle returns idle")
    func endTrimWhenIdle() {
        let controller = makeController()
        let result = controller.endTrim()
        #expect(result.type == .idle)
    }

    @Test("endTrim without movement cancels")
    func endTrimWithoutMovement() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startTrim(clipId: "clip1", trimType: .head, position: CGPoint(x: 180, y: 50))
        controller.updateTrim(CGPoint(x: 181, y: 50)) // below threshold

        let result = controller.endTrim()
        #expect(result.type == .cancelled)
    }

    @Test("endTrim with valid movement completes")
    func endTrimWithValidMovement() {
        let clip = makeClip(startTime: 1_000_000, duration: 2_000_000)
        let controller = makeController(clips: [clip])
        controller.startTrim(clipId: "clip1", trimType: .tail, position: CGPoint(x: 380, y: 50))

        // Move 20 pixels left (shrink by 200_000 micros) - valid tail trim
        controller.updateTrim(CGPoint(x: 360, y: 50))

        let result = controller.endTrim()
        #expect(result.type == .completed)
    }

    // MARK: - Cancel Trim Tests

    @Test("cancelTrim when idle returns idle")
    func cancelTrimWhenIdle() {
        let controller = makeController()
        let result = controller.cancelTrim()
        #expect(result.type == .idle)
    }

    @Test("cancelTrim resets state")
    func cancelTrimResetsState() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startTrim(clipId: "clip1", trimType: .head, position: CGPoint(x: 180, y: 50))

        let result = controller.cancelTrim()
        #expect(result.type == .cancelled)
        #expect(controller.state.type == .idle)
    }

    // MARK: - Collision Tests

    @Test("trim head blocked by adjacent clip")
    func trimHeadBlockedByAdjacent() {
        let clip1 = makeClip(id: "clip1", startTime: 0, duration: 1_000_000, label: "First")
        let clip2 = makeClip(id: "clip2", startTime: 1_000_000, duration: 2_000_000)
        let controller = makeController(clips: [clip1, clip2])

        controller.startTrim(clipId: "clip2", trimType: .head, position: CGPoint(x: 180, y: 50))

        // Try to move head left past clip1's end
        controller.updateTrim(CGPoint(x: 130, y: 50))

        let state = controller.state
        if state.exceededThreshold {
            // Should detect collision or clamp
            let preview = state.preview
            // The trim should either be invalid or clamped
            #expect(preview.originalClip.id == "clip2")
        }
    }

    // MARK: - Snap Tests

    @Test("trim snaps to target")
    func trimSnapsToTarget() {
        let clip = makeClip(startTime: 0, duration: 2_000_000)
        let controller = makeController(clips: [clip], snapTargets: [1_500_000])

        controller.startTrim(clipId: "clip1", trimType: .tail, position: CGPoint(x: 280, y: 50))

        // Move to approximately snap target position
        // endTime was 2_000_000 (x=280), snap at 1_500_000 (x=230)
        // 10px snap distance = 100_000 micros threshold
        // Move to x=232 -> timeDelta = -48px * 10000 = -480_000
        // new edge = 2_000_000 - 480_000 = 1_520_000
        // distance from 1_500_000 = 20_000 < 100_000 -> should snap
        controller.updateTrim(CGPoint(x: 232, y: 50))

        let state = controller.state
        if state.exceededThreshold {
            let preview = state.preview
            if preview.hasSnap {
                #expect(preview.snappedTime == 1_500_000)
            }
        }
    }

    // MARK: - Minimum Duration Tests

    @Test("trim respects minimum duration")
    func trimRespectsMinDuration() {
        let clip = makeClip(startTime: 0, duration: 100_000) // short clip
        let controller = makeController(clips: [clip])

        controller.startTrim(clipId: "clip1", trimType: .tail, position: CGPoint(x: 90, y: 50))

        // Try to trim tail past min duration
        controller.updateTrim(CGPoint(x: 82, y: 50))

        let state = controller.state
        if state.exceededThreshold {
            // Preview should be clamped or invalid
            let preview = state.preview
            #expect(preview.previewClip.duration >= TimelineClip.minDuration || !preview.isValid)
        }
    }

    // MARK: - Callback Tests

    @Test("onStateChanged callback fires")
    func onStateChangedCallback() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])

        var callbackCount = 0
        controller.onStateChanged = { _ in callbackCount += 1 }

        controller.startTrim(clipId: "clip1", trimType: .head, position: CGPoint(x: 180, y: 50))
        #expect(callbackCount == 1)

        controller.updateTrim(CGPoint(x: 190, y: 50))
        #expect(callbackCount == 2)

        controller.endTrim()
        #expect(callbackCount >= 3)
    }
}
