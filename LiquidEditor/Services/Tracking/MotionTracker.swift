//
//  MotionTracker.swift
//  LiquidEditor
//
//  Object tracking using VNTrackObjectRequest for user-selected regions.
//  Supports face, object, and rectangle tracking through video frames.
//
//  Uses AsyncStream for progress reporting.
//

import AVFoundation
import Foundation
import Vision

// MARK: - Motion Tracking Result

/// Result of a completed motion tracking job.
struct MotionTrackingResult: Sendable {
    /// Tracked points with positions and confidence.
    let points: [MotionTrackedPoint]
    /// Average confidence across all tracked frames.
    let averageConfidence: Double
    /// Timestamps (ms) where tracking was lost.
    let lostFrameTimestamps: [Int]
}

/// A single tracked point from motion tracking.
struct MotionTrackedPoint: Sendable, Codable {
    /// Timestamp in milliseconds.
    let timeMs: Int
    /// Center X (normalized 0-1).
    let x: Double
    /// Center Y (normalized 0-1, top-left origin).
    let y: Double
    /// Width (normalized 0-1).
    let width: Double
    /// Height (normalized 0-1).
    let height: Double
    /// Tracking confidence (0-1).
    let confidence: Double
    /// Estimated rotation (radians).
    let rotation: Double
}

// MARK: - Motion Tracking Progress

/// Progress event from a motion tracking job.
struct MotionTrackingProgressEvent: Sendable {
    let jobId: String
    let progress: Double
    let result: MotionTrackingResult?
    let error: String?
}

// MARK: - Motion Tracker

/// Object tracking service using VNTrackObjectRequest.
///
/// Uses `actor` isolation for thread-safe job management.
actor MotionTracker {

    // MARK: - Constants

    private static let lowConfidenceThreshold: Double = 0.3

    // MARK: - Active Jobs

    private var activeJobs: Set<String> = []
    private var cancelledJobs: Set<String> = []

    // MARK: - Start Tracking

    /// Start tracking an object through a video.
    ///
    /// - Parameters:
    ///   - videoPath: Path to the video file.
    ///   - initialRect: Initial bounding box (normalized, top-left origin).
    ///   - startFrameMs: Start time in milliseconds.
    ///   - endFrameMs: End time in milliseconds.
    ///   - trackingQuality: Quality level ("fast", "balanced", "accurate").
    ///   - jobId: Optional job identifier.
    /// - Returns: Job ID and an AsyncStream of progress events.
    func startTracking(
        videoPath: String,
        initialRect: CGRect,
        startFrameMs: Int,
        endFrameMs: Int,
        trackingQuality: String = "balanced",
        jobId: String? = nil
    ) -> (jobId: String, progress: AsyncStream<MotionTrackingProgressEvent>) {
        let id = jobId ?? UUID().uuidString

        activeJobs.insert(id)

        let trackingLevel: VNRequestTrackingLevel
        switch trackingQuality {
        case "fast": trackingLevel = .fast
        case "accurate": trackingLevel = .accurate
        default: trackingLevel = .fast
        }

        // Vision uses bottom-left origin
        let visionRect = CGRect(
            x: initialRect.origin.x,
            y: 1.0 - initialRect.origin.y - initialRect.height,
            width: initialRect.width,
            height: initialRect.height
        )
        let stream = AsyncStream<MotionTrackingProgressEvent> { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                let observation = VNDetectedObjectObservation(boundingBox: visionRect)
                await self.processTracking(
                    jobId: id,
                    videoPath: videoPath,
                    initialObservation: observation,
                    startMs: startFrameMs,
                    endMs: endFrameMs,
                    trackingLevel: trackingLevel,
                    continuation: continuation
                )
                continuation.finish()
            }
        }

        return (id, stream)
    }

    /// Cancel a tracking job.
    func cancelTracking(jobId: String) {
        cancelledJobs.insert(jobId)
        activeJobs.remove(jobId)
    }

    // MARK: - Processing

    private func processTracking(
        jobId: String,
        videoPath: String,
        initialObservation: VNDetectedObjectObservation,
        startMs: Int,
        endMs: Int,
        trackingLevel: VNRequestTrackingLevel,
        continuation: AsyncStream<MotionTrackingProgressEvent>.Continuation
    ) async {
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVURLAsset(url: url)

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            continuation.yield(MotionTrackingProgressEvent(jobId: jobId, progress: 1.0, result: nil, error: "No video track found"))
            return
        }

        guard let reader = try? AVAssetReader(asset: asset) else {
            continuation.yield(MotionTrackingProgressEvent(jobId: jobId, progress: 1.0, result: nil, error: "Could not create asset reader"))
            return
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        let startTime = CMTime(value: CMTimeValue(startMs), timescale: 1000)
        let endTime = CMTime(value: CMTimeValue(endMs), timescale: 1000)
        reader.timeRange = CMTimeRange(start: startTime, duration: CMTimeSubtract(endTime, startTime))
        reader.add(output)

        guard reader.startReading() else {
            continuation.yield(MotionTrackingProgressEvent(jobId: jobId, progress: 1.0, result: nil, error: "Could not start reading"))
            return
        }

        let sequenceHandler = VNSequenceRequestHandler()
        var currentObservation = initialObservation
        var trackedPoints: [MotionTrackedPoint] = []
        var lostFrames: [Int] = []
        var totalConfidence: Double = 0
        var frameCount = 0
        let totalDurationMs = endMs - startMs

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if await isJobCancelled(jobId) {
                reader.cancelReading()
                break
            }

            autoreleasepool {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let timeMs = Int(presentationTime.seconds * 1000)

                let trackRequest = VNTrackObjectRequest(detectedObjectObservation: currentObservation)
                trackRequest.trackingLevel = trackingLevel

                do {
                    try sequenceHandler.perform([trackRequest], on: pixelBuffer, orientation: .up)

                    guard let result = trackRequest.results?.first as? VNDetectedObjectObservation else {
                        lostFrames.append(timeMs)
                        return
                    }

                    let confidence = Double(result.confidence)
                    if confidence < Self.lowConfidenceThreshold {
                        lostFrames.append(timeMs)
                    }

                    let bbox = result.boundingBox
                    trackedPoints.append(MotionTrackedPoint(
                        timeMs: timeMs,
                        x: bbox.origin.x + bbox.width / 2,
                        y: 1.0 - bbox.origin.y - bbox.height / 2,
                        width: bbox.width,
                        height: bbox.height,
                        confidence: confidence,
                        rotation: 0.0
                    ))
                    totalConfidence += confidence
                    frameCount += 1
                    currentObservation = result
                } catch {
                    lostFrames.append(timeMs)
                }
            }

            // Progress
            let currentTimeMs = trackedPoints.last?.timeMs ?? 0
            let progress = totalDurationMs > 0 ? Double(currentTimeMs - startMs) / Double(totalDurationMs) : 0.0
            continuation.yield(MotionTrackingProgressEvent(
                jobId: jobId, progress: min(progress, 1.0), result: nil, error: nil
            ))
        }

        if await isJobCancelled(jobId) { return }

        let averageConfidence = frameCount > 0 ? totalConfidence / Double(frameCount) : 0.0

        let result = MotionTrackingResult(
            points: trackedPoints,
            averageConfidence: averageConfidence,
            lostFrameTimestamps: lostFrames
        )

        continuation.yield(MotionTrackingProgressEvent(
            jobId: jobId, progress: 1.0, result: result, error: nil
        ))

        await cleanupJob(jobId)
    }

    private func isJobCancelled(_ jobId: String) -> Bool {
        cancelledJobs.contains(jobId)
    }

    private func cleanupJob(_ jobId: String) {
        activeJobs.remove(jobId)
        cancelledJobs.remove(jobId)
    }
}
