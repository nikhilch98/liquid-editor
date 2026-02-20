import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - PanScanRegion Tests

@Suite("PanScanRegion Tests")
struct PanScanRegionTests {

    @Test("fullFrame is full frame")
    func fullFrame() {
        let region = PanScanRegion.fullFrame
        #expect(region.isFullFrame == true)
        #expect(region.rotation == 0.0)
    }

    @Test("isFullFrame detects non-full regions")
    func isFullFrameFalse() {
        let cropped = PanScanRegion(
            cropRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )
        #expect(cropped.isFullFrame == false)
    }

    @Test("zoomLevel for full frame is 1.0")
    func zoomLevelFullFrame() {
        let region = PanScanRegion.fullFrame
        #expect(abs(region.zoomLevel - 1.0) < 0.01)
    }

    @Test("zoomLevel for half-size crop is 2.0")
    func zoomLevelHalf() {
        let region = PanScanRegion(
            cropRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        )
        #expect(abs(region.zoomLevel - 2.0) < 0.01)
    }

    @Test("center calculation")
    func center() {
        let region = PanScanRegion(
            cropRect: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.6)
        )
        #expect(abs(region.center.x - 0.4) < 0.001)
        #expect(abs(region.center.y - 0.6) < 0.001)
    }

    @Test("lerp interpolation at 0.0 returns a")
    func lerpZero() {
        let a = PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let b = PanScanRegion(cropRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let result = PanScanRegion.lerp(a, b, t: 0.0)
        #expect(abs(result.cropRect.origin.x) < 0.001)
        #expect(abs(result.cropRect.width - 1.0) < 0.001)
    }

    @Test("lerp interpolation at 1.0 returns b")
    func lerpOne() {
        let a = PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let b = PanScanRegion(cropRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), rotation: 1.0)
        let result = PanScanRegion.lerp(a, b, t: 1.0)
        #expect(abs(result.cropRect.origin.x - 0.2) < 0.001)
        #expect(abs(result.cropRect.width - 0.6) < 0.001)
        #expect(abs(result.rotation - 1.0) < 0.001)
    }

    @Test("lerp at midpoint")
    func lerpMidpoint() {
        let a = PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 0.0)
        let b = PanScanRegion(cropRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), rotation: 2.0)
        let result = PanScanRegion.lerp(a, b, t: 0.5)
        #expect(abs(result.cropRect.origin.x - 0.1) < 0.001)
        #expect(abs(result.cropRect.width - 0.8) < 0.001)
        #expect(abs(result.rotation - 1.0) < 0.001)
    }

    @Test("with() copy method")
    func withCopy() {
        let region = PanScanRegion(cropRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), rotation: 0.5)
        let modified = region.with(rotation: 1.0)
        #expect(modified.cropRect == region.cropRect)
        #expect(modified.rotation == 1.0)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PanScanRegion(
            cropRect: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5),
            rotation: 0.3
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PanScanRegion.self, from: data)
        #expect(abs(decoded.cropRect.origin.x - 0.1) < 0.001)
        #expect(abs(decoded.cropRect.origin.y - 0.2) < 0.001)
        #expect(abs(decoded.cropRect.width - 0.6) < 0.001)
        #expect(abs(decoded.cropRect.height - 0.5) < 0.001)
        #expect(abs(decoded.rotation - 0.3) < 0.001)
    }
}

// MARK: - PanScanConfig Tests

@Suite("PanScanConfig Tests")
struct PanScanConfigTests {

    @Test("disabled config")
    func disabled() {
        let config = PanScanConfig.disabled
        #expect(config.isEnabled == false)
        #expect(config.keyframes.isEmpty)
        #expect(config.hasKeyframes == false)
    }

    @Test("creation with defaults")
    func creationDefaults() {
        let config = PanScanConfig()
        #expect(config.isEnabled == false)
        #expect(config.keyframes.isEmpty)
    }

    @Test("hasKeyframes requires at least 2")
    func hasKeyframes() {
        let oneKf = PanScanConfig(isEnabled: true, keyframes: [
            PanScanKeyframe(id: "kf1", timeMicros: 0, region: .fullFrame)
        ])
        #expect(oneKf.hasKeyframes == false)

        let twoKf = PanScanConfig(isEnabled: true, keyframes: [
            PanScanKeyframe(id: "kf1", timeMicros: 0, region: .fullFrame),
            PanScanKeyframe(id: "kf2", timeMicros: 1_000_000, region: .fullFrame)
        ])
        #expect(twoKf.hasKeyframes == true)
    }

    @Test("simple factory creates two-keyframe config")
    func simpleFactory() {
        let startRegion = PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let endRegion = PanScanRegion(cropRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let config = PanScanConfig.simple(
            startId: "s", endId: "e",
            startRegion: startRegion,
            endRegion: endRegion,
            clipDurationMicros: 5_000_000
        )
        #expect(config.isEnabled == true)
        #expect(config.keyframes.count == 2)
        #expect(config.keyframes[0].timeMicros == 0)
        #expect(config.keyframes[1].timeMicros == 5_000_000)
    }

    @Test("regionAtTime before first keyframe returns first region")
    func regionAtTimeBeforeFirst() {
        let config = PanScanConfig.simple(
            startId: "s", endId: "e",
            startRegion: PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            endRegion: PanScanRegion(cropRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            clipDurationMicros: 2_000_000
        )
        let region = config.regionAtTime(-100)
        #expect(abs(region.cropRect.width - 1.0) < 0.001)
    }

    @Test("regionAtTime after last keyframe returns last region")
    func regionAtTimeAfterLast() {
        let config = PanScanConfig.simple(
            startId: "s", endId: "e",
            startRegion: PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            endRegion: PanScanRegion(cropRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            clipDurationMicros: 2_000_000
        )
        let region = config.regionAtTime(3_000_000)
        #expect(abs(region.cropRect.width - 0.6) < 0.001)
    }

    @Test("regionAtTime interpolates at midpoint")
    func regionAtTimeMidpoint() {
        let config = PanScanConfig.simple(
            startId: "s", endId: "e",
            startRegion: PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            endRegion: PanScanRegion(cropRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            clipDurationMicros: 2_000_000
        )
        let region = config.regionAtTime(1_000_000)
        #expect(abs(region.cropRect.origin.x - 0.1) < 0.01)
        #expect(abs(region.cropRect.width - 0.8) < 0.01)
    }

    @Test("regionAtTime for empty keyframes returns fullFrame")
    func regionAtTimeEmpty() {
        let config = PanScanConfig()
        let region = config.regionAtTime(500_000)
        #expect(region.isFullFrame == true)
    }

    @Test("with() copy method")
    func withCopy() {
        let config = PanScanConfig(isEnabled: false)
        let modified = config.with(isEnabled: true)
        #expect(modified.isEnabled == true)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let config = PanScanConfig.simple(
            startId: "s", endId: "e",
            startRegion: PanScanRegion(cropRect: CGRect(x: 0, y: 0, width: 1, height: 1)),
            endRegion: PanScanRegion(cropRect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)),
            clipDurationMicros: 3_000_000
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PanScanConfig.self, from: data)
        #expect(decoded.isEnabled == true)
        #expect(decoded.keyframes.count == 2)
    }
}
