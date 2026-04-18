// TimelineView.swift
// LiquidEditor
//
// Full timeline view — shows time ruler, track headers with mute/lock
// controls, track lanes with clips, playhead, drag/trim preview overlays,
// selection overlay, reorder overlay, snap guides, and in/out point markers.
// Handles gestures for scrolling, zooming, and clip interaction.
//
// Pure SwiftUI, iOS 26 native styling.
// Matches Flutter TimelineWidget layout.

import SwiftUI
import UIKit

// MARK: - TimelineView

struct TimelineView: View {

    // MARK: - Dependencies

    @Bindable var viewModel: TimelineViewModel
    @Bindable var playbackViewModel: PlaybackViewModel

    /// Optional auto-follow-playhead preference (T7-35). When `true` and
    /// playback is running, the viewport scrolls to keep the playhead in
    /// view. When `nil` (default), auto-follow is disabled — preserves
    /// backwards compatibility for call-sites that haven't wired it yet.
    var autoFollowPlayhead: Bool = false

    // MARK: - Local State

    @State private var containerSize: CGSize = .zero
    @State private var isReorderMode: Bool = false

    /// T7-1: true while a clip long-press is active. Drives a 60%
    /// dim overlay on the surrounding UI.
    @State private var isClipLongPressActive: Bool = false

    // MARK: - Constants

    private let rulerHeight: CGFloat = 30
    private let trackHeight: CGFloat = 64
    private let minimumTrackLaneHeight: CGFloat = 120
    private let trackHeaderWidth: CGFloat = 80

    // Background / overlay opacity constants
    private static let rulerBackgroundOpacity: Double = 0.5
    private static let trackEvenOpacity: Double = 0.03
    private static let trackOddOpacity: Double = 0.05
    private static let sidebarBackgroundOpacity: Double = 0.9
    private static let sidebarDividerOpacity: Double = 0.1
    private static let sidebarDividerWidth: CGFloat = 0.5
    private static let inOutMarkerOpacity: Double = 0.8
    private static let inOutMarkerWidth: CGFloat = 2
    private static let snapGuideOpacity: Double = 0.4
    private static let reorderOverlayOpacity: Double = 0.85
    private static let majorTickOpacity: Double = 0.6
    private static let minorTickOpacity: Double = 0.25
    private static let rulerLabelOpacity: Double = 0.5
    private static let rulerTickWidth: CGFloat = 0.5
    private static let majorTickHeight: CGFloat = 14
    private static let minorTickHeight: CGFloat = 8
    private static let rulerFontSize: CGFloat = 9
    private static let trackHeaderNameFontSize: CGFloat = 10
    private static let trackHeaderNameOpacity: Double = 0.8
    private static let trackHeaderIconFontSize: CGFloat = 14
    private static let trackHeaderIconOpacity: Double = 0.5
    private static let trackHeaderButtonMinSize: CGFloat = 24
    private static let trackHeaderHorizontalPadding: CGFloat = 4
    private static let trackHeaderVerticalPadding: CGFloat = 2
    private static let trackHeaderControlSpacing: CGFloat = 6
    private static let trackDotSize: CGFloat = 6
    private static let trackLabelOpacity: Double = 0.4
    private static let clipInsetVertical: CGFloat = 4
    private static let clipVerticalPadding: CGFloat = 2
    private static let overlayCornerRadius: CGFloat = 6
    private static let overlayFillOpacity: Double = 0.25
    private static let overlayBorderWidth: CGFloat = 2
    private static let selectionCornerRadius: CGFloat = 2
    private static let selectionFillOpacity: Double = 0.1
    private static let selectionBorderOpacity: Double = 0.5
    private static let selectionBorderWidth: CGFloat = 1
    private static let reorderIconFontSize: CGFloat = 32
    private static let reorderIconOpacity: Double = 0.6
    private static let reorderTextFontSize: CGFloat = 14
    private static let reorderTextOpacity: Double = 0.6
    private static let tickTargetPixelSpacing: Double = 12.0
    private static let majorTickMultiplier: TimeMicros = 5

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack(alignment: .topLeading) {
                // Background — alternating track lane colors (no solid black).
                trackLaneBackgrounds(size: size)

                // Main content area.
                HStack(spacing: 0) {
                    // Track header sidebar on the LEFT.
                    if !viewModel.tracks.isEmpty {
                        trackHeaderSidebar
                            .frame(width: trackHeaderWidth)
                            .padding(.top, rulerHeight)
                    }

                    // Timeline content area (ruler + track lanes).
                    VStack(spacing: 0) {
                        // Time ruler.
                        timeRuler(width: size.width - (viewModel.tracks.isEmpty ? 0 : trackHeaderWidth))
                            .frame(height: rulerHeight)

                        // Track Lanes (no divider between ruler and tracks).
                        ScrollView(.vertical, showsIndicators: false) {
                            trackLanes(width: size.width - (viewModel.tracks.isEmpty ? 0 : trackHeaderWidth))
                        }
                    }
                }

                // Selection overlay layer.
                selectionOverlay(size: size)

                // Drag preview overlay layer.
                if viewModel.isDragging {
                    dragPreviewOverlay(size: size)
                }

                // Trim preview overlay layer.
                if viewModel.isTrimming {
                    trimPreviewOverlay(size: size)
                }

                // Snap guides.
                if viewModel.isDragging && viewModel.snapEnabled {
                    snapGuides(height: size.height)
                }

                // In/Out point markers on ruler.
                inOutPointMarkers(width: size.width, rulerH: rulerHeight)

                // Playhead overlay (spans full height).
                playheadOverlay(height: size.height)

                // Reorder overlay (dims timeline when in reorder mode).
                if isReorderMode {
                    reorderOverlay(size: size)
                }

                // T7-1: 60% dim while a clip long-press is active, so the
                // GlassContextMenu pops against a muted backdrop.
                if isClipLongPressActive {
                    Color.black.opacity(0.6)
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isClipLongPressActive)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Video timeline editor")
            .onAppear {
                containerSize = size
                viewModel.updateViewportSize(width: size.width, height: size.height)
            }
            .onChange(of: size) { _, newSize in
                containerSize = newSize
                viewModel.updateViewportSize(width: newSize.width, height: newSize.height)
            }
            .onChange(of: playbackViewModel.currentTime) { _, newTime in
                // T7-35: auto-follow playhead during playback.
                applyAutoFollowIfNeeded(currentTime: newTime)
            }
            .gesture(pinchZoomGesture)
            .clipped()
        }
    }

    // MARK: - Track Lane Backgrounds (Alternating)

    @ViewBuilder
    private func trackLaneBackgrounds(size: CGSize) -> some View {
        VStack(spacing: 0) {
            // Ruler background area.
            Rectangle()
                .fill(Color.black.opacity(Self.rulerBackgroundOpacity))
                .frame(height: rulerHeight)

            if viewModel.tracks.isEmpty {
                // Single track background.
                Rectangle()
                    .fill(Color.white.opacity(Self.trackEvenOpacity))
                    .frame(height: max(trackHeight, minimumTrackLaneHeight))
                Spacer(minLength: 0)
            } else {
                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                    Rectangle()
                        .fill(Color.white.opacity(index.isMultiple(of: 2) ? Self.trackEvenOpacity : Self.trackOddOpacity))
                        .frame(height: track.effectiveHeight)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Track Header Sidebar

    @ViewBuilder
    private var trackHeaderSidebar: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.tracks, id: \.id) { track in
                trackHeaderItem(track: track)
                    .frame(height: track.effectiveHeight)
            }
            Spacer(minLength: 0)
        }
        .background(Color.black.opacity(Self.sidebarBackgroundOpacity))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(Self.sidebarDividerOpacity))
                .frame(width: Self.sidebarDividerWidth)
        }
    }

    /// Individual track header — delegates to `TrackHeaderView` so the
    /// long-press GlassContextMenu (T7-11) is attached uniformly.
    ///
    /// `onRename` / `onMuteAll` / `onDelete` are no-ops for now; the
    /// menu items show but their callbacks are future work (T7-31, etc.).
    @ViewBuilder
    private func trackHeaderItem(track: Track) -> some View {
        TrackHeaderView(
            track: track,
            onToggleMute: { toggleTrackMute(trackId: track.id) },
            onToggleLock: { toggleTrackLock(trackId: track.id) },
            onRename: { /* TODO (T7-31): rename sheet */ },
            onMuteAll: { toggleAllTracksMute() },
            onDelete: { /* TODO (T7-32): delete track with confirmation */ }
        )
    }

    /// T7-11 support: mute every track. If ANY track is unmuted, mute
    /// all; otherwise unmute all.
    private func toggleAllTracksMute() {
        let hasUnmuted = viewModel.tracks.contains { !$0.isMuted }
        for i in viewModel.tracks.indices {
            if viewModel.tracks[i].isMuted != hasUnmuted {
                viewModel.tracks[i] = viewModel.tracks[i].toggleMute()
            }
        }
    }

    // MARK: - Time Ruler

    @ViewBuilder
    private func timeRuler(width: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let visibleRange = viewModel.viewport.visibleTimeRange
            let pxPerMicro = viewModel.viewport.pixelsPerMicrosecond

            // Determine tick interval based on zoom level.
            let tickInterval = Self.tickInterval(for: viewModel.viewport.microsPerPixel)
            let majorTickInterval = tickInterval * Self.majorTickMultiplier

            // First tick at or before the visible start.
            let firstTick = (visibleRange.start / tickInterval) * tickInterval

            var t = firstTick
            while t <= visibleRange.end {
                let x = CGFloat(Double(t - visibleRange.start) * pxPerMicro)
                let isMajor = (t % majorTickInterval) == 0

                // Tick line.
                let tickHeight: CGFloat = isMajor ? Self.majorTickHeight : Self.minorTickHeight
                let tickColor = isMajor
                    ? Color.white.opacity(Self.majorTickOpacity)
                    : Color.white.opacity(Self.minorTickOpacity)

                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: canvasSize.height - tickHeight))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    },
                    with: .color(tickColor),
                    lineWidth: Self.rulerTickWidth
                )

                // Time label on major ticks.
                if isMajor {
                    let label = t.simpleTimeString
                    let text = Text(label)
                        .font(.system(size: Self.rulerFontSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(Self.rulerLabelOpacity))

                    context.draw(
                        context.resolve(text),
                        at: CGPoint(x: x, y: 6),
                        anchor: .top
                    )
                }

                t += tickInterval
            }
        }
        .background(Color.black.opacity(Self.rulerBackgroundOpacity))
        .gesture(rulerDragGesture)
        // Accessibility: Canvas is opaque to VoiceOver; expose ruler as a single
        // adjustable element so users can scrub the playhead with swipe up/down.
        .accessibilityElement()
        .accessibilityLabel("Timeline ruler, current time \(playbackViewModel.currentTime.simpleTimeString)")
        .accessibilityHint("Swipe up or down to move playhead")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAdjustableAction { direction in
            // Step size: 1% of total duration, minimum 1 second.
            let stepMicros: TimeMicros = max(
                viewModel.totalDuration / 100,
                1_000_000
            )
            switch direction {
            case .increment:
                let newTime = min(playbackViewModel.currentTime + stepMicros, viewModel.totalDuration)
                playbackViewModel.updateCurrentTime(newTime)
                viewModel.playheadPosition = newTime
                playbackViewModel.seek(to: newTime)
            case .decrement:
                let newTime = max(playbackViewModel.currentTime - stepMicros, 0)
                playbackViewModel.updateCurrentTime(newTime)
                viewModel.playheadPosition = newTime
                playbackViewModel.seek(to: newTime)
            @unknown default:
                break
            }
        }
    }

    // MARK: - In/Out Point Markers

    @ViewBuilder
    private func inOutPointMarkers(width: CGFloat, rulerH: CGFloat) -> some View {
        let headerOffset = viewModel.tracks.isEmpty ? 0 : trackHeaderWidth

        if let inPoint = viewModel.selection.inPoint {
            let inX = viewModel.timeToX(inPoint)
                - CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond)
                + headerOffset

            Rectangle()
                .fill(Color.green.opacity(Self.inOutMarkerOpacity))
                .frame(width: Self.inOutMarkerWidth, height: rulerH)
                .position(x: inX, y: rulerH / 2)
                .accessibilityLabel("In point at \(inPoint.simpleTimeString)")
                .accessibilityAddTraits(.isStaticText)
        }

        if let outPoint = viewModel.selection.outPoint {
            let outX = viewModel.timeToX(outPoint)
                - CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond)
                + headerOffset

            Rectangle()
                .fill(Color.red.opacity(Self.inOutMarkerOpacity))
                .frame(width: Self.inOutMarkerWidth, height: rulerH)
                .position(x: outX, y: rulerH / 2)
                .accessibilityLabel("Out point at \(outPoint.simpleTimeString)")
                .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Track Lanes

    @ViewBuilder
    private func trackLanes(width: CGFloat) -> some View {
        let items = viewModel.timeline.toList()

        VStack(spacing: 0) {
            if viewModel.tracks.isEmpty {
                // Single implicit track when no explicit tracks exist.
                singleTrackLane(items: items, width: width)
            } else {
                ForEach(viewModel.tracks, id: \.id) { track in
                    trackLane(track: track, items: items, width: width)
                }
            }
        }
    }

    @ViewBuilder
    private func singleTrackLane(items: [any TimelineItemProtocol], width: CGFloat) -> some View {
        let visibleRange = viewModel.viewport.visibleTimeRange
        let pxPerMicro = viewModel.viewport.pixelsPerMicrosecond

        ZStack(alignment: .leading) {
            // Clips laid out horizontally — only render clips overlapping the visible viewport.
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                    let clipWidth = CGFloat(Double(item.durationMicroseconds) * pxPerMicro)
                    let clipStart = viewModel.timeline.startTimeOf(item.id) ?? 0
                    let clipEnd = clipStart + item.durationMicroseconds
                    let clipVisible = clipEnd > visibleRange.start && clipStart < visibleRange.end

                    if clipVisible {
                        let isSelected = viewModel.selection.isClipSelected(item.id)

                        ClipView(
                            item: item,
                            width: max(clipWidth, 2),
                            height: trackHeight,
                            isSelected: isSelected,
                            isDragging: viewModel.isDragging && isSelected,
                            onTap: {
                                viewModel.selectClip(id: item.id)
                            },
                            onDoubleTapped: {
                                // T7-1: Trim Precision entry point.
                                viewModel.selectClip(id: item.id)
                            },
                            onLongPressChanged: { active in
                                isClipLongPressActive = active
                            },
                            onDragChanged: { delta in
                                handleClipDrag(id: item.id, delta: delta)
                            },
                            onDragEnded: {
                                viewModel.isDragging = false
                            },
                            onTrimStartChanged: { delta in
                                handleTrimStart(id: item.id, delta: delta)
                            },
                            onTrimEndChanged: { delta in
                                handleTrimEnd(id: item.id, delta: delta)
                            },
                            onTrimEnded: {
                                viewModel.isTrimming = false
                            }
                        )
                    } else {
                        // Invisible clip: use a lightweight spacer to preserve layout.
                        Color.clear
                            .frame(width: max(clipWidth, 2), height: trackHeight)
                    }
                }
            }
            .offset(x: -CGFloat(Double(viewModel.viewport.scrollPosition) * pxPerMicro))
        }
        .frame(height: max(trackHeight, minimumTrackLaneHeight))
    }

    @ViewBuilder
    private func trackLane(track: Track, items: [any TimelineItemProtocol], width: CGFloat) -> some View {
        let effectiveHeight = track.effectiveHeight
        let visibleRange = viewModel.viewport.visibleTimeRange
        let pxPerMicro = viewModel.viewport.pixelsPerMicrosecond

        ZStack(alignment: .leading) {
            // Track label.
            HStack(spacing: LiquidSpacing.xs) {
                Circle()
                    .fill(Color(argb32: track.colorARGB32))
                    .frame(width: Self.trackDotSize, height: Self.trackDotSize)
                Text(track.name)
                    .font(.system(size: Self.trackHeaderNameFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(Self.trackLabelOpacity))
            }
            .padding(.leading, LiquidSpacing.xs)
            .padding(.top, LiquidSpacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityHidden(true)

            // Clips for this track — only render clips overlapping the visible viewport.
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                    let clipWidth = CGFloat(Double(item.durationMicroseconds) * pxPerMicro)
                    let clipStart = viewModel.timeline.startTimeOf(item.id) ?? 0
                    let clipEnd = clipStart + item.durationMicroseconds
                    let clipVisible = clipEnd > visibleRange.start && clipStart < visibleRange.end

                    if clipVisible {
                        let isSelected = viewModel.selection.isClipSelected(item.id)

                        ClipView(
                            item: item,
                            width: max(clipWidth, 2),
                            height: effectiveHeight - Self.clipInsetVertical,
                            isSelected: isSelected,
                            isDragging: viewModel.isDragging && isSelected,
                            onTap: {
                                viewModel.selectClip(id: item.id)
                            },
                            onDoubleTapped: {
                                // T7-1: Trim Precision entry point.
                                viewModel.selectClip(id: item.id)
                            },
                            onLongPressChanged: { active in
                                isClipLongPressActive = active
                            },
                            onDragChanged: { delta in
                                handleClipDrag(id: item.id, delta: delta)
                            },
                            onDragEnded: {
                                viewModel.isDragging = false
                            },
                            onTrimStartChanged: { delta in
                                handleTrimStart(id: item.id, delta: delta)
                            },
                            onTrimEndChanged: { delta in
                                handleTrimEnd(id: item.id, delta: delta)
                            },
                            onTrimEnded: {
                                viewModel.isTrimming = false
                            }
                        )
                    } else {
                        // Invisible clip: use a lightweight spacer to preserve layout.
                        Color.clear
                            .frame(width: max(clipWidth, 2), height: effectiveHeight - Self.clipInsetVertical)
                    }
                }
            }
            .padding(.vertical, Self.clipVerticalPadding)
            .offset(x: -CGFloat(Double(viewModel.viewport.scrollPosition) * pxPerMicro))
        }
        .frame(height: effectiveHeight)
    }

    // MARK: - Drag Preview Overlay

    @ViewBuilder
    private func dragPreviewOverlay(size: CGSize) -> some View {
        // Blue-tinted semi-transparent rectangle at the preview position.
        // Uses the selected clips' positions for a simple preview.
        let selectedIds = viewModel.selection.selectedClipIds
        let items = viewModel.timeline.toList()
        let scrollOffsetPx = CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond)
        let headerOffset = viewModel.tracks.isEmpty ? 0 : trackHeaderWidth

        ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
            if selectedIds.contains(item.id) {
                let clipWidth = CGFloat(Double(item.durationMicroseconds) * viewModel.viewport.pixelsPerMicrosecond)
                let startTime = viewModel.timeline.startTimeOf(item.id) ?? 0
                let clipX = viewModel.timeToX(startTime) - scrollOffsetPx + headerOffset

                RoundedRectangle(cornerRadius: Self.overlayCornerRadius)
                    .fill(Color.blue.opacity(Self.overlayFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.overlayCornerRadius)
                            .strokeBorder(Color.blue, lineWidth: Self.overlayBorderWidth)
                    )
                    .frame(width: max(clipWidth, 2), height: trackHeight)
                    .position(x: clipX + max(clipWidth, 2) / 2, y: rulerHeight + trackHeight / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Trim Preview Overlay

    @ViewBuilder
    private func trimPreviewOverlay(size: CGSize) -> some View {
        // Orange/red-tinted preview rectangle when trimming.
        let selectedIds = viewModel.selection.selectedClipIds
        let items = viewModel.timeline.toList()
        let scrollOffsetPx = CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond)
        let headerOffset = viewModel.tracks.isEmpty ? 0 : trackHeaderWidth

        ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
            if selectedIds.contains(item.id) {
                let clipWidth = CGFloat(Double(item.durationMicroseconds) * viewModel.viewport.pixelsPerMicrosecond)
                let startTime = viewModel.timeline.startTimeOf(item.id) ?? 0
                let clipX = viewModel.timeToX(startTime) - scrollOffsetPx + headerOffset

                RoundedRectangle(cornerRadius: Self.overlayCornerRadius)
                    .fill(Color.orange.opacity(Self.overlayFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: Self.overlayCornerRadius)
                            .strokeBorder(Color.orange, lineWidth: Self.overlayBorderWidth)
                    )
                    .frame(width: max(clipWidth, 2), height: trackHeight)
                    .position(x: clipX + max(clipWidth, 2) / 2, y: rulerHeight + trackHeight / 2)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private func selectionOverlay(size: CGSize) -> some View {
        // Multi-selection marquee overlay.
        if let marqueeStart = viewModel.selection.marqueeStart,
           let marqueeEnd = viewModel.selection.marqueeEnd {
            let rect = CGRect(
                x: min(marqueeStart.x, marqueeEnd.x),
                y: min(marqueeStart.y, marqueeEnd.y),
                width: abs(marqueeEnd.x - marqueeStart.x),
                height: abs(marqueeEnd.y - marqueeStart.y)
            )

            RoundedRectangle(cornerRadius: Self.selectionCornerRadius)
                .fill(Color.blue.opacity(Self.selectionFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.selectionCornerRadius)
                        .strokeBorder(Color.blue.opacity(Self.selectionBorderOpacity), lineWidth: Self.selectionBorderWidth)
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Reorder Overlay

    @ViewBuilder
    private func reorderOverlay(size: CGSize) -> some View {
        // Dims the entire timeline and shows a reorder interface.
        Color.black.opacity(Self.reorderOverlayOpacity)
            .frame(width: size.width, height: size.height)
            .overlay(
                VStack(spacing: LiquidSpacing.md) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: Self.reorderIconFontSize, weight: .light))
                        .foregroundStyle(.white.opacity(Self.reorderIconOpacity))
                    Text("Reorder Mode")
                        .font(.system(size: Self.reorderTextFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(Self.reorderTextOpacity))
                }
            )
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reorder mode active. Drag clips to rearrange.")
    }

    // MARK: - Playhead Overlay

    @ViewBuilder
    private func playheadOverlay(height: CGFloat) -> some View {
        let headerOffset = viewModel.tracks.isEmpty ? 0 : trackHeaderWidth
        let playheadX = viewModel.timeToX(playbackViewModel.currentTime)
            - CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond)
            + headerOffset

        PlayheadView(
            xPosition: playheadX,
            height: height,
            currentTime: playbackViewModel.currentTime,
            onDrag: { newX in
                viewModel.isScrubbingTimeline = true
                let adjustedX = newX - headerOffset
                    + CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond)
                let time = viewModel.xToTime(adjustedX)
                let clamped = max(0, min(time, viewModel.totalDuration))
                playbackViewModel.updateCurrentTime(clamped)
                viewModel.playheadPosition = clamped
            },
            onDragEnded: {
                viewModel.isScrubbingTimeline = false
                playbackViewModel.seek(to: playbackViewModel.currentTime)
            }
        )
    }

    // MARK: - Snap Guides

    @ViewBuilder
    private func snapGuides(height: CGFloat) -> some View {
        let items = viewModel.timeline.toList()
        var runningTime: TimeMicros = 0
        let headerOffset = viewModel.tracks.isEmpty ? 0 : trackHeaderWidth

        ForEach(Array(items.indices), id: \.self) { index in
            let item = items[index]
            let _ = { runningTime += item.durationMicroseconds }()
            let edgeX = viewModel.timeToX(runningTime)
                - CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond)
                + headerOffset

            Rectangle()
                .fill(Color.yellow.opacity(Self.snapGuideOpacity))
                .frame(width: 1, height: height)
                .position(x: edgeX, y: height / 2)
        }
    }

    // MARK: - Track Mutation Helpers

    private func toggleTrackMute(trackId: String) {
        guard let index = viewModel.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        viewModel.tracks[index] = viewModel.tracks[index].toggleMute()
    }

    private func toggleTrackLock(trackId: String) {
        guard let index = viewModel.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        viewModel.tracks[index] = viewModel.tracks[index].toggleLock()
    }

    // MARK: - Gestures

    /// Pinch gesture for zooming the timeline.
    private var pinchZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let scale = value.magnification
                viewModel.zoom(scale: scale, anchor: containerSize.width / 2)
            }
    }

    /// Drag gesture on the ruler for scrubbing the playhead.
    private var rulerDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                viewModel.isScrubbingTimeline = true
                let time = viewModel.xToTime(value.location.x + CGFloat(Double(viewModel.viewport.scrollPosition) * viewModel.viewport.pixelsPerMicrosecond))
                let clamped = max(0, min(time, viewModel.totalDuration))
                playbackViewModel.updateCurrentTime(clamped)
                viewModel.playheadPosition = clamped
            }
            .onEnded { _ in
                viewModel.isScrubbingTimeline = false
                playbackViewModel.seek(to: playbackViewModel.currentTime)
            }
    }

    // MARK: - Auto-Follow Playhead (T7-35)

    /// Scroll the timeline to keep the playhead visible while playing.
    ///
    /// No-op when:
    /// - `autoFollowPlayhead` is false
    /// - playback is paused
    /// - the user is actively scrubbing (do not fight their finger)
    ///
    /// Strategy: when the playhead is within the trailing 15% of the
    /// visible range, advance `viewport.scrollPosition` so the playhead
    /// returns to the leading 30%. This mirrors Premiere/DaVinci
    /// "page-scroll" behavior and avoids jitter compared to a
    /// continuous center-lock.
    private func applyAutoFollowIfNeeded(currentTime: TimeMicros) {
        guard autoFollowPlayhead,
              playbackViewModel.isPlaying,
              !viewModel.isScrubbingTimeline
        else { return }

        let viewport = viewModel.viewport
        let visible = viewport.visibleTimeRange
        let visibleDuration = visible.end - visible.start
        guard visibleDuration > 0 else { return }

        let trailingTriggerRatio = 0.85
        let leadingTargetRatio = 0.30

        let trigger = visible.start + TimeMicros(
            Double(visibleDuration) * trailingTriggerRatio
        )

        guard currentTime >= trigger else { return }

        let newScroll = max(
            0,
            currentTime - TimeMicros(Double(visibleDuration) * leadingTargetRatio)
        )

        viewModel.viewport = viewport.withScrollPosition(
            newScroll,
            maxPosition: viewModel.totalDuration
        )
    }

    // MARK: - Clip Interaction Handlers

    private func handleClipDrag(id: String, delta: CGFloat) {
        viewModel.isDragging = true
        let timeDelta = viewModel.xToTime(delta) - viewModel.xToTime(0)
        guard let startTime = viewModel.timeline.startTimeOf(id) else { return }
        var newTime = startTime + timeDelta
        newTime = viewModel.snapToNearestEdge(time: newTime)
        viewModel.moveClip(id: id, toTime: max(0, newTime))
    }

    private func handleTrimStart(id: String, delta: CGFloat) {
        viewModel.isTrimming = true
        let timeDelta = viewModel.xToTime(delta) - viewModel.xToTime(0)
        viewModel.trimClipStart(id: id, delta: timeDelta)
    }

    private func handleTrimEnd(id: String, delta: CGFloat) {
        viewModel.isTrimming = true
        let timeDelta = viewModel.xToTime(delta) - viewModel.xToTime(0)
        viewModel.trimClipEnd(id: id, delta: timeDelta)
    }

    // MARK: - Tick Interval Calculation

    /// Determine tick interval in microseconds based on zoom level.
    private static func tickInterval(for microsPerPixel: Double) -> TimeMicros {
        // Target ~60px between major ticks (5 minor ticks per major).
        let targetMicrosPerTick = microsPerPixel * tickTargetPixelSpacing

        let intervals: [TimeMicros] = [
            100_000,        // 0.1s
            250_000,        // 0.25s
            500_000,        // 0.5s
            1_000_000,      // 1s
            2_000_000,      // 2s
            5_000_000,      // 5s
            10_000_000,     // 10s
            30_000_000,     // 30s
            60_000_000,     // 1min
        ]

        for interval in intervals {
            if Double(interval) >= targetMicrosPerTick {
                return interval
            }
        }

        return intervals.last!
    }
}

// MARK: - Color Extension for ARGB32

private extension Color {
    /// Create a Color from an ARGB32 integer.
    init(argb32: Int) {
        let a = Double((argb32 >> 24) & 0xFF) / 255.0
        let r = Double((argb32 >> 16) & 0xFF) / 255.0
        let g = Double((argb32 >> 8) & 0xFF) / 255.0
        let b = Double(argb32 & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
