// CompositionServiceProtocol.swift
// LiquidEditor
//
// Protocol for timeline composition building and playback.
// Enables dependency injection and testability.

import AVFoundation
import Foundation

// MARK: - CompositionServiceProtocol

/// Protocol for timeline composition building and playback.
///
/// Implementations manage AVComposition lifecycle, playback state,
/// and hot-swap for zero-interruption editing. All async operations
/// use Swift concurrency (async/throws).
protocol CompositionServiceProtocol: Sendable {
    /// Build an AVComposition from timeline segments.
    ///
    /// - Parameter segments: Ordered list of composition segments describing
    ///   the timeline layout.
    /// - Returns: An opaque handle to the built composition.
    /// - Throws: If asset loading or composition building fails.
    func buildComposition(segments: [CompositionSegment]) async throws -> CompositionHandle

    /// Hot-swap to a new composition without playback interruption.
    ///
    /// Uses double-buffered AVPlayerItem swap for seamless transition.
    /// - Parameters:
    ///   - handle: The new composition handle to swap in.
    ///   - time: Time position to seek to after swap.
    /// - Throws: If the swap fails or the handle is invalid.
    func hotSwapComposition(_ handle: CompositionHandle, seekTo time: TimeMicros) async throws

    /// Start playback from the current position.
    func play() async throws

    /// Pause playback.
    func pause() async throws

    /// Seek to a specific time position.
    ///
    /// - Parameter time: Target time in microseconds.
    func seek(to time: TimeMicros) async throws

    /// Set the playback rate.
    ///
    /// - Parameter rate: Playback rate multiplier (1.0 = normal speed).
    func setPlaybackRate(_ rate: Float) async throws

    /// Set the playback volume.
    ///
    /// - Parameter volume: Volume level (0.0 = muted, 1.0 = full volume).
    func setVolume(_ volume: Float) async throws

    /// Get the current playhead position.
    ///
    /// - Returns: Current time in microseconds.
    func currentTime() async -> TimeMicros

    /// Whether the player is currently playing.
    var isPlaying: Bool { get async }

    /// Stream of playback time updates emitted during playback.
    ///
    /// Updates are emitted at display-link frequency while playing.
    var timeUpdates: AsyncStream<TimeMicros> { get }

    /// Stream of playback state changes.
    var stateUpdates: AsyncStream<PlaybackState> { get }

    /// Dispose the composition and release all resources.
    func dispose() async
}

// MARK: - CompositionHandle

/// Opaque handle for a built composition.
///
/// Wraps the AVFoundation composition objects needed for playback.
/// `AVComposition` is `Sendable` in iOS 26.
struct CompositionHandle: @unchecked Sendable, Equatable, Identifiable {
    /// Unique identifier for this composition build.
    let id: String

    /// The built AVComposition.
    let composition: AVComposition

    /// Optional video composition for custom rendering instructions.
    let videoComposition: AVVideoComposition?

    /// Optional audio mix for volume/panning adjustments.
    let audioMix: AVAudioMix?

    /// Total duration of the composition in microseconds.
    let duration: TimeMicros

    static func == (lhs: CompositionHandle, rhs: CompositionHandle) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - PlaybackState

/// Playback state reported via `stateUpdates`.
enum PlaybackState: String, Sendable {
    case idle
    case playing
    case paused
    case buffering
    case error
}

// MARK: - CompositionSegment

/// A segment describing one clip's contribution to the composition.
///
/// Maps a source media asset time range to a position on the timeline,
/// accounting for playback speed and volume.
struct CompositionSegment: Sendable, Equatable {
    /// Clip identifier from the timeline.
    let clipId: String

    /// Media asset identifier.
    let assetId: String

    /// URL of the source media file.
    let assetURL: URL

    /// Time range within the source asset.
    let sourceTimeRange: TimeRange

    /// Start time on the output timeline in microseconds.
    let timelineStartTime: TimeMicros

    /// Playback speed multiplier for this segment.
    let playbackSpeed: Double

    /// Volume level for this segment (0.0-1.0).
    let volume: Float

    /// Track index for multi-track composition.
    let trackIndex: Int
}
