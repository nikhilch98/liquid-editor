// PlaybackViewModel.swift
// LiquidEditor
//
// ViewModel for playback transport controls — bridges the PlaybackEngine
// actor with the SwiftUI view layer.
//
// Uses @Observable macro (iOS 26) for SwiftUI reactivity.
// All mutable UI state is @MainActor-isolated.
// Communicates with the PlaybackEngine actor via async calls.

import Foundation
import SwiftUI
import os

// MARK: - PlaybackViewModel

@Observable
@MainActor
final class PlaybackViewModel {

    // MARK: - Logger

    private static let logger = Logger(
        subsystem: "com.liquideditor",
        category: "PlaybackViewModel"
    )

    // MARK: - Configuration

    /// Default seek delta for skip forward/backward (5 seconds).
    var seekDeltaMicros: TimeMicros = 5_000_000

    // MARK: - Playback State

    /// Whether playback is active.
    private(set) var isPlaying: Bool = false

    /// Current playhead time in microseconds.
    private(set) var currentTime: TimeMicros = 0

    /// Total timeline duration in microseconds.
    var totalDuration: TimeMicros = 0

    /// Playback speed multiplier.
    var playbackRate: Float = 1.0

    /// Audio volume (0.0 to 1.0).
    var volume: Float = 1.0

    /// Whether audio is muted.
    var isMuted: Bool = false

    /// Whether looping is enabled.
    var isLooping: Bool = false

    // MARK: - Available Rates

    /// Preset playback rates for the speed picker.
    static let availableRates: [Float] = [0.25, 0.5, 1.0, 1.5, 2.0]

    // MARK: - Engine Reference

    /// The playback engine actor (injected).
    /// Optional so the ViewModel can be created before the engine is ready.
    private var engine: PlaybackEngine?

    /// Task listening to playhead updates from the engine.
    @ObservationIgnored
    nonisolated(unsafe) private var playheadListenerTask: Task<Void, Never>?

    /// Task listening to playback events from the engine.
    @ObservationIgnored
    nonisolated(unsafe) private var eventListenerTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Current time formatted as "MM:SS.ms".
    var formattedCurrentTime: String {
        currentTime.simpleTimeString
    }

    /// Total duration formatted as "MM:SS.ms".
    var formattedTotalDuration: String {
        totalDuration.simpleTimeString
    }

    /// Playback progress as a value between 0.0 and 1.0.
    var progress: Double {
        guard totalDuration > 0 else { return 0.0 }
        return min(max(Double(currentTime) / Double(totalDuration), 0.0), 1.0)
    }

    /// Formatted playback rate string for display.
    var formattedRate: String {
        if playbackRate == 1.0 { return "1x" }
        if playbackRate == floor(playbackRate) {
            return "\(Int(playbackRate))x"
        }
        return String(format: "%.2gx", playbackRate)
    }

    /// Effective volume (0 when muted).
    var effectiveVolume: Float {
        isMuted ? 0.0 : volume
    }

    // MARK: - Initialization

    init() {}

    /// Initialize with a playback engine and start listening for updates.
    init(engine: PlaybackEngine) {
        self.engine = engine
        startListening()
    }

    // MARK: - Engine Binding

    /// Bind to a playback engine and start listening for updates.
    func bind(to engine: PlaybackEngine) {
        self.engine = engine
        startListening()
    }

    /// Start listening to the engine's async streams.
    private func startListening() {
        guard let engine else {
            Self.logger.warning("Cannot start listening: engine is nil")
            return
        }

        // Cancel previous listeners.
        playheadListenerTask?.cancel()
        eventListenerTask?.cancel()

        // Listen for playhead position updates.
        playheadListenerTask = Task { [weak self] in
            do {
                for await timeMicros in engine.playheadStream {
                    guard let self, !Task.isCancelled else { return }
                    self.currentTime = timeMicros
                }
            } catch {
                Self.logger.error("Playhead stream error: \(error.localizedDescription)")
            }
        }

        // Listen for playback events.
        eventListenerTask = Task { [weak self] in
            do {
                for await event in engine.eventStream {
                    guard let self, !Task.isCancelled else { return }
                    self.handleEvent(event)
                }
            } catch {
                Self.logger.error("Event stream error: \(error.localizedDescription)")
            }
        }
    }

    /// Handle a playback event from the engine.
    private func handleEvent(_ event: PlaybackEvent) {
        switch event {
        case .started:
            isPlaying = true
        case .paused, .stopped, .ended:
            isPlaying = false
        case .rebuildStarted, .rebuildCompleted:
            break
        case .scrubStarted:
            isPlaying = false
        case .scrubEnded:
            break
        case .errorOccurred:
            isPlaying = false
        }
    }

    // MARK: - Playback Controls

    /// Start playback.
    func play() {
        guard let engine else { return }
        Task {
            await engine.play()
        }
    }

    /// Pause playback.
    func pause() {
        guard let engine else { return }
        Task {
            await engine.pause()
        }
    }

    /// Toggle between play and pause.
    func togglePlayPause() {
        guard let engine else { return }
        Task {
            await engine.togglePlayPause()
        }
    }

    /// Seek to an absolute time position.
    func seek(to time: TimeMicros) {
        guard let engine else { return }
        currentTime = time
        Task {
            await engine.seek(time)
        }
    }

    /// Seek forward by the configured delta (default 5 seconds).
    func seekForward() {
        guard let engine else { return }
        Task {
            await engine.seekForward(seekDeltaMicros)
        }
    }

    /// Seek backward by the configured delta (default 5 seconds).
    func seekBackward() {
        guard let engine else { return }
        Task {
            await engine.seekBackward(seekDeltaMicros)
        }
    }

    // MARK: - Settings

    /// Set the playback rate.
    func setRate(_ rate: Float) {
        playbackRate = rate
        guard let engine else { return }
        Task {
            await engine.setPlaybackRate(Double(rate))
        }
    }

    /// Cycle to the next available playback rate.
    func cycleRate() {
        guard let currentIndex = Self.availableRates.firstIndex(of: playbackRate) else {
            setRate(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % Self.availableRates.count
        setRate(Self.availableRates[nextIndex])
    }

    /// Toggle mute state.
    func toggleMute() {
        isMuted.toggle()
        guard let engine else { return }
        Task {
            await engine.setVolume(Double(effectiveVolume))
        }
    }

    /// Set the volume (0.0 to 1.0).
    func setVolume(_ vol: Float) {
        volume = min(max(vol, 0.0), 1.0)
        guard let engine else { return }
        Task {
            await engine.setVolume(Double(effectiveVolume))
        }
    }

    /// Toggle looping.
    func toggleLooping() {
        isLooping.toggle()
        guard let engine else { return }
        Task {
            await engine.setLooping(isLooping)
        }
    }

    // MARK: - External Updates

    /// Update current time from an external source (e.g., timeline scrubbing).
    func updateCurrentTime(_ time: TimeMicros) {
        currentTime = time
    }

    /// Update total duration (e.g., after timeline edit).
    func updateTotalDuration(_ duration: TimeMicros) {
        totalDuration = duration
    }
}
