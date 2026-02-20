//
//  TrackingService.swift
//  LiquidEditor
//
//  Main tracking service actor for video analysis using Vision framework.
//  Manages tracking sessions, coordinates trackers, and reports progress.
//
//

import AVFoundation
import CoreMedia
import Foundation
import os
import UIKit
import Vision

// MARK: - Progress Event

/// A progress update emitted during video analysis.
struct TrackingProgressEvent: Sendable {
    /// Session identifier.
    let sessionId: String
    /// Progress value (0.0-1.0). Negative indicates error.
    let progress: Double
    /// Error message (nil if no error).
    let error: String?
    /// Debug information (nil if none).
    let debugInfo: String?

    init(sessionId: String, progress: Double, error: String? = nil, debugInfo: String? = nil) {
        self.sessionId = sessionId
        self.progress = progress
        self.error = error
        self.debugInfo = debugInfo
    }
}

// MARK: - Quality Metrics

/// Quality metrics for a completed tracking session.
struct TrackingQualityMetrics: Sendable {
    /// Average detection confidence across all frames.
    let averageConfidence: Double
    /// Tracking stability (ratio of tracked frames to total person-frames).
    let trackingStability: Double
    /// Total number of frames analyzed.
    let totalFrames: Int
    /// Number of frames where tracking was active.
    let trackedFrames: Int
    /// Number of gap-filled (low-confidence) frames.
    let gapFilledFrames: Int
}

// MARK: - Tracking Service

/// Main service for video tracking operations.
///
/// Uses `actor` isolation for thread-safe concurrent access.
/// All I/O-bound Vision requests run off the main thread naturally
/// via structured concurrency.
actor TrackingService {

    // MARK: - Logger

    private static let logger = Logger(subsystem: "LiquidEditor", category: "TrackingService")

    // MARK: - Properties

    /// Active tracking sessions keyed by session ID.
    private var sessions: [String: TrackingSessionState] = [:]

    /// Data stores keyed by session ID.
    private var dataStores: [String: TrackingDataStore] = [:]

    /// Available tracking algorithms.
    private let trackers: [String: BoundingBoxTracker]

    /// Person identifier for People Library matching.
    private let personIdentifier = PersonIdentifier()

    /// Track re-identifier for post-tracking merge.
    private let trackReidentifier = TrackReidentifier(config: .default)

    /// Cached merge statistics per session with timestamps for LRU eviction.
    private var mergeStatisticsCache: [String: (statistics: TrackMergeStatistics, timestamp: Date)] = [:]
    private let mergeStatisticsCacheLimit = 20

    // MARK: - Initialization

    init() {
        self.trackers = [
            "boundingBox": BoundingBoxTracker(),
        ]
    }

    // MARK: - Available Algorithms

    /// List available tracking algorithms.
    func availableAlgorithms() -> [(id: String, name: String, supportsMultiplePeople: Bool)] {
        trackers.map { (key, tracker) in
            (id: key, name: tracker.displayName, supportsMultiplePeople: tracker.supportsMultiplePeople)
        }
    }

    // MARK: - Analyze Video

    /// Analyze a video file for person tracking.
    ///
    /// - Parameters:
    ///   - path: File path to the video.
    ///   - algorithm: Algorithm identifier (e.g. "boundingBox").
    ///   - stride: Process every Nth frame (default 1).
    ///   - sessionId: Optional client-provided session ID.
    /// - Returns: An `AsyncStream` of progress events and the session ID.
    func analyzeVideo(
        path: String,
        algorithm: String = "boundingBox",
        stride: Int = 1,
        sessionId: String? = nil
    ) -> (sessionId: String, progress: AsyncStream<TrackingProgressEvent>) {
        guard let tracker = trackers[algorithm] else {
            let id = sessionId ?? UUID().uuidString
            let stream = AsyncStream<TrackingProgressEvent> { continuation in
                continuation.yield(TrackingProgressEvent(
                    sessionId: id, progress: -1,
                    error: "Unknown algorithm: \(algorithm)"
                ))
                continuation.finish()
            }
            return (id, stream)
        }

        let id = sessionId ?? UUID().uuidString
        let dataStore = TrackingDataStore()
        let session = TrackingSessionState(id: id, algorithmType: algorithm)

        sessions[id] = session
        dataStores[id] = dataStore

        let stream = AsyncStream<TrackingProgressEvent> { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.performAnalysis(
                    sessionId: id,
                    path: path,
                    tracker: tracker,
                    stride: stride,
                    dataStore: dataStore,
                    continuation: continuation
                )
                continuation.finish()
            }
        }

        return (id, stream)
    }

    // MARK: - Analysis Implementation

    private func performAnalysis(
        sessionId: String,
        path: String,
        tracker: BoundingBoxTracker,
        stride: Int,
        dataStore: TrackingDataStore,
        continuation: AsyncStream<TrackingProgressEvent>.Continuation
    ) async {
        continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: 0.01))

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            markSessionCancelled(sessionId)
            continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: -1, error: "No video track"))
            return
        }

        guard let duration = try? await asset.load(.duration) else {
            markSessionCancelled(sessionId)
            continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: -1, error: "Could not load duration"))
            return
        }

        let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate)
        let transform = try? await videoTrack.load(.preferredTransform)

        await dataStore.configure(algorithmType: tracker.algorithmType, videoDuration: duration)
        continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: 0.03))

        guard let reader = try? AVAssetReader(asset: asset) else {
            markSessionCancelled(sessionId)
            continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: -1, error: "Could not create reader"))
            return
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            markSessionCancelled(sessionId)
            continuation.yield(TrackingProgressEvent(
                sessionId: sessionId, progress: -1,
                error: "Could not start reading: \(reader.error?.localizedDescription ?? "unknown")"
            ))
            return
        }

        continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: 0.05))

        let orientation = calculateOrientation(from: transform ?? .identity)
        let totalSeconds = duration.seconds
        let checkpointProgress: Double = 0.05

        var lastProgressValue: Double = 0
        var lastProgressTime: TimeInterval = 0
        var frameIndex = 0
        var processedFrames = 0
        var previousResults: [PersonTrackingResult]?
        var frameBuffer: [FrameTrackingResult] = []
        let bufferSize = 10
        var lastFrameTime = Date()
        let maxStallSeconds: TimeInterval = 10.0
        var didStall = false

        // Check cancellation
        if isSessionCancelled(sessionId) {
            reader.cancelReading()
            return
        }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            // Check reader status
            if reader.status == .failed || reader.status == .cancelled {
                break
            }

            // Check cancellation
            if isSessionCancelled(sessionId) {
                reader.cancelReading()
                break
            }

            // Skip frames based on stride
            if frameIndex % stride != 0 {
                frameIndex += 1
                continue
            }

            // Stall detection
            let currentTime = Date()
            if currentTime.timeIntervalSince(lastFrameTime) > maxStallSeconds {
                didStall = true
                break
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                frameIndex += 1
                continue
            }

            lastFrameTime = currentTime

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let timestampMs = Int(presentationTime.seconds * 1000)

            // CVPixelBuffer is thread-safe but not Sendable; nonisolated(unsafe)
            // is safe here because the buffer is consumed within this iteration.
            nonisolated(unsafe) let safeBuffer = pixelBuffer

            do {
                let results = try await tracker.analyze(
                    pixelBuffer: safeBuffer,
                    orientation: orientation,
                    previousResults: previousResults
                )

                let timedResults = results.map { result in
                    result.with(timestampMs: timestampMs)
                }

                let frameResult = FrameTrackingResult(
                    timestampMs: timestampMs,
                    people: timedResults
                )

                frameBuffer.append(frameResult)

                if frameBuffer.count >= bufferSize {
                    let framesToFlush = frameBuffer
                    frameBuffer = []
                    for frame in framesToFlush {
                        await dataStore.store(frame, smooth: true)
                    }
                }

                previousResults = timedResults
                processedFrames += 1
            } catch {
                // Log but continue
                Self.logger.warning("Error at \(timestampMs)ms: \(error.localizedDescription, privacy: .public)")
            }

            // Progress update
            let frameProgress = presentationTime.seconds / totalSeconds
            let progress = checkpointProgress + frameProgress * (1.0 - checkpointProgress)

            let now = Date().timeIntervalSince1970
            if progress - lastProgressValue >= 0.01 || now - lastProgressTime >= 0.1 || progress >= 1.0 {
                continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: progress))
                lastProgressValue = progress
                lastProgressTime = now
            }

            frameIndex += 1
        }

        // Flush remaining buffer
        if !frameBuffer.isEmpty {
            for frame in frameBuffer {
                await dataStore.store(frame, smooth: true)
            }
            frameBuffer.removeAll()
        }

        if didStall {
            markSessionCancelled(sessionId)
            continuation.yield(TrackingProgressEvent(
                sessionId: sessionId, progress: -1,
                error: "Analysis stalled - video may be too complex. Try again or use a shorter video."
            ))
        } else {
            // Post-processing pipeline
            let fps = Double(nominalFrameRate ?? 30)

            // Phase 0: RTS backward smoothing
            await dataStore.applyRTSSmoothing(fps: fps)

            // Phase 1: Bounding box smoothing
            await dataStore.smoothBoundingBoxes()

            // Phase 1b: Merge tracks by spatial proximity
            await dataStore.mergeTracksBySpatialProximity()

            // Phase 1c: Filter noise tracks
            await dataStore.filterNoiseTracks(minDurationSeconds: 0.5, fps: fps)

            // Phase 2: Gap filling
            _ = await dataStore.fillTrackingGaps(maxGapFrames: 15)

            // Phase 3: ReID-based merge
            await applyPostTrackingMerge(
                sessionId: sessionId,
                dataStore: dataStore,
                videoPath: path
            )

            // Phase 4: People Library identification
            await identifyTracksParallel(
                dataStore: dataStore,
                videoPath: path
            )

            markSessionComplete(sessionId)
            continuation.yield(TrackingProgressEvent(sessionId: sessionId, progress: 1.0))

            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Session Management

    private func markSessionCancelled(_ sessionId: String) {
        sessions[sessionId]?.isCancelled = true
    }

    private func markSessionComplete(_ sessionId: String) {
        sessions[sessionId]?.isComplete = true
    }

    private func isSessionCancelled(_ sessionId: String) -> Bool {
        sessions[sessionId]?.isCancelled ?? true
    }

    /// Cancel an active analysis session.
    func cancelAnalysis(sessionId: String) {
        sessions[sessionId]?.isCancelled = true
        sessions.removeValue(forKey: sessionId)
        dataStores.removeValue(forKey: sessionId)
        mergeStatisticsCache.removeValue(forKey: sessionId)
    }

    /// Remove a completed session.
    func removeSession(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        dataStores.removeValue(forKey: sessionId)
        mergeStatisticsCache.removeValue(forKey: sessionId)
    }

    // MARK: - Results

    /// Get tracking results for a time range.
    func getResults(sessionId: String, startMs: Int = 0, endMs: Int = Int.max) async -> [FrameTrackingResult]? {
        guard let dataStore = dataStores[sessionId] else { return nil }
        let startTime = CMTime(value: Int64(startMs), timescale: 1000)
        let endTime = CMTime(value: Int64(endMs), timescale: 1000)
        return await dataStore.getResults(from: startTime, to: endTime)
    }

    /// Get interpolated result at a specific timestamp.
    func getInterpolatedResult(sessionId: String, timestampMs: Int) async -> FrameTrackingResult? {
        guard let dataStore = dataStores[sessionId] else { return nil }
        let time = CMTime(value: Int64(timestampMs), timescale: 1000)
        return await dataStore.getInterpolatedResult(at: time)
    }

    /// Get all results from a session.
    func getAllResults(sessionId: String) async -> [FrameTrackingResult]? {
        guard let dataStore = dataStores[sessionId] else { return nil }
        return await dataStore.getAllResults()
    }

    /// Export tracking data as JSON.
    func exportTrackingData(sessionId: String) async throws -> Data? {
        guard let dataStore = dataStores[sessionId] else { return nil }
        return try await dataStore.exportJSON()
    }

    /// Get detected persons for a session.
    func getDetectedPersons(sessionId: String) async -> [TrackingDataStore.DetectedPersonInfo]? {
        guard let dataStore = dataStores[sessionId] else { return nil }
        return await dataStore.getDetectedPersons()
    }

    /// Get quality metrics for a session.
    func getQualityMetrics(sessionId: String) async -> TrackingQualityMetrics? {
        guard let dataStore = dataStores[sessionId] else { return nil }

        let allResults = await dataStore.getAllResults()
        guard !allResults.isEmpty else { return nil }

        var totalConfidence: Double = 0
        var totalFramesWithTracking = 0
        var totalPersonFrames = 0
        var lowConfidenceFrames = 0

        let allPersonIDs = Set(allResults.flatMap { $0.people.map(\.personIndex) })

        for frame in allResults {
            totalPersonFrames += allPersonIDs.count
            for person in frame.people {
                totalConfidence += person.confidence
                totalFramesWithTracking += 1
                if person.confidence < 0.65 {
                    lowConfidenceFrames += 1
                }
            }
        }

        let avgConfidence = totalFramesWithTracking > 0
            ? totalConfidence / Double(totalFramesWithTracking)
            : 0.0

        let trackingStability = totalPersonFrames > 0
            ? Double(totalFramesWithTracking) / Double(totalPersonFrames)
            : 0.0

        return TrackingQualityMetrics(
            averageConfidence: avgConfidence,
            trackingStability: trackingStability,
            totalFrames: allResults.count,
            trackedFrames: totalFramesWithTracking,
            gapFilledFrames: lowConfidenceFrames
        )
    }

    // MARK: - Person Thumbnail

    /// Extract a cropped thumbnail for a detected person.
    func extractPersonThumbnail(
        sessionId: String,
        personIndex: Int,
        videoPath: String
    ) async -> Data? {
        guard let dataStore = dataStores[sessionId] else { return nil }

        let detectedPersons = await dataStore.getDetectedPersons()
        guard let person = detectedPersons.first(where: { $0.personIndex == personIndex }) else {
            return nil
        }

        return await extractThumbnail(
            videoPath: videoPath,
            timestampMs: person.firstTimestampMs,
            boundingBox: person.boundingBox
        )
    }

    // MARK: - People Library Integration

    /// Set the People library for track identification.
    func setPeopleLibrary(_ entries: [PersonLibraryEntry]) async {
        await personIdentifier.updateLibrary(entries)
    }

    /// Clear the People library.
    func clearPeopleLibrary() async {
        await personIdentifier.clearLibrary()
    }

    // MARK: - Orientation Helper

    private func calculateOrientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let angle = atan2(transform.b, transform.a)
        switch angle {
        case 0: return .up
        case .pi / 2: return .right
        case -.pi / 2: return .left
        case .pi, -.pi: return .down
        default: return .up
        }
    }

    // MARK: - Post-Tracking Merge

    private func applyPostTrackingMerge(
        sessionId: String,
        dataStore: TrackingDataStore,
        videoPath: String
    ) async {
        let allResults = await dataStore.getAllResults()
        guard !allResults.isEmpty else { return }

        let videoURL = URL(fileURLWithPath: videoPath)
        let (mergedResults, statistics) = await trackReidentifier.mergeFragmentedTracks(
            results: allResults,
            videoURL: videoURL
        )

        mergeStatisticsCache[sessionId] = (statistics: statistics, timestamp: Date())
        if mergeStatisticsCache.count > mergeStatisticsCacheLimit {
            if let oldestKey = mergeStatisticsCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                mergeStatisticsCache.removeValue(forKey: oldestKey)
            }
        }

        if statistics.mergeCount > 0 {
            await dataStore.replaceAllResults(mergedResults)
        }
    }

    // MARK: - Parallel Identification

    private func identifyTracksParallel(
        dataStore: TrackingDataStore,
        videoPath: String
    ) async {
        let reidExtractor = ReIDExtractor.shared
        guard reidExtractor.isReady else { return }
        guard await personIdentifier.hasLibrary else { return }

        let trackIds = await dataStore.getUniqueTrackIds()
        guard !trackIds.isEmpty else { return }

        let url = URL(fileURLWithPath: videoPath)
        let asset = AVURLAsset(url: url)

        let maxSamplesPerTrack = 5
        let maxConcurrency = 4

        // Extract actor references before task group to avoid capturing `self`
        let identifier = personIdentifier

        await withTaskGroup(of: (Int, String, String, Double)?.self) { group in
            var runningCount = 0

            for trackId in trackIds {
                if runningCount >= maxConcurrency {
                    if let result = await group.next() {
                        runningCount -= 1
                        if let (tid, personId, personName, confidence) = result {
                            await dataStore.updateIdentification(
                                forTrack: tid,
                                personId: personId,
                                personName: personName,
                                confidence: confidence
                            )
                        }
                    }
                }

                group.addTask {
                    // Create per-task image generator to avoid sharing non-Sendable state
                    let imageGenerator = AVAssetImageGenerator(asset: asset)
                    imageGenerator.appliesPreferredTrackTransform = true
                    imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
                    imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

                    let trackFrames = await dataStore.getFramesForTrack(trackId, limit: maxSamplesPerTrack)
                    guard !trackFrames.isEmpty else { return nil }

                    var multiView: MultiViewAppearance?

                    for frame in trackFrames {
                        let time = CMTime(value: CMTimeValue(frame.timestampMs), timescale: 1000)
                        guard let (cgImage, _) = try? await imageGenerator.image(at: time) else { continue }

                        let cropRect = CGRect(
                            x: frame.bbox.x - frame.bbox.width / 2,
                            y: frame.bbox.y - frame.bbox.height / 2,
                            width: frame.bbox.width,
                            height: frame.bbox.height
                        )

                        guard let appearance = reidExtractor.extractFeature(
                            from: cgImage,
                            boundingBox: cropRect,
                            skipQualityCheck: true
                        ) else { continue }

                        if multiView == nil {
                            multiView = MultiViewAppearance(appearance: appearance)
                        } else {
                            multiView?.update(with: appearance, orientation: .unknown)
                        }

                        guard let mv = multiView else { continue }
                        let identResult = await identifier.identify(
                            trackId: trackId,
                            multiViewAppearance: mv
                        )

                        if identResult.isIdentified,
                           let personId = identResult.personId,
                           let personName = identResult.personName {
                            return (trackId, personId, personName, identResult.confidence)
                        }
                    }

                    return nil
                }
                runningCount += 1
            }

            for await result in group {
                guard let (tid, personId, personName, confidence) = result else { continue }
                await dataStore.updateIdentification(
                    forTrack: tid,
                    personId: personId,
                    personName: personName,
                    confidence: confidence
                )
            }
        }
    }

    // MARK: - Thumbnail Extraction

    private func extractThumbnail(
        videoPath: String,
        timestampMs: Int,
        boundingBox: NormalizedBoundingBox?
    ) async -> Data? {
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVURLAsset(url: url)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        let time = CMTime(value: CMTimeValue(timestampMs), timescale: 1000)

        do {
            let (cgImage, _) = try await imageGenerator.image(at: time)
            var finalImage = cgImage

            if let bbox = boundingBox {
                let imageWidth = Double(cgImage.width)
                let imageHeight = Double(cgImage.height)

                let padding = 0.15
                let paddedWidth = min(1.0, bbox.width * (1 + 2 * padding))
                let paddedHeight = min(1.0, bbox.height * (1 + 2 * padding))
                let paddedX = max(0, min(1.0 - paddedWidth, bbox.x - bbox.width * padding))
                let paddedY = max(0, min(1.0 - paddedHeight, bbox.y - bbox.height * padding))

                let cropX = paddedX * imageWidth
                let cropY = (1.0 - paddedY - paddedHeight) * imageHeight
                let cropWidth = min(paddedWidth * imageWidth, imageWidth - cropX)
                let cropHeight = min(paddedHeight * imageHeight, imageHeight - cropY)

                let cropRect = CGRect(
                    x: max(0, min(cropX, imageWidth - 1)),
                    y: max(0, min(cropY, imageHeight - 1)),
                    width: max(1, min(cropWidth, imageWidth - max(0, cropX))),
                    height: max(1, min(cropHeight, imageHeight - max(0, cropY)))
                )

                if let croppedImage = cgImage.cropping(to: cropRect) {
                    finalImage = croppedImage
                }
            }

            // Resize to thumbnail
            let uiImage = UIImage(cgImage: finalImage)
            let maxSize: CGFloat = 150
            let scale = min(maxSize / uiImage.size.width, maxSize / uiImage.size.height)
            let targetSize = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            let resizedImage = renderer.image { _ in
                uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            return resizedImage.jpegData(compressionQuality: 0.8)
        } catch {
            Self.logger.warning("Error extracting thumbnail: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Get cached merge statistics for debug info.
    func getMergeStatistics(for sessionId: String) -> TrackMergeStatistics? {
        mergeStatisticsCache[sessionId]?.statistics
    }

    // MARK: - Debug Summary

    /// Build a comprehensive debug summary for a completed tracking session.
    ///
    /// Computes per-track statistics (confidence, gaps, motion, identification)
    /// from raw frame results and cached merge statistics.
    ///
    /// - Parameter sessionId: The session to summarize.
    /// - Returns: A `TrackingDebugSummary`, or nil if the session has no results.
    func getDebugSummary(for sessionId: String) async -> TrackingDebugSummary? {
        guard let allResults = await getAllResults(sessionId: sessionId),
              !allResults.isEmpty else { return nil }

        let mergeStats = getMergeStatistics(for: sessionId)
        let detectedPersons = await getDetectedPersons(sessionId: sessionId) ?? []

        // Pre-compute ReID events and merge details for per-track lookup.
        let allReidEvents = mergeStats?.reidEvents ?? []
        let allMergeDetails = mergeStats?.mergeDetails ?? []

        // Group frame results by person index.
        var personFrames: [Int: [(timestampMs: Int, person: PersonTrackingResult)]] = [:]
        for frame in allResults {
            for person in frame.people {
                personFrames[person.personIndex, default: []].append(
                    (frame.timestampMs, person)
                )
            }
        }

        let uniquePersonCount = personFrames.count
        let rawTrackCount = mergeStats?.tracksBeforeMerge ?? uniquePersonCount

        // Build per-track TrackDebugInfo.
        var trackInfos: [TrackDebugInfo] = []
        for (personIndex, frames) in personFrames.sorted(by: { $0.key < $1.key }) {
            let sorted = frames.sorted { $0.timestampMs < $1.timestampMs }
            let timestamps = sorted.map(\.timestampMs)

            // Confidence statistics.
            let confidences = sorted.map { Float($0.person.confidence) }
            let avgConf = confidences.reduce(0, +) / Float(max(confidences.count, 1))
            let minConf = confidences.min() ?? 0
            let maxConf = confidences.max() ?? 0

            // Confidence histogram (10 equal-width buckets 0.0–1.0).
            var histogram = [Int](repeating: 0, count: 10)
            for conf in confidences {
                let bucket = min(9, Int(conf * 10))
                histogram[bucket] += 1
            }

            // Gap detection: a gap is any inter-frame interval > 3× average.
            let avgIntervalMs = timestamps.count > 1
                ? (timestamps.last! - timestamps.first!) / (timestamps.count - 1)
                : 33
            let gapThresholdMs = avgIntervalMs * 3
            var gaps: [TrackGap] = []
            for i in 1..<timestamps.count {
                let dt = timestamps[i] - timestamps[i - 1]
                if dt > gapThresholdMs {
                    let reason: GapReason = dt > 2_000 ? .outOfFrame : .lowConfidence
                    gaps.append(TrackGap(
                        startFrame: i - 1,
                        endFrame: i,
                        startMs: timestamps[i - 1],
                        endMs: timestamps[i],
                        likelyReason: reason
                    ))
                }
            }

            // Bounding box statistics.
            let boxes = sorted.compactMap(\.person.boundingBox)
            let avgW = boxes.isEmpty ? 0 : boxes.map(\.width).reduce(0, +) / Double(boxes.count)
            let avgH = boxes.isEmpty ? 0 : boxes.map(\.height).reduce(0, +) / Double(boxes.count)
            let avgCX = boxes.isEmpty ? 0 : boxes.map { $0.x }.reduce(0, +) / Double(boxes.count)
            let avgCY = boxes.isEmpty ? 0 : boxes.map { $0.y }.reduce(0, +) / Double(boxes.count)

            // Motion estimation (normalized units/second).
            var velocities: [Float] = []
            for i in 1..<sorted.count {
                let dtSec = Float(sorted[i].timestampMs - sorted[i - 1].timestampMs) / 1_000
                guard dtSec > 0,
                      let b1 = sorted[i - 1].person.boundingBox,
                      let b2 = sorted[i].person.boundingBox else { continue }
                let dx = Float(b2.x - b1.x)
                let dy = Float(b2.y - b1.y)
                velocities.append(sqrt(dx * dx + dy * dy) / dtSec)
            }
            let avgVel = velocities.isEmpty ? 0 : velocities.reduce(0, +) / Float(velocities.count)
            let maxVel = velocities.max() ?? 0
            let motionClass: MotionClass = avgVel > 0.02 ? .high : (avgVel > 0.005 ? .medium : .low)

            // Identification from People Library.
            let identified = detectedPersons.first { $0.personIndex == personIndex }

            // ReID restorations: events where this track's identity was restored.
            let trackReidEvents = allReidEvents.filter { $0.restoredTrackId == personIndex }

            // Merged-from track IDs: tracks that were absorbed into this one.
            let mergedFrom = allMergeDetails
                .filter { $0.toTrackId == personIndex }
                .map(\.fromTrackId)

            trackInfos.append(TrackDebugInfo(
                trackId: personIndex,
                firstFrame: sorted.first.map { _ in 0 } ?? 0,
                lastFrame: sorted.count - 1,
                firstFrameMs: sorted.first?.timestampMs ?? 0,
                lastFrameMs: sorted.last?.timestampMs ?? 0,
                totalFrames: sorted.count,
                avgConfidence: avgConf,
                minConfidence: minConf,
                maxConfidence: maxConf,
                confidenceHistogram: histogram,
                gaps: gaps,
                totalGapDurationMs: gaps.reduce(0) { $0 + $1.durationMs },
                reidRestorations: trackReidEvents,
                mergedFromTrackIds: mergedFrom,
                identifiedPersonId: identified?.identifiedPersonId,
                identifiedPersonName: identified?.identifiedPersonName,
                identificationConfidence: identified?.identificationConfidence,
                avgBboxSize: CGSize(width: avgW, height: avgH),
                avgBboxCenter: CGPoint(x: avgCX, y: avgCY),
                bboxSizeVariance: 0,
                avgVelocity: avgVel,
                maxVelocity: maxVel,
                motionClassification: motionClass,
                state: "confirmed"
            ))
        }

        let mergeDetails: [TrackMergeDebugDetail] = mergeStats?.mergeDetails.map {
            TrackMergeDebugDetail(
                fromTrackId: $0.fromTrackId,
                toTrackId: $0.toTrackId,
                similarity: $0.similarity,
                gapMs: $0.gapMs
            )
        } ?? []

        return TrackingDebugSummary(
            uniquePersonCount: uniquePersonCount,
            rawTrackCount: rawTrackCount,
            reidMergeCount: mergeStats?.mergeCount ?? 0,
            reidEnabled: true,
            tracks: trackInfos,
            tracksBeforeMerge: mergeStats?.tracksBeforeMerge ?? rawTrackCount,
            tracksAfterMerge: mergeStats?.tracksAfterMerge ?? uniquePersonCount,
            postTrackingMergeCount: mergeStats?.mergeCount ?? 0,
            postTrackingMergeDetails: mergeDetails,
            postTrackingMergeEnabled: mergeStats != nil
        )
    }
}

// MARK: - Session State (Internal)

/// Mutable session state managed by the actor.
private struct TrackingSessionState {
    let id: String
    let algorithmType: String
    var progress: Double = 0
    var isComplete: Bool = false
    var isCancelled: Bool = false
}
