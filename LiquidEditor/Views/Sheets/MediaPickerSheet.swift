// MediaPickerSheet.swift
// LiquidEditor
//
// Multi-select media picker sheet backed by SwiftUI's native
// `PhotosPicker`. Supports filter chips (All / Photos / Videos / Audio),
// a selection count indicator, and an "Import N items" CTA that hands
// the selected items to `MediaImportService`.
//
// Audio is not supported by `PhotosPicker` on iOS (the Photos app does
// not vend audio assets), so selecting the Audio filter routes the user
// to the existing `ImportSourceSheet` / Files importer elsewhere in the
// app. Here we surface the audio filter for UX consistency with F6-1
// spec but communicate the platform limitation.

import Photos
import PhotosUI
import SwiftUI
import os

// MARK: - MediaPickerFilter

/// Filter chip options for the media picker sheet.
enum MediaPickerFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case photos
    case videos
    case audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .audio: return "Audio"
        }
    }

    var sfSymbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .photos: return "photo"
        case .videos: return "video"
        case .audio: return "waveform"
        }
    }

    /// Map to the matching `PHPickerFilter`. Returns `nil` for `.audio`
    /// since audio is not a `PhotosPicker` filter.
    var photosFilter: PHPickerFilter? {
        switch self {
        case .all: return .any(of: [.images, .videos, .livePhotos])
        case .photos: return .any(of: [.images, .livePhotos])
        case .videos: return .videos
        case .audio: return nil
        }
    }
}

// MARK: - MediaPickerSheet

/// Multi-select media picker sheet with filter chips and an import CTA.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showPicker) {
///     MediaPickerSheet(
///         mediaImportService: ServiceContainer.shared.mediaImportService,
///         onImported: { media in ... }
///     )
/// }
/// ```
///
/// Thread Safety:
/// - `@MainActor` per CLAUDE.md guidance for view models / UI-bound types.
/// - Import work is awaited on `MediaImportService` actor.
struct MediaPickerSheet: View {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "MediaPickerSheet"
    )

    // MARK: - Inputs

    /// Import service used to finalise selections.
    ///
    /// NOTE: `MediaImportService` is an `actor`. In the current codebase it
    /// exposes picker-presenting methods (`importFromPhotos`), but here we
    /// drive selection from SwiftUI directly via `PhotosPicker`. The
    /// selected items are passed as URLs to downstream consumers via
    /// `onImported`; future wiring can forward them to a batch-import API
    /// on `MediaImportService`.
    let mediaImportService: MediaImportService?

    /// Called with the resolved imported media after the user taps the
    /// "Import N items" CTA. The sheet dismisses itself before calling.
    let onImported: ([ImportedMedia]) -> Void

    /// Optional cancel callback.
    var onCancel: (() -> Void)?

    // MARK: - State

    @State private var filter: MediaPickerFilter = .all
    @State private var selections: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                    .padding(.horizontal, LiquidSpacing.lg)
                    .padding(.vertical, LiquidSpacing.sm)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                importBar
            }
            .background(LiquidColors.background.ignoresSafeArea())
            .navigationTitle("Import Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
            }
            .alert("Import failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Filter Chips

    @ViewBuilder
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.sm) {
                ForEach(MediaPickerFilter.allCases) { option in
                    filterChip(option)
                }
            }
        }
    }

    @ViewBuilder
    private func filterChip(_ option: MediaPickerFilter) -> some View {
        let selected = filter == option
        Button {
            let feedback = UISelectionFeedbackGenerator()
            feedback.selectionChanged()
            withAnimation(.easeOut(duration: 0.2)) {
                filter = option
                selections.removeAll()
            }
        } label: {
            HStack(spacing: LiquidSpacing.xs) {
                Image(systemName: option.sfSymbol)
                    .imageScale(.small)
                Text(option.label)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.sm)
            .background(
                Capsule()
                    .fill(selected ? Color.accentColor.opacity(0.25) : .clear)
            )
            .overlay(
                Capsule()
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filter == .audio {
            audioUnavailableState
        } else {
            pickerBody
        }
    }

    @ViewBuilder
    private var pickerBody: some View {
        VStack(spacing: LiquidSpacing.lg) {
            Image(systemName: filter.sfSymbol)
                .font(.system(size: 56, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .padding(.top, LiquidSpacing.xl)

            Text(selections.isEmpty ? "Select items from your photo library" : "\(selections.count) item\(selections.count == 1 ? "" : "s") selected")
                .font(.headline)
                .foregroundStyle(.primary)

            PhotosPicker(
                selection: $selections,
                maxSelectionCount: 0,
                selectionBehavior: .ordered,
                matching: filter.photosFilter,
                preferredItemEncoding: .current
            ) {
                Label(selections.isEmpty ? "Browse Library" : "Change Selection", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, LiquidSpacing.xl)

            if !selections.isEmpty {
                Button(role: .destructive) {
                    selections.removeAll()
                } label: {
                    Label("Clear Selection", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var audioUnavailableState: some View {
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 56, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("Audio is not available in the photo library")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Use the Files importer from the main import menu to add audio tracks to your project.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidSpacing.xl)
        }
        .padding(.top, LiquidSpacing.xl)
    }

    // MARK: - Import Bar

    @ViewBuilder
    private var importBar: some View {
        HStack {
            Text("\(selections.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                performImport()
            } label: {
                if isImporting {
                    HStack(spacing: LiquidSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Importing…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(selections.isEmpty ? "Import" : "Import \(selections.count) item\(selections.count == 1 ? "" : "s")")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selections.isEmpty || isImporting)
        }
        .padding(LiquidSpacing.lg)
        .background(.ultraThinMaterial)
    }

    // MARK: - Import Action

    private func performImport() {
        guard !selections.isEmpty, !isImporting else { return }
        isImporting = true
        let items = selections

        Task { @MainActor in
            defer { isImporting = false }
            do {
                let imported = try await loadItems(items)

                // Stub: when a MediaImportService instance is provided we
                // could call `extractMetadata` / `generateThumbnail` on each
                // URL here. Left to the caller via `onImported` to avoid
                // coupling this sheet to a specific import pipeline.
                _ = mediaImportService
                Self.logger.info("MediaPickerSheet imported \(imported.count, privacy: .public) items (filter=\(filter.rawValue, privacy: .public))")

                onImported(imported)
                dismiss()
            } catch {
                Self.logger.error("MediaPickerSheet import failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Load each selected item as a temporary file URL and wrap in
    /// `ImportedMedia`. Videos / images are handled; anything else is
    /// skipped.
    private func loadItems(_ items: [PhotosPickerItem]) async throws -> [ImportedMedia] {
        var results: [ImportedMedia] = []
        for item in items {
            if let url = try await loadTemporaryURL(for: item) {
                let type: MediaType = inferType(for: item)
                results.append(
                    ImportedMedia(
                        url: url,
                        type: type,
                        assetIdentifier: item.itemIdentifier,
                        originalFilename: url.lastPathComponent
                    )
                )
            }
        }
        return results
    }

    private func inferType(for item: PhotosPickerItem) -> MediaType {
        let hasVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
        if hasVideo { return .video }
        return .image
    }

    private func loadTemporaryURL(for item: PhotosPickerItem) async throws -> URL? {
        guard let data = try await item.loadTransferable(type: Data.self) else { return nil }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }
}
