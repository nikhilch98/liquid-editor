import Testing
import Foundation
@testable import LiquidEditor

// MARK: - SnapCandidate Tests

@Suite("SnapCandidate Tests")
struct SnapCandidateTests {

    @Test("Creation and equality")
    func creation() {
        let a = SnapCandidate(time: 500_000, type: .playhead, priority: 0, pixelDistance: 5.0)
        let b = SnapCandidate(time: 500_000, type: .playhead, priority: 0, pixelDistance: 5.0)
        #expect(a == b)
        #expect(a.time == 500_000)
        #expect(a.type == .playhead)
    }
}

// MARK: - SnapTargets Tests

@Suite("SnapTargets Tests")
struct SnapTargetsTests {

    @Test("Empty targets")
    func emptyTargets() {
        let targets = SnapTargets.empty
        #expect(targets.playheadTime == nil)
        #expect(targets.clipEdges.isEmpty)
        #expect(targets.markerTimes.isEmpty)
        #expect(targets.inPoint == nil)
        #expect(targets.outPoint == nil)
        #expect(targets.beatTimes.isEmpty)
        #expect(targets.gridTimes.isEmpty)
    }

    @Test("Full targets")
    func fullTargets() {
        let targets = SnapTargets(
            playheadTime: 500_000,
            clipEdges: [0, 1_000_000],
            markerTimes: [250_000],
            inPoint: 100_000,
            outPoint: 900_000,
            beatTimes: [333_000],
            gridTimes: [200_000, 400_000]
        )
        #expect(targets.playheadTime == 500_000)
        #expect(targets.clipEdges.count == 2)
        #expect(targets.markerTimes.count == 1)
    }
}

// MARK: - SnapController Tests

@Suite("SnapController Tests")
@MainActor
struct SnapControllerTests {

    /// Create a configured snap controller.
    private func makeController(pixelsPerMicros: Double = 0.001) -> SnapController {
        let controller = SnapController()
        controller.updateScale(pixelsPerMicros)
        return controller
    }

    // MARK: - Disabled Snap

    @Test("Snap disabled returns raw delta")
    func snapDisabled() {
        let controller = makeController()
        controller.isEnabled = false

        let result = controller.findSnapPoints(
            currentDelta: 100_000,
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(playheadTime: 100_000)
        )

        #expect(result.adjustedDelta == 100_000)
        #expect(result.guides.isEmpty)
        #expect(!result.snappedToPlayhead)
    }

    @Test("Zero scale returns raw delta")
    func zeroScale() {
        let controller = SnapController()
        // Don't set scale (stays at 0)

        let result = controller.findSnapPoints(
            currentDelta: 100_000,
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(playheadTime: 100_000)
        )

        #expect(result.adjustedDelta == 100_000)
    }

    // MARK: - Playhead Snap

    @Test("Snap to playhead via start edge")
    func snapToPlayheadStart() {
        // pixelsPerMicros = 0.001 means 1000 micros = 1 pixel
        // Threshold = 10 pixels = 10_000 micros
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findSnapPoints(
            currentDelta: 495_000, // projected start = 495_000
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(playheadTime: 500_000) // 5_000 micros = 5 pixels away
        )

        // Should snap: start edge at 495k, playhead at 500k -> 5px distance < 10px threshold
        #expect(result.adjustedDelta == 500_000) // Snapped to playhead
        #expect(result.snappedToPlayhead)
        #expect(result.guides.count == 1)
    }

    @Test("No snap when outside threshold")
    func noSnapOutsideThreshold() {
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findSnapPoints(
            currentDelta: 480_000, // projected start = 480_000
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(playheadTime: 500_000) // 20_000 micros = 20 pixels away
        )

        // Should NOT snap: 20 pixels > 10 pixel threshold
        #expect(result.adjustedDelta == 480_000)
        #expect(result.guides.isEmpty)
    }

    // MARK: - Clip Edge Snap

    @Test("Snap to clip edge")
    func snapToClipEdge() {
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findSnapPoints(
            currentDelta: 997_000, // projected start = 997_000
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(clipEdges: [1_000_000]) // 3_000 micros = 3 pixels away
        )

        #expect(result.adjustedDelta == 1_000_000) // Snapped to clip edge
        #expect(!result.snappedToPlayhead)
    }

    // MARK: - Priority

    @Test("Playhead has higher priority than clip edge")
    func playheadPriorityOverClipEdge() {
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findSnapPoints(
            currentDelta: 497_000, // projected start = 497_000
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(
                playheadTime: 500_000,
                clipEdges: [500_000] // Same position, but lower priority
            )
        )

        // Should prefer playhead
        #expect(result.snappedToPlayhead)
    }

    // MARK: - Trim Snap

    @Test("Find trim snap to playhead")
    func trimSnapToPlayhead() {
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findTrimSnapPoints(
            trimmedEdgeTime: 498_000,
            targets: SnapTargets(playheadTime: 500_000)
        )

        #expect(result != nil)
        #expect(result!.snapTime == 500_000)
        #expect(result!.guide.type == .playhead)
    }

    @Test("Find trim snap to marker")
    func trimSnapToMarker() {
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findTrimSnapPoints(
            trimmedEdgeTime: 248_000,
            targets: SnapTargets(markerTimes: [250_000])
        )

        #expect(result != nil)
        #expect(result!.snapTime == 250_000)
        #expect(result!.guide.type == .marker)
    }

    @Test("Trim snap returns nil when disabled")
    func trimSnapDisabled() {
        let controller = makeController()
        controller.isEnabled = false

        let result = controller.findTrimSnapPoints(
            trimmedEdgeTime: 498_000,
            targets: SnapTargets(playheadTime: 500_000)
        )

        #expect(result == nil)
    }

    @Test("Trim snap returns nil when no candidates in threshold")
    func trimSnapNoCandidates() {
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findTrimSnapPoints(
            trimmedEdgeTime: 100_000,
            targets: SnapTargets(playheadTime: 500_000) // Far away
        )

        #expect(result == nil)
    }

    @Test("Trim snap to in/out points")
    func trimSnapToInOutPoints() {
        let controller = makeController(pixelsPerMicros: 0.001)

        let result = controller.findTrimSnapPoints(
            trimmedEdgeTime: 99_000,
            targets: SnapTargets(inPoint: 100_000, outPoint: 900_000)
        )

        #expect(result != nil)
        #expect(result!.snapTime == 100_000)
        #expect(result!.guide.type == .inOutPoint)
    }

    // MARK: - Scale Update

    @Test("Update scale")
    func updateScale() {
        let controller = SnapController()
        controller.updateScale(0.005)

        // After updating scale, snapping should work
        let result = controller.findSnapPoints(
            currentDelta: 498_000,
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(playheadTime: 500_000)
        )

        // At 0.005 px/micros, 2_000 micros = 10 pixels, just at threshold
        #expect(result.adjustedDelta == 500_000)
    }

    // MARK: - Threshold

    @Test("Custom snap threshold")
    func customThreshold() {
        let controller = makeController(pixelsPerMicros: 0.001)
        controller.snapThresholdPixels = 5.0 // Tighter threshold

        let result = controller.findSnapPoints(
            currentDelta: 492_000, // 8_000 micros = 8 pixels away
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: SnapTargets(playheadTime: 500_000)
        )

        // 8 pixels > 5 pixel threshold, should NOT snap
        #expect(result.adjustedDelta == 492_000)
        #expect(result.guides.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("No targets returns raw delta")
    func noTargets() {
        let controller = makeController()

        let result = controller.findSnapPoints(
            currentDelta: 100_000,
            clipStartTime: 0,
            clipEndTime: 500_000,
            targets: .empty
        )

        #expect(result.adjustedDelta == 100_000)
        #expect(result.guides.isEmpty)
    }
}
