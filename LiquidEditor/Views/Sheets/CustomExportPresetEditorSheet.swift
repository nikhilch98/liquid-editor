// CustomExportPresetEditorSheet.swift
// LiquidEditor
//
// S2-25: Custom Export Preset Editor (XL form).
//
// Full-screen sheet for creating or editing a custom export preset. Bound
// to the existing `ExportPreset` / `ExportConfig` model pair (the spec
// references `CustomExportPreset` but the on-disk shape is the
// generic `ExportPreset` returned by `ExportPresetService`).
//
// Sections (Video / Audio / Container) mirror the premium UI redesign
// spec §2 XL form, with a live estimated file-size footer and two CTAs
// (Save as Preset / Export Now) emitted via callbacks.

import SwiftUI
import UIKit

// MARK: - CustomExportPresetEditorSheet

/// Sheet for creating or editing a custom export preset.
///
/// The sheet manages its own draft state bound to an `ExportConfig`; it
/// does NOT mutate any persisted preset directly. On confirm, it invokes
/// `onSavePreset` or `onExportNow` with the finalised preset / config.
@MainActor
struct CustomExportPresetEditorSheet: View {

    // MARK: - Inputs

    /// Existing preset being edited, or nil to create new.
    let initialPreset: ExportPreset?

    /// Estimated duration of the current timeline, used for file-size preview.
    let timelineDurationSeconds: TimeInterval

    /// Invoked when the user taps "Save as Preset".
    let onSavePreset: (ExportPreset) -> Void

    /// Invoked when the user taps "Export Now".
    let onExportNow: (ExportConfig) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Draft State

    @State private var name: String
    @State private var codec: ExportCodec
    @State private var resolution: PresetResolutionOption
    @State private var fps: Int
    @State private var bitrateMbps: Double
    @State private var colorSpace: ColorSpaceOption
    @State private var audioCodec: AudioCodecOption
    @State private var audioBitrateKbps: Int
    @State private var sampleRate: SampleRateOption
    @State private var format: ExportFormat
    @State private var hdrEnabled: Bool

    // MARK: - Init

    init(
        initialPreset: ExportPreset? = nil,
        timelineDurationSeconds: TimeInterval = 60,
        onSavePreset: @escaping (ExportPreset) -> Void,
        onExportNow: @escaping (ExportConfig) -> Void
    ) {
        self.initialPreset = initialPreset
        self.timelineDurationSeconds = max(1, timelineDurationSeconds)
        self.onSavePreset = onSavePreset
        self.onExportNow = onExportNow

        let seedConfig = initialPreset?.config ?? ExportConfig()
        _name = State(initialValue: initialPreset?.name ?? "Custom Preset")
        _codec = State(initialValue: seedConfig.codec)
        _resolution = State(initialValue: PresetResolutionOption.from(seedConfig.resolution))
        _fps = State(initialValue: seedConfig.fps)
        _bitrateMbps = State(initialValue: seedConfig.bitrateMbps)
        _colorSpace = State(initialValue: seedConfig.enableHdr ? .bt2020 : .bt709)
        _audioCodec = State(initialValue: AudioCodecOption.from(seedConfig.audioCodec))
        _audioBitrateKbps = State(initialValue: seedConfig.audioBitrate)
        _sampleRate = State(initialValue: .hz48)
        _format = State(initialValue: seedConfig.format)
        _hdrEnabled = State(initialValue: seedConfig.enableHdr)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                videoSection
                audioSection
                containerSection
            }
            .navigationTitle(initialPreset == nil ? "New Preset" : "Edit Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Preset Name") {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
        }
    }

    private var videoSection: some View {
        Section("Video") {
            Picker("Codec", selection: $codec) {
                ForEach(ExportCodec.allCases, id: \.self) { c in
                    Text(codecDisplayLabel(c)).tag(c)
                }
            }

            Picker("Resolution", selection: $resolution) {
                ForEach(PresetResolutionOption.allCases, id: \.self) { r in
                    Text(r.label).tag(r)
                }
            }

            Picker("Frame Rate", selection: $fps) {
                ForEach(Self.fpsOptions, id: \.self) { value in
                    Text("\(value) fps").tag(value)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bitrate")
                    Spacer()
                    Text("\(Int(bitrateMbps)) Mbps")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $bitrateMbps,
                    in: 2...200,
                    step: 1
                )
            }

            Picker("Color Space", selection: $colorSpace) {
                ForEach(ColorSpaceOption.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .onChange(of: colorSpace) { _, newValue in
                if newValue == .bt2020 { hdrEnabled = true }
            }
        }
    }

    private var audioSection: some View {
        Section("Audio") {
            Picker("Codec", selection: $audioCodec) {
                ForEach(AudioCodecOption.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bitrate")
                    Spacer()
                    Text("\(audioBitrateKbps) kbps")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(audioBitrateKbps) },
                        set: { audioBitrateKbps = Int($0) }
                    ),
                    in: 96...512,
                    step: 32
                )
                .disabled(audioCodec.isLossless)
            }

            Picker("Sample Rate", selection: $sampleRate) {
                ForEach(SampleRateOption.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
        }
    }

    private var containerSection: some View {
        Section("Container") {
            Picker("Format", selection: $format) {
                ForEach([ExportFormat.mp4, ExportFormat.mov], id: \.self) { fmt in
                    Text(fmt.displayName).tag(fmt)
                }
            }

            Toggle(isOn: $hdrEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HDR")
                    Text("Enables HDR10 / BT.2020 output where supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: hdrEnabled) { _, newValue in
                if !newValue, colorSpace == .bt2020 {
                    colorSpace = .bt709
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Estimated file size")
                    .font(.footnote.weight(.medium))
                Spacer()
                Text(estimatedSizeText)
                    .font(.footnote.monospacedDigit().weight(.semibold))
            }
            .padding(.horizontal)
            .padding(.top, 10)

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSavePreset(buildPreset())
                    dismiss()
                } label: {
                    Label("Save as Preset", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isValid)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onExportNow(buildConfig())
                    dismiss()
                } label: {
                    Label("Export Now", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding(.horizontal)
            .padding(.bottom, 14)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Derived

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bitrateMbps > 0
            && fps > 0
    }

    private var estimatedSizeText: String {
        let bytes = FileSizeEstimator.estimateVideoSizeBytes(
            config: buildConfig(),
            duration: timelineDurationSeconds
        )
        return FileSizeEstimator.formatBytes(bytes)
    }

    // MARK: - Building

    private func buildConfig() -> ExportConfig {
        ExportConfig(
            resolution: resolution.exportResolution,
            customWidth: resolution.customSize?.width,
            customHeight: resolution.customSize?.height,
            fps: fps,
            codec: codec,
            format: format,
            quality: .high,
            bitrateMbps: bitrateMbps,
            audioCodec: audioCodec.exportAudioCodec,
            audioBitrate: audioBitrateKbps,
            enableHdr: hdrEnabled,
            audioOnly: false,
            socialPreset: nil
        )
    }

    private func buildPreset() -> ExportPreset {
        let presetId = initialPreset?.id ?? "custom_\(UUID().uuidString)"
        let description = "\(resolution.label) • \(fps) fps • "
            + "\(Int(bitrateMbps)) Mbps • \(codecDisplayLabel(codec))"
        return ExportPreset(
            id: presetId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description,
            sfSymbolName: "slider.horizontal.3",
            config: buildConfig(),
            isBuiltIn: false
        )
    }

    // MARK: - Labels

    private func codecDisplayLabel(_ c: ExportCodec) -> String {
        switch c {
        case .h264:   return "H.264"
        case .h265:   return "HEVC (H.265)"
        case .proRes: return "ProRes"
        }
    }

    // MARK: - Constants

    private static let fpsOptions: [Int] = [24, 25, 30, 50, 60, 120]
}

// MARK: - Option Enums

/// Resolution options exposed by the editor.
enum PresetResolutionOption: String, CaseIterable, Hashable, Sendable {
    case r1080p
    case r4K
    case r8K

    var label: String {
        switch self {
        case .r1080p: return "1080p"
        case .r4K:    return "4K"
        case .r8K:    return "8K"
        }
    }

    var exportResolution: ExportResolution {
        switch self {
        case .r1080p: return .r1080p
        case .r4K:    return .r4K
        case .r8K:    return .custom
        }
    }

    var customSize: (width: Int, height: Int)? {
        switch self {
        case .r8K: return (7680, 4320)
        default:   return nil
        }
    }

    static func from(_ resolution: ExportResolution) -> PresetResolutionOption {
        switch resolution {
        case .r4K:    return .r4K
        case .custom: return .r8K
        default:      return .r1080p
        }
    }
}

/// Color space options.
enum ColorSpaceOption: String, CaseIterable, Hashable, Sendable {
    case bt709
    case bt2020

    var label: String {
        switch self {
        case .bt709:  return "BT.709 (SDR)"
        case .bt2020: return "BT.2020 (HDR)"
        }
    }
}

/// Audio codec options exposed by the editor (subset of ExportAudioCodec).
enum AudioCodecOption: String, CaseIterable, Hashable, Sendable {
    case aac
    case lossless

    var label: String {
        switch self {
        case .aac:      return "AAC"
        case .lossless: return "Lossless (ALAC)"
        }
    }

    var isLossless: Bool { self == .lossless }

    var exportAudioCodec: ExportAudioCodec {
        switch self {
        case .aac:      return .aac
        case .lossless: return .alac
        }
    }

    static func from(_ codec: ExportAudioCodec) -> AudioCodecOption {
        switch codec {
        case .aac:              return .aac
        case .alac, .wav, .flac: return .lossless
        }
    }
}

/// Sample-rate options.
enum SampleRateOption: String, CaseIterable, Hashable, Sendable {
    case hz44_1
    case hz48

    var label: String {
        switch self {
        case .hz44_1: return "44.1 kHz"
        case .hz48:   return "48 kHz"
        }
    }
}

// MARK: - Preview

#Preview("Custom Preset Editor") {
    CustomExportPresetEditorSheet(
        initialPreset: nil,
        timelineDurationSeconds: 120,
        onSavePreset: { _ in },
        onExportNow: { _ in }
    )
}
