// SnapGuideRenderer.swift
// LiquidEditor
//
// SwiftUI Canvas renderer for magnetic snap guide lines.
// Renders vertical snap lines with glow effects during drag/trim operations.
//

import SwiftUI

// MARK: - SnapGuideColor

/// Provides colors for snap guide types.
enum SnapGuideColor {

    /// Default color for a snap target type.
    static func color(for type: SnapTargetType) -> Color {
        switch type {
        case .playhead:   Color(red: 1.0, green: 0.231, blue: 0.188)   // iOS red
        case .clipEdge:   Color(red: 1.0, green: 0.839, blue: 0.039)   // Yellow
        case .marker:     Color(red: 0.204, green: 0.78, blue: 0.349)  // Green
        case .inOutPoint: Color(red: 0.0, green: 0.478, blue: 1.0)     // Blue
        case .beatMarker: Color(red: 0.686, green: 0.322, blue: 0.871) // Purple
        case .gridLine:   Color(red: 0.557, green: 0.557, blue: 0.576) // Gray
        }
    }
}

// MARK: - SnapGuideRenderer

/// Renders vertical snap lines with glow effects during drag/trim operations.
struct SnapGuideRenderer: View, Equatable {

    /// List of active snap guides to render.
    let guides: [SnapGuide]

    /// Height of the ruler area (guides start below this).
    let rulerHeight: Double

    /// Total height of the timeline area.
    let timelineHeight: Double

    /// Whether to show glow effect.
    let showGlow: Bool

    /// Glow intensity (0.0 - 1.0).
    let glowIntensity: Double

    init(
        guides: [SnapGuide],
        rulerHeight: Double,
        timelineHeight: Double,
        showGlow: Bool = true,
        glowIntensity: Double = 0.8
    ) {
        self.guides = guides
        self.rulerHeight = rulerHeight
        self.timelineHeight = timelineHeight
        self.showGlow = showGlow
        self.glowIntensity = glowIntensity
    }

    var body: some View {
        Canvas { context, size in
            let calculations = SnapGuideCalculations(
                guides: guides,
                rulerHeight: rulerHeight,
                timelineHeight: timelineHeight,
                showGlow: showGlow,
                glowIntensity: glowIntensity
            )
            calculations.draw(into: &context, size: size)
        }
    }
}

// MARK: - SnapGuideCalculations

/// Extracted calculation and drawing logic for testability.
struct SnapGuideCalculations: Sendable {

    let guides: [SnapGuide]
    let rulerHeight: Double
    let timelineHeight: Double
    let showGlow: Bool
    let glowIntensity: Double

    // MARK: - Constants

    static let dashLength: Double = 4.0
    static let gapLength: Double = 4.0
    static let indicatorOffset: Double = 2.0
    static let playheadIndicatorSize: Double = 6.0
    static let clipEdgeIndicatorSize: Double = 5.0
    static let markerIndicatorSize: Double = 6.0
    static let inOutIndicatorSize: Double = 6.0
    static let beatIndicatorRadius: Double = 3.0

    static let lineStrokeWidth: Double = 1.5
    static let glowStrokeWidth: Double = 6.0
    static let outerGlowStrokeWidth: Double = 12.0

    // MARK: - Drawing

    func draw(into context: inout GraphicsContext, size: CGSize) {
        guard !guides.isEmpty else { return }

        for guide in guides {
            drawSnapGuide(guide: guide, viewportWidth: size.width, context: &context)
        }
    }

    private func drawSnapGuide(guide: SnapGuide, viewportWidth: Double, context: inout GraphicsContext) {
        let x = guide.x
        let color = SnapGuideColor.color(for: guide.type)

        guard x >= 0, x <= viewportWidth else { return }

        if showGlow {
            drawGlowEffect(x: x, color: color, context: &context)
        }

        drawMainLine(x: x, color: color, context: &context)
        drawSnapIndicator(x: x, type: guide.type, color: color, context: &context)
    }

    private func drawGlowEffect(x: Double, color: Color, context: inout GraphicsContext) {
        var outerPath = Path()
        outerPath.move(to: CGPoint(x: x, y: rulerHeight))
        outerPath.addLine(to: CGPoint(x: x, y: timelineHeight))
        context.stroke(
            outerPath,
            with: .color(color.opacity(0.1 * glowIntensity)),
            lineWidth: Self.outerGlowStrokeWidth
        )

        var innerPath = Path()
        innerPath.move(to: CGPoint(x: x, y: rulerHeight))
        innerPath.addLine(to: CGPoint(x: x, y: timelineHeight))
        context.stroke(
            innerPath,
            with: .color(color.opacity(0.3 * glowIntensity)),
            lineWidth: Self.glowStrokeWidth
        )
    }

    private func drawMainLine(x: Double, color: Color, context: inout GraphicsContext) {
        let dashLength = Self.dashLength
        let gapLength = Self.gapLength
        let totalLength = dashLength + gapLength

        var y = rulerHeight
        while y < timelineHeight {
            let endY = min(y + dashLength, timelineHeight)
            var dash = Path()
            dash.move(to: CGPoint(x: x, y: y))
            dash.addLine(to: CGPoint(x: x, y: endY))
            context.stroke(dash, with: .color(color), lineWidth: Self.lineStrokeWidth)
            y += totalLength
        }
    }

    private func drawSnapIndicator(x: Double, type: SnapTargetType, color: Color, context: inout GraphicsContext) {
        switch type {
        case .playhead:
            drawPlayheadIndicator(x: x, color: color, context: &context)
        case .clipEdge:
            drawClipEdgeIndicator(x: x, color: color, context: &context)
        case .marker:
            drawMarkerIndicator(x: x, color: color, context: &context)
        case .inOutPoint:
            drawInOutIndicator(x: x, color: color, context: &context)
        case .beatMarker:
            drawBeatIndicator(x: x, color: color, context: &context)
        case .gridLine:
            break
        }
    }

    private func drawPlayheadIndicator(x: Double, color: Color, context: inout GraphicsContext) {
        let size = Self.playheadIndicatorSize
        let y = rulerHeight - Self.indicatorOffset

        var path = Path()
        path.move(to: CGPoint(x: x - size / 2, y: y - size))
        path.addLine(to: CGPoint(x: x + size / 2, y: y - size))
        path.addLine(to: CGPoint(x: x, y: y))
        path.closeSubpath()

        context.fill(path, with: .color(color))
    }

    private func drawClipEdgeIndicator(x: Double, color: Color, context: inout GraphicsContext) {
        let size = Self.clipEdgeIndicatorSize
        let y = rulerHeight - size - Self.indicatorOffset

        let rect = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
        context.fill(Path(rect), with: .color(color))
    }

    private func drawMarkerIndicator(x: Double, color: Color, context: inout GraphicsContext) {
        let size = Self.markerIndicatorSize
        let y = rulerHeight - size / 2 - Self.indicatorOffset

        var path = Path()
        path.move(to: CGPoint(x: x, y: y - size / 2))
        path.addLine(to: CGPoint(x: x + size / 2, y: y))
        path.addLine(to: CGPoint(x: x, y: y + size / 2))
        path.addLine(to: CGPoint(x: x - size / 2, y: y))
        path.closeSubpath()

        context.fill(path, with: .color(color))
    }

    private func drawInOutIndicator(x: Double, color: Color, context: inout GraphicsContext) {
        let size = Self.inOutIndicatorSize
        let y = rulerHeight - size - Self.indicatorOffset

        var path = Path()
        path.move(to: CGPoint(x: x + 2, y: y))
        path.addLine(to: CGPoint(x: x - 2, y: y))
        path.addLine(to: CGPoint(x: x - 2, y: y + size))
        path.addLine(to: CGPoint(x: x + 2, y: y + size))

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
        )
    }

    private func drawBeatIndicator(x: Double, color: Color, context: inout GraphicsContext) {
        let radius = Self.beatIndicatorRadius
        let y = rulerHeight - radius - Self.indicatorOffset

        let circlePath = Path(ellipseIn: CGRect(
            x: x - radius, y: y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.fill(circlePath, with: .color(color))
    }
}
