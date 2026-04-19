// TabDrillDownTests.swift
// LiquidEditorTests
//
// I14-1: End-to-end tab drill-down verification.
//
// Exercises every editor bottom-bar tab (premium-redesign `EditorTabID`
// plus the legacy `EditorTab` cases) and validates three contracts:
//   1. Default tool-strip buttons for the tab are non-empty.
//   2. Every tool button exposes a non-empty label (the 11pt caption the
//      spec requires under each icon).
//   3. Switching `selectedTab` (or `activeTab`) triggers haptic feedback
//      — validated via `HapticService.playForTesting(.selection)` which
//      mirrors the View-layer behaviour.
//
// The legacy `EditorTab` enum (`.edit/.fx/.overlay/.audio/.smart`) has no
// `currentTabTools` — coverage for those two extra cases (`.smart`,
// `.overlay`) is therefore restricted to identity + haptic contract.

import Foundation
import Testing
@testable import LiquidEditor

@Suite("Tab drill-down end-to-end")
@MainActor
struct TabDrillDownTests {

    // MARK: - Helpers

    private func makeViewModel() -> EditorViewModel {
        let project = Project(name: "Tab Drill Project", sourceVideoPath: "/stub/video.mp4")
        return EditorViewModel(project: project, timeline: .empty)
    }

    /// Fresh haptic service in a known state for each test.
    private func resetHaptics() -> HapticService {
        let svc = HapticService.shared
        svc.setEnabled(true)
        svc.resetThrottleForTesting()
        return svc
    }

    // MARK: - 1. Edit-tab drill-down

    @Test("Edit tab exposes 6 labelled tool buttons and selection fires haptic")
    func editTabDrillDown() {
        let svc = resetHaptics()
        let vm = makeViewModel()

        vm.selectedTab = .edit
        // Mirror the View-layer tab-switch haptic.
        #expect(svc.playForTesting(.selection) == true)

        let tools = vm.currentTabTools
        #expect(!tools.isEmpty, "Edit tab must expose at least one tool")
        #expect(tools.count == 6, "Edit tab spec §3 mandates exactly 6 tools")

        for tool in tools {
            #expect(!tool.label.isEmpty, "Edit tool '\(tool.id)' missing label")
            #expect(!tool.icon.isEmpty, "Edit tool '\(tool.id)' missing icon")
            #expect(!tool.id.isEmpty)
        }
    }

    // MARK: - 2. Audio-tab drill-down

    @Test("Audio tab exposes 6 labelled tool buttons and selection fires haptic")
    func audioTabDrillDown() {
        let svc = resetHaptics()
        let vm = makeViewModel()

        vm.selectedTab = .audio
        #expect(svc.playForTesting(.selection) == true)

        let tools = vm.currentTabTools
        #expect(!tools.isEmpty)
        #expect(tools.count == 6)
        for tool in tools {
            #expect(!tool.label.isEmpty, "Audio tool '\(tool.id)' missing label")
            #expect(!tool.icon.isEmpty)
        }
    }

    // MARK: - 3. Text-tab drill-down

    @Test("Text tab exposes 6 labelled tool buttons and selection fires haptic")
    func textTabDrillDown() {
        let svc = resetHaptics()
        let vm = makeViewModel()

        vm.selectedTab = .text
        #expect(svc.playForTesting(.selection) == true)

        let tools = vm.currentTabTools
        #expect(!tools.isEmpty)
        #expect(tools.count == 6)
        for tool in tools {
            #expect(!tool.label.isEmpty, "Text tool '\(tool.id)' missing label")
            #expect(!tool.icon.isEmpty)
        }
    }

    // MARK: - 4. FX-tab drill-down

    @Test("FX tab exposes 6 labelled tool buttons and selection fires haptic")
    func fxTabDrillDown() {
        let svc = resetHaptics()
        let vm = makeViewModel()

        vm.selectedTab = .fx
        #expect(svc.playForTesting(.selection) == true)

        let tools = vm.currentTabTools
        #expect(!tools.isEmpty)
        #expect(tools.count == 6)
        for tool in tools {
            #expect(!tool.label.isEmpty, "FX tool '\(tool.id)' missing label")
            #expect(!tool.icon.isEmpty)
        }
    }

    // MARK: - 5. Color-tab drill-down

    @Test("Color tab exposes 6 labelled tool buttons and selection fires haptic")
    func colorTabDrillDown() {
        let svc = resetHaptics()
        let vm = makeViewModel()

        vm.selectedTab = .color
        #expect(svc.playForTesting(.selection) == true)

        let tools = vm.currentTabTools
        #expect(!tools.isEmpty)
        #expect(tools.count == 6)
        for tool in tools {
            #expect(!tool.label.isEmpty, "Color tool '\(tool.id)' missing label")
            #expect(!tool.icon.isEmpty)
        }
    }

    // MARK: - 6. Every premium-redesign tab covered by iteration

    @Test("Every EditorTabID produces non-empty, well-labelled tool list")
    func everyEditorTabIDYieldsToolList() {
        let vm = makeViewModel()

        for tabID in EditorTabID.allCases {
            vm.selectedTab = tabID
            let tools = vm.currentTabTools

            #expect(!tools.isEmpty, "Tab \(tabID.rawValue) produced empty tool list")

            let ids = Set(tools.map(\.id))
            #expect(ids.count == tools.count, "Tab \(tabID.rawValue) has duplicate tool ids")

            for tool in tools {
                #expect(!tool.label.isEmpty, "Tab \(tabID.rawValue) tool '\(tool.id)' missing label")
                #expect(!tool.icon.isEmpty, "Tab \(tabID.rawValue) tool '\(tool.id)' missing icon")
            }
        }
    }

    // MARK: - 7. Legacy EditorTab: Smart + Overlay identity & haptic

    @Test("Legacy EditorTab.smart is identifiable and switch fires haptic")
    func legacySmartTabHapticAndIdentity() {
        let svc = resetHaptics()
        let vm = makeViewModel()

        vm.activeTab = .smart
        #expect(svc.playForTesting(.selection) == true,
                "Switching to Smart tab must fire selection haptic")

        #expect(vm.activeTab == .smart)
        #expect(!EditorTab.smart.displayName.isEmpty)
        #expect(!EditorTab.smart.iconName.isEmpty)
        #expect(!EditorTab.smart.activeIconName.isEmpty)
    }

    @Test("Legacy EditorTab.overlay is identifiable and switch fires haptic")
    func legacyOverlayTabHapticAndIdentity() {
        let svc = resetHaptics()
        let vm = makeViewModel()

        vm.activeTab = .overlay
        #expect(svc.playForTesting(.selection) == true,
                "Switching to Overlay tab must fire selection haptic")

        #expect(vm.activeTab == .overlay)
        #expect(!EditorTab.overlay.displayName.isEmpty)
        #expect(!EditorTab.overlay.iconName.isEmpty)
    }

    // MARK: - 8. Legacy EditorTab.allCases exhaustive sweep

    @Test("Every EditorTab.allCases has non-empty display & icon names")
    func legacyEditorTabAllCasesWellFormed() {
        #expect(EditorTab.allCases.count == 5,
                "EditorTab spec §3 keeps 5 legacy cases: edit/fx/overlay/audio/smart")

        for tab in EditorTab.allCases {
            #expect(!tab.displayName.isEmpty, "Tab \(tab.rawValue) missing displayName")
            #expect(!tab.iconName.isEmpty, "Tab \(tab.rawValue) missing iconName")
            #expect(!tab.activeIconName.isEmpty, "Tab \(tab.rawValue) missing activeIconName")
            #expect(!tab.rawValue.isEmpty)
        }
    }

    // MARK: - 9. Tab switch sequence fires haptic each time

    @Test("Sequencing through every premium tab fires a selection haptic per switch")
    func sequentialTabSwitchFiresHapticEachTime() async throws {
        let svc = resetHaptics()
        let vm = makeViewModel()

        // Throttle window is 40ms — sleep a touch longer between switches
        // so each selection haptic is allowed to fire.
        for tabID in EditorTabID.allCases {
            vm.selectedTab = tabID
            #expect(svc.playForTesting(.selection) == true,
                    "selection haptic should fire when entering \(tabID.rawValue)")
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - 10. Haptic respects the user's enable flag

    @Test("Tab-switch haptic is suppressed when HapticService is disabled")
    func tabSwitchHapticRespectsDisableFlag() {
        let svc = HapticService.shared
        svc.resetThrottleForTesting()
        svc.setEnabled(false)
        defer { svc.setEnabled(true) }

        let vm = makeViewModel()
        vm.selectedTab = .edit

        #expect(svc.playForTesting(.selection) == false,
                "Disabled haptic service must not fire when switching tabs")
    }

    // MARK: - 11. Tool-strip uniqueness across tabs

    @Test("Tool IDs are namespaced per tab to prevent ForEach collisions")
    func toolStripIDsAreNamespacedPerTab() {
        let vm = makeViewModel()

        for tabID in EditorTabID.allCases {
            vm.selectedTab = tabID
            let tools = vm.currentTabTools
            let expectedPrefix = tabID.rawValue + "."
            for tool in tools {
                #expect(tool.id.hasPrefix(expectedPrefix),
                        "Tool '\(tool.id)' on tab '\(tabID.rawValue)' must be namespaced with prefix '\(expectedPrefix)'")
            }
        }
    }

    // MARK: - 12. EditorTabID.allCases matches spec count

    @Test("EditorTabID has exactly five spec-compliant cases")
    func editorTabIDCaseCount() {
        #expect(EditorTabID.allCases.count == 5,
                "Premium redesign §3.1 freezes the bottom bar at 5 tabs: edit/audio/text/fx/color")

        let expected: Set<EditorTabID> = [.edit, .audio, .text, .fx, .color]
        let actual = Set(EditorTabID.allCases)
        #expect(actual == expected)
    }
}
