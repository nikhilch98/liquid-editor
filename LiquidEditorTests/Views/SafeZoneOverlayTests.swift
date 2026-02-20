import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("SafeZoneOverlay Tests")
struct SafeZoneOverlayTests {

    // MARK: - SafeZonePreset

    @Suite("SafeZonePreset")
    struct PresetTests {

        @Test("displayName returns correct values for all cases")
        func displayNames() {
            #expect(SafeZonePreset.titleSafe.displayName == "Title Safe")
            #expect(SafeZonePreset.actionSafe.displayName == "Action Safe")
            #expect(SafeZonePreset.tikTok.displayName == "TikTok")
            #expect(SafeZonePreset.instagramReels.displayName == "Instagram Reels")
            #expect(SafeZonePreset.youTubeShorts.displayName == "YouTube Shorts")
            #expect(SafeZonePreset.broadcast.displayName == "Broadcast")
            #expect(SafeZonePreset.custom.displayName == "Custom")
        }

        @Test("shortLabel returns abbreviated names")
        func shortLabels() {
            #expect(SafeZonePreset.instagramReels.shortLabel == "IG Reels")
            #expect(SafeZonePreset.youTubeShorts.shortLabel == "YT Shorts")
            #expect(SafeZonePreset.titleSafe.shortLabel == "Title Safe")
        }

        @Test("allCases contains 7 presets")
        func allCasesCount() {
            #expect(SafeZonePreset.allCases.count == 7)
        }

        @Test("id equals rawValue")
        func identifiable() {
            for preset in SafeZonePreset.allCases {
                #expect(preset.id == preset.rawValue)
            }
        }

        @Test("Codable roundtrip preserves value")
        func codableRoundtrip() throws {
            for preset in SafeZonePreset.allCases {
                let data = try JSONEncoder().encode(preset)
                let decoded = try JSONDecoder().decode(SafeZonePreset.self, from: data)
                #expect(decoded == preset)
            }
        }
    }

    // MARK: - SafeZoneConfig

    @Suite("SafeZoneConfig")
    struct ConfigTests {

        @Test("Default values are correct")
        func defaults() {
            let config = SafeZoneConfig()
            #expect(config.activeZones.isEmpty)
            #expect(config.customTopPercent == 10.0)
            #expect(config.customBottomPercent == 10.0)
            #expect(config.customLeftPercent == 10.0)
            #expect(config.customRightPercent == 10.0)
            #expect(config.showLabels == true)
        }

        @Test("Equatable works for identical configs")
        func equality() {
            let a = SafeZoneConfig()
            let b = SafeZoneConfig()
            #expect(a == b)
        }

        @Test("Equatable detects different active zones")
        func inequalityZones() {
            let a = SafeZoneConfig()
            var b = SafeZoneConfig()
            b.activeZones = [.titleSafe]
            #expect(a != b)
        }
    }

    // MARK: - SafeZoneCalculator

    @Suite("SafeZoneCalculator")
    struct CalculatorTests {

        let testSize = CGSize(width: 1920, height: 1080)

        @Test("Title safe zone uses 10% insets")
        func titleSafeInsets() {
            let insets = SafeZoneCalculator.insets(for: .titleSafe, in: testSize)
            #expect(abs(insets.top - 108) < 0.01)
            #expect(abs(insets.bottom - 108) < 0.01)
            #expect(abs(insets.left - 192) < 0.01)
            #expect(abs(insets.right - 192) < 0.01)
        }

        @Test("Action safe zone uses 5% insets")
        func actionSafeInsets() {
            let insets = SafeZoneCalculator.insets(for: .actionSafe, in: testSize)
            #expect(abs(insets.top - 54) < 0.01)
            #expect(abs(insets.bottom - 54) < 0.01)
            #expect(abs(insets.left - 96) < 0.01)
            #expect(abs(insets.right - 96) < 0.01)
        }

        @Test("TikTok has asymmetric vertical insets (top 15%, bottom 25%)")
        func tikTokInsets() {
            let insets = SafeZoneCalculator.insets(for: .tikTok, in: testSize)
            #expect(abs(insets.top - 162) < 0.01)    // 15%
            #expect(abs(insets.bottom - 270) < 0.01)  // 25%
            #expect(abs(insets.left - 96) < 0.01)     // 5%
            #expect(abs(insets.right - 96) < 0.01)    // 5%
        }

        @Test("Instagram Reels has asymmetric vertical insets (top 12%, bottom 20%)")
        func instagramReelsInsets() {
            let insets = SafeZoneCalculator.insets(for: .instagramReels, in: testSize)
            #expect(abs(insets.top - 129.6) < 0.01)   // 12%
            #expect(abs(insets.bottom - 216) < 0.01)   // 20%
        }

        @Test("YouTube Shorts has asymmetric vertical insets (top 10%, bottom 15%)")
        func youTubeShortsInsets() {
            let insets = SafeZoneCalculator.insets(for: .youTubeShorts, in: testSize)
            #expect(abs(insets.top - 108) < 0.01)     // 10%
            #expect(abs(insets.bottom - 162) < 0.01)   // 15%
        }

        @Test("Broadcast zone matches title safe (10%)")
        func broadcastInsets() {
            let broadcastInsets = SafeZoneCalculator.insets(for: .broadcast, in: testSize)
            let titleSafeInsets = SafeZoneCalculator.insets(for: .titleSafe, in: testSize)
            #expect(broadcastInsets == titleSafeInsets)
        }

        @Test("Custom zone respects config percentages")
        func customInsets() {
            var config = SafeZoneConfig()
            config.customTopPercent = 20.0
            config.customBottomPercent = 30.0
            config.customLeftPercent = 5.0
            config.customRightPercent = 15.0

            let insets = SafeZoneCalculator.insets(for: .custom, in: testSize, config: config)
            #expect(abs(insets.top - 216) < 0.01)    // 20% of 1080
            #expect(abs(insets.bottom - 324) < 0.01)  // 30% of 1080
            #expect(abs(insets.left - 96) < 0.01)     // 5% of 1920
            #expect(abs(insets.right - 288) < 0.01)   // 15% of 1920
        }

        @Test("Zero-size produces zero insets")
        func zeroSize() {
            let insets = SafeZoneCalculator.insets(for: .titleSafe, in: .zero)
            #expect(insets.top == 0)
            #expect(insets.left == 0)
            #expect(insets.bottom == 0)
            #expect(insets.right == 0)
        }

        @Test("Each preset has a unique color")
        func uniqueColors() {
            // Verify colors are different (by string representation at minimum)
            var colorStrings = Set<String>()
            for preset in SafeZonePreset.allCases {
                let desc = String(describing: SafeZoneCalculator.color(for: preset))
                colorStrings.insert(desc)
            }
            #expect(colorStrings.count == SafeZonePreset.allCases.count)
        }
    }
}
