// GapView.swift
// LiquidEditor
//
// Renders a timeline gap (empty space between clips) using a Canvas-based
// diagonal hatched pattern with optional selection state.
//
// Matches Flutter TimelineGapWidget styling:
// - Dark semi-transparent background with glass blur
// - Diagonal hatched lines pattern (12pt spacing)
// - Rounded border (1pt normal, 2pt selected)
// - X icon for gaps wider than 60pt
// - Haptic feedback on tap and double-tap
//
// Pure SwiftUI, iOS 26 native styling.

import SwiftUI
import UIKit

// MARK: - GapView

struct GapView: View {

    // MARK: - Properties

    /// Width of the gap in points.
    let width: CGFloat

    /// Height of the gap in points.
    let height: CGFloat

    /// Whether this gap is currently selected.
    var isSelected: Bool = false

    /// Callback when the gap is tapped (for selection).
    var onTap: (() -> Void)? = nil

    /// Callback when the gap is double-tapped (to close / ripple-delete).
    var onDoubleTap: (() -> Void)? = nil

    // MARK: - Constants

    /// Minimum visible width so the gap remains selectable even when very short.
    private static let minWidth: CGFloat = 20

    private static let borderRadius: CGFloat = 4
    private static let selectedBorderWidth: CGFloat = 2
    private static let normalBorderWidth: CGFloat = 1

    // Hatched pattern
    private static let patternSpacing: CGFloat = 12
    private static let patternStrokeWidth: CGFloat = 1
    private static let iconSize: CGFloat = 12
    private static let iconStrokeWidth: CGFloat = 2
    private static let minWidthForIcon: CGFloat = 60

    // Color opacities
    private static let backgroundOpacity: Double = 0.55
    private static let selectedBorderOpacity: Double = 0.85
    private static let normalBorderOpacity: Double = 0.3
    private static let selectedLineOpacity: Double = 0.5
    private static let normalLineOpacity: Double = 0.3
    private static let iconOpacity: Double = 0.4

    // MARK: - Computed

    private var effectiveWidth: CGFloat {
        max(width, Self.minWidth)
    }

    private var borderColor: Color {
        isSelected
            ? Color.yellow.opacity(Self.selectedBorderOpacity)
            : Color.secondary.opacity(Self.normalBorderOpacity)
    }

    private var borderLineWidth: CGFloat {
        isSelected ? Self.selectedBorderWidth : Self.normalBorderWidth
    }

    // MARK: - Body

    var body: some View {
        hatchedContent
            .frame(width: effectiveWidth, height: height)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Self.borderRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.borderRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderLineWidth)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onTapGesture {
                UISelectionFeedbackGenerator().selectionChanged()
                onTap?()
            }
            .onTapGesture(count: 2) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDoubleTap?()
            }
            .accessibilityElement()
            .accessibilityLabel("Timeline gap")
            .accessibilityHint(isSelected ? "Double tap to close gap" : "Tap to select gap")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Hatched Canvas

    private var hatchedContent: some View {
        Canvas { context, size in
            // Background fill
            let bgRect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(bgRect),
                with: .color(Color(white: 0.08).opacity(Self.backgroundOpacity))
            )

            // Diagonal hatched lines — bottom-left to top-right direction
            let lineOpacity = isSelected ? Self.selectedLineOpacity : Self.normalLineOpacity
            var lineStyle = StrokeStyle(lineWidth: Self.patternStrokeWidth)
            lineStyle.lineCap = .square

            let diagonal = sqrt(size.width * size.width + size.height * size.height)
            let count = Int(diagonal / Self.patternSpacing) * 2 + 2

            for i in -count..<count {
                let offset = CGFloat(i) * Self.patternSpacing
                var path = Path()
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + size.height, y: size.height))

                context.stroke(
                    path,
                    with: .color(Color.gray.opacity(lineOpacity)),
                    style: lineStyle
                )
            }

            // X icon for wide gaps
            if size.width > Self.minWidthForIcon {
                let cx = size.width / 2
                let cy = size.height / 2
                let half = Self.iconSize / 2

                var iconPath = Path()
                iconPath.move(to: CGPoint(x: cx - half, y: cy - half))
                iconPath.addLine(to: CGPoint(x: cx + half, y: cy + half))
                iconPath.move(to: CGPoint(x: cx + half, y: cy - half))
                iconPath.addLine(to: CGPoint(x: cx - half, y: cy + half))

                var iconStyle = StrokeStyle(lineWidth: Self.iconStrokeWidth)
                iconStyle.lineCap = .round

                context.stroke(
                    iconPath,
                    with: .color(Color.gray.opacity(Self.iconOpacity)),
                    style: iconStyle
                )
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("GapView") {
    ZStack {
        Color.black
        VStack(spacing: 16) {
            GapView(width: 120, height: 56, isSelected: false)
            GapView(width: 120, height: 56, isSelected: true)
            GapView(width: 30, height: 56, isSelected: false)
        }
        .padding()
    }
}
#endif
