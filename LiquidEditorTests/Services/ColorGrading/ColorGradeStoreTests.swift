import Testing
import Foundation
@testable import LiquidEditor

@Suite("ColorGradeStore Tests")
struct ColorGradeStoreTests {

    // MARK: - Grade CRUD

    @Test("Initially has no grades")
    @MainActor func initiallyEmpty() {
        let store = ColorGradeStore()
        #expect(store.gradeCount == 0)
        #expect(store.gradedClipIds.isEmpty)
    }

    @Test("Set and get a grade")
    @MainActor func setAndGetGrade() {
        let store = ColorGradeStore()
        let grade = makeGrade(exposure: 1.0)

        store.setGrade("clip1", grade)

        #expect(store.hasGrade("clip1"))
        #expect(store.gradeForClip("clip1")?.exposure == 1.0)
        #expect(store.gradeCount == 1)
    }

    @Test("Update single parameter creates default grade if needed")
    @MainActor func updateParameterCreatesDefault() {
        let store = ColorGradeStore()

        store.updateParameter("clip1", param: "exposure", value: 0.5)

        #expect(store.hasGrade("clip1"))
        #expect(store.gradeForClip("clip1")?.exposure == 0.5)
    }

    @Test("Remove grade deletes grade and keyframes")
    @MainActor func removeGrade() {
        let store = ColorGradeStore()
        store.setGrade("clip1", makeGrade())
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 0))

        store.removeGrade("clip1")

        #expect(!store.hasGrade("clip1"))
        #expect(store.keyframesForClip("clip1").isEmpty)
    }

    @Test("Reset grade restores defaults")
    @MainActor func resetGrade() {
        let store = ColorGradeStore()
        store.setGrade("clip1", makeGrade(exposure: 2.0))
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 0))

        store.resetGrade("clip1")

        let grade = store.gradeForClip("clip1")
        #expect(grade != nil)
        #expect(grade?.isIdentity == true)
        #expect(store.keyframesForClip("clip1").isEmpty)
    }

    @Test("Copy grade duplicates to target clip")
    @MainActor func copyGrade() {
        let store = ColorGradeStore()
        store.setGrade("clip1", makeGrade(exposure: 1.5))
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 1000))

        store.copyGrade(from: "clip1", to: "clip2")

        #expect(store.hasGrade("clip2"))
        #expect(store.gradeForClip("clip2")?.exposure == 1.5)
        // ID should be different
        #expect(store.gradeForClip("clip2")?.id != store.gradeForClip("clip1")?.id)
        // Keyframes should be copied
        #expect(store.keyframesForClip("clip2").count == 1)
    }

    @Test("Copy grade is no-op for non-existent source")
    @MainActor func copyNonExistent() {
        let store = ColorGradeStore()
        store.copyGrade(from: "missing", to: "clip2")
        #expect(!store.hasGrade("clip2"))
    }

    @Test("getOrCreateGrade returns existing or creates default")
    @MainActor func getOrCreateGrade() {
        let store = ColorGradeStore()

        // Creates default
        let defaultGrade = store.getOrCreateGrade("clip1")
        #expect(defaultGrade.isIdentity)

        // Returns existing
        store.setGrade("clip1", makeGrade(contrast: 0.5))
        let existing = store.getOrCreateGrade("clip1")
        #expect(existing.contrast == 0.5)
    }

    // MARK: - Keyframe Operations

    @Test("Add keyframe maintains sorted order")
    @MainActor func addKeyframeSorted() {
        let store = ColorGradeStore()
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 3000))
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 1000))
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 2000))

        let kfs = store.keyframesForClip("clip1")
        #expect(kfs.count == 3)
        #expect(kfs[0].timestampMicros == 1000)
        #expect(kfs[1].timestampMicros == 2000)
        #expect(kfs[2].timestampMicros == 3000)
    }

    @Test("Remove keyframe by ID")
    @MainActor func removeKeyframe() {
        let store = ColorGradeStore()
        let kf = makeKeyframe(timestampMicros: 1000)
        store.addKeyframe("clip1", kf)
        #expect(store.hasKeyframes("clip1"))

        store.removeKeyframe("clip1", keyframeId: kf.id)
        #expect(!store.hasKeyframes("clip1"))
    }

    @Test("Update keyframe replaces in place")
    @MainActor func updateKeyframe() {
        let store = ColorGradeStore()
        let kf = makeKeyframe(timestampMicros: 1000)
        store.addKeyframe("clip1", kf)

        let updated = kf.with(timestampMicros: 2000)
        store.updateKeyframe("clip1", updated)

        let kfs = store.keyframesForClip("clip1")
        #expect(kfs.count == 1)
        #expect(kfs[0].timestampMicros == 2000)
    }

    @Test("Clear keyframes removes all for clip")
    @MainActor func clearKeyframes() {
        let store = ColorGradeStore()
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 1000))
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 2000))

        store.clearKeyframes("clip1")
        #expect(!store.hasKeyframes("clip1"))
    }

    // MARK: - Clip Split

    @Test("Partition on split distributes grades and keyframes")
    @MainActor func partitionOnSplit() {
        let store = ColorGradeStore()
        let grade = makeGrade(brightness: 0.3)
        store.setGrade("original", grade)

        store.addKeyframe("original", makeKeyframe(timestampMicros: 1000))
        store.addKeyframe("original", makeKeyframe(timestampMicros: 3000))
        store.addKeyframe("original", makeKeyframe(timestampMicros: 5000))

        store.partitionOnSplit(
            originalClipId: "original",
            leftClipId: "left",
            rightClipId: "right",
            offsetMicros: 3000
        )

        // Original removed
        #expect(!store.hasGrade("original"))

        // Both halves have the grade
        #expect(store.gradeForClip("left")?.brightness == 0.3)
        #expect(store.gradeForClip("right")?.brightness == 0.3)

        // Keyframes partitioned: <3000 to left, >=3000 to right
        let leftKFs = store.keyframesForClip("left")
        let rightKFs = store.keyframesForClip("right")
        #expect(leftKFs.count == 1) // timestamp 1000
        #expect(rightKFs.count == 2) // timestamps 3000, 5000

        // Right keyframes should have adjusted timestamps
        #expect(rightKFs[0].timestampMicros == 0) // 3000 - 3000
        #expect(rightKFs[1].timestampMicros == 2000) // 5000 - 3000
    }

    // MARK: - Serialization

    @Test("JSON roundtrip preserves data")
    @MainActor func jsonRoundtrip() throws {
        let store = ColorGradeStore()
        store.setGrade("clip1", makeGrade(exposure: 1.5, contrast: -0.3))
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 500))

        let data = try store.toJSON()

        let restored = ColorGradeStore()
        try restored.loadFromJSON(data)

        #expect(restored.gradeCount == 1)
        #expect(restored.gradeForClip("clip1")?.exposure == 1.5)
        #expect(restored.gradeForClip("clip1")?.contrast == -0.3)
        #expect(restored.keyframesForClip("clip1").count == 1)
    }

    @Test("Clear removes all data")
    @MainActor func clearAll() {
        let store = ColorGradeStore()
        store.setGrade("clip1", makeGrade())
        store.addKeyframe("clip1", makeKeyframe(timestampMicros: 0))

        store.clear()

        #expect(store.gradeCount == 0)
        #expect(store.gradedClipIds.isEmpty)
    }

    // MARK: - Helpers

    private func makeGrade(
        exposure: Double = 0.0,
        brightness: Double = 0.0,
        contrast: Double = 0.0
    ) -> ColorGrade {
        let now = Date()
        return ColorGrade(
            id: UUID().uuidString,
            exposure: exposure,
            brightness: brightness,
            contrast: contrast,
            createdAt: now,
            modifiedAt: now
        )
    }

    private func makeKeyframe(timestampMicros: TimeMicros) -> ColorKeyframe {
        let now = Date()
        return ColorKeyframe(
            id: UUID().uuidString,
            timestampMicros: timestampMicros,
            grade: ColorGrade(
                id: UUID().uuidString,
                createdAt: now,
                modifiedAt: now
            )
        )
    }
}
