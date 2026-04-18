// GlassPill.swift
// LiquidEditor
//
// Pill / capsule primitive for the 2026-04-18 premium UI redesign.
// The base container used by the resolution chip, aspect chip, time
// chip, rate chip, and inline selection pills.

import SwiftUI

/// Sizes for ``GlassPill`` matching the spec's sm / md / lg tokens.
enum GlassPillSize {
    case small
    case medium
    case large

    var height: CGFloat {
        switch self {
        case .small:  28
        case .medium: 36
        case .large:  44
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small:  10
        case .medium: 12
        case .large:  14
        }
    }
}

/// Floating capsule / chip surface built on top of LiquidMaterials.
/// Used standalone (label-only) or with optional leading / trailing
/// slots for glyphs.
struct GlassPill<Leading: View, Trailing: View>: View {

    let label: String
    var leading: Leading
    var trailing: Trailing
    var size: GlassPillSize = .small
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: LiquidSpacing.xs) {
            leading
            Text(label)
                .font(size == .small ? LiquidTypography.Caption.font : LiquidTypography.Body.font)
                .foregroundStyle(LiquidColors.Text.primary)
            trailing
        }
        .padding(.horizontal, size.horizontalPadding)
        .frame(height: size.height)
        .background(LiquidMaterials.chrome, in: Capsule())
        .overlay(
            Capsule().stroke(
                isActive ? LiquidColors.Accent.amber : LiquidStroke.hairlineColor,
                lineWidth: isActive ? LiquidStroke.activeWidth : LiquidStroke.hairlineWidth
            )
        )
        .contentShape(Capsule())
    }
}

extension GlassPill where Leading == EmptyView, Trailing == EmptyView {
    init(
        label: String,
        size: GlassPillSize = .small,
        isActive: Bool = false
    ) {
        self.label = label
        self.leading = EmptyView()
        self.trailing = EmptyView()
        self.size = size
        self.isActive = isActive
    }
}
