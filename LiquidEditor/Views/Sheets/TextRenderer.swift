// TextRenderer.swift
// LiquidEditor
//
// Renders text with styling, shadows, outlines, glow, and background on a Canvas.
// Preview-side renderer for text overlays. Export-side renderer uses CATextLayer (native).
// Pure iOS 26 SwiftUI with Canvas for rendering.
//

import SwiftUI
import CoreGraphics

// MARK: - TextClipRenderData

/// Data needed to render a text clip at a specific time.
///
/// Combines the clip with animation-computed opacity for the current frame.
struct TextClipRenderData: Equatable, Sendable {

    /// The text clip to render.
    let clip: TextClip

    /// Animated opacity (0.0-1.0) computed from enter/exit/sustain animations.
    let animatedOpacity: Double

    init(clip: TextClip, animatedOpacity: Double = 1.0) {
        self.clip = clip
        self.animatedOpacity = animatedOpacity
    }
}

// MARK: - TextClipRenderer

/// Renders a `TextClip` onto a `GraphicsContext` at a given size.
///
/// Handles all visual properties: font, color, shadow, outline,
/// glow, background box, positioning, rotation, and scaling.
///
/// Usage:
/// ```swift
/// TextClipRenderer.paint(context: ctx, size: size, clip: clip)
/// ```
enum TextClipRenderer {

    // MARK: - Main Paint

    /// Paint a `TextClip` onto the graphics context at the given size.
    ///
    /// - Parameters:
    ///   - context: The SwiftUI `GraphicsContext`.
    ///   - size: The video preview area size in logical pixels.
    ///   - clip: The text clip to render.
    ///   - clipOpacity: External opacity control (e.g., for animation).
    static func paint(
        context: inout GraphicsContext,
        size: CGSize,
        clip: TextClip,
        clipOpacity: Double = 1.0
    ) {
        guard !clip.text.isEmpty else { return }

        let effectiveOpacity = clip.opacity * clipOpacity
        guard effectiveOpacity > 0.0 else { return }

        let style = clip.style
        let maxWidth = size.width * clip.maxWidthFraction

        // Create attributed string for measurement
        let resolvedText = resolveText(clip: clip, style: style, maxWidth: maxWidth)
        let textSize = resolvedText.size

        // Calculate position from normalized coordinates
        let centerX = size.width * clip.positionX
        let centerY = size.height * clip.positionY

        // Apply transform: translate to center, then rotate/scale
        var copy = context
        copy.translateBy(x: centerX, y: centerY)

        if clip.rotation != 0.0 {
            copy.rotate(by: .radians(clip.rotation))
        }

        if clip.scale != 1.0 {
            copy.scaleBy(x: clip.scale, y: clip.scale)
        }

        // Top-left corner offset (text is centered on the position point)
        let textOffset = CGPoint(x: -textSize.width / 2, y: -textSize.height / 2)

        // Draw background box if configured
        if let background = style.background {
            paintBackground(
                context: &copy,
                textOffset: textOffset,
                textSize: textSize,
                background: background,
                opacity: effectiveOpacity
            )
        }

        // Draw glow effect if configured
        if let glow = style.glow {
            paintGlow(
                context: &copy,
                text: resolvedText.text,
                offset: textOffset,
                glow: glow,
                opacity: effectiveOpacity
            )
        }

        // Draw shadow if configured
        if let shadow = style.shadow {
            paintShadow(
                context: &copy,
                text: resolvedText.text,
                offset: textOffset,
                shadow: shadow,
                opacity: effectiveOpacity,
                fontSize: style.fontSize
            )
        }

        // Draw outline if configured
        if let outline = style.outline {
            paintOutline(
                context: &copy,
                clip: clip,
                maxWidth: maxWidth,
                offset: textOffset,
                outline: outline,
                opacity: effectiveOpacity
            )
        }

        // Draw the main text
        copy.opacity = effectiveOpacity
        copy.draw(resolvedText.text, at: textOffset, anchor: .topLeading)
    }

    // MARK: - Text Resolution

    /// Resolved text with pre-measured size for layout.
    struct ResolvedTextData {
        let text: Text
        let size: CGSize
    }

    /// Create and measure the text view.
    static func resolveText(clip: TextClip, style: TextOverlayStyle, maxWidth: CGFloat) -> ResolvedTextData {
        let swiftUIColor = Color(
            .sRGB,
            red: style.color.red,
            green: style.color.green,
            blue: style.color.blue,
            opacity: style.color.alpha
        )

        var font = Font.custom(style.fontFamily, size: style.fontSize)
        switch style.fontWeight {
        case .w100, .w200: font = font.weight(.ultraLight)
        case .w300: font = font.weight(.light)
        case .w400: font = font.weight(.regular)
        case .w500: font = font.weight(.medium)
        case .w600: font = font.weight(.semibold)
        case .w700: font = font.weight(.bold)
        case .w800: font = font.weight(.heavy)
        case .w900: font = font.weight(.black)
        }

        var text = Text(clip.text)
            .font(font)
            .foregroundStyle(swiftUIColor)

        if style.isItalic {
            text = text.italic()
        }

        // Estimate text size (approximate; Canvas does not provide layout measurement)
        let estimatedWidth = min(maxWidth, CGFloat(clip.text.count) * style.fontSize * 0.6)
        let lineCount = max(1, Int(ceil(estimatedWidth / maxWidth)))
        let estimatedHeight = CGFloat(lineCount) * style.fontSize * style.lineHeight

        return ResolvedTextData(
            text: text,
            size: CGSize(width: min(estimatedWidth, maxWidth), height: estimatedHeight)
        )
    }

    // MARK: - Background

    /// Paint the background box behind text.
    private static func paintBackground(
        context: inout GraphicsContext,
        textOffset: CGPoint,
        textSize: CGSize,
        background: TextBackgroundStyle,
        opacity: Double
    ) {
        let rect = CGRect(
            x: textOffset.x - background.paddingHorizontal,
            y: textOffset.y - background.paddingVertical,
            width: textSize.width + background.paddingHorizontal * 2,
            height: textSize.height + background.paddingVertical * 2
        )

        let bgColor = Color(
            .sRGB,
            red: background.color.red,
            green: background.color.green,
            blue: background.color.blue,
            opacity: background.color.alpha * opacity
        )

        let path = RoundedRectangle(cornerRadius: background.cornerRadius)
            .path(in: rect)

        context.fill(path, with: .color(bgColor))
    }

    // MARK: - Glow

    /// Paint glow effect around text.
    private static func paintGlow(
        context: inout GraphicsContext,
        text: Text,
        offset: CGPoint,
        glow: TextGlowStyle,
        opacity: Double
    ) {
        let glowColor = Color(
            .sRGB,
            red: glow.color.red,
            green: glow.color.green,
            blue: glow.color.blue,
            opacity: glow.intensity * opacity
        )

        var copy = context
        copy.addFilter(.blur(radius: glow.radius))
        copy.opacity = glow.intensity * opacity

        // Draw text as glow layer with blur
        let glowText = text.foregroundStyle(glowColor)
        copy.draw(glowText, at: offset, anchor: .topLeading)
    }

    // MARK: - Shadow

    /// Paint text shadow.
    private static func paintShadow(
        context: inout GraphicsContext,
        text: Text,
        offset: CGPoint,
        shadow: TextShadowStyle,
        opacity: Double,
        fontSize: Double
    ) {
        let shadowOffset = CGPoint(
            x: shadow.offsetX * fontSize,
            y: shadow.offsetY * fontSize
        )

        let shadowColor = Color(
            .sRGB,
            red: shadow.color.red,
            green: shadow.color.green,
            blue: shadow.color.blue,
            opacity: shadow.color.alpha * opacity
        )

        var copy = context
        copy.addFilter(.blur(radius: shadow.blurRadius))
        copy.opacity = shadow.color.alpha * opacity

        let shadowText = text.foregroundStyle(shadowColor)
        let shadowPosition = CGPoint(
            x: offset.x + shadowOffset.x,
            y: offset.y + shadowOffset.y
        )
        copy.draw(shadowText, at: shadowPosition, anchor: .topLeading)
    }

    // MARK: - Outline

    /// Paint text outline/stroke.
    private static func paintOutline(
        context: inout GraphicsContext,
        clip: TextClip,
        maxWidth: CGFloat,
        offset: CGPoint,
        outline: TextOutlineStyle,
        opacity: Double
    ) {
        let outlineColor = Color(
            .sRGB,
            red: outline.color.red,
            green: outline.color.green,
            blue: outline.color.blue,
            opacity: outline.color.alpha * opacity
        )

        // Create outline text using stroke style
        let outlineText = Text(clip.text)
            .font(.custom(clip.style.fontFamily, size: clip.style.fontSize))
            .foregroundStyle(outlineColor)

        // Draw offset copies to simulate stroke
        let strokeWidth = outline.width
        let offsets: [(CGFloat, CGFloat)] = [
            (-strokeWidth, 0), (strokeWidth, 0),
            (0, -strokeWidth), (0, strokeWidth),
            (-strokeWidth * 0.7, -strokeWidth * 0.7),
            (strokeWidth * 0.7, -strokeWidth * 0.7),
            (-strokeWidth * 0.7, strokeWidth * 0.7),
            (strokeWidth * 0.7, strokeWidth * 0.7),
        ]

        for (dx, dy) in offsets {
            context.draw(
                outlineText,
                at: CGPoint(x: offset.x + dx, y: offset.y + dy),
                anchor: .topLeading
            )
        }
    }
}

// MARK: - TextPreviewView

/// SwiftUI view that renders multiple text clips using Canvas.
///
/// Used to overlay text on the video preview.
/// Takes a list of text clips and renders all that are visible
/// at the current playhead time.
struct TextPreviewView: View {

    /// Text clips visible at the current time, ordered by z-index.
    let visibleClips: [TextClipRenderData]

    var body: some View {
        Canvas { context, size in
            for data in visibleClips {
                TextClipRenderer.paint(
                    context: &context,
                    size: size,
                    clip: data.clip,
                    clipOpacity: data.animatedOpacity
                )
            }
        }
        .accessibilityLabel(
            visibleClips.isEmpty
                ? "No text overlays"
                : "\(visibleClips.count) text overlay\(visibleClips.count == 1 ? "" : "s")"
        )
    }
}
