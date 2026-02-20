//
//  BoundingBoxTracker.swift
//  LiquidEditor
//
//  Full-body bounding box tracking using Vision pose detection.
//  Tracks people via VNDetectHumanBodyPoseRequest with velocity-predicted
//  re-identification across frames.
//
//

import CoreMedia
import Foundation
import os
import Vision

// MARK: - Tracking Algorithm Protocol

/// Protocol for pluggable tracking algorithms.
protocol TrackingAlgorithm: Sendable {
    /// Unique algorithm identifier.
    var algorithmType: String { get }
    /// Human-readable name.
    var displayName: String { get }
    /// Whether multiple people can be tracked simultaneously.
    var supportsMultiplePeople: Bool { get }

    /// Analyze a single frame.
    func analyze(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        previousResults: [PersonTrackingResult]?
    ) async throws -> [PersonTrackingResult]

    /// Reset internal state.
    func reset()
}

// MARK: - Tracking Errors

enum TrackingError: LocalizedError {
    case videoNotFound
    case videoTrackNotFound
    case analysisFailure(String)
    case cancelled
    case unsupportedAlgorithm(String)
    case insufficientConfidence

    var errorDescription: String? {
        switch self {
        case .videoNotFound: "Video file not found"
        case .videoTrackNotFound: "No video track in asset"
        case .analysisFailure(let reason): "Tracking analysis failed: \(reason)"
        case .cancelled: "Tracking analysis cancelled"
        case .unsupportedAlgorithm(let name): "Unsupported tracking algorithm: \(name)"
        case .insufficientConfidence: "Tracking confidence too low"
        }
    }
}

// MARK: - BoundingBoxTracker

/// Tracks people using pose-based full-body bounding boxes.
///
/// Uses `VNDetectHumanBodyPoseRequest` to detect all keypoints, then
/// computes a bounding box encompassing detected joints. Falls back to
/// `VNDetectHumanRectanglesRequest` when pose detection yields no results.
///
/// **Thread Safety:** This class uses `@unchecked Sendable` and protects
/// all mutable state with `OSAllocatedUnfairLock`. Callers may invoke
/// `analyze` and `reset` from any context; internal locking ensures
/// correctness. In practice, `TrackingService` (an actor) serializes
/// calls, so lock contention is expected to be zero.
final class BoundingBoxTracker: TrackingAlgorithm, @unchecked Sendable {

    // MARK: - Protocol Properties

    let algorithmType = "boundingBox"
    let displayName = "Full Body"
    let supportsMultiplePeople = true

    // MARK: - Lock-Protected State

    /// Mutable tracking state protected by the unfair lock.
    private struct TrackerState: @unchecked Sendable {
        var sequenceHandler: VNSequenceRequestHandler? = VNSequenceRequestHandler()
        var lastKnownBoxes: [Int: CGRect] = [:]
        var velocities: [Int: CGPoint] = [:]
        var lastFrameNumbers: [Int: Int] = [:]
        var currentFrameNumber: Int = 0
        var nextPersonIndex = 0
    }

    /// Lock protecting all mutable state.
    private let trackerState = OSAllocatedUnfairLock(initialState: TrackerState())

    // MARK: - Constants

    private let minConfidence: Float = 0.3
    private let reidentificationIoUThreshold: Float = 0.15
    private let maxCenterDistance: CGFloat = 0.6
    private let velocitySmoothing: CGFloat = 0.3

    // Body bounding box margins
    private static let headMarginRatio: CGFloat = 0.12
    private static let footMarginRatio: CGFloat = 0.08
    private static let lateralPaddingRatio: CGFloat = 0.15

    // Joint confidence threshold
    private static let jointConfidenceThreshold: Float = 0.05

    // MARK: - Initialization

    init() {}

    // MARK: - TrackingAlgorithm

    func analyze(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        previousResults: [PersonTrackingResult]?
    ) async throws -> [PersonTrackingResult] {
        trackerState.withLock { $0.currentFrameNumber += 1 }
        return try autoreleasepool {
            try performPoseDetection(pixelBuffer: pixelBuffer, orientation: orientation)
        }
    }

    func reset() {
        trackerState.withLock { s in
            s.sequenceHandler = VNSequenceRequestHandler()
            s.lastKnownBoxes.removeAll()
            s.velocities.removeAll()
            s.lastFrameNumbers.removeAll()
            s.currentFrameNumber = 0
            s.nextPersonIndex = 0
        }
    }

    // MARK: - Pose-Based Detection

    private func performPoseDetection(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> [PersonTrackingResult] {
        // Vision requests run outside the lock (CPU-bound, no state access).
        let poseRequest = VNDetectHumanBodyPoseRequest()
        let rectRequest = VNDetectHumanRectanglesRequest()
        rectRequest.upperBodyOnly = false

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        try handler.perform([poseRequest, rectRequest])

        let observations = poseRequest.results ?? []
        guard !observations.isEmpty else {
            return processRectangleResults(rectRequest.results ?? [])
        }

        // Build detection list (pure computation, no mutable state).
        // Extract Sendable data before entering the lock closure.
        // Use let binding so the closure does not capture a mutable variable.
        let genericDetections: [(index: Int, rect: CGRect, confidence: Float, pose: PoseJoints?)] =
            observations.enumerated().compactMap { index, observation in
                guard observation.confidence >= minConfidence,
                      let rect = computeFullBodyBoundingBox(from: observation)
                else { return nil }
                let pose = extractPoseJoints(from: observation)
                return (index, rect, observation.confidence, pose)
            }

        // Match detections to tracked persons and update state under lock.
        // Use withLockUnchecked: genericDetections is effectively Sendable (all
        // members are Sendable value types) but Swift cannot prove tuple Sendable.
        return trackerState.withLockUnchecked { s in
            self.matchAndUpdateStateGeneric(
                detections: genericDetections,
                state: &s,
                iouWeight: 0.4,
                distWeight: 0.6,
                maxCenterDist: self.maxCenterDistance,
                useIoUThreshold: true
            )
        }
    }

    // MARK: - Rectangle Fallback

    private func processRectangleResults(_ observations: [VNHumanObservation]) -> [PersonTrackingResult] {
        var detectionBoxes: [(rect: CGRect, observation: VNHumanObservation)] = []
        for observation in observations {
            guard observation.confidence >= minConfidence else { continue }
            detectionBoxes.append((observation.boundingBox, observation))
        }
        guard !detectionBoxes.isEmpty else { return [] }

        // Convert to generic detection format for shared matching logic.
        let genericDetections: [(index: Int, rect: CGRect, confidence: Float, pose: PoseJoints?)] =
            detectionBoxes.enumerated().map { (idx, det) in
                (index: idx, rect: det.rect, confidence: det.observation.confidence, pose: nil)
            }

        return trackerState.withLockUnchecked { s in
            matchAndUpdateStateGeneric(
                detections: genericDetections,
                state: &s,
                iouWeight: 0.3,
                distWeight: 0.7,
                maxCenterDist: maxCenterDistance * 1.5,
                useIoUThreshold: false
            )
        }
    }

    // MARK: - Shared Matching Logic

    /// Generic matching of detections to tracked persons.
    /// Must be called under `trackerState` lock.
    private func matchAndUpdateStateGeneric(
        detections: [(index: Int, rect: CGRect, confidence: Float, pose: PoseJoints?)],
        state s: inout TrackerState,
        iouWeight: Double,
        distWeight: Double,
        maxCenterDist: CGFloat,
        useIoUThreshold: Bool
    ) -> [PersonTrackingResult] {
        // Velocity-predicted positions
        var predictedPositions: [Int: CGRect] = [:]
        for (personIndex, lastRect) in s.lastKnownBoxes {
            let framesSinceSeen = s.currentFrameNumber - (s.lastFrameNumbers[personIndex] ?? s.currentFrameNumber)
            guard framesSinceSeen < 60 else { continue }
            if let velocity = s.velocities[personIndex] {
                let px = lastRect.midX + velocity.x * CGFloat(framesSinceSeen)
                let py = lastRect.midY + velocity.y * CGFloat(framesSinceSeen)
                predictedPositions[personIndex] = CGRect(
                    x: px - lastRect.width / 2, y: py - lastRect.height / 2,
                    width: lastRect.width, height: lastRect.height
                )
            } else {
                predictedPositions[personIndex] = lastRect
            }
        }

        // Cost matrix
        let knownPersonIds = Array(predictedPositions.keys).sorted()
        var costMatrix: [[Double]] = []

        for detection in detections {
            var rowCosts: [Double] = []
            for personId in knownPersonIds {
                guard let predictedRect = predictedPositions[personId] else {
                    rowCosts.append(.infinity)
                    continue
                }

                let overlap = iou(detection.rect, predictedRect)
                let lastRect = s.lastKnownBoxes[personId]!
                let currentCenter = CGPoint(x: detection.rect.midX, y: detection.rect.midY)
                let predictedCenter = CGPoint(x: predictedRect.midX, y: predictedRect.midY)
                let distance = hypot(currentCenter.x - predictedCenter.x, currentCenter.y - predictedCenter.y)
                let lastCenter = CGPoint(x: lastRect.midX, y: lastRect.midY)
                let distanceToLast = hypot(currentCenter.x - lastCenter.x, currentCenter.y - lastCenter.y)
                let effectiveDistance = min(distance, distanceToLast)

                let iouCost = 1.0 - Double(overlap)
                let distCost = min(Double(effectiveDistance), 1.0)
                let cost = iouCost * iouWeight + distCost * distWeight

                let reject: Bool
                if useIoUThreshold {
                    reject = overlap < CGFloat(reidentificationIoUThreshold) && effectiveDistance > maxCenterDist
                } else {
                    reject = effectiveDistance > maxCenterDist
                }

                rowCosts.append(reject ? .infinity : cost)
            }
            costMatrix.append(rowCosts)
        }

        // Greedy assignment
        var usedPersonIds: Set<Int> = []
        var usedDetections: Set<Int> = []
        var assignments: [(detectionIdx: Int, personId: Int)] = []

        for _ in 0..<min(detections.count, knownPersonIds.count) {
            var bestCost = Double.infinity
            var bestDetection = -1
            var bestPerson = -1

            for (detIdx, _) in detections.enumerated() {
                guard !usedDetections.contains(detIdx) else { continue }
                for (personColIdx, personId) in knownPersonIds.enumerated() {
                    guard !usedPersonIds.contains(personId) else { continue }
                    let cost = costMatrix[detIdx][personColIdx]
                    if cost < bestCost {
                        bestCost = cost
                        bestDetection = detIdx
                        bestPerson = personId
                    }
                }
            }

            if bestCost < .infinity && bestDetection >= 0 && bestPerson >= 0 {
                assignments.append((bestDetection, bestPerson))
                usedDetections.insert(bestDetection)
                usedPersonIds.insert(bestPerson)
            } else {
                break
            }
        }

        // Build results
        var results: [PersonTrackingResult] = []

        for (detIdx, personId) in assignments {
            let detection = detections[detIdx]
            updateVelocity(personId: personId, rect: detection.rect, state: &s)
            s.lastKnownBoxes[personId] = detection.rect
            s.lastFrameNumbers[personId] = s.currentFrameNumber

            let bbox = NormalizedBoundingBox.from(visionRect: detection.rect)
            results.append(PersonTrackingResult(
                personIndex: personId,
                confidence: Double(detection.confidence),
                boundingBox: bbox,
                bodyOutline: nil,
                pose: detection.pose,
                timestampMs: 0,
                identifiedPersonId: nil,
                identifiedPersonName: nil,
                identificationConfidence: nil
            ))
        }

        for (detIdx, detection) in detections.enumerated() {
            guard !usedDetections.contains(detIdx) else { continue }
            let personId = s.nextPersonIndex
            s.nextPersonIndex += 1
            s.lastKnownBoxes[personId] = detection.rect
            s.lastFrameNumbers[personId] = s.currentFrameNumber

            let bbox = NormalizedBoundingBox.from(visionRect: detection.rect)
            results.append(PersonTrackingResult(
                personIndex: personId,
                confidence: Double(detection.confidence),
                boundingBox: bbox,
                bodyOutline: nil,
                pose: detection.pose,
                timestampMs: 0,
                identifiedPersonId: nil,
                identifiedPersonName: nil,
                identificationConfidence: nil
            ))
        }

        return results
    }

    // MARK: - Body Bounding Box

    private func computeFullBodyBoundingBox(from observation: VNHumanBodyPoseObservation) -> CGRect? {
        guard let allPoints = try? observation.recognizedPoints(.all) else { return nil }

        let importantJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftEye, .rightEye, .leftEar, .rightEar,
            .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip,
            .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
        ]

        var minX: CGFloat = 1.0, maxX: CGFloat = 0.0
        var minY: CGFloat = 1.0, maxY: CGFloat = 0.0
        var validPointCount = 0

        for joint in importantJoints {
            guard let point = allPoints[joint], point.confidence > Self.jointConfidenceThreshold else { continue }
            let location = point.location
            minX = min(minX, location.x)
            maxX = max(maxX, location.x)
            minY = min(minY, location.y)
            maxY = max(maxY, location.y)
            validPointCount += 1
        }

        guard validPointCount >= 2 else { return nil }

        let width = maxX - minX
        let height = maxY - minY
        let headMargin = height * Self.headMarginRatio
        let footMargin = height * Self.footMarginRatio
        let lateralPadding = width * Self.lateralPaddingRatio

        return CGRect(
            x: max(0, minX - lateralPadding),
            y: max(0, minY - footMargin),
            width: min(1 - max(0, minX - lateralPadding), width + 2 * lateralPadding),
            height: min(1 - max(0, minY - footMargin), height + headMargin + footMargin)
        )
    }

    // MARK: - Pose Joint Extraction

    private func extractPoseJoints(from observation: VNHumanBodyPoseObservation) -> PoseJoints? {
        guard let allPoints = try? observation.recognizedPoints(.all) else { return nil }

        let jointMapping: [(VNHumanBodyPoseObservation.JointName, String)] = [
            (.nose, "nose"), (.leftEye, "leftEye"), (.rightEye, "rightEye"),
            (.leftEar, "leftEar"), (.rightEar, "rightEar"),
            (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
            (.leftElbow, "leftElbow"), (.rightElbow, "rightElbow"),
            (.leftWrist, "leftWrist"), (.rightWrist, "rightWrist"),
            (.leftHip, "leftHip"), (.rightHip, "rightHip"),
            (.leftKnee, "leftKnee"), (.rightKnee, "rightKnee"),
            (.leftAnkle, "leftAnkle"), (.rightAnkle, "rightAnkle"),
            (.neck, "neck"), (.root, "root"),
        ]

        var joints: [String: CGPoint] = [:]
        for (jointName, stringKey) in jointMapping {
            guard let point = allPoints[jointName], point.confidence > Self.jointConfidenceThreshold else { continue }
            joints[stringKey] = CGPoint(x: point.location.x, y: 1.0 - point.location.y)
        }

        return joints.isEmpty ? nil : PoseJoints(joints: joints)
    }

    // MARK: - Velocity Update

    /// Update velocity for a tracked person. Must be called under lock.
    private func updateVelocity(personId: Int, rect: CGRect, state s: inout TrackerState) {
        if let lastRect = s.lastKnownBoxes[personId],
           let lastFrame = s.lastFrameNumbers[personId] {
            let framesDelta = max(1, s.currentFrameNumber - lastFrame)
            let newVelocity = CGPoint(
                x: (rect.midX - lastRect.midX) / CGFloat(framesDelta),
                y: (rect.midY - lastRect.midY) / CGFloat(framesDelta)
            )
            if let oldVelocity = s.velocities[personId] {
                s.velocities[personId] = CGPoint(
                    x: oldVelocity.x * velocitySmoothing + newVelocity.x * (1 - velocitySmoothing),
                    y: oldVelocity.y * velocitySmoothing + newVelocity.y * (1 - velocitySmoothing)
                )
            } else {
                s.velocities[personId] = newVelocity
            }
        }
    }

    // MARK: - IoU

    private func iou(_ rect1: CGRect, _ rect2: CGRect) -> CGFloat {
        let intersection = rect1.intersection(rect2)
        if intersection.isNull { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = rect1.width * rect1.height + rect2.width * rect2.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}

// MARK: - NormalizedBoundingBox Vision Extension

extension NormalizedBoundingBox {
    /// Create from Vision observation (bottom-left origin to top-left origin).
    static func from(visionRect: CGRect) -> NormalizedBoundingBox {
        NormalizedBoundingBox(
            x: visionRect.midX,
            y: 1.0 - visionRect.midY,
            width: visionRect.width,
            height: visionRect.height
        )
    }
}
