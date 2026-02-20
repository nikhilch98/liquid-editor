// TimelinePlayheadController.swift
// LiquidEditor
//
// Playhead controller for smooth playhead movement and scrubbing.
// Provides frame-accurate scrubbing, smooth playhead animation,
// and timecode display formatting.
//

import Foundation
import UIKit

// MARK: - PlayheadState

/// State of the playhead.
enum PlayheadState: String, Sendable, CaseIterable {
    /// Stationary, no interaction.
    case idle
    /// User is scrubbing (dragging the playhead).
    case scrubbing
    /// Playing back.
    case playing
    /// Seeking to a specific time.
    case seeking
}

// MARK: - ScrubAudioConfig

/// Configuration for scrub audio preview.
struct ScrubAudioConfig: Equatable, Sendable {
    /// Whether scrub audio preview is enabled.
    let isEnabled: Bool

    /// Volume of scrub audio preview (0.0-1.0).
    let volume: Double

    /// Whether to use audio-follows-video during scrub.
    let audioFollowsVideo: Bool

    init(
        isEnabled: Bool = true,
        volume: Double = 0.5,
        audioFollowsVideo: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.volume = volume
        self.audioFollowsVideo = audioFollowsVideo
    }

    static let defaults = ScrubAudioConfig()
    static let disabled = ScrubAudioConfig(isEnabled: false)

    func with(
        isEnabled: Bool? = nil,
        volume: Double? = nil,
        audioFollowsVideo: Bool? = nil
    ) -> ScrubAudioConfig {
        ScrubAudioConfig(
            isEnabled: isEnabled ?? self.isEnabled,
            volume: volume ?? self.volume,
            audioFollowsVideo: audioFollowsVideo ?? self.audioFollowsVideo
        )
    }
}

// MARK: - TimecodeFormat

/// Timecode display format.
enum TimecodeFormat: String, Sendable, CaseIterable {
    /// HH:MM:SS:FF (frames).
    case smpte
    /// HH:MM:SS.mmm (milliseconds).
    case milliseconds
    /// MM:SS (simple minutes:seconds).
    case simple
    /// Seconds only (e.g., "12.5s").
    case seconds
}

// MARK: - TimelinePlayheadController

/// Controller for playhead position, scrubbing, and timecode display.
///
/// Manages:
/// - Smooth playhead positioning and animation.
/// - Frame-accurate scrubbing with haptic feedback at frame boundaries.
/// - Timecode formatting in multiple display formats.
@Observable @MainActor
final class TimelinePlayheadController {

    // MARK: - State

    /// Current playhead time (microseconds).
    private(set) var currentTime: TimeMicros = 0

    /// Current state.
    private(set) var state: PlayheadState = .idle

    /// Scrub audio configuration.
    private(set) var scrubAudioConfig: ScrubAudioConfig = .defaults

    /// Frame rate for frame-accurate scrubbing.
    private(set) var frameRate: Rational = .fps30

    // MARK: - Private State

    /// Last frame boundary crossed during scrub (for haptic feedback).
    private var lastFrameIndex: Int = 0

    /// Seek animation state.
    private var seekStartTime: TimeMicros = 0
    private var seekTargetTime: TimeMicros = 0
    private var seekDisplayLink: CADisplayLink?
    private var seekStartDate: Date?
    private let seekDuration: TimeInterval = 0.2

    // MARK: - Callbacks

    /// Callback when playhead time changes.
    var onTimeChanged: (@MainActor (TimeMicros) -> Void)?

    /// Callback when playhead state changes.
    var onStateChanged: (@MainActor (PlayheadState) -> Void)?

    // MARK: - Computed Properties

    /// Whether the playhead is being scrubbed.
    var isScrubbing: Bool { state == .scrubbing }

    /// Whether playback is active.
    var isPlaying: Bool { state == .playing }

    /// Current frame number.
    var currentFrame: Int { frameRate.microsecondsToFrame(currentTime) }

    /// Duration of one frame in microseconds.
    var frameDurationMicros: Int64 { frameRate.microsecondsPerFrame }

    // MARK: - Configuration

    /// Set the frame rate for frame-accurate scrubbing.
    func setFrameRate(_ fps: Rational) {
        frameRate = fps
    }

    /// Set frame rate from a Double value.
    func setFrameRate(_ fps: Double) {
        let clamped = min(max(fps, 1.0), 240.0)
        frameRate = Rational.fromDouble(clamped)
    }

    /// Update scrub audio configuration.
    func updateScrubAudioConfig(_ config: ScrubAudioConfig) {
        scrubAudioConfig = config
    }

    // MARK: - Playhead Position

    /// Set playhead time directly (no animation).
    func setTime(_ time: TimeMicros) {
        let clampedTime = max(time, 0)
        if currentTime == clampedTime { return }

        currentTime = clampedTime
        onTimeChanged?(currentTime)
    }

    /// Seek to a specific time with smooth animation.
    func seekTo(_ targetTime: TimeMicros) {
        let clampedTarget = max(targetTime, 0)

        seekStartTime = currentTime
        seekTargetTime = clampedTarget
        state = .seeking
        notifyStateChanged()

        seekStartDate = Date()

        // Use CADisplayLink for smooth animation
        seekDisplayLink?.invalidate()
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in
            self?.onSeekAnimationTick()
        }, selector: #selector(DisplayLinkTarget.tick))
        link.add(to: .main, forMode: .common)
        seekDisplayLink = link
    }

    /// Move playhead by delta.
    func moveBy(_ delta: TimeMicros) {
        setTime(currentTime + delta)
    }

    /// Move playhead to the next frame boundary.
    func nextFrame() {
        let nextFrameTime = frameRate.frameToMicroseconds(currentFrame + 1)
        setTime(nextFrameTime)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Move playhead to the previous frame boundary.
    func previousFrame() {
        let prevFrame = max(currentFrame - 1, 0)
        let prevFrameTime = frameRate.frameToMicroseconds(prevFrame)
        setTime(prevFrameTime)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Snap playhead to nearest frame boundary.
    func snapToFrame(_ time: TimeMicros) -> TimeMicros {
        let frame = frameRate.microsecondsToFrame(time)
        let snapped = frameRate.frameToMicroseconds(frame)
        let nextSnapped = frameRate.frameToMicroseconds(frame + 1)
        // Pick the closest boundary
        if (time - snapped) < (nextSnapped - time) {
            return snapped
        }
        return nextSnapped
    }

    // MARK: - Scrubbing

    /// Start scrubbing at a position.
    func startScrub(_ time: TimeMicros) {
        state = .scrubbing
        lastFrameIndex = frameRate.microsecondsToFrame(time)
        setTime(time)
        notifyStateChanged()

        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Update scrub position.
    func updateScrub(_ time: TimeMicros) {
        guard state == .scrubbing else { return }

        let clampedTime = max(time, 0)
        let currentFrameIndex = frameRate.microsecondsToFrame(clampedTime)

        // Fire haptic feedback when crossing frame boundaries.
        if currentFrameIndex != lastFrameIndex {
            UISelectionFeedbackGenerator().selectionChanged()
            lastFrameIndex = currentFrameIndex
        }

        setTime(clampedTime)
    }

    /// End scrubbing.
    func endScrub() {
        guard state == .scrubbing else { return }

        // Snap to nearest frame boundary on scrub end.
        setTime(snapToFrame(currentTime))

        state = .idle
        notifyStateChanged()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Cancel scrubbing and return to original position.
    func cancelScrub(_ originalTime: TimeMicros) {
        guard state == .scrubbing else { return }

        setTime(originalTime)
        state = .idle
        notifyStateChanged()
    }

    // MARK: - Playback State

    /// Notify that playback has started.
    func notifyPlaybackStarted() {
        state = .playing
        notifyStateChanged()
    }

    /// Notify that playback has stopped.
    func notifyPlaybackStopped() {
        state = .idle
        notifyStateChanged()
    }

    /// Update time during playback (called by playback engine).
    func updatePlaybackTime(_ time: TimeMicros) {
        guard state == .playing else { return }
        currentTime = time
        onTimeChanged?(currentTime)
    }

    // MARK: - Timecode Formatting

    /// Format a time value as a timecode string.
    static func formatTimecode(
        _ time: TimeMicros,
        format: TimecodeFormat = .smpte,
        frameRate: Rational = .fps30
    ) -> String {
        let clampedTime = max(time, 0)

        switch format {
        case .smpte:
            return formatSMPTE(clampedTime, frameRate: frameRate)
        case .milliseconds:
            return formatMilliseconds(clampedTime)
        case .simple:
            return formatSimple(clampedTime)
        case .seconds:
            return formatSecondsOnly(clampedTime)
        }
    }

    /// Format the current playhead time.
    func formatCurrentTime(format: TimecodeFormat = .smpte) -> String {
        Self.formatTimecode(currentTime, format: format, frameRate: frameRate)
    }

    // MARK: - Seek Animation

    private func onSeekAnimationTick() {
        guard let startDate = seekStartDate else {
            stopSeekAnimation()
            return
        }

        let elapsed = Date().timeIntervalSince(startDate)
        let progress = min(elapsed / seekDuration, 1.0)

        // Ease-out cubic curve
        let eased = 1.0 - pow(1.0 - progress, 3.0)

        let interpolated = Double(seekStartTime) + eased * Double(seekTargetTime - seekStartTime)
        currentTime = TimeMicros(interpolated.rounded())
        onTimeChanged?(currentTime)

        if progress >= 1.0 {
            currentTime = seekTargetTime
            onTimeChanged?(currentTime)
            stopSeekAnimation()
        }
    }

    private func stopSeekAnimation() {
        seekDisplayLink?.invalidate()
        seekDisplayLink = nil
        seekStartDate = nil
        state = .idle
        notifyStateChanged()
    }

    // MARK: - Helpers

    private func notifyStateChanged() {
        onStateChanged?(state)
    }

    // MARK: - Static Timecode Formatters

    /// SMPTE timecode: HH:MM:SS:FF or MM:SS:FF
    private static func formatSMPTE(_ time: TimeMicros, frameRate: Rational) -> String {
        let totalFrames = timeToFrames(time, frameRate: frameRate)
        let fps = Int(frameRate.value.rounded())

        let frames = totalFrames % fps
        let totalSeconds = totalFrames / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
        }
        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }

    /// Milliseconds format: HH:MM:SS.mmm or MM:SS.mmm
    private static func formatMilliseconds(_ time: TimeMicros) -> String {
        let totalMs = time / 1000
        let ms = totalMs % 1000
        let totalSeconds = totalMs / 1000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, ms)
        }
        return String(format: "%02d:%02d.%03d", minutes, seconds, ms)
    }

    /// Simple format: MM:SS
    private static func formatSimple(_ time: TimeMicros) -> String {
        let totalSeconds = time / 1_000_000
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60

        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Seconds format: 12.5s
    private static func formatSecondsOnly(_ time: TimeMicros) -> String {
        let seconds = Double(time) / 1_000_000.0
        return String(format: "%.1fs", seconds)
    }

    // MARK: - Cleanup

    /// Dispose resources and break CADisplayLink retain cycle.
    ///
    /// **CRITICAL**: Callers MUST call this method when the controller is no longer needed
    /// to prevent memory leaks. CADisplayLink retains its target, creating a strong reference
    /// cycle. While `deinit` attempts cleanup, proper disposal ensures timely resource release.
    ///
    /// Safe to call multiple times (idempotent).
    func dispose() {
        seekDisplayLink?.invalidate()
        seekDisplayLink = nil
    }

    deinit {
        // CADisplayLink retains its target, so if dispose() is never called,
        // the controller would leak. Invalidation is thread-safe and breaks
        // the retain cycle. We use assumeIsolated because @Observable
        // @MainActor objects are deallocated on the main actor.
        MainActor.assumeIsolated {
            seekDisplayLink?.invalidate()
            seekDisplayLink = nil
        }
    }
}

// MARK: - DisplayLinkTarget

/// Helper class to bridge CADisplayLink callbacks to closures.
@MainActor
private final class DisplayLinkTarget: NSObject {
    private let callback: () -> Void

    init(callback: @escaping @MainActor () -> Void) {
        self.callback = callback
    }

    @objc func tick() {
        callback()
    }
}
