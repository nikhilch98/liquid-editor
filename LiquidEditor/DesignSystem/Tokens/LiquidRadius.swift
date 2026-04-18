// LiquidRadius.swift
// LiquidEditor
//
// Corner radius scale for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Corner radius scale — consumer side pairs with the RoundedRectangle
/// style `.continuous` (the "squircle" look iOS 26 uses everywhere).
enum LiquidRadius {
    /// Tool chips.
    static let sm: CGFloat = 6
    /// Clips, cards.
    static let md: CGFloat = 10
    /// Sheets.
    static let lg: CGFloat = 16
    /// Floating pills.
    static let xl: CGFloat = 22
    /// Capsules / FABs.
    static let full: CGFloat = 999
}
