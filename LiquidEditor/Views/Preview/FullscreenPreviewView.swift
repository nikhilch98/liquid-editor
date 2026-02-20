// FullscreenPreviewView.swift
// LiquidEditor
//
// Immersive fullscreen video preview with auto-hiding controls.
// Supports pinch-to-zoom, double-tap-to-reset, and swipe-to-dismiss.
//
// Matches Flutter FullscreenPreviewView layout:
// - Play/pause button at CENTER of screen: 64x64 circle with .ultraThinMaterial,
//   large play/pause icon
// - No project name in top bar
// - Top bar: Close (xmark, left) + Spacer + grid toggle + safe zone toggle (right)
// - Bottom bar: progress slider + time display row only (no play/pause)
//
// Pure SwiftUI with iOS 26 native styling. Uses .ultraThinMaterial
// for translucent control overlays. Renders live video via
// VideoPlayerView (AVPlayerLayer) when a player is available.

import AVFoundation
import SwiftUI

// MARK: - FullscreenPreviewView

/// Immersive fullscreen preview for video playback.
///
/// Displays live video from an `AVPlayer` centered on a black background
/// with auto-hiding overlay controls. Falls back to a placeholder when
/// no player is available.
///
/// ## Gestures
/// - **Tap:** Toggle controls visibility
/// - **Pinch:** Zoom in/out
/// - **Double Tap:** Reset zoom to 1x
/// - **Swipe Down:** Dismiss the preview
///
/// ## Controls
/// Controls auto-hide after 3 seconds of inactivity.
/// Top bar: close button + grid toggle + safe zone toggle.
/// Center: play/pause button (64x64 glass circle).
/// Bottom bar: time scrubber and time labels (no play/pause).
struct FullscreenPreviewView: View {

    // MARK: - Properties

    /// Total duration in microseconds.
    let totalDuration: Int64

    /// The AVPlayer for live video rendering. Nil when no media is loaded.
    let player: AVPlayer?

    /// Dismiss action for full-screen cover.
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Whether overlay controls are visible.
    @State private var controlsVisible: Bool = true

    /// Task for auto-hiding controls (Swift 6 concurrency safe).
    @State private var hideTask: Task<Void, Never>?

    /// Whether playback is active.
    @State private var isPlaying: Bool = false

    /// Current playhead time in microseconds.
    @State private var currentTime: Int64 = 0

    /// Current zoom scale for pinch gesture.
    @State private var zoomScale: CGFloat = 1.0

    /// Accumulated zoom scale from previous gesture.
    @State private var lastZoomScale: CGFloat = 1.0

    /// Drag offset for swipe-to-dismiss gesture.
    @State private var dragOffset: CGFloat = 0

    /// Whether grid overlay is visible.
    @State private var gridOverlayVisible: Bool = false

    /// Whether safe zone overlay is visible.
    @State private var safeZoneVisible: Bool = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()

                // Video frame (centered, aspect fit)
                videoFrameView
                    .scaleEffect(zoomScale)
                    .offset(y: dragOffset)
                    .gesture(pinchGesture)
                    .gesture(swipeDownGesture)

                // Overlay controls
                if controlsVisible {
                    controlsOverlay(geometry: geometry)
                        .transition(.opacity)
                }
            }
            .onTapGesture {
                toggleControls()
            }
            .onTapGesture(count: 2) {
                resetZoom()
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear {
            scheduleHideControls()
        }
        .onDisappear {
            hideTask?.cancel()
        }
    }

    // MARK: - Video Frame

    @ViewBuilder
    private var videoFrameView: some View {
        if player != nil {
            VideoPlayerView(player: player)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    GeometryReader { geo in
                        ZStack {
                            if gridOverlayVisible {
                                GridOverlayView(
                                    config: GridOverlayConfig(
                                        type: .ruleOfThirds,
                                        isVisible: true,
                                        opacity: 0.5,
                                        lineColor: .white,
                                        lineWidth: 0.5
                                    ),
                                    previewSize: geo.size
                                )
                            }
                            if safeZoneVisible {
                                SafeZoneOverlayView(
                                    config: SafeZoneConfig(
                                        activeZones: [.titleSafe, .actionSafe],
                                        showLabels: true
                                    ),
                                    previewSize: geo.size
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.05))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: LiquidSpacing.md) {
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.25))

                        Text("No media loaded")
                            .font(LiquidTypography.subheadline)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No media loaded")
        }
    }

    // MARK: - Controls Overlay

    private func controlsOverlay(geometry: GeometryProxy) -> some View {
        ZStack {
            // Top bar
            VStack {
                topBar
                    .padding(.top, geometry.safeAreaInsets.top + 8)
                Spacer()
            }

            // Center play/pause button (64x64 glass circle)
            centerPlayPauseButton

            // Bottom bar
            VStack {
                Spacer()
                bottomBar
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 16)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: LiquidSpacing.minTouchTarget, height: LiquidSpacing.minTouchTarget)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close fullscreen preview")

            Spacer()

            // Grid overlay toggle
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                gridOverlayVisible.toggle()
                scheduleHideControls()
            } label: {
                Image(systemName: "grid")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        gridOverlayVisible
                            ? AnyShapeStyle(Color.accentColor.opacity(0.6))
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Circle()
                    )
            }
            .accessibilityLabel("Grid overlay")
            .accessibilityValue(gridOverlayVisible ? "On" : "Off")

            // Safe zone toggle
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                safeZoneVisible.toggle()
                scheduleHideControls()
            } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        safeZoneVisible
                            ? AnyShapeStyle(Color.accentColor.opacity(0.6))
                            : AnyShapeStyle(.ultraThinMaterial),
                        in: Circle()
                    )
            }
            .accessibilityLabel("Safe zone overlay")
            .accessibilityValue(safeZoneVisible ? "On" : "Off")
        }
        .padding(.horizontal, LiquidSpacing.xl)
        .padding(.vertical, LiquidSpacing.sm)
    }

    // MARK: - Center Play/Pause Button

    private var centerPlayPauseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isPlaying.toggle()
            scheduleHideControls()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityHint(isPlaying ? "Pauses video playback" : "Starts video playback")
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: LiquidSpacing.xs) {
            // Time scrubber
            Slider(
                value: Binding(
                    get: {
                        guard totalDuration > 0 else { return 0 }
                        return Double(currentTime) / Double(totalDuration)
                    },
                    set: { newValue in
                        currentTime = Int64(newValue * Double(totalDuration))
                        scheduleHideControls()
                    }
                ),
                in: 0...1
            )
            .tint(.white)
            .accessibilityLabel("Playback position")
            .accessibilityValue(formatTime(currentTime))

            // Time display row
            HStack {
                Text(formatTime(currentTime))
                    .font(LiquidTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColors.textSecondary)

                Spacer()

                Text(formatTime(totalDuration))
                    .font(LiquidTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColors.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Time: \(formatTime(currentTime)) of \(formatTime(totalDuration))")
        }
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.vertical, LiquidSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge)
                .fill(.ultraThinMaterial)
                .padding(.horizontal, LiquidSpacing.sm)
        )
        .padding(.horizontal, LiquidSpacing.sm)
    }

    // MARK: - Gestures

    /// Pinch-to-zoom gesture.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastZoomScale * value.magnification
                zoomScale = min(max(newScale, 0.5), 5.0)
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
                if zoomScale < 1.0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomScale = 1.0
                        lastZoomScale = 1.0
                    }
                }
            }
    }

    /// Swipe-down-to-dismiss gesture.
    private var swipeDownGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 150 {
                    dismiss()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Controls Visibility

    /// Toggle the visibility of overlay controls.
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            scheduleHideControls()
        }
    }

    /// Schedule auto-hide of controls after 3 seconds.
    private func scheduleHideControls() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.0))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                controlsVisible = false
            }
        }
    }

    /// Reset zoom to 1x with animation.
    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            zoomScale = 1.0
            lastZoomScale = 1.0
        }
    }

    // MARK: - Time Formatting

    /// Format microseconds to MM:SS display string.
    private func formatTime(_ micros: Int64) -> String {
        let totalSeconds = Int(micros / 1_000_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
