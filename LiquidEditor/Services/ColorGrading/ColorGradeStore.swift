/// ColorGradeStore - Per-clip color grade persistence.
///
/// Manages color grades and color keyframes keyed by clip ID.
/// Works with both V1 and V2 clip models since grades are stored
/// separately from clip models.
///
/// Thread Safety: `@MainActor` for UI-driven mutations. All state
/// changes publish through Observation for SwiftUI binding.

import Foundation
import Observation

// MARK: - ColorGradeStore

/// Manages color grades for all clips.
///
/// Color grades are stored separately from clip models, keyed by clip ID.
/// Supports per-clip grades, color keyframes, clip split partitioning,
/// and JSON serialization for project persistence.
@Observable
@MainActor
final class ColorGradeStore {

    // MARK: - State

    /// Per-clip color grades: clipId -> ColorGrade.
    private(set) var grades: [String: ColorGrade] = [:]

    /// Per-clip color keyframes: clipId -> sorted keyframes.
    private(set) var keyframes: [String: [ColorKeyframe]] = [:]

    // MARK: - Grade Operations

    /// Get the color grade for a clip, or nil if none.
    func gradeForClip(_ clipId: String) -> ColorGrade? {
        grades[clipId]
    }

    /// Whether a clip has a color grade.
    func hasGrade(_ clipId: String) -> Bool {
        grades[clipId] != nil
    }

    /// Set the color grade for a clip.
    func setGrade(_ clipId: String, _ grade: ColorGrade) {
        grades[clipId] = grade
    }

    /// Update a single parameter of a clip's color grade.
    /// Creates a default grade if none exists.
    func updateParameter(_ clipId: String, param: String, value: Double) {
        let existing = grades[clipId] ?? defaultGrade(clipId)
        grades[clipId] = existing.withParam(param, value: value)
    }

    /// Remove the color grade for a clip.
    func removeGrade(_ clipId: String) {
        grades.removeValue(forKey: clipId)
        keyframes.removeValue(forKey: clipId)
    }

    /// Reset a clip's color grade to defaults.
    func resetGrade(_ clipId: String) {
        grades[clipId] = defaultGrade(clipId)
        keyframes.removeValue(forKey: clipId)
    }

    /// Copy color grade from one clip to another.
    func copyGrade(from sourceClipId: String, to targetClipId: String) {
        guard let source = grades[sourceClipId] else { return }

        grades[targetClipId] = source.with(
            id: UUID().uuidString,
            modifiedAt: Date()
        )

        // Copy keyframes too
        if let sourceKeyframes = keyframes[sourceClipId], !sourceKeyframes.isEmpty {
            keyframes[targetClipId] = sourceKeyframes.map {
                $0.with(id: UUID().uuidString)
            }
        }
    }

    /// Get or create a default grade for a clip.
    func getOrCreateGrade(_ clipId: String) -> ColorGrade {
        grades[clipId] ?? defaultGrade(clipId)
    }

    // MARK: - Keyframe Operations

    /// Get color keyframes for a clip (empty array if none).
    func keyframesForClip(_ clipId: String) -> [ColorKeyframe] {
        keyframes[clipId] ?? []
    }

    /// Whether a clip has color keyframes.
    func hasKeyframes(_ clipId: String) -> Bool {
        guard let kfs = keyframes[clipId] else { return false }
        return !kfs.isEmpty
    }

    /// Add a color keyframe for a clip.
    /// Maintains sorted order by timestamp.
    func addKeyframe(_ clipId: String, _ keyframe: ColorKeyframe) {
        var list = keyframes[clipId] ?? []
        list.append(keyframe)
        list.sort { $0.timestampMicros < $1.timestampMicros }
        keyframes[clipId] = list
    }

    /// Remove a color keyframe by ID.
    func removeKeyframe(_ clipId: String, keyframeId: String) {
        keyframes[clipId]?.removeAll { $0.id == keyframeId }
        if keyframes[clipId]?.isEmpty == true {
            keyframes.removeValue(forKey: clipId)
        }
    }

    /// Update a color keyframe in place.
    func updateKeyframe(_ clipId: String, _ keyframe: ColorKeyframe) {
        guard var kfs = keyframes[clipId],
              let index = kfs.firstIndex(where: { $0.id == keyframe.id }) else {
            return
        }
        kfs[index] = keyframe
        kfs.sort { $0.timestampMicros < $1.timestampMicros }
        keyframes[clipId] = kfs
    }

    /// Clear all keyframes for a clip.
    func clearKeyframes(_ clipId: String) {
        keyframes.removeValue(forKey: clipId)
    }

    // MARK: - Clip Split Support

    /// Partition color keyframes when a clip is split.
    ///
    /// Keyframes before `offsetMicros` stay with the left clip.
    /// Keyframes at or after `offsetMicros` go to the right clip
    /// with timestamps adjusted relative to the new clip start.
    func partitionOnSplit(
        originalClipId: String,
        leftClipId: String,
        rightClipId: String,
        offsetMicros: TimeMicros
    ) {
        // Copy grade to both halves
        if let grade = grades[originalClipId] {
            grades[leftClipId] = grade.with(id: UUID().uuidString)
            grades[rightClipId] = grade.with(id: UUID().uuidString)
        }

        // Partition keyframes
        if let kfs = keyframes[originalClipId], !kfs.isEmpty {
            keyframes[leftClipId] = kfs
                .filter { $0.timestampMicros < offsetMicros }
                .map { $0.with(id: UUID().uuidString) }

            keyframes[rightClipId] = kfs
                .filter { $0.timestampMicros >= offsetMicros }
                .map {
                    $0.with(
                        id: UUID().uuidString,
                        timestampMicros: $0.timestampMicros - offsetMicros
                    )
                }
        }

        // Remove original
        grades.removeValue(forKey: originalClipId)
        keyframes.removeValue(forKey: originalClipId)
    }

    // MARK: - Serialization

    /// Serialize all grades and keyframes to a JSON-compatible dictionary.
    func toJSON() throws -> Data {
        let payload = ColorGradeStorePayload(grades: grades, keyframes: keyframes)
        return try JSONEncoder().encode(payload)
    }

    /// Load grades and keyframes from JSON data.
    func loadFromJSON(_ data: Data) throws {
        let payload = try JSONDecoder().decode(ColorGradeStorePayload.self, from: data)
        grades = payload.grades
        keyframes = payload.keyframes
    }

    /// Clear all data.
    func clear() {
        grades.removeAll()
        keyframes.removeAll()
    }

    /// All clip IDs that have color grades.
    var gradedClipIds: Set<String> { Set(grades.keys) }

    /// Total number of grades stored.
    var gradeCount: Int { grades.count }

    // MARK: - Private

    private func defaultGrade(_ clipId: String) -> ColorGrade {
        let now = Date()
        return ColorGrade(id: UUID().uuidString, createdAt: now, modifiedAt: now)
    }
}

// MARK: - Serialization Model

/// Internal JSON payload for ColorGradeStore persistence.
private struct ColorGradeStorePayload: Codable {
    let grades: [String: ColorGrade]
    let keyframes: [String: [ColorKeyframe]]
}
