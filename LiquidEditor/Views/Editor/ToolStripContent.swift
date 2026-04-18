// ToolStripContent.swift
// LiquidEditor
//
// Premium redesign editor tab bar + tool strip (spec §3 and §4).
//
// Introduces:
//   * `EditorTabID` — the new 5-tab model (edit / audio / text / fx / color)
//     that replaces the legacy `EditorTab` naming (overlay / smart) in the
//     premium redesign flow without removing the old enum.
//   * `ToolStripButton` — a data model for one button in the horizontal
//     tool strip that sits directly above the tab bar.
//   * `ToolStripContent` — the horizontally scrollable tool strip that
//     swaps its buttons based on `viewModel.selectedTab` via the
//     `viewModel.currentTabTools` computed property on `EditorViewModel`.
//
// Tab-switch haptic: `.tabSwitch` (see `HapticService`), which the spec
// maps to `UISelectionFeedbackGenerator.selectionChanged()` (spec §2.4).

import SwiftUI

// MARK: - EditorTabID (defined in EditorViewModel.swift)

#if false
/// Premium-redesign 5-tab model for the editor bottom bar.
///
/// Distinct from the legacy `EditorTab` (which has `.overlay` / `.smart`).
/// Kept in a separate enum so existing code paths that rely on
/// `EditorViewModel.activeTab` continue to compile.
///
/// Order matches spec §3.1 bullet 6: Edit / Audio / Text / FX / Color.
enum _EditorTabID_Unused: String, CaseIterable, Sendable, Identifiable {
    case edit
    case audio
    case text
    case fx
    case color

    var id: String { rawValue }

    /// Human-readable title shown under the tab icon.
    var displayName: String {
        switch self {
        case .edit:  return "Edit"
        case .audio: return "Audio"
        case .text:  return "Text"
        case .fx:    return "FX"
        case .color: return "Color"
        }
    }

    /// SF Symbol for the tab when unselected.
    var iconName: String {
        switch self {
        case .edit:  return "slider.horizontal.3"
        case .audio: return "speaker.wave.2"
        case .text:  return "textformat"
        case .fx:    return "sparkles"
        case .color: return "paintpalette"
        }
    }

    /// SF Symbol for the tab when selected (filled variants).
    var activeIconName: String {
        switch self {
        case .edit:  return "slider.horizontal.3"
        case .audio: return "speaker.wave.2.fill"
        case .text:  return "textformat"
        case .fx:    return "sparkles"
        case .color: return "paintpalette.fill"
        }
    }
}
#endif

// MARK: - ToolStripButton

/// One button in the editor's context-sensitive tool strip.
///
/// The `action` closure is captured by the view model when building
/// `currentTabTools`. Buttons are `Identifiable` (stable `id` string)
/// so SwiftUI's `ForEach` can diff them correctly when the strip swaps
/// on tab change.
struct ToolStripButton: Identifiable, Sendable {

    /// Stable identifier (e.g., "edit.split", "audio.fade").
    let id: String

    /// SF Symbol name.
    let icon: String

    /// 11pt label shown under the icon (spec §3 / §4).
    let label: String

    /// Whether this button carries the destructive red tint.
    let isDestructive: Bool

    /// Whether this button is in its active state (amber highlight).
    let isActive: Bool

    /// Tap handler — @MainActor closure provided by `EditorViewModel`.
    let action: @MainActor @Sendable () -> Void

    init(
        id: String,
        icon: String,
        label: String,
        isDestructive: Bool = false,
        isActive: Bool = false,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.label = label
        self.isDestructive = isDestructive
        self.isActive = isActive
        self.action = action
    }
}

// MARK: - ToolStripContent

/// Horizontally scrolling tool-strip that sits directly above the tab bar.
///
/// Binds to `EditorViewModel.currentTabTools` so the button set swaps
/// automatically on `selectedTab` change. Each button fires the tap
/// haptic (`EditorHapticType.selection`) before invoking its action.
struct ToolStripContent: View {

    // MARK: - Properties

    @Bindable var viewModel: EditorViewModel

    /// Haptic service used for tap feedback. Defaults to the singleton.
    var hapticService: HapticService = .shared

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.xs) {
                ForEach(viewModel.currentTabTools) { tool in
                    toolButton(tool)
                }
            }
            .padding(.horizontal, LiquidSpacing.xs)
        }
        .frame(height: LiquidSpacing.timelineTrackHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(viewModel.selectedTab.rawValue.capitalized) tools")
    }

    // MARK: - Tool Button

    /// Build a single tool button using existing Liquid Glass tokens.
    /// Label is 11pt per spec §3/§4 (existing legacy toolbar uses 10pt).
    @ViewBuilder
    private func toolButton(_ tool: ToolStripButton) -> some View {
        Button {
            hapticService.trigger(.selection)
            tool.action()
        } label: {
            VStack(spacing: LiquidSpacing.xxs) {
                Image(systemName: tool.icon)
                    .font(.system(size: 22))
                    .frame(width: 28, height: 28)
                Text(tool.label)
                    .font(.system(size: 11, weight: tool.isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor(for: tool))
            .frame(width: 60)
            .padding(.vertical, 6)
            .background(
                tool.isActive
                ? RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15))
                : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.label)
        .accessibilityAddTraits(tool.isActive ? .isSelected : [])
    }

    /// Color logic mirrors legacy `EditorToolbar.toolButtonColor`.
    private func foregroundColor(for tool: ToolStripButton) -> Color {
        if tool.isDestructive { return LiquidColors.error }
        if tool.isActive { return .orange }
        return LiquidColors.textSecondary
    }
}

// (No SwiftUI #Preview — `EditorViewModel` requires a fully-configured
// `Project` which is non-trivial to construct for a static preview.
// Visual verification happens in-app via the editor screen.)
