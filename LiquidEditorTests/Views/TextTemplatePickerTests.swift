import Testing
import CoreGraphics
@testable import LiquidEditor

// MARK: - TextTemplatePicker Tests

@Suite("TextTemplatePicker - Built-in Templates")
struct TextTemplatePickerTests {

    @Test("Built-in templates has 28 entries")
    func builtInTemplateCount() {
        #expect(BuiltInTextTemplates.all.count == 28)
    }

    @Test("Categories include All, Titles, Lower Thirds, Social, Cinematic, Subtitles")
    func categoriesIncludeAll() {
        let categories = BuiltInTextTemplates.categories
        #expect(categories.contains("All"))
        #expect(categories.contains("Titles"))
        #expect(categories.contains("Lower Thirds"))
        #expect(categories.contains("Social"))
        #expect(categories.contains("Cinematic"))
        #expect(categories.contains("Subtitles"))
    }

    @Test("Titles has 8 templates")
    func titlesCategoryCount() {
        let titles = BuiltInTextTemplates.byCategory("Titles")
        #expect(titles.count == 8)
    }

    @Test("Lower Thirds has 6 templates")
    func lowerThirdsCategoryCount() {
        let lowerThirds = BuiltInTextTemplates.byCategory("Lower Thirds")
        #expect(lowerThirds.count == 6)
    }

    @Test("Social has 6 templates")
    func socialCategoryCount() {
        let social = BuiltInTextTemplates.byCategory("Social")
        #expect(social.count == 6)
    }

    @Test("Cinematic has 4 templates")
    func cinematicCategoryCount() {
        let cinematic = BuiltInTextTemplates.byCategory("Cinematic")
        #expect(cinematic.count == 4)
    }

    @Test("Subtitles has 4 templates")
    func subtitlesCategoryCount() {
        let subtitles = BuiltInTextTemplates.byCategory("Subtitles")
        #expect(subtitles.count == 4)
    }

    @Test("All category returns all templates")
    func allCategoryReturnsAll() {
        let all = BuiltInTextTemplates.byCategory("All")
        #expect(all.count == 28)
    }

    @Test("All template IDs are unique")
    func uniqueTemplateIds() {
        let ids = BuiltInTextTemplates.all.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "Duplicate template IDs found")
    }

    @Test("All templates have non-empty names")
    func nonEmptyNames() {
        for template in BuiltInTextTemplates.all {
            #expect(!template.name.isEmpty, "Template \(template.id) has empty name")
        }
    }

    @Test("All templates have non-empty preview text")
    func nonEmptyPreviewText() {
        for template in BuiltInTextTemplates.all {
            #expect(!template.previewText.isEmpty, "Template \(template.id) has empty previewText")
        }
    }

    @Test("All templates are marked as built-in")
    func allTemplatesAreBuiltIn() {
        for template in BuiltInTextTemplates.all {
            #expect(template.isBuiltIn, "Template \(template.id) should be built-in")
        }
    }

    @Test("Find template by ID works")
    func findByIdWorks() {
        let template = BuiltInTextTemplates.findById("title_bold_center")
        #expect(template != nil)
        #expect(template?.name == "Bold Title")
    }

    @Test("Find template by invalid ID returns nil")
    func findByIdInvalidReturnsNil() {
        let template = BuiltInTextTemplates.findById("nonexistent_id")
        #expect(template == nil)
    }

    @Test("Neon Glow template has glow effect")
    func neonGlowHasGlow() {
        let template = BuiltInTextTemplates.findById("title_neon")
        #expect(template != nil)
        #expect(template?.style.glow != nil)
        #expect(template?.style.glow?.intensity == 0.8)
    }

    @Test("Neon Glow template has sustain animation")
    func neonGlowHasSustainAnimation() {
        let template = BuiltInTextTemplates.findById("title_neon")
        #expect(template?.defaultSustainAnimation != nil)
        #expect(template?.defaultSustainAnimation?.type == .pulse)
    }

    @Test("Outline Title has outline but transparent fill")
    func outlineTitleStyle() {
        let template = BuiltInTextTemplates.findById("title_outline")
        #expect(template != nil)
        #expect(template?.style.outline != nil)
        #expect(template?.style.outline?.width == 3.0)
        // Color alpha is 0 (transparent fill)
        #expect(template?.style.color.alpha == 0.0)
    }

    @Test("News Bar has background and lower third position")
    func newsBarTemplate() {
        let template = BuiltInTextTemplates.findById("lower_third_news")
        #expect(template != nil)
        #expect(template?.style.background != nil)
        #expect(template?.defaultPosition.y == 0.82)
        #expect(template?.defaultAlignment == .left)
        #expect(template?.defaultMaxWidthFraction == 0.6)
    }

    @Test("Subtitle templates have bottom positions")
    func subtitlePositions() {
        let subtitles = BuiltInTextTemplates.byCategory("Subtitles")
        for template in subtitles {
            #expect(template.defaultPosition.y == 0.85,
                    "Subtitle \(template.id) should have y=0.85, got \(template.defaultPosition.y)")
        }
    }

    @Test("Cinematic templates have longer durations")
    func cinematicDurations() {
        let cinematic = BuiltInTextTemplates.byCategory("Cinematic")
        for template in cinematic {
            #expect(template.defaultDurationMicros >= 4_000_000,
                    "Cinematic \(template.id) should have duration >= 4s")
        }
    }

    @Test("Unknown category returns empty list")
    func unknownCategoryReturnsEmpty() {
        let result = BuiltInTextTemplates.byCategory("Nonexistent")
        #expect(result.isEmpty)
    }
}
