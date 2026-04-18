// NewProjectSheet.swift
// LiquidEditor
//
// Sheet presented when the user starts a new project from the Library tab.
// Collects project name, aspect, resolution, FPS, and optional starter
// `LibraryTemplate`, then hands a `NewProjectConfig` back to the caller for
// actual project creation (ProjectRepository wiring done at the call site).
//
// Introduced for S2-18 (premium UI redesign: new-project creation flow).

import SwiftUI

// MARK: - NewProjectConfig

/// The configuration payload produced by `NewProjectSheet` on Create.
///
/// The sheet is intentionally decoupled from `ProjectRepository` -- the caller
/// is responsible for translating this into a `Project` and persisting it.
struct NewProjectConfig: Sendable, Equatable {

    /// Project display name (trimmed, non-empty validated by the sheet).
    let name: String

    /// Target canvas aspect ratio.
    let aspectRatio: AspectRatioSetting

    /// Target export resolution.
    let resolution: Resolution

    /// Target frame rate.
    let frameRate: FrameRateOption

    /// Optional starter template chosen by the user.
    let template: LibraryTemplate?
}

// MARK: - NewProjectSheet

/// Modal form for creating a new project.
///
/// Wrapped in a `NavigationStack` so toolbar items (Cancel / Create) render
/// correctly when presented via `.sheet()`. Create is disabled until a
/// non-empty, non-whitespace name is provided.
struct NewProjectSheet: View {

    /// Optional set of selectable starter templates. Defaults to the built-in
    /// library; injectable for preview / test contexts.
    let templates: [LibraryTemplate]

    /// Callback invoked when the user taps Create with a valid configuration.
    let onCreate: (NewProjectConfig) -> Void

    /// Dismiss handle (used for Cancel and after Create).
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var projectName: String = ""
    @State private var selectedAspect: AspectRatioSetting = .landscape16x9
    @State private var selectedResolution: Resolution = .fullHD1080p
    @State private var selectedFrameRate: FrameRateOption = .fixed30
    @State private var selectedTemplateID: UUID? = nil

    // MARK: - Options

    /// Aspect ratios surfaced in the picker (matches spec S2-18).
    private let aspectOptions: [AspectRatioSetting] = [
        .landscape16x9,
        .portrait9x16,
        .square1x1,
        .portrait4x5,
    ]

    /// Resolution options surfaced in the picker.
    private let resolutionOptions: [Resolution] = [
        .fullHD1080p,
        .uhd4k,
    ]

    /// Frame-rate options surfaced in the picker.
    private let frameRateOptions: [FrameRateOption] = [
        .fixed24,
        .fixed30,
        .fixed60,
    ]

    // MARK: - Init

    init(
        templates: [LibraryTemplate] = LibraryTemplate.builtIn,
        onCreate: @escaping (NewProjectConfig) -> Void
    ) {
        self.templates = templates
        self.onCreate = onCreate
    }

    // MARK: - Derived State

    /// Trimmed project name used for both validation and submission.
    private var trimmedName: String {
        projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the Create CTA should be enabled.
    private var canCreate: Bool {
        !trimmedName.isEmpty
    }

    /// Currently selected template (if any).
    private var selectedTemplate: LibraryTemplate? {
        guard let id = selectedTemplateID else { return nil }
        return templates.first(where: { $0.id == id })
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                formatSection
                templateSection
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: submit)
                        .disabled(!canCreate)
                }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Project name", text: $projectName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .submitLabel(.done)
        }
    }

    private var formatSection: some View {
        Section("Format") {
            Picker("Aspect", selection: $selectedAspect) {
                ForEach(aspectOptions, id: \.label) { option in
                    Text(option.label).tag(option)
                }
            }

            Picker("Resolution", selection: $selectedResolution) {
                ForEach(resolutionOptions, id: \.rawValue) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("Frame Rate", selection: $selectedFrameRate) {
                ForEach(frameRateOptions, id: \.rawValue) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
    }

    @ViewBuilder
    private var templateSection: some View {
        if !templates.isEmpty {
            Section("Starter Template (optional)") {
                Picker("Template", selection: $selectedTemplateID) {
                    Text("None").tag(UUID?.none)
                    ForEach(templates) { template in
                        Text(template.name).tag(UUID?.some(template.id))
                    }
                }

                if let template = selectedTemplate {
                    templatePreview(template)
                }
            }
        }
    }

    private func templatePreview(_ template: LibraryTemplate) -> some View {
        HStack(spacing: LiquidSpacing.sm) {
            Image(systemName: template.category.iconSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.body)
                Text("\(Int(template.durationSec))s • \(template.presetClips.count) clips • \(template.aspectRatio.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func submit() {
        guard canCreate else { return }
        let config = NewProjectConfig(
            name: trimmedName,
            aspectRatio: selectedAspect,
            resolution: selectedResolution,
            frameRate: selectedFrameRate,
            template: selectedTemplate
        )
        onCreate(config)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NewProjectSheet { _ in }
}
