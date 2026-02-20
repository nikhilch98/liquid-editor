// MediaBrowserView.swift
// LiquidEditor
//
// Media browser view displaying all imported media assets.
// Provides a Photos-app style square grid (3 columns),
// search, filter chips (All, Video, Photo, Audio, Favorites),
// sort options, and context menu actions.
//
// Matches Flutter MediaBrowserView layout:
// - Navigation bar with "Media" title and sort button
// - Inline search bar
// - Filter chips: All, Video, Photo, Audio, Favorites (heart icon)
// - 3-column square grid cells with thumbnail fill
// - Duration badge overlay (bottom-right) for videos
// - Favorite heart overlay (top-right)
// - No type badges, no filename, no file size in cells
//
// Pure SwiftUI with iOS 26 native styling. No Material Design.

import SwiftUI

// MARK: - MediaSortOption

/// Sort options for the media browser grid.
///
/// Provides 8 sort criteria matching the Flutter implementation:
/// date, name, duration, and file size -- each ascending/descending.
enum MediaSortOption: String, CaseIterable, Identifiable, Sendable {
    case dateNewest
    case dateOldest
    case nameAZ
    case nameZA
    case durationLongest
    case durationShortest
    case sizeLargest
    case sizeSmallest

    var id: String { rawValue }

    /// Human-readable label for display in the sort menu.
    var displayName: String {
        switch self {
        case .dateNewest: return "Date (Newest First)"
        case .dateOldest: return "Date (Oldest First)"
        case .nameAZ: return "Name (A-Z)"
        case .nameZA: return "Name (Z-A)"
        case .durationLongest: return "Duration (Longest)"
        case .durationShortest: return "Duration (Shortest)"
        case .sizeLargest: return "Size (Largest)"
        case .sizeSmallest: return "Size (Smallest)"
        }
    }
}

// MARK: - AsyncThumbnailView

/// Loads a thumbnail image asynchronously to avoid blocking the main thread.
///
/// Uses a `.task` modifier to load the image on a background thread, displaying
/// a placeholder while loading. The `id` modifier ensures the task restarts
/// when the thumbnail path changes.
private struct AsyncThumbnailView<Placeholder: View>: View {

    let thumbnailPath: String?
    let mediaType: MediaType
    let placeholderBuilder: (MediaType) -> Placeholder

    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let uiImage = loadedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderBuilder(mediaType)
            }
        }
        .task(id: thumbnailPath) {
            loadedImage = nil
            guard let thumbnailPath, !thumbnailPath.isEmpty else { return }
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
            guard let url = documentsURL?.appendingPathComponent(thumbnailPath) else { return }
            let path = url.path
            let image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
            if !Task.isCancelled {
                loadedImage = image
            }
        }
    }
}

// MARK: - MediaBrowserView

/// Grid view of all imported media assets in a Photos-app square grid.
///
/// Provides filter chips for media type (All, Video, Photo, Audio, Favorites),
/// a 3-column square grid of thumbnail cells, and context menu actions
/// for Info, Favorite, and Delete.
struct MediaBrowserView: View {

    @Bindable var viewModel: ProjectLibraryViewModel

    /// Whether favorites-only filter is active.
    @State private var favoritesOnly: Bool = false

    /// Search query text for inline search.
    @State private var searchQuery: String = ""

    /// Current sort option for media assets.
    @State private var sortOption: MediaSortOption = .dateNewest

    var body: some View {
        VStack(spacing: 0) {
            // Inline search bar
            inlineSearchBar

            // Filter chips
            filterChips

            // Content
            mediaContent
        }
        .navigationTitle("Media")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mediaSortMenu
            }
        }
        .sheet(
            item: $viewModel.selectedMediaAssetForDetail
        ) { asset in
            MediaDetailSheet(
                asset: asset,
                onToggleFavorite: { id in
                    Task { await viewModel.toggleMediaFavorite(id: id) }
                }
            )
        }
    }

    // MARK: - Sort Menu

    /// Sort menu button using `arrow.up.arrow.down` SF Symbol.
    private var mediaSortMenu: some View {
        Menu {
            ForEach(MediaSortOption.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sortOption = option
                    }
                } label: {
                    HStack {
                        Text(option.displayName)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    // MARK: - Inline Search Bar

    private var inlineSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search media...", text: $searchQuery)
                .textFieldStyle(.plain)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.sm)
        .background(LiquidColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2, style: .continuous))
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.vertical, LiquidSpacing.sm)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.sm) {
                filterChip(label: "All", isSelected: viewModel.mediaFilter == .all) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.mediaFilter = .all
                    }
                }

                filterChip(label: "Video", isSelected: viewModel.mediaFilter == .video) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.mediaFilter = .video
                    }
                }

                filterChip(label: "Photo", isSelected: viewModel.mediaFilter == .image) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.mediaFilter = .image
                    }
                }

                filterChip(label: "Audio", isSelected: viewModel.mediaFilter == .audio) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.mediaFilter = .audio
                    }
                }

                // Favorites filter chip with heart icon
                filterChip(
                    label: "Favorites",
                    systemImage: "heart.fill",
                    isSelected: favoritesOnly
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        favoritesOnly.toggle()
                    }
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.xs)
        }
    }

    private func filterChip(
        label: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: LiquidSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                }
                Text(label)
                    .font(isSelected ? LiquidTypography.footnoteSemibold : LiquidTypography.footnote)
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.xs + 2)
            .background(
                isSelected
                    ? AnyShapeStyle(.tint)
                    : AnyShapeStyle(LiquidColors.fillTertiary)
            )
            .foregroundStyle(isSelected ? .white : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.accentColor : Color(uiColor: .separator),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Media Content

    /// Filtered and sorted assets applying ViewModel filter, local favorites/search, and sort.
    private var displayedAssets: [MediaAsset] {
        var result = viewModel.filteredMediaAssets

        // Apply favorites filter
        if favoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        // Apply local search
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter {
                $0.originalFilename.lowercased().contains(query)
            }
        }

        // Apply sort
        result = sortedAssets(result)

        return result
    }

    /// Sort assets according to the current `sortOption`.
    private func sortedAssets(_ assets: [MediaAsset]) -> [MediaAsset] {
        switch sortOption {
        case .dateNewest:
            return assets.sorted { $0.importedAt > $1.importedAt }
        case .dateOldest:
            return assets.sorted { $0.importedAt < $1.importedAt }
        case .nameAZ:
            return assets.sorted {
                $0.originalFilename.localizedCaseInsensitiveCompare($1.originalFilename) == .orderedAscending
            }
        case .nameZA:
            return assets.sorted {
                $0.originalFilename.localizedCaseInsensitiveCompare($1.originalFilename) == .orderedDescending
            }
        case .durationLongest:
            return assets.sorted { $0.durationMicroseconds > $1.durationMicroseconds }
        case .durationShortest:
            return assets.sorted { $0.durationMicroseconds < $1.durationMicroseconds }
        case .sizeLargest:
            return assets.sorted { $0.fileSize > $1.fileSize }
        case .sizeSmallest:
            return assets.sorted { $0.fileSize < $1.fileSize }
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.isLoading && viewModel.mediaAssets.isEmpty {
            loadingView
        } else if displayedAssets.isEmpty {
            emptyMediaView
        } else {
            mediaGrid
        }
    }

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                ],
                spacing: 2
            ) {
                ForEach(displayedAssets, id: \.id) { asset in
                    mediaThumbnailCell(for: asset)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, LiquidSpacing.sm)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Thumbnail Cell

    private func mediaThumbnailCell(for asset: MediaAsset) -> some View {
        Button {
            viewModel.selectedMediaAssetForDetail = asset
        } label: {
            ZStack {
                // Thumbnail or placeholder
                assetThumbnail(for: asset)

                // Duration badge (bottom-right) for videos
                if (asset.type == .video || asset.type == .audio),
                   asset.durationMicroseconds > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(asset.durationMicroseconds))
                                .font(LiquidTypography.caption2Semibold)
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Color.black.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                                )
                                .padding(4)
                        }
                    }
                }

                // Favorite heart (top-right)
                if asset.isFavorite {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "heart.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .padding(4)
                        }
                        Spacer()
                    }
                }

                // Audio icon for audio files
                if asset.type == .audio {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "waveform")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .padding(4)
                        }
                    }
                }
            }
            .clipped()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(asset.originalFilename), \(asset.type == .video ? "video" : asset.type == .audio ? "audio" : "photo")\(asset.isFavorite ? ", favorited" : "")")
        .contextMenu {
            assetContextMenu(for: asset)
        }
    }

    private func assetThumbnail(for asset: MediaAsset) -> some View {
        AsyncThumbnailView(
            thumbnailPath: asset.thumbnailPath,
            mediaType: asset.type,
            placeholderBuilder: { type in
                assetPlaceholder(for: type)
            }
        )
    }

    private func assetPlaceholder(for type: MediaType) -> some View {
        Rectangle()
            .fill(Color(uiColor: .tertiarySystemFill))
            .overlay {
                Image(systemName: placeholderIcon(for: type))
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }
    }

    private func placeholderIcon(for type: MediaType) -> String {
        switch type {
        case .video: return "play.rectangle"
        case .image: return "photo"
        case .audio: return "waveform"
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func assetContextMenu(for asset: MediaAsset) -> some View {
        Button {
            viewModel.selectedMediaAssetForDetail = asset
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        Button {
            Task { await viewModel.toggleMediaFavorite(id: asset.id) }
        } label: {
            Label(
                asset.isFavorite ? "Unfavorite" : "Favorite",
                systemImage: asset.isFavorite ? "heart.slash" : "heart"
            )
        }

        Divider()

        Button(role: .destructive) {
            Task { await viewModel.deleteMediaAsset(id: asset.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty / Loading States

    private var emptyMediaView: some View {
        ContentUnavailableView {
            Label("No Media", systemImage: "photo.on.rectangle")
        } description: {
            Text("Import video, image, or audio files to get started.")
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading media...")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, LiquidSpacing.sm)
            Spacer()
        }
    }

    // MARK: - Formatting Helpers

    private func formatDuration(_ microseconds: TimeMicros) -> String {
        let totalSeconds = Int(microseconds / 1_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
