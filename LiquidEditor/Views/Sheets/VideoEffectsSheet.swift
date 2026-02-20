// VideoEffectsSheet.swift
// LiquidEditor
//
// Video effects browser sheet view matching Flutter predecessor layout.
// Vertical list rows with icon + name + mix badge + Toggle, expandable
// with Mix slider + params + Remove button. Category tabs as horizontal
// scroll chips. Purple theme. Pure iOS 26 SwiftUI with native styling.

import SwiftUI

struct VideoEffectsSheet: View {

    @State private var selectedCategory: EffectCategory = .stylize
    @State private var effects: [VideoEffect]
    @State private var expandedEffectType: EffectType?

    @Environment(\.dismiss) private var dismiss

    let onApply: ([VideoEffect]) -> Void

    init(
        initialEffects: [VideoEffect] = [],
        onApply: @escaping ([VideoEffect]) -> Void
    ) {
        _effects = State(initialValue: initialEffects)
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            headerRow
                .padding(.horizontal, LiquidSpacing.xl)
                .padding(.top, LiquidSpacing.xl)
                .padding(.bottom, LiquidSpacing.lg)

            // Category tabs
            categoryTabs
                .padding(.bottom, LiquidSpacing.md)

            // Effects list
            ScrollView {
                effectsList
                    .padding(.horizontal, LiquidSpacing.xl)
                    .padding(.bottom, LiquidSpacing.lg)
            }

            // Apply Effects button
            applyButton
                .padding(.horizontal, LiquidSpacing.xl)
                .padding(.vertical, LiquidSpacing.lg)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Video Effects")
                .font(LiquidTypography.headline)

            Spacer()

            // Active count badge (purple)
            if activeCount > 0 {
                Text("\(activeCount) active")
                    .font(LiquidTypography.captionMedium)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, LiquidSpacing.sm + 2)
                    .padding(.vertical, LiquidSpacing.xs)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                    .accessibilityLabel("\(activeCount) active effects")
            }

            // Reset All (red)
            if !effects.isEmpty {
                Button("Reset All") {
                    resetAll()
                }
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.error)
                .accessibilityHint("Removes all applied effects")
            }

            // X close button
            Button {
                onApply(effects)
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.sm) {
                ForEach(EffectCategory.allCases, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal, LiquidSpacing.xl)
        }
    }

    private func categoryChip(_ category: EffectCategory) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            selectedCategory = category
        } label: {
            Text(category.displayName)
                .font(isSelected ? LiquidTypography.captionMedium : LiquidTypography.caption)
                .padding(.horizontal, LiquidSpacing.md + 2)
                .padding(.vertical, LiquidSpacing.sm)
                .background(
                    isSelected
                        ? Color.purple.opacity(0.2)
                        : LiquidColors.surface
                )
                .foregroundStyle(isSelected ? .purple : .primary)
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected
                                ? Color.purple.opacity(0.5)
                                : Color(.separator).opacity(0.3),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Effects List

    private var effectsList: some View {
        let filteredTypes = EffectType.allCases.filter { $0.category == selectedCategory }

        return VStack(spacing: LiquidSpacing.xs + 2) {
            ForEach(filteredTypes, id: \.self) { effectType in
                effectRow(effectType)
            }
        }
    }

    private func effectRow(_ effectType: EffectType) -> some View {
        let effect = effects.first { $0.type == effectType }
        let isActive = effect?.isEnabled ?? false
        let isExpanded = expandedEffectType == effectType

        return VStack(spacing: 0) {
            // Main row - tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedEffectType = isExpanded ? nil : effectType
                }
            } label: {
                HStack(spacing: LiquidSpacing.sm + 2) {
                    // Icon
                    Image(systemName: effectType.sfSymbol)
                        .font(LiquidTypography.body)
                        .frame(width: LiquidSpacing.xl)
                        .foregroundStyle(isActive ? .purple : .secondary)

                    // Name
                    Text(effectType.displayName)
                        .font(isActive ? LiquidTypography.subheadlineSemibold : LiquidTypography.subheadline)
                        .foregroundStyle(isActive ? .primary : .secondary)

                    Spacer()

                    // Mix badge (purple)
                    if isActive, let eff = effect {
                        Text("\(Int(eff.mix * 100))%")
                            .font(LiquidTypography.caption2Semibold)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, LiquidSpacing.sm)
                            .padding(.vertical, LiquidSpacing.xxs)
                            .background(Color.purple.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.xs + 2))
                    }

                    // Toggle
                    Toggle("", isOn: Binding(
                        get: { isActive },
                        set: { _ in toggleEffect(effectType) }
                    ))
                    .labelsHidden()
                    .tint(.purple)
                }
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.sm + 2)
            }
            .buttonStyle(.plain)

            // Expanded controls
            if isExpanded, isActive, let eff = effect {
                effectControls(effectType, effect: eff)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
                .fill(isActive
                      ? Color.purple.opacity(0.08)
                      : LiquidColors.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
                .strokeBorder(
                    isActive
                        ? Color.purple.opacity(0.3)
                        : Color(.separator).opacity(0.3),
                    lineWidth: isActive ? 1.0 : 0.5
                )
        )
    }

    // MARK: - Effect Controls (Expanded)

    private func effectControls(_ effectType: EffectType, effect: VideoEffect) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs + 2) {
            // Divider
            Divider()
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.bottom, LiquidSpacing.xs)

            // Mix slider
            sliderRow(
                label: "Mix",
                value: effect.mix,
                min: 0.0,
                max: 1.0,
                unit: nil
            ) { newVal in
                updateMix(effectType, mix: newVal)
            }

            // Parameter sliders
            ForEach(Array(effect.parameters.keys.sorted()), id: \.self) { paramName in
                if let param = effect.parameters[paramName],
                   let minVal = param.minValue?.asDouble,
                   let maxVal = param.maxValue?.asDouble,
                   let currentVal = param.currentValue.asDouble {
                    sliderRow(
                        label: param.displayName,
                        value: currentVal,
                        min: minVal,
                        max: maxVal,
                        unit: param.unit
                    ) { newVal in
                        updateParameter(effectType, paramName: paramName, value: newVal)
                    }
                }
            }

            // Remove Effect button (red, right-aligned)
            HStack {
                Spacer()
                Button("Remove Effect") {
                    removeEffect(effectType)
                }
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.error)
                .accessibilityHint("Removes this effect from the clip")
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.top, LiquidSpacing.xs)
            .padding(.bottom, LiquidSpacing.sm)
        }
    }

    // MARK: - Slider Row

    private func sliderRow(
        label: String,
        value: Double,
        min: Double,
        max: Double,
        unit: String?,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let displayValue: String = {
            if let unit, !unit.isEmpty {
                return String(format: "%.1f %@", value, unit)
            } else {
                return "\(Int(value * 100))%"
            }
        }()

        return HStack(spacing: 0) {
            Text(label)
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: min...max
            )
            .tint(.purple)
            .accessibilityLabel(label)
            .accessibilityValue(displayValue)

            Text(displayValue)
                .font(LiquidTypography.caption2Semibold)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LiquidSpacing.lg)
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        Button {
            onApply(effects)
            dismiss()
        } label: {
            Text("Apply Effects")
                .font(LiquidTypography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiquidSpacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
    }

    // MARK: - Computed Properties

    private var activeCount: Int {
        effects.filter(\.isEnabled).count
    }

    // MARK: - Actions

    private func toggleEffect(_ type: EffectType) {
        if let index = effects.firstIndex(where: { $0.type == type }) {
            effects[index] = effects[index].with(isEnabled: !effects[index].isEnabled)
        } else {
            if effects.count < EffectRegistry.maxEffectsPerClip {
                effects.append(VideoEffect.create(type))
            }
        }
    }

    private func updateMix(_ type: EffectType, mix: Double) {
        if let index = effects.firstIndex(where: { $0.type == type }) {
            effects[index] = effects[index].with(mix: mix)
        }
    }

    private func updateParameter(_ type: EffectType, paramName: String, value: Double) {
        if let index = effects.firstIndex(where: { $0.type == type }) {
            effects[index] = effects[index].updateParameter(paramName, value: .double_(value))
        }
    }

    private func removeEffect(_ type: EffectType) {
        effects.removeAll { $0.type == type }
        if expandedEffectType == type {
            expandedEffectType = nil
        }
    }

    private func resetAll() {
        effects.removeAll()
        expandedEffectType = nil
    }
}

#Preview {
    VideoEffectsSheet { _ in }
}

// MARK: - SF Symbol helper

/// Returns the SF Symbol name for a given `EffectType`.
///
/// Delegates to `EffectType.sfSymbol`, which is the single source of truth defined
/// in `EffectTypes.swift`. This free function exists as a convenience for call sites
/// that prefer a function call over a property access (e.g. inline panel builders).
func sfSymbolForEffectType(_ type: EffectType) -> String {
    type.sfSymbol
}

// MARK: - VideoEffectsInlinePanel

/// Compact inline video effects panel for embedding directly in the editor canvas area.
///
/// Unlike `VideoEffectsSheet` (which is presented modally), this view is designed
/// to be placed inline below the video preview at a fixed height of ~120 pt.
/// It provides:
/// - A horizontally scrollable row of effect-type pill buttons.
/// - A single expanded parameter slider area for the currently selected effect.
/// - A real-time `onEffectChanged` callback fired on every slider drag.
///
/// Usage:
/// ```swift
/// VideoEffectsInlinePanel(effects: $clipEffects) { updatedEffect in
///     applyEffect(updatedEffect)
/// }
/// ```
struct VideoEffectsInlinePanel: View {

    /// The full list of effects currently applied to the clip.
    @Binding var effects: [VideoEffect]

    /// Called in real-time whenever an effect parameter changes.
    var onEffectChanged: ((VideoEffect) -> Void)?

    /// The effect type whose pill is currently selected / expanded.
    @State private var selectedType: EffectType?

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable effect type pills
            effectPills
                .frame(height: 44)

            // Expanded slider area for the selected active effect
            if let type = selectedType,
               let effect = effects.first(where: { $0.type == type }),
               effect.isEnabled {
                expandedSlider(for: effect)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: selectedType.flatMap { type in
            effects.first(where: { $0.type == type })?.isEnabled == true ? 120 : 52
        } ?? 52)
        .animation(.easeInOut(duration: 0.2), value: selectedType)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
    }

    // MARK: Effect Pills

    private var effectPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.xs + 2) {
                ForEach(activeOrSelectableTypes, id: \.self) { type in
                    effectPill(type)
                }
            }
            .padding(.horizontal, LiquidSpacing.md)
        }
    }

    private func effectPill(_ type: EffectType) -> some View {
        let effect = effects.first(where: { $0.type == type })
        let isActive = effect?.isEnabled ?? false
        let isSelected = selectedType == type

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selectedType == type {
                    selectedType = nil
                } else {
                    selectedType = type
                    // Auto-enable the effect when its pill is tapped
                    if effect == nil {
                        toggleEffect(type)
                    }
                }
            }
        } label: {
            HStack(spacing: LiquidSpacing.xxs + 2) {
                Image(systemName: type.sfSymbol)
                    .font(.caption2)
                Text(type.displayName)
                    .font(isSelected ? LiquidTypography.captionMedium : LiquidTypography.caption)
            }
            .foregroundStyle(isSelected || isActive ? .purple : .secondary)
            .padding(.horizontal, LiquidSpacing.sm + 2)
            .padding(.vertical, LiquidSpacing.xs + 1)
            .background(
                isSelected
                    ? Color.purple.opacity(0.2)
                    : (isActive ? Color.purple.opacity(0.1) : LiquidColors.surface.opacity(0.6))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected
                        ? Color.purple.opacity(0.5)
                        : (isActive ? Color.purple.opacity(0.25) : Color(.separator).opacity(0.3)),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(type.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Expanded Slider

    @ViewBuilder
    private func expandedSlider(for effect: VideoEffect) -> some View {
        Divider()
            .padding(.horizontal, LiquidSpacing.md)

        // Show the mix slider as the primary control in the compact panel
        HStack(spacing: 0) {
            Text("Mix")
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            Slider(
                value: Binding(
                    get: { effect.mix },
                    set: { newMix in
                        updateMix(effect.type, mix: newMix)
                    }
                ),
                in: 0.0...1.0
            )
            .tint(.purple)
            .accessibilityLabel("Mix")
            .accessibilityValue("\(Int(effect.mix * 100)) percent")

            Text("\(Int(effect.mix * 100))%")
                .font(LiquidTypography.caption2Semibold)
                .foregroundStyle(.purple)
                .frame(width: 40, alignment: .trailing)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.top, LiquidSpacing.xs)
        .frame(height: 44)
    }

    // MARK: Computed Properties

    /// Returns active effects first (sorted by type name), followed by the first
    /// five inactive types from the selected category for quick access.
    private var activeOrSelectableTypes: [EffectType] {
        let active = effects.filter(\.isEnabled).map(\.type)
        let inactivePreview = EffectType.allCases
            .filter { !active.contains($0) }
            .prefix(5)
        return active + Array(inactivePreview)
    }

    // MARK: Actions

    private func toggleEffect(_ type: EffectType) {
        if let index = effects.firstIndex(where: { $0.type == type }) {
            effects[index] = effects[index].with(isEnabled: !effects[index].isEnabled)
            if let updated = effects.first(where: { $0.type == type }) {
                onEffectChanged?(updated)
            }
        } else if effects.count < EffectRegistry.maxEffectsPerClip {
            let newEffect = VideoEffect.create(type)
            effects.append(newEffect)
            onEffectChanged?(newEffect)
        }
    }

    private func updateMix(_ type: EffectType, mix: Double) {
        if let index = effects.firstIndex(where: { $0.type == type }) {
            effects[index] = effects[index].with(mix: mix)
            onEffectChanged?(effects[index])
        }
    }
}

#Preview("Inline Panel") {
    @Previewable @State var effects: [VideoEffect] = [
        VideoEffect.create(.blur).with(isEnabled: true),
        VideoEffect.create(.vignette).with(isEnabled: true, mix: 0.6),
    ]
    return VideoEffectsInlinePanel(effects: $effects)
        .padding()
        .background(Color.black)
}
