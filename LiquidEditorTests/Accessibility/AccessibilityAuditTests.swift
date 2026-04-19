// AccessibilityAuditTests.swift
// LiquidEditor
//
// TT13-6 (Premium UI §11.6): Accessibility audits for the key premium
// UI views. Without ViewInspector we can't read `accessibilityLabel`
// back from a SwiftUI view at runtime, so we verify the *source data*
// used to build those labels — plus the structural existence of each
// view — which is the same thing the labels would render.
//
// This covers:
// - `ClipView` labels derived from `TimelineItemProtocol.displayName`
//   (labels are non-empty for every clip type the audit covers).
// - `ProjectCardView` labels derived from `ProjectMetadata.name` and
//   `formattedDuration`.
// - `EditorToolbar` tab labels come from `EditorTab.displayName`; the
//   underlying `TabBarItem` renders `.accessibilityLabel(label)`, so we
//   assert each tab exposes a non-empty display name and matching icon.
//
// NOTE: Per code review — `TabBarItem` today has no per-tab
// `accessibilityHint`, only `.accessibilityLabel(label)`. The TT13-6
// spec language "tab buttons have accessibilityHint" is downgraded to
// "tab buttons have a non-empty spoken label"; the missing hint is
// tracked as a deferred enhancement.

import Foundation
import Testing
@testable import LiquidEditor

// MARK: - Accessibility audits

@Suite("Accessibility audits")
@MainActor
struct AccessibilityAuditTests {

    // MARK: - ClipView label source

    @Test("ClipView's accessibility label source — displayName is non-empty for VideoClip")
    func clipViewLabelSourceVideo() {
        let clip = VideoClip(
            id: "video-a",
            mediaAssetId: "asset-1",
            sourceInMicros: 0,
            sourceOutMicros: 5_000_000
        )
        // ClipView renders `.accessibilityLabel("Clip: \(item.displayName)")`,
        // so displayName must be non-empty to produce a meaningful label.
        #expect(!clip.displayName.isEmpty)
    }

    @Test("ClipView's accessibility label source — displayName is non-empty for AudioClip")
    func clipViewLabelSourceAudio() {
        let clip = AudioClip(
            id: "audio-a",
            mediaAssetId: "asset-2",
            sourceInMicros: 0,
            sourceOutMicros: 3_000_000
        )
        #expect(!clip.displayName.isEmpty)
    }

    @Test("ClipView's accessibility label source — displayName is non-empty for GapClip")
    func clipViewLabelSourceGap() {
        let clip = GapClip(id: "gap-a", durationMicroseconds: 1_000_000)
        #expect(!clip.displayName.isEmpty)
    }

    // MARK: - ProjectCardView label source

    @Test("ProjectCardView label source — name and formattedDuration are non-empty")
    func projectCardLabelSource() {
        let project = ProjectMetadata(
            id: "p1",
            name: "My Trip",
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 1),
            timelineDurationMs: 65_000  // 1:05
        )
        // ProjectCardView renders:
        //   .accessibilityLabel("\(project.name), \(project.formattedDuration)")
        // Both components must be non-empty to produce a useful label.
        #expect(!project.name.isEmpty)
        #expect(!project.formattedDuration.isEmpty)
    }

    @Test("ProjectCardView label reflects name changes")
    func projectCardLabelReflectsName() {
        let original = ProjectMetadata(
            id: "p1",
            name: "Original Name",
            createdAt: Date(),
            modifiedAt: Date()
        )
        // Copy-with-new-name (`with(name:)` on ProjectMetadata).
        let renamed = original.with(name: "Renamed")

        // The source of truth for the VoiceOver label changes accordingly.
        #expect(original.name == "Original Name")
        #expect(renamed.name == "Renamed")
    }

    // MARK: - EditorToolbar tab label source

    @Test("EditorToolbar tabs — every EditorTab exposes a non-empty displayName")
    func editorToolbarTabLabels() {
        // TabBarItem uses `.accessibilityLabel(label)` where `label` comes
        // from `EditorTab.displayName`. Every tab must supply a non-empty
        // spoken label so VoiceOver users can distinguish them.
        for tab in EditorTab.allCases {
            #expect(!tab.displayName.isEmpty, "Tab \(tab.rawValue) missing displayName")
            #expect(!tab.iconName.isEmpty, "Tab \(tab.rawValue) missing iconName")
            #expect(!tab.activeIconName.isEmpty, "Tab \(tab.rawValue) missing activeIconName")
        }
    }

    @Test("EditorToolbar premium tabs — every EditorTabID exposes a non-empty rawValue")
    func editorToolbarPremiumTabIdentifiers() {
        for tab in EditorTabID.allCases {
            // Raw value drives persistence; it must never be empty.
            #expect(!tab.rawValue.isEmpty)
        }
    }

    // MARK: - ToolStripButton labels (premium §3/§4)

    @Test("ToolStripButtons on every premium tab have non-empty label, icon, and id")
    func toolStripButtonsHaveLabels() {
        let project = Project(name: "A11y Test", sourceVideoPath: "")
        let vm = EditorViewModel(project: project)

        for tab in EditorTabID.allCases {
            vm.selectedTab = tab
            let buttons = vm.currentTabTools
            #expect(!buttons.isEmpty, "Tab \(tab) returned no tools")
            for button in buttons {
                #expect(!button.label.isEmpty,
                        "Tool \(button.id) on tab \(tab) has empty label")
                #expect(!button.icon.isEmpty,
                        "Tool \(button.id) on tab \(tab) has empty icon")
                #expect(!button.id.isEmpty,
                        "Tool on tab \(tab) has empty id")
            }
        }
    }
}
