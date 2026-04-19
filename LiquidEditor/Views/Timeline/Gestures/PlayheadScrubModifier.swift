// PlayheadScrubModifier.swift
// LiquidEditor
//
// T7-9 (Premium UI §10.3): Drag the playhead to scrub. When
// `scrubWithAudio` is on, each position update fires `onScrub(time)` so
// the caller can play a short audio sample at that position.
//
// Pure SwiftUI, iOS 26 native. No UIKit wrappers.

import SwiftUI

/// Scrub the playhead horizontally; optionally emits audio-scrub events.
struct PlayheadScrubModifier: ViewModifier {

    @Binding var currentTime: TimeMicros

    /// Points per second at the current timeline zoom.
    let pointsPerSecond: CGFloat

    /// Emit `onScrub` at every update so audio can follow the playhead.
    let scrubWithAudio: Bool

    /// Clamps (µs). Default is wide open; caller can clamp to timeline span.
    let minTime: TimeMicros
    let maxTime: TimeMicros

    let onScrub: (TimeMicros) -> Void

    @State private var dragStartTime: TimeMicros = 0

    init(
        currentTime: Binding<TimeMicros>,
        pointsPerSecond: CGFloat,
        scrubWithAudio: Bool,
        minTime: TimeMicros = 0,
        maxTime: TimeMicros = .max,
        onScrub: @escaping (TimeMicros) -> Void
    ) {
        self._currentTime = currentTime
        self.pointsPerSecond = pointsPerSecond
        self.scrubWithAudio = scrubWithAudio
        self.minTime = minTime
        self.maxTime = maxTime
        self.onScrub = onScrub
    }

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { dragStartTime = currentTime }
                    let deltaSec = Double(value.translation.width / max(pointsPerSecond, 0.001))
                    let deltaMicros = TimeMicros(deltaSec * 1_000_000)
                    let newTime = max(minTime, min(maxTime, dragStartTime &+ deltaMicros))
                    currentTime = newTime
                    if scrubWithAudio { onScrub(newTime) }
                }
                .onEnded { _ in
                    if scrubWithAudio { onScrub(currentTime) }
                }
        )
    }
}

extension View {
    /// Attach a drag-to-scrub gesture to the playhead.
    func playheadScrub(
        currentTime: Binding<TimeMicros>,
        pointsPerSecond: CGFloat,
        scrubWithAudio: Bool,
        minTime: TimeMicros = 0,
        maxTime: TimeMicros = .max,
        onScrub: @escaping (TimeMicros) -> Void
    ) -> some View {
        modifier(PlayheadScrubModifier(
            currentTime: currentTime,
            pointsPerSecond: pointsPerSecond,
            scrubWithAudio: scrubWithAudio,
            minTime: minTime,
            maxTime: maxTime,
            onScrub: onScrub
        ))
    }
}
