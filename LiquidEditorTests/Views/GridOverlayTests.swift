import Testing
import Foundation
@testable import LiquidEditor

@Suite("GridOverlay Tests")
struct GridOverlayTests {

    // MARK: - GridType

    @Suite("GridType")
    struct GridTypeTests {

        @Test("displayName returns correct values for all cases")
        func displayNames() {
            #expect(GridType.ruleOfThirds.displayName == "Rule of Thirds")
            #expect(GridType.goldenRatio.displayName == "Golden Ratio")
            #expect(GridType.centerCross.displayName == "Center Cross")
            #expect(GridType.diagonal.displayName == "Diagonal")
            #expect(GridType.squareGrid.displayName == "Square Grid")
            #expect(GridType.custom.displayName == "Custom")
        }

        @Test("allCases contains all 6 grid types")
        func allCasesCount() {
            #expect(GridType.allCases.count == 6)
        }

        @Test("id equals rawValue for all cases")
        func identifiable() {
            for type in GridType.allCases {
                #expect(type.id == type.rawValue)
            }
        }

        @Test("Codable roundtrip preserves value")
        func codableRoundtrip() throws {
            for type in GridType.allCases {
                let data = try JSONEncoder().encode(type)
                let decoded = try JSONDecoder().decode(GridType.self, from: data)
                #expect(decoded == type)
            }
        }
    }

    // MARK: - GridOverlayConfig

    @Suite("GridOverlayConfig")
    struct ConfigTests {

        @Test("Default values are correct")
        func defaults() {
            let config = GridOverlayConfig()
            #expect(config.type == .ruleOfThirds)
            #expect(config.isVisible == false)
            #expect(config.opacity == 0.5)
            #expect(config.lineWidth == 0.5)
            #expect(config.customRows == 3)
            #expect(config.customColumns == 3)
        }

        @Test("Equatable works for identical configs")
        func equality() {
            let a = GridOverlayConfig()
            let b = GridOverlayConfig()
            #expect(a == b)
        }

        @Test("Equatable detects differences")
        func inequality() {
            var modified = GridOverlayConfig()
            modified.type = .diagonal
            #expect(modified != GridOverlayConfig())
        }
    }

    // MARK: - GridLineCalculator

    @Suite("GridLineCalculator")
    struct CalculatorTests {

        @Test("Vertical line positions for 3 columns (rule of thirds)")
        func verticalThirds() {
            let positions = GridLineCalculator.verticalLinePositions(width: 300, columns: 3)
            #expect(positions.count == 2)
            #expect(abs(positions[0] - 100) < 0.001)
            #expect(abs(positions[1] - 200) < 0.001)
        }

        @Test("Horizontal line positions for 3 rows (rule of thirds)")
        func horizontalThirds() {
            let positions = GridLineCalculator.horizontalLinePositions(height: 300, rows: 3)
            #expect(positions.count == 2)
            #expect(abs(positions[0] - 100) < 0.001)
            #expect(abs(positions[1] - 200) < 0.001)
        }

        @Test("Vertical line positions for 4 columns (square grid)")
        func verticalSquareGrid() {
            let positions = GridLineCalculator.verticalLinePositions(width: 400, columns: 4)
            #expect(positions.count == 3)
            #expect(abs(positions[0] - 100) < 0.001)
            #expect(abs(positions[1] - 200) < 0.001)
            #expect(abs(positions[2] - 300) < 0.001)
        }

        @Test("Custom grid with 5 columns produces 4 lines")
        func customFiveColumns() {
            let positions = GridLineCalculator.verticalLinePositions(width: 500, columns: 5)
            #expect(positions.count == 4)
        }

        @Test("1 column produces 0 lines")
        func singleColumnNoLines() {
            let positions = GridLineCalculator.verticalLinePositions(width: 300, columns: 1)
            #expect(positions.isEmpty)
        }

        @Test("Golden ratio positions are symmetric around center")
        func goldenRatioSymmetry() {
            let positions = GridLineCalculator.goldenRatioPositions(length: 1000)
            #expect(positions.count == 2)
            // phi ~ 0.381966
            #expect(abs(positions[0] - 381.966) < 0.1)
            #expect(abs(positions[1] - 618.034) < 0.1)
            // Sum should equal the length
            #expect(abs(positions[0] + positions[1] - 1000) < 0.1)
        }

        @Test("Center position is half the length")
        func centerPosition() {
            #expect(GridLineCalculator.centerPosition(length: 400) == 200)
            #expect(GridLineCalculator.centerPosition(length: 0) == 0)
        }

        @Test("Zero width produces no vertical lines")
        func zeroWidth() {
            let positions = GridLineCalculator.verticalLinePositions(width: 0, columns: 3)
            #expect(positions.count == 2) // Positions exist but at 0
            #expect(positions[0] == 0)
        }
    }
}
