// TextPositionHandle.swift
// LiquidEditor
//
// Interactive draggable/resizable text positioning handle.
// Provides a mini canvas with drag, plus sliders for scale, rotation, opacity.
// Pure iOS 26 SwiftUI with native styling.
//

import SwiftUI

// MARK: - TextPositionHandle

/// Widget for controlling text position, scale, rotation, and opacity.
///
/// Displays a visual representation of the text position on a
/// mini 16:9 canvas, along with sliders for scale, rotation, and opacity.
/// Users can drag the position indicator to move text, or use
/// the sliders for precise control.
struct TextPositionHandle: View {

    // MARK: - Properties

    /// Current position in normalized coordinates (0.0-1.0).
    @Binding var position: CGPoint

    /// Current scale factor.
    @Binding var scale: Double

    /// Current rotation in radians.
    @Binding var rotation: Double

    /// Current opacity (0.0-1.0).
    @Binding var opacity: Double

    /// Whether snapping occurred during the current drag.
    @State private var didSnap = false

    /// Snap threshold in normalized coordinate space.
    static let snapThreshold: Double = 0.02

    // MARK: - Position Presets

    /// Predefined quick-position presets.
    static let positionPresets: [(String, CGPoint)] = [
        ("Top", CGPoint(x: 0.5, y: 0.15)),
        ("Center", CGPoint(x: 0.5, y: 0.5)),
        ("Bottom", CGPoint(x: 0.5, y: 0.85)),
    ]

    /// Second row of position presets.
    static let positionPresetsRow2: [(String, CGPoint)] = [
        ("Top Left", CGPoint(x: 0.2, y: 0.15)),
        ("Top Right", CGPoint(x: 0.8, y: 0.15)),
        ("Btm Left", CGPoint(x: 0.2, y: 0.85)),
    ]

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: LiquidSpacing.lg) {
                // Position canvas
                positionCanvas

                // Position readout
                positionReadout

                // Scale slider
                sliderRow(
                    label: "Scale",
                    value: $scale,
                    range: 0.1...5.0,
                    displayValue: "\(Int(scale * 100))%"
                )

                // Rotation slider
                sliderRow(
                    label: "Rotation",
                    value: $rotation,
                    range: -.pi ... .pi,
                    displayValue: String(format: "%.1fdeg", rotation * 180 / .pi)
                )

                // Opacity slider
                sliderRow(
                    label: "Opacity",
                    value: $opacity,
                    range: 0.0...1.0,
                    displayValue: "\(Int(opacity * 100))%"
                )

                // Quick position presets
                quickPositionPresets

                // Reset button
                Button(role: .destructive) {
                    resetTransform()
                } label: {
                    Text("Reset Position")
                        .font(LiquidTypography.subheadline)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.sm)
        }
    }

    // MARK: - Position Canvas

    /// Mini 16:9 canvas showing position crosshairs and draggable indicator.
    private var positionCanvas: some View {
        GeometryReader { geometry in
            let canvasWidth = geometry.size.width
            let canvasHeight = canvasWidth / (16.0 / 9.0)

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(LiquidColors.separator.opacity(0.3))
                    )

                // Center crosshairs
                Path { path in
                    path.move(to: CGPoint(x: 0, y: canvasHeight / 2))
                    path.addLine(to: CGPoint(x: canvasWidth, y: canvasHeight / 2))
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)

                Path { path in
                    path.move(to: CGPoint(x: canvasWidth / 2, y: 0))
                    path.addLine(to: CGPoint(x: canvasWidth / 2, y: canvasHeight))
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)

                // Thirds guides
                ForEach([1.0 / 3.0, 2.0 / 3.0], id: \.self) { fraction in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: canvasHeight * fraction))
                        path.addLine(to: CGPoint(x: canvasWidth, y: canvasHeight * fraction))
                    }
                    .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)

                    Path { path in
                        path.move(to: CGPoint(x: canvasWidth * fraction, y: 0))
                        path.addLine(to: CGPoint(x: canvasWidth * fraction, y: canvasHeight))
                    }
                    .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                }

                // Position indicator
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .shadow(color: Color.blue.opacity(0.4), radius: 8)
                    .position(
                        x: position.x * canvasWidth,
                        y: position.y * canvasHeight
                    )
            }
            .frame(height: canvasHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.translation.width / canvasWidth
                        let dy = value.translation.height / canvasHeight

                        let startX = value.startLocation.x / canvasWidth
                        let startY = value.startLocation.y / canvasHeight

                        var newX = min(max(startX + dx, 0.0), 1.0)
                        var newY = min(max(startY + dy, 0.0), 1.0)

                        let snapped = applySnap(x: newX, y: newY)
                        newX = snapped.x
                        newY = snapped.y

                        position = CGPoint(x: newX, y: newY)
                    }
                    .onEnded { _ in
                        didSnap = false
                    }
            )
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    // MARK: - Position Readout

    private var positionReadout: some View {
        HStack(spacing: LiquidSpacing.xxl) {
            Text("X: \(Int(position.x * 100))%")
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)

            Text("Y: \(Int(position.y * 100))%")
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Position X \(Int(position.x * 100)) percent, Y \(Int(position.y * 100)) percent")
    }

    // MARK: - Quick Position Presets

    private var quickPositionPresets: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text("Quick Position")
                .font(LiquidTypography.subheadlineSemibold)
                .foregroundStyle(.secondary)

            HStack(spacing: LiquidSpacing.sm) {
                ForEach(Self.positionPresets, id: \.0) { label, preset in
                    presetButton(label: label, target: preset)
                }
            }

            HStack(spacing: LiquidSpacing.sm) {
                ForEach(Self.positionPresetsRow2, id: \.0) { label, preset in
                    presetButton(label: label, target: preset)
                }
            }
        }
    }

    // MARK: - Subviews

    /// Slider row with label, slider, and value readout.
    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        displayValue: String
    ) -> some View {
        HStack {
            Text(label)
                .font(LiquidTypography.subheadline)
                .frame(width: 80, alignment: .leading)

            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(displayValue)

            Text(displayValue)
                .font(LiquidTypography.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .padding(.vertical, LiquidSpacing.xs)
    }

    /// Preset position button.
    private func presetButton(label: String, target: CGPoint) -> some View {
        let distance = hypot(position.x - target.x, position.y - target.y)
        let isActive = distance < 0.05

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            position = target
        } label: {
            Text(label)
                .font(LiquidTypography.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? LiquidColors.primary : .primary)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs + 1)
                .background(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .fill(isActive
                              ? LiquidColors.primary.opacity(0.15)
                              : LiquidColors.tertiaryBackground.opacity(0.5))
                        .overlay(
                            isActive
                                ? RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                                    .strokeBorder(LiquidColors.primary.opacity(0.4))
                                : nil
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// Reset all transform values to defaults.
    func resetTransform() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        position = CGPoint(x: 0.5, y: 0.5)
        scale = 1.0
        rotation = 0.0
        opacity = 1.0
    }

    /// Apply snap-to-grid logic for position.
    ///
    /// Snaps to center (0.5) and edges (0.0, 1.0).
    /// Provides haptic feedback on the first snap of a drag gesture.
    func applySnap(x: Double, y: Double) -> CGPoint {
        var snappedX = x
        var snappedY = y
        var didSnapNow = false

        // Snap to horizontal center
        if abs(x - 0.5) < Self.snapThreshold {
            snappedX = 0.5
            didSnapNow = true
        }

        // Snap to vertical center
        if abs(y - 0.5) < Self.snapThreshold {
            snappedY = 0.5
            didSnapNow = true
        }

        // Snap to edges
        if abs(x) < Self.snapThreshold {
            snappedX = 0.0
            didSnapNow = true
        }
        if abs(x - 1.0) < Self.snapThreshold {
            snappedX = 1.0
            didSnapNow = true
        }
        if abs(y) < Self.snapThreshold {
            snappedY = 0.0
            didSnapNow = true
        }
        if abs(y - 1.0) < Self.snapThreshold {
            snappedY = 1.0
            didSnapNow = true
        }

        // Haptic feedback on snap
        if didSnapNow && !didSnap {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        didSnap = didSnapNow

        return CGPoint(x: snappedX, y: snappedY)
    }
}
