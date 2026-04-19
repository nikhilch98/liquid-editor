// ExportScreeniPhone.swift
// LiquidEditor
//
// Full-screen Export redesign for iPhone (S2-8).
//
// Layout (top to bottom):
//   1. Header chrome with close button.
//   2. Project preview thumbnail (~40% of height).
//   3. Vertical scroll of preset cards (Quick / Social / Pro / Custom).
//   4. Bottom CTA: "Export" primary + "Cancel" secondary.
//
// Wiring:
//   The screen owns a local `ExportPresetSelectionViewModel` (new, below)
//   that tracks selected preset + estimated duration and exposes an
//   `ExportJobStateMachine`. The actual export start call is left as a
//   `// TODO: wire to ExportService` marker so the visual contract and
//   state model can land first.

import SwiftUI
import UIKit

// MARK: - ExportPresetSelectionViewModel

/// Observable view model for preset-driven export screens.
///
/// Holds the selected preset plus a state machine so both iPhone and iPad
/// screens can share a single, test-friendly backing store.
@Observable
@MainActor
final class ExportPresetSelectionViewModel {

    // MARK: - State

    /// All presets available for selection (built-ins + customs).
    var presets: [ExportPreset]

    /// The currently selected preset, if any.
    var selectedPreset: ExportPreset?

    /// Estimated clip duration in seconds (used for size/ETA previews).
    var estimatedDurationSeconds: Double

    /// Thumbnail image for the preview area.
    var thumbnail: UIImage?

    /// Per-stream toggles & granular overrides used by the iPad inspector.
    var videoEnabled: Bool = true
    var audioEnabled: Bool = true
    var audioBitrateKbps: Double = 256
    var colorProfile: ExportColorProfile = .standard

    /// Finite-state model of the current export.
    let stateMachine: ExportJobStateMachine

    // MARK: - Init

    init(
        presets: [ExportPreset] = ExportPresetService.allPresets
            + ExportPresetService.loadCustomPresets(),
        selected: ExportPreset? = nil,
        estimatedDurationSeconds: Double = 60,
        thumbnail: UIImage? = nil,
        stateMachine: ExportJobStateMachine = ExportJobStateMachine()
    ) {
        self.presets = presets
        self.selectedPreset = selected ?? presets.first
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.thumbnail = thumbnail
        self.stateMachine = stateMachine
    }

    // MARK: - Grouping

    /// Presets grouped by category in display order.
    var groupedPresets: [(category: ExportPresetCategory, presets: [ExportPreset])] {
        let buckets = Dictionary(grouping: presets) { ExportPresetCategory.infer(from: $0) }
        return ExportPresetCategory.allCases.compactMap { cat in
            guard let list = buckets[cat], !list.isEmpty else { return nil }
            return (cat, list)
        }
    }

    // MARK: - Intents

    func select(_ preset: ExportPreset) {
        selectedPreset = preset
    }

    /// Kick off the export.
    ///
    /// Currently transitions the state machine to `.exporting(0, 0)` and
    /// leaves the real pipeline work as a TODO — the redesigned screens
    /// are meant to land visual + state first.
    func startExport() {
        guard selectedPreset != nil else { return }
        stateMachine.transition(to: .exporting(progress: 0, eta: estimatedDurationSeconds))
        // TODO: wire to ExportService.startExport(config:) and forward
        // progress updates into `stateMachine.transition(to: .exporting(...))`.
    }

    func cancel() {
        stateMachine.cancel()
        // TODO: wire to ExportService.cancelExport(exportId:) once an
        // export handle is captured at start time.
    }
}

// MARK: - ExportColorProfile

/// Color profile selection offered by the iPad settings inspector.
enum ExportColorProfile: String, CaseIterable, Identifiable, Sendable {
    case standard
    case hdr10
    case dolbyVision

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Rec. 709 (Standard)"
        case .hdr10: return "HDR10"
        case .dolbyVision: return "Dolby Vision"
        }
    }
}

// MARK: - ExportScreeniPhone

/// Full-screen Export UI for iPhone.
struct ExportScreeniPhone: View {

    // MARK: - Inputs

    @State private var selection: ExportPresetSelectionViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - Layout Constants

    /// Approximate preview height as a fraction of screen height.
    private static let previewHeightFraction: CGFloat = 0.40

    /// Corner radius for the preview surface.
    private static let previewCornerRadius: CGFloat = LiquidSpacing.cornerXLarge

    /// Bottom CTA height.
    private static let ctaHeight: CGFloat = LiquidSpacing.buttonHeight

    // MARK: - Init

    init(viewModel: ExportPresetSelectionViewModel = ExportPresetSelectionViewModel()) {
        _selection = State(initialValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, LiquidSpacing.xl)
                    .padding(.top, LiquidSpacing.md)
                    .padding(.bottom, LiquidSpacing.sm)

                previewSection(height: proxy.size.height * Self.previewHeightFraction)
                    .padding(.horizontal, LiquidSpacing.xl)
                    .padding(.bottom, LiquidSpacing.lg)

                presetList
                    .padding(.horizontal, LiquidSpacing.xl)

                Spacer(minLength: 0)

                bottomBar
                    .padding(.horizontal, LiquidSpacing.xl)
                    .padding(.bottom, LiquidSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LiquidColors.Canvas.base.ignoresSafeArea())
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export")
                    .font(LiquidTypography.title2)
                    .foregroundStyle(LiquidColors.Text.primary)
                Text(stateSubtitle)
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(LiquidColors.Text.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(LiquidColors.Text.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close export")
        }
    }

    private var stateSubtitle: String {
        switch selection.stateMachine.state {
        case .idle: return "Choose a preset to get started"
        case .exporting(let progress, _): return "Exporting · \(Int(progress * 100))%"
        case .success: return "Export finished"
        case .error(let message): return "Error: \(message)"
        case .cancelled: return "Export cancelled"
        }
    }

    // MARK: - Preview

    private func previewSection(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.previewCornerRadius, style: .continuous)
                .fill(LiquidColors.Canvas.raised)

            if let thumb = selection.thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Self.previewCornerRadius,
                                         style: .continuous)
                    )
            } else {
                VStack(spacing: LiquidSpacing.sm) {
                    Image(systemName: "film")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(LiquidColors.Text.tertiary)
                    Text("Project Preview")
                        .font(LiquidTypography.footnote)
                        .foregroundStyle(LiquidColors.Text.secondary)
                }
            }

            // Progress overlay when exporting.
            if let progress = selection.stateMachine.state.progressValue {
                ZStack {
                    RoundedRectangle(cornerRadius: Self.previewCornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                    VStack(spacing: LiquidSpacing.sm) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        ProgressView(value: progress)
                            .tint(.white)
                            .frame(maxWidth: 220)
                    }
                }
            }
        }
        .frame(height: height)
        .overlay(
            RoundedRectangle(cornerRadius: Self.previewCornerRadius, style: .continuous)
                .stroke(LiquidStroke.hairlineColor, lineWidth: LiquidStroke.hairlineWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Project preview")
    }

    // MARK: - Preset List

    private var presetList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: LiquidSpacing.xl) {
                ForEach(selection.groupedPresets, id: \.category.id) { group in
                    presetSection(category: group.category, presets: group.presets)
                }
            }
            .padding(.bottom, LiquidSpacing.xl)
        }
    }

    private func presetSection(
        category: ExportPresetCategory,
        presets: [ExportPreset]
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            HStack(spacing: LiquidSpacing.sm) {
                Image(systemName: category.sfSymbolName)
                    .foregroundStyle(category.accentColor)
                Text(category.displayName)
                    .font(LiquidTypography.subheadlineSemibold)
                    .foregroundStyle(LiquidColors.Text.primary)
            }
            .padding(.leading, LiquidSpacing.xs)

            ForEach(presets) { preset in
                ExportPresetCard(
                    preset: preset,
                    category: category,
                    isSelected: selection.selectedPreset == preset,
                    estimatedDurationSeconds: selection.estimatedDurationSeconds,
                    onTap: {
                        let gen = UISelectionFeedbackGenerator()
                        gen.selectionChanged()
                        selection.select(preset)
                    }
                )
            }
        }
    }

    // MARK: - Bottom CTA

    private var bottomBar: some View {
        VStack(spacing: LiquidSpacing.sm) {
            Button {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                selection.startExport()
            } label: {
                Text(exportButtonLabel)
                    .font(LiquidTypography.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.ctaHeight)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selection.selectedPreset == nil || selection.stateMachine.state.isRunning)
            .accessibilityHint("Starts exporting with the selected preset")

            Button(role: .cancel) {
                if selection.stateMachine.state.isRunning {
                    selection.cancel()
                } else {
                    dismiss()
                }
            } label: {
                Text(selection.stateMachine.state.isRunning ? "Cancel Export" : "Cancel")
                    .font(LiquidTypography.subheadlineSemibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: LiquidSpacing.buttonHeightCompact)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LiquidColors.Text.secondary)
        }
    }

    private var exportButtonLabel: String {
        switch selection.stateMachine.state {
        case .idle, .cancelled, .error: return "Export"
        case .exporting: return "Exporting…"
        case .success: return "Export Again"
        }
    }
}

#Preview {
    ExportScreeniPhone()
}
