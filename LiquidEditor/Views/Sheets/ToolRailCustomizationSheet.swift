// ToolRailCustomizationSheet.swift
// LiquidEditor
//
// TD8-15: Sheet for customizing the 6-slot ToolRail — drag to reorder,
// toggle each tool's visibility, or reset to defaults.
//
// Per docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.15.
//
// The UI uses SwiftUI `List` + `.onMove` to drag-reorder the slot
// identifiers; a `Toggle` per row controls visibility. A "Reset to
// default" button restores the canonical order and clears the hidden
// set.
//
// Pure SwiftUI, iOS 26 Liquid Glass.

import SwiftUI

// MARK: - ToolRailSlot

/// Canonical identifiers for the 6 customizable ToolRail slots.
/// Each case carries its SF Symbol + display name.
enum ToolRailSlot: String, CaseIterable, Identifiable, Sendable, Codable {
    case split
    case speed
    case volume
    case filter
    case text
    case audio

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .split:  return "scissors"
        case .speed:  return "speedometer"
        case .volume: return "speaker.wave.2.fill"
        case .filter: return "camera.filters"
        case .text:   return "textformat"
        case .audio:  return "waveform"
        }
    }

    var displayName: String {
        switch self {
        case .split:  return "Split"
        case .speed:  return "Speed"
        case .volume: return "Volume"
        case .filter: return "Filter"
        case .text:   return "Text"
        case .audio:  return "Audio"
        }
    }
}

// MARK: - ToolRailConfig

/// Value type describing the user's current ToolRail customization.
///
/// `orderedSlots` is the full ordered list of slot ids (including
/// hidden ones, so drag-order is preserved across visibility toggles).
/// `hiddenSlots` is the set of currently-hidden ids.
struct ToolRailConfig: Sendable, Equatable, Codable {
    var orderedSlots: [ToolRailSlot]
    var hiddenSlots: Set<ToolRailSlot>

    /// Canonical default configuration: all 6 slots in the order the
    /// spec illustrates, none hidden.
    static let `default` = ToolRailConfig(
        orderedSlots: ToolRailSlot.allCases,
        hiddenSlots: []
    )

    /// Slots currently visible on the rail (preserves user order).
    var visibleSlots: [ToolRailSlot] {
        orderedSlots.filter { !hiddenSlots.contains($0) }
    }
}

// MARK: - ToolRailCustomizationSheet

/// Sheet allowing the user to reorder and toggle visibility of the
/// 6 ToolRail slots.
@MainActor
struct ToolRailCustomizationSheet: View {

    // MARK: - Inputs

    /// Starting configuration. The sheet edits a local copy and only
    /// commits to the caller via `onCommit` on Done.
    let initialConfig: ToolRailConfig

    /// Invoked with the user's new configuration when they tap Done.
    let onCommit: (ToolRailConfig) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode

    // MARK: - State

    @State private var workingConfig: ToolRailConfig

    // MARK: - Init

    init(initialConfig: ToolRailConfig,
         onCommit: @escaping (ToolRailConfig) -> Void) {
        self.initialConfig = initialConfig
        self.onCommit = onCommit
        _workingConfig = State(initialValue: initialConfig)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(workingConfig.orderedSlots) { slot in
                        row(for: slot)
                    }
                    .onMove(perform: moveSlots)
                } header: {
                    Text("Drag to reorder. Toggle visibility per tool.")
                        .textCase(nil)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive, action: resetToDefault) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to default")
                        }
                    }
                    .accessibilityLabel("Reset tool rail to default")
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Tool Rail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Row

    private func row(for slot: ToolRailSlot) -> some View {
        let isVisible = !workingConfig.hiddenSlots.contains(slot)
        return HStack(spacing: LiquidSpacing.md) {
            Image(systemName: slot.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(isVisible ? LiquidColors.Accent.amber : .secondary)
                .frame(width: 24, alignment: .center)

            Text(slot.displayName)
                .font(.body)
                .foregroundStyle(isVisible ? .primary : .secondary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { newValue in setVisibility(newValue, for: slot) }
            ))
            .labelsHidden()
            .tint(LiquidColors.Accent.amber)
            .accessibilityLabel("\(slot.displayName) visibility")
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mutations

    private func moveSlots(from source: IndexSet, to destination: Int) {
        workingConfig.orderedSlots.move(fromOffsets: source, toOffset: destination)
        HapticService.shared.trigger(.selection)
    }

    private func setVisibility(_ visible: Bool, for slot: ToolRailSlot) {
        if visible {
            workingConfig.hiddenSlots.remove(slot)
        } else {
            workingConfig.hiddenSlots.insert(slot)
        }
        HapticService.shared.trigger(.selection)
    }

    private func resetToDefault() {
        workingConfig = .default
        HapticService.shared.trigger(.selection)
    }

    private func commit() {
        HapticService.shared.trigger(.selection)
        onCommit(workingConfig)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Tool rail customize") {
    ToolRailCustomizationSheet(
        initialConfig: .default,
        onCommit: { _ in }
    )
    .preferredColorScheme(.dark)
}
