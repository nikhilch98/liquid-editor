// TextAnimationPicker.swift
// LiquidEditor
//
// Picker for enter/exit/sustain text animation presets.
// Shows a phase segmented control, duration sliders, and a scrollable list
// of animation presets for each phase.
// Pure iOS 26 SwiftUI with native styling.
//

import SwiftUI

// MARK: - Animation Phase Groups

/// Enter animation preset types.
let enterAnimations: [TextAnimationPresetType] = [
    .fadeIn, .slideInLeft, .slideInRight, .slideInTop,
    .slideInBottom, .scaleUp, .bounceIn, .typewriter,
    .glitchIn, .rotateIn, .blurIn, .popIn,
]

/// Exit animation preset types.
let exitAnimations: [TextAnimationPresetType] = [
    .fadeOut, .slideOutLeft, .slideOutRight, .slideOutTop,
    .slideOutBottom, .scaleDown, .bounceOut,
    .glitchOut, .rotateOut, .blurOut, .popOut,
]

/// Sustain animation preset types.
let sustainAnimations: [TextAnimationPresetType] = [
    .breathe, .pulse, .float, .shake, .flicker,
]

// MARK: - Display Name

/// Human-readable display name for an animation preset type.
func animationDisplayName(_ type: TextAnimationPresetType) -> String {
    switch type {
    case .fadeIn: return "Fade In"
    case .slideInLeft: return "Slide Left"
    case .slideInRight: return "Slide Right"
    case .slideInTop: return "Slide Top"
    case .slideInBottom: return "Slide Bottom"
    case .scaleUp: return "Scale Up"
    case .bounceIn: return "Bounce In"
    case .typewriter: return "Typewriter"
    case .glitchIn: return "Glitch In"
    case .rotateIn: return "Rotate In"
    case .blurIn: return "Blur In"
    case .popIn: return "Pop In"
    case .fadeOut: return "Fade Out"
    case .slideOutLeft: return "Slide Left"
    case .slideOutRight: return "Slide Right"
    case .slideOutTop: return "Slide Top"
    case .slideOutBottom: return "Slide Bottom"
    case .scaleDown: return "Scale Down"
    case .bounceOut: return "Bounce Out"
    case .glitchOut: return "Glitch Out"
    case .rotateOut: return "Rotate Out"
    case .blurOut: return "Blur Out"
    case .popOut: return "Pop Out"
    case .breathe: return "Breathe"
    case .pulse: return "Pulse"
    case .float: return "Float"
    case .shake: return "Shake"
    case .flicker: return "Flicker"
    }
}

/// SF Symbol name for an animation type.
func animationSFSymbol(_ type: TextAnimationPresetType) -> String {
    switch type {
    case .fadeIn, .fadeOut:
        return "circle.lefthalf.filled"
    case .slideInLeft, .slideOutLeft:
        return "arrow.left"
    case .slideInRight, .slideOutRight:
        return "arrow.right"
    case .slideInTop, .slideOutTop:
        return "arrow.up"
    case .slideInBottom, .slideOutBottom:
        return "arrow.down"
    case .scaleUp, .scaleDown:
        return "plus.magnifyingglass"
    case .bounceIn, .bounceOut:
        return "figure.run"
    case .typewriter:
        return "character.cursor.ibeam"
    case .glitchIn, .glitchOut:
        return "bolt.fill"
    case .rotateIn, .rotateOut:
        return "arrow.clockwise"
    case .blurIn, .blurOut:
        return "drop.fill"
    case .popIn, .popOut:
        return "burst.fill"
    case .breathe:
        return "wind"
    case .pulse:
        return "heart.fill"
    case .float:
        return "cloud.fill"
    case .shake:
        return "waveform"
    case .flicker:
        return "lightbulb.fill"
    }
}

// MARK: - TextAnimationPicker

/// View for picking text enter, exit, and sustain animations.
///
/// Displays a segmented control to switch between Enter, Exit, and Sustain
/// phases, with a scrollable list of animation presets for each phase
/// and duration sliders for enter/exit.
struct TextAnimationPicker: View {

    // MARK: - Properties

    /// Current enter animation (nil = none).
    @Binding var enterAnimation: TextAnimationPreset?

    /// Current exit animation (nil = none).
    @Binding var exitAnimation: TextAnimationPreset?

    /// Current sustain animation (nil = none).
    @Binding var sustainAnimation: TextAnimationPreset?

    /// Enter animation duration in microseconds.
    @Binding var enterDurationMicros: Int64

    /// Exit animation duration in microseconds.
    @Binding var exitDurationMicros: Int64

    /// Total clip duration in microseconds (for clamping).
    let clipDurationMicros: Int64

    /// Currently selected phase index: 0=Enter, 1=Exit, 2=Sustain.
    @State private var phaseIndex = 0

    private static let phaseLabels = ["Enter", "Exit", "Sustain"]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Phase selector
            Picker("Phase", selection: $phaseIndex) {
                ForEach(0..<Self.phaseLabels.count, id: \.self) { index in
                    Text(Self.phaseLabels[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.sm)
            .onChange(of: phaseIndex) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            // Duration slider (only for Enter and Exit)
            if phaseIndex == 0 {
                durationSlider(isEnter: true)
            }
            if phaseIndex == 1 {
                durationSlider(isEnter: false)
            }

            // Animation preset list
            animationList
        }
    }

    // MARK: - Duration Slider

    private func durationSlider(isEnter: Bool) -> some View {
        let maxDurationMicros = clipDurationMicros / 2
        let currentMicros = isEnter ? enterDurationMicros : exitDurationMicros
        let durationMs = Double(currentMicros) / 1000.0
        let maxMs = Double(maxDurationMicros) / 1000.0

        return HStack {
            Text("Duration")
                .font(LiquidTypography.subheadline)
                .frame(width: 80, alignment: .leading)

            Slider(
                value: Binding(
                    get: { min(durationMs, maxMs) },
                    set: { newValue in
                        let micros = Int64(newValue * 1000)
                        if isEnter {
                            enterDurationMicros = micros
                        } else {
                            exitDurationMicros = micros
                        }
                    }
                ),
                in: 0...(maxMs > 0 ? maxMs : 1)
            )

            Text(String(format: "%.1fs", durationMs / 1000.0))
                .font(LiquidTypography.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.vertical, LiquidSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isEnter ? "Enter" : "Exit") duration: \(String(format: "%.1f", durationMs / 1000.0)) seconds")
    }

    // MARK: - Animation List

    private var animationList: some View {
        let presets: [TextAnimationPresetType]
        let currentPreset: TextAnimationPreset?
        let updatePreset: (TextAnimationPreset?) -> Void

        switch phaseIndex {
        case 0:
            presets = enterAnimations
            currentPreset = enterAnimation
            updatePreset = { enterAnimation = $0 }
        case 1:
            presets = exitAnimations
            currentPreset = exitAnimation
            updatePreset = { exitAnimation = $0 }
        case 2:
            presets = sustainAnimations
            currentPreset = sustainAnimation
            updatePreset = { sustainAnimation = $0 }
        default:
            presets = []
            currentPreset = nil
            updatePreset = { _ in }
        }

        return ScrollView {
            LazyVStack(spacing: 2) {
                // "None" option
                animationTile(
                    label: "None",
                    sfSymbol: "xmark.circle",
                    isSelected: currentPreset == nil,
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        updatePreset(nil)
                    }
                )

                // Animation presets
                ForEach(presets, id: \.self) { type in
                    animationTile(
                        label: animationDisplayName(type),
                        sfSymbol: animationSFSymbol(type),
                        isSelected: currentPreset?.type == type,
                        onTap: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if currentPreset?.type == type {
                                updatePreset(nil)
                            } else {
                                updatePreset(TextAnimationPreset(type: type))
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
        }
    }

    // MARK: - Animation Tile

    private func animationTile(
        label: String,
        sfSymbol: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: sfSymbol)
                    .font(LiquidTypography.body)
                    .foregroundStyle(isSelected ? LiquidColors.primary : .secondary)
                    .frame(width: LiquidSpacing.xl)

                Text(label)
                    .font(LiquidTypography.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(LiquidTypography.subheadline)
                        .foregroundStyle(LiquidColors.primary)
                }
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium - 2)
                    .fill(isSelected
                          ? LiquidColors.primary.opacity(0.15)
                          : LiquidColors.tertiaryBackground.opacity(0.5))
                    .overlay(
                        isSelected
                            ? RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium - 2)
                                .strokeBorder(LiquidColors.primary.opacity(0.4), lineWidth: 1.5)
                            : nil
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
