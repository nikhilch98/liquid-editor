// SafeZoneOverlay.swift
// LiquidEditor
//
// Broadcast and social media safe zone guide overlays for the video
// preview. Renders dashed rectangles with labels for each active
// safe zone preset using SwiftUI Canvas drawing. Includes a settings
// panel with toggles for each preset.
//
// Pure SwiftUI, iOS 26 native styling.
// Matches Flutter SafeZonePainter + SafeZoneSettingsPanel layout.

import SwiftUI

// MARK: - SafeZonePreset

/// Available safe zone presets for overlay display.
enum SafeZonePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case titleSafe
    case actionSafe
    case tikTok
    case instagramReels
    case youTubeShorts
    case broadcast
    case custom

    var id: String { rawValue }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .titleSafe:      "Title Safe"
        case .actionSafe:     "Action Safe"
        case .tikTok:         "TikTok"
        case .instagramReels: "Instagram Reels"
        case .youTubeShorts:  "YouTube Shorts"
        case .broadcast:      "Broadcast"
        case .custom:         "Custom"
        }
    }

    /// Short label for display on the overlay.
    var shortLabel: String {
        switch self {
        case .titleSafe:      "Title Safe"
        case .actionSafe:     "Action Safe"
        case .tikTok:         "TikTok"
        case .instagramReels: "IG Reels"
        case .youTubeShorts:  "YT Shorts"
        case .broadcast:      "Broadcast"
        case .custom:         "Custom"
        }
    }
}

// MARK: - SafeZoneConfig

/// Configuration for safe zone overlays.
struct SafeZoneConfig: Equatable, Sendable {

    /// Set of currently active safe zone presets.
    var activeZones: Set<SafeZonePreset> = []

    /// Custom zone top inset percentage (0-50).
    var customTopPercent: Double = 10.0

    /// Custom zone bottom inset percentage (0-50).
    var customBottomPercent: Double = 10.0

    /// Custom zone left inset percentage (0-50).
    var customLeftPercent: Double = 10.0

    /// Custom zone right inset percentage (0-50).
    var customRightPercent: Double = 10.0

    /// Whether to show text labels on zone boundaries.
    var showLabels: Bool = true
}

// MARK: - SafeZoneInsets

/// Resolved pixel insets for a safe zone relative to a given size.
struct SafeZoneInsets: Equatable, Sendable {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat
}

// MARK: - SafeZoneOverlayView

/// SwiftUI Canvas overlay that draws safe zone boundaries on the video preview.
///
/// Draws dashed rectangles for each active safe zone preset with
/// optional text labels. Each zone has a unique color for easy
/// identification.
struct SafeZoneOverlayView: View {

    /// Configuration for the safe zone overlay.
    let config: SafeZoneConfig

    /// Size of the video preview area to draw over.
    let previewSize: CGSize

    var body: some View {
        if !config.activeZones.isEmpty, previewSize.width > 0, previewSize.height > 0 {
            Canvas { context, size in
                let origin = CGPoint(
                    x: (size.width - previewSize.width) / 2,
                    y: (size.height - previewSize.height) / 2
                )
                for zone in config.activeZones.sorted(by: { $0.rawValue < $1.rawValue }) {
                    drawZone(in: &context, zone: zone, origin: origin)
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Safe zone overlay showing \(config.activeZones.map(\.displayName).joined(separator: ", "))")
        }
    }

    // MARK: - Zone Drawing

    private func drawZone(
        in context: inout GraphicsContext,
        zone: SafeZonePreset,
        origin: CGPoint
    ) {
        let insets = SafeZoneCalculator.insets(for: zone, in: previewSize, config: config)
        let rect = CGRect(
            x: origin.x + insets.left,
            y: origin.y + insets.top,
            width: previewSize.width - insets.left - insets.right,
            height: previewSize.height - insets.top - insets.bottom
        )
        guard rect.width > 0, rect.height > 0 else { return }

        let color = SafeZoneCalculator.color(for: zone)
        drawDashedRect(in: &context, rect: rect, color: color)

        if config.showLabels {
            drawLabel(in: &context, rect: rect, text: zone.shortLabel, color: color)
        }
    }

    // MARK: - Dashed Rectangle

    private func drawDashedRect(
        in context: inout GraphicsContext,
        rect: CGRect,
        color: Color
    ) {
        let dashLength: CGFloat = 6.0
        let gapLength: CGFloat = 4.0

        // Top edge
        drawDashedLine(
            in: &context,
            from: CGPoint(x: rect.minX, y: rect.minY),
            to: CGPoint(x: rect.maxX, y: rect.minY),
            color: color, dashLength: dashLength, gapLength: gapLength
        )
        // Right edge
        drawDashedLine(
            in: &context,
            from: CGPoint(x: rect.maxX, y: rect.minY),
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            color: color, dashLength: dashLength, gapLength: gapLength
        )
        // Bottom edge
        drawDashedLine(
            in: &context,
            from: CGPoint(x: rect.maxX, y: rect.maxY),
            to: CGPoint(x: rect.minX, y: rect.maxY),
            color: color, dashLength: dashLength, gapLength: gapLength
        )
        // Left edge
        drawDashedLine(
            in: &context,
            from: CGPoint(x: rect.minX, y: rect.maxY),
            to: CGPoint(x: rect.minX, y: rect.minY),
            color: color, dashLength: dashLength, gapLength: gapLength
        )
    }

    private func drawDashedLine(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        dashLength: CGFloat,
        gapLength: CGFloat
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }

        let unitDx = dx / length
        let unitDy = dy / length
        var currentLength: CGFloat = 0
        var drawing = true

        while currentLength < length {
            let segmentLength = drawing ? dashLength : gapLength
            let endLength = min(currentLength + segmentLength, length)

            if drawing {
                var path = Path()
                path.move(to: CGPoint(
                    x: start.x + unitDx * currentLength,
                    y: start.y + unitDy * currentLength
                ))
                path.addLine(to: CGPoint(
                    x: start.x + unitDx * endLength,
                    y: start.y + unitDy * endLength
                ))
                context.stroke(path, with: .color(color), lineWidth: 1.0)
            }

            currentLength = endLength
            drawing.toggle()
        }
    }

    // MARK: - Label

    private func drawLabel(
        in context: inout GraphicsContext,
        rect: CGRect,
        text: String,
        color: Color
    ) {
        let resolvedText = context.resolve(
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .tracking(0.3)
                .foregroundStyle(color)
        )
        let labelPoint = CGPoint(x: rect.minX + 4, y: rect.minY + 2)
        // Draw shadow copy first, then main text
        var shadowContext = context
        shadowContext.addFilter(.shadow(color: .black.opacity(0.5), radius: 4))
        shadowContext.draw(resolvedText, at: labelPoint, anchor: .topLeading)
    }
}

// MARK: - SafeZoneCalculator

/// Pure functions for computing safe zone insets and colors.
///
/// Extracted to enable unit testing without requiring view instantiation.
enum SafeZoneCalculator {

    /// Compute pixel insets for a safe zone preset given a size.
    ///
    /// - Parameters:
    ///   - zone: The safe zone preset.
    ///   - size: The dimensions to compute insets for.
    ///   - config: Configuration for custom zone percentages.
    /// - Returns: Resolved pixel insets.
    static func insets(
        for zone: SafeZonePreset,
        in size: CGSize,
        config: SafeZoneConfig = SafeZoneConfig()
    ) -> SafeZoneInsets {
        switch zone {
        case .titleSafe:
            return SafeZoneInsets(
                top: size.height * 0.1,
                left: size.width * 0.1,
                bottom: size.height * 0.1,
                right: size.width * 0.1
            )
        case .actionSafe:
            return SafeZoneInsets(
                top: size.height * 0.05,
                left: size.width * 0.05,
                bottom: size.height * 0.05,
                right: size.width * 0.05
            )
        case .tikTok:
            return SafeZoneInsets(
                top: size.height * 0.15,
                left: size.width * 0.05,
                bottom: size.height * 0.25,
                right: size.width * 0.05
            )
        case .instagramReels:
            return SafeZoneInsets(
                top: size.height * 0.12,
                left: size.width * 0.05,
                bottom: size.height * 0.20,
                right: size.width * 0.05
            )
        case .youTubeShorts:
            return SafeZoneInsets(
                top: size.height * 0.10,
                left: size.width * 0.05,
                bottom: size.height * 0.15,
                right: size.width * 0.05
            )
        case .broadcast:
            return SafeZoneInsets(
                top: size.height * 0.10,
                left: size.width * 0.10,
                bottom: size.height * 0.10,
                right: size.width * 0.10
            )
        case .custom:
            return SafeZoneInsets(
                top: size.height * config.customTopPercent / 100,
                left: size.width * config.customLeftPercent / 100,
                bottom: size.height * config.customBottomPercent / 100,
                right: size.width * config.customRightPercent / 100
            )
        }
    }

    /// Get the display color for a safe zone preset.
    ///
    /// - Parameter zone: The safe zone preset.
    /// - Returns: The associated color with appropriate opacity.
    static func color(for zone: SafeZonePreset) -> Color {
        switch zone {
        case .titleSafe:      Color.yellow.opacity(0.6)
        case .actionSafe:     Color.green.opacity(0.5)
        case .tikTok:         Color.pink.opacity(0.5)
        case .instagramReels: Color.purple.opacity(0.5)
        case .youTubeShorts:  Color.red.opacity(0.5)
        case .broadcast:      Color.teal.opacity(0.5)
        case .custom:         Color.blue.opacity(0.5)
        }
    }
}

// MARK: - SafeZoneSettingsPanel

/// Settings panel for configuring safe zone overlays.
///
/// Contains a toggle for each `SafeZonePreset` case, plus a
/// "Show Labels" toggle. Styled with native `List` and
/// `.listStyle(.insetGrouped)`.
struct SafeZoneSettingsPanel: View {

    /// Binding to the safe zone configuration.
    @Binding var config: SafeZoneConfig

    var body: some View {
        List {
            Section(header: Text("SAFE ZONES")) {
                // Toggle for each preset.
                ForEach(SafeZonePreset.allCases) { preset in
                    Toggle(preset.displayName, isOn: zoneBinding(for: preset))
                }

                // Show Labels toggle.
                Toggle("Show Labels", isOn: $config.showLabels)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Zone Toggle Binding

    /// Creates a binding that toggles a specific preset in `activeZones`.
    private func zoneBinding(for preset: SafeZonePreset) -> Binding<Bool> {
        Binding<Bool>(
            get: { config.activeZones.contains(preset) },
            set: { isActive in
                if isActive {
                    config.activeZones.insert(preset)
                } else {
                    config.activeZones.remove(preset)
                }
            }
        )
    }
}
