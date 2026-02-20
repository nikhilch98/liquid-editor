// ExportSheet.swift
// LiquidEditor
//
// Export configuration and progress sheet view matching Flutter predecessor layout.
// Video preview at top, Export Settings with Auto/Manual toggle, step sliders,
// gradient progress border during export. Pure iOS 26 SwiftUI with native styling.

import SwiftUI
import UIKit

// MARK: - GradientProgressBorderView

/// A SwiftUI view that draws an animated angular-gradient progress border
/// around a rounded-rectangle video preview.
///
/// The arc starts from the top center and sweeps clockwise, matching the
/// Flutter `GradientProgressBorderPainter` behaviour.
///
/// Usage:
/// ```swift
/// GradientProgressBorderView(progress: 0.65, size: CGSize(width: 296, height: 216))
/// ```
struct GradientProgressBorderView: View {

    /// Progress value from 0.0 (no border) to 1.0 (full border).
    let progress: Double

    /// Overall size of the border frame (outer edge of stroke).
    let size: CGSize

    /// Corner radius of the rounded rectangle border.
    var cornerRadius: CGFloat = 20

    /// Stroke width in points.
    var strokeWidth: CGFloat = 4

    // Gradient stop colors – pink → red → orange clockwise from top
    private static let colorPink   = Color(red: 1.0, green: 0.42, blue: 0.62)
    private static let colorRed    = Color(red: 1.0, green: 0.28, blue: 0.34)
    private static let colorOrange = Color(red: 1.0, green: 0.55, blue: 0.26)
    private static let colorYellow = Color(red: 1.0, green: 0.70, blue: 0.28)

    var body: some View {
        Canvas { context, _ in
            let halfStroke = strokeWidth / 2
            let borderRect = CGRect(
                x: halfStroke,
                y: halfStroke,
                width: size.width - strokeWidth,
                height: size.height - strokeWidth
            )

            // Background track – full rounded-rect at 10 % white opacity.
            let trackPath = Path(roundedRect: borderRect, cornerRadius: cornerRadius)
            context.stroke(
                trackPath,
                with: .color(.white.opacity(0.1)),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )

            guard progress > 0 else { return }

            // Build a path that starts from the top-center and goes clockwise.
            // SwiftUI's `Path(roundedRect:)` starts at the right-center (3 o'clock),
            // so we rotate the drawing context 90° counter-clockwise around the
            // center of the canvas before trimming, which maps 3 o'clock → 12 o'clock.

            let clampedProgress = progress.clamp(to: 0...1)
            let cx = size.width / 2
            let cy = size.height / 2

            // The full rounded-rect path used for trimming.
            let fullPath = Path(roundedRect: borderRect, cornerRadius: cornerRadius)
            let trimmedPath = fullPath.trimmedPath(from: 0, to: clampedProgress)

            // Apply the -90° rotation to a copy of the context so the background
            // track is not affected.
            var rotatedCtx = context
            // Translate to centre, rotate, translate back.
            rotatedCtx.translateBy(x: cx, y: cy)
            rotatedCtx.rotate(by: .degrees(-90))
            rotatedCtx.translateBy(x: -cx, y: -cy)

            // Conic (angular) gradient centred on the canvas; the colour ramp
            // flows pink → red → orange → yellow → pink clockwise from 12 o'clock
            // after the context rotation.
            let gradient = Gradient(stops: [
                .init(color: Self.colorPink,   location: 0.00),
                .init(color: Self.colorRed,    location: 0.25),
                .init(color: Self.colorOrange, location: 0.50),
                .init(color: Self.colorYellow, location: 0.75),
                .init(color: Self.colorPink,   location: 1.00),
            ])

            let shading = GraphicsContext.Shading.conicGradient(
                gradient,
                center: CGPoint(x: cx, y: cy),
                angle: .degrees(0)
            )

            rotatedCtx.stroke(
                trimmedPath,
                with: shading,
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Double+Clamp (private helper)

private extension Double {
    func clamp(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

struct ExportSheet: View {

    @State private var viewModel = ExportViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Project duration in seconds used for file size estimation.
    /// Defaults to 60 if not provided by the caller.
    let estimatedDurationSeconds: Double

    /// Optional video thumbnail image for the preview area.
    /// When nil, a placeholder icon is shown instead.
    let thumbnailImage: UIImage?

    // Manual settings state (mirrors Flutter _isManual / Auto mode)
    @State private var isManual = true
    @State private var exportAudioOnly = false
    @State private var isHdr = true

    // Step slider indices (0..4 for 5 stops)
    @State private var resolutionIndex: Double = Self.defaultResolutionIndex
    @State private var fpsIndex: Double = Self.defaultFpsIndex
    @State private var bitrateValue: Double = Self.defaultBitrateMbps

    // Preview play/pause overlay state
    /// Whether the preview is currently playing.
    @State private var isPreviewPlaying = false
    /// Controls overlay visibility; hides after 2 s of inactivity.
    @State private var isPlayPauseOverlayVisible = true
    /// Timer task for the auto-hide behaviour.
    @State private var playPauseHideTask: Task<Void, Never>?

    // Debug sheet presentation
    @State private var isDebugSheetPresented = false

    // Resolution and FPS stop definitions
    private let resolutions = [540, 720, 1080, 2700, 3840]
    private let resolutionLabels = ["540p", "720p", "1080p", "2.7K", "4K"]
    private let fpsOptions = [24, 25, 30, 50, 60]

    // MARK: - Constants

    /// Default resolution step index (4 = 4K).
    private static let defaultResolutionIndex: Double = 4.0

    /// Default FPS step index (4 = 60 fps).
    private static let defaultFpsIndex: Double = 4.0

    /// Default average bitrate in Mbps.
    private static let defaultBitrateMbps: Double = 54.6

    /// Minimum bitrate in Mbps.
    private static let minimumBitrateMbps: Double = 1.0

    /// Maximum bitrate in Mbps.
    private static let maximumBitrateMbps: Double = 150.0

    /// Maximum slider step index for resolution and FPS.
    private static let sliderMaxIndex: Double = 4.0

    /// Audio bitrate overhead used for file size estimation (MB per second).
    private static let audioSizeMbPerSecond: Double = 0.024

    /// Export completion threshold for status message display.
    private static let exportCompletionThreshold: Double = 0.99

    // Preview / layout constants
    private static let previewWidth: CGFloat = 280
    private static let previewHeight: CGFloat = 200
    private static let previewBorderWidth: CGFloat = 296
    private static let previewBorderHeight: CGFloat = 216
    private static let previewBorderCornerRadius: CGFloat = 20
    private static let previewInnerCornerRadius: CGFloat = 16
    private static let previewBorderStrokeWidth: CGFloat = 4
    private static let previewShadowOpacity: Double = 0.3
    private static let previewShadowRadius: CGFloat = 20
    private static let previewShadowY: CGFloat = 10
    private static let previewBorderBackgroundOpacity: Double = 0.1
    private static let previewTopPadding: CGFloat = 20
    private static let previewBottomPadding: CGFloat = 32
    private static let exportProgressFontSize: CGFloat = 56
    private static let exportPlaceholderIconFontSize: CGFloat = 48
    private static let exportBottomSpacer: CGFloat = 100
    private static let headerBottomPadding: CGFloat = 10

    // Toggle / slider layout constants
    private static let toggleContainerPadding: CGFloat = 2
    private static let toggleOptionCornerRadius: CGFloat = 6
    private static let toggleOptionHorizontalPadding: CGFloat = LiquidSpacing.md
    private static let toggleOptionVerticalPadding: CGFloat = 6
    private static let toggleContainerCornerRadius: CGFloat = 8
    private static let bitrateDisplayCornerRadius: CGFloat = 6
    private static let stepSliderLabelFontSize: CGFloat = 10
    private static let stepSliderLabelPadding: CGFloat = 10
    private static let bitrateRangeLabelFontSize: CGFloat = 10
    private static let bitratePadding: CGFloat = 6

    // Export progress gradient colors
    private static let gradientColorPink = Color(red: 1.0, green: 0.42, blue: 0.62)
    private static let gradientColorRed = Color(red: 1.0, green: 0.28, blue: 0.34)
    private static let gradientColorOrange = Color(red: 1.0, green: 0.55, blue: 0.26)
    private static let gradientColorYellow = Color(red: 1.0, green: 0.70, blue: 0.28)

    // Play/pause overlay constants
    /// Diameter of the semi-transparent circular play/pause button (44 pt minimum touch target).
    private static let playPauseButtonSize: CGFloat = 44
    /// Auto-hide delay for the play/pause overlay in seconds.
    private static let playPauseAutoHideDelay: Double = 2.0

    // DEBUG: Set true to show the "Debug Export" button in the header.
    // In a production release this would be driven by a build flag; we expose
    // it as a private constant so it can be toggled at compile time.
    #if DEBUG
    private static let isDebugExportEnabled = true
    #else
    private static let isDebugExportEnabled = false
    #endif

    init(estimatedDurationSeconds: Double = 60.0, thumbnailImage: UIImage? = nil) {
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.thumbnailImage = thumbnailImage
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with X close button
            headerRow
                .padding(.horizontal, LiquidSpacing.xl)
                .padding(.top, LiquidSpacing.xl)
                .padding(.bottom, Self.headerBottomPadding)

            if viewModel.isExporting || viewModel.isComplete {
                exportProgressView
            } else {
                // Config view
                ScrollView {
                    VStack(spacing: 0) {
                        // Video preview placeholder
                        previewPlaceholder
                            .padding(.top, Self.previewTopPadding)
                            .padding(.bottom, Self.previewBottomPadding)

                        // Settings form
                        settingsForm
                            .padding(.horizontal, LiquidSpacing.xxl)

                        Spacer().frame(height: Self.exportBottomSpacer)
                    }
                }

                // Full-width Export button
                exportButton
                    .padding(.horizontal, LiquidSpacing.xxl)
                    .padding(.vertical, LiquidSpacing.xxl)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Export")
                .font(LiquidTypography.headline)

            Spacer()

            // Debug Export button – only visible in DEBUG builds and when not exporting.
            if Self.isDebugExportEnabled && !viewModel.isExporting {
                Button {
                    isDebugSheetPresented = true
                } label: {
                    Label("Debug Export", systemImage: "ladybug.fill")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, LiquidSpacing.sm)
                        .padding(.vertical, LiquidSpacing.xs)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Debug Export")
                .accessibilityHint("Opens the export debug comparison sheet")
                .sheet(isPresented: $isDebugSheetPresented) {
                    // Provide placeholder Data so the sheet can be opened even before
                    // a real export has been run.
                    ExportDebugSheet(
                        previewFrame: Data(),
                        exportFrame: Data(),
                        debugInfo: ExportDebugInfo()
                    )
                }
            }

            Button {
                if viewModel.isExporting {
                    Task { await viewModel.cancelExport() }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isExporting ? "Cancel export" : "Close")
            .accessibilityHint(viewModel.isExporting ? "Cancels the ongoing export" : "Dismisses the export sheet")
        }
    }

    // MARK: - Preview Placeholder

    private var previewPlaceholder: some View {
        ZStack {
            // Video frame or placeholder background
            if let thumbnail = thumbnailImage {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.previewWidth, height: Self.previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge))
                    .shadow(color: .black.opacity(Self.previewShadowOpacity), radius: Self.previewShadowRadius, y: Self.previewShadowY)
            } else {
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge)
                    .fill(Color(.systemGray6))
                    .frame(width: Self.previewWidth, height: Self.previewHeight)
                    .shadow(color: .black.opacity(Self.previewShadowOpacity), radius: Self.previewShadowRadius, y: Self.previewShadowY)

                Image(systemName: "film")
                    .font(.system(size: Self.exportPlaceholderIconFontSize))
                    .foregroundStyle(.secondary)
            }

            // Play/pause overlay – semi-transparent circle centred on the preview.
            // Auto-hides 2 s after the last tap.
            Button {
                togglePreviewPlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: Self.playPauseButtonSize, height: Self.playPauseButtonSize)

                    Image(systemName: isPreviewPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .opacity(isPlayPauseOverlayVisible ? 1 : 0)
            .allowsHitTesting(isPlayPauseOverlayVisible)
            .animation(.easeInOut(duration: 0.2), value: isPlayPauseOverlayVisible)
            .accessibilityLabel(isPreviewPlaying ? "Pause preview" : "Play preview")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping anywhere on the preview shows the overlay and schedules hide.
            showPlayPauseOverlay()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Video preview")
    }

    // MARK: - Play/Pause Overlay Helpers

    /// Toggles preview playback state and reschedules the auto-hide timer.
    private func togglePreviewPlayback() {
        isPreviewPlaying.toggle()
        showPlayPauseOverlay()
    }

    /// Makes the play/pause overlay visible and schedules it to hide after
    /// `playPauseAutoHideDelay` seconds of inactivity.
    private func showPlayPauseOverlay() {
        isPlayPauseOverlayVisible = true
        // Cancel any pending hide task before scheduling a fresh one.
        playPauseHideTask?.cancel()
        playPauseHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.playPauseAutoHideDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isPlayPauseOverlayVisible = false
            }
        }
    }

    // MARK: - Settings Form

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xxl) {
            // Export Settings header + Auto/Manual toggle
            HStack {
                Text("Export Settings   \(currentResolutionLabel) / \(currentFps)fps")
                    .font(LiquidTypography.subheadlineSemibold)

                Spacer()

                autoManualToggle
            }

            // Export Audio Only toggle
            switchRow("Export Audio Only", isOn: $exportAudioOnly)

            // HDR toggle
            switchRow("HDR", isOn: $isHdr)

            if isManual {
                // Resolution step slider
                VStack(alignment: .leading, spacing: LiquidSpacing.md) {
                    Text("Resolution")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)

                    stepSlider(
                        value: $resolutionIndex,
                        maxValue: Self.sliderMaxIndex,
                        labels: resolutionLabels
                    )
                }

                // FPS step slider
                VStack(alignment: .leading, spacing: LiquidSpacing.md) {
                    Text("FPS")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)

                    stepSlider(
                        value: $fpsIndex,
                        maxValue: Self.sliderMaxIndex,
                        labels: fpsOptions.map { String($0) }
                    )
                }

                // Bitrate continuous slider
                VStack(alignment: .leading, spacing: LiquidSpacing.md) {
                    HStack {
                        Text("Average Bitrate (Mbps)")
                            .font(LiquidTypography.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(String(format: "%.1f", bitrateValue))
                            .font(LiquidTypography.subheadline)
                            .padding(.horizontal, LiquidSpacing.md)
                            .padding(.vertical, Self.bitratePadding)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: Self.bitrateDisplayCornerRadius))
                    }

                    Slider(value: $bitrateValue, in: Self.minimumBitrateMbps...Self.maximumBitrateMbps)
                        .accessibilityLabel("Average Bitrate")
                        .accessibilityValue(String(format: "%.1f megabits per second", bitrateValue))

                    HStack {
                        Text("\(String(format: "%.1f", Self.minimumBitrateMbps)) Mbps")
                            .font(.system(size: Self.bitrateRangeLabelFontSize))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.1f", Self.maximumBitrateMbps)) Mbps")
                            .font(.system(size: Self.bitrateRangeLabelFontSize))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Estimated File Size
            Text("Estimated File Size   \(estimatedFileSize)")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Estimated file size: \(estimatedFileSize)")
        }
    }

    // MARK: - Auto/Manual Toggle

    private var autoManualToggle: some View {
        HStack(spacing: 0) {
            toggleOption("Auto", isSelected: !isManual)
            toggleOption("Manual", isSelected: isManual)
        }
        .padding(Self.toggleContainerPadding)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.toggleContainerCornerRadius))
    }

    private func toggleOption(_ label: String, isSelected: Bool) -> some View {
        Button {
            isManual = (label == "Manual")
        } label: {
            Text(label)
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, Self.toggleOptionHorizontalPadding)
                .padding(.vertical, Self.toggleOptionVerticalPadding)
                .background(
                    isSelected
                        ? Color(.tertiarySystemGroupedBackground)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: Self.toggleOptionCornerRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Switch Row

    private func switchRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(LiquidTypography.subheadlineSemibold)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }

    // MARK: - Step Slider

    private func stepSlider(
        value: Binding<Double>,
        maxValue: Double,
        labels: [String]
    ) -> some View {
        VStack(spacing: LiquidSpacing.xs) {
            Slider(
                value: value,
                in: 0...maxValue,
                step: 1
            )

            HStack {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: Self.stepSliderLabelFontSize))
                        .foregroundStyle(.secondary)
                    if label != labels.last {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, Self.stepSliderLabelPadding)
        }
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button {
            applySettingsToConfig()
            Task { await viewModel.startExport() }
        } label: {
            Text("Export")
                .font(LiquidTypography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiquidSpacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Export video")
        .accessibilityHint("Starts exporting the video with the current settings")
    }

    /// Applies the UI-driven export settings to the ExportViewModel's config
    /// before starting the export.
    private func applySettingsToConfig() {
        let selectedResolution = resolutions[Int(resolutionIndex.rounded())]
        let selectedFps = fpsOptions[Int(fpsIndex.rounded())]

        // Map the selected resolution pixel height to an ExportResolution case
        let resolution: ExportResolution
        switch selectedResolution {
        case 540: resolution = .r480p
        case 720: resolution = .r720p
        case 1080: resolution = .r1080p
        case 2700: resolution = .r1440p
        case 3840: resolution = .r4K
        default: resolution = .r1080p
        }

        viewModel.config = viewModel.config.with(
            resolution: resolution,
            fps: selectedFps,
            bitrateMbps: bitrateValue,
            enableHdr: isHdr,
            audioOnly: exportAudioOnly
        )
    }

    // MARK: - Export Progress View

    private var exportProgressView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Large percentage text above video
            Text("\(Int(viewModel.progress * 100))%")
                .font(.system(size: Self.exportProgressFontSize, weight: .bold))
                .monospacedDigit()

            Text("Please don't close the app or lock your screen while exporting.")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidSpacing.xxxl)
                .padding(.top, LiquidSpacing.sm)
                .padding(.bottom, LiquidSpacing.xxxl)

            // Video preview with gradient progress border
            // GradientProgressBorderView is overlaid on top of the inner preview so
            // the arc sweeps clockwise from top-center as progress increases.
            ZStack {
                // Video preview area (inner)
                Group {
                    if let thumbnail = thumbnailImage {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Self.previewWidth, height: Self.previewHeight)
                            .clipShape(RoundedRectangle(cornerRadius: Self.previewInnerCornerRadius))
                    } else {
                        RoundedRectangle(cornerRadius: Self.previewInnerCornerRadius)
                            .fill(Color(.systemGray6))
                            .frame(width: Self.previewWidth, height: Self.previewHeight)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.system(size: Self.exportPlaceholderIconFontSize))
                                    .foregroundStyle(.secondary)
                            )
                    }
                }

                // Gradient progress border rendered via GradientProgressBorderView.
                // The border is sized slightly larger than the inner preview so it
                // sits flush around the outside of the clipped video frame.
                GradientProgressBorderView(
                    progress: viewModel.progress,
                    size: CGSize(width: Self.previewBorderWidth, height: Self.previewBorderHeight),
                    cornerRadius: Self.previewBorderCornerRadius,
                    strokeWidth: Self.previewBorderStrokeWidth
                )
            }
            .animation(.linear(duration: 0.1), value: viewModel.progress)

            // Status message below video
            if viewModel.isComplete {
                Text("Export Complete")
                    .font(LiquidTypography.headline)
                    .padding(.top, LiquidSpacing.xxl)

                if let url = viewModel.shareExportedVideo() {
                    ShareLink(item: url) {
                        Label("Share Video", systemImage: "square.and.arrow.up")
                            .font(LiquidTypography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, LiquidSpacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, LiquidSpacing.xxxl)
                    .padding(.top, LiquidSpacing.lg)
                }

                Button("Done") {
                    dismiss()
                }
                .padding(.top, LiquidSpacing.sm)
            } else {
                Text(statusMessage)
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, LiquidSpacing.xxl)

                Button("Cancel Export", role: .destructive) {
                    Task { await viewModel.cancelExport() }
                }
                .padding(.top, LiquidSpacing.sm)
                .accessibilityHint("Cancels the ongoing video export")
            }

            Spacer()
        }
    }

    // MARK: - Computed Properties

    private var currentResolutionLabel: String {
        resolutionLabels[Int(resolutionIndex.rounded())]
    }

    private var currentFps: Int {
        fpsOptions[Int(fpsIndex.rounded())]
    }

    private var statusMessage: String {
        if viewModel.progress >= Self.exportCompletionThreshold {
            return "Saving to Photos..."
        }
        return "Rendering video..."
    }

    private var estimatedFileSize: String {
        let durationSec = max(estimatedDurationSeconds, 1.0)
        let mbps = bitrateValue
        var sizeMB = (mbps / 8.0) * durationSec

        // Audio adds ~192kbps (~0.024 MB/s)
        let audioSizeMB = Self.audioSizeMbPerSecond * durationSec
        sizeMB += audioSizeMB

        if sizeMB >= 1024 {
            return String(format: "%.2f GB", sizeMB / 1024)
        }
        return String(format: "%.1f MB", sizeMB)
    }

    // MARK: - Error Categorization

    /// Produces a user-friendly error message from a raw export error.
    ///
    /// Inspects the error's localised description for keywords that identify
    /// common failure causes (storage, permissions, codec issues) and returns
    /// a clear, actionable string. Falls back to the raw description for
    /// unrecognised errors.
    ///
    /// - Parameter error: The error thrown by the export pipeline.
    /// - Returns: A localised, user-friendly error string.
    private func exportErrorMessage(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("space") || msg.contains("disk") {
            return "Not enough storage space. Free up space and try again."
        }
        if msg.contains("permission") || msg.contains("access") {
            return "Photos access denied. Enable in Settings > Privacy."
        }
        if msg.contains("codec") || msg.contains("format") {
            return "This video format is not supported for export."
        }
        return "Export failed: \(error.localizedDescription)"
    }
}

#Preview {
    ExportSheet()
}
