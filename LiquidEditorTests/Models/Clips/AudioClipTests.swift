import Testing
import Foundation
@testable import LiquidEditor

@Suite("AudioClip Tests")
struct AudioClipTests {

    // MARK: - Helpers

    private func makeClip(
        id: String = "ac-1",
        mediaAssetId: String = "asset-1",
        sourceIn: Int64 = 0,
        sourceOut: Int64 = 5_000_000,
        name: String? = nil,
        volume: Double = 1.0,
        isMuted: Bool = false,
        speed: Double = 1.0,
        pan: Double = 0.0
    ) -> AudioClip {
        AudioClip(
            id: id,
            mediaAssetId: mediaAssetId,
            sourceInMicros: sourceIn,
            sourceOutMicros: sourceOut,
            name: name,
            volume: volume,
            isMuted: isMuted,
            speed: speed,
            pan: pan
        )
    }

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let clip = makeClip()
        #expect(clip.id == "ac-1")
        #expect(clip.mediaAssetId == "asset-1")
        #expect(clip.sourceInMicros == 0)
        #expect(clip.sourceOutMicros == 5_000_000)
        #expect(clip.name == nil)
        #expect(clip.volume == 1.0)
        #expect(clip.isMuted == false)
        #expect(clip.fadeIn == nil)
        #expect(clip.fadeOut == nil)
        #expect(clip.effects.isEmpty)
        #expect(clip.linkedVideoClipId == nil)
        #expect(clip.speed == 1.0)
        #expect(clip.pan == 0.0)
    }

    // MARK: - Computed Properties

    @Test("durationMicroseconds at normal speed")
    func durationNormalSpeed() {
        let clip = makeClip(sourceIn: 1_000_000, sourceOut: 4_000_000)
        #expect(clip.durationMicroseconds == 3_000_000)
    }

    @Test("durationMicroseconds at 2x speed is half")
    func durationDoubleSpeed() {
        let clip = makeClip(sourceIn: 0, sourceOut: 4_000_000, speed: 2.0)
        #expect(clip.durationMicroseconds == 2_000_000)
    }

    @Test("durationMicroseconds at 0.5x speed is double")
    func durationHalfSpeed() {
        let clip = makeClip(sourceIn: 0, sourceOut: 2_000_000, speed: 0.5)
        #expect(clip.durationMicroseconds == 4_000_000)
    }

    @Test("displayName uses name if available")
    func displayNameCustom() {
        let clip = makeClip(name: "Voiceover")
        #expect(clip.displayName == "Voiceover")
    }

    @Test("displayName defaults to Audio")
    func displayNameDefault() {
        let clip = makeClip()
        #expect(clip.displayName == "Audio")
    }

    @Test("itemType is audio")
    func itemType() {
        let clip = makeClip()
        #expect(clip.itemType == "audio")
    }

    @Test("isMediaClip is true")
    func isMediaClip() {
        let clip = makeClip()
        #expect(clip.isMediaClip == true)
    }

    @Test("effectiveVolume returns 0 when muted")
    func effectiveVolumeMuted() {
        let clip = makeClip(volume: 0.8, isMuted: true)
        #expect(clip.effectiveVolume == 0.0)
    }

    @Test("effectiveVolume returns volume when not muted")
    func effectiveVolumeNotMuted() {
        let clip = makeClip(volume: 0.8)
        #expect(clip.effectiveVolume == 0.8)
    }

    @Test("hasEffects and effectCount")
    func effectsProperties() {
        let clip = makeClip()
        #expect(clip.hasEffects == false)
        #expect(clip.effectCount == 0)
    }

    @Test("hasFadeIn and hasFadeOut")
    func fadeProperties() {
        let clip = makeClip()
        #expect(clip.hasFadeIn == false)
        #expect(clip.hasFadeOut == false)
    }

    @Test("isLinked property")
    func isLinked() {
        let unlinked = makeClip()
        #expect(unlinked.isLinked == false)

        let linked = AudioClip(
            id: "ac-2", mediaAssetId: "a", sourceInMicros: 0, sourceOutMicros: 1_000_000,
            linkedVideoClipId: "vc-1"
        )
        #expect(linked.isLinked == true)
    }

    @Test("sourceRange tuple")
    func sourceRange() {
        let clip = makeClip(sourceIn: 1_000_000, sourceOut: 3_000_000)
        #expect(clip.sourceRange.start == 1_000_000)
        #expect(clip.sourceRange.end == 3_000_000)
    }

    // MARK: - Convenience Methods

    @Test("withVolume clamps to 0-2")
    func withVolume() {
        let clip = makeClip()
        #expect(clip.withVolume(1.5).volume == 1.5)
        #expect(clip.withVolume(-0.5).volume == 0.0)
        #expect(clip.withVolume(3.0).volume == 2.0)
    }

    @Test("withMuted toggles mute")
    func withMuted() {
        let clip = makeClip()
        #expect(clip.withMuted(true).isMuted == true)
        #expect(clip.withMuted(false).isMuted == false)
    }

    @Test("withSpeed clamps to 0.25-4.0")
    func withSpeed() {
        let clip = makeClip()
        #expect(clip.withSpeed(2.0).speed == 2.0)
        #expect(clip.withSpeed(0.1).speed == 0.25)
        #expect(clip.withSpeed(10.0).speed == 4.0)
    }

    @Test("withPan clamps to -1.0 to 1.0")
    func withPan() {
        let clip = makeClip()
        #expect(clip.withPan(0.5).pan == 0.5)
        #expect(clip.withPan(-2.0).pan == -1.0)
        #expect(clip.withPan(2.0).pan == 1.0)
    }

    // MARK: - Split

    @Test("split at valid offset returns two clips")
    func splitValid() {
        let clip = makeClip(sourceIn: 0, sourceOut: 2_000_000, name: "Test")
        let result = clip.splitAt(1_000_000)
        #expect(result != nil)

        let (left, right) = result!
        #expect(left.sourceInMicros == 0)
        #expect(left.sourceOutMicros == 1_000_000)
        #expect(right.sourceInMicros == 1_000_000)
        #expect(right.sourceOutMicros == 2_000_000)
        #expect(left.name == "Test (1)")
        #expect(right.name == "Test (2)")
        #expect(left.id != right.id)
        #expect(left.id != clip.id)
    }

    @Test("split at offset too close to start returns nil")
    func splitTooCloseToStart() {
        let clip = makeClip(sourceIn: 0, sourceOut: 2_000_000)
        #expect(clip.splitAt(50_000) == nil)  // < 100ms minimum
    }

    @Test("split at offset too close to end returns nil")
    func splitTooCloseToEnd() {
        let clip = makeClip(sourceIn: 0, sourceOut: 2_000_000)
        #expect(clip.splitAt(1_950_000) == nil)
    }

    // MARK: - Trim

    @Test("trimStart returns trimmed clip")
    func trimStart() {
        let clip = makeClip(sourceIn: 0, sourceOut: 3_000_000)
        let trimmed = clip.trimStart(1_000_000)
        #expect(trimmed != nil)
        #expect(trimmed!.sourceInMicros == 1_000_000)
        #expect(trimmed!.sourceOutMicros == 3_000_000)
        #expect(trimmed!.id == clip.id)  // Same ID for trim
    }

    @Test("trimStart returns nil for invalid in point")
    func trimStartInvalid() {
        let clip = makeClip(sourceIn: 0, sourceOut: 1_000_000)
        #expect(clip.trimStart(0) == nil)  // Not > sourceInMicros
        #expect(clip.trimStart(1_000_000) == nil)  // Not < sourceOutMicros
    }

    @Test("trimStart returns nil when result too short")
    func trimStartTooShort() {
        let clip = makeClip(sourceIn: 0, sourceOut: 200_000)
        #expect(clip.trimStart(150_000) == nil)  // Result < 100ms
    }

    @Test("trimEnd returns trimmed clip")
    func trimEnd() {
        let clip = makeClip(sourceIn: 0, sourceOut: 3_000_000)
        let trimmed = clip.trimEnd(2_000_000)
        #expect(trimmed != nil)
        #expect(trimmed!.sourceInMicros == 0)
        #expect(trimmed!.sourceOutMicros == 2_000_000)
    }

    @Test("trimEnd returns nil for invalid out point")
    func trimEndInvalid() {
        let clip = makeClip(sourceIn: 0, sourceOut: 1_000_000)
        #expect(clip.trimEnd(1_000_000) == nil)
        #expect(clip.trimEnd(0) == nil)
    }

    // MARK: - Duplicate

    @Test("duplicate creates new ID and appends (copy)")
    func duplicate() {
        let clip = makeClip(name: "Original")
        let dupe = clip.duplicate()
        #expect(dupe.id != clip.id)
        #expect(dupe.mediaAssetId == clip.mediaAssetId)
        #expect(dupe.name == "Original (copy)")
        #expect(dupe.sourceInMicros == clip.sourceInMicros)
        #expect(dupe.sourceOutMicros == clip.sourceOutMicros)
    }

    // MARK: - Copy-With Clear Fields

    @Test("with clearName sets name to nil")
    func withClearName() {
        let clip = makeClip(name: "Named")
        let modified = clip.with(clearName: true)
        #expect(modified.name == nil)
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves core fields")
    func codableRoundTrip() throws {
        let clip = makeClip(
            id: "ac-rt",
            mediaAssetId: "asset-rt",
            sourceIn: 500_000,
            sourceOut: 2_500_000,
            name: "Round Trip",
            volume: 0.8,
            isMuted: true,
            speed: 1.5,
            pan: -0.5
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(AudioClip.self, from: data)
        #expect(decoded.id == "ac-rt")
        #expect(decoded.mediaAssetId == "asset-rt")
        #expect(decoded.sourceInMicros == 500_000)
        #expect(decoded.sourceOutMicros == 2_500_000)
        #expect(decoded.name == "Round Trip")
        #expect(decoded.volume == 0.8)
        #expect(decoded.isMuted == true)
        #expect(decoded.speed == 1.5)
        #expect(decoded.pan == -0.5)
        #expect(decoded.itemType == "audio")
    }

    @Test("Codable decoding with missing optional fields uses defaults")
    func codableDefaults() throws {
        let json: [String: Any] = [
            "id": "ac-min",
            "mediaAssetId": "asset-min",
            "sourceInMicros": 0,
            "sourceOutMicros": 1_000_000,
            "itemType": "audio"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AudioClip.self, from: data)
        #expect(decoded.volume == 1.0)
        #expect(decoded.isMuted == false)
        #expect(decoded.speed == 1.0)
        #expect(decoded.pan == 0.0)
        #expect(decoded.effects.isEmpty)
    }

    // MARK: - Hashable

    @Test("hash is based on ID")
    func hashable() {
        let a = makeClip(id: "same-id")
        let b = AudioClip(id: "same-id", mediaAssetId: "different", sourceInMicros: 0, sourceOutMicros: 999)
        #expect(a.hashValue == b.hashValue)
    }
}
