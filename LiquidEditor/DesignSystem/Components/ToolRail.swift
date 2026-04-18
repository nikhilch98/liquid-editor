// ToolRail.swift
// LiquidEditor
//
// P1-3: Vertical 6-slot tool rail (iPad editor + landscape iPhone editor)
// per spec §3.3, §10.4.
//
// Visual:
// - 36pt wide vertical column
// - 6 tool buttons (28pt square, elevated cell background)
// - active tool gets amber fill + amber border + amber icon
// - long-press on any slot opens the "Edit rail..." customization sheet
//   (the sheet itself lives in TD8-15, invoked via onEditRail)

import SwiftUI

// MARK: - ToolRailItem

/// A single tool exposed on the rail. `id` is a stable string persisted
/// in `ProjectUIState.toolRailItemIDs`.
struct ToolRailItem: Identifiable, Equatable, Sendable {
    let id: String
    let systemImage: String
    let label: String

    init(id: String, systemImage: String, label: String) {
        self.id = id
        self.systemImage = systemImage
        self.label = label
    }
}

// MARK: - ToolRail

/// Vertical tool rail for iPad / landscape iPhone.
///
/// - Parameters:
///   - items: the 6 tools to show, in the user-customized order
///   - selectedID: the currently-active tool's id (`nil` if no tool active)
///   - onSelect: invoked when a tool is tapped
///   - onEditRail: invoked on long-press to open customization
struct ToolRail: View {

    // MARK: - Inputs

    let items: [ToolRailItem]
    let selectedID: String?
    let onSelect: (ToolRailItem) -> Void
    let onEditRail: () -> Void

    // MARK: - Constants

    static let railWidth: CGFloat = 36
    static let slotSize: CGFloat = 28
    static let maxItems = 6

    // MARK: - Body

    var body: some View {
        VStack(spacing: 3) {
            ForEach(items.prefix(Self.maxItems)) { item in
                slot(for: item)
            }
            if items.count < Self.maxItems {
                Spacer(minLength: 0)
            }
        }
        .padding(4)
        .frame(width: Self.railWidth)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LiquidColors.Canvas.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LiquidColors.Text.tertiary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool rail")
        .onLongPressGesture(minimumDuration: 0.45) { onEditRail() }
    }

    // MARK: - Slot

    @ViewBuilder
    private func slot(for item: ToolRailItem) -> some View {
        let isActive = item.id == selectedID
        Button {
            onSelect(item)
        } label: {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? LiquidColors.Accent.amber : LiquidColors.Text.secondary)
                .frame(width: Self.slotSize, height: Self.slotSize)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? LiquidColors.Accent.amberGlow : LiquidColors.Canvas.elev)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isActive ? LiquidColors.Accent.amber : .clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Previews

#Preview("Active Split") {
    let items = [
        ToolRailItem(id: "split", systemImage: "scissors", label: "Split"),
        ToolRailItem(id: "trim", systemImage: "arrow.left.and.right.square", label: "Trim"),
        ToolRailItem(id: "speed", systemImage: "speedometer", label: "Speed"),
        ToolRailItem(id: "mask", systemImage: "oval.portrait", label: "Mask"),
        ToolRailItem(id: "keyframes", systemImage: "diamond", label: "Keyframes"),
        ToolRailItem(id: "tracking", systemImage: "target", label: "Tracking"),
    ]
    return ToolRail(
        items: items,
        selectedID: "split",
        onSelect: { _ in },
        onEditRail: { }
    )
    .padding()
    .background(LiquidColors.Canvas.base)
    .preferredColorScheme(.dark)
}
