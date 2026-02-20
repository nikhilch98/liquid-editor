// CropSheet.swift
// LiquidEditor
//
// Crop and rotation sheet view matching Flutter predecessor layout.
// Pure iOS 26 SwiftUI with native styling.

import SwiftUI

/// Aspect ratio presets for crop.
enum CropAspectRatio: String, CaseIterable, Identifiable {
    case original = "Original"
    case r1x1 = "1:1"
    case r4x3 = "4:3"
    case r16x9 = "16:9"
    case r9x16 = "9:16"
    case r4x5 = "4:5"
    case r235x1 = "2.35:1"
    case free = "Free"

    var id: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .original: "photo"
        case .r1x1: "square"
        case .r4x3: "rectangle.ratio.4.to.3"
        case .r16x9: "rectangle"
        case .r9x16: "rectangle.portrait"
        case .r4x5: "rectangle.portrait"
        case .r235x1: "rectangle"
        case .free: "crop"
        }
    }

    var ratio: Double? {
        switch self {
        case .original: return nil
        case .r1x1: return 1.0
        case .r4x3: return 4.0 / 3.0
        case .r16x9: return 16.0 / 9.0
        case .r9x16: return 9.0 / 16.0
        case .r4x5: return 4.0 / 5.0
        case .r235x1: return 2.35
        case .free: return nil
        }
    }

    /// Whether this preset disables aspect ratio constraints.
    var isFree: Bool { self == .free }
}

struct CropSheet: View {

    @State private var selectedAspectRatio: CropAspectRatio
    @State private var rotation90: Int // 0, 1, 2, 3 for 0/90/180/270 degrees
    @State private var isFlippedHorizontally: Bool
    @State private var isFlippedVertically: Bool

    @Environment(\.dismiss) private var dismiss

    let onApply: (CropAspectRatio, Double, Bool, Bool) -> Void

    init(
        initialAspectRatio: CropAspectRatio = .original,
        initialRotation: Double = 0,
        initialFlipH: Bool = false,
        initialFlipV: Bool = false,
        onApply: @escaping (CropAspectRatio, Double, Bool, Bool) -> Void
    ) {
        _selectedAspectRatio = State(initialValue: initialAspectRatio)
        _rotation90 = State(initialValue: Int(initialRotation / 90.0) % 4)
        _isFlippedHorizontally = State(initialValue: initialFlipH)
        _isFlippedVertically = State(initialValue: initialFlipV)
        self.onApply = onApply
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title, aspect ratio badge, reset, X close
            headerRow
                .padding(.horizontal)
                .padding(.top, LiquidSpacing.lg)
                .padding(.bottom, LiquidSpacing.sm)

            Divider()
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: LiquidSpacing.xl) {
                    // Aspect Ratio section label
                    Text("Aspect Ratio")
                        .font(LiquidTypography.captionMedium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .accessibilityAddTraits(.isHeader)

                    // Aspect ratio chips - horizontal scroll, text-only
                    aspectRatioChips

                    // Free crop dashed border preview indicator
                    if selectedAspectRatio.isFree {
                        freeCropPreview
                    }

                    // Transform section label
                    Text("Transform")
                        .font(LiquidTypography.captionMedium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .accessibilityAddTraits(.isHeader)

                    // Rotation and flip controls
                    transformControls
                }
                .padding(.vertical, LiquidSpacing.sm)
            }

            Divider()
                .padding(.horizontal)

            // Full-width Apply button
            Button {
                let rotationDegrees = Double(rotation90 * 90)
                onApply(selectedAspectRatio, rotationDegrees, isFlippedHorizontally, isFlippedVertically)
                dismiss()
            } label: {
                Text("Apply")
                    .font(LiquidTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .padding(.horizontal, LiquidSpacing.lg)
            .padding(.vertical, LiquidSpacing.md)
            .accessibilityLabel("Apply crop settings")
            .accessibilityHint("Applies the selected aspect ratio, rotation, and flip settings")
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Crop & Rotate")
                .font(LiquidTypography.headline)

            Spacer()

            // Aspect ratio badge (teal)
            Text(selectedAspectRatio.rawValue)
                .font(LiquidTypography.captionMedium)
                .foregroundStyle(.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, LiquidSpacing.xs)
                .background(Color.teal.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                .accessibilityLabel("Current aspect ratio: \(selectedAspectRatio.rawValue)")

            // Reset button
            Button("Reset") {
                resetAll()
            }
            .font(LiquidTypography.caption)
            .foregroundStyle(.secondary)
            .accessibilityHint("Resets crop and rotation to default values")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Dismisses the crop sheet")
        }
    }

    // MARK: - Aspect Ratio Chips

    private var aspectRatioChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LiquidSpacing.sm) {
                ForEach(CropAspectRatio.allCases) { ratio in
                    aspectRatioChip(ratio)
                }
            }
            .padding(.horizontal)
        }
    }

    private func aspectRatioChip(_ ratio: CropAspectRatio) -> some View {
        let isSelected = selectedAspectRatio == ratio

        return Button {
            withAnimation(.snappy) {
                selectedAspectRatio = ratio
            }
        } label: {
            Text(ratio.rawValue)
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, LiquidSpacing.sm)
                .background(
                    isSelected
                        ? Color.teal.opacity(0.2)
                        : Color(.secondarySystemGroupedBackground)
                )
                .foregroundStyle(isSelected ? .teal : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aspect ratio \(ratio.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Free Crop Preview

    /// Dashed border indicator shown when Free crop mode is active.
    private var freeCropPreview: some View {
        RoundedRectangle(cornerRadius: LiquidSpacing.cornerMedium)
            .strokeBorder(
                Color.teal.opacity(0.6),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
            .frame(height: 80)
            .overlay {
                HStack(spacing: LiquidSpacing.sm) {
                    Image(systemName: "crop")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.teal)
                    Text("Free crop — no aspect constraint")
                        .font(LiquidTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Transform Controls

    private var transformControls: some View {
        HStack(spacing: LiquidSpacing.sm) {
            // CCW rotation button
            actionButton(label: "CCW", symbol: "rotate.left", isActive: false) {
                rotation90 = (rotation90 + 3) % 4
            }
            .accessibilityLabel("Rotate counter-clockwise 90°")

            // Rotation degree display
            Text("\(rotation90 * 90)\u{00B0}")
                .font(LiquidTypography.captionMedium)
                .foregroundStyle(rotation90 != 0 ? .teal : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, LiquidSpacing.sm)
                .background(
                    rotation90 != 0
                        ? Color.teal.opacity(0.15)
                        : Color(.secondarySystemGroupedBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Current rotation: \(rotation90 * 90) degrees")

            // CW rotation button
            actionButton(label: "CW", symbol: "rotate.right", isActive: false) {
                rotation90 = (rotation90 + 1) % 4
            }
            .accessibilityLabel("Rotate clockwise 90°")

            Spacer().frame(width: LiquidSpacing.sm)

            // Flip H button
            actionButton(
                label: "Flip H",
                symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                isActive: isFlippedHorizontally
            ) {
                isFlippedHorizontally.toggle()
            }
            .accessibilityLabel("Flip horizontal")

            // Flip V button
            actionButton(
                label: "Flip V",
                symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                isActive: isFlippedVertically
            ) {
                isFlippedVertically.toggle()
            }
            .accessibilityLabel("Flip vertical")
        }
        .padding(.horizontal)
    }

    private func actionButton(
        label: String,
        symbol: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: LiquidSpacing.xxs) {
                Image(systemName: symbol)
                    .font(LiquidTypography.body)
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundStyle(isActive ? .teal : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? Color.teal.opacity(0.15)
                    : Color(.secondarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func resetAll() {
        withAnimation(.snappy) {
            selectedAspectRatio = .original
            rotation90 = 0
            isFlippedHorizontally = false
            isFlippedVertically = false
        }
    }
}

// MARK: - CropInlinePanel

/// Compact inline crop panel for embedding directly in the editor layout.
///
/// Displays a horizontally scrollable row of aspect ratio chips (Original,
/// 1:1, 4:3, 16:9, 9:16, 4:5, Free) followed by a row of rotation stepper
/// and flip buttons. Height is approximately 100pt.
///
/// `onChanged` is called on every interaction for real-time preview.
struct CropInlinePanel: View {

    @State private var selectedAspectRatio: CropAspectRatio
    @State private var rotation90: Int
    @State private var isFlippedHorizontally: Bool
    @State private var isFlippedVertically: Bool

    var onChanged: (CropAspectRatio, Double, Bool, Bool) -> Void

    /// Ordered set of presets shown in the inline panel.
    private let inlinePresets: [CropAspectRatio] = [
        .original, .r1x1, .r4x3, .r16x9, .r9x16, .r4x5, .free
    ]

    init(
        initialAspectRatio: CropAspectRatio = .original,
        initialRotation: Double = 0,
        initialFlipH: Bool = false,
        initialFlipV: Bool = false,
        onChanged: @escaping (CropAspectRatio, Double, Bool, Bool) -> Void = { _, _, _, _ in }
    ) {
        _selectedAspectRatio = State(initialValue: initialAspectRatio)
        _rotation90 = State(initialValue: Int(initialRotation / 90.0) % 4)
        _isFlippedHorizontally = State(initialValue: initialFlipH)
        _isFlippedVertically = State(initialValue: initialFlipV)
        self.onChanged = onChanged
    }

    var body: some View {
        VStack(spacing: LiquidSpacing.sm) {
            // Horizontally scrollable aspect ratio chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LiquidSpacing.sm) {
                    ForEach(inlinePresets) { ratio in
                        inlineChip(ratio)
                    }
                }
                .padding(.horizontal, LiquidSpacing.lg)
            }

            // Rotation stepper + flip buttons
            HStack(spacing: LiquidSpacing.sm) {
                // CCW
                inlineIconButton(
                    symbol: "rotate.left",
                    isActive: false,
                    accessibilityLabel: "Rotate counter-clockwise 90°"
                ) {
                    rotation90 = (rotation90 + 3) % 4
                    notifyChanged()
                }

                // Degree display
                Text("\(rotation90 * 90)°")
                    .font(LiquidTypography.captionMedium)
                    .foregroundStyle(rotation90 != 0 ? .teal : .secondary)
                    .frame(minWidth: 44)
                    .accessibilityLabel("Current rotation: \(rotation90 * 90) degrees")

                // CW
                inlineIconButton(
                    symbol: "rotate.right",
                    isActive: false,
                    accessibilityLabel: "Rotate clockwise 90°"
                ) {
                    rotation90 = (rotation90 + 1) % 4
                    notifyChanged()
                }

                Spacer()

                // Flip H
                inlineIconButton(
                    symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    isActive: isFlippedHorizontally,
                    accessibilityLabel: "Flip horizontal"
                ) {
                    isFlippedHorizontally.toggle()
                    notifyChanged()
                }

                // Flip V
                inlineIconButton(
                    symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                    isActive: isFlippedVertically,
                    accessibilityLabel: "Flip vertical"
                ) {
                    isFlippedVertically.toggle()
                    notifyChanged()
                }
            }
            .padding(.horizontal, LiquidSpacing.lg)
        }
        .frame(height: 100)
    }

    // MARK: Private helpers

    private func inlineChip(_ ratio: CropAspectRatio) -> some View {
        let isSelected = selectedAspectRatio == ratio

        return Button {
            withAnimation(.snappy) {
                selectedAspectRatio = ratio
            }
            notifyChanged()
        } label: {
            Text(ratio.rawValue)
                .font(LiquidTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, LiquidSpacing.xs + 2)
                .background(
                    isSelected
                        ? Color.teal.opacity(0.2)
                        : Color(.secondarySystemGroupedBackground)
                )
                .foregroundStyle(isSelected ? .teal : .primary)
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
                // Dashed border overlay when Free is selected
                .overlay {
                    if ratio.isFree && isSelected {
                        RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall)
                            .strokeBorder(
                                Color.teal.opacity(0.7),
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aspect ratio \(ratio.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func inlineIconButton(
        symbol: String,
        isActive: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(LiquidTypography.body)
                .foregroundStyle(isActive ? .teal : .primary)
                .frame(width: 36, height: 36)
                .background(
                    isActive
                        ? Color.teal.opacity(0.15)
                        : Color(.secondarySystemGroupedBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerSmall))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func notifyChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
        onChanged(selectedAspectRatio, Double(rotation90 * 90), isFlippedHorizontally, isFlippedVertically)
    }
}

#Preview("Sheet") {
    CropSheet { _, _, _, _ in }
}

#Preview("Inline Panel") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            CropInlinePanel()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: LiquidSpacing.cornerLarge))
                .padding()
        }
    }
}
