// TransitionPickerSheet.swift
// LiquidEditor
//
// Transition selection sheet view.
// Pure iOS 26 SwiftUI with native styling.
//
// Matches Flutter TransitionPickerSheet layout:
// - Header with title + selected type name badge (orange)
// - Category picker as horizontal scroll chips (orange theme)
// - Transition type grid (orange selections)
// - Duration slider (orange tint)
// - Easing picker
// - Bottom: "Remove" (glass, conditional) + "Apply" (filled, orange)
// - No direction picker

import SwiftUI

struct TransitionPickerSheet: View {

    @State private var selectedType: TransitionType
    @State private var duration: Double // seconds
    @State private var easing: EasingCurve
    @State private var selectedCategory: TransitionCategory = .basic

    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    let onApply: (TransitionType, TimeMicros, EasingCurve) -> Void
    let onRemove: (() -> Void)?

    init(
        initialType: TransitionType = .crossDissolve,
        initialDuration: TimeMicros = 500_000,
        initialEasing: EasingCurve = .easeInOut,
        isEditing: Bool = false,
        onApply: @escaping (TransitionType, TimeMicros, EasingCurve) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        _selectedType = State(initialValue: initialType)
        _duration = State(initialValue: Double(initialDuration) / 1_000_000.0)
        _easing = State(initialValue: initialEasing)
        _selectedCategory = State(initialValue: initialType.category)
        self.isEditing = isEditing
        self.onApply = onApply
        self.onRemove = onRemove
    }

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
                VStack(spacing: LiquidSpacing.lg) {
                    // Header with selected type badge
                    headerBadge

                    // Category chips (horizontal scroll, orange theme)
                    categoryChips

                    // Transition Grid
                    transitionGrid

                    Divider()
                        .padding(.horizontal)

                    // Duration slider (orange tint)
                    durationSlider

                    // Easing picker
                    easingPicker
                }
                .padding(.vertical)
            }

            Divider()
                .padding(.horizontal)

            // Bottom action buttons
            actionButtons
                .padding(.horizontal, LiquidSpacing.lg)
                .padding(.vertical, LiquidSpacing.md)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack {
            Text(isEditing ? "Edit Transition" : "Add Transition")
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

    // MARK: - Header Badge

    private var headerBadge: some View {
        HStack {
            Spacer()
            Text(selectedType.displayName)
                .font(LiquidTypography.captionMedium)
                .foregroundStyle(.orange)
                .padding(.horizontal, LiquidSpacing.md)
                .padding(.vertical, LiquidSpacing.xs + 2)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(.horizontal)
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.sm) {
                ForEach(TransitionCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.displayName)
                            .font(selectedCategory == category ? LiquidTypography.captionMedium : LiquidTypography.caption)
                            .foregroundStyle(
                                selectedCategory == category
                                    ? Color.orange
                                    : Color.primary.opacity(0.8)
                            )
                            .padding(.horizontal, LiquidSpacing.md + 2)
                            .padding(.vertical, LiquidSpacing.sm)
                            .background(
                                selectedCategory == category
                                    ? Color.orange.opacity(0.2)
                                    : LiquidColors.surface
                            )
                            .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall + 2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        selectedCategory == category
                                            ? Color.orange.opacity(0.5)
                                            : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.displayName)
                    .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Transition Grid

    private var transitionGrid: some View {
        let types = selectedCategory.types
        let columns = [GridItem(.adaptive(minimum: 80), spacing: LiquidSpacing.sm)]

        return LazyVGrid(columns: columns, spacing: LiquidSpacing.sm) {
            ForEach(types, id: \.self) { transitionType in
                Button {
                    selectedType = transitionType
                } label: {
                    VStack(spacing: LiquidSpacing.xs) {
                        TransitionPreviewCell(
                            transitionType: transitionType,
                            isSelected: selectedType == transitionType
                        )

                        Text(transitionType.displayName)
                            .font(selectedType == transitionType ? LiquidTypography.caption2Semibold : LiquidTypography.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(
                                selectedType == transitionType
                                    ? Color.orange : Color.primary
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(transitionType.displayName)
                .accessibilityAddTraits(selectedType == transitionType ? .isSelected : [])
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Duration Slider

    private var durationSlider: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.sm) {
            Text("Duration")
                .font(LiquidTypography.subheadline)

            HStack(spacing: LiquidSpacing.sm) {
                Text("0.1s")
                    .font(LiquidTypography.caption2)
                    .foregroundStyle(.secondary)

                Slider(value: $duration, in: 0.1...2.0, step: 0.1)
                    .tint(.orange)
                    .accessibilityLabel("Transition duration")
                    .accessibilityValue(String(format: "%.1f seconds", duration))

                Text("2.0s")
                    .font(LiquidTypography.caption2)
                    .foregroundStyle(.secondary)
            }

            // Current value centered below
            Text(String(format: "%.1fs", duration))
                .font(LiquidTypography.captionMedium)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal)
    }

    // MARK: - Easing Picker

    private var easingPicker: some View {
        VStack(alignment: .leading, spacing: LiquidSpacing.xs) {
            Text("Easing")
                .font(LiquidTypography.subheadline)
            Picker("Easing", selection: $easing) {
                Text("Linear").tag(EasingCurve.linear)
                Text("Ease In").tag(EasingCurve.easeIn)
                Text("Ease Out").tag(EasingCurve.easeOut)
                Text("Ease In/Out").tag(EasingCurve.easeInOut)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: LiquidSpacing.md) {
            // Remove button (only when editing existing transition)
            if isEditing, let onRemove {
                Button {
                    onRemove()
                    dismiss()
                } label: {
                    Text("Remove")
                        .font(LiquidTypography.subheadlineMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LiquidSpacing.md)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Apply button (filled, orange)
            Button {
                let durationMicros = TimeMicros(duration * 1_000_000.0)
                let clamped = min(
                    max(durationMicros, ClipTransition.minDuration),
                    ClipTransition.maxDuration
                )
                onApply(selectedType, clamped, easing)
                dismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.md)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - TransitionPreviewCell

private struct TransitionPreviewCell: View {
    let transitionType: TransitionType
    let isSelected: Bool

    @State private var phase: CGFloat = 0

    // Color palette for the animation
    private let colorA = Color(hue: 0.58, saturation: 0.7, brightness: 0.9)   // blue-ish
    private let colorB = Color(hue: 0.08, saturation: 0.8, brightness: 0.95)  // orange-ish

    var body: some View {
        Canvas { ctx, size in
            drawPreview(ctx: &ctx, size: size, phase: phase)
        }
        .frame(width: 64, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
        .onDisappear {
            phase = 0
        }
    }

    private func drawPreview(ctx: inout GraphicsContext, size: CGSize, phase: CGFloat) {
        let w = size.width
        let h = size.height
        let p = phase  // 0...1

        // Determine animation style from transition type name
        let name = String(describing: transitionType).lowercased()

        if name.contains("crossdissolve") || name.contains("crossfade") || name.contains("dissolve") || name.contains("fade") {
            // Crossfade
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            var sub = ctx
            sub.opacity = p
            sub.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorB))

        } else if name.contains("dip") {
            // Dip to black: fade out then fade in
            let brightness: CGFloat = p < 0.5 ? 1.0 - (p * 2) : (p - 0.5) * 2
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(.black))
            var sub = ctx
            sub.opacity = brightness
            sub.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(p < 0.5 ? colorA : colorB))

        } else if name.contains("wipeleft") || name.contains("slideleft") || name.contains("left") {
            // Wipe/slide from right to left
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let splitX = w * (1 - p)
            if splitX < w {
                ctx.fill(Path(CGRect(x: splitX, y: 0, width: w - splitX, height: h)), with: .color(colorB))
            }

        } else if name.contains("wiperight") || name.contains("slideright") || name.contains("right") {
            // Wipe/slide from left to right
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let splitX = w * p
            if splitX > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: splitX, height: h)), with: .color(colorB))
            }

        } else if name.contains("wipeup") || name.contains("slideup") || name.contains("up") {
            // Wipe from bottom
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let splitY = h * (1 - p)
            if splitY < h {
                ctx.fill(Path(CGRect(x: 0, y: splitY, width: w, height: h - splitY)), with: .color(colorB))
            }

        } else if name.contains("wipedown") || name.contains("slidedown") || name.contains("down") {
            // Wipe from top
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let splitY = h * p
            if splitY > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: splitY)), with: .color(colorB))
            }

        } else if name.contains("wipeclock") {
            // Clock wipe: radial sweep
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let angle = p * 2 * .pi
            let cx = w / 2
            let cy = h / 2
            let r = max(w, h)
            var piePath = Path()
            piePath.move(to: CGPoint(x: cx, y: cy))
            piePath.addArc(center: CGPoint(x: cx, y: cy),
                           radius: r,
                           startAngle: .radians(-.pi / 2),
                           endAngle: .radians(-.pi / 2 + angle),
                           clockwise: false)
            piePath.closeSubpath()
            ctx.fill(piePath, with: .color(colorB))

        } else if name.contains("wipeiris") || name.contains("iris") {
            // Iris wipe: expanding circle
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let r = p * max(w, h)
            let irisPath = Path(ellipseIn: CGRect(x: w / 2 - r, y: h / 2 - r, width: r * 2, height: r * 2))
            ctx.fill(irisPath, with: .color(colorB))

        } else if name.contains("wipe") || name.contains("slide") || name.contains("push") {
            // Generic wipe/slide — left-to-right reveal
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let splitX = w * p
            if splitX > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: splitX, height: h)), with: .color(colorB))
            }

        } else if name.contains("zoom") || name.contains("scale") {
            // Zoom in
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let scale = max(0.01, p)
            let rw = w * scale
            let rh = h * scale
            ctx.fill(Path(CGRect(x: (w - rw) / 2, y: (h - rh) / 2, width: rw, height: rh)),
                     with: .color(colorB))

        } else if name.contains("rotation") || name.contains("spin") || name.contains("rotat") {
            // Spin: show colorA and colorB split by a rotating diagonal line
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            let angle = p * 2 * .pi
            let cx = w / 2
            let cy = h / 2
            let r = max(w, h)
            var piePath = Path()
            piePath.move(to: CGPoint(x: cx, y: cy))
            piePath.addArc(center: CGPoint(x: cx, y: cy),
                           radius: r,
                           startAngle: .radians(angle),
                           endAngle: .radians(angle + .pi),
                           clockwise: false)
            piePath.closeSubpath()
            ctx.fill(piePath, with: .color(colorB))

        } else if name.contains("pagecurl") || name.contains("curl") {
            // Page curl: folding corner effect
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorB))
            let foldX = w * (1 - p)
            var curlPath = Path()
            curlPath.move(to: CGPoint(x: 0, y: 0))
            curlPath.addLine(to: CGPoint(x: foldX, y: 0))
            curlPath.addLine(to: CGPoint(x: foldX, y: h))
            curlPath.addLine(to: CGPoint(x: 0, y: h))
            curlPath.closeSubpath()
            ctx.fill(curlPath, with: .color(colorA))

        } else if name.contains("blur") || name.contains("glow") {
            // Blur pulse: fade with opacity bands
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            var sub = ctx
            sub.opacity = p
            sub.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorB))

        } else {
            // Fallback: crossfade for any unrecognized transition
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorA))
            var sub = ctx
            sub.opacity = p
            sub.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(colorB))
        }
    }
}

#Preview {
    TransitionPickerSheet(onApply: { _, _, _ in })
}
