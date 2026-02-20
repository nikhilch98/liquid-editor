// ColorGradingSheet.swift
// LiquidEditor
//
// Full 5-tab color grading sheet: Basic (presets + 10 sliders), Color
// (temperature/tint/vibrance/hue + Tone section + Detail section),
// HSL (Shadows/Midtones/Highlights H/S/L + Vignette), Curves (RGB
// channel curve editor with draggable control points), LUT (category
// grid with intensity slider + remove). Pure iOS 26 SwiftUI.

import SwiftUI

// MARK: - GradingTab

/// Tab sections within the color grading sheet.
private enum GradingTab: Int, CaseIterable {
    case basic, color, hsl, curves, lut

    var label: String {
        switch self {
        case .basic:  return "Basic"
        case .color:  return "Color"
        case .hsl:    return "HSL"
        case .curves: return "Curves"
        case .lut:    return "LUT"
        }
    }
}

// MARK: - ColorGradingSheet

/// Full-featured color grading modal sheet.
///
/// Organized into five tabs: Basic, Color, HSL, Curves, and LUT.
/// Supports real-time grade editing with instant preview via bindings.
/// Conforms to iOS 26 Liquid Glass design language throughout.
struct ColorGradingSheet: View {

    // MARK: - State

    @State private var selectedTab: GradingTab = .basic
    @State private var grade: ColorGrade
    @State private var activePresetId: String?

    // Curves tab sub-state
    @State private var selectedCurveChannel: CurveChannelOption = .rgb

    // LUT tab sub-state: loaded async snapshot
    @State private var lutCategories: [String] = []
    @State private var lutsByCategory: [String: [LUTReference]] = [:]
    @State private var lutServiceLoaded = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Dependencies

    /// Optional LUT service for populating the LUT tab.
    let lutService: LUTService?

    /// Called with the finalized grade when the user taps Done.
    let onApply: (ColorGrade) -> Void

    // MARK: - Init

    init(
        initialGrade: ColorGrade? = nil,
        lutService: LUTService? = nil,
        onApply: @escaping (ColorGrade) -> Void
    ) {
        let now = Date()
        _grade = State(initialValue: initialGrade ?? ColorGrade(
            id: UUID().uuidString,
            createdAt: now,
            modifiedAt: now
        ))
        self.lutService = lutService
        self.onApply = onApply
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.md)

            Divider()
                .padding(.horizontal, LiquidSpacing.lg)

            tabPicker
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.vertical, LiquidSpacing.sm)

            ScrollView {
                VStack(spacing: LiquidSpacing.sm) {
                    switch selectedTab {
                    case .basic:  basicTab
                    case .color:  colorTab
                    case .hsl:    hslTab
                    case .curves: curvesTab
                    case .lut:    lutTab
                    }
                }
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.vertical, LiquidSpacing.sm)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadLUTData()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button("Reset") {
                resetGrade()
            }
            .font(LiquidTypography.subheadline)
            .foregroundStyle(grade.isIdentity ? Color.secondary : LiquidColors.error)
            .accessibilityHint("Resets all color grading to default values")

            Spacer()

            Text("Color Grading")
                .font(LiquidTypography.headline)

            Spacer()

            HStack(spacing: LiquidSpacing.sm) {
                Button("Done") {
                    onApply(grade)
                    dismiss()
                }
                .font(LiquidTypography.subheadlineMedium)
                .foregroundStyle(.orange)
                .accessibilityHint("Applies color grading and dismisses the sheet")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityHint("Dismisses the color grading sheet without applying")
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(GradingTab.allCases, id: \.self) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Color grading tab")
        .onChange(of: selectedTab) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Basic Tab

    private var basicTab: some View {
        VStack(spacing: 4) {
            // Presets row
            ColorGradingPresets(
                activePresetId: activePresetId,
                onPresetSelected: applyPreset,
                onReset: resetGrade
            )
            .padding(.bottom, LiquidSpacing.xs)

            gradingSlider("Exposure",   value: exposureBinding,   range: -3.0...3.0)
            gradingSlider("Brightness", value: brightnessBinding, range: -1.0...1.0)
            gradingSlider("Contrast",   value: contrastBinding,   range: -1.0...1.0)
            gradingSlider("Saturation", value: saturationBinding, range: -1.0...1.0)
            gradingSlider("Highlights", value: highlightsBinding, range: -1.0...1.0)
            gradingSlider("Shadows",    value: shadowsBinding,    range: -1.0...1.0)
            gradingSlider("Whites",     value: whitesBinding,     range: -1.0...1.0)
            gradingSlider("Blacks",     value: blacksBinding,     range: -1.0...1.0)
            gradingSlider("Sharpness",  value: sharpnessBinding,  range:  0.0...1.0)
            gradingSlider("Clarity",    value: clarityBinding,    range: -1.0...1.0)
        }
    }

    // MARK: - Color Tab

    private var colorTab: some View {
        VStack(spacing: 4) {
            gradingSlider("Temperature", value: temperatureBinding, range: -1.0...1.0)
            gradingSlider("Tint",        value: tintBinding,        range: -1.0...1.0)

            sectionHeader("TONE")
            gradingSlider("Vibrance", value: vibranceBinding, range: -1.0...1.0)

            sectionHeader("DETAIL")
            gradingSlider("Hue Shift", value: hueBinding, range: -180.0...180.0)
        }
    }

    // MARK: - HSL Tab

    private var hslTab: some View {
        VStack(spacing: 4) {
            DisclosureGroup {
                hslSliderGroup(
                    adjustment: grade.hslShadows,
                    onChange: { adj in
                        grade = grade.with(hslShadows: adj)
                        activePresetId = nil
                    }
                )
                .padding(.top, LiquidSpacing.xs)
            } label: {
                Text("SHADOWS")
                    .font(LiquidTypography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
            }

            DisclosureGroup {
                hslSliderGroup(
                    adjustment: grade.hslMidtones,
                    onChange: { adj in
                        grade = grade.with(hslMidtones: adj)
                        activePresetId = nil
                    }
                )
                .padding(.top, LiquidSpacing.xs)
            } label: {
                Text("MIDTONES")
                    .font(LiquidTypography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
            }

            DisclosureGroup {
                hslSliderGroup(
                    adjustment: grade.hslHighlights,
                    onChange: { adj in
                        grade = grade.with(hslHighlights: adj)
                        activePresetId = nil
                    }
                )
                .padding(.top, LiquidSpacing.xs)
            } label: {
                Text("HIGHLIGHTS")
                    .font(LiquidTypography.caption2Semibold)
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
            }

            sectionHeader("VIGNETTE")
            gradingSlider("Intensity", value: vignetteIntensityBinding, range: 0.0...1.0)
            gradingSlider("Radius",    value: vignetteRadiusBinding,    range: 0.0...1.0)
            gradingSlider("Softness",  value: vignetteSoftnessBinding,  range: 0.0...1.0)
        }
    }

    // MARK: - Curves Tab

    private var curvesTab: some View {
        VStack(spacing: LiquidSpacing.md) {
            // Channel selector
            Picker("Channel", selection: $selectedCurveChannel) {
                ForEach(CurveChannelOption.allCases) { channel in
                    Text(channel.label).tag(channel)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Curve channel")

            // Curve canvas
            curveCanvas
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity)

            // Reset curve button
            Button {
                resetCurrentCurve()
            } label: {
                Label("Reset Curve", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(currentCurveData.isIdentity)
        }
    }

    /// The CurveData for the currently selected channel.
    private var currentCurveData: CurveData {
        switch selectedCurveChannel {
        case .rgb:   return grade.curveLuminance
        case .red:   return grade.curveRed
        case .green: return grade.curveGreen
        case .blue:  return grade.curveBlue
        }
    }

    private func updateCurrentCurve(_ newCurve: CurveData) {
        switch selectedCurveChannel {
        case .rgb:   grade = grade.with(curveLuminance: newCurve)
        case .red:   grade = grade.with(curveRed: newCurve)
        case .green: grade = grade.with(curveGreen: newCurve)
        case .blue:  grade = grade.with(curveBlue: newCurve)
        }
        activePresetId = nil
    }

    private func resetCurrentCurve() {
        updateCurrentCurve(.identity)
    }

    private var curveCanvas: some View {
        let curveData = currentCurveData
        let strokeColor = selectedCurveChannel.color

        return ZStack {
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.8))

            Canvas { context, size in
                let w = size.width
                let h = size.height

                let gridColor = Color.gray.opacity(0.25)
                for i in 1..<4 {
                    let fraction = CGFloat(i) / 4.0
                    let vPath = Path { p in
                        p.move(to: CGPoint(x: fraction * w, y: 0))
                        p.addLine(to: CGPoint(x: fraction * w, y: h))
                    }
                    context.stroke(vPath, with: .color(gridColor), lineWidth: 0.5)
                    let hPath = Path { p in
                        p.move(to: CGPoint(x: 0, y: fraction * h))
                        p.addLine(to: CGPoint(x: w, y: fraction * h))
                    }
                    context.stroke(hPath, with: .color(gridColor), lineWidth: 0.5)
                }

                let diagPath = Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: 0))
                }
                context.stroke(diagPath, with: .color(Color.gray.opacity(0.3)), lineWidth: 1)

                let sampleCount = 64
                let curvePath = Path { p in
                    for s in 0..<sampleCount {
                        let inputX = Double(s) / Double(sampleCount - 1)
                        let outputY = curveData.evaluate(inputX)
                        let px = inputX * Double(w)
                        let py = (1.0 - outputY) * Double(h)
                        if s == 0 {
                            p.move(to: CGPoint(x: px, y: py))
                        } else {
                            p.addLine(to: CGPoint(x: px, y: py))
                        }
                    }
                }
                context.stroke(curvePath, with: .color(strokeColor), lineWidth: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall, style: .continuous))

            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height

                ForEach(Array(curveData.points.enumerated()), id: \.offset) { index, point in
                    let px = point.x * Double(w)
                    let py = (1.0 - point.y) * Double(h)

                    Circle()
                        .fill(strokeColor)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().strokeBorder(Color.white, lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .position(x: px, y: py)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let newX = Double(value.location.x / w)
                                    let newY = 1.0 - Double(value.location.y / h)
                                    let updated = currentCurveData.movePoint(
                                        index, newX: newX, newY: newY
                                    )
                                    updateCurrentCurve(updated)
                                }
                        )
                }
            }
        }
    }

    // MARK: - LUT Tab

    private var lutTab: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            // Current LUT banner
            if let currentLut = grade.lutFilter {
                currentLUTBanner(lut: currentLut)
                gradingSlider("LUT Intensity", value: lutIntensityBinding, range: 0.0...1.0)
                Divider()
            }

            if !lutServiceLoaded {
                // Loading indicator
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 40)
                    Spacer()
                }
            } else if lutCategories.isEmpty {
                // No LUTs available
                HStack {
                    Spacer()
                    VStack(spacing: LiquidSpacing.sm) {
                        Spacer().frame(height: 40)
                        Image(systemName: "slider.horizontal.below.rectangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No LUTs Available")
                            .font(LiquidTypography.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer().frame(height: 40)
                    }
                    Spacer()
                }
            } else {
                // LUT grid by category
                ForEach(lutCategories, id: \.self) { category in
                    if let luts = lutsByCategory[category], !luts.isEmpty {
                        sectionHeader(category.uppercased())

                        FlowLayout(spacing: LiquidSpacing.sm) {
                            ForEach(luts, id: \.id) { lut in
                                lutTile(lut: lut)
                            }
                        }
                        .padding(.bottom, LiquidSpacing.xs)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func currentLUTBanner(lut: LUTReference) -> some View {
        HStack {
            Image(systemName: "slider.horizontal.below.rectangle")
                .font(LiquidTypography.body)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(lut.name)
                .font(LiquidTypography.subheadlineMedium)
                .foregroundStyle(.orange)
                .lineLimit(1)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                grade = grade.with(clearLut: true)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove LUT")
            .accessibilityHint("Removes the currently applied LUT filter")
        }
        .padding(.horizontal, LiquidSpacing.md)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current LUT: \(lut.name)")
    }

    @ViewBuilder
    private func lutTile(lut: LUTReference) -> some View {
        let isSelected = grade.lutFilter?.id == lut.id

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                grade = grade.with(clearLut: true)
            } else {
                grade = grade.with(lutFilter: lut)
            }
            activePresetId = nil
        } label: {
            Text(lut.name)
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.orange : Color.primary)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.sm)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.orange.opacity(0.7) : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel(lut.name)
        .accessibilityHint(isSelected ? "Currently selected LUT" : "Applies the \(lut.name) LUT")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(LiquidTypography.caption2Semibold)
            .foregroundStyle(.tertiary)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, LiquidSpacing.xs)
            .padding(.bottom, LiquidSpacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - HSL Slider Group

    private func hslSliderGroup(
        adjustment: HSLAdjustment,
        onChange: @escaping (HSLAdjustment) -> Void
    ) -> some View {
        VStack(spacing: 4) {
            gradingSlider(
                "Hue",
                value: Binding(
                    get: { adjustment.hue },
                    set: { onChange(adjustment.with(hue: $0)) }
                ),
                range: 0.0...360.0
            )
            gradingSlider(
                "Saturation",
                value: Binding(
                    get: { adjustment.saturation },
                    set: { onChange(adjustment.with(saturation: $0)) }
                ),
                range: 0.0...1.0
            )
            gradingSlider(
                "Luminance",
                value: Binding(
                    get: { adjustment.luminance },
                    set: { onChange(adjustment.with(luminance: $0)) }
                ),
                range: -1.0...1.0
            )
        }
    }

    // MARK: - Grading Slider

    /// A single slider row: label (fixed width) + slider + formatted value.
    private func gradingSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(LiquidTypography.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            Slider(value: value, in: range)
                .tint(.orange)
                .accessibilityLabel(label)
                .accessibilityValue(formattedSliderValue(value.wrappedValue, range: range))

            Text(formattedSliderValue(value.wrappedValue, range: range))
                .font(LiquidTypography.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, LiquidSpacing.xs)
    }

    /// Format slider value with sign prefix for bipolar ranges (range.lowerBound < 0).
    private func formattedSliderValue(_ value: Double, range: ClosedRange<Double>) -> String {
        if range.lowerBound < 0 {
            if abs(value) < 0.005 { return "0" }
            let intVal = Int(value.rounded())
            return intVal >= 0 ? "+\(intVal)" : "\(intVal)"
        }
        return "\(Int(value.rounded()))"
    }

    // MARK: - Preset Application

    private func applyPreset(_ preset: FilterPreset) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let now = Date()
        grade = preset.grade.with(
            id: grade.id,
            createdAt: grade.createdAt,
            modifiedAt: now
        )
        activePresetId = preset.id
    }

    private func resetGrade() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let now = Date()
        grade = ColorGrade(
            id: grade.id,
            createdAt: grade.createdAt,
            modifiedAt: now
        )
        activePresetId = nil
    }

    // MARK: - LUT Data Loading

    private func loadLUTData() async {
        guard let lutService else {
            // No LUT service provided – mark as loaded with empty data
            lutServiceLoaded = true
            return
        }

        await lutService.initialize()

        let cats = await lutService.categories
        var byCategory: [String: [LUTReference]] = [:]
        for cat in cats {
            byCategory[cat] = await lutService.lutsForCategory(cat)
        }

        lutCategories = cats
        lutsByCategory = byCategory
        lutServiceLoaded = true
    }

    // MARK: - Bindings

    private var exposureBinding: Binding<Double> {
        Binding(get: { grade.exposure },    set: { grade = grade.with(exposure: $0);    activePresetId = nil })
    }
    private var brightnessBinding: Binding<Double> {
        Binding(get: { grade.brightness },  set: { grade = grade.with(brightness: $0);  activePresetId = nil })
    }
    private var contrastBinding: Binding<Double> {
        Binding(get: { grade.contrast },    set: { grade = grade.with(contrast: $0);    activePresetId = nil })
    }
    private var saturationBinding: Binding<Double> {
        Binding(get: { grade.saturation },  set: { grade = grade.with(saturation: $0);  activePresetId = nil })
    }
    private var temperatureBinding: Binding<Double> {
        Binding(get: { grade.temperature }, set: { grade = grade.with(temperature: $0); activePresetId = nil })
    }
    private var tintBinding: Binding<Double> {
        Binding(get: { grade.tint },        set: { grade = grade.with(tint: $0);        activePresetId = nil })
    }
    private var vibranceBinding: Binding<Double> {
        Binding(get: { grade.vibrance },    set: { grade = grade.with(vibrance: $0);    activePresetId = nil })
    }
    private var hueBinding: Binding<Double> {
        Binding(get: { grade.hue },         set: { grade = grade.with(hue: $0);         activePresetId = nil })
    }
    private var highlightsBinding: Binding<Double> {
        Binding(get: { grade.highlights },  set: { grade = grade.with(highlights: $0);  activePresetId = nil })
    }
    private var shadowsBinding: Binding<Double> {
        Binding(get: { grade.shadows },     set: { grade = grade.with(shadows: $0);     activePresetId = nil })
    }
    private var whitesBinding: Binding<Double> {
        Binding(get: { grade.whites },      set: { grade = grade.with(whites: $0);      activePresetId = nil })
    }
    private var blacksBinding: Binding<Double> {
        Binding(get: { grade.blacks },      set: { grade = grade.with(blacks: $0);      activePresetId = nil })
    }
    private var sharpnessBinding: Binding<Double> {
        Binding(get: { grade.sharpness },   set: { grade = grade.with(sharpness: $0);   activePresetId = nil })
    }
    private var clarityBinding: Binding<Double> {
        Binding(get: { grade.clarity },     set: { grade = grade.with(clarity: $0);     activePresetId = nil })
    }
    private var vignetteIntensityBinding: Binding<Double> {
        Binding(get: { grade.vignetteIntensity }, set: { grade = grade.with(vignetteIntensity: $0); activePresetId = nil })
    }
    private var vignetteRadiusBinding: Binding<Double> {
        Binding(get: { grade.vignetteRadius },    set: { grade = grade.with(vignetteRadius: $0);    activePresetId = nil })
    }
    private var vignetteSoftnessBinding: Binding<Double> {
        Binding(get: { grade.vignetteSoftness },  set: { grade = grade.with(vignetteSoftness: $0);  activePresetId = nil })
    }
    private var lutIntensityBinding: Binding<Double> {
        Binding(
            get: { grade.lutFilter?.intensity ?? 1.0 },
            set: { newVal in
                if let lut = grade.lutFilter {
                    grade = grade.with(lutFilter: lut.with(intensity: newVal))
                }
            }
        )
    }
}

// MARK: - CurveChannelOption

/// Selectable curve channel for the curves editor.
private enum CurveChannelOption: String, CaseIterable, Identifiable {
    case rgb, red, green, blue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rgb:   return "RGB"
        case .red:   return "Red"
        case .green: return "Green"
        case .blue:  return "Blue"
        }
    }

    var color: Color {
        switch self {
        case .rgb:   return .white
        case .red:   return .red
        case .green: return .green
        case .blue:  return .blue
        }
    }
}

// MARK: - FlowLayout

/// Wrap-style layout: arranges children left-to-right, wrapping to the
/// next row when the available width is exceeded.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentY += rowHeight + spacing
                currentX = 0
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentY += rowHeight + spacing
                currentX = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    ColorGradingSheet { _ in }
}
