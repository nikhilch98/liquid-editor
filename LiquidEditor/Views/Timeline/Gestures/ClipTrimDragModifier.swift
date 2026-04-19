// ClipTrimDragModifier.swift
// LiquidEditor
//
// T7-4 (Premium UI §10.3): Drag a clip's left/right trim handle, with
// magnet snapping to the playhead and beat markers.
//
// Emits `onTrimUpdate(side, newSeconds)` continuously while the user
// drags. Snap magnet threshold is 8pt by default.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Which edge of the clip is being trimmed.
enum TrimSide: Equatable, Sendable {
    case leading
    case trailing
}

/// Drag one trim handle with playhead + beat snapping.
struct ClipTrimDragModifier: ViewModifier {

    let side: TrimSide

    /// Points per second of timeline at the current zoom.
    let pointsPerSecond: CGFloat

    /// Starting seconds position of this edge before the drag.
    let startSeconds: Double

    /// Playhead position in seconds (snap target).
    let playheadSeconds: Double

    /// Beat markers in seconds (snap targets).
    let beatSeconds: [Double]

    /// Magnet threshold in points. Default 8pt per §10.3.
    let snapThresholdPoints: CGFloat

    let onTrimUpdate: (TrimSide, Double) -> Void

    init(
        side: TrimSide,
        pointsPerSecond: CGFloat,
        startSeconds: Double,
        playheadSeconds: Double,
        beatSeconds: [Double],
        snapThresholdPoints: CGFloat = 8,
        onTrimUpdate: @escaping (TrimSide, Double) -> Void
    ) {
        self.side = side
        self.pointsPerSecond = pointsPerSecond
        self.startSeconds = startSeconds
        self.playheadSeconds = playheadSeconds
        self.beatSeconds = beatSeconds
        self.snapThresholdPoints = snapThresholdPoints
        self.onTrimUpdate = onTrimUpdate
    }

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let deltaSeconds = Double(value.translation.width / max(pointsPerSecond, 0.001))
                    let raw = startSeconds + deltaSeconds
                    onTrimUpdate(side, snapped(raw))
                }
        )
    }

    /// Snap to playhead / beat markers if within threshold.
    private func snapped(_ seconds: Double) -> Double {
        let thresholdSec = Double(snapThresholdPoints / max(pointsPerSecond, 0.001))
        var best = seconds
        var bestDelta = thresholdSec
        for target in [playheadSeconds] + beatSeconds {
            let delta = abs(seconds - target)
            if delta < bestDelta {
                best = target
                bestDelta = delta
            }
        }
        return best
    }
}

extension View {
    /// Attach a trim-drag gesture to a handle view.
    func clipTrimDrag(
        side: TrimSide,
        pointsPerSecond: CGFloat,
        startSeconds: Double,
        playheadSeconds: Double,
        beatSeconds: [Double],
        onTrimUpdate: @escaping (TrimSide, Double) -> Void
    ) -> some View {
        modifier(ClipTrimDragModifier(
            side: side,
            pointsPerSecond: pointsPerSecond,
            startSeconds: startSeconds,
            playheadSeconds: playheadSeconds,
            beatSeconds: beatSeconds,
            onTrimUpdate: onTrimUpdate
        ))
    }
}
