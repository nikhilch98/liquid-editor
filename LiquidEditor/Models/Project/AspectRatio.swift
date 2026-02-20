// AspectRatio.swift
// LiquidEditor
//
// Aspect ratio models for project canvas configuration.

import Foundation

// MARK: - AspectRatioMode

/// How clips adapt when the project aspect ratio differs from source.
enum AspectRatioMode: String, Codable, CaseIterable, Sendable {
    /// Fit entirely within frame with bars (letterbox/pillarbox).
    case letterbox
    /// Zoom to fill the frame (crop edges).
    case zoomToFill
    /// Stretch non-uniformly to fill (distort).
    case stretch

    var displayName: String {
        switch self {
        case .letterbox: return "Fit (Letterbox)"
        case .zoomToFill: return "Fill (Crop)"
        case .stretch: return "Stretch"
        }
    }
}

// MARK: - AspectRatioSetting

/// Predefined and custom aspect ratio settings.
///
/// Stores width:height components (e.g., 16:9) and computes
/// the decimal value for calculations.
struct AspectRatioSetting: Codable, Equatable, Hashable, Sendable {

    /// Width component (e.g., 16 for 16:9).
    let widthRatio: Int

    /// Height component (e.g., 9 for 16:9).
    let heightRatio: Int

    /// Display label (e.g., "16:9").
    let label: String

    // MARK: - Computed Properties

    /// Decimal aspect ratio value.
    var value: Double {
        Double(widthRatio) / Double(heightRatio)
    }

    /// Whether this is a landscape orientation.
    var isLandscape: Bool { widthRatio > heightRatio }

    /// Whether this is a portrait orientation.
    var isPortrait: Bool { heightRatio > widthRatio }

    /// Whether this is square.
    var isSquare: Bool { widthRatio == heightRatio }

    // MARK: - Presets

    static let landscape16x9 = AspectRatioSetting(widthRatio: 16, heightRatio: 9, label: "16:9")
    static let portrait9x16 = AspectRatioSetting(widthRatio: 9, heightRatio: 16, label: "9:16")
    static let square1x1 = AspectRatioSetting(widthRatio: 1, heightRatio: 1, label: "1:1")
    static let classic4x3 = AspectRatioSetting(widthRatio: 4, heightRatio: 3, label: "4:3")
    static let portrait3x4 = AspectRatioSetting(widthRatio: 3, heightRatio: 4, label: "3:4")
    static let portrait4x5 = AspectRatioSetting(widthRatio: 4, heightRatio: 5, label: "4:5")
    static let cinematic = AspectRatioSetting(widthRatio: 47, heightRatio: 20, label: "2.35:1")

    static let presets: [AspectRatioSetting] = [
        .landscape16x9,
        .portrait9x16,
        .square1x1,
        .classic4x3,
        .portrait3x4,
        .portrait4x5,
        .cinematic,
    ]

    /// Find a preset matching a given width:height ratio, or nil.
    static func fromWidthHeight(width: Int, height: Int) -> AspectRatioSetting? {
        for preset in presets {
            if preset.widthRatio * height == preset.heightRatio * width {
                return preset
            }
        }
        return nil
    }

    // MARK: - with(...)

    func with(
        widthRatio: Int? = nil,
        heightRatio: Int? = nil,
        label: String? = nil
    ) -> AspectRatioSetting {
        AspectRatioSetting(
            widthRatio: widthRatio ?? self.widthRatio,
            heightRatio: heightRatio ?? self.heightRatio,
            label: label ?? self.label
        )
    }

    // MARK: - Equatable / Hashable

    static func == (lhs: AspectRatioSetting, rhs: AspectRatioSetting) -> Bool {
        lhs.widthRatio == rhs.widthRatio && lhs.heightRatio == rhs.heightRatio
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(widthRatio)
        hasher.combine(heightRatio)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case widthRatio
        case heightRatio
        case label
    }
}
