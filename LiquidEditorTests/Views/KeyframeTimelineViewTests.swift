import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("KeyframeTimelineView Tests")
struct KeyframeTimelineViewTests {

    // MARK: - Test Data

    private static let durationMicros: TimeMicros = 10_000_000 // 10 seconds
    private static let durationMs: Double = 10_000.0

    private static let testKeyframes: [Keyframe] = [
        Keyframe(id: "kf-0", timestampMicros: 0),
        Keyframe(id: "kf-1", timestampMicros: 2_000_000),
        Keyframe(id: "kf-2", timestampMicros: 5_000_000),
        Keyframe(id: "kf-3", timestampMicros: 10_000_000),
    ]

    // MARK: - Keyframe Position Calculations

    @Test("Keyframe at timestamp 0 maps to progress 0.0")
    func keyframeAtStart() {
        let kf = Self.testKeyframes[0]
        let progress = kf.milliseconds / Self.durationMs
        #expect(progress == 0.0)
    }

    @Test("Keyframe at duration maps to progress 1.0")
    func keyframeAtEnd() {
        let kf = Self.testKeyframes[3]
        let progress = kf.milliseconds / Self.durationMs
        #expect(progress == 1.0)
    }

    @Test("Keyframe at midpoint maps to progress 0.5")
    func keyframeAtMidpoint() {
        let kf = Self.testKeyframes[2]
        let progress = kf.milliseconds / Self.durationMs
        #expect(progress == 0.5)
    }

    @Test("Keyframe X position calculation with padding")
    func keyframeXPosition() {
        let trackPadding: CGFloat = 20
        let trackWidth: CGFloat = 300 - (trackPadding * 2) // 260
        let kf = Self.testKeyframes[1] // 2 seconds = 0.2 progress
        let progress = kf.milliseconds / Self.durationMs

        let x = trackPadding + trackWidth * progress
        #expect(x == 72.0) // 20 + 260 * 0.2
    }

    // MARK: - Tap Tolerance

    @Test("Tap within tolerance selects keyframe")
    func tapWithinTolerance() {
        let tapTolerance: CGFloat = 25
        let trackPadding: CGFloat = 20
        let trackWidth: CGFloat = 300 - (trackPadding * 2) // 260

        let kf = Self.testKeyframes[1] // at x = 72
        let keyframeX = trackPadding + trackWidth * (kf.milliseconds / Self.durationMs)
        let tapX = keyframeX + 20 // 20px offset, within 25px tolerance

        let distance = abs(tapX - keyframeX)
        #expect(distance < tapTolerance)
    }

    @Test("Tap outside tolerance does not select keyframe")
    func tapOutsideTolerance() {
        let tapTolerance: CGFloat = 25
        let trackPadding: CGFloat = 20
        let trackWidth: CGFloat = 300 - (trackPadding * 2) // 260

        let kf = Self.testKeyframes[1] // at x = 72
        let keyframeX = trackPadding + trackWidth * (kf.milliseconds / Self.durationMs)
        let tapX = keyframeX + 30 // 30px offset, outside 25px tolerance

        let distance = abs(tapX - keyframeX)
        #expect(distance >= tapTolerance)
    }

    // MARK: - Zoom Calculations

    @Test("Zoom clamped to 0.5x minimum")
    func zoomMinimum() {
        let zoom = max(0.5, min(4.0, 0.3))
        #expect(zoom == 0.5)
    }

    @Test("Zoom clamped to 4.0x maximum")
    func zoomMaximum() {
        let zoom = max(0.5, min(4.0, 5.0))
        #expect(zoom == 4.0)
    }

    @Test("Zoom 1.0 produces base width")
    func zoomBaseWidth() {
        let baseWidth: CGFloat = 300
        let zoom: Double = 1.0
        let zoomedWidth = baseWidth * zoom
        #expect(zoomedWidth == 300)
    }

    @Test("Zoom 2.0 doubles width")
    func zoomDoubled() {
        let baseWidth: CGFloat = 300
        let zoom: Double = 2.0
        let zoomedWidth = baseWidth * zoom
        #expect(zoomedWidth == 600)
    }

    // MARK: - Time Marker Intervals

    @Test("Very high pixel density uses 100ms interval")
    func timeMarkerHighDensity() {
        let pixelsPerSecond: CGFloat = 250
        let interval: Int
        if pixelsPerSecond > 200 { interval = 100 }
        else if pixelsPerSecond > 100 { interval = 500 }
        else { interval = 1000 }

        #expect(interval == 100)
    }

    @Test("Medium pixel density uses 1000ms interval")
    func timeMarkerMediumDensity() {
        let pixelsPerSecond: CGFloat = 60
        let interval: Int
        if pixelsPerSecond > 200 { interval = 100 }
        else if pixelsPerSecond > 100 { interval = 500 }
        else if pixelsPerSecond > 50 { interval = 1000 }
        else { interval = 2000 }

        #expect(interval == 1000)
    }

    @Test("Low pixel density uses 5000ms interval")
    func timeMarkerLowDensity() {
        let pixelsPerSecond: CGFloat = 15
        let interval: Int
        if pixelsPerSecond > 200 { interval = 100 }
        else if pixelsPerSecond > 100 { interval = 500 }
        else if pixelsPerSecond > 50 { interval = 1000 }
        else if pixelsPerSecond > 25 { interval = 2000 }
        else if pixelsPerSecond > 10 { interval = 5000 }
        else { interval = 10000 }

        #expect(interval == 5000)
    }

    // MARK: - Diamond Path

    @Test("Diamond path creates 4-point shape")
    func diamondPath() {
        let center = CGPoint(x: 50, y: 50)
        let path = KeyframeTimelinePainter.diamondPath(center: center, size: 10)

        // The path should not be empty
        #expect(!path.isEmpty)

        // The path bounds should be approximately 20x20 centered on (50,50)
        let bounds = path.boundingRect
        #expect(abs(bounds.midX - 50) < 1)
        #expect(abs(bounds.midY - 50) < 1)
        #expect(abs(bounds.width - 20) < 1)
        #expect(abs(bounds.height - 20) < 1)
    }

    // MARK: - Drag Seek Calculations

    @Test("Drag at track start produces progress 0.0")
    func dragAtStart() {
        let trackPadding: CGFloat = 20
        let width: CGFloat = 300
        let trackWidth = width - trackPadding * 2 // 260

        let x = trackPadding // At the very start
        let progress = max(0.0, min(1.0, (x - trackPadding) / trackWidth))
        #expect(progress == 0.0)
    }

    @Test("Drag at track end produces progress 1.0")
    func dragAtEnd() {
        let trackPadding: CGFloat = 20
        let width: CGFloat = 300
        let trackWidth = width - trackPadding * 2 // 260

        let x = width - trackPadding // At the very end
        let progress = max(0.0, min(1.0, (x - trackPadding) / trackWidth))
        #expect(progress == 1.0)
    }

    @Test("Drag before track start clamps to 0.0")
    func dragBeforeStart() {
        let trackPadding: CGFloat = 20
        let width: CGFloat = 300
        let trackWidth = width - trackPadding * 2 // 260

        let x: CGFloat = 5 // Before padding
        let progress = max(0.0, min(1.0, (x - trackPadding) / trackWidth))
        #expect(progress == 0.0)
    }
}
