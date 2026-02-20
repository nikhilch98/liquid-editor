// MagneticSnapServiceTests.swift
// LiquidEditorTests
//
// Tests for MagneticSnapService.

import Testing
import Foundation
@testable import LiquidEditor

@Suite("MagneticSnapService")
@MainActor
struct MagneticSnapServiceTests {

    // MARK: - Helpers

    private func makeService(config: MagneticSnapConfig = .defaults) -> MagneticSnapService {
        MagneticSnapService(config: config)
    }

    private func makeClip(
        id: String,
        startTime: TimeMicros = 0,
        duration: TimeMicros = 1_000_000,
        trackId: String = "track-1",
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

    // MARK: - Initial State

    @Test("Default config has snapping enabled")
    func defaultEnabled() {
        let service = makeService()
        #expect(service.isEnabled == true)
    }

    @Test("Disabled config has snapping off")
    func disabledConfig() {
        let service = makeService(config: .disabled)
        #expect(service.isEnabled == false)
    }

    // MARK: - Toggle

    @Test("toggle switches snapping state")
    func toggleSnap() {
        let service = makeService()
        service.toggle()
        #expect(service.isEnabled == false)
        service.toggle()
        #expect(service.isEnabled == true)
    }

    // MARK: - Collect Snap Points

    @Test("collectSnapPoints collects clip edges")
    func collectClipEdges() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 1_000_000, duration: 2_000_000),
        ]
        let points = service.collectSnapPoints(clips: clips)
        #expect(points.count == 2)
        #expect(points[0].time == 1_000_000)
        #expect(points[0].source == .clipEdge)
        #expect(points[1].time == 3_000_000)
        #expect(points[1].source == .clipEdge)
    }

    @Test("collectSnapPoints excludes specified clip IDs")
    func collectExcludes() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 1_000_000),
            makeClip(id: "v2", startTime: 3_000_000),
        ]
        let points = service.collectSnapPoints(
            clips: clips,
            excludeClipIds: ["v1"]
        )
        // Only v2 edges
        #expect(points.count == 2)
        #expect(points.allSatisfy { $0.time >= 3_000_000 })
    }

    @Test("collectSnapPoints includes playhead")
    func collectPlayhead() {
        let service = makeService()
        let points = service.collectSnapPoints(
            clips: [],
            playheadTime: 5_000_000
        )
        #expect(points.count == 1)
        #expect(points[0].source == .playhead)
        #expect(points[0].time == 5_000_000)
    }

    @Test("collectSnapPoints includes markers")
    func collectMarkers() {
        let service = makeService()
        let markers = [
            TimelineMarker.point(id: "m1", time: 2_000_000, label: "M1"),
        ]
        let points = service.collectSnapPoints(clips: [], markers: markers)
        #expect(points.count == 1)
        #expect(points[0].source == .marker)
        #expect(points[0].time == 2_000_000)
    }

    @Test("collectSnapPoints includes range marker end")
    func collectRangeMarker() {
        let service = makeService()
        let markers = [
            TimelineMarker.range(
                id: "m1",
                startTime: 2_000_000,
                endTime: 4_000_000,
                label: "Range"
            ),
        ]
        let points = service.collectSnapPoints(clips: [], markers: markers)
        #expect(points.count == 2)
        #expect(points[0].time == 2_000_000)
        #expect(points[1].time == 4_000_000)
    }

    @Test("collectSnapPoints respects config flags")
    func collectRespectsConfig() {
        let config = MagneticSnapConfig(
            snapToClipEdges: false,
            snapToPlayhead: false,
            snapToMarkers: false
        )
        let service = makeService(config: config)
        let clips = [makeClip(id: "v1")]
        let markers = [TimelineMarker.point(id: "m1", time: 1_000_000, label: "M")]
        let points = service.collectSnapPoints(
            clips: clips,
            playheadTime: 500_000,
            markers: markers
        )
        #expect(points.isEmpty)
    }

    // MARK: - Detect Snap

    @Test("detectSnap finds nearest snap point within threshold")
    func detectSnapWithinThreshold() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 1_000_000, source: .clipEdge),
        ]
        // microsPerPixel=10000, threshold=10 pixels => 100_000 micros threshold
        let result = service.detectSnap(
            time: 1_050_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        #expect(result.adjustedTime == 1_000_000)
        #expect(result.snapPoint?.source == .clipEdge)
    }

    @Test("detectSnap returns noSnap when outside threshold")
    func detectSnapOutsideThreshold() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 1_000_000, source: .clipEdge),
        ]
        // microsPerPixel=10000, threshold=10 pixels => 100_000 micros threshold
        let result = service.detectSnap(
            time: 1_200_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == false)
        #expect(result.adjustedTime == 1_200_000)
    }

    @Test("detectSnap picks closest when multiple snap points")
    func detectSnapClosest() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 1_000_000, source: .clipEdge),
            SnapPoint(time: 1_080_000, source: .playhead),
        ]
        let result = service.detectSnap(
            time: 1_070_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        #expect(result.adjustedTime == 1_080_000)
        #expect(result.snapPoint?.source == .playhead)
    }

    @Test("detectSnap returns noSnap when disabled")
    func detectSnapDisabled() {
        let service = makeService(config: .disabled)
        let snapPoints = [
            SnapPoint(time: 1_000_000, source: .clipEdge),
        ]
        let result = service.detectSnap(
            time: 1_000_000,
            snapPoints: snapPoints
        )
        #expect(result.didSnap == false)
    }

    @Test("detectSnap returns noSnap when empty snap points")
    func detectSnapEmpty() {
        let service = makeService()
        let result = service.detectSnap(
            time: 1_000_000,
            snapPoints: []
        )
        #expect(result.didSnap == false)
    }

    // MARK: - Detect Clip Snap

    @Test("detectClipSnap snaps start edge")
    func detectClipSnapStart() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 1_000_000, source: .clipEdge),
        ]
        let result = service.detectClipSnap(
            clipStartTime: 1_050_000,
            clipDuration: 2_000_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        #expect(result.adjustedTime == 1_000_000)
    }

    @Test("detectClipSnap snaps end edge and adjusts start")
    func detectClipSnapEnd() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 5_000_000, source: .clipEdge),
        ]
        // Clip end at 3_050_000 + 2_000_000 = 5_050_000, close to 5M
        let result = service.detectClipSnap(
            clipStartTime: 3_050_000,
            clipDuration: 2_000_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        #expect(result.adjustedTime == 3_000_000) // 5M - 2M duration
    }

    @Test("detectClipSnap returns noSnap when neither edge snaps")
    func detectClipSnapNone() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 10_000_000, source: .clipEdge),
        ]
        let result = service.detectClipSnap(
            clipStartTime: 1_000_000,
            clipDuration: 2_000_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == false)
    }

    @Test("detectClipSnap prefers closer snap when both edges match")
    func detectClipSnapBothEdges() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 1_020_000, source: .clipEdge, label: "start-snap"),
            SnapPoint(time: 3_080_000, source: .playhead, label: "end-snap"),
        ]
        // Start: 1_000_000 -> 1_020_000 (20k away)
        // End: 3_000_000 -> 3_080_000 (80k away)
        let result = service.detectClipSnap(
            clipStartTime: 1_000_000,
            clipDuration: 2_000_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        // Start snap is closer
        #expect(result.adjustedTime == 1_020_000)
    }

    // MARK: - Config Updates

    @Test("withZoomLevel updates threshold")
    func withZoomLevel() {
        let config = MagneticSnapConfig.defaults.withZoomLevel(5000)
        // 10 pixels * 5000 = 50_000 micros
        #expect(config.thresholdMicros == 50_000)
    }

    // MARK: - Additional Config Tests

    @Test("updateConfig replaces config entirely")
    func updateConfig() {
        let service = makeService()
        let newConfig = MagneticSnapConfig(isEnabled: false, thresholdPixels: 20.0)
        service.updateConfig(newConfig)
        #expect(service.isEnabled == false)
        #expect(service.config.thresholdPixels == 20.0)
    }

    @Test("config.with creates selective copy")
    func configWith() {
        let config = MagneticSnapConfig.defaults
        let updated = config.with(snapToMarkers: false, snapToGrid: true)
        #expect(updated.snapToGrid == true)
        #expect(updated.snapToMarkers == false)
        #expect(updated.snapToClipEdges == true) // Unchanged
        #expect(updated.snapToPlayhead == true) // Unchanged
        #expect(updated.isEnabled == true) // Unchanged
    }

    @Test("MagneticSnapConfig defaults have expected values")
    func configDefaults() {
        let config = MagneticSnapConfig.defaults
        #expect(config.isEnabled == true)
        #expect(config.thresholdPixels == 10.0)
        #expect(config.thresholdMicros == 100_000)
        #expect(config.snapToClipEdges == true)
        #expect(config.snapToPlayhead == true)
        #expect(config.snapToMarkers == true)
        #expect(config.snapToGrid == false)
    }

    @Test("MagneticSnapConfig.disabled has snapping off")
    func configDisabled() {
        let config = MagneticSnapConfig.disabled
        #expect(config.isEnabled == false)
    }

    // MARK: - Additional Collect Snap Points

    @Test("collectSnapPoints includes clip labels in snap point labels")
    func collectClipLabels() {
        let service = makeService()
        let clip = makeClip(id: "v1", startTime: 1_000_000, duration: 2_000_000, label: "Intro")
        let points = service.collectSnapPoints(clips: [clip])
        let startPoint = points.first { $0.time == 1_000_000 }
        #expect(startPoint?.label?.contains("Intro") == true)
    }

    @Test("collectSnapPoints uses clip type as label fallback")
    func collectClipTypeFallback() {
        let service = makeService()
        let clip = makeClip(id: "v1", startTime: 0, duration: 1_000_000)
        let points = service.collectSnapPoints(clips: [clip])
        let startPoint = points.first { $0.time == 0 }
        #expect(startPoint?.label?.contains("video") == true)
    }

    @Test("collectSnapPoints with all sources disabled returns empty")
    func collectAllDisabled() {
        let config = MagneticSnapConfig(
            snapToClipEdges: false, snapToPlayhead: false,
            snapToMarkers: false, snapToGrid: false
        )
        let service = makeService(config: config)
        let clips = [makeClip(id: "v1")]
        let markers = [TimelineMarker.point(id: "m1", time: 100, label: "M")]
        let points = service.collectSnapPoints(clips: clips, playheadTime: 500, markers: markers)
        #expect(points.isEmpty)
    }

    @Test("collectSnapPoints with multiple clips collects all edges")
    func collectMultipleClips() {
        let service = makeService()
        let clips = [
            makeClip(id: "v1", startTime: 0, duration: 1_000_000),
            makeClip(id: "v2", startTime: 2_000_000, duration: 500_000),
            makeClip(id: "v3", startTime: 4_000_000, duration: 1_500_000),
        ]
        let points = service.collectSnapPoints(clips: clips)
        #expect(points.count == 6) // 3 clips * 2 edges each
    }

    // MARK: - Additional Detect Snap

    @Test("detectSnap pixel distance is correct")
    func detectSnapPixelDistance() {
        let service = makeService()
        let snapPoints = [SnapPoint(time: 1_000_000, source: .clipEdge)]
        let result = service.detectSnap(
            time: 1_050_000, snapPoints: snapPoints, microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        // pixelDist = 50_000 / 10000 = 5.0
        #expect(abs(result.pixelDistance - 5.0) < 0.001)
    }

    @Test("detectSnap exactly at snap point returns zero distance")
    func detectSnapExactMatch() {
        let service = makeService()
        let snapPoints = [SnapPoint(time: 1_000_000, source: .clipEdge)]
        let result = service.detectSnap(
            time: 1_000_000, snapPoints: snapPoints, microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        #expect(result.pixelDistance == 0.0)
        #expect(result.adjustedTime == 1_000_000)
    }

    @Test("detectSnap at exact threshold boundary snaps")
    func detectSnapAtThreshold() {
        let service = makeService()
        let snapPoints = [SnapPoint(time: 1_000_000, source: .clipEdge)]
        // threshold = 10 * 10000 = 100_000
        let result = service.detectSnap(
            time: 1_100_000, snapPoints: snapPoints, microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
    }

    @Test("detectSnap just beyond threshold does not snap")
    func detectSnapBeyondThreshold() {
        let service = makeService()
        let snapPoints = [SnapPoint(time: 1_000_000, source: .clipEdge)]
        // threshold = 10 * 10000 = 100_000
        let result = service.detectSnap(
            time: 1_100_001, snapPoints: snapPoints, microsPerPixel: 10000
        )
        #expect(result.didSnap == false)
    }

    // MARK: - SnapPoint Hashable and Equatable

    @Test("SnapPoint equality based on time and source")
    func snapPointEquality() {
        let a = SnapPoint(time: 1_000_000, source: .clipEdge, label: "A")
        let b = SnapPoint(time: 1_000_000, source: .clipEdge, label: "B")
        let c = SnapPoint(time: 1_000_000, source: .playhead, label: "A")
        #expect(a == b) // Same time and source, different labels
        #expect(a != c) // Different source
    }

    @Test("SnapPoint hashing works in Set")
    func snapPointHashing() {
        let a = SnapPoint(time: 1_000_000, source: .clipEdge, label: "A")
        let b = SnapPoint(time: 1_000_000, source: .clipEdge, label: "B")
        let c = SnapPoint(time: 2_000_000, source: .clipEdge)
        let set: Set<SnapPoint> = [a, b, c]
        #expect(set.count == 2) // a and b are equal
    }

    @Test("SnapDetectionResult.noSnap factory")
    func noSnapFactory() {
        let result = SnapDetectionResult.noSnap(5_000_000)
        #expect(result.didSnap == false)
        #expect(result.adjustedTime == 5_000_000)
        #expect(result.snapPoint == nil)
        #expect(result.pixelDistance == 0)
    }

    @Test("SnapSource allCases contains four types")
    func snapSourceAllCases() {
        #expect(SnapSource.allCases.count == 4)
    }

    // MARK: - Clip Snap Both Edges Closer End

    @Test("detectClipSnap prefers closer end snap when end is closer")
    func detectClipSnapEndCloser() {
        let service = makeService()
        let snapPoints = [
            SnapPoint(time: 1_080_000, source: .clipEdge, label: "start-snap"),
            SnapPoint(time: 3_020_000, source: .playhead, label: "end-snap"),
        ]
        // Start: 1_000_000 -> 1_080_000 (80k away)
        // End: 3_000_000 -> 3_020_000 (20k away)
        let result = service.detectClipSnap(
            clipStartTime: 1_000_000,
            clipDuration: 2_000_000,
            snapPoints: snapPoints,
            microsPerPixel: 10000
        )
        #expect(result.didSnap == true)
        // End snap is closer, adjusted start = 3_020_000 - 2_000_000 = 1_020_000
        #expect(result.adjustedTime == 1_020_000)
    }

    @Test("detectClipSnap disabled returns noSnap")
    func detectClipSnapDisabled() {
        let service = makeService(config: .disabled)
        let snapPoints = [SnapPoint(time: 1_000_000, source: .clipEdge)]
        let result = service.detectClipSnap(
            clipStartTime: 1_000_000, clipDuration: 500_000,
            snapPoints: snapPoints
        )
        #expect(result.didSnap == false)
    }

    @Test("detectClipSnap with empty snap points returns noSnap")
    func detectClipSnapEmptyPoints() {
        let service = makeService()
        let result = service.detectClipSnap(
            clipStartTime: 1_000_000, clipDuration: 500_000,
            snapPoints: []
        )
        #expect(result.didSnap == false)
        #expect(result.adjustedTime == 1_000_000)
    }
}
