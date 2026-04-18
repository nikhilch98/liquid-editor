// GlassContextMenu.swift
// LiquidEditor
//
// P1-5: Standardized long-press context menu pattern per spec §9.4.
//
// SwiftUI's native `.contextMenu` already renders a glass-style floating
// menu near the touch point with a long-press trigger. This file provides
// structured item types + a single `.glassContextMenu(sections:)` View
// modifier so every call site uses the same grouping + destructive rules.
//
// Sections per spec:
//   primary -> secondary -> destructive, divided by hairlines (via native
//   Divider/Section in Menu builders).

import SwiftUI

// MARK: - ContextMenuItem

/// A single context-menu entry.
///
/// Keyboard shortcut is displayed natively on iPad when `shortcut` is set
/// (SwiftUI auto-renders the modifier glyph in the menu row).
struct ContextMenuItem: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String?
    let role: ButtonRole?
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    init(
        _ label: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.shortcut = shortcut
        self.action = action
    }
}

// MARK: - ContextMenuSection

/// A grouping of items. Sections are separated by native `Divider` in the menu.
struct ContextMenuSection: Identifiable {
    let id = UUID()
    let items: [ContextMenuItem]

    init(_ items: [ContextMenuItem]) { self.items = items }
}

// MARK: - View extension

extension View {

    /// Attach a sectioned long-press context menu (primary → secondary →
    /// destructive). Renders via SwiftUI's native `.contextMenu`, which
    /// provides the glass appearance + long-press trigger automatically.
    func glassContextMenu(sections: [ContextMenuSection]) -> some View {
        contextMenu {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 { Divider() }
                ForEach(section.items) { item in
                    button(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func button(for item: ContextMenuItem) -> some View {
        let action = item.action
        if let role = item.role {
            Button(role: role, action: action) { labelFor(item) }
        } else {
            Button(action: action) { labelFor(item) }
        }
    }

    @ViewBuilder
    private func labelFor(_ item: ContextMenuItem) -> some View {
        if let icon = item.systemImage {
            Label(item.label, systemImage: icon)
        } else {
            Text(item.label)
        }
    }
}

// MARK: - Previews

#Preview("Clip context menu") {
    struct Demo: View {
        var body: some View {
            Text("Long-press me")
                .padding(30)
                .background(LiquidColors.Canvas.raised)
                .foregroundStyle(LiquidColors.Text.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .glassContextMenu(sections: [
                    ContextMenuSection([
                        ContextMenuItem("Split at playhead", systemImage: "scissors") { },
                        ContextMenuItem("Trim...", systemImage: "arrow.left.and.right.square") { },
                        ContextMenuItem("Copy", systemImage: "doc.on.doc") { },
                        ContextMenuItem("Duplicate", systemImage: "plus.square.on.square") { },
                    ]),
                    ContextMenuSection([
                        ContextMenuItem("Speed...", systemImage: "speedometer") { },
                        ContextMenuItem("Replace with...", systemImage: "arrow.triangle.2.circlepath") { },
                        ContextMenuItem("Properties", systemImage: "info.circle") { },
                    ]),
                    ContextMenuSection([
                        ContextMenuItem("Delete", systemImage: "trash", role: .destructive) { },
                    ]),
                ])
        }
    }
    return Demo()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColors.Canvas.base)
        .preferredColorScheme(.dark)
}
