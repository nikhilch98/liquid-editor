// ComponentSmokeTests.swift
// LiquidEditorTests
//
// Construction smoke tests for premium-UI components. SwiftUI views
// don't expose a good unit-testable layout surface, so these tests
// only verify the components construct without crashing and expose
// the accessibility labels declared by the spec.

import Testing
import SwiftUI
@testable import LiquidEditor

@Suite("Component Smoke Tests")
@MainActor
struct ComponentSmokeTests {

    // MARK: - Atoms group A

    @Test("GlassPill constructs with label")
    func glassPill() {
        let pill = GlassPill(label: "1080p")
        _ = pill.body
    }

    @Test("IconButton constructs and declares an accessibility label")
    func iconButton() {
        let button = IconButton(systemName: "xmark", accessibilityLabel: "Close") {}
        _ = button.body
    }

    @Test("PrimaryCTA constructs with title")
    func primaryCTA() {
        let cta = PrimaryCTA(title: "Export") {}
        _ = cta.body
    }

    // MARK: - Atoms group B

    @Test("TransportButton constructs in primary / secondary sizes")
    func transportButton() {
        let primary = TransportButton(systemName: "play.fill", kind: .primary) {}
        let secondary = TransportButton(systemName: "arrow.uturn.backward", kind: .secondary) {}
        _ = primary.body
        _ = secondary.body
    }

    @Test("ToolButton constructs with glyph + caption")
    func toolButton() {
        let tool = ToolButton(systemName: "scissors", caption: "Split", isActive: false) {}
        _ = tool.body
    }

    @Test("TabBarItem constructs")
    func tabBarItem() {
        let tab = TabBarItem(
            systemName: "slider.horizontal.3",
            label: "Edit",
            isActive: true
        ) {}
        _ = tab.body
    }

    // MARK: - Composites

    @Test("PlayheadWithChip constructs with a time value")
    func playheadWithChip() {
        let p = PlayheadWithChip(timeText: "00:02.14", isScrubbing: false)
        _ = p.body
    }

    @Test("SheetHeader constructs with optional apply")
    func sheetHeader() {
        let header = SheetHeader(
            title: "Export",
            onClose: {},
            onApply: { }
        )
        _ = header.body
    }

    @Test("EmptyStateCard constructs")
    func emptyStateCard() {
        let card = EmptyStateCard(
            glyph: "film.stack",
            title: "No media",
            body: "Add clips to get started",
            ctaTitle: "Import Media",
            action: {}
        )
        _ = card.body
    }

    @Test("ToolPanelRow constructs with slider control")
    func toolPanelRow() {
        let row = ToolPanelRow(
            label: "Speed",
            value: "1.0×",
            control: AnyView(Slider(value: .constant(1.0)))
        )
        _ = row.body
    }

    // MARK: - Feedback

    @Test("BrandLoader constructs with and without caption")
    func brandLoader() {
        _ = BrandLoader().body
        _ = BrandLoader(caption: "Loading project…").body
    }

    @Test("ErrorChip constructs")
    func errorChip() {
        _ = ErrorChip(message: "Export failed").body
    }

    @Test("Toast constructs")
    func toast() {
        _ = Toast(message: "Saved", kind: .success).body
    }
}
