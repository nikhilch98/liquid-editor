// PlaybackControlsView.swift
// LiquidEditor
//
// CapCut-style playback controls row.
//
// Layout: play/pause (left) | stacked time display (center) | keyframe + undo/redo (right)
//
// Pure SwiftUI, iOS 26 native styling. No glass background (transparent).

import SwiftUI

// MARK: - PlaybackControlsView

struct PlaybackControlsView: View {

    // MARK: - Dependencies

    @Bindable var viewModel: PlaybackViewModel

    /// Editor view model for keyframe and undo/redo access.
    @Bindable var editorViewModel: EditorViewModel

    // MARK: - Body

    var body: some View {
        ZStack {
            // Stacked time display (absolutely centered)
            timeDisplay

            // Left and right controls
            HStack {
                // Play/Pause button (left, 32pt icon)
                playPauseButton

                Spacer()

                // Right side: Keyframe + Undo/Redo
                HStack(spacing: 0) {
                    keyframeButton
                    undoButton
                    redoButton
                }
            }
        }
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback controls")
    }

    // MARK: - Play/Pause Button

    private var playPauseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.togglePlayPause()
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
        .accessibilityHint(viewModel.isPlaying ? "Pauses video playback" : "Starts video playback")
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        VStack(spacing: 1) {
            Text(viewModel.formattedCurrentTime)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)

            Text(viewModel.formattedTotalDuration)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time: \(viewModel.formattedCurrentTime) of \(viewModel.formattedTotalDuration)")
    }

    // MARK: - Keyframe Button

    private var keyframeButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            editorViewModel.toggleKeyframeAtCurrentTime()
        } label: {
            ZStack {
                // Background when active
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        editorViewModel.hasKeyframeAtCurrentTime
                        ? Color.yellow.opacity(0.15)
                        : Color.clear
                    )
                    .frame(width: 28, height: 28)

                // Diamond shape
                diamondShape
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))

                // Plus/minus indicator
                Image(
                    systemName: editorViewModel.hasKeyframeAtCurrentTime
                        ? "minus"
                        : "plus"
                )
                .font(.system(size: 11))
                .foregroundStyle(
                    editorViewModel.hasKeyframeAtCurrentTime
                    ? .black
                    : .white.opacity(0.8)
                )
            }
            .frame(width: LiquidSpacing.minTouchTarget, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(editorViewModel.hasKeyframeAtCurrentTime ? "Remove keyframe" : "Add keyframe")
        .accessibilityHint("Toggles keyframe at current playhead position")
    }

    /// Diamond shape for keyframe indicator.
    private var diamondShape: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                editorViewModel.hasKeyframeAtCurrentTime
                ? Color.yellow
                : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        editorViewModel.hasKeyframeAtCurrentTime
                        ? Color.yellow
                        : Color.white.opacity(0.6),
                        lineWidth: 2
                    )
            )
    }

    // MARK: - Undo/Redo Buttons

    private var undoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editorViewModel.undo()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 22))
                .foregroundStyle(
                    editorViewModel.canUndo
                    ? .white.opacity(0.9)
                    : .white.opacity(0.3)
                )
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editorViewModel.canUndo)
        .accessibilityLabel("Undo")
        .accessibilityHint(editorViewModel.canUndo ? "Undoes the last edit" : "No actions to undo")
    }

    private var redoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editorViewModel.redo()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 22))
                .foregroundStyle(
                    editorViewModel.canRedo
                    ? .white.opacity(0.9)
                    : .white.opacity(0.3)
                )
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!editorViewModel.canRedo)
        .accessibilityLabel("Redo")
        .accessibilityHint(editorViewModel.canRedo ? "Redoes the last undone edit" : "No actions to redo")
    }
}
