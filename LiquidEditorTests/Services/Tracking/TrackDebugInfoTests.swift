import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - GapReason Tests

@Suite("GapReason Tests")
struct GapReasonTests {

    @Test("all cases exist")
    func allCases() {
        let reasons: [GapReason] = [.occlusion, .outOfFrame, .lowConfidence, .unknown]
        #expect(reasons.count == 4)
    }

    @Test("raw values")
    func rawValues() {
        #expect(GapReason.occlusion.rawValue == "occlusion")
        #expect(GapReason.outOfFrame.rawValue == "outOfFrame")
        #expect(GapReason.lowConfidence.rawValue == "lowConfidence")
        #expect(GapReason.unknown.rawValue == "unknown")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for reason in [GapReason.occlusion, .outOfFrame, .lowConfidence, .unknown] {
            let data = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(GapReason.self, from: data)
            #expect(decoded == reason)
        }
    }
}

// MARK: - MotionClass Tests

@Suite("MotionClass Tests")
struct MotionClassTests {

    @Test("all cases exist")
    func allCases() {
        let classes: [MotionClass] = [.low, .medium, .high]
        #expect(classes.count == 3)
    }

    @Test("raw values")
    func rawValues() {
        #expect(MotionClass.low.rawValue == "low")
        #expect(MotionClass.medium.rawValue == "medium")
        #expect(MotionClass.high.rawValue == "high")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for cls in [MotionClass.low, .medium, .high] {
            let data = try JSONEncoder().encode(cls)
            let decoded = try JSONDecoder().decode(MotionClass.self, from: data)
            #expect(decoded == cls)
        }
    }
}

// MARK: - TrackGap Tests

@Suite("TrackGap Tests")
struct TrackGapTests {

    @Test("creation and durationMs")
    func creationAndDuration() {
        let gap = TrackGap(
            startFrame: 10,
            endFrame: 40,
            startMs: 333,
            endMs: 1333,
            likelyReason: .occlusion
        )
        #expect(gap.startFrame == 10)
        #expect(gap.endFrame == 40)
        #expect(gap.startMs == 333)
        #expect(gap.endMs == 1333)
        #expect(gap.durationMs == 1000)
        #expect(gap.likelyReason == .occlusion)
    }

    @Test("zero duration gap")
    func zeroDuration() {
        let gap = TrackGap(
            startFrame: 10,
            endFrame: 10,
            startMs: 333,
            endMs: 333,
            likelyReason: .unknown
        )
        #expect(gap.durationMs == 0)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let gap = TrackGap(
            startFrame: 5,
            endFrame: 15,
            startMs: 166,
            endMs: 500,
            likelyReason: .outOfFrame
        )
        let data = try JSONEncoder().encode(gap)
        let decoded = try JSONDecoder().decode(TrackGap.self, from: data)
        #expect(decoded.startFrame == 5)
        #expect(decoded.endFrame == 15)
        #expect(decoded.durationMs == 334)
        #expect(decoded.likelyReason == .outOfFrame)
    }
}

// MARK: - TrackReIDEvent Tests

@Suite("TrackReIDEvent Tests")
struct TrackReIDEventTests {

    @Test("creation")
    func creation() {
        let event = TrackReIDEvent(
            frameNumber: 100,
            timestampMs: 3300,
            similarity: 0.82,
            restoredTrackId: 1,
            wouldHaveBeenTrackId: 5
        )
        #expect(event.frameNumber == 100)
        #expect(event.timestampMs == 3300)
        #expect(event.similarity == 0.82)
        #expect(event.restoredTrackId == 1)
        #expect(event.wouldHaveBeenTrackId == 5)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let event = TrackReIDEvent(
            frameNumber: 50,
            timestampMs: 1650,
            similarity: 0.75,
            restoredTrackId: 3,
            wouldHaveBeenTrackId: nil
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(TrackReIDEvent.self, from: data)
        #expect(decoded.frameNumber == 50)
        #expect(decoded.similarity == 0.75)
        #expect(decoded.wouldHaveBeenTrackId == nil)
    }
}

// MARK: - TrackDebugInfo Tests

@Suite("TrackDebugInfo Tests")
struct TrackDebugInfoTests {

    private func makeDebugInfo(
        trackId: Int = 1,
        gaps: [TrackGap] = [],
        reidRestorations: [TrackReIDEvent] = [],
        identifiedPersonId: String? = nil,
        identifiedPersonName: String? = nil
    ) -> TrackDebugInfo {
        TrackDebugInfo(
            trackId: trackId,
            firstFrame: 0,
            lastFrame: 100,
            firstFrameMs: 0,
            lastFrameMs: 3333,
            totalFrames: 90,
            avgConfidence: 0.85,
            minConfidence: 0.6,
            maxConfidence: 0.99,
            confidenceHistogram: [0, 0, 0, 0, 0, 0, 5, 20, 40, 25],
            gaps: gaps,
            totalGapDurationMs: gaps.reduce(0) { $0 + $1.durationMs },
            reidRestorations: reidRestorations,
            mergedFromTrackIds: [],
            identifiedPersonId: identifiedPersonId,
            identifiedPersonName: identifiedPersonName,
            identificationConfidence: identifiedPersonId != nil ? 0.88 : nil,
            avgBboxSize: CGSize(width: 0.2, height: 0.5),
            avgBboxCenter: CGPoint(x: 0.5, y: 0.5),
            bboxSizeVariance: 0.02,
            avgVelocity: 5.0,
            maxVelocity: 15.0,
            motionClassification: .medium,
            state: "confirmed"
        )
    }

    @Test("computed properties without gaps")
    func computedNoGaps() {
        let info = makeDebugInfo()
        #expect(info.gapCount == 0)
        #expect(info.longestGapMs == 0)
        #expect(info.reidRestorationCount == 0)
        #expect(info.isIdentified == false)
    }

    @Test("computed properties with gaps")
    func computedWithGaps() {
        let gaps = [
            TrackGap(startFrame: 10, endFrame: 20, startMs: 333, endMs: 666, likelyReason: .occlusion),
            TrackGap(startFrame: 50, endFrame: 80, startMs: 1666, endMs: 2666, likelyReason: .outOfFrame),
        ]
        let info = makeDebugInfo(gaps: gaps)
        #expect(info.gapCount == 2)
        #expect(info.longestGapMs == 1000) // 2666 - 1666
    }

    @Test("computed properties with ReID restorations")
    func computedWithReID() {
        let events = [
            TrackReIDEvent(frameNumber: 25, timestampMs: 833, similarity: 0.78, restoredTrackId: 1, wouldHaveBeenTrackId: 3),
        ]
        let info = makeDebugInfo(reidRestorations: events)
        #expect(info.reidRestorationCount == 1)
    }

    @Test("isIdentified when person ID is set")
    func isIdentified() {
        let info = makeDebugInfo(identifiedPersonId: "person-1", identifiedPersonName: "Alice")
        #expect(info.isIdentified == true)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let info = makeDebugInfo(
            gaps: [TrackGap(startFrame: 10, endFrame: 20, startMs: 333, endMs: 666, likelyReason: .lowConfidence)],
            identifiedPersonId: "p1",
            identifiedPersonName: "Bob"
        )
        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(TrackDebugInfo.self, from: data)
        #expect(decoded.trackId == 1)
        #expect(decoded.totalFrames == 90)
        #expect(decoded.avgConfidence == 0.85)
        #expect(decoded.gaps.count == 1)
        #expect(decoded.identifiedPersonId == "p1")
        #expect(decoded.motionClassification == .medium)
    }
}

// MARK: - TrackMergeDebugDetail Tests

@Suite("TrackMergeDebugDetail Tests")
struct TrackMergeDebugDetailTests {

    @Test("creation")
    func creation() {
        let detail = TrackMergeDebugDetail(
            fromTrackId: 3,
            toTrackId: 1,
            similarity: 0.82,
            gapMs: 500
        )
        #expect(detail.fromTrackId == 3)
        #expect(detail.toTrackId == 1)
        #expect(detail.similarity == 0.82)
        #expect(detail.gapMs == 500)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let detail = TrackMergeDebugDetail(
            fromTrackId: 5,
            toTrackId: 2,
            similarity: 0.75,
            gapMs: 1000
        )
        let data = try JSONEncoder().encode(detail)
        let decoded = try JSONDecoder().decode(TrackMergeDebugDetail.self, from: data)
        #expect(decoded.fromTrackId == 5)
        #expect(decoded.toTrackId == 2)
        #expect(decoded.similarity == 0.75)
        #expect(decoded.gapMs == 1000)
    }
}

// MARK: - TrackingDebugSummary Tests

@Suite("TrackingDebugSummary Tests")
struct TrackingDebugSummaryTests {

    @Test("fragmentationReduction calculated correctly")
    func fragmentationReduction() {
        let summary = TrackingDebugSummary(
            uniquePersonCount: 3,
            rawTrackCount: 10,
            reidMergeCount: 7,
            reidEnabled: true,
            tracks: []
        )
        // (10 - 3) / 10 * 100 = 70%
        #expect(abs(summary.fragmentationReduction - 70.0) < 0.01)
    }

    @Test("fragmentationReduction zero for zero raw tracks")
    func fragmentationReductionZero() {
        let summary = TrackingDebugSummary(
            uniquePersonCount: 0,
            rawTrackCount: 0,
            reidMergeCount: 0,
            reidEnabled: true,
            tracks: []
        )
        #expect(summary.fragmentationReduction == 0)
    }

    @Test("postTrackingFragmentationReduction calculated correctly")
    func postTrackingFragmentationReduction() {
        let summary = TrackingDebugSummary(
            uniquePersonCount: 2,
            rawTrackCount: 8,
            reidMergeCount: 3,
            reidEnabled: true,
            tracks: [],
            tracksBeforeMerge: 5,
            tracksAfterMerge: 2,
            postTrackingMergeCount: 3,
            postTrackingMergeEnabled: true
        )
        // (5 - 2) / 5 * 100 = 60%
        #expect(abs(summary.postTrackingFragmentationReduction - 60.0) < 0.01)
    }

    @Test("postTrackingFragmentationReduction zero for zero before merge")
    func postTrackingFragReductionZero() {
        let summary = TrackingDebugSummary(
            uniquePersonCount: 0,
            rawTrackCount: 0,
            reidMergeCount: 0,
            reidEnabled: false,
            tracks: [],
            tracksBeforeMerge: 0,
            tracksAfterMerge: 0
        )
        #expect(summary.postTrackingFragmentationReduction == 0)
    }

    @Test("identifiedTrackCount and identificationRate")
    func identificationMetrics() {
        let identifiedInfo = TrackDebugInfo(
            trackId: 1,
            firstFrame: 0, lastFrame: 100,
            firstFrameMs: 0, lastFrameMs: 3333,
            totalFrames: 90,
            avgConfidence: 0.85, minConfidence: 0.6, maxConfidence: 0.99,
            confidenceHistogram: [0, 0, 0, 0, 0, 0, 5, 20, 40, 25],
            gaps: [], totalGapDurationMs: 0,
            reidRestorations: [], mergedFromTrackIds: [],
            identifiedPersonId: "p1", identifiedPersonName: "Alice",
            identificationConfidence: 0.88,
            avgBboxSize: CGSize(width: 0.2, height: 0.5),
            avgBboxCenter: CGPoint(x: 0.5, y: 0.5),
            bboxSizeVariance: 0.02,
            avgVelocity: 5.0, maxVelocity: 15.0,
            motionClassification: .medium,
            state: "confirmed"
        )

        let unidentifiedInfo = TrackDebugInfo(
            trackId: 2,
            firstFrame: 0, lastFrame: 50,
            firstFrameMs: 0, lastFrameMs: 1666,
            totalFrames: 45,
            avgConfidence: 0.7, minConfidence: 0.5, maxConfidence: 0.85,
            confidenceHistogram: [0, 0, 0, 0, 0, 10, 15, 15, 5, 0],
            gaps: [], totalGapDurationMs: 0,
            reidRestorations: [], mergedFromTrackIds: [],
            identifiedPersonId: nil, identifiedPersonName: nil,
            identificationConfidence: nil,
            avgBboxSize: CGSize(width: 0.15, height: 0.4),
            avgBboxCenter: CGPoint(x: 0.3, y: 0.5),
            bboxSizeVariance: 0.03,
            avgVelocity: 3.0, maxVelocity: 8.0,
            motionClassification: .low,
            state: "confirmed"
        )

        let summary = TrackingDebugSummary(
            uniquePersonCount: 2,
            rawTrackCount: 4,
            reidMergeCount: 2,
            reidEnabled: true,
            tracks: [identifiedInfo, unidentifiedInfo]
        )

        #expect(summary.identifiedTrackCount == 1)
        #expect(abs(summary.identificationRate - 50.0) < 0.01) // 1/2 * 100
    }

    @Test("identificationRate zero for zero unique persons")
    func identificationRateZero() {
        let summary = TrackingDebugSummary(
            uniquePersonCount: 0,
            rawTrackCount: 0,
            reidMergeCount: 0,
            reidEnabled: false,
            tracks: []
        )
        #expect(summary.identificationRate == 0)
    }

    @Test("init defaults for merge fields")
    func initDefaults() {
        let summary = TrackingDebugSummary(
            uniquePersonCount: 3,
            rawTrackCount: 5,
            reidMergeCount: 2,
            reidEnabled: true,
            tracks: []
        )
        // When tracksBeforeMerge defaults to 0, it uses rawTrackCount
        #expect(summary.tracksBeforeMerge == 5)
        // When tracksAfterMerge defaults to 0, it uses uniquePersonCount
        #expect(summary.tracksAfterMerge == 3)
        #expect(summary.postTrackingMergeCount == 0)
        #expect(summary.postTrackingMergeDetails.isEmpty)
        #expect(summary.postTrackingMergeEnabled == false)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let summary = TrackingDebugSummary(
            uniquePersonCount: 2,
            rawTrackCount: 6,
            reidMergeCount: 4,
            reidEnabled: true,
            tracks: [],
            tracksBeforeMerge: 4,
            tracksAfterMerge: 2,
            postTrackingMergeCount: 2,
            postTrackingMergeDetails: [
                TrackMergeDebugDetail(fromTrackId: 3, toTrackId: 1, similarity: 0.8, gapMs: 300)
            ],
            postTrackingMergeEnabled: true
        )
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(TrackingDebugSummary.self, from: data)
        #expect(decoded.uniquePersonCount == 2)
        #expect(decoded.rawTrackCount == 6)
        #expect(decoded.reidMergeCount == 4)
        #expect(decoded.reidEnabled == true)
        #expect(decoded.tracksBeforeMerge == 4)
        #expect(decoded.tracksAfterMerge == 2)
        #expect(decoded.postTrackingMergeCount == 2)
        #expect(decoded.postTrackingMergeDetails.count == 1)
    }
}
