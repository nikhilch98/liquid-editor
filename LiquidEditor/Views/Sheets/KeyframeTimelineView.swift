// KeyframeTimelineView.swift
// LiquidEditor
//
// Timeline visualization for keyframes with pinch-to-zoom, scrubbing,
// and keyframe selection. Uses Canvas for efficient rendering of the
// timeline track, keyframe diamonds, playhead, and time markers.

import SwiftUI

// MARK: - KeyframeTimelineView

/// Interactive timeline view that displays keyframes as diamond markers
/// on a horizontal track with a scrubbing playhead.
///
/// Features:
/// - Pinch-to-zoom for timeline precision (0.5x to 4.0x)
/// - Tap on keyframe diamonds to select
/// - Drag to scrub the playhead
/// - Premium diamond rendering with glow effects
/// - Adaptive time markers based on zoom level
struct KeyframeTimelineView: View {

    // MARK: - Properties

    /// Current playback progress (0.0-1.0).
    let progress: Double

    /// List of keyframes to display.
    let keyframes: [Keyframe]

    /// Total video duration.
    let videoDurationMicros: TimeMicros

    /// Currently selected keyframe ID.
    let selectedKeyframeId: String?

    /// Whether tapping only seeks to keyframes (vs. free seek).
    var onlySeekOnKeyframes: Bool = true

    /// Callback when the user seeks to a new position.
    var onSeek: ((Double) -> Void)?

    /// Callback when a keyframe is selected.
    var onKeyframeSelected: ((String) -> Void)?

    /// Callback when zoom level changes.
    var onZoomChanged: ((Double) -> Void)?

    // MARK: - State

    @State private var currentZoom: Double = 1.0
    @State private var baseZoom: Double = 1.0

    // MARK: - Constants

    /// Padding on left/right of the track.
    private static let trackPadding: CGFloat = 20

    /// Tap tolerance for keyframe selection (points).
    private static let keyframeTapTolerance: CGFloat = 25

    /// Minimum zoom level.
    private static let minimumZoom: Double = 0.5

    /// Maximum zoom level.
    private static let maximumZoom: Double = 4.0

    /// Zoom level snap points for haptic feedback.
    private static let zoomSnapPoints: [Double] = [0.5, 1.0, 2.0, 4.0]

    /// Threshold for triggering haptic snap feedback.
    private static let zoomSnapThreshold: Double = 0.05

    /// Multiplicative step factor for VoiceOver zoom adjustments.
    private static let zoomAccessibilityStepFactor: Double = 1.25

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let baseWidth = geometry.size.width
            let zoomedWidth = baseWidth * currentZoom

            Group {
                if currentZoom > 1.0 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        timelineCanvas(width: zoomedWidth, height: geometry.size.height, baseWidth: baseWidth)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    timelineCanvas(width: baseWidth, height: geometry.size.height, baseWidth: baseWidth)
                }
            }
            .glassEffect(cornerRadius: LiquidSpacing.cornerLarge)
            .gesture(pinchGesture)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyframe timeline")
        .accessibilityHint("Pinch to zoom. Swipe up or down on zoom control to change zoom level.")
        .accessibilityValue("\(keyframes.count) keyframes, zoom \(String(format: "%.1f", currentZoom))x")
        .accessibilityAdjustableAction { direction in
            // Expose zoom adjustment via VoiceOver swipe up/down.
            switch direction {
            case .increment:
                let newZoom = min(currentZoom * Self.zoomAccessibilityStepFactor, Self.maximumZoom)
                currentZoom = newZoom
                baseZoom = newZoom
                onZoomChanged?(newZoom)
                UISelectionFeedbackGenerator().selectionChanged()
            case .decrement:
                let newZoom = max(currentZoom / Self.zoomAccessibilityStepFactor, Self.minimumZoom)
                currentZoom = newZoom
                baseZoom = newZoom
                onZoomChanged?(newZoom)
                UISelectionFeedbackGenerator().selectionChanged()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Canvas

    private func timelineCanvas(width: CGFloat, height: CGFloat, baseWidth: CGFloat) -> some View {
        ZStack {
            // Canvas rendering layer — invisible to VoiceOver.
            Canvas { context, size in
                KeyframeTimelinePainter.paint(
                    context: &context,
                    size: size,
                    progress: progress,
                    keyframes: keyframes,
                    durationMicros: videoDurationMicros,
                    selectedKeyframeId: selectedKeyframeId,
                    zoomLevel: currentZoom
                )
            }
            .accessibilityHidden(true)

            // Invisible accessibility overlay: individual keyframe tap targets.
            keyframeAccessibilityOverlay(width: width, height: height)

            // Invisible accessibility element for scrubbing via VoiceOver.
            Color.clear
                .frame(width: width, height: height)
                .accessibilityElement()
                .accessibilityLabel("Scrub bar, progress \(Int((progress * 100).rounded()))%")
                .accessibilityHint("Swipe up or down to scrub through the clip")
                .accessibilityAddTraits(.allowsDirectInteraction)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        onSeek?(min(progress + 0.01, 1.0))
                    case .decrement:
                        onSeek?(max(progress - 0.01, 0.0))
                    @unknown default:
                        break
                    }
                }
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(dragGesture(width: width))
        .onTapGesture { location in
            handleTap(at: location, width: width)
        }
    }

    /// Invisible tappable overlay views positioned over each keyframe diamond.
    @ViewBuilder
    private func keyframeAccessibilityOverlay(width: CGFloat, height: CGFloat) -> some View {
        let trackWidth = width - Self.trackPadding * 2
        let durationMs = Double(videoDurationMicros) / 1_000.0
        let centerY = height / 2
        let tapSize: CGFloat = Self.keyframeTapTolerance * 2

        ForEach(keyframes, id: \.id) { keyframe in
            let keyframeProgress = durationMs > 0 ? keyframe.milliseconds / durationMs : 0.0
            let keyframeX = Self.trackPadding + trackWidth * keyframeProgress
            let isSelected = keyframe.id == selectedKeyframeId

            Color.clear
                .frame(width: tapSize, height: tapSize)
                .contentShape(Rectangle())
                .position(x: keyframeX, y: centerY)
                .onTapGesture {
                    let exactProgress = durationMs > 0 ? keyframe.milliseconds / durationMs : 0.0
                    onSeek?(exactProgress)
                    onKeyframeSelected?(keyframe.id)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .accessibilityLabel(keyframeAccessibilityLabel(for: keyframe))
                .accessibilityHint(isSelected ? "Selected. Double-tap to seek here." : "Double-tap to seek here.")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }

    /// Build a VoiceOver label for a keyframe using its timestamp.
    private func keyframeAccessibilityLabel(for keyframe: Keyframe) -> String {
        let secs = keyframe.seconds
        if secs < 60 {
            return String(format: "Keyframe at %.1f seconds", secs)
        } else {
            let mins = Int(secs / 60)
            let remainder = secs.truncatingRemainder(dividingBy: 60)
            return String(format: "Keyframe at %d minutes %.1f seconds", mins, remainder)
        }
    }

    // MARK: - Gestures

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newZoom = (baseZoom * value.magnification).clamped(to: Self.minimumZoom...Self.maximumZoom)

                // Trigger haptic feedback at snap points
                for snapPoint in Self.zoomSnapPoints {
                    if abs(newZoom - snapPoint) < Self.zoomSnapThreshold && abs(currentZoom - snapPoint) >= Self.zoomSnapThreshold {
                        let selection = UISelectionFeedbackGenerator()
                        selection.selectionChanged()
                    }
                }

                currentZoom = newZoom
                onZoomChanged?(newZoom)
            }
            .onEnded { value in
                baseZoom = (baseZoom * value.magnification).clamped(to: Self.minimumZoom...Self.maximumZoom)
                currentZoom = baseZoom
            }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let trackWidth = width - Self.trackPadding * 2
                let x = value.location.x - Self.trackPadding
                let newProgress = (x / trackWidth).clamped(to: 0.0...1.0)
                onSeek?(newProgress)
            }
            .onEnded { _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint, width: CGFloat) {
        let trackWidth = width - Self.trackPadding * 2
        let durationMs = Double(videoDurationMicros) / 1_000.0

        if onlySeekOnKeyframes {
            // Find nearest keyframe within tolerance
            var nearestKeyframe: Keyframe?
            var nearestDistance: CGFloat = .infinity

            for keyframe in keyframes {
                let keyframeProgress = keyframe.milliseconds / durationMs
                let keyframeX = Self.trackPadding + trackWidth * keyframeProgress
                let distance = abs(location.x - keyframeX)

                if distance < Self.keyframeTapTolerance, distance < nearestDistance {
                    nearestKeyframe = keyframe
                    nearestDistance = distance
                }
            }

            if let nearest = nearestKeyframe {
                let exactProgress = nearest.milliseconds / durationMs
                onSeek?(exactProgress)
                onKeyframeSelected?(nearest.id)
                UISelectionFeedbackGenerator().selectionChanged()
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } else {
            let tapProgress = ((location.x - Self.trackPadding) / trackWidth).clamped(to: 0.0...1.0)
            onSeek?(tapProgress)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - KeyframeTimelinePainter

/// Static rendering functions for the keyframe timeline Canvas.
///
/// Draws the track background, progress fill, time markers, keyframe diamonds,
/// and playhead with glow effects. All rendering is contained in static methods
/// for testability and separation from the SwiftUI view layer.
enum KeyframeTimelinePainter {

    /// Track padding on each side.
    static let trackPadding: CGFloat = 20

    // Track geometry constants
    static let trackBarHalfHeight: CGFloat = 3
    static let trackBarHeight: CGFloat = 6
    static let trackBarCornerRadius: CGFloat = 3

    // Track background color components
    static let trackBackgroundRed: Double = 0.1
    static let trackBackgroundGreen: Double = 0.1
    static let trackBackgroundBlue: Double = 0.13

    // Progress fill opacities
    static let progressFillStartOpacity: Double = 0.6
    static let progressFillEndOpacity: Double = 0.3

    // Diamond clipping margin (diamond size + glow margin)
    static let diamondClipMargin: CGFloat = 20

    // Diamond sizes
    static let diamondBaseSize: CGFloat = 11
    static let diamondOuterGlowOffset: CGFloat = 4
    static let diamondInnerGlowOffset: CGFloat = 2
    static let diamondFillOffset: CGFloat = 1

    // Diamond glow opacities
    static let diamondOuterGlowOpacity: Double = 0.25
    static let diamondInnerGlowSelectedOpacity: Double = 0.35
    static let diamondInnerGlowNormalOpacity: Double = 0.2
    static let diamondSelectionStrokeOpacity: Double = 0.7
    static let diamondSelectionStrokeWidth: CGFloat = 2

    // Diamond gradient colors (gold tones)
    static let diamondGradientTopRed: Double = 1.0
    static let diamondGradientTopGreen: Double = 0.84
    static let diamondGradientTopBlue: Double = 0.0
    static let diamondGradientBottomRed: Double = 1.0
    static let diamondGradientBottomGreen: Double = 0.58
    static let diamondGradientBottomBlue: Double = 0.0

    // Playhead geometry
    static let playheadInset: CGFloat = 10
    static let playheadLineInset: CGFloat = 14
    static let playheadHandleRadius: CGFloat = 6
    static let playheadHandleSize: CGFloat = 12
    static let playheadGlowWidth: CGFloat = 6
    static let playheadGlowOpacity: Double = 0.15
    static let playheadHandleBorderOpacity: Double = 0.5
    static let playheadLineWidth: CGFloat = 2

    // Time marker geometry
    static let majorTickHeight: CGFloat = 8.0
    static let minorTickHeight: CGFloat = 4.0
    static let tickCenterOffset: CGFloat = 10
    static let tickLabelOffset: CGFloat = 8
    static let majorTickOpacity: Double = 0.4
    static let minorTickOpacity: Double = 0.2
    static let majorTickLineWidth: CGFloat = 1
    static let minorTickLineWidth: CGFloat = 0.5
    static let tickLabelFontSize: CGFloat = 9
    static let tickLabelOpacity: Double = 0.7

    // Tick interval pixel density thresholds (pixels per second)
    static let tickDensityThresholdVeryHigh: Double = 200
    static let tickDensityThresholdHigh: Double = 100
    static let tickDensityThresholdMed: Double = 50
    static let tickDensityThresholdLow: Double = 25
    static let tickDensityThresholdVeryLow: Double = 10

    // Tick interval values in milliseconds
    static let tickInterval100ms: Int = 100
    static let tickInterval500ms: Int = 500
    static let tickInterval1s: Int = 1000
    static let tickInterval2s: Int = 2000
    static let tickInterval5s: Int = 5000
    static let tickInterval10s: Int = 10000

    // Visible canvas margin for off-screen culling
    static let visibleCanvasMargin: CGFloat = 2

    /// Paint the complete timeline.
    static func paint(
        context: inout GraphicsContext,
        size: CGSize,
        progress: Double,
        keyframes: [Keyframe],
        durationMicros: TimeMicros,
        selectedKeyframeId: String?,
        zoomLevel: Double
    ) {
        let trackWidth = size.width - trackPadding * 2
        let centerY = size.height / 2

        // Track background
        let trackRect = CGRect(x: trackPadding, y: centerY - trackBarHalfHeight, width: trackWidth, height: trackBarHeight)
        let trackPath = Path(roundedRect: trackRect, cornerRadius: trackBarCornerRadius)
        context.fill(trackPath, with: .color(Color(red: trackBackgroundRed, green: trackBackgroundGreen, blue: trackBackgroundBlue)))

        // Time markers
        drawTimeMarkers(
            context: context,
            size: size,
            padding: trackPadding,
            trackWidth: trackWidth,
            centerY: centerY,
            durationMicros: durationMicros
        )

        // Progress fill
        let progressWidth = trackWidth * progress
        if progressWidth > 0 {
            let progressRect = CGRect(x: trackPadding, y: centerY - trackBarHalfHeight, width: progressWidth, height: trackBarHeight)
            let progressPath = Path(roundedRect: progressRect, cornerRadius: trackBarCornerRadius)
            context.fill(
                progressPath,
                with: .linearGradient(
                    Gradient(colors: [Color.blue.opacity(progressFillStartOpacity), Color.blue.opacity(progressFillEndOpacity)]),
                    startPoint: CGPoint(x: 0, y: 0.5),
                    endPoint: CGPoint(x: 1, y: 0.5)
                )
            )
        }

        // Keyframe diamonds — skip keyframes outside the visible canvas bounds.
        let durationMs = Double(durationMicros) / 1_000.0
        if durationMs > 0 {
            for keyframe in keyframes {
                let keyframeProgress = keyframe.milliseconds / durationMs
                let x = trackPadding + trackWidth * keyframeProgress
                // Early-exit: skip keyframes entirely outside the visible canvas width.
                guard x >= -diamondClipMargin && x <= size.width + diamondClipMargin else { continue }
                let isSelected = keyframe.id == selectedKeyframeId
                drawDiamond(context: &context, center: CGPoint(x: x, y: centerY), isSelected: isSelected)
            }
        }

        // Playhead
        let playheadX = trackPadding + trackWidth * progress
        drawPlayhead(context: context, x: playheadX, height: size.height)
    }

    /// Draw adaptive time markers based on pixel density.
    static func drawTimeMarkers(
        context: GraphicsContext,
        size: CGSize,
        padding: CGFloat,
        trackWidth: CGFloat,
        centerY: CGFloat,
        durationMicros: TimeMicros
    ) {
        let durationMs = Double(durationMicros) / 1_000.0
        guard durationMs > 0 else { return }

        let pixelsPerSecond = trackWidth / (durationMs / 1_000.0)

        let tickIntervalMs: Int
        if pixelsPerSecond > tickDensityThresholdVeryHigh {
            tickIntervalMs = tickInterval100ms
        } else if pixelsPerSecond > tickDensityThresholdHigh {
            tickIntervalMs = tickInterval500ms
        } else if pixelsPerSecond > tickDensityThresholdMed {
            tickIntervalMs = tickInterval1s
        } else if pixelsPerSecond > tickDensityThresholdLow {
            tickIntervalMs = tickInterval2s
        } else if pixelsPerSecond > tickDensityThresholdVeryLow {
            tickIntervalMs = tickInterval5s
        } else {
            tickIntervalMs = tickInterval10s
        }

        // Pre-compute visible x bounds to skip off-screen markers.
        let visibleMinX: CGFloat = -visibleCanvasMargin
        let visibleMaxX: CGFloat = size.width + visibleCanvasMargin

        var ms = 0
        while ms <= Int(durationMs) {
            let tickProgress = Double(ms) / durationMs
            let x = padding + trackWidth * tickProgress

            // Early-exit: skip markers entirely outside the visible canvas.
            if x > visibleMaxX { break }
            if x < visibleMinX {
                ms += tickIntervalMs
                continue
            }

            let isMajorTick = ms % tickInterval1s == 0
            let tickHeight: CGFloat = isMajorTick ? majorTickHeight : minorTickHeight

            // Tick line
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: centerY - tickCenterOffset - tickHeight))
            tickPath.addLine(to: CGPoint(x: x, y: centerY - tickCenterOffset))
            context.stroke(
                tickPath,
                with: .color(Color.secondary.opacity(isMajorTick ? majorTickOpacity : minorTickOpacity)),
                lineWidth: isMajorTick ? majorTickLineWidth : minorTickLineWidth
            )

            // Time label for major ticks
            if isMajorTick, ms % (tickIntervalMs * 2) == 0 || tickIntervalMs >= tickInterval1s {
                let totalSeconds = ms / tickInterval1s
                let minutes = totalSeconds / 60
                let secs = totalSeconds % 60
                let label = "\(minutes):\(String(format: "%02d", secs))"

                let text = Text(label)
                    .font(.system(size: tickLabelFontSize, weight: .medium))
                    .foregroundColor(.secondary.opacity(tickLabelOpacity))
                let resolved = context.resolve(text)
                context.draw(
                    resolved,
                    at: CGPoint(x: x, y: centerY - tickCenterOffset - tickHeight - tickLabelOffset),
                    anchor: .center
                )
            }

            ms += tickIntervalMs
        }
    }

    /// Draw a diamond keyframe marker with lightweight glow (no blur filter).
    static func drawDiamond(
        context: inout GraphicsContext,
        center: CGPoint,
        isSelected: Bool
    ) {
        let size: CGFloat = diamondBaseSize

        // Lightweight glow: larger, semi-transparent diamond behind the main one (no GPU blur).
        if isSelected {
            let outerGlowPath = diamondPath(center: center, size: size + diamondOuterGlowOffset)
            context.fill(outerGlowPath, with: .color(Color.orange.opacity(diamondOuterGlowOpacity)))
        }
        let glowPath = diamondPath(center: center, size: size + diamondInnerGlowOffset)
        context.fill(glowPath, with: .color(Color.orange.opacity(isSelected ? diamondInnerGlowSelectedOpacity : diamondInnerGlowNormalOpacity)))

        // Diamond fill with gradient
        let fillPath = diamondPath(center: center, size: size - diamondFillOffset)
        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: diamondGradientTopRed, green: diamondGradientTopGreen, blue: diamondGradientTopBlue),
                    Color(red: diamondGradientBottomRed, green: diamondGradientBottomGreen, blue: diamondGradientBottomBlue)
                ]),
                startPoint: CGPoint(x: center.x, y: center.y - size),
                endPoint: CGPoint(x: center.x, y: center.y + size)
            )
        )

        // Selection highlight
        if isSelected {
            context.stroke(
                fillPath,
                with: .color(.white.opacity(diamondSelectionStrokeOpacity)),
                lineWidth: diamondSelectionStrokeWidth
            )
        }
    }

    /// Draw the playhead line with lightweight glow and handles.
    static func drawPlayhead(context: GraphicsContext, x: CGFloat, height: CGFloat) {
        // Lightweight glow line (wider semi-transparent stroke, no blur filter).
        var glowPath = Path()
        glowPath.move(to: CGPoint(x: x, y: playheadInset))
        glowPath.addLine(to: CGPoint(x: x, y: height - playheadInset))
        context.stroke(
            glowPath,
            with: .color(.white.opacity(playheadGlowOpacity)),
            lineWidth: playheadGlowWidth
        )

        // Main line
        var linePath = Path()
        linePath.move(to: CGPoint(x: x, y: playheadLineInset))
        linePath.addLine(to: CGPoint(x: x, y: height - playheadLineInset))
        context.stroke(
            linePath,
            with: .color(.white),
            style: StrokeStyle(lineWidth: playheadLineWidth, lineCap: .round)
        )

        // Top handle
        let topCenter = CGPoint(x: x, y: playheadInset)
        let topCircle = Path(ellipseIn: CGRect(x: topCenter.x - playheadHandleRadius, y: topCenter.y - playheadHandleRadius, width: playheadHandleSize, height: playheadHandleSize))
        context.fill(topCircle, with: .color(.white))
        context.stroke(topCircle, with: .color(.white.opacity(playheadHandleBorderOpacity)), lineWidth: 1)

        // Bottom handle
        let bottomCenter = CGPoint(x: x, y: height - playheadInset)
        let bottomCircle = Path(ellipseIn: CGRect(x: bottomCenter.x - playheadHandleRadius, y: bottomCenter.y - playheadHandleRadius, width: playheadHandleSize, height: playheadHandleSize))
        context.fill(bottomCircle, with: .color(.white))
        context.stroke(bottomCircle, with: .color(.white.opacity(playheadHandleBorderOpacity)), lineWidth: 1)
    }

    /// Create a diamond-shaped path centered at a point.
    static func diamondPath(center: CGPoint, size: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: center.x, y: center.y - size))
            path.addLine(to: CGPoint(x: center.x + size, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + size))
            path.addLine(to: CGPoint(x: center.x - size, y: center.y))
            path.closeSubpath()
        }
    }
}

// MARK: - Comparable Clamping

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
