// TrackLanesRenderer.swift
// LiquidEditor
//
// SwiftUI Canvas renderer for track backgrounds and separators.
// Renders alternating backgrounds, lock overlays, mute overlays, and collapse indicators.
//

import SwiftUI

// MARK: - TrackLanesRenderer

/// Renders alternating track backgrounds, separators, lock/mute/collapse overlays.
struct TrackLanesRenderer: View, Equatable {

    /// List of tracks to render.
    let tracks: [Track]

    /// Viewport state for positioning.
    let viewport: ViewportState

    /// Primary background color (even tracks).
    let primaryBackgroundColor: Color

    /// Secondary background color (odd tracks).
    let secondaryBackgroundColor: Color

    /// Separator line color.
    let separatorColor: Color

    /// Whether to show track separators.
    let showSeparators: Bool

    /// Whether to show locked track overlay.
    let showLockedOverlay: Bool

    init(
        tracks: [Track],
        viewport: ViewportState,
        primaryBackgroundColor: Color = Color(red: 0.11, green: 0.11, blue: 0.118),
        secondaryBackgroundColor: Color = Color(red: 0.173, green: 0.173, blue: 0.18),
        separatorColor: Color = Color(red: 0.227, green: 0.227, blue: 0.235),
        showSeparators: Bool = true,
        showLockedOverlay: Bool = true
    ) {
        self.tracks = tracks
        self.viewport = viewport
        self.primaryBackgroundColor = primaryBackgroundColor
        self.secondaryBackgroundColor = secondaryBackgroundColor
        self.separatorColor = separatorColor
        self.showSeparators = showSeparators
        self.showLockedOverlay = showLockedOverlay
    }

    var body: some View {
        Canvas { context, size in
            let calculations = TrackLanesCalculations(
                tracks: tracks,
                viewport: viewport,
                primaryBackgroundColor: primaryBackgroundColor,
                secondaryBackgroundColor: secondaryBackgroundColor,
                separatorColor: separatorColor,
                showSeparators: showSeparators,
                showLockedOverlay: showLockedOverlay
            )
            calculations.draw(into: &context, size: size)
        }
    }
}

// MARK: - TrackLanesCalculations

/// Extracted calculation and drawing logic for testability.
struct TrackLanesCalculations: Sendable {

    let tracks: [Track]
    let viewport: ViewportState
    let primaryBackgroundColor: Color
    let secondaryBackgroundColor: Color
    let separatorColor: Color
    let showSeparators: Bool
    let showLockedOverlay: Bool

    // MARK: - Constants

    static let trackIndicatorWidth: Double = 3.0
    static let lockedStripeWidth: Double = 8.0
    static let lockedStripeGap: Double = 16.0
    static let lockIconSize: Double = 12.0
    static let lockIconOffset: Double = 8.0
    static let rulerShadowHeight: Double = 4.0
    static let collapseArrowSize: Double = 12.0

    // MARK: - Calculations

    /// Calculate Y position for a track at the given index.
    func trackY(at index: Int) -> Double {
        var y = viewport.rulerHeight - viewport.verticalOffset
        for i in 0..<index {
            guard i < tracks.count else { break }
            y += tracks[i].effectiveHeight
        }
        return y
    }

    // MARK: - Drawing

    func draw(into context: inout GraphicsContext, size: CGSize) {
        guard !tracks.isEmpty else { return }

        var currentY = viewport.rulerHeight - viewport.verticalOffset

        for i in 0..<tracks.count {
            let track = tracks[i]
            let trackHeight = track.effectiveHeight

            // Skip if above viewport
            if currentY + trackHeight < 0 {
                currentY += trackHeight
                continue
            }

            // Stop if below viewport
            if currentY > size.height { break }

            drawTrackBackground(track: track, index: i, y: currentY, width: size.width, context: &context)

            if showSeparators && i < tracks.count - 1 {
                drawSeparator(y: currentY + trackHeight, width: size.width, context: &context)
            }

            currentY += trackHeight
        }

        drawRulerShadow(width: size.width, context: &context)
    }

    private func drawTrackBackground(
        track: Track, index: Int, y: Double, width: Double, context: inout GraphicsContext
    ) {
        let trackHeight = track.effectiveHeight
        let bgColor = index.isMultiple(of: 2) ? primaryBackgroundColor : secondaryBackgroundColor

        let rect = CGRect(x: 0, y: y, width: width, height: trackHeight)

        // Background
        let effectiveColor = track.isVisible ? bgColor : bgColor.opacity(0.5)
        context.fill(Path(rect), with: .color(effectiveColor))

        // Track type color indicator on left edge
        let indicatorColor = Color(argb32: UInt32(bitPattern: Int32(truncatingIfNeeded: track.colorARGB32)))
        context.fill(
            Path(CGRect(x: 0, y: y, width: Self.trackIndicatorWidth, height: trackHeight)),
            with: .color(indicatorColor.opacity(0.3))
        )

        // Locked overlay
        if showLockedOverlay && track.isLocked {
            drawLockedPattern(rect: rect, context: &context)
        }

        // Muted overlay
        if track.isMuted && !track.isSolo {
            context.fill(Path(rect), with: .color(Color.black.opacity(0.125)))
        }

        // Collapsed indicator
        if track.isCollapsed {
            drawCollapsedIndicator(y: y, width: width, height: trackHeight, context: &context)
        }
    }

    private func drawLockedPattern(rect: CGRect, context: inout GraphicsContext) {
        context.clipToLayer(opacity: 1.0) { layerContext in
            let stripeWidth = Self.lockedStripeWidth
            let stripeGap = Self.lockedStripeGap
            let patternWidth = stripeWidth + stripeGap

            let startX = rect.minX - rect.height
            var x = startX
            while x < rect.maxX + rect.height {
                var stripePath = Path()
                stripePath.move(to: CGPoint(x: x, y: rect.maxY))
                stripePath.addLine(to: CGPoint(x: x + stripeWidth, y: rect.maxY))
                stripePath.addLine(to: CGPoint(x: x + rect.height + stripeWidth, y: rect.minY))
                stripePath.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                stripePath.closeSubpath()

                layerContext.fill(stripePath, with: .color(Color.white.opacity(0.063)))
                x += patternWidth
            }
        }

        // Lock icon
        let iconSize = Self.lockIconSize
        let iconX = rect.maxX - iconSize - Self.lockIconOffset
        let iconY = rect.midY - iconSize / 2
        let lockColor = Color.white.opacity(0.25)
        let lockStyle = StrokeStyle(lineWidth: 1.5)

        // Lock body
        context.stroke(
            Path(roundedRect: CGRect(x: iconX, y: iconY + 4, width: iconSize, height: iconSize - 4), cornerRadius: 2),
            with: .color(lockColor),
            style: lockStyle
        )

        // Lock shackle (arc)
        var shacklePath = Path()
        shacklePath.addArc(
            center: CGPoint(x: iconX + iconSize / 2, y: iconY + 4),
            radius: (iconSize - 4) / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        context.stroke(shacklePath, with: .color(lockColor), style: lockStyle)
    }

    private func drawCollapsedIndicator(y: Double, width: Double, height: Double, context: inout GraphicsContext) {
        let iconSize = Self.collapseArrowSize
        let iconX = width - iconSize - Self.lockIconOffset
        let iconY = y + (height - iconSize) / 2

        var arrowPath = Path()
        arrowPath.move(to: CGPoint(x: iconX, y: iconY + iconSize / 3))
        arrowPath.addLine(to: CGPoint(x: iconX + iconSize / 2, y: iconY + iconSize * 2 / 3))
        arrowPath.addLine(to: CGPoint(x: iconX + iconSize, y: iconY + iconSize / 3))

        context.stroke(
            arrowPath,
            with: .color(Color.white.opacity(0.375)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSeparator(y: Double, width: Double, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: width, y: y))
        context.stroke(path, with: .color(separatorColor), lineWidth: 1.0)
    }

    private func drawRulerShadow(width: Double, context: inout GraphicsContext) {
        let shadowY = viewport.rulerHeight - viewport.verticalOffset
        let shadowRect = CGRect(x: 0, y: shadowY, width: width, height: Self.rulerShadowHeight)

        context.fill(
            Path(shadowRect),
            with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.0)]),
                startPoint: CGPoint(x: 0, y: shadowRect.minY),
                endPoint: CGPoint(x: 0, y: shadowRect.maxY)
            )
        )
    }
}
