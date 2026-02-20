import Testing
import Foundation
import CoreGraphics
@testable import LiquidEditor

@Suite("AutoReframePanel Tests")
struct AutoReframePanelTests {

    // MARK: - AutoReframeConfig Defaults

    @Suite("AutoReframeConfig Defaults")
    struct ConfigDefaultsTests {

        @Test("Default config has expected values")
        func defaultValues() {
            let config = AutoReframeConfig()
            #expect(config.zoomIntensity == 1.2)
            #expect(config.followSpeed == 0.3)
            #expect(config.safeZonePadding == 0.1)
            #expect(config.maxZoom == 3.0)
            #expect(config.minZoom == 1.0)
            #expect(config.targetAspectRatio == nil)
            #expect(config.framingStyle == .centered)
            #expect(config.lookaheadMs == 150)
        }
    }

    // MARK: - AutoReframeConfig Copy

    @Suite("AutoReframeConfig Copy")
    struct ConfigCopyTests {

        @Test("Copy with zoomIntensity override")
        func copyZoomIntensity() {
            let config = AutoReframeConfig()
            let modified = config.with(zoomIntensity: 2.0)
            #expect(modified.zoomIntensity == 2.0)
            #expect(modified.followSpeed == config.followSpeed)
            #expect(modified.safeZonePadding == config.safeZonePadding)
        }

        @Test("Copy with followSpeed override")
        func copyFollowSpeed() {
            let config = AutoReframeConfig()
            let modified = config.with(followSpeed: 0.8)
            #expect(modified.followSpeed == 0.8)
        }

        @Test("Copy with safeZonePadding override")
        func copySafeZone() {
            let config = AutoReframeConfig()
            let modified = config.with(safeZonePadding: 0.25)
            #expect(modified.safeZonePadding == 0.25)
        }

        @Test("Copy with framingStyle override")
        func copyFramingStyle() {
            let config = AutoReframeConfig()
            let modified = config.with(framingStyle: .ruleOfThirds)
            #expect(modified.framingStyle == .ruleOfThirds)
        }

        @Test("Copy with lookaheadMs override")
        func copyLookahead() {
            let config = AutoReframeConfig()
            let modified = config.with(lookaheadMs: 300)
            #expect(modified.lookaheadMs == 300)
        }

        @Test("Copy preserves unchanged fields")
        func copyPreserves() {
            let custom = AutoReframeConfig(
                zoomIntensity: 1.8,
                followSpeed: 0.5,
                safeZonePadding: 0.2,
                maxZoom: 2.5,
                minZoom: 1.2,
                framingStyle: .ruleOfThirds,
                lookaheadMs: 200
            )
            let modified = custom.with(zoomIntensity: 2.0)
            #expect(modified.zoomIntensity == 2.0)
            #expect(modified.followSpeed == 0.5)
            #expect(modified.safeZonePadding == 0.2)
            #expect(modified.maxZoom == 2.5)
            #expect(modified.minZoom == 1.2)
            #expect(modified.framingStyle == .ruleOfThirds)
            #expect(modified.lookaheadMs == 200)
        }
    }

    // MARK: - FramingStyle

    @Suite("FramingStyle")
    struct FramingStyleTests {

        @Test("All framing styles exist")
        func allCases() {
            let cases = FramingStyle.allCases
            #expect(cases.count == 2)
            #expect(cases.contains(.centered))
            #expect(cases.contains(.ruleOfThirds))
        }

        @Test("Framing style raw values")
        func rawValues() {
            #expect(FramingStyle.centered.rawValue == "centered")
            #expect(FramingStyle.ruleOfThirds.rawValue == "ruleOfThirds")
        }

        @Test("Codable roundtrip")
        func codableRoundtrip() throws {
            for style in FramingStyle.allCases {
                let data = try JSONEncoder().encode(style)
                let decoded = try JSONDecoder().decode(FramingStyle.self, from: data)
                #expect(decoded == style)
            }
        }
    }

    // MARK: - Follow Speed Label Logic

    @Suite("Follow Speed Label")
    struct FollowSpeedLabelTests {

        private func followSpeedLabel(for speed: Double) -> String {
            if speed < 0.3 { return "Smooth" }
            if speed > 0.7 { return "Fast" }
            return "Normal"
        }

        @Test("Low speed shows Smooth")
        func lowSpeed() {
            #expect(followSpeedLabel(for: 0.1) == "Smooth")
        }

        @Test("Medium speed shows Normal")
        func mediumSpeed() {
            #expect(followSpeedLabel(for: 0.5) == "Normal")
        }

        @Test("High speed shows Fast")
        func highSpeed() {
            #expect(followSpeedLabel(for: 0.9) == "Fast")
        }

        @Test("Boundary 0.3 shows Normal")
        func boundary03() {
            #expect(followSpeedLabel(for: 0.3) == "Normal")
        }

        @Test("Boundary 0.7 shows Normal")
        func boundary07() {
            #expect(followSpeedLabel(for: 0.7) == "Normal")
        }
    }

    // MARK: - Slider Ranges

    @Suite("Slider Ranges")
    struct SliderRangesTests {

        @Test("Zoom intensity range 0.8 to 2.5")
        func zoomRange() {
            let config = AutoReframeConfig()
            #expect(config.zoomIntensity >= 0.8)
            #expect(config.zoomIntensity <= 2.5)
        }

        @Test("Follow speed range 0.05 to 1.0")
        func followSpeedRange() {
            let config = AutoReframeConfig()
            #expect(config.followSpeed >= 0.05)
            #expect(config.followSpeed <= 1.0)
        }

        @Test("Safe zone padding range 0.0 to 0.3")
        func safeZoneRange() {
            let config = AutoReframeConfig()
            #expect(config.safeZonePadding >= 0.0)
            #expect(config.safeZonePadding <= 0.3)
        }

        @Test("Lookahead range 0 to 500")
        func lookaheadRange() {
            let config = AutoReframeConfig()
            #expect(config.lookaheadMs >= 0)
            #expect(config.lookaheadMs <= 500)
        }
    }

    // MARK: - Config Codable

    @Suite("Config Codable")
    struct ConfigCodableTests {

        @Test("AutoReframeConfig encodes and decodes correctly")
        func configRoundtrip() throws {
            let config = AutoReframeConfig(
                zoomIntensity: 1.8,
                followSpeed: 0.5,
                safeZonePadding: 0.2,
                framingStyle: .ruleOfThirds,
                lookaheadMs: 200
            )

            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(AutoReframeConfig.self, from: data)

            #expect(decoded == config)
        }
    }
}
