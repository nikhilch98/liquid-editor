// PremiumTokenTests.swift
// LiquidEditorTests

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("Premium Token Tests")
struct PremiumTokenTests {

    @Test("LiquidColors.Canvas tokens resolve to their spec hex values")
    @MainActor
    func canvasTokensMatchSpec() {
        // Canvas.base = #07070A
        #expect(LiquidColors.Canvas.base.resolvedComponents() == (7, 7, 10))
        // Canvas.raised = #0F0F12
        #expect(LiquidColors.Canvas.raised.resolvedComponents() == (15, 15, 18))
    }

    @Test("LiquidColors.Text tokens resolve to their spec hex values")
    @MainActor
    func textTokensMatchSpec() {
        // Text.primary = #F3EEE6
        #expect(LiquidColors.Text.primary.resolvedComponents() == (243, 238, 230))
        // Text.secondary = #9C9A93
        #expect(LiquidColors.Text.secondary.resolvedComponents() == (156, 154, 147))
        // Text.tertiary = #5A5852
        #expect(LiquidColors.Text.tertiary.resolvedComponents() == (90, 88, 82))
        // Text.onAccent = #07070A
        #expect(LiquidColors.Text.onAccent.resolvedComponents() == (7, 7, 10))
    }

    @Test("LiquidColors.Accent tokens match spec")
    @MainActor
    func accentTokensMatchSpec() {
        // Accent.amber = #E6B340
        #expect(LiquidColors.Accent.amber.resolvedComponents() == (230, 179, 64))
        // Accent.destructive = #E5534A
        #expect(LiquidColors.Accent.destructive.resolvedComponents() == (229, 83, 74))
    }

    @Test("LiquidTypography premium scale is defined")
    func premiumTypographyScaleExists() {
        // This test compiles only if all the nested Font accessors exist.
        // Font doesn't expose point-size introspection, so a compile-time
        // smoke test is sufficient.
        let fonts: [Font] = [
            LiquidTypography.Display.font,
            LiquidTypography.Title.font,
            LiquidTypography.Body.font,
            LiquidTypography.Caption.font,
            LiquidTypography.Mono.font,
            LiquidTypography.MonoLarge.font,
        ]
        #expect(fonts.count == 6)
    }

    @Test("Material / elevation / radius / stroke tokens compile")
    @MainActor
    func auxiliaryTokensExist() {
        _ = LiquidMaterials.chrome
        _ = LiquidMaterials.float
        _ = LiquidElevation.floatSm
        _ = LiquidElevation.floatMd
        _ = LiquidElevation.floatLg
        #expect(LiquidRadius.sm == 6)
        #expect(LiquidRadius.md == 10)
        #expect(LiquidRadius.lg == 16)
        #expect(LiquidRadius.xl == 22)
        #expect(LiquidRadius.full == 999)
        #expect(LiquidStroke.hairlineWidth == 0.5)
        #expect(LiquidStroke.activeWidth == 1.5)
    }

    @Test("Motion tokens compile and evaluate")
    func motionTokensExist() {
        let anims: [Animation] = [
            LiquidMotion.snap,
            LiquidMotion.smooth,
            LiquidMotion.bounce,
            LiquidMotion.glide,
            LiquidMotion.easeOut,
        ]
        #expect(anims.count == 5)
    }

    @Test("FormFactor picks compact / regular based on min dimension")
    func formFactorThreshold() {
        #expect(FormFactor(canvasSize: CGSize(width: 375, height: 800)) == .compact)
        #expect(FormFactor(canvasSize: CGSize(width: 820, height: 1180)) == .regular)
        // Edge: split-view iPad at 500 pt wide still counts as compact
        #expect(FormFactor(canvasSize: CGSize(width: 500, height: 1180)) == .compact)
    }

    @Test("FormFactor size tokens scale per spec")
    func formFactorSizeTokens() {
        #expect(FormFactor.compact.toolButtonWidth == 48)
        #expect(FormFactor.regular.toolButtonWidth == 52)
        #expect(FormFactor.compact.trackLaneHeight == 56)
        #expect(FormFactor.regular.trackLaneHeight == 72)
    }
}

// MARK: - Test helper

private extension Color {
    /// Returns the (r, g, b) components of a Color as 0-255 ints.
    /// Used by the premium-token tests to confirm hex values survive.
    @MainActor
    func resolvedComponents() -> (Int, Int, Int) {
        let resolved = self.resolve(in: EnvironmentValues())
        let r = Int((resolved.red * 255).rounded())
        let g = Int((resolved.green * 255).rounded())
        let b = Int((resolved.blue * 255).rounded())
        return (r, g, b)
    }
}
