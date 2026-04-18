// SFXBrowserSheet.swift
// LiquidEditor
//
// TD8-3: SFX browser sheet. Categorised library of bundled sound effects
// with search, preview playback (visual stub until real assets are wired),
// and an "Add to timeline" action on the selected card.
//
// Pure iOS 26 SwiftUI. Stub data lives in this file; real bundle integration
// and AVAudioPlayer preview are follow-up work.

import SwiftUI

// MARK: - SFXBrowserSheet

/// Full-sheet browser showing categorised bundled sound effects.
///
/// Layout:
/// - Header row with title, Reset / Close controls.
/// - Search field.
/// - Horizontal category chip strip.
/// - LazyVGrid of SFX cards (icon + name + duration).
/// - Tapping a card selects + toggles its preview highlight.
/// - "Add to Timeline" button in the footer commits the selection.
@MainActor
struct SFXBrowserSheet: View {

    // MARK: Inputs

    /// Called when the user taps "Add to Timeline" with the current selection.
    let onAdd: (SoundEffectAsset) -> Void

    // MARK: State

    @State private var searchQuery: String = ""
    @State private var selectedCategory: BrowserCategory = .all
    @State private var selectedAssetID: String?
    /// Card currently showing the "previewing" highlight.
    @State private var previewingAssetID: String?

    @Environment(\.dismiss) private var dismiss

    // MARK: Static stub library

    private static let library: [SoundEffectAsset] = buildStubLibrary()

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, LiquidSpacing.lg)
                    .padding(.top, LiquidSpacing.sm)

                categoryStrip
                    .padding(.top, LiquidSpacing.sm)

                Divider()
                    .padding(.top, LiquidSpacing.sm)

                if filteredAssets.isEmpty {
                    emptyState
                } else {
                    sfxGrid
                }

                footer
            }
            .navigationTitle("Sound Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Subviews

    private var searchBar: some View {
        HStack(spacing: LiquidSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search sound effects", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(LiquidTypography.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.sm)
        .background(LiquidColors.fillTertiary, in: RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.xs) {
                ForEach(BrowserCategory.allCases) { category in
                    categoryChip(for: category)
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
        }
    }

    private func categoryChip(for category: BrowserCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: LiquidSpacing.xs) {
                Image(systemName: category.symbolName)
                    .font(.caption)
                Text(category.displayName)
                    .font(LiquidTypography.captionMedium)
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.xs + 2)
            .foregroundStyle(isSelected ? Color.white : .primary)
            .background(
                isSelected ? Color.accentColor : LiquidColors.fillTertiary,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var sfxGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140), spacing: LiquidSpacing.md)
                ],
                spacing: LiquidSpacing.md
            ) {
                ForEach(filteredAssets, id: \.id) { asset in
                    sfxCard(for: asset)
                }
            }
            .padding(LiquidSpacing.lg)
        }
    }

    private func sfxCard(for asset: SoundEffectAsset) -> some View {
        let isSelected = asset.id == selectedAssetID
        let isPreviewing = asset.id == previewingAssetID

        return Button {
            handleCardTap(asset)
        } label: {
            VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous)
                        .fill(LiquidColors.fillTertiary)
                        .aspectRatio(1.4, contentMode: .fit)

                    Image(systemName: asset.category.sfSymbolName)
                        .font(.title2)
                        .foregroundStyle(isPreviewing ? Color.accentColor : .secondary)
                        .symbolEffect(.pulse, isActive: isPreviewing)
                }

                Text(asset.name)
                    .font(LiquidTypography.subheadlineMedium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: LiquidSpacing.xs) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(formatDuration(asset.durationMicros))
                        .font(LiquidTypography.caption2)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
            .padding(LiquidSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : LiquidColors.surface.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : LiquidColors.glassBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(asset.name), \(formatDuration(asset.durationMicros))")
        .accessibilityHint(isSelected ? "Selected. Tap again to preview." : "Tap to select")
    }

    private var emptyState: some View {
        VStack(spacing: LiquidSpacing.sm) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No sound effects found")
                .font(LiquidTypography.headline)
                .foregroundStyle(.secondary)
            if !searchQuery.isEmpty {
                Text("Try a different search")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                commitAdd()
            } label: {
                HStack(spacing: LiquidSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add to Timeline")
                }
                .font(LiquidTypography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiquidSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedAssetID == nil)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
            .accessibilityHint("Adds the selected sound effect to the timeline")
        }
    }

    // MARK: Filtering

    private var filteredAssets: [SoundEffectAsset] {
        Self.library.filter { asset in
            let categoryMatch: Bool
            switch selectedCategory {
            case .all:
                categoryMatch = true
            case .category(let sfxCategory):
                categoryMatch = asset.category == sfxCategory
            }
            guard categoryMatch else { return false }
            return asset.matchesSearch(searchQuery)
        }
    }

    // MARK: Actions

    private func handleCardTap(_ asset: SoundEffectAsset) {
        if selectedAssetID == asset.id {
            // Second tap: toggle preview highlight. Real AVAudioPlayer
            // playback is deferred until real bundle assets are wired.
            // TODO: Wire to bundle asset via AVAudioPlayer for audible preview.
            previewingAssetID = (previewingAssetID == asset.id) ? nil : asset.id
        } else {
            selectedAssetID = asset.id
            previewingAssetID = nil
        }
    }

    private func commitAdd() {
        guard let id = selectedAssetID,
              let asset = Self.library.first(where: { $0.id == id }) else { return }
        onAdd(asset)
        dismiss()
    }

    private func formatDuration(_ micros: TimeMicros) -> String {
        let seconds = Double(micros) / 1_000_000.0
        if seconds < 1.0 {
            return String(format: "%.2fs", seconds)
        }
        return String(format: "%.1fs", seconds)
    }
}

// MARK: - BrowserCategory

private enum BrowserCategory: Hashable, Identifiable, CaseIterable {
    case all
    case category(SFXCategory)

    static var allCases: [BrowserCategory] {
        [.all] + SFXCategory.allCases.map { .category($0) }
    }

    var id: String {
        switch self {
        case .all: "all"
        case .category(let c): c.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .all: "All"
        case .category(let c): c.displayName
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.grid.2x2"
        case .category(let c): c.sfSymbolName
        }
    }
}

// MARK: - Stub library builder

/// Builds the hardcoded stub library used until real bundle assets are wired.
/// Covers the spec categories (Whoosh / Impact / UI / Foley / Ambience / Glitch)
/// by mapping them onto the existing `SFXCategory` cases.
private func buildStubLibrary() -> [SoundEffectAsset] {
    func asset(
        _ id: String,
        _ name: String,
        _ category: SFXCategory,
        seconds: Double,
        tags: [String] = []
    ) -> SoundEffectAsset {
        SoundEffectAsset(
            id: id,
            name: name,
            category: category,
            durationMicros: TimeMicros(seconds * 1_000_000),
            assetPath: "",
            tags: tags
        )
    }

    var lib: [SoundEffectAsset] = []

    // Whoosh -> transitions
    lib.append(asset("whoosh_cinematic", "Cinematic Whoosh", .transitions, seconds: 1.2, tags: ["whoosh", "sweep"]))
    lib.append(asset("whoosh_swipe", "Swipe Whoosh", .transitions, seconds: 0.6, tags: ["whoosh", "swipe"]))
    lib.append(asset("whoosh_transition", "Transition Rush", .transitions, seconds: 1.5, tags: ["whoosh", "transition"]))
    lib.append(asset("whoosh_air", "Air Whoosh", .transitions, seconds: 0.8, tags: ["whoosh", "air"]))
    lib.append(asset("whoosh_heavy", "Heavy Whoosh", .transitions, seconds: 1.3, tags: ["whoosh", "heavy"]))

    // Impact -> impacts
    lib.append(asset("impact_cinematic", "Cinematic Boom", .impacts, seconds: 2.4, tags: ["impact", "boom"]))
    lib.append(asset("impact_thud", "Heavy Thud", .impacts, seconds: 0.9, tags: ["impact", "thud"]))
    lib.append(asset("impact_hit", "Sharp Hit", .impacts, seconds: 0.3, tags: ["impact", "hit"]))
    lib.append(asset("impact_explosion", "Explosion", .impacts, seconds: 1.8, tags: ["impact", "explosion"]))
    lib.append(asset("impact_slam", "Door Slam", .impacts, seconds: 0.7, tags: ["impact", "slam"]))
    lib.append(asset("impact_punch", "Punch", .impacts, seconds: 0.5, tags: ["impact", "punch"]))

    // UI -> ui
    lib.append(asset("ui_click1", "UI Click 1", .ui, seconds: 0.12, tags: ["ui", "click"]))
    lib.append(asset("ui_click2", "UI Click 2", .ui, seconds: 0.15, tags: ["ui", "click"]))
    lib.append(asset("ui_pop", "UI Pop", .ui, seconds: 0.2, tags: ["ui", "pop"]))
    lib.append(asset("ui_tap", "UI Tap", .ui, seconds: 0.1, tags: ["ui", "tap"]))
    lib.append(asset("ui_notify", "UI Notification", .ui, seconds: 0.6, tags: ["ui", "notification"]))
    // Glitch -> mapped under UI (closest existing case)
    lib.append(asset("glitch_digital", "Digital Glitch", .ui, seconds: 0.8, tags: ["glitch", "digital"]))
    lib.append(asset("glitch_static", "Static Burst", .ui, seconds: 0.5, tags: ["glitch", "static"]))
    lib.append(asset("glitch_artifact", "Glitch Artifact", .ui, seconds: 0.4, tags: ["glitch"]))

    // Foley -> foley
    lib.append(asset("foley_footstep", "Footstep", .foley, seconds: 0.3, tags: ["foley", "footstep"]))
    lib.append(asset("foley_cloth", "Cloth Movement", .foley, seconds: 0.5, tags: ["foley", "cloth"]))
    lib.append(asset("foley_paper", "Paper Rustle", .foley, seconds: 0.9, tags: ["foley", "paper"]))
    lib.append(asset("foley_keys", "Keys Jingle", .foley, seconds: 1.1, tags: ["foley", "keys"]))
    lib.append(asset("foley_typewriter", "Typewriter", .foley, seconds: 1.4, tags: ["foley", "typewriter"]))

    // Ambience -> ambience
    lib.append(asset("ambience_room", "Room Tone", .ambience, seconds: 8.0, tags: ["ambience", "room"]))
    lib.append(asset("ambience_city", "City Ambience", .ambience, seconds: 12.0, tags: ["ambience", "city"]))
    lib.append(asset("ambience_forest", "Forest", .ambience, seconds: 10.0, tags: ["ambience", "forest"]))
    lib.append(asset("ambience_rain", "Light Rain", .ambience, seconds: 15.0, tags: ["ambience", "rain"]))
    lib.append(asset("ambience_wind", "Wind", .ambience, seconds: 9.0, tags: ["ambience", "wind"]))

    return lib
}

// MARK: - Preview

#Preview("SFX Browser") {
    SFXBrowserSheet { _ in }
}
