// LiquidMaterials.swift
// LiquidEditor
//
// Material / glass tokens for the 2026-04-18 premium UI redesign.

import SwiftUI

/// Material styles keyed by the role they play in the shell.
enum LiquidMaterials {
    /// For floating chrome: nav bars, bottom toolbar, sheet headers.
    static let chrome: Material = .ultraThinMaterial

    /// For floating sheets and popovers. Pair with a 14% white overlay.
    static let float: Material = .regularMaterial
}
