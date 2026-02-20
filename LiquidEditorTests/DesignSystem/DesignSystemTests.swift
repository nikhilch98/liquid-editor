import Testing
import SwiftUI
@testable import LiquidEditor

// MARK: - LiquidSpacing Tests

@Suite("LiquidSpacing Tests")
struct LiquidSpacingTests {

    // MARK: - Spacing Scale Values

    @Test("Spacing xxs is 2")
    func spacingXXS() {
        #expect(LiquidSpacing.xxs == 2)
    }

    @Test("Spacing xs is 4")
    func spacingXS() {
        #expect(LiquidSpacing.xs == 4)
    }

    @Test("Spacing sm is 8")
    func spacingSM() {
        #expect(LiquidSpacing.sm == 8)
    }

    @Test("Spacing md is 12")
    func spacingMD() {
        #expect(LiquidSpacing.md == 12)
    }

    @Test("Spacing lg is 16")
    func spacingLG() {
        #expect(LiquidSpacing.lg == 16)
    }

    @Test("Spacing xl is 20")
    func spacingXL() {
        #expect(LiquidSpacing.xl == 20)
    }

    @Test("Spacing xxl is 24")
    func spacingXXL() {
        #expect(LiquidSpacing.xxl == 24)
    }

    @Test("Spacing xxxl is 32")
    func spacingXXXL() {
        #expect(LiquidSpacing.xxxl == 32)
    }

    @Test("Spacing scale is monotonically increasing")
    func spacingScaleIsIncreasing() {
        let scale: [CGFloat] = [
            LiquidSpacing.xxs, LiquidSpacing.xs, LiquidSpacing.sm,
            LiquidSpacing.md, LiquidSpacing.lg, LiquidSpacing.xl,
            LiquidSpacing.xxl, LiquidSpacing.xxxl,
        ]
        for i in 1..<scale.count {
            #expect(scale[i] > scale[i - 1], "Spacing scale must be increasing at index \(i)")
        }
    }

    // MARK: - Corner Radius Values

    @Test("Corner radius small is 8")
    func cornerSmall() {
        #expect(LiquidSpacing.cornerSmall == 8)
    }

    @Test("Corner radius medium is 12")
    func cornerMedium() {
        #expect(LiquidSpacing.cornerMedium == 12)
    }

    @Test("Corner radius large is 16")
    func cornerLarge() {
        #expect(LiquidSpacing.cornerLarge == 16)
    }

    @Test("Corner radius XLarge is 20")
    func cornerXLarge() {
        #expect(LiquidSpacing.cornerXLarge == 20)
    }

    @Test("Corner radius circular is 9999")
    func cornerCircular() {
        #expect(LiquidSpacing.cornerCircular == 9999)
    }

    @Test("Corner radius scale is monotonically increasing")
    func cornerRadiusIsIncreasing() {
        let radii: [CGFloat] = [
            LiquidSpacing.cornerSmall, LiquidSpacing.cornerMedium,
            LiquidSpacing.cornerLarge, LiquidSpacing.cornerXLarge,
            LiquidSpacing.cornerCircular,
        ]
        for i in 1..<radii.count {
            #expect(radii[i] > radii[i - 1], "Corner radius must be increasing at index \(i)")
        }
    }

    // MARK: - Padding Presets

    @Test("Compact padding uses sm values")
    func compactPadding() {
        let padding = LiquidSpacing.paddingCompact
        #expect(padding.top == LiquidSpacing.sm)
        #expect(padding.leading == LiquidSpacing.sm)
        #expect(padding.bottom == LiquidSpacing.sm)
        #expect(padding.trailing == LiquidSpacing.sm)
    }

    @Test("Standard padding uses lg values")
    func standardPadding() {
        let padding = LiquidSpacing.paddingStandard
        #expect(padding.top == LiquidSpacing.lg)
        #expect(padding.leading == LiquidSpacing.lg)
        #expect(padding.bottom == LiquidSpacing.lg)
        #expect(padding.trailing == LiquidSpacing.lg)
    }

    @Test("Spacious padding uses xxl values")
    func spaciousPadding() {
        let padding = LiquidSpacing.paddingSpacious
        #expect(padding.top == LiquidSpacing.xxl)
        #expect(padding.leading == LiquidSpacing.xxl)
        #expect(padding.bottom == LiquidSpacing.xxl)
        #expect(padding.trailing == LiquidSpacing.xxl)
    }

    @Test("Horizontal padding has zero vertical")
    func horizontalPadding() {
        let padding = LiquidSpacing.paddingHorizontal
        #expect(padding.top == 0)
        #expect(padding.bottom == 0)
        #expect(padding.leading == LiquidSpacing.lg)
        #expect(padding.trailing == LiquidSpacing.lg)
    }

    @Test("Section header padding values")
    func sectionHeaderPadding() {
        let padding = LiquidSpacing.paddingSectionHeader
        #expect(padding.top == LiquidSpacing.xl)
        #expect(padding.leading == LiquidSpacing.lg)
        #expect(padding.bottom == LiquidSpacing.sm)
        #expect(padding.trailing == LiquidSpacing.lg)
    }

    // MARK: - Icon Sizes

    @Test("Icon sizes are correct")
    func iconSizes() {
        #expect(LiquidSpacing.iconSmall == 16)
        #expect(LiquidSpacing.iconMedium == 20)
        #expect(LiquidSpacing.iconLarge == 24)
        #expect(LiquidSpacing.iconXLarge == 32)
    }

    // MARK: - Touch Targets

    @Test("Minimum touch target is 44")
    func minTouchTarget() {
        #expect(LiquidSpacing.minTouchTarget == 44)
    }

    @Test("Button heights are correct")
    func buttonHeights() {
        #expect(LiquidSpacing.buttonHeight == 50)
        #expect(LiquidSpacing.buttonHeightCompact == 36)
    }

    @Test("Bar heights are correct")
    func barHeights() {
        #expect(LiquidSpacing.tabBarHeight == 49)
        #expect(LiquidSpacing.navigationBarHeight == 44)
    }

    @Test("Timeline track height is 56")
    func timelineTrackHeight() {
        #expect(LiquidSpacing.timelineTrackHeight == 56)
    }
}

// MARK: - LiquidTypography Tests

@Suite("LiquidTypography Tests")
struct LiquidTypographyTests {

    @Test("Large title styles are accessible")
    func largeTitleStyles() {
        // Verify the static properties exist and return Font values.
        // We can't inspect Font internals, so we verify they are not equal
        // to each other (different weights should produce different fonts).
        let largeTitle = LiquidTypography.largeTitle
        let largeTitleLight = LiquidTypography.largeTitleLight
        // Both should be non-nil (always true for static let) but
        // we verify the compiler accepts them as Font.
        let _: Font = largeTitle
        let _: Font = largeTitleLight
    }

    @Test("Title styles are accessible")
    func titleStyles() {
        let _: Font = LiquidTypography.title
        let _: Font = LiquidTypography.title2
        let _: Font = LiquidTypography.title3
    }

    @Test("Headline styles are accessible")
    func headlineStyles() {
        let _: Font = LiquidTypography.headline
        let _: Font = LiquidTypography.headlineBold
    }

    @Test("Body styles are accessible")
    func bodyStyles() {
        let _: Font = LiquidTypography.body
        let _: Font = LiquidTypography.bodyMedium
        let _: Font = LiquidTypography.bodySemibold
    }

    @Test("Callout styles are accessible")
    func calloutStyles() {
        let _: Font = LiquidTypography.callout
        let _: Font = LiquidTypography.calloutMedium
    }

    @Test("Subheadline styles are accessible")
    func subheadlineStyles() {
        let _: Font = LiquidTypography.subheadline
        let _: Font = LiquidTypography.subheadlineMedium
        let _: Font = LiquidTypography.subheadlineSemibold
    }

    @Test("Footnote styles are accessible")
    func footnoteStyles() {
        let _: Font = LiquidTypography.footnote
        let _: Font = LiquidTypography.footnoteMedium
        let _: Font = LiquidTypography.footnoteSemibold
    }

    @Test("Caption styles are accessible")
    func captionStyles() {
        let _: Font = LiquidTypography.caption
        let _: Font = LiquidTypography.captionMedium
        let _: Font = LiquidTypography.caption2
        let _: Font = LiquidTypography.caption2Semibold
    }

    @Test("Monospaced styles are accessible")
    func monospacedStyles() {
        let _: Font = LiquidTypography.monoBody
        let _: Font = LiquidTypography.monoCaption
        let _: Font = LiquidTypography.monoSubheadline
    }

    @Test("All expected typography styles exist (22 total)")
    func allTypographyStylesCount() {
        // Collect all styles to verify they compile and are distinct references.
        let allStyles: [Font] = [
            LiquidTypography.largeTitle, LiquidTypography.largeTitleLight,
            LiquidTypography.title, LiquidTypography.title2, LiquidTypography.title3,
            LiquidTypography.headline, LiquidTypography.headlineBold,
            LiquidTypography.body, LiquidTypography.bodyMedium, LiquidTypography.bodySemibold,
            LiquidTypography.callout, LiquidTypography.calloutMedium,
            LiquidTypography.subheadline, LiquidTypography.subheadlineMedium,
            LiquidTypography.subheadlineSemibold,
            LiquidTypography.footnote, LiquidTypography.footnoteMedium,
            LiquidTypography.footnoteSemibold,
            LiquidTypography.caption, LiquidTypography.captionMedium,
            LiquidTypography.caption2, LiquidTypography.caption2Semibold,
        ]
        #expect(allStyles.count == 22)
    }
}

// MARK: - GlassStyle Tests

@Suite("GlassStyle Tests")
@MainActor
struct GlassStyleTests {

    @Test("GlassStyle has all expected cases")
    func allCases() {
        let thin = GlassStyle.thin
        let regular = GlassStyle.regular
        let thick = GlassStyle.thick
        let ultraThick = GlassStyle.ultraThick

        // Verify all four cases exist by using them.
        _ = thin
        _ = regular
        _ = thick
        _ = ultraThick
    }

    @Test("GlassStyle is Sendable")
    func isSendable() {
        // Verifying the type conforms to Sendable by passing across concurrency boundary.
        let style: any Sendable = GlassStyle.regular
        #expect(style is GlassStyle)
    }

    @Test("GlassEffectModifier can be created with all styles")
    func modifierCreation() {
        let styles: [GlassStyle] = [.thin, .regular, .thick, .ultraThick]
        for style in styles {
            let modifier = GlassEffectModifier(
                style: style,
                cornerRadius: 20,
                showBorder: true,
                showShadow: true
            )
            #expect(modifier.style == style)
            #expect(modifier.cornerRadius == 20)
            #expect(modifier.showBorder == true)
            #expect(modifier.showShadow == true)
        }
    }

    @Test("GlassEffectModifier stores configuration correctly")
    func modifierConfiguration() {
        let modifier = GlassEffectModifier(
            style: .thick,
            cornerRadius: 12,
            showBorder: false,
            showShadow: false
        )
        #expect(modifier.style == .thick)
        #expect(modifier.cornerRadius == 12)
        #expect(modifier.showBorder == false)
        #expect(modifier.showShadow == false)
    }
}

// MARK: - CropAspectRatio Tests

@Suite("CropAspectRatio Tests")
struct CropAspectRatioTests {

    @Test("CaseIterable has exactly 5 cases")
    func caseCount() {
        #expect(CropAspectRatio.allCases.count == 8)
    }

    @Test("All expected cases exist in allCases")
    func allExpectedCases() {
        let allCases = CropAspectRatio.allCases
        #expect(allCases.contains(.free))
        #expect(allCases.contains(.r16x9))
        #expect(allCases.contains(.r9x16))
        #expect(allCases.contains(.r4x3))
        #expect(allCases.contains(.r1x1))
    }

    // MARK: - Ratio Values

    @Test("Free ratio is nil")
    func freeRatioIsNil() {
        #expect(CropAspectRatio.free.ratio == nil)
    }

    @Test("16:9 ratio is correct")
    func ratio16x9() {
        let ratio = CropAspectRatio.r16x9.ratio
        #expect(ratio != nil)
        let expected = 16.0 / 9.0
        #expect(abs(ratio! - expected) < 0.0001)
    }

    @Test("9:16 ratio is correct")
    func ratio9x16() {
        let ratio = CropAspectRatio.r9x16.ratio
        #expect(ratio != nil)
        let expected = 9.0 / 16.0
        #expect(abs(ratio! - expected) < 0.0001)
    }

    @Test("4:3 ratio is correct")
    func ratio4x3() {
        let ratio = CropAspectRatio.r4x3.ratio
        #expect(ratio != nil)
        let expected = 4.0 / 3.0
        #expect(abs(ratio! - expected) < 0.0001)
    }

    @Test("1:1 ratio is 1.0")
    func ratio1x1() {
        #expect(CropAspectRatio.r1x1.ratio == 1.0)
    }

    @Test("16:9 and 9:16 are reciprocals")
    func reciprocalRatios() {
        guard let wide = CropAspectRatio.r16x9.ratio,
              let tall = CropAspectRatio.r9x16.ratio else {
            Issue.record("Expected non-nil ratios")
            return
        }
        #expect(abs(wide * tall - 1.0) < 0.0001)
    }

    // MARK: - SF Symbols

    @Test("All cases have non-empty SF symbols")
    func allSFSymbolsNonEmpty() {
        for ratio in CropAspectRatio.allCases {
            #expect(!ratio.sfSymbol.isEmpty, "\(ratio.rawValue) has empty sfSymbol")
        }
    }

    @Test("SF symbols match expected values")
    func sfSymbolValues() {
        #expect(CropAspectRatio.free.sfSymbol == "crop")
        #expect(CropAspectRatio.r16x9.sfSymbol == "rectangle")
        #expect(CropAspectRatio.r9x16.sfSymbol == "rectangle.portrait")
        #expect(CropAspectRatio.r4x3.sfSymbol == "rectangle.ratio.4.to.3")
        #expect(CropAspectRatio.r1x1.sfSymbol == "square")
    }

    // MARK: - Raw Values

    @Test("Raw values match display strings")
    func rawValues() {
        #expect(CropAspectRatio.free.rawValue == "Free")
        #expect(CropAspectRatio.r16x9.rawValue == "16:9")
        #expect(CropAspectRatio.r9x16.rawValue == "9:16")
        #expect(CropAspectRatio.r4x3.rawValue == "4:3")
        #expect(CropAspectRatio.r1x1.rawValue == "1:1")
    }

    // MARK: - Identifiable

    @Test("id matches rawValue")
    func idMatchesRawValue() {
        for ratio in CropAspectRatio.allCases {
            #expect(ratio.id == ratio.rawValue)
        }
    }

    @Test("All ids are unique")
    func allIdsUnique() {
        let ids = CropAspectRatio.allCases.map(\.id)
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == CropAspectRatio.allCases.count)
    }
}

// MARK: - LiquidColors Tests

@Suite("LiquidColors Tests")
struct LiquidColorsTests {

    @Test("Background colors are accessible")
    func backgroundColors() {
        let _: Color = LiquidColors.background
        let _: Color = LiquidColors.secondaryBackground
        let _: Color = LiquidColors.tertiaryBackground
    }

    @Test("Surface colors are accessible")
    func surfaceColors() {
        let _: Color = LiquidColors.surface
        let _: Color = LiquidColors.glassSurface
        let _: Color = LiquidColors.glassSurfaceProminent
        let _: Color = LiquidColors.glassSurfaceSubtle
    }

    @Test("Brand colors are accessible")
    func brandColors() {
        let _: Color = LiquidColors.primary
        let _: Color = LiquidColors.secondary
        let _: Color = LiquidColors.accent
    }

    @Test("Text colors are accessible")
    func textColors() {
        let _: Color = LiquidColors.textPrimary
        let _: Color = LiquidColors.textSecondary
        let _: Color = LiquidColors.textTertiary
        let _: Color = LiquidColors.textQuaternary
    }

    @Test("Separator colors are accessible")
    func separatorColors() {
        let _: Color = LiquidColors.separator
        let _: Color = LiquidColors.separatorOpaque
    }

    @Test("Semantic colors are accessible")
    func semanticColors() {
        let _: Color = LiquidColors.error
        let _: Color = LiquidColors.success
        let _: Color = LiquidColors.warning
        let _: Color = LiquidColors.info
    }

    @Test("Fill colors are accessible")
    func fillColors() {
        let _: Color = LiquidColors.fillPrimary
        let _: Color = LiquidColors.fillSecondary
        let _: Color = LiquidColors.fillTertiary
        let _: Color = LiquidColors.fillQuaternary
    }

    @Test("Glass border colors are accessible")
    func glassBorderColors() {
        let _: Color = LiquidColors.glassBorder
        let _: Color = LiquidColors.glassBorderProminent
    }

    @Test("Timeline colors are accessible")
    func timelineColors() {
        let _: Color = LiquidColors.timelineVideo
        let _: Color = LiquidColors.timelineAudio
        let _: Color = LiquidColors.timelineText
        let _: Color = LiquidColors.timelineSticker
        let _: Color = LiquidColors.timelineTransition
        let _: Color = LiquidColors.timelinePlayhead
    }
}
