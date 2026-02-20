import Foundation

// MARK: - Keyframe

/// Represents a single keyframe in the Smart Editing timeline.
///
/// A keyframe captures the transform state at a specific point in time,
/// with an interpolation type that defines the easing curve to the next keyframe.
struct Keyframe: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this keyframe.
    let id: String

    /// Timestamp in microseconds (TimeMicros) where this keyframe occurs.
    let timestampMicros: TimeMicros

    /// Transform state at this keyframe.
    let transform: VideoTransform

    /// Interpolation type to the next keyframe.
    let interpolation: InterpolationType

    /// Custom Bezier control points (used when interpolation == .bezier).
    let bezierPoints: BezierControlPoints?

    /// Optional label for the keyframe.
    let label: String?

    /// Creation timestamp for undo/redo ordering.
    let createdAt: Date

    init(
        id: String,
        timestampMicros: TimeMicros,
        transform: VideoTransform = .identity,
        interpolation: InterpolationType = .easeInOut,
        bezierPoints: BezierControlPoints? = nil,
        label: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timestampMicros = timestampMicros
        self.transform = transform
        self.interpolation = interpolation
        self.bezierPoints = bezierPoints
        self.label = label
        self.createdAt = createdAt
    }

    /// Timestamp in seconds.
    var seconds: Double { timestampMicros.toSeconds }

    /// Timestamp in milliseconds.
    var milliseconds: Double { timestampMicros.toMilliseconds }

    /// Create a copy with optional overrides.
    func with(
        id: String? = nil,
        timestampMicros: TimeMicros? = nil,
        transform: VideoTransform? = nil,
        interpolation: InterpolationType? = nil,
        bezierPoints: BezierControlPoints? = nil,
        clearBezierPoints: Bool = false,
        label: String? = nil,
        clearLabel: Bool = false
    ) -> Keyframe {
        Keyframe(
            id: id ?? self.id,
            timestampMicros: timestampMicros ?? self.timestampMicros,
            transform: transform ?? self.transform,
            interpolation: interpolation ?? self.interpolation,
            bezierPoints: clearBezierPoints ? nil : (bezierPoints ?? self.bezierPoints),
            label: clearLabel ? nil : (label ?? self.label),
            createdAt: createdAt
        )
    }

    // MARK: - Equatable

    static func == (lhs: Keyframe, rhs: Keyframe) -> Bool {
        lhs.id == rhs.id
            && lhs.timestampMicros == rhs.timestampMicros
            && lhs.transform == rhs.transform
            && lhs.interpolation == rhs.interpolation
            && lhs.bezierPoints == rhs.bezierPoints
            && lhs.label == rhs.label
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(timestampMicros)
        hasher.combine(transform)
        hasher.combine(interpolation)
        hasher.combine(bezierPoints)
        hasher.combine(label)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case timestampMs
        case transform
        case interpolation
        case bezierPoints
        case label
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let ms = try container.decode(Int.self, forKey: .timestampMs)
        timestampMicros = TimeMicros(ms) * 1_000 // ms -> micros
        transform = try container.decode(VideoTransform.self, forKey: .transform)

        let interpName = try container.decodeIfPresent(String.self, forKey: .interpolation)
        interpolation = interpName.flatMap { InterpolationType(rawValue: $0) } ?? .easeInOut

        bezierPoints = try container.decodeIfPresent(BezierControlPoints.self, forKey: .bezierPoints)
        label = try container.decodeIfPresent(String.self, forKey: .label)

        let dateString = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: dateString) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(Int(timestampMicros / 1_000), forKey: .timestampMs) // micros -> ms
        try container.encode(transform, forKey: .transform)
        try container.encode(interpolation.rawValue, forKey: .interpolation)
        try container.encodeIfPresent(bezierPoints, forKey: .bezierPoints)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(ISO8601DateFormatter().string(from: createdAt), forKey: .createdAt)
    }
}

// MARK: - KeyframeTimeline

/// Collection of keyframes for a video track, sorted by timestamp.
///
/// Unlike the Dart version which maintains internal mutability,
/// this Swift version is fully immutable. All modification methods
/// return new instances. The `modificationHash` is preserved for
/// cache invalidation compatibility.
struct KeyframeTimeline: Codable, Equatable, Hashable, Sendable {
    /// Sorted list of keyframes (sorted by timestampMicros, ascending).
    let keyframes: [Keyframe]

    /// Video duration in microseconds.
    let videoDurationMicros: TimeMicros

    /// Modification hash for cache invalidation.
    let modificationHash: Int

    init(
        videoDurationMicros: TimeMicros,
        keyframes: [Keyframe] = [],
        modificationHash: Int = 0
    ) {
        self.videoDurationMicros = videoDurationMicros
        self.keyframes = keyframes.sorted { $0.timestampMicros < $1.timestampMicros }
        self.modificationHash = modificationHash
    }

    // MARK: - Modification (returns new instances)

    /// Add a keyframe, maintaining sort order.
    func adding(_ keyframe: Keyframe) -> KeyframeTimeline {
        var newKeyframes = keyframes
        newKeyframes.append(keyframe)
        return KeyframeTimeline(
            videoDurationMicros: videoDurationMicros,
            keyframes: newKeyframes,
            modificationHash: modificationHash + 1
        )
    }

    /// Remove a keyframe by ID.
    func removing(id: String) -> KeyframeTimeline {
        KeyframeTimeline(
            videoDurationMicros: videoDurationMicros,
            keyframes: keyframes.filter { $0.id != id },
            modificationHash: modificationHash + 1
        )
    }

    /// Update a keyframe (replace by matching ID).
    func updating(_ keyframe: Keyframe) -> KeyframeTimeline {
        var newKeyframes = keyframes
        if let index = newKeyframes.firstIndex(where: { $0.id == keyframe.id }) {
            newKeyframes[index] = keyframe
        }
        return KeyframeTimeline(
            videoDurationMicros: videoDurationMicros,
            keyframes: newKeyframes,
            modificationHash: modificationHash + 1
        )
    }

    // MARK: - Queries

    /// Get keyframe at or near a timestamp.
    ///
    /// - Parameters:
    ///   - timestampMicros: The target timestamp in microseconds.
    ///   - toleranceMicros: Maximum distance to consider "near" (default: 100ms).
    /// - Returns: The nearest keyframe within tolerance, or nil.
    func keyframeNear(
        _ timestampMicros: TimeMicros,
        toleranceMicros: TimeMicros = 100_000
    ) -> Keyframe? {
        keyframes.first { abs($0.timestampMicros - timestampMicros) <= toleranceMicros }
    }

    /// Get surrounding keyframes for interpolation using binary search O(log n).
    ///
    /// Returns the keyframe immediately before and after the given timestamp.
    func surroundingKeyframes(
        _ timestampMicros: TimeMicros
    ) -> (before: Keyframe?, after: Keyframe?) {
        if keyframes.isEmpty { return (nil, nil) }

        // Binary search for insertion point
        var low = 0
        var high = keyframes.count

        while low < high {
            let mid = (low + high) / 2
            if keyframes[mid].timestampMicros <= timestampMicros {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let before = low > 0 ? keyframes[low - 1] : nil
        let after = low < keyframes.count ? keyframes[low] : nil

        return (before, after)
    }

    /// Check if there's a keyframe at the exact timestamp (within ~1 frame at 60fps).
    func hasKeyframe(at timestampMicros: TimeMicros) -> Bool {
        keyframeNear(timestampMicros, toleranceMicros: 16_000) != nil
    }

    // MARK: - Mutation (with-style)

    /// Create a copy with optional overrides.
    func with(
        videoDurationMicros: TimeMicros? = nil,
        keyframes: [Keyframe]? = nil
    ) -> KeyframeTimeline {
        KeyframeTimeline(
            videoDurationMicros: videoDurationMicros ?? self.videoDurationMicros,
            keyframes: keyframes ?? self.keyframes,
            modificationHash: modificationHash
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case videoDurationMs
        case keyframes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ms = try container.decode(Int.self, forKey: .videoDurationMs)
        videoDurationMicros = TimeMicros(ms) * 1_000
        let decoded = try container.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        keyframes = decoded.sorted { $0.timestampMicros < $1.timestampMicros }
        modificationHash = 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Int(videoDurationMicros / 1_000), forKey: .videoDurationMs)
        try container.encode(keyframes, forKey: .keyframes)
    }
}
