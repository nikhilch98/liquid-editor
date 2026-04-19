// TimelineEdgeAutoScrollModifier.swift
// LiquidEditor
//
// T7-43 (Premium UI §10.3): When the user drags a clip near the left or
// right edge of the visible timeline, fire `onEdgeHover(direction, speed)`
// so the caller can auto-scroll the timeline. `speed` is 0.0..1.0 and
// scales with proximity — closer to the edge = faster scroll.
//
// This modifier is PASSIVE: it observes a drag location passed in via
// `@Binding dragLocation` (the caller updates this from its own drag
// gesture). That keeps the scroll driver decoupled from the specific
// gesture (clip drag, trim drag, lasso, etc.).
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Edge-hover direction for auto-scroll.
enum AutoScrollDirection: Equatable, Sendable {
    case leading
    case trailing
}

/// Drives auto-scroll when a drag hovers near the left/right edge.
struct TimelineEdgeAutoScrollModifier: ViewModifier {

    /// Current drag location in the modified view's local coordinate
    /// space. When `nil`, no drag is active and no callback fires.
    @Binding var dragLocation: CGPoint?

    /// Proximity threshold in points. Default §10.3: 40pt.
    let edgeThreshold: CGFloat

    let onEdgeHover: (AutoScrollDirection, Double) -> Void

    init(
        dragLocation: Binding<CGPoint?>,
        edgeThreshold: CGFloat = 40,
        onEdgeHover: @escaping (AutoScrollDirection, Double) -> Void
    ) {
        self._dragLocation = dragLocation
        self.edgeThreshold = edgeThreshold
        self.onEdgeHover = onEdgeHover
    }

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .onChange(of: dragLocation) { _, loc in
                    guard let loc else { return }
                    let width = proxy.size.width
                    guard width > 0 else { return }
                    let leadingDistance = loc.x
                    let trailingDistance = width - loc.x
                    if leadingDistance < edgeThreshold {
                        let speed = clampedSpeed(for: leadingDistance)
                        onEdgeHover(.leading, speed)
                    } else if trailingDistance < edgeThreshold {
                        let speed = clampedSpeed(for: trailingDistance)
                        onEdgeHover(.trailing, speed)
                    }
                }
        }
    }

    /// Returns a 0..1 speed where `0` = exactly at threshold and `1` =
    /// at or past the edge itself.
    private func clampedSpeed(for distance: CGFloat) -> Double {
        let clamped = max(0, min(edgeThreshold, distance))
        return Double(1 - (clamped / edgeThreshold))
    }
}

extension View {
    /// Attach timeline edge-proximity auto-scroll detection.
    func timelineEdgeAutoScroll(
        dragLocation: Binding<CGPoint?>,
        edgeThreshold: CGFloat = 40,
        onEdgeHover: @escaping (AutoScrollDirection, Double) -> Void
    ) -> some View {
        modifier(TimelineEdgeAutoScrollModifier(
            dragLocation: dragLocation,
            edgeThreshold: edgeThreshold,
            onEdgeHover: onEdgeHover
        ))
    }
}
