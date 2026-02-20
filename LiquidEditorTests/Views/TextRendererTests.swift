import Testing
import CoreGraphics
@testable import LiquidEditor

// MARK: - TextRenderer Tests

@Suite("TextClipRenderer")
struct TextRendererTests {

    // MARK: - TextClipRenderData

    @Test("TextClipRenderData defaults to opacity 1.0")
    func renderDataDefaultOpacity() {
        let clip = makeTextClip(text: "Test")
        let data = TextClipRenderData(clip: clip)
        #expect(data.animatedOpacity == 1.0)
    }

    @Test("TextClipRenderData equality compares clip and opacity")
    func renderDataEquality() {
        let clip = makeTextClip(text: "Test")
        let data1 = TextClipRenderData(clip: clip, animatedOpacity: 0.5)
        let data2 = TextClipRenderData(clip: clip, animatedOpacity: 0.5)
        let data3 = TextClipRenderData(clip: clip, animatedOpacity: 0.8)

        #expect(data1 == data2)
        #expect(data1 != data3)
    }

    @Test("TextClipRenderData with different text is not equal")
    func renderDataDifferentClipNotEqual() {
        let clip1 = makeTextClip(text: "Hello")
        let clip2 = makeTextClip(text: "World")
        let data1 = TextClipRenderData(clip: clip1)
        let data2 = TextClipRenderData(clip: clip2)
        #expect(data1 != data2)
    }

    // MARK: - Text Resolution

    @Test("Resolve text with default style produces non-empty size")
    func resolveTextDefaultStyle() {
        let clip = makeTextClip(text: "Hello World")
        let style = clip.style
        let resolved = TextClipRenderer.resolveText(clip: clip, style: style, maxWidth: 500)
        #expect(resolved.size.width > 0)
        #expect(resolved.size.height > 0)
    }

    @Test("Resolve text with empty string produces minimal size")
    func resolveTextEmpty() {
        let clip = makeTextClip(text: "")
        let resolved = TextClipRenderer.resolveText(clip: clip, style: clip.style, maxWidth: 500)
        // Empty text should have zero width
        #expect(resolved.size.width == 0)
    }

    @Test("Resolve text respects maxWidth constraint")
    func resolveTextMaxWidth() {
        let clip = makeTextClip(text: "This is a long text that should wrap within the max width constraint")
        let resolved = TextClipRenderer.resolveText(clip: clip, style: clip.style, maxWidth: 200)
        #expect(resolved.size.width <= 200)
    }

    @Test("Longer text produces wider resolved size")
    func resolveTextLongerIsWider() {
        let shortClip = makeTextClip(text: "Hi")
        let longClip = makeTextClip(text: "Hello World This Is Longer")
        let shortResolved = TextClipRenderer.resolveText(clip: shortClip, style: shortClip.style, maxWidth: 1000)
        let longResolved = TextClipRenderer.resolveText(clip: longClip, style: longClip.style, maxWidth: 1000)
        #expect(longResolved.size.width > shortResolved.size.width)
    }

    @Test("Larger font size produces taller resolved text")
    func resolveTextLargerFontTaller() {
        let smallClip = makeTextClip(text: "Test", fontSize: 20)
        let largeClip = makeTextClip(text: "Test", fontSize: 80)
        let smallResolved = TextClipRenderer.resolveText(clip: smallClip, style: smallClip.style, maxWidth: 500)
        let largeResolved = TextClipRenderer.resolveText(clip: largeClip, style: largeClip.style, maxWidth: 500)
        #expect(largeResolved.size.height > smallResolved.size.height)
    }

    // MARK: - Helpers

    private func makeTextClip(
        text: String,
        fontSize: Double = 48.0,
        positionX: Double = 0.5,
        positionY: Double = 0.5
    ) -> TextClip {
        TextClip(
            durationMicroseconds: 3_000_000,
            text: text,
            style: TextOverlayStyle(fontSize: fontSize),
            positionX: positionX,
            positionY: positionY
        )
    }
}
