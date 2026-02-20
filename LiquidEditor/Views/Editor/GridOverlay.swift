// GridOverlay.swift
// LiquidEditor
//
// Rule-of-thirds, golden ratio, center cross, diagonal, square grid,
// and custom grid overlays rendered via SwiftUI Canvas on the video
// preview. Includes a settings panel for configuration.
//
// Pure SwiftUI, iOS 26 native styling.
// Matches Flutter GridOverlayPainter + GridSettingsPanel layout.

import SwiftUI

// MARK: - GridType

/// Available grid overlay types for composition guidance.
enum GridType: String, CaseIterable, Codable, Identifiable, Sendable {
    case ruleOfThirds
    case goldenRatio
    case centerCross
    case diagonal
    case squareGrid
    case custom

    var id: String { rawValue }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .ruleOfThirds: "Rule of Thirds"
        case .goldenRatio:  "Golden Ratio"
        case .centerCross:  "Center Cross"
        case .diagonal:     "Diagonal"
        case .squareGrid:   "Square Grid"
        case .custom:       "Custom"
        }
    }
}

// MARK: - GridOverlayConfig

/// Configuration for the grid overlay.
struct GridOverlayConfig: Equatable, Sendable {

    /// The type of grid to display.
    var type: GridType = .ruleOfThirds

    /// Whether the grid is currently visible.
    var isVisible: Bool = false

    /// Opacity of the grid lines (0.0 - 1.0).
    var opacity: Double = 0.5

    /// Color of the grid lines.
    var lineColor: Color = .white

    /// Width of the grid lines in points.
    var lineWidth: CGFloat = 0.5

    /// Number of rows for custom grid (clamped to 2-20).
    var customRows: Int = 3

    /// Number of columns for custom grid (clamped to 2-20).
    var customColumns: Int = 3
}

// MARK: - GridOverlayView

/// SwiftUI Canvas overlay that draws grid lines on top of the video preview.
///
/// Renders different grid patterns based on ``GridOverlayConfig/type``.
/// Each line is drawn with a shadow stroke behind it for readability
/// against any background content.
struct GridOverlayView: View {

    /// Configuration driving the grid display.
    let config: GridOverlayConfig

    /// Size of the video preview area to draw over.
    let previewSize: CGSize

    var body: some View {
        if config.isVisible, previewSize.width > 0, previewSize.height > 0 {
            Canvas { context, size in
                let origin = CGPoint(
                    x: (size.width - previewSize.width) / 2,
                    y: (size.height - previewSize.height) / 2
                )
                let area = CGRect(origin: origin, size: previewSize)
                draw(in: &context, area: area)
            }
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("\(config.type.displayName) grid overlay")
            .accessibilityHint("Composition guide visible on video preview")
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, area: CGRect) {
        switch config.type {
        case .ruleOfThirds:
            drawGrid(in: &context, area: area, rows: 3, cols: 3)
        case .goldenRatio:
            drawGoldenRatio(in: &context, area: area)
        case .centerCross:
            drawCenterCross(in: &context, area: area)
        case .diagonal:
            drawDiagonals(in: &context, area: area)
        case .squareGrid:
            drawGrid(in: &context, area: area, rows: 4, cols: 4)
        case .custom:
            let rows = max(2, min(config.customRows, 20))
            let cols = max(2, min(config.customColumns, 20))
            drawGrid(in: &context, area: area, rows: rows, cols: cols)
        }
    }

    private func drawGrid(
        in context: inout GraphicsContext,
        area: CGRect,
        rows: Int,
        cols: Int
    ) {
        // Vertical lines
        for i in 1..<cols {
            let x = area.minX + area.width * CGFloat(i) / CGFloat(cols)
            let from = CGPoint(x: x, y: area.minY)
            let to = CGPoint(x: x, y: area.maxY)
            strokeLine(in: &context, from: from, to: to)
        }
        // Horizontal lines
        for i in 1..<rows {
            let y = area.minY + area.height * CGFloat(i) / CGFloat(rows)
            let from = CGPoint(x: area.minX, y: y)
            let to = CGPoint(x: area.maxX, y: y)
            strokeLine(in: &context, from: from, to: to)
        }
    }

    private func drawGoldenRatio(
        in context: inout GraphicsContext,
        area: CGRect
    ) {
        let phi: CGFloat = 0.381966 // 1 - 1/phi
        let positions: [CGFloat] = [phi, 1.0 - phi]
        for p in positions {
            let x = area.minX + area.width * p
            let y = area.minY + area.height * p
            strokeLine(
                in: &context,
                from: CGPoint(x: x, y: area.minY),
                to: CGPoint(x: x, y: area.maxY)
            )
            strokeLine(
                in: &context,
                from: CGPoint(x: area.minX, y: y),
                to: CGPoint(x: area.maxX, y: y)
            )
        }
    }

    private func drawCenterCross(
        in context: inout GraphicsContext,
        area: CGRect
    ) {
        let cx = area.midX
        let cy = area.midY
        strokeLine(
            in: &context,
            from: CGPoint(x: cx, y: area.minY),
            to: CGPoint(x: cx, y: area.maxY)
        )
        strokeLine(
            in: &context,
            from: CGPoint(x: area.minX, y: cy),
            to: CGPoint(x: area.maxX, y: cy)
        )
    }

    private func drawDiagonals(
        in context: inout GraphicsContext,
        area: CGRect
    ) {
        strokeLine(
            in: &context,
            from: CGPoint(x: area.minX, y: area.minY),
            to: CGPoint(x: area.maxX, y: area.maxY)
        )
        strokeLine(
            in: &context,
            from: CGPoint(x: area.maxX, y: area.minY),
            to: CGPoint(x: area.minX, y: area.maxY)
        )
    }

    // MARK: - Stroke Helper

    /// Draws a line with a shadow stroke behind it for contrast.
    private func strokeLine(
        in context: inout GraphicsContext,
        from: CGPoint,
        to: CGPoint
    ) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)

        // Shadow for readability
        context.stroke(
            path,
            with: .color(.black.opacity(config.opacity * 0.5)),
            lineWidth: config.lineWidth + 1.0
        )
        // Foreground line
        context.stroke(
            path,
            with: .color(config.lineColor.opacity(config.opacity)),
            lineWidth: config.lineWidth
        )
    }
}

// MARK: - Grid Line Calculations (Testable)

/// Pure functions for computing grid line positions.
///
/// Extracted to enable unit testing without requiring view instantiation.
enum GridLineCalculator {

    /// Compute x-positions for vertical grid lines.
    ///
    /// - Parameters:
    ///   - width: Total width of the area.
    ///   - columns: Number of columns to divide into.
    /// - Returns: Array of x-positions for vertical lines.
    static func verticalLinePositions(width: CGFloat, columns: Int) -> [CGFloat] {
        guard columns > 1 else { return [] }
        return (1..<columns).map { i in
            width * CGFloat(i) / CGFloat(columns)
        }
    }

    /// Compute y-positions for horizontal grid lines.
    ///
    /// - Parameters:
    ///   - height: Total height of the area.
    ///   - rows: Number of rows to divide into.
    /// - Returns: Array of y-positions for horizontal lines.
    static func horizontalLinePositions(height: CGFloat, rows: Int) -> [CGFloat] {
        guard rows > 1 else { return [] }
        return (1..<rows).map { i in
            height * CGFloat(i) / CGFloat(rows)
        }
    }

    /// Compute golden ratio line positions along an axis.
    ///
    /// - Parameter length: Total length of the axis.
    /// - Returns: Two positions at the golden ratio proportions.
    static func goldenRatioPositions(length: CGFloat) -> [CGFloat] {
        let phi: CGFloat = 0.381966
        return [length * phi, length * (1.0 - phi)]
    }

    /// Compute the center position along an axis.
    ///
    /// - Parameter length: Total length of the axis.
    /// - Returns: The midpoint.
    static func centerPosition(length: CGFloat) -> CGFloat {
        length / 2
    }
}

// MARK: - GridSettingsPanel

/// Settings panel for configuring the grid overlay.
///
/// Contains Show Grid toggle, Grid Type picker (via action sheet),
/// Opacity slider, and conditional Custom rows/columns stepper controls.
/// Styled with native `List` and `.listStyle(.insetGrouped)`.
struct GridSettingsPanel: View {

    /// Binding to the grid configuration.
    @Binding var config: GridOverlayConfig

    var body: some View {
        List {
            Section(header: Text("GRID OVERLAY")) {
                // Show Grid toggle.
                Toggle("Show Grid", isOn: $config.isVisible)

                // Grid Type picker via Menu.
                gridTypePicker

                // Opacity slider.
                opacityControl

                // Custom rows/columns (only when custom type selected).
                if config.type == .custom {
                    customRowsControl
                    customColumnsControl
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Grid Type Picker

    @ViewBuilder
    private var gridTypePicker: some View {
        HStack {
            Text("Grid Type")
            Spacer()
            Menu {
                ForEach(GridType.allCases) { gridType in
                    Button {
                        config.type = gridType
                    } label: {
                        HStack {
                            Text(gridType.displayName)
                            if config.type == gridType {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: LiquidSpacing.xs) {
                    Text(config.type.displayName)
                        .foregroundStyle(LiquidColors.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidColors.textSecondary)
                }
            }
            .accessibilityLabel("Grid type: \(config.type.displayName)")
            .accessibilityHint("Opens grid type selection menu")
        }
    }

    // MARK: - Opacity Control

    @ViewBuilder
    private var opacityControl: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            HStack {
                Text("Opacity")
                Spacer()
                Text("\(Int(config.opacity * 100))%")
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            Slider(value: $config.opacity, in: 0.1...1.0)
                .accessibilityLabel("Grid opacity")
                .accessibilityValue("\(Int(config.opacity * 100)) percent")
        }
    }

    // MARK: - Custom Rows Control

    @ViewBuilder
    private var customRowsControl: some View {
        HStack {
            Text("Rows")
            Spacer()
            Text("\(config.customRows)")
                .foregroundStyle(LiquidColors.textSecondary)

            Button {
                config.customRows = max(2, config.customRows - 1)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .disabled(config.customRows <= 2)
            .accessibilityLabel("Decrease rows")

            Button {
                config.customRows = min(20, config.customRows + 1)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .disabled(config.customRows >= 20)
            .accessibilityLabel("Increase rows")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Grid rows: \(config.customRows)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                config.customRows = min(20, config.customRows + 1)
            case .decrement:
                config.customRows = max(2, config.customRows - 1)
            @unknown default:
                break
            }
        }
    }

    // MARK: - Custom Columns Control

    @ViewBuilder
    private var customColumnsControl: some View {
        HStack {
            Text("Columns")
            Spacer()
            Text("\(config.customColumns)")
                .foregroundStyle(LiquidColors.textSecondary)

            Button {
                config.customColumns = max(2, config.customColumns - 1)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .disabled(config.customColumns <= 2)
            .accessibilityLabel("Decrease columns")

            Button {
                config.customColumns = min(20, config.customColumns + 1)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            .disabled(config.customColumns >= 20)
            .accessibilityLabel("Increase columns")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Grid columns: \(config.customColumns)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                config.customColumns = min(20, config.customColumns + 1)
            case .decrement:
                config.customColumns = max(2, config.customColumns - 1)
            @unknown default:
                break
            }
        }
    }
}
