import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

// MARK: - StickerKeyframe Tests

@Suite("StickerKeyframe Tests")
struct StickerKeyframeTests {

    @Test("creation with defaults")
    func creationDefaults() {
        let kf = StickerKeyframe(
            id: "skf-1",
            timestampMicros: 500_000,
            position: CGPoint(x: 0.5, y: 0.5)
        )
        #expect(kf.id == "skf-1")
        #expect(kf.timestampMicros == 500_000)
        #expect(kf.position == CGPoint(x: 0.5, y: 0.5))
        #expect(kf.scale == 1.0)
        #expect(kf.rotation == 0.0)
        #expect(kf.opacity == 1.0)
        #expect(kf.interpolation == .easeInOut)
        #expect(kf.bezierPoints == nil)
    }

    @Test("creation with custom values")
    func creationCustom() {
        let bp = BezierControlPoints(
            controlPoint1: CGPoint(x: 0.1, y: 0.2),
            controlPoint2: CGPoint(x: 0.8, y: 0.9)
        )
        let kf = StickerKeyframe(
            id: "skf-2",
            timestampMicros: 1_000_000,
            position: CGPoint(x: 0.2, y: 0.8),
            scale: 2.0,
            rotation: 1.57,
            opacity: 0.6,
            interpolation: .bezier,
            bezierPoints: bp
        )
        #expect(kf.scale == 2.0)
        #expect(kf.rotation == 1.57)
        #expect(kf.opacity == 0.6)
        #expect(kf.interpolation == .bezier)
        #expect(kf.bezierPoints != nil)
    }

    @Test("with() copy preserves unchanged fields")
    func withCopy() {
        let kf = StickerKeyframe(
            id: "skf-1",
            timestampMicros: 500_000,
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.5
        )
        let modified = kf.with(opacity: 0.3)
        #expect(modified.opacity == 0.3)
        #expect(modified.scale == 1.5)
        #expect(modified.id == "skf-1")
        #expect(modified.timestampMicros == 500_000)
    }

    @Test("with() can set bezierPoints to nil")
    func withSetBezierNil() {
        let bp = BezierControlPoints()
        let kf = StickerKeyframe(
            id: "skf-1",
            timestampMicros: 0,
            position: .zero,
            bezierPoints: bp
        )
        #expect(kf.bezierPoints != nil)
        let cleared = kf.with(bezierPoints: Optional<BezierControlPoints>.none)
        #expect(cleared.bezierPoints == nil)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let kf = StickerKeyframe(
            id: "skf-codec",
            timestampMicros: 750_000,
            position: CGPoint(x: 0.3, y: 0.7),
            scale: 1.8,
            rotation: 0.5,
            opacity: 0.9,
            interpolation: .cubicInOut
        )
        let data = try JSONEncoder().encode(kf)
        let decoded = try JSONDecoder().decode(StickerKeyframe.self, from: data)
        #expect(decoded.id == kf.id)
        #expect(decoded.timestampMicros == kf.timestampMicros)
        #expect(decoded.position.x == kf.position.x)
        #expect(decoded.position.y == kf.position.y)
        #expect(decoded.scale == kf.scale)
        #expect(decoded.rotation == kf.rotation)
        #expect(decoded.opacity == kf.opacity)
        #expect(decoded.interpolation == kf.interpolation)
    }

    @Test("Codable roundtrip with bezierPoints")
    func codableWithBezier() throws {
        let bp = BezierControlPoints(
            controlPoint1: CGPoint(x: 0.2, y: 0.3),
            controlPoint2: CGPoint(x: 0.7, y: 0.8)
        )
        let kf = StickerKeyframe(
            id: "skf-bp",
            timestampMicros: 0,
            position: CGPoint(x: 0.5, y: 0.5),
            interpolation: .bezier,
            bezierPoints: bp
        )
        let data = try JSONEncoder().encode(kf)
        let decoded = try JSONDecoder().decode(StickerKeyframe.self, from: data)
        #expect(decoded.bezierPoints != nil)
        #expect(decoded.bezierPoints!.controlPoint1.x == 0.2)
        #expect(decoded.bezierPoints!.controlPoint2.y == 0.8)
    }
}

// MARK: - StickerCategory Tests

@Suite("StickerCategory Tests")
struct StickerCategoryTests {

    @Test("creation")
    func creation() {
        let cat = StickerCategory(
            id: "custom",
            name: "Custom",
            iconName: "star.fill",
            sortOrder: 10,
            isBuiltIn: false
        )
        #expect(cat.id == "custom")
        #expect(cat.name == "Custom")
        #expect(cat.iconName == "star.fill")
        #expect(cat.sortOrder == 10)
        #expect(cat.isBuiltIn == false)
    }

    @Test("builtInCategories has 8 entries")
    func builtInCount() {
        #expect(StickerCategory.builtInCategories.count == 8)
    }

    @Test("builtInCategories are sorted by sortOrder")
    func builtInSorted() {
        let categories = StickerCategory.builtInCategories
        for i in 0..<(categories.count - 1) {
            #expect(categories[i].sortOrder < categories[i + 1].sortOrder)
        }
    }

    @Test("builtInCategories IDs are unique")
    func builtInUniqueIds() {
        let ids = Set(StickerCategory.builtInCategories.map { $0.id })
        #expect(ids.count == StickerCategory.builtInCategories.count)
    }

    @Test("Equatable is identity-based")
    func equatableById() {
        let a = StickerCategory(id: "same", name: "A", iconName: "a")
        let b = StickerCategory(id: "same", name: "B", iconName: "b")
        #expect(a == b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let cat = StickerCategory(
            id: "test-cat",
            name: "Test Category",
            iconName: "circle",
            sortOrder: 5,
            isBuiltIn: false
        )
        let data = try JSONEncoder().encode(cat)
        let decoded = try JSONDecoder().decode(StickerCategory.self, from: data)
        #expect(decoded.id == cat.id)
        #expect(decoded.name == cat.name)
        #expect(decoded.iconName == cat.iconName)
        #expect(decoded.sortOrder == cat.sortOrder)
        #expect(decoded.isBuiltIn == cat.isBuiltIn)
    }
}

// MARK: - StickerAssetType Tests

@Suite("StickerAssetType Tests")
struct StickerAssetTypeTests {

    @Test("all cases")
    func allCases() {
        #expect(StickerAssetType.allCases.count == 3)
        #expect(StickerAssetType.staticImage.rawValue == "staticImage")
        #expect(StickerAssetType.lottie.rawValue == "lottie")
        #expect(StickerAssetType.gif.rawValue == "gif")
    }
}

// MARK: - StickerAsset Tests

@Suite("StickerAsset Tests")
struct StickerAssetTests {

    private func makeAsset() -> StickerAsset {
        StickerAsset(
            id: "sa-1",
            name: "Star",
            type: .staticImage,
            categoryId: "shapes",
            assetPath: "shapes/star.png"
        )
    }

    @Test("creation with defaults")
    func creationDefaults() {
        let asset = makeAsset()
        #expect(asset.id == "sa-1")
        #expect(asset.name == "Star")
        #expect(asset.type == .staticImage)
        #expect(asset.categoryId == "shapes")
        #expect(asset.assetPath == "shapes/star.png")
        #expect(asset.isBuiltIn == true)
        #expect(asset.intrinsicWidth == 120.0)
        #expect(asset.intrinsicHeight == 120.0)
        #expect(asset.animationDurationMs == nil)
        #expect(asset.frameCount == nil)
        #expect(asset.keywords.isEmpty)
        #expect(asset.thumbnailPath == nil)
    }

    @Test("isAnimated computed property")
    func isAnimated() {
        let staticAsset = makeAsset()
        #expect(!staticAsset.isAnimated)

        let lottie = StickerAsset(id: "sa-l", name: "Anim", type: .lottie, categoryId: "animated", assetPath: "anim.json")
        #expect(lottie.isAnimated)

        let gif = StickerAsset(id: "sa-g", name: "Gif", type: .gif, categoryId: "animated", assetPath: "anim.gif")
        #expect(gif.isAnimated)
    }

    @Test("with() copy")
    func withCopy() {
        let asset = makeAsset()
        let modified = asset.with(name: "New Star", intrinsicWidth: 200.0)
        #expect(modified.name == "New Star")
        #expect(modified.intrinsicWidth == 200.0)
        #expect(modified.id == asset.id)
    }

    @Test("with() can set optional to nil")
    func withSetNil() {
        let asset = StickerAsset(
            id: "sa-n",
            name: "With Duration",
            type: .lottie,
            categoryId: "animated",
            assetPath: "a.json",
            animationDurationMs: 1000,
            frameCount: 30
        )
        #expect(asset.animationDurationMs == 1000)
        let cleared = asset.with(animationDurationMs: Optional<Int>.none)
        #expect(cleared.animationDurationMs == nil)
    }

    @Test("Equatable is identity-based")
    func equatableById() {
        let a = StickerAsset(id: "same", name: "A", type: .staticImage, categoryId: "c", assetPath: "a.png")
        let b = StickerAsset(id: "same", name: "B", type: .gif, categoryId: "d", assetPath: "b.gif")
        #expect(a == b)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let asset = StickerAsset(
            id: "sa-codec",
            name: "Fire",
            type: .lottie,
            categoryId: "emoji",
            assetPath: "emoji/fire.json",
            isBuiltIn: false,
            intrinsicWidth: 150.0,
            intrinsicHeight: 150.0,
            animationDurationMs: 2000,
            frameCount: 60,
            keywords: ["fire", "hot", "flame"],
            thumbnailPath: "thumb/fire.png"
        )
        let data = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(StickerAsset.self, from: data)
        #expect(decoded.id == asset.id)
        #expect(decoded.name == asset.name)
        #expect(decoded.type == asset.type)
        #expect(decoded.categoryId == asset.categoryId)
        #expect(decoded.assetPath == asset.assetPath)
        #expect(decoded.isBuiltIn == asset.isBuiltIn)
        #expect(decoded.animationDurationMs == asset.animationDurationMs)
        #expect(decoded.frameCount == asset.frameCount)
        #expect(decoded.keywords == asset.keywords)
        #expect(decoded.thumbnailPath == asset.thumbnailPath)
    }
}

// MARK: - StickerClip Model Tests

@Suite("StickerClip Model Tests")
struct StickerClipModelTests {

    private func makeClip() -> StickerClip {
        StickerClip(
            id: "sc-1",
            durationMicroseconds: 2_000_000,
            stickerAssetId: "asset-star",
            name: "Star Sticker"
        )
    }

    @Test("creation with defaults")
    func creationDefaults() {
        let clip = makeClip()
        #expect(clip.id == "sc-1")
        #expect(clip.durationMicroseconds == 2_000_000)
        #expect(clip.stickerAssetId == "asset-star")
        #expect(clip.positionX == 0.5)
        #expect(clip.positionY == 0.5)
        #expect(clip.rotation == 0.0)
        #expect(clip.scale == 1.0)
        #expect(clip.opacity == 1.0)
        #expect(clip.isFlippedHorizontally == false)
        #expect(clip.isFlippedVertically == false)
        #expect(clip.keyframes.isEmpty)
        #expect(clip.tintColorValue == nil)
        #expect(clip.animationSpeed == 1.0)
        #expect(clip.animationLoops == true)
        #expect(clip.itemType == "sticker")
        #expect(clip.isGeneratorClip == true)
    }

    @Test("displayName logic")
    func displayName() {
        let named = makeClip()
        #expect(named.displayName == "Star Sticker")

        let unnamed = StickerClip(id: "sc-2", durationMicroseconds: 1_000_000, stickerAssetId: "a")
        #expect(unnamed.displayName == "Sticker")
    }

    @Test("splitAt valid offset")
    func splitAtValid() {
        let clip = makeClip()
        let result = clip.splitAt(1_000_000)
        #expect(result != nil)
        let (left, right) = result!
        #expect(left.durationMicroseconds == 1_000_000)
        #expect(right.durationMicroseconds == 1_000_000)
        #expect(left.stickerAssetId == clip.stickerAssetId)
        #expect(right.stickerAssetId == clip.stickerAssetId)
        #expect(left.name == "Star Sticker (1)")
        #expect(right.name == "Star Sticker (2)")
        #expect(left.id != right.id)
    }

    @Test("splitAt too close to edges returns nil")
    func splitAtEdges() {
        let clip = makeClip()
        #expect(clip.splitAt(50_000) == nil)
        #expect(clip.splitAt(1_950_000) == nil)
    }

    @Test("splitAt partitions keyframes and retimes right half")
    func splitAtKeyframes() {
        let kf1 = StickerKeyframe(id: "sk1", timestampMicros: 300_000, position: CGPoint(x: 0.1, y: 0.1))
        let kf2 = StickerKeyframe(id: "sk2", timestampMicros: 1_200_000, position: CGPoint(x: 0.9, y: 0.9))
        let clip = StickerClip(
            id: "sc-kf",
            durationMicroseconds: 2_000_000,
            stickerAssetId: "a",
            keyframes: [kf1, kf2]
        )
        let result = clip.splitAt(1_000_000)!
        #expect(result.left.keyframes.count == 1)
        #expect(result.left.keyframes[0].id == "sk1")
        #expect(result.right.keyframes.count == 1)
        #expect(result.right.keyframes[0].id == "sk2")
        #expect(result.right.keyframes[0].timestampMicros == 200_000)
    }

    @Test("duplicate creates new ID")
    func duplicate() {
        let clip = makeClip()
        let dup = clip.duplicate()
        #expect(dup.id != clip.id)
        #expect(dup.stickerAssetId == clip.stickerAssetId)
        #expect(dup.durationMicroseconds == clip.durationMicroseconds)
        #expect(dup.name == "Star Sticker (copy)")
    }

    @Test("with() copy")
    func withCopy() {
        let clip = makeClip()
        let modified = clip.with(opacity: 0.5, isFlippedHorizontally: true)
        #expect(modified.opacity == 0.5)
        #expect(modified.isFlippedHorizontally == true)
        #expect(modified.id == clip.id)
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let clip = StickerClip(
            id: "sc-codec",
            durationMicroseconds: 3_000_000,
            stickerAssetId: "asset-fire",
            positionX: 0.3,
            positionY: 0.7,
            rotation: 0.785,
            scale: 1.5,
            opacity: 0.8,
            isFlippedHorizontally: true,
            isFlippedVertically: false,
            keyframes: [
                StickerKeyframe(id: "sk1", timestampMicros: 0, position: CGPoint(x: 0.5, y: 0.5))
            ],
            name: "Fire",
            tintColorValue: 0xFFFF0000,
            animationSpeed: 2.0,
            animationLoops: false
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(StickerClip.self, from: data)
        #expect(decoded.id == clip.id)
        #expect(decoded.durationMicroseconds == clip.durationMicroseconds)
        #expect(decoded.stickerAssetId == clip.stickerAssetId)
        #expect(decoded.positionX == clip.positionX)
        #expect(decoded.positionY == clip.positionY)
        #expect(decoded.rotation == clip.rotation)
        #expect(decoded.scale == clip.scale)
        #expect(decoded.opacity == clip.opacity)
        #expect(decoded.isFlippedHorizontally == true)
        #expect(decoded.isFlippedVertically == false)
        #expect(decoded.keyframes.count == 1)
        #expect(decoded.name == "Fire")
        #expect(decoded.tintColorValue == 0xFFFF0000)
        #expect(decoded.animationSpeed == 2.0)
        #expect(decoded.animationLoops == false)
    }
}
