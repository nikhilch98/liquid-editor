// AutoReframePanel.swift
// LiquidEditor
//
// Auto-reframe settings panel with sliders for controlling reframe behavior.
// Includes zoom intensity, tracking strength, deadzone, smooth motion,
// follow speed, safe zone, framing style, look-ahead, and person selection.
// Uses Liquid Glass styling.

import SwiftUI

// MARK: - AutoReframePanel

/// Panel with sliders for controlling auto-reframe behavior.
///
/// Features:
/// - Enable/disable toggle with animated content reveal
/// - Tracking strength and deadzone sliders
/// - Smooth motion toggle
/// - Zoom level display as percentage
/// - Person selection button (shows selected person name or "All Persons")
/// - Zoom intensity, follow speed, safe zone, and look-ahead sliders
/// - Framing style segmented control (Center / Thirds)
/// - Regenerate keyframes button
struct AutoReframePanel: View {

    // MARK: - Properties

    /// The auto-reframe engine providing config state.
    @Bindable var engine: AutoReframeEngine

    /// Number of currently tracked persons.
    var trackedPersonCount: Int = 0

    /// Name of the currently selected person, or nil for "All Persons".
    var selectedPersonName: String? = nil

    /// Callback when settings change and keyframes should regenerate.
    var onApply: (() -> Void)?

    /// Callback when auto-reframe is disabled.
    var onDisable: (() -> Void)?

    /// Callback to open person re-selection / person selection sheet.
    var onChangePersons: (() -> Void)?

    /// Callback to close the panel.
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Local smooth motion toggle state (maps to followSpeed preference).
    @State private var smoothMotionEnabled: Bool = true

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Title and toggle
            titleRow

            // Tracking status / person selection (when active)
            if trackedPersonCount > 0 {
                trackingStatusRow
            }

            // Sliders (when enabled)
            if engine.isEnabled {
                Divider()
                    .background(Color(UIColor.systemGray4))

                ScrollView {
                    VStack(spacing: LiquidSpacing.lg) {
                        slidersSection
                    }
                    .padding(LiquidSpacing.lg)
                }

                regenerateButton
            }

            // Bottom safe area padding
            Spacer().frame(height: 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: LiquidSpacing.cornerXLarge,
                topTrailingRadius: LiquidSpacing.cornerXLarge
            )
        )
        .onAppear {
            // Initialise smooth motion toggle from current followSpeed.
            // Fast followSpeed (>= 0.7) implies smoothing is off.
            smoothMotionEnabled = engine.config.followSpeed < 0.7
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(width: 40, height: 4)
            .padding(.top, LiquidSpacing.md)
            .accessibilityLabel("Drag to resize panel")
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack {
            // Icon
            Image(systemName: "crop")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
                .padding(LiquidSpacing.sm)
                .background(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: LiquidSpacing.xxs) {
                Text("Auto-Reframe")
                    .font(LiquidTypography.title3)
                    .foregroundStyle(.white)

                Text("Keep subjects centered")
                    .font(LiquidTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Zoom level display (current zoom intensity as %)
            if engine.isEnabled {
                Text("\(Int(engine.config.zoomIntensity * 100))%")
                    .font(LiquidTypography.captionMedium)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, LiquidSpacing.sm)
                    .padding(.vertical, LiquidSpacing.xxs)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.xs))
                    .accessibilityLabel("Zoom level \(Int(engine.config.zoomIntensity * 100)) percent")
            }

            // Enable toggle
            Toggle("", isOn: $engine.isEnabled)
                .toggleStyle(.switch)
                .tint(.orange)
                .labelsHidden()
                .accessibilityLabel("Auto-Reframe enabled")
                .accessibilityHint("Toggles automatic subject reframing")
                .onChange(of: engine.isEnabled) { _, newValue in
                    if newValue {
                        onApply?()
                    } else {
                        onDisable?()
                    }
                }

            // Close button
            Button {
                onClose?()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
            }
            .accessibilityLabel("Close")
            .accessibilityHint("Closes the auto-reframe panel")
        }
        .padding(LiquidSpacing.lg)
    }

    // MARK: - Tracking Status

    private var trackingStatusRow: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))

            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: LiquidSpacing.iconSmall))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("Tracking \(trackedPersonCount) person\(trackedPersonCount > 1 ? "s" : "")")
                    .font(LiquidTypography.subheadline)
                    .foregroundStyle(.white)

                Spacer()

                // Person selection button
                Button {
                    onChangePersons?()
                } label: {
                    HStack(spacing: LiquidSpacing.xs) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                        Text(selectedPersonName ?? "All Persons")
                            .font(LiquidTypography.footnoteMedium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, LiquidSpacing.md)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .accessibilityLabel(
                    selectedPersonName.map { "Tracking \($0)" } ?? "Tracking all persons"
                )
                .accessibilityHint("Opens person selection for reframing")
            }
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
        }
    }

    // MARK: - Sliders Section

    @ViewBuilder
    private var slidersSection: some View {
        // Tracking Strength (maps to followSpeed: 0 = loose/smooth, 1 = tight/fast)
        sliderRow(
            label: "Tracking Strength",
            icon: "target",
            value: Binding(
                get: { engine.config.followSpeed },
                set: { engine.config = engine.config.with(followSpeed: $0); onApply?() }
            ),
            range: 0.0...1.0,
            valueLabel: trackingStrengthLabel
        )

        // Deadzone (maps to safeZonePadding: how much subject can move before camera follows)
        sliderRow(
            label: "Deadzone",
            icon: "circle.dashed",
            value: Binding(
                get: { engine.config.safeZonePadding / 0.3 },  // normalise 0-0.3 → 0-1
                set: {
                    engine.config = engine.config.with(safeZonePadding: $0 * 0.3)
                    onApply?()
                }
            ),
            range: 0.0...1.0,
            valueLabel: "\(Int(engine.config.safeZonePadding / 0.3 * 100))%"
        )

        // Smooth Motion toggle
        smoothMotionRow

        // Divider between primary and advanced controls
        Divider()
            .background(Color.white.opacity(0.08))

        // Zoom Intensity
        sliderRow(
            label: "Zoom Intensity",
            icon: "plus.magnifyingglass",
            value: Binding(
                get: { engine.config.zoomIntensity },
                set: { engine.config = engine.config.with(zoomIntensity: $0); onApply?() }
            ),
            range: 0.8...2.5,
            valueLabel: "\(String(format: "%.1f", engine.config.zoomIntensity))x"
        )

        // Safe Zone (advanced — retained for expert users)
        sliderRow(
            label: "Safe Zone",
            icon: "rectangle.expand.vertical",
            value: Binding(
                get: { engine.config.safeZonePadding },
                set: { engine.config = engine.config.with(safeZonePadding: $0); onApply?() }
            ),
            range: 0.0...0.3,
            valueLabel: "\(Int(engine.config.safeZonePadding * 100))%"
        )

        // Framing Style
        framingStyleRow

        // Look-ahead
        sliderRow(
            label: "Look-ahead",
            icon: "arrow.right.circle",
            value: Binding(
                get: { Double(engine.config.lookaheadMs) },
                set: { engine.config = engine.config.with(lookaheadMs: Int($0)); onApply?() }
            ),
            range: 0...500,
            valueLabel: "\(engine.config.lookaheadMs)ms"
        )
    }

    private func sliderRow(
        label: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: String
    ) -> some View {
        VStack(spacing: LiquidSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(label)
                    .font(LiquidTypography.footnote)
                    .foregroundStyle(LiquidColors.textSecondary)

                Spacer()

                Text(valueLabel)
                    .font(LiquidTypography.captionMedium)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, LiquidSpacing.sm)
                    .padding(.vertical, LiquidSpacing.xxs)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.xs))
            }

            Slider(value: value, in: range)
                .tint(.orange)
                .accessibilityLabel(label)
                .accessibilityValue(valueLabel)
        }
    }

    // MARK: - Smooth Motion Row

    private var smoothMotionRow: some View {
        HStack {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Smooth Motion")
                .font(LiquidTypography.footnote)
                .foregroundStyle(LiquidColors.textSecondary)

            Spacer()

            Toggle("", isOn: $smoothMotionEnabled)
                .toggleStyle(.switch)
                .tint(.orange)
                .labelsHidden()
                .accessibilityLabel("Smooth motion")
                .accessibilityValue(smoothMotionEnabled ? "Enabled" : "Disabled")
                .accessibilityHint("Enables motion smoothing between frames")
                .onChange(of: smoothMotionEnabled) { _, enabled in
                    // Map toggle to followSpeed:
                    // smooth on  -> low followSpeed (0.3 = gentle)
                    // smooth off -> high followSpeed (0.8 = responsive)
                    let speed = enabled ? 0.3 : 0.8
                    engine.config = engine.config.with(followSpeed: speed)
                    onApply?()
                }
        }
    }

    // MARK: - Tracking Strength Label

    private var trackingStrengthLabel: String {
        let speed = engine.config.followSpeed
        if speed < 0.3 { return "Loose" }
        if speed > 0.7 { return "Tight" }
        return "Normal"
    }

    // MARK: - Framing Style

    private var framingStyleRow: some View {
        HStack {
            Image(systemName: "rectangle.split.3x3")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Framing")
                .font(LiquidTypography.footnote)
                .foregroundStyle(LiquidColors.textSecondary)

            Spacer()

            Picker("Framing", selection: Binding(
                get: { engine.config.framingStyle },
                set: { engine.config = engine.config.with(framingStyle: $0); onApply?() }
            )) {
                Text("Center").tag(FramingStyle.centered)
                Text("Thirds").tag(FramingStyle.ruleOfThirds)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    // MARK: - Regenerate Button

    private var regenerateButton: some View {
        Button {
            onApply?()
        } label: {
            Label("Regenerate Keyframes", systemImage: "arrow.clockwise")
                .font(LiquidTypography.calloutMedium)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .padding(.horizontal, LiquidSpacing.lg)
        .padding(.bottom, LiquidSpacing.lg)
        .accessibilityHint("Recalculates reframe keyframes with current settings")
    }
}

// MARK: - AutoReframeToggle

/// Compact inline toggle for auto-reframe in a toolbar.
///
/// Shows a small pill-shaped button with crop icon and "Auto" label.
/// Tapping opens the full auto-reframe panel.
struct AutoReframeToggle: View {

    /// The auto-reframe engine.
    @Bindable var engine: AutoReframeEngine

    /// Callback when tapped.
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Label("Auto", systemImage: "crop")
                .font(LiquidTypography.caption)
                .foregroundStyle(engine.isEnabled ? .orange : .secondary)
                .padding(.horizontal, LiquidSpacing.sm)
                .padding(.vertical, LiquidSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .fill(engine.isEnabled ? Color.orange.opacity(0.2) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                        .stroke(
                            engine.isEnabled ? Color.orange.opacity(0.5) : Color.white.opacity(0.1),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto-Reframe")
        .accessibilityValue(engine.isEnabled ? "Enabled" : "Disabled")
        .accessibilityHint("Opens the auto-reframe settings panel")
    }
}
