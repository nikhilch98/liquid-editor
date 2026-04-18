// LUTPickerSheet.swift
// LiquidEditor
//
// LUT picker sheet (C5-5).
//
// Presents a grid of bundled LUT thumbnails plus a "Browse files" option
// to import a `.cube` file from Files / iCloud Drive. The selected LUT
// is surfaced to the caller via `onSelect`, along with the chosen
// intensity (0.0 … 1.0).
//
// Pure SwiftUI — uses `.sheet`, `Grid`/`LazyVGrid`, native `Slider`,
// and `.fileImporter` for document picking.

import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - LUTPickerSelection

/// Result payload emitted by `LUTPickerSheet` when the user confirms a selection.
struct LUTPickerSelection: Sendable, Equatable {

    /// Source URL for the selected LUT.
    ///
    /// • Bundled LUTs resolve to the app bundle (`Bundle.main.url(forResource:)`).
    /// • Custom LUTs resolve to a security-scoped file URL from the document picker.
    let url: URL

    /// Display name of the LUT (either the bundled preset name or the file's basename).
    let name: String

    /// Normalized intensity in the range `0.0 … 1.0`.
    let intensity: Double

    /// Whether this LUT was sourced from the app bundle.
    let isBundled: Bool
}

// MARK: - LUTPickerSheet

/// iOS 26 Liquid Glass sheet that lets the user pick a bundled LUT
/// or import a custom `.cube` file from Files.
@MainActor
struct LUTPickerSheet: View {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "LUTPickerSheet"
    )

    // MARK: - Bundled Presets

    /// Bundled LUT filenames (without extension) shown in the grid.
    ///
    /// Sourced from the C5-20 bundle (`LiquidEditor/Resources/LUTs`).
    private static let bundledLUTs: [BundledLUT] = [
        .init(filename: "Cinematic_Warm",     displayName: "Cinematic Warm",    symbol: "sun.max.fill"),
        .init(filename: "Cinematic_Cool",     displayName: "Cinematic Cool",    symbol: "moon.stars.fill"),
        .init(filename: "Vintage",            displayName: "Vintage",           symbol: "camera.vintage"),
        .init(filename: "Bleach_Bypass",      displayName: "Bleach Bypass",     symbol: "square.stack.3d.up"),
        .init(filename: "Day_For_Night",      displayName: "Day for Night",     symbol: "moon.fill"),
        .init(filename: "Punchy",             displayName: "Punchy",            symbol: "bolt.fill"),
        .init(filename: "Muted",              displayName: "Muted",             symbol: "circle.lefthalf.filled"),
        .init(filename: "BW_High_Contrast",   displayName: "B&W High Contrast", symbol: "circle.righthalf.filled"),
        .init(filename: "Sepia",              displayName: "Sepia",             symbol: "photo.fill"),
        .init(filename: "Teal_Orange",        displayName: "Teal & Orange",     symbol: "paintpalette.fill")
    ]

    // MARK: - Callback

    /// Invoked when the user confirms a LUT selection. The sheet is
    /// dismissed automatically after the callback fires.
    let onSelect: (LUTPickerSelection) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Currently-selected bundled LUT (if any).
    @State private var selectedBundledFilename: String?

    /// Currently-imported custom LUT (if any).
    @State private var customSelection: (url: URL, name: String)?

    /// Intensity slider value, 0 … 100 for clearer affordance.
    @State private var intensityPercent: Double = 100

    /// Whether the document picker is presented.
    @State private var isImporterPresented = false

    /// Last error surfaced to the user (file import failures).
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LiquidSpacing.xl) {
                    lutGrid
                    browseButton
                }
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, 120) // reserve room for sticky intensity controls
            }
            .safeAreaInset(edge: .bottom) {
                intensityControls
            }
            .navigationTitle("Choose LUT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applySelection() }
                        .disabled(!hasSelection)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: Self.cubeContentTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert(
                "Import Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - LUT Grid

    private var lutGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: LiquidSpacing.md)],
            spacing: LiquidSpacing.md
        ) {
            ForEach(Self.bundledLUTs) { lut in
                lutCell(lut)
            }
            if let custom = customSelection {
                customLUTCell(name: custom.name)
            }
        }
    }

    private func lutCell(_ lut: BundledLUT) -> some View {
        let isSelected = (selectedBundledFilename == lut.filename)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedBundledFilename = lut.filename
            customSelection = nil
        } label: {
            VStack(spacing: LiquidSpacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(height: 96)

                    Image(systemName: lut.symbol)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(.primary)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )

                Text(lut.displayName)
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(lut.displayName) LUT")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func customLUTCell(name: String) -> some View {
        VStack(spacing: LiquidSpacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 96)

                Image(systemName: "doc.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            )

            Text(name)
                .font(LiquidTypography.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityLabel("Imported LUT: \(name)")
        .accessibilityAddTraits(.isSelected)
    }

    // MARK: - Browse Files

    private var browseButton: some View {
        Button {
            isImporterPresented = true
        } label: {
            HStack(spacing: LiquidSpacing.sm) {
                Image(systemName: "folder.fill")
                Text("Browse files")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiquidSpacing.md)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Browse for custom LUT file")
    }

    // MARK: - Intensity Controls

    private var intensityControls: some View {
        VStack(spacing: LiquidSpacing.sm) {
            HStack {
                Text("Intensity")
                    .font(LiquidTypography.headline)
                Spacer()
                Text("\(Int(intensityPercent))%")
                    .font(LiquidTypography.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $intensityPercent, in: 0...100, step: 1)
                .tint(.accentColor)
                .accessibilityLabel("LUT intensity")
                .accessibilityValue("\(Int(intensityPercent)) percent")
        }
        .padding(LiquidSpacing.lg)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var hasSelection: Bool {
        selectedBundledFilename != nil || customSelection != nil
    }

    private static var cubeContentTypes: [UTType] {
        if let cubeType = UTType(filenameExtension: "cube") {
            return [cubeType, .plainText, .data]
        }
        return [.plainText, .data]
    }

    private func applySelection() {
        let normalizedIntensity = max(0, min(1, intensityPercent / 100))

        if let filename = selectedBundledFilename {
            guard let url = Bundle.main.url(forResource: filename, withExtension: "cube") else {
                errorMessage = "Bundled LUT \"\(filename)\" could not be located."
                Self.logger.error(
                    "Missing bundled LUT resource: \(filename, privacy: .public).cube"
                )
                return
            }
            let name = Self.bundledLUTs.first(where: { $0.filename == filename })?.displayName ?? filename
            onSelect(
                LUTPickerSelection(
                    url: url,
                    name: name,
                    intensity: normalizedIntensity,
                    isBundled: true
                )
            )
            dismiss()
            return
        }

        if let custom = customSelection {
            onSelect(
                LUTPickerSelection(
                    url: custom.url,
                    name: custom.name,
                    intensity: normalizedIntensity,
                    isBundled: false
                )
            )
            dismiss()
            return
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let name = url.deletingPathExtension().lastPathComponent
            selectedBundledFilename = nil
            customSelection = (url: url, name: name)
        case .failure(let error):
            Self.logger.error(
                "LUT import failed: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - BundledLUT

/// Static descriptor for a bundled LUT cell in the picker grid.
private struct BundledLUT: Identifiable, Sendable {
    let filename: String
    let displayName: String
    let symbol: String

    var id: String { filename }
}
