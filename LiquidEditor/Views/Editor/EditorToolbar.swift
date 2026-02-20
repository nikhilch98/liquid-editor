// EditorToolbar.swift
// LiquidEditor
//
// Bottom toolbar with tab selection and context-specific tool buttons.
// Uses .ultraThinMaterial for iOS Liquid Glass styling.
// Each tab presents a different set of editing tools.
//
// Layout (top to bottom):
//   1. Scrollable tool buttons row (context-specific to active tab)
//   2. Divider
//   3. Tab bar (icons only, no text labels)

import SwiftUI

// MARK: - EditorToolbar

/// Bottom toolbar with tabs and context-sensitive tool buttons.
///
/// Matches the Flutter `EditorBottomToolbar` layout:
/// Tools row -> Divider -> Tab bar (icons only).
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

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Context-specific tool buttons (above divider)
                toolButtonsForActiveTab
                    .padding(.horizontal, LiquidSpacing.md)
                    .padding(.vertical, LiquidSpacing.sm)

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.horizontal, LiquidSpacing.lg)

                // Tab bar (icons only, no text labels)
                tabBar
                    .padding(.horizontal, LiquidSpacing.md)
                    .padding(.vertical, 6)
                    .padding(.bottom, max(LiquidSpacing.sm, geometry.safeAreaInsets.bottom))
            }
            .background(.ultraThinMaterial)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editor toolbar")
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(EditorTab.allCases, id: \.self) { tab in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.activeTab = tab
                    }
                } label: {
                    Image(
                        systemName: viewModel.activeTab == tab
                            ? tab.activeIconName
                            : tab.iconName
                    )
                    .font(.system(size: 24))
                    .foregroundStyle(
                        viewModel.activeTab == tab
                        ? Color.orange
                        : LiquidColors.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: LiquidSpacing.timelineTrackHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tab.displayName) tab")
                .accessibilityAddTraits(viewModel.activeTab == tab ? .isSelected : [])
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
                    editTools
                case .fx:
                    fxTools
                case .overlay:
                    overlayTools
                case .audio:
                    audioTools
                case .smart:
                    smartTools
                }
            }
            .padding(.horizontal, LiquidSpacing.xs)
        }
        .frame(height: LiquidSpacing.timelineTrackHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(viewModel.activeTab.displayName) tools")
    }

    // MARK: - Edit Tab Tools

    private var editTools: some View {
        Group {
            toolButton(icon: "rectangle.split.2x1", label: "Trim") {
                viewModel.toggleTrimMode()
            }
            toolButton(icon: "scissors", label: "Split") {
                viewModel.splitAtPlayhead()
            }
            toolButton(icon: "doc.on.doc", label: "Copy") {
                viewModel.duplicateSelected()
            }
            toolButton(icon: "trash", label: "Delete", isDestructive: true) {
                viewModel.deleteSelected()
            }
            toolButton(icon: "square.3.layers.3d", label: "Tracks") {
                viewModel.setActivePanel(.trackManagement)
            }
        }
    }

    // MARK: - FX Tab Tools

    private var fxTools: some View {
        Group {
            toolButton(icon: "camera.filters", label: "Filters") {
                viewModel.setActivePanel(.videoEffects)
            }
            toolButton(icon: "sparkles", label: "Effects") {
                viewModel.setActivePanel(.videoEffects)
            }
            toolButton(icon: "square.on.square", label: "Transition") {
                viewModel.setActivePanel(.transition)
            }
            toolButton(icon: "tuningfork", label: "Adjust") {
                viewModel.setActivePanel(.colorGrading)
            }
            toolButton(icon: "crop", label: "Crop") {
                viewModel.setActivePanel(.crop)
            }
        }
    }

    // MARK: - Overlay Tab Tools

    private var overlayTools: some View {
        Group {
            toolButton(icon: "textformat", label: "Text") {
                viewModel.setActivePanel(.textEditor)
            }
            toolButton(icon: "face.smiling", label: "Sticker") {
                viewModel.setActivePanel(.stickerPicker)
            }
        }
    }

    // MARK: - Audio Tab Tools

    private var audioTools: some View {
        Group {
            toolButton(icon: "speaker.wave.2", label: "Volume") {
                viewModel.setActivePanel(.volume)
            }
            toolButton(icon: "gauge.with.dots.needle.33percent", label: "Speed") {
                viewModel.setActivePanel(.speed)
            }
            // Voice/mic button — wired to recording or custom callback
            voiceButton
            if let playbackViewModel {
                toolButton(icon: "speaker.slash", label: "Mute") {
                    playbackViewModel.toggleMute()
                }
            }
        }
    }

    // MARK: - Voice Button

    /// Voice/mic button with live recording indicator.
    ///
    /// When recording is active the icon is replaced by a pulsing red circle.
    private var voiceButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
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
                        .font(.system(size: 22))
                        .frame(width: 28, height: 28)
                }
                Text("Voice")
                    .font(.system(size: 10, weight: viewModel.isRecording ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(viewModel.isRecording ? Color.red : LiquidColors.textSecondary)
            .frame(width: 60)
            .padding(.vertical, 6)
            .background(
                viewModel.isRecording
                ? RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.15))
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

    private var smartTools: some View {
        Group {
            toolButton(
                icon: "person.crop.rectangle",
                label: "Track",
                isActive: viewModel.isTrackingActive
            ) {
                viewModel.setActivePanel(.personSelection)
            }
            toolButton(icon: "crop", label: "Reframe") {
                viewModel.setActivePanel(.autoReframe)
            }
            toolButton(
                icon: "ant",
                label: "Debug",
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

    // MARK: - Tool Button Builder

    /// Creates a standard tool button with icon and label.
    ///
    /// Supports active state (orange highlight) and destructive (red) styling
    /// matching the Flutter `_ToolButton` widget.
    private func toolButton(
        icon: String,
        label: String,
        isActive: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            VStack(spacing: LiquidSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(width: 28, height: 28)
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(toolButtonColor(isActive: isActive, isDestructive: isDestructive))
            .frame(width: 60)
            .padding(.vertical, 6)
            .background(
                isActive
                ? RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Determine tool button foreground color based on state.
    private func toolButtonColor(isActive: Bool, isDestructive: Bool) -> Color {
        if isDestructive { return LiquidColors.error }
        if isActive { return .orange }
        return LiquidColors.textSecondary
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
