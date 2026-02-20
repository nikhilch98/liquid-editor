// SelectionOverlayRenderer.swift
// LiquidEditor
//
// SwiftUI Canvas renderer for selection visualization.
// Renders selection highlights, marquee selection, corner indicators, and trim handles.
//

import SwiftUI

// MARK: - SelectionOverlayRenderer

/// Renders selection rectangles, marquee selection, and trim handles.
struct SelectionOverlayRenderer: View, Equatable {

    /// Selected clips to highlight.
    let selectedClips: [TimelineClip]

    /// Track information for positioning.
    let tracks: [Track]

    /// Viewport state for coordinate conversion.
    let viewport: ViewportState

    /// Current selection state (for marquee).
    let selectionState: SelectionState?

    /// Selection highlight color.
    let selectionColor: Color

    /// Marquee selection color.
    let marqueeColor: Color

    /// Corner radius for selection rectangles.
    let cornerRadius: Double

    init(
        selectedClips: [TimelineClip],
        tracks: [Track],
        viewport: ViewportState,
        selectionState: SelectionState? = nil,
        selectionColor: Color = Color(red: 0.0, green: 0.478, blue: 1.0),
        marqueeColor: Color = Color(red: 0.0, green: 0.478, blue: 1.0),
        cornerRadius: Double = 6.0
    ) {
        self.selectedClips = selectedClips
        self.tracks = tracks
        self.viewport = viewport
        self.selectionState = selectionState
        self.selectionColor = selectionColor
        self.marqueeColor = marqueeColor
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Canvas { context, size in
            let calculations = SelectionOverlayCalculations(
                selectedClips: selectedClips,
                tracks: tracks,
                viewport: viewport,
                selectionState: selectionState,
                selectionColor: selectionColor,
                marqueeColor: marqueeColor,
                cornerRadius: cornerRadius
            )
            calculations.draw(into: &context, size: size)
        }
    }
}

// MARK: - SelectionOverlayCalculations

/// Extracted calculation and drawing logic for testability.
struct SelectionOverlayCalculations: Sendable {

    let selectedClips: [TimelineClip]
    let tracks: [Track]
    let viewport: ViewportState
    let selectionState: SelectionState?
    let selectionColor: Color
    let marqueeColor: Color
    let cornerRadius: Double

    // MARK: - Constants

    static let selectionGlowAlpha: Double = 0.3
    static let cornerIndicatorLength: Double = 8.0
    static let trimHandleWidth: Double = 8.0
    static let trimHandleHeightRatio: Double = 0.5
    static let trimHandleCornerRadius: Double = 3.0
    static let gripLineSpacing: Double = 2.0
    static let gripLineHeightRatio: Double = 0.4
    static let marqueeDashLength: Double = 6.0
    static let marqueeGapLength: Double = 4.0
    static let clipPadding: Double = 4.0
    static let clipPaddingOffset: Double = 2.0

    // MARK: - Coordinate Calculations

    /// Calculate the pixel rect for a clip.
    func calculateClipRect(clip: TimelineClip, trackIndex: Int, trackHeight: Double) -> CGRect {
        let x = viewport.timeToPixelX(clip.startTime)
        let y = viewport.trackIndexToPixelY(trackIndex, trackHeight: trackHeight)
        let width = Double(clip.duration) / viewport.microsPerPixel
        let height = trackHeight - Self.clipPadding
        return CGRect(x: x, y: y + Self.clipPaddingOffset, width: width, height: height)
    }

    // MARK: - Drawing

    func draw(into context: inout GraphicsContext, size: CGSize) {
        var trackIndexMap: [String: Int] = [:]
        var trackMap: [String: Track] = [:]
        for track in tracks {
            trackIndexMap[track.id] = track.index
            trackMap[track.id] = track
        }

        for clip in selectedClips {
            guard let trackIndex = trackIndexMap[clip.trackId] else { continue }
            guard let track = trackMap[clip.trackId] else { continue }

            let clipRect = calculateClipRect(
                clip: clip, trackIndex: trackIndex, trackHeight: track.effectiveHeight
            )

            guard clipRect.maxX >= 0, clipRect.minX <= size.width else { continue }
            guard clipRect.maxY >= 0, clipRect.minY <= size.height else { continue }

            drawSelectionHighlight(rect: clipRect, context: &context)
            drawTrimHandles(rect: clipRect, context: &context)
        }

        // Marquee selection
        if let state = selectionState, state.isMarqueeSelecting {
            drawMarqueeSelection(selectionState: state, context: &context)
        }
    }

    private func drawSelectionHighlight(rect: CGRect, context: inout GraphicsContext) {
        let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

        // Glow effect
        context.stroke(
            path,
            with: .color(selectionColor.opacity(Self.selectionGlowAlpha)),
            lineWidth: 6.0
        )

        // Selection stroke
        context.stroke(
            path,
            with: .color(selectionColor),
            lineWidth: 2.0
        )

        // Corner indicators
        drawCornerIndicators(rect: rect, context: &context)
    }

    private func drawCornerIndicators(rect: CGRect, context: inout GraphicsContext) {
        let len = Self.cornerIndicatorLength
        let style = StrokeStyle(lineWidth: 2.0, lineCap: .round)

        // Top-left
        var tlV = Path(); tlV.move(to: CGPoint(x: rect.minX - 1, y: rect.minY + len)); tlV.addLine(to: CGPoint(x: rect.minX - 1, y: rect.minY - 1))
        var tlH = Path(); tlH.move(to: CGPoint(x: rect.minX - 1, y: rect.minY - 1)); tlH.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY - 1))
        context.stroke(tlV, with: .color(selectionColor), style: style)
        context.stroke(tlH, with: .color(selectionColor), style: style)

        // Top-right
        var trV = Path(); trV.move(to: CGPoint(x: rect.maxX + 1, y: rect.minY + len)); trV.addLine(to: CGPoint(x: rect.maxX + 1, y: rect.minY - 1))
        var trH = Path(); trH.move(to: CGPoint(x: rect.maxX + 1, y: rect.minY - 1)); trH.addLine(to: CGPoint(x: rect.maxX - len, y: rect.minY - 1))
        context.stroke(trV, with: .color(selectionColor), style: style)
        context.stroke(trH, with: .color(selectionColor), style: style)

        // Bottom-left
        var blV = Path(); blV.move(to: CGPoint(x: rect.minX - 1, y: rect.maxY - len)); blV.addLine(to: CGPoint(x: rect.minX - 1, y: rect.maxY + 1))
        var blH = Path(); blH.move(to: CGPoint(x: rect.minX - 1, y: rect.maxY + 1)); blH.addLine(to: CGPoint(x: rect.minX + len, y: rect.maxY + 1))
        context.stroke(blV, with: .color(selectionColor), style: style)
        context.stroke(blH, with: .color(selectionColor), style: style)

        // Bottom-right
        var brV = Path(); brV.move(to: CGPoint(x: rect.maxX + 1, y: rect.maxY - len)); brV.addLine(to: CGPoint(x: rect.maxX + 1, y: rect.maxY + 1))
        var brH = Path(); brH.move(to: CGPoint(x: rect.maxX + 1, y: rect.maxY + 1)); brH.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY + 1))
        context.stroke(brV, with: .color(selectionColor), style: style)
        context.stroke(brH, with: .color(selectionColor), style: style)
    }

    private func drawTrimHandles(rect: CGRect, context: inout GraphicsContext) {
        let handleWidth = Self.trimHandleWidth
        let handleHeight = rect.height * Self.trimHandleHeightRatio
        let handleY = rect.minY + (rect.height - handleHeight) / 2

        // Left handle
        let leftRect = CGRect(x: rect.minX - handleWidth / 2, y: handleY, width: handleWidth, height: handleHeight)
        drawSingleTrimHandle(rect: leftRect, isLeft: true, context: &context)

        // Right handle
        let rightRect = CGRect(x: rect.maxX - handleWidth / 2, y: handleY, width: handleWidth, height: handleHeight)
        drawSingleTrimHandle(rect: rightRect, isLeft: false, context: &context)
    }

    private func drawSingleTrimHandle(rect: CGRect, isLeft: Bool, context: inout GraphicsContext) {
        let handlePath = Path(roundedRect: rect, cornerRadius: Self.trimHandleCornerRadius)

        // Shadow
        let shadowRect = rect.offsetBy(dx: 0, dy: 1)
        context.fill(
            Path(roundedRect: shadowRect, cornerRadius: Self.trimHandleCornerRadius),
            with: .color(Color.black.opacity(0.25))
        )

        // Handle background with gradient
        let startColors: [Color] = isLeft
            ? [.white, Color(white: 0.878)]
            : [Color(white: 0.878), .white]
        context.fill(
            handlePath,
            with: .linearGradient(
                Gradient(colors: startColors),
                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                endPoint: CGPoint(x: rect.maxX, y: rect.midY)
            )
        )

        // Grip lines
        drawGripLines(rect: rect, context: &context)
    }

    private func drawGripLines(rect: CGRect, context: inout GraphicsContext) {
        let centerX = rect.midX
        let lineSpacing = Self.gripLineSpacing
        let lineHeight = rect.height * Self.gripLineHeightRatio
        let startY = rect.midY - lineHeight / 2

        let gripColor = Color.black.opacity(0.375)
        let style = StrokeStyle(lineWidth: 1.0, lineCap: .round)

        var line1 = Path()
        line1.move(to: CGPoint(x: centerX - lineSpacing, y: startY))
        line1.addLine(to: CGPoint(x: centerX - lineSpacing, y: startY + lineHeight))
        context.stroke(line1, with: .color(gripColor), style: style)

        var line2 = Path()
        line2.move(to: CGPoint(x: centerX + lineSpacing, y: startY))
        line2.addLine(to: CGPoint(x: centerX + lineSpacing, y: startY + lineHeight))
        context.stroke(line2, with: .color(gripColor), style: style)
    }

    private func drawMarqueeSelection(selectionState: SelectionState, context: inout GraphicsContext) {
        guard let marqueeRect = selectionState.marqueeRect else { return }

        // Semi-transparent fill
        context.fill(
            Path(marqueeRect),
            with: .color(marqueeColor.opacity(0.1))
        )

        // Dashed border
        drawDashedRect(rect: marqueeRect, context: &context)
    }

    private func drawDashedRect(rect: CGRect, context: inout GraphicsContext) {
        let dashLength = Self.marqueeDashLength
        let gapLength = Self.marqueeGapLength
        let totalLength = dashLength + gapLength
        let style = StrokeStyle(lineWidth: 1.0)

        // Horizontal lines (top and bottom)
        for y in [rect.minY, rect.maxY] {
            var x = rect.minX
            while x < rect.maxX {
                let endX = min(x + dashLength, rect.maxX)
                var dash = Path()
                dash.move(to: CGPoint(x: x, y: y))
                dash.addLine(to: CGPoint(x: endX, y: y))
                context.stroke(dash, with: .color(marqueeColor), style: style)
                x += totalLength
            }
        }

        // Vertical lines (left and right)
        for x in [rect.minX, rect.maxX] {
            var y = rect.minY
            while y < rect.maxY {
                let endY = min(y + dashLength, rect.maxY)
                var dash = Path()
                dash.move(to: CGPoint(x: x, y: y))
                dash.addLine(to: CGPoint(x: x, y: endY))
                context.stroke(dash, with: .color(marqueeColor), style: style)
                y += totalLength
            }
        }
    }
}
