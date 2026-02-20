import Testing
import Foundation
@testable import LiquidEditor

// MARK: - VolumeKeyframe Tests

@Suite("VolumeKeyframe Tests")
struct VolumeKeyframeTests {

    @Test("Creation with valid volume")
    func creation() {
        let kf = VolumeKeyframe(id: "kf-1", time: 1_000_000, volume: 0.5)
        #expect(kf.id == "kf-1")
        #expect(kf.time == 1_000_000)
        #expect(kf.volume == 0.5)
    }

    @Test("Volume clamped to 0")
    func volumeClampedLow() {
        let kf = VolumeKeyframe(id: "kf", time: 0, volume: -0.5)
        #expect(kf.volume == 0.0)
    }

    @Test("Volume clamped to 1")
    func volumeClampedHigh() {
        let kf = VolumeKeyframe(id: "kf", time: 0, volume: 1.5)
        #expect(kf.volume == 1.0)
    }

    @Test("Volume at boundary 0")
    func volumeAtZero() {
        let kf = VolumeKeyframe(id: "kf", time: 0, volume: 0.0)
        #expect(kf.volume == 0.0)
    }

    @Test("Volume at boundary 1")
    func volumeAtOne() {
        let kf = VolumeKeyframe(id: "kf", time: 0, volume: 1.0)
        #expect(kf.volume == 1.0)
    }

    @Test("with() copy method")
    func withCopy() {
        let original = VolumeKeyframe(id: "kf-1", time: 1_000_000, volume: 0.5)
        let modified = original.with(volume: 0.8)
        #expect(modified.volume == 0.8)
        #expect(modified.time == 1_000_000)
        #expect(modified.id == "kf-1")
    }

    @Test("moveTo changes time")
    func moveTo() {
        let kf = VolumeKeyframe(id: "kf-1", time: 1_000_000, volume: 0.5)
        let moved = kf.moveTo(2_000_000)
        #expect(moved.time == 2_000_000)
        #expect(moved.volume == 0.5) // unchanged
    }

    @Test("withVolume changes volume")
    func withVolume() {
        let kf = VolumeKeyframe(id: "kf-1", time: 1_000_000, volume: 0.5)
        let updated = kf.withVolume(0.9)
        #expect(updated.volume == 0.9)
        #expect(updated.time == 1_000_000)
    }

    @Test("withVolume clamps")
    func withVolumeClamps() {
        let kf = VolumeKeyframe(id: "kf-1", time: 0, volume: 0.5)
        let clamped = kf.withVolume(2.0)
        #expect(clamped.volume == 1.0)
    }

    @Test("Identifiable id property")
    func identifiable() {
        let kf = VolumeKeyframe(id: "kf-unique", time: 0, volume: 0.5)
        #expect(kf.id == "kf-unique")
    }

    @Test("Equatable")
    func equatable() {
        let a = VolumeKeyframe(id: "kf", time: 100, volume: 0.5)
        let b = VolumeKeyframe(id: "kf", time: 100, volume: 0.5)
        #expect(a == b)
    }

    @Test("Equatable detects different volume")
    func equatableDifferent() {
        let a = VolumeKeyframe(id: "kf", time: 100, volume: 0.5)
        let b = VolumeKeyframe(id: "kf", time: 100, volume: 0.8)
        #expect(a != b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = VolumeKeyframe(id: "kf-1", time: 2_500_000, volume: 0.75)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VolumeKeyframe.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - VolumeEnvelope Tests

@Suite("VolumeEnvelope Tests")
struct VolumeEnvelopeTests {

    @Test("Empty envelope returns 1.0")
    func emptyEnvelope() {
        let envelope = VolumeEnvelope.empty
        #expect(envelope.getVolumeAt(0) == 1.0)
        #expect(envelope.getVolumeAt(1_000_000) == 1.0)
    }

    @Test("Single keyframe returns its volume")
    func singleKeyframe() {
        let kf = VolumeKeyframe(id: "kf", time: 500_000, volume: 0.5)
        let envelope = VolumeEnvelope(keyframes: [kf])
        #expect(envelope.getVolumeAt(0) == 0.5)
        #expect(envelope.getVolumeAt(500_000) == 0.5)
        #expect(envelope.getVolumeAt(1_000_000) == 0.5)
    }

    @Test("Interpolation between two keyframes")
    func interpolation() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 0.0)
        let kf2 = VolumeKeyframe(id: "kf2", time: 1_000_000, volume: 1.0)
        let envelope = VolumeEnvelope(keyframes: [kf1, kf2])

        // At start
        #expect(envelope.getVolumeAt(0) == 0.0)
        // At end
        #expect(envelope.getVolumeAt(1_000_000) == 1.0)
        // At midpoint
        #expect(abs(envelope.getVolumeAt(500_000) - 0.5) < 0.0001)
        // At quarter
        #expect(abs(envelope.getVolumeAt(250_000) - 0.25) < 0.0001)
    }

    @Test("Before first keyframe returns first volume")
    func beforeFirst() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 1_000_000, volume: 0.8)
        let kf2 = VolumeKeyframe(id: "kf2", time: 2_000_000, volume: 0.2)
        let envelope = VolumeEnvelope(keyframes: [kf1, kf2])
        #expect(envelope.getVolumeAt(0) == 0.8) // before first -> first volume
    }

    @Test("After last keyframe returns last volume")
    func afterLast() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 0.2)
        let kf2 = VolumeKeyframe(id: "kf2", time: 1_000_000, volume: 0.8)
        let envelope = VolumeEnvelope(keyframes: [kf1, kf2])
        #expect(envelope.getVolumeAt(5_000_000) == 0.8) // after last -> last volume
    }

    @Test("Three keyframes interpolation")
    func threeKeyframes() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 1.0)
        let kf2 = VolumeKeyframe(id: "kf2", time: 1_000_000, volume: 0.0)
        let kf3 = VolumeKeyframe(id: "kf3", time: 2_000_000, volume: 1.0)
        let envelope = VolumeEnvelope(keyframes: [kf1, kf2, kf3])

        #expect(abs(envelope.getVolumeAt(500_000) - 0.5) < 0.0001)   // between kf1 and kf2
        #expect(abs(envelope.getVolumeAt(1_000_000) - 0.0) < 0.0001) // at kf2
        #expect(abs(envelope.getVolumeAt(1_500_000) - 0.5) < 0.0001) // between kf2 and kf3
    }

    @Test("Keyframes are sorted by time")
    func keyframesSorted() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 2_000_000, volume: 1.0)
        let kf2 = VolumeKeyframe(id: "kf2", time: 0, volume: 0.0)
        let kf3 = VolumeKeyframe(id: "kf3", time: 1_000_000, volume: 0.5)
        let envelope = VolumeEnvelope(keyframes: [kf1, kf2, kf3])

        #expect(envelope.keyframes[0].time == 0)
        #expect(envelope.keyframes[1].time == 1_000_000)
        #expect(envelope.keyframes[2].time == 2_000_000)
    }

    @Test("addKeyframe adds new keyframe")
    func addKeyframe() {
        let envelope = VolumeEnvelope.empty
        let kf = VolumeKeyframe(id: "kf1", time: 500_000, volume: 0.5)
        let updated = envelope.addKeyframe(kf)
        #expect(updated.keyframes.count == 1)
        #expect(updated.keyframes[0].id == "kf1")
    }

    @Test("addKeyframe replaces at same time")
    func addKeyframeReplaceSameTime() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 500_000, volume: 0.5)
        let envelope = VolumeEnvelope(keyframes: [kf1])
        let kf2 = VolumeKeyframe(id: "kf2", time: 500_000, volume: 0.8)
        let updated = envelope.addKeyframe(kf2)
        #expect(updated.keyframes.count == 1)
        #expect(updated.keyframes[0].id == "kf2")
        #expect(updated.keyframes[0].volume == 0.8)
    }

    @Test("removeKeyframe removes by ID")
    func removeKeyframe() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 0.5)
        let kf2 = VolumeKeyframe(id: "kf2", time: 1_000_000, volume: 1.0)
        let envelope = VolumeEnvelope(keyframes: [kf1, kf2])
        let updated = envelope.removeKeyframe("kf1")
        #expect(updated.keyframes.count == 1)
        #expect(updated.keyframes[0].id == "kf2")
    }

    @Test("removeKeyframe with non-existent ID does nothing")
    func removeKeyframeNonExistent() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 0.5)
        let envelope = VolumeEnvelope(keyframes: [kf1])
        let updated = envelope.removeKeyframe("nonexistent")
        #expect(updated.keyframes.count == 1)
    }

    @Test("updateKeyframe updates existing")
    func updateKeyframe() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 0.5)
        let envelope = VolumeEnvelope(keyframes: [kf1])
        let newKf = VolumeKeyframe(id: "kf1", time: 0, volume: 0.9)
        let updated = envelope.updateKeyframe(newKf)
        #expect(updated.keyframes.count == 1)
        #expect(updated.keyframes[0].volume == 0.9)
    }

    @Test("keyframeNear finds within threshold")
    func keyframeNear() {
        let kf = VolumeKeyframe(id: "kf1", time: 1_000_000, volume: 0.5)
        let envelope = VolumeEnvelope(keyframes: [kf])
        let found = envelope.keyframeNear(1_050_000, threshold: 100_000)
        #expect(found != nil)
        #expect(found?.id == "kf1")
    }

    @Test("keyframeNear returns nil outside threshold")
    func keyframeNearOutside() {
        let kf = VolumeKeyframe(id: "kf1", time: 1_000_000, volume: 0.5)
        let envelope = VolumeEnvelope(keyframes: [kf])
        let found = envelope.keyframeNear(2_000_000, threshold: 100_000)
        #expect(found == nil)
    }

    @Test("fadeIn factory")
    func fadeIn() {
        let envelope = VolumeEnvelope.fadeIn(
            startId: "start",
            endId: "end",
            startTime: 0,
            endTime: 1_000_000
        )
        #expect(envelope.keyframes.count == 2)
        #expect(envelope.keyframes[0].volume == 0.0)
        #expect(envelope.keyframes[1].volume == 1.0)
        #expect(envelope.getVolumeAt(0) == 0.0)
        #expect(envelope.getVolumeAt(1_000_000) == 1.0)
        #expect(abs(envelope.getVolumeAt(500_000) - 0.5) < 0.0001)
    }

    @Test("fadeIn with custom volumes")
    func fadeInCustomVolumes() {
        let envelope = VolumeEnvelope.fadeIn(
            startId: "s",
            endId: "e",
            startTime: 0,
            endTime: 1_000_000,
            startVolume: 0.2,
            endVolume: 0.8
        )
        #expect(envelope.keyframes[0].volume == 0.2)
        #expect(envelope.keyframes[1].volume == 0.8)
    }

    @Test("fadeOut factory")
    func fadeOut() {
        let envelope = VolumeEnvelope.fadeOut(
            startId: "start",
            endId: "end",
            startTime: 0,
            endTime: 1_000_000
        )
        #expect(envelope.keyframes.count == 2)
        #expect(envelope.keyframes[0].volume == 1.0)
        #expect(envelope.keyframes[1].volume == 0.0)
        #expect(envelope.getVolumeAt(0) == 1.0)
        #expect(envelope.getVolumeAt(1_000_000) == 0.0)
        #expect(abs(envelope.getVolumeAt(500_000) - 0.5) < 0.0001)
    }

    @Test("fadeOut with custom volumes")
    func fadeOutCustomVolumes() {
        let envelope = VolumeEnvelope.fadeOut(
            startId: "s",
            endId: "e",
            startTime: 0,
            endTime: 1_000_000,
            startVolume: 0.8,
            endVolume: 0.2
        )
        #expect(envelope.keyframes[0].volume == 0.8)
        #expect(envelope.keyframes[1].volume == 0.2)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 0.0)
        let kf2 = VolumeKeyframe(id: "kf2", time: 1_000_000, volume: 1.0)
        let original = VolumeEnvelope(keyframes: [kf1, kf2])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VolumeEnvelope.self, from: data)
        #expect(decoded == original)
        #expect(decoded.keyframes.count == 2)
    }

    @Test("Equatable")
    func equatable() {
        let kf1 = VolumeKeyframe(id: "kf1", time: 0, volume: 0.5)
        let a = VolumeEnvelope(keyframes: [kf1])
        let b = VolumeEnvelope(keyframes: [kf1])
        #expect(a == b)
    }

    @Test("Empty static is truly empty")
    func emptyStatic() {
        #expect(VolumeEnvelope.empty.keyframes.isEmpty)
    }
}
