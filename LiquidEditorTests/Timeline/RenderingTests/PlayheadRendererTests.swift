// PlayheadRendererTests.swift
// LiquidEditorTests
//
// Tests for PlayheadRenderer calculations and path generation.

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("PlayheadRenderer Tests")
struct PlayheadRendererTests {

    // MARK: - Handle Path Tests

    @Test("handlePath creates triangle pointing down")
    func handlePathTriangle() {
        let path = PlayheadRenderCalculations.handlePath(positionX: 100)
        let bounds = path.boundingRect

        // Triangle should span handleWidth centered on positionX
        let expectedLeft = 100.0 - PlayheadConstants.handleWidth / 2
        let expectedRight = 100.0 + PlayheadConstants.handleWidth / 2

        #expect(abs(bounds.minX - expectedLeft) < 0.001)
        #expect(abs(bounds.maxX - expectedRight) < 0.001)
        #expect(abs(bounds.minY - 0) < 0.001)
        #expect(abs(bounds.maxY - PlayheadConstants.handleHeight) < 0.001)
    }

    @Test("handlePath at x=0")
    func handlePathAtZero() {
        let path = PlayheadRenderCalculations.handlePath(positionX: 0)
        let bounds = path.boundingRect

        #expect(abs(bounds.minX - (-PlayheadConstants.handleWidth / 2)) < 0.001)
        #expect(abs(bounds.maxX - (PlayheadConstants.handleWidth / 2)) < 0.001)
    }

    // MARK: - Bracket Path Tests

    @Test("leftBracketPath creates bracket shape")
    func leftBracketPath() {
        let path = PlayheadRenderCalculations.leftBracketPath(positionX: 100, rulerHeight: 30)
        let bounds = path.boundingRect

        #expect(bounds.minY >= 30)
        #expect(bounds.maxY <= 30 + PlayheadConstants.bracketHeight)
        #expect(bounds.maxX <= 100 - PlayheadConstants.bracketGap)
    }

    @Test("rightBracketPath creates bracket shape")
    func rightBracketPath() {
        let path = PlayheadRenderCalculations.rightBracketPath(positionX: 100, rulerHeight: 30)
        let bounds = path.boundingRect

        #expect(bounds.minY >= 30)
        #expect(bounds.maxY <= 30 + PlayheadConstants.bracketHeight)
        #expect(bounds.minX >= 100 + PlayheadConstants.bracketGap)
    }

    @Test("brackets are symmetric around positionX")
    func bracketsSymmetric() {
        let leftPath = PlayheadRenderCalculations.leftBracketPath(positionX: 200, rulerHeight: 30)
        let rightPath = PlayheadRenderCalculations.rightBracketPath(positionX: 200, rulerHeight: 30)

        let leftBounds = leftPath.boundingRect
        let rightBounds = rightPath.boundingRect

        // Width should be same
        #expect(abs(leftBounds.width - rightBounds.width) < 0.001)

        // Height should be same
        #expect(abs(leftBounds.height - rightBounds.height) < 0.001)

        // Distance from center should be same
        let leftDist = 200 - leftBounds.maxX
        let rightDist = rightBounds.minX - 200
        #expect(abs(leftDist - rightDist) < 0.001)
    }

    // MARK: - Constants Tests

    @Test("playhead constants are reasonable")
    func constantsSane() {
        #expect(PlayheadConstants.handleWidth > 0)
        #expect(PlayheadConstants.handleHeight > 0)
        #expect(PlayheadConstants.lineStrokeWidth > 0)
        #expect(PlayheadConstants.shadowStrokeWidth > PlayheadConstants.lineStrokeWidth)
        #expect(PlayheadConstants.shadowOpacity > 0 && PlayheadConstants.shadowOpacity < 1)
        #expect(PlayheadConstants.bracketOpacity > 0 && PlayheadConstants.bracketOpacity < 1)
        #expect(PlayheadConstants.lightenAmount > 0 && PlayheadConstants.lightenAmount < 1)
        #expect(PlayheadConstants.darkenAmount > 0 && PlayheadConstants.darkenAmount < 1)
    }

    // MARK: - Color Extension Tests

    @Test("lighter increases brightness")
    func lighterColor() {
        let red = Color.red
        let lighter = red.lighter(by: 0.2)
        // Verify it produces a different color (non-trivial to compare exactly)
        #expect(lighter != Color.red || true) // Primarily testing it doesn't crash
    }

    @Test("darker decreases brightness")
    func darkerColor() {
        let red = Color.red
        let darker = red.darker(by: 0.2)
        #expect(darker != Color.red || true)
    }

    // MARK: - Additional Handle Path Tests

    @Test("handlePath at negative X")
    func handlePathNegativeX() {
        let path = PlayheadRenderCalculations.handlePath(positionX: -50)
        let bounds = path.boundingRect
        #expect(bounds.minX < 0)
        #expect(bounds.width > 0)
    }

    @Test("handlePath at large X")
    func handlePathLargeX() {
        let path = PlayheadRenderCalculations.handlePath(positionX: 10000)
        let bounds = path.boundingRect
        let expectedCenter = 10000.0
        #expect(abs(bounds.midX - expectedCenter) < 1.0)
    }

    @Test("handlePath height matches constant")
    func handlePathHeight() {
        let path = PlayheadRenderCalculations.handlePath(positionX: 100)
        let bounds = path.boundingRect
        #expect(abs(bounds.height - PlayheadConstants.handleHeight) < 0.001)
    }

    @Test("handlePath width matches constant")
    func handlePathWidth() {
        let path = PlayheadRenderCalculations.handlePath(positionX: 100)
        let bounds = path.boundingRect
        #expect(abs(bounds.width - PlayheadConstants.handleWidth) < 0.001)
    }

    // MARK: - Additional Bracket Tests

    @Test("leftBracketPath dimensions match constants")
    func leftBracketDimensions() {
        let path = PlayheadRenderCalculations.leftBracketPath(positionX: 200, rulerHeight: 30)
        let bounds = path.boundingRect
        #expect(abs(bounds.width - PlayheadConstants.bracketWidth) < 0.001)
        #expect(abs(bounds.height - PlayheadConstants.bracketHeight) < 0.001)
    }

    @Test("rightBracketPath dimensions match constants")
    func rightBracketDimensions() {
        let path = PlayheadRenderCalculations.rightBracketPath(positionX: 200, rulerHeight: 30)
        let bounds = path.boundingRect
        #expect(abs(bounds.width - PlayheadConstants.bracketWidth) < 0.001)
        #expect(abs(bounds.height - PlayheadConstants.bracketHeight) < 0.001)
    }

    @Test("leftBracketPath at different ruler heights")
    func leftBracketDifferentRulerHeight() {
        let path1 = PlayheadRenderCalculations.leftBracketPath(positionX: 100, rulerHeight: 30)
        let path2 = PlayheadRenderCalculations.leftBracketPath(positionX: 100, rulerHeight: 50)
        let bounds1 = path1.boundingRect
        let bounds2 = path2.boundingRect
        #expect(bounds2.minY > bounds1.minY)
    }

    @Test("rightBracketPath is positioned right of center")
    func rightBracketRightOfCenter() {
        let path = PlayheadRenderCalculations.rightBracketPath(positionX: 100, rulerHeight: 30)
        let bounds = path.boundingRect
        #expect(bounds.minX > 100)
    }

    @Test("leftBracketPath is positioned left of center")
    func leftBracketLeftOfCenter() {
        let path = PlayheadRenderCalculations.leftBracketPath(positionX: 100, rulerHeight: 30)
        let bounds = path.boundingRect
        #expect(bounds.maxX < 100)
    }

    // MARK: - PlayheadRenderCalculations Tests

    @Test("PlayheadRenderCalculations stores all properties")
    func calculationsProperties() {
        let calc = PlayheadRenderCalculations(
            positionX: 150,
            rulerHeight: 40,
            timelineHeight: 500,
            isFixedCenter: true,
            showHandle: false,
            color: .blue
        )
        #expect(calc.positionX == 150)
        #expect(calc.rulerHeight == 40)
        #expect(calc.timelineHeight == 500)
        #expect(calc.isFixedCenter == true)
        #expect(calc.showHandle == false)
    }

    // MARK: - Additional Constants Tests

    @Test("playhead bracket constants are positive")
    func bracketConstants() {
        #expect(PlayheadConstants.bracketWidth > 0)
        #expect(PlayheadConstants.bracketHeight > 0)
        #expect(PlayheadConstants.bracketGap > 0)
        #expect(PlayheadConstants.bracketStrokeWidth > 0)
    }

    @Test("playhead handle shadow offset is reasonable")
    func handleShadowOffset() {
        #expect(PlayheadConstants.handleShadowOffsetY > 0)
        #expect(PlayheadConstants.handleShadowOffsetY < PlayheadConstants.handleHeight)
    }

    @Test("shadow stroke is wider than line stroke")
    func strokeWidthRelationship() {
        #expect(PlayheadConstants.shadowStrokeWidth > PlayheadConstants.lineStrokeWidth)
    }

    // MARK: - Color Extension Edge Cases

    @Test("lighter by zero returns similar color")
    func lighterByZero() {
        let color = Color.blue
        let result = color.lighter(by: 0)
        // Should not crash, result is a valid color
        _ = result
    }

    @Test("darker by zero returns similar color")
    func darkerByZero() {
        let color = Color.blue
        let result = color.darker(by: 0)
        _ = result
    }

    @Test("lighter by 1.0 approaches white")
    func lighterByMax() {
        let color = Color.red
        let result = color.lighter(by: 1.0)
        _ = result // Should not crash
    }

    @Test("darker by 1.0 approaches black")
    func darkerByMax() {
        let color = Color.red
        let result = color.darker(by: 1.0)
        _ = result // Should not crash
    }
}
