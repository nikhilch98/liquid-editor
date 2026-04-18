// ClipAnimationPanel.swift
// LiquidEditor
//
// TD8-14: Clip animation preset panel (In / Out / Loop) hosted in
// ContextSubPanel.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.
//
// Layout:
// - Three sections (In, Out, Loop), each rendered identically:
//     • section label
//     • horizontal scroll of preset chips (None, Fade, Slide, Zoom,
//       Spin, Bounce, Pop, Squish)
//     • duration slider 0–2 s with monospaced readout
// - The panel is stateless; parent owns a ``ClipAnimationConfig``.

import SwiftUI

// MARK: - ClipAnimationPreset

/// One of the pre-baked animation styles available for clip in/out/loop.
enum ClipAnimationPreset: String, CaseIterable, Identifiable, Sendable {
    case none, fade, slide, zoom, spin, bounce, pop, squish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .fade: return "Fade"
        case .slide: return "Slide"
        case .zoom: return "Zoom"
        case .spin: return "Spin"
        case .bounce: return "Bounce"
        case .pop: return "Pop"
        case .squish: return "Squish"
        }
    }

    /// SF Symbol used in the chip.
    var symbol: String {
        switch self {
        case .none: return "circle.slash"
        case .fade: return "circle.lefthalf.filled"
        case .slide: return "arrow.right"
        case .zoom: return "plus.magnifyingglass"
        case .spin: return "arrow.clockwise"
        case .bounce: return "arrow.up.and.down"
        case .pop: return "sparkle"
        case .squish: return "rectangle.compress.vertical"
        }
    }
}

// MARK: - ClipAnimationSettings

/// Parametric state for one of the three animation phases.
struct ClipAnimationSettings: Equatable, Sendable {
    /// Selected preset (`.none` disables the phase entirely).
    var preset: ClipAnimationPreset
    /// Duration in seconds, 0..2.
    var duration: Double

    /// Default neutral state — no animation, 0 s duration.
    static let neutral = ClipAnimationSettings(preset: .none, duration: 0)
}

// MARK: - ClipAnimationConfig

/// Aggregate model holding the in / out / loop phases for a single clip.
struct ClipAnimationConfig: Equatable, Sendable {
    var animIn: ClipAnimationSettings
    var animOut: ClipAnimationSettings
    var loop: ClipAnimationSettings

    /// Neutral state — everything `none` / 0 s.
    static let neutral = ClipAnimationConfig(
        animIn: .neutral, animOut: .neutral, loop: .neutral
    )
}

// MARK: - ClipAnimationPanel

/// Preset-based clip-animation panel hosted inside ``ContextSubPanel``.
@MainActor
struct ClipAnimationPanel: View {

    // MARK: - Inputs

    @Binding var config: ClipAnimationConfig
    let onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        ContextSubPanel(title: "Clip Animation", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 10) {
                section(title: "In", settings: $config.animIn)
                Divider().background(LiquidColors.Canvas.elev)
                section(title: "Out", settings: $config.animOut)
                Divider().background(LiquidColors.Canvas.elev)
                section(title: "Loop", settings: $config.loop)
            }
        }
    }

    // MARK: - Section

    private func section(
        title: String,
        settings: Binding<ClipAnimationSettings>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(LiquidColors.Text.secondary)

            presetScroller(settings: settings)

            durationRow(settings: settings)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) animation")
    }

    // MARK: - Preset scroller

    private func presetScroller(settings: Binding<ClipAnimationSettings>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClipAnimationPreset.allCases) { preset in
                    chip(preset: preset, settings: settings)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(
        preset: ClipAnimationPreset,
        settings: Binding<ClipAnimationSettings>
    ) -> some View {
        let isSelected = settings.wrappedValue.preset == preset
        return Button {
            settings.wrappedValue.preset = preset
            // When selecting a non-neutral preset, give it a sensible default
            // duration if the phase was previously disabled.
            if preset != .none, settings.wrappedValue.duration == 0 {
                settings.wrappedValue.duration = 0.4
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: preset.symbol)
                    .font(.caption)
                Text(preset.displayName)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(
                isSelected ? LiquidColors.Accent.amber : LiquidColors.Text.secondary
            )
            .frame(width: 52, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? LiquidColors.Accent.amberGlow
                            : LiquidColors.Canvas.elev
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.displayName) preset")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Duration row

    private func durationRow(
        settings: Binding<ClipAnimationSettings>
    ) -> some View {
        HStack(spacing: 10) {
            Text("Duration")
                .font(.caption2)
                .foregroundStyle(LiquidColors.Text.tertiary)
                .frame(width: 64, alignment: .leading)

            Slider(value: settings.duration, in: 0...2)
                .tint(LiquidColors.Accent.amber)
                .disabled(settings.wrappedValue.preset == .none)

            Text(String(format: "%.2f s", settings.wrappedValue.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LiquidColors.Text.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .opacity(settings.wrappedValue.preset == .none ? 0.5 : 1)
    }
}

// MARK: - Previews

#Preview("Clip animation panel") {
    ClipAnimationPanelPreviewHost()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidColors.Canvas.base)
        .preferredColorScheme(.dark)
}

private struct ClipAnimationPanelPreviewHost: View {
    @State private var config: ClipAnimationConfig = .neutral
    var body: some View {
        VStack {
            Spacer()
            ClipAnimationPanel(config: $config, onDismiss: { })
                .padding(.horizontal, 20)
        }
    }
}
