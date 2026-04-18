// EffectStackReorderView.swift
// LiquidEditor
//
// C5-19: FX Browser "drag-to-reorder" panel for a clip's effect stack.
//
// A SwiftUI `List` bound to a `@Bindable` `EffectStackReorderViewModel`
// that holds an ordered `[VideoEffect]`. Supports:
//   - `.onMove { from, to in ... }` drag reorder
//   - Intensity slider per row (bound to `mix`)
//   - Enable/disable toggle (Toggle on the row)
//   - Swipe to Delete
//
// Pure iOS 26 SwiftUI. No UIKit, `@Observable` macro on the VM,
// `@MainActor` throughout.

import SwiftUI
import Observation

// MARK: - EffectStackReorderViewModel

/// Backing state for `EffectStackReorderView`.
///
/// Wraps an ordered list of `VideoEffect`s and exposes the reorder
/// / toggle / mix / delete operations the view needs. Callers supply
/// `onCommit` which is invoked whenever the ordered stack changes so
/// the enclosing feature (e.g. `EffectStore`) can persist.
@Observable
@MainActor
final class EffectStackReorderViewModel {

    /// Ordered stack of effects (head of list = bottom of stack,
    /// consistent with `EffectChain.effects`).
    var effects: [VideoEffect]

    /// Invoked whenever `effects` is mutated by the view.
    var onCommit: ([VideoEffect]) -> Void

    init(
        effects: [VideoEffect] = [],
        onCommit: @escaping ([VideoEffect]) -> Void = { _ in }
    ) {
        self.effects = effects
        self.onCommit = onCommit
    }

    // MARK: - Mutations

    func move(from source: IndexSet, to destination: Int) {
        effects.move(fromOffsets: source, toOffset: destination)
        onCommit(effects)
    }

    func delete(at offsets: IndexSet) {
        effects.remove(atOffsets: offsets)
        onCommit(effects)
    }

    func updateMix(id: String, mix: Double) {
        guard let idx = effects.firstIndex(where: { $0.id == id }) else { return }
        effects[idx] = effects[idx].with(mix: mix)
        onCommit(effects)
    }

    func toggleEnabled(id: String) {
        guard let idx = effects.firstIndex(where: { $0.id == id }) else { return }
        effects[idx] = effects[idx].with(isEnabled: !effects[idx].isEnabled)
        onCommit(effects)
    }
}

// MARK: - EffectStackReorderView

/// Drag-to-reorder view for a clip's effect stack.
///
/// Rows display SF Symbol icon + effect name + intensity slider.
/// Supports `.onMove` drag-reorder, disable toggle, and swipe-to-delete.
@MainActor
struct EffectStackReorderView: View {

    @Bindable var viewModel: EffectStackReorderViewModel

    @Environment(\.dismiss) private var dismiss

    init(viewModel: EffectStackReorderViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.effects.isEmpty {
                    emptyState
                } else {
                    effectList
                }
            }
            .navigationTitle("Effect Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(LiquidTypography.bodyMedium)
                }

                if !viewModel.effects.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                            .font(LiquidTypography.body)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: LiquidSpacing.lg) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text("No effects applied")
                .font(LiquidTypography.headline)
                .foregroundStyle(.primary)

            Text("Add effects from the FX browser, then return here to reorder, tune or remove them.")
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - List

    private var effectList: some View {
        List {
            Section {
                ForEach(viewModel.effects, id: \.id) { effect in
                    EffectStackRow(
                        effect: effect,
                        onMixChange: { newMix in
                            viewModel.updateMix(id: effect.id, mix: newMix)
                        },
                        onToggle: {
                            viewModel.toggleEnabled(id: effect.id)
                        }
                    )
                }
                .onMove { from, to in
                    viewModel.move(from: from, to: to)
                }
                .onDelete { offsets in
                    viewModel.delete(at: offsets)
                }
            } header: {
                Text("Drag to reorder • Swipe to remove")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Row

/// Single effect row: icon + name + enable toggle + intensity slider.
@MainActor
private struct EffectStackRow: View {
    let effect: VideoEffect
    let onMixChange: (Double) -> Void
    let onToggle: () -> Void

    @State private var mix: Double

    init(
        effect: VideoEffect,
        onMixChange: @escaping (Double) -> Void,
        onToggle: @escaping () -> Void
    ) {
        self.effect = effect
        self.onMixChange = onMixChange
        self.onToggle = onToggle
        _mix = State(initialValue: effect.mix)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            HStack(spacing: LiquidSpacing.md) {
                Image(systemName: effect.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(effect.displayName)
                        .font(LiquidTypography.bodyMedium)
                        .foregroundStyle(.primary)

                    Text(effect.category.rawValue.capitalized)
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: LiquidSpacing.sm)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { effect.isEnabled },
                        set: { _ in onToggle() }
                    )
                )
                .labelsHidden()
                .tint(.purple)
                .accessibilityLabel(effect.isEnabled ? "Disable effect" : "Enable effect")
            }

            HStack(spacing: LiquidSpacing.sm) {
                Image(systemName: "slider.horizontal.below.sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Slider(value: $mix, in: 0...1) { editing in
                    if !editing {
                        onMixChange(mix)
                    }
                }
                .tint(.purple)
                .disabled(!effect.isEnabled)
                .accessibilityLabel("Intensity")
                .accessibilityValue("\(Int(mix * 100)) percent")

                Text("\(Int(mix * 100))%")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, LiquidSpacing.xs)
        .contentShape(Rectangle())
        .opacity(effect.isEnabled ? 1.0 : 0.55)
    }
}
