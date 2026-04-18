// EditorView.swift
// LiquidEditor
//
// Main editor interface. Combines video preview, timeline,
// and context-sensitive toolbar into a full-screen editing experience.
//
// Layout (top to bottom):
//   1. Navigation bar (close, project name + dropdown, more, 2K, export)
//   2. Video preview (flexible, aspect-fit, with comparison + fullscreen triggers)
//   3. Playback controls row (play/pause, time, keyframe, undo/redo)
//   4. Timeline area OR inline tool panel
//   5. Editor toolbar (tabs + tool buttons)

import AVFoundation
import PhotosUI
import SwiftUI

// MARK: - EditorView

/// The main editor screen.
///
/// Manages the overall layout and coordinates between the video preview,
/// timeline, and toolbar sections. Uses `EditorViewModel` as the single
/// source of truth for editor state.
struct EditorView: View {

    // MARK: - State

    @State private var viewModel: EditorViewModel

    /// Timeline view model for the timeline UI.
    @State private var timelineViewModel: TimelineViewModel

    /// Playback view model bridging the PlaybackEngine with the UI.
    @State private var playbackViewModel: PlaybackViewModel

    /// Auto-reframe engine for the auto-reframe panel.
    @State private var autoReframeEngine = AutoReframeEngine()

    /// Selected person indices for person selection sheet.
    @State private var selectedPersonIndices: Set<Int> = []

    /// Thumbnail image generated from the current video for export preview.
    @State private var exportThumbnail: UIImage?

    /// Pending PhotosPicker selection for attaching media to the project.
    @State private var pendingImportItem: PhotosPickerItem?

    /// Dismiss action for navigation.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    /// Creates an editor view for the given project.
    ///
    /// - Parameter project: The project to edit.
    init(project: Project) {
        let editorVM = EditorViewModel(project: project)
        _viewModel = State(initialValue: editorVM)
        _timelineViewModel = State(
            initialValue: TimelineViewModel(
                timeline: editorVM.timeline,
                tracks: [Self.defaultMainVideoTrack]
            )
        )
        _playbackViewModel = State(initialValue: PlaybackViewModel())
    }

    /// Default single "Main Video" track used before the project is loaded
    /// and as the minimum lane for the timeline UI.
    private static var defaultMainVideoTrack: Track {
        Track(
            id: "main-video",
            name: TrackType.mainVideo.displayName,
            type: .mainVideo,
            index: 0
        )
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let formFactor = FormFactor(canvasSize: geometry.size)
            VStack(spacing: 0) {
                // Navigation bar
                editorNavigationBar

                if viewModel.isLoading {
                    // Loading state
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    // Error state
                    errorView(message: errorMessage)
                } else {
                    // Video preview (takes available space)
                    VideoPreviewView(
                        player: viewModel.player,
                        currentTime: viewModel.currentTime,
                        isPlaying: viewModel.isPlaying,
                        isTrackingActive: viewModel.isTrackingActive,
                        trackingBoundingBoxes: viewModel.currentTrackingBoxes,
                        isComparisonMode: viewModel.isComparisonMode,
                        videoAspectRatio: currentVideoAspectRatio,
                        onTogglePlayPause: { viewModel.togglePlayPause() },
                        onToggleComparison: { viewModel.isComparisonMode.toggle() },
                        onFullscreen: { viewModel.showFullscreenPreview = true }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight(for: geometry))
                    .overlay {
                        if showImportCTA {
                            importMediaCTA
                        }
                    }
                    .onChange(of: viewModel.currentTime) { _, newTime in
                        let ms = Int(newTime / 1_000)
                        Task { await viewModel.updateTrackingBoxes(for: ms) }
                    }

                    // Playback controls row (CapCut style)
                    PlaybackControlsView(
                        viewModel: playbackViewModel,
                        editorViewModel: viewModel
                    )

                    // Timeline OR inline tool panel
                    if viewModel.activePanel.isPresented {
                        toolPanelInline
                            .frame(maxWidth: .infinity)
                            .frame(height: timelineHeight(for: geometry))
                    } else {
                        timelineContent
                            .frame(maxWidth: .infinity)
                            .frame(height: timelineHeight(for: geometry))
                    }

                    // Toolbar
                    EditorToolbar(viewModel: viewModel, playbackViewModel: playbackViewModel)
                }
            }
            .environment(\.formFactor, formFactor)
            .overlay {
                // Hidden keyboard shortcut buttons
                keyboardShortcutButtons
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(white: 0.12),
                        Color(white: 0.08),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .topLeading) {
            if viewModel.showProjectSettingsDropdown {
                projectSettingsDropdown
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            // Bind the transport-controls VM to the shared PlaybackEngine
            // BEFORE loadProject so tap handlers on the play/seek buttons
            // route through to the engine as soon as media is ready.
            playbackViewModel.bind(to: ServiceContainer.shared.playbackEngine)
            await viewModel.loadProject()
            syncTimelineViewModel()
        }
        // Keep EditorViewModel.timeline in lock-step with any edits the user
        // makes through the TimelineView (drag, trim). This propagates the
        // mutation back to the single source of truth used for composition
        // rebuilds and auto-save.
        .onChange(of: timelineViewModel.timeline) { _, newTimeline in
            viewModel.timeline = newTimeline
        }
        // Rebuild the composition whenever the timeline changes — but defer
        // the (relatively expensive) AVComposition rebuild until the user
        // finishes their interactive gesture so dragging and trimming stay
        // at 60 FPS.
        .onChange(of: viewModel.timeline) { _, _ in
            scheduleCompositionRebuildIfIdle()
        }
        .onChange(of: timelineViewModel.isDragging) { _, isDragging in
            if !isDragging { scheduleCompositionRebuildIfIdle() }
        }
        .onChange(of: timelineViewModel.isTrimming) { _, isTrimming in
            if !isTrimming { scheduleCompositionRebuildIfIdle() }
        }
        .onChange(of: pendingImportItem) { _, newItem in
            guard let newItem else { return }
            pendingImportItem = nil
            Task {
                await handlePickedVideo(newItem)
            }
        }
        .sheet(isPresented: $viewModel.showExportSheet) {
            exportSheet
        }
        .onChange(of: viewModel.showExportSheet) { _, isPresented in
            if isPresented {
                generateExportThumbnail()
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            settingsSheet
        }
        .sheet(isPresented: $viewModel.isTrackDebugActive) {
            TrackDebugSheet(
                sessionId: viewModel.activeTrackingSessionId ?? "",
                onClose: { viewModel.isTrackDebugActive = false }
            )
        }
        .fullScreenCover(isPresented: $viewModel.showFullscreenPreview) {
            FullscreenPreviewView(
                totalDuration: viewModel.totalDuration,
                player: viewModel.player
            )
        }
    }

    // MARK: - Keyboard Shortcuts

    /// Hidden buttons that provide keyboard shortcut bindings for common editor actions.
    private var keyboardShortcutButtons: some View {
        Group {
            Button("") { viewModel.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])

            Button("") { viewModel.undo() }
                .keyboardShortcut("z", modifiers: .command)

            Button("") { viewModel.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])

            Button("") { viewModel.splitAtPlayhead() }
                .keyboardShortcut("b", modifiers: .command)

            Button("") { viewModel.deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])

            Button("") { viewModel.showExportSheet = true }
                .keyboardShortcut("e", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: - Navigation Bar

    private var editorNavigationBar: some View {
        HStack(spacing: LiquidSpacing.sm) {
            // Close
            IconButton(systemName: "xmark", accessibilityLabel: "Close editor") {
                dismiss()
            }

            Rectangle()
                .fill(LiquidStroke.hairlineColor)
                .frame(width: LiquidStroke.hairlineWidth, height: 20)

            // Project name + settings dropdown trigger
            Button {
                withAnimation(.liquid(LiquidMotion.smooth, reduceMotion: false)) {
                    viewModel.showProjectSettingsDropdown.toggle()
                }
                HapticService.shared.play(.tapSecondary)
            } label: {
                HStack(spacing: LiquidSpacing.xs) {
                    Text(viewModel.project.name)
                        .font(LiquidTypography.Title.font)
                        .foregroundStyle(LiquidColors.Text.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LiquidColors.Text.secondary)
                        .rotationEffect(.degrees(viewModel.showProjectSettingsDropdown ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Project settings. Current project: \(viewModel.project.name)")

            Spacer(minLength: LiquidSpacing.sm)

            // More menu
            IconButton(systemName: "ellipsis", accessibilityLabel: "More options") {
                // placeholder -- existing menu logic can hang off showProjectSettingsDropdown
                viewModel.showProjectSettingsDropdown.toggle()
            }

            // Resolution chip
            GlassPill(label: resolutionLabel)
                .accessibilityLabel("Resolution \(resolutionLabel)")

            // Export CTA
            PrimaryCTA(title: "Export") {
                viewModel.showExportSheet = true
            }
        }
        .padding(.horizontal, LiquidSpacing.md)
        .frame(height: 52)
        .background(LiquidMaterials.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LiquidStroke.hairlineColor)
                .frame(height: LiquidStroke.hairlineWidth)
        }
    }

    /// Label for the resolution chip. Pulled from the project settings or
    /// falls back to 2K if unknown.
    private var resolutionLabel: String {
        "2K"
    }

    // MARK: - Project Settings Dropdown

    private var projectSettingsDropdown: some View {
        ZStack(alignment: .topLeading) {
            // Dismiss backdrop (tapping outside closes dropdown)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showProjectSettingsDropdown = false
                    }
                }
                .ignoresSafeArea()

            // Dropdown menu
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showProjectSettingsDropdown = false
                    }
                    // Rename action placeholder
                } label: {
                    Label("Rename", systemImage: "pencil")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LiquidSpacing.lg)
                        .padding(.vertical, LiquidSpacing.md)
                }
                .buttonStyle(.plain)

                Divider()
                    .background(Color.white.opacity(0.1))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showProjectSettingsDropdown = false
                    }
                    viewModel.showSettings = true
                } label: {
                    Label("Project Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LiquidSpacing.lg)
                        .padding(.vertical, LiquidSpacing.md)
                }
                .buttonStyle(.plain)

                Divider()
                    .background(Color.white.opacity(0.1))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.showProjectSettingsDropdown = false
                    }
                    // Duplicate action placeholder
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LiquidSpacing.lg)
                        .padding(.vertical, LiquidSpacing.md)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .font(LiquidTypography.subheadline)
            .frame(width: 200)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.top, 48)
            .padding(.leading, 44)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: LiquidSpacing.xl) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Loading video...")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading video")
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: LiquidSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LiquidColors.warning.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(LiquidColors.warning)
            }
            .accessibilityHidden(true)

            Text("Could not load video")
                .font(LiquidTypography.title3)
                .foregroundStyle(.white)

            Text(message)
                .font(LiquidTypography.caption)
                .foregroundStyle(LiquidColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiquidSpacing.xxxl)

            HStack(spacing: LiquidSpacing.md) {
                Button {
                    dismiss()
                } label: {
                    Text("Go Back")
                        .font(LiquidTypography.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, LiquidSpacing.xl)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go back")
                .accessibilityHint("Returns to the previous screen")

                Button {
                    viewModel.loadVideo()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                        Text("Retry")
                            .font(LiquidTypography.subheadlineSemibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, LiquidSpacing.xl)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry loading video")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error loading video: \(message)")
    }

    // MARK: - Timeline

    private var timelineContent: some View {
        Group {
            if viewModel.timeline.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .fill(Color.white.opacity(0.05))
                        .padding(.horizontal, LiquidSpacing.sm)

                    VStack(spacing: LiquidSpacing.sm) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 28))
                            .foregroundStyle(LiquidColors.textSecondary)
                        Text("Add clips to get started")
                            .font(LiquidTypography.subheadline)
                            .foregroundStyle(LiquidColors.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Empty timeline. Add clips to get started.")
            } else {
                TimelineView(
                    viewModel: timelineViewModel,
                    playbackViewModel: playbackViewModel
                )
            }
        }
        .onAppear {
            syncTimelineViewModel()
        }
    }

    // MARK: - Inline Tool Panel

    @ViewBuilder
    private var toolPanelInline: some View {
        switch viewModel.activePanel {
        case .none:
            EmptyView()

        case .colorGrading:
            ColorGradingSheet { _ in
                viewModel.dismissPanel()
            }

        case .videoEffects:
            VideoEffectsSheet { _ in
                viewModel.dismissPanel()
            }

        case .crop:
            CropSheet { _, _, _, _ in
                viewModel.dismissPanel()
            }

        case .transition:
            TransitionPickerSheet(onApply: { _, _, _ in
                viewModel.dismissPanel()
            })

        case .audioEffects:
            AudioEffectsSheet { _, _ in
                viewModel.dismissPanel()
            }

        case .textEditor:
            TextEditorSheet { _ in
                viewModel.dismissPanel()
            }

        case .stickerPicker:
            StickerPickerSheet { _ in
                viewModel.dismissPanel()
            }

        case .volume:
            VolumeControlSheet { _, _, _, _ in
                viewModel.dismissPanel()
            }

        case .speed:
            SpeedControlSheet { _ in
                viewModel.dismissPanel()
            }

        case .trackManagement:
            TrackManagementSheet { _ in
                viewModel.dismissPanel()
            }

        case .keyframeEditor:
            if viewModel.hasKeyframeAtCurrentTime {
                KeyframeEditorSheet(
                    keyframe: Keyframe(
                        id: "keyframe-\(viewModel.currentTime)",
                        timestampMicros: viewModel.currentTime
                    ),
                    videoDurationMicros: viewModel.totalDuration,
                    onUpdate: { _ in viewModel.dismissPanel() },
                    onDelete: { _ in
                        viewModel.deleteKeyframeAtCurrentTime()
                        viewModel.dismissPanel()
                    },
                    onDuplicate: { _ in viewModel.dismissPanel() },
                    onResetTransform: {}
                )
            } else {
                ContentUnavailableView(
                    "No Clip Selected",
                    systemImage: "film",
                    description: Text("Select a clip to edit its keyframes")
                )
            }

        case .autoReframe:
            AutoReframePanel(
                engine: autoReframeEngine,
                onApply: { viewModel.dismissPanel() },
                onClose: { viewModel.dismissPanel() }
            )

        case .personSelection:
            PersonSelectionSheet(
                persons: [],
                selectedIndices: $selectedPersonIndices,
                onConfirm: { viewModel.dismissPanel() },
                onDismiss: { viewModel.dismissPanel() }
            )
        }
    }

    // MARK: - Sheet Views

    @ViewBuilder
    private var exportSheet: some View {
        ExportSheet(
            estimatedDurationSeconds: Double(viewModel.totalDuration) / 1_000_000.0,
            thumbnailImage: exportThumbnail
        )
    }

    @ViewBuilder
    private var settingsSheet: some View {
        SettingsView(
            preferencesRepository: RepositoryContainer.shared.preferencesRepository
        )
    }

    // MARK: - Sync

    /// Rebuild the playback composition unless the user is mid-gesture.
    /// Composition rebuilds re-decode source assets, which is expensive
    /// compared to a SwiftUI redraw; running it every frame of a drag would
    /// drop the timeline well below 60 FPS. Deferring until the gesture
    /// ends keeps scrubbing smooth while still producing an up-to-date
    /// AVPlayer by the time the user lifts their finger.
    private func scheduleCompositionRebuildIfIdle() {
        guard !timelineViewModel.isDragging,
              !timelineViewModel.isTrimming,
              !timelineViewModel.isScrubbingTimeline else {
            return
        }
        Task { await viewModel.rebuildComposition() }
    }

    /// Whether the preview area should show the "Import Media" empty-state
    /// overlay. True when the project has no playable source and we are not
    /// currently loading or showing an error.
    private var showImportCTA: Bool {
        viewModel.player == nil
            && !viewModel.isLoading
            && viewModel.errorMessage == nil
            && viewModel.project.sourceVideoPath.isEmpty
            && viewModel.project.clips.isEmpty
    }

    /// Centered Import Media button shown over the empty preview area.
    @ViewBuilder
    private var importMediaCTA: some View {
        VStack(spacing: LiquidSpacing.md) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))
            Text("This project has no media yet")
                .font(.headline)
                .foregroundStyle(.white)
            PhotosPicker(
                selection: $pendingImportItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Label("Import Media", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, LiquidSpacing.lg)
                    .padding(.vertical, LiquidSpacing.sm)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .accessibilityLabel("Import media into this project")
        }
        .padding(LiquidSpacing.lg)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Load the picked video's data, write it to a temp file, and hand it to
    /// EditorViewModel.attachSourceVideo. Removes the temp file after the
    /// attach completes.
    private func handlePickedVideo(_ item: PhotosPickerItem) async {
        do {
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                viewModel.errorMessage = "Could not load the selected video."
                return
            }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try videoData.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            await viewModel.attachSourceVideo(from: tempURL)
            syncTimelineViewModel()
        } catch {
            viewModel.errorMessage = "Could not import video: \(error.localizedDescription)"
        }
    }

    /// Synchronize the timeline view model with the editor's current timeline.
    /// Preserves existing tracks if any, falling back to a single Main Video
    /// track so the timeline always has at least one lane to render clips on.
    private func syncTimelineViewModel() {
        let tracks = timelineViewModel.tracks.isEmpty
            ? [Self.defaultMainVideoTrack]
            : timelineViewModel.tracks
        timelineViewModel = TimelineViewModel(
            timeline: viewModel.timeline,
            tracks: tracks
        )
        playbackViewModel.updateTotalDuration(viewModel.totalDuration)
    }

    // MARK: - Layout Helpers

    /// The current video's aspect ratio derived from the player's presentation size.
    private var currentVideoAspectRatio: CGFloat? {
        guard let size = viewModel.player?.currentItem?.presentationSize,
              size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }

    // MARK: - Layout Constants

    /// Navigation bar height.
    private static let navigationBarHeight: CGFloat = 44

    /// Playback controls row height.
    private static let playbackControlsHeight: CGFloat = 30

    /// Toolbar height (approximate).
    private static let toolbarHeight: CGFloat = 140

    /// Preview ratio of available content area.
    private static let previewHeightRatio: CGFloat = 0.55

    /// Timeline ratio of available content area.
    private static let timelineHeightRatio: CGFloat = 0.45

    /// Minimum preview height.
    private static let minPreviewHeight: CGFloat = 200

    /// Minimum timeline height.
    private static let minTimelineHeight: CGFloat = 120

    /// Calculate preview height based on available geometry.
    private func previewHeight(for geometry: GeometryProxy) -> CGFloat {
        let available = geometry.size.height
            - Self.navigationBarHeight
            - Self.playbackControlsHeight
            - Self.toolbarHeight
        return max(available * Self.previewHeightRatio, Self.minPreviewHeight)
    }

    /// Calculate timeline height based on available geometry.
    private func timelineHeight(for geometry: GeometryProxy) -> CGFloat {
        let available = geometry.size.height
            - Self.navigationBarHeight
            - Self.playbackControlsHeight
            - Self.toolbarHeight
        return max(available * Self.timelineHeightRatio, Self.minTimelineHeight)
    }

    // MARK: - Thumbnail Generation

    /// Generates a thumbnail from the current video asset at the current playhead time.
    ///
    /// Uses `AVAssetImageGenerator` to capture a frame. The work is performed
    /// off the main actor to avoid blocking the UI thread.
    private func generateExportThumbnail() {
        guard let asset = viewModel.player?.currentItem?.asset else {
            exportThumbnail = nil
            return
        }

        let currentTimeMicros = viewModel.currentTime
        let requestTime = CMTime(
            value: Int64(currentTimeMicros),
            timescale: 1_000_000
        )

        Task.detached {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 560, height: 400)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: requestTime)
                let image = UIImage(cgImage: cgImage)
                await MainActor.run {
                    exportThumbnail = image
                }
            } catch {
                await MainActor.run {
                    exportThumbnail = nil
                }
            }
        }
    }
}
