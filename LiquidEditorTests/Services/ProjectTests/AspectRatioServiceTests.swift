// AspectRatioServiceTests.swift
// LiquidEditorTests
//
// Tests for AspectRatioService: export dimensions, letterbox/pillarbox bars,
// zoom-to-fill scale, and translation clamping.

import Testing
import Foundation
@testable import LiquidEditor

// MARK: - Export Dimensions Tests

@Suite("AspectRatioService - exportDimensions")
struct ExportDimensionsTests {

    private let service = AspectRatioService.shared

    @Test("nil ratio returns base dimensions unchanged")
    func nilRatioPassthrough() {
        let result = service.exportDimensions(baseWidth: 1920, baseHeight: 1080, ratio: nil)
        #expect(result.width == 1920)
        #expect(result.height == 1080)
    }

    @Test("16:9 ratio with 1920x1080 base returns 1920x1080")
    func landscape16x9() {
        let result = service.exportDimensions(
            baseWidth: 1920,
            baseHeight: 1080,
            ratio: .landscape16x9
        )
        #expect(result.width == 1920)
        #expect(result.height == 1080)
    }

    @Test("9:16 vertical ratio with 1080x1920 base returns correct dimensions")
    func portrait9x16WithPortraitBase() {
        let result = service.exportDimensions(
            baseWidth: 1080,
            baseHeight: 1920,
            ratio: .portrait9x16
        )
        #expect(result.width == 1080)
        #expect(result.height == 1920)
    }

    @Test("9:16 vertical ratio with 1920x1080 landscape base constrains height")
    func portrait9x16WithLandscapeBase() {
        // targetAR = 9/16 = 0.5625
        // resWidth/resHeight = 1920/1080 = 1.778
        // targetAR < baseAR, so constrain by height: w = 1080 * 0.5625 = 607.5 -> 608
        let result = service.exportDimensions(
            baseWidth: 1920,
            baseHeight: 1080,
            ratio: .portrait9x16
        )
        #expect(result.height == 1080)
        #expect(abs(result.width - 608) <= 1)
    }

    @Test("1:1 square ratio with 1920x1080 base")
    func square1x1() {
        // targetAR = 1.0
        // baseAR = 1920/1080 = 1.778
        // targetAR < baseAR, so constrain by height: w = 1080 * 1.0 = 1080
        let result = service.exportDimensions(
            baseWidth: 1920,
            baseHeight: 1080,
            ratio: .square1x1
        )
        #expect(result.width == 1080)
        #expect(result.height == 1080)
    }

    @Test("4:3 ratio with 1920x1080 base")
    func classic4x3() {
        // targetAR = 4/3 = 1.333
        // baseAR = 1920/1080 = 1.778
        // targetAR < baseAR, so constrain by height: w = 1080 * 1.333 = 1440
        let result = service.exportDimensions(
            baseWidth: 1920,
            baseHeight: 1080,
            ratio: .classic4x3
        )
        #expect(result.height == 1080)
        #expect(abs(result.width - 1440) <= 1)
    }

    @Test("4:3 ratio with 1080x1080 square base constrains by width")
    func classic4x3WithSquareBase() {
        // targetAR = 4/3 = 1.333
        // baseAR = 1080/1080 = 1.0
        // targetAR > baseAR, so constrain by width: h = 1080 / 1.333 = 810
        let result = service.exportDimensions(
            baseWidth: 1080,
            baseHeight: 1080,
            ratio: .classic4x3
        )
        #expect(result.width == 1080)
        #expect(abs(result.height - 810) <= 1)
    }

    @Test("cinematic 2.35:1 ratio with 1920x1080 base constrains by width")
    func cinematic() {
        // targetAR = 47/20 = 2.35
        // baseAR = 1920/1080 = 1.778
        // targetAR > baseAR, so constrain by width: h = 1920 / 2.35 = 817
        let result = service.exportDimensions(
            baseWidth: 1920,
            baseHeight: 1080,
            ratio: .cinematic
        )
        #expect(result.width == 1920)
        #expect(abs(result.height - 817) <= 1)
    }
}

// MARK: - Calculate Bars Tests

@Suite("AspectRatioService - calculateBars")
struct CalculateBarsTests {

    private let service = AspectRatioService.shared

    @Test("same ratio returns zero bars")
    func sameRatioZeroBars() {
        let bars = service.calculateBars(sourceRatio: 16.0 / 9.0, targetRatio: 16.0 / 9.0)
        #expect(abs(bars.horizontal) < 0.01)
        #expect(abs(bars.vertical) < 0.01)
    }

    @Test("nearly identical ratios within tolerance return zero bars")
    func nearlyIdenticalRatios() {
        let bars = service.calculateBars(sourceRatio: 1.777, targetRatio: 1.778)
        #expect(abs(bars.horizontal) < 0.01)
        #expect(abs(bars.vertical) < 0.01)
    }

    @Test("16:9 source in 4:3 target produces letterbox (vertical) bars")
    func widerSourceLetterbox() {
        let sourceRatio = 16.0 / 9.0  // 1.778
        let targetRatio = 4.0 / 3.0   // 1.333
        let bars = service.calculateBars(sourceRatio: sourceRatio, targetRatio: targetRatio)

        // Source is wider than canvas => letterbox => vertical bars > 0, horizontal = 0
        #expect(abs(bars.horizontal) < 0.001)
        #expect(bars.vertical > 0.0)
        // scaledHeight = 1.333/1.778 = 0.7496, bar = (1-0.7496)/2 = 0.1252
        #expect(abs(bars.vertical - 0.125) < 0.01)
    }

    @Test("4:3 source in 16:9 target produces pillarbox (horizontal) bars")
    func narrowerSourcePillarbox() {
        let sourceRatio = 4.0 / 3.0   // 1.333
        let targetRatio = 16.0 / 9.0  // 1.778
        let bars = service.calculateBars(sourceRatio: sourceRatio, targetRatio: targetRatio)

        // Source is taller than canvas => pillarbox => horizontal bars > 0, vertical = 0
        #expect(bars.horizontal > 0.0)
        #expect(abs(bars.vertical) < 0.001)
        // scaledWidth = 1.333/1.778 = 0.7496, bar = (1-0.7496)/2 = 0.1252
        #expect(abs(bars.horizontal - 0.125) < 0.01)
    }

    @Test("1:1 source in 16:9 target produces pillarbox bars")
    func squareInWidescreen() {
        let bars = service.calculateBars(sourceRatio: 1.0, targetRatio: 16.0 / 9.0)

        #expect(bars.horizontal > 0.0)
        #expect(abs(bars.vertical) < 0.001)
        // scaledWidth = 1.0/1.778 = 0.5625, bar = (1-0.5625)/2 = 0.21875
        #expect(abs(bars.horizontal - 0.219) < 0.01)
    }

    @Test("9:16 source in 16:9 target produces large pillarbox bars")
    func portraitInLandscape() {
        let sourceRatio = 9.0 / 16.0  // 0.5625
        let targetRatio = 16.0 / 9.0  // 1.778
        let bars = service.calculateBars(sourceRatio: sourceRatio, targetRatio: targetRatio)

        #expect(bars.horizontal > 0.0)
        #expect(abs(bars.vertical) < 0.001)
        // scaledWidth = 0.5625/1.778 = 0.3164, bar = (1-0.3164)/2 = 0.3418
        #expect(abs(bars.horizontal - 0.342) < 0.01)
    }

    @Test("16:9 source in 1:1 target produces letterbox bars")
    func widescreenInSquare() {
        let bars = service.calculateBars(sourceRatio: 16.0 / 9.0, targetRatio: 1.0)

        #expect(abs(bars.horizontal) < 0.001)
        #expect(bars.vertical > 0.0)
        // scaledHeight = 1.0/1.778 = 0.5625, bar = (1-0.5625)/2 = 0.21875
        #expect(abs(bars.vertical - 0.219) < 0.01)
    }
}

// MARK: - Zoom to Fill Scale Tests

@Suite("AspectRatioService - zoomToFillScale")
struct ZoomToFillScaleTests {

    private let service = AspectRatioService.shared

    @Test("same ratio returns scale 1.0")
    func sameRatioScale1() {
        let scale = service.zoomToFillScale(sourceRatio: 16.0 / 9.0, targetRatio: 16.0 / 9.0)
        #expect(abs(scale - 1.0) < 0.01)
    }

    @Test("nearly identical ratios within tolerance return 1.0")
    func nearlyIdenticalRatios() {
        let scale = service.zoomToFillScale(sourceRatio: 1.777, targetRatio: 1.778)
        #expect(abs(scale - 1.0) < 0.01)
    }

    @Test("wider source in narrower target returns scale > 1.0")
    func widerSourceNarrowerTarget() {
        let sourceRatio = 16.0 / 9.0  // 1.778
        let targetRatio = 4.0 / 3.0   // 1.333
        let scale = service.zoomToFillScale(sourceRatio: sourceRatio, targetRatio: targetRatio)

        #expect(scale > 1.0)
        // source wider => sourceRatio / targetRatio = 1.778/1.333 = 1.334
        #expect(abs(scale - 1.334) < 0.01)
    }

    @Test("narrower source in wider target returns scale > 1.0")
    func narrowerSourceWiderTarget() {
        let sourceRatio = 4.0 / 3.0   // 1.333
        let targetRatio = 16.0 / 9.0  // 1.778
        let scale = service.zoomToFillScale(sourceRatio: sourceRatio, targetRatio: targetRatio)

        #expect(scale > 1.0)
        // source taller => targetRatio / sourceRatio = 1.778/1.333 = 1.334
        #expect(abs(scale - 1.334) < 0.01)
    }

    @Test("1:1 source in 16:9 target")
    func squareInWidescreen() {
        let scale = service.zoomToFillScale(sourceRatio: 1.0, targetRatio: 16.0 / 9.0)

        #expect(scale > 1.0)
        // source taller => targetRatio / sourceRatio = 1.778/1.0 = 1.778
        #expect(abs(scale - 1.778) < 0.01)
    }

    @Test("9:16 source in 16:9 target produces large scale")
    func portraitInLandscape() {
        let sourceRatio = 9.0 / 16.0  // 0.5625
        let targetRatio = 16.0 / 9.0  // 1.778
        let scale = service.zoomToFillScale(sourceRatio: sourceRatio, targetRatio: targetRatio)

        #expect(scale > 1.0)
        // source taller => targetRatio / sourceRatio = 1.778/0.5625 = 3.160
        #expect(abs(scale - 3.160) < 0.01)
    }

    @Test("scale is always at least 1.0")
    func scaleAlwaysAtLeast1() {
        let ratios: [Double] = [0.5, 0.75, 1.0, 1.333, 1.778, 2.35]
        for source in ratios {
            for target in ratios {
                let scale = service.zoomToFillScale(sourceRatio: source, targetRatio: target)
                #expect(scale >= 1.0 - 0.01, "Scale should be >= 1.0 for source=\(source), target=\(target)")
            }
        }
    }
}

// MARK: - Clamp Translation Tests

@Suite("AspectRatioService - clampTranslation")
struct ClampTranslationTests {

    private let service = AspectRatioService.shared

    @Test("zero translation returns zero")
    func zeroTranslation() {
        let result = service.clampTranslation(
            translation: 0.0,
            scale: 1.5,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: true
        )
        #expect(abs(result) < 0.001)
    }

    @Test("scale at or below 1.0 returns translation unchanged")
    func scaleAtOrBelow1() {
        let result = service.clampTranslation(
            translation: 0.4,
            scale: 1.0,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: true
        )
        #expect(abs(result - 0.4) < 0.001)
    }

    @Test("scale below 1.0 returns translation unchanged")
    func scaleBelow1() {
        let result = service.clampTranslation(
            translation: -0.3,
            scale: 0.5,
            sourceRatio: 1.0,
            targetRatio: 1.778,
            isHorizontal: false
        )
        #expect(abs(result - (-0.3)) < 0.001)
    }

    @Test("translation within bounds returns same value - horizontal wider source")
    func withinBoundsHorizontalWider() {
        // sourceRatio > targetRatio, horizontal: maxT = (scale - 1) / (2*scale)
        // scale=2.0: maxT = (2-1)/(2*2) = 0.25
        let result = service.clampTranslation(
            translation: 0.1,
            scale: 2.0,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: true
        )
        #expect(abs(result - 0.1) < 0.001)
    }

    @Test("translation exceeding positive bound is clamped - horizontal wider source")
    func exceedingPositiveBound() {
        // sourceRatio > targetRatio, horizontal: maxT = (scale - 1) / (2*scale)
        // scale=2.0: maxT = (2-1)/(2*2) = 0.25
        let result = service.clampTranslation(
            translation: 0.4,
            scale: 2.0,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: true
        )
        #expect(abs(result - 0.25) < 0.01)
    }

    @Test("translation exceeding negative bound is clamped - horizontal wider source")
    func exceedingNegativeBound() {
        // maxT = 0.25 as above; -0.4 should be clamped to -0.25
        let result = service.clampTranslation(
            translation: -0.4,
            scale: 2.0,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: true
        )
        #expect(abs(result - (-0.25)) < 0.01)
    }

    @Test("vertical clamping for wider source")
    func verticalClampWiderSource() {
        // sourceRatio > targetRatio, vertical:
        // maxT = (scale * targetRatio / sourceRatio - 1) / (2*scale)
        // scale=2.0, target=4/3=1.333, source=16/9=1.778
        // maxT = (2.0 * 1.333 / 1.778 - 1) / (2*2) = (1.4994 - 1) / 4 = 0.1249
        let result = service.clampTranslation(
            translation: 0.3,
            scale: 2.0,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: false
        )
        #expect(abs(result - 0.125) < 0.01)
    }

    @Test("horizontal clamping for narrower source")
    func horizontalClampNarrowerSource() {
        // sourceRatio < targetRatio, horizontal:
        // maxT = (scale * sourceRatio / targetRatio - 1) / (2*scale)
        // scale=2.0, source=4/3=1.333, target=16/9=1.778
        // maxT = (2.0 * 1.333 / 1.778 - 1) / (2*2) = (1.4994 - 1) / 4 = 0.1249
        let result = service.clampTranslation(
            translation: 0.3,
            scale: 2.0,
            sourceRatio: 4.0 / 3.0,
            targetRatio: 16.0 / 9.0,
            isHorizontal: true
        )
        #expect(abs(result - 0.125) < 0.01)
    }

    @Test("vertical clamping for narrower source")
    func verticalClampNarrowerSource() {
        // sourceRatio < targetRatio, vertical:
        // maxT = (scale - 1) / (2*scale)
        // scale=2.0: maxT = (2-1)/(2*2) = 0.25
        let result = service.clampTranslation(
            translation: 0.4,
            scale: 2.0,
            sourceRatio: 4.0 / 3.0,
            targetRatio: 16.0 / 9.0,
            isHorizontal: false
        )
        #expect(abs(result - 0.25) < 0.01)
    }

    @Test("clamping is symmetric for positive and negative translations")
    func symmetricClamping() {
        let positive = service.clampTranslation(
            translation: 0.5,
            scale: 1.5,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: true
        )
        let negative = service.clampTranslation(
            translation: -0.5,
            scale: 1.5,
            sourceRatio: 16.0 / 9.0,
            targetRatio: 4.0 / 3.0,
            isHorizontal: true
        )
        #expect(abs(positive + negative) < 0.001)
    }
}

// MARK: - Preset Access Tests

@Suite("AspectRatioService - Presets")
struct PresetAccessTests {

    private let service = AspectRatioService.shared

    @Test("presets returns all predefined ratios")
    func presetsCount() {
        #expect(service.presets.count == 7)
    }

    @Test("presetLabels returns correct labels")
    func presetLabels() {
        let labels = service.presetLabels
        #expect(labels.contains("16:9"))
        #expect(labels.contains("9:16"))
        #expect(labels.contains("1:1"))
        #expect(labels.contains("4:3"))
        #expect(labels.contains("3:4"))
        #expect(labels.contains("4:5"))
        #expect(labels.contains("2.35:1"))
    }

    @Test("presets and presetLabels have same count")
    func presetsAndLabelsMatch() {
        #expect(service.presets.count == service.presetLabels.count)
    }
}
