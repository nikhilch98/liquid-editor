import Foundation
import CoreGraphics

// MARK: - TrackingQuality

/// Quality level for tracking accuracy vs speed.
enum TrackingQuality: String, Codable, CaseIterable, Sendable {
    /// Fast tracking, lower accuracy. ~2ms per frame.
    case fast

    /// Balanced tracking. ~5ms per frame.
    case balanced

    /// Highest accuracy, slower. ~8ms per frame.
    case accurate
}

// MARK: - TrackingTargetType

/// Type of object being tracked.
enum TrackingTargetType: String, Codable, CaseIterable, Sendable {
    /// Generic rectangular region selected by user.
    case object

    /// Face detected by Vision framework.
    case face

    /// Rectangular surface (signs, screens).
    case rectangle
}

// MARK: - TrackingPoint

/// A single tracked position at a specific time.
struct TrackingPoint: Codable, Equatable, Hashable, Sendable {
    /// Time in the source video (microseconds).
    let timeMicros: TimeMicros

    /// Normalized position (0.0-1.0) of the tracked object center.
    let position: CGPoint

    /// Normalized size of the tracked bounding box.
    let size: CGSize

    /// Tracking confidence (0.0 = lost, 1.0 = perfect).
    let confidence: Double

    /// Estimated rotation angle in radians (if available).
    let rotation: Double

    /// Whether this point was interpolated (gap-filled) rather than
    /// directly observed by the tracking algorithm.
    let isInterpolated: Bool

    init(
        timeMicros: TimeMicros,
        position: CGPoint,
        size: CGSize,
        confidence: Double = 1.0,
        rotation: Double = 0.0,
        isInterpolated: Bool = false
    ) {
        self.timeMicros = timeMicros
        self.position = position
        self.size = size
        self.confidence = confidence
        self.rotation = rotation
        self.isInterpolated = isInterpolated
    }

    /// Normalized bounding rectangle.
    var boundingRect: CGRect {
        CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Create a copy with optional overrides.
    func with(
        timeMicros: TimeMicros? = nil,
        position: CGPoint? = nil,
        size: CGSize? = nil,
        confidence: Double? = nil,
        rotation: Double? = nil,
        isInterpolated: Bool? = nil
    ) -> TrackingPoint {
        TrackingPoint(
            timeMicros: timeMicros ?? self.timeMicros,
            position: position ?? self.position,
            size: size ?? self.size,
            confidence: confidence ?? self.confidence,
            rotation: rotation ?? self.rotation,
            isInterpolated: isInterpolated ?? self.isInterpolated
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case timeMicros, x, y, width, height, confidence, rotation, isInterpolated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeMicros = try container.decode(TimeMicros.self, forKey: .timeMicros)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        position = CGPoint(x: x, y: y)
        let w = try container.decode(Double.self, forKey: .width)
        let h = try container.decode(Double.self, forKey: .height)
        size = CGSize(width: w, height: h)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        isInterpolated = try container.decodeIfPresent(Bool.self, forKey: .isInterpolated) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeMicros, forKey: .timeMicros)
        try container.encode(position.x, forKey: .x)
        try container.encode(position.y, forKey: .y)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(isInterpolated, forKey: .isInterpolated)
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: TrackingPoint, rhs: TrackingPoint) -> Bool {
        lhs.timeMicros == rhs.timeMicros &&
        lhs.position == rhs.position &&
        lhs.size == rhs.size &&
        lhs.confidence == rhs.confidence
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(timeMicros)
        hasher.combine(position.x)
        hasher.combine(position.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
        hasher.combine(confidence)
    }
}

// MARK: - MotionTrack

/// A complete motion track -- a sequence of tracked positions over time.
///
/// Represents the result of tracking an object through a video clip.
/// Points are sorted by time and can be interpolated for any time
/// within the track's range.
struct MotionTrack: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this track.
    let id: String

    /// Human-readable label for this track.
    let label: String

    /// ID of the clip this track was computed from.
    let clipId: String

    /// Type of tracking target.
    let targetType: TrackingTargetType

    /// Quality level used during tracking.
    let quality: TrackingQuality

    /// Tracked points sorted by time.
    let points: [TrackingPoint]

    /// Average confidence across all points.
    let averageConfidence: Double

    /// Timestamps where tracking was lost (microseconds).
    let lostFrames: [TimeMicros]

    /// When this track was created.
    let createdAt: Date

    init(
        id: String,
        label: String,
        clipId: String,
        targetType: TrackingTargetType = .object,
        quality: TrackingQuality = .balanced,
        points: [TrackingPoint],
        averageConfidence: Double? = nil,
        lostFrames: [TimeMicros] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.clipId = clipId
        self.targetType = targetType
        self.quality = quality
        self.points = points
        self.averageConfidence = averageConfidence ?? (
            points.isEmpty
                ? 0.0
                : points.reduce(0.0) { $0 + $1.confidence } / Double(points.count)
        )
        self.lostFrames = lostFrames
        self.createdAt = createdAt
    }

    /// Whether this track has any points.
    var isEmpty: Bool { points.isEmpty }

    /// Whether this track has points.
    var isNotEmpty: Bool { !points.isEmpty }

    /// Number of tracked points.
    var pointCount: Int { points.count }

    /// Start time of the track (microseconds).
    var startTimeMicros: TimeMicros { points.isEmpty ? 0 : points.first!.timeMicros }

    /// End time of the track (microseconds).
    var endTimeMicros: TimeMicros { points.isEmpty ? 0 : points.last!.timeMicros }

    /// Duration of the track (microseconds).
    var durationMicros: TimeMicros { endTimeMicros - startTimeMicros }

    /// Get the tracking point at or nearest to a specific time.
    func pointAtTime(_ timeMicros: TimeMicros) -> TrackingPoint? {
        guard !points.isEmpty else { return nil }
        if timeMicros <= startTimeMicros { return points.first }
        if timeMicros >= endTimeMicros { return points.last }

        // Binary search for nearest point.
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timeMicros < timeMicros {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Check which of the two neighbors is closer.
        if low > 0 {
            let prev = points[low - 1]
            let curr = points[low]
            if abs(timeMicros - prev.timeMicros) < abs(timeMicros - curr.timeMicros) {
                return prev
            }
        }
        return points[low]
    }

    /// Interpolate position at a specific time.
    ///
    /// Returns a linearly interpolated TrackingPoint between the
    /// two nearest tracked points.
    func interpolateAtTime(_ timeMicros: TimeMicros) -> TrackingPoint? {
        guard !points.isEmpty else { return nil }
        if timeMicros <= startTimeMicros { return points.first }
        if timeMicros >= endTimeMicros { return points.last }

        // Find surrounding points.
        var i = 0
        while i < points.count - 1 && points[i + 1].timeMicros <= timeMicros {
            i += 1
        }

        if i >= points.count - 1 { return points.last }

        let before = points[i]
        let after = points[i + 1]
        let range = after.timeMicros - before.timeMicros
        if range == 0 { return before }

        let t = Double(timeMicros - before.timeMicros) / Double(range)

        return TrackingPoint(
            timeMicros: timeMicros,
            position: CGPoint(
                x: before.position.x + (after.position.x - before.position.x) * t,
                y: before.position.y + (after.position.y - before.position.y) * t
            ),
            size: CGSize(
                width: before.size.width + (after.size.width - before.size.width) * t,
                height: before.size.height + (after.size.height - before.size.height) * t
            ),
            confidence: before.confidence + (after.confidence - before.confidence) * t,
            rotation: before.rotation + (after.rotation - before.rotation) * t,
            isInterpolated: true
        )
    }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        label: String? = nil,
        clipId: String? = nil,
        targetType: TrackingTargetType? = nil,
        quality: TrackingQuality? = nil,
        points: [TrackingPoint]? = nil,
        averageConfidence: Double? = nil,
        lostFrames: [TimeMicros]? = nil,
        createdAt: Date? = nil
    ) -> MotionTrack {
        MotionTrack(
            id: id ?? self.id,
            label: label ?? self.label,
            clipId: clipId ?? self.clipId,
            targetType: targetType ?? self.targetType,
            quality: quality ?? self.quality,
            points: points ?? self.points,
            averageConfidence: averageConfidence ?? self.averageConfidence,
            lostFrames: lostFrames ?? self.lostFrames,
            createdAt: createdAt ?? self.createdAt
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: MotionTrack, rhs: MotionTrack) -> Bool {
        lhs.id == rhs.id && lhs.clipId == rhs.clipId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(clipId)
    }
}
