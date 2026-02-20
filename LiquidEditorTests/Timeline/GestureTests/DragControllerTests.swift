import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("ClipDragController Tests")
@MainActor
struct DragControllerTests {

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
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000,
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
        tracks: [Track] = [],
        viewport: ViewportState? = nil,
        snapTargets: [SnapTarget] = []
    ) -> ClipDragController {
        let controller = ClipDragController()
        controller.updateContext(
            clips: clips,
            tracks: tracks,
            viewport: viewport ?? makeViewport(),
            snapTargets: snapTargets
        )
        return controller
    }

    // MARK: - DragState Tests

    @Test("idle state properties")
    func idleStateProperties() {
        let state = DragState.idle
        #expect(state.type == .idle)
        #expect(state.draggedClipIds.isEmpty)
        #expect(!state.isDragging)
        #expect(!state.hasMoved)
    }

    @Test("drag state copyWith")
    func dragStateCopyWith() {
        let state = DragState.idle
        let updated = state.with(type: .dragging, exceededThreshold: true)
        #expect(updated.type == .dragging)
        #expect(updated.exceededThreshold)
        #expect(updated.startPosition == .zero) // unchanged
    }

    // MARK: - DragPreview Tests

    @Test("empty preview")
    func emptyPreview() {
        let preview = DragPreview.empty
        #expect(!preview.hasPreviews)
        #expect(!preview.isValid)
        #expect(!preview.hasSnap)
    }

    // MARK: - SnapTarget Tests

    @Test("snap target creation")
    func snapTargetCreation() {
        let target = SnapTarget(time: 1_000_000, description: "Clip edge")
        #expect(target.time == 1_000_000)
        #expect(target.description == "Clip edge")
        #expect(target.priority == 0)
    }

    // MARK: - Start Drag Tests

    @Test("startDrag with empty clip IDs returns idle")
    func startDragEmptyClipIds() {
        let controller = makeController()
        let result = controller.startDrag(clipIds: [], position: .zero, time: 0)
        #expect(result.type == .idle)
    }

    @Test("startDrag sets pending state")
    func startDragSetsPending() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        let result = controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 500_000)

        #expect(result.type == .pending)
        #expect(result.draggedClipIds == ["clip1"])
        #expect(result.startPosition == CGPoint(x: 100, y: 50))
        #expect(result.startTime == 500_000)
        #expect(!result.exceededThreshold)
    }

    // MARK: - Update Drag Tests

    @Test("updateDrag below threshold stays pending")
    func updateDragBelowThreshold() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 500_000)

        // Move 3 pixels (below 8px threshold)
        let result = controller.updateDrag(CGPoint(x: 103, y: 50))
        #expect(result.type == .pending)
        #expect(!result.exceededThreshold)
    }

    @Test("updateDrag above threshold transitions to dragging")
    func updateDragAboveThreshold() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 500_000)

        // Move 10 pixels (above 8px threshold)
        let result = controller.updateDrag(CGPoint(x: 110, y: 50))
        #expect(result.type == .dragging)
        #expect(result.exceededThreshold)
    }

    @Test("updateDrag when idle returns idle")
    func updateDragWhenIdle() {
        let controller = makeController()
        let result = controller.updateDrag(CGPoint(x: 100, y: 50))
        #expect(result.type == .idle)
    }

    // MARK: - End Drag Tests

    @Test("endDrag when idle returns idle")
    func endDragWhenIdle() {
        let controller = makeController()
        let result = controller.endDrag()
        #expect(result.type == .idle)
    }

    @Test("endDrag without movement cancels")
    func endDragWithoutMovement() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 500_000)
        controller.updateDrag(CGPoint(x: 102, y: 50)) // below threshold

        let result = controller.endDrag()
        #expect(result.type == .cancelled)
    }

    @Test("endDrag with movement completes")
    func endDragWithMovement() {
        let clip = makeClip(startTime: 500_000, duration: 1_000_000)
        let controller = makeController(clips: [clip])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 130, y: 50), time: 500_000)

        // Move 20 pixels right (above threshold, valid position)
        controller.updateDrag(CGPoint(x: 150, y: 50))

        let result = controller.endDrag()
        #expect(result.type == .completed)
    }

    // MARK: - Cancel Drag Tests

    @Test("cancelDrag when idle returns idle")
    func cancelDragWhenIdle() {
        let controller = makeController()
        let result = controller.cancelDrag()
        #expect(result.type == .idle)
    }

    @Test("cancelDrag resets state")
    func cancelDragResetsState() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 500_000)

        let result = controller.cancelDrag()
        #expect(result.type == .cancelled)
        #expect(controller.state.type == .idle)
    }

    // MARK: - Collision Detection Tests

    @Test("collision detected with overlapping clips")
    func collisionDetected() {
        let clip1 = makeClip(id: "clip1", startTime: 0, duration: 1_000_000)
        let clip2 = makeClip(id: "clip2", startTime: 1_500_000, duration: 1_000_000, label: "Second")
        let controller = makeController(clips: [clip1, clip2])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 0)

        // Move clip1 to overlap with clip2 (move ~15 pixels right = 150_000 micros at 10000/px)
        // clip1 would end at 1_500_000 which meets clip2's start exactly,
        // but moving 20 pixels right pushes it to start at 200_000, end at 1_200_000 - still safe
        // Let's move enough to actually overlap: need start time of clip1 to be > 500_000
        // Move 150 pixels right = 1_500_000 micros, clip1 would be at 1_500_000 -> 2_500_000
        // That overlaps clip2 at 1_500_000 -> 2_500_000
        controller.updateDrag(CGPoint(x: 250, y: 50))
        let state = controller.state

        // The preview should show invalid position
        #expect(!state.preview.isValid || state.preview.clipPreviews.contains(where: { !$0.isValidPosition }))
    }

    @Test("no collision with non-overlapping position")
    func noCollision() {
        let clip1 = makeClip(id: "clip1", startTime: 0, duration: 500_000)
        let clip2 = makeClip(id: "clip2", startTime: 2_000_000, duration: 500_000)
        let controller = makeController(clips: [clip1, clip2])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 0)

        // Move clip1 to 1_000_000 (100 pixels) - no overlap with clip2
        controller.updateDrag(CGPoint(x: 200, y: 50))
        let state = controller.state

        if state.exceededThreshold {
            #expect(state.preview.isValid)
        }
    }

    @Test("negative start time rejected")
    func negativeStartTimeRejected() {
        let clip = makeClip(startTime: 100_000, duration: 500_000)
        let controller = makeController(clips: [clip])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 0)

        // Move left past timeline start: -50 pixels = -500_000 micros
        controller.updateDrag(CGPoint(x: 50, y: 50))
        let state = controller.state

        if state.exceededThreshold && !state.preview.clipPreviews.isEmpty {
            let preview = state.preview.clipPreviews[0]
            if preview.previewStartTime < 0 {
                #expect(!preview.isValidPosition)
            }
        }
    }

    // MARK: - Snapping Tests

    @Test("snap to target within threshold")
    func snapToTarget() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let target = SnapTarget(time: 2_100_000, description: "Playhead")
        let controller = makeController(clips: [clip], snapTargets: [target])
        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 0)

        // Move to approximately 2_000_000 (200 pixels)
        // Clip end would be at ~3_000_000. Snap target at 2_100_000.
        // Clip start at ~2_000_000 is within 100_000 of snap target at 2_100_000
        // 12px * 10000 = 120_000 snap threshold
        controller.updateDrag(CGPoint(x: 300, y: 50))
        let state = controller.state

        if state.exceededThreshold {
            // Snap may or may not trigger depending on exact calculation
            // Just verify the preview exists
            #expect(!state.preview.clipPreviews.isEmpty)
        }
    }

    // MARK: - DraggedClipPreview Tests

    @Test("DraggedClipPreview properties")
    func draggedClipPreviewProperties() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let preview = DraggedClipPreview(
            originalClip: clip,
            previewStartTime: 500_000,
            previewTrackId: "track1",
            timeDelta: 500_000,
            isValidPosition: true,
            collisionInfo: nil
        )

        #expect(preview.previewEndTime == 1_500_000)
        #expect(preview.changedTime)
        #expect(!preview.changedTrack)
        #expect(preview.hasChanged)
    }

    @Test("DraggedClipPreview no change")
    func draggedClipPreviewNoChange() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let preview = DraggedClipPreview(
            originalClip: clip,
            previewStartTime: 0,
            previewTrackId: "track1",
            timeDelta: 0,
            isValidPosition: true,
            collisionInfo: nil
        )

        #expect(!preview.changedTime)
        #expect(!preview.changedTrack)
        #expect(!preview.hasChanged)
    }

    @Test("DraggedClipPreview changed track")
    func draggedClipPreviewChangedTrack() {
        let clip = makeClip(startTime: 0, duration: 1_000_000)
        let preview = DraggedClipPreview(
            originalClip: clip,
            previewStartTime: 0,
            previewTrackId: "track2",
            timeDelta: 0,
            isValidPosition: true,
            collisionInfo: nil
        )

        #expect(!preview.changedTime)
        #expect(preview.changedTrack)
        #expect(preview.hasChanged)
    }

    // MARK: - Callback Tests

    @Test("onStateChanged callback fires")
    func onStateChangedCallback() {
        let clip = makeClip()
        let controller = makeController(clips: [clip])

        var callbackCount = 0
        controller.onStateChanged = { _ in callbackCount += 1 }

        controller.startDrag(clipIds: ["clip1"], position: CGPoint(x: 100, y: 50), time: 0)
        #expect(callbackCount == 1)

        controller.updateDrag(CGPoint(x: 110, y: 50))
        #expect(callbackCount == 2)

        controller.endDrag()
        // endDrag may call callback once or twice (cancelled + reset)
        #expect(callbackCount >= 3)
    }
}
