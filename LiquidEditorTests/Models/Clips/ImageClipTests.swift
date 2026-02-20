import Testing
import Foundation
@testable import LiquidEditor

@Suite("ImageClip Tests")
struct ImageClipTests {

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let clip = ImageClip(
            id: "ic-1",
            mediaAssetId: "img-asset",
            durationMicroseconds: 3_000_000
        )
        #expect(clip.id == "ic-1")
        #expect(clip.mediaAssetId == "img-asset")
        #expect(clip.durationMicroseconds == 3_000_000)
        #expect(clip.name == nil)
        #expect(clip.sourceInMicros == 0)
        #expect(clip.sourceOutMicros == 3_000_000)
    }

    @Test("creation with name")
    func creationWithName() {
        let clip = ImageClip(
            id: "ic-2",
            mediaAssetId: "img-asset",
            durationMicroseconds: 5_000_000,
            name: "Sunset Photo"
        )
        #expect(clip.name == "Sunset Photo")
    }

    // MARK: - Computed Properties

    @Test("displayName defaults to Image")
    func displayNameDefault() {
        let clip = ImageClip(mediaAssetId: "a", durationMicroseconds: 1_000_000)
        #expect(clip.displayName == "Image")
    }

    @Test("displayName uses custom name")
    func displayNameCustom() {
        let clip = ImageClip(mediaAssetId: "a", durationMicroseconds: 1_000_000, name: "My Photo")
        #expect(clip.displayName == "My Photo")
    }

    @Test("itemType is image")
    func itemType() {
        let clip = ImageClip(mediaAssetId: "a", durationMicroseconds: 1_000_000)
        #expect(clip.itemType == "image")
    }

    @Test("isMediaClip is true")
    func isMediaClip() {
        let clip = ImageClip(mediaAssetId: "a", durationMicroseconds: 1_000_000)
        #expect(clip.isMediaClip == true)
    }

    @Test("sourceRange matches duration")
    func sourceRange() {
        let clip = ImageClip(mediaAssetId: "a", durationMicroseconds: 2_000_000)
        #expect(clip.sourceRange.start == 0)
        #expect(clip.sourceRange.end == 2_000_000)
    }

    // MARK: - Copy-With

    @Test("with() preserves unchanged fields")
    func withPreserves() {
        let clip = ImageClip(id: "ic-1", mediaAssetId: "a", durationMicroseconds: 3_000_000, name: "Photo")
        let modified = clip.with(durationMicroseconds: 5_000_000)
        #expect(modified.id == "ic-1")
        #expect(modified.mediaAssetId == "a")
        #expect(modified.durationMicroseconds == 5_000_000)
        #expect(modified.name == "Photo")
    }

    @Test("with clearName sets name to nil")
    func withClearName() {
        let clip = ImageClip(id: "ic-1", mediaAssetId: "a", durationMicroseconds: 1_000_000, name: "Photo")
        let modified = clip.with(clearName: true)
        #expect(modified.name == nil)
    }

    // MARK: - withDuration

    @Test("withDuration changes duration")
    func withDuration() {
        let clip = ImageClip(mediaAssetId: "a", durationMicroseconds: 3_000_000)
        let modified = clip.withDuration(5_000_000)
        #expect(modified.durationMicroseconds == 5_000_000)
        #expect(modified.sourceOutMicros == 5_000_000)
    }

    // MARK: - Duplicate

    @Test("duplicate creates new ID")
    func duplicate() {
        let clip = ImageClip(id: "ic-1", mediaAssetId: "a", durationMicroseconds: 3_000_000, name: "Photo")
        let dupe = clip.duplicate()
        #expect(dupe.id != clip.id)
        #expect(dupe.mediaAssetId == "a")
        #expect(dupe.durationMicroseconds == 3_000_000)
        #expect(dupe.name == "Photo (copy)")
    }

    @Test("duplicate with nil name stays nil")
    func duplicateNilName() {
        let clip = ImageClip(mediaAssetId: "a", durationMicroseconds: 1_000_000)
        let dupe = clip.duplicate()
        #expect(dupe.name == nil)
    }

    // MARK: - Hashable

    @Test("hash is based on ID")
    func hashable() {
        let a = ImageClip(id: "ic-1", mediaAssetId: "a", durationMicroseconds: 1_000_000)
        let b = ImageClip(id: "ic-1", mediaAssetId: "b", durationMicroseconds: 2_000_000)
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = ImageClip(
            id: "ic-rt",
            mediaAssetId: "asset-rt",
            durationMicroseconds: 4_000_000,
            name: "Test Image"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageClip.self, from: data)
        #expect(decoded.id == "ic-rt")
        #expect(decoded.mediaAssetId == "asset-rt")
        #expect(decoded.durationMicroseconds == 4_000_000)
        #expect(decoded.name == "Test Image")
    }

    @Test("Codable round-trip without name")
    func codableNoName() throws {
        let original = ImageClip(id: "ic-nn", mediaAssetId: "a", durationMicroseconds: 1_000_000)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ImageClip.self, from: data)
        #expect(decoded.name == nil)
    }
}
