// SnapGuideOverlay.swift
// LiquidEditor
//
// T7-42: Snap guide vertical lines for the timeline.
//
// Renders an overlay of thin, colored vertical lines that indicate
// active snap targets while a drag is in progress. Each guide has a
// `SnapKind` (playhead / clipEdge / marker / beat) and is colored
// per the Liquid Glass spec:
//
//   playhead  -> amber
//   clipEdge  -> white
//   marker    -> cyan
//   beat      -> purple
//
// The overlay animates in/out with a short fade + slight vertical
// stretch so guides don't pop harshly on drag start.
//
// Pure SwiftUI, iOS 26 native styling.
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.17.

import SwiftUI

// MARK: - SnapKind

/// Type of snap target a guide represents. Drives the guide color.
enum SnapKind: Sendable, Hashable {
    case playhead
    case clipEdge
    case marker
    case beat
}

// MARK: - SnapGuide

/// A single snap guide. `positionSec` is an absolute timeline time.
/// The overlay converts it to an x-coordinate using the
/// `secondsToPoints` closure supplied by the caller.
struct TimelineSnapGuide: Sendable, Hashable, Identifiable {
    let positionSec: Double
    let kind: SnapKind

    var id: String { "\(kind)@\(positionSec)" }
}

// MARK: - SnapGuideOverlay

@MainActor
struct SnapGuideOverlay: View {

    // MARK: - Input

    /// Active snap guides to render. When empty the overlay animates
    /// out.
    let guides: [TimelineSnapGuide]

    /// Total overlay width in points (= timeline content width).
    let width: CGFloat

    /// Total overlay height in points (= timeline content height).
    let height: CGFloat

    /// Converts a timeline time (seconds) into an x-coordinate in
    /// local view space. Callers typically inject
    /// `{ sec in sec * pixelsPerSecond }` with their current zoom.
    let secondsToPoints: (Double) -> CGFloat

    /// Controls the fade-in animation. Typically bound to the
    /// timeline's `isDragging` state — guides fade in when a drag
    /// begins and out when it ends.
    var isActive: Bool = true

    // MARK: - Constants

    private let lineWidth: CGFloat = 1
    private let glowWidth: CGFloat = 3

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(guides) { guide in
                lineView(for: guide)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .opacity(isActive ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: isActive)
        .animation(.easeOut(duration: 0.18), value: guides)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Line

    @ViewBuilder
    private func lineView(for guide: TimelineSnapGuide) -> some View {
        let x = secondsToPoints(guide.positionSec)
        let clamped = min(max(x, 0), width)
        let tint = color(for: guide.kind)

        ZStack {
            // Soft glow — widens the target visually without bleeding
            // the pure line color.
            Rectangle()
                .fill(tint.opacity(0.25))
                .frame(width: glowWidth, height: height)

            // Crisp 1pt line in the semantic color.
            Rectangle()
                .fill(tint.opacity(0.9))
                .frame(width: lineWidth, height: height)
        }
        .compositingGroup()
        .position(x: clamped, y: height / 2)
        .transition(
            .opacity.combined(
                with: .scale(scale: 0.92, anchor: .center)
            )
        )
    }

    // MARK: - Color mapping

    /// Maps the snap kind to the Liquid Glass guide palette.
    private func color(for kind: SnapKind) -> Color {
        switch kind {
        case .playhead: return .orange
        case .clipEdge: return .white
        case .marker: return Color(.cyan)
        case .beat: return .purple
        }
    }
}

// MARK: - Preview

#Preview {
    SnapGuideOverlay(
        guides: [
            TimelineSnapGuide(positionSec: 0.5, kind: .playhead),
            TimelineSnapGuide(positionSec: 1.25, kind: .clipEdge),
            TimelineSnapGuide(positionSec: 2.0, kind: .marker),
            TimelineSnapGuide(positionSec: 3.5, kind: .beat),
        ],
        width: 400,
        height: 120,
        secondsToPoints: { $0 * 80 },
        isActive: true
    )
    .background(Color.black)
}
