import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - TrackingAlgorithmType Tests

@Suite("TrackingAlgorithmType Tests")
struct TrackingAlgorithmTypeTests {

    @Test("all cases")
    func allCases() {
        #expect(TrackingAlgorithmType.allCases.count == 1)
        #expect(TrackingAlgorithmType.boundingBox.rawValue == "boundingBox")
    }

    @Test("display name")
    func displayName() {
        #expect(TrackingAlgorithmType.boundingBox.displayName == "Bounding Box")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let algo = TrackingAlgorithmType.boundingBox
        let data = try JSONEncoder().encode(algo)
        let decoded = try JSONDecoder().decode(TrackingAlgorithmType.self, from: data)
        #expect(decoded == algo)
    }
}

// MARK: - NormalizedBoundingBox Tests

@Suite("NormalizedBoundingBox Tests")
struct NormalizedBoundingBoxTests {

    @Test("creation")
    func creation() {
        let bb = NormalizedBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.3)
        #expect(bb.x == 0.5)
        #expect(bb.y == 0.5)
        #expect(bb.width == 0.2)
        #expect(bb.height == 0.3)
    }

    @Test("center computed property")
    func center() {
        let bb = NormalizedBoundingBox(x: 0.3, y: 0.7, width: 0.1, height: 0.1)
        #expect(bb.center == CGPoint(x: 0.3, y: 0.7))
    }

    @Test("toRect converts correctly")
    func toRect() {
        let bb = NormalizedBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.4)
        let rect = bb.toRect(containerSize: CGSize(width: 1000, height: 500))
        #expect(rect.origin.x == 400.0) // (0.5 - 0.1) * 1000
        #expect(rect.origin.y == 150.0) // (0.5 - 0.2) * 500
        #expect(rect.size.width == 200.0) // 0.2 * 1000
        #expect(rect.size.height == 200.0) // 0.4 * 500
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let bb = NormalizedBoundingBox(x: 0.3, y: 0.4, width: 0.5, height: 0.6)
        let data = try JSONEncoder().encode(bb)
        let decoded = try JSONDecoder().decode(NormalizedBoundingBox.self, from: data)
        #expect(decoded == bb)
    }
}

// MARK: - BodyOutline Tests

@Suite("BodyOutline Tests")
struct BodyOutlineTests {

    @Test("creation")
    func creation() {
        let points = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.5, y: 0.6)]
        let outline = BodyOutline(points: points)
        #expect(outline.points.count == 3)
        #expect(outline.points[0] == CGPoint(x: 0.1, y: 0.2))
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let points = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.5)]
        let outline = BodyOutline(points: points)
        let data = try JSONEncoder().encode(outline)
        let decoded = try JSONDecoder().decode(BodyOutline.self, from: data)
        #expect(decoded.points.count == 2)
        #expect(decoded.points[0].x == 0.1)
        #expect(decoded.points[0].y == 0.2)
        #expect(decoded.points[1].x == 0.5)
    }
}

// MARK: - PoseJoints Tests

@Suite("PoseJoints Tests")
struct PoseJointsTests {

    @Test("creation")
    func creation() {
        let joints: [String: CGPoint] = [
            "nose": CGPoint(x: 0.5, y: 0.3),
            "leftShoulder": CGPoint(x: 0.4, y: 0.5),
        ]
        let pose = PoseJoints(joints: joints)
        #expect(pose.joints.count == 2)
        #expect(pose.joints["nose"] == CGPoint(x: 0.5, y: 0.3))
    }

    @Test("getJoint scales to container")
    func getJoint() {
        let pose = PoseJoints(joints: [
            "nose": CGPoint(x: 0.5, y: 0.3)
        ])
        let scaled = pose.getJoint("nose", containerSize: CGSize(width: 1920, height: 1080))
        #expect(scaled != nil)
        #expect(scaled!.x == 960.0)
        #expect(scaled!.y == 324.0)
    }

    @Test("getJoint returns nil for missing joint")
    func getJointMissing() {
        let pose = PoseJoints(joints: [:])
        #expect(pose.getJoint("nose", containerSize: CGSize(width: 100, height: 100)) == nil)
    }

    @Test("allJointNames has expected count")
    func allJointNames() {
        #expect(PoseJoints.allJointNames.count == 19)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let pose = PoseJoints(joints: [
            "nose": CGPoint(x: 0.5, y: 0.3),
            "leftEye": CGPoint(x: 0.45, y: 0.28),
        ])
        let data = try JSONEncoder().encode(pose)
        let decoded = try JSONDecoder().decode(PoseJoints.self, from: data)
        #expect(decoded.joints.count == 2)
        #expect(decoded.joints["nose"]!.x == 0.5)
        #expect(decoded.joints["leftEye"]!.y == 0.28)
    }
}

// MARK: - PersonTrackingResult Tests

@Suite("PersonTrackingResult Tests")
struct PersonTrackingResultTests {

    @Test("creation")
    func creation() {
        let result = PersonTrackingResult(
            personIndex: 0,
            confidence: 0.95,
            boundingBox: NormalizedBoundingBox(x: 0.5, y: 0.5, width: 0.3, height: 0.6),
            bodyOutline: nil,
            pose: nil,
            timestampMs: 100,
            identifiedPersonId: nil,
            identifiedPersonName: nil,
            identificationConfidence: nil
        )
        #expect(result.personIndex == 0)
        #expect(result.confidence == 0.95)
        #expect(result.boundingBox != nil)
        #expect(!result.isIdentified)
        #expect(result.displayName == "Person 1")
    }

    @Test("identified person properties")
    func identified() {
        let result = PersonTrackingResult(
            personIndex: 1,
            confidence: 0.9,
            boundingBox: nil,
            bodyOutline: nil,
            pose: nil,
            timestampMs: 200,
            identifiedPersonId: "person-abc",
            identifiedPersonName: "Alice",
            identificationConfidence: 0.85
        )
        #expect(result.isIdentified)
        #expect(result.displayName == "Alice")
        #expect(result.identifiedPersonId == "person-abc")
    }

    @Test("with() copy")
    func withCopy() {
        let result = PersonTrackingResult(
            personIndex: 0,
            confidence: 0.8,
            boundingBox: nil,
            bodyOutline: nil,
            pose: nil,
            timestampMs: 0,
            identifiedPersonId: nil,
            identifiedPersonName: nil,
            identificationConfidence: nil
        )
        let modified = result.with(confidence: 0.95, identifiedPersonName: .some("Bob"))
        #expect(modified.confidence == 0.95)
        #expect(modified.identifiedPersonName == "Bob")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let result = PersonTrackingResult(
            personIndex: 0,
            confidence: 0.92,
            boundingBox: NormalizedBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.4),
            bodyOutline: nil,
            pose: nil,
            timestampMs: 500,
            identifiedPersonId: "p1",
            identifiedPersonName: "Test",
            identificationConfidence: 0.88
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PersonTrackingResult.self, from: data)
        #expect(decoded.personIndex == result.personIndex)
        #expect(decoded.confidence == result.confidence)
        #expect(decoded.timestampMs == result.timestampMs)
        #expect(decoded.identifiedPersonId == "p1")
    }
}

// MARK: - FrameTrackingResult Tests

@Suite("FrameTrackingResult Tests")
struct FrameTrackingResultTests {

    @Test("creation and getPerson")
    func creationAndGetPerson() {
        let p0 = PersonTrackingResult(
            personIndex: 0, confidence: 0.9,
            boundingBox: nil, bodyOutline: nil, pose: nil,
            timestampMs: 100, identifiedPersonId: nil,
            identifiedPersonName: nil, identificationConfidence: nil
        )
        let p1 = PersonTrackingResult(
            personIndex: 1, confidence: 0.85,
            boundingBox: nil, bodyOutline: nil, pose: nil,
            timestampMs: 100, identifiedPersonId: nil,
            identifiedPersonName: nil, identificationConfidence: nil
        )
        let frame = FrameTrackingResult(timestampMs: 100, people: [p0, p1])
        #expect(frame.people.count == 2)
        #expect(frame.getPerson(0)?.confidence == 0.9)
        #expect(frame.getPerson(1)?.confidence == 0.85)
        #expect(frame.getPerson(5) == nil)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let frame = FrameTrackingResult(timestampMs: 200, people: [])
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(FrameTrackingResult.self, from: data)
        #expect(decoded.timestampMs == 200)
        #expect(decoded.people.isEmpty)
    }
}

// MARK: - TrackingSession Tests

@Suite("TrackingSession Tests")
struct TrackingSessionTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let session = TrackingSession(id: "ts-1", algorithm: .boundingBox)
        #expect(session.id == "ts-1")
        #expect(session.algorithm == .boundingBox)
        #expect(session.progress == 0)
        #expect(session.isComplete == false)
        #expect(session.error == nil)
    }

    @Test("with() copy")
    func withCopy() {
        let session = TrackingSession(id: "ts-1", algorithm: .boundingBox)
        let updated = session.with(progress: 0.5)
        #expect(updated.progress == 0.5)
        #expect(updated.id == "ts-1")

        let completed = updated.with(isComplete: true)
        #expect(completed.isComplete)

        let errored = session.with(error: .some("Failed"))
        #expect(errored.error == "Failed")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let session = TrackingSession(
            id: "ts-codec",
            algorithm: .boundingBox,
            progress: 0.75,
            isComplete: false,
            error: nil
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TrackingSession.self, from: data)
        #expect(decoded.id == session.id)
        #expect(decoded.algorithm == session.algorithm)
        #expect(decoded.progress == session.progress)
    }
}

// MARK: - TrackingQuality Tests

@Suite("TrackingQuality Tests")
struct TrackingQualityTests {

    @Test("all cases")
    func allCases() {
        #expect(TrackingQuality.allCases.count == 3)
        #expect(TrackingQuality.fast.rawValue == "fast")
        #expect(TrackingQuality.balanced.rawValue == "balanced")
        #expect(TrackingQuality.accurate.rawValue == "accurate")
    }
}

// MARK: - TrackingTargetType Tests

@Suite("TrackingTargetType Tests")
struct TrackingTargetTypeTests {

    @Test("all cases")
    func allCases() {
        #expect(TrackingTargetType.allCases.count == 3)
        #expect(TrackingTargetType.object.rawValue == "object")
        #expect(TrackingTargetType.face.rawValue == "face")
        #expect(TrackingTargetType.rectangle.rawValue == "rectangle")
    }
}

// MARK: - TrackingPoint Tests

@Suite("TrackingPoint Tests")
struct TrackingPointTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let pt = TrackingPoint(
            timeMicros: 1_000_000,
            position: CGPoint(x: 0.5, y: 0.5),
            size: CGSize(width: 0.2, height: 0.3)
        )
        #expect(pt.timeMicros == 1_000_000)
        #expect(pt.confidence == 1.0)
        #expect(pt.rotation == 0.0)
        #expect(pt.isInterpolated == false)
    }

    @Test("boundingRect computed property")
    func boundingRect() {
        let pt = TrackingPoint(
            timeMicros: 0,
            position: CGPoint(x: 0.5, y: 0.5),
            size: CGSize(width: 0.2, height: 0.4)
        )
        let rect = pt.boundingRect
        #expect(rect.origin.x == 0.4)
        #expect(rect.origin.y == 0.3)
        #expect(rect.size.width == 0.2)
        #expect(rect.size.height == 0.4)
    }

    @Test("with() copy")
    func withCopy() {
        let pt = TrackingPoint(
            timeMicros: 0,
            position: CGPoint(x: 0.5, y: 0.5),
            size: CGSize(width: 0.1, height: 0.1)
        )
        let modified = pt.with(confidence: 0.5, isInterpolated: true)
        #expect(modified.confidence == 0.5)
        #expect(modified.isInterpolated == true)
        #expect(modified.position == pt.position)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let pt = TrackingPoint(
            timeMicros: 500_000,
            position: CGPoint(x: 0.3, y: 0.7),
            size: CGSize(width: 0.15, height: 0.25),
            confidence: 0.9,
            rotation: 0.1,
            isInterpolated: true
        )
        let data = try JSONEncoder().encode(pt)
        let decoded = try JSONDecoder().decode(TrackingPoint.self, from: data)
        #expect(decoded.timeMicros == pt.timeMicros)
        #expect(decoded.position.x == pt.position.x)
        #expect(decoded.position.y == pt.position.y)
        #expect(decoded.size.width == pt.size.width)
        #expect(decoded.size.height == pt.size.height)
        #expect(decoded.confidence == pt.confidence)
        #expect(decoded.rotation == pt.rotation)
        #expect(decoded.isInterpolated == true)
    }
}

// MARK: - MotionTrack Tests

@Suite("MotionTrack Tests")
struct MotionTrackTests {

    private func makePoints() -> [TrackingPoint] {
        [
            TrackingPoint(timeMicros: 0, position: CGPoint(x: 0.1, y: 0.1), size: CGSize(width: 0.2, height: 0.2), confidence: 0.8),
            TrackingPoint(timeMicros: 500_000, position: CGPoint(x: 0.3, y: 0.3), size: CGSize(width: 0.2, height: 0.2), confidence: 0.9),
            TrackingPoint(timeMicros: 1_000_000, position: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.2, height: 0.2), confidence: 1.0),
        ]
    }

    private func makeTrack() -> MotionTrack {
        MotionTrack(
            id: "mt-1",
            label: "Object 1",
            clipId: "clip-1",
            points: makePoints()
        )
    }

    @Test("creation and computed properties")
    func creationComputed() {
        let track = makeTrack()
        #expect(track.id == "mt-1")
        #expect(track.label == "Object 1")
        #expect(track.clipId == "clip-1")
        #expect(track.targetType == .object)
        #expect(track.quality == .balanced)
        #expect(!track.isEmpty)
        #expect(track.isNotEmpty)
        #expect(track.pointCount == 3)
        #expect(track.startTimeMicros == 0)
        #expect(track.endTimeMicros == 1_000_000)
        #expect(track.durationMicros == 1_000_000)
    }

    @Test("averageConfidence auto-calculated")
    func averageConfidence() {
        let track = makeTrack()
        let expected = (0.8 + 0.9 + 1.0) / 3.0
        #expect(abs(track.averageConfidence - expected) < 0.001)
    }

    @Test("empty track properties")
    func emptyTrack() {
        let track = MotionTrack(id: "mt-empty", label: "Empty", clipId: "c", points: [])
        #expect(track.isEmpty)
        #expect(!track.isNotEmpty)
        #expect(track.pointCount == 0)
        #expect(track.startTimeMicros == 0)
        #expect(track.endTimeMicros == 0)
        #expect(track.durationMicros == 0)
        #expect(track.averageConfidence == 0.0)
    }

    @Test("pointAtTime returns nearest point")
    func pointAtTime() {
        let track = makeTrack()
        // Before start
        let before = track.pointAtTime(-100)
        #expect(before?.timeMicros == 0)
        // After end
        let after = track.pointAtTime(2_000_000)
        #expect(after?.timeMicros == 1_000_000)
        // Close to second point
        let near = track.pointAtTime(400_000)
        #expect(near?.timeMicros == 500_000)
        // Close to first point
        let nearFirst = track.pointAtTime(100_000)
        #expect(nearFirst?.timeMicros == 0)
    }

    @Test("pointAtTime on empty returns nil")
    func pointAtTimeEmpty() {
        let track = MotionTrack(id: "e", label: "E", clipId: "c", points: [])
        #expect(track.pointAtTime(0) == nil)
    }

    @Test("interpolateAtTime returns interpolated point")
    func interpolateAtTime() {
        let track = makeTrack()
        // Midpoint between first and second
        let interp = track.interpolateAtTime(250_000)
        #expect(interp != nil)
        #expect(interp!.isInterpolated == true)
        #expect(interp!.timeMicros == 250_000)
        // Position should be between first (0.1) and second (0.3) at t=0.5
        #expect(abs(interp!.position.x - 0.2) < 0.001)
        #expect(abs(interp!.position.y - 0.2) < 0.001)
    }

    @Test("interpolateAtTime at boundaries")
    func interpolateAtBoundaries() {
        let track = makeTrack()
        let start = track.interpolateAtTime(0)
        #expect(start?.position.x == 0.1)
        let end = track.interpolateAtTime(1_000_000)
        #expect(end?.position.x == 0.5)
    }

    @Test("Equatable is by id + clipId")
    func equatable() {
        let a = MotionTrack(id: "mt-1", label: "A", clipId: "c-1", points: [])
        let b = MotionTrack(id: "mt-1", label: "B", clipId: "c-1", points: makePoints())
        #expect(a == b) // Same id + clipId
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let track = MotionTrack(
            id: "mt-codec",
            label: "Test Track",
            clipId: "clip-codec",
            targetType: .face,
            quality: .accurate,
            points: makePoints(),
            lostFrames: [250_000]
        )
        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(MotionTrack.self, from: data)
        #expect(decoded.id == track.id)
        #expect(decoded.label == track.label)
        #expect(decoded.clipId == track.clipId)
        #expect(decoded.targetType == .face)
        #expect(decoded.quality == .accurate)
        #expect(decoded.points.count == 3)
        #expect(decoded.lostFrames == [250_000])
    }
}
