// VOInputSourceSheet.swift
// LiquidEditor
//
// F6-21: Voice-over input-source selector sheet.
//
// Enumerates available audio inputs via `AVAudioSession.availableInputs` and
// presents each as a selectable row with a small horizontal level meter.
// Supports Built-in, Bluetooth, USB and AirPods style ports via the
// `AVAudioSession.Port` system taxonomy.
//
// This sheet is intentionally presentation-layer only. Selection is emitted
// through a callback so callers (e.g. `VoiceOverSheet`) can persist the
// chosen input and reconfigure the audio session.

import AVFoundation
import SwiftUI

// MARK: - VOInputSource

/// UI-level model describing a single audio-input source.
///
/// Decouples the sheet from `AVAudioSessionPortDescription` (which is not
/// `Sendable`) so the row model is safe to pass across concurrency domains.
struct VOInputSource: Identifiable, Sendable, Hashable {

    /// Stable UID (`AVAudioSessionPortDescription.uid`).
    let id: String

    /// Human-readable port name ("iPhone Microphone", "AirPods Pro", …).
    let name: String

    /// Raw port-type string (matches `AVAudioSession.Port` raw values).
    let portTypeRaw: String

    /// Classifies the raw port type into a high-level bucket for icon
    /// selection and for exposing groupings to the UI.
    var kind: Kind {
        switch portTypeRaw {
        case AVAudioSession.Port.bluetoothHFP.rawValue,
             AVAudioSession.Port.bluetoothA2DP.rawValue,
             AVAudioSession.Port.bluetoothLE.rawValue:
            return .bluetooth
        case AVAudioSession.Port.usbAudio.rawValue:
            return .usb
        case AVAudioSession.Port.airPlay.rawValue:
            return .airplay
        case AVAudioSession.Port.headsetMic.rawValue,
             AVAudioSession.Port.headphones.rawValue:
            return .airpods
        case AVAudioSession.Port.builtInMic.rawValue:
            return .builtIn
        default:
            return .other
        }
    }

    /// Coarse bucket used to drive iconography.
    enum Kind: Sendable {
        case builtIn
        case bluetooth
        case usb
        case airpods
        case airplay
        case other

        /// SF Symbol matching the kind.
        var systemImage: String {
            switch self {
            case .builtIn:   "mic.fill"
            case .bluetooth: "dot.radiowaves.left.and.right"
            case .usb:       "cable.connector"
            case .airpods:   "airpods.pro"
            case .airplay:   "airplayaudio"
            case .other:     "mic"
            }
        }
    }
}

// MARK: - VOInputSourceSheet

/// Modal sheet that lists available audio input sources.
///
/// Live mic levels per row are stubbed with a small timer-driven randomiser
/// so the UI can demonstrate the meter without depending on the real
/// `AVAudioEngine` tap (owned by `VoiceoverRecorder`). The real wiring is
/// a TODO noted in `updateLevels()`.
@MainActor
struct VOInputSourceSheet: View {

    // MARK: - Inputs

    /// Currently-selected source identifier, if any.
    let selectedSourceID: String?

    /// Invoked when the user taps a source row.
    let onSelect: (VOInputSource) -> Void

    /// Optional override for source discovery — used by previews + tests to
    /// inject deterministic data without touching `AVAudioSession`.
    var sourceProvider: @MainActor () -> [VOInputSource] = VOInputSourceSheet.liveSources

    // MARK: - Sheet State

    @Environment(\.dismiss) private var dismiss

    /// Discovered sources, refreshed when the sheet appears.
    @State private var sources: [VOInputSource] = []

    /// Live meter level per source id (0.0 … 1.0).
    @State private var levels: [String: Float] = [:]

    /// Drives the stub-level animation.
    @State private var meterTimer: Timer?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Input Source")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onAppear {
            sources = sourceProvider()
            startMeterStub()
        }
        .onDisappear { stopMeterStub() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if sources.isEmpty {
            emptyState
        } else {
            List {
                Section {
                    ForEach(sources) { source in
                        row(for: source)
                    }
                } header: {
                    Text("Available inputs")
                        .font(LiquidTypography.footnoteMedium)
                        .foregroundStyle(LiquidColors.textSecondary)
                } footer: {
                    Text("Tap a source to route your voice-over input.")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(LiquidColors.textTertiary)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "mic.slash")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(LiquidColors.textTertiary)
            Text("No inputs detected")
                .font(LiquidTypography.headline)
            Text("Connect a microphone, headset, or Bluetooth device to see it here.")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(LiquidSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Row

    private func row(for source: VOInputSource) -> some View {
        let isSelected = (source.id == selectedSourceID)
        return Button {
            onSelect(source)
            dismiss()
        } label: {
            HStack(spacing: LiquidSpacing.md) {
                Image(systemName: source.kind.systemImage)
                    .font(.system(size: LiquidSpacing.iconMedium, weight: .medium))
                    .foregroundStyle(
                        isSelected
                        ? LiquidColors.Accent.amber
                        : LiquidColors.textPrimary
                    )
                    .frame(width: LiquidSpacing.iconLarge)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(LiquidTypography.bodyMedium)
                        .foregroundStyle(LiquidColors.textPrimary)
                        .lineLimit(1)
                    levelBar(for: source.id)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(LiquidColors.Accent.amber)
                        .accessibilityLabel("Current route")
                }
            }
            .padding(.vertical, LiquidSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isSelected
            ? "\(source.name), currently selected"
            : source.name
        )
        .accessibilityHint("Double tap to select this input.")
    }

    // MARK: - Live Level Meter

    /// Horizontal bar backing the stubbed mic-level indicator.
    private func levelBar(for id: String) -> some View {
        let level = CGFloat(levels[id] ?? 0)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LiquidColors.fillTertiary)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(LiquidColors.Accent.amber)
                    .frame(width: geo.size.width * max(0, min(level, 1)))
                    .animation(.linear(duration: 0.12), value: level)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    // MARK: - Stub Level Driver

    /// Starts a 10 Hz timer that randomises per-source levels so the UI can
    /// demonstrate meter motion. Real integration should replace this with a
    /// live tap off `AVAudioEngine.inputNode`.
    ///
    /// TODO: replace with `VoiceoverRecorder`-driven live meter values.
    private func startMeterStub() {
        stopMeterStub()
        meterTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { _ in
            Task { @MainActor in
                updateLevels()
            }
        }
    }

    private func stopMeterStub() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateLevels() {
        var next: [String: Float] = [:]
        for source in sources {
            // TODO: swap for live input-level sampling per source.
            let isSelected = source.id == selectedSourceID
            let base: Float = isSelected ? 0.45 : 0.15
            let jitter = Float.random(in: -0.1...0.3)
            next[source.id] = max(0, min(1, base + jitter))
        }
        levels = next
    }

    // MARK: - Live Source Discovery

    /// Snapshots `AVAudioSession.availableInputs` on the main actor.
    static func liveSources() -> [VOInputSource] {
        let session = AVAudioSession.sharedInstance()
        let descriptions = session.availableInputs ?? []
        return descriptions.map { desc in
            VOInputSource(
                id: desc.uid,
                name: desc.portName,
                portTypeRaw: desc.portType.rawValue
            )
        }
    }
}

// MARK: - Preview

#Preview("Populated") {
    VOInputSourceSheet(
        selectedSourceID: "bluetooth-airpods",
        onSelect: { _ in },
        sourceProvider: {
            [
                VOInputSource(id: "builtin", name: "iPhone Microphone", portTypeRaw: AVAudioSession.Port.builtInMic.rawValue),
                VOInputSource(id: "bluetooth-airpods", name: "AirPods Pro", portTypeRaw: AVAudioSession.Port.headsetMic.rawValue),
                VOInputSource(id: "usb", name: "Shure MV7", portTypeRaw: AVAudioSession.Port.usbAudio.rawValue),
                VOInputSource(id: "bluetooth-speaker", name: "Kitchen Speaker", portTypeRaw: AVAudioSession.Port.bluetoothHFP.rawValue),
            ]
        }
    )
}

#Preview("Empty") {
    VOInputSourceSheet(
        selectedSourceID: nil,
        onSelect: { _ in },
        sourceProvider: { [] }
    )
}
