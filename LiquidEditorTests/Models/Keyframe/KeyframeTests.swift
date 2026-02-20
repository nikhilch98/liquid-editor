import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - Keyframe Tests

@Suite("Keyframe Tests")
struct KeyframeTests {

    // MARK: - Creation

    @Test("Keyframe creation with defaults")
    func defaultCreation() {
        let kf = Keyframe(id: "kf1", timestampMicros: 1_000_000)
        #expect(kf.id == "kf1")
        #expect(kf.timestampMicros == 1_000_000)
        #expect(kf.transform == .identity)
        #expect(kf.interpolation == .easeInOut)
        #expect(kf.bezierPoints == nil)
        #expect(kf.label == nil)
    }

    @Test("Keyframe creation with all parameters")
    func fullCreation() {
        let transform = VideoTransform(scale: 2.0, translation: CGPoint(x: 0.1, y: 0.2), rotation: 0.5)
        let kf = Keyframe(
            id: "kf1",
            timestampMicros: 500_000,
            transform: transform,
            interpolation: .cubicIn,
            bezierPoints: BezierControlPoints.easeInOut,
            label: "Start"
        )
        #expect(kf.transform.scale == 2.0)
        #expect(kf.interpolation == .cubicIn)
        #expect(kf.bezierPoints != nil)
        #expect(kf.label == "Start")
    }

    // MARK: - Time Conversions

    @Test("seconds conversion from microseconds")
    func secondsConversion() {
        let kf = Keyframe(id: "kf1", timestampMicros: 1_500_000) // 1.5 seconds
        #expect(kf.seconds == 1.5)
    }

    @Test("milliseconds conversion from microseconds")
    func millisecondsConversion() {
        let kf = Keyframe(id: "kf1", timestampMicros: 1_500_000) // 1500ms
        #expect(kf.milliseconds == 1500.0)
    }

    @Test("Zero microseconds gives zero seconds and milliseconds")
    func zeroTime() {
        let kf = Keyframe(id: "kf1", timestampMicros: 0)
        #expect(kf.seconds == 0.0)
        #expect(kf.milliseconds == 0.0)
    }

    // MARK: - with() Copy

    @Test("with() updates timestampMicros while preserving other fields")
    func withTimestamp() {
        let kf = Keyframe(id: "kf1", timestampMicros: 100_000, label: "test")
        let updated = kf.with(timestampMicros: 200_000)
        #expect(updated.timestampMicros == 200_000)
        #expect(updated.id == "kf1")
        #expect(updated.label == "test")
        #expect(updated.createdAt == kf.createdAt)
    }

    @Test("with() updates transform")
    func withTransform() {
        let kf = Keyframe(id: "kf1", timestampMicros: 0)
        let newTransform = VideoTransform(scale: 3.0)
        let updated = kf.with(transform: newTransform)
        #expect(updated.transform.scale == 3.0)
    }

    @Test("with() updates interpolation")
    func withInterpolation() {
        let kf = Keyframe(id: "kf1", timestampMicros: 0, interpolation: .linear)
        let updated = kf.with(interpolation: .cubicOut)
        #expect(updated.interpolation == .cubicOut)
    }

    @Test("with() clears bezierPoints when clearBezierPoints is true")
    func withClearBezierPoints() {
        let kf = Keyframe(
            id: "kf1",
            timestampMicros: 0,
            bezierPoints: BezierControlPoints.easeInOut
        )
        #expect(kf.bezierPoints != nil)
        let updated = kf.with(clearBezierPoints: true)
        #expect(updated.bezierPoints == nil)
    }

    @Test("with() clears label when clearLabel is true")
    func withClearLabel() {
        let kf = Keyframe(id: "kf1", timestampMicros: 0, label: "test")
        let updated = kf.with(clearLabel: true)
        #expect(updated.label == nil)
    }

    @Test("with() preserves createdAt")
    func withPreservesCreatedAt() {
        let kf = Keyframe(id: "kf1", timestampMicros: 0)
        let updated = kf.with(timestampMicros: 500_000)
        #expect(updated.createdAt == kf.createdAt)
    }

    // MARK: - Equatable

    @Test("Identical keyframes are equal")
    func equality() {
        let date = Date()
        let kf1 = Keyframe(id: "a", timestampMicros: 100, interpolation: .linear, createdAt: date)
        let kf2 = Keyframe(id: "a", timestampMicros: 100, interpolation: .linear, createdAt: date)
        #expect(kf1 == kf2)
    }

    @Test("Keyframes with different IDs are not equal")
    func inequalityId() {
        let kf1 = Keyframe(id: "a", timestampMicros: 100)
        let kf2 = Keyframe(id: "b", timestampMicros: 100)
        #expect(kf1 != kf2)
    }

    @Test("Keyframes with different timestamps are not equal")
    func inequalityTimestamp() {
        let date = Date()
        let kf1 = Keyframe(id: "a", timestampMicros: 100, createdAt: date)
        let kf2 = Keyframe(id: "a", timestampMicros: 200, createdAt: date)
        #expect(kf1 != kf2)
    }

    @Test("Keyframes with different transforms are not equal")
    func inequalityTransform() {
        let date = Date()
        let kf1 = Keyframe(id: "a", timestampMicros: 100, transform: .identity, createdAt: date)
        let kf2 = Keyframe(id: "a", timestampMicros: 100, transform: VideoTransform(scale: 2.0), createdAt: date)
        #expect(kf1 != kf2)
    }

    @Test("Keyframes with different labels are not equal")
    func inequalityLabel() {
        let date = Date()
        let kf1 = Keyframe(id: "a", timestampMicros: 100, label: "first", createdAt: date)
        let kf2 = Keyframe(id: "a", timestampMicros: 100, label: "second", createdAt: date)
        #expect(kf1 != kf2)
    }

    // MARK: - Hashable

    @Test("Equal keyframes have same hash value")
    func hashConsistency() {
        let date = Date()
        let kf1 = Keyframe(id: "a", timestampMicros: 100, createdAt: date)
        let kf2 = Keyframe(id: "a", timestampMicros: 100, createdAt: date)
        #expect(kf1.hashValue == kf2.hashValue)
    }

    @Test("Keyframes can be used in a Set")
    func setUsage() {
        let date = Date()
        let kf1 = Keyframe(id: "a", timestampMicros: 100, createdAt: date)
        let kf2 = Keyframe(id: "b", timestampMicros: 200, createdAt: date)
        let kf3 = Keyframe(id: "a", timestampMicros: 100, createdAt: date)
        let set: Set<Keyframe> = [kf1, kf2, kf3]
        #expect(set.count == 2) // kf1 and kf3 are equal
    }

    // MARK: - Codable

    @Test("Keyframe Codable roundtrip")
    func codableRoundtrip() throws {
        let original = Keyframe(
            id: "kf1",
            timestampMicros: 2_500_000, // 2500ms -> encoded as 2500
            transform: VideoTransform(scale: 1.5, rotation: 0.3),
            interpolation: .cubicIn,
            label: "test_label"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Keyframe.self, from: data)
        #expect(decoded.id == original.id)
        // Timestamp is encoded as ms, so verify microsecond precision is maintained
        #expect(decoded.timestampMicros == original.timestampMicros)
        #expect(decoded.transform == original.transform)
        #expect(decoded.interpolation == .cubicIn)
        #expect(decoded.label == "test_label")
    }

    @Test("Keyframe Codable roundtrip with bezier points")
    func codableWithBezier() throws {
        let original = Keyframe(
            id: "kf2",
            timestampMicros: 1_000_000,
            interpolation: .bezier,
            bezierPoints: BezierControlPoints(
                controlPoint1: CGPoint(x: 0.1, y: 0.2),
                controlPoint2: CGPoint(x: 0.8, y: 0.9)
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Keyframe.self, from: data)
        #expect(decoded.bezierPoints != nil)
        #expect(decoded.bezierPoints!.controlPoint1.x == 0.1)
        #expect(decoded.bezierPoints!.controlPoint2.y == 0.9)
    }

    @Test("Keyframe Codable encodes timestampMs correctly")
    func codableTimestampMs() throws {
        let kf = Keyframe(id: "kf1", timestampMicros: 3_000_000) // 3000ms
        let data = try JSONEncoder().encode(kf)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // Should be encoded as milliseconds
        #expect(json["timestampMs"] as? Int == 3000)
    }
}

// MARK: - KeyframeTimeline Tests

@Suite("KeyframeTimeline Tests")
struct KeyframeTimelineTests {

    // MARK: - Creation

    @Test("Empty KeyframeTimeline creation")
    func emptyCreation() {
        let timeline = KeyframeTimeline(videoDurationMicros: 5_000_000)
        #expect(timeline.keyframes.isEmpty)
        #expect(timeline.videoDurationMicros == 5_000_000)
        #expect(timeline.modificationHash == 0)
    }

    @Test("KeyframeTimeline sorts keyframes on creation")
    func sortingOnCreation() {
        let kf1 = Keyframe(id: "a", timestampMicros: 2_000_000)
        let kf2 = Keyframe(id: "b", timestampMicros: 500_000)
        let kf3 = Keyframe(id: "c", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf1, kf2, kf3]
        )
        #expect(timeline.keyframes[0].id == "b") // 500_000
        #expect(timeline.keyframes[1].id == "c") // 1_000_000
        #expect(timeline.keyframes[2].id == "a") // 2_000_000
    }

    // MARK: - Adding Keyframes

    @Test("Adding a keyframe maintains sorted order")
    func addingKeyframe() {
        let timeline = KeyframeTimeline(videoDurationMicros: 5_000_000)
        let kf1 = Keyframe(id: "a", timestampMicros: 2_000_000)
        let kf2 = Keyframe(id: "b", timestampMicros: 500_000)
        let t1 = timeline.adding(kf1)
        let t2 = t1.adding(kf2)
        #expect(t2.keyframes.count == 2)
        #expect(t2.keyframes[0].id == "b") // Earlier timestamp first
        #expect(t2.keyframes[1].id == "a")
    }

    @Test("Adding a keyframe increments modificationHash")
    func addingIncrementsHash() {
        let timeline = KeyframeTimeline(videoDurationMicros: 5_000_000)
        let updated = timeline.adding(Keyframe(id: "a", timestampMicros: 0))
        #expect(updated.modificationHash == 1)
    }

    // MARK: - Removing Keyframes

    @Test("Removing a keyframe by ID")
    func removingKeyframe() {
        let kf1 = Keyframe(id: "a", timestampMicros: 0)
        let kf2 = Keyframe(id: "b", timestampMicros: 500_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf1, kf2]
        )
        let removed = timeline.removing(id: "a")
        #expect(removed.keyframes.count == 1)
        #expect(removed.keyframes[0].id == "b")
    }

    @Test("Removing nonexistent ID leaves keyframes unchanged")
    func removingNonexistent() {
        let kf = Keyframe(id: "a", timestampMicros: 0)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let removed = timeline.removing(id: "zzz")
        #expect(removed.keyframes.count == 1)
    }

    @Test("Removing increments modificationHash")
    func removingIncrementsHash() {
        let kf = Keyframe(id: "a", timestampMicros: 0)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let removed = timeline.removing(id: "a")
        #expect(removed.modificationHash == 1)
    }

    // MARK: - Updating Keyframes

    @Test("Updating a keyframe replaces by ID")
    func updatingKeyframe() {
        let kf = Keyframe(id: "a", timestampMicros: 0, interpolation: .linear)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let updatedKf = kf.with(interpolation: .cubicIn)
        let updated = timeline.updating(updatedKf)
        #expect(updated.keyframes[0].interpolation == .cubicIn)
    }

    @Test("Updating nonexistent keyframe leaves timeline unchanged")
    func updatingNonexistent() {
        let kf = Keyframe(id: "a", timestampMicros: 0)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let newKf = Keyframe(id: "zzz", timestampMicros: 100)
        let updated = timeline.updating(newKf)
        #expect(updated.keyframes.count == 1)
        #expect(updated.keyframes[0].id == "a")
    }

    // MARK: - surroundingKeyframes (Binary Search)

    @Test("surroundingKeyframes on empty timeline returns nils")
    func surroundingEmpty() {
        let timeline = KeyframeTimeline(videoDurationMicros: 5_000_000)
        let (before, after) = timeline.surroundingKeyframes(500_000)
        #expect(before == nil)
        #expect(after == nil)
    }

    @Test("surroundingKeyframes before all keyframes")
    func surroundingBeforeAll() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let (before, after) = timeline.surroundingKeyframes(500_000)
        #expect(before == nil)
        #expect(after?.id == "a")
    }

    @Test("surroundingKeyframes after all keyframes")
    func surroundingAfterAll() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let (before, after) = timeline.surroundingKeyframes(2_000_000)
        #expect(before?.id == "a")
        #expect(after == nil)
    }

    @Test("surroundingKeyframes at exact keyframe time returns it as before")
    func surroundingAtExactTime() {
        let kf1 = Keyframe(id: "a", timestampMicros: 1_000_000)
        let kf2 = Keyframe(id: "b", timestampMicros: 2_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf1, kf2]
        )
        let (before, after) = timeline.surroundingKeyframes(1_000_000)
        #expect(before?.id == "a")
        #expect(after?.id == "b")
    }

    @Test("surroundingKeyframes between two keyframes")
    func surroundingBetween() {
        let kf1 = Keyframe(id: "a", timestampMicros: 0)
        let kf2 = Keyframe(id: "b", timestampMicros: 1_000_000)
        let kf3 = Keyframe(id: "c", timestampMicros: 2_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf1, kf2, kf3]
        )
        let (before, after) = timeline.surroundingKeyframes(1_500_000)
        #expect(before?.id == "b")
        #expect(after?.id == "c")
    }

    @Test("surroundingKeyframes with single keyframe at exact time")
    func surroundingSingleExact() {
        let kf = Keyframe(id: "a", timestampMicros: 500_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let (before, after) = timeline.surroundingKeyframes(500_000)
        #expect(before?.id == "a")
        #expect(after == nil)
    }

    // MARK: - keyframeNear

    @Test("keyframeNear returns keyframe within default tolerance")
    func keyframeNearDefault() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let found = timeline.keyframeNear(1_050_000) // 50ms away, within 100ms tolerance
        #expect(found?.id == "a")
    }

    @Test("keyframeNear returns nil when outside tolerance")
    func keyframeNearOutsideTolerance() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let found = timeline.keyframeNear(1_200_000) // 200ms away, outside 100ms tolerance
        #expect(found == nil)
    }

    @Test("keyframeNear with custom tolerance")
    func keyframeNearCustomTolerance() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        let found = timeline.keyframeNear(1_200_000, toleranceMicros: 250_000)
        #expect(found?.id == "a")
    }

    // MARK: - hasKeyframe

    @Test("hasKeyframe returns true at exact position")
    func hasKeyframeExact() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        #expect(timeline.hasKeyframe(at: 1_000_000))
    }

    @Test("hasKeyframe returns true within one frame (16ms)")
    func hasKeyframeWithinFrame() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        #expect(timeline.hasKeyframe(at: 1_010_000)) // 10ms away
    }

    @Test("hasKeyframe returns false when far away")
    func hasKeyframeFarAway() {
        let kf = Keyframe(id: "a", timestampMicros: 1_000_000)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf]
        )
        #expect(!timeline.hasKeyframe(at: 2_000_000))
    }

    // MARK: - with() Copy

    @Test("with() updates videoDurationMicros")
    func withDuration() {
        let timeline = KeyframeTimeline(videoDurationMicros: 5_000_000)
        let updated = timeline.with(videoDurationMicros: 10_000_000)
        #expect(updated.videoDurationMicros == 10_000_000)
    }

    @Test("with() replaces keyframes")
    func withKeyframes() {
        let kf1 = Keyframe(id: "a", timestampMicros: 0)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf1]
        )
        let kf2 = Keyframe(id: "b", timestampMicros: 100_000)
        let updated = timeline.with(keyframes: [kf2])
        #expect(updated.keyframes.count == 1)
        #expect(updated.keyframes[0].id == "b")
    }

    // MARK: - Codable

    @Test("KeyframeTimeline Codable roundtrip")
    func codableRoundtrip() throws {
        let kf1 = Keyframe(id: "a", timestampMicros: 1_000_000, interpolation: .linear)
        let kf2 = Keyframe(id: "b", timestampMicros: 2_000_000, interpolation: .easeIn)
        let timeline = KeyframeTimeline(
            videoDurationMicros: 5_000_000,
            keyframes: [kf1, kf2]
        )
        let data = try JSONEncoder().encode(timeline)
        let decoded = try JSONDecoder().decode(KeyframeTimeline.self, from: data)
        #expect(decoded.videoDurationMicros == 5_000_000)
        #expect(decoded.keyframes.count == 2)
        #expect(decoded.keyframes[0].id == "a")
        #expect(decoded.keyframes[1].id == "b")
    }

    @Test("KeyframeTimeline Codable encodes videoDurationMs")
    func codableDurationMs() throws {
        let timeline = KeyframeTimeline(videoDurationMicros: 3_000_000) // 3000ms
        let data = try JSONEncoder().encode(timeline)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["videoDurationMs"] as? Int == 3000)
    }
}
