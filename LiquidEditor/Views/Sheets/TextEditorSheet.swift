// TextEditorSheet.swift
// LiquidEditor
//
// Text overlay editor sheet view.
// Pure iOS 26 SwiftUI with native styling.
//
// Layout matches Flutter TextEditorPanel:
// - Full-screen presentation
// - Nav bar: Cancel | "Edit Text" | Done
// - Video preview area (~60% of height) with inline text input overlaid
// - Segmented tab picker between preview and panel content
// - Panel content in bottom ~40%

import SwiftUI

// MARK: - TextEffectPreset

private enum TextEffectPreset: String, CaseIterable, Identifiable {
    case none        = "None"
    case hardShadow  = "Hard Shadow"
    case softShadow  = "Soft Shadow"
    case blockOffset = "Block Offset"
    case neon        = "Neon"
    case glow        = "Glow"
    case halo        = "Halo"
    case shimmer     = "Shimmer"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none:        return "textformat"
        case .hardShadow:  return "shadow"
        case .softShadow:  return "aqi.medium"
        case .blockOffset: return "rectangle.stack"
        case .neon:        return "bolt.fill"
        case .glow:        return "rays"
        case .halo:        return "circle.dashed"
        case .shimmer:     return "sparkles"
        }
    }
}

struct TextEditorSheet: View {

    // MARK: - Core State

    @State private var selectedTab = 0
    @State private var text: String
    @State private var fontFamily: String
    @State private var fontSize: Double
    @State private var textColor: Color
    @State private var textAlignment: TextClipAlignment
    @State private var isItalic: Bool
    @State private var hasUnderline: Bool

    // MARK: - Position / Transform State (wired to TextPositionHandle)

    @State private var position: CGPoint
    @State private var scale: Double
    @State private var rotation: Double
    @State private var opacity: Double

    @State private var selectedAnimationPreset: TextAnimationPresetType?
    @State private var selectedExitPreset: TextAnimationPresetType?
    @State private var selectedSustainPreset: TextAnimationPresetType?

    // MARK: - Per-Phase Animation Duration State

    /// Enter animation duration in seconds (0.1 - 2.0).
    @State private var enterDuration: Double
    /// Exit animation duration in seconds (0.1 - 2.0).
    @State private var exitDuration: Double

    @FocusState private var isTextFieldFocused: Bool

    // MARK: - Font Weight State

    /// Font weight index: 0=Light, 1=Regular, 2=Semi, 3=Bold, 4=Heavy
    @State private var fontWeight: Int

    // MARK: - Letter Spacing & Line Height State

    @State private var letterSpacing: Double
    @State private var lineHeight: Double

    // MARK: - Effects State

    @State private var hasShadow: Bool
    @State private var shadowBlur: Double

    @State private var hasOutline: Bool
    @State private var outlineWidth: Double

    @State private var hasBackground: Bool
    @State private var backgroundColor: Color
    @State private var backgroundCornerRadius: Double

    @State private var hasGlow: Bool
    @State private var glowRadius: Double
    @State private var glowIntensity: Double

    @Environment(\.dismiss) private var dismiss

    // isInline variant: when true, caller should present this in a bottom panel rather than full sheet.
    // The parameter is available for EditorView integration.
    var isInline: Bool = false

    let onApply: (TextClip) -> Void
    private let existingClip: TextClip?

    /// Segmented tab sections shown below the preview in the editor panel.
    enum TextEditorTab: String, CaseIterable {
        case style = "Style"
        case animation = "Animation"
        case position = "Position"
        case templates = "Templates"
    }

    private let tabs = TextEditorTab.allCases

    // MARK: - Color Presets

    private let colorPresets: [(String, Color)] = [
        ("White", .white),
        ("Black", .black),
        ("Red", .red),
        ("Orange", .orange),
        ("Yellow", .yellow),
        ("Green", .green),
        ("Blue", .blue),
        ("Purple", .purple),
        ("Pink", .pink),
        ("Light Blue", Color(red: 0.4, green: 0.8, blue: 1.0)),
    ]

    // MARK: - Initialization

    init(
        existingClip: TextClip? = nil,
        onApply: @escaping (TextClip) -> Void
    ) {
        self.existingClip = existingClip
        self.onApply = onApply

        let clip = existingClip
        _text = State(initialValue: clip?.text ?? "")
        _fontFamily = State(initialValue: clip?.style.fontFamily ?? ".SF Pro Display")
        _fontSize = State(initialValue: clip?.style.fontSize ?? 48.0)
        _textColor = State(initialValue: .white)
        _textAlignment = State(initialValue: clip?.textAlign ?? .center)
        _isItalic = State(initialValue: clip?.style.isItalic ?? false)
        _hasUnderline = State(initialValue: clip?.style.decoration.contains(.underline) ?? false)
        _position = State(initialValue: CGPoint(
            x: clip?.positionX ?? 0.5,
            y: clip?.positionY ?? 0.5
        ))
        _scale = State(initialValue: clip?.scale ?? 1.0)
        _rotation = State(initialValue: clip?.rotation ?? 0.0)
        _opacity = State(initialValue: clip?.opacity ?? 1.0)
        _selectedAnimationPreset = State(initialValue: clip?.enterAnimation?.type)
        _selectedExitPreset = State(initialValue: clip?.exitAnimation?.type)
        _selectedSustainPreset = State(initialValue: clip?.sustainAnimation?.type)

        // Per-phase durations: convert from microseconds to seconds
        _enterDuration = State(initialValue: Double(clip?.enterDurationMicros ?? 300_000) / 1_000_000.0)
        _exitDuration = State(initialValue: Double(clip?.exitDurationMicros ?? 300_000) / 1_000_000.0)

        // Font Weight: map FontWeightValue to picker index
        let weight = clip?.style.fontWeight ?? .bold
        let weightIndex: Int
        switch weight {
        case .w100, .w200, .w300: weightIndex = 0  // Light
        case .w400, .w500: weightIndex = 1           // Regular
        case .w600: weightIndex = 2                   // Semi
        case .w700: weightIndex = 3                   // Bold
        case .w800, .w900: weightIndex = 4            // Heavy
        }
        _fontWeight = State(initialValue: weightIndex)

        // Letter Spacing & Line Height
        _letterSpacing = State(initialValue: clip?.style.letterSpacing ?? 0.0)
        _lineHeight = State(initialValue: clip?.style.lineHeight ?? 1.2)

        // Effects
        _hasShadow = State(initialValue: clip?.style.shadow != nil)
        _shadowBlur = State(initialValue: clip?.style.shadow?.blurRadius ?? 4.0)

        _hasOutline = State(initialValue: clip?.style.outline != nil)
        _outlineWidth = State(initialValue: clip?.style.outline?.width ?? 2.0)

        _hasBackground = State(initialValue: clip?.style.background != nil)
        _backgroundColor = State(initialValue: .black.opacity(0.5))
        _backgroundCornerRadius = State(initialValue: clip?.style.background?.cornerRadius ?? 8.0)

        _hasGlow = State(initialValue: clip?.style.glow != nil)
        _glowRadius = State(initialValue: clip?.style.glow?.radius ?? 10.0)
        _glowIntensity = State(initialValue: clip?.style.glow?.intensity ?? 0.5)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom header row
            headerRow
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()

            // Video preview area with inline text editing (~60%)
            previewArea

            // Segmented tab picker between preview and panel
            tabPicker

            // Panel content (~40%)
            ScrollView {
                switch selectedTab {
                case 0: styleTab
                case 1: animationTab
                case 2: positionTab
                case 3: templatesTab
                default: EmptyView()
                }
            }

            Divider()

            // Full-width Apply button
            Button {
                applyChanges()
                dismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(text.isEmpty)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
            .accessibilityLabel("Apply text changes")
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Edit Text")
                .font(LiquidTypography.headline)

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
        }
    }

    // MARK: - Preview Area

    private var previewArea: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background simulating video preview
                Color.black

                // Inline text field overlaid on the preview, offset by position
                TextField("Enter text...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(previewFont)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(textAlignmentValue)
                    .lineLimit(1...6)
                    .focused($isTextFieldFocused)
                    .padding()
                    .scaleEffect(scale)
                    .rotationEffect(.radians(rotation))
                    .opacity(opacity)
                    .offset(
                        x: (position.x - 0.5) * geometry.size.width,
                        y: (position.y - 0.5) * geometry.size.height
                    )
            }
            .frame(height: geometry.size.height)
            .onTapGesture {
                isTextFieldFocused = false
            }
        }
        .frame(maxHeight: .infinity)
        .layoutPriority(3)
    }

    private var previewFont: Font {
        var font = Font.system(size: fontSize * 0.4, weight: resolvedSwiftUIFontWeight)
        if isItalic { font = font.italic() }
        return font
    }

    /// Map the fontWeight picker index to SwiftUI Font.Weight.
    private var resolvedSwiftUIFontWeight: Font.Weight {
        switch fontWeight {
        case 0: .light
        case 1: .regular
        case 2: .semibold
        case 3: .bold
        case 4: .heavy
        default: .regular
        }
    }

    private var textAlignmentValue: TextAlignment {
        switch textAlignment {
        case .left, .start: .leading
        case .center: .center
        case .right, .end: .trailing
        case .justify: .leading
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        VStack(spacing: 0) {
            Divider()

            Picker("Tab", selection: $selectedTab) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    Text(tabs[index].rawValue).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()
        }
        .background(.ultraThinMaterial)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - Style Tab

    private var styleTab: some View {
        VStack(spacing: LiquidSpacing.lg) {
            // Font Picker
            fontPickerSection

            // Font Size
            fontSizeSection

            // Font Weight Picker
            fontWeightSection

            // Text Color Presets + Picker
            textColorSection

            // Alignment
            alignmentSection

            // Style toggles (Italic, Underline)
            styleTogglesSection

            // Letter Spacing
            letterSpacingSection

            // Line Height
            lineHeightSection

            // Effects
            effectsSection
        }
        .padding(.vertical)
    }

    // MARK: - Style Tab Subsections

    private var fontPickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Font")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
            Picker("Font", selection: $fontFamily) {
                ForEach(availableFonts, id: \.self) { font in
                    Text(font).tag(font)
                }
            }
        }
        .padding(.horizontal)
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Size")
                    .font(LiquidTypography.subheadline)
                Spacer()
                Text(String(format: "%.0f pt", fontSize))
                    .font(LiquidTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $fontSize, in: 12...200)
        }
        .padding(.horizontal)
    }

    private var fontWeightSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weight")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
            Picker("Weight", selection: $fontWeight) {
                Text("Light").tag(0)
                Text("Regular").tag(1)
                Text("Semi").tag(2)
                Text("Bold").tag(3)
                Text("Heavy").tag(4)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
    }

    private var textColorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color")
                    .font(LiquidTypography.subheadline)
                Spacer()
                ColorPicker("", selection: $textColor)
                    .labelsHidden()
            }

            // Preset color circles
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(colorPresets, id: \.0) { preset in
                        Button {
                            textColor = preset.1
                        } label: {
                            Circle()
                                .fill(preset.1)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.0)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var alignmentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alignment")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
            Picker("Alignment", selection: $textAlignment) {
                Image(systemName: "text.alignleft").tag(TextClipAlignment.left)
                Image(systemName: "text.aligncenter").tag(TextClipAlignment.center)
                Image(systemName: "text.alignright").tag(TextClipAlignment.right)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
    }

    private var styleTogglesSection: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $isItalic) {
                Text("I").font(.headline).italic()
            }
            .toggleStyle(.button)

            Toggle(isOn: $hasUnderline) {
                Text("U").font(.headline).underline()
            }
            .toggleStyle(.button)

            Spacer()
        }
        .padding(.horizontal)
    }

    private var letterSpacingSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Letter Spacing")
                    .font(LiquidTypography.subheadline)
                Spacer()
                Text(String(format: "%.1f", letterSpacing))
                    .font(LiquidTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $letterSpacing, in: -5.0...20.0)
        }
        .padding(.horizontal)
    }

    private var lineHeightSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Line Height")
                    .font(LiquidTypography.subheadline)
                Spacer()
                Text(String(format: "%.1fx", lineHeight))
                    .font(LiquidTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $lineHeight, in: 0.8...3.0)
        }
        .padding(.horizontal)
    }

    // MARK: - Text Effect Presets Row

    private var textEffectPresetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TextEffectPreset.allCases) { preset in
                    presetCell(preset)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func presetCell(_ preset: TextEffectPreset) -> some View {
        Button {
            applyPreset(preset)
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 34)
                    .overlay(
                        Image(systemName: preset.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                    )
                Text(preset.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Effects Section

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effects")
                .font(LiquidTypography.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            // --- Text Effect Presets ---
            textEffectPresetsRow
            // --- End Presets ---

            // Shadow
            shadowEffectRow

            // Outline
            outlineEffectRow

            // Background
            backgroundEffectRow

            // Glow
            glowEffectRow
        }
    }

    private var shadowEffectRow: some View {
        VStack(spacing: 8) {
            Toggle("Shadow", isOn: $hasShadow)
                .font(LiquidTypography.subheadline)
                .padding(.horizontal)

            if hasShadow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Blur")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", shadowBlur))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $shadowBlur, in: 0...20)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var outlineEffectRow: some View {
        VStack(spacing: 8) {
            Toggle("Outline", isOn: $hasOutline)
                .font(LiquidTypography.subheadline)
                .padding(.horizontal)

            if hasOutline {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Width")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", outlineWidth))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $outlineWidth, in: 0...10)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var backgroundEffectRow: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $hasBackground) {
                HStack {
                    Text("Background")
                        .font(LiquidTypography.subheadline)
                    if hasBackground {
                        ColorPicker("", selection: $backgroundColor)
                            .labelsHidden()
                    }
                }
            }
            .padding(.horizontal)

            if hasBackground {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Corner Radius")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f", backgroundCornerRadius))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $backgroundCornerRadius, in: 0...20)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var glowEffectRow: some View {
        VStack(spacing: 8) {
            Toggle("Glow", isOn: $hasGlow)
                .font(LiquidTypography.subheadline)
                .padding(.horizontal)

            if hasGlow {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Radius")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", glowRadius))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $glowRadius, in: 0...30)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Intensity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", glowIntensity * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $glowIntensity, in: 0...1)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Animation Tab

    private var animationTab: some View {
        VStack(spacing: 20) {
            // --- Enter Phase ---
            animationPhaseSection(
                title: "Enter Animation",
                icon: "arrow.right.circle.fill",
                presets: [
                    .fadeIn, .slideInLeft, .slideInRight, .slideInTop,
                    .slideInBottom, .scaleUp, .bounceIn, .typewriter,
                    .glitchIn, .rotateIn, .blurIn, .popIn
                ],
                selection: $selectedAnimationPreset
            )

            // Enter Duration Slider
            if selectedAnimationPreset != nil {
                phaseDurationSlider(
                    label: "Enter Duration",
                    value: $enterDuration,
                    range: 0.1...2.0
                )
            }

            Divider()
                .padding(.horizontal)

            // --- Sustain Phase ---
            animationPhaseSection(
                title: "Sustain Animation",
                icon: "repeat.circle.fill",
                presets: [
                    .breathe, .pulse, .float, .shake, .flicker
                ],
                selection: $selectedSustainPreset
            )

            Divider()
                .padding(.horizontal)

            // --- Exit Phase ---
            animationPhaseSection(
                title: "Exit Animation",
                icon: "arrow.left.circle.fill",
                presets: [
                    .fadeOut, .slideOutLeft, .slideOutRight, .slideOutTop,
                    .slideOutBottom, .scaleDown, .bounceOut,
                    .glitchOut, .rotateOut, .blurOut, .popOut
                ],
                selection: $selectedExitPreset
            )

            // Exit Duration Slider
            if selectedExitPreset != nil {
                phaseDurationSlider(
                    label: "Exit Duration",
                    value: $exitDuration,
                    range: 0.1...2.0
                )
            }

            // Clear All Animations
            if selectedAnimationPreset != nil
                || selectedExitPreset != nil
                || selectedSustainPreset != nil {
                Button("Clear All Animations") {
                    selectedAnimationPreset = nil
                    selectedExitPreset = nil
                    selectedSustainPreset = nil
                }
                .foregroundStyle(LiquidColors.error)
                .font(LiquidTypography.caption)
                .padding(.top, 4)
            }
        }
        .padding(.vertical)
    }

    // MARK: - Animation Phase Section (Reusable)

    @ViewBuilder
    private func animationPhaseSection(
        title: String,
        icon: String,
        presets: [TextAnimationPresetType],
        selection: Binding<TextAnimationPresetType?>
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(LiquidTypography.headline)
                Spacer()
                if selection.wrappedValue != nil {
                    Button {
                        selection.wrappedValue = nil
                    } label: {
                        Text("Clear")
                            .font(LiquidTypography.caption)
                            .foregroundStyle(LiquidColors.error)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        selection.wrappedValue = preset
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection.wrappedValue == preset
                                      ? Color.accentColor.opacity(0.2)
                                      : Color(.secondarySystemGroupedBackground))
                                .frame(height: 50)
                                .overlay {
                                    Image(systemName: "play.fill")
                                        .font(.caption)
                                        .foregroundStyle(
                                            selection.wrappedValue == preset
                                                ? Color.accentColor : .secondary
                                        )
                                }

                            Text(displayName(for: preset))
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Phase Duration Slider (Reusable)

    @ViewBuilder
    private func phaseDurationSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(LiquidTypography.subheadline)
                Spacer()
                Text(String(format: "%.1fs", value.wrappedValue))
                    .font(LiquidTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.1)
        }
        .padding(.horizontal)
    }

    // MARK: - Position Tab

    /// Wires directly to TextPositionHandle for drag, scale, rotation, and opacity.
    private var positionTab: some View {
        TextPositionHandle(
            position: $position,
            scale: $scale,
            rotation: $rotation,
            opacity: $opacity
        )
    }

    // MARK: - Templates Tab

    private var templatesTab: some View {
        VStack(spacing: 16) {
            Text("Text Templates")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(templatePreviews, id: \.name) { template in
                    Button {
                        applyTemplate(template)
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(height: 80)

                                Text(template.previewText)
                                    .font(template.previewFont)
                                    .foregroundStyle(template.previewColor)
                            }

                            Text(template.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private let availableFonts = [
        ".SF Pro Display",
        ".SF Pro Rounded",
        "Helvetica Neue",
        "Avenir Next",
        "Georgia",
        "Courier New",
        "Futura",
        "Gill Sans",
        "Menlo",
        "Optima"
    ]

    private struct TemplatePreviewData {
        let name: String
        let previewText: String
        let previewFont: Font
        let previewColor: Color
        let fontFamily: String
        let fontSizeValue: Double
        let fontWeightValue: FontWeightValue
    }

    private var templatePreviews: [TemplatePreviewData] {
        [
            TemplatePreviewData(
                name: "Title",
                previewText: "TITLE",
                previewFont: .largeTitle.bold(),
                previewColor: .white,
                fontFamily: ".SF Pro Display",
                fontSizeValue: 72,
                fontWeightValue: .bold
            ),
            TemplatePreviewData(
                name: "Subtitle",
                previewText: "Subtitle text",
                previewFont: .title3,
                previewColor: .white,
                fontFamily: ".SF Pro Display",
                fontSizeValue: 36,
                fontWeightValue: .w600
            ),
            TemplatePreviewData(
                name: "Caption",
                previewText: "Caption here",
                previewFont: .caption,
                previewColor: .white,
                fontFamily: ".SF Pro Display",
                fontSizeValue: 24,
                fontWeightValue: .regular
            ),
            TemplatePreviewData(
                name: "Bold Headline",
                previewText: "BOLD",
                previewFont: .headline.bold(),
                previewColor: .yellow,
                fontFamily: "Futura",
                fontSizeValue: 64,
                fontWeightValue: .w900
            ),
            TemplatePreviewData(
                name: "Minimal",
                previewText: "minimal",
                previewFont: .body,
                previewColor: .white.opacity(0.8),
                fontFamily: "Helvetica Neue",
                fontSizeValue: 32,
                fontWeightValue: .light
            ),
            TemplatePreviewData(
                name: "Typewriter",
                previewText: "typewriter",
                previewFont: .system(.body, design: .monospaced),
                previewColor: .green,
                fontFamily: "Courier New",
                fontSizeValue: 28,
                fontWeightValue: .regular
            ),
        ]
    }

    private func displayName(for preset: TextAnimationPresetType) -> String {
        let raw = preset.rawValue
        var result = ""
        for char in raw {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result += String(char)
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    private func applyTemplate(_ template: TemplatePreviewData) {
        fontFamily = template.fontFamily
        fontSize = template.fontSizeValue
        // Map FontWeightValue to picker index
        switch template.fontWeightValue {
        case .w100, .w200, .w300: fontWeight = 0
        case .w400, .w500: fontWeight = 1
        case .w600: fontWeight = 2
        case .w700: fontWeight = 3
        case .w800, .w900: fontWeight = 4
        }
        selectedTab = 0 // Switch to style tab
    }

    // MARK: - Font Weight Conversion

    /// Map the fontWeight picker index to the model's FontWeightValue.
    private var resolvedFontWeightValue: FontWeightValue {
        switch fontWeight {
        case 0: .light       // w300
        case 1: .regular     // w400
        case 2: .semiBold    // w600
        case 3: .bold        // w700
        case 4: .w900        // Heavy
        default: .regular
        }
    }

    // MARK: - Preset Application

    /// Apply a TextEffectPreset by mutating the local effects @State variables.
    ///
    /// TextOverlayStyle is immutable; the sheet manages effect properties as individual
    /// @State vars (hasShadow, shadowBlur, hasGlow, glowRadius, glowIntensity, hasOutline,
    /// outlineWidth). This method resets all effect state then applies the selected preset.
    private func applyPreset(_ preset: TextEffectPreset) {
        // Reset all effects
        hasShadow = false
        shadowBlur = 4.0
        hasOutline = false
        outlineWidth = 2.0
        hasGlow = false
        glowRadius = 10.0
        glowIntensity = 0.5

        switch preset {
        case .none:
            // All effects already reset above
            break
        case .hardShadow:
            hasShadow = true
            shadowBlur = 0.0
        case .softShadow:
            hasShadow = true
            shadowBlur = 8.0
        case .blockOffset:
            hasShadow = true
            shadowBlur = 0.0
        case .neon:
            hasGlow = true
            glowRadius = 12.0
            glowIntensity = 0.9
            hasOutline = true
            outlineWidth = 1.0
        case .glow:
            hasGlow = true
            glowRadius = 20.0
            glowIntensity = 1.0
        case .halo:
            hasShadow = true
            shadowBlur = 16.0
        case .shimmer:
            hasGlow = true
            glowRadius = 8.0
            glowIntensity = 0.6
            hasOutline = true
            outlineWidth = 0.5
        }
    }

    // MARK: - Apply

    /// Validate and resolve the font family, falling back to system font if unavailable.
    private func resolvedFontFamily() -> String {
        let available = UIFont.familyNames
        if available.contains(fontFamily) {
            return fontFamily
        }
        // System fonts use a dot-prefix convention (e.g. ".SF Pro Display")
        // and are always available even if not listed in familyNames.
        if fontFamily.hasPrefix(".") {
            return fontFamily
        }
        return ".AppleSystemUIFont"
    }

    private func applyChanges() {
        var decoration: TextDecorationType = .none
        if hasUnderline { decoration.insert(.underline) }

        let validatedFontFamily = resolvedFontFamily()

        let style = TextOverlayStyle(
            fontFamily: validatedFontFamily,
            fontSize: fontSize,
            fontWeight: resolvedFontWeightValue,
            isItalic: isItalic,
            letterSpacing: letterSpacing,
            lineHeight: lineHeight,
            shadow: hasShadow ? TextShadowStyle(blurRadius: shadowBlur) : nil,
            outline: hasOutline ? TextOutlineStyle(width: outlineWidth) : nil,
            background: hasBackground ? TextBackgroundStyle(cornerRadius: backgroundCornerRadius) : nil,
            glow: hasGlow ? TextGlowStyle(radius: glowRadius, intensity: glowIntensity) : nil,
            decoration: decoration
        )

        let enterAnim: TextAnimationPreset? = selectedAnimationPreset.map {
            TextAnimationPreset(type: $0)
        }
        let exitAnim: TextAnimationPreset? = selectedExitPreset.map {
            TextAnimationPreset(type: $0)
        }
        let sustainAnim: TextAnimationPreset? = selectedSustainPreset.map {
            TextAnimationPreset(type: $0)
        }

        // Convert per-phase durations from seconds to microseconds
        let enterDurationMicros = Int64(enterDuration * 1_000_000)
        let exitDurationMicros = Int64(exitDuration * 1_000_000)

        // Build the final TextClip, preserving existing clip properties
        // (duration, keyframes, etc.) when editing.
        // TextClipManager.updateText / updatePosition are stateless helpers
        // but here we need a full rebuild because the sheet owns all style state.
        let baseClip = existingClip ?? TextClip(
            durationMicroseconds: 3_000_000,
            text: text,
            style: style
        )

        let clip = baseClip.with(
            text: text,
            style: style,
            positionX: position.x,
            positionY: position.y,
            rotation: rotation,
            scale: scale,
            opacity: max(0.0, min(1.0, opacity)),
            enterAnimation: enterAnim,
            exitAnimation: exitAnim,
            sustainAnimation: sustainAnim,
            enterDurationMicros: enterDurationMicros,
            exitDurationMicros: exitDurationMicros,
            textAlign: textAlignment,
            clearEnterAnimation: enterAnim == nil,
            clearExitAnimation: exitAnim == nil,
            clearSustainAnimation: sustainAnim == nil
        )

        onApply(clip)
    }
}

#Preview {
    TextEditorSheet { _ in }
}
