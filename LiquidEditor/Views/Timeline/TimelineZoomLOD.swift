// TimelineZoomLOD.swift
// LiquidEditor
//
// T7-44: Level-of-detail policy for the timeline ruler + clip renderers.
// Zooming out far enough on a long timeline produces thousands of tiny
// thumbnails and waveform spans that blow out both GPU bandwidth and
// main-thread layout. At those scales we can elide detail without the
// user noticing (they literally cannot see it).
//
// This file defines the discrete LOD levels, the per-LOD rendering
// budgets, and the selector that maps a live zoom scale onto the
// correct level.
//
// The zoom scale unit is "seconds per 100pt of screen width" — smaller
// number means more zoomed-in.
//
// Spec: docs/superpowers/specs/2026-04-18-premium-ui-redesign-spec.md §7.14
//       (timeline LOD / virtualization).

import Foundation

// MARK: - TimelineLODLevel

/// Discrete LOD levels applied to the timeline ruler, thumbnails, and
/// waveforms. Ordered coarsest → finest.
enum TimelineLODLevel: String, Sendable, CaseIterable {

    /// Very zoomed out — thousands of seconds across the screen.
    /// Use for project overview / "fit whole project" mode.
    case overview

    /// Zoomed out, but individual clips are still visually distinct.
    case wide

    /// Default editing zoom; seconds-tick ruler + clip thumbnails.
    case medium

    /// Frame-accurate editing; sub-second ruler + per-frame thumbnails.
    case frame

    /// Sample-level inspection; sub-frame audio waveforms.
    case subframe

    // MARK: - Thresholds

    /// Lower bound of the zoom-scale range where this LOD applies
    /// (seconds per 100pt). The LOD applies when
    /// `minZoomSec <= currentZoom < next-coarser.minZoomSec`.
    ///
    /// Overview: 60s+ / 100pt
    /// Wide:     15s-60s / 100pt
    /// Medium:   3s-15s  / 100pt
    /// Frame:    0.2s-3s / 100pt
    /// Subframe: <0.2s / 100pt
    var minZoomSec: Double {
        switch self {
        case .overview: 60.0
        case .wide: 15.0
        case .medium: 3.0
        case .frame: 0.2
        case .subframe: 0.0
        }
    }

    // MARK: - Renderer gates

    /// Whether clip thumbnails should be decoded at this level.
    var shouldShowThumbnails: Bool {
        switch self {
        case .overview: false
        case .wide, .medium, .frame, .subframe: true
        }
    }

    /// Whether audio waveforms should be rendered.
    var shouldShowWaveforms: Bool {
        switch self {
        case .overview, .wide: false
        case .medium, .frame, .subframe: true
        }
    }

    /// Whether the time ruler should draw tick marks.
    var shouldShowRuler: Bool {
        // The ruler itself is always drawn; only tick density differs per
        // LOD (see `rulerGranularitySec`). Draw suppressed only in
        // overview where the bar becomes a single solid strip.
        switch self {
        case .overview: false
        case .wide, .medium, .frame, .subframe: true
        }
    }

    /// Spacing between major ruler tick marks, in seconds.
    var rulerGranularitySec: Double {
        switch self {
        case .overview: 60.0
        case .wide: 10.0
        case .medium: 1.0
        case .frame: 0.1
        case .subframe: 1.0 / 60.0
        }
    }
}

// MARK: - TimelineZoomLOD

/// Namespaced selector for the current LOD level given a zoom scale.
@MainActor
enum TimelineZoomLOD {

    /// Returns the LOD level that matches `zoomScale`.
    ///
    /// - Parameter zoomScale: Current zoom as seconds per 100pt of screen
    ///                        width. Must be `>= 0`. Negative values are
    ///                        clamped to `0`.
    /// - Returns: A ``TimelineLODLevel`` — never nil because ``subframe``
    ///            covers the `0…` interval.
    static func current(for zoomScale: Double) -> TimelineLODLevel {
        let clamped = max(0, zoomScale)
        if clamped >= TimelineLODLevel.overview.minZoomSec { return .overview }
        if clamped >= TimelineLODLevel.wide.minZoomSec { return .wide }
        if clamped >= TimelineLODLevel.medium.minZoomSec { return .medium }
        if clamped >= TimelineLODLevel.frame.minZoomSec { return .frame }
        return .subframe
    }
}

// MARK: - TimelineLODBudget

/// Per-LOD rendering budgets. Surfaced to downstream renderers so they
/// can short-circuit expensive work (e.g. a thumbnail cache that would
/// otherwise decode frames we never draw).
///
/// Budgets are declarative; each renderer chooses what to clamp on.
struct TimelineLODBudget: Sendable, Equatable {

    // MARK: - Fields

    /// Maximum number of thumbnails to keep resident at this LOD.
    /// `0` disables thumbnail rendering for this LOD.
    let maxThumbnails: Int

    /// Maximum resolution of a single waveform sprite, in points.
    /// Renderers should downsample source audio to fit.
    let maxWaveformWidthPt: Int

    /// Frame-step between consecutive thumbnails. Larger values skip
    /// frames to stay within ``maxThumbnails``.
    let thumbnailFrameStride: Int

    /// Whether per-clip text labels should be drawn at this LOD.
    let showsClipLabels: Bool

    // MARK: - Presets

    /// Budget for a given LOD level. Derived, not stored — so changing
    /// a preset only requires editing this switch.
    static func budget(for level: TimelineLODLevel) -> TimelineLODBudget {
        switch level {
        case .overview:
            // Project overview: draw only the clip colors, no thumbnails
            // or waveforms. A single composite strip per track.
            return TimelineLODBudget(
                maxThumbnails: 0,
                maxWaveformWidthPt: 0,
                thumbnailFrameStride: 0,
                showsClipLabels: false
            )
        case .wide:
            return TimelineLODBudget(
                maxThumbnails: 32,
                maxWaveformWidthPt: 0,
                thumbnailFrameStride: 60,
                showsClipLabels: true
            )
        case .medium:
            return TimelineLODBudget(
                maxThumbnails: 128,
                maxWaveformWidthPt: 256,
                thumbnailFrameStride: 15,
                showsClipLabels: true
            )
        case .frame:
            return TimelineLODBudget(
                maxThumbnails: 512,
                maxWaveformWidthPt: 1024,
                thumbnailFrameStride: 1,
                showsClipLabels: true
            )
        case .subframe:
            return TimelineLODBudget(
                maxThumbnails: 1024,
                maxWaveformWidthPt: 2048,
                thumbnailFrameStride: 1,
                showsClipLabels: true
            )
        }
    }
}
