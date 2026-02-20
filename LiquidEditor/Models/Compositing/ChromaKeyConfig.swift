// ChromaKeyConfig.swift
// LiquidEditor
//
// Chroma key (green/blue screen) configuration model.
// Defines the parameters for background removal from overlay footage.
// Used by the native MultiTrackCompositor via CIColorCube filter.

import Foundation

/// Target color for chroma key removal.
enum ChromaKeyColor: String, Codable, CaseIterable, Sendable {
    /// Standard green screen (#00FF00 range).
    case green

    /// Blue screen.
    case blue

    /// User-picked custom color.
    case custom

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .green:
            return "Green"
        case .blue:
            return "Blue"
        case .custom:
            return "Custom"
        }
    }
}

/// Chroma key configuration for background removal.
///
/// Controls how aggressively the target color is removed
/// and how smooth the edges are between foreground and background.
struct ChromaKeyConfig: Codable, Equatable, Hashable, Sendable {
    /// Target color to remove.
    let targetColor: ChromaKeyColor

    /// Custom color value (used when ``targetColor`` is ``ChromaKeyColor/custom``).
    ///
    /// ARGB color value. Alpha channel is ignored.
    let customColorValue: Int?

    /// Sensitivity: how close a pixel color must be to the target (0.0-1.0).
    ///
    /// Lower = more selective (less removal).
    /// Higher = more aggressive (more removal, may eat into foreground).
    let sensitivity: Double

    /// Smoothness of the edge transition (0.0-1.0).
    ///
    /// Higher = smoother, softer edges between foreground and background.
    /// Lower = harder, sharper edges.
    let smoothness: Double

    /// Spill suppression strength (0.0-1.0).
    ///
    /// Removes color cast from edges of the foreground subject
    /// caused by light reflecting off the green/blue screen.
    let spillSuppression: Double

    /// Whether chroma key processing is enabled.
    let isEnabled: Bool

    init(
        targetColor: ChromaKeyColor = .green,
        customColorValue: Int? = nil,
        sensitivity: Double = 0.4,
        smoothness: Double = 0.1,
        spillSuppression: Double = 0.5,
        isEnabled: Bool = true
    ) {
        self.targetColor = targetColor
        self.customColorValue = customColorValue
        self.sensitivity = sensitivity
        self.smoothness = smoothness
        self.spillSuppression = spillSuppression
        self.isEnabled = isEnabled
    }

    /// Default green screen configuration.
    static let defaultGreen = ChromaKeyConfig()

    /// Default blue screen configuration.
    static let defaultBlue = ChromaKeyConfig(targetColor: .blue)

    /// Get the effective color as an ARGB integer.
    var effectiveColorARGB: Int {
        switch targetColor {
        case .green:
            return 0xFF00_FF00
        case .blue:
            return 0xFF00_00FF
        case .custom:
            return customColorValue ?? 0xFF00_FF00
        }
    }

    /// Create a copy with updated fields.
    func with(
        targetColor: ChromaKeyColor? = nil,
        customColorValue: Int?? = nil,
        sensitivity: Double? = nil,
        smoothness: Double? = nil,
        spillSuppression: Double? = nil,
        isEnabled: Bool? = nil
    ) -> ChromaKeyConfig {
        ChromaKeyConfig(
            targetColor: targetColor ?? self.targetColor,
            customColorValue: customColorValue ?? self.customColorValue,
            sensitivity: sensitivity ?? self.sensitivity,
            smoothness: smoothness ?? self.smoothness,
            spillSuppression: spillSuppression ?? self.spillSuppression,
            isEnabled: isEnabled ?? self.isEnabled
        )
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case targetColor
        case customColorValue
        case sensitivity
        case smoothness
        case spillSuppression
        case isEnabled
    }
}

// MARK: - CustomStringConvertible

extension ChromaKeyConfig: CustomStringConvertible {
    var description: String {
        "ChromaKeyConfig(\(targetColor.rawValue), sensitivity: \(sensitivity), smoothness: \(smoothness))"
    }
}
