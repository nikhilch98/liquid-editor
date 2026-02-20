// ClipsRenderer.swift
// LiquidEditor
//
// SwiftUI Canvas renderer for timeline clips.
// Renders clips as rounded rectangles with labels, badges, and indicators.
//

import SwiftUI

// MARK: - ClipsRenderer

/// Renders timeline clips as rounded rectangles with labels, badges, and indicators.
///
/// Uses SwiftUI `Canvas` for high-performance drawing. Each clip is drawn with:
/// - Background fill with gradient overlay for depth
/// - Optional clip label
/// - Effect badges (FX count)
/// - Speed indicators (slow/fast)
/// - Reverse arrow indicator
/// - Offline overlay (missing media)
/// - Selection highlight with trim handles
struct ClipsRenderer: View, Equatable {

    /// Clips to render.
    let clips: [TimelineClip]

    /// Track information for positioning.
    let tracks: [Track]

    /// Set of selected clip IDs.
    let selectedClipIds: Set<String>

    /// Viewport state for coordinate conversion.
    let viewport: ViewportState

    /// Whether to show trim handles on selected clips.
    let showTrimHandles: Bool

    /// Clip corner radius.
    let cornerRadius: Double

    init(
        clips: [TimelineClip],
        tracks: [Track],
        selectedClipIds: Set<String>,
        viewport: ViewportState,
        showTrimHandles: Bool = true,
        cornerRadius: Double = 6.0
    ) {
        self.clips = clips
        self.tracks = tracks
        self.selectedClipIds = selectedClipIds
        self.viewport = viewport
        self.showTrimHandles = showTrimHandles
        self.cornerRadius = cornerRadius
    }

    // MARK: - Accessibility Helpers

    /// Map from track ID to (index, Track) for fast lookup in accessibility overlay.
    private var accessibilityTrackIndexMap: [String: (index: Int, track: Track)] {
        var map: [String: (Int, Track)] = [:]
        for track in tracks {
            map[track.id] = (track.index, track)
        }
        return map
    }

    /// Clips visible in the current viewport for accessibility overlay.
    private var visibleClips: [TimelineClip] {
        clips.filter { viewport.isTimeRangeVisible($0.timeRange) }
    }

    var body: some View {
        ZStack {
            // Canvas rendering layer — invisible to VoiceOver.
            Canvas { context, size in
                let calculations = ClipsRenderCalculations(
                    clips: clips,
                    tracks: tracks,
                    selectedClipIds: selectedClipIds,
                    viewport: viewport,
                    showTrimHandles: showTrimHandles,
                    cornerRadius: cornerRadius
                )
                calculations.draw(into: &context, size: size)
            }
            .accessibilityHidden(true)

            // Invisible accessibility overlay for each visible clip.
            // Provides VoiceOver with clip name, type, duration, and selection state.
            accessibilityOverlay
        }
        .accessibilityElement(children: .contain)
    }

    /// Invisible overlay views positioned over each visible clip for VoiceOver.
    @ViewBuilder
    private var accessibilityOverlay: some View {
        let renderCalc = ClipsRenderCalculations(
            clips: clips,
            tracks: tracks,
            selectedClipIds: selectedClipIds,
            viewport: viewport,
            showTrimHandles: showTrimHandles,
            cornerRadius: cornerRadius
        )
        let trackMap = accessibilityTrackIndexMap

        ForEach(visibleClips, id: \.id) { clip in
            if let trackInfo = trackMap[clip.trackId] {
                let rect = renderCalc.calculateClipRect(
                    clip: clip,
                    trackIndex: trackInfo.index,
                    trackHeight: trackInfo.track.effectiveHeight
                )
                let durationSeconds = Double(clip.duration) / 1_000_000.0
                let isSelected = selectedClipIds.contains(clip.id)

                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityLabel(for: clip, durationSeconds: durationSeconds))
                    .accessibilityHint(isSelected ? "Selected. Double-tap to deselect." : "Double-tap to select.")
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// Build a VoiceOver label for a clip describing its type, name, and duration.
    private func accessibilityLabel(for clip: TimelineClip, durationSeconds: Double) -> String {
        let typeName: String
        switch clip.type {
        case .video: typeName = "Video clip"
        case .audio: typeName = "Audio clip"
        case .image: typeName = "Image clip"
        case .text: typeName = "Text clip"
        case .effect: typeName = "Effect clip"
        case .gap: typeName = "Gap"
        case .color: typeName = "Color clip"
        }

        let name = clip.label ?? clip.id
        let durationStr: String
        if durationSeconds < 60 {
            durationStr = String(format: "%.1f seconds", durationSeconds)
        } else {
            let mins = Int(durationSeconds / 60)
            let secs = durationSeconds.truncatingRemainder(dividingBy: 60)
            durationStr = String(format: "%d minutes %.1f seconds", mins, secs)
        }

        var label = "\(typeName) \(name), duration \(durationStr)"
        if clip.isOffline { label += ", offline" }
        if clip.speed != 1.0 { label += ", speed \(ClipsRenderCalculations.speedText(for: clip.speed))" }
        if clip.isReversed { label += ", reversed" }
        return label
    }
}

// MARK: - ClipsRenderCalculations

/// Extracted calculation and drawing logic for testability.
struct ClipsRenderCalculations: Sendable {

    let clips: [TimelineClip]
    let tracks: [Track]
    let selectedClipIds: Set<String>
    let viewport: ViewportState
    let showTrimHandles: Bool
    let cornerRadius: Double

    // MARK: - Constants

    static let minWidthForLabel: Double = 30.0
    static let minWidthForSpeedIndicator: Double = 40.0
    static let minWidthForEffectBadge: Double = 50.0
    static let minWidthForReverseIndicator: Double = 30.0

    static let clipPadding: Double = 4.0
    static let clipPaddingOffset: Double = 2.0
    static let trimHandleWidth: Double = 6.0
    static let trimHandleHeightRatio: Double = 0.6
    static let badgeHeight: Double = 14.0
    static let iconSizeSmall: Double = 12.0
    static let iconSizeLarge: Double = 20.0
    static let effectBadgeTopOffset: Double = 4.0
    static let speedBadgeTopOffsetWithEffect: Double = 22.0

    // MARK: - Coordinate Calculations

    /// Calculate the pixel rect for a clip given its track.
    func calculateClipRect(clip: TimelineClip, trackIndex: Int, trackHeight: Double) -> CGRect {
        let x = viewport.timeToPixelX(clip.startTime)
        let y = viewport.trackIndexToPixelY(trackIndex, trackHeight: trackHeight)
        let width = Double(clip.duration) / viewport.microsPerPixel
        let height = trackHeight - Self.clipPadding

        return CGRect(x: x, y: y + Self.clipPaddingOffset, width: width, height: height)
    }

    /// Format speed text for a clip.
    static func speedText(for speed: Double) -> String {
        if speed < 1 {
            return "\(Int((speed * 100).rounded()))%"
        } else if speed == speed.rounded() {
            return "\(Int(speed))x"
        } else {
            return String(format: "%.1fx", speed)
        }
    }

    /// Color for a speed indicator.
    static func speedColor(for speed: Double) -> Color {
        speed > 1 ? Color(red: 1.0, green: 0.584, blue: 0.0) : Color(red: 0.204, green: 0.78, blue: 0.349)
    }

    // MARK: - Drawing

    func draw(into context: inout GraphicsContext, size: CGSize) {
        // Build track index map for fast lookup
        var trackIndexMap: [String: Int] = [:]
        var trackMap: [String: Track] = [:]
        for track in tracks {
            trackIndexMap[track.id] = track.index
            trackMap[track.id] = track
        }

        for clip in clips {
            // Skip if not in visible time range
            guard viewport.isTimeRangeVisible(clip.timeRange) else { continue }
            guard let trackIndex = trackIndexMap[clip.trackId] else { continue }
            guard let track = trackMap[clip.trackId] else { continue }

            let clipRect = calculateClipRect(
                clip: clip, trackIndex: trackIndex, trackHeight: track.effectiveHeight
            )
            guard clipRect.width >= 1 else { continue }

            drawClip(clip: clip, rect: clipRect, context: &context)
        }
    }

    private func drawClip(clip: TimelineClip, rect: CGRect, context: inout GraphicsContext) {
        let isSelected = selectedClipIds.contains(clip.id)
        let roundedRect = RoundedRectangle(cornerRadius: cornerRadius)
        let clipPath = Path(roundedRect: rect, cornerRadius: cornerRadius)
        let clipColor = Color(argb32: clip.clipColorValue)

        // Clip background fill
        context.fill(clipPath, with: .color(clipColor))

        // Gradient overlay for depth
        let gradientRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let gradient = Gradient(stops: [
            .init(color: Color.white.opacity(0.125), location: 0.0),
            .init(color: Color.white.opacity(0.0), location: 0.3),
            .init(color: Color.black.opacity(0.063), location: 1.0),
        ])
        context.fill(
            Path(roundedRect: gradientRect, cornerRadius: cornerRadius),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: gradientRect.midX, y: gradientRect.minY),
                endPoint: CGPoint(x: gradientRect.midX, y: gradientRect.maxY)
            )
        )

        // Offline overlay
        if clip.isOffline {
            context.fill(
                clipPath,
                with: .color(Color(red: 1.0, green: 0.231, blue: 0.188).opacity(0.5))
            )
            drawOfflineIcon(rect: rect, context: &context)
        }

        // Border
        context.stroke(
            clipPath,
            with: .color(clipColor.opacity(0.3)),
            lineWidth: 1.0
        )

        // Label
        if let label = clip.label, rect.width > Self.minWidthForLabel {
            drawLabel(label, in: rect, context: &context)
        }

        // Effect badge
        if clip.hasEffects, rect.width > Self.minWidthForEffectBadge {
            drawEffectBadge(clip: clip, rect: rect, context: &context)
        }

        // Speed indicator
        if clip.speed != 1.0, rect.width > Self.minWidthForSpeedIndicator {
            drawSpeedIndicator(clip: clip, rect: rect, context: &context)
        }

        // Reverse indicator
        if clip.isReversed, rect.width > Self.minWidthForReverseIndicator {
            drawReverseIndicator(rect: rect, context: &context)
        }

        // Selection highlight
        if isSelected {
            context.stroke(
                clipPath,
                with: .color(Color(red: 0.0, green: 0.478, blue: 1.0)),
                lineWidth: 2.0
            )
            if showTrimHandles {
                drawTrimHandles(rect: rect, context: &context)
            }
        }
    }

    private func drawLabel(_ label: String, in rect: CGRect, context: inout GraphicsContext) {
        let text = Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)

        let resolvedText = context.resolve(text)
        let textSize = resolvedText.measure(in: CGSize(width: rect.width - 16, height: rect.height))

        let origin = CGPoint(
            x: rect.minX + 8,
            y: rect.minY + (rect.height - textSize.height) / 2
        )

        context.draw(resolvedText, in: CGRect(origin: origin, size: textSize))
    }

    private func drawEffectBadge(clip: TimelineClip, rect: CGRect, context: inout GraphicsContext) {
        let badgeText = clip.effectCount > 1 ? "FX x\(clip.effectCount)" : "FX"
        let text = Text(badgeText)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)

        let resolvedText = context.resolve(text)
        let textSize = resolvedText.measure(in: CGSize(width: 100, height: Self.badgeHeight))
        let badgeWidth = textSize.width + 8

        let badgeRect = CGRect(
            x: rect.maxX - badgeWidth - Self.effectBadgeTopOffset,
            y: rect.minY + Self.effectBadgeTopOffset,
            width: badgeWidth,
            height: Self.badgeHeight
        )

        context.fill(
            Path(roundedRect: badgeRect, cornerRadius: 3),
            with: .color(Color(red: 0.0, green: 0.478, blue: 1.0))
        )

        context.draw(
            resolvedText,
            in: CGRect(
                x: badgeRect.minX + 4,
                y: badgeRect.minY + 1,
                width: textSize.width,
                height: textSize.height
            )
        )
    }

    private func drawSpeedIndicator(clip: TimelineClip, rect: CGRect, context: inout GraphicsContext) {
        let speedStr = Self.speedText(for: clip.speed)
        let text = Text(speedStr)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)

        let resolvedText = context.resolve(text)
        let textSize = resolvedText.measure(in: CGSize(width: 100, height: Self.badgeHeight))
        let indicatorWidth = textSize.width + 8

        let topOffset = clip.hasEffects ? Self.speedBadgeTopOffsetWithEffect : Self.effectBadgeTopOffset

        let indicatorRect = CGRect(
            x: rect.maxX - indicatorWidth - Self.effectBadgeTopOffset,
            y: rect.minY + topOffset,
            width: indicatorWidth,
            height: Self.badgeHeight
        )

        context.fill(
            Path(roundedRect: indicatorRect, cornerRadius: 3),
            with: .color(Self.speedColor(for: clip.speed))
        )

        context.draw(
            resolvedText,
            in: CGRect(
                x: indicatorRect.minX + 4,
                y: indicatorRect.minY + 1,
                width: textSize.width,
                height: textSize.height
            )
        )
    }

    private func drawReverseIndicator(rect: CGRect, context: inout GraphicsContext) {
        let iconSize = Self.iconSizeSmall
        let iconX = rect.minX + Self.effectBadgeTopOffset
        let iconY = rect.maxY - iconSize - Self.effectBadgeTopOffset

        var path = Path()
        path.move(to: CGPoint(x: iconX + iconSize, y: iconY + iconSize / 2))
        path.addLine(to: CGPoint(x: iconX + 4, y: iconY + iconSize / 2))
        path.addLine(to: CGPoint(x: iconX + 6, y: iconY + 2))
        path.move(to: CGPoint(x: iconX + 4, y: iconY + iconSize / 2))
        path.addLine(to: CGPoint(x: iconX + 6, y: iconY + iconSize - 2))

        context.stroke(
            path,
            with: .color(Color.white.opacity(0.8)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
        )
    }

    private func drawOfflineIcon(rect: CGRect, context: inout GraphicsContext) {
        let iconSize = Self.iconSizeLarge
        let centerX = rect.midX
        let centerY = rect.midY

        var path = Path()
        path.move(to: CGPoint(x: centerX - iconSize / 2, y: centerY - iconSize / 2))
        path.addLine(to: CGPoint(x: centerX + iconSize / 2, y: centerY + iconSize / 2))
        path.move(to: CGPoint(x: centerX + iconSize / 2, y: centerY - iconSize / 2))
        path.addLine(to: CGPoint(x: centerX - iconSize / 2, y: centerY + iconSize / 2))

        context.stroke(
            path,
            with: .color(.white),
            style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
        )
    }

    private func drawTrimHandles(rect: CGRect, context: inout GraphicsContext) {
        let handleWidth = Self.trimHandleWidth
        let handleHeight = rect.height * Self.trimHandleHeightRatio
        let handleY = rect.minY + (rect.height - handleHeight) / 2

        // Left handle
        let leftRect = CGRect(
            x: rect.minX - handleWidth / 2,
            y: handleY,
            width: handleWidth,
            height: handleHeight
        )
        context.fill(
            Path(roundedRect: leftRect, cornerRadius: 2),
            with: .color(.white)
        )

        // Right handle
        let rightRect = CGRect(
            x: rect.maxX - handleWidth / 2,
            y: handleY,
            width: handleWidth,
            height: handleHeight
        )
        context.fill(
            Path(roundedRect: rightRect, cornerRadius: 2),
            with: .color(.white)
        )
    }
}

// MARK: - Color Extension

extension Color {
    /// Create a SwiftUI Color from a UInt32 ARGB value.
    init(argb32 value: UInt32) {
        let a = Double((value >> 24) & 0xFF) / 255.0
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
