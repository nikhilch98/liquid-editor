import Foundation
import CoreGraphics

// MARK: - TrackingAlgorithmType

/// Types of tracking algorithms available.
enum TrackingAlgorithmType: String, Codable, CaseIterable, Sendable {
    /// Bounding box tracking - fast, good for auto-reframe.
    case boundingBox

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .boundingBox: "Bounding Box"
        }
    }
}

// MARK: - NormalizedBoundingBox

/// Normalized bounding box (0.0-1.0 coordinates).
struct NormalizedBoundingBox: Codable, Equatable, Hashable, Sendable {
    /// Center X (0.0-1.0).
    let x: Double

    /// Center Y (0.0-1.0).
    let y: Double

    /// Width (0.0-1.0).
    let width: Double

    /// Height (0.0-1.0).
    let height: Double

    /// Convert to CGRect with given container size.
    func toRect(containerSize: CGSize) -> CGRect {
        let left = (x - width / 2) * containerSize.width
        let top = (y - height / 2) * containerSize.height
        return CGRect(
            x: left,
            y: top,
            width: width * containerSize.width,
            height: height * containerSize.height
        )
    }

    /// Center point.
    var center: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - BodyOutline

/// Body outline as contour points.
struct BodyOutline: Codable, Equatable, Hashable, Sendable {
    /// Normalized contour points (0.0-1.0).
    let points: [CGPoint]

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case points
    }

    init(points: [CGPoint]) {
        self.points = points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var pointsContainer = try container.nestedUnkeyedContainer(forKey: .points)
        var decodedPoints: [CGPoint] = []
        while !pointsContainer.isAtEnd {
            let point = try pointsContainer.decode(CodablePoint.self)
            decodedPoints.append(CGPoint(x: point.x, y: point.y))
        }
        self.points = decodedPoints
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let codablePoints = points.map { CodablePoint(x: $0.x, y: $0.y) }
        try container.encode(codablePoints, forKey: .points)
    }
}

// MARK: - PoseJoints

/// Pose joints (skeletal keypoints).
struct PoseJoints: Codable, Equatable, Hashable, Sendable {
    /// Joint positions keyed by joint name (normalized 0.0-1.0).
    let joints: [String: CGPoint]

    /// Standard joint names.
    static let allJointNames: [String] = [
        "nose", "leftEye", "rightEye", "leftEar", "rightEar",
        "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
        "leftWrist", "rightWrist", "leftHip", "rightHip",
        "leftKnee", "rightKnee", "leftAnkle", "rightAnkle",
        "neck", "root",
    ]

    /// Get joint position scaled to container.
    func getJoint(_ name: String, containerSize: CGSize) -> CGPoint? {
        guard let p = joints[name] else { return nil }
        return CGPoint(x: p.x * containerSize.width, y: p.y * containerSize.height)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case joints
    }

    init(joints: [String: CGPoint]) {
        self.joints = joints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawJoints = try container.decode([String: CodablePoint].self, forKey: .joints)
        self.joints = rawJoints.mapValues { CGPoint(x: $0.x, y: $0.y) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let codableJoints = joints.mapValues { CodablePoint(x: $0.x, y: $0.y) }
        try container.encode(codableJoints, forKey: .joints)
    }
}

// MARK: - PersonTrackingResult

/// Tracking result for a single person at a single timestamp.
struct PersonTrackingResult: Codable, Equatable, Hashable, Sendable {
    /// Person index (stable across frames).
    let personIndex: Int

    /// Tracking confidence (0.0-1.0).
    let confidence: Double

    /// Bounding box (if available).
    let boundingBox: NormalizedBoundingBox?

    /// Body outline (if available).
    let bodyOutline: BodyOutline?

    /// Pose joints (if available).
    let pose: PoseJoints?

    /// Timestamp in milliseconds.
    let timestampMs: Int

    /// Identified person's ID from People library (nil if not identified).
    let identifiedPersonId: String?

    /// Identified person's name from People library (nil if not identified).
    let identifiedPersonName: String?

    /// Confidence of identification (nil if not attempted).
    let identificationConfidence: Double?

    /// Whether this person has been identified against the People library.
    var isIdentified: Bool { identifiedPersonId != nil }

    /// Display name: identified name or "Person {index+1}".
    var displayName: String { identifiedPersonName ?? "Person \(personIndex + 1)" }

    /// Create a copy with optional overrides.
    func with(
        personIndex: Int? = nil,
        confidence: Double? = nil,
        boundingBox: NormalizedBoundingBox?? = nil,
        bodyOutline: BodyOutline?? = nil,
        pose: PoseJoints?? = nil,
        timestampMs: Int? = nil,
        identifiedPersonId: String?? = nil,
        identifiedPersonName: String?? = nil,
        identificationConfidence: Double?? = nil
    ) -> PersonTrackingResult {
        PersonTrackingResult(
            personIndex: personIndex ?? self.personIndex,
            confidence: confidence ?? self.confidence,
            boundingBox: boundingBox ?? self.boundingBox,
            bodyOutline: bodyOutline ?? self.bodyOutline,
            pose: pose ?? self.pose,
            timestampMs: timestampMs ?? self.timestampMs,
            identifiedPersonId: identifiedPersonId ?? self.identifiedPersonId,
            identifiedPersonName: identifiedPersonName ?? self.identifiedPersonName,
            identificationConfidence: identificationConfidence ?? self.identificationConfidence
        )
    }
}

// MARK: - FrameTrackingResult

/// Frame-level tracking result containing all detected people.
struct FrameTrackingResult: Codable, Equatable, Hashable, Sendable {
    /// Timestamp in milliseconds.
    let timestampMs: Int

    /// All tracked people in this frame.
    let people: [PersonTrackingResult]

    /// Get specific person by index.
    func getPerson(_ index: Int) -> PersonTrackingResult? {
        people.first { $0.personIndex == index }
    }

    /// Create a copy with optional overrides.
    func with(
        timestampMs: Int? = nil,
        people: [PersonTrackingResult]? = nil
    ) -> FrameTrackingResult {
        FrameTrackingResult(
            timestampMs: timestampMs ?? self.timestampMs,
            people: people ?? self.people
        )
    }
}

// MARK: - TrackingSession

/// Tracking session state.
struct TrackingSession: Codable, Equatable, Hashable, Sendable {
    let id: String
    let algorithm: TrackingAlgorithmType
    let progress: Double
    let isComplete: Bool
    let error: String?

    init(
        id: String,
        algorithm: TrackingAlgorithmType,
        progress: Double = 0,
        isComplete: Bool = false,
        error: String? = nil
    ) {
        self.id = id
        self.algorithm = algorithm
        self.progress = progress
        self.isComplete = isComplete
        self.error = error
    }

    /// Create a copy with optional overrides.
    func with(
        progress: Double? = nil,
        isComplete: Bool? = nil,
        error: String?? = nil
    ) -> TrackingSession {
        TrackingSession(
            id: id,
            algorithm: algorithm,
            progress: progress ?? self.progress,
            isComplete: isComplete ?? self.isComplete,
            error: error ?? self.error
        )
    }
}

// MARK: - CodablePoint (Shared helper)

/// Internal helper for encoding/decoding CGPoint as {x, y} JSON.
struct CodablePoint: Codable, Equatable, Hashable, Sendable {
    let x: Double
    let y: Double
}
