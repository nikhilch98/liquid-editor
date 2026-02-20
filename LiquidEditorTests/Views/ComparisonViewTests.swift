import Testing
import Foundation
@testable import LiquidEditor

@Suite("ComparisonView Tests")
struct ComparisonViewTests {

    // MARK: - ComparisonMode

    @Suite("ComparisonMode")
    struct ComparisonModeTests {

        @Test("displayName returns correct values for all cases")
        func displayNames() {
            #expect(ComparisonMode.off.displayName == "Off")
            #expect(ComparisonMode.splitScreen.displayName == "Split Screen")
            #expect(ComparisonMode.toggle.displayName == "Toggle")
            #expect(ComparisonMode.sideBySide.displayName == "Side by Side")
        }

        @Test("allCases contains exactly 4 modes")
        func allCasesCount() {
            #expect(ComparisonMode.allCases.count == 4)
        }

        @Test("allCases contains all expected modes")
        func allCasesContent() {
            let cases = ComparisonMode.allCases
            #expect(cases.contains(.off))
            #expect(cases.contains(.splitScreen))
            #expect(cases.contains(.toggle))
            #expect(cases.contains(.sideBySide))
        }

        @Test("id returns rawValue for each mode")
        func identifiable() {
            #expect(ComparisonMode.off.id == "off")
            #expect(ComparisonMode.splitScreen.id == "splitScreen")
            #expect(ComparisonMode.toggle.id == "toggle")
            #expect(ComparisonMode.sideBySide.id == "sideBySide")
        }

        @Test("Codable roundtrip preserves value")
        func codableRoundtrip() throws {
            for mode in ComparisonMode.allCases {
                let data = try JSONEncoder().encode(mode)
                let decoded = try JSONDecoder().decode(ComparisonMode.self, from: data)
                #expect(decoded == mode)
            }
        }
    }

    // MARK: - ComparisonConfig

    @Suite("ComparisonConfig")
    struct ComparisonConfigTests {

        @Test("Default values are correct")
        func defaults() {
            let config = ComparisonConfig()
            #expect(config.mode == .off)
            #expect(config.splitPosition == 0.5)
            #expect(config.showingOriginal == false)
        }

        @Test("splitPosition is clamped to minimum 0.1")
        func splitPositionClampedMin() {
            let config = ComparisonConfig(splitPosition: 0.0)
            #expect(config.splitPosition == 0.1)
        }

        @Test("splitPosition is clamped to maximum 0.9")
        func splitPositionClampedMax() {
            let config = ComparisonConfig(splitPosition: 1.0)
            #expect(config.splitPosition == 0.9)
        }

        @Test("splitPosition accepts values within valid range")
        func splitPositionValidRange() {
            let config = ComparisonConfig(splitPosition: 0.3)
            #expect(config.splitPosition == 0.3)
        }

        @Test("splitPosition boundary values are accepted")
        func splitPositionBoundaries() {
            let configMin = ComparisonConfig(splitPosition: 0.1)
            #expect(configMin.splitPosition == 0.1)

            let configMax = ComparisonConfig(splitPosition: 0.9)
            #expect(configMax.splitPosition == 0.9)
        }

        @Test("splitPosition negative value is clamped to 0.1")
        func splitPositionNegative() {
            let config = ComparisonConfig(splitPosition: -0.5)
            #expect(config.splitPosition == 0.1)
        }

        @Test("splitPosition value above 1.0 is clamped to 0.9")
        func splitPositionAboveOne() {
            let config = ComparisonConfig(splitPosition: 2.0)
            #expect(config.splitPosition == 0.9)
        }

        // MARK: - copyWith

        @Test("copyWith without arguments returns equal config")
        func copyWithNoArgs() {
            let original = ComparisonConfig(
                mode: .splitScreen,
                splitPosition: 0.7,
                showingOriginal: true
            )
            let copy = original.copyWith()
            #expect(copy == original)
        }

        @Test("copyWith mode changes only mode")
        func copyWithMode() {
            let original = ComparisonConfig(
                mode: .off,
                splitPosition: 0.6,
                showingOriginal: false
            )
            let updated = original.copyWith(mode: .toggle)
            #expect(updated.mode == .toggle)
            #expect(updated.splitPosition == 0.6)
            #expect(updated.showingOriginal == false)
        }

        @Test("copyWith splitPosition changes only splitPosition")
        func copyWithSplitPosition() {
            let original = ComparisonConfig(mode: .splitScreen, splitPosition: 0.5)
            let updated = original.copyWith(splitPosition: 0.3)
            #expect(updated.mode == .splitScreen)
            #expect(updated.splitPosition == 0.3)
        }

        @Test("copyWith splitPosition is clamped")
        func copyWithSplitPositionClamped() {
            let original = ComparisonConfig()
            let updated = original.copyWith(splitPosition: 0.0)
            #expect(updated.splitPosition == 0.1)

            let updated2 = original.copyWith(splitPosition: 1.0)
            #expect(updated2.splitPosition == 0.9)
        }

        @Test("copyWith showingOriginal changes only showingOriginal")
        func copyWithShowingOriginal() {
            let original = ComparisonConfig(
                mode: .toggle,
                splitPosition: 0.5,
                showingOriginal: false
            )
            let updated = original.copyWith(showingOriginal: true)
            #expect(updated.mode == .toggle)
            #expect(updated.splitPosition == 0.5)
            #expect(updated.showingOriginal == true)
        }

        @Test("copyWith all fields creates fully new config")
        func copyWithAllFields() {
            let original = ComparisonConfig()
            let updated = original.copyWith(
                mode: .sideBySide,
                splitPosition: 0.8,
                showingOriginal: true
            )
            #expect(updated.mode == .sideBySide)
            #expect(updated.splitPosition == 0.8)
            #expect(updated.showingOriginal == true)
        }

        // MARK: - Equatable

        @Test("Equal configs are equal")
        func equatableEqual() {
            let a = ComparisonConfig(mode: .splitScreen, splitPosition: 0.5, showingOriginal: false)
            let b = ComparisonConfig(mode: .splitScreen, splitPosition: 0.5, showingOriginal: false)
            #expect(a == b)
        }

        @Test("Configs with different mode are not equal")
        func equatableDifferentMode() {
            let a = ComparisonConfig(mode: .splitScreen)
            let b = ComparisonConfig(mode: .toggle)
            #expect(a != b)
        }

        @Test("Configs with different splitPosition are not equal")
        func equatableDifferentSplitPosition() {
            let a = ComparisonConfig(splitPosition: 0.3)
            let b = ComparisonConfig(splitPosition: 0.7)
            #expect(a != b)
        }

        @Test("Configs with different showingOriginal are not equal")
        func equatableDifferentShowingOriginal() {
            let a = ComparisonConfig(showingOriginal: false)
            let b = ComparisonConfig(showingOriginal: true)
            #expect(a != b)
        }
    }
}
