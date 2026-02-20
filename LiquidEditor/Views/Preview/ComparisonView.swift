// ComparisonView.swift
// LiquidEditor
//
// Before/after comparison view for video editing.
// Supports split screen, toggle, and side-by-side modes.
//
// Pure SwiftUI with iOS 26 native styling. Uses .ultraThinMaterial
// for translucent label overlays and native gestures.
//

import SwiftUI

// MARK: - ComparisonView

/// Displays before/after comparison of video content.
///
/// Shows the original (untransformed) content alongside the edited
/// (transformed) content in one of three modes:
///
/// - **Split Screen:** Draggable vertical divider reveals original
///   on the left and edited on the right.
/// - **Toggle:** Long-press shows original with crossfade animation;
///   release returns to edited.
/// - **Side by Side:** Two equal-width panels with labels.
///
/// When the mode is `.off`, only the edited content is displayed.
///
/// ## Usage
/// ```swift
/// ComparisonView(
///     originalContent: { originalPreview },
///     editedContent: { editedPreview },
///     config: $comparisonConfig
/// )
/// ```
struct ComparisonView<Original: View, Edited: View>: View {

    // MARK: - Properties

    /// Builder for the original (unmodified) content.
    let originalContent: Original

    /// Builder for the edited (with transforms/effects) content.
    let editedContent: Edited

    /// Current comparison configuration (mode, split position, toggle state).
    @Binding var config: ComparisonConfig

    // MARK: - Body

    var body: some View {
        switch config.mode {
        case .off:
            editedContent
        case .splitScreen:
            splitScreenView
        case .toggle:
            toggleView
        case .sideBySide:
            sideBySideView
        }
    }

    // MARK: - Split Screen Mode

    /// Split screen comparison with draggable divider.
    ///
    /// The edited content fills the entire frame as background.
    /// The original content is clipped to the left portion,
    /// determined by `config.splitPosition`.
    private var splitScreenView: some View {
        GeometryReader { geometry in
            let splitX = geometry.size.width * config.splitPosition

            ZStack {
                // Full-frame: edited content (background)
                editedContent

                // Clipped: original content (left portion)
                originalContent
                    .clipShape(
                        SplitClipShape(splitPosition: config.splitPosition)
                    )

                // Divider handle
                splitDivider(splitX: splitX, height: geometry.size.height)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newPosition = value.location.x / geometry.size.width
                                config = config.copyWith(
                                    splitPosition: min(max(newPosition, 0.1), 0.9)
                                )
                            }
                            .onEnded { _ in
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    )

                // Labels
                ComparisonGlassLabel(text: "Original")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, LiquidSpacing.sm)
                    .padding(.leading, LiquidSpacing.sm)

                ComparisonGlassLabel(text: "Edited")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, LiquidSpacing.sm)
                    .padding(.trailing, LiquidSpacing.sm)
            }
        }
    }

    /// The draggable vertical divider line with circular handle.
    private func splitDivider(splitX: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // White vertical line (3pt wide)
            Rectangle()
                .fill(Color.white)
                .frame(width: 3, height: height)

            // Circular handle with arrow icon
            Circle()
                .fill(Color.white)
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.3), radius: 4)
                .overlay {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                }
        }
        .position(x: splitX, y: height / 2)
        .contentShape(Rectangle().size(width: LiquidSpacing.minTouchTarget, height: height))
        .accessibilityElement()
        .accessibilityLabel("Split divider")
        .accessibilityHint("Drag left or right to adjust comparison split position")
        .accessibilityValue("\(Int(config.splitPosition * 100)) percent from left")
        .accessibilityAdjustableAction { direction in
            let step: Double = 0.05
            switch direction {
            case .increment:
                config = config.copyWith(splitPosition: min(config.splitPosition + step, 0.9))
            case .decrement:
                config = config.copyWith(splitPosition: max(config.splitPosition - step, 0.1))
            @unknown default:
                break
            }
        }
    }

    // MARK: - Toggle Mode

    /// Toggle comparison with long-press gesture.
    ///
    /// Long-pressing shows the original content with a 200ms crossfade.
    /// Releasing returns to the edited content.
    private var toggleView: some View {
        ZStack {
            // Crossfade between edited and original
            if config.showingOriginal {
                originalContent
                    .transition(.opacity)
            } else {
                editedContent
                    .transition(.opacity)
            }

            // Indicator pill
            VStack {
                HStack(spacing: LiquidSpacing.xs) {
                    Image(systemName: config.showingOriginal ? "eye.slash" : "eye")
                        .font(.system(size: 10, weight: .semibold))
                    Text(config.showingOriginal ? "Original" : "Edited")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, LiquidSpacing.sm)
                .padding(.vertical, LiquidSpacing.xs)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(config.showingOriginal ? "Showing original" : "Showing edited")

                Spacer()
            }
            .padding(.top, LiquidSpacing.sm)
        }
        .animation(.easeInOut(duration: 0.2), value: config.showingOriginal)
        .onLongPressGesture(
            minimumDuration: .infinity,
            pressing: { isPressing in
                if isPressing {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                config = config.copyWith(showingOriginal: isPressing)
            },
            perform: {}
        )
        .accessibilityHint("Long-press to temporarily show original content")
    }

    // MARK: - Side by Side Mode

    /// Side-by-side comparison with two equal panels.
    private var sideBySideView: some View {
        HStack(spacing: 0) {
            // Original panel
            ZStack(alignment: .topLeading) {
                originalContent
                    .clipped()

                ComparisonGlassLabel(text: "Original")
                    .padding(.top, LiquidSpacing.xs)
                    .padding(.leading, LiquidSpacing.xs)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Original video")

            // White separator
            Rectangle()
                .fill(Color.white)
                .frame(width: 2)
                .accessibilityHidden(true)

            // Edited panel
            ZStack(alignment: .topTrailing) {
                editedContent
                    .clipped()

                ComparisonGlassLabel(text: "Edited")
                    .padding(.top, LiquidSpacing.xs)
                    .padding(.trailing, LiquidSpacing.xs)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Edited video")
        }
    }
}

// MARK: - SplitClipShape

/// Custom shape that clips content to the left portion up to `splitPosition`.
///
/// Used by split screen mode to reveal the original content on the left
/// side of the divider.
private struct SplitClipShape: Shape {

    /// Fraction of width to clip to (0.0 to 1.0).
    var splitPosition: Double

    var animatableData: Double {
        get { splitPosition }
        set { splitPosition = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width * splitPosition,
            height: rect.height
        ))
    }
}

// MARK: - ComparisonGlassLabel

/// Glass pill label used as overlay indicator in comparison views.
///
/// Displays text on a translucent material background with
/// rounded corners, matching iOS 26 Liquid Glass styling.
struct ComparisonGlassLabel: View {

    /// The label text to display.
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, LiquidSpacing.sm)
            .padding(.vertical, LiquidSpacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(text)
    }
}
