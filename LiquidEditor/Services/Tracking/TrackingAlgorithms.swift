//
//  TrackingAlgorithms.swift
//  LiquidEditor
//
//  Pure computation namespace for tracking post-processing algorithms.
//  Extracted from TrackingDataStore to adhere to SRP -- the data store
//  handles storage/coordination, while this enum contains the math.
//
//  All methods are static, pure functions with no mutable state.
//

import CoreGraphics
import CoreMedia
import Foundation

// MARK: - TrackingAlgorithms

/// Pure-computation namespace for tracking data post-processing algorithms.
///
/// Contains smoothing (Kalman forward, RTS backward, temporal bbox smoothing),
/// gap filling (autoregressive motion prediction), noise filtering,
/// spatial proximity merging, and interpolation.
///
/// All methods are static and take inputs/return outputs -- no side effects.
enum TrackingAlgorithms {

    // MARK: - Kalman Smoothing (Forward Pass)

    /// Apply Kalman smoothing to a single frame's tracking results.
    ///
    /// Updates per-person Kalman filters for bbox center and joint positions.
    /// Returns the smoothed result and updated filter/snapshot state.
    ///
    /// - Parameters:
    ///   - result: The raw tracking result for one frame.
    ///   - kalmanFilters: Per-person Kalman filters (mutated in place).
    ///   - jointKalmanFilters: Per-person per-joint Kalman filters (mutated in place).
    ///   - bboxKalmanSnapshots: Snapshot storage for RTS backward pass (mutated in place).
    ///   - jointKalmanSnapshots: Joint snapshot storage for RTS backward pass (mutated in place).
    /// - Returns: Smoothed `FrameTrackingResult`.
    static func applySmoothing(
        to result: FrameTrackingResult,
        kalmanFilters: inout [Int: KalmanFilter2D],
        jointKalmanFilters: inout [Int: [String: KalmanFilter2D]],
        bboxKalmanSnapshots: inout [Int: [(timestampMs: Int, snapshot: KalmanSnapshot)]],
        jointKalmanSnapshots: inout [Int: [String: [(timestampMs: Int, snapshot: KalmanSnapshot)]]]
    ) -> FrameTrackingResult {
        var smoothedPeople: [PersonTrackingResult] = []

        for person in result.people {
            guard let bbox = person.boundingBox else {
                smoothedPeople.append(person)
                continue
            }

            // Get or create Kalman filter for this person
            if kalmanFilters[person.personIndex] == nil {
                kalmanFilters[person.personIndex] = KalmanFilter2D()
            }

            let filter = kalmanFilters[person.personIndex]!

            // Smooth the center position and collect snapshot for RTS backward pass
            let center = CGPoint(x: bbox.x, y: bbox.y)
            let (smoothedCenter, bboxSnapshot) = filter.update(measurement: center, collectSnapshot: true)
            if let snapshot = bboxSnapshot {
                bboxKalmanSnapshots[person.personIndex, default: []].append(
                    (timestampMs: result.timestampMs, snapshot: snapshot)
                )
            }

            // Create smoothed bounding box
            let smoothedBbox = NormalizedBoundingBox(
                x: Double(smoothedCenter.x),
                y: Double(smoothedCenter.y),
                width: bbox.width,
                height: bbox.height
            )

            // Smooth pose joints with per-joint Kalman filters
            var smoothedPose: PoseJoints? = person.pose
            if let pose = person.pose {
                if jointKalmanFilters[person.personIndex] == nil {
                    jointKalmanFilters[person.personIndex] = [:]
                }

                var smoothedJoints: [String: CGPoint] = [:]
                if jointKalmanSnapshots[person.personIndex] == nil {
                    jointKalmanSnapshots[person.personIndex] = [:]
                }
                for (jointName, point) in pose.joints {
                    if jointKalmanFilters[person.personIndex]![jointName] == nil {
                        jointKalmanFilters[person.personIndex]![jointName] = KalmanFilter2D(
                            processNoise: 0.02,
                            measurementNoise: 0.08
                        )
                    }
                    let jointFilter = jointKalmanFilters[person.personIndex]![jointName]!
                    let (smoothedPoint, jointSnapshot) = jointFilter.update(
                        measurement: CGPoint(x: point.x, y: point.y),
                        collectSnapshot: true
                    )
                    smoothedJoints[jointName] = smoothedPoint
                    if let snapshot = jointSnapshot {
                        jointKalmanSnapshots[person.personIndex]![jointName, default: []].append(
                            (timestampMs: result.timestampMs, snapshot: snapshot)
                        )
                    }
                }
                smoothedPose = PoseJoints(joints: smoothedJoints)
            }

            smoothedPeople.append(person.with(
                boundingBox: smoothedBbox,
                pose: smoothedPose
            ))
        }

        return result.with(people: smoothedPeople)
    }

    // MARK: - RTS Backward Smoothing

    /// Apply Rauch-Tung-Striebel backward smoother to all stored tracking data.
    ///
    /// Replaces forward-only Kalman estimates with optimal bidirectional estimates,
    /// eliminating systematic lag during fast movements.
    ///
    /// - Parameters:
    ///   - frameResults: All frame results (mutated in place).
    ///   - bboxKalmanSnapshots: Bbox Kalman snapshots (consumed and cleared).
    ///   - jointKalmanSnapshots: Joint Kalman snapshots (consumed and cleared).
    ///   - fps: Video frame rate for dt calculation.
    static func applyRTSSmoothing(
        frameResults: inout [Int: FrameTrackingResult],
        bboxKalmanSnapshots: inout [Int: [(timestampMs: Int, snapshot: KalmanSnapshot)]],
        jointKalmanSnapshots: inout [Int: [String: [(timestampMs: Int, snapshot: KalmanSnapshot)]]],
        fps: Double = 30.0
    ) {
        let dt = 1.0 / fps

        // Phase 1: Smooth bbox center positions
        for (personIndex, snapshots) in bboxKalmanSnapshots {
            guard snapshots.count > 1 else { continue }
            let smoothedPositions = KalmanFilter2D.rtsSmooth(
                snapshots: snapshots.map(\.snapshot), dt: dt
            )
            for (i, (timestampMs, _)) in snapshots.enumerated() {
                guard let frame = frameResults[timestampMs] else { continue }
                let updatedPeople = frame.people.map { person -> PersonTrackingResult in
                    guard person.personIndex == personIndex,
                          let bbox = person.boundingBox else { return person }
                    let smoothedBbox = NormalizedBoundingBox(
                        x: smoothedPositions[i].x,
                        y: smoothedPositions[i].y,
                        width: bbox.width,
                        height: bbox.height
                    )
                    return person.with(boundingBox: smoothedBbox)
                }
                frameResults[timestampMs] = frame.with(people: updatedPeople)
            }
        }

        // Phase 2: Smooth per-joint positions
        for (personIndex, jointSnapshotsByName) in jointKalmanSnapshots {
            for (jointName, snapshots) in jointSnapshotsByName {
                guard snapshots.count > 1 else { continue }
                let smoothedPositions = KalmanFilter2D.rtsSmooth(
                    snapshots: snapshots.map(\.snapshot), dt: dt
                )
                for (i, (timestampMs, _)) in snapshots.enumerated() {
                    guard let frame = frameResults[timestampMs] else { continue }
                    let updatedPeople = frame.people.map { person -> PersonTrackingResult in
                        guard person.personIndex == personIndex,
                              let pose = person.pose else { return person }
                        var updatedJoints: [String: CGPoint] = [:]
                        for (name, point) in pose.joints {
                            if name == jointName {
                                updatedJoints[name] = CGPoint(
                                    x: smoothedPositions[i].x,
                                    y: smoothedPositions[i].y
                                )
                            } else {
                                updatedJoints[name] = CGPoint(x: point.x, y: point.y)
                            }
                        }
                        return person.with(pose: PoseJoints(joints: updatedJoints))
                    }
                    frameResults[timestampMs] = frame.with(people: updatedPeople)
                }
            }
        }

        // Phase 3: Free snapshot storage
        bboxKalmanSnapshots.removeAll()
        jointKalmanSnapshots.removeAll()
    }

    // MARK: - Gap Filling

    /// Fill tracking gaps using autoregressive motion prediction.
    ///
    /// - Parameters:
    ///   - allResults: All frame results in chronological order.
    ///   - maxGapFrames: Maximum gap length to fill.
    ///   - personIdentifications: Identification data per person.
    /// - Returns: Tuple of (updated frame results keyed by timestampMs, gaps filled count).
    static func fillTrackingGaps(
        allResults: [FrameTrackingResult],
        maxGapFrames: Int = 5,
        personIdentifications: [Int: (personId: String?, personName: String?, confidence: Double?)]
    ) -> (updatedFrames: [Int: FrameTrackingResult], gapsFilled: Int) {
        guard !allResults.isEmpty else { return ([:], 0) }

        var updatedFrames: [Int: FrameTrackingResult] = [:]
        var gapsFilled = 0

        // Get all unique person IDs
        var allPersonIDs = Set<Int>()
        for frame in allResults {
            for person in frame.people {
                allPersonIDs.insert(person.personIndex)
            }
        }

        // For each person, find and fill gaps
        for personID in allPersonIDs {
            var lastSeenIndex: Int?

            for (index, _) in allResults.enumerated() {
                let hasPersonNow = allResults[index].people.contains { $0.personIndex == personID }

                if hasPersonNow {
                    if let lastIndex = lastSeenIndex {
                        let gapLength = index - lastIndex - 1
                        if gapLength > 0 && gapLength <= maxGapFrames {
                            let filled = fillGap(
                                in: allResults,
                                personID: personID,
                                fromIndex: lastIndex,
                                toIndex: index,
                                personIdentifications: personIdentifications,
                                updatedFrames: &updatedFrames
                            )
                            gapsFilled += filled
                        }
                    }
                    lastSeenIndex = index
                }
            }
        }

        return (updatedFrames, gapsFilled)
    }

    /// Predict and fill frames in a gap using autoregressive motion model.
    private static func fillGap(
        in allResults: [FrameTrackingResult],
        personID: Int,
        fromIndex: Int,
        toIndex: Int,
        personIdentifications: [Int: (personId: String?, personName: String?, confidence: Double?)],
        updatedFrames: inout [Int: FrameTrackingResult]
    ) -> Int {
        let gapLength = toIndex - fromIndex - 1
        guard gapLength > 0 else { return 0 }

        // Get motion history before gap (last 5 frames)
        let historyStart = max(0, fromIndex - 5)
        let historyFrames = Array(allResults[historyStart...fromIndex])

        // Extract positions for velocity calculation
        var positions: [(x: Double, y: Double)] = []
        for frame in historyFrames {
            guard let person = frame.people.first(where: { $0.personIndex == personID }),
                  let bbox = person.boundingBox else { continue }
            positions.append((x: bbox.x + bbox.width / 2, y: bbox.y + bbox.height / 2))
        }

        guard positions.count >= 2 else { return 0 }

        // Calculate weighted average velocity (recent frames weighted more)
        var velocityX: Double = 0
        var velocityY: Double = 0
        var totalWeight: Double = 0

        for i in 1..<positions.count {
            let weight = Double(i)
            velocityX += (positions[i].x - positions[i - 1].x) * weight
            velocityY += (positions[i].y - positions[i - 1].y) * weight
            totalWeight += weight
        }

        velocityX /= totalWeight
        velocityY /= totalWeight

        guard let lastSeenPerson = allResults[fromIndex].people.first(where: { $0.personIndex == personID }),
              let lastBbox = lastSeenPerson.boundingBox else { return 0 }

        let avgWidth = lastBbox.width
        let avgHeight = lastBbox.height

        // Get pose from both boundary frames for interpolation
        let fromPose = lastSeenPerson.pose
        let toPerson = allResults[toIndex].people.first(where: { $0.personIndex == personID })
        let toPose = toPerson?.pose

        // Fill each frame in the gap
        var filledCount = 0
        for i in 1...gapLength {
            let frameIndex = fromIndex + i
            guard let lastPos = positions.last else { return 0 }

            let t = Double(i) / Double(gapLength + 1)

            let predictedCenterX = lastPos.x + velocityX * Double(i)
            let predictedCenterY = lastPos.y + velocityY * Double(i)

            let predictedBbox = NormalizedBoundingBox(
                x: predictedCenterX - avgWidth / 2,
                y: predictedCenterY - avgHeight / 2,
                width: avgWidth,
                height: avgHeight
            )

            // Interpolate pose joints between boundary frames
            var interpolatedPose: PoseJoints?
            if let poseA = fromPose, let poseB = toPose {
                var joints: [String: CGPoint] = [:]
                for (jointName, pointA) in poseA.joints {
                    if let pointB = poseB.joints[jointName] {
                        joints[jointName] = CGPoint(
                            x: lerp(pointA.x, pointB.x, CGFloat(t)),
                            y: lerp(pointA.y, pointB.y, CGFloat(t))
                        )
                    }
                }
                if !joints.isEmpty {
                    interpolatedPose = PoseJoints(joints: joints)
                }
            }

            // Preserve identification from last seen person or stored identification
            let identification = personIdentifications[personID]
            let predictedPerson = PersonTrackingResult(
                personIndex: personID,
                confidence: 0.6,
                boundingBox: predictedBbox,
                bodyOutline: nil,
                pose: interpolatedPose,
                timestampMs: allResults[frameIndex].timestampMs,
                identifiedPersonId: lastSeenPerson.identifiedPersonId ?? identification?.personId,
                identifiedPersonName: lastSeenPerson.identifiedPersonName ?? identification?.personName,
                identificationConfidence: lastSeenPerson.identificationConfidence ?? identification?.confidence
            )

            var updatedPeople = allResults[frameIndex].people
            updatedPeople.append(predictedPerson)

            let updatedFrame = FrameTrackingResult(
                timestampMs: allResults[frameIndex].timestampMs,
                people: updatedPeople
            )

            updatedFrames[updatedFrame.timestampMs] = updatedFrame
            filledCount += 1
        }

        return filledCount
    }

    // MARK: - Temporal BBox Smoothing

    /// Smooth bounding box sizes using bidirectional running average with hard minimum floors.
    ///
    /// - Parameter allResults: All frame results in chronological order.
    /// - Returns: Array of smoothed frame results.
    static func smoothBoundingBoxes(allResults: [FrameTrackingResult]) -> [FrameTrackingResult] {
        guard !allResults.isEmpty else { return [] }

        let smoothingAlpha = 0.1
        let minRatio = 0.55
        let hardMinWidth = 0.04
        let hardMinHeight = 0.12

        // Phase 1: Compute per-person median sizes
        var personWidths: [Int: [Double]] = [:]
        var personHeights: [Int: [Double]] = [:]
        for frame in allResults {
            for person in frame.people {
                guard let bbox = person.boundingBox else { continue }
                personWidths[person.personIndex, default: []].append(bbox.width)
                personHeights[person.personIndex, default: []].append(bbox.height)
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

        // Build per-person frame index lists
        var personFrames: [Int: [(frameIdx: Int, width: Double, height: Double)]] = [:]
        for (frameIdx, frame) in allResults.enumerated() {
            for person in frame.people {
                guard let bbox = person.boundingBox else { continue }
                personFrames[person.personIndex, default: []].append(
                    (frameIdx: frameIdx, width: bbox.width, height: bbox.height)
                )
            }
        }

        // Phase 2: Forward and backward smoothed sizes
        var smoothedSizes: [Int: [Int: (w: Double, h: Double)]] = [:]

        for (pid, frames) in personFrames {
            guard !frames.isEmpty else { continue }
            let seed = (w: medianWidth[pid] ?? frames[0].width,
                        h: medianHeight[pid] ?? frames[0].height)

            // Forward pass
            var forwardResults: [(w: Double, h: Double)] = []
            var runW = seed.w
            var runH = seed.h
            for (i, f) in frames.enumerated() {
                if i < 5 {
                    runW = (runW * Double(i) + f.width) / Double(i + 1)
                    runH = (runH * Double(i) + f.height) / Double(i + 1)
                } else {
                    runW = runW * (1 - smoothingAlpha) + f.width * smoothingAlpha
                    runH = runH * (1 - smoothingAlpha) + f.height * smoothingAlpha
                }
                forwardResults.append((w: runW, h: runH))
            }

            // Backward pass
            var backwardResults: [(w: Double, h: Double)] = Array(repeating: (0, 0), count: frames.count)
            runW = seed.w
            runH = seed.h
            for i in stride(from: frames.count - 1, through: 0, by: -1) {
                let f = frames[i]
                let remaining = frames.count - 1 - i
                if remaining < 5 {
                    runW = (runW * Double(remaining) + f.width) / Double(remaining + 1)
                    runH = (runH * Double(remaining) + f.height) / Double(remaining + 1)
                } else {
                    runW = runW * (1 - smoothingAlpha) + f.width * smoothingAlpha
                    runH = runH * (1 - smoothingAlpha) + f.height * smoothingAlpha
                }
                backwardResults[i] = (w: runW, h: runH)
            }

            // Merge: average forward and backward
            var merged: [Int: (w: Double, h: Double)] = [:]
            for (i, f) in frames.enumerated() {
                let avgW = (forwardResults[i].w + backwardResults[i].w) / 2.0
                let avgH = (forwardResults[i].h + backwardResults[i].h) / 2.0
                merged[f.frameIdx] = (w: avgW, h: avgH)
            }
            smoothedSizes[pid] = merged
        }

        // Phase 3: Apply smoothed sizes with floor enforcement and clamping
        var smoothedResults: [FrameTrackingResult] = []
        for (frameIdx, frame) in allResults.enumerated() {
            var smoothedPeople: [PersonTrackingResult] = []
            for person in frame.people {
                guard let bbox = person.boundingBox else {
                    smoothedPeople.append(person)
                    continue
                }
                let pid = person.personIndex

                var newW: Double
                var newH: Double

                if let sizes = smoothedSizes[pid]?[frameIdx] {
                    newW = sizes.w
                    newH = sizes.h

                    let rawW = bbox.width
                    let rawH = bbox.height
                    if rawW < newW * minRatio { newW = max(rawW, newW * minRatio) }
                    if rawH < newH * minRatio { newH = max(rawH, newH * minRatio) }
                } else {
                    newW = bbox.width
                    newH = bbox.height
                }

                if newW < hardMinWidth { newW = hardMinWidth }
                if newH < hardMinHeight { newH = hardMinHeight }

                let clampedW = min(newW, 1.0)
                let clampedH = min(newH, 1.0)
                let clampedX = max(clampedW / 2, min(bbox.x, 1.0 - clampedW / 2))
                let clampedY = max(clampedH / 2, min(bbox.y, 1.0 - clampedH / 2))

                let smoothedBbox = NormalizedBoundingBox(
                    x: clampedX,
                    y: clampedY,
                    width: clampedW,
                    height: clampedH
                )

                smoothedPeople.append(person.with(boundingBox: smoothedBbox))
            }
            smoothedResults.append(frame.with(people: smoothedPeople))
        }

        return smoothedResults
    }

    // MARK: - Noise Track Filtering

    /// Identify tracks to remove and compute contiguous ID remapping.
    ///
    /// - Parameters:
    ///   - allResults: All frame results.
    ///   - minDurationSeconds: Minimum track duration to keep.
    ///   - fps: Video frame rate.
    /// - Returns: Tuple of (tracks to remove, contiguous ID remap) or nil if nothing to remove.
    static func computeNoiseTrackFilter(
        allResults: [FrameTrackingResult],
        minDurationSeconds: Double = 1.0,
        fps: Double = 30.0
    ) -> (tracksToRemove: Set<Int>, remapToContiguous: [Int: Int])? {
        guard !allResults.isEmpty else { return nil }

        var trackFrameCounts: [Int: Int] = [:]
        for frame in allResults {
            for person in frame.people {
                trackFrameCounts[person.personIndex, default: 0] += 1
            }
        }

        let minFrames = max(15, Int(fps * minDurationSeconds))
        let tracksToRemove = Set(trackFrameCounts.filter { $0.value < minFrames }.map { $0.key })

        guard !tracksToRemove.isEmpty else { return nil }

        let validIds = trackFrameCounts.keys.filter { !tracksToRemove.contains($0) }.sorted()
        var remapToContiguous: [Int: Int] = [:]
        for (newIdx, oldId) in validIds.enumerated() {
            remapToContiguous[oldId] = newIdx
        }

        return (tracksToRemove, remapToContiguous)
    }

    /// Apply noise track filter to results, returning filtered results.
    static func applyNoiseTrackFilter(
        allResults: [FrameTrackingResult],
        tracksToRemove: Set<Int>,
        remapToContiguous: [Int: Int]
    ) -> [FrameTrackingResult] {
        allResults.map { frame in
            let filteredPeople = frame.people
                .filter { !tracksToRemove.contains($0.personIndex) }
                .map { person in
                    person.with(personIndex: remapToContiguous[person.personIndex] ?? person.personIndex)
                }
            return frame.with(people: filteredPeople)
        }
    }

    // MARK: - Spatial/Temporal Track Merging

    /// Compute merge mapping for fragmented tracks using spatial proximity and bbox similarity.
    ///
    /// - Parameter allResults: All frame results.
    /// - Returns: Tuple of (merge map, contiguous ID remap) or nil if no merging needed.
    static func computeTrackMergeMapping(
        allResults: [FrameTrackingResult]
    ) -> (mergeMap: [Int: Int], remapToContiguous: [Int: Int])? {
        guard !allResults.isEmpty else { return nil }

        struct TrackInfo {
            var firstFrameIdx: Int
            var lastFrameIdx: Int
            var firstPosition: CGPoint
            var lastPosition: CGPoint
            var avgBBoxWidth: Double
            var avgBBoxHeight: Double
            var frameCount: Int
            var frameIndices: Set<Int>
        }

        var trackInfos: [Int: TrackInfo] = [:]

        for (frameIdx, frame) in allResults.enumerated() {
            for person in frame.people {
                guard let bbox = person.boundingBox else { continue }
                let center = CGPoint(x: bbox.x, y: bbox.y)
                if var info = trackInfos[person.personIndex] {
                    info.lastFrameIdx = frameIdx
                    info.lastPosition = center
                    let n = Double(info.frameCount)
                    info.avgBBoxWidth = (info.avgBBoxWidth * n + bbox.width) / (n + 1)
                    info.avgBBoxHeight = (info.avgBBoxHeight * n + bbox.height) / (n + 1)
                    info.frameCount += 1
                    info.frameIndices.insert(frameIdx)
                    trackInfos[person.personIndex] = info
                } else {
                    trackInfos[person.personIndex] = TrackInfo(
                        firstFrameIdx: frameIdx,
                        lastFrameIdx: frameIdx,
                        firstPosition: center,
                        lastPosition: center,
                        avgBBoxWidth: bbox.width,
                        avgBBoxHeight: bbox.height,
                        frameCount: 1,
                        frameIndices: [frameIdx]
                    )
                }
            }
        }

        let allTrackIds = trackInfos.keys.sorted()
        guard allTrackIds.count > 1 else { return nil }

        var mergeMap: [Int: Int] = [:]

        let sortedByLength = allTrackIds.sorted { trackInfos[$0]!.frameCount > trackInfos[$1]!.frameCount }

        for i in 0..<sortedByLength.count {
            let candidateId = sortedByLength[i]
            guard mergeMap[candidateId] == nil else { continue }
            let candidateInfo = trackInfos[candidateId]!

            var bestMergeTarget: Int?
            var bestMergeScore: Double = Double.infinity

            for j in 0..<sortedByLength.count {
                if i == j { continue }
                let targetId = sortedByLength[j]

                var resolvedId = targetId
                var visited: Set<Int> = []
                while let next = mergeMap[resolvedId], !visited.contains(next) {
                    visited.insert(resolvedId)
                    resolvedId = next
                }
                if resolvedId == candidateId { continue }

                let targetInfo = trackInfos[targetId]!

                let overlapCount = candidateInfo.frameIndices.intersection(targetInfo.frameIndices).count
                let overlapRatio = Double(overlapCount) / Double(min(candidateInfo.frameCount, targetInfo.frameCount))
                if overlapRatio > 0.1 { continue }

                let (earlier, later): (TrackInfo, TrackInfo)
                if candidateInfo.firstFrameIdx <= targetInfo.firstFrameIdx {
                    earlier = candidateInfo
                    later = targetInfo
                } else {
                    earlier = targetInfo
                    later = candidateInfo
                }

                let gapFrames = later.firstFrameIdx - earlier.lastFrameIdx
                if gapFrames < -5 { continue }

                let boundaryDist = hypot(
                    earlier.lastPosition.x - later.firstPosition.x,
                    earlier.lastPosition.y - later.firstPosition.y
                )
                let earlierDiag = hypot(earlier.avgBBoxWidth, earlier.avgBBoxHeight)
                let laterDiag = hypot(later.avgBBoxWidth, later.avgBBoxHeight)
                let avgDiag = (earlierDiag + laterDiag) / 2
                let normalizedDist = Double(boundaryDist) / max(avgDiag, 0.01)

                let areaEarlier = earlier.avgBBoxWidth * earlier.avgBBoxHeight
                let areaLater = later.avgBBoxWidth * later.avgBBoxHeight
                let sizeRatio = min(areaEarlier, areaLater) / max(areaEarlier, areaLater)
                if sizeRatio < 0.33 { continue }

                let maxNormalizedDist = 2.5 - Double(max(0, gapFrames)) * 0.005
                if normalizedDist > max(maxNormalizedDist, 0.5) { continue }

                let distScore = normalizedDist / 2.5
                let sizeScore = 1.0 - sizeRatio
                let gapScore = Double(max(0, gapFrames)) / 300.0
                let score = distScore * 0.5 + sizeScore * 0.2 + gapScore * 0.3

                if score < bestMergeScore {
                    bestMergeScore = score
                    bestMergeTarget = resolvedId
                }
            }

            if let target = bestMergeTarget {
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

        guard !mergeMap.isEmpty else { return nil }

        let finalIds = Set(allTrackIds.map { mergeMap[$0] ?? $0 }).sorted()
        var remapToContiguous: [Int: Int] = [:]
        for (newIdx, oldId) in finalIds.enumerated() {
            remapToContiguous[oldId] = newIdx
        }

        return (mergeMap, remapToContiguous)
    }

    /// Apply merge mapping to results, returning merged results.
    static func applyTrackMerge(
        allResults: [FrameTrackingResult],
        mergeMap: [Int: Int],
        remapToContiguous: [Int: Int]
    ) -> [FrameTrackingResult] {
        allResults.map { frame in
            let remappedPeople = frame.people.map { person in
                let mergedId = mergeMap[person.personIndex] ?? person.personIndex
                let finalId = remapToContiguous[mergedId] ?? mergedId
                return person.with(personIndex: finalId)
            }
            return frame.with(people: remappedPeople)
        }
    }

    // MARK: - Interpolation

    /// Interpolate between two tracking results at parameter t (0..1).
    static func interpolateResults(
        from a: FrameTrackingResult,
        to b: FrameTrackingResult,
        t: Double,
        at timestampMs: Int
    ) -> FrameTrackingResult {
        var interpolatedPeople: [PersonTrackingResult] = []

        for personA in a.people {
            guard let personB = b.people.first(where: { $0.personIndex == personA.personIndex }) else {
                continue
            }
            let interpolatedPerson = interpolatePerson(from: personA, to: personB, t: t, at: timestampMs)
            interpolatedPeople.append(interpolatedPerson)
        }

        return FrameTrackingResult(timestampMs: timestampMs, people: interpolatedPeople)
    }

    /// Interpolate a single person's tracking data.
    static func interpolatePerson(
        from a: PersonTrackingResult,
        to b: PersonTrackingResult,
        t: Double,
        at timestampMs: Int
    ) -> PersonTrackingResult {
        // Interpolate bounding box
        var interpolatedBbox: NormalizedBoundingBox?
        if let bboxA = a.boundingBox, let bboxB = b.boundingBox {
            interpolatedBbox = NormalizedBoundingBox(
                x: lerp(bboxA.x, bboxB.x, t),
                y: lerp(bboxA.y, bboxB.y, t),
                width: lerp(bboxA.width, bboxB.width, t),
                height: lerp(bboxA.height, bboxB.height, t)
            )
        }

        // Interpolate outline (use closest)
        let outline = t < 0.5 ? a.bodyOutline : b.bodyOutline

        // Interpolate pose joints
        var interpolatedPose: PoseJoints?
        if let poseA = a.pose, let poseB = b.pose {
            var joints: [String: CGPoint] = [:]
            for (jointName, pointA) in poseA.joints {
                if let pointB = poseB.joints[jointName] {
                    joints[jointName] = CGPoint(
                        x: lerp(pointA.x, pointB.x, CGFloat(t)),
                        y: lerp(pointA.y, pointB.y, CGFloat(t))
                    )
                }
            }
            interpolatedPose = PoseJoints(joints: joints)
        }

        // Interpolate confidence
        let confidence = lerp(a.confidence, b.confidence, t)

        return PersonTrackingResult(
            personIndex: a.personIndex,
            confidence: confidence,
            boundingBox: interpolatedBbox,
            bodyOutline: outline,
            pose: interpolatedPose,
            timestampMs: timestampMs,
            identifiedPersonId: a.identifiedPersonId ?? b.identifiedPersonId,
            identifiedPersonName: a.identifiedPersonName ?? b.identifiedPersonName,
            identificationConfidence: a.identificationConfidence ?? b.identificationConfidence
        )
    }

    // MARK: - Lerp Helpers

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
