// KeyframeEditorSheet.swift
// LiquidEditor
//
// Premium keyframe editor with Liquid Glass UI.
// Allows editing transform properties (scale, translation, rotation),
// selecting interpolation types, and managing keyframes (delete, duplicate).

import SwiftUI

// MARK: - GlassCard

/// A reusable Liquid Glass card container for grouping related controls.
///
/// Wraps any content with an `.ultraThinMaterial` background and continuous
/// rounded corners, matching the iOS 26 Liquid Glass design language.
///
/// Usage:
/// ```swift
/// GlassCard {
///     Text("Hello, glass!")
/// }
/// ```
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - KeyframeEditorSheet

/// Full-screen sheet for editing a single keyframe's transform and interpolation.
///
/// Presents:
/// - Live transform preview with animated rectangle
/// - Scale, horizontal, vertical, and rotation sliders with a Reset Transform link
/// - Interpolation type picker (Basic / Cubic / Special) with Bezier control point sliders
/// - Delete and duplicate action buttons
/// - Glass card containers via `GlassCard` and `.glassEffect()` modifiers
/// - Haptic feedback on all interactive controls
struct KeyframeEditorSheet: View {

    // MARK: - Properties

    /// The keyframe being edited.
    let keyframe: Keyframe

    /// Video duration for context.
    let videoDurationMicros: TimeMicros

    /// Callback when the keyframe is updated.
    let onUpdate: (Keyframe) -> Void

    /// Callback when the keyframe should be deleted.
    let onDelete: (String) -> Void

    /// Callback when the keyframe should be duplicated.
    let onDuplicate: (Keyframe) -> Void

    /// Callback when the transform should be fully reset to identity.
    let onResetTransform: () -> Void

    // MARK: - State

    @State private var editingTransform: VideoTransform
    @State private var selectedInterpolation: InterpolationType
    @State private var bezierPoints: BezierControlPoints

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(
        keyframe: Keyframe,
        videoDurationMicros: TimeMicros,
        onUpdate: @escaping (Keyframe) -> Void,
        onDelete: @escaping (String) -> Void,
        onDuplicate: @escaping (Keyframe) -> Void,
        onResetTransform: @escaping () -> Void = {}
    ) {
        self.keyframe = keyframe
        self.videoDurationMicros = videoDurationMicros
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
        self.onResetTransform = onResetTransform
        _editingTransform = State(initialValue: keyframe.transform)
        _selectedInterpolation = State(initialValue: keyframe.interpolation)
        _bezierPoints = State(initialValue: keyframe.bezierPoints ?? .easeInOut)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Custom header row
            headerRow
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: LiquidSpacing.xl) {
                    previewSection
                    transformControlsSection
                    interpolationPickerSection
                    actionButtonsSection
                }
                .padding(LiquidSpacing.xl)
            }

            Divider()
                .padding(.horizontal)

            // Full-width Apply button
            Button {
                saveAndDismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
            .accessibilityLabel("Apply keyframe changes")
            .accessibilityHint("Saves the transform and interpolation changes")
        }
        .background(Color.black)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("Edit Keyframe")
                    .font(LiquidTypography.headline)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Dismisses the keyframe editor without saving")
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
            Label("Preview", systemImage: "eye")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 140)

                previewRectangle
            }
        }
        .glassEffect(cornerRadius: LiquidSpacing.cornerLarge)
        .padding(LiquidSpacing.lg)
    }

    private var previewRectangle: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 100, height: 56)
            .overlay {
                Image(systemName: "play.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 20))
            }
            .shadow(color: .blue.opacity(0.4), radius: 16, y: 4)
            .scaleEffect(editingTransform.scale)
            .offset(
                x: editingTransform.translation.x * 60,
                y: editingTransform.translation.y * 35
            )
            .rotationEffect(.radians(editingTransform.rotation))
            .animation(.easeInOut(duration: 0.15), value: editingTransform.scale)
            .animation(.easeInOut(duration: 0.15), value: editingTransform.translation.x)
            .animation(.easeInOut(duration: 0.15), value: editingTransform.translation.y)
            .animation(.easeInOut(duration: 0.15), value: editingTransform.rotation)
    }

    // MARK: - Transform Controls

    private var transformControlsSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xl) {
            HStack {
                Label("Transform", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(LiquidTypography.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    resetTransform()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHint("Resets transform to identity")
                .glassEffect(style: .thin, cornerRadius: LiquidSpacing.cornerSmall, showShadow: false)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs)
            }

            transformSlider(
                icon: "plus.magnifyingglass",
                label: "Scale",
                value: $editingTransform.transformScale,
                range: 0.1...5.0,
                displayValue: "\(String(format: "%.1f", editingTransform.scale))x",
                tint: .blue
            )

            transformSlider(
                icon: "arrow.left.arrow.right",
                label: "Horizontal",
                value: $editingTransform.translationX,
                range: -1.0...1.0,
                displayValue: String(format: "%.2f", editingTransform.translation.x),
                tint: .cyan
            )

            transformSlider(
                icon: "arrow.up.arrow.down",
                label: "Vertical",
                value: $editingTransform.translationY,
                range: -1.0...1.0,
                displayValue: String(format: "%.2f", editingTransform.translation.y),
                tint: .indigo
            )

            transformSlider(
                icon: "rotate.right",
                label: "Rotation",
                value: $editingTransform.transformRotation,
                range: -.pi ... .pi,
                displayValue: "\(String(format: "%.1f", editingTransform.rotation * 180 / .pi))\u{00B0}",
                tint: .orange
            )

            // Standalone "Reset Transform" link below sliders area
            HStack {
                Spacer()
                Button {
                    resetTransform()
                    onResetTransform()
                } label: {
                    Label("Reset Transform", systemImage: "arrow.counterclockwise.circle")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset Transform")
                .accessibilityHint("Resets all transform values to their defaults")
            }
        }
        .glassEffect(cornerRadius: LiquidSpacing.cornerLarge)
        .padding(LiquidSpacing.lg)
    }

    private func transformSlider(
        icon: String,
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayValue: String,
        tint: Color
    ) -> some View {
        VStack(spacing: LiquidSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                    .accessibilityHidden(true)

                Text(label)
                    .font(LiquidTypography.body)
                    .foregroundStyle(.primary)

                Spacer()

                Text(displayValue)
                    .font(LiquidTypography.monoCaption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, LiquidSpacing.xs)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Slider(value: value, in: range)
                .tint(tint)
                .accessibilityLabel(label)
                .accessibilityValue(displayValue)
        }
    }

    // MARK: - Interpolation Picker

    private var interpolationPickerSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.lg) {
            Label("Interpolation", systemImage: "waveform.path")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)

            interpolationCategory("Basic", types: [
                .linear, .hold, .easeIn, .easeOut, .easeInOut,
            ])

            interpolationCategory("Cubic", types: [
                .cubicIn, .cubicOut, .cubicInOut, .bezier,
            ])

            interpolationCategory("Special", types: [
                .spring, .bounce, .elastic,
            ])

            // Bezier control point sliders -- shown only when Bezier is selected
            if selectedInterpolation == .bezier {
                bezierControlPointsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassEffect(cornerRadius: LiquidSpacing.cornerLarge)
        .padding(LiquidSpacing.lg)
        .animation(.easeInOut(duration: 0.2), value: selectedInterpolation == .bezier)
    }

    /// Control point sliders for custom Cubic Bezier easing.
    ///
    /// Control point 1 drives the in-tangent (x1, y1),
    /// control point 2 drives the out-tangent (x2, y2).
    /// Both points are clamped to [0, 1] on the X axis and [-0.5, 1.5] on Y.
    private var bezierControlPointsSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.md) {
            Label("Bezier Control Points", systemImage: "scribble.variable")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)

            // Control Point 1
            VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
                Text("Point 1 (In-Tangent)")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)

                bezierAxisSlider(
                    label: "X1",
                    value: Binding(
                        get: { bezierPoints.controlPoint1.x },
                        set: { newVal in
                            bezierPoints = bezierPoints.with(
                                controlPoint1: CGPoint(x: newVal, y: bezierPoints.controlPoint1.y)
                            )
                        }
                    ),
                    range: 0.0...1.0,
                    tint: .blue
                )

                bezierAxisSlider(
                    label: "Y1",
                    value: Binding(
                        get: { bezierPoints.controlPoint1.y },
                        set: { newVal in
                            bezierPoints = bezierPoints.with(
                                controlPoint1: CGPoint(x: bezierPoints.controlPoint1.x, y: newVal)
                            )
                        }
                    ),
                    range: -0.5...1.5,
                    tint: .blue
                )
            }
            .padding(LiquidSpacing.sm)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous))

            // Control Point 2
            VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
                Text("Point 2 (Out-Tangent)")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)

                bezierAxisSlider(
                    label: "X2",
                    value: Binding(
                        get: { bezierPoints.controlPoint2.x },
                        set: { newVal in
                            bezierPoints = bezierPoints.with(
                                controlPoint2: CGPoint(x: newVal, y: bezierPoints.controlPoint2.y)
                            )
                        }
                    ),
                    range: 0.0...1.0,
                    tint: .orange
                )

                bezierAxisSlider(
                    label: "Y2",
                    value: Binding(
                        get: { bezierPoints.controlPoint2.y },
                        set: { newVal in
                            bezierPoints = bezierPoints.with(
                                controlPoint2: CGPoint(x: bezierPoints.controlPoint2.x, y: newVal)
                            )
                        }
                    ),
                    range: -0.5...1.5,
                    tint: .orange
                )
            }
            .padding(LiquidSpacing.sm)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous))
        }
    }

    private func bezierAxisSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        tint: Color
    ) -> some View {
        HStack(spacing: LiquidSpacing.sm) {
            Text(label)
                .font(LiquidTypography.monoCaption)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            Slider(value: value, in: range)
                .tint(tint)
                .onChange(of: value.wrappedValue) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

            Text(String(format: "%.2f", value.wrappedValue))
                .font(LiquidTypography.monoCaption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func interpolationCategory(
        _ title: String,
        types: [InterpolationType]
    ) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: LiquidSpacing.sm)], spacing: LiquidSpacing.sm) {
                ForEach(types, id: \.self) { type in
                    interpolationChip(type)
                }
            }
        }
    }

    private func interpolationChip(_ type: InterpolationType) -> some View {
        let isSelected = type == selectedInterpolation
        return Button {
            selectedInterpolation = type
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(type.displayName)
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.blue : .secondary)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .stroke(
                            isSelected ? Color.blue.opacity(0.5) : LiquidColors.glassBorder,
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
        }
        .accessibilityLabel("\(type.displayName) interpolation")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Action Buttons

    private var actionButtonsSection: some View {
        HStack(spacing: LiquidSpacing.md) {
            Button(role: .destructive) {
                deleteKeyframe()
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(LiquidColors.error)
            .accessibilityHint("Permanently deletes this keyframe")

            Button {
                duplicateKeyframe()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .accessibilityHint("Creates a copy of this keyframe at a slightly later time")
        }
    }

    // MARK: - Actions

    private func resetTransform() {
        editingTransform = .identity
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveAndDismiss() {
        let updated = keyframe.with(
            transform: editingTransform,
            interpolation: selectedInterpolation,
            bezierPoints: selectedInterpolation == .bezier ? bezierPoints : nil,
            clearBezierPoints: selectedInterpolation != .bezier
        )
        onUpdate(updated)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deleteKeyframe() {
        onDelete(keyframe.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }

    private func duplicateKeyframe() {
        let duplicated = Keyframe(
            id: UUID().uuidString,
            timestampMicros: keyframe.timestampMicros + 500_000, // +500ms
            transform: editingTransform,
            interpolation: selectedInterpolation,
            bezierPoints: selectedInterpolation == .bezier ? bezierPoints : nil
        )
        onDuplicate(duplicated)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - VideoTransform Binding Helpers

extension Binding where Value == VideoTransform {
    /// Binding to the scale component.
    var transformScale: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.scale },
            set: { wrappedValue = wrappedValue.with(scale: $0) }
        )
    }

    /// Binding to translation X component.
    var translationX: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.translation.x },
            set: { wrappedValue = wrappedValue.with(translation: CGPoint(x: $0, y: wrappedValue.translation.y)) }
        )
    }

    /// Binding to translation Y component.
    var translationY: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.translation.y },
            set: { wrappedValue = wrappedValue.with(translation: CGPoint(x: wrappedValue.translation.x, y: $0)) }
        )
    }

    /// Binding to the rotation component.
    var transformRotation: Binding<Double> {
        Binding<Double>(
            get: { wrappedValue.rotation },
            set: { wrappedValue = wrappedValue.with(rotation: $0) }
        )
    }
}
