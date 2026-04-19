// ScreenshotScenarios.swift
// LiquidEditorTests
//
// I14-3: App Store screenshot scenario catalog (test-only helper).
//
// Declares a fixed catalogue of screenshot scenarios the marketing /
// submission pipeline renders for each required App Store device family.
// No actual screenshotting happens here — the catalog exists to (a) give
// the submission workflow a stable list of scenarios, and (b) let CI
// verify the list stays well-formed (unique names, non-empty metadata,
// coverage of each required device family).
//
// Keeping the catalog under `LiquidEditorTests` rather than the app
// target keeps it out of production binaries and lets it grow without
// bloating the release bundle.

import Foundation
import Testing
@testable import LiquidEditor

// MARK: - DeviceCategory

/// App-Store required device families. Each App Store submission must
/// ship at least one screenshot per category. Raw-value string is used
/// as a stable key in the export pipeline.
enum DeviceCategory: String, CaseIterable, Sendable {
    /// iPhone 6.7" — iPhone 15/16 Pro Max (primary marketing device).
    case iPhone67
    /// iPhone 6.1" — iPhone 15/16 / Pro.
    case iPhone61
    /// iPad Pro 13" — M4 iPad Pro (universal submission requirement).
    case iPadPro13
}

// MARK: - ScreenshotScenario

/// A single named screenshot configuration used by the App Store
/// submission pipeline. Marked `Sendable` so scenarios may be streamed
/// across concurrency domains during automated capture.
struct ScreenshotScenario: Sendable {
    /// Unique human-readable identifier used as the file stem.
    let name: String
    /// Device family this scenario targets.
    let deviceCategory: DeviceCategory
    /// One-line marketing description, shown in the submission tooling.
    let description: String
}

// MARK: - ScreenshotScenarioCatalog

/// Static catalogue of every screenshot scenario the submission pipeline
/// currently knows about. Keep entries App Store-ordered (hero first)
/// and ensure each `name` is unique across the list.
enum ScreenshotScenarioCatalog {
    /// Ordered list of scenarios; hero shot first, device-specific last.
    static let allScenarios: [ScreenshotScenario] = [
        // --- iPhone 6.7" hero set ---
        ScreenshotScenario(
            name: "library-empty-iphone67",
            deviceCategory: .iPhone67,
            description: "Library empty state with the Liquid Glass 'Create Project' hero CTA."
        ),
        ScreenshotScenario(
            name: "library-with-projects-iphone67",
            deviceCategory: .iPhone67,
            description: "Library populated with recent projects showing glass tiles and thumbnails."
        ),
        ScreenshotScenario(
            name: "editor-clip-selected-iphone67",
            deviceCategory: .iPhone67,
            description: "Editor with a video clip selected, showing the premium ToolStrip on the Edit tab."
        ),
        ScreenshotScenario(
            name: "inspector-color-grading-iphone67",
            deviceCategory: .iPhone67,
            description: "Inspector with the Color Grading panel open and wheels visible."
        ),
        ScreenshotScenario(
            name: "export-progress-iphone67",
            deviceCategory: .iPhone67,
            description: "Export sheet showing mid-export progress with Liquid Glass blur overlay."
        ),
        ScreenshotScenario(
            name: "timeline-multi-track-iphone67",
            deviceCategory: .iPhone67,
            description: "Timeline with multiple video + audio + text tracks and a compound clip."
        ),

        // --- iPhone 6.1" parity set ---
        ScreenshotScenario(
            name: "editor-clip-selected-iphone61",
            deviceCategory: .iPhone61,
            description: "Editor with a clip selected on iPhone 6.1\" — parity with the hero shot."
        ),

        // --- iPad Pro 13" required ---
        ScreenshotScenario(
            name: "editor-ipad-split-view",
            deviceCategory: .iPadPro13,
            description: "iPad Pro 13\" editor with NavigationSplitView showing Library and Inspector simultaneously."
        ),
        ScreenshotScenario(
            name: "export-ipad-presets",
            deviceCategory: .iPadPro13,
            description: "iPad Pro 13\" export sheet highlighting all built-in quality presets."
        ),
        ScreenshotScenario(
            name: "color-grading-ipad",
            deviceCategory: .iPadPro13,
            description: "iPad Pro 13\" full-screen color grading workspace with wheels, curves, and scopes docked."
        )
    ]
}

// MARK: - Tests

@Suite("Screenshot scenario configuration")
@MainActor
struct ScreenshotScenarioTests {

    private var catalog: [ScreenshotScenario] { ScreenshotScenarioCatalog.allScenarios }

    // MARK: - 1. Catalogue size is within the expected range

    @Test("Screenshot catalogue has 8 to 10 scenarios")
    func catalogueSizeWithinSpec() {
        #expect(catalog.count >= 8, "At least 8 scenarios required for coverage")
        #expect(catalog.count <= 10, "Cap at 10 scenarios to keep submission lightweight")
    }

    // MARK: - 2. Every scenario has a unique name

    @Test("All scenario names are unique")
    func scenarioNamesAreUnique() {
        let names = catalog.map(\.name)
        let unique = Set(names)
        #expect(names.count == unique.count, "Scenario names must be unique for file-system safety")
    }

    // MARK: - 3. Every scenario has a non-empty description & name

    @Test("Scenario names and descriptions are non-empty")
    func scenarioFieldsNonEmpty() {
        for scenario in catalog {
            #expect(!scenario.name.isEmpty, "Scenario missing name")
            #expect(!scenario.description.isEmpty,
                    "Scenario '\(scenario.name)' missing description")
        }
    }

    // MARK: - 4. Every DeviceCategory is covered

    @Test("Every DeviceCategory is covered by at least one scenario")
    func everyDeviceCategoryCovered() {
        let categories = Set(catalog.map(\.deviceCategory))
        for required in DeviceCategory.allCases {
            #expect(categories.contains(required),
                    "DeviceCategory \(required.rawValue) is not covered by any scenario")
        }
    }

    // MARK: - 5. Names are file-system safe

    @Test("Scenario names are lowercase kebab-case (file-safe)")
    func scenarioNamesAreFilesystemSafe() {
        let allowed = CharacterSet.lowercaseLetters
            .union(CharacterSet.decimalDigits)
            .union(CharacterSet(charactersIn: "-"))
        for scenario in catalog {
            let unexpected = scenario.name.unicodeScalars.filter { !allowed.contains($0) }
            #expect(unexpected.isEmpty,
                    "Scenario name '\(scenario.name)' contains disallowed characters: \(unexpected)")
        }
    }

    // MARK: - 6. Hero set covers all required marketing views

    @Test("Hero iPhone 6.7\" set covers Library / Editor / Inspector / Export / Timeline")
    func heroSetCoversMarketingFunnel() {
        let heroNames = catalog
            .filter { $0.deviceCategory == .iPhone67 }
            .map(\.name)
            .joined(separator: " ")

        #expect(heroNames.contains("library"), "Hero set missing a Library scenario")
        #expect(heroNames.contains("editor"), "Hero set missing an Editor scenario")
        #expect(heroNames.contains("inspector") || heroNames.contains("color"),
                "Hero set missing an Inspector/Color Grading scenario")
        #expect(heroNames.contains("export"), "Hero set missing an Export scenario")
        #expect(heroNames.contains("timeline"), "Hero set missing a Timeline scenario")
    }

    // MARK: - 7. DeviceCategory exhaustive case count

    @Test("DeviceCategory covers the three App Store required families")
    func deviceCategoryCaseCount() {
        #expect(DeviceCategory.allCases.count == 3,
                "Apple currently requires iPhone 6.7\", iPhone 6.1\", and iPad Pro 13\"")
        let raw = Set(DeviceCategory.allCases.map(\.rawValue))
        #expect(raw == ["iPhone67", "iPhone61", "iPadPro13"])
    }

    // MARK: - 8. iPhone 6.7" hero count is sufficient

    @Test("iPhone 6.7\" has at least 5 hero scenarios (App Store max strip)")
    func iphone67HeroScenarioCount() {
        let heroCount = catalog.filter { $0.deviceCategory == .iPhone67 }.count
        #expect(heroCount >= 5,
                "Apple allows up to 10 screenshots; ship at least 5 hero shots for the primary device")
    }

    // MARK: - 9. iPad coverage includes marketing essentials

    @Test("iPad Pro 13\" set includes at least one editor and one export scenario")
    func ipadCoversEditorAndExport() {
        let ipadNames = catalog
            .filter { $0.deviceCategory == .iPadPro13 }
            .map(\.name)
            .joined(separator: " ")

        #expect(ipadNames.contains("editor") || ipadNames.contains("color"),
                "iPad set missing an Editor/Color scenario")
        #expect(ipadNames.contains("export"), "iPad set missing an Export scenario")
    }

    // MARK: - 10. Descriptions carry enough context for reviewers

    @Test("Every scenario description is descriptive (at least 20 characters)")
    func scenarioDescriptionsAreDescriptive() {
        for scenario in catalog {
            #expect(scenario.description.count >= 20,
                    "Scenario '\(scenario.name)' description too short: '\(scenario.description)'")
        }
    }
}
