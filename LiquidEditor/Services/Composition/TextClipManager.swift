// TextClipManager.swift
// LiquidEditor
//
// Stateless text clip service for text overlay CRUD operations.
//
// This is a pure-function namespace (enum with no cases).
// All methods are static and return new TextClip instances.
// The caller is responsible for persisting changes.

import Foundation
import CoreGraphics

// MARK: - TextRenderState

/// Computed render state for a text clip at a specific time.
///
/// All animation and keyframe interpolation has been applied.
/// This is the final state used by the renderer.
struct TextRenderState: Sendable, Equatable {
    /// The source clip ID.
    let clipId: String

    /// Text content to render.
    let text: String

    /// Final position (after animation + keyframes).
    let position: CGPoint

    /// Final scale (after animation + keyframes).
    let scale: Double

    /// Final rotation (after animation + keyframes).
    let rotation: Double

    /// Final opacity (after animation + keyframes).
    let opacity: Double

    /// Maximum width fraction.
    let maxWidthFraction: Double

    /// Whether this is a subtitle.
    let isSubtitle: Bool

    /// Number of visible characters (for typewriter animation, -1 = all).
    let visibleCharCount: Int

    /// Blur sigma for blur animations (0.0 = no blur).
    let blurSigma: Double
}

// MARK: - TextClipManager

/// Stateless service for text clip operations.
///
/// This namespace does NOT own state. It provides pure functions that
/// create new `TimelineClip` instances for text overlays. The caller
/// is responsible for persisting changes via the timeline manager.
///
/// Uses `enum` namespace pattern (no cases) -- no instances can be created.
enum TextClipManager {

    // MARK: - Creation

    /// Create a new text clip with default values.
    ///
    /// - Parameters:
    ///   - trackId: Track to place the clip on.
    ///   - text: Initial text content.
    ///   - startTime: Start time on timeline in microseconds.
    ///   - durationMicros: Duration in microseconds (default 3 seconds).
    /// - Returns: A new text overlay clip.
    static func createDefault(
        trackId: String,
        text: String = "Text",
        startTime: TimeMicros = 0,
        durationMicros: TimeMicros = 3_000_000
    ) -> TimelineClip {
        TimelineClip(
            trackId: trackId,
            type: .text,
            startTime: startTime,
            duration: durationMicros,
            label: text
        )
    }

    // MARK: - Modification

    /// Update the text label of a clip.
    static func updateText(_ clip: TimelineClip, newText: String) -> TimelineClip {
        clip.with(label: newText)
    }

    /// Update the position of a clip on the timeline.
    static func updatePosition(_ clip: TimelineClip, newStartTime: TimeMicros) -> TimelineClip {
        clip.with(startTime: newStartTime)
    }

    /// Update the duration of a text clip.
    static func updateDuration(_ clip: TimelineClip, newDuration: TimeMicros) -> TimelineClip {
        clip.with(duration: max(newDuration, TimelineClip.minDuration))
    }

    /// Move clip to a different track.
    static func moveToTrack(_ clip: TimelineClip, trackId: String) -> TimelineClip {
        clip.with(trackId: trackId)
    }

    // MARK: - Render State

    /// Compute the render state for a text clip at a given time offset.
    ///
    /// - Parameters:
    ///   - clip: The text timeline clip.
    ///   - clipOffsetMicros: Time relative to clip start, in microseconds.
    /// - Returns: The computed render state.
    static func computeRenderState(
        _ clip: TimelineClip,
        clipOffsetMicros: TimeMicros
    ) -> TextRenderState {
        // For the Swift port, text animation evaluation would be layered on top.
        // This provides the base render state.
        let progress = clip.duration > 0
            ? Double(clipOffsetMicros) / Double(clip.duration)
            : 0.0
        let clampedProgress = min(max(progress, 0.0), 1.0)

        // Base state (no animation applied in this simplified port)
        return TextRenderState(
            clipId: clip.id,
            text: clip.label ?? "Text",
            position: CGPoint(x: 0.5, y: 0.5),
            scale: 1.0,
            rotation: 0.0,
            opacity: 1.0,
            maxWidthFraction: 0.8,
            isSubtitle: false,
            visibleCharCount: -1,
            blurSigma: 0.0
        )
    }
}
