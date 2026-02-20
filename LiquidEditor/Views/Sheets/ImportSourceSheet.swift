// ImportSourceSheet.swift
// LiquidEditor
//
// Selection sheet for choosing an import source (camera roll, files, camera, URL).
// Uses .confirmationDialog for native iOS action sheet behavior.

import SwiftUI

// MARK: - ImportSourceOption

/// Available import sources.
///
/// Aligns with `ImportSource` in Models/Media/MediaAsset.swift.
enum ImportSourceOption: String, CaseIterable, Sendable, Identifiable {
    case photoLibrary
    case files
    case camera
    case url

    var id: String { rawValue }

    /// Human-readable label.
    var label: String {
        switch self {
        case .photoLibrary: return "Photo Library"
        case .files: return "Files"
        case .camera: return "Camera"
        case .url: return "URL"
        }
    }

    /// SF Symbol name for the source icon.
    var sfSymbol: String {
        switch self {
        case .photoLibrary: return "photo.on.rectangle"
        case .files: return "folder"
        case .camera: return "camera"
        case .url: return "link"
        }
    }

    /// Convert to the `ImportSource` model type.
    var asImportSource: ImportSource {
        switch self {
        case .photoLibrary: return .photoLibrary
        case .files: return .files
        case .camera: return .camera
        case .url: return .url
        }
    }
}

// MARK: - ImportSourceSheet

/// Sheet presenting import source options using native iOS action sheet style.
///
/// Presents a list of import sources (Photo Library, Files, Camera, URL)
/// with SF Symbol icons. Each option triggers the `onSourceSelected` callback.
///
/// Can be used either as a standalone sheet or via the
/// `importSourceConfirmationDialog` modifier.
struct ImportSourceSheet: View {

    /// Called when the user selects an import source.
    let onSourceSelected: (ImportSourceOption) -> Void

    /// Called when the user dismisses the sheet.
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ImportSourceOption.allCases) { source in
                        Button {
                            let selection = UISelectionFeedbackGenerator()
                            selection.selectionChanged()
                            dismiss()
                            onSourceSelected(source)
                        } label: {
                            Label(source.label, systemImage: source.sfSymbol)
                        }
                        .accessibilityHint("Imports media from \(source.label)")
                    }
                } header: {
                    Text("Choose a source to import from")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Import Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss?()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - View Extension for Confirmation Dialog

extension View {

    /// Present an import source selection as a confirmation dialog (action sheet).
    ///
    /// This is the SwiftUI equivalent of the Flutter `showImportSourceSheet()`.
    ///
    /// Usage:
    /// ```swift
    /// .importSourceConfirmationDialog(
    ///     isPresented: $showImportPicker,
    ///     onSourceSelected: { source in
    ///         viewModel.startImport(from: source)
    ///     }
    /// )
    /// ```
    func importSourceConfirmationDialog(
        isPresented: Binding<Bool>,
        onSourceSelected: @escaping (ImportSourceOption) -> Void
    ) -> some View {
        confirmationDialog(
            "Import Media",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            ForEach(ImportSourceOption.allCases) { source in
                Button {
                    onSourceSelected(source)
                } label: {
                    Label(source.label, systemImage: source.sfSymbol)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a source to import from")
        }
    }
}

// MARK: - Preview

#Preview("Sheet Style") {
    ImportSourceSheet(
        onSourceSelected: { _ in }
    )
}

#Preview("Confirmation Dialog") {
    struct PreviewWrapper: View {
        @State private var showDialog = true

        var body: some View {
            Button("Show Import Source") {
                showDialog = true
            }
            .importSourceConfirmationDialog(
                isPresented: $showDialog,
                onSourceSelected: { _ in }
            )
        }
    }

    return PreviewWrapper()
}
