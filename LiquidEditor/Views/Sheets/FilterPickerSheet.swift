// FilterPickerSheet.swift
// LiquidEditor
//
// TD8-9: Filter picker sheet — live-preview thumbnail grid with category
// chips and a global intensity slider.
//
// Per docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §8.9:
// - 3-column LazyVGrid of filter cards (80×80 gradient thumbnails).
// - Category chips: All / Cinematic / Vintage / B&W / Vibrant / Mood.
// - Selected card gets an amber border.
// - Bottom sticky region: intensity slider (0-100%) + Apply CTA.
//
// Pure SwiftUI (iOS 26 Liquid Glass). The CIFilter chain reference is
// stored as an opaque `String` identifier on the model so the `Filter`
// struct remains `Sendable` — the actual CIFilter graph is resolved
// downstream by the effect pipeline when `Apply` fires.

import SwiftUI

// MARK: - Filter Model

/// Lightweight, `Sendable` descriptor for a single tone/colour preset.
///
/// The filter's CoreImage chain is referenced by identifier only
/// (`ciFilterChain`) so we do not capture a non-Sendable `CIFilter`
/// instance on the model. Downstream consumers look up the chain
/// by id when applying the filter.
struct Filter: Identifiable, Hashable, Sendable {

    /// Stable id (matches `ciFilterChain`).
    let id: String

    /// Display name shown under the thumbnail.
    let name: String

    /// Category shown in the top chip row.
    let category: FilterCategory

    /// Identifier of the bundled CIFilter chain (e.g. "cinematic.warm").
    /// Resolution to an actual `CIFilter` graph happens in the pipeline.
    let ciFilterChain: String

    /// Two-stop gradient used for the card thumbnail placeholder.
    let gradientStart: Color
    let gradientEnd: Color

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Filter, rhs: Filter) -> Bool { lhs.id == rhs.id }
}

// MARK: - Filter Category

/// Top-row chip categories.
enum FilterCategory: String, CaseIterable, Sendable, Identifiable {
    case all       = "All"
    case cinematic = "Cinematic"
    case vintage   = "Vintage"
    case blackWhite = "B&W"
    case vibrant   = "Vibrant"
    case mood      = "Mood"

    var id: String { rawValue }
}

// MARK: - FilterPickerSelection

/// Payload emitted on Apply.
struct FilterPickerSelection: Sendable, Equatable {
    let filter: Filter
    /// Normalized intensity `0.0 … 1.0`.
    let intensity: Double
}

// MARK: - FilterPickerSheet

/// TD8-9 — 3-column filter grid sheet with category chips + intensity.
@MainActor
struct FilterPickerSheet: View {

    // MARK: - Inputs

    /// Invoked with the final selection when the user taps Apply.
    let onApply: (FilterPickerSelection) -> Void

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var selectedCategory: FilterCategory = .all
    @State private var selectedFilterID: String?
    @State private var intensityPercent: Double = 100

    // MARK: - Catalog

    /// Stub catalog — a small set of presets per category so the grid
    /// renders realistically. Real catalog is injected later.
    private static let catalog: [Filter] = [
        // Cinematic
        Filter(id: "cin.warm",   name: "Cinematic Warm", category: .cinematic,
               ciFilterChain: "cinematic.warm",
               gradientStart: Color(red: 0.98, green: 0.62, blue: 0.30),
               gradientEnd:   Color(red: 0.45, green: 0.20, blue: 0.10)),
        Filter(id: "cin.cool",   name: "Cinematic Cool", category: .cinematic,
               ciFilterChain: "cinematic.cool",
               gradientStart: Color(red: 0.35, green: 0.55, blue: 0.90),
               gradientEnd:   Color(red: 0.10, green: 0.15, blue: 0.30)),
        Filter(id: "cin.teal",   name: "Teal & Orange", category: .cinematic,
               ciFilterChain: "cinematic.teal_orange",
               gradientStart: Color(red: 0.20, green: 0.70, blue: 0.70),
               gradientEnd:   Color(red: 0.95, green: 0.55, blue: 0.20)),

        // Vintage
        Filter(id: "vin.kodak",  name: "Kodak 200",     category: .vintage,
               ciFilterChain: "vintage.kodak200",
               gradientStart: Color(red: 0.90, green: 0.75, blue: 0.40),
               gradientEnd:   Color(red: 0.55, green: 0.35, blue: 0.15)),
        Filter(id: "vin.faded",  name: "Faded Film",    category: .vintage,
               ciFilterChain: "vintage.faded",
               gradientStart: Color(red: 0.78, green: 0.72, blue: 0.62),
               gradientEnd:   Color(red: 0.40, green: 0.38, blue: 0.30)),
        Filter(id: "vin.sepia",  name: "Sepia",         category: .vintage,
               ciFilterChain: "vintage.sepia",
               gradientStart: Color(red: 0.80, green: 0.60, blue: 0.35),
               gradientEnd:   Color(red: 0.35, green: 0.22, blue: 0.10)),

        // B&W
        Filter(id: "bw.classic", name: "Classic Mono",  category: .blackWhite,
               ciFilterChain: "bw.classic",
               gradientStart: .white, gradientEnd: .black),
        Filter(id: "bw.hicon",   name: "High Contrast", category: .blackWhite,
               ciFilterChain: "bw.high_contrast",
               gradientStart: Color(white: 0.95),
               gradientEnd:   Color(white: 0.05)),
        Filter(id: "bw.silver",  name: "Silver Tone",   category: .blackWhite,
               ciFilterChain: "bw.silver",
               gradientStart: Color(white: 0.82),
               gradientEnd:   Color(white: 0.18)),

        // Vibrant
        Filter(id: "vib.punch",  name: "Punchy",        category: .vibrant,
               ciFilterChain: "vibrant.punchy",
               gradientStart: Color(red: 1.0, green: 0.35, blue: 0.50),
               gradientEnd:   Color(red: 0.30, green: 0.10, blue: 0.50)),
        Filter(id: "vib.tropic", name: "Tropical",      category: .vibrant,
               ciFilterChain: "vibrant.tropical",
               gradientStart: Color(red: 0.15, green: 0.85, blue: 0.60),
               gradientEnd:   Color(red: 0.05, green: 0.35, blue: 0.60)),
        Filter(id: "vib.neon",   name: "Neon",          category: .vibrant,
               ciFilterChain: "vibrant.neon",
               gradientStart: Color(red: 0.95, green: 0.25, blue: 0.95),
               gradientEnd:   Color(red: 0.20, green: 0.90, blue: 0.95)),

        // Mood
        Filter(id: "mood.moody", name: "Moody",         category: .mood,
               ciFilterChain: "mood.moody",
               gradientStart: Color(red: 0.25, green: 0.25, blue: 0.35),
               gradientEnd:   Color(red: 0.05, green: 0.05, blue: 0.10)),
        Filter(id: "mood.dream", name: "Dreamy",        category: .mood,
               ciFilterChain: "mood.dreamy",
               gradientStart: Color(red: 0.95, green: 0.80, blue: 0.90),
               gradientEnd:   Color(red: 0.55, green: 0.45, blue: 0.70)),
        Filter(id: "mood.noir",  name: "Noir",          category: .mood,
               ciFilterChain: "mood.noir",
               gradientStart: Color(white: 0.55),
               gradientEnd:   .black)
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryChipRow
                    .padding(.top, LiquidSpacing.sm)
                    .padding(.horizontal, LiquidSpacing.lg)

                ScrollView {
                    filterGrid
                        .padding(.horizontal, LiquidSpacing.lg)
                        .padding(.top, LiquidSpacing.lg)
                        .padding(.bottom, 140) // reserve for intensity bar
                }
            }
            .safeAreaInset(edge: .bottom) {
                intensityBar
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Category Chips

    private var categoryChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.sm) {
                ForEach(FilterCategory.allCases) { category in
                    categoryChip(category)
                }
            }
            .padding(.vertical, LiquidSpacing.xs)
        }
    }

    private func categoryChip(_ category: FilterCategory) -> some View {
        let isSelected = (selectedCategory == category)
        return Button {
            HapticService.shared.trigger(.selection)
            selectedCategory = category
        } label: {
            Text(category.rawValue)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? LiquidColors.Accent.amber : .primary)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs + 2)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? LiquidColors.Accent.amber : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.rawValue) filter category")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Filter Grid

    private var filteredCatalog: [Filter] {
        if selectedCategory == .all { return Self.catalog }
        return Self.catalog.filter { $0.category == selectedCategory }
    }

    private var filterGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: LiquidSpacing.md),
                           count: 3),
            spacing: LiquidSpacing.md
        ) {
            ForEach(filteredCatalog) { filter in
                filterCard(filter)
            }
        }
    }

    private func filterCard(_ filter: Filter) -> some View {
        let isSelected = (selectedFilterID == filter.id)
        let intensityDotOpacity: Double = isSelected ? max(intensityPercent / 100, 0.15) : 0.0

        return Button {
            HapticService.shared.trigger(.selection)
            selectedFilterID = filter.id
        } label: {
            VStack(spacing: LiquidSpacing.xs) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [filter.gradientStart, filter.gradientEnd],
                                startPoint: .topLeading,
                                endPoint:   .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    // Intensity dot (top-right) — fills proportionally.
                    Circle()
                        .fill(LiquidColors.Accent.amber)
                        .frame(width: 8, height: 8)
                        .opacity(intensityDotOpacity)
                        .padding(6)
                        .accessibilityHidden(true)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                        .stroke(
                            isSelected ? LiquidColors.Accent.amber : Color.clear,
                            lineWidth: 2
                        )
                )

                Text(filter.name)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.name) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Intensity Bar

    private var intensityBar: some View {
        VStack(spacing: LiquidSpacing.sm) {
            HStack {
                Text("Intensity")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(intensityPercent))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $intensityPercent, in: 0...100, step: 1)
                .tint(LiquidColors.Accent.amber)
                .accessibilityLabel("Filter intensity")
                .accessibilityValue("\(Int(intensityPercent)) percent")
                .disabled(selectedFilterID == nil)

            Button(action: applySelection) {
                Text("Apply")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge, style: .continuous)
                            .fill(selectedFilterID == nil
                                  ? AnyShapeStyle(Color.gray.opacity(0.25))
                                  : AnyShapeStyle(LiquidColors.Accent.amber))
                    )
                    .foregroundStyle(selectedFilterID == nil ? Color.secondary : Color.black)
            }
            .buttonStyle(.plain)
            .disabled(selectedFilterID == nil)
            .accessibilityLabel("Apply filter")
        }
        .padding(LiquidSpacing.lg)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func applySelection() {
        guard let id = selectedFilterID,
              let chosen = Self.catalog.first(where: { $0.id == id }) else { return }
        HapticService.shared.trigger(.selection)
        onApply(FilterPickerSelection(
            filter: chosen,
            intensity: intensityPercent / 100.0
        ))
        dismiss()
    }
}

// MARK: - Previews

#Preview("Filter picker") {
    FilterPickerSheet(onApply: { _ in })
        .preferredColorScheme(.dark)
}
