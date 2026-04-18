// TrimPrecisionView.swift
// LiquidEditor
//
// E4-3: Frame-level trim precision sheet.
//
// Presents a Liquid Glass sheet for adjusting the in/out points of the
// selected clip with single-frame precision. Shows two scrubbable preview
// thumbnails (in / out) side-by-side, timecode displays, and ±1f / ±10f
// stepper buttons.
//
// The view is intentionally decoupled from ``EditorViewModel``: the caller
// passes the clip to trim and an ``onApply`` closure. This keeps the view
// testable and avoids coupling the sheet to any specific view model API.

import SwiftUI

// MARK: - TrimPrecisionView

/// Sheet view for frame-level trim of a selected clip's in/out points.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showTrim) {
///     TrimPrecisionView(clip: clip) { newIn, newOut in
///         // TODO: wire to EditorViewModel.applyTrim(in:out:) once exposed
///     }
/// }
/// ```
@MainActor
struct TrimPrecisionView: View {

    // MARK: - Input

    /// The clip whose in/out points are being adjusted.
    let clip: TimelineClip

    /// Called when the user taps Apply with the new source in/out values.
    let onApply: (TimeMicros, TimeMicros) -> Void

    /// Frames per second used for frame arithmetic. Defaults to 30 fps.
    let framesPerSecond: Int

    // MARK: - State

    /// Working source-in point (microseconds).
    @State private var workingIn: TimeMicros

    /// Working source-out point (microseconds).
    @State private var workingOut: TimeMicros

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(
        clip: TimelineClip,
        framesPerSecond: Int = 30,
        onApply: @escaping (TimeMicros, TimeMicros) -> Void
    ) {
        self.clip = clip
        self.framesPerSecond = framesPerSecond
        self.onApply = onApply
        _workingIn = State(initialValue: clip.sourceIn)
        _workingOut = State(initialValue: clip.sourceOut)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: LiquidSpacing.xl) {
                header

                thumbnailRow

                timecodeRow

                stepperSection(
                    title: "In Point",
                    time: $workingIn,
                    lowerBound: 0,
                    upperBound: max(0, workingOut - minGap)
                )

                stepperSection(
                    title: "Out Point",
                    time: $workingOut,
                    lowerBound: workingIn + minGap,
                    upperBound: maxSourceTime
                )

                Spacer(minLength: 0)

                actionBar
            }
            .padding(LiquidSpacing.xl)
            .background(LiquidColors.background.ignoresSafeArea())
            .navigationTitle("Precision Trim")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: LiquidSpacing.xs) {
            Text("Frame-level Trim")
                .font(LiquidTypography.title3)
                .foregroundStyle(LiquidColors.textPrimary)

            Text("Adjust in and out points to single-frame precision.")
                .font(LiquidTypography.footnote)
                .foregroundStyle(LiquidColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var thumbnailRow: some View {
        HStack(spacing: LiquidSpacing.md) {
            thumbnailCard(title: "In", time: workingIn)
            thumbnailCard(title: "Out", time: workingOut)
        }
    }

    private func thumbnailCard(title: String, time: TimeMicros) -> some View {
        VStack(spacing: LiquidSpacing.sm) {
            Text(title)
                .font(LiquidTypography.captionMedium)
                .foregroundStyle(LiquidColors.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .fill(LiquidColors.fillTertiary)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                Image(systemName: "film")
                    .font(.system(size: LiquidSpacing.iconXLarge))
                    .foregroundStyle(LiquidColors.textTertiary)
            }
            .overlay(
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                    .strokeBorder(LiquidColors.glassBorder, lineWidth: 0.5)
            )

            Text(timecodeString(for: time))
                .font(LiquidTypography.monoCaption)
                .foregroundStyle(LiquidColors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(LiquidSpacing.md)
        .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerLarge)
    }

    private var timecodeRow: some View {
        HStack {
            timecodeBadge(title: "Duration", value: timecodeString(for: workingOut - workingIn))
            Spacer()
            timecodeBadge(title: "Frames", value: "\(frames(for: workingOut - workingIn))")
        }
    }

    private func timecodeBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
            Text(title)
                .font(LiquidTypography.caption2Semibold)
                .foregroundStyle(LiquidColors.textSecondary)
            Text(value)
                .font(LiquidTypography.monoSubheadline)
                .foregroundStyle(LiquidColors.textPrimary)
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, LiquidSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous)
                .fill(LiquidColors.fillQuaternary)
        )
    }

    @ViewBuilder
    private func stepperSection(
        title: String,
        time: Binding<TimeMicros>,
        lowerBound: TimeMicros,
        upperBound: TimeMicros
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text(title)
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(LiquidColors.textPrimary)

            HStack(spacing: LiquidSpacing.sm) {
                stepperButton(
                    label: "−10f",
                    systemImage: "gobackward.10"
                ) {
                    adjust(time, by: -10, lowerBound: lowerBound, upperBound: upperBound)
                }

                stepperButton(
                    label: "−1f",
                    systemImage: "minus"
                ) {
                    adjust(time, by: -1, lowerBound: lowerBound, upperBound: upperBound)
                }

                Text(timecodeString(for: time.wrappedValue))
                    .font(LiquidTypography.monoBody)
                    .foregroundStyle(LiquidColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous)
                            .fill(LiquidColors.fillQuaternary)
                    )

                stepperButton(
                    label: "+1f",
                    systemImage: "plus"
                ) {
                    adjust(time, by: 1, lowerBound: lowerBound, upperBound: upperBound)
                }

                stepperButton(
                    label: "+10f",
                    systemImage: "goforward.10"
                ) {
                    adjust(time, by: 10, lowerBound: lowerBound, upperBound: upperBound)
                }
            }
        }
        .padding(LiquidSpacing.md)
        .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerLarge)
    }

    private func stepperButton(
        label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: LiquidSpacing.iconSmall, weight: .semibold))
                Text(label)
                    .font(LiquidTypography.caption2Semibold)
            }
            .frame(minWidth: LiquidSpacing.minTouchTarget, minHeight: LiquidSpacing.minTouchTarget)
            .foregroundStyle(LiquidColors.accent)
            .padding(.horizontal, LiquidSpacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) adjustment")
    }

    private var actionBar: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.bordered)

            Button {
                // TODO: wire to EditorViewModel.applyTrim(in:out:) once exposed.
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onApply(workingIn, workingOut)
                dismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.bodySemibold)
                    .frame(maxWidth: .infinity, minHeight: LiquidSpacing.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isApplyEnabled)
        }
    }

    // MARK: - Helpers

    /// One frame duration in microseconds at the active frame rate.
    private var microsecondsPerFrame: TimeMicros {
        guard framesPerSecond > 0 else { return 33_333 }
        return TimeMicros(1_000_000 / framesPerSecond)
    }

    /// Minimum gap (in microseconds) between in and out points (1 frame).
    private var minGap: TimeMicros { microsecondsPerFrame }

    /// Upper bound for the working out point (clip source end).
    private var maxSourceTime: TimeMicros {
        max(clip.sourceOut, clip.sourceIn + clip.duration)
    }

    /// Whether Apply is enabled (bounds are valid and something changed).
    private var isApplyEnabled: Bool {
        workingOut > workingIn + minGap - 1 &&
            (workingIn != clip.sourceIn || workingOut != clip.sourceOut)
    }

    /// Adjust a bound by `frames` frames, clamped to `[lowerBound, upperBound]`.
    private func adjust(
        _ time: Binding<TimeMicros>,
        by frames: Int,
        lowerBound: TimeMicros,
        upperBound: TimeMicros
    ) {
        let delta = TimeMicros(frames) * microsecondsPerFrame
        let proposed = time.wrappedValue + delta
        time.wrappedValue = min(max(proposed, lowerBound), upperBound)
    }

    /// Convert a microsecond value to frame count at the active fps.
    private func frames(for micros: TimeMicros) -> Int {
        guard microsecondsPerFrame > 0 else { return 0 }
        return Int(micros / microsecondsPerFrame)
    }

    /// Format a microsecond value as HH:MM:SS:FF using the active frame rate.
    private func timecodeString(for micros: TimeMicros) -> String {
        let clamped = max(0, micros)
        let totalSeconds = Int(clamped / 1_000_000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let remainingMicros = clamped % 1_000_000
        let frameCount: Int = {
            guard microsecondsPerFrame > 0 else { return 0 }
            return Int(remainingMicros / microsecondsPerFrame)
        }()
        return String(
            format: "%02d:%02d:%02d:%02d",
            hours,
            minutes,
            seconds,
            min(frameCount, max(framesPerSecond - 1, 0))
        )
    }
}
