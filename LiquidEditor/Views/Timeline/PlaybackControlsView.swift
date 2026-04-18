// PlaybackControlsView.swift
// LiquidEditor
//
// Transport controls row rebuilt on TransportButton + SF Mono timecode.
//
// Layout: [undo][redo] ·· [skip-back][play/pause][skip-forward] ·· [time]
// Row height is FormFactor-adaptive (56pt iPhone / 64pt iPad).
// Background: LiquidMaterials.chrome with a hairline divider on top.
//
// Pure SwiftUI, iOS 26 native styling.

import SwiftUI

// MARK: - PlaybackControlsView

struct PlaybackControlsView: View {

    // MARK: - Dependencies

    @Bindable var viewModel: PlaybackViewModel

    /// Editor view model for undo/redo access.
    @Bindable var editorViewModel: EditorViewModel

    @Environment(\.formFactor) private var formFactor

    // MARK: - Body

    var body: some View {
        HStack(spacing: LiquidSpacing.md) {
            // Left: undo / redo
            TransportButton(
                systemName: "arrow.uturn.backward",
                kind: .secondary,
                accessibilityLabel: "Undo"
            ) {
                editorViewModel.undo()
            }
            .disabled(!editorViewModel.canUndo)
            .opacity(editorViewModel.canUndo ? 1.0 : 0.4)

            TransportButton(
                systemName: "arrow.uturn.forward",
                kind: .secondary,
                accessibilityLabel: "Redo"
            ) {
                editorViewModel.redo()
            }
            .disabled(!editorViewModel.canRedo)
            .opacity(editorViewModel.canRedo ? 1.0 : 0.4)

            Spacer(minLength: LiquidSpacing.lg)

            // Center: transport
            TransportButton(
                systemName: "gobackward.5",
                kind: .secondary,
                accessibilityLabel: "Skip back 5 seconds"
            ) {
                viewModel.seekBackward()
            }

            TransportButton(
                systemName: viewModel.isPlaying ? "pause.fill" : "play.fill",
                kind: .primary,
                accessibilityLabel: viewModel.isPlaying ? "Pause" : "Play"
            ) {
                viewModel.togglePlayPause()
            }

            TransportButton(
                systemName: "goforward.5",
                kind: .secondary,
                accessibilityLabel: "Skip forward 5 seconds"
            ) {
                viewModel.seekForward()
            }

            Spacer(minLength: LiquidSpacing.lg)

            // Right: time display
            VStack(alignment: .trailing, spacing: 1) {
                Text(viewModel.formattedCurrentTime)
                    .font(LiquidTypography.MonoLarge.font)
                    .foregroundStyle(LiquidColors.Text.primary)
                    .monospacedDigit()
                Text(viewModel.formattedTotalDuration)
                    .font(LiquidTypography.Mono.font)
                    .foregroundStyle(LiquidColors.Text.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Time \(viewModel.formattedCurrentTime) of \(viewModel.formattedTotalDuration)")
        }
        .padding(.horizontal, LiquidSpacing.lg)
        .frame(height: formFactor.playbackControlsHeight)
        .background(LiquidMaterials.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LiquidStroke.hairlineColor)
                .frame(height: LiquidStroke.hairlineWidth)
        }
    }
}
