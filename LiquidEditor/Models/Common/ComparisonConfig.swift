// ComparisonConfig.swift
// LiquidEditor
//
// Before/after comparison configuration for video editing.
// Supports split screen, toggle, and side-by-side modes.
//

import Foundation

// MARK: - ComparisonMode

/// Available comparison display modes for before/after preview.
///
/// Each mode provides a different way to compare original (unmodified)
/// content against edited (with effects/transforms) content.
enum ComparisonMode: String, CaseIterable, Identifiable, Codable, Sendable {

    /// Comparison is disabled; only edited content is shown.
    case off

    /// Vertical divider splits the frame horizontally.
    /// User can drag the divider to reveal more of either side.
    case splitScreen

    /// Hold to show original, release for edited.
    /// Crossfade animation between views.
    case toggle

    /// Two side-by-side previews showing original and edited simultaneously.
    case sideBySide

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - Display

    /// Human-readable display name for UI presentation.
    var displayName: String {
        switch self {
        case .off:
            "Off"
        case .splitScreen:
            "Split Screen"
        case .toggle:
            "Toggle"
        case .sideBySide:
            "Side by Side"
        }
    }
}

// MARK: - ComparisonConfig

/// Configuration for the comparison view.
///
/// Tracks the current comparison mode, the split divider position
/// (for split screen mode), and whether the original is currently
/// showing (for toggle mode).
struct ComparisonConfig: Equatable, Sendable {

    /// Current comparison mode.
    let mode: ComparisonMode

    /// Position of the split divider (0.1 to 0.9).
    ///
    /// A value of 0.5 places the divider at the center.
    /// Clamped on creation and via `copyWith` to prevent
    /// the divider from reaching the edges.
    let splitPosition: Double

    /// Whether currently showing the original in toggle mode.
    let showingOriginal: Bool

    // MARK: - Initialization

    /// Creates a comparison configuration with the given values.
    ///
    /// - Parameters:
    ///   - mode: The comparison mode. Defaults to `.off`.
    ///   - splitPosition: Divider position (0.1...0.9). Defaults to 0.5.
    ///     Values outside the range are clamped.
    ///   - showingOriginal: Whether original content is visible in toggle mode.
    ///     Defaults to `false`.
    init(
        mode: ComparisonMode = .off,
        splitPosition: Double = 0.5,
        showingOriginal: Bool = false
    ) {
        self.mode = mode
        self.splitPosition = min(max(splitPosition, 0.1), 0.9)
        self.showingOriginal = showingOriginal
    }

    // MARK: - Copy With

    /// Create a copy with modified fields.
    ///
    /// Any parameter set to `nil` retains the current value.
    /// The `splitPosition` is clamped to 0.1...0.9.
    func copyWith(
        mode: ComparisonMode? = nil,
        splitPosition: Double? = nil,
        showingOriginal: Bool? = nil
    ) -> ComparisonConfig {
        ComparisonConfig(
            mode: mode ?? self.mode,
            splitPosition: splitPosition ?? self.splitPosition,
            showingOriginal: showingOriginal ?? self.showingOriginal
        )
    }
}
