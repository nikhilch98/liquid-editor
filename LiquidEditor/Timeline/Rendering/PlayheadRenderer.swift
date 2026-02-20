// PlayheadRenderer.swift
// LiquidEditor
//
// SwiftUI Canvas renderer for the timeline playhead.
// Renders a red vertical line with triangle handle, shadow, and fixed-center indicator.
//

import SwiftUI

// MARK: - PlayheadConstants

/// Constants for playhead rendering dimensions and styling.
enum PlayheadConstants: Sendable {
    static let handleWidth: Double = 12.0
    static let handleHeight: Double = 10.0

    static let lineStrokeWidth: Double = 2.0
    static let shadowStrokeWidth: Double = 4.0
    static let shadowBlur: Double = 2.0
    static let handleStrokeWidth: Double = 1.5

    static let bracketWidth: Double = 4.0
    static let bracketHeight: Double = 8.0
    static let bracketGap: Double = 6.0
    static let bracketStrokeWidth: Double = 1.5

    static let lightenAmount: Double = 0.2
    static let darkenAmount: Double = 0.2

    static let shadowOpacity: Double = 0.3
    static let bracketOpacity: Double = 0.6

    static let handleShadowOffsetY: Double = 1.0
}

// MARK: - PlayheadRenderer

/// Renders the playhead as a red vertical line with a triangle handle and shadow.
struct PlayheadRenderer: View, Equatable {

    /// X position of the playhead in pixels.
    let positionX: Double

    /// Height of the ruler area (handle sits here).
    let rulerHeight: Double

    /// Total height of the timeline area.
    let timelineHeight: Double

    /// Whether playhead is in fixed-center mode (used during playback).
    let isFixedCenter: Bool

    /// Whether to show the drag handle.
    let showHandle: Bool

    /// Color of the playhead line (defaults to iOS red).
    let color: Color

    init(
        positionX: Double,
        rulerHeight: Double,
        timelineHeight: Double,
        isFixedCenter: Bool = false,
        showHandle: Bool = true,
        color: Color = LiquidColors.timelinePlayhead
    ) {
        self.positionX = positionX
        self.rulerHeight = rulerHeight
        self.timelineHeight = timelineHeight
        self.isFixedCenter = isFixedCenter
        self.showHandle = showHandle
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            let calculations = PlayheadRenderCalculations(
                positionX: positionX,
                rulerHeight: rulerHeight,
                timelineHeight: timelineHeight,
                isFixedCenter: isFixedCenter,
                showHandle: showHandle,
                color: color
            )
            calculations.draw(into: &context, size: size)
        }
    }
}

// MARK: - PlayheadRenderCalculations

/// Extracted calculation and drawing logic for testability.
struct PlayheadRenderCalculations: Sendable {

    let positionX: Double
    let rulerHeight: Double
    let timelineHeight: Double
    let isFixedCenter: Bool
    let showHandle: Bool
    let color: Color

    /// Create the triangle handle path for a given X position.
    static func handlePath(positionX: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: positionX - PlayheadConstants.handleWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: positionX + PlayheadConstants.handleWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: positionX, y: PlayheadConstants.handleHeight))
        path.closeSubpath()
        return path
    }

    /// Create the left bracket path for fixed-center indicator.
    static func leftBracketPath(positionX: Double, rulerHeight: Double) -> Path {
        var path = Path()
        let gap = PlayheadConstants.bracketGap
        let w = PlayheadConstants.bracketWidth
        let h = PlayheadConstants.bracketHeight
        path.move(to: CGPoint(x: positionX - gap, y: rulerHeight + h))
        path.addLine(to: CGPoint(x: positionX - gap - w, y: rulerHeight + h))
        path.addLine(to: CGPoint(x: positionX - gap - w, y: rulerHeight))
        path.addLine(to: CGPoint(x: positionX - gap, y: rulerHeight))
        return path
    }

    /// Create the right bracket path for fixed-center indicator.
    static func rightBracketPath(positionX: Double, rulerHeight: Double) -> Path {
        var path = Path()
        let gap = PlayheadConstants.bracketGap
        let w = PlayheadConstants.bracketWidth
        let h = PlayheadConstants.bracketHeight
        path.move(to: CGPoint(x: positionX + gap, y: rulerHeight + h))
        path.addLine(to: CGPoint(x: positionX + gap + w, y: rulerHeight + h))
        path.addLine(to: CGPoint(x: positionX + gap + w, y: rulerHeight))
        path.addLine(to: CGPoint(x: positionX + gap, y: rulerHeight))
        return path
    }

    // MARK: - Drawing

    func draw(into context: inout GraphicsContext, size: CGSize) {
        guard positionX >= 0, positionX <= size.width else { return }

        drawShadow(into: &context)
        drawLine(into: &context)

        if showHandle {
            drawHandle(into: &context)
        }

        if isFixedCenter {
            drawFixedCenterIndicator(into: &context)
        }
    }

    private func drawShadow(into context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: positionX, y: rulerHeight))
        path.addLine(to: CGPoint(x: positionX, y: timelineHeight))
        context.stroke(
            path,
            with: .color(color.opacity(PlayheadConstants.shadowOpacity)),
            lineWidth: PlayheadConstants.shadowStrokeWidth
        )
    }

    private func drawLine(into context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: positionX, y: rulerHeight))
        path.addLine(to: CGPoint(x: positionX, y: timelineHeight))
        context.stroke(
            path,
            with: .color(color),
            lineWidth: PlayheadConstants.lineStrokeWidth
        )
    }

    private func drawHandle(into context: inout GraphicsContext) {
        let trianglePath = Self.handlePath(positionX: positionX)

        // Shadow
        var shadowContext = context
        shadowContext.translateBy(x: 0, y: PlayheadConstants.handleShadowOffsetY)
        shadowContext.fill(trianglePath, with: .color(Color.black.opacity(0.25)))

        // Gradient fill
        let handleRect = CGRect(
            x: positionX - PlayheadConstants.handleWidth / 2,
            y: 0,
            width: PlayheadConstants.handleWidth,
            height: PlayheadConstants.handleHeight
        )
        context.fill(
            trianglePath,
            with: .linearGradient(
                Gradient(colors: [color.lighter(by: PlayheadConstants.lightenAmount), color]),
                startPoint: CGPoint(x: handleRect.midX, y: handleRect.minY),
                endPoint: CGPoint(x: handleRect.midX, y: handleRect.maxY)
            )
        )

        // Stroke
        context.stroke(
            trianglePath,
            with: .color(color.darker(by: PlayheadConstants.darkenAmount)),
            lineWidth: PlayheadConstants.handleStrokeWidth
        )

        // Connector line from handle to ruler
        var connectorPath = Path()
        connectorPath.move(to: CGPoint(x: positionX, y: PlayheadConstants.handleHeight))
        connectorPath.addLine(to: CGPoint(x: positionX, y: rulerHeight))
        context.stroke(connectorPath, with: .color(color), lineWidth: PlayheadConstants.lineStrokeWidth)
    }

    private func drawFixedCenterIndicator(into context: inout GraphicsContext) {
        let bracketColor = color.opacity(PlayheadConstants.bracketOpacity)
        let style = StrokeStyle(lineWidth: PlayheadConstants.bracketStrokeWidth, lineCap: .round)

        context.stroke(
            Self.leftBracketPath(positionX: positionX, rulerHeight: rulerHeight),
            with: .color(bracketColor),
            style: style
        )
        context.stroke(
            Self.rightBracketPath(positionX: positionX, rulerHeight: rulerHeight),
            with: .color(bracketColor),
            style: style
        )
    }
}

// MARK: - Color Lighten/Darken

extension Color {

    /// Lighten a color by the given amount (0.0 - 1.0).
    func lighter(by amount: Double) -> Color {
        adjustBrightness(by: amount)
    }

    /// Darken a color by the given amount (0.0 - 1.0).
    func darker(by amount: Double) -> Color {
        adjustBrightness(by: -amount)
    }

    private func adjustBrightness(by amount: Double) -> Color {
        // Use UIColor HSL conversion
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let newBrightness = min(max(brightness + CGFloat(amount), 0), 1)
        return Color(UIColor(hue: hue, saturation: saturation, brightness: newBrightness, alpha: alpha))
    }
}
