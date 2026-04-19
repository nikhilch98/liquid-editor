// TimelineZoomCommand.swift
// LiquidEditor
//
// T7-36 (Premium UI §7.20): Zoom-to-fit and zoom-to-selection for the
// timeline ruler. Returns a new `zoomScale` (pixels-per-microsecond, in
// the same units consumed by `TimelineViewModel`) and, for zoom-to-
// selection, a `scrollOffset` so the selection is centred after the
// zoom.
//
// Empty timelines and empty selections return safe defaults so the
// caller can apply the result unconditionally.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.20
//       (zoom-to-fit / zoom-to-selection).

import CoreGraphics
import Foundation

// MARK: - TimelineZoomCommand

/// Stateless zoom helpers. Marked `@MainActor` because consumers are
/// ViewModels that mutate `@MainActor`-isolated zoom state.
@MainActor
enum TimelineZoomCommand {

    /// Minimum zoom scale (pixels-per-microsecond). Prevents division
    /// blow-ups on near-empty timelines.
    static let minZoomScale: Double = 1e-6

    /// Compute a zoom scale that fits the entire timeline into
    /// `viewportWidth`.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - viewportWidth: The visible ruler width in points.
    /// - Returns: A zoom scale in points-per-microsecond. Falls back to
    ///   `minZoomScale` for empty timelines.
    static func zoomToFit(
        timeline: PersistentTimeline,
        viewportWidth: CGFloat
    ) -> Double {
        let totalMicros = Double(timeline.totalDurationMicros)
        guard totalMicros > 0, viewportWidth > 0 else { return minZoomScale }
        return Double(viewportWidth) / totalMicros
    }

    /// Compute zoom + scroll offset that frames the current selection in
    /// `viewportWidth`.
    ///
    /// - Parameters:
    ///   - timeline: The current timeline.
    ///   - selection: Currently-selected clip IDs.
    ///   - viewportWidth: Visible ruler width in points.
    /// - Returns: `(zoomScale, scrollOffset)`. `scrollOffset` is in
    ///   points and positions the selection at the viewport's left edge.
    static func zoomToSelection(
        timeline: PersistentTimeline,
        selection: Set<String>,
        viewportWidth: CGFloat
    ) -> (zoomScale: Double, scrollOffset: Double) {
        guard !selection.isEmpty, viewportWidth > 0 else {
            return (zoomToFit(timeline: timeline, viewportWidth: viewportWidth), 0)
        }

        // Build the bounding interval covering every selected clip.
        var minStart: TimeMicros = .max
        var maxEnd: TimeMicros = .min
        for id in selection {
            guard let item = timeline.getById(id),
                  let start = timeline.startTimeOf(id) else { continue }
            let end = start + item.durationMicroseconds
            if start < minStart { minStart = start }
            if end > maxEnd { maxEnd = end }
        }

        guard minStart != .max, maxEnd > minStart else {
            return (zoomToFit(timeline: timeline, viewportWidth: viewportWidth), 0)
        }

        let spanMicros = Double(maxEnd - minStart)
        let scale = Double(viewportWidth) / spanMicros
        let offset = Double(minStart) * scale
        return (max(scale, minZoomScale), offset)
    }
}
