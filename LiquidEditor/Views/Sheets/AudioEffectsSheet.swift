// AudioEffectsSheet.swift
// LiquidEditor
//
// Audio effects configuration sheet view matching Flutter predecessor layout.
// Fixed 4 sections: Compressor, Noise Gate, Noise Reduction, Beat Detection.
// Pure iOS 26 SwiftUI with native styling.

import SwiftUI

struct AudioEffectsSheet: View {

    // Compressor state
    @State private var compressorEnabled: Bool
    @State private var compThreshold: Double
    @State private var compRatio: Double
    @State private var compAttack: Double
    @State private var compRelease: Double
    @State private var compExpanded = false

    // Noise Gate state
    @State private var noiseGateEnabled: Bool
    @State private var gateThreshold: Double
    @State private var gateAttack: Double
    @State private var gateRelease: Double
    @State private var gateExpanded = false

    // Noise Reduction state
    @State private var noiseReductionEnabled: Bool
    @State private var noiseReductionIntensity: Double
    @State private var nrExpanded = false

    // Beat Detection state
    @State private var beatDetectionEnabled = false
    @State private var bdExpanded = false

    @Environment(\.dismiss) private var dismiss

    let onApply: (AudioEffectChain, Bool) -> Void

    init(
        initialChain: AudioEffectChain = .empty,
        initialVolume: Double = 1.0,
        onApply: @escaping (AudioEffectChain, Bool) -> Void
    ) {
        // Extract compressor params from chain if present
        let compressor = initialChain.effects.compactMap { effect -> CompressorParams? in
            if case .compressor(let params) = effect { return params }
            return nil
        }.first

        _compressorEnabled = State(initialValue: compressor?.isEnabled ?? false)
        _compThreshold = State(initialValue: compressor?.threshold ?? -20.0)
        _compRatio = State(initialValue: compressor?.ratio ?? 4.0)
        _compAttack = State(initialValue: compressor?.attack ?? 0.01)
        _compRelease = State(initialValue: compressor?.release ?? 0.1)

        // Extract noise gate params
        let gate = initialChain.effects.compactMap { effect -> NoiseGateParams? in
            if case .noiseGate(let params) = effect { return params }
            return nil
        }.first

        _noiseGateEnabled = State(initialValue: gate?.isEnabled ?? false)
        _gateThreshold = State(initialValue: gate?.threshold ?? -40.0)
        _gateAttack = State(initialValue: gate?.attack ?? 0.005)
        _gateRelease = State(initialValue: gate?.release ?? 0.05)

        _noiseReductionEnabled = State(initialValue: false)
        _noiseReductionIntensity = State(initialValue: 0.5)

        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title, Reset All, X close button
            headerRow
                .padding(.horizontal)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            // Fixed 4 effect sections
            ScrollView {
                VStack(spacing: LiquidSpacing.sm) {
                    // 1. Compressor
                    effectSection(
                        title: "Compressor",
                        symbol: "arrow.triangle.merge",
                        isEnabled: $compressorEnabled,
                        isExpanded: $compExpanded,
                        accentColor: .purple
                    ) {
                        audioSlider("Threshold", value: $compThreshold, range: ParameterRanges.compressorThreshold, unit: "dB", tintColor: .purple)
                        audioSlider("Ratio", value: $compRatio, range: ParameterRanges.compressorRatio, unit: ":1", tintColor: .purple)
                        audioSlider("Attack", value: $compAttack, range: ParameterRanges.compressorAttack, unit: "s", decimals: 3, tintColor: .purple)
                        audioSlider("Release", value: $compRelease, range: ParameterRanges.compressorRelease, unit: "s", tintColor: .purple)
                    }

                    // 2. Noise Gate
                    effectSection(
                        title: "Noise Gate",
                        symbol: "shield.slash",
                        isEnabled: $noiseGateEnabled,
                        isExpanded: $gateExpanded,
                        accentColor: .green
                    ) {
                        audioSlider("Threshold", value: $gateThreshold, range: ParameterRanges.noiseGateThreshold, unit: "dB", tintColor: .green)
                        audioSlider("Attack", value: $gateAttack, range: ParameterRanges.noiseGateAttack, unit: "s", decimals: 4, tintColor: .green)
                        audioSlider("Release", value: $gateRelease, range: ParameterRanges.noiseGateRelease, unit: "s", tintColor: .green)
                    }

                    // 3. Noise Reduction
                    effectSection(
                        title: "Noise Reduction",
                        symbol: "waveform.badge.minus",
                        isEnabled: $noiseReductionEnabled,
                        isExpanded: $nrExpanded,
                        accentColor: .orange
                    ) {
                        VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
                            HStack {
                                Text("Intensity")
                                    .font(LiquidTypography.caption)
                                Spacer()
                                Text(String(format: "%.0f%%", noiseReductionIntensity * 100))
                                    .font(LiquidTypography.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $noiseReductionIntensity, in: ParameterRanges.noiseReductionIntensity)
                                .tint(.orange)
                                .accessibilityLabel("Noise Reduction Intensity")
                                .accessibilityValue("\(Int(noiseReductionIntensity * 100)) percent")
                        }
                    }

                    // 4. Beat Detection
                    effectSection(
                        title: "Beat Detection",
                        symbol: "metronome",
                        isEnabled: $beatDetectionEnabled,
                        isExpanded: $bdExpanded,
                        accentColor: .pink
                    ) {
                        Text("Beat detection analyzes the audio track to find tempo and rhythm. Use this to sync cuts to music.")
                            .font(LiquidTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.vertical, LiquidSpacing.sm)
            }

            Divider()
                .padding(.horizontal)

            // Full-width Apply button
            Button {
                applyAndDismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
            .accessibilityLabel("Apply audio effects")
            .accessibilityHint("Applies the configured audio effects and dismisses the sheet")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Audio Effects")
                .font(LiquidTypography.headline)

            Spacer()

            Button("Reset All") {
                resetAll()
            }
            .font(LiquidTypography.caption)
            .foregroundStyle(.secondary)
            .accessibilityHint("Resets all audio effects to default values")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Dismisses the audio effects sheet")
        }
    }

    // MARK: - Effect Section

    private func effectSection<Content: View>(
        title: String,
        symbol: String,
        isEnabled: Binding<Bool>,
        isExpanded: Binding<Bool>,
        accentColor: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Header row - tap to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: symbol)
                        .font(LiquidTypography.body)
                        .foregroundStyle(isEnabled.wrappedValue ? accentColor : .secondary)

                    Text(title)
                        .font(LiquidTypography.subheadlineMedium)
                        .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)

                    Spacer()

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Toggle("", isOn: isEnabled)
                        .labelsHidden()
                        .tint(accentColor)
                        .accessibilityLabel("\(title) enabled")
                }
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) section")
            .accessibilityHint(isExpanded.wrappedValue ? "Collapse \(title) settings" : "Expand \(title) settings")

            // Expanded content
            if isExpanded.wrappedValue {
                VStack(spacing: 6) {
                    content()
                }
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.bottom, LiquidSpacing.md)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
                .fill(isEnabled.wrappedValue
                      ? accentColor.opacity(0.08)
                      : Color(.secondarySystemGroupedBackground).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
                .strokeBorder(
                    isEnabled.wrappedValue
                        ? accentColor.opacity(0.25)
                        : Color(.separator).opacity(0.3),
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Audio Slider

    // Parameter range constants
    private enum ParameterRanges {
        static let compressorThreshold: ClosedRange<Double> = -60...0
        static let compressorRatio: ClosedRange<Double> = 1...20
        static let compressorAttack: ClosedRange<Double> = 0.001...0.5
        static let compressorRelease: ClosedRange<Double> = 0.01...2

        static let noiseGateThreshold: ClosedRange<Double> = -80...0
        static let noiseGateAttack: ClosedRange<Double> = 0.0001...0.1
        static let noiseGateRelease: ClosedRange<Double> = 0.01...1

        static let noiseReductionIntensity: ClosedRange<Double> = 0...1
    }

    private func audioSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        decimals: Int = 1,
        tintColor: Color = .accentColor
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
            HStack {
                Text(label)
                    .font(LiquidTypography.caption)
                Spacer()
                Text(String(format: "%.\(decimals)f %@", value.wrappedValue, unit))
                    .font(LiquidTypography.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(tintColor)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: "%.\(decimals)f \(unit)", value.wrappedValue))
        }
    }

    // MARK: - Actions

    private func resetAll() {
        compressorEnabled = false
        compThreshold = -20.0
        compRatio = 4.0
        compAttack = 0.01
        compRelease = 0.1

        noiseGateEnabled = false
        gateThreshold = -40.0
        gateAttack = 0.005
        gateRelease = 0.05

        noiseReductionEnabled = false
        noiseReductionIntensity = 0.5

        beatDetectionEnabled = false
    }

    private func applyAndDismiss() {
        var effects: [AudioEffect] = []

        if compressorEnabled {
            let params = CompressorParams(
                id: UUID().uuidString,
                isEnabled: true,
                threshold: compThreshold,
                ratio: compRatio,
                attack: compAttack,
                release: compRelease
            )
            effects.append(.compressor(params))
        }

        if noiseGateEnabled {
            let params = NoiseGateParams(
                id: UUID().uuidString,
                isEnabled: true,
                threshold: gateThreshold,
                attack: gateAttack,
                release: gateRelease
            )
            effects.append(.noiseGate(params))
        }

        // Include noise reduction as a reverb-based effect with intensity as mix
        // (Noise reduction is modeled via the effect chain until a dedicated type is added)
        if noiseReductionEnabled {
            let nrParams = ReverbParams(
                id: UUID().uuidString,
                isEnabled: true,
                mix: noiseReductionIntensity,
                roomSize: 0.0,
                damping: 1.0
            )
            effects.append(.reverb(nrParams))
        }

        let chain = AudioEffectChain(effects: effects)
        onApply(chain, beatDetectionEnabled)
        dismiss()
    }
}

#Preview {
    AudioEffectsSheet { _, _ in }
}

// MARK: - EffectSlider

/// Reusable labelled slider row for an audio effect parameter.
///
/// Displays the label on the left, the current value + unit string on the right,
/// and a full-width `Slider` below. The value display switches to a percentage
/// format when `unit` is empty and `isPercent` is `true`.
///
/// This component is intentionally `private` — it is internal to the audio
/// effects UI files and should not be used from outside this module.
private struct EffectSlider: View {

    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var decimals: Int = 1
    var unit: String = ""
    var isPercent: Bool = false
    var tintColor: Color = .accentColor

    private var displayValue: String {
        if isPercent {
            return "\(Int(value * 100))%"
        }
        if unit.isEmpty {
            return String(format: "%.\(decimals)f", value)
        }
        return String(format: "%.\(decimals)f \(unit)", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
            HStack {
                Text(label)
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Text(displayValue)
                    .font(LiquidTypography.caption2)
                    .monospacedDigit()
                    .foregroundStyle(tintColor)
            }
            Slider(value: $value, in: range)
                .tint(tintColor)
                .accessibilityLabel(label)
                .accessibilityValue(displayValue)
        }
    }
}

// MARK: - AudioEffectsInlinePanel

/// Compact inline audio effects panel for embedding in the editor canvas area.
///
/// Shows four effect toggle buttons (Compressor, Noise Gate, Noise Reduction,
/// Beat Detection) in a horizontal row. Tapping a button toggles the effect on/off
/// AND expands a slider area below the row for real-time parameter adjustment.
/// The `onChanged` callback fires on every parameter change for live preview.
///
/// Approximate height: 52 pt (buttons only) / 120 pt (buttons + expanded slider).
struct AudioEffectsInlinePanel: View {

    // MARK: Inputs

    var initialChain: AudioEffectChain
    var noiseReductionIntensity: Double
    var noiseReductionEnabled: Bool

    /// Called on every parameter change for real-time preview.
    /// Parameters: (updatedChain, nrIntensity, nrEnabled, beatDetectionEnabled)
    var onChanged: ((AudioEffectChain, Double, Bool, Bool) -> Void)?

    // MARK: Internal state

    @State private var compressorEnabled: Bool
    @State private var compThreshold: Double
    @State private var compRatio: Double
    @State private var compAttack: Double
    @State private var compRelease: Double

    @State private var noiseGateEnabled: Bool
    @State private var gateThreshold: Double
    @State private var gateAttack: Double
    @State private var gateRelease: Double

    @State private var nrEnabled: Bool
    @State private var nrIntensity: Double

    @State private var beatDetectionEnabled: Bool = false

    /// Which effect section is currently expanded (nil = none).
    @State private var expandedEffect: InlineAudioEffect?

    // MARK: Init

    init(
        initialChain: AudioEffectChain = .empty,
        noiseReductionIntensity: Double = 0.5,
        noiseReductionEnabled: Bool = false,
        onChanged: ((AudioEffectChain, Double, Bool, Bool) -> Void)? = nil
    ) {
        self.initialChain = initialChain
        self.noiseReductionIntensity = noiseReductionIntensity
        self.noiseReductionEnabled = noiseReductionEnabled
        self.onChanged = onChanged

        let compressor = initialChain.effects.compactMap { effect -> CompressorParams? in
            if case .compressor(let params) = effect { return params }
            return nil
        }.first

        _compressorEnabled = State(initialValue: compressor?.isEnabled ?? false)
        _compThreshold = State(initialValue: compressor?.threshold ?? -20.0)
        _compRatio = State(initialValue: compressor?.ratio ?? 4.0)
        _compAttack = State(initialValue: compressor?.attack ?? 0.01)
        _compRelease = State(initialValue: compressor?.release ?? 0.1)

        let gate = initialChain.effects.compactMap { effect -> NoiseGateParams? in
            if case .noiseGate(let params) = effect { return params }
            return nil
        }.first

        _noiseGateEnabled = State(initialValue: gate?.isEnabled ?? false)
        _gateThreshold = State(initialValue: gate?.threshold ?? -40.0)
        _gateAttack = State(initialValue: gate?.attack ?? 0.005)
        _gateRelease = State(initialValue: gate?.release ?? 0.05)

        _nrEnabled = State(initialValue: noiseReductionEnabled)
        _nrIntensity = State(initialValue: noiseReductionIntensity)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Row of 4 toggle buttons
            effectToggleRow

            // Expanded slider area (appears below the button row)
            if let expanded = expandedEffect {
                Divider()
                    .padding(.horizontal, LiquidSpacing.md)
                expandedControls(for: expanded)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedEffect)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
    }

    // MARK: Toggle Row

    private var effectToggleRow: some View {
        HStack(spacing: LiquidSpacing.xs) {
            inlineToggleButton(
                title: "Comp",
                symbol: "arrow.triangle.merge",
                isEnabled: compressorEnabled,
                accentColor: .purple,
                effect: .compressor
            )
            inlineToggleButton(
                title: "Gate",
                symbol: "shield.slash",
                isEnabled: noiseGateEnabled,
                accentColor: .green,
                effect: .noiseGate
            )
            inlineToggleButton(
                title: "NR",
                symbol: "waveform.badge.minus",
                isEnabled: nrEnabled,
                accentColor: .orange,
                effect: .noiseReduction
            )
            inlineToggleButton(
                title: "Beats",
                symbol: "metronome",
                isEnabled: beatDetectionEnabled,
                accentColor: .pink,
                effect: .beatDetection
            )
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.sm)
        .frame(height: 52)
    }

    private func inlineToggleButton(
        title: String,
        symbol: String,
        isEnabled: Bool,
        accentColor: Color,
        effect: InlineAudioEffect
    ) -> some View {
        let isExpanded = expandedEffect == effect

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                // Tapping toggles expand; also toggles enable state on first tap
                if expandedEffect == effect {
                    expandedEffect = nil
                } else {
                    expandedEffect = effect
                    toggleEffect(effect)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.callout)
                Text(title)
                    .font(LiquidTypography.caption2)
            }
            .foregroundStyle(isEnabled || isExpanded ? accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidSpacing.xs + 1)
            .background(
                isExpanded
                    ? accentColor.opacity(0.18)
                    : (isEnabled ? accentColor.opacity(0.1) : LiquidColors.surface.opacity(0.5))
            )
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2, style: .continuous)
                    .strokeBorder(
                        isExpanded
                            ? accentColor.opacity(0.5)
                            : (isEnabled ? accentColor.opacity(0.25) : Color(.separator).opacity(0.25)),
                        lineWidth: isExpanded ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(isEnabled ? "enabled" : "disabled")")
        .accessibilityHint(isExpanded ? "Collapse \(title) settings" : "Expand \(title) settings")
    }

    // MARK: Expanded Controls

    @ViewBuilder
    private func expandedControls(for effect: InlineAudioEffect) -> some View {
        VStack(spacing: LiquidSpacing.xs) {
            switch effect {
            case .compressor:
                EffectSlider(label: "Threshold", value: $compThreshold,
                             range: -60...0, decimals: 1, unit: "dB", tintColor: .purple)
                    .onChange(of: compThreshold) { _, _ in notifyChanged() }
                EffectSlider(label: "Ratio", value: $compRatio,
                             range: 1...20, decimals: 1, unit: ":1", tintColor: .purple)
                    .onChange(of: compRatio) { _, _ in notifyChanged() }

            case .noiseGate:
                EffectSlider(label: "Threshold", value: $gateThreshold,
                             range: -80...0, decimals: 1, unit: "dB", tintColor: .green)
                    .onChange(of: gateThreshold) { _, _ in notifyChanged() }
                EffectSlider(label: "Release", value: $gateRelease,
                             range: 0.01...1.0, decimals: 2, unit: "s", tintColor: .green)
                    .onChange(of: gateRelease) { _, _ in notifyChanged() }

            case .noiseReduction:
                EffectSlider(label: "Intensity", value: $nrIntensity,
                             range: 0...1, isPercent: true, tintColor: .orange)
                    .onChange(of: nrIntensity) { _, _ in notifyChanged() }

            case .beatDetection:
                Text("Beat detection analyzes the audio track to find tempo and rhythm. Use this to sync cuts to music.")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.sm)
        .frame(height: 68)
    }

    // MARK: Actions

    private func toggleEffect(_ effect: InlineAudioEffect) {
        switch effect {
        case .compressor:
            compressorEnabled.toggle()
        case .noiseGate:
            noiseGateEnabled.toggle()
        case .noiseReduction:
            nrEnabled.toggle()
        case .beatDetection:
            beatDetectionEnabled.toggle()
        }
        notifyChanged()
    }

    private func notifyChanged() {
        var audioEffects: [AudioEffect] = []

        if compressorEnabled {
            audioEffects.append(.compressor(CompressorParams(
                id: "comp_inline",
                isEnabled: true,
                threshold: compThreshold,
                ratio: compRatio,
                attack: compAttack,
                release: compRelease
            )))
        }

        if noiseGateEnabled {
            audioEffects.append(.noiseGate(NoiseGateParams(
                id: "gate_inline",
                isEnabled: true,
                threshold: gateThreshold,
                attack: gateAttack,
                release: gateRelease
            )))
        }

        if nrEnabled {
            audioEffects.append(.reverb(ReverbParams(
                id: "nr_inline",
                isEnabled: true,
                mix: nrIntensity,
                roomSize: 0.0,
                damping: 1.0
            )))
        }

        let chain = AudioEffectChain(effects: audioEffects)
        onChanged?(chain, nrIntensity, nrEnabled, beatDetectionEnabled)
    }
}

// MARK: - InlineAudioEffect

/// Identifiable enum for the four audio effect sections shown in `AudioEffectsInlinePanel`.
private enum InlineAudioEffect: Hashable {
    case compressor
    case noiseGate
    case noiseReduction
    case beatDetection
}

#Preview("Audio Inline Panel") {
    AudioEffectsInlinePanel()
        .padding()
        .background(Color.black)
}
