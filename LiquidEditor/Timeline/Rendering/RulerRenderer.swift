// RulerRenderer.swift
// LiquidEditor
//
// SwiftUI Canvas renderer for the timeline ruler.
// Renders adaptive tick marks, time labels, and in/out range highlights.
//

import SwiftUI

// MARK: - RulerConstants

/// Constants for ruler rendering dimensions and styling.
enum RulerConstants: Sendable {
    static let defaultHeight: Double = 30.0
    static let labelFontSize: Double = 10.0
    static let letterSpacing: Double = -0.2
    static let targetMajorSpacing: Double = 80.0

    static let majorTickHeightRatio: Double = 0.6
    static let mediumTickHeightRatio: Double = 0.4
    static let minorTickHeightRatio: Double = 0.25

    static let majorTickStroke: Double = 1.0
    static let minorTickStroke: Double = 0.5

    static let rangeMarkerWidth: Double = 2.0
    static let triangleIndicatorSize: Double = 6.0

    static let borderOpacity: Double = 0.3
    static let rangeHighlightOpacity: Double = 0.3
    static let mediumTickOpacity: Double = 0.6
    static let minorTickOpacity: Double = 0.3

    static let labelTopOffset: Double = 4.0
    static let labelEdgePadding: Double = 2.0
    static let bottomBorderOffset: Double = 0.5
}

// MARK: - RulerRenderer

/// Renders the time ruler with adaptive tick intervals and time labels.
struct RulerRenderer: View, Equatable {

    /// Viewport state for time-to-pixel conversion.
    let viewport: ViewportState

    /// In point for range highlight (optional).
    let inPoint: TimeMicros?

    /// Out point for range highlight (optional).
    let outPoint: TimeMicros?

    /// Height of the ruler.
    let height: Double

    /// Background color.
    let backgroundColor: Color

    /// Tick color.
    let tickColor: Color

    /// Text color.
    let textColor: Color

    /// Range highlight color (for in/out selection).
    let rangeColor: Color

    init(
        viewport: ViewportState,
        inPoint: TimeMicros? = nil,
        outPoint: TimeMicros? = nil,
        height: Double = RulerConstants.defaultHeight,
        backgroundColor: Color = Color(red: 0.11, green: 0.11, blue: 0.118),
        tickColor: Color = Color(red: 0.557, green: 0.557, blue: 0.576),
        textColor: Color = .white,
        rangeColor: Color = Color(red: 0.0, green: 0.478, blue: 1.0)
    ) {
        self.viewport = viewport
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.height = height
        self.backgroundColor = backgroundColor
        self.tickColor = tickColor
        self.textColor = textColor
        self.rangeColor = rangeColor
    }

    var body: some View {
        Canvas { context, size in
            let calculations = RulerRenderCalculations(
                viewport: viewport,
                inPoint: inPoint,
                outPoint: outPoint,
                height: height,
                backgroundColor: backgroundColor,
                tickColor: tickColor,
                textColor: textColor,
                rangeColor: rangeColor
            )
            calculations.draw(into: &context, size: size)
        }
    }
}

// MARK: - RulerRenderCalculations

/// Extracted calculation and drawing logic for testability.
struct RulerRenderCalculations: Sendable {

    let viewport: ViewportState
    let inPoint: TimeMicros?
    let outPoint: TimeMicros?
    let height: Double
    let backgroundColor: Color
    let tickColor: Color
    let textColor: Color
    let rangeColor: Color

    // MARK: - Tick Configuration

    /// Tick interval configurations: (interval in microseconds, majorEvery).
    static let tickConfigs: [(interval: Int, majorEvery: Int)] = [
        (1_000, 10),        // 1ms, major every 10ms
        (10_000, 10),       // 10ms, major every 100ms
        (100_000, 10),      // 100ms, major every 1s
        (500_000, 2),       // 500ms, major every 1s
        (1_000_000, 10),    // 1s, major every 10s
        (5_000_000, 2),     // 5s, major every 10s
        (10_000_000, 6),    // 10s, major every 1m
        (30_000_000, 2),    // 30s, major every 1m
        (60_000_000, 5),    // 1m, major every 5m
        (300_000_000, 2),   // 5m, major every 10m
        (600_000_000, 6),   // 10m, major every 1h
    ]

    /// Select appropriate tick configuration for the current zoom level.
    func getTickConfig() -> (interval: Int, majorEvery: Int) {
        let targetMajorMicros = viewport.microsPerPixel * RulerConstants.targetMajorSpacing

        for config in Self.tickConfigs {
            let majorInterval = config.interval * config.majorEvery
            if Double(majorInterval) >= targetMajorMicros * 0.5 {
                return config
            }
        }
        return Self.tickConfigs.last!
    }

    /// Format a time value as a display string.
    func formatTime(_ micros: TimeMicros) -> String {
        let totalSeconds = Int(micros / 1_000_000)
        let ms = Int((micros % 1_000_000) / 1_000)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        } else if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else if viewport.microsPerPixel < 5000 {
            return "\(seconds).\(String(format: "%02d", ms / 10))"
        } else {
            return "\(seconds)s"
        }
    }

    // MARK: - Drawing

    func draw(into context: inout GraphicsContext, size: CGSize) {
        // Background
        context.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: height)),
            with: .color(backgroundColor)
        )

        // Range highlight
        if let inPt = inPoint, let outPt = outPoint {
            drawRangeHighlight(inPoint: inPt, outPoint: outPt, into: &context)
        }

        // Ticks
        let config = getTickConfig()
        drawTicks(tickInterval: config.interval, majorEvery: config.majorEvery, into: &context, size: size)

        // Bottom border
        var borderPath = Path()
        let borderY = height - RulerConstants.bottomBorderOffset
        borderPath.move(to: CGPoint(x: 0, y: borderY))
        borderPath.addLine(to: CGPoint(x: size.width, y: borderY))
        context.stroke(
            borderPath,
            with: .color(tickColor.opacity(RulerConstants.borderOpacity)),
            lineWidth: 1.0
        )
    }

    private func drawTicks(tickInterval: Int, majorEvery: Int, into context: inout GraphicsContext, size: CGSize) {
        let visibleRange = viewport.visibleTimeRange

        let firstTick = (visibleRange.start / TimeMicros(tickInterval)) * TimeMicros(tickInterval)

        var tickCount = 0
        var time = firstTick
        while time <= visibleRange.end {
            let x = viewport.timeToPixelX(time)

            if x < 0 {
                tickCount += 1
                time += TimeMicros(tickInterval)
                continue
            }
            if x > viewport.contentWidth { break }

            let isMajor = tickCount % majorEvery == 0
            let halfMajor = majorEvery / 2
            let isMedium = !isMajor && halfMajor > 0 && tickCount % halfMajor == 0

            // Tick height
            let tickHeight: Double
            if isMajor {
                tickHeight = height * RulerConstants.majorTickHeightRatio
            } else if isMedium {
                tickHeight = height * RulerConstants.mediumTickHeightRatio
            } else {
                tickHeight = height * RulerConstants.minorTickHeightRatio
            }

            // Tick color & width
            let currentTickColor: Color
            let strokeWidth: Double
            if isMajor {
                currentTickColor = tickColor
                strokeWidth = RulerConstants.majorTickStroke
            } else if isMedium {
                currentTickColor = tickColor.opacity(RulerConstants.mediumTickOpacity)
                strokeWidth = RulerConstants.minorTickStroke
            } else {
                currentTickColor = tickColor.opacity(RulerConstants.minorTickOpacity)
                strokeWidth = RulerConstants.minorTickStroke
            }

            // Draw tick
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: height))
            tickPath.addLine(to: CGPoint(x: x, y: height - tickHeight))
            context.stroke(tickPath, with: .color(currentTickColor), lineWidth: strokeWidth)

            // Time label at major ticks
            if isMajor {
                drawTimeLabel(time: time, x: x, into: &context)
            }

            tickCount += 1
            time += TimeMicros(tickInterval)
        }
    }

    private func drawTimeLabel(time: TimeMicros, x: Double, into context: inout GraphicsContext) {
        let label = formatTime(time)
        let text = Text(label)
            .font(.system(size: RulerConstants.labelFontSize, weight: .medium))
            .foregroundColor(textColor)

        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: CGSize(width: 200, height: height))
        let labelX = x - textSize.width / 2
        let labelY = RulerConstants.labelTopOffset

        // Don't draw if clipped at edges
        if labelX < RulerConstants.labelEdgePadding ||
           labelX + textSize.width > viewport.contentWidth - RulerConstants.labelEdgePadding {
            return
        }

        context.draw(
            resolved,
            in: CGRect(x: labelX, y: labelY, width: textSize.width, height: textSize.height)
        )
    }

    private func drawRangeHighlight(inPoint: TimeMicros, outPoint: TimeMicros, into context: inout GraphicsContext) {
        let startX = viewport.timeToPixelX(inPoint)
        let endX = viewport.timeToPixelX(outPoint)

        if endX < 0 || startX > viewport.contentWidth { return }

        let clampedStartX = min(max(startX, 0), viewport.contentWidth)
        let clampedEndX = min(max(endX, 0), viewport.contentWidth)

        // Range fill
        context.fill(
            Path(CGRect(x: clampedStartX, y: 0, width: clampedEndX - clampedStartX, height: height)),
            with: .color(rangeColor.opacity(RulerConstants.rangeHighlightOpacity))
        )

        // In/out markers
        drawRangeMarker(x: startX, isInPoint: true, into: &context)
        drawRangeMarker(x: endX, isInPoint: false, into: &context)
    }

    private func drawRangeMarker(x: Double, isInPoint: Bool, into context: inout GraphicsContext) {
        guard x >= 0, x <= viewport.contentWidth else { return }

        // Vertical line
        context.fill(
            Path(CGRect(
                x: x - RulerConstants.rangeMarkerWidth / 2,
                y: 0,
                width: RulerConstants.rangeMarkerWidth,
                height: height
            )),
            with: .color(rangeColor)
        )

        // Triangle indicator
        let triSize = RulerConstants.triangleIndicatorSize
        var triPath = Path()
        if isInPoint {
            triPath.move(to: CGPoint(x: x, y: height - triSize))
            triPath.addLine(to: CGPoint(x: x + triSize, y: height))
            triPath.addLine(to: CGPoint(x: x, y: height))
            triPath.closeSubpath()
        } else {
            triPath.move(to: CGPoint(x: x, y: height - triSize))
            triPath.addLine(to: CGPoint(x: x - triSize, y: height))
            triPath.addLine(to: CGPoint(x: x, y: height))
            triPath.closeSubpath()
        }
        context.fill(triPath, with: .color(rangeColor))
    }
}
