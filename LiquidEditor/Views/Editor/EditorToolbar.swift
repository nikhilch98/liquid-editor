// EditorToolbar.swift
// LiquidEditor
//
// Bottom toolbar with tab selection and context-specific tool buttons.
// Uses ToolButton + TabBarItem from the 2026-04-18 premium UI design.
//
// Layout (top to bottom):
//   1. Scrollable tool buttons row (context-specific to active tab)
//   2. Divider
//   3. Tab bar (TabBarItem cells with amber pill indicator)

import SwiftUI

// MARK: - EditorToolbar

/// Bottom toolbar with tabs and context-sensitive tool buttons.
///
/// Top row: horizontally-scrolling ToolButton cells for the active tab's
/// tools. Bottom row: five TabBarItem cells animated with LiquidMotion.bounce.
struct EditorToolbar: View {

    // MARK: - Properties

    /// The editor view model (bindable for tab/panel changes).
    @Bindable var viewModel: EditorViewModel

    /// Optional playback view model for mute toggle.
    var playbackViewModel: PlaybackViewModel?

    /// Optional voice/mic tap callback. When provided, the Voice button
    /// calls this instead of opening the audio-effects panel.
    var onVoice: (() -> Void)?

    /// Optional track-debug tap callback. When provided, the Debug button
    /// calls this; otherwise the viewModel.toggleTrackDebug() is used.
    var onTrackDebug: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Top row: context tool buttons
            toolButtonsForActiveTab
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.sm)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.horizontal, LiquidSpacing.lg)

            // Tab bar
            tabBar
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs)
                .padding(.bottom, safeBottomInset)
        }
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor toolbar")
    }

    // MARK: - Safe Bottom Inset

    private var safeBottomInset: CGFloat {
        max(LiquidSpacing.sm, 8)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(EditorTab.allCases, id: \.self) { tab in
                TabBarItem(
                    systemName: viewModel.activeTab == tab ? tab.activeIconName : tab.iconName,
                    label: tab.displayName,
                    isActive: viewModel.activeTab == tab
                ) {
                    withAnimation(.liquid(LiquidMotion.smooth, reduceMotion: reduceMotion)) {
                        viewModel.activeTab = tab
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor tabs")
    }

    // MARK: - Tool Buttons

    @ViewBuilder
    private var toolButtonsForActiveTab: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.xs) {
                switch viewModel.activeTab {
                case .edit:
                    editTabTools
                case .fx:
                    fxTabTools
                case .overlay:
                    overlayTabTools
                case .audio:
                    audioTabTools
                case .smart:
                    smartTabTools
                }
            }
            .padding(.horizontal, LiquidSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(viewModel.activeTab.displayName) tools")
    }

    // MARK: - Edit Tab Tools

    @ViewBuilder
    private var editTabTools: some View {
        ToolButton(systemName: "scissors", caption: "Split", isActive: false) {
            viewModel.splitAtPlayhead()
        }
        ToolButton(
            systemName: "arrow.left.and.right.square",
            caption: "Trim",
            isActive: viewModel.isTrimMode
        ) {
            viewModel.isTrimMode.toggle()
        }
        ToolButton(systemName: "doc.on.doc", caption: "Copy", isActive: false) {
            viewModel.duplicateSelected()
        }
        ToolButton(systemName: "trash", caption: "Delete", isActive: false) {
            viewModel.deleteSelected()
        }
        ToolButton(
            systemName: "square.stack.3d.up",
            caption: "Tracks",
            isActive: viewModel.activePanel == .trackManagement
        ) {
            viewModel.activePanel = (viewModel.activePanel == .trackManagement) ? .none : .trackManagement
        }
    }

    // MARK: - FX Tab Tools

    @ViewBuilder
    private var fxTabTools: some View {
        ToolButton(
            systemName: "camera.filters",
            caption: "Filters",
            isActive: viewModel.activePanel == .videoEffects
        ) {
            viewModel.setActivePanel(.videoEffects)
        }
        ToolButton(
            systemName: "sparkles",
            caption: "Effects",
            isActive: viewModel.activePanel == .videoEffects
        ) {
            viewModel.setActivePanel(.videoEffects)
        }
        ToolButton(
            systemName: "square.on.square",
            caption: "Transition",
            isActive: viewModel.activePanel == .transition
        ) {
            viewModel.setActivePanel(.transition)
        }
        ToolButton(
            systemName: "tuningfork",
            caption: "Adjust",
            isActive: viewModel.activePanel == .colorGrading
        ) {
            viewModel.setActivePanel(.colorGrading)
        }
        ToolButton(
            systemName: "crop",
            caption: "Crop",
            isActive: viewModel.activePanel == .crop
        ) {
            viewModel.setActivePanel(.crop)
        }
    }

    // MARK: - Overlay Tab Tools

    @ViewBuilder
    private var overlayTabTools: some View {
        ToolButton(
            systemName: "textformat",
            caption: "Text",
            isActive: viewModel.activePanel == .textEditor
        ) {
            viewModel.setActivePanel(.textEditor)
        }
        ToolButton(
            systemName: "face.smiling",
            caption: "Sticker",
            isActive: viewModel.activePanel == .stickerPicker
        ) {
            viewModel.setActivePanel(.stickerPicker)
        }
    }

    // MARK: - Audio Tab Tools

    @ViewBuilder
    private var audioTabTools: some View {
        ToolButton(
            systemName: "speaker.wave.2",
            caption: "Volume",
            isActive: viewModel.activePanel == .volume
        ) {
            viewModel.setActivePanel(.volume)
        }
        ToolButton(
            systemName: "gauge.with.dots.needle.33percent",
            caption: "Speed",
            isActive: viewModel.activePanel == .speed
        ) {
            viewModel.setActivePanel(.speed)
        }
        // Voice/mic button — wired to recording or custom callback
        voiceButton
        if let playbackViewModel {
            ToolButton(systemName: "speaker.slash", caption: "Mute", isActive: false) {
                playbackViewModel.toggleMute()
            }
        }
    }

    // MARK: - Voice Button

    /// Voice/mic button with live recording indicator.
    ///
    /// When recording is active the icon is replaced by a pulsing red circle.
    private var voiceButton: some View {
        Button {
            HapticService.shared.play(.selection)
            if let onVoice {
                onVoice()
            } else {
                viewModel.toggleVoiceoverRecording()
            }
        } label: {
            VStack(spacing: LiquidSpacing.xxs) {
                if viewModel.isRecording {
                    RecordingIndicator()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                Text("Voice")
                    .font(.system(size: 11, weight: viewModel.isRecording ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(viewModel.isRecording ? Color.red : LiquidColors.Text.secondary)
            .frame(width: 60)
            .padding(.vertical, 6)
            .background(
                viewModel.isRecording
                ? RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.15))
                : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voice recording")
        .accessibilityValue(viewModel.isRecording ? "Recording" : "Stopped")
        .accessibilityHint(viewModel.isRecording ? "Tap to stop recording" : "Tap to start voiceover recording")
        .accessibilityAddTraits(viewModel.isRecording ? .isSelected : [])
    }

    // MARK: - Smart Tab Tools

    @ViewBuilder
    private var smartTabTools: some View {
        ToolButton(
            systemName: "person.crop.rectangle",
            caption: "Track",
            isActive: viewModel.isTrackingActive
        ) {
            viewModel.setActivePanel(.personSelection)
        }
        ToolButton(
            systemName: "crop",
            caption: "Reframe",
            isActive: viewModel.activePanel == .autoReframe
        ) {
            viewModel.setActivePanel(.autoReframe)
        }
        ToolButton(
            systemName: "ant",
            caption: "Debug",
            isActive: viewModel.isTrackDebugActive
        ) {
            if let onTrackDebug {
                onTrackDebug()
            } else {
                viewModel.toggleTrackDebug()
            }
        }
    }
}

// MARK: - RecordingIndicator

/// Animated pulsing red circle shown in the voice button while recording is active.
private struct RecordingIndicator: View {

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(Color.red.opacity(isPulsing ? 0.0 : 0.3))
                .scaleEffect(isPulsing ? 1.6 : 1.0)

            // Inner solid circle
            Circle()
                .fill(Color.red)
                .scaleEffect(0.55)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
    }
}
