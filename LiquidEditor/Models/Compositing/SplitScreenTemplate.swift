// SplitScreenTemplate.swift
// LiquidEditor
//
// Split screen layout templates for multi-track compositing.
// Pre-defined grid layouts that assign tracks to cells within the output frame.
// Each cell is a NormalizedRect defining where a track renders.

import Foundation

/// Content fitting mode for split screen cells.
enum ContentFit: String, Codable, CaseIterable, Sendable {
    /// Fill cell, cropping excess (default -- no letterboxing).
    case fill

    /// Fit entire video within cell (may show black bars).
    case fit

    /// Stretch video to exactly match cell dimensions.
    case stretch

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .fill:
            return "Fill"
        case .fit:
            return "Fit"
        case .stretch:
            return "Stretch"
        }
    }
}

/// Split-screen layout template.
///
/// Defines a grid layout with named cells. Each cell is a ``NormalizedRect``
/// specifying where a track's video renders within the output frame.
struct SplitScreenTemplate: Codable, Equatable, Hashable, Sendable {
    /// Unique identifier for this template.
    let id: String

    /// Display name.
    let name: String

    /// Number of rows in the grid.
    let rows: Int

    /// Number of columns in the grid.
    let columns: Int

    /// Cell regions in the grid.
    let cells: [NormalizedRect]

    /// Normalized gap width between cells (0.0-0.05).
    let gapWidth: Double

    init(
        id: String,
        name: String,
        rows: Int,
        columns: Int,
        cells: [NormalizedRect],
        gapWidth: Double = 0.005
    ) {
        self.id = id
        self.name = name
        self.rows = rows
        self.columns = columns
        self.cells = cells
        self.gapWidth = gapWidth
    }

    /// Number of cells in the template.
    var cellCount: Int { cells.count }

    // MARK: - Built-in Templates

    /// Side by side (50/50 horizontal).
    static let sideBySide = SplitScreenTemplate(
        id: "side_by_side",
        name: "Side by Side",
        rows: 1,
        columns: 2,
        cells: [
            NormalizedRect(x: 0.0, y: 0.0, width: 0.497, height: 1.0),
            NormalizedRect(x: 0.503, y: 0.0, width: 0.497, height: 1.0),
        ]
    )

    /// Top and bottom (50/50 vertical).
    static let topBottom = SplitScreenTemplate(
        id: "top_bottom",
        name: "Top & Bottom",
        rows: 2,
        columns: 1,
        cells: [
            NormalizedRect(x: 0.0, y: 0.0, width: 1.0, height: 0.497),
            NormalizedRect(x: 0.0, y: 0.503, width: 1.0, height: 0.497),
        ]
    )

    /// 2x2 grid.
    static let grid2x2 = SplitScreenTemplate(
        id: "grid_2x2",
        name: "2x2 Grid",
        rows: 2,
        columns: 2,
        cells: [
            NormalizedRect(x: 0.0, y: 0.0, width: 0.497, height: 0.497),
            NormalizedRect(x: 0.503, y: 0.0, width: 0.497, height: 0.497),
            NormalizedRect(x: 0.0, y: 0.503, width: 0.497, height: 0.497),
            NormalizedRect(x: 0.503, y: 0.503, width: 0.497, height: 0.497),
        ]
    )

    /// 3-up layout (1 top full-width + 2 bottom).
    static let threeUp = SplitScreenTemplate(
        id: "three_up",
        name: "3-Up (1 + 2)",
        rows: 2,
        columns: 2,
        cells: [
            NormalizedRect(x: 0.0, y: 0.0, width: 1.0, height: 0.497),
            NormalizedRect(x: 0.0, y: 0.503, width: 0.497, height: 0.497),
            NormalizedRect(x: 0.503, y: 0.503, width: 0.497, height: 0.497),
        ]
    )

    /// All built-in templates.
    static let builtInTemplates: [SplitScreenTemplate] = [
        .sideBySide,
        .topBottom,
        .grid2x2,
        .threeUp,
    ]

    // MARK: - Equatable

    static func == (lhs: SplitScreenTemplate, rhs: SplitScreenTemplate) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case rows
        case columns
        case cells
        case gapWidth
    }
}

// MARK: - CustomStringConvertible

extension SplitScreenTemplate: CustomStringConvertible {
    var description: String {
        "SplitScreenTemplate(\(name), \(cells.count) cells)"
    }
}
