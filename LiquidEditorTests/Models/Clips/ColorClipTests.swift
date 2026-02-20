import Testing
import Foundation
@testable import LiquidEditor

@Suite("ColorClip Tests")
struct ColorClipTests {

    // MARK: - Creation

    @Test("Creation with all parameters")
    func creation() {
        let clip = ColorClip(
            id: "color-1",
            durationMicroseconds: 2_000_000,
            colorValue: 0xFF00FF00,
            name: "Green"
        )
        #expect(clip.id == "color-1")
        #expect(clip.durationMicroseconds == 2_000_000)
        #expect(clip.colorValue == 0xFF00FF00)
        #expect(clip.name == "Green")
    }

    @Test("Creation without name defaults to nil")
    func creationNoName() {
        let clip = ColorClip(
            id: "c1",
            durationMicroseconds: 1_000_000,
            colorValue: 0xFF000000
        )
        #expect(clip.name == nil)
    }

    @Test("displayName returns name when provided")
    func displayNameWithName() {
        let clip = ColorClip(id: "c", durationMicroseconds: 100, colorValue: 0, name: "Custom")
        #expect(clip.displayName == "Custom")
    }

    @Test("displayName returns 'Color' when name is nil")
    func displayNameDefault() {
        let clip = ColorClip(id: "c", durationMicroseconds: 100, colorValue: 0)
        #expect(clip.displayName == "Color")
    }

    @Test("itemType is .color")
    func itemType() {
        let clip = ColorClip(id: "c", durationMicroseconds: 100, colorValue: 0)
        #expect(clip.itemType == .color)
    }

    @Test("isGeneratorClip is true")
    func isGeneratorClip() {
        let clip = ColorClip(id: "c", durationMicroseconds: 100, colorValue: 0)
        #expect(clip.isGeneratorClip == true)
    }

    @Test("isMediaClip is false")
    func isMediaClip() {
        let clip = ColorClip(id: "c", durationMicroseconds: 100, colorValue: 0)
        #expect(clip.isMediaClip == false)
    }

    // MARK: - Factory Methods

    @Test("black factory creates opaque black clip")
    func blackFactory() {
        let clip = ColorClip.black(id: "b", durationMicroseconds: 1_000_000)
        #expect(clip.colorValue == 0xFF00_0000)
        #expect(clip.name == "Black")
        #expect(clip.isBlack == true)
        #expect(clip.isWhite == false)
        #expect(clip.isTransparent == false)
    }

    @Test("white factory creates opaque white clip")
    func whiteFactory() {
        let clip = ColorClip.white(id: "w", durationMicroseconds: 1_000_000)
        #expect(clip.colorValue == 0xFFFF_FFFF)
        #expect(clip.name == "White")
        #expect(clip.isWhite == true)
        #expect(clip.isBlack == false)
        #expect(clip.isTransparent == false)
    }

    @Test("transparent factory creates fully transparent clip")
    func transparentFactory() {
        let clip = ColorClip.transparent(id: "t", durationMicroseconds: 1_000_000)
        #expect(clip.colorValue == 0x0000_0000)
        #expect(clip.name == "Transparent")
        #expect(clip.isTransparent == true)
        #expect(clip.isBlack == false)
        #expect(clip.isWhite == false)
    }

    @Test("fromColor factory creates clip from ARGBColor")
    func fromColorFactory() {
        let color = ARGBColor(alpha: 1.0, red: 1.0, green: 0.0, blue: 0.0)
        let clip = ColorClip.fromColor(
            id: "red",
            durationMicroseconds: 500_000,
            color: color,
            name: "Red"
        )
        #expect(clip.name == "Red")
        #expect(clip.durationMicroseconds == 500_000)
        // Red = 0xFFFF0000
        #expect(clip.colorValue == color.toARGB32)
    }

    @Test("fromColor without name")
    func fromColorNoName() {
        let clip = ColorClip.fromColor(
            id: "c",
            durationMicroseconds: 100,
            color: .black
        )
        #expect(clip.name == nil)
    }

    // MARK: - Color Queries

    @Test("color computed property returns correct ARGBColor")
    func colorProperty() {
        let clip = ColorClip.black(id: "b", durationMicroseconds: 100)
        let color = clip.color
        #expect(color.alpha == 1.0)
        #expect(color.red == 0.0)
        #expect(color.green == 0.0)
        #expect(color.blue == 0.0)
    }

    @Test("isBlack detects opaque black")
    func isBlack() {
        let black = ColorClip(id: "b", durationMicroseconds: 100, colorValue: 0xFF00_0000)
        #expect(black.isBlack == true)

        let notBlack = ColorClip(id: "b", durationMicroseconds: 100, colorValue: 0xFF00_0001)
        #expect(notBlack.isBlack == false)
    }

    @Test("isWhite detects opaque white")
    func isWhite() {
        let white = ColorClip(id: "w", durationMicroseconds: 100, colorValue: 0xFFFF_FFFF)
        #expect(white.isWhite == true)

        let notWhite = ColorClip(id: "w", durationMicroseconds: 100, colorValue: 0xFFFFFFFE)
        #expect(notWhite.isWhite == false)
    }

    @Test("isTransparent checks alpha channel is zero")
    func isTransparent() {
        let transparent = ColorClip(id: "t", durationMicroseconds: 100, colorValue: 0x00FF0000)
        #expect(transparent.isTransparent == true)

        // Semi-transparent (alpha = 0x80)
        let semi = ColorClip(id: "s", durationMicroseconds: 100, colorValue: 0x80FF0000)
        #expect(semi.isTransparent == false)

        // Fully opaque
        let opaque = ColorClip(id: "o", durationMicroseconds: 100, colorValue: 0xFFFF0000)
        #expect(opaque.isTransparent == false)
    }

    // MARK: - Modification

    @Test("withDuration changes duration, preserves other fields")
    func withDuration() {
        let clip = ColorClip(id: "c1", durationMicroseconds: 1_000_000, colorValue: 0xFF0000FF, name: "Blue")
        let updated = clip.withDuration(2_000_000)
        #expect(updated.id == "c1")
        #expect(updated.durationMicroseconds == 2_000_000)
        #expect(updated.colorValue == 0xFF0000FF)
        #expect(updated.name == "Blue")
    }

    @Test("withColor changes color, preserves other fields")
    func withColor() {
        let clip = ColorClip(id: "c1", durationMicroseconds: 1_000_000, colorValue: 0xFF0000FF, name: "Blue")
        let updated = clip.withColor(0xFFFF0000)
        #expect(updated.id == "c1")
        #expect(updated.durationMicroseconds == 1_000_000)
        #expect(updated.colorValue == 0xFFFF0000)
        #expect(updated.name == "Blue")
    }

    @Test("withARGBColor changes color from ARGBColor")
    func withARGBColor() {
        let clip = ColorClip.black(id: "c", durationMicroseconds: 100)
        let updated = clip.withARGBColor(.white)
        #expect(updated.colorValue == ARGBColor.white.toARGB32)
    }

    // MARK: - with() Copy

    @Test("with() preserves all values when no changes")
    func withNoChanges() {
        let clip = ColorClip(id: "c1", durationMicroseconds: 500_000, colorValue: 0xFF00FF00, name: "Green")
        let copy = clip.with()
        #expect(copy == clip)
    }

    @Test("with() changes specified fields")
    func withPartialChanges() {
        let clip = ColorClip(id: "c1", durationMicroseconds: 500_000, colorValue: 0xFF00FF00, name: "Green")
        let updated = clip.with(colorValue: 0xFF0000FF, name: "Blue")
        #expect(updated.id == "c1")
        #expect(updated.durationMicroseconds == 500_000)
        #expect(updated.colorValue == 0xFF0000FF)
        #expect(updated.name == "Blue")
    }

    @Test("with() clearName sets name to nil")
    func withClearName() {
        let clip = ColorClip(id: "c1", durationMicroseconds: 500_000, colorValue: 0, name: "Named")
        let cleared = clip.with(clearName: true)
        #expect(cleared.name == nil)
    }

    @Test("with() clearName overrides new name value")
    func withClearNameOverrides() {
        let clip = ColorClip(id: "c1", durationMicroseconds: 100, colorValue: 0, name: "Old")
        let result = clip.with(name: "New", clearName: true)
        #expect(result.name == nil)
    }

    // MARK: - duplicate

    @Test("duplicate creates new id, same color and duration")
    func duplicate() {
        let clip = ColorClip(id: "orig", durationMicroseconds: 1_000_000, colorValue: 0xFF00FF00, name: "Green")
        let dup = clip.duplicate()
        #expect(dup.id != "orig")
        #expect(!dup.id.isEmpty)
        #expect(dup.durationMicroseconds == 1_000_000)
        #expect(dup.colorValue == 0xFF00FF00)
        #expect(dup.name == "Green (copy)")
    }

    @Test("duplicate with nil name keeps nil")
    func duplicateNilName() {
        let clip = ColorClip(id: "orig", durationMicroseconds: 100, colorValue: 0)
        let dup = clip.duplicate()
        #expect(dup.name == nil)
    }

    // MARK: - splitAt

    @Test("splitAt produces correct left and right")
    func splitAtBasic() {
        let clip = ColorClip(id: "c", durationMicroseconds: 1_000_000, colorValue: 0xFF00FF00, name: "Green")
        let result = clip.splitAt(400_000)
        #expect(result != nil)

        let left = result!.left
        let right = result!.right

        #expect(left.durationMicroseconds == 400_000)
        #expect(right.durationMicroseconds == 600_000)
        #expect(left.colorValue == 0xFF00FF00)
        #expect(right.colorValue == 0xFF00FF00)
        #expect(left.name == "Green (1)")
        #expect(right.name == "Green (2)")
        #expect(left.id != clip.id)
        #expect(right.id != clip.id)
        #expect(left.id != right.id)
    }

    @Test("splitAt with nil name")
    func splitAtNilName() {
        let clip = ColorClip(id: "c", durationMicroseconds: 500_000, colorValue: 0xFF000000)
        let result = clip.splitAt(200_000)!
        #expect(result.left.name == nil)
        #expect(result.right.name == nil)
    }

    @Test("splitAt returns nil when left too small")
    func splitAtLeftTooSmall() {
        let clip = ColorClip(id: "c", durationMicroseconds: 500_000, colorValue: 0)
        let result = clip.splitAt(50_000)
        #expect(result == nil)
    }

    @Test("splitAt returns nil when right too small")
    func splitAtRightTooSmall() {
        let clip = ColorClip(id: "c", durationMicroseconds: 500_000, colorValue: 0)
        let result = clip.splitAt(450_000) // right = 50_000 < 100_000
        #expect(result == nil)
    }

    @Test("splitAt at exact minimum boundary")
    func splitAtMinimumBoundary() {
        let clip = ColorClip(id: "c", durationMicroseconds: 200_000, colorValue: 0)
        let result = clip.splitAt(100_000)
        #expect(result != nil)
        #expect(result!.left.durationMicroseconds == 100_000)
        #expect(result!.right.durationMicroseconds == 100_000)
    }

    @Test("splitAt preserves total duration")
    func splitAtTotalDuration() {
        let clip = ColorClip(id: "c", durationMicroseconds: 1_500_000, colorValue: 0xFF0000FF)
        let result = clip.splitAt(600_000)!
        let total = result.left.durationMicroseconds + result.right.durationMicroseconds
        #expect(total == 1_500_000)
    }

    @Test("splitAt at zero returns nil")
    func splitAtZero() {
        let clip = ColorClip(id: "c", durationMicroseconds: 500_000, colorValue: 0)
        #expect(clip.splitAt(0) == nil)
    }

    @Test("splitAt at full duration returns nil")
    func splitAtFullDuration() {
        let clip = ColorClip(id: "c", durationMicroseconds: 500_000, colorValue: 0)
        #expect(clip.splitAt(500_000) == nil)
    }

    // MARK: - Codable Roundtrip

    @Test("Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let clip = ColorClip(
            id: "codec-color",
            durationMicroseconds: 2_500_000,
            colorValue: 0xFF00FF00,
            name: "Green"
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(ColorClip.self, from: data)
        #expect(decoded == clip)
    }

    @Test("Codable roundtrip with nil name")
    func codableRoundtripNilName() throws {
        let clip = ColorClip(id: "no-name", durationMicroseconds: 100, colorValue: 0xFF000000)
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(ColorClip.self, from: data)
        #expect(decoded.name == nil)
        #expect(decoded == clip)
    }

    @Test("JSON uses correct coding keys")
    func jsonCodingKeys() throws {
        let clip = ColorClip(id: "key-test", durationMicroseconds: 300_000, colorValue: 0xFFAABBCC, name: "Custom")
        let data = try JSONEncoder().encode(clip)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["itemType"] as? String == "color")
        #expect(json["id"] as? String == "key-test")
        #expect(json["durationMicros"] as? Int64 == 300_000)
        #expect(json["colorValue"] as? Int == 0xFFAABBCC)
        #expect(json["name"] as? String == "Custom")
        // Should not have raw property name
        #expect(json["durationMicroseconds"] == nil)
    }

    @Test("Decode from Dart-style JSON")
    func decodeDartJson() throws {
        let jsonString = """
        {
            "itemType": "color",
            "id": "dart-color",
            "durationMicros": 500000,
            "colorValue": 4278190080,
            "name": "Black"
        }
        """
        let data = jsonString.data(using: .utf8)!
        let clip = try JSONDecoder().decode(ColorClip.self, from: data)
        #expect(clip.id == "dart-color")
        #expect(clip.durationMicroseconds == 500_000)
        #expect(clip.colorValue == 0xFF000000)
        #expect(clip.name == "Black")
    }

    @Test("Decode from JSON without optional name")
    func decodeDartJsonNoName() throws {
        let jsonString = """
        {
            "itemType": "color",
            "id": "no-name",
            "durationMicros": 100000,
            "colorValue": 0
        }
        """
        let data = jsonString.data(using: .utf8)!
        let clip = try JSONDecoder().decode(ColorClip.self, from: data)
        #expect(clip.name == nil)
    }

    // MARK: - Equatable & Hashable

    @Test("Equal clips are equal")
    func equality() {
        let a = ColorClip(id: "c1", durationMicroseconds: 500_000, colorValue: 0xFF00FF00, name: "Green")
        let b = ColorClip(id: "c1", durationMicroseconds: 500_000, colorValue: 0xFF00FF00, name: "Green")
        #expect(a == b)
    }

    @Test("Different clips are not equal")
    func inequality() {
        let a = ColorClip(id: "c1", durationMicroseconds: 500_000, colorValue: 0xFF00FF00)
        let b = ColorClip(id: "c2", durationMicroseconds: 500_000, colorValue: 0xFF00FF00)
        #expect(a != b)

        let c = ColorClip(id: "c1", durationMicroseconds: 600_000, colorValue: 0xFF00FF00)
        #expect(a != c)

        let d = ColorClip(id: "c1", durationMicroseconds: 500_000, colorValue: 0xFF0000FF)
        #expect(a != d)
    }

    @Test("Clips can be used in Set")
    func setUsage() {
        let a = ColorClip(id: "c1", durationMicroseconds: 100, colorValue: 0)
        let b = ColorClip(id: "c2", durationMicroseconds: 100, colorValue: 0)
        let c = ColorClip(id: "c1", durationMicroseconds: 100, colorValue: 0)
        let clipSet: Set<ColorClip> = [a, b, c]
        #expect(clipSet.count == 2)
    }

    // MARK: - Sendable

    @Test("Sendable conformance")
    func sendable() async {
        let clip = ColorClip.black(id: "s", durationMicroseconds: 1_000_000)
        let result = await Task.detached { clip.colorValue }.value
        #expect(result == 0xFF00_0000)
    }

    // MARK: - ARGBColor Roundtrip through ColorClip

    @Test("ARGBColor roundtrip through factory and color property")
    func argbRoundtrip() {
        let original = ARGBColor(alpha: 0.5, red: 0.25, green: 0.75, blue: 1.0)
        let clip = ColorClip.fromColor(id: "rt", durationMicroseconds: 100, color: original)
        let recovered = clip.color
        // Allow for 8-bit quantization (1/255 = ~0.004)
        #expect(abs(recovered.alpha - original.alpha) < 0.005)
        #expect(abs(recovered.red - original.red) < 0.005)
        #expect(abs(recovered.green - original.green) < 0.005)
        #expect(abs(recovered.blue - original.blue) < 0.005)
    }
}
