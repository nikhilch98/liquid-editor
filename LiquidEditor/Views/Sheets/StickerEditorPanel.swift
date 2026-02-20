// StickerEditorPanel.swift
// LiquidEditor
//
// Sticker editor panel - transform controls and keyframe management.
//
// Inspector panel shown when a sticker is selected on the timeline
// or video preview. Provides controls for opacity, flip, tint,
// animation speed/loop, duration, and keyframe animation editing.
//
// Pure iOS 26 SwiftUI with native Liquid Glass styling.

import SwiftUI

// MARK: - StickerEditorPanel

/// Editor panel for a selected sticker clip.
///
/// Displays property controls (opacity, duration, flip, tint, animation
/// speed/loop) and a keyframe list with add/select/delete actions.
///
/// All controls use native SwiftUI components for iOS 26 Liquid Glass.
struct StickerEditorPanel: View {

    // MARK: - Properties

    /// The sticker clip being edited.
    let clip: StickerClip

    /// Whether this sticker's asset is animated (Lottie/GIF).
    let isAnimatedAsset: Bool

    /// Current playhead position relative to clip start (microseconds).
    let currentPlayheadMicros: Int64

    /// Called when the clip properties change.
    let onClipChanged: (StickerClip) -> Void

    /// Called when a keyframe should be added at the current playhead.
    let onAddKeyframe: ((Int64) -> Void)?

    /// Called when a keyframe is selected.
    let onKeyframeSelected: ((String) -> Void)?

    /// Called when a keyframe is deleted.
    let onKeyframeDeleted: ((String) -> Void)?

    // MARK: - Init

    init(
        clip: StickerClip,
        isAnimatedAsset: Bool = false,
        currentPlayheadMicros: Int64 = 0,
        onClipChanged: @escaping (StickerClip) -> Void,
        onAddKeyframe: ((Int64) -> Void)? = nil,
        onKeyframeSelected: ((String) -> Void)? = nil,
        onKeyframeDeleted: ((String) -> Void)? = nil
    ) {
        self.clip = clip
        self.isAnimatedAsset = isAnimatedAsset
        self.currentPlayheadMicros = currentPlayheadMicros
        self.onClipChanged = onClipChanged
        self.onAddKeyframe = onAddKeyframe
        self.onKeyframeSelected = onKeyframeSelected
        self.onKeyframeDeleted = onKeyframeDeleted
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
                sectionHeader("Sticker Properties")

                opacitySlider

                durationField

                flipToggles

                tintColorRow

                if isAnimatedAsset {
                    animationSpeedSlider
                    animationLoopToggle
                }

                sectionHeader("Keyframes")
                    .padding(.top, LiquidSpacing.sm)

                addKeyframeButton

                keyframeList
            }
            .padding(LiquidSpacing.lg)
        }
        .background(LiquidColors.background)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(LiquidTypography.subheadlineSemibold)
            .foregroundStyle(LiquidColors.textPrimary)
    }

    // MARK: - Opacity Slider

    private var opacitySlider: some View {
        HStack {
            Text("Opacity")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            Slider(
                value: Binding(
                    get: { clip.opacity },
                    set: { onClipChanged(clip.with(opacity: $0)) }
                ),
                in: 0...1
            )
            .accessibilityLabel("Opacity")
            .accessibilityValue("\(Int(clip.opacity * 100)) percent")

            Text("\(Int(clip.opacity * 100))%")
                .font(LiquidTypography.monoCaption)
                .foregroundStyle(LiquidColors.textPrimary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Duration Field

    /// Duration display (read-only).
    private var durationField: some View {
        let durationSeconds = Double(clip.durationMicroseconds) / 1_000_000.0

        return HStack {
            Text("Duration")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            Text(String(format: "%.1fs", durationSeconds))
                .font(LiquidTypography.monoCaption)
                .foregroundStyle(LiquidColors.textPrimary)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.sm)
                .background(LiquidColors.fillTertiary)
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
        }
    }

    // MARK: - Flip Toggles

    private var flipToggles: some View {
        HStack {
            Text("Flip")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                onClipChanged(clip.with(
                    isFlippedHorizontally: !clip.isFlippedHorizontally
                ))
            } label: {
                Text("H")
                    .font(LiquidTypography.subheadlineSemibold)
                    .foregroundStyle(
                        clip.isFlippedHorizontally
                            ? .white
                            : LiquidColors.textSecondary
                    )
                    .padding(.horizontal, LiquidSpacing.lg)
                    .padding(.vertical, LiquidSpacing.sm)
                    .background(
                        clip.isFlippedHorizontally
                            ? LiquidColors.primary
                            : LiquidColors.fillTertiary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Flip horizontal")
            .accessibilityValue(clip.isFlippedHorizontally ? "On" : "Off")

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                onClipChanged(clip.with(
                    isFlippedVertically: !clip.isFlippedVertically
                ))
            } label: {
                Text("V")
                    .font(LiquidTypography.subheadlineSemibold)
                    .foregroundStyle(
                        clip.isFlippedVertically
                            ? .white
                            : LiquidColors.textSecondary
                    )
                    .padding(.horizontal, LiquidSpacing.lg)
                    .padding(.vertical, LiquidSpacing.sm)
                    .background(
                        clip.isFlippedVertically
                            ? LiquidColors.primary
                            : LiquidColors.fillTertiary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Flip vertical")
            .accessibilityValue(clip.isFlippedVertically ? "On" : "Off")
        }
    }

    // MARK: - Tint Color Row

    private var tintColorRow: some View {
        HStack {
            Text("Tint Color")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            tintColorSwatch

            if clip.tintColorValue != nil {
                Button {
                    onClipChanged(clip.with(clearTintColorValue: true))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: LiquidSpacing.xl))
                        .foregroundStyle(LiquidColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear tint color")
            }
        }
    }

    private var tintColorSwatch: some View {
        let color: Color = if let tintValue = clip.tintColorValue {
            Color(argb: tintValue)
        } else {
            LiquidColors.fillTertiary
        }

        return RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                    .stroke(LiquidColors.separator.opacity(0.3), lineWidth: 1)
            )
            .overlay {
                if clip.tintColorValue == nil {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 16))
                        .foregroundStyle(LiquidColors.textSecondary)
                }
            }
    }

    // MARK: - Animation Speed Slider

    private var animationSpeedSlider: some View {
        HStack {
            Text("Anim Speed")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            Slider(
                value: Binding(
                    get: { clip.animationSpeed },
                    set: { onClipChanged(clip.with(animationSpeed: $0)) }
                ),
                in: 0.25...3.0
            )
            .accessibilityLabel("Animation speed")
            .accessibilityValue(String(format: "%.1f times", clip.animationSpeed))

            Text(String(format: "%.1fx", clip.animationSpeed))
                .font(LiquidTypography.monoCaption)
                .foregroundStyle(LiquidColors.textPrimary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Animation Loop Toggle

    private var animationLoopToggle: some View {
        HStack {
            Text("Anim Loop")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(LiquidColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { clip.animationLoops },
                    set: { newValue in
                        UISelectionFeedbackGenerator().selectionChanged()
                        onClipChanged(clip.with(animationLoops: newValue))
                    }
                )
            )
            .labelsHidden()
        }
    }

    // MARK: - Add Keyframe Button

    private var addKeyframeButton: some View {
        Button {
            onAddKeyframe?(currentPlayheadMicros)
        } label: {
            HStack(spacing: LiquidSpacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 16))
                Text("Add Keyframe at \(StickerEditorPanel.formatTimestamp(currentPlayheadMicros))")
                    .font(LiquidTypography.subheadline)
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
        }
        .buttonStyle(.borderedProminent)
        .disabled(onAddKeyframe == nil)
    }

    // MARK: - Keyframe List

    private var keyframeList: some View {
        Group {
            if clip.sortedKeyframes.isEmpty {
                Text("No keyframes. Add a keyframe to animate this sticker.")
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(LiquidColors.textTertiary)
                    .padding(.vertical, LiquidSpacing.lg)
            } else {
                VStack(spacing: LiquidSpacing.xs) {
                    ForEach(clip.sortedKeyframes, id: \.id) { kf in
                        keyframeRow(kf)
                    }
                }
            }
        }
    }

    private func keyframeRow(_ kf: StickerKeyframe) -> some View {
        Button {
            onKeyframeSelected?(kf.id)
        } label: {
            HStack {
                // Diamond keyframe icon
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(.systemYellow))

                Text(StickerEditorPanel.formatTimestamp(kf.timestampMicros))
                    .font(LiquidTypography.monoCaption)
                    .foregroundStyle(LiquidColors.textPrimary)

                Text(kf.interpolation.displayName)
                    .font(LiquidTypography.caption)
                    .foregroundStyle(LiquidColors.textSecondary)

                Spacer()

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onKeyframeDeleted?(kf.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(LiquidColors.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete keyframe at \(StickerEditorPanel.formatTimestamp(kf.timestampMicros))")
            }
            .padding(.horizontal, LiquidSpacing.md)
            .padding(.vertical, LiquidSpacing.md)
            .background(LiquidColors.fillTertiary)
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timestamp Formatting

    /// Format microseconds as `S:CC` display string (seconds:centiseconds).
    ///
    /// Examples:
    /// - `1_000_000 µs` → `"1:00"` (1 second, 0 centiseconds)
    /// - `500_000 µs`   → `"0:50"` (0 seconds, 50 centiseconds)
    /// - `100_000 µs`   → `"0:10"` (0 seconds, 10 centiseconds)
    static func formatTimestamp(_ microseconds: Int64) -> String {
        let totalCentiseconds = Int(Double(microseconds) / 10_000)
        let seconds = totalCentiseconds / 100
        let centiseconds = totalCentiseconds % 100
        return String(format: "%d:%02d", seconds, centiseconds)
    }
}

// MARK: - Color Extension for ARGB

extension Color {

    /// Create a Color from a UInt32 ARGB value.
    init(argb value: UInt32) {
        let a = Double((value >> 24) & 0xFF) / 255.0
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}

#Preview {
    StickerEditorPanel(
        clip: StickerClip(
            durationMicroseconds: 3_000_000,
            stickerAssetId: "preview_star"
        ),
        onClipChanged: { _ in }
    )
}
