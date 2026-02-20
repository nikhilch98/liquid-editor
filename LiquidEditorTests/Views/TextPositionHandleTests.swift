import Testing
import CoreGraphics
@testable import LiquidEditor

// MARK: - TextPositionHandle Tests

@Suite("TextPositionHandle")
struct TextPositionHandleTests {

    @Test("Snap threshold is 0.02")
    func snapThreshold() {
        #expect(TextPositionHandle.snapThreshold == 0.02)
    }

    @Test("Position presets has 3 entries")
    func positionPresetsCount() {
        #expect(TextPositionHandle.positionPresets.count == 3)
    }

    @Test("Position presets row 2 has 3 entries")
    func positionPresetsRow2Count() {
        #expect(TextPositionHandle.positionPresetsRow2.count == 3)
    }

    @Test("Position presets include Center at (0.5, 0.5)")
    func centerPresetExists() {
        let center = TextPositionHandle.positionPresets.first { $0.0 == "Center" }
        #expect(center != nil)
        #expect(center?.1.x == 0.5)
        #expect(center?.1.y == 0.5)
    }

    @Test("Position presets include Top at (0.5, 0.15)")
    func topPresetExists() {
        let top = TextPositionHandle.positionPresets.first { $0.0 == "Top" }
        #expect(top != nil)
        #expect(top?.1.x == 0.5)
        #expect(top?.1.y == 0.15)
    }

    @Test("Position presets include Bottom at (0.5, 0.85)")
    func bottomPresetExists() {
        let bottom = TextPositionHandle.positionPresets.first { $0.0 == "Bottom" }
        #expect(bottom != nil)
        #expect(bottom?.1.x == 0.5)
        #expect(bottom?.1.y == 0.85)
    }

    @Test("Snap to horizontal center")
    func snapHorizontalCenter() {
        // x is within threshold of 0.5
        let result = applySnapStatic(x: 0.49, y: 0.3)
        #expect(result.x == 0.5)
        #expect(result.y == 0.3)
    }

    @Test("Snap to vertical center")
    func snapVerticalCenter() {
        let result = applySnapStatic(x: 0.3, y: 0.51)
        #expect(result.x == 0.3)
        #expect(result.y == 0.5)
    }

    @Test("Snap to left edge")
    func snapLeftEdge() {
        let result = applySnapStatic(x: 0.01, y: 0.5)
        #expect(result.x == 0.0)
    }

    @Test("Snap to right edge")
    func snapRightEdge() {
        let result = applySnapStatic(x: 0.99, y: 0.5)
        #expect(result.x == 1.0)
    }

    @Test("Snap to top edge")
    func snapTopEdge() {
        let result = applySnapStatic(x: 0.5, y: 0.01)
        #expect(result.y == 0.0)
    }

    @Test("Snap to bottom edge")
    func snapBottomEdge() {
        let result = applySnapStatic(x: 0.5, y: 0.99)
        #expect(result.y == 1.0)
    }

    @Test("No snap when far from guides")
    func noSnapWhenFar() {
        let result = applySnapStatic(x: 0.3, y: 0.7)
        #expect(result.x == 0.3)
        #expect(result.y == 0.7)
    }

    @Test("Snap to both center axes simultaneously")
    func snapBothAxes() {
        let result = applySnapStatic(x: 0.49, y: 0.51)
        #expect(result.x == 0.5)
        #expect(result.y == 0.5)
    }

    // MARK: - Static Snap Helper

    /// Static snap logic matching the view's implementation for testing.
    private func applySnapStatic(x: Double, y: Double) -> CGPoint {
        let threshold = TextPositionHandle.snapThreshold
        var snappedX = x
        var snappedY = y

        if abs(x - 0.5) < threshold { snappedX = 0.5 }
        if abs(y - 0.5) < threshold { snappedY = 0.5 }
        if abs(x) < threshold { snappedX = 0.0 }
        if abs(x - 1.0) < threshold { snappedX = 1.0 }
        if abs(y) < threshold { snappedY = 0.0 }
        if abs(y - 1.0) < threshold { snappedY = 1.0 }

        return CGPoint(x: snappedX, y: snappedY)
    }
}
