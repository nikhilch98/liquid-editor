import Foundation
import Vision
import AVFoundation
import CoreImage
import AppKit

// MARK: - Tracking Result Models

struct BoundingBox: Codable {
    let x: Double      // Center X (normalized 0-1)
    let y: Double      // Center Y (normalized 0-1)
    let width: Double  // Width (normalized 0-1)
    let height: Double // Height (normalized 0-1)
}

struct TrackedPerson: Codable {
    let personIndex: Int
    let confidence: Float
    let boundingBox: BoundingBox
    let joints: [String: JointPosition]?  // Skeleton joints (normalized coords, Y flipped for web)
}

struct FrameResult: Codable {
    let frameNumber: Int
    let timestampMs: Int64
    let people: [TrackedPerson]
}

// MARK: - Raw Detection Cache (Algorithm-Independent)

struct JointPosition: Codable {
    let x: Double
    let y: Double
    let confidence: Float
}

struct RawPoseDetection: Codable {
    let boundingBox: BoundingBox  // Computed from joints
    let confidence: Float
    let joints: [String: JointPosition]  // Joint name -> position
}

struct RawFrameDetections: Codable {
    let frameNumber: Int
    let timestampMs: Int64
    let detections: [RawPoseDetection]
}

struct DetectionCache: Codable {
    let videoPath: String
    let videoDuration: Double
    let fps: Double
    let totalFrames: Int
    let stride: Int
    let createdAt: Date
    let frames: [RawFrameDetections]
}

struct VideoAnalysisResult: Codable {
    let totalFrames: Int
    let duration: Double
    let fps: Double
    let frames: [FrameResult]
}

// MARK: - Matrix Operations for Kalman Filter

private struct Mat {
    var d: [[Double]]
    var rows: Int { d.count }
    var cols: Int { d.isEmpty ? 0 : d[0].count }

    static func eye(_ n: Int) -> Mat {
        var m = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n { m[i][i] = 1.0 }
        return Mat(d: m)
    }

    static func diag(_ v: [Double]) -> Mat {
        var m = Array(repeating: Array(repeating: 0.0, count: v.count), count: v.count)
        for i in 0..<v.count { m[i][i] = v[i] }
        return Mat(d: m)
    }

    func T() -> Mat {
        var r = Array(repeating: Array(repeating: 0.0, count: rows), count: cols)
        for i in 0..<rows { for j in 0..<cols { r[j][i] = d[i][j] } }
        return Mat(d: r)
    }

    static func *(a: Mat, b: Mat) -> Mat {
        var r = Array(repeating: Array(repeating: 0.0, count: b.cols), count: a.rows)
        for i in 0..<a.rows {
            for k in 0..<a.cols {
                let aik = a.d[i][k]
                for j in 0..<b.cols { r[i][j] += aik * b.d[k][j] }
            }
        }
        return Mat(d: r)
    }

    static func +(a: Mat, b: Mat) -> Mat {
        var r = a.d
        for i in 0..<a.rows { for j in 0..<a.cols { r[i][j] += b.d[i][j] } }
        return Mat(d: r)
    }

    static func -(a: Mat, b: Mat) -> Mat {
        var r = a.d
        for i in 0..<a.rows { for j in 0..<a.cols { r[i][j] -= b.d[i][j] } }
        return Mat(d: r)
    }

    func mulVec(_ v: [Double]) -> [Double] {
        d.map { row in zip(row, v).map(*).reduce(0, +) }
    }

    /// Gauss-Jordan inverse for small matrices
    func inverse() -> Mat {
        let n = rows
        var aug = Array(repeating: Array(repeating: 0.0, count: 2*n), count: n)
        for i in 0..<n {
            for j in 0..<n { aug[i][j] = d[i][j] }
            aug[i][n+i] = 1.0
        }
        for col in 0..<n {
            var maxRow = col
            for row in (col+1)..<n {
                if abs(aug[row][col]) > abs(aug[maxRow][col]) { maxRow = row }
            }
            if maxRow != col { aug.swapAt(col, maxRow) }
            let pivot = aug[col][col]
            if abs(pivot) < 1e-12 { continue }
            for j in 0..<(2*n) { aug[col][j] /= pivot }
            for row in 0..<n {
                if row == col { continue }
                let f = aug[row][col]
                for j in 0..<(2*n) { aug[row][j] -= f * aug[col][j] }
            }
        }
        return Mat(d: aug.map { Array($0[n..<(2*n)]) })
    }
}

// MARK: - Kalman Filter for Box Tracking

/// Per-track Kalman filter tracking [cx, cy, w, h, vcx, vcy, vw, vh]
private class KalmanBoxState {
    var x: [Double]        // 8D state vector
    var P: Mat             // 8x8 covariance
    let F: Mat             // 8x8 state transition
    let H: Mat             // 4x8 measurement matrix
    var Q: Mat             // 8x8 process noise
    let R: Mat             // 4x4 measurement noise

    init(bbox: CGRect) {
        x = [Double(bbox.midX), Double(bbox.midY), Double(bbox.width), Double(bbox.height), 0, 0, 0, 0]

        // State transition: next_pos = pos + velocity
        var f = Array(repeating: Array(repeating: 0.0, count: 8), count: 8)
        for i in 0..<8 { f[i][i] = 1.0 }
        for i in 0..<4 { f[i][i+4] = 1.0 }  // velocity contribution
        F = Mat(d: f)

        // Measurement: observe [cx, cy, w, h]
        var h = Array(repeating: Array(repeating: 0.0, count: 8), count: 4)
        for i in 0..<4 { h[i][i] = 1.0 }
        H = Mat(d: h)

        // Process noise: higher for velocity components
        let posNoise = 0.01
        let velNoise = 0.1
        Q = Mat.diag([posNoise, posNoise, posNoise, posNoise,
                       velNoise, velNoise, velNoise, velNoise])

        // Measurement noise
        R = Mat.diag([0.05, 0.05, 0.05, 0.05])

        // Initial covariance: low for position (we observed it), high for velocity (unknown)
        P = Mat.diag([0.1, 0.1, 0.1, 0.1, 10, 10, 10, 10])
    }

    /// Predict next state, return predicted bbox
    func predict() -> CGRect {
        x = F.mulVec(x)
        P = F * P * F.T() + Q
        return CGRect(x: x[0] - x[2]/2, y: x[1] - x[3]/2, width: x[2], height: x[3])
    }

    /// Update state with observed measurement
    func update(bbox: CGRect) {
        let z = [Double(bbox.midX), Double(bbox.midY), Double(bbox.width), Double(bbox.height)]
        let y = zip(z, H.mulVec(x)).map(-)  // Innovation
        let S = H * P * H.T() + R            // Innovation covariance
        let K = P * H.T() * S.inverse()      // Kalman gain
        x = zip(x, K.mulVec(y)).map(+)       // Updated state
        P = (Mat.eye(8) - K * H) * P         // Updated covariance
    }

    var predictedRect: CGRect {
        CGRect(x: x[0] - x[2]/2, y: x[1] - x[3]/2, width: max(x[2], 0.01), height: max(x[3], 0.01))
    }
}

// MARK: - Hungarian Algorithm

/// Finds minimum cost assignment. Returns [(row, col)] pairs.
/// Handles non-square matrices. Entries >= `reject` are not assigned.
private func hungarianAssignment(costs: [[Double]], reject: Double = 1e6) -> [(Int, Int)] {
    let nRows = costs.count
    let nCols = costs.isEmpty ? 0 : costs[0].count
    guard nRows > 0 && nCols > 0 else { return [] }

    let n = max(nRows, nCols)
    // Pad to square with reject cost
    var c = Array(repeating: Array(repeating: reject, count: n), count: n)
    for i in 0..<nRows {
        for j in 0..<nCols {
            c[i][j] = min(costs[i][j], reject)
        }
    }

    // Kuhn-Munkres (Hungarian) algorithm
    var u = Array(repeating: 0.0, count: n + 1)
    var v = Array(repeating: 0.0, count: n + 1)
    var p = Array(repeating: 0, count: n + 1)
    var way = Array(repeating: 0, count: n + 1)

    for i in 1...n {
        p[0] = i
        var j0 = 0
        var minv = Array(repeating: Double.infinity, count: n + 1)
        var used = Array(repeating: false, count: n + 1)

        repeat {
            used[j0] = true
            let i0 = p[j0]
            var delta = Double.infinity
            var j1 = 0

            for j in 1...n {
                if used[j] { continue }
                let cur = c[i0 - 1][j - 1] - u[i0] - v[j]
                if cur < minv[j] {
                    minv[j] = cur
                    way[j] = j0
                }
                if minv[j] < delta {
                    delta = minv[j]
                    j1 = j
                }
            }

            for j in 0...n {
                if used[j] {
                    u[p[j]] += delta
                    v[j] -= delta
                } else {
                    minv[j] -= delta
                }
            }

            j0 = j1
        } while p[j0] != 0

        repeat {
            let j1 = way[j0]
            p[j0] = p[j1]
            j0 = j1
        } while j0 != 0
    }

    var result: [(Int, Int)] = []
    for j in 1...n {
        let i = p[j] - 1
        let jj = j - 1
        if i < nRows && jj < nCols && costs[i][jj] < reject {
            result.append((i, jj))
        }
    }
    return result
}

// MARK: - SORT-Style Tracker

private class SORTTrack {
    let id: Int
    var kalman: KalmanBoxState
    var timeSinceUpdate: Int = 0
    var hitStreak: Int = 1         // Consecutive frames with detection
    var age: Int = 1               // Total frames since creation
    var confidence: Float = 1.0
    var lastJoints: [String: JointPosition]?  // Last known skeleton joints

    init(id: Int, bbox: CGRect, confidence: Float, joints: [String: JointPosition]? = nil) {
        self.id = id
        self.kalman = KalmanBoxState(bbox: bbox)
        self.confidence = confidence
        self.lastJoints = joints
    }

    func predict() -> CGRect {
        let predicted = kalman.predict()
        age += 1
        timeSinceUpdate += 1
        return predicted
    }

    func update(bbox: CGRect, confidence: Float, joints: [String: JointPosition]? = nil) {
        kalman.update(bbox: bbox)
        timeSinceUpdate = 0
        hitStreak += 1
        self.confidence = confidence
        if let joints = joints { self.lastJoints = joints }
    }

    var isConfirmed: Bool { hitStreak >= 3 || age <= 3 }
    var currentRect: CGRect { kalman.predictedRect }
}

class SORTTracker {
    private var tracks: [SORTTrack] = []
    private var nextId = 0
    private let maxAge: Int           // Frames before deleting lost track
    private let minHits: Int          // Min consecutive hits to confirm
    private let iouThreshold: Double  // IoU threshold for assignment

    init(maxAge: Int = 90, minHits: Int = 3, iouThreshold: Double = 0.1) {
        self.maxAge = maxAge
        self.minHits = minHits
        self.iouThreshold = iouThreshold
    }

    func reset() {
        tracks.removeAll()
        nextId = 0
    }

    func update(detections: [(rect: CGRect, confidence: Float, joints: [String: JointPosition]?)]) -> [TrackedPerson] {
        // Step 1: Predict all existing tracks
        var predictedRects: [CGRect] = []
        for track in tracks {
            let predicted = track.predict()
            predictedRects.append(predicted)
        }

        // Step 2: Build IoU-based cost matrix (detections x tracks)
        var costMatrix: [[Double]] = []
        for det in detections {
            var row: [Double] = []
            for predicted in predictedRects {
                let iouVal = iou(det.rect, predicted)
                // Cost = 1 - IoU (lower is better)
                // Also factor in center distance for cases where IoU is 0
                let centerDist = hypot(det.rect.midX - predicted.midX, det.rect.midY - predicted.midY)
                let sizeScale = max(hypot(det.rect.width, det.rect.height),
                                    hypot(predicted.width, predicted.height))
                let normalizedDist = centerDist / max(sizeScale, 0.01)

                if iouVal > CGFloat(iouThreshold) {
                    // Good IoU - use IoU-based cost
                    row.append(1.0 - Double(iouVal))
                } else if normalizedDist < 3.0 {
                    // Low IoU but close - use distance cost (penalized)
                    row.append(0.9 + normalizedDist * 0.1)
                } else {
                    row.append(1e6)  // Too far, reject
                }
            }
            costMatrix.append(row)
        }

        // Step 3: Hungarian assignment
        let assignments = hungarianAssignment(costs: costMatrix)
        var matchedDetections = Set<Int>()
        var matchedTracks = Set<Int>()

        for (detIdx, trackIdx) in assignments {
            matchedDetections.insert(detIdx)
            matchedTracks.insert(trackIdx)
            tracks[trackIdx].update(bbox: detections[detIdx].rect, confidence: detections[detIdx].confidence, joints: detections[detIdx].joints)
        }

        // Step 4: Create new tracks for unmatched detections
        for (detIdx, det) in detections.enumerated() {
            if !matchedDetections.contains(detIdx) {
                let track = SORTTrack(id: nextId, bbox: det.rect, confidence: det.confidence, joints: det.joints)
                nextId += 1
                tracks.append(track)
            }
        }

        // Step 5: Remove dead tracks
        tracks.removeAll { $0.timeSinceUpdate > maxAge }

        // Step 6: Build results (only confirmed tracks)
        var results: [TrackedPerson] = []
        for track in tracks {
            if track.timeSinceUpdate == 0 && (track.hitStreak >= minHits || track.age <= minHits) {
                var rect = track.currentRect

                // Velocity-based expansion: Kalman state x[4]=vcx, x[5]=vcy
                let speed = hypot(track.kalman.x[4], track.kalman.x[5])
                if speed > 0.005 {
                    let expansionFactor = min(speed * 3.0, 0.30)
                    let expandX = rect.width * CGFloat(expansionFactor)
                    let expandY = rect.height * CGFloat(expansionFactor)
                    rect = CGRect(
                        x: max(0, rect.origin.x - expandX / 2),
                        y: max(0, rect.origin.y - expandY / 2),
                        width: min(1 - max(0, rect.origin.x - expandX / 2), rect.width + expandX),
                        height: min(1 - max(0, rect.origin.y - expandY / 2), rect.height + expandY)
                    )
                }

                let bbox = BoundingBox(
                    x: rect.midX,
                    y: 1.0 - rect.midY,  // Flip Y for web
                    width: rect.width,
                    height: rect.height
                )
                results.append(TrackedPerson(
                    personIndex: track.id,
                    confidence: track.confidence,
                    boundingBox: bbox,
                    joints: track.lastJoints
                ))
            }
        }

        return results
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}

// MARK: - Box Tracker (Ported from iOS)

class BoxTracker {
    var lastKnownBoxes: [Int: CGRect] = [:]
    var velocities: [Int: CGPoint] = [:]
    var lastFrameNumbers: [Int: Int] = [:]
    var firstFrameNumbers: [Int: Int] = [:]  // When each track was first seen
    var trackSizes: [Int: CGFloat] = [:]  // Running average bbox diagonal for each track
    var currentFrameNumber: Int = 0
    var nextPersonIndex = 0

    let minConfidence: Float = 0.3
    let boundingBoxPadding: CGFloat = 0.1
    /// Max distance for center-point matching (synced with iOS BoundingBoxTracker)
    let maxCenterDistance: CGFloat = 0.6
    /// Velocity smoothing: 0.3 = 30% old + 70% new - responsive to rapid direction changes (synced with iOS)
    let velocitySmoothing: CGFloat = 0.3
    let maxFrameGap: Int = 90  // Keep tracks alive for 3 seconds at 30fps
    let maxAssignmentCost: Double = 0.8  // Soft cap on assignment cost
    /// Minimum IoU to consider a detection as the same person (synced with iOS)
    let reidentificationIoUThreshold: Float = 0.15

    func reset() {
        lastKnownBoxes.removeAll()
        velocities.removeAll()
        lastFrameNumbers.removeAll()
        firstFrameNumbers.removeAll()
        trackSizes.removeAll()
        currentFrameNumber = 0
        nextPersonIndex = 0
    }

    func analyze(cgImage: CGImage) throws -> [TrackedPerson] {
        currentFrameNumber += 1

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            // Fallback to rectangle detection
            return try performRectangleDetection(cgImage: cgImage)
        }

        // Compute detection bounding boxes and extract joints (matching iOS BoundingBoxTracker)
        var detectionBoxes: [(index: Int, rect: CGRect, observation: VNHumanBodyPoseObservation, joints: [String: JointPosition]?)] = []
        for (index, observation) in observations.enumerated() {
            guard observation.confidence >= minConfidence,
                  let rect = computeFullBodyBoundingBox(from: observation) else { continue }
            let joints = extractPoseJoints(from: observation)
            detectionBoxes.append((index, rect, observation, joints))
        }

        // Predict positions based on velocity
        // Predict where each known person should be based on velocity (synced with iOS: 60 frames = 2s at 30fps)
        var predictedPositions: [Int: CGRect] = [:]
        for (personIndex, lastRect) in lastKnownBoxes {
            let framesSinceLastSeen = currentFrameNumber - (lastFrameNumbers[personIndex] ?? currentFrameNumber)
            if framesSinceLastSeen < 60 {
                if let velocity = velocities[personIndex] {
                    let predictedCenterX = lastRect.midX + velocity.x * CGFloat(framesSinceLastSeen)
                    let predictedCenterY = lastRect.midY + velocity.y * CGFloat(framesSinceLastSeen)
                    let predictedRect = CGRect(
                        x: predictedCenterX - lastRect.width / 2,
                        y: predictedCenterY - lastRect.height / 2,
                        width: lastRect.width,
                        height: lastRect.height
                    )
                    predictedPositions[personIndex] = predictedRect
                } else {
                    predictedPositions[personIndex] = lastRect
                }
            }
        }

        // Cost matrix assignment (synced with iOS: 0.4 IoU + 0.6 distance weighting)
        let knownPersonIds = Array(predictedPositions.keys).sorted()
        var costMatrix: [[Double]] = []

        for detection in detectionBoxes {
            var rowCosts: [Double] = []
            for personId in knownPersonIds {
                guard let predictedRect = predictedPositions[personId] else {
                    rowCosts.append(Double.infinity)
                    continue
                }

                let overlap = iou(detection.rect, predictedRect)
                let lastRect = lastKnownBoxes[personId]!
                let currentCenter = CGPoint(x: detection.rect.midX, y: detection.rect.midY)
                let predictedCenter = CGPoint(x: predictedRect.midX, y: predictedRect.midY)
                let distance = hypot(currentCenter.x - predictedCenter.x, currentCenter.y - predictedCenter.y)

                let lastCenter = CGPoint(x: lastRect.midX, y: lastRect.midY)
                let distanceToLast = hypot(currentCenter.x - lastCenter.x, currentCenter.y - lastCenter.y)
                let effectiveDistance = min(distance, distanceToLast)

                let iouCost = 1.0 - Double(overlap)
                let distCost = min(Double(effectiveDistance), 1.0)
                let cost = iouCost * 0.4 + distCost * 0.6

                // Synced with iOS: reject if both IoU too low AND too far
                if overlap < CGFloat(reidentificationIoUThreshold) && effectiveDistance > maxCenterDistance {
                    rowCosts.append(Double.infinity)
                } else {
                    rowCosts.append(cost)
                }
            }
            costMatrix.append(rowCosts)
        }

        // Greedy assignment
        var usedPersonIds: Set<Int> = []
        var usedDetections: Set<Int> = []
        var assignments: [(detectionIdx: Int, personId: Int)] = []

        for _ in 0..<min(detectionBoxes.count, knownPersonIds.count) {
            var bestCost = Double.infinity
            var bestDetection = -1
            var bestPerson = -1

            for (detIdx, _) in detectionBoxes.enumerated() {
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

            if bestCost < Double.infinity && bestDetection >= 0 && bestPerson >= 0 {
                assignments.append((bestDetection, bestPerson))
                usedDetections.insert(bestDetection)
                usedPersonIds.insert(bestPerson)
            } else {
                break
            }
        }

        // Build results
        var results: [TrackedPerson] = []

        // Process matched detections
        for (detIdx, personId) in assignments {
            let detection = detectionBoxes[detIdx]

            // Update velocity
            if let lastRect = lastKnownBoxes[personId],
               let lastFrame = lastFrameNumbers[personId] {
                let framesDelta = max(1, currentFrameNumber - lastFrame)
                let newVelocity = CGPoint(
                    x: (detection.rect.midX - lastRect.midX) / CGFloat(framesDelta),
                    y: (detection.rect.midY - lastRect.midY) / CGFloat(framesDelta)
                )

                if let oldVelocity = velocities[personId] {
                    velocities[personId] = CGPoint(
                        x: oldVelocity.x * velocitySmoothing + newVelocity.x * (1 - velocitySmoothing),
                        y: oldVelocity.y * velocitySmoothing + newVelocity.y * (1 - velocitySmoothing)
                    )
                } else {
                    velocities[personId] = newVelocity
                }
            }

            lastKnownBoxes[personId] = detection.rect
            lastFrameNumbers[personId] = currentFrameNumber

            let bbox = convertToNormalized(visionRect: detection.rect)
            results.append(TrackedPerson(
                personIndex: personId,
                confidence: detection.observation.confidence,
                boundingBox: bbox,
                joints: detection.joints
            ))
        }

        // Process unmatched detections as new persons
        for (detIdx, detection) in detectionBoxes.enumerated() {
            guard !usedDetections.contains(detIdx) else { continue }

            let personId = nextPersonIndex
            nextPersonIndex += 1

            lastKnownBoxes[personId] = detection.rect
            lastFrameNumbers[personId] = currentFrameNumber

            let bbox = convertToNormalized(visionRect: detection.rect)
            results.append(TrackedPerson(
                personIndex: personId,
                confidence: detection.observation.confidence,
                boundingBox: bbox,
                joints: detection.joints
            ))
        }

        return results
    }

    private func computeFullBodyBoundingBox(from observation: VNHumanBodyPoseObservation) -> CGRect? {
        guard let allPoints = try? observation.recognizedPoints(.all) else {
            return nil
        }

        let importantJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftEye, .rightEye, .leftEar, .rightEar,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]

        var minX: CGFloat = 1.0
        var maxX: CGFloat = 0.0
        var minY: CGFloat = 1.0
        var maxY: CGFloat = 0.0
        var validPointCount = 0

        // Lower confidence threshold to 0.05 for fast motion
        for joint in importantJoints {
            guard let point = allPoints[joint],
                  point.confidence > 0.05 else { continue }

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

        // Asymmetric padding for head top, feet, and lateral arm motion
        let headMargin = height * 0.12
        let footMargin = height * 0.08
        let lateralPadding = width * 0.15

        let finalMinX = max(0, minX - lateralPadding)
        let finalMaxX = min(1, maxX + lateralPadding)
        let finalMinY = max(0, minY - footMargin)
        let finalMaxY = min(1, maxY + headMargin)

        return CGRect(
            x: finalMinX,
            y: finalMinY,
            width: finalMaxX - finalMinX,
            height: finalMaxY - finalMinY
        )
    }

    /// Extract skeleton joint positions from a pose observation (matching iOS BoundingBoxTracker).
    /// Flips Y coordinate from Vision's bottom-left to web's top-left origin.
    private func extractPoseJoints(from observation: VNHumanBodyPoseObservation) -> [String: JointPosition]? {
        guard let allPoints = try? observation.recognizedPoints(.all) else {
            return nil
        }

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

        var joints: [String: JointPosition] = [:]
        for (jointName, stringKey) in jointMapping {
            guard let point = allPoints[jointName],
                  point.confidence > 0.05 else { continue }
            // Flip Y: Vision uses bottom-left origin, web uses top-left
            joints[stringKey] = JointPosition(
                x: point.location.x,
                y: 1.0 - point.location.y,
                confidence: point.confidence
            )
        }

        return joints.isEmpty ? nil : joints
    }

    private func performRectangleDetection(cgImage: CGImage) throws -> [TrackedPerson] {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        var results: [TrackedPerson] = []

        for observation in observations {
            let personIndex = nextPersonIndex
            nextPersonIndex += 1

            let visionRect = observation.boundingBox
            lastKnownBoxes[personIndex] = visionRect
            lastFrameNumbers[personIndex] = currentFrameNumber

            let bbox = convertToNormalized(visionRect: visionRect)
            results.append(TrackedPerson(
                personIndex: personIndex,
                confidence: observation.confidence,
                boundingBox: bbox,
                joints: nil  // Rectangle detection has no skeleton data
            ))
        }

        return results
    }

    func convertToNormalized(visionRect: CGRect) -> BoundingBox {
        // Vision uses bottom-left origin, convert to center-based coordinates
        return BoundingBox(
            x: visionRect.midX,
            y: 1.0 - visionRect.midY,  // Flip Y for web coordinates
            width: visionRect.width,
            height: visionRect.height
        )
    }

    func iou(_ rect1: CGRect, _ rect2: CGRect) -> CGFloat {
        let intersection = rect1.intersection(rect2)
        if intersection.isNull { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = rect1.width * rect1.height + rect2.width * rect2.height - intersectionArea

        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}

// MARK: - Detection Extractor (No Tracking - Just Vision)

class DetectionExtractor {
    private let boundingBoxPadding: CGFloat = 0.1
    private let minConfidence: Float = 0.3

    /// Extract raw detections from a single frame (no tracking logic)
    func extractDetections(from cgImage: CGImage) throws -> [RawPoseDetection] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        var detections: [RawPoseDetection] = []

        for observation in observations {
            guard observation.confidence >= minConfidence,
                  let allPoints = try? observation.recognizedPoints(.all),
                  let bbox = computeBoundingBox(from: allPoints) else { continue }

            // Extract joint positions using human-readable names (matching iOS BoundingBoxTracker)
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
            var joints: [String: JointPosition] = [:]
            for (visionKey, stringKey) in jointMapping {
                guard let point = allPoints[visionKey], point.confidence > 0.05 else { continue }
                joints[stringKey] = JointPosition(
                    x: point.location.x,
                    y: point.location.y,
                    confidence: point.confidence
                )
            }

            detections.append(RawPoseDetection(
                boundingBox: bbox,
                confidence: observation.confidence,
                joints: joints
            ))
        }

        return detections
    }

    private func computeBoundingBox(from allPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> BoundingBox? {
        let importantJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .leftEye, .rightEye, .leftEar, .rightEar,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle
        ]

        var minX: CGFloat = 1.0
        var maxX: CGFloat = 0.0
        var minY: CGFloat = 1.0
        var maxY: CGFloat = 0.0
        var validPointCount = 0

        // Lower confidence threshold to 0.05 to catch extremities during fast motion
        for joint in importantJoints {
            guard let point = allPoints[joint], point.confidence > 0.05 else { continue }
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

        // Asymmetric padding: body extends beyond detected joints
        // - Head top is ~30% of head height above nose/ears
        // - Feet extend ~15% below ankles
        // - Hands/elbows need lateral margin for motion
        let headMargin = height * 0.12   // Extra space above for head top
        let footMargin = height * 0.08   // Extra space below for feet
        let lateralPadding = width * 0.15 // Lateral padding for arms in motion

        let finalMinX = max(0, minX - lateralPadding)
        let finalMaxX = min(1, maxX + lateralPadding)
        let finalMinY = max(0, minY - footMargin)   // Vision Y: bottom=0, so foot margin goes down
        let finalMaxY = min(1, maxY + headMargin)    // Head margin goes up

        let finalWidth = finalMaxX - finalMinX
        let finalHeight = finalMaxY - finalMinY

        return BoundingBox(
            x: finalMinX + finalWidth / 2,  // Center X
            y: 1.0 - (finalMinY + finalHeight / 2),  // Center Y (flipped for web)
            width: finalWidth,
            height: finalHeight
        )
    }
}

// MARK: - Detection Cache Manager

class DetectionCacheManager {
    private let cacheDir: URL

    init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDir = paths[0].appendingPathComponent("TrackingTesterCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func cacheKey(for videoPath: String, stride: Int) -> String {
        let hash = videoPath.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .prefix(50)
        return "detections_\(hash)_stride\(stride).json"
    }

    func loadCache(for videoPath: String, stride: Int) -> DetectionCache? {
        let key = cacheKey(for: videoPath, stride: stride)
        let cacheFile = cacheDir.appendingPathComponent(key)

        guard let data = try? Data(contentsOf: cacheFile),
              let cache = try? JSONDecoder().decode(DetectionCache.self, from: data) else {
            return nil
        }

        // Validate cache is for the same video
        if cache.videoPath == videoPath && cache.stride == stride {
            return cache
        }
        return nil
    }

    func saveCache(_ cache: DetectionCache) {
        let key = cacheKey(for: cache.videoPath, stride: cache.stride)
        let cacheFile = cacheDir.appendingPathComponent(key)

        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFile)
            print("Cache saved: \(cacheFile.lastPathComponent) (\(data.count / 1024) KB)")
        }
    }
}

// MARK: - Video Analyzer

class VideoAnalyzer {
    private let tracker = BoxTracker()

    func analyzeVideo(at path: String, frameStride: Int = 1, progressCallback: @escaping (Double) -> Void) async throws -> VideoAnalysisResult {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }

        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        tracker.reset()

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        let totalSeconds = duration.seconds
        let fps = Double(nominalFrameRate)
        let totalFrames = Int(totalSeconds * fps)
        let framesToProcess = totalFrames / frameStride

        var frameResults: [FrameResult] = []

        for frameIndex in Swift.stride(from: 0, to: totalFrames, by: frameStride) {
            let time = CMTime(seconds: Double(frameIndex) / fps, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await imageGenerator.image(at: time)
                let people = try tracker.analyze(cgImage: cgImage)

                let result = FrameResult(
                    frameNumber: frameIndex,
                    timestampMs: Int64(time.seconds * 1000),
                    people: people
                )
                frameResults.append(result)

                // Report progress
                let progress = Double(frameIndex) / Double(totalFrames)
                progressCallback(progress)

            } catch {
                print("Error at frame \(frameIndex): \(error)")
            }
        }

        progressCallback(1.0)

        return VideoAnalysisResult(
            totalFrames: framesToProcess,
            duration: totalSeconds,
            fps: fps,
            frames: frameResults
        )
    }

    // MARK: - Cached Detection Flow

    private let extractor = DetectionExtractor()
    private let cacheManager = DetectionCacheManager()

    /// Extract raw detections and cache them (slow - Vision inference)
    func extractAndCacheDetections(at path: String, frameStride: Int = 1, progressCallback: @escaping (Double) -> Void) async throws -> DetectionCache {
        // Check if cache exists
        if let cached = cacheManager.loadCache(for: path, stride: frameStride) {
            print("Using cached detections (\(cached.frames.count) frames)")
            progressCallback(1.0)
            return cached
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }

        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        let totalSeconds = duration.seconds
        let fps = Double(nominalFrameRate)
        let totalFrames = Int(totalSeconds * fps)

        var rawFrames: [RawFrameDetections] = []

        for frameIndex in Swift.stride(from: 0, to: totalFrames, by: frameStride) {
            let time = CMTime(seconds: Double(frameIndex) / fps, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await imageGenerator.image(at: time)
                let detections = try extractor.extractDetections(from: cgImage)

                rawFrames.append(RawFrameDetections(
                    frameNumber: frameIndex,
                    timestampMs: Int64(time.seconds * 1000),
                    detections: detections
                ))

                let progress = Double(frameIndex) / Double(totalFrames)
                progressCallback(progress)

            } catch {
                print("Error at frame \(frameIndex): \(error)")
            }
        }

        progressCallback(1.0)

        let cache = DetectionCache(
            videoPath: path,
            videoDuration: totalSeconds,
            fps: fps,
            totalFrames: totalFrames / frameStride,
            stride: frameStride,
            createdAt: Date(),
            frames: rawFrames
        )

        cacheManager.saveCache(cache)
        return cache
    }

    /// Run tracking algorithm on cached detections (fast - no Vision inference)
    func runTrackingOnCache(_ cache: DetectionCache) -> VideoAnalysisResult {
        tracker.reset()

        var frameResults: [FrameResult] = []

        for rawFrame in cache.frames {
            let people = tracker.trackFromDetections(rawFrame.detections)
            frameResults.append(FrameResult(
                frameNumber: rawFrame.frameNumber,
                timestampMs: rawFrame.timestampMs,
                people: people
            ))
        }

        // Post-processing Phase 0: RTS backward smoothing (synced with iOS TrackingService)
        // Eliminates systematic lag from forward-only Kalman filtering during fast movements
        frameResults = applyRTSSmoothing(frameResults, fps: cache.fps)

        // Post-processing step 1: smooth bounding boxes (prevent sudden shrinkage)
        frameResults = smoothBoundingBoxes(frameResults)

        // Post-processing step 2: merge duplicate tracks
        frameResults = mergeTracksPostProcessing(frameResults)

        // Post-processing step 3: filter out noise tracks
        // Tracks shorter than minTrackFrames are likely false positives
        frameResults = filterNoiseTracks(frameResults, fps: cache.fps)

        return VideoAnalysisResult(
            totalFrames: cache.totalFrames,
            duration: cache.videoDuration,
            fps: cache.fps,
            frames: frameResults
        )
    }

    // MARK: - RTS Backward Smoothing (Ported from iOS KalmanFilter2D)

    /// Apply Rauch-Tung-Striebel backward smoother to tracked positions.
    /// Uses all data (past + future) to produce minimum-variance position estimates,
    /// eliminating systematic lag during fast movements.
    private func applyRTSSmoothing(_ frames: [FrameResult], fps: Double) -> [FrameResult] {
        let dt = 1.0 / fps

        // Collect per-person position timeseries
        struct PositionEntry {
            let frameIdx: Int
            let x: Double
            let y: Double
        }

        var personPositions: [Int: [PositionEntry]] = [:]
        for (frameIdx, frame) in frames.enumerated() {
            for person in frame.people {
                personPositions[person.personIndex, default: []].append(
                    PositionEntry(frameIdx: frameIdx, x: person.boundingBox.x, y: person.boundingBox.y)
                )
            }
        }

        // Run forward Kalman + backward RTS for each person
        var smoothedPositions: [Int: [Int: (x: Double, y: Double)]] = [:]  // personId -> frameIdx -> (x, y)

        for (personId, positions) in personPositions {
            guard positions.count > 2 else { continue }

            // Forward pass: run Kalman filter and collect snapshots
            let processNoise = 0.01
            let measurementNoise = 0.1
            var state: [Double] = [positions[0].x, positions[0].y, 0, 0]
            var P: [[Double]] = [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
            var adaptiveQ = processNoise
            var snapshots: [(state: [Double], P: [[Double]], q: Double)] = []

            // First frame snapshot
            snapshots.append((state: state, P: P, q: adaptiveQ))

            for i in 1..<positions.count {
                let measurement = (positions[i].x, positions[i].y)

                // Predict
                let F = rtsStateTransition(dt: dt)
                state = rtsMatVecMul(F, state)
                let Q = rtsProcessNoise(q: adaptiveQ, dt: dt)
                P = rtsMatAdd(rtsMatMul(rtsMatMul(F, P), rtsTranspose(F)), Q)

                // Innovation (residual)
                let innovX = measurement.0 - state[0]
                let innovY = measurement.1 - state[1]
                let innovMag = sqrt(innovX * innovX + innovY * innovY)

                // Adaptive process noise (synced with iOS KalmanFilter2D)
                if innovMag > 0.05 {
                    let scale = min(50.0, 1.0 + pow(innovMag / 0.05, 2))
                    adaptiveQ = processNoise * scale
                } else {
                    adaptiveQ = adaptiveQ * 0.8 + processNoise * 0.2
                }

                // Correct
                let H: [[Double]] = [[1,0,0,0],[0,1,0,0]]
                let z = [measurement.0, measurement.1]
                let Hx = [state[0], state[1]]
                let y = [z[0] - Hx[0], z[1] - Hx[1]]
                let R: [[Double]] = [[measurementNoise, 0], [0, measurementNoise]]
                let Ht = rtsTranspose(H)
                let S = rtsMatAdd(rtsMatMul(rtsMatMul(H, P), Ht), R)
                let Sinv = rtsInverse2x2(S)
                let K = rtsMatMul(rtsMatMul(P, Ht), Sinv)
                let Ky = rtsMatVecMul(K, y)
                for j in 0..<4 { state[j] += Ky[j] }
                let KH = rtsMatMul(K, H)
                let I = rtsIdentity(4)
                let IminusKH = rtsMatSub(I, KH)
                P = rtsMatMul(IminusKH, P)

                snapshots.append((state: state, P: P, q: adaptiveQ))
            }

            // Backward pass: RTS smoother
            let n = snapshots.count
            var smoothedStates: [[Double]] = Array(repeating: [0,0,0,0], count: n)
            smoothedStates[n - 1] = snapshots[n - 1].state

            let F = rtsStateTransition(dt: dt)
            let Ft = rtsTranspose(F)

            for k in stride(from: n - 2, through: 0, by: -1) {
                let xk = snapshots[k].state
                let Pk = snapshots[k].P
                let qk = snapshots[k].q

                let xk1_pred = rtsMatVecMul(F, xk)
                let Qk = rtsProcessNoise(q: qk, dt: dt)
                let Pk1_pred = rtsMatAdd(rtsMatMul(rtsMatMul(F, Pk), Ft), Qk)

                // Regularize
                var Pk1_reg = Pk1_pred
                for i in 0..<4 { Pk1_reg[i][i] += 1e-10 }

                let PkFt = rtsMatMul(Pk, Ft)
                let Pk1_inv = rtsInverse4x4(Pk1_reg)
                let G = rtsMatMul(PkFt, Pk1_inv)

                let diff = rtsVecSub(smoothedStates[k + 1], xk1_pred)
                let correction = rtsMatVecMul(G, diff)
                smoothedStates[k] = rtsVecAdd(xk, correction)
            }

            // Store smoothed positions indexed by frame
            var posMap: [Int: (x: Double, y: Double)] = [:]
            for (i, pos) in positions.enumerated() {
                posMap[pos.frameIdx] = (smoothedStates[i][0], smoothedStates[i][1])
            }
            smoothedPositions[personId] = posMap
        }

        // Apply smoothed positions back to frames
        return frames.enumerated().map { (frameIdx, frame) in
            let smoothedPeople = frame.people.map { person -> TrackedPerson in
                if let smoothed = smoothedPositions[person.personIndex]?[frameIdx] {
                    let bb = person.boundingBox
                    let smoothedBB = BoundingBox(
                        x: max(bb.width/2, min(smoothed.x, 1.0 - bb.width/2)),
                        y: max(bb.height/2, min(smoothed.y, 1.0 - bb.height/2)),
                        width: bb.width,
                        height: bb.height
                    )
                    return TrackedPerson(
                        personIndex: person.personIndex,
                        confidence: person.confidence,
                        boundingBox: smoothedBB,
                        joints: person.joints
                    )
                }
                return person
            }
            return FrameResult(frameNumber: frame.frameNumber, timestampMs: frame.timestampMs, people: smoothedPeople)
        }
    }

    // MARK: - RTS Matrix Helpers

    private func rtsStateTransition(dt: Double) -> [[Double]] {
        [[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]]
    }

    private func rtsProcessNoise(q: Double, dt: Double) -> [[Double]] {
        let dt2 = dt * dt
        let dt3 = dt2 * dt / 2
        let dt4 = dt2 * dt2 / 4
        return [
            [dt4*q, 0, dt3*q, 0],
            [0, dt4*q, 0, dt3*q],
            [dt3*q, 0, dt2*q, 0],
            [0, dt3*q, 0, dt2*q]
        ]
    }

    private func rtsIdentity(_ n: Int) -> [[Double]] {
        var I = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n { I[i][i] = 1.0 }
        return I
    }

    private func rtsTranspose(_ m: [[Double]]) -> [[Double]] {
        guard !m.isEmpty else { return m }
        let rows = m.count, cols = m[0].count
        var r = Array(repeating: Array(repeating: 0.0, count: rows), count: cols)
        for i in 0..<rows { for j in 0..<cols { r[j][i] = m[i][j] } }
        return r
    }

    private func rtsMatMul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        let rowsA = a.count, colsA = a[0].count, colsB = b[0].count
        var r = Array(repeating: Array(repeating: 0.0, count: colsB), count: rowsA)
        for i in 0..<rowsA { for j in 0..<colsB { for k in 0..<colsA { r[i][j] += a[i][k] * b[k][j] } } }
        return r
    }

    private func rtsMatVecMul(_ m: [[Double]], _ v: [Double]) -> [Double] {
        m.map { row in zip(row, v).map(*).reduce(0, +) }
    }

    private func rtsMatAdd(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var r = a
        for i in 0..<a.count { for j in 0..<a[0].count { r[i][j] += b[i][j] } }
        return r
    }

    private func rtsMatSub(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        var r = a
        for i in 0..<a.count { for j in 0..<a[0].count { r[i][j] -= b[i][j] } }
        return r
    }

    private func rtsVecAdd(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map(+)
    }

    private func rtsVecSub(_ a: [Double], _ b: [Double]) -> [Double] {
        zip(a, b).map(-)
    }

    private func rtsInverse2x2(_ m: [[Double]]) -> [[Double]] {
        let det = m[0][0] * m[1][1] - m[0][1] * m[1][0]
        guard abs(det) > 1e-15 else { return m }
        return [[m[1][1]/det, -m[0][1]/det], [-m[1][0]/det, m[0][0]/det]]
    }

    private func rtsInverse4x4(_ m: [[Double]]) -> [[Double]] {
        let s0 = m[0][0]*m[1][1] - m[1][0]*m[0][1]
        let s1 = m[0][0]*m[1][2] - m[1][0]*m[0][2]
        let s2 = m[0][0]*m[1][3] - m[1][0]*m[0][3]
        let s3 = m[0][1]*m[1][2] - m[1][1]*m[0][2]
        let s4 = m[0][1]*m[1][3] - m[1][1]*m[0][3]
        let s5 = m[0][2]*m[1][3] - m[1][2]*m[0][3]
        let c5 = m[2][2]*m[3][3] - m[3][2]*m[2][3]
        let c4 = m[2][1]*m[3][3] - m[3][1]*m[2][3]
        let c3 = m[2][1]*m[3][2] - m[3][1]*m[2][2]
        let c2 = m[2][0]*m[3][3] - m[3][0]*m[2][3]
        let c1 = m[2][0]*m[3][2] - m[3][0]*m[2][2]
        let c0 = m[2][0]*m[3][1] - m[3][0]*m[2][1]
        let det = s0*c5 - s1*c4 + s2*c3 + s3*c2 - s4*c1 + s5*c0
        guard abs(det) > 1e-15 else { return rtsIdentity(4) }
        let inv = 1.0 / det
        return [
            [( m[1][1]*c5 - m[1][2]*c4 + m[1][3]*c3)*inv, (-m[0][1]*c5 + m[0][2]*c4 - m[0][3]*c3)*inv,
             ( m[3][1]*s5 - m[3][2]*s4 + m[3][3]*s3)*inv, (-m[2][1]*s5 + m[2][2]*s4 - m[2][3]*s3)*inv],
            [(-m[1][0]*c5 + m[1][2]*c2 - m[1][3]*c1)*inv, ( m[0][0]*c5 - m[0][2]*c2 + m[0][3]*c1)*inv,
             (-m[3][0]*s5 + m[3][2]*s2 - m[3][3]*s1)*inv, ( m[2][0]*s5 - m[2][2]*s2 + m[2][3]*s1)*inv],
            [( m[1][0]*c4 - m[1][1]*c2 + m[1][3]*c0)*inv, (-m[0][0]*c4 + m[0][1]*c2 - m[0][3]*c0)*inv,
             ( m[3][0]*s4 - m[3][1]*s2 + m[3][3]*s0)*inv, (-m[2][0]*s4 + m[2][1]*s2 - m[2][3]*s0)*inv],
            [(-m[1][0]*c3 + m[1][1]*c1 - m[1][2]*c0)*inv, ( m[0][0]*c3 - m[0][1]*c1 + m[0][2]*c0)*inv,
             (-m[3][0]*s3 + m[3][1]*s1 - m[3][2]*s0)*inv, ( m[2][0]*s3 - m[2][1]*s1 + m[2][2]*s0)*inv],
        ]
    }

    /// Temporal bounding box smoothing: prevent sudden bbox shrinkage during fast motion.
    /// Two mechanisms:
    /// 1. Running average enforcement: bbox must be >= 55% of running average size
    /// 2. Hard minimum size floor: a detected human must be at least a minimum bbox size
    /// This handles cases where Vision detects fewer joints during motion blur.
    private func smoothBoundingBoxes(_ frames: [FrameResult]) -> [FrameResult] {
        // Track running average width/height per person
        var avgWidth: [Int: Double] = [:]
        var avgHeight: [Int: Double] = [:]
        var frameCount: [Int: Int] = [:]  // Frames seen per person
        let smoothingAlpha = 0.1   // Slow adaptation for stability
        let minRatio = 0.55        // Bbox must be at least 55% of running average

        // Hard minimum size floor: if body pose is detected, person must be at least this big
        // A person far away is at least 4% wide and 12% tall in frame
        let hardMinWidth = 0.04
        let hardMinHeight = 0.12

        // First pass: compute per-person median size (robust initial estimate)
        var personWidths: [Int: [Double]] = [:]
        var personHeights: [Int: [Double]] = [:]
        for frame in frames {
            for person in frame.people {
                personWidths[person.personIndex, default: []].append(person.boundingBox.width)
                personHeights[person.personIndex, default: []].append(person.boundingBox.height)
            }
        }
        var medianWidth: [Int: Double] = [:]
        var medianHeight: [Int: Double] = [:]
        for (pid, widths) in personWidths {
            let sorted = widths.sorted()
            medianWidth[pid] = sorted[sorted.count / 2]
        }
        for (pid, heights) in personHeights {
            let sorted = heights.sorted()
            medianHeight[pid] = sorted[sorted.count / 2]
        }

        var smoothedFrames: [FrameResult] = []

        for frame in frames {
            var smoothedPeople: [TrackedPerson] = []

            for person in frame.people {
                let pid = person.personIndex
                let bb = person.boundingBox
                let count = frameCount[pid, default: 0]

                var newW = bb.width
                var newH = bb.height

                // Hard minimum floor
                if newW < hardMinWidth { newW = hardMinWidth }
                if newH < hardMinHeight { newH = hardMinHeight }

                if count >= 5, let runningW = avgWidth[pid], let runningH = avgHeight[pid] {
                    // After 5 frames, enforce running average minimum
                    let minW = runningW * minRatio
                    let minH = runningH * minRatio

                    if newW < minW { newW = minW }
                    if newH < minH { newH = minH }

                    // Update running average (use actual detection, not smoothed)
                    avgWidth[pid] = runningW * (1 - smoothingAlpha) + bb.width * smoothingAlpha
                    avgHeight[pid] = runningH * (1 - smoothingAlpha) + bb.height * smoothingAlpha
                } else if count < 5 {
                    // First 5 frames: use median as initial estimate for the running average
                    // This prevents the average from being seeded with a tiny initial detection
                    let seedW = medianWidth[pid] ?? bb.width
                    let seedH = medianHeight[pid] ?? bb.height
                    if count == 0 {
                        avgWidth[pid] = seedW
                        avgHeight[pid] = seedH
                    } else {
                        avgWidth[pid] = (avgWidth[pid]! * Double(count) + bb.width) / Double(count + 1)
                        avgHeight[pid] = (avgHeight[pid]! * Double(count) + bb.height) / Double(count + 1)
                    }

                    // Even in early frames, don't let bbox be less than 40% of median
                    let earlyMinW = seedW * 0.4
                    let earlyMinH = seedH * 0.4
                    if newW < earlyMinW { newW = earlyMinW }
                    if newH < earlyMinH { newH = earlyMinH }
                }

                frameCount[pid] = count + 1

                // Clamp to valid range
                let clampedW = min(newW, 1.0)
                let clampedH = min(newH, 1.0)
                let clampedX = max(clampedW / 2, min(bb.x, 1.0 - clampedW / 2))
                let clampedY = max(clampedH / 2, min(bb.y, 1.0 - clampedH / 2))

                let smoothedBB = BoundingBox(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
                smoothedPeople.append(TrackedPerson(
                    personIndex: pid,
                    confidence: person.confidence,
                    boundingBox: smoothedBB,
                    joints: person.joints
                ))
            }

            smoothedFrames.append(FrameResult(
                frameNumber: frame.frameNumber,
                timestampMs: frame.timestampMs,
                people: smoothedPeople
            ))
        }

        return smoothedFrames
    }

    /// Remove tracks that are too short to be real people.
    /// Threshold: must appear for at least 1 second (fps frames) or 30 frames, whichever is smaller.
    private func filterNoiseTracks(_ frames: [FrameResult], fps: Double) -> [FrameResult] {
        // Count frames per track
        var trackFrameCounts: [Int: Int] = [:]
        for frame in frames {
            for person in frame.people {
                trackFrameCounts[person.personIndex, default: 0] += 1
            }
        }

        // Minimum: 1 second worth of frames, but at least 15 frames
        let minFrames = max(15, Int(fps))
        let tracksToRemove = trackFrameCounts.filter { $0.value < minFrames }.map { $0.key }

        if !tracksToRemove.isEmpty {
            print("Filtering \(tracksToRemove.count) noise tracks (< \(minFrames) frames): \(tracksToRemove.sorted())")
        }

        guard !tracksToRemove.isEmpty else { return frames }

        let removeSet = Set(tracksToRemove)

        // Remove noise tracks and remap remaining IDs to contiguous
        let validIds = trackFrameCounts.keys.filter { !removeSet.contains($0) }.sorted()
        var remapToContiguous: [Int: Int] = [:]
        for (newIdx, oldId) in validIds.enumerated() {
            remapToContiguous[oldId] = newIdx
        }

        return frames.map { frame in
            let filtered = frame.people
                .filter { !removeSet.contains($0.personIndex) }
                .map { person in
                    TrackedPerson(
                        personIndex: remapToContiguous[person.personIndex] ?? person.personIndex,
                        confidence: person.confidence,
                        boundingBox: person.boundingBox,
                        joints: person.joints
                    )
                }
            return FrameResult(
                frameNumber: frame.frameNumber,
                timestampMs: frame.timestampMs,
                people: filtered
            )
        }
    }

    /// Post-processing: merge tracks that are likely the same person.
    /// Uses size-relative spatial thresholds, strict temporal overlap checks,
    /// and bbox similarity to work across any video content.
    private func mergeTracksPostProcessing(_ frames: [FrameResult]) -> [FrameResult] {
        struct TrackInfo {
            var firstFrameIdx: Int
            var lastFrameIdx: Int
            var firstPosition: CGPoint
            var lastPosition: CGPoint
            var firstBBox: BoundingBox
            var lastBBox: BoundingBox
            var avgBBoxWidth: Double
            var avgBBoxHeight: Double
            var frameCount: Int
            var frameIndices: Set<Int>  // All frame indices where this track appears
        }

        var trackInfos: [Int: TrackInfo] = [:]

        for (frameIdx, frame) in frames.enumerated() {
            for person in frame.people {
                let center = CGPoint(x: person.boundingBox.x, y: person.boundingBox.y)
                if var info = trackInfos[person.personIndex] {
                    info.lastFrameIdx = frameIdx
                    info.lastPosition = center
                    info.lastBBox = person.boundingBox
                    // Running average of bbox size
                    let n = Double(info.frameCount)
                    info.avgBBoxWidth = (info.avgBBoxWidth * n + person.boundingBox.width) / (n + 1)
                    info.avgBBoxHeight = (info.avgBBoxHeight * n + person.boundingBox.height) / (n + 1)
                    info.frameCount += 1
                    info.frameIndices.insert(frameIdx)
                    trackInfos[person.personIndex] = info
                } else {
                    trackInfos[person.personIndex] = TrackInfo(
                        firstFrameIdx: frameIdx,
                        lastFrameIdx: frameIdx,
                        firstPosition: center,
                        lastPosition: center,
                        firstBBox: person.boundingBox,
                        lastBBox: person.boundingBox,
                        avgBBoxWidth: person.boundingBox.width,
                        avgBBoxHeight: person.boundingBox.height,
                        frameCount: 1,
                        frameIndices: [frameIdx]
                    )
                }
            }
        }

        let allTrackIds = trackInfos.keys.sorted()
        print("Pre-merge: \(allTrackIds.count) unique tracks: \(allTrackIds)")
        for tid in allTrackIds {
            let info = trackInfos[tid]!
            print("  Track \(tid): frames=\(info.frameCount), range=\(info.firstFrameIdx)-\(info.lastFrameIdx), avgSize=(\(String(format: "%.3f", info.avgBBoxWidth))x\(String(format: "%.3f", info.avgBBoxHeight)))")
        }

        var mergeMap: [Int: Int] = [:]

        // Sort tracks by frame count descending - merge short tracks into long ones
        let sortedByLength = allTrackIds.sorted { trackInfos[$0]!.frameCount > trackInfos[$1]!.frameCount }

        for i in 0..<sortedByLength.count {
            let candidateId = sortedByLength[i]
            guard mergeMap[candidateId] == nil else { continue }
            let candidateInfo = trackInfos[candidateId]!

            var bestMergeTarget: Int? = nil
            var bestMergeScore: Double = Double.infinity

            for j in 0..<sortedByLength.count {
                if i == j { continue }
                let targetId = sortedByLength[j]

                // Resolve merge chains
                var resolvedId = targetId
                while let next = mergeMap[resolvedId] { resolvedId = next }
                if resolvedId == candidateId { continue }  // Would create cycle

                let targetInfo = trackInfos[targetId]!

                // 1. STRICT TEMPORAL OVERLAP CHECK
                // Count how many frames both tracks appear in simultaneously
                let overlapCount = candidateInfo.frameIndices.intersection(targetInfo.frameIndices).count
                let overlapRatio = Double(overlapCount) / Double(min(candidateInfo.frameCount, targetInfo.frameCount))
                // If more than 10% of the shorter track overlaps, these are different people
                if overlapRatio > 0.1 { continue }

                // 2. DETERMINE TEMPORAL RELATIONSHIP
                // Which track ends first and which starts after?
                let (earlier, later): (TrackInfo, TrackInfo)
                if candidateInfo.firstFrameIdx <= targetInfo.firstFrameIdx {
                    earlier = candidateInfo
                    later = targetInfo
                } else {
                    earlier = targetInfo
                    later = candidateInfo
                }

                let gapFrames = later.firstFrameIdx - earlier.lastFrameIdx
                // If they overlap significantly (beyond the 10% check above), skip
                if gapFrames < -5 { continue }

                // 3. SIZE-RELATIVE SPATIAL DISTANCE
                // Compute distance at the boundary (where one ends and other starts)
                let boundaryDist = hypot(
                    earlier.lastPosition.x - later.firstPosition.x,
                    earlier.lastPosition.y - later.firstPosition.y
                )

                // Normalize by average bbox diagonal of both tracks
                let earlierDiag = hypot(earlier.avgBBoxWidth, earlier.avgBBoxHeight)
                let laterDiag = hypot(later.avgBBoxWidth, later.avgBBoxHeight)
                let avgDiag = (earlierDiag + laterDiag) / 2

                // Distance in units of "person sizes"
                let normalizedDist = boundaryDist / max(avgDiag, 0.01)

                // 4. BOUNDING BOX SIZE SIMILARITY
                let areaEarlier = earlier.avgBBoxWidth * earlier.avgBBoxHeight
                let areaLater = later.avgBBoxWidth * later.avgBBoxHeight
                let sizeRatio = min(areaEarlier, areaLater) / max(areaEarlier, areaLater)
                // Same person should have similar bbox size (within 3x)
                if sizeRatio < 0.33 { continue }

                // 5. COMPUTE MERGE SCORE
                // Base threshold: within 2.5 person-diagonals at the boundary
                // Tighter for larger gaps (person could have moved elsewhere)
                let maxNormalizedDist = 2.5 - Double(max(0, gapFrames)) * 0.005
                if normalizedDist > max(maxNormalizedDist, 0.5) { continue }

                // Score: lower is better
                let distScore = normalizedDist / 2.5  // [0, 1]
                let sizeScore = 1.0 - sizeRatio        // [0, 1] lower is better
                let gapScore = Double(max(0, gapFrames)) / 300.0  // Penalize large gaps
                let score = distScore * 0.5 + sizeScore * 0.2 + gapScore * 0.3

                if score < bestMergeScore {
                    bestMergeScore = score
                    bestMergeTarget = resolvedId
                }
            }

            if let target = bestMergeTarget {
                // Merge shorter track into longer track
                let targetInfo = trackInfos[target]!
                if candidateInfo.frameCount <= targetInfo.frameCount {
                    mergeMap[candidateId] = target
                } else {
                    mergeMap[target] = candidateId
                }
            }
        }

        // Resolve merge chains
        for trackId in mergeMap.keys {
            var resolvedId = trackId
            var visited: Set<Int> = []
            while let next = mergeMap[resolvedId], !visited.contains(next) {
                visited.insert(resolvedId)
                resolvedId = next
            }
            mergeMap[trackId] = resolvedId
        }

        let finalIds = Set(allTrackIds.map { mergeMap[$0] ?? $0 })
        print("Post-merge: \(finalIds.count) unique tracks (merged \(allTrackIds.count - finalIds.count) duplicates)")
        for (from, to) in mergeMap.sorted(by: { $0.key < $1.key }) {
            print("  Track \(from) -> merged into Track \(to)")
        }

        // Remap to contiguous IDs
        let sortedFinalIds = finalIds.sorted()
        var remapToContiguous: [Int: Int] = [:]
        for (newIdx, oldId) in sortedFinalIds.enumerated() {
            remapToContiguous[oldId] = newIdx
        }

        return frames.map { frame in
            let remappedPeople = frame.people.map { person in
                let mergedId = mergeMap[person.personIndex] ?? person.personIndex
                let finalId = remapToContiguous[mergedId] ?? mergedId
                return TrackedPerson(
                    personIndex: finalId,
                    confidence: person.confidence,
                    boundingBox: person.boundingBox,
                    joints: person.joints
                )
            }
            return FrameResult(
                frameNumber: frame.frameNumber,
                timestampMs: frame.timestampMs,
                people: remappedPeople
            )
        }
    }

    // MARK: - SORT Tracker on Cached Detections

    private let sortTracker = SORTTracker(maxAge: 90, minHits: 3, iouThreshold: 0.1)

    func runSORTTrackingOnCache(_ cache: DetectionCache) -> VideoAnalysisResult {
        sortTracker.reset()

        var frameResults: [FrameResult] = []

        for rawFrame in cache.frames {
            // Convert raw detections to CGRects with joints
            var detectionBoxes: [(rect: CGRect, confidence: Float, joints: [String: JointPosition]?)] = []
            for detection in rawFrame.detections {
                let bbox = detection.boundingBox
                let rect = CGRect(
                    x: bbox.x - bbox.width / 2,
                    y: 1.0 - bbox.y - bbox.height / 2,
                    width: bbox.width,
                    height: bbox.height
                )
                // Convert joint coords to web space (Y flipped)
                var webJoints: [String: JointPosition]? = nil
                if !detection.joints.isEmpty {
                    var converted: [String: JointPosition] = [:]
                    for (key, joint) in detection.joints {
                        converted[key] = JointPosition(x: joint.x, y: 1.0 - joint.y, confidence: joint.confidence)
                    }
                    webJoints = converted
                }
                detectionBoxes.append((rect, detection.confidence, webJoints))
            }

            let people = sortTracker.update(detections: detectionBoxes)

            frameResults.append(FrameResult(
                frameNumber: rawFrame.frameNumber,
                timestampMs: rawFrame.timestampMs,
                people: people
            ))
        }

        // Apply same post-processing: RTS + smooth + merge + noise filter
        frameResults = applyRTSSmoothing(frameResults, fps: cache.fps)
        frameResults = smoothBoundingBoxes(frameResults)
        frameResults = mergeTracksPostProcessing(frameResults)
        frameResults = filterNoiseTracks(frameResults, fps: cache.fps)

        return VideoAnalysisResult(
            totalFrames: cache.totalFrames,
            duration: cache.videoDuration,
            fps: cache.fps,
            frames: frameResults
        )
    }
}

// MARK: - BoxTracker Extension for Cached Detections

extension BoxTracker {
    /// Compute diagonal size of a rect (used for size-relative distance thresholds)
    private func bboxDiagonal(_ rect: CGRect) -> CGFloat {
        return hypot(rect.width, rect.height)
    }

    /// Expand bounding box based on velocity to capture trailing limbs during fast motion.
    /// During fast movement, the body extends in the direction of motion (trailing arms/legs)
    /// and the detection may lag behind the actual body extent.
    private func velocityExpandedBox(_ rect: CGRect, personId: Int) -> CGRect {
        guard let velocity = velocities[personId] else { return rect }

        let speed = hypot(velocity.x, velocity.y)
        // Only expand for significant motion (> 0.5% of frame per frame)
        guard speed > 0.005 else { return rect }

        // Expansion proportional to speed, capped at 30% of bbox dimension
        let expansionFactor = min(speed * 3.0, 0.30)

        // Expand in the direction of motion AND opposite (trailing limbs)
        let expandX = rect.width * expansionFactor
        let expandY = rect.height * expansionFactor

        return CGRect(
            x: max(0, rect.origin.x - expandX / 2),
            y: max(0, rect.origin.y - expandY / 2),
            width: min(1 - max(0, rect.origin.x - expandX / 2), rect.width + expandX),
            height: min(1 - max(0, rect.origin.y - expandY / 2), rect.height + expandY)
        )
    }

    /// Process pre-extracted detections (no Vision calls needed)
    func trackFromDetections(_ detections: [RawPoseDetection]) -> [TrackedPerson] {
        currentFrameNumber += 1

        // Convert RawPoseDetection to the format tracker expects, carrying joints through
        var detectionBoxes: [(rect: CGRect, confidence: Float, joints: [String: JointPosition]?)] = []
        for detection in detections {
            let bbox = detection.boundingBox
            let rect = CGRect(
                x: bbox.x - bbox.width / 2,
                y: 1.0 - bbox.y - bbox.height / 2,  // Flip Y back
                width: bbox.width,
                height: bbox.height
            )
            // Convert joint coordinates: the raw detection joints have Vision coords (Y up)
            // We need web coords (Y down) for the final output
            var webJoints: [String: JointPosition]? = nil
            if !detection.joints.isEmpty {
                var converted: [String: JointPosition] = [:]
                for (key, joint) in detection.joints {
                    converted[key] = JointPosition(x: joint.x, y: 1.0 - joint.y, confidence: joint.confidence)
                }
                webJoints = converted
            }
            detectionBoxes.append((rect, detection.confidence, webJoints))
        }

        // Predict positions based on velocity
        var predictedPositions: [Int: CGRect] = [:]
        for (personIndex, lastRect) in lastKnownBoxes {
            let framesSinceLastSeen = currentFrameNumber - (lastFrameNumbers[personIndex] ?? currentFrameNumber)
            if framesSinceLastSeen < maxFrameGap {
                if let velocity = velocities[personIndex], framesSinceLastSeen < 30 {
                    let predictedCenterX = lastRect.midX + velocity.x * CGFloat(framesSinceLastSeen)
                    let predictedCenterY = lastRect.midY + velocity.y * CGFloat(framesSinceLastSeen)
                    let predictedRect = CGRect(
                        x: predictedCenterX - lastRect.width / 2,
                        y: predictedCenterY - lastRect.height / 2,
                        width: lastRect.width,
                        height: lastRect.height
                    )
                    predictedPositions[personIndex] = predictedRect
                } else {
                    predictedPositions[personIndex] = lastRect
                }
            }
        }

        // Cost matrix: combine distance, IoU, and size similarity
        let knownPersonIds = Array(predictedPositions.keys).sorted()
        var costMatrix: [[Double]] = []

        for detection in detectionBoxes {
            var rowCosts: [Double] = []
            let detDiagonal = bboxDiagonal(detection.rect)

            for personId in knownPersonIds {
                guard let predictedRect = predictedPositions[personId] else {
                    rowCosts.append(Double.infinity)
                    continue
                }

                let overlap = iou(detection.rect, predictedRect)
                let lastRect = lastKnownBoxes[personId]!
                let currentCenter = CGPoint(x: detection.rect.midX, y: detection.rect.midY)
                let predictedCenter = CGPoint(x: predictedRect.midX, y: predictedRect.midY)
                let distance = hypot(currentCenter.x - predictedCenter.x, currentCenter.y - predictedCenter.y)

                let lastCenter = CGPoint(x: lastRect.midX, y: lastRect.midY)
                let distanceToLast = hypot(currentCenter.x - lastCenter.x, currentCenter.y - lastCenter.y)
                let effectiveDistance = min(distance, distanceToLast)

                // Size similarity: ratio of bbox areas (0 = totally different, 1 = identical)
                let detArea = detection.rect.width * detection.rect.height
                let lastArea = lastRect.width * lastRect.height
                let sizeRatio = min(detArea, lastArea) / max(detArea, lastArea)

                // Adaptive distance threshold: scale by bbox size
                // A person's bbox diagonal gives the scale - allow movement up to 2x the diagonal
                let trackDiagonal = trackSizes[personId] ?? bboxDiagonal(lastRect)
                let avgDiagonal = (detDiagonal + trackDiagonal) / 2
                let adaptiveMaxDist = min(maxCenterDistance, avgDiagonal * 3.0)

                if effectiveDistance > adaptiveMaxDist {
                    rowCosts.append(Double.infinity)
                    continue
                }

                // Normalized distance (relative to person size)
                let normalizedDist = Double(effectiveDistance / max(avgDiagonal, 0.01))

                // Cost components
                let iouCost = 1.0 - Double(overlap)
                let distCost = min(normalizedDist / 3.0, 1.0)  // Normalize to [0,1]
                let sizePenalty = (1.0 - Double(sizeRatio)) * 0.3

                let cost = iouCost * 0.25 + distCost * 0.55 + sizePenalty + 0.2 * 0.0
                // 0.25 IoU + 0.55 distance + up to 0.3 size penalty

                if cost > maxAssignmentCost {
                    rowCosts.append(Double.infinity)
                } else {
                    rowCosts.append(cost)
                }
            }
            costMatrix.append(rowCosts)
        }

        // Greedy assignment (lowest cost first)
        var usedPersonIds: Set<Int> = []
        var usedDetections: Set<Int> = []
        var assignments: [(detectionIdx: Int, personId: Int)] = []

        for _ in 0..<min(detectionBoxes.count, knownPersonIds.count) {
            var bestCost = Double.infinity
            var bestDetection = -1
            var bestPerson = -1

            for (detIdx, _) in detectionBoxes.enumerated() {
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

            if bestCost < Double.infinity && bestDetection >= 0 && bestPerson >= 0 {
                assignments.append((bestDetection, bestPerson))
                usedDetections.insert(bestDetection)
                usedPersonIds.insert(bestPerson)
            } else {
                break
            }
        }

        // Build results
        var results: [TrackedPerson] = []

        // Process matched detections
        for (detIdx, personId) in assignments {
            let detection = detectionBoxes[detIdx]

            // Update velocity
            if let lastRect = lastKnownBoxes[personId],
               let lastFrame = lastFrameNumbers[personId] {
                let framesDelta = max(1, currentFrameNumber - lastFrame)
                let newVelocity = CGPoint(
                    x: (detection.rect.midX - lastRect.midX) / CGFloat(framesDelta),
                    y: (detection.rect.midY - lastRect.midY) / CGFloat(framesDelta)
                )

                if let oldVelocity = velocities[personId] {
                    velocities[personId] = CGPoint(
                        x: oldVelocity.x * velocitySmoothing + newVelocity.x * (1 - velocitySmoothing),
                        y: oldVelocity.y * velocitySmoothing + newVelocity.y * (1 - velocitySmoothing)
                    )
                } else {
                    velocities[personId] = newVelocity
                }
            }

            // Update running average bbox size
            let newDiag = bboxDiagonal(detection.rect)
            if let oldSize = trackSizes[personId] {
                trackSizes[personId] = oldSize * 0.8 + newDiag * 0.2
            } else {
                trackSizes[personId] = newDiag
            }

            lastKnownBoxes[personId] = detection.rect
            lastFrameNumbers[personId] = currentFrameNumber

            // Expand bbox based on velocity for fast-moving persons
            let expandedRect = velocityExpandedBox(detection.rect, personId: personId)
            let bbox = convertToNormalized(visionRect: expandedRect)
            results.append(TrackedPerson(
                personIndex: personId,
                confidence: detection.confidence,
                boundingBox: bbox,
                joints: detection.joints
            ))
        }

        // Process unmatched detections as new persons
        for (detIdx, detection) in detectionBoxes.enumerated() {
            guard !usedDetections.contains(detIdx) else { continue }

            let personId = nextPersonIndex
            nextPersonIndex += 1

            lastKnownBoxes[personId] = detection.rect
            lastFrameNumbers[personId] = currentFrameNumber
            firstFrameNumbers[personId] = currentFrameNumber
            trackSizes[personId] = bboxDiagonal(detection.rect)

            let bbox = convertToNormalized(visionRect: detection.rect)
            results.append(TrackedPerson(
                personIndex: personId,
                confidence: detection.confidence,
                boundingBox: bbox,
                joints: detection.joints
            ))
        }

        return results
    }
}

// MARK: - HTTP Server

class HTTPServer {
    private var listener: Task<Void, Never>?
    private let port: UInt16
    private let analyzer = VideoAnalyzer()
    private let webDir: String
    private var currentProgress: Double = 0
    private var isAnalyzing: Bool = false

    init(port: UInt16 = 8080) {
        self.port = port
        // Find the web directory relative to the executable or current directory
        let currentDir = FileManager.default.currentDirectoryPath
        if FileManager.default.fileExists(atPath: "\(currentDir)/web/index.html") {
            self.webDir = "\(currentDir)/web"
        } else if FileManager.default.fileExists(atPath: "\(currentDir)/tools/tracking-tester/web/index.html") {
            self.webDir = "\(currentDir)/tools/tracking-tester/web"
        } else {
            self.webDir = currentDir
        }
    }

    func start() async {
        print("Starting Tracking Tester Server on http://localhost:\(port)")
        print("Open in browser: http://localhost:\(port)")
        print("Web directory: \(webDir)")
        print("\nPress Ctrl+C to stop\n")

        // Create a simple TCP server
        let server = try! ServerSocket(port: port)

        while true {
            do {
                let client = try await server.accept()
                Task {
                    await self.handleClient(client)
                }
            } catch {
                print("Accept error: \(error)")
            }
        }
    }

    private func handleClient(_ client: ClientSocket) async {
        defer { client.close() }

        guard let request = client.readRequest() else { return }

        // Parse request
        let lines = request.split(separator: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return }

        let method = String(parts[0])
        let path = String(parts[1])

        print("Request: \(method) '\(path)'")
        fflush(stdout)

        // CORS headers for all responses
        let corsHeaders = """
        Access-Control-Allow-Origin: *
        Access-Control-Allow-Methods: GET, POST, OPTIONS
        Access-Control-Allow-Headers: Content-Type, Range
        Access-Control-Expose-Headers: Content-Range, Accept-Ranges, Content-Length
        """

        // Handle OPTIONS for CORS preflight
        if method == "OPTIONS" {
            let response = "HTTP/1.1 204 No Content\r\n\(corsHeaders)\r\n\r\n"
            client.write(response)
            return
        }

        // Route handling
        if method == "GET" && (path == "/" || path == "/index.html") {
            handleStaticFile(client: client, filePath: "\(webDir)/index.html", corsHeaders: corsHeaders)
        } else if method == "GET" && path == "/health" {
            let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}"
            client.write(response)
        } else if method == "GET" && path == "/progress" {
            let progressJson = "{\"progress\":\(currentProgress),\"analyzing\":\(isAnalyzing)}"
            let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n\(progressJson)"
            client.write(response)
        } else if method == "POST" && path == "/analyze" {
            await handleAnalyze(client: client, request: request, corsHeaders: corsHeaders)
        } else if method == "POST" && path == "/analyze-cached" {
            await handleAnalyzeCached(client: client, request: request, corsHeaders: corsHeaders)
        } else if method == "POST" && path == "/retrack" {
            await handleRetrack(client: client, request: request, corsHeaders: corsHeaders)
        } else if method == "POST" && path == "/retrack-sort" {
            await handleRetrackSORT(client: client, request: request, corsHeaders: corsHeaders)
        } else if (method == "GET" || method == "HEAD") && path.starts(with: "/video") {
            // Serve video file from local path
            if let range = path.range(of: "?path=") {
                let encodedPath = String(path[range.upperBound...])
                let videoPath = encodedPath.removingPercentEncoding ?? encodedPath
                print("Serving video (\(method)): '\(videoPath)'")
                fflush(stdout)
                handleVideoFile(client: client, request: request, filePath: videoPath, corsHeaders: corsHeaders, headOnly: method == "HEAD")
            } else {
                print("Video path missing query parameter")
                fflush(stdout)
                let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: text/plain\r\n\r\nMissing path parameter"
                client.write(response)
            }
        } else {
            print("404: method=\(method) path='\(path)'")
            fflush(stdout)
            let response = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)\r\nContent-Type: text/plain\r\n\r\nNot Found"
            client.write(response)
        }
    }

    private func handleStaticFile(client: ClientSocket, filePath: String, corsHeaders: String) {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = FileManager.default.contents(atPath: filePath),
              let content = String(data: data, encoding: .utf8) else {
            let response = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)\r\nContent-Type: text/plain\r\n\r\nFile not found"
            client.write(response)
            return
        }

        let contentType = filePath.hasSuffix(".html") ? "text/html" : "text/plain"
        let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)\r\nContent-Type: \(contentType); charset=utf-8\r\nContent-Length: \(data.count)\r\n\r\n\(content)"
        client.write(response)
    }

    private func handleVideoFile(client: ClientSocket, request: String, filePath: String, corsHeaders: String, headOnly: Bool = false) {
        let expandedPath = NSString(string: filePath).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            let response = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)\r\nContent-Type: text/plain\r\n\r\nVideo file not found: \(expandedPath)"
            client.write(response)
            return
        }

        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: expandedPath)[.size] as? UInt64) ?? 0

        // Determine content type
        let contentType: String
        if filePath.lowercased().hasSuffix(".mov") {
            contentType = "video/quicktime"
        } else if filePath.lowercased().hasSuffix(".mp4") {
            contentType = "video/mp4"
        } else {
            contentType = "video/mp4"
        }

        // Check for Range header
        var rangeStart: UInt64 = 0
        var rangeEnd: UInt64 = fileSize - 1
        var hasRangeHeader = false

        let requestLines = request.split(separator: "\r\n")
        for line in requestLines {
            if line.lowercased().hasPrefix("range:") {
                hasRangeHeader = true
                let rangeValue = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if rangeValue.hasPrefix("bytes=") {
                    let rangeSpec = String(rangeValue.dropFirst(6))
                    let rangeParts = rangeSpec.split(separator: "-")
                    if let start = UInt64(rangeParts[0]) {
                        rangeStart = start
                        if rangeParts.count > 1, !rangeParts[1].isEmpty, let end = UInt64(rangeParts[1]) {
                            rangeEnd = min(end, fileSize - 1)
                        }
                    }
                }
                break
            }
        }

        let contentLength = rangeEnd - rangeStart + 1
        let statusCode = hasRangeHeader ? "206 Partial Content" : "200 OK"
        let rangeHeader = "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(fileSize)"

        // For HEAD requests, just return headers
        if headOnly {
            let headers = """
            HTTP/1.1 \(statusCode)\r
            \(corsHeaders)\r
            Content-Type: \(contentType)\r
            Content-Length: \(contentLength)\r
            Accept-Ranges: bytes\r
            \(rangeHeader)\r
            \r

            """
            client.writeData(headers.data(using: .utf8)!)
            return
        }

        // For GET requests, open file and send data
        guard let fileHandle = FileHandle(forReadingAtPath: expandedPath) else {
            let response = "HTTP/1.1 500 Internal Server Error\r\n\(corsHeaders)\r\nContent-Type: text/plain\r\n\r\nCannot open file"
            client.write(response)
            return
        }
        defer { try? fileHandle.close() }

        // Seek to start position
        try? fileHandle.seek(toOffset: rangeStart)

        // Read the requested range (limit to 10MB chunks for streaming)
        let chunkSize = min(contentLength, 10 * 1024 * 1024)
        let data = fileHandle.readData(ofLength: Int(chunkSize))

        let actualRangeEnd = rangeStart + UInt64(data.count) - 1
        let actualRangeHeader = "Content-Range: bytes \(rangeStart)-\(actualRangeEnd)/\(fileSize)"

        let headers = """
        HTTP/1.1 \(statusCode)\r
        \(corsHeaders)\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Accept-Ranges: bytes\r
        \(actualRangeHeader)\r
        \r

        """

        client.writeData(headers.data(using: .utf8)!)
        client.writeData(data)
    }

    private func handleAnalyze(client: ClientSocket, request: String, corsHeaders: String) async {
        // Extract JSON body
        guard let bodyStart = request.range(of: "\r\n\r\n") else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"No body\"}"
            client.write(response)
            return
        }

        let body = String(request[bodyStart.upperBound...])

        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videoPath = json["videoPath"] as? String else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Invalid request\"}"
            client.write(response)
            return
        }

        let frameStride = json["stride"] as? Int ?? 1

        // Expand ~ in path
        let expandedPath = NSString(string: videoPath).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            let response = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Video file not found: \(expandedPath)\"}"
            client.write(response)
            return
        }

        print("Analyzing video: \(expandedPath) (stride: \(frameStride))")

        currentProgress = 0
        isAnalyzing = true

        do {
            let result = try await analyzer.analyzeVideo(at: expandedPath, frameStride: frameStride) { [self] progress in
                currentProgress = progress
                print("Progress: \(Int(progress * 100))%", terminator: "\r")
                fflush(stdout)
            }
            isAnalyzing = false
            currentProgress = 1.0
            print("\nAnalysis complete: \(result.frames.count) frames, \(result.frames.flatMap { $0.people }.count) total detections")

            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\n\r\n\(jsonString)"
            client.write(response)

        } catch {
            isAnalyzing = false
            print("Analysis error: \(error)")
            let response = "HTTP/1.1 500 Internal Server Error\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"\(error.localizedDescription)\"}"
            client.write(response)
        }
    }

    /// Extract detections and cache them, then run tracking
    private func handleAnalyzeCached(client: ClientSocket, request: String, corsHeaders: String) async {
        guard let bodyStart = request.range(of: "\r\n\r\n") else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"No body\"}"
            client.write(response)
            return
        }

        let body = String(request[bodyStart.upperBound...])

        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videoPath = json["videoPath"] as? String else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Invalid request\"}"
            client.write(response)
            return
        }

        let frameStride = json["stride"] as? Int ?? 1
        let expandedPath = NSString(string: videoPath).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            let response = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Video file not found\"}"
            client.write(response)
            return
        }

        print("Analyzing with cache: \(expandedPath) (stride: \(frameStride))")
        currentProgress = 0
        isAnalyzing = true

        do {
            // Step 1: Extract and cache detections (slow, but cached for future runs)
            let cache = try await analyzer.extractAndCacheDetections(at: expandedPath, frameStride: frameStride) { [self] progress in
                currentProgress = progress
                print("Detection progress: \(Int(progress * 100))%", terminator: "\r")
                fflush(stdout)
            }
            print("\nDetections cached: \(cache.frames.count) frames")

            // Step 2: Run tracking on cached detections (fast)
            let result = analyzer.runTrackingOnCache(cache)

            isAnalyzing = false
            currentProgress = 1.0
            print("Tracking complete: \(result.frames.flatMap { $0.people }.count) total detections")

            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(result)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

            let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\n\r\n\(jsonString)"
            client.write(response)

        } catch {
            isAnalyzing = false
            print("Analysis error: \(error)")
            let response = "HTTP/1.1 500 Internal Server Error\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"\(error.localizedDescription)\"}"
            client.write(response)
        }
    }

    /// Re-run tracking on already cached detections (instant)
    private func handleRetrack(client: ClientSocket, request: String, corsHeaders: String) async {
        guard let bodyStart = request.range(of: "\r\n\r\n") else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"No body\"}"
            client.write(response)
            return
        }

        let body = String(request[bodyStart.upperBound...])

        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videoPath = json["videoPath"] as? String else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Invalid request\"}"
            client.write(response)
            return
        }

        let frameStride = json["stride"] as? Int ?? 1
        let expandedPath = NSString(string: videoPath).expandingTildeInPath

        // Load cached detections
        let cacheManager = DetectionCacheManager()
        guard let cache = cacheManager.loadCache(for: expandedPath, stride: frameStride) else {
            let response = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"No cache found. Run /analyze-cached first.\"}"
            client.write(response)
            return
        }

        print("Re-tracking from cache: \(cache.frames.count) frames")

        // Run tracking (instant - no Vision calls)
        let result = analyzer.runTrackingOnCache(cache)
        print("Re-track complete: \(result.frames.flatMap { $0.people }.count) detections")

        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(result),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            let response = "HTTP/1.1 500 Internal Server Error\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Encoding failed\"}"
            client.write(response)
            return
        }

        let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\n\r\n\(jsonString)"
        client.write(response)
    }

    /// Re-run tracking using SORT (Kalman + Hungarian) on cached detections
    private func handleRetrackSORT(client: ClientSocket, request: String, corsHeaders: String) async {
        guard let bodyStart = request.range(of: "\r\n\r\n") else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"No body\"}"
            client.write(response)
            return
        }

        let body = String(request[bodyStart.upperBound...])

        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videoPath = json["videoPath"] as? String else {
            let response = "HTTP/1.1 400 Bad Request\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Invalid request\"}"
            client.write(response)
            return
        }

        let frameStride = json["stride"] as? Int ?? 1
        let expandedPath = NSString(string: videoPath).expandingTildeInPath

        let cacheManager = DetectionCacheManager()
        guard let cache = cacheManager.loadCache(for: expandedPath, stride: frameStride) else {
            let response = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"No cache found. Run /analyze-cached first.\"}"
            client.write(response)
            return
        }

        print("SORT re-tracking from cache: \(cache.frames.count) frames")

        let result = analyzer.runSORTTrackingOnCache(cache)
        print("SORT re-track complete: \(result.frames.flatMap { $0.people }.count) detections")

        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(result),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            let response = "HTTP/1.1 500 Internal Server Error\r\n\(corsHeaders)\r\nContent-Type: application/json\r\n\r\n{\"error\":\"Encoding failed\"}"
            client.write(response)
            return
        }

        let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\n\r\n\(jsonString)"
        client.write(response)
    }
}

// MARK: - Simple Socket Helpers

class ServerSocket {
    private var socket: Int32

    init(port: UInt16) throws {
        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw NSError(domain: "Socket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }

        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(socket)
            throw NSError(domain: "Socket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind to port \(port)"])
        }

        guard listen(socket, 10) == 0 else {
            Darwin.close(socket)
            throw NSError(domain: "Socket", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen"])
        }
    }

    func accept() async throws -> ClientSocket {
        var clientAddr = sockaddr_in()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.accept(socket, sockaddrPtr, &clientAddrLen)
            }
        }

        guard clientSocket >= 0 else {
            throw NSError(domain: "Socket", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to accept"])
        }

        return ClientSocket(socket: clientSocket)
    }
}

class ClientSocket {
    private let socket: Int32

    init(socket: Int32) {
        self.socket = socket
        // Prevent SIGPIPE on this socket
        var noSigPipe: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    }

    func readRequest() -> String? {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(socket, &buffer, buffer.count)
        guard bytesRead > 0 else { return nil }
        return String(bytes: buffer[0..<bytesRead], encoding: .utf8)
    }

    func write(_ string: String) {
        let data = Array(string.utf8)
        data.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            var totalWritten = 0
            while totalWritten < data.count {
                let written = Darwin.write(socket, baseAddress + totalWritten, data.count - totalWritten)
                if written <= 0 { break }
                totalWritten += written
            }
        }
    }

    func writeData(_ data: Data) {
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            var totalWritten = 0
            while totalWritten < data.count {
                let written = Darwin.write(socket, baseAddress + totalWritten, data.count - totalWritten)
                if written <= 0 { break }
                totalWritten += written
            }
        }
    }

    func close() {
        Darwin.close(socket)
    }
}

// MARK: - Main

// Ignore SIGPIPE to prevent crash when client disconnects during write
signal(SIGPIPE, SIG_IGN)

let server = HTTPServer(port: 8090)
await server.start()
