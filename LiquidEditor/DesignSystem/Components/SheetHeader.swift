// SheetHeader.swift
// LiquidEditor
//
// Shared sheet top bar for the 2026-04-18 premium UI redesign.

import SwiftUI

/// 56pt glass header used by every bottom sheet.
/// Layout: [close] [title centered] [Apply CTA or trailing slot].
struct SheetHeader<Trailing: View>: View {

    let title: String
    let onClose: () -> Void
    var trailing: Trailing

    var body: some View {
        ZStack {
            HStack {
                IconButton(systemName: "xmark", accessibilityLabel: "Close", action: onClose)
                Spacer(minLength: 0)
                trailing
            }
            Text(title)
                .font(LiquidTypography.Title.font)
                .foregroundStyle(LiquidColors.Text.primary)
        }
        .padding(.horizontal, LiquidSpacing.md)
        .frame(height: 56)
        .background(LiquidMaterials.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LiquidStroke.hairlineColor)
                .frame(height: LiquidStroke.hairlineWidth)
        }
    }
}

extension SheetHeader where Trailing == AnyView {
    /// Convenience init with an Apply CTA on the right.
    init(title: String, onClose: @escaping () -> Void, onApply: @escaping () -> Void) {
        self.title = title
        self.onClose = onClose
        self.trailing = AnyView(
            PrimaryCTA(title: "Apply", action: onApply)
        )
    }

    /// Convenience init without a trailing action.
    init(title: String, onClose: @escaping () -> Void) {
        self.title = title
        self.onClose = onClose
        self.trailing = AnyView(Spacer().frame(width: 44))
    }
}
