// StickerPickerSheet.swift
// LiquidEditor
//
// Sticker browser sheet view.
// Pure iOS 26 SwiftUI with native styling.
// Layout: NavBar (X close) -> Search bar -> Categories -> Grid

import SwiftUI

struct StickerPickerSheet: View {

    @State private var selectedCategory: StickerCategory
    @State private var searchText = ""
    @State private var favoriteIds: Set<String> = []

    @Environment(\.dismiss) private var dismiss

    let categories: [StickerCategory]
    let stickers: [StickerAsset]
    let onSelect: (StickerAsset) -> Void

    init(
        categories: [StickerCategory] = StickerCategory.builtInCategories,
        stickers: [StickerAsset] = [],
        onSelect: @escaping (StickerAsset) -> Void
    ) {
        self.categories = categories
        self.stickers = stickers
        self.onSelect = onSelect
        _selectedCategory = State(
            initialValue: categories.first ?? StickerCategory.builtInCategories[0]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header row
            headerRow
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            // Search bar (native searchable style)
            searchBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Category tabs (hidden while searching)
            if searchText.isEmpty {
                categoryTabs
            }

            // Sticker grid
            ScrollView {
                if selectedCategory.id == "favorites" && !filteredFavorites.isEmpty {
                    stickerGrid(stickers: filteredFavorites)
                } else if selectedCategory.id != "favorites" {
                    stickerGrid(stickers: filteredStickers)
                } else {
                    emptyFavoritesView
                }

                Spacer(minLength: 16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Stickers")
                .font(LiquidTypography.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: LiquidSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(LiquidTypography.callout)

            TextField("Search stickers", text: $searchText)
                .textFieldStyle(.plain)
                .font(LiquidTypography.callout)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(LiquidTypography.callout)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.sm)
        .background(LiquidColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium - 2, style: .continuous))
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.xs) {
                ForEach(categories, id: \.id) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        VStack(spacing: LiquidSpacing.xxs) {
                            Image(systemName: category.iconName)
                                .font(LiquidTypography.body)
                            Text(category.name)
                                .font(LiquidTypography.caption2)
                        }
                        .padding(.horizontal, LiquidSpacing.md)
                        .padding(.vertical, LiquidSpacing.xs + 2)
                        .background(
                            selectedCategory.id == category.id
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.name) category")
                    .accessibilityAddTraits(selectedCategory.id == category.id ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, LiquidSpacing.xs + 2)
        }
    }

    // MARK: - Sticker Grid

    private func stickerGrid(stickers: [StickerAsset]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 72), spacing: LiquidSpacing.md)]

        return LazyVGrid(columns: columns, spacing: LiquidSpacing.md) {
            ForEach(stickers, id: \.id) { sticker in
                stickerCell(sticker)
            }
        }
        .padding()
    }

    private func stickerCell(_ sticker: StickerAsset) -> some View {
        Button {
            onSelect(sticker)
            dismiss()
        } label: {
            VStack(spacing: LiquidSpacing.xs) {
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium - 2)
                        .fill(LiquidColors.surface)
                        .frame(width: 64, height: 64)

                    // Placeholder thumbnail (photo icon for all, static or animated)
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    // Animated badge: play.circle.fill overlay in bottom-right
                    if sticker.isAnimated {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(4)
                    }

                    // Favorite indicator: heart.fill in top-right (orange)
                    if favoriteIds.contains(sticker.id) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.orange)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(4)
                    }
                }
                .frame(width: 64, height: 64)

                Text(sticker.name)
                    .font(LiquidTypography.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                toggleFavorite(sticker.id)
            } label: {
                Label(
                    favoriteIds.contains(sticker.id) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: favoriteIds.contains(sticker.id) ? "heart.slash" : "heart"
                )
            }

            Button {
                onSelect(sticker)
                dismiss()
            } label: {
                Label("Add to Timeline", systemImage: "plus.rectangle.on.rectangle")
            }
        }
    }

    // MARK: - Empty Favorites

    private var emptyFavoritesView: some View {
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "heart")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Favorites Yet")
                .font(LiquidTypography.headline)
                .foregroundStyle(.secondary)
            Text("Long-press a sticker to add it to favorites")
                .font(LiquidTypography.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Filtering

    private var filteredStickers: [StickerAsset] {
        let categoryFiltered = stickers.filter { $0.categoryId == selectedCategory.id }
        if searchText.isEmpty { return categoryFiltered }
        let query = searchText.lowercased()
        return categoryFiltered.filter {
            $0.name.lowercased().contains(query) ||
            $0.keywords.contains { $0.lowercased().contains(query) }
        }
    }

    private var filteredFavorites: [StickerAsset] {
        let favorites = stickers.filter { favoriteIds.contains($0.id) }
        if searchText.isEmpty { return favorites }
        let query = searchText.lowercased()
        return favorites.filter {
            $0.name.lowercased().contains(query) ||
            $0.keywords.contains { $0.lowercased().contains(query) }
        }
    }

    // MARK: - Favorites

    private func toggleFavorite(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if favoriteIds.contains(id) {
            favoriteIds.remove(id)
        } else {
            favoriteIds.insert(id)
        }
    }
}

// MARK: - StickerInlinePanel

/// Compact inline sticker picker for embedding directly in the editor layout.
///
/// Shows a 5-column sticker grid with category chip tabs (including a synthetic
/// "All" tab at position 0). No search bar -- space is limited.
/// Height: approximately 200pt.
///
/// Unlike the modal `StickerPickerSheet`, this stays visible so users can
/// add multiple stickers without reopening the picker.
struct StickerInlinePanel: View {

    // MARK: - Properties

    let categories: [StickerCategory]
    let stickers: [StickerAsset]
    let onStickerSelected: (StickerAsset) -> Void

    // MARK: - State

    @State private var selectedCategoryIndex: Int = 0

    // MARK: - Init

    init(
        categories: [StickerCategory] = StickerCategory.builtInCategories,
        stickers: [StickerAsset] = [],
        onStickerSelected: @escaping (StickerAsset) -> Void
    ) {
        self.categories = categories
        self.stickers = stickers
        self.onStickerSelected = onStickerSelected
    }

    // MARK: - Computed: visible stickers

    private var visibleStickers: [StickerAsset] {
        if selectedCategoryIndex == 0 {
            // "All" tab: show every sticker
            return stickers
        }
        // Offset by 1 because index 0 is the synthetic "All" tab
        let category = categories[selectedCategoryIndex - 1]
        return stickers.filter { $0.categoryId == category.id }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Category chip row
            categoryChips
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.top, LiquidSpacing.sm)
                .padding(.bottom, LiquidSpacing.xs)

            // 5-column sticker grid
            if visibleStickers.isEmpty {
                emptyState
            } else {
                stickerGrid
            }
        }
        .frame(height: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.xs) {
                // Synthetic "All" tab at index 0
                categoryChip(label: "All", index: 0)

                ForEach(categories.indices, id: \.self) { idx in
                    categoryChip(label: categories[idx].name, index: idx + 1)
                }
            }
        }
    }

    private func categoryChip(label: String, index: Int) -> some View {
        let isSelected = selectedCategoryIndex == index
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedCategoryIndex = index
        } label: {
            Text(label)
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : LiquidColors.textSecondary)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.15)
                        : LiquidColors.fillTertiary
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) category")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Sticker Grid (5 columns)

    private var stickerGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: LiquidSpacing.xs), count: 5)

        return ScrollView {
            LazyVGrid(columns: columns, spacing: LiquidSpacing.xs) {
                ForEach(visibleStickers, id: \.id) { asset in
                    inlineTile(asset)
                }
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.xs)
        }
    }

    private func inlineTile(_ asset: StickerAsset) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onStickerSelected(asset)
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .fill(LiquidColors.fillTertiary)

                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)

                    // Animated badge for inline tiles
                    if asset.isAnimated {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(2)
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                Text(asset.name)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .foregroundStyle(LiquidColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.name)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("No stickers in this category")
            .font(LiquidTypography.caption)
            .foregroundStyle(LiquidColors.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    StickerPickerSheet { _ in }
}

#Preview("Inline Panel") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            StickerInlinePanel { _ in }
                .padding()
        }
    }
}
