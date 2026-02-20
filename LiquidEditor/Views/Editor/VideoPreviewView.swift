// VideoPreviewView.swift
// LiquidEditor
//
// Video preview player area. Displays the current video frame with
// aspect-ratio-fit sizing via AVPlayerLayer. Supports tap to play/pause,
// pinch-to-zoom, pan when zoomed, double-tap to reset zoom.
// Renders tracking bounding box visualization when tracking is active.
// Includes grid and safe zone overlays on the video content area,
// comparison mode toggle, fullscreen chevron trigger, and play/pause
// flash animation.

import AVFoundation
import SwiftUI

// MARK: - VideoPreviewView

/// Displays the video preview as a thin wrapper around the native player.
///
/// When an AVPlayer is provided, renders live video via ``VideoPlayerView``.
/// When no player is available (no media loaded), shows a graceful empty
/// state placeholder with import instructions.
///
/// Supports:
/// - Tap to toggle play/pause (with flash icon animation)
/// - Pinch-to-zoom (1x to 5x)
/// - Pan when zoomed (drag gesture active when zoom > 1x)
/// - Double-tap to reset zoom and pan with animation
/// - Grid overlay (rule of thirds by default)
/// - Safe zone overlay (title safe + action safe)
/// - Comparison mode toggle button (top-right corner)
/// - Fullscreen chevron trigger (bottom center)
/// - Tracking bounding box overlay (when tracking is active)
struct VideoPreviewView: View {

    // MARK: - Properties

    /// The AVPlayer to display. Nil when no media is loaded.
    let player: AVPlayer?

    /// Current playhead position (microseconds).
    let currentTime: TimeMicros

    /// Whether the video is currently playing.
    let isPlaying: Bool

    /// Whether object tracking visualization is active.
    let isTrackingActive: Bool

    /// Tracked bounding boxes for the tracking overlay.
    let trackingBoundingBoxes: [TrackedBoundingBox]

    /// Whether comparison mode is active.
    let isComparisonMode: Bool

    /// Optional aspect ratio for the video. When nil, defaults to 16:9.
    var videoAspectRatio: CGFloat?

    /// Callback when the user taps to toggle play/pause.
    let onTogglePlayPause: () -> Void

    /// Callback to toggle comparison mode.
    let onToggleComparison: () -> Void

    /// Callback when the user taps the fullscreen chevron.
    let onFullscreen: () -> Void

    // MARK: - Zoom & Pan State

    /// Current zoom scale applied to the video content.
    @State private var zoomScale: CGFloat = 1.0

    /// Stored zoom scale from the end of the last magnify gesture.
    @State private var lastZoomScale: CGFloat = 1.0

    /// Current pan offset when zoomed in.
    @State private var panOffset: CGSize = .zero

    /// Stored pan offset from the end of the last drag gesture.
    @State private var lastPanOffset: CGSize = .zero

    // MARK: - Overlay State

    /// Configuration for the grid overlay on the video content.
    @State private var gridConfig = GridOverlayConfig(
        type: .ruleOfThirds,
        isVisible: false,
        opacity: 0.5,
        lineColor: .white,
        lineWidth: 0.5
    )

    /// Configuration for the safe zone overlay on the video content.
    @State private var safeZoneConfig = SafeZoneConfig()

    /// Tracks whether safe zone overlays are toggled on.
    @State private var isSafeZoneVisible: Bool = false

    // MARK: - Play/Pause Flash Animation State

    /// Whether the play/pause flash icon is currently showing.
    @State private var showPlayPauseFlash: Bool = false

    /// The SF Symbol name for the flash icon (play.fill or pause.fill).
    @State private var flashIconName: String = "play.fill"

    /// Opacity for the flash icon fade-out animation.
    @State private var flashOpacity: Double = 0.0

    /// Tracks the previous isPlaying value to detect state changes.
    @State private var previousIsPlaying: Bool = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black

                // Video frame / placeholder with zoom, pan, overlays
                videoContentWithGestures(in: geometry)

                // Play/pause flash icon overlay
                playPauseFlashOverlay

                // Tracking overlay
                if isTrackingActive {
                    TrackingOverlayView(
                        boundingBoxes: trackingBoundingBoxes,
                        viewSize: geometry.size
                    )
                }

                // Fullscreen chevron at bottom center
                VStack {
                    Spacer()
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onFullscreen()
                    } label: {
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, LiquidSpacing.sm)
                    .accessibilityLabel("Fullscreen preview")
                    .accessibilityHint("Opens video in fullscreen mode")
                }

                // Overlay toggle buttons (top-left corner)
                VStack {
                    HStack {
                        overlayToggleButtons
                        Spacer()
                        Button {
                            onToggleComparison()
                        } label: {
                            Image(systemName: "rectangle.split.3x1")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                                        .fill(
                                            isComparisonMode
                                            ? LiquidColors.primary.opacity(0.8)
                                            : Color.black.opacity(0.4)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Comparison mode")
                        .accessibilityValue(isComparisonMode ? "On" : "Off")
                        .accessibilityHint("Toggles before and after comparison")
                    }
                    .padding(LiquidSpacing.sm)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
        .onChange(of: isPlaying) { oldValue, newValue in
            triggerPlayPauseFlash(isNowPlaying: newValue)
        }
    }

    // MARK: - Computed Properties

    /// The effective aspect ratio: uses the provided `videoAspectRatio` or falls back to 16:9.
    private var effectiveAspectRatio: CGFloat {
        videoAspectRatio ?? (16.0 / 9.0)
    }

    // MARK: - Overlay Toggle Buttons

    /// Small pill-style toggle buttons for grid and safe zone overlays.
    private var overlayToggleButtons: some View {
        VStack(spacing: 6) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    gridConfig.isVisible.toggle()
                }
            } label: {
                Image(systemName: gridConfig.isVisible ? "grid.circle.fill" : "grid")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                            .fill(
                                gridConfig.isVisible
                                ? LiquidColors.primary.opacity(0.8)
                                : Color.black.opacity(0.4)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Grid overlay")
            .accessibilityValue(gridConfig.isVisible ? "On" : "Off")
            .accessibilityHint("Toggles composition grid overlay")

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSafeZoneVisible.toggle()
                    if isSafeZoneVisible {
                        safeZoneConfig.activeZones = [.titleSafe, .actionSafe]
                    } else {
                        safeZoneConfig.activeZones = []
                    }
                }
            } label: {
                Image(systemName: isSafeZoneVisible ? "tv.circle.fill" : "tv")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                            .fill(
                                isSafeZoneVisible
                                ? LiquidColors.primary.opacity(0.8)
                                : Color.black.opacity(0.4)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Safe zone overlay")
            .accessibilityValue(isSafeZoneVisible ? "On" : "Off")
            .accessibilityHint("Toggles safe zone guides")
        }
    }

    // MARK: - Video Content with Gestures

    /// Wraps the video content with zoom, pan, and tap gestures.
    @ViewBuilder
    private func videoContentWithGestures(in geometry: GeometryProxy) -> some View {
        videoContent(in: geometry)
            .scaleEffect(zoomScale)
            .offset(panOffset)
            .gesture(magnifyGesture)
            .simultaneousGesture(panGesture)
            .onTapGesture(count: 2) {
                resetZoomAndPan()
            }
            .onTapGesture(count: 1) {
                onTogglePlayPause()
            }
    }

    // MARK: - Video Content

    @ViewBuilder
    private func videoContent(in geometry: GeometryProxy) -> some View {
        if player != nil {
            // Live video preview via AVPlayerLayer with inline overlays
            VideoPlayerView(player: player)
                .aspectRatio(effectiveAspectRatio, contentMode: .fit)
                .frame(
                    maxWidth: geometry.size.width,
                    maxHeight: geometry.size.height
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    GeometryReader { videoGeo in
                        ZStack {
                            // Grid overlay
                            GridOverlayView(
                                config: gridConfig,
                                previewSize: videoGeo.size
                            )

                            // Safe zone overlay
                            SafeZoneOverlayView(
                                config: safeZoneConfig,
                                previewSize: videoGeo.size
                            )
                        }
                    }
                }
        } else {
            // Empty state placeholder when no media is loaded
            emptyStatePlaceholder(in: geometry)
        }
    }

    /// Graceful empty state shown when no player/media is available.
    private func emptyStatePlaceholder(in geometry: GeometryProxy) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                .fill(Color(white: 0.12))

            VStack(spacing: LiquidSpacing.md) {
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.25))

                Text("Import media to preview")
                    .font(LiquidTypography.subheadline)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No media loaded. Import media to preview.")
        .aspectRatio(effectiveAspectRatio, contentMode: .fit)
        .frame(
            maxWidth: geometry.size.width,
            maxHeight: geometry.size.height
        )
    }

    // MARK: - Play/Pause Flash Overlay

    /// Large play/pause icon that briefly appears and fades out on state change.
    @ViewBuilder
    private var playPauseFlashOverlay: some View {
        if showPlayPauseFlash {
            Image(systemName: flashIconName)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
                .padding(LiquidSpacing.xxl)
                .background(.ultraThinMaterial, in: Circle())
                .opacity(flashOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Gestures

    /// Pinch-to-zoom gesture (1x to 5x range).
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastZoomScale * value.magnification
                zoomScale = min(max(newScale, 1.0), 5.0)
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
                // Snap back to 1x if below minimum
                if zoomScale < 1.0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                        panOffset = .zero
                        lastPanOffset = .zero
                    }
                }
            }
    }

    /// Drag gesture for panning when zoomed in (only active when zoomScale > 1.0).
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard zoomScale > 1.0 else { return }
                let newWidth = lastPanOffset.width + value.translation.width
                let newHeight = lastPanOffset.height + value.translation.height
                panOffset = CGSize(width: newWidth, height: newHeight)
            }
            .onEnded { _ in
                guard zoomScale > 1.0 else { return }
                lastPanOffset = panOffset
            }
    }

    /// Resets zoom to 1x and pan to zero with a spring animation.
    private func resetZoomAndPan() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            zoomScale = 1.0
            lastZoomScale = 1.0
            panOffset = .zero
            lastPanOffset = .zero
        }
    }

    // MARK: - Flash Animation

    /// Triggers the play/pause flash icon animation.
    private func triggerPlayPauseFlash(isNowPlaying: Bool) {
        flashIconName = isNowPlaying ? "play.fill" : "pause.fill"
        showPlayPauseFlash = true
        flashOpacity = 1.0

        withAnimation(.easeOut(duration: 0.6)) {
            flashOpacity = 0.0
        }

        // Remove flash view after animation completes
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.65))
            showPlayPauseFlash = false
        }
    }
}
