// TrackingServiceProtocol.swift
// LiquidEditor
//
// Protocol for video tracking services (bounding box, pose).
// Enables dependency injection and testability.

import Foundation

// MARK: - TrackingServiceProtocol

/// Protocol for video tracking services using Apple Vision framework.
///
/// Implementations analyze video frames to detect and track objects
/// (bounding boxes) or people (pose estimation). Results are stored
/// per session and can be queried by frame index.
///
/// References:
/// - `TrackingAlgorithmType` from Models/Tracking/Tracking.swift
/// - `TrackingSession` from Models/Tracking/Tracking.swift
/// - `PersonTrackingResult` from Models/Tracking/Tracking.swift
/// - `FrameTrackingResult` from Models/Tracking/Tracking.swift
/// - `NormalizedBoundingBox` from Models/Tracking/Tracking.swift
/// - `DetectedPerson` from Models/Person/Person.swift
protocol TrackingServiceProtocol: Sendable {
    /// Analyze a video for trackable objects.
    ///
    /// Starts asynchronous analysis that processes frames at the given
    /// stride interval. Progress is reported via `progressStream`.
    ///
    /// - Parameters:
    ///   - path: URL of the video file to analyze.
    ///   - algorithm: Tracking algorithm to use.
    ///   - stride: Frame sampling stride (1 = every frame, 2 = every other, etc.).
    ///   - sessionId: Unique identifier for this tracking session.
    /// - Returns: The tracking session descriptor.
    /// - Throws: If the video cannot be loaded or analysis fails to start.
    func analyzeVideo(
        path: URL,
        algorithm: TrackingAlgorithmType,
        stride: Int,
        sessionId: String
    ) async throws -> TrackingSession

    /// Get all frame-level tracking results for a session.
    ///
    /// - Parameter sessionId: Session identifier.
    /// - Returns: Array of frame tracking results, sorted by timestamp.
    /// - Throws: If the session does not exist.
    func getResults(sessionId: String) async throws -> [FrameTrackingResult]

    /// Get interpolated tracking result at a specific frame index.
    ///
    /// If the frame was not directly analyzed (due to stride), the result
    /// is interpolated from surrounding analyzed frames.
    ///
    /// - Parameters:
    ///   - sessionId: Session identifier.
    ///   - frameIndex: Target frame index.
    /// - Returns: Interpolated result, or nil if out of range.
    /// - Throws: If the session does not exist.
    func getInterpolatedResult(
        sessionId: String,
        frameIndex: Int
    ) async throws -> PersonTrackingResult?

    /// Cancel an active analysis session.
    ///
    /// - Parameter sessionId: Session identifier to cancel.
    func cancelAnalysis(sessionId: String) async

    /// Get the list of available tracking algorithms.
    ///
    /// - Returns: Array of supported algorithm types.
    func availableAlgorithms() -> [TrackingAlgorithmType]

    /// Progress stream for an active analysis session.
    ///
    /// - Parameter sessionId: Session identifier.
    /// - Returns: AsyncStream emitting progress updates.
    func progressStream(sessionId: String) -> AsyncStream<TrackingProgressUpdate>

    /// Get detected persons in a completed tracking session.
    ///
    /// - Parameter sessionId: Session identifier.
    /// - Returns: Array of detected persons with bounding boxes.
    /// - Throws: If the session does not exist or is not complete.
    func getDetectedPersons(sessionId: String) async throws -> [DetectedPerson]
}

// MARK: - TrackingProgressUpdate

/// Progress update for a tracking analysis session.
struct TrackingProgressUpdate: Sendable {
    /// Session identifier.
    let sessionId: String

    /// Number of frames processed so far.
    let framesProcessed: Int

    /// Total number of frames to process.
    let totalFrames: Int

    /// Progress fraction (0.0-1.0).
    let progress: Double

    /// Number of objects detected so far.
    let detectedObjects: Int
}
