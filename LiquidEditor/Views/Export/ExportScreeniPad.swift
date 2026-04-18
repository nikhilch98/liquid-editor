// ExportScreeniPad.swift
// LiquidEditor
//
// Three-column Export redesign for iPad (S2-9).
//
// Layout (NavigationSplitView):
//   - Left:   preset sidebar (~250pt) grouped by Quick / Social / Pro / Custom.
//   - Middle: preview surface with project thumbnail + live progress overlay.
//   - Right:  settings inspector (~320pt) with per-stream toggles, color
//             profile picker, and audio bitrate slider.
//
// Bottom toolbar hosts: Export / Save Preset / Cancel.
//
// This screen shares `ExportPresetSelectionViewModel` with the iPhone
// screen so state (selection, state machine) can be carried between form
// factors when the user rotates or switches idioms.

import SwiftUI
import UIKit

// MARK: - ExportScreeniPad

struct ExportScreeniPad: View {

    // MARK: - State

    @State private var selection: ExportPresetSelectionViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var savePresetSheetPresented = false
    @State private var savePresetName: String = ""

    @Environment(\.dismiss) private var dismiss

    // MARK: - Layout Constants

    private static let sidebarIdealWidth: CGFloat = 260
    private static let inspectorIdealWidth: CGFloat = 320

    // MARK: - Init

    init(viewModel: ExportPresetSelectionViewModel = ExportPresetSelectionViewModel()) {
        _selection = State(initialValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: Self.sidebarIdealWidth,
                    max: 320
                )
        } content: {
            VStack(spacing: 0) {
                previewColumn
                Divider()
                bottomToolbar
                    .padding(.horizontal, LiquidSpacing.xl)
                    .padding(.vertical, LiquidSpacing.lg)
            }
            .background(LiquidColors.background.ignoresSafeArea())
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(
                    min: 280,
                    ideal: Self.inspectorIdealWidth,
                    max: 400
                )
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $savePresetSheetPresented) {
            savePresetSheet
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            ForEach(selection.groupedPresets, id: \.category.id) { group in
                Section {
                    ForEach(group.presets) { preset in
                        sidebarRow(preset: preset, category: group.category)
                            .listRowInsets(EdgeInsets(
                                top: LiquidSpacing.xs,
                                leading: LiquidSpacing.sm,
                                bottom: LiquidSpacing.xs,
                                trailing: LiquidSpacing.sm
                            ))
                    }
                } header: {
                    HStack(spacing: LiquidSpacing.sm) {
                        Image(systemName: group.category.sfSymbolName)
                            .foregroundStyle(group.category.accentColor)
                        Text(group.category.displayName)
                            .font(LiquidTypography.subheadlineSemibold)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Presets")
    }

    private func sidebarRow(preset: ExportPreset, category: ExportPresetCategory) -> some View {
        Button {
            selection.select(preset)
        } label: {
            HStack(spacing: LiquidSpacing.md) {
                Image(systemName: preset.sfSymbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(category.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(LiquidTypography.bodySemibold)
                    Text(preset.config.resolution.label + " · " + preset.config.codec.displayName)
                        .font(LiquidTypography.caption)
                        .foregroundStyle(LiquidColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if selection.selectedPreset == preset {
                    Image(systemName: "checkmark")
                        .foregroundStyle(category.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            selection.selectedPreset == preset ? [.isSelected, .isButton] : [.isButton]
        )
    }

    // MARK: - Preview Column

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
            HStack {
                Text(selection.selectedPreset?.name ?? "No Preset Selected")
                    .font(LiquidTypography.title2)
                Spacer()
                Text(stateBadgeLabel)
                    .font(LiquidTypography.caption)
                    .padding(.horizontal, LiquidSpacing.md)
                    .padding(.vertical, LiquidSpacing.xs)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, LiquidSpacing.xl)
            .padding(.top, LiquidSpacing.xl)

            previewSurface
                .padding(.horizontal, LiquidSpacing.xl)

            Spacer(minLength: 0)
        }
    }

    private var previewSurface: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerXLarge, style: .continuous)
                    .fill(LiquidColors.surface)

                if let thumb = selection.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: LiquidSpacing.md) {
                        Image(systemName: "film")
                            .font(.system(size: 64, weight: .medium))
                            .foregroundStyle(LiquidColors.textTertiary)
                        Text("Project Preview")
                            .font(LiquidTypography.footnote)
                            .foregroundStyle(LiquidColors.textSecondary)
                    }
                }

                if let progress = selection.stateMachine.state.progressValue {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: LiquidSpacing.cornerXLarge,
                            style: .continuous
                        )
                        .fill(Color.black.opacity(0.35))
                        VStack(spacing: LiquidSpacing.md) {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            ProgressView(value: progress)
                                .tint(.white)
                                .frame(maxWidth: 280)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerXLarge, style: .continuous)
                    .stroke(LiquidColors.glassBorder, lineWidth: 1)
            )
        }
        .frame(minHeight: 300)
    }

    private var stateBadgeLabel: String {
        switch selection.stateMachine.state {
        case .idle: return "Idle"
        case .exporting(let p, _): return "Exporting · \(Int(p * 100))%"
        case .success: return "Done"
        case .error: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        Form {
            Section("Streams") {
                Toggle("Video", isOn: videoEnabledBinding)
                Toggle("Audio", isOn: audioEnabledBinding)
            }

            Section("Color") {
                Picker("Color Profile", selection: colorProfileBinding) {
                    ForEach(ExportColorProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Audio Bitrate") {
                VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
                    HStack {
                        Text("Bitrate")
                        Spacer()
                        Text("\(Int(selection.audioBitrateKbps)) kbps")
                            .monospacedDigit()
                            .foregroundStyle(LiquidColors.textSecondary)
                    }
                    Slider(
                        value: audioBitrateBinding,
                        in: 64...512,
                        step: 32
                    )
                    .accessibilityLabel("Audio bitrate")
                    .accessibilityValue("\(Int(selection.audioBitrateKbps)) kilobits per second")
                }
            }

            if let preset = selection.selectedPreset {
                Section("Preset Details") {
                    detailRow(label: "Resolution",
                              value: preset.config.resolution == .custom
                                ? "\(preset.config.outputWidth)x\(preset.config.outputHeight)"
                                : preset.config.resolution.label)
                    detailRow(label: "FPS", value: "\(preset.config.fps)")
                    detailRow(label: "Codec", value: preset.config.codec.displayName)
                    detailRow(label: "Format", value: preset.config.format.displayName)
                    detailRow(
                        label: "Bitrate",
                        value: String(format: "%.1f Mbps", preset.config.effectiveBitrateMbps)
                    )
                    if preset.config.enableHdr {
                        detailRow(label: "HDR", value: "Enabled")
                    }
                }
            }
        }
        .navigationTitle("Inspector")
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(LiquidColors.textSecondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button(role: .cancel) {
                if selection.stateMachine.state.isRunning {
                    selection.cancel()
                } else {
                    dismiss()
                }
            } label: {
                Text(selection.stateMachine.state.isRunning ? "Cancel Export" : "Cancel")
                    .frame(maxWidth: .infinity)
                    .frame(height: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                savePresetName = selection.selectedPreset?.name.appending(" Copy") ?? "My Preset"
                savePresetSheetPresented = true
            } label: {
                Label("Save Preset", systemImage: "square.and.arrow.down.on.square")
                    .frame(maxWidth: .infinity)
                    .frame(height: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(selection.selectedPreset == nil)

            Button {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                selection.startExport()
            } label: {
                Text(selection.stateMachine.state.isRunning ? "Exporting…" : "Export")
                    .frame(maxWidth: .infinity)
                    .frame(height: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selection.selectedPreset == nil || selection.stateMachine.state.isRunning)
        }
    }

    // MARK: - Save Preset Sheet

    private var savePresetSheet: some View {
        NavigationStack {
            Form {
                Section("Preset Name") {
                    TextField("Preset Name", text: $savePresetName)
                        .autocorrectionDisabled()
                }
                if let base = selection.selectedPreset {
                    Section("Copied From") {
                        Text(base.name)
                            .foregroundStyle(LiquidColors.textSecondary)
                    }
                }
            }
            .navigationTitle("Save Preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { savePresetSheetPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCurrentAsCustomPreset()
                        savePresetSheetPresented = false
                    }
                    .disabled(savePresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Bindings (Inspector)

    private var videoEnabledBinding: Binding<Bool> {
        Binding(
            get: { selection.videoEnabled },
            set: { selection.videoEnabled = $0 }
        )
    }

    private var audioEnabledBinding: Binding<Bool> {
        Binding(
            get: { selection.audioEnabled },
            set: { selection.audioEnabled = $0 }
        )
    }

    private var audioBitrateBinding: Binding<Double> {
        Binding(
            get: { selection.audioBitrateKbps },
            set: { selection.audioBitrateKbps = $0 }
        )
    }

    private var colorProfileBinding: Binding<ExportColorProfile> {
        Binding(
            get: { selection.colorProfile },
            set: { selection.colorProfile = $0 }
        )
    }

    // MARK: - Actions

    private func saveCurrentAsCustomPreset() {
        guard let base = selection.selectedPreset else { return }
        let trimmed = savePresetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let custom = ExportPreset(
            id: "custom_\(UUID().uuidString)",
            name: trimmed,
            description: "Custom preset based on \(base.name)",
            sfSymbolName: "slider.horizontal.3",
            config: base.config,
            isBuiltIn: false
        )
        // TODO: wire to ExportPresetService.addCustomPreset(_:) — the current
        // selection VM holds the in-memory list; the queue/service persists.
        selection.presets.append(custom)
        selection.select(custom)
    }
}

#Preview {
    ExportScreeniPad()
}
