// CompBlendMode.swift
// LiquidEditor
//
// Blend modes for multi-track video compositing.
// Each blend mode maps to a specific CIFilter on the native iOS side.

import Foundation

/// Blend modes for compositing overlay tracks onto lower tracks.
///
/// Each maps to a specific CIFilter on the native side.
enum CompBlendMode: String, Codable, CaseIterable, Sendable {
    /// Normal alpha compositing (source-over).
    case normal

    /// Multiply: darkens. CIMultiplyBlendMode.
    case multiply

    /// Screen: lightens. CIScreenBlendMode.
    case screen

    /// Overlay: contrast. CIOverlayBlendMode.
    case overlay

    /// Soft Light. CISoftLightBlendMode.
    case softLight

    /// Hard Light. CIHardLightBlendMode.
    case hardLight

    /// Color Dodge. CIColorDodgeBlendMode.
    case colorDodge

    /// Color Burn. CIColorBurnBlendMode.
    case colorBurn

    /// Darken: min of source and destination. CIDarkenBlendMode.
    case darken

    /// Lighten: max of source and destination. CILightenBlendMode.
    case lighten

    /// Difference. CIDifferenceBlendMode.
    case difference

    /// Exclusion. CIExclusionBlendMode.
    case exclusion

    /// Additive (linear dodge). CIAdditionCompositing.
    case add

    /// Luminosity blend. CILuminosityBlendMode.
    case luminosity

    /// Hue blend. CIHueBlendMode.
    case hue

    /// Saturation blend. CISaturationBlendMode.
    case saturation

    /// Color blend. CIColorBlendMode.
    case color

    /// CIFilter name for this blend mode.
    var ciFilterName: String {
        switch self {
        case .normal:
            return "CISourceOverCompositing"
        case .multiply:
            return "CIMultiplyBlendMode"
        case .screen:
            return "CIScreenBlendMode"
        case .overlay:
            return "CIOverlayBlendMode"
        case .softLight:
            return "CISoftLightBlendMode"
        case .hardLight:
            return "CIHardLightBlendMode"
        case .colorDodge:
            return "CIColorDodgeBlendMode"
        case .colorBurn:
            return "CIColorBurnBlendMode"
        case .darken:
            return "CIDarkenBlendMode"
        case .lighten:
            return "CILightenBlendMode"
        case .difference:
            return "CIDifferenceBlendMode"
        case .exclusion:
            return "CIExclusionBlendMode"
        case .add:
            return "CIAdditionCompositing"
        case .luminosity:
            return "CILuminosityBlendMode"
        case .hue:
            return "CIHueBlendMode"
        case .saturation:
            return "CISaturationBlendMode"
        case .color:
            return "CIColorBlendMode"
        }
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .normal:
            return "Normal"
        case .multiply:
            return "Multiply"
        case .screen:
            return "Screen"
        case .overlay:
            return "Overlay"
        case .softLight:
            return "Soft Light"
        case .hardLight:
            return "Hard Light"
        case .colorDodge:
            return "Color Dodge"
        case .colorBurn:
            return "Color Burn"
        case .darken:
            return "Darken"
        case .lighten:
            return "Lighten"
        case .difference:
            return "Difference"
        case .exclusion:
            return "Exclusion"
        case .add:
            return "Add"
        case .luminosity:
            return "Luminosity"
        case .hue:
            return "Hue"
        case .saturation:
            return "Saturation"
        case .color:
            return "Color"
        }
    }

    /// Category for UI grouping.
    var category: String {
        switch self {
        case .normal:
            return "Normal"
        case .multiply, .darken, .colorBurn:
            return "Darken"
        case .screen, .lighten, .colorDodge, .add:
            return "Lighten"
        case .overlay, .softLight, .hardLight:
            return "Contrast"
        case .difference, .exclusion:
            return "Comparative"
        case .hue, .saturation, .color, .luminosity:
            return "Component"
        }
    }
}

/// Blend mode categories for UI grouping.
let blendModeCategories: [String: [CompBlendMode]] = [
    "Normal": [.normal],
    "Darken": [.multiply, .darken, .colorBurn],
    "Lighten": [.screen, .lighten, .colorDodge, .add],
    "Contrast": [.overlay, .softLight, .hardLight],
    "Comparative": [.difference, .exclusion],
    "Component": [.hue, .saturation, .color, .luminosity],
]
