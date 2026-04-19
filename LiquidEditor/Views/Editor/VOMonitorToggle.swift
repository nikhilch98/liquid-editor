// VOMonitorToggle.swift
// LiquidEditor
//
// F6-22: Compact voice-over monitor toggle.
//
// Routes microphone input to the output (headphones / speaker) in real time
// so the user can hear themselves while recording. When enabled the icon
// turns amber; when disabled it stays in the secondary-label tint.
//
// The AVAudioEngine plumbing is stubbed in this view for now — the real
// wiring lives alongside `VoiceoverRecorder` and will be hooked up when
// live monitoring ships. The stub is clearly marked with `TODO` comments.

import AVFoundation
import SwiftUI

// MARK: - VOMonitorToggle

/// Compact toggle button for voice-over input monitoring.
///
/// The toggle is intentionally self-contained: it holds its own
/// `AVAudioEngine` instance (stubbed) and exposes a binding so parent views
/// can observe/force the on/off state (e.g. to disable monitoring when the
/// sheet is dismissed).
@MainActor
struct VOMonitorToggle: View {

    // MARK: - Inputs

    /// Binds the external on/off state.
    @Binding var isOn: Bool

    /// Optional callback fired after the toggle flips; useful for analytics
    /// or for parent views that need to react (e.g. dim the waveform UI).
    var onChange: ((Bool) -> Void)? = nil

    // MARK: - Local State

    /// Backing AVAudioEngine wired up with the mic → output pass-through.
    ///
    /// Stored as `@State` so it survives view recreation. The engine is
    /// configured lazily the first time the user enables monitoring.
    @State private var engine = AVAudioEngine()

    /// Whether the engine has been prepared at least once. Prevents
    /// repeatedly re-installing taps across toggle presses.
    @State private var enginePrepared = false

    // MARK: - Body

    var body: some View {
        Button {
            let newValue = !isOn
            isOn = newValue
            apply(monitoring: newValue)
            onChange?(newValue)
            Haptics.selection()
        } label: {
            Image(systemName: isOn ? "headphones.circle.fill" : "headphones")
                .font(.system(size: LiquidSpacing.iconLarge, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isOn
                    ? LiquidColors.Accent.amber
                    : LiquidColors.textSecondary
                )
                .padding(LiquidSpacing.sm)
                .frame(
                    minWidth: LiquidSpacing.minTouchTarget,
                    minHeight: LiquidSpacing.minTouchTarget
                )
                .background {
                    if isOn {
                        Circle()
                            .fill(LiquidColors.Accent.amberGlow)
                    }
                }
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice-over monitor")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Double tap to \(isOn ? "disable" : "enable") live headphone monitoring.")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .onDisappear {
            // Make sure we never leave the engine running when the
            // hosting view disappears — monitoring would keep routing
            // mic audio to output in the background otherwise.
            if isOn {
                apply(monitoring: false)
            }
        }
    }

    // MARK: - Monitoring Wiring (stub)

    /// Starts or stops monitoring based on the new toggle state.
    ///
    /// This is the hook where a real AVAudioEngine graph would be brought
    /// up. The shape of the graph is:
    ///
    ///   inputNode ──▶ mainMixerNode ──▶ outputNode
    ///
    /// With a small gain node in the middle to prevent feedback runaway.
    private func apply(monitoring newValue: Bool) {
        if newValue {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        // TODO: configure `AVAudioSession` with category `.playAndRecord`,
        //       mode `.voiceChat`, and options `[.defaultToSpeaker,
        //       .allowBluetooth]` before starting the engine.
        // TODO: connect `engine.inputNode` to `engine.mainMixerNode` using
        //       a low-gain `AVAudioMixerNode` to prevent feedback.
        // TODO: attach a peak-level tap to drive a VU indicator in the
        //       parent view.
        // TODO: call `engine.prepare(); try engine.start()` and surface
        //       engine failures to the user.
        enginePrepared = true
        _ = engine // silence unused warning until wiring lands
    }

    private func stopMonitoring() {
        // TODO: detach the mic → output connection and pause the engine.
        //       Use `engine.pause()` rather than `.stop()` to avoid
        //       re-allocating buffers on the next enable.
        if enginePrepared {
            // Reserved for future teardown. No-op today.
        }
    }
}

// MARK: - Haptics Helper

/// Thin wrapper around `UISelectionFeedbackGenerator` so the haptic call
/// site stays one-liner. Kept `fileprivate` to avoid leaking a general
/// haptics shim from this view.
private enum Haptics {
    @MainActor
    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
    }
}

// MARK: - Preview

#Preview("Off") {
    StatefulPreviewWrapper(false) { binding in
        VOMonitorToggle(isOn: binding)
            .padding()
            .background(LiquidColors.Canvas.base)
    }
}

#Preview("On") {
    StatefulPreviewWrapper(true) { binding in
        VOMonitorToggle(isOn: binding)
            .padding()
            .background(LiquidColors.Canvas.base)
    }
}

/// Preview helper that provides a mutable `Binding` in `#Preview` scope.
private struct StatefulPreviewWrapper<Content: View>: View {
    @State private var value: Bool
    private let content: (Binding<Bool>) -> Content

    init(_ initial: Bool, @ViewBuilder content: @escaping (Binding<Bool>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
