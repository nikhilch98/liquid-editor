// InspectorPanel.swift
// LiquidEditor
//
// P1-2: Right-rail (iPad) / top-right (iPhone landscape) inspector
// container per spec §3.3, §10.2.
//
// Provides a section-slot container with:
// - titled header (clip name + duration when a clip is selected)
// - scroll-based vertical stack of `InspectorSection` slots
// - empty-state for "No selection" (delegated to EmptyStateView)
//
// Per spec §10.2, consumers populate the panel with per-selection-type
// sections (Transform / Speed / Volume / Opacity / ... / Properties).
// The InspectorVM in IM9-1 decides which sections to show.

import SwiftUI

// MARK: - InspectorSection

/// A single section rendered in the Inspector stack.
///
/// `id` is stable so SwiftUI can diff incremental section-set changes.
/// `isCollapsed` is the default collapsed state per spec §10.2 (shown
/// vs collapsed-by-default).
struct InspectorSection: Identifiable {
    let id: String
    let title: String
    let isCollapsed: Bool
    let content: AnyView

    init<Content: View>(
        id: String,
        title: String,
        isCollapsed: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.title = title
        self.isCollapsed = isCollapsed
        self.content = AnyView(content())
    }
}

// MARK: - InspectorPanel

/// Right-rail inspector container.
///
/// - `header`: rendered above the sections (typically a clip-header card).
/// - `sections`: the stack of collapsible sections.
/// - `emptyState`: shown when `sections` is empty.
struct InspectorPanel<Header: View>: View {

    // MARK: - Inputs

    let sections: [InspectorSection]
    let header: Header?
    let emptyState: EmptyStateView?

    init(
        sections: [InspectorSection],
        @ViewBuilder header: () -> Header = { EmptyView() },
        emptyState: EmptyStateView? = nil
    ) {
        self.sections = sections
        self.header = header()
        self.emptyState = emptyState
    }

    // MARK: - Body

    var body: some View {
        Group {
            if sections.isEmpty, let empty = emptyState {
                empty
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let header { header }
                        ForEach(sections) { section in
                            SectionView(section: section)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(LiquidColors.Canvas.raised)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - SectionView

private struct SectionView: View {
    let section: InspectorSection

    @State private var collapsed: Bool

    init(section: InspectorSection) {
        self.section = section
        self._collapsed = State(initialValue: section.isCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(LiquidMotion.snap) { collapsed.toggle() }
            } label: {
                HStack {
                    Text(section.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(LiquidColors.Text.tertiary)
                    Spacer()
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(LiquidColors.Text.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits([.isButton, .isHeader])

            if !collapsed {
                section.content
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiquidColors.Canvas.elev)
        )
    }
}

// MARK: - Preview

#Preview("Populated") {
    InspectorPanel(
        sections: [
            InspectorSection(id: "hdr", title: "Clip · B-roll_04") {
                Text("00:08 · 2K · 60fps")
                    .font(.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
            },
            InspectorSection(id: "transform", title: "Transform") {
                Text("Position / Scale / Rotation")
                    .font(.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
            },
            InspectorSection(id: "speed", title: "Speed", isCollapsed: true) {
                Text("1.0×")
                    .font(.caption)
                    .foregroundStyle(LiquidColors.Text.secondary)
            },
        ]
    )
    .frame(width: 160, height: 400)
    .background(LiquidColors.Canvas.base)
    .preferredColorScheme(.dark)
}
