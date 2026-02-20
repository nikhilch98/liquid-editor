// TextTemplatePicker.swift
// LiquidEditor
//
// Browse and select built-in text templates in a grid layout.
// Shows category filter bar at top and template preview tiles below.
// Pure iOS 26 SwiftUI with native styling.
//

import SwiftUI

// MARK: - Built-in Templates

/// All built-in text templates organized by category.
enum BuiltInTextTemplates {

    /// All templates.
    static let all: [TextTemplate] = titles + lowerThirds + social + cinematic + subtitles

    /// All unique category names.
    static let categories: [String] = {
        var seen = Set<String>()
        var result = ["All"]
        for template in all {
            if seen.insert(template.category).inserted {
                result.append(template.category)
            }
        }
        return result
    }()

    /// Get templates filtered by category.
    static func byCategory(_ category: String) -> [TextTemplate] {
        if category == "All" { return all }
        return all.filter { $0.category == category }
    }

    /// Find a template by ID.
    static func findById(_ id: String) -> TextTemplate? {
        all.first { $0.id == id }
    }

    // MARK: - Titles

    static let titles: [TextTemplate] = [
        TextTemplate(
            id: "title_bold_center", name: "Bold Title", category: "Titles",
            style: TextOverlayStyle(
                fontSize: 72, fontWeight: .w900,
                shadow: TextShadowStyle(color: .fromARGB32(0x80000000), blurRadius: 8)
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "BOLD TITLE"
        ),
        TextTemplate(
            id: "title_elegant", name: "Elegant", category: "Titles",
            style: TextOverlayStyle(
                fontSize: 56, fontWeight: .w300, letterSpacing: 8.0, lineHeight: 1.5
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "ELEGANT"
        ),
        TextTemplate(
            id: "title_neon", name: "Neon Glow", category: "Titles",
            style: TextOverlayStyle(
                fontSize: 64, color: .fromARGB32(0xFF00FF88), fontWeight: .w700,
                glow: TextGlowStyle(color: .fromARGB32(0xFF00FF88), radius: 15.0, intensity: 0.8)
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .popIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            defaultSustainAnimation: TextAnimationPreset(type: .pulse, parameters: ["loopDuration": 1.5]),
            previewText: "NEON"
        ),
        TextTemplate(
            id: "title_minimal", name: "Minimal Clean", category: "Titles",
            style: TextOverlayStyle(fontSize: 48, fontWeight: .w400, letterSpacing: 2.0),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInBottom),
            defaultExitAnimation: TextAnimationPreset(type: .slideOutTop),
            previewText: "Minimal"
        ),
        TextTemplate(
            id: "title_shadow_bold", name: "Heavy Shadow", category: "Titles",
            style: TextOverlayStyle(
                fontSize: 64, fontWeight: .w800,
                shadow: TextShadowStyle(color: .fromARGB32(0xCC000000), offsetX: 0.04, offsetY: 0.04, blurRadius: 12)
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .scaleUp),
            defaultExitAnimation: TextAnimationPreset(type: .scaleDown),
            previewText: "SHADOW"
        ),
        TextTemplate(
            id: "title_outline", name: "Outline Title", category: "Titles",
            style: TextOverlayStyle(
                fontSize: 72, color: .fromARGB32(0x00000000), fontWeight: .w900,
                outline: TextOutlineStyle(color: .fromARGB32(0xFFFFFFFF), width: 3.0)
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "OUTLINE"
        ),
        TextTemplate(
            id: "title_glitch", name: "Glitch", category: "Titles",
            style: TextOverlayStyle(fontSize: 64, color: .fromARGB32(0xFFFF0050), fontWeight: .w900),
            defaultEnterAnimation: TextAnimationPreset(type: .glitchIn),
            defaultExitAnimation: TextAnimationPreset(type: .glitchOut),
            previewText: "GLITCH"
        ),
        TextTemplate(
            id: "title_typewriter", name: "Typewriter", category: "Titles",
            style: TextOverlayStyle(fontSize: 48, fontWeight: .w400, letterSpacing: 1.0),
            defaultEnterAnimation: TextAnimationPreset(type: .typewriter),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "Typewriter Effect"
        ),
    ]

    // MARK: - Lower Thirds

    static let lowerThirds: [TextTemplate] = [
        TextTemplate(
            id: "lower_third_news", name: "News Bar", category: "Lower Thirds",
            style: TextOverlayStyle(
                fontSize: 32, fontWeight: .w600,
                background: TextBackgroundStyle(color: .fromARGB32(0xCC000000), cornerRadius: 4.0, paddingHorizontal: 16.0, paddingVertical: 8.0)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.82),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInLeft),
            defaultExitAnimation: TextAnimationPreset(type: .slideOutLeft),
            defaultAlignment: .left, defaultMaxWidthFraction: 0.6,
            previewText: "Breaking News"
        ),
        TextTemplate(
            id: "lower_third_social", name: "Social Tag", category: "Lower Thirds",
            style: TextOverlayStyle(
                fontSize: 28, fontWeight: .w500,
                background: TextBackgroundStyle(color: .fromARGB32(0xCC007AFF), cornerRadius: 12.0, paddingHorizontal: 14.0, paddingVertical: 6.0)
            ),
            defaultPosition: CGPoint(x: 0.3, y: 0.85),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInBottom),
            defaultExitAnimation: TextAnimationPreset(type: .slideOutBottom),
            defaultAlignment: .left, defaultMaxWidthFraction: 0.5,
            previewText: "@username"
        ),
        TextTemplate(
            id: "lower_third_name", name: "Name & Title", category: "Lower Thirds",
            style: TextOverlayStyle(
                fontSize: 30, fontWeight: .bold,
                background: TextBackgroundStyle(color: .fromARGB32(0x99000000), cornerRadius: 8.0, paddingHorizontal: 16.0, paddingVertical: 10.0)
            ),
            defaultPosition: CGPoint(x: 0.35, y: 0.82),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInLeft),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            defaultAlignment: .left, defaultMaxWidthFraction: 0.5,
            previewText: "John Smith\nCEO, Company"
        ),
        TextTemplate(
            id: "lower_third_location", name: "Location Tag", category: "Lower Thirds",
            style: TextOverlayStyle(
                fontSize: 26, fontWeight: .w500, letterSpacing: 1.5,
                background: TextBackgroundStyle(color: .fromARGB32(0x80000000), cornerRadius: 6.0, paddingHorizontal: 12.0, paddingVertical: 6.0)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.88),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "San Francisco, CA"
        ),
        TextTemplate(
            id: "lower_third_minimal", name: "Minimal Lower", category: "Lower Thirds",
            style: TextOverlayStyle(fontSize: 28, fontWeight: .w400, letterSpacing: 2.0),
            defaultPosition: CGPoint(x: 0.5, y: 0.88),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "Minimal Lower Third"
        ),
        TextTemplate(
            id: "lower_third_accent", name: "Accent Bar", category: "Lower Thirds",
            style: TextOverlayStyle(
                fontSize: 30, fontWeight: .w600,
                background: TextBackgroundStyle(color: .fromARGB32(0xFFFF3B30), cornerRadius: 4.0, paddingHorizontal: 14.0, paddingVertical: 6.0)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.85),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInRight),
            defaultExitAnimation: TextAnimationPreset(type: .slideOutRight),
            previewText: "LIVE"
        ),
    ]

    // MARK: - Social

    static let social: [TextTemplate] = [
        TextTemplate(
            id: "social_instagram", name: "Instagram Caption", category: "Social",
            style: TextOverlayStyle(
                fontSize: 36, fontWeight: .bold,
                shadow: TextShadowStyle(color: .fromARGB32(0xBB000000), offsetX: 0.01, offsetY: 0.01, blurRadius: 6)
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .popIn),
            defaultExitAnimation: TextAnimationPreset(type: .popOut),
            previewText: "Caption Here"
        ),
        TextTemplate(
            id: "social_tiktok", name: "TikTok Title", category: "Social",
            style: TextOverlayStyle(
                fontSize: 42, fontWeight: .w900,
                outline: TextOutlineStyle(color: .fromARGB32(0xFF000000), width: 2.0)
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .scaleUp),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "POV:"
        ),
        TextTemplate(
            id: "social_youtube", name: "YouTube Subscribe", category: "Social",
            style: TextOverlayStyle(
                fontSize: 28, fontWeight: .bold,
                background: TextBackgroundStyle(color: .fromARGB32(0xFFFF0000), cornerRadius: 6.0, paddingHorizontal: 16.0, paddingVertical: 8.0)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.88),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInBottom),
            defaultExitAnimation: TextAnimationPreset(type: .slideOutBottom),
            previewText: "SUBSCRIBE"
        ),
        TextTemplate(
            id: "social_story", name: "Story Text", category: "Social",
            style: TextOverlayStyle(
                fontSize: 40, fontWeight: .w800,
                shadow: TextShadowStyle(color: .fromARGB32(0x99000000), offsetX: 0.015, offsetY: 0.015, blurRadius: 4)
            ),
            defaultEnterAnimation: TextAnimationPreset(type: .bounceIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "STORY TEXT"
        ),
        TextTemplate(
            id: "social_hashtag", name: "Hashtag", category: "Social",
            style: TextOverlayStyle(fontSize: 32, color: .fromARGB32(0xFF007AFF), fontWeight: .bold),
            defaultPosition: CGPoint(x: 0.5, y: 0.8),
            defaultEnterAnimation: TextAnimationPreset(type: .slideInBottom),
            defaultExitAnimation: TextAnimationPreset(type: .slideOutBottom),
            previewText: "#trending"
        ),
        TextTemplate(
            id: "social_meme", name: "Meme Text", category: "Social",
            style: TextOverlayStyle(
                fontSize: 56, fontWeight: .w900,
                outline: TextOutlineStyle(color: .fromARGB32(0xFF000000), width: 3.0)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.15),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            previewText: "WHEN YOU"
        ),
    ]

    // MARK: - Cinematic

    static let cinematic: [TextTemplate] = [
        TextTemplate(
            id: "cinematic_credits", name: "Film Credits", category: "Cinematic",
            style: TextOverlayStyle(fontSize: 36, fontWeight: .w300, letterSpacing: 6.0, lineHeight: 1.8),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            defaultDurationMicros: 5_000_000,
            previewText: "DIRECTED BY\nJane Smith"
        ),
        TextTemplate(
            id: "cinematic_chapter", name: "Chapter Title", category: "Cinematic",
            style: TextOverlayStyle(fontSize: 48, fontWeight: .w200, letterSpacing: 10.0),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn, intensity: 0.8),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            defaultDurationMicros: 4_000_000,
            previewText: "CHAPTER ONE"
        ),
        TextTemplate(
            id: "cinematic_quote", name: "Quote Frame", category: "Cinematic",
            style: TextOverlayStyle(fontSize: 36, fontWeight: .w300, isItalic: true, lineHeight: 1.6),
            defaultEnterAnimation: TextAnimationPreset(type: .fadeIn),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            defaultDurationMicros: 5_000_000, defaultMaxWidthFraction: 0.7,
            previewText: "\"The journey of a\nthousand miles...\""
        ),
        TextTemplate(
            id: "cinematic_typewriter", name: "Cinematic Type", category: "Cinematic",
            style: TextOverlayStyle(fontSize: 32, color: .fromARGB32(0xFFCCCCCC), fontWeight: .w400, letterSpacing: 2.0),
            defaultEnterAnimation: TextAnimationPreset(type: .typewriter),
            defaultExitAnimation: TextAnimationPreset(type: .fadeOut),
            defaultDurationMicros: 5_000_000,
            previewText: "Based on a true story..."
        ),
    ]

    // MARK: - Subtitles

    static let subtitles: [TextTemplate] = [
        TextTemplate(
            id: "subtitle_standard", name: "Standard White", category: "Subtitles",
            style: TextOverlayStyle(
                fontSize: 32, fontWeight: .w600,
                outline: TextOutlineStyle(color: .fromARGB32(0xFF000000), width: 1.5)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.85),
            previewText: "Standard subtitle text"
        ),
        TextTemplate(
            id: "subtitle_boxed", name: "Boxed Black", category: "Subtitles",
            style: TextOverlayStyle(
                fontSize: 30, fontWeight: .w500,
                background: TextBackgroundStyle(color: .fromARGB32(0xCC000000), cornerRadius: 4.0, paddingHorizontal: 10.0, paddingVertical: 4.0)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.85),
            previewText: "Boxed subtitle text"
        ),
        TextTemplate(
            id: "subtitle_yellow", name: "Yellow Outline", category: "Subtitles",
            style: TextOverlayStyle(
                fontSize: 34, color: .fromARGB32(0xFFFFFF00), fontWeight: .bold,
                outline: TextOutlineStyle(color: .fromARGB32(0xFF000000), width: 2.0)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.85),
            previewText: "Yellow subtitle text"
        ),
        TextTemplate(
            id: "subtitle_karaoke", name: "Karaoke Style", category: "Subtitles",
            style: TextOverlayStyle(
                fontSize: 36, fontWeight: .w800,
                outline: TextOutlineStyle(color: .fromARGB32(0xFF0000FF), width: 2.0),
                glow: TextGlowStyle(color: .fromARGB32(0xFF0066FF), radius: 8.0, intensity: 0.4)
            ),
            defaultPosition: CGPoint(x: 0.5, y: 0.85),
            previewText: "Karaoke style"
        ),
    ]
}

// MARK: - TextTemplatePicker

/// View for browsing and selecting text templates.
///
/// Shows a category filter bar at the top and a grid of template
/// preview tiles below. Each tile shows a programmatic preview of
/// the template's style applied to its preview text.
struct TextTemplatePicker: View {

    /// Called when a template is selected.
    let onTemplateSelected: (TextTemplate) -> Void

    /// Currently selected category filter.
    @State private var selectedCategory = "All"

    // MARK: - Body

    var body: some View {
        VStack(spacing: LiquidSpacing.sm) {
            // Category filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LiquidSpacing.xs + 2) {
                    ForEach(BuiltInTextTemplates.categories, id: \.self) { category in
                        let isSelected = category == selectedCategory
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedCategory = category
                        } label: {
                            Text(category)
                                .font(LiquidTypography.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, LiquidSpacing.md + 2)
                                .padding(.vertical, LiquidSpacing.sm - 1)
                                .background(
                                    Capsule().fill(isSelected ? LiquidColors.primary : LiquidColors.tertiaryBackground)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, LiquidSpacing.md)
            }
            .frame(height: 36)

            // Template grid
            let templates = BuiltInTextTemplates.byCategory(selectedCategory)
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 150), spacing: 8),
                    ],
                    spacing: LiquidSpacing.sm
                ) {
                    ForEach(templates, id: \.id) { template in
                        TemplatePreviewTile(template: template) {
                            onTemplateSelected(template)
                        }
                    }
                }
                .padding(.horizontal, LiquidSpacing.md)
            }
        }
    }
}

// MARK: - TemplatePreviewTile

/// A single template preview tile in the grid.
///
/// Renders a programmatic preview of the template's style
/// with the template's preview text on a dark background.
private struct TemplatePreviewTile: View {
    let template: TextTemplate
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            ZStack {
                // Dark background with glass border
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(LiquidColors.separator.opacity(0.3))
                    )

                // Preview text centered
                VStack {
                    Spacer()

                    Text(template.previewText)
                        .font(previewFont)
                        .foregroundStyle(previewColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(8)

                    Spacer()

                    // Template name label at bottom
                    Text(template.name)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                }

                // Category badge at top-right
                VStack {
                    HStack {
                        Spacer()
                        Text(template.category)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.6))
                            )
                            .padding(4)
                    }
                    Spacer()
                }
            }
            .aspectRatio(1.4, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }

    /// Compute the preview font from the template style.
    private var previewFont: Font {
        let scaledSize = min(max(template.style.fontSize * 0.3, 12.0), 28.0)
        var font = Font.system(size: scaledSize)
        switch template.style.fontWeight {
        case .w100, .w200, .w300:
            font = font.weight(.light)
        case .w400:
            font = font.weight(.regular)
        case .w500, .w600:
            font = font.weight(.semibold)
        case .w700:
            font = font.weight(.bold)
        case .w800, .w900:
            font = font.weight(.heavy)
        }
        if template.style.isItalic {
            font = font.italic()
        }
        return font
    }

    /// Compute the preview color from the template style.
    private var previewColor: Color {
        let c = template.style.color
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}
