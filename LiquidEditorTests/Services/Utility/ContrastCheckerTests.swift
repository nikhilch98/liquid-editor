import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("ContrastChecker WCAG AA")
struct ContrastCheckerTests {

    // MARK: - Known Pairs

    @Test("Black on white is maximum contrast (~21:1)")
    func blackOnWhiteRatio() {
        let ratio = ContrastChecker.contrastRatio(
            foreground: .black,
            background: .white,
            colorScheme: .light
        )
        #expect(ratio > 20.9)
        #expect(ratio <= 21.0)
    }

    @Test("White on white has ratio 1.0")
    func sameColorRatio() {
        let ratio = ContrastChecker.contrastRatio(
            foreground: .white,
            background: .white,
            colorScheme: .light
        )
        #expect(abs(ratio - 1.0) < 0.01)
    }

    @Test("Black on black has ratio 1.0")
    func sameColorBlackRatio() {
        let ratio = ContrastChecker.contrastRatio(
            foreground: .black,
            background: .black,
            colorScheme: .dark
        )
        #expect(abs(ratio - 1.0) < 0.01)
    }

    // MARK: - AA Thresholds

    @Test("Black on white passes AA normal text")
    func blackOnWhitePassesAANormal() {
        #expect(ContrastChecker.meetsAANormalText(
            foreground: .black,
            background: .white,
            colorScheme: .light
        ))
    }

    @Test("Gray 0.5 on white fails AA normal text")
    func midGrayFailsAANormal() {
        // ~4.0:1 — just below the 4.5 threshold.
        let gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1.0)
        #expect(!ContrastChecker.meetsAANormalText(
            foreground: gray,
            background: .white,
            colorScheme: .light
        ))
    }

    @Test("Gray 0.5 on white passes AA large text")
    func midGrayPassesAALarge() {
        let gray = Color(.sRGB, red: 0.5, green: 0.5, blue: 0.5, opacity: 1.0)
        #expect(ContrastChecker.meetsAALargeText(
            foreground: gray,
            background: .white,
            colorScheme: .light
        ))
    }

    // MARK: - Design Token Sweep

    @Test("Primary text over system background passes AA in dark mode")
    func primaryTextOverBackgroundDark() {
        let ratio = ContrastChecker.contrastRatio(
            foreground: LiquidColors.textPrimary,
            background: LiquidColors.background,
            colorScheme: .dark
        )
        #expect(ratio >= ContrastChecker.minimumRatioNormalText)
    }

    @Test("Primary text over system background passes AA in light mode")
    func primaryTextOverBackgroundLight() {
        let ratio = ContrastChecker.contrastRatio(
            foreground: LiquidColors.textPrimary,
            background: LiquidColors.background,
            colorScheme: .light
        )
        #expect(ratio >= ContrastChecker.minimumRatioNormalText)
    }

    @Test("Secondary text over system background meets AA in dark mode")
    func secondaryTextOverBackgroundDark() {
        let ratio = ContrastChecker.contrastRatio(
            foreground: LiquidColors.textSecondary,
            background: LiquidColors.background,
            colorScheme: .dark
        )
        // secondaryLabel over background should comfortably exceed AA.
        #expect(ratio >= ContrastChecker.minimumRatioNormalText)
    }

    // MARK: - Symmetry / Sanity

    @Test("Contrast ratio is symmetric")
    func symmetry() {
        let a = ContrastChecker.contrastRatio(
            foreground: .red,
            background: .blue,
            colorScheme: .light
        )
        let b = ContrastChecker.contrastRatio(
            foreground: .blue,
            background: .red,
            colorScheme: .light
        )
        #expect(abs(a - b) < 0.001)
    }
}
