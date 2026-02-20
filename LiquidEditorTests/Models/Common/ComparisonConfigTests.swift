import Testing
import Foundation
@testable import LiquidEditor

// MARK: - ComparisonMode Tests

@Suite("ComparisonMode Tests")
struct ComparisonModeTests {

    @Test("all raw values correct")
    func rawValues() {
        #expect(ComparisonMode.off.rawValue == "off")
        #expect(ComparisonMode.splitScreen.rawValue == "splitScreen")
        #expect(ComparisonMode.toggle.rawValue == "toggle")
        #expect(ComparisonMode.sideBySide.rawValue == "sideBySide")
    }

    @Test("Identifiable id is rawValue")
    func identifiable() {
        #expect(ComparisonMode.off.id == "off")
        #expect(ComparisonMode.splitScreen.id == "splitScreen")
    }

    @Test("displayName for all cases")
    func displayNames() {
        #expect(ComparisonMode.off.displayName == "Off")
        #expect(ComparisonMode.splitScreen.displayName == "Split Screen")
        #expect(ComparisonMode.toggle.displayName == "Toggle")
        #expect(ComparisonMode.sideBySide.displayName == "Side by Side")
    }

    @Test("CaseIterable has 4 cases")
    func allCases() {
        #expect(ComparisonMode.allCases.count == 4)
    }

    @Test("Codable round-trip for all cases")
    func codableRoundTrip() throws {
        for mode in ComparisonMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(ComparisonMode.self, from: data)
            #expect(decoded == mode)
        }
    }
}

// MARK: - ComparisonConfig Tests

@Suite("ComparisonConfig Tests")
struct ComparisonConfigTests {

    // MARK: - Creation

    @Test("creation with defaults")
    func creationDefaults() {
        let config = ComparisonConfig()
        #expect(config.mode == .off)
        #expect(config.splitPosition == 0.5)
        #expect(config.showingOriginal == false)
    }

    @Test("creation with custom values")
    func creationCustom() {
        let config = ComparisonConfig(
            mode: .splitScreen,
            splitPosition: 0.3,
            showingOriginal: true
        )
        #expect(config.mode == .splitScreen)
        #expect(config.splitPosition == 0.3)
        #expect(config.showingOriginal == true)
    }

    // MARK: - Split Position Clamping

    @Test("splitPosition clamps to 0.1 minimum")
    func splitPositionMin() {
        let config = ComparisonConfig(splitPosition: 0.0)
        #expect(config.splitPosition == 0.1)
    }

    @Test("splitPosition clamps to 0.9 maximum")
    func splitPositionMax() {
        let config = ComparisonConfig(splitPosition: 1.0)
        #expect(config.splitPosition == 0.9)
    }

    @Test("splitPosition negative clamped to 0.1")
    func splitPositionNegative() {
        let config = ComparisonConfig(splitPosition: -0.5)
        #expect(config.splitPosition == 0.1)
    }

    @Test("splitPosition within range is preserved")
    func splitPositionValid() {
        let config = ComparisonConfig(splitPosition: 0.7)
        #expect(config.splitPosition == 0.7)
    }

    // MARK: - Copy-With

    @Test("copyWith preserves unchanged fields")
    func copyWithPreserves() {
        let config = ComparisonConfig(
            mode: .toggle,
            splitPosition: 0.6,
            showingOriginal: true
        )
        let modified = config.copyWith(mode: .splitScreen)
        #expect(modified.mode == .splitScreen)
        #expect(modified.splitPosition == 0.6)
        #expect(modified.showingOriginal == true)
    }

    @Test("copyWith can override all fields")
    func copyWithOverridesAll() {
        let config = ComparisonConfig()
        let modified = config.copyWith(
            mode: .sideBySide,
            splitPosition: 0.8,
            showingOriginal: true
        )
        #expect(modified.mode == .sideBySide)
        #expect(modified.splitPosition == 0.8)
        #expect(modified.showingOriginal == true)
    }

    @Test("copyWith clamps split position")
    func copyWithClampsSplitPosition() {
        let config = ComparisonConfig()
        let modified = config.copyWith(splitPosition: 0.0)
        #expect(modified.splitPosition == 0.1)
    }

    // MARK: - Equatable

    @Test("equal configs are equal")
    func equality() {
        let a = ComparisonConfig(mode: .toggle, splitPosition: 0.5, showingOriginal: false)
        let b = ComparisonConfig(mode: .toggle, splitPosition: 0.5, showingOriginal: false)
        #expect(a == b)
    }

    @Test("different configs are not equal")
    func inequality() {
        let a = ComparisonConfig(mode: .off)
        let b = ComparisonConfig(mode: .toggle)
        #expect(a != b)
    }
}
