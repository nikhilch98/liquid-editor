import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("TextClip Tests")
struct TextClipTests {

    // MARK: - Helpers

    private func makeStyle(fontSize: Double = 48.0) -> TextOverlayStyle {
        TextOverlayStyle(fontSize: fontSize)
    }

    private func makeClip(
        id: String = "tc-1",
        duration: Int64 = 3_000_000,
        text: String = "Hello World",
        name: String? = nil,
        isSubtitle: Bool = false
    ) -> TextClip {
        TextClip(
            id: id,
            durationMicroseconds: duration,
            text: text,
            style: makeStyle(),
            name: name,
            isSubtitle: isSubtitle
        )
    }

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let clip = makeClip()
        #expect(clip.id == "tc-1")
        #expect(clip.durationMicroseconds == 3_000_000)
        #expect(clip.text == "Hello World")
        #expect(clip.positionX == 0.5)
        #expect(clip.positionY == 0.5)
        #expect(clip.rotation == 0.0)
        #expect(clip.scale == 1.0)
        #expect(clip.opacity == 1.0)
        #expect(clip.enterAnimation == nil)
        #expect(clip.exitAnimation == nil)
        #expect(clip.sustainAnimation == nil)
        #expect(clip.enterDurationMicros == 300_000)
        #expect(clip.exitDurationMicros == 300_000)
        #expect(clip.keyframes.isEmpty)
        #expect(clip.templateId == nil)
        #expect(clip.name == nil)
        #expect(clip.isSubtitle == false)
        #expect(clip.textAlign == .center)
        #expect(clip.maxWidthFraction == 0.9)
    }

    // MARK: - Computed Properties

    @Test("displayName returns Text by default")
    func displayNameDefault() {
        let clip = makeClip()
        #expect(clip.displayName == "Text")
    }

    @Test("displayName returns Subtitle for subtitle clips")
    func displayNameSubtitle() {
        let clip = makeClip(isSubtitle: true)
        #expect(clip.displayName == "Subtitle")
    }

    @Test("displayName returns custom name when set")
    func displayNameCustom() {
        let clip = makeClip(name: "Title Card")
        #expect(clip.displayName == "Title Card")
    }

    @Test("itemType is text")
    func itemType() {
        let clip = makeClip()
        #expect(clip.itemType == "text")
    }

    @Test("isGeneratorClip is true")
    func isGeneratorClip() {
        let clip = makeClip()
        #expect(clip.isGeneratorClip == true)
    }

    @Test("position as CGPoint")
    func position() {
        let clip = TextClip(
            durationMicroseconds: 1_000_000,
            text: "Test",
            style: makeStyle(),
            positionX: 0.2,
            positionY: 0.8
        )
        #expect(clip.position == CGPoint(x: 0.2, y: 0.8))
    }

    @Test("shortLabel for short text")
    func shortLabelShort() {
        let clip = makeClip(text: "Short")
        #expect(clip.shortLabel == "Short")
    }

    @Test("shortLabel for long text truncates")
    func shortLabelLong() {
        let longText = String(repeating: "A", count: 40)
        let clip = makeClip(text: longText)
        #expect(clip.shortLabel.count == 30)
        #expect(clip.shortLabel.hasSuffix("..."))
    }

    @Test("shortLabel for empty text")
    func shortLabelEmpty() {
        let clip = makeClip(text: "")
        #expect(clip.shortLabel == "[Empty]")
    }

    @Test("shortLabel uses first line for multi-line text")
    func shortLabelMultiline() {
        let clip = makeClip(text: "First line\nSecond line")
        #expect(clip.shortLabel == "First line")
    }

    // MARK: - Factory

    @Test("subtitle factory creates subtitle clip")
    func subtitleFactory() {
        let clip = TextClip.subtitle(
            durationMicroseconds: 2_000_000,
            text: "Hello subtitle"
        )
        #expect(clip.isSubtitle == true)
        #expect(clip.positionY == 0.85)
        #expect(clip.enterDurationMicros == 0)
        #expect(clip.exitDurationMicros == 0)
        #expect(clip.displayName == "Subtitle")
    }

    // MARK: - Split

    @Test("split at valid offset returns two clips")
    func splitValid() {
        let clip = makeClip(duration: 2_000_000, text: "Test", name: "Title")
        let result = clip.splitAt(1_000_000)
        #expect(result != nil)

        let (left, right) = result!
        #expect(left.durationMicroseconds == 1_000_000)
        #expect(right.durationMicroseconds == 1_000_000)
        #expect(left.text == "Test")
        #expect(right.text == "Test")
        #expect(left.name == "Title (1)")
        #expect(right.name == "Title (2)")
    }

    @Test("split preserves enter/exit animations correctly")
    func splitAnimations() {
        let enter = TextAnimationPreset(type: .fadeIn)
        let exit = TextAnimationPreset(type: .fadeOut)
        let clip = TextClip(
            durationMicroseconds: 2_000_000,
            text: "Test",
            style: makeStyle(),
            enterAnimation: enter,
            exitAnimation: exit
        )
        let result = clip.splitAt(1_000_000)!
        #expect(result.left.enterAnimation != nil)
        #expect(result.left.exitAnimation == nil)
        #expect(result.right.enterAnimation == nil)
        #expect(result.right.exitAnimation != nil)
    }

    @Test("split at invalid offset returns nil")
    func splitInvalid() {
        let clip = makeClip(duration: 200_000)
        #expect(clip.splitAt(50_000) == nil)
    }

    // MARK: - Copy-With

    @Test("with() preserves unchanged fields")
    func withPreserves() {
        let clip = makeClip(text: "Original")
        let modified = clip.with(text: "Modified")
        #expect(modified.text == "Modified")
        #expect(modified.id == clip.id)
        #expect(modified.durationMicroseconds == clip.durationMicroseconds)
    }

    @Test("with clearName sets name to nil")
    func withClearName() {
        let clip = makeClip(name: "Named")
        let modified = clip.with(clearName: true)
        #expect(modified.name == nil)
    }

    // MARK: - Duplicate

    @Test("duplicate creates new ID")
    func duplicate() {
        let clip = makeClip(name: "Original")
        let dupe = clip.duplicate()
        #expect(dupe.id != clip.id)
        #expect(dupe.text == clip.text)
        #expect(dupe.name == "Original (copy)")
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves fields")
    func codableRoundTrip() throws {
        let clip = TextClip(
            id: "tc-rt",
            durationMicroseconds: 2_000_000,
            text: "Codable Test",
            style: makeStyle(fontSize: 64.0),
            positionX: 0.3,
            positionY: 0.7,
            rotation: 0.5,
            scale: 1.5,
            opacity: 0.9,
            isSubtitle: true,
            textAlign: .left,
            maxWidthFraction: 0.8
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(TextClip.self, from: data)
        #expect(decoded.id == "tc-rt")
        #expect(decoded.text == "Codable Test")
        #expect(decoded.positionX == 0.3)
        #expect(decoded.positionY == 0.7)
        #expect(decoded.isSubtitle == true)
        #expect(decoded.textAlign == .left)
        #expect(decoded.maxWidthFraction == 0.8)
    }

    // MARK: - TextClipAlignment

    @Test("TextClipAlignment raw values")
    func alignmentRawValues() {
        #expect(TextClipAlignment.left.rawValue == "left")
        #expect(TextClipAlignment.right.rawValue == "right")
        #expect(TextClipAlignment.center.rawValue == "center")
        #expect(TextClipAlignment.justify.rawValue == "justify")
        #expect(TextClipAlignment.start.rawValue == "start")
        #expect(TextClipAlignment.end.rawValue == "end")
    }
}
