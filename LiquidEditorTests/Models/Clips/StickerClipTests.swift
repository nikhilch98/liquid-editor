import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("StickerClip Tests")
struct StickerClipTests {

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let clip = StickerClip(
            id: "sc-1",
            durationMicroseconds: 2_000_000,
            stickerAssetId: "sticker-heart"
        )
        #expect(clip.id == "sc-1")
        #expect(clip.durationMicroseconds == 2_000_000)
        #expect(clip.stickerAssetId == "sticker-heart")
        #expect(clip.positionX == 0.5)
        #expect(clip.positionY == 0.5)
        #expect(clip.rotation == 0.0)
        #expect(clip.scale == 1.0)
        #expect(clip.opacity == 1.0)
        #expect(clip.isFlippedHorizontally == false)
        #expect(clip.isFlippedVertically == false)
        #expect(clip.keyframes.isEmpty)
        #expect(clip.name == nil)
        #expect(clip.tintColorValue == nil)
        #expect(clip.animationSpeed == 1.0)
        #expect(clip.animationLoops == true)
    }

    // MARK: - Computed Properties

    @Test("displayName defaults to Sticker")
    func displayNameDefault() {
        let clip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s")
        #expect(clip.displayName == "Sticker")
    }

    @Test("displayName uses custom name")
    func displayNameCustom() {
        let clip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s", name: "My Sticker")
        #expect(clip.displayName == "My Sticker")
    }

    @Test("itemType is sticker")
    func itemType() {
        let clip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s")
        #expect(clip.itemType == "sticker")
    }

    @Test("isGeneratorClip is true")
    func isGeneratorClip() {
        let clip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s")
        #expect(clip.isGeneratorClip == true)
    }

    @Test("position as CGPoint")
    func position() {
        let clip = StickerClip(
            durationMicroseconds: 1_000_000,
            stickerAssetId: "s",
            positionX: 0.3,
            positionY: 0.7
        )
        #expect(clip.position == CGPoint(x: 0.3, y: 0.7))
    }

    @Test("shortLabel truncates long names")
    func shortLabel() {
        let shortClip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s", name: "Short")
        #expect(shortClip.shortLabel == "Short")

        let longName = String(repeating: "A", count: 40)
        let longClip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s", name: longName)
        #expect(longClip.shortLabel.count == 30)
        #expect(longClip.shortLabel.hasSuffix("..."))
    }

    @Test("hasKeyframes and keyframeCount")
    func keyframeProperties() {
        let noKf = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s")
        #expect(noKf.hasKeyframes == false)
        #expect(noKf.keyframeCount == 0)

        let kf = StickerKeyframe(
            id: "kf-1", timestampMicros: 500_000, position: CGPoint(x: 0.5, y: 0.5)
        )
        let withKf = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s", keyframes: [kf])
        #expect(withKf.hasKeyframes == true)
        #expect(withKf.keyframeCount == 1)
    }

    // MARK: - Split

    @Test("split at valid offset returns two clips")
    func splitValid() {
        let clip = StickerClip(
            id: "sc-1",
            durationMicroseconds: 2_000_000,
            stickerAssetId: "sticker",
            name: "Test"
        )
        let result = clip.splitAt(1_000_000)
        #expect(result != nil)

        let (left, right) = result!
        #expect(left.durationMicroseconds == 1_000_000)
        #expect(right.durationMicroseconds == 1_000_000)
        #expect(left.stickerAssetId == "sticker")
        #expect(right.stickerAssetId == "sticker")
        #expect(left.name == "Test (1)")
        #expect(right.name == "Test (2)")
        #expect(left.id != right.id)
    }

    @Test("split at invalid offset returns nil")
    func splitInvalid() {
        let clip = StickerClip(durationMicroseconds: 200_000, stickerAssetId: "s")
        #expect(clip.splitAt(50_000) == nil)  // Left too short
        #expect(clip.splitAt(150_000) == nil)  // Right too short
    }

    // MARK: - Copy-With

    @Test("with() preserves unchanged and applies overrides")
    func withCopy() {
        let clip = StickerClip(
            id: "sc-1",
            durationMicroseconds: 2_000_000,
            stickerAssetId: "s",
            positionX: 0.5,
            positionY: 0.5,
            scale: 1.0
        )
        let modified = clip.with(scale: 2.0, opacity: 0.5)
        #expect(modified.scale == 2.0)
        #expect(modified.opacity == 0.5)
        #expect(modified.positionX == 0.5)
        #expect(modified.id == "sc-1")
    }

    @Test("with clearName sets name to nil")
    func withClearName() {
        let clip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s", name: "Named")
        let modified = clip.with(clearName: true)
        #expect(modified.name == nil)
    }

    @Test("with clearTintColorValue sets tint to nil")
    func withClearTint() {
        let clip = StickerClip(durationMicroseconds: 1_000_000, stickerAssetId: "s", tintColorValue: 0xFF0000FF)
        let modified = clip.with(clearTintColorValue: true)
        #expect(modified.tintColorValue == nil)
    }

    // MARK: - Duplicate

    @Test("duplicate creates new ID")
    func duplicate() {
        let clip = StickerClip(
            id: "sc-1", durationMicroseconds: 1_000_000,
            stickerAssetId: "sticker", name: "Original"
        )
        let dupe = clip.duplicate()
        #expect(dupe.id != clip.id)
        #expect(dupe.stickerAssetId == "sticker")
        #expect(dupe.name == "Original (copy)")
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves fields")
    func codableRoundTrip() throws {
        let clip = StickerClip(
            id: "sc-rt",
            durationMicroseconds: 3_000_000,
            stickerAssetId: "sticker-star",
            positionX: 0.3,
            positionY: 0.7,
            rotation: 1.57,
            scale: 2.0,
            opacity: 0.8,
            isFlippedHorizontally: true,
            name: "Star",
            tintColorValue: 0xFFFF0000,
            animationSpeed: 0.5,
            animationLoops: false
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(StickerClip.self, from: data)
        #expect(decoded.id == "sc-rt")
        #expect(decoded.stickerAssetId == "sticker-star")
        #expect(decoded.positionX == 0.3)
        #expect(decoded.positionY == 0.7)
        #expect(abs(decoded.rotation - 1.57) < 0.001)
        #expect(decoded.scale == 2.0)
        #expect(decoded.opacity == 0.8)
        #expect(decoded.isFlippedHorizontally == true)
        #expect(decoded.name == "Star")
        #expect(decoded.tintColorValue == 0xFFFF0000)
        #expect(decoded.animationSpeed == 0.5)
        #expect(decoded.animationLoops == false)
    }

    // MARK: - Hashable

    @Test("hash is based on ID")
    func hashable() {
        let a = StickerClip(id: "sc-1", durationMicroseconds: 1_000_000, stickerAssetId: "s1")
        let b = StickerClip(id: "sc-1", durationMicroseconds: 2_000_000, stickerAssetId: "s2")
        #expect(a.hashValue == b.hashValue)
    }
}
