// VirtualizedGrid.swift
// LiquidEditor
//
// PP12-1: A thin SwiftUI wrapper around `LazyVGrid` that documents and
// standardizes the virtualized-grid pattern used across Library,
// Sticker Picker, Template Browser, and Effects Browser screens.
//
// Why this exists:
// - `LazyVGrid` already virtualizes rows — cells outside the visible
//   window are NOT instantiated until scrolled into view, and are
//   deallocated when scrolled far enough out of view (subject to
//   SwiftUI's internal windowing heuristics).
// - This wrapper makes the virtualization opt-in contract explicit,
//   and provides a single place to add instrumentation (os_signpost),
//   memory-pressure reactions, and visible-row tracking in the future.
// - It also makes grids cheaper to refactor — consumers pass a flat
//   `[Item]` array and a cell builder, and do not need to hand-roll
//   `LazyVGrid(columns:)` every time.
//
// Thread Safety: Pure SwiftUI view — no shared mutable state. Safe
// from any context that can construct a View.

import SwiftUI

// MARK: - VirtualizedGridContentMode

/// How the grid lays out columns.
///
/// - adaptive: `GridItem(.adaptive(minimum:))` — columns count is
///   derived from the available width and the minimum cell size.
///   This is the default and recommended mode for responsive grids
///   that need to work across iPhone/iPad/Split View.
/// - fixed: Exactly `columns` columns, each `.flexible()`. Use when
///   the layout requires a hard column count.
enum VirtualizedGridContentMode: Sendable, Equatable {
    case adaptive(minimum: CGFloat)
    case fixed(columns: Int)
}

// MARK: - VirtualizedGrid

/// A virtualized grid of items backed by `LazyVGrid`.
///
/// Use for any scrolling grid of 50+ items — Library thumbnails,
/// Sticker Picker, Template Browser, Effects Browser, etc. Cells are
/// instantiated lazily as they scroll into view, so memory stays
/// proportional to the visible window regardless of total item count.
///
/// ## Usage
///
/// ```swift
/// VirtualizedGrid(
///     items: library.items,
///     mode: .adaptive(minimum: 110),
///     spacing: LiquidSpacing.md
/// ) { item in
///     LibraryThumbnail(item: item)
/// }
/// ```
///
/// ## Visible-window tracking
///
/// Consumers that need to react to which items are currently visible
/// (e.g. to prefetch thumbnails) can pass `onAppear` / `onDisappear`
/// handlers; these fire when a cell's `onAppear` / `onDisappear`
/// SwiftUI lifecycle callback fires. Note that SwiftUI may instantiate
/// cells slightly outside the visible frame for smooth scrolling.
///
/// - Parameters:
///   - items: The flat array of items to display. Must be `Identifiable`.
///   - mode: How columns are laid out. Defaults to
///     `.adaptive(minimum: 100)` which works for most thumbnail grids.
///   - spacing: Inter-cell spacing (applied to both rows and columns).
///     Defaults to 12pt.
///   - alignment: Horizontal alignment of cells inside each row.
///   - onAppear: Optional callback when a cell appears on screen.
///   - onDisappear: Optional callback when a cell leaves the screen.
///   - content: Cell builder. Called lazily only for visible items.
struct VirtualizedGrid<Item: Identifiable, Content: View>: View {

    // MARK: - Inputs

    let items: [Item]
    let mode: VirtualizedGridContentMode
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let onAppear: ((Item) -> Void)?
    let onDisappear: ((Item) -> Void)?
    @ViewBuilder let content: (Item) -> Content

    // MARK: - Init

    init(
        items: [Item],
        mode: VirtualizedGridContentMode = .adaptive(minimum: 100),
        spacing: CGFloat = 12,
        alignment: HorizontalAlignment = .leading,
        onAppear: ((Item) -> Void)? = nil,
        onDisappear: ((Item) -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.mode = mode
        self.spacing = spacing
        self.alignment = alignment
        self.onAppear = onAppear
        self.onDisappear = onDisappear
        self.content = content
    }

    /// Convenience initializer for the common fixed-column case.
    init(
        items: [Item],
        columns: Int,
        spacing: CGFloat = 12,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.init(
            items: items,
            mode: .fixed(columns: max(1, columns)),
            spacing: spacing,
            alignment: alignment,
            onAppear: nil,
            onDisappear: nil,
            content: content
        )
    }

    // MARK: - Layout

    /// Computed `[GridItem]` for the current mode and spacing.
    private var gridColumns: [GridItem] {
        switch mode {
        case .adaptive(let minimum):
            return [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .top)]
        case .fixed(let columns):
            return Array(
                repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
                count: max(1, columns)
            )
        }
    }

    // MARK: - Body

    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: alignment, spacing: spacing) {
            ForEach(items) { item in
                content(item)
                    .onAppear { onAppear?(item) }
                    .onDisappear { onDisappear?(item) }
            }
        }
    }
}

// MARK: - Preview

#Preview("VirtualizedGrid — adaptive") {
    struct PreviewItem: Identifiable {
        let id = UUID()
        let label: String
    }
    let items = (0..<500).map { PreviewItem(label: "#\($0)") }
    return ScrollView {
        VirtualizedGrid(items: items, mode: .adaptive(minimum: 90), spacing: 12) { item in
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(height: 90)
                .overlay(Text(item.label).font(.caption))
        }
        .padding(16)
    }
}
