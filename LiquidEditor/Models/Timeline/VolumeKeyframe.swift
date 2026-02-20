import Foundation

// MARK: - VolumeKeyframe

/// Immutable volume keyframe for audio envelope.
struct VolumeKeyframe: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Unique keyframe identifier.
    let id: String

    /// Time position on timeline (microseconds).
    let time: TimeMicros

    /// Volume level (0.0 to 1.0).
    let volume: Double

    init(id: String, time: TimeMicros, volume: Double) {
        self.id = id
        self.time = time
        self.volume = min(max(volume, 0.0), 1.0)
    }

    /// Create a copy with updated values.
    func with(
        id: String? = nil,
        time: TimeMicros? = nil,
        volume: Double? = nil
    ) -> VolumeKeyframe {
        VolumeKeyframe(
            id: id ?? self.id,
            time: time ?? self.time,
            volume: volume ?? self.volume
        )
    }

    /// Move keyframe to new time.
    func moveTo(_ newTime: TimeMicros) -> VolumeKeyframe {
        with(time: newTime)
    }

    /// Set volume level.
    func withVolume(_ newVolume: Double) -> VolumeKeyframe {
        with(volume: newVolume)
    }
}

// MARK: - VolumeEnvelope

/// Collection of volume keyframes for an audio clip.
struct VolumeEnvelope: Codable, Equatable, Hashable, Sendable {
    /// Keyframes sorted by time.
    let keyframes: [VolumeKeyframe]

    /// Empty envelope (constant volume).
    static let empty = VolumeEnvelope()

    init(keyframes: [VolumeKeyframe] = []) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    /// Get volume at a specific time (with interpolation).
    func getVolumeAt(_ time: TimeMicros) -> Double {
        guard !keyframes.isEmpty else { return 1.0 }
        if keyframes.count == 1 { return keyframes.first!.volume }

        // Find surrounding keyframes
        var before: VolumeKeyframe?
        var after: VolumeKeyframe?

        for kf in keyframes {
            if kf.time <= time {
                before = kf
            } else {
                after = kf
                break
            }
        }

        // Handle edge cases
        guard let b = before else { return keyframes.first!.volume }
        guard let a = after else { return keyframes.last!.volume }

        // Linear interpolation
        let t = Double(time - b.time) / Double(a.time - b.time)
        return b.volume + (a.volume - b.volume) * t
    }

    /// Add a keyframe.
    func addKeyframe(_ keyframe: VolumeKeyframe) -> VolumeEnvelope {
        var newKeyframes = keyframes.filter { $0.time != keyframe.time }
        newKeyframes.append(keyframe)
        return VolumeEnvelope(keyframes: newKeyframes)
    }

    /// Remove a keyframe by ID.
    func removeKeyframe(_ keyframeId: String) -> VolumeEnvelope {
        VolumeEnvelope(keyframes: keyframes.filter { $0.id != keyframeId })
    }

    /// Update a keyframe.
    func updateKeyframe(_ keyframe: VolumeKeyframe) -> VolumeEnvelope {
        let newKeyframes = keyframes.map { kf in
            kf.id == keyframe.id ? keyframe : kf
        }
        return VolumeEnvelope(keyframes: newKeyframes)
    }

    /// Get keyframe near a time (within threshold).
    func keyframeNear(_ time: TimeMicros, threshold: TimeMicros) -> VolumeKeyframe? {
        keyframes.first { abs($0.time - time) <= threshold }
    }

    /// Create fade in envelope.
    static func fadeIn(
        startId: String,
        endId: String,
        startTime: TimeMicros,
        endTime: TimeMicros,
        startVolume: Double = 0.0,
        endVolume: Double = 1.0
    ) -> VolumeEnvelope {
        VolumeEnvelope(keyframes: [
            VolumeKeyframe(id: startId, time: startTime, volume: startVolume),
            VolumeKeyframe(id: endId, time: endTime, volume: endVolume),
        ])
    }

    /// Create fade out envelope.
    static func fadeOut(
        startId: String,
        endId: String,
        startTime: TimeMicros,
        endTime: TimeMicros,
        startVolume: Double = 1.0,
        endVolume: Double = 0.0
    ) -> VolumeEnvelope {
        VolumeEnvelope(keyframes: [
            VolumeKeyframe(id: startId, time: startTime, volume: startVolume),
            VolumeKeyframe(id: endId, time: endTime, volume: endVolume),
        ])
    }
}
