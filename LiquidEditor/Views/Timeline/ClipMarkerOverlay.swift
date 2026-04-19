// ClipMarkerOverlay.swift
// LiquidEditor
//
// T7-38: Clip-level marker pips + label + keyboard navigation stub.
//
// Renders `ClipMarker` pips horizontally on top of a clip tile. Each
// pip is an 8pt colored circle whose x-position is derived from
// `marker.positionInClip / clipDurationMicros`. Tapping (or
// long-pressing) a pip surfaces a truncated label callout and invokes
// the `onSelect` callback with the tapped marker.
//
// Keyboard navigation (prev / next) is stubbed for a follow-up task
// — see `navigate(_:)` below. The stub is exposed so callers can wire
// it up to a `.focused` / `.keyboardShortcut` modifier in the future
// without changing this view's API.
//
// Pure SwiftUI, iOS 26 native styling.
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.17.

import SwiftUI

// MARK: - ClipMarkerOverlay

@MainActor
struct ClipMarkerOverlay: View {

    // MARK: - Input

    /// Markers to render. Assumed already filtered to the clip's
    /// visible source range by the caller.
    let markers: [ClipMarker]

    /// Clip duration in microseconds. Used to compute pip x-positions
    /// as `positionInClip / clipDurationMicros`.
    let clipDurationMicros: TimeMicros

    /// Width of the clip tile in points.
    let width: CGFloat

    /// Height of the clip tile in points. Pips are vertically
    /// centered; the callout floats slightly above the pip.
    let height: CGFloat

    /// Invoked when the user taps a pip.
    var onSelect: ((ClipMarker) -> Void)?

    // MARK: - State

    /// Currently-selected marker whose label callout is shown.
    @State private var previewed: ClipMarker.ID?

    // MARK: - Constants

    private let pipDiameter: CGFloat = 8
    private let calloutMaxWidth: CGFloat = 96
    private let calloutVerticalOffset: CGFloat = 14

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(markers) { marker in
                pip(for: marker)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .allowsHitTesting(true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clip markers")
    }

    // MARK: - Pip

    @ViewBuilder
    private func pip(for marker: ClipMarker) -> some View {
        let x = xPosition(for: marker)
        let y = height / 2

        ZStack {
            Circle()
                .fill(color(for: marker.color))
                .frame(width: pipDiameter, height: pipDiameter)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

            if previewed == marker.id {
                label(for: marker)
                    .offset(y: -calloutVerticalOffset)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .position(x: x, y: y)
        .contentShape(Rectangle().inset(by: -4))
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                previewed = (previewed == marker.id) ? nil : marker.id
            }
            UISelectionFeedbackGenerator().selectionChanged()
            onSelect?(marker)
        }
        .accessibilityLabel(Text(marker.label))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Label Callout

    @ViewBuilder
    private func label(for marker: ClipMarker) -> some View {
        Text(marker.label)
            .font(.caption2)
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: calloutMaxWidth)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }

    // MARK: - Geometry

    /// Maps `marker.positionInClip` into the pip's x-coordinate.
    /// Clamped to `[pipDiameter/2, width - pipDiameter/2]` so the pip
    /// never clips off the edge of the tile.
    private func xPosition(for marker: ClipMarker) -> CGFloat {
        guard clipDurationMicros > 0 else { return pipDiameter / 2 }
        let fraction = Double(marker.positionInClip) / Double(clipDurationMicros)
        let clamped = min(max(fraction, 0), 1)
        let raw = CGFloat(clamped) * width
        let minX = pipDiameter / 2
        let maxX = max(minX, width - pipDiameter / 2)
        return min(max(raw, minX), maxX)
    }

    // MARK: - Color mapping

    /// Maps the six-color `ClipMarkerColor` palette to SwiftUI colors.
    private func color(for markerColor: ClipMarkerColor) -> Color {
        switch markerColor {
        case .amber: return .orange
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .white: return .white
        }
    }

    // MARK: - Keyboard navigation (stub)

    /// TODO: wire to keyboard shortcuts (`[` / `]`) in a follow-up.
    /// Returns the next (or previous) marker relative to the currently
    /// previewed one, or the first / last when no preview is active.
    enum NavigationDirection { case previous, next }

    func navigate(_ direction: NavigationDirection) -> ClipMarker? {
        // TODO: surface via keyboardShortcut once the focus system lands.
        guard !markers.isEmpty else { return nil }
        let sorted = markers.sorted { $0.positionInClip < $1.positionInClip }
        switch direction {
        case .previous:
            if let current = previewed,
               let idx = sorted.firstIndex(where: { $0.id == current }),
               idx > 0 {
                return sorted[idx - 1]
            }
            return sorted.last
        case .next:
            if let current = previewed,
               let idx = sorted.firstIndex(where: { $0.id == current }),
               idx < sorted.count - 1 {
                return sorted[idx + 1]
            }
            return sorted.first
        }
    }
}

// MARK: - Preview

#Preview {
    ClipMarkerOverlay(
        markers: [
            ClipMarker(positionInClip: 250_000, label: "Intro", color: .amber),
            ClipMarker(positionInClip: 1_500_000, label: "Reaction close-up", color: .green),
            ClipMarker(positionInClip: 2_750_000, label: "Cut", color: .red),
        ],
        clipDurationMicros: 3_000_000,
        width: 320,
        height: 56,
        onSelect: { _ in }
    )
    .padding()
    .background(Color.black)
}
