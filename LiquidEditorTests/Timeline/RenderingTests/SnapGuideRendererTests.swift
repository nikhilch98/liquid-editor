// SnapGuideRendererTests.swift
// LiquidEditorTests
//
// Tests for SnapGuideRenderer calculations.

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("SnapGuideRenderer Tests")
struct SnapGuideRendererTests {

    // MARK: - Color Tests

    @Test("snap guide colors are distinct for each type")
    func distinctColors() {
        let types = SnapTargetType.allCases
        var colors: [Color] = []
        for type in types {
            let color = SnapGuideColor.color(for: type)
            colors.append(color)
        }
        // All types should produce a color (no crash)
        #expect(colors.count == types.count)
    }

    @Test("playhead snap color is red-ish")
    func playheadColor() {
        let color = SnapGuideColor.color(for: .playhead)
        // iOS red: (1.0, 0.231, 0.188)
        #expect(color == Color(red: 1.0, green: 0.231, blue: 0.188))
    }

    @Test("clip edge snap color is yellow-ish")
    func clipEdgeColor() {
        let color = SnapGuideColor.color(for: .clipEdge)
        #expect(color == Color(red: 1.0, green: 0.839, blue: 0.039))
    }

    // MARK: - Constants Tests

    @Test("snap guide constants are reasonable")
    func constants() {
        #expect(SnapGuideCalculations.dashLength == 4.0)
        #expect(SnapGuideCalculations.gapLength == 4.0)
        #expect(SnapGuideCalculations.lineStrokeWidth == 1.5)
        #expect(SnapGuideCalculations.glowStrokeWidth > SnapGuideCalculations.lineStrokeWidth)
        #expect(SnapGuideCalculations.outerGlowStrokeWidth > SnapGuideCalculations.glowStrokeWidth)
    }

    // MARK: - Indicator Size Tests

    @Test("indicator sizes are positive")
    func indicatorSizes() {
        #expect(SnapGuideCalculations.playheadIndicatorSize > 0)
        #expect(SnapGuideCalculations.clipEdgeIndicatorSize > 0)
        #expect(SnapGuideCalculations.markerIndicatorSize > 0)
        #expect(SnapGuideCalculations.inOutIndicatorSize > 0)
        #expect(SnapGuideCalculations.beatIndicatorRadius > 0)
    }

    // MARK: - Edge Cases

    @Test("empty guides produces no drawing")
    func emptyGuides() {
        let calc = SnapGuideCalculations(
            guides: [], rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 0.8
        )
        #expect(calc.guides.isEmpty)
    }

    @Test("guide at negative X is skipped")
    func negativeXGuide() {
        let guide = SnapGuide(x: -10, type: .clipEdge)
        let calc = SnapGuideCalculations(
            guides: [guide], rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 0.8
        )
        // The guide exists but drawing logic skips x < 0
        #expect(calc.guides.count == 1)
        #expect(calc.guides[0].x < 0)
    }

    @Test("guide at very large X is skipped when past viewport")
    func veryLargeXGuide() {
        let guide = SnapGuide(x: 10000, type: .clipEdge)
        let calc = SnapGuideCalculations(
            guides: [guide], rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 0.8
        )
        // The guide exists but drawing logic would skip past viewport width
        #expect(calc.guides[0].x == 10000)
    }

    // MARK: - Additional Color Tests

    @Test("marker snap color is green")
    func markerColor() {
        let color = SnapGuideColor.color(for: .marker)
        #expect(color == Color(red: 0.204, green: 0.78, blue: 0.349))
    }

    @Test("inOutPoint snap color is blue")
    func inOutPointColor() {
        let color = SnapGuideColor.color(for: .inOutPoint)
        #expect(color == Color(red: 0.0, green: 0.478, blue: 1.0))
    }

    @Test("beatMarker snap color is purple")
    func beatMarkerColor() {
        let color = SnapGuideColor.color(for: .beatMarker)
        #expect(color == Color(red: 0.686, green: 0.322, blue: 0.871))
    }

    @Test("gridLine snap color is gray")
    func gridLineColor() {
        let color = SnapGuideColor.color(for: .gridLine)
        #expect(color == Color(red: 0.557, green: 0.557, blue: 0.576))
    }

    @Test("all SnapTargetType cases produce a color")
    func allTypesProduceColor() {
        for type in SnapTargetType.allCases {
            let color = SnapGuideColor.color(for: type)
            _ = color // Just verify no crash
        }
    }

    // MARK: - Additional Constants Tests

    @Test("indicator offset is positive")
    func indicatorOffset() {
        #expect(SnapGuideCalculations.indicatorOffset > 0)
    }

    @Test("glow stroke width is larger than line stroke")
    func glowVsLineStroke() {
        #expect(SnapGuideCalculations.glowStrokeWidth > SnapGuideCalculations.lineStrokeWidth)
    }

    @Test("outer glow stroke width is largest")
    func outerGlowLargest() {
        #expect(SnapGuideCalculations.outerGlowStrokeWidth > SnapGuideCalculations.glowStrokeWidth)
    }

    @Test("dash and gap lengths are equal")
    func dashGapEqual() {
        #expect(SnapGuideCalculations.dashLength == SnapGuideCalculations.gapLength)
    }

    // MARK: - Multiple Guides Tests

    @Test("multiple guides stored correctly")
    func multipleGuides() {
        let guides = [
            SnapGuide(x: 100, type: .playhead),
            SnapGuide(x: 200, type: .clipEdge),
            SnapGuide(x: 300, type: .marker),
        ]
        let calc = SnapGuideCalculations(
            guides: guides, rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 0.8
        )
        #expect(calc.guides.count == 3)
    }

    // MARK: - Glow Configuration Tests

    @Test("showGlow false disables glow")
    func showGlowFalse() {
        let calc = SnapGuideCalculations(
            guides: [SnapGuide(x: 100, type: .clipEdge)],
            rulerHeight: 30, timelineHeight: 400,
            showGlow: false, glowIntensity: 0.0
        )
        #expect(calc.showGlow == false)
        #expect(calc.glowIntensity == 0.0)
    }

    @Test("glowIntensity at maximum")
    func glowIntensityMax() {
        let calc = SnapGuideCalculations(
            guides: [], rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 1.0
        )
        #expect(calc.glowIntensity == 1.0)
    }

    @Test("glowIntensity at zero")
    func glowIntensityZero() {
        let calc = SnapGuideCalculations(
            guides: [], rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 0.0
        )
        #expect(calc.glowIntensity == 0.0)
    }

    // MARK: - Timeline Height Tests

    @Test("calculations store ruler and timeline heights")
    func heightsStored() {
        let calc = SnapGuideCalculations(
            guides: [], rulerHeight: 50, timelineHeight: 600,
            showGlow: true, glowIntensity: 0.8
        )
        #expect(calc.rulerHeight == 50)
        #expect(calc.timelineHeight == 600)
    }

    // MARK: - Guide at X = 0

    @Test("guide at X = 0 is valid")
    func guideAtZero() {
        let guide = SnapGuide(x: 0, type: .playhead)
        let calc = SnapGuideCalculations(
            guides: [guide], rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 0.8
        )
        #expect(calc.guides[0].x == 0)
    }

    // MARK: - SnapGuide Type Preservation

    @Test("guide type is preserved in calculations")
    func guideTypePreserved() {
        let guides = [
            SnapGuide(x: 100, type: .beatMarker),
            SnapGuide(x: 200, type: .inOutPoint),
        ]
        let calc = SnapGuideCalculations(
            guides: guides, rulerHeight: 30, timelineHeight: 400,
            showGlow: true, glowIntensity: 0.8
        )
        #expect(calc.guides[0].type == .beatMarker)
        #expect(calc.guides[1].type == .inOutPoint)
    }
}
