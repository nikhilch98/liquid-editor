// GlobalSnapSettingsPanel.swift
// LiquidEditor
//
// T7-20 (Premium UI §10.3): Sub-panel reachable from the transport
// row's settings gear. Presents four toggles that govern which
// snap-targets are active during drag / trim / scrub gestures:
// - Playhead
// - Beat (from an attached BeatMap)
// - Marker
// - Grid (tier-based tick lines)
//
// Bound to `ProjectUIState.snap` via a `@Binding<SnapSettings>`. This
// keeps the panel stateless — callers own the ProjectUIState instance
// (usually stored on an @Observable ViewModel) and pass a binding.
//
// Visual: glass-styled sub-panel consistent with `ContextSubPanel`
// aesthetics. Compact — four rows, no extra chrome.
//
// Pure SwiftUI, iOS 26 native.

import SwiftUI

// MARK: - GlobalSnapSettingsPanel

/// Snap-target toggles panel.
struct GlobalSnapSettingsPanel: View {

    // MARK: - Inputs

    /// Two-way binding to the current snap settings.
    @Binding var settings: SnapSettings

    /// Close handler — caller pops the panel.
    let onClose: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            header

            Toggle(isOn: $settings.playhead) {
                label("Snap to playhead", systemImage: "line.3.horizontal.decrease")
            }

            Toggle(isOn: $settings.beat) {
                label("Snap to beat", systemImage: "metronome")
            }

            Toggle(isOn: $settings.marker) {
                label("Snap to marker", systemImage: "flag")
            }

            Toggle(isOn: $settings.grid) {
                label("Snap to grid", systemImage: "grid")
            }
        }
        .padding(LiquidSpacing.md)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .tint(.accentColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snap settings panel")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("SNAP")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close snap settings")
        }
    }

    // MARK: - Label

    @ViewBuilder
    private func label(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(.system(size: 14))
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Default snap") {
    @Previewable @State var settings = SnapSettings.default
    GlobalSnapSettingsPanel(settings: $settings, onClose: {})
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
